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
'SELECT 201407151::integer;'
  LANGUAGE 'sql' IMMUTABLE;

ALTER TABLE pem.data_chart ADD COLUMN orderdir character(1)[];
ALTER TABLE pem.chart_metric ADD COLUMN gorderdir character(1)[];

ALTER TABLE pem.chart_catagory RENAME TO chart_category;
ALTER SEQUENCE pem.chart_catagory_id_seq RENAME TO chart_category_id_seq;

-- RM #33313
UPDATE pem.chart_func SET func = E'SELECT o_idx, o_label, ''Date('' || (EXTRACT(EPOCH FROM o_aggtime) * 1000)::numeric(40, 0)::text || '')'', o_aggval FROM pem.generate_conn_overview_chart_data(11, $1::int4, $2::text, $3::timestamptz, $4::timestamptz) ORDER BY o_idx, o_aggtime' WHERE id = 11;
UPDATE pem.chart_func SET func = E'SELECT o_idx, o_label, ''Date('' || (EXTRACT(EPOCH FROM o_aggtime) * 1000)::numeric(40, 0)::text || '')'', o_aggval FROM pem.generate_conn_overview_chart_data(55, $1::int4, NULL::text, $2::timestamptz, $3::timestamptz) ORDER BY o_idx, o_aggtime' WHERE id = 55;

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
	SELECT max(last_heartbeat) INTO v_hbtime FROM pem.agent_heartbeat WHERE agent_id = p_aid;
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

-- RM #33366
UPDATE pem.chart_metric SET agg_func='{M}' WHERE mid = 1 AND cid = 80;
UPDATE pem.chart_metric SET agg_func='{M,M}' WHERE mid = 2 AND cid = 80;

CREATE OR REPLACE FUNCTION pem.generate_replication_segment_lag_chart_data (
	p_sid integer, p_stime timestamptz, p_etime timestamptz
) RETURNS TABLE(
	o_idx int2, o_label text, o_aggtime timestamptz, o_aggval bigint
) AS $$
DECLARE
	v_span      interval;
	v_freq      interval;
	v_maxpoints bigint;
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

	SELECT max_points::bigint INTO v_maxpoints FROM pem.metrices_chart WHERE cid = 81;

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
		SELECT floor(EXTRACT(EPOCH FROM (v_etime - v_stime)) / EXTRACT(EPOCH FROM v_span))::bigint INTO v_maxpoints;
		IF v_maxpoints < 1 THEN
			v_maxpoints := 1;
		END IF;
	ELSE
		v_maxpoints := v_maxpoints - 1;
	END IF;
	v_span := (v_etime - v_stime)::interval;

	RETURN QUERY EXECUTE '
WITH dtbl AS (
        SELECT
                floor(dt / (EXTRACT(EPOCH FROM $1::interval))) pr, floor(dt / (EXTRACT(EPOCH FROM $2::interval) / $3::bigint)) dr, idx,
                rt, val, lbl,
                dense_rank() OVER (PARTITION BY floor(dt / (EXTRACT(EPOCH FROM $2::interval) / $3::bigint)) ORDER BY floor(dt / (EXTRACT(EPOCH FROM $1::interval))) DESC) pidx,
                row_number() OVER (PARTITION BY idx ORDER BY rt) rn
        FROM (
                SELECT
                        pd.client_addr lbl, EXTRACT(EPOCH FROM (ph.recorded_time - $4::timestamptz)) dt,
                        ph.recorded_time rt, COALESCE(ph.xlog_lag_in_segments, 0) val, pd.idx idx
                FROM
                        pemhistory.streaming_replication ph
                        INNER JOIN (SELECT server_id, client_addr, (dense_rank() OVER (ORDER BY client_addr))::int2 idx FROM pemdata.streaming_replication WHERE server_id = $5::int ORDER BY client_addr LIMIT 32) pd ON (ph.server_id = pd.server_id AND ph.client_addr = pd.client_addr)
                WHERE ph.server_id = $5::int AND ph.recorded_time >= $6::timestamptz AND ph.recorded_time <= $7::timestamptz) tbl
        )
