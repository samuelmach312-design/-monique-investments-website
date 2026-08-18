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

-- Upgrade script for v2.0.0b3 to v2.0.0rc1

BEGIN TRANSACTION;

-- Upgrade the schema version
CREATE OR REPLACE FUNCTION pem.schema_version()
  RETURNS integer AS
'SELECT 201107281::integer;'
  LANGUAGE 'sql' IMMUTABLE;

-- Update the default_execution_frequency of some probes to more meaningful values.
UPDATE pem.probe SET default_execution_frequency = 300 WHERE internal_name = 'session_info';
UPDATE pem.probe SET default_execution_frequency = 300 WHERE internal_name = 'lock_info';
UPDATE pem.probe SET default_execution_frequency = 300 WHERE internal_name = 'memory_usage';
UPDATE pem.probe SET default_execution_frequency = 300 WHERE internal_name = 'system_waits';
UPDATE pem.probe SET default_execution_frequency = 300 WHERE internal_name = 'session_waits';
UPDATE pem.probe SET default_execution_frequency = 1800 WHERE internal_name = 'table_bloat';

-- Insert unit column in pemdata.settings
ALTER TABLE pemdata.settings ADD COLUMN unit text;
ALTER TABLE pemhistory.settings ADD COLUMN unit text;
INSERT INTO pem.probe_column(probe_id, internal_name, display_name, display_position, classification, sql_data_type, unit_of_value, calculate_pit, discard_history, pit_by_default) SELECT id, 'unit', 'Unit', 3, 'm', 'text', '', false, false, false FROM pem.probe WHERE internal_name='settings';
-- Update the trigger functions related to pemdata.settings probe
CREATE OR REPLACE FUNCTION pemdata.copy_settings_to_history() RETURNS TRIGGER AS $$
BEGIN
	IF (TG_OP = 'INSERT' OR TG_OP = 'UPDATE') THEN
    	INSERT INTO pemhistory.settings (recorded_time, server_id, name, setting, unit) VALUES (NEW.recorded_time, NEW.server_id, NEW.name, NEW.setting, NEW.unit);
	ELSIF EXISTS(SELECT 1 FROM pem.server WHERE id = OLD.server_id) THEN
		INSERT INTO pemhistory.settings (server_id, name) VALUES (OLD.server_id, OLD.name);
	END IF;
	RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Servers down and agents down alerts should have 2*heartbeat_interval as
-- the decision time interval
UPDATE pem.alert_template SET sql =
	$sql$
SELECT
	count(agent_id)
FROM
	pem.agent_heartbeat pah,
	pem.agent pa
WHERE
	pah.agent_id = pa.id AND
	pa.active = TRUE AND
	pah.last_heartbeat < now() - (pa.heartbeat_interval)*2*'1 second'::interval$sql$
WHERE display_name = 'Agents Down' AND object_type = 50;

UPDATE pem.alert_template SET sql =
	$sql$
SELECT
	count(distinct(server_id))
FROM
	pem.server_heartbeat psh,
	pem.agent pa
WHERE
	psh.agent_id = pa.id AND
	CASE WHEN psh.server_id IS NULL THEN TRUE
	ELSE psh.server_id IN
		(SELECT id FROM pem.server WHERE active
		INTERSECT
		SELECT server_id FROM pem.agent_server_binding)
        END AND
	psh.last_heartbeat < now() - (pa.heartbeat_interval)*2*'1 second'::interval$sql$
WHERE display_name = 'Servers Down' AND object_type = 50;

-- Update the last Vacuum/Analyze alerts to allow for databases that have never been vacuumed or analyzed.
UPDATE pem.alert_template SET sql =
	$sql$
SELECT
	CASE WHEN last_vacuum IS NULL THEN
		EXTRACT(EPOCH FROM (capture_time - '1970-01-01'::timestamp)::interval)/3600
	ELSE
		EXTRACT(EPOCH FROM (capture_time - last_vacuum)::interval)/3600
	END
FROM pemdata.table_statistics
WHERE	server_id = ${server_id}
AND		database_name = '${database_name}'
AND		schema_name = '${schema_name}'
AND		table_name = '${object_name}'$sql$
WHERE display_name = 'Last Vacuum' AND object_type = 500;

UPDATE pem.alert_template SET sql =
	$sql$
SELECT
	CASE WHEN last_vacuum IS NULL THEN
		EXTRACT(EPOCH FROM (capture_time - '1970-01-01'::timestamp)::interval)/3600
	ELSE
		EXTRACT(EPOCH FROM (capture_time - last_vacuum)::interval)/3600
	END
