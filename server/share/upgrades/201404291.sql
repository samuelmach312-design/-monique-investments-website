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
'SELECT 201404291::integer;'
  LANGUAGE 'sql' IMMUTABLE;

ALTER TABLE pem.alert ALTER COLUMN email_group_id SET DEFAULT NULL;
ALTER TABLE pem.alert
	ADD COLUMN low_send_trap bool NOT NULL DEFAULT FALSE,
	ADD COLUMN low_email_group_id integer DEFAULT NULL REFERENCES pem.email_group(id) ON UPDATE RESTRICT ON DELETE SET DEFAULT,
	ADD COLUMN med_send_trap bool NOT NULL DEFAULT FALSE,
	ADD COLUMN med_email_group_id integer DEFAULT NULL REFERENCES pem.email_group(id) ON UPDATE RESTRICT ON DELETE SET DEFAULT,
	ADD COLUMN high_send_trap bool NOT NULL DEFAULT FALSE,
	ADD COLUMN high_email_group_id integer DEFAULT NULL REFERENCES pem.email_group(id) ON UPDATE RESTRICT ON DELETE SET DEFAULT;

DROP FUNCTION pem.create_alert(text, integer, integer, integer, text, text, text, text, text[], text, numeric[], integer, integer, boolean, integer, boolean, boolean, timestamp with time zone, boolean, integer);
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
											high_email_group_id	integer DEFAULT NULL)
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
							med_email_group_id, high_send_trap, high_email_group_id)
	VALUES($1, $14, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, $15, $16, $17, $18, $19, $20,
			$21, $22, $23, $24, $25, $26);
$$ LANGUAGE sql;

DROP FUNCTION pem.send_email(integer, text, text);
CREATE OR REPLACE FUNCTION pem.send_email(mail_group_id integer[], subject text, message text)
RETURNS boolean AS $$
DECLARE
	mail_to text;
	mail_cc text;
	mail_bcc text;
	mail_from text;
	is_smtp_enabled boolean:= false;
	i integer;
	is_notify boolean:= false;
BEGIN
	-- Check if smtp_enabled == true, if not return.
	SELECT value INTO is_smtp_enabled FROM pem.config WHERE param = 'smtp_enabled';

	IF is_smtp_enabled THEN
		-- iterate through all the group id's and insert into the spool table
		FOR i in 1..COALESCE(array_upper(mail_group_id, 1), 0) LOOP
			-- Get email details
			SELECT
				grp_to, grp_cc, grp_bcc, grp_from
			INTO
				mail_to, mail_cc, mail_bcc, mail_from
			FROM
				pem.email_group
			WHERE
				id = mail_group_id[i];

			IF (mail_to <> '' AND mail_from <> '') THEN
				-- Insert the spool record
				INSERT INTO pem.smtp_spool(mail_to, mail_cc, mail_bcc, mail_from, subject, message, sent_status) VALUES(mail_to, mail_cc, mail_bcc, mail_from, subject, message, 'u');
				is_notify = true;
			END IF;
		END LOOP;

		IF is_notify THEN
			-- Notify listeners that a message is ready for delivery
			NOTIFY SMTP_SPOOL;
			RETURN true;
		END IF;
	END IF;

	RETURN false;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

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
BEGIN
	-- Get alert details
	SELECT
		agent_id, template_id, send_email, acknowledged, flapping_detected, send_trap, snmp_trap_version, low_send_trap, med_send_trap, high_send_trap
	INTO
		agentid, templateid, is_send_email, is_acknowledged, is_flapping_detected, is_send_trap, trap_version, low_trap, med_trap, high_trap
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
	END IF;

	RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION pem.get_email_group_ids(alert_id integer, current_state text, previous_state text) RETURNS integer[] AS
$$
DECLARE
	res integer[] = ARRAY[]::integer[];
	all_group_id integer;
	low_group_id integer;
	med_group_id integer;
	high_group_id integer;
	arrindex integer:= 1;
