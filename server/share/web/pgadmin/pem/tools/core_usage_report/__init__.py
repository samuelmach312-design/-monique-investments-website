##########################################################################
#
# Postgres Enterprise Manager
#
# Copyright (C) 2016 - 2025, EnterpriseDB Corporation. All rights reserved.
#
##########################################################################

"""Implements Core Usage Report"""
import time
import json
import os
try:
    from collections import OrderedDict
except ImportError:
    from ordereddict import OrderedDict
from flask import render_template, current_app, Response, request
from flask_babel import gettext
from flask_security import current_user, login_required
from pgadmin.utils.ajax import internal_server_error, \
    precondition_required
from pgadmin.pem import version
from pgadmin.pem.utils import pem_connection, get_default_stylesheets
from pgadmin.utils import PgAdminModule
from pgadmin.utils.csrf import pgCSRFProtect
import config
from io import open

MODULE_NAME = 'core_usage_report'


class CoreUsageReportModule(PgAdminModule):
    """
    class CoreUsageReportModule(Object):

        CoreUsageReportModule inherits PgAdminModule
        class and define methods to load its own
        javascript file.
    """
    LABEL = gettext('Core Usage Report')

    def register_preferences(self):
        """
            This function will setup preference for Core Usage Report

            :return None
        """
        pass

    def get_exposed_url_endpoints(self):
        """
        Returns:
            list: a list of url endpoints exposed to the client.
        """
        return [
            'core_usage_report.download'
        ]


# Create blueprint for CoreAuditReportModule class
blueprint = CoreUsageReportModule(
    MODULE_NAME,
    __name__,
    static_url_path='',
    url_prefix='/pem/core_usage_report'
)


def generate_report_data(conn, is_json):
    """Generic function to generate data for report"""
    final_result = OrderedDict()
    result = OrderedDict()
    if not current_user.is_admin:
        return False, precondition_required(gettext(
            "The Postgres Enterprise Manager core usage report is only "
            "available to superusers and users in the pem_admin role."
        ))

    # Fetch the report details
    sql = render_template('core_usage_report/sql/report_data.sql')
    status, res = conn.execute_dict(sql)
    if not status:
        current_app.logger.error(
            "Core Usage Report: Failed to fetch the report information!\n"
            "Details: {0}".format(res)
        )
        return False, internal_server_error(
            errormsg=gettext("Failed to fetch the report information!")
        )
    # psycopg2 gives result in string so we need to convert it as Python type
    for row in res['rows']:
        json_obj = json.loads(row['res'])
        for key, value in list(json_obj.items()):
            result[key] = value

    # Lets add PEM related information into the response
    final_result['pem_info'] = {
        'name': config.APP_NAME,
        'version': version.APP_VERSION,
        'schema': current_user.schema_version,
        'database': conn.manager.ver,
        'user': current_user.user.username,
    }
    if not is_json:
        final_result['report_header_labels'] = {
            'header': gettext('Core Usage Report'),
            'generated_on': gettext('Generated On'),
            'using': gettext('Using'),
            'version': gettext('Version'),
            'schema': gettext('schema'),
        }
        final_result['core_summary_labels'] = {
            'core_summary': gettext('Core Summary'),
            'total_number_of_cores': gettext('Total Number of Cores'),
            'server_type_columns': [
                {'header': gettext('Server Type'), 'accessor': 'type'},
                {'header': gettext('Number of Servers'),
                 'accessor': 'servers'},
                {'header': gettext('Number of Cores'), 'accessor': 'cores'},
            ],
            'database_version_columns': [
                {'header': gettext('Database Version'), 'accessor': 'version'},
                {'header': gettext('Number of Servers'),
                 'accessor': 'servers'},
                {'header': gettext('Number of Cores'), 'accessor': 'cores'},
            ],
            'platform_columns': [
                {'header': gettext('Platform'), 'accessor': 'platform'},
                {'header': gettext('Number of Servers'),
                 'accessor': 'servers'},
                {'header': gettext('Number of Cores'), 'accessor': 'cores'},
            ],
            'group_name_columns': [
                {'header': gettext('Group Name'), 'accessor': 'name'},
                {'header': gettext('Number of Servers'),
                 'accessor': 'servers'},
                {'header': gettext('Number of Cores'), 'accessor': 'cores'},
            ],
        }
        final_result['server_summary_labels'] = {
            'server_summary': gettext('Server Core Summary'),
            'locally_managed_servers': gettext('Locally Managed Servers'),
            'server_summary_columns': [
                {'header': gettext('Name'), 'accessor': 'name'},
                {'header': gettext('Type'), 'accessor': 'type'},
                {'header': gettext('Host:Port'), 'accessor': 'hostPort'},
                {'header': gettext('PGD?'), 'accessor': 'pgd'},
                {'header': gettext('PGD Version'), 'accessor': 'pgdVersion'},
                {'header': gettext('Platform'), 'accessor': 'platform'},
                {'header': gettext('Cores'), 'accessor': 'cores'},
                {'header': gettext('Total RAM (MB)'), 'accessor': 'ram'},
            ],
            'remote_servers': gettext('Remotely Managed Servers:'),
            'unmanaged_servers': gettext('Unmanaged Servers:'),
            'remote_servers_columns': [
                {'header': gettext('Name'), 'accessor': 'name'},
                {'header': gettext('Type'), 'accessor': 'type'},
                {'header': gettext('Host:Port'), 'accessor': 'hostPort'},
                {'header': gettext('PGD?'), 'accessor': 'pgd'},
                {'header': gettext('PGD Version'), 'accessor': 'pgdVersion'}
            ],
            'unmanaged_servers_columns': [
                {'header': gettext('Name'), 'accessor': 'name'},
                {'header': gettext('Host:Port'), 'accessor': 'hostPort'},
                {'header': gettext('PGD?'), 'accessor': 'pgd'},
                {'header': gettext('PGD Version'), 'accessor': 'pgdVersion'}
            ]
        }
    final_result['report'] = result

    return True, final_result


@blueprint.route("/download", methods=["GET"], endpoint='download')
@pgCSRFProtect.exempt
@login_required
@pem_connection
def download(pem_conn=None):
    """
    Route to download Usage Usage Report in standalone HTML format
    :param pem_conn:
    :return:
    """
    is_json = request.args.get('json') == 'true'
    status, data = generate_report_data(pem_conn, is_json)
    if not status:
        return data

    file_extn = 'html'
    # If user requested JSON then we need to change the file extn

    if is_json:
        file_extn = 'json'

    file_name = 'PEM_CoreUsageReport_{0}.{1}'.format(
        time.strftime("%Y-%m-%d_%H-%M-%S"), file_extn
    )

    if is_json:
        resp = Response(
            json.dumps(data),
            mimetype='application/json'
        )
        resp.headers['Content-Disposition'] = \
            'attachment; filename={0}'.format(file_name)
        return resp
    else:
        js_files = []
        js_paths = [os.path.realpath('{}{}'.format(os.path.dirname(
            os.path.realpath(__file__)),
            '/../../static/js/generated/reports/core_usage_report.js'))]

        for js_path in js_paths:
            f = open(js_path, "r", encoding='utf-8')
            js_files.append(f.read())
    return render_template(
        'core_usage_report/html/index.html',
        js_files=js_files,
        report_time=time.strftime("%Y-%m-%d %H:%M:%S %Z"),
        report_data=data)
