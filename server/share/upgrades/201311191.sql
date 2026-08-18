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

-- Upgrade script for v4.0.0 GA to v4.0.1 GA

BEGIN TRANSACTION;

-- Update the schema version
CREATE OR REPLACE FUNCTION pem.schema_version()
  RETURNS integer AS
'SELECT 201311191::integer;'
  LANGUAGE 'sql' IMMUTABLE;
COMMENT ON FUNCTION pem.schema_version() IS 'Returns the version number of the PEM schema';

--Fixing #31841 in PEM 4.0.1.
--
UPDATE pem.chart SET params = ARRAY['sort_index', 'sort_direction'] WHERE id IN(2, 3, 4);

-- Fix for RM 23188.
--
DELETE from pem.config where param='chart_disable_bullets';

-- Fix for RM 31745. PEM capacity Manager giving error insufficient data.
--

-- This function executes the linear trend analysis on a given set of data to predict
-- the trend in the future between the given start time and end time or the cut-off
-- threshold values based on the linear regression model
CREATE OR REPLACE FUNCTION pem.linear_trend_analysis (probe_table text,
							aggregate_function text,
							probe_data_column text,
							start_time timestamp with time zone,
							end_time timestamp with time zone,
							cur_time timestamp with time zone,
							time_interval interval,
							required_points int,
							probe_target_key_list varchar[],
							probe_target_value_list varchar[],
							cutoff_count int,
							agent_id int)
RETURNS TABLE (trend_metric_time timestamp with time zone, trend_metric_value numeric)
AS $$
DECLARE
	data_timestamp timestamptz[];
	data_value numeric[];
	i int :=0;
	count int := 0;
	xa numeric := 0;
	ya numeric := 0;
	xx numeric := 0;
	xy numeric := 0;
	ma numeric := 0;
	mb numeric := 0;
	start_epoch numeric;
	end_epoch1 numeric;
	end_epoch2 numeric;
	tmpx numeric;
	tmpy numeric;
	tmpt numeric;
	tmp_val numeric;
	tmp_et1 numeric;
	tmp_row RECORD;
	tmp_time timestamp with time zone;
	percent_unit boolean;
BEGIN
	-- check if unit of metric is of type % or not. if it is then the metric bound at extrapolation should never cross 100.
	EXECUTE 'SELECT (CASE WHEN unit_of_value = ''%'' THEN true ELSE false END) FROM pem.probe_column WHERE probe_id=(SELECT id FROM pem.probe WHERE internal_name='
	|| pg_catalog.quote_literal(probe_table) || ') AND internal_name=' || pg_catalog.quote_literal (probe_data_column) INTO percent_unit;

	-- get current time and unix epoch for comparison sake
	SELECT EXTRACT(EPOCH FROM start_time) INTO start_epoch;
	SELECT EXTRACT(EPOCH FROM cur_time) INTO end_epoch1;
	SELECT EXTRACT(EPOCH FROM end_time) INTO end_epoch2;
	IF (end_epoch2 <= end_epoch1) THEN
		cur_time = end_time;
	END IF;

	-- get data till current time from start time from data rollup function & calculate mean of value & time interval
	-- caculating xa = sum_of(time - start_time)
	--            ya = sum_of(value)
	-- these values are returned by data_reconstruction function for given start_time to end_time
	FOR tmp_row IN SELECT metric_time, recorded_value FROM pem.data_reconstruction (probe_table, probe_data_column,
		start_time, cur_time, time_interval, probe_target_key_list, probe_target_value_list, agent_id, true)
	LOOP
		IF (NOT tmp_row.recorded_value IS NULL) THEN
			data_timestamp[count] = tmp_row.metric_time;
			data_value[count] = tmp_row.recorded_value;
			SELECT EXTRACT(EPOCH FROM tmp_row.metric_time) INTO tmpt;
			xa = xa + (tmpt - start_epoch);
			ya = ya + tmp_row.recorded_value;
			count = count + 1;
		END IF;
	END LOOP;

	-- if there is no data then just bail out with error
	IF (count = 0) THEN
		RAISE EXCEPTION '1';
		RETURN;
	END IF;

	-- apply linear trend algorithm to extrapolate the data if the end time
	-- is greater than the current time, else return the currently collected
	-- data.
	IF (end_epoch2 <= end_epoch1) THEN
		IF cutoff_count != 0 THEN
			IF cutoff_count < count THEN
				count = cutoff_count;
			END IF;
		END IF;
	ELSE
		-- we cannot extrapolate data with just 1 point
		IF (count < 2) THEN
			RAISE EXCEPTION '1';
			RETURN;
		END IF;

		-- get mean
		xa = xa / count;
		ya = ya / count;

		-- compute values to get values of a & b for linear equation which is (y = a + bx)
		-- where a = intercept & b = slope
		-- b = sum_of((x(i) - xa) * (y(i) - ya)) / sum_of((x(i) - xa)^2)
		-- a = ya - (b * xa)
		-- refer http://en.wikipedia.org/wiki/Regression_analysis#Linear_regression
		-- for understanding the formula
		FOR i IN 0..(count - 1)
		LOOP
			SELECT EXTRACT(EPOCH FROM data_timestamp[i]) INTO tmpt;
			tmpx = (tmpt - start_epoch) - xa;
			IF (data_value[i] IS NULL) THEN
				tmpy = 0 - ya;
			ELSE
				tmpy = data_value[i] - ya;
			END IF;
			xx = xx + (tmpx * tmpx);
			xy = xy + (tmpx * tmpy);
		END LOOP;

		-- if slope is 0 then there is no graph may get divide by 0 error
		IF (abs(xx) = 0) THEN
			RAISE EXCEPTION '2';
			RETURN;
		END IF;

		-- get a & b value
		mb = xy / xx;
		ma = ya - (mb * xa);

		tmp_time = data_timestamp[count - 1];
		SELECT EXTRACT (EPOCH FROM tmp_time) INTO tmp_et1;
		WHILE tmp_et1 < end_epoch2
		LOOP
			tmp_time = tmp_time + time_interval;
			tmpt = (SELECT EXTRACT( EPOCH FROM tmp_time)) - start_epoch;
			tmp_val = ma + (mb * tmpt);
			IF tmp_val < 0 THEN
				data_value[count] = NULL;
			ELSE
				IF percent_unit = TRUE AND tmp_val > 100 THEN
					data_value[count] = 100;
				ELSE
					data_value[count] = tmp_val;
				END IF;
			END IF;
			data_timestamp[count] = tmp_time;
			count = count + 1;
			IF (cutoff_count != 0) THEN
				-- exit if cut off point is reached
				EXIT WHEN count >= cutoff_count;
			END IF;
			SELECT EXTRACT (EPOCH FROM tmp_time) INTO tmp_et1;
		END LOOP;
	END IF;

	RETURN QUERY EXECUTE 'SELECT agg_time AS trend_metric_time, agg_value AS trend_metric_value FROM pem.data_aggregation(' ||
			pg_catalog.quote_literal(aggregate_function) || '::text,' || pg_catalog.quote_literal(data_timestamp::text) || '::timestamptz[],' ||
			pg_catalog.quote_literal(data_value::text) || '::numeric[],' || pg_catalog.quote_literal(count::text) || '::int,' ||
			pg_catalog.quote_literal(required_points::text) || ')';
