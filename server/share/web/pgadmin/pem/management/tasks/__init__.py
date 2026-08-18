##########################################################################
#
# Postgres Enterprise Manager
#
# Copyright (C) 2016 - 2025, EnterpriseDB Corporation. All rights reserved.
#
##########################################################################

"""Implements Tasks"""

from flask import render_template
from flask_babel import gettext
from pgadmin.utils.ajax import internal_server_error, \
    bad_request, make_response, make_json_response
from pgadmin.utils import PgAdminModule
from flask import Response, url_for, stream_with_context, request
from flask_security import login_required
from pgadmin.pem.utils import pem_connection
from pgadmin.pem.utils.role import scheduleTaskRole
from pgadmin.utils.preferences import Preferences
from pgadmin.utils.csrf import pgCSRFProtect

MODULE_NAME = 'tasks'


class TasksModule(PgAdminModule):
    """
    class TasksModule(PgAdminModule):
        Implementation of Task class for Task Module.
    """

    LABEL = gettext('Scheduled Tasks')

    def get_own_stylesheets(self):
        """
        Returns:
            list: the stylesheets used by this module.
        """
        stylesheets = [
            url_for('management.static', filename='css/management.css'),
            url_for('tasks.static',
                    filename='css/tasks.css')
        ]
        return stylesheets

    def register_preferences(self):
        self.preference.register(
            'options', 'auto_refresh_interval',
            gettext("Auto refresh interval"), 'integer', 0,
            min_val=0,
            category_label=gettext('Options'),
            help_str=gettext('Auto refresh interval in seconds. '
                             'Set 0 to disabled auto refresh.')
        )
        self.preference.register(
            'options', 'number_of_characters_from_logs',
            gettext("Number of characters"), 'integer', 250,
            min_val=50,
            category_label=gettext('Options'),
            help_str=gettext('Number of characters to read from the backend '
                             'for the job step output column')
        )

    def get_exposed_url_endpoints(self):
        """
        Returns:
            list: a list of url endpoints exposed to the client.
        """
        return [
            'tasks.task_by_execution_date', 'tasks.task_steps',
            'tasks.agent_task', 'tasks.server_task',
            'tasks.database_task', 'tasks.delete_tasks',
            'tasks.get_step_output', 'tasks.agent_task_instances',
            'tasks.server_task_instances', 'tasks.database_task_instances'
        ]


# Create blueprint for Scheduled Tasks class
blueprint = TasksModule(
    MODULE_NAME, __name__, static_url_path='',
    url_prefix="/pem/tasks")


@blueprint.route("/")
@login_required
def index():
    return bad_request(errormsg=gettext(
        "This URL cannot be called directly!")
    )


@blueprint.route('/agent/<int:agent_id>/task',
                 methods=["GET"],
                 defaults={'sys_tasks': -1})
@blueprint.route('/agent/<int:agent_id>/task/<int:sys_tasks>',
                 methods=["GET"], endpoint='agent_task')
@pem_connection
@login_required
@scheduleTaskRole.check_role(
    gettext("Logged-in user do not have permission to access agent task.")
)
def agent_task(agent_id, sys_tasks=-1, pem_conn=None):
    """
    This function is used to get the list of
    scheduled tasks of agent, server or database.

    :param agent_id: agent id
    :param sys_tasks: 1 show system tasks other than 1 hide system task.
    :param pem_conn: PEM Connection object.
    """
    page = request.args.get('page', default=1, type=int)
    page_size = request.args.get('page_size', default=100, type=int)
    offset = (page - 1) * page_size
    search_query = ' & '.join(
        request.args.get('search_query', default='', type=str).split()
    )

    params = {
        'server_id': -1,
        'db_name': -1,
        'show_sys_tasks': sys_tasks,
        'agent_id': agent_id,
        'offset': offset,
        'page_size': page_size,
        'search_query': search_query,
        'search_query_like': f"%{search_query}%" if search_query else None
    }

    status, res = get_tasks(params, pem_conn)

    if not status:
        return internal_server_error(errormsg=res)

    return make_response(res)


