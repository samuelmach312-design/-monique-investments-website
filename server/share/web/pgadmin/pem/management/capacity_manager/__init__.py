##########################################################################
#
# Postgres Enterprise Manager
#
# Copyright (C) 2016 - 2025, EnterpriseDB Corporation. All rights reserved.
#
##########################################################################

"""Implements Capacity Manager
    Purpose: Generates a Capacity Manager report as per the input given to
      PEM client

    Parameters:
      report_title - Title of the report.
      chart_type   - Type of chart (0: graph, 1: table, 2:both)
      chart_style  - Style of chart (1: individual, 0: comparative)
      start        - Start date
      current      - Current date
      end          - End date or threshold parameters separated by ','
      metric_count - Count of metrics to be computed
      metric_%d    - List of parameters defining a metric separated
                    by ','
      download_file- 1 if you want to download a file,
                    0/null otherwise
      filename     - name of the file to be downloaded as. (For
                    web-client only)
"""

import time
from flask import render_template, request
from flask_babel import gettext
from flask import jsonify
from pgadmin.utils.ajax import bad_request, success_return,\
    make_json_response, internal_server_error
from pgadmin.utils import PgAdminModule
from pgadmin.utils.csrf import pgCSRFProtect
from flask import Response, url_for
from flask_security import login_required
from pgadmin.pem.utils import get_params, get_default_stylesheets
import json
from flask import session
import os
import logging
import config
from .utils.cm_linecharts import linechart_capacity_manager_metric, \
    linechart_capacity_manager_report
from pgadmin.pem.monitor.dashboard.utils import cancel_dashboard
from pgadmin.pem.utils.role import PEMRole
from io import open
from pgadmin.pem.utils import datetimeFromPGISOString
from pgadmin.browser import BROWSER_INDEX

MODULE_NAME = 'capacity_manager'

cmRole = PEMRole(
    'pem_comp_capacity_manager', gettext('Capacity manager'),
    gettext('Capacity manager'),
    gettext('Privilege to generate the capacity manager report.')
)


class CapacityManagerModule(PgAdminModule):
    """
    class CapacityManagerModule(PgAdminModule):

        It is a wizard which inherits PgAdminModule
        class and define methods to load its own
        javascript file.
    """

    LABEL = gettext('Capacity Manager')

    def get_own_stylesheets(self):
        """
        Returns:
            list: the stylesheets used by this module.
        """
        stylesheets = [
            url_for('management.static', filename='css/management.css')
        ]
        return stylesheets

    def get_exposed_url_endpoints(self):
        """
        Returns:
            list: a list of url endpoints exposed to the client.
        """
        return ['capacity_manager.init_report',
                'capacity_manager.get_report_data',

                'capacity_manager.download_report',
                'capacity_manager.close'
                ]


# Create blueprint for Manage Probes class
blueprint = CapacityManagerModule(
    MODULE_NAME, __name__,
    static_url_path='', url_prefix="/pem/capacity_manager"
)


@blueprint.route("/")
@login_required
def index():
    return bad_request(errormsg=gettext(
        "This URL cannot be called directly!")
    )


@blueprint.route('/report/init/<int:trans_id>', methods=["GET", "POST"],
                 endpoint='init_report')
