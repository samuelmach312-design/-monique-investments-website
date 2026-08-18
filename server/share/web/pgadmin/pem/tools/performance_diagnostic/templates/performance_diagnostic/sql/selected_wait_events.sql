SELECT sample_time, COALESCE(wait_event_type, 'CPU') AS wait_event_type, count(*) AS cnt
FROM (
    SELECT
        EXTRACT(EPOCH FROM sample_time) * 1000 AS sample_time,
        wait_event_type
    FROM edb_wait_states_samples(
        to_timestamp((%s)::float),
        to_timestamp((%s)::float)
    )
) AS s GROUP BY 1, 2 ORDER BY 1, 2
