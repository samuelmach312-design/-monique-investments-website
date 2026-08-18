##########################################################################
#
# Postgres Enterprise Manager
#
# Copyright (C) 2016 - 2025, EnterpriseDB Corporation. All rights reserved.
#
##########################################################################

"""HTML Related Functions."""

import os
import base64
import re
import config

from flask import url_for, render_template, render_template_string
from xml.etree import ElementTree as ET
from xml.etree.ElementTree import Element, SubElement
from pgadmin.pem.misc.error import prettify
from pgadmin.pem.utils import pem_connection
import codecs
from pgadmin.pem.misc.error import error_return, PEMErrorType
from pgadmin.pem.monitor.utils import DashboardLevel
from pgadmin.pem.monitor.utils.charts import ChartType, SystemCharts
from pgadmin.pem.monitor.dashboard.utils.charts import PEMChartAlign, \
    PEMChartWidth
from flask_babel import gettext

from urllib.parse import quote


class PEMPredefinedDashboards:
    # Can't have array as constant :(
    GLOBAL_OVERVIEW = 1
    ALERTS = 2
    AUDIT_LOGS = 3
    PROBE_LOGS = 4
    SERVER_LOGS = 5
    OS = 6
    SERVER = 7
    MEMORY = 8
    SESSION_ACTIVITY = 9
    STORAGE = 10
    SYSTEM_WAIT = 11
    DATABASE = 12
    IO = 13
    OBJ_ACTIVITY = 14
    SESSION_WAITS = 15
    # JIRA: PEM-3502
    # Update the ID in JS code in case we change the STREAMING_REPLICATION ID
    STREAMING_REPLICATION = 16
    BDR_NODE_MONITORING = 17
    BDR_GROUP_MONITORING = 18
    BDR_ADMIN = 19


