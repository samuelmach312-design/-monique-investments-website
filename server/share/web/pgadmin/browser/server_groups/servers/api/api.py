##########################################################################
#
# Postgres Enterprise Manager
#
# Copyright (C) 2016 - 2025, EnterpriseDB Corporation. All rights reserved.
#
##########################################################################


""" Api for objects """

from flask_babel import gettext
from flask import render_template, current_app, request
from functools import wraps
import json

from pgadmin.browser.server_groups.servers.pem.utils import \
    validate_server_request, create_server, update_server, \
    fetch_message_from_exception
from pgadmin.utils.ajax import make_response, precondition_required, \
    internal_server_error, make_json_response, success_return, bad_request
from pgadmin.pem.api.utils import ApiView
from pgadmin.pem.utils import is_object_exists, is_agent_exists
from flask_security import current_user

api_versions_v2 = list(ApiView.api_versions)[1:13]
api_versions_v3 = list(ApiView.api_versions)[13:14]
api_versions_v4 = list(ApiView.api_versions)[14:]

ALLOWED_CONNECTION_PARAM_KEYWORDS = {
    "hostaddr",
    "channel_binding",
    "connect_timeout",
    "client_encoding",
    "options",
    "application_name",
    "fallback_application_name",
    "keepalives",
    "keepalives_idle",
    "keepalives_interval",
    "keepalives_count",
    "tcp_user_timeout",
    "tty",
    "replication",
    "gssencmode",
    "sslmode",
    "sslcompression",
    "sslcert",
    "sslkey",
    "sslpassword",
    "sslrootcert",
    "sslcrl",
    "sslcrldir",
    "sslsni",
    "requirepeer",
    "ssl_min_protocol_version",
    "ssl_max_protocol_version",
    "krbsrvname",
    "gsslib",
    "target_session_attrs",
    "load_balance_hosts"
}


def check_precondition(f):
    """
    Works as a decorator.
    Checks the database connection status.
    Attaches the connection object and template path to the class object.
    """

    @wraps(f)
    def wrap(*args, **kwargs):
        """
        Responsible for making PEM connection object and template path
        """
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

        # we will set template path for sql scripts
        self.template_path = 'servers/sql'

        return f(*args, **kwargs)

    return wrap


