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

-- Update the schema version
CREATE OR REPLACE FUNCTION pem.schema_version()
  RETURNS integer AS
'SELECT 201404171::integer;'
  LANGUAGE 'sql' IMMUTABLE;

DROP FUNCTION pem.generate_metric_chart_data (
	integer, integer, integer, text, text, integer, boolean, boolean
);

CREATE OR REPLACE FUNCTION pem.get_chart_params(id integer, mid integer, OUT attrs text, OUT vals text)
	RETURNS record
AS $$
DECLARE
	p pem.chart_metric_param[];
	i integer;
BEGIN
	EXECUTE 'SELECT params FROM pem.chart_metric WHERE cid = $1::integer AND mid = $2::integer' USING id, mid INTO p;

	IF p IS NULL THEN
		RETURN;
	END IF;

	attrs := '';
	vals  := '';

	FOR i IN 1 .. array_upper(p, 1)
	LOOP
		IF length(attrs) <> 0 THEN
			attrs := attrs || ',';
			vals  := vals || ',';
		END IF;
		attrs := attrs || p[i].name;
		vals  := vals || pg_catalog.quote_ident(p[i].value);
	END LOOP;
END
$$ LANGUAGE 'plpgsql';

-------------------------------------------------------------------------------
-- Function:                                                                  -
--    pem.generate_metric_chart_data                                          -
--                                                                            -
-- Parameters:                                                                -
--    p_cid     : chart-id                                                    -
--    p_aid     : agent-id                                                    -
--    p_sid     : server-id                                                   -
--    p_db      : database-name                                               -
--    p_schema  : schema-name                                                 -
--    p_level   : Current dashboard level                                     -
--    p_sysobjs : Show the system objects                                     -
--    p_stime   : Start time                                                  -
--    p_etime   : End time                                                    -
--                                                                            -
-- Returns:                                                                   -
--    o_idx     : Index (position) of the generated data                      -
--    o_label   : Custom label if generated                                   -
--    o_aggtime : Aggregated time for generated data                          -
--    o_agg_val : Calculated the aggregated value at that point               -
--                                                                            -
-- Purpose:                                                                   -
--    This will generate the aggregated values for the metrices for the       -
--    line/table charts. The last three parameters are used to calculate the  -
--    points for the zoom support.                                            -
--                                                                            -
-------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION pem.generate_metric_chart_data (
	p_cid integer, p_aid integer, p_sid integer, p_db text, p_schema text,
	p_level integer, p_sysobjs boolean, p_stime timestamptz DEFAULT NULL,
	p_etime timestamptz DEFAULT NULL)
RETURNS TABLE(o_idx int2, o_label text, o_aggtime timestamptz, o_aggval numeric)
AS $$
DECLARE
	v_chart_exists boolean := false;
	v_s_time       timestamptz := NULL;
	v_e_time       timestamptz := now();
	v_e_span       interval := NULL;
	v_e_id         integer := NULL;
	v_e_op         text;
	v_e_val        numeric;
	v_maxpoints    integer;
	v_mcurs        refcursor;
	v_gcurs        refcursor;
	v_metric       pem.chart_metric%ROWTYPE;
	v_chart        pem.chart%ROWTYPE;
	v_pid          int4;
	v_target       integer;
	v_applies      integer;
	v_deleted      boolean;
	v_keys         text[];
	v_key_vals     text[];
	v_m_rest_dbs   text[];
	v_rest_dbs     text[];
	v_rest_schemas text[];
	v_pos          int2 := 0;
	v_qry          text;
	v_t_str        text;
	v__params      text[];
	v__vals        text[];
	v_params       text[];
	v_vals         text[];
	v_mlbl         text := NULL;
	v_percent_unit boolean := false;
	v_ptype        text := NULL;
	v_span         interval := NULL;
	v_r_monitored  boolean := false;
	v_m_ops        text[][] = array[]::text[][];
	v_t_op         text[] := NULL;
	v_freq         text := NULL;
	v_minspan      interval := 0;
	v_aggspan      interval;
	v_obj_active   boolean;
	v_obj          text;
	v_groupon      text;
	v_where        text;
	v_t_time       timestamptz := now();
	v_m_idx        integer;

	v_m_e_time     timestamptz := NULL;
	v_m_s_time     timestamptz := NULL;

	v_m_raw_cur    refcursor;
	v_m_curr_rec   record;
	v_m_next_rec   record;
	v_m_new_rec    record;
	v_aggarr       numeric[];

	v_ttime        numeric[];
	v_tvals        numeric[];
	v_t_val        numeric;
	v_cnt          integer;
	v_tmpx         numeric;
	v_tmpy         numeric;
	v_ma           numeric;
	v_mb           numeric;
	v_xa           numeric;
	v_ya           numeric;
	v_xx           numeric;
	v_xy           numeric;

BEGIN
	-- Check if the data for the chart exists in the pem.metrices_chart
	EXECUTE 'SELECT CASE WHEN count(charts.*) > 0 THEN true ELSE false END FROM ((SELECT cid FROM pem.metrices_chart WHERE cid = $1::int4) UNION ALL (SELECT cid FROM pem.capacity_report_chart WHERE cid = $1::int4)) AS charts'
	INTO v_chart_exists USING p_cid;

	IF NOT v_chart_exists OR v_chart_exists IS NULL THEN
		RAISE EXCEPTION '101';
	END IF;

	BEGIN
		EXECUTE 'SELECT (value||'' ''||unit)::interval FROM pem.config WHERE param = (SELECT rwlimit_span_param FROM pem.chart WHERE id = $1::int4)'
		INTO v_span USING p_cid;
	EXCEPTION
	WHEN invalid_datetime_format THEN
		v_span := '7 days'::interval;
	WHEN datetime_field_overflow THEN
		v_span := '7 days'::interval;
	END;

	-- Fetch the start time, end time, maximum points & aggregation intervals
	IF v_span IS NOT NULL THEN
		EXECUTE E'
SELECT
	now() - $1::interval, now(), max_points, ext_span, ext_id, ext_op, ext_val
FROM (
	SELECT
		mc.cid, mc.time_span, mc.max_points, mc.ext_span, mc.ext_id, mc.ext_op, mc.ext_val
	FROM
		pem.chart c
		LEFT JOIN pem.metrices_chart mc ON (mc.cid = c.id AND NOT (c.type = ''CL'' OR c.type = ''CT''))
	WHERE c.id = $2::int
UNION ALL
SELECT
	cp.cid,
	historical * INTERVAL ''1 day'' AS time_span,
	(SELECT value FROM pem.config WHERE param = ''cm_data_points_per_report'')::integer AS max_points,
	CASE
	WHEN cp.type = ''E'' AND extrapolated IS NOT NULL THEN extrapolated * INTERVAL ''1 day''
	ELSE ''0 minutes''::interval
	END AS ext_span, cp.midx AS ext_id, cp.toperator::character varying AS ext_op,
	cp.tval AS ext_val
FROM
	pem.chart c
	LEFT JOIN pem.capacity_report_chart cp ON (cp.cid = c.id AND (c.type = ''CL'' OR c.type = ''CT''))
WHERE c.id = $2::int) AS chart_details
WHERE cid IS NOT NULL LIMIT 1'
		INTO v_s_time, v_e_time, v_maxpoints, v_e_span, v_e_id, v_e_op, v_e_val
		USING v_span, p_cid;
	ELSE
		EXECUTE E'
SELECT
	now() - time_span, now(), max_points, ext_span, ext_id, ext_op, ext_val
FROM (
	SELECT
		mc.cid, mc.time_span, mc.max_points, mc.ext_span, mc.ext_id, mc.ext_op, mc.ext_val
	FROM
		pem.chart c
		LEFT JOIN pem.metrices_chart mc ON (mc.cid = c.id AND NOT (c.type = ''CL'' OR c.type = ''CT''))
	WHERE c.id = $1::int
UNION ALL
SELECT
	cp.cid,
	historical * INTERVAL ''1 day'' AS time_span,
	(SELECT value FROM pem.config WHERE param = ''cm_data_points_per_report'')::integer AS max_points,
	CASE
	WHEN cp.type = ''E'' AND extrapolated IS NOT NULL THEN extrapolated * INTERVAL ''1 day''
	ELSE ''0 minutes''::interval
	END AS ext_span, cp.midx AS ext_id, cp.toperator::character varying AS ext_op,
	cp.tval AS ext_val
FROM
	pem.chart c
	LEFT JOIN pem.capacity_report_chart cp ON (cp.cid = c.id AND (c.type = ''CL'' OR c.type = ''CT''))
WHERE c.id = $1::int) AS chart_details
WHERE cid IS NOT NULL LIMIT 1'
		INTO v_s_time, v_e_time, v_maxpoints, v_e_span, v_e_id, v_e_op, v_e_val
		USING p_cid;
	END IF;

	-- Couldn't fetch the time_span/max_points from the pem.metrices_chart table
	IF v_s_time IS NULL THEN
		RAISE EXCEPTION '102';
	END IF;

	CASE
	WHEN p_level = 100 THEN
		-- On agent level dash, agent-id must exists
		IF p_aid IS NULL OR p_aid <= 0 THEN
			RAISE EXCEPTION '103';
		END IF;

	WHEN p_level >= 200 THEN
		-- On server level dash, server-id must exists
		IF p_sid IS NULL OR p_sid <= 0 THEN
			RAISE EXCEPTION '104';
		END IF;

		-- Fetch agent-id, if not provided
		IF p_aid IS NULL OR p_aid <= 0 THEN
			p_aid := NULL;

			EXECUTE 'SELECT agent_id FROM pem.agent_server_binding WHERE server_id = $1::int4' INTO p_aid USING p_sid;

			IF p_aid IS NULL THEN
				RAISE EXCEPTION '105';
			END IF;
		END IF;

		-- Fetch remote monitoring status of the server.
		EXECUTE 'SELECT is_remote_monitoring FROM pem.server WHERE id = $1::int4' INTO v_r_monitored USING p_sid;

		-- Fetch the restricted databases information (only for server level charts)
		IF p_level = 200 THEN
			EXECUTE '
