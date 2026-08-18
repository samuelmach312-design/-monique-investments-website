##########################################################################
#
# Postgres Enterprise Manager
#
# Copyright (C) 2016 - 2025, EnterpriseDB Corporation. All rights reserved.
#
##########################################################################

"""Server helper utilities"""
import os
import json
from flask import request, current_app, render_template, session
from flask_babel import gettext
from flask_security import current_user

import config
from pgadmin.browser.server_groups.servers import ServerType
from pgadmin.pem.utils import pem_encrypt as encrypt
from pgadmin.pem.utils.role import PEMRole
from pgadmin.utils import get_storage_directory
from pgadmin.utils.ajax import make_response, internal_server_error
from pgadmin.utils.driver import get_driver
from pgadmin.browser.server_groups.servers.utils import (
    convert_connection_parameter, check_ssl_fields)


serverRegistrationRole = PEMRole(
    'pem_database_server_registration',
    gettext('Database server registration'), None,
    gettext(
        'Privilege to register/modify a database server properties, and '
        'change the agent server binding information.'
    )
)


SSL_MODES = ['prefer', 'require', 'verify-ca', 'verify-full']


def get_sql_profiler_version(manager):
    sql_profiler_loaded = False
    sql_profiler_version = None
    if manager.user_info.get('is_superuser'):
        sql_profiler_check_sql = "/".join(['servers/sql/pem',
                                           'sql_profiler_check.sql'])
        sql = render_template(
            sql_profiler_check_sql,
            super_user=True
        )
        conn = manager.connection()
        status, result = conn.execute_scalar(sql)

        if result.find('sql-profiler') != -1:
            sql_profiler_loaded = True

        sql = render_template(
            sql_profiler_check_sql,
            is_functions_present=True
        )
        status, is_func_present = conn.execute_scalar(sql)

        if sql_profiler_loaded and is_func_present:
            sql = render_template(
                sql_profiler_check_sql,
                get_profiler_version=True
            )

            status, sql_profiler_version = conn.execute_scalar(sql)

            if not status:
                sql_profiler_version = None

        return sql_profiler_version


def is_edb_wait_events_loaded(manager):
    """
    This function will allow us to check if edb_wait_events plugin is loaded

    :param manager: Server manager
    :return: True/False
    """
    conn = manager.connection()
    sql = "SELECT pg_catalog.pg_has_role('pg_read_all_settings', 'member')"

    status, has_required_role = conn.execute_scalar(sql)

    if not has_required_role:
        return False

    sql = render_template(
        "/".join(['servers/sql/pem',
                  'edb_wait_event_check.sql']),
        check_shared_preload_library=True
    )

    status, result = conn.execute_scalar(sql)

    if not ('edb_wait_states' in result):
        return False

    sql = render_template(
        "/".join(['servers/sql/pem',
                  'edb_wait_event_check.sql']),
        is_functions_present=True
    )
    status, is_func_present_and_executable = conn.execute_scalar(sql)

    return is_func_present_and_executable


def fetch_message_from_exception(e):
    """Allow us to fetch the readable message from exception"""
    if hasattr(e, 'message') and e.message:
        msg = e.message
    elif hasattr(e, 'description') and e.description:
        msg = e.description
    else:
        msg = str(e)
    return msg


