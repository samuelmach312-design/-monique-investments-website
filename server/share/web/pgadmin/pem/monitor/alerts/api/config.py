##########################################################################
#
# Postgres Enterprise Manager
#
# Copyright (C) 2016 - 2025, EnterpriseDB Corporation. All rights reserved.
#
##########################################################################

"""Alert Config API"""

from pgadmin.pem.api.utils import ApiView
from pgadmin.pem.monitor.alerts.api.utils import transform_snmp_version_value
from pgadmin.utils.ajax import make_response, make_json_response, \
    internal_server_error, precondition_required, success_return, bad_request
from pgadmin.pem.monitor.alerts import utils
from flask_babel import gettext
from pgadmin.pem.utils import is_agent_exists, is_object_exists, is_edb_server
from pgadmin.pem.monitor.utils import DashboardLevel
from flask import render_template, request
from functools import wraps
from pgadmin.pem.monitor.alerts.webhook import insert_webhook_alert_config
from pgadmin.pem.monitor.alerts.webhook import validate_update_webhook_params
from pgadmin.pem.monitor.alerts.webhook import update_webhook_alert_config
import re

upto_v4_params = [
    "id", "alert_name", "alert_template", "description", "enabled",
    "auto_created", "template_id", "agent_id", "server_id", "database_name",
    "schema_name", "package_name", "object_name", "params", "param_names",
    "param_types", "params_units", "threshold_unit", "operator", "thresholds",
    "low_threshold_value", "medium_threshold_value", "high_threshold_value",
    "frequency_min", "default_frequency", "default_history_retention",
    "frequency_default", "history_retention", "history_retention_default",
    "email_group_id", "send_email", "send_trap", "snmp_trap_version",
    "agent_desc", "server_desc", "email_group_name", "low_send_trap",
    "med_send_trap", "high_send_trap", "low_email_group_id",
    "med_email_group_id", "high_email_group_id", "execute_script",
    "execute_script_on_clear", "execute_script_on_pem_server",
    "script_code", "submit_to_nagios", "low_email_group_name",
    "med_email_group_name", "high_email_group_name", "all_alert_enable",
    "low_alert_enable", "med_alert_enable", "high_alert_enable"
]

v5_params = [
    "id", "alert_name", "alert_template", "description", "enabled",
    "auto_created", "template_id", "agent_id", "server_id", "database_name",
    "schema_name", "package_name", "object_name", "params", "param_names",
    "param_types", "params_units", "threshold_unit", "operator", "thresholds",
    "low_threshold_value", "medium_threshold_value", "high_threshold_value",
    "frequency_min", "default_frequency", "default_history_retention",
    "frequency_default", "history_retention", "history_retention_default",
    "email_group_id", "send_email", "send_trap", "snmp_trap_version",
    "agent_desc", "server_desc", "email_group_name", "low_send_trap",
    "med_send_trap", "high_send_trap", "low_email_group_id",
    "med_email_group_id", "high_email_group_id", "execute_script",
    "execute_script_on_clear", "execute_script_on_pem_server", "script_code",
    "submit_to_nagios", "low_email_group_name", "med_email_group_name",
    "high_email_group_name", "all_alert_enable", "low_alert_enable",
    "med_alert_enable", "high_alert_enable", "override_default_config",
    "low_webhook_ids", "med_webhook_ids", "high_webhook_ids",
    "cleared_webhook_ids", "send_notification"
]

v11_params = [
    "id", "alert_name", "alert_template", "description", "enabled",
    "auto_created", "template_id", "agent_id", "server_id", "database_name",
    "schema_name", "package_name", "object_name", "params", "param_names",
    "param_types", "params_units", "threshold_unit", "operator", "thresholds",
    "low_threshold_value", "medium_threshold_value", "high_threshold_value",
    "frequency_min", "default_frequency", "default_history_retention",
    "frequency_default", "history_retention", "history_retention_default",
    "email_group_id", "send_email", "send_trap", "snmp_trap_version",
    "agent_desc", "server_desc", "email_group_name", "low_send_trap",
    "med_send_trap", "high_send_trap", "low_email_group_id",
    "med_email_group_id", "high_email_group_id", "execute_script",
    "execute_script_on_clear", "execute_script_on_pem_server", "script_code",
    "submit_to_nagios", "low_email_group_name", "med_email_group_name",
    "high_email_group_name", "all_alert_enable", "low_alert_enable",
    "med_alert_enable", "high_alert_enable", "override_default_config",
    "low_webhook_ids", "med_webhook_ids", "high_webhook_ids",
    "cleared_webhook_ids", "send_notification", "cleared_alert_enable"
]

api_versions_v5 = list(ApiView.api_versions)[4:]


def check_precondition(f):
    """
    This function will behave as a decorator which will checks
    database connection before running view, it will also attaches
    manager,conn & template_path properties to self
    """

    @wraps(f)
    def wrap(self, *args, **kwargs):
        """Makes PEM connection and sets template path"""
        self.conn = kwargs['pem_conn']

        if not self.conn.connected():
            self.conn.connect()

        # If DB not connected then return error to browser
        if not self.conn.connected():
            return precondition_required(
                gettext("Connection to the PEM server has been lost!")
            )

        # We do not need to pass the pem_conn to the wrapped functions
        del kwargs['pem_conn']

        # Check server type is ppas or not
        if 'server_id' in kwargs:
            self.is_edb = int(is_edb_server(self.conn,
                                            kwargs['server_id']))
        else:
            self.is_edb = 0

        # Set the template path for sql scripts
        self.template_path = 'alerts/sql/alerts'

        return f(self, *args, **kwargs)

    return wrap


class GlobalConfigApiView(ApiView):
    """
    This class provide APIs to configure the alerts at global level.
    """

    endpoint = 'global_alert_config'
    url = '/alert/config/global/'
    pk = 'alert_id'
    conn = None
    template_path = None
    is_edb = 0
    methods = ['GET', 'DELETE', 'POST', 'PUT']
    api_versions = ['v1_api', 'v2_api', 'v3_api', 'v4_api']

    def __init__(self, *args, **kwargs):
        super(ApiView, self).__init__(*args, **kwargs)
        self.params = frozenset(upto_v4_params)

    @check_precondition
    def get(self, alert_id=None):
        """
        This function will return the list of alerts at global level.

        :param alert_id: Alert Id for which information will be fetched.

        Method: GET
        URL: /api/v1/alert/config/global/
        DESCRIPTION: All the alerts will be returned at global level.

        Method: GET
        URL: /api/v1/alert/config/global/1
        DESCRIPTION: Alerts with id 1 will be returned at global level.

        Input Data:
        Valid alert id  for which information to be fetched.

        Input URL:
        /api/v1/alert/config/global/

        :return:

        [
          { "med_send_trap":false,"alert_template":"1", .....},
          { "med_send_trap":false,"alert_template":"2", .....},
          ...
        ]

        Input URL:
        /api/v1/alert/config/global/1

        :return:
        [
          { "med_send_trap":false,"alert_template":"1", .....}
        ]

        """

        status, res = utils.get_alerts(
            DashboardLevel.DB_GLOBAL, pem_conn=self.conn, alert_id=alert_id
        )
        if not status:
            return internal_server_error(errormsg=res)

        if alert_id is not None and len(res['rows']) == 0:
            return make_json_response(
                status=404, success=0,
                errormsg=gettext(
                    "The specified alert id is not applicable "
                    "for the specified agent"
                )
            )

        for alert in res['rows']:
            del alert['agent_id']
            del alert['server_id']
            del alert['database_name']
            del alert['schema_name']
            del alert['package_name']
            del alert['object_name']
            del alert['agent_desc']
            del alert['server_desc']
            del alert['email_group_name']
            del alert['frequency_default']
            del alert['med_email_group_name']
            del alert['default_history_retention']
            del alert['low_email_group_name']
            del alert['default_frequency']
            del alert['high_email_group_name']
            del alert['thresholds']
            del alert['history_retention_default']
            transform_snmp_version_value(alert, request)

            # Remove any unwanted params passed which are not applicable for
            # current api version.
            self.discard_unwanted_params(alert)

        return make_response(res['rows'])

    @check_precondition
    def delete(self, alert_id):
        """
        This function will delete the alerts at global level for specified
        alert id

        :param alert_id: Alert Id for which information will be fetched.

        Input Data:
        Valid alert id to delete the alert.

        e.g.
        /api/v1/alert/config/global/1

        :return:

        Below is the expected result.

        status: 200 OK
        {
          "success":1,
          "info":"Alert deleted successfully.",
          "result":null,
          "errormsg":"",
          "data":null
        }

        """
        # First check alert id exists or not.
        if alert_id is None:
            return make_json_response(
                status=404, success=0,
                errormsg=gettext(
                    "Please specify alert id you wish to delete."
                )
            )

        params = {
            'alert_id': alert_id
        }

        sql = render_template(
            "/".join([self.template_path, 'alert_exists.sql']),
            alert_id=alert_id
        )

        try:
            # Check the alert exists or not.
            status, al_exists = self.conn.execute_dict(sql, params)

            if not status:
                return internal_server_error(al_exists)

            if int(al_exists['rows'][0]['alert_count']) == 0:
                return make_json_response(
                    status=404, success=0,
                    errormsg=gettext("The specified alert id is not exists.")
                )
        except Exception as e:
            return internal_server_error(e)

        sql = render_template(
            "/".join([self.template_path, 'delete.sql'])
        )

        try:
            alert_ids = []
            alert_ids.append(alert_id)

            status, result = self.conn.execute_void(
                sql, {'alert_ids': alert_ids}
            )

            if not status:
                return internal_server_error(result)

        except Exception as e:
            return internal_server_error(e)

        return success_return(message=gettext('Alert deleted successfully.'))

    @check_precondition
    def put(self, alert_id):
        """
        This function will update alert parameters at global level.

        :param alert_id: Alert Id for which information will be fetched.

        Input Data: Below are the json input format required to update
        alert.

        Below are required data type for each input parameters.
        "alert_name": string,
        "alert_template": string, ( positive integer values. )
        "low_threshold_value": string, ( integer/float values. )
        "medium_threshold_value": string, ( integer/float values. )
        "high_threshold_value": string, (  integer/float values. )
        "history_retention": string, ( Possible values 1-99999 )
        "enabled": string, ( Possible values true and false)
        "frequency_min": string ( Possible values 1-65534 )
        "operator": string ( Valid string are ">" and "<")
        "params": list of dict values.

        Example input data as below.
        {
          "alert_name":"alert_name",
          "alert_template": "180",
          "low_threshold_value": "1",
          "medium_threshold_value": "2",
          "high_threshold_value": "3",
          "history_retention": 32,
          "enabled": true,
          "frequency_min": 11,
          "operator": ">",
          "params":
          {
            "changed": [
              {
                "paramvalue": "7",
                "paramname": "param_1"
              }
            ]
          }
        }

        :return:

        Below is the expected result.

        status: 200 OK
        {
          "success":1,
          "info":"Alert updated successfully.",
          "result":null,
          "errormsg":"",
          "data":null
        }

        """

        data = request.get_json()
        if data is None:
            return make_json_response(
                status=404, success=0,
                errormsg=gettext(
                    "Please specify input data for which you wish "
                    "to update the alert parameters."
                )
            )

        # First check alert id exists or not.
        if alert_id is None:
            return make_json_response(
                status=404, success=0,
                errormsg=gettext("Please specify alert id for which you wish"
                                 "to update the alert parameters.")
            )

        if 'send_trap' in data and data['send_trap'] is True and \
                'snmp_trap_version' in data and \
                request.blueprint in ['v1_api', 'v2_api'] and \
                not isinstance(data['snmp_trap_version'], bool):
            return make_json_response(
                status=404, success=0,
                errormsg=gettext("Invalid SNMP trap version value")
            )

        status, alerts = utils.get_alerts(
            DashboardLevel.DB_GLOBAL, pem_conn=self.conn, alert_id=alert_id
        )
        if not status:
            return internal_server_error(errormsg=alerts)

        if alert_id is not None and len(alerts['rows']) == 0:
            return make_json_response(
                status=404, success=0,
                errormsg=gettext("The specified alert id is not exists.")
            )

        # Check for duplicate alert name
        status, alerts = utils.get_alerts(
            DashboardLevel.DB_GLOBAL, pem_conn=self.conn
        )
        if not status:
            return internal_server_error(errormsg=alerts)

        if len(alerts['rows']) > 0 and 'alert_name' in data:
            for a_param in alerts['rows']:
                if a_param['alert_name'] == data['alert_name']:
                    return make_json_response(
                        status=404, success=0,
                        errormsg=gettext(
                            "The specified alert name already exists."
                        )
                    )

        data['id'] = alert_id

        data = transform_snmp_version_value(data, request)

        # remove any unwanted params passed which are not applicable for
        # current api version.
        data = self.discard_unwanted_params(data)

        # First validate all input parameters
        status, result = utils.validate_update_params(
            alert_id, DashboardLevel.DB_GLOBAL, data, self.is_edb, self.conn
        )
        if not status:
            return bad_request(result)

        # Update all input parameters
        status, result = utils.update_alert(data, self.conn)
        if not status:
            return internal_server_error(errormsg=result)

        return success_return(message=gettext('Alert updated successfully.'))

    @check_precondition
    def post(self):
        """
        This function will create new alert at global level.

        Input Data: Below are the json input format required to create
        new alert.

        Below are the mandatory parameters required to create the new
        alert and input are always dict of below values.

        "alert_name", "alert_template", "low_threshold_value",
        "medium_threshold_value", "high_threshold_value",
        "frequency_min", "operator", "history_retention", "enabled".
        If alert template requires then "params"

        Below are required data type for each input parameters.
        "alert_name": string,
        "alert_template": string, ( positive integer values. )
        "low_threshold_value": string, ( integer/flaot values. )
        "medium_threshold_value": string, ( integer/float values. )
        "high_threshold_value": string, (  integer/float values. )
        "history_retention": string, ( Possible values 1-99999 )
        "enabled": string, ( Possible values true and false)
        "frequency_min": string ( Possible values 1-65534 )
        "operator": string ( Valid string are ">" and "<")
        "params": list of dict values.

        Example input data as below.
        {
          "alert_name":"alert_name",
          "alert_template": "180",
          "low_threshold_value": "1",
          "medium_threshold_value": "2",
          "high_threshold_value": "3",
          "history_retention": 32,
          "enabled": true,
          "frequency_min": 11,
          "operator": ">",
          "params": [
            {
              "paramvalue": "7",
              "paramname": "param_1"
            }
          ]
        }

        :return:

        Below is the expected result.

        status: 200 OK
        {
          "success":1,
          "info":"Alert created successfully.",
          "result":null,
          "errormsg":"",
          "data":null
        }

        """

        data = request.get_json()
        if data is None:
            return make_json_response(
                status=404, success=0,
                errormsg=gettext(
                    "Please specify input data for which you wish "
                    "to create the alert."
                )
            )

        if 'send_trap' in data and data['send_trap'] is True and \
                'snmp_trap_version' in data and \
                request.blueprint in ['v1_api', 'v2_api'] and \
                not isinstance(data['snmp_trap_version'], bool):
            return make_json_response(
                status=404, success=0,
                errormsg=gettext("Invalid SNMP trap version value")
            )

        # Check for duplicate alert name
        status, alerts = utils.get_alerts(
            DashboardLevel.DB_GLOBAL, pem_conn=self.conn
        )
        if not status:
            return internal_server_error(errormsg=alerts)

        if len(alerts['rows']) > 0 and 'alert_name' in data:
            for a_param in alerts['rows']:
                if a_param['alert_name'] == data['alert_name']:
                    return make_json_response(
                        status=404, success=0,
                        errormsg=gettext(
                            "The specified alert name already exists."
                        )
                    )

        # Create the node information to create the new alert.
        node_info = {
            'target_type_id': DashboardLevel.DB_GLOBAL
        }

        data = transform_snmp_version_value(data, request)

        # remove any unwanted params passed which are not applicable for
        # current api version.
        data = self.discard_unwanted_params(data)

        # First validate all input parameters
        status, result = utils.validate_insert_params(
            DashboardLevel.DB_GLOBAL, data, self.is_edb, self.conn
        )
        if not status:
            return bad_request(result)

        status, result = utils.insert_alert(data, node_info, self.conn)
        if not status:
            return internal_server_error(errormsg=result)

        return success_return(message=gettext('Alert created successfully.'))


class AgentConfigApiView(ApiView):
    """
    API to expose the configuration of the alerts at agent level.
    """

    endpoint = 'agent_alert_config'
    url = '/alert/config/agent/<int:agent_id>/'
    pk = 'alert_id'
    conn = None
    template_path = None
    is_edb = 0
    api_versions = ['v1_api', 'v2_api', 'v3_api', 'v4_api']

    def __init__(self, *args, **kwargs):
        super(ApiView, self).__init__(*args, **kwargs)
        self.params = frozenset(upto_v4_params)

    def get(self, agent_id, alert_id=None, pem_conn=None):
        """
        This function will return the list of alerts for specified
        agent id.

        :param agent_id: Agent Id for which alerts will be fetched.
        :param alert_id: Alert Id for which information will be fetched.
        :param pem_conn: PEM connection object.

        Method: GET
        URL: /api/v1/alert/config/agent
        DESCRIPTION: All the alerts will be returned at agent level.

        Method: GET
        URL: /api/v1/alert/config/agent/1
        DESCRIPTION: Alerts with id 1 will be returned at agent level.

        Input Data:
        Valid alert id  for which information to be fetched.

        Input URL:
        /api/v1/alert/config/agent

        :return:

        [
          { "med_send_trap":false,"alert_template":"1", .....},
          { "med_send_trap":false,"alert_template":"2", .....},
          ...
        ]

        Input URL:
        /api/v1/alert/config/agent/1

        :return:
        [
          { "med_send_trap":false,"alert_template":"1", .....}
        ]

        """

        agent_exist = is_agent_exists(pem_conn, agent_id)
        if not agent_exist:
            return make_json_response(
                status=404, success=0,
                errormsg=gettext("The specified agent not found!")
            )

        status, res = utils.get_alerts(
            DashboardLevel.DB_AGENT, agent_id, pem_conn=pem_conn,
            alert_id=alert_id
        )
        if not status:
            return internal_server_error(errormsg=res)

        if alert_id is not None and len(res['rows']) == 0:
            return make_json_response(
                status=404, success=0,
                errormsg=gettext(
                    "The specified alert id is not applicable "
                    "for the specified agent"
                )
            )

        for alert in res['rows']:
            del alert['agent_id']
            del alert['server_id']
            del alert['database_name']
            del alert['schema_name']
            del alert['package_name']
            del alert['object_name']
            del alert['agent_desc']
            del alert['server_desc']
            del alert['email_group_name']
            del alert['frequency_default']
            del alert['med_email_group_name']
            del alert['default_history_retention']
            del alert['low_email_group_name']
            del alert['default_frequency']
            del alert['high_email_group_name']
            del alert['thresholds']
            del alert['history_retention_default']
            transform_snmp_version_value(alert, request)

            # Remove any unwanted params passed which are not applicable for
            # current api version.
            self.discard_unwanted_params(alert)

        return make_response(res['rows'])

    @check_precondition
    def delete(self, agent_id, alert_id=None):
        """
        This function will delete the alert for specified agent id.

        :param alert_id: Alert Id for which information will be deleted.
        :param agent_id: Agent Id for which alerts will be deleted.

        Input Data:
        Valid alert id to delete the alert.

        e.g.
        /api/v1/alert/config/agent/1

        :return:

        Below is the expected result.

        status: 200 OK
        {
          "success":1,
          "info":"Alert deleted successfully.",
          "result":null,
          "errormsg":"",
          "data":null
        }

        """
        # First check alert id exists or not.
        if alert_id is None:
            return make_json_response(
                status=404, success=0,
                errormsg=gettext("Please specify alert id you wish to delete")
            )

        if agent_id is None or agent_id == 0:
            return make_json_response(
                status=404, success=0,
                errormsg=gettext("Please specify valid agent id.")
            )

        params = {
            'alert_id': alert_id
        }

        sql = render_template(
            "/".join([self.template_path, 'alert_exists.sql']),
            alert_id=alert_id, agent_id=agent_id
        )

        try:
            # Check the alert exists or not.
            status, al_exists = self.conn.execute_dict(sql, params)

            if not status:
                return internal_server_error(al_exists)

            if int(al_exists['rows'][0]['alert_count']) == 0:
                return make_json_response(
                    status=404, success=0,
                    errormsg=gettext("The specified alert id is not exists.")
                )
        except Exception as e:
            return internal_server_error(e)

        sql = render_template(
            "/".join([self.template_path, 'delete.sql'])
        )

        try:
            alert_ids = []
            alert_ids.append(alert_id)

            status, result = self.conn.execute_void(
                sql, {'alert_ids': alert_ids}
            )

            if not status:
                return internal_server_error(result)

        except Exception as e:
            return internal_server_error(e)

        return success_return(message=gettext('Alert deleted successfully.'))

    @check_precondition
    def put(self, agent_id, alert_id):
        """
        This function will update the alert for specified agent id.

        :param agent_id: Agent Id for which alerts will be fetched.
        :param alert_id: Alert Id for which information will be fetched.

        Input Data: Below are the json input format required to update
        alert.

        Below are required data type for each input parameters.
        "alert_name": string,
        "alert_template": string, ( positive integer values. )
        "low_threshold_value": string, ( integer/flaot values. )
        "medium_threshold_value": string, ( integer/float values. )
        "high_threshold_value": string, (  integer/float values. )
        "history_retention": string, ( Possible values 1-99999 )
        "enabled": string, ( Possible values true and false)
        "frequency_min": string ( Possible values 1-65534 )
        "operator": string ( Valid string are ">" and "<")
        "params": list of dict values.

        Example input data as below.
        {
          "alert_name":"alert_name",
          "alert_template": "180",
          "low_threshold_value": "1",
          "medium_threshold_value": "2",
          "high_threshold_value": "3",
          "history_retention": 32,
          "enabled": true,
          "frequency_min": 11,
          "operator": ">",
          "params":
          {
            "changed": [
              {
                "paramvalue": "7",
                "paramname": "param_1"
              }
            ]
          }
        }

        :return:

        Below is the expected result.

        status: 200 OK
        {
          "success":1,
          "info":"Alert updated successfully.",
          "result":null,
          "errormsg":"",
          "data":null
        }

        """

        data = request.get_json()
        if data is None:
            return make_json_response(
                status=404, success=0,
                errormsg=gettext(
                    "Please specify input data for which you "
                    "wish to update the alert parameters."
                )
            )

        # Check agent exists or not.
        agent_exist = is_agent_exists(self.conn, agent_id)
        if not agent_exist:
            return make_json_response(
                status=404, success=0,
                errormsg=gettext("The specified agent not found!")
            )

        # First check alert id exists or not.
        if alert_id is None:
            return make_json_response(
                status=404, success=0,
                errormsg=gettext(
                    "Please specify alert id for which you wish "
                    "to update the alert parameters."
                )
            )

        if 'send_trap' in data and data['send_trap'] is True and \
                'snmp_trap_version' in data and \
                request.blueprint in ['v1_api', 'v2_api'] and \
                not isinstance(data['snmp_trap_version'], bool):
            return make_json_response(
                status=404, success=0,
                errormsg=gettext("Invalid SNMP trap version value")
            )

        status, alerts = utils.get_alerts(
            DashboardLevel.DB_AGENT, agent_id, pem_conn=self.conn,
            alert_id=alert_id
        )
        if not status:
            return internal_server_error(errormsg=alerts)

        if alert_id is not None and len(alerts['rows']) == 0:
            return make_json_response(
                status=404, success=0,
                errormsg=gettext(
                    "The specified alert id is not applicable "
                    "for the specified agent"
                )
            )

        # Check for duplicate alert name
        status, alerts = utils.get_alerts(
            DashboardLevel.DB_AGENT, agent_id, pem_conn=self.conn
        )
        if not status:
            return internal_server_error(errormsg=alerts)

        if len(alerts['rows']) > 0 and 'alert_name' in data:
            for a_param in alerts['rows']:
                if a_param['alert_name'] == data['alert_name']:
                    return make_json_response(
                        status=404, success=0,
                        errormsg=gettext(
                            "The specified alert name already exists."
                        )
                    )

        data['id'] = alert_id
        data = transform_snmp_version_value(data, request)

        # remove any unwanted params passed which are not applicable for
        # current api version.
        data = self.discard_unwanted_params(data)

        # First validate all input parameters
        status, result = utils.validate_update_params(
            alert_id, DashboardLevel.DB_AGENT, data, self.is_edb, self.conn
        )
        if not status:
            return bad_request(result)

        status, result = utils.update_alert(data, self.conn)
        if not status:
            return internal_server_error(errormsg=result)

        return success_return(message=gettext('Alert updated successfully.'))

    @check_precondition
    def post(self, agent_id):
        """
        This function will create new alert for specified agent id.

        :param agent_id: Agent Id for which alerts will be fetched.

        Input Data: Below are the json input format required to create
        new alert.

        Below are the mandatory parameters required to create the new
        alert and input are always dict of below values.

        "alert_name", "alert_template", "low_threshold_value",
        "medium_threshold_value", "high_threshold_value",
        "frequency_min", "operator", "history_retention", "enabled".
        If alert template requires then "params"

        Below are required data type for each input parameters.
        "alert_name": string,
        "alert_template": string, ( positive integer values. )
        "low_threshold_value": string, ( integer/float values. )
        "medium_threshold_value": string, ( integer/float values. )
        "high_threshold_value": string, (  integer/float values. )
        "history_retention": string, ( Possible values 1-99999 )
        "enabled": string, ( Possible values true and false)
        "frequency_min": string ( Possible values 1-65534 )
        "operator": string ( Valid string are ">" and "<")
        "params": list of dict values.

        Example input data as below.
        {
          "alert_name":"alert_name",
          "alert_template": "180",
          "low_threshold_value": "1",
          "medium_threshold_value": "2",
          "high_threshold_value": "3",
          "history_retention": 32,
          "enabled": true,
          "frequency_min": 11,
          "operator": ">",
          "params": [
            {
              "paramvalue": "7",
              "paramname": "param_1"
            }
          ]
        }

        :return:

        Below is the expected result.

        status: 200 OK
        {
          "success":1,
          "info":"Alert created successfully.",
          "result":null,
          "errormsg":"",
          "data":null
        }

        """

        data = request.get_json()
        if data is None:
            return make_json_response(
                status=404, success=0,
                errormsg=gettext(
                    "Please specify input data for which you wish "
                    "to create the alert."
                )
            )

        # Check agent exists or not.
        agent_exist = is_agent_exists(self.conn, agent_id)
        if not agent_exist:
            return make_json_response(
                status=404, success=0,
                errormsg=gettext("The specified agent not found!")
            )

        if 'send_trap' in data and data['send_trap'] is True and \
                'snmp_trap_version' in data and \
                request.blueprint in ['v1_api', 'v2_api'] and \
                not isinstance(data['snmp_trap_version'], bool):
            return make_json_response(
                status=404, success=0,
                errormsg=gettext("Invalid SNMP trap version value")
            )

        # Check for duplicate alert name
        status, alerts = utils.get_alerts(
            DashboardLevel.DB_AGENT, agent_id, pem_conn=self.conn
        )
        if not status:
            return internal_server_error(errormsg=alerts)

        if len(alerts['rows']) > 0 and 'alert_name' in data:
            for a_param in alerts['rows']:
                if a_param['alert_name'] == data['alert_name']:
                    return make_json_response(
                        status=404, success=0,
                        errormsg=gettext(
                            "The specified alert name already exists."
                        )
                    )

        # Create the node information to create the new alert.
        node_info = {
            'target_type_id': DashboardLevel.DB_AGENT,
            'agent_id': agent_id
        }

        data = transform_snmp_version_value(data, request)

        # remove any unwanted params passed which are not applicable for
        # current api version.
        data = self.discard_unwanted_params(data)

        # First validate all input parameters
        status, result = utils.validate_insert_params(
            DashboardLevel.DB_AGENT, data, self.is_edb, self.conn
        )
        if not status:
            return bad_request(result)

        status, result = utils.insert_alert(data, node_info, self.conn)
        if not status:
            return internal_server_error(errormsg=result)

        return success_return(message=gettext('Alert created successfully.'))