class PEMDashboards:

    dashboards = {
        PEMPredefinedDashboards.GLOBAL_OVERVIEW: {
            "id": PEMPredefinedDashboards.GLOBAL_OVERVIEW,
            "title": gettext("Global Overview"),
            "supports_edb_server": True,
            "supports_pg_server": True,
            "url": PEMPredefinedDashboards.GLOBAL_OVERVIEW,
            "content": [{
                "type": "section",
                "id": 1,
                "label": gettext("Enterprise Dashboard"),
                "charts": [
                    dict({
                        "id": SystemCharts.GLOBAL_STATUS,
                        "level": DashboardLevel.DB_GLOBAL,
                        "label": gettext("Status"),
                        "width": PEMChartWidth.MEDIUM,
                        "type": ChartType.BAR,
                        "align": PEMChartAlign.CENTER,
                    }),
                    dict({
                        "id": SystemCharts.AGENT_STATUS_INFO,
                        "level": DashboardLevel.DB_GLOBAL,
                        "label": gettext("Agent Status"),
                        "width": PEMChartWidth.FULL,
                        "type": ChartType.AGENT_STATUS,
                        "align": PEMChartAlign.CENTER,
                    }),
                    dict({
                        "id": SystemCharts.SERVER_STATUS_INFO,
                        "level": DashboardLevel.DB_GLOBAL,
                        "label": gettext("Server Status"),
                        "width": PEMChartWidth.FULL,
                        "type": ChartType.SERVER_STATUS,
                        "align": PEMChartAlign.CENTER,
                    }),
                    dict({
                        "id": SystemCharts.ALERTS_STATUS_INFO,
                        "level": DashboardLevel.DB_GLOBAL,
                        "label": gettext("Alerts"),
                        "width": PEMChartWidth.FULL,
                        "type": ChartType.ALERT_STATUS,
                        "align": PEMChartAlign.CENTER,
                    }),
                ],
            }],
        },
        PEMPredefinedDashboards.ALERTS: {
            "id": PEMPredefinedDashboards.ALERTS,
            "title": gettext("Alerts"),
            "supports_edb_server": True,
            "supports_pg_server": True,
            "url": PEMPredefinedDashboards.ALERTS,
            "content": [dict({
                "type": "section",
                "id": 1,
                "label": gettext("Alerts Overview"),
                "charts": [
                    dict({
                        "id": SystemCharts.ALERTS_OVERVIEW,
                        "level": -1,
                        "label": gettext("Alert Status"),
                        "width": PEMChartWidth.SMALL,
                        "type": ChartType.BAR,
                        "align": PEMChartAlign.CENTER,
                    }),
                    dict({
                        "id": SystemCharts.ALERTS_DETAILS,
                        "level": -1,
                        "label": gettext("Alert Details"),
                        "type": ChartType.ALERT_DETAILS,
                        "width": PEMChartWidth.FULL,
                    }),
                    dict({
                        "id": SystemCharts.ALERTS_ERRORS,
                        "level": -1,
                        "label": gettext("Alert Errors"),
                        "type": ChartType.ALERT_ERRORS,
                        "width": PEMChartWidth.FULL,
                    })
                ],
            })],
        },
        PEMPredefinedDashboards.AUDIT_LOGS: {
            "id": PEMPredefinedDashboards.AUDIT_LOGS,
            "title": gettext("Audit Log"),
            "supports_edb_server": True,
            "supports_pg_server": False,
            "url": PEMPredefinedDashboards.AUDIT_LOGS,
            "content": [dict({
                "type": "infinite_table",
                "label": gettext("Audit Logs"),
                "filter_on": ['username', 'database', 'commandtype'],
                "url": 'audit_logs',
                "tooltip":
                """{0}  \n
**{1}:** {2}

**{3}:** {4}

**{5}:** {6}

**{7}:** {8}

**{9}:** {10}

**{11}:** {12}

**{13}:** {14}

**{15}:** {16}

**{17}:** {18}""".format(
                    gettext(
                        "This table displays audit messages returned by the "
                        "PPAS audit logs."
                    ),
                    gettext("Timestamp"),
                    gettext("The date and time that the log entry was made."),
                    gettext("User Name"),
                    gettext(
                        "The user which executed the statement in the audit "
                        "log entry."
                    ),
                    gettext("Database Name"),
                    gettext(
                        "The database on which the statement in the audit log "
                        "entry was executed."
                    ),
                    gettext("Process ID"),
                    gettext(
                        "The ID of the process which executed the statement "
                        "in the audit log entry."
                    ),
                    gettext("Session ID"),
                    gettext(
                        "The ID of the session in which the statement in the "
                        "audit log entry was executed."
                    ),
                    gettext("Transaction ID"),
                    gettext(
                        "The ID of the transaction in which the statement in "
                        "the audit log entry was executed."
                    ),
                    gettext("Connection From"),
                    gettext(
                        "The client address from where the session was "
                        "connected."
                    ),
                    gettext("Command"),
                    gettext(
                        "The type of statement."
                    ),
                    gettext("Message"),
                    gettext(
                        "The message associated with the audit log entry."
                    ),
                ),
            })],
        },
        PEMPredefinedDashboards.PROBE_LOGS: {
            "id": PEMPredefinedDashboards.PROBE_LOGS,
            "title": gettext("Probe Log"),
            "supports_edb_server": True,
            "supports_pg_server": True,
            "url": PEMPredefinedDashboards.PROBE_LOGS,
            "content": [dict({
                "type": "infinite_table",
                "label": gettext("Probe Logs"),
                "filter_on": [],
                "url": 'probe_logs',
                "tooltip":
                """{0}  \n
**{1}:** {2}

**{3}:** {4}

**{5}:** {6}""".format(
                    gettext(
                        "This table displays error messages returned by the "
                        "PEM Agent while executing probes to collect "
                        "monitoring server statistics.  Entries in the Probe "
                        "Log table may reflect incorrect agent binding "
                        "information or authentication errors between the PEM "
                        "agent and the server PPAS audit logs."
                    ),
                    gettext("Timestamp"),
                    gettext("The date and time that the log entry was made."),
                    gettext("Probe Name"),
                    gettext(
                        "The name of the probe that recorded the log entry."
                    ),
                    gettext("Error Message"),
                    gettext(
                        "The error message returned by the probe."
                    ),
                )
            })],
        },
        PEMPredefinedDashboards.SERVER_LOGS: {
            "id": PEMPredefinedDashboards.SERVER_LOGS,
            "title": gettext("Server Log"),
            "supports_edb_server": True,
            "supports_pg_server": True,
            "url": PEMPredefinedDashboards.SERVER_LOGS,
            "content": [dict({
                "type": "infinite_table",
                "label": gettext("Server Logs"),
                "filter_on": ["username", "database", "commandtype"],
                "url": "server_logs",
                "tooltip":
                """{0}  \n
**{1}:** {2}

**{3}:** {4}

**{5}:** {6}

**{7}:** {8}

**{9}:** {10}

**{11}:** {12}

**{13}:** {14}

**{15}:** {16}

**{17}:** {18}""".format(
                    gettext(
                        "This table displays server log messages returned by "
                        "the server logs."
                    ),
                    gettext("Timestamp"),
                    gettext("The date and time that the log entry was made."),
                    gettext("User Name"),
                    gettext(
                        "The user which executed the statement in the server "
                        "log entry."
                    ),
                    gettext("Database Name"),
                    gettext(
                        "The database on which the statement in the server "
                        "log entry was executed."
                    ),
                    gettext("Process ID"),
                    gettext(
                        "The ID of the process which executed the statement "
                        "in the server log entry."
                    ),
                    gettext("Session ID"),
                    gettext(
                        "The ID of the session in which the statement in the "
                        "server log entry was executed."
                    ),
                    gettext("Transaction ID"),
                    gettext(
                        "The ID of the transaction in which the statement in "
                        "the server log entry was executed."
                    ),
                    gettext("Connection From"),
                    gettext(
                        "The client address from where the session was "
                        "connected."
                    ),
                    gettext("Command"),
                    gettext(
                        "The type of statement."
                    ),
                    gettext("Message"),
                    gettext(
                        "The message associated with the server log entry."
                    ),
                ),
            })],
        },
        PEMPredefinedDashboards.OS: {
            "id": PEMPredefinedDashboards.OS,
            "title": gettext("Operating System"),
            "supports_edb_server": True,
            "supports_pg_server": True,
            "url": PEMPredefinedDashboards.OS,
            "content": [
                dict({
                    "type": "section",
                    "id": 1,
                    "label": gettext("OS Overview"),
                    "charts": [
                        dict({
                            "id": SystemCharts.CPU_STATS,
                            "level": DashboardLevel.DB_AGENT,
                            "label": gettext("CPU"),
                            "type": ChartType.LINE,
                            "summary": SystemCharts.CPU_STATS_DETAILS,
                            "width": PEMChartWidth.MEDIUM,
                        }),
                        dict({
                            "id": SystemCharts.STRG_STATS,
                            "level": DashboardLevel.DB_AGENT,
                            "label": gettext("Storage"),
                            "type": ChartType.PIE,
                            "width": PEMChartWidth.MICRO,
                        }),
                        dict({
                            "id": SystemCharts.MEMORY_STATS,
                            "level": DashboardLevel.DB_AGENT,
                            "label": gettext("Memory"),
                            "type": ChartType.LINE,
                            "summary": SystemCharts.MEMORY_STATS_DETAILS,
                            "width": PEMChartWidth.SMALL,
                        }),
                        dict({
                            "id": SystemCharts.PROCESS_STATS,
                            "level": DashboardLevel.DB_AGENT,
                            "label": gettext("Process"),
                            "type": ChartType.LINE,
                            "width": PEMChartWidth.SMALL,
                        }),
                    ],
                }),
                dict({
                    "type": "section",
                    "id": 2,
                    "label": gettext("Disk"),
                    "charts": [
                        dict({
                            "id": SystemCharts.DISK_UTILIZATION,
                            "level": DashboardLevel.DB_AGENT,
                            "label": gettext("Disk"),
                            "type": ChartType.LINE,
                            "width": PEMChartWidth.SMALL,
                        }),
                        dict({
                            "id": SystemCharts.IO_STATS,
                            "level": DashboardLevel.DB_AGENT,
                            "label": gettext("Storage"),
                            "type": ChartType.LINE,
                            "width": PEMChartWidth.SMALL,
                        }),
                        dict({
                            "id": SystemCharts.HOST_DETAILS,
                            "level": DashboardLevel.DB_AGENT,
                            "label": gettext("Memory"),
                            "type": ChartType.TABLE,
                            "width": PEMChartWidth.FULL,
                        }),
                    ],
                }),
                dict({
                    "type": "section",
                    "id": 3,
                    "label": gettext("Network"),
                    "charts": [
                        dict({
                            "id": SystemCharts.NET_PACKET_STATS,
                            "level": DashboardLevel.DB_AGENT,
                            "label": gettext("Packets"),
                            "type": ChartType.LINE,
                            "width": PEMChartWidth.SMALL,
                        }),
                        dict({
                            "id": SystemCharts.NET_TRAFFIC_STATS,
                            "level": DashboardLevel.DB_AGENT,
                            "label": gettext("Traffic"),
                            "type": ChartType.LINE,
                            "width": PEMChartWidth.SMALL,
                        }),
                        dict({
                            "id": SystemCharts.NET_INTERFACE_DETAILS,
                            "level": DashboardLevel.DB_AGENT,
                            "label": None,
                            "type": ChartType.TEXT,
                            "width": PEMChartWidth.FULL,
                        }),
                    ],
                }),
            ]
        },
        PEMPredefinedDashboards.SERVER: {
            "id": PEMPredefinedDashboards.SERVER,
            "title": gettext("Database Server"),
            "supports_edb_server": True,
            "supports_pg_server": True,
            "url": PEMPredefinedDashboards.SERVER,
            "content": [
                dict({
                    "type": "section",
                    "id": 1,
                    "label": gettext("Storage"),
                    "charts": [
                        dict({
                            "id": SystemCharts.DATABASES_SIZE,
                            "level": DashboardLevel.DB_SERVER,
                            "label": gettext("Database Size"),
                            "type": ChartType.LINE,
                            "align": PEMChartAlign.LEFT,
                            "width": PEMChartWidth.SMALL,
                        }),
                        dict({
                            "id": SystemCharts.TBLSPACES_SIZE,
                            "level": DashboardLevel.DB_SERVER,
                            "label": gettext("Tablespace Size"),
                            "align": PEMChartAlign.LEFT,
                            "type": ChartType.LINE,
                            "width": PEMChartWidth.SMALL,
                        }),
                    ],
                }),
                dict({
                    "type": "section",
                    "id": 2,
                    "label": gettext("Memory"),
                    "charts": [
                        dict({
                            "id": SystemCharts.SHARED_BUFFER,
                            "level": DashboardLevel.DB_SERVER,
                            "label": gettext("Shared Buffers"),
                            "type": ChartType.LINE,
                            "align": PEMChartAlign.LEFT,
                            "width": PEMChartWidth.MEDIUM,
                            "summary": SystemCharts.SHARED_BUFFER_DETAILS,
                        }),
                        dict({
                            "id": SystemCharts.HOST_MEMORY_INFORMATION,
                            "level": DashboardLevel.DB_AGENT,
                            "label": gettext("Host Memory"),
                            "align": PEMChartAlign.LEFT,
                            "type": ChartType.PIE,
                            "width": PEMChartWidth.MICRO,
                            "summary": SystemCharts.HOST_MEMORY_DETAILS,
                        }),
                    ],
                }),
                dict({
                    "type": "section",
                    "id": 3,
                    "label": gettext("Users"),
                    "charts": [
                        dict({
                            "id": SystemCharts.USER_ACTIVITY,
                            "level": DashboardLevel.DB_SERVER,
                            "label": gettext("User Activity"),
                            "type": ChartType.LINE,
                            "align": PEMChartAlign.LEFT,
                            "width": PEMChartWidth.MEDIUM,
                            "summary": SystemCharts.USER_ACTIVITY_DETAILS,
                        }),
                        dict({
                            "id": SystemCharts.CONN_OVERVIEW,
                            "level": DashboardLevel.DB_SERVER,
                            "label": gettext("Connection Overview"),
                            "align": PEMChartAlign.LEFT,
                            "type": ChartType.PIE,
                            "width": PEMChartWidth.MICRO,
                            "summary": SystemCharts.CONN_OVERVIEW_DETAILS,
                        }),
                    ],
                }),
                dict({
                    "type": "section",
                    "id": 4,
                    "label": gettext("I/O"),
                    "charts": [
                        dict({
                            "id": SystemCharts.DISK_INFORMATION,
                            "level": DashboardLevel.DB_AGENT,
                            "label": gettext("Disk"),
                            "type": ChartType.LINE,
                            "align": PEMChartAlign.CENTER,
                            "width": PEMChartWidth.FULL,
                        }),
                        dict({
                            "id": SystemCharts.ROWS_ACTIVITY,
                            "level": DashboardLevel.DB_SERVER,
                            "label": gettext("Row Activity"),
                            "align": PEMChartAlign.LEFT,
                            "type": ChartType.LINE,
                            "width": PEMChartWidth.SMALL,
                        }),
                        dict({
                            "id": SystemCharts.COMMITS_ROLLBACKS,
                            "level": DashboardLevel.DB_SERVER,
                            "label": gettext("Commits/Rollbacks"),
                            "align": PEMChartAlign.LEFT,
                            "type": ChartType.LINE,
                            "width": PEMChartWidth.SMALL,
                        }),
                    ],
                }),
                dict({
                    "type": "section",
                    "id": 4,
                    "label": gettext("Databases"),
                    "charts": [
                        dict({
                            "id": SystemCharts.DATABASES_ANALYSIS,
                            "level": DashboardLevel.DB_SERVER,
                            "label": gettext("Database Analysis"),
                            "type": ChartType.TABLE,
                            "align": PEMChartAlign.CENTER,
                            "width": PEMChartWidth.FULL,
                        }),
                    ],
                }),
            ],
        },
        PEMPredefinedDashboards.MEMORY: {
            "id": PEMPredefinedDashboards.MEMORY,
            "title": gettext("Memory"),
            "supports_edb_server": True,
            "supports_pg_server": True,
            "url": PEMPredefinedDashboards.MEMORY,
            "content": [
                dict({
                    "type": "section",
                    "id": 1,
                    "label": gettext("Database Server"),
                    "charts": [
                        dict({
                            "id": SystemCharts.SE_MEMORY_ACTIVITY,
                            "level": DashboardLevel.DB_SERVER,
                            "label": gettext("Server Memory Activity"),
                            "type": ChartType.LINE,
                            "align": PEMChartAlign.LEFT,
                            "width": PEMChartWidth.MEDIUM,
                            "summary": SystemCharts.SE_MEMORY_ACTIVITY_DETAILS,
                        }),
                        dict({
                            "id": SystemCharts.SE_MEMORY_CONFIGURATION,
                            "level": DashboardLevel.DB_SERVER,
                            "label": gettext("Server Memory Configuration"),
                            "align": PEMChartAlign.LEFT,
                            "type": ChartType.PIE,
                            "width": PEMChartWidth.MICRO,
                        }),
                    ],
                }),
                dict({
                    "type": "section",
                    "id": 2,
                    "label": gettext("Host"),
                    "charts": [
                        dict({
                            "id": SystemCharts.HOST_MEMORY_ACTIVITY,
                            "level": DashboardLevel.DB_AGENT,
                            "label": gettext("Host Memory Activity"),
                            "type": ChartType.LINE,
                            "align": PEMChartAlign.LEFT,
                            "width": PEMChartWidth.MEDIUM,
                        }),
                        dict({
                            "id": SystemCharts.HOST_MEMORY_INFORMATION,
                            "level": DashboardLevel.DB_SERVER,
                            "label": gettext("Host Memory Configuration"),
                            "align": PEMChartAlign.LEFT,
                            "type": ChartType.PIE,
                            "width": PEMChartWidth.MICRO,
                            "summary": SystemCharts.HOST_MEMORY_DETAILS,
                        }),
                    ],
                }),
            ],
        },
        PEMPredefinedDashboards.SESSION_ACTIVITY: {
            "id": PEMPredefinedDashboards.SESSION_ACTIVITY,
            "title": gettext("Session Activity"),
            "supports_edb_server": True,
            "supports_pg_server": True,
            "url": PEMPredefinedDashboards.SESSION_ACTIVITY,
            "content": [
                dict({
                    "type": "section",
                    "id": 1,
                    "label": gettext("Session Activity"),
                    "charts": [
                        dict({
                            "id": SystemCharts.SESSION_WORK_LOAD,
                            "level": DashboardLevel.DB_SERVER,
                            "label": gettext("Session Workload"),
                            "type": ChartType.TABLE,
                            "align": PEMChartAlign.CENTER,
                            "width": PEMChartWidth.FULL,
                        }),
                        dict({
                            "id": SystemCharts.SESSION_LOCKS_ACTIVITY,
                            "level": DashboardLevel.DB_SERVER,
                            "label": gettext("Session Lock Activity"),
                            "type": ChartType.TABLE,
                            "align": PEMChartAlign.CENTER,
                            "width": PEMChartWidth.FULL,
                        }),
                    ],
                }),
            ]
        },
        PEMPredefinedDashboards.STORAGE: {
            "id": PEMPredefinedDashboards.STORAGE,
            "title": gettext("Storage"),
            "supports_edb_server": True,
            "supports_pg_server": True,
            "url": PEMPredefinedDashboards.STORAGE,
            "content": [
                dict({
                    "type": "section",
                    "id": 1,
                    "label": gettext("Storage Overview"),
                    "charts": [
                        dict({
                            "id": SystemCharts.DATABASES_STRG_OVERVIEW,
                            "level": DashboardLevel.DB_SERVER,
                            "label": gettext("Database Overview"),
                            "type": ChartType.PIE,
                            "align": PEMChartAlign.LEFT,
                            "width": PEMChartWidth.MICRO,
                        }),
                        dict({
                            "id": SystemCharts.TBLSPACES_STRG_OVERVIEW,
                            "level": DashboardLevel.DB_SERVER,
                            "label": gettext("Tablespace Overview"),
                            "type": ChartType.PIE,
                            "align": PEMChartAlign.LEFT,
                            "width": PEMChartWidth.MICRO,
                        }),
                        dict({
                            "id": SystemCharts.HOST_STRG_OVERVIEW,
                            "level": DashboardLevel.DB_AGENT,
                            "label": gettext("Host Overview"),
                            "type": ChartType.PIE,
                            "align": PEMChartAlign.LEFT,
                            "width": PEMChartWidth.MICRO,
                        }),
                    ],
                }),
                dict({
                    "type": "section",
                    "id": 2,
                    "label": gettext("Database Details"),
                    "charts": [
                        dict({
                            "id": SystemCharts.DATABASES_STRG_DETAILS_TBL,
                            "level": DashboardLevel.DB_SERVER,
                            "label": gettext("Database"),
                            "type": ChartType.TABLE,
                            "align": PEMChartAlign.CENTER,
                            "width": PEMChartWidth.SMALL,
                        }),
                    ],
                }),
                dict({
                    "type": "section",
                    "id": 2,
                    "label": gettext("Tablespace Details"),
                    "charts": [
                        dict({
                            "id": SystemCharts.TBLSPACES_STRG_DETAILS_TBL,
                            "level": DashboardLevel.DB_SERVER,
                            "label": gettext("Tablespace"),
                            "type": ChartType.TABLE,
                            "align": PEMChartAlign.CENTER,
                            "width": PEMChartWidth.SMALL,
                        }),
                    ],
                }),
                dict({
                    "type": "section",
                    "id": 2,
                    "label": gettext("Host File System Details"),
                    "charts": [
                        dict({
                            "id": SystemCharts.HOST_STRG_DETAILS_TBL,
                            "level": DashboardLevel.DB_SERVER,
                            "label": gettext("Host File System"),
                            "type": ChartType.TABLE,
                            "align": PEMChartAlign.LEFT,
                            "width": PEMChartWidth.FULL,
                        }),
                    ],
                }),
            ],
        },
        PEMPredefinedDashboards.SYSTEM_WAIT: {
            "id": PEMPredefinedDashboards.SYSTEM_WAIT,
            "title": gettext("System Wait"),
            "supports_edb_server": True,
            "supports_pg_server": False,
            "url": PEMPredefinedDashboards.SYSTEM_WAIT,
            "content": [
                dict({
                    "type": "section",
                    "id": 1,
                    "label": gettext("System Waits Overview"),
                    "charts": [
                        dict({
                            "id": SystemCharts.NUM_SYS_WAITS,
                            "level": DashboardLevel.DB_SERVER,
                            "label":
                                gettext("System Waits By Number Of Waits"),
                            "type": ChartType.PIE,
                            "align": PEMChartAlign.LEFT,
                            "width": PEMChartWidth.SMALL,
                        }),
                        dict({
                            "id": SystemCharts.SYS_WAIT_TIME,
                            "level": DashboardLevel.DB_SERVER,
                            "label": gettext("System Waits By Time Waited"),
                            "type": ChartType.PIE,
                            "align": PEMChartAlign.LEFT,
                            "width": PEMChartWidth.SMALL,
                        }),
                        dict({
                            "id": SystemCharts.SYS_WAIT_DETAILS_TBL,
                            "level": DashboardLevel.DB_SERVER,
                            "label": gettext("System Wait Details"),
                            "type": ChartType.TABLE,
                            "align": PEMChartAlign.CENTER,
                            "width": PEMChartWidth.MEDIUM,
                        }),
                    ],
                }),
            ],
        },
        PEMPredefinedDashboards.DATABASE: {
            "id": PEMPredefinedDashboards.DATABASE,
            "title": gettext("Database"),
            "supports_edb_server": True,
            "supports_pg_server": True,
            "url": PEMPredefinedDashboards.DATABASE,
            "content": [
                dict({
                    "type": "section",
                    "id": 1,
                    "label": gettext("Storage"),
                    "charts": [
                        dict({
                            "id": SystemCharts.DB_STRG,
                            "level": DashboardLevel.DB_DATABASE,
                            "label": gettext("Object Size"),
                            "type": ChartType.BAR,
                            "align": PEMChartAlign.CENTER,
                            "width": PEMChartWidth.MEDIUM,
                            "summary": SystemCharts.DB_STRG_DETAILS,
                        }),
                    ],
                }),
                dict({
                    "type": "section",
                    "id": 2,
                    "label": gettext("Users"),
                    "charts": [
                        dict({
                            "id": SystemCharts.DB_USER_ACTIVITY,
                            "level": DashboardLevel.DB_DATABASE,
                            "label": gettext("Object Size"),
                            "type": ChartType.LINE,
                            "align": PEMChartAlign.LEFT,
                            "width": PEMChartWidth.MEDIUM,
                        }),
                        dict({
                            "id": SystemCharts.DB_CONN_OVERVIEW,
                            "level": DashboardLevel.DB_DATABASE,
                            "label": gettext("Connection Overview"),
                            "type": ChartType.PIE,
                            "align": PEMChartAlign.LEFT,
                            "width": PEMChartWidth.MICRO,
                        }),
                    ],
                }),
                dict({
                    "type": "section",
                    "id": 3,
                    "label": gettext("I/O"),
                    "charts": [
                        dict({
                            "id": SystemCharts.DB_IO_HIT_READ_STATS,
                            "level": DashboardLevel.DB_DATABASE,
                            "label": gettext("Database I/O"),
                            "type": ChartType.LINE,
                            "align": PEMChartAlign.LEFT,
                            "width": PEMChartWidth.FULL,
                        }),
                        dict({
                            "id": SystemCharts.ROWS_ACTIVITY,
                            "level": DashboardLevel.DB_DATABASE,
                            "label": gettext("Row Activity"),
                            "type": ChartType.LINE,
                            "align": PEMChartAlign.LEFT,
                            "width": PEMChartWidth.SMALL,
                        }),
                        dict({
                            "id": SystemCharts.COMMITS_ROLLBACKS,
                            "level": DashboardLevel.DB_DATABASE,
                            "label": gettext("Commits/Rollbacks"),
                            "type": ChartType.LINE,
                            "align": PEMChartAlign.LEFT,
                            "width": PEMChartWidth.SMALL,
                        }),
                        dict({
                            "id": SystemCharts.DB_TOP_TABLES,
                            "level": DashboardLevel.DB_DATABASE,
                            "label": gettext("Top Tables"),
                            "type": ChartType.TABLE,
                            "align": PEMChartAlign.CENTER,
                            "width": PEMChartWidth.FULL,
                        }),
                    ],
                }),
            ],
        },
        PEMPredefinedDashboards.IO: {
            "id": PEMPredefinedDashboards.IO,
            "title": gettext("I/O"),
            "supports_edb_server": True,
            "supports_pg_server": True,
            "url": PEMPredefinedDashboards.IO,
            "content": [
                dict({
                    "type": "section",
                    "id": 1,
                    "label": gettext("I/O Overview"),
                    "charts": [
                        dict({
                            "id": SystemCharts.DB_IO_HIT_READ_STATS,
                            "level": DashboardLevel.DB_DATABASE,
                            "label": gettext("Database I/O"),
                            "type": ChartType.LINE,
                            "align": PEMChartAlign.LEFT,
                            "width": PEMChartWidth.FULL,
                        }),
                        dict({
                            "id": SystemCharts.ROWS_ACTIVITY,
                            "level": DashboardLevel.DB_DATABASE,
                            "label": gettext("Row Activity"),
                            "type": ChartType.LINE,
                            "align": PEMChartAlign.LEFT,
                            "width": PEMChartWidth.SMALL,
                        }),
                        dict({
                            "id": SystemCharts.COMMITS_ROLLBACKS,
                            "level": DashboardLevel.DB_DATABASE,
                            "label": gettext("Commits/Rollbacks"),
                            "type": ChartType.LINE,
                            "align": PEMChartAlign.LEFT,
                            "width": PEMChartWidth.SMALL,
                        }),
                    ],
                }),
                dict({
                    "type": "section",
                    "id": 2,
                    "label": gettext("Top Tables/Indexes"),
                    "charts": [
                        dict({
                            "id": SystemCharts.IO_TOP5_SCANNED_TABLES,
                            "level": DashboardLevel.DB_DATABASE,
                            "label": gettext("Top Tables"),
                            "type": ChartType.BAR,
                            "align": PEMChartAlign.LEFT,
                            "width": PEMChartWidth.SMALL,
                        }),
                        dict({
                            "id": SystemCharts.IO_TOP5_SCANNED_INDEXES,
                            "level": DashboardLevel.DB_DATABASE,
                            "label": gettext("Top Indexes"),
                            "type": ChartType.BAR,
                            "align": PEMChartAlign.LEFT,
                            "width": PEMChartWidth.SMALL,
                        }),
                    ],
                }),
                dict({
                    "type": "section",
                    "id": 2,
                    "label": gettext("Object I/O Details"),
                    "charts": [
                        dict({
                            "id": SystemCharts.OBJECT_ACTIVITIES,
                            "level": DashboardLevel.DB_DATABASE,
                            "label": gettext("Table Activity"),
                            "type": ChartType.TABLE,
                            "align": PEMChartAlign.LEFT,
                            "width": PEMChartWidth.FULL,
                        }),
                        dict({
                            "id": SystemCharts.TOP_20_INDEX_ACTIVITY,
                            "level": DashboardLevel.DB_DATABASE,
                            "label": gettext("Index Activity"),
                            "type": ChartType.TABLE,
                            "align": PEMChartAlign.LEFT,
                            "width": PEMChartWidth.FULL,
                        }),
                    ],
                }),
            ],
        },
        PEMPredefinedDashboards.OBJ_ACTIVITY: {
            "id": PEMPredefinedDashboards.OBJ_ACTIVITY,
            "title": gettext("Objects Activity"),
            "supports_edb_server": True,
            "supports_pg_server": True,
            "url": PEMPredefinedDashboards.OBJ_ACTIVITY,
            "content": [
                dict({
                    "type": "section",
                    "id": 1,
                    "label": gettext("Size Overview"),
                    "charts": [
                        dict({
                            "id": SystemCharts.TOP_5_LARGEST_TABLES,
                            "level": DashboardLevel.DB_DATABASE,
                            "label": gettext("Largest Tables"),
                            "type": ChartType.BAR,
                            "align": PEMChartAlign.LEFT,
                            "width": PEMChartWidth.SMALL,
                        }),
                        dict({
                            "id": SystemCharts.TOP_5_LARGEST_INDEXES,
                            "level": DashboardLevel.DB_DATABASE,
                            "label": gettext("Largest Indexes"),
                            "type": ChartType.BAR,
                            "align": PEMChartAlign.LEFT,
                            "width": PEMChartWidth.SMALL,
                        }),
                        dict({
                            "id": SystemCharts.OBJECT_ACTIVITIES,
                            "level": DashboardLevel.DB_DATABASE,
                            "label": gettext("Objects Activity"),
                            "type": ChartType.TABLE,
                            "align": PEMChartAlign.CENTER,
                            "width": PEMChartWidth.FULL,
                        }),
                        dict({
                            "id": SystemCharts.OBJECT_STRG,
                            "level": DashboardLevel.DB_DATABASE,
                            "label": gettext("Objects Storage"),
                            "type": ChartType.TABLE,
                            "align": PEMChartAlign.CENTER,
                            "width": PEMChartWidth.FULL,
                        }),
                    ],
                }),
            ],
        },
        PEMPredefinedDashboards.SESSION_WAITS: {
            "id": PEMPredefinedDashboards.SESSION_WAITS,
            "title": gettext("Session Wait"),
            "supports_edb_server": True,
            "supports_pg_server": False,
            "url": PEMPredefinedDashboards.SESSION_WAITS,
            "content": [
                dict({
                    "type": "section",
                    "id": 1,
                    "label": gettext("Session Waits Overview"),
                    "charts": [
                        dict({
                            "id": SystemCharts.NUM_SESSION_WAITS,
                            "level": DashboardLevel.DB_DATABASE,
                            "label":
                                gettext("Session Waits By Number Of Waits"),
                            "type": ChartType.PIE,
                            "align": PEMChartAlign.LEFT,
                            "width": PEMChartWidth.SMALL,
                        }),
                        dict({
                            "id": SystemCharts.SESSOIN_TIME_WAITS,
                            "level": DashboardLevel.DB_DATABASE,
                            "label":
                                gettext("Session Time Waits By Time Waited"),
                            "type": ChartType.PIE,
                            "align": PEMChartAlign.LEFT,
                            "width": PEMChartWidth.SMALL,
                        }),
                        dict({
                            "id": SystemCharts.SESSION_WAIT_DETAILS,
                            "level": DashboardLevel.DB_DATABASE,
                            "label": gettext("Session Wait Details"),
                            "type": ChartType.TABLE,
                            "align": PEMChartAlign.LEFT,
                            "width": PEMChartWidth.FULL,
                        }),
                    ],
                }),
            ],
        },
        PEMPredefinedDashboards.STREAMING_REPLICATION: {
            "id": PEMPredefinedDashboards.STREAMING_REPLICATION,
            "title": gettext("Streaming Replication"),
            "supports_edb_server": True,
            "supports_pg_server": True,
            "url": PEMPredefinedDashboards.STREAMING_REPLICATION,
            "content": [
                dict({
                    "type": "section",
                    "id": 1,
                    "label": gettext("WAL Status"),
                    "any": ["wal_archive", "streaming_replication"],
                    "charts": [
                        dict({
                            "id": SystemCharts.WAL_ARCHIVE_STATUS,
                            "level": DashboardLevel.DB_SERVER,
                            "label": gettext("WAL Archive Status"),
                            "type": ChartType.LINE,
                            "align": PEMChartAlign.CENTER,
                            "width": PEMChartWidth.FULL,
                            "required": {
                                "locally_monitored": gettext(
                                    "Information not available for the"
                                    " remotely monitored server."
                                ),
                                "wal_archive": gettext(
                                    "'WAL Archive Status' probe is"
                                    " disabled or no data is available."
                                ),
                            },
                        }),
                        dict({
                            "id": SystemCharts.WAL_SEGMENT_LAG,
                            "level": DashboardLevel.DB_SERVER,
                            "label": gettext("WAL Segment Lag"),
                            "type": ChartType.LINE,
                            "align": PEMChartAlign.LEFT,
                            "width": PEMChartWidth.SMALL,
                            "required": {
                                "streaming_replication": gettext(
                                    "'Streaming Replication' probe is"
                                    " disabled or no data is available."
                                ),
                            },
                        }),
                        dict({
                            "id": SystemCharts.WAL_PAGE_LAG,
                            "level": DashboardLevel.DB_SERVER,
                            "label": gettext("WAL Page Lag"),
                            "type": ChartType.LINE,
                            "align": PEMChartAlign.LEFT,
                            "width": PEMChartWidth.SMALL,
                            "required": {
                                "streaming_replication": gettext(
                                    "'Streaming Replication' probe is"
                                    " disabled or no data is available."
                                ),
                            },
                        }),
                    ],
                }),
                dict({
                    "type": "section",
                    "id": 1,
                    "label": gettext("Replication Status"),
                    "any": ["streaming_replication_lag_time"],
                    "charts": [
                        dict({
                            "id": SystemCharts.REPLICATION_TIME_LAG,
                            "level": DashboardLevel.DB_SERVER,
                            "label": gettext("Replication Time Lag"),
                            "type": ChartType.LINE,
                            "align": PEMChartAlign.CENTER,
                            "width": PEMChartWidth.FULL,
                            "summary":
                                SystemCharts.REPLICATION_TIME_LAG_DETAILS,
                        }),
                    ],
                }),
                dict({
                    "type": "section",
                    "id": 1,
                    "label": gettext("Failover Manager Cluster Status"),
                    "any": ["efm_cluster_node_status", "efm_cluster_info"],
                    "charts": [
                        dict({
                            "id": SystemCharts.EFM_CLUSTER_INFO,
                            "level": DashboardLevel.DB_SERVER,
                            "label": gettext(
                                "Failover Manager Cluster Information"
                            ),
                            "type": ChartType.TABLE,
                            "align": PEMChartAlign.CENTER,
                            "width": PEMChartWidth.MEDIUM,
                            "required": dict({
                                "efm_cluster_info": gettext(
                                    "'EFM Cluster Info' probe is"
                                    " disabled or no data is available."
                                ),
                            }),
                        }),
                        dict({
                            "id": SystemCharts.EFM_CLUSTER_NODE_STATUS,
                            "level": DashboardLevel.DB_SERVER,
                            "label": gettext("Failover Manager Node Status"),
                            "type": ChartType.TABLE,
                            "align": PEMChartAlign.CENTER,
                            "width": PEMChartWidth.FULL,
                            "required": dict({
                                "efm_cluster_node_status": gettext(
                                    "'EFM Node Status' probe is"
                                    " disabled or no data is available."
                                ),
                            }),
                        }),
                    ],
                }),
                dict({
                    "type": "section",
                    "id": 1,
                    "label": gettext("Patroni Cluster Status"),
                    "any": ["patroni_node_status",
                            "patroni_cluster_status"],
                    "charts": [
                        dict({
                            "id": SystemCharts.PATRONI_CLUSTER_INFO,
                            "level": DashboardLevel.DB_SERVER,
                            "label": gettext(
                                "Patroni Cluster Information"
                            ),
                            "type": ChartType.TABLE,
                            "align": PEMChartAlign.CENTER,
                            "width": PEMChartWidth.MEDIUM,
                            "required": dict({
                                "patroni_cluster_status": gettext(
                                    "'Patroni Cluster Status' probe is"
                                    " disabled or no data is available."
                                ),
                            }),
                        }),
                        dict({
                            "id": SystemCharts.PATRONI_CLUSTER_NODE_STATUS,
                            "level": DashboardLevel.DB_SERVER,
                            "label": gettext("Patroni Node Status"),
                            "type": ChartType.TABLE,
                            "align": PEMChartAlign.CENTER,
                            "width": PEMChartWidth.FULL,
                            "required": dict({
                                "patroni_node_status": gettext(
                                    "'Patroni Node Status' probe is"
                                    " disabled or no data is available."
                                ),
                            }),
                        }),
                    ],
                })
            ]
        },

        PEMPredefinedDashboards.BDR_NODE_MONITORING: {
            "id": PEMPredefinedDashboards.BDR_NODE_MONITORING,
            "title": gettext("PGD Node Monitoring"),
            "supports_edb_server": True,
            "supports_pg_server": True,
            "url": PEMPredefinedDashboards.BDR_NODE_MONITORING,
            "content": [
                dict({
                    "type": "section",
                    "id": 1,
                    "label": gettext("EDB Postgres Distributed Node Slots"),
                    "charts": [
                        dict({
                            "id": SystemCharts.BDR_NODE_SLOT_REPLAY_LAG_BYTES,
                            "level": DashboardLevel.DB_DATABASE,
                            "label": gettext(
                                "PGD Node Slots Replay Lag (Bytes)"),
                            "type": ChartType.LINE,
                            "width": PEMChartWidth.SMALL,
                        }),
                        dict({
                            "id":
                                SystemCharts.BDR_NODE_SLOT_REPLAY_LAG_SECONDS,
                            "level": DashboardLevel.DB_DATABASE,
                            "label": gettext(
                                "PGD Node Slots Replay Lag (Seconds)"),
                            "type": ChartType.LINE,
                            "width": PEMChartWidth.SMALL,
                        }),
                    ],
                }),
                dict({
                    "type": "section",
                    "id": 2,
                    "label": gettext("EDB Postgres Distributed Conflict"
                                     " History Summary"),
                    "charts": [
                        dict({
                            "id": SystemCharts.BDR_CONFLICT_HISTORY_SUMMARY,
                            "level": DashboardLevel.DB_DATABASE,
                            "label": gettext("PGD Conflict History Summary"),
                            "type": ChartType.LINE,
                            "align": PEMChartAlign.LEFT,
                            "width": PEMChartWidth.FULL,
                        }),
                    ],
                }),
                dict({
                    "type": "section",
                    "id": 3,

                    "label": gettext("EDB Postgres Distributed Node"
                                     " Replication"),
                    "charts": [
                        dict({
                            "id":
                                SystemCharts.BDR_ND_REP_RATES_REPLAY_LAG_BYTE,
                            "level": DashboardLevel.DB_DATABASE,
                            "label": gettext(
                                "PGD Node Replication Replay Lag (Bytes)"),
                            "type": ChartType.LINE,
                            "width": PEMChartWidth.SMALL,
                        }),
                        dict({
                            "id":
                                SystemCharts.BDR_ND_REP_RATES_REPLAY_LAG_SEC,
                            "level": DashboardLevel.DB_DATABASE,
                            "label": gettext(
                                "PGD Node Replication Replay Lag (Seconds)"),
                            "type": ChartType.LINE,
                            "width": PEMChartWidth.SMALL,
                        }),
                        dict({
                            "id": SystemCharts.BDR_ND_REP_RATES_APPLY_RATE,
                            "level": DashboardLevel.DB_DATABASE,
                            "label": gettext(
                                "PGD Node Replication Apply Rates"),
                            "type": ChartType.LINE,
                            "width": PEMChartWidth.FULL,
                        }),
                    ],
                }),
                dict({
                    "type": "section",
                    "id": 4,
                    "label": gettext("EDB Postgres Distributed Statistics"),
                    "charts": [
                        dict({
                            "id": SystemCharts.BDR_STAT_RELATIONS,
                            "level": DashboardLevel.DB_DATABASE,
                            "label": gettext("PGD Relation Statistics"),
                            "type": ChartType.TABLE,
                            "width": PEMChartWidth.FULL,
                        }),
                        dict({
                            "id": SystemCharts.BDR_STAT_SUBSCRIPTIONS,
                            "level": DashboardLevel.DB_DATABASE,
                            "label": gettext("PGD Subscription Statistics"),
                            "type": ChartType.TABLE,
                            "width": PEMChartWidth.FULL,
                        }),
                    ],
                }),
            ],
        },
        PEMPredefinedDashboards.BDR_GROUP_MONITORING: {
            "id": PEMPredefinedDashboards.BDR_GROUP_MONITORING,
            "title": gettext("PGD Group Monitoring"),
            "supports_edb_server": True,
            "supports_pg_server": True,
            "url": PEMPredefinedDashboards.BDR_GROUP_MONITORING,
            "content": [
                dict({
                    "type": "section",
                    "id": 1,
                    "label": gettext("EDB Postgres Distributed Group"
                                     " Subscription Summary"),

                    "charts": [
                        dict({
                            "id": SystemCharts.BDR_GP_SUB_SUMMARY_SUB_LAG_SEC,
                            "level": DashboardLevel.DB_DATABASE,
                            "label": gettext("PGD Group Subscription Lag"),
                            "type": ChartType.LINE,
                            "width": PEMChartWidth.FULL,
                        }),
                    ],
                }),
                dict({
                    "type": "section",
                    "id": 2,
                    "label": gettext("EDB Postgres Distributed Group"
                                     " Replication Slots Details"),

                    "charts": [
                        dict({
                            "id":
                                SystemCharts.BDR_GP_REP_SL_REPLAY_LAG,
                            "level": DashboardLevel.DB_DATABASE,
                            "label": gettext(
                                "PGD Group Replication Slots Replay Lag "
                                "(Bytes)"),
                            "type": ChartType.LINE,
                            "width": PEMChartWidth.SMALL,
                        }),
                        dict({
                            "id":
                                SystemCharts.BDR_GP_REP_SL_REPLAY_LAG_SEC,
                            "level": DashboardLevel.DB_DATABASE,
                            "label": gettext(
                                "PGD Group Replication Slots Replay "
                                "Lag (Seconds)"),
                            "type": ChartType.LINE,
                            "width": PEMChartWidth.SMALL,
                        }),
                        dict({
                            "id":
                                SystemCharts.BDR_GP_REP_SL_FLUSH_LAG,
                            "level": DashboardLevel.DB_DATABASE,
                            "label": gettext(
                                "PGD Group Replication Slots Flush Lag"
                                " (Bytes)"),
                            "type": ChartType.LINE,
                            "width": PEMChartWidth.SMALL,
                        }),
                        dict({
                            "id":
                                SystemCharts.BDR_GP_REP_SL_FLUSH_LAG_SEC,
                            "level": DashboardLevel.DB_DATABASE,
                            "label": gettext(
                                "PGD Group Replication Slots Flush Lag"
                                " (Seconds)"),
                            "type": ChartType.LINE,
                            "width": PEMChartWidth.SMALL,
                        }),
                        dict({
                            "id":
                                SystemCharts.BDR_GP_REP_SL_WRITE_LAG,
                            "level": DashboardLevel.DB_DATABASE,
                            "label": gettext(
                                "PGD Group Replication Slots Write Lag"
                                " (Bytes)"),
                            "type": ChartType.LINE,
                            "width": PEMChartWidth.SMALL,
                        }),
                        dict({
                            "id":
                                SystemCharts.BDR_GP_REP_SL_WRITE_LAG_SEC,
                            "level": DashboardLevel.DB_DATABASE,
                            "label": gettext(
                                "PGD Group Replication Slots Write Lag"
                                " (Seconds)"),
                            "type": ChartType.LINE,
                            "width": PEMChartWidth.SMALL,
                        }),
                        dict({
                            "id":
                                SystemCharts.BDR_GP_REP_SL_SENT_LAG,
                            "level": DashboardLevel.DB_DATABASE,
                            "label": gettext(
                                "PGD Group Replication Slots Sent Lag"
                                " (Bytes)"),
                            "type": ChartType.LINE,
                            "width": PEMChartWidth.FULL,
                        }),
                    ],
                }),
            ]
        },
        PEMPredefinedDashboards.BDR_ADMIN: {
            "id": PEMPredefinedDashboards.BDR_ADMIN,
            "title": gettext("PGD Admin"),
            "supports_edb_server": True,
            "supports_pg_server": True,
            "url": PEMPredefinedDashboards.BDR_ADMIN,
            "content": [
                dict({
                    "type": "section",
                    "id": 1,
                    "label": gettext("Node Summary"),
                    "charts": [
                        dict({
                            "id": SystemCharts.BDR_NODE_SUMMARY,
                            "level": DashboardLevel.DB_DATABASE,
                            "label": gettext("Node Summary"),
                            "type": ChartType.TABLE,
                            "align": PEMChartAlign.LEFT,
                            "width": PEMChartWidth.FULL,
                        }),
                    ],
                }),
                dict({
                    "type": "section",
                    "id": 2,
                    "label": gettext("Global Locks"),
                    "charts": [
                        dict({
                            "id": SystemCharts.BDR_GLOBAL_LOCKS,
                            "level": DashboardLevel.DB_DATABASE,
                            "label": gettext("Global Locks"),
                            "type": ChartType.TABLE,
                            "align": PEMChartAlign.LEFT,
                            "width": PEMChartWidth.FULL,
                        }),
                    ],
                }),
                dict({
                    "type": "section",
                    "id": 3,
                    "label": gettext("EDB Postgres Distributed Group"
                                     " Version Details"),

                    "charts": [
                        dict({
                            "id":
                                SystemCharts.BDR_GROUP_VERSION_DETAILS,
                            "level": DashboardLevel.DB_DATABASE,
                            "label": gettext("PGD Group Version Details"),
                            "type": ChartType.TABLE,
                            "width": PEMChartWidth.FULL,
                        }),
                    ],
                }),
                dict({
                    "type": "section",
                    "id": 4,
                    "label": gettext("EDB Postgres Distributed Workers"),
                    "charts": [
                        dict({
                            "id":
                                SystemCharts.BDR_WORKERS,
                            "level": DashboardLevel.DB_DATABASE,
                            "label": gettext("PGD Workers"),
                            "type": ChartType.PGD_WORKERS,
                            "width": PEMChartWidth.FULL,
                        }),
                    ],
                }),
                dict({
                    "type": "section",
                    "id": 5,
                    "label": gettext("EDB Postgres Distributed Group"
                                     " Camo Details"),

                    "charts": [
                        dict({
                            "id":
                                SystemCharts.BDR_GROUP_CAMO_DETAILS,
                            "level": DashboardLevel.DB_DATABASE,
                            "label": gettext("PGD Group Camo Details"),
                            "type": ChartType.TABLE,
                            "width": PEMChartWidth.FULL,
                        }),
                    ],
                }),
                dict({
                    "type": "section",
                    "id": 6,
                    "label": gettext("EDB Postgres Distributed Group"
                                     " Raft Details"),

                    "charts": [
                        dict({
                            "id":
                                SystemCharts.BDR_GROUP_RAFT_DETAILS,
                            "level": DashboardLevel.DB_DATABASE,
                            "label": gettext("PGD Group Raft Details"),
                            "type": ChartType.TABLE,
                            "width": PEMChartWidth.FULL,
                        }),
                    ],
                }),
            ],
        },
    }
    sys_dashboards = {
        DashboardLevel.DB_GLOBAL: {
            PEMPredefinedDashboards.GLOBAL_OVERVIEW,
            PEMPredefinedDashboards.ALERTS,
            PEMPredefinedDashboards.AUDIT_LOGS,
            PEMPredefinedDashboards.SERVER_LOGS
        },
        DashboardLevel.DB_AGENT: {
            PEMPredefinedDashboards.ALERTS,
            PEMPredefinedDashboards.AUDIT_LOGS,
            PEMPredefinedDashboards.OS,
            PEMPredefinedDashboards.PROBE_LOGS,
            PEMPredefinedDashboards.SERVER_LOGS
        },
        DashboardLevel.DB_SERVER: {
            PEMPredefinedDashboards.ALERTS,
            PEMPredefinedDashboards.AUDIT_LOGS,
            PEMPredefinedDashboards.SERVER,
            PEMPredefinedDashboards.SERVER_LOGS,
            PEMPredefinedDashboards.MEMORY,
            PEMPredefinedDashboards.SESSION_ACTIVITY,
            PEMPredefinedDashboards.STORAGE,
            PEMPredefinedDashboards.SYSTEM_WAIT,
            PEMPredefinedDashboards.STREAMING_REPLICATION,
        },
        DashboardLevel.DB_DATABASE: {
            PEMPredefinedDashboards.ALERTS,
            PEMPredefinedDashboards.DATABASE,
            PEMPredefinedDashboards.IO,
            PEMPredefinedDashboards.OBJ_ACTIVITY,
            PEMPredefinedDashboards.SESSION_WAITS,
            PEMPredefinedDashboards.BDR_NODE_MONITORING,
            PEMPredefinedDashboards.BDR_GROUP_MONITORING,
            PEMPredefinedDashboards.BDR_ADMIN

        }
    }

    def getDashboard(self, did):
        if did == PEMPredefinedDashboards.GLOBAL_OVERVIEW:
            return gettext("Global Overview")
        elif did == PEMPredefinedDashboards.ALERTS:
            return gettext("Alerts")
        elif did == PEMPredefinedDashboards.AUDIT_LOGS:
            return gettext("Audit Log")
        elif did == PEMPredefinedDashboards.PROBE_LOGS:
            return gettext("Probe Log")
        elif did == PEMPredefinedDashboards.SERVER_LOGS:
            return gettext("Server Log")
        elif did == PEMPredefinedDashboards.OS:
            return gettext("Operating System")
        elif did == PEMPredefinedDashboards.SERVER:
            return gettext("Database Server")
        elif did == PEMPredefinedDashboards.MEMORY:
            return gettext("Memory")
        elif did == PEMPredefinedDashboards.SESSION_ACTIVITY:
            return gettext("Session Activity")
        elif did == PEMPredefinedDashboards.STORAGE:
            return gettext("Storage")
        elif did == PEMPredefinedDashboards.SYSTEM_WAIT:
            return gettext("System Wait")
        elif did == PEMPredefinedDashboards.DATABASE:
            return gettext("Database")
        elif did == PEMPredefinedDashboards.IO:
            return gettext("I/O")
        elif did == PEMPredefinedDashboards.OBJ_ACTIVITY:
            return gettext("Objects Activity")
        elif did == PEMPredefinedDashboards.SESSION_WAITS:
            return gettext("Session Wait")
        elif did == PEMPredefinedDashboards.STREAMING_REPLICATION:
            return gettext("Streaming Replication")
        elif did == PEMPredefinedDashboards.BDR_NODE_MONITORING:
            return gettext("BDR Node Monitoring")
        elif did == PEMPredefinedDashboards.BDR_GROUP_MONITORING:
            return gettext("BDR Group Monitoring")
        elif did == PEMPredefinedDashboards.ADMIN:
            return gettext("BDR Admin")
        return None

    def getDashboardObject(self, d):
        if d in self.dashboards:
            return self.dashboards[d]
        return None

    def getSysDashboards(self, level, is_edb, sid=None, pem_conn=None):
        server_version = None
        if sid != '' and sid is not None:
            params = [sid]  # Use sid instead of id
            status, server_version = pem_conn.execute_scalar(
                "SELECT server_version_id FROM pemdata.server_info "
                "WHERE server_id = (%s)::int4", params
            )

            if not status:
                error_return(
                    gettext(
                        "Error executing query: {0}".format(server_version)),
                    e_type=PEMErrorType.JSON
                )

        d = dict()
        res = dict()

        if level in self.sys_dashboards:
            d = self.sys_dashboards[level]

        for v in d:
            dashboard = self.dashboards[v]
            supports_edb = dashboard['supports_edb_server']
            supports_pg = dashboard['supports_pg_server']

            # Special case for System Wait and Session Wait dashboards
            if ((v == PEMPredefinedDashboards.SYSTEM_WAIT or
                v == PEMPredefinedDashboards.SESSION_WAITS) and
                    is_edb and server_version):
                # Hide these dashboards for EDB servers version 18 and above
                if server_version >= 21800:
                    continue
            if is_edb is None or \
                    (is_edb is True and supports_edb) or \
                    (is_edb is False and supports_pg):
                res[v] = dashboard

        return res

    @classmethod
    def getSystemDashboard(cls, level, did):
        sys_dashboards = cls.sys_dashboards.get(level, None)
        if not sys_dashboards:
            return None
        if did in sys_dashboards:
            return cls.dashboards[did]
        return None