def store_password(obj, enc_pass, server_data, is_tunnel_password=False):
    # Save the encrypted password using the user's login password key.
    update_server_auth = True
    option = {
        'server_id': server_data['id'],
        'gid': server_data['server_group_id'],
        'username': server_data['username'],
        'store_pwd': False,
        'restore_env': False,
        'num_db_options': 0,
        'role': '',
        'db_restriction': '',
        'last_database': '',
        'last_schema': '',
        'ssl_root_cert': '',
        'ssl_rev_list': '',
        'ssl_client_cert': '',
        'ssl_client_key': '',
        'save_password': server_data.get('is_password_saved', False),
        'password': enc_pass if not is_tunnel_password else None,
        'passfile': None,
        'sslcompression': False,
        'fgcolor': None,
        'bgcolor': None,
        'connect_timeout': None,
        'tunnel_password': enc_pass if is_tunnel_password else None,
        'connection_params': server_data.get('connection_params', {})
    }

    sql = render_template(
        "/".join([obj.template_path, 'get_options.sql']),
        server_id=server_data['id'])

    status, rows = obj.pem_conn.execute_scalar(sql)
    if not status:
        current_app.logger.exception(rows)
        return False

    # TODO:: We don't have 'pg_service' in PEM schema yet.
    if int(rows) == 0:
        # insert record for logged in pem user
        sql = render_template("/".join([
            obj.template_path, 'store_options.sql']),
            data=option,
            insert_server_auth=True,
            insert_server_options=True)

        status, res = obj.pem_conn.execute_void(sql)
        if not status:
            current_app.logger.exception(res)
            return False
    else:
        sql = render_template(
            "/".join([obj.template_path, 'get_server_auth.sql']),
            server_id=server_data['id'])
        status, rows = obj.pem_conn.execute_scalar(sql)

        if not status:
            current_app.logger.exception(rows)
            return False

        # If server auth data not found in 'pem.server_auth' table then
        # add the server auth data
        if int(rows) == 0:
            sql = render_template(
                "/".join([obj.template_path, 'store_options.sql']),
                data=option,
                insert_server_auth=True,
                insert_server_options=False)

            status, res = obj.pem_conn.execute_void(sql)
            if not status:
                current_app.logger.exception(res)
                return False
            update_server_auth = False

    if update_server_auth:
        # update password only for logged in pem user
        option = {}
        if is_tunnel_password:
            option['tunnel_password'] = enc_pass
        else:
            option['password'] = enc_pass
            option['save_password'] = False if enc_pass is None else True

        sql = render_template(
            "/".join([obj.template_path, 'update_options.sql']),
            data=option, server_id=server_data['id']
        )

        status, res = obj.pem_conn.execute_void(sql)
        if not status:
            current_app.logger.exception(res)
            return False
    return True


def validate_server_request(
    obj, func, *args, rest_api_param_check=False, **kwargs
):
    # Server Parameters
    server_params = {
        'server': {
            'name': '',
            'server_type': '',
            'version': '',
            'comment': '',
            'host': '',
            'port': 0,
            'db': '',
            'team': '',
            'ssl': 2,
            'hostaddr': '',
            'serviceid': '',
            'is_remote_monitoring': False,
            'tags': [],
            'efm_cluster_name': '',
            'efm_service_name': '',
            'efm_installation_path': '',
            'replication_solution': '',
            'patroni_cluster_name': '',
            'patroni_installation_path': '',
            'patroni_config_path': '',
            'update_last_access_only': False,
            'connect_now': False,
            'alert_blackout': False,
            'post_connection_sql': '',
            'profile_id': None
        },
        'option': {
            'gid': 0,
            'username': '',
            'store_pwd': False,
            'restore_env': False,
            'num_db_options': 0,
            'role': '',
            'db_res': '',
            'last_database': '',
            'last_schema': '',
            'ssl_root_cert': '',
            'ssl_rev_list': '',
            'ssl_client_cert': '',
            'ssl_client_key': '',
            'password': None,
            'save_password': False,
            'passfile': None,
            'sslcompression': False,
            'fgcolor': None,
            'bgcolor': None,
            'use_ssh_tunnel': False,
            'tunnel_host': '',
            'tunnel_port': 22,
            'tunnel_username': '',
            'tunnel_authentication': False,
            'tunnel_identity_file': '',
            'tunnel_password': None,
            'connect_timeout': None,
            'save_tunnel_password': False,
            'kerberos_conn': False,
            'connection_params': {},
        },
        'agent': {
            'agent_id': None,
            'server_id': 0,
            'asb_host': '',
            'asb_port': '',
            'asb_sslmode': '',
            'asb_database': '',
            'asb_username': '',
            'asb_password': None,
            'asb_cpass': None,
            'asb_exclude_databases': [],
            'agent_allowtakeover': False
        },
    }

    if request.data:
        req = json.loads(request.data.decode())
    else:
        req = request.args or request.form

    # checking params if called from Rest Api
    if rest_api_param_check:
        required_args = \
            list(server_params['agent']) + list(server_params['option']) + \
            list(server_params['server']) + ["id"]
        is_bad_request = False
        for arg in req:
            if arg not in required_args or arg == '':
                # If argument not in request or value of argument is blank,
                # then set the is_bad_request to True.
                is_bad_request = True

            if is_bad_request:
                return make_response(
                    status=400,
                    response=gettext(
                        "({}) is not a valid parameter."
                    ).format(arg)
                )

    if 'sid' not in kwargs:
        required_args = [
            u'gid',
            u'name',
        ]

        # Some fields can be provided with service file so they are optional
        # if u'service' in req and not req[u'service']:
        required_args.extend([
            u'port',
            u'host',
            u'hostaddr',
            u'db',
            u'username'
        ])

        is_bad_request = False
        for arg in required_args:
            if arg not in req or req[arg] == '':
                # If argument not in request or value of argument is blank,
                # then set the is_bad_request to True.
                is_bad_request = True

                # But if argument is either host or host address then value
                # for either of one is required else it is a bad request.
                if arg in ['host', 'hostaddr'] \
                        and (req['host'] != '' or req['hostaddr'] != ''):
                    is_bad_request = False

            if is_bad_request:
                return make_response(
                    status=400,
                    response=gettext(
                        "Could not find the required parameter ({})."
                    ).format(arg)
                )

    try:
        for int_param in ('gid', 'port', 'ssl', 'agent_id', 'asb_port'):
            if int_param in req \
                    and req[int_param] is not None and req[int_param] != '':
                req[int_param] = int(req[int_param])
    except ValueError as e:
        return make_response(
            status=400,
            response=str(e)
        )
    try:
        if 'sid' not in kwargs:
            for r in req:
                if r in server_params['server']:
                    server_params['server'][r] = req[r]
                if r in server_params['option']:
                    server_params['option'][r] = req[r]
                if r in server_params['agent']:
                    server_params['agent'][r] = req[r]
                    server_params['agent']['agent_created'] = True
            obj.request = server_params
        else:
            updated_params = {'server': {}, 'option': {}, 'agent': {}}
            for r in req:
                if r in server_params['server']:
                    updated_params['server'][r] = req[r]
                if r in server_params['option']:
                    updated_params['option'][r] = req[r]
            if 'agent_id' in req and (req['agent_id'] is None or
                                      req['agent_id'] == '' or
                                      req['agent_id'] == 0):
                updated_params['agent']['agent_deleted'] = True
            else:
                for r in server_params['agent']:
                    if r in req:
                        updated_params['agent'][r] = req[r]
                        updated_params['agent']['agent_updated'] = True
            obj.request = updated_params

    except Exception as e:
        return internal_server_error(errormsg=str(e))

    return func(obj, **kwargs)


