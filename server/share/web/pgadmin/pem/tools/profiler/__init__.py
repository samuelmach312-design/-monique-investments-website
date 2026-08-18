##########################################################################
#
# Postgres Enterprise Manager
#
# Copyright (C) 2016 - 2025, EnterpriseDB Corporation. All rights reserved.
#
##########################################################################

"""Implements SQL Profiler"""

import json
import random
import csv
import sys
from flask import render_template, request, session, current_app
from flask_babel import gettext
from pgadmin.utils.ajax import internal_server_error, bad_request, \
    make_response as ajax_response, make_json_response, \
    precondition_required, gone
from pgadmin.utils.csrf import pgCSRFProtect
from pgadmin.utils.driver import get_driver
from config import PG_DEFAULT_DRIVER
from pgadmin.utils import PgAdminModule
from flask import Response, url_for
from flask_security import login_required
from pgadmin.pem.utils import pem_connection
from pgadmin.utils import get_storage_directory
from pgadmin.utils.preferences import Preferences
from pgadmin.utils.exception import ConnectionLost
from pgadmin.pem.utils.role import PEMRole
from pgadmin.pem.utils import pem_encrypt
from threading import Lock
from .utils.sql_profiler_preferences import RegisterSQLProfilerPreferences

sql_profiler_session_lock = Lock()

from io import StringIO


_ = gettext
MODULE_NAME = 'profiler'
server_info = {}
# Constants
ASYNC_OK = 1

sqlProfilerRole = PEMRole(
    'pem_comp_sqlprofiler', gettext('SQLProfiler'), gettext('SQL Profiler'),
    gettext('Priviledge to execute the SQL-Profiler.')
)


class NoSuggestedIndex(ValueError):
    """raise this when there's no suggested index found"""


class ProfilerModule(PgAdminModule):
    """
    class ProfilerModule(Object):

        ProfilerModule inherits PgAdminModule
        class and define methods to load its own
        javascript file.
    """
    LABEL = gettext('SQL Profiler')

    def register_preferences(self):
        """
            This function will setup preference for sql profiler

            :return None
        """
        RegisterSQLProfilerPreferences(self)

    def get_exposed_url_endpoints(self):
        """
        Returns:
            list: a list of url endpoints exposed to the client.
        """
        return [
            'profiler.traces_load_file', 'profiler.traces_save_file',
            'profiler.action_on_trace',
            'profiler.traces_get_sql', 'profiler.traces_new',
            'profiler.traces_delete', 'profiler.traces_delete_with_trace_id',
            'profiler.traces_open', 'profiler.traces_refresh_data',
            'profiler.traces_execute_data',
            'profiler.traces_execute_data_with_filter',
            'profiler.traces_poll_data', 'profiler.traces_metrics',
            'profiler.traces_scheduled_list', 'profiler.traces_scheduled_step',
            'profiler.traces_delete_scheduled', 'profiler.traces_server_info',
            'profiler.traces_download', 'profiler.trace_close'
        ]


# Create blueprint for ProfilerModule class
blueprint = ProfilerModule(
    MODULE_NAME, __name__, static_url_path='',
    url_prefix='/pem/profiler'
)


def database_connection(sid, trans_id=None, database=None):
    """
    This function creates connection to database

     Args:
        sid: Server ID
        trans_id: Transaction ID,
        database: Database

    Returns:
        Connection object
    """
    try:
        manager = get_driver(PG_DEFAULT_DRIVER).connection_manager(
            int(sid)
        )
        if trans_id is None:
            return True, manager.connection()
        else:
            if database:
                return True, manager.connection(
                    conn_id=trans_id, database=database
                )
            return True, manager.connection(conn_id=trans_id)
    except ConnectionLost:
        return False, gone(
            gettext("Connection to the server has been lost.")
        )


def validate_trans_id(trans_id):
    """
    Before we proceed further we need to check if transaction id is valid

    This function is used fetch server group and server information

     Args:
        trans_id: Unique transaction id for trace

    Returns:
        Flag & Valid trace object from session or else Error

    """
    if trans_id is not None:
        trace_object = session.get(trans_id)
        if trace_object is None:
            return False, gone(
                gettext("Could not find the requested trace and transaction "
                        "id on server.")
            )
        else:
            # verify trace id is present or not
            if trace_object.get('trace_id'):
                trace_id = trace_object.get('trace_id')
                sid = trace_object.get('sid')
                status, conn = database_connection(sid)
                if not status:
                    return conn

                if not conn.connected():
                    return False, precondition_required(
                        gettext("Connection to the database server "
                                "has been lost!")
                    )

                sql = "SELECT count(*) from public.sp_traces_list() " \
                      "WHERE trace_id = '{0}';".format(trace_id)
                status, result = conn.execute_scalar(sql)
                if not status:
                    current_app.logger.error(
                        "SQL Profiler trace existence verification failed."
                        "\nError: {0}".format(str(result))
                    )
                    return False, internal_server_error(errormsg=str(result))
                if int(result) == 0:
                    return False, gone(
                        gettext("Could not find the requested trace "
                                "on server.")
                    )

            return True, trace_object


@blueprint.route("/")
@login_required
def index():
    """
        Home route to SQL Profiler
    """
    return bad_request(errormsg=gettext(
        "This URL cannot be called directly!")
    )


@blueprint.route("/open_in_new_browser.js", endpoint="open_in_new_browser")
@pgCSRFProtect.exempt
@login_required
def trace_script():
    """Render SQL profiler Trace javascript"""
    pref = Preferences.module('profiler')
    open_in_browser = pref.preference('open_window_preference').get()
    return Response(
        response="define([], function() {{ return {0}; }})".format(
            'true' if open_in_browser else 'false'
        ),
        status=200,
        mimetype="application/javascript"
    )


def get_trace_status_message(status):
    """
    This function will convert numeric status to respective
    text based status

    Args:
        status: Numeric status for trace

    Returns:
        Text based status
    """
    messages = {
        0: gettext("Unknown (database server restarted)"),
        1: gettext("Running"),
        2: gettext("Stopped"),
        3: gettext("Stopped (maximum trace size limit exceeded)"),
        4: gettext("Stopped (maximum time limit exceeded/scheduled trace)")
    }
    return messages.get(
        status,
        gettext("Unknown (database server restarted)")
    )


