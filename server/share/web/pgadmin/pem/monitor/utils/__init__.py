##########################################################################
#
# Postgres Enterprise Manager
#
# Copyright (C) 2016 - 2025, EnterpriseDB Corporation. All rights reserved.
#
##########################################################################

"""PEM Monitoring Dashboard utility functions"""

from pgadmin.pem.misc.error import error_return, PEMErrorType
from pgadmin.pem.utils import pem_connection
from flask_babel import gettext


class DashboardLevel:
    levels = [
        'DB_GLOBAL', 'DB_AGENT', 'DB_SERVER', 'DB_DATABASE', 'DB_SCHEMA',
        'DB_TABLE', 'DB_INDEX', 'DB_SEQUENCE', 'DB_FUNCTION', 'DB_VIEW',
        'DB_EXTENSION'
    ]
    DB_GLOBAL = 50
    DB_AGENT = 100
    DB_SERVER = 200
    DB_DATABASE = 300
    DB_SCHEMA = 400
    DB_TABLE = 500
    DB_INDEX = 600
    DB_SEQUENCE = 700
    DB_FUNCTION = 800
    DB_VIEW = 900
    DB_EXTENSION = 1000


class SystemCharts:
    # Global Overview
    GLOBAL_STATUS = 1
    AGENT_STATUS_INFO = 2
    SERVER_STATUS_INFO = 3
    ALERTS_STATUS_INFO = 4

    # Alerts Dashboard
    ALERTS_OVERVIEW = 5
    ALERTS_DETAILS = 6
    ALERTS_ERRORS = 7

    # Audit Logs Dashboard
    AUDIT_LOGS = 8

    # Database Dashboard
    DB_STRG_DETAILS = 9
    DB_STRG = 10
    DB_USER_ACTIVITY = 11
    DB_CONN_DETAILS = 12
    DB_CONN_OVERVIEW = 13
    DB_TOP_TABLES = 17
    SLONY_EVENT_LAG = 85
    SLONY_TIME_LAG = 86

    # I/O Analysis Dashboard
    DB_IO_HIT_READ_DETAILS = 18
    DB_IO_HIT_READ_STATS = 19
    IO_CHECK_POINT_DETAILS = 22
    IO_CHECK_POINT_ACTIVITY = 23
    IO_TOP5_SCANNED_TABLES = 24
    IO_TOP5_SCANNED_INDEXES = 25
    TOP_20_INDEX_ACTIVITY = 79

    # Server Memory Dashboard
    SE_MEMORY_ACTIVITY_DETAILS = 26
    SE_MEMORY_ACTIVITY = 27
    SE_MEMORY_CONFIGURATION = 28
    HOST_MEMORY_ACTIVITY = 29
    HOST_MEMORY_INFORMATION = 30
    HOST_MEMORY_DETAILS = 78

    # Object Activity Dashboard
    TOP_5_LARGEST_TABLES = 31
    TOP_5_LARGEST_INDEXES = 32
    OBJECT_ACTIVITIES = 33
    OBJECT_STRG = 34

    # Operating System Dashboard
    CPU_STATS_DETAILS = 35
    CPU_STATS = 36
    STRG_STATS = 37
    MEMORY_STATS_DETAILS = 38
    MEMORY_STATS = 39
    PROCESS_STATS = 40
    DISK_UTILIZATION = 42
    IO_STATS = 43
    HOST_DETAILS = 44
    NET_PACKET_STATS = 45
    NET_INTERFACE_DETAILS = 46
    NET_TRAFFIC_STATS = 47

    # Probe Logs Dashboard
    PROBE_LOGS = 48

    # Server Logs Dashboard
    SERVER_LOGS = 49

    # Server Analysis Dashboard
    DATABASES_SIZE = 50
    TBLSPACES_SIZE = 51
    SHARED_BUFFER_DETAILS = 52
    SHARED_BUFFER = 53
    USER_ACTIVITY_DETAILS = 54
    USER_ACTIVITY = 55
    CONN_OVERVIEW_DETAILS = 56
    CONN_OVERVIEW = 57
    DISK_INFORMATION = 58
    ROWS_ACTIVITY = 59
    ROWS_ACTIVITY_DETAILS = 21
    COMMITS_ROLLBACKS = 60
    DATABASES_ANALYSIS = 61

    # Session Activity Dashboard
    SESSION_WORK_LOAD = 62
    SESSION_LOCKS_ACTIVITY = 63

    # Session Wait Dashboard
    NUM_SESSION_WAITS = 64
    SESSION_WAIT_DETAILS = 65
    SESSOIN_TIME_WAITS = 66

    # Storage Analysis Dashboard
    DATABASES_STRG_OVERVIEW = 67
    TBLSPACES_STRG_OVERVIEW = 68
    HOST_STRG_OVERVIEW_DETAILS = 69
    HOST_STRG_OVERVIEW = 70
    DATABASES_STRG_DETAILS_TBL = 71
    TBLSPACES_STRG_DETAILS_TBL = 72
    HOST_STRG_DETAILS_TBL = 73

    # System Wait Dashboard
    NUM_SYS_WAITS = 74
    SYS_WAIT_TIME = 75
    SYS_WAIT_DETAILS_TBL = 76

    # Streaming Replication Dashboard
    WAL_ARCHIVE_STATUS = 80
    WAL_SEGMENT_LAG = 81
    WAL_PAGE_LAG = 82
    REPLICATION_TIME_LAG_DETAILS = 83
    REPLICATION_TIME_LAG = 84
    NUMBER_OF_EVENTS_LEG = 85
    TIME_LEG = 86
    BG_WRITER_STATS = 87
    EFM_CLUSTER_NODE_STATUS = 88
    EFM_CLUSTER_INFO = 89
    PATRONI_CLUSTER_NODE_STATUS = 113
    PATRONI_CLUSTER_INFO = 114

    # BDR Node Monitoring Dashboard
    BDR_ND_REP_RATES_REPLAY_LAG_SEC = 90
    BDR_ND_REP_RATES_REPLAY_LAG_BYTE = 91
    BDR_ND_REP_RATES_APPLY_RATE = 92
    BDR_NODE_SLOT_REPLAY_LAG_SECONDS = 93
    BDR_NODE_SLOT_REPLAY_LAG_BYTES = 94
    BDR_CONFLICT_HISTORY_SUMMARY = 95

    # BDR Group Dashboard
    BDR_GP_REP_SL_REPLAY_LAG_SEC = 96
    BDR_GP_REP_SL_FLUSH_LAG_SEC = 97
    BDR_GP_REP_SL_WRITE_LAG_SEC = 98
    BDR_GP_REP_SL_SENT_LAG = 99
    BDR_GP_REP_SL_REPLAY_LAG = 100
    BDR_GP_REP_SL_FLUSH_LAG = 101
    BDR_GP_REP_SL_WRITE_LAG = 102
    BDR_GP_SUB_SUMMARY_SUB_LAG_SEC = 103

    # BDR Admin Dashboard
    BDR_NODE_SUMMARY = 104
    BDR_GLOBAL_LOCKS = 105
    BDR_WORKERS = 106
