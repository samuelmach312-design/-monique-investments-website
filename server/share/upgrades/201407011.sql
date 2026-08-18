/*
// Postgres Enterprise Manager
//
// Copyright (C) 2010 - 2025, EnterpriseDB Corporation. All rights reserved.
//
// Portions of Postgres Enteprise Manager are derived from pgAgent, which is
// released under the PostgreSQL License.
// Copyright (C) 2002 - 2010 The pgAdmin Development Team
//
*/

BEGIN TRANSACTION;

CREATE OR REPLACE FUNCTION pem.schema_version()
  RETURNS integer AS
'SELECT 201407011::integer;'
  LANGUAGE 'sql' IMMUTABLE;

UPDATE pem.logexp_charts SET lables = ARRAY['Query', 'Parameters', 'No.Of Times Executed', 'Total Duration (ms)', 'Min Duration (ms)', 'Max Duration (ms)']
WHERE analyzer_name IN ('Frequently Executed Query Statistics', 'Most Time Consumed Query Statistics');

CREATE OR REPLACE FUNCTION pem.loganalysis_freqexe_queries(sdate TIMESTAMP, edate TIMESTAMP, server_id INT, tlimit INT DEFAULT 20) RETURNS REFCURSOR
AS
$BODY$
DECLARE
loganalysis_freqexe_queries_ref REFCURSOR:= 'loganalysis_freqexe_queries';
loganalysis_mosttimeexe_queries_ref REFCURSOR:= 'loganalysis_mosttimeexe_queries';
query text := '';

BEGIN

	IF ((sdate IS NULL OR edate IS NULL) OR (sdate > edate)) THEN
		RAISE EXCEPTION 'LOGANALYSIS_FREQEXE_QUERIES: Invalid time.';
	END IF;

	IF (server_id IS NULL OR server_id < 0) THEN
		RAISE EXCEPTION 'LOGANALYSIS_FREQEXE_QUERIES: Invalid server id.';
	END IF;

	IF (tlimit IS NULL OR tlimit<=0 ) THEN
		RAISE EXCEPTION 'LOGANALYSIS_FREQEXE_QUERIES: Invalid table limit.';
	END IF;

	-- Queries executed most frequently

	query :=
		$$
		SELECT
			query,
			parameters,
			COUNT(query) AS no_of_times_executed,
			ROUND(SUM(duration), 2) AS total_duration,
			ROUND(min(duration), 2) AS "Min Duration",
			ROUND(max(duration), 2) AS "Max Duration"
		FROM
		(
		SELECT
		(SUBSTRING(SUBSTRING(message FROM '^duration: [0-9\.]+ ms') FROM '[0-9\.]+')::NUMERIC) AS duration,
			TRIM(BOTH ' ' FROM
			SPLIT_PART(message,
			SUBSTRING(message FROM '^duration:\s+[0-9\.]+\s+ms\s*(?:prepare|parse|bind|execute from fetch|execute|statement)(?:\s+<(?:[^>]|>)+>)?:'), 2)) as query,
			detail AS parameters
		FROM
			pemdata.server_logs
		WHERE
		message LIKE 'duration:%' AND message ~ '^duration:\s+[0-9\.]+\s+ms\s*(?:prepare|parse|bind|execute from fetch|execute|statement)' AND
		server_id = $3::INT AND
			error_severity = 'LOG'
			AND pem.date_trunc_minutes(log_time) BETWEEN $1::TIMESTAMP AND $2::TIMESTAMP
		) AS freq_executed_queries
		GROUP BY query, parameters
		ORDER BY 3 DESC
		LIMIT $4::INT
		$$;

	OPEN loganalysis_freqexe_queries_ref FOR EXECUTE query USING sdate, edate, server_id, tlimit;
	RETURN loganalysis_freqexe_queries_ref;

END;
$BODY$
LANGUAGE PLPGSQL;

CREATE OR REPLACE FUNCTION pem.loganalysis_mosttime_exec_queries(sdate TIMESTAMP, edate TIMESTAMP, server_id INT, tlimit INT DEFAULT 20) RETURNS REFCURSOR
AS
$BODY$
DECLARE
loganalysis_mosttimeexe_queries_ref REFCURSOR:= 'loganalysis_mosttimeexe_queries';
query text := '';

BEGIN

	IF ((sdate IS NULL OR edate IS NULL) OR (sdate > edate)) THEN
		RAISE EXCEPTION 'LOGANALYSIS_MOSTTIMEEXE_QUERIES: Invalid time.';
	END IF;

	IF (server_id IS NULL OR server_id < 0) THEN
		RAISE EXCEPTION 'LOGANALYSIS_MOSTTIMEEXE_QUERIES: Invalid server id.';
	END IF;

	IF (tlimit IS NULL OR tlimit<=0 ) THEN
		RAISE EXCEPTION 'LOGANALYSIS_MOSTTIMEEXE_QUERIES: Invalid table limit.';
	END IF;


	query :=
		$$
		SELECT
			query,
			parameters,
			COUNT(query) AS no_of_times_executed,
			ROUND(SUM(duration), 2) AS total_duration,
			ROUND(min(duration), 2) AS "Min Duration",
			ROUND(max(duration), 2) AS "Max Duration"
		FROM
		(
		SELECT
			(SUBSTRING(SUBSTRING(message FROM '^duration: [0-9\.]+ ms') FROM '[0-9\.]+')::NUMERIC) AS duration,
			TRIM(BOTH ' ' FROM
			SPLIT_PART(message,
			SUBSTRING(message FROM '^duration:\s+[0-9\.]+\s+ms\s*(?:prepare|parse|bind|execute from fetch|execute|statement)(?:\s+<(?:[^>]|>)+>)?:'), 2)) as query,
			detail AS parameters
		FROM
			pemdata.server_logs
		WHERE
			message LIKE 'duration:%' AND message ~ '^duration:\s+[0-9\.]+\s+ms\s*(?:prepare|parse|bind|execute from fetch|execute|statement)' AND
			server_id = $3::INT AND
			error_severity = 'LOG'
			AND pem.date_trunc_minutes(log_time) BETWEEN $1::TIMESTAMP AND $2::TIMESTAMP
		) AS freq_executed_queries
		GROUP BY query, parameters
		ORDER BY 4 DESC
		LIMIT $4::INT
		$$;
	OPEN loganalysis_mosttimeexe_queries_ref FOR EXECUTE query USING sdate, edate, server_id, tlimit;
	RETURN loganalysis_mosttimeexe_queries_ref;
END;
$BODY$
LANGUAGE PLPGSQL;

INSERT INTO pem.chart_func(id, type, func, r_sys_obj) VALUES
	(87, 'Q', E'SELECT idx, label, ''Date('' || (EXTRACT(EPOCH FROM agg_time) * 1000)::numeric(40, 0)::text || '')'', agg_val FROM pem.generate_server_pages_written ($1::int4, $2::timestamptz, $3::timestamptz) ORDER BY idx, agg_time', false);

INSERT INTO pem.chart
	(id, cid, fid, type,      level,                                           name, owner, shared, ref_cnt, reload, summary,                                                            labels,                                      params,            rwlimit_span_param,                     ref_timeout_param)
	VALUES
	(87,  11,  87,  'L', ARRAY[200], 'Pages Written (Background Writer) Statistics',     0,   NULL,       1,  50000,    NULL, ARRAY['Checkpoint Processes', 'Background Writer', 'By Backends'], ARRAY['agent_id', 'start_time', 'end_time'], 'dash_server_buffers_written', 'dash_server_buffers_written_timeout');
INSERT INTO pem.line_chart (cid, type, yaxis) VALUES (87, 'M', '(%)');
INSERT INTO pem.metrices_chart (cid, time_span, max_points) VALUES (87, '7 days'::interval, 100);

INSERT INTO pem.config (param, value, unit, datatype) VALUES
	('dash_server_buffers_written', '168', 'hours', 'integer'),
	('dash_server_buffers_written_timeout', '1800', 'seconds', 'integer');

UPDATE pem.chart SET params = '{agent_id, start_time, end_time}'::character varying[] WHERE id = 39;
UPDATE pem.chart SET params = '{server_id, start_time, end_time}'::character varying[] WHERE id IN (55, 81, 82);
UPDATE pem.chart SET params = '{server_id, database_name, start_time, end_time}'::character varying[] WHERE id IN (11, 85, 86);

