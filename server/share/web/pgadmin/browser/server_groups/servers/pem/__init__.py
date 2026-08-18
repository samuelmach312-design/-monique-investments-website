##########################################################################
#
# Postgres Enterprise Manager
#
# Copyright (C) 2016 - 2025, EnterpriseDB Corporation. All rights reserved.
#
##########################################################################

import json
import re
from collections import OrderedDict
from psycopg import OperationalError
import pgadmin.browser.server_groups as sg
from flask import render_template, request, make_response, jsonify, \
    current_app, url_for, session
from flask_babel import gettext
from flask_security import current_user
from pgadmin.user_login_check import pga_login_required
from psycopg.conninfo import make_conninfo, conninfo_to_dict
from pgadmin.browser.server_groups.servers.types import ServerType
from pgadmin.browser.server_groups.servers.utils import (
    convert_connection_parameter)
from pgadmin.browser.utils import PGChildNodeView
from pgadmin.utils.ajax import make_json_response, bad_request, forbidden, \
    make_response as ajax_response, internal_server_error, unauthorized, \
    gone, precondition_required
from pgadmin.utils.crypto import encrypt, decrypt, pqencryptpassword
from pgadmin.utils.menu import MenuItem
from pgadmin.pem import _pem, pem_connection
from pgadmin.pem.utils import is_edb_server
from pgadmin.tools.sqleditor.utils.query_history import QueryHistory

import config
from config import PG_DEFAULT_DRIVER, ALLOW_SAVE_PASSWORD, \
    ALLOW_SAVE_TUNNEL_PASSWORD
from pgadmin.model import db, Server, ServerGroup, User
from pgadmin.utils.driver import get_driver
from pgadmin.utils.master_password import get_crypt_key
from pgadmin.utils.exception import CryptKeyMissing
from pgadmin.utils.constants import UNAUTH_REQ, MIMETYPE_APP_JS, \
    SERVER_CONNECTION_CLOSED
from sqlalchemy import or_
from pgadmin.utils.preferences import Preferences
from pgadmin.utils.constants import KEY_RING_SERVICE_NAME, \
    KEY_RING_USERNAME_FORMAT, KEY_RING_TUNNEL_FORMAT, UNAUTH_REQ, \
    MIMETYPE_APP_JS, SERVER_CONNECTION_CLOSED
from pgadmin import socketio as sio
import keyring
from ..utils import is_valid_ipaddress, get_replication_type, is_valid_hostname
from .utils import \
    get_sql_profiler_version, \
    is_edb_wait_events_loaded, serverRegistrationRole, \
    fetch_message_from_exception, validate_server_request, store_password, \
    update_server, create_server
from pgadmin.pem.utils.role import RoleRequired
from pgadmin.settings.utils import with_object_filters

SERVER_NOT_FOUND_ERROR = gettext("Could not find the server information or "
                                 "current user don't have permission to "
                                 "access this server.")


def has_any(data, keys):
    """
    Checks any one of the keys present in the data given
    """
    if data is None and not isinstance(data, dict):
        return False

    if keys is None and not isinstance(keys, list):
        return False

    for key in keys:
        if key in data:
            return True

    return False


def has_patroni_config(server):
    return bool(
        server.get('replication_solution') == 'patroni' and
        server.get('patroni_cluster_name') and
        server.get('patroni_installation_path') and
        server.get('patroni_config_path')
    )


def server_icon_and_background(is_connected, manager, server):
    """

    Args:
        is_connected: Flag to check if server is connected
        manager: Connection manager
        server: Sever object

    Returns:
        Server Icon CSS class
    """
    server_background_color = ''
    if server and server['bgcolor']:
        server_background_color = ' {0}'.format(
            server['bgcolor']
        )
        # If user has set font color also
        if server['fgcolor']:
            server_background_color = '{0} {1}'.format(
                server_background_color,
                server['fgcolor']
            )

    if is_connected:
        return 'icon-{0}{1}'.format(
            manager.server_type, server_background_color
        )
    else:
        return 'icon-server-not-connected{0}'.format(
            server_background_color
        )


def recovery_state(connection, postgres_version):
    recovery_check_sql = render_template(
        "connect/sql/#{0}#/check_recovery.sql".format(postgres_version))

    status, result = connection.execute_dict(recovery_check_sql)
    if status and 'rows' in result and len(result['rows']) > 0:
        in_recovery = result['rows'][0]['inrecovery']
        wal_paused = result['rows'][0]['isreplaypaused']
    else:
        in_recovery = None
        wal_paused = None
    return status, result, in_recovery, wal_paused