@blueprint.route(
    '/server/<int:server_id>/task',
    methods=["GET"],
    defaults={'db_name': -1, 'sys_tasks': -1})
@blueprint.route(
    '/server/<int:server_id>/task/<int:sys_tasks>',
    methods=["GET"],
    defaults={'db_name': -1},
    endpoint='server_task')
@blueprint.route(
    '/server/<int:server_id>/database/<path:db_name>/task',
    methods=["GET"],
    defaults={'sys_tasks': -1})
@blueprint.route(
    '/server/<int:server_id>/database/<path:db_name>/task/<int:sys_tasks>',
    methods=["GET"],
    endpoint='database_task')
@pem_connection
@login_required
@scheduleTaskRole.check_role(gettext(
    "Logged-in user do not have permission to access server or database task."
))
def server_database_task(server_id, db_name, sys_tasks, pem_conn=None):
    """
    This function is used to get the list of
    scheduled tasks of server or database.

    :param server_id: server id
    :param db_name: database name
    :param sys_tasks: 1 show system tasks other than 1 hide system task.
    :param pem_conn: PEM Connection object.
    """

    page = request.args.get('page', default=1, type=int)
    page_size = request.args.get('page_size', default=100, type=int)
    offset = (page - 1) * page_size
    search_query = ' & '.join(
        request.args.get('search_query', default='', type=str).split()
    )

    params = {
        'server_id': server_id,
        'db_name': db_name,
        'show_sys_tasks': sys_tasks,
        'agent_id': -1,
        'offset': offset,
        'page_size': page_size,
        'search_query': search_query,
        'search_query_like': f"%{search_query}%" if search_query else None
    }

    status, res = get_tasks(params, pem_conn)

    if not status:
        return internal_server_error(errormsg=res)

    return make_response(res)


@blueprint.route(
    '/instances/server/<int:server_id>/sys_task',
    methods=["GET"],
    defaults={'db_name': -1, 'sys_tasks': -1}
)
@blueprint.route(
    '/instances/server/<int:server_id>/sys_task/<int:sys_tasks>',
    methods=["GET"],
    defaults={'db_name': -1},
    endpoint='server_task_instances'
)
@blueprint.route(
    '/instances/server/<int:server_id>/database/<path:db_name>/sys_task',
    methods=["GET"],
    defaults={'sys_tasks': -1}
)
@blueprint.route(
    '/instances/server/<int:server_id>/database/<path:db_name>/sys_task/'
    '<int:sys_tasks>',
    methods=["GET"],
    endpoint='database_task_instances'
)
@pem_connection
@login_required
@scheduleTaskRole.check_role(gettext(
    "Logged-in user do not have permission to access task by execution date."
))
def server_task_instances(server_id, db_name, sys_tasks=-1, pem_conn=None):
    """
    This function is used to get the list of job
    instances for server or database.

    :param task_id: task id
    :param pem_conn: PEM Connection object.
    :return:
    """
    page = request.args.get('page', default=1, type=int)
    page_size = request.args.get('page_size', default=100, type=int)
    offset = (page - 1) * page_size
    search_query = ' & '.join(
        request.args.get('search_query', default='', type=str).split()
    )

    params = {
        'server_id': server_id,
        'db_name': db_name,
        'show_sys_tasks': sys_tasks,
        'agent_id': -1,
        'offset': offset,
        'page_size': page_size,
        'search_query': search_query,
        'search_query_like': f"%{search_query}%" if search_query else None
    }

    status, res = get_task_instances(params, pem_conn)

    if not status:
        return internal_server_error(errormsg=res)

    return make_response(res)


@blueprint.route('/instances/agent/<int:agent_id>/sys_task',
                 methods=["GET"],
                 defaults={'sys_tasks': -1})
@blueprint.route('/instances/agent/<int:agent_id>/sys_task/<int:sys_tasks>',
                 methods=["GET"], endpoint='agent_task_instances')
