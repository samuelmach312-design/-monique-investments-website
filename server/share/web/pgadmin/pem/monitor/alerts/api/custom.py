##########################################################################
#
# Postgres Enterprise Manager
#
# Copyright (C) 2016 - 2025, EnterpriseDB Corporation. All rights reserved.
#
##########################################################################

"""Alert template API"""

from pgadmin.pem.api.utils import ApiView
from pgadmin.utils.ajax import make_response, make_json_response, \
    internal_server_error, precondition_required, success_return, \
    bad_request, forbidden
from flask_babel import gettext
from flask import render_template, request
from pgadmin.pem.utils import get_sql_placeholders
from pgadmin.pem.monitor.alerts.custom import update_custom_alert, \
    validate_update_template_params, insert_custom_alert, \
    validate_insert_template_params
from functools import wraps
api_versions_v2 = list(ApiView.api_versions)[1:]


class AlertTemplateApiV1View(ApiView):
    """
    This class provide APIs to configure the alerts templates.
    """

    endpoint = 'alert_template_config_V1'
    url = '/alert/template/'
    pk = 'alert_template_id'
    conn = None
    template_path = None
    is_edb = 0
    api_versions = ['v1_api']

    def __init__(self, *args, **kwargs):
        super(ApiView, self).__init__(*args, **kwargs)
        self.params = frozenset(["description", "applicable_on_server", "sql",
                                 "default_history_retention",
                                 "is_system_template", "probe_dependency_list",
                                 "name", "param_types", "threshold_unit",
                                 "object_type", "default_check_frequency",
                                 "param_names", "param_units", "id"])

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
            self.is_edb = 0

            # Set the template path for sql scripts
            self.template_path = 'alerts/sql/custom_alert'

            return f(self, *args, **kwargs)
        return wrap

    def _get_custom_alerts(self, alert_template_id):
        """
        Get the custom alert template properties for the given id.

        :return:
        List of alert properties for the given template-id
        (when template-id is not None)

        List of alert properties of all the custom alerts
        (when template-id is None)
        """
        sql = render_template(
            "/".join([self.template_path, 'list.sql']),
            show_all_templates=True,
            alert_template_id=alert_template_id
        )

        try:
            status, custom_alerts = self.conn.execute_dict(sql)

            if not status:
                return None, internal_server_error(errormsg=custom_alerts)

        except Exception as e:
            return None, internal_server_error(e)

        if alert_template_id is not None and len(custom_alerts['rows']) == 0:
            return custom_alerts['rows'], make_json_response(
                status=404, success=0,
                errormsg=gettext(
                    "The specified alert template id is not available")
            )

        return custom_alerts['rows'], None

    @check_precondition
    def get(self, alert_template_id=None):
        """
        This function will return the list of alert templates.

        :param alert_template_id: Alert template Id for which information
        will be fetched.

        Method: GET
        URL: /api/v1/alert/template
        DESCRIPTION: All the alert templates will be returned.

        Method: GET
        URL: /api/v1/alert/template/1
        DESCRIPTION: Alert templates with id 1 will be returned.

        Input Data:
        Valid alert template id to delete the alert template.

        e.g.
        /api/v1/alert/template

        :return:
        [
          {"id":232,"default_check_frequency":1,"sql":"SELECT 1;
            "object_type":"100", .....},
          {"id":232,"default_check_frequency":1,"sql":"SELECT 1;
            "object_type":"100", .....},
          ...
        ]

        e.g.
        /api/v1/alert/template/1

        :return:
        [
          {"id":232,"default_check_frequency":1,"sql":"SELECT 1;
            "object_type":"100", .....}
        ]

        """
        custom_alerts, error_response = self._get_custom_alerts(
            alert_template_id
        )

        if error_response is not None:
            return error_response

        # Remove any unwanted params passed which are not applicable for
        # current api version.
        res = []
        for row in custom_alerts:
            res.append(self.discard_unwanted_params(row))

        return make_response(res)

    @check_precondition
    def delete(self, alert_template_id):
        """
        This function will delete the alert template. if alert template id is
        system template then it cannot be deleted.

        :param alert_template_id: Alert template Id for which information
        will be deleted.

        Method: DELETE
        URL: /api/v1/alert/template/<alert_template_id>

        Input Data:
        Valid alert template id to delete the alert template.

        e.g.
        /api/v1/alert/template/234

        :return:

        Below is the expected result.

        status: 200 OK
        {
          "success":1,
          "info":"Alert template deleted successfully.",
          "result":null,
          "errormsg":"",
          "data":null
        }

        """
        # First check alert id exists or not.
        if alert_template_id <= 0:
            return make_json_response(
                status=404, success=0,
                errormsg=gettext("Invalid alert template id.")
            )

        custom_alerts, error_response = self._get_custom_alerts(
            alert_template_id
        )

        if error_response is not None:
            return error_response

        # If alert template id is not specified then return error.
        if alert_template_id is not None and len(custom_alerts) == 0:
            return make_json_response(
                status=404, success=0,
                errormsg=gettext(
                    "The specified alert template id is not available."
                )
            )

        # If alert template is system template then return error.
        if custom_alerts[0]['is_system_template']:
            return forbidden(
                gettext("The system alert template cannot be deleted.")
            )

        sql = render_template(
            "/".join([self.template_path, 'delete.sql']),
            placeholders=get_sql_placeholders([alert_template_id])
        )

        try:
            alert_template_ids = list()
            alert_template_ids.append(alert_template_id)

            status, result = \
                self.conn.execute_void(sql, alert_template_ids)

            if not status:
                return internal_server_error(result)

        except Exception as e:
            return internal_server_error(e)

        return success_return(message=gettext(
            'Alert template deleted successfully.')
        )

    @check_precondition
    def put(self, alert_template_id):
        """
        This function will update alert template parameters.

        :param alert_template_id: Alert template Id for which template
        information will be updated.

        Method: PUT
        URL: /api/v1/alert/template/<alert_template_id>

        Below are data type for each input parameters.

        "name": string,
        "object_type": string, ( Enum type, possible values are as below.
                                 50,100.200,300,400,500,600,700,800 )
        "description": string,
        "sql": string,
        "applicable_on_server": string ( Possible values are as below
                                       "ALL",
                                       "POSTGRES_SERVER",
                                       "ADVANCED_SERVER" )
        "default_check_frequency": string ( Possible values 1-65534 )
        "default_history_retention": string ( Possible values 1-99999 )
        "probe_dependency_list": list of dict values.
        "params": list of dict values.

        Input Data: Below are the json input format required to update
        existing alert template.

        {
          "name":"template_name",
          "sql": "SELECT 1;",
          "applicable_on_server":"ALL",
          "default_check_frequency":"123",
          "default_history_retention":"32",
          "probe_dependency_list":
          {
            "deleted": [
              {
                "internal_name": "cpu_usage",
                "display_name": "Cpu Usage"
              }
            ],
            "added": [
              {
                "internal_name": "database_frozen xid",
                "display_name": "Database Frozen XID"
              }
            ]
          },
          "params":
          {
            "added": [
              {
                "param_names": "1",
                "param_types": "STRING",
                "param_units": "KB"
              },
              {
                "param_names": "12",
                "param_types": "INTEGER",
                "param_units": "MB"
              }
            ],
            "changed": [
              {
                "param_names": "12",
                "param_types": "INTEGER",
                "param_units": "MB"
              }
            ],
            "deleted": [
              {
                "param_names": "12",
                "param_types": "INTEGER",
                "param_units": "MB"
              }
            ]
          }
        }

        :return:

        Below is the expected result.

        status: 200 OK
        {
          "success":1,
          "info":"Alert template updated successfully.",
          "result":null,
          "errormsg":"",
          "data":null
        }

        """
        # First check alert template id exists or not.
        if alert_template_id <= 0 or alert_template_id is None:
            return make_json_response(
                status=404, success=0,
                errormsg=gettext("Invalid alert template id.")
            )

        data = request.get_json()

        if data is None:
            return make_json_response(
                status=400, success=0,
                errormsg=gettext(
                    "Please specify input data for which you wish to "
                    "update the alert template."
                )
            )

        # remove any unwanted params passed which are not applicable for
        # current api version.
        data = self.discard_unwanted_params(data)

        custom_alerts, error_response = self._get_custom_alerts(
            alert_template_id
        )

        if error_response is not None:
            return error_response

        # check if probe exists which are provided in probe dependency
        status, result = self.conn.execute_2darray(
            'select internal_name from pem.probe')
        if not status:
            return bad_request(result)
        existing_probes = [value[0] for value in result['rows']]
        if 'probe_dependency_list' in data:
            probe_dep_arr = data['probe_dependency_list']['added'][:] \
                if 'added' in data['probe_dependency_list'] else []
            if 'deleted' in data['probe_dependency_list']:
                probe_dep_arr += data['probe_dependency_list']['deleted']
            for probe in [value['internal_name'] for value in probe_dep_arr]:
                if probe not in existing_probes:
                    return make_json_response(
                        status=404, success=0,
                        errormsg=gettext(
                            f"The specified probe '{probe}' is not available."
                        )
                    )

            # formating the data to include display_name if not provided
            # Todo: display name not required but still being validated
            # hence adding dummy value if not present
            # need to fix this but removing the dependency of display name
            # might affect some other functionality hence handling
            if 'added' in data['probe_dependency_list']:
                for row in data['probe_dependency_list']['added']:
                    if 'display_name' not in row:
                        row['display_name'] = '_'

            if 'deleted' in data['probe_dependency_list']:
                for row in data['probe_dependency_list']['deleted']:
                    if 'display_name' not in row:
                        row['display_name'] = '_'

        # If alert template id is not specified then return error.
        if len(custom_alerts) == 0:
            return make_json_response(
                status=404, success=0,
                errormsg=gettext(
                    "The specified alert template id is not available."
                )
            )

        # If alert template is system template then return error.
        if custom_alerts[0]['is_system_template'] is True:
            return forbidden(gettext(
                "The system alert template cannot be modified."
            ))
        # Cannot modify the object type of alert template.
        if 'object_type' in data:
            return forbidden(gettext(
                "Alert template target type cannot be modified."
            ))

        org_data = custom_alerts
        data['id'] = alert_template_id

        # First validate all input parameters
        status, result = validate_update_template_params(
            data, pem_conn=self.conn
        )

        if not status:
            return bad_request(result)

        # Update all input parameters
        status, result = update_custom_alert(data, org_data,
                                             pem_conn=self.conn)
        if not status:
            return internal_server_error(errormsg=result)

        return success_return(message=gettext(
            'Alert template updated successfully.')
        )

    @check_precondition
    def post(self):
        """
        This function will create new alert template.

        Method: POST
        URL: /api/v1/alert/template

        Input Data: Below are the json input format required to create
        new alert template.

        Below are the mandatory parameters required to create the new
        custom alert template and input are always dict of below values.

        "name", "object_type", "description", "sql", "applicable_on_server",
        "default_check_frequency", "default_history_retention"

        Below are required data type for each input parameters.
        "name": string,
        "object_type": string, ( Enum type, possible values are as below.
                                 50,100.200,300,400,500,600,700,800 )
        "description": string,
        "sql": string,
        "applicable_on_server": string ( Possible values are as below
                                       "ALL",
                                       "POSTGRES_SERVER",
                                       "ADVANCED_SERVER" )
        "default_check_frequency": string ( Possible values 1-65534 )
        "default_history_retention": string ( Possible values 1-99999 )
        "probe_dependency_list": list of dict values.
        "params": list of dict values.

        Example input data as below.
        {
          "name":"alert_template_name",
          "object_type": "200",
          "description": "Alert template description",
          "sql": "SELECT 1;",
          "applicable_on_server":"ALL",
          "default_check_frequency":"123",
          "default_history_retention":"32",
          "probe_dependency_list": [
            {
              "internal_name": "cpu_usage",
              "display_name": "CPU Usage"
            }
          ],
          "params": [
            {
              "param_types": "STRING",
              "param_units": "KK",
              "param_names": "param__1"
            }
          ]
        }

        :return:

        Below is the expected result.

        status: 200 OK
        {
          "success":1,
          "info":"Alert template created successfully.",
          "result":null,
          "errormsg":"",
          "data":null
        }

        """

        data = request.get_json()
        if data is None:
            return make_json_response(
                status=400, success=0,
                errormsg=gettext(
                    "Please specify input data for which you wish to "
                    "create the alert template."
                )
            )

        # remove any unwanted params passed which are not applicable for
        # current api version.
        data = self.discard_unwanted_params(data)

        # check if probe exists which are provided in probe dependency
        status, result = self.conn.execute_2darray(
            'select internal_name from pem.probe')
        if not status:
            return bad_request(result)
        existing_probes = [value['internal_name'] for value in result['rows']]
        if 'probe_dependency_list' in data:
            probe_dep_arr = data['probe_dependency_list'][:]
            for probe in [value['internal_name'] for value in probe_dep_arr]:
                if probe not in existing_probes:
                    return make_json_response(
                        status=404, success=0,
                        errormsg=gettext(
                            f"The specified probe '{probe}' is not available."
                        )
                    )

            # formating the data to include display_name if not provided
            # Todo: display name not required but still being validated
            # hence adding dummy value if not present
            # need to fix this but removing the dependency of display name
            # might affect some other functionality hence handling
            for row in data['probe_dependency_list']:
                if 'display_name' not in row:
                    row['display_name'] = '_'

        # First validate all input parameters
        status, result = validate_insert_template_params(data,
                                                         pem_conn=self.conn)
        if not status:
            return bad_request(result)

        status, result = insert_custom_alert(data, pem_conn=self.conn)
        if not status:
            return internal_server_error(errormsg=result)

        return success_return(message=gettext(
            'Alert template created successfully.')
        )


class AlertTemplateApiV2View(AlertTemplateApiV1View):
    """
    This class provide APIs to configure the alerts templates.
    """

    endpoint = 'alert_template_config_V2'
    api_versions = api_versions_v2

    def __init__(self, *args, **kwargs):
        super(AlertTemplateApiV1View, self).__init__(*args, **kwargs)
        self.params = frozenset([
            "description", "applicable_on_server", "sql",
            "default_history_retention", "is_system_template",
            "probe_dependency_list", "name", "param_types", "threshold_unit",
            "object_type", "default_check_frequency", "param_names",
            "param_units", "id", "is_auto_create", "thresholds", "operator",
            "high_threshold_value", "medium_threshold_value", "info_sql",
            "low_threshold_value","params"
        ])
