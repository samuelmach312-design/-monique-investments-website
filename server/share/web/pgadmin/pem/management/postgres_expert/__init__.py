##########################################################################
#
# Postgres Enterprise Manager
#
# Copyright (C) 2016 - 2025, EnterpriseDB Corporation. All rights reserved.
#
##########################################################################

"""Implements Postres Expert Wizard"""

import json
import time
from flask import Response, url_for
from flask import render_template, request, current_app
from flask_babel import gettext
from flask_security import login_required
from pgadmin.utils import PgAdminModule
from pgadmin.utils.ajax import make_response as ajax_response, \
    make_json_response, internal_server_error, bad_request
from pgadmin.utils.csrf import pgCSRFProtect
from pgadmin.pem.utils import pem_connection
from pgadmin.pem.monitor.dashboard.utils import DashboardTransaction, \
    cancel_dashboard
from pgadmin.pem.utils.role import PEMRole
from .utils import get_databases, get_servers_data, embed_css_js_files, \
    get_response, get_rules_count

# set template path for sql scripts
_ = gettext
MODULE_NAME = 'postgres_expert'
server_info = {}

peRole = PEMRole(
    'pem_comp_postgres_expert', gettext('Postgres expert'),
    gettext('Postgres expert'),
    gettext('Priviledge to generate the Postgres expert report.')
)


class PostgresExpertModule(PgAdminModule):
    """
    class PostgresExpertModule(Object):

        It is a wizard class which inherits PgAdminModule
        class and define methods to load its own
        javascript file.
    """
    LABEL = gettext('Postgres Expert')

    def get_own_stylesheets(self):
        """
        Returns:
            list: the stylesheets used by this module.
        """
        stylesheets = [
            url_for('management.static', filename='css/management.css'),
            url_for('browser.static', filename='css/wizard.css')
        ]
        return stylesheets

    def get_exposed_url_endpoints(self):
        """
        Returns:
            list: a list of url endpoints exposed to the client.
        """
        return [
            'postgres_expert.rules', 'postgres_expert.servers',
            'postgres_expert.generate_report', 'postgres_expert.close'
        ]


# Create blueprint for PostgresExpertModule class
blueprint = PostgresExpertModule(
    MODULE_NAME, __name__, static_url_path='',
    url_prefix='/pem/postgres_expert')


@blueprint.route("/")
@login_required
def index():
    return bad_request(errormsg=gettext(
        "This URL cannot be called directly!")
    )


@blueprint.route("/postgres_expert.css")
@login_required
def postgres_expert_css():
    """render own javascript"""
    return ajax_response(
        render_template(
            'postgres_expert/css/postgres_expert.css'
        ),
        200, {
            'Content-Type': 'text/css'
        })


@blueprint.route('/rules', methods=["GET"], endpoint='rules')
@login_required
@peRole.check_role(
    gettext("Logged-in user do not have permission to access "
            "postgres expert rules.")
)
@pem_connection
def rules(pem_conn=None):
    """
    This function will return the experts/rules list
    """
    sql = render_template(
        'postgres_expert/sql/rules.sql'
    )

    status, res = pem_conn.execute_dict(sql)

    if not status:
        return internal_server_error(errormsg=res)

    # Create json response for expert/rules
    data = []
    d = {
        'label': gettext('Experts/Rules'),
        'inode': True,
        'open': True,
        'branch': [],
        'checkbox': True,
        'checked': True,
        'dummy': True
    }
    data.append(d)

    for expert in res['rows']:
        k = {
            'id': expert['expert_id'],
            'label': expert['expert_name'],
            'inode': True,
            'checked': True,
            'dummy': False,
            'branch': []
        }
        d['branch'].append(k)

        for (rule, rid) in zip(expert['rule_list'], expert['rule_id_list']):
            k['branch'].append({
                'id': str(expert['expert_id']) + '/' + str(rid),
                'expert_id': expert['expert_id'],
                'rule_id': rid,
                'label': rule,
                'inode': False,
                'dummy': False,
                'icon': False,
                'checked': True
            })

    return make_json_response(
        data=data
    )