END
$$ LANGUAGE plpgsql;

-- This function returns the cut-off count for a given metric for when its value
-- will either exceed or falls below the given threhold when we apply the linear
-- regression model to it.
CREATE OR REPLACE FUNCTION pem.linear_trend_threshold (probe_table text,
							probe_data_column text,
							start_time timestamp with time zone,
							cur_time timestamp with time zone,
							threshold numeric,
							exceeds_opr boolean,
							time_interval interval,
							probe_target_key_list varchar[],
							probe_target_value_list varchar[],
							max_end_time_in_years int,
							agent_id int)
RETURNS int
AS $$
DECLARE
	data_timestamp timestamptz[];
	data_value numeric[];
	count int := 0;
	i int :=0;
	final_end_time timestamp with time zone;
	xa numeric := 0;
	ya numeric := 0;
	xx numeric := 0;
	xy numeric := 0;
	ma numeric := 0;
	mb numeric := 0;
	start_epoch numeric;
	end_epoch numeric;
	tmp_et numeric;
	tmpx numeric;
	tmpy numeric;
	tmpt numeric;
	tmp_last_time timestamp with time zone;
	tmp_row RECORD;
	percent_unit boolean;
BEGIN
	-- check if unit of metric is of type % or not. if it is then the metric bound at extrapolation should never cross 100.
	EXECUTE 'SELECT (CASE WHEN unit_of_value = ''%'' THEN true ELSE false END) FROM pem.probe_column WHERE probe_id=(SELECT id FROM pem.probe WHERE internal_name='
	|| pg_catalog.quote_literal(probe_table) || ') AND internal_name=' || pg_catalog.quote_literal (probe_data_column) INTO percent_unit;

	IF percent_unit = TRUE AND threshold > 100 THEN
		threshold = 100;
	END IF;

	-- get current time and final time is which is (x) years in future
	SELECT cur_time + (max_end_time_in_years * '1 year'::interval) INTO final_end_time;

	-- get unix epoch for comparison sake
	SELECT EXTRACT(EPOCH FROM start_time) INTO start_epoch;
	SELECT EXTRACT(EPOCH FROM final_end_time) INTO end_epoch;

	-- get data till current time from start time from data rollup function & calculate mean of value & time interval
	-- caculating xa = sum_of(time - start_time)
	--            ya = sum_of(value)
	-- these values are returned by data_rollup function for given start_time to end_time
	FOR tmp_row IN SELECT metric_time, recorded_value FROM pem.data_reconstruction (probe_table, probe_data_column,
		start_time, cur_time, time_interval, probe_target_key_list, probe_target_value_list, agent_id, true)
	LOOP
		IF (NOT tmp_row.recorded_value IS NULL) THEN
			data_timestamp[count] = tmp_row.metric_time;
			data_value[count] = tmp_row.recorded_value;
			SELECT EXTRACT(EPOCH FROM tmp_row.metric_time) INTO tmpt;
			xa = xa + (tmpt - start_epoch);
			ya = ya + tmp_row.recorded_value;
			count = count + 1;
		END IF;
	END LOOP;

	-- we cannot extrapolate data with just 1 point
	IF (count < 2) THEN
		RAISE EXCEPTION '1';
	END IF;

	-- get mean
	xa = xa / count;
	ya = ya / count;

	-- compute values to get values of a & b for linear equation which is (y = a + bx)
	-- where a = intercept & b = slope
	-- b = sum_of((x(i) - xa) * (y(i) - ya)) / sum_of((x(i) - xa)^2)
	-- a = ya - (b * xa)
	-- refer http://en.wikipedia.org/wiki/Regression_analysis#Linear_regression
	-- for understanding the formula
	FOR i IN 0..(count - 1)
	LOOP
		SELECT EXTRACT(EPOCH FROM data_timestamp[i]) INTO tmpt;
		tmpx = (tmpt - start_epoch) - xa;
		IF (data_value[i] IS NULL) THEN
			tmpy = 0 - ya;
		ELSE
			tmpy = data_value[i] - ya;
		END IF;
		xx = xx + (tmpx * tmpx);
		xy = xy + (tmpx * tmpy);
	END LOOP;

	-- if slope is 0 then there is no graph may get divide by 0 error
	IF (abs(xx) = 0) THEN
		RAISE EXCEPTION '2';
	END IF;

	-- get a & b value
	mb = xy / xx;
	ma = ya - (mb * xa);

	-- now apply the equation to extrapolated data till you reach the
	-- given threshold or you reach the final end time.
	tmp_last_time = data_timestamp[count - 1];
	SELECT EXTRACT (EPOCH FROM tmp_last_time) INTO tmp_et;
	WHILE tmp_et < end_epoch
	LOOP
		tmp_last_time = tmp_last_time + time_interval;
		tmpt = (SELECT EXTRACT( EPOCH FROM tmp_last_time)) - start_epoch;
		tmpy = ma + (mb * tmpt);
		count = count + 1;

		IF (tmpy < 0) THEN
			RETURN count;
		END IF;

		IF (exceeds_opr = TRUE) THEN
			IF (tmpy > threshold) THEN
				RETURN count-1;
			END IF;
		ELSE
			IF (tmpy < threshold) THEN
				RETURN count-1;
			END IF;
		END IF;
		SELECT EXTRACT (EPOCH FROM tmp_last_time) INTO tmp_et;
	END LOOP;

	RETURN count-1;