UPDATE pem.chart_func SET func = E'SELECT o_idx, o_label, ''Date('' || (EXTRACT(EPOCH FROM o_aggtime) * 1000)::numeric(40, 0)::text || '')'', o_aggval FROM pem.generate_conn_overview_chart_data(11, $1::int4, $2::text, $3::timestamptz, $4::timestamptz) ORDER BY o_idx, o_aggtime' WHERE id = 11;
UPDATE pem.chart_func SET func = E'SELECT o_idx, o_label, ''Date('' || (EXTRACT(EPOCH FROM o_aggtime) * 1000)::numeric(40, 0)::text || '')'', o_aggval FROM pem.generate_conn_overview_chart_data(55, $1::int4, NULL::text, $2::timestamptz, $3::timestamptz) ORDER BY o_idx, o_aggtime' WHERE id = 55;
UPDATE pem.chart_func SET func = E'SELECT o_idx, o_label, ''Date('' || (EXTRACT(EPOCH FROM o_aggtime) * 1000)::numeric(40, 0)::text || '')'', o_aggval FROM pem.generate_host_memory_chart_data($1::int4, $2::timestamptz, $3::timestamptz) ORDER BY o_idx, o_aggtime' WHERE id = 39;
UPDATE pem.chart_func SET func = E'SELECT o_idx, o_label, ''Date('' || (EXTRACT(EPOCH FROM o_aggtime) * 1000)::numeric(40, 0)::text || '')'', o_aggval FROM pem.generate_replication_segment_lag_chart_data($1::int4, $2::timestamptz, $3::timestamptz) ORDER BY o_idx, o_aggtime' WHERE id = 81;
UPDATE pem.chart_func SET func = E'SELECT o_idx, o_label, ''Date('' || (EXTRACT(EPOCH FROM o_aggtime) * 1000)::numeric(40, 0)::text || '')'', o_aggval FROM pem.generate_replication_page_lag_chart_data($1::int4, $2::timestamptz, $3::timestamptz) ORDER BY o_idx, o_aggtime' WHERE id = 82;
UPDATE pem.chart_func SET func = E'SELECT o_idx, o_label, ''Date('' || (EXTRACT(EPOCH FROM o_aggtime) * 1000)::numeric(40, 0)::text || '')'', o_aggval FROM pem.generate_slony_event_lag_chart_data($1::int4, $2::text, $3::timestamptz, $4::timestamptz) ORDER BY o_idx, o_aggtime' WHERE id = 85;
UPDATE pem.chart_func SET func = E'SELECT o_idx, o_label, ''Date('' || (EXTRACT(EPOCH FROM o_aggtime) * 1000)::numeric(40, 0)::text || '')'', o_aggval FROM pem.generate_slony_time_lag_chart_data($1::int4, $2::text, $3::timestamptz, $4::timestamptz) ORDER BY o_idx, o_aggtime' WHERE id = 86;

-- Change the unit of span to 'hours' from 'days'
UPDATE pem.config
	SET value=(value::integer * 24)::text, unit='hours'
	WHERE param IN (
		SELECT rwlimit_span_param FROM pem.chart
		WHERE rwlimit_span_param IS NOT NULL AND type ='L' AND unit = 'days'
	);

-- Remove existing function
DROP FUNCTION pem.generate_host_memory_chart_data(integer);
DROP FUNCTION pem.generate_conn_overview_chart_data(integer, text, integer, integer, text);
DROP FUNCTION pem.generate_replication_segment_lag_chart_data(integer, text, integer, integer);
DROP FUNCTION pem.generate_replication_page_lag_chart_data(integer, text, integer, integer);
DROP FUNCTION pem.generate_slony_event_lag_chart_data(integer, text, integer, integer, text);
DROP FUNCTION pem.generate_slony_time_lag_chart_data(integer, text, integer, integer, text);

CREATE OR REPLACE FUNCTION pem.generate_host_memory_chart_data(
	p_aid integer, p_stime timestamptz, p_etime timestamptz
)
RETURNS TABLE(
	o_idx int2, o_label text, o_aggtime timestamptz, o_aggval numeric
) AS $$
DECLARE
	v_span      interval;
	v_freq      interval;
	v_maxpoints integer;
	v_curr      timestamptz;
	v_stime     timestamptz;
	v_etime     timestamptz;
	v_hbtime    timestamptz;
	v_t_start   timestamptz;
	v_cursor    refcursor;
	v_curr_rec  record;
	v_next_rec  record;
	v_new_rec   record;
	v_arr_um    numeric[];
	v_arr_fm    numeric[];
	v_um        numeric;
	v_fm        numeric;
BEGIN
	v_curr := now();
	SELECT max(last_heartbeat) INTO v_hbtime FROM pem.agent_heartbeat WHERE server_id = p_aid;
	IF p_stime IS NULL OR p_etime IS NULL OR p_stime >= p_etime THEN
		BEGIN
			EXECUTE 'SELECT (value||'' ''||unit)::interval FROM pem.config WHERE param = ''dash_os_memory_span'''
			INTO v_span;
		EXCEPTION
		WHEN invalid_datetime_format THEN
			v_span := '7 days'::interval;
		WHEN datetime_field_overflow THEN
			v_span := '7 days'::interval;
		END;
		v_stime := v_curr - v_span;
		v_etime := v_curr;

		IF v_hbtime IS NOT NULL THEN
			v_etime := v_hbtime;
		END IF;

	ELSE
		v_stime := p_stime;
		v_etime := p_etime;

		IF v_etime > v_hbtime THEN
			v_etime := v_hbtime;
		ELSIF v_etime > v_curr THEN
			v_etime := v_curr;
		END IF;

		IF v_stime >= v_etime THEN
			RETURN;
		END IF;
	END IF;

	SELECT max_points INTO v_maxpoints FROM pem.metrices_chart WHERE cid = 39;

	IF v_maxpoints IS NULL THEN
		v_maxpoints := 100;
	END IF;

	v_t_start := NULL;
	SELECT max(recorded_time) INTO v_t_start FROM pemhistory.memory_usage WHERE recorded_time < v_stime AND agent_id = p_aid;

	IF v_t_start IS NULL THEN
		SELECT min(recorded_time) INTO v_t_start FROM pemhistory.memory_usage WHERE recorded_time >= v_stime AND agent_id = p_aid;

		IF v_t_start IS NULL THEN
			v_t_start := v_stime;
		ELSE
			v_stime := v_t_start;
		END IF;
	END IF;

	v_span := ((v_etime - v_stime) / v_maxpoints)::interval;

	EXECUTE '
SELECT
	(COALESCE(pca.execution_frequency, p.default_execution_frequency, 10) || ''seconds'')::interval AS freq
FROM
	pem.probe p
	LEFT JOIN pem.probe_config_agent pca ON (p.id = pca.probe_id AND pca.agent_id = $1::integer)
WHERE
	p.id = (SELECT id FROM pem.probe WHERE internal_name = ''memory_usage'')'
	USING p_aid INTO v_freq;

	IF v_freq IS NULL THEN
		v_freq := '10 seconds'::interval;
	END IF;

	IF v_span < v_freq THEN
		v_span := v_freq;
	END IF;

	OPEN v_cursor FOR EXECUTE '
SELECT
	recorded_time rtime,
	(total_ram_memory_mb - free_ram_memory_mb)::numeric used_mem,
	free_ram_memory_mb::numeric free_mem
FROM
	pemhistory.memory_usage
WHERE
	agent_id = $1::integer AND
	recorded_time >= $2::timestamptz AND
	recorded_time <= $3::timestamptz