FROM pemdata.table_statistics
WHERE	server_id = ${server_id}
AND		database_name = '${database_name}'
AND		schema_name = '${schema_name}'
ORDER BY last_vacuum DESC NULLS LAST LIMIT 1$sql$
WHERE display_name = 'Last Vacuum' AND object_type = 400;

UPDATE pem.alert_template SET sql =
	$sql$
SELECT
	CASE WHEN last_vacuum IS NULL THEN
		EXTRACT(EPOCH FROM (capture_time - '1970-01-01'::timestamp)::interval)/3600
	ELSE
		EXTRACT(EPOCH FROM (capture_time - last_vacuum)::interval)/3600
	END
FROM pemdata.table_statistics
WHERE	server_id = ${server_id}
AND		database_name = '${database_name}'
ORDER BY last_vacuum DESC NULLS LAST LIMIT 1$sql$
WHERE display_name = 'Last Vacuum' AND object_type = 300;

UPDATE pem.alert_template SET sql =
	$sql$
SELECT
	CASE WHEN last_vacuum IS NULL THEN
		EXTRACT(EPOCH FROM (capture_time - '1970-01-01'::timestamp)::interval)/3600
	ELSE
		EXTRACT(EPOCH FROM (capture_time - last_vacuum)::interval)/3600
	END
FROM pemdata.table_statistics
WHERE	server_id = ${server_id}
ORDER BY last_vacuum DESC NULLS LAST LIMIT 1$sql$
WHERE display_name = 'Last Vacuum' AND object_type = 200;

UPDATE pem.alert_template SET sql =
	$sql$
SELECT
	CASE WHEN last_autovacuum IS NULL THEN
		EXTRACT(EPOCH FROM (capture_time - '1970-01-01'::timestamp)::interval)/3600
	ELSE
		EXTRACT(EPOCH FROM (capture_time - last_autovacuum)::interval)/3600
	END
FROM pemdata.table_statistics
WHERE	server_id = ${server_id}
AND		database_name = '${database_name}'
AND		schema_name = '${schema_name}'
AND		table_name = '${object_name}'$sql$
WHERE display_name = 'Last AutoVacuum' AND object_type = 500;

UPDATE pem.alert_template SET sql =
	$sql$
SELECT
	CASE WHEN last_autovacuum IS NULL THEN
		EXTRACT(EPOCH FROM (capture_time - '1970-01-01'::timestamp)::interval)/3600
	ELSE
		EXTRACT(EPOCH FROM (capture_time - last_autovacuum)::interval)/3600
	END
FROM pemdata.table_statistics
WHERE	server_id = ${server_id}
AND		database_name = '${database_name}'
AND		schema_name = '${schema_name}'
ORDER BY last_autovacuum DESC NULLS LAST LIMIT 1$sql$
WHERE display_name = 'Last AutoVacuum' AND object_type = 400;

UPDATE pem.alert_template SET sql =
	$sql$
SELECT
	CASE WHEN last_autovacuum IS NULL THEN
		EXTRACT(EPOCH FROM (capture_time - '1970-01-01'::timestamp)::interval)/3600
	ELSE
		EXTRACT(EPOCH FROM (capture_time - last_autovacuum)::interval)/3600
	END
FROM pemdata.table_statistics
WHERE	server_id = ${server_id}
AND		database_name = '${database_name}'
ORDER BY last_autovacuum DESC NULLS LAST LIMIT 1$sql$
WHERE display_name = 'Last AutoVacuum' AND object_type = 300;

UPDATE pem.alert_template SET sql =
	$sql$
SELECT
	CASE WHEN last_autovacuum IS NULL THEN
		EXTRACT(EPOCH FROM (capture_time - '1970-01-01'::timestamp)::interval)/3600
	ELSE
		EXTRACT(EPOCH FROM (capture_time - last_autovacuum)::interval)/3600
	END
FROM pemdata.table_statistics
WHERE	server_id = ${server_id}
ORDER BY last_autovacuum DESC NULLS LAST LIMIT 1$sql$
WHERE display_name = 'Last AutoVacuum' AND object_type = 200;

UPDATE pem.alert_template SET sql =
	$sql$
SELECT
	CASE WHEN last_analyze IS NULL THEN
		EXTRACT(EPOCH FROM (capture_time - '1970-01-01'::timestamp)::interval)/3600
	ELSE
		EXTRACT(EPOCH FROM (capture_time - last_analyze)::interval)/3600
	END
