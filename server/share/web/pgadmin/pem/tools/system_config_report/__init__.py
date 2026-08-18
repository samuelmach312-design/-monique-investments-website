##########################################################################
#
# Postgres Enterprise Manager
#
# Copyright (C) 2016 - 2025, EnterpriseDB Corporation. All rights reserved.
#
##########################################################################
"""Implements System Config Report"""

import platform
import time
import json
import os

try:
    from collections import OrderedDict
except ImportError:
    from ordereddict import OrderedDict
from flask import render_template, current_app, __version__, Response, request
from flask_babel import gettext
from flask_security import current_user, login_required
from pgadmin.utils.ajax import internal_server_error, precondition_required
from pgadmin.pem import version
from pgadmin.pem.utils import pem_connection, get_default_stylesheets
from pgadmin.utils import PgAdminModule
from pgadmin.utils.csrf import pgCSRFProtect
import config
from io import open
from .utils import (
    get_agent_bound_servers,
    get_server_details,
    get_core_mem_disk_details,
)

MODULE_NAME = 'system_config_report'


class SystemConfigReportModule(PgAdminModule):
    """
    class SystemConfigReportModule(Object):

        SystemConfigReportModule inherits PgAdminModule
        class and define methods to load its own
        javascript file.
    """

    LABEL = gettext('System Config Report')

    def register_preferences(self):
        """
        This function will setup preference for System Config Report

        :return None
        """
        pass

    def get_exposed_url_endpoints(self):
        """
        Returns:
            list: a list of url endpoints exposed to the client.
        """
        return ['system_config_report.download']


# Create blueprint for SystemConfigReportModule class
blueprint = SystemConfigReportModule(
    MODULE_NAME,
    __name__,
    static_url_path='',
    url_prefix='/pem/system_config_report',
)

PATH = 'system_config_report/sql/'

FILE_NAMES = {
    "alert_info": "alerts_info.sql",
    "probes_info": "probes_info.sql",
    "alert_thread_count": "alert_thread_count.sql",
    "active_agents_alert_settings": "active_agents_alert_settings.sql",
    "active_agents_last_24h": "active_agents_last_24h.sql",
    "active_servers_last_24h": "active_servers_last_24h.sql",
    "alert_eval_stats": "alert_eval_stats.sql",
    "delayed_alerts": "delayed_alerts.sql",
    "no_of_key_objects": "no_of_key_objects.sql",
    "pem_table_sizes":"pem_table_sizes.sql"
}


def execute_sql_template(conn, sql_path, error_label):
    query = render_template(PATH + sql_path)
    status, res = conn.execute_dict(query)
    if not status:
        current_app.logger.error(
            f"System Config Report: Failed to fetch the PEM {error_label}!\n"
            f"Details: {res}"
        )
        return False, internal_server_error(
            errormsg=gettext(f"Failed to fetch the PEM {error_label}!")
        )
    return res


def fetch_probes_alerts_info(conn, final_result):
    key = "alert_info"
    result = {}
    query = render_template(PATH + FILE_NAMES[key])
    status, res = conn.execute_dict(query)
    if not status:
        current_app.logger.error(
            "System Config Report: Failed to fetch the\
                PEM alert information!\n"
            f"Details: {res}"
        )
        return False, internal_server_error(
            errormsg=gettext("Failed to fetch\
                the PEM alert information!")
        )
    if len(res['rows']) > 0:
        result["data"] = res['rows'][0]

    result['label_keymap'] = {
        'enabled_alerts': gettext("No of alerts (enabled)"),
        'alert_evaluations_per_hour': gettext(
            "No of alerts evaluations per hour"
        )
    }

    key = "probes_info"
    query = render_template(PATH + FILE_NAMES[key])
    status, res = conn.execute_dict(query)
    if not status:
        current_app.logger.error(
            "System Config Report: Failed to fetch the\
                PEM probes information!\n"
            f"Details: {res}"
        )
        return False, internal_server_error(
            errormsg=gettext(f"Failed to fetch the PEM\
                probe information!")
        )
    if len(res['rows']) > 0:
        result['data'].update(res['rows'][0])

    result['label_keymap'].update(
        {"probes_per_hour": gettext("No of probe executions per hour")}
    )

    key = "active_agents_last_24h"
    active_agents_last_24h = 0
    query = render_template(PATH + FILE_NAMES[key])
    status, res = conn.execute_dict(query)
    if not status:
        current_app.logger.error(
            f"System Config Report: Failed to \
                fetch the PEM active_agents_last_24h!\n"
            f"Details: {res}"
        )
        return False, internal_server_error(
            errormsg=gettext(f"Failed to fetch the \
                PEM Number of active agents last 24h!")
        )
    if len(res['rows']) > 0:
        active_agents_last_24h = res['rows'][0].get('count')
    result['data'][key] = active_agents_last_24h
    result['label_keymap'].update(
        {key: gettext('Active agents (in last 24 hours)')}
    )

    key = "active_servers_last_24h"
    active_servers_last_24h = 0
    query = render_template(PATH + FILE_NAMES[key])
    status, res = conn.execute_dict(query)
    if not status:
        current_app.logger.error(
            f"System Config Report: Failed to \
                fetch the PEM active_servers_last_24h!\n"
            f"Details: {res}"
        )
        return False, internal_server_error(
            errormsg=gettext("Failed to fetch the PEM\
                Number of actively monitored servers last 24h!")
        )
    if len(res['rows']) > 0:
        active_servers_last_24h = res['rows'][0].get('count')
    result['data'][key] = active_servers_last_24h
    result['label_keymap'].update(
        {key: gettext('Active servers (in last 24 hours)')}
    )

    final_result['monitoring_overview'] = {
        'header': gettext('Monitoring Overview'),
        'columns': [
            {
                'header': gettext('Parameter'),
                'accessor': 'parameter',
                'width': '30%'
            },
            {
                'header': gettext('Value'),
                'accessor': 'value',
                'width': '70%'
            },
        ],
        **result
    }

    return final_result


