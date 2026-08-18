##########################################################################
#
# Postgres Enterprise Manager
#
# Copyright (C) 2016 - 2025, EnterpriseDB Corporation. All rights reserved.
#
##########################################################################

"""Implements Log Analysis Expert"""
import logging
import traceback
import os
import ast
import config
import random
import json
from flask import Response, render_template, request, url_for, session
from flask_babel import gettext
from pgadmin.utils.ajax import internal_server_error, bad_request,\
    make_json_response, make_response, gone, success_return
from pgadmin.utils.csrf import pgCSRFProtect
from pgadmin.utils import PgAdminModule
from flask_security import login_required
from pgadmin.pem.utils import pem_connection, current_datetime,\
    pem_dedicated_connection
from .utils.pglogexp_charts import fetch_chart_data, build_chart
from .utils import get_bundled_css, get_bundled_js
from werkzeug.exceptions import BadRequest
from pgadmin.pem.utils.role import PEMRole

# Async Constants
ASYNC_OK = 1
ASYNC_READ_TIMEOUT = 2
ASYNC_WRITE_TIMEOUT = 3
ASYNC_NOT_CONNECTED = 4
ASYNC_EXECUTION_ABORTED = 5


MODULE_NAME = 'log_analysis_expert'

REPORT_STORAGE_ROOT = os.path.join(
    config.DATA_DIR, 'pglogexp'
)

logAnalysisExpertRole = PEMRole(
    'pem_comp_log_analysis_expert', gettext('Postgres log analysis expert'),
    gettext('Postgres log analysis expert'),
    gettext(
        'Priviledge to generate the Postgres log analysis expert report.'
    )
)


class LogAnalysisExpertModule(PgAdminModule):
    """
    class LogAnalysisExpertModule(PgAdminModule):

        It is a wizard which inherits PgAdminModule
        class and define methods to load its own
        javascript file.
    """

    LABEL = gettext('Postgres Log Analysis Expert')

    def get_own_stylesheets(self):
        """
        Returns:
            list: the stylesheets used by this module.
        """
        stylesheets = [
            url_for('management.static', filename='css/management.css'),
            url_for('log_analysis_expert.static',
                    filename='css/log_analysis_expert.css')
        ]
        return stylesheets

    def get_exposed_url_endpoints(self):
        """
        Returns:
            list: a list of url endpoints exposed to the client.
        """
        return ['log_analysis_expert.analyzers_list',
                'log_analysis_expert.server_list',
                'log_analysis_expert.init_report',
                'log_analysis_expert.download_report',
                'log_analysis_expert.open_report',
                'log_analysis_expert.cancel_report',
                'log_analysis_expert.poll_report',
                ]


blueprint = LogAnalysisExpertModule(
    MODULE_NAME, __name__, static_url_path='',
    url_prefix="/pem/log_analysis_expert")


@blueprint.route("/")
@login_required
def index():
    return bad_request(errormsg=gettext(
        "This URL cannot be called directly!")
    )


@blueprint.route(
    '/analyzers/list', methods=["GET"], endpoint='analyzers_list'
)
@pem_connection
@login_required
@logAnalysisExpertRole.check_role(
    gettext(
        "Logged-in user do not have permission to access log analyzers list.")
)
def pglog_exp_analyzers_list(pem_conn=None):
    """Return a list of postgres log experts analyzers."""

    sql = render_template('log_analysis_expert/sql/analyzers.sql')

    # Execute the query.
    status, res = pem_conn.execute_dict(sql)

    if not status:
        return internal_server_error(errormsg=res)

    analyzers = []

    d = {
        'label': gettext('Analyzers'),
        'inode': True,
        'open': True,
        'branch': [],
        'checkbox': True,
        'checked': True
    }
    analyzers.append(d)

    for analyzer in res['rows']:
        k = {
            'id': analyzer['id'],
            'label': analyzer['analyzer_name'],
            'inode': False,
            'checkbox': True,
            'checked': True
        }
        d['branch'].append(k)

    return make_json_response(
        data=analyzers
    )


