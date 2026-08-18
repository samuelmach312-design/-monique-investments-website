##########################################################################
#
# Postgres Enterprise Manager
#
# Copyright (C) 2016 - 2025, EnterpriseDB Corporation. All rights reserved.
#
##########################################################################

"""Implements Audit Manager"""

import ast
import config
import json
from dateutil.parser import parse
from flask import render_template, request
from flask_babel import gettext
from pgadmin.utils.ajax import bad_request, make_json_response
from pgadmin.utils import PgAdminModule
from pgadmin.utils.ajax import make_response as ajax_response, \
    internal_server_error
from flask import url_for
from flask_security import login_required
from pgadmin.pem.utils import pem_connection, \
    validate_server_for_wizard_tree_control
from pgadmin.pem.utils.role import PEMRole

MODULE_NAME = 'audit_manager'

auditLogManagerRole = PEMRole(
    'pem_comp_audit_manager', gettext('Audit log manager'),
    gettext('Audit log manager'),
    gettext(
        'Priviledge to execute the audit log manager wizard, and create a '
        'recurrent job to import the database audit logs into the Postgres '
        'Enterprise Manager.'
    )
)


class AuditManagerModule(PgAdminModule):
    """
    class AuditManagerModule(Object):

        It is a wizard which inherits PgAdminModule
        class and define methods to load its own
        javascript file.
    """

    LABEL = gettext('Audit Manager')

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
            'audit_manager.server_list', 'audit_manager.server_get_config',
            'audit_manager.schedule'
        ]


# Create blueprint for Manage Probes class
blueprint = AuditManagerModule(
    MODULE_NAME, __name__, static_url_path='', url_prefix="/pem/audit_manager")


@blueprint.route("/")
@login_required
def index():
    return bad_request(errormsg=gettext(
        "This URL cannot be called directly!")
    )


@blueprint.route('/server/list', methods=["GET"], endpoint='server_list')
@login_required
@auditLogManagerRole.check_role(
    gettext("Logged-in user do not have permission to access server list.")
)
@pem_connection
def servers(pem_conn=None):
    """
    This function will return the servers list
    """
    sql = render_template(
        'audit_manager/sql/list_servers.sql'
    )

    status, res = pem_conn.execute_dict(sql)

    if not status:
        return internal_server_error(errormsg=res)

    data = []
    d = {
        'label': 'Servers',
        'inode': True,
        'open': True,
        'branch': [],
        'checked': True,
    }
    data.append(d)

    if len(res['rows']) == 0:
        d['inode'] = False
        d['checkbox'] = False
        d['checked'] = False
        d['err_msg'] = gettext(
            "Only {0} Advanced Servers with remote monitoring false will "
            " appear here."
        ).format(config.SHORT_COMPANY_NAME.upper())
    else:
        for server in res['rows']:
            checkbox, is_info_msg, err_msg = \
                validate_server_for_wizard_tree_control(server)

            k = {
                'server_id': server['server_id'],
                'label': "{} ({}:{})".format(
                    server['description'], server['server_name'],
                    server['port']
                ),
                'inode': False,
                'branch': [],
                'checkbox': checkbox,
                'checked': checkbox,
                'err_msg': err_msg,
                'is_info_msg': is_info_msg,
                'server_info': {
                    'server_id': server['server_id'],
                    'agent_id': server['agent_id'],
                    'data_directory': server['data_directory'],
                    'service_id': server['service_id'],
                    'server_version_id': server['server_version_id'],
                    'agent_os': server['agent_os']
                }
            }
            d['branch'].append(k)

    return make_json_response(
        data=data
    )


@blueprint.route('/server/get_config',
                 methods=["POST"], endpoint='server_get_config')