@serverRegistrationRole.check_role(
    msg=gettext("User does not have privileges to create the server.")
)
def create_server(self):
    """
    Utility function create server from object data.
    :param self:
    :param data:
    :return:
    """

    self.pem_conn.execute_void("BEGIN;")

    if 'update_last_access_only' not in self.request['server'] or \
            self.request['server']['update_last_access_only'] is False:
        enc_pass = None
        tunnel_password = ''
        have_password = False
        have_tunnel_password = False
        manager = None
        group_pid = None

        connection_params = convert_connection_parameter(
            self.request['option'].get('connection_params', []))

        # To check ssl configuration
        _, connection_params = check_ssl_fields(connection_params)
        if 'connection_params' in self.request['option']:
            self.request['option']['connection_params'] = connection_params

        if 'password' in self.request['option'] and \
                self.request['option']['password'] != '':
            # If user requested to save password
            if 'save_password' in self.request['option'] and \
                    self.request['option']['save_password']:
                have_password = True
            enc_pass = self.request['option']['password'] = encrypt(
                self.request['option']['password'],
                True
            )

        if 'tunnel_password' in self.request['option'] and \
                self.request['option']["tunnel_password"] != '':
            if self.request['option']['tunnel_password']:
                if 'save_tunnel_password' in self.request['option'] and \
                        self.request['option']["save_tunnel_password"]:
                    have_tunnel_password = True

                tunnel_password = self.request['option']['tunnel_password']

                key = '{}{}'.format(
                    self.request['option']['tunnel_username'],
                    self.pem_conn.manager.password)

                tunnel_password = encrypt(
                    tunnel_password, True, key
                )
                self.request['option']['tunnel_password'] = tunnel_password
            else:
                tunnel_password = ''
        if not self.request['server'].get('replication_solution'):
            self.request['server']['efm_cluster_name'] = ''
            self.request['server']['efm_service_name'] = ''
            self.request['server']['efm_installation_path'] = ''
            self.request['server']['patroni_cluster_name'] = ''
            self.request['server']['patroni_installation_path'] = ''
            self.request['server']['patroni_config_path'] = ''
        elif self.request['server']['replication_solution'] == 'efm':
            self.request['server']['patroni_cluster_name'] = ''
            self.request['server']['patroni_installation_path'] = ''
            self.request['server']['patroni_config_path'] = ''
        elif self.request['server']['replication_solution'] == 'patroni':
            self.request['server']['efm_cluster_name'] = ''
            self.request['server']['efm_service_name'] = ''
            self.request['server']['efm_installation_path'] = ''

        # Store the main server definition
        sql = render_template(
            "/".join([self.template_path, 'create.sql']),
            data=self.request['server']
        )

        status, server_id = self.pem_conn.execute_scalar(sql)

        if not status:
            self.pem_conn.execute_void("ROLLBACK;")
            current_app.logger.exception(server_id)
            return False, server_id, None, False, None

        self.request['server']['server_id'] = server_id

        sql = render_template(
            "/".join([self.template_path, 'get_options.sql']),
            server_group_id=self.request['option']['gid']
        )

        status, server_group_res = self.pem_conn.execute_dict(sql)

        if not status:
            self.pem_conn.execute_void("ROLLBACK;")
            current_app.logger.exception(server_group_res)

            return False, server_group_res, None, False, None

        if len(server_group_res['rows']) > 0:
            server_group_name = server_group_res['rows'][0]['name']
            group_pid = server_group_res['rows'][0]['parent_id']
        else:
            return False, gettext("Server group not found"), None, False, None

        self.request['option']['server_group_name'] = server_group_name

        sql = render_template(
            "/".join([self.template_path, 'get_options.sql']),
            server_id=server_id)

        status, rows = self.pem_conn.execute_scalar(sql)
        if not status:
            self.pem_conn.execute_void("ROLLBACK;")
            current_app.logger.exception(rows)
            return False, rows, None, False, None

        if int(rows) == 0:
            sql = render_template(
                "/".join([self.template_path, 'get_owner.sql']),
                server_id=server_id
            )

            status, is_owner = self.pem_conn.execute_scalar(sql)
            if not status:
                self.pem_conn.execute_void("ROLLBACK;")
                current_app.logger.exception(is_owner)
                return False, is_owner, None, False, None

            if not (config.ALLOW_SAVE_PASSWORD and have_password):
                self.request['option']['password'] = None

            if not (config.ALLOW_SAVE_TUNNEL_PASSWORD and
                    have_tunnel_password):
                self.request['option']['tunnel_password'] = None

            is_owner = is_owner != 0
            if ('db_res' in self.request['option'] and
                    isinstance(self.request['option']['db_res'], list)):
                self.request['option']['db_res'] = (
                    ','.join(self.request['option']['db_res']))
            # TODO:: We don't have 'pg_service' in PEM schema yet.
            if not is_owner:
                sql = render_template("/".join([
                    self.template_path, 'get_options.sql']),
                    data=self.request['option']
                )

                status, is_different = (
                    self.pem_conn.execute_scalar(sql) is True
                )
                if not status:
                    self.pem_conn.execute_void("ROLLBACK;")
                    current_app.logger.exception(is_different)
                    return False, is_different, None, False, None

                if is_different:
                    sql = render_template("/".join([
                        self.template_path, 'store_options.sql']),
                        data=self.request['option'],
                        insert_server_auth=True,
                        insert_server_options=True)

                    status, res = self.pem_conn.execute_void(sql)
                    if not status:
                        self.pem_conn.execute_void("ROLLBACK;")
                        current_app.logger.exception(res)
                        return False, res, None, False, None
            else:
                self.request['option']['server_id'] = server_id
                sql = render_template("/".join([
                    self.template_path, 'store_options.sql']),
                    data=self.request['option'],
                    insert_server_auth=True,
                    insert_server_options=True)

                status, res = self.pem_conn.execute_void(sql)
                if not status:
                    self.pem_conn.execute_void("ROLLBACK;")
                    current_app.logger.exception(res)
                    return False, res, None, False, None

        # Agent Binding
        if (
            self.request['agent'] and len(self.request['agent']) > 0 and
            'agent_id' in self.request['agent'] and
            self.request['agent']['agent_id'] is not None and
            int(self.request['agent']['agent_id']) > 0
        ):
            status, res = agent_binding(self, server_id,
                                        self.request['agent'])
            if not status:
                self.pem_conn.execute_void("ROLLBACK;")
                current_app.logger.exception(res)
                return False, res, None, False, None

        connected = False
        manager = get_driver(
            config.PG_DEFAULT_DRIVER
        ).connection_manager(server_id)
        if self.request['server']['connect_now']:
            manager.update()
            conn = manager.connection()

            status, errmsg = conn.connect(
                password=enc_pass,
                tunnel_password=tunnel_password,
                server_types=ServerType.types()
            )

            if not status:
                self.pem_conn.execute_void("ROLLBACK;")
                current_app.logger.exception(errmsg)
                return False, errmsg, None, False, None

            connected = True

    self.pem_conn.execute_void("COMMIT;")

    # If a profile was assigned during creation, perform an immediate
    # materialized view refresh so UI components depending on
    # pem.probe_target_view see the new profile's probes without waiting
    # for the scheduled job.
    try:
        if self.request['server'].get('profile_id') is not None:
            status, err = self.pem_conn.execute_void(
                "SELECT pem.refresh_stale_probe_view();"
            )
            if not status:
                current_app.logger.warning(
                    "Immediate probe view refresh after "
                    "server create failed: %s", err
                )
    except Exception as e:  # Defensive; refresh failure shouldn't abort create
        current_app.logger.warning(
            "Exception during immediate probe view "
            "refresh after server create: %s", e
        )
    return True, server_id, group_pid, connected, manager