class PEMServerModule(sg.ServerGroupPluginModule):
    _NODE_TYPE = "server"
    LABEL = gettext("Servers")

    @property
    def node_type(self):
        return self._NODE_TYPE

    @property
    def script_load(self):
        """
        Load the module script for server, when any of the server-group node is
        initialized.
        """
        return sg.ServerGroupModule.node_type

    def has_tag(self, server, object_filters):
        try:
            # No tags filter, show all
            if len(object_filters['tags']) == 0:
                return True

            # No tags on server, don't show
            if server.get('tags') is None or len(server.get('tags')) == 0:
                return False
            # Check if any of the tag exists
            return any([t['text'] in object_filters['tags']
                        for t in server.get('tags')])
        except Exception as _:
            return True

    @with_object_filters
    @pga_login_required
    @pem_connection
    def get_nodes(self, gid, object_filters, pem_conn=None, clid=None):
        """Return a JSON document listing the server groups for the user"""

        sql = render_template(
            "/".join(['servers/sql', 'node.sql']),
            sgid=clid if clid is not None else gid,
            schema_version=current_user.schema_version
        )
        status, servers = pem_conn.execute_dict(sql)
        if not status:
            current_app.logger.error(servers)
            return internal_server_error(errormsg=servers)
        else:
            driver = get_driver(PG_DEFAULT_DRIVER)

        for server in servers['rows']:
            connected = False
            manager = None
            errmsg = None
            was_connected = False
            in_recovery = None
            wal_paused = None
            user_info = None
            sql_profiler_version = None
            edb_wait_events_loaded = False

            server['tags'] = json.loads(server['tags']) if (
                server.get('tags')) else []

            if not self.has_tag(server, object_filters):
                continue

            post_connection_sql = server.get('post_connection_sql')
            try:
                manager = driver.connection_manager(server['id'])
                conn = manager.connection()
                was_connected = conn.wasConnected
                connected = conn.connected()
                if connected:
                    sql_profiler_version = get_sql_profiler_version(manager)
                    server_type = manager.server_type
                    user_info = manager.user_info
                    edb_wait_events_loaded = is_edb_wait_events_loaded(manager)
            except CryptKeyMissing:
                # show the nodes at least even if not able to connect.
                pass
            except Exception as e:
                current_app.logger.exception(e)
                errmsg = str(e)

            yield self.generate_browser_node(
                "%d" % (server['id']),
                clid if clid is not None else gid,
                server['name'],
                server_icon_and_background(connected, manager, server),
                True,
                self.node_type,
                connected=connected,
                server_type='ppas' if is_edb_server(
                    pem_conn, server['id']) else "pg",
                version=manager.version if manager else None,
                db=manager.db if manager else None,
                user=user_info,
                in_recovery=in_recovery,
                wal_pause=wal_paused,
                host=server['host'],
                port=server['port'],
                was_connected=was_connected,
                errmsg=errmsg,
                sql_profiler_version=sql_profiler_version,
                is_efm_enabled=not not (server['efm_cluster_name'] and
                                        server['efm_installation_path']),
                is_patroni_enabled=has_patroni_config(server),
                patroni_cluster_name=server.get('patroni_cluster_name'),
                is_password_saved=server['is_password_saved'],
                is_tunnel_password_saved=server[
                    'is_tunnel_password_saved'],
                is_agent_binded=server['is_agent_binded'],
                description=server['description'],
                edb_wait_events_loaded=edb_wait_events_loaded,
                tags=server['tags'],
                post_connection_sql=post_connection_sql,
                profile_id=server['profile_id'],
                profile_name=server['profile_name']
            )

    @property
    def jssnippets(self):
        return []

    @property
    def csssnippets(self):
        """
        Returns a snippet of css to include in the page
        """
        snippets = [render_template("css/servers.css")]

        for submodule in self.submodules:
            snippets.extend(submodule.csssnippets)

        for st in ServerType.types():
            snippets.extend(st.csssnippets)

        return snippets

    def register(self, app, options):
        """
        Override the default register function to automagically register
        sub-modules at once.
        """
        driver = get_driver(PG_DEFAULT_DRIVER, app)
        app.jinja_env.filters['qtLiteral'] = driver.qtLiteral
        app.jinja_env.filters['qtIdent'] = driver.qtIdent
        app.jinja_env.filters['qtTypeIdent'] = driver.qtTypeIdent
        app.jinja_env.filters['hasAny'] = has_any

        from ..ppas import PPAS

        from ..databases import blueprint as module
        self.submodules.append(module)

        from ..pgagent import blueprint as module
        self.submodules.append(module)

        from ..resource_groups import blueprint as module
        self.submodules.append(module)

        from ..roles import blueprint as module
        self.submodules.append(module)

        from ..tablespaces import blueprint as module
        self.submodules.append(module)

        from ..replica_nodes import blueprint as module
        self.submodules.append(module)

        from ..pgd_replication_groups import blueprint as module
        self.submodules.append(module)

        from ..directories import blueprint as module
        self.submodules.append(module)

        super().register(app, options)

    # We do not have any preferences for server node.
    def register_preferences(self):
        """
        register_preferences
        Override it so that - it does not register the show_node preference for
        server type.
        """
        ServerType.register_preferences()

    def get_exposed_url_endpoints(self):
        return ['NODE-server.connect_id']


class PEMServerMenuItem(MenuItem):
    def __init__(self, **kwargs):
        kwargs.setdefault("type", PEMServerModule.node_type)
        super().__init__(**kwargs)


