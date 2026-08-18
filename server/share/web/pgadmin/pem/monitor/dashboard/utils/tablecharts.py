##########################################################################
#
# Postgres Enterprise Manager
#
# Copyright (C) 2016 - 2025, EnterpriseDB Corporation. All rights reserved.
#
##########################################################################

"""Generates data for the barcharts in the dashboard."""

import random
from flask import url_for
from xml.etree.ElementTree import Element, SubElement
from pgadmin.pem.misc.error import PEMChartStatus, prettify
from pgadmin.pem.misc.import_helper import quote
from .html import get_params
from pgadmin.pem.utils import pem_connection, get_restricted_objects_clause, \
    table_sys_clause
from pgadmin.utils.ajax import make_json_response
from pgadmin.pem.misc.error import error_return, PEMErrorType
from flask_babel import gettext
from ..utils import DashboardTransaction, create_dashboard_transaction_id
from .generate_table_chart_data import generate_json_for_table_chart
from ..helpers.chart import statusColor, alertColor
from html import escape

TABLE_ID = {
    'AGENT_STATUS': 2,
    'SERVER_STATUS': 3,
    'ALERT_STATUS': 4,
    'ALERT_DETAILS': 6,
    'ALERT_ERRORS': 7,
    'BDR_NODE_SUMMARY': 104,
    'BDR_WORKERS': 105,
    'BDR_WORKER_ERRORS': 106,
    'SESSION_WORKLOAD': 62,
    'IO_OBJECT_INDEX_IO': 79
}


@pem_connection
def table_global_overview_agent_status(
    sort_index=3, sort_direction=0, reload=30000, trans_id=0, pem_conn=None
):
    query = """
    WITH agent_status AS (
        SELECT
            pa.id AS id, pa.alert_blackout AS blackout, pa.description AS name,
            pa.version AS version,
            CASE
            WHEN (
                pah.agent_id IS NOT NULL AND
                pah.last_heartbeat < now() AND
                pah.last_heartbeat > (
                    now() - (
                        (pa.heartbeat_tolerance + 15) * '1 second'::interval
                        )
                )
            ) THEN 'UP'
            WHEN (
                pah.agent_id IS NOT NULL AND
                pah.last_heartbeat < (
                    now() - (
                        (pa.heartbeat_tolerance + 15) * '1 second'::interval
                        )
                )
            ) THEN 'DOWN'
            ELSE 'UNKNOWN'
            END AS status
        FROM
            pem.agent pa
            LEFT OUTER JOIN pem.agent_heartbeat pah ON (pa.id = pah.agent_id)
        WHERE
            pa.active = TRUE
    )
    SELECT
        id, blackout AS "Blackout", name AS "Name", status AS "Status", (
            SELECT count(*) FROM pem.alert pal
            LEFT OUTER JOIN pem.alert_status pas ON (pal.id = pas.alert_id)
            WHERE
                pal.agent_id = pa.id AND pal.enabled=true AND
                pal.acknowledged=false AND
                COALESCE(pal.error_message, '') = '' AND
                pas.current_state IS NOT NULL
        ) AS "Alerts",
        version AS "Version",
        CASE
        WHEN status = 'UP' THEN os.total_process_count ELSE 0 END
        AS "Processes",
        CASE
        WHEN status = 'UP' THEN os.total_thread_count ELSE 0
        END AS "Threads",
        CASE
            WHEN status = 'UP' THEN
                (SELECT
                    CASE WHEN avg(load_percentage) = 0 THEN 0
                        ELSE round(avg(load_percentage)::numeric, 2)
                    END
                FROM pemdata.cpu_usage WHERE agent_id = pa.id)
            ELSE 0
        END AS "CPU Utilization (%%)",
        CASE
            WHEN status = 'UP' THEN (
                SELECT
                    CASE
                    WHEN total_ram_memory_mb = 0 OR free_ram_memory_mb = 0
                        THEN 0
                    ELSE round((100 - (
                        free_ram_memory_mb::numeric / total_ram_memory_mb
                    ) * 100)::numeric, 2)
                    END
                FROM pemdata.memory_usage WHERE agent_id = pa.id
            )
            ELSE 0
        END AS "Memory Utilization (%%)",
        CASE
        WHEN status = 'UP' THEN (
            SELECT
                CASE
                WHEN total_swap_memory_mb = 0 OR free_swap_memory_mb = 0
                    THEN 0
                ELSE round((
                    100 - (
                        free_swap_memory_mb::numeric / total_swap_memory_mb
                    ) * 100
                )::numeric, 2)
                END
            FROM pemdata.memory_usage WHERE agent_id = pa.id
        )
        ELSE 0
        END AS "Swap Utilization (%%)",
        CASE
        WHEN status = 'UP' THEN (
            SELECT CASE
                WHEN sum(size_mb) > 0
                THEN round((
                    sum(space_used_mb)::numeric / sum(size_mb) * 100
                )::numeric, 2)
                ELSE 0
                END
            FROM pemdata.disk_space WHERE agent_id = pa.id AND size_mb > 0
        )
        ELSE 0
        END AS "Disk Utilization (%%)"
    FROM
        agent_status AS pa
        LEFT OUTER JOIN pemdata.os_statistics os ON (pa.id = os .agent_id)
    ORDER BY (%s)::int4"""

    if (sort_direction is not None and sort_direction == 1):
        query += ' DESC'

    sort_index = int(sort_index) if (sort_index is not None) else sort_index
    if (sort_index is None or sort_index == '' or sort_index < 3):
        sort_index = 3  # default "Name"

    params = [sort_index]

    with DashboardTransaction(
        trans_id, pem_conn.conn_id, -1, random.randint(1, 9999999)
    ):
        status, res = pem_conn.execute_dict(query, params)

    if not status:
        error_return(
            gettext("Error fetching agent status!\nERROR: {0}".format(res)),
            e_type=PEMErrorType.JSON
        )

    result = generate_json_for_table_chart(res, 'agent_status',
                                           TABLE_ID['AGENT_STATUS'])
    result['timeout'] = reload
    return make_json_response(data=result)


