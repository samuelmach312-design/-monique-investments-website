SELECT
    DISTINCT se.session_id, se.username, se.dbname
FROM edb_wait_states_samples(
    to_timestamp((%(sample_time)s)::float - 1),
    to_timestamp((%(sample_time)s)::float + 1)
) sa
LEFT OUTER JOIN (
    SELECT * FROM edb_wait_states_sessions(
        to_timestamp((%(sample_time)s)::float - 1),
        to_timestamp((%(sample_time)s)::float + 1)
    )
) se ON sa.session_id = se.session_id
WHERE sa.query_id = (%(query_id)s)::bigint AND
    EXTRACT(EPOCH FROM sa.sample_time)::int8 = %(sample_time)s::int8
ORDER BY 1;