END
$$ LANGUAGE plpgsql;

-- Fix for RM 32192

CREATE OR REPLACE FUNCTION pem.generate_metric_chart_data(
	cid integer, aid integer, sid integer, db text, schema text,
	level integer, show_system_objects boolean, is_capacity_manager boolean=false)
RETURNS TABLE(idx int2, label text, agg_time timestamptz, agg_val numeric)
AS $$
DECLARE
	chart_exists        boolean := false;
	start_time          timestamptz := NULL;
	end_time            timestamptz := NULL;
	max_points          integer;
	curs                refcursor;
	mcurs               refcursor;
	gcurs               refcursor;
	metric              pem.chart_metric%ROWTYPE;
	chart               pem.chart%ROWTYPE;
	probe_id            int4;
	probe_target_type   integer;
	probe_applies_to_id integer;
	probe_keys          text[];
	probe_key_vals      text[];
	metric_restrict_dbs text[];
	restricted_dbs      text[];
	restricted_schemas  text[];
	pos                 int2 := 0;
	query               text;
	tmp_str             text;
	_params             text[];
	_vals               text[];
	params              text[];
	vals                text[];
	agg_int             integer;
	metric_label        text := NULL;
	probe_type          text := NULL;
	chart_span          text := NULL;
BEGIN
	-- Check if the data for the chart exists in the pem.metrices_chart
	EXECUTE 'SELECT CASE WHEN count(*) > 0 THEN true ELSE false END FROM pem.metrices_chart WHERE cid = $1::int4'
	INTO chart_exists USING cid;

	IF NOT chart_exists OR chart_exists IS NULL THEN
		RAISE EXCEPTION '101';
	END IF;

	EXECUTE 'SELECT value||'' ''||unit FROM pem.config WHERE param = (SELECT rwlimit_span_param FROM pem.chart WHERE id = $1::int4)'
	INTO chart_span USING cid;

	-- Fetch the start time, end time, maximum points & aggregation intervals
	IF chart_span IS NOT NULL AND trim(chart_span) != '' THEN
	EXECUTE 'SELECT now() - '''||chart_span||'''::interval, now(), max_points, agg_int FROM pem.metrices_chart WHERE cid = $1::int4'
	INTO start_time, end_time, max_points, agg_int USING cid;
	END IF;

	IF start_time IS NULL THEN
	EXECUTE 'SELECT now() -  time_span, now(), max_points, agg_int FROM pem.metrices_chart WHERE cid = $1::int4'
	INTO start_time, end_time, max_points, agg_int USING cid;
	END IF;

	-- Couldn't fetch the time_span/max_points from the pem.metrices_chart table
	IF start_time IS NULL THEN
		RAISE EXCEPTION '102';
	END IF;

	CASE
	WHEN level = 100 THEN
		-- On agent level dash, agent-id must exists
		IF aid IS NULL OR aid <= 0 THEN
			RAISE EXCEPTION '103';
		END IF;
	WHEN level >= 200 THEN
		-- On server level dash, server-id must exists
		IF sid IS NULL OR sid <= 0 THEN
			RAISE EXCEPTION '104';
		END IF;

		-- Fetch agent-id, if not provided
		IF aid IS NULL OR aid <= 0 THEN
			aid := NULL;

			EXECUTE 'SELECT agent_id FROM pem.agent_server_binding WHERE server_id = $1::int4' INTO aid USING sid;

			IF aid IS NULL THEN
				RAISE EXCEPTION '105';
			END IF;
		END IF;

		-- Fetch the restricted databases information (only for server level charts)
		IF level = 200 THEN
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
    s.id = $1::int4' INTO restricted_dbs USING sid;
		END IF;

		IF level >= 300 THEN
			-- database_name is required for any charts lower than server
			-- level
			IF db IS NULL OR trim(db) = '' THEN
				RAISE EXCEPTION '106';
			END IF;

			-- Fetch the restricted schema information (for database level chats)
			IF level = 300 THEN
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
    s.id = $1::int4' INTO restricted_schemas USING sid, db;
			END IF;
		END IF;
	ELSE -- DO NOTHING
	END CASE;

	EXECUTE 'SELECT * FROM pem.chart WHERE id = $1::int4' USING cid INTO chart;
	-- Fetch all the metrices for this chart
	OPEN mcurs FOR EXECUTE 'SELECT * FROM pem.chart_metric WHERE cid = $1::int4' USING cid;
	LOOP
		FETCH mcurs INTO metric;
		EXIT WHEN NOT FOUND;

		probe_id := NULL;
		probe_target_type := NULL;
		probe_applies_to_id := NULL;
		probe_keys := NULL;

		-- Fetch target-type, probe-applies-to, primary keys for the involved
		-- probe-table
		EXECUTE
		'SELECT p.id, p.target_type_id, p.applies_to_id, ARRAY(SELECT pc.internal_name FROM pem.probe_column pc WHERE pc.probe_id = p.id AND (($2::int4 = 300 AND pc.internal_name <> ''database_name'') OR ($2::int4 = 400 AND pc.internal_name NOT IN (''database_name'', ''schema_name'')) OR true) AND pc.classification = ''k'' ORDER BY pc.id) AS keys FROM pem.probe p WHERE p.internal_name = $1::text'
		INTO probe_id, probe_target_type, probe_applies_to_id, probe_keys USING metric.tbl, level;

		IF probe_target_type IS NULL THEN
			-- We couldn't find the probe_target_id, it means the probe with
			-- that name does not exists
			RAISE EXCEPTION '107|%', metric.tbl;
		END IF;

		-- We need to find out, if this metric actually generates multiple
		-- sub-metrices (because they may have other primary keys too)
		IF level > 0 AND probe_keys IS NOT NULL AND array_length(probe_keys, 1) <> 0 THEN

			query := 'SELECT ARRAY[';

			SELECT string_agg('tbl.' || pg_catalog.quote_ident(probe_keys[a]), '::text, ')
				FROM generate_series(array_lower(probe_keys,1), array_upper(probe_keys,1)) a INTO tmp_str;
			query := query || tmp_str || '::text]::text[] FROM pemdata.' || pg_catalog.quote_ident(metric.tbl) || ' tbl';

			metric_restrict_dbs = NULL;
			CASE WHEN probe_applies_to_id = 100 THEN
					query := query || ' WHERE tbl.agent_id = ' || aid::text || '::integer';
					_params := ARRAY['agent_id'];
					_vals := ARRAY[aid::text];
				WHEN probe_target_type = 200 THEN
					query := query || ' WHERE tbl.server_id = ' || sid::text || '::integer';
					_params := ARRAY['server_id'];
					_vals := ARRAY[sid::text]::text[];
					IF probe_applies_to_id >= 300 AND level >= 300 THEN
						-- Restricted DBs are availabe that doesn't mean - they're applicable
						-- for this metric
						--
						-- Thye're applicable only if probe can applies to database level and
						-- current dashboard is for server-level
						IF array_length(restricted_dbs, 1) <> 0 THEN
							metric_restrict_dbs = restricted_dbs;
						ELSE
							metric_restrict_dbs := NULL;
						END IF;

						query := query || ' AND tbl.database_name = ' || pg_catalog.quote_literal(db::text) || '::text';
						_params := ARRAY['server_id', 'database_name'];
						_vals := ARRAY[sid::text, db];
					END IF;
					IF probe_applies_to_id >= 400 AND level = 400 THEN
						_params := ARRAY['server_id', 'database_name', 'schema_name'];
						_vals := ARRAY[sid::text, db, schema];
						query := query || ' AND tbl.schema_name = ' || pg_catalog.quote_literal(schema::text) || '::text';
					END IF;
					IF NOT show_system_objects THEN
						IF probe_applies_to_id = 300 THEN
							query := query || ' AND CASE WHEN database_name != '''' THEN database_name != ''template0'' AND database_name != ''template1'' ELSE TRUE END';
						ELSIF probe_applies_to_id > 300 THEN
							query := query || E' AND CASE WHEN database_name != '''' THEN database_name != ''template0'' AND database_name != ''template1'' AND schema_name NOT IN (''pg_catalog'', ''sys'', ''information_schema'') AND schema_name NOT LIKE ''pg_toast%'' AND schema_name NOT LIKE ''pg_temp%'' ELSE TRUE END';

							query := query || ' AND CASE WHEN database_name != '''' THEN database_name != ''template0'' AND database_name != ''template1'' ELSE TRUE END';
						END IF;
					END IF;
					IF probe_applies_to_id = 300 THEN
						IF restricted_dbs IS NOT NULL AND array_length(restricted_dbs, 1) > 0 THEN
							query := query || ' AND database_name = ANY(' || pg_catalog.quote_literal(restricted_dbs::text) || ')';
						END IF;
					ELSIF probe_applies_to_id > 300 THEN
						IF restricted_dbs IS NOT NULL AND array_length(restricted_dbs, 1) > 0 THEN
							query := query || ' AND database_name = ANY(' || pg_catalog.quote_literal(restricted_dbs::text) || ') AND schema_name = ANY(
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
						IF level = 400 THEN
							query := query || ' AND schema_name = ' || pg_catalog.quote_literal(schema::text) || '::text';
						END IF;
					END IF;
				WHEN probe_target_type = 300 THEN
					query := query || ' WHERE tbl.server_id = ' || sid::text || '::integer AND tbl.database_name = ' || pg_catalog.quote_literal(db::text) || '::text';
					_params := ARRAY['server_id', 'database_name'];
					_vals := ARRAY[sid::text, db]::text[];
					IF array_length(restricted_dbs, 1) <> 0 THEN
						metric_restrict_dbs = restricted_dbs;
					ELSE
						metric_restrict_dbs := NULL;
					END IF;
					IF probe_applies_to_id > 300  THEN
						IF level > 300 THEN
							_params := ARRAY['server_id', 'database_name', 'schema_name'];
							_vals := ARRAY[sid::text, db, schema];
						END IF;
						IF NOT show_system_objects THEN
							query := query || E' AND (schema_name NOT IN (''pg_catalog'', ''sys'', ''information_schema'') AND schema_name NOT LIKE ''pg_toast%'' AND schema_name NOT LIKE ''pg_temp%'')';
						END IF;
						IF restricted_schemas IS NOT NULL AND array_length(restricted_schemas, 1) > 0 THEN
							query := query || ' AND schema_name = ANY(' || pg_catalog.quote_literal(restricted_schemas::text) || ')';
						END IF;
					END IF;
				WHEN probe_target_type = 400 THEN
					_params := ARRAY['server_id', 'database_name', 'schema_name'];
					_vals := ARRAY[sid::text, db, schema];
					query := query || ' WHERE tbl.server_id = ' || sid::text || '::integer AND tbl.database_name = ' || pg_catalog.quote_literal(db::text) || '::text AND tbl.schema_name = ' || pg_catalog.quote_literal(schema::text) || '::text';
				ELSE
					query := query;
			END CASE;

			IF metric.gorderby IS NOT NULL AND array_length(metric.gorderby, 1) >0 THEN
				SELECT string_agg('tbl.' || pg_catalog.quote_ident(metric.gorderby[i]), ', ')
					FROM generate_series(array_lower(metric.gorderby,1), array_upper(metric.gorderby,1)) i INTO tmp_str;
				query := query || ' ORDER BY ' || tmp_str;
			END IF;
			IF (metric.glimit IS NOT NULL OR metric.glimit <> 0) THEN
				IF (metric.glimit < 0) THEN
					query := query || ' LIMIT ' || (metric.glimit * -1)::text || ' DESC';
				ELSE
					query := query || ' LIMIT ' || metric.glimit::text;
				END IF;
			END IF;

			IF metric.glimit IS NULL OR metric.glimit <> 0 THEN
				OPEN gcurs FOR EXECUTE query;
				LOOP
					FETCH gcurs INTO probe_key_vals;
					EXIT WHEN NOT FOUND;
					params := _params;
					vals := _vals;

					FOR a IN array_lower(probe_key_vals, 1) .. array_upper(probe_key_vals, 1)
					LOOP
						params := params || probe_keys[a]::text;
						vals := vals || probe_key_vals[a]::text;
					END LOOP;

					FOR m_idx IN array_lower(metric.metrices, 1) .. array_upper(metric.metrices, 1)
					LOOP
						pos := pos + 1;
						SELECT string_agg(probe_key_vals[b], ', ')
							FROM generate_series(array_lower(probe_key_vals,1), array_upper(probe_key_vals,1)) b INTO label;
						EXECUTE '
	SELECT
		(CASE WHEN NOT pit_by_default THEN display_name || ''+'' ELSE display_name END), sql_data_type
	FROM pem.probe_column
	WHERE probe_id = $1::int4 AND internal_name = $2::text AND is_graphable
	UNION ALL
	SELECT
		display_name, sql_data_type
	FROM pem.probe_column
	WHERE probe_id = $1::int4 AND (internal_name || ''_pit'') = $2::text AND is_graphable AND NOT pit_by_default AND calculate_pit'
	USING probe_id, metric.metrices[m_idx] INTO metric_label, probe_type;

						IF chart.labels IS NOT NULL AND array_length(chart.labels, 1) >= pos AND chart.labels[pos] IS NOT NULL THEN
							label := chart.labels[pos] || ' - ' || label;
						ELSE
							IF metric_label IS NOT NULL THEN
								label := metric_label || ' - ' || label;
							END IF;
						END IF;
						query := '
	SELECT
		$1::int2 AS idx, $2::text AS label, aggregated_time, aggregated_value
	FROM pem.data_rollup ($3::text, $4::text, $5::text, $6::timestamptz, $7::timestamptz, $8::interval, $9::integer, $10::text[], $11::text[], $12::integer, $13::boolean, $14::text[])';
						IF metric.agg_func IS NOT NULL AND array_length(metric.agg_func, 1) >= m_idx AND metric.agg_func[m_idx] IS NOT NULL THEN
							tmp_str := metric.agg_func[m_idx];
						END IF;
						CASE
							WHEN tmp_str = 'A' THEN tmp_str := 'avg';
							WHEN tmp_str = 'M' THEN tmp_str := 'max';
							WHEN tmp_str = 'm' THEN tmp_str := 'min';
							WHEN tmp_str = 'F' THEN tmp_str := 'FIRST';
							ELSE tmp_str := 'avg';
						END CASE;

						RETURN QUERY EXECUTE query USING pos, label, metric.tbl, tmp_str, metric.metrices[m_idx], start_time, end_time, agg_int * '1 minute'::interval, max_points, params, vals, aid, is_capacity_manager, metric_restrict_dbs;
					END LOOP;
				END LOOP;
				CLOSE gcurs;
			ELSE
				FOR m_idx IN array_lower(metric.metrices, 1) .. array_upper(metric.metrices, 1)
				LOOP
					pos := pos + 1;
					EXECUTE '