def fetch_sizing_info(conn, final_result):
    key = "no_of_key_objects"
    result = []
    object_order = [
        "Agents",
        "Servers",
        "Databases",
        "Schemas",
        "Tables",
        "Indexes",
    ]
    query = render_template(PATH + FILE_NAMES[key])
    status, res = conn.execute_dict(query)
    if not status:
        current_app.logger.error(
            "System Config Report: Failed to fetch the\
                PEM no_of_key_objects!\n"
            f"Details: {res}"
        )
        return False, internal_server_error(
            errormsg=gettext("Failed to fetch the PEM\
                Number of key objects information!")
        )

    no_of_key_objects = sorted(
        res['rows'],
        key=lambda x: object_order.index(x["object_type"])
    )
    result.append({
        'data': no_of_key_objects,
        'columns': [
            {
                'header': gettext('Object Type'),
                'accessor': 'object_type',
                'width': '30%'
            },
            {
                'header': gettext('Count'),
                'accessor': 'count',
                'width': '70%'
            },
        ],
        'header': gettext('Object Catalogue Summary')
    })

    key = "pem_table_sizes"
    query = render_template(PATH + FILE_NAMES[key])
    status, res = conn.execute_dict(query)
    if not status:
        current_app.logger.error(
            "System Config Report: Failed to fetch\
                the pem_table_sizes!\n"
            f"Details: {res}"
        )
        return False, internal_server_error(
            errormsg=gettext("Failed to fetch the\
                PEM Table sizes!")
        )

    result.append({
        'data': res['rows'],
        'columns': [
            {
                'header': gettext("Table Name"),
                'accessor': "Table Name"
            },
            {
                'header': gettext("Schema Name"),
                'accessor': "Schema Name"
            },
            {
                'header': gettext("Index Size"),
                'accessor': "Index Size"
            },
            {
                'header': gettext("Table Size"),
                'accessor': "Table Size"
            },
            {
                'header': gettext("Total Table Size"),
                'accessor': "Total Table Size",
            },
        ],
        'header': gettext("Table Sizes")
    })

    final_result['sizing_info'] = {
        'header': gettext('Sizing Information'),
        'data': result
    }

    return final_result


