WITH all_wait_events AS
(
    SELECT
        s.query_id,
        q.query,
        COALESCE(s.wait_event_type, 'CPU') AS wait_event_type,
        COUNT(DISTINCT s.session_id) AS number_of_sessions,
        CAST('{"wait_event_type":"' || COALESCE(s.wait_event_type, 'CPU') || '","count":'|| COUNT(*) || '}' AS json) AS wait_event_type_by_count,
        COUNT(*) AS wait_event_type_count
    FROM
        edb_wait_states_samples(
            to_timestamp((%(time_stamp)s)::float - 1),
            to_timestamp((%(time_stamp)s)::float + 1)
        ) s
        LEFT OUTER JOIN (
            SELECT DISTINCT query_id, query
            FROM edb_wait_states_queries(
                to_timestamp((%(time_stamp)s)::float - 1),
                to_timestamp((%(time_stamp)s)::float + 1)
            )
        ) q ON q.query_id = s.query_id
    WHERE
    EXTRACT(EPOCH FROM s.sample_time)::int8 = (%(time_stamp)s::int8)
    GROUP BY 1, 2, 3
)
SELECT
    a.query_id,
    a.query AS sql,
    ARRAY_AGG(
        a.wait_event_type_by_count ORDER BY a.wait_event_type_by_count->>'wait_event_type'
    )::json[] AS load_by_waits,
    SUM(wait_event_type_count) AS total_waits,
    b.number_of_sessions AS number_of_sessions
FROM
    all_wait_events AS a
    LEFT OUTER JOIN (
        SELECT se.query_id,
        SUM(number_of_sessions) AS number_of_sessions
        FROM all_wait_events AS se
        GROUP BY se.query_id
    ) AS b
    ON a.query_id = b.query_id
GROUP BY a.query_id, a.query , b.number_of_sessions
ORDER BY SUM(wait_event_type_count) DESC;
