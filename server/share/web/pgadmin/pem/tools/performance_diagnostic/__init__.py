##########################################################################
#
# Postgres Enterprise Manager
#
# Copyright (C) 2016 - 2025, EnterpriseDB Corporation. All rights reserved.
#
##########################################################################

"""Implements Performance Diagnostic"""

import time
import random
import json
from flask import render_template, session, current_app, \
    Response, request
from flask_babel import gettext
from flask_security import login_required
from pgadmin.utils.ajax import internal_server_error, bad_request, \
    make_response, make_json_response, precondition_required, gone
from pgadmin.utils.csrf import pgCSRFProtect
from pgadmin.utils.driver import get_driver
from config import PG_DEFAULT_DRIVER
from pgadmin.utils import PgAdminModule
from pgadmin.pem.utils import pem_connection
from pgadmin.utils.preferences import Preferences
from pgadmin.utils.exception import ConnectionLost
from pgadmin.pem.utils.role import PEMRole
from pgadmin.pem.monitor.dashboard.helpers.chart import whichColor
from pgadmin.settings import get_setting


MODULE_NAME = 'performance_diagnostic'

sqlPerformanceDiagnostic = PEMRole(
    'pem_comp_performance_diagnostic',
    gettext('PerformanceDiagnostic'),
    gettext('Performance Diagnostic'),
    gettext('Privilege to execute the Performance diagnostic.')
)

# Null value for an wait_event/wait_event_type suggests, session is busy
# utilizing the CPU

_knownEventTypes = [
    'Activity', 'IO', 'LWLock', 'Lock', 'BufferPin', 'CPU', 'Extension',
    'IPC', 'Timeout', 'Client', 'ALL_WAIT_EVENT_TYPE',
]

_unknownEventTypes = []

_knownEventTypeColors = {
    'Total': '#DC143C',
    'CPU': '#D2691E',
    'IO': '#008080',
    'Lock': '#9400D3',
    'LWLock': '#228B22',
    'PgSleep': '#FF4500',
    'Timeout': '#FF007F',
    'Activity': '#FF00FF',
    'BufferPin': '#00AAFF',
    'Client': '#000080',
    'Extension': '#CCCCFF',
    'InjectionPoint': '#03E0E0',
    'IPC': '#98FF98',
    'Unknown': '#FD5E53',
}


def to_js_boolean(flag):
    if flag is True:
        return 'true'
    else:
        return 'false'


class PerformanceDiagnosticModule(PgAdminModule):
    """
    class PerformanceDiagnosticModule(Object):

        PerformanceDiagnosticModule inherits PgAdminModule
        class and define methods to load its own
        javascript file.
    """
    LABEL = gettext('Performance Diagnostic')

    def get_exposed_url_endpoints(self):
        """
        Returns:
            list: a list of url endpoints exposed to the client.
        """
        return [
            'performance_diagnostic.open_in_new_browser',
            'performance_diagnostic.main_dashboard',
            'performance_diagnostic.get_total_wait_events',
            'performance_diagnostic.get_selected_wait_events',
            'performance_diagnostic.query_dashboard',
            'performance_diagnostic.wait_event_stats',
            'performance_diagnostic.query_details_by_session',
            'performance_diagnostic.query_get_total_wait_events',
            'performance_diagnostic.report',
            'performance_diagnostic.colors',
            'performance_diagnostic.close',
        ]


# Create blueprint for PerformanceDiagnosticModule class
blueprint = PerformanceDiagnosticModule(
    MODULE_NAME,
    __name__,
    static_url_path='',
    url_prefix='/pem/performance_diagnostic'
)


@blueprint.route("/")
@login_required
def index():
    """
        Home route to Performance diagnostic
    """
    return bad_request(
        errormsg=gettext("This URL cannot be called directly!")
    )


@blueprint.route("/open_in_new_browser.js", endpoint="open_in_new_browser")
@pgCSRFProtect.exempt
@login_required
def trace_script():
    """Render performance diagnostic javascript"""
    pref = Preferences.module('performance_diagnostic')
    open_in_browser = pref.preference('performance_diagnostic').get()
    return Response(
        response="define([], function() {{ return {0}; }})".format(
            'true' if open_in_browser else 'false'
        ),
        status=200,
        mimetype="application/javascript"
    )


