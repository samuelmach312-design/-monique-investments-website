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
'SELECT 201405091::integer;'
  LANGUAGE 'sql' IMMUTABLE;

ALTER TABLE pem.jobstep
	ADD COLUMN jstsetenvironment	bool NOT NULL DEFAULT false;

ALTER TABLE pem.alert
	ADD COLUMN execute_script bool NOT NULL DEFAULT FALSE,
	ADD COLUMN execute_script_on_clear bool NOT NULL DEFAULT FALSE,
	ADD COLUMN execute_script_on_pem_server bool NOT NULL DEFAULT FALSE,
	ADD COLUMN script_code text;

DROP FUNCTION pem.create_alert(text, integer, integer, integer, text, text, text, text, text[], text, numeric[], integer, integer, boolean, integer, boolean, boolean, timestamp with time zone, boolean, integer, boolean, integer, boolean, integer, boolean, integer);
CREATE OR REPLACE FUNCTION pem.create_alert(name				text,
											alert_template_id	integer,
											agent_id		integer,
											server_id		integer,
											database_name		text,
											schema_name		text,
											package_name		text,
											object_name		text,
											params			text[],
											operator		text,
											thresholds		numeric[],
											check_frequency		integer DEFAULT 1,
											history_retention	integer DEFAULT 30,
											enabled			bool DEFAULT true,
											email_group_id		integer DEFAULT NULL,
											send_email		bool DEFAULT false,
											flapping_detected	bool DEFAULT FALSE,
											last_flapping_detection_processed timestamptz DEFAULT current_timestamp,
											send_trap		bool DEFAULT false,
											snmp_trap_version	integer DEFAULT 2,
											low_send_trap		bool DEFAULT false,
											low_email_group_id	integer DEFAULT NULL,
											med_send_trap		bool DEFAULT false,
											med_email_group_id	integer DEFAULT NULL,
											high_send_trap		bool DEFAULT false,
											high_email_group_id	integer DEFAULT NULL,
											execute_script	bool DEFAULT false,
											execute_script_on_clear	bool DEFAULT false,
											execute_script_on_pem_server	bool DEFAULT false,
											script_code	text DEFAULT NULL)
RETURNS VOID AS $$
	/*
	 * TODO: Should we check if an object by the name object_name of type
	 * alert_template[template_id].object_type exists in the history logs? Or
	 * for that matter, verify all the Agent, Database, Server, etc.
	 *
	 * Probably not, because most of the time the user would be using the GUI to
	 * create alerts and the GUI would help the user pick up appropriate object
	 * based on object_type. And even if the object does not exist, all that
	 * would happen is the sql query of the alert would return zero rows.
	 */

	INSERT INTO pem.alert(name, enabled, template_id, agent_id, server_id,
							database_name, schema_name, package_name,
							object_name, params, operator, thresholds,
							check_frequency, history_retention, email_group_id, send_email,
							flapping_detected, last_flapping_detection_processed,
							send_trap, snmp_trap_version, low_send_trap, low_email_group_id, med_send_trap,
							med_email_group_id, high_send_trap, high_email_group_id, execute_script, execute_script_on_clear,
							execute_script_on_pem_server, script_code)
	VALUES($1, $14, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, $15, $16, $17, $18, $19, $20,
			$21, $22, $23, $24, $25, $26, $27, $28, $29, $30);
$$ LANGUAGE sql;

GRANT USAGE ON SEQUENCE pem.job_jobid_seq TO pem_agent;
GRANT USAGE ON SEQUENCE pem.jobstep_jstid_seq TO pem_agent;
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE pem.jobstep TO pem_agent;

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
	write_message_streaming_repl text;
	flush_message_streaming_repl text;
	replay_message_streaming_repl text;
	upgrade_pkg_list text;
	new_pkg_list text;
	obsolete_pkg_list text;
	message_replication_lag text := '';
	replication_alert_params text[];
	low_trap boolean:= false;
	med_trap boolean:= false;
	high_trap boolean:= false;
	is_execute_script boolean:= false;
	is_execute_on_clear boolean:= false;
	is_execute_on_pem_server boolean:= false;
	code text;
