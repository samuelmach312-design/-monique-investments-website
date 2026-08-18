##########################################################################
#
# Postgres Enterprise Manager
#
# Copyright (C) 2016 - 2025, EnterpriseDB Corporation. All rights reserved.
#
##########################################################################
""" Implements cmline chart functionality """

import json

from flask_babel import gettext
from flask import request

from pgadmin.pem.utils import get_config_by_name
from pgadmin.pem.utils import pem_connection
from pgadmin.pem.monitor.dashboard.helpers.chart import whichColor
from pgadmin.pem.misc.error import error_return, PEMErrorType, \
    PEMChartStatus
from pgadmin.utils.ajax import make_json_response
from .utils import ChartView


class CMLineChart(ChartView):
    """
    This class has line chart related functionality for capacity manager
    like initialize chart's settings, get_chart_settings etc..
    """
    chart_label = 'cmline'
    chart_type = 'CL'
    suffix = 'stime/<start_time>/etime/<end_time>'

    def __init__(self, *args, **kwargs):
        super(CMLineChart, self).__init__(*args, **kwargs)

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
        super(CMLineChart, self).initialize(
            self.chart_label, pem_conn, *args, **kwargs
        )
        self.dep_probes_params["agent"] = self.aid
        self.colors = self.chart['colors']

    @pem_connection
    def fetch_chart_info(self, pem_conn):
        """
       This function fetches the cmline chart information from
       charts/sql/cmline/info.sql and returns the response data
       :param pem_conn: PEM database connection object
       :return: chart information
       """
        return super(CMLineChart, self).fetch_chart_info(
            pem_conn, self.chart_label
        )

    @pem_connection
    def get_chart_settings(self, pem_conn=None):
        """
        This function gets the chart settings from super class's method
        :param pem_conn: pem database connection
        :return: chart settings
        """
        return super(CMLineChart, self).get_chart_settings(
            pem_conn, self.chart_label
        )

    @pem_connection
    def set_chart_settings(self, pem_conn=None, *args, **kwargs):
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
        return super(CMLineChart, self).set_settings_for_chart(
            req, level, pem_conn)

    @pem_connection
    def cmline_get_data(self, pem_conn=None, *args, **kwargs):
        self.get_dep_probes()

        # Get agent id
        if self.sid is not None:
            self.aid = self.get_agent_id(self.sid)
        self.get_params()

        success = PEMChartStatus.SUCCESS
        query = """
                        SELECT
                        idx, label, is_agent, object, is_active, color
                        FROM
                        pem.cm_report_chart_info((%s)::int4)
                        """

        with self.dashboard_transaction:
            status, metaRS = pem_conn.execute_2darray(query, [self.cid])

        if 'rows' in metaRS:
            metaRS = metaRS['rows']
        meta = {}
        for row in metaRS:
            meta[row['idx']] = {
                'label': row['label'],
                'is_agent': row['is_agent'], 'object': row['object'],
                'is_active': row['is_active'], 'color': row['color'],
                'data_present': False
            }
            if row['color'] == '' or row['color'] is None:
                meta[row['idx']]['color'] = whichColor(
                    row['idx'], row['label'], self.colors, self.settings
                )

        # Save dashboard transaction id
        with self.dashboard_transaction:
            status, ctime = pem_conn.execute_scalar(
                "SELECT (EXTRACT(EPOCH FROM now()) * 1000)::numeric(40, 0)"
            )

        query = """
                        SELECT
                        idx, 'Date(' || (
                            EXTRACT(EPOCH FROM rtime) * 1000
                        )::numeric(40, 0)::text || ')' agg_time,
                        value
                        FROM
                        pem.generate_cm_chart_data((%s)::int4)
                        ORDER BY idx, rtime"""

        with self.dashboard_transaction:
            status, rs = pem_conn.execute_2darray(query, [self.cid], True)

        if status is not True:
            error_return(
                gettext(
                    "Couldn't generate the chart data."
                ) + "\n" + rs,
                PEMErrorType.JSON
            )

        if 'rows' in rs:
            rs = rs['rows']

        prevIdx = None
        data = []
        label = ''
        color = ''
        series = []
        for row in rs:
            if prevIdx != row['idx']:
                if prevIdx is not None:
                    series.append({
                        'data': data, 'label': label, 'color': color,
                        'points': {'show': self.show_points},
                        'shadowSize': self.shadow_size
                    })
                    data = []
                if row['idx'] in meta:
                    color = meta[row['idx']]['color']
                    label = meta[row['idx']]['label']
                    meta[row['idx']]['data_present'] = True
                else:
                    label = 'M#' + row['idx']
                    color = whichColor(row['idx'], label,
                                       self.colors, self.settings)
                prevIdx = row['idx']
            data.append([row['agg_time'], row['value']])
        if prevIdx is not None:
            series.append({
                'data': data, 'label': label, 'color': color,
                'points': {'show': self.show_points},
                'shadowSize': self.shadow_size
            })
        msg = ''
        agents = ''
        servers = ''
        objs = ''
        for key, row in list(meta.items()):
            if not row['data_present']:
                success = PEMChartStatus.WARNING | PEMChartStatus.SUCCESS
                if not row['is_active'] and row['is_active'] != 't':
                    if not row['is_agent'] and row['is_agent'] != 't':
                        servers = servers + row['object']
                    else:
                        agents = agents + row['object']
                else:
                    objs = objs + row['label']

        if agents:
            msg = gettext(
                "Could not generate chart for the following agents.\n(They "
                "are no longer registered with the Postgres Enterprise Manage)"
            )
            msg += agents
        if servers != '':
            msg += gettext(
                "Could not generate chart for the following database "
                "servers:\n(They are no longer monitored by the Postgres "
                "Enterprise Manage)"
            )
            msg += servers
        if objs != '':
            msg += gettext(
                "Insufficient information is available to generate the chart "
                "for the following metrices:"
            )
            msg += objs

        return make_json_response(
            data={
                'options': {
                    'separators': {
                        'xval': ctime, 'xlabel': 'extrapolated data',
                        'show': True, 'xcolor': '#FF0000', 'lineWidth': 1
                    }
                },
                'series': series, 'success': success, 'error': msg,
                'timeout': self.settings.get('timeout', 1800000),
                'spreadsheet': self.show_data_tab
            })

    def data(self, *args, **kwargs):
        self.initialize()
        return self.cmline_get_data()

    def data_with_timespan(self, *args, **kwargs):
        self.initialize()

        # Get agent id
        if self.sid is not None:
            self.aid = self.get_agent_id(self.sid)
        self.get_params()

        # Get start and end time
        results = self.get_start_end_time()
        self.stime = results[0]['stime']
        self.etime = results[0]['etime']
        return self.cmline_get_data()

    def get_settings(self, *args, **kwargs):
        res = self.get_chart_settings()
        return make_json_response(
            data=res
        )

    def set_settings(self, *args, **kwargs):
        return self.set_chart_settings(*args, **kwargs)
