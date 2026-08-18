##########################################################################
#
# Postgres Enterprise Manager
#
# Copyright (C) 2016 - 2025, EnterpriseDB Corporation. All rights reserved.
#
##########################################################################

"""Alert Template Import Export API"""

from pgadmin.pem.api.utils import ApiView
from functools import wraps

import json
from flask import request, Response
from flask_babel import gettext
from pgadmin.utils.ajax import internal_server_error, make_json_response, \
    make_response, precondition_required, bad_request
from pgadmin.pem.monitor.utils.import_export import CURRENT_EXPORT_VERSION, \
    get_pem_installation_id, is_export_version_supported, \
    get_import_schema_version
from pgadmin.pem.monitor.alerts.utils import generate_export_alert_data
from pgadmin.pem.monitor.alerts.custom import insert_imported_alerts, \
    validate_insert_template_params


v6_export_req_params = ['alert_templates']
v6_import_req_params = ['alert_templates', 'skip_overwrite',
                        'skip_overwrite_probe', 'version']
api_versions_v6 = list(ApiView.api_versions)[5:]


class AlertTemplateExportApiView(ApiView):
    """
    This class provide APIs to exports probe in JSON format.
    """

    endpoint = 'custom_alert_export'
    url = '/alert/custom/export/'

    # Api version from v6 till latest
    # ['v6_api', 'v7_api', 'v8_api']
    api_versions = api_versions_v6
    methods = ['POST']

    def __init__(self, *args, **kwargs):
        super(ApiView, self).__init__(*args, **kwargs)
        self.req_params = v6_export_req_params

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

            # Set the template path for sql scripts
            self.template_path = 'alerts/sql/custom_alert'

            return f(self, *args, **kwargs)
        return wrap

    @check_precondition
    def post(self):
        """
        This function will export all the requested alerts in the JSON

        Method: POST
        URL: /api/v6/alert/custom/export/

        Input Data: List of custom alert template ids [integers]

        Example input data as below.
        {
            alert_templates: [101,...]
        }

        :return:

        Below is the expected result.

        status: 200 OK
        {
           "version":1,
           "alert_templates":[
              {
                 "name":"test-1",
                 "description":"New Test",
                 "reference_id":"template_1627468667181042519653_245",
                 "sql":"Select 1;",
                 "info_sql":"Select 1;",
                 "object_type":"200",
                 "param_names":null,
                 "param_types":null,
                 "param_units":null,
                 "default_check_frequency":1,
                 "default_history_retention":30,
                 "probe_dependency_list":[
                    {
                       "display_name":"Background Writer Statistics",
                       "internal_name":"background_writer_statistics"
                    }
                 ],
                 "applicable_on_server":"ALL",
                 "is_auto_create":false,
                 "operator":">",
                 "thresholds":null,
                 "low_threshold_value":null,
                 "medium_threshold_value":null,
                 "high_threshold_value":null,
                 "threshold_unit":"",
                 "params":[

                 ],
                 "probes":[
                    {
                       "probe_name":"Background Writer Statistics",
                       "internal_name":"background_writer_statistics",
                       "collection_method":"s",
                       "target_type":"200",
                       "enabled":true,
                       "interval":300,
                       "lifetime":180,
                       "probe_code":"SELECT checkpoints_timed,
                       checkpoints_req, buffers_clean, buffers_checkpoint,
                       maxwritten_clean, buffers_backend, buffers_alloc
                       FROM pg_catalog.pg_stat_bgwriter",
                       "any_server_version":false,
                       "discard_history":false,
                       "platform":"*nix",
                       "probe_columns":[
                          {
                             "pc_name":"Checkpoints - Timed",
                             "pc_internal_name":"checkpoints_timed",
                             "pc_position":1,
                             "pc_col_type":"m",
                             "pc_data_type":"bigint",
                             "pc_unit":"#",
                             "pc_graphable":true,
                             "pc_pit_default":false,
                             "pc_calc_pit":true
                          },
                          {
                             "pc_name":"Checkpoints - Untimed",
                             "pc_internal_name":"checkpoints_req",
                             "pc_position":2,
                             "pc_col_type":"m",
                             "pc_data_type":"bigint",
                             "pc_unit":"#",
                             "pc_graphable":true,
                             "pc_pit_default":false,
                             "pc_calc_pit":true
                          },
                       ],
                       "alternate_code":[
                          {
                             "server_version_id":"21200",
                             "server_probe_code":null
                          },
                          {
                             "server_version_id":"21300",
                             "server_probe_code":null
                          }
                       ]
                    }
                 ]
              }
           ]
        }
        """
        data = request.get_json()
        pem_conn = self.conn

        alert_list = data.get('alert_templates', [])
        if len(alert_list) == 0:
            return bad_request(
                errormsg=gettext("No alerts to export")
            )
        status, result = generate_export_alert_data(pem_conn, alert_list)
        if not status:
            return internal_server_error(errormsg=result)

        resp = Response(
            json.dumps({
                "version": CURRENT_EXPORT_VERSION,
                "alert_templates": result
            }),
            mimetype='application/json'
        )
        return resp


