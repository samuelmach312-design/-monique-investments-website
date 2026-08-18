##########################################################################
#
# Postgres Enterprise Manager
#
# Copyright (C) 2016 - 2025, EnterpriseDB Corporation. All rights reserved.
#
##########################################################################

"""Implements Tuning Wizard"""

import json
import time
import os
from io import open
from flask import render_template, request, current_app
from flask_babel import gettext
from pgadmin.utils.ajax import internal_server_error, bad_request,\
    make_json_response, success_return, precondition_required,\
    make_response
from pgadmin.utils.csrf import pgCSRFProtect
from pgadmin.utils import PgAdminModule
from flask import Response, url_for
from flask_security import login_required
from pgadmin.pem.utils import pem_connection, \
    get_default_stylesheets, validate_server_for_wizard_tree_control
from pgadmin.pem.monitor.dashboard.utils import DashboardTransaction, \
    cancel_dashboard
from pgadmin.pem.utils.role import PEMRole
from .utils import process_req, process_req_data, check_params, \
    process_node_data, get_sch_time, get_filename_download_status, \
    filename_exists, get_value_str, process_scheduler, process_filename, \
    process_server_data, get_total_servers, embed_files

MODULE_NAME = 'tuning_wizard'
GET_SETTINGS_SQL = 'tuning_wizard/sql/get_settings.sql'

tuningWizardRole = PEMRole(
    'pem_comp_tuning_wizard', gettext('Tuning wizard'),
    gettext('Tuning wizard'),
    gettext(
        'Priviledge to execute the wizard for tuning the database '
        'configuration parameters.'
    )
)


class TuningWizardModule(PgAdminModule):
    """
    class TuningWizardModule(Object):

        It is a wizard which inherits PgAdminModule
        class and define methods to load its own
        javascript file.
    """

    LABEL = gettext('Tuning Wizard')

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
            'tuning_wizard.server_list', 'tuning_wizard.tuning_server_config',
            'tuning_wizard.schedule', 'tuning_wizard.generate',
            'tuning_wizard.close'
        ]


# Create blueprint for Tuning Wizard class
blueprint = TuningWizardModule(
    MODULE_NAME, __name__, static_url_path='', url_prefix="/pem/tuning_wizard")


@blueprint.route("/")
@login_required
def index():
    return bad_request(errormsg=gettext(
        "This URL cannot be called directly!")
    )


@blueprint.route('/server_list', methods=["GET"], endpoint='server_list')
@login_required
@tuningWizardRole.check_role(
    gettext("Logged-in user do not have permission to access server list.")
)
@pem_connection
def server_list(pem_conn=None):
    """
    This function will return the servers list.
    """
    sql = render_template(
        'tuning_wizard/sql/list_servers.sql'
    )

    status, res = pem_conn.execute_dict(sql)

    if not status:
        return internal_server_error(errormsg=res)

    data = []
    node_data = {
        'label': 'Servers',
        'inode': True,
        'open': True,
        'branch': [],
        'checked': True,
    }
    data.append(node_data)

    if len(res['rows']) == 0:
        node_data['inode'] = False
        node_data['checkbox'] = False
        node_data['checked'] = False

    for server in res['rows']:
        checkbox, is_info_msg, err_msg = \
            validate_server_for_wizard_tree_control(server)

        branch_data = {
            'server_id': server['server_id'],
            'label': gettext("{} ({}:{})".format(server['description'],
                                                 server['server_name'],
                                                 server['port'])),
            'description': server['description'],
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
                'server_version_id': server['server_version_id']
            }
        }
        node_data['branch'].append(branch_data)

    return make_json_response(
        data=data
    )


