/***************************************************************************
 *
 * Postgres Enterprise Manager
 *
 * Copyright (C) 2010 - 2025, EnterpriseDB Corporation. All rights reserved.
 *
 ***************************************************************************/

-- JIRA: PEM-2046

BEGIN TRANSACTION;

CREATE OR REPLACE FUNCTION pem.schema_version()
RETURNS integer AS
'SELECT 201904191::integer;'
LANGUAGE 'sql' IMMUTABLE;

/*
 * Function to process one alert.
 *
 * It returns true if it processed any alerts, and false otherwise. A return
 * value of false implies that the caller can forego checking for anymore
 * alerts until next one minute boundary, or whatever boundary is chosen.
 *
 * The function tries to take advisory lock on an alert before processing it,
 * and move on to trying to lock another one if it can't lock the first one.
 * Hence multiple simultaneous invocations of this function are allowed, and
 * preferred when a single-threaded alert processor is unable to keep up with
 * the workload.
 */
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
	probe_disabled_err := 'Required probe(s) ';
	zero_rows_err := 'Zero rows returned';

	locked_alert := false;

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
			locked_alert := true;
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

	sql := alert_rec.sql;

	/* Replace any reference to hierarchy-related alert parameters */
	sql := regexp_replace(sql, E'\\${agent_id}',		COALESCE(alert_rec.agent_id::text,	'')::text, 'g');
	sql := regexp_replace(sql, E'\\${server_id}',	COALESCE(alert_rec.server_id::text,	'')::text, 'g');
	sql := regexp_replace(sql, E'\\${database_name}',COALESCE(alert_rec.database_name,	'')::text, 'g');
	sql := regexp_replace(sql, E'\\${schema_name}',	COALESCE(alert_rec.schema_name,		'')::text, 'g');
	sql := regexp_replace(sql, E'\\${package_name}',	COALESCE(alert_rec.package_name,	'')::text, 'g');
	sql := regexp_replace(sql, E'\\${object_name}',	COALESCE(alert_rec.object_name,		'')::text, 'g');

	/* Replace ${param_n} with corresponding alert parameters */
	FOR i IN 1..COALESCE(array_upper(alert_rec.params, 1), 0) LOOP
		sql := regexp_replace(sql, E'\\${param_' || i || '}', alert_rec.params[i]::text, 'g');
	END LOOP;

	err := '';

	/* Check any required probe is disabled from the probe dependency list */
	all_probes_enabled := true;
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
			probe_disabled_err := probe_disabled_err || alert_rec.probe_dependency_list[i] || ',';
			all_probes_enabled := false;
		END IF;

		-- Get minimum probe interval from all dependent probes
		SELECT default_execution_frequency INTO probe_interval FROM pem.probe WHERE internal_name = alert_rec.probe_dependency_list[i];
		IF (probe_interval <  min_probe_interval) OR (i = 1) THEN
			min_probe_interval := probe_interval;
		END IF;
	END LOOP;

	probe_disabled_err := trim(trailing ',' from probe_disabled_err);
	probe_disabled_err := probe_disabled_err || ' are disabled.';

	IF NOT all_probes_enabled THEN
		err := probe_disabled_err;
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
			    err := '';
			  END IF;

			WHEN OTHERS THEN
				err := SQLERRM;
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
			state := 'HIGH';
		ELSIF (sql_ret < alert_rec.thresholds[2]) THEN
			state := 'MEDIUM';
		ELSIF (sql_ret < alert_rec.thresholds[1]) THEN
			state := 'LOW';
		ELSE
			state := NULL;
		END IF;
	ELSIF (alert_rec.operator = '>') THEN
		IF (sql_ret > alert_rec.thresholds[3]) THEN
			state := 'HIGH';
		ELSIF (sql_ret > alert_rec.thresholds[2]) THEN
			state := 'MEDIUM';
		ELSIF (sql_ret > alert_rec.thresholds[1]) THEN
			state := 'LOW';
		ELSE
			state := NULL;
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
	 *        set acked := false
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
				send_mail_val := pem.send_email(mail_group_id, subject, message);
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
		message := regexp_replace(message, '%CurrentState%', state::text, 'g');
		message := regexp_replace(message, '%AlertingSince%', alert_state_since::text, 'g');
		CASE WHEN sql_ret_display IS NOT NULL AND sql_ret_display != '' THEN
			message := regexp_replace(message, '%CurrentValue%', COALESCE(sql_ret_display, 0::text), 'g');
		ELSE
			message := regexp_replace(message, '%CurrentValue%', COALESCE(sql_ret, 0)::text, 'g');
		END CASE;

		-- Get the list of down objetcs
		down_objects_list := pem.get_down_objects_list(alert_rec.template_name);
		message := regexp_replace(message, '%DownObjects%', down_objects_list::text, 'g');
		message := regexp_replace(message, '%DetailInfo%', COALESCE(alert_info, 'None')::text, 'g');

		send_mail_val := pem.send_email(mail_group_id, subject, message);
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
			subject = regexp_replace(subject, '%AlertType%', NEW.current_state::text, 'g');
			message = regexp_replace(message, '%CurrentValue%', alert_curr_value, 'g');
			message = regexp_replace(message, '%AlertDetected%', now()::text, 'g');
			message = regexp_replace(message, '%DownObjects%', down_objects_list::text, 'g');
			message = regexp_replace(message, '%DetailInfo%', COALESCE(NEW.info, 'None')::text, 'g');

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
					message = regexp_replace(message, '%CurrentState%', NEW.current_state::text, 'g');
					message = regexp_replace(message, '%OldState%', OLD.current_state::text, 'g');
					message = regexp_replace(message, '%StateChanged%', now()::text, 'g');
				ELSIF (OLD.current_state IS NOT NULL AND (OLD.current_state < NEW.current_state)) THEN
					-- Create subject and message
					SELECT subject_mail, message_mail INTO subject, message FROM pem.create_email(NEW.alert_id, 'Alert Level Increased');
					message = regexp_replace(message, '%CurrentState%', NEW.current_state::text, 'g');
					message = regexp_replace(message, '%OldState%', OLD.current_state::text, 'g');
					message = regexp_replace(message, '%StateChanged%', now()::text, 'g');
				ELSE
					-- Create subject and message
					SELECT subject_mail, message_mail INTO subject, message FROM pem.create_email(NEW.alert_id, 'Alert Detected');
					subject = regexp_replace(subject, '%AlertType%', NEW.current_state::text, 'g');
					message = regexp_replace(message, '%AlertDetected%', now()::text, 'g');
				END IF;
			ELSE
				-- Create subject and message
				SELECT subject_mail, message_mail INTO subject, message FROM pem.create_email(NEW.alert_id, 'Alert Cleared');
				message = regexp_replace(message, '%AlertCleared%', now()::text, 'g');
			END IF;

			message = regexp_replace(message, '%CurrentValue%', alert_curr_value, 'g');
			message = regexp_replace(message, '%DownObjects%', down_objects_list::text, 'g');
			message = regexp_replace(message, '%DetailInfo%', COALESCE(NEW.info, 'None')::text, 'g');

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
					passive_check_result_text = regexp_replace(passive_check_result_text, '%OldState%', OLD.current_state::text, 'g');
					passive_check_result_text = regexp_replace(passive_check_result_text, '%NewState%', NEW.current_state::text, 'g');

				ELSIF (OLD.current_state IS NOT NULL AND (OLD.current_state < NEW.current_state)) THEN
					SELECT passive_check_result INTO passive_check_result_text FROM pem.create_passive_service_check_result(NEW.alert_id,
																	'Alert Level Increased',
																	alert_curr_value,
																	NEW.current_state::text);
					passive_check_result_text = regexp_replace(passive_check_result_text, '%OldState%', OLD.current_state::text, 'g');
					passive_check_result_text = regexp_replace(passive_check_result_text, '%NewState%', NEW.current_state::text, 'g');

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