def handle_load_data_errors(trans_id, error_details=None):
    """
    This will handle the error response
    Args:
        trans_id: Unique transaction id
        error_details: Error information

    Returns:
        Response page
    """
    # Clear session data
    if 'performance_diagnostic' in session and \
            trans_id in session['performance_diagnostic']:
        del session['performance_diagnostic'][trans_id]

    error_header = gettext('Loading of the performance diagnostic dashboard is'
                           ' failed due to an error, Please try again.')

    current_app.logger.error(
        "Could not load the performance diagnostic dashboard due to an error"
        "(trans_id: {0}).\nError: {1}".format(trans_id, error_details)
    )

    # Return error page to display in panel

    # ToDo: Replaced the old logic of returning the error.html content with
    #  internal server error, need to replace this in future with
    #  more accurate error message.
    return internal_server_error(errormsg=str(error_details))


#################################
# TODO: Add privilege check here
#################################
@blueprint.route(
    '/<sid>/dashboard', methods=["GET"], endpoint='main_dashboard')
@pgCSRFProtect.exempt
@login_required
@sqlPerformanceDiagnostic.check_role(
    gettext("Logged-in user do not have permission to "
            "view performance diagnostics dashboard.")
)
@pem_connection
def main_dashboard(sid, pem_conn=None):
    """
    This function is used to open performance diagnostic dashboard.
    Args:
        sid: Server ID

    Returns:
        Response
    """
    # Create a unique id for the transaction
    trans_id = str(
        random.randint(1, 999999) +
        random.randint(1, 999999)
    )

    try:
        manager = get_driver(PG_DEFAULT_DRIVER).connection_manager(int(sid))
        conn = manager.connection(conn_id=trans_id)
    except Exception as e:
        current_app.logger.exception(e)
        return handle_load_data_errors(trans_id, str(e))

    # Connect the Server
    status, msg = conn.connect()
    if not status:
        return handle_load_data_errors(trans_id, str(msg))

    # Fetch Server Details
    sql = render_template(
        "/".join(['servers/sql', 'get_server.sql']),
        sid=sid
    )

    manager = get_driver(PG_DEFAULT_DRIVER).connection_manager(int(sid))
    status, server = pem_conn.execute_dict(sql)

    if not status:
        current_app.logger.exception(server)
        return internal_server_error(errormsg=server)
    server = server['rows'][0]

    # Save it into session
    if 'performance_diagnostic' not in session:
        session['performance_diagnostic'] = {}

    session['performance_diagnostic'][trans_id] = {
        'sid': sid,
        'serverName': server['name']
    }

    layout = get_setting('Debugger/Layout')

    return render_template(
        "performance_diagnostic/main_dashboard.html",
        gettext=gettext,
        uniqueId=trans_id,
        report_time=time.strftime("%Y-%m-%d %H:%M:%S"),
        serverName=server['name'],
        sid=str(sid),
        title=gettext('Performance Diagnostics (%s)' % server['name']),
        layout=layout
    )


@blueprint.route(
    '/<transid>/total_wait_events',
    methods=["GET"],
    endpoint='get_total_wait_events'
)
@login_required
@sqlPerformanceDiagnostic.check_role(
    gettext("Logged-in user do not have permission to "
            "fetch total wait events.")
)
def get_total_wait_events(transid):
    """
    This function is used to get total wait events count to render the charts.
    Args:
        transid: Unique transaction ID
    Returns:
        Response
    """

    # Get the server connection
    if 'performance_diagnostic' not in session or \
            transid not in session['performance_diagnostic']:
        gone(gettext(
            "Could not find the requested transaction id on the server"
        ))

    server_id = int(session['performance_diagnostic'][transid]['sid'])

    if request.data:
        filter_data = json.loads(request.data.decode())
    else:
        filter_data = request.args or request.form

    if isinstance(filter_data, list) and len(filter_data) > 0:
        last_hour = filter_data[0]['last_hours']
        date_time = filter_data[0]['date_time']
        date_time = float(date_time) / 1000
    else:
        last_hour = filter_data.get('last_hours', '1')
        date_time = float(filter_data['date_time']) / 1000

    # Validate input parameter before query to server
    if str(last_hour) not in ['1', '4', '12', '24']:
        return bad_request(gettext('Provide valid last hour parameter for '
                                   'total wait events.'))

    sql = render_template(
        'performance_diagnostic/sql/total_wait_events.sql',
        last_hour='{} hours'.format(last_hour),
        filter_date_time=date_time
    )

    return flat_timeline_from_sql(server_id, sql, None, int, transid)


