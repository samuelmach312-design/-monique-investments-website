SELECT
    query_start_time AS query_start_time,
    EXTRACT(EPOCH FROM (query_start_time - INTERVAL '100 milliseconds')) AS min_sample_time,
    NOT pg_is_in_recovery() AND pg_catalog.has_database_privilege(
        current_database(), 'TEMP'
    ) AS require_permision
FROM
    edb_wait_states_samples(
        to_timestamp(((%(time_stamp)s)::float / 1000)::bigint - 1),
        to_timestamp(((%(time_stamp)s)::float / 1000)::bigint + 1)
    )
WHERE query_id = (%(query_id)s)::int8 AND
    session_id = (%(session_id)s)::int4 AND
    EXTRACT(EPOCH FROM sample_time)::int = ((%(time_stamp)s)::double precision / 1000)::int;
