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
'SELECT 201509011::integer;'
  LANGUAGE 'sql' IMMUTABLE;
COMMENT ON FUNCTION pem.schema_version() IS 'Returns the version number of the PEM schema';

DROP FUNCTION IF EXISTS pem.generate_conn_overview_chart_data(integer, integer, text, timestamptz, timestamptz);

CREATE OR REPLACE FUNCTION pem.generate_conn_overview_chart_data(
	p_cid integer, p_did integer, p_sid integer, p_database text, p_stime timestamptz, p_etime timestamptz
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
	v_ic        numeric;
	v_ac        numeric;
BEGIN
	v_curr := now();
	SELECT max(last_heartbeat) INTO v_hbtime FROM pem.server_heartbeat WHERE server_id = p_sid;

	EXECUTE '
SELECT
    span, points
FROM
    ((SELECT
        -1::integer as lvl,
        (SELECT (value||'' ''||unit)::interval FROM pem.config WHERE CASE WHEN $1::integer = 55 THEN param = ''dash_server_useract_span'' ELSE param = ''dash_db_useract_span'' END) as span,
        (SELECT max_points FROM pem.metrices_chart WHERE cid = $1::integer) as points
    )
    UNION ALL
    (SELECT
        CASE
        WHEN cfg.did = -1 THEN
            CASE
            WHEN cfg.objid IS NULL THEN 1::integer
            WHEN $3::integer IS NOT NULL AND cfg.objid = $3::integer AND
                cfg.database IS NULL
                THEN 2::integer
            WHEN $3::integer IS NOT NULL AND cfg.objid = $3::integer AND
                cfg.database IS NOT NULL AND cfg.database = $4::text
                THEN 3::integer
            END
        ELSE
            CASE
            WHEN cfg.objid IS NULL THEN 6::integer
            WHEN $3::integer IS NOT NULL AND cfg.objid = $3::integer AND
                cfg.database IS NULL
                THEN 7::integer
            WHEN $3::integer IS NOT NULL AND cfg.objid = $3::integer AND
                cfg.database IS NOT NULL AND cfg.database = $4::text
                THEN 8::integer
            END
        END AS lvl,
        (cfg.span * ''1 hours''::interval) as span, cfg.points as points
    FROM
        pem.chart_config cfg
    WHERE
        cfg.cid = $1::integer AND (
            (cfg.did = -1 AND cfg.level <= COALESCE(
                    (SELECT level FROM pem.dashboard WHERE did=$2::integer),
                    CASE WHEN $1::integer = 55 THEN 200 ELSE 300 END
                )) OR
            ($2::integer IS NOT NULL AND cfg.did = $2::integer AND cfg.level =
                COALESCE(
                    (SELECT level FROM pem.dashboard WHERE did=$2::integer),
                    CASE WHEN $1::integer = 55 THEN 200 ELSE 300 END
                )
            )
        ) AND cfg.uid = (
            SELECT u.usesysid FROM pg_catalog.pg_user u
                WHERE u.usename = current_user
        )
    )) config
ORDER BY lvl DESC
LIMIT 1' USING p_cid, p_did, p_sid, p_database INTO v_span, v_maxpoints;

    IF v_span IS NULL THEN
        v_span = '7 days'::interval;
    END IF;

	IF p_stime IS NULL OR p_etime IS NULL OR p_stime >= p_etime THEN
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

	OPEN v_cursor FOR EXECUTE '
SELECT
    ((span * $5::interval) + $3::timestamptz) rtime, SUM(active_conn) active_conn, SUM(idle_backends) idle_conn
FROM (
    SELECT
        database_name,
        floor(
            EXTRACT(EPOCH FROM (recorded_time - $3::timestamptz)) /
            EXTRACT(EPOCH FROM $5::interval)
        ) span,
        MAX(numbackends - idle_backends) active_conn,
        MAX(idle_backends) idle_backends
    FROM
        pemhistory.database_statistics d
    WHERE
        server_id = $1::integer AND
        ($2::text IS NULL OR database_name = $2::text) AND
        recorded_time >= $3::timestamptz AND recorded_time <= $4::timestamptz
    GROUP BY database_name, span
    ORDER BY span, database_name) a
GROUP BY span' USING p_sid, p_database, v_t_start, v_etime, v_span;

	FETCH v_cursor INTO v_curr_rec;
	IF FOUND THEN

		FETCH v_cursor INTO v_next_rec;

		FOR v_new_rec IN
			EXECUTE 'SELECT ts AS rtime FROM generate_series($1::timestamptz, $2::timestamptz, $3::interval) ts'
			USING v_stime, v_etime, v_span
		LOOP

            IF v_curr_rec.rtime <= v_new_rec.rtime THEN
			    o_aggtime := v_new_rec.rtime;

			    o_idx := 1;
			    o_label := 'Active Connections';
			    o_aggval := v_curr_rec.active_conn;
			    RETURN NEXT;

			    o_idx := 2;
			    o_label := 'Idle Connections';
			    o_aggval := v_curr_rec.idle_conn;
			    RETURN NEXT;
            END IF;

			WHILE v_next_rec IS NOT NULL AND
			    v_new_rec.rtime >= v_next_rec.rtime
            LOOP
                v_curr_rec := v_next_rec;
				FETCH v_cursor INTO v_next_rec;
			END LOOP;
		END LOOP;
	END IF;

	CLOSE v_cursor;
END
$$ LANGUAGE 'plpgsql';

UPDATE pem.chart SET params = '{cid,did,server_id,database_name,start_time,end_time}' WHERE id = 11;
UPDATE pem.chart SET params = '{cid,did,server_id,start_time,end_time}' WHERE id = 55;
UPDATE pem.chart_func SET func = 'SELECT o_idx, o_label, ''Date('' || (EXTRACT(EPOCH FROM o_aggtime) * 1000)::numeric(40, 0)::text || '')'', o_aggval FROM pem.generate_conn_overview_chart_data($1::int4, $2::int4, $3::int4, NULL::text, $4::timestamptz, $5::timestamptz) ORDER BY o_idx, o_aggtime' WHERE id = 55;
UPDATE pem.chart_func SET func = 'SELECT o_idx, o_label, ''Date('' || (EXTRACT(EPOCH FROM o_aggtime) * 1000)::numeric(40, 0)::text || '')'', o_aggval FROM pem.generate_conn_overview_chart_data($1::int4, $2::int4, $3::int4, $4::text, $5::timestamptz, $6::timestamptz) ORDER BY o_idx, o_aggtime' WHERE id = 11;

DROP FUNCTION IF EXISTS pem.generate_host_memory_chart_data(integer, timestamptz, timestamptz);

CREATE OR REPLACE FUNCTION pem.generate_host_memory_chart_data(
	p_cid integer, p_did integer, p_aid integer, p_stime timestamptz, p_etime timestamptz
)
RETURNS TABLE(
	o_idx int2, o_label text, o_aggtime timestamptz, o_aggval numeric
) AS $$
DECLARE
	v_span      interval;
	v_freq      interval;
	v_maxpoints integer;
	v_curr      timestamptz := now()::timestamptz;
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
	SELECT max(last_heartbeat) INTO v_hbtime FROM pem.agent_heartbeat WHERE agent_id = p_aid;

    EXECUTE '
SELECT
    span, points
FROM
    ((SELECT
        -1::integer as lvl,
        (SELECT (value||'' ''||unit)::interval FROM pem.config WHERE param = ''dash_os_memory_span'') as span,
        (SELECT max_points FROM pem.metrices_chart WHERE cid = $1::integer) as points
    )
    UNION ALL
    (SELECT
        CASE
        WHEN cfg.did = -1 THEN
            CASE
            WHEN cfg.objid IS NULL THEN 1::integer
            WHEN $3::integer IS NOT NULL AND cfg.objid = $3::integer AND
                cfg.database IS NULL
                THEN 2::integer
            END
        ELSE
            CASE
            WHEN cfg.objid IS NULL THEN 6::integer
            WHEN $3::integer IS NOT NULL AND cfg.objid = $3::integer AND
                cfg.database IS NULL
                THEN 7::integer
            END
        END AS lvl,
        (cfg.span * ''1 hours''::interval) as span, cfg.points as points
    FROM
        pem.chart_config cfg
    WHERE
        cfg.cid = $1::integer AND (
            (cfg.did = -1 AND cfg.level <= 100) OR
            ($2::integer IS NOT NULL AND cfg.did = $2::integer AND cfg.level = 100)
        ) AND cfg.uid = (
            SELECT u.usesysid FROM pg_catalog.pg_user u
                WHERE u.usename = current_user
        )
    )) config
ORDER BY lvl DESC
LIMIT 1' USING p_cid, p_did, p_aid INTO v_span, v_maxpoints;

	IF p_stime IS NULL OR p_etime IS NULL OR p_stime >= p_etime THEN
		IF v_span IS NULL THEN
			v_span := '7 days'::interval;
		END IF;

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

UPDATE pem.chart SET params = '{cid,did,agent_id,start_time,end_time}' WHERE id = 39;
UPDATE pem.chart_func SET func = 'SELECT o_idx, o_label, ''Date('' || (EXTRACT(EPOCH FROM o_aggtime) * 1000)::numeric(40, 0)::text || '')'', o_aggval FROM pem.generate_host_memory_chart_data($1::int4, $2::int4, $3::int4, $4::timestamptz, $5::timestamptz) ORDER BY o_idx, o_aggtime' WHERE id = 39;


DROP FUNCTION IF EXISTS pem.generate_replication_segment_lag_chart_data(integer, timestamptz, timestamptz);

CREATE OR REPLACE FUNCTION pem.generate_replication_segment_lag_chart_data (
	p_cid integer, p_did integer, p_sid integer, p_stime timestamptz, p_etime timestamptz
) RETURNS TABLE(
	o_idx int2, o_label text, o_aggtime timestamptz, o_aggval bigint
) AS $$
DECLARE
	v_span      interval;
	v_freq      interval;
	v_maxpoints bigint;
	v_curr      timestamptz := now();
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
	SELECT max(last_heartbeat) INTO v_hbtime FROM pem.server_heartbeat WHERE server_id = p_sid;

	EXECUTE '
SELECT
    span, points
FROM
    ((SELECT
        -1::integer as lvl,
        (SELECT (value||'' ''||unit)::interval FROM pem.config WHERE param = ''dash_replication_segmentlag_span'') as span,
        (SELECT max_points FROM pem.metrices_chart WHERE cid = $1::integer) as points
    )
    UNION ALL
    (SELECT
        CASE
        WHEN cfg.did = -1 THEN
            CASE
            WHEN cfg.objid IS NULL THEN 1::integer
            WHEN $3::integer IS NOT NULL AND cfg.objid = $3::integer AND
                cfg.database IS NULL
                THEN 2::integer
            END
        ELSE
            CASE
            WHEN cfg.objid IS NULL THEN 6::integer
            WHEN $3::integer IS NOT NULL AND cfg.objid = $3::integer AND
                cfg.database IS NULL
                THEN 7::integer
            END
        END AS lvl,
        (cfg.span * ''1 hours''::interval) as span, cfg.points as points
    FROM
        pem.chart_config cfg
    WHERE
        cfg.cid = $1::integer AND (
            (cfg.did = -1 AND cfg.level <= 200) OR
            ($2::integer IS NOT NULL AND cfg.did = $2::integer AND cfg.level = 200)
        ) AND cfg.uid = (
            SELECT u.usesysid FROM pg_catalog.pg_user u
                WHERE u.usename = current_user
        )
    )) config
ORDER BY lvl DESC
LIMIT 1' USING p_cid, p_did, p_sid INTO v_span, v_maxpoints;

	IF p_stime IS NULL OR p_etime IS NULL OR p_stime >= p_etime THEN
		IF v_span IS NULL THEN
			v_span := '7 days'::interval;
		END IF;

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

UPDATE pem.chart SET params = '{cid,did,server_id,start_time,end_time}' WHERE id = 81;
UPDATE pem.chart_func SET func = 'SELECT o_idx, o_label, ''Date('' || (EXTRACT(EPOCH FROM o_aggtime) * 1000)::numeric(40, 0)::text || '')'', o_aggval FROM pem.generate_replication_segment_lag_chart_data($1::int4, $2::int4, $3::int4, $4::timestamptz, $5::timestamptz) ORDER BY o_idx, o_aggtime' WHERE id = 81;

DROP FUNCTION IF EXISTS pem.generate_replication_page_lag_chart_data(integer, timestamptz, timestamptz);

CREATE OR REPLACE FUNCTION pem.generate_replication_page_lag_chart_data (
	p_cid integer, p_did integer, p_sid integer, p_stime timestamptz, p_etime timestamptz
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

	EXECUTE '
SELECT
    span, points
FROM
    ((SELECT
        -1::integer as lvl,
        (SELECT (value||'' ''||unit)::interval FROM pem.config WHERE param = ''dash_replication_pagelag_span'') as span,
        (SELECT max_points FROM pem.metrices_chart WHERE cid = $1::integer) as points
    )
    UNION ALL
    (SELECT
        CASE
        WHEN cfg.did = -1 THEN
            CASE
            WHEN cfg.objid IS NULL THEN 1::integer
            WHEN $3::integer IS NOT NULL AND cfg.objid = $3::integer AND
                cfg.database IS NULL
                THEN 2::integer
            END
        ELSE
            CASE
            WHEN cfg.objid IS NULL THEN 6::integer
            WHEN $3::integer IS NOT NULL AND cfg.objid = $3::integer AND
                cfg.database IS NULL
                THEN 7::integer
            END
        END AS lvl,
        (cfg.span * ''1 hours''::interval) as span, cfg.points as points
    FROM
        pem.chart_config cfg
    WHERE
        cfg.cid = $1::integer AND (
            (cfg.did = -1 AND cfg.level <= 200) OR
            ($2::integer IS NOT NULL AND cfg.did = $2::integer AND cfg.level = 200)
        ) AND cfg.uid = (
            SELECT u.usesysid FROM pg_catalog.pg_user u
                WHERE u.usename = current_user
        )
    )) config
ORDER BY lvl DESC
LIMIT 1' USING p_cid, p_did, p_sid INTO v_span, v_maxpoints;

	IF p_stime IS NULL OR p_etime IS NULL OR p_stime >= p_etime THEN
		IF v_span IS NULL THEN
			v_span := '7 days'::interval;
		END IF;

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

UPDATE pem.chart SET params = '{cid,did,server_id,start_time,end_time}' WHERE id = 82;
UPDATE pem.chart_func SET func = 'SELECT o_idx, o_label, ''Date('' || (EXTRACT(EPOCH FROM o_aggtime) * 1000)::numeric(40, 0)::text || '')'', o_aggval FROM pem.generate_replication_page_lag_chart_data($1::int4, $2::int4, $3::int4, $4::timestamptz, $5::timestamptz) ORDER BY o_idx, o_aggtime' WHERE id = 82;

DROP FUNCTION IF EXISTS pem.generate_slony_event_lag_chart_data(integer, text, timestamptz, timestamptz);

CREATE OR REPLACE FUNCTION pem.generate_slony_event_lag_chart_data(
	p_cid integer, p_did integer, p_sid integer, p_database text, p_stime timestamptz, p_etime timestamptz
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

	EXECUTE '
SELECT
    span, points
FROM
    ((SELECT
        -1::integer as lvl,
        (SELECT (value||'' ''||unit)::interval FROM pem.config WHERE param = ''dash_db_eventlag_span'') as span,
        (SELECT max_points FROM pem.metrices_chart WHERE cid = $1::integer) as points
    )
    UNION ALL
    (SELECT
        CASE
        WHEN cfg.did = -1 THEN
            CASE
            WHEN cfg.objid IS NULL THEN 1::integer
            WHEN $3::integer IS NOT NULL AND cfg.objid = $3::integer AND
                cfg.database IS NULL
                THEN 2::integer
            WHEN $3::integer IS NOT NULL AND cfg.objid = $3::integer AND
                cfg.database IS NOT NULL AND cfg.database = $4::text
                THEN 3::integer
            END
        ELSE
            CASE
            WHEN cfg.objid IS NULL THEN 6::integer
            WHEN $3::integer IS NOT NULL AND cfg.objid = $3::integer AND
                cfg.database IS NULL
                THEN 7::integer
            WHEN $3::integer IS NOT NULL AND cfg.objid = $3::integer AND
                cfg.database IS NOT NULL AND cfg.database = $4::text
                THEN 8::integer
            END
        END AS lvl,
        (cfg.span * ''1 hours''::interval) as span, cfg.points as points
    FROM
        pem.chart_config cfg
    WHERE
        cfg.cid = $1::integer AND (
            (cfg.did = -1 AND cfg.level <= 300) OR
            ($2::integer IS NOT NULL AND cfg.did = $2::integer AND cfg.level = 300)
        ) AND cfg.uid = (
            SELECT u.usesysid FROM pg_catalog.pg_user u
                WHERE u.usename = current_user
        )
    )) config
ORDER BY lvl DESC
LIMIT 1' USING p_cid, p_did, p_sid, p_database INTO v_span, v_maxpoints;

	IF p_stime IS NULL OR p_etime IS NULL OR p_stime >= p_etime THEN
		IF v_span IS NULL THEN
			v_span := '7 days'::interval;
		END IF;

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
        idx::int2 o_idx, lbl o_lbl, to_timestamp((dra * (EXTRACT(EPOCH FROM $2::interval) / $3::bigint)) + EXTRACT(EPOCH FROM $4::timestamptz)) o_aggtime, MAX(val)::numeric o_aggval
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


DROP FUNCTION IF EXISTS pem.generate_slony_time_lag_chart_data(integer, text, timestamptz, timestamptz);

CREATE OR REPLACE FUNCTION pem.generate_slony_time_lag_chart_data(
	p_cid integer, p_did integer, p_sid integer, p_database text, p_stime timestamptz, p_etime timestamptz
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

		EXECUTE '
SELECT
    span, points
FROM
    ((SELECT
        -1::integer as lvl,
        (SELECT (value||'' ''||unit)::interval FROM pem.config WHERE param = ''dash_db_timelag_span'') as span,
        (SELECT max_points FROM pem.metrices_chart WHERE cid = $1::integer) as points
    )
    UNION ALL
    (SELECT
        CASE
        WHEN cfg.did = -1 THEN
            CASE
            WHEN cfg.objid IS NULL THEN 1::integer
            WHEN $3::integer IS NOT NULL AND cfg.objid = $3::integer AND
                cfg.database IS NULL
                THEN 2::integer
            WHEN $3::integer IS NOT NULL AND cfg.objid = $3::integer AND
                cfg.database IS NOT NULL AND cfg.database = $4::text
                THEN 3::integer
            END
        ELSE
            CASE
            WHEN cfg.objid IS NULL THEN 6::integer
            WHEN $3::integer IS NOT NULL AND cfg.objid = $3::integer AND
                cfg.database IS NULL
                THEN 7::integer
            WHEN $3::integer IS NOT NULL AND cfg.objid = $3::integer AND
                cfg.database IS NOT NULL AND cfg.database = $4::text
                THEN 8::integer
            END
        END AS lvl,
        (cfg.span * ''1 hours''::interval) as span, cfg.points as points
    FROM
        pem.chart_config cfg
    WHERE
        cfg.cid = $1::integer AND (
            (cfg.did = -1 AND cfg.level <= 300) OR
            ($2::integer IS NOT NULL AND cfg.did = $2::integer AND cfg.level = 300)
        ) AND cfg.uid = (
            SELECT u.usesysid FROM pg_catalog.pg_user u
                WHERE u.usename = current_user
        )
    )) config
ORDER BY lvl DESC
LIMIT 1' USING p_cid, p_did, p_sid, p_database INTO v_span, v_maxpoints;

	IF p_stime IS NULL OR p_etime IS NULL OR p_stime >= p_etime THEN
		IF v_span IS NULL THEN
			v_span := '7 days'::interval;
		END IF;

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
        idx::int2 o_idx, lbl o_lbl, to_timestamp((dra * (EXTRACT(EPOCH FROM $2::interval) / $3::bigint)) + EXTRACT(EPOCH FROM $4::timestamptz)) o_aggtime, MAX(val)::numeric o_aggval
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

UPDATE pem.chart SET params = '{cid,did,server_id,database_name,start_time,end_time}' WHERE id in (85, 86);
UPDATE pem.chart_func SET func = 'SELECT o_idx, o_label, ''Date('' || (EXTRACT(EPOCH FROM o_aggtime) * 1000)::numeric(40, 0)::text || '')'', o_aggval FROM pem.generate_slony_event_lag_chart_data($1::int4, $2::int4, $3::int4, $4::text, $5::timestamptz, $6::timestamptz) ORDER BY o_idx, o_aggtime' WHERE id = 85;
UPDATE pem.chart_func SET func = 'SELECT o_idx, o_label, ''Date('' || (EXTRACT(EPOCH FROM o_aggtime) * 1000)::numeric(40, 0)::text || '')'', o_aggval FROM pem.generate_slony_time_lag_chart_data($1::int4, $2::int4, $3::int4, $4::text, $5::timestamptz, $6::timestamptz) ORDER BY o_idx, o_aggtime' WHERE id = 86;


DROP FUNCTION IF EXISTS pem.generate_server_pages_written (integer, timestamptz, timestamptz);

CREATE OR REPLACE FUNCTION pem.generate_server_pages_written (
	p_cid integer, p_did integer, p_sid integer, p_stime timestamptz, p_etime timestamptz
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

	EXECUTE '
SELECT
    span, points
FROM
    ((SELECT
        -1::integer as lvl,
        (SELECT (value||'' ''||unit)::interval FROM pem.config WHERE param = ''dash_server_buffers_written'') as span,
        (SELECT max_points FROM pem.metrices_chart WHERE cid = $1::integer) as points
    )
    UNION ALL
    (SELECT
        CASE
        WHEN cfg.did = -1 THEN
            CASE
            WHEN cfg.objid IS NULL THEN 1::integer
            WHEN $3::integer IS NOT NULL AND cfg.objid = $3::integer AND
                cfg.database IS NULL
                THEN 2::integer
            END
        ELSE
            CASE
            WHEN cfg.objid IS NULL THEN 6::integer
            WHEN $3::integer IS NOT NULL AND cfg.objid = $3::integer AND
                cfg.database IS NULL
                THEN 7::integer
            END
        END AS lvl,
        (cfg.span * ''1 hours''::interval) as span, cfg.points as points
    FROM
        pem.chart_config cfg
    WHERE
        cfg.cid = $1::integer AND (
            (cfg.did = -1 AND cfg.level <= 200) OR
            ($2::integer IS NOT NULL AND cfg.did = $2::integer AND cfg.level = 200)
        ) AND cfg.uid = (
            SELECT u.usesysid FROM pg_catalog.pg_user u
                WHERE u.usename = current_user
        )
    )) config
ORDER BY lvl DESC
LIMIT 1' USING p_cid, p_did, p_sid INTO v_span, v_maxpoints;

	IF p_stime IS NULL OR p_etime IS NULL OR p_stime >= p_etime THEN
		IF v_span IS NULL THEN
			v_span := '7 days'::interval;
		END IF;

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

UPDATE pem.chart SET params = '{cid,did,server_id,start_time,end_time}' WHERE id = 87;
UPDATE pem.chart_func SET func = 'SELECT o_idx, o_label, ''Date('' || (EXTRACT(EPOCH FROM o_aggtime) * 1000)::numeric(40, 0)::text || '')'', o_aggval FROM pem.generate_server_pages_written($1::int4, $2::int4, $3::int4, $4::timestamptz, $5::timestamptz) ORDER BY o_idx, o_aggtime' WHERE id = 87;

COMMIT TRANSACTION;