@blueprint.route(
    '/tuning_server_config', methods=["GET"], endpoint='tuning_server_config'
)
@login_required
@tuningWizardRole.check_role(
    gettext("Logged-in user do not have permission to access server "
            "tuning configuration.")
)
@pem_connection
def tuning_server_config(pem_conn=None):
    """
    Returns the tuning parameters for the selected Postgres server.
    Parameters:
        servers : Selected servers.
        workload_profile: Index of selected workload profile
        server_util: Index of selected server utilization.
    """

    req = process_req(request)

    sql = ""
    params = {}
    server_util = req['server_util']
    workload_profile = req['workload_profile']
    servers = req['servers'].split(",")

    params.update({'util': server_util})
    params.update({'workload': workload_profile})

    for x in range(0, len(servers)):
        params.update({'server_id_' + str(x): servers[x]})
        sql += render_template('tuning_wizard/sql/config_tuning_server.sql',
                               cnt=x)

        if x != (len(servers) - 1):
            sql += " UNION ALL "

    status, res = pem_conn.execute_dict(sql, params)
    if not status:
        return internal_server_error(errormsg=res)

    sql = render_template(
        'tuning_wizard/sql/list_servers.sql'
    )
    status, servers = pem_conn.execute_dict(sql)
    if not status:
        return internal_server_error(errormsg=servers)

    servers = servers['rows']
    server_details = {}

    for s in servers:
        server_details[s['server_id']] = s

    data = []
    server_checkbox = False
    node_data = {
        'label': 'Servers',
        'inode': True,
        'open': True,
        'branch': [],
        'checked': server_checkbox,
        'checkbox': server_checkbox
    }
    data.append(node_data)

    if len(res['rows']) == 0:
        node_data['inode'] = False
        node_data['checkbox'] = False
        node_data['checked'] = False

    req_status = process_node_data(res, server_details, node_data,
                                   server_checkbox)
    if req_status == 400:
        return bad_request(errormsg=gettext("Bad Request."))

    return make_json_response(
        data=data
    )


@blueprint.route('/schedule', methods=["POST"], endpoint='schedule')
@login_required
@tuningWizardRole.check_role(
    gettext("Logged-in user do not have permission to apply server "
            "tuning configurations.")
)
@pem_connection
def schedule(trans_id=0, pem_conn=None):
    """Schedule server's tuning configuration job settings.
        Parameters:
            servers          - The list of servers with its details to be tuned
            tuning_changes   - Tuning Changes details
            schedule         - Time for job schedule
            tuning_config    - Tuning config details
    """

    req = process_req(request)

    req_params = ['schedule', 'servers', 'tuning_changes', 'tuning_config']

    status, response = check_params(req, req_params)
    if status == 400:
        return make_response(
            status=400,
            response=response
        )

    if req['schedule']['schedule_or_generate'] == 'schedule':
        sch_time = get_sch_time(req)
    else:
        return precondition_required("Schedule time is missing.")

    job_id = 0
    for s in req['servers']:
        pem_conn.execute_void("BEGIN;")
        if 'server_id' in s:
            status, response, j_id = process_scheduler(s, pem_conn,
                                                       sch_time, req)
            if status == 500:
                return internal_server_error(errormsg=response)
            else:
                job_id = j_id

    return success_return({"job_id": job_id})