def generate_flat_timeline(_rows, _type):
    """
    This function takes the time series of multiple wait_event_types as input,
    and flattens these time series by iterating the time series and putting 0
    for the wait_event_type, which does not have data, at that particular time
    unit. Also - cast the timeline in to given type.

    Args:
        _rows: timeseries of wait_event_types
        _type: type in which the time unit to convert into

    Returns:
        Flattened time line from the given time series of wait_event_types and
        dict of wait_event_type with the value series for the respective to
        that time series.

        e.g.
        timeline -> [1111, 1112, 1113, 1114]
        wait_event_types -> {
         'IO': [2, 0, 0, 2],
         'CPU': [4, 0, 0, 0],
         'LWLOCK': [0, 1, 2, 0],
        }
    """

    wait_event_types = {}
    timeline = []
    sample_time = None

    for row in _rows:
        if sample_time != row['sample_time']:
            for wait_event in wait_event_types:
                dataset = wait_event_types[wait_event]
                if dataset['latest_sample_time'] != sample_time:
                    dataset['latest_sample_time'] = sample_time
                    dataset['data'].append(0)
            sample_time = row['sample_time']
            timeline.append(_type(sample_time))

        if row['wait_event_type'] not in wait_event_types:
            color = wait_event_type_color(row['wait_event_type'])
            curr_sample_time = _type(sample_time)
            wait_event_types[row['wait_event_type']] = {
                'latest_sample_time': sample_time,
                'data': [0 for x in timeline if x != curr_sample_time],
                'color': color,
            }
            wait_event_types[row['wait_event_type']]['data'].append(
                int(row['cnt']))
        else:
            wait_event_types[row['wait_event_type']][
                'latest_sample_time'] = sample_time
            wait_event_types[row['wait_event_type']][
                'data'].append(int(row['cnt']))

    if sample_time is not None:
        for key in wait_event_types:
            if wait_event_types[key]['latest_sample_time'] != sample_time:
                wait_event_types[key]['data'].append(0)

    return timeline, wait_event_types


@blueprint.route(
    '/<transid>/wait_events/<start_time>/<end_time>',
    methods=["GET"],
    endpoint='get_selected_wait_events'
)
@login_required
@sqlPerformanceDiagnostic.check_role(
    gettext("Logged-in user do not have permission to "
            "fetch selected wait events.")
)
def get_selected_wait_events(transid, start_time, end_time):
    """
    This function is used to get wait events for selected time span to render
    the second charts.

    Args:
        transid: Unique transaction ID
        start_time: Start time
        end_time: End time
    Returns:
        Response
    """

    # Get the server connection
    if 'performance_diagnostic' not in session or \
            transid not in session['performance_diagnostic']:
        gone(gettext(
            "Could not find the requested transaction id on the server"
        ))

    if start_time is None or end_time is None:
        return precondition_required(
            gettext("Please provide the valid start time and end time.")
        )

    start_time = float(start_time) / 1000
    end_time = float(end_time) / 1000
    server_id = int(session['performance_diagnostic'][transid]['sid'])

    sql = render_template(
        'performance_diagnostic/sql/selected_wait_events.sql'
    )

    return flat_timeline_from_sql(
        server_id, sql, (start_time, end_time), float, transid
    )


def flat_timeline_from_sql(_server_id, _sql, _params, _type, transid):
    """
    This function takes the _server_id, the performance diagnostics query, its
    parameters, and timeline type as input. It will execute the parameterized
    query against the databse server represented by the _server_id, and send
    the result to the generate_flat_timeline(...) function to generate the
    timeline and wait_event_type series for sending the result as HTTPResponse.

    Args:
        _rows: timeseries of wait_event_types
        _type: type in which the time unit to convert into

    Returns:
        HTTPResoponse as JSON with timeline, and wait_event_types series on
        successful query execution, otherwise returns as appropriate error
        response.
    """

    manager = get_driver(PG_DEFAULT_DRIVER).connection_manager(_server_id)
    status, pool_ctx = manager.get_pd_connection_pool_ctxmgr()
    if not status:
        return internal_server_error(errormsg=pool_ctx)

    with pool_ctx() as conn:
        status, result = conn.execute_2darray(_sql, _params)

    if not status:
        return internal_server_error(errormsg=result)

    timeline, wait_event_types = generate_flat_timeline(result['rows'], _type)

    # Send response of data received from edb wait states.
    return make_json_response(
        data={
            'status': status,
            'timeline': timeline,
            'wait_event_types': [{
                'label': key,
                'dataset': wait_event_types[key]['data'],
                'color': wait_event_types[key]['color'],
            } for key in wait_event_types],
        }
    )