def update_trace_metrics(trans_id):
    """
    This function is used to update metrics for trace.

    Args:
        trans_id: Unique transaction id for trace

    Returns:
        SQL to update trace metrics
    """
    # Trace index
    tid = session.get(trans_id)['tid']

    # Fetch tid and save it in session
    return render_template(
        "profiler/sql/update_metrics.sql", _=gettext, tid=tid)


def get_trace_data_query(
    trans_id, page_number, page_size, column, order_by,
    csv_query=False
):
    """
    This function is used to form a query for fetching trace data.

    Args:
        trans_id: Unique transaction id for trace
        page_number: offset of data,
        page_size: limit of data,
        column: column to order by,
        order_by: sort column by ASC or DESC order

    Returns:
        sql query to be executed
    """

    trace_obj = session.get(trans_id)
    tid = trace_obj.get('tid')
    filter_sql = trace_obj.get('filter_sql')

    if page_number and page_number > 0:
        # We need to calculate new offset
        page_number *= page_size

    return render_template(
        "profiler/sql/fetch_trace_data.sql",
        filter_sql=filter_sql,
        _=gettext,
        tid=tid,
        offset_value=page_number,
        limit_value=page_size,
        column=column,
        order_by=order_by,
        csv_query=csv_query
    )


def check_if_all_values_present(conn, list_of_oids, node_type='role'):
    """Allow us to check if all the users which are not roles
    are selected in the trace"""
    label = gettext('<All users>') if node_type == 'role' else gettext(
        '<All databases>')

    sql = render_template(
        'profiler/sql/fetch_oids.sql',
        databases=False if node_type == 'role' else True
    )
    status, rset = conn.execute_dict(sql)
    if not status or len(rset['rows']) == 0:
        return False, None

    result = []
    for row in rset['rows']:
        if str(row['oid']) in list_of_oids:
            result.append('true')
        else:
            result.append('false')

    if 'false' in result:
        return False, None

    return True, label


@blueprint.route('/traces/<_id>', methods=["GET"], endpoint='traces_get_sql')
@login_required
@sqlProfilerRole.check_role(
    gettext("Logged-in user do not have permission to access existing traces.")
)
def get_sql_traces(_id):
    """
    This function will fetch list of
    existing traces for server.
    """
    # Note: _id may be server id or transaction id
    # We need to check & take appropriate action
    trace_id = server_name = None
    # Check in session for transaction id
    trace_object = session.get(_id, None)

    if trace_object is not None:
        trace_id = trace_object.get('trace_id')
        sid = trace_object.get('sid')
        if 'server_name' in trace_object:
            server_name = trace_object['server_name']
    else:
        # This may be server id
        sid = _id

    status, conn = database_connection(sid)
    if not status:
        return conn

    if not conn.connected():
        return precondition_required(
            gettext("Connection to the database server has been lost!")
        )

    sql = render_template(
        'profiler/sql/get_existing_traces.sql',
        trace_id=trace_id,
        conn=conn
    )

    status, rset = conn.execute_dict(sql)

    if not status:
        current_app.logger.error(
            "SQL Profiler get list of traces operation failed."
            "\nError: {0}".format(str(rset))
        )
        return internal_server_error(errormsg=rset)

    for row in rset['rows']:
        # Split oidvector type to coma separated string
        # Fetch the name from User & Database OIDS
        if row['users']:
            users = row['users'].split(' ')
            sql = render_template(
                'profiler/sql/fetch_names_from_oids.sql',
                roles=users
            )
            status, row['users'] = conn.execute_scalar(sql, [users])

            status, label = check_if_all_values_present(conn, users)
            if status:
                row['users'] = label
        # If all the users are selected by user then
        # it will be blank, so we can hard code it
        elif not row['users']:
            row['users'] = gettext("<All users>")

        if row['databases']:
            databases = row['databases'].split(' ')
            sql = render_template(
                'profiler/sql/fetch_names_from_oids.sql',
                databases=databases
            )
            status, row['databases'] = conn.execute_scalar(
                sql, [databases])
            status, label = check_if_all_values_present(
                conn, databases, 'database')
            if status:
                row['databases'] = label

        # If all the database are selected by user then
        # it will be blank, so we can hard code it
        elif not row['databases']:
            row['databases'] = gettext("<All databases>")

        # Fetch the detailed message based on status code
        row['status'] = get_trace_status_message(row['status'])
        # Add server name in trace details
        row['server_name'] = server_name

    res = rset['rows'][0] if len(rset['rows']) > 0 else rset['rows']

    return ajax_response(
        response=rset['rows'] if trace_id is None else res,
        status=200
    )


@blueprint.route('/traces', methods=["POST"], endpoint='traces_new')
@login_required
@sqlProfilerRole.check_role(
    gettext("Logged-in user do not have permission to create new traces.")
)
@pem_connection
def create_new_trace(pem_conn=None):
    """
    This function is used to create new trace
    """
    data = json.loads(request.data.decode())
    status, conn = database_connection(data['server_id'])
    if not status:
        return conn

    if not conn.connected():
        return precondition_required(
            gettext("Connection to the database server has been lost!")
        )

    # If all databases are selected, we will pass NULL in create trace SQL
    if len(data['databases']) == 1 and data['databases'][0] == "null":
        data['databases'] = None
    else:
        data['databases'] = " ".join(data['databases'])

    # If all users are selected, we will pass NULL in create trace SQL
    if len(data['users']) == 1 and data['users'][0] == "null":
        data['users'] = None
    else:
        data['users'] = " ".join(data['users'])

    # If user provided size to Zero then set it to 250 MB Max.
    if int(data['trace_file_size']) == 0:
        data['trace_file_size'] = 250

    if data.get('log_min_duration', None) is None:
        data['log_min_duration'] = 0

    sql = render_template(
        'profiler/sql/create_trace.sql',
        data=data
    )

    # making copy for future use
    trace_sql = sql

    # If run now then execute it now
    if data['run_option']:
        schedule_trace = False
        status, tid = conn.execute_scalar(sql)
        if not status:
            current_app.logger.error(
                "SQL Profiler create new trace operation failed."
                "\nError: {0}".format(str(tid))
            )
            return internal_server_error(errormsg=tid)
    else:
        # create a Job to execute schedule trace
        from pgadmin.browser.server_groups.agents.jobs.schedules.utils import \
            format_schedule_data
        schedule_trace = True
        format_schedule_data(data)
        try:
            status, _ = pem_conn.execute_void('BEGIN;')
            if not status:
                raise RuntimeError(gettext(
                    'Failed to start trace transaction'
                ))

            sql = render_template(
                'profiler/sql/schedule_trace_job.sql',
                data=data,
                create_job=True
            )
            status, job_id = pem_conn.execute_scalar(sql)
            if not status:
                raise RuntimeError(gettext(
                    'Failed to schedule trace job'
                ))
            if job_id is None:
                raise RuntimeError(gettext(
                    'Unable to schedule trace as PEM agent is '
                    'not bound with the database server'
                ))

            sql = render_template(
                'profiler/sql/schedule_trace_job.sql',
                create_job_step=True,
            )
            params = [job_id, trace_sql, data['server_id']]
            status, job_step = pem_conn.execute_void(sql, params)
            if not status:
                raise RuntimeError(gettext(
                    'Failed to schedule trace job step'
                ))

            if 'repeat' in data and data['repeat'] is not None \
                    and data['repeat']:
                sql = render_template(
                    'profiler/sql/schedule_trace_job.sql',
                    create_repeat_job=True,
                    data=data,
                    job_id=job_id
                )
                status, _ = pem_conn.execute_void(sql)
                if not status:
                    raise RuntimeError(gettext(
                        'Failed to schedule periodic '
                        'scheduled sql-profiler job'
                    ))

            # We won't return any trace id as it's schedule trace
            tid = None
            # All done successfully then commit
            status, _ = pem_conn.execute_void('COMMIT;')
            if not status:
                raise RuntimeError(gettext(
                    'Failed to commit the trace transaction'
                ))

        except RuntimeError as e:
            current_app.logger.error(
                "SQL Profiler create new schedule trace operation failed."
                "\nError: {0}".format(str(e))
            )

            status, _ = pem_conn.execute_void('ROLLBACK;')
            if not status:
                # Lets try one more time
                _, _ = pem_conn.execute_void('ROLLBACK;')
            return internal_server_error(errormsg=str(e))

    return make_json_response(
        data={
            'tid': tid,
            'schedule_trace': schedule_trace
        },
        status=200
    )