@pem_connection
def table_global_overview_server_status(
    sort_index=3, sort_direction=0, reload=30000, trans_id=0, pem_conn=None
):
    query = """
WITH server_status AS (
    SELECT
        ps.id AS server_id, pa.id AS agent_id, ps.alert_blackout AS blackout,
        ps.description AS name, (
            CASE WHEN ps.is_remote_monitoring = true THEN 'Yes' ELSE 'No' END
        ) AS remotely_monitored,
        CASE
            WHEN pa.active IS NOT NULL AND pa.active AND
                psh.last_heartbeat IS NOT NULL AND
                psh.last_heartbeat < now() AND
                psh.last_heartbeat > (
                    now() - (
                        (pa.heartbeat_tolerance + 15) * '1 second'::interval
                        )
                )
                THEN 'UP'
            WHEN pa.active IS NOT NULL AND pa.active AND
                pah.last_heartbeat IS NOT NULL AND
                pah.last_heartbeat < now() AND
                pah.last_heartbeat > (
                    now() - (
                        (pa.heartbeat_tolerance + 15) * '1 second'::interval
                        )
                ) AND
                psh.last_heartbeat IS NOT NULL AND
                psh.last_heartbeat < (
                    now() - (
                        (pa.heartbeat_tolerance + 15) * '1 second'::interval
                        )
                )
                THEN 'DOWN'
            WHEN pasb.agent_id is NULL
                THEN 'UNMANAGED'
            ELSE 'UNKNOWN'
        END AS status
    FROM
        pem.server ps
        LEFT OUTER JOIN pem.server_heartbeat psh ON (ps.id = psh.server_id)
        LEFT OUTER JOIN pem.agent_server_binding pasb ON (
            ps.id = pasb.server_id
        )
        LEFT OUTER JOIN pem.agent pa ON (
            pasb.agent_id = pa.id AND psh.agent_id = pa.id
        )
        LEFT OUTER JOIN pem.agent_heartbeat pah ON (
            pah.agent_id = pasb.agent_id
        )
    WHERE
        ps.active = true
)
SELECT
    server_id, blackout AS "Blackout", name AS "Name", status AS "Status",
    CASE
        WHEN status = 'UP' THEN
            (SELECT sum(pds.numbackends) FROM pemdata.database_statistics pds
                WHERE pds.server_id = s.server_id)
        ELSE 0
    END AS "Connections",
    CASE
        WHEN status = 'UP' THEN (
            SELECT count(pa.id) FROM pem.alert pa
            LEFT JOIN pem.alert_status pas ON (pa.id = pas.alert_id)
            WHERE pa.server_id = s.server_id AND pa.enabled AND
                pas.current_state IS NOT NULL AND
                pa.acknowledged = false AND
                COALESCE(pa.error_message, '') = ''
        )
        ELSE 0
    END AS "Alerts", (
        SELECT version_string FROM pemdata.server_info
        WHERE server_id=s.server_id
    ) AS "Version", remotely_monitored AS "Remotely Monitored?",
    agent_id
FROM
    server_status s
    LEFT OUTER JOIN (
       SELECT value AS config_value FROM pem.config c
       WHERE param = 'show_unmanaged_servers'
    ) c ON c.config_value='f'
WHERE s.status != 'UNMANAGED' OR c.config_value IS NULL
ORDER BY (%s)::int4"""

    if (
        sort_direction != '' and sort_direction is not None and
        sort_direction == 1
    ):
        query += ' DESC'

    sort_index = int(sort_index) if sort_index is not None else sort_index
    if (sort_index == '' or sort_index is None or sort_index < 3):
        sort_index = 3  # default "Name"

    params = [sort_index]

    with DashboardTransaction(
        trans_id, pem_conn.conn_id, -1, random.randint(1, 9999999)
    ):
        status, res = pem_conn.execute_dict(query, params)

    if not status:
        error_return(
            gettext("Error fetching server status!\nERROR: {0}".format(res)),
            e_type=PEMErrorType.JSON
        )

    result = generate_json_for_table_chart(res, 'server_status',
                                           TABLE_ID['SERVER_STATUS'])
    result['timeout'] = reload
    return make_json_response(data=result)


@pem_connection
def table_global_overview_alerts_status(
    sort_index=3, sort_direction=0, reload=30000, trans_id=0, pem_conn=None
):
    result = {}

    query = """
SELECT
    pal.id,
    (
        CASE
        WHEN pas.current_state = 'HIGH' THEN 'High'
        WHEN pas.current_state = 'MEDIUM' THEN 'Medium'
        WHEN pas.current_state = 'LOW' THEN 'Low'
        END
    ) "Alarm Type",
    (CASE WHEN pt.object_type != 50
        THEN COALESCE(ps.description, pa.description, 'N/A'::text)
    ELSE 'N/A'::text END) AS "Object Description",
    pal.name AS "Alert Name", (
        CASE
        WHEN COALESCE(pas.display_value, '')::text != '' THEN pas.display_value
        ELSE pem.unit_converter(pas.current_value, pt.threshold_unit)
        END
    ) AS "Value",
    pal.database_name AS "Database",
    pal.schema_name AS "Schema",
    pal.package_name AS "Package",
    pal.object_name AS "Object",
    to_char(
        pas.current_state_since, 'YYYY-MM-DD HH24:MI:SS'
    )::timestamp AS "Alerting Since",
    pal.name AS "Alert Name", pal.server_id, pal.agent_id, ps.description,
    pa.description, pt.object_type, ppt.display_name
FROM
    pem.alert pal
    LEFT JOIN pem.alert_template pt ON (pt.id = pal.template_id)
    LEFT JOIN pem.probe_target_type ppt ON (pt.object_type = ppt.id)
    LEFT JOIN pem.alert_status pas ON (pal.id = pas.alert_id)
    LEFT JOIN pem.server ps ON (pal.server_id = ps.id)
    LEFT JOIN pem.agent pa ON (pal.agent_id = pa.id)
WHERE

(NOT (pa.id IS NULL AND ps.id IS NULL) AND
    (pas.current_state IS NOT NULL) AND
    pal.enabled AND NOT pal.acknowledged AND
    COALESCE(pal.error_message, '') = '' AND
    ((ps.active AND NOT ps.alert_blackout) OR
    (pa.active AND NOT pa.alert_blackout)))
OR
(
    pal.agent_id = -1 AND
    pas.current_state IS NOT NULL AND
    pal.enabled=true AND pal.acknowledged=false AND
    COALESCE(pal.error_message, '') = ''
)
ORDER BY (%s)"""

    if (
        sort_direction != '' and sort_direction is not None and
        sort_direction == 1
    ):
        query += ' DESC'

    sort_index = int(sort_index) if sort_index is not None else sort_index
    if (sort_index == '' or sort_index is None or sort_index < 3):
        sort_index = 3  # default "Name"

    params = [sort_index]

    with DashboardTransaction(
        trans_id, pem_conn.conn_id, -1, random.randint(1, 9999999)
    ):
        status, res = pem_conn.execute_dict(query, params)

    if not status:
        error_return(
            gettext("Error fetching alert status!\nERROR: {0}".format(res)),
            e_type=PEMErrorType.JSON
        )

    result = generate_json_for_table_chart(res, 'alert_status',
                                           TABLE_ID['ALERT_STATUS'])
    result['timeout'] = reload
    return make_json_response(data=result)