FROM pemdata.table_statistics
WHERE	server_id = ${server_id}
AND		database_name = '${database_name}'
AND		schema_name = '${schema_name}'
AND		table_name = '${object_name}'$sql$
WHERE display_name = 'Last Analyze' AND object_type = 500;

UPDATE pem.alert_template SET sql =
	$sql$
SELECT
	CASE WHEN last_analyze IS NULL THEN
		EXTRACT(EPOCH FROM (capture_time - '1970-01-01'::timestamp)::interval)/3600
	ELSE
		EXTRACT(EPOCH FROM (capture_time - last_analyze)::interval)/3600
	END
FROM pemdata.table_statistics
WHERE	server_id = ${server_id}
AND		database_name = '${database_name}'
AND		schema_name = '${schema_name}'
ORDER BY last_analyze DESC NULLS LAST LIMIT 1$sql$
WHERE display_name = 'Last Analyze' AND object_type = 400;

UPDATE pem.alert_template SET sql =
	$sql$
SELECT
	CASE WHEN last_analyze IS NULL THEN
		EXTRACT(EPOCH FROM (capture_time - '1970-01-01'::timestamp)::interval)/3600
	ELSE
		EXTRACT(EPOCH FROM (capture_time - last_analyze)::interval)/3600
	END
FROM pemdata.table_statistics
WHERE	server_id = ${server_id}
AND		database_name = '${database_name}'
ORDER BY last_analyze DESC NULLS LAST LIMIT 1$sql$
WHERE display_name = 'Last Analyze' AND object_type = 300;

UPDATE pem.alert_template SET sql =
	$sql$
SELECT
	CASE WHEN last_analyze IS NULL THEN
		EXTRACT(EPOCH FROM (capture_time - '1970-01-01'::timestamp)::interval)/3600
	ELSE
		EXTRACT(EPOCH FROM (capture_time - last_analyze)::interval)/3600
	END
SELECT EXTRACT(EPOCH FROM (capture_time - last_analyze)::interval)/3600
FROM pemdata.table_statistics
WHERE	server_id = ${server_id}
ORDER BY last_analyze DESC NULLS LAST LIMIT 1$sql$
WHERE display_name = 'Last Analyze' AND object_type = 200;

UPDATE pem.alert_template SET sql =
	$sql$
SELECT
	CASE WHEN last_autoanalyze IS NULL THEN
		EXTRACT(EPOCH FROM (capture_time - '1970-01-01'::timestamp)::interval)/3600
	ELSE
		EXTRACT(EPOCH FROM (capture_time - last_autoanalyze)::interval)/3600
	END
FROM pemdata.table_statistics
WHERE	server_id = ${server_id}
AND		database_name = '${database_name}'
AND		schema_name = '${schema_name}'
AND		table_name = '${object_name}'$sql$
WHERE display_name = 'Last AutoAnalyze' AND object_type = 500;

UPDATE pem.alert_template SET sql =
	$sql$
SELECT
	CASE WHEN last_autoanalyze IS NULL THEN
		EXTRACT(EPOCH FROM (capture_time - '1970-01-01'::timestamp)::interval)/3600
	ELSE
		EXTRACT(EPOCH FROM (capture_time - last_autoanalyze)::interval)/3600
	END
FROM pemdata.table_statistics
WHERE	server_id = ${server_id}
AND		database_name = '${database_name}'
AND		schema_name = '${schema_name}'
ORDER BY last_autoanalyze DESC NULLS LAST LIMIT 1$sql$
WHERE display_name = 'Last AutoAnalyze' AND object_type = 400;

UPDATE pem.alert_template SET sql =
	$sql$
SELECT
	CASE WHEN last_autoanalyze IS NULL THEN
		EXTRACT(EPOCH FROM (capture_time - '1970-01-01'::timestamp)::interval)/3600
	ELSE
		EXTRACT(EPOCH FROM (capture_time - last_autoanalyze)::interval)/3600
	END
FROM pemdata.table_statistics
WHERE	server_id = ${server_id}
AND		database_name = '${database_name}'
ORDER BY last_autoanalyze DESC NULLS LAST LIMIT 1$sql$
WHERE display_name = 'Last AutoAnalyze' AND object_type = 300;

UPDATE pem.alert_template SET sql =
	$sql$