@blueprint.route('/server/list', methods=["GET"], endpoint='server_list')
@pem_connection
@login_required
@logAnalysisExpertRole.check_role(
    gettext("Logged-in user do not have permission to access server list.")
)
def list_server(pem_conn=None):
    """
    This function is used to get the list of
    database server's installed on that agent.

    :param pem_conn: PEM Connection object.
    """

    sql = render_template('log_analysis_expert/sql/server_list.sql')

    # Execute the query.
    status, res = pem_conn.execute_dict(sql)

    if not status:
        return internal_server_error(errormsg=res)

    # Create json response for server
    server_nodes = []
    d = {
        'label': gettext('Servers'),
        'inode': True,
        'open': True,
        'branch': [],
        'checkbox': True,
        'checked': True
    }
    server_nodes.append(d)
    if len(res['rows']) == 0:
        d['inode'] = False
        d['checkbox'] = False
        d['checked'] = False
        d['err_msg'] = gettext("Please enable the log manager to configure "
                               "log analysis expert report for servers.")
    else:
        for server in res['rows']:
            err_msg = ''
            if not server.get('has_logs'):
                if not server.get('log_manager_runs'):
                    err_msg = gettext(
                        "Log manager has not been enabled for this server.")
                else:
                    err_msg = gettext("No logs found for this server.")

            k = {
                'id': server['server_id'],
                'label': server['description'],
                'inode': False,
                'checkbox': True if server['has_logs'] else False,
                'checked': True if server['has_logs'] else False,
                'err_msg': err_msg
            }
            d['branch'].append(k)

    return make_json_response(
        data=server_nodes
    )


@blueprint.route('/report', methods=["POST"], endpoint='init_report')
@pgCSRFProtect.exempt
@pem_connection
@login_required
@logAnalysisExpertRole.check_role(
    gettext(
        "Logged-in user do not have permission to generate log analysis "
        "expert report.")
)
def init_report(pem_conn=None):
    try:
        if request.data:
            params = json.loads(request.data.decode())
        else:
            params = request.args or request.form
    except BadRequest as e:
        return bad_request(e.description)

    # python list literal ==> python list.
    analyzers = sorted(ast.literal_eval(params['analyzers']))
    # Sort the analyzers by ID, in aciTree it's sorted by label
    params['analyzers'] = analyzers

    params['servers'] = ast.literal_eval(params['servers'])

    chart_query = render_template(
        'log_analysis_expert/sql/charts/analyzer_chart_details.sql')

    status, res = pem_conn.execute_dict(
        chart_query,
        [tuple(params['analyzers'])]
    )

    if not status:
        raise Exception(str(res))

    chart_config = {}
    for row in res['rows']:
        chart_config[str(row['id'])] = row

    sql = render_template(
        'log_analysis_expert/sql/charts/server_details.sql')

    status, res = pem_conn.execute_dict(sql, [tuple(params['servers'])])

    if not status:
        raise Exception(str(res))

    server_data = {}
    for row in res['rows']:
        server_data[str(row['id'])] = row

    data = {
        'params': params,
        'current_server': 0,
        'current_analyzer': 0,
        'chart_config': chart_config,
        'server_data': server_data,
        'server_charts': {},
        'move_to_next': True,
        'status': 'busy',
    }

    if 'pglog_exp_report' not in session:
        pglog_exp_report_data = session['pglog_exp_report'] = dict()
    else:
        pglog_exp_report_data = session['pglog_exp_report']

    trans_id = str(random.randint(1, 9999999))

    while True:
        if trans_id not in pglog_exp_report_data:
            break
        trans_id = str(random.randint(1, 9999999))

    # update session with chart data.
    pglog_exp_report_data[trans_id] = data

    return make_json_response(
        data={
            'trans_id': trans_id
        }
    )


