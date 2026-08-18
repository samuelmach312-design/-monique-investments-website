##########################################################################
#
# Postgres Enterprise Manager
#
# Copyright (C) 2016 - 2025, EnterpriseDB Corporation. All rights reserved.
#
##########################################################################

"""Renders the headers for all the dashboards and updates the
        no. of alerts info and generated time info accordingly."""
import time

from flask import render_template, current_app
from flask_babel import gettext

from pgadmin.pem.utils import is_edb_server, is_remotely_monitored_server
from ..helpers.settings import dashboard_get_settings


def dashboard_info(pem_conn, did, agent_id=None, server_id=None,
                   database=None):
    """
    This function charts info for monitoring/dashboard page
    :param pem_conn: pem database connection
    :type pem_conn: database connection object
    :param did: database id
    :type did: int
    :param agent_id: agent id
    :type agent_id: int
    :param server_id: server id
    :type server_id: int
    :param database: database name for which we need to fetch alerts
    :type database: str
    :return: res, dashboard info
    :rtype: dict
    """
    res = dict({
        'level': gettext('System'),
        'status': gettext('N/A'),
        'generated': int(time.time() * 1000),
        'alerts': dict({
            'total': 0,
            'acknowledged': 0,
        }),
        'refresh': 30,
    })

    sql = render_template(
        'dashboard/sql/alerts.sql',
        ctx=dict({
            'agent_id': agent_id,
            'server_id': server_id,
            'database': database,
            'schema': None,
        }),
        conn=pem_conn
    )

    status, sresult = pem_conn.execute_dict(sql)

    if not status:
        current_app.logger.error(res)
        return None

    if len(sresult['rows']) != 1:
        return None

    res['settings'] = dashboard_get_settings(pem_conn, did)
    row = sresult['rows'][0]
    res['alerts'] = dict({
        'total': row['total'],
        'acknowledged': row['acknowledged'],
    })

    params = []
    since = -1
    if agent_id is not None:
        res['level'] = gettext('Host Agent')
        params.append(agent_id)
        # 1. Check the status of the agent as UP, DOWN or UNKNOWN.
        # 2. To check status as unknown we check if there is an entry for the
        #    given agent in agent_heartbeat table.
        # 3. To check status as up we check if the
        #    'last_heartbeat value > now - (heartbeat_tolerance+15)' of
        #    the given agent.
        # 4. To check status as down we check if the
        #    'last_heartbeat value < now - (heartbeat_tolerance+15)' of
        #    the given agent.
        sql = """SELECT
                (SELECT
                    CASE WHEN
                        (SELECT CASE WHEN count(id) = 1 THEN 'UNKNOWN' END
                            FROM
                                pem.get_agents_with_status('UNKNOWN')
                                    AS (id integer, description text)
                            WHERE
                                id = pa.id) = 'UNKNOWN' THEN 'UNKNOWN'
                    WHEN
                        (SELECT CASE WHEN count(id) = 1 THEN 'UP' END
                            FROM
                                pem.get_agents_with_status('UP')
                                    AS (id integer, description text)
                            WHERE
                                id = pa.id) = 'UP' THEN 'UP'
                    WHEN
                        (SELECT CASE WHEN count(id) = 1 THEN 'DOWN' END
                            FROM
                                pem.get_agents_with_status('DOWN')
                                    AS (id integer, description text)
                            WHERE
                                id = pa.id) = 'DOWN' THEN 'DOWN'
                    END) "Status"
                FROM
                    pem.avail_agents pa LEFT
                    OUTER JOIN pemdata.os_statistics os
                        ON (pa.id = os.agent_id)
                WHERE
                    pa.active = TRUE AND pa.id = (%s)::int4"""

        status, agent_status = pem_conn.execute_scalar(sql, params)

        if not status:
            agent_status = gettext('UNKNOWN')
            since = -1

        elif agent_status == "UP":
            # If agent is up take system uptime from pemdata.os_info
            status, since = pem_conn.execute_scalar(
                """SELECT EXTRACT(EPOCH FROM
                os_start_time::timestamptz) * 1000
                FROM pemdata.os_info WHERE agent_id=(%s)::int4""",
                params
            )

            if not status:
                since = -1

            agent_status = gettext('UP')

        elif agent_status == "DOWN":
            # is agent is down take last_heartbeat time from
            # pem.agent_heartbeat
            status, since = pem_conn.execute_scalar(
                """SELECT EXTRACT(EPOCH FROM last_heartbeat) * 1000
                FROM pem.agent_heartbeat
                WHERE agent_id = (%s)::int4""",
                params
            )
            if not status:
                since = -1
            agent_status = gettext('DOWN')

        res['status'] = agent_status
        res['since'] = since
    elif server_id is not None:
        res['level'] = gettext('Server')
        params.append(server_id)
        # 1. check the status of the server as UP, DOWN or UNKNOWN
        # 2. to check status as unknown we check if the agent bound to the
        # server is up or not
        # 3. to check status as up we check if the last_heartbeat value < now
        # of the given server and
        # the last_heartbeat value or the
        # server > now - (heartbeat_tolerance+15) of the associated agent
        # 4. to check status as down we check if the last_heartbeat value <
        # now of the given server and
        # the last_heartbeat value of agent > now - (heartbeat_tolerance+15) of
        # the associated agent and
        # the last_heartbeat value of
        # server < now - (heartbeat_tolerance+15) of
        # the associated agent
        sql = """SELECT
                (SELECT
                    CASE WHEN
                        (SELECT
                            CASE WHEN count(id) = 1 THEN 'UNKNOWN' END
                        FROM
                            pem.get_servers_with_status('UNKNOWN') AS (
                                id integer, description text, server text,
                                port integer
                            )
                        WHERE
                            id=ps.id) = 'UNKNOWN' THEN 'UNKNOWN'
                    WHEN
                        (SELECT
                            CASE WHEN count(id) = 1 THEN 'UP' END
                        FROM
                            pem.get_servers_with_status('UP') AS (
                                id integer, description text, server text,
                                port integer
                            )
                        WHERE
                            id=ps.id) = 'UP' THEN 'UP'
                    WHEN
                        (SELECT
                            CASE WHEN count(id) = 1 THEN 'DOWN' END
                        FROM
                            pem.get_servers_with_status('DOWN') AS (
                                id integer, description text, server text,
                                port integer
                            )
                        WHERE
                            id=ps.id) = 'DOWN' THEN 'DOWN'
                    END ) "Status"
                FROM
                    pem.avail_servers ps,
                    pem.agent_server_binding pasb,
                    pem.avail_agents pa
                WHERE
                    ps.id = pasb.server_id AND
                    pa.id = pasb.agent_id AND
                    ps.active = TRUE AND
                    pa.active = TRUE AND
                    ps.id = (%s)::int4"""

        status, server_status = pem_conn.execute_scalar(sql, params)

        if not status:
            server_status = gettext('UNKNOWN')

        if server_status == "UP":
            # if server and its agent are up then show uptime from server_info
            # probe
            status, since = pem_conn.execute_scalar(
                """SELECT EXTRACT(EPOCH FROM server_start_time) * 1000
                FROM pemdata.server_info
                WHERE server_id=(%s)::int4""", params
            )

            if not status:
                since = -1

            server_status = gettext("UP")
        elif server_status == "DOWN":
            # if server is down but agent is up then show the server's last
            # heartbeat from server_heartbeat table
            status, since = pem_conn.execute_scalar(
                """SELECT EXTRACT(EPOCH FROM last_heartbeat) * 1000
                FROM pem.server_heartbeat
                WHERE server_id=(%s)::int4""", params
            )

            if not status:
                since = -1

            server_status = gettext("DOWN")
        else:
            # if agent of the server is down then show the agent's last
            # heartbeat time from agent_heartbeat table
            status, since = pem_conn.execute_scalar(
                """SELECT EXTRACT(EPOCH FROM last_heartbeat) * 1000
                FROM pem.agent_heartbeat
                WHERE agent_id = (
                    SELECT agent_id FROM pem.agent_server_binding
                    WHERE server_id=(%s)::int4
                )
                """, params)

            if not status or since is None or since == '':
                since = -1
            server_status = gettext('UNKNOWN')

        res['status'] = server_status
        res['since'] = since

        if database is not None:
            res['level'] = gettext('Database')

        res['is_edb'] = is_edb_server(pem_conn, server_id)
        res['remotely_monitored'] = is_remotely_monitored_server(
            pem_conn, server_id
        )
        res['locally_monitored'] = not res['remotely_monitored']
        status, rset = pem_conn.execute_dict("""
            WITH replication_info AS (
                SELECT COALESCE(
                        NULLIF(replication_solution, ''),
                        'none'
                    ) AS repl
                FROM pem.server
                WHERE id = (%(sid)s)::int4
            )
            SELECT 'wal_archive' AS name,
                (SELECT count(*) > 0
                    FROM pemdata.wal_archive_status
                    WHERE server_id = (%(sid)s)::int4) AS status
            UNION ALL
            SELECT 'streaming_replication' AS name,
                (SELECT count(*) > 0
                    FROM pemdata.streaming_replication
                    WHERE server_id = (%(sid)s)::int4) AS status
            UNION ALL
            SELECT 'streaming_replication_lag_time' AS name,
                (SELECT count(*) > 0
                    FROM pemdata.streaming_replication_lag_time
                    WHERE server_id = (%(sid)s)::int4) AS status
            UNION ALL
            SELECT 'efm_cluster_node_status' AS name,
                CASE WHEN repl = 'efm' THEN
                    (SELECT count(*) > 0
                        FROM pemdata.efm_cluster_node_status
                        WHERE server_id = (%(sid)s)::int4)
                ELSE FALSE END
            FROM replication_info
            UNION ALL
            SELECT 'efm_cluster_info' AS name,
                CASE WHEN repl = 'efm' THEN
                    (SELECT count(*) > 0
                        FROM pemdata.efm_cluster_info
                        WHERE server_id = (%(sid)s)::int4)
                ELSE FALSE END
            FROM replication_info
            UNION ALL
            SELECT 'patroni_node_status' AS name,
                CASE WHEN repl = 'patroni' THEN
                    (SELECT count(*) > 0
                        FROM pemdata.patroni_node_status
                        WHERE server_id = (%(sid)s)::int4)
                ELSE FALSE END
            FROM replication_info
            UNION ALL
            SELECT 'patroni_cluster_status' AS name,
                CASE WHEN repl = 'patroni' THEN
                    (SELECT count(*) > 0
                        FROM pemdata.patroni_cluster_status
                        WHERE server_id = (%(sid)s)::int4)
                ELSE FALSE END
            FROM replication_info
        """, {'sid': server_id})

        res['show_streaming_dashboard'] = False
        if status is True:
            for row in rset['rows']:
                res[row['name']] = row['status']
                if row['status'] is True:
                    res['show_streaming_dashboard'] = True

    return res
