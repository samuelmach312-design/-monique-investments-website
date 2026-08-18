SELECT sample_time, COALESCE(wait_event_type, 'CPU') AS wait_event_type, count(*) AS cnt
FROM (
    SELECT
        (((EXTRACT(EPOCH FROM sample_time) / 15)::bigint * 15) + 15) * 1000 AS sample_time,
        wait_event_type
    FROM edb_wait_states_samples(
        to_timestamp({{ filter_date_time|qtLiteral(conn) }}::float) - interval {{ last_hour|qtLiteral(conn, true) }},
        to_timestamp({{ filter_date_time|qtLiteral(conn) }}::float)
    )
) AS s GROUP BY 1, 2 ORDER BY 1, 2