ORDER BY recorded_time' USING p_aid, v_t_start, v_etime;

	FETCH v_cursor INTO v_curr_rec;
	IF FOUND THEN
		FETCH v_cursor INTO v_next_rec;
		FOR v_new_rec IN
			EXECUTE 'SELECT ts AS rtime FROM generate_series($1::timestamptz, $2::timestamptz, $3::interval) ts'
			USING v_stime, v_etime, v_span
		LOOP
			v_um := v_curr_rec.used_mem;
			v_fm := v_curr_rec.free_mem;

			IF (v_curr_rec.rtime IS NOT NULL
				AND v_curr_rec.rtime <= v_new_rec.rtime
				AND v_next_rec IS NOT NULL
				AND v_new_rec.rtime >= v_next_rec.rtime) THEN
					v_arr_um := ARRAY[]::numeric[];
					v_arr_fm := ARRAY[]::numeric[];

					-- Find the next value for the time, which is closest to the
					-- next expected time
					WHILE v_next_rec IS NOT NULL AND
						v_new_rec.rtime >= v_next_rec.rtime
					LOOP
						v_arr_um := v_arr_um || v_next_rec.used_mem;
						v_arr_fm := v_arr_fm || v_next_rec.free_mem;

						v_curr_rec := v_next_rec;
						FETCH v_cursor INTO v_next_rec;
					END LOOP;

					o_aggtime := v_new_rec.rtime;
					EXECUTE 'SELECT COALESCE(max(d), 0), COALESCE(max(e), 0) FROM (SELECT unnest($1::numeric[]) d, unnest($2::numeric[]) e) a'
						INTO v_um, v_fm USING v_arr_um, v_arr_fm;

					o_idx := 1;
					o_label := 'Used Memory';
					o_aggval := v_um;
					RETURN NEXT;

					o_idx := 2;
					o_label := 'Free Memory';
					o_aggval := v_fm;
					RETURN NEXT;

					CONTINUE;
			END IF;
			IF v_curr_rec.rtime <= v_new_rec.rtime THEN
				o_aggtime := v_new_rec.rtime;

				o_idx := 1;
				o_label := 'Used Memory';
				o_aggval := v_um;
				RETURN NEXT;

				o_idx := 2;
				o_label := 'Free Memory';
				o_aggval := v_fm;
				RETURN NEXT;
			END IF;
		END LOOP;
	END IF;

	CLOSE v_cursor;
END
$$ LANGUAGE 'plpgsql';

CREATE OR REPLACE FUNCTION pem.generate_conn_overview_chart_data(
	p_cid integer, p_sid integer, p_database text, p_stime timestamptz, p_etime timestamptz
) RETURNS TABLE(
	o_idx int2, o_label text, o_aggtime timestamptz, o_aggval numeric
) AS $$
DECLARE
	v_span      interval;
	v_freq      interval;
	v_maxpoints integer;
	v_curr      timestamptz;
	v_stime     timestamptz;
	v_etime     timestamptz;
	v_hbtime    timestamptz;
	v_t_start   timestamptz;
	v_cursor    refcursor;
	v_curr_rec  record;
	v_next_rec  record;
	v_new_rec   record;
	v_arr_ic    numeric[];
	v_arr_ac    numeric[];
	v_arr_dbs   text[];
	v_ic        numeric;
	v_ac        numeric;
BEGIN
	v_curr := now();
	SELECT max(last_heartbeat) INTO v_hbtime FROM pem.server_heartbeat WHERE server_id = p_sid;
	IF p_stime IS NULL OR p_etime IS NULL OR p_stime >= p_etime THEN
		BEGIN
            IF p_cid = 55 THEN
			    EXECUTE 'SELECT (value||'' ''||unit)::interval FROM pem.config WHERE param = ''dash_server_useract_span'''
			        INTO v_span;
            ELSE
			    EXECUTE 'SELECT (value||'' ''||unit)::interval FROM pem.config WHERE param = ''dash_db_useract_span'''
			        INTO v_span;
            END IF;
		EXCEPTION
		WHEN invalid_datetime_format THEN
			v_span := '7 days'::interval;
		WHEN datetime_field_overflow THEN
			v_span := '7 days'::interval;
		END;
		v_stime := v_curr - v_span;
		v_etime := v_curr;

		IF v_hbtime IS NOT NULL THEN
			v_etime := v_hbtime;
		END IF;

	ELSE
		v_stime := p_stime;
		v_etime := p_etime;

		IF v_etime > v_hbtime THEN
			v_etime := v_hbtime;
		ELSIF v_etime > v_curr THEN
			v_etime := v_curr;
		END IF;

		IF v_stime >= v_etime THEN
			RETURN;
		END IF;
	END IF;

	SELECT max_points INTO v_maxpoints FROM pem.metrices_chart WHERE cid = p_cid;

	IF v_maxpoints IS NULL THEN
		v_maxpoints := 100;
	END IF;

	v_t_start := NULL;
	IF p_database IS NULL THEN
		SELECT max(recorded_time) INTO v_t_start FROM pemhistory.database_statistics WHERE recorded_time < v_stime AND server_id = p_sid;

		IF v_t_start IS NULL THEN
			SELECT min(recorded_time) INTO v_t_start FROM pemhistory.database_statistics WHERE recorded_time >= v_stime AND server_id = p_sid;

			IF v_t_start IS NULL THEN
				v_t_start := v_stime;
			ELSE
				v_stime := v_t_start;
			END IF;
		END IF;
	ELSE
		SELECT max(recorded_time) INTO v_t_start FROM pemhistory.database_statistics WHERE recorded_time < v_stime AND server_id = p_sid AND database_name = p_database;

		IF v_t_start IS NULL THEN
			SELECT min(recorded_time) INTO v_t_start FROM pemhistory.database_statistics WHERE recorded_time >= v_stime AND server_id = p_sid AND database_name = p_database;

			IF v_t_start IS NULL THEN
				v_t_start := v_stime;
			ELSE
				v_stime := v_t_start;
			END IF;
		END IF;
	END IF;

	v_span := ((v_etime - v_stime) / v_maxpoints)::interval;

	EXECUTE '
SELECT
	(COALESCE(pcs.execution_frequency, p.default_execution_frequency, 10) || ''seconds'')::interval AS freq
FROM
	pem.probe p
	LEFT JOIN pem.probe_config_server pcs ON (p.id = pcs.probe_id AND pcs.server_id = $1::integer)
WHERE
	p.id = (SELECT id FROM pem.probe WHERE internal_name = ''database_statistics'')'
	USING p_sid INTO v_freq;

	IF v_freq IS NULL THEN
		v_freq := '10 seconds'::interval;
	END IF;

	IF v_span < v_freq THEN
		v_span := v_freq;
	END IF;

	IF p_database IS NULL THEN
		OPEN v_cursor FOR EXECUTE '
SELECT
	recorded_time rtime,
	(numbackends - idle_backends)::numeric active_conn,
	idle_backends::numeric idle_conn,
	database_name db
FROM
	pemhistory.database_statistics
WHERE
	server_id = $1::integer AND
	recorded_time >= $2::timestamptz AND
	recorded_time <= $3::timestamptz
ORDER BY recorded_time'
		USING p_sid, v_t_start, v_etime;
	ELSE
		OPEN v_cursor FOR EXECUTE '
SELECT
	recorded_time rtime,
	(numbackends - idle_backends)::numeric active_conn,
	idle_backends::numeric idle_conn,
	database_name db
FROM
	pemhistory.database_statistics
WHERE
	server_id = $1::integer AND
	database_name = $2::text AND
	recorded_time >= $2::timestamptz AND
	recorded_time <= $3::timestamptz