#     BDR_WORKER_ERRORS = 107
    BDR_GROUP_VERSION_DETAILS = 108
    BDR_GROUP_RAFT_DETAILS = 109
    BDR_GROUP_CAMO_DETAILS = 110
    BDR_STAT_RELATIONS = 111
    BDR_STAT_SUBSCRIPTIONS = 112

    @pem_connection
    def getChartSettings(
            self, cid, level, did=None, objid=None, database=None,
            schema=None, tbl=None, pem_conn=None
    ):
        sql = """
WITH chart_cfg AS (
SELECT
    c.id AS cid,
    c.type AS ctype,
    c.name,
    /*
     * Only line charts and capacity report chart (line/table) can have
     * historical span and extrapolated span
     */
    CASE
        WHEN c.type IN ('L', 'GL') THEN
            CASE
                /*
                 * Extrapolated span can only be present, when ext_id is not
                 * specified, and ext_span is not equal to '0 hours'
                 */
                WHEN (mc.ext_id IS NULL AND mc.ext_span > '0 hours'::interval)
                    THEN 'HES'
                ELSE 'HS'
            END
        WHEN c.type IN ('CL', 'CT') AND cr.midx is NULL OR cr.tval IS NULL
            THEN 'HES'
        WHEN c.type IN ('CL', 'CT') AND cr.midx IS NOT NULL THEN 'HS'
        ELSE c.type
    END AS type,
    /*
     * Some system level charts has configuration for the historical span,
     * no of rows, and timeout saved in the pem.config table
     *
     * We will calculate the span in hours only
     * Hence, EPOCH (i.e. seconds) / 3600.
     */
    CASE
        WHEN c.type IN ('L', 'GL') THEN
            EXTRACT(EPOCH FROM COALESCE(
                (SELECT (cfg.value || cfg.unit)::interval FROM pem.config cfg
                    WHERE cfg.param = c.rwlimit_span_param), mc.time_span)
            ) / 3600
        WHEN c.type IN ('CL', 'CT') AND cr.midx IS NULL THEN
            cr.historical * 24
        ELSE NULL
    END AS span,
    CASE
        WHEN c.type IN ('L', 'GL') AND
            (mc.ext_id IS NULL AND mc.ext_span > '0 hours'::interval) THEN
            EXTRACT(EPOCH FROM mc.ext_span) / 3600
        WHEN c.type IN ('CL', 'CT') AND
            cr.midx IS NULL THEN
            cr.extrapolated * 24
        ELSE NULL
    END AS espan,
    EXTRACT (EPOCH FROM COALESCE(
        (SELECT (cfg.value || cfg.unit)::interval FROM pem.config cfg
            WHERE cfg.param = c.ref_timeout_param),
        ((c.reload / 1000) || 'seconds')::interval)
    ) AS reload,
    /*
     * maximum no of points are for line (normal/capacity report) charts
     * and no of rows for tables
     */
    CASE
        WHEN c.type = 'TB' THEN
            COALESCE(
                (SELECT cfg.value::integer FROM pem.config cfg
                    WHERE cfg.param = c.rwlimit_span_param),
                dc.glimit::integer
            )
        ELSE mc.max_points
    END AS points,
    CASE
        WHEN c.type = 'B' THEN (
            SELECT b.colors FROM pem.bar_chart b
            WHERE b.cid = (%(cid)s)::integer
        )
        WHEN c.type = 'P' THEN (
            SELECT p.colors FROM pem.pie_chart p
            WHERE p.cid = (%(cid)s)::integer
        )
        WHEN c.type IN ('L', 'GL') THEN (
            SELECT l.colors FROM pem.line_chart l
            WHERE l.cid = (%(cid)s)::integer
        )
        WHEN c.type = 'CL' THEN cr.colors
        ELSE NULL
    END AS colors,
    c.labels AS labels, (
        SELECT
        CASE WHEN lower(cfg.value) = 'png' THEN 2 ELSE 1 END
        FROM pem.config cfg
        WHERE cfg.param = 'download_chart_format'
    ) AS downloadformat
FROM
    pem.chart c
    LEFT JOIN (
        SELECT * FROM pem.metrices_chart WHERE cid = (%(cid)s)::integer
    ) mc ON (mc.cid = c.id)
    LEFT JOIN (
        SELECT * FROM pem.data_chart WHERE cid = (%(cid)s)::integer
    ) dc ON (dc.cid = c.id)
    LEFT JOIN (
        SELECT * FROM pem.capacity_report_chart WHERE cid = (%(cid)s)::integer
    ) cr ON (cr.cid = c.id)
WHERE c.id = (%(cid)s)::integer
),
user_cfg AS (
    SELECT * FROM (
        SELECT
            cfg.cid, cfg.level, (
                CASE
                WHEN cfg.did = -1 THEN 0 ELSE 5
                END +
                CASE
                WHEN cfg.objid IS NULL THEN 1::integer
                WHEN (%(objid)s)::integer IS NOT NULL AND
                    cfg.objid = (%(objid)s)::integer AND
                    cfg.database IS NULL
                    THEN 2::integer
                WHEN (%(objid)s)::integer IS NOT NULL AND
                    cfg.objid = (%(objid)s)::integer AND
                    (%(database)s)::text IS NOT NULL AND
                    cfg.database = (%(database)s)::text AND
                    cfg.schema IS NULL
                    THEN 3::integer
                WHEN (%(objid)s)::integer IS NOT NULL AND
                    cfg.objid = (%(objid)s)::integer AND
                    (%(database)s)::text IS NOT NULL AND
                    cfg.database = (%(database)s)::text AND
                    (%(schema)s)::text IS NOT NULL AND
                    cfg.schema = (%(schema)s)::text AND
                    cfg.tbl IS NULL
                    THEN 4::integer
                WHEN (%(objid)s)::integer IS NOT NULL AND
                    cfg.objid = (%(objid)s)::integer AND
                    (%(database)s)::text IS NOT NULL AND
                    cfg.database = (%(database)s)::text AND
                    (%(schema)s)::text IS NOT NULL AND
                    cfg.schema = (%(schema)s)::text AND
                    (%(tbl)s)::text IS NOT NULL AND cfg.tbl = (%(tbl)s)::text
                    THEN 5::integer
                END
            ) AS lvl,
            cfg.reload, cfg.colors, cfg.span, cfg.espan, cfg.points,
            cfg.sortseq,
            CASE
            WHEN cfg.downloadformat = 2::integer THEN 2::integer
            ELSE 1::integer
            END AS downloadformat,
            cfg.showackalerts
        FROM pem.chart_config cfg
        WHERE
            /*
             * Find the chart configuration for the specified in
             * pem.chart_config table:
             * 1. Matches for the same combination on the same did
             * 2. On any dashboard (for same configuration)
             */
            cfg.cid = (%(cid)s)::integer AND ((
                cfg.did = -1 AND cfg.level <= (%(level)s)::integer
            ) OR (
                cfg.did = (%(did)s)::integer AND (%(did)s)::integer IS NOT NULL
            )) AND
            cfg.uid = (
                SELECT u.usesysid FROM pg_catalog.pg_user u
                WHERE u.usename = current_user
            )
    ) a WHERE lvl IS NOT NULL
    /*
     * we only need the highest level possible chart configuration saved by the
     * user
     */
    ORDER BY lvl DESC, level DESC
    LIMIT 1
)
SELECT type, timeout,
  (unnest(colors)::pem.chart_metric_param).name AS clname,
  (unnest(colors)::pem.chart_metric_param).value as clval,
  default_colors, span, espan, points, sortseq, labels, downloadformat,
  name, showackalerts
FROM (
    /*
     * Give priority to the user configuration over default configuration
     */
    SELECT
        c.type AS type,
        /* Default timeout is 300 seconds */
        COALESCE(x.reload, c.reload, 300) AS timeout,
        CASE
        WHEN x.colors IS NOT NULL THEN x.colors
        ELSE '{"(,)"}'::pem.chart_metric_param[]
        END AS colors,
        c.colors AS default_colors,
        CASE
        WHEN c.ctype IN ('L', 'GL', 'CL', 'CT') THEN COALESCE(x.span, c.span)
        ELSE NULL
        END AS span,
        CASE
        WHEN c.type = 'HES' THEN COALESCE(x.espan, c.espan)
        ELSE NULL
        END AS espan,
        COALESCE(x.points, c.points) AS points,
        CASE WHEN c.type = 'TB' THEN x.sortseq ELSE NULL END AS sortseq,
        CASE
        WHEN c.labels IS NOT NULL THEN c.labels ELSE '{}'::character varying[]
        END AS labels,
        COALESCE(x.downloadformat, c.downloadformat) as downloadformat,
        c.name, x.showackalerts
    FROM
        chart_cfg c LEFT OUTER JOIN user_cfg x ON (c.cid = x.cid)
) c"""

        params = {
            "cid": cid, "did": did, "objid": objid, "database":
            database, "schema": schema, "tbl": tbl, "level": level
        }
        status, dbRes = pem_conn.execute_2darray(sql, params)

        if not status or dbRes is None or len(dbRes) == 0:
            error_return(
                gettext("Couldn't find the chart settings for this chart!"),
                PEMErrorType.JSON
            )

        res = {}
        idx = 0
        for row in dbRes['rows']:
            if idx == 0:
                # type, timeout, clname, clval, span, espan, points, sortseq,
                # label, downloadformat, alert_ack

                res['type'] = row['type']
                res['timeout'] = row['timeout']

                # Fetch all the labels and store them in result.
                res['labels'] = {}
                if row['labels']:
                    for i in range(1, len(row['labels'])):
                        res['labels'][i] = row['labels'][i]

                if res['type'] != 'TB':
                    # Check default colors returned by the query and also check
                    # number of labels and number of default colors must be
                    # same
                    res['colors'] = {}
                    if (
                        row['default_colors'] and row['labels'] and
                        len(row['labels']) == len(row['default_colors'])
                    ):
                        for i in range(1, len(row['labels'])):
                            res['colors'][row['labels'][i]] = \
                                row['default_colors'][i]

                    res['span'] = row['span']
                    res['espan'] = row['espan']

                    if row['points'] is not None:
                        res['points'] = row['points']

                    if row['downloadformat']:
                        res['downloadformat'] = row['downloadformat']

                    # Check if color is changed by the user if it is then
                    # update the color with the changed value.
                    if row['clname']:
                        res['colors'][row['clname']] = row['clval']
                else:
                    try:
                        res['sortseq'] = row['sortseq']
                        if row['points'] is not None:
                            res['max_rows'] = row['points']
                    except Exception:
                        pass

                # Check the chart name to identify whether we should show
                # showackalerts config or not
                if row['name'].lower() == 'alerts details':
                    res['showackalerts'] = row['showackalerts']
                idx += 1
            elif res['type'] != 'TB':
                if row['clname']:
                    res['colors'][row['clname']] = row['clval']

        return res


