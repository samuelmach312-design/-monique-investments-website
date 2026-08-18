##########################################################################
#
# Postgres Enterprise Manager
#
# Copyright (C) 2016 - 2025, EnterpriseDB Corporation. All rights reserved.
#
##########################################################################

"""tuning wizard utility functions"""

import json
from io import open
from flask import render_template
from flask_babel import gettext
from functools import reduce

restart_required_params = ['shared_buffers', 'wal_buffers']


def process_req(request):
    """function used to process request"""
    if request.data:
        req = json.loads(request.data.decode())
    else:
        req = request.args or request.form
    return req


def process_req_data(request):
    """function used to process request data"""
    if request.data:
        req = json.loads(request.data.decode())
    else:
        req = json.loads(request.args['data']) if 'data' in \
                                                  request.args else {}
    return req


def check_params(req, req_params):
    """function used to check required params"""
    for param in req_params:
        if param not in req or len(req[param]) == 0:
            return 400, gettext("Could not find the required parameter (%s)."
                                % param)
    return 200, 'Ok'


def set_checkboxes(server_tuned_param, server_checkbox, branch_data,
                   node_data):
    """function used to set checkboxes as per server_tuned_param"""
    if server_tuned_param:
        branch_data['checkbox'] = True
        branch_data['checked'] = True
        server_checkbox = True
    if server_checkbox:
        node_data['checked'] = server_checkbox
        node_data['checkbox'] = server_checkbox


def process_node_data(res, server_details, node_data, server_checkbox):
    """function used to process node data for tuning_server_config"""
    server_id = 0
    server_tuned_param = False
    cnt = 0
    branch_data = dict()

    for server in res['rows']:
        checkbox = True
        err_msg = None
        if server['tuned_value'] is None or server['orig_value'] is None:
            return 400
        if server_id != server['tuned_server_id']:
            if server_tuned_param:
                branch_data['checkbox'] = True
                branch_data['checked'] = True
                server_checkbox = True
            branch_data = {
                'server_id': server['tuned_server_id'],
                'label': gettext("{} ({}:{})".format(
                    server_details[server['tuned_server_id']]['description'],
                    server_details[server['tuned_server_id']]['server_name'],
                    server_details[server['tuned_server_id']]['port'])),
                'description': server_details[
                    server['tuned_server_id']]['description'],
                'inode': True,
                'open': True,
                'branch': [],
                'checkbox': False,
                'checked': False,
                'server_info': {
                    'server_id': server_details[
                        server['tuned_server_id']]['server_id'],
                    'agent_id': server_details[
                        server['tuned_server_id']]['agent_id'],
                    'data_directory': server_details[
                        server['tuned_server_id']]['data_directory'],
                    'service_id': server_details[
                        server['tuned_server_id']]['service_id'],
                    'server_version_id': server_details[
                        server['tuned_server_id']]['server_version_id']
                },
            }
            node_data['branch'].append(branch_data)
            server_tuned_param = False
        already_tuned = False
        if server['orig_value'] == server['tuned_value']:
            checkbox = False
            already_tuned = True
            err_msg = gettext("Parameter is already tuned with the"
                              " suggested value.")
        else:
            server_tuned_param = True

        branch = {
            'server_id': server['tuned_server_id'],
            'label': gettext("{} = {} {}".format(
                server['tuned_parameter'],
                server['tuned_value'],
                '*' if server['tuned_parameter'] in restart_required_params
                else '')),
            'inode': False,
            'branch': [],
            'checkbox': checkbox,
            'checked': checkbox,
            'err_msg': err_msg,
            'already_tuned': already_tuned,
            'tuning_param_info': server['tuned_parameter'] + "," +
            server['tuned_value'],
            'restart_required':
                server['tuned_parameter'] in restart_required_params
        }

        branch_data['branch'].append(branch)
        server_id = server['tuned_server_id']
        cnt += 1

        if cnt == len(res['rows']):
            set_checkboxes(server_tuned_param, server_checkbox,
                           branch_data, node_data)


def get_sch_time(req):
    """function gives response as sch_time based on schedule"""
    if req['schedule']['configure_now']:
        return "now()"
    else:
        return "'" + req['schedule']['configure_date_time'] + "'"