SELECT
        idx::int2 o_idx, lbl o_lbl, to_timestamp((dra * (EXTRACT(EPOCH FROM $2::interval) / $3::bigint)) + EXTRACT(EPOCH FROM $4::timestamptz)) o_aggtime, MAX(val) o_aggval
FROM
        (SELECT
                t1.idx idx, t1.lbl lbl,
                CASE WHEN t2.rt IS NULL THEN 1 ELSE (t2.dr - t1.dr) END pnt, t1.dr dr,
                CASE WHEN t2.rt IS NULL THEN 1 ELSE (t2.pr - t1.pr) END cnt, t1.pr pr,
                unnest(CASE
                        WHEN t2.dr - t1.dr > 1 THEN ARRAY(SELECT g FROM generate_series(t1.dr::bigint, (t2.dr - 1)::bigint, 1) g)
                        WHEN t2.rt IS NULL AND t1.dr < $3::bigint THEN ARRAY(SELECT g FROM generate_series(t1.dr::bigint, $3::bigint, 1) g)
                        ELSE ARRAY[t1.dr] END) dra,
                t1.rt rt, t1.val val, t1.pidx pidx, t1.rn rn
        FROM
                dtbl t1
                LEFT JOIN dtbl t2 ON (t1.rn = t2.rn - 1 AND t1.idx = t2.idx)) ltbl
WHERE dra >= 0
GROUP BY dra, idx, lbl
ORDER BY idx, dra' USING v_freq, v_span, v_maxpoints, v_stime, p_sid, v_t_start, v_etime;

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
	v_maxpoints bigint;
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

	SELECT max_points::bigint INTO v_maxpoints FROM pem.metrices_chart WHERE cid = 81;

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
		SELECT floor(EXTRACT(EPOCH FROM (v_etime - v_stime)) / EXTRACT(EPOCH FROM v_span))::bigint INTO v_maxpoints;
		IF v_maxpoints < 1 THEN
			v_maxpoints := 1;
		END IF;
	ELSE
		v_maxpoints := v_maxpoints - 1;
	END IF;
	v_span := (v_etime - v_stime)::interval;

	RETURN QUERY EXECUTE '
WITH dtbl AS (
        SELECT
                floor(dt / (EXTRACT(EPOCH FROM $1::interval))) pr, floor(dt / (EXTRACT(EPOCH FROM $2::interval) / $3::bigint)) dr, idx,
                rt, val, lbl,
                dense_rank() OVER (PARTITION BY floor(dt / (EXTRACT(EPOCH FROM $2::interval) / $3::bigint)) ORDER BY floor(dt / (EXTRACT(EPOCH FROM $1::interval))) DESC) pidx,
                row_number() OVER (PARTITION BY idx ORDER BY rt) rn
        FROM (
                SELECT
                        pd.client_addr lbl, EXTRACT(EPOCH FROM (ph.recorded_time - $4::timestamptz)) dt,
                        ph.recorded_time rt, COALESCE(ph.xlog_lag_in_pages, 0) val, pd.idx idx
                FROM
                        pemhistory.streaming_replication ph
                        INNER JOIN (SELECT server_id, client_addr, (dense_rank() OVER (ORDER BY client_addr))::int2 idx FROM pemdata.streaming_replication WHERE server_id = $5::int ORDER BY client_addr LIMIT 32) pd ON (ph.server_id = pd.server_id AND ph.client_addr = pd.client_addr)
                WHERE ph.server_id = $5::int AND ph.recorded_time >= $6::timestamptz AND ph.recorded_time <= $7::timestamptz) tbl
        )
SELECT
        idx::int2 o_idx, lbl o_lbl, to_timestamp((dra * (EXTRACT(EPOCH FROM $2::interval) / $3::bigint)) + EXTRACT(EPOCH FROM $4::timestamptz)) o_aggtime, MAX(val) o_aggval
