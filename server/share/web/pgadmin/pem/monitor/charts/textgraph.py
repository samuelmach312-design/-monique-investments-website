##########################################################################
#
# Postgres Enterprise Manager
#
# Copyright (C) 2016 - 2025, EnterpriseDB Corporation. All rights reserved.
#
##########################################################################
""" Implements info chart functionality """

import json

from flask_babel import gettext

from pgadmin.pem.utils import get_config_by_name
from pgadmin.pem.utils import pem_connection
from pgadmin.pem.monitor.dashboard.utils import DashboardTransaction
from flask import request, render_template
from pgadmin.pem.misc.error import error_return, PEMErrorType, \
    PEMChartStatus
from .utils import ChartView
from pgadmin.utils.ajax import make_json_response


class TextChart(ChartView):
    """
    This class has text chart related functionality like initialize,
    set_settings, fetch_chart_info etc..
    """
    chart_label = 'text'
    chart_type = 'TE'

    def __init__(self, *args, **kwargs):
        super(TextChart, self).__init__(*args, **kwargs)

        # Graph configuration settings
        self.show_points = get_config_by_name('show_data_points_on_graph')
        self.show_data_tab = get_config_by_name('show_data_tab_on_graph')
        self.shadow_size = 4
        self.dashboard_transaction = None
        self.stime = None
        self.etime = None
        self.sort_seq = None

    @pem_connection
    def initialize(self, pem_conn=None, *args, **kwargs):
        """
        This function initialize the chart settings
       :param pem_conn: pem database connection
       :param args: args
       :param kwargs: kwargs
       :return: None
       """
        super(TextChart, self).initialize(
            TextChart.chart_label, pem_conn, *args, **kwargs
        )

        self.dep_probes_params["agent"] = self.aid
        self.c_func = self.chart['func']

    @pem_connection
    def fetch_chart_info(self, pem_conn=None):
        """
        This function fetches the text graph chart information from
        charts/sql/text/info.sql and returns the response data
        :param pem_conn: PEM database connection object
        :return: chart information
        """
        return super(TextChart, self).fetch_chart_info(
            pem_conn, TextChart.chart_label
        )

    @pem_connection
    def data(self, pem_conn=None, *args, **kwargs):
        self.initialize()

        # Get agent id
        if self.sid is not None:
            self.aid = self.get_agent_id(self.sid)
            self.is_remotely_monitored_server = \
                self.is_remotely_monitored_server()

        self.get_params()
        with self.dashboard_transaction:
            status, res = pem_conn.execute_scalar(
                self.c_func, self.params
            )
        if not status or res is None:
            error_return(
                gettext("Not enough data is available to give summary."),
                e_type=PEMErrorType.JSON, status_code=200
            )
        else:
            return make_json_response(
                data={
                    'html': res,
                    'success': PEMChartStatus.SUCCESS,
                    'timeout': self.settings['timeout']
                }
            )

    @pem_connection
    def get_chart_settings(self, pem_conn=None):
        sql = render_template(
            'charts/sql/text/get_settings.sql'
        )

        objid = self.get_obj_id()
        params = {
            "cid": self.cid, "did": self.did,
            "objid": objid, "database": self.database,
            "schema": self.schema, "tbl": self.table,
            "level": self.level
        }
        status, dbRes = pem_conn.execute_2darray(sql, params)

        if not status or dbRes is None or len(dbRes) == 0:
            error_return(
                gettext("Couldn't find the chart settings for this chart!"),
                PEMErrorType.JSON
            )

        res = {}
        idx = 0
        for row in dbRes['rows']:
            if idx == 0:
                res['type'] = row['type']
                res['timeout'] = row['timeout']
                res['did'] = row['did']
                res['level'] = row['level']
                idx += 1
        return res

    def get_settings(self, *args, **kwargs):
        res = self.get_chart_settings()
        return make_json_response(
            data=res
        )

    @pem_connection
    def set_settings(self, pem_conn=None, *args, **kwargs):
        """
        This function sets the chart settings
        :param pem_conn: pem database connection object
        :param args: args
        :param kwargs: kwargs
        :return: None
        """
        if request.data:
            req = json.loads(request.data)
        else:
            req = request.args or request.form
        level = req.get('level') if 'level' in req else None

        # set settings in super class
        return super(TextChart, self).set_settings_for_chart(
            req, level, pem_conn)
