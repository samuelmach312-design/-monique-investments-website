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
'SELECT 201802211::integer;'
  LANGUAGE 'sql' IMMUTABLE;
COMMENT ON FUNCTION pem.schema_version() IS 'Returns the version number of the PEM schema';

-- Added new column to store display value
ALTER TABLE pem.alert_status ADD COLUMN display_value text DEFAULT NULL;

-- update alert_template sql for Last Vacuum and Last AutoVacuum
-- update alert_template sql for Last Vacuum
UPDATE pem.alert_template
SET sql =
$sql$
SELECT
	CASE WHEN last_vacuum IS NULL THEN
		EXTRACT(EPOCH FROM (capture_time - '1970-01-01'::timestamp)::interval)/3600
	ELSE
		EXTRACT(EPOCH FROM (capture_time - last_vacuum)::interval)/3600
	END AS current_value,
	CASE WHEN last_vacuum IS NULL THEN
		'Never ran'
	ELSE
		NULL
	END AS display_value
FROM pemdata.table_statistics
WHERE	server_id = ${server_id}
AND		database_name = '${database_name}'
AND		schema_name = '${schema_name}'
AND		table_name = '${object_name}'
$sql$
WHERE display_name = 'Last Vacuum' AND object_type = 500;

UPDATE pem.alert_template
SET sql =
$sql$
SELECT
	CASE WHEN last_vacuum IS NULL THEN
		EXTRACT(EPOCH FROM (capture_time - '1970-01-01'::timestamp)::interval)/3600
	ELSE
		EXTRACT(EPOCH FROM (capture_time - last_vacuum)::interval)/3600
	END AS current_value,
	CASE WHEN last_vacuum IS NULL THEN
		'Never ran'
	ELSE
		NULL
	END AS display_value
FROM pemdata.table_statistics
WHERE	server_id = ${server_id}
AND		database_name = '${database_name}'
AND		schema_name = '${schema_name}'
ORDER BY last_vacuum DESC NULLS LAST LIMIT 1
$sql$
WHERE display_name = 'Last Vacuum' AND object_type = 400;

UPDATE pem.alert_template
SET sql =
$sql$
SELECT
	CASE WHEN last_vacuum IS NULL THEN
		EXTRACT(EPOCH FROM (capture_time - '1970-01-01'::timestamp)::interval)/3600
	ELSE
		EXTRACT(EPOCH FROM (capture_time - last_vacuum)::interval)/3600
	END AS current_value,
	CASE WHEN last_vacuum IS NULL THEN
		'Never ran'
	ELSE
		NULL
	END AS display_value
FROM pemdata.table_statistics
WHERE	server_id = ${server_id}
AND		database_name = '${database_name}'
ORDER BY last_vacuum DESC NULLS LAST LIMIT 1
$sql$
WHERE display_name = 'Last Vacuum' AND object_type = 300;


UPDATE pem.alert_template
SET sql =
$sql$
SELECT
	CASE WHEN last_vacuum IS NULL THEN
		EXTRACT(EPOCH FROM (capture_time - '1970-01-01'::timestamp)::interval)/3600
	ELSE
		EXTRACT(EPOCH FROM (capture_time - last_vacuum)::interval)/3600
	END AS current_value,
	CASE WHEN last_vacuum IS NULL THEN
		'Never ran'
	ELSE
		NULL
	END AS display_value
FROM pemdata.table_statistics
WHERE	server_id = ${server_id}
ORDER BY last_vacuum DESC NULLS LAST LIMIT 1
$sql$
WHERE display_name = 'Last Vacuum' AND object_type = 200;

--update alert_template sql for Last AutoVacuum

UPDATE pem.alert_template
SET sql =
$sql$
SELECT
	CASE WHEN last_autovacuum IS NULL THEN
		EXTRACT(EPOCH FROM (capture_time - '1970-01-01'::timestamp)::interval)/3600
	ELSE
		EXTRACT(EPOCH FROM (capture_time - last_autovacuum)::interval)/3600
	END AS current_value,
	CASE WHEN last_autovacuum IS NULL THEN
		'Never ran'
	ELSE
		NULL
	END AS display_value
FROM pemdata.table_statistics
WHERE	server_id = ${server_id}
AND		database_name = '${database_name}'
AND		schema_name = '${schema_name}'
AND		table_name = '${object_name}'
$sql$
WHERE display_name = 'Last AutoVacuum' AND object_type = 500;

UPDATE pem.alert_template
SET sql =
$sql$
SELECT
	CASE WHEN last_autovacuum IS NULL THEN
		EXTRACT(EPOCH FROM (capture_time - '1970-01-01'::timestamp)::interval)/3600
	ELSE
		EXTRACT(EPOCH FROM (capture_time - last_autovacuum)::interval)/3600
	END AS current_value,
	CASE WHEN last_autovacuum IS NULL THEN
		'Never ran'
	ELSE
		NULL
	END AS display_value
FROM pemdata.table_statistics
WHERE	server_id = ${server_id}
AND		database_name = '${database_name}'
AND		schema_name = '${schema_name}'
ORDER BY last_autovacuum DESC NULLS LAST LIMIT 1
$sql$
WHERE display_name = 'Last AutoVacuum' AND object_type = 400;

UPDATE pem.alert_template
SET sql =
$sql$
SELECT
	CASE WHEN last_autovacuum IS NULL THEN
		EXTRACT(EPOCH FROM (capture_time - '1970-01-01'::timestamp)::interval)/3600
	ELSE
		EXTRACT(EPOCH FROM (capture_time - last_autovacuum)::interval)/3600
	END AS current_value,
	CASE WHEN last_autovacuum IS NULL THEN
		'Never ran'
	ELSE
		NULL
	END AS display_value