SELECT
	(CASE WHEN NOT pit_by_default THEN display_name || ''+'' ELSE display_name END)
FROM pem.probe_column
WHERE probe_id = $1::int4 AND internal_name = $2::text AND is_graphable
UNION ALL
SELECT
	display_name
FROM pem.probe_column
WHERE probe_id = $1::int4 AND (internal_name || ''_pit'') = $2::text AND is_graphable AND NOT pit_by_default AND calculate_pit'
USING probe_id, metric.metrices[m_idx] INTO metric_label;

					IF chart.labels IS NOT NULL AND array_length(chart.labels, 1) >= pos AND chart.labels[pos] IS NOT NULL THEN
						label := chart.labels[pos];
					ELSE
						IF metric_label IS NOT NULL THEN
							label := metric_label;
						END IF;
					END IF;
					query := '
SELECT
	$1::int2 AS idx, $2::text AS label, aggregated_time, aggregated_value::numeric
FROM pem.data_rollup ($3::text, $4::text, $5::text, $6::timestamptz, $7::timestamptz, $8::interval, $9::integer, $10::text[], $11::text[], $12::integer, $13::boolean, $14::text[])';
					IF metric.agg_func IS NOT NULL AND array_length(metric.agg_func, 1) >= m_idx AND metric.agg_func[m_idx] IS NOT NULL THEN
						tmp_str := metric.agg_func[m_idx];
					END IF;
					CASE
						WHEN tmp_str = 'A' THEN tmp_str := 'avg';
						WHEN tmp_str = 'M' THEN tmp_str := 'max';
						WHEN tmp_str = 'm' THEN tmp_str := 'min';
						WHEN tmp_str = 'F' THEN tmp_str := 'FIRST';
						ELSE tmp_str := 'avg';
					END CASE;

					RETURN QUERY EXECUTE query USING pos, label, metric.tbl, tmp_str, metric.metrices[m_idx], start_time, end_time, agg_int * '1 minute'::interval, max_points, _params, _vals, aid, is_capacity_manager, metric_restrict_dbs;
				END LOOP;
			END IF;
		ELSE
			params := ARRAY[]::text[];
			vals := ARRAY[]::text[];
			metric_restrict_dbs := NULL;

			CASE WHEN probe_applies_to_id = 100 THEN
					params := ARRAY['agent_id'];
					vals := ARRAY[aid::text];
				WHEN probe_target_type = 200 THEN
					params := ARRAY['server_id'];
					vals := ARRAY[sid::text]::text[];

					IF probe_applies_to_id >= 300 AND level >= 300 THEN
						-- Restricted DBs are availabe that doesn't mean - they're applicable
						-- for this metric
						--
						-- Thye're applicable only if probe can applies to database level and
						-- current dashboard is for server-level
						IF array_length(restricted_dbs, 1) <> 0 THEN
							metric_restrict_dbs = restricted_dbs;
						ELSE
							metric_restrict_dbs := NULL;
						END IF;
					END IF;

					IF probe_applies_to_id >= 400 AND level = 400 THEN
						params := ARRAY['server_id', 'database_name', 'schema_name'];
						vals := ARRAY[sid::text, db, schema];
					ELSIF probe_applies_to_id >= 300 AND level >= 300 THEN
						params := ARRAY['server_id', 'database_name'];
						vals := ARRAY[sid::text, db];
					END IF;
				WHEN probe_target_type = 300 THEN
					params := ARRAY['server_id', 'database_name'];
					vals := ARRAY[sid::text, db]::text[];
					IF array_length(restricted_dbs, 1) <> 0 THEN
						metric_restrict_dbs = restricted_dbs;
					ELSE
						metric_restrict_dbs := NULL;
					END IF;
					IF probe_applies_to_id > 300  THEN
						IF level > 300 THEN
							params := ARRAY['server_id', 'database_name', 'schema_name'];
							vals := ARRAY[sid::text, db, schema];
						END IF;
					END IF;
				WHEN probe_target_type = 400 THEN
					params := ARRAY['server_id', 'database_name', 'schema_name'];
					vals := ARRAY[sid::text, db, schema];
			ELSE -- Do nothing
			END CASE;
			CASE WHEN metric.params IS NOT NULL THEN
				FOR i IN array_lower(metric.params, 1) .. array_upper(metric.params, 1)
				LOOP
					IF metric.params[i].name IS NOT NULL AND metric.params[i].name != '' THEN
						IF sid IS NOT NULL AND metric.params[i].name = 'server_id' THEN
							params := params || metric.params[i].name;
							vals := vals || sid::text;
						ELSIF aid IS NOT NULL AND metric.params[i].name = 'agent_id' THEN
							params := params || metric.params[i].name;
							vals := vals || aid::text;
						ELSIF db IS NOT NULL AND db <> '' AND metric.params[i].name = 'database_name' THEN
							params := params || metric.params[i].name;
							vals := vals || db::text;
						ELSIF schema IS NOT NULL AND schema <> '' AND metric.params[i].name = 'schema_name' THEN
							params := params || metric.params[i].name;
							vals := vals || schema::text;
						ELSE
							params := params || metric.params[i].name;
							vals := vals || metric.params[i].value;
						END IF;
					END IF;
				END LOOP;
			ELSE -- Do nothing
			END CASE;

			tmp_str := 'A';
			FOR m_idx IN array_lower(metric.metrices, 1) .. array_upper(metric.metrices, 1)
			LOOP
				pos := pos + 1;
				label := '';

				EXECUTE '
