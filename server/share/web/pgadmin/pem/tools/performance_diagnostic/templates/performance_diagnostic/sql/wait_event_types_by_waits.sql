SELECT
    a.wait_event,
    a.wait_event_type,
    a.wait_events_count,
	a.total_waits,
	ARRAY_AGG(a.load_by_event ORDER BY a.load_by_event->>'wait_event')::json[] AS load_by_event
    FROM (
        SELECT
            s.wait_event,
            s.wait_event_type,
            CAST(
                '{"wait_event":"' || s.wait_event ||
                '","wait_event_type":"' || s.wait_event_type ||
                '","count":'|| COUNT(s.wait_event) || '}' AS json
            ) AS load_by_event,
            COUNT(s.wait_event) AS wait_events_count,
		    SUM(COUNT(s.wait_event)) OVER (PARTITION BY s.wait_event_type) AS total_waits
        FROM
            edb_wait_states_data(
                to_timestamp((%(time_stamp)s)::float - 1),
                to_timestamp((%(time_stamp)s)::float + 1)
            ) s
        WHERE
            EXTRACT(EPOCH FROM s.sample_time)::int8 = %(time_stamp)s::int8
            AND wait_event_type IS NOT NULL
            AND wait_event IS NOT NULL
        GROUP BY s.wait_event, s.wait_event_type
        ORDER BY wait_events_count DESC
) AS a
GROUP BY a.wait_event, a.wait_event_type, a.wait_events_count, a.total_waits
ORDER BY wait_events_count DESC