FROM pemdata.table_statistics
WHERE	server_id = ${server_id}
AND		database_name = '${database_name}'
ORDER BY last_autovacuum DESC NULLS LAST LIMIT 1
$sql$
WHERE display_name = 'Last AutoVacuum' AND object_type = 300;

UPDATE pem.alert_template
SET sql =
$sql$
SELECT
	CASE WHEN last_autovacuum IS NULL THEN
		EXTRACT(EPOCH FROM (capture_time - '1970-01-01'::timestamp)::interval)/3600
	ELSE
		EXTRACT(EPOCH FROM (capture_time - last_autovacuum)::interval)/3600
	END AS current_value,
	CASE WHEN last_autovacuum IS NULL THEN
		'Never ran'
	ELSE
		NULL
	END AS display_value
FROM pemdata.table_statistics
WHERE	server_id = ${server_id}
ORDER BY last_autovacuum DESC NULLS LAST LIMIT 1
$sql$
WHERE display_name = 'Last AutoVacuum' AND object_type = 200;

--function process_one_alert modified to show display value as 'Never ran'
--for Last Vacuum and Last AutoVacuum alerts if it's not activated
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
	sql_curs			REFCURSOR;
	sql_rec       RECORD;
	hs_row        RECORD;
	first_time    boolean := FALSE;
	sql_ret_display text := '';

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
			OPEN sql_curs FOR EXECUTE sql;
			LOOP
				FETCH NEXT FROM sql_curs INTO sql_rec;
				EXIT WHEN NOT FOUND;
				-- Loop through the output of the query using hstore.
				FOR hs_row IN SELECT kv."key", kv."value" FROM each(hstore(sql_rec)) kv
				LOOP
					-- First column is our curernt value and second column is the display
					-- value if provided in the SQL query.
					IF first_time IS FALSE THEN
						sql_ret := COALESCE(hs_row."value", NULL);
						first_time := TRUE;
					ELSE
						sql_ret_display := COALESCE(hs_row."value", '');
					END IF;
				END LOOP;
			END LOOP;
			CLOSE sql_curs;
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
		display_value = sql_ret_display,
		current_state = state, -- may be NULL
		current_state_since =	CASE
								WHEN state IS DISTINCT FROM alert_rec.state
								THEN now()
								ELSE current_state_since
								END
	WHERE alert_id = alert_rec.id;

	-- If there wasn't any status row for this alert already, then populate one.
	IF (NOT FOUND) THEN
		INSERT INTO pem.alert_status("alert_id", "current_value", "current_state",
		    "current_state_since", "last_processed", "display_value")
		VALUES (alert_rec.id, sql_ret, state,
				CASE
				WHEN state IS NOT NULL
				THEN now()
				ELSE NULL
				END,
				now(), sql_ret_display);
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
		message = regexp_replace(message, '%CurrentState%', state::text);
		message = regexp_replace(message, '%AlertingSince%', alert_state_since::text);
		CASE WHEN sql_ret_display IS NOT NULL OR sql_ret_display != '' THEN
			message = regexp_replace(message, '%CurrentValue%', COALESCE(sql_ret_display, 0)::text);
		ELSE
			message = regexp_replace(message, '%CurrentValue%', COALESCE(sql_ret, 0)::text);
		END CASE;

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

CREATE OR REPLACE FUNCTION pem.send_notifications() RETURNS trigger AS $$
DECLARE
	subject text;
	message text;
	mail_group_id integer[];
	is_send_email boolean:= false;
	is_acknowledged boolean:= false;
	send_mail_val boolean:= false;
	is_flapping_detected boolean:= false;
	is_send_trap boolean:= false;
	trap_oid text;
	enterprise_oid text;
	trap_version integer:= 2;
	varbinding_oid text;
	varbinding_value text;
	send_trap_val boolean:= false;
	templateid integer;
	template_name text;
	down_objects_list text;
	agentid integer;
	low_trap boolean:= false;
	med_trap boolean:= false;
	high_trap boolean:= false;
	is_execute_script boolean:= false;
	is_execute_on_clear boolean:= false;
	is_execute_on_pem_server boolean:= false;
	code text;
	is_submit_to_nagios boolean:= false;
	passive_check_result_text text;
	submit_to_nagios_val boolean:= false;
	alert_curr_value text;