@pgCSRFProtect.exempt
@login_required
@cmRole.check_role(
    gettext(
        "Logged-in user do not have permission to generate "
        "capacity manager report."
    )
)
def init_report(trans_id):
    """
    This function is responsible for returning HTML data for Charts.
    Returns: HTML data for Charts.

    """
    if 'capacity_manager_metrics' not in session:
        capacity_manager_metrics = session['capacity_manager_metrics'] = dict()
    else:
        capacity_manager_metrics = session['capacity_manager_metrics']

    if request.method == "POST":
        # update session with chart data.
        capacity_manager_metrics[trans_id] = request.json or json.loads(
            request.data.decode())
        return success_return()

    params = capacity_manager_metrics.get(trans_id, None)

    if not params:
        return bad_request(gettext("No metrics found."))

    js_files = []

    js_paths = [
        os.path.realpath('{}{}'.format(os.path.dirname(
            os.path.realpath(__file__)),
            '/../../static/js/generated/reports/capacity_manager_report.js'))
    ]

    for js_path in js_paths:
        f = open(js_path, "r", encoding='utf-8')
        js_files.append(f.read())

    download_file = int(params['download_file'])

    data_url = ''
    if download_file != 2:
        data_url = url_for('capacity_manager.get_report_data',
                           trans_id=trans_id)
    report_data = {
        'report_time': time.strftime("%Y-%m-%d %H:%M:%S"),
        'trans_id': trans_id,
        'chart_style': int(params['chart_style']),
        'metrices': json.loads(params['metrices']),
        'download_file': download_file,
        'data_url': data_url,
        'data_set': '',
        'labels': {
            'generated_on': 'Generated On',
            'go_to_text': 'Go To'
        }
    }
    return Response(render_template(
        'capacity_manager/html/report.html',
        js_files=js_files,
        report_data=report_data),
        mimetype='text/html')


@blueprint.route('/report/download/<int:trans_id>', methods=["GET"],
                 endpoint='download_report')
@pgCSRFProtect.exempt
@login_required
@cmRole.check_role(
    gettext(
        "Logged-in user do not have permission to download "
        "capacity manager report."
    )
)
def download_report(trans_id):
    """
    This function is responsible for Download report.
    Embeds required JS and CSS files.
    Returns: report in HTML/JSON format

    """
    params = session['capacity_manager_metrics'].get(trans_id, None)
    # report downloading requires access to cookie on js side, do not set
    # httponly to True, or else download report will not work properly
    if not params:
        r = bad_request(gettext("No metrics found."))
        r.set_cookie(
            request.args['cookie_id'], value='-1',
            path=url_for(BROWSER_INDEX),
            secure=config.SESSION_COOKIE_SECURE,
            samesite=config.SESSION_COOKIE_SAMESITE
        )
        return r

    destination_file = \
        f"{params.get('destination_file')}.{params.get('report_type')}"

    # We will try to encode report file name with latin-1
    # If it fails then we will fallback to default ascii file name
    # werkzeug only supports latin-1 encoding supported values
    try:
        tmp_file_name = destination_file
        tmp_file_name.encode('latin-1', 'strict')
    except UnicodeEncodeError:
        if params.get('report_type') == 'html':
            destination_file = "capacity_manager_report_error.html"
        else:
            destination_file = "capacity_manager_report_error.json"

    try:
        status, data = prepare_report_data(trans_id)

        if not status:
            raise RuntimeError(gettext("Unknown transaction id"))

        download_file = int(params['download_file'])

        data_url = ''

        if params.get('report_type') == 'html':
            js_files = []
            f = '/../../static/js/generated/reports/capacity_manager_report.js'
            js_paths = [
                os.path.realpath('{}{}'.format(os.path.dirname(
                    os.path.realpath(__file__)), f
                ))
            ]

            for js_path in js_paths:
                f = open(js_path, "r", encoding='utf-8')
                js_files.append(f.read())
            report_data = {
                'report_time': time.strftime("%Y-%m-%d %H:%M:%S"),
                'trans_id': trans_id,
                'report_metadata': {
                    'chart_style': int(params['chart_style']),
                    'report_title': params['report_title'],
                    'chart_type': int(params.get('chart_type', 0)),
                },
                'metrices': json.loads(params['metrices']),
                'download_file': download_file,
                'data_url': data_url,
                'chart_data': data['chart_data'],
                'labels': {
                    'generated_on': 'Generated On',
                    'go_to_text': 'Go To'
                }
            }
            return render_template(
                'capacity_manager/html/report.html',
                js_files=js_files,
                report_data=report_data)
        elif params.get('report_type') == 'json':
            response = jsonify({
                'trans_id': trans_id,
                'report_time': time.strftime("%Y-%m-%d %H:%M:%S"),
                'download_file': download_file,
                'data_url': data_url,
                'report_title': params['report_title'],
                'data_set': data
            })
        else:
            raise ValueError('Invalid report type')

        # Validate the request before setting up the cookie
        # Iframe request does not send any content type
        if request.args.get("Content-Type") is None:
            response.headers["Content-Disposition"] = \
                "attachment;filename=" + destination_file
            # report downloading requires access to cookie on js side, do not
            # set httponly to True, or else download report will not work
            # properly
            response.set_cookie(
                request.args['cookie_id'], value='0',
                path=url_for(BROWSER_INDEX),
                secure=config.SESSION_COOKIE_SECURE,
                samesite=config.SESSION_COOKIE_SAMESITE
            )
        return response
    except Exception as e:
        # 'logging' is important here as we are handling generic exception.
        # Also at the same time we need to let client know that something
        # went wrong while generating report by sending '-1' in cookie so
        # that client side can unblock.
        # Without cookie value either 0 or -1 client side will never
        # unblock.
        # Log the actual exception traceback with message str(e) as
        # heading.
        logging.exception(str(e), exc_info=True)

        msg = gettext(
            'Error occurred while generating capacity manager report.'
        )

        r = internal_server_error(errormsg=msg)
        # report downloading requires access to cookie on js side, do not set
        # httponly to True, or else download report will not work properly
        r.set_cookie(
            request.args['cookie_id'], value='-1',
            path=url_for(BROWSER_INDEX),
            secure=config.SESSION_COOKIE_SECURE,
            samesite=config.SESSION_COOKIE_SAMESITE
        )
        return r


