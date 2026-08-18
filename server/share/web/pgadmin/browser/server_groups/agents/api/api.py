##########################################################################
#
# Postgres Enterprise Manager
#
# Copyright (C) 2016 - 2025, EnterpriseDB Corporation. All rights reserved.
#
##########################################################################


""" Api for Agent """

from flask_babel import gettext as _
from functools import wraps
from flask import render_template, request, current_app
from flask_security import current_user
from pgadmin.utils.ajax import make_response, precondition_required, \
    make_json_response, internal_server_error, success_return
from pgadmin.pem.api.utils import ApiView
from pgadmin.browser.server_groups.agents.utils import update_agent
from pgadmin.pem.utils.data_type import validate_boolean, \
    validate_empty_string, validate_integer
from pgadmin.browser.server_groups.agents.jobs import JobView
from pgadmin.browser.server_groups.servers.pem.utils import \
    fetch_message_from_exception
import json
api_versions_v2 = list(ApiView.api_versions)[1:14]
api_versions_v3 = list(ApiView.api_versions)[14:15]


def check_precondition(f):
    """
    This function will behave as a decorator which will checks
    database connection before running view, it will also attaches
    manager,conn & template_path properties to self
    """
    @wraps(f)
    def wrap(obj, *args, **kwargs):
        """
        Responsible for making PEM connection object and template path
        """

        obj.conn = kwargs['pem_conn']

        if not obj.conn.connected():
            obj.conn.connect()

        # If DB not connected then return error to browser
        if not obj.conn.connected():
            return precondition_required(
                _("Connection to the PEM server has been lost!")
            )

        # We do not need to pass the pem_conn to the wrapped functions
        del kwargs['pem_conn']

        # Set the template path for sql scripts
        obj.template_path = 'agents/sql'

        return f(obj, *args, **kwargs)
    return wrap


class AgentApiV1View(ApiView):
    """
    An agent view with CRUD operations.
    """

    endpoint = 'agent_v1'

    url = '/agent/'
    pk = 'agid'
    methods = ['GET', 'PUT']
    api_versions = ['v1_api']
    properties = dict({
        "name": validate_empty_string(_("Name cannot be empty")),
        "heartbeat_tolerance": validate_integer(
            _("Please provide numeric value for heartbeat_tolerance field")
        )
    })

    output_params = list([
        "domain_name", "host_name", "boot_time", "alert_blacked_out",
        "active", "id", "version", "heartbeat_tolerance", "owner",
        "window_domain", "capability_list", "server_bind", "status",
        "operating_sys", "team", "name","tags"
    ])

    def __init__(self, *args, **kwargs):
        super(ApiView, self).__init__(*args, **kwargs)
        self.params = self.properties

    @check_precondition
    def get(self, agid=None):
        """
        Responsible for fetching and listing agent resource

        :param agid: Agent ID
        :return: JSON response
        """
        # First check agent id exists or not.
        if agid is not None and agid <= 0:
            return make_json_response(
                status=404, success=0,
                errormsg=_("The specified agent id is not valid")
            )

        SQL = render_template(
            "/".join([self.template_path, 'properties.sql']),
            agent_id=agid,
            schema_version=current_user.schema_version
        )
        status, res = self.conn.execute_dict(SQL)

        if not status:
            return internal_server_error(res)

        if len(res['rows']) > 0:
            res = res['rows']
            if agid is not None:
                res = self.discard_unwanted_params(res[0], self.output_params)
            else:
                for row in res:
                    row = self.discard_unwanted_params(
                        row, self.output_params
                    )

            return make_response(res)

        if agid is None:
            return make_response(list())

        return make_json_response(
            status=404, success=0,
            errormsg=_("The specified agent id is not available")
        )

    @check_precondition
    def put(self, agid):
        """
        Responsible for updating agent resource

        :param agid: Agent ID
        :return: JSON response
        """

        # First check agent id exists or not.
        if agid is not None and agid <= 0:
            return make_json_response(
                status=404, success=0,
                errormsg=_("The specified agent id is not valid")
            )

        data = json.loads(request.data.decode())

        if data is None:
            return make_json_response(
                status=400, success=0,
                errormsg=_(
                    "Please specify input data for which you wish to "
                    "update the agent properties."
                )
            )

        # Check for invalid input for the current version.
        self.check_for_invalid_param(data)
        if 'profile_id' in data:
            sql = ("SELECT count(*) FROM pem.profile WHERE id = %s AND "
                   "status = 'published' AND "
                   "target_kind = 'a'")
            status, res = (
                self.conn.execute_scalar(sql, (data['profile_id'],)))
            if not status:
                return internal_server_error(res)
            if int(res) == 0:
                return make_json_response(
                    status=400, success=0,
                    errormsg=str(
                        "Provided profile_id not found, not published, "
                        "or is not an agent profile")
                )
        # Check the validity of the input
        for key in self.params:
            if key in data:
                if self.properties[key] is not None:
                    try:
                        self.properties[key](data[key])
                    except ValueError as ve:
                        return make_json_response(
                            status=400, success=0,
                            errormsg=str(ve)
                        )

        status, res = update_agent(self.conn, agid, data)

        if status is False:
            return internal_server_error(res)

        if status is not True:
            return make_json_response(
                status=404, success=0,
                errormsg=status
            )

        if res is None:
            # We are retuning agent id from update_agent.
            # If status is True and agent id is none then agent was not found.
            return make_json_response(
                status=404, success=0,
                errormsg=_("Agent not found.")
            )

        return success_return(message=_('Agent updated successfully.'))