class PEMServerNode(PGChildNodeView):
    node_type = PEMServerModule._NODE_TYPE
    node_label = "Server"

    parent_ids = [{'type': 'int', 'id': 'gid'}]
    ids = [{'type': 'int', 'id': 'sid'}]
    operations = dict({
        'obj': [
            {'get': 'properties', 'delete': 'delete', 'put': 'update'},
            {'get': 'list', 'post': 'create'}
        ],
        'nodes': [{'get': 'node'}, {'get': 'nodes'}],
        'sql': [{'get': 'sql'}],
        'msql': [{'get': 'modified_sql'}],
        'stats': [{'get': 'statistics'}],
        'dependency': [{'get': 'dependencies'}],
        'dependent': [{'get': 'dependents'}],
        'children': [{'get': 'children'}],
        'supported_servers.js': [{}, {}, {'get': 'supported_servers'}],
        'reload':
            [{'get': 'reload_configuration'}],
        'restore_point':
            [{'post': 'create_restore_point'}],
        'connect': [{
            'get': 'connect_status', 'post': 'connect', 'delete': 'disconnect'
        }],
        'change_password': [{'post': 'change_password'}],
        'wal_replay': [{
            'delete': 'pause_wal_replay', 'put': 'resume_wal_replay'
        }],
        'get_agents': [{}, {'get': 'get_agents'}],
        'check_pgpass': [{'get': 'check_pgpass'}],
        'clear_saved_password': [{'put': 'clear_saved_password'}],
        'clear_sshtunnel_password': [{'put': 'clear_sshtunnel_password'}]
    })
    SSL_MODES = ['prefer', 'require', 'verify-ca', 'verify-full']

    def validate_request(f):
        """
        Works as a decorator.
        Validating request on the request of create, update and modified SQL.

        Required Args:
                    name: Server Name
                    server: Server host
                    port: Server port
                    database: Server database
                    username: Server username

        Above all the arguments will not be validated in the update action.
        """
        from functools import wraps

        @wraps(f)
        def wrap(self, **kwargs):

            return validate_server_request(self, f, **kwargs)

        return wrap

    def check_precondition(f):
        """
        Works as a decorator.
        Checks the database connection status.
        Attaches the connection object and template path to the class object.
        """
        from functools import wraps

        @wraps(f)
        @pem_connection
        def wrap(*args, **kwargs):
            pem_conn = kwargs.pop('pem_conn')
            self = args[0]

            # Get Pem Server connection
            self.pem_conn = pem_conn

            if not self.pem_conn.connected():
                return precondition_required(
                    gettext(
                        "Connection to the PEM server has been lost."
                    )
                )

            # Get a Pg Driver
            self.driver = get_driver(PG_DEFAULT_DRIVER)

            # Get the server connection.
            if 'sid' in kwargs:
                # Get a Server Connection
                self.manager = self.driver.connection_manager(kwargs['sid'])
                self.qtIdent = self.driver.qtIdent
                self.qtLiteral = self.driver.qtLiteral

            # we will set template path for sql scripts
            self.template_path = 'servers/sql'

            return f(*args, **kwargs)

        return wrap

    @pga_login_required
    @check_precondition
    def nodes(self, gid):
        res = []
        """
        Return a JSON document listing the servers under this server group
        for the user.
        """
        # Get Servers from PEM Database
        sql = render_template(
            "/".join([self.template_path, 'node.sql']), sgid=gid,
            schema_version=current_user.schema_version
        )
        status, servers = self.pem_conn.execute_dict(sql)

        for server in servers['rows']:
            manager = self.driver.connection_manager(server['id'])
            conn = manager.connection()
            connected = conn.connected()
            errmsg = None
            in_recovery = None
            wal_paused = None
            sql_profiler_version = None
            edb_wait_events_loaded = False
            server['tags'] = json.loads(server['tags']) if (
                server.get('tags')) else []
            post_connection_sql = server.get('post_connection_sql')
            if connected:
                status, result, in_recovery, wal_paused = \
                    recovery_state(conn, manager.version)
                if not status:
                    connected = False
                    manager.release()
                    errmsg = "{0} : {1}".format(server.name, result)
                else:
                    sql_profiler_version = get_sql_profiler_version(manager)
                    edb_wait_events_loaded = is_edb_wait_events_loaded(manager)

            res.append(
                self.blueprint.generate_browser_node(
                    "%d" % (server['id']),
                    gid,
                    server['name'],
                    server_icon_and_background(connected, manager, server),
                    True,
                    self.node_type,
                    connected=connected,
                    server_type='ppas' if is_edb_server(
                        self.pem_conn, server['id'])
                    else "pg",
                    version=manager.version,
                    db=manager.db,
                    host=server['host'],
                    user=manager.user_info if connected else None,
                    in_recovery=in_recovery,
                    wal_pause=wal_paused,
                    sql_profiler_version=sql_profiler_version,
                    edb_wait_events_loaded=edb_wait_events_loaded,
                    is_efm_enabled=not not (server['efm_cluster_name'] and
                                            server['efm_installation_path']),
                    is_patroni_enabled=has_patroni_config(server),
                    patroni_cluster_name=server.get('patroni_cluster_name'),
                    is_password_saved=server['is_password_saved'],
                    is_tunnel_password_saved=server[
                        'is_tunnel_password_saved'],
                    is_agent_binded=server['is_agent_binded'],
                    errmsg=errmsg,
                    description=server['description'],
                    tags=server['tags'],
                    post_connection_sql=post_connection_sql
                )
            )

        if not len(res):
            return gone(errormsg=gettext(
                'The specified server group with id# {0} could not be found.'
            ))

        return make_json_response(result=res)

    @pga_login_required
    @check_precondition
    def node(self, gid, sid):
        """Return a JSON document listing the server for the user"""
        sql = render_template(
            "/".join([self.template_path, 'get_server.sql']), sgid=gid,
            sid=sid, schema_version=current_user.schema_version
        )
        status, server = self.pem_conn.execute_dict(sql)
        if not status:
            current_app.logger.exception(server)
            return internal_server_error(errormsg=server)

        if len(server['rows']) == 0:
            return make_json_response(
                status=410,
                success=0,
                errormsg=gettext(
                    gettext(
                        "Could not find the server with id# {0}."
                    ).format(sid)
                )
            )
        server = server['rows'][0]
        errmsg = None
        in_recovery = None
        wal_paused = None
        sql_profiler_version = None
        edb_wait_events_loaded = False
        is_efm_enabled = False
        is_patroni_enabled = False
        from pgadmin.utils.driver import get_driver
        manager = (
            get_driver(PG_DEFAULT_DRIVER).connection_manager(server['id']))

        conn = manager.connection()
        connected = conn.connected()
        server['tags'] = json.loads(server['tags']) if (
            server.get('tags')) else []
        post_connection_sql = server.get('post_connection_sql')
        if connected:
            status, result, in_recovery, wal_paused = \
                recovery_state(conn, manager.version)

            if not status:
                connected = False
                manager.release()
                errmsg = "{0} : {1}".format(server['name'], result)
            else:
                sql_profiler_version = get_sql_profiler_version(manager)
                edb_wait_events_loaded = is_edb_wait_events_loaded(manager)

            if 'efm_cluster_name' in server:
                is_efm_enabled = not not (
                    server['efm_cluster_name'] and
                    server['efm_installation_path']
                )

            if 'patroni_cluster_name' in server:
                is_patroni_enabled = has_patroni_config(server),

            replication_type = get_replication_type(conn, manager.version)

        return make_json_response(
            result=self.blueprint.generate_browser_node(
                "%d" % (sid),
                gid,
                server['name'],
                server_icon_and_background(connected, manager, server),
                True,
                self.node_type,
                connected=connected,
                server_type='ppas' if is_edb_server(self.pem_conn, sid)
                else "pg",
                replication_type=replication_type,
                version=manager.version,
                db=manager.db,
                user=manager.user_info if connected else None,
                in_recovery=in_recovery,
                wal_pause=wal_paused,
                host=server['host'],
                sql_profiler_version=sql_profiler_version,
                edb_wait_events_loaded=edb_wait_events_loaded,
                is_efm_enabled=is_efm_enabled,
                is_patroni_enabled=is_patroni_enabled,
                patroni_cluster_name=server.get('patroni_cluster_name'),
                is_password_saved=server['is_password_saved'],
                is_tunnel_password_saved=server['is_tunnel_password_saved'],
                is_agent_binded=server['is_agent_binded'],
                errmsg=errmsg,
                tags=server['tags'],
                post_connection_sql=post_connection_sql
            ),
        )

    @pga_login_required
    @check_precondition
    @serverRegistrationRole.check_role(
        msg=gettext("User does not have privileges to delete the server.")
    )
    def delete(self, gid, sid):
        """Delete a server node in the settings database."""
        sql = render_template(
            "/".join([self.template_path, 'get_server.sql']), sgid=gid,
            sid=sid, schema_version=current_user.schema_version
        )

        status, res = self.pem_conn.execute_dict(sql)
        if not status:
            current_app.logger.error(res)
            return internal_server_error(errormsg=res)
        if len(res['rows']) == 0:
            return gone(
                errormsg=gettext(
                    "Couldn't find the server with id# {0}!"
                ).format(sid)
            )

        # server, which is connected, cannot be deleted
        res = self.connect_status(gid, sid)
        if res.status_code == 200 and res.json['data']['connected']:
            return make_json_response(
                success=0,
                errormsg="Connected server cannot be deleted. "
                         "Please disconnect the server and try again")
        try:
            sql = render_template(
                "/".join([self.template_path, 'delete.sql']), sid=sid
            )

            status, res = self.pem_conn.execute_void(sql)
            if not status:
                current_app.logger.exception(res)
                return internal_server_error(errormsg=res)

            # ToDo: create a scheduled job to delete all probe data for the
            #  server which is getting deleted

            QueryHistory.clear_history(current_user.id, sid)
        except Exception as e:
            current_app.logger.exception(e)
            return make_json_response(
                success=0,
                errormsg=fetch_message_from_exception(e))

        # Release the existing Connection (PEM-563)
        manager = get_driver(PG_DEFAULT_DRIVER).connection_manager(sid)
        status = manager.release()
        if not status:
            current_app.logger.error(
                "server id#{0} connections could not be disconnected".format(
                    sid
                )
            )

        return make_json_response(success=1,
                                  info=gettext("Server deleted"))

    @pga_login_required
    @check_precondition
    @validate_request
    def update(self, gid, sid):
        """Update the server settings"""
        if 'server' in self.request \
            and 'host' in self.request['server'] \
            and self.request['server']['host'] \
                and self.request['server']['host'] != '':
            host = self.request['server']['host']
            if (not is_valid_ipaddress(host) and
                    not is_valid_hostname(host)):
                return make_json_response(
                    success=0,
                    status=400,
                    errormsg=gettext('Host address not valid')
                )

        # Not all parameters can be modified, while the server is connected
        disp_lbl = {
            'name': gettext('Name'),
            'host': gettext('Host name/address'),
            'port': gettext('Port'),
            'database': gettext('Maintenance database'),
            'username': gettext('Username'),
            'ssl': gettext('SSL Mode'),
            'role': gettext('Role'),
            'efm_installation_path': gettext('EFM installation path'),
            'efm_cluster_name': gettext('EFM cluster name'),
            'serviceid': gettext('Service ID'),
            'db_restriction': gettext('DB restriction'),
            'fgcolor': gettext('Foreground color'),
            'bgcolor': gettext('Background color'),
            'team': gettext('Team'),
            'kerberos_conn': gettext('Kerberos Authentication?'),
            'prepare_threshold': 'prepare_threshold',
            'tags': 'tags'
        }

        data = request.form if request.form else json.loads(
            request.data
        )

        manager = get_driver(PG_DEFAULT_DRIVER).connection_manager(sid)
        conn = manager.connection()
        connected = conn.connected()

        self._server_modify_disallowed_when_connected(
            connected, data, disp_lbl)

        status, code, res = update_server(self, data, sid)
        if not status:
            if code == 500:
                return internal_server_error(str(res))

            return ajax_response(
                response=res, status=code
            )
        conn = self.manager.connection()
        connected = conn.connected()
        # When server is connected, we don't require to update the connection
        # manager. Because - we don't allow to change any of the parameters,
        # which will affect the connections.
        if not connected:
            self.manager.update()

        # If server name is get updated then we need to send updated one
        if 'name' in self.request['server'] and \
                self.request['server']['name'] is not None:
            server_name = self.request['server']['name']
        else:
            server_name = res['name']

        # If server fgcolor or bgcolor is get updated then we need to send
        # updated one.
        for opt in ['fgcolor', 'bgcolor']:
            if opt in self.request['option'] and \
                    self.request['option'][opt] is not None:
                res[opt] = self.request['option'][opt]

        # Get EFM settings
        efm_cluster_name = res['efm_cluster_name']
        efm_installation_path = res['efm_installation_path']

        return jsonify(
            node=self.blueprint.generate_browser_node(
                "%d" % (sid), res['gid'],
                server_name,
                server_icon_and_background(
                    connected, self.manager, res),
                True,
                self.node_type,
                connected=connected,
                user=self.manager.user_info if connected else None,
                server_type='ppas'
                if is_edb_server(self.pem_conn, sid) else "pg",
                is_efm_enabled=not not (efm_cluster_name and
                                        efm_installation_path),
                is_patroni_enabled=has_patroni_config(res),
                patroni_cluster_name=res.get('patroni_cluster_name'),
                is_password_saved=res['is_password_saved'],
                is_tunnel_password_saved=res['is_tunnel_password_saved'],
                tags=json.loads(res['tags']) if
                isinstance(res['tags'], str) else res['tags'],
                **({"group_pid": res['group_pid']}
                   if 'group_pid' in res else {})
            )
        )

    def _server_modify_disallowed_when_connected(
            self, connected, data, disp_lbl):

        if connected:
            for arg in (
                    'db', 'role', 'service'
            ):
                if arg in data:
                    return forbidden(
                        errmsg=gettext(
                            "'{0}' is not allowed to modify, "
                            "when server is connected."
                        ).format(disp_lbl[arg])
                    )

    @pga_login_required
    def list(self, gid):
        """
        Return list of attributes of all servers.
        """
        sql = render_template(
            "/".join([self.template_path, 'node.sql']), sgid=gid,
            schema_version=current_user.schema_version
        )
        status, servers = self.pem_conn.execute_dict(sql)
        res = []

        driver = get_driver(PG_DEFAULT_DRIVER)

        for server in servers['rows']:
            manager = driver.connection_manager(server['id'])
            conn = manager.connection()
            connected = conn.connected()

            res.append({
                'id': server['id'],
                'name': server['name'],
                'host': server['host'],
                'port': server['port'],
                'db': server['db'],
                'gid': server.servergroup_id,
                'comment': server['comment'],
                'role': server['role'],
                'connected': connected,
                'version': manager.ver,
                'server_type':
                    'ppas' if is_edb_server(self.pem_conn, server['id'])
                    else "pg"
            })

        return ajax_response(
            response=res
        )

    @pga_login_required
    @check_precondition
    def properties(self, gid, sid):
        """Return list of attributes of a server"""

        sql = render_template(
            "/".join([self.template_path, 'properties.sql']), sid=sid,
            schema_version=current_user.schema_version
        )
        status, server = self.pem_conn.execute_dict(sql)

        if not status:
            return internal_server_error(errormsg=server)

        if server and len(server['rows']) <= 0:
            return make_json_response(
                status=410,
                success=0,
                errormsg=self.not_found_error_msg()
            )
        # Get the server details
        server = server['rows'][0]

        exclude_db_list = []
        if 'asb_exclude_databases' in server and \
                server['asb_exclude_databases'] is not None:
            if len(server['asb_exclude_databases']) > 0:
                for ex_db in server['asb_exclude_databases']:
                    exclude_db_list.append({
                        'exclude_database': ex_db
                    })
        server['asb_exclude_databases'] = exclude_db_list

        # Get connection status
        conn = self.manager.connection()
        server['connected'] = conn.connected()

        # TODO:: [PEM] We don't have service field in the server_options
        # instead it is in the pem.server table, which is a wrong, as it breaks
        # per user settings.
        server['service'] = None
        # To avoid unwated validation issue in JS model when only
        # confirm password field gets updated
        server['asb_cpass'] = server['asb_password']
        if server['connected'] is True:
            server['server_type'] = 'ppas' if \
                is_edb_server(self.pem_conn, sid) else 'pg'
            server['version'] = self.manager.ver
            server['gss_authenticated'] = getattr(
                self.manager, 'gss_authenticated', False
            )
            server['gss_encrypted'] = getattr(
                self.manager, 'gss_encrypted', False
            )
        else:
            server['gss_authenticated'] = False
            server['gss_encrypted'] = False
        server['kerberos_conn'] = _pem.use_kerberos_connection(
            server['kerberos_conn']
        )

        # Get updated connection string to show on UI, if user change host,
        # port and user when server is connected
        display_connection_str = (
            self.update_connection_string(conn.manager, server))

        # Adding the key db for maintaining the pgadmin front end code
        server['db'] = server['database']
        server['connection_string'] = display_connection_str

        if server['tags'] is not None:
            server['tags'] = json.loads(server['tags'])
            server['tags'] = [{**tag, 'old_text': tag['text']}
                              for tag in server['tags']]
        server['server_type'] = 'ppas' if is_edb_server(
            self.pem_conn, server['id']) else "pg"
        server['version'] = self.manager.ver
        server['db_res'] = (
            server['db_restriction'].split(',')) if (
            server.get('db_restriction')) else []
        server['user_id'] = current_user.id

        # ToDo: Need to add the column tunnel_keep_alive in server_auth
        server['tunnel_keep_alive'] = 0
        # Handle case where it's a JSON string instead of dict
        conn_params = server.get('connection_params')
        if isinstance(conn_params, str):
            try:
                # First, try to parse it as JSON
                conn_params = json.loads(conn_params)
                # it might still be a *stringified JSON inside JSON*, so:
                if isinstance(conn_params, str):
                    conn_params = json.loads(conn_params)
                server['connection_params'] = conn_params
            except Exception as e:
                current_app.logger.exception(e)
                return make_json_response(
                    success=0,
                    errormsg=str(e)
                )
        server['connection_params'] = \
            convert_connection_parameter(server['connection_params'])

        return ajax_response(response=server)

    @staticmethod
    def update_connection_string(manager, server):
        # Get current connection info in dict.
        con_info = conninfo_to_dict(manager.display_connection_string)
        db_name = con_info['dbname'] if 'dbname' in con_info else None

        if 'host' in con_info and 'port' in con_info and 'user' in con_info:
            con_info.pop('host')
            con_info.pop('port')
            con_info.pop('user')

        # Create ordered dict to maintain the order of updated host, port,
        # dbname, user.
        con_info_ord = OrderedDict([('host', server['host']),
                                    ('port', server['port']),
                                    ('dbname', db_name),
                                    ('user', server['username'])])
        con_info_ord.update(con_info)
        display_conn_string = make_conninfo(**con_info_ord)
        return display_conn_string

    @pga_login_required
    @check_precondition
    @validate_request
    def create(self, gid):
        """Add a server node to the settings database"""
        required_args = ['name', 'db', 'host', 'port', 'username']
        data = request.form if request.form else json.loads(
            request.data
        )
        # Loop through data and if found any value is blank string then
        # convert it to None as after porting into React, from frontend
        # '' blank string is coming as a value instead of null.
        for item in data:
            if data[item] == '':
                data[item] = None

        for arg in required_args:
            if arg not in data:
                return make_json_response(
                    status=410,
                    success=0,
                    errormsg=gettext(
                        "Could not find the required parameter ({})."
                    ).format(arg)
                )

        if 'host' in data and data['host'] and data['host'] != '':
            if (not is_valid_ipaddress(data['host']) and
                    not is_valid_hostname(data['host'])):
                return make_json_response(
                    success=0,
                    status=400,
                    errormsg=gettext('Host address not valid')
                )
        if 'tags' in data and data['tags']:
            self.request['server']['tags'] = data['tags']
        else:
            self.request['server']['tags'] = []
        try:
            status, server_id, group_pid, connected, manager = create_server(
                self)

            if not status:
                return internal_server_error(server_id)

            if gid == 0:
                return make_json_response(data={'server_id': server_id})

            sql_profiler_version = None
            edb_wait_events_loaded = False
            in_recovery = None
            wal_paused = None
            replication_type = None

            # If server is connected then only check for SQL Profiler
            if connected and manager:
                sql_profiler_version = get_sql_profiler_version(manager)
                edb_wait_events_loaded = is_edb_wait_events_loaded(manager)
                conn = manager.connection()
                _, _, in_recovery, wal_paused = recovery_state(
                    conn, manager.version
                )
                replication_type = get_replication_type(conn, manager.version)

            password_flag = False
            if ALLOW_SAVE_PASSWORD and \
                    'save_password' in data:
                password_flag = data['save_password']

            tunnel_password_flag = None
            if 'tunnel_password' in data:
                tunnel_password_flag = \
                    data['tunnel_password']
            if ALLOW_SAVE_TUNNEL_PASSWORD and tunnel_password_flag and \
                    tunnel_password_flag != '':
                tunnel_password_flag = True
            else:
                tunnel_password_flag = False

            return jsonify(
                node=self.blueprint.generate_browser_node(
                    "%d" % server_id, data['gid'],
                    data['name'],
                    server_icon_and_background(
                        connected, manager, self.request['option']
                    ),
                    True,
                    self.node_type,
                    connected=connected,
                    replication_type=replication_type,
                    server_type='ppas' if
                    is_edb_server(self.pem_conn, server_id) else "pg",
                    version=manager.version
                    if manager and manager.version else None,
                    db=manager.db,
                    user=manager.user_info if connected else None,
                    sql_profiler_version=sql_profiler_version,
                    edb_wait_events_loaded=edb_wait_events_loaded,
                    in_recovery=in_recovery,
                    wal_pause=wal_paused,
                    host=data['host'],
                    is_password_saved=password_flag,
                    is_tunnel_password_saved=tunnel_password_flag,
                    tags=data.get('tags', None),
                    group_pid=group_pid,
                    post_connection_sql=data.get('post_connection_sql')
                )
            )

        except RoleRequired as e:
            self.pem_conn.execute_void("ROLLBACK;")
            current_app.logger.exception(e)
            raise
        except Exception as e:
            self.pem_conn.execute_void("ROLLBACK;")
            current_app.logger.exception(e)
            return internal_server_error(str(e))

    @pga_login_required
    def sql(self, gid, sid):
        return make_json_response(data='')

    @pga_login_required
    def modified_sql(self, gid, sid):
        return make_json_response(data='')

    @pga_login_required
    def statistics(self, gid, sid):
        manager = get_driver(PG_DEFAULT_DRIVER).connection_manager(sid)
        conn = manager.connection()

        if conn.connected():
            status, res = conn.execute_dict(
                render_template(
                    "/servers/sql/#{0}#/stats.sql".format(manager.version),
                    conn=conn, _=gettext
                )
            )

            if not status:
                return internal_server_error(errormsg=res)

            return make_json_response(data=res)

        return make_json_response(
            info=gettext(
                "Server has no active connection for generating statistics."
            )
        )

    @pga_login_required
    def dependencies(self, gid, sid):
        return make_json_response(data='')

    @pga_login_required
    def dependents(self, gid, sid):
        return make_json_response(data='')

    def supported_servers(self, **kwargs):
        """
        This property defines (if javascript) exists for this node.
        Override this property for your own logic.
        """

        return make_response(
            render_template(
                "servers/supported_servers.js",
                server_types=ServerType.types()
            ),
            200, {'Content-Type': MIMETYPE_APP_JS}
        )

    @check_precondition
    def connect_status(self, gid, sid):
        """Check and return the connection status."""
        sql = render_template(
            "/".join([self.template_path, 'get_server.sql']),
            sid=sid, schema_version=current_user.schema_version
        )

        status, server = self.pem_conn.execute_dict(sql)
        if not status:
            current_app.logger.exception(server)
            return internal_server_error(errormsg=server)

        if len(server['rows']) == 0:
            return bad_request(self.not_found_error_msg())
        server = server['rows'][0]
        manager = get_driver(PG_DEFAULT_DRIVER).connection_manager(sid)
        conn = manager.connection()
        connected = conn.connected()
        in_recovery = None
        wal_paused = None
        errmsg = None
        replication_type = None
        if connected:
            status, result, in_recovery, wal_paused =\
                recovery_state(conn, manager.version)

            if not status:
                connected = False
                manager.release()
                errmsg = "{0} : {1}".format(server['name'], result)

            replication_type = get_replication_type(conn, manager.version)

        return make_json_response(
            data={
                'icon': server_icon_and_background(connected, manager, server),
                'connected': connected,
                'replication_type': replication_type,
                'in_recovery': in_recovery,
                'wal_pause': wal_paused,
                'server_type':
                    'ppas' if is_edb_server(self.pem_conn, sid) else "pg",
                'user': manager.user_info if connected else None,
                'errmsg': errmsg
            }
        )

    @check_precondition
    def connect(self, gid, sid, user_name=None):
        """
        Connect the Server and return the connection object.
        Verification Process before Connection:
            Verify requested server.

            Check the server password is already been stored in the
            database or not.
            If Yes, connect the server and return connection.
            If No, Raise HTTP error and ask for the password.

            In case of 'Save Password' request from user, excrypted Pasword
            will be stored in the respected server database and
            establish the connection OR just connect the server and do not
            store the password.
        """
        current_app.logger.info(
            'Connection Request for server#{0}'.format(sid)
        )

        # Fetch Server Details
        sql = render_template(
            "/".join([self.template_path, 'get_server.sql']),
            sid=sid, schema_version=current_user.schema_version
        )
        status, server = self.pem_conn.execute_dict(sql)
        if not status:
            current_app.logger.exception(server)
            return internal_server_error(errormsg=server)

        if len(server['rows']) == 0:
            return bad_request(self.not_found_error_msg())

        server = server['rows'][0]

        if server is None or len(server) == 0:
            return bad_request(self.not_found_error_msg())

        # Return if username is blank
        if server['username'] is None:
            return make_json_response(
                status=200,
                success=0,
                errormsg=gettext(
                    "Please enter the server details to connect")
            )

        data = request.form if request.form else json.loads(request.data) if \
            request.data else {}

        password = None
        tunnel_password = None
        save_password = False
        save_tunnel_password = False
        prompt_password = False
        prompt_tunnel_password = False

        # Connect the Server
        from pgadmin.utils.driver import get_driver
        manager = get_driver(PG_DEFAULT_DRIVER).connection_manager(sid)
        conn = manager.connection()

        # If server using SSH Tunnel
        if server['use_ssh_tunnel']:
            if 'tunnel_password' not in data:
                if server['tunnel_password'] is None:
                    prompt_tunnel_password = True
                else:
                    tunnel_password = server['tunnel_password']
            else:
                tunnel_password = data.get('tunnel_password') \
                    if 'tunnel_password' in data else ''
                save_tunnel_password = data.get('save_tunnel_password') \
                    if tunnel_password and 'save_tunnel_password' in data \
                    else False
                # Encrypt the password before saving with user's login
                # password key.
                try:
                    tunnel_username = data.get(
                        'tunnel_username', server['tunnel_username'])
                    key = '{}{}'.format(tunnel_username,
                                        self.pem_conn.manager.password)
                    tunnel_password = encrypt(
                        tunnel_password, True,
                        key=key) \
                        if tunnel_password is not None else \
                        server['tunnel_password']
                except Exception as e:
                    current_app.logger.exception(e)
                    return internal_server_error(
                        errormsg=fetch_message_from_exception(e))

        kerberos_conn = _pem.use_kerberos_connection(server['kerberos_conn'])

        if 'password' not in data:
            conn_passwd = getattr(conn, 'password', None)
            if conn_passwd is None and not server['is_password_saved'] and \
                    manager.passfile is None:
                # Return the password template in case password is not
                # provided, or password has not been saved earlier or
                # passfile has not been saved earlier.
                prompt_password = False if kerberos_conn else True
            else:
                password = conn_passwd or server['password']
        else:
            password = data.get('password') if 'password' in data else None

            try:
                # Encrypt the password before saving with username and
                # user's login password key.
                key = '{}{}'.format(server['username'],
                                    self.pem_conn.manager.password)
                password = _pem.encrypt(password) \
                    if password is not None else None
                save_password = data.get('save_password', 'false') == 'true'
            except Exception as e:
                current_app.logger.exception(e)
                return internal_server_error(
                    errormsg=fetch_message_from_exception(e)
                )

        # Check do we need to prompt for the database server or ssh tunnel
        # password or both. Return the password template in case password
        # is not provided, or password has not been saved earlier.
        if prompt_password or prompt_tunnel_password:
            return self.get_response_for_password(server, 428,
                                                  prompt_password,
                                                  prompt_tunnel_password)
        status = True
        try:
            status, errmsg = conn.connect(
                password=password,
                tunnel_password=tunnel_password,
                server_types=ServerType.types()
            )
        except OperationalError as e:
            return internal_server_error(errormsg=str(e))
        except Exception as e:
            current_app.logger.exception(e)
            return internal_server_error(
                errormsg=fetch_message_from_exception(e)
            )

        if not status:
            current_app.logger.error(
                "Could not connect to server(#{0}) - '{1}'.\nError: {2}"
                .format(server['id'], server['name'], errmsg)
            )
            if errmsg.find('Ticket expired') != -1:
                return internal_server_error(errmsg)

            return self.get_response_for_password(
                server, 401, True, True, errmsg
            )
        else:
            if not kerberos_conn and save_password and ALLOW_SAVE_PASSWORD:
                try:
                    # Save the encrypted password
                    server['is_password_saved'] = save_password
                    store_password(self, password, server)
                except Exception as e:
                    # Release Connection
                    current_app.logger.exception(e)
                    manager.release(database=server['maintenance_db'])
                    conn = None

                    return internal_server_error(errormsg=e)

            if save_tunnel_password and ALLOW_SAVE_TUNNEL_PASSWORD:
                try:
                    # Save the encrypted password
                    store_password(self, tunnel_password, server, True)
                except Exception as e:
                    # Release Connection
                    current_app.logger.exception(e)
                    manager.release(database=server['maintenance_db'])
                    conn = None

                    return internal_server_error(errormsg=e)

            current_app.logger.info(
                'Connection Established for server: %s - %s' % (
                    sid, server['name']
                )
            )
            # Update the recovery and wal pause option for the server
            # if connected successfully
            _, _, in_recovery, wal_paused =\
                recovery_state(conn, manager.version)

            replication_type = get_replication_type(conn, manager.version)

            sql_profiler_version = get_sql_profiler_version(manager)
            edb_wait_events_loaded = is_edb_wait_events_loaded(manager)

            return make_json_response(
                success=1,
                info=gettext("Server connected."),
                data={
                    'sid': server['id'],
                    'did': manager.did,
                    'icon': server_icon_and_background(True, manager, server),
                    'connected': True,
                    'server_type': 'ppas' if is_edb_server(
                        self.pem_conn, sid
                    ) else "pg",
                    'type': manager.server_type,
                    'replication_type': replication_type,
                    'version': manager.version,
                    'db': manager.db,
                    'user': manager.user_info,
                    'in_recovery': in_recovery,
                    'wal_pause': wal_paused,
                    'sql_profiler_version': sql_profiler_version,
                    'edb_wait_events_loaded': edb_wait_events_loaded,
                    'is_password_saved': save_password and ALLOW_SAVE_PASSWORD,
                    'is_tunnel_password_saved':
                        save_tunnel_password and ALLOW_SAVE_TUNNEL_PASSWORD,
                    'is_agent_binded': server['is_agent_binded'],
                }
            )

    @check_precondition
    def disconnect(self, gid, sid):
        """Disconnect the Server."""
        # Fetch Server Details
        sql = render_template(
            "/".join([self.template_path, 'get_server.sql']), sgid=gid,
            sid=sid, schema_version=current_user.schema_version
        )

        status, server = self.pem_conn.execute_dict(sql)

        if not status:
            current_app.logger.exception(server)
            return internal_server_error(errormsg=server)

        if len(server['rows']) == 0:
            return bad_request(gettext(
                "Could not find the server with id# {0}."
            ).format(sid))

        server = server['rows'][0]

        # Release Connection
        manager = get_driver(PG_DEFAULT_DRIVER).connection_manager(sid)
        # Check if any psql terminal is running for the current disconnecting
        # server. If any terminate the psql tool connection.
        if 'sid_soid_mapping' in current_app.config and str(sid) in \
                current_app.config['sid_soid_mapping'] and \
                str(sid) in current_app.config['sid_soid_mapping']:
            for i in current_app.config['sid_soid_mapping'][str(sid)]:
                sio.emit('disconnect-psql', namespace='/pty', to=i)

        status = manager.release()

        if not status:
            return unauthorized(gettext("Server could not be disconnected."))
        else:
            return make_json_response(
                success=1,
                info=gettext("Server disconnected."),
                data={
                    'icon': server_icon_and_background(False, manager, server),
                    'connected': False
                }
            )

    def reload_configuration(self, gid, sid):
        """Reload the server configuration"""

        # Reload the server configurations
        manager = get_driver(PG_DEFAULT_DRIVER).connection_manager(sid)
        conn = manager.connection()

        if conn.connected():
            # Execute the command for reload configuration for the server
            status, _ = conn.execute_scalar("SELECT pg_reload_conf();")

            if not status:
                return internal_server_error(
                    gettext("Could not reload the server configuration.")
                )
            else:
                return make_json_response(data={
                    'status': True,
                    'result': gettext('Server configuration reloaded.')
                })

        else:
            return make_json_response(data={
                'status': False,
                'result': SERVER_CONNECTION_CLOSED})

    def create_restore_point(self, gid, sid):
        """
        This method will create named restore point

        Args:
            gid: Server group ID
            sid: Server ID

        Returns:
            None
        """
        try:
            data = request.form
            restore_point_name = data['value'] if data else None
            manager = get_driver(PG_DEFAULT_DRIVER).connection_manager(sid)
            conn = manager.connection()

            # Execute SQL to create named restore point
            if conn.connected():
                if restore_point_name:
                    status, res = conn.execute_scalar(
                        "SELECT pg_create_restore_point('{0}');".format(
                            restore_point_name
                        )
                    )
                if not status:
                    return internal_server_error(
                        errormsg=str(res)
                    )

                return make_json_response(
                    data={
                        'status': 1,
                        'result': gettext(
                            'Named restore point created: {0}').format(
                                restore_point_name)
                    })

        except Exception as e:
            current_app.logger.error(gettext(
                'Named restore point creation failed ({0})').format(
                    str(e))
            )
            return internal_server_error(errormsg=str(e))

    def change_password(self, gid, sid):
        """
        This function is used to change the password of the
        Database Server.

        Args:
            gid: Group id
            sid: Server id
        """
        try:
            data = None
            if request.form:
                data = request.form
            elif request.data:
                data = json.loads(request.data)

            # Get enc key
            crypt_key_present, crypt_key = get_crypt_key()
            if not crypt_key_present:
                raise CryptKeyMissing

            # Fetch Server Details
            server = Server.query.filter_by(id=sid).first()
            if server is None:
                return bad_request(self.not_found_error_msg())

            # Fetch User Details.
            user = User.query.filter_by(id=current_user.id).first()
            if user is None:
                return unauthorized(gettext(UNAUTH_REQ))

            manager = get_driver(PG_DEFAULT_DRIVER).connection_manager(sid)
            conn = manager.connection()
            is_passfile = False

            # If there is no password found for the server
            # then check for pgpass file
            if not server.password and not manager.password and \
                hasattr(server, 'connection_params') and \
                'passfile' in server.connection_params and \
                manager.get_connection_param_value('passfile') and \
                server.connection_params['passfile'] == \
                    manager.get_connection_param_value('passfile'):
                is_passfile = True

            # Check for password only if there is no pgpass file used
            if not is_passfile and data and \
                    ('password' not in data or data['password'] == ''):
                return make_json_response(
                    status=400,
                    success=0,
                    errormsg=gettext(
                        "Could not find the required parameter(s)."
                    )
                )

            if data and ('newPassword' not in data or
                         data['newPassword'] == '' or
                         'confirmPassword' not in data or
                         data['confirmPassword'] == ''):
                return make_json_response(
                    status=400,
                    success=0,
                    errormsg=gettext(
                        "Could not find the required parameter(s)."
                    )
                )

            if data['newPassword'] != data['confirmPassword']:
                return make_json_response(
                    status=200,
                    success=0,
                    errormsg=gettext(
                        "Passwords do not match."
                    )
                )

            # Check against old password only if no pgpass file
            if not is_passfile:
                decrypted_password = decrypt(manager.password, crypt_key)
                if isinstance(decrypted_password, bytes):
                    decrypted_password = decrypted_password.decode()
                password = data['password']

                # Validate old password before setting new.
                if password != decrypted_password:
                    return unauthorized(gettext("Incorrect password."))

            # Hash new password before saving it.
            if manager.sversion >= 100000:
                password = conn.pq_encrypt_password_conn(data['newPassword'],
                                                         manager.user)
                if password is None:
                    # Unable to encrypt the password so used the
                    # old method of encryption
                    password = pqencryptpassword(data['newPassword'],
                                                 manager.user)
            else:
                password = pqencryptpassword(data['newPassword'], manager.user)

            SQL = render_template(
                "/servers/sql/#{0}#/change_password.sql".format(
                    manager.version),
                conn=conn, _=gettext,
                user=manager.user, encrypted_password=password)

            status, res = conn.execute_scalar(SQL)

            if not status:
                return internal_server_error(errormsg=res)

            # Store password in sqlite only if no pgpass file
            if not is_passfile:
                password = encrypt(data['newPassword'], crypt_key)
                # Check if old password was stored in pgadmin4 sqlite database.
                # If yes then update that password.
                if server.password is not None and config.ALLOW_SAVE_PASSWORD:
                    setattr(server, 'password', password)
                    db.session.commit()
                # Also update password in connection manager.
                manager.password = password
                manager.update_session()

            return make_json_response(
                status=200,
                success=1,
                info=gettext(
                    "Password changed successfully."
                )
            )

        except Exception as e:
            return internal_server_error(errormsg=str(e))

    def wal_replay(self, sid, pause=True):
        """
        Utility function for wal_replay for resume/pause.
        """
        server = Server.query.filter_by(
            user_id=current_user.id, id=sid
        ).first()

        if server is None:
            return make_json_response(
                success=0,
                errormsg=self.not_found_error_msg()
            )

        try:
            manager = get_driver(PG_DEFAULT_DRIVER).connection_manager(sid)
            conn = manager.connection()
            msg = None
            # Execute SQL to pause or resume WAL replay
            if conn.connected():
                if pause:
                    sql = "SELECT pg_xlog_replay_pause();"
                    if manager.version >= 100000:
                        sql = "SELECT pg_wal_replay_pause();"

                    status, res = conn.execute_scalar(sql)
                    if not status:
                        return internal_server_error(
                            errormsg=str(res)
                        )
                    msg = gettext('WAL replay paused')
                else:
                    sql = "SELECT pg_xlog_replay_resume();"
                    if manager.version >= 100000:
                        sql = "SELECT pg_wal_replay_resume();"

                    status, res = conn.execute_scalar(sql)
                    if not status:
                        return internal_server_error(
                            errormsg=str(res)
                        )
                    msg = gettext('WAL replay resumed')
                return make_json_response(
                    success=1,
                    info=msg,
                    data={'in_recovery': True, 'wal_pause': pause}
                )
            return gone(errormsg=gettext('Please connect the server.'))
        except Exception as e:
            current_app.logger.error(
                'WAL replay pause/resume failed'
            )
            return internal_server_error(errormsg=str(e))

    def resume_wal_replay(self, gid, sid):
        """
        This method will resume WAL replay

        Args:
            gid: Server group ID
            sid: Server ID

        Returns:
            None
        """
        return self.wal_replay(sid, False)

    def pause_wal_replay(self, gid, sid):
        """
        This method will pause WAL replay

        Args:
            gid: Server group ID
            sid: Server ID

        Returns:
            None
        """
        return self.wal_replay(sid, True)

    def check_pgpass(self, gid, sid):
        """
        This function is used to check whether server is connected
        using pgpass file or not

        Args:
            gid: Group id
            sid: Server id
        """
        is_pgpass = False
        server = Server.query.filter_by(
            user_id=current_user.id, id=sid
        ).first()

        if server is None:
            return make_json_response(
                success=0,
                errormsg=self.not_found_error_msg()
            )

        try:
            manager = get_driver(PG_DEFAULT_DRIVER).connection_manager(sid)
            conn = manager.connection()
            if not conn.connected():
                return gone(
                    errormsg=gettext('Please connect the server.')
                )

            if (not server.password or not manager.password) and \
                hasattr(server, 'connection_params') and \
                'passfile' in server.connection_params and \
                manager.get_connection_param_value('passfile') and \
                server.connection_params['passfile'] == \
                    manager.get_connection_param_value('passfile'):
                is_pgpass = True
            return make_json_response(
                success=1,
                data=dict({'is_pgpass': is_pgpass}),
            )
        except Exception as e:
            current_app.logger.error(
                'Cannot able to fetch pgpass status'
            )
            return internal_server_error(errormsg=str(e))

    def get_response_for_password(self, server, status, prompt_password=False,
                                  prompt_tunnel_password=False, errmsg=None):

        if server['use_ssh_tunnel']:
            data = {
                "server_label": server['name'],
                "username": server['username'],
                "tunnel_username": server['tunnel_username'],
                "tunnel_host": server['tunnel_host'],
                "tunnel_identity_file": server['tunnel_identity_file'],
                "tunnel_keep_alive": server['tunnel_keep_alive'],
                "errmsg": errmsg,
                "service": server.get('service', None),
                "prompt_tunnel_password": prompt_tunnel_password,
                "prompt_password": prompt_password,
                "allow_save_password":
                    True if config.ALLOW_SAVE_PASSWORD and
                    'allow_save_password' in session and
                    session['allow_save_password'] else False,
                "allow_save_tunnel_password":
                    True if config.ALLOW_SAVE_TUNNEL_PASSWORD and
                    'allow_save_tunnel_password' in session and
                    session['allow_save_tunnel_password'] else False
            }

            return make_json_response(
                success=0,
                status=status,
                result=data
            )
        else:
            data = {
                "server_label": server['name'],
                "username": server['username'],
                "errmsg": errmsg,
                "service": server.get('service', None),
                "prompt_password": True,
                "allow_save_password":
                    True if config.ALLOW_SAVE_PASSWORD and
                    'allow_save_password' in session and
                    session['allow_save_password'] else False,
            }
            return make_json_response(
                success=0,
                status=status,
                result=data
            )

    @pga_login_required
    @check_precondition
    def get_agents(self, gid, sid=None):
        """To fetch all the agents for select2 control in agent binding tab"""

        sql = render_template(
            "/".join(['servers/sql/pem', 'get_agents.sql'])
        )
        status, res = self.pem_conn.execute_dict(sql)
        if not status:
            current_app.logger.error(
                'Cannot able to fetch agents.'
            )
            return internal_server_error(errormsg=str(res))

        agents = [agent for agent in res['rows']]

        return make_json_response(
            data=agents,
            status=200
        )

    @pga_login_required
    @check_precondition
    def clear_saved_password(self, gid, sid):
        """
        This function is used to remove database server password stored into
        the database.

        :param gid:
        :param sid:
        :return:
        """
        # Fetch Server Details
        sql = render_template(
            "/".join([self.template_path, 'get_server.sql']),
            sid=sid, schema_version=current_user.schema_version
        )

        status, server = self.pem_conn.execute_dict(sql)

        if not status:
            current_app.logger.exception(server)
            return internal_server_error(errormsg=server)

        if len(server['rows']) == 0:
            return gone(SERVER_NOT_FOUND_ERROR)

        server = server['rows'][0]
        if server is None or len(server) == 0:
            return bad_request(SERVER_NOT_FOUND_ERROR)

        try:
            # Clear the password
            server['is_password_saved'] = False
            store_password(self, None, server)
        except Exception as e:
            # Release Connection
            driver = get_driver(PG_DEFAULT_DRIVER)
            manager = driver.connection_manager(sid)
            manager.release(database=server['maintenance_db'])
            current_app.logger.exception(e)
            return internal_server_error(errormsg=e)

        return make_json_response(
            success=1,
            info=gettext("The saved password cleared successfully."),
            data={'is_password_saved': False}
        )

    @pga_login_required
    @check_precondition
    def clear_sshtunnel_password(self, gid, sid):
        """
        This function is used to remove sshtunnel password stored into
        database.

        :param gid:
        :param sid:
        :return:
        """
        # Fetch Server Details
        sql = render_template(
            "/".join([self.template_path, 'get_server.sql']),
            sid=sid, schema_version=current_user.schema_version
        )

        status, server = self.pem_conn.execute_dict(sql)

        if not status:
            current_app.logger.exception(server)
            return internal_server_error(errormsg=server)

        if len(server['rows']) == 0:
            return gone(SERVER_NOT_FOUND_ERROR)

        server = server['rows'][0]
        if server is None or len(server) == 0:
            return bad_request(gettext(SERVER_NOT_FOUND_ERROR))

        try:
            # Clear the password
            store_password(self, None, server, True)
        except Exception as e:
            # Release Connection
            current_app.logger.exception(e)
            driver = get_driver(PG_DEFAULT_DRIVER)
            manager = driver.connection_manager(sid)
            manager.release(database=server['maintenance_db'])
            return internal_server_error(errormsg=e)

        return make_json_response(
            success=1,
            info=gettext(
                "The saved SSH tunnel password cleared successfully."),
            data={'is_tunnel_password_saved': False}
        )
