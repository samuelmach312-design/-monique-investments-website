WITH barman_backups AS (
SELECT tool_id, server, backup_id, begin_time, end_time, mode, status, error
    FROM pemdata.barman_server_backup
UNION ALL
SELECT tool_id, server, backup_id, begin_time, end_time, mode, status, error
    FROM pemhistory.barman_server_backup phbs
    WHERE backup_id NOT IN (SELECT backup_id FROM pemdata.barman_server_backup pbs WHERE pbs.tool_id = phbs.tool_id)
)
SELECT
    'barman_backup' AS action,
    psb.server,
    (EXTRACT(EPOCH FROM psb.begin_time) * 1000)::numeric(40, 0) AS start_time,
    (EXTRACT(EPOCH FROM psb.end_time) * 1000)::numeric(40, 0) AS end_time,
    CASE
        WHEN psb.end_time IS NOT NULL THEN
            (psb.end_time - psb.begin_time)::interval
        ELSE NULL::interval
    END AS duration,
    psb.mode,
    LOWER(psb.status) AS status,
    COALESCE(psb.error, '') AS error_message
FROM barman_backups psb
WHERE tool_id = {{bsid|qtLiteral(conn)}}::int
    AND (EXTRACT(EPOCH FROM psb.begin_time) * 1000)::numeric(40, 0) >= {{ until|qtLiteral(conn) }}::numeric - (EXTRACT(epoch FROM interval '{{duration}} days') * 1000)
    AND (EXTRACT(EPOCH FROM psb.begin_time) * 1000)::numeric(40, 0) <= {{ until|qtLiteral(conn) }}::numeric
{% if server %}
AND psb.server = '{{server|qtLiteral(conn)}}'::text
{% endif %}
ORDER BY action, begin_time;