@pem_connection
def table_alerts_details(
    agent_id=None, server_id=None, database=None, schema=None,
    show_system_objects=None, sort_index=3, sort_direction=0, reload=30000,
    trans_id=0, pem_conn=None
):
    result = {}
    params = []
    show_ack_query = ""
    sub_query = ""
    sub_query_params = []
    # Alert page at schema level
    if (
        server_id is not None and server_id != 0 and schema is not None and
        database is not None
    ):
        # make where clause for other metrices
        where_clause1 = "pa.server_id = (%s)::int4 AND " \
            "pa.database_name = (%s)::text AND pa.schema_name = (%s)::text AND"
        # If page_type = 1 => get description from pem.server
        page_type = 1
        params = [server_id, database, schema]
        sub_query_params = [400, server_id, database, schema]
        sub_query = " AND cf.level = (%s)::int4 " \
            "AND cf.objid = (%s)::int4 AND database = (%s)::text " \
            "AND schema = (%s)::text"
    # Alert page at database level
    elif server_id is not None and server_id != 0 and database is not None:
        # If page_type = 1 => get description from pem.server
        page_type = 1
        params = [server_id, database]

        # make where clause for other metrices
        # Apply schema restriction clause only when schema_name field is not
        # NULL and schema restriction exists in database_option
        with DashboardTransaction(
            trans_id, pem_conn.conn_id, -1, random.randint(1, 9999999)
        ):
            ret_val, restricted_objects_clause, rest_param = \
                get_restricted_objects_clause(
                    pem_conn, '(%s)', 'pa.schema_name', 1, server_id, database
                )

        if ret_val == 0 and restricted_objects_clause != '':
            restricted_objects_clause = "AND (pa.schema_name IS NULL OR " + \
                restricted_objects_clause + ")"
        if rest_param is not None and rest_param != '':
            params.append(rest_param)

        where_clause1 = " pa.server_id = (%s)::int4 AND " \
            "pa.database_name = (%s)::text " + \
            restricted_objects_clause + " AND "
        sub_query_params = [300, server_id, database]
        sub_query = " AND cf.level = (%s)::int4 " \
            "AND cf.objid = (%s)::int4 AND database = (%s)::text"
    # Alert page at agent level
    elif agent_id is not None and agent_id != 0 and \
            (server_id is None or server_id == 0):
        # make where clause for other metrices
        where_clause1 = 'pa.agent_id = (%s)::int4 AND '
        # If page_type = 2 => get description from pem.avail_agents
        page_type = 2
        params = [agent_id]
        sub_query_params = [100, agent_id]
        sub_query = " AND cf.level = (%s)::int4 AND cf.objid = (%s)::int4"
    elif server_id is not None and server_id != 0:
        # Alert page at server level
        # If page_type = 1 => get description from pem.server
        page_type = 1
        # make where clause for other metrices
        params = [server_id]

        with DashboardTransaction(
            trans_id, pem_conn.conn_id, -1, random.randint(1, 9999999)
        ):
            ret_val, restricted_objects_clause, rest_param = \
                get_restricted_objects_clause(
                    pem_conn, '(%s)', 'pa.database_name', 0, server_id
                )

        if ret_val and restricted_objects_clause != '':
            restricted_objects_clause = \
                " AND (pa.database_name IS NULL OR " + \
                restricted_objects_clause + ")"
        if rest_param is not None and rest_param != '':
            params.append(rest_param)

        where_clause1 = " pa.server_id = (%s)::int4 " + \
            restricted_objects_clause + " AND "
        sub_query_params = [200, server_id]
        sub_query = " AND cf.level = (%s)::int4 AND cf.objid = (%s)::int4"
    # Alert page at global level
    else:
        # make where clause for other metrices
        where_clause1 = ''
        # If page_type = 0 => get description from pem.server and
        # pem.avail_agents both
        page_type = 0
        params = []
        sub_query_params = [50]
        sub_query = " AND cf.level = (%s)::int4"

    # Whether we should display ack'ed column or not depending on the config
    query = "SELECT showackalerts FROM pem.chart_config cf " \
        "JOIN pem.chart c ON cf.cid = c.id AND " \
        "LOWER(c.name) = 'alerts details' " \
        "WHERE cf.uid = (" \
        "SELECT u.usesysid FROM pg_catalog.pg_user u " \
        "WHERE u.usename = current_user)" + sub_query

    status, results = pem_conn.execute_dict(query, sub_query_params)
    if not status:
        error_return(
            gettext(
                "Error fetching alert details!\nERROR: {0}".format(results)),
            e_type=PEMErrorType.JSON
        )

    if 'rows' in results and len(results['rows']) > 0:
        if results['rows'][0]['showackalerts'] is False:
            show_ack_query = " AND pa.acknowledged=false"

    sys_objects_clause = table_sys_clause('pa', True if database else False)

    # Get description from pem.server
    if page_type == 1:
        query = """
SELECT
    pa.id,
    pa.acknowledged AS "Ack'ed", (
        CASE
        WHEN pas.current_state = 'HIGH' THEN 'High'
        WHEN pas.current_state = 'MEDIUM' THEN 'Medium'
        WHEN pas.current_state = 'LOW' THEN 'Low'
        END
    ) "Alert Type",
    pa.name AS "Name", (
        CASE
        WHEN COALESCE(pas.display_value, '')::text != '' THEN pas.display_value
        ELSE pem.unit_converter(pas.current_value, pat.threshold_unit)
        END
    ) AS "Value",
    pa.agent_id AS "Agent ID", (
        -- This dashboard is at server level, so setting the agent
        -- description as ''.
        CASE WHEN pat.object_type != 50 THEN '' ELSE 'N/A'::text END
    ) AS "Agent",
    pa.server_id AS "Server ID", (
        CASE
        WHEN pat.object_type != 50 THEN ps.description
        ELSE 'N/A'::text
        END
    ) AS "Server",
    pa.database_name AS "Database",
    pa.schema_name AS "Schema",
    pa.package_name AS "Package",
    pa.object_name AS "Object",
    to_char(
        pas.current_state_since, 'YYYY-MM-DD HH24:MI:SS'
    )::timestamp AS "Alerting Since",
    pat.object_type AS "Object Type", ppt.display_name AS "Display Name"
FROM
    pem.alert pa
    LEFT JOIN pem.alert_template pat ON (pat.id = pa.template_id)
    LEFT JOIN pem.probe_target_type ppt ON (ppt.id = pat.object_type)
    LEFT JOIN pem.alert_status pas ON (pas.alert_id = pa.id)
    LEFT JOIN pem.avail_servers ps ON (ps.id = pa.server_id)"""

        query_where_clause = """ WHERE {0} pa.enabled=true AND
                pas.current_state IS NOT NULL AND
                COALESCE(pa.error_message, '') = '' {1} AND
                NOT ps.alert_blackout {2}
            ORDER BY """.format(
            where_clause1, sys_objects_clause, show_ack_query
        )
        query += query_where_clause

        def_sort_index = 3
    elif page_type == 2:  # Get description from pem.avail_agents
        # If pem.alert_template.object_type = 50, it means it is an alert for
        # global objects so don't list the alert on the
        # agent level alert page, only on the global level.
        query = """
SELECT
    pa.id,
    pa.acknowledged AS "Ack'ed", (
        CASE WHEN pas.current_state = 'HIGH' THEN 'High'
        WHEN pas.current_state = 'MEDIUM' THEN 'Medium'
        WHEN pas.current_state = 'LOW' THEN 'Low'
        END
    ) "Alert Type",
    pa.name AS "Name", (
        CASE
        WHEN COALESCE(pas.display_value, '')::text != '' THEN pas.display_value
        ELSE pem.unit_converter(pas.current_value, pat.threshold_unit)
        END
    ) AS "Value",
    pa.agent_id AS "Agent ID", (
        CASE
        WHEN pat.object_type != 50 THEN pag.description
        ELSE 'N/A'::text
        END
    ) AS "Agent",
    pa.server_id AS "Server ID",(
        -- This dashboard is at agent level, so setting the server description
        -- as ''.
        CASE WHEN pat.object_type != 50 THEN '' ELSE 'N/A'::text END
    ) AS "Server",
    pa.database_name AS "Database",
    pa.schema_name AS "Schema",
    pa.package_name AS "Package",
    pa.object_name AS "Object",
    to_char(
        pas.current_state_since, 'YYYY-MM-DD HH24:MI:SS'
    )::timestamp AS "Alerting Since",
    pat.object_type AS "Object Type", ppt.display_name AS "Display Name"
FROM
    pem.alert pa
    LEFT JOIN pem.alert_status pas ON (pa.id = pas.alert_id)
    LEFT JOIN pem.avail_agents pag ON (pag.id = pa.agent_id )
    LEFT JOIN pem.alert_template pat ON (pa.template_id = pat.id)
    LEFT JOIN pem.probe_target_type ppt ON (ppt.id = pat.object_type)"""
        query_where_clause = """ WHERE {0}
                pa.enabled=true AND
                pas.current_state IS NOT NULL AND
                COALESCE(pa.error_message, '') = '' AND
                pat.object_type != 50 {1} AND
                pag.active = TRUE AND
                NOT pag.alert_blackout {2}
            ORDER BY """.format(
            where_clause1, sys_objects_clause, show_ack_query
        )
        query += query_where_clause

        def_sort_index = 3
    # Get description from pem.server and pem.avail_agents both
    elif page_type == 0:
        query = """
SELECT
    pa.id,
    pa.acknowledged AS "Ack'ed", (
        CASE
        WHEN pas.current_state = 'HIGH' THEN 'High'
        WHEN pas.current_state = 'MEDIUM' THEN 'Medium'
        WHEN pas.current_state = 'LOW' THEN 'Low'
        END
    ) "Alert Type",
    pa.name AS "Name",
    (CASE WHEN COALESCE(pas.display_value, '')::text != ''
      THEN pas.display_value
      ELSE pem.unit_converter(pas.current_value, pat.threshold_unit) END
    ) AS "Value",
    pa.agent_id AS "Agent ID", (
        CASE
        WHEN pat.object_type != 50 THEN pag.description
        ELSE 'N/A'::text
        END
    ) AS "Agent",
    pa.server_id AS "Server ID", (
        CASE
        WHEN pat.object_type != 50 THEN pavs.description
        ELSE 'N/A'::text
        END
    ) AS "Server",
    pa.database_name AS "Database",
    pa.schema_name AS "Schema",
    pa.package_name AS "Package",
    pa.object_name AS "Object",
    to_char(
        pas.current_state_since, 'YYYY-MM-DD HH24:MI:SS'
    )::timestamp AS "Alerting Since",
    pat.object_type AS "Object Type", ppt.display_name AS "Display Name"
FROM
    pem.alert pa
    LEFT JOIN pem.alert_status pas ON (pa.id = pas.alert_id)
    LEFT JOIN pem.alert_template pat ON (pa.template_id = pat.id)
    LEFT JOIN pem.probe_target_type ppt ON (ppt.id = pat.object_type)
    LEFT JOIN pem.avail_servers pavs ON (pa.server_id = pavs.id)
    LEFT JOIN pem.avail_agents pag ON (pag.id = pa.agent_id) """

        query_where_clause = """
WHERE
    (({0} pa.enabled=true AND
    pas.current_state IS NOT NULL AND
    COALESCE(pa.error_message, '') = '' {1} AND (
        NOT pavs.alert_blackout OR (
            NOT pag.alert_blackout AND pag.active IS TRUE
        )
    )) OR (
        pa.agent_id = -1 AND pa.enabled=true AND
        pas.current_state IS NOT NULL AND
        COALESCE(pa.error_message, '') = ''
    )) {2}
    ORDER BY """.format(
            where_clause1, sys_objects_clause, show_ack_query
        )

        query += query_where_clause
        def_sort_index = 3

    if sort_index == '' or sort_index is None or int(sort_index) < 3:
        sort_index = def_sort_index  # default "Name"

    query += str(sort_index)

    if (
        sort_direction != '' and sort_direction is not None and
        sort_direction == 1
    ):
        query += ' DESC'

    with DashboardTransaction(
        trans_id, pem_conn.conn_id, -1, random.randint(1, 9999999)
    ):
        status, qresults = pem_conn.execute_dict(query, params)

    if not status:
        error_return(
            gettext(
                "Error fetching alert details!\nERROR: {0}"
                .format(qresults)),
            e_type=PEMErrorType.JSON
        )
    result = generate_json_for_table_chart(qresults, 'alert_details',
                                           TABLE_ID['ALERT_DETAILS'])
    result['timeout'] = reload
    return make_json_response(data=result)