class ServerConfigApiView(ApiView):
    """
    API to expose the configuration of the alerts at server level.
    """

    endpoint = 'server_alert_config'
    url = '/alert/config/server/<int:server_id>/'
    pk = 'alert_id'
    api_versions = ['v1_api', 'v2_api', 'v3_api', 'v4_api']

    def __init__(self, *args, **kwargs):
        super(ApiView, self).__init__(*args, **kwargs)
        self.params = frozenset(upto_v4_params)

    def get(self, server_id, alert_id=None, pem_conn=None):
        """
        This function will return the list of alerts for specified server.

        :param server_id: Server Id for which alerts will be fetched.
        :param alert_id: Alert Id for which information will be fetched.
        :param pem_conn: PEM connection object

        Method: GET
        URL: /api/v1/alert/config/server
        DESCRIPTION: All the alerts will be returned at server level.

        Method: GET
        URL: /api/v1/alert/config/server/1
        DESCRIPTION: Alerts with id 1 will be returned at server level.

        Input Data:
        Valid alert id  for which information to be fetched.

        Input URL:
        /api/v1/alert/config/server

        :return:

        [
          { "med_send_trap":false,"alert_template":"1", .....},
          { "med_send_trap":false,"alert_template":"2", .....},
          ...
        ]

        Input URL:
        /api/v1/alert/config/server/1

        :return:
        [
          { "med_send_trap":false,"alert_template":"1", .....}
        ]

        """

        object_exist, msg = is_object_exists(pem_conn, 'server', server_id)
        if not object_exist:
            return make_json_response(
                status=404, success=0, errormsg=msg
            )

        status, res = utils.get_alerts(
            DashboardLevel.DB_SERVER, server_id, pem_conn=pem_conn,
            alert_id=alert_id
        )
        if not status:
            return internal_server_error(errormsg=res)

        if alert_id is not None and len(res['rows']) == 0:
            return make_json_response(
                status=404, success=0,
                errormsg=gettext(
                    "The specified alert id is not applicable "
                    "for the specified server"
                )
            )

        for alert in res['rows']:
            del alert['agent_id']
            del alert['server_id']
            del alert['database_name']
            del alert['schema_name']
            del alert['package_name']
            del alert['object_name']
            del alert['agent_desc']
            del alert['server_desc']
            del alert['email_group_name']
            del alert['frequency_default']
            del alert['med_email_group_name']
            del alert['default_history_retention']
            del alert['low_email_group_name']
            del alert['default_frequency']
            del alert['high_email_group_name']
            del alert['thresholds']
            del alert['history_retention_default']
            transform_snmp_version_value(alert, request)

            # Remove any unwanted params passed which are not applicable for
            # current api version.
            self.discard_unwanted_params(alert)

        return make_response(res['rows'])

    @check_precondition
    def delete(self, server_id, alert_id=None):
        """
        This function will delete the alert for specified server.

        :param alert_id: Alert Id for which information will be deleted.
        :param server_id: Server Id for which information will be deleted.

        Input Data:
        Valid alert id to delete the alert.

        e.g.
        /api/v1/alert/config/server/1

        :return:

        Below is the expected result.

        status: 200 OK
        {
          "success":1,
          "info":"Alert deleted successfully.",
          "result":null,
          "errormsg":"",
          "data":null
        }

        """
        # First check alert id exists or not.
        if alert_id is None:
            return make_json_response(
                status=404, success=0,
                errormsg=gettext("Please specify alert id you wish to delete")
            )

        if server_id is None or server_id == 0:
            return make_json_response(
                status=404, success=0,
                errormsg=gettext("Please specify valid server id.")
            )

        params = {
            'alert_id': alert_id
        }

        sql = render_template(
            "/".join([self.template_path, 'alert_exists.sql']),
            alert_id=alert_id, server_id=server_id
        )

        try:
            # Check the alert exists or not.
            status, al_exists = self.conn.execute_dict(sql, params)

            if not status:
                return internal_server_error(al_exists)

            if int(al_exists['rows'][0]['alert_count']) == 0:
                return make_json_response(
                    status=404, success=0,
                    errormsg=gettext("The specified alert id is not exists.")
                )
        except Exception as e:
            return internal_server_error(e)

        sql = render_template(
            "/".join([self.template_path, 'delete.sql'])
        )

        try:
            alert_ids = []
            alert_ids.append(alert_id)

            status, result = self.conn.execute_void(
                sql, {'alert_ids': alert_ids}
            )

            if not status:
                return internal_server_error(result)

        except Exception as e:
            return internal_server_error(e)

        return success_return(message=gettext('Alert deleted successfully.'))

    @check_precondition
    def put(self, server_id, alert_id=None):
        """
        This function will update the alert for specified server.

        :param server_id: Server Id for which alerts will be fetched.
        :param alert_id: Alert Id for which information will be fetched.

        Input Data: Below are the json input format required to update
        alert.

        Below are required data type for each input parameters.
        "alert_name": string,
        "alert_template": string, ( positive integer values. )
        "low_threshold_value": string, ( integer/flaot values. )
        "medium_threshold_value": string, ( integer/float values. )
        "high_threshold_value": string, (  integer/float values. )
        "history_retention": string, ( Possible values 1-99999 )
        "enabled": string, ( Possible values true and false)
        "frequency_min": string ( Possible values 1-65534 )
        "operator": string ( Valid string are ">" and "<")
        "params": list of dict values.

        Example input data as below.
        {
          "alert_name":"alert_name",
          "alert_template": "180",
          "low_threshold_value": "1",
          "medium_threshold_value": "2",
          "high_threshold_value": "3",
          "history_retention": 32,
          "enabled": true,
          "frequency_min": 11,
          "operator": ">",
          "params":
          {
            "changed": [
              {
                "paramvalue": "7",
                "paramname": "param_1"
              }
            ]
          }
        }

        :return:

        Below is the expected result.

        status: 200 OK
        {
          "success":1,
          "info":"Alert updated successfully.",
          "result":null,
          "errormsg":"",
          "data":null
        }

        """

        data = request.get_json()
        if data is None:
            return make_json_response(
                status=404, success=0,
                errormsg=gettext(
                    "Please specify input data for which you wish "
                    "to update the alert parameters."
                )
            )

        # Check server exists or not.
        object_exist, msg = is_object_exists(self.conn, 'server', server_id)
        if not object_exist:
            return make_json_response(
                status=404, success=0, errormsg=msg
            )

        # First check alert id exists or not.
        if alert_id is None:
            return make_json_response(
                status=404, success=0,
                errormsg=gettext(
                    "Please specify alert id for which you wish "
                    "to update the alert parameters."
                )
            )

        if 'send_trap' in data and data['send_trap'] is True and \
                'snmp_trap_version' in data and \
                request.blueprint in ['v1_api', 'v2_api'] and \
                not isinstance(data['snmp_trap_version'], bool):
            return make_json_response(
                status=404, success=0,
                errormsg=gettext("Invalid SNMP trap version value")
            )

        status, alerts = utils.get_alerts(
            DashboardLevel.DB_SERVER, server_id, pem_conn=self.conn,
            alert_id=alert_id
        )
        if not status:
            return internal_server_error(errormsg=alerts)

        if alert_id is not None and len(alerts['rows']) == 0:
            return make_json_response(
                status=404, success=0,
                errormsg=gettext(
                    "The specified alert id is not applicable "
                    "for the specified server"
                )
            )

        # Check for duplicate alert name
        status, alerts = utils.get_alerts(
            DashboardLevel.DB_SERVER, server_id, pem_conn=self.conn
        )
        if not status:
            return internal_server_error(errormsg=alerts)

        if len(alerts['rows']) > 0 and 'alert_name' in data:
            for a_param in alerts['rows']:
                if a_param['alert_name'] == data['alert_name']:
                    return make_json_response(
                        status=404, success=0,
                        errormsg=gettext(
                            "The specified alert name already exists."
                        )
                    )

        data['id'] = alert_id
        data = transform_snmp_version_value(data, request)

        # remove any unwanted params passed which are not applicable for
        # current api version.
        data = self.discard_unwanted_params(data)

        # First validate all input parameters
        status, result = utils.validate_update_params(
            alert_id, DashboardLevel.DB_SERVER, data, self.is_edb, self.conn
        )
        if not status:
            return bad_request(result)

        status, result = utils.update_alert(data, self.conn)
        if not status:
            return internal_server_error(errormsg=result)

        return success_return(message=gettext('Alert updated successfully.'))

    @check_precondition
    def post(self, server_id):
        """
        This function will create new alert for specified server.

        :param server_id: Server Id for which alerts will be created.

        Input Data: Below are the json input format required to create
        new alert.

        Below are the mandatory parameters required to create the new
        alert and input are always dict of below values.

        "alert_name", "alert_template", "low_threshold_value",
        "medium_threshold_value", "high_threshold_value",
        "frequency_min", "operator", "history_retention", "enabled".
        If alert template requires then "params"

        Below are required data type for each input parameters.
        "alert_name": string,
        "alert_template": string, ( positive integer values. )
        "low_threshold_value": string, ( integer/flaot values. )
        "medium_threshold_value": string, ( integer/float values. )
        "high_threshold_value": string, (  integer/float values. )
        "history_retention": string, ( Possible values 1-99999 )
        "enabled": string, ( Possible values true and false)
        "frequency_min": string ( Possible values 1-65534 )
        "operator": string ( Valid string are ">" and "<")
        "params": list of dict values.

        Example input data as below.
        {
          "alert_name":"alert_name",
          "alert_template": "180",
          "low_threshold_value": "1",
          "medium_threshold_value": "2",
          "high_threshold_value": "3",
          "history_retention": 32,
          "enabled": true,
          "frequency_min": 11,
          "operator": ">",
          "params": [
            {
              "paramvalue": "7",
              "paramname": "param_1"
            }
          ]
        }

        :return:

        Below is the expected result.

        status: 200 OK
        {
          "success":1,
          "info":"Alert created successfully.",
          "result":null,
          "errormsg":"",
          "data":null
        }

        """

        data = request.get_json()
        if data is None:
            return make_json_response(
                status=404, success=0,
                errormsg=gettext(
                    "Please specify input data for which you wish "
                    "to create the alert."
                )
            )

        # Check server exists or not.
        object_exist, msg = is_object_exists(self.conn, 'server', server_id)
        if not object_exist:
            return make_json_response(
                status=404, success=0, errormsg=msg
            )

        if 'send_trap' in data and data['send_trap'] is True and \
                'snmp_trap_version' in data and \
                request.blueprint in ['v1_api', 'v2_api'] and \
                not isinstance(data['snmp_trap_version'], bool):
            return make_json_response(
                status=404, success=0,
                errormsg=gettext("Invalid SNMP trap version value")
            )

        # Check for duplicate alert name
        status, alerts = utils.get_alerts(
            DashboardLevel.DB_SERVER, server_id, pem_conn=self.conn
        )
        if not status:
            return internal_server_error(errormsg=alerts)

        if len(alerts['rows']) > 0 and 'alert_name' in data:
            for a_param in alerts['rows']:
                if a_param['alert_name'] == data['alert_name']:
                    return make_json_response(
                        status=404, success=0,
                        errormsg=gettext(
                            "The specified alert name already exists."
                        )
                    )

        # Create the node information to create the new alert.
        node_info = {
            'target_type_id': DashboardLevel.DB_SERVER,
            'server_id': server_id
        }
        data = transform_snmp_version_value(data, request)

        # remove any unwanted params passed which are not applicable for
        # current api version.
        data = self.discard_unwanted_params(data)

        # First validate all input parameters
        status, result = utils.validate_insert_params(
            DashboardLevel.DB_SERVER, data, self.is_edb, self.conn
        )
        if not status:
            return bad_request(result)

        status, result = utils.insert_alert(data, node_info, self.conn)
        if not status:
            return internal_server_error(errormsg=result)

        return success_return(message=gettext('Alert created successfully.'))


class DatabaseConfigApiView(ApiView):
    """
    API to expose the configuration of the alerts at database level.
    """

    endpoint = 'database_alert_config'
    url = '/alert/config/server/<int:server_id>/database/<database_name>/'
    pk = 'alert_id'
    # conn = None
    # template_path = None
    is_edb = 0
    api_versions = ['v1_api', 'v2_api', 'v3_api', 'v4_api']

    def __init__(self, *args, **kwargs):
        super(ApiView, self).__init__(*args, **kwargs)
        self.params = frozenset(upto_v4_params)

    def get(self, server_id, database_name, alert_id=None, pem_conn=None):
        """
        This function will return the list of alerts for specified
        server and database.

        :param server_id: Server Id
        :param database_name: Database Name for which alerts will be fetched.
        :param alert_id: Alert Id for which information will be fetched.
        :param pem_conn: PEM connection object.

        Method: GET
        URL: /api/v1/alert/config/database/1/postgres
        DESCRIPTION: All the alerts will be returned at database level.

        Method: GET
        URL: /api/v1/alert/config/database/1/postgres/1
        DESCRIPTION: Alerts with id 1 will be returned at database level.

        Input Data:
        Valid alert id  for which information to be fetched.

        Input URL:
        /api/v1/alert/config/database/1/postgres

        :return:

        [
          { "med_send_trap":false,"alert_template":"1", .....},
          { "med_send_trap":false,"alert_template":"2", .....},
          ...
        ]

        Input URL:
        /api/v1/alert/config/database/1/postgres/1

        :return:
        [
          { "med_send_trap":false,"alert_template":"1", .....}
        ]

        """

        object_exist, msg = is_object_exists(pem_conn, 'database', server_id,
                                             database_name)
        if not object_exist:
            return make_json_response(
                status=404, success=0, errormsg=msg
            )

        status, res = utils.get_alerts(
            DashboardLevel.DB_DATABASE, server_id, database_name,
            pem_conn=pem_conn, alert_id=alert_id
        )
        if not status:
            return internal_server_error(errormsg=res)

        if alert_id is not None and len(res['rows']) == 0:
            return make_json_response(
                status=404, success=0,
                errormsg=gettext(
                    "The specified alert id is not applicable "
                    "for the specified database"
                )
            )

        for alert in res['rows']:
            del alert['agent_id']
            del alert['server_id']
            del alert['database_name']
            del alert['schema_name']
            del alert['package_name']
            del alert['object_name']
            del alert['agent_desc']
            del alert['server_desc']
            del alert['email_group_name']
            del alert['frequency_default']
            del alert['med_email_group_name']
            del alert['default_history_retention']
            del alert['low_email_group_name']
            del alert['default_frequency']
            del alert['high_email_group_name']
            del alert['thresholds']
            del alert['history_retention_default']
            transform_snmp_version_value(alert, request)

            # Remove any unwanted params passed which are not applicable for
            # current api version.
            self.discard_unwanted_params(alert)

        return make_response(res['rows'])

    @check_precondition
    def delete(self, server_id, database_name, alert_id=None):
        """
        This function will delete the alert for specified server and database.

        :param server_id: Server Id
        :param database_name: Database Name for which alerts will be deleted.
        :param alert_id: Alert Id for which information will be deleted.

        Input Data:
        Valid alert id to delete the alert.

        e.g.
        /api/v1/alert/config/database/1/postgres/1

        :return:

        Below is the expected result.

        status: 200 OK
        {
          "success":1,
          "info":"Alert deleted successfully.",
          "result":null,
          "errormsg":"",
          "data":null
        }

        """
        # First check alert id exists or not.
        if alert_id is None:
            return make_json_response(
                status=404, success=0,
                errormsg=gettext("Please specify alert id you wish to delete")
            )

        if server_id is None or server_id == 0:
            return make_json_response(
                status=404, success=0,
                errormsg=gettext("Please specify valid server id.")
            )

        if database_name is None and not database_name:
            return make_json_response(
                status=404, success=0,
                errormsg=gettext("Please specify valid database name.")
            )

        params = {
            'alert_id': alert_id
        }

        sql = render_template(
            "/".join([self.template_path, 'alert_exists.sql']),
            alert_id=alert_id, server_id=server_id,
            database_name=database_name
        )

        try:
            # Check the alert exists or not.
            status, al_exists = self.conn.execute_dict(sql, params)

            if not status:
                return internal_server_error(al_exists)

            if int(al_exists['rows'][0]['alert_count']) == 0:
                return make_json_response(
                    status=404, success=0,
                    errormsg=gettext("The specified alert id is not exists.")
                )
        except Exception as e:
            return internal_server_error(e)

        sql = render_template(
            "/".join([self.template_path, 'delete.sql'])
        )

        try:
            alert_ids = []
            alert_ids.append(alert_id)

            status, result = self.conn.execute_void(
                sql, {'alert_ids': alert_ids}
            )

            if not status:
                return internal_server_error(result)

        except Exception as e:
            return internal_server_error(e)

        return success_return(message=gettext('Alert deleted successfully.'))

    @check_precondition
    def put(self, server_id, database_name, alert_id=None):
        """
        This function will update the alert for specified server and database.

        :param server_id: Server Id for which alerts will be fetched.
        :param database_name: Database Name for which alerts will be fetched.
        :param alert_id: Alert Id for which information will be fetched.

        Input Data: Below are the json input format required to update
        alert.

        Below are required data type for each input parameters.
        "alert_name": string,
        "alert_template": string, ( positive integer values. )
        "low_threshold_value": string, ( integer/flaot values. )
        "medium_threshold_value": string, ( integer/float values. )
        "high_threshold_value": string, (  integer/float values. )
        "history_retention": string, ( Possible values 1-99999 )
        "enabled": string, ( Possible values true and false)
        "frequency_min": string ( Possible values 1-65534 )
        "operator": string ( Valid string are ">" and "<")
        "params": list of dict values.

        Example input data as below.
        {
          "alert_name":"alert_name",
          "alert_template": "180",
          "low_threshold_value": "1",
          "medium_threshold_value": "2",
          "high_threshold_value": "3",
          "history_retention": 32,
          "enabled": true,
          "frequency_min": 11,
          "operator": ">",
          "params":
          {
            "changed": [
              {
                "paramvalue": "7",
                "paramname": "param_1"
              }
            ]
          }
        }

        :return:

        Below is the expected result.

        status: 200 OK
        {
          "success":1,
          "info":"Alert updated successfully.",
          "result":null,
          "errormsg":"",
          "data":null
        }

        """

        data = request.get_json()
        if data is None:
            return make_json_response(
                status=404, success=0,
                errormsg=gettext(
                    "Please specify input data for which you wish "
                    "to update the alert parameters."
                )
            )

        # Check database exists or not.
        object_exist, msg = is_object_exists(self.conn, 'database', server_id,
                                             database_name)
        if not object_exist:
            return make_json_response(
                status=404, success=0, errormsg=msg
            )

        # First check alert id exists or not.
        if alert_id is None:
            return make_json_response(
                status=404, success=0,
                errormsg=gettext(
                    "Please specify alert id for which you wish "
                    "to update the alert parameters."
                )
            )

        if 'send_trap' in data and data['send_trap'] is True and \
                'snmp_trap_version' in data and \
                request.blueprint in ['v1_api', 'v2_api'] and \
                not isinstance(data['snmp_trap_version'], bool):
            return make_json_response(
                status=404, success=0,
                errormsg=gettext("Invalid SNMP trap version value")
            )

        status, alerts = utils.get_alerts(
            DashboardLevel.DB_DATABASE, server_id, database_name,
            pem_conn=self.conn, alert_id=alert_id
        )
        if not status:
            return internal_server_error(errormsg=alerts)

        if alert_id is not None and len(alerts['rows']) == 0:
            return make_json_response(
                status=404, success=0,
                errormsg=gettext(
                    "The specified alert id is not applicable "
                    "for the specified database"
                )
            )

        # Check for duplicate alert name
        status, alerts = utils.get_alerts(
            DashboardLevel.DB_DATABASE, server_id, database_name,
            pem_conn=self.conn
        )
        if not status:
            return internal_server_error(errormsg=alerts)

        if len(alerts['rows']) > 0 and 'alert_name' in data:
            for a_param in alerts['rows']:
                if a_param['alert_name'] == data['alert_name']:
                    return make_json_response(
                        status=404, success=0,
                        errormsg=gettext(
                            "The specified alert name already exists."
                        )
                    )

        data['id'] = alert_id
        data = transform_snmp_version_value(data, request)

        # remove any unwanted params passed which are not applicable for
        # current api version.
        data = self.discard_unwanted_params(data)

        # First validate all input parameters
        status, result = \
            utils.validate_update_params(alert_id, DashboardLevel.DB_DATABASE,
                                         data, self.is_edb, self.conn)
        if not status:
            return bad_request(result)

        status, result = utils.update_alert(data, self.conn)
        if not status:
            return internal_server_error(errormsg=result)

        return success_return(message=gettext('Alert updated successfully.'))

    @check_precondition
    def post(self, server_id, database_name):
        """
        This function will create the new alert for specified server
        and database.

        :param server_id: Server Id for which alerts will be created.
        :param database_name: Database Name for which alerts will be created.

        Input Data: Below are the json input format required to create
        new alert.

        Below are the mandatory parameters required to create the new
        alert and input are always dict of below values.

        "alert_name", "alert_template", "low_threshold_value",
        "medium_threshold_value", "high_threshold_value",
        "frequency_min", "operator", "history_retention", "enabled".
        If alert template requires then "params"

        Below are required data type for each input parameters.
        "alert_name": string,
        "alert_template": string, ( positive integer values. )
        "low_threshold_value": string, ( integer/float values. )
        "medium_threshold_value": string, ( integer/float values. )
        "high_threshold_value": string, (  integer/float values. )
        "history_retention": string, ( Possible values 1-99999 )
        "enabled": string, ( Possible values true and false)
        "frequency_min": string ( Possible values 1-65534 )
        "operator": string ( Valid string are ">" and "<")
        "params": list of dict values.

        Example input data as below.
        {
          "alert_name":"alert_name",
          "alert_template": "180",
          "low_threshold_value": "1",
          "medium_threshold_value": "2",
          "high_threshold_value": "3",
          "history_retention": 32,
          "enabled": true,
          "frequency_min": 11,
          "operator": ">",
          "params": [
            {
              "paramvalue": "7",
              "paramname": "param_1"
            }
          ]
        }

        :return:

        Below is the expected result.

        status: 200 OK
        {
          "success":1,
          "info":"Alert created successfully.",
          "result":null,
          "errormsg":"",
          "data":null
        }

        """

        data = request.get_json()
        if data is None:
            return make_json_response(
                status=404, success=0,
                errormsg=gettext(
                    "Please specify input data for which you wish "
                    "to create the alert."
                )
            )

        # Check database exists or not.
        object_exist, msg = is_object_exists(self.conn, 'database', server_id,
                                             database_name)
        if not object_exist:
            return make_json_response(
                status=404, success=0, errormsg=msg
            )

        if 'send_trap' in data and data['send_trap'] is True and \
                'snmp_trap_version' in data and \
                request.blueprint in ['v1_api', 'v2_api'] and \
                not isinstance(data['snmp_trap_version'], bool):
            return make_json_response(
                status=404, success=0,
                errormsg=gettext("Invalid SNMP trap version value")
            )

        # Check for duplicate alert name
        status, alerts = utils.get_alerts(
            DashboardLevel.DB_DATABASE, server_id, database_name,
            pem_conn=self.conn
        )
        if not status:
            return internal_server_error(errormsg=alerts)

        if len(alerts['rows']) > 0 and 'alert_name' in data:
            for a_param in alerts['rows']:
                if a_param['alert_name'] == data['alert_name']:
                    return make_json_response(
                        status=404, success=0,
                        errormsg=gettext(
                            "The specified alert name already exists."
                        )
                    )

        # Create the node information to create the new alert.
        node_info = {
            'target_type_id': DashboardLevel.DB_DATABASE,
            'server_id': server_id,
            'database_name': database_name
        }
        data = transform_snmp_version_value(data, request)

        # remove any unwanted params passed which are not applicable for
        # current api version.
        data = self.discard_unwanted_params(data)

        # First validate all input parameters
        status, result = \
            utils.validate_insert_params(DashboardLevel.DB_DATABASE, data,
                                         self.is_edb, self.conn)
        if not status:
            return bad_request(result)

        status, result = utils.insert_alert(data, node_info, self.conn)
        if not status:
            return internal_server_error(errormsg=result)

        return success_return(message=gettext('Alert created successfully.'))