def update_server(self, obj, sid):
    try:
        profile_id_before = None
        self.pem_conn.execute_void("BEGIN;")

        sql = render_template(
            "/".join([self.template_path, 'properties.sql']), sid=sid,
            schema_version=current_user.schema_version
        )

        status, rows = self.pem_conn.execute_dict(sql)
        if not status:
            self.pem_conn.execute_void("ROLLBACK;")
            current_app.logger.exception(rows)
            return False, 500, rows

        if len(rows['rows']) > 0:
            server = rows['rows'][0]
            profile_id_before = server.get('profile_id')
        else:
            return False, 404, gettext("Server not found")

        if 'gid' in self.request['option']:
            sql = render_template(
                "/".join([self.template_path, 'get_options.sql']),
                server_group_id=self.request['option']['gid'])

            status, server_group_res = self.pem_conn.execute_dict(sql)

            if not status:
                current_app.logger.exception(server_group_res)
                return False, 500, server_group_res

            if len(server_group_res['rows']) > 0:
                server_group_name = server_group_res['rows'][0]['name']
                server_group_parent_id = server_group_res[
                    'rows'][0]['parent_id']
            else:
                return False, 404, gettext("Server not found")

            self.request['option']['server_group_name'] = server_group_name
            # We have to update gid in response as well
            server['gid'] = self.request['option']['gid']
            server['group_pid'] = server_group_parent_id

        if 'replication_solution' in self.request['server']:
            if self.request['server']['replication_solution'] not in \
                    ['efm', 'patroni', 'none', '']:
                return False, 400, gettext(
                    "Invalid replication solution specified."
                )
            if self.request['server']['replication_solution'] in ['none', '']:
                self.request['server']['efm_cluster_name'] = ''
                self.request['server']['efm_service_name'] = ''
                self.request['server']['efm_installation_path'] = ''
                self.request['server']['patroni_cluster_name'] = ''
                self.request['server']['patroni_installation_path'] = ''
                self.request['server']['patroni_config_path'] = ''
            elif self.request['server']['replication_solution'] == 'efm':
                self.request['server']['patroni_cluster_name'] = ''
                self.request['server']['patroni_installation_path'] = ''
                self.request['server']['patroni_config_path'] = ''
            elif self.request['server']['replication_solution'] == 'patroni':
                self.request['server']['efm_cluster_name'] = ''
                self.request['server']['efm_service_name'] = ''
                self.request['server']['efm_installation_path'] = ''

        if 'update_last_access_only' not in self.request['server'] or \
                self.request['server']['update_last_access_only'] is False:
            if serverRegistrationRole.has_role():
                can_update = False
                if (
                    (current_user.schema_version >= 201111101) and
                    ((server['server_owner'] is not None) and
                     session['username'] == server['server_owner']) or
                    current_user.is_super_admin
                ):
                    can_update = True

                if self.request['server'] and len(self.request['server']) > 0:
                    if 'tags' in obj:
                        update_tags(obj, server)
                        server['tags'] = obj['tags']

                    sql = render_template(
                        "/".join([self.template_path, 'update.sql']),
                        data=obj, server_id=sid,
                        canupdate=can_update
                    )

                    status, server_id = self.pem_conn.execute_scalar(sql)
                    if not status:
                        self.pem_conn.execute_void("ROLLBACK;")
                        current_app.logger.exception(server_id)
                        return False, 500, server_id

                # TODO:: We don't have 'pg_service' in PEM schema yet.
                if self.request['option'] and len(self.request['option']) > 0:
                    status, res = self.pem_conn.execute_scalar(
                        render_template(
                            "/".join([self.template_path, 'get_options.sql']),
                            server_id=sid
                        )
                    )
                    if not status:
                        self.pem_conn.execute_void("ROLLBACK;")
                        current_app.logger.error(res)
                        return False, 500, res

                    if ('db_res' in self.request['option'] and isinstance(
                            self.request['option']['db_res'], list)):
                        self.request['option']['db_res'] = (
                            ','.join(self.request['option']['db_res']))

                    if int(res) == 0:
                        req = self.request['option']
                        data = dict({
                            'server_id': sid,
                            'store_pwd': 'false',
                            'restore_env': 'false',
                            'password': None,
                            'save_password': False,
                            'sslcompression': req['sslcompression']
                            if 'sslcompression' in self.request['option']
                            else False
                        })
                        for opt in ['last_database', 'last_schema',
                                    'fgcolor', 'bgcolor']:
                            data[opt] = ''

                        for opt in [
                            'username', 'gid', 'db_restriction', 'role',
                            'ssl_root_cert', 'ssl_rev_list',
                            'ssl_client_cert', 'ssl_client_key',
                            'passfile',
                            'use_ssh_tunnel', 'tunnel_host', 'tunnel_port',
                            'tunnel_username', 'tunnel_authentication',
                            'tunnel_identity_file', 'connect_timeout',
                            'tunnel_password', 'kerberos_conn',
                            'connection_params'
                        ]:
                            if opt in req:
                                data[opt] = req[opt]
                            elif opt in server and server[opt]:
                                data[opt] = server[opt]
                            else:
                                data[opt] = None
                        update_connection_parameter(data, server)
                        sql = render_template(
                            "/".join(
                                [self.template_path, 'store_options.sql']),
                            data=data,
                            insert_server_auth=True,
                            insert_server_options=True
                        )
                    else:
                        # Update Server Option
                        if current_user.schema_version < 202104021:
                            self.request['option'].pop('kerberos_conn')

                        update_connection_parameter(self.request['option'],
                                                    server)
                        if 'username' in self.request['option'] and \
                            self.request['option']['username'] != '' and \
                            rows['rows'][0]['username'] != \
                                self.request['option']['username']:
                            # New user and old user are different so
                            # clear password and passfile for old user.
                            self.request['option']['password'] = None
                            self.request['option']['passfile'] = None
                            self.request['option']['save_password'] = False

                        sql = render_template(
                            "/".join(
                                [self.template_path, 'update_options.sql']),
                            data=self.request['option'], server_id=sid
                        )

                    if sql != '':
                        status, res = self.pem_conn.execute_void(sql)
                        if not status:
                            self.pem_conn.execute_void("ROLLBACK;")
                            current_app.logger.exception(res)
                            return False, 500, res

                # Agent Binding
                if self.request['agent'] and len(self.request['agent']) > 0:
                    status, res = (
                        agent_binding(self, sid, self.request['agent']))
                    if not status:
                        self.pem_conn.execute_void("ROLLBACK;")
                        current_app.logger.exception(res)
                        return False, 500, res
        # After successful update, decide on immediate refresh
        try:
            profile_id_after = (
                self.request.get('server', {}).get('profile_id')
                if 'server' in self.request else None
            )
            if (
                'server' in self.request and
                'profile_id' in self.request['server'] and
                profile_id_before != profile_id_after and
                profile_id_after is not None
            ):
                status, err = self.pem_conn.execute_void(
                    "SELECT pem.refresh_stale_probe_view();"
                )
                if not status:
                    current_app.logger.warning(
                        "Immediate probe view refresh after "
                        "server profile change failed: %s", err
                    )
        except Exception as e_inner:
            current_app.logger.warning(
                "Exception during immediate probe view refresh "
                "after server update: %s", e_inner
            )
    except Exception as e:
        self.pem_conn.execute_void("ROLLBACK;")
        current_app.logger.exception(e)
        return False, 500, str(e)
    finally:
        self.pem_conn.execute_void("end;")
    return True, 200, server