# To Do Need to review
def include_javascript(js_file, embed=False, relative=True):
    """Includes a javascript in the given HTML document
        xml     - document object
        js_file - javascript file to be included
        embed   - check if you want to embed or include"""

    if relative:
        path = os.path.dirname(os.path.realpath(__file__))
        js_file_name = path + "/../static/js/" + js_file
    else:
        js_file_name = js_file

    jsfile = ''
    if embed and embed is True:
        if js_file != '' and os.path.isfile(js_file_name):
            try:
                handle = codecs.open(js_file_name, "r", "utf-8")
                contents = handle.read()
                handle.close()

                jsfile = Element('script', attrib={'type': 'text/javascript'})
                cdata = CDATA(contents)
                jsfile.append(cdata)

                # End script
            except IOError:
                jsfile = ''
    else:
        jsfile = Element(
            'script', attrib={
                'type': 'text/javascript',
                'src': url_for(
                    'pem.static', filename='js/' + js_file
                ) if relative else js_file
            })
        jsfile.text = ' '

    return jsfile


def include_css_file(css_file, embed=False,
                     attribute_list=dict(), relative=True):
    """# Includes a css file in the given HTML document
    xml        - document object
    css_file   - javascript file to be included
    embed      - check if you want to embed or include
    attributes - any other attributes to be added to link/style tag."""

    xml_ret = ''
    if relative:
        path = os.path.dirname(os.path.realpath(__file__))
        css_file_name = path + "/../static/css/" + css_file
    else:
        css_file_name = css_file

    # To Do if (css_file and os.path.isfile(os.path.join(path, css_file))):
    if embed and embed is True:
        if css_file != '' and os.path.isfile(css_file_name):
            try:
                handle = open(css_file_name, "r")
                contents = handle.read()
                handle.close()

                css = Element('style', attrib={'type': 'text/css'})
                if attribute_list and len(attribute_list) > 0:
                    for attr in attribute_list:
                        css.attrib[attr] = attribute_list[attr]

                css.text = contents
                xml_ret = css
            except IOError:
                xml_ret = ''
    else:
        css = Element(
            'link', attrib={'rel': 'stylesheet', 'type': 'text/css'})
        if attribute_list and len(attribute_list) > 0:
            for attr in attribute_list:
                css.attrib[attr] = attribute_list[attr]
        css.attrib['href'] = url_for(
            'pem.static', filename='css/' + css_file
        ) if relative else css_file

        # End </link>
        xml_ret = css
    return xml_ret