FROM
        (SELECT
                t1.idx idx, t1.lbl lbl,
                CASE WHEN t2.rt IS NULL THEN 1 ELSE (t2.dr - t1.dr) END pnt, t1.dr dr,
                CASE WHEN t2.rt IS NULL THEN 1 ELSE (t2.pr - t1.pr) END cnt, t1.pr pr,
                unnest(CASE
                        WHEN t2.dr - t1.dr > 1 THEN ARRAY(SELECT g FROM generate_series(t1.dr::bigint, (t2.dr - 1)::bigint, 1) g)
                        WHEN t2.rt IS NULL AND t1.dr < $3::bigint THEN ARRAY(SELECT g FROM generate_series(t1.dr::bigint, $3::bigint, 1) g)
                        ELSE ARRAY[t1.dr] END) dra,
                t1.rt rt, t1.val val, t1.pidx pidx, t1.rn rn
        FROM
                dtbl t1
                LEFT JOIN dtbl t2 ON (t1.rn = t2.rn - 1 AND t1.idx = t2.idx)) ltbl
WHERE dra >= 0
GROUP BY dra, idx, lbl
ORDER BY idx, dra' USING v_freq, v_span, v_maxpoints, v_stime, p_sid, v_t_start, v_etime;

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
	v_maxpoints bigint;
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

	SELECT max_points::bigint INTO v_maxpoints FROM pem.metrices_chart WHERE cid = 81;

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
		SELECT floor(EXTRACT(EPOCH FROM (v_etime - v_stime)) / EXTRACT(EPOCH FROM v_span))::bigint INTO v_maxpoints;
		IF v_maxpoints < 1 THEN
			v_maxpoints := 1;
		END IF;
	ELSE
		v_maxpoints := v_maxpoints - 1;
	END IF;
	v_span := (v_etime - v_stime)::interval;

	RETURN QUERY EXECUTE '
WITH dtbl AS (
        SELECT
                floor(dt / (EXTRACT(EPOCH FROM $1::interval))) pr, floor(dt / (EXTRACT(EPOCH FROM $2::interval) / $3::bigint)) dr, idx,
                rt, val, lbl,
                dense_rank() OVER (PARTITION BY floor(dt / (EXTRACT(EPOCH FROM $2::interval) / $3::bigint)) ORDER BY floor(dt / (EXTRACT(EPOCH FROM $1::interval))) DESC) pidx,
                row_number() OVER (PARTITION BY idx ORDER BY rt) rn
        FROM (
                SELECT
                        pd.cluster_name lbl, EXTRACT(EPOCH FROM (ph.recorded_time - $4::timestamptz)) dt,
                        ph.recorded_time rt, COALESCE(ph.lag_num_events, 0) val, pd.idx idx
                FROM
                        pemhistory.slony_replication ph
                        INNER JOIN (SELECT server_id, cluster_name, database_name, (dense_rank() OVER (ORDER BY cluster_name))::int2 idx FROM (SELECT server_id, cluster_name, database_name FROM pemdata.slony_replication WHERE server_id = $5::int AND database_name = $6::text ORDER BY cluster_name LIMIT 32) p) pd ON (ph.server_id = pd.server_id AND ph.database_name = pd.database_name AND ph.cluster_name = pd.cluster_name)
                WHERE ph.server_id = $5::int AND ph.recorded_time >= $7::timestamptz AND ph.recorded_time <= $8::timestamptz) tbl
        )
SELECT
        idx::int2 o_idx, lbl o_lbl, to_timestamp((dra * (EXTRACT(EPOCH FROM $2::interval) / $3::bigint)) + EXTRACT(EPOCH FROM $4::timestamptz)) o_aggtime, MAX(val) o_aggval
FROM
        (SELECT
                t1.idx idx, t1.lbl lbl,
                CASE WHEN t2.rt IS NULL THEN 1 ELSE (t2.dr - t1.dr) END pnt, t1.dr dr,
                CASE WHEN t2.rt IS NULL THEN 1 ELSE (t2.pr - t1.pr) END cnt, t1.pr pr,
                unnest(CASE
                        WHEN t2.dr - t1.dr > 1 THEN ARRAY(SELECT g FROM generate_series(t1.dr::bigint, (t2.dr - 1)::bigint, 1) g)
                        WHEN t2.rt IS NULL AND t1.dr < $3::bigint THEN ARRAY(SELECT g FROM generate_series(t1.dr::bigint, $3::bigint, 1) g)
                        ELSE ARRAY[t1.dr] END) dra,
                t1.rt rt, t1.val val, t1.pidx pidx, t1.rn rn
        FROM
                dtbl t1
                LEFT JOIN dtbl t2 ON (t1.rn = t2.rn - 1 AND t1.idx = t2.idx)) ltbl
