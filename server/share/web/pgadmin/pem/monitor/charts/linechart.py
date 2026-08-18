##########################################################################
#
# Postgres Enterprise Manager
#
# Copyright (C) 2016 - 2025, EnterpriseDB Corporation. All rights reserved.
#
##########################################################################
""" Implements line chart functionality """

import json

from flask import current_app, request, render_template
from flask_babel import gettext

from pgadmin.pem.misc.error import error_return, PEMErrorType, \
    PEMChartStatus
from pgadmin.pem.monitor.dashboard.helpers.chart import \
    get_chart_probe_dependency, whichColor
from pgadmin.pem.utils import ChartMetricParam, pem_connection
from pgadmin.pem.utils import get_config_by_name
from pgadmin.utils.ajax import make_json_response
from . import utils


class LineChart(utils.ChartView):
    """
    This class has line chart related functionality like initialize chart
    settings, get_chart_settings etc..
    """
    chart_label = 'line'
    chart_type = 'L'
    suffix = 'stime/<start_time>/etime/<end_time>'

    def __init__(self, *args, **kwargs):
        super(LineChart, self).__init__(*args, **kwargs)

        # Graph configuration settings
        self.show_points = get_config_by_name('show_data_points_on_graph')
        self.show_data_tab = get_config_by_name('show_data_tab_on_graph')
        self.shadow_size = 0
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
        # initialize some settings from super class
        super(LineChart, self).initialize(
            self.chart_label, pem_conn, *args, **kwargs
        )

        self.fid = self.chart['fid']             # Id of the Chart functions
        self.c_func = self.chart['func']
        self.metadata = dict(self.chart)

        self.dep_probes_params["agent"] = self.aid
        self.colors = self.chart['colors']

    @pem_connection
    def get_chart_settings(self, pem_conn=None):
        """
        This function gets the chart settings from super class's method
        :param pem_conn: pem database connection
        :return: chart settings
        """
        return super(LineChart, self).get_chart_settings(pem_conn,
                                                         self.chart_label)

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
        return super(LineChart, self).set_settings_for_chart(
            req, level, pem_conn)

    @pem_connection
    def fetch_chart_info(self, pem_conn):
        """
        This function fetches the line chart information from
        charts/sql/line/info.sql and returns the response data
        :param pem_conn: PEM database connection object
        :return: chart information
        """
        return super(LineChart, self).fetch_chart_info(pem_conn,
                                                       self.chart_label)

    @pem_connection
    def render_as_agg_metrics(self, pem_conn=None):
        """ Generate chart data if function type is AGGREGATION """
        params = []
        result = {}
        dep_probes = None

        # We may need to display somelevel dashboards in some other
        # level charts. For example, in server level dashboard we need
        # to display agent level's DISK I/O.

        if self.level not in self.levels:
            self.level = self.lowest_supported_level

        params.append(self.cid)
        params.append(self.did)
        params.append(self.aid)
        params.append(self.sid)
        params.append(self.database)
        params.append(self.schema)
        params.append(self.table)
        params.append(self.level)
        params.append(self.show_system_objects)
        params.append(self.stime)
        params.append(self.etime)

        query = render_template(
            'charts/sql/line/generate_metric_chart_data.sql'
        )

        with self.dashboard_transaction:
            status, rs = pem_conn.execute_2darray(query, params)

        if status is False:
            current_app.logger.warning(
                'Failed to execute the line metric generation logic for the'
                ' chart (id#{0}) with error - {1}'.format(
                    self.cid, rs
                )
            )
            error_return(
                gettext(
                    'Failed to execute the line metric generation logic for '
                    'the chart (id#{0}) with error - {1}'
                ).format(self.cid, rs), e_type=PEMErrorType.JSON
            )

        if 'rows' in rs:
            rs = rs['rows']

        # Fetch the information about the chart from the database
        query = render_template(
            'charts/sql/line/get_chart_metric.sql'
        )

        with self.dashboard_transaction:
            status, res = pem_conn.execute_dict(query, [self.cid])

        if not status:
            current_app.logger.warning(
                'Failed to fetch the probe dependency of the'
                ' chart (id#{0}) with error - {1}'.format(
                    self.cid, self.dep_probes_warning
                )
            )
            error_return(
                gettext(
                    'Failed to fetch the probe dependency'
                    ' of the chart (id#{0}) in the'
                    ' Postgres Enterprise Manager Server database'
                ).format(self.cid), e_type=PEMErrorType.JSON
            )

        if 'rows' in res and len(res['rows']) > 0:
            dep_probes = res['rows'][0]['dep_probes']

        dep_probes_warning = None
        ret_status = None

        if dep_probes:
            # Check the probe dependency
            self.dep_probes_params['probes'] = tuple(dep_probes)
            if self.sid:
                self.dep_probes_params['server'] = self.sid
            if self.database:
                self.dep_probes_params['database'] = self.database
            ret_status, dep_probes_warning = get_chart_probe_dependency(
                self.cid, self.dep_probes_params, self.dashboard_transaction,
                pem_conn
            )

            if ret_status == PEMChartStatus.ERROR:
                current_app.logger.warning(
                    'Failed to fetch the probe dependency of the chart '
                    '(id#{0}) with error - {1}'.format(
                        self.cid, dep_probes_warning
                    )
                )
                error_return(
                    gettext(
                        'Failed to fetch the probe dependency of'
                        'the chart (id#{0}) in the Postgres Enterprise Manager'
                        'Server database'
                    ).format(self.cid), e_type=PEMErrorType.JSON
                )

        series = []
        chart_colors = []
        if len(rs) == 0:
            error_return(
                gettext("Not enough data is available to render the chart.") +
                dep_probes_warning if dep_probes_warning else "",
                e_type=PEMErrorType.JSON,
                status_code=200,
                probe_error=bool(dep_probes_warning)
            )
        else:
            prevIdx = None
            data = []
            label = ''
            color = ''

            result.update({'success': ret_status or PEMChartStatus.SUCCESS})
            result.update({'error': dep_probes_warning})

            for row in rs:
                if row['o_idx'] == -1:
                    if row['o_label'] == '101':
                        result['success'] = PEMChartStatus.ERROR
                        result['error'] = gettext(
                            'Information for the chart is no longer '
                            'available. '
                            'It has been removed from the system.'
                        )
                    elif row['o_label'] == '102':
                        result['success'] = PEMChartStatus.ERROR
                        result['error'] = gettext(
                            'Couldn\'t fetch the required information.'
                            ' Dependent object is no longer available '
                            'in the system.'
                        )
                    elif row['o_label'] == '103':
                        result['success'] = PEMChartStatus.ERROR
                        result['error'] = gettext(
                            'Couldn\'t find the agent information '
                            'required to generate data for this chart.'
                        )
                    elif row['o_label'] == '104':
                        result['success'] = PEMChartStatus.ERROR
                        result['error'] = gettext(
                            'Couldn\'t find the server information '
                            'required to generate data for this chart.'
                        )
                    elif row['o_label'] == '105':
                        result['success'] = PEMChartStatus.ERROR
                        result['error'] = gettext(
                            'This database server is not bound to any '
                            'agent.'
                        )
                    elif row['o_label'] == '106':
                        result['success'] = PEMChartStatus.ERROR
                        result['error'] = gettext(
                            'Couldn\'t find the server information '
                            'required to generate data for this chart.'
                        )
                    elif row['o_label'] == '114':
                        result['success'] = \
                            result['success'] or PEMChartStatus.INFO
                        result['error'] = gettext(
                            'Data for few metrics has not been '
                            'generated, because this database server '
                            'is monitored remotely.'
                        )
                    elif row['o_label'] == '115':
                        result['options'] = {
                            'separators': {
                                'xval': row['o_aggtime'][5:-1],
                                'xlabel': 'extrapolated data',
                                'show': True,
                                'xcolor': '#444444', 'lineWidth': 1
                            }
                        }
                    elif row['o_label'] == '116':
                        result['success'] = result[
                            'success'] or PEMChartStatus.WARNING
                        result['error'] = (
                            (result['error'] + ' ')
                            if result['error'] else '')
                        result['error'] += gettext(
                            'Not enough data is available to determine '
                            'the extrapolated threshold time.'
                        )
                    else:
                        rest_res = row['o_label'][5:5 + len(row['o_label'])]
                        tmp = row['o_label'][0:3]
                        if tmp == '107':
                            result['success'] = PEMChartStatus.ERROR
                            result['error'] = gettext(
                                "The probe - '{0}', to figure out the "
                                "extrapolated data, could not be found "
                                "from, or has been marked for deletion "
                                "in the Postgres Enterprise Manager "
                                "Server."
                            ).format(rest_res)
                        elif tmp == '108':
                            result['success'] = result['success'] | \
                                PEMChartStatus.WARNING
                            result['error'] = result['error'] + ' ' \
                                if result['error'] else ''
                            result['error'] += gettext(
                                "The probe - '{0}' could not be found "
                                "from, or has been marked for deletion "
                                "in the Postgres Enterprise Manager "
                                "Server."
                            ).format(rest_res)
                        elif tmp == '109':
                            result['success'] = result['success'] | \
                                PEMChartStatus.WARNING
                            result['error'] = result['error'] + ' ' \
                                if result['error'] else ''
                            result['error'] += gettext(
                                "The probe - '{0}' does not keep the "
                                "historical data!"
                            ).format(rest_res)
                        elif tmp == '110':
                            result['success'] = result['success'] | \
                                PEMChartStatus.WARNING
                            result['error'] = (result['error'] + ' ') \
                                if result['error'] else ''
                            result['error'] += gettext(
                                "Agent - '{0}' has been deleted."
                                " Data could not been generated "
                                "for it."
                            ).format(rest_res)
                        elif tmp == '111':
                            result['success'] = result['success'] | \
                                PEMChartStatus.WARNING
                            result['error'] = (result['error'] + ' ') \
                                if result['error'] else ''
                            result['error'] += gettext(
                                "Server - '{0}' has been deleted. "
                                "Data has not been generated for it."
                            ).format(rest_res)
                        elif tmp == '112':
                            result['success'] = PEMChartStatus.ERROR
                            result['error'] = gettext(
                                "Agent - '{0}', which is responsible "
                                "to determine extrapolated data"
                                " generation threshold time, has been "
                                "deleted from the Postgres Enterprise "
                                "Manager."
                            ).format(rest_res)
                        elif tmp == '113':
                            result['success'] = result['success'] | \
                                PEMChartStatus.WARNING
                            result['error'] = gettext(
                                "Server - '{0}', which is responsible "
                                "to determine extrapolated data "
                                "generation theshold time, has been "
                                "deletd from the Postgres Enterprise "
                                "Manager."
                            ).format(rest_res)
                        else:
                            result['success'] = PEMChartStatus.WARNING
                            result['error'] = gettext(
                                "Unknown error - '{0} returned during "
                                "generating data for this "
                                "chart."
                            ).format(row['o_label'])
                    continue
                elif prevIdx != row['o_idx']:
                    if prevIdx is not None:
                        series.append({
                            'data': data, 'label': label,
                            'color': color,
                            'points': {'show': self.show_points},
                            'shadowSize': self.shadow_size
                        })
                        data = []
                        chart_colors.append(color)
                    if len(row) > 1 and row['o_label']:
                        label = row['o_label']
                    else:
                        label = 'M#' + row['o_idx']
                    color = whichColor(row['o_idx'] - 1, label,
                                       self.colors, self.settings)
                    prevIdx = row['o_idx']
                    data.append([row['o_aggtime'], row['o_aggval']])
                else:
                    data.append([row['o_aggtime'], row['o_aggval']])
            if prevIdx is not None:
                series.append({
                    'data': data, 'label': label,
                    'color': color, 'points': {'show': self.show_points},
                    'shadowSize': self.shadow_size
                })
                chart_colors.append(color)

        result['series'] = series
        result['colors'] = chart_colors
        result['timeout'] = self.settings.get('timeout', 1800000)
        result['downloadformat'] = self.settings.get('downloadformat')
        result['spreadsheet'] = self.show_data_tab

        return result

    @pem_connection
    def render_as_query(self, pem_conn=None):
        """ Generate chart data if function type is query """
        self.get_params()
        with self.dashboard_transaction:
            status, rs = pem_conn.execute_2darray(self.c_func, self.params,
                                                  True)
        if rs is None or len(rs) == 0:
            error_return(
                gettext(
                    "Not enough data is available to render"
                    " the chart. {0} "
                ) % self.dep_probes_warning, e_type=PEMErrorType.JSON,
                status_code=200)

        if 'rows' in rs:
            rs = rs['rows']
        result = {}
        series = []
        chart_colors = []
        prevIdx = None
        data = []
        label = ''
        color = ''

        result.update({'success': self.ret_status or PEMChartStatus.SUCCESS})
        result.update({'error': self.dep_probes_warning})
        for row in rs:
            row = list(row.values())
            if row[0] == -1:
                if row[1] == '101':
                    result['success'] = PEMChartStatus.ERROR
                    result['error'] = gettext(
                        'Information for the chart is no longer '
                        'available. '
                        'It has been removed from the system.'
                    )
                elif row[1] == '102':
                    result['success'] = PEMChartStatus.ERROR
                    result['error'] = gettext(
                        'Could not fetch the required information. '
                        'Dependent object is no longer available '
                        'in the system.'
                    )
                elif row[1] == '103':
                    result['success'] = PEMChartStatus.ERROR
                    result['error'] = gettext(
                        'Could not find the agent information '
                        'required to generate data for this chart.'
                    )
                elif row[1] == '104':
                    result['success'] = PEMChartStatus.ERROR
                    result['error'] = gettext(
                        'Could not find the server information '
                        'required to generate data for this chart.'
                    )
                elif row[1] == '105':
                    result['success'] = PEMChartStatus.ERROR
                    result['error'] = gettext(
                        'This database server is not bound to any '
                        'agent.'
                    )
                elif row[1] == '106':
                    result['success'] = PEMChartStatus.ERROR
                    result['error'] = gettext(
                        'Could not find the server information '
                        'required to generate data for this chart.'
                    )
                elif row[1] == '114':
                    result['success'] = \
                        result['success'] or PEMChartStatus.INFO
                    result['error'] = gettext(
                        'Data for few metrics has not been '
                        'generated, because this database server '
                        'is monitored remotely.'
                    )
                elif row[1] == '115':
                    result['options'] = {
                        'separators': {
                            'xval': row[2][5:-1],
                            'xlabel': 'extrapolated data',
                            'show': True,
                            'xcolor': '#444444', 'lineWidth': 1
                        }
                    }
                elif row[1] == '116':
                    result['success'] = result[
                        'success'] or PEMChartStatus.WARNING
                    result['error'] = (
                        (result['error'] + ' ')
                        if result['error'] else '')
                    result['error'] += gettext(
                        'Not enough data is available to determine '
                        'the extrapolated threshold time.'
                    )
                else:
                    rest_res = row[1][5:5 + len(row[1])]
                    tmp = row[1][0:3]
                    if tmp == '107':
                        result['success'] = PEMChartStatus.ERROR
                        result['error'] = gettext(
                            "The probe - '{0}', to figure out the "
                            "extrapolated data, could not be found "
                            "from, or has been marked for deletion "
                            "in the Postgres Enterprise Manager "
                            "Server."
                        ).format(rest_res)
                    elif tmp == '108':
                        result['success'] = result['success'] | \
                            PEMChartStatus.WARNING
                        result['error'] = result['error'] + ' ' \
                            if result['error'] else ''
                        result['error'] += gettext(
                            "The probe - '{0}' could not be found "
                            "from, or has been marked for deletion "
                            "in the Postgres Enterprise Manager "
                            "Server."
                        ).format(rest_res)
                    elif tmp == '109':
                        result['success'] = result['success'] | \
                            PEMChartStatus.WARNING
                        result['error'] = result['error'] + ' ' \
                            if result['error'] else ''
                        result['error'] += gettext(
                            "The probe - '{0}' does not keep the "
                            "historical data!"
                        ).format(rest_res)
                    elif tmp == '110':
                        result['success'] = result['success'] | \
                            PEMChartStatus.WARNING
                        result['error'] = (result['error'] + ' ') \
                            if result['error'] else ''
                        result['error'] += gettext(
                            "Agent - '{0}' has been deleted."
                            " Data could not been generated "
                            "for it."
                        ).format(rest_res)
                    elif tmp == '111':
                        result['success'] = result['success'] | \
                            PEMChartStatus.WARNING
                        result['error'] = (result['error'] + ' ') \
                            if result['error'] else ''
                        result['error'] += gettext(
                            "Server - '{0}' has been deleted. "
                            "Data has not been generated for it."
                        ).format(rest_res)
                    elif tmp == '112':
                        result['success'] = PEMChartStatus.ERROR
                        result['error'] = gettext(
                            "Agent - '{0}', which is responsible "
                            "to determine extrapolated data"
                            " generation theshold time, has been "
                            "deletd from the Postgres Enterprise "
                            "Manager."
                        ).format(rest_res)
                    elif tmp == '113':
                        result['success'] = result['success'] | \
                            PEMChartStatus.WARNING
                        result['error'] = gettext(
                            "Server - '{0}', which is responsible "
                            "to determine extrapolated data "
                            "generation theshold time, has been "
                            "deletd from the Postgres Enterprise "
                            "Manager."
                        ).format(rest_res)
                    else:
                        result['success'] = PEMChartStatus.WARNING
                        result['error'] = gettext(
                            "Unknown error - '{0} returned during "
                            "generating data for this "
                            "chart."
                        ).format(row[1])
                continue
            elif prevIdx != row[0]:
                if prevIdx is not None:
                    series.append({
                        'data': data, 'label': label,
                        'color': color,
                        'points': {'show': self.show_points},
                        'shadowSize': self.shadow_size
                    })
                    data = []
                    chart_colors.append(color)
                if row[1] is not None and row[1] != '':
                    label = row[1]
                else:
                    label = 'M#' + row[0]
                color = whichColor(row[0] - 1, label,
                                   self.colors, self.settings)
                prevIdx = row[0]

            if row[3] is not None:
                data.append([row[2], row[3]])

        if prevIdx is not None:
            series.append({
                'data': data, 'label': label, 'color': color,
                'points': {'show': self.show_points},
                'shadowSize': self.shadow_size
            })

        result['series'] = series
        result['colors'] = chart_colors
        result['timeout'] = self.settings['timeout'],
        result['spreadsheet'] = self.show_data_tab

        return result

    def data(self, *args, **kwargs):
        self.initialize()

        # Get agent id
        if self.sid is not None:
            self.aid = self.get_agent_id(self.sid)

        res = None

        if self.fid is None:
            res = self.render_as_agg_metrics()
        else:
            res = self.render_as_query()

        # Remove the function source (if exists)
        self.metadata.pop('func', None)
        res['metadata'] = self.metadata

        return make_json_response(
            data=res
        )

    def data_with_timespan(self, *args, **kwargs):
        self.initialize()

        # Get agent id
        if self.sid is not None:
            self.aid = self.get_agent_id(self.sid)

        # Get start and end time
        results = self.get_start_end_time()
        self.stime = results[0]['stime']
        self.etime = results[0]['etime']

        res = None
        if self.fid is None:
            res = self.render_as_agg_metrics()
        else:
            res = self.render_as_query()

        # Remove the function source (if exists)
        self.metadata.pop('func', None)
        res['metadata'] = self.metadata

        return make_json_response(
            data=res
        )

    def get_settings(self, *args, **kwargs):
        res = self.get_chart_settings()
        return make_json_response(
            data=res
        )

    def set_settings(self, *args, **kwargs):
        return self.set_chart_settings(*args, **kwargs)