SELECT
	pem.db_escaped_string_to_array(COALESCE(o.database_restriction, oa.database_restriction))
FROM
	pem.server s
	LEFT OUTER JOIN pg_catalog.pg_roles owner ON (owner.oid = s.owner)
	LEFT OUTER JOIN pem.server_option o ON (s.id = o.server_id AND o.pem_user = current_user)
	LEFT OUTER JOIN pem.server_option oa
		ON (o.id IS NULL AND s.id = oa.server_id AND
			(owner.rolname = oa.pem_user OR (owner.rolname IS NULL AND oa.pem_user IS NULL)))
WHERE
	s.id = $1::int4' INTO v_rest_dbs USING p_sid;
		END IF;

		IF p_level >= 300 THEN
			-- database_name is required for any charts lower than server
			-- level
			IF p_db IS NULL OR trim(p_db) = '' THEN
				RAISE EXCEPTION '106';
			END IF;

			-- Fetch the restricted schema information (for database level chats)
			IF p_level = 300 THEN
				EXECUTE '
SELECT
	pem.db_escaped_string_to_array(COALESCE(o.schema_restriction, oa.schema_restriction))
FROM
	pem.server s
	LEFT OUTER JOIN pg_catalog.pg_roles owner ON (owner.oid = s.owner)
	LEFT OUTER JOIN pem.database_option o ON (s.id = o.server_id AND o.pem_user = current_user AND o.database = $2::text)
	LEFT OUTER JOIN pem.database_option oa
		ON (o.id IS NULL AND s.id = oa.server_id AND oa.database = $2::text AND
			(owner.rolname = oa.pem_user OR (owner.rolname IS NULL AND oa.pem_user IS NULL)))
WHERE
	s.id = $1::int4' INTO v_rest_schemas USING p_sid, p_db;
			END IF;
		END IF;
	ELSE -- DO NOTHING
	END CASE;

	EXECUTE 'SELECT * FROM pem.chart WHERE id = $1::int4' USING p_cid INTO v_chart;

	-- Fetch all the metrices for this chart
	OPEN v_mcurs FOR EXECUTE 'SELECT * FROM pem.chart_metric WHERE cid = $1::int4' USING p_cid;
	LOOP
		FETCH v_mcurs INTO v_metric;
		EXIT WHEN NOT FOUND;

		v_pid := NULL;
		v_target := NULL;
		v_applies := NULL;
		v_keys := NULL;
		v_deleted := false;

		-- FETCH target_type, probe_applies_to, PRIMARY KEYS FOR THE INVOLVED
		-- PROBE-TABLE
		EXECUTE
		'SELECT p.id, p.target_type_id, p.applies_to_id, ARRAY(SELECT pc.internal_name FROM pem.probe_column pc WHERE pc.probe_id = p.id AND (($2::int4 = 300 AND pc.internal_name <> ''database_name'') OR ($2::int4 = 400 AND pc.internal_name NOT IN (''database_name'', ''schema_name'')) OR true) AND pc.classification = ''k'' ORDER BY pc.id) AS keys, p.deleted FROM pem.probe p WHERE p.internal_name = $1::text'
		INTO v_pid, v_target, v_applies, v_keys, v_deleted USING v_metric.tbl, p_level;

		o_idx := 0;
		o_aggtime := NULL;
		o_aggval  := NULL;

		-- WE COULDN'T FIND 'probe_target_id', IT MEANS THE PROBE WITH
		-- THAT NAME DOES NOT EXISTS
		IF v_target IS NULL THEN
			o_label :=  '107|'::text || v_metric.tbl;

			IF v_e_id IS NOT NULL AND v_e_id = v_metric.mid THEN
				RAISE EXCEPTION '109|%', v_metric.tbl;
			END IF;

			RETURN NEXT;
			CONTINUE;
		END IF;

		IF v_deleted THEN
			o_label :=  '108|'::text || v_metric.tbl;

			-- The probe has been marked for deletion
			IF v_e_id IS NOT NULL AND v_e_id = v_metric.mid THEN
				o_label := '108a';
			END IF;

			RETURN NEXT;
			CONTINUE;
		END IF;

		-- If server is remotely monitored then we will not render agent level metrics
		IF v_r_monitored AND v_target = 100 THEN
			o_label :=  '111';
			RETURN NEXT;
			CONTINUE;
		END IF;

		IF v_metric.params IS NOT NULL OR array_length(v_metric.params::pem.chart_metric_param[], 1) <> 0 THEN
			SELECT string_agg('pc.' || pg_catalog.quote_ident((param).name) || ' = ' || pg_catalog.quote_literal((param).value), ' AND ') FROM (SELECT unnest(v_metric.params::pem.chart_metric_param[]) AS param) p WHERE (param).name IN ('agent_id','server_id', 'database_name') INTO v_t_str;

			CASE
			WHEN ((v_metric.params::pem.chart_metric_param[])[1]).name = 'agent_id' THEN
				EXECUTE 'SELECT description, active FROM pem.agent WHERE id = $1::int4'
					USING ((v_metric.params::pem.chart_metric_param[])[1]).value
					INTO v_obj, v_obj_active;
			WHEN ((v_metric.params::pem.chart_metric_param[])[1]).name = 'server_id' THEN
				EXECUTE 'SELECT description, active FROM pem.server WHERE id = $1::int4'
					USING ((v_metric.params::pem.chart_metric_param[])[1]).value
					INTO v_obj, v_obj_active;
			ELSE
			END CASE;
			IF v_obj_active IS NULL OR v_obj_active = false THEN
				o_label :=  '110|'::text || COALESCE(v_obj, ((v_metric.params::pem.chart_metric_param[])[1]).value);

				-- The probe has been marked for deletion
				IF v_e_id IS NOT NULL AND v_e_id = v_metric.mid THEN
					o_label := '110a|'::text || COALESCE(v_obj, ((v_metric.params::pem.chart_metric_param[])[1]).value);
				END IF;

				RETURN NEXT;
				CONTINUE;
			END IF;

			CASE
			WHEN ((v_metric.params::pem.chart_metric_param[])[1]).name = 'agent_id' THEN
				IF v_freq IS NOT NULL THEN
					v_freq := v_freq || ' UNION ALL (SELECT COALESCE(pac.execution_frequency, p.default_execution_frequency) AS freq FROM pem.probe p LEFT JOIN pem.probe_config_agent pac ON (p.id = pac.probe_id AND pac.agent_id = ' || ((v_metric.params::pem.chart_metric_param[])[1]).value || ') WHERE p.id = ' || v_pid || ')';
				ELSE
					v_freq := '(SELECT COALESCE(pac.execution_frequency, p.default_execution_frequency) AS freq FROM pem.probe p LEFT JOIN pem.probe_config_agent pac ON (p.id = pac.probe_id AND pac.agent_id = ' || ((v_metric.params::pem.chart_metric_param[])[1]).value || ') WHERE p.id = ' || v_pid || ')';
				END IF;
			WHEN ((v_metric.params::pem.chart_metric_param[])[1]).name = 'server_id' THEN
				IF v_freq IS NOT NULL THEN
					v_freq := v_freq || ' UNION ALL (SELECT COALESCE(psc.execution_frequency, p.default_execution_frequency) AS freq FROM pem.probe p LEFT JOIN pem.probe_config_server psc ON (p.id = psc.probe_id AND psc.server_id = ' || ((v_metric.params::pem.chart_metric_param[])[1]).value || ') WHERE p.id = ' || v_pid || ')';
				ELSE
					v_freq := '(SELECT COALESCE(psc.execution_frequency, p.default_execution_frequency) AS freq FROM pem.probe p LEFT JOIN pem.probe_config_server psc ON (p.id = psc.probe_id AND psc.server_id = ' || ((v_metric.params::pem.chart_metric_param[])[1]).value || ') WHERE p.id = ' || v_pid || ')';
				END IF;
			END CASE;
			v_pos := v_pos + 1;

			SELECT string_agg(CASE WHEN (param).name = 'agent_id' THEN (SELECT description FROM pem.agent WHERE id = (param).value::int4) WHEN (param).name = 'server_id' THEN (SELECT description FROM pem.server WHERE id = (param).value::int4) ELSE (param).value END, '/'), string_agg(pg_catalog.quote_ident((param).name) || ' = ' || pg_catalog.quote_literal((param).value), ' AND '), string_agg(pg_catalog.quote_ident((param).name), ', ') FROM (SELECT unnest(v_metric.params::pem.chart_metric_param[]) AS param) p INTO v_t_str, v_where, v_groupon;

			EXECUTE E'