@pem_connection
def table_alerts_errors(
    agent_id='', server_id='', database='', schema='',
    show_system_objects='', sort_index=3, sort_direction=0,
    reload=30000, trans_id=0, pem_conn=None
):
    result = {}
    # Alert page at schema level
    if server_id is not None and server_id != 0 and \
            database is not None and schema is not None:
        # make where clause for other metrices
        where_clause1 = "pa.server_id = (%s)::int4 AND ' \
            'pa.database_name = (%s)::text AND pa.schema_name = (%s)::text AND"
        # If page_type = 1 => get description from pem.server
        page_type = 1
        params = [server_id, database, schema]
    # Alert page at database level
    elif (server_id is not None and server_id != 0 and database is not None):
        # make where clause for other metrices
        where_clause1 = 'pa.server_id = (%s)::int4 AND ' \
            'pa.database_name = (%s)::text AND'
        # If page_type = 1 => get description from pem.server
        page_type = 1
        params = [server_id, database]
    elif agent_id is not None and agent_id != 0 and \
            (server_id is None or server_id == 0):  # Alert page at agent level
        # make where clause for other metrices
        where_clause1 = 'pa.agent_id = (%s)::int4 AND'
        # If page_type = 2 => get description from pem.avail_agents
        page_type = 2
        params = [agent_id]
    elif (server_id is not None and server_id != 0):
        # Alert page at server level
        # make where clause for other metrices
        where_clause1 = 'pa.server_id = (%s)::int4 AND'
        # If page_type = 1 => get description from pem.server
        page_type = 1
        params = [server_id]
    # Alert page at global level
    else:
        # make where clause for other metrices
        where_clause1 = ''
        # If page_type = 0 => get description from pem.server and
        # pem.avail_agents both
        page_type = 0
        params = []

    sys_objects_clause = ''
    sys_objects_clause = table_sys_clause('pa', True if database else False)
    with DashboardTransaction(
        trans_id, pem_conn.conn_id, -1, random.randint(1, 9999999)
    ):
        ret_val, result1, rest_param = get_restricted_objects_clause(
            pem_conn, '%s', 'pa.database_name', 0, server_id
        )

    restricted_objects_clause = ''
    if ret_val is True and result1 != '':
        restricted_objects_clause = " AND " + result1
    if rest_param != '':
        params.append(rest_param)

    if (page_type == 1):
        query = """
SELECT
    pa.id, (
        CASE WHEN COALESCE(pa.error_message, '') <> '' THEN 'Error' END
    ) "Alert Type",
    pa.name AS "Name",
    pas.current_value::numeric(24,4) AS "Value",
    pa.agent_id AS "Agent ID", (
        -- This chart is at server level, hence setting agent description as ''
        CASE WHEN pat.object_type != 50 THEN '' ELSE 'N/A'::text END
    ) AS "Agent",
    pa.server_id AS "Server ID", (
        CASE
        WHEN pat.object_type != 50 THEN ps.description
        ELSE 'N/A'::text
        END
    ) AS "Server",
    pa.database_name AS "Database",
    pa.schema_name AS "Schema",
    pa.package_name AS "Package",
    pa.object_name AS "Object",
    pa.error_message AS "Error Message",
    pat.object_type AS "Object Type",
    ppt.display_name AS "Display Name",
    to_char(pa.error_timestamp, 'YYYY-MM-DD HH24:MI:SS')::timestamp
      AS "Error Timestamp"
FROM
    pem.alert pa
    LEFT JOIN pem.alert_template pat ON (pat.id = pa.template_id)
    LEFT JOIN pem.probe_target_type ppt ON (ppt.id = pat.object_type)
    LEFT JOIN pem.alert_status pas ON (pas.alert_id = pa.id)
    LEFT JOIN pem.avail_servers ps ON (ps.id = pa.server_id)
WHERE
    NOT ps.alert_blackout AND {0}
    pa.enabled=true AND
    COALESCE(pa.error_message, '') <> '' {1}{2} ORDER BY """.format(
            where_clause1, sys_objects_clause,
            restricted_objects_clause
        )

        def_sort_index = 'pas.current_state'

    elif (page_type == 2):
        # If pem.alert_template.object_type = 50, it means it is an alert for
        # global objects so don't list the alert on the
        # agent level alert page, only on the global level.
        query = """
SELECT
    pa.id, (
        CASE WHEN COALESCE(pa.error_message, '') <> '' THEN 'Error' END
    ) "Alert Type",
    pa.name AS "Name",
    pas.current_value::numeric(24,4) AS "Value",
    pa.agent_id AS "Agent ID", (
        CASE
        WHEN pat.object_type != 50 THEN pag.description
        ELSE 'N/A'::text
        END
    ) AS "Agent",
    pa.server_id AS "Server ID", (
        -- This chart is at agent level, hence setting server description as ''
        CASE
        WHEN pat.object_type != 50 THEN ''
        ELSE 'N/A'::text END
    ) AS "Server",
    pa.database_name AS "Database",
    pa.schema_name AS "Schema",
    pa.package_name AS "Package",
    pa.object_name AS "Object",
    pa.error_message AS "Error Message",
    pat.object_type AS "Object Type",
    ppt.display_name AS "Display Name",
    to_char(pa.error_timestamp, 'YYYY-MM-DD HH24:MI:SS')::timestamp
      AS "Error Timestamp"
FROM
    pem.alert pa
    LEFT JOIN pem.alert_status pas ON (pa.id = pas.alert_id)
    LEFT JOIN pem.avail_agents pag ON (pag.id = pa.agent_id)
    LEFT JOIN pem.alert_template pat ON (pat.id = pa.template_id)
    LEFT JOIN pem.probe_target_type ppt ON (ppt.id = pat.object_type)
WHERE
    pag.active = TRUE AND
    NOT pag.alert_blackout AND {0}
    pa.enabled=true AND
    COALESCE(pa.error_message, '') <> '' AND
    pat.object_type != 50 {1}{2} ORDER BY """.format(
            where_clause1, sys_objects_clause, restricted_objects_clause
        )
        def_sort_index = 'pas.current_state'
    elif (page_type == 0):
        query = """
SELECT
    pa.id, (
        CASE
        WHEN COALESCE(pa.error_message, '') <> '' THEN 'Error'
        END
    ) "Alert Type",
    pa.name AS "Name",
    pas.current_value::numeric(24,4) AS "Value",
    pa.agent_id AS "Agent ID", (
        CASE
        WHEN pat.object_type != 50 THEN pag.description
        ELSE 'N/A'::text END
    ) AS "Agent",
    pa.server_id AS "Server ID", (
        CASE
        WHEN pat.object_type != 50 THEN pavs.description
        ELSE 'N/A'::text END
    ) AS "Server",
    pa.database_name AS "Database",
    pa.schema_name AS "Schema",
    pa.package_name AS "Package",
    pa.object_name AS "Object",
    pa.error_message AS "Error Message",
    pat.object_type AS "Object Type",
    ppt.display_name AS "Display Name",
    to_char(pa.error_timestamp, 'YYYY-MM-DD HH24:MI:SS')::timestamp
      AS "Error Timestamp"
FROM
    pem.alert pa
    LEFT JOIN pem.alert_status pas ON (pa.id = pas.alert_id )
    LEFT JOIN pem.alert_template pat ON (pa.template_id = pat.id)
    LEFT JOIN pem.probe_target_type ppt ON (ppt.id = pat.object_type)
    LEFT JOIN pem.avail_agents pag ON (pag.id = pa.agent_id)
    LEFT JOIN pem.avail_servers pavs ON (pa.server_id = pavs.id)
WHERE (
    NOT pavs.alert_blackout AND pa.enabled=true AND
    COALESCE(pa.error_message, '') <> ''
) OR (
    pag.active = TRUE AND NOT pag.alert_blackout AND
    COALESCE(pa.error_message, '') <> ''
) OR (
    pa.enabled=true AND pa.agent_id = -1 AND pa.server_id = 0 AND
    COALESCE(pa.error_message, '') <> ''
) {0}{1}
ORDER BY """.format(
            sys_objects_clause, restricted_objects_clause
        )

        def_sort_index = 1  # default "Alert Type"

    sort_index = int(sort_index) if sort_index is not None else sort_index
    if (sort_index == '' or sort_index is None or sort_index < 3):
        sort_index = def_sort_index  # default "Name"

    query += str(sort_index)

    if (
        sort_direction != '' and sort_direction is not None and
        sort_direction == 1
    ):
        query += ' DESC'

    try:
        with DashboardTransaction(
            trans_id, pem_conn.conn_id, -1, random.randint(1, 9999999)
        ):
            status, qresults = pem_conn.execute_dict(query, tuple(params))

        if not status:
            error_return(gettext(
                "Error fetching alert details!\nERROR: {0}"
            ).format(qresults), e_type=PEMErrorType.JSON)
    except Exception as e:
        from flask import current_app
        current_app.logger.exception(e)

    result = generate_json_for_table_chart(qresults, 'alert_errors',
                                           TABLE_ID['ALERT_ERRORS'])
    result['timeout'] = reload
    return make_json_response(data=result)