BEGIN
	-- Get alert details
	SELECT
		agent_id, template_id, send_email, acknowledged, flapping_detected, send_trap, snmp_trap_version, low_send_trap, med_send_trap,
		high_send_trap, execute_script, execute_script_on_clear, execute_script_on_pem_server, script_code
	INTO
		agentid, templateid, is_send_email, is_acknowledged, is_flapping_detected, is_send_trap, trap_version, low_trap, med_trap,
		high_trap, is_execute_script, is_execute_on_clear, is_execute_on_pem_server, code
	FROM
		pem.alert
	WHERE
		id = NEW.alert_id;

	-- Get the template name
	SELECT display_name INTO template_name FROM pem.alert_template WHERE id = templateid;

	-- Get the list of Agents/Servers Down
	down_objects_list = pem.get_down_objects_list(template_name);

	-- Get the list of slave that lag behind by write location
	IF (template_name = 'Number of standby servers lag behind the master by write location') THEN
		SELECT pem.email_write_lag_streaming_replication() INTO write_message_streaming_repl;
	END IF;

	-- Get the list of slave that lag behind by flush location
	IF (template_name = 'Number of standby servers lag behind the master by flush location') THEN
		SELECT pem.email_flush_lag_streaming_replication() INTO flush_message_streaming_repl;
	END IF;

	-- Get the list of slave that lag behind by replay location
	IF (template_name = 'Number of standby servers lag behind the master by replay location') THEN
		SELECT pem.email_replay_lag_streaming_replication() INTO replay_message_streaming_repl;
	END IF;

	-- Get the list of obsolete packages and packages for which updates are avalibale
	IF (template_name = 'Package version mismatch') THEN
		SELECT upgrade_packages_list, new_packages_list, obsolete_packages_list INTO upgrade_pkg_list,
		new_pkg_list, obsolete_pkg_list FROM pem.get_mismatch_packages_list(agentid);
	END IF;

	-- Get the standby server details for segment lag and page lag alerts
	IF (template_name = 'Standby server lag behind the master by WAL segments' OR template_name = 'Standby server lag behind the master by WAL pages') THEN
		SELECT params FROM pem.alert WHERE id = NEW.alert_id INTO replication_alert_params;
		IF array_lower(replication_alert_params, 1) IS NOT NULL THEN
			message_replication_lag := 'Standby server: ' || array_to_string(replication_alert_params, ':');
		END IF;
	END IF;

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
			message = regexp_replace(message, '%CurrentValue%', COALESCE(NEW.current_value, 0)::text);
			message = regexp_replace(message, '%AlertDetected%', now()::text);
			message = regexp_replace(message, '%DownObjects%', down_objects_list::text);

			-- Special handling for 'Write lag Alert' alert
			IF (template_name = 'Number of standby servers lag behind the master by write location') THEN
				message = message || COALESCE(write_message_streaming_repl, '')::text ;
			END IF;

			-- Special handling for 'Flush lag Alert' alert
			IF (template_name = 'Number of standby servers lag behind the master by flush location') THEN
				message = message || COALESCE(flush_message_streaming_repl, '')::text ;
			END IF;

			-- Special handling for 'Replay lag Alert' alert
			IF (template_name = 'Number of standby servers lag behind the master by replay location') THEN
				message = message || COALESCE(replay_message_streaming_repl, '')::text ;
			END IF;

			-- Special handling for 'Package version mismatch' alert
			IF (template_name = 'Package version mismatch') THEN
				message = message || E'\n' || COALESCE(upgrade_pkg_list, '')::text || E'\n' || COALESCE(obsolete_pkg_list, '')::text;
			END IF;

			-- Special handling for segment lag/page lag alerts
			IF (template_name = 'Standby server lag behind the master by WAL segments'
				OR template_name = 'Standby server lag behind the master by WAL pages') THEN
				message = message || message_replication_lag;
			END IF;

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
			varbinding_value = varbinding_value || '|NULL|' || COALESCE(NEW.current_value, 0)::text || '|NULL|';
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

			-- Special handling for 'Write lag Alert' alert
			IF (template_name = 'Number of standby servers lag behind the master by write location') THEN
				varbinding_oid = varbinding_oid || '|' || enterprise_oid || '.7.17';
				varbinding_value = varbinding_value || '|' || COALESCE(write_message_streaming_repl, '')::text;
			END IF;

			IF (template_name = 'Number of standby servers lag behind the master by flush location') THEN
				varbinding_oid = varbinding_oid || '|' || enterprise_oid || '.7.17';
				varbinding_value = varbinding_value || '|' || COALESCE(flush_message_streaming_repl, '')::text;
			END IF;

			IF (template_name = 'Number of standby servers lag behind the master by replay location') THEN
				varbinding_oid = varbinding_oid || '|' || enterprise_oid || '.7.17';
				varbinding_value = varbinding_value || '|' || COALESCE(replay_message_streaming_repl, '')::text;
			END IF;

			-- Special handling for "Package version mismatch" alert
			IF (template_name = 'Package version mismatch') THEN
				varbinding_oid = varbinding_oid || '|' || enterprise_oid || '.7.16';
				varbinding_value = varbinding_value || '|' || COALESCE(upgrade_pkg_list, '')::text || ' ' || COALESCE(obsolete_pkg_list, '')::text;
			END IF;

			-- Special handling for segment lag/page lag alerts
			IF (template_name = 'Standby server lag behind the master by WAL segments'
				OR template_name = 'Standby server lag behind the master by WAL pages') THEN
				varbinding_oid = varbinding_oid || '|' || enterprise_oid || '.7.18';
				varbinding_value = varbinding_value || '|' || message_replication_lag;
			END IF;

			-- Send SNMP traps
			send_trap_val = pem.send_snmptrap(trap_oid, enterprise_oid, trap_version, varbinding_oid, varbinding_value);
		END IF;

		-- Script Execution
		IF is_execute_script AND (NOT is_acknowledged) AND (NOT is_flapping_detected) THEN
			PERFORM pem.create_script_job(NEW.alert_id, COALESCE(NEW.current_value, 0)::text, NEW.current_state::text, ''::text, is_execute_on_pem_server, code);
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

			message = regexp_replace(message, '%CurrentValue%', COALESCE(NEW.current_value, 0)::text);
			message = regexp_replace(message, '%DownObjects%', down_objects_list::text);

			-- Special handling for 'Write lag Alert' alert
			IF (template_name = 'Number of standby servers lag behind the master by write location') THEN
				message = message || COALESCE(write_message_streaming_repl, '')::text ;
			END IF;

			IF (template_name = 'Number of standby servers lag behind the master by flush location') THEN
				message = message || COALESCE(flush_message_streaming_repl, '')::text ;
			END IF;

			IF (template_name = 'Number of standby servers lag behind the master by replay location') THEN
				message = message || COALESCE(replay_message_streaming_repl, '')::text ;
			END IF;

			-- Special handling for 'Package version mismatch' alert
			IF (template_name = 'Package version mismatch') THEN
				message = message || E'\n' || COALESCE(upgrade_pkg_list, '')::text || E'\n' || COALESCE(obsolete_pkg_list, '')::text;
			END IF;

			-- Special handling for segment lag/page lag alerts
			IF (template_name = 'Standby server lag behind the master by WAL segments'
				OR template_name = 'Standby server lag behind the master by WAL pages') THEN
				message = message || E'\n' || message_replication_lag;
			END IF;

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
			varbinding_value = varbinding_value || '|' || COALESCE(OLD.current_value, 0)::text || '|' || COALESCE(NEW.current_value, 0)::text;

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

			-- Special handling for 'Write lag Alert' alert
			IF (template_name = 'Number of standby servers lag behind the master by write location') THEN
				varbinding_oid = varbinding_oid || '|' || enterprise_oid || '.7.17';
				varbinding_value = varbinding_value || '|' || COALESCE(write_message_streaming_repl, '')::text;
			END IF;

			IF (template_name = 'Number of standby servers lag behind the master by flush location') THEN
				varbinding_oid = varbinding_oid || '|' || enterprise_oid || '.7.17';
				varbinding_value = varbinding_value || '|' || COALESCE(flush_message_streaming_repl, '')::text;
			END IF;

			IF (template_name = 'Number of standby servers lag behind the master by replay location') THEN
				varbinding_oid = varbinding_oid || '|' || enterprise_oid || '.7.17';
				varbinding_value = varbinding_value || '|' || COALESCE(replay_message_streaming_repl, '')::text;
			END IF;

			-- Special handling for "Package version mismatch" alert
			IF (template_name = 'Package version mismatch') THEN
				varbinding_oid = varbinding_oid || '|' || enterprise_oid || '.7.16';
				varbinding_value = varbinding_value || '|' || COALESCE(upgrade_pkg_list, '')::text || ' ' || COALESCE(obsolete_pkg_list, '')::text;
			END IF;

			-- Special handling for segment lag/page lag alerts
			IF (template_name = 'Standby server lag behind the master by WAL segments'
				OR template_name = 'Standby server lag behind the master by WAL pages') THEN
				varbinding_oid = varbinding_oid || '|' || enterprise_oid || '.7.18';
				varbinding_value = varbinding_value || '|' || message_replication_lag;
			END IF;

			-- Send SNMP traps
			send_trap_val = pem.send_snmptrap(trap_oid, enterprise_oid, trap_version, varbinding_oid, varbinding_value);
		END IF;

		-- Script Execution
		IF is_execute_script AND (NOT is_acknowledged) AND (NOT is_flapping_detected) THEN
			-- If current state is NULL means alert is cleared then need to check the value of is_execute_on_clear flag.
			IF (NEW.current_state IS NULL) THEN
				IF is_execute_on_clear THEN
					PERFORM pem.create_script_job(NEW.alert_id, COALESCE(NEW.current_value, 0)::text, NEW.current_state::text, 'CLEAR'::text, is_execute_on_pem_server, code);
				END IF;
			ELSE
				PERFORM pem.create_script_job(NEW.alert_id, COALESCE(NEW.current_value, 0)::text, NEW.current_state::text, OLD.current_state::text, is_execute_on_pem_server, code);
			END IF;
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

	script_code = regexp_replace(script_code, '%AlertName%', alert_name);
	script_code = regexp_replace(script_code, '%ObjectName%', alert_object_name);
	script_code = regexp_replace(script_code, '%ThresholdValue%', alert_thresholdvalue::text);
	script_code = regexp_replace(script_code, '%CurrentValue%', current_value);
	script_code = regexp_replace(script_code, '%CurrentState%', COALESCE(current_state, '')::text);
	script_code = regexp_replace(script_code, '%OldState%', COALESCE(previous_state, '')::text);
	script_code = regexp_replace(script_code, '%AlertRaisedTime%', now()::text);

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

COMMIT TRANSACTION;