@blueprint.route(
    '/traces/<trans_id>/<action>',
    methods=["PUT", "GET"], endpoint='action_on_trace'
)
@login_required
@sqlProfilerRole.check_role(
    gettext("Logged-in user do not have permission to perform actions on "
            "trace.")
)
def action_on_trace(trans_id, action):
    """
    This function is used to perform different actions on trace

     Args:
        trans_id: Unique transaction id for trace
        action: Action to be performed on trace

    Returns:
        Response

    """
    is_valid, trace_object = validate_trans_id(trans_id)
    if not is_valid:
        # Return from here as trace id is not valid
        return trace_object

    trace_id = trace_object.get('trace_id')
    sid = trace_object.get('sid')
    status, conn = database_connection(sid, trans_id)
    if not status:
        return conn

    if not conn.connected():
        return precondition_required(
            gettext("Connection to the database server has been lost!")
        )

    # If request is to stop the trace then do following
    if action == 'stop':
        sql = "SELECT public.sp_deactivate('{0}')".format(
            trace_id
        )
        status, result = conn.execute_scalar(sql)
        if not status:
            current_app.logger.error(
                "SQL Profiler stop trace operation failed."
                "\nError: {0}".format(str(result))
            )
            return internal_server_error(errormsg=str(result))

        return make_json_response(
            data=gettext(
                "Trace stopped successfully"
            ),
            status=200
        )

    # If request is to restart the trace then do following
    elif action == 'restart':
        restart_data = request.form if request.form else request.json

        sql = render_template(
            'profiler/sql/get_existing_traces.sql',
            trace_id=trace_id
        )
        status, result = conn.execute_dict(sql)
        if not status:
            current_app.logger.error(
                "SQL Profiler fetch trace operation failed."
                "\nError: {0}".format(str(result))
            )
            return internal_server_error(errormsg=str(result))

        old_data = result['rows'][0]

        old_data['name'] = old_data['comments']
        old_data['trace_file_size'] = old_data['max_size']
        # To load it we need to run it now
        old_data['run_option'] = True

        if old_data.get('log_min_duration', None) is None:

            old_data['log_min_duration'] = (
                restart_data.get('log_min_duration', 0))

        sql = render_template(
            'profiler/sql/create_trace.sql',
            data=old_data
        )
        status, tid = conn.execute_scalar(sql)
        if not status:
            current_app.logger.error(
                "SQL Profiler restart trace operation failed."
                "\nError: {0}".format(str(tid))
            )
            return internal_server_error(errormsg=tid)

        # We need to set new trace id for current transaction in session
        session[trans_id]['trace_id'] = tid

        return make_json_response(
            data={
                'Success': True,
                'trace_id': tid
            }
        )
    elif action == 'filter':
        filter_data = request.form if request.form else request.json
        # If there is no filter data to process
        if not filter_data or len(filter_data.get('filter')) < 1:
            session[trans_id]['filter_sql'] = None
            return make_json_response(
                data={'filter_applied': True}
            )

        try:
            # We will replace pattern with actual value
            condition_mapping = {
                "matches": "ILIKE E'%@@##PATTERN@##@@%'",
                "does_not_match": "NOT ILIKE E'%@@##PATTERN@##@@%'",
                "equals": "= '@@##PATTERN@##@@'",
                "not_equals": "!= '@@##PATTERN@##@@'",
                "starts_with": "ILIKE E'@@##PATTERN@##@@%'",
                "do_not_starts_with": "NOT ILIKE E'@@##PATTERN@##@@%'",
                "less_than": "< '@@##PATTERN@##@@'",
                "greater_than": "> '@@##PATTERN@##@@'",
                "less_than_equalsTo": "<= '@@##PATTERN@##@@'",
                "greater_than_equalsTo": ">= '@@##PATTERN@##@@'"
            }

            query_type_mapping = {
                "SELECT": '1',
                "UPDATE": '2',
                "INSERT": '3',
                "DELETE": '4',
                "UTILIT": '5',
                "NOTHING": '6'
            }

            final_sql = ''
            for filter in filter_data['filter']:
                value = None
                sql = ''
                # If we have more than one condition
                if final_sql != '':
                    sql = '\n AND '

                # Get column name
                column = filter['type']

                # Query type has mapping in integer hence we need below logic
                # If no reverse mapping for query type then set it to 0(zero)
                if column == 'p.query_type':
                    chances = []
                    is_not = False
                    _condition = filter['condition']
                    _value = filter['value'].upper()

                    if 'match' in _condition:
                        chances = list(
                            [x for x in list(
                                query_type_mapping.keys()) if x in _value]
                        )
                    elif 'starts' in _condition:
                        chances = list([
                            x for x in list(query_type_mapping.keys())
                            if x.startswith(_value)]
                        )
                    # If negation in condition then
                    if 'not' in _condition:
                        is_not = True

                    _inner_sql = ''
                    for idx, c in enumerate(chances):
                        if idx > 0:
                            _inner_sql += ' OR '
                        value = query_type_mapping.get(c, '0')
                        condition = condition_mapping.get(
                            "not_equals" if is_not else "equals"
                        ).replace('@@##PATTERN@##@@', value)

                        _inner_sql += '{column} {condition}'.format(
                            column=column,
                            condition=condition
                        )

                    if len(_inner_sql) > 0:
                        sql += '( {0} )'.format(_inner_sql)
                    else:
                        # Check for equal or not equal operation
                        # Above we only check for special case when user
                        # gave match or starts with clause for query type
                        # which is numeric in database
                        value = query_type_mapping.get(_value.upper(), '0')
                        condition = condition_mapping.get(
                            _condition
                        ).replace('@@##PATTERN@##@@', value)
                        sql += '( {column} {condition} )'.format(
                            column=column,
                            condition=condition
                        )
                else:
                    # Get condition & its check value
                    condition = condition_mapping.get(
                        filter['condition']
                    ).replace(
                        '@@##PATTERN@##@@',
                        value or filter['value']
                    )

                    sql += '( {column} {condition} )'.format(
                        column=column,
                        condition=condition
                    )

                # Append into main filter sql
                final_sql += sql

            # Save filter in session
            if len(final_sql) > 0:
                session[trans_id]['filter_sql'] = final_sql
            else:
                session[trans_id]['filter_sql'] = None

        except Exception as e:
            current_app.logger.error(
                "SQL Profiler filter trace data operation failed."
                "\nError: {0}".format(str(e))
            )
            return internal_server_error(errormsg=str(e))

        return make_json_response(
            data={
                'filter_applied': True
            }
        )

    # If request is to restart the trace then do following
    elif action == 'total_rows':
        tid = trace_object.get('tid')
        filter_sql = trace_object.get('filter_sql')

        sql = render_template(
            'profiler/sql/get_total_rows.sql',
            tid=tid,
            filter_sql=filter_sql
        )
        status, result = conn.execute_scalar(sql)
        if not status:
            current_app.logger.error(
                "SQL Profiler get total rows operation failed."
                "\nError: {0}".format(str(result))
            )
            return internal_server_error(errormsg=str(result))

        return make_json_response(
            data={
                'total_rows': result
            }
        )


