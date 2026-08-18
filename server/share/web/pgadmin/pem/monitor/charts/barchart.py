##########################################################################
#
# Postgres Enterprise Manager
#
# Copyright (C) 2016 - 2025, EnterpriseDB Corporation. All rights reserved.
#
##########################################################################
""" Implements bar chart functionality """

import json
from flask import request

from flask_babel import gettext

from pgadmin.pem.utils import get_config_by_name
from pgadmin.pem.utils import ChartMetricParam, pem_connection
from pgadmin.pem.monitor.dashboard.helpers.chart import whichColor
from pgadmin.pem.misc.error import error_return, PEMErrorType
from pgadmin.utils.ajax import make_json_response
from pgadmin.pem.monitor.dashboard.utils.chart_constant import PEMChartFunc
from pgadmin.pem.monitor.dashboard.utils.barcharts \
    import barchart_alerts_overview
from .utils import ChartView
from html import escape


class BarChart(ChartView):
    """
    This class has bart chart functionality. Contains some methods like
    initialize chart, get_chart_settings(), set_settings() etc.
    """
    chart_label = 'bar'
    chart_type = 'B'

    def __init__(self, *args, **kwargs):
        super(BarChart, self).__init__(*args, **kwargs)

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
        super(BarChart, self).initialize(
            self.chart_label, pem_conn, *args, **kwargs
        )

        self.f_type = self.chart['func_type']
        self.c_func = self.chart['func']
        self.is_position_based = self.chart['is_position_based']
        self.metadata = dict(self.chart)

        self.dep_probes_params["agent"] = self.aid
        self.colors = self.chart['colors']

    @pem_connection
    def fetch_chart_info(self, pem_conn):
        """
        This function fetches the bart chart information from
        charts/sql/bar/info.sql and returns the response data
        :param pem_conn: PEM database connection object
        :return: chart information
        """
        return super(BarChart, self).fetch_chart_info(pem_conn,
                                                      self.chart_label)

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
        return super(BarChart, self).set_settings_for_chart(
            req, level, pem_conn)

    @pem_connection
    def get_chart_settings(self, pem_conn=None):
        """
        This function gets the chart settings from super class's method
        :param pem_conn: pem database connection
        :return: chart settings
        """
        return super(BarChart, self).get_chart_settings(pem_conn,
                                                        self.chart_label)

    def get_settings(self, *args, **kwargs):
        """
        This function gets the chart settings
        :param args: args
        :param kwargs: kwargs
        :return: settings in json response
        """
        res = self.get_chart_settings()
        return make_json_response(
            data=res
        )

    def update_label_and_id_keys(self, chart_id, id_keys, row):
        """
        This function update id_keys dict and chart labels ans returns the
        chart id count
        chart ids
        :param chart_id: chart id
        :param id_keys: chart id keys
        :param row: chart function response
        :return: count
        """
        if chart_id in id_keys:
            cnt = id_keys[chart_id]
        else:
            cnt = len(id_keys)
            id_keys.update({chart_id: cnt})

        # second will be label (in case of position based)
        if self.is_position_based:
            label = self.pop(row)

            if label == '':
                label = '#' + str(cnt)
            if cnt not in self.labels:
                self.labels.update({cnt: label})
        else:
            if chart_id not in self.labels:
                self.labels.update({cnt: chart_id})
        return cnt

    def create_chart_dict(self, res, id_keys):
        """
        This function create and returns  chart info dict with chart label and
        chart count
        :param res: chart function's response
        :param id_keys: blank dict to update the only chart ids
        :return: chart dict with chart label and chart id
        """
        data_array = {}

        for row in res:
            row = list(row.values())
            chart_id = self.pop(row)
            cnt = self.update_label_and_id_keys(chart_id, id_keys, row)

            if self.is_position_based:
                data_array.update({chart_id: [[cnt, self.pop(row)]]})
            else:
                data_array.update({cnt: [[cnt, self.pop(row)]]})

        return data_array

    def call_c_function(self):
        """
        This function calls the c_function and returns the response
        :return: c_function response
        """
        res = None
        try:
            params = list(self.params.values())
            res = self.c_func(*params)
        except Exception as e:
            error_return(
                gettext(
                    "Error generating the data for the chart "
                    "({0})\nERROR\n{1}"
                ).format(self.name, str(e)), e_type=PEMErrorType.JSON,
                status_code=500
            )

        if res is not None and not isinstance(res, list):
            error_return(
                gettext(
                    "The function ({0}) must return an array"
                ).format(self.c_func), e_type=PEMErrorType.JSON,
                status_code=500
            )
        return res

    @pem_connection
    def data(self, pem_conn=None, *args, **kwargs):
        self.initialize()

        res = None
        self.get_dep_probes()
        self.get_params()

        if self.f_type == PEMChartFunc.PYTHON:
            self.c_func = eval(self.c_func)
            if callable(self.c_func):
                res = self.call_c_function()
            else:
                error_return(
                    gettext(
                        "The function ({0}), for generating the data for the "
                        "chart ({1}), could not be found."
                    ).format(self.c_func, self.name),
                    e_type=PEMErrorType.JSON, status_code=400
                )
        elif self.f_type == PEMChartFunc.QUERY:
            with self.dashboard_transaction:
                status, res = pem_conn.execute_2darray(
                    self.c_func, self.params, False
                )
            if not status:
                error_return(
                    gettext(
                        "Error generating the data for the chart "
                        "({0})\nERROR:\n{1}"
                    ).format(self.name, res), e_type=PEMErrorType.JSON,
                    status_code=500
                )
        else:
            # Hmm - we don't support any other chart-function type
            error_return(
                gettext(
                    "We do not support a function based data generation for "
                    "other than as the system function/QUERY."
                ), e_type=PEMErrorType.JSON, status_code=501
            )
        if 'rows' in res:
            res = res['rows']

        id_keys = {}
        chart_colors = []
        series = []

        data_array = self.create_chart_dict(res, id_keys)

        data_array_dict = sorted(
            list(data_array.items()), key=lambda item: item[0])
        for sorted_chart_id, data in data_array_dict:
            if self.is_position_based:
                sorted_chart_id -= 1

            if sorted_chart_id < len(self.labels):
                label = escape(self.labels[sorted_chart_id])
            color = whichColor(
                sorted_chart_id, label, self.colors, self.settings
            )
            chart_colors.append(color)
            series.append({
                'data': data,
                'label': label,
                'color': color
            })

        # Remove the function source (if exists)
        self.metadata.pop('func', None)

        return make_json_response(data={
            'series': series, 'success': self.ret_status,
            'colors': chart_colors,
            'timeout': self.settings.get('timeout', 60000),
            'downloadformat': self.settings.get('downloadformat'),
            'spreadsheet': self.show_data_tab,
            'error': self.dep_probes_warning,
            'metadata': self.metadata,
        })