@login_required
@auditLogManagerRole.check_role(
    gettext(
        "Logged-in user do not have permission to access server "
        "audit configuration."
    )
)
@pem_connection
def get_audit_config(pem_conn=None):
    """
    Returns the audit configuration settings of selected PPAS server
    """
    if request.data:
        servers = json.loads(request.data.decode()).get('server_ids', [])
    else:
        servers = request.args or request.form
        servers = ast.literal_eval(servers['server_ids'])

    sql = render_template('audit_manager/sql/get_audit_config.sql',
                          server_id=servers)
    status, res = pem_conn.execute_dict(sql, servers)
    if not status:
        return internal_server_error(errormsg=res)

    data_rows = res['rows']
    audit_server_data = []
    for row in data_rows:
        modularize_data = dict()
        modularize_data['server_id'] = row['server_id']
        modularize_data['params_config'] = {
            'edb_audit': True if row['edb_audit'] != "none" else False,
            'log_collection': row['log_collection'],
            'log_collection_frequency': row['log_collection_frequency'],
            'log_format': 'xml' if (row['log_format'] == 'xml' or
                                    row['log_format'] == "none") else 'csv',
            'edb_audit_filename': row['edb_audit_filename'],
            'edb_audit_directory': row['edb_audit_directory'],
            'edb_audit_destination': row['edb_audit_destination']
        }

        modularize_data['log_config'] = {
            'edb_audit_connect': row['edb_audit_connect'],
            'edb_audit_disconnect': row['edb_audit_disconnect'],
            'edb_audit_statements': row['edb_audit_statements'],
            'edb_audit_tag': row['edb_audit_tag'],
            'edb_audit_rotation_day': row['edb_audit_rotation_day'],
            'edb_audit_rotation_size': row['edb_audit_rotation_size'],
            'edb_audit_rotation_sec': row['edb_audit_rotation_sec']
        }
        audit_server_data.append(modularize_data)

    return ajax_response(
        response=audit_server_data,
        status=200
    )


