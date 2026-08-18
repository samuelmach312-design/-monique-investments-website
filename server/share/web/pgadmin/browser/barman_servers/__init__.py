##########################################################################
#
# Postgres Enterprise Manager
#
# Copyright (C) 2016 - 2025, EnterpriseDB Corporation. All rights reserved.
#
##########################################################################
"""Implements Barman Server Module"""

import json
from functools import wraps
from flask import request, render_template, jsonify, current_app, session
from flask_security import login_required, current_user
from flask_babel import gettext

from pgadmin.utils.ajax import make_json_response, internal_server_error, \
    make_response as ajax_response, precondition_required, gone, \
    service_unavailable
from pgadmin.browser.utils import NodeView
from pgadmin.browser.collection import CollectionNodeModule
from pgadmin.pem.utils import pem_connection
from pgadmin.utils.preferences import Preferences

from .utils import manageBarman, BARMAN_RLS_ROLE, BARMAN_RLS_ERROR_MSG, \
    get_all_server_details, get_all_backup_details, VALID_BACKUP_STATUS


class BarmanServerModule(CollectionNodeModule):
    """
    class BarmanServerModule(CollectionNodeModule):

        This class represents The Barman Server Module.

    Methods:
    -------
    * __init__(*args, **kwargs)
      - Initialize the Barman Server Module.

    * node_inode(gid, sid, did, scid)
      - Returns Barman Server node as leaf node.

    * script_load()
      - Returns None

    * get_nodes(gid, sid, did, scid)
      - Generate the Barman Server collection node.

    """
    _NODE_TYPE = 'barman_server'
    _COLLECTION_LABEL = gettext("Barman Servers")
    LABEL = gettext("Barman Servers")
    SHOW_ON_BROWSER = True

    def __init__(self, *args, **kwargs):
        self.min_ver = None
        self.max_ver = None
        super(BarmanServerModule, self).__init__(*args, **kwargs)

    @property
    def script_load(self):
        return None

    @property
    def node_inode(self):
        """
        Returns Barman Server node as leaf node.
        """
        return False

    @pem_connection
    def get_nodes(self, id=1, pem_conn=None):
        """
        Generate the Barman Server collection node
        """
        if self.show_node and manageBarman.has_role():
            yield self.generate_browser_collection_node(id)

    @property
    def module_use_template_javascript(self):
        """
        Returns whether Jinja2 template is used for generating the javascript
        module.
        """
        return False

    @property
    def csssnippets(self):
        """
        Returns a snippet of css to include in the page
        """
        snippets = [
            render_template(
                "barman_server/css/barman_server.css",
                node_type=self.node_type
            )
        ]

        for submodule in self.submodules:
            snippets.extend(submodule.csssnippets)

        return snippets

    def get_exposed_url_endpoints(self):
        """
        Returns:
            list: a list of url endpoints exposed to the client.
        """
        return [
            'NODE-barman_server.dashboard',
            'NODE-barman_server.dashboard_servers',
            'NODE-barman_server.dashboard_backups',
            'NODE-barman_server.barman_graph_stats',
            'NODE-barman_server.barman_graph_stats_with_defaults'
        ]

    def register_preferences(self):
        """
        register_preferences
        Register preferences for this module.

        Keep the browser preference object to be used by overriden submodule,
        along with that get two browser level preferences show_system_objects,
        and show_node will be registered to used by the submodules.
        """
        # Add the node informaton for browser, not in respective node
        # preferences
        self.browser_preference = Preferences.module('browser')
        self.pref_show_system_objects = self.browser_preference.preference(
            'show_system_objects'
        )
        self.pref_show_node = self.preference.register(
            'node', 'show_node_' + self.node_type,
            self.collection_label, 'node', self.SHOW_ON_BROWSER,
            category_label=gettext('Nodes')
        )


blueprint = BarmanServerModule(__name__)


