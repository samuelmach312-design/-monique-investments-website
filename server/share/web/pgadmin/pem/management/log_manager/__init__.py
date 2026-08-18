##########################################################################
#
# Postgres Enterprise Manager
#
# Copyright (C) 2016 - 2025, EnterpriseDB Corporation. All rights reserved.
#
##########################################################################

"""Implements Log Manager"""

from flask import render_template, request
from flask_babel import gettext
from pgadmin.utils.ajax import internal_server_error, bad_request, \
    make_json_response
from pgadmin.utils import PgAdminModule
from flask import url_for, current_app
from flask_security import login_required
from pgadmin.pem.utils import pem_connection, boolean_to_on_off, \
    bool_to_numeric, validate_server_for_wizard_tree_control
import json
import ast
from pgadmin.pem.utils import get_sql_placeholders
from pgadmin.pem.utils.role import PEMRole

MODULE_NAME = 'log_manager'

logManagerRole = PEMRole(
    'pem_comp_log_manager', gettext('Log manager'), gettext('Log manager'),
    gettext(
        'Priviledge to execute the log manager wizard, and create a '
        'recurrent job to import the database logs into the Postgres '
        'Enterprise Manager.'
    )
)


class LogManagerModule(PgAdminModule):
    """
    class LogManagerModule(PgAdminModule):

        It is a wizard which inherits PgAdminModule
        class and define methods to load its own
        javascript file.
    """

    LABEL = gettext('Log Manager')

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
        return [
            'log_manager.server_list',
            'log_manager.server_log_config',
            'log_manager.server_get_details'
        ]


# Create blueprint for Manage Probes class
blueprint = LogManagerModule(
    MODULE_NAME, __name__, static_url_path='', url_prefix="/pem/log_manager")


@blueprint.route("/")
@login_required
def index():
    return bad_request(errormsg=gettext(
        "This URL cannot be called directly!")
    )


@blueprint.route('/server/list', methods=["GET"], endpoint='server_list')
@pem_connection
@login_required
@logManagerRole.check_role(
    gettext("Logged-in user do not have permission to access server list.")
)
def list_server(pem_conn=None):
    """
    This function is used to get the list of
    database server's installed on that agent.

    :param pem_conn: PEM Connection object.
    """

    sql = render_template('log_manager/sql/server_list.sql')

    # Execute the query.
    status, res = pem_conn.execute_dict(sql)

    if not status:
        current_app.logger.error(str(res))
        return internal_server_error(errormsg=res)

    # Create json response for server
    server_nodes = []
    d = {
        'label': gettext('Servers'),
        'inode': True,
        'open': True,
        'branch': [],
        'checkbox': True,
        'checked': True,
    }
    server_nodes.append(d)

    if len(res['rows']) == 0:
        d['inode'] = False
        d['checkbox'] = False
        d['checked'] = False
        d['err_msg'] = gettext(
            "Only servers with remote monitoring false will appear here."
        )
    else:
        for server in res['rows']:
            checkbox, is_info_msg, err_msg = \
                validate_server_for_wizard_tree_control(server)

            k = {
                'id': server['server_id'],
                'label': "{} ({}:{})".format(server['description'],
                                             server['server_name'],
                                             server['port']),
                'inode': False,
                'checkbox': checkbox,
                'checked': checkbox,
                'err_msg': err_msg,
                'is_info_msg': is_info_msg,
                'service_id': server['service_id'],
                'server_version_id': server['server_version_id'],
                'agent_os': server['agent_os']
            }
            d['branch'].append(k)

    return make_json_response(
        data=server_nodes
    )


@blueprint.route('/server/get_details',
                 methods=["GET"], endpoint='server_get_details')