@pem_connection
def table_audit_logs(
    agent_id, server_id, rowid, database=None, username=None,
    commandtype=None, fromdate=None, todate=None, reload=30000, trans_id=0,
    pem_conn=None
):

    agent_id = int(agent_id)
    server_id = int(server_id)
    # Start building the document
    params = []
    is_simple_query = True

    if server_id > 0:  # For Server Level Logs.
        sql = """
            SELECT
               id,
               EXTRACT(EPOCH FROM log_time) * 1000 AS "Timestamp",
               user_name AS "User Name",
               database_name AS "Database Name",
               connection_from AS "Connection From",
               command_tag AS "Command",
               message AS "Message",
               process_id AS "Process ID",
               session_id AS "Session ID",
               transaction_id AS "Transaction ID"
            FROM
              pemdata.audit_logs
            WHERE server_id = (%s)::int4"""

        params = [server_id]
    elif agent_id != -1 and agent_id != 0:  # For Agent Level Logs.
        sql = """
SELECT s.id, s.description FROM pem.avail_servers s
LEFT JOIN pem.agent_server_binding asb ON (asb.server_id = s.id)
WHERE asb.agent_id = (%s)::int4"""

        with DashboardTransaction(
            trans_id, pem_conn.conn_id, -1, random.randint(1, 9999999)
        ):
            status, rs = pem_conn.execute_2darray(sql, [agent_id])

        if not status:
            error_return(
                gettext("Error executing query: {0}".format(rs)),
                e_type=PEMErrorType.JSON
            )

        sql = ''
        params = []
        if status and 'rows' in rs:
            rs = rs['rows']
        if (len(rs) == 0):
            sql = """
                SELECT
                    al.id AS id,
                    'none'::text AS "Server",
                    EXTRACT(EPOCH FROM log_time) * 1000 AS "Timestamp",
                    user_name AS "User Name",
                    database_name AS "Database Name",
                    connection_from AS "Connection From",
                    command_tag AS "Command",
                    message AS "Message",
                    process_id AS "Process ID",
                    session_id AS "Session ID",
                    transaction_id AS "Transaction ID"
                FROM
                    pemdata.audit_logs al
                WHERE false"""
        else:
            sql += """
                    SELECT
                        id,
                        server AS "Server",
                        EXTRACT(EPOCH FROM log_time) * 1000 AS "Timestamp",
                        user_name AS "User Name",
                        database_name AS "Database Name",
                        connection_from AS "Connection From",
                        command_tag AS "Command",
                        message AS "Message",
                        process_id AS "Process ID",
                        session_id AS "Session ID",
                        transaction_id AS "Transaction ID"
                    FROM (
                    """
            for row in range(0, len(rs)):
                if (row != 0):
                    sql += " UNION ALL "

                sql += """ SELECT
                                al.id AS id,
                                (%s)::text AS server,
                                log_time,
                                user_name,
                                database_name,
                                connection_from,
                                command_tag,
                                message,
                                process_id,
                                session_id,
                                transaction_id
                            FROM
                                pemdata.audit_logs al
                            WHERE al.server_id = (%s)::int4"""

                # Server description
                params.append(rs[row]['description'])
                # Server id
                params.append(rs[row]['id'])

            sql += ") AS x"
            is_simple_query = False
    elif server_id <= 0 and agent_id <= 0:  # For Global Level Logs.
        sql = """
SELECT
    s.id, s.description, a.description AS agent
FROM pem.avail_servers s
    LEFT JOIN pem.agent_server_binding asb ON (asb.server_id = s.id)
    LEFT JOIN pem.avail_agents a ON (asb.agent_id = a.id)
WHERE a.id IS NOT NULL"""

        with DashboardTransaction(
            trans_id, pem_conn.conn_id, -1, random.randint(1, 9999999)
        ):
            status, rs = pem_conn.execute_dict(sql)

        if not status:
            error_return(
                gettext("Error executing query: {0}".format(rs)),
                e_type=PEMErrorType.JSON
            )

        sql = ''
        params = []
        if status and 'rows' in rs:
            rs = rs['rows']

        if (len(rs) == 0):
            sql = """
                SELECT
                    al.id AS id,
                    'none'::text AS "Agent",
                    'none'::text AS "Server",
                    EXTRACT(EPOCH FROM log_time) * 1000 AS "Timestamp",
                    user_name AS "User Name",
                    database_name AS "Database Name",
                    connection_from AS "Connection From",
                    command_tag AS "Command",
                    message AS "Message",
                    process_id AS "Process ID",
                    session_id AS "Session ID",
                    transaction_id AS "Transaction ID"
                FROM
                    pemdata.audit_logs al
                WHERE false"""
        else:
            sql += """
                    SELECT
                        id,
                        agent AS "Agent",
                        server AS "Server",
                        EXTRACT(EPOCH FROM log_time) * 1000 AS "Timestamp",
                        user_name AS "User Name",
                        database_name AS "Database Name",
                        connection_from AS "Connection From",
                        command_tag AS "Command",
                        message AS "Message",
                        process_id AS "Process ID",
                        session_id AS "Session ID",
                        transaction_id AS "Transaction ID"
                    FROM ("""
            for row in range(0, len(rs)):
                if (row != 0):
                    sql += " UNION ALL "

                sql += """
                        SELECT
                            al.id AS id,
                            (%s)::text AS agent,
                            (%s)::text AS server,
                            log_time,
                            user_name,
                            database_name,
                            connection_from,
                            command_tag,
                            message,
                            process_id,
                            session_id,
                            transaction_id
                        FROM
                            pemdata.audit_logs al
                        WHERE al.server_id = (%s)::int4"""

                # Agent description
                params.append(rs[row]['agent'])
                # Server description
                params.append(rs[row]['description'])
                # Server id
                params.append(rs[row]['id'])

            sql += ") AS x"
            is_simple_query = False

    cond_arr = []
    if database is not None:
        cond_arr.append("database_name = (%s)::text")
        params.append(database)
    if username is not None:
        cond_arr.append("user_name = (%s)::text")
        params.append(username)
    if commandtype is not None:
        lowercommandtype = commandtype.lower()
        uppercommandtype = commandtype.upper()
        cond_arr.append(
            "(command_tag = (%s)::text OR command_tag = (%s)::text)")
        params.append(lowercommandtype)
        params.append(uppercommandtype)

    if fromdate is not None:
        cond_arr.append("log_time >= to_timestamp(%s)")
        params.append(int(fromdate))

    if todate is not None:
        cond_arr.append("log_time <= to_timestamp(%s)")
        params.append(int(todate))

    if len(cond_arr) > 0:
        if is_simple_query:
            sql += " AND " + " AND ".join(cond_arr)
            if rowid > 0:
                sql += " AND id < (%s)::int8"  # To Check
                params.append(rowid)
        else:
            sql += " WHERE " + " AND ".join(cond_arr)
            if rowid > 0:
                sql += " AND id < (%s)::int8"  # To Check
                params.append(rowid)
    elif rowid > 0:
        if is_simple_query:
            sql += " AND id < (%s)::int8"
        else:
            sql += " WHERE id < (%s)::int8"
        params.append(rowid)

    sql += " ORDER BY 1 DESC LIMIT 500"

    with DashboardTransaction(
        trans_id, pem_conn.conn_id, -1, random.randint(1, 9999999)
    ):
        status, res = pem_conn.execute_dict(sql, params)

    if not status:
        error_return(gettext(
            "Error fetching the audit logs data!\nERROR: {0}"
        ).format(res), e_type=PEMErrorType.JSON)

    return make_json_response(
        status=200, success=1,
        data={'data': res['rows'], 'columns': res['columns']}
    )