class ServerApiV1View(ApiView):
    """
    A server api view with CRUD operations.
    """

    endpoint = 'server_v1'

    url = '/server/'

    pk = 'sid'

    methods = ['GET', 'DELETE', 'POST', 'PUT']

    api_versions = ['v1_api']

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

        @wraps(f)
        def wrap(self, **kwargs):
            """Validates request"""

            return validate_server_request(
                self, f, rest_api_param_check=True, **kwargs)

        return wrap

    @staticmethod
    def is_not_empty(field):
        """
        Validates value

        :param field: Any string
        :return: True/False
        """
        return len(field.strip().strip('\n')) > 0

    @staticmethod
    def is_valid_port_value(port):
        """
        Validates maximum and minimum port value

        :param port: Server Port
        :return: True/False
        """
        return 1024 <= port <= 65535

    def validate_required_server_fields(self):
        """
        This function validates the provided data in API

        :return: True/False, Error message
        """
        server_request_data = self.request['server']
        agent_request_data = self.request['agent']
        option_request_data = self.request['option']

        server_required_args = [
            'name', 'host', 'port', 'database',
            'username', 'gid'
        ]

        for arg in server_required_args:
            if arg in server_request_data:
                is_data_valid = ServerApiV1View.is_valid_port_value(
                    server_request_data[arg]
                ) if arg == 'port' else ServerApiV1View.is_not_empty(
                    server_request_data[arg]
                )

                if not is_data_valid:
                    return False, 400, gettext(
                        "The required server field {0} is not valid".format(
                            arg
                        )
                    )

        # If agent_id is provided then check agent required fields
        agent_id = agent_request_data.get('agent_id', None)
        if agent_id is not None:
            agent_exist = is_agent_exists(self.pem_conn, agent_id)
            if not agent_exist:
                return False, 404, \
                    gettext("The specified agent_id is not valid")

            agent_required_args = [
                'asb_host', 'asb_port',
                'asb_username', 'asb_database'
            ]

            for arg in agent_required_args:
                if arg in agent_request_data:
                    is_data_valid = ServerApiV1View.is_valid_port_value(
                        agent_request_data[arg]
                    ) if 'asb_port' in arg else ServerApiV1View.is_not_empty(
                        agent_request_data[arg]
                    )

                    if not is_data_valid:
                        return False, 400, gettext(
                            "The required agent field {0} "
                            "is not valid".format(arg)
                        )

        # Check for the required properties for replication solution
        if 'replication_solution' in server_request_data:
            replication_solution = server_request_data['replication_solution']

            # Validate for EFM
            if replication_solution == 'efm':
                required_fields = ['efm_cluster_name', 'efm_installation_path']
                missing_fields = [
                    field for field in required_fields
                    if field not in server_request_data or
                    not server_request_data[field]
                ]
                if missing_fields:
                    return False, 400, gettext(
                        "Missing required fields for EFM "
                        "replication solution: {fields}"
                    ).format(fields=', '.join(missing_fields))

            # Validate for Patroni
            elif replication_solution == 'patroni':
                required_fields = [
                    'patroni_cluster_name',
                    'patroni_installation_path',
                    'patroni_config_path'
                ]
                missing_fields = [
                    field for field in required_fields
                    if field not in server_request_data or
                    not server_request_data[field]
                ]
                if missing_fields:
                    return False, 400, gettext(
                        "Missing required fields for Patroni "
                        "replication solution: {fields}"
                    ).format(fields=', '.join(missing_fields))

            # Skip validation if replication_solution is None
            elif replication_solution in [None, '', 'none']:
                server_request_data['replication_solution'] = ''

            # Handle invalid replication_solution values
            else:
                return False, 400, gettext(
                    "Invalid replication solution: {solution}"
                ).format(solution=replication_solution)

        # if use_ssh_tunnel is true, then check required fields
        if 'use_ssh_tunnel' in option_request_data and \
                option_request_data['use_ssh_tunnel'] is True:
            ssh_tunnel_required_args = [
                'tunnel_host',
                'tunnel_username', 'tunnel_password'
            ]

            for arg in ssh_tunnel_required_args:
                if arg not in option_request_data or \
                        option_request_data[arg] == '':
                    return False, 404, gettext(
                        "The required ssh_tunnel field {0} "
                        "is not provided".format(arg)
                    )
            if 'tunnel_port' not in option_request_data:
                return False, 404, gettext(
                    "tunnel_port not provided")

            if 'tunnel_authentication' in option_request_data and \
                    option_request_data['tunnel_authentication'] is True:

                if 'tunnel_identity_file' not in option_request_data \
                        or option_request_data['tunnel_identity_file'] == '':
                    return False, 404, gettext(
                        "tunnel_identity_file not provided")

        return True, None, None

    def validate_connection_params(self, conn_params):
        """
        Validates that all connection_params have allowed keywords and names.
        """

        def _validate_param_list(param_list):
            for param in param_list:
                keyword = param.get('keyword')
                name = param.get('name')
                if keyword not in ALLOWED_CONNECTION_PARAM_KEYWORDS:
                    return False, (f"Invalid connection parameter "
                                   f"keyword: {keyword}")
                if name not in ALLOWED_CONNECTION_PARAM_KEYWORDS:
                    return False, f"Invalid connection parameter name: {name}"
                if keyword != name:
                    return False, (f"Connection parameter 'keyword' and "
                                   f"'name' must be the same: "
                                   f"got '{keyword}' and '{name}'")
            return True, None
        # If it's a dict with 'added', 'changed', 'deleted' keys (PUT)
        if isinstance(conn_params, dict):
            for key in ['added', 'changed', 'deleted']:
                param_list = conn_params.get(key, [])
                is_valid, err = _validate_param_list(param_list)
                if not is_valid:
                    return False, err
            return True, None
        # If it's a list (POST)
        elif isinstance(conn_params, list):
            return _validate_param_list(conn_params)
        else:
            return False, "Invalid format for connection_params"

    @check_precondition
    def get(self, sid=None):
        """
        Responsible for fetching and listing server resource

        :param sid: Server id
        :return: JSON response
        """
        # Check the given object is exist or not.
        if sid is not None:
            object_exist, msg = is_object_exists(self.pem_conn, 'server', sid)
            if not object_exist:
                return make_json_response(
                    status=404, success=0, errormsg=msg
                )

        def transform(data):

            # Following keys needs not to be exposed in the REST API
            for key in [
                'store_pwd', 'restore_env', 'last_database', 'last_schema',
                'ssl_root_cert', 'ssl_rev_list', 'ssl_client_cert',
                'ssl_client_key', 'passfile', 'tunnel_password',
                # connect_timeout was added after v1 api so exclude it from v2
                'connect_timeout'
            ]:
                del data[key]

            res = dict()
            # v1 api fields

            res["username"] = data["username"]
            res["option_pem_username"] = data["option_pem_username"]
            res["gid"] = data["gid"]
            res["asb_username"] = data["asb_username"]
            res["host"] = data["host"]
            res["server_owner"] = data["server_owner"]
            res["database"] = data["database"]
            res["active"] = data["active"]
            res["owner"] = data["owner"]
            res["is_remote_monitoring"] = data["is_remote_monitoring"]
            res["hostaddr"] = data["hostaddr"]
            res["port"] = data["port"]
            res["efm_service_name"] = data["efm_service_name"]
            res["role"] = data["role"]
            res["comment"] = data["comment"]
            res["team"] = data["team"]
            # res["service"] = data["service"]
            res["asb_password"] = data["asb_password"]
            res["efm_cluster_name"] = data["efm_cluster_name"]
            res["db_restriction"] = data["db_restriction"]
            res["asb_database"] = data["asb_database"]
            res["asb_host"] = data["asb_host"]
            res["ssl"] = data["ssl"]
            res["is_edb"] = data["is_edb"]
            res["agent_id"] = data["agent_id"]
            res["name"] = data["name"]
            res["alert_blackout"] = data["alert_blackout"]
            res["asb_port"] = data["asb_port"]
            res["agent_description"] = data["agent_description"]
            res["server_group_name"] = data["server_group_name"]
            res["id"] = data["id"]
            res["agent_capability_list"] = data["agent_capability_list"]
            res["agent_allowtakeover"] = data["agent_allowtakeover"]
            res["asb_sslmode"] = data["asb_sslmode"]
            res["serviceid"] = data["serviceid"]
            res["efm_installation_path"] = data["efm_installation_path"]
            res["post_connection_sql"] = data["post_connection_sql"]
            return res

        SQL = render_template(
            "/".join([self.template_path, 'properties.sql']),
            sid=sid
        )
        status, res = self.pem_conn.execute_dict(SQL)

        if not status:
            return internal_server_error(res)

        if sid is not None:
            if len(res['rows']) == 0:
                return bad_request(gettext("Server not found."))
            return make_response(transform(res['rows'][0]))

        return make_response([transform(row) for row in res['rows']])

    @check_precondition
    @validate_request
    def post(self):
        """
        Responsible for creating server resource

        :return: JSON response
        """
        try:
            is_data_valid, st_code, msg = \
                self.validate_required_server_fields()
            if not is_data_valid:
                return make_json_response(
                    status=st_code, success=0, errormsg=msg
                )
            default_connection_params = [
                {
                    "name": "sslmode",
                    "value": "prefer",
                    "keyword": "sslmode",
                },
                {
                    "name": "connect_timeout",
                    "value": 10,
                    "keyword": "connect_timeout",
                }
            ]
            option = self.request.get('option', {})
            conn_params = option.get('connection_params', None)
            server_request_data = self.request['server']
            if 'tags' in server_request_data and server_request_data['tags']:
                for tag in server_request_data['tags']:
                    if (not isinstance(tag, dict) or 'text' not in
                            tag or 'color' not in tag):
                        return make_json_response(
                            status=400, success=0, errormsg=gettext(
                                "Each tag must contain 'text' and "
                                "'color' properties"
                            ))
            if conn_params is not None:
                if not conn_params:
                    # If empty, set to default
                    option['connection_params'] = default_connection_params
                else:
                    # Validate all keywords
                    is_valid, err = (
                        self.validate_connection_params(conn_params))
                    if not is_valid:
                        return make_json_response(
                            status=400, success=0, errormsg=err
                        )
                    # Add missing defaults
                    existing_keywords = {d.get('keyword') for d in conn_params}
                    for param in default_connection_params:
                        if param['keyword'] not in existing_keywords:
                            conn_params.append(param)
                    option['connection_params'] = conn_params
                self.request['option'] = option
            if (self.endpoint != 'server_v4' and 'profile_id'
                    in self.request['server']):
                return make_json_response(
                    status=400, success=0,
                    errormsg=gettext(
                        "'profile_id' is not supported in POST requests.")
                )
            elif 'profile_id' in self.request['server']:
                sql = (
                    "SELECT count(*) FROM pem.profile WHERE id = %s AND "
                    "status = 'published' AND "
                    "target_kind = 's';"
                )
                status, res = self.pem_conn.execute_scalar(
                    sql, (self.request['server']['profile_id'],)
                )
                if not status:
                    return internal_server_error(res)
                if int(res) == 0:
                    return make_json_response(
                        status=400, success=0,
                        errormsg=str(
                            "Provided profile_id not found, not published, "
                            "or not a server profile")
                    )

            status, server_id, *_ = (
                create_server(self))  # Removed unused variables

            if not status:
                return internal_server_error(server_id)

            return make_json_response(
                data={'server_id': server_id},
                info=gettext("Server created successfully.")
            )
        except Exception as e:
            self.pem_conn.execute_void("ROLLBACK;")
            current_app.logger.exception(e)
            return internal_server_error(e)

    @check_precondition
    @validate_request
    def put(self, sid):
        """
        Responsible for updating server resource

        :param sid: Server ID
        :return: JSON response
        """
        object_exist, msg = is_object_exists(self.pem_conn, 'server', sid)
        if not object_exist:
            return make_json_response(
                status=404, success=0, errormsg=msg
            )

        is_data_valid, st_code, msg = self.validate_required_server_fields()
        if not is_data_valid:
            return make_json_response(
                status=st_code, success=0, errormsg=msg
            )

        option = self.request.get('option', {})
        conn_params = option.get('connection_params', None)
        if conn_params is not None:
            # Only validate, do not add defaults
            is_valid, err = self.validate_connection_params(conn_params)
            if not is_valid:
                return make_json_response(
                    status=400, success=0, errormsg=err
                )
            option['connection_params'] = conn_params
            self.request['option'] = option
        data = self.request['server']
        if self.endpoint != 'server_v4' and 'profile_id' in data:
            return internal_server_error("Invalid param profile_id")
        elif 'profile_id' in data:
            sql = ("SELECT count(*) FROM pem.profile WHERE id = %s AND "
                   "status = 'published' AND "
                   "target_kind = 's';")
            status, res = (
                self.pem_conn.execute_scalar(sql, (data['profile_id'],)))
            if not status:
                return internal_server_error(res)
            if int(res) == 0:
                return make_json_response(
                    status=400, success=0,
                    errormsg=str(
                        "Provided profile_id not found, not published, "
                        "or is not a server profile")
                )
        status, code, res = update_server(self, data, sid)

        if not status:
            if code == 500:
                return internal_server_error(res)
            return make_response(
                response=res,
                status=code)

        return make_json_response(
            data={'server_id': res['id']},
            info=gettext("Server updated successfully.")
        )

    @check_precondition
    def delete(self, sid):
        """
        Responsible for deleting server resource

        :param sid: Server ID
        :return: JSON response
        """
        object_exist, msg = is_object_exists(self.pem_conn, 'server', sid)
        if not object_exist:
            return make_json_response(
                status=404, success=0, errormsg=msg
            )

        sql = render_template(
            "/".join([self.template_path, 'delete.sql']), sid=sid
        )
        status, res = self.pem_conn.execute_void(sql)
        if not status:
            return internal_server_error(res)

        # create a scheduled job to delete all probe data for the server
        try:
            from pgadmin.browser.server_groups.agents.jobs.utils \
                import create_purge_job
            create_purge_job(self.pem_conn, sid=sid)
        except Exception as e:
            current_app.logger.exception(e)
            return internal_server_error(
                errormsg=fetch_message_from_exception(e))

        return success_return(message=gettext('Server deleted successfully.'))