@blueprint.route('/traces/<_id>/<trace_id>', methods=["DELETE"],
                 endpoint='traces_delete_with_trace_id')
@blueprint.route('/traces/<_id>', methods=["DELETE"],
                 endpoint='traces_delete')
@login_required
@sqlProfilerRole.check_role(
    gettext("Logged-in user do not have permission to clear trace.")
)
def clean_trace(_id, trace_id=None):
    """
    This function is used to clear trace.

    Args:
        _id: Server ID or Transaction ID
             If request comes from Wizard then _id will be
             Server ID else it will be Transaction ID
        trace_id: Trace ID

    Returns:
        Response
    """

    # Note: _id may be server id or transaction id
    # We need to check & take appropriate action

    if trace_id is None:
        # This means we have received transaction id
        is_valid, trace_object = validate_trans_id(_id)
        if not is_valid:
            # Return from here as transaction id is not valid
            return trace_object
        trace_id = trace_object.get('trace_id')
        sid = trace_object.get('sid')
        tid = trace_object.get('tid')
    else:
        # This request is from wizard
        sid = _id
        tid = None

    status, conn = database_connection(sid)
    if not status:
        return conn

    if not conn.connected():
        return precondition_required(
            gettext("Connection to the database server has been lost!")
        )

    # To handle requests from Delete trace dialog
    if tid is None:
        sql = "SET sql_profiler.explain_format = 'json';"
        _, _ = conn.execute_void(sql)
    else:
        # First stop the trace
        sql = "SELECT public.sp_deactivate('{0}');".format(
            trace_id
        )
        _, _ = conn.execute_scalar(sql)

    # Delete the trace
    sql = "SELECT public.sp_cleanup('{0}', true);".format(
        trace_id
    )
    status, result = conn.execute_scalar(sql)
    if not status:
        current_app.logger.error(
            "SQL Profiler delete trace operation failed."
            "\nError: {0}".format(str(result))
        )
        return internal_server_error(errormsg=str(result))

    # Now delete data from temp tables
    if tid is not None:
        sql = "DELETE FROM _sp_tmp_tbl_metrics " \
              "WHERE trace_id = '{0}';".format(tid)
        _, _ = conn.execute_void(sql)

    # Check if trace is deleted successfully
    sql = "SELECT count(*) from public.sp_traces_list() " \
          "WHERE trace_id = '{0}';".format(trace_id)
    status, result = conn.execute_scalar(sql)
    if not status:
        current_app.logger.error(
            "SQL Profiler delete trace data operation failed."
            "\nError: {0}".format(str(result))
        )
        return internal_server_error(errormsg=str(result))

    if int(result) == 0:
        # remove trans_id from the session
        if trace_id is None:
            # This means we have received transaction id
            del session[_id]
        else:
            # find trans_id and delete from session
            trans_id = None
            if 'SQL_PROFILER_ACTIVE_SESSIONS' in session:
                for sess in session['SQL_PROFILER_ACTIVE_SESSIONS']:
                    if sess['trans_id'] in session:
                        for key, value in list(
                            session[sess['trans_id']].items()
                        ):
                            if key == 'trace_id' and value == trace_id:
                                trans_id = sess['trans_id']
                                break
            if trans_id:
                del session[trans_id]

        return make_json_response(
            data={'Status': gettext("Trace deleted successfully")},
            status=200
        )
    else:
        return internal_server_error(
            errormsg=gettext("Trace does not deleted successfully")
        )