@blueprint.route('/servers', methods=["GET"], endpoint='servers')
@login_required
@peRole.check_role(
    gettext("Logged-in user do not have permission to access server list.")
)
@pem_connection
def servers(pem_conn=None):
    """
    This function will return the server/databases list
    """
    sql = render_template(
        'postgres_expert/sql/servers.sql'
    )

    status, res = pem_conn.execute_dict(sql)

    if not status:
        return internal_server_error(errormsg=res)

    data = []
    d = {
        'label': gettext('Servers/Databases'),
        'inode': True,
        'open': True,
        'branch': [],
        'checked': True,
        'dummy': True
    }
    data.append(d)
    for server in res['rows']:
        k = {
            'server_id': server['server_id'],
            'label': server['description'],
            'inode': False if (len(server['database_list']) == 0 or
                               (len(server['database_list']) == 1 and
                                server['database_list'][0] is None)) else True,
            'branch': [],
            'checked': True,
            'dummy': False
        }
        d['branch'].append(k)

        for database in server['database_list']:
            if database is not None:
                k['branch'].append({
                    'id': str(server['server_id']) + '/' + database,
                    'server_id': server['server_id'],
                    'database': database,
                    'label': database,
                    'inode': False,
                    'checked': True,
                    'dummy': False
                })

    return make_json_response(
        data=data
    )


@blueprint.route(
    '/generate_report/<int:trans_id>', methods=('GET', 'POST'),
    endpoint='generate_report'
)
@pgCSRFProtect.exempt
@login_required
@peRole.check_role(
    gettext("Logged-in user do not have permission to generate "
            "postgres expert report.")
)
@pem_connection
def generate_report(trans_id=0, pem_conn=None):
    """
    This function will generate the postgres export report
    """
    try:
        rules_list = json.loads(request.args['rulesList'])
        server_db_list = json.loads(request.args['serverDbList'])

        # Fetch filename if provided from client
        file_name = None
        if 'file_name' in request.args and request.args['file_name'] != '':
            file_name = request.args['file_name']

        new_server_db_list = []
        server_list = set()
        servers_found_in_report_data = set()
        total_remote_servers = 0

        if len(rules_list) <= 0 or len(server_db_list) <= 0:
            return bad_request(
                errormsg=gettext(
                    'Either rule list or server/database list is empty.'
                )
            )
        dashboard_transaction = DashboardTransaction(
            trans_id, pem_conn.conn_id, -1, 0
        )
        # Create proper server-database list for all selected servers
        for obj in server_db_list:

            # Create a set of all selected servers
            server_list.add(obj['sid'])

            # Check for remotely monitored server
            sql = render_template(
                'postgres_expert/sql/remote_server_check.sql',
                sid=obj['sid']
            )

            with dashboard_transaction:
                status, is_remote_server = pem_conn.execute_scalar(sql)

            if not status:
                return internal_server_error(errormsg=is_remote_server)

            if is_remote_server is True:
                total_remote_servers += 1

            get_databases(obj, dashboard_transaction, pem_conn,
                          new_server_db_list)

        # if all servers are remotely monitored then allow rules which are
        # applicable only on remotely monitored servers
        updated_rules_list = rules_list
        if len(server_list) == total_remote_servers:
            # Check if the rule is applicable on remotely monitored server
            sql = render_template(
                'postgres_expert/sql/remote_rule_check.sql'
            )

            with dashboard_transaction:
                status, res = pem_conn.execute_dict(sql, (tuple(rules_list),))

            if not status:
                return internal_server_error(errormsg=res)

            is_remote_rules = {row['id']: row['run_on_remote_server']
                               for row in res['rows']}

            updated_rules_list = [rule for rule in rules_list if
                                  is_remote_rules[rule] is True]

        # Call pem.pe_engine() function to receive postgres expert report table
        sql = render_template(
            'postgres_expert/sql/pe_engine.sql'
        )
        with dashboard_transaction:
            pem_conn.execute_void("BEGIN;")
            status, res = pem_conn.execute_dict(sql,
                                                [updated_rules_list,
                                                 new_server_db_list]
                                                )
            pem_conn.execute_void("END;")

        if not status:
            return internal_server_error(errormsg=res)

        pe_engine_data = res['rows']
        total_servers = len(server_list)
        total_rules = len(updated_rules_list)

        # Below function call will restructure the data
        # And also return total no of high, medium and low alerts
        # Get restructured rule data,

        report_data, \
            total_high_alerts, \
            total_medium_alerts, \
            total_low_alerts = restructure_report_data(pe_engine_data)

        get_servers_data(server_list, servers_found_in_report_data,
                         pem_conn, report_data)

        # Embed css/js files
        css_files, js_files = embed_css_js_files()

        # Call this function to load the html template for report with all
        # required data

        # If there is no data for selected rules then show appropriate message
        is_goto_dropdown_required = True
        if len(report_data) == 0:
            is_goto_dropdown_required = False

        result = render_template(
            'postgres_expert/html/report.html',
            is_goto_dropdown_required=is_goto_dropdown_required,
            report_data=report_data,
            total_servers=total_servers,
            total_rules=total_rules,
            high_alerts=total_high_alerts,
            medium_alerts=total_medium_alerts,
            low_alerts=total_low_alerts,
            report_time=time.strftime("%Y-%m-%d %H:%M:%S"),
            css_files=css_files,
            js_files=js_files
        )
        r = get_response(file_name, result)

        return r
    except Exception as e:
        current_app.logger.exception(e)
        r = Response("{}".format(str(e)), status=500)
        r.headers["Content-Disposition"] = "attachment;filename={0}".format(
            file_name)

        return r