SELECT
	CASE WHEN last_autoanalyze IS NULL THEN
		EXTRACT(EPOCH FROM (capture_time - '1970-01-01'::timestamp)::interval)/3600
	ELSE
		EXTRACT(EPOCH FROM (capture_time - last_autoanalyze)::interval)/3600
	END
FROM pemdata.table_statistics
WHERE	server_id = ${server_id}
ORDER BY last_autoanalyze DESC NULLS LAST LIMIT 1$sql$
WHERE display_name = 'Last AutoAnalyze' AND object_type = 200;

-- Add Alert Errors alert
SELECT pem.create_alert_template(
	'Alert Errors',
	'Number of alerts in an error state.',
	$sql$
SELECT
	count(*)
FROM
	pem.alert al
WHERE 	COALESCE(error_message, '') <> ''
AND 	CASE WHEN al.agent_id = 0 THEN TRUE
	ELSE al.agent_id IN (SELECT id FROM pem.agent WHERE active)
	END
AND 	CASE WHEN al.server_id IS NULL THEN TRUE
	ELSE al.server_id IN
		(SELECT id FROM pem.server WHERE active
		INTERSECT
		SELECT server_id FROM pem.agent_server_binding)
        END$sql$,
	50, NULL, NULL, NULL, NULL);

SELECT pem.create_alert(
	'Alert Errors',
	(SELECT id FROM pem.alert_template WHERE display_name = 'Alert Errors' LIMIT 1),
	1, NULL, NULL, NULL, NULL, NULL, '{}', '>', '{0.1, 0.2, 0.3}', 1, 30, true);


ALTER TABLE pem.alert_template ADD COLUMN probe_dependency_list text[] NOT NULL DEFAULT '{}';
DROP FUNCTION pem.create_alert_template(text, text, text, integer, text[], pem.alert_param_type[], text[], text, integer, integer);
CREATE OR REPLACE FUNCTION pem.create_alert_template(
									name					text,
									description				text,
									sql						text,
									object_type				integer,
									param_names				text[],
									param_types				pem.alert_param_type[],
									param_units				text[],
									threshold_unit			text,
									probe_dependency_list	text[] DEFAULT '{}',
									default_check_frequency	integer DEFAULT 1,
									default_history_retention	integer DEFAULT 30
									)
RETURNS VOID AS $$
	/*
	 * If we ever change to pl/pgsql, we might want to validate input and RAISE
	 * exceptions here.
	 *
	 * If this INSERT fails the user will see the ERROR with this function's
	 * name in context, hence it doesn't seem any worse than validating params
	 * and RAISE'ing errors, except that by using RAISE we can provide friendly
	 * hints.
	 */
	INSERT INTO pem.alert_template (display_name, description, sql, object_type,
									param_names, param_types, param_units,
									threshold_unit, probe_dependency_list,
									default_check_frequency, default_history_retention)
	VALUES($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11);
$$ LANGUAGE SQL;

CREATE OR REPLACE FUNCTION pem.process_one_alert() RETURNS BOOL AS $$
DECLARE
	err					text;
	sql					text;
	acked				bool;
	state				pem.alert_state;
	sql_ret				numeric;
	alert_rec			record;
	locked_alert		bool;
	probe_disabled_err	text;
	zero_rows_err		text;
	probe_enabled		bool;
	all_probes_enabled	bool;