def html_render(
    title, body, embed_css=False, css_files=[], embed_js=False,
    include_js=[], is_download=False, trans_id=0, did=0
):
    """Renders an HTML document
        title -      title of the html document
        body -       body content of the html document
        embed_css -  checks if you want to embed the css file
        css_files -  css files to be included in the html document
        emded_js -   checks if you want to embed the javascript files
        include_js - javascript files to be included in the html document."""

    html = ET.Element('html', attrib={
        'xmlns': 'https://www.w3.org/1999/xhtml',
        'xmlns:svg': 'https://www.w3.org/2000/svg',
        'xmlns:xlink': 'https://www.w3.org/1999/xlink'
    })
    ET.SubElement(html, 'meta', attrib={
        'name': 'viewport', 'charset': 'utf-8',
        'content': 'width=device-width, initial-scale=1.0, maximum-scale=1.0'
    })

    # Head section
    head = ET.SubElement(html, 'head')
    titleele = ET.SubElement(head, 'title')
    if title:
        titleele.text = title  # End title

    # Favicon
    ET.SubElement(head, 'link', attrib={
        'rel': 'shortcut icon',
        'href': url_for('static', filename='img/favicon.ico'),
        'type': 'image/x-icon',
        'alt': gettext('Shortcut icon'),
    })

    # Include given css files defined
    if css_files and len(css_files) > 0:
        for css_file in css_files:
            ret_xml = include_css_file(css_file, embed_css)
            head.append(ret_xml)
    path = os.path.dirname(os.path.realpath(__file__))

    css_file = include_css_file(
        url_for('static',
                filename='vendor/alertifyjs/alertify.css'),
        embed_css, relative=False
    )
    if css_file != '':
        head.append(css_file)

    css_file = include_css_file(
        url_for('browser.static', filename='css/wizard.css'),
        embed_css, relative=False
    )
    if css_file != '':
        head.append(css_file)

    css_file = include_css_file(
        url_for('static', filename='js/generated/style.css'),
        embed_css, relative=False
    )
    if css_file != '':
        head.append(css_file)

    css_file = include_css_file(
        url_for('static', filename='js/generated/pgadmin.css'),
        embed_css, relative=False
    )
    if css_file != '':
        head.append(css_file)

    ret_xml = include_css_file(
        os.path.realpath(
            os.path.join(path, '../../../../static/css/pem.css')
        ) if embed_css else
        url_for('static', filename='css/pem.css'),
        embed_css, relative=False
    )
    if ret_xml != '':
        head.append(ret_xml)

    # Include pem.css by default
    ret_xml = include_css_file('pem.css', embed_css)
    if ret_xml != '':
        head.append(ret_xml)

    # Include the jquery script by default
    jsfile = include_javascript(
        os.path.realpath(
            os.path.join(
                path, '../../../../static/vendor/jquery/jquery-1.11.2.min.js')
        ) if embed_js else
        url_for('static', filename='vendor/jquery/jquery-1.11.2.min.js'),
        embed_js, relative=False
    )
    if jsfile != '':
        head.append(jsfile)

    jsfile = include_javascript(
        url_for('static',
                filename='vendor/moment/moment-with-locales.min.js'),
        embed_js, relative=False
    )
    if jsfile != '':
        head.append(jsfile)

    jsfile = include_javascript(
        url_for('static',
                filename='vendor/bootstrap/bootstrap-datetimepicker.min.js'),
        embed_js, relative=False
    )
    if jsfile != '':
        head.append(jsfile)

    css_file = include_css_file(
        url_for(
            'static',
            filename='vendor/bootstrap/bootstrap-datetimepicker.min.css'),
        embed_css, relative=False
    )
    if css_file != '':
        head.append(css_file)

    jsfile = include_javascript(
        url_for('static',
                filename='vendor/bootstrap/bootstrap-switch.min.js'),
        embed_js, relative=False
    )
    if jsfile != '':
        head.append(jsfile)

    css_file = include_css_file(
        url_for('static',
                filename='vendor/font-awesome/css/font-awesome.min.css'),
        embed_css, relative=False
    )
    if css_file != '':
        head.append(css_file)

    script = ET.SubElement(
        head, 'script', attrib={'type': 'text/javascript'})
    script.text = render_template_string(
        """
    window.dashboardSettingsUrl = '{{ dashboardSettingsUrl }}';
    window.dashboard_base_url = '{{ dashboard_base_url }}';
    window.alerts_base_url = '{{ alerts_base_url }}';
    window.pem_did = {{ did }};
""",
        dashboardSettingsUrl=url_for('pem_dashboard.index') + 'settings',
        dashboard_base_url=url_for('pem_dashboard.index'),
        alerts_base_url=url_for('alerts.index'),
        did=did
    )

    styleEl = ET.SubElement(head, 'style')
    styleEl.text = 'body { overflow-y: auto; }'

    css_file = include_css_file(
        url_for(
            'static',
            filename='vendor/flotr2/hsd-flotr2.css'
        ),
        embed_css, relative=False
    )

    if css_file != '':
        head.append(css_file)
    css_file = include_css_file(
        url_for(
            'static',
            filename='vendor/qTip2/dist/jquery.qtip.min.css'
        ),
        embed_css, {'media': 'screen'}, relative=False
    )
    if css_file != '':
        head.append(css_file)
    css_file = include_css_file(
        url_for('pem_dashboard.static', filename='css/dashboard_menu.css'),
        embed_js, relative=False
    )
    if css_file != '':
        head.append(css_file)
    css_file = include_css_file(
        url_for(
            'static',
            filename='vendor/really-simple-color-picker/css/colorPicker.css'
        ),
        embed_css, {'media': 'screen'}, relative=False
    )
    if css_file != '':
        head.append(css_file)
    css_file = include_css_file('dashboard.css', embed_js)
    if css_file != '':
        head.append(css_file)

    script = ET.SubElement(
        head, 'script', attrib={'type': 'text/javascript'})
    script.text = 'var showtooltip = true; var showmenu = true;'
    # End script

    ifie = IFIE(head)
    ifie.append(
        include_javascript(
            url_for(
                'static',
                filename='vendor/flashcanvas/bin/flashcanvas.js'
            ),
            embed_js, relative=False
        )
    )
    js_file = include_javascript(
        url_for(
            'static',
            filename='vendor/jquery-ui/jquery-ui-1.11.3.min.js'
        ),
        embed_js, relative=False
    )
    if js_file != '':
        head.append(js_file)
    js_file = include_javascript(
        url_for(
            'static',
            filename='vendor/underscore/underscore.js'
        ),
        embed_js, relative=False
    )
    if js_file != '':
        head.append(js_file)
    js_file = include_javascript(
        url_for(
            'static',
            filename='vendor/flotr2/bean.js'
        ),
        embed_js, relative=False
    )
    if js_file != '':
        head.append(js_file)
    js_file = include_javascript(
        url_for(
            'static',
            filename='vendor/flotr2/flotr2.amd.js'
        ),
        embed_js, relative=False
    )
    if js_file != '':
        head.append(js_file)

    js_file = include_javascript(
        url_for(
            'static',
            filename='vendor/tablesort/jquery.tableSort.js'
        ),
        embed_js, relative=False
    )
    if js_file != '':
        head.append(js_file)
    js_file = include_javascript(
        url_for(
            'static',
            filename='vendor/qTip2/dist/jquery.qtip.min.js'
        ),
        embed_js, relative=False
    )
    if js_file != '':
        head.append(js_file)
    js_file = include_javascript(
        url_for('pem_dashboard.static', filename='js/hoverIntent.js'),
        embed_js, relative=False
    )
    if js_file != '':
        head.append(js_file)
    js_file = include_javascript(
        os.path.realpath(
            os.path.join(
                path,
                '../../../../static/vendor/bootstrap/js/bootstrap.min.js')
        ) if embed_js else
        url_for('static', filename='vendor/bootstrap/js/bootstrap.min.js'),
        embed_js, relative=False
    )
    if js_file != '':
        head.append(js_file)
    js_file = include_javascript(
        url_for('pem_dashboard.static', filename='js/utils.js'),
        embed_js, relative=False
    )

    if js_file != '':
        head.append(js_file)
    js_file = include_javascript(
        url_for('static', filename='vendor/backbone/backbone.js'),
        embed_js, relative=False
    )

    if js_file != '':
        head.append(js_file)
    js_file = include_javascript(
        url_for('static', filename='vendor/backform/backform.js'),
        embed_js, relative=False
    )

    if js_file != '':
        head.append(js_file)
    js_file = include_javascript(
        url_for('static', filename='vendor/backgrid/backgrid.js'),
        embed_js, relative=False
    )

    if js_file != '':
        head.append(js_file)
    js_file = include_javascript(
        url_for('static', filename='vendor/alertifyjs/alertify.js'),
        embed_js, relative=False
    )

    if js_file != '':
        head.append(js_file)
    js_file = include_javascript(
        url_for('static', filename='vendor/bootstrap/bootstrap-switch.js'),
        embed_js, relative=False
    )

    if js_file != '':
        head.append(js_file)

    # PEM-527 adding for checking privileges
    js_file = include_javascript(
        url_for('user_management.current_user_info'),
        embed_js, relative=False
    )
    if js_file != '':
        head.append(js_file)

    js_file = include_javascript(
        url_for("pem.info_js"),
        embed_js, relative=False
    )
    if js_file != '':
        head.append(js_file)
    # PEM-527 Changes ends here

    js_file = include_javascript(
        url_for('pem_dashboard.static', filename='js/dashboard_settings.js'),
        embed_js, relative=False
    )

    if js_file != '':
        head.append(js_file)
    js_file = include_javascript(
        url_for('pem_dashboard.static', filename='js/dashboard.js'),
        embed_js, relative=False
    )
    if js_file != '':
        head.append(js_file)
    js_file = include_javascript(
        url_for('static', filename='vendor/really-simple-color-picker/'
                                   'js/jquery.colorPicker.min.js'),
        embed_js, relative=False
    )

    if js_file != '':
        head.append(js_file)
    js_file = include_javascript(
        url_for('pem_dashboard.static', filename='js/pem_graph.js'),
        embed_js, relative=False
    )

    if js_file != '':
        head.append(js_file)
    js_file = include_javascript(
        url_for('pem_dashboard.static', filename='js/pem_chart.js'),
        embed_js, relative=False
    )

    if js_file != '':
        head.append(js_file)
    js_file = include_javascript(
        url_for('pem_dashboard.static', filename='js/piechart.js'),
        embed_js, relative=False
    )

    if js_file != '':
        head.append(js_file)
    js_file = include_javascript(
        url_for('pem_dashboard.static', filename='js/barchart.js'),
        embed_js, relative=False
    )

    if js_file != '':
        head.append(js_file)
    js_file = include_javascript(
        url_for('pem_dashboard.static', filename='js/linechart.js'),
        embed_js, relative=False
    )

    if js_file != '':
        head.append(js_file)
    js_file = include_javascript(
        url_for('pem_dashboard.static', filename='js/capacity_linechart.js'),
        embed_js, relative=False
    )

    if js_file != '':
        head.append(js_file)
    js_file = include_javascript(
        url_for('pem_dashboard.static', filename='js/capacity_tablegraph.js'),
        embed_js, relative=False
    )

    if js_file != '':
        head.append(js_file)
    js_file = include_javascript(
        url_for('pem_dashboard.static', filename='js/tablegraph.js'),
        embed_js, relative=False
    )

    if js_file != '':
        head.append(js_file)
    js_file = include_javascript(
        url_for('pem_dashboard.static', filename='js/textgraph.js'),
        embed_js, relative=False
    )

    if js_file != '':
        head.append(js_file)
    js_file = include_javascript(
        url_for('pem_dashboard.static', filename='js/group_linechart.js'),
        embed_js, relative=False
    )

    if js_file != '':
        head.append(js_file)
    js_file = include_javascript(
        url_for('pem_dashboard.static', filename='js/loading.js'),
        embed_js, relative=False
    )
    if js_file != '':
        head.append(js_file)

    js_file = include_javascript(
        url_for('static', filename='js/jstz.min.js'),
        embed_js, relative=False
    )
    if js_file != '':
        head.append(js_file)
    # End head

    script = SubElement(body, 'script', type='text/javascript')
    cdata = CDATA("trans_id = {0}".format(trans_id) + ";")
    script.append(cdata)

    # Body section
    if (is_download):
        div = ET.SubElement(body, 'div', attrib={
            'style': 'width:850px; text-align: center; margin: 0px auto'
        })
        style = ET.SubElement(div, 'style', attrib={'type': 'text/css'})
        style.text = """
            @media print
                tr page-break-inside: avoid
                div page-break-inside: avoid
                canvas page-break-inside: avoid
                #reportMenu display:none
        """
        # End Style

        html.append(body)
    else:
        html.append(body)

    return prettify(html, 'xml', True, True)