class SchemaConfigApiView(ApiView):
    """
    API to expose the configuration of the alerts at schema level.
    """

    endpoint = 'schema_alert_config'
    url = '/alert/config/server/<int:server_id>/database/<database_name>/' \
          'schema/<schema_name>/'
    pk = 'alert_id'
    conn = None
    template_path = None
    is_edb = 0
    api_versions = ['v1_api', 'v2_api', 'v3_api', 'v4_api']

    def __init__(self, *args, **kwargs):
        super(ApiView, self).__init__(*args, **kwargs)
        self.params = frozenset(upto_v4_params)

    def get(self, server_id, database_name,
            schema_name, alert_id=None, pem_conn=None):
        """
        This function will return the list of alerts for
        specified server, database and schema.

        :param server_id: Server Id
        :param database_name: Database Name
        :param schema_name: Schema Name for which alerts will be fetched.
        :param alert_id: Alert Id for which information will be fetched.
        :param pem_conn: PEM connection object.

        Method: GET
        URL: /api/v1/alert/config/schema/1/postgres/public
        DESCRIPTION: All the alerts will be returned at schema level.

        Method: GET
        URL: /api/v1/alert/config/schema/1/postgres/public/1
        DESCRIPTION: Alerts with id 1 will be returned at schema level.

        Input Data:
        Valid alert id for which information to be fetched.

        Input URL:
        /api/v1/alert/config/schema/1/postgres/public

        :return:

        [
          { "med_send_trap":false,"alert_template":"1", .....},
          { "med_send_trap":false,"alert_template":"2", .....},
          ...
        ]

        Input URL:
        /api/v1/alert/config/schema/1/postgres/public/1

        :return:
        [
          { "med_send_trap":false,"alert_template":"1", .....}
        ]

        """

        object_exist, msg = is_object_exists(pem_conn, 'schema', server_id,
                                             database_name, schema_name)
        if not object_exist:
            return make_json_response(
                status=404, success=0, errormsg=msg
            )

        status, res = utils.get_alerts(
            DashboardLevel.DB_SCHEMA, server_id, database_name,
            schema_name, pem_conn=pem_conn, alert_id=alert_id
        )
        if not status:
            return internal_server_error(errormsg=res)

        if alert_id is not None and len(res['rows']) == 0:
            return make_json_response(
                status=404, success=0,
                errormsg=gettext(
                    "The specified alert id is not applicable "
                    "for the specified schema"
                )
            )

        for alert in res['rows']:
            del alert['agent_id']
            del alert['server_id']
            del alert['database_name']
            del alert['schema_name']
            del alert['package_name']
            del alert['object_name']
            del alert['agent_desc']
            del alert['server_desc']
            del alert['email_group_name']
            del alert['frequency_default']
            del alert['med_email_group_name']
            del alert['default_history_retention']
            del alert['low_email_group_name']
            del alert['default_frequency']
            del alert['high_email_group_name']
            del alert['thresholds']
            del alert['history_retention_default']
            transform_snmp_version_value(alert, request)

            # Remove any unwanted params passed which are not applicable for
            # current api version.
            self.discard_unwanted_params(alert)

        return make_response(res['rows'])

    @check_precondition
    def delete(self, server_id, database_name, schema_name, alert_id=None):
        """
        This function will delete the alert for specified server, database and
        schema.

        :param alert_id: Alert Id for which information will be deleted.
        :param server_id: server Id for which information will be deleted.
        :param database_name: Database name for which information will be
        deleted.
        :param schema_name: Schema name for which information will be deleted

        Input Data:
        Valid alert id to delete the alert.

        e.g.
        /api/v1/alert/config/schema/1/postgres/public/1

        :return:

        Below is the expected result.

        status: 200 OK
        {
          "success":1,
          "info":"Alert deleted successfully.",
          "result":null,
          "errormsg":"",
          "data":null
        }

        """
        # First check alert id exists or not.
        if alert_id is None:
            return make_json_response(
                status=404, success=0,
                errormsg=gettext("Please specify alert id you wish to delete")
            )

        if server_id is None or server_id == 0:
            return make_json_response(
                status=404, success=0,
                errormsg=gettext("Please specify valid server id.")
            )

        if database_name is None and not database_name:
            return make_json_response(
                status=404, success=0,
                errormsg=gettext("Please specify valid database name.")
            )

        if schema_name is None and not schema_name:
            return make_json_response(
                status=404, success=0,
                errormsg=gettext("Please specify valid schema name.")
            )

        params = {
            'alert_id': alert_id
        }

        sql = render_template(
            "/".join([self.template_path, 'alert_exists.sql']),
            alert_id=alert_id, server_id=server_id,
            database_name=database_name, schema_name=schema_name
        )

        try:
            # Check the alert exists or not.
            status, al_exists = self.conn.execute_dict(sql, params)

            if not status:
                return internal_server_error(al_exists)

            if int(al_exists['rows'][0]['alert_count']) == 0:
                return make_json_response(
                    status=404, success=0,
                    errormsg=gettext("The specified alert id is not exists.")
                )
        except Exception as e:
            return internal_server_error(e)

        sql = render_template(
            "/".join([self.template_path, 'delete.sql'])
        )

        try:
            alert_ids = []
            alert_ids.append(alert_id)

            status, result = self.conn.execute_void(
                sql, {'alert_ids': alert_ids}
            )

            if not status:
                return internal_server_error(result)

        except Exception as e:
            return internal_server_error(e)

        return success_return(message=gettext('Alert deleted successfully.'))

    @check_precondition
    def put(self, server_id, database_name,
            schema_name, alert_id=None):
        """
        This function will update the alert for specified
        server, database and schema

        :param server_id: Server Id for which alerts will be fetched.
        :param database_name: Database Name for which alerts will be fetched.
        :param schema_name: Schema Name for which alerts will be fetched.
        :param alert_id: Alert Id for which information will be fetched.

        Input Data: Below are the json input format required to update
        alert.

        Below are required data type for each input parameters.
        "alert_name": string,
        "alert_template": string, ( positive integer values. )
        "low_threshold_value": string, ( integer/float values. )
        "medium_threshold_value": string, ( integer/float values. )
        "high_threshold_value": string, (  integer/float values. )
        "history_retention": string, ( Possible values 1-99999 )
        "enabled": string, ( Possible values true and false)
        "frequency_min": string ( Possible values 1-65534 )
        "operator": string ( Valid string are ">" and "<")
        "params": list of dict values.

        Example input data as below.
        {
          "alert_name":"alert_name",
          "alert_template": "180",
          "low_threshold_value": "1",
          "medium_threshold_value": "2",
          "high_threshold_value": "3",
          "history_retention": 32,
          "enabled": true,
          "frequency_min": 11,
          "operator": ">",
          "params":
          {
            "changed": [
              {
                "paramvalue": "7",
                "paramname": "param_1"
              }
            ]
          }
        }

        :return:

        Below is the expected result.

        status: 200 OK
        {
          "success":1,
          "info":"Alert updated successfully.",
          "result":null,
          "errormsg":"",
          "data":null
        }

        """

        data = request.get_json()
        if data is None:
            return make_json_response(
                status=404, success=0,
                errormsg=gettext(
                    "Please specify input data for which you wish to "
                    "update the alert parameters."
                )
            )

        object_exist, msg = is_object_exists(self.conn, 'schema', server_id,
                                             database_name, schema_name)
        if not object_exist:
            return make_json_response(
                status=404, success=0, errormsg=msg
            )

        # First check alert id exists or not.
        if alert_id is None:
            return make_json_response(
                status=404, success=0,
                errormsg=gettext(
                    "Please specify alert id for which you wish to "
                    "update the alert parameters."
                )
            )

        if 'send_trap' in data and data['send_trap'] is True and \
                'snmp_trap_version' in data and \
                request.blueprint in ['v1_api', 'v2_api'] and \
                not isinstance(data['snmp_trap_version'], bool):
            return make_json_response(
                status=404, success=0,
                errormsg=gettext("Invalid SNMP trap version value")
            )

        status, alerts = utils.get_alerts(
            DashboardLevel.DB_SCHEMA, server_id, database_name,
            schema_name, pem_conn=self.conn, alert_id=alert_id
        )
        if not status:
            return internal_server_error(errormsg=alerts)

        if alert_id is not None and len(alerts['rows']) == 0:
            return make_json_response(
                status=404, success=0,
                errormsg=gettext(
                    "The specified alert id is not applicable for "
                    "the specified schema"
                )
            )

        # Check for duplicate alert name
        status, alerts = utils.get_alerts(
            DashboardLevel.DB_SCHEMA, server_id, database_name,
            schema_name, pem_conn=self.conn
        )
        if not status:
            return internal_server_error(errormsg=alerts)

        if len(alerts['rows']) > 0 and 'alert_name' in data:
            for a_param in alerts['rows']:
                if a_param['alert_name'] == data['alert_name']:
                    return make_json_response(
                        status=404, success=0,
                        errormsg=gettext(
                            "The specified alert name already exists."
                        )
                    )

        data['id'] = alert_id
        data = transform_snmp_version_value(data, request)

        # remove any unwanted params passed which are not applicable for
        # current api version.
        data = self.discard_unwanted_params(data)

        # First validate all input parameters
        status, result = utils.validate_update_params(
            alert_id, DashboardLevel.DB_SCHEMA, data, self.is_edb, self.conn
        )
        if not status:
            return bad_request(result)

        status, result = utils.update_alert(data, self.conn)
        if not status:
            return internal_server_error(errormsg=result)

        return success_return(message=gettext('Alert updated successfully.'))

    @check_precondition
    def post(self, server_id, database_name, schema_name):
        """
        This function will create the new alert for specified
        server, database and schema.

        :param server_id: Server Id for which alerts will be created.
        :param database_name: Database Name for which alerts will be created.
        :param schema_name: Schema Name for which alerts will be created.

        Input Data: Below are the json input format required to create
        new alert.

        Below are the mandatory parameters required to create the new
        alert and input are always dict of below values.

        "alert_name", "alert_template", "low_threshold_value",
        "medium_threshold_value", "high_threshold_value",
        "frequency_min", "operator", "history_retention", "enabled".
        If alert template requires then "params"

        Below are required data type for each input parameters.
        "alert_name": string,
        "alert_template": string, ( positive integer values. )
        "low_threshold_value": string, ( integer/float values. )
        "medium_threshold_value": string, ( integer/float values. )
        "high_threshold_value": string, (  integer/float values. )
        "history_retention": string, ( Possible values 1-99999 )
        "enabled": string, ( Possible values true and false)
        "frequency_min": string ( Possible values 1-65534 )
        "operator": string ( Valid string are ">" and "<")
        "params": list of dict values.

        Example input data as below.
        {
          "alert_name":"alert_name",
          "alert_template": "180",
          "low_threshold_value": "1",
          "medium_threshold_value": "2",
          "high_threshold_value": "3",
          "history_retention": 32,
          "enabled": true,
          "frequency_min": 11,
          "operator": ">",
          "params": [
            {
              "paramvalue": "7",
              "paramname": "param_1"
            }
          ]
        }

        :return:

        Below is the expected result.

        status: 200 OK
        {
          "success":1,
          "info":"Alert created successfully.",
          "result":null,
          "errormsg":"",
          "data":null
        }

        """

        data = request.get_json()
        if data is None:
            return make_json_response(
                status=404, success=0,
                errormsg=gettext(
                    "Please specify input data for which you wish to "
                    "create the alert."
                )
            )

        object_exist, msg = is_object_exists(self.conn, 'schema', server_id,
                                             database_name, schema_name)
        if not object_exist:
            return make_json_response(
                status=404, success=0, errormsg=msg
            )

        if 'send_trap' in data and data['send_trap'] is True and \
                'snmp_trap_version' in data and \
                request.blueprint in ['v1_api', 'v2_api'] and \
                not isinstance(data['snmp_trap_version'], bool):
            return make_json_response(
                status=404, success=0,
                errormsg=gettext("Invalid SNMP trap version value")
            )

        # Check for duplicate alert name
        status, alerts = utils.get_alerts(
            DashboardLevel.DB_SCHEMA, server_id, database_name,
            schema_name, pem_conn=self.conn
        )
        if not status:
            return internal_server_error(errormsg=alerts)

        if len(alerts['rows']) > 0 and 'alert_name' in data:
            for a_param in alerts['rows']:
                if a_param['alert_name'] == data['alert_name']:
                    return make_json_response(
                        status=404, success=0,
                        errormsg=gettext(
                            "The specified alert name already exists."
                        )
                    )

        # Create the node information to create the new alert.
        node_info = {
            'target_type_id': DashboardLevel.DB_SCHEMA,
            'server_id': server_id,
            'database_name': database_name,
            'schema_name': schema_name,
        }

        data = transform_snmp_version_value(data, request)

        # remove any unwanted params passed which are not applicable for
        # current api version.
        data = self.discard_unwanted_params(data)

        # First validate all input parameters
        status, result = utils.validate_insert_params(
            DashboardLevel.DB_SCHEMA, data, self.is_edb, self.conn
        )
        if not status:
            return bad_request(result)

        status, result = utils.insert_alert(data, node_info, self.conn)
        if not status:
            return internal_server_error(errormsg=result)

        return success_return(message=gettext('Alert created successfully.'))


class TableConfigApiView(ApiView):
    """
    API to expose the configuration of the alerts at table level.
    """

    endpoint = 'table_alert_config'
    url = '/alert/config/server/<int:server_id>/' \
          'database/<string:database_name>/' \
          'schema/<schema_name>/table/<object_name>/'
    pk = 'alert_id'
    conn = None
    template_path = None
    is_edb = 0
    api_versions = ['v1_api', 'v2_api', 'v3_api', 'v4_api']

    def __init__(self, *args, **kwargs):
        super(ApiView, self).__init__(*args, **kwargs)
        self.params = frozenset(upto_v4_params)

    def get(self, server_id, database_name, schema_name,
            object_name, alert_id=None, pem_conn=None):
        """
        This function will return the list of alerts for
        specified server, database, schema and table.

        :param server_id: Server Id
        :param database_name: Database Name
        :param schema_name: Schema Name
        :param object_name: Table Name for which alerts will be fetched.
        :param alert_id: Alert Id for which information will be fetched.
        :param pem_conn: PEM connection object.

        Method: GET
        URL: /api/v1/alert/config/table/1/postgres/public/alert
        DESCRIPTION: All the alerts will be returned at table level.

        Method: GET
        URL: /api/v1/alert/config/table/1/postgres/public/alert/1
        DESCRIPTION: Alerts with id 1 will be returned at table level.

        Input Data:
        Valid alert id for which information to be fetched.

        Input URL:
        /api/v1/alert/config/table/1/postgres/public/alert

        :return:

        [
          { "med_send_trap":false,"alert_template":"1", .....},
          { "med_send_trap":false,"alert_template":"2", .....},
          ...
        ]

        Input URL:
        /api/v1/alert/config/table/1/postgres/public/alert/1

        :return:
        [
          { "med_send_trap":false,"alert_template":"1", .....}
        ]

        :return:
        """

        object_exist, msg = is_object_exists(pem_conn, 'table', server_id,
                                             database_name, schema_name,
                                             object_name)
        if not object_exist:
            return make_json_response(
                status=404, success=0, errormsg=msg
            )

        status, res = utils.get_alerts(
            DashboardLevel.DB_TABLE, server_id, database_name,
            schema_name, object_name, pem_conn=pem_conn, alert_id=alert_id
        )
        if not status:
            return internal_server_error(errormsg=res)

        if alert_id is not None and len(res['rows']) == 0:
            return make_json_response(
                status=404, success=0,
                errormsg=gettext(
                    "The specified alert id is not applicable for "
                    "the specified table"
                )
            )

        for alert in res['rows']:
            del alert['agent_id']
            del alert['server_id']
            del alert['database_name']
            del alert['schema_name']
            del alert['package_name']
            del alert['object_name']
            del alert['agent_desc']
            del alert['server_desc']
            del alert['email_group_name']
            del alert['frequency_default']
            del alert['med_email_group_name']
            del alert['default_history_retention']
            del alert['low_email_group_name']
            del alert['default_frequency']
            del alert['high_email_group_name']
            del alert['thresholds']
            del alert['history_retention_default']
            transform_snmp_version_value(alert, request)

            # Remove any unwanted params passed which are not applicable for
            # current api version.
            self.discard_unwanted_params(alert)

        return make_response(res['rows'])

    @check_precondition
    def delete(self, server_id, database_name, schema_name, object_name,
               alert_id=None):
        """
        This function will delete the alert for specified
        server, database, schema and table.

        :param server_id: Server Id
        :param database_name: Database Name
        :param schema_name: Schema Name
        :param object_name: Table Name for which alerts will be deleted.
        :param alert_id: Alert Id for which information will be deleted.

        Input Data:
        Valid alert id to delete the alert.

        e.g.
        /api/v1/alert/config/table/1/postgres/public/alert/1

        :return:

        Below is the expected result.

        status: 200 OK
        {
          "success":1,
          "info":"Alert deleted successfully.",
          "result":null,
          "errormsg":"",
          "data":null
        }

        """
        # First check alert id exists or not.
        if alert_id is None:
            return make_json_response(
                status=404, success=0,
                errormsg=gettext("Please specify alert id you wish to delete")
            )

        if server_id is None or server_id == 0:
            return make_json_response(
                status=404, success=0,
                errormsg=gettext("Please specify valid server id.")
            )

        if database_name is None and not database_name:
            return make_json_response(
                status=404, success=0,
                errormsg=gettext("Please specify valid database name.")
            )

        if schema_name is None and not schema_name:
            return make_json_response(
                status=404, success=0,
                errormsg=gettext("Please specify valid schema name.")
            )

        if object_name is None and not object_name:
            return make_json_response(
                status=404, success=0,
                errormsg=gettext("Please specify valid table name.")
            )

        params = {
            'alert_id': alert_id
        }

        sql = render_template(
            "/".join([self.template_path, 'alert_exists.sql']),
            alert_id=alert_id, server_id=server_id,
            database_name=database_name, schema_name=schema_name,
            object_name=object_name
        )

        try:
            # Check the alert exists or not.
            status, al_exists = self.conn.execute_dict(sql, params)

            if not status:
                return internal_server_error(al_exists)

            if int(al_exists['rows'][0]['alert_count']) == 0:
                return make_json_response(
                    status=404, success=0,
                    errormsg=gettext("The specified alert id is not exists.")
                )
        except Exception as e:
            return internal_server_error(e)

        sql = render_template(
            "/".join([self.template_path, 'delete.sql'])
        )

        try:
            alert_ids = []
            alert_ids.append(alert_id)

            status, result = self.conn.execute_void(
                sql, {'alert_ids': alert_ids}
            )

            if not status:
                return internal_server_error(result)

        except Exception as e:
            return internal_server_error(e)

        return success_return(message=gettext('Alert deleted successfully.'))

    @check_precondition
    def put(self, server_id, database_name, schema_name,
            object_name, alert_id=None):
        """
        This function will update the alert for specified
        server, database, schema and table.

        :param server_id: Server Id for which alerts will be fetched.
        :param database_name: Database Name for which alerts will be fetched.
        :param schema_name: Schema Name for which alerts will be fetched.
        :param object_name: Table Name for which alerts will be fetched.
        :param alert_id: Alert Id for which information will be fetched.

        Input Data: Below are the json input format required to update
        alert.

        Below are required data type for each input parameters.
        "alert_name": string,
        "alert_template": string, ( positive integer values. )
        "low_threshold_value": string, ( integer/float values. )
        "medium_threshold_value": string, ( integer/float values. )
        "high_threshold_value": string, (  integer/float values. )
        "history_retention": string, ( Possible values 1-99999 )
        "enabled": string, ( Possible values true and false)
        "frequency_min": string ( Possible values 1-65534 )
        "operator": string ( Valid string are ">" and "<")
        "params": list of dict values.

        Example input data as below.
        {
          "alert_name":"alert_name",
          "alert_template": "180",
          "low_threshold_value": "1",
          "medium_threshold_value": "2",
          "high_threshold_value": "3",
          "history_retention": 32,
          "enabled": true,
          "frequency_min": 11,
          "operator": ">",
          "params":
          {
            "changed": [
              {
                "paramvalue": "7",
                "paramname": "param_1"
              }
            ]
          }
        }

        :return:

        Below is the expected result.

        status: 200 OK
        {
          "success":1,
          "info":"Alert updated successfully.",
          "result":null,
          "errormsg":"",
          "data":null
        }

        """

        data = request.get_json()
        if data is None:
            return make_json_response(
                status=404, success=0,
                errormsg=gettext(
                    "Please specify input data for which you wish to "
                    "update the alert parameters."
                )
            )

        object_exist, msg = is_object_exists(self.conn, 'table', server_id,
                                             database_name, schema_name,
                                             object_name)
        if not object_exist:
            return make_json_response(
                status=404, success=0, errormsg=msg
            )

        # First check alert id exists or not.
        if alert_id is None:
            return make_json_response(
                status=404, success=0,
                errormsg=gettext(
                    "Please specify alert id for which you wish to "
                    "update the alert parameters."
                )
            )

        if 'send_trap' in data and data['send_trap'] is True and \
                'snmp_trap_version' in data and \
                request.blueprint in ['v1_api', 'v2_api'] and \
                not isinstance(data['snmp_trap_version'], bool):
            return make_json_response(
                status=404, success=0,
                errormsg=gettext("Invalid SNMP trap version value")
            )

        status, alerts = utils.get_alerts(
            DashboardLevel.DB_TABLE, server_id, database_name,
            schema_name, object_name, pem_conn=self.conn, alert_id=alert_id
        )
        if not status:
            return internal_server_error(errormsg=alerts)

        if alert_id is not None and len(alerts['rows']) == 0:
            return make_json_response(
                status=404, success=0,
                errormsg=gettext(
                    "The specified alert id is not applicable for "
                    "the specified table"
                )
            )

        # Check for duplicate alert name
        status, alerts = utils.get_alerts(
            DashboardLevel.DB_TABLE, server_id, database_name,
            schema_name, object_name, pem_conn=self.conn
        )
        if not status:
            return internal_server_error(errormsg=alerts)

        if len(alerts['rows']) > 0 and 'alert_name' in data:
            for a_param in alerts['rows']:
                if a_param['alert_name'] == data['alert_name']:
                    return make_json_response(
                        status=404, success=0,
                        errormsg=gettext(
                            "The specified alert name already exists."
                        )
                    )

        data['id'] = alert_id
        data = transform_snmp_version_value(data, request)

        # remove any unwanted params passed which are not applicable for
        # current api version.
        data = self.discard_unwanted_params(data)

        # First validate all input parameters
        status, result = utils.validate_update_params(
            alert_id, DashboardLevel.DB_TABLE, data, self.is_edb, self.conn
        )
        if not status:
            return bad_request(result)

        status, result = utils.update_alert(data, self.conn)
        if not status:
            return internal_server_error(errormsg=result)

        return success_return(message=gettext('Alert updated successfully.'))

    @check_precondition
    def post(self, server_id, database_name, schema_name, object_name):
        """
        This function will create the new alert for specified
        server, database, schema and table.

        :param server_id: Server Id for which alerts will be created.
        :param database_name: Database Name for which alerts will be created.
        :param schema_name: Schema Name for which alerts will be created.
        :param object_name: Table Name for which alerts will be created.

        Input Data: Below are the json input format required to create
        new alert.

        Below are the mandatory parameters required to create the new
        alert and input are always dict of below values.

        "alert_name", "alert_template", "low_threshold_value",
        "medium_threshold_value", "high_threshold_value",
        "frequency_min", "operator", "history_retention", "enabled".
        If alert template requires then "params"

        Below are required data type for each input parameters.
        "alert_name": string,
        "alert_template": string, ( positive integer values. )
        "low_threshold_value": string, ( integer/float values. )
        "medium_threshold_value": string, ( integer/float values. )
        "high_threshold_value": string, (  integer/float values. )
        "history_retention": string, ( Possible values 1-99999 )
        "enabled": string, ( Possible values true and false)
        "frequency_min": string ( Possible values 1-65534 )
        "operator": string ( Valid string are ">" and "<")
        "params": list of dict values.

        Example input data as below.
        {
          "alert_name":"alert_name",
          "alert_template": "180",
          "low_threshold_value": "1",
          "medium_threshold_value": "2",
          "high_threshold_value": "3",
          "history_retention": 32,
          "enabled": true,
          "frequency_min": 11,
          "operator": ">",
          "params": [
            {
              "paramvalue": "7",
              "paramname": "param_1"
            }
          ]
        }

        :return:

        Below is the expected result.

        status: 200 OK
        {
          "success":1,
          "info":"Alert created successfully.",
          "result":null,
          "errormsg":"",
          "data":null
        }

        """

        data = request.get_json()
        if data is None:
            return make_json_response(
                status=404, success=0,
                errormsg=gettext(
                    "Please specify input data for which you wish to "
                    "create the alert."
                )
            )

        object_exist, msg = is_object_exists(self.conn, 'table', server_id,
                                             database_name, schema_name,
                                             object_name)
        if not object_exist:
            return make_json_response(
                status=404, success=0, errormsg=msg
            )

        if 'send_trap' in data and data['send_trap'] is True and \
                'snmp_trap_version' in data and \
                request.blueprint in ['v1_api', 'v2_api'] and \
                not isinstance(data['snmp_trap_version'], bool):
            return make_json_response(
                status=404, success=0,
                errormsg=gettext("Invalid SNMP trap version value")
            )

        # Check for duplicate alert name
        status, alerts = utils.get_alerts(
            DashboardLevel.DB_TABLE, server_id, database_name,
            schema_name, object_name, pem_conn=self.conn
        )
        if not status:
            return internal_server_error(errormsg=alerts)

        if len(alerts['rows']) > 0 and 'alert_name' in data:
            for a_param in alerts['rows']:
                if a_param['alert_name'] == data['alert_name']:
                    return make_json_response(
                        status=404, success=0,
                        errormsg=gettext(
                            "The specified alert name already exists."
                        )
                    )

        # Create the node information to create the new alert.
        node_info = {
            'target_type_id': DashboardLevel.DB_TABLE,
            'server_id': server_id,
            'database_name': database_name,
            'schema_name': schema_name,
            'object_name': object_name
        }
        data = transform_snmp_version_value(data, request)

        # remove any unwanted params passed which are not applicable for
        # current api version.
        data = self.discard_unwanted_params(data)

        # First validate all input parameters
        status, result = utils.validate_insert_params(
            DashboardLevel.DB_TABLE, data, self.is_edb, self.conn
        )
        if not status:
            return bad_request(result)

        status, result = utils.insert_alert(data, node_info, self.conn)
        if not status:
            return internal_server_error(errormsg=result)

        return success_return(message=gettext('Alert created successfully.'))