def handle_load_trace_errors(trans_id, error_details=None):
    """
    This will handle the error response
    Args:
        trans_id: Unique transaction id
        error_details: Error information

    Returns:
        Response page
    """
    # Clear session data
    if trans_id in session:
        del session[trans_id]

    error_header = gettext('Loading of a trace is failed due to an error, '
                           'Please try again.')

    current_app.logger.error(
        "Could not load a trace due to an error (trans_id: {0})."
        "\nError: {1}".format(
            trans_id, error_details
        )
    )

    # Return error page to display in panel
    # ToDo: Replaced the old logic of returning the error.html content with
    #  internal server error, need to replace this in future with
    #  more accurate error message.
    return internal_server_error(errormsg=str(error_details))


@blueprint.route('/traces/open/<sid>/<trace_id>', methods=["GET"],
                 endpoint='traces_open')
@pgCSRFProtect.exempt
@login_required
@sqlProfilerRole.check_role(
    gettext("Logged-in user do not have permission to load trace.")
)
def open_and_load_trace(sid, trace_id):
    """
    This function is used to open & load trace.
    Args:
        sid: Server ID
        trace_id: Trace ID

    Returns:
        Response
    """
    # Create a unique id for the transaction & open the trace
    import random
    trans_id = str(
        random.randint(1, 999999) +
        random.randint(1, 999999)
    )

    # We need to store trace_id and its server_id in session
    try:
        manager = get_driver(PG_DEFAULT_DRIVER).connection_manager(int(sid))
        conn = manager.connection(conn_id=trans_id)
    except Exception as e:
        return handle_load_trace_errors(trans_id, str(e))

    # Connect the Server
    status, msg = conn.connect()
    if not status:
        return handle_load_trace_errors(trans_id, str(msg))

    # Save everything into session
    if 'SQL_PROFILER_ACTIVE_SESSIONS' not in session:
        session['SQL_PROFILER_ACTIVE_SESSIONS'] = []
    session['SQL_PROFILER_ACTIVE_SESSIONS'].append({
        'trans_id': trans_id,
        'sid': sid
    })
    session[trans_id] = {
        'trace_id': trace_id,
        'sid': sid
    }

    # run the trace initialization code
    data = trace_initialization(trans_id, manager)

    return render_template(
        "profiler/profiler.html",
        _=gettext,
        requirejs=True,
        basejs=True,
        sid=sid,
        trace_id=trace_id,
        title=gettext('SQL Profiler (Trace: %s)' % data['comments']),
        trans_id=trans_id
    )


def trace_initialization(trans_id, manager):
    """
    This function will runs initialization code trace

    Args:
        manager: Connection manager
        trans_id: Unique transaction id for trace

    Returns:
        None
    """
    trace_object = session.get(trans_id)
    trace_id = trace_object.get('trace_id')
    sid = trace_object.get('sid')
    status, conn = database_connection(sid, trans_id)
    if not status:
        return handle_load_trace_errors(
            trans_id, gettext("Could not find the requested server.")
        )

    user = manager.user_info

    # Make logging silent
    status, res = conn.execute_scalar(
        render_template(
            "profiler/sql/trace_connection_initialization.sql",
            _=gettext,
            user=user,
            make_log_silent=True
        )
    )
    if not status:
        return handle_load_trace_errors(trans_id, str(res))

    # Check if profile_version function is present
    status, is_function_present = conn.execute_scalar(
        render_template(
            "profiler/sql/trace_connection_initialization.sql",
            _=gettext,
            check_profiler_version_function=True
        )
    )
    if not status:
        return handle_load_trace_errors(trans_id, str(is_function_present))

    if int(is_function_present) == 1:
        # Get the  profile plugin version
        status, plugin_version = conn.execute_scalar(
            render_template(
                "profiler/sql/trace_connection_initialization.sql",
                _=gettext,
                get_profiler_version=True
            )
        )
        if not status:
            return handle_load_trace_errors(trans_id, str(plugin_version))

        if float(plugin_version) >= 3.0:
            # Get the  profile plugin version
            status, res = conn.execute_scalar(
                render_template(
                    "profiler/sql/trace_connection_initialization.sql",
                    _=gettext,
                    use_array_for_paramas=True
                )
            )
            if not status:
                return handle_load_trace_errors(trans_id, str(res))

    # Load the trace
    status, res = conn.execute_scalar(
        render_template(
            "profiler/sql/trace_connection_initialization.sql",
            _=gettext,
            load_trace=True,
            trace_id=trace_id
        )
    )
    if not status:
        return handle_load_trace_errors(trans_id, str(res))

    # Fetch tid and save it in session
    status, tid = conn.execute_scalar(
        render_template(
            "profiler/sql/trace_connection_initialization.sql",
            _=gettext,
            fetch_tid=True,
            trace_id=trace_id
        )
    )
    if not status:
        return handle_load_trace_errors(trans_id, str(tid))

    status, res = conn.execute_dict(
        render_template(
            'profiler/sql/get_existing_traces.sql',
            trace_id=trace_id
        )
    )
    if not status:
        return handle_load_trace_errors(trans_id, str(tid))

    data = res['rows'][0]

    # Save tid in session
    session[trans_id]['tid'] = tid

    return data


@blueprint.route(
    '/traces/refresh/<trans_id>/<int:page_number>/<int:page_size>',
    methods=["GET"], endpoint='traces_refresh_data'
)
@blueprint.route(
    '/traces/execute/<trans_id>/<int:page_number>/<int:page_size>',
    methods=["GET"], endpoint='traces_execute_data'
)
@blueprint.route(
    '/traces/execute/<trans_id>/<int:page_number>/<int:page_size>/'
    '<column>/<order_by>', endpoint='traces_execute_data_with_filter',
    methods=["GET"]
)
@login_required
@sqlProfilerRole.check_role(
    gettext("Logged-in user do not have permission to execute sql on trace "
            "data.")
)
def get_trace_data(
        trans_id, page_number=None, page_size=None,
        column=None, order_by=None
):
    """
    This function is used to execute sql for trace data.

    Args:
        trans_id: Unique transaction id for trace
        page_number: Requested page [Offset]
        page_size: Requested limit for the page [Limit]
        column: Column to be sort [Optional]
        order_by: Sort order [Optional]

    Returns:
        Status of query execution
    """
    is_valid, trace_object = validate_trans_id(trans_id)
    if not is_valid:
        # Return from here as trace id is not valid
        return trace_object
    trace_id = trace_object.get('trace_id')
    sid = trace_object.get('sid')
    status, conn = database_connection(sid, trans_id)
    if not status:
        return conn

    if not conn.connected():
        return precondition_required(
            gettext("Connection to the database server has been lost!")
        )

    # Load the trace again
    status, res = conn.execute_scalar(
        render_template(
            "profiler/sql/trace_connection_initialization.sql",
            _=gettext,
            load_trace=True,
            trace_id=trace_id
        )
    )
    if not status:
        current_app.logger.error(
            "SQL Profiler trace initialization failed."
            "\nError: {0}".format(str(res))
        )
        return internal_server_error(errormsg=str(res))

    # Load the trace again as user clicked on start trace button
    if request.base_url.find('/refresh/') > -1:
        # Re-create trace & then Fetch tid for new trace id
        # and save it in session
        status, tid = conn.execute_scalar(
            render_template(
                "profiler/sql/trace_connection_initialization.sql",
                _=gettext,
                fetch_tid=True,
                trace_id=trace_id
            )
        )
        if not status:
            current_app.logger.error(
                "SQL Profiler trace refresh operation failed."
                "\nError: {0}".format(str(tid))
            )
            return internal_server_error(errormsg=str(tid))

        # Save tid in session
        session[trans_id]['tid'] = tid

    # Get update metrics query
    sql = update_trace_metrics(trans_id)

    # Fetch data query
    sql += get_trace_data_query(
        trans_id, page_number, page_size, column, order_by
    )

    # run the query in async mode
    status, res = conn.execute_async(sql)
    if not status:
        current_app.logger.error(
            "SQL Profiler run async query operation failed."
            "\nError: {0}".format(str(res))
        )
        return internal_server_error(errormsg=str(res))

    return make_json_response(
        data={
            'status': status,
            'result': gettext("Success")
        }
    )