BEGIN
	-- Get alert details
	SELECT
		agent_id, template_id, send_email, acknowledged, flapping_detected, send_trap, snmp_trap_version, low_send_trap, med_send_trap,
		high_send_trap, execute_script, execute_script_on_clear, execute_script_on_pem_server, script_code, submit_to_nagios
	INTO
		agentid, templateid, is_send_email, is_acknowledged, is_flapping_detected, is_send_trap, trap_version, low_trap, med_trap,
		high_trap, is_execute_script, is_execute_on_clear, is_execute_on_pem_server, code, is_submit_to_nagios
	FROM
		pem.alert
	WHERE
		id = NEW.alert_id;

	-- Get the template name
	SELECT display_name INTO template_name FROM pem.alert_template WHERE id = templateid;

	-- Get the list of Agents/Servers Down
	down_objects_list = pem.get_down_objects_list(template_name);

	-- Get the current value of alert
	CASE WHEN COALESCE(NEW.display_value, '')::text != '' THEN
		alert_curr_value = COALESCE(NEW.display_value, '')::text;
	ELSE
		alert_curr_value = COALESCE(NEW.current_value, 0)::text;
	END CASE;

	IF ((TG_OP = 'INSERT') AND (NEW.current_state IS NOT NULL)) THEN
		-- Update state change count
		UPDATE pem.alert_status SET state_change_count = state_change_count + 1 WHERE alert_id = NEW.alert_id;

		-- Get group id's to send email
		SELECT ARRAY(SELECT DISTINCT UNNEST(pem.get_email_group_ids(NEW.alert_id, NEW.current_state::text, ''))) INTO mail_group_id;

		-- Check whether to send trap according to alert level low, med and high.
		IF (NEW.current_state IS NOT NULL) AND (NEW.current_state::text = 'LOW') AND low_trap THEN
			is_send_trap = true;
		ELSIF (NEW.current_state IS NOT NULL) AND (NEW.current_state::text = 'MEDIUM') AND med_trap THEN
			is_send_trap = true;
		ELSIF (NEW.current_state IS NOT NULL) AND (NEW.current_state::text = 'HIGH') AND high_trap THEN
			is_send_trap = true;
		ELSE
			is_send_trap = false;
		END IF;

		-- SMTP Notifications
		IF is_send_email AND (NOT is_acknowledged) AND (NOT is_flapping_detected) THEN
			-- Create subject and message
			SELECT subject_mail, message_mail INTO subject, message FROM pem.create_email(NEW.alert_id, 'Alert Detected');
			subject = regexp_replace(subject, '%AlertType%', NEW.current_state::text);
			message = regexp_replace(message, '%CurrentValue%', alert_curr_value);
			message = regexp_replace(message, '%AlertDetected%', now()::text);
			message = regexp_replace(message, '%DownObjects%', down_objects_list::text);
			message = regexp_replace(message, '%DetailInfo%', COALESCE(NEW.info, 'None')::text);

			-- send emails.
			send_mail_val = pem.send_email(mail_group_id, subject, message);
			IF send_mail_val THEN
				-- update the time of mail send.
				UPDATE pem.alert SET last_mail_send = now() WHERE id = NEW.alert_id;
			END IF;
		END IF;

		-- SNMP Notifications
		IF is_send_trap AND (NOT is_acknowledged) AND (NOT is_flapping_detected) THEN
			-- Create SNMP trap objects
			SELECT
				snmp_trap_oid, snmp_enterprise_oid, snmp_varbinding_oid, snmp_varbinding_value
			INTO
				trap_oid, enterprise_oid, varbinding_oid, varbinding_value
			FROM
				pem.create_trap(NEW.alert_id);

			-- Append varbinding values
			varbinding_value = varbinding_value || '|NULL|' || alert_curr_value || '|NULL|';
			IF NEW.current_state IS NULL THEN
				varbinding_value = varbinding_value || '|CLEAR';
			ELSE
				varbinding_value = varbinding_value || NEW.current_state::text;
			END IF;
			-- Append current timestamp
			varbinding_value = varbinding_value || '|' || now()::text;

			-- Special handling for "Agents Down" and "Servers Down" alert
			IF (template_name = 'Agents Down') OR  (template_name = 'Servers Down') THEN
				varbinding_oid = varbinding_oid || '|' || enterprise_oid || '.7.15';
				varbinding_value = varbinding_value || '|' || down_objects_list::text;
			END IF;

			-- Check if detailed information is available then add variable binding
			IF NEW.info IS NOT NULL THEN
				varbinding_oid = varbinding_oid || '|' || enterprise_oid || '.7.16';
				varbinding_value = varbinding_value || '|' || COALESCE(NEW.info, 'None')::text;
			END IF;

			-- Send SNMP traps
			send_trap_val = pem.send_snmptrap(trap_oid, enterprise_oid, trap_version, varbinding_oid, varbinding_value);
		END IF;

		-- Script Execution
		IF is_execute_script AND (NOT is_acknowledged) AND (NOT is_flapping_detected) THEN
			PERFORM pem.create_script_job(NEW.alert_id, alert_curr_value, NEW.current_state::text, ''::text, is_execute_on_pem_server, code);
		END IF;

		-- submit to Nagios
		IF is_submit_to_nagios AND (NOT is_acknowledged) AND (NOT is_flapping_detected) THEN

			SELECT passive_check_result INTO passive_check_result_text FROM pem.create_passive_service_check_result(NEW.alert_id, 'Alert Detected',
															alert_curr_value,
															NEW.current_state::text);
			submit_to_nagios_val = pem.submit_to_nagios(passive_check_result_text);
		END IF;
	END IF;

	IF ((TG_OP = 'UPDATE') AND (NEW.current_state IS DISTINCT FROM OLD.current_state)) THEN
		-- Update state change count
		UPDATE pem.alert_status SET state_change_count = state_change_count + 1 WHERE alert_id = NEW.alert_id;

		-- Get group id's to send email
		SELECT ARRAY(SELECT DISTINCT UNNEST(pem.get_email_group_ids(NEW.alert_id, NEW.current_state::text, OLD.current_state::text))) INTO mail_group_id;

		-- Check whether to send trap according to alert level low, med and high.
		IF (NEW.current_state IS NOT NULL) AND (NEW.current_state::text = 'LOW' OR OLD.current_state::text = 'LOW') AND low_trap THEN
			is_send_trap = true;
		ELSIF (NEW.current_state IS NOT NULL) AND (NEW.current_state::text = 'MEDIUM' OR OLD.current_state::text = 'MEDIUM') AND med_trap THEN
			is_send_trap = true;
		ELSIF (NEW.current_state IS NOT NULL) AND (NEW.current_state::text = 'HIGH' OR OLD.current_state::text = 'HIGH') AND high_trap THEN
			is_send_trap = true;
		ELSIF (NEW.current_state IS NULL) AND (OLD.current_state IS NOT NULL) AND is_send_trap THEN
			is_send_trap = true;
		ELSE
			is_send_trap = false;
		END IF;

		-- SMTP Notifications
		IF is_send_email AND (NOT is_acknowledged) AND (NOT is_flapping_detected) THEN
			-- If current state is NULL means alert is cleared.
			IF (NEW.current_state IS NOT NULL) THEN
				-- if OLD current_state is not null means alert level changed.
				IF (OLD.current_state IS NOT NULL AND (OLD.current_state > NEW.current_state)) THEN
					-- Create subject and message
					SELECT subject_mail, message_mail INTO subject, message FROM pem.create_email(NEW.alert_id, 'Alert Level Decreased');
					message = regexp_replace(message, '%CurrentState%', NEW.current_state::text);
					message = regexp_replace(message, '%OldState%', OLD.current_state::text);
					message = regexp_replace(message, '%StateChanged%', now()::text);
				ELSIF (OLD.current_state IS NOT NULL AND (OLD.current_state < NEW.current_state)) THEN
					-- Create subject and message
					SELECT subject_mail, message_mail INTO subject, message FROM pem.create_email(NEW.alert_id, 'Alert Level Increased');
					message = regexp_replace(message, '%CurrentState%', NEW.current_state::text);
					message = regexp_replace(message, '%OldState%', OLD.current_state::text);
					message = regexp_replace(message, '%StateChanged%', now()::text);
				ELSE
					-- Create subject and message
					SELECT subject_mail, message_mail INTO subject, message FROM pem.create_email(NEW.alert_id, 'Alert Detected');
					subject = regexp_replace(subject, '%AlertType%', NEW.current_state::text);
					message = regexp_replace(message, '%AlertDetected%', now()::text);
				END IF;
			ELSE
				-- Create subject and message
				SELECT subject_mail, message_mail INTO subject, message FROM pem.create_email(NEW.alert_id, 'Alert Cleared');
				message = regexp_replace(message, '%AlertCleared%', now()::text);
			END IF;

			message = regexp_replace(message, '%CurrentValue%', alert_curr_value);
			message = regexp_replace(message, '%DownObjects%', down_objects_list::text);
			message = regexp_replace(message, '%DetailInfo%', COALESCE(NEW.info, 'None')::text);

			-- send emails.
			send_mail_val = pem.send_email(mail_group_id, subject, message);
			IF send_mail_val THEN
				-- update the time of mail send.
				UPDATE pem.alert SET last_mail_send = now() WHERE id = NEW.alert_id;
			END IF;
		END IF;

		-- SNMP Notifications
		IF is_send_trap AND (NOT is_acknowledged) AND (NOT is_flapping_detected) THEN
			-- Create SNMP trap objects
			SELECT
				snmp_trap_oid, snmp_enterprise_oid, snmp_varbinding_oid, snmp_varbinding_value
			INTO
				trap_oid, enterprise_oid, varbinding_oid, varbinding_value
			FROM
				pem.create_trap(NEW.alert_id);

			-- Append varbinding values
			varbinding_value = varbinding_value || '|' || COALESCE(OLD.current_value, 0)::text || '|' || alert_curr_value;

			IF OLD.current_state IS NULL THEN
				varbinding_value = varbinding_value || '|CLEAR';
			ELSE
				varbinding_value = varbinding_value || '|' || OLD.current_state::text;
			END IF;

			IF NEW.current_state IS NULL THEN
				varbinding_value = varbinding_value || '|CLEAR';
			ELSE
				varbinding_value = varbinding_value || '|' || NEW.current_state::text;
			END IF;
			-- Append current timestamp
			varbinding_value = varbinding_value || '|' || now()::text;

			-- Special handling for "Agents Down" and "Servers Down" alert
			IF (template_name = 'Agents Down') OR  (template_name = 'Servers Down') THEN
				varbinding_oid = varbinding_oid || '|' || enterprise_oid || '.7.15';
				varbinding_value = varbinding_value || '|' || down_objects_list::text;
			END IF;

			-- Check if detailed information is available then add variable binding
			IF NEW.info IS NOT NULL THEN
				varbinding_oid = varbinding_oid || '|' || enterprise_oid || '.7.16';
				varbinding_value = varbinding_value || '|' || COALESCE(NEW.info, 'None')::text;
			END IF;

			-- Send SNMP traps
			send_trap_val = pem.send_snmptrap(trap_oid, enterprise_oid, trap_version, varbinding_oid, varbinding_value);
		END IF;

		-- Script Execution
		IF is_execute_script AND (NOT is_acknowledged) AND (NOT is_flapping_detected) THEN
			-- If current state is NULL means alert is cleared then need to check the value of is_execute_on_clear flag.
			IF (NEW.current_state IS NULL) THEN
				IF is_execute_on_clear THEN
					PERFORM pem.create_script_job(NEW.alert_id, alert_curr_value, NEW.current_state::text, 'CLEAR'::text, is_execute_on_pem_server, code);
				END IF;
			ELSE
				PERFORM pem.create_script_job(NEW.alert_id, alert_curr_value, NEW.current_state::text, OLD.current_state::text, is_execute_on_pem_server, code);
			END IF;
		END IF;

		-- submit to Nagios
		IF is_submit_to_nagios AND (NOT is_acknowledged) AND (NOT is_flapping_detected) THEN

			-- If current state is NULL means alert is cleared.
			IF (NEW.current_state IS NOT NULL) THEN
				-- if OLD current_state is not null means alert level changed.
				IF (OLD.current_state IS NOT NULL AND (OLD.current_state > NEW.current_state)) THEN
					SELECT passive_check_result INTO passive_check_result_text FROM pem.create_passive_service_check_result(NEW.alert_id,
																	'Alert Level Decreased',
																	alert_curr_value,
																	NEW.current_state::text);
					passive_check_result_text = regexp_replace(passive_check_result_text, '%OldState%', OLD.current_state::text);
					passive_check_result_text = regexp_replace(passive_check_result_text, '%NewState%', NEW.current_state::text);

				ELSIF (OLD.current_state IS NOT NULL AND (OLD.current_state < NEW.current_state)) THEN
					SELECT passive_check_result INTO passive_check_result_text FROM pem.create_passive_service_check_result(NEW.alert_id,
																	'Alert Level Increased',
																	alert_curr_value,
																	NEW.current_state::text);
					passive_check_result_text = regexp_replace(passive_check_result_text, '%OldState%', OLD.current_state::text);
					passive_check_result_text = regexp_replace(passive_check_result_text, '%NewState%', NEW.current_state::text);

				ELSE
					SELECT passive_check_result INTO passive_check_result_text FROM pem.create_passive_service_check_result(NEW.alert_id,
																	'Alert Detected',
																	alert_curr_value,
																	NEW.current_state::text);
				END IF;

			ELSE
				SELECT passive_check_result INTO passive_check_result_text FROM pem.create_passive_service_check_result(NEW.alert_id,
																'Alert Cleared',
																alert_curr_value,
																NEW.current_state::text);
			END IF;

			submit_to_nagios_val = pem.submit_to_nagios(passive_check_result_text);
		END IF;
	END IF;

	RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Add lag bytes in streaming replication probe.