class IndexConfigApiView(ApiView):
    """
    API to expose the configuration of the alerts at index level.
    """

    endpoint = 'index_alert_config'

    url = '/alert/config/server/<int:server_id>/database/<database_name>/' \
          'schema/<schema_name>/index/<object_name>/'
    pk = 'alert_id'
    conn = None
    template_path = None
    is_edb = 0
    api_versions = ['v1_api', 'v2_api', 'v3_api', 'v4_api']

    def __init__(self, *args, **kwargs):
        super(ApiView, self).__init__(*args, **kwargs)
        self.params = frozenset(upto_v4_params)

    def get(self, server_id, database_name, schema_name,
            object_name, alert_id=None, pem_conn=None):
        """
        This function will return the list of alerts for
        specified server, database, schema and index.

        :param server_id: Server Id
        :param database_name: Database Name
        :param schema_name: Schema Name
        :param object_name: Index Name for which alerts will be fetched.
        :param alert_id: Alert Id for which information will be fetched.
        :param pem_conn: PEM connection object

        Method: GET
        URL: /api/v1/alert/config/index/1/postgres/public/alert_index
        DESCRIPTION: All the alerts will be returned at index level.

        Method: GET
        URL: /api/v1/alert/config/index/1/postgres/public/alert_index/1
        DESCRIPTION: Alerts with id 1 will be returned at index level.

        Input Data:
        Valid alert id for which information to be fetched.

        Input URL:
        /api/v1/alert/config/index/1/postgres/public/alert_index

        :return:

        [
          { "med_send_trap":false,"alert_template":"1", .....},
          { "med_send_trap":false,"alert_template":"2", .....},
          ...
        ]

        Input URL:
        /api/v1/alert/config/index/1/postgres/public/alert_index/1

        :return:
        [
          { "med_send_trap":false,"alert_template":"1", .....}
        ]

        """

        object_exist, msg = is_object_exists(pem_conn, 'index', server_id,
                                             database_name, schema_name,
                                             object_name)
        if not object_exist:
            return make_json_response(
                status=404, success=0, errormsg=msg
            )

        status, res = utils.get_alerts(
            DashboardLevel.DB_INDEX, server_id, database_name,
            schema_name, object_name, pem_conn=pem_conn, alert_id=alert_id
        )
        if not status:
            return internal_server_error(errormsg=res)

        if alert_id is not None and len(res['rows']) == 0:
            return make_json_response(
                status=404, success=0,
                errormsg=gettext(
                    "The specified alert id is not applicable for "
                    "the specified index"
                )
            )

        for alert in res['rows']:
            del alert['agent_id']
            del alert['server_id']
            del alert['database_name']
            del alert['schema_name']
            del alert['package_name']
            del alert['object_name']
            del alert['agent_desc']
            del alert['server_desc']
            del alert['email_group_name']
            del alert['frequency_default']
            del alert['med_email_group_name']
            del alert['default_history_retention']
            del alert['low_email_group_name']
            del alert['default_frequency']
            del alert['high_email_group_name']
            del alert['thresholds']
            del alert['history_retention_default']
            transform_snmp_version_value(alert, request)

            # Remove any unwanted params passed which are not applicable for
            # current api version.
            self.discard_unwanted_params(alert)

        return make_response(res['rows'])

    @check_precondition
    def delete(self, server_id, database_name, schema_name,
               object_name, alert_id=None):
        """
        This function will delete the alert for specified
        server, database, schema and index.

        :param server_id: Server Id
        :param database_name: Database Name
        :param schema_name: Schema Name
        :param object_name: Index Name for which alerts will be deleted.
        :param alert_id: Alert Id for which information will be deleted.

        Input Data:
        Valid alert id to delete the alert.

        e.g.
        /api/v1/alert/config/index/1/postgres/public/alert_index/1

        :return:

        Below is the expected result.

        status: 200 OK
        {
          "success":1,
          "info":"Alert deleted successfully.",
          "result":null,
          "errormsg":"",
          "data":null
        }

        """
        # First check alert id exists or not.
        if alert_id is None:
            return make_json_response(
                status=404, success=0,
                errormsg=gettext("Please specify alert id you wish to delete")
            )

        if server_id is None or server_id == 0:
            return make_json_response(
                status=404, success=0,
                errormsg=gettext("Please specify valid server id.")
            )

        if database_name is None and not database_name:
            return make_json_response(
                status=404, success=0,
                errormsg=gettext("Please specify valid database name.")
            )

        if schema_name is None and not schema_name:
            return make_json_response(
                status=404, success=0,
                errormsg=gettext("Please specify valid schema name.")
            )

        if object_name is None and not object_name:
            return make_json_response(
                status=404, success=0,
                errormsg=gettext("Please specify valid index name.")
            )

        params = {
            'alert_id': alert_id
        }

        sql = render_template(
            "/".join([self.template_path, 'alert_exists.sql']),
            alert_id=alert_id, server_id=server_id,
            database_name=database_name, schema_name=schema_name,
            object_name=object_name
        )

        try:
            # Check the alert exists or not.
            status, al_exists = self.conn.execute_dict(sql, params)

            if not status:
                return internal_server_error(al_exists)

            if int(al_exists['rows'][0]['alert_count']) == 0:
                return make_json_response(
                    status=404, success=0,
                    errormsg=gettext("The specified alert id is not exists.")
                )
        except Exception as e:
            return internal_server_error(e)

        sql = render_template(
            "/".join([self.template_path, 'delete.sql'])
        )

        try:
            alert_ids = []
            alert_ids.append(alert_id)

            status, result = self.conn.execute_void(
                sql, {'alert_ids': alert_ids}
            )

            if not status:
                return internal_server_error(result)

        except Exception as e:
            return internal_server_error(e)

        return success_return(message=gettext('Alert deleted successfully.'))

    @check_precondition
    def put(self, server_id, database_name, schema_name,
            object_name, alert_id=None):
        """
        This function will update the alert for specified
        server, database, schema and index.

        :param server_id: Server Id for which alerts will be fetched.
        :param database_name: Database Name for which alerts will be fetched.
        :param schema_name: Schema Name for which alerts will be fetched.
        :param object_name: Table Name for which alerts will be fetched.
        :param alert_id: Alert Id for which information will be fetched.

        Input Data: Below are the json input format required to update
        alert.

        Below are required data type for each input parameters.
        "alert_name": string,
        "alert_template": string, ( positive integer values. )
        "low_threshold_value": string, ( integer/float values. )
        "medium_threshold_value": string, ( integer/float values. )
        "high_threshold_value": string, (  integer/float values. )
        "history_retention": string, ( Possible values 1-99999 )
        "enabled": string, ( Possible values true and false)
        "frequency_min": string ( Possible values 1-65534 )
        "operator": string ( Valid string are ">" and "<")
        "params": list of dict values.

        Example input data as below.
        {
          "alert_name":"alert_name",
          "alert_template": "180",
          "low_threshold_value": "1",
          "medium_threshold_value": "2",
          "high_threshold_value": "3",
          "history_retention": 32,
          "enabled": true,
          "frequency_min": 11,
          "operator": ">",
          "params":
          {
            "changed": [
              {
                "paramvalue": "7",
                "paramname": "param_1"
              }
            ]
          }
        }

        :return:

        Below is the expected result.

        status: 200 OK
        {
          "success":1,
          "info":"Alert updated successfully.",
          "result":null,
          "errormsg":"",
          "data":null
        }

        """

        data = request.get_json()
        if data is None:
            return make_json_response(
                status=404, success=0,
                errormsg=gettext(
                    "Please specify input data for which you wish to "
                    "update the alert parameters."
                )
            )

        object_exist, msg = is_object_exists(self.conn, 'index', server_id,
                                             database_name, schema_name,
                                             object_name)
        if not object_exist:
            return make_json_response(
                status=404, success=0, errormsg=msg
            )

        # First check alert id exists or not.
        if alert_id is None:
            return make_json_response(
                status=404, success=0,
                errormsg=gettext(
                    "Please specify alert id for which you wish to "
                    "update the alert parameters."
                )
            )

        if 'send_trap' in data and data['send_trap'] is True and \
                'snmp_trap_version' in data and \
                request.blueprint in ['v1_api', 'v2_api'] and \
                not isinstance(data['snmp_trap_version'], bool):
            return make_json_response(
                status=404, success=0,
                errormsg=gettext("Invalid SNMP trap version value")
            )

        status, alerts = utils.get_alerts(
            DashboardLevel.DB_INDEX, server_id, database_name,
            schema_name, object_name, pem_conn=self.conn, alert_id=alert_id
        )
        if not status:
            return internal_server_error(errormsg=alerts)

        if alert_id is not None and len(alerts['rows']) == 0:
            return make_json_response(
                status=404, success=0,
                errormsg=gettext(
                    "The specified alert id is not applicable for "
                    "the specified index"
                )
            )

        # Check for duplicate alert name
        status, alerts = utils.get_alerts(
            DashboardLevel.DB_INDEX, server_id, database_name,
            schema_name, object_name, pem_conn=self.conn
        )
        if not status:
            return internal_server_error(errormsg=alerts)

        if len(alerts['rows']) > 0 and 'alert_name' in data:
            for a_param in alerts['rows']:
                if a_param['alert_name'] == data['alert_name']:
                    return make_json_response(
                        status=404, success=0,
                        errormsg=gettext(
                            "The specified alert name already exists."
                        )
                    )

        data['id'] = alert_id
        data = transform_snmp_version_value(data, request)

        # remove any unwanted params passed which are not applicable for
        # current api version.
        data = self.discard_unwanted_params(data)

        # First validate all input parameters
        status, result = utils.validate_update_params(
            alert_id, DashboardLevel.DB_INDEX, data, self.is_edb, self.conn
        )
        if not status:
            return bad_request(result)

        status, result = utils.update_alert(data, self.conn)
        if not status:
            return internal_server_error(errormsg=result)

        return success_return(message=gettext('Alert updated successfully.'))

    @check_precondition
    def post(self, server_id, database_name, schema_name, object_name):
        """
        This function will create the alert for specified
        server, database, schema and index.

        :param server_id: Server Id for which alerts will be created.
        :param database_name: Database Name for which alerts will be created.
        :param schema_name: Schema Name for which alerts will be created.
        :param object_name: Table Name for which alerts will be created.

        Input Data: Below are the json input format required to create
        new alert.

        Below are the mandatory parameters required to create the new
        alert and input are always dict of below values.

        "alert_name", "alert_template", "low_threshold_value",
        "medium_threshold_value", "high_threshold_value",
        "frequency_min", "operator", "history_retention", "enabled".
        If alert template requires then "params"

        Below are required data type for each input parameters.
        "alert_name": string,
        "alert_template": string, ( positive integer values. )
        "low_threshold_value": string, ( integer/float values. )
        "medium_threshold_value": string, ( integer/float values. )
        "high_threshold_value": string, (  integer/float values. )
        "history_retention": string, ( Possible values 1-99999 )
        "enabled": string, ( Possible values true and false)
        "frequency_min": string ( Possible values 1-65534 )
        "operator": string ( Valid string are ">" and "<")
        "params": list of dict values.

        Example input data as below.
        {
          "alert_name":"alert_name",
          "alert_template": "180",
          "low_threshold_value": "1",
          "medium_threshold_value": "2",
          "high_threshold_value": "3",
          "history_retention": 32,
          "enabled": true,
          "frequency_min": 11,
          "operator": ">",
          "params": [
            {
              "paramvalue": "7",
              "paramname": "param_1"
            }
          ]
        }

        :return:

        Below is the expected result.

        status: 200 OK
        {
          "success":1,
          "info":"Alert created successfully.",
          "result":null,
          "errormsg":"",
          "data":null
        }

        """

        data = request.get_json()
        if data is None:
            return make_json_response(
                status=404, success=0,
                errormsg=gettext(
                    "Please specify input data for which you wish to "
                    "create the alert."
                )
            )

        object_exist, msg = is_object_exists(self.conn, 'index', server_id,
                                             database_name, schema_name,
                                             object_name)
        if not object_exist:
            return make_json_response(
                status=404, success=0, errormsg=msg
            )

        if 'send_trap' in data and data['send_trap'] is True and \
                'snmp_trap_version' in data and \
                request.blueprint in ['v1_api', 'v2_api'] and \
                not isinstance(data['snmp_trap_version'], bool):
            return make_json_response(
                status=404, success=0,
                errormsg=gettext("Invalid SNMP trap version value")
            )

        # Check for duplicate alert name
        status, alerts = utils.get_alerts(
            DashboardLevel.DB_INDEX, server_id, database_name,
            schema_name, object_name, pem_conn=self.conn
        )
        if not status:
            return internal_server_error(errormsg=alerts)

        if len(alerts['rows']) > 0 and 'alert_name' in data:
            for a_param in alerts['rows']:
                if a_param['alert_name'] == data['alert_name']:
                    return make_json_response(
                        status=404, success=0,
                        errormsg=gettext(
                            "The specified alert name already exists."
                        )
                    )

        # Create the node information to create the new alert.
        node_info = {
            'target_type_id': DashboardLevel.DB_INDEX,
            'server_id': server_id,
            'database_name': database_name,
            'schema_name': schema_name,
            'object_name': object_name
        }
        data = transform_snmp_version_value(data, request)

        # remove any unwanted params passed which are not applicable for
        # current api version.
        data = self.discard_unwanted_params(data)

        # First validate all input parameters
        status, result = utils.validate_insert_params(
            DashboardLevel.DB_INDEX, data, self.is_edb, self.conn
        )
        if not status:
            return bad_request(result)

        status, result = utils.insert_alert(data, node_info, self.conn)
        if not status:
            return internal_server_error(errormsg=result)

        return success_return(message=gettext('Alert created successfully.'))


class SequenceConfigApiView(ApiView):
    """
    API to expose the configuration of the alerts at sequence level.
    """

    endpoint = 'sequence_alert_config'

    url = '/alert/config/server/<int:server_id>/database/<database_name>/' \
          'schema/<schema_name>/sequence/<object_name>/'
    pk = 'alert_id'
    conn = None
    template_path = None
    is_edb = 0
    api_versions = ['v1_api', 'v2_api', 'v3_api', 'v4_api']

    def __init__(self, *args, **kwargs):
        super(ApiView, self).__init__(*args, **kwargs)
        self.params = frozenset(upto_v4_params)

    def get(self, server_id, database_name, schema_name,
            object_name, alert_id=None, pem_conn=None):
        """
        This function will return the list of alerts for
        specified server, database, schema and sequence.

        :param server_id: Server Id
        :param database_name: Database Name
        :param schema_name: Schema Name
        :param object_name: Sequence Name for which alerts will be fetched.
        :param alert_id: Alert Id for which information will be fetched.
        :param pem_conn: PEM connection object.

        Method: GET
        URL: /api/v1/alert/config/sequence/1/postgres/public/alert_seq
        DESCRIPTION: All the alerts will be returned at sequence level.

        Method: GET
        URL: /api/v1/alert/config/sequence/1/postgres/public/alert_seq/1
        DESCRIPTION: Alerts with id 1 will be returned at sequence level.

        Input Data:
        Valid alert id for which information to be fetched.

        Input URL:
        /api/v1/alert/config/sequence/1/postgres/public/alert_seq

        :return:

        [
          { "med_send_trap":false,"alert_template":"1", .....},
          { "med_send_trap":false,"alert_template":"2", .....},
          ...
        ]

        Input URL:
        /api/v1/alert/config/sequence/1/postgres/public/alert_seq/1

        :return:
        [
          { "med_send_trap":false,"alert_template":"1", .....}
        ]

        """

        object_exist, msg = is_object_exists(pem_conn, 'sequence', server_id,
                                             database_name, schema_name,
                                             object_name)
        if not object_exist:
            return make_json_response(
                status=404, success=0, errormsg=msg
            )

        status, res = utils.get_alerts(
            DashboardLevel.DB_SEQUENCE, server_id, database_name,
            schema_name, object_name, pem_conn=pem_conn, alert_id=alert_id
        )
        if not status:
            return internal_server_error(errormsg=res)

        if alert_id is not None and len(res['rows']) == 0:
            return make_json_response(
                status=404, success=0,
                errormsg=gettext(
                    "The specified alert id is not applicable for "
                    "the specified sequence"
                )
            )

        for alert in res['rows']:
            del alert['agent_id']
            del alert['server_id']
            del alert['database_name']
            del alert['schema_name']
            del alert['package_name']
            del alert['object_name']
            del alert['agent_desc']
            del alert['server_desc']
            del alert['email_group_name']
            del alert['frequency_default']
            del alert['med_email_group_name']
            del alert['default_history_retention']
            del alert['low_email_group_name']
            del alert['default_frequency']
            del alert['high_email_group_name']
            del alert['thresholds']
            del alert['history_retention_default']
            transform_snmp_version_value(alert, request)

            # Remove any unwanted params passed which are not applicable for
            # current api version.
            self.discard_unwanted_params(alert)

        return make_response(res['rows'])

    @check_precondition
    def delete(self, server_id, database_name, schema_name,
               object_name, alert_id=None):
        """
        This function will delete the alert for specified
        server, database, schema and sequence.

        :param server_id: Server Id
        :param database_name: Database Name
        :param schema_name: Schema Name
        :param object_name: Sequence Name for which alerts will be deleted.
        :param alert_id: Alert Id for which information will be deleted.

        Input Data:
        Valid alert id to delete the alert.

        e.g.
        /api/v1/alert/config/sequence/1/postgres/public/alert_seq/1

        :return:

        Below is the expected result.

        status: 200 OK
        {
          "success":1,
          "info":"Alert deleted successfully.",
          "result":null,
          "errormsg":"",
          "data":null
        }

        """
        # First check alert id exists or not.
        if alert_id is None:
            return make_json_response(
                status=404, success=0,
                errormsg=gettext("Please specify alert id you wish to delete")
            )

        if server_id is None or server_id == 0:
            return make_json_response(
                status=404, success=0,
                errormsg=gettext("Please specify valid server id.")
            )

        if database_name is None and not database_name:
            return make_json_response(
                status=404, success=0,
                errormsg=gettext("Please specify valid database name.")
            )

        if schema_name is None and not schema_name:
            return make_json_response(
                status=404, success=0,
                errormsg=gettext("Please specify valid schema name.")
            )

        if object_name is None and not object_name:
            return make_json_response(
                status=404, success=0,
                errormsg=gettext("Please specify valid sequence name.")
            )

        params = {
            'alert_id': alert_id
        }

        sql = render_template(
            "/".join([self.template_path, 'alert_exists.sql']),
            alert_id=alert_id, server_id=server_id,
            database_name=database_name, schema_name=schema_name,
            object_name=object_name
        )

        try:
            # Check the alert exists or not.
            status, al_exists = self.conn.execute_dict(sql, params)

            if not status:
                return internal_server_error(al_exists)

            if int(al_exists['rows'][0]['alert_count']) == 0:
                return make_json_response(
                    status=404, success=0,
                    errormsg=gettext("The specified alert id is not exists.")
                )
        except Exception as e:
            return internal_server_error(e)

        sql = render_template(
            "/".join([self.template_path, 'delete.sql'])
        )

        try:
            alert_ids = []
            alert_ids.append(alert_id)

            status, result = self.conn.execute_void(
                sql, {'alert_ids': alert_ids}
            )

            if not status:
                return internal_server_error(result)

        except Exception as e:
            return internal_server_error(e)

        return success_return(message=gettext('Alert deleted successfully.'))

    @check_precondition
    def put(self, server_id, database_name, schema_name,
            object_name, alert_id=None):
        """
        This function will update the alert for specified
        server, database, schema and sequence.

        :param server_id: Server Id for which alerts will be fetched.
        :param database_name: Database Name for which alerts will be fetched.
        :param schema_name: Schema Name for which alerts will be fetched.
        :param object_name: Table Name for which alerts will be fetched.
        :param alert_id: Alert Id for which information will be fetched.

        Input Data: Below are the json input format required to update
        alert.

        Below are required data type for each input parameters.
        "alert_name": string,
        "alert_template": string, ( positive integer values. )
        "low_threshold_value": string, ( integer/float values. )
        "medium_threshold_value": string, ( integer/float values. )
        "high_threshold_value": string, (  integer/float values. )
        "history_retention": string, ( Possible values 1-99999 )
        "enabled": string, ( Possible values true and false)
        "frequency_min": string ( Possible values 1-65534 )
        "operator": string ( Valid string are ">" and "<")
        "params": list of dict values.

        Example input data as below.
        {
          "alert_name":"alert_name",
          "alert_template": "180",
          "low_threshold_value": "1",
          "medium_threshold_value": "2",
          "high_threshold_value": "3",
          "history_retention": 32,
          "enabled": true,
          "frequency_min": 11,
          "operator": ">",
          "params":
          {
            "changed": [
              {
                "paramvalue": "7",
                "paramname": "param_1"
              }
            ]
          }
        }

        :return:

        Below is the expected result.

        status: 200 OK
        {
          "success":1,
          "info":"Alert updated successfully.",
          "result":null,
          "errormsg":"",
          "data":null
        }

        """

        data = request.get_json()
        if data is None:
            return make_json_response(
                status=404, success=0,
                errormsg=gettext(
                    "Please specify input data for which you wish to "
                    "update the alert parameters."
                )
            )

        object_exist, msg = is_object_exists(self.conn, 'sequence', server_id,
                                             database_name, schema_name,
                                             object_name)
        if not object_exist:
            return make_json_response(
                status=404, success=0, errormsg=msg
            )

        # First check alert id exists or not.
        if alert_id is None:
            return make_json_response(
                status=404, success=0,
                errormsg=gettext(
                    "Please specify alert id for which you wish to "
                    "update the alert parameters."
                )
            )

        if 'send_trap' in data and data['send_trap'] is True and \
                'snmp_trap_version' in data and \
                request.blueprint in ['v1_api', 'v2_api'] and \
                not isinstance(data['snmp_trap_version'], bool):
            return make_json_response(
                status=404, success=0,
                errormsg=gettext("Invalid SNMP trap version value")
            )

        status, alerts = utils.get_alerts(
            DashboardLevel.DB_SEQUENCE, server_id, database_name,
            schema_name, object_name, pem_conn=self.conn, alert_id=alert_id
        )
        if not status:
            return internal_server_error(errormsg=alerts)

        if alert_id is not None and len(alerts['rows']) == 0:
            return make_json_response(
                status=404, success=0,
                errormsg=gettext(
                    "The specified alert id is not applicable for "
                    "the specified sequence"
                )
            )

        # Check for duplicate alert name
        status, alerts = utils.get_alerts(
            DashboardLevel.DB_SEQUENCE, server_id, database_name,
            schema_name, object_name, pem_conn=self.conn
        )
        if not status:
            return internal_server_error(errormsg=alerts)

        if len(alerts['rows']) > 0 and 'alert_name' in data:
            for a_param in alerts['rows']:
                if a_param['alert_name'] == data['alert_name']:
                    return make_json_response(
                        status=404, success=0,
                        errormsg=gettext(
                            "The specified alert name already exists."
                        )
                    )

        data['id'] = alert_id
        data = transform_snmp_version_value(data, request)

        # remove any unwanted params passed which are not applicable for
        # current api version.
        data = self.discard_unwanted_params(data)

        # First validate all input parameters
        status, result = \
            utils.validate_update_params(alert_id, DashboardLevel.DB_SEQUENCE,
                                         data, self.is_edb, self.conn)
        if not status:
            return bad_request(result)

        status, result = utils.update_alert(data, self.conn)
        if not status:
            return internal_server_error(errormsg=result)

        return success_return(message=gettext('Alert updated successfully.'))

    @check_precondition
    def post(self, server_id, database_name, schema_name,
             object_name):
        """
        This function will create the new alert for specified
        server, database, schema and sequence.

        :param server_id: Server Id for which alerts will be created.
        :param database_name: Database Name for which alerts will be created.
        :param schema_name: Schema Name for which alerts will be created.
        :param object_name: Table Name for which alerts will be created.

        Input Data: Below are the json input format required to create
        new alert.

        Below are the mandatory parameters required to create the new
        alert and input are always dict of below values.

        "alert_name", "alert_template", "low_threshold_value",
        "medium_threshold_value", "high_threshold_value",
        "frequency_min", "operator", "history_retention", "enabled".
        If alert template requires then "params"

        Below are required data type for each input parameters.
        "alert_name": string,
        "alert_template": string, ( positive integer values. )
        "low_threshold_value": string, ( integer/float values. )
        "medium_threshold_value": string, ( integer/float values. )
        "high_threshold_value": string, (  integer/float values. )
        "history_retention": string, ( Possible values 1-99999 )
        "enabled": string, ( Possible values true and false)
        "frequency_min": string ( Possible values 1-65534 )
        "operator": string ( Valid string are ">" and "<")
        "params": list of dict values.

        Example input data as below.
        {
          "alert_name":"alert_name",
          "alert_template": "180",
          "low_threshold_value": "1",
          "medium_threshold_value": "2",
          "high_threshold_value": "3",
          "history_retention": 32,
          "enabled": true,
          "frequency_min": 11,
          "operator": ">",
          "params": [
            {
              "paramvalue": "7",
              "paramname": "param_1"
            }
          ]
        }

        :return:

        Below is the expected result.

        status: 200 OK
        {
          "success":1,
          "info":"Alert created successfully.",
          "result":null,
          "errormsg":"",
          "data":null
        }

        """

        data = request.get_json()
        if data is None:
            return make_json_response(
                status=404, success=0,
                errormsg=gettext(
                    "Please specify input data for which you wish to "
                    "create the alert."
                )
            )

        object_exist, msg = is_object_exists(self.conn, 'sequence', server_id,
                                             database_name, schema_name,
                                             object_name)
        if not object_exist:
            return make_json_response(
                status=404, success=0, errormsg=msg
            )

        if 'send_trap' in data and data['send_trap'] is True and \
                'snmp_trap_version' in data and \
                request.blueprint in ['v1_api', 'v2_api'] and \
                not isinstance(data['snmp_trap_version'], bool):
            return make_json_response(
                status=404, success=0,
                errormsg=gettext("Invalid SNMP trap version value")
            )

        # Check for duplicate alert name
        status, alerts = utils.get_alerts(
            DashboardLevel.DB_SEQUENCE, server_id, database_name,
            schema_name, object_name, pem_conn=self.conn
        )
        if not status:
            return internal_server_error(errormsg=alerts)

        if len(alerts['rows']) > 0 and 'alert_name' in data:
            for a_param in alerts['rows']:
                if a_param['alert_name'] == data['alert_name']:
                    return make_json_response(
                        status=404, success=0,
                        errormsg=gettext(
                            "The specified alert name already exists."
                        )
                    )

        # Create the node information to create the new alert.
        node_info = {
            'target_type_id': DashboardLevel.DB_SEQUENCE,
            'server_id': server_id,
            'database_name': database_name,
            'schema_name': schema_name,
            'object_name': object_name
        }

        data = transform_snmp_version_value(data, request)

        # remove any unwanted params passed which are not applicable for
        # current api version.
        data = self.discard_unwanted_params(data)

        # First validate all input parameters
        status, result = \
            utils.validate_insert_params(DashboardLevel.DB_SEQUENCE, data,
                                         self.is_edb, self.conn)
        if not status:
            return bad_request(result)

        status, result = utils.insert_alert(data, node_info, self.conn)
        if not status:
            return internal_server_error(errormsg=result)

        return success_return(message=gettext('Alert created successfully.'))


