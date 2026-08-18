##########################################################################
#
# Postgres Enterprise Manager
#
# Copyright (C) 2016 - 2025, EnterpriseDB Corporation. All rights reserved.
#
##########################################################################

"""Alert History API"""

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


HISTORY_OUTPUT_PARAMS = list([
    "alert_id", "state", "value", "actual_value",
])


def check_precondition(f):
    """
    This function will behave as a decorator which will checks
    database connection before running view, it will also attaches
    manager,conn & template_path properties to self
    """

    @wraps(f)
    def wrap(instance, *args, **kwargs):
        """Makes PEM connection object and sets template path"""
        instance.conn = kwargs['pem_conn']

        if not instance.conn.connected():
            instance.conn.connect()

        # If DB not connected then return error to browser
        if not instance.conn.connected():
            return precondition_required(
                gettext("Connection to the PEM server has been lost!")
            )

        # We do not need to pass the pem_conn to the wrapped functions
        del kwargs['pem_conn']

        # Set the template path for sql scripts
        instance.template_path = 'alerts/sql/alerts'

        return f(instance, *args, **kwargs)

    return wrap


class AlertHistoryApiView(ApiView):
    """
    This class provide APIs to get the history of the state changes of all the
    alerts.
    """
    endpoint = 'alerts_history'
    url = '/alert/history/'
    conn = None
    template_path = None
    methods = ['GET']

    api_versions_v4 = list(ApiView.api_versions)[3:]
    # Api version from v4 till latest
    # ['v4_api', 'v5_api', 'v6_api', 'v7_api', 'v8_api']
    api_versions = api_versions_v4
    pk = None
    pk_type = None
    output_params = HISTORY_OUTPUT_PARAMS

    def _get_alerts_history(
        self, alert_id=None, agent_id=None, server_id=None, database_name=None
    ):
        status, res = self.conn.execute_dict(render_template(
            "/".join([self.template_path, 'alerts_history.sql']),
            alert_id=alert_id, agent_id=agent_id, server_id=server_id,
            database_name=database_name, conn=self.conn
        ))

        if not status:
            return internal_server_error(errormsg=res)

        return make_response([
            self.discard_unwanted_params(row, self.output_params)
            for row in res['rows']
        ])

    @check_precondition
    def get(self):
        """
        This function will return the history of the state changes of all the
        alerts.

        Method: GET
        URL: /api/v4/alert/history/
        DESCRIPTION: Fetch the state changes of all the alerts.

        :return:
        [{
            "alert_id": 1,  "state": "High", "value": "UP", "actual_value": 0
        },
        ...
        ]
        """
        return self._get_alerts_history()


class AgentAlertHistoryApiView(AlertHistoryApiView):
    """
    This class provide APIs to get the history of the state changes of all the
    alerts.
    """
    endpoint = 'agent_alerts_history'
    url = '/alert/history/agent/<int:agent_id>'

    @check_precondition
    def get(self, agent_id):
        """
        This function will return the history of the state changes of all the
        alerts for the given agent.

        Method: GET
        URL: /api/v4/alert/history/agent/1
        DESCRIPTION: Fetch the state changes of all the alerts for the given
        agent.

        Input Data:
        Valid Agent ID

        :return:
        [{
            "alert_id": 1,  "state": "High", "value": "UP", "actual_value": 0
        },
        ...
        ]
        """
        return self._get_alerts_history(agent_id=agent_id)


class ServerAlertHistoryApiView(AlertHistoryApiView):
    """
    This class provide APIs to get the history of the state changes of all the
    alerts.
    """
    endpoint = 'server_alerts_history'
    url = '/alert/history/server/<int:server_id>'

    @check_precondition
    def get(self, server_id):
        """
        This function will return the history of the state changes of all the
        alerts for the given server.

        Method: GET
        URL: /api/v4/alert/history/server/1
        DESCRIPTION: Fetch the state changes of all the alerts for the given
        server.

        Input Data:
        Valid Server ID

        :return:
        [{
            "alert_id": 1,  "state": "High", "value": "UP", "actual_value": 0
        },
        ...
        ]
        """
        return self._get_alerts_history(server_id=server_id)


class DatabaseAlertHistoryApiView(AlertHistoryApiView):
    """
    This class provide APIs to get the history of the state changes of all the
    alerts.
    """
    endpoint = 'database_alerts_history'
    url = '/alert/history/server/<int:server_id>/database/' \
          '<string:database_name>'

    @check_precondition
    def get(self, server_id, database_name):
        """
        This function will return the history of the state changes of all the
        alerts for the given server.

        Method: GET
        URL: /api/v4/alert/history/server/1/database/pem
        DESCRIPTION: Fetch the state changes of all the alerts for the given
        server and database.

        Input Data:
        Valid Server ID and database name

        :return:
        [{
            "alert_id": 1,  "state": "High", "value": "UP", "actual_value": 0
        },
        ...
        ]
        """
        return self._get_alerts_history(
            server_id=server_id, database_name=database_name
        )