def update_connection_parameter(data, server):
    """
    This function is used to update the connection parameters.
    """
    if 'connection_params' in data and 'connection_params' in server:
        existing_conn_params = json.loads(server['connection_params'])
        if isinstance(existing_conn_params, str):
            existing_conn_params = json.loads(existing_conn_params)
        new_conn_params = data['connection_params']

        if 'deleted' in new_conn_params:
            for item in new_conn_params['deleted']:
                existing_conn_params.pop(item['name'], None)

        if 'added' in new_conn_params:
            for item in new_conn_params['added']:
                existing_conn_params[item['name']] = item['value']

        if 'changed' in new_conn_params:
            for item in new_conn_params['changed']:
                existing_conn_params[item['name']] = item['value']

        data['connection_params'] = existing_conn_params


def encrypt_asb_password(obj, server_id, data):
    """
    This function is used to encrypt ASB password

    :param obj:
    :param server_id:
    :param data: data of agent binding request
    """

    agent_id = data.get('agent_id', None)
    if agent_id is None:
        sql = "SELECT \
                agent_id FROM pem.agent_server_binding \
                WHERE server_id = %s::int"
        status, agent = obj.pem_conn.execute_dict(sql, (server_id,))
        if not status:
            current_app.logger.exception(agent)
            return internal_server_error(errormsg=agent)

        if len(agent['rows']) == 0:
            return False, Exception("Invalid server id.")

        agent_id = agent['rows'][0]['agent_id']

    if agent_id is None:
        return False, Exception("Agent id missing in the "
                                "agent-server binding information.")

    # get PEM agent version
    sql = "SELECT \
            supported_schema FROM pem.agent_runtime \
            WHERE agent_id = %s::int"
    status, agent = obj.pem_conn.execute_dict(sql, (agent_id,))
    if not status:
        current_app.logger.exception(agent)
        return internal_server_error(errormsg=agent)

    agent_schema_version = None
    if len(agent['rows']) > 0:
        agent_schema_version = agent['rows'][0]['supported_schema']
    else:
        current_app.logger.warning(
            "Couldn't find the schema version of the "
            "agent (id#{0}) in the PEM database.".format(
                agent_id
            )
        )

    if agent_schema_version is not None and agent_schema_version <= 202508141:
        data['asb_password'] = encrypt(
            data['asb_password'], False, None, '20110912'
        )
    else:
        data['asb_password'] = encrypt(
            data['asb_password'], False
        )

    return True, None