ALTER TABLE pemdata.streaming_replication ADD COLUMN lag_MB bigint;
ALTER TABLE pemhistory.streaming_replication ADD COLUMN lag_MB bigint;

COMMENT ON COLUMN pemdata.streaming_replication.lag_MB IS 'Standby server lag behind the master (In MB).';
COMMENT ON COLUMN pemhistory.streaming_replication.lag_MB IS 'Standby server lag behind the master (In MB).';

UPDATE pem.probe SET probe_code = $sql$
SELECT client_addr, client_port, sent_location, write_location, flush_location, replay_location, xlog_lag_in_segments,
	(((sent_location -replay_location)>>10) / (SUBSTRING(unit FROM '[0-9]+'))::INT) AS xlog_lag_in_pages,
    floor(((lag_MB/1024)/1024)) AS lag_MB
FROM (

		WITH pg_stat_replication_log_bytes AS (
		SELECT
			host(client_addr) AS client_addr, client_port,

			pg_catalog.split_part(sent_location, '/', 1) AS s1,
			pg_catalog.split_part(sent_location, '/', 2) AS s2,

			pg_catalog.split_part(write_location, '/', 1) AS w1,
			pg_catalog.split_part(write_location, '/', 2) AS w2,

			pg_catalog.split_part(flush_location, '/', 1) AS f1,
			pg_catalog.split_part(flush_location, '/', 2) AS f2,

			pg_catalog.split_part(replay_location, '/', 1) AS r1,
			pg_catalog.split_part(replay_location, '/', 2) AS r2,

			(('x'||SUBSTRING((pg_xlogfile_name_offset(sent_location)).file_name FROM 9))::BIT(64)::BIGINT -
				('x'||SUBSTRING((pg_xlogfile_name_offset(replay_location)).file_name FROM 9))::BIT(64)::BIGINT) AS xlog_lag_in_segments,

			pg_xlog_location_diff(sent_location, replay_location) AS lag_MB

		FROM pg_stat_replication WHERE client_addr IS NOT NULL)
	SELECT
		client_addr, client_port,
		CASE WHEN s1 IS NULL AND s2 IS NULL THEN 0::bigint
			WHEN s1 IS NULL THEN ('x' || repeat('0', 16 - length(s2)) || s2)::bit(64)::bigint
			WHEN s2 IS NULL THEN 4278190080 * ('x' || repeat('0', 16 - length(s1)) || s1)::bit(64)::bigint
			ELSE 4278190080 * ('x' || repeat('0', 16 - length(s1)) || s1)::bit(64)::bigint + ('x' || repeat('0', 16 - length(s2)) || s2)::bit(64)::bigint
		END AS sent_location,
		CASE WHEN w1 IS NULL AND w2 IS NULL THEN 0::bigint
			WHEN w1 IS NULL THEN ('x' || repeat('0', 16 - length(w2)) || w2)::bit(64)::bigint
			WHEN w2 IS NULL THEN 4278190080 * ('x' || repeat('0', 16 - length(w1)) || w1)::bit(64)::bigint
			ELSE 4278190080 * ('x' || repeat('0', 16 - length(w1)) || w1)::bit(64)::bigint + ('x' || repeat('0', 16 - length(w2)) || w2)::bit(64)::bigint
		END AS write_location,
		CASE WHEN f1 IS NULL AND f2 IS NULL THEN 0::bigint
			WHEN f1 IS NULL THEN ('x' || repeat('0', 16 - length(f2)) || f2)::bit(64)::bigint
			WHEN f2 IS NULL THEN 4278190080 * ('x' || repeat('0', 16 - length(f1)) || f1)::bit(64)::bigint
			ELSE 4278190080 * ('x' || repeat('0', 16 - length(f1)) || f1)::bit(64)::bigint + ('x' || repeat('0', 16 - length(f2)) || f2)::bit(64)::bigint
		END AS flush_location,
		CASE WHEN r1 IS NULL AND r2 IS NULL THEN 0::bigint
			WHEN r1 IS NULL THEN ('x' || repeat('0', 16 - length(r2)) || r2)::bit(64)::bigint
			WHEN r2 IS NULL THEN 4278190080 * ('x' || repeat('0', 16 - length(r1)) || r1)::bit(64)::bigint
			ELSE 4278190080 * ('x' || repeat('0', 16 - length(r1)) || r1)::bit(64)::bigint + ('x' || repeat('0', 16 - length(r2)) || r2)::bit(64)::bigint
		END AS replay_location,
		xlog_lag_in_segments,
		lag_MB
	FROM pg_stat_replication_log_bytes
) AS pg_stat_replication_dtls, pg_catalog.pg_settings
WHERE name ~ 'wal_segment_size'
$sql$
WHERE internal_name = 'streaming_replication';

