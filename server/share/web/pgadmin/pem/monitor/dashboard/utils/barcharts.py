##########################################################################
#
# Postgres Enterprise Manager
#
# Copyright (C) 2016 - 2025, EnterpriseDB Corporation. All rights reserved.
#
##########################################################################

"""Bar Charts Related Functionalities."""

from pgadmin.pem.utils import pem_connection, get_restricted_objects_clause
from pgadmin.pem.utils import table_sys_clause
from pgadmin.pem.misc.error import error_return, PEMErrorType
from flask_babel import gettext


@pem_connection
def barchart_alerts_overview(agent_id, server_id, database,
                             schema, show_system_objects=False, pem_conn=None):
    # Alert page at schema level
    if server_id is not None and schema is not None and database is not None:
        # make where clause for other metrices
        where_clause1 = ' pa.server_id = (%(server_id)s)::int4 AND ' \
            'pa.database_name = (%(database)s)::text AND ' \
            'pa.schema_name = (%(schema)s)::text AND'

        params = {
            "server_id": server_id, "database": database, "schema": schema
        }

    # Alert page at database level
    elif server_id is not None and database is not None:
        params = {"server_id": server_id, "database": database}

        # make where clause for other metrices
        ret_val, result, rest_param = get_restricted_objects_clause(
            pem_conn, '(%(schema)s)', 'pa.schema_name', 1, server_id, database
        )

        if ret_val:
            where_clause1 = "pa.server_id = (%(server_id)s)::int4 AND " \
                "pa.database_name = (%(database)s)::text AND " + \
                result + " AND "
            params.update({"schema": rest_param})
        else:
            where_clause1 = " pa.server_id = (%(server_id)s)::int4 AND " \
                "pa.database_name = (%(database)s)::text AND"

    # Alert page at server level
    elif server_id is not None:

        # make where clause for other metrices
        ret_val, result, rest_param = get_restricted_objects_clause(
            pem_conn, '(%s)', 'pa.database_name', 0, server_id
        )
        if ret_val:
            where_clause1 = " pa.server_id = (%(server_id)s)::int4 AND " + \
                result + " AND "
            params = {"server_id": server_id, "schema": rest_param}

        else:
            where_clause1 = " pa.server_id = (%(server_id)s)::int4 AND "
            params = {"server_id": server_id}
    # Alert page at agent level
    elif agent_id is not None:
        # make where clause for other metrices
        where_clause1 = 'pa.agent_id = (%(agent_id)s)::int4 AND'

        params = {"agent_id": agent_id}

    # Alert page at global level
    else:
        # make where clause for other metrices
        where_clause1 = ''
        params = []

    # For global level alerts server_id should be 0 as like agent_id

    if server_id is None:
        server_id = 0
    if agent_id is None:
        agent_id = 0

    # create sql to get the bar chart. where_clause1 has all the conditional
    # clauses required at a particular level. If page is at schema level then
    # where_clause will contain condition for server_id, database_name
    # and schema_name.
    sys_objects_clause = table_sys_clause('pa', True if database else False)

    sql = """
SELECT pos, "Alert Type", "Alert Count" FROM (
SELECT
    'High' AS "Alert Type", (
    SELECT (
        SELECT count(*) FROM pem.alert pa,
        pem.alert_status pas, pem.avail_agents pag
        WHERE pa.id = pas.alert_id AND {1}
            pas.current_state='HIGH' AND
            COALESCE(pa.error_message, '') = '' AND
            pa.enabled=true AND pa.agent_id = pag.id AND pag.active = TRUE AND
            NOT pag.alert_blackout {0}) + (
        SELECT count(*) FROM pem.alert pa, pem.alert_status pas,
        pem.avail_servers ps
        WHERE pa.id = pas.alert_id AND {1} pas.current_state='HIGH' AND
            COALESCE(pa.error_message, '') = '' AND pa.enabled=true AND
            pa.server_id = ps.id AND NOT ps.alert_blackout {0}
        ) + (
        -- We need to show the alerts those alert_id's = -1 as well.
        -- And also, we need to show them only on global level.
        SELECT count(*) FROM pem.alert pa, pem.alert_status pas
        WHERE pa.id = pas.alert_id AND 0 = {2} AND 0 = {3} AND
        pa.agent_id = -1 AND pa.enabled=true AND
        COALESCE(pa.error_message, '') = '' AND pas.current_state='HIGH'
        )
    ) AS "Alert Count",
    1::int AS pos
UNION
SELECT
    'Medium' AS "Alert Type", (
    SELECT (
        SELECT count(*) FROM pem.alert pa,
        pem.alert_status pas, pem.avail_agents pag
        WHERE pa.id = pas.alert_id AND {1}
            pas.current_state='MEDIUM' AND
            COALESCE(pa.error_message, '') = '' AND
            pa.enabled=true AND pa.agent_id = pag.id AND pag.active = TRUE AND
            NOT pag.alert_blackout {0}) + (
        SELECT count(*) FROM pem.alert pa, pem.alert_status pas,
        pem.avail_servers ps
        WHERE pa.id = pas.alert_id AND {1} pas.current_state='MEDIUM' AND
            COALESCE(pa.error_message, '') = '' AND pa.enabled=true AND
            pa.server_id = ps.id AND NOT ps.alert_blackout {0}
        ) + (
        -- We need to show the alerts those alert_id's = -1 as well.
        -- And also, we need to show them only on global level.
        SELECT count(*) FROM pem.alert pa, pem.alert_status pas
        WHERE pa.id = pas.alert_id AND 0 = {2} AND 0 = {3} AND
        pa.agent_id = -1 AND pa.enabled=true AND
        COALESCE(pa.error_message, '') = '' AND pas.current_state='MEDIUM'
        )
    ) AS "Alert Count",
    2::int AS pos
UNION
SELECT
    'Low' AS "Alert Type", (
    SELECT (
        SELECT count(*) FROM pem.alert pa,
        pem.alert_status pas, pem.avail_agents pag
        WHERE pa.id = pas.alert_id AND {1}
            pas.current_state='LOW' AND
            COALESCE(pa.error_message, '') = '' AND
            pa.enabled=true AND pa.agent_id = pag.id AND pag.active = TRUE AND
            NOT pag.alert_blackout {0}) + (
        SELECT count(*) FROM pem.alert pa, pem.alert_status pas,
        pem.avail_servers ps
        WHERE pa.id = pas.alert_id AND {1} pas.current_state='LOW' AND
            COALESCE(pa.error_message, '') = '' AND pa.enabled=true AND
            pa.server_id = ps.id AND NOT ps.alert_blackout {0}
        ) + (
        -- We need to show the alerts those alert_id's = -1 as well.
        -- And also, we need to show them only on global level.
        SELECT count(*) FROM pem.alert pa, pem.alert_status pas
        WHERE pa.id = pas.alert_id AND 0 = {2} AND 0 = {3} AND
        pa.agent_id = -1 AND pa.enabled=true AND
        COALESCE(pa.error_message, '') = '' AND pas.current_state='LOW'
        )
    ) AS "Alert Count",
    3::int AS pos
UNION
SELECT
    'None' AS "Alert Type", (
    SELECT (
        SELECT count(*) FROM pem.alert pa,
        pem.alert_status pas, pem.avail_agents pag
        WHERE pa.id = pas.alert_id AND {1}
            pas.current_state IS NULL AND
            COALESCE(pa.error_message, '') = '' AND
            pa.enabled=true AND pa.agent_id = pag.id AND pag.active = TRUE AND
            NOT pag.alert_blackout {0}) + (
        SELECT count(*) FROM pem.alert pa, pem.alert_status pas,
        pem.avail_servers ps
        WHERE pa.id = pas.alert_id AND {1} pas.current_state IS NULL AND
            COALESCE(pa.error_message, '') = '' AND pa.enabled=true AND
            pa.server_id = ps.id AND NOT ps.alert_blackout {0}
        ) + (
        -- We need to show the alerts those alert_id's = -1 as well.
        -- And also, we need to show them only on global level.
        SELECT count(*) FROM pem.alert pa, pem.alert_status pas
        WHERE pa.id = pas.alert_id AND 0 = {2} AND 0 = {3} AND
        pa.agent_id = -1 AND pa.enabled=true AND
        COALESCE(pa.error_message, '') = '' AND pas.current_state IS NULL
        )
    ) AS "Alert Count",
    4::int AS pos
) AS foo
ORDER BY pos;
        """.format(
        sys_objects_clause, where_clause1, agent_id, server_id
    )
    status, res = pem_conn.execute_2darray(sql, params)

    if not status:
        error_return(
            gettext("Error executing query: {0}".format(res)),
            e_type=PEMErrorType.JSON
        )

    res = res['rows']
    return res