def html_append_logo(logo, alt_val, embed=False):
    """Append header logo."""
    html = Element('div', id='ReportImage')
    img = SubElement(html, 'img')

    if embed:
        try:
            path = os.path.dirname(os.path.realpath(__file__))
            logo_file_name = path + "/../pem/static/img/" + \
                os.path.basename(os.path.realpath(logo))
            handle = open(logo_file_name, "rb")
            contents = handle.read()
            handle.close()
            imgdata = base64.b64encode(contents)
            img.attrib = {
                'src': 'data:image/png;base64,' + imgdata.decode('utf-8'),
                'alt': alt_val
            }
        except IOError:
            return html
    else:
        img.attrib = {
            'src': url_for('pem.static', filename='img/' + logo),
            'alt': alt_val
        }

    return html


def html_embed_img(img_path, file_type='png', attribs=dict(), as_text=True):
    img_tag = Element('img', attribs)

    try:
        with open(img_path, 'rb') as img:
            contents = img.read()
            imgdata = base64.b64encode(contents).decode('utf-8')
            img_tag.attrib = {
                'src': 'data:image/{0};base64,'.format(file_type) + imgdata
            }
            img_tag.text = ' '
    except IOError:
        pass
    return prettify(img_tag, 'xml', True, False) if as_text else img_tag