@blueprint.route('/data/<int:trans_id>', methods=["GET"],
                 endpoint='get_report_data')
@pgCSRFProtect.exempt
@login_required
@cmRole.check_role(
    gettext(
        "Logged-in user do not have permission to view "
        "capacity manager report."
    )
)
def get_report_data(trans_id):
    """
    This function is responsible for returning the Chart Layout
    generated using generate_markup method. It is called from
    report_show.html template file.

    Returns: Report Layout

    """

    status, res = prepare_report_data(trans_id)

    if not status:
        if res is None:
            res = gettext('Not a validate transaction')
        return bad_request(res)

    return make_json_response(data=res)


def prepare_report_data(trans_id):
    """
    This function is responsible for generating Markup/Layout
    for Charts.
    Args:
        trans_id: Configuration parameters required for report
        generation.
    Returns: HTML Markup for Charts

    """

    if 'capacity_manager_metrics' not in session:
        return False, None

    capacity_manager_metrics = session['capacity_manager_metrics']

    params = capacity_manager_metrics.pop(trans_id, None)

    if params is None:
        return False, None

    required_args = [
        'metrices', 'aggregation', 'chart_style', 'start_time',
        'end_time', 'current_time', 'chart_type'
    ]

    # don't allow empty value in required fields
    # chart_style and chart_type can have value as 0
    for arg in required_args:
        if arg not in params or (not params[arg] and arg not in
                                 ('chart_style', 'chart_type')
                                 ):
            return False, gettext("Could not find the required "
                                  "parameter (%s)." % arg)

    # Global variables (can be tweaked as per requirement)
    required_points = get_params('cm_data_points_per_report')

    if required_points is not None:
        required_points = 50

    # Check the parameters
    chart_style = int(params.get('chart_style', 0))
    start_date = params['start_time']
    current_date = params['current_time']
    end_value = params['end_time']
    metrices = json.loads(params['metrices'])
    threshold_index = int(params.get('threshold_index', 0))
    threshold_opr = params.get('threshold_opr')
    threshold_value = params.get('threshold_value')
    metric_count = len(metrices)

    threshold_data = None
    if threshold_index:
        threshold_data = [threshold_index, threshold_value, threshold_opr]

    report_data = {
        'report_metadata': {
            'chart_style': chart_style,
            'report_title': params['report_title'],
            'chart_type': int(params.get('chart_type', 0)),
            'metric_count': metric_count,
        },
        'chart_data': [],
        'labels': {
            'generated_on': 'Generated On',
            'go_to_text': 'Go To'
        }
    }

    import datetime
    import pytz

    current_epoch = \
        (
            datetimeFromPGISOString(current_date) -
            datetime.datetime.utcfromtimestamp(0).replace(
                tzinfo=pytz.timezone('utc')
            )
        ).total_seconds()

    # for json report not considering chart_style=1
    if chart_style == 1 and params['report_type'] != 'json':
        for x, row in enumerate(metrices):
            options = {
                'option': 'LoadCapacityManagerLineChartMetric',
                'start': start_date,
                'current': current_date,
                'current_epoch': current_epoch * 1000,
                'end': end_value,
                'required_points': required_points,
                'metric': row,
                'yaxis': row['metric_info']['unit'],
                'threshold_index': threshold_index,
                'threshold_opr': threshold_opr,
                'threshold_value': threshold_value,
            }

            chart_data = linechart_capacity_manager_metric(
                start_date, current_date,
                end_value, required_points,
                row
            )

            report_data['chart_data'].append({
                'colors': [chart['color'] for chart in chart_data if
                           'color' in chart],
                'metadata': options,
                'series': chart_data,
                'label': '{} ({})'.format(
                    options['metric']['label'],
                    options['metric']['metric_info']['metric_object'])
            })
    else:
        metric_count = len(metrices)

        options = {
            'option': 'LoadCapacityManagerLineChart',
            'start': start_date,
            'current': current_date,
            'current_epoch': current_epoch * 1000,
            'end': end_value,
            'metric_count': metric_count,
            'required_points': required_points,
            'metrics': metrices,
            'yaxis': '',  # don't display yaxis label for combined metric chart
            'threshold_index': threshold_index,
            'threshold_opr': threshold_opr,
            'threshold_value': threshold_value,
        }

        # signature references needs to be resolved
        try:
            chart_data = linechart_capacity_manager_report(
                start_date, current_date, end_value,
                required_points, metrices, threshold_data
            )
        except Exception as e:
            chart_data = e
        report_data['labels'] = {
            'generated_on': 'Generated On',
            'go_to_text': 'Go To'
        }
        report_data['chart_data'].append({
            'colors': [chart['color'] for chart in chart_data if
                       'color' in chart],
            'metadata': options,
            'series': chart_data,
            'label': 'All metrics',
        })
        # Transform the report data wrt json format
        if params['report_type'] == 'json':
            report_data = prepare_report_data_json(report_data)

    return True, report_data