class FunctionConfigApiView(ApiView):
    """
    API to expose the configuration of the alerts at function level.
    """

    endpoint = 'function_alert_config'

    url = '/alert/config/server/<int:server_id>/database/<database_name>/' \
          'schema/<schema_name>/function/<function_name>/' \
          'args/<function_arguments>/'
    pk = 'alert_id'
    conn = None
    template_path = None
    is_edb = 0
    api_versions = ['v1_api', 'v2_api', 'v3_api', 'v4_api']

    def __init__(self, *args, **kwargs):
        super(ApiView, self).__init__(*args, **kwargs)
        self.params = frozenset(upto_v4_params)

    def get(
        self, server_id, database_name, schema_name,
        function_name, function_arguments, alert_id=None, pem_conn=None
    ):
        """
        This function will return the list of alerts for
        specified server, database, schema and function.

        :param server_id: Server Id
        :param database_name: Database Name
        :param schema_name: Schema Name
        :param object_name: Function Name for which alerts will be fetched.
        :param alert_id: Alert Id for which information will be fetched.
        :param pem_conn: PEM connection object.

        Method: GET
        URL: /api/v1/alert/config/function/1/postgres/public/alert_func
        DESCRIPTION: All the alerts will be returned at function level.

        Method: GET
        URL: /api/v1/alert/config/function/1/postgres/public/alert_func/1
        DESCRIPTION: Alerts with id 1 will be returned at function level.

        Input Data:
        Valid alert id for which information to be fetched.

        Input URL:
        /api/v1/alert/config/function/1/postgres/public/alert_func/

        :return:

        [
          { "med_send_trap":false,"alert_template":"1", .....},
          { "med_send_trap":false,"alert_template":"2", .....},
          ...
        ]

        Input URL:
        /api/v1/alert/config/function/1/postgres/public/alert_func/1

        :return:
        [
          { "med_send_trap":false,"alert_template":"1", .....}
        ]

        :return:
        """

        # handling if no function arguments provided
        if function_arguments == ' ':
            function_arguments = ''

        # using re for addding space after ',' for comma separated args
        function_arguments = re.sub(r'(?<=[,])(?=[^\s])',
                                    r' ', function_arguments)

        object_exist, msg = is_object_exists(
            pem_conn, 'function', server_id,
            database_name, schema_name,
            function_name, arguments=function_arguments
        )
        if not object_exist:
            return make_json_response(
                status=404, success=0, errormsg=msg
            )

        # function name with args
        function_name = "{}({})".format(function_name, function_arguments)

        status, res = utils.get_alerts(
            DashboardLevel.DB_FUNCTION, server_id, database_name,
            schema_name, function_name, pem_conn=pem_conn, alert_id=alert_id
        )
        if not status:
            return internal_server_error(errormsg=res)

        if alert_id is not None and len(res['rows']) == 0:
            return make_json_response(
                status=404, success=0,
                errormsg=gettext(
                    "The specified alert id is not applicable for "
                    "the specified function"
                )
            )

        for alert in res['rows']:
            del alert['agent_id']
            del alert['server_id']
            del alert['database_name']
            del alert['schema_name']
            del alert['package_name']
            del alert['object_name']
            del alert['agent_desc']
            del alert['server_desc']
            del alert['email_group_name']
            del alert['frequency_default']
            del alert['med_email_group_name']
            del alert['default_history_retention']
            del alert['low_email_group_name']
            del alert['default_frequency']
            del alert['high_email_group_name']
            del alert['thresholds']
            del alert['history_retention_default']
            transform_snmp_version_value(alert, request)

            # Remove any unwanted params passed which are not applicable for
            # current api version.
            self.discard_unwanted_params(alert)

        return make_response(res['rows'])

    @check_precondition
    def delete(self, server_id, database_name, schema_name,
               function_name, function_arguments, alert_id=None):
        """
        This function will delete the alert for specified
        server, database, schema and function.

        :param server_id: Server Id
        :param database_name: Database Name
        :param schema_name: Schema Name
        :param object_name: Function Name for which alerts will be deleted.
        :param alert_id: Alert Id for which information will be deleted.

        Input Data:
        Valid alert id to delete the alert.

        e.g.
        /api/v1/alert/config/function/1/postgres/public/alert_func/1

        :return:

        Below is the expected result.

        status: 200 OK
        {
          "success":1,
          "info":"Alert deleted successfully.",
          "result":null,
          "errormsg":"",
          "data":null
        }

        """
        # First check alert id exists or not.
        if alert_id is None:
            return make_json_response(
                status=404, success=0,
                errormsg=gettext("Please specify alert id you wish to delete")
            )

        if server_id is None or server_id == 0:
            return make_json_response(
                status=404, success=0,
                errormsg=gettext("Please specify valid server id.")
            )

        if database_name is None and not database_name:
            return make_json_response(
                status=404, success=0,
                errormsg=gettext("Please specify valid database name.")
            )

        if schema_name is None and not schema_name:
            return make_json_response(
                status=404, success=0,
                errormsg=gettext("Please specify valid schema name.")
            )

        if function_name is None and not function_name:
            return make_json_response(
                status=404, success=0,
                errormsg=gettext("Please specify valid function name.")
            )

        params = {
            'alert_id': alert_id
        }
        # handling if no function arguments provided
        if function_arguments == ' ':
            function_arguments = ''

        # using re for addding space after ',' for comma separated args
        function_arguments = re.sub(
            r'(?<=[,])(?=[^\s])', r' ', function_arguments)
        # function name with args
        function_name = "{}({})".format(function_name, function_arguments)

        sql = render_template(
            "/".join([self.template_path, 'alert_exists.sql']),
            alert_id=alert_id, server_id=server_id,
            database_name=database_name, schema_name=schema_name,
            object_name=function_name
        )

        try:
            # Check the alert exists or not.
            status, al_exists = self.conn.execute_dict(sql, params)

            if not status:
                return internal_server_error(al_exists)

            if int(al_exists['rows'][0]['alert_count']) == 0:
                return make_json_response(
                    status=404, success=0,
                    errormsg=gettext("The specified alert id is not exists.")
                )
        except Exception as e:
            return internal_server_error(e)

        sql = render_template(
            "/".join([self.template_path, 'delete.sql'])
        )

        try:
            alert_ids = []
            alert_ids.append(alert_id)

            status, result = self.conn.execute_void(
                sql, {'alert_ids': alert_ids}
            )

            if not status:
                return internal_server_error(result)

        except Exception as e:
            return internal_server_error(e)

        return success_return(message=gettext('Alert deleted successfully.'))

    @check_precondition
    def put(self, server_id, database_name, schema_name,
            function_name, function_arguments, alert_id=None):
        """
        This function will update the alert for specified
        server, database, schema and function.

        :param server_id: Server Id for which alerts will be fetched.
        :param database_name: Database Name for which alerts will be fetched.
        :param schema_name: Schema Name for which alerts will be fetched.
        :param object_name: Table Name for which alerts will be fetched.
        :param alert_id: Alert Id for which information will be fetched.

        Input Data: Below are the json input format required to update
        alert.

        Below are required data type for each input parameters.
        "alert_name": string,
        "alert_template": string, ( positive integer values. )
        "low_threshold_value": string, ( integer/float values. )
        "medium_threshold_value": string, ( integer/float values. )
        "high_threshold_value": string, (  integer/float values. )
        "history_retention": string, ( Possible values 1-99999 )
        "enabled": string, ( Possible values true and false)
        "frequency_min": string ( Possible values 1-65534 )
        "operator": string ( Valid string are ">" and "<")
        "params": list of dict values.

        Example input data as below.
        {
          "alert_name":"alert_name",
          "alert_template": "180",
          "low_threshold_value": "1",
          "medium_threshold_value": "2",
          "high_threshold_value": "3",
          "history_retention": 32,
          "enabled": true,
          "frequency_min": 11,
          "operator": ">",
          "params":
          {
            "changed": [
              {
                "paramvalue": "7",
                "paramname": "param_1"
              }
            ]
          }
        }

        :return:

        Below is the expected result.

        status: 200 OK
        {
          "success":1,
          "info":"Alert updated successfully.",
          "result":null,
          "errormsg":"",
          "data":null
        }

        """

        data = request.get_json()
        if data is None:
            return make_json_response(
                status=404, success=0,
                errormsg=gettext(
                    "Please specify input data for which you wish to "
                    "update the alert parameters."
                )
            )
        # handling if no function arguments provided
        if function_arguments == ' ':
            function_arguments = ''

        # using re for addding space after ',' for comma separated args
        function_arguments = re.sub(
            r'(?<=[,])(?=[^\s])', r' ', function_arguments)

        object_exist, msg = is_object_exists(self.conn, 'function', server_id,
                                             database_name, schema_name,
                                             function_name,
                                             function_name=function_arguments)
        if not object_exist:
            return make_json_response(
                status=404, success=0, errormsg=msg
            )

        # First check alert id exists or not.
        if alert_id is None:
            return make_json_response(
                status=404, success=0,
                errormsg=gettext(
                    "Please specify alert id for which you wish to "
                    "update the alert parameters."
                )
            )

        if 'send_trap' in data and data[
                'send_trap'] is True and 'snmp_trap_version' in data and \
                request.blueprint in ['v1_api', 'v2_api'] and \
                not isinstance(data['snmp_trap_version'], bool):
            return make_json_response(
                status=404, success=0,
                errormsg=gettext("Invalid SNMP trap version value")
            )

        # function name with args
        function_name = "{}({})".format(function_name, function_arguments)

        status, alerts = utils.get_alerts(
            DashboardLevel.DB_FUNCTION, server_id, database_name,
            schema_name, function_name, pem_conn=self.conn, alert_id=alert_id
        )
        if not status:
            return internal_server_error(errormsg=alerts)

        if alert_id is not None and len(alerts['rows']) == 0:
            return make_json_response(
                status=404, success=0,
                errormsg=gettext(
                    "The specified alert id is not applicable for "
                    "the specified function"
                )
            )

        # Check for duplicate alert name
        status, alerts = utils.get_alerts(
            DashboardLevel.DB_FUNCTION, server_id, database_name,
            schema_name, function_name, pem_conn=self.conn
        )
        if not status:
            return internal_server_error(errormsg=alerts)

        if len(alerts['rows']) > 0 and 'alert_name' in data:
            for a_param in alerts['rows']:
                if a_param['alert_name'] == data['alert_name']:
                    return make_json_response(
                        status=404, success=0,
                        errormsg=gettext(
                            "The specified alert name already exists."
                        )
                    )

        data['id'] = alert_id
        data = transform_snmp_version_value(data, request)

        # remove any unwanted params passed which are not applicable for
        # current api version.
        data = self.discard_unwanted_params(data)

        # First validate all input parameters
        status, result = \
            utils.validate_update_params(alert_id, DashboardLevel.DB_FUNCTION,
                                         data, self.is_edb, self.conn)
        if not status:
            return bad_request(result)

        status, result = utils.update_alert(data, self.conn)
        if not status:
            return internal_server_error(errormsg=result)

        return success_return(message=gettext('Alert updated successfully.'))

    @check_precondition
    def post(self, server_id, database_name, schema_name,
             function_name, function_arguments):
        """
        This function will create new alert for specified
        server, database, schema and function.

        :param server_id: Server Id for which alerts will be created.
        :param database_name: Database Name for which alerts will be created.
        :param schema_name: Schema Name for which alerts will be created.
        :param object_name: Table Name for which alerts will be created.

        Input Data: Below are the json input format required to create
        new alert.

        Below are the mandatory parameters required to create the new
        alert and input are always dict of below values.

        "alert_name", "alert_template", "low_threshold_value",
        "medium_threshold_value", "high_threshold_value",
        "frequency_min", "operator", "history_retention", "enabled".
        If alert template requires then "params"

        Below are required data type for each input parameters.
        "alert_name": string,
        "alert_template": string, ( positive integer values. )
        "low_threshold_value": string, ( integer/float values. )
        "medium_threshold_value": string, ( integer/float values. )
        "high_threshold_value": string, (  integer/float values. )
        "history_retention": string, ( Possible values 1-99999 )
        "enabled": string, ( Possible values true and false)
        "frequency_min": string ( Possible values 1-65534 )
        "operator": string ( Valid string are ">" and "<")
        "params": list of dict values.

        Example input data as below.
        {
          "alert_name":"alert_name",
          "alert_template": "180",
          "low_threshold_value": "1",
          "medium_threshold_value": "2",
          "high_threshold_value": "3",
          "history_retention": 32,
          "enabled": true,
          "frequency_min": 11,
          "operator": ">",
          "params": [
            {
              "paramvalue": "7",
              "paramname": "param_1"
            }
          ]
        }

        :return:

        Below is the expected result.

        status: 200 OK
        {
          "success":1,
          "info":"Alert created successfully.",
          "result":null,
          "errormsg":"",
          "data":null
        }

        """

        data = request.get_json()
        if data is None:
            return make_json_response(
                status=404, success=0,
                errormsg=gettext(
                    "Please specify input data for which you wish to "
                    "create the alert."
                )
            )

        # handling if no function arguments provided
        if function_arguments == ' ':
            function_arguments = ''

        # using re for addding space after ',' for comma separated args
        function_arguments = re.sub(
            r'(?<=[,])(?=[^\s])', r' ', function_arguments)

        object_exist, msg = is_object_exists(self.conn, 'function', server_id,
                                             database_name, schema_name,
                                             function_name,
                                             arguments=function_arguments)

        if not object_exist:
            return make_json_response(
                status=404, success=0, errormsg=msg
            )

        if 'send_trap' in data and data[
                'send_trap'] is True and 'snmp_trap_version' in data and \
                request.blueprint in ['v1_api', 'v2_api'] and \
                not isinstance(data['snmp_trap_version'], bool):
            return make_json_response(
                status=404, success=0,
                errormsg=gettext("Invalid SNMP trap version value")
            )

        # Check for duplicate alert name
        status, alerts = utils.get_alerts(
            DashboardLevel.DB_FUNCTION, server_id, database_name,
            schema_name, function_name, pem_conn=self.conn
        )
        if not status:
            return internal_server_error(errormsg=alerts)

        if len(alerts['rows']) > 0 and 'alert_name' in data:
            for a_param in alerts['rows']:
                if a_param['alert_name'] == data['alert_name']:
                    return make_json_response(
                        status=404, success=0,
                        errormsg=gettext(
                            "The specified alert name already exists."
                        )
                    )

        # function name with args
        function_name = "{}({})".format(function_name, function_arguments)

        # Create the node information to create the new alert.
        node_info = {
            'target_type_id': DashboardLevel.DB_FUNCTION,
            'server_id': server_id,
            'database_name': database_name,
            'schema_name': schema_name,
            'object_name': function_name
        }
        data = transform_snmp_version_value(data, request)

        # remove any unwanted params passed which are not applicable for
        # current api version.
        data = self.discard_unwanted_params(data)

        # First validate all input parameters
        status, result = \
            utils.validate_insert_params(DashboardLevel.DB_FUNCTION, data,
                                         self.is_edb, self.conn)
        if not status:
            return bad_request(result)

        status, result = utils.insert_alert(data, node_info, self.conn)
        if not status:
            return internal_server_error(errormsg=result)

        return success_return(message=gettext('Alert created successfully.'))


class GlobalConfigApiV5View(GlobalConfigApiView):
    """
    This class provide APIs to configure the alerts at global level.
    """

    endpoint = 'global_alert_config_V5'

    # Api version from v5 till latest
    # ['v5_api', 'v6_api', 'v7_api', 'v8_api'..]
    api_versions = api_versions_v5

    def __init__(self, *args, **kwargs):
        super(GlobalConfigApiView, self).__init__(*args, **kwargs)
        # from v11 onwards use v11_params else v5_params
        self.params = frozenset(
            v11_params) if request.blueprint in api_versions_v5[6:] \
            else frozenset(v5_params)

    @check_precondition
    def put(self, alert_id):
        """
        This function will update alert parameters at global level.

        :param alert_id: Alert Id for which information will be fetched.

        Input Data: Below are the json input format required to update
        alert.

        Below are required data type for each input parameters.
        "alert_name": string,
        "alert_template": string, ( positive integer values. )
        "low_threshold_value": string, ( integer/float values. )
        "medium_threshold_value": string, ( integer/float values. )
        "high_threshold_value": string, (  integer/float values. )
        "history_retention": string, ( Possible values 1-99999 )
        "enabled": string, ( Possible values true and false)
        "frequency_min": string ( Possible values 1-65534 )
        "operator": string ( Valid string are ">" and "<")
        "params": list of dict values.

        Example input data as below.
        {
          "alert_name":"alert_name",
          "alert_template": "180",
          "low_threshold_value": "1",
          "medium_threshold_value": "2",
          "high_threshold_value": "3",
          "history_retention": 32,
          "enabled": true,
          "frequency_min": 11,
          "operator": ">",
          "params":
          {
            "changed": [
              {
                "paramvalue": "7",
                "paramname": "param_1"
              }
            ]
          }
        }

        :return:

        Below is the expected result.

        status: 200 OK
        {
          "success":1,
          "info":"Alert updated successfully.",
          "result":null,
          "errormsg":"",
          "data":null
        }

        """

        data = request.get_json()
        if data is None:
            return make_json_response(
                status=404, success=0,
                errormsg=gettext(
                    "Please specify input data for which you wish "
                    "to update the alert parameters."
                )
            )

        # First check alert id exists or not.
        if alert_id is None:
            return make_json_response(
                status=404, success=0,
                errormsg=gettext("Please specify alert id for which you wish"
                                 "to update the alert parameters.")
            )

        if 'send_trap' in data and data['send_trap'] is True and \
                'snmp_trap_version' in data and \
                request.blueprint in ['v1_api', 'v2_api'] and \
                not isinstance(data['snmp_trap_version'], bool):
            return make_json_response(
                status=404, success=0,
                errormsg=gettext("Invalid SNMP trap version value")
            )

        status, alerts = utils.get_alerts(
            DashboardLevel.DB_GLOBAL, pem_conn=self.conn, alert_id=alert_id
        )
        if not status:
            return internal_server_error(errormsg=alerts)

        if alert_id is not None and len(alerts['rows']) == 0:
            return make_json_response(
                status=404, success=0,
                errormsg=gettext("The specified alert id is not exists.")
            )

        # Check for duplicate alert name
        status, alerts = utils.get_alerts(
            DashboardLevel.DB_GLOBAL, pem_conn=self.conn
        )
        if not status:
            return internal_server_error(errormsg=alerts)

        if len(alerts['rows']) > 0 and 'alert_name' in data:
            for a_param in alerts['rows']:
                if a_param['alert_name'] == data['alert_name']:
                    return make_json_response(
                        status=404, success=0,
                        errormsg=gettext(
                            "The specified alert name already exists."
                        )
                    )

        data['id'] = alert_id

        data = transform_snmp_version_value(data, request)

        # remove any unwanted params passed which are not applicable for
        # current api version.
        data = self.discard_unwanted_params(data)

        # First validate all input parameters
        status, result = utils.validate_update_params(
            alert_id, DashboardLevel.DB_GLOBAL, data, self.is_edb, self.conn
        )
        if not status:
            return bad_request(result)

        self.conn.execute_void('BEGIN')
        # Update all input parameters
        status, result = utils.update_alert(data, self.conn)
        if not status:
            self.conn.execute_void('ROLLBACK')
            return internal_server_error(errormsg=result)

        wh_status, wh_result = validate_update_webhook_params(data, self.conn)
        if not wh_status:
            self.conn.execute_void('ROLLBACK')
            return internal_server_error(errormsg=wh_result)

        wh_status, wh_result = update_webhook_alert_config(data, self.conn)
        if not wh_status:
            self.conn.execute_void('ROLLBACK')
            return internal_server_error(errormsg=wh_result)
        self.conn.execute_void('COMMIT')

        return success_return(message=gettext('Alert updated successfully.'))

    @check_precondition
    def post(self):
        """
        This function will create new alert at global level.

        Input Data: Below are the json input format required to create
        new alert.

        Below are the mandatory parameters required to create the new
        alert and input are always dict of below values.

        "alert_name", "alert_template", "low_threshold_value",
        "medium_threshold_value", "high_threshold_value",
        "frequency_min", "operator", "history_retention", "enabled".
        If alert template requires then "params"

        Below are required data type for each input parameters.
        "alert_name": string,
        "alert_template": string, ( positive integer values. )
        "low_threshold_value": string, ( integer/flaot values. )
        "medium_threshold_value": string, ( integer/float values. )
        "high_threshold_value": string, (  integer/float values. )
        "history_retention": string, ( Possible values 1-99999 )
        "enabled": string, ( Possible values true and false)
        "frequency_min": string ( Possible values 1-65534 )
        "operator": string ( Valid string are ">" and "<")
        "params": list of dict values.

        Example input data as below.
        {
          "alert_name":"alert_name",
          "alert_template": "180",
          "low_threshold_value": "1",
          "medium_threshold_value": "2",
          "high_threshold_value": "3",
          "history_retention": 32,
          "enabled": true,
          "frequency_min": 11,
          "operator": ">",
          "params": [
            {
              "paramvalue": "7",
              "paramname": "param_1"
            }
          ]
        }

        :return:

        Below is the expected result.

        status: 200 OK
        {
          "success":1,
          "info":"Alert created successfully.",
          "result":null,
          "errormsg":"",
          "data":null
        }

        """

        data = request.get_json()
        if data is None:
            return make_json_response(
                status=404, success=0,
                errormsg=gettext(
                    "Please specify input data for which you wish "
                    "to create the alert."
                )
            )

        if 'send_trap' in data and data['send_trap'] is True and \
                'snmp_trap_version' in data and \
                request.blueprint in ['v1_api', 'v2_api'] and \
                not isinstance(data['snmp_trap_version'], bool):
            return make_json_response(
                status=404, success=0,
                errormsg=gettext("Invalid SNMP trap version value")
            )

        # Check for duplicate alert name
        status, alerts = utils.get_alerts(
            DashboardLevel.DB_GLOBAL, pem_conn=self.conn
        )
        if not status:
            return internal_server_error(errormsg=alerts)

        if len(alerts['rows']) > 0 and 'alert_name' in data:
            for a_param in alerts['rows']:
                if a_param['alert_name'] == data['alert_name']:
                    return make_json_response(
                        status=404, success=0,
                        errormsg=gettext(
                            "The specified alert name already exists."
                        )
                    )

        # Create the node information to create the new alert.
        node_info = {
            'target_type_id': DashboardLevel.DB_GLOBAL
        }

        data = transform_snmp_version_value(data, request)

        # remove any unwanted params passed which are not applicable for
        # current api version.
        data = self.discard_unwanted_params(data)

        # First validate all input parameters
        status, result = utils.validate_insert_params(
            DashboardLevel.DB_GLOBAL, data, self.is_edb, self.conn
        )
        if not status:
            return bad_request(result)

        self.conn.execute_void('BEGIN')
        status, result = utils.insert_alert(data, node_info, self.conn)
        if not status:
            self.conn.execute_void('ROLLBACK')
            return internal_server_error(errormsg=result)

        if result:
            wh_status, wh_result = insert_webhook_alert_config(
                result, data, self.conn)
            if not wh_status:
                self.conn.execute_void('ROLLBACK')
                return internal_server_error(errormsg=wh_result)
        self.conn.execute_void('COMMIT')

        return success_return(message=gettext('Alert created successfully.'))