BEGIN
	-- Get alert details
	SELECT
		email_group_id, low_email_group_id, med_email_group_id, high_email_group_id
	INTO
		all_group_id, low_group_id, med_group_id, high_group_id
	FROM
		pem.alert
	WHERE
		id = alert_id;

	IF (all_group_id IS NOT NULL) AND (all_group_id > 0) THEN
		res[arrindex] = all_group_id;
		arrindex = arrindex + 1;
	END IF;

	IF (low_group_id IS NOT NULL) AND (low_group_id > 0) AND (current_state = 'LOW' OR previous_state = 'LOW') THEN
		res[arrindex] = low_group_id;
		arrindex = arrindex + 1;
	END IF;

	IF (med_group_id IS NOT NULL) AND (med_group_id > 0) AND (current_state = 'MEDIUM' OR previous_state = 'MEDIUM') THEN
		res[arrindex] = med_group_id;
		arrindex = arrindex + 1;
	END IF;

	IF (high_group_id IS NOT NULL) AND (high_group_id > 0) AND (current_state = 'HIGH' OR previous_state = 'HIGH') THEN
		res[arrindex] = high_group_id;
		arrindex = arrindex + 1;
	END IF;

	return res;
END
$$ LANGUAGE plpgsql;

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
	write_message_streaming_repl text;
	flush_message_streaming_repl text;
	replay_message_streaming_repl text;
	upgrade_pkg_list text;
	new_pkg_list text;
	obsolete_pkg_list text;
	mail_group_id integer[];
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
		message = regexp_replace(message, '%CurrentValue%', COALESCE(sql_ret, 0)::text);
		message = regexp_replace(message, '%CurrentState%', state::text);
		message = regexp_replace(message, '%AlertingSince%', alert_state_since::text);

		-- Get the list of down objetcs
		down_objects_list = pem.get_down_objects_list(alert_rec.template_name);
		message = regexp_replace(message, '%DownObjects%', down_objects_list::text);

		-- Special handling for 'Write lag Alert' alert
		IF (alert_rec.template_name = 'Number of standby servers lag behind the master by write location') THEN
			SELECT pem.email_write_lag_streaming_replication() INTO write_message_streaming_repl;
			message = message || COALESCE(write_message_streaming_repl, '')::text ;
		END IF;

		IF (alert_rec.template_name = 'Number of standby servers lag behind the master by flush location') THEN
			SELECT pem.email_flush_lag_streaming_replication() INTO flush_message_streaming_repl;
			message = message || COALESCE(flush_message_streaming_repl, '')::text ;
		END IF;

		IF (alert_rec.template_name = 'Number of standby servers lag behind the master by replay location') THEN
			SELECT pem.email_replay_lag_streaming_replication() INTO replay_message_streaming_repl;
			message = message || COALESCE(replay_message_streaming_repl, '')::text ;
		END IF;

		-- Get the list of obsolete packages and packages for which updates are avalibale
		IF (alert_rec.template_name = 'Package version mismatch') THEN
			SELECT upgrade_packages_list, new_packages_list, obsolete_packages_list INTO upgrade_pkg_list,
			new_pkg_list, obsolete_pkg_list FROM pem.get_mismatch_packages_list(alert_rec.agent_id);

			message = message || E'\n' || COALESCE(upgrade_pkg_list, '')::text || E'\n' || COALESCE(obsolete_pkg_list, '')::text;
		END IF;

		-- Special handling for segment lag/page lag alerts
		IF (alert_rec.template_name = 'Standby server lag behind the master by WAL segments'
			OR alert_rec.template_name = 'Standby server lag behind the master by WAL pages') THEN
			IF array_lower(alert_rec.params, 1) IS NOT NULL THEN
				message = message || E'Standby server: ' || array_to_string(replication_alert_params, ':');
			END IF;
		END IF;

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