@pem_connection
@login_required
@scheduleTaskRole.check_role(gettext(
    "Logged-in user do not have permission to access task by execution date."
))
def agent_task_instances(agent_id, sys_tasks=-1, pem_conn=None):
    """
    This function is used to get the list of job
    instances for agent.

    :param task_id: task id
    :param pem_conn: PEM Connection object.
    :return:
    """
    page = request.args.get('page', default=1, type=int)
    page_size = request.args.get('page_size', default=100, type=int)
    offset = (page - 1) * page_size
    search_query = ' & '.join(
        request.args.get('search_query', default='', type=str).split()
    )

    params = {
        'server_id': -1,
        'db_name': -1,
        'show_sys_tasks': sys_tasks,
        'agent_id': agent_id,
        'offset': offset,
        'page_size': page_size,
        'search_query': search_query,
        'search_query_like': f"%{search_query}%" if search_query else None
    }

    status, res = get_task_instances(params, pem_conn)

    if not status:
        return internal_server_error(errormsg=res)

    return make_response(res)


def get_task_instances(params, pem_conn):
    sql_data = render_template('tasks/sql/task_history.sql', data=params)
    status, res = pem_conn.execute_dict(sql_data, params)

    if not status:
        return status, res

    sql_count = render_template(
        'tasks/sql/task_history_count.sql', data=params
    )
    status_count, res_count = pem_conn.execute_dict(sql_count, params)

    if not status_count:
        return status_count, res_count

    total_count = (
        res_count['rows'][0]['total_rows'] if res_count['rows'] else 0
    )

    return True, {'rows': res['rows'], 'total_count': total_count}


@blueprint.route('/task/<int:task_id>/date',
                 methods=["GET"],
                 endpoint='task_by_execution_date')
@pem_connection
@login_required
@scheduleTaskRole.check_role(gettext(
    "Logged-in user do not have permission to access task by execution date."
))
def task_by_execution_date(task_id, pem_conn=None):
    """
    This function is used to get the list of
    jod of given jod id grouped by execution date.

    :param task_id: task id
    :param pem_conn: PEM Connection object.
    :return:
    """

    sql = render_template(
        'tasks/sql/task_log_by_execution_day.sql'
    )

    # Execute the query.
    status, res = pem_conn.execute_dict(sql, {'jid': task_id})

    if not status:
        return internal_server_error(errormsg=res)

    return make_response(
        response=res['rows']
    )


@blueprint.route('/task/<int:task_id>/jblogid/<int:job_log_id>',
                 methods=["GET"],
                 endpoint='task_steps')
@pem_connection
@login_required
@scheduleTaskRole.check_role(
    gettext("Logged-in user do not have permission to access task steps.")
)
def task_steps(task_id, job_log_id, pem_conn=None):
    """
    This function is used to get the list of
    jod steps of given jod id on given date.

    :param task_id: task id
    :param date: date in ths format YYYY-MM-DD
    :param pem_conn: PEM Connection object.
    :return:
    """
    # Get the max string count we need to fetch from output column
    perf = Preferences.module('tasks')
    max_chars = perf.preference(
        'number_of_characters_from_logs'
    ).get()
    sql = render_template(
        'tasks/sql/history_step_list.sql',
        max_chars=max_chars
    )

    # Execute the query.
    status, res = pem_conn.execute_dict(
        sql,
        {
            'jid': task_id,
            'job_log_id': job_log_id
        }
    )

    if not status:
        return internal_server_error(errormsg=res)

    return make_response(
        response=res['rows']
    )


@blueprint.route('/task/<path:task_ids>',
                 methods=["DELETE"],
                 endpoint='delete_tasks')
