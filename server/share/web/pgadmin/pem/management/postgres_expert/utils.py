##########################################################################
#
# Postgres Enterprise Manager
#
# Copyright (C) 2016 - 2025, EnterpriseDB Corporation. All rights reserved.
#
##########################################################################

"""postgres expert utility functions"""

import os
from io import open
from flask import Response, render_template
from pgadmin.utils.ajax import internal_server_error
from pgadmin.pem.utils import get_default_stylesheets


def get_databases(obj, dashboard_transaction, pem_conn, new_server_db_list):
    """ function used to list the server and database"""
    # If database name is provided, add an entry for it in
    # newServerDbList
    if obj['dbName'] is not None:
        new_server_db_list.append([obj['sid'], obj['dbName']])

    # If not provided then fetch all database from that server and add
    # an entry for each database with that server id
    else:
        sql = render_template(
            'postgres_expert/sql/databases.sql',
            sid=obj['sid']
        )

        with dashboard_transaction:
            status, res = pem_conn.execute_dict(sql)

        if not status:
            return internal_server_error(errormsg=res)

        # If there is no database in that server, add an entry with
        # empty database so only server level rules can be applied on
        # it
        if len(res['rows']) == 0 or res['rows'][0]['database_name'] is None:
            new_server_db_list.append([obj['sid'], ''])
        else:
            for database in res['rows']:
                new_server_db_list.append([obj['sid'],
                                           database['database_name']])


def get_servers_data(server_list, servers_found_in_report_data, pem_conn,
                     report_data):
    """ function used to server data"""
    # Here we need to iterate over report data and check if data for all
    # the servers selected by user is present or not, if it is not present
    # then we need to add empty record for that missing server so that we
    # can list them on report with proper message
    for server in report_data:
        if server['id'] in server_list:
            servers_found_in_report_data.add(server['id'])

    servers_missing_in_report_data = server_list.difference(
        servers_found_in_report_data
    )

    if len(servers_missing_in_report_data) > 0:
        sql = render_template(
            'postgres_expert/sql/servers.sql'
        )
        status, result = pem_conn.execute_dict(sql)
        if not status:
            return internal_server_error(errormsg=result)

        for server in result['rows']:
            if server['server_id'] in servers_missing_in_report_data:
                report_data.append({
                    'id': server['server_id'],
                    'description': server['s_description'],
                    'host': server['server_name'],
                    'port': server['s_port'],
                    'experts': []
                })


def embed_css_js_files():
    """ this function is used to embed the css and js files in report"""
    css_files = []
    css_paths = get_default_stylesheets()

    for css_path in css_paths:
        f = open(css_path, "r", encoding='utf-8')
        css_files.append(f.read())

    js_files = []
    js_paths = [os.path.realpath('{}{}'.format(os.path.dirname(
        os.path.realpath(__file__)),
        '/../../static/js/generated/reports/postgres_expert.js'))]

    for js_path in js_paths:
        f = open(js_path, "r", encoding='utf-8')
        js_files.append(f.read())
    return css_files, js_files


def get_response(file_name, result):
    """ This function gives response as attachment in case of download """
    if file_name:
        r = Response(result, mimetype='text/html')
        r.headers["Content-Disposition"] = "attachment;filename={0}".\
            format(file_name)
    else:
        r = Response(result)
    return r


def get_rules_count(expert, rows, total_high_rules,
                    total_medium_rules, total_low_rules):
    """ function used to get high, medium and low rules count"""

    new_rule = {
        'id': rows['rule_id'],
        'name': rows['rule_name'],
        'database': rows['database_name'],
        'trigger': rows['trigger'],
        'recommend': rows['recommended_value'],
        'desc': rows['description'],
        'severity': rows['severity'],
        'data': []
    }
    # add data names and values in new_rule['data']
    if len(rows['data_name']) != 0 and len(rows['data_value']) != 0:
        for name, value in zip(rows['data_name'],
                               rows['data_value']):
            new_rule['data'].append({
                'name': name,
                'value': value
            })
    expert['rules'].append(new_rule)
    if rows['severity'] >= 9:
        total_high_rules += 1
    if 5 <= rows['severity'] < 9:
        total_medium_rules += 1
    if 1 <= rows['severity'] < 5:
        total_low_rules += 1
    return total_high_rules, total_medium_rules, total_low_rules