ORDER BY recorded_time'
		USING p_sid, p_database, v_t_start, v_etime;
	END IF;

	FETCH v_cursor INTO v_curr_rec;
	IF FOUND THEN
		FETCH v_cursor INTO v_next_rec;
		FOR v_new_rec IN
			EXECUTE 'SELECT ts AS rtime FROM generate_series($1::timestamptz, $2::timestamptz, $3::interval) ts'
			USING v_stime, v_etime, v_span
		LOOP
			v_ac := v_curr_rec.active_conn;
			v_ic := v_curr_rec.idle_conn;

			IF (v_curr_rec.rtime IS NOT NULL
				AND v_curr_rec.rtime <= v_new_rec.rtime
				AND v_next_rec IS NOT NULL
				AND v_new_rec.rtime >= v_next_rec.rtime) THEN
					v_arr_ac := ARRAY[]::numeric[];
					v_arr_ic := ARRAY[]::numeric[];
					v_arr_dbs := ARRAY[]::text[];
					v_ac := 0;
					v_ic := 0;

					-- Find the next value for the time, which is closest to the
					-- next expected time
					WHILE v_next_rec IS NOT NULL AND
						v_new_rec.rtime >= v_next_rec.rtime
					LOOP
						IF p_database IS NOT NULL THEN
							v_arr_ac := v_arr_ac || v_next_rec.active_conn;
							v_arr_ic := v_arr_ic || v_next_rec.idle_conn;
						ELSIF ARRAY[v_next_rec.db] <@ v_arr_dbs THEN
							v_ac := v_ac + v_next_rec.active_conn;
							v_ic := v_ic + v_next_rec.idle_conn;
						ELSE
							v_arr_dbs := ARRAY[]::text[];
							v_arr_ac := v_arr_ac || v_ac;
							v_arr_ic := v_arr_ic || v_ic;
							v_ac := v_next_rec.active_conn;
							v_ic := v_next_rec.idle_conn;
						END IF;

						v_curr_rec := v_next_rec;
						FETCH v_cursor INTO v_next_rec;
					END LOOP;

					o_aggtime := v_new_rec.rtime;
					EXECUTE 'SELECT COALESCE(sum(d), 0), COALESCE(sum(e), 0) FROM (SELECT unnest($1::numeric[]) d, unnest($2::numeric[]) e) a'
						INTO v_ac, v_ic USING v_arr_ic, v_arr_ac;

					o_idx := 1;
					o_label := 'Active Connections';
					o_aggval := v_ac;
					RETURN NEXT;

					o_idx := 2;
					o_label := 'Idle Connections';
					o_aggval := v_ic;
					RETURN NEXT;

					CONTINUE;
			END IF;
			IF v_curr_rec.rtime <= v_new_rec.rtime THEN
				o_aggtime := v_new_rec.rtime;

				o_idx := 1;
				o_label := 'Active Connections';
				o_aggval := v_ac;
				RETURN NEXT;

				o_idx := 2;
				o_label := 'Idle Connections';
				o_aggval := v_ic;
				RETURN NEXT;
			END IF;
		END LOOP;
	END IF;

	CLOSE v_cursor;
END
$$ LANGUAGE 'plpgsql';

CREATE OR REPLACE FUNCTION pem.generate_replication_segment_lag_chart_data (
	p_sid integer, p_stime timestamptz, p_etime timestamptz
) RETURNS TABLE(
	o_idx int2, o_label text, o_aggtime timestamptz, o_aggval bigint
) AS $$
DECLARE
	v_span      interval;
	v_freq      interval;
	v_maxpoints integer;
	v_curr      timestamptz;
	v_stime     timestamptz;
	v_etime     timestamptz;
	v_hbtime    timestamptz;
	v_t_start   timestamptz;
	v_cursor    refcursor;
	v_timecur   refcursor;
	v_curr_rec  record;
	v_next_rec  record;
	v_arr_val   numeric[];
	v_arr_lbl   text[];
	v_idx       integer;
	v_arr_present boolean[];
	v_val       bigint;
BEGIN
	v_curr := now();
	SELECT max(last_heartbeat) INTO v_hbtime FROM pem.server_heartbeat WHERE server_id = p_sid;
	IF p_stime IS NULL OR p_etime IS NULL OR p_stime >= p_etime THEN
		BEGIN
			EXECUTE 'SELECT (value||'' ''||unit)::interval FROM pem.config WHERE param = ''dash_replication_segmentlag_span'''
			INTO v_span;
		EXCEPTION
		WHEN invalid_datetime_format THEN
			v_span := '7 days'::interval;
		WHEN datetime_field_overflow THEN
			v_span := '7 days'::interval;
		END;
		v_stime := v_curr - v_span;
		v_etime := v_curr;

		IF v_hbtime IS NOT NULL THEN
			v_etime := v_hbtime;
		END IF;
	ELSE
		v_stime := p_stime;
		v_etime := p_etime;

		IF v_etime > v_hbtime THEN
			v_etime := v_hbtime;
		ELSIF v_etime > v_curr THEN
			v_etime := v_curr;
		END IF;

		IF v_stime >= v_etime THEN
			RETURN;
		END IF;
	END IF;

	SELECT max_points INTO v_maxpoints FROM pem.metrices_chart WHERE cid = 81;

	IF v_maxpoints IS NULL THEN
		v_maxpoints := 100;
	END IF;

	v_t_start := NULL;
	SELECT max(recorded_time) INTO v_t_start FROM pemhistory.streaming_replication WHERE recorded_time < v_stime AND server_id = p_sid;

	IF v_t_start IS NULL THEN
		SELECT min(recorded_time) INTO v_t_start FROM pemhistory.streaming_replication WHERE recorded_time >= v_stime AND server_id = p_sid;

		IF v_t_start IS NULL THEN
			v_t_start := v_stime;
		ELSE
			v_stime := v_t_start;
		END IF;
	END IF;

	v_span := ((v_etime - v_stime) / v_maxpoints)::interval;

	EXECUTE '
SELECT
	(COALESCE(pcs.execution_frequency, p.default_execution_frequency, 10) || ''seconds'')::interval AS freq
FROM
	pem.probe p
	LEFT JOIN pem.probe_config_server pcs ON (p.id = pcs.probe_id AND pcs.server_id = $1::integer)
WHERE
	p.id = (SELECT id FROM pem.probe WHERE internal_name = ''streaming_replication'')'
	USING p_sid INTO v_freq;

	IF v_freq IS NULL THEN
		v_freq := '10 seconds'::interval;
	END IF;

	IF v_span < v_freq THEN
		v_span := v_freq;
	END IF;

	OPEN v_cursor FOR EXECUTE '
SELECT  idx, to_timestamp(atime::numeric/1000000) rtime, lag, lbl
FROM (
	SELECT
		idx, (rtime * 1000000::bigint)::bigint atime, SUM(lag) lag, lbl
	FROM (
		SELECT
			dense_rank() OVER (ORDER BY sd.server_id, sd.client_addr) idx,
			(floor(EXTRACT(EPOCH FROM sh.recorded_time) / EXTRACT(EPOCH FROM $4::interval)) * EXTRACT(EPOCH FROM $4::interval)) rtime,
			COALESCE(sh.xlog_lag_in_segments, 0) lag,
			sh.client_addr lbl
		FROM
			pemhistory.streaming_replication sh
			JOIN pemdata.streaming_replication sd ON (sh.client_addr = sd.client_addr AND sh.server_id = sd.server_id)
		WHERE
			sh.server_id = $1::integer AND
			sh.recorded_time >= $2::timestamptz AND
			sh.recorded_time <= $3::timestamptz) a
		GROUP BY idx, atime, lbl
	) b
ORDER BY rtime, idx' USING p_sid, v_t_start, v_etime, v_span;

	FETCH v_cursor INTO v_curr_rec;
	IF FOUND THEN
		FETCH v_cursor INTO v_next_rec;
		v_hbtime := v_stime;
		v_arr_val := ARRAY[]::bigint[];
		v_arr_lbl := ARRAY[]::text[];
		v_arr_present := ARRAY[]::boolean[];
		v_arr_val[v_curr_rec.idx] := v_curr_rec.lag::bigint;
		<<data_loop>>
		LOOP
			o_aggtime := v_hbtime;
			IF v_hbtime > v_etime THEN
				EXIT data_loop;
			END IF;
			IF array_length(v_arr_present, 1) > 0 THEN
				FOR v_idx IN array_lower(v_arr_present, 1)..array_upper(v_arr_present, 1)
				LOOP
					IF v_arr_present[v_idx] IS NOT NULL THEN
						v_arr_present[v_idx] := false;
					END IF;
				END LOOP;
			END IF;
			WHILE v_next_rec IS NOT NULL AND
				v_next_rec.rtime < v_hbtime
			LOOP
				v_arr_val[v_curr_rec.idx] := v_curr_rec.lag::bigint;
				v_arr_lbl[v_curr_rec.idx] := v_curr_rec.lbl;
				v_curr_rec := v_next_rec;
				FETCH v_cursor INTO v_next_rec;
			END LOOP;

			IF v_curr_rec.rtime <= v_hbtime THEN
				<<inner_loop>>
				WHILE v_curr_rec.rtime <= v_hbtime
				LOOP
					IF v_arr_present[v_curr_rec.idx] IS NULL OR v_arr_present[v_curr_rec.idx] = false THEN
						o_idx := v_curr_rec.idx;
						o_label := v_curr_rec.lbl;
						o_aggval := v_curr_rec.lag::bigint;
						v_arr_present[o_idx] := true;

						RETURN NEXT;
					END IF;

					v_arr_val[v_curr_rec.idx] := v_curr_rec.lag::bigint;
					v_arr_lbl[v_curr_rec.idx] := v_curr_rec.lbl;
					IF v_next_rec IS NULL THEN
						EXIT inner_loop;
					END IF;
					v_curr_rec := v_next_rec;
					FETCH v_cursor INTO v_next_rec;
				END LOOP;
			END IF;
			IF array_length(v_arr_present, 1) > 0 THEN
				FOR v_idx IN array_lower(v_arr_lbl, 1)..array_upper(v_arr_lbl, 1)
				LOOP
					IF v_arr_present[v_idx] IS NULL OR v_arr_present[v_idx] = false THEN
						o_idx := v_idx;
						o_label := v_arr_lbl[v_idx];
						o_aggval := v_arr_val[v_idx];
						v_arr_present[o_idx] := true;

						RETURN NEXT;
					END IF;
				END LOOP;
			END IF;
			v_hbtime := v_hbtime + v_span;
		END LOOP;
	END IF;

	CLOSE v_cursor;