@pem_connection
def table_probe_logs(agent_id, rowid, fromdate=None,
                     todate=None, reload=30000, trans_id=0, pem_conn=None):
    # Start building the document

    sql = """
SELECT
   pl.id,
   EXTRACT(EPOCH FROM pl.recorded_time) * 10000::int8 / 10 AS "Timestamp",
   pr.display_name AS "Probe Name",
   s.description AS "Server Name",
   pl.message AS "Error Message"
FROM
  pem.probe_log pl
  LEFT OUTER JOIN pem.probe pr ON pl.probe_id = pr.id
  LEFT OUTER JOIN pem.server s ON (
    s.id = pl.parameter_value_list[1]::int AND pr.applies_to_id > 100
  )
WHERE agent_id = (%s)::int4
        """
    params = [agent_id]
    cond_arr = []
    if fromdate is not None:
        cond_arr.append("recorded_time >= to_timestamp(%s)")
        params.append(int(fromdate))
    if todate is not None:
        cond_arr.append("recorded_time <= to_timestamp(%s)")
        params.append(int(todate))
    if len(cond_arr) > 0:
        sql += " AND " + " AND ".join(cond_arr)
        if rowid > 0:
            sql += " AND pl.id < (%s)::int4"
            params.append(rowid)

    sql += " ORDER BY 1 DESC LIMIT 500"

    with DashboardTransaction(
        trans_id, pem_conn.conn_id, -1, random.randint(1, 9999999)
    ):
        status, res = pem_conn.execute_dict(sql, params)

    if not status:
        error_return(gettext(
            "Error fetching table probe logs!\nERROR: {0}"
        ).format(res), e_type=PEMErrorType.JSON)

    return make_json_response(
        status=200, success=1, data={'data': res['rows'],
                                     'columns': res['columns']})


