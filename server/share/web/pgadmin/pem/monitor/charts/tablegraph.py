##########################################################################
#
# Postgres Enterprise Manager
#
# Copyright (C) 2016 - 2025, EnterpriseDB Corporation. All rights reserved.
#
##########################################################################
""" Implements table chart functionality """

import json

from flask_babel import gettext
from flask import current_app, request, render_template
from xml.etree.ElementTree import Element, SubElement

from pgadmin.pem.utils import get_config_by_name
from pgadmin.pem.utils import pem_connection
from pgadmin.pem.monitor.utils import DashboardLevel
from pgadmin.pem.monitor.dashboard.utils.tablecharts import \
    table_global_overview_agent_status, table_global_overview_alerts_status, \
    table_global_overview_server_status, table_alerts_details, \
    table_alerts_errors, table_session_workload, table_io_object_index_io, \
    table_bdr_node_summary, table_bdr_workers, table_bdr_worker_errors

from pgadmin.pem.monitor.dashboard.helpers.chart import \
    get_chart_probe_dependency
from pgadmin.pem.misc.error import error_return, PEMErrorType, \
    PEMChartStatus, prettify, is_numeric
from pgadmin.pem.monitor.dashboard.utils.chart_constant import PEMChartFunc
from pgadmin.pem.monitor.dashboard.utils.\
    generate_table_chart_data import generate_json_for_table_chart
from pgadmin.utils.ajax import bad_request, make_json_response, \
    internal_server_error
from .utils import ChartView


class TableGraph(ChartView):
    """
    This class has table graph functionality  like initialise chart settings,
     get_chart_settings etc..
    """
    chart_label = 'table'
    chart_type = 'TB'
    supported_settings = ['sortseq', 'type', 'timeout', 'row', 'did']

    def __init__(self, *args, **kwargs):
        super(TableGraph, self).__init__(*args, **kwargs)

        # Graph configuration settings
        self.show_points = get_config_by_name('show_data_points_on_graph')
        self.show_data_tab = get_config_by_name('show_data_tab_on_graph')
        self.shadow_size = 4
        self.dashboard_transaction = None
        self.sort_seq = None
        self.sort_index = None
        self.sort_direction = None
        self.is_server_remotely_monitored = None

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
        super(TableGraph, self).initialize(
            TableGraph.chart_label, pem_conn, *args, **kwargs
        )
        self.f_type = self.chart['func_type']  # PYTHON or QUERY Function
        self.c_func = self.chart['func']
        self.is_position_based = self.chart['is_position_based']
        self.isvertical = self.chart['isvertical']
        self.tcType = self.chart['ttype']  # table-chart/line-chart type

        self.chart_row_limit = self.settings.get('max_rows', None)

    @pem_connection
    def fetch_chart_info(self, pem_conn=None):
        """
        This function fetches the line chart information from
        charts/sql/line/info.sql and returns the response data
        :param pem_conn: PEM database connection object
        :return: chart information
        """
        return super(TableGraph, self).fetch_chart_info(
            pem_conn, TableGraph.chart_label
        )

    @pem_connection
    def data(self, pem_conn=None, *args, **kwargs):
        self.initialize()

        # Get agent id
        if self.sid is not None:
            self.aid = self.get_agent_id(self.sid)

        self.get_dep_probes()
        self.get_params()
        html = None
        if self.f_type == PEMChartFunc.PYTHON:
            self.c_func = eval(self.c_func)
            if callable(self.c_func):
                self.params['timeout'] = self.settings['timeout']
                self.params['trans_id'] = self.trans_id
                try:
                    params = list(self.params.values())
                    res = self.c_func(*params)
                    return res
                except Exception as e:
                    current_app.logger.exception(e)
                    error_return(
                        gettext(
                            "Error generating the data for the "
                            "table ({0})\nERROR: \n"
                        ).format(self.name) + str(e), e_type=PEMErrorType.JSON,
                    )
            else:
                error_return(
                    gettext(
                        "The function ({0}), for generating the data for "
                        "the table ({1}), could not be found."
                    ).format(self.c_func, self.name), e_type=PEMErrorType.JSON
                )
        elif self.f_type == PEMChartFunc.QUERY:
            with self.dashboard_transaction:
                status, res = pem_conn.execute_dict(
                    self.c_func, self.params
                )

            if not status:
                error_return(
                    gettext(
                        "Error executing query: {0}"
                    ).format(res), e_type=PEMErrorType.JSON, status_code=500
                )
            # Convert the result into json
            msg = None
            response = generate_json_for_table_chart(res, table_id=self.cid)
            if response['data'] is None or len(response['data']) == 0:
                msg = gettext(
                    "Not enough data is available to generate the "
                    "table. {0}"
                ).format(self.dep_probes_warning)
            response['success'] = self.ret_status
            response['info_msg'] = msg or gettext(self.dep_probes_warning)
            response['timeout'] = self.settings['timeout']
            return make_json_response(data=response)
        elif self.f_type is not None:
            # Hmm - we don't support any other chart-function type
            error_return(
                gettext(
                    "We do not support a function based data generation for "
                    "other than the system function/QUERY.\nPlease contact "
                    "EnterpriseDB support team for this error."
                ),
                e_type=PEMErrorType.JSON
            )
        else:
            return self.data_view()

    @pem_connection
    def get_chart_settings(self, pem_conn=None):
        sql = render_template(
            'charts/sql/table/get_settings.sql'
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
                ), PEMErrorType.JSON
            )

        res = {}
        idx = 0
        for row in dbRes['rows']:
            # Fetch all the labels and store them in result.
            res['labels'] = {}
            if row['labels']:
                for i in range(1, len(row['labels'])):
                    res['labels'][i] = row['labels'][i]

            for setting in self.supported_settings:
                if setting in row:
                    res[setting] = row[setting]

            if row['name'].lower() == 'alert details':
                res['showackalerts'] = row['showackalerts']
            break
        return res

    def get_settings(self, *args, **kwargs):
        res = self.get_chart_settings()
        return make_json_response(
            data=res
        )

    def set_settings(self, *args, **kwargs):
        return self.set_chart_settings(*args, **kwargs)


class AlertDetailsGraph(TableGraph):
    chart_label = 'alert'
    chart_type = 'AD'
    supported_settings = ['sortseq', 'type', 'timeout', 'showackalerts']


class AlertErrorsGraph(TableGraph):
    chart_type = 'AE'
    chart_label = 'alert_errors'


class AlertStatusGraph(TableGraph):
    chart_type = 'AS'
    chart_label = 'alert_status'


class PGDWorkersGraph(TableGraph):
    chart_type = 'PW'
    chart_label = 'pgd_workers'


class AgentStatusGraph(TableGraph):
    chart_type = 'AG'
    chart_label = 'agent_status'


class ServerStatusGraph(TableGraph):
    chart_type = 'SS'
    chart_label = 'server_status'