@blueprint.route('/traces/poll/<trans_id>', methods=["GET"],
                 endpoint='traces_poll_data')
@login_required
@sqlProfilerRole.check_role(
    gettext("Logged-in user do not have permission to poll result for trace "
            "data.")
)
def poll_trace_data(trans_id):
    """
    This function is used to poll the result for trace data.

    Args:
        trans_id: Unique transaction id for trace

    Returns:
        Query result/status
    """
    is_valid, trace_object = validate_trans_id(trans_id)
    if not is_valid:
        # Return from here as trans id is not valid
        return trace_object

    sid = trace_object.get('sid')
    status, conn = database_connection(sid, trans_id)
    if not status:
        return conn

    if not conn.connected():
        return precondition_required(
            gettext("Connection to the database server has been lost!")
        )

    if conn.connected():
        statusmsg = conn.status_message()
        status, result = conn.poll()
        if status == ASYNC_OK:
            if result:
                if 'ERROR' in result:
                    status = 'ERROR'
                    return make_json_response(
                        info=gettext("Execution completed with error"),
                        data={'status': status, 'status_message': result,
                              'result': result}
                    )
                else:
                    status = 'Success'
                    columns = []
                    col_info = conn.get_column_info()
                    # Check column info is available or not
                    if col_info is not None and len(col_info) > 0:
                        for col in col_info:
                            items = list(col.items())
                            column = dict()
                            column['name'] = items[0][1]
                            column['type_code'] = items[1][1]
                            columns.append(column)

                    return make_json_response(
                        success=1,
                        info=gettext("Execution Completed."),
                        data={
                            'status': status, 'result': result,
                            'col_info': columns, 'status_message': statusmsg
                        }
                    )
            else:
                # Execution complete but no rows returned
                return make_json_response(
                    success=1,
                    info=gettext("Execution Completed."),
                    data={
                        'status': 'Success', 'result': [],
                        'col_info': None, 'status_message': statusmsg
                    }
                )
        else:
            status = 'Busy'

    return make_json_response(
        data={
            'status': status, 'result': result, 'status_message': statusmsg
        }
    )


@blueprint.route('/traces/metrics/<trans_id>/<query_id>', methods=["GET"],
                 endpoint='traces_metrics')
@login_required
@sqlProfilerRole.check_role(
    gettext("Logged-in user do not have permission to access metrics for "
            "given sql.")
)
def get_metrics(trans_id, query_id):
    """
    This function will send metrics result for the given sql.

    Args:
        trans_id: Unique transaction id for trace
        query_id: Query ID for selected SQL

    Returns:
        Trace data
    """
    is_valid, trace_object = validate_trans_id(trans_id)
    if not is_valid:
        # Return from here as trans id is not valid
        return trace_object
    tid = trace_object.get('tid')
    sid = trace_object.get('sid')
    status, conn = database_connection(sid, trans_id)
    if not status:
        return conn

    calculated_metics = dict()

    if not conn.connected():
        return precondition_required(
            gettext("Connection to the database server has been lost!")
        )

    # Fetch overall metrics data
    sql = render_template(
        'profiler/sql/fetch_metrics.sql',
        overall_trace_metrics=True,
        tid=tid
    )

    status, overall_rset = conn.execute_dict(sql)
    if not status:
        current_app.logger.error(
            "SQL Profiler get trace metrics operation failed."
            "\nError: {0}".format(str(overall_rset))
        )
        return internal_server_error(errormsg=str(overall_rset))

    overall_rset = overall_rset['rows'][0] or None

    # Fetch metrics data for selected query id
    sql = render_template(
        'profiler/sql/fetch_metrics.sql',
        metrics_for_query_id=True,
        tid=tid,
        query_id=query_id
    )

    status, query_rset = conn.execute_dict(sql)
    if not status:
        current_app.logger.error(
            "SQL Profiler fetch trace metrics operation failed."
            "\nError: {0}".format(str(query_rset))
        )
        return internal_server_error(errormsg=str(query_rset))

    query_rset = query_rset['rows'][0] or None

    for result in overall_rset:
        # Calculate % data for overall metrics count against
        # currently selected query_id metrics
        if query_rset[result] is None or \
                int(query_rset[result]) < 0 or \
                overall_rset[result] is None or \
                int(overall_rset[result]) <= 0:
            percent = 0
        else:
            percent = int(
                (int(query_rset[result]) / int(overall_rset[result])) * 100
            )

        # We need both total executed query count as well as
        #  overall query execution as a calculated %
        if result == 'executed':
            calculated_metics['execution'] = percent
            calculated_metics[result] = query_rset[result]
        else:
            calculated_metics[result] = percent

    return make_json_response(
        data=calculated_metics
    )


@blueprint.route('/traces/save_file', methods=["POST"],
                 endpoint='traces_save_file')