class ServerApiV2View(ServerApiV1View):
    """
    A server api view with CRUD operations.
    """
    endpoint = 'server_v2'

    # Api version from v2 till v13
    # ['v2_api', 'v3_api', 'v4_api', 'v5_api', 'v6_api', 'v7_api', 'v8_api']
    api_versions = api_versions_v2

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

    @check_precondition
    def get(self, sid=None):
        """
        Responsible for fetching and listing server resource

        :param sid: Server id
        :return: JSON response
        """
        # Check the given object is exist or not.
        if sid is not None:
            object_exist, msg = is_object_exists(self.pem_conn, 'server', sid)
            if not object_exist:
                return make_json_response(
                    status=404, success=0, errormsg=msg
                )

        def transform(data):

            # Following keys needs not to be exposed in the REST API
            for key in [
                'store_pwd', 'restore_env', 'last_database', 'last_schema',
                'ssl_root_cert', 'ssl_rev_list', 'ssl_client_cert',
                'ssl_client_key', 'passfile', 'tunnel_password',
                # connect_timeout was added after v2 api so exclude it from v2
                'connect_timeout'
            ]:
                del data[key]
            res = dict()
            # v2 api fields
            res["id"] = data["id"]
            res["name"] = data["name"]
            res["host"] = data["host"]
            res["port"] = data["port"]
            res["db"] = data["database"]
            res["ssl"] = data["ssl"]
            res["serviceid"] = data["serviceid"]
            res["active"] = data["active"]
            res["alert_blackout"] = data["alert_blackout"]
            res["owner"] = data["owner"]
            res["team"] = data["team"]
            res["server_owner"] = data["server_owner"]
            res["is_remote_monitoring"] = data["is_remote_monitoring"]
            res["efm_cluster_name"] = data["efm_cluster_name"]
            res["efm_service_name"] = data["efm_service_name"]
            res["efm_installation_path"] = data["efm_installation_path"]
            res["comment"] = data["comment"]
            res["username"] = data["username"]
            res["gid"] = data["gid"]
            res["server_group_name"] = data["server_group_name"]
            res["db_restriction"] = data["db_restriction"]
            res["role"] = data["role"]
            res["is_edb"] = data["is_edb"]
            res["agent_id"] = data["agent_id"]
            res["asb_host"] = data["asb_host"]
            res["asb_port"] = data["asb_port"]
            res["asb_username"] = data["asb_username"]
            res["asb_database"] = data["asb_database"]
            res["asb_sslmode"] = data["asb_sslmode"]
            # res["asb_password"] = data["asb_password"]
            res["agent_allowtakeover"] = data["agent_allowtakeover"]
            res["agent_capability_list"] = data["agent_capability_list"]
            res["agent_description"] = data["agent_description"]
            res['sslcompression'] = data['sslcompression']
            res['use_ssh_tunnel'] = data['use_ssh_tunnel']
            res['tunnel_host'] = data['tunnel_host']
            res['tunnel_port'] = data['tunnel_port']
            res['tunnel_username'] = data['tunnel_username']
            res['tunnel_authentication'] = data['tunnel_authentication']
            res['tunnel_identity_file'] = data['tunnel_identity_file']

            return res

        SQL = render_template(
            "/".join([self.template_path, 'properties.sql']),
            sid=sid
        )
        status, res = self.pem_conn.execute_dict(SQL)

        if not status:
            return internal_server_error(res)

        if sid is not None:
            if len(res['rows']) == 0:
                return bad_request(gettext("Server not found."))
            return make_response(transform(res['rows'][0]))

        return make_response([transform(row) for row in res['rows']])


