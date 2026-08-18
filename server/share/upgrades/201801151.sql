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
'SELECT 201801151::integer;'
  LANGUAGE 'sql' IMMUTABLE;
COMMENT ON FUNCTION pem.schema_version() IS 'Returns the version number of the PEM schema';

-- Update threshold unit for global level templates
UPDATE pem.alert_template SET threshold_unit = '#'
WHERE display_name IN ('Agents Down', 'Servers Down', 'Alert Errors')
AND object_type = 50;

-- Update threshold unit for agent level templates
UPDATE pem.alert_template SET threshold_unit = '#'
WHERE display_name IN ('Number of WARNINGS or ERRORS in the audit logfile on agent N in last X hours',
  'Number of WARNINGS in the audit logfile on agent N in last X hours',
  'Number of ERRORS in the audit logfile on agent N in last X hours',
  'Number of WARNINGS or ERRORS in the logfile on agent N in last X hours',
  'Number of WARNINGS in the logfile on agent N in last X hours',
  'Number of ERRORS in the logfile on agent N in last X hours', 'Agent Down',
  'Package version mismatch', 'Number of CPUs running higher than a threshold')
AND object_type = 100;

UPDATE pem.alert_template SET threshold_unit = '%'
WHERE display_name IN ('Disk consumption percentage', 'Disk busy percentage',
  'CPU utilization', 'Load Average per CPU Core (1 minutes)',
  'Load Average per CPU Core (5 minutes)',
  'Load Average per CPU Core (15 minutes)', 'Most used disk percentage',
  'Load Average (1 minute)', 'Load Average (5 minutes)', 'Load Average (15 minutes)',
  'Swap consumption percentage', 'Memory used percentage', 'Free memory percentage')
AND object_type = 100;

UPDATE pem.alert_template SET threshold_unit = 'MB'
WHERE display_name IN ('Disk Consumption', 'Disk Available', 'Swap consumption')
AND object_type = 100;

-- Update threshold unit for server level templates
UPDATE pem.alert_template SET threshold_unit = 'Hours'
WHERE display_name IN ('Last Analyze', 'Last AutoAnalyze', 'Last Vacuum', 'Last AutoVacuum')
AND object_type = 200;

UPDATE pem.alert_template SET threshold_unit = 'MB'
WHERE display_name IN ('Largest table (by multiple of unbloated size)',
  'Largest materialized view (by multiple of unbloated size)')
AND object_type = 200;

UPDATE pem.alert_template SET threshold_unit = '%'
WHERE display_name IN ('Percentage of buffers written by backends',
  'Percentage of buffers written by checkpoint', 'Committed transactions percentage',
  'Dead tuples percentage', 'Shared buffers hit percentage',
  'InfiniteCache buffers hit percentage', 'Hot update percentage',
  'Percentage of buffers written by backends over last N minutes',
  'Index size as a percentage of table size', 'Largest index by table-size percentage')
AND object_type = 200;

UPDATE pem.alert_template SET threshold_unit = '#'
WHERE display_name IN ('Materialized View Count', 'View Count',
  'Unused, non-superuser connections',
  'Unused, non-superuser connections as percentage of max_connections',
  'Ungranted locks', 'Buffers written per second',
  'Buffers allocated per second', 'Tuples fetched', 'Tuples returned', 'Tuples inserted',
  'Tuples updated', 'Tuples deleted', 'Tuples hot updated', 'Sequential Scans',
  'Index Scans', 'Live Tuples', 'Dead Tuples', 'Table Count', 'Sequence Count', 'Function Count',
  'Number of attacks detected in the last N minutes',
  'Number of attacks detected in the last N minutes by username',
  'Number of ERRORS in the logfile on server M in the last X hours',
  'Number of WARNINGS in the logfile on server M in the last X hours',
  'Number of WARNINGS or ERRORS in the logfile on server M in the last X hours',
  'Number of ERRORS in the audit logfile on server M in the last X hours',
  'Number of WARNINGS in the audit logfile on server M in the last X hours',
  'Number of WARNINGS or ERRORS in the audit logfile on server M in the last X hours',
  'Server Down', 'Number of WAL files', 'Number of prepared transactions',
  'Total connections', 'Total connections as percentage of max_connections',
  'Connections in idle state', 'Connections in idle-in-transaction state',
  'Connections in idle-in-transaction state, as a percentage of max_connections',
  'Long-running transactions', 'Audit config mismatch', 'Log config mismatch',
  'Number of WAL archives pending', 'Long-running idle connections',
  'Long-running idle connections and idle transactions', 'Long-running idle transactions',
  'Long-running queries', 'Long-running vacuums', 'Long-running autovacuums',
  'Number of standby servers lag behind the master by write location',
  'Number of standby servers lag behind the master by flush location',
  'Number of standby servers lag behind the master by replay location')