UPDATE pem.probe_server_version SET probe_code = $sql$
SELECT client_addr, client_port, sent_location, write_location, flush_location, replay_location, xlog_lag_in_segments,
		(((sent_location -replay_location)>>10) / (SUBSTRING(unit FROM '[0-9]+'))::INT) AS xlog_lag_in_pages,
        floor(((lag_MB/1024)/1024)) AS lag_MB
FROM (
		WITH pg_stat_replication_log_bytes AS (
		SELECT
			host(client_addr) AS client_addr, client_port,

			pg_catalog.split_part(sent_location::text, '/', 1) AS s1,
			pg_catalog.split_part(sent_location::text, '/', 2) AS s2,

			pg_catalog.split_part(write_location::text, '/', 1) AS w1,
			pg_catalog.split_part(write_location::text, '/', 2) AS w2,

			pg_catalog.split_part(flush_location::text, '/', 1) AS f1,
			pg_catalog.split_part(flush_location::text, '/', 2) AS f2,

			pg_catalog.split_part(replay_location::text, '/', 1) AS r1,
			pg_catalog.split_part(replay_location::text, '/', 2) AS r2,

			(('x'||SUBSTRING((pg_xlogfile_name_offset(sent_location)).file_name FROM 9))::BIT(64)::BIGINT -
				('x'||SUBSTRING((pg_xlogfile_name_offset(replay_location)).file_name FROM 9))::BIT(64)::BIGINT) AS xlog_lag_in_segments,

			pg_xlog_location_diff(sent_location, replay_location) AS lag_MB

		FROM pg_stat_replication WHERE client_addr IS NOT NULL)
	SELECT
		client_addr, client_port,
		CASE WHEN s1 IS NULL AND s2 IS NULL THEN 0::bigint
			WHEN s1 IS NULL THEN ('x' || repeat('0', 16 - length(s2)) || s2)::bit(64)::bigint
			WHEN s2 IS NULL THEN 4278190080 * ('x' || repeat('0', 16 - length(s1)) || s1)::bit(64)::bigint
			ELSE 4278190080 * ('x' || repeat('0', 16 - length(s1)) || s1)::bit(64)::bigint + ('x' || repeat('0', 16 - length(s2)) || s2)::bit(64)::bigint
		END AS sent_location,
		CASE WHEN w1 IS NULL AND w2 IS NULL THEN 0::bigint
			WHEN w1 IS NULL THEN ('x' || repeat('0', 16 - length(w2)) || w2)::bit(64)::bigint
			WHEN w2 IS NULL THEN 4278190080 * ('x' || repeat('0', 16 - length(w1)) || w1)::bit(64)::bigint
			ELSE 4278190080 * ('x' || repeat('0', 16 - length(w1)) || w1)::bit(64)::bigint + ('x' || repeat('0', 16 - length(w2)) || w2)::bit(64)::bigint
		END AS write_location,
		CASE WHEN f1 IS NULL AND f2 IS NULL THEN 0::bigint
			WHEN f1 IS NULL THEN ('x' || repeat('0', 16 - length(f2)) || f2)::bit(64)::bigint
			WHEN f2 IS NULL THEN 4278190080 * ('x' || repeat('0', 16 - length(f1)) || f1)::bit(64)::bigint
			ELSE 4278190080 * ('x' || repeat('0', 16 - length(f1)) || f1)::bit(64)::bigint + ('x' || repeat('0', 16 - length(f2)) || f2)::bit(64)::bigint
		END AS flush_location,
		CASE WHEN r1 IS NULL AND r2 IS NULL THEN 0::bigint
			WHEN r1 IS NULL THEN ('x' || repeat('0', 16 - length(r2)) || r2)::bit(64)::bigint
			WHEN r2 IS NULL THEN 4278190080 * ('x' || repeat('0', 16 - length(r1)) || r1)::bit(64)::bigint
			ELSE 4278190080 * ('x' || repeat('0', 16 - length(r1)) || r1)::bit(64)::bigint + ('x' || repeat('0', 16 - length(r2)) || r2)::bit(64)::bigint
		END AS replay_location,
		xlog_lag_in_segments,
		lag_MB
	FROM pg_stat_replication_log_bytes
) AS pg_stat_replication_dtls, pg_catalog.pg_settings
WHERE name ~ 'wal_segment_size'
$sql$
WHERE probe_id = (SELECT id from pem.probe WHERE internal_name = 'streaming_replication')
AND server_version_id IN (10904, 10905, 10906, 20904, 20905, 20906);