def fetch_agent_info(conn, final_result):
    result = {}
    key = "alert_eval_stats"
    query = render_template(PATH + FILE_NAMES[key])
    status, res = conn.execute_dict(query)
    if not status:
        current_app.logger.error(
            "System Config Report:\
                Failed to fetch the PEM alert_eval_stats!\n"
            "Details: {res}"
        )
        return False, internal_server_error(
            errormsg=gettext(
                "Failed to fetch the PEM Evaluation time per alert!"
            )
        )
    eval_matrics = []
    if len(res['rows']) > 0:
        eval_matrics = [{'metric': k, 'value':v}
                        for k, v in res['rows'][0].items()]

    result[key] = {
        'data': eval_matrics,
        'columns': [
            {
                'header': gettext('Metric'),
                'accessor': 'metric',
            },
            {
                'header': gettext('Value'),
                'accessor': 'value',
            }
        ],
        'header': gettext('Alert Evaluation Metrics')
    }

    key = "active_agents_alert_settings"
    query = render_template(PATH + FILE_NAMES[key])
    status, res = conn.execute_dict(query)
    if not status:
        current_app.logger.error(
            "System Config Report:\
                Failed to fetch the PEM active_agents_alert_settings!\n"
            f"Details: {res}"
        )
        return False, internal_server_error(
            errormsg=gettext("Failed to fetch\
                the PEM active agent alert settings!")
        )

    result[key] = {
        'data': res['rows'],
        'columns': [
            {
                'header': gettext('Agent ID'),
                'accessor': 'agent_id',
            },
            {
                'header': gettext('Parameter'),
                'accessor': 'param',
            },
            {
                'header': gettext('Value'),
                'accessor': 'value',
            }
        ],
        'header': gettext('PEM Active Agent Alert Settings')
    }

    key = "delayed_alerts"
    query = render_template(PATH + FILE_NAMES[key])
    status, res = conn.execute_dict(query)
    if not status:
        current_app.logger.error(
            f"System Config Report: Failed to fetch the PEM delayed_alerts!\n"
            f"Details: {res}"
        )
        return False, internal_server_error(
            errormsg=gettext(f"Failed to fetch the PEM delayed alerts!")
        )

    result[key] = {
        'data': res['rows'],
        'columns': [
            {
                'header': gettext('Alert ID'),
                'accessor': 'id',
            },
            {
                'header': gettext('Name'),
                'accessor': 'name',
            },
            {
                'header': gettext('Check frequency'),
                'accessor': 'check_frequency',
            },
            {
                'header': gettext('Last mail sent'),
                'accessor': 'last_mail_send',
            },
            {
                'header': gettext('State'),
                'accessor': 'state',
            },
            {
                'header': gettext('Template name'),
                'accessor': 'template_name',
            },
            {
                'header': gettext('Last processed'),
                'accessor': 'last_processed',
            },
            {
                'header': gettext('Current time'),
                'accessor': 'now',
            },
            {
                'header': gettext('Delayed by'),
                'accessor': 'delayed_by',
            }
        ],
        'header': gettext('PEM Delayed Alerts')
    }

    final_result['agent_info'] = {
        'header': gettext('Alert Evaluation Info'),
        'data': result
    }

    return final_result