AND object_type = 200;

-- Update threshold unit for database level templates
UPDATE pem.alert_template SET threshold_unit = 'Hours'
WHERE display_name IN ('Last Analyze', 'Last AutoAnalyze', 'Last Vacuum', 'Last AutoVacuum')
AND object_type = 300;

UPDATE pem.alert_template SET threshold_unit = 'MB'
WHERE display_name IN ('Largest table (by multiple of unbloated size)',
  'Largest materialized view (by multiple of unbloated size)')
AND object_type = 300;

UPDATE pem.alert_template SET threshold_unit = '%'
WHERE display_name IN ('Committed transactions percentage',
  'Dead tuples percentage', 'Shared buffers hit percentage',
  'InfiniteCache buffers hit percentage', 'Hot update percentage',
  'Index size as a percentage of table size', 'Largest index by table-size percentage')
AND object_type = 300;

UPDATE pem.alert_template SET threshold_unit = '#'
WHERE display_name IN ('Connections in idle state', 'Connections in idle-in-transaction state',
  'Connections in idle-in-transaction state, as a percentage of max_connections',
  'Tuples fetched', 'Tuples returned', 'Tuples inserted',
  'Tuples updated', 'Tuples deleted', 'Tuples hot updated', 'Sequential Scans',
  'Index Scans', 'Live Tuples', 'Dead Tuples', 'Table Count', 'Sequence Count',
  'Function Count', 'Total connections', 'Long-running transactions',
  'Total connections as percentage of max_connections', 'Long-running idle connections',
  'Long-running idle connections and idle transactions', 'Long-running idle transactions',
  'Long-running queries', 'Long-running vacuums', 'Long-running autovacuums',
  'Materialized View Count', 'View Count', 'Ungranted locks',
  'Number of attacks detected in the last N minutes',
  'Number of attacks detected in the last N minutes by username',
  'Total rows lagging in xdb multi master replication',
  'Total rows lagging in xdb single master replication')
AND object_type = 300;

-- Update threshold unit for schema level templates
UPDATE pem.alert_template SET threshold_unit = 'Hours'
WHERE display_name IN ('Last Analyze', 'Last AutoAnalyze', 'Last Vacuum', 'Last AutoVacuum')
AND object_type = 400;

UPDATE pem.alert_template SET threshold_unit = 'MB'
WHERE display_name IN ('Largest table (by multiple of unbloated size)',
  'Largest materialized view (by multiple of unbloated size)',
  'Materialized view size as a multiple of ubloated size')
AND object_type = 400;

UPDATE pem.alert_template SET threshold_unit = '%'
WHERE display_name IN ('Dead tuples percentage', 'Hot update percentage',
  'Index size as a percentage of table size', 'Largest index by table-size percentage')
AND object_type = 400;

UPDATE pem.alert_template SET threshold_unit = '#'
WHERE display_name IN ('Dead Tuples', 'Function Count', 'Index Scans', 'Live Tuples',
  'Materialized View Count', 'Sequence Count', 'Sequential Scans', 'Table Count',
  'Tuples deleted', 'Tuples hot updated', 'Tuples inserted', 'Tuples updated',
  'View Count')
AND object_type = 400;

-- Update threshold unit for table level templates
UPDATE pem.alert_template SET threshold_unit = 'Hours'
WHERE display_name IN ('Last Analyze', 'Last AutoAnalyze', 'Last Vacuum', 'Last AutoVacuum')
AND object_type = 500;

UPDATE pem.alert_template SET threshold_unit = 'MB'
WHERE display_name IN ('Table size as a multiple of ubloated size')
AND object_type = 500;

UPDATE pem.alert_template SET threshold_unit = '%'
WHERE display_name IN ('Dead tuples percentage', 'Hot update percentage',
  'Index size as a percentage of table size')
AND object_type = 500;

UPDATE pem.alert_template SET threshold_unit = '#'
WHERE display_name IN ('Dead Tuples', 'Index Scans', 'Live Tuples',
  'Row Count', 'Sequential Scans', 'Tuples deleted', 'Tuples hot updated',
  'Tuples inserted', 'Tuples updated')
AND object_type = 500;

UPDATE pem.alert_template SET threshold_unit = '%'
WHERE display_name IN ('Index size as a percentage of table size')
AND object_type = 600;