class AgentApiV2View(AgentApiV1View):
    """
    An agent view with CRUD operations.
    """

    endpoint = 'agent_v2'

    # Api version from v2 till latest
    # ['v2_api', 'v3_api', 'v4_api', 'v5_api', 'v6_api', 'v7_api', 'v8_api']
    api_versions = api_versions_v2
    methods = ['GET', 'PUT', 'DELETE']
    properties = dict({
        "name": validate_empty_string(_("Name cannot be empty")),
        "heartbeat_tolerance": validate_integer(
            _("Please provide numeric value for heartbeat_tolerance field")
        ),
        "alert_blackout": validate_boolean(
            _("Alert blackout cannot be empty or contain boolean value.")
        ),
        "team": None,
        "gid": validate_integer(
            _("Please provide the valid group-id value"),
            min_value=0
        ),
        "tags": None,
        "ignore_mnt_points": None
    })
    output_params = list([
        "domain_name", "host_name", "boot_time", "alert_blacked_out",
        "active", "id", "version", "heartbeat_tolerance", "owner",
        "window_domain", "capability_list", "server_bind", "status",
        "operating_sys", "team", "name", "gid", "tags", "ignore_mnt_points"
    ])

    @check_precondition
    def delete(self, agid):
        """
        Responsible for deleting agent.

        :param agid: Agent ID
        :return: JSON response
        """
        # First check agent id exists or not.
        if agid is not None and agid <= 0:
            return make_json_response(
                status=404, success=0,
                errormsg=_("The specified agent id is not valid.")
            )

        # PEM agent with id = 1 will not be allowed to delete.
        if agid == 1:
            return make_json_response(
                status=403, success=0,
                errormsg=_("User can not delete PEM Agent with id=1.")
            )

        sql = render_template(
            "/".join([self.template_path, 'properties.sql']),
            agent_id=agid,
            schema_version=current_user.schema_version
        )

        try:
            status, res = self.conn.execute_dict(sql)

            if not status:
                return internal_server_error(errormsg=res)

        except Exception as e:
            return internal_server_error(e)

        # If agent id is not specified then return error.
        if agid is not None and len(res['rows']) == 0:
            return make_json_response(
                status=404, success=0,
                errormsg=_(
                    "The specified agent id is "
                    "not available."
                )
            )

        sql = render_template(
            "/".join([self.template_path, 'drop.sql']),
            id=agid
        )

        try:
            status, del_agents = self.conn.execute_void(sql)
            if not status:
                return internal_server_error(errormsg=del_agents)

            # create a scheduled job to delete all probe data for the agent
            try:
                from ..jobs.utils import create_purge_job
                create_purge_job(self.conn, agid=agid)
            except Exception as e:
                current_app.logger.exception(e)
                return internal_server_error(
                    errormsg=fetch_message_from_exception(e))
        except Exception as e:
            return make_json_response(
                status=410, success=0,
                errormsg=_(
                    "Error deleting agent id."
                )
            )

        return success_return(message=_('Agent deleted successfully.'))


