##########################################################################
#
# Postgres Enterprise Manager
#
# Copyright (C) 2016 - 2025, EnterpriseDB Corporation. All rights reserved.
#
##########################################################################
""" Implements capacity manager table graph functionality """

from flask_babel import gettext
from flask import current_app, render_template

from pgadmin.pem.utils import get_config_by_name
from pgadmin.pem.utils import pem_connection
from pgadmin.pem.misc.error import error_return, PEMErrorType, PEMChartStatus
from pgadmin.pem.monitor.dashboard.utils.chart_constant import PEMChartFunc
from pgadmin.pem.monitor.dashboard.utils.\
    generate_table_chart_data import generate_json_for_table_chart
from pgadmin.utils.ajax import make_json_response
from .utils import ChartView
from .tablegraph import TableGraph
from xml.etree.ElementTree import Element, SubElement
from pgadmin.pem.misc.error import error_return, PEMErrorType, \
    PEMChartStatus, prettify
from datetime import datetime


class CMTableGraph(ChartView):
    """
    This class has capacity manager's table graph functionality like initialize
    chart data, fetch_chart_info etc..
    """
    chart_label = 'cmtable'
    chart_type = 'CT'

    def __init__(self, *args, **kwargs):
        super(CMTableGraph, self).__init__(*args, **kwargs)

        # Graph configuration settings
        self.show_points = get_config_by_name('show_data_points_on_graph')
        self.show_data_tab = get_config_by_name('show_data_tab_on_graph')
        self.shadow_size = 4
        self.dashboard_transaction = None
        self.sort_seq = None
        self.dep_probes = None

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
        super(CMTableGraph, self).initialize(
            self.chart_label, pem_conn, *args, **kwargs
        )
        self.f_type = self.chart['func_type']    # PYTHON or QUERY Function

    @pem_connection
    def fetch_chart_info(self, pem_conn=None):
        """
        This function fetches the table graph information for capacity manager
         from charts/sql/cmtable/info.sql and returns the response data
        :param pem_conn: PEM database connection object
        :return: chart information
       """
        return super(CMTableGraph, self).fetch_chart_info(
            pem_conn, self.chart_label
        )

    @pem_connection
    def data(self, pem_conn=None, *args, **kwargs):
        self.initialize()
        self.get_dep_probes()

        # Get agent id
        if self.sid is not None:
            self.aid = self.get_agent_id(self.sid)
        self.get_params()

        if self.f_type in [PEMChartFunc.PYTHON, PEMChartFunc.QUERY]:
            error_return(
                gettext(
                    "We do not support a function based data generation for "
                    "other than the system function/QUERY.\nPlease contact "
                    "EnterpriseDB support team for this error."
                ),
                e_type=PEMErrorType.JSON, status_code=501
            )
        elif self.f_type is not None:
            # Hmm - we don't support any other chart-function type
            error_return(
                gettext(
                    "We do not support a function based data generation for "
                    "other than the system function/QUERY.\nPlease contact "
                    "EnterpriseDB support team for this error."
                ),
                e_type=PEMErrorType.JSON, status_code=501
            )
        elif self.ctype == 'CT' and self.chart_label == 'cmtable':
            return self.cmtable_get_data()
        else:
            return self.data_view()

    @pem_connection
    def get_chart_settings(self, pem_conn=None):
        sql = render_template(
            'charts/sql/cmtable/get_settings.sql'
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
                gettext(
                    "Couldn't find the chart settings for this chart."
                ), PEMErrorType.JSON, status_code=503
            )

        res = {}
        idx = 0
        for row in dbRes['rows']:
            if idx == 0:
                res['type'] = row['type']
                res['timeout'] = row.get('timeout', 300000)
                res['did'] = row['did']
                res['level'] = row['level']

                # Fetch all the labels and store them in result.
                res['labels'] = {}
                if row['labels']:
                    for i in range(1, len(row['labels'])):
                        res['labels'][i] = row['labels'][i]

                try:
                    res['sortseq'] = row['sortseq']
                    if row['points'] is not None:
                        res['max_rows'] = row['points']
                except Exception:
                    pass

                if row['name'].lower() == 'alert details':
                    res['showackalerts'] = row['showackalerts']
                idx += 1
            elif res['type'] != 'TB':
                if row['clname']:
                    res['colors'][row['clname']] = row['clval']
        return res

    def get_settings(self, *args, **kwargs):
        res = self.get_chart_settings()
        return make_json_response(
            data=res
        )

    def set_settings(self, *args, **kwargs):
        return self.set_chart_settings(*args, **kwargs)

    @pem_connection
    def cmtable_get_data(self, pem_conn=None, *args, **kwargs):
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
            status, res = pem_conn.execute_2darray(query, [self.cid])

        if 'rows' in res:
            meta_res = res['rows']
        meta = {}
        for row in meta_res:
            meta[row['idx']] = {
                'label': row['label'],
                'is_agent': row['is_agent'], 'object': row['object'],
                'is_active': row['is_active'], 'color': row['color'],
                'data_present': False
            }

        # Save dashboard transaction id
        with self.dashboard_transaction:
            status, ctime = pem_conn.execute_scalar(
                "SELECT (EXTRACT(EPOCH FROM now()) * 1000)::numeric(40, 0)"
            )

        query = """SELECT idx, rtime, value
                    FROM pem.generate_cm_chart_data((%s)::int4)
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

        prev_idx = None
        data = []
        label = ''
        series = []
        for row in rs:
            if prev_idx != row['idx']:
                if prev_idx is not None:
                    series.append({
                        'data': data, 'label': label,
                        'points': {'show': self.show_points},
                        'shadowSize': self.shadow_size
                    })
                    data = []
                if row['idx'] in meta:
                    label = meta[row['idx']]['label']
                    meta[row['idx']]['data_present'] = True
                else:
                    label = 'M#' + row['idx']

                prev_idx = row['idx']
            data.append([row['rtime'], row['value']])
        if prev_idx is not None:
            series.append({
                'data': data, 'label': label,
                # 'color': color,
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

        return self.view_table(
            series, success, msg
        )

    def view_table(
        self, series, success, msg
    ):
        columns = [{'id': 'Recorded Time', 'label': 'Recorded Time',
                    'type': 'timestamp'}]

        # Add other columns to the list
        for col in series:
            columns.append(
                {'id': col['label'], 'label': col['label'], 'type': 'text'})

        # Initialize data as a list
        data = []

        rows = len(series[0]['data']) if len(series) > 0 else 0

        for i in range(rows):
            row = {}
            timestamp = datetime.strptime(
                series[0]['data'][i][0][:19],
                '%Y-%m-%d %H:%M:%S')
            epoch_time = timestamp.timestamp()

            # Add the Recorded Time to the row dictionary
            row['Recorded Time'] = epoch_time

            # Add each column's data to the row dictionary
            try:
                for col in series:
                    label = col['label']
                    value = col['data'][i][1]
                    row[label] = value
            except Exception as e:
                pass

            # Append the row dictionary to the data list
            data.append(row)
        result = {
            'is_nested': False,
            'columns': columns,
            'data': data,
            'error': msg,
        }
        return make_json_response(data=result)