def html_common_header(homepage_type='', id='', database='', schema='',
                       agent_id=0, title='', div_id=''):
    """Common HTML Header for all Dashboards."""

    database = database or '0'
    schema = schema or '0'
    id = id or 0
    # values to be obtained are in seconds
    dash_header_timeout = get_params_default('dash_header_timeout', 60)
    refresh_time = int(dash_header_timeout)
    refresh_time *= 1000  # convert to msec

    html = Element('div', id='ReportHeader')
    if title:
        title_el = SubElement(html, 'h1')
        title_el.text = title  # End title
    # Script to auto refresh graphs/charts/tables in the given dashboard
    script = SubElement(html, 'script', attrib={
        'type': 'text/javascript'
    })

    response = render_template(
        "charts/js/dashboard_header.js",
        id=id, database=quote(database), schema=quote(schema),
        agent_id=agent_id, div_id=div_id, refresh_time=refresh_time
    )

    cdata = CDATA(response)
    script.append(cdata)

    return script, html


@pem_connection
def html_header(homepage_type='', id='', database='', schema='', agent_id=0,
                pem_conn=None):
    """HTML Header."""
    script, html = html_common_header(
        homepage_type, id, database, schema, agent_id,
        div_id='LoadDashboardHeader')
    # Document title
    # Get description of the server
    if id != '' and id is not None:
        params = [id]
        status, description = pem_conn.execute_scalar(
            "SELECT description FROM pem.server WHERE id = (%s)::int4", params
        )

        if not status:
            error_return(
                gettext("Error executing query: {0}".format(description)),
                e_type=PEMErrorType.JSON
            )

    else:  # is server_id is not supplied then it is an agent
        params = [agent_id]
        status, description = pem_conn.execute_scalar(
            "SELECT description FROM pem.avail_agents WHERE id = (%s)::int4",
            params
        )

        if not status:
            error_return(
                gettext("Error executing query: {0}".format(description)),
                e_type=PEMErrorType.JSON
            )

    if not description or description == "":
        description = "Unknown"

    # Get title string in different cases
    if id != '' and schema != '' and database != '' and id is not None and \
            schema is not None and database is not None:
        title = gettext("{0}, Database: {1}, Schema: {2}".format(
            description, database, schema))
    elif id != '' and database != '' and id is not None and \
            database is not None:
        title = gettext("{0}, Database: {1}".format(description, database))
    elif agent_id != '' and agent_id is not None:
        title = gettext("{0}".format(description))
    elif id != '' and id is not None:
        title = gettext("{0}".format(description))

    h1 = SubElement(html, 'h1')
    if homepage_type != '':
        if homepage_type == 'Alerts':
            h1.text = homepage_type + " For " + title
        else:
            h1.text = homepage_type + " - " + title
    else:
        h1.text = title

    SubElement(html, 'div', id='LoadDashboardHeader').text = ' '

    # Script to auto refresh graphs/charts/tables in the given dashboard
    script1 = SubElement(html, 'script', type='text/javascript')
    script1.text = "setTimeout('ReloadDashboardHeader()',1);"

    return html


