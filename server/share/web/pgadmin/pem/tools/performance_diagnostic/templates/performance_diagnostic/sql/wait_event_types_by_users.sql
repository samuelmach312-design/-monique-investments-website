SELECT a.username AS username,
    ARRAY_AGG(a.wait_event_type_by_count ORDER BY a.wait_event_type_by_count->>'wait_event_type')::json[] AS load_by_waits,
    SUM(wait_events_count) as number_of_events,
    SUM(a.execution_count) as execution_count
FROM (
        SELECT
            s.username,
            COUNT(s.query_start_time) AS execution_count,
            s.wait_event_type,
            COUNT(
            CASE
                WHEN s.wait_event_type IS NOT NULL AND s.wait_event IS NOT NULL THEN s.wait_event
            END) AS wait_events_count,
            CAST('{"wait_event_type":"' || s.wait_event_type || '","count":'|| COUNT(s.wait_event_type) || '}' AS json)
            AS wait_event_type_by_count,
            COUNT(s.wait_event_type) AS wait_event_type_count
        FROM
            edb_wait_states_data(
                to_timestamp((%(time_stamp)s)::float - 1),
                to_timestamp((%(time_stamp)s)::float + 1)
            ) s
        WHERE
            EXTRACT(EPOCH FROM s.sample_time)::int8 = %(time_stamp)s::int8
        GROUP BY s.username, s.wait_event_type
        ORDER BY wait_event_type_count DESC
     ) AS a
GROUP BY a.username
ORDER BY SUM(wait_event_type_count) DESC;
