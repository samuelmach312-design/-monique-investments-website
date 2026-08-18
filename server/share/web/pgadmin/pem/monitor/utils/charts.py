##########################################################################
#
# Postgres Enterprise Manager
#
# Copyright (C) 2016 - 2025, EnterpriseDB Corporation. All rights reserved.
#
##########################################################################

"""PEM Monitoring Chart Utility functions"""

from . import SystemCharts
from flask_babel import gettext


class ChartType:
    BAR = 'B'
    PIE = 'P'
    TABLE = 'TB'
    TEXT = 'TE'
    LINE = 'L'
    PROBE_TBL = 'PT'
    CM_LINE = 'CL'
    CM_TBL = 'CT'
    GROUP_LINE = 'GL'
    ALERT_DETAILS = 'AD'
    ALERT_STATUS = 'AS'
    PGD_WORKERS = 'PW'
    AGENT_STATUS = 'AG'
    SERVER_STATUS = 'SS'
    ALERT_ERRORS = 'AE'


# Chart descriptions
SYSTEM_CHART_DESCRIPTIONS = {
    # Global Overview
    SystemCharts.GLOBAL_STATUS: gettext(
        "This bar graph provides an at-a-glance overview of the status of "
        "your PEM agents and servers."
    ),
    SystemCharts.AGENT_STATUS_INFO: gettext(
        "This table provides detailed information about the status of each "
        "individual agent:  \n"
        "A healthy agent displays a blue 'check' icon to the left of the "
        "agent name a down agent displays a red 'X' icon a unknown agent "
        "displays a yellow '!' icon.\n\n"
        "**Blackout:** Use the checkbox in this column to silence alerts "
        "from this agent and monitored servers. This may be desired during "
        "maintenance work for example.  \n"
        "**Name:** The name of the agent.  \n"
        "**Status:** The current state of the agent UP, DOWN or "
        "UNKNOWN.  \n"
        "**Alerts:** The number of current alerts triggered on the "
        "agent.  \n"
        "**Version:** The version number of the agent running on the "
        "host.  \n"
        "**Processes:** The number of processes running on the host.  \n"
        "**Threads:** The number of threads running on the host.  \n"
        "**CPU Utilization:** The average utilization of all CPU cores on "
        "the host.  \n"
        "**Memory Utilization:** The percentage of available RAM memory "
        "used on the host.  \n"
        "**Swap Utilization:** The percentage of available swap memory "
        "used on the host.  \n"
        "**Disk Utilization:** The percentage of total disk space used, "
        "for all disks on the host.\n\n"
        "Agents with 'DOWN' status or with Alerts may need attention"
    ),
    SystemCharts.SERVER_STATUS_INFO: gettext(
        "This table provides detailed information about the status of each "
        "individual server:\n\n"
        "A healthy server displays a blue 'check' icon to the left of the "
        "server name a down server displays a red 'X' icon a unknown server "
        "displays a yellow '!' icon.\n\n"
        "**Blackout:** Use the checkbox in this column to silence alerts "
        "from this server. This may be desired during maintenance work for "
        "example.  \n"
        "**Name:** The name of the server.  \n"
        "**Status:** The current state of the server UP, DOWN "
        "or UNKNOWN.  \n"
        "**Connections:** The current number of connections to the "
        "server.  \n"
        "**Alerts:** The number of current alerts triggered on the "
        "server.  \n"
        "**Version:** The Postgres version and build signature.\n\n"
        "Servers with 'DOWN' status or with Alerts may need attention."
    ),

    # Alerts
    SystemCharts.ALERTS_STATUS_INFO: gettext(
        "This table displays triggered alerts which include both PEM-d alerts "
        "and user-d alerts for all PEM-monitored hosts, servers, agents and "
        "database objects. This table will also display an alert if an agent "
        "or server is down.\n\n"
        "An alert level icon displays in red for a **High** severity "
        "alert, in orange for a **Medium** severity alert, and in yellow "
        "for a **Low** severity alert."
        "The caret-right icon in the table grid will expand to display "
        "detailed information and parameters of that alert when clicked."
        "\n\n"
        "**Alarm Type:** The alert severity.  \n"
        "**Object Description:** The description of the object that "
        "triggered the alert.  \n"
        "**Alert Name:** The name of the triggered alert.  \n"
        "**Value:** The current value of the object that triggered the "
        "alert.  \n"
        "**Database:** The name of the database to which the alert is "
        "associated (if any).  \n"
        "**Schema:** The name of the schema to which the alert is "
        "associated (if any).  \n"
        "**Package:** The name of the package to which the alert is "
        "associated (if any).  \n"
        "**Object:** The name of the object to which the alert is "
        "associated (if any).  \n"
        "**Alerting Since:** The date and time at which the alert "
        "triggered."
    ),
    SystemCharts.ALERTS_OVERVIEW: gettext(
        "This graph provides an overview of triggered alerts. The three bars "
        "on the left indicate the number of High, Medium and Low alerts for "
        "the selected object the rightmost bar indicates count of configured "
        "alerts which are not currently in an alert state. The vertical key "
        "on the left side of the graph provides an alert count."
    ),
    SystemCharts.ALERTS_DETAILS: gettext(
        "This table lists the currently triggered alerts for the selected "
        "object if opened from the global overview, the Alert Details table "
        "lists all of the currently triggered alerts for all monitored "
        "objects. Click a column heading to sort the table by the contents of "
        "a selected column click a second time to reverse the sort order. "
        "The table contains detailed information about each alert.\n\n"
        "An alert level icon displays in red for a **High** severity "
        "alert, in orange for a **Medium** severity alert, and in yellow "
        "for a **Low** severity alert.\n\n"
        "The caret-right icon in the table grid will expand to display "
        "detailed information and parameters of that alert when clicked.  \n"
        "**Ack'ed:** If checked then no notification will be sent till "
        "alert is cleared or unchecked again.  \n"
        "**Alert Type:** The severity of the alert.  \n"
        "**Name:** The name of the currently triggered alerts.  \n"
        "**Value:** The value of the metric that triggered the error, "
        "if applicable.  \n"
        "**Agent:** The name of the server triggering the error message, "
        "if applicable.  \n"
        "**Server:** The name of the server triggering the error message, "
        "if applicable.  \n"
        "**Database:** The name of the database on which the alert is "
        "associated, if applicable.  \n"
        "**Schema:** The name of the schema on which the alert is "
        "associated, if applicable.  \n"
        "**Package:** The name of the package on which the alert is "
        "associated, if applicable.  \n"
        "**Object:** The name of the monitored object on which the alert "
        "is associated, if applicable.  \n"
        "**Additional Params:** The parameters are displayed in this "
        "column, if the alert definition includes specified parameters.  \n"
        "**Additional Params Value:** The additional parameter values are "
        "displayed in this column, if the alert definition includes "
        "additional specified parameters.  \n"
        "**Alerting Since:** The date and time that the alert triggered."
    ),
    SystemCharts.ALERTS_ERRORS: gettext(
        "This table displays configuration-related errors  (eg. accidentally "
        "disabling a required probe, or improperly configuring an alert "
        "parameter).\n\n"
        "An alert indicator in the left-most column indicates that this is "
        "an Error.  \n"
        "**Alert Type:** The severity of the alert.  \n"
        "**Name:** The name of the alert.  \n"
        "**Value:** The value of the metric that triggered the error, if "
        "applicable.  \n"
        "**Agent:** The name of the server triggering the error message, "
        "if applicable.  \n"
        "**Server:** The name of the server triggering the error message, "
        "if applicable.  \n"
        "**Database:** The name of the database on which the alert is d, "
        "if applicable.  \n"
        "**Schema:** The name of the schema on which the alert is d, if "
        "applicable.  \n"
        "**Package:** The name of the package on which the alert is d, if "
        "applicable.  \n"
        "**Object:** The name of the monitored object on which the alert "
        "is d, if applicable.  \n"
        "**Error Message:** The condition that triggered the alert error."
        "  \n"
        "**Error Timestamp:** The date and time that the alert error "
        "triggered"
    ),

    # Database Analysis
    SystemCharts.DB_STRG: gettext(
        "This bar graph plots the relative size of the 5 largest tables and "
        "indexes that reside within the selected database.  The vertical key "
        "on the left side of the graph indicates the object size in megabytes."
    ),
    SystemCharts.DB_USER_ACTIVITY: gettext(
        "This graph plots the total and idle connections over the previous "
        "week:  \n"
        "The vertical key on the left side of the chart indicates the total "
        "connection count."
    ),
    SystemCharts.DB_CONN_OVERVIEW: gettext(
        "This graph provides a comparative display of the total and idle "
        "connections currently established with the server "
        "(when the most recent probe executed)."),
    SystemCharts.DB_TOP_TABLES: gettext(
        "This table provides a detailed analysis of the activity for each "
        "table that resides within the selected database. Click a column "
        "heading to sort the table by the values within the column click "
        "again to reverse the sort order.\n\n"
        "**Schema:** This column identifies the schema in which the table "
        "resides.  \n"
        "**Table Name:** This column identifies the name of the table.  \n"
        "**Scans:** The number of scans performed on the table.  \n"
        "**Rows Read:** The number of rows read from the specified table."
        "  \n"
        "**Index Scans:** The number of index scans performed on the "
        "specified table.  \n"
        "**Index Rows Read:** The number of rows read during index scans "
        "on the specified table.  \n"
        "**Rows Inserted:** The number of rows inserted into the specified "
        "table.  \n"
        "**Rows Updated:** The number of rows updated in the specified "
        "table.  \n"
        "**Rows Deleted:** The number of rows deleted from the specified "
        "table.  \n"
        "**Hot Rows Updated:** The number of hot row updates into the "
        "table when a hot row update occurs, the new row occupies the same "
        "page as the previous row.  \n"
        "**Total Rows:** The number of total rows in the table.  \n"
        "**Dead Rows:** The number of rows that have been deleted, but "
        "have not been reclaimed via a VACUUM command or the AUTOVACUUM "
        "process."
    ),
    SystemCharts.SLONY_EVENT_LAG: gettext(
        "This graph displays the number of event lags for the all the slony "
        "clusters associated to the selected database. The legends at the "
        "bottom of the graph shows each cluster name with a line color in "
        "the graph."),
    SystemCharts.SLONY_TIME_LAG: gettext(
        "This graph displays the time lag (in minutes) for the all the slony "
        "clusters associated to the selected database. The legends at the "
        "bottom of the graph shows each cluster name with a line color in "
        "the graph."
    ),

    # I/O Analysis
    SystemCharts.DB_IO_HIT_READ_STATS: gettext(
        "This graph displays the number of blocks read to and written from "
        "disk and memory buffers for the specified database over the course "
        "of the previous week:  \n"
        "The vertical key on the left side of the graph charts the block "
        "count."
    ),
    SystemCharts.IO_CHECK_POINT_ACTIVITY: gettext(
        "This graph displays the number of timed and untimed (requested) "
        "checkpoints written for the database over the last week. The "
        "vertical key on the left side indicates the number of timed "
        "checkpoints recorded.\n\n"
        "A checkpoint is a point in the transaction logging sequence at which "
        "all data files have been updated to reflect the information in the "
        "log, and data files are flushed to disk.  Checkpoints can be "
        "automatically generated, or forced by use of the CHECKPOINT "
        "command.\n\n"
        "A timed checkpoint occurs when the checkpoints_timeout parameter "
        "time limit is met.  An untimed (requested) checkpoint occur when the "
        "checkpoint_segments parameter is met, or when a superuser issues the "
        "CHECKPOINT command.  Frequent checkpointing can impose extra load on "
        "the server, but can reduce recovery time in the event of a crash or "
        "hardware failure."
    ),
    SystemCharts.IO_TOP5_SCANNED_TABLES: gettext(
        "This bar graph represents the comparative scans of the 5 tables "
        "(in order of number of sequential scans) that reside in the database "
        "a vertical key displays number of table scans."),
    SystemCharts.IO_TOP5_SCANNED_INDEXES: gettext(
        "This bar graph represents the comparative scans of the 5 indexes "
        "(in order of number of scans) that reside in the database a vertical "
        "key displays number of index scans."),
    SystemCharts.TOP_20_INDEX_ACTIVITY: gettext(
        "This table provides a detailed analysis of the activity for each "
        "index of a table that resides within the database.  Click a column "
        "heading to sort the table by the values within the column click "
        "again to reverse the sort order.\n\n"
        "**Schema:** The schema in which the table resides.  \n"
        "**Table Name:** The name of the table.  \n"
        "**Index Name:** The name of the index.  \n"
        "**Scans:** The number of scans performed on the table.  \n"
        "**Rows Read:** The number of rows read from the specified table."
        "  \n"
        "**Rows Fetched:** The number of rows fetched from the specified "
        "table.  \n"
        "**Blocks Read:** The number of blocks read from the specified "
        "table.  \n"
        "**Blocks Hit:** The number of blocks hit in the specified table."
    ),

    # Memory Analysis
    SystemCharts.SE_MEMORY_ACTIVITY: gettext(
        "This graph displays the previous week's activity on the server. "
        "Vertical keys on the left side of the graph indicate the actual "
        "block count for each value."
    ),
    SystemCharts.SE_MEMORY_CONFIGURATION: gettext(
        "This graph represents the current memory usage (in megabytes)."
    ),
    SystemCharts.HOST_MEMORY_ACTIVITY: gettext(
        "This graph plots the free and used memory on the host system over "
        "the last week."
    ),
    SystemCharts.HOST_MEMORY_INFORMATION: gettext(
        "This pie chart represents the free and available memory on the host "
        "system when the last probe was executed."
    ),

    # Object Activity Dashboard
    SystemCharts.TOP_5_LARGEST_TABLES: gettext(
        "This bar graph represents the comparative sizes of the 5 largest "
        "tables that reside in the database a vertical key displays the table "
        "size in megabytes."
    ),
    SystemCharts.TOP_5_LARGEST_INDEXES: gettext(
        "This bar graph represents the comparative sizes of the 5 largest "
        "indexes that reside in the database a vertical key displays the "
        "index size in megabytes."
    ),
    SystemCharts.OBJECT_ACTIVITIES: gettext(
        "This table provides a detailed analysis of the activity for each "
        "table that resides within the database. Click a column heading to "
        "sort the table by the values within the column click again to "
        "reverse the sort order.\n\n"
        "**Schema:** The schema in which the specified table resides.  \n"
        "**Object Name:** The name of the table.  \n"
        "**Scans:** The number of scans performed on the table.  \n"
        "**Rows Read:** The number of rows read from the specified table."
        "  \n"
        "**Index Scans:** The number of index scans performed on the "
        "specified table.  \n"
        "**Index Rows Read:** The number of rows read during index scans "
        "on the specified table.  \n"
        "**Rows Inserted:** The number of rows inserted into the specified "
        "table.  \n"
        "**Rows Updated:** The number of rows updated in the specified "
        "table."
        "  \n"
        "**Rows Deleted:** The number of rows deleted from the specified "
        "table.  \n"
        "**Hot Rows Updated:** The number of hot row updates into the "
        "table when a hot row update occurs, the new row occupies the same "
        "page as the previous row.  \n"
        "**Total Rows:** The number of total rows in the table.  \n"
        "**Dead Rows:** The number of rows that have been deleted, but "
        "have not been reclaimed via a VACUUM command or the AUTOVACUUM "
        "process."
    ),
    SystemCharts.OBJECT_STRG: gettext(
        "This table displays the schema objects that reside in the selected "
        "database. Click a column heading to sort the table data by the "
        "values within that column click again to reverse the sort order."
        "\n\n**Schema:** This column identifies the schema in which "
        "the object resides.  \n"
        "**Object:** Name column identifies the name of the schema object."
        "  \n"
        "**Object Type:** column identifies the type of schema object "
        "(Table or Index).  \n"
        "**Table Size:** The size of the table in megabytes (if "
        "applicable).  \n"
        "**Index Size:** The size of indexes associated with the specified "
        "in megabytes (if applicable).  \n"
        "**Total (MB):** The cumulative size (in megabytes) of the "
        "specified table and/or indexes and associated TOAST tables."
    ),

    # Operating System Dashboard
    SystemCharts.CPU_STATS: gettext(
        "This graph represents the percentage of the CPU used at a given "
        "point in time over the last week.  The vertical key on the left side "
        "of the graph indicates the percentage."
    ),
    SystemCharts.STRG_STATS: gettext(
        "Segments of this pie chart represent the free and used storage on "
        "the host."
    ),
    SystemCharts.PROCESS_STATS: gettext(
        "This graph displays the process count on the PEM agent host for the "
        "last week."
    ),
    SystemCharts.MEMORY_STATS: gettext(
        "This graph displays the memory usage on the monitored server for the "
        "last week."
    ),
    SystemCharts.DISK_UTILIZATION: gettext(
        "This graph represents the percentage of the disk space used at a "
        "given point in time over the last week. The vertical key on the left "
        "side of the graph indicates the used space percentage."
    ),
    SystemCharts.IO_STATS: gettext(
        "This graph displays the amount of data read from and written to "
        "disk(s)."
    ),
    SystemCharts.HOST_DETAILS: gettext(
        "This table displays information about the file systems that reside "
        "on the system:\n\n"
        "**Size (GB):** The size of the file system.  \n"
        "**Used (GB):** The amount of the file system that is currently "
        "storing information.  \n"
        "**Available (GB):** The amount of space available on the file "
        "system.  \n"
        "**%% Used:** The percentage of the total storage space in use."
        "  \n**Mounted On:** The directory or drive letter on which the "
        "file system is mounted."
    ),
    SystemCharts.NET_PACKET_STATS: gettext(
        "This graph displays the number of packets sent and received across "
        "the network over the last week.  The vertical key on the left side "
        "of the graph indicates the packet count."
    ),
    SystemCharts.NET_TRAFFIC_STATS: gettext(
        "This graph displays the amount of data transferred across the "
        "network over the last week.  The vertical key on the left side of "
        "the graph indicates the amount of data transferred (in kilobytes)."
    ),

    # Server Analysis Dashboard
    SystemCharts.DATABASES_SIZE: gettext(
        "This graph displays the size (in Megabytes) of the largest databases "
        "that reside on the monitored server.  The legends at the bottom of "
        "the graph shows each database name with a line color in the graph."),
    SystemCharts.TBLSPACES_SIZE: gettext(
        "This graph displays the size (in Megabytes) of the largest "
        "tablespaces that reside on the monitored server. The legends at the "
        "bottom of the graph shows tablespace name with a line color in the "
        "graph."),
    SystemCharts.SHARED_BUFFER: gettext(
        "This graph compares the number of data blocks found in the shared "
        "memory cache with the number of blocks read from disk:\n\n"
        "The vertical key on the left side of the graph indicates a block "
        "count.  \n A high hit-to-miss ratio indicates an efficiently "
        "configured memory cache."
    ),
    SystemCharts.USER_ACTIVITY: gettext(
        "This graph displays connection statistics gathered over the last "
        "week. The vertical key on the left side of the graph indicates the "
        "total user connections."
    ),
    SystemCharts.CONN_OVERVIEW: gettext(
        "This pie graph compares the currently total connections to the "
        "currently idle connections."
    ),
    SystemCharts.DISK_INFORMATION: gettext(
        "This graph indicates the number of 8KB blocks read from disk(s), and "
        "the number of 8KB blocks written to disk(s) over the last week."
    ),
    SystemCharts.ROWS_ACTIVITY: gettext(
        "This graph plots row activity on tables stored on the server over "
        "the past week."
    ),
    SystemCharts.COMMITS_ROLLBACKS: gettext(
        "This graph displays the number of transactions committed and rolled "
        "back in the selected server within the last week:\n\n"
        "The vertical key on the left side of the graph indicates the number "
        "of transactions committed."
    ),
    SystemCharts.DATABASES_ANALYSIS: gettext(
        "This table displays the monitored databases that reside on the "
        "server, and the statistics gathered for each database. Click a "
        "column heading to sort the table by the data displayed in the column "
        "click again to reverse the sort order:\n\n"
        "**Database:** The database name.  \n"
        "**Connections:** The number of current connections to the "
        "database.  \n"
        "**TX Committed:** The number of transactions committed to the "
        "database within the last week.  \n"
        "**TX Rolled Back:** The number of transactions rolled back within "
        "the last week.  \n"
        "**Blocks Hit:** The number of blocks hit in the cache "
        "(in megabytes) within the last week.  \n"
        "**Blocks Read:** The number of blocks read from memory "
        "(in megabytes) within the last week.  \n"
        "**Tuples Fetched:** The number of tuples fetched within the last "
        "week.  \n"
        "**Tuples Returned:** The number of tuples returned within the "
        "last week.  \n"
        "**Tuples Inserted:** The number of tuples inserted into the "
        "database within the last week.  \n"
        "**Tuples Updated:** The number of tuples updated in the database "
        "within the last week.  \n"
        "**Tuples Deleted:** The number of tuples deleted from the "
        "database within the last week."
    ),

    # Session Activity Dashboard
    SystemCharts.SESSION_WORK_LOAD: gettext(
        "This table provides information about the current session workload "
        "for the server.  Click a column heading to sort the table data by "
        "the selected column click the heading a second time to reverse the "
        "sort order. The Session Workload table displays the following "
        "information:\n\n"
        "**Session ID:** The process identifier for the session.  \n"
        "**User Name:** The (role) name of the user that established the "
        "client connection to the server.  \n"
        "**Source:** This column displays the IP address and port number "
        "of the client.  \n"
        "**Database Name:** The name of the database to which the client "
        "is connected.  \n"
        "**Waiting:** This column displays Yes if the session is waiting "
        "for a lock No if the session is not waiting for a lock.  \n"
        "**Backend Start:** The date and time that the client established "
        "a connection to the server.  \n"
        "**Transaction Start:** The date and time that the current "
        "transaction started, if applicable.  \n"
        "**Query Start:** The date and time that the current query "
        "started, if applicable.  \n"
        "**Memory Usage:** Memory used (in megabytes) by that session.  \n"
        "**Swap Usage:** Swap used (in megabytes) by that session.  \n"
        "**CPU Usage:** CPU used (in percentage) by that session.  \n"
        "**IO Reads (#bytes):** Number of IO blockes (in bytes) read by "
        "that session.  \n"
        "**IO Writes (#bytes):** Number of IO blockes (in bytes) write by "
        "that session"
    ),
    SystemCharts.SESSION_LOCKS_ACTIVITY: gettext(
        "This table displays a list of locks held by processes on the server. "
        "Click a column heading to sort the table data by the selected column "
        "click the heading a second time to reverse the sort order. The "
        "Session Lock Activity table displays the following information:  \n"
        "  \n**Session ID:** The process ID for the session.  \n"
        "**User Name:** The name of the user holding (or waiting for) the "
        "lock.  \n"
        "**Source:** This column displays the IP address and port number "
        "of the client.  \n"
        "**Database Name:** The name of the database to which the client "
        "is connected.  \n"
        "**Blocked:** This column indicates if the lock request is blocked "
        "by another lock.  \n"
        "**Blocked By:** This column specifies the session ID of the "
        "session that is holding the lock.  \n"
        "**Lock Type:** The type of lock that is held by the client. "
        "Lock Type may be:  \n"
        "-  *advisory:* a user-d lock created by pg_advisory_lock() or "
        "pg_advisory_lock_shared(),  \n"
        "-  *extend:* a lock held while extending a table or index,  \n"
        "-  *object:* a lock held on a database object,  \n"
        "-  *page:* a lock held on a page (within the shared buffer "
        "cache),  \n"
        "-  *relation:* a lock held on the metadata describing a table, "
        "view, or sequence (to prevent another session from altering the "
        "table, view, or sequence),  \n"
        "-  *transactionid:* a lock held on a transaction ID (one "
        "session typically waits for another transaction to complete by "
        "waiting on the other session's transaction ID),  \n"
        "-  *tuple:* lock held on a tuple (typically, a tuple which has "
        "been inserted, updated, or deleted, but not yet committed),  \n"
        "-  *userlock:* a user-d lock created with the LOCK statement,"
        "  \n"
        "-  *virtualxid:* a lock identified by a virtual transaction ID,"
        "  \n"
        "**Object ID:** The OID of the relation, or NULL if the object is "
        "not a relation (of part of a relation).  \n"
        "**Mode:** The name of the lock mode help (or sought) by the "
        "process.  \n"
        "**Transaction Start:** The date and time that the transaction "
        "started."
    ),

    # Session Wait Dashboard
    SystemCharts.NUM_SESSION_WAITS: gettext(
        "This graph displays the 5 most frequently encountered wait events, "
        "per Advanced Server session."),
    SystemCharts.SESSOIN_TIME_WAITS: gettext(
        "This graph displays the 5 wait events that consume the most time, "
        "per Advanced Server session."),
    SystemCharts.SESSION_WAIT_DETAILS: gettext(
        "This table lists the current system wait events for the selected "
        "server. Click a column heading to sort the table by the column data "
        "click again to reverse the sort order.\n\n"
        "The table displays:  \n"
        "**User:** The name of the user that encountered the wait.  \n"
        "**Wait Name:** The name of the of wait event.  \n"
        "**Wait Count:** The total number of waits encountered by the user."
        "  \n"
        "**Time (ms):** Displays the number of milliseconds that the user "
        "waited for the specified event.  \n"
        "**Wait Time (%%):** The percentage of the total wait time "
        "consumed by the specified wait event."
    ),

    # Storage Analysis Dashboard
    SystemCharts.DATABASES_STRG_OVERVIEW: gettext(
        "This graph shows the relative size of monitored databases stored on "
        "the server.  The key (located below the chart) matches the database "
        "name to the respective color on the chart."),
    SystemCharts.TBLSPACES_STRG_OVERVIEW: gettext(
        "This graph shows the relative size of tablespaces on the server. "
        "The key (located below the chart) matches the tablespace name to the "
        "respective color on the chart."),
    SystemCharts.HOST_STRG_OVERVIEW: gettext(
        "This graph represents the amount of used and free storage space on "
        "the server as of the last probe execution."),
    SystemCharts.DATABASES_STRG_DETAILS_TBL: gettext(
        "This table displays the size of each database stored on the server. "
        "Click a column heading to sort the table by the specified column "
        "click again to reverse the sort order. The table includes:\n\n"
        "**Database Name:** The name of the database.  \n"
        "**Database Size (MB):** The size of the database in megabytes."
        "  \n**Tablespace Name:** The name of the default tablespace "
        "assigned to the database."
    ),
    SystemCharts.TBLSPACES_STRG_DETAILS_TBL: gettext(
        "This table lists the name and size (in megabytes) of each tablespace "
        "d for the server. Click a column heading to sort the table by the "
        "specified column click again to reverse the sort order.\n\n"
        "The table includes:  \n"
        "**Tablespace Name:** The name of the tablespace.  \n"
        "**Tablespace Size (MB):** The size of the tablespace in megabytes."
    ),
    SystemCharts.HOST_STRG_DETAILS_TBL: gettext(
        "This table displays information about the file systems that reside "
        "on the system that hosts the monitored server:\n\n"
        "**File System:** The name of the file system.  \n"
        "**Size (GB):** The size of the file system.  \n"
        "**Used (GB):** The amount of the file system that is currently "
        "storing information.  \n"
        "**Available (GB):** The amount of space available on the file "
        "system.  \n"
        "**%% Used:** The percentage of the total storage space in use."
        "  \n**Mounted On:** The directory or drive letter on which the "
        "file system is mounted."
    ),

    # System Wait Dashboard
    SystemCharts.NUM_SYS_WAITS: gettext(
        "This graph displays the 5 most frequently encountered wait events "
        "for the selected Advanced Server database."),
    SystemCharts.SYS_WAIT_TIME: gettext(
        "This graph displays the 5 wait events that consume the most time for "
        "the selected Advanced Server database."),
    SystemCharts.SYS_WAIT_DETAILS_TBL: gettext(
        "This table lists the current system wait events for the selected "
        "server.  Click a column heading to sort the table by the column data "
        "click again to reverse the sort order.\n\n"
        "The table displays:  \n"
        "**Event:** The name of the wait event.  \n"
        "**Wait Count:** This column contains the number of times that the "
        "wait event occurred.  \n"
        "**Percentage of Total:** The percentage of the total wait count "
        "consumed by this event.  \n"
        "**Time Waited (ms):** Displays the number of milliseconds that "
        "the server waited for the event.  \n"
        "**Percentage of Time Waited:** "
        "Displays the percentage of the total "
        "wait time consumed by this event.  \n"
        "**Average Wait Time (ms):** The average wait time for this event."
    ),

    # Streaming Replication Dashboard
    SystemCharts.WAL_ARCHIVE_STATUS: gettext(
        "This graph plots the number of WAL files, the number of WAL archives "
        "done and the number of WAL archives pending over the previous week."),
    SystemCharts.WAL_SEGMENT_LAG: gettext(
        "This graph displays the number of segment lag for all the replica "
        "nodes associated to the selected server. The legends at the bottom "
        "of the graph shows each replica node (as hostname:port) with a line "
        "color in the graph."
    ),
    SystemCharts.WAL_PAGE_LAG: gettext(
        "This graph displays the number of page lag for all the replica nodes "
        "associated to the selected server. The legends at the bottom of the "
        "graph shows each replica node (as hostname:port) with a line color in"
        " the graph."),
    SystemCharts.REPLICATION_TIME_LAG: gettext(
        "This graph plots the time lag (in minutes) between the selected "
        "server and it's primary node in streaming replication."),
    SystemCharts.BDR_NODE_SUMMARY: gettext(
        "This table show node summary."),
    SystemCharts.BDR_ND_REP_RATES_REPLAY_LAG_SEC: gettext(
        "This graph shows node replication lag (seconds)."),
    SystemCharts.BDR_ND_REP_RATES_REPLAY_LAG_BYTE: gettext(
        "This graph shows node replication lag (bytes)."),
    SystemCharts.BDR_ND_REP_RATES_APPLY_RATE: gettext(
        "This graph shows node replication apply rate."),
    SystemCharts.BDR_NODE_SLOT_REPLAY_LAG_SECONDS: gettext(
        "This graph shows node slots replay lag (Seconds)."),
    SystemCharts.BDR_NODE_SLOT_REPLAY_LAG_BYTES: gettext(
        "This graph shows node slots replay lag (bytes)."),
    SystemCharts.BDR_GLOBAL_LOCKS: gettext(
        "This graph shows current global locks."),
    SystemCharts.BDR_GP_SUB_SUMMARY_SUB_LAG_SEC: gettext(
        "This graph shows group subscription lag (Seconds)."),
    SystemCharts.BDR_GROUP_VERSION_DETAILS: gettext(
        "This table shows group version details."),
    SystemCharts.BDR_GROUP_RAFT_DETAILS: gettext(
        "This table shows group raft details."),
    SystemCharts.BDR_GP_REP_SL_WRITE_LAG_SEC: gettext(
        "This graph shows replication slot write lag (seconds) "
        "in BDR group"),
    SystemCharts.BDR_GP_REP_SL_REPLAY_LAG_SEC: gettext(
        "This graph shows replication slot replay lag (seconds) "
        "in BDR group"),
    SystemCharts.BDR_GP_REP_SL_FLUSH_LAG_SEC: gettext(
        "This graph shows replication slot flush lag (seconds) "
        "in BDR group"),
    SystemCharts.BDR_GP_REP_SL_SENT_LAG: gettext(
        "This graph shows replication slot sent lag (bytes) "
        "in BDR group"),
    SystemCharts.BDR_GP_REP_SL_WRITE_LAG: gettext(
        "This graph shows replication slot write lag (bytes) "
        "in BDR group"),
    SystemCharts.BDR_GP_REP_SL_FLUSH_LAG: gettext(
        "This graph shows replication slot flush lag (bytes) "
        "in BDR group"),
    SystemCharts.BDR_GP_REP_SL_REPLAY_LAG: gettext(
        "This graph shows replication slot replay lag (bytes) "
        "in BDR group"),
    SystemCharts.BDR_WORKERS: gettext(
        "This table shows worker details in BDR node."),
    SystemCharts.BDR_GROUP_CAMO_DETAILS: gettext(
        "This table shows group camo details."),
    SystemCharts.BDR_CONFLICT_HISTORY_SUMMARY: gettext(
        "This graph shows number of conflicts occurred per hour "
        "for each conflict type in BDR node."),
    SystemCharts.BDR_STAT_RELATIONS: gettext(
        "This table shows statistics for each relation in BDR node."),
    SystemCharts.BDR_STAT_SUBSCRIPTIONS: gettext(
        "This table shows statistics for each subscription in BDR node."),
}
