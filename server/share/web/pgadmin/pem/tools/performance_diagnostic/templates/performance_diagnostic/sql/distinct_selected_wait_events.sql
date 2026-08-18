SELECT
    distinct(wait_event_type)
FROM
    edb_wait_states_samples(
      to_timestamp((%s)::float),
      to_timestamp((%s)::float)
    )
WHERE
    wait_event_type IS NOT NULL
GROUP BY
    sample_time, wait_event_type
ORDER BY 1;