def generate_report_data(conn, is_json=False):
    """Generic function to generate data for report"""

    if not current_user.is_admin:
        return False, precondition_required(
            gettext(
                "The Postgres Enterprise Manager system config report is only "
                "available to superusers and users in the pem_admin role."
            )
        )

    # Store to hold all information for report
    final_result = OrderedDict()
    result = OrderedDict()

    # Counters
    total_agents = 0
    total_windows_agents = 0
    total_servers = 0
    total_locally_managed_server = 0
    total_remotely_managed_server = 0
    total_unmanaged_server = 0
    total_pg_servers = 0
    total_epas_servers = 0
    total_unknwon_servers = 0

    # Fetch the groups
    groups = render_template('system_config_report/sql/groups.sql')
    status, res = conn.execute_dict(groups)
    if not status:
        current_app.logger.error(
            "System Config Report: Failed to fetch the groups information!\n"
            "Details: {0}".format(res)
        )
        return False, internal_server_error(
            errormsg=gettext("Failed to fetch the groups information!")
        )
    if len(res['rows']) == 0:
        return False, internal_server_error(
            errormsg=gettext("No groups found!")
        )

    for group in res['rows']:
        result[group['id']] = {
            'name': group['name'],
            'agents': [],
            'servers': [],
        }

    # Fetch the agents details
    agents = render_template('system_config_report/sql/agents.sql')
    status, res = conn.execute_dict(agents, [current_user.user.username])
    if not status:
        current_app.logger.error(
            "System Config Report: Failed to fetch the agents information!\n"
            "Details: {0}".format(res)
        )
        return False, internal_server_error(
            errormsg=gettext("Failed to fetch the agents information!")
        )

    for agent in res['rows']:
        total_agents += 1

        _platform = agent['platform']
        if _platform and _platform.lower().find('windows') != -1:
            total_windows_agents += 1

        get_agent_bound_servers(agent)
        get_core_mem_disk_details(agent)

        result[agent['group_id']]['agents'].append(agent)

    # Fetch the servers details
    servers = render_template('system_config_report/sql/servers.sql')
    status, res = conn.execute_dict(servers, [current_user.user.username])
    if not status:
        current_app.logger.error(
            "System Config Report: Failed to fetch the servers information!\n"
            "Details: {0}".format(res)
        )
        return False, internal_server_error(
            errormsg=gettext("Failed to fetch the servers information!")
        )

    (
        total_servers,
        total_unmanaged_server,
        total_remotely_managed_server,
        total_locally_managed_server,
        total_epas_servers,
        total_pg_servers,
        total_unknwon_servers,
    ) = get_server_details(res, result)

    final_result['pem_info'] = {
        'name': config.APP_NAME,
        'version': version.APP_VERSION,
        'schema': current_user.schema_version,
        'database': conn.manager.ver,
        'user': current_user.user.username,
        'python': str(platform.python_version()),
        'flask': __version__,
        'platform': {
            'system': platform.system(),
            'node': platform.node(),
            'release': platform.release(),
            'version': platform.version(),
            'machine': platform.machine(),
            'processor': platform.processor(),
        },
    }
    try:
        import apache

        final_result['pem_info']['apache'] = str(apache.description)
    except Exception:
        # Application is not running as wsgi application under HTTPD
        pass

    # Basic summary stats
    final_result = fetch_probes_alerts_info(conn, final_result)

    # Sizing information
    final_result = fetch_sizing_info(conn, final_result)

    # Agent information
    final_result = fetch_agent_info(conn, final_result)

    # Summary of the report
    final_result['summary'] = {
        'total_agents': total_agents,
        'total_windows_agents': total_windows_agents,
        'total_unix_linux_agents': total_agents - total_windows_agents,
        'total_servers': total_servers,
        'total_locally_monitored_servers': total_locally_managed_server,
        'total_remotely_monitored_servers': total_remotely_managed_server,
        'total_unmanaged_servers': total_unmanaged_server,
        'total_pg_servers': total_pg_servers,
        'total_epas_servers': total_epas_servers,
        'total_unknwon_servers': total_unknwon_servers,
        'report_generated_time': time.strftime("%Y-%m-%d %H:%M:%S"),
    }

    final_result['report'] = result
    if not is_json:
        final_result['report_header_labels'] = {
            'header': gettext('System Configuration Report'),
            'generated_on': gettext('Generated On'),
            'go_to_text': gettext('Go To'),
            'pem_agents': gettext('PEM Agents'),
            'pem_server_dir': gettext('PEM Server Directory'),
            'table_sizes': gettext('PEM Table Sizes'),
        }
        final_result['pem_summary_labels'] = {
            'header': gettext('Postgres Enterprise Manager Summary'),
            'columns': [
                {'header': gettext('Parameter'),
                 'accessor': 'parameter',
                 'width': '30%'
                 },
                {'header': gettext('Value'),
                 'accessor': 'value',
                 'width': '70%'
                 },
            ],
        }
        final_result['summary_labels'] = {
            'header': gettext('Summary'),
            'columns': [
                {'header': gettext('Parameter'),
                 'accessor': 'parameter',
                 'width': '30%'
                 },
                {'header': gettext('Value'),
                 'accessor': 'value',
                 'width': '70%'
                 },
            ],
            'key_map': {
                'unknown': gettext('Unknown'),
                'locally_managed': gettext('Locally Managed'),
                'remotely_managed': gettext('Remotely Managed'),
                'unmanaged': gettext('Unmanaged'),
                'agents': gettext('Agents'),
                'servers': gettext('Servers'),
            },
        }
        final_result['pem_agents_labels'] = {
            "agent": {
                "group_name": gettext("Group"),
                "agent_description": gettext("Agent"),
                "active": gettext("Active"),
                "platform": gettext("Platform"),
                "os": gettext("Operating System"),
                "version": gettext("Version"),
                "hostname": gettext("Hostname"),
                "domain_name": gettext("Domain Name"),
                "bound_local_servers": gettext("Bound Local Servers"),
                "bound_remote_servers": gettext("Bound Remote Servers"),
                "none": gettext("(none)"),
                "agent_details": gettext("Agent Details"),
                "parameter": gettext('Parameter'),
                "value": gettext("Value"),
            },
            "cpu": {
                "section_title": gettext("CPU"),
                "total_cores": gettext("Total CPU Cores"),
                "avg_utilization": gettext("Average CPU Utilization (%)"),
                "core_id": gettext("Core ID"),
                "load_percentage": gettext("Load Percentage"),
            },
            "disk": {
                "section_title": gettext("Disk Utilization"),
                "total_disk_size": gettext("Total Disk Size (MB)"),
                "disk_space_used": gettext("Disk Space Used (MB)"),
                "disk_space_available": gettext("Disk Space Available (MB)"),
                "disk_utilization": gettext("Disk Utilization (%)"),
                "mount_point": gettext("Mount Point"),
                "file_system": gettext("File System"),
                "size_mb": gettext("Size (MB)"),
                "space_used_mb": gettext("Space Used (MB)"),
                "space_available_mb": gettext("Space Available (MB)"),
            },
            "memory": {
                "section_title": gettext("Memory Details"),
                "total_ram": gettext("Total RAM (MB)"),
                "free_ram": gettext("Free RAM (MB)"),
                "memory_usage": gettext("Memory Usage (%)"),
                "total_swap": gettext("Total Swap (MB)"),
                "free_swap": gettext("Free Swap (MB)"),
                "swap_usage": gettext("Swap Usage (%)"),
                "parameter": gettext('Parameter'),
                "value": gettext("Value"),
            },
            "general": {
                "unknown": gettext("Unknown"),
                "remotely_managed": gettext("Remotely Managed"),
                "locally_managed": gettext("Locally Managed"),
                "unmanaged": gettext("Unmanaged"),
            }
        }
        final_result['pem_servers_labels'] = {
            "group": {
                "name": gettext("Group"),
            },
            "server": {
                "header": gettext("Server"),
                "details": gettext("Server Details"),
                "parameter": gettext("Parameter"),
                "value": gettext("Value"),
                "agent": gettext("Agent"),
                "host": gettext("Host"),
                "port": gettext("Port"),
                "database": gettext("Database"),
                "version": gettext("Version"),
                "service_id": gettext("Service Id"),
                "remote_monitored": gettext("Remote Monitored?"),
                "active": gettext("Active"),
                "none": gettext("None"),
            },
            "database": {
                "header": gettext("Database Details"),
                "name": gettext("Name"),
                "size_mb": gettext("Size (MB)"),
                "tablespace_name": gettext("Tablespace Name"),
            },
            "tablespace": {
                "header": gettext("Tablespace Details"),
                "name": gettext("Name"),
                "size_mb": gettext("Size (MB)"),
            },
            "object_count": {
                "header": gettext("Object Count"),
                "name": gettext("Object Name"),
                "count": gettext("Count"),
                "num_indexes": gettext('Index'),
                "num_tables": gettext('Table')
            },
            "db_objects_stats":{
                'section_title': gettext('Table Index Summary'),
                'db_hash': gettext('Database Hash'),
                'schema_hash': gettext('Schema Hash'),
                'tables': gettext('Tables'),
                'indexes': gettext('Indexes'),
            }
        }
        final_result['common_labels'] = {
            'group_name': gettext('Group'),
            'no_data': gettext('No data found.')
        }
    return True, final_result