def wait_event_type_color(event_type):
    """
    Returns the color of the wait_event_type based on its index.
    """
    global _knownEventTypes, _unknownEventTypes, _knownEventTypeColors

    if event_type in _knownEventTypeColors:
        return _knownEventTypeColors[event_type]
    else:
        if event_type not in _unknownEventTypes:
            _unknownEventTypes.append(event_type)
        idx = _unknownEventTypes.index(event_type) + len(_knownEventTypes) + 1

    return whichColor(str(idx), None)


@blueprint.route(
    '/<transid>/wait_event_stats/<action>/<time_stamp>',
    methods=["GET"],
    endpoint='wait_event_stats')
@login_required
@sqlPerformanceDiagnostic.check_role(
    gettext("Logged-in user do not have permission to "
            "fetch wait event stats.")
)
@pem_connection
def wait_event_stats(transid, action, time_stamp, pem_conn=None):
    """
    This function is used to get total wait events by users.
    Args:
        transid: Unique transaction ID
        action: Action performed by user ( SQL, Users, Waits )
        time_stamp: Time stamp
    Returns:
        Response
    """

    # Get the server connection
    if 'performance_diagnostic' not in session or \
            transid not in session['performance_diagnostic']:
        gone(gettext(
            "Could not find the requested transaction id on the server"
        ))

    server_id = int(session['performance_diagnostic'][transid]['sid'])

    sql = render_template(
        'performance_diagnostic/sql/'
        'wait_event_types_by_{}.sql'.format(action)
    )

    manager = get_driver(PG_DEFAULT_DRIVER).connection_manager(server_id)
    status, pool_ctx = manager.get_pd_connection_pool_ctxmgr()

    if not status:
        return internal_server_error(errormsg=pool_ctx)

    with pool_ctx() as conn:
        status, res = conn.execute_dict(
            sql, {'time_stamp': float(time_stamp) / 1000}
        )
    if not status:
        return internal_server_error(errormsg=res)

    enum_val = 'load_by_waits'
    if action == 'waits':
        enum_val = 'load_by_event'

    for rec in res['rows']:
        for index, item in enumerate(rec[enum_val]):
            if item is None:
                rec[enum_val][index] = []
            else:
                rec[enum_val][index] = json.loads(item)

    return make_response(res['rows'])


@blueprint.route(
    '/<trans_id>/report/<int:start_epoch>/<int:end_epoch>/<int:limit>',
    methods=["GET"],
    endpoint='report'
)
@login_required
@sqlPerformanceDiagnostic.check_role(
    gettext("Logged-in user do not have permission to generate the report")
)
def report(trans_id, start_epoch, end_epoch, limit):
    """
    """
    try:
        trans_data = session['performance_diagnostic'].get(trans_id, None)
    except KeyError as ke:
        current_app.logger.exception(ke)
        return handle_load_data_errors(
            trans_id,
            gettext('Transaction id not found')
        )

    if not trans_data:
        return handle_load_data_errors(
            trans_id,
            gettext('Transaction id not found')
        )

    server_id = int(trans_data['sid'])

    sql = render_template(
        'performance_diagnostic/sql/wait_events_report.sql',
        limit=limit,
    )

    manager = get_driver(PG_DEFAULT_DRIVER).connection_manager(server_id)
    status, pool_ctx = manager.get_pd_connection_pool_ctxmgr()

    if not status:
        return internal_server_error(errormsg=pool_ctx)

    res = None
    status = None

    with pool_ctx() as conn:
        status, res = conn.execute_dict(
            sql, {
                'start_epoch': float(start_epoch) / 1000,
                'end_epoch': float(end_epoch) / 1000,
            },
        )

    if not status:
        return internal_server_error(errormsg=res)

    report = {}

    for rec in res['rows']:

        report[rec['kind']] = \
            json.loads(rec['data']) if rec['data'] is not None else []
    return make_response({
        'report': report
    })


@blueprint.route(
    '/colors', methods=["GET"], endpoint='colors'
)
def colors():
    global _knownEventTypes, _unknownEventTypes

    colors = {}

    for event_type in _knownEventTypes:
        if event_type in _knownEventTypeColors:
            colors[event_type] = _knownEventTypeColors[event_type]
        else:
            idx = _knownEventTypes.index(event_type)
            colors[event_type] = whichColor(str(idx), None)

    number_known_wait_event_types = len(_knownEventTypes)

    for event_type in _unknownEventTypes:
        idx = _unknownEventTypes.index(
            event_type) + number_known_wait_event_types + 1
        colors[event_type] = whichColor(str(idx), None)

    return make_response({'colors': colors})