class ServerApiV3View(ServerApiV2View):
    """
    A server api view with CRUD operations.
    """
    endpoint = 'server_v3'

    # Api version from v14 till latest
    # ['v14_api']
    api_versions = api_versions_v3

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
            """Validates request"""

            return validate_server_request(
                self, f, rest_api_param_check=True, **kwargs)

        return wrap

    @check_precondition
    def get(self, sid=None):
        """
        Responsible for fetching and listing server resource

        :param sid: Server id
        :return: JSON response
        """
        # Check the given object is exist or not.
        if sid is not None:
            object_exist, msg = is_object_exists(self.pem_conn, 'server', sid)
            if not object_exist:
                return make_json_response(
                    status=404, success=0, errormsg=msg
                )

        def transform(data):

            # Following keys needs not to be exposed in the REST API
            for key in [
                'store_pwd', 'restore_env', 'last_database', 'last_schema',
                'ssl_root_cert', 'ssl_rev_list', 'ssl_client_cert',
                'ssl_client_key', 'passfile', 'tunnel_password'
            ]:
                del data[key]
            res = dict()
            # v14 api fields
            res["id"] = data["id"]
            res["name"] = data["name"]
            res["host"] = data["host"]
            res["port"] = data["port"]
            res["db"] = data["database"]
            res["serviceid"] = data["serviceid"]
            res["connection_params"] = data["connection_params"]
            res["active"] = data["active"]
            res["alert_blackout"] = data["alert_blackout"]
            res["owner"] = data["owner"]
            res["team"] = data["team"]
            res["server_owner"] = data["server_owner"]
            res["is_remote_monitoring"] = data["is_remote_monitoring"]
            res["tags"] = data["tags"]
            res["replication_solution"] = data["replication_solution"]
            res["efm_cluster_name"] = data["efm_cluster_name"]
            res["efm_service_name"] = data["efm_service_name"]
            res["efm_installation_path"] = data["efm_installation_path"]
            res["patroni_cluster_name"] = data["patroni_cluster_name"]
            res["patroni_installation_path"] = data[
                "patroni_installation_path"
            ]
            res["patroni_config_path"] = data["patroni_config_path"]
            res["comment"] = data["comment"]
            res["username"] = data["username"]
            res["gid"] = data["gid"]
            res["server_group_name"] = data["server_group_name"]
            res["db_res"] = data["db_restriction"]
            res["role"] = data["role"]
            res["is_edb"] = data["is_edb"]
            res["agent_id"] = data["agent_id"]
            res["asb_host"] = data["asb_host"]
            res["asb_port"] = data["asb_port"]
            res["asb_username"] = data["asb_username"]
            res["asb_database"] = data["asb_database"]
            res["asb_sslmode"] = data["asb_sslmode"]
            # res["asb_password"] = data["asb_password"]
            res["agent_allowtakeover"] = data["agent_allowtakeover"]
            res["agent_capability_list"] = data["agent_capability_list"]
            res["agent_description"] = data["agent_description"]
            res["sslcompression"] = data["sslcompression"]
            res["use_ssh_tunnel"] = data["use_ssh_tunnel"]
            res["tunnel_host"] = data["tunnel_host"]
            res["tunnel_port"] = data["tunnel_port"]
            res["tunnel_username"] = data["tunnel_username"]
            res["tunnel_authentication"] = data["tunnel_authentication"]
            res["tunnel_identity_file"] = data["tunnel_identity_file"]
            res["post_connection_sql"] = data["post_connection_sql"]

            return res

        SQL = render_template(
            "/".join([self.template_path, 'properties.sql']),
            sid=sid, schema_version=current_user.schema_version
        )
        status, res = self.pem_conn.execute_dict(SQL)

        if not status:
            return internal_server_error(res)

        if sid is not None:
            if len(res['rows']) == 0:
                return bad_request(gettext("Server not found."))
            return make_response(transform(res['rows'][0]))

        return make_response([transform(row) for row in res['rows']])