UPDATE pem.probe_server_version SET probe_code = $sql$
SELECT client_addr, client_port, sent_location, write_location, flush_location, replay_location, xlog_lag_in_segments,
		(((sent_location -replay_location)>>10) / (SUBSTRING(unit FROM '[0-9]+'))::INT) AS xlog_lag_in_pages,
        floor(((lag_MB/1024)/1024)) AS lag_MB
FROM (
		WITH pg_stat_replication_log_bytes AS (
		SELECT
			host(client_addr) AS client_addr, client_port,

			pg_catalog.split_part(sent_lsn::text, '/', 1) AS s1,
			pg_catalog.split_part(sent_lsn::text, '/', 2) AS s2,

			pg_catalog.split_part(write_lsn::text, '/', 1) AS w1,
			pg_catalog.split_part(write_lsn::text, '/', 2) AS w2,

			pg_catalog.split_part(flush_lsn::text, '/', 1) AS f1,
			pg_catalog.split_part(flush_lsn::text, '/', 2) AS f2,

			pg_catalog.split_part(replay_lsn::text, '/', 1) AS r1,
			pg_catalog.split_part(replay_lsn::text, '/', 2) AS r2,

			(('x'||SUBSTRING((pg_walfile_name_offset(sent_lsn)).file_name FROM 9))::BIT(64)::BIGINT -
				('x'||SUBSTRING((pg_walfile_name_offset(replay_lsn)).file_name FROM 9))::BIT(64)::BIGINT) AS xlog_lag_in_segments,

			pg_wal_lsn_diff(sent_lsn, replay_lsn) AS lag_MB

		FROM pg_stat_replication WHERE client_addr IS NOT NULL)
	SELECT
		client_addr, client_port,
		CASE WHEN s1 IS NULL AND s2 IS NULL THEN 0::bigint
			WHEN s1 IS NULL THEN ('x' || repeat('0', 16 - length(s2)) || s2)::bit(64)::bigint
			WHEN s2 IS NULL THEN 4278190080 * ('x' || repeat('0', 16 - length(s1)) || s1)::bit(64)::bigint
			ELSE 4278190080 * ('x' || repeat('0', 16 - length(s1)) || s1)::bit(64)::bigint + ('x' || repeat('0', 16 - length(s2)) || s2)::bit(64)::bigint
		END AS sent_location,
		CASE WHEN w1 IS NULL AND w2 IS NULL THEN 0::bigint
			WHEN w1 IS NULL THEN ('x' || repeat('0', 16 - length(w2)) || w2)::bit(64)::bigint
			WHEN w2 IS NULL THEN 4278190080 * ('x' || repeat('0', 16 - length(w1)) || w1)::bit(64)::bigint
			ELSE 4278190080 * ('x' || repeat('0', 16 - length(w1)) || w1)::bit(64)::bigint + ('x' || repeat('0', 16 - length(w2)) || w2)::bit(64)::bigint
		END AS write_location,
		CASE WHEN f1 IS NULL AND f2 IS NULL THEN 0::bigint
			WHEN f1 IS NULL THEN ('x' || repeat('0', 16 - length(f2)) || f2)::bit(64)::bigint
			WHEN f2 IS NULL THEN 4278190080 * ('x' || repeat('0', 16 - length(f1)) || f1)::bit(64)::bigint
			ELSE 4278190080 * ('x' || repeat('0', 16 - length(f1)) || f1)::bit(64)::bigint + ('x' || repeat('0', 16 - length(f2)) || f2)::bit(64)::bigint
		END AS flush_location,
		CASE WHEN r1 IS NULL AND r2 IS NULL THEN 0::bigint
			WHEN r1 IS NULL THEN ('x' || repeat('0', 16 - length(r2)) || r2)::bit(64)::bigint
			WHEN r2 IS NULL THEN 4278190080 * ('x' || repeat('0', 16 - length(r1)) || r1)::bit(64)::bigint
			ELSE 4278190080 * ('x' || repeat('0', 16 - length(r1)) || r1)::bit(64)::bigint + ('x' || repeat('0', 16 - length(r2)) || r2)::bit(64)::bigint
		END AS replay_location,
		xlog_lag_in_segments,
		lag_MB
	FROM pg_stat_replication_log_bytes
) AS pg_stat_replication_dtls, pg_catalog.pg_settings
WHERE name ~ 'wal_segment_size'
$sql$
WHERE probe_id = (SELECT id from pem.probe WHERE internal_name = 'streaming_replication')
AND server_version_id IN (11000, 21000);