class AgentApiV3View(AgentApiV2View):
    """
    An agent view with CRUD operations.
    """

    endpoint = 'agent_v3'

    # Api version from v2 till latest
    # ['v2_api', 'v3_api', 'v4_api', 'v5_api', 'v6_api', 'v7_api', 'v8_api']
    api_versions = api_versions_v3
    methods = ['GET', 'PUT', 'DELETE']
    properties = dict({
        "name": validate_empty_string(_("Name cannot be empty")),
        "heartbeat_tolerance": validate_integer(
            _("Please provide numeric value for heartbeat_tolerance field")
        ),
        "profile_id": None,
        "alert_blackout": validate_boolean(
            _("Alert blackout cannot be empty or contain boolean value.")
        ),
        "team": None,
        "gid": validate_integer(
            _("Please provide the valid group-id value"),
            min_value=0
        ),
        "tags": None,
        "ignore_mnt_points": None
    })
    output_params = list([
        "domain_name", "host_name", "boot_time", "alert_blacked_out",
        "active", "id", "version", "heartbeat_tolerance", "profile_id",
        "owner", "window_domain", "capability_list", "server_bind", "status",
        "operating_sys", "team", "name", "gid", "tags", "ignore_mnt_points"
    ])

    @check_precondition
    def get(self, agid=None):
        """
        Responsible for fetching and listing agent resource

        :param agid: Agent ID
        :return: JSON response
        """
        # First check agent id exists or not.
        if agid is not None and agid <= 0:
            return make_json_response(
                status=404, success=0,
                errormsg=_("The specified agent id is not valid")
            )

        SQL = render_template(
            "/".join([self.template_path, 'properties.sql']),
            agent_id=agid,
            schema_version=current_user.schema_version
        )
        status, res = self.conn.execute_dict(SQL)

        if not status:
            return internal_server_error(res)

        if len(res['rows']) > 0:
            res = res['rows']
            if agid is not None:
                res = self.discard_unwanted_params(res[0], self.output_params)
            else:
                for row in res:
                    row = self.discard_unwanted_params(
                        row, self.output_params
                    )

            return make_response(res)

        if agid is None:
            return make_response(list())

        return make_json_response(
            status=404, success=0,
            errormsg=_("The specified agent id is not available")
        )


class AgentStatusApiView(ApiView):

    endpoint = 'agent_status'

    url = '/agent/status/'
    pk = 'agid'
    methods = ['GET']

    # Api version from v4 till latest
    # ['v4_api', 'v5_api', 'v6_api', 'v7_api', 'v8_api']
    api_versions = api_versions_v2[2:]

    output_params = list([
        "group_id", "group_name", "id", "blackout", "name", "status", "alerts",
        "version", "processes", "threads", "cpu_utilization",
        "memory_utilization", "swap_utilization", "disk_utilization"
    ])

    @check_precondition
    def get(self, agid=None):
        """
        Responsible for fetching and listing agent resource

        :param agid: Agent ID
        :return: JSON response
        """
        # First check agent id exists or not.
        if agid is not None and agid <= 0:
            return make_json_response(
                status=404, success=0,
                errormsg=_("The specified agent id is not valid")
            )

        SQL = render_template(
            "/".join([self.template_path, 'status.sql']),
            agent_id=agid
        )
        status, res = self.conn.execute_dict(SQL)

        if not status:
            return internal_server_error(res)

        def _format_agent_status_data(_data):
            _data['alerts'] = json.loads(_data['alerts'])
            _data["processes"] = int(_data["processes"])
            _data["threads"] = int(_data["threads"])
            _data["cpu_utilization"] = float(_data["cpu_utilization"])
            _data["memory_utilization"] = float(_data["memory_utilization"])
            _data["swap_utilization"] = float(_data["swap_utilization"])
            _data["disk_utilization"] = float(_data["disk_utilization"])

        if len(res['rows']) > 0:
            res = res['rows']
            if agid is not None:
                res = self.discard_unwanted_params(res[0], self.output_params)
                _format_agent_status_data(res)
            else:
                for row in res:
                    row = self.discard_unwanted_params(
                        row, self.output_params
                    )
                    _format_agent_status_data(row)

            return make_response(res)

        if agid is None:
            return make_response(list())

        return make_json_response(
            status=404, success=0,
            errormsg=_("The specified agent id is not available")
        )