class ServerApiV4View(ServerApiV3View):
    """
    A server api view with CRUD operations.
    """
    endpoint = 'server_v4'

    # Api version from v15 till latest
    # ['v15_api']
    api_versions = api_versions_v4

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
            """Validates request"""

            return validate_server_request(
                self, f, rest_api_param_check=True, **kwargs)

        return wrap

    @check_precondition
    def get(self, sid=None):
        """
        Responsible for fetching and listing server resource

        :param sid: Server id
        :return: JSON response
        """
        # Check the given object is exist or not.
        if sid is not None:
            object_exist, msg = is_object_exists(self.pem_conn, 'server', sid)
            if not object_exist:
                return make_json_response(
                    status=404, success=0, errormsg=msg
                )

        def transform(data):

            # Following keys needs not to be exposed in the REST API
            for key in [
                'store_pwd', 'restore_env', 'last_database', 'last_schema',
                'ssl_root_cert', 'ssl_rev_list', 'ssl_client_cert',
                'ssl_client_key', 'passfile', 'tunnel_password'
            ]:
                del data[key]
            res = dict()
            # v15 api fields
            res["id"] = data["id"]
            res["name"] = data["name"]
            res["host"] = data["host"]
            res["port"] = data["port"]
            res["db"] = data["database"]
            res['profile_id'] = data["profile_id"]
            res["serviceid"] = data["serviceid"]
            res["connection_params"] = data["connection_params"]
            res["active"] = data["active"]
            res["alert_blackout"] = data["alert_blackout"]
            res["owner"] = data["owner"]
            res["team"] = data["team"]
            res["server_owner"] = data["server_owner"]
            res["is_remote_monitoring"] = data["is_remote_monitoring"]
            res["tags"] = data["tags"]
            res["replication_solution"] = data["replication_solution"]
            res["efm_cluster_name"] = data["efm_cluster_name"]
            res["efm_service_name"] = data["efm_service_name"]
            res["efm_installation_path"] = data["efm_installation_path"]
            res["patroni_cluster_name"] = data["patroni_cluster_name"]
            res["patroni_installation_path"] = data[
                "patroni_installation_path"
            ]
            res["patroni_config_path"] = data["patroni_config_path"]
            res["comment"] = data["comment"]
            res["username"] = data["username"]
            res["gid"] = data["gid"]
            res["server_group_name"] = data["server_group_name"]
            res["db_res"] = data["db_restriction"]
            res["role"] = data["role"]
            res["is_edb"] = data["is_edb"]
            res["agent_id"] = data["agent_id"]
            res["asb_host"] = data["asb_host"]
            res["asb_port"] = data["asb_port"]
            res["asb_username"] = data["asb_username"]
            res["asb_database"] = data["asb_database"]
            res["asb_sslmode"] = data["asb_sslmode"]
            # res["asb_password"] = data["asb_password"]
            res["agent_allowtakeover"] = data["agent_allowtakeover"]
            res["agent_capability_list"] = data["agent_capability_list"]
            res["agent_description"] = data["agent_description"]
            res["sslcompression"] = data["sslcompression"]
            res["use_ssh_tunnel"] = data["use_ssh_tunnel"]
            res["tunnel_host"] = data["tunnel_host"]
            res["tunnel_port"] = data["tunnel_port"]
            res["tunnel_username"] = data["tunnel_username"]
            res["tunnel_authentication"] = data["tunnel_authentication"]
            res["tunnel_identity_file"] = data["tunnel_identity_file"]
            res["post_connection_sql"] = data["post_connection_sql"]

            return res

        SQL = render_template(
            "/".join([self.template_path, 'properties.sql']),
            sid=sid, schema_version=current_user.schema_version
        )
        status, res = self.pem_conn.execute_dict(SQL)

        if not status:
            return internal_server_error(res)

        if sid is not None:
            if len(res['rows']) == 0:
                return bad_request(gettext("Server not found."))
            return make_response(transform(res['rows'][0]))

        return make_response([transform(row) for row in res['rows']])