CREATE OR REPLACE FUNCTION pem.create_script_job(alert_id integer, current_value text, current_state text, previous_state text, run_on_pem_server boolean, script_code text) RETURNS VOID AS $$
DECLARE
	alert_name text;
	alert_agent_id int;
	alert_server_id int;
	alert_object_name text;
	alert_thresholdvalue text;
	server_name text;
	server_ip text;
	server_port integer;
	agent_name text;
	job_id integer;
	job_name text;
BEGIN
	-- Get alert, agent, server details
	SELECT
		a.name, a.agent_id, a.server_id, a.thresholds,
		s.description, s.server, s.port,
		ag.description
	INTO
		alert_name, alert_agent_id, alert_server_id, alert_thresholdvalue, server_name, server_ip, server_port,
		agent_name
	FROM
		pem.alert a
		LEFT JOIN pem.server s ON a.server_id = s.id
		LEFT JOIN pem.agent ag ON a.agent_id = ag.id
	WHERE
		a.id = alert_id;

	CASE WHEN server_name IS NOT NULL THEN
		alert_object_name = server_name || ' ('|| server_ip ||': ' || server_port || ')';
	WHEN agent_name IS NOT NULL THEN
		alert_object_name = agent_name;
	ELSE
		alert_object_name = 'Postgres Enterprise Manager Server';
	END CASE;

	-- Replace single "\" with "\\" because regexp_replace escapes backslash
	alert_name = replace(alert_name, E'\\', E'\\\\');
	alert_object_name = replace(alert_object_name, E'\\', E'\\\\');

	script_code = regexp_replace(script_code, '%ThresholdValue%', alert_thresholdvalue::text, 'g');
	script_code = regexp_replace(script_code, '%CurrentValue%', current_value, 'g');
	script_code = regexp_replace(script_code, '%CurrentState%', COALESCE(current_state, '')::text, 'g');
	script_code = regexp_replace(script_code, '%OldState%', COALESCE(previous_state, '')::text, 'g');
	script_code = regexp_replace(script_code, '%AlertRaisedTime%', now()::text, 'g');
	script_code = regexp_replace(script_code, '%ObjectName%', alert_object_name, 'g');
	script_code = regexp_replace(script_code, '%AlertName%', alert_name, 'g');

	IF run_on_pem_server THEN
		alert_agent_id = 1;
	ELSE
		IF alert_agent_id < 1 THEN
			SELECT agent_id FROM pem.agent_server_binding WHERE server_id = alert_server_id INTO alert_agent_id;
		END IF;
	END IF;

	-- Create jobs only when agent_id is correct
	IF alert_agent_id >= 1 THEN
		job_name = 'Execute script for alert "' || alert_name || '"';
		-- Create script execution job.
		INSERT INTO pem.job(jobname, jobdesc, agent_id, jobnextrun) VALUES(job_name, 'This job executes the given script when alert raises', alert_agent_id, now()) RETURNING jobid INTO job_id;
		-- Create script execution step.
		IF alert_server_id >= 1 THEN
			INSERT INTO pem.jobstep(jstjobid, jstname, jstdesc, jstkind, jstcode, server_id, jstonerror, jstsetenvironment) VALUES (job_id, job_name,'This job step executes the given script when alert raises', 'b', script_code, alert_server_id, 'f', 't');
		ELSE
			INSERT INTO pem.jobstep(jstjobid, jstname, jstdesc, jstkind, jstcode, jstonerror, jstsetenvironment) VALUES (job_id, job_name,'This job step executes the given script when alert raises', 'b', script_code, 'f', 'f');
		END IF;
	END IF;