@blueprint.route(
    '/report/<int:trans_id>/cancel', methods=["GET"],
    endpoint='cancel_report'
)
@pgCSRFProtect.exempt
@pem_connection
@login_required
@logAnalysisExpertRole.check_role(
    gettext("Logged-in user do not have permission to cancel log analysis "
            "expert report generation.")
)
def cancel(trans_id, pem_conn=None):
    """
    Cancel report generation and perform full cleanup.
    :param pem_conn:
    :return:
    """

    if 'pglog_exp_report' not in session \
            or str(trans_id) not in session['pglog_exp_report']:
        return success_return()

    pglog_exp_report = session['pglog_exp_report']
    pglog_exp_report[str(trans_id)] = {'status': 'canceled'}
    session['pglog_exp_report'] = pglog_exp_report

    cleanup(trans_id, full_cleanup=True)

    return success_return()


@blueprint.route(
    '/report/<int:trans_id>/download', methods=["GET"],
    endpoint='download_report'
)
@pgCSRFProtect.exempt
@pem_connection
@login_required
@logAnalysisExpertRole.check_role(
    gettext("Logged-in user do not have permission to download log analysis "
            "expert report.")
)
def download(trans_id, pem_conn=None):
    """
    Returns downloadable report in xhtml format or returns html which is shown
    in frame which will initiate show report in panel.
    Return type behaviour will be completely dependent on 'save' flag.
    :param trans_id:
    :param pem_conn:
    :return:
    """

    if 'pglog_exp_report' not in session \
            or str(trans_id) not in session['pglog_exp_report']:
        return make_response(
            status=404,
            response=gettext('Transaction id not found')
        )

    data = session['pglog_exp_report'][str(trans_id)]

    if data['status'] == 'failed':
        return gone()
    elif data['status'] == 'busy':
        bad_request(gettext("Report not ready."))
    elif data['status'] == 'canceled':
        return make_json_response(data={"status": "canceled"})

    try:
        r = Response(
            get_html_page(trans_id, data),
            mimetype='application/xhtml+xml'
        )

        r.headers["Content-Disposition"] = "attachment;filename=" \
                                           "log_analysis_expert.htm"
        # report downloading requires access to cookie on js side, do not set
        # httponly to True, or else download report will not work properly
        r.set_cookie(
            str(trans_id), value='1',
            path=url_for('browser.index'),
            secure=config.SESSION_COOKIE_SECURE,
            samesite=config.SESSION_COOKIE_SAMESITE
        )

        return r
    except Exception as e:
        logging.exception(str(e), exc_info=True)

        r = Response("{}".format(traceback.format_exc()), status=500)

        r.headers["Content-Disposition"] = "attachment;filename="" \
        ""log_analysis_expert.htm"
        # report downloading requires access to cookie on js side, do not set
        # httponly to True, or else download report will not work properly
        r.set_cookie(
            str(trans_id), value='-1',
            path=url_for('browser.index'),
            secure=config.SESSION_COOKIE_SECURE,
            samesite=config.SESSION_COOKIE_SAMESITE
        )

        return r
    finally:
        cleanup(trans_id, full_cleanup=True)


@blueprint.route(
    '/report/<int:trans_id>/open', methods=["GET"], endpoint='open_report'
)
@pgCSRFProtect.exempt
@pem_connection
@login_required
@logAnalysisExpertRole.check_role(
    gettext("Logged-in user do not have permission to view log analysis "
            "expert report.")
)
def get_report_panel(trans_id, pem_conn=None):
    """
    Creates panel for report.
    :param trans_id:
    :param pem_conn:
    :return:
    """
    if 'pglog_exp_report' not in session \
            or str(trans_id) not in session['pglog_exp_report']:
        return make_response(
            status=404,
            response=gettext('Transaction id not found')
        )

    data = session['pglog_exp_report'][str(trans_id)]
    return Response(
        get_html_page(trans_id, data),
        mimetype='text/html'
    )