-- Function unit_converter(text, text) which convert value
-- of one type to another. It is used on Alert details and Alert status
-- dashboard to display units with alert values.
CREATE OR REPLACE FUNCTION pem.unit_converter(val numeric, unit text)
RETURNS text AS $$
DECLARE
    temp_unit text:= '';
	temp_val text;
BEGIN

    IF unit IS NULL OR unit = '#' THEN
	    val = val::decimal(30, 2);
	    RETURN trim(trailing '0' FROM val::text)::numeric;
	END IF;

    unit = trim(unit);
    IF unit = '%' THEN
	    val = val::decimal(30, 2);
	    RETURN trim(trailing '0' FROM val::text)::numeric || ' %';
	END IF;

    temp_val = val::decimal(30, 2);
	IF upper(unit) = 'KB' THEN
	    -- Convert value to MB OR GB
	    IF (val::decimal / 1024::decimal) >= 1.00 THEN
	        val = val::decimal / 1024::decimal;
            IF (val::decimal / 1024::decimal) >= 1.00 THEN
			    temp_unit = ' GB';
                temp_val = val::decimal / 1024::decimal;
            ELSE
			    temp_unit = ' MB';
                temp_val = val::decimal(30, 2);
            END IF;

        ELSE
		    temp_unit = ' KB';
            temp_val = val::decimal(30, 2);
        END IF;
	END IF;

	IF upper(unit) = 'MB' THEN
	    -- Convert value to GB
	    IF (val::decimal / 1024::decimal) >= 1.00 THEN
		    temp_unit = ' GB';
            temp_val = val::decimal / 1024::decimal;
        ELSE
		    temp_unit = ' MB';
            temp_val = val::decimal(30, 2);
        END IF;
	END IF;

    IF upper(unit) = 'GB' THEN
		temp_unit = ' GB';
        temp_val = val::decimal(30, 2);
	END IF;

    IF upper(unit) = 'HOURS' THEN
		temp_unit = ' hrs';
        temp_val = val::decimal(30, 2);
	END IF;


	IF upper(unit) = 'MINUTES' THEN
		temp_unit = ' mins';
        temp_val = val::decimal(30, 2);
	END IF;

	IF upper(unit) = 'DAYS' THEN
		temp_unit = ' days';
        temp_val = val::decimal(30, 2);
	END IF;

    RETURN trim(trailing '0' FROM temp_val)::numeric || temp_unit;
END
$$ LANGUAGE plpgsql;

-- Fixed #
CREATE OR REPLACE FUNCTION pem.pe_engine(
    rule_id_array integer[],
    server_database_pair_array text[])
  RETURNS SETOF record AS
$BODY$
DECLARE
	temp_server int;
	prev_server int:= 0;
	database text;
	evaluator_function text;
	function_query text;
	is_server_only boolean:= false;
	is_run_on_remote_server boolean:= true;
	remote_monitoring boolean:= false;
	execute_rule boolean:= true;
	rule_name text; server_host text; expert_name text; database_name text; rule_description text; rule_trigger text; rule_recommended_value text; server_description text;
	server_port int:= 0;
	rule_id int := 0;
	expert_id int:= 0;
	row  RECORD;