class DatabaseApiView(ApiView):
    """
    A database api view to get list of databases for given server.
    """

    endpoint = 'database'

    url = '/server/<sid>/database/'

    pk = 'db_name'

    pk_type = 'string'

    methods = ['GET']

    @check_precondition
    def get(self, sid, db_name=None):
        """
        Responsible for listing resource

        :param sid: Server id
        :param db_name: Database name
        :return: JSON response
        """
        # Check the given object is exist or not.
        if db_name is not None:
            object_exist, msg = is_object_exists(self.pem_conn,
                                                 'database', sid, db_name)
        else:
            object_exist, msg = is_object_exists(
                self.pem_conn, 'server', sid
            )

        if not object_exist:
            return make_json_response(
                status=404, success=0, errormsg=msg
            )

        params = {'server_id': sid}

        if db_name:
            params['db_name'] = db_name

        SQL = render_template(
            "/".join([self.template_path, 'pem/database.sql']),
            params=params
        )

        status, res = self.pem_conn.execute_dict(SQL, params)

        if not status:
            return internal_server_error(res)

        return make_response(res['rows'][0] if db_name else res['rows'])


class SchemaApiView(ApiView):
    """
    A schema api view to get list of schemas for given server.
    """

    endpoint = 'schema'

    url = '/server/<sid>/database/<string:db_name>/schema/'

    pk = 'schema_name'

    pk_type = 'string'

    methods = ['GET']

    @check_precondition
    def get(self, sid, db_name, schema_name=None):
        """
        Responsible for listing resource

        :param sid: Server id
        :param db_name: Database name
        :param schema_name: Schema name
        :return: JSON response
        """
        # Check the given object is exist or not.
        if schema_name is not None:
            object_exist, msg = is_object_exists(self.pem_conn, 'schema',
                                                 sid, db_name, schema_name)
        else:
            object_exist, msg = is_object_exists(self.pem_conn, 'database',
                                                 sid, db_name)
        if not object_exist:
            return make_json_response(
                status=404, success=0, errormsg=msg
            )

        params = {'server_id': sid,
                  'db_name': db_name}

        if schema_name:
            params['schema_name'] = schema_name

        SQL = render_template(
            "/".join([self.template_path, 'pem/schema.sql']),
            params=params
        )

        status, res = self.pem_conn.execute_dict(SQL, params)

        if not status:
            return internal_server_error(res)

        return make_response(res['rows'][0] if schema_name else res['rows'])


class TableApiView(ApiView):
    """
    A table api view to get list of tables for given server.
    """

    endpoint = 'table'

    url = '/server/<sid>/database/<string:db_name>/schema/' \
          '<string:schema_name>/table/'

    pk = 'table_name'

    pk_type = 'string'

    methods = ['GET']

    @check_precondition
    def get(self, sid, db_name, schema_name, table_name=None):
        """
        Responsible for listing resource

        :param sid: Server id
        :param db_name: Database name
        :param schema_name: Schema name
        :param table_name: Table name
        :return: JSON response
        """
        # Check the given object is exist or not.
        if table_name is not None:
            object_exist, msg = is_object_exists(self.pem_conn, 'table',
                                                 sid, db_name,
                                                 schema_name, table_name)
        else:
            object_exist, msg = is_object_exists(self.pem_conn, 'schema',
                                                 sid, db_name, schema_name)
        if not object_exist:
            return make_json_response(
                status=404, success=0, errormsg=msg
            )

        params = {'server_id': sid,
                  'db_name': db_name,
                  'schema_name': schema_name}

        if table_name:
            params['table_name'] = table_name

        SQL = render_template(
            "/".join([self.template_path, 'pem/table.sql']),
            params=params
        )

        status, res = self.pem_conn.execute_dict(SQL, params)

        if not status:
            return internal_server_error(res)

        return make_response(res['rows'][0] if table_name else res['rows'])


class IndexApiView(ApiView):
    """
    A Index api view to get list of index for given server.
    """

    endpoint = 'table_index'

    url = '/server/<sid>/database/<string:db_name>/schema/' \
          '<string:schema_name>/index/'

    pk = 'index_name'

    pk_type = 'string'

    methods = ['GET']

    @check_precondition
    def get(self, sid, db_name, schema_name, index_name=None):
        """
        Responsible for listing resource

        :param sid: Server id
        :param db_name: Database name
        :param schema_name: Schema name
        :param index_name: Index name
        :return: JSON response
        """
        # Check the given object is exist or not.
        if index_name is not None:
            object_exist, msg = is_object_exists(self.pem_conn, 'index', sid,
                                                 db_name, schema_name,
                                                 index_name)
        else:
            object_exist, msg = is_object_exists(self.pem_conn, 'schema',
                                                 sid, db_name, schema_name)
        if not object_exist:
            return make_json_response(
                status=404, success=0, errormsg=msg
            )

        params = {'server_id': sid,
                  'db_name': db_name,
                  'schema_name': schema_name}

        if index_name:
            params['index_name'] = index_name

        SQL = render_template(
            "/".join([self.template_path, 'pem/index.sql']),
            params=params
        )

        status, res = self.pem_conn.execute_dict(SQL, params)

        if not status:
            return internal_server_error(res)

        return make_response(res['rows'][0] if index_name else res['rows'])