def getTableInfo(_id):
    predefined_tables_info = dict({
        SystemCharts.AGENT_STATUS_INFO: dict({
            "label": gettext("Agent Status"),
            "columns": [
                dict({
                    "label": gettext("Blackout"),
                    "sort-method": None,
                }),
                dict({
                    "label": gettext("Status")
                }),
                dict({
                    "label": gettext("Name"),
                }),
                dict({
                    "label": gettext("Alerts"),
                    "sort-method": "number"
                }),
                dict({
                    "label": gettext("Version"),
                    "sort-method": "number"
                }),
                dict({
                    "label": gettext("Processes"),
                    "sort-method": "number"
                }),
                dict({
                    "label": gettext("Threads"),
                    "sort-method": "number"
                }),
                dict({
                    "label": gettext("CPU Utilization (%)"),
                    "sort-method": "number"
                }),
                dict({
                    "label": gettext("Memory Utilization (%)"),
                    "sort-method": "number"
                }),
                dict({
                    "label": gettext("Swap Utilization (%)"),
                    "sort-method": "number"
                }),
                dict({
                    "label": gettext("Disk Utilization (%)"),
                    "sort-method": "number"
                }),
            ],
        }),
        SystemCharts.SERVER_STATUS_INFO: dict({
            "label": gettext("Server Status"),
            "columns": [
                dict({
                    "label": gettext("Blackout"),
                    "sort-method": None,
                }),
                dict({
                    "label": gettext("Status")
                }),
                dict({"label": gettext("Name")}),
                dict({
                    "label": gettext("Connections"),
                    "sort-method": "number"
                }),
                dict({
                    "label": gettext("Alerts"),
                    "sort-method": "number"
                }),
                dict({"label": gettext("Version")}),
                dict({"label": gettext("Remotely Monitored?")}),
            ],
        }),
        SystemCharts.ALERTS_STATUS_INFO: dict({
            "label": gettext("Alert Status"),
            "columns": [
                dict({
                    "label": "expand",
                    "sort-method": None,
                }),
                dict({"label": gettext("Alarm Type")}),
                dict({"label": gettext("Object Description")}),
                dict({"label": gettext("Alert Name")}),
                dict({"label": gettext("Value")}),
                dict({"label": gettext("Database")}),
                dict({"label": gettext("Schema")}),
                dict({"label": gettext("Package")}),
                dict({"label": gettext("Object")}),
                dict({"label": gettext("Alerting Since")})
            ],
        }),
        SystemCharts.ALERTS_ERRORS: dict({
            "label": gettext("Alert Errors"),
            "columns": [
                dict({"label": gettext("Alert Type")}),
                dict({"label": gettext("Name")}),
                dict({"label": gettext("Value")}),
                dict({"label": gettext("Agent")}),
                dict({"label": gettext("Server")}),
                dict({"label": gettext("Database")}),
                dict({"label": gettext("Schema")}),
                dict({"label": gettext("Package")}),
                dict({"label": gettext("Object")}),
                dict({"label": gettext("Error Message")}),
                dict({"label": gettext("Error Timestamp")})
            ],
        }),
        SystemCharts.DB_TOP_TABLES: dict({
            "label": gettext("Top Tables"),
            "columns": [
                dict({"label": gettext("Schema")}),
                dict({
                    "label": gettext("Table Name"),
                    "sort-method": "number"
                }),
                dict({
                    "label": gettext("Scans"),
                    "sort-method": "number"
                }),
                dict({
                    "label": gettext("Rows Read"),
                    "sort-method": "number"
                }),
                dict({
                    "label": gettext("Index Scans"),
                    "sort-method": "number"
                }),
                dict({
                    "label": gettext("Index Rows Read"),
                    "sort-method": "number"
                }),
                dict({
                    "label": gettext("Rows Inserted"),
                    "sort-method": "number"
                }),
                dict({
                    "label": gettext("Rows Updated"),
                    "sort-method": "number"
                }),
                dict({
                    "label": gettext("Rows Deleted"),
                    "sort-method": "number"
                }),
                dict({
                    "label": gettext("HOT Rows Updated"),
                    "sort-method": "number"
                }),
                dict({
                    "label": gettext("Total Rows"),
                    "sort-method": "number"
                }),
                dict({
                    "label": gettext("Dead Rows"),
                    "sort-method": "number"
                }),
            ],
        }),
        SystemCharts.TOP_20_INDEX_ACTIVITY: dict({
            "label": gettext("Top 20 Indexes Activity"),
            "columns": [
                dict({"label": gettext("Schema")}),
                dict({"label": gettext("Table Name")}),
                dict({"label": gettext("Index Name")}),
                dict({
                    "label": gettext("Scans"),
                    "sort-method": "number"
                }),
                dict({
                    "label": gettext("Rows Read"),
                    "sort-method": "number"
                }),
                dict({
                    "label": gettext("Rows Fetched"),
                    "sort-method": "number"
                }),
                dict({
                    "label": gettext("Blocks Read"),
                    "sort-method": "number"
                }),
                dict({
                    "label": gettext("Blocks Hit"),
                    "sort-method": "number"
                }),
            ],
        }),
        SystemCharts.OBJECT_ACTIVITIES: dict({
            "id": 33,
            "label": gettext("Objects Activity"),
            "columns": [
                dict({"label": gettext("Schema")}),
                dict({
                    "label": gettext("Table Name"),
                    "sort-method": "number"
                }),
                dict({
                    "label": gettext("Scans"),
                    "sort-method": "number"
                }),
                dict({
                    "label": gettext("Rows Read"),
                    "sort-method": "number"
                }),
                dict({
                    "label": gettext("Index Scans"),
                    "sort-method": "number"
                }),
                dict({
                    "label": gettext("Index Rows Read"),
                    "sort-method": "number"
                }),
                dict({
                    "label": gettext("Rows Inserted"),
                    "sort-method": "number"
                }),
                dict({
                    "label": gettext("Rows Updated"),
                    "sort-method": "number"
                }),
                dict({
                    "label": gettext("Rows Deleted"),
                    "sort-method": "number"
                }),
                dict({
                    "label": gettext("HOT Rows Updated"),
                    "sort-method": "number"
                }),
                dict({
                    "label": gettext("Total Rows"),
                    "sort-method": "number"
                }),
                dict({
                    "label": gettext("Dead Rows"),
                    "sort-method": "number"
                }),
            ],
        }),
        SystemCharts.OBJECT_STRG: dict({
            "label": gettext("Object Storage"),
            "columns": [
                dict({"label": gettext("Schema")}),
                dict({"label": gettext("Object")}),
                dict({"label": gettext("Object Type")}),
                dict({
                    "label": gettext("Table Size (MB)"),
                    "sort-method": "number"
                }),
                dict({
                    "label": gettext("Index Size (MB)"),
                    "sort-method": "number"
                }),
                dict({
                    "label": gettext("Total(MB)"),
                    "sort-method": "number"
                }),
            ],
        }),
        SystemCharts.HOST_DETAILS: dict({
            "label": gettext("Host Details"),
            "columns": [
                dict({"label": gettext("File System")}),
                dict({
                    "label": gettext("Size (GB)"),
                    "sort-method": "number"
                }),
                dict({
                    "label": gettext("Used (GB)"),
                    "sort-method": "number"
                }),
                dict({
                    "label": gettext("Available (GB)"),
                    "sort-method": "number"
                }),
                dict({
                    "label": gettext("% Used"),
                    "sort-method": "number"
                }),
                dict({"label": gettext("Mounted On")}),
            ],
        }),
        SystemCharts.DATABASES_ANALYSIS: dict({
            "label": gettext("Databases Statistics"),
            "columns": [
                dict({"label": gettext("Database")}),
                dict({
                    "label": gettext("Connections"),
                    "sort-method": "number"
                }),
                dict({
                    "label": gettext("TX Committed"),
                    "sort-method": "number"
                }),
                dict({
                    "label": gettext("TX Rolled Back"),
                    "sort-method": "number"
                }),
                dict({
                    "label": gettext("Blocks Hit"),
                    "sort-method": "number"
                }),
                dict({
                    "label": gettext("Blocks Read"),
                    "sort-method": "number"
                }),
                dict({
                    "label": gettext("Tuples Fetched"),
                    "sort-method": "number"
                }),
                dict({
                    "label": gettext("Tuples Returned"),
                    "sort-method": "number"
                }),
                dict({
                    "label": gettext("Tuples Inserted"),
                    "sort-method": "number"
                }),
                dict({
                    "label": gettext("Tuples Updated"),
                    "sort-method": "number"
                }),
                dict({
                    "label": gettext("Tuples Deleted"),
                    "sort-method": "number"
                }),
            ]
        }),
        SystemCharts.SESSION_WORK_LOAD: dict({
            "label": gettext("Work Load"),
            "columns": [
                dict({
                    "label": gettext("Session Id"),
                    "sort-method": "number"
                }),
                dict({"label": gettext("User Name")}),
                dict({"label": gettext("Source")}),
                dict({"label": gettext("Database Name")}),
                dict({"label": gettext("Waiting?")}),
                dict({"label": gettext("Backend Start")}),
                dict({"label": gettext("Transaction Start")}),
                dict({"label": gettext("Query Start")}),
                dict({
                    "label": gettext("Memory Usage"),
                    "sort-method": "number"
                }),
                dict({
                    "label": gettext("Swap Usage"),
                    "sort-method": "number"
                }),
                dict({
                    "label": gettext("CPU Usage"),
                    "sort-method": "number"
                }),
                dict({
                    "label": gettext("I/O Reads (bytes)"),
                    "sort-method": "number"
                }),
                dict({
                    "label": gettext("I/O Writes (bytes)"),
                    "sort-method": "number"
                })
            ],
        }),
        SystemCharts.SESSION_LOCKS_ACTIVITY: dict({
            "label": gettext("Locks Activity"),
            "columns": [
                dict({
                    "label": gettext("Session Id"),
                    "sort-method": "number"
                }),
                dict({"label": gettext("User Name")}),
                dict({"label": gettext("Source")}),
                dict({"label": gettext("Database Name")}),
                dict({"label": gettext("Blocked")}),
                dict({"label": gettext("Blocked By")}),
                dict({"label": gettext("Lock Type")}),
                dict({
                    "label": gettext("Object Id"),
                    "sort-method": "number"
                }),
                dict({"label": gettext("Mode")}),
                dict({"label": gettext("Transaction Start")})
            ],
        }),
        SystemCharts.SESSION_WAIT_DETAILS: dict({
            "label": gettext("Session Wait Details"),
            "columns": [
                dict({"label": gettext("User")}),
                dict({"label": gettext("Wait Name")}),
                dict({
                    "label": gettext("Wait Count"),
                    "sort-method": "number"
                }),
                dict({
                    "label": gettext("Time (ms)"),
                    "sort-method": "number"
                }),
                dict({
                    "label": gettext("Wait Time (%)"),
                    "sort-method": "number"
                }),
            ],
        }),
        SystemCharts.DATABASES_STRG_DETAILS_TBL: dict({
            "label": gettext("Database Storage Details"),
            "columns": [
                dict({"label": gettext("Database Name")}),
                dict({
                    "label": gettext("Database Size (MB)"),
                    "sort-method": "number"
                }),
                dict({"label": gettext("Tablespace Name")}),
            ],
        }),
        SystemCharts.TBLSPACES_STRG_DETAILS_TBL: dict({
            "label": gettext("Tablespace Storage Details"),
            "columns": [
                dict({"label": gettext("Tablespace Name")}),
                dict({
                    "label": gettext("Tablespace Size (MB)"),
                    "sort-method": "number"
                }),
            ],
        }),
        SystemCharts.HOST_STRG_DETAILS_TBL: dict({
            "label": gettext("Host Storage Details"),
            "columns": [
                dict({"label": gettext("File System")}),
                dict({
                    "label": gettext("Size (GB)"),
                    "sort-method": "number"
                }),
                dict({
                    "label": gettext("Used (GB)"),
                    "sort-method": "number"
                }),
                dict({
                    "label": gettext("Available (GB)"),
                    "sort-method": "number"
                }),
                dict({
                    "label": gettext("% Used"),
                    "sort-method": "number"
                }),
                dict({"label": gettext("Mounted On")}),
            ]
        }),
        SystemCharts.SYS_WAIT_DETAILS_TBL: dict({
            "label": gettext("Wait Details"),
            "columns": [
                dict({"label": gettext("Event")}),
                dict({
                    "label": gettext("Wait Count"),
                    "sort-method": "number"
                }),
                dict({
                    "label": gettext("Percentage of Total"),
                    "sort-method": "number"
                }),
                dict({
                    "label": gettext("Time Waited (ms)"),
                    "sort-method": "number"
                }),
                dict({
                    "label": gettext("Percentage of Time Waited"),
                    "sort-method": "number"
                }),
                dict({
                    "label": gettext("Average Wait Time (ms)"),
                    "sort-method": "number"
                })
            ]
        }),
        SystemCharts.EFM_CLUSTER_INFO: dict({
            "label": gettext("Failover Manager Cluster Information"),
            "columns": [
                dict({"label": gettext("Property")}),
                dict({"label": gettext("Value")}),
            ],
        }),
        SystemCharts.EFM_CLUSTER_NODE_STATUS: dict({
            "label": gettext("Failover Manager Node Status"),
            "columns": [
                dict({"label": gettext("Agent Type")}),
                dict({"label": gettext("Address")}),
                dict({"label": gettext("DB")}),
                dict({"label": gettext("XLog Location")}),
                dict({"label": gettext("XLog Receive")}),
                dict({"label": gettext("Status Information")}),
                dict({"label": gettext("XLog Information")}),
                dict({"label": gettext("Virtual IP Address")}),
                dict({"label": gettext("VIP Status")}),
            ],
        }),
        SystemCharts.EFM_CLUSTER_INFO: dict({
            "label": gettext("Failover Manager Cluster Information"),
            "columns": [
                dict({"label": gettext("Property")}),
                dict({"label": gettext("Value")}),
            ],
        }),
        SystemCharts.ALERTS_DETAILS: dict({
            "label": gettext("Alert Details"),
            "columns": [
                dict({
                    "label": "expand",
                    "sort-method": None,
                }),
                dict({"label": gettext("Ack'ed")}),
                dict({"label": gettext("Alert Type")}),
                dict({"label": gettext("Name")}),
                dict({"label": gettext("Value")}),
                dict({"label": gettext("Agent")}),
                dict({"label": gettext("Server")}),
                dict({"label": gettext("Database")}),
                dict({"label": gettext("Schema")}),
                dict({"label": gettext("Package")}),
                dict({"label": gettext("Object")}),
                dict({"label": gettext("Alerting Since")}),
            ],
        }),
        SystemCharts.BDR_NODE_SUMMARY: dict({
            "label": gettext("Node Summary"),
            "columns": [
                dict({"label": gettext("Node")}),
                dict({"label": gettext("Node Group")}),
                dict({"label": gettext("Peer State")}),
                dict({"label": gettext("Peer Target State")}),
                dict({"label": gettext("Sub Repset")})
            ],
        }),
        SystemCharts.BDR_GLOBAL_LOCKS: dict({
            "label": gettext("Global Locks"),
            "columns": [
                dict({"label": gettext("Origin node name")}),
                dict({"label": gettext("Lock type")}),
                dict({"label": gettext("Relation")}),
                dict({"label": gettext("PID")}),
                dict({"label": gettext("Acquire stage")}),
                dict({"label": gettext("Waiters")}),
                dict({"label": gettext("Global lock request time")}),
                dict({"label": gettext("Local lock request time")}),
                dict({"label": gettext("Last state change time")}),
            ],
        }),
        SystemCharts.BDR_GROUP_VERSION_DETAILS: dict({
            "label": gettext("PGD Group Version Details"),
            "columns": [
                dict({"label": gettext("Node Name")}),
                dict({"label": gettext("Postgres Version")}),
                dict({"label": gettext("pglogical Version")}),
                dict({"label": gettext("PGD Version")}),
                dict({"label": gettext("PGD Edition")}),
            ],
        }),
        SystemCharts.BDR_GROUP_CAMO_DETAILS: dict({
            "label": gettext("PGD Group Camo Details"),
            "columns": [
                dict({"label": gettext("Node Name")}),
                dict({"label": gettext("Camo partner of")}),
                dict({"label": gettext("Camo origin for")}),
                dict({"label": gettext("Is camo partner connected?")}),
                dict({"label": gettext("Is camo partner ready?")}),
                dict({"label": gettext("Camo transactions resolved")}),
                dict({"label": gettext("Apply LSN")}),
                dict({"label": gettext("Receive LSN")}),
                dict({"label": gettext("Apply queue size")}),
            ],
        }),
        SystemCharts.BDR_GROUP_RAFT_DETAILS: dict({
            "label": gettext("PGD Group Raft Details"),
            "columns": [
                dict({"label": gettext("Node Name")}),
                dict({"label": gettext("State")}),
                dict({"label": gettext("Leader ID")}),
                dict({"label": gettext("Current Term")}),
                dict({"label": gettext("Commit Index")}),
            ],
        }),
        SystemCharts.BDR_WORKERS: dict({
            "label": gettext("PGD Workers"),
            "columns": [
                dict({"label": "expand"}),
                dict({
                    "label": gettext("Worker PID"),
                    "sort-method": "number"
                }),
                dict({"label": gettext("Worker Role Name")}),
                dict({"label": gettext("Query Start")}),
                dict({"label": gettext("Worker Commit Timestamp")}),
                dict({"label": gettext("Wait Event Type")})
            ],
        }),
        SystemCharts.BDR_STAT_RELATIONS: dict({
            "label": gettext("PGD Relation Statistics"),
            "columns": [
                dict({"label": gettext("Relation Schema Name")}),
                dict({"label": gettext("Relation Name")}),
                dict({"label": gettext("Relation OID"),
                      "sort-method": "number"}),
                dict({"label": gettext("Total Time")}),
                dict({"label": gettext("# Inserts"),
                      "sort-method": "number"}),
                dict({"label": gettext("# Updates"),
                      "sort-method": "number"}),
                dict({"label": gettext("# Deletes"),
                      "sort-method": "number"}),
                dict({"label": gettext("# Truncates"),
                      "sort-method": "number"}),
                dict({"label": gettext("# Shared Blocks Cache Hit"),
                      "sort-method": "number"}),
                dict({"label": gettext("# Shared Blocks Read"),
                      "sort-method": "number"}),
                dict({"label": gettext("# Shared Blocks Dirtied"),
                      "sort-method": "number"}),
                dict({"label": gettext("# Shared Blocks Written"),
                      "sort-method": "number"}),
                dict({"label": gettext("# Time Spent Reading Blocks")}),
                dict({"label": gettext("# Time Spent Writing Blocks")}),
                dict({"label": gettext("# Time Spent Acquiring Blocks")}),
            ],
        }),
        SystemCharts.BDR_STAT_SUBSCRIPTIONS: dict({
            "label": gettext("PGD Subscription Statistics"),
            "columns": [
                dict({"label": gettext("Subscription Name")}),
                dict({"label": gettext("Subscription OID")}),
                dict({"label": gettext("# Subscription Connected Upstream")}),
                dict({"label": gettext("# Commits"),
                      "sort-method": "number"}),
                dict({"label": gettext("# Aborts"),
                      "sort-method": "number"}),
                dict({"label": gettext("# Errors"),
                      "sort-method": "number"}),
                dict({"label": gettext("# Transactions Skipped"),
                      "sort-method": "number"}),
                dict({"label": gettext("# Inserts"),
                      "sort-method": "number"}),
                dict({"label": gettext("# Updates"),
                      "sort-method": "number"}),
                dict({"label": gettext("# Deletes"),
                      "sort-method": "number"}),
                dict({"label": gettext("# Truncates"),
                      "sort-method": "number"}),
                dict({"label": gettext("# DDL operations"),
                      "sort-method": "number"}),
                dict({"label": gettext("# Errors Caused By Deadlocks"),
                      "sort-method": "number"}),
                dict({"label": gettext("# Retries"),
                      "sort-method": "number"}),
                dict({"label": gettext("# Shared Blocks Cache Hit"),
                      "sort-method": "number"}),
                dict({"label": gettext("# Shared Blocks Read"),
                      "sort-method": "number"}),
                dict({"label": gettext("# Shared Blocks Dirtied"),
                      "sort-method": "number"}),
                dict({"label": gettext("# Shared Blocks Written"),
                      "sort-method": "number"}),
                dict({"label": gettext("# Time Spent Reading Blocks"),
                      "sort-method": "number"}),
                dict({"label": gettext("# Time Spent Writing Blocks"),
                      "sort-method": "number"}),
                dict({"label": gettext("Current Upstream connection Time"),
                      "sort-method": "number"}),
                dict({"label": gettext("Last Upstream Disconnection Time"),
                      "sort-method": "number"}),
                dict({"label":
                      gettext("LSN Requested to start Upstream Replication"),
                      "sort-method": "number"}),
                dict({"label": gettext("# Retries At Same LSN"),
                      "sort-method": "number"}),
                dict({"label": gettext("# Commits After Current Connection"),
                      "sort-method": "number"}),
            ],
        }),
    })
    if _id in predefined_tables_info:
        return predefined_tables_info[_id]

    return None


def nl2br(string, isAttr=False, isDefault=False):
    if isAttr:
        return string.replace('\n', '@@PEMEDBATBR@@\n')
    if isDefault:
        return string.replace('\n', '<br/>')
    return string.replace('\n', '@@PEMEDBBR@@\n')