# Header for global dashboards like 'Global Overview' and 'Alerts Dashboard'
def html_global_header(title):
    script, html = html_common_header(
        title=title, div_id='LoadGlobalDashboardHeader')

    global_dash_header = SubElement(
        html, 'div', id='LoadGlobalDashboardHeader')
    # Head section
    if title:
        head = SubElement(global_dash_header, 'head')
        title_el = SubElement(head, 'title')
        title_el.text = title  # End title

    script = SubElement(html, 'script', type='text/javascript')
    cdata = CDATA("setTimeout('ReloadDashboardHeader()',1)")
    script.append(cdata)

    return html


@pem_connection
def html_ops_header(
    homepage_type='', id='', database='', schema='', agent_id='', pem_conn=None
):
    div = Element('div', attrib={'id': 'ReportOpsHeader'})
    title = ' '
    # Document title
    # Get description of the server
    if (id != '' and id is not None):
        params = [id]
        status, description = pem_conn.execute_scalar(
            "SELECT description FROM pem.server WHERE id = (%s)::int4", params
        )

        if not status:
            error_return(
                gettext("Error executing query: {0}".format(description)),
                e_type=PEMErrorType.JSON
            )

    else:  # is server_id is not supplied then it is an agent
        params = [agent_id]
        status, description = pem_conn.execute_scalar(
            "SELECT description FROM pem.avail_agents WHERE id = (%s)::int4",
            params
        )

        if not status:
            error_return(
                gettext("Error executing query: {0}".format(description)),
                e_type=PEMErrorType.JSON
            )

    if (description == "" or description is None):
        description = "Unknown"

    # Get title string in different cases
    if id != '' and schema != '' and database != '' and id is not None and \
            schema is not None and database is not None:
        title = gettext("{{0}}, Database: {{1}}, Schema: {{2}}").format(
            description, database, schema
        )
    elif id != '' and database != '' and id is not None and \
            database is not None:
        title = gettext("{0}, Database: {1}".format(description, database))
    elif agent_id != '' and agent_id is not None:
        title = "{0}".format(description)
    elif id != '' and id is not None:
        title = "{0}".format(description)

    h1 = SubElement(div, 'h1', attrib={
        'style': 'padding-left: 0.5%;width: 99.5%;'
    })
    if (homepage_type != ''):
        if (homepage_type == 'Alerts'):
            h1.text = homepage_type + " For " + title
        else:
            h1.text = homepage_type + ((" - " + title) if title else '')
    else:
        h1.text = title

    # End div
    return div