@pem_connection
@login_required
@scheduleTaskRole.check_role(
    gettext("Logged-in user do not have permission to delete task.")
)
def delete_tasks(task_ids, pem_conn=None):
    """
    This function is used to delete tasks.

    :param pem_conn: PEM Connection object.
    :param task_ids: task ids to delete.
    """
    task_id_list = task_ids.split('/')

    try:
        for task_id in task_id_list:
            task_id = int(task_id)
    except Exception:
        return bad_request(gettext('task ids are not valid integer value.'))

    data = tuple(task_id_list)

    sql = render_template('tasks/sql/check_tasks.sql')

    status, valid_task_ids = pem_conn.execute_scalar(
        sql,
        {'jobid': task_id_list})

    if not status:
        return internal_server_error(errormsg=valid_task_ids)

    if not valid_task_ids:
        return bad_request(gettext('Invalid tasks ids provided.'))

    sql = render_template('tasks/sql/filter_non_sys_tasks.sql')

    status, non_sys_task_ids = pem_conn.execute_scalar(
        sql,
        {'jobid': valid_task_ids})

    if not status:
        return internal_server_error(errormsg=non_sys_task_ids)

    # Nothing to delete.
    if not non_sys_task_ids:
        return bad_request(gettext('System tasks cannot be deleted.'))

    sql = render_template('tasks/sql/delete_tasks.sql')

    status, res = pem_conn.execute_void("BEGIN;")

    if not status:
        return internal_server_error(errormsg=res)

    # Remove the tasks
    status, res = pem_conn.execute_void(sql, {'jobid': non_sys_task_ids})

    if not status:
        pem_conn.execute_void("ROLLBACK;")
        return internal_server_error(errormsg=res)

    # Commit Transaction
    status, res = pem_conn.execute_void("COMMIT;")

    if not status:
        pem_conn.execute_void("ROLLBACK;")
        return internal_server_error(errormsg=res)

    return make_json_response(success=1)


def get_tasks(params, pem_conn):
    sql_data = render_template('tasks/sql/task_list.sql', data=params)
    status, res = pem_conn.execute_dict(sql_data, params)

    if not status:
        return status, res

    sql_count = render_template('tasks/sql/task_list_count.sql', data=params)
    status_count, res_count = pem_conn.execute_dict(sql_count, params)

    if not status_count:
        return status_count, res_count

    total_count = (
        res_count['rows'][0]['total_rows'] if res_count['rows'] else 0
    )
    for row in res['rows']:
        tasks_sql = render_template('tasks/sql/scheduled_step_list.sql')
        status, tasks = pem_conn.execute_dict(
            tasks_sql, {'jid': row['taskid']})
        row['steps'] = tasks['rows'] if status else []

    return True, {'rows': res['rows'], 'total_count': total_count}


@blueprint.route(
    '/jobstep/<int:jslid>/log', methods=["GET"], endpoint='get_step_output'
)
@pem_connection
@pgCSRFProtect.exempt
@login_required
@scheduleTaskRole.check_role(
    gettext("Logged-in user do not have permission to access step logs.")
)
def get_job_step_output(jslid, pem_conn=None):
    """

    :param step_id: Unique job step id
    :param option: Option for operation to perform
    :param pem_conn: Connection objects
    :return: Response based on option selected
    """
    is_download = request.args.get('download', 'false') == 'true'
    SQL = render_template(
        'tasks/sql/fetch_step_output.sql'
    )
    # Execute the query.
    status, output = pem_conn.execute_scalar(
        SQL, {'jslid': jslid}
    )
    if not status:
        # If user is expecting the file then
        if is_download:
            r = Response('{0}'.format(output), mimetype='text/plain')
            r.headers[
                "Content-Disposition"
            ] = "attachment;filename=error.log"
            return r
        else:
            return internal_server_error(errormsg=output)

    # Generator which will read the output line by line from output column
    def read_log():
        if output:
            for line in output.splitlines(True):
                yield line
        else:
            yield gettext("No log content found for the selected job step.")

    # We are using the stream to pass the data in small chunks to avoid memory
    # and network spike at both server and client side
    resp = Response(
        stream_with_context(read_log()),
        mimetype='text/plain'
    )
    # If user requested for download then send it as attachment
    if is_download:
        filename = request.args.get(
            'filename', "job_step_log_{0}.log".format(jslid)
        )
        resp.headers[
            "Content-Disposition"
        ] = "attachment;filename={0}".format(filename)

    return resp