SELECT
	(CASE WHEN NOT pit_by_default THEN display_name || ''+'' ELSE display_name END), sql_data_type
FROM pem.probe_column
WHERE probe_id = $1::int4 AND internal_name = $2::text AND is_graphable
UNION ALL
SELECT
	display_name, sql_data_type
FROM pem.probe_column
WHERE probe_id = $1::int4 AND (internal_name || ''_pit'') = $2::text AND is_graphable AND NOT pit_by_default AND calculate_pit'
USING probe_id, metric.metrices[m_idx] INTO metric_label, probe_type;

				IF chart.labels IS NOT NULL AND array_length(chart.labels, 1) >= pos THEN
					label := chart.labels[pos];
				ELSE
					IF metric_label IS NOT NULL THEN
						label := metric_label;
					END IF;
				END IF;
				query := 'SELECT
	$1::int2 AS idx, $2::text AS label, aggregated_time, aggregated_value
FROM pem.data_rollup ($3::text, $4::text, $5::text, $6::timestamptz, $7::timestamptz, $8::interval, $9::integer, $10::text[], $11::text[], $12::integer, $13::boolean, $14::text[])';
				IF metric.agg_func IS NOT NULL AND array_length(metric.agg_func, 1) >= m_idx THEN
					tmp_str := metric.agg_func[m_idx];
				END IF;
				CASE
					WHEN tmp_str = 'A' THEN tmp_str := 'avg';
					WHEN tmp_str = 'M' THEN tmp_str := 'max';
					WHEN tmp_str = 'm' THEN tmp_str := 'min';
					WHEN tmp_str = 'F' THEN tmp_str := 'FIRST';
					ELSE tmp_str := 'avg';
				END CASE;

				RETURN QUERY EXECUTE query USING pos, label, metric.tbl, tmp_str, metric.metrices[m_idx], start_time, end_time, agg_int * '1 minutes'::interval, max_points, params, vals, aid, is_capacity_manager, metric_restrict_dbs;
			END LOOP;
		END IF;
	END LOOP;
	CLOSE mcurs;
