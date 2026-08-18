SELECT
    EXTRACT(EPOCH FROM sample_time) * 1000 AS sample_time,
    COALESCE(wait_event_type::text, 'CPU'::text)
        AS wait_event_types,
    COALESCE(wait_event::text, 'CPU'::text) AS wait_events,
    1
FROM edb_wait_states_samples(
    to_timestamp((%(sample_start_time))::float) + INTERVAL (
        ((%(idx)s)::int8 * 15) || ' minutes'
    ),
    to_timestamp((%(sample_start_time))::float) + INTERVAL (
        (((%(idx)s)::int8 + 1) * 15) || ' minutes'
    )
)
WHERE query_id = (%(query_id)s)::int8 AND
    session_id = (%(session_id)s)::int4 AND
    query_start_time = (%(query_start_time)s)::timestamptz
ORDER BY 1, 2, 3