BEGIN
	probe_disabled_err = 'Required probe(s) ';
	zero_rows_err = 'Zero rows returned';

	locked_alert = false;

	FOR alert_rec in	SELECT al.*, ast.current_state AS state, at.sql,
								at.probe_dependency_list
						FROM (pem.alert AS al
								JOIN pem.alert_template AS at
								ON al.template_id = at.id)
						LEFT JOIN pem.alert_status AS ast
							ON(al.id = ast.alert_id)
						WHERE al.enabled = true
						-- We do not process alerts that are known erroneous
						AND (COALESCE(al.error_message, '' ) IN ('', zero_rows_err)
							OR al.error_message LIKE probe_disabled_err || '%' )
						AND (now() - COALESCE(ast.last_processed, '1900-01-01'))
							>= (al.check_frequency||'minutes')::interval
						/*
						 * We process only those alerts that are bound to
						 * 'active' agents and servers.
						 *
						 * Note:alert.agent_id, agent|server.active are defined
						 * NOT NULL.
						 */
						AND CASE WHEN al.agent_id = 0 THEN TRUE
							ELSE al.agent_id IN (SELECT id FROM pem.agent WHERE active)
							END
						AND CASE WHEN al.server_id IS NULL THEN TRUE
							ELSE al.server_id IN
									(SELECT id FROM pem.server WHERE active
									INTERSECT
									SELECT server_id FROM pem.agent_server_binding)
							END
						ORDER BY ast.last_processed NULLS FIRST
	LOOP
		IF (pg_try_advisory_lock(0, alert_rec.id) = true) THEN
			locked_alert = true;
			EXIT; /* the loop */
		END IF;
	END LOOP;

	/* If we couldn't find or lock any candidate alert ... */
	IF (locked_alert = false) THEN
		/* tell the caller that we didn't process any alerts */
		RETURN false;
	END IF;

	/*
	 * We should return only 'true' from here on, since there may be more alerts
	 * to process.
	 *
	 * Also try to capture any ERROR and mark the alert as invalid
	 * instead of passing that ERROR back to the caller.
	 */

	sql = alert_rec.sql;

	/* Replace any reference to hierarchy-related alert parameters */
	sql = regexp_replace(sql, E'\\${agent_id}',		COALESCE(alert_rec.agent_id::text,	'')::text, 'g');
	sql = regexp_replace(sql, E'\\${server_id}',	COALESCE(alert_rec.server_id::text,	'')::text, 'g');
	sql = regexp_replace(sql, E'\\${database_name}',COALESCE(alert_rec.database_name,	'')::text, 'g');
	sql = regexp_replace(sql, E'\\${schema_name}',	COALESCE(alert_rec.schema_name,		'')::text, 'g');
	sql = regexp_replace(sql, E'\\${package_name}',	COALESCE(alert_rec.package_name,	'')::text, 'g');
	sql = regexp_replace(sql, E'\\${object_name}',	COALESCE(alert_rec.object_name,		'')::text, 'g');

	/* Replace ${param_n} with corresponding alert parameters */
	FOR i IN 1..COALESCE(array_upper(alert_rec.params, 1), 0) LOOP
		sql = regexp_replace(sql, E'\\${param_' || i || '}', alert_rec.params[i]::text, 'g');
	END LOOP;

	err = '';

	/* Check any required probe is disabled from the probe dependency list */
	all_probes_enabled = true;
	FOR i IN 1..COALESCE(array_upper(alert_rec.probe_dependency_list, 1), 0) LOOP
		SELECT enabled INTO probe_enabled FROM pem.probe_target_view WHERE probe_internal_name = alert_rec.probe_dependency_list[i]
		AND CASE WHEN applies_to_id = 100 THEN (agent_id = alert_rec.agent_id)
			WHEN applies_to_id = 200 THEN (server_id = alert_rec.server_id)
			ELSE (server_id = alert_rec.server_id AND database_name = alert_rec.database_name)
			END;
		IF NOT probe_enabled THEN
			probe_disabled_err = probe_disabled_err || alert_rec.probe_dependency_list[i] || ',';
			all_probes_enabled = false;
		END IF;
	END LOOP;
	probe_disabled_err = trim(trailing ',' from probe_disabled_err);
	probe_disabled_err = probe_disabled_err || ' are disabled.';

	IF NOT all_probes_enabled THEN
		err = probe_disabled_err;
	ELSE
		RAISE DEBUG 'Alert query being executed: %', sql;

		BEGIN
			EXECUTE sql INTO STRICT sql_ret;
		EXCEPTION
			WHEN no_data_found THEN
				IF all_probes_enabled THEN
					err = zero_rows_err;
				END IF;

			WHEN OTHERS THEN
				err = SQLERRM;
		END;
	END IF;

	-- If there was an error while processing the alert's sql
	IF (err <> '') THEN
		-- Set that error message on the alert
		UPDATE pem.alert
		SET error_message = err
		WHERE id = alert_rec.id;

		-- ... and also set the last processed timestamp
		UPDATE pem.alert_status
		SET last_processed = now()
		WHERE alert_id = alert_rec.id;

		-- If there wasn't any row for this alert already, then populate one.
		IF (NOT FOUND) THEN
			INSERT INTO pem.alert_status
			VALUES (alert_rec.id, NULL, NULL, NULL, now());
		END IF;

		-- RAISE NOTICE 'Encountered error while processing SQL: %', err;

		/*
		 * XXX: There's a small window of race condition here. Another transaction
		 * might pick up processing of this alert immediately after we unlock it
		 * below using non-transactional advisory lock.
		 *
		 * Someday consider trading this for transactional advisory locks. This
		 * will be possible when we mandate PG 9.1 as a minimum requirement.
		 */
		PERFORM pg_advisory_unlock(0, alert_rec.id);

		RETURN true;
	ELSE
		-- Set that error message to NULL on the alert if the SQL executes successfully
		UPDATE pem.alert
		SET error_message = NULL
		WHERE id = alert_rec.id;
	END IF;

	/* Some sample alerts
		Table size:  1GB => low, 2GB => med, 5GB => high

		>5 high
		>2 med
		>1 low

		operator: > ; thresholds: {1,2,5}

		current_connections : 50 => low, 20 => med, 5 => high

		<5 high
		<20 med
		<50 low

		operator: < ; thresholds: {50,20,5}
	 */

	IF (alert_rec.operator = '<') THEN
		IF (sql_ret < alert_rec.thresholds[3]) THEN
			state = 'HIGH';
		ELSIF (sql_ret < alert_rec.thresholds[2]) THEN
			state = 'MEDIUM';
		ELSIF (sql_ret < alert_rec.thresholds[1]) THEN
			state = 'LOW';
		ELSE
			state = NULL;
		END IF;
	ELSIF (alert_rec.operator = '>') THEN
		IF (sql_ret > alert_rec.thresholds[3]) THEN
			state = 'HIGH';
		ELSIF (sql_ret > alert_rec.thresholds[2]) THEN
			state = 'MEDIUM';
		ELSIF (sql_ret > alert_rec.thresholds[1]) THEN
			state = 'LOW';
		ELSE
			state = NULL;
		END IF;
	END IF;

	/*
	 * For an alert that is active (state IS NOT NULL), we do not want to clear
	 * its 'acknowledged' flag the first time it goes lower than LOW. So we wait
	 * for another round of check, and if it still appears lower than LOW, then
	 * we reset its acknowledged flag.
	 *
	 * The pseudo-code is:
	 *
	 * if (acked = true)
	 *     if current severity_level is null and previous/stored severity_level is null
	 *        set acked = false
	 *
	 *     if severity_level increases or changed from null to not-null
	 *         set acked = false
	 *
	 *     If severity_level decreases or goes from not-null to null
	 *         do nothing.
	 * end if
	 */
	IF (alert_rec.acknowledged) THEN

		acked = true;

		IF (state IS NULL AND alert_rec.state IS NULL) THEN
			-- State has been lower than LOW, two times in a row.
			acked = false;
		END IF;

		IF ((alert_rec.state IS NULL AND state IS NOT NULL)
			OR (state > alert_rec.state))
		THEN
			-- Severity has increased
			acked = false;
		END IF;

		IF ((alert_rec.state IS NOT NULL AND state IS NULL)
			OR (state < alert_rec.state))
		THEN
			/*
			 * Severity decreased, or went to NULL for the first time so don't
			 * clear the acked flag
			 */
			NULL;
		END IF;
	ELSE
		acked = false;
	END IF;

	IF (acked <> alert_rec.acknowledged)
	THEN
		-- The state changed, or acked flag changed
		UPDATE pem.alert
		SET acknowledged = acked
		WHERE id = alert_rec.id;
	END IF;

	UPDATE pem.alert_status
	SET last_processed = now(),
		current_value = sql_ret,
		current_state = state, -- may be NULL
		current_state_since =	CASE
								WHEN state IS DISTINCT FROM alert_rec.state
								THEN now()
								ELSE current_state_since
								END
	WHERE alert_id = alert_rec.id;

	-- If there wasn't any status row for this alert already, then populate one.
	IF (NOT FOUND) THEN
		INSERT INTO pem.alert_status
		VALUES (alert_rec.id, sql_ret, state,
				CASE
				WHEN state IS NOT NULL
				THEN now()
				ELSE NULL
				END,
				now());
	END IF;

	PERFORM pg_advisory_unlock(0, alert_rec.id);
	RETURN true;
