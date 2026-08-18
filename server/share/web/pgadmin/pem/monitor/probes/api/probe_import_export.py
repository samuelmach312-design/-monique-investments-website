##########################################################################
#
# Postgres Enterprise Manager
#
# Copyright (C) 2016 - 2025, EnterpriseDB Corporation. All rights reserved.
#
##########################################################################

"""Probe Import Export API"""

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
from pgadmin.pem.monitor.probes.utils import generate_export_probe_data, \
    insert_imported_probes, validate_imported_probes_fields


api_versions_v6 = list(ApiView.api_versions)[5:]
v6_export_req_params = ['probes']
v6_import_req_params = ['probes', 'skip_overwrite', 'version']


class ProbeExportApiView(ApiView):
    """
    This class provide APIs to exports probe in JSON format.
    """

    endpoint = 'custom_export'
    url = '/probe/custom/export/'

    # Api version from v6 till latest
    # ['v6_api, 'v7_api', 'v8_api']
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
            self.template_path = 'probes/sql/custom_probe'

            return f(self, *args, **kwargs)
        return wrap

    @check_precondition
    def post(self):
        """
        This function will export all the requested probes in the JSON

        Method: POST
        URL: /api/v5/probe/custom/export/

        Input Data: List of custom probe ids [integers]

        Example input data as below.
        {
            probes: [101,...]
        }

        :return:

        Below is the expected result.

        status: 200 OK
        {
          "version":1,
          "probes":[
            {
              "probe_name":"test-1",
              "internal_name":"probe_11111111111111_101",
              "collection_method":"s",
              "target_type":"200",
              "enabled":true,
              "interval":60,
              "lifetime":1,
              "probe_code":"select version();",
              "any_server_version":true,
              "discard_history":false,
              "platform":"*nix",
              "probe_columns":[
                {
                  "pc_name":"version",
                  "pc_internal_name":"version",
                  "pc_position":1,
                  "pc_col_type":"k",
                  "pc_data_type":"text",
                  "pc_unit":"",
                  "pc_graphable":false,
                  "pc_pit_default":false,
                  "pc_calc_pit":false
                }
              ],
              "alternate_code":[
              ]
            }
          ]
        }
        """
        data = request.get_json()
        pem_conn = self.conn

        probe_list = data.get('probes', [])
        if len(probe_list) == 0:
            return bad_request(
                errormsg=gettext("No probes to export")
            )
        status, result = generate_export_probe_data(pem_conn, probe_list)
        if not status:
            return internal_server_error(errormsg=result)

        resp = Response(
            json.dumps({
                "version": CURRENT_EXPORT_VERSION,
                "probes": result
            }),
            mimetype='application/json'
        )
        return resp


class ProbeImportApiView(ApiView):
    """
    This class provide APIs to exports probe in JSON format.
    """

    endpoint = 'custom_import'
    url = '/probe/custom/import/'

    # Api version from v6 till latest
    # ['v6_api, 'v7_api', 'v8_api']
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
            self.template_path = 'probes/sql/custom_probe'

            return f(self, *args, **kwargs)
        return wrap

    @check_precondition
    def post(self):
        """
        This function will import all the requested probes into the PEM

        Method: POST
        URL: /api/v5/probe/custom/import/

        Input Data: List of custom probes which are exported by an probe
        export api.

        Example input data as below.
        {
          "version":1,
          skip_overwrite: true,
          "probes":[
            {
              "probe_name":"test-1",
              "internal_name":"probe_11111111111111_101",
              "collection_method":"s",
              "target_type":"200",
              "enabled":true,
              "interval":60,
              "lifetime":1,
              "probe_code":"select version();",
              "any_server_version":true,
              "discard_history":false,
              "platform":"*nix",
              "probe_columns":[
                {
                  "pc_name":"version",
                  "pc_internal_name":"version",
                  "pc_position":1,
                  "pc_col_type":"k",
                  "pc_data_type":"text",
                  "pc_unit":"",
                  "pc_graphable":false,
                  "pc_pit_default":false,
                  "pc_calc_pit":false
                }
              ],
              "alternate_code":[
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
        if 'probes' not in data or \
                type(data['probes']) != list or \
                len(data['probes']) == 0:
            return bad_request(
                errormsg=gettext("Please provide valid JSON data")
            )

        if 'skip_overwrite' not in data:
            return bad_request(
                errormsg=gettext("skip_overwrite not provided")
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

        # Verify the inputs first
        status, msg = validate_imported_probes_fields(
            pem_conn, data['probes'])
        if not status:
            return bad_request(errormsg=msg)

        result = insert_imported_probes(
            pem_conn, data['probes'], skip_overwrite
        )
        return make_json_response(result=result)
