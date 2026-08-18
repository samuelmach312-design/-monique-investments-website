WITH agent_status AS (
    SELECT
        pa.id AS id, pa.alert_blackout AS blackout, pa.description AS name,
        pa.version AS version,
        CASE
        WHEN (
            pah.agent_id IS NOT NULL AND
            pah.last_heartbeat < now() AND
            pah.last_heartbeat > (
                now() - ((pa.heartbeat_tolerance + 15) * '1 second'::interval)
            )
        ) THEN 'UP'
        WHEN (
            pah.agent_id IS NOT NULL AND
            pah.last_heartbeat < (
                now() - ((pa.heartbeat_tolerance + 15) * '1 second'::interval)
            )
        ) THEN 'DOWN'
        ELSE 'UNKNOWN'
        END AS status,
        group_id
    FROM
        pem.avail_agents pa
        LEFT OUTER JOIN pem.agent_heartbeat pah ON (pa.id = pah.agent_id)
    WHERE
        pa.active = TRUE {% if agent_id is not none %} AND
        pa.id = {{ agent_id }}{% endif %}
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
    sg.id AS group_id, sg.name AS group_name, pa.id, pa.blackout, pa.name, pa.status, (
        SELECT json_build_object(
          'total', count(*),
          'acknowledged', count(CASE WHEN pal.acknowledged THEN TRUE END),
          'high', COUNT(CASE WHEN pas.current_state = 'HIGH' THEN TRUE END),
          'medium', COUNT(CASE WHEN pas.current_state = 'MEDIUM' THEN TRUE END),
          'low', COUNT(CASE WHEN pas.current_state = 'LOW' THEN TRUE END),
          'high_acknowledged', COUNT(CASE WHEN pas.current_state = 'HIGH' AND pal.acknowledged THEN TRUE END),
          'medium_acknowledged', COUNT(CASE WHEN pas.current_state = 'MEDIUM' AND pal.acknowledged THEN TRUE END),
          'low_acknowledged', COUNT(CASE WHEN pas.current_state = 'LOW' AND pal.acknowledged THEN TRUE END)
        ) FROM pem.alert pal
        LEFT OUTER JOIN pem.alert_status pas ON (pal.id = pas.alert_id)
        WHERE
            pal.agent_id = pa.id AND pal.enabled=true AND
            COALESCE(pal.error_message, '') = ''
    ) AS alerts,
    pa.version,
    CASE
    WHEN pa.status = 'UP' THEN os.total_process_count ELSE 0 END
      AS processes,
    CASE
    WHEN pa.status = 'UP' THEN os.total_thread_count ELSE 0 END
      AS threads,
    CASE
        WHEN pa.status = 'UP' THEN
            (SELECT
                CASE WHEN avg(load_percentage) = 0 THEN 0
                    ELSE round(avg(load_percentage)::numeric, 2)
                END
            FROM pemdata.cpu_usage WHERE agent_id = pa.id)
        ELSE 0
    END AS cpu_utilization,
    CASE
        WHEN pa.status = 'UP' THEN (
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
    END AS memory_utilization,
    CASE
    WHEN pa.status = 'UP' THEN (
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
    END AS swap_utilization,
    CASE
    WHEN pa.status = 'UP' THEN (
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
    END AS disk_utilization
FROM
    agent_status AS pa
    LEFT OUTER JOIN pemdata.os_statistics os ON (pa.id = os .agent_id)
    LEFT OUTER JOIN all_available_server_groups sg ON (pa.group_id = sg.id)