class AlertTemplateImportApiView(ApiView):
    """
    This class provide APIs to exports alert in JSON format.
    """

    endpoint = 'custom_alert_import'
    url = '/alert/custom/import/'

    # Api version from v6 till latest
    # ['v6_api', 'v7_api', 'v8_api']
    api_versions = api_versions_v6
    methods = ['POST']

    def __init__(self, *args, **kwargs):
        super(ApiView, self).__init__(*args, **kwargs)
        self.req_params = v6_import_req_params

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

            # Set the template path for sql scripts
            self.template_path = 'alerts/sql/custom_alert'

            return f(self, *args, **kwargs)
        return wrap

    @check_precondition
    def post(self):
        """
        This function will import all the requested alerts into the PEM

        Method: POST
        URL: /api/v6/alert/custom/import/

        Input Data: List of custom alerts which are exported by an alert
        export api.

        Example input data as below.
        {
           "version":1,
           "alert_templates":[
              {
                 "name":"test-1",
                 "description":"New Test",
                 "reference_id":"template_1627468667181042519653_245",
                 "sql":"Select 1;",
                 "info_sql":"Select 1;",
                 "object_type":"200",
                 "param_names":null,
                 "param_types":null,
                 "param_units":null,
                 "default_check_frequency":1,
                 "default_history_retention":30,
                 "probe_dependency_list":[
                    {
                       "display_name":"Background Writer Statistics",
                       "internal_name":"background_writer_statistics"
                    }
                 ],
                 "applicable_on_server":"ALL",
                 "is_auto_create":false,
                 "operator":">",
                 "thresholds":null,
                 "low_threshold_value":null,
                 "medium_threshold_value":null,
                 "high_threshold_value":null,
                 "threshold_unit":"",
                 "params":[

                 ],
                 "probes":[
                    {
                       "probe_name":"Background Writer Statistics",
                       "internal_name":"background_writer_statistics",
                       "collection_method":"s",
                       "target_type":"200",
                       "enabled":true,
                       "interval":300,
                       "lifetime":180,
                       "probe_code":"SELECT checkpoints_timed,
                       checkpoints_req, buffers_clean, buffers_checkpoint,
                       maxwritten_clean, buffers_backend, buffers_alloc
                       FROM pg_catalog.pg_stat_bgwriter",
                       "any_server_version":false,
                       "discard_history":false,
                       "platform":"*nix",
                       "probe_columns":[
                          {
                             "pc_name":"Checkpoints - Timed",
                             "pc_internal_name":"checkpoints_timed",
                             "pc_position":1,
                             "pc_col_type":"m",
                             "pc_data_type":"bigint",
                             "pc_unit":"#",
                             "pc_graphable":true,
                             "pc_pit_default":false,
                             "pc_calc_pit":true
                          },
                          {
                             "pc_name":"Checkpoints - Untimed",
                             "pc_internal_name":"checkpoints_req",
                             "pc_position":2,
                             "pc_col_type":"m",
                             "pc_data_type":"bigint",
                             "pc_unit":"#",
                             "pc_graphable":true,
                             "pc_pit_default":false,
                             "pc_calc_pit":true
                          },
                       ],
                       "alternate_code":[
                          {
                             "server_version_id":"21200",
                             "server_probe_code":null
                          },
                          {
                             "server_version_id":"21300",
                             "server_probe_code":null
                          }
                       ]
                    }
                 ]
              }
           ]
        }

        :return:

        Below is the expected result.
        status: 200 OK
        {
          "success":1,
          "errormsg":"",
          "info":"",
          "result":[
            {
              "name":"test-1",
              "status":"Success/Skipped/Failed",
              "msg":null
            }
          ],
          "data":null
        }
        """
        data = request.get_json()
        pem_conn = self.conn

        # Verify the request
        if 'alert_templates' not in data or \
                type(data['alert_templates']) != list or \
                len(data['alert_templates']) == 0:
            return bad_request(
                errormsg=gettext("Please provide valid JSON data")
            )

        if 'skip_overwrite' not in data or \
                'skip_overwrite_probe' not in data:
            return bad_request(
                errormsg=gettext("skip_overwrite or skip_overwrite_probe not "
                                 "provided")
            )

        # Check if export version is supported
        if 'version' not in data or not data['version']:
            return bad_request(
                errormsg=gettext("Unable to verify the export version")
            )

        if not is_export_version_supported(data['version']):
            return bad_request(
                errormsg=gettext(
                    "The JSON file is incompatible with current version of"
                    " PEM, the import is supported from following"
                    " schema version(s) - {}".format(", ".join(
                        str(sv) for sv in
                        get_import_schema_version(CURRENT_EXPORT_VERSION)
                    ))
                )
            )
        skip_overwrite = data['skip_overwrite']
        skip_overwrite_probe = data['skip_overwrite_probe']

        # Verify the inputs first
        for alert in data['alert_templates']:
            status, msg = validate_insert_template_params(
                alert, pem_conn)
            if not status:
                return bad_request(errormsg=msg)

        result = insert_imported_alerts(
            pem_conn, data['alert_templates'], skip_overwrite,
            skip_overwrite_probe
        )
        return make_json_response(result=result)