END
$$ LANGUAGE plpgsql;

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

	subject_mail = regexp_replace(subject_mail, '%AlertName%', alert_name, 'g');
	subject_mail = regexp_replace(subject_mail, '%ObjectName%', alert_object_name, 'g');
	message_mail = regexp_replace(message_mail, '%AlertName%', alert_name, 'g');
	message_mail = regexp_replace(message_mail, '%ObjectName%', msg_object_name, 'g');
	message_mail = regexp_replace(message_mail, '%ThresholdValue%', alert_thresholdvalue::text, 'g');
END;
$$ LANGUAGE plpgsql;

-- Function to create unique service name for nagios
CREATE OR REPLACE FUNCTION pem.create_nagios_service_name(
    alert_name text,
    server_name text DEFAULT NULL::text,
    database_name text DEFAULT NULL::text,
    schema_name text DEFAULT NULL::text,
    package_name text DEFAULT NULL::text,
    object_name text DEFAULT NULL::text)
  RETURNS text AS
$BODY$
DECLARE
    service_name_text    text := '';
    new_alert_name       text := '';
BEGIN

        new_alert_name = regexp_replace(regexp_replace(alert_name, E'[`~$%^&*|''"<>?,(=]', '-', 'g'), E'[)]', '-', 'g');
        service_name_text = E'' || new_alert_name || CASE WHEN (server_name IS NOT NULL AND server_name != '') THEN ' - svr: ' || server_name ELSE '' END || CASE WHEN (database_name IS NOT NULL AND database_name != '') THEN ' - db: ' || database_name ELSE '' END || CASE WHEN (schema_name IS NOT NULL AND schema_name != '') THEN ' - schema: ' || schema_name ELSE '' END || CASE WHEN (package_name IS NOT NULL AND package_name != '') THEN ' - pkg: ' || package_name ELSE '' END || CASE WHEN (object_name IS NOT NULL AND object_name != '') THEN ' - obj: ' || object_name ELSE '' END || E'';

RETURN service_name_text;