END
$$ LANGUAGE 'plpgsql';

CREATE OR REPLACE FUNCTION pem.generate_replication_page_lag_chart_data (
	p_sid integer, p_stime timestamptz, p_etime timestamptz
) RETURNS TABLE(
	o_idx int2, o_label text, o_aggtime timestamptz, o_aggval bigint
) AS $$
DECLARE
	v_span      interval;
	v_freq      interval;
	v_maxpoints integer;
	v_curr      timestamptz;
	v_stime     timestamptz;
	v_etime     timestamptz;
	v_hbtime    timestamptz;
	v_t_start   timestamptz;
	v_cursor    refcursor;
	v_timecur   refcursor;
	v_curr_rec  record;
	v_next_rec  record;
	v_arr_val   numeric[];
	v_arr_lbl   text[];
	v_idx       integer;
	v_arr_present boolean[];
	v_val       bigint;
BEGIN
	v_curr := now();
	SELECT max(last_heartbeat) INTO v_hbtime FROM pem.server_heartbeat WHERE server_id = p_sid;
	IF p_stime IS NULL OR p_etime IS NULL OR p_stime >= p_etime THEN
		BEGIN
			EXECUTE 'SELECT (value||'' ''||unit)::interval FROM pem.config WHERE param = ''dash_replication_pagelag_span'''
			INTO v_span;
		EXCEPTION
		WHEN invalid_datetime_format THEN
			v_span := '7 days'::interval;
		WHEN datetime_field_overflow THEN
			v_span := '7 days'::interval;
		END;
		v_stime := v_curr - v_span;
		v_etime := v_curr;

		IF v_hbtime IS NOT NULL THEN
			v_etime := v_hbtime;
		END IF;
	ELSE
		v_stime := p_stime;
		v_etime := p_etime;

		IF v_etime > v_hbtime THEN
			v_etime := v_hbtime;
		ELSIF v_etime > v_curr THEN
			v_etime := v_curr;
		END IF;

		IF v_stime >= v_etime THEN
			RETURN;
		END IF;
	END IF;

	SELECT max_points INTO v_maxpoints FROM pem.metrices_chart WHERE cid = 81;

	IF v_maxpoints IS NULL THEN
		v_maxpoints := 100;
	END IF;

	v_t_start := NULL;
	SELECT max(recorded_time) INTO v_t_start FROM pemhistory.streaming_replication WHERE recorded_time < v_stime AND server_id = p_sid;

	IF v_t_start IS NULL THEN
		SELECT min(recorded_time) INTO v_t_start FROM pemhistory.streaming_replication WHERE recorded_time >= v_stime AND server_id = p_sid;

		IF v_t_start IS NULL THEN
			v_t_start := v_stime;
		ELSE
			v_stime := v_t_start;
		END IF;
	END IF;

	v_span := ((v_etime - v_stime) / v_maxpoints)::interval;

	EXECUTE '
SELECT
	(COALESCE(pcs.execution_frequency, p.default_execution_frequency, 10) || ''seconds'')::interval AS freq
FROM
	pem.probe p
	LEFT JOIN pem.probe_config_server pcs ON (p.id = pcs.probe_id AND pcs.server_id = $1::integer)
WHERE
	p.id = (SELECT id FROM pem.probe WHERE internal_name = ''streaming_replication'')'
	USING p_sid INTO v_freq;

	IF v_freq IS NULL THEN
		v_freq := '10 seconds'::interval;
	END IF;

	IF v_span < v_freq THEN
		v_span := v_freq;
	END IF;

	OPEN v_cursor FOR EXECUTE '
SELECT  idx, to_timestamp(atime::numeric/1000000) rtime, lag, lbl
FROM (
	SELECT
		idx, (rtime * 1000000::bigint)::bigint atime, SUM(lag) lag, lbl
	FROM (
		SELECT
			dense_rank() OVER (ORDER BY sd.server_id, sd.client_addr) idx,
			(floor(EXTRACT(EPOCH FROM sh.recorded_time) / EXTRACT(EPOCH FROM $4::interval)) * EXTRACT(EPOCH FROM $4::interval)) rtime,
			COALESCE(sh.xlog_lag_in_pages, 0) lag,
			sh.client_addr lbl
		FROM
			pemhistory.streaming_replication sh
			JOIN pemdata.streaming_replication sd ON (sh.client_addr = sd.client_addr AND sh.server_id = sd.server_id)
		WHERE
			sh.server_id = $1::integer AND
			sh.recorded_time >= $2::timestamptz AND
			sh.recorded_time <= $3::timestamptz) a
		GROUP BY idx, atime, lbl
	) b
ORDER BY rtime, idx' USING p_sid, v_t_start, v_etime, v_span;

	FETCH v_cursor INTO v_curr_rec;
	IF FOUND THEN
		FETCH v_cursor INTO v_next_rec;
		v_hbtime := v_stime;
		v_arr_val := ARRAY[]::bigint[];
		v_arr_lbl := ARRAY[]::text[];
		v_arr_present := ARRAY[]::boolean[];
		v_arr_val[v_curr_rec.idx] := v_curr_rec.lag::bigint;
		<<data_loop>>
		LOOP
			o_aggtime := v_hbtime;
			IF v_hbtime > v_etime THEN
				EXIT data_loop;
			END IF;
			IF array_length(v_arr_present, 1) > 0 THEN
				FOR v_idx IN array_lower(v_arr_present, 1)..array_upper(v_arr_present, 1)
				LOOP
					IF v_arr_present[v_idx] IS NOT NULL THEN
						v_arr_present[v_idx] := false;
					END IF;
				END LOOP;
			END IF;
			WHILE v_next_rec IS NOT NULL AND
				v_next_rec.rtime < v_hbtime
			LOOP
				v_arr_val[v_curr_rec.idx] := v_curr_rec.lag::bigint;
				v_arr_lbl[v_curr_rec.idx] := v_curr_rec.lbl;
				v_curr_rec := v_next_rec;
				FETCH v_cursor INTO v_next_rec;
			END LOOP;

			IF v_curr_rec.rtime <= v_hbtime THEN
				<<inner_loop>>
				WHILE v_curr_rec.rtime <= v_hbtime
				LOOP
					IF v_arr_present[v_curr_rec.idx] IS NULL OR v_arr_present[v_curr_rec.idx] = false THEN
						o_idx := v_curr_rec.idx;
						o_label := v_curr_rec.lbl;
						o_aggval := v_curr_rec.lag::bigint;
						v_arr_present[o_idx] := true;

						RETURN NEXT;
					END IF;

					v_arr_val[v_curr_rec.idx] := v_curr_rec.lag::bigint;
					v_arr_lbl[v_curr_rec.idx] := v_curr_rec.lbl;
					IF v_next_rec IS NULL THEN
						EXIT inner_loop;
					END IF;
					v_curr_rec := v_next_rec;
					FETCH v_cursor INTO v_next_rec;
				END LOOP;
			END IF;
			IF array_length(v_arr_present, 1) > 0 THEN
				FOR v_idx IN array_lower(v_arr_lbl, 1)..array_upper(v_arr_lbl, 1)
				LOOP
					IF v_arr_present[v_idx] IS NULL OR v_arr_present[v_idx] = false THEN
						o_idx := v_idx;
						o_label := v_arr_lbl[v_idx];
						o_aggval := v_arr_val[v_idx];
						v_arr_present[o_idx] := true;

						RETURN NEXT;
					END IF;
				END LOOP;
			END IF;
			v_hbtime := v_hbtime + v_span;
		END LOOP;
	END IF;

	CLOSE v_cursor;