WHERE dra >= 0
GROUP BY dra, idx, lbl
ORDER BY idx, dra' USING v_freq, v_span, v_maxpoints, v_stime, p_sid, p_database, v_t_start, v_etime;

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
	v_maxpoints bigint;
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

	SELECT max_points::bigint INTO v_maxpoints FROM pem.metrices_chart WHERE cid = 81;

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
		SELECT floor(EXTRACT(EPOCH FROM (v_etime - v_stime)) / EXTRACT(EPOCH FROM v_span))::bigint INTO v_maxpoints;
		IF v_maxpoints < 1 THEN
			v_maxpoints := 1;
		END IF;
	ELSE
		v_maxpoints := v_maxpoints - 1;
	END IF;
	v_span := (v_etime - v_stime)::interval;

	RETURN QUERY EXECUTE '
WITH dtbl AS (
        SELECT
                floor(dt / (EXTRACT(EPOCH FROM $1::interval))) pr, floor(dt / (EXTRACT(EPOCH FROM $2::interval) / $3::bigint)) dr, idx,
                rt, val, lbl,
                dense_rank() OVER (PARTITION BY floor(dt / (EXTRACT(EPOCH FROM $2::interval) / $3::bigint)) ORDER BY floor(dt / (EXTRACT(EPOCH FROM $1::interval))) DESC) pidx,
                row_number() OVER (PARTITION BY idx ORDER BY rt) rn
        FROM (
                SELECT
                        pd.cluster_name lbl, EXTRACT(EPOCH FROM (ph.recorded_time - $4::timestamptz)) dt,
                        ph.recorded_time rt, COALESCE(ph.lag_time, 0) val, pd.idx idx
                FROM
                        pemhistory.slony_replication ph
                        INNER JOIN (SELECT server_id, cluster_name, database_name, (dense_rank() OVER (ORDER BY cluster_name))::int2 idx FROM (SELECT server_id, cluster_name, database_name FROM pemdata.slony_replication WHERE server_id = $5::int AND database_name = $6::text ORDER BY cluster_name LIMIT 32) p) pd ON (ph.server_id = pd.server_id AND ph.database_name = pd.database_name AND ph.cluster_name = pd.cluster_name)
                WHERE ph.server_id = $5::int AND ph.recorded_time >= $7::timestamptz AND ph.recorded_time <= $8::timestamptz) tbl
        )
SELECT
        idx::int2 o_idx, lbl o_lbl, to_timestamp((dra * (EXTRACT(EPOCH FROM $2::interval) / $3::bigint)) + EXTRACT(EPOCH FROM $4::timestamptz)) o_aggtime, MAX(val) o_aggval
FROM
        (SELECT
                t1.idx idx, t1.lbl lbl,
                CASE WHEN t2.rt IS NULL THEN 1 ELSE (t2.dr - t1.dr) END pnt, t1.dr dr,
                CASE WHEN t2.rt IS NULL THEN 1 ELSE (t2.pr - t1.pr) END cnt, t1.pr pr,
                unnest(CASE
                        WHEN t2.dr - t1.dr > 1 THEN ARRAY(SELECT g FROM generate_series(t1.dr::bigint, (t2.dr - 1)::bigint, 1) g)
                        WHEN t2.rt IS NULL AND t1.dr < $3::bigint THEN ARRAY(SELECT g FROM generate_series(t1.dr::bigint, $3::bigint, 1) g)
                        ELSE ARRAY[t1.dr] END) dra,
                t1.rt rt, t1.val val, t1.pidx pidx, t1.rn rn
        FROM
                dtbl t1
                LEFT JOIN dtbl t2 ON (t1.rn = t2.rn - 1 AND t1.idx = t2.idx)) ltbl
WHERE dra >= 0
GROUP BY dra, idx, lbl
ORDER BY idx, dra' USING v_freq, v_span, v_maxpoints, v_stime, p_sid, p_database, v_t_start, v_etime;

END
$$ LANGUAGE 'plpgsql';

COMMIT TRANSACTION;