INSERT INTO pem.probe_column (
    probe_id, internal_name, display_name, display_position, classification,
    sql_data_type, unit_of_value, calculate_pit, discard_history,
    pit_by_default, is_graphable
) VALUES (
    (SELECT id FROM pem.probe WHERE internal_name='streaming_replication'), 'lag_MB',
    'Lag in MB', 9, 'm', 'bigint', 'MB', false, false, true, true
);

-- Create new alert template that will be used to find the lag in MB.
SELECT pem.create_alert_template(
        'Standby servers lag behind the master by size(MB)',
        'In streaming replication number of bytes(MB) standby node is lagging behind the master node. This alert template should be applied on master node.',
        $sql$
SELECT MAX(lag_MB) FROM pemdata.streaming_replication WHERE server_id = ${server_id}$sql$,
        200, NULL, NULL, NULL, 'MB','{streaming_replication}', (SELECT CASE WHEN MAX(snmp_oid) > 0 THEN MAX(snmp_oid) + 1 ELSE 1 END FROM pem.alert_template WHERE object_type = 200),
'ALL', 1, 30, true,
$sql$SELECT srv.description || ' (' || srv.server || ')' AS "Master server",
       srl.description || ' (' || srl.server || ')' AS "Standby server", sr.client_port AS "Standby server port",
       sr.xlog_lag_in_segments AS "Lag in segments", sr.xlog_lag_in_pages AS "Lag in pages",
       sr.lag_MB AS "Lag in MB"
FROM pemdata.streaming_replication AS sr
JOIN pem.server AS srv
ON sr.server_id = srv.id
JOIN pem.server AS srl
ON (sr.client_addr = srl.server)
WHERE sr.server_id = '${server_id}'::integer
AND lag_MB ${comparison_operator} '${threshold_value}'::numeric;$sql$);

--
-- Probe: blocked_session_info
--
INSERT INTO pem.probe
    (display_name, internal_name, collection_method, target_type_id,
     agent_capability, enabled_by_default, force_enabled,
     default_execution_frequency, default_lifetime, any_server_version, probe_code)