class BarmanServerView(NodeView):
    """
    class BarmanServerView(PGChildNodeView):

    This class inherits PGChildNodeView to get the different routes for
    the module.

    The class is responsible to Read, Update and Delete operations for
    the Barman Server View.

    Methods:
    -------

    * check_precondition(f):
      - Works as a decorator.
      -  Checks database connection status.
      -  Attach connection object and template path.

    * list():
      - List the Barman Servers.

    * nodes():
      - Returns all the Barman Servers to generate Nodes in the browser.

    * properties(bsid):
      - Returns the Barman Server properties.

    * create():
      - Creates the Barman Server object.

    * update(bsid):
      - Updates the Barman Server object.

    * delete(bsid):
      - Drops the Barman Server object.
    """
    node_type = blueprint.node_type
    parent_ids = []
    barman_server = None
    ids = [{'type': 'int', 'id': 'bsid'}]

    operations = dict({
        'obj': [
            {
                'get': 'properties',
                'delete': 'delete',
                'put': 'update'
            }, {
                'get': 'list',
                'post': 'create',
                'delete': 'delete'
            }
        ],
        'nodes': [
            {
                'get': 'node'
            }, {
                'get': 'nodes'
            }
        ],
        'children': [
            {
                'get': 'children'
            }
        ],
        'agent_list': [
            {
                'get': 'agent_list'
            }, {
                'get': 'agent_list'
            }
        ]
    })

    def check_precondition(f):
        """
        This function will behave as a decorator which will checks
        database connection before running view, it will also attaches
        manager,conn & template_path properties to self
        """
        @wraps(f)
        @pem_connection
        @manageBarman.check_role(msg=BARMAN_RLS_ERROR_MSG)
        def wrap(self, *args, **kwargs):
            self.conn = kwargs['pem_conn']
            # If DB not connected then return error to browser
            if not self.conn.connected():
                self.conn.connect()

            if not self.conn.connected():
                return precondition_required(
                    gettext("Connection to the PEM server has been lost!")
                )

            # We do not need to pass the pem_conn to the wrapped functions
            del kwargs['pem_conn']

            # Set the template path for sql scripts
            self.template_path = 'barman_server/sql'

            return f(self, *args, **kwargs)
        return wrap

    def get_barman_server_data(self, bsid):
        """Fetches existing Barman server properties"""
        sql = render_template(
            "/".join([self.template_path, 'node.sql']),
            bsid=bsid
        )
        status, res = self.conn.execute_dict(sql)
        if not status:
            return False, 'error', res

        if len(res['rows']) == 0:
            return False, 'gone', gettext('Barman Server is not available.')

        result = res['rows'][0]

        return True, 'success', result

    def get_agents(self, option=None):
        """
        This is generic function & will fetch agents which supports
        provided Barman capablities

        :param capabilities: List of Barman capablities
        :return:
        """
        SQL = render_template(
            "/".join([self.template_path, 'get_agents.sql']),
            option=option
        )
        status, res = self.conn.execute_dict(SQL)
        if not status:
            current_app.logger.error(res)
            return internal_server_error(errormsg=res)

        if res and len(res['rows']) <= 0:
            return make_json_response(
                status=410,
                success=0,
                errormsg=gettext(
                    "Could not able to fetch the supported agent list."
                )
            )

        return make_json_response(
            data=res['rows'],
            status=200
        )

    @login_required
    @check_precondition
    def agent_list(self, bsid=None):
        """List down the agents"""
        return self.get_agents()

    @login_required
    @check_precondition
    def list(self):
        """
        List the Barman Servers.
        """
        sql = render_template(
            "/".join([self.template_path, 'node.sql'])
        )
        status, res = self.conn.execute_dict(sql)

        if not status:
            current_app.logger.error(res)
            return internal_server_error(errormsg=res)

        return ajax_response(response=res['rows'], status=200)

    @login_required
    @check_precondition
    def node(self, bsid):
        return self.nodes(bsid)

    @login_required
    @check_precondition
    def nodes(self, bsid=None):
        """
        Returns all the Barman Servers.
        """
        SQL = render_template(
            "/".join([self.template_path, 'node.sql']),
            bsid=bsid
        )
        status, rset = self.conn.execute_dict(SQL)
        if not status:
            current_app.logger.error(rset)
            return internal_server_error(errormsg=rset)

        if bsid is not None:
            if len(rset['rows']) == 0:
                return gone(errormsg=gettext(
                    'Barman Server is not available.'
                ))

            row = rset['rows'][0]

            return make_json_response(
                data=self.blueprint.generate_browser_node(
                    bsid,
                    None,
                    row['description'],
                    icon="icon-barman_server",
                )
            )

        result = []
        for row in sorted(rset['rows'], key=lambda k: k['description']):
            result.append(
                self.blueprint.generate_browser_node(
                    row['id'],
                    None,
                    row['description'],
                    icon="icon-barman_server",
                )
            )

        return make_json_response(data=result, status=200)

    @login_required
    @check_precondition
    def properties(self, bsid):
        """
        Get the Barman Server properties
        """
        status, type, res = self.get_barman_server_data(bsid)
        if not status:
            if type == 'error':
                return internal_server_error(errormsg=res)
            elif type == 'gone':
                current_app.logger.error(
                    'Barman Server#{0} is not available.'.format(bsid)
                )
                return gone(errormsg=res)

        barman_node = res

        def query_output_for_barman_node(_col, _sql,):
            status, res = self.conn.execute_dict(_sql)

            if not status:
                return internal_server_error(errormsg=res)

            barman_node[_col] = res['rows']

        res = query_output_for_barman_node(
            'barman_info',
            render_template(
                "/".join([self.template_path, 'info.sql']),
                bsid=bsid
            )
        )

        if res is not None:
            return res

        res = query_output_for_barman_node(
            'barman_config',
            render_template(
                "/".join([self.template_path, 'config.sql']),
                bsid=bsid
            )
        )

        if res is not None:
            return res

        return ajax_response(response=barman_node, status=200)

    @login_required
    @check_precondition
    def create(self):
        """Create the Barman server."""
        required_args = [
            'description', 'url',
        ]

        data = request.form if request.form else json.loads(request.data)

        for arg in required_args:
            if arg not in data:
                return make_json_response(
                    status=410,
                    success=0,
                    errormsg=gettext(
                        "Could not find the required parameter ({0})."
                    ).format(arg)
                )

        current_app.logger.info(
            'Creat request for the Barman Server by the pem user '
            '{0}.'.format(current_user.user.username)
        )

        if 'probe_execution_frequency' not in data:
            data['probe_execution_frequency'] = 30

        if 'heartbeat_interval' not in data:
            data['heartbeat_interval'] = 10

        options = {
            opt: data[opt] for opt in data if opt in (
                'url', 'probe_execution_frequency',
                'heartbeat_interval'
            )
        }
        data['options'] = options
        data['name'] = 'barman'

        if 'team' not in data:
            data['team'] = ''

        _, _ = self.conn.execute_void("BEGIN")
        SQL = render_template(
            "/".join([self.template_path, 'create.sql']),
            data=data
        )

        status, barman_id = self.conn.execute_scalar(SQL)

        if not status:
            _, _ = self.conn.execute_void("ROLLBACK")
            current_app.logger.error(barman_id)
            return internal_server_error(errormsg=barman_id)

        if 'agent_id' in data and data['agent_id'] is not None:
            SQL = render_template(
                "/".join([
                    self.template_path, 'store_agent_tool_binding.sql'
                ]), conn=self.conn, tool_id=barman_id,
                agent_id=data['agent_id'], options=None
            )

            status, msg = self.conn.execute_void(SQL)

            if not status:
                _, _ = self.conn.execute_void("ROLLBACK")
                current_app.logger.error(msg)
                return internal_server_error(errormsg=msg)

        SQL = render_template(
            "/".join([self.template_path, 'store_tool_options.sql']),
            tool_id=barman_id, current_user=current_user.user.username,
            description=data['description'], options=None
        )

        status, msg = self.conn.execute_void(SQL)

        if not status:
            _, _ = self.conn.execute_void("ROLLBACK")
            current_app.logger.error(msg)
            return internal_server_error(errormsg=msg)

        _, _ = self.conn.execute_void("COMMIT")

        return jsonify(
            node=self.blueprint.generate_browser_node(
                barman_id,
                None,
                data['description'],
                icon="icon-barman_server",
            )
        )

    @login_required
    @check_precondition
    def update(self, bsid):
        """
        Update the Barman Server properties
        """
        if request.form:
            data = request.form
        else:
            data = json.loads(request.data.decode())

        current_app.logger.info(
            'Update request for the Barman Server#{0} by the pem user '
            '{1}.'.format(bsid, current_user.user.username)
        )

        status, type, old_data = self.get_barman_server_data(bsid)

        if not status:
            if type == 'error':
                return internal_server_error(errormsg=old_data)
            elif type == 'gone':
                current_app.logger.error(
                    'Barman Server#{0} is not available.'.format(bsid)
                )
                return gone(errormsg=old_data)

        sql = ''

        desc = data['description'] if 'description' in data else \
            old_data['description']

        # Start transaction
        _, _ = self.conn.execute_void("BEGIN")

        if (
            session['username'] == old_data['tool_owner'] or
            current_user.is_super_admin
        ):
            options = {}

            for opt in (
                    'url', 'probe_execution_frequency', 'heartbeat_interval'):
                if opt in data:
                    options[opt] = data[opt]
                else:
                    options[opt] = old_data[opt]
            data['options'] = options

            if (
                'description' in data or 'team' in data or
                'options' in data or 'gid' in data or 'team' in data
            ):
                sql = render_template(
                    "/".join([self.template_path, 'update.sql']),
                    conn=self.conn,
                    tool_id=bsid,
                    data=data
                )

            if 'agent_id' in data:
                if data['agent_id'] is None:
                    sql += render_template(
                        "/".join([
                            self.template_path,
                            'delete_agent_binding.sql'
                        ]), tool_id=bsid
                    )
                else:
                    sql += render_template(
                        "/".join([
                            self.template_path,
                            'store_agent_tool_binding.sql'
                        ]), conn=self.conn, tool_id=bsid,
                        agent_id=data['agent_id'], options=None
                    )

        if 'description' in data:
            sql += render_template(
                "/".join([
                    self.template_path,
                    'store_tool_options.sql'
                ]), tool_id=bsid, description=data['description'],
                current_user=current_user.user.username, options=None
            )

        if sql != '':
            status, msg = self.conn.execute_void(sql)

            if not status:
                current_app.logger.error(msg)
                _, _ = self.conn.execute_void("ROLLBACK")
                return internal_server_error(errormsg=msg)

        # End & Commit transaction
        _, _ = self.conn.execute_void("COMMIT")

        return jsonify(
            node=self.blueprint.generate_browser_node(
                bsid,
                None,
                desc,
                icon="icon-barman_server",
            )
        )

    @login_required
    @check_precondition
    def delete(self, bsid=None):
        """
        Delete a Barman Server
        """

        if bsid is None:
            data = request.form if request.form else json.loads(request.data)
        else:
            data = {'ids': [bsid]}

        try:
            for bsid in data['ids']:
                sql = render_template(
                    "/".join([self.template_path, 'delete.sql']),
                    bsid=bsid
                )
                status, res = self.conn.execute_void(sql)
                if not status:
                    current_app.logger.error(res)
                    return internal_server_error(res)

                # schedule a job to delete all probe data for the server
                try:
                    from pgadmin.browser.server_groups.agents.jobs.utils \
                        import create_purge_job
                    create_purge_job(self.conn, toolid=bsid)
                except Exception as e:
                    current_app.logger.exception(e)

                    from pgadmin.browser.server_groups.servers.utils import \
                        fetch_message_from_exception

                    return internal_server_error(
                        errormsg=fetch_message_from_exception(e)
                    )

        except Exception as e:
            return internal_server_error(errormsg=str(e))

        return make_json_response(success=1)