@blueprint.route(
    '/report/<int:trans_id>/poll', methods=["GET"], endpoint='poll_report'
)
@pgCSRFProtect.exempt
@pem_connection
@login_required
@logAnalysisExpertRole.check_role(
    gettext("Logged-in user do not have permission to poll log analysis "
            "expert report data.")
)
def poll(trans_id, pem_conn=None):
    """
    Poll callback for report generation.
    :param trans_id:
    :param pem_conn:
    :param params:
    :return:
    """

    try:
        if 'pglog_exp_report' not in session \
                or str(trans_id) not in session['pglog_exp_report']:
            return make_response(
                status=404,
                response=gettext('Transaction id not found')
            )

        data = session['pglog_exp_report'][str(trans_id)]

        if data['status'] == 'failed':
            return make_json_response(data={"status": "failed"})
        elif data['status'] == 'canceled':
            return make_json_response(data={"status": "canceled"})

        params = data['params']
        current_server = data['current_server']
        current_analyzer = data['current_analyzer']

        if (current_server + 1) > len(params['servers']):
            # Connection cleanup only.
            cleanup(trans_id)
            result = {
                "status": "completed",
            }
            # When Download is False, send the data as well
            if 'save' in params and not params['save']:
                result['charts_data'] = list(data['server_charts'].values())
            return make_json_response(data=result)

        pId = params['analyzers'][current_analyzer]
        pServerID = params['servers'][current_server]
        chart_obj = data['chart_config'][str(pId)]

        async_conn = pem_dedicated_connection(trans_id, async_=1)

        res = async_conn.poll(formatted_exception_msg=True)

        if data['move_to_next']:
            # This will get called on first poll and we are starting to fetch
            # data for first analyzer of first server asynchronously.
            # OR
            # Previous async query was completed and chart was build and we
            # are starting to fetch data for next analyzer of current server
            # asynchronously.

            data['move_to_next'] = False
            if len(res) == 3:
                status, msg, result = res
            else:
                status, result = res

            got_error = False
            zero_rows = False

            if current_analyzer == 0:
                # Check the given time intervals, and adjust them as per the
                # existing data.
                # Convert the time intervals like start datetime offset, end
                # datetime offset.

                sql = render_template(
                    'log_analysis_expert/sql/validate_intervals.sql')

                status, res = async_conn.execute_2darray(
                    sql,
                    [params['start_date_time'],
                     params['end_date_time'],
                     pServerID,
                     str(params['interval'])]
                )

                if not status:
                    error_message = str(res)
                    got_error = True
                    data['server_data'][str(pServerID)]['got_error'] = \
                        got_error
                    data['server_data'][str(pServerID)]['zero_rows'] = \
                        zero_rows
                    data['server_data'][str(pServerID)]['error_message'] = \
                        error_message

                    session['pglog_exp_report'][str(trans_id)] = data

                    return make_json_response(data={"status": "busy"})

                if got_error is False and len(res['rows']) == 0:
                    error_message = gettext(
                        'No data found to render this chart')
                    zero_rows = True
                    data['server_data'][str(pServerID)]['got_error'] = \
                        got_error
                    data['server_data'][str(pServerID)]['zero_rows'] = \
                        zero_rows
                    data['server_data'][str(pServerID)]['error_message'] = \
                        error_message

                    session['pglog_exp_report'][str(trans_id)] = data

                    return make_json_response(data={"status": "busy"})

                elif got_error is False:
                    data['server_data'][str(pServerID)]['got_error'] = \
                        got_error
                    data['server_data'][str(pServerID)]['zero_rows'] = \
                        zero_rows
                    data['server_data'][str(pServerID)]['error_message'] = \
                        None
                    data['server_data'][str(pServerID)]['start_date_time'] = \
                        res['rows'][0][0]
                    data['server_data'][str(pServerID)]['end_date_time'] = \
                        res['rows'][0][1]

            session['pglog_exp_report'][str(trans_id)] = data

            server_data = data['server_data'][str(pServerID)]

            # fetch chart data asynchronously
            status, res = fetch_chart_data(
                async_conn, params, chart_obj, pServerID, server_data)

            if not status:
                cleanup(trans_id, failed=True)
                return internal_server_error(res)
        else:
            # Check if async query is completed and if completed then build
            # chart and return busy.

            server_data = data['server_data'][str(pServerID)]
            server_charts = data['server_charts']
            server_charts.setdefault(
                str(pServerID),
                {
                    "type": "section",
                    "label": "{}{}".format(
                        server_data['description'],
                        server_data['host_details']
                    ),
                    "id": pServerID,
                    'charts': [],
                    'no_charts': True,
                    'error_message': ''
                }
            )
            server_chart = server_charts.get(str(pServerID))

            if server_data['got_error'] or server_data['zero_rows']:
                server_chart['error_message'] = server_data['error_message']
                # If we got error while validating the intervals,
                # then no need to display the chart for this server.
                # So, stop this loop.

                # move to next server
                data['current_analyzer'] = 0
                data['current_server'] += 1
                data['move_to_next'] = True
            else:
                if len(res) == 3:
                    # Something is wrong. Generally we should not be here.
                    status, msg, result = res
                else:
                    status, result = res

                if not status:
                    cleanup(trans_id, failed=True)
                    return internal_server_error(result)

                column_info = async_conn.column_info

                if status == ASYNC_EXECUTION_ABORTED:
                    cleanup(trans_id, failed=True)
                    return internal_server_error(result)

                if status == ASYNC_OK:
                    query = "END WORK;"
                    async_conn.execute_void(query)
                    chart = build_chart(result, column_info, data,
                                        pServerID, pem_conn,
                                        session['timezone'])

                    server_chart['charts'].append(chart)
                    server_chart['no_charts'] = False

                    if (current_analyzer + 1) < len(params['analyzers']):
                        # Move to next analyzer/chart
                        data['current_analyzer'] += 1
                    else:
                        # Move to next next server
                        data['current_analyzer'] = 0
                        data['current_server'] += 1

                    data['move_to_next'] = True
            # Update session
            session['pglog_exp_report'][str(trans_id)] = data

        return make_json_response(data={"status": "busy"})
    except Exception as e:
        cleanup(trans_id, failed=True)
        logging.exception(str(e), exc_info=True)
        return internal_server_error("{}".format(e))