VALUES
    ('Blocked Session Information', 'blocked_session_info', 's',
     200, NULL, true, false, 300, 180, false,
    $sql$
SELECT
       blocked_locks.pid AS blocked_pid,
       blocked_activity.usename AS blocked_user,
       blocked_locks.mode       AS locktype,
       blocking_locks.pid AS blocking_pid,
       blocking_activity.usename AS blocking_user,
       blocking_activity.datname AS database_name,
       now() - blocking_activity.query_start AS blocking_duration,
       now() - blocked_activity.query_start  AS blocked_duration,
       blocking_activity.query_start         AS blocking_query_start,
       blocked_activity.query_start          AS blocked_query_start,
       blocked_activity.query AS blocked_statement,
       blocking_activity.query AS current_statement_in_blocking_process,
       blocked_activity.application_name AS blocked_application,
       blocking_activity.application_name AS blocking_application
FROM
    pg_catalog.pg_locks blocked_locks
    JOIN pg_catalog.pg_stat_activity blocked_activity ON blocked_activity.pid = blocked_locks.pid
    JOIN pg_catalog.pg_locks blocking_locks ON blocking_locks.locktype = blocked_locks.locktype AND
         blocking_locks.DATABASE IS NOT DISTINCT FROM blocked_locks.DATABASE AND
         blocking_locks.relation IS NOT DISTINCT FROM blocked_locks.relation AND
         blocking_locks.page IS NOT DISTINCT FROM blocked_locks.page AND
         blocking_locks.tuple IS NOT DISTINCT FROM blocked_locks.tuple AND
         blocking_locks.virtualxid IS NOT DISTINCT FROM blocked_locks.virtualxid AND
         blocking_locks.transactionid IS NOT DISTINCT FROM blocked_locks.transactionid AND
         blocking_locks.classid IS NOT DISTINCT FROM blocked_locks.classid AND
         blocking_locks.objid IS NOT DISTINCT FROM blocked_locks.objid AND
         blocking_locks.objsubid IS NOT DISTINCT FROM blocked_locks.objsubid AND
         blocking_locks.pid != blocked_locks.pid
    JOIN pg_catalog.pg_stat_activity blocking_activity ON blocking_activity.pid = blocking_locks.pid
WHERE
    NOT blocked_locks.GRANTED
    $sql$
);

INSERT INTO pem.probe_server_version
    (probe_id, server_version_id, probe_code)
SELECT
    (SELECT id FROM pem.probe WHERE internal_name = 'blocked_session_info'),
    v.version, NULL
FROM
    (VALUES (10902), (10903), (10904), (10905), (10906), (11000),
        (20902), (20903), (20904), (20905), (20906), (21000)) v(version);

INSERT INTO pem.probe_column
    (probe_id, internal_name, display_name, display_position, classification,
    sql_data_type, unit_of_value, calculate_pit, discard_history, pit_by_default, is_graphable)
SELECT
    (SELECT max(id) FROM pem.probe),
    v.internal_name, v.display_name, v.display_position, v.classification,
    v.sql_data_type, v.unit_of_value, v.calculate_pit, v.discard_history, v.pit_by_default, v.is_graphable
FROM
    (VALUES
        ('blocked_pid', 'Blocked PID', 1, 'k', 'integer', '', false, false, false, false),
        ('blocked_user', 'Blocked user', 2, 'm', 'name', '', false, false, false, false),
        ('locktype', 'Lock type', 3, 'k', 'text', '', false, false, false, false),
        ('blocking_pid', 'Blocking PID', 4, 'k', 'integer', '', false, false, false, false),
        ('blocking_user', 'Blocking user', 5, 'm', 'name', '', false, false, false, false),
        ('database_name', 'Database name', 6, 'm', 'name', '', false, false, false, false),
        ('blocking_duration', 'Blocking duration', 7, 'm', 'interval', '', false, false, false, false),
        ('blocked_duration', 'Blocked duration', 8, 'm', 'interval', '', false, false, false, false),
        ('blocking_query_start', 'Blocking query start', 9, 'm', 'timestamp with time zone', '', false, false, false, false),
        ('blocked_query_start', 'Blocked query start', 10, 'm', 'timestamp with time zone', '', false, false, false, false),
        ('blocked_statement', 'Blocked statement', 11, 'm', 'text', '', false, false, false, false),
        ('current_statement_in_blocking_process', 'Blocking process statement', 12, 'm', 'text', '', false, false, false, false),
        ('blocked_application', 'Blocked application', 13, 'm', 'text', '', false, false, false, false),
        ('blocking_application', 'Blocking application', 14, 'm', 'text', '', false, false, false, false)
    ) v(internal_name, display_name, display_position, classification,
        sql_data_type, unit_of_value, calculate_pit, discard_history, pit_by_default, is_graphable);

UPDATE pem.alert_template SET sql = $sql$
  SELECT COUNT(*) FROM pemdata.blocked_session_info
    WHERE   server_id = ${server_id}
    AND     database_name = '${database_name}'$sql$,
probe_dependency_list = '{blocked_session_info}',
info_sql = $sql$
SELECT
    database_name AS "Database name",
    blocked_pid AS "Blocked PID",
    locktype AS "Lock type",
    blocking_pid AS "Blocking PID",
    blocking_user AS "Blocking user",
    blocking_duration AS "Blocking duration",
    blocked_duration AS "Blocked duration",
    blocking_query_start AS "Blocking query start",
    blocked_query_start AS "Blocked query start",
    blocked_statement AS "Blocked statement",
    blocked_application AS "Blocked application",
    blocking_application AS "Blocking application"
FROM
    pemdata.blocked_session_info
WHERE
    server_id = '${server_id}'::integer
    AND database_name = '${database_name}';$sql$
WHERE display_name = 'Ungranted locks' AND object_type = 300;

UPDATE pem.alert_template SET sql = $sql$SELECT COUNT(*) FROM pemdata.blocked_session_info
    WHERE   server_id = ${server_id}$sql$,
probe_dependency_list = '{blocked_session_info}',
info_sql = $sql$
SELECT
    database_name AS "Database name",
    blocked_pid AS "Blocked PID",
    locktype AS "Lock type",
    blocking_pid AS "Blocking PID",
    blocking_user AS "Blocking user",
    blocking_duration AS "Blocking duration",
    blocked_duration AS "Blocked duration",
    blocking_query_start AS "Blocking query start",
    blocked_query_start AS "Blocked query start",
    blocked_statement AS "Blocked statement",
    blocked_application AS "Blocked application",
    blocking_application AS "Blocking application"
FROM
    pemdata.blocked_session_info
WHERE
    server_id = '${server_id}'::integer;$sql$
WHERE display_name = 'Ungranted locks' AND object_type = 200;

SELECT pem.create_data_and_history_tables();

COMMIT TRANSACTION;