END;
$$ LANGUAGE plpgsql;

UPDATE pem.alert
    SET error_message = 'Zero rows returned'
    WHERE error_message = 'No data found. Please ensure the required probes are enabled and that data is being collected.';

UPDATE pem.alert_template
	SET probe_dependency_list = string_to_array(regexp_replace(description,'.*Probe dependency list: (.*)', E'\\1' ), ', ')::text[]
	WHERE description ~ '.*Probe dependency list: (.*)';

UPDATE pem.alert_template
	SET description = regexp_replace(description, E'(.*)\\n\nProbe dependency list: .*$', E'\\1' )
	WHERE description ~ '.*Probe dependency list: (.*)';

-- Added the changes to data_aggregation function for fixing FB case 19177
-- Now the aggregation of collected points is interval based instead of
-- reduction factor based.
CREATE OR REPLACE FUNCTION pem.data_aggregation (aggregate_function text,
							data_timestamp timestamptz[],
							data_value numeric[],
							actual_points int,
							required_points int)
RETURNS TABLE (agg_time timestamp with time zone, agg_value numeric)
AS $$
DECLARE
	start_time timestamptz := NULL;
	end_time timestamptz := NULL;
	diff_interval interval := NULL;
	count int := 0;
	i int := 0;
	data_array numeric[];
	tmp int;