@pem_connection
@login_required
@logManagerRole.check_role(
    gettext("Logged-in user do not have permission to access server details.")
)
def get_details(pem_conn=None):
    """
    This function is used to get the list of
    database server details by server id.

    :param pem_conn: PEM Connection object.
    """

    status, pem_schema_version = pem_conn.execute_scalar(
        'select pem.schema_version();')
    if not status:
        current_app.logger.error(str(pem_schema_version))
        return internal_server_error(gettext(str(pem_schema_version)))
    sql = render_template(
        'log_manager/sql/server_details.sql',
        placeholders=get_sql_placeholders(
            ast.literal_eval(request.args['server_ids'])))

    status, res = pem_conn.execute_dict(
        sql, ast.literal_eval(request.args['server_ids']))

    if not status:
        current_app.logger.error(str(res))
        return internal_server_error(errormsg=res)

    return make_json_response(
        data=res['rows']
    )


@blueprint.route('/server/log_config',
                 methods=["POST"], endpoint='server_log_config')
@pem_connection
@login_required
@logManagerRole.check_role(
    gettext(
        "Logged-in user do not have permission to access server log "
        "configuration."
    )
)
def server_log_config(pem_conn=None):
    if request.data:
        data = json.loads(request.data.decode())
    else:
        data = request.args or request.form

    servers = data['servers']
    restart_servers = servers.get('restart_servers', [])
    configuration = data['configuration']
    location = data['location']
    when = data['when']
    what = data['what']
    schedule = data['schedule']

    status, pem_schema_version = pem_conn.execute_scalar(
        'select pem.schema_version();')
    if not status:
        current_app.logger.error(str(pem_schema_version))
        return internal_server_error(gettext(str(pem_schema_version)))

    # Set 'on' or 'off' for boolean values instead of 0 or 1.
    log_collector = boolean_to_on_off(location['log_collector'])
    log_silent_mode = boolean_to_on_off(location['log_silent_mode'])
    log_rotation_truncate = boolean_to_on_off(
        configuration['log_rotation_truncate'])
    log_parse_tree = boolean_to_on_off(what['log_parse_tree'])
    log_rewriter_output = boolean_to_on_off(what['log_rewriter_output'])
    log_exec_plan = boolean_to_on_off(what['log_exec_plan'])
    log_indent_debug_output = boolean_to_on_off(
        what['log_indent_debug_output'])
    log_checkpoints = boolean_to_on_off(what['log_checkpoints'])
    log_disconnections = boolean_to_on_off(what['log_disconnections'])
    log_duration = boolean_to_on_off(what['log_duration'])
    log_hostname = boolean_to_on_off(what['log_hostname'])
    log_lock_waits = boolean_to_on_off(what['log_lock_waits'])

    log_directory = location['log_directory']
    log_syslog_facility = location['log_syslog_facility']
    log_syslog_ident = location['log_syslog_ident']
    log_rotation_size = str(configuration['log_rotation_size'])
    log_rotation_time = str(configuration['log_rotation_time'])
    log_client_min_messages = when['log_client_min_messages']
    log_min_messages = when['log_min_messages']
    log_min_duration_statement = str(when['log_min_duration_statement'])
    log_min_error_statement = when['log_min_error_statement']
    log_error_verbosity = what['log_error_verbosity']
    log_prefix_string = what['log_prefix_string']
    log_statements = what['log_statements']
    log_autovacuum_min_duration = str(when['log_autovacuum_min_duration'])
    log_temp_files = str(when['log_temp_files'])
    log_import = str(bool_to_numeric(configuration['log_import']))
    log_import_frequency = configuration['log_import_frequency']
    update_log_dir = str(bool_to_numeric(location['update_log_dir']))
    configure_now = schedule['configure_now']

    # Lets validate all the Check constraint related fields
    LOG_LEVELS = [
        'panic', 'fatal', 'error', 'warning', 'notice', 'log',
        'debug1', 'debug2', 'debug3', 'debug4', 'debug5'
    ]

    if log_import_frequency not in [
        '5 Minutes', '30 Minutes', '1 Hour', '4 Hours', '12 Hours', '1 Day'
    ]:
        current_app.logger.error(
            "Error: invalid value for log import frequency")
        return bad_request(
            gettext("Please provide valid value for log import frequency")
        )

    if log_error_verbosity not in [
        'default', 'terse', 'verbose'
    ]:
        current_app.logger.error(
            "Error: invalid value for log error verbosity")
        return bad_request(
            gettext("Please provide valid value for log error verbosity")
        )

    if log_min_error_statement not in LOG_LEVELS:
        current_app.logger.error(
            "Error: invalid value for log min error statement")
        return bad_request(
            gettext("Please provide valid value for log min error statement")
        )

    if log_min_messages not in LOG_LEVELS:
        current_app.logger.error(
            "Error: invalid value for log min messages")
        return bad_request(
            gettext("Please provide valid value for log min messages")
        )

    if log_client_min_messages not in LOG_LEVELS:
        current_app.logger.error(
            "Error: invalid value for log client min messages")
        return bad_request(
            gettext("Please provide valid value for log client min messages")
        )

    if location['log_destination_syslog'] and log_syslog_facility not in [
        'LOCAL0', 'LOCAL1', 'LOCAL2', 'LOCAL3', 'LOCAL4', 'LOCAL5',
        'LOCAL6', 'LOCAL7'
    ]:
        current_app.logger.error(
            "Error: invalid value for log syslog facility")
        return bad_request(
            gettext("Please provide valid value for log syslog facility")
        )

    if log_statements not in [
        'none', 'ddl', 'mod', 'all'
    ]:
        current_app.logger.error(
            "Error: invalid value for log statements")
        return bad_request(
            gettext("Please provide valid value for log statements")
        )

    log_destination = ''
    if location['log_destination_stderr']:
        log_destination = 'stderr'

    if location['log_destination_csvlog']:
        if log_destination != '':
            log_destination += ','
        log_destination += 'csvlog'

    if location['log_destination_syslog']:
        if log_destination != '':
            log_destination += ','
        log_destination += 'syslog'

    if location['log_destination_eventlog']:
        if log_destination != '':
            log_destination += ','
        log_destination += 'eventlog'

    if log_destination == '':
        log_destination = 'stderr'

    for server_id in servers['servers']:

        sql = render_template('log_manager/sql/server_list.sql',
                              server_id=server_id)

        status, res = pem_conn.execute_dict(sql)

        if not status:
            current_app.logger.error(str(res))
            return internal_server_error(gettext(str(res)))

        server_data = res['rows'][0]

        sql = (f"SELECT * FROM pem.log_configuration "
               f"WHERE server_id IN (%s)")
        status, res = pem_conn.execute_dict(sql, [server_id])
        if not status:
            current_app.logger.error(str(res))
            return internal_server_error(gettext(str(res)))

        server_config_data = {}
        if len(res['rows']) > 0:
            server_config_data = res['rows'][0]

        # If user don't changed the log directory and default directory name
        # is 'pg_log' then for database server PG/EPAS 10 and above, default
        # directory is 'log' instead of 'pg_log'.
        server_version = server_data['server_version_id']
        # For PostgreSQL and EPAS versions before 18, use boolean
        if ((server_version < 11800 and server_version >= 11000) or
                (server_version < 21800 and server_version >= 21000)):
            log_connections = boolean_to_on_off(what['log_connections'])
        else:
            log_connections = str(what['log_connections'])

        if not location['update_log_dir'] and log_directory == 'pg_log' \
                and ((11000 <= server_version < 20000) or
                     (server_version >= 21000)):
            log_directory = 'log'

        if location['log_filename'] == "DEFAULT":
            if server_data['server_version_id'] > 20000:
                log_filename = "enterprisedb-%Y-%m-%d_%H%M%S.log"
            else:
                log_filename = "postgresql-%Y-%m-%d_%H%M%S.log"
        else:
            log_filename = location['log_filename']

        # Set the minute & hour array for job frequency
        minute_array = "{t,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f," \
            "f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f," \
            "f,f,f,f}"
        hour_array = "{t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t}"

        if log_import_frequency == "5 Minutes":
            minute_array = "{t,f,f,f,f,t,f,f,f,f,t,f,f,f,f,t,f,f,f,f,t,f,f," \
                "f,f,t,f,f,f,f,t,f,f,f,f,t,f,f,f,f,t,f,f,f,f,t,f,f,f,f,t,f," \
                "f,f,f,t,f,f,f,f}"
            hour_array = "{t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t}"
        if log_import_frequency == "30 Minutes":
            minute_array = "{t,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f," \
                "f,f,f,f,f,f,f,t,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f," \
                "f,f,f,f,f,f,f,f}"
            hour_array = "{t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t}"
        if log_import_frequency == "1 Hour":
            minute_array = "{t,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f," \
                "f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f," \
                "f,f,f,f,f,f,f,f}"
            hour_array = "{t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t}"
        if log_import_frequency == "4 Hours":
            minute_array = "{t,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f," \
                "f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f," \
                "f,f,f,f,f,f,f,f}"
            hour_array = "{t,f,f,f,t,f,f,f,t,f,f,f,t,f,f,f,t,f,f,f,t,f,f,f}"
        if log_import_frequency == "12 Hours":
            minute_array = "{t,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f," \
                "f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f," \
                "f,f,f,f,f,f,f,f}"
            hour_array = "{t,f,f,f,f,f,f,f,f,f,f,f,t,f,f,f,f,f,f,f,f,f,f,f}"
        if log_import_frequency == "1 Day":
            minute_array = "{t,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f," \
                "f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f," \
                "f,f,f,f,f,f,f,f}"
            hour_array = "{t,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f}"

        pem_conn.execute_void("BEGIN;")

        alert_name = 'Log config mismatch'

        params = [alert_name, 200]

        sql = render_template('log_manager/sql/get_alert_template.sql')
        status, template_id = pem_conn.execute_scalar(sql, params)

        if not status:
            pem_conn.execute_void("ROLLBACK;")
            current_app.logger.error(str(template_id))
            return internal_server_error(gettext(str(template_id)))

        if template_id == '' or template_id == 'NULL' or template_id is None:
            current_app.logger.error(
                "Error: unable to process an empty template id")
            internal_server_error(
                gettext("Error: unable to process an empty template id"))

        params = [alert_name, 0, server_id, None, None, None, None, 200]

        sql = render_template('log_manager/sql/alert_exist.sql')
        status, is_alert_exist = pem_conn.execute_scalar(sql, params)

        if not status:
            pem_conn.execute_void("ROLLBACK;")
            current_app.logger.error(str(is_alert_exist))
            return internal_server_error(gettext(str(is_alert_exist)))

        if is_alert_exist == 'f' or is_alert_exist is False:
            params = [alert_name, template_id, 0, server_id, None, None,
                      None, None, '{}', '>', '{0.1, 0.2, 0.3}', 1, 30, True]

            sql = render_template('log_manager/sql/create_alert.sql')
            status, res = pem_conn.execute_void(sql, params)

            if not status:
                pem_conn.execute_void("ROLLBACK;")
                current_app.logger.error(str(res))
                return internal_server_error(gettext(str(res)))

        name = "Server log configuration request"
        description = "Server ID: {}, agent ID: {}".format(
            server_id, server_data['agent_id'])

        if configure_now:
            time = "now()"
        else:
            time = "'" + schedule['time'] + "'"

        # pem_conn.set_db_session_timezone()

        params = [name, description, server_data['agent_id'], time]
        sql = render_template('log_manager/sql/create_job.sql')

        status, jobid = pem_conn.execute_scalar(sql, params)
        if not status:
            pem_conn.execute_void("ROLLBACK;")
            current_app.logger.error(str(jobid))
            return internal_server_error(gettext(str(jobid)))

        if server_data['agent_os'] == 'windows':
            log_syslog_facility_windows = 'none'
        else:
            log_syslog_facility_windows = log_syslog_facility

        name = "Modify postgresql.conf"

        # Get the config directory file path, It requires when database
        # server's data directory and config directory is different.
        status, res = pem_conn.execute_dict(
            "SELECT regexp_replace (st.setting, '[|/][^|/]*$', '') "
            "AS config_file FROM pemdata.settings st WHERE "
            "server_id = %(server_id)s AND name = 'config_file'",
            {'server_id': server_id}
        )

        if not status:
            pem_conn.execute_void('ROLLBACK')
            current_app.logger.error(str(res))
            return internal_server_error(gettext(str(res)))

        # Add configuration directory value
        if len(res['rows']) > 0:
            code = "log_configuration \"" + res['rows'][0]['config_file'] + \
                   "\" " + log_destination + " " + log_collector + " " + \
                   log_silent_mode + " \""
        else:
            code = "log_configuration \"" + server_data['data_directory'] + \
                   "\" " + log_destination + " " + log_collector + " " + \
                   log_silent_mode + " \""

        code += log_directory + "\" \"" + log_filename + "\" " + \
            log_syslog_facility_windows + " " + \
            log_syslog_ident + " " + log_rotation_size
        code += " " + log_rotation_time + " " + log_rotation_truncate + \
            " " + log_client_min_messages + \
                " " + log_min_messages + " "
        code += log_min_error_statement + " " + log_min_duration_statement + \
            " " + log_parse_tree + " " + log_rewriter_output + " "
        code += log_exec_plan + " " + log_indent_debug_output + " " + \
            log_checkpoints + " " + log_connections + \
            " " + log_disconnections + " "
        code += log_duration + " " + log_hostname + " " + log_lock_waits + \
            " " + log_error_verbosity + " \"" + \
            str(log_prefix_string) + "\" "
        code += log_statements + " " + \
            log_autovacuum_min_duration + " " + log_temp_files + \
            " " + update_log_dir + " " + str(server_id)
        code += " " + str(server_data['server_version_id']) + " " + \
            str(log_import) + " " + log_import_frequency

        params = [jobid, name, description, 'i', code, server_id]

        sql = render_template('log_manager/sql/create_jobstep.sql')

        status, res = pem_conn.execute_void(sql, params)
        if not status:
            pem_conn.execute_void("ROLLBACK;")
            current_app.logger.error(str(res))
            return internal_server_error(gettext(str(res)))

        if server_id in restart_servers:
            name = "Server Restart"
            code_type = 'i'
            code = "server_restart " + server_data['service_id']
        else:
            name = "Server Reload"
            code_type = 's'
            code = "SELECT pg_reload_conf();"

        params = [jobid, name, description, code_type, code, server_id]
        sql = render_template('log_manager/sql/create_jobstep.sql')

        status, res = pem_conn.execute_void(sql, params)
        if not status:
            pem_conn.execute_void("ROLLBACK;")
            current_app.logger.error(str(res))
            return internal_server_error(gettext(str(res)))

        name = "PEM Log Manager Log Import - Server " + str(server_id)
        params = [name, server_data['agent_id']]

        sql = render_template('log_manager/sql/get_jobid.sql')
        status, jobid = pem_conn.execute_scalar(sql, params)

        if not status:
            pem_conn.execute_void("ROLLBACK;")
            current_app.logger.error(str(jobid))
            return internal_server_error(gettext(str(jobid)))

        if log_import == '1':
            update_existing_job = 1
            name = "PEM Log Manager Log Import - Server " + str(server_id)
            description = "Server ID: {}, agent ID: {}".format(
                server_id, server_data['agent_id'])

            # Create the Log Import Job for the server
            if jobid == "" or jobid is None:
                if configure_now:
                    time = "now()"
                else:
                    time = "'" + time + "'"

                # pem_conn.set_db_session_timezone()

                # We need to insert the job not update them
                update_existing_job = 0
                params = [name, description, server_data['agent_id'], time]
                sql = render_template('log_manager/sql/create_job.sql')

                stuats, jobid = pem_conn.execute_scalar(sql, params)
                if not status:
                    pem_conn.execute_void("ROLLBACK;")
                    current_app.logger.error(str(jobid))
                    return internal_server_error(gettext(str(jobid)))

            code = "server_log_import \"" + server_data['data_directory'] + \
                "\" " + str(server_id) + " " + \
                str(server_data['server_version_id'])

            if update_existing_job == 0:
                params = [jobid, name, description, 'i', code, server_id]
                sql = render_template('log_manager/sql/create_jobstep.sql')
            else:
                params = [name, description, code, server_id, jobid]
                sql = render_template('log_manager/sql/update_jobstep.sql')
            status, res = pem_conn.execute_void(sql, params)

            if not status:
                pem_conn.execute_void("ROLLBACK;")
                current_app.logger.error(str(res))
                return internal_server_error(gettext(str(res)))

            if update_existing_job == 0:
                params = [jobid, minute_array, hour_array]
                sql = render_template(
                    'log_manager/sql/create_job_schedule.sql')
            else:
                params = [minute_array, hour_array, jobid]
                sql = render_template(
                    'log_manager/sql/update_job_schedule.sql')

            status, res = pem_conn.execute_void(sql, params)
            if not status:
                pem_conn.execute_void("ROLLBACK;")
                current_app.logger.error(str(res))
                return internal_server_error(gettext(str(res)))
        else:
            if jobid is not None or jobid != "":
                # Delete the job.
                params = [jobid]
                sql = render_template('log_manager/sql/delete_job.sql')
                status, res = pem_conn.execute_void(sql, params)
                if not status:
                    pem_conn.execute_void("ROLLBACK;")
                    current_app.logger.error(str(res))
                    return internal_server_error(gettext(str(res)))

        is_update = False
        if 'server_id' in server_config_data:
            is_update = True

        version_string = server_data['server_version_id']
        if server_data['agent_os'] == 'windows' or \
                not ((version_string > 0 and version_string < 10902) or
                     (version_string > 20000 and version_string < 20902)):
            log_silent_mode_server = 'off'
        else:
            log_silent_mode_server = location['log_silent_mode']

        if server_data['agent_os'] == 'windows':
            log_syslog_facility_server = 'none'
            log_syslog_ident_server = 'NA'
        else:
            log_syslog_facility_server = log_syslog_facility
            log_syslog_ident_server = log_syslog_ident

        if not is_update:
            # pem_conn.set_db_session_timezone()

            params = [
                server_id, log_destination, log_collector,
                log_silent_mode_server, log_directory, log_filename,
                log_syslog_facility_server, log_syslog_ident_server,
                log_rotation_size, log_rotation_time, log_rotation_truncate,
                log_client_min_messages, log_min_messages,
                log_min_error_statement, log_min_duration_statement,
                log_parse_tree, log_rewriter_output, log_exec_plan,
                log_indent_debug_output, log_checkpoints, log_connections,
                log_disconnections, log_duration, log_hostname, log_lock_waits,
                log_error_verbosity, log_prefix_string, log_statements,
                log_autovacuum_min_duration, log_temp_files, log_import,
                log_import_frequency, update_log_dir
            ]

            sql = render_template(
                'log_manager/sql/create_log_configuration.sql',
                pem_schema_version=pem_schema_version
            )

        else:
            # pem_conn.set_db_session_timezone()

            params = [
                log_destination, log_collector, log_silent_mode_server,
                log_directory, log_filename, log_syslog_facility_server,
                log_syslog_ident_server, log_rotation_size, log_rotation_time,
                log_rotation_truncate, log_client_min_messages,
                log_min_messages, log_min_error_statement,
                log_min_duration_statement, log_parse_tree,
                log_rewriter_output, log_exec_plan, log_indent_debug_output,
                log_checkpoints, log_connections, log_disconnections,
                log_duration, log_hostname, log_lock_waits,
                log_error_verbosity, log_prefix_string, log_statements,
                log_autovacuum_min_duration, log_temp_files, log_import,
                log_import_frequency, update_log_dir, server_id
            ]

            sql = render_template(
                'log_manager/sql/update_log_configuration.sql',
                pem_schema_version=pem_schema_version
            )

        status, res = pem_conn.execute_void(sql, params)
        if not status:
            pem_conn.execute_void("ROLLBACK;")
            current_app.logger.error(str(res))
            return internal_server_error(gettext(str(res)))

        pem_conn.execute_void("COMMIT;")

    return make_json_response(success=1)