def restructure_report_data(pe_engine_data):
    server_rules = []
    total_high_rules = 0
    total_medium_rules = 0
    total_low_rules = 0
    for rows in pe_engine_data:
        # check if existing server has same id as rows['server_id']
        server = next((srvr for srvr in server_rules
                       if srvr['id'] == rows['server_id']), None)
        # if server exists then check for existing expert in that server
        if not server:
            new_server = {
                'id': rows['server_id'],
                'description': rows['server_description'],
                'host': rows['server_host'],
                'port': rows['server_port'],
                'experts': []
            }
            server_rules.append(new_server)

        server = next((srvr for srvr in server_rules
                       if srvr['id'] == rows['server_id']), None)
        # check if expert exists in that server with given expert name
        expert = next((exp for exp in server['experts']
                       if exp['name'] == rows['expert_name']), None)
        # Add new expert if it does not exists
        if server and not expert:
            new_expert = {
                'name': rows['expert_name'],
                'rules': []
            }
            server['experts'].append(new_expert)
        # If expert exists then check for rule in that expert for given rule_id
        if server:
            expert = next((exp for exp in server['experts']
                           if exp['name'] == rows['expert_name']), None)
            if expert:
                rule = next((rule for rule in expert['rules']
                             if rule['id'] == rows['rule_id']), None)
                # if rule does not exists then add a new rule
                if rule is None:
                    total_high_rules, total_medium_rules, total_low_rules = \
                        get_rules_count(expert, rows, total_high_rules,
                                        total_medium_rules, total_low_rules)

    return server_rules, total_high_rules, total_medium_rules, total_low_rules


@blueprint.route(
    '/close/<int:trans_id>',
    methods=['get'], endpoint='close'
)
@login_required
@peRole.check_role(
    gettext("Logged-in user do not have permission to cancel postgres expert "
            "report generation.")
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