END
$$ LANGUAGE 'plpgsql';

--Fix for RM 32281

DO $$
DECLARE
    job_id integer;
    serverid integer;
    agentid integer;
    name text;
BEGIN
    -- Default serverid
    serverid := 1;

    -- Default agentid
    agentid := 1;

    -- Check if the job already exists (for purging deleted charts)
    SELECT jobid INTO job_id FROM pem.job WHERE jobname = 'Job purge the deleted charts' AND agent_id = agentid;

    IF (NOT FOUND) THEN
        -- Create data purging job.
        INSERT INTO pem.job(jobname, jobdesc, agent_id) VALUES('Job purge the deleted charts', 'This job runs periodically to purge the deleted charts.', agentid) RETURNING jobid INTO job_id;
    END IF;

    -- Check if the job step already exists.
    SELECT jstname INTO name FROM pem.jobstep WHERE jstname = 'Job purge the deleted charts' AND jstjobid = job_id;

    IF (NOT FOUND) THEN
        -- Create data purging step.
        INSERT INTO pem.jobstep(jstjobid, jstname, jstdesc, jstkind, jstcode, server_id, database_name) VALUES (job_id, 'Job purge the deleted charts','This job step runs periodically to purge the deleted charts (we do not clean them up immediately).', 's',
        'SELECT pem.purge_deleted_charts()', serverid, 'pem');
    END IF;

    -- Check if the job schedule already exists.
    SELECT jscname INTO name FROM pem.schedule WHERE jscname = 'Job purge the deleted charts' AND jscjobid = job_id;

    IF (NOT FOUND) THEN
        -- Create data purging schedule.
        INSERT INTO pem.schedule(jscjobid, jscname, jscdesc, jscminutes, jschours, jscweekdays, jscmonthdays, jscmonths) VALUES(job_id, 'Job purge the deleted charts', 'This job schedule runs periodically to purge the deletecd charts.', '{t,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f}', '{f,f,t,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f}','{t,t,t,t,t,t,t}', '{t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t}', '{t,t,t,t,t,t,t,t,t,t,t,t}');
    END IF;
END $$;

REVOKE ALL ON FUNCTION pem.purge_deleted_charts() FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION pem.purge_deleted_charts() FROM pem_user;
GRANT EXECUTE ON FUNCTION pem.purge_deleted_charts() TO pem_agent;


--Fix for RM 32193