@blueprint.route('/<int:bsid>/dashboard', endpoint='dashboard')
@pem_connection
@manageBarman.check_role(msg=BARMAN_RLS_ERROR_MSG)
@login_required
def dashboard(bsid, pem_conn=None):
    """
    Renders the Barman Server dashboard
    Args:
        bsid: Barman Server ID

    Returns: Barman Server dashboard
    """
    import config as _config
    lang = 'en'
    if _config.SHORT_COMPANY_NAME == 'etdb':
        lang = 'cn'

    status, res = pem_conn.execute_scalar(
        "SELECT COUNT(1) FROM pem.tool WHERE active and id = %s ", (bsid,)
    )
    if not status:
        return internal_server_error(errormsg=str(res))

    status, servers = get_all_server_details(bsid, pem_conn)
    if not status:
        return internal_server_error(errormsg=str(servers))

    return render_template(
        '/barman_server/dashboard.html',
        _=gettext,
        requirejs=True,
        basejs=True,
        language_reference=lang,
        company_website=_config.COMPANY_SITE,
        bsid=bsid,
        valid_backup_status=VALID_BACKUP_STATUS,
        servers=servers
    )


@blueprint.route('/<int:bsid>/servers', endpoint='dashboard_servers')
@pem_connection
@manageBarman.check_role(msg=BARMAN_RLS_ERROR_MSG)
@login_required
def dashboard_servers(bsid, pem_conn=None):
    """
    Renders the Barman Server dashboard
    Args:
        bsid: Barman Server ID
        pem_conn: PEM connection

    Returns: Barman Server dashboard
    """
    status, servers = get_all_server_details(bsid, pem_conn)
    if not status:
        return internal_server_error(errormsg=str(servers))

    return ajax_response(
        response=servers,
        status=200
    )