@blueprint.route(
    '/generate/<int:trans_id>', methods=["GET", "POST"], endpoint='generate'
)
@pgCSRFProtect.exempt
@login_required
@tuningWizardRole.check_role(
    gettext("Logged-in user do not have permission to generate "
            "tuning configuration report.")
)
@pem_connection
def generate_report(trans_id, pem_conn=None):
    """
    Generates a Tuning Wizard's recommendation report from
    Parameters:
        schedule        - Report schedule
        tuning_changes  - Tuning changes
        servers         - Selected servers
        tuning_config   - workload & utilization option
    """
    try:

        req = process_req_data(request)

        req_params = ['schedule', 'servers', 'tuning_changes', 'tuning_config']

        status, response = check_params(req, req_params)
        if status == 400:
            return make_response(
                status=400,
                response=response
            )

        servers = {}
        filename, is_download = get_filename_download_status(req)

        if not filename_exists(filename, is_download):
            return make_response(
                status=400,
                response=gettext(
                    "Could not find the required parameter file_name."
                )
            )

        filename = process_filename(filename, is_download)

        dashboard_transaction = DashboardTransaction(
            trans_id, pem_conn.conn_id, -1, 0
        )

        # We will try to encode report file name with latin-1
        # If it fails then we will fallback to default ascii file name
        # werkzeug only supports latin-1 encoding supported values
        try:
            tmp_file_name = filename
            tmp_file_name.encode('latin-1', 'strict')
        except UnicodeEncodeError:
            filename = "tuning_wizard_report.html"

        for s in req['servers']:
            process_server_data(s, servers)

        for t in req['tuning_changes']:
            if 'tuning_param_info' in t:
                data = t['tuning_param_info'].split(',')
                value_str = ''

                if data[0] in [
                    'work_mem', 'maintenance_work_mem', 'shared_buffers',
                    'wal_buffers', 'effective_cache_size'
                ]:
                    sql = render_template(GET_SETTINGS_SQL,
                                          flag=1)

                    params = [t['server_id'], data[0]]
                    with dashboard_transaction:
                        status, values = pem_conn.execute_2darray(sql, params)

                    value = int(
                        values['rows'][0][0]) * int(values['rows'][0][1])

                    # Get size in KB or MBs with manipulations
                    value_str = get_value_str(value, 'kB', 'MB')

                elif data[0] in ['random_page_cost', 'checkpoint_segments']:
                    sql = render_template(GET_SETTINGS_SQL,
                                          flag=2)
                    params = [t['server_id'], data[0]]

                    with dashboard_transaction:
                        status, value_str = \
                            pem_conn.execute_scalar(sql, params)

                elif data[0] in ['max_wal_size', 'min_wal_size']:
                    sql = render_template(GET_SETTINGS_SQL,
                                          flag=2)
                    params = [t['server_id'], data[0]]

                    with dashboard_transaction:
                        status, values = pem_conn.execute_scalar(sql, params)

                    value = int(values)
                    value_str = get_value_str(value, 'MB', 'GB')

                t['param'] = data[0]
                t['orig_value'] = value_str
                t['rec_value'] = data[1]
                servers[t['server_id']]['has_changed'] = True

        total_servers = get_total_servers(req)

        usage = {"UTILISATION_DEDICATED": "Dedicated",
                 "UTILISATION_MIXED": "Mixed use",
                 "UTILISATION_DEVELOPER": "Developer workstation"}
        workload = {"WORKLOAD_OLTP": "OLTP",
                    "WORKLOAD_MIXED": "Mixed",
                    "WORKLOAD_DW": "Data warehouse"}

        req['tuning_config']['usage'] = usage[req['tuning_config']['usage']]
        req['tuning_config']['workload'] = workload[
            req['tuning_config']['workload']]

        # Embed files
        css_files = []
        css_paths = get_default_stylesheets()
        embed_files(css_paths, css_files)

        js_files = []
        js_paths = [os.path.realpath('{}{}'.format(os.path.dirname(
            os.path.realpath(__file__)),
            '/../../static/js/generated/reports/tuning_wizard.js'))]

        embed_files(js_paths, js_files)

        # Call this function to load the html template for report with all
        # required data

        result = render_template(
            'tuning_wizard/html/report.html',
            servers=servers,
            tuning_changes=req['tuning_changes'],
            tuning_config=req['tuning_config'],
            report_time=time.strftime("%Y-%m-%d %H:%M:%S"),
            css_files=css_files,
            js_files=js_files,
            total_servers=total_servers,
        )
        if is_download:
            res = Response(result, mimetype='text/html')
            res.headers["Content-Disposition"] = \
                "attachment;filename={0}".format(
                filename)
        else:
            res = Response(result)
        return res
    except Exception as e:
        current_app.logger.exception("generate report")

        res = Response("{}".format(str(e)), status=500)

        res.headers["Content-Disposition"] = "attachment;filename={0}".format(
            filename)

        return res


@blueprint.route(
    '/close/<int:trans_id>',
    methods=['get'], endpoint='close'
)
@login_required
@tuningWizardRole.check_role(
    gettext("Logged-in user do not have permission to cancel report "
            "generation of tuning parameters.")
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