def prepare_report_data_json(report_data):

    """
    this function is used to transform and clean the data to generate
    json report
    """

    del report_data['report_metadata']
    chart_data = report_data['chart_data']

    for data in chart_data:
        if 'yaxis' in data['metadata']:
            del data['metadata']['yaxis']
        metrics_data = data['metadata']['metrics']
        series_data = data['series']
        for metrics, series in zip(metrics_data,series_data):
            metrics.update({'series': series})
            metrics['keys'] = {key: val for key, val in zip(
                metrics['met_keys'], metrics['met_values'])}
            metrics['keys'].update(
                {'server_name':
                    metrics['metric_info']['metric_object'].strip(
                        '"').split('/')[0]})

            # Deleting the keys which are not necessary
            del_keys = ['pit', 'pit_def', 'label',
                        'sub_count', 'chart_style', 'params',
                        'version', 'met_values', 'met_keys', '_id', '_label']
            for del_key in del_keys:
                if del_key in metrics['metric_info']:
                    del metrics['metric_info'][del_key]
                if del_key in metrics:
                    del metrics[del_key]
        del data['colors']
        del data['series']

    report_data['chart_data'] = chart_data

    return report_data


@blueprint.route(
    '/close/<int:trans_id>',
    methods=['get'], endpoint='close'
)
@pgCSRFProtect.exempt
@login_required
@cmRole.check_role(
    gettext(
        "Logged-in user do not have permission to cancel capacity "
        "manager report generation."
    )
)
def report_cancel(trans_id):
    """Cancel the report generation transactions if running."""
    if trans_id == 0 or trans_id is None:
        return bad_request(
            errormsg=gettext(
                'Could not close the report panel.'
            )
        )
    return cancel_dashboard(trans_id)