class SequenceApiView(ApiView):
    """
    A Sequence api view to get list of sequence for given server.
    """

    endpoint = 'sequence'

    url = '/server/<sid>/database/<string:db_name>/schema/' \
          '<string:schema_name>/sequence/'

    pk = 'sequence_name'

    pk_type = 'string'

    methods = ['GET']

    @check_precondition
    def get(self, sid, db_name, schema_name, sequence_name=None):
        """
        Responsible for listing resource

        :param sid: Server id
        :param db_name: Database name
        :param schema_name: Schema name
        :param sequence_name: Index name
        :return: JSON response
        """
        # Check the given object is exist or not.
        if sequence_name is not None:
            object_exist, msg = is_object_exists(self.pem_conn, 'sequence',
                                                 sid, db_name, schema_name,
                                                 sequence_name)
        else:
            object_exist, msg = is_object_exists(self.pem_conn, 'schema',
                                                 sid, db_name, schema_name)
        if not object_exist:
            return make_json_response(
                status=404, success=0, errormsg=msg
            )

        params = {'server_id': sid,
                  'db_name': db_name,
                  'schema_name': schema_name}

        if sequence_name:
            params['sequence_name'] = sequence_name

        SQL = render_template(
            "/".join([self.template_path, 'pem/sequence.sql']),
            params=params
        )

        status, res = self.pem_conn.execute_dict(SQL, params)

        if not status:
            return internal_server_error(res)

        return make_response(res['rows'][0] if sequence_name else res['rows'])


class ViewApiView(ApiView):
    """
    A View api view to get list of view for given server.
    """

    endpoint = 'view'

    url = '/server/<sid>/database/<string:db_name>/schema/' \
          '<string:schema_name>/view/'

    pk = 'view_name'

    pk_type = 'string'

    methods = ['GET']

    @check_precondition
    def get(self, sid, db_name, schema_name, view_name=None):
        """
        Responsible for listing resource

        :param sid: Server id
        :param db_name: Database name
        :param schema_name: Schema name
        :param view_name: View name
        :return: JSON response
        """
        # Check the given object is exist or not.
        if view_name is not None:
            object_exist, msg = is_object_exists(self.pem_conn, 'view', sid,
                                                 db_name, schema_name,
                                                 view_name)
        else:
            object_exist, msg = is_object_exists(self.pem_conn, 'schema', sid,
                                                 db_name, schema_name)
        if not object_exist:
            return make_json_response(
                status=404, success=0, errormsg=msg
            )

        params = {'server_id': sid,
                  'db_name': db_name,
                  'schema_name': schema_name}

        if view_name:
            params['view_name'] = view_name

        SQL = render_template(
            "/".join([self.template_path, 'pem/view.sql']),
            params=params
        )

        status, res = self.pem_conn.execute_dict(SQL, params)

        if not status:
            return internal_server_error(res)

        return make_response(res['rows'][0] if view_name else res['rows'])


class FunctionApiView(ApiView):
    """
    A Function api view to get list of function for given server.
    """

    endpoint = 'function'

    url = '/server/<sid>/database/<string:db_name>/schema/' \
          '<string:schema_name>/function/'

    pk = 'function_name'

    pk_type = 'string'

    methods = ['GET']

    @check_precondition
    def get(self, sid, db_name, schema_name, function_name=None):
        """
        Responsible for listing resource

        :param sid: Server id
        :param db_name: Database name
        :param schema_name: Schema name
        :param function_name: Function name
        :return: JSON response
        """
        # Check the given object is exist or not.
        if function_name is not None:
            object_exist, msg = is_object_exists(self.pem_conn, 'function',
                                                 sid, db_name, schema_name,
                                                 function_name)
        else:
            object_exist, msg = is_object_exists(self.pem_conn, 'schema',
                                                 sid, db_name, schema_name)
        if not object_exist:
            return make_json_response(
                status=404, success=0, errormsg=msg
            )

        params = {'server_id': sid,
                  'db_name': db_name,
                  'schema_name': schema_name}

        if function_name:
            params['function_name'] = function_name

        SQL = render_template(
            "/".join([self.template_path, 'pem/function.sql']),
            params=params
        )

        status, res = self.pem_conn.execute_dict(SQL, params)

        if not status:
            return internal_server_error(res)

        return make_response(res['rows'][0] if function_name else res['rows'])


class ServerStatusApiView(ApiView):

    endpoint = 'server_status'

    url = '/server/status/'
    pk = 'sid'
    methods = ['GET']

    # Api version from v4 till latest
    # ['v4_api', 'v5_api', 'v6_api', 'v7_api', 'v8_api']
    api_versions = api_versions_v2[2:]

    output_params = list([
        "group_id", "group_name", "id", "blackout", "name", "status",
        "version", "remote_monitoring", "agent_id",
        "alerts", "number_connections", "sessions",  # {'sessions': [{
        #   'database_name', 'procpid', 'usename', 'backend_start',
        #   'xact_start', 'query_start', 'is_waiting', 'is_idle',
        #   'is_idle_in_transaction', 'is_vacuum', 'is_autovacuum',
        #   'client_addr', 'client_port', 'memory_usage_mb',
        #   'swap_usage_mb', 'cpu_usage', 'io_read_bytes', 'io_write_bytes',
        #   'state', 'state_change'
        # }], 'last_recorded_time'}
        "alerts"  # {
        #   'total', 'acknowledged', 'high', 'medium', 'low',
        #   'high_acknowledged', 'medium_acknowledged', 'low_acknowledged'
        # }
    ])

    @check_precondition
    def get(self, sid=None):
        """
        Responsible for fetching and listing agent resource

        :param sid: Server ID
        :return: JSON response
        """
        # First check agent id exists or not.
        if sid is not None and sid <= 0:
            return make_json_response(
                status=404, success=0,
                errormsg=gettext("The specified server id is not valid")
            )

        SQL = render_template(
            "/".join([self.template_path, 'status.sql']),
            server_id=sid
        )
        status, res = self.pem_conn.execute_dict(SQL)

        if not status:
            return internal_server_error(res)

        def _format_server_status_data(_data):
            _data['alerts'] = json.loads(_data['alerts'])
            _data['sessions'] = json.loads(_data['sessions'])
            _data['number_connections'] = int(_data['number_connections'])

        if len(res['rows']) > 0:
            res = res['rows']
            if sid is not None:
                res = self.discard_unwanted_params(res[0], self.output_params)
                _format_server_status_data(res)
            else:
                for row in res:
                    row = self.discard_unwanted_params(
                        row, self.output_params
                    )
                    _format_server_status_data(row)

            return make_response(res)

        if sid is None:
            return make_response(list())

        return make_json_response(
            status=404, success=0,
            errormsg=gettext("The specified server id is not available")
        )


