##########################################################################
#
# Postgres Enterprise Manager
#
# Copyright (C) 2016 - 2025, EnterpriseDB Corporation. All rights reserved.
#
##########################################################################
""" Implements pie chart functionality """

import sys
import json

from flask_babel import gettext
from flask import request, render_template

from pgadmin.pem.utils import get_config_by_name
from pgadmin.pem.utils import ChartMetricParam, pem_connection
from pgadmin.pem.monitor.dashboard.helpers.chart import whichColor
from pgadmin.pem.misc.error import error_return, PEMErrorType, is_numeric
from .utils import ChartView
from pgadmin.utils.ajax import bad_request, make_json_response, \
    internal_server_error
from pgadmin.pem.monitor.dashboard.utils.chart_constant import PEMChartFunc


class PieChart(ChartView):
    """
    This class has pie chart related functionality like initialize chart,
    fetch_chart_info, get_chart_settings etc..
    """
    chart_label = 'pie'
    chart_type = 'P'

    def __init__(self, *args, **kwargs):
        super(PieChart, self).__init__(*args, **kwargs)

        # Graph configuration settings
        self.show_points = get_config_by_name('show_data_points_on_graph')
        self.show_data_tab = get_config_by_name('show_data_tab_on_graph')
        self.dashboard_transaction = None

    @pem_connection
    def initialize(self, pem_conn=None, *args, **kwargs):
        """
         This function initialize the chart settings
        :param pem_conn: pem database connection
        :param args: args
        :param kwargs: kwargs
        :return: None
        """
        # initialize some settings from super class
        super(PieChart, self).initialize(
            self.chart_label, pem_conn, *args, **kwargs
        )

        # Get agent id
        if self.sid is not None:
            self.aid = self.get_agent_id(self.sid)
        if self.aid is not None:
            self.dep_probes_params["agent"] = self.aid

        self.f_type = self.chart['func_type']  # PYTHON or QUERY Function
        self.c_func = self.chart['func']
        self.colors = self.chart['colors']
        self.isvertical = self.chart['isvertical']
        self.metadata = dict(self.chart)

    @pem_connection
    def fetch_chart_info(self, pem_conn=None):
        """
        This function fetches the line chart information from
        charts/sql/pie/info.sql and returns the response data
        :param pem_conn: PEM database connection object
        :return: chart information
        """
        return super(PieChart, self).fetch_chart_info(
            pem_conn, self.chart_label
        )

    @pem_connection
    def data(self, pem_conn=None, *args, **kwargs):
        self.initialize()

        # Get agent id
        if self.sid is not None:
            self.aid = self.get_agent_id(self.sid)

        self.get_dep_probes()
        self.get_params()

        res = None
        if self.f_type == PEMChartFunc.QUERY:
            with self.dashboard_transaction:
                status, res = pem_conn.execute_2darray(
                    self.c_func, self.params, False)

            if not status or res is None or len(res['rows']) == 0:
                error_return(
                    gettext(
                        "{0}" if self.dep_probes_warning
                        else "Not enough data is available to render "
                        "the chart."
                    ).format(self.dep_probes_warning),
                    e_type=PEMErrorType.JSON,
                    status_code=200
                )
        else:
            # We don't support any other chart-function type
            error_return(
                gettext(
                    "{0}" if self.dep_probes_warning
                    else "Not enough data is available to render "
                    "the chart."
                ).format(self.dep_probes_warning),e_type=PEMErrorType.JSON,
                status_code=200
            )

        series = []
        chart_colors = []
        self.metadata.pop('func', None)
        metadata = self.metadata
        res = res['rows']

        if self.isvertical:
            res = [[i for i in obj.values()] for obj in res]

            has_valid_data = False
            for idx, data in enumerate(res):
                if (
                    data[1] is not None and
                    is_numeric(data[1]) and
                    float(data[1]) != 0
                ):
                    has_valid_data = True
                    color = whichColor(
                        idx, data[0], self.colors, self.settings
                    )
                    chart_colors.append(color)
                    series.insert(
                        idx,
                        {
                            'data': [[0, data[1]]],
                            'label': data[0],
                            'color': color,
                        },
                    )

        else:
            data = list(res[0].values()) if res else []
            has_valid_data = False

            for i, value in enumerate(data):
                if value is not None and is_numeric(value) and int(value) != 0:
                    has_valid_data = True
                    color = whichColor(
                        i,
                        self.labels[i] if self.labels else ('#' + str(i)),
                        self.colors,
                        self.settings,
                    )
                    chart_colors.append(color)
                    series.insert(
                        i,
                        {
                            'data': [[0, value]],
                            'label': (
                                self.labels[i] if self.labels else (
                                    '#' + str(i)
                                )
                            ),
                            'color': color,
                        },
                    )

        if not has_valid_data:
            series = []

        return make_json_response(
            data={
                'metadata': metadata,
                'series': series, 'success': self.ret_status,
                'colors': chart_colors,
                'downloadformat': self.settings.get('downloadformat'),
                'timeout': self.settings.get('timeout', 300000),
                'spreadsheet': self.show_data_tab,
                'error': self.dep_probes_warning
            }
        )

    @pem_connection
    def get_chart_settings(self, pem_conn=None):
        """
        This function gets the chart settings from super class's method
        :param pem_conn: pem database connection
        :return: chart settings
        """
        return super(PieChart, self).get_chart_settings(
            pem_conn, self.chart_label
        )

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
        level = self.get_chart_level(**kwargs)

        # set settings in super class
        return super(PieChart, self).set_settings_for_chart(
            req, level, pem_conn)
