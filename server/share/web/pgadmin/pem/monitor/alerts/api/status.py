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
api_versions_v4 = list(ApiView.api_versions)[3:]


status_output_params = list([
    "alert_since", "alert_id", "alert_state", "alert_name", "value",
    "object_description", "server_id", "agent_id", "database", "schema",
    "package", "object", "alert_target_level", "last_processed", "info",
    "info_cols", "info_vals"
])


class AlertStatusApiView(ApiView):
    """
    This class provide APIs to current state of the all alerts.
    """
    endpoint = 'alert_status'
    url = '/alert/status/'
    conn = None
    template_path = None
    methods = ['GET']

    # Api version from v4 till latest
    # ['v4_api', 'v5_api', 'v6_api', 'v7_api', 'v8_api']
    api_versions = api_versions_v4
    pk = 'since'
    pk_type = 'float'

    def check_precondition(f):
        """
        This function will behave as a decorator which will checks
        database connection before running view, it will also attaches
        manager,conn & template_path properties to self
        """

        @wraps(f)
        def wrap(self, *args, **kwargs):
            """Makes PEM connection object and sets template path"""
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
            self.template_path = 'alerts/sql/alerts'

            return f(self, *args, **kwargs)

        return wrap

    output_params = status_output_params

    @check_precondition
    def get(self, since=None):
        """
        This function will return the status of all the alerts whose states has
        been updated since the given timeline.

        :param since: Time line since which the status has been updated.

        Method: GET
        URL: /api/v4/alert/status/
        DESCRIPTION: List the status of the alerts

        Method: GET
        URL: /api/v4/alert/status/12312313.123
        DESCRIPTION: List of alerts updated after the given time line

        Input Data:
        Valid EPOCH time since that time for the alert status has been changed.

        Input URL:
        /api/v4/alert/status/

        :return:

        [{
            "alert_since": "1595319076408.53","alert_id":150,
            "alert_state": "High", "alert_name":"CPU utilization",
            "value":"7.45%", "object_description": "Game Console Host",
            "server_id": null, "agent_id": 8, "database":null, "schema":null,
            "package": null, "object": null, "alert_target_level":"Agent",
            "last_processed": "1595319076408.53",
            "info":null, "info_cols":null, "info_vals":null
        },
        ...
        ]

        Input URL:
        /api/v1/alert/status/23413413.34

        :return:
        [{
            "alert_since": "1595319076408.53","alert_id":150,
            "alert_state": "Low", "alert_name":"CPU utilization",
            "value":"7.45%", "object_description": "Game Console Host",
            "server_id": null, "agent_id": 8, "database":null, "schema":null,
            "package": null, "object": null, "alert_target_level":"Agent",
            "last_processed": "1595319076408.53",
            "info":null, "info_cols":null, "info_vals":null
        },
        ...
        ]



        """
        status, res = self.conn.execute_dict(render_template(
            "/".join([self.template_path, 'alert_status.sql']),
            since=since
        ))

        if not status:
            return internal_server_error(errormsg=res)

        return make_response([
            self.discard_unwanted_params(row, self.output_params)
            for row in res['rows']
        ])