END
$$ LANGUAGE 'plpgsql';

CREATE OR REPLACE FUNCTION pem.generate_slony_event_lag_chart_data(
	p_sid integer, p_database text, p_stime timestamptz, p_etime timestamptz
) RETURNS TABLE(
	o_idx int2, o_label text, o_aggtime timestamptz, o_aggval numeric
) AS $$
DECLARE
	v_span      interval;
	v_freq      interval;
	v_maxpoints integer;
	v_curr      timestamptz;
	v_stime     timestamptz;
	v_etime     timestamptz;
	v_hbtime    timestamptz;
	v_t_start   timestamptz;
	v_cursor    refcursor;
	v_timecur   refcursor;
	v_curr_rec  record;
	v_next_rec  record;
	v_arr_val   numeric[];
	v_arr_lbl   text[];
	v_idx       integer;
	v_arr_present boolean[];
	v_val       bigint;
BEGIN
	v_curr := now();
	SELECT max(last_heartbeat) INTO v_hbtime FROM pem.server_heartbeat WHERE server_id = p_sid;
	IF p_stime IS NULL OR p_etime IS NULL OR p_stime >= p_etime THEN
		BEGIN
			EXECUTE 'SELECT (value||'' ''||unit)::interval FROM pem.config WHERE param = ''dash_db_eventlag_span'''
			INTO v_span;
		EXCEPTION
		WHEN invalid_datetime_format THEN
			v_span := '7 days'::interval;
		WHEN datetime_field_overflow THEN
			v_span := '7 days'::interval;
		END;
		v_stime := v_curr - v_span;
		v_etime := v_curr;

		IF v_hbtime IS NOT NULL THEN
			v_etime := v_hbtime;
		END IF;
	ELSE
		v_stime := p_stime;
		v_etime := p_etime;

		IF v_etime > v_hbtime THEN
			v_etime := v_hbtime;
		ELSIF v_etime > v_curr THEN
			v_etime := v_curr;
		END IF;

		IF v_stime >= v_etime THEN
			RETURN;
		END IF;
	END IF;

	SELECT max_points INTO v_maxpoints FROM pem.metrices_chart WHERE cid = 81;

	IF v_maxpoints IS NULL THEN
		v_maxpoints := 100;
	END IF;

	v_t_start := NULL;
	SELECT max(recorded_time) INTO v_t_start FROM pemhistory.slony_replication WHERE recorded_time < v_stime AND server_id = p_sid AND database_name = p_database;

	IF v_t_start IS NULL THEN
		SELECT min(recorded_time) INTO v_t_start FROM pemhistory.slony_replication WHERE recorded_time >= v_stime AND server_id = p_sid AND database_name = p_database;

		IF v_t_start IS NULL THEN
			v_t_start := v_stime;
		ELSE
			v_stime := v_t_start;
		END IF;
	END IF;

	v_span := ((v_etime - v_stime) / v_maxpoints)::interval;
	EXECUTE '
SELECT
	(COALESCE(pc.execution_frequency, p.default_execution_frequency, 10) || ''seconds'')::interval AS freq
FROM
	pem.probe p
	LEFT JOIN pem.probe_config_database pc ON (p.id = pc.probe_id AND pc.server_id = $1::integer AND pc.database_name = $2::text)
WHERE
	p.id = (SELECT id FROM pem.probe WHERE internal_name = ''slony_replication'')'
	USING p_sid, p_database INTO v_freq;

	IF v_freq IS NULL THEN
		v_freq := '10 seconds'::interval;
	END IF;

	IF v_span < v_freq THEN
		v_span := v_freq;
	END IF;

	OPEN v_cursor FOR EXECUTE '
SELECT  idx, to_timestamp(atime::numeric/1000000) rtime, lag, lbl
FROM (
	SELECT
		idx, (rtime * 1000000::bigint)::bigint atime, SUM(lag) lag, lbl
	FROM (
		SELECT
			dense_rank() OVER (ORDER BY sd.server_id, sd.client_addr) idx,
			(floor(EXTRACT(EPOCH FROM sh.recorded_time) / EXTRACT(EPOCH FROM $4::interval)) * EXTRACT(EPOCH FROM $4::interval)) rtime,
			COALESCE(sh.lag_num_events, 0) lag,
			sd.cluster_name lbl
		FROM
			pemhistory.slony_replication sh
			JOIN pemdata.slony_replication sd ON (sh.client_addr = sd.client_addr AND sh.server_id = sd.server_id AND sd.database_name = sh.database_name AND sd.cluster_name = sh.cluster_name)
		WHERE
			sh.server_id = $1::integer AND
			sh.recorded_time >= $2::timestamptz AND
			sh.recorded_time <= $3::timestamptz) a
		GROUP BY idx, atime, lbl
	) b
ORDER BY rtime, idx' USING p_sid, v_t_start, v_etime, v_span;

	FETCH v_cursor INTO v_curr_rec;
	IF FOUND THEN
		FETCH v_cursor INTO v_next_rec;
		v_hbtime := v_stime;
		v_arr_val := ARRAY[]::bigint[];
		v_arr_lbl := ARRAY[]::text[];
		v_arr_present := ARRAY[]::boolean[];
		v_arr_val[v_curr_rec.idx] := v_curr_rec.lag::bigint;
		<<data_loop>>
		LOOP
			o_aggtime := v_hbtime;
			IF v_hbtime > v_etime THEN
				EXIT data_loop;
			END IF;
			IF array_length(v_arr_present, 1) > 0 THEN
				FOR v_idx IN array_lower(v_arr_present, 1)..array_upper(v_arr_present, 1)
				LOOP
					IF v_arr_present[v_idx] IS NOT NULL THEN
						v_arr_present[v_idx] := false;
					END IF;
				END LOOP;
			END IF;
			WHILE v_next_rec IS NOT NULL AND
				v_next_rec.rtime < v_hbtime
			LOOP
				v_arr_val[v_curr_rec.idx] := v_curr_rec.lag::bigint;
				v_arr_lbl[v_curr_rec.idx] := v_curr_rec.lbl;
				v_curr_rec := v_next_rec;
				FETCH v_cursor INTO v_next_rec;
			END LOOP;

			IF v_curr_rec.rtime <= v_hbtime THEN
				<<inner_loop>>
				WHILE v_curr_rec.rtime <= v_hbtime
				LOOP
					IF v_arr_present[v_curr_rec.idx] IS NULL OR v_arr_present[v_curr_rec.idx] = false THEN
						o_idx := v_curr_rec.idx;
						o_label := v_curr_rec.lbl;
						o_aggval := v_curr_rec.lag::bigint;
						v_arr_present[o_idx] := true;

						RETURN NEXT;
					END IF;

					v_arr_val[v_curr_rec.idx] := v_curr_rec.lag::bigint;
					v_arr_lbl[v_curr_rec.idx] := v_curr_rec.lbl;
					IF v_next_rec IS NULL THEN
						EXIT inner_loop;
					END IF;
					v_curr_rec := v_next_rec;
					FETCH v_cursor INTO v_next_rec;
				END LOOP;
			END IF;
			IF array_length(v_arr_present, 1) > 0 THEN
				FOR v_idx IN array_lower(v_arr_lbl, 1)..array_upper(v_arr_lbl, 1)
				LOOP
					IF v_arr_present[v_idx] IS NULL OR v_arr_present[v_idx] = false THEN
						o_idx := v_idx;
						o_label := v_arr_lbl[v_idx];
						o_aggval := v_arr_val[v_idx];
						v_arr_present[o_idx] := true;

						RETURN NEXT;
					END IF;
				END LOOP;
			END IF;
			v_hbtime := v_hbtime + v_span;
		END LOOP;
	END IF;

	CLOSE v_cursor;

END
$$ LANGUAGE 'plpgsql';

CREATE OR REPLACE FUNCTION pem.generate_slony_time_lag_chart_data(
	p_sid integer, p_database text, p_stime timestamptz, p_etime timestamptz
) RETURNS TABLE(
	o_idx int2, o_label text, o_aggtime timestamptz, o_aggval numeric
) AS $$
DECLARE
	v_span      interval;
	v_freq      interval;
	v_maxpoints integer;
	v_curr      timestamptz;
	v_stime     timestamptz;
	v_etime     timestamptz;
	v_hbtime    timestamptz;
	v_t_start   timestamptz;
	v_cursor    refcursor;
	v_timecur   refcursor;
	v_curr_rec  record;
	v_next_rec  record;
	v_arr_val   numeric[];
	v_arr_lbl   text[];
	v_idx       integer;
	v_arr_present boolean[];
	v_val       bigint;