@pem_connection
def table_server_logs(
    agent_id, server_id, rowid, database=None, username=None, commandtype=None,
    fromdate=None, todate=None, reload=30000, trans_id=0, pem_conn=None
):
    agent_id = int(agent_id)
    server_id = int(server_id)

    is_simple_query = True
    i = 1
    params = []

    # For Server Level Logs.
    if server_id > 0:
        sql = """
                SELECT
                   id,
                   EXTRACT(EPOCH FROM log_time) * 1000 AS "Timestamp",
                   user_name AS "User Name",
                   database_name AS "Database Name",
                   connection_from AS "Connection From",
                   command_tag AS "Command",
                   message AS "Message",
                   process_id AS "Process ID",
                   session_id AS "Session ID",
                   transaction_id AS "Transaction ID"
                FROM
                  pemdata.server_logs
                WHERE server_id = (%s)::int4"""

        params.append(server_id)
        i = 2
    # For Agent Level Logs.
    elif agent_id != 0 and agent_id != -1:
        sql = """
SELECT s.id, s.description FROM pem.avail_servers s
LEFT JOIN pem.agent_server_binding asb ON (asb.server_id = s.id)
WHERE asb.agent_id = (%s)::int4"""

        with DashboardTransaction(
            trans_id, pem_conn.conn_id, -1, random.randint(1, 9999999)
        ):
            status, rs = pem_conn.execute_2darray(sql, [agent_id])

        if not status:
            error_return(
                gettext("Error executing query: {0}".format(rs)),
                e_type=PEMErrorType.JSON
            )

        sql = ''
        params = []
        i = 1
        if status and 'rows' in rs:
            rs = rs['rows']

        if (len(rs) == 0):
            sql += """
                    SELECT
                       al.id AS id,
                       'none'::text AS "Server",
                       EXTRACT(EPOCH FROM log_time) * 1000 AS "Timestamp",
                       user_name AS "User Name",
                       database_name AS "Database Name",
                       connection_from AS "Connection From",
                       command_tag AS "Command",
                       message AS "Message",
                       process_id AS "Process ID",
                       session_id AS "Session ID",
                       transaction_id AS "Transaction ID"
                    FROM
                      pemdata.server_logs al
                    WHERE false"""
        else:
            sql += """
                    SELECT
                       id,
                       server AS "Server",
                       EXTRACT(EPOCH FROM log_time) * 1000 AS "Timestamp",
                       user_name AS "User Name",
                       database_name AS "Database Name",
                       connection_from AS "Connection From",
                       command_tag AS "Command",
                       message AS "Message",
                       process_id AS "Process ID",
                       session_id AS "Session ID",
                       transaction_id AS "Transaction ID"
                    FROM ("""

            for row in range(0, len(rs)):
                if (row != 0):
                    sql += " UNION ALL "

                sql += """
                       SELECT
                          al.id AS id,
                          (%s)::text AS server,
                          log_time,
                          user_name,
                          database_name,
                          connection_from,
                          command_tag,
                          message,
                          process_id,
                          session_id,
                          transaction_id
                       FROM
                          pemdata.server_logs al
                       WHERE al.server_id = (%s)::int4"""

                # Agent description
                params.append(rs[row]['description'])
                # Server id
                params.append(rs[row]['id'])

            sql += ') AS x'
            is_simple_query = False

    elif server_id <= 0 and agent_id <= 0:  # For Global Level Logs.
        sql = """
                SELECT
                    s.id, s.description, a.description AS agent
                FROM
                    pem.avail_servers s
                    LEFT JOIN pem.agent_server_binding asb ON (
                        asb.server_id = s.id
                    )
                    LEFT JOIN pem.avail_agents a ON (asb.agent_id = a.id)
                WHERE a.id IS NOT NULL"""

        with DashboardTransaction(
            trans_id, pem_conn.conn_id, -1, random.randint(1, 9999999)
        ):
            status, rs = pem_conn.execute_dict(sql)

        if not status:
            error_return(
                gettext("Error executing query: {0}".format(rs)),
                e_type=PEMErrorType.JSON
            )

        params = []
        sql = ''
        i = 1
        if status and 'rows' in rs:
            rs = rs['rows']

        if (len(rs) == 0):
            sql = """
                    SELECT
                        al.id AS id,
                        'none'::text AS "Agent",
                        'none'::text AS "Server",
                        EXTRACT(EPOCH FROM log_time) * 1000 AS "Timestamp",
                        user_name AS "User Name",
                        database_name AS "Database Name",
                        connection_from AS "Connection From",
                        command_tag AS "Command",
                        message AS "Message",
                        process_id AS "Process ID",
                        session_id AS "Session ID",
                        transaction_id AS "Transaction ID"
                    FROM
                        pemdata.server_logs al
                    WHERE false"""
        else:
            sql += """
                        SELECT
                            id,
                            agent AS "Agent",
                            server AS "Server",
                            EXTRACT(EPOCH FROM log_time) * 1000 AS "Timestamp",
                            user_name AS "User Name",
                            database_name AS "Database Name",
                            connection_from AS "Connection From",
                            command_tag AS "Command",
                            message AS "Message",
                            process_id AS "Process ID",
                            session_id AS "Session ID",
                            transaction_id AS "Transaction ID"
                        FROM ("""
            for row in range(0, len(rs)):
                if (row != 0):
                    sql += " UNION ALL "

                sql += """
                        SELECT
                            al.id AS id,
                            (%s)::text AS agent,
                            (%s)::text AS server,
                            log_time,
                            user_name,
                            database_name,
                            connection_from,
                            command_tag,
                            message,
                            process_id,
                            session_id,
                            transaction_id
                        FROM
                            pemdata.server_logs al
                        WHERE al.server_id = (%s)::int4"""

                # Agent description
                params.append(rs[row]['agent'])
                # Server description
                params.append(rs[row]['description'])
                # Server id
                params.append(rs[row]['id'])
                i = i + 3

            sql += ') AS x'
            is_simple_query = False

    cond_arr = []
    if database is not None:
        cond_arr.append("database_name = (%s)::text")
        params.append(database)

    if username is not None:
        cond_arr.append("user_name = (%s)::text")
        params.append(username)

    if commandtype is not None:
        lowercommandtype = commandtype.lower()
        uppercommandtype = commandtype.upper()
        cond_arr.append(
            "(command_tag = (%s)::text OR command_tag = (%s)::text)")
        params.append(lowercommandtype)
        params.append(uppercommandtype)

    if fromdate is not None:
        cond_arr.append("log_time >= to_timestamp(%s)")
        params.append(int(fromdate))

    if todate is not None:
        cond_arr.append("log_time <= to_timestamp(%s)")
        params.append(int(todate))

    # Table without headers.
    if len(cond_arr) > 0:
        if is_simple_query:
            sql += " AND " + \
                " AND ".join(cond_arr)
        else:
            sql += " WHERE " + \
                " AND ".join(cond_arr)
        if rowid > 0:
            sql += " AND id < " + str(rowid)
    elif rowid > 0:
        if is_simple_query:
            sql += " AND id < " + str(rowid)
        else:
            sql += " WHERE id < " + str(rowid)

    sql += " ORDER BY 1 DESC LIMIT 500"

    with DashboardTransaction(
        trans_id, pem_conn.conn_id, -1, random.randint(1, 9999999)
    ):
        status, res = pem_conn.execute_dict(sql, params)

    if not status:
        error_return(gettext(
            "Error fetching table server logs!\nERROR: {0}"
        ).format(res), e_type=PEMErrorType.JSON)

    return make_json_response(
        status=200, success=1, data={'data': res['rows'],
                                     'columns': res['columns']}
    )


@pem_connection
def table_io_object_index_io(
    server_id, database, show_system_objects,
    sort_index=3, reload=30000, trans_id=0, pem_conn=None
):
    query = """
WITH restricted_db_schemas AS (
    SELECT
        s.id, pem.db_escaped_string_to_array(COALESCE(
            o.schema_restriction, oa.schema_restriction
        )) as rest_schemas
    FROM
        pem.server s
        LEFT OUTER JOIN pg_catalog.pg_roles owner ON (owner.oid = s.owner)
        LEFT OUTER JOIN pem.database_option o ON (
            s.id = o.server_id AND o.pem_user = current_user AND
            o.database = (%(database)s)::text
        )
        LEFT OUTER JOIN pem.database_option oa ON (
            o.id IS NULL AND s.id = oa.server_id AND
            oa.database = (%(database)s)::text AND (
                owner.rolname = oa.pem_user OR (
                    owner.rolname IS NULL AND oa.pem_user IS NULL
                )
            )
        )
    WHERE
        s.id = (%(server_id)s)::int4)
SELECT
    i.schema_name as "Schema",
    t.table_name as "Table Name",
    i.index_name as "Index Name",
    i.idx_scan as "Scans",
    i.idx_tup_read as "Rows Read",
    i.idx_tup_fetch as "Rows Fetched",
    i.idx_blks_read as "Blocks Read",
    i.idx_blks_hit as "Blocks Hit"
FROM
    pemdata.index_statistics AS i
    LEFT OUTER JOIN pemdata.oc_index t ON (
        i.server_id = t.server_id AND i.database_name = t.database_name AND
        i.schema_name = t.schema_name AND i.index_name = t.index_name
    )
    LEFT OUTER JOIN restricted_db_schemas rds ON (t.server_id = rds.id)
WHERE
    i.server_id = (%(server_id)s)::int4 AND
    i.database_name = (%(database)s)::text AND (
        rds.rest_schemas IS NULL OR t.schema_name = ANY (rds.rest_schemas)
    ) AND
    ((%(sys_obj)s)::boolean OR (
        t.schema_name NOT IN (
            'pg_catalog', 'pg_toast', 'information_schema', 'sys'
        ) AND t.schema_name !~'pg_temp|pg_toast'
    ))
ORDER BY (%(sort_index)s)::int4 DESC LIMIT (%(num_rows)s)::int4"""

    sort_index = int(sort_index) if sort_index is not None else sort_index
    if (sort_index is None or sort_index ==
            '' or sort_index == 'null' or sort_index < 3):
        sort_index = 3  # default "Index Name"

    num_rows = get_params('dash_io_index_objectio_rows')  # To Do

    params = {
        "server_id": server_id, "database": database, "sys_obj":
        show_system_objects, "sort_index": sort_index, "num_rows": num_rows
    }

    with DashboardTransaction(
        trans_id, pem_conn.conn_id, -1, random.randint(1, 9999999)
    ):
        status, res = pem_conn.execute_dict(query, params)

    if not status:
        error_return(
            gettext("Error executing query: {0}".format(res)),
            e_type=PEMErrorType.JSON
        )
    result = generate_json_for_table_chart(res, 'io_object_index_io',
                                           TABLE_ID['IO_OBJECT_INDEX_IO'])
    result['timeout'] = reload
    return make_json_response(data=result)