def get_filename_download_status(req):
    """function gives response as filename & download status
        based on schedule"""
    filename = req['schedule']['file_name'] if 'file_name' \
                                               in req['schedule'] else ''
    is_download = False if 'view_now' in req['schedule'] and \
                           req['schedule']['view_now'] else True
    return filename, is_download


def filename_exists(filename, is_download):
    """function used to check if filename exists"""
    if is_download and (filename is None or filename == ''):
        return False
    return True


def process_filename(filename, is_download):
    """function gives response as filename with html extension"""
    if is_download and (filename is not None or filename != '') and\
        not filename.endswith(".html") and\
            not filename.endswith(".htm"):
        filename = filename + ".html"
    return filename


def process_server_data(s, servers):
    """function used to update server data in servers"""
    s['has_changed'] = False
    if 'server_id' in s:
        servers[s['server_id']] = s


def get_value_str(value, postfix1, postfix2):
    """function return value after adding proper postfix"""
    if int(value) < 1024:
        value_str = str(value) + postfix1
    else:
        value_div = round(int(value) / 1024)
        value_str = str(int(value_div)) + postfix2
    return value_str


def get_total_servers(req):
    """function return count of total servers"""
    total_servers = 0
    for s in req['servers']:
        if s['has_changed']:
            total_servers += 1
    return total_servers


def embed_files(paths, files):
    """function used to embed files in report"""
    for path in paths:
        f = open(path, "r", encoding='utf-8')
        files.append(f.read())


def process_scheduler(s, pem_conn, sch_time, req):
    """function returns jobid after scheduling jobs"""
    # Create the activation job for server tuning.
    description = "Server ID: " + str(s['server_id']) + \
                  ", agent ID: " + str(s['server_info']['agent_id'])

    params = ["Server tuning configuration request",
              description, s['server_info']['agent_id'], sch_time]

    sql = render_template('tuning_wizard/sql/create_job.sql')
    status, job_id = pem_conn.execute_scalar(sql, params)

    if not status:
        pem_conn.execute_void('ROLLBACK;')
        return 500, job_id, job_id

    # Format tuning parameters for the server
    tuning_params = ''
    for t in req['tuning_changes']:
        if 'server_id' in t and t['server_id'] == s['server_id'] \
                and 'tuning_param_info' in t:
            tuning_params += t['tuning_param_info'] + ";"

    tuning_params = tuning_params[0:tuning_params.rfind(";")]

    # Get the config directory file path, It requires when database
    # server's data directory and config directory is different.
    status, res = pem_conn.execute_dict(
        "SELECT regexp_replace (st.setting, '[|/][^|/]*$', '') "
        "AS config_file FROM pemdata.settings st WHERE "
        "server_id = %(server_id)s AND name = 'config_file'",
        {'server_id': s['server_id']}
    )

    if not status:
        pem_conn.execute_void('ROLLBACK')
        return 500, gettext("Error while fetching postgresql "
                            "configuration directory.")

    # Add configuration directory
    if len(res['rows']) > 0:
        code = "tuning_configuration \"" + \
               res['rows'][0]['config_file'] + "\" \"" + \
               tuning_params + "\""
    else:
        code = "tuning_configuration \"" + \
               s['server_info']['data_directory'] + "\" \"" + \
               tuning_params + "\""

    params = [job_id, "Modify postgresql.conf", description,
              "i", code, s['server_id']]

    # Create Job step to modify postgres conf
    sql = render_template('tuning_wizard/sql/create_jobstep.sql')
    status, msg = pem_conn.execute_void(sql, params)

    if not status:
        pem_conn.execute_void('ROLLBACK;')
        return 500, msg, job_id

    is_restart_required = reduce(lambda p, e:
                                 True if p or e + ',' in tuning_params
                                 else False, restart_required_params, False)

    if is_restart_required:
        params = [job_id, "Server Restart", description, "i",
                  "server_restart " + str(s['server_info']['service_id']),
                  s['server_id']]
    else:
        params = [job_id, "Server Reload", description, "s",
                  "SELECT pg_reload_conf();", s['server_id']]

    # Create Job step to restart the server
    sql = render_template('tuning_wizard/sql/create_jobstep.sql')
    status, msg = pem_conn.execute_void(sql, params)

    if not status:
        pem_conn.execute_void('ROLLBACK;')
        return 500, msg, job_id

    pem_conn.execute_void("COMMIT;")

    return 200, 'OK', job_id