class AgentConfigApiV5View(AgentConfigApiView):
    """
    API to expose the configuration of the alerts at agent level.
    """

    endpoint = 'agent_alert_config_V5'

    # Api version from v5 till latest
    # ['v5_api', 'v6_api', 'v7_api', 'v8_api']
    api_versions = api_versions_v5

    def __init__(self, *args, **kwargs):
        super(AgentConfigApiView, self).__init__(*args, **kwargs)
        # from v11 onwards use v11_params else v5_params
        self.params = frozenset(
            v11_params) if request.blueprint in api_versions_v5[6:] \
            else frozenset(v5_params)

    @check_precondition
    def put(self, agent_id, alert_id):
        """
        This function will update the alert for specified agent id.

        :param agent_id: Agent Id for which alerts will be fetched.
        :param alert_id: Alert Id for which information will be fetched.

        Input Data: Below are the json input format required to update
        alert.

        Below are required data type for each input parameters.
        "alert_name": string,
        "alert_template": string, ( positive integer values. )
        "low_threshold_value": string, ( integer/flaot values. )
        "medium_threshold_value": string, ( integer/float values. )
        "high_threshold_value": string, (  integer/float values. )
        "history_retention": string, ( Possible values 1-99999 )
        "enabled": string, ( Possible values true and false)
        "frequency_min": string ( Possible values 1-65534 )
        "operator": string ( Valid string are ">" and "<")
        "params": list of dict values.

        Example input data as below.
        {
          "alert_name":"alert_name",
          "alert_template": "180",
          "low_threshold_value": "1",
          "medium_threshold_value": "2",
          "high_threshold_value": "3",
          "history_retention": 32,
          "enabled": true,
          "frequency_min": 11,
          "operator": ">",
          "params":
          {
            "changed": [
              {
                "paramvalue": "7",
                "paramname": "param_1"
              }
            ]
          }
        }

        :return:

        Below is the expected result.

        status: 200 OK
        {
          "success":1,
          "info":"Alert updated successfully.",
          "result":null,
          "errormsg":"",
          "data":null
        }

        """

        data = request.get_json()
        if data is None:
            return make_json_response(
                status=404, success=0,
                errormsg=gettext(
                    "Please specify input data for which you "
                    "wish to update the alert parameters."
                )
            )

        # Check agent exists or not.
        agent_exist = is_agent_exists(self.conn, agent_id)
        if not agent_exist:
            return make_json_response(
                status=404, success=0,
                errormsg=gettext("The specified agent not found!")
            )

        # First check alert id exists or not.
        if alert_id is None:
            return make_json_response(
                status=404, success=0,
                errormsg=gettext(
                    "Please specify alert id for which you wish "
                    "to update the alert parameters."
                )
            )

        if 'send_trap' in data and data['send_trap'] is True and \
                'snmp_trap_version' in data and \
                request.blueprint in ['v1_api', 'v2_api'] and \
                not isinstance(data['snmp_trap_version'], bool):
            return make_json_response(
                status=404, success=0,
                errormsg=gettext("Invalid SNMP trap version value")
            )

        status, alerts = utils.get_alerts(
            DashboardLevel.DB_AGENT, agent_id, pem_conn=self.conn,
            alert_id=alert_id
        )
        if not status:
            return internal_server_error(errormsg=alerts)

        if alert_id is not None and len(alerts['rows']) == 0:
            return make_json_response(
                status=404, success=0,
                errormsg=gettext(
                    "The specified alert id is not applicable "
                    "for the specified agent"
                )
            )

        # Check for duplicate alert name
        status, alerts = utils.get_alerts(
            DashboardLevel.DB_AGENT, agent_id, pem_conn=self.conn
        )
        if not status:
            return internal_server_error(errormsg=alerts)

        if len(alerts['rows']) > 0 and 'alert_name' in data:
            for a_param in alerts['rows']:
                if a_param['alert_name'] == data['alert_name']:
                    return make_json_response(
                        status=404, success=0,
                        errormsg=gettext(
                            "The specified alert name already exists."
                        )
                    )

        data['id'] = alert_id
        data = transform_snmp_version_value(data, request)

        # remove any unwanted params passed which are not applicable for
        # current api version.
        data = self.discard_unwanted_params(data)

        # First validate all input parameters
        status, result = utils.validate_update_params(
            alert_id, DashboardLevel.DB_AGENT, data, self.is_edb, self.conn
        )
        if not status:
            return bad_request(result)

        self.conn.execute_void('BEGIN')
        status, result = utils.update_alert(data, self.conn)
        if not status:
            self.conn.execute_void('ROLLBACK')
            return internal_server_error(errormsg=result)

        wh_status, wh_result = validate_update_webhook_params(data, self.conn)
        if not wh_status:
            self.conn.execute_void('ROLLBACK')
            return internal_server_error(errormsg=wh_result)

        wh_status, wh_result = update_webhook_alert_config(data, self.conn)
        if not wh_status:
            self.conn.execute_void('ROLLBACK')
            return internal_server_error(errormsg=wh_result)
        self.conn.execute_void('COMMIT')

        return success_return(message=gettext('Alert updated successfully.'))

    @check_precondition
    def post(self, agent_id):
        """
        This function will create new alert for specified agent id.

        :param agent_id: Agent Id for which alerts will be fetched.

        Input Data: Below are the json input format required to create
        new alert.

        Below are the mandatory parameters required to create the new
        alert and input are always dict of below values.

        "alert_name", "alert_template", "low_threshold_value",
        "medium_threshold_value", "high_threshold_value",
        "frequency_min", "operator", "history_retention", "enabled".
        If alert template requires then "params"

        Below are required data type for each input parameters.
        "alert_name": string,
        "alert_template": string, ( positive integer values. )
        "low_threshold_value": string, ( integer/float values. )
        "medium_threshold_value": string, ( integer/float values. )
        "high_threshold_value": string, (  integer/float values. )
        "history_retention": string, ( Possible values 1-99999 )
        "enabled": string, ( Possible values true and false)
        "frequency_min": string ( Possible values 1-65534 )
        "operator": string ( Valid string are ">" and "<")
        "params": list of dict values.

        Example input data as below.
        {
          "alert_name":"alert_name",
          "alert_template": "180",
          "low_threshold_value": "1",
          "medium_threshold_value": "2",
          "high_threshold_value": "3",
          "history_retention": 32,
          "enabled": true,
          "frequency_min": 11,
          "operator": ">",
          "params": [
            {
              "paramvalue": "7",
              "paramname": "param_1"
            }
          ]
        }

        :return:

        Below is the expected result.

        status: 200 OK
        {
          "success":1,
          "info":"Alert created successfully.",
          "result":null,
          "errormsg":"",
          "data":null
        }

        """

        data = request.get_json()
        if data is None:
            return make_json_response(
                status=404, success=0,
                errormsg=gettext(
                    "Please specify input data for which you wish "
                    "to create the alert."
                )
            )

        # Check agent exists or not.
        agent_exist = is_agent_exists(self.conn, agent_id)
        if not agent_exist:
            return make_json_response(
                status=404, success=0,
                errormsg=gettext("The specified agent not found!")
            )

        if 'send_trap' in data and data['send_trap'] is True and \
                'snmp_trap_version' in data and \
                request.blueprint in ['v1_api', 'v2_api'] and \
                not isinstance(data['snmp_trap_version'], bool):
            return make_json_response(
                status=404, success=0,
                errormsg=gettext("Invalid SNMP trap version value")
            )

        # Check for duplicate alert name
        status, alerts = utils.get_alerts(
            DashboardLevel.DB_AGENT, agent_id, pem_conn=self.conn
        )
        if not status:
            return internal_server_error(errormsg=alerts)

        if len(alerts['rows']) > 0 and 'alert_name' in data:
            for a_param in alerts['rows']:
                if a_param['alert_name'] == data['alert_name']:
                    return make_json_response(
                        status=404, success=0,
                        errormsg=gettext(
                            "The specified alert name already exists."
                        )
                    )

        # Create the node information to create the new alert.
        node_info = {
            'target_type_id': DashboardLevel.DB_AGENT,
            'agent_id': agent_id
        }

        data = transform_snmp_version_value(data, request)

        # remove any unwanted params passed which are not applicable for
        # current api version.
        data = self.discard_unwanted_params(data)

        # First validate all input parameters
        status, result = utils.validate_insert_params(
            DashboardLevel.DB_AGENT, data, self.is_edb, self.conn
        )
        if not status:
            return bad_request(result)

        self.conn.execute_void('BEGIN')
        status, result = utils.insert_alert(data, node_info, self.conn)
        if not status:
            self.conn.execute_void('ROLLBACK')
            return internal_server_error(errormsg=result)
        if result:
            status, result = insert_webhook_alert_config(
                result, data, self.conn)
            if not status:
                self.conn.execute_void('ROLLBACK')
                return internal_server_error(errormsg=result)
        self.conn.execute_void('COMMIT')

        return success_return(message=gettext('Alert created successfully.'))


class ServerConfigApiV5View(ServerConfigApiView):
    """
    API to expose the configuration of the alerts at server level.
    """

    endpoint = 'server_alert_config_V5'

    # Api version from v5 till latest
    # ['v5_api', 'v6_api', 'v7_api', 'v8_api']
    api_versions = api_versions_v5

    def __init__(self, *args, **kwargs):
        super(ServerConfigApiView, self).__init__(*args, **kwargs)
        # from v11 onwards use v11_params else v5_params
        self.params = frozenset(
            v11_params) if request.blueprint in api_versions_v5[6:] \
            else frozenset(v5_params)

    @check_precondition
    def put(self, server_id, alert_id=None):
        """
        This function will update the alert for specified server.

        :param server_id: Server Id for which alerts will be fetched.
        :param alert_id: Alert Id for which information will be fetched.

        Input Data: Below are the json input format required to update
        alert.

        Below are required data type for each input parameters.
        "alert_name": string,
        "alert_template": string, ( positive integer values. )
        "low_threshold_value": string, ( integer/flaot values. )
        "medium_threshold_value": string, ( integer/float values. )
        "high_threshold_value": string, (  integer/float values. )
        "history_retention": string, ( Possible values 1-99999 )
        "enabled": string, ( Possible values true and false)
        "frequency_min": string ( Possible values 1-65534 )
        "operator": string ( Valid string are ">" and "<")
        "params": list of dict values.

        Example input data as below.
        {
          "alert_name":"alert_name",
          "alert_template": "180",
          "low_threshold_value": "1",
          "medium_threshold_value": "2",
          "high_threshold_value": "3",
          "history_retention": 32,
          "enabled": true,
          "frequency_min": 11,
          "operator": ">",
          "params":
          {
            "changed": [
              {
                "paramvalue": "7",
                "paramname": "param_1"
              }
            ]
          }
        }

        :return:

        Below is the expected result.

        status: 200 OK
        {
          "success":1,
          "info":"Alert updated successfully.",
          "result":null,
          "errormsg":"",
          "data":null
        }

        """

        data = request.get_json()
        if data is None:
            return make_json_response(
                status=404, success=0,
                errormsg=gettext(
                    "Please specify input data for which you wish "
                    "to update the alert parameters."
                )
            )

        # Check server exists or not.
        object_exist, msg = is_object_exists(self.conn, 'server', server_id)
        if not object_exist:
            return make_json_response(
                status=404, success=0, errormsg=msg
            )

        # First check alert id exists or not.
        if alert_id is None:
            return make_json_response(
                status=404, success=0,
                errormsg=gettext(
                    "Please specify alert id for which you wish "
                    "to update the alert parameters."
                )
            )

        if 'send_trap' in data and data['send_trap'] is True and \
                'snmp_trap_version' in data and \
                request.blueprint in ['v1_api', 'v2_api'] and \
                not isinstance(data['snmp_trap_version'], bool):
            return make_json_response(
                status=404, success=0,
                errormsg=gettext("Invalid SNMP trap version value")
            )

        status, alerts = utils.get_alerts(
            DashboardLevel.DB_SERVER, server_id, pem_conn=self.conn,
            alert_id=alert_id
        )
        if not status:
            return internal_server_error(errormsg=alerts)

        if alert_id is not None and len(alerts['rows']) == 0:
            return make_json_response(
                status=404, success=0,
                errormsg=gettext(
                    "The specified alert id is not applicable "
                    "for the specified server"
                )
            )

        # Check for duplicate alert name
        status, alerts = utils.get_alerts(
            DashboardLevel.DB_SERVER, server_id, pem_conn=self.conn
        )
        if not status:
            return internal_server_error(errormsg=alerts)

        if len(alerts['rows']) > 0 and 'alert_name' in data:
            for a_param in alerts['rows']:
                if a_param['alert_name'] == data['alert_name']:
                    return make_json_response(
                        status=404, success=0,
                        errormsg=gettext(
                            "The specified alert name already exists."
                        )
                    )

        data['id'] = alert_id
        data = transform_snmp_version_value(data, request)

        # remove any unwanted params passed which are not applicable for
        # current api version.
        data = self.discard_unwanted_params(data)

        # First validate all input parameters
        status, result = utils.validate_update_params(
            alert_id, DashboardLevel.DB_SERVER, data, self.is_edb, self.conn
        )
        if not status:
            return bad_request(result)

        self.conn.execute_void('BEGIN')
        status, result = utils.update_alert(data, self.conn, is_api=True)
        if not status:
            self.conn.execute_void('ROLLBACK')
            return internal_server_error(errormsg=result)

        wh_status, wh_result = validate_update_webhook_params(data, self.conn)
        if not wh_status:
            self.conn.execute_void('ROLLBACK')
            return internal_server_error(errormsg=wh_result)

        wh_status, wh_result = update_webhook_alert_config(data, self.conn)
        if not wh_status:
            self.conn.execute_void('ROLLBACK')
            return internal_server_error(errormsg=wh_result)
        self.conn.execute_void('COMMIT')

        return success_return(message=gettext('Alert updated successfully.'))

    @check_precondition
    def post(self, server_id):
        """
        This function will create new alert for specified server.

        :param server_id: Server Id for which alerts will be created.

        Input Data: Below are the json input format required to create
        new alert.

        Below are the mandatory parameters required to create the new
        alert and input are always dict of below values.

        "alert_name", "alert_template", "low_threshold_value",
        "medium_threshold_value", "high_threshold_value",
        "frequency_min", "operator", "history_retention", "enabled".
        If alert template requires then "params"

        Below are required data type for each input parameters.
        "alert_name": string,
        "alert_template": string, ( positive integer values. )
        "low_threshold_value": string, ( integer/flaot values. )
        "medium_threshold_value": string, ( integer/float values. )
        "high_threshold_value": string, (  integer/float values. )
        "history_retention": string, ( Possible values 1-99999 )
        "enabled": string, ( Possible values true and false)
        "frequency_min": string ( Possible values 1-65534 )
        "operator": string ( Valid string are ">" and "<")
        "params": list of dict values.

        Example input data as below.
        {
          "alert_name":"alert_name",
          "alert_template": "180",
          "low_threshold_value": "1",
          "medium_threshold_value": "2",
          "high_threshold_value": "3",
          "history_retention": 32,
          "enabled": true,
          "frequency_min": 11,
          "operator": ">",
          "params": [
            {
              "paramvalue": "7",
              "paramname": "param_1"
            }
          ]
        }

        :return:

        Below is the expected result.

        status: 200 OK
        {
          "success":1,
          "info":"Alert created successfully.",
          "result":null,
          "errormsg":"",
          "data":null
        }

        """

        data = request.get_json()
        if data is None:
            return make_json_response(
                status=404, success=0,
                errormsg=gettext(
                    "Please specify input data for which you wish "
                    "to create the alert."
                )
            )

        # Check server exists or not.
        object_exist, msg = is_object_exists(self.conn, 'server', server_id)
        if not object_exist:
            return make_json_response(
                status=404, success=0, errormsg=msg
            )

        if 'send_trap' in data and data['send_trap'] is True and \
                'snmp_trap_version' in data and \
                request.blueprint in ['v1_api', 'v2_api'] and \
                not isinstance(data['snmp_trap_version'], bool):
            return make_json_response(
                status=404, success=0,
                errormsg=gettext("Invalid SNMP trap version value")
            )

        # Check for duplicate alert name
        status, alerts = utils.get_alerts(
            DashboardLevel.DB_SERVER, server_id, pem_conn=self.conn
        )
        if not status:
            return internal_server_error(errormsg=alerts)

        if len(alerts['rows']) > 0 and 'alert_name' in data:
            for a_param in alerts['rows']:
                if a_param['alert_name'] == data['alert_name']:
                    return make_json_response(
                        status=404, success=0,
                        errormsg=gettext(
                            "The specified alert name already exists."
                        )
                    )

        # Create the node information to create the new alert.
        node_info = {
            'target_type_id': DashboardLevel.DB_SERVER,
            'server_id': server_id
        }
        data = transform_snmp_version_value(data, request)

        # remove any unwanted params passed which are not applicable for
        # current api version.
        data = self.discard_unwanted_params(data)

        # First validate all input parameters
        status, result = utils.validate_insert_params(
            DashboardLevel.DB_SERVER, data, self.is_edb, self.conn
        )
        if not status:
            return bad_request(result)

        self.conn.execute_void('BEGIN')
        status, result = utils.insert_alert(data, node_info, self.conn)
        if not status:
            self.conn.execute_void('ROLLBACK')
            return internal_server_error(errormsg=result)

        if result:
            wh_status, wh_result = insert_webhook_alert_config(
                result, data, self.conn)
            if not wh_status:
                self.conn.execute_void('ROLLBACK')
                return internal_server_error(errormsg=wh_result)
        self.conn.execute_void('COMMIT')

        return success_return(message=gettext('Alert created successfully.'))


class DatabaseConfigApiV5View(DatabaseConfigApiView):
    """
    API to expose the configuration of the alerts at database level.
    """

    endpoint = 'database_alert_config_V5'

    # Api version from v5 till latest
    # ['v5_api', 'v6_api', 'v7_api', 'v8_api']
    api_versions = api_versions_v5

    def __init__(self, *args, **kwargs):
        super(DatabaseConfigApiView, self).__init__(*args, **kwargs)
        # from v11 onwards use v11_params else v5_params
        self.params = frozenset(
            v11_params) if request.blueprint in api_versions_v5[6:] \
            else frozenset(v5_params)

    @check_precondition
    def put(self, server_id, database_name, alert_id=None):
        """
        This function will update the alert for specified server and database.

        :param server_id: Server Id for which alerts will be fetched.
        :param database_name: Database Name for which alerts will be fetched.
        :param alert_id: Alert Id for which information will be fetched.

        Input Data: Below are the json input format required to update
        alert.

        Below are required data type for each input parameters.
        "alert_name": string,
        "alert_template": string, ( positive integer values. )
        "low_threshold_value": string, ( integer/flaot values. )
        "medium_threshold_value": string, ( integer/float values. )
        "high_threshold_value": string, (  integer/float values. )
        "history_retention": string, ( Possible values 1-99999 )
        "enabled": string, ( Possible values true and false)
        "frequency_min": string ( Possible values 1-65534 )
        "operator": string ( Valid string are ">" and "<")
        "params": list of dict values.

        Example input data as below.
        {
          "alert_name":"alert_name",
          "alert_template": "180",
          "low_threshold_value": "1",
          "medium_threshold_value": "2",
          "high_threshold_value": "3",
          "history_retention": 32,
          "enabled": true,
          "frequency_min": 11,
          "operator": ">",
          "params":
          {
            "changed": [
              {
                "paramvalue": "7",
                "paramname": "param_1"
              }
            ]
          }
        }

        :return:

        Below is the expected result.

        status: 200 OK
        {
          "success":1,
          "info":"Alert updated successfully.",
          "result":null,
          "errormsg":"",
          "data":null
        }

        """

        data = request.get_json()
        if data is None:
            return make_json_response(
                status=404, success=0,
                errormsg=gettext(
                    "Please specify input data for which you wish "
                    "to update the alert parameters."
                )
            )

        # Check database exists or not.
        object_exist, msg = is_object_exists(self.conn, 'database', server_id,
                                             database_name)
        if not object_exist:
            return make_json_response(
                status=404, success=0, errormsg=msg
            )

        # First check alert id exists or not.
        if alert_id is None:
            return make_json_response(
                status=404, success=0,
                errormsg=gettext(
                    "Please specify alert id for which you wish "
                    "to update the alert parameters."
                )
            )

        if 'send_trap' in data and data['send_trap'] is True and \
                'snmp_trap_version' in data and \
                request.blueprint in ['v1_api', 'v2_api'] and \
                not isinstance(data['snmp_trap_version'], bool):
            return make_json_response(
                status=404, success=0,
                errormsg=gettext("Invalid SNMP trap version value")
            )

        status, alerts = utils.get_alerts(
            DashboardLevel.DB_DATABASE, server_id, database_name,
            pem_conn=self.conn, alert_id=alert_id
        )
        if not status:
            return internal_server_error(errormsg=alerts)

        if alert_id is not None and len(alerts['rows']) == 0:
            return make_json_response(
                status=404, success=0,
                errormsg=gettext(
                    "The specified alert id is not applicable "
                    "for the specified database"
                )
            )

        # Check for duplicate alert name
        status, alerts = utils.get_alerts(
            DashboardLevel.DB_DATABASE, server_id, database_name,
            pem_conn=self.conn
        )
        if not status:
            return internal_server_error(errormsg=alerts)

        if len(alerts['rows']) > 0 and 'alert_name' in data:
            for a_param in alerts['rows']:
                if a_param['alert_name'] == data['alert_name']:
                    return make_json_response(
                        status=404, success=0,
                        errormsg=gettext(
                            "The specified alert name already exists."
                        )
                    )

        data['id'] = alert_id
        data = transform_snmp_version_value(data, request)

        # remove any unwanted params passed which are not applicable for
        # current api version.
        data = self.discard_unwanted_params(data)

        # First validate all input parameters
        status, result = \
            utils.validate_update_params(alert_id, DashboardLevel.DB_DATABASE,
                                         data, self.is_edb, self.conn)
        if not status:
            return bad_request(result)

        self.conn.execute_void('BEGIN')
        status, result = utils.update_alert(data, self.conn)
        if not status:
            self.conn.execute_void('ROLLBACK')
            return internal_server_error(errormsg=result)

        wh_status, wh_result = validate_update_webhook_params(data, self.conn)
        if not wh_status:
            self.conn.execute_void('ROLLBACK')
            return internal_server_error(errormsg=wh_result)

        wh_status, wh_result = update_webhook_alert_config(data, self.conn)
        if not wh_status:
            self.conn.execute_void('ROLLBACK')
            return internal_server_error(errormsg=wh_result)
        self.conn.execute_void('COMMIT')

        return success_return(message=gettext('Alert updated successfully.'))

    @check_precondition
    def post(self, server_id, database_name):
        """
        This function will create the new alert for specified server
        and database.

        :param server_id: Server Id for which alerts will be created.
        :param database_name: Database Name for which alerts will be created.

        Input Data: Below are the json input format required to create
        new alert.

        Below are the mandatory parameters required to create the new
        alert and input are always dict of below values.

        "alert_name", "alert_template", "low_threshold_value",
        "medium_threshold_value", "high_threshold_value",
        "frequency_min", "operator", "history_retention", "enabled".
        If alert template requires then "params"

        Below are required data type for each input parameters.
        "alert_name": string,
        "alert_template": string, ( positive integer values. )
        "low_threshold_value": string, ( integer/float values. )
        "medium_threshold_value": string, ( integer/float values. )
        "high_threshold_value": string, (  integer/float values. )
        "history_retention": string, ( Possible values 1-99999 )
        "enabled": string, ( Possible values true and false)
        "frequency_min": string ( Possible values 1-65534 )
        "operator": string ( Valid string are ">" and "<")
        "params": list of dict values.

        Example input data as below.
        {
          "alert_name":"alert_name",
          "alert_template": "180",
          "low_threshold_value": "1",
          "medium_threshold_value": "2",
          "high_threshold_value": "3",
          "history_retention": 32,
          "enabled": true,
          "frequency_min": 11,
          "operator": ">",
          "params": [
            {
              "paramvalue": "7",
              "paramname": "param_1"
            }
          ]
        }

        :return:

        Below is the expected result.

        status: 200 OK
        {
          "success":1,
          "info":"Alert created successfully.",
          "result":null,
          "errormsg":"",
          "data":null
        }

        """

        data = request.get_json()
        if data is None:
            return make_json_response(
                status=404, success=0,
                errormsg=gettext(
                    "Please specify input data for which you wish "
                    "to create the alert."
                )
            )

        # Check database exists or not.
        object_exist, msg = is_object_exists(self.conn, 'database', server_id,
                                             database_name)
        if not object_exist:
            return make_json_response(
                status=404, success=0, errormsg=msg
            )

        if 'send_trap' in data and data['send_trap'] is True and \
                'snmp_trap_version' in data and \
                request.blueprint in ['v1_api', 'v2_api'] and \
                not isinstance(data['snmp_trap_version'], bool):
            return make_json_response(
                status=404, success=0,
                errormsg=gettext("Invalid SNMP trap version value")
            )

        # Check for duplicate alert name
        status, alerts = utils.get_alerts(
            DashboardLevel.DB_DATABASE, server_id, database_name,
            pem_conn=self.conn
        )
        if not status:
            return internal_server_error(errormsg=alerts)

        if len(alerts['rows']) > 0 and 'alert_name' in data:
            for a_param in alerts['rows']:
                if a_param['alert_name'] == data['alert_name']:
                    return make_json_response(
                        status=404, success=0,
                        errormsg=gettext(
                            "The specified alert name already exists."
                        )
                    )

        # Create the node information to create the new alert.
        node_info = {
            'target_type_id': DashboardLevel.DB_DATABASE,
            'server_id': server_id,
            'database_name': database_name
        }
        data = transform_snmp_version_value(data, request)

        # remove any unwanted params passed which are not applicable for
        # current api version.
        data = self.discard_unwanted_params(data)

        # First validate all input parameters
        status, result = \
            utils.validate_insert_params(DashboardLevel.DB_DATABASE, data,
                                         self.is_edb, self.conn)
        if not status:
            return bad_request(result)

        self.conn.execute_void('BEGIN')
        status, result = utils.insert_alert(data, node_info, self.conn)
        if not status:
            self.conn.execute_void('ROLLBACK')
            return internal_server_error(errormsg=result)

        if result:
            wh_status, wh_result = insert_webhook_alert_config(
                result, data, self.conn)
            if not wh_status:
                self.conn.execute_void('ROLLBACK')
                return internal_server_error(errormsg=wh_result)
        self.conn.execute_void('COMMIT')

        return success_return(message=gettext('Alert created successfully.'))