def agent_binding(obj, server_id, data):
    """
    Utility function to bind given server to agent.

    :param obj:
    :param server_id:
    :param data:
    :return:
    """
    if 'server_id' not in data or (
        'server_id' in data and int(data['server_id']) <= 0
    ):
        data['server_id'] = server_id

    if not current_user.is_admin:
        return True, None

    sql = ''
    if ('agent_created' in data and data['agent_created']) or \
            ('agent_updated' in data and data['agent_updated']):

        sql = render_template("/".join([
            obj.template_path, 'get_agent_server_binding.sql']),
            server_id=server_id)

        status, rows = obj.pem_conn.execute_scalar(sql)
        if not status:
            return status, rows

        # Encrypt agent password
        if 'asb_password' in data and data['asb_password'] is not None \
                and data['asb_password'] != '':
            status, res = encrypt_asb_password(obj, server_id, data)
            if not status:
                return status, res

        status, res = exclude_database(obj, server_id, data)
        if not status:
            return status, res

        data['asb_exclude_databases'] = res

        if int(rows) == 0:
            # This is a bad idea but no other way found to handle this case
            if 'agent_allowtakeover' not in data:
                data['agent_allowtakeover'] = False
            if 'asb_password' not in data or \
                    data['asb_password'] == '':
                data['asb_password'] = None

            if data.get('asb_port', None) is None:
                return False, Exception("Server Port missing in the "
                                        "agent-server binding information.")

            sql = render_template("/".join([
                obj.template_path, 'store_agent_server_binding.sql']),
                data=data)
        else:
            sql = render_template("/".join([
                obj.template_path, 'update_agent_server_binding.sql']),
                data=data)

        status, res = obj.pem_conn.execute_void(sql)
        if not status:
            return status, res
    elif 'agent_deleted' in data and data['agent_deleted']:
        sql = render_template("/".join([
            obj.template_path, 'delete_agent_server_binding.sql']),
            server_id=server_id)

        status, res = obj.pem_conn.execute_void(sql)
        if not status:
            return status, res

    return True, None