class ExcludeDatabaseApiView(ApiView):

    endpoint = 'exclude_database'

    url = '/server/exclude_database/'
    pk = 'sid'
    methods = ['GET', 'DELETE', 'PUT']

    # Api version from v6 till latest
    # ['v6_api', 'v7_api', 'v8_api']
    api_versions = api_versions_v2[4:]

    def validate_server_id(self, sid, method='GET'):
        """
        This function validates the provided data in API

        :return: True/False, Error message
        """
        if sid is not None and sid <= 0:
            return False, make_json_response(
                status=404, success=0,
                errormsg=gettext("The specified server id is not valid")
            )

        SQL = render_template(
            "/".join([self.template_path, 'exclude_databases.sql']),
            server_id=sid
        )
        status, res = self.pem_conn.execute_dict(SQL)

        if not status:
            return False, internal_server_error(res)

        if len(res['rows']) == 0:
            return False, make_json_response(
                status=404, success=0,
                errormsg=gettext("The specified server id is not available")
            )
        elif method == 'GET':
            return True, make_response(res['rows'][0])

        return True, None

    @check_precondition
    def get(self, sid=None):
        """
        This function will return all the excluded databases for given
        server id

        :param sid: Server Id

        Method: GET
        URL: /api/v6/server/exclude_database/<sid>

        Input Data:
        Valid server id to fetch the exclude database list

        e.g.
        /api/v6/server/exclude_database/2

        :return:

        Below is the expected result.

        status: 200 OK
        {
          "server_id":1,
          "excluded_databases":["edb, test_db"]
        }

        """

        _, res = self.validate_server_id(sid)  # Ignored unused variable
        return res

    @check_precondition
    def delete(self, sid):
        """
        This function will remove the all excluded databases for given server

        :param sid: Server Id from which excluded databases to be removed

        Method: DELETE
        URL: /api/v6/server/exclude_database/<sid>

        Input Data:
        Valid server id to delete the exclude database list

        e.g.
        /api/v6/server/exclude_database/2

        :return:

        Below is the expected result.

        status: 200 OK
        {
          "success":1,
          "info":"Excluded databases deleted successfully.",
          "result":null,
          "errormsg":"",
          "data":null
        }

        """

        status, res = self.validate_server_id(sid, 'DELETE')

        if not status:
            return res

        sql = render_template(
            "/".join([self.template_path, 'update_exclude_database.sql']),
            server_id=sid,
            remove_dbs=True
        )

        try:
            status, result = self.pem_conn.execute_void(sql)

            if not status:
                return internal_server_error(result)

        except Exception as e:
            return internal_server_error(str(e))

        return success_return(message=gettext(
            'Exclude databases deleted successfully.')
        )

    @check_precondition
    def put(self, sid):
        """
        This function will update exclude database .

        :param sid: Server Id for which exclude databases
        needs to be added.

        Method: POST
        URL: /api/v6/server/exclude_database/<sid>

        Input Data: Below are the json input format required to update
        email groups.

        Example input data as below.
        {
          "exclude_databases":[edb,test_db]
        }

        :return:

        Below is the expected result.

        status: 200 OK
        {
          "success":1,
          "info":"Exclude database added successfully.",
          "result":null,
          "errormsg":"",
          "data":null
        }

        """
        data = request.get_json()

        # Check for exclude_databases in data(dict)
        if 'exclude_databases' not in data or len(
            data['exclude_databases']
        ) == 0:
            return make_json_response(
                status=404, success=0,
                errormsg=gettext(
                    "Please specify exclude_databases to be added"
                )
            )
        status, res = self.validate_server_id(sid)

        if not status:
            return res

        asb_database = res.json['database']
        if asb_database in data['exclude_databases']:
            return make_json_response(
                success=0,
                status=400,
                errormsg=gettext('The database specified in the PEM Agent '
                                 'connection parameters cannot be part of '
                                 'excluded databases.')
            )

        if 'exclude_databases' in res.json and len(
            res.json['exclude_databases']
        ) > 0:
            old_ex_dbs = res.json['exclude_databases']
            for new_db in data['exclude_databases']:
                if new_db in old_ex_dbs:
                    return make_json_response(
                        success=0,
                        status=400,
                        errormsg=gettext("The database '%s' is already added "
                                         "in excluded databases") % new_db
                    )
                old_ex_dbs.append(new_db)
            data['exclude_databases'] = old_ex_dbs

        sql = render_template(
            "/".join([self.template_path, 'update_exclude_database.sql']),
            server_id=sid,
            data=data,
            update_dbs=True,
            conn=self.pem_conn
        )

        try:
            status, result = self.pem_conn.execute_void(sql)
            if not status:
                return internal_server_error(result)

        except Exception as e:
            return internal_server_error(str(e))

        return success_return(message=gettext(
            'Excluded databases added successfully.')
        )