BEGIN
	v_curr := now();
	SELECT max(last_heartbeat) INTO v_hbtime FROM pem.server_heartbeat WHERE server_id = p_sid;
	IF p_stime IS NULL OR p_etime IS NULL OR p_stime >= p_etime THEN
		BEGIN
			EXECUTE 'SELECT (value||'' ''||unit)::interval FROM pem.config WHERE param = ''dash_db_timelag_span'''
			INTO v_span;
		EXCEPTION
		WHEN invalid_datetime_format THEN
			v_span := '7 days'::interval;
		WHEN datetime_field_overflow THEN
			v_span := '7 days'::interval;
		END;
		v_stime := v_curr - v_span;
		v_etime := v_curr;

		IF v_hbtime IS NOT NULL THEN
			v_etime := v_hbtime;
		END IF;
	ELSE
		v_stime := p_stime;
		v_etime := p_etime;

		IF v_etime > v_hbtime THEN
			v_etime := v_hbtime;
		ELSIF v_etime > v_curr THEN
			v_etime := v_curr;
		END IF;

		IF v_stime >= v_etime THEN
			RETURN;
		END IF;
	END IF;

	SELECT max_points INTO v_maxpoints FROM pem.metrices_chart WHERE cid = 81;

	IF v_maxpoints IS NULL THEN
		v_maxpoints := 100;
	END IF;

	v_t_start := NULL;
	SELECT max(recorded_time) INTO v_t_start FROM pemhistory.slony_replication WHERE recorded_time < v_stime AND server_id = p_sid AND database_name = p_database;

	IF v_t_start IS NULL THEN
		SELECT min(recorded_time) INTO v_t_start FROM pemhistory.slony_replication WHERE recorded_time >= v_stime AND server_id = p_sid AND database_name = p_database;

		IF v_t_start IS NULL THEN
			v_t_start := v_stime;
		ELSE
			v_stime := v_t_start;
		END IF;
	END IF;

	v_span := ((v_etime - v_stime) / v_maxpoints)::interval;
	EXECUTE '
SELECT
	(COALESCE(pc.execution_frequency, p.default_execution_frequency, 10) || ''seconds'')::interval AS freq
FROM
	pem.probe p
	LEFT JOIN pem.probe_config_database pc ON (p.id = pc.probe_id AND pc.server_id = $1::integer AND pc.database_name = $2::text)
WHERE
	p.id = (SELECT id FROM pem.probe WHERE internal_name = ''slony_replication'')'
	USING p_sid, p_database INTO v_freq;

	IF v_freq IS NULL THEN
		v_freq := '10 seconds'::interval;
	END IF;

	IF v_span < v_freq THEN
		v_span := v_freq;
	END IF;

	OPEN v_cursor FOR EXECUTE '
SELECT  idx, to_timestamp(atime::numeric/1000000) rtime, lag, lbl
FROM (
	SELECT
		idx, (rtime * 1000000::bigint)::bigint atime, SUM(lag) lag, lbl
	FROM (
		SELECT
			dense_rank() OVER (ORDER BY sd.server_id, sd.client_addr) idx,
			(floor(EXTRACT(EPOCH FROM sh.recorded_time) / EXTRACT(EPOCH FROM $4::interval)) * EXTRACT(EPOCH FROM $4::interval)) rtime,
			COALESCE(sh.lag_time, 0) lag,
			sd.cluster_name lbl
		FROM
			pemhistory.slony_replication sh
			JOIN pemdata.slony_replication sd ON (sh.client_addr = sd.client_addr AND sh.server_id = sd.server_id AND sd.database_name = sh.database_name AND sd.cluster_name = sh.cluster_name)
		WHERE
			sh.server_id = $1::integer AND
			sh.recorded_time >= $2::timestamptz AND
			sh.recorded_time <= $3::timestamptz) a
		GROUP BY idx, atime, lbl
	) b
ORDER BY rtime, idx' USING p_sid, v_t_start, v_etime, v_span;

	FETCH v_cursor INTO v_curr_rec;
	IF FOUND THEN
		FETCH v_cursor INTO v_next_rec;
		v_hbtime := v_stime;
		v_arr_val := ARRAY[]::bigint[];
		v_arr_lbl := ARRAY[]::text[];
		v_arr_present := ARRAY[]::boolean[];
		v_arr_val[v_curr_rec.idx] := v_curr_rec.lag::bigint;
		<<data_loop>>
		LOOP
			o_aggtime := v_hbtime;
			IF v_hbtime > v_etime THEN
				EXIT data_loop;
			END IF;
			IF array_length(v_arr_present, 1) > 0 THEN
				FOR v_idx IN array_lower(v_arr_present, 1)..array_upper(v_arr_present, 1)
				LOOP
					IF v_arr_present[v_idx] IS NOT NULL THEN
						v_arr_present[v_idx] := false;
					END IF;
				END LOOP;
			END IF;
			WHILE v_next_rec IS NOT NULL AND
				v_next_rec.rtime < v_hbtime
			LOOP
				v_arr_val[v_curr_rec.idx] := v_curr_rec.lag::bigint;
				v_arr_lbl[v_curr_rec.idx] := v_curr_rec.lbl;
				v_curr_rec := v_next_rec;
				FETCH v_cursor INTO v_next_rec;
			END LOOP;

			IF v_curr_rec.rtime <= v_hbtime THEN
				<<inner_loop>>
				WHILE v_curr_rec.rtime <= v_hbtime
				LOOP
					IF v_arr_present[v_curr_rec.idx] IS NULL OR v_arr_present[v_curr_rec.idx] = false THEN
						o_idx := v_curr_rec.idx;
						o_label := v_curr_rec.lbl;
						o_aggval := v_curr_rec.lag::bigint;
						v_arr_present[o_idx] := true;

						RETURN NEXT;
					END IF;

					v_arr_val[v_curr_rec.idx] := v_curr_rec.lag::bigint;
					v_arr_lbl[v_curr_rec.idx] := v_curr_rec.lbl;
					IF v_next_rec IS NULL THEN
						EXIT inner_loop;
					END IF;
					v_curr_rec := v_next_rec;
					FETCH v_cursor INTO v_next_rec;
				END LOOP;
			END IF;
			IF array_length(v_arr_present, 1) > 0 THEN
				FOR v_idx IN array_lower(v_arr_lbl, 1)..array_upper(v_arr_lbl, 1)
				LOOP
					IF v_arr_present[v_idx] IS NULL OR v_arr_present[v_idx] = false THEN
						o_idx := v_idx;
						o_label := v_arr_lbl[v_idx];
						o_aggval := v_arr_val[v_idx];
						v_arr_present[o_idx] := true;

						RETURN NEXT;
					END IF;
				END LOOP;
			END IF;
			v_hbtime := v_hbtime + v_span;
		END LOOP;
	END IF;

	CLOSE v_cursor;
END
$$ LANGUAGE 'plpgsql';

CREATE OR REPLACE FUNCTION pem.generate_server_pages_written (
	p_sid integer, p_stime timestamptz, p_etime timestamptz
) RETURNS TABLE (
	o_idx int2, o_label text, o_aggtime timestamptz, o_aggval numeric
) AS $$
DECLARE
	v_span      interval;
	v_freq      interval;
	v_maxpoints integer;
	v_curr      timestamptz;
	v_stime     timestamptz;
	v_etime     timestamptz;
	v_hbtime    timestamptz;
	v_t_start   timestamptz;
	v_cursor    refcursor;
	v_curr_rec  record;
	v_next_rec  record;
	v_new_rec   record;
	v_arr_cp    numeric[];
	v_arr_bw    numeric[];
	v_arr_bb    numeric[];
	v_cp        numeric;
	v_bw        numeric;
	v_bb        numeric;
