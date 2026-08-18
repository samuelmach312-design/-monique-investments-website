##########################################################################
#
# Postgres Enterprise Manager
#
# Copyright (C) 2016 - 2025, EnterpriseDB Corporation. All rights reserved.
#
##########################################################################

"""Chart Import Export API"""

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
from pgadmin.pem.monitor.charts.manage.utils import insert_imported_charts, \
    generate_export_chart_data


api_versions_v7 = list(ApiView.api_versions)[6:]
v7_export_req_params = ['charts']
v7_import_req_params = ['charts', 'skip_overwrite',
                        'skip_overwrite_probe', 'version']


class ChartExportApiView(ApiView):
    """
    This class provide APIs to exports chart in JSON format.
    """

    endpoint = 'custom_chart_export'
    url = '/chart/custom/export/'

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
        URL: /api/v7/chart/custom/export/

        Input Data: List of custom chart ids [integers]

        Example input data as below.
        {
            charts: [101,...]
        }

        :return:

        Below is the expected result.

        status: 200 OK
        {
          "version":1,
          "charts":[
            {
              "id":257,
              "reference_id":"chart_1627468667181042519653_257",
              "chart_title":"abcdef",
              "chart_category":"Alerts",
              "chart_description":"bbbb",
              "chart_level":200,
              "chart_type":"L",
              "shared":[

              ],
              "shared_all":true,
              "chart_refresh":3,
              "line_span":11581,
              "chart_line_points":51,
              "espan":25,
              "chart_line_ext_metric":null,
              "chart_line_ext_opt":null,
              "chart_line_ext_val":null,
              "chart_line_extrapolated_type":"SE",
              "chart_line_span":[
                8,
                1,
                1
              ],
              "chart_line_ext":[
                1,
                1
              ],
              "chart_line_ext_metric_options":[

              ],
              "sel_metrics_L":[
                {
                  "pid":35,
                  "mid":200,
                  "metric_id":1,
                  "g_options":[
                    {
                      "label":"Core ID",
                      "value":"199,x",
                      "selected":"selected"
                    },
                    {
                      "label":"Load Percentage",
                      "value":"200,f"
                    }
                  ],
                  "g":"199,x",
                  "gd":"A",
                  "compare":[
                    "{\"(agent_id,1)\",\"(core_id,CPU0)\"}",
                    "{\"(agent_id,1)\",\"(core_id,CPU1)\"}",
                    "{\"(agent_id,1)\",\"(core_id,CPU2)\"}",
                    "{\"(agent_id,1)\",\"(core_id,CPU3)\"}"
                  ],
                  "chart_line_ext_metric_options":[
                    {
                      "label":"Load Percentage ",
                      "value":"35,200,False,CPU0",
                      "metric_id":2
                    },
                    {
                      "label":"Load Percentage ",
                      "value":"35,200,False,CPU1",
                      "metric_id":3
                    },
                    {
                      "label":"Load Percentage ",
                      "value":"35,200,False,CPU2",
                      "metric_id":4
                    },
                    {
                      "label":"Load Percentage ",
                      "value":"35,200,False,CPU3",
                      "metric_id":5
                    }
                  ],
                  "line_ext_metric":false,
                  "c":[

                  ],
                  "pit":false,
                  "l":1,
                  "mt":"load_percentage",
                  "label":"Load Percentage",
                  "internal_name":"load_percentage",
                  "m":"Load Percentage [ CPU Usage ]",
                  "probe_target_type":100,
                  "applies_to_id":100,
                  "probe_key_list":[
                    "core_id"
                  ],
                  "probe_key_display_name":[
                    "Core ID"
                  ],
                  "probe":"CPU Usage",
                  "is_system_probe":true
                },
                {
                  "pid":33,
                  "mid":192,
                  "metric_id":6,
                  "g_options":[
                    {
                      "label":"Device ID",
                      "value":"193,x",
                      "selected":"selected"
                    },
                    {
                      "label":"Disk Busy Percentage",
                      "value":"192,f"
                    },
                    {
                      "label":"Mount Point",
                      "value":"191,x"
                    }
                  ],
                  "g":"193,x",
                  "gd":"A",
                  "compare":[

                  ],
                  "chart_line_ext_metric_options":[

                  ],
                  "line_ext_metric":false,
                  "c":[

                  ],
                  "pit":false,
                  "l":1,
                  "mt":"disk_busy",
                  "label":"Disk Busy Percentage",
                  "internal_name":"disk_busy",
                  "m":"Disk Busy Percentage [ Disk Busy Info ]",
                  "probe_target_type":100,
                  "applies_to_id":100,
                  "probe_key_list":[
                    "device_id",
                    "mount_point"
                  ],
                  "probe_key_display_name":[
                    "Device ID",
                    "Mount Point"
                  ],
                  "probe":"Disk Busy Info",
                  "is_system_probe":true
                },
                {
                  "pid":37,
                  "mid":213,
                  "metric_id":7,
                  "g_options":[
                    {
                      "label":"In Packet Discards+",
                      "value":"215,f"
                    },
                    {
                      "label":"In Packet Discards",
                      "value":"215,t"
                    },
                    {
                      "label":"In Packet Errors+",
                      "value":"217,f"
                    },
                    {
                      "label":"In Packet Errors",
                      "value":"217,t"
                    },
                    {
                      "label":"Interface Name",
                      "value":"208,x",
                      "selected":"selected"
                    },
                    {
                      "label":"IP Address",
                      "value":"209,x"
                    },
                    {
                      "label":"Link Bandwidth (Mbit/s)",
                      "value":"218,f"
                    },
                    {
                      "label":"Out Packet Discards+",
                      "value":"214,f"
                    },
                    {
                      "label":"Out Packet Discards",
                      "value":"214,t"
                    },
                    {
                      "label":"Out Packet Errors+",
                      "value":"216,f"
                    },
                    {
                      "label":"Out Packet Errors",
                      "value":"216,t"
                    },
                    {
                      "label":"Packets Received+",
                      "value":"211,f"
                    },
                    {
                      "label":"Packets Received",
                      "value":"211,t"
                    },
                    {
                      "label":"Packets Sent+",
                      "value":"210,f"
                    },
                    {
                      "label":"Packets Sent",
                      "value":"210,t"
                    },
                    {
                      "label":"Bytes Received (KB)+",
                      "value":"213,f"
                    },
                    {
                      "label":"Bytes Received (KB)",
                      "value":"213,t"
                    },
                    {
                      "label":"Bytes Sent (KB)+",
                      "value":"212,f"
                    },
                    {
                      "label":"Bytes Sent (KB)",
                      "value":"212,t"
                    }
                  ],
                  "g":"208,x",
                  "gd":"A",
                  "compare":[

                  ],
                  "chart_line_ext_metric_options":[

                  ],
                  "line_ext_metric":false,
                  "c":[

                  ],
                  "pit":false,
                  "l":1,
                  "mt":"receive_bytes_kb",
                  "label":"Bytes Received (KB)+",
                  "internal_name":"receive_bytes_kb",
                  "m":"Bytes Received (KB)+ [ Network Statistics ]",
                  "probe_target_type":100,
                  "applies_to_id":100,
                  "probe_key_list":[
                    "interface_name"
                  ],
                  "probe_key_display_name":[
                    "Interface Name"
                  ],
                  "probe":"Network Statistics",
                  "is_system_probe":true
                }
              ]
            }
          ]
        }
        """
        data = request.get_json()
        pem_conn = self.conn

        charts = data.get('charts', [])
        if len(charts) == 0:
            return bad_request(
                errormsg=gettext("No charts to export")
            )
        status, result = generate_export_chart_data(pem_conn, charts)
        if not status:
            return internal_server_error(errormsg=result)

        resp = Response(
            json.dumps({
                "version": CURRENT_EXPORT_VERSION,
                "charts": result
            }),
            mimetype='application/json'
        )
        return resp


class ChartImportApiView(ApiView):
    """
    This class provide APIs to import chart in JSON format.
    """

    endpoint = 'custom_chart_import'
    url = '/chart/custom/import/'

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
            {
              "id":257,
              "reference_id":"chart_1627468667181042519653_257",
              "chart_title":"abcdef",
              "chart_category":"Alerts",
              "chart_description":"bbbb",
              "chart_level":200,
              "chart_type":"L",
              "shared":[

              ],
              "shared_all":true,
              "chart_refresh":3,
              "line_span":11581,
              "chart_line_points":51,
              "espan":25,
              "chart_line_ext_metric":null,
              "chart_line_ext_opt":null,
              "chart_line_ext_val":null,
              "chart_line_extrapolated_type":"SE",
              "chart_line_span":[
                8,
                1,
                1
              ],
              "chart_line_ext":[
                1,
                1
              ],
              "chart_line_ext_metric_options":[

              ],
              "sel_metrics_L":[
                {
                  "pid":35,
                  "mid":200,
                  "metric_id":1,
                  "g_options":[
                    {
                      "label":"Core ID",
                      "value":"199,x",
                      "selected":"selected"
                    },
                    {
                      "label":"Load Percentage",
                      "value":"200,f"
                    }
                  ],
                  "g":"199,x",
                  "gd":"A",
                  "compare":[
                    "{\"(agent_id,1)\",\"(core_id,CPU0)\"}",
                    "{\"(agent_id,1)\",\"(core_id,CPU1)\"}",
                    "{\"(agent_id,1)\",\"(core_id,CPU2)\"}",
                    "{\"(agent_id,1)\",\"(core_id,CPU3)\"}"
                  ],
                  "chart_line_ext_metric_options":[
                    {
                      "label":"Load Percentage ",
                      "value":"35,200,False,CPU0",
                      "metric_id":2
                    },
                    {
                      "label":"Load Percentage ",
                      "value":"35,200,False,CPU1",
                      "metric_id":3
                    },
                    {
                      "label":"Load Percentage ",
                      "value":"35,200,False,CPU2",
                      "metric_id":4
                    },
                    {
                      "label":"Load Percentage ",
                      "value":"35,200,False,CPU3",
                      "metric_id":5
                    }
                  ],
                  "line_ext_metric":false,
                  "c":[

                  ],
                  "pit":false,
                  "l":1,
                  "mt":"load_percentage",
                  "label":"Load Percentage",
                  "internal_name":"load_percentage",
                  "m":"Load Percentage [ CPU Usage ]",
                  "probe_target_type":100,
                  "applies_to_id":100,
                  "probe_key_list":[
                    "core_id"
                  ],
                  "probe_key_display_name":[
                    "Core ID"
                  ],
                  "probe":"CPU Usage",
                  "is_system_probe":true
                },
                {
                  "pid":33,
                  "mid":192,
                  "metric_id":6,
                  "g_options":[
                    {
                      "label":"Device ID",
                      "value":"193,x",
                      "selected":"selected"
                    },
                    {
                      "label":"Disk Busy Percentage",
                      "value":"192,f"
                    },
                    {
                      "label":"Mount Point",
                      "value":"191,x"
                    }
                  ],
                  "g":"193,x",
                  "gd":"A",
                  "compare":[

                  ],
                  "chart_line_ext_metric_options":[

                  ],
                  "line_ext_metric":false,
                  "c":[

                  ],
                  "pit":false,
                  "l":1,
                  "mt":"disk_busy",
                  "label":"Disk Busy Percentage",
                  "internal_name":"disk_busy",
                  "m":"Disk Busy Percentage [ Disk Busy Info ]",
                  "probe_target_type":100,
                  "applies_to_id":100,
                  "probe_key_list":[
                    "device_id",
                    "mount_point"
                  ],
                  "probe_key_display_name":[
                    "Device ID",
                    "Mount Point"
                  ],
                  "probe":"Disk Busy Info",
                  "is_system_probe":true
                },
                {
                  "pid":37,
                  "mid":213,
                  "metric_id":7,
                  "g_options":[
                    {
                      "label":"In Packet Discards+",
                      "value":"215,f"
                    },
                    {
                      "label":"In Packet Discards",
                      "value":"215,t"
                    },
                    {
                      "label":"In Packet Errors+",
                      "value":"217,f"
                    },
                    {
                      "label":"In Packet Errors",
                      "value":"217,t"
                    },
                    {
                      "label":"Interface Name",
                      "value":"208,x",
                      "selected":"selected"
                    },
                    {
                      "label":"IP Address",
                      "value":"209,x"
                    },
                    {
                      "label":"Link Bandwidth (Mbit/s)",
                      "value":"218,f"
                    },
                    {
                      "label":"Out Packet Discards+",
                      "value":"214,f"
                    },
                    {
                      "label":"Out Packet Discards",
                      "value":"214,t"
                    },
                    {
                      "label":"Out Packet Errors+",
                      "value":"216,f"
                    },
                    {
                      "label":"Out Packet Errors",
                      "value":"216,t"
                    },
                    {
                      "label":"Packets Received+",
                      "value":"211,f"
                    },
                    {
                      "label":"Packets Received",
                      "value":"211,t"
                    },
                    {
                      "label":"Packets Sent+",
                      "value":"210,f"
                    },
                    {
                      "label":"Packets Sent",
                      "value":"210,t"
                    },
                    {
                      "label":"Bytes Received (KB)+",
                      "value":"213,f"
                    },
                    {
                      "label":"Bytes Received (KB)",
                      "value":"213,t"
                    },
                    {
                      "label":"Bytes Sent (KB)+",
                      "value":"212,f"
                    },
                    {
                      "label":"Bytes Sent (KB)",
                      "value":"212,t"
                    }
                  ],
                  "g":"208,x",
                  "gd":"A",
                  "compare":[

                  ],
                  "chart_line_ext_metric_options":[

                  ],
                  "line_ext_metric":false,
                  "c":[

                  ],
                  "pit":false,
                  "l":1,
                  "mt":"receive_bytes_kb",
                  "label":"Bytes Received (KB)+",
                  "internal_name":"receive_bytes_kb",
                  "m":"Bytes Received (KB)+ [ Network Statistics ]",
                  "probe_target_type":100,
                  "applies_to_id":100,
                  "probe_key_list":[
                    "interface_name"
                  ],
                  "probe_key_display_name":[
                    "Interface Name"
                  ],
                  "probe":"Network Statistics",
                  "is_system_probe":true
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
        if 'charts' not in data or \
                not isinstance(data['charts'], list) or \
                len(data['charts']) == 0 or \
                'skip_overwrite' not in data or \
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
        skip_overwrite_probe = data['skip_overwrite_probe']

        result = insert_imported_charts(
            pem_conn, data['charts'], skip_overwrite,
            skip_overwrite_probe
        )
        return make_json_response(result=result)