@login_required
@sqlProfilerRole.check_role(
    gettext("Logged-in user do not have permission to save trace filters "
            "to file.")
)
def save_file():
    """
    This function is used to Save trace filters to file
    """
    import os
    import json
    request_data = request.json or json.loads(request.data.decode())
    # retrieve storage directory path
    storage_manager_path = get_storage_directory()
    filename = request_data.get('filename')
    filter_data = {
        'filter': request_data.get('filter')
    }

    if filename is None:
        return internal_server_error(errormsg=gettext(
            "Please provide filename"
        ))

    if storage_manager_path is not None:
        file_path = os.path.join(
            storage_manager_path,
            filename.lstrip('/')
        )
    else:
        return internal_server_error(errormsg=gettext(
            "Please provide storage directory path in config file"
        ))

    # write to file
    try:
        with open(file_path, 'w') as outfile:
            json.dump(
                filter_data, outfile, ensure_ascii=False,
                sort_keys=True, indent=4
            )
    except Exception as e:
        err_msg = "Error: {0}".format(str(e))
        return internal_server_error(errormsg=err_msg)

    return make_json_response(
        data={
            'status': True
        }
    )


@blueprint.route('/traces/load_file', methods=["POST"],
                 endpoint='traces_load_file')
@login_required
@sqlProfilerRole.check_role(
    gettext("Logged-in user do not have permission to load trace filters "
            "from file.")
)
def load_file():
    """
    This function is used to load trace filters from file
    """
    import os
    import json

    request_data = request.json or json.loads(request.data.decode())
    # retrieve storage directory path
    storage_manager_path = get_storage_directory()
    filename = request_data.get('filename')

    if filename is None:
        return internal_server_error(errormsg=gettext(
            "Please provide filename"
        ))

    if storage_manager_path is not None:
        file_path = os.path.join(
            storage_manager_path,
            filename.lstrip('/')
        )
    else:
        return internal_server_error(errormsg=gettext(
            "Please provide storage directory path in config file"
        ))

    # Read from file
    try:
        with open(file_path, 'r') as outfile:
            filter_data = json.load(outfile)
    except Exception as e:
        err_msg = "Error: {0}".format(str(e))
        return internal_server_error(errormsg=err_msg)

    return make_json_response(
        data={
            'result': filter_data,
            'status': True
        }
    )


@blueprint.route('/traces/scheduled/<int:server_id>', methods=["GET"],
                 endpoint='traces_scheduled_list')
@pem_connection
@login_required
@sqlProfilerRole.check_role(
    gettext("Logged-in user do not have permission to access schedules "
            "traces list.")
)
def scheduled_trace_list(server_id=None, pem_conn=None):
    """
    This function is used to list all the scheduled traces
    for the given server & its associated agent

    Args
        server_id: Server ID
        pem_conn: PEM connection

    Returns
        List of scheduled traces
    """
    try:
        sql = render_template('profiler/sql/schedule_trace_list.sql')
        params = [server_id, server_id]
        status, rset = pem_conn.execute_dict(sql, params)
        if not status:
            raise RuntimeError(gettext(
                'Failed to fetch schedule traces'
            ))
    except Exception as e:
        current_app.logger.error(
            "SQL Profiler fetch schedule trace operation failed."
            "\nError: {0}".format(str(e))
        )
        return internal_server_error(errormsg=str(e))

    return ajax_response(
        response={'tasks': rset['rows']},
        status=200
    )


@blueprint.route('/traces/scheduled/<int:job_id>/steps', methods=["GET"],
                 endpoint='traces_scheduled_step')
@pem_connection
@login_required
@sqlProfilerRole.check_role(
    gettext("Logged-in user do not have permission to access stesp for "
            "schedules trace.")
)
def scheduled_trace_step(job_id=None, pem_conn=None):
    """
    This function is used to list all the steps for scheduled trace
    for the given job id

    Args
        job_id: Task/Job ID
        pem_conn: PEM connection

    Returns
        List of steps for task/job
    """
    try:
        sql = render_template('profiler/sql/schedule_trace_steps.sql')
        params = [job_id]
        status, rset = pem_conn.execute_dict(sql, params)
        if not status:
            raise RuntimeError(gettext(
                'Failed to run schedule trace steps query'
            ))
    except Exception as e:
        current_app.logger.error(
            "SQL Profiler schedule trace job steps operation failed."
            "\nError: {0}".format(str(e))
        )
        return internal_server_error(errormsg=str(e))

    return ajax_response(
        response=rset['rows'],
        status=200
    )


@blueprint.route('/traces/scheduled/<int:job_id>', methods=["DELETE"],
                 endpoint='traces_delete_scheduled')
@pem_connection
@login_required
@sqlProfilerRole.check_role(
    gettext("Logged-in user do not have permission to delete stesp for "
            "schedules trace.")
)
def delete_scheduled_trace(job_id=None, pem_conn=None):
    """
    This function is used to delete scheduled trace
    for the given job id

    Args
        job_id: Task/Job ID
        pem_conn: PEM connection

    Returns
        Status
    """
    try:
        sql = render_template('profiler/sql/delete_schedule_trace_job.sql')
        params = [job_id]
        status, job_step = pem_conn.execute_void(sql, params)
        if not status:
            raise RuntimeError(gettext(
                'Failed to delete schedule trace job'
            ))

    except RuntimeError as e:
        status, res = pem_conn.execute_void('ROLLBACK;')
        if not status:
            # Lets try one more time
            _, _ = pem_conn.execute_void('ROLLBACK;')
        return internal_server_error(errormsg=str(e))

    return make_json_response(
        data={
            'status': True,
            'info': gettext("Schedule trace job deleted successfully")
        },
        status=200
    )


@blueprint.route('/traces/<trans_id>/server', methods=["GET"],
                 endpoint='traces_server_info')