BEGIN
	v_curr := now();
	SELECT max(last_heartbeat) INTO v_hbtime FROM pem.server_heartbeat WHERE server_id = p_sid;

	IF p_stime IS NULL OR p_etime IS NULL OR p_stime >= p_etime THEN
		BEGIN
			EXECUTE 'SELECT (value||'' ''||unit)::interval FROM pem.config WHERE param = ''dash_server_buffers_written'''
			INTO v_span;
		EXCEPTION
		WHEN invalid_datetime_format THEN
			v_span := '7 days'::interval;
		WHEN datetime_field_overflow THEN
			v_span := '7 days'::interval;
		END;
		v_stime := v_curr - v_span;
		v_etime := v_curr;

		IF v_hbtime IS NOT NULL THEN
			v_etime := v_hbtime;
		END IF;

	ELSE
		v_stime := p_stime;
		v_etime := p_etime;

		IF v_etime > v_hbtime THEN
			v_etime := v_hbtime;
		ELSIF v_etime > v_curr THEN
			v_etime := v_curr;
		END IF;

		IF v_stime >= v_etime THEN
			RETURN;
		END IF;
	END IF;

	SELECT max_points INTO v_maxpoints FROM pem.metrices_chart WHERE cid = 87;

	IF v_maxpoints IS NULL THEN
		v_maxpoints := 100;
	END IF;

	v_span := ((v_etime - v_stime) / v_maxpoints)::interval;

	EXECUTE '
SELECT
	(COALESCE(psc.execution_frequency, p.default_execution_frequency, 10) || ''seconds'')::interval AS freq
FROM
	pem.probe p
	LEFT JOIN pem.probe_config_server psc ON (p.id = psc.probe_id AND psc.server_id = $1::integer)
WHERE
	p.id = (SELECT id FROM pem.probe WHERE internal_name = ''background_writer_statistics'')'
	USING p_sid INTO v_freq;

	IF v_freq IS NULL THEN
		v_freq := '10 seconds'::interval;
	END IF;

	IF v_span < v_freq THEN
		v_span := v_freq;
	END IF;

	v_t_start := NULL;
	SELECT max(recorded_time) INTO v_t_start FROM pemhistory.background_writer_statistics WHERE recorded_time < v_stime AND server_id = p_sid;

	IF v_t_start IS NULL THEN
		SELECT min(recorded_time) INTO v_t_start FROM pemhistory.background_writer_statistics WHERE recorded_time >= v_stime AND server_id = p_sid;
		IF v_t_start IS NULL THEN
			v_t_start := v_stime;
		ELSE
			v_stime := v_t_start;
		END IF;
	END IF;

	OPEN v_cursor FOR EXECUTE '
SELECT
	recorded_time rtime,
	(buffers_checkpoint::decimal / total ) * 100 buffers_checkpoint,
	(buffers_clean::decimal / total ) * 100 buffers_clean,
	(buffers_backend::decimal / total ) * 100 buffers_backend
FROM
	(WITH bgws AS
		(SELECT
			ROW_NUMBER() OVER (PARTITION BY server_id ORDER BY recorded_time) rownum,
			recorded_time,
			CASE WHEN buffers_checkpoint_pit = 0 AND buffers_clean_pit = 0 AND buffers_backend_pit = 0 THEN true ELSE false END possible_reset,
			buffers_checkpoint,
			buffers_clean,
			buffers_backend,
			buffers_alloc,
			(buffers_checkpoint + buffers_clean + buffers_backend) total
		FROM pemhistory.background_writer_statistics
		WHERE server_id = $1::integer)
	SELECT
		b1.recorded_time,
		CASE WHEN (b1.possible_reset AND b1.buffers_checkpoint != b2.buffers_checkpoint) OR b2.buffers_checkpoint IS NULL THEN
			b1.buffers_checkpoint
		ELSE (b1.buffers_checkpoint - b2.buffers_checkpoint)
		END buffers_checkpoint,
		CASE WHEN (b1.possible_reset AND b1.buffers_clean != b2.buffers_clean) OR b2.buffers_clean IS NULL THEN
			b1.buffers_clean
		ELSE (b1.buffers_clean - b2.buffers_clean)
		END buffers_clean,
		CASE WHEN (b1.possible_reset AND b1.buffers_backend != b2.buffers_backend) OR b2.buffers_backend IS NULL THEN
			b1.buffers_backend
		ELSE (b1.buffers_backend - b2.buffers_backend)
		END buffers_backend,
		CASE WHEN (b1.possible_reset AND b1.buffers_alloc != b2.buffers_alloc) OR b2.buffers_alloc IS NULL THEN b1.buffers_alloc ELSE (b1.buffers_alloc - b2.buffers_alloc) END buffers_alloc,
		CASE WHEN (b1.possible_reset AND b1.total != b2.total) OR b2.total IS NULL THEN
			b1.total
		ELSE (b1.total - b2.total)
		END total
	FROM bgws b1
	LEFT JOIN bgws b2 ON (b1.rownum = b2.rownum + 1)
	WHERE b2.rownum IS NOT NULL) bg
WHERE bg.recorded_time >= $2::timestamptz AND bg.recorded_time <= $3::timestamptz
ORDER BY recorded_time' USING p_sid, v_t_start, v_etime;

	FETCH v_cursor INTO v_curr_rec;
	IF FOUND THEN
		FETCH v_cursor INTO v_next_rec;
		FOR v_new_rec IN
			EXECUTE 'SELECT ts AS rtime FROM generate_series($1::timestamptz, $2::timestamptz, $3::interval) ts'
			USING v_stime, v_etime, v_span
		LOOP
			IF (v_curr_rec.rtime IS NOT NULL
				AND v_curr_rec.rtime <= v_new_rec.rtime
				AND v_next_rec IS NOT NULL
				AND v_new_rec.rtime >= v_next_rec.rtime) THEN
					v_arr_cp := ARRAY[]::numeric[];
					v_arr_bw := ARRAY[]::numeric[];
					v_arr_bb := ARRAY[]::numeric[];

					-- Find the next value for the time, which is closest to the
					-- next expected time
					WHILE v_next_rec IS NOT NULL AND
						v_new_rec.rtime >= v_next_rec.rtime
					LOOP
						v_arr_cp := v_arr_cp || v_next_rec.buffers_checkpoint;
						v_arr_bw := v_arr_bw || v_next_rec.buffers_clean;
						v_arr_bb := v_arr_bb || v_next_rec.buffers_backend;

						v_curr_rec := v_next_rec;
						FETCH v_cursor INTO v_next_rec;
					END LOOP;
					o_aggtime := v_new_rec.rtime;
					EXECUTE 'SELECT COALESCE(avg(d), 0), COALESCE(avg(e), 0), COALESCE(avg(f), 0) FROM (SELECT unnest($1::numeric[]) d, unnest($2::numeric[]) e, unnest($3::numeric[]) f) a'
						INTO v_cp, v_bw, v_bb USING v_arr_cp, v_arr_bw, v_arr_bb;

					o_idx := 1;
					o_label := 'Checkpoint Processes';
					o_aggval := v_cp;
					RETURN NEXT;

					o_idx := 2;
					o_label := 'Background Writer';
					o_aggval := v_bw;
					RETURN NEXT;

					o_idx := 3;
					o_label := 'By Backends';
					o_aggval := v_bb;
					RETURN NEXT;

					CONTINUE;
			END IF;
			IF v_curr_rec.rtime <= v_new_rec.rtime THEN
				o_aggtime := v_new_rec.rtime;
				o_aggval := 0;

				o_idx := 1;
				o_label := 'Checkpoint Processes';
				RETURN NEXT;

				o_idx := 2;
				o_label := 'Background Writer';
				RETURN NEXT;

				o_idx := 3;
				o_label := 'By Backends';
				RETURN NEXT;
			END IF;
		END LOOP;
	END IF;

	CLOSE v_cursor;

END
$$ LANGUAGE 'plpgsql';

UPDATE pem.probe_server_version SET probe_code = E'SELECT datname AS database_name, pid AS procpid, usename, client_addr, client_port, backend_start, xact_start, query_start, waiting AS is_waiting, state = ''idle'' AS is_idle, state = ''idle in transaction'' AS is_idle_in_transaction, query ilike $$VACUUM%$$ as is_vacuum, client_port IS NULL AND (query like $$autovacuum:%$$ OR query like $$VACUUM%$$) as is_autovacuum, now() AS capture_time FROM pg_catalog.pg_stat_activity'
WHERE probe_id = (SELECT id FROM pem.probe WHERE internal_name = 'session_info') AND server_version_id IN (10902, 10903, 10904, 20902, 20903, 20904);

COMMIT TRANSACTION;