def exclude_database(obj, server_id, data):
    """
    Utility function to handle exclude database operations
    :param obj:
    :param server_id:
    :param data:
    :return:
    """
    new_db = []
    deleted_db = []
    old_ex_dbs = []

    # get current excluded databases
    sql = render_template("/".join([
        obj.template_path, 'exclude_databases.sql']),
        server_id=server_id)

    status, res = obj.pem_conn.execute_dict(sql)
    if not status:
        return False, internal_server_error(res)

    if len(res['rows']) > 0:
        asb_database = res['rows'][0]['database']
        old_ex_dbs = res['rows'][0]['exclude_databases']
    if 'asb_database' in data:
        asb_database = data['asb_database']

    if 'asb_exclude_databases' in data and len(
        data['asb_exclude_databases']
    ) > 0:
        if 'added' in data['asb_exclude_databases']:
            for added_db in data['asb_exclude_databases']['added']:
                db_to_add = added_db['exclude_database']
                if db_to_add in old_ex_dbs:
                    return False, gettext("The database '%s' is already "
                                          "added in excluded databases"
                                          ) % db_to_add
                new_db.append(db_to_add)
            if asb_database in new_db:
                return False, gettext("The database specified in the PEM "
                                      "Agent connection parameters cannot "
                                      "be part of excluded databases."
                                      )

            old_ex_dbs.extend(new_db)

        if 'deleted' in data['asb_exclude_databases']:
            for del_db in data['asb_exclude_databases']['deleted']:
                deleted_db.append(del_db['exclude_database'])
            old_ex_dbs = [db for db in old_ex_dbs if db not in deleted_db]

        if 'changed' in data['asb_exclude_databases']:
            for changed_db in data['asb_exclude_databases']['changed']:
                new_db.append(changed_db['exclude_database'])
            if asb_database in new_db:
                return False, gettext("The database specified in the PEM "
                                      "Agent connection parameters cannot "
                                      "be part of excluded databases."
                                      )

            old_ex_dbs.extend(new_db)

    return True, old_ex_dbs


def update_tags(data, server):
    """
    This function is used to update tags
    """
    import ast
    server['tags'] = ast.literal_eval(server['tags'])
    old_tags = server.get('tags', [])
    if isinstance(old_tags, str):  # Ensure it is a list
        old_tags = ast.literal_eval(old_tags)
    # add old_text for comparison
    old_tags = [{**tag, 'old_text': tag['text']}
                for tag in old_tags] if old_tags is not None else []
    new_tags_info = data.get('tags', None)

    def update_tag(tags, changed):
        for i, item in enumerate(tags):
            if item['old_text'] == changed['old_text']:
                item = {**item, **changed}
                tags[i] = item
                break

    if new_tags_info:
        deleted_ids = [t['old_text']
                       for t in new_tags_info.get('deleted', [])]
        if len(deleted_ids) > 0:
            old_tags = [
                t for t in old_tags if t['old_text'] not in deleted_ids
            ]

        for item in new_tags_info.get('changed', []):
            update_tag(old_tags, item)

        for item in new_tags_info.get('added', []):
            old_tags.append(item)

        # remove the old_text key
        data['tags'] = [
            {k: v for k, v in tag.items()
             if k != 'old_text'} for tag in old_tags
        ]