@blueprint.route('/<int:bsid>/backups', endpoint='dashboard_backups')
@pem_connection
@manageBarman.check_role(msg=BARMAN_RLS_ERROR_MSG)
@login_required
def dashboard_backups(bsid, pem_conn=None):
    """
    Renders the Barman backup dashboard
    Args:
        bsid: Barman Server ID
        pem_conn: PEM connection

    Returns: Barman backup dashboard
    """
    status, backups = get_all_backup_details(bsid, pem_conn)
    if not status:
        return internal_server_error(errormsg=str(backups))

    return ajax_response(
        response=backups,
        status=200
    )


@blueprint.route(
    '/<int:bsid>/stats/<int:duration>/<until>/<server>',
    endpoint='barman_graph_stats',
)
@blueprint.route(
    '/<int:bsid>/stats/<int:duration>/<until>/',
    endpoint='barman_graph_stats_with_defaults',
)
@pem_connection
@manageBarman.check_role(msg=BARMAN_RLS_ERROR_MSG)
@login_required
def activity_stats(bsid, duration, until, server=None,
                   pem_conn=None):
    if not pem_conn.connected():
        pem_conn.connect()
    if not pem_conn.connected():
        return precondition_required(
            gettext("Connection to the PEM server has been lost!")
        )

    if duration not in (1, 3, 7, 14, 21, 28):
        return precondition_required(
            gettext("Please provide valid barman activity duration")
        )

    SQL = render_template(
        'barman_server/sql/activity_chart_data.sql',
        bsid=bsid,
        server=server,
        duration=duration,
        until=until
    )
    status, rset = pem_conn.execute_dict(SQL)
    if not status:
        current_app.logger.error(rset)
        return internal_server_error(errormsg=rset)

    action = []
    for row in rset['rows']:
        action.append({
            'server': row['server'],
            'action': row['action'],
            'start_time': row['start_time'],
            'end_time': row['end_time'],
            'duration': row['duration'],
            'status': row['status'],
            'mode': row['mode'],
            'error_message': row['error_message'],
        })

    result = {
        'action': action
    }
    return ajax_response(result)


BarmanServerView.register_node_view(blueprint)