@blueprint.route('/schedule', methods=["POST", "PUT"], endpoint='schedule')
@login_required
@auditLogManagerRole.check_role(
    gettext(
        "Logged-in user do not have permission to apply audit configuration "
        "parameters."
    )
)
@pem_connection
def server_audit_config(pem_conn=None):
    """
    Schedule server's audit configuration settings changes,
    creation of audit config mismatch alert and (if enabled) creation
    of audit log collection job.
      Parameters:
          audit_status        - The audit configuration status, 'none', 'xml'
                                or 'csv'.
          audit_directory     - The directory name inside PGDATA which contains
                                the audit logs.
          audit_destination   - The audit destination values could be 'file' or
                                'syslog'.
          audit_filename      - The filename (can be a regex) which determines
                                the audit log filenames.
          audit_tag		        - The Audit log session tracking tag.
          audit_rotation_day  - The day when the audit log files should be
                                rotated. (every, mon, tue, wed, thu, fri, sat,
                                sun, none)
          audit_rotation_size - Size in MB after which the audit log files
                                should be rotated.
          audit_rotation_sec  - Time in Seconds after which the audit log files
                                should be rotated.
          audit_connect       - Whether to log connection attempts (all,
                                failed, none).
          audit_disconect     - Whether to log dis-connection attempts (all,
                                none).
          audit_statements    - What type of SQL Statements to log (ddl, dml,
                                error, select, all, none).
          agent_id            - The agent ID to execute the request
          server_id           - The ID of the server whose configuration needs
                                to be changed.
          service_id          - The alpha-numeric service ID of the server,
                                identified by server_id,  to stop/start
          data_directory      - The data directory of the server, identified by
                                server_id.
          server_version_id   - The exact server version id of the server,
                                identified by server_id. (e.g. 20900)
          update_config       - Flag to determine whether there is a
                                change/update in the audit configuration.
          time                - The time the startup/shutdown should be
                                scheduled for. If not set, now() is used.
    """

    if request.data:
        data = json.loads(request.data.decode())
    else:
        data = request.args or request.form

    params_config = data['params_config']
    log_config = data['log_config']
    config_servers = data['servers']
    schedule = data['schedule']

    # Audit params config data
    audit_status = params_config.get('log_format')
    audit_directory = params_config.get('edb_audit_directory')
    audit_filename = params_config.get('edb_audit_filename')
    enable_log_collection = int(params_config.get('log_collection'))
    log_collection_frequency = params_config.get('log_collection_frequency')
    update_audit_dir = int(params_config.get('change_log_directory', 0))
    audit_destination = params_config.get('edb_audit_destination')

    # Audit log config data
    audit_tag = log_config.get('edb_audit_tag', "")
    audit_connect = log_config.get('edb_audit_connect')
    audit_disconnect = log_config.get('edb_audit_disconnect')
    audit_statements = log_config.get('edb_audit_statements')
    audit_rotation_day = log_config.get('edb_audit_rotation_day')
    audit_rotation_size = int(log_config.get('edb_audit_rotation_size'))
    audit_rotation_sec = int(log_config.get('edb_audit_rotation_sec'))
    audit_statements = ', '.join(audit_statements) \
        if isinstance(audit_statements, list) else audit_statements
    audit_statements = audit_statements if audit_statements != '' else 'none'

    # If audit_status is other than none, xml and csv, it is bad request.
    if not audit_status \
            or audit_status not in ['xml', 'csv', 'none']:
        return bad_request(errormsg=gettext('Invalid log format.'))

    # Audit Schedule settings
    configure_now = schedule.get('configure_now')

    # validate schedule datetime if schedule now is set to false
    if not configure_now:
        configure_date_time = schedule.get('configure_date_time')
        if configure_date_time is None or \
                configure_date_time.replace(' ', '') == '':
            return bad_request(
                errormsg=gettext('Please provide a valid value for the '
                                 'scheduled date time.')
            )
        try:
            parse(configure_date_time, yearfirst=True)
        except Exception as e:
            return bad_request(
                errormsg=gettext('Invalid scheduled date time.')
            )

    status, pem_schema_version = pem_conn.execute_scalar(
        'select pem.schema_version();'
    )

    if not status:
        return internal_server_error(errormsg=str(pem_schema_version))

    for server in config_servers:
        # Get server details.
        server_info = server['server_info']
        server_id = int(server_info.get('server_id'))
        agent_id = int(server_info.get('agent_id'))
        data_directory = server_info.get('data_directory')
        service_id = server_info.get('service_id')
        server_version_id = int(server_info.get('server_version_id'))
        update_config = False
        if 'update_config' in server:
            update_config = True

        temp_audit_tag = audit_tag if server_version_id >= 20905 else ''

        # Audit Destination parameter is for server version greater than or
        # equal to 21000 (EPAS 10 and above)
        temp_audit_destination = ''
        # In case of windows server value of audit destination parameter is
        # file
        if server_version_id >= 21000 and server_info['agent_os'] == 'windows':
            temp_audit_destination = 'file'
        elif (
            server_version_id >= 21000 and server_info['agent_os'] != 'windows'
        ):
            temp_audit_destination = \
                audit_destination if audit_destination != '' else 'file'

        # Set the minute & hour array for job frequency
        minute_array = "{t,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f" \
                       ",f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f" \
                       ",f,f,f,f,f,f,f,f}"
        hour_array = "{t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t}"

        if log_collection_frequency == "5 Minutes":
            minute_array = "{t,f,f,f,f,t,f,f,f,f,t,f,f,f,f,t,f,f,f,f,t,f,f,f" \
                           ",f,t,f,f,f,f,t,f,f,f,f,t,f,f,f,f,t,f,f,f,f,t,f,f" \
                           ",f,f,t,f,f,f,f,t,f,f,f,f}"
            hour_array = "{t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t}"
        if log_collection_frequency == "30 Minutes":
            minute_array = "{t,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f" \
                           ",f,f,f,f,f,f,t,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f" \
                           ",f,f,f,f,f,f,f,f,f,f,f,f}"
            hour_array = "{t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t}"
        if log_collection_frequency == "1 Hour":
            minute_array = "{t,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f" \
                           ",f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f" \
                           ",f,f,f,f,f,f,f,f,f,f,f,f}"
            hour_array = "{t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t}"
        if log_collection_frequency == "4 Hours":
            minute_array = "{t,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f" \
                           ",f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f" \
                           ",f,f,f,f,f,f,f,f,f,f,f,f}"
            hour_array = "{t,f,f,f,t,f,f,f,t,f,f,f,t,f,f,f,t,f,f,f,t,f,f,f}"
        if log_collection_frequency == "12 Hours":
            minute_array = "{t,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f" \
                           ",f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f" \
                           ",f,f,f,f,f,f,f,f,f,f,f,f}"
            hour_array = "{t,f,f,f,f,f,f,f,f,f,f,f,t,f,f,f,f,f,f,f,f,f,f,f}"
        if log_collection_frequency == "1 Day":
            minute_array = "{t,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f" \
                           ",f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f" \
                           ",f,f,f,f,f,f,f,f,f,f,f,f}"
            hour_array = "{t,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f}"

        # Get ready to rock
        pem_conn.execute_void("BEGIN;")

        # Create Audit config mismatch alert
        alert_name = 'Audit config mismatch'
        params = [alert_name, 200]

        sql = render_template('audit_manager/sql/get_template.sql')
        status, template_id = pem_conn.execute_scalar(sql, params)

        if not status:
            return internal_server_error(errormsg=str(template_id))

        if template_id == '' or template_id == 'NULL' or template_id is None:
            return internal_server_error(
                errormsg=gettext(
                    "Error: unable to process an empty template id"
                )
            )

        params = [alert_name, 0, server_id, None, None, None, None, 200]

        sql = render_template('audit_manager/sql/is_alert_exist.sql')
        status, is_alert_exist = pem_conn.execute_scalar(sql, params)

        if not status:
            return internal_server_error(errormsg=str(is_alert_exist))

        if is_alert_exist == 'f' or is_alert_exist is False:
            params = [alert_name, template_id, 0, server_id, None, None,
                      None, None, '{}', '>', '{0.1, 0.2, 0.3}', 1, 30, True]
            # {} - Parameters to substitute in the sql query of the
            #      alert_template; see alert_template.param_* columns.
            # > - Operator to use to compare query result with threshold
            #     values. Currently we support < and >.
            # We may support <= and >= in future.
            # {0.1, 0.2, 0.3} - A 3-element array representing low, medium and
            #                   high thresholds.
            sql = render_template('audit_manager/sql/create_alert.sql')
            status = pem_conn.execute_scalar(sql, params)

            if not status:
                pem_conn.execute_void('ROLLBACK')
                return internal_server_error(
                    errormsg=gettext("Error creating alert")
                )

        if update_config:
            # Create the activation job - change audit configuration.
            name = "Server audit configuration request"
            description = "Server ID: " + \
                str(server_id) + ", agent ID: " + str(agent_id)

            if configure_now:
                time = "now()"
            else:
                time = "'" + schedule.get('configure_date_time') + "'"

            # pem.set_db_session_timezone()

            params = [name, description, agent_id, time]

            sql = render_template('audit_manager/sql/create_job.sql')
            status, jobid = pem_conn.execute_scalar(sql, params)

            if not status:
                pem_conn.execute_void('ROLLBACK')
                return internal_server_error(errormsg=str(jobid))

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
                return internal_server_error(
                    errormsg=gettext("Error while fetching postgresql "
                                     "configuration directory.")
                )

            # Add configuration directory value.
            if len(res['rows']) > 0:
                code = "audit_configuration \"" + \
                       res['rows'][0]['config_file'] + "\" "
            else:
                code = "audit_configuration \"" + data_directory + "\" "

            code += audit_status + " \"" + audit_directory + "\" \"" + \
                audit_filename + "\" " + audit_rotation_day + " " + \
                str(audit_rotation_size) + " " + \
                str(audit_rotation_sec) + " " + audit_connect + " " + \
                audit_disconnect + " \"" + str(audit_statements) + "\" " + \
                str(update_audit_dir)

            # Add value of edb_audit_tag.
            if server_version_id >= 20905:
                code += " \"" + temp_audit_tag + "\""

            # Add value of edb_audit_destination.
            if server_version_id >= 21000:
                code += " \"" + temp_audit_destination + "\""

            params = [jobid, name, description, 'i', code, server_id]

            sql = render_template('audit_manager/sql/create_jobstep.sql')
            status = pem_conn.execute_void(sql, params)

            if not status:
                pem_conn.execute_void('ROLLBACK')
                return internal_server_error(
                    errormsg=gettext(
                        "Error while inserting into jobstep table.")
                )

            name = "Server Reload"
            code = "select pg_reload_conf();"

            params = [jobid, name, description, 's', code, server_id]
            sql = render_template('audit_manager/sql/create_jobstep.sql')
            status = pem_conn.execute_void(sql, params)

            if not status:
                pem_conn.execute_void('ROLLBACK')
                return internal_server_error(
                    errormsg=gettext(
                        "Error while inserting into jobstep table.")
                )

        name = "Audit Log Collection - Server " + str(server_id)
        params = [name, agent_id]

        sql = render_template('audit_manager/sql/get_job_id.sql')
        status, jobid = pem_conn.execute_scalar(sql, params)

        if not status:
            return internal_server_error(errormsg=str(jobid))

        if enable_log_collection == 1:
            update_existing_job = 1
            name = "Audit Log Collection - Server " + str(server_id)
            description = "Server ID: " + \
                str(server_id) + ", agent ID: " + str(agent_id)
            if jobid == "" or jobid is None:
                update_existing_job = 0

                if configure_now:
                    time = "now()"
                else:
                    time = "'" + schedule.get('configure_date_time') + "'"

                # pem.set_db_session_timezone()
                params = [name, description, agent_id, time]

                sql = render_template('audit_manager/sql/create_job.sql')
                status, jobid = pem_conn.execute_scalar(sql, params)

                if not status:
                    pem_conn.execute_void('ROLLBACK')
                    return internal_server_error(errormsg=str(jobid))

            code = "audit_log_collection \"" + data_directory + \
                "\" " + str(server_id) + " " + str(server_version_id)
            if update_existing_job == 0:
                params = [jobid, name, description, 'i', code, server_id]
                sql = render_template('audit_manager/sql/create_jobstep.sql')
            else:
                params = [name, description, code, 'i', server_id, jobid]
                sql = render_template('audit_manager/sql/update_jobstep.sql')
            status = pem_conn.execute_void(sql, params)

            if not status:
                pem_conn.execute_void('ROLLBACK')
                return internal_server_error(
                    errormsg=gettext('Error executing query')
                )

            if update_existing_job == 0:
                params = [jobid, minute_array, hour_array]
                sql = render_template('audit_manager/sql/create_schedule.sql')
            else:
                params = [minute_array, hour_array, jobid]
                sql = render_template('audit_manager/sql/update_schedule.sql')
            status = pem_conn.execute_void(sql, params)

            if not status:
                pem_conn.execute_void('ROLLBACK')
                return internal_server_error(
                    errormsg=gettext('Error executing query.')
                )
        else:
            if jobid != "":
                # Delete the job.
                params = [jobid]
                sql = render_template('audit_manager/sql/delete_job.sql')
                status = pem_conn.execute_void(sql, params)

                if not status:
                    return internal_server_error(
                        errormsg=gettext('Error deleting job.')
                    )

        params = [server_id]
        sql = "SELECT 1 FROM pem.audit_configuration WHERE server_id = " \
              "(%s)::int;"

        status, is_update = pem_conn.execute_scalar(sql, params)
        if enable_log_collection == 1:
            log_collection = "t"
        else:
            log_collection = "f"

        if not is_update:
            params = [server_id, audit_status, audit_directory, audit_filename,
                      audit_rotation_day, audit_rotation_size,
                      audit_rotation_sec, audit_connect,
                      audit_disconnect, audit_statements,
                      log_collection, log_collection_frequency, temp_audit_tag,
                      temp_audit_destination]
            sql = render_template('audit_manager/sql/create_audit.sql')
        else:
            params = [audit_status, audit_directory, audit_filename,
                      audit_rotation_day, audit_rotation_size,
                      audit_rotation_sec, audit_connect, audit_disconnect,
                      audit_statements, log_collection,
                      log_collection_frequency, temp_audit_tag,
                      temp_audit_destination, server_id]
            sql = render_template('audit_manager/sql/update_audit.sql')

        status = pem_conn.execute_void(sql, params)

        if not status:
            pem_conn.execute_void('ROLLBACK')
            return internal_server_error(
                errormsg=gettext('Error inserting into audit table.')
            )

        pem_conn.execute_void("COMMIT;")

    return make_json_response(data={'status': 1})