class SchemaConfigApiV5View(SchemaConfigApiView):
    """
    API to expose the configuration of the alerts at schema level.
    """

    endpoint = 'schema_alert_config_V5'

    # Api version from v5 till latest
    # ['v5_api', 'v6_api', 'v7_api', 'v8_api']
    api_versions = api_versions_v5

    def __init__(self, *args, **kwargs):
        super(SchemaConfigApiView, self).__init__(*args, **kwargs)
        # from v11 onwards use v11_params else v5_params
        self.params = frozenset(
            v11_params) if request.blueprint in api_versions_v5[6:] \
            else frozenset(v5_params)

    @check_precondition
    def put(self, server_id, database_name,
            schema_name, alert_id=None):
        """
        This function will update the alert for specified
        server, database and schema

        :param server_id: Server Id for which alerts will be fetched.
        :param database_name: Database Name for which alerts will be fetched.
        :param schema_name: Schema Name for which alerts will be fetched.
        :param alert_id: Alert Id for which information will be fetched.

        Input Data: Below are the json input format required to update
        alert.

        Below are required data type for each input parameters.
        "alert_name": string,
        "alert_template": string, ( positive integer values. )
        "low_threshold_value": string, ( integer/float values. )
        "medium_threshold_value": string, ( integer/float values. )
        "high_threshold_value": string, (  integer/float values. )
        "history_retention": string, ( Possible values 1-99999 )
        "enabled": string, ( Possible values true and false)
        "frequency_min": string ( Possible values 1-65534 )
        "operator": string ( Valid string are ">" and "<")
        "params": list of dict values.

        Example input data as below.
        {
          "alert_name":"alert_name",
          "alert_template": "180",
          "low_threshold_value": "1",
          "medium_threshold_value": "2",
          "high_threshold_value": "3",
          "history_retention": 32,
          "enabled": true,
          "frequency_min": 11,
          "operator": ">",
          "params":
          {
            "changed": [
              {
                "paramvalue": "7",
                "paramname": "param_1"
              }
            ]
          }
        }

        :return:

        Below is the expected result.

        status: 200 OK
        {
          "success":1,
          "info":"Alert updated successfully.",
          "result":null,
          "errormsg":"",
          "data":null
        }

        """

        data = request.get_json()
        if data is None:
            return make_json_response(
                status=404, success=0,
                errormsg=gettext(
                    "Please specify input data for which you wish to "
                    "update the alert parameters."
                )
            )

        object_exist, msg = is_object_exists(self.conn, 'schema', server_id,
                                             database_name, schema_name)
        if not object_exist:
            return make_json_response(
                status=404, success=0, errormsg=msg
            )

        # First check alert id exists or not.
        if alert_id is None:
            return make_json_response(
                status=404, success=0,
                errormsg=gettext(
                    "Please specify alert id for which you wish to "
                    "update the alert parameters."
                )
            )

        if 'send_trap' in data and data['send_trap'] is True and \
                'snmp_trap_version' in data and \
                request.blueprint in ['v1_api', 'v2_api'] and \
                not isinstance(data['snmp_trap_version'], bool):
            return make_json_response(
                status=404, success=0,
                errormsg=gettext("Invalid SNMP trap version value")
            )

        status, alerts = utils.get_alerts(
            DashboardLevel.DB_SCHEMA, server_id, database_name,
            schema_name, pem_conn=self.conn, alert_id=alert_id
        )
        if not status:
            return internal_server_error(errormsg=alerts)

        if alert_id is not None and len(alerts['rows']) == 0:
            return make_json_response(
                status=404, success=0,
                errormsg=gettext(
                    "The specified alert id is not applicable for "
                    "the specified schema"
                )
            )

        # Check for duplicate alert name
        status, alerts = utils.get_alerts(
            DashboardLevel.DB_SCHEMA, server_id, database_name,
            schema_name, pem_conn=self.conn
        )
        if not status:
            return internal_server_error(errormsg=alerts)

        if len(alerts['rows']) > 0 and 'alert_name' in data:
            for a_param in alerts['rows']:
                if a_param['alert_name'] == data['alert_name']:
                    return make_json_response(
                        status=404, success=0,
                        errormsg=gettext(
                            "The specified alert name already exists."
                        )
                    )

        data['id'] = alert_id
        data = transform_snmp_version_value(data, request)

        # remove any unwanted params passed which are not applicable for
        # current api version.
        data = self.discard_unwanted_params(data)

        # First validate all input parameters
        status, result = utils.validate_update_params(
            alert_id, DashboardLevel.DB_SCHEMA, data, self.is_edb, self.conn
        )
        if not status:
            return bad_request(result)

        self.conn.execute_void('BEGIN')
        status, result = utils.update_alert(data, self.conn)
        if not status:
            self.conn.execute_void('ROLLBACK')
            return internal_server_error(errormsg=result)

        wh_status, wh_result = validate_update_webhook_params(data, self.conn)
        if not wh_status:
            self.conn.execute_void('ROLLBACK')
            return internal_server_error(errormsg=wh_result)

        wh_status, wh_result = update_webhook_alert_config(data, self.conn)
        if not wh_status:
            self.conn.execute_void('ROLLBACK')
            return internal_server_error(errormsg=wh_result)
        self.conn.execute_void('COMMIT')

        return success_return(message=gettext('Alert updated successfully.'))

    @check_precondition
    def post(self, server_id, database_name, schema_name):
        """
        This function will create the new alert for specified
        server, database and schema.

        :param server_id: Server Id for which alerts will be created.
        :param database_name: Database Name for which alerts will be created.
        :param schema_name: Schema Name for which alerts will be created.

        Input Data: Below are the json input format required to create
        new alert.

        Below are the mandatory parameters required to create the new
        alert and input are always dict of below values.

        "alert_name", "alert_template", "low_threshold_value",
        "medium_threshold_value", "high_threshold_value",
        "frequency_min", "operator", "history_retention", "enabled".
        If alert template requires then "params"

        Below are required data type for each input parameters.
        "alert_name": string,
        "alert_template": string, ( positive integer values. )
        "low_threshold_value": string, ( integer/float values. )
        "medium_threshold_value": string, ( integer/float values. )
        "high_threshold_value": string, (  integer/float values. )
        "history_retention": string, ( Possible values 1-99999 )
        "enabled": string, ( Possible values true and false)
        "frequency_min": string ( Possible values 1-65534 )
        "operator": string ( Valid string are ">" and "<")
        "params": list of dict values.

        Example input data as below.
        {
          "alert_name":"alert_name",
          "alert_template": "180",
          "low_threshold_value": "1",
          "medium_threshold_value": "2",
          "high_threshold_value": "3",
          "history_retention": 32,
          "enabled": true,
          "frequency_min": 11,
          "operator": ">",
          "params": [
            {
              "paramvalue": "7",
              "paramname": "param_1"
            }
          ]
        }

        :return:

        Below is the expected result.

        status: 200 OK
        {
          "success":1,
          "info":"Alert created successfully.",
          "result":null,
          "errormsg":"",
          "data":null
        }

        """

        data = request.get_json()
        if data is None:
            return make_json_response(
                status=404, success=0,
                errormsg=gettext(
                    "Please specify input data for which you wish to "
                    "create the alert."
                )
            )

        object_exist, msg = is_object_exists(self.conn, 'schema', server_id,
                                             database_name, schema_name)
        if not object_exist:
            return make_json_response(
                status=404, success=0, errormsg=msg
            )

        if 'send_trap' in data and data['send_trap'] is True and \
                'snmp_trap_version' in data and \
                request.blueprint in ['v1_api', 'v2_api'] and \
                not isinstance(data['snmp_trap_version'], bool):
            return make_json_response(
                status=404, success=0,
                errormsg=gettext("Invalid SNMP trap version value")
            )

        # Check for duplicate alert name
        status, alerts = utils.get_alerts(
            DashboardLevel.DB_SCHEMA, server_id, database_name,
            schema_name, pem_conn=self.conn
        )
        if not status:
            return internal_server_error(errormsg=alerts)

        if len(alerts['rows']) > 0 and 'alert_name' in data:
            for a_param in alerts['rows']:
                if a_param['alert_name'] == data['alert_name']:
                    return make_json_response(
                        status=404, success=0,
                        errormsg=gettext(
                            "The specified alert name already exists."
                        )
                    )

        # Create the node information to create the new alert.
        node_info = {
            'target_type_id': DashboardLevel.DB_SCHEMA,
            'server_id': server_id,
            'database_name': database_name,
            'schema_name': schema_name,
        }

        data = transform_snmp_version_value(data, request)

        # remove any unwanted params passed which are not applicable for
        # current api version.
        data = self.discard_unwanted_params(data)

        # First validate all input parameters
        status, result = utils.validate_insert_params(
            DashboardLevel.DB_SCHEMA, data, self.is_edb, self.conn
        )
        if not status:
            return bad_request(result)

        self.conn.execute_void('BEGIN')
        status, result = utils.insert_alert(data, node_info, self.conn)

        if not status:
            self.conn.execute_void('ROLLBACK')
            return internal_server_error(errormsg=result)

        if result:
            wh_status, wh_result = insert_webhook_alert_config(
                result, data, self.conn)
            if not wh_status:
                self.conn.execute_void('ROLLBACK')
                return internal_server_error(errormsg=wh_result)
        self.conn.execute_void('COMMIT')

        return success_return(message=gettext('Alert created successfully.'))


class TableConfigApiV5View(TableConfigApiView):
    """
    API to expose the configuration of the alerts at table level.
    """

    endpoint = 'table_alert_config_V5'

    # Api version from v5 till latest
    # ['v5_api', 'v6_api', 'v7_api', 'v8_api']
    api_versions = api_versions_v5

    def __init__(self, *args, **kwargs):
        super(TableConfigApiView, self).__init__(*args, **kwargs)
        # from v11 onwards use v11_params else v5_params
        self.params = frozenset(
            v11_params) if request.blueprint in api_versions_v5[6:] \
            else frozenset(v5_params)

    @check_precondition
    def put(self, server_id, database_name, schema_name,
            object_name, alert_id=None):
        """
        This function will update the alert for specified
        server, database, schema and table.

        :param server_id: Server Id for which alerts will be fetched.
        :param database_name: Database Name for which alerts will be fetched.
        :param schema_name: Schema Name for which alerts will be fetched.
        :param object_name: Table Name for which alerts will be fetched.
        :param alert_id: Alert Id for which information will be fetched.

        Input Data: Below are the json input format required to update
        alert.

        Below are required data type for each input parameters.
        "alert_name": string,
        "alert_template": string, ( positive integer values. )
        "low_threshold_value": string, ( integer/float values. )
        "medium_threshold_value": string, ( integer/float values. )
        "high_threshold_value": string, (  integer/float values. )
        "history_retention": string, ( Possible values 1-99999 )
        "enabled": string, ( Possible values true and false)
        "frequency_min": string ( Possible values 1-65534 )
        "operator": string ( Valid string are ">" and "<")
        "params": list of dict values.

        Example input data as below.
        {
          "alert_name":"alert_name",
          "alert_template": "180",
          "low_threshold_value": "1",
          "medium_threshold_value": "2",
          "high_threshold_value": "3",
          "history_retention": 32,
          "enabled": true,
          "frequency_min": 11,
          "operator": ">",
          "params":
          {
            "changed": [
              {
                "paramvalue": "7",
                "paramname": "param_1"
              }
            ]
          }
        }

        :return:

        Below is the expected result.

        status: 200 OK
        {
          "success":1,
          "info":"Alert updated successfully.",
          "result":null,
          "errormsg":"",
          "data":null
        }

        """

        data = request.get_json()
        if data is None:
            return make_json_response(
                status=404, success=0,
                errormsg=gettext(
                    "Please specify input data for which you wish to "
                    "update the alert parameters."
                )
            )

        object_exist, msg = is_object_exists(self.conn, 'table', server_id,
                                             database_name, schema_name,
                                             object_name)
        if not object_exist:
            return make_json_response(
                status=404, success=0, errormsg=msg
            )

        # First check alert id exists or not.
        if alert_id is None:
            return make_json_response(
                status=404, success=0,
                errormsg=gettext(
                    "Please specify alert id for which you wish to "
                    "update the alert parameters."
                )
            )

        if 'send_trap' in data and data['send_trap'] is True and \
                'snmp_trap_version' in data and \
                request.blueprint in ['v1_api', 'v2_api'] and \
                not isinstance(data['snmp_trap_version'], bool):
            return make_json_response(
                status=404, success=0,
                errormsg=gettext("Invalid SNMP trap version value")
            )

        status, alerts = utils.get_alerts(
            DashboardLevel.DB_TABLE, server_id, database_name,
            schema_name, object_name, pem_conn=self.conn, alert_id=alert_id
        )
        if not status:
            return internal_server_error(errormsg=alerts)

        if alert_id is not None and len(alerts['rows']) == 0:
            return make_json_response(
                status=404, success=0,
                errormsg=gettext(
                    "The specified alert id is not applicable for "
                    "the specified table"
                )
            )

        # Check for duplicate alert name
        status, alerts = utils.get_alerts(
            DashboardLevel.DB_TABLE, server_id, database_name,
            schema_name, object_name, pem_conn=self.conn
        )
        if not status:
            return internal_server_error(errormsg=alerts)

        if len(alerts['rows']) > 0 and 'alert_name' in data:
            for a_param in alerts['rows']:
                if a_param['alert_name'] == data['alert_name']:
                    return make_json_response(
                        status=404, success=0,
                        errormsg=gettext(
                            "The specified alert name already exists."
                        )
                    )

        data['id'] = alert_id
        data = transform_snmp_version_value(data, request)

        # remove any unwanted params passed which are not applicable for
        # current api version.
        data = self.discard_unwanted_params(data)

        # First validate all input parameters
        status, result = utils.validate_update_params(
            alert_id, DashboardLevel.DB_TABLE, data, self.is_edb, self.conn
        )
        if not status:
            return bad_request(result)

        self.conn.execute_void('BEGIN')
        status, result = utils.update_alert(data, self.conn)
        if not status:
            self.conn.execute_void('ROLLBACK')
            return internal_server_error(errormsg=result)

        wh_status, wh_result = validate_update_webhook_params(data, self.conn)
        if not wh_status:
            self.conn.execute_void('ROLLBACK')
            return internal_server_error(errormsg=wh_result)

        wh_status, wh_result = update_webhook_alert_config(data, self.conn)
        if not wh_status:
            self.conn.execute_void('ROLLBACK')
            return internal_server_error(errormsg=wh_result)
        self.conn.execute_void('COMMIT')

        return success_return(message=gettext('Alert updated successfully.'))

    @check_precondition
    def post(self, server_id, database_name, schema_name, object_name):
        """
        This function will create the new alert for specified
        server, database, schema and table.

        :param server_id: Server Id for which alerts will be created.
        :param database_name: Database Name for which alerts will be created.
        :param schema_name: Schema Name for which alerts will be created.
        :param object_name: Table Name for which alerts will be created.

        Input Data: Below are the json input format required to create
        new alert.

        Below are the mandatory parameters required to create the new
        alert and input are always dict of below values.

        "alert_name", "alert_template", "low_threshold_value",
        "medium_threshold_value", "high_threshold_value",
        "frequency_min", "operator", "history_retention", "enabled".
        If alert template requires then "params"

        Below are required data type for each input parameters.
        "alert_name": string,
        "alert_template": string, ( positive integer values. )
        "low_threshold_value": string, ( integer/float values. )
        "medium_threshold_value": string, ( integer/float values. )
        "high_threshold_value": string, (  integer/float values. )
        "history_retention": string, ( Possible values 1-99999 )
        "enabled": string, ( Possible values true and false)
        "frequency_min": string ( Possible values 1-65534 )
        "operator": string ( Valid string are ">" and "<")
        "params": list of dict values.

        Example input data as below.
        {
          "alert_name":"alert_name",
          "alert_template": "180",
          "low_threshold_value": "1",
          "medium_threshold_value": "2",
          "high_threshold_value": "3",
          "history_retention": 32,
          "enabled": true,
          "frequency_min": 11,
          "operator": ">",
          "params": [
            {
              "paramvalue": "7",
              "paramname": "param_1"
            }
          ]
        }

        :return:

        Below is the expected result.

        status: 200 OK
        {
          "success":1,
          "info":"Alert created successfully.",
          "result":null,
          "errormsg":"",
          "data":null
        }

        """

        data = request.get_json()
        if data is None:
            return make_json_response(
                status=404, success=0,
                errormsg=gettext(
                    "Please specify input data for which you wish to "
                    "create the alert."
                )
            )

        object_exist, msg = is_object_exists(self.conn, 'table', server_id,
                                             database_name, schema_name,
                                             object_name)
        if not object_exist:
            return make_json_response(
                status=404, success=0, errormsg=msg
            )

        if 'send_trap' in data and data['send_trap'] is True and \
                'snmp_trap_version' in data and \
                request.blueprint in ['v1_api', 'v2_api'] and \
                not isinstance(data['snmp_trap_version'], bool):
            return make_json_response(
                status=404, success=0,
                errormsg=gettext("Invalid SNMP trap version value")
            )

        # Check for duplicate alert name
        status, alerts = utils.get_alerts(
            DashboardLevel.DB_TABLE, server_id, database_name,
            schema_name, object_name, pem_conn=self.conn
        )
        if not status:
            return internal_server_error(errormsg=alerts)

        if len(alerts['rows']) > 0 and 'alert_name' in data:
            for a_param in alerts['rows']:
                if a_param['alert_name'] == data['alert_name']:
                    return make_json_response(
                        status=404, success=0,
                        errormsg=gettext(
                            "The specified alert name already exists."
                        )
                    )

        # Create the node information to create the new alert.
        node_info = {
            'target_type_id': DashboardLevel.DB_TABLE,
            'server_id': server_id,
            'database_name': database_name,
            'schema_name': schema_name,
            'object_name': object_name
        }
        data = transform_snmp_version_value(data, request)

        # remove any unwanted params passed which are not applicable for
        # current api version.
        data = self.discard_unwanted_params(data)

        # First validate all input parameters
        status, result = utils.validate_insert_params(
            DashboardLevel.DB_TABLE, data, self.is_edb, self.conn
        )
        if not status:
            return bad_request(result)

        self.conn.execute_void('BEGIN')
        status, result = utils.insert_alert(data, node_info, self.conn)
        if not status:
            self.conn.execute_void('ROLLBACK')
            return internal_server_error(errormsg=result)

        if result:
            wh_status, wh_result = insert_webhook_alert_config(
                result, data, self.conn)
            if not wh_status:
                self.conn.execute_void('ROLLBACK')
                return internal_server_error(errormsg=wh_result)
        self.conn.execute_void('COMMIT')

        return success_return(message=gettext('Alert created successfully.'))