@blueprint.route("/download", methods=["GET"], endpoint='download')
@pgCSRFProtect.exempt
@login_required
@pem_connection
def download(pem_conn=None):
    """
    Route to download System Config Report in standalone HTML format
    :param pem_conn:
    :return:
    """
    is_json = request.args.get('json') == 'true'
    status, data = generate_report_data(pem_conn, is_json)
    if not status:
        return data

    file_extn = 'html'

    if is_json:
        file_extn = 'json'

    file_name = 'PEM_SystemConfigReport_{0}.{1}'.format(
        time.strftime("%Y-%m-%d_%H-%M-%S"), file_extn
    )

    if is_json:
        resp = Response(json.dumps(data), mimetype='application/json')
        resp.headers['Content-Disposition'] = (
            'attachment; filename={0}'.format(file_name)
        )
        return resp
    else:

        js_files = []
        path = '/../../static/js/generated/reports/system_config_report.js'
        js_paths = [
            os.path.realpath(
                '{}{}'.format(
                    os.path.dirname(os.path.realpath(__file__)),
                    path,
                )
            )
        ]

        for js_path in js_paths:
            f = open(js_path, "r", encoding='utf-8')
            js_files.append(f.read())

    return render_template(
        'system_config_report/html/index.html',
        js_files=js_files,
        report_time=time.strftime("%Y-%m-%d %H:%M:%S %Z"),
        report_data=data,
    )