@blueprint.route(
    '/<trans_id>/query/<query_id>/<sample_time>',
    methods=["GET"],
    endpoint='query_dashboard')
@pgCSRFProtect.exempt
@login_required
@sqlPerformanceDiagnostic.check_role(
    gettext("Logged-in user do not have permission to "
            "view query dashboard.")
)
@pem_connection
def query_dashboard(trans_id, query_id, sample_time, pem_conn=None):
    """
    This function is used to open performance diagnostic dashboard.
    Args:
        sid: Server ID
        query_id: Query Id
        sample_time: Query sample time

    Returns:
        Response
    """

    try:
        trans_data = session['performance_diagnostic'].get(trans_id, None)
    except KeyError as e:
        current_app.logger.exception(e)
        return handle_load_data_errors(trans_id,
                                       gettext('Transaction id not found'))

    if not trans_data:
        return handle_load_data_errors(trans_id,
                                       gettext('Transaction id not found'))

    return render_template(
        "performance_diagnostic/query_dashboard.html",
        gettext=gettext,
        trans_id=trans_id,
        requirejs=True,
        basejs=True,
        report_time=time.strftime("%Y-%m-%d %H:%M:%S"),
        serverName=trans_data['serverName'],
        sid=str(trans_data['sid']),
        query_id=str(query_id),
        sample_time=sample_time,
        title=gettext('Query Dashboard (query id: {})').format(query_id),
        uniqueId=trans_id,
    )


@blueprint.route(
    '/<transid>/query_details_by_session/<query_id>/<sample_time>',
    methods=["GET"],
    endpoint='query_details_by_session')
@login_required
@sqlPerformanceDiagnostic.check_role(
    gettext("Logged-in user do not have permission to "
            "fetch query details by session.")
)
@pem_connection
def query_details_by_session(transid, query_id, sample_time, pem_conn=None):
    """
    This function is used to get query details by session.
    Args:
        transid: Unique transaction ID,
        query_id:
        sample_time
    Returns:
        Response
    """

    # Get the server connection
    server_id = int(session['performance_diagnostic'][transid]['sid'])

    sql = render_template(
        'performance_diagnostic/sql/query.sql')

    manager = get_driver(PG_DEFAULT_DRIVER).connection_manager(server_id)
    status, pool_ctx = manager.get_pd_connection_pool_ctxmgr()

    if not status:
        return internal_server_error(errormsg=pool_ctx)

    with pool_ctx() as conn:
        status, query = conn.execute_scalar(
            sql,
            {'query_id': query_id,
             'sample_time': float(sample_time) / 1000}
        )

        if not status:
            return internal_server_error(errormsg=query)

        sql = render_template(
            'performance_diagnostic/sql/query_details_by_session.sql')

        status, query_details_by_session = conn.execute_dict(
            sql,
            {'query_id': query_id,
             'sample_time': float(sample_time) / 1000}
        )

        if not status:
            return internal_server_error(errormsg=query_details_by_session)

    return make_response({
        'query': query,
        'query_sessions': query_details_by_session['rows']
    })


def _find_query_start_time(conn, query_id, session_id, sample_time):
    """
    This function returns the query_start_time and min_sample_time based on
    query_id, session_id and sample_time.
    """
    sql = render_template(
        'performance_diagnostic/sql/find_query_with_min_starttime.sql'
    )

    # Get total wait events list from sample time.
    return conn.execute_dict(sql, {
        'time_stamp': sample_time,
        'query_id': query_id,
        'session_id': session_id
    })


def _find_wait_events_using_temp_table(
    conn, query_id, session_id, sample_start_time, query_start_time
):
    """
    This function fetches all the wait_event & wait_event_type for the given
    query identified by query_id, session_id, start_time using a temporary
    table to do the operations quickly. (used mainly on active server, which is
    not being used as stand-by server.
    """

    sql = render_template(
        'performance_diagnostic/sql/query_wait_events_temp_tbl.sql'
    ).format(query_id=query_id,
             session_id=session_id,
             query_start_time=query_start_time,
             sample_start_time=sample_start_time)

    status, res = conn.execute_2darray(sql)

    if not status:
        conn.execute_void("ROLLBACK;")
        return False, internal_server_error(errormsg=res)

    conn.execute_void('COMMIT;')
    return True, res['rows']