END
$BODY$
  LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION pem.create_passive_service_check_result(
    IN alert_id integer,
    IN template text,
    IN current_value text,
    IN current_state text,
    OUT passive_check_result text)
  RETURNS text AS
$BODY$
DECLARE
    alert_name                            text;
    alert_object_name                    text;
    msg_object_name                        text;
    alert_thresholdvalue                text;
    server_name                            text;
    server_ip                            text;
    server_port                            integer;
    agent_name                            text;
    status_text                            text;
    is_nagios_medium_alert_as_critical    boolean:=false;
    agent_id                             integer;
    server_id                            integer;
    database_name                        text;
    schema_name                          text;
    package_name                         text;
    object_name                          text;
    agent_description                    text;
    service_name                         text;
BEGIN

    -- Get alert, agent, server details
    SELECT
        a.name, a.thresholds,
        s.description, s.server, s.port,
        ag.description, a.agent_id, a.server_id,
        a.database_name, a.schema_name, a.package_name, a.object_name
    INTO
        alert_name, alert_thresholdvalue,
        server_name, server_ip, server_port,
        agent_name, agent_id, server_id, database_name,
        schema_name, package_name, object_name
    FROM
        pem.alert a
        LEFT JOIN pem.server s ON a.server_id = s.id
        LEFT JOIN pem.agent ag ON a.agent_id = ag.id
    WHERE
        a.id = alert_id;

    SELECT value INTO is_nagios_medium_alert_as_critical FROM pem.config WHERE param = 'nagios_medium_alert_as_critical';

    SELECT mail_subject INTO status_text FROM pem.email_template WHERE display_name = template;

    -- Function to create the nagios host name from agent and server id
    SELECT pem.create_nagios_host_name(agent_id , server_id) INTO agent_description;

    CASE WHEN server_name IS NOT NULL THEN
        alert_object_name = server_name || ' ('|| server_ip ||': ' || server_port || ')';
        msg_object_name = alert_object_name;
    WHEN agent_name IS NOT NULL THEN
        alert_object_name = agent_name;
        msg_object_name = alert_object_name;
    -- in case of global alert agent name and server_name are NULL so description from main pem agent has been fetched
    ELSE
        SELECT description INTO alert_object_name FROM pem.agent where id = 1;
        msg_object_name = alert_object_name;
    END CASE;

    -- Replace single "\" with "\\" because regexp_replace escapes backslash
    alert_name = replace(alert_name, E'\\', E'\\\\');
    alert_object_name = replace(alert_object_name, E'\\', E'\\\\');

    status_text = regexp_replace(status_text, '%AlertName%', alert_name, 'g');
    status_text = regexp_replace(status_text, '%ObjectName%', msg_object_name, 'g');
    IF current_state IS NOT NULL THEN
        status_text = regexp_replace(status_text, '%AlertType%', current_state, 'g');
    END IF;
    status_text = status_text || E' (threshold values: ' || alert_thresholdvalue;
        IF current_value IS NOT NULL THEN
        status_text = status_text || E', current value: ' || current_value || ')';
        ELSE
        status_text = status_text || E', current value: UNKNOWN)';
        END IF;

    IF template NOT IN ('Alert Detected','Alert Cleared') THEN
        status_text = status_text || E' (new State: %NewState% ';
        status_text = status_text || E', old State: %OldState%)';
    END IF;

    passive_check_result = E'[';
    passive_check_result = passive_check_result || round(extract('epoch' from now())) || E'] ';
    passive_check_result = passive_check_result || E'PROCESS_SERVICE_CHECK_RESULT;';

    passive_check_result = passive_check_result || agent_description || E';';

    -- Function to create the nagios service/alert name
    SELECT pem.create_nagios_service_name(alert_name, server_name, database_name, schema_name, package_name, object_name) INTO service_name;

    passive_check_result = passive_check_result || service_name || E';';
    IF (current_state = 'HIGH') THEN
        passive_check_result = passive_check_result || E'2;';

    ELSIF (current_state = 'LOW') THEN
        passive_check_result = passive_check_result || E'1;';

    ELSIF (current_state = 'MEDIUM') THEN

        IF(is_nagios_medium_alert_as_critical) THEN
            passive_check_result = passive_check_result || E'2;';
        ELSE
            passive_check_result = passive_check_result || E'1;';
        END IF;

    ELSIF (current_state IS NULL) THEN
        passive_check_result = passive_check_result || E'0;';
    END IF;

    passive_check_result = passive_check_result || status_text;
END $BODY$
  LANGUAGE plpgsql;

END TRANSACTION;