BEGIN
	-- if required points are not given the return actual points
	IF (required_points = 0) THEN
		RETURN QUERY EXECUTE 'SELECT unnest(' || quote_literal(data_timestamp)::varchar || '::timestamptz[]) AS agg_time, unnest(' ||
			quote_literal(data_value)::varchar || '::numeric[]) AS agg_value';
	ELSE
		-- if actual points are less than required points then no need to apply aggregation
		IF (required_points >= actual_points) THEN
			RETURN QUERY EXECUTE 'SELECT unnest(' || quote_literal(data_timestamp)::varchar || '::timestamptz[]) AS agg_time, unnest(' ||
				quote_literal(data_value)::varchar || '::numeric[]) AS agg_value';
		ELSE
			diff_interval = (data_timestamp[actual_points - 1] - data_timestamp[0]) / required_points;
			start_time := data_timestamp[0];
			end_time := data_timestamp[0] + diff_interval;
			WHILE count < actual_points
			LOOP
				agg_time = start_time;
				-- collect the set of points and apply aggregation to it and return the resultant point
				i = 0;
				WHILE data_timestamp[count] <= end_time
				LOOP
					EXIT WHEN count = actual_points;
					data_array[i] = data_value[count];
					i = i + 1;
					count = count + 1;
				END LOOP;

				IF (aggregate_function = 'FIRST') THEN
					agg_value = data_array[0];
				ELSE
					EXECUTE 'SELECT ' || aggregate_function || '(x)
							FROM (SELECT unnest(' || quote_literal(data_array)::varchar || '::numeric[]) AS x) AS y'
							INTO agg_value;
				END IF;
				RETURN NEXT;

				-- reset the data array
				tmp = 0;
				WHILE tmp < i
				LOOP
					data_array[tmp] = NULL;
					tmp = tmp + 1;
				END LOOP;

				-- set the time counters ahead
				start_time := end_time;
				end_time := end_time + diff_interval;
			END LOOP;
		END IF;
	END IF;
	RETURN;
END
$$ LANGUAGE plpgsql;

-- updating data_rollup function to show data points at regular interval.
CREATE OR REPLACE FUNCTION pem.data_rollup(probe_table text,
                                       aggregate_function text,
                                       probe_data_column text,
                                       start_time timestamp with time zone,
                                       end_time timestamp with time zone,
                                       time_interval interval,
				       				   required_points int,
				       				   probe_target_key_list varchar[],
				       				   probe_target_value_list varchar[],
				       				   agentid integer,
				       				   is_capacity_manager boolean)
RETURNS TABLE (aggregated_time timestamp with time zone, aggregated_value numeric)
AS $$
DECLARE
	y_record RECORD;
	data_timestamp timestamptz[];
	data_value numeric[];
	count int;
	curs refcursor;