CREATE OR REPLACE FUNCTION pem.create_email(alert_id integer, template text, OUT subject_mail text, OUT message_mail text) AS $$
DECLARE
	alert_name text;
	alert_agent_id int;
	alert_server_id int;
	alert_database_name text;
	alert_object_name text;
	alert_schema_name text;
	alert_thresholdvalue text;
	server_name text;
	server_ip text;
	server_port integer;
	agent_name text;
	msg_object_name text;
BEGIN
	-- Get alert, agent, server details
	SELECT
		a.name, a.agent_id, a.server_id, a.database_name, a.schema_name, a.thresholds,
		s.description, s.server, s.port,
		ag.description
	INTO
		alert_name, alert_agent_id, alert_server_id, alert_database_name, alert_schema_name,
		alert_thresholdvalue, server_name, server_ip, server_port,
		agent_name
	FROM
		pem.alert a
		LEFT JOIN pem.server s ON a.server_id = s.id
		LEFT JOIN pem.agent ag ON a.agent_id = ag.id
	WHERE
		a.id = alert_id;

	SELECT mail_subject, mail_message INTO subject_mail, message_mail FROM pem.email_template WHERE display_name = template;

	CASE WHEN server_name IS NOT NULL THEN
		alert_object_name = server_name || ' ('|| server_ip ||': ' || server_port || ')';
		msg_object_name = alert_object_name;
	WHEN agent_name IS NOT NULL THEN
		alert_object_name = agent_name;
		msg_object_name = alert_object_name;
	ELSE
		alert_object_name = 'Postgres Enterprise Manager Server';
		msg_object_name = 'N/A';
	END CASE;

	-- Replace single "\" with "\\" because regexp_replace escapes backslash
	alert_name = replace(alert_name, E'\\', E'\\\\');
	alert_object_name = replace(alert_object_name, E'\\', E'\\\\');

	subject_mail = regexp_replace(subject_mail, '%AlertName%', alert_name);
	subject_mail = regexp_replace(subject_mail, '%ObjectName%', alert_object_name);
	message_mail = regexp_replace(message_mail, '%AlertName%', alert_name);
	message_mail = regexp_replace(message_mail, '%ObjectName%', msg_object_name);
	message_mail = regexp_replace(message_mail, '%ThresholdValue%', alert_thresholdvalue::text);
END;
$$ LANGUAGE plpgsql;

-- Fix for RM 32103
CREATE OR REPLACE FUNCTION pem.generate_cm_chart_data(id int4, OUT idx int4, OUT rtime timestamptz, OUT value numeric)
RETURNS SETOF RECORD AS $$
DECLARE
	type         char(1);
	historical   int4;
	extrapolated int4;
	midx         int4;
	topt         text;
	tval         numeric;
	rec          record;
	curs         refcursor;
	points       int4;
	frequency    interval := NULL;
	intv         interval := NULL;
	max_cm_span  int4;
	cutoff_cnt   int4 := 0;
	back         int4 := -1;
	start_time   timestamptz;
	end_time     timestamptz;
	curr_time    timestamptz := now();
	min_recorded_time timestamptz;
	history_sql  text := '';
	prev_tbl     text := '';
BEGIN
	EXECUTE 'SELECT
	type, historical, extrapolated, midx, tval, toperator,
	COALESCE((SELECT value::int4 FROM pem.config WHERE param like ''cm_data_points_per_report''), 100),
	COALESCE((SELECT value::int4 FROM pem.config WHERE param like ''cm_max_end_date_in_years''), 5)
FROM pem.capacity_report_chart
WHERE cid = $1::int4'
		INTO type, historical, extrapolated, midx, tval, topt, points, max_cm_span USING id;

	IF type IS NULL THEN
		-- Couldn't find the chart in capacity_report_chart table
		RAISE EXCEPTION '201';
	END IF;

	OPEN curs SCROLL FOR EXECUTE 'SELECT
	cm.mid AS mid, cm.tbl AS tbl, p.applies_to_id AS applies_to_id,
	cm.metrices[1] AS metric, cm.agg_func[1] AS agg,
	CASE WHEN p.applies_to_id <> 100 THEN (SELECT agent_id FROM pem.agent_server_binding WHERE server_id = s.id) ELSE a.id END agent,
	COALESCE(CASE WHEN p.applies_to_id <> 100 THEN s.id ELSE a.id END, 0) AS object,
	COALESCE(CASE WHEN p.applies_to_id <> 100 THEN s.active ELSE a.active END, false) AS is_active,
	(pv.execution_frequency * ''1 sec''::interval) AS execution_frequency,
	array(SELECT (param).name FROM (SELECT unnest(cm.params) AS param) p) AS names,
	array(SELECT (param).value FROM (SELECT unnest(cm.params) AS param) p) AS vals
FROM
	pem.chart_metric cm
	LEFT JOIN pem.server s ON (s.id::text = (cm.params[1]).value)
	LEFT JOIN pem.agent  a ON (a.id::text = (cm.params[1]).value)
	LEFT JOIN pem.probe p ON (p.internal_name = cm.tbl)
	LEFT JOIN pem.probe_target_view pv ON (p.id = pv.probe_id AND
		CASE
		WHEN p.target_type_id = 100 THEN pv.agent_id = a.id
		WHEN p.target_type_id = 200 THEN pv.server_id = s.id
		ELSE pv.server_id = s.id AND pv.database_name = (cm.params[2]).value
		END)