BEGIN
	DROP TABLE IF EXISTS temp_expert_records;
	CREATE TEMPORARY TABLE temp_expert_records(server_id int, rule_id int, rule_name text, server_host text, server_description text, server_port int, expert_name text, database_name text, description text, trigger text, recommended_value text, data_name text[], data_value text[], severity int) ON COMMIT DROP;
	-- Loop through the rule ids
	FOR k IN array_lower(rule_id_array,1) .. array_upper(rule_id_array,1)
	LOOP
		-- Get rule name, description, trigger, recommended value
		SELECT name, description, trigger, recommended_value INTO rule_name,rule_description,rule_trigger,rule_recommended_value FROM pem.pe_rules_text pe_text WHERE pe_text.rule_id = rule_id_array[k];

		-- Get the evaluator function and value of "run_on_server_only" and "run_on_remote_server" for rule id
		SELECT expert, evaluator, run_on_server_only, run_on_remote_server INTO expert_id, evaluator_function, is_server_only, is_run_on_remote_server FROM pem.pe_rules where id = rule_id_array[k];

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
			SELECT server, is_remote_monitoring INTO server_host, remote_monitoring FROM pem.server WHERE id = temp_server;
			-- Get description and port for server
			SELECT description, port INTO server_description, server_port FROM pem.server WHERE id = temp_server;

			-- In case of remotely monitored server, we will check the value of "run_on_remote_server"
			-- if it is true then only we execute the rule else skip it.
			execute_rule = true;
			IF (remote_monitoring) THEN
				IF (is_run_on_remote_server) THEN
					execute_rule = true;
				ELSE
					execute_rule = false;
				END IF;
			END IF;

			IF  (execute_rule) THEN
				-- if value of is_server_only is true then we have to run this rule on server only
				IF (is_server_only) THEN
					IF (prev_server != temp_server) THEN
						function_query = E'SELECT ' || evaluator_function || '(' || temp_server ||',''' || rule_name ||''');';
						database_name = '-';

						INSERT INTO temp_expert_records(server_id, rule_id, rule_name, server_host, server_description, server_port, expert_name, database_name, description, trigger, recommended_value, data_name, data_value, severity) VALUES (temp_server, rule_id_array[k], rule_name, server_host, server_description, server_port, expert_name, database_name, rule_description, rule_trigger, rule_recommended_value, '{}', '{}', 0);

						EXECUTE function_query;
						prev_server = temp_server;
					END IF;
				ELSE
					-- run on databases;
					function_query = E'SELECT ' || evaluator_function || '(' || temp_server ||',''' || rule_name ||''',''' || database || ''');';
					database_name = database;

					INSERT INTO temp_expert_records(server_id, rule_id, rule_name, server_host, server_description, server_port, expert_name, database_name, description, trigger, recommended_value, data_name, data_value, severity) VALUES (temp_server, rule_id_array[k], rule_name, server_host, server_description, server_port, expert_name, database_name, rule_description, rule_trigger, rule_recommended_value, '{}', '{}', 0);

					EXECUTE function_query;
				END IF;
			END IF;
		END LOOP;
	END LOOP;

	FOR row IN SELECT * FROM temp_expert_records ORDER BY server_id, expert_name, rule_name LOOP
		RETURN NEXT row;
	END LOOP;

	RETURN;
END
$BODY$
LANGUAGE plpgsql;

-- Fixed PEM-474
CREATE OR REPLACE FUNCTION pem.process_one_alert() RETURNS BOOL AS $$
DECLARE
	err			text;
	sql			text;
	state			pem.alert_state;
	sql_ret			numeric;
	alert_rec		record;
	locked_alert		bool;
	probe_disabled_err	text;
	zero_rows_err		text;
	probe_enabled		bool;
	all_probes_enabled	bool;
	alert_state_since	timestamp with time zone;
	reminder_interval	integer;
	subject			text;
	message			text;
	send_mail_val		bool;
	min_probe_interval	integer;
	probe_interval		integer;
	default_flapping_detection_state_change integer;
	down_objects_list text;
	template_name text;
	mail_group_id integer[];
	alert_info    text;
BEGIN
	probe_disabled_err = 'Required probe(s) ';
	zero_rows_err = 'Zero rows returned';

	locked_alert = false;

	FOR alert_rec in	SELECT al.*, ast.current_state AS state, at.sql, at.display_name AS template_name,
								at.probe_dependency_list, ast.state_change_count
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
						AND CASE WHEN al.agent_id IN (-1 , 0) THEN TRUE
							ELSE al.agent_id IN (SELECT id FROM pem.agent WHERE active AND NOT alert_blackout)
							END
						AND CASE WHEN (al.server_id IS NULL) OR (al.server_id = 0) THEN TRUE
							ELSE al.server_id IN
									(SELECT id FROM pem.server WHERE active AND NOT alert_blackout
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
		SELECT v.enabled INTO probe_enabled FROM pem.probe_target_view v LEFT JOIN pem.probe p ON p.id = v.probe_id
		WHERE v.probe_internal_name = alert_rec.probe_dependency_list[i]
		AND CASE WHEN p.target_type_id = 100 THEN (v.agent_id = alert_rec.agent_id)
			WHEN p.target_type_id = 200 THEN (v.server_id = alert_rec.server_id)
			WHEN p.target_type_id = 300 THEN (v.server_id = alert_rec.server_id AND v.database_name = alert_rec.database_name)
			ELSE (v.server_id = alert_rec.server_id AND v.database_name = alert_rec.database_name
				AND v.parameter_value_list[3] = alert_rec.schema_name)
			END;
		IF NOT probe_enabled THEN
			probe_disabled_err = probe_disabled_err || alert_rec.probe_dependency_list[i] || ',';
			all_probes_enabled = false;
		END IF;

		-- Get minimum probe interval from all dependent probes
		SELECT default_execution_frequency INTO probe_interval FROM pem.probe WHERE internal_name = alert_rec.probe_dependency_list[i];
		IF (probe_interval <  min_probe_interval) OR (i = 1) THEN
			min_probe_interval = probe_interval;
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
			    err = '';
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
		PERFORM pg_catalog.pg_advisory_unlock(0, alert_rec.id);

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

	-- Get group id's to send email
	SELECT ARRAY(SELECT DISTINCT UNNEST(pem.get_email_group_ids(alert_rec.id, state::text, state::text))) INTO mail_group_id;

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
	 *         do nothing
	 *
	 *     If severity_level decreases or goes from not-null to null
	 *         do nothing.
	 * end if
	 */
	IF (alert_rec.acknowledged) THEN
		IF (state IS NULL AND alert_rec.state IS NULL) THEN
			-- State has been lower than LOW, two times in a row.
			UPDATE pem.alert
			SET acknowledged = false
			WHERE id = alert_rec.id;

			--send alert cleared SMTP notification
			IF alert_rec.send_email THEN
				-- Create subject and message
				SELECT subject_mail, message_mail INTO subject, message FROM pem.create_email(alert_rec.id, 'Alert Cleared');
				send_mail_val = pem.send_email(mail_group_id, subject, message);
				IF send_mail_val THEN
					-- update the time of mail send.
					UPDATE pem.alert SET last_mail_send = now() WHERE id = alert_rec.id;
				END IF;
			END IF;
		END IF;
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

	-- Check for reminder notification
	SELECT value INTO reminder_interval FROM pem.config WHERE param = 'reminder_notification_interval';
	SELECT current_state_since INTO alert_state_since FROM pem.alert_status WHERE alert_id = alert_rec.id;
	IF alert_rec.send_email AND (NOT alert_rec.acknowledged) AND (alert_state_since IS NOT NULL) AND (state IS NOT NULL) AND (NOT alert_rec.flapping_detected)
	AND ((now() - alert_state_since) >= (reminder_interval||'hours')::interval)
	AND ((now() - alert_rec.last_mail_send) >= (reminder_interval||'hours')::interval) THEN

		-- Create subject and message
		SELECT subject_mail, message_mail INTO subject, message FROM pem.create_email(alert_rec.id, 'Alert Reminder');
		SELECT info INTO alert_info FROM pem.alert_status WHERE alert_id = alert_rec.id;
		message = regexp_replace(message, '%CurrentValue%', COALESCE(sql_ret, 0)::text);
		message = regexp_replace(message, '%CurrentState%', state::text);
		message = regexp_replace(message, '%AlertingSince%', alert_state_since::text);

		-- Get the list of down objetcs
		down_objects_list = pem.get_down_objects_list(alert_rec.template_name);
		message = regexp_replace(message, '%DownObjects%', down_objects_list::text);
		message = regexp_replace(message, '%DetailInfo%', COALESCE(alert_info, 'None')::text);

		send_mail_val = pem.send_email(mail_group_id, subject, message);
		IF send_mail_val THEN
			-- update the time of mail send.
			UPDATE pem.alert SET last_mail_send = now() WHERE id = alert_rec.id;
		END IF;
	END IF;

	SELECT value INTO default_flapping_detection_state_change FROM pem.config WHERE param = 'flapping_detection_state_change';

	IF (NOT alert_rec.flapping_detected) THEN
		--Flapping start is true when more than N state changes have occurred over (N + 1) * (min(probe_interval) * 2) seconds
		IF ((now() - alert_rec.last_flapping_detection_processed) >=
		(((default_flapping_detection_state_change + 1) * (min_probe_interval * 2)) * '1 second'::interval)) THEN

			UPDATE pem.alert SET last_flapping_detection_processed = now() WHERE id = alert_rec.id;
			UPDATE pem.alert_status SET state_change_count = 0 WHERE alert_id = alert_rec.id;

			IF (alert_rec.state_change_count > default_flapping_detection_state_change) THEN
				UPDATE pem.alert SET flapping_detected = 't' WHERE id = alert_rec.id;
			END IF;
		END IF;
	ELSE
		-- Flapping end is true when zero state changes have occurred over 2N * min(probe_interval) seconds
		IF ((now() - alert_rec.last_flapping_detection_processed) >=
		((2* default_flapping_detection_state_change * min_probe_interval) * '1 second'::interval)) THEN
			UPDATE pem.alert SET last_flapping_detection_processed = now() WHERE id = alert_rec.id;

			IF (alert_rec.state_change_count = 0) THEN
				UPDATE pem.alert SET flapping_detected = 'f' WHERE id = alert_rec.id;
			END IF;
		END IF;
	END IF;

	PERFORM pg_catalog.pg_advisory_unlock(0, alert_rec.id);
	RETURN true;
END;
$$ LANGUAGE plpgsql;

COMMIT TRANSACTION;