def html_append_footer():
    html = Element('div', id='ReportFooter')
    a = SubElement(html, 'a', href=config.COMPANY_SITE)
    a.text = config.LONG_COMPANY_NAME
    SubElement(html, 'br')

    return html


def html_append_report_footer():
    html = Element('div', id='ReportFooter')
    html.text = gettext('Report generated by: ')
    a = SubElement(html, 'a', href=config.COMPANY_SITE)
    a.text = gettext('Postgres Enterprise Manager') + "\u2122"
    SubElement(html, 'br')

    return html


@pem_connection
def get_params(name, pem_conn=None):
    if 'PARAM_CACHE' not in globals():
        # Get the dashboard settings from pem.config and stuff them in the
        # global array.
        status, datum_list = pem_conn.execute_2darray(
            'SELECT param, value FROM pem.config'
        )

        if not status:
            error_return(
                gettext("Error executing query: {0}".format(datum_list)),
                e_type=PEMErrorType.JSON
            )

        PARAM_CACHE = {}
        for row in datum_list['rows']:
            PARAM_CACHE[row['param']] = row['value']

        globals().update({'PARAM_CACHE': PARAM_CACHE})

    if 'PARAM_CACHE' in globals() and name in globals()['PARAM_CACHE']:
        return globals()['PARAM_CACHE'][name]
    else:
        # If this param is related to dashboard span
        if re.search('/^(dash_).+(_span)/', name) is not None:
            return 7
        # If this param is related to dashboard rows
        elif re.search('/^(dash_).+(_rows)/', name) is not None:
            return 25
        # If this param is related to chart bullets
        elif re.search('/^(chart_).+(_bullets)/', name) is not None:
            return 0
        return ""


def get_params_default(name, default):
    value = get_params(name)
    if (value == ""):
        return default
    return value


def CDATA(text=None):
    element = Element('![CDATA[')
    element.text = text
    return element


def IFIE(parent):
    return ET.SubElement(parent, '[if IE]')


if hasattr(ET, '_serialize_xml'):
    ET._original_serialize_xml = ET._serialize_xml

    def _serialize_xml(write, elem, *args, **kwargs):
        if elem.tag == '![CDATA[':
            return write("//<{0}\n {1} \n//]]>\n".format(elem.tag, elem.text))
        if elem.tag == '[if IE]':
            def conditional_write(text, *a, **k):
                if text == '<[if IE]':
                    write('<!-- [if IE]')
                elif text == '</[if IE]>':
                    write('<![endif] -->\n')
                else:
                    write(text)
            return ET._original_serialize_xml(
                conditional_write, elem, *args, **kwargs)
        return ET._original_serialize_xml(write, elem, *args, **kwargs)
    ET._serialize_xml = ET._serialize['xml'] = _serialize_xml


def unescape(s):
    s = s.replace("&lt;", "<")
    s = s.replace("&gt;", ">")
    return s


def unescape_prettify(s):
    s = s.replace("&amp;lt;", "&lt;")
    s = s.replace("&amp;gt;", "&gt;")
    return s


def addslashes(s):
    lst = ["\\", '"', "'", "\0", ]
    for i in lst:
        if i in s:
            s = s.replace(i, '\\' + i)
    return s
