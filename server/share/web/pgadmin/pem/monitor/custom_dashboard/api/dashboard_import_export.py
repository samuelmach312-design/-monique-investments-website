##########################################################################
#
# Postgres Enterprise Manager
#
# Copyright (C) 2016 - 2025, EnterpriseDB Corporation. All rights reserved.
#
##########################################################################

"""Dashboard Import Export API"""

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
from pgadmin.pem.monitor.custom_dashboard.utils import \
    insert_imported_dashboards, generate_export_dashboard_data


api_versions_v7 = list(ApiView.api_versions)[6:]
v7_export_req_params = ['dashboards']
v7_import_req_params = ['dashboards', 'skip_overwrite',
                        'skip_overwrite_chart',
                        'skip_overwrite_probe', 'version']


class DashboardExportApiView(ApiView):
    """
    This class provide APIs to exports dashboard in JSON format.
    """

    endpoint = 'custom_dashboard_export'
    url = '/dashboard/custom/export/'

    # Api version from v7 till latest
    # ['v7_api', 'v8_api']
    api_versions = api_versions_v7
    methods = ['POST']

    def __init__(self, *args, **kwargs):
        super(ApiView, self).__init__(*args, **kwargs)
        self.req_params = v7_export_req_params

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
            self.template_path = 'manage/sql'

            return f(self, *args, **kwargs)
        return wrap

    @check_precondition
    def post(self):
        """
        This function will export all the requested charts in the JSON

        Method: POST
        URL: /api/v7/dashboard/custom/export/

        Input Data: List of custom dashboard ids [integers]

        Example input data as below.
        {
            charts: [101,...]
        }

        :return:

        Below is the expected result.

        status: 200 OK
        {
          "version":1,
          "dashboards":[
            {}
            }
          ]
        }
        """
        data = request.get_json()
        pem_conn = self.conn

        dashboards = data.get('dashboards', [])
        if len(dashboards) == 0:
            return bad_request(
                errormsg=gettext("No dashboards to export")
            )
        status, result = generate_export_dashboard_data(pem_conn, dashboards)
        if not status:
            return internal_server_error(errormsg=result)

        resp = Response(
            json.dumps({
                "version": CURRENT_EXPORT_VERSION,
                "dashboards": result
            }),
            mimetype='application/json'
        )
        return resp


class DashboardImportApiView(ApiView):
    """
    This class provide APIs to import dashboard in JSON format.
    """

    endpoint = 'custom_dashboard_import'
    url = '/dashboard/custom/import/'

    # Api version from v7 till latest
    # ['v7_api', 'v8_api']
    api_versions = api_versions_v7
    methods = ['POST']

    def __init__(self, *args, **kwargs):
        super(ApiView, self).__init__(*args, **kwargs)
        self.req_params = v7_import_req_params

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
            self.template_path = 'manage/sql'

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
          "charts":[
            {}
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
        if 'dashboards' not in data or \
                type(data['dashboards']) != list or \
                len(data['dashboards']) == 0 or \
                'skip_overwrite' not in data or \
                'skip_overwrite_chart' not in data or \
                'skip_overwrite_probe' not in data:
            return bad_request(
                errormsg=gettext("Please provide valid JSON data")
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
        skip_overwrite_chart = data['skip_overwrite_chart']
        skip_overwrite_probe = data['skip_overwrite_probe']

        result = insert_imported_dashboards(
            pem_conn,
            data['dashboards'],
            skip_overwrite,
            skip_overwrite_chart,
            skip_overwrite_probe
        )

        return make_json_response(result=result)