def _find_query_wait_events(
    conn, query_id, session_id, sample_start_time, query_start_time
):
    """
    This function fetches all the wait_event & wait_event_type for the given
    query identified by query_id, session_id, start_time.
    """
    rset = []
    sql = render_template(
        'performance_diagnostic/sql/query_total_wait_events.sql',
    )

    idx = 0
    break_loop = True

    while break_loop is True:
        # Get total wait events list from sample time.
        status, res = conn.execute_dict(sql, {
            'query_id': query_id,
            'session_id': session_id,
            'query_start_time': query_start_time,
            'sample_start_time': float(sample_start_time) - 1,
            'idx': idx,
        })

        if not status:
            return False, internal_server_error(errormsg=res)

        if len(res['rows']) > 0:
            rset.append(res['rows'])
            idx += 1
        else:
            return True, rset


@blueprint.route(
    '/<transid>/query_total_wait_events',
    methods=["GET"],
    endpoint='query_get_total_wait_events'
)
@login_required
@sqlPerformanceDiagnostic.check_role(
    gettext("Logged-in user do not have permission to "
            "query total wait events.")
)
def query_get_total_wait_events(transid):
    """
    This function is used to get total wait events count for
    specific query selected by user to render the charts.
    Args:
        transid: Unique transaction ID
    Returns:
        Response
    """
    # Get the server connection
    if 'performance_diagnostic' not in session or \
            transid not in session['performance_diagnostic']:
        return gone(gettext(
            "Could not find the requested transaction id on the server"
        ))

    server_id = int(session['performance_diagnostic'][transid]['sid'])

    if request.data:
        filter_data = json.loads(request.data.decode())
    else:
        filter_data = request.args or request.form

    args = {}

    if isinstance(filter_data, list) and len(filter_data) > 0:
        def fetch_input_arg(name):
            args[name] = filter_data[0][name]
            if args[name] is None:
                return False
            return True
    else:
        def fetch_input_arg(name):
            args[name] = filter_data.get(name, None)

            if args[name] is None:
                return False

            return True

    for input_arg in [
        ['query_id', gettext(
            'Provide valid query id for total wait events by query.'
        )],
        ['sample_time', gettext(
            'Provide valid sample time for total wait events by query.'
        )],
        ['session_id', gettext(
            'Provide valid session id for total wait events by query.'
        )],
    ]:
        if fetch_input_arg(input_arg[0]) is False:
            return bad_request(input_arg[1])

    manager = get_driver(PG_DEFAULT_DRIVER).connection_manager(server_id)
    status, pool_ctx = manager.get_pd_connection_pool_ctxmgr()

    if not status:
        return internal_server_error(errormsg=pool_ctx)

    data = []
    with pool_ctx() as conn:
        status, res = _find_query_start_time(
            conn, args['query_id'], args['session_id'], args['sample_time']
        )

        if not status:
            return internal_server_error(errormsg=res)

        if 'rows' in res and len(res['rows']) >= 1:
            query_start_time = res['rows'][0]['query_start_time']
            use_temp_table = res['rows'][0]['require_permision']
            sample_start_time = res['rows'][0]['min_sample_time']

            status, res = _find_wait_events_using_temp_table(
                conn, args['query_id'], args['session_id'], sample_start_time,
                query_start_time
            ) if use_temp_table is True else _find_query_wait_events(
                conn, args['query_id'], args['session_id'], sample_start_time,
                query_start_time
            )

            if not status:
                return res
            data = res

    colors = dict()
    for event in _knownEventTypes:
        colors[event] = wait_event_type_color(event)
    for event in _unknownEventTypes:
        colors[event] = wait_event_type_color(event)

    # Send response of data received from edb wait states.
    return make_json_response(
        data={
            'status': status,
            'data': data,
            'colors': colors,
        }
    )


@blueprint.route(
    '/close/<int:sid>/<int:trans_id>', methods=["DELETE"], endpoint='close'
)
def close(sid, trans_id):
    """
    close(trans_id)

    This method is used to close the asynchronous connection
    and remove the information of unique transaction id from
    the session variable.

    Parameters:
        trans_id
        - unique transaction id.
    """

    manager = get_driver(PG_DEFAULT_DRIVER).connection_manager(int(sid))
    manager.release(conn_id=trans_id)

    return make_json_response(data={'status': True})