WHERE cm.cid = $1::int4 AND CASE WHEN p.applies_to_id <> 100 THEN s.active ELSE a.active END ORDER BY p.internal_name' USING id;

	-- Find the minimum frequency of the probes
	LOOP
		FETCH curs INTO rec;
		EXIT WHEN NOT FOUND;
		-- Create query to find the least time from when the metrics are available
		IF prev_tbl <> rec.tbl THEN
			IF history_sql <> '' THEN
				history_sql := history_sql || ' UNION ALL ';
			END IF;
			history_sql := history_sql || 'SELECT min(recorded_time) AS r FROM pemhistory.' || pg_catalog.quote_ident(rec.tbl);
			prev_tbl := rec.tbl;
		END IF;

		IF rec.execution_frequency IS NOT NULL THEN
			IF frequency IS NULL THEN
				frequency := rec.execution_frequency;
			ELSEIF frequency > rec.execution_frequency THEN
				frequency := rec.execution_frequency;
			END IF;
			IF type = 'T' THEN
				IF back <> -1 THEN
					back := back + 1;
				ELSEIF rec.mid = midx THEN
					back := 1;
				END IF;
			END IF;
		END IF;
	END LOOP;

	IF frequency IS NULL THEN
		-- No matrices are for the active server or agent
		RAISE EXCEPTION '203';
	END IF;

	history_sql := 'SELECT min(s.r) FROM (' || history_sql || ') s';
	-- Find the least time from when the metrics are available
	EXECUTE history_sql INTO min_recorded_time;

	intv := (historical * '1 day'::interval) / points;
	start_time := curr_time - (historical * '1 day'::interval);
	-- If minimum recorded time for data is greater than start_time it means that data
	-- is available from the recorded time not from the start time.
	IF min_recorded_time > start_time THEN
		start_time := min_recorded_time;
		intv := (curr_time - min_recorded_time) / points;
	END IF;

	IF intv < frequency THEN
		intv := frequency;
	END IF;

	IF type = 'T' THEN
		intv := intv * 2;

		WHILE back >= 0
		LOOP
			MOVE PRIOR IN curs;
			back := back - 1;
		END LOOP;
		FETCH curs INTO rec;
		end_time := curr_time + (max_cm_span * '1 year'::interval);

		EXECUTE 'SELECT pem.linear_trend_threshold($1::text, $2::text, $3::timestamptz, $4::timestamptz,
			$5::numeric, $6::boolean, $7::interval, $8::varchar[], $9::varchar[], 10::int4, $11::int4)'
		INTO cutoff_cnt USING rec.tbl, rec.metric, start_time, curr_time, tval,
			CASE WHEN topt = 'EXCEEDS' THEN true ELSE false END, intv, rec.names,
			rec.vals, max_cm_span, rec.agent;
	ELSE
		end_time := curr_time + (extrapolated * '1 day'::interval);
	END IF;

	-- Moving the cursor to the first record now
	MOVE BACKWARD ALL FROM curs;

	LOOP
		FETCH curs INTO rec;
		EXIT WHEN NOT FOUND;

		BEGIN
			RETURN QUERY EXECUTE '
SELECT
	$1::int4 AS idx, trend_metric_time AS rtime, trend_metric_value::numeric(25, 4) AS value
FROM pem.linear_trend_analysis($2::text, $3::text, $4::text, $5::timestamptz, $6::timestamptz,
	$7::timestamptz, $8::interval, $9::int4, $10::varchar[], $11::varchar[], $12::int4, $13::int4) WHERE trend_metric_value IS NOT NULL'
			USING rec.mid, rec.tbl, CASE WHEN rec.agg = 'A' THEN 'avg'
				WHEN rec.agg = 'M' THEN 'max' WHEN rec.agg = 'm' THEN 'min'
				WHEN rec.agg = 'F' THEN 'FIRST' ELSE 'avg' END, rec.metric, start_time,
				end_time, curr_time, intv, points, rec.names, rec.vals, cutoff_cnt,
				rec.agent;
			EXCEPTION
				WHEN raise_exception THEN
					back := 1;
		END;
	END LOOP;
END;
$$ LANGUAGE plpgsql;

--Fixing #31622
--
-- Deleting the xdb_smr_mmr probe on a database,
-- Which is not having the xdb required catalog schema.
--
DELETE
FROM
	pem.probe_config_database pcd
USING
(
	SELECT
	probe_id,
        server_id,
        database_name
FROM
	pem.probe_config_database
WHERE
	probe_id=
	(
		SELECT
			id
		FROM
			pem.probe
		WHERE
			internal_name='xdb_smr_mmr_replication'
	)
	AND enabled=TRUE  AND (server_id, database_name) NOT IN
	(
		SELECT
			server_id,
			database_name
		FROM
			pemdata.oc_schema
		WHERE
			schema_name = '_edb_replicator_pub'
	)
)as xdbp
WHERE pcd.probe_id = xdbp.probe_id AND pcd.server_id = xdbp.server_id AND pcd.database_name = xdbp.database_name;

--Preventing the user to enable the XDB probe,
--if pem db don't find the required xdb catalog schema.
--
CREATE OR REPLACE FUNCTION pem.on_probe_config_database_insert_or_update() RETURNS TRIGGER AS
$$
BEGIN
	IF EXISTS (
		SELECT (NEW.probe_id = id)
		FROM pem.probe
		WHERE internal_name = 'xdb_smr_mmr_replication') AND NEW.enabled IS TRUE THEN

		IF EXISTS (
			SELECT 1
			FROM pemdata.oc_schema
			WHERE database_name = NEW.database_name
			AND server_id = NEW.server_id
			AND schema_name = '_edb_replicator_pub') THEN

				RETURN NEW;
		ELSE
				RAISE EXCEPTION E'\nXDB publication''s catalog is not found.\nXDB probe should be configured on publication side.';
				RETURN NULL;
		END IF;
	ELSE
		RETURN NEW;
	END IF;
END;
$$
LANGUAGE PLPGSQL;

-- Create xdb probe enable prevent trigger, if the trigger is not exist
--
DO
$$
BEGIN
IF NOT EXISTS(SELECT true FROM pg_trigger WHERE tgname ~ 'on_probe_config_database_insert_or_update_trg') THEN
EXECUTE 'CREATE TRIGGER on_probe_config_database_insert_or_update_trg BEFORE INSERT OR UPDATE ON pem.probe_config_database FOR EACH ROW EXECUTE PROCEDURE pem.on_probe_config_database_insert_or_update()';
END IF;
END
$$;

UPDATE pem.probe_column SET unit_of_value = '#' WHERE probe_id=(SELECT id FROM pem.probe WHERE internal_name = 'database_frozenxid') AND internal_name = 'frozenxid';
UPDATE pem.probe_column SET unit_of_value = '#' WHERE probe_id=(SELECT id FROM pem.probe WHERE internal_name = 'table_frozenxid') AND internal_name = 'frozenxid';
UPDATE pem.probe_column SET unit_of_value = '#' WHERE probe_id=(SELECT id FROM pem.probe WHERE internal_name = 'mview_frozenxid') AND internal_name = 'frozenxid';

COMMIT TRANSACTION;