SELECT
	(CASE WHEN NOT pit_by_default THEN display_name || ''+'' ELSE display_name END), unit_of_value = ''%''::text
FROM pem.probe_column
WHERE probe_id = $1::int4 AND internal_name = $2::text AND is_graphable
UNION ALL
SELECT
	display_name, unit_of_value = ''%''::text
FROM pem.probe_column
WHERE probe_id = $1::int4 AND (internal_name || ''_pit'') = $2::text AND is_graphable AND NOT pit_by_default AND calculate_pit'
				USING v_pid, v_metric.metrices[1] INTO v_mlbl, v_percent_unit;
			v_mlbl := v_mlbl || ' [' || v_t_str || ']';

			-- pos, label, probe_tbl, probe_col, agg, condition, groupon
			IF v_e_id IS NOT NULL AND v_e_id = v_metric.mid THEN
				v_t_op := ARRAY[v_pos::text, v_mlbl, v_metric.tbl, v_metric.metrices[1]::text, v_metric.agg_func[1]::text, v_where, v_groupon, v_percent_unit::text];
			ELSE
				v_m_ops := v_m_ops || ARRAY[ARRAY[v_pos::text, v_mlbl, v_metric.tbl, v_metric.metrices[1]::text, v_metric.agg_func[1]::text, v_where, v_groupon, v_percent_unit::text]];
			END IF;
			EXECUTE 'SELECT CASE WHEN min(recorded_time) < $1::timestamptz THEN min(recorded_time) ELSE $1::timestamptz END FROM pemhistory.' || pg_catalog.quote_ident(v_metric.tbl) || ' WHERE ' || v_where USING v_t_time INTO v_t_time;
		ELSE
			-- We need to find out, if this metric actually generates multiple
			-- sub-metrices (because they may have other primary keys too)
			IF p_level > 0 AND v_keys IS NOT NULL AND array_length(v_keys, 1) <> 0 THEN

				v_qry := 'SELECT ARRAY[';

				SELECT string_agg('tbl.' || pg_catalog.quote_ident(v_keys[a]), '::text, ')
					FROM generate_series(array_lower(v_keys,1), array_upper(v_keys,1)) a INTO v_t_str;
				v_qry := v_qry || v_t_str || '::text]::text[] FROM pemdata.' || pg_catalog.quote_ident(v_metric.tbl) || ' tbl';

				v_m_rest_dbs = NULL;
				CASE WHEN v_applies = 100 THEN
						v_qry := v_qry || ' WHERE tbl.agent_id = ' || p_aid::text || '::integer';
						v__params := ARRAY['agent_id'];
						v__vals := ARRAY[p_aid::text];

						IF v_freq IS NOT NULL THEN
							v_freq := v_freq || ' UNION ALL (SELECT COALESCE(pac.execution_frequency, p.default_execution_frequency) AS freq FROM pem.probe p LEFT JOIN pem.probe_config_agent pac ON (p.id = pac.probe_id AND pac.agent_id = ' || p_aid || ') WHERE p.id = ' || v_pid || ')';
						ELSE
							v_freq := '(SELECT COALESCE(pac.execution_frequency, p.default_execution_frequency) AS freq FROM pem.probe p LEFT JOIN pem.probe_config_agent pac ON (p.id = pac.probe_id AND pac.agent_id = ' || p_aid || ') WHERE p.id = ' || v_pid || ')';
						END IF;

					WHEN v_target = 200 THEN
						v_qry := v_qry || ' WHERE tbl.server_id = ' || p_sid::text || '::integer';
						v__params := ARRAY['server_id'];
						v__vals := ARRAY[p_sid::text]::text[];
						IF v_applies >= 300 AND p_level >= 300 THEN
							-- Restricted DBs are availabe that doesn't mean - they're applicable
							-- for this metric
							--
							-- Thye're applicable only if probe can applies to database level and
							-- current dashboard is for server-level
							IF array_length(v_rest_dbs, 1) <> 0 THEN
								v_m_rest_dbs = v_rest_dbs;
							ELSE
								v_m_rest_dbs := NULL;
							END IF;

							v_qry := v_qry || ' AND tbl.database_name = ' || pg_catalog.quote_literal(p_db::text) || '::text';
							v__params := ARRAY['server_id', 'database_name'];
							v__vals := ARRAY[p_sid::text, p_db];

							IF v_freq IS NOT NULL THEN
								v_freq := v_freq || ' UNION ALL (SELECT COALESCE(pdc.execution_frequency, psc.execution_frequency, p.default_execution_frequency) AS freq FROM pem.probe p LEFT JOIN pem.probe_config_server psc ON (p.id = psc.probe_id AND psc.server_id = ' || p_sid || ') LEFT JOIN pem.probe_config_database pdc ON (p.id = pdc.probe_id AND pdc.server_id = ' || p_sid  || ' AND pdc.database_name = ' || pg_catalog.quote_literal(p_db) || ') WHERE p.id = ' || v_pid || ')';
							ELSE
								v_freq := '(SELECT COALESCE(pdc.execution_frequency, psc.execution_frequency, p.default_execution_frequency) AS freq FROM pem.probe p LEFT JOIN pem.probe_config_server psc ON (p.id = psc.probe_id AND psc.server_id = ' || p_sid || ') LEFT JOIN pem.probe_config_database pdc ON (p.id = pdc.probe_id AND pdc.server_id = ' || p_sid  || ' AND pdc.database_name = ' || pg_catalog.quote_literal(p_db) || ') WHERE p.id = ' || v_pid || ')';
							END IF;
						ELSE

							IF v_freq IS NOT NULL THEN
								v_freq := v_freq || ' UNION ALL (SELECT COALESCE(psc.execution_frequency, p.default_execution_frequency) AS freq FROM pem.probe p LEFT JOIN pem.probe_config_server psc ON (p.id = psc.probe_id AND psc.server_id = ' || p_sid || ') WHERE p.id = ' || v_pid || ')';
							ELSE
								v_freq := '(SELECT COALESCE(psc.execution_frequency, p.default_execution_frequency) AS freq FROM pem.probe p LEFT JOIN pem.probe_config_server psc ON (p.id = psc.probe_id AND psc.server_id = ' || p_sid || ') WHERE p.id = ' || v_pid || ')';
							END IF;
						END IF;
						IF v_applies >= 400 AND p_level = 400 THEN
							v__params := ARRAY['server_id', 'database_name', 'schema_name'];
							v__vals := ARRAY[p_sid::text, p_db, p_schema];
							v_qry := v_qry || ' AND tbl.schema_name = ' || pg_catalog.quote_literal(p_schema::text) || '::text';
						END IF;
						IF NOT p_sysobjs THEN
							IF v_applies = 300 THEN
								v_qry := v_qry || ' AND CASE WHEN database_name != '''' THEN database_name != ''template0'' AND database_name != ''template1'' ELSE TRUE END';
							ELSIF v_applies > 300 THEN
								v_qry := v_qry || E' AND CASE WHEN database_name != '''' THEN database_name != ''template0'' AND database_name != ''template1'' AND schema_name NOT IN (''pg_catalog'', ''sys'', ''information_schema'') AND schema_name NOT LIKE ''pg_toast%'' AND schema_name NOT LIKE ''pg_temp%'' ELSE TRUE END';

								v_qry := v_qry || ' AND CASE WHEN database_name != '''' THEN database_name != ''template0'' AND database_name != ''template1'' ELSE TRUE END';
							END IF;
						END IF;
						IF v_applies = 300 THEN
							IF v_rest_dbs IS NOT NULL AND array_length(v_rest_dbs, 1) > 0 THEN
								v_qry := v_qry || ' AND database_name = ANY(' || pg_catalog.quote_literal(v_rest_dbs::text) || ')';
							END IF;
						ELSIF v_applies > 300 THEN
							IF v_rest_dbs IS NOT NULL AND array_length(v_rest_dbs, 1) > 0 THEN
								v_qry := v_qry || ' AND database_name = ANY(' || pg_catalog.quote_literal(v_rest_dbs::text) || ') AND schema_name = ANY(
	SELECT
		COALESCE(o.schema_restriction, oa.schema_restriction)
	FROM
		pem.server s
		LEFT OUTER JOIN pg_catalog.pg_roles owner ON (owner.oid = s.owner)
		LEFT OUTER JOIN pem.database_option o ON (s.id = o.server_id AND o.pem_user = current_user AND o.database = tbl.database_name)
		LEFT OUTER JOIN pem.database_option oa
			ON (o.id IS NULL AND s.id = oa.server_id AND oa.database = tbl.database_name AND
				(owner.rolname = oa.pem_user OR (owner.rolname IS NULL AND oa.pem_user IS NULL)))
	WHERE
		s.id = tbl.server_id)';
							END IF;
							IF p_level = 400 THEN
								v_qry := v_qry || ' AND schema_name = ' || pg_catalog.quote_literal(p_schema::text) || '::text';
							END IF;
						END IF;
					WHEN v_target = 300 THEN
						v_qry := v_qry || ' WHERE tbl.server_id = ' || p_sid::text || '::integer AND tbl.database_name = ' || pg_catalog.quote_literal(p_db::text) || '::text';
						v__params := ARRAY['server_id', 'database_name'];
						v__vals := ARRAY[p_sid::text, p_db]::text[];
						IF v_freq IS NOT NULL THEN
							v_freq := v_freq || ' UNION ALL (SELECT COALESCE(pdc.execution_frequency, psc.execution_frequency, p.default_execution_frequency) AS freq FROM pem.probe p LEFT JOIN pem.probe_config_server psc ON (p.id = psc.probe_id AND psc.server_id = ' || p_sid || ') LEFT JOIN pem.probe_config_database pdc ON (p.id = pdc.probe_id AND pdc.server_id = ' || p_sid  || ' AND pdc.database_name = ' || pg_catalog.quote_literal(p_db) || ') WHERE p.id = ' || v_pid || ')';
						ELSE
							v_freq := '(SELECT COALESCE(pdc.execution_frequency, psc.execution_frequency, p.default_execution_frequency) AS freq FROM pem.probe p LEFT JOIN pem.probe_config_server psc ON (p.id = psc.probe_id AND psc.server_id = ' || p_sid || ') LEFT JOIN pem.probe_config_database pdc ON (p.id = pdc.probe_id AND pdc.server_id = ' || p_sid  || ' AND pdc.database_name = ' || pg_catalog.quote_literal(p_db) || ') WHERE p.id = ' || v_pid || ')';
						END IF;

						IF array_length(v_rest_dbs, 1) <> 0 THEN
							v_m_rest_dbs = v_rest_dbs;
						ELSE
							v_m_rest_dbs := NULL;
						END IF;
						IF v_applies > 300  THEN
							IF p_level > 300 THEN
								v__params := ARRAY['server_id', 'database_name', 'schema_name'];
								v__vals := ARRAY[p_sid::text, p_db, p_schema];
							END IF;
							IF NOT p_sysobjs THEN
								v_qry := v_qry || E' AND (schema_name NOT IN (''pg_catalog'', ''sys'', ''information_schema'') AND schema_name NOT LIKE ''pg_toast%'' AND schema_name NOT LIKE ''pg_temp%'')';
							END IF;
							IF v_rest_schemas IS NOT NULL AND array_length(v_rest_schemas, 1) > 0 THEN
								v_qry := v_qry || ' AND schema_name = ANY(' || pg_catalog.quote_literal(v_rest_schemas::text) || ')';
							END IF;
						END IF;
					WHEN v_target = 400 THEN
						v__params := ARRAY['server_id', 'database_name', 'schema_name'];
						v__vals := ARRAY[p_sid::text, p_db, p_schema];
						v_qry := v_qry || ' WHERE tbl.server_id = ' || p_sid::text || '::integer AND tbl.database_name = ' || pg_catalog.quote_literal(p_db::text) || '::text AND tbl.schema_name = ' || pg_catalog.quote_literal(schema::text) || '::text';
					ELSE
						v_qry := v_qry;
				END CASE;

				IF v_metric.gorderby IS NOT NULL AND array_length(v_metric.gorderby, 1) >0 THEN
					SELECT string_agg('tbl.' || pg_catalog.quote_ident(v_metric.gorderby[i]), ', ')
						FROM generate_series(array_lower(v_metric.gorderby,1), array_upper(v_metric.gorderby,1)) i INTO v_t_str;
					v_qry := v_qry || ' ORDER BY ' || v_t_str;
				END IF;
				IF (v_metric.glimit IS NOT NULL OR v_metric.glimit <> 0) THEN
					IF (v_metric.glimit < 0) THEN
						v_qry := v_qry || ' LIMIT ' || (v_metric.glimit * -1)::text || ' DESC';
					ELSE
						v_qry := v_qry || ' LIMIT ' || v_metric.glimit::text;
					END IF;
				END IF;

				IF v_metric.glimit IS NULL OR v_metric.glimit <> 0 THEN
					OPEN v_gcurs FOR EXECUTE v_qry;
					LOOP
						FETCH v_gcurs INTO v_key_vals;
						EXIT WHEN NOT FOUND;
						v_params := v__params;
						v_vals := v__vals;

						FOR a IN array_lower(v_key_vals, 1) .. array_upper(v_key_vals, 1)
						LOOP
							v_params := v_params || v_keys[a]::text;
							v_vals := v_vals || v_key_vals[a]::text;
						END LOOP;

						FOR m_idx IN array_lower(v_metric.metrices, 1) .. array_upper(v_metric.metrices, 1)
						LOOP
							v_pos := v_pos + 1;
							SELECT string_agg(v_key_vals[b], ', ')
								FROM generate_series(array_lower(v_key_vals,1), array_upper(v_key_vals,1)) b INTO o_label;
							EXECUTE E'
		SELECT
			(CASE WHEN NOT pit_by_default THEN display_name || ''+'' ELSE display_name END), sql_data_type, unit_of_value = ''%''::text
		FROM pem.probe_column
		WHERE probe_id = $1::int4 AND internal_name = $2::text AND is_graphable
		UNION ALL
		SELECT
			display_name, sql_data_type, unit_of_value = ''%''::text
		FROM pem.probe_column
		WHERE probe_id = $1::int4 AND (internal_name || ''_pit'') = $2::text AND is_graphable AND NOT pit_by_default AND calculate_pit'
		USING v_pid, v_metric.metrices[m_idx] INTO v_mlbl, v_ptype, v_percent_unit;

							IF v_chart.labels IS NOT NULL AND array_length(v_chart.labels, 1) >= v_pos AND v_chart.labels[v_pos] IS NOT NULL THEN
								o_label := v_chart.labels[v_pos] || ' - ' || o_label;
							ELSE
								IF v_mlbl IS NOT NULL THEN
									o_label := v_mlbl || ' - ' || o_label;
								END IF;
							END IF;
							IF v_metric.agg_func IS NOT NULL AND array_length(v_metric.agg_func, 1) >= m_idx AND v_metric.agg_func[m_idx] IS NOT NULL THEN
								v_t_str := v_metric.agg_func[m_idx];
							END IF;

							SELECT string_agg(pg_catalog.quote_ident(v_params[idx]) || ' = ' || pg_catalog.quote_literal(v_vals[idx]), ' AND '), string_agg(pg_catalog.quote_ident(v_params[idx]), ', ') FROM generate_series(array_lower(v_params,1), array_upper(v_params,1)) idx INTO v_where, v_groupon;
							-- pos, label, probe_tbl, probe_col, agg, condition, groupon, restricted_dbs
							IF v_e_id IS NOT NULL AND v_e_id = v_metric.mid THEN
								v_t_op := ARRAY[v_pos::text, o_label, v_metric.tbl, v_metric.metrices[m_idx]::text, v_t_str, v_where, v_groupon, v_percent_unit::text];
							ELSE
								v_m_ops := v_m_ops || ARRAY[ARRAY[v_pos::text, o_label, v_metric.tbl, v_metric.metrices[m_idx]::text, v_t_str, v_where, v_groupon, v_percent_unit::text]];
							END IF;
							EXECUTE 'SELECT CASE WHEN min(recorded_time) < $1::timestamptz THEN min(recorded_time) ELSE $1::timestamptz END FROM pemhistory.' || pg_catalog.quote_ident(v_metric.tbl) || ' WHERE ' || v_where USING v_t_time INTO v_t_time;
						END LOOP;
					END LOOP;
					CLOSE v_gcurs;
				ELSE
					FOR m_idx IN array_lower(v_metric.metrices, 1) .. array_upper(v_metric.metrices, 1)
					LOOP
						v_pos := v_pos + 1;
						EXECUTE E'
	SELECT
		(CASE WHEN NOT pit_by_default THEN display_name || ''+'' ELSE display_name END), unit_of_value = ''%''::text
	FROM pem.probe_column
	WHERE probe_id = $1::int4 AND internal_name = $2::text AND is_graphable
	UNION ALL
	SELECT
		display_name, unit_of_value = ''%''::text
	FROM pem.probe_column
	WHERE probe_id = $1::int4 AND (internal_name || ''_pit'') = $2::text AND is_graphable AND NOT pit_by_default AND calculate_pit'
	USING v_pid, v_metric.metrices[m_idx] INTO v_mlbl, v_percent_unit;

						IF v_chart.labels IS NOT NULL AND array_length(v_chart.labels, 1) >= v_pos AND v_chart.labels[v_pos] IS NOT NULL THEN
							o_label := v_chart.labels[v_pos];
						ELSE
							IF v_mlbl IS NOT NULL THEN
								o_label := v_mlbl;
							END IF;
						END IF;

						IF v_metric.agg_func IS NOT NULL AND array_length(v_metric.agg_func, 1) >= m_idx AND v_metric.agg_func[m_idx] IS NOT NULL THEN
							v_t_str := v_metric.agg_func[m_idx];
						END IF;

						SELECT string_agg(pg_catalog.quote_ident(v__params[idx]) || ' = ' || pg_catalog.quote_literal(v__vals[idx]), ' AND '), string_agg(pg_catalog.quote_ident(v__params[idx]), ', ') FROM generate_series(array_lower(v__params,1), array_upper(v__params,1)) idx INTO v_where, v_groupon;

						-- pos, label, probe_tbl, probe_col, agg, condition, groupon, restricted_dbs
						IF v_e_id IS NOT NULL AND v_e_id = v_metric.mid THEN
							v_t_op := ARRAY[v_pos::text, o_label, v_metric.tbl, v_metric.metrices[m_idx]::text, v_t_str, v_where, v_groupon, v_percent_unit::text];
						ELSE
							v_m_ops := v_m_ops || ARRAY[ARRAY[v_pos::text, o_label, v_metric.tbl, v_metric.metrices[m_idx]::text, v_t_str, v_where, v_groupon, v_percent_unit::text]];
						EXECUTE 'SELECT CASE WHEN min(recorded_time) < $1::timestamptz THEN min(recorded_time) ELSE $1::timestamptz END FROM pemhistory.' || pg_catalog.quote_ident(v_metric.tbl) || ' WHERE ' || v_where USING v_t_time INTO v_t_time;
						END IF;
					END LOOP;
				END IF;
			ELSE
				v_params := ARRAY[]::text[];
				v_vals := ARRAY[]::text[];
				v_m_rest_dbs := NULL;

				CASE WHEN v_applies = 100 THEN
						v_params := ARRAY['agent_id'];
						v_vals := ARRAY[p_aid::text];
					WHEN v_target = 200 THEN
						v_params := ARRAY['server_id'];
						v_vals := ARRAY[p_sid::text]::text[];

						IF v_applies >= 300 AND p_level >= 300 THEN
							-- Restricted DBs are availabe that doesn't mean - they're applicable
							-- for this metric
							--
							-- Thye're applicable only if probe can applies to database level and
							-- current dashboard is for server-level
							IF array_length(v_rest_dbs, 1) <> 0 THEN
								v_m_rest_dbs = v_rest_dbs;
							ELSE
								v_m_rest_dbs := NULL;
							END IF;
						END IF;

						IF v_applies >= 400 AND p_level = 400 THEN
							v_params := ARRAY['server_id', 'database_name', 'schema_name'];
							v_vals := ARRAY[p_sid::text, p_db, p_schema];
						ELSIF v_applies >= 300 AND p_level >= 300 THEN
							v_params := ARRAY['server_id', 'database_name'];
							v_vals := ARRAY[p_sid::text, p_db];
						END IF;
					WHEN v_target = 300 THEN
						v_params := ARRAY['server_id', 'database_name'];
						v_vals := ARRAY[p_sid::text, p_db]::text[];
						IF array_length(v_rest_dbs, 1) <> 0 THEN
							v_m_rest_dbs = v_rest_dbs;
						ELSE
							v_m_rest_dbs := NULL;
						END IF;
						IF v_applies > 300  THEN
							IF p_level > 300 THEN
								v_params := ARRAY['server_id', 'database_name', 'schema_name'];
								v_vals := ARRAY[p_sid::text, p_db, p_schema];
							END IF;
						END IF;
					WHEN v_target = 400 THEN
						v_params := ARRAY['server_id', 'database_name', 'schema_name'];
						v_vals := ARRAY[p_sid::text, p_db, p_schema];
				ELSE -- Do nothing
				END CASE;
				CASE WHEN v_metric.params IS NOT NULL THEN
					FOR i IN array_lower(v_metric.params, 1) .. array_upper(v_metric.params, 1)
					LOOP
						IF v_metric.params[i].name IS NOT NULL AND v_metric.params[i].name != '' THEN
							IF p_sid IS NOT NULL AND v_metric.params[i].name = 'server_id' THEN
								v_params := v_params || v_metric.params[i].name;
								v_vals := v_vals || p_sid::text;
							ELSIF p_aid IS NOT NULL AND v_metric.params[i].name = 'agent_id' THEN
								v_params := v_params || v_metric.params[i].name;
								v_vals := v_vals || p_aid::text;
							ELSIF p_db IS NOT NULL AND p_db <> '' AND v_metric.params[i].name = 'database_name' THEN
								v_params := v_params || v_metric.params[i].name;
								v_vals := v_vals || p_db::text;
							ELSIF p_schema IS NOT NULL AND p_schema <> '' AND v_metric.params[i].name = 'schema_name' THEN
								v_params := v_params || v_metric.params[i].name;
								v_vals := v_vals || p_schema::text;
							ELSE
								v_params := v_params || v_metric.params[i].name;
								v_vals := v_vals || v_metric.params[i].value;
							END IF;
						END IF;
					END LOOP;
				ELSE -- Do nothing
				END CASE;

				v_t_str := 'A';
				FOR m_idx IN array_lower(v_metric.metrices, 1) .. array_upper(v_metric.metrices, 1)
				LOOP
					v_pos := v_pos + 1;
					o_label := '';

					EXECUTE E'
	SELECT
		(CASE WHEN NOT pit_by_default THEN display_name || ''+'' ELSE display_name END), sql_data_type, unit_of_value = ''%''::text
	FROM pem.probe_column
	WHERE probe_id = $1::int4 AND internal_name = $2::text AND is_graphable
	UNION ALL
	SELECT
		display_name, sql_data_type, unit_of_value = ''%''::text
	FROM pem.probe_column
	WHERE probe_id = $1::int4 AND (internal_name || ''_pit'') = $2::text AND is_graphable AND NOT pit_by_default AND calculate_pit'
	USING v_pid, v_metric.metrices[m_idx] INTO v_mlbl, v_ptype, v_percent_unit;

					IF v_chart.labels IS NOT NULL AND array_length(v_chart.labels, 1) >= v_pos THEN
						o_label := v_chart.labels[v_pos];
					ELSE
						IF v_mlbl IS NOT NULL THEN
							o_label := v_mlbl;
						END IF;
					END IF;

					IF v_metric.agg_func IS NOT NULL AND array_length(v_metric.agg_func, 1) >= m_idx THEN
						v_t_str := v_metric.agg_func[m_idx];
					END IF;

					SELECT string_agg(pg_catalog.quote_ident(v_params[idx]) || ' = ' || pg_catalog.quote_literal(v_vals[idx]), ' AND '), string_agg(pg_catalog.quote_ident(v_params[idx]), ', ') FROM generate_series(array_lower(v_params,1), array_upper(v_params,1)) idx INTO v_where, v_groupon;

					-- pos, label, probe_tbl, probe_col, agg, condition, groupon, restricted_dbs
					IF v_e_id IS NOT NULL AND v_e_id = v_metric.mid THEN
						v_t_op := ARRAY[v_pos::text, o_label, v_metric.tbl, v_metric.metrices[m_idx]::text, v_t_str, v_where, v_groupon, v_percent_unit::text];
					ELSE
						v_m_ops := v_m_ops || ARRAY[ARRAY[v_pos::text, o_label, v_metric.tbl, v_metric.metrices[m_idx]::text, v_t_str, v_where, v_groupon, v_percent_unit::text]];
					END IF;
					EXECUTE 'SELECT CASE WHEN min(recorded_time) < $1::timestamptz THEN min(recorded_time) ELSE $1::timestamptz END FROM pemhistory.' || pg_catalog.quote_ident(v_metric.tbl) || ' WHERE ' || v_where USING v_t_time INTO v_t_time;
				END LOOP;
			END IF;
		END IF;
	END LOOP;
	CLOSE v_mcurs;
	IF v_freq IS NOT NULL THEN
		EXECUTE 'SELECT (max(freq) || '' seconds'')::interval  FROM (' || v_freq || ') AS f' INTO v_minspan;
	END IF;
	IF v_minspan IS NULL OR v_minspan < '10 seconds'::interval THEN
		v_minspan := '10 seconds'::interval;
	END IF;
	v_aggspan := v_minspan;

	IF v_s_time < v_t_time THEN
		v_s_time := v_t_time;
	END IF;
	v_t_time := v_e_time;
	IF v_maxpoints < 2 THEN
		v_maxpoints := 2;
	END IF;

	IF p_stime IS NOT NULL AND p_etime IS NOT NULL THEN
		IF v_s_time < p_stime THEN
			v_s_time := p_stime;
		END IF;

		v_t_time := now();
		-- We will not entertain the threshold value, while zooming
		IF p_etime > v_t_time AND v_t_time > v_e_time THEN
			v_e_time := v_t_time;
			v_maxpoints := (v_maxpoints * (1 - ((EXTRACT(EPOCH FROM p_etime - v_t_time)) / (EXTRACT(EPOCH FROM p_etime)))))::int4;
		ELSIF p_etime < v_e_time THEN
			v_e_time := p_etime;
		END IF;

		v_aggspan := ((v_e_time - v_s_time) / (v_maxpoints))::interval;
		IF v_minspan > v_aggspan THEN
			v_aggspan := v_minspan;
		END IF;

		v_t_time = v_e_time;

		IF v_t_op IS NOT NULL THEN

			o_idx := v_t_op[1];
			o_label := v_t_op[2];

			-- Get the time when probe started collecting the data
			EXECUTE
			'SELECT COALESCE(MAX(recorded_time), NULL::timestamptz) AS recorded_time FROM pemhistory.' ||
			pg_catalog.quote_ident(v_t_op[3]) || ' WHERE recorded_time <= $1::timestamptz AND ' ||
			v_t_op[6]
			USING v_s_time INTO v_m_s_time;

			IF v_m_s_time IS NULL THEN
				v_m_s_time := v_s_time;
			END IF;

			-- Data for the threshold metric
			--
			-- Queries for landing pages
			-- SUM(probe_data_column) has been used to aggregate the values. For
			-- example on server page if nummbackends are to be
			-- found then SUM() will be taken after applying group by on
			-- server_id for all databases.
			-- truncate has been used in group by clause because
			-- sometimes data collection has time difference in miliseconds
			v_t_str := 'SELECT MAX(recorded_time) AS rtime, SUM(COALESCE(' ||
				pg_catalog.quote_ident(v_t_op[4]) ||
				'::numeric, 0::numeric)) AS mval FROM pemhistory.' ||
				pg_catalog.quote_ident(v_t_op[3]) ||
				' WHERE recorded_time >= $1::timestamptz AND recorded_time <= $2::timestamptz AND ' ||
				v_t_op[6] || ' GROUP BY date_trunc(''second'', recorded_time), ' ||
				v_t_op[7] || ' ORDER BY rtime';

			OPEN v_m_raw_cur FOR EXECUTE v_t_str USING v_m_s_time, v_t_time;

			IF v_t_op[5] = 'F' THEN
				v_t_str := 'SELECT COALESCE(($1::numeric[])[1], 0)';
			ELSIF v_t_op[5] = 'M' THEN
				v_t_str := 'SELECT COALESCE(max(d), 0) FROM unnest($1::numeric[]) d';
			ELSIF v_t_op[5] = 'm' THEN
				v_t_str := 'SELECT COALESCE(min(d), 0) FROM unnest($1::numeric[]) d';
			ELSE
				v_t_str := 'SELECT COALESCE(avg(d), 0) FROM unnest($1::numeric[]) d';
			END IF;

			FETCH v_m_raw_cur INTO v_m_curr_rec;
			IF FOUND THEN
				FETCH v_m_raw_cur INTO v_m_next_rec;
				o_aggval := v_m_curr_rec.mval;

				FOR v_m_new_rec IN
					EXECUTE 'SELECT ts AS rtime FROM generate_series($1::timestamptz, $2::timestamptz, $3::interval) ts'
					USING v_s_time, v_t_time, v_aggspan
				LOOP
					IF (v_m_curr_rec.rtime IS NOT NULL
						AND v_m_curr_rec.rtime <= v_m_new_rec.rtime
						AND v_m_next_rec IS NOT NULL
						AND v_m_new_rec.rtime >= v_m_next_rec.rtime) THEN
							v_aggarr := ARRAY[]::numeric[];
							-- Find the next value for the time, which is closest to the
							-- next expected time
							WHILE v_m_next_rec IS NOT NULL AND
								v_m_new_rec.rtime >= v_m_next_rec.rtime
							LOOP
								v_aggarr := v_aggarr || v_m_next_rec.mval;
								v_m_curr_rec := v_m_next_rec;
								FETCH v_m_raw_cur INTO v_m_next_rec;
							END LOOP;
							o_aggtime := v_m_new_rec.rtime;
							EXECUTE v_t_str INTO o_aggval USING v_aggarr;
							RETURN NEXT;

							o_aggval := v_aggarr[array_length(v_aggarr, 1)];
							CONTINUE;
					END IF;
					IF v_m_curr_rec.rtime <= v_m_new_rec.rtime THEN
						o_aggtime := v_m_new_rec.rtime;

						RETURN NEXT;
					END IF;
				END LOOP;
			END IF;

			CLOSE v_m_raw_cur;
		END IF;
	ELSE
		IF v_t_op IS NULL THEN
			v_e_time := v_e_time + v_e_span;
			v_aggspan := ((v_e_time + v_e_span - v_s_time) / (v_maxpoints - 1))::interval;
			IF v_minspan > v_aggspan THEN
				v_aggspan := v_minspan;
			END IF;
		ELSE
			IF v_t_op[8]::boolean = TRUE AND v_e_val > 100 THEN
				v_e_val := 100;
			END IF;

			o_idx := v_t_op[1];
			o_label := v_t_op[2];

			-- calculate end-time
			-- Get the time when probe started collecting the data
			EXECUTE
			'SELECT COALESCE(MAX(recorded_time), NULL::timestamptz) AS recorded_time FROM pemhistory.' ||
			pg_catalog.quote_ident(v_t_op[3]) || ' WHERE recorded_time <= $1::timestamptz AND ' ||
			v_t_op[6]
			USING v_s_time INTO v_m_s_time;

			IF v_m_s_time IS NULL THEN
				v_m_s_time := v_s_time;
			END IF;

			-- Queries for landing pages
			-- SUM(probe_data_column) has been used to aggregate the values. For
			-- example on server page if nummbackends are to be
			-- found then SUM() will be taken after applying group by on
			-- server_id for all databases.
			-- truncate has been used in group by clause because
			-- sometimes data collection has time difference in miliseconds
			v_t_str := 'SELECT MAX(recorded_time) AS rtime, SUM(COALESCE(' ||
				pg_catalog.quote_ident(v_t_op[4]) ||
				'::numeric, 0::numeric)) AS mval FROM pemhistory.' ||
				pg_catalog.quote_ident(v_t_op[3]) ||
				' WHERE recorded_time >= $1::timestamptz AND recorded_time <= $2::timestamptz AND ' ||
				v_t_op[6] || ' GROUP BY date_trunc(''second'', recorded_time), ' ||
				v_t_op[7] || ' ORDER BY rtime';

			OPEN v_m_raw_cur FOR EXECUTE v_t_str USING v_m_s_time, v_t_time;
			FETCH v_m_raw_cur INTO v_m_curr_rec;

			IF FOUND THEN
				FETCH v_m_raw_cur INTO v_m_next_rec;

				v_ttime := ARRAY[]::numeric[];
				v_tvals := ARRAY[]::numeric[];
				o_aggval := v_m_curr_rec.mval;
				v_cnt := 0;
				v_xa := 0;
				v_ya := 0;
				v_tmpx := 0;
				v_tmpy := 0;
				v_ma := 0;
				v_mb := 0;
				v_xx := 0;
				v_xy := 0;

				IF v_t_op[5] = 'F' THEN
					v_t_str := 'SELECT COALESCE(($1::numeric[])[1], 0)';
				ELSIF v_t_op[5] = 'M' THEN
					v_t_str := 'SELECT COALESCE(max(d), 0) FROM unnest($1::numeric[]) d';
				ELSIF v_t_op[5] = 'm' THEN
					v_t_str := 'SELECT COALESCE(min(d), 0) FROM unnest($1::numeric[]) d';
				ELSE
					v_t_str := 'SELECT COALESCE(avg(d), 0) FROM unnest($1::numeric[]) d';
				END IF;

				FOR v_m_new_rec IN
					EXECUTE 'SELECT ts AS rtime FROM generate_series($1::timestamptz, $2::timestamptz, $3::interval) ts'
					USING v_s_time, v_t_time, v_aggspan
				LOOP
					IF (v_m_curr_rec.rtime IS NOT NULL
						AND v_m_curr_rec.rtime <= v_m_new_rec.rtime
						AND v_m_next_rec IS NOT NULL
						AND v_m_new_rec.rtime >= v_m_next_rec.rtime) THEN

						v_aggarr := ARRAY[]::numeric[];
						-- Find the next value for the time, which is closest to the
						-- next expected time
						WHILE v_m_next_rec IS NOT NULL AND
							v_m_new_rec.rtime >= v_m_next_rec.rtime
						LOOP
							v_aggarr := v_aggarr || v_m_next_rec.mval;
							v_m_curr_rec := v_m_next_rec;
							FETCH v_m_raw_cur INTO v_m_next_rec;
						END LOOP;
						o_aggtime := v_m_new_rec.rtime;
						EXECUTE v_t_str INTO o_aggval USING v_aggarr;

						SELECT EXTRACT(EPOCH FROM v_m_new_rec.rtime - v_s_time) INTO v_tmpx;
						v_ttime := v_ttime || v_tmpx;
						v_tvals := v_tvals || o_aggval;
						v_xa := v_xa + v_tmpx;
						v_ya := v_ya + o_aggval;
						v_cnt := v_cnt + 1;

						o_aggval := v_aggarr[array_length(v_aggarr, 1)];
						CONTINUE;
					END IF;

					-- caculating xa = sum_of(time - start_time)
					--			ya = sum_of(value)
					IF v_m_curr_rec.rtime <= v_m_new_rec.rtime THEN
						SELECT EXTRACT(EPOCH FROM v_m_new_rec.rtime - v_s_time) INTO v_tmpx;
						v_ttime := v_ttime || v_tmpx;
						v_tvals := v_tvals || o_aggval;
						v_xa := v_xa + v_tmpx;
						v_ya := v_ya + o_aggval;
						v_cnt := v_cnt + 1;
					END IF;
				END LOOP;

				-- we cannot extrapolate data with just 1 point
				IF v_cnt >= 2 THEN
					-- get mean
					v_xa := v_xa / v_cnt;
					v_ya := v_ya / v_cnt;

					-- compute values to get values of a & b for linear equation which is (y = a + bx)
					-- where a = intercept & b = slope
					-- b = sum_of((x(i) - xa) * (y(i) - ya)) / sum_of((x(i) - xa)^2)
					-- a = ya - (b * xa)
					-- refer http://en.wikipedia.org/wiki/Regression_analysis#Linear_regression
					-- for understanding the formula
					FOR i IN 1 .. v_cnt
					LOOP
						v_tmpx := v_ttime[i] - v_xa;
						IF (v_tvals[i] IS NULL) THEN
							v_tmpy := 0 - v_ya;
						ELSE
							v_tmpy := v_tvals[i] - v_ya;
						END IF;
						v_xx := v_xx + (v_tmpx * v_tmpx);
						v_xy := v_xy + (v_tmpx * v_tmpy);
					END LOOP;

					-- if slope is 0 then there is no graph may get divide by 0 error
					IF (abs(v_xx) <> 0) THEN
						-- get a & b value
						v_mb = v_xy / v_xx;
						v_ma = v_ya - (v_mb * v_xa);

						-- Do we need to calculate the timeline for extrapolated data?
						IF (v_e_op = 'FALLS_BELOW' AND v_tvals[v_cnt] > v_e_val) OR
							(v_e_op = 'EXCEEDS' AND v_tvals[v_cnt] < v_e_val) THEN

							-- Let's calculate the value at maximum time period
							SELECT EXTRACT(EPOCH FROM (v_e_time + '5 years'::interval) - v_s_time)::numeric INTO v_tmpx;
							v_tmpy = v_ma + (v_mb * v_tmpx);

							IF v_tmpy < 0 THEN
								IF v_e_op = 'FALLS_BELOW' THEN
									v_tmpx := (v_e_val - v_ma) / v_mb;
									v_e_time := v_s_time + ((v_tmpx) * INTERVAL '1 second');
								ELSE
									v_tmpx := (0 - v_ma) / v_mb;
									v_e_time := v_s_time + ((v_tmpx) * INTERVAL '1 second');
								END IF;
							ELSE
								IF v_e_op = 'EXCEEDS' THEN
									IF v_tmpy > v_e_val THEN
										v_tmpx := (v_e_val - v_ma) / v_mb;
										v_e_time := v_s_time + (v_tmpx * INTERVAL '1 second');
									ELSE
										v_e_time := v_e_time + '5 years'::interval;
									END IF;
								ELSE
									IF v_tmpy < v_e_val THEN
										v_tmpx := (v_e_val - v_ma) / v_mb;
										v_e_time := v_s_time + (v_tmpx * INTERVAL '1 second');
									ELSE
										v_e_time := v_e_time + '5 years'::interval;
									END IF;
								END IF;
							END IF;
						END IF;

						v_aggspan := ((v_e_time - v_s_time) / (v_maxpoints))::interval;
						IF v_minspan > v_aggspan THEN
							v_aggspan := v_minspan;
						END IF;

					END IF;
				END IF;
				v_ttime := NULL;
				v_tvals := NULL;

				MOVE BACKWARD ALL IN v_m_raw_cur;
				FETCH v_m_raw_cur INTO v_m_curr_rec;
				FETCH v_m_raw_cur INTO v_m_next_rec;
				o_aggval := v_m_curr_rec.mval;

				FOR v_m_new_rec IN
					EXECUTE 'SELECT ts AS rtime FROM generate_series($1::timestamptz, $2::timestamptz, $3::interval) ts'
					USING v_s_time, v_t_time, v_aggspan
				LOOP
					IF (v_m_curr_rec.rtime IS NOT NULL
						AND v_m_curr_rec.rtime <= v_m_new_rec.rtime
						AND v_m_next_rec IS NOT NULL
						AND v_m_new_rec.rtime >= v_m_next_rec.rtime) THEN
						v_aggarr := ARRAY[]::numeric[];
						-- Find the next value for the time, which is closest to the
						-- next expected time
						WHILE v_m_next_rec IS NOT NULL AND
							v_m_new_rec.rtime >= v_m_next_rec.rtime
						LOOP
							v_aggarr := v_aggarr || v_m_next_rec.mval;
							v_m_curr_rec := v_m_next_rec;
							FETCH v_m_raw_cur INTO v_m_next_rec;
						END LOOP;
						o_aggtime := v_m_new_rec.rtime;
						EXECUTE v_t_str INTO o_aggval USING v_aggarr;
						RETURN NEXT;

						o_aggval := v_aggarr[array_length(v_aggarr, 1)];
						CONTINUE;
					END IF;
					IF v_m_curr_rec.rtime <= v_m_new_rec.rtime THEN
						o_aggtime := v_m_new_rec.rtime;

						RETURN NEXT;
					END IF;
				END LOOP;

			END IF;
			CLOSE v_m_raw_cur;

			IF v_t_op[8]::boolean = TRUE THEN
				<<lbl_perc_agg_calculation>>
				LOOP
					o_aggtime := o_aggtime + v_aggspan;
					EXIT lbl_perc_agg_calculation WHEN o_aggtime > v_e_time;

					SELECT v_ma + (EXTRACT(EPOCH FROM (o_aggtime - v_s_time))::numeric * v_mb) INTO o_aggval;

					EXIT lbl_perc_agg_calculation WHEN o_aggval < 0;

					IF o_aggval > 100 THEN
						o_aggval := 100;
					END IF;

					RETURN NEXT;
				END LOOP lbl_perc_agg_calculation;
			ELSE
				<<lbl_agg_calculation>>
				LOOP
					o_aggtime := o_aggtime + v_aggspan;
					EXIT lbl_agg_calculation WHEN o_aggtime > v_e_time;

					SELECT v_ma + (EXTRACT(EPOCH FROM (o_aggtime - v_s_time))::numeric * v_mb) INTO o_aggval;
					EXIT lbl_agg_calculation WHEN o_aggval < 0;

					RETURN NEXT;
				END LOOP lbl_agg_calculation;
			END IF;
		END IF;
	END IF;

	IF array_length(v_m_ops, 1) = 0 THEN
		RETURN;
	END IF;

	-- We need to create the slop for generating the extrapolated data
	IF (p_stime IS NULL OR p_etime IS NULL) AND v_t_time != v_e_time THEN

		FOR v_pos IN array_lower(v_m_ops, 1) .. array_upper(v_m_ops, 1)
		LOOP
			o_idx := v_m_ops[v_pos][1];
			o_label := v_m_ops[v_pos][2];

			-- calculate end-time
			-- Get the time when probe started collecting the data
			EXECUTE
			'SELECT COALESCE(MAX(recorded_time), NULL::timestamptz) AS recorded_time FROM pemhistory.' ||
			pg_catalog.quote_ident(v_m_ops[v_pos][3]) || ' WHERE recorded_time <= $1::timestamptz AND ' ||
			v_m_ops[v_pos][6]
			USING v_s_time INTO v_m_s_time;

			IF v_m_s_time IS NULL THEN
				v_m_s_time := v_s_time;
			END IF;

			-- Queries for landing pages
			-- SUM(probe_data_column) has been used to aggregate the values. For
			-- example on server page if nummbackends are to be
			-- found then SUM() will be taken after applying group by on
			-- server_id for all databases.
			-- truncate has been used in group by clause because
			-- sometimes data collection has time difference in miliseconds
			v_t_str := 'SELECT MAX(recorded_time) AS rtime, SUM(COALESCE(' ||
				pg_catalog.quote_ident(v_m_ops[v_pos][4]) ||
				'::numeric, 0::numeric)) AS mval FROM pemhistory.' ||
				pg_catalog.quote_ident(v_m_ops[v_pos][3]) ||
				' WHERE recorded_time >= $1::timestamptz AND recorded_time <= $2::timestamptz AND ' ||
				v_m_ops[v_pos][6] || ' GROUP BY date_trunc(''second'', recorded_time), ' ||
				v_m_ops[v_pos][7] || ' ORDER BY rtime';

			OPEN v_m_raw_cur FOR EXECUTE v_t_str USING v_m_s_time, v_t_time;
			FETCH v_m_raw_cur INTO v_m_curr_rec;

			IF NOT FOUND THEN
			    CLOSE v_m_raw_cur;
				CONTINUE;
			END IF;
			FETCH v_m_raw_cur INTO v_m_next_rec;

			v_ttime := ARRAY[]::numeric[];
			v_tvals := ARRAY[]::numeric[];
			o_aggval := v_m_curr_rec.mval;
			v_cnt := 0;
			v_xa := 0;
			v_ya := 0;
			v_tmpx := 0;
			v_tmpy := 0;
			v_ma := 0;
			v_mb := 0;
			v_xx := 0;
			v_xy := 0;

			IF v_m_ops[v_pos][5] = 'F' THEN
				v_t_str := 'SELECT COALESCE(($1::numeric[])[1], 0)';
			ELSIF v_m_ops[v_pos][5] = 'M' THEN
				v_t_str := 'SELECT COALESCE(max(d), 0) FROM unnest($1::numeric[]) d';
			ELSIF v_m_ops[v_pos][5] = 'm' THEN
				v_t_str := 'SELECT COALESCE(min(d), 0) FROM unnest($1::numeric[]) d';
			ELSE
				v_t_str := 'SELECT COALESCE(avg(d), 0) FROM unnest($1::numeric[]) d';
			END IF;

			FOR v_m_new_rec IN
				EXECUTE 'SELECT ts AS rtime FROM generate_series($1::timestamptz, $2::timestamptz, $3::interval) ts'
				USING v_s_time, v_t_time, v_aggspan
			LOOP
				IF (v_m_curr_rec.rtime IS NOT NULL
					AND v_m_curr_rec.rtime <= v_m_new_rec.rtime
					AND v_m_next_rec IS NOT NULL
					AND v_m_new_rec.rtime >= v_m_next_rec.rtime) THEN
					v_aggarr := ARRAY[]::numeric[];
					-- Find the next value for the time, which is closest to the
					-- next expected time
					WHILE v_m_next_rec IS NOT NULL AND
						v_m_new_rec.rtime > v_m_next_rec.rtime
					LOOP
						v_aggarr := v_aggarr || v_m_next_rec.mval;
						v_m_curr_rec := v_m_next_rec;
						FETCH v_m_raw_cur INTO v_m_next_rec;
					END LOOP;
					o_aggtime := v_m_new_rec.rtime;
					EXECUTE v_t_str INTO o_aggval USING v_aggarr;

					SELECT EXTRACT(EPOCH FROM o_aggtime - v_s_time) INTO v_tmpx;
					v_ttime := v_ttime || v_tmpx;
					v_tvals := v_tvals || o_aggval;
					v_xa := v_xa + v_tmpx;
					v_ya := v_ya + o_aggval;
					v_cnt := v_cnt + 1;

					o_aggval := v_aggarr[array_length(v_aggarr, 1)];
					CONTINUE;
				END IF;
				-- caculating xa = sum_of(time - start_time)
				--			ya = sum_of(value)
				IF v_m_curr_rec.rtime <= v_m_new_rec.rtime THEN
					o_aggtime := v_m_new_rec.rtime;
					SELECT EXTRACT(EPOCH FROM o_aggtime - v_s_time) INTO v_tmpx;
					v_ttime := v_ttime || v_tmpx;
					v_tvals := v_tvals || o_aggval;
					v_xa := v_xa + v_tmpx;
					v_ya := v_ya + o_aggval;
					v_cnt := v_cnt + 1;

					RETURN NEXT;
				END IF;
			END LOOP;
			CLOSE v_m_raw_cur;

			-- we cannot extrapolate data with just 1 point
			IF v_cnt >= 2 THEN
				-- get mean
				v_xa := v_xa / v_cnt;
				v_ya := v_ya / v_cnt;

				-- compute values to get values of a & b for linear equation which is (y = a + bx)
				-- where a = intercept & b = slope
				-- b = sum_of((x(i) - xa) * (y(i) - ya)) / sum_of((x(i) - xa)^2)
				-- a = ya - (b * xa)
				-- refer http://en.wikipedia.org/wiki/Regression_analysis#Linear_regression
				-- for understanding the formula
				FOR i IN 1 .. v_cnt
				LOOP
					v_tmpx := v_ttime[i] - v_xa;
					IF (v_tvals[i] IS NULL) THEN
						v_tmpy := 0 - v_ya;
					ELSE
						v_tmpy := v_tvals[i] - v_ya;
					END IF;
					v_xx := v_xx + (v_tmpx * v_tmpx);
					v_xy := v_xy + (v_tmpx * v_tmpy);
				END LOOP;

				-- if slope is 0 then there is no graph may get divide by 0 error
				IF (abs(v_xx) <> 0) THEN
					-- get a & b value
					v_mb = v_xy / v_xx;
					v_ma = v_ya - (v_mb * v_xa);

					IF v_m_ops[v_pos][8]::boolean = TRUE THEN
						<<lbl_perc_agg_calculation>>
						LOOP
							o_aggtime := o_aggtime + v_aggspan;
							EXIT lbl_perc_agg_calculation WHEN o_aggtime > v_e_time;

							SELECT v_ma + (EXTRACT(EPOCH FROM (o_aggtime - v_s_time))::numeric * v_mb) INTO o_aggval;

							EXIT lbl_perc_agg_calculation WHEN o_aggval < 0;

							IF o_aggval > 100 THEN
								o_aggval := 100;
							END IF;
							RETURN NEXT;
						END LOOP lbl_perc_agg_calculation;
					ELSE
						<<lbl_agg_calculation>>
						LOOP
							o_aggtime := o_aggtime + v_aggspan;
							EXIT lbl_agg_calculation WHEN o_aggtime > v_e_time;
							SELECT v_ma + (EXTRACT(EPOCH FROM (o_aggtime - v_s_time))::numeric * v_mb) INTO o_aggval;

							EXIT lbl_agg_calculation WHEN o_aggval < 0;

							RETURN NEXT;
						END LOOP lbl_agg_calculation;
					END IF;

				END IF;
			END IF;
			v_ttime := NULL;
			v_tvals := NULL;

		END LOOP;
		o_idx := -1;
		o_label := NULL;
		o_aggtime := v_t_time;
		o_aggval := NULL;

		RETURN NEXT;
	ELSE
		FOR v_pos IN array_lower(v_m_ops, 1) .. array_upper(v_m_ops, 1)
		LOOP
			-- pos, label, probe_tbl, probe_col, agg, condition, groupon
			-- TABLE(o_idx int2, o_label text, o_aggtime timestamptz, o_aggval numeric)

			o_idx := v_m_ops[v_pos][1];
			o_label := v_m_ops[v_pos][2];

			-- Get the time when probe started collecting the data
			EXECUTE
			'SELECT COALESCE(MAX(recorded_time), NULL::timestamptz) AS recorded_time FROM pemhistory.' ||
			pg_catalog.quote_ident(v_m_ops[v_pos][3]) || ' WHERE recorded_time <= $1::timestamptz AND ' ||
			v_m_ops[v_pos][6]
			USING v_s_time INTO v_m_s_time;

			IF v_m_s_time IS NULL THEN
				v_m_s_time := v_s_time;
			END IF;
			-- Queries for landing pages
			-- SUM(probe_data_column) has been used to aggregate the values. For
			-- example on server page if nummbackends are to be
			-- found then SUM() will be taken after applying group by on
			-- server_id for all databases.
			-- truncate has been used in group by clause because
			-- sometimes data collection has time difference in miliseconds
			v_t_str := 'SELECT MAX(recorded_time) AS rtime, SUM(COALESCE(' ||
				pg_catalog.quote_ident(v_m_ops[v_pos][4]) ||
				'::numeric, 0::numeric)) AS mval FROM pemhistory.' ||
				pg_catalog.quote_ident(v_m_ops[v_pos][3]) ||
				' WHERE recorded_time >= $1::timestamptz AND recorded_time <= $2::timestamptz AND ' ||
				v_m_ops[v_pos][6] || ' GROUP BY date_trunc(''second'', recorded_time), ' ||
				v_m_ops[v_pos][7] || ' ORDER BY rtime';

			OPEN v_m_raw_cur FOR EXECUTE v_t_str USING v_m_s_time, v_t_time;

			IF v_m_ops[v_pos][5] = 'F' THEN
				v_t_str := 'SELECT COALESCE(($1::numeric[])[1], 0)';
			ELSIF v_m_ops[v_pos][5] = 'M' THEN
				v_t_str := 'SELECT COALESCE(max(d), 0) FROM unnest($1::numeric[]) d';
			ELSIF v_m_ops[v_pos][5] = 'm' THEN
				v_t_str := 'SELECT COALESCE(min(d), 0) FROM unnest($1::numeric[]) d';
			ELSE
				v_t_str := 'SELECT COALESCE(avg(d), 0) FROM unnest($1::numeric[]) d';
			END IF;

			FETCH v_m_raw_cur INTO v_m_curr_rec;
			IF NOT FOUND THEN
				CLOSE v_m_raw_cur;
				CONTINUE;
			END IF;
			FETCH v_m_raw_cur INTO v_m_next_rec;
			o_aggval := v_m_curr_rec.mval;

			FOR v_m_new_rec IN
				EXECUTE 'SELECT ts AS rtime FROM generate_series($1::timestamptz, $2::timestamptz, $3::interval) ts'
				USING v_s_time, v_t_time, v_aggspan
			LOOP
				IF (v_m_curr_rec.rtime IS NOT NULL
					AND v_m_curr_rec.rtime <= v_m_new_rec.rtime
					AND v_m_next_rec IS NOT NULL
					AND v_m_new_rec.rtime >= v_m_next_rec.rtime) THEN

					v_aggarr := ARRAY[]::numeric[];
					-- Find the next value for the time, which is closest to the
					-- next expected time
					WHILE v_m_next_rec IS NOT NULL AND
						v_m_new_rec.rtime >= v_m_next_rec.rtime
					LOOP
						v_aggarr := v_aggarr || v_m_next_rec.mval;
						v_m_curr_rec := v_m_next_rec;
						FETCH v_m_raw_cur INTO v_m_next_rec;
					END LOOP;
					o_aggtime := v_m_new_rec.rtime;
					EXECUTE v_t_str INTO o_aggval USING v_aggarr;
					RETURN NEXT;

					o_aggval := v_aggarr[array_length(v_aggarr, 1)];
					CONTINUE;
				END IF;
				IF v_m_curr_rec.rtime <= v_m_new_rec.rtime THEN
					o_aggtime := v_m_new_rec.rtime;

					RETURN NEXT;
				END IF;
			END LOOP;

			CLOSE v_m_raw_cur;

		END LOOP;
	END IF;
END
$$ LANGUAGE 'plpgsql';

COMMIT TRANSACTION;