class IndexConfigApiV5View(IndexConfigApiView):
    """
    API to expose the configuration of the alerts at index level.
    """

    endpoint = 'index_alert_config_V5'

    # Api version from v5 till latest
    # ['v5_api', 'v6_api', 'v7_api', 'v8_api']
    api_versions = api_versions_v5

    def __init__(self, *args, **kwargs):
        super(IndexConfigApiView, self).__init__(*args, **kwargs)
        # from v11 onwards use v11_params else v5_params
        self.params = frozenset(
            v11_params) if request.blueprint in api_versions_v5[6:] \
            else frozenset(v5_params)

    @check_precondition
    def put(self, server_id, database_name, schema_name,
            object_name, alert_id=None):
        """
        This function will update the alert for specified
        server, database, schema and index.

        :param server_id: Server Id for which alerts will be fetched.
        :param database_name: Database Name for which alerts will be fetched.
        :param schema_name: Schema Name for which alerts will be fetched.
        :param object_name: Table Name for which alerts will be fetched.
        :param alert_id: Alert Id for which information will be fetched.

        Input Data: Below are the json input format required to update
        alert.

        Below are required data type for each input parameters.
        "alert_name": string,
        "alert_template": string, ( positive integer values. )
        "low_threshold_value": string, ( integer/float values. )
        "medium_threshold_value": string, ( integer/float values. )
        "high_threshold_value": string, (  integer/float values. )
        "history_retention": string, ( Possible values 1-99999 )
        "enabled": string, ( Possible values true and false)
        "frequency_min": string ( Possible values 1-65534 )
        "operator": string ( Valid string are ">" and "<")
        "params": list of dict values.

        Example input data as below.
        {
          "alert_name":"alert_name",
          "alert_template": "180",
          "low_threshold_value": "1",
          "medium_threshold_value": "2",
          "high_threshold_value": "3",
          "history_retention": 32,
          "enabled": true,
          "frequency_min": 11,
          "operator": ">",
          "params":
          {
            "changed": [
              {
                "paramvalue": "7",
                "paramname": "param_1"
              }
            ]
          }
        }

        :return:

        Below is the expected result.

        status: 200 OK
        {
          "success":1,
          "info":"Alert updated successfully.",
          "result":null,
          "errormsg":"",
          "data":null
        }

        """

        data = request.get_json()
        if data is None:
            return make_json_response(
                status=404, success=0,
                errormsg=gettext(
                    "Please specify input data for which you wish to "
                    "update the alert parameters."
                )
            )

        object_exist, msg = is_object_exists(self.conn, 'index', server_id,
                                             database_name, schema_name,
                                             object_name)
        if not object_exist:
            return make_json_response(
                status=404, success=0, errormsg=msg
            )

        # First check alert id exists or not.
        if alert_id is None:
            return make_json_response(
                status=404, success=0,
                errormsg=gettext(
                    "Please specify alert id for which you wish to "
                    "update the alert parameters."
                )
            )

        if 'send_trap' in data and data['send_trap'] is True and \
                'snmp_trap_version' in data and \
                request.blueprint in ['v1_api', 'v2_api'] and \
                not isinstance(data['snmp_trap_version'], bool):
            return make_json_response(
                status=404, success=0,
                errormsg=gettext("Invalid SNMP trap version value")
            )

        status, alerts = utils.get_alerts(
            DashboardLevel.DB_INDEX, server_id, database_name,
            schema_name, object_name, pem_conn=self.conn, alert_id=alert_id
        )
        if not status:
            return internal_server_error(errormsg=alerts)

        if alert_id is not None and len(alerts['rows']) == 0:
            return make_json_response(
                status=404, success=0,
                errormsg=gettext(
                    "The specified alert id is not applicable for "
                    "the specified index"
                )
            )

        # Check for duplicate alert name
        status, alerts = utils.get_alerts(
            DashboardLevel.DB_INDEX, server_id, database_name,
            schema_name, object_name, pem_conn=self.conn
        )
        if not status:
            return internal_server_error(errormsg=alerts)

        if len(alerts['rows']) > 0 and 'alert_name' in data:
            for a_param in alerts['rows']:
                if a_param['alert_name'] == data['alert_name']:
                    return make_json_response(
                        status=404, success=0,
                        errormsg=gettext(
                            "The specified alert name already exists."
                        )
                    )

        data['id'] = alert_id
        data = transform_snmp_version_value(data, request)

        # remove any unwanted params passed which are not applicable for
        # current api version.
        data = self.discard_unwanted_params(data)

        # First validate all input parameters
        status, result = utils.validate_update_params(
            alert_id, DashboardLevel.DB_INDEX, data, self.is_edb, self.conn
        )
        if not status:
            return bad_request(result)

        self.conn.execute_void('BEGIN')
        status, result = utils.update_alert(data, self.conn)
        if not status:
            self.conn.execute_void('ROLLBACK')
            return internal_server_error(errormsg=result)

        wh_status, wh_result = validate_update_webhook_params(data, self.conn)
        if not wh_status:
            self.conn.execute_void('ROLLBACK')
            return internal_server_error(errormsg=wh_result)

        wh_status, wh_result = update_webhook_alert_config(data, self.conn)
        if not wh_status:
            self.conn.execute_void('ROLLBACK')
            return internal_server_error(errormsg=wh_result)
        self.conn.execute_void('COMMIT')

        return success_return(message=gettext('Alert updated successfully.'))

    @check_precondition
    def post(self, server_id, database_name, schema_name, object_name):
        """
        This function will create the alert for specified
        server, database, schema and index.

        :param server_id: Server Id for which alerts will be created.
        :param database_name: Database Name for which alerts will be created.
        :param schema_name: Schema Name for which alerts will be created.
        :param object_name: Table Name for which alerts will be created.

        Input Data: Below are the json input format required to create
        new alert.

        Below are the mandatory parameters required to create the new
        alert and input are always dict of below values.

        "alert_name", "alert_template", "low_threshold_value",
        "medium_threshold_value", "high_threshold_value",
        "frequency_min", "operator", "history_retention", "enabled".
        If alert template requires then "params"

        Below are required data type for each input parameters.
        "alert_name": string,
        "alert_template": string, ( positive integer values. )
        "low_threshold_value": string, ( integer/float values. )
        "medium_threshold_value": string, ( integer/float values. )
        "high_threshold_value": string, (  integer/float values. )
        "history_retention": string, ( Possible values 1-99999 )
        "enabled": string, ( Possible values true and false)
        "frequency_min": string ( Possible values 1-65534 )
        "operator": string ( Valid string are ">" and "<")
        "params": list of dict values.

        Example input data as below.
        {
          "alert_name":"alert_name",
          "alert_template": "180",
          "low_threshold_value": "1",
          "medium_threshold_value": "2",
          "high_threshold_value": "3",
          "history_retention": 32,
          "enabled": true,
          "frequency_min": 11,
          "operator": ">",
          "params": [
            {
              "paramvalue": "7",
              "paramname": "param_1"
            }
          ]
        }

        :return:

        Below is the expected result.

        status: 200 OK
        {
          "success":1,
          "info":"Alert created successfully.",
          "result":null,
          "errormsg":"",
          "data":null
        }

        """

        data = request.get_json()
        if data is None:
            return make_json_response(
                status=404, success=0,
                errormsg=gettext(
                    "Please specify input data for which you wish to "
                    "create the alert."
                )
            )

        object_exist, msg = is_object_exists(self.conn, 'index', server_id,
                                             database_name, schema_name,
                                             object_name)
        if not object_exist:
            return make_json_response(
                status=404, success=0, errormsg=msg
            )

        if 'send_trap' in data and data['send_trap'] is True and \
                'snmp_trap_version' in data and \
                request.blueprint in ['v1_api', 'v2_api'] and \
                not isinstance(data['snmp_trap_version'], bool):
            return make_json_response(
                status=404, success=0,
                errormsg=gettext("Invalid SNMP trap version value")
            )

        # Check for duplicate alert name
        status, alerts = utils.get_alerts(
            DashboardLevel.DB_INDEX, server_id, database_name,
            schema_name, object_name, pem_conn=self.conn
        )
        if not status:
            return internal_server_error(errormsg=alerts)

        if len(alerts['rows']) > 0 and 'alert_name' in data:
            for a_param in alerts['rows']:
                if a_param['alert_name'] == data['alert_name']:
                    return make_json_response(
                        status=404, success=0,
                        errormsg=gettext(
                            "The specified alert name already exists."
                        )
                    )

        # Create the node information to create the new alert.
        node_info = {
            'target_type_id': DashboardLevel.DB_INDEX,
            'server_id': server_id,
            'database_name': database_name,
            'schema_name': schema_name,
            'object_name': object_name
        }
        data = transform_snmp_version_value(data, request)

        # remove any unwanted params passed which are not applicable for
        # current api version.
        data = self.discard_unwanted_params(data)

        # First validate all input parameters
        status, result = utils.validate_insert_params(
            DashboardLevel.DB_INDEX, data, self.is_edb, self.conn
        )
        if not status:
            return bad_request(result)

        self.conn.execute_void('BEGIN')
        status, result = utils.insert_alert(data, node_info, self.conn)
        if not status:
            self.conn.execute_void('ROLLBACK')
            return internal_server_error(errormsg=result)

        if result:
            wh_status, wh_result = insert_webhook_alert_config(
                result, data, self.conn)
            if not wh_status:
                self.conn.execute_void('ROLLBACK')
                return internal_server_error(errormsg=wh_result)
        self.conn.execute_void('COMMIT')

        return success_return(message=gettext('Alert created successfully.'))


class SequenceConfigApiV5View(SequenceConfigApiView):
    """
    API to expose the configuration of the alerts at sequence level.
    """

    endpoint = 'sequence_alert_config'

    # Api version from v5 till latest
    # ['v5_api', 'v6_api', 'v7_api', 'v8_api']
    api_versions = api_versions_v5

    def __init__(self, *args, **kwargs):
        super(SequenceConfigApiView, self).__init__(*args, **kwargs)
        # from v11 onwards use v11_params else v5_params
        self.params = frozenset(
            v11_params) if request.blueprint in api_versions_v5[6:] \
            else frozenset(v5_params)

    @check_precondition
    def put(self, server_id, database_name, schema_name,
            object_name, alert_id=None):
        """
        This function will update the alert for specified
        server, database, schema and sequence.

        :param server_id: Server Id for which alerts will be fetched.
        :param database_name: Database Name for which alerts will be fetched.
        :param schema_name: Schema Name for which alerts will be fetched.
        :param object_name: Table Name for which alerts will be fetched.
        :param alert_id: Alert Id for which information will be fetched.

        Input Data: Below are the json input format required to update
        alert.

        Below are required data type for each input parameters.
        "alert_name": string,
        "alert_template": string, ( positive integer values. )
        "low_threshold_value": string, ( integer/float values. )
        "medium_threshold_value": string, ( integer/float values. )
        "high_threshold_value": string, (  integer/float values. )
        "history_retention": string, ( Possible values 1-99999 )
        "enabled": string, ( Possible values true and false)
        "frequency_min": string ( Possible values 1-65534 )
        "operator": string ( Valid string are ">" and "<")
        "params": list of dict values.

        Example input data as below.
        {
          "alert_name":"alert_name",
          "alert_template": "180",
          "low_threshold_value": "1",
          "medium_threshold_value": "2",
          "high_threshold_value": "3",
          "history_retention": 32,
          "enabled": true,
          "frequency_min": 11,
          "operator": ">",
          "params":
          {
            "changed": [
              {
                "paramvalue": "7",
                "paramname": "param_1"
              }
            ]
          }
        }

        :return:

        Below is the expected result.

        status: 200 OK
        {
          "success":1,
          "info":"Alert updated successfully.",
          "result":null,
          "errormsg":"",
          "data":null
        }

        """

        data = request.get_json()
        if data is None:
            return make_json_response(
                status=404, success=0,
                errormsg=gettext(
                    "Please specify input data for which you wish to "
                    "update the alert parameters."
                )
            )

        object_exist, msg = is_object_exists(self.conn, 'sequence', server_id,
                                             database_name, schema_name,
                                             object_name)
        if not object_exist:
            return make_json_response(
                status=404, success=0, errormsg=msg
            )

        # First check alert id exists or not.
        if alert_id is None:
            return make_json_response(
                status=404, success=0,
                errormsg=gettext(
                    "Please specify alert id for which you wish to "
                    "update the alert parameters."
                )
            )

        if 'send_trap' in data and data['send_trap'] is True and \
                'snmp_trap_version' in data and \
                request.blueprint in ['v1_api', 'v2_api'] and \
                not isinstance(data['snmp_trap_version'], bool):
            return make_json_response(
                status=404, success=0,
                errormsg=gettext("Invalid SNMP trap version value")
            )

        status, alerts = utils.get_alerts(
            DashboardLevel.DB_SEQUENCE, server_id, database_name,
            schema_name, object_name, pem_conn=self.conn, alert_id=alert_id
        )
        if not status:
            return internal_server_error(errormsg=alerts)

        if alert_id is not None and len(alerts['rows']) == 0:
            return make_json_response(
                status=404, success=0,
                errormsg=gettext(
                    "The specified alert id is not applicable for "
                    "the specified sequence"
                )
            )

        # Check for duplicate alert name
        status, alerts = utils.get_alerts(
            DashboardLevel.DB_SEQUENCE, server_id, database_name,
            schema_name, object_name, pem_conn=self.conn
        )
        if not status:
            return internal_server_error(errormsg=alerts)

        if len(alerts['rows']) > 0 and 'alert_name' in data:
            for a_param in alerts['rows']:
                if a_param['alert_name'] == data['alert_name']:
                    return make_json_response(
                        status=404, success=0,
                        errormsg=gettext(
                            "The specified alert name already exists."
                        )
                    )

        data['id'] = alert_id
        data = transform_snmp_version_value(data, request)

        # remove any unwanted params passed which are not applicable for
        # current api version.
        data = self.discard_unwanted_params(data)

        # First validate all input parameters
        status, result = \
            utils.validate_update_params(alert_id, DashboardLevel.DB_SEQUENCE,
                                         data, self.is_edb, self.conn)
        if not status:
            return bad_request(result)

        self.conn.execute_void('BEGIN')
        status, result = utils.update_alert(data, self.conn)
        if not status:
            self.conn.execute_void('ROLLBACK')
            return internal_server_error(errormsg=result)

        wh_status, wh_result = validate_update_webhook_params(data, self.conn)
        if not wh_status:
            self.conn.execute_void('ROLLBACK')
            return internal_server_error(errormsg=wh_result)

        wh_status, wh_result = update_webhook_alert_config(data, self.conn)
        if not wh_status:
            self.conn.execute_void('ROLLBACK')
            return internal_server_error(errormsg=wh_result)
        self.conn.execute_void('COMMIT')

        return success_return(message=gettext('Alert updated successfully.'))

    @check_precondition
    def post(self, server_id, database_name, schema_name,
             object_name):
        """
        This function will create the new alert for specified
        server, database, schema and sequence.

        :param server_id: Server Id for which alerts will be created.
        :param database_name: Database Name for which alerts will be created.
        :param schema_name: Schema Name for which alerts will be created.
        :param object_name: Table Name for which alerts will be created.

        Input Data: Below are the json input format required to create
        new alert.

        Below are the mandatory parameters required to create the new
        alert and input are always dict of below values.

        "alert_name", "alert_template", "low_threshold_value",
        "medium_threshold_value", "high_threshold_value",
        "frequency_min", "operator", "history_retention", "enabled".
        If alert template requires then "params"

        Below are required data type for each input parameters.
        "alert_name": string,
        "alert_template": string, ( positive integer values. )
        "low_threshold_value": string, ( integer/float values. )
        "medium_threshold_value": string, ( integer/float values. )
        "high_threshold_value": string, (  integer/float values. )
        "history_retention": string, ( Possible values 1-99999 )
        "enabled": string, ( Possible values true and false)
        "frequency_min": string ( Possible values 1-65534 )
        "operator": string ( Valid string are ">" and "<")
        "params": list of dict values.

        Example input data as below.
        {
          "alert_name":"alert_name",
          "alert_template": "180",
          "low_threshold_value": "1",
          "medium_threshold_value": "2",
          "high_threshold_value": "3",
          "history_retention": 32,
          "enabled": true,
          "frequency_min": 11,
          "operator": ">",
          "params": [
            {
              "paramvalue": "7",
              "paramname": "param_1"
            }
          ]
        }

        :return:

        Below is the expected result.

        status: 200 OK
        {
          "success":1,
          "info":"Alert created successfully.",
          "result":null,
          "errormsg":"",
          "data":null
        }

        """

        data = request.get_json()
        if data is None:
            return make_json_response(
                status=404, success=0,
                errormsg=gettext(
                    "Please specify input data for which you wish to "
                    "create the alert."
                )
            )

        object_exist, msg = is_object_exists(self.conn, 'sequence', server_id,
                                             database_name, schema_name,
                                             object_name)
        if not object_exist:
            return make_json_response(
                status=404, success=0, errormsg=msg
            )

        if 'send_trap' in data and data['send_trap'] is True and \
                'snmp_trap_version' in data and \
                request.blueprint in ['v1_api', 'v2_api'] and \
                not isinstance(data['snmp_trap_version'], bool):
            return make_json_response(
                status=404, success=0,
                errormsg=gettext("Invalid SNMP trap version value")
            )

        # Check for duplicate alert name
        status, alerts = utils.get_alerts(
            DashboardLevel.DB_SEQUENCE, server_id, database_name,
            schema_name, object_name, pem_conn=self.conn
        )
        if not status:
            return internal_server_error(errormsg=alerts)

        if len(alerts['rows']) > 0 and 'alert_name' in data:
            for a_param in alerts['rows']:
                if a_param['alert_name'] == data['alert_name']:
                    return make_json_response(
                        status=404, success=0,
                        errormsg=gettext(
                            "The specified alert name already exists."
                        )
                    )

        # Create the node information to create the new alert.
        node_info = {
            'target_type_id': DashboardLevel.DB_SEQUENCE,
            'server_id': server_id,
            'database_name': database_name,
            'schema_name': schema_name,
            'object_name': object_name
        }

        data = transform_snmp_version_value(data, request)

        # remove any unwanted params passed which are not applicable for
        # current api version.
        data = self.discard_unwanted_params(data)

        # First validate all input parameters
        status, result = \
            utils.validate_insert_params(DashboardLevel.DB_SEQUENCE, data,
                                         self.is_edb, self.conn)
        if not status:
            return bad_request(result)

        self.conn.execute_void('BEGIN')
        status, result = utils.insert_alert(data, node_info, self.conn)
        if not status:
            self.conn.execute_void('ROLLBACK')
            return internal_server_error(errormsg=result)

        if result:
            wh_status, wh_result = insert_webhook_alert_config(
                result, data, self.conn)
            if not wh_status:
                self.conn.execute_void('ROLLBACK')
                return internal_server_error(errormsg=wh_result)
        self.conn.execute_void('COMMIT')

        return success_return(message=gettext('Alert created successfully.'))


class FunctionConfigApiV5View(FunctionConfigApiView):
    """
    API to expose the configuration of the alerts at function level.
    """

    endpoint = 'function_alert_config_V5'

    # Api version from v5 till latest
    # ['v5_api', 'v6_api', 'v7_api', 'v8_api']
    api_versions = api_versions_v5

    def __init__(self, *args, **kwargs):
        super(FunctionConfigApiView, self).__init__(*args, **kwargs)
        # from v11 onwards use v11_params else v5_params
        self.params = frozenset(
            v11_params) if request.blueprint in api_versions_v5[6:] \
            else frozenset(v5_params)

    @check_precondition
    def put(self, server_id, database_name, schema_name,
            function_name, function_arguments, alert_id=None):
        """
        This function will update the alert for specified
        server, database, schema and function.

        :param server_id: Server Id for which alerts will be fetched.
        :param database_name: Database Name for which alerts will be fetched.
        :param schema_name: Schema Name for which alerts will be fetched.
        :param object_name: Table Name for which alerts will be fetched.
        :param alert_id: Alert Id for which information will be fetched.

        Input Data: Below are the json input format required to update
        alert.

        Below are required data type for each input parameters.
        "alert_name": string,
        "alert_template": string, ( positive integer values. )
        "low_threshold_value": string, ( integer/float values. )
        "medium_threshold_value": string, ( integer/float values. )
        "high_threshold_value": string, (  integer/float values. )
        "history_retention": string, ( Possible values 1-99999 )
        "enabled": string, ( Possible values true and false)
        "frequency_min": string ( Possible values 1-65534 )
        "operator": string ( Valid string are ">" and "<")
        "params": list of dict values.

        Example input data as below.
        {
          "alert_name":"alert_name",
          "alert_template": "180",
          "low_threshold_value": "1",
          "medium_threshold_value": "2",
          "high_threshold_value": "3",
          "history_retention": 32,
          "enabled": true,
          "frequency_min": 11,
          "operator": ">",
          "params":
          {
            "changed": [
              {
                "paramvalue": "7",
                "paramname": "param_1"
              }
            ]
          }
        }

        :return:

        Below is the expected result.

        status: 200 OK
        {
          "success":1,
          "info":"Alert updated successfully.",
          "result":null,
          "errormsg":"",
          "data":null
        }

        """

        data = request.get_json()
        if data is None:
            return make_json_response(
                status=404, success=0,
                errormsg=gettext(
                    "Please specify input data for which you wish to "
                    "update the alert parameters."
                )
            )

        # handling if no function arguments provided
        if function_arguments == ' ':
            function_arguments = ''

        # using re for addding space after ',' for comma separated args
        function_arguments = re.sub(
            r'(?<=[,])(?=[^\s])', r' ', function_arguments)

        object_exist, msg = is_object_exists(self.conn, 'function', server_id,
                                             database_name, schema_name,
                                             function_name,
                                             arguments=function_arguments)
        if not object_exist:
            return make_json_response(
                status=404, success=0, errormsg=msg
            )

        # First check alert id exists or not.
        if alert_id is None:
            return make_json_response(
                status=404, success=0,
                errormsg=gettext(
                    "Please specify alert id for which you wish to "
                    "update the alert parameters."
                )
            )

        if 'send_trap' in data and data[
                'send_trap'] is True and 'snmp_trap_version' in data and \
                request.blueprint in ['v1_api', 'v2_api'] and \
                not isinstance(data['snmp_trap_version'], bool):
            return make_json_response(
                status=404, success=0,
                errormsg=gettext("Invalid SNMP trap version value")
            )

        # function name with args
        function_name = "{}({})".format(function_name, function_arguments)

        status, alerts = utils.get_alerts(
            DashboardLevel.DB_FUNCTION, server_id, database_name,
            schema_name, function_name, pem_conn=self.conn, alert_id=alert_id
        )
        if not status:
            return internal_server_error(errormsg=alerts)

        if alert_id is not None and len(alerts['rows']) == 0:
            return make_json_response(
                status=404, success=0,
                errormsg=gettext(
                    "The specified alert id is not applicable for "
                    "the specified function"
                )
            )

        # Check for duplicate alert name
        status, alerts = utils.get_alerts(
            DashboardLevel.DB_FUNCTION, server_id, database_name,
            schema_name, function_name, pem_conn=self.conn
        )
        if not status:
            return internal_server_error(errormsg=alerts)

        if len(alerts['rows']) > 0 and 'alert_name' in data:
            for a_param in alerts['rows']:
                if a_param['alert_name'] == data['alert_name']:
                    return make_json_response(
                        status=404, success=0,
                        errormsg=gettext(
                            "The specified alert name already exists."
                        )
                    )

        data['id'] = alert_id
        data = transform_snmp_version_value(data, request)

        # remove any unwanted params passed which are not applicable for
        # current api version.
        data = self.discard_unwanted_params(data)

        # First validate all input parameters
        status, result = \
            utils.validate_update_params(alert_id, DashboardLevel.DB_FUNCTION,
                                         data, self.is_edb, self.conn)
        if not status:
            return bad_request(result)

        self.conn.execute_void('BEGIN')
        status, result = utils.update_alert(data, self.conn)
        if not status:
            self.conn.execute_void('ROLLBACK')
            return internal_server_error(errormsg=result)

        wh_status, wh_result = validate_update_webhook_params(data, self.conn)
        if not wh_status:
            self.conn.execute_void('ROLLBACK')
            return internal_server_error(errormsg=wh_result)

        wh_status, wh_result = update_webhook_alert_config(data, self.conn)
        if not wh_status:
            self.conn.execute_void('ROLLBACK')
            return internal_server_error(errormsg=wh_result)
        self.conn.execute_void('COMMIT')

        return success_return(message=gettext('Alert updated successfully.'))

    @check_precondition
    def post(self, server_id, database_name, schema_name,
             function_name, function_arguments):
        """
        This function will create new alert for specified
        server, database, schema and function.

        :param server_id: Server Id for which alerts will be created.
        :param database_name: Database Name for which alerts will be created.
        :param schema_name: Schema Name for which alerts will be created.
        :param object_name: Table Name for which alerts will be created.

        Input Data: Below are the json input format required to create
        new alert.

        Below are the mandatory parameters required to create the new
        alert and input are always dict of below values.

        "alert_name", "alert_template", "low_threshold_value",
        "medium_threshold_value", "high_threshold_value",
        "frequency_min", "operator", "history_retention", "enabled".
        If alert template requires then "params"

        Below are required data type for each input parameters.
        "alert_name": string,
        "alert_template": string, ( positive integer values. )
        "low_threshold_value": string, ( integer/float values. )
        "medium_threshold_value": string, ( integer/float values. )
        "high_threshold_value": string, (  integer/float values. )
        "history_retention": string, ( Possible values 1-99999 )
        "enabled": string, ( Possible values true and false)
        "frequency_min": string ( Possible values 1-65534 )
        "operator": string ( Valid string are ">" and "<")
        "params": list of dict values.

        Example input data as below.
        {
          "alert_name":"alert_name",
          "alert_template": "180",
          "low_threshold_value": "1",
          "medium_threshold_value": "2",
          "high_threshold_value": "3",
          "history_retention": 32,
          "enabled": true,
          "frequency_min": 11,
          "operator": ">",
          "params": [
            {
              "paramvalue": "7",
              "paramname": "param_1"
            }
          ]
        }

        :return:

        Below is the expected result.

        status: 200 OK
        {
          "success":1,
          "info":"Alert created successfully.",
          "result":null,
          "errormsg":"",
          "data":null
        }

        """

        data = request.get_json()
        if data is None:
            return make_json_response(
                status=404, success=0,
                errormsg=gettext(
                    "Please specify input data for which you wish to "
                    "create the alert."
                )
            )

        # handling if no function arguments provided
        if function_arguments == ' ':
            function_arguments = ''

        # using re for addding space after ',' for comma separated args
        function_arguments = re.sub(
            r'(?<=[,])(?=[^\s])', r' ', function_arguments)

        object_exist, msg = is_object_exists(self.conn, 'function', server_id,
                                             database_name, schema_name,
                                             function_name,
                                             arguments=function_arguments)
        if not object_exist:
            return make_json_response(
                status=404, success=0, errormsg=msg
            )

        if 'send_trap' in data and data[
                'send_trap'] is True and 'snmp_trap_version' in data and \
                request.blueprint in ['v1_api', 'v2_api'] and \
                not isinstance(data['snmp_trap_version'], bool):
            return make_json_response(
                status=404, success=0,
                errormsg=gettext("Invalid SNMP trap version value")
            )

        # Check for duplicate alert name
        status, alerts = utils.get_alerts(
            DashboardLevel.DB_FUNCTION, server_id, database_name,
            schema_name, function_name, pem_conn=self.conn
        )
        if not status:
            return internal_server_error(errormsg=alerts)

        if len(alerts['rows']) > 0 and 'alert_name' in data:
            for a_param in alerts['rows']:
                if a_param['alert_name'] == data['alert_name']:
                    return make_json_response(
                        status=404, success=0,
                        errormsg=gettext(
                            "The specified alert name already exists."
                        )
                    )

        # function name with args
        function_name = "{}({})".format(function_name, function_arguments)

        # Create the node information to create the new alert.
        node_info = {
            'target_type_id': DashboardLevel.DB_FUNCTION,
            'server_id': server_id,
            'database_name': database_name,
            'schema_name': schema_name,
            'object_name': function_name
        }
        data = transform_snmp_version_value(data, request)

        # remove any unwanted params passed which are not applicable for
        # current api version.
        data = self.discard_unwanted_params(data)

        # First validate all input parameters
        status, result = \
            utils.validate_insert_params(DashboardLevel.DB_FUNCTION, data,
                                         self.is_edb, self.conn)
        if not status:
            return bad_request(result)
        self.conn.execute_void('BEGIN')
        status, result = utils.insert_alert(data, node_info, self.conn)
        if not status:
            return internal_server_error(errormsg=result)

        if result:
            wh_status, wh_result = insert_webhook_alert_config(
                result, data, self.conn)
            if not wh_status:
                self.conn.execute_void('ROLLBACK')
                return internal_server_error(errormsg=wh_result)
        self.conn.execute_void('COMMIT')

        return success_return(message=gettext('Alert created successfully.'))