@pem_connection
def table_session_workload(
    server_id, show_system_objects, reload=30000, trans_id=0, pem_conn=None
):
    # Check the remote monitoring status
    result = {}
    is_remote_monitoring = 'f'
    params = [server_id]
    query = "SELECT is_remote_monitoring FROM pem.server WHERE id = (%s)::int4"

    with DashboardTransaction(
        trans_id, pem_conn.conn_id, -1, random.randint(1, 9999999)
    ):
        status, is_remote_monitoring = pem_conn.execute_scalar(query, params)

    if is_remote_monitoring:
        query = """
WITH restricted_dbs AS (
    SELECT s.id, pem.db_escaped_string_to_array(COALESCE(
        o.database_restriction, oa.database_restriction
    )) AS dbs
FROM
    pem.server s
    LEFT OUTER JOIN pg_catalog.pg_roles owner ON (owner.oid = s.owner)
    LEFT OUTER JOIN pem.server_options o ON (
        s.id = o.server_id AND o.pem_user = current_user
    )
    LEFT OUTER JOIN pem.server_options oa ON (
        o.id IS NULL AND s.id = oa.server_id AND (
            owner.rolname = oa.pem_user OR (
                owner.rolname IS NULL AND oa.pem_user IS NULL
            )
        )
    )
)
SELECT
    procpid as "Session Id",
    usename as "User Name",
    (client_addr || ':' || client_port) as "Source",
    database_name as "Database Name",
    CASE WHEN is_waiting = 't' then 'Yes' ELSE 'No' END as "Waiting?",
    backend_start AS "Backend Start",
    xact_start AS "Transaction Start",
    query_start AS "Query Start"
FROM
    pemdata.session_info s
    LEFT OUTER JOIN restricted_dbs r ON (s.server_id = r.id)
WHERE
    server_id = (%s)::int4 AND
    ((%s)::boolean OR (
        CASE
        WHEN s.database_name != ''
            THEN s.database_name NOT IN ('template0', 'template1')
        ELSE TRUE END
    )) AND (
        r.dbs IS NULL OR (s.database_name = ANY(r.dbs))
    )
ORDER BY 3"""
    else:
        query = """
WITH restricted_dbs AS (
    SELECT s.id, pem.db_escaped_string_to_array(COALESCE(
        o.database_restriction, oa.database_restriction
    )) AS dbs
FROM
    pem.server s
    LEFT OUTER JOIN pg_catalog.pg_roles owner ON (owner.oid = s.owner)
    LEFT OUTER JOIN pem.server_options o ON (
        s.id = o.server_id AND o.pem_user = current_user
    )
    LEFT OUTER JOIN pem.server_options oa
    ON (
        o.id IS NULL AND s.id = oa.server_id AND (
            owner.rolname = oa.pem_user OR (
                owner.rolname IS NULL AND oa.pem_user IS NULL
            )
        )
    )
)
SELECT
    procpid as "Session Id",
    usename as "User Name",
    (client_addr || ':' || client_port) as "Source",
    database_name as "Database Name",
    CASE
    WHEN is_waiting = 't' then 'Yes'
    ELSE 'No'
    END as "Waiting?",
    backend_start AS "Backend Start",
    xact_start AS "Transaction Start",
    query_start AS "Query Start",
    ROUND(CAST(memory_usage_mb as numeric), 3)
        AS "Memory Usage",
    ROUND(CAST(swap_usage_mb  as numeric), 3)
        AS "Swap Usage",
    ROUND(CAST(cpu_usage as numeric), 3)
        AS "CPU Usage",
    ROUND(CAST(io_read_bytes as numeric), 3)
        AS "I/O Reads (bytes)",
    ROUND(CAST(io_write_bytes as numeric), 3)
        AS "I/O Writes (bytes)"
FROM
    pemdata.session_info s
    LEFT OUTER JOIN restricted_dbs r ON (s.server_id = r.id)
WHERE
    server_id = (%s)::int4 AND
    ((%s)::boolean OR (
        CASE WHEN s.database_name != ''
            THEN s.database_name NOT IN (
                'template0', 'template1'
            ) ELSE TRUE END
    )) AND
    (r.dbs IS NULL OR (s.database_name = ANY(r.dbs)))
    ORDER BY 3"""

    params = [server_id, show_system_objects]
    status = False
    qresults = None

    with DashboardTransaction(
        trans_id, pem_conn.conn_id, -1, random.randint(1, 9999999)
    ):
        status, qresults = pem_conn.execute_dict(query, params)

    if not status:
        error_return(
            gettext(
                "Error fetching table session workload!\nERROR: {0}"
            ).format(qresults),
            e_type=PEMErrorType.JSON
        )
    results = generate_json_for_table_chart(qresults, 'session_workload',
                                            TABLE_ID['SESSION_WORKLOAD'])
    results['timeout'] = reload
    return make_json_response(
        data=results
    )


@pem_connection
def table_bdr_node_summary(
    server_id, sort_index=3, sort_direction=0,
    reload=30000, trans_id=0, pem_conn=None
):
    result = {}

    query = """
    SELECT node_name as "Node", node_group_name "Node Group",
    peer_state_name as "Peer State",
    peer_target_state_name as "Peer Target State",
    sub_repsets as "Sub Repset" FROM pemdata.bdr_node_summary
    where server_id={0}::integer ORDER BY %(sort_index)s::int4;
    """.format(server_id)

    if (
        sort_direction != '' and sort_direction is not None and
        sort_direction == 1
    ):
        query += ' DESC'

    sort_index = int(sort_index) if sort_index is not None else sort_index
    if sort_index == '' or sort_index is None or sort_index < 3:
        sort_index = 3  # default "Name"

    params = {'sort_index': sort_index}

    with DashboardTransaction(
        trans_id, pem_conn.conn_id, -1, random.randint(1, 9999999)
    ):
        status, res = pem_conn.execute_dict(query, params)

    if not status:
        error_return(
            gettext("Error fetching alert status!\nERROR: {0}".format(res)),
            e_type=PEMErrorType.JSON
        )
    result = generate_json_for_table_chart(res, 'bdr_node_summary',
                                           TABLE_ID['BDR_NODE_SUMMARY'])
    result['timeout'] = reload
    return make_json_response(data=result)


@pem_connection
def table_bdr_workers(
    server_id, sort_index=3, sort_direction=0,
    reload=30000, trans_id=0, pem_conn=None
):
    result = {}
    query = """
    select worker_pid AS "Worker PID", worker_role_name AS "Worker Role Name",
    query_start AS "Query Start", worker_commit_timestamp
    AS "Worker Commit Timestamp",
    wait_event_type AS "Wait Event Type", server_id
     from pemdata.bdr_workers where server_id={0}::integer
     ORDER BY %(sort_index)s::int4 ;
    """.format(server_id)

    if (
        sort_direction != '' and sort_direction is not None and
        sort_direction == 1
    ):
        query += ' DESC'

    sort_index = int(sort_index) if sort_index is not None else sort_index
    if (sort_index == '' or sort_index is None or sort_index < 3):
        sort_index = 3  # default "Name"

    params = {'sort_index': sort_index}

    with DashboardTransaction(
        trans_id, pem_conn.conn_id, -1, random.randint(1, 9999999)
    ):
        status, res = pem_conn.execute_dict(query, params)

    if not status:
        error_return(
            gettext("Error fetching worker details!\nERROR: {0}".format(res)),
            e_type=PEMErrorType.JSON
        )
    result = generate_json_for_table_chart(res, 'bdr_workers',
                                           TABLE_ID['BDR_WORKERS'])
    result['timeout'] = reload
    return make_json_response(data=result)


@pem_connection
def table_bdr_worker_errors(
    server_id, database_name=None, sort_index=3, sort_direction=0,
    reload=30000, trans_id=0, pem_conn=None
):
    result = {}
    query = """
    select worker_pid, origin_name, error_message, error_time, error_age
    from pemdata.bdr_worker_errors where server_id={0}::integer
    ORDER BY %(sort_index)s::int4 ;
    """.format(server_id)

    if (
        sort_direction != '' and sort_direction is not None and
        sort_direction == 1
    ):
        query += ' DESC'

    sort_index = int(sort_index) if sort_index is not None else sort_index
    if sort_index == '' or sort_index is None or sort_index < 3:
        sort_index = 3  # default "Name"

    params = {'sort_index': sort_index}

    with DashboardTransaction(
        trans_id, pem_conn.conn_id, -1, random.randint(1, 9999999)
    ):
        status, res = pem_conn.execute_dict(query, params)

    if not status:
        error_return(
            gettext("Error fetching worker details!\nERROR: {0}".format(res)),
            e_type=PEMErrorType.JSON
        )
    result = generate_json_for_table_chart(res, 'bdr_worker_errors',
                                           TABLE_ID['BDR_WORKER_ERRORS'])
    result['timeout'] = reload
    return make_json_response(data=result)
