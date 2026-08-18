WITH server_status AS (
    SELECT
        ps.id AS server_id, pa.id AS agent_id, ps.alert_blackout AS blackout,
        ps.description AS name, ps.is_remote_monitoring AS remote_monitoring,
        CASE
            WHEN pa.active IS NOT NULL AND pa.active AND
                psh.last_heartbeat IS NOT NULL AND
                psh.last_heartbeat < now() AND
                psh.last_heartbeat > (
                    now() - ((pa.heartbeat_tolerance + 15) * '1 second'::interval)
                )
                THEN 'UP'
            WHEN pa.active IS NOT NULL AND pa.active AND
                pah.last_heartbeat IS NOT NULL AND
                pah.last_heartbeat < now() AND
                pah.last_heartbeat > (
                    now() - ((pa.heartbeat_tolerance + 15) * '1 second'::interval)
                ) AND
                psh.last_heartbeat IS NOT NULL AND
                psh.last_heartbeat < (
                    now() - ((pa.heartbeat_tolerance + 15) * '1 second'::interval)
                )
                THEN 'DOWN'
            WHEN pasb.agent_id is NULL
                THEN 'UNMANAGED'
            ELSE 'UNKNOWN'
        END AS status, ps.group_id
    FROM
        pem.avail_servers ps
        LEFT OUTER JOIN pem.server_heartbeat psh ON (ps.id = psh.server_id)
        LEFT OUTER JOIN pem.agent_server_binding pasb ON (
            ps.id = pasb.server_id
        )
        LEFT OUTER JOIN pem.avail_agents pa ON (
            pasb.agent_id = pa.id AND psh.agent_id = pa.id
        )
        LEFT OUTER JOIN pem.agent_heartbeat pah ON (
            pah.agent_id = pasb.agent_id
        )
    WHERE
        ps.active = true{% if server_id is not none %} AND
        ps.id = {{ server_id }}{% endif %}
),
user_overridden_server_groups AS (
    SELECT * FROM pem.user_server_group WHERE uid = pem.current_user_id()
),
all_available_server_groups AS (
    SELECT  sg.id,
        COALESCE(usg.name, sg.name) AS name,
        COALESCE(usg.hidden, false) AS hidden
    FROM pem.server_group sg
    LEFT JOIN user_overridden_server_groups usg
        ON sg.id = usg.id
    WHERE usg.deleted IS NULL OR NOT usg.deleted
    ORDER BY NAME
)
SELECT
    sg.id AS group_id, sg.name AS group_name, s.server_id, s.blackout, s.name, s.status, (
      SELECT json_build_object(
        'sessions', json_agg(
          json_build_object(
            'database_name', database_name,
            'procpid', procpid,
            'usename', usename,
            'backend_start', EXTRACT(EPOCH FROM backend_start),
            'xact_start', EXTRACT(EPOCH FROM xact_start),
            'query_start', EXTRACT(EPOCH FROM query_start),
            'is_waiting', is_waiting,
            'is_idle', is_idle,
            'is_idle_in_transaction', is_idle_in_transaction,
            'is_vacuum', is_vacuum,
            'is_autovacuum', is_autovacuum,
            'client_addr', client_addr,
            'client_port', client_port,
            'memory_usage_mb', memory_usage_mb,
            'swap_usage_mb', swap_usage_mb,
            'cpu_usage', cpu_usage,
            'io_read_bytes', io_read_bytes,
            'io_write_bytes', io_write_bytes,
            'state', state,
            'state_change', EXTRACT(EPOCH FROM state_change)
          )
        ),
        'last_recorded_time', EXTRACT(EPOCH FROM max(recorded_time))
      )
      FROM pemdata.session_info si WHERE si.server_id = s.server_id
    ) AS sessions,
    CASE
        WHEN status = 'UP' THEN
            (SELECT sum(pds.numbackends) FROM pemdata.database_statistics pds
                WHERE pds.server_id = s.server_id)
        ELSE 0
    END AS number_connections, (
      SELECT
      json_build_object(
        'total', count(pa.id),
        'acknowledged', count(CASE WHEN pa.acknowledged THEN TRUE END),
        'high', COUNT(CASE WHEN pas.current_state = 'HIGH' THEN TRUE END),
        'medium', COUNT(CASE WHEN pas.current_state = 'MEDIUM' THEN TRUE END),
        'low', COUNT(CASE WHEN pas.current_state = 'LOW' THEN TRUE END),
        'high_acknowledged', COUNT(
          CASE
          WHEN pas.current_state = 'HIGH' AND pa.acknowledged THEN TRUE
          END
        ),
        'medium_acknowledged', COUNT(
          CASE
          WHEN pas.current_state = 'MEDIUM' AND pa.acknowledged THEN TRUE
          END
        ),
        'low_acknowledged', COUNT(
          CASE
          WHEN pas.current_state = 'LOW' AND pa.acknowledged THEN TRUE
          END
        )
      )
      FROM pem.alert pa
        LEFT JOIN pem.alert_status pas ON (pa.id = pas.alert_id)
      WHERE pa.server_id = s.server_id AND pa.enabled AND
        COALESCE(pa.error_message, '') = ''
    ) AS alerts, (
        SELECT version_string FROM pemdata.server_info
        WHERE server_id=s.server_id
    ) AS version, s.remote_monitoring,
    s.agent_id
FROM
    server_status s
    LEFT OUTER JOIN all_available_server_groups sg ON (
      sg.id = s.group_id
    );