def cleanup(trans_id, failed=False, full_cleanup=False):
    """
    Performs cleanup.
    This should not be called outside app context.

    :param trans_id:
    :param failed:
    :param full_cleanup:
    :return:
    """
    try:
        pem_dedicated_connection(trans_id, release=True)
    except Exception as e:
        # log and ignore any errors during cleanup, we don't want report to
        # fail because of cleanup fail.
        logging.exception(str(e), exc_info=True)


def get_span_and_interval_in_params(params):
    """Instead of doing calulcation in HTML/Jina, we will do in Python"""
    params['interval_str'] = '{} - {}'.format(
        params['start_date_time'], params['end_date_time'])
    span = int(params['interval']) // 60
    params['span'] = '{0} {1}'.format(span, gettext('Minutes'))
    return params


def get_html_page(trans_id, data):
    params = data['params']
    is_download = False
    data = session['pglog_exp_report'][str(trans_id)]
    report_time = current_datetime()
    params = get_span_and_interval_in_params(data['params'])
    servers = []
    result = ''

    if 'save' in params and params['save']:
        is_download = True

    if is_download:
        result = list(data['server_charts'].values())

    for server_id in data['params']['servers']:
        sname = data['server_data'][str(server_id)]['description']
        servers.append({
            'id': sname,
            'name': sname
        })

    return render_template(
        'log_analysis_expert/html/report_panel.html',
        is_download=is_download,
        css_content=get_bundled_css(),
        js_content=get_bundled_js(),
        report_time=report_time,
        trans_id=trans_id,
        params=params,
        servers=servers,
        chart_data=json.dumps(result),
        company_website=config.COMPANY_SITE
    )
