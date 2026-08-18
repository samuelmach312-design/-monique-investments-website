WITH all_wait_events AS (
	SELECT
		q.query_id, q.query,
		s.session_id, s.dbname, s.username,
		sa.query_start_time, sa.sample_time,
		COALESCE(sa.wait_event_type, 'CPU') AS wait_event_type,
		sa.wait_event AS wait_event
	FROM
		edb_wait_states_samples(
			to_timestamp((%(start_epoch)s)::float),
			to_timestamp((%(end_epoch)s)::float)
		) sa
		INNER JOIN
		edb_wait_states_sessions(
			to_timestamp((%(start_epoch)s)::float),
			to_timestamp((%(end_epoch)s)::float)
		) s ON (sa.session_id = s.session_id)
		LEFT OUTER JOIN
		edb_wait_states_queries(
			to_timestamp((%(start_epoch)s)::float),
			to_timestamp((%(end_epoch)s)::float)
		) q ON (sa.query_id = q.query_id)
),
queries_by_wait_events AS (
	SELECT
		query_id,
		query,
		wait_event_type,
		wait_event,
		COUNT(1) filter (WHERE wait_event_type != 'CPU') AS wait_event_count,
		COUNT(1) filter (WHERE wait_event_type = 'CPU') AS cpu_count
	FROM all_wait_events
	GROUP BY 1, 2, 3, 4
),
events AS (
	SELECT
		query_id,
		query,
		sum(wait_event_count) AS wait_event_count,
		sum(cpu_count) AS cpu_count,
		jsonb_agg(
			jsonb_build_object(
				'wait_event_type', wait_event_type,
				'wait_event', wait_event,
				'count', cpu_count + wait_event_count
			)
			ORDER BY wait_event_type, wait_event
		) AS wait_events
	FROM
		queries_by_wait_events
	GROUP BY 1, 2
),
sessions_per_queries AS (
	SELECT
		query_id,
		count(DISTINCT query_start_time) AS queries_count,
		count(DISTINCT dbname) AS databases_count,
		count(DISTINCT username) AS users_count
	FROM all_wait_events GROUP BY query_id
),
sessions_per_users AS (
	SELECT
		username,
		dbname,
		count(DISTINCT (session_id, query_start_time)) AS queries_count,
		COUNT(1) filter (where wait_event_type != 'CPU') AS wait_event_count,
		COUNT(1) filter (where wait_event_type = 'CPU') AS cpu_count
	FROM all_wait_events
	GROUP BY username, dbname
),
wait_states_per_users AS (
	SELECT
		username,
		dbname,
		jsonb_build_object(
			'wait_event_type', wait_event_type,
			'wait_event', wait_event,
			'count', count(1)
		) AS wait_events
	FROM
		all_wait_events
	GROUP BY username, dbname, wait_event_type, wait_event 
),
top_queries_per_wait_events AS (
	SELECT
		e.query_id,
		s.queries_count,
		s.databases_count, s.users_count,
		e.wait_event_count, e.cpu_count,
		e.query, e.wait_events
	FROM
		events e
		LEFT OUTER JOIN sessions_per_queries s ON (e.query_id = s.query_id)
	WHERE wait_event_count > 0
	ORDER BY wait_event_count DESC, cpu_count DESC
	LIMIT {% if limit is defined %}{{ limit | int }}{% else %}20{% endif %}
),
top_queries_per_cpu AS (
	SELECT
		e.query_id,
		s.queries_count,
		s.databases_count, s.users_count,
		e.wait_event_count, e.cpu_count,
		e.query, e.wait_events
	FROM
		events e
		LEFT OUTER JOIN sessions_per_queries s ON (e.query_id = s.query_id)
	WHERE cpu_count > 0
	ORDER BY cpu_count DESC, wait_event_count DESC
	LIMIT {% if limit is defined %}{{ limit | int }}{% else %}20{% endif %}
),
top_users_per_wait_events AS (
	SELECT
		s.username, s.dbname,
		s.queries_count,
		s.wait_event_count, s.cpu_count,
		w.wait_events AS wait_events
	FROM
		sessions_per_users s
		LEFT OUTER JOIN (
			SELECT
				username, dbname,
				jsonb_agg(
					wait_events
					ORDER BY wait_events->>'wait_event_type', wait_events->>'wait_event'
				) AS wait_events
			FROM wait_states_per_users
			GROUP BY username, dbname
		) w ON (s.username = w.username AND s.dbname = w.dbname)
	WHERE wait_event_count > 0
	ORDER BY wait_event_count DESC
	LIMIT {% if limit is defined %}{{ limit | int }}{% else %}20{% endif %}
),
top_users_per_cpu AS (
	SELECT
		s.username, s.dbname,
		s.queries_count,
		s.wait_event_count, s.cpu_count,
		w.wait_events AS wait_events
	FROM
		sessions_per_users s
		LEFT OUTER JOIN (
			SELECT
				username, dbname, jsonb_agg(
					wait_events
					ORDER BY wait_events->>'wait_event_type', wait_events->>'wait_event'
				) AS wait_events
			FROM wait_states_per_users
			GROUP BY username, dbname
		) w ON (s.username = w.username AND s.dbname = w.dbname)
	WHERE cpu_count > 0
	ORDER BY cpu_count DESC
	LIMIT {% if limit is defined %}{{ limit | int }}{% else %}20{% endif %}
)
SELECT
	'top_queries_by_wait_events' AS kind, json_agg(qw) AS data
FROM top_queries_per_wait_events qw
UNION ALL
SELECT
	'top_queries_by_cpu_usage' AS kind, json_agg(qc) AS data
FROM top_queries_per_cpu qc
UNION ALL
SELECT
	'top_users_by_wait_events' AS kind, json_agg(uw) AS data
FROM top_users_per_wait_events uw
UNION ALL
SELECT
	'top_users_by_cpu_usage' AS kind, json_agg(uc) AS data
FROM top_users_per_cpu uc
;