BEGIN
	-- Create a cursor to store actual points
	OPEN curs FOR EXECUTE  'SELECT metric_time, recorded_value::numeric
							FROM pem.data_reconstruction(' || quote_literal(probe_table) || ','
   										|| quote_literal(probe_data_column) || ','
										|| quote_literal(start_time) || ','
										|| quote_literal(end_time) || ','
										|| quote_literal(time_interval) || ','
										|| quote_literal(probe_target_key_list) || ','
										|| quote_literal(probe_target_value_list)  || ','
                                      	|| quote_literal(agentid)  || ','
                                       	|| quote_literal(is_capacity_manager)  ||
										')';
	count = 0;
	LOOP
		FETCH curs INTO y_record;
		EXIT WHEN NOT FOUND;
		IF (y_record.metric_time IS NOT NULL) THEN
			data_timestamp[count] = y_record.metric_time;
			data_value[count] = y_record.recorded_value;
			count = count + 1;
		END IF;
	END LOOP;

	RETURN QUERY EXECUTE 'SELECT agg_time AS aggregated_time, agg_value AS aggregated_value FROM pem.data_aggregation(' ||
		quote_literal(aggregate_function) || '::text,' || quote_literal(data_timestamp)::varchar || '::timestamptz[],' ||
		quote_literal(data_value)::varchar || '::numeric[],' || quote_literal(count) || '::int,' ||
		quote_literal(required_points) || ')';
END
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION pem.pe_engine(rule_id_array int[], server_database_pair_array text[][]) RETURNS SETOF RECORD
AS $$
DECLARE
	temp_server int;
	prev_server int:= 0;
	database text;
	evaluator_function text;
	function_query text;
	is_server_only boolean:= false;
	rule_name text; server_host text; expert_name text; database_name text; rule_description text; rule_trigger text; rule_recommended_value text; server_description text;
	server_port int:= 0;
	expert_id int:= 0;
	row  RECORD;

BEGIN
	CREATE TEMPORARY TABLE temp_expert_records(server_id int, rule_name text, server_host text, server_description text, server_port int, expert_name text, database_name text, description text, trigger text, recommended_value text, data_name text[], data_value text[], severity int);

	-- Loop through the rule ids
	FOR k IN array_lower(rule_id_array,1) .. array_upper(rule_id_array,1)
	LOOP

		-- Get rule name, description, trigger, recommended value
		SELECT name, description, trigger, recommended_value INTO rule_name,rule_description,rule_trigger,rule_recommended_value FROM pem.pe_rules_text WHERE rule_id = rule_id_array[k];

		-- Get the evaluator function and value of run_on_server_only for rule id
		SELECT expert, evaluator,run_on_server_only INTO expert_id, evaluator_function, is_server_only FROM pem.pe_rules where id = rule_id_array[k];

		-- Get expert name
		SELECT name INTO expert_name FROM pem.pe_experts WHERE id = expert_id;

		-- Reset value of prev server for next rule
		prev_server = 0;

		-- Loop through the no of servers
		FOR i in array_lower(server_database_pair_array,1) .. array_upper(server_database_pair_array,1)
		LOOP

			-- Assumptions: We will always have two dimentions:
			--    First represents server
			--    Second represents database

			temp_server := server_database_pair_array[i][1];
			database := server_database_pair_array[i][2];

			-- Get server name
			SELECT server INTO server_host FROM pem.server WHERE id = temp_server;
			-- Get description and port for server
			SELECT description, port INTO server_description, server_port FROM pem.server WHERE id = temp_server;

			-- if value of is_server_only is true then we have to run this rule on server only
			IF (is_server_only) THEN
				IF (prev_server != temp_server) THEN
					function_query = E'SELECT ' || evaluator_function || '(' || temp_server ||',''' || rule_name ||''');';
					database_name = '-';

					INSERT INTO temp_expert_records(server_id, rule_name, server_host, server_description, server_port, expert_name, database_name, description, trigger, recommended_value, data_name, data_value, severity) VALUES (temp_server, rule_name, server_host, server_description, server_port, expert_name, database_name, rule_description, rule_trigger, rule_recommended_value, '{}', '{}', 0);

					EXECUTE function_query;
					prev_server = temp_server;
				END IF;
			ELSE
				-- run on databases;
				function_query = E'SELECT ' || evaluator_function || '(' || temp_server ||',''' || rule_name ||''',''' || database || ''');';
				database_name = database;

				INSERT INTO temp_expert_records(server_id, rule_name, server_host, server_description, server_port, expert_name, database_name, description, trigger, recommended_value, data_name, data_value, severity) VALUES (temp_server, rule_name, server_host, server_description, server_port, expert_name, database_name, rule_description, rule_trigger, rule_recommended_value, '{}', '{}', 0);

				EXECUTE function_query;
			END IF;

		END LOOP;
	END LOOP;

	FOR row IN SELECT * FROM temp_expert_records ORDER BY server_id, expert_name LOOP
		RETURN NEXT row;
	END LOOP;

	RETURN;
END
$$ LANGUAGE plpgsql;

-- Update the settings probe to log units.
UPDATE pem.probe SET probe_code = 'SELECT name, setting, unit FROM pg_catalog.pg_settings' WHERE internal_name = 'settings';
COMMIT TRANSACTION;