@login_required
@sqlProfilerRole.check_role(
    gettext("Logged-in user do not have permission to fetch server "
            "information.")
)
@pem_connection
def get_server_info(trans_id, pem_conn=None):
    """
    This function is used fetch server group and server information

     Args:
        trans_id: Unique transaction id for trace
        pem_conn: PEM database connection object

    Returns:
        Server information
    """
    is_valid, trace_object = validate_trans_id(trans_id)
    if not is_valid:
        # Return from here as trans id is not valid
        return trace_object
    sid = trace_object.get('sid')

    # Try to fetch it from session first
    if 'sgid' in trace_object:
        sgid = trace_object.get('sgid')
        name = trace_object.get('server_name')
        is_agent_binded = trace_object.get('is_agent_binded')
    else:
        status, name = pem_conn.execute_scalar(
            "SELECT description FROM pem.server WHERE id=(%s)",
            [sid]
        )
        if not status:
            current_app.logger.error(
                "SQL Profiler get server information operation failed."
                "\nError: {0}".format(str(name))
            )
            return internal_server_error(errormsg=gettext(
                'Failed to fetch server information'
            ))

        status, sgid = pem_conn.execute_scalar(
            "SELECT server_group_id FROM "
            "pem.server_options WHERE server_id=(%s)",
            [sid]
        )
        if not status:
            current_app.logger.error(
                "SQL Profiler get server group operation failed."
                "\nError: {0}".format(str(sgid))
            )
            return internal_server_error(errormsg=gettext(
                'Failed to fetch server information'
            ))
        status, agent_id = pem_conn.execute_scalar(
            "SELECT agent_id FROM "
            "pem.agent_server_binding WHERE server_id=(%s)",
            [sid]
        )
        if not status:
            current_app.logger.error(
                "SQL Profiler get server agent id operation failed."
                "\nError: {0}".format(str(sgid))
            )
            return internal_server_error(errormsg=gettext(
                'Failed to fetch server information'
            ))

        is_agent_binded = True if agent_id else False
        # Save it in session, so that next don't need to execute sql
        session[trans_id]['sgid'] = sgid
        session[trans_id]['server_name'] = name
        session[trans_id]['is_agent_binded'] = is_agent_binded

    return make_json_response(
        data={
            'sgid': int(sgid),
            'sid': int(sid),
            'server_name': name,
            'is_agent_binded': is_agent_binded
        },
        status=200
    )


@blueprint.route('/traces/<trans_id>/download', methods=["GET"],
                 endpoint='traces_download')
@pgCSRFProtect.exempt
@login_required
@sqlProfilerRole.check_role(
    gettext("Logged-in user do not have permission to send all trace details.")
)
def send_csv(trans_id):
    """
    This function is used send csv file with all the
    trace details

     Args:
        trans_id: Unique transaction id for trace

    Returns:
        CSV file as response
    """
    sync_conn = None

    is_valid, trace_object = validate_trans_id(trans_id)
    if not is_valid:
        # Return from here as trans id is not valid
        return trace_object
    trace_id = trace_object.get('trace_id')
    sid = trace_object.get('sid')
    csv_file_name = "complete_trace_" + str(trace_id) + ".csv"

    try:
        status, conn = database_connection(sid, trans_id)
        if not status:
            raise RuntimeError(
                gettext("Connection to the database server has been lost!")
            )

        conn_id = str(random.randint(1, 9999999))
        sync_conn = conn.manager.connection(
            conn_id=conn_id,
            auto_reconnect=False,
            async_=False
        )

        sync_conn.connect(autocommit=False)

        if not sync_conn.connected():
            raise RuntimeError(
                gettext("Connection to the database server has been lost!")
            )

        def cleanup():
            """Release connection"""
            conn.manager.connections[sync_conn.conn_id]._release()
            del conn.manager.connections[sync_conn.conn_id]

        # Load the trace again
        status, res = sync_conn.execute_scalar(
            render_template(
                "profiler/sql/trace_connection_initialization.sql",
                _=gettext,
                load_trace=True,
                trace_id=trace_id
            )
        )
        if not status:
            raise RuntimeError(
                gettext("Unable to load the trace.")
            )

        # Fetch data query for CSV which will exclude
        # row number and explain data
        sql = get_trace_data_query(
            trans_id, None, None, None, None, True
        )

        status, res = sync_conn.execute_2darray(sql)
        if not status:
            raise RuntimeError(
                gettext("Unable to fetch the trace data.")
            )

        # Prepare Header for CSV
        header_columns = []
        for column in res['columns']:
            header_columns.append(column['name'])

        res_io = StringIO()

        csv_writer = csv.DictWriter(
            res_io, delimiter=',', quoting=csv.QUOTE_NONNUMERIC,
            fieldnames=header_columns
        )
        csv_writer.writeheader()
        for row in res['rows']:
            csv_writer.writerow(row)

        resp = Response(
            res_io.getvalue(), mimetype='text/csv'
        )

        # Prepare proper csv response
        resp.headers[
            "Content-Disposition"
        ] = "attachment;filename={0}".format(csv_file_name)

        # Do clean up now
        resp.call_on_close(cleanup)

        return resp

    except Exception as e:
        current_app.logger.error(
            "SQL Profiler CSV download failed."
            "\nError: {0}".format(str(e))
        )
        resp = Response('"{0}"'.format(e), mimetype='text/csv', status=500)
        resp.headers["Content-Disposition"] = "attachment;filename=error.csv"
        return resp


@blueprint.route('/traces/<trans_id>/close', methods=["DELETE"],
                 endpoint='trace_close')
@login_required
@sqlProfilerRole.check_role(
    gettext("Logged-in user do not have permission to send all trace details.")
)
def release_connection(trans_id):
    """
    When user close the Panel we need to release the connection

    :param trans_id:
    :return:
    """
    is_valid, session_obj = validate_trans_id(trans_id)
    if not is_valid:
        return session_obj
    session_obj['trans_id'] = trans_id
    release_sql_profiler_connection(session_obj)
    del session[trans_id]
    idx = 0
    for session_obj in session['SQL_PROFILER_ACTIVE_SESSIONS']:
        if session_obj['trans_id'] == trans_id:
            break
        idx += 1
    del session['SQL_PROFILER_ACTIVE_SESSIONS'][idx]
    return make_json_response(data={'status': 'Success'}, status=200)


def on_logout(self, user):
    """
    This is a callback function when user logsout from PEM
    Here we will release all the connection created by SQL Profiler if any
    """
    with sql_profiler_session_lock:
        if 'SQL_PROFILER_ACTIVE_SESSIONS' in session:
            for session_obj in session['SQL_PROFILER_ACTIVE_SESSIONS']:
                release_sql_profiler_connection(session_obj)
            # release all the connections
            del session['SQL_PROFILER_ACTIVE_SESSIONS']


def release_sql_profiler_connection(session_obj):
    manager = get_driver(PG_DEFAULT_DRIVER).connection_manager(
        int(session_obj['sid'])
    )
    if manager is not None:
        conn = manager.connection(conn_id=session_obj['trans_id'])
        if conn.connected():
            conn.cancel_transaction(session_obj['trans_id'])
            manager.release(conn_id=session_obj['trans_id'])
