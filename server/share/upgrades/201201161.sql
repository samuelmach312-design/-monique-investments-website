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

-- Upgrade script for v2.0.1 GA to v2.1.0b1

BEGIN TRANSACTION;

CREATE OR REPLACE FUNCTION pem.schema_version()
  RETURNS integer AS
'SELECT 201201161::integer;'
  LANGUAGE 'sql' IMMUTABLE;

INSERT INTO pem.config VALUES ('dash_os_disk_span', 7);
INSERT INTO pem.config VALUES ('chart_disable_bullets', 0);

/****************************************
 * SMTP Email Group and Templates	*
 ****************************************/
CREATE TABLE pem.email_group(
	-- Unique ID
	id serial NOT NULL,

	-- Email group name
	name text NOT NULL,

	-- Email group 'To' field
	grp_to text NOT NULL,

	-- Email group 'Cc' field
	grp_cc text,

	-- Email group 'Bcc' field
	grp_bcc text,

	-- Email group 'From' field
	grp_from text NOT NULL,

	CONSTRAINT email_group_pkey PRIMARY KEY (id),

	-- We don't allow same name for two groups.
	CONSTRAINT email_group_name_uniq UNIQUE(name)
);

--Create Email group name 'None'
INSERT INTO pem.email_group(name, grp_to, grp_from) VALUES ('<Default>', '', '');

CREATE TABLE pem.email_template(
	-- Unique ID
	id serial NOT NULL,

	-- Display Name to show in UI
	display_name text NOT NULL,

	-- subject
	mail_subject text NOT NULL,

	--message
	mail_message text NOT NULL,

	CONSTRAINT email_template_pkey PRIMARY KEY (id),

	-- We don't allow same name for two groups.
	CONSTRAINT email_template_display_name_uniq UNIQUE(display_name)
);

--Template for alert detected
INSERT INTO pem.email_template(display_name, mail_subject, mail_message) VALUES('Alert Detected', '[%AlertType%] alert "%AlertName%" detected on %ObjectName%', E'Alert Details\n------------------------\nAlert Name: %AlertName%\nServer/Agent: %ObjectName%\nCurrent Value: %CurrentValue%\nThreshold Value: %ThresholdValue%\nAlert Detected: %AlertDetected%');
--Template for alert level increased
INSERT INTO pem.email_template(display_name, mail_subject, mail_message) VALUES('Alert Level Increased', 'Alert level increased for alert "%AlertName%" on %ObjectName%', E'Alert Details\n------------------------\nAlert Name: %AlertName%\nServer/Agent: %ObjectName%\nCurrent Value: %CurrentValue%\nThreshold Value: %ThresholdValue%\nCurrent State: %CurrentState%\nOld State: %OldState%\nState Changed: %StateChanged%');
--Template for alert level decreased
INSERT INTO pem.email_template(display_name, mail_subject, mail_message) VALUES('Alert Level Decreased', 'Alert level decreased for alert "%AlertName%" on %ObjectName%', E'Alert Details\n------------------------\nAlert Name: %AlertName%\nServer/Agent: %ObjectName%\nCurrent Value: %CurrentValue%\nThreshold Value: %ThresholdValue%\nCurrent State: %CurrentState%\nOld State: %OldState%\nState Changed: %StateChanged%');
--Template for alert cleared
INSERT INTO pem.email_template(display_name, mail_subject, mail_message) VALUES('Alert Cleared', 'Alert "%AlertName%" cleared On %ObjectName%', E'Alert Details\n------------------------\nAlert Name: %AlertName%\nServer/Agent: %ObjectName%\nAlert Cleared: %AlertCleared%');
--Template for alert reminder
INSERT INTO pem.email_template(display_name, mail_subject, mail_message) VALUES('Alert Reminder', '[Alert Reminder] for "%AlertName%"', E'Alert Details\n------------------------\nAlert Name: %AlertName%\nCurrent Value: %CurrentValue%\nThreshold Value: %ThresholdValue%\nCurrent State: %CurrentState%\nAlerting Since: %AlertingSince%');

-- Add columns for SMTP
ALTER TABLE pem.alert ADD COLUMN email_group_id integer DEFAULT 1 REFERENCES pem.email_group(id)
	ON UPDATE RESTRICT ON DELETE SET DEFAULT;
ALTER TABLE pem.alert ADD COLUMN send_email bool NOT NULL DEFAULT FALSE;
ALTER TABLE pem.alert ADD COLUMN last_mail_send timestamptz DEFAULT NULL;
ALTER TABLE pem.alert ADD COLUMN flapping_detected bool NOT NULL DEFAULT FALSE;
ALTER TABLE pem.alert ADD COLUMN last_flapping_detection_processed timestamptz NOT NULL DEFAULT current_timestamp;
ALTER TABLE pem.alert_status ADD COLUMN state_change_count integer NOT NULL DEFAULT 0;
-- Add columns for SNMP
ALTER TABLE pem.alert_template ADD COLUMN snmp_oid integer NOT NULL DEFAULT 0;
ALTER TABLE pem.alert ADD COLUMN send_trap bool NOT NULL DEFAULT FALSE;
ALTER TABLE pem.alert ADD COLUMN snmp_trap_version integer NOT NULL DEFAULT 2;
--Add colums for Audit Manager
CREATE TYPE pem.server_type AS ENUM(
       'ALL',
       'ADVANCED_SERVER',
       'POSTGRES_SERVER'
);
ALTER TABLE pem.alert_template ADD COLUMN applicable_on_server pem.server_type NOT NULL DEFAULT 'ALL';

-- Need to drop previous pem.create_alert function
-- otherwise create or replace with additional parameter creates a new function
-- instead of replacing the previous one.
DROP FUNCTION pem.create_alert(name	text,
							alert_template_id	integer,
							agent_id			integer,
							server_id			integer,
							database_name		text,
							schema_name			text,
							package_name		text,
							object_name			text,
							params				text[],
							operator			text,
							thresholds			numeric[],
							check_frequency		integer,
							history_retention	integer,
							enabled				bool);

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
											email_group_id		integer DEFAULT 1,
											send_email		bool DEFAULT false,
											flapping_detected	bool DEFAULT FALSE,
											last_flapping_detection_processed timestamptz DEFAULT current_timestamp,
											send_trap		bool DEFAULT false,
											snmp_trap_version	integer DEFAULT 2)
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
							send_trap, snmp_trap_version)
	VALUES($1, $14, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, $15, $16, $17, $18, $19, $20);
$$ LANGUAGE sql;

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
BEGIN
	probe_disabled_err = 'Required probe(s) ';
	zero_rows_err = 'Zero rows returned';

	locked_alert = false;

	FOR alert_rec in	SELECT al.*, ast.current_state AS state, at.sql,
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
									(SELECT id FROM pem.avail_servers WHERE NOT alert_blackout
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
				send_mail_val = pem.send_email(alert_rec.email_group_id, subject, message);
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

		send_mail_val = pem.send_email(alert_rec.email_group_id, subject, message);
		IF send_mail_val THEN
			-- update the time of mail send.
			UPDATE pem.alert SET last_mail_send = now() WHERE id = alert_rec.id;
		END IF;
	END IF;

	SELECT value INTO default_flapping_detection_state_change FROM pem.config WHERE param = 'flapping_detection_state_change';

	IF (NOT alert_rec.flapping_detected) THEN
		--Flapping start is true when more than N state changes have occurred over (N + 1) * (min(probe_interval) * 2) seconds
		IF ((now() - alert_rec.last_flapping_detection_processed) >=
		(((default_flapping_detection_state_change + 1) * (min_probe_interval * 2))||'seconds')::interval) THEN

			UPDATE pem.alert SET last_flapping_detection_processed = now() WHERE id = alert_rec.id;
			UPDATE pem.alert_status SET state_change_count = 0 WHERE alert_id = alert_rec.id;

			IF (alert_rec.state_change_count > default_flapping_detection_state_change) THEN
				UPDATE pem.alert SET flapping_detected = 't' WHERE id = alert_rec.id;
			END IF;
		END IF;
	ELSE
		-- Flapping end is true when zero state changes have occurred over 2N * min(probe_interval) seconds
		IF ((now() - alert_rec.last_flapping_detection_processed) >=
		((2* default_flapping_detection_state_change * min_probe_interval)||'seconds')::interval) THEN
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

/********************************
* SMTP Spooler			*
********************************/
INSERT INTO pem.config (param, value) VALUES ('smtp_server', '127.0.0.1'); -- The SMTP mail server/smarthost to use
INSERT INTO pem.config (param, value) VALUES ('smtp_port', '25'); -- The SMTP port on the mail server
INSERT INTO pem.config (param, value) VALUES ('smtp_encryption', 'f'); -- Should a secure connection be used (t/f)?
INSERT INTO pem.config (param, value) VALUES ('smtp_username', NULL); -- The username for the SMTP server
INSERT INTO pem.config (param, value) VALUES ('smtp_password', NULL); -- The password for the SMTP server
INSERT INTO pem.config (param, value) VALUES ('smtp_enabled', 't'); -- Enable/disable SMTP delivery (t/f)
INSERT INTO pem.config (param, value) VALUES ('smtp_authentication', 'f'); -- Required authentication (t/f)
INSERT INTO pem.config (param, value) VALUES ('reminder_notification_interval', '24'); -- Reminder notification interval
INSERT INTO pem.config (param, value) VALUES ('flapping_detection_state_change', '3'); -- Default no of state change for flapping detection
INSERT INTO pem.config (param, value) VALUES ('smtp_spool_retention_time', '7'); -- Default values to be used by purging function.

CREATE TABLE pem.smtp_spool (
	id 		serial NOT NULL,
	mail_to 	text NOT NULL,
	mail_cc		text,
	mail_bcc	text,
	mail_from	text NOT NULL,
	subject		text NOT NULL,
	message		text NOT NULL,
	error_count	integer,
	sent_status 	char NOT NULL,
	recorded_time	timestamp with time zone NOT NULL DEFAULT now(),

	CONSTRAINT smtp_spool_pkey PRIMARY KEY (id),

	CONSTRAINT smtp_spool_sent_status
	CHECK (sent_status IN ('s', 'u', 'i'))
);

CREATE OR REPLACE FUNCTION pem.send_email(mail_group_id integer, subject text, message text)
RETURNS boolean AS $$
DECLARE
	mail_to text;
	mail_cc text;
	mail_bcc text;
	mail_from text;
	is_smtp_enabled boolean:= false;
BEGIN
	-- Check if smtp_enabled == true, if not return.
	SELECT value INTO is_smtp_enabled FROM pem.config WHERE param = 'smtp_enabled';

	-- Get email details
	SELECT
		grp_to, grp_cc, grp_bcc, grp_from
	INTO
		mail_to, mail_cc, mail_bcc, mail_from
	FROM
		pem.email_group
	WHERE
		id = mail_group_id;

	-- IF any of the flag is false then no SMTP mail should be send.
	IF is_smtp_enabled AND (mail_to <> '' AND mail_from <> '') THEN

		-- Insert the spool record
		INSERT INTO pem.smtp_spool(mail_to, mail_cc, mail_bcc, mail_from, subject, message, sent_status) VALUES(mail_to, mail_cc, mail_bcc, mail_from, subject, message, 'u');
		-- Notify listeners that a message is ready for delivery
		NOTIFY SMTP_SPOOL;

		RETURN true;
	END IF;

	RETURN false;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE OR REPLACE FUNCTION pem.send_notifications() RETURNS trigger AS $$
DECLARE
	subject text;
	message text;
	mail_group_id integer;
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

BEGIN
	-- Get alert details
	SELECT
		email_group_id, send_email, acknowledged, flapping_detected, send_trap, snmp_trap_version
	INTO
		mail_group_id, is_send_email, is_acknowledged, is_flapping_detected, is_send_trap, trap_version
	FROM
		pem.alert
	WHERE
		id = NEW.alert_id;

	IF ((TG_OP = 'INSERT') AND (NEW.current_state IS NOT NULL)) THEN
		-- Update state change count
		UPDATE pem.alert_status SET state_change_count = state_change_count + 1 WHERE alert_id = NEW.alert_id;

		-- SMTP Notifications
		IF is_send_email AND (NOT is_acknowledged) AND (NOT is_flapping_detected) THEN
			-- Create subject and message
			SELECT subject_mail, message_mail INTO subject, message FROM pem.create_email(NEW.alert_id, 'Alert Detected');
			subject = regexp_replace(subject, '%AlertType%', NEW.current_state::text);
			message = regexp_replace(message, '%CurrentValue%', COALESCE(NEW.current_value, 0)::text);
			message = regexp_replace(message, '%AlertDetected%', now()::text);
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
				varbinding_value = varbinding_value || NEW.current_state;
			END IF;
			-- Append current timestamp
			varbinding_value = varbinding_value || '|' || now()::text;

			-- Send SNMP traps
			send_trap_val = pem.send_snmptrap(trap_oid, enterprise_oid, trap_version, varbinding_oid, varbinding_value);
		END IF;
	END IF;

	IF ((TG_OP = 'UPDATE') AND (NEW.current_state IS DISTINCT FROM OLD.current_state)) THEN
		-- Update state change count
		UPDATE pem.alert_status SET state_change_count = state_change_count + 1 WHERE alert_id = NEW.alert_id;

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
				varbinding_value = varbinding_value || '|' || OLD.current_state;
			END IF;

			IF NEW.current_state IS NULL THEN
				varbinding_value = varbinding_value || '|CLEAR';
			ELSE
				varbinding_value = varbinding_value || '|' || NEW.current_state;
			END IF;
			-- Append current timestamp
			varbinding_value = varbinding_value || '|' || now()::text;

			-- Send SNMP traps
			send_trap_val = pem.send_snmptrap(trap_oid, enterprise_oid, trap_version, varbinding_oid, varbinding_value);
		END IF;
	END IF;

	RETURN NEW;
END;
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
BEGIN
	-- Get alert, agent, server details
	SELECT
		a.name, a.agent_id, a.server_id, a.database_name, a.schema_name, a.object_name, a.thresholds,
		s.description, s.server, s.port,
		ag.description
	INTO
		alert_name, alert_agent_id, alert_server_id, alert_database_name, alert_schema_name, alert_object_name,
		alert_thresholdvalue, server_name, server_ip, server_port,
		agent_name
	FROM
		pem.alert a
		LEFT JOIN pem.avail_servers s ON a.server_id = s.id
		LEFT JOIN pem.agent ag ON a.agent_id = ag.id
	WHERE
		a.id = alert_id;

	SELECT mail_subject, mail_message INTO subject_mail, message_mail FROM pem.email_template WHERE display_name = template;

	subject_mail = regexp_replace(subject_mail, '%AlertName%', alert_name);
	subject_mail = regexp_replace(subject_mail, '%ObjectName%', COALESCE(server_name || ' ('|| server_ip ||': ' || server_port || ')', agent_name));
	message_mail = regexp_replace(message_mail, '%AlertName%', alert_name);
	message_mail = regexp_replace(message_mail, '%ObjectName%', COALESCE(server_name || ' ('|| server_ip ||': ' || server_port || ')', agent_name));
	message_mail = regexp_replace(message_mail, '%ThresholdValue%', alert_thresholdvalue::text);
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION pem.purge_smtp_spool()
RETURNS void AS $$
	DELETE FROM pem.smtp_spool WHERE sent_status = 's' AND (now() - recorded_time) >= ((SELECT value FROM pem.config WHERE param = 'smtp_spool_retention_time')||'days')::interval;
$$ LANGUAGE sql SECURITY DEFINER;

CREATE TRIGGER send_notifications_trigger AFTER INSERT OR UPDATE ON pem.alert_status FOR EACH ROW EXECUTE PROCEDURE pem.send_notifications();
COMMENT ON TRIGGER send_notifications_trigger ON pem.alert_status IS 'Send notifications';

REVOKE EXECUTE ON FUNCTION pem.send_email(mail_group_id integer, subject text, message text) FROM pem_user;
REVOKE EXECUTE ON FUNCTION pem.purge_smtp_spool() FROM pem_user;
REVOKE EXECUTE ON FUNCTION pem.send_email(mail_group_id integer, subject text, message text) FROM pem_admin;
REVOKE EXECUTE ON FUNCTION pem.purge_smtp_spool() FROM pem_admin;
REVOKE EXECUTE ON FUNCTION pem.send_email(mail_group_id integer, subject text, message text) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION pem.purge_smtp_spool() FROM PUBLIC;

GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE pem.smtp_spool TO pem_agent;
GRANT EXECUTE ON FUNCTION pem.send_email(mail_group_id integer, subject text, message text) TO pem_agent;
GRANT EXECUTE ON FUNCTION pem.purge_smtp_spool() TO pem_agent;

/* upgrade sql code for adding client_address and client_port columns to session_info probe */
UPDATE pem.probe SET probe_code = 'SELECT datname AS database_name, procpid, usename, client_addr, client_port, backend_start, xact_start, query_start,'
	' waiting AS is_waiting, current_query = $$<IDLE>$$ AS is_idle,'
	' current_query = $$<IDLE> in transaction$$ AS is_idle_in_transaction,'
	' current_query ilike $$VACUUM%$$ as is_vacuum,'
	' client_port IS NULL AND (current_query like $$autovacuum:%$$ OR current_query like $$VACUUM%$$) as is_autovacuum,'
	' now() AS capture_time'
	' FROM pg_catalog.pg_stat_activity'
WHERE internal_name = 'session_info';

UPDATE pem.probe_server_version
	SET probe_code = 'SELECT datname AS database_name, procpid, usename, client_addr, client_port, backend_start, NULL::timestamptz AS xact_start, query_start,'
		' waiting AS is_waiting, current_query = $$<IDLE>$$ AS is_idle,'
		' current_query = $$<IDLE> in transaction$$ AS is_idle_in_transaction,'
		' current_query ilike $$VACUUM%$$ as is_vacuum,'
		' client_port IS NULL AND (current_query like $$autovacuum:%$$ OR current_query like $$VACUUM%$$) as is_autovacuum,'
		' now() AS capture_time'
		' FROM pg_catalog.pg_stat_activity'
WHERE probe_id = (SELECT id FROM pem.probe WHERE internal_name = 'session_info') AND server_version_id = 10802;

UPDATE pem.probe_server_version
	SET probe_code = 'SELECT datname AS database_name, procpid, usename, client_addr, client_port, backend_start, NULL::timestamptz AS xact_start, query_start,'
		' waiting AS is_waiting, current_query = $$<IDLE>$$ AS is_idle,'
		' current_query = $$<IDLE> in transaction$$ AS is_idle_in_transaction,'
		' current_query ilike $$VACUUM%$$ as is_vacuum,'
		' client_port IS NULL AND (current_query like $$autovacuum:%$$ OR current_query like $$VACUUM%$$) as is_autovacuum,'
		' now() AS capture_time'
		' FROM pg_catalog.pg_stat_activity'
WHERE probe_id = (SELECT id FROM pem.probe WHERE internal_name = 'session_info') AND server_version_id = 20803;

INSERT INTO pem.probe_column(probe_id, internal_name, display_name, display_position, classification, sql_data_type, unit_of_value, calculate_pit, discard_history, pit_by_default) SELECT id, 'client_addr', 'Client Address', 13, 'm', 'text', '', false, false, false FROM pem.probe WHERE internal_name='session_info';
INSERT INTO pem.probe_column(probe_id, internal_name, display_name, display_position, classification, sql_data_type, unit_of_value, calculate_pit, discard_history, pit_by_default) SELECT id, 'client_port', 'Client Port', 14, 'm', 'integer', '', false, false, false FROM pem.probe WHERE internal_name='session_info';

ALTER TABLE pemdata.session_info ADD COLUMN client_addr text;
ALTER TABLE pemdata.session_info ADD COLUMN client_port integer;
ALTER TABLE pemhistory.session_info ADD COLUMN client_addr text;
ALTER TABLE pemhistory.session_info ADD COLUMN client_port integer;

CREATE OR REPLACE FUNCTION pemdata.copy_session_info_to_history() RETURNS TRIGGER AS $$
BEGIN
	IF (TG_OP = 'INSERT' OR TG_OP = 'UPDATE') THEN
		INSERT INTO pemhistory.session_info (recorded_time, server_id, database_name, procpid, usename, backend_start, xact_start, query_start, is_waiting, is_idle, is_idle_in_transaction, is_vacuum, is_autovacuum, capture_time, client_addr, client_port) VALUES (NEW.recorded_time, NEW.server_id, NEW.database_name, NEW.procpid, NEW.usename, NEW.backend_start, NEW.xact_start, NEW.query_start, NEW.is_waiting, NEW.is_idle, NEW.is_idle_in_transaction, NEW.is_vacuum, NEW.is_autovacuum, NEW.capture_time, NEW.client_addr, NEW.client_port);
	ELSIF EXISTS(SELECT 1 FROM pem.server WHERE id = OLD.server_id) THEN
		INSERT INTO pemhistory.session_info (server_id, procpid) VALUES (OLD.server_id, OLD.procpid);
	END IF;
	RETURN NEW;
END;
$$ LANGUAGE plpgsql;

/* FB case 19365 fix. CM shows some useless metrics. */
ALTER TABLE pem.probe_column ADD COLUMN is_graphable boolean NOT NULL DEFAULT false;
UPDATE pem.probe_column SET is_graphable = true WHERE classification = 'm' AND sql_data_type LIKE ANY (ARRAY['smallint%', 'integer%', 'bigint%', 'decimal%', 'numeric%', 'real%', 'double precision%']) AND NOT sql_data_type LIKE E'%[]' AND NOT internal_name LIKE ANY (ARRAY['device_id', 'client_port']);

-- Team related changes
ALTER TABLE pem.server ADD COLUMN owner oid;
COMMENT ON COLUMN pem.server.owner IS 'The owner of the registered server';
ALTER TABLE pem.server ADD COLUMN team text;
COMMENT ON COLUMN pem.server.team IS 'Defines the visibility of the server in particular role/team';
-- Alert blackout related changes
ALTER TABLE pem.server ADD COLUMN alert_blackout boolean DEFAULT false;
COMMENT ON COLUMN pem.server.alert_blackout IS 'Blackout server alert processing';
ALTER TABLE pem.agent ADD COLUMN alert_blackout boolean DEFAULT false;
COMMENT ON COLUMN pem.agent.alert_blackout IS 'Blackout agent alert processing';

CREATE OR REPLACE FUNCTION pem.server_insertion() RETURNS trigger AS $$
DECLARE
	curr_user_oid oid;
BEGIN
	IF NEW.owner IS NULL THEN
		SELECT oid INTO curr_user_oid FROM pg_catalog.pg_roles WHERE rolname = current_user;
		NEW.owner := curr_user_oid;
	END IF;
	RETURN NEW;
END
$$ LANGUAGE 'plpgsql';

CREATE TRIGGER server_insertion
	BEFORE INSERT ON pem.server
	FOR EACH ROW EXECUTE PROCEDURE pem.server_insertion();

-- Only these server(s) are available, which meets following conditions:
-- 1.  Active
-- 2a. current_user is a superuser.
-- OR
-- 2b. No team is specified.
-- OR
-- 2c. Current User is the owner
-- OR
-- 2d. Current User is the member of the specified team/role.
CREATE OR REPLACE VIEW pem.avail_servers AS
	SELECT
		s.id AS id,
		s.description AS description,
		s.server AS server,
		s.port AS port,
		s.database AS database,
		s.ssl AS ssl,
		s.serviceid AS serviceid,
		s.active AS active,
		s.hostaddr AS hostaddr,
		s.service AS service,
		s.alert_blackout AS alert_blackout,
		s.owner AS owner,
		s.team AS team,
		o.rolname AS server_owner
	FROM (SELECT s.*, r.rolsuper AS rolsuper FROM pem.server s, pg_catalog.pg_roles r WHERE r.rolname = current_user) AS s
		LEFT OUTER JOIN pg_catalog.pg_roles o ON (o.oid = s.owner)
		LEFT OUTER JOIN pg_catalog.pg_roles t ON (t.rolname = s.team)
	WHERE
	    -- Only active servers
		s.active AND
		-- Is a superuser
		(s.rolsuper OR
			-- No team provided
			s.team IS NULL OR s.team = '' OR
			-- Owner of the server
			o.rolname = current_user OR
			-- Valid team provided and current_user is member of the it
			(t.oid IS NOT NULL AND pg_catalog.pg_has_role(s.team, 'member')));

UPDATE pem.alert_template SET sql =
	$sql$
SELECT
    count(ps.id)
FROM
    pem.avail_servers ps LEFT OUTER JOIN pem.server_heartbeat psh ON (ps.id = psh.server_id),
    pem.agent pa LEFT OUTER JOIN pem.agent_heartbeat pah ON (pa.id = pah.agent_id),
    pem.agent_server_binding pasb
WHERE
    pa.id = pasb.agent_id AND
    ps.id = pasb.server_id AND
    pa.active = TRUE AND
	NOT ps.alert_blackout AND
    CASE WHEN psh.agent_id IS NULL THEN FALSE ELSE psh.agent_id = pa.id END AND
	CASE WHEN pah.agent_id is NULL THEN FALSE ELSE pah.last_heartbeat > now() - (pa.heartbeat_interval)*2*'1 second'::interval END AND
	CASE WHEN psh.server_id IS NULL THEN FALSE ELSE psh.last_heartbeat < now() - (pa.heartbeat_interval)*2*'1 second'::interval END$sql$
WHERE display_name = 'Servers Down' AND object_type = 50;

UPDATE pem.alert_template SET sql =
	$sql$
SELECT
    count(pa.id)
FROM
    pem.agent pa LEFT OUTER JOIN pem.agent_heartbeat pah ON (pa.id = pah.agent_id)
WHERE
    pa.active = TRUE AND
	NOT pa.alert_blackout AND
    CASE WHEN pah.agent_id IS NULL THEN FALSE ELSE pah.last_heartbeat < now() - (pa.heartbeat_interval)*2*'1 second'::interval END$sql$
WHERE display_name = 'Agents Down' AND object_type = 50;

UPDATE pem.alert_template SET sql =
	$sql$
SELECT
	count(*)
FROM
	pem.alert al
WHERE 	COALESCE(error_message, '') <> ''
AND 	CASE WHEN al.agent_id = -1 THEN TRUE
	ELSE al.agent_id IN (SELECT id FROM pem.agent WHERE active AND NOT alert_blackout)
	END
AND 	CASE WHEN al.server_id IS NULL THEN TRUE
	ELSE al.server_id IN
		(SELECT id FROM pem.avail_servers WHERE NOT alert_blackout
		INTERSECT
		SELECT server_id FROM pem.agent_server_binding)
        END$sql$
WHERE display_name = 'Alert Errors' AND object_type = 50;

/******************************
 * Capacity Manager Templates *
 ******************************/

-- Types of time period options for capacity manager
CREATE TYPE pem.cm_time_period AS ENUM(
	'START_DATE_TO_END_DATE',		-- Start date and end date
	'START_DATE_TO_THREHOLD',		-- Start date and threshold
	'HISTORIC_DATE_TO_EXTRAPOLATED_DATE',	-- Historical date and extrapolated date
	'HISTORIC_DATE_TO_THRESHOLD'		-- Historical date and threshold
);

COMMENT ON TYPE pem.cm_time_period IS 'Types of time period options for capacity manager';

-- Threshold operators for capacity manager
CREATE TYPE pem.cm_threshold_operator AS ENUM(
	'FALLS_BELOW',		-- Falls below
	'EXCEEDS'		-- Exceeds
);

COMMENT ON TYPE pem.cm_threshold_operator IS 'Threshold operators for capacity manager';

-- Types of report for capacity manager
CREATE TYPE pem.cm_report_type AS ENUM(
	'GRAPH',		-- Graph
	'TABLE',		-- Table
	'GRAPH_AND_TABLE'	-- Graph and table
);

COMMENT ON TYPE pem.cm_report_type IS 'Types of report for capacity manager';

-- Output location for capacity manager reports
CREATE TYPE pem.cm_output_loc AS ENUM(
	'NEW_TAB',	-- New tab
	'PREV_TAB',	-- Previous tab
	'FILE'		-- Html file
);

COMMENT ON TYPE pem.cm_output_loc IS 'Output location for capacity manager reports';

-- Aggregation associated with metric for capacity manager reports
CREATE TYPE pem.cm_metric_aggregation AS ENUM(
	'AVERAGE',	-- Average
	'MAXIMUM',	-- Maximum
	'MINIMUM',	-- Minimum
	'FIRST'		-- First
);

COMMENT ON TYPE pem.cm_metric_aggregation IS 'Aggregation associated with metric for capacity manager reports';

CREATE TABLE pem.cm_template_path (
	-- Unique ID
	id serial,

	-- Parent ID
	parent_id integer,

	-- Folder/template title
	title text NOT NULL,

	CONSTRAINT template_path_pkey PRIMARY KEY (id),
	CONSTRAINT template_path_parent_fkey FOREIGN KEY (parent_id)
		REFERENCES pem.cm_template_path (id) MATCH SIMPLE
		ON UPDATE NO ACTION ON DELETE CASCADE
);

CREATE TABLE pem.cm_template (
	-- Unique ID
	id serial,

	-- Folder ID
	folder_id integer NOT NULL,

	-- Template name
	name text NOT NULL,

	-- Individual report
	individual_report boolean,

	-- Time period options
	time_period pem.cm_time_period,

	-- Start date
	start_date timestamptz,

	-- End date
	end_date timestamptz,

	-- Historical days
	historical_days integer,

	-- Extrapolated days
	extrapolated_days integer,

	-- Index of selected threshold metric
	threshold_index integer,

	-- selected operator for threshold
	threshold_opr pem.cm_threshold_operator,

	-- threshold value
	threshold_value numeric,

	-- Report type
	report_type pem.cm_report_type,

	-- Report output type
	output_loc pem.cm_output_loc,

	-- Report output value (only for file and email options)
	output_value text,

	CONSTRAINT cm_template_pkey PRIMARY KEY (id),
	CONSTRAINT cm_template_folder_fkey FOREIGN KEY (folder_id)
		REFERENCES pem.cm_template_path (id) MATCH SIMPLE
		ON UPDATE NO ACTION ON DELETE CASCADE
);

CREATE TABLE pem.cm_template_metrics (
	-- Unique ID
	id serial,

	-- ID of associated option in pem.cm_template
	template_id integer NOT NULL,

	-- Metric ID
	metric_id integer,

	-- Metric name
	metric_name text,

	-- Metric display name
	metric_disp_name text,

	-- Metric agent id
	metric_agent_id integer,

	-- Metric target attribute
	metric_target_attributes text,

	-- Metric target values
	metric_target_values text,

	-- Metric type pit
	metric_calculate_pit text,

	-- Metric unit
	metric_unit text,

	-- Server type for the given metric
	metric_server_type text,

	-- Query type for given metric
	metric_query_type integer,

	-- Path of the object related to metric
	metric_object text,

	-- Aggregation of each metric
	metric_aggregation pem.cm_metric_aggregation,

	CONSTRAINT cm_template_metrics_pkey PRIMARY KEY (id),
	CONSTRAINT cm_template_metrics_fkey FOREIGN KEY (template_id)
		REFERENCES pem.cm_template (id) MATCH SIMPLE
		ON UPDATE NO ACTION ON DELETE CASCADE
);

INSERT INTO pem.cm_template_path (id, title) VALUES (0, 'Templates');

/****************************************
 * Dashboard Auto-refresh config values *
 ****************************************/

INSERT INTO pem.config VALUES ('dash_objectact_objtoptables_timeout', 300);
INSERT INTO pem.config VALUES ('dash_objectact_objtopindexes_timeout', 300);
INSERT INTO pem.config VALUES ('dash_objectact_objectactivity_timeout', 300);
INSERT INTO pem.config VALUES ('dash_objectact_objstorage_timeout', 300);
INSERT INTO pem.config VALUES ('dash_probe_log_timeout', 300);
INSERT INTO pem.config VALUES ('dash_sess_waits_nowaits_timeout', 300);
INSERT INTO pem.config VALUES ('dash_sess_waits_timewait_timeout', 300);
INSERT INTO pem.config VALUES ('dash_sess_waits_waitdtl_timeout', 300);
INSERT INTO pem.config VALUES ('dash_sys_waits_nowaits_timeout', 300);
INSERT INTO pem.config VALUES ('dash_sys_waits_timewait_timeout', 300);
INSERT INTO pem.config VALUES ('dash_sys_waits_waitdtl_timeout', 300);
INSERT INTO pem.config VALUES ('dash_sessact_workload_timeout', 300);
INSERT INTO pem.config VALUES ('dash_sessact_lockact_timeout', 300);
INSERT INTO pem.config VALUES ('dash_storage_dbovervw_timeout', 300);
INSERT INTO pem.config VALUES ('dash_storage_tblspcovervw_timeout', 300);
INSERT INTO pem.config VALUES ('dash_storage_hostovervw_timeout', 300);
INSERT INTO pem.config VALUES ('dash_storage_dbdtls_timeout', 300);
INSERT INTO pem.config VALUES ('dash_storage_tblspcdtls_timeout', 300);
INSERT INTO pem.config VALUES ('dash_storage_hostdtls_timeout', 300);
INSERT INTO pem.config VALUES ('dash_memory_servmemact_timeout', 1800);
INSERT INTO pem.config VALUES ('dash_memory_servmemconf_timeout', 300);
INSERT INTO pem.config VALUES ('dash_memory_hostmemact_timeout', 1800);
INSERT INTO pem.config VALUES ('dash_memory_hostmemconf_timeout', 300);
INSERT INTO pem.config VALUES ('dash_io_dbio_timeout', 1800);
INSERT INTO pem.config VALUES ('dash_io_rowact_timeout', 1800);
INSERT INTO pem.config VALUES ('dash_io_chkpt_timeout', 1800);
INSERT INTO pem.config VALUES ('dash_io_hottbl_timeout', 300);
INSERT INTO pem.config VALUES ('dash_io_hotindx_timeout', 300);
INSERT INTO pem.config VALUES ('dash_io_objectio_timeout', 300);
INSERT INTO pem.config VALUES ('dash_db_storage_timeout', 300);
INSERT INTO pem.config VALUES ('dash_db_useract_timeout', 1800);
INSERT INTO pem.config VALUES ('dash_db_connovervw_timeout', 300);
INSERT INTO pem.config VALUES ('dash_db_io_timeout', 1800);
INSERT INTO pem.config VALUES ('dash_db_rowact_timeout', 1800);
INSERT INTO pem.config VALUES ('dash_db_comrol_timeout', 1800);
INSERT INTO pem.config VALUES ('dash_db_hottable_timeout', 300);
INSERT INTO pem.config VALUES ('dash_os_cpu_timeout', 1800);
INSERT INTO pem.config VALUES ('dash_os_storage_timeout', 1800);
INSERT INTO pem.config VALUES ('dash_os_memory_timeout', 1800);
INSERT INTO pem.config VALUES ('dash_os_util_timeout', 1800);
INSERT INTO pem.config VALUES ('dash_os_io_timeout', 1800);
INSERT INTO pem.config VALUES ('dash_os_packet_timeout', 1800);
INSERT INTO pem.config VALUES ('dash_os_traffic_timeout', 1800);
INSERT INTO pem.config VALUES ('dash_server_dbsize_timeout', 1800);
INSERT INTO pem.config VALUES ('dash_server_tabspacesize_timeout', 1800);
INSERT INTO pem.config VALUES ('dash_server_sharedbuff_timeout', 1800);
INSERT INTO pem.config VALUES ('dash_server_hostmem_timeout', 300);
INSERT INTO pem.config VALUES ('dash_server_useract_timeout', 1800);
INSERT INTO pem.config VALUES ('dash_server_connovervw_timeout', 300);
INSERT INTO pem.config VALUES ('dash_server_disk_timeout', 1800);
INSERT INTO pem.config VALUES ('dash_server_rowact_timeout', 1800);
INSERT INTO pem.config VALUES ('dash_server_comrol_timeout', 1800);
INSERT INTO pem.config VALUES ('dash_server_database_timeout', 300);
INSERT INTO pem.config VALUES ('dash_global_overview_timeout', 60);
INSERT INTO pem.config VALUES ('dash_header_timeout', 60);
INSERT INTO pem.config VALUES ('dash_alerts_timeout', 60);

-- Replace '' with NULL in pem.alert table.
UPDATE pem.alert SET
	database_name = (CASE WHEN database_name = '' THEN NULL ELSE database_name END),
	schema_name = (CASE WHEN schema_name = '' THEN NULL ELSE schema_name END),
	package_name = (CASE WHEN package_name = '' THEN NULL ELSE package_name END),
	object_name = (CASE WHEN object_name = '' THEN NULL ELSE object_name END);

-- Need to drop previous pem.create_alert_template function
-- otherwise create or replace with additional parameter creates a new function
-- instead of replacing the previous one.
DROP FUNCTION pem.create_alert_template(
									name					text,
									description				text,
									sql						text,
									object_type				integer,
									param_names				text[],
									param_types				pem.alert_param_type[],
									param_units				text[],
									threshold_unit			text,
									probe_dependency_list	text[],
									default_check_frequency	integer,
									default_history_retention	integer);

CREATE OR REPLACE FUNCTION pem.create_alert_template(
									name				text,
									description			text,
									sql				text,
									object_type			integer,
									param_names			text[],
									param_types			pem.alert_param_type[],
									param_units			text[],
									threshold_unit			text,
									probe_dependency_list		text[] DEFAULT '{}',
									snmp_oid			integer DEFAULT 0,
									applicable_on_server            pem.server_type DEFAULT 'ALL',
									default_check_frequency		integer DEFAULT 1,
									default_history_retention	integer DEFAULT 30
									)
RETURNS VOID AS $$
	/*
	 * If we ever change to pl/pgsql, we might want to validate input and RAISE
	 * exceptions here.
	 *
	 * If this INSERT fails the user will see the ERROR with this functions
	 * name in context, hence it doesn't seem any worse than validating params
	 * and RAISE'ing errors, except that by using RAISE we can provide friendly
	 * hints.
	 */
	INSERT INTO pem.alert_template (display_name, description, sql, object_type,
									param_names, param_types, param_units,
									threshold_unit, probe_dependency_list, snmp_oid, applicable_on_server,
									default_check_frequency, default_history_retention)
	VALUES($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13);
$$ LANGUAGE SQL;

/********************************
* SNMP Spooler			*
********************************/
INSERT INTO pem.config (param, value) VALUES ('snmp_server', '127.0.0.1');; -- The SNMP trap recipient server
INSERT INTO pem.config (param, value) VALUES ('snmp_port', '162'); -- The SNMP port on the recipient server
INSERT INTO pem.config (param, value) VALUES ('snmp_community', 'public'); -- The SNMP community name
INSERT INTO pem.config (param, value) VALUES ('snmp_enabled', 't'); -- Enable/disable SNMP trap delivery
INSERT INTO pem.config (param, value) VALUES ('snmp_spool_retention_time', '7'); -- Default values to be used by purging function.

CREATE TABLE pem.snmp_spool (
	id 			serial NOT NULL,
	trap_oid 		text NOT NULL,
	enterprise_oid		text NOT NULL,
	trap_version		integer NOT NULL DEFAULT 1,
	varbinding_oid		text,
	varbinding_value	text,
	sent_status 		char NOT NULL,
	recorded_time		timestamp with time zone NOT NULL DEFAULT now(),

	CONSTRAINT snmp_spool_pkey PRIMARY KEY (id),

	CONSTRAINT snmp_spool_sent_status
	CHECK (sent_status IN ('s', 'u', 'i'))
);

CREATE OR REPLACE FUNCTION pem.send_snmptrap(trap_oid text, enterprise_oid text, trap_version integer, varbinding_oid text, varbinding_value text)
RETURNS boolean AS $$
DECLARE
	is_snmp_enabled boolean:= false;
BEGIN
	-- Check if snmp_enabled == true, if not return.
	SELECT value INTO is_snmp_enabled FROM pem.config WHERE param = 'snmp_enabled';

	IF is_snmp_enabled THEN
		/* Insert the spool record */
		INSERT INTO pem.snmp_spool(trap_oid, enterprise_oid, trap_version, varbinding_oid, varbinding_value, sent_status) VALUES(trap_oid, enterprise_oid, trap_version, varbinding_oid, varbinding_value, 'u');

		/* Notify listeners that a message is ready for delivery */
		NOTIFY SNMP_SPOOL;

		RETURN true;
	END IF;

	RETURN false;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE OR REPLACE FUNCTION pem.create_trap(alert_id integer, OUT snmp_trap_oid text, OUT snmp_enterprise_oid text, OUT snmp_varbinding_oid text, OUT snmp_varbinding_value text) AS $$
DECLARE
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
	alert_template_id integer;
	alert_object_type integer;
	alert_snmp_oid integer;
BEGIN
	snmp_enterprise_oid = '.1.3.6.1.4.1.27645.5444';

	-- Get alert, agent, server details
	SELECT
		a.agent_id, a.server_id, a.database_name, a.schema_name, a.object_name, a.thresholds, a.template_id,
		s.description, s.server, s.port,
		ag.description
	INTO
		alert_agent_id, alert_server_id, alert_database_name, alert_schema_name, alert_object_name,
		alert_thresholdvalue, alert_template_id, server_name, server_ip, server_port,
		agent_name
	FROM
		pem.alert a
		LEFT JOIN pem.server s ON a.server_id = s.id
		LEFT JOIN pem.agent ag ON a.agent_id = ag.id
	WHERE
		a.id = alert_id;

	-- We used "|" as one of the delimiter for snmp_varbinding_oid and snmp_varbinding_value, so replacing it with " " to avoid errors.
	agent_name = replace(agent_name, '|', ' ');
	server_name = replace(server_name, '|', ' ');
	alert_database_name = replace(alert_database_name, '|', ' ');
	alert_object_name = replace(alert_object_name, '|', ' ');
	alert_schema_name = replace(alert_schema_name, '|', ' ');

	-- Get SNMP OID
	SELECT snmp_oid, object_type INTO alert_snmp_oid, alert_object_type FROM pem.alert_template WHERE id = alert_template_id;

	CASE
	WHEN alert_object_type = 50 THEN
		snmp_trap_oid = snmp_enterprise_oid || '.6.' || alert_snmp_oid;
	WHEN alert_object_type = 100 THEN
		snmp_trap_oid = snmp_enterprise_oid || '.1.' || alert_snmp_oid;
		snmp_varbinding_oid =  snmp_enterprise_oid || '.7.1|' || snmp_enterprise_oid || '.7.3|' || snmp_enterprise_oid ||
							'.7.8|' || snmp_enterprise_oid || '.7.9|' || snmp_enterprise_oid || '.7.10|' || snmp_enterprise_oid ||
							'.7.11|' || snmp_enterprise_oid || '.7.12|' || snmp_enterprise_oid || '.7.13';
		snmp_varbinding_value = alert_agent_id || '|' || agent_name || '|' || alert_thresholdvalue;
	WHEN alert_object_type = 200 THEN
		snmp_trap_oid = snmp_enterprise_oid || '.2.' || alert_snmp_oid;
		snmp_varbinding_oid =  snmp_enterprise_oid || '.7.2|' || snmp_enterprise_oid || '.7.4|' || snmp_enterprise_oid ||
							'.7.8|' || snmp_enterprise_oid || '.7.9|' || snmp_enterprise_oid || '.7.10|' || snmp_enterprise_oid ||
							'.7.11|' || snmp_enterprise_oid || '.7.12|' || snmp_enterprise_oid || '.7.13';
		snmp_varbinding_value = alert_server_id || '|' || server_name || ' ('|| server_ip ||': ' || server_port || ')|' || alert_thresholdvalue;
	WHEN alert_object_type = 300 THEN
		snmp_trap_oid = snmp_enterprise_oid || '.3.' || alert_snmp_oid;
		snmp_varbinding_oid =  snmp_enterprise_oid || '.7.2|' || snmp_enterprise_oid || '.7.4|' || snmp_enterprise_oid ||
							'.7.5|' || snmp_enterprise_oid || '.7.8|' || snmp_enterprise_oid || '.7.9|' || snmp_enterprise_oid ||
							'.7.10|'|| snmp_enterprise_oid || '.7.11|' || snmp_enterprise_oid || '.7.12|' || snmp_enterprise_oid || '.7.13';
		snmp_varbinding_value = alert_server_id || '|' || server_name || ' ('|| server_ip ||': ' || server_port || ')|' ||
							alert_database_name || '|' || alert_thresholdvalue;
	WHEN alert_object_type = 400 THEN
		snmp_trap_oid = snmp_enterprise_oid || '.4.' || alert_snmp_oid;
		snmp_varbinding_oid =  snmp_enterprise_oid || '.7.2|' || snmp_enterprise_oid || '.7.4|' || snmp_enterprise_oid ||
							'.7.5|' || snmp_enterprise_oid || '.7.6|' || snmp_enterprise_oid || '.7.8|' || snmp_enterprise_oid ||
							'.7.9|' || snmp_enterprise_oid || '.7.10|'|| snmp_enterprise_oid || '.7.11|' || snmp_enterprise_oid ||
							'.7.12|' || snmp_enterprise_oid || '.7.13';
		snmp_varbinding_value = alert_server_id || '|' || server_name || ' ('|| server_ip ||': ' || server_port || ')|' ||
							 alert_database_name || '|' || alert_schema_name || '|' || alert_thresholdvalue;
	WHEN alert_object_type > 400 THEN
		snmp_trap_oid = snmp_enterprise_oid || '.5.' || alert_snmp_oid;
		snmp_varbinding_oid =  snmp_enterprise_oid || '.7.2|' || snmp_enterprise_oid || '.7.4|' || snmp_enterprise_oid ||
							'.7.5|' || snmp_enterprise_oid || '.7.6|' || snmp_enterprise_oid || '.7.7|' || snmp_enterprise_oid ||
							'.7.8|' || snmp_enterprise_oid || '.7.9|'|| snmp_enterprise_oid || '.7.10|' || snmp_enterprise_oid ||
							'.7.11|'|| snmp_enterprise_oid || '.7.12|' || snmp_enterprise_oid || '.7.13';
		snmp_varbinding_value = alert_server_id || '|' || server_name || ' ('|| server_ip ||': ' || server_port || ')|' ||
							 alert_database_name || '|' || alert_schema_name || '|' || alert_object_name || '|' ||
							 alert_thresholdvalue;
	END CASE;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION pem.purge_snmp_spool()
RETURNS void AS $$
	DELETE FROM pem.snmp_spool WHERE sent_status = 's' AND (now() - recorded_time) >= ((SELECT value FROM pem.config WHERE param = 'snmp_spool_retention_time')||'days')::interval;
$$ LANGUAGE sql SECURITY DEFINER;

CREATE OR REPLACE FUNCTION pem.generate_alert_mib()
RETURNS text AS $$
DECLARE
	mib_text text;
BEGIN

	mib_text = E'\n-- File Name : PEM-ALERTING-MIB\n
-- Date      : ' || now()::text || E'\n
-- Author    : EnterpriseDB \n

PEM-ALERTING-MIB	DEFINITIONS ::= BEGIN

	IMPORTS
		enterprises, MODULE-IDENTITY, OBJECT-TYPE, Integer32, NOTIFICATION-TYPE
			FROM SNMPv2-SMI
		DisplayString
			FROM SNMPv2-TC
		MODULE-COMPLIANCE, OBJECT-GROUP, NOTIFICATION-GROUP
			FROM SNMPv2-CONF;


	postgresql	MODULE-IDENTITY
		LAST-UPDATED	"201109271419Z"
		ORGANIZATION	"EnterpriseDB"
		CONTACT-INFO	"http://www.enterprisedb.com"
		DESCRIPTION	"This MIB file used for alerting notifications."
		REVISION	"201109271419Z"
		DESCRIPTION	"This MIB file used for alerting notifications."
		::=  {  enterprises  27645  }

	pem	OBJECT IDENTIFIER ::=  {  postgresql  5444  }

	agentAlerts	OBJECT IDENTIFIER ::=  {  pem  1  }

	serverAlerts	OBJECT IDENTIFIER ::=  {  pem  2  }

	databaseAlerts	OBJECT IDENTIFIER ::=  {  pem  3  }

	schemaAlerts	OBJECT IDENTIFIER ::=  {  pem  4  }

	objectAlerts	OBJECT IDENTIFIER ::=  {  pem  5  }

	globalAlerts	OBJECT IDENTIFIER ::=  {  pem  6  }

	bindingVariables	OBJECT IDENTIFIER ::=  {  pem  7  }

	pemObjectGroup  OBJECT-GROUP
		OBJECTS { agentID,
			agentName,
			databaseName,
			objectName,
			previousStatus,
			previousValue,
			schemaName,
			serverID,
			serverName,
			status,
			thresholdValue,
			value }
	STATUS 	current
	DESCRIPTION
		"This group contains the notification detail objects"
	::= { postgresql 5445 }

	agentID		OBJECT-TYPE
		SYNTAX			Integer32
		MAX-ACCESS		read-only
		STATUS			current
		DESCRIPTION		"This parameter gives the agent id for which this alert is raised"
		::=  {  bindingVariables  1  }

	serverID	OBJECT-TYPE
		SYNTAX			Integer32
		MAX-ACCESS		read-only
		STATUS			current
		DESCRIPTION		"This parameter gives the server id for which this alert is raised"
		::=  {  bindingVariables  2  }

	agentName	OBJECT-TYPE
		SYNTAX			DisplayString
		MAX-ACCESS		read-only
		STATUS			current
		DESCRIPTION		"This parameter gives the agent name for which this alert is raised"
		::=  {  bindingVariables  3  }

	serverName	OBJECT-TYPE
		SYNTAX			DisplayString
		MAX-ACCESS		read-only
		STATUS			current
		DESCRIPTION		"This parameter gives the server name for which this alert is raised"
		::=  {  bindingVariables  4  }

	databaseName	OBJECT-TYPE
		SYNTAX			DisplayString
		MAX-ACCESS		read-only
		STATUS			current
		DESCRIPTION		"This parameter gives the database name for which this alert is raised"
		::=  {  bindingVariables  5  }

	schemaName	OBJECT-TYPE
		SYNTAX			DisplayString
		MAX-ACCESS		read-only
		STATUS			current
		DESCRIPTION		"This parameter gives the schema name for which this alert is raised"
		::=  {  bindingVariables  6  }

	objectName	OBJECT-TYPE
		SYNTAX			DisplayString
		MAX-ACCESS		read-only
		STATUS			current
		DESCRIPTION		"This parameter gives the object name for which this alert is raised"
		::=  {  bindingVariables  7  }

	thresholdValue	OBJECT-TYPE
		SYNTAX			DisplayString
		MAX-ACCESS		read-only
		STATUS			current
		DESCRIPTION		"This parameter gives the threshold value of the alert"
		::=  {  bindingVariables  8  }

	previousValue	OBJECT-TYPE
		SYNTAX			DisplayString
		MAX-ACCESS		read-only
		STATUS			current
		DESCRIPTION		"This parameter gives the current value of the alert"
		::=  {  bindingVariables  9  }

	value	OBJECT-TYPE
		SYNTAX			DisplayString
		MAX-ACCESS		read-only
		STATUS			current
		DESCRIPTION		"This parameter gives the current value of the alert"
		::=  {  bindingVariables  10  }

	previousStatus	OBJECT-TYPE
		SYNTAX			INTEGER  { low ( 0 ) , medium ( 1 ), high ( 2 ) }
		MAX-ACCESS		read-only
		STATUS			current
		DESCRIPTION		"This parameter gives the current status of the alert"
		::=  {  bindingVariables  11  }

	status	OBJECT-TYPE
		SYNTAX			INTEGER  { low ( 0 ) , medium ( 1 ), high ( 2 ) }
		MAX-ACCESS		read-only
		STATUS			current
		DESCRIPTION		"This parameter gives the old status of the alert"
		::=  {  bindingVariables  12  }

	recordedTime	OBJECT-TYPE
		SYNTAX			DisplayString
		MAX-ACCESS		read-only
		STATUS			current
		DESCRIPTION		"This parameter gives the time when the event was recorded"
		::=  {  bindingVariables  13  }';

	/* Agent Alerts */
	mib_text = mib_text || pem.create_mib_notification_type(100, 5446);
	/* server Alerts */
	mib_text = mib_text || pem.create_mib_notification_type(200, 5447);
	/* database Alerts */
	mib_text = mib_text || pem.create_mib_notification_type(300, 5448);
	/* schema Alerts */
	mib_text = mib_text || pem.create_mib_notification_type(400, 5449);
	/* object Alerts */
	mib_text = mib_text || pem.create_mib_notification_type(500, 5450);
	mib_text = mib_text || pem.create_mib_notification_type(600, 5451);
	mib_text = mib_text || pem.create_mib_notification_type(700, 5452);
	mib_text = mib_text || pem.create_mib_notification_type(800, 5453);
	/* global Alerts */
	mib_text = mib_text || pem.create_mib_notification_type(50, 5454);

	mib_text = mib_text || E'\nEND';

	RETURN mib_text;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION pem.create_mib_notification_type(object_type integer, group_oid_type integer)
RETURNS text AS $$
DECLARE
	return_text text = '';
	tmp_rec	RECORD;
	parent_node text;
	where_clause text;
	object_prefix text;
	object_string text;
	group_text text = '';
	group_description text = '';
	is_alert_found boolean = false;
BEGIN
	CASE
	WHEN object_type = 50 THEN
		where_clause = 'WHERE object_type = 50 AND snmp_oid > 0';
		parent_node = 'globalAlerts';
		object_string = '{ previousValue, value , previousStatus, status, recordedTime }';
		object_prefix = 'gl';
		group_text = E'\n\n\tpemGlobalNotificationGroup  NOTIFICATION-GROUP
	\tNOTIFICATIONS {';
		group_description = 'This group contains the global notification types';
	WHEN object_type = 100 THEN
		where_clause = 'WHERE object_type = 100 AND snmp_oid > 0';
		parent_node = 'agentAlerts';
		object_string = '{ agentID , agentName, thresholdValue, previousValue, value , previousStatus, status, recordedTime }';
		object_prefix = 'ag';
		group_text = E'\n\n\tpemAgentNotificationGroup  NOTIFICATION-GROUP
	\tNOTIFICATIONS {';
		group_description = 'This group contains the agent level notification types';
	WHEN object_type = 200 THEN
		where_clause = 'WHERE object_type = 200 AND snmp_oid > 0';
		parent_node = 'serverAlerts';
		object_string = '{ serverID , serverName, thresholdValue, previousValue, value , previousStatus, status, recordedTime }';
		object_prefix = 'sr';
		group_text = E'\n\n\tpemServerNotificationGroup  NOTIFICATION-GROUP
	\tNOTIFICATIONS {';
		group_description = 'This group contains the server level notification types';
	WHEN object_type = 300 THEN
		where_clause = 'WHERE object_type = 300 AND snmp_oid > 0';
		parent_node = 'databaseAlerts';
		object_string = '{ serverID , serverName, databaseName, thresholdValue, previousValue, value , previousStatus, status, recordedTime }';
		object_prefix = 'db';
		group_text = E'\n\n\tpemDatabaseNotificationGroup  NOTIFICATION-GROUP
	\tNOTIFICATIONS {';
		group_description = 'This group contains the database level notification types';
	WHEN object_type = 400 THEN
		where_clause = 'WHERE object_type = 400 AND snmp_oid > 0';
		parent_node = 'schemaAlerts';
		object_string = '{ serverID , serverName, databaseName, schemaName, thresholdValue, previousValue, value , previousStatus, status, recordedTime }';
		object_prefix = 'sc';
		group_text = E'\n\n\tpemSchemaNotificationGroup  NOTIFICATION-GROUP
	\tNOTIFICATIONS {';
		group_description = 'This group contains the schema level notification types';
	WHEN object_type = 500 THEN
		where_clause = 'WHERE object_type = 500 AND snmp_oid > 0';
		parent_node = 'objectAlerts';
		object_string = '{ serverID , serverName, databaseName, schemaName, objectName, thresholdValue, previousValue, value , previousStatus, status, recordedTime }';
		object_prefix = 'tb';
		group_text = E'\n\n\tpemTableNotificationGroup  NOTIFICATION-GROUP
	\tNOTIFICATIONS {';
		group_description = 'This group contains the table level notification types';
	WHEN object_type = 600 THEN
		where_clause = 'WHERE object_type = 600 AND snmp_oid > 0';
		parent_node = 'objectAlerts';
		object_string = '{ serverID , serverName, databaseName, schemaName, objectName, thresholdValue, previousValue, value , previousStatus, status, recordedTime }';
		object_prefix = 'in';
		group_text = E'\n\n\tpemIndexNotificationGroup  NOTIFICATION-GROUP
	\tNOTIFICATIONS {';
		group_description = 'This group contains the index level notification types';
	WHEN object_type = 700 THEN
		where_clause = 'WHERE object_type = 700 AND snmp_oid > 0';
		parent_node = 'objectAlerts';
		object_string = '{ serverID , serverName, databaseName, schemaName, objectName, thresholdValue, previousValue, value , previousStatus, status, recordedTime }';
		object_prefix = 'se';
		group_text = E'\n\n\tpemSequenceNotificationGroup  NOTIFICATION-GROUP
	\tNOTIFICATIONS {';
		group_description = 'This group contains the sequence level notification types';
	WHEN object_type = 800 THEN
		where_clause = 'WHERE object_type = 800 AND snmp_oid > 0';
		parent_node = 'objectAlerts';
		object_string = '{ serverID , serverName, databaseName, schemaName, objectName, thresholdValue, previousValue, value , previousStatus, status, recordedTime }';
		object_prefix = 'fn';
		group_text = E'\n\n\tpemFunctionNotificationGroup  NOTIFICATION-GROUP
	\tNOTIFICATIONS {';
		group_description = 'This group contains the function level notification types';
	END CASE;

	FOR tmp_rec IN EXECUTE 'SELECT display_name, description , snmp_oid FROM pem.alert_template ' || where_clause || ' ORDER BY snmp_oid'
	LOOP
		is_alert_found = true;
		tmp_rec.display_name = lower(tmp_rec.display_name);
		tmp_rec.display_name = replace(tmp_rec.display_name, '(', '');
		tmp_rec.display_name = replace(tmp_rec.display_name, ')', '');
		tmp_rec.display_name = replace(tmp_rec.display_name, ',', '');
		tmp_rec.display_name = replace(tmp_rec.display_name, '-', '');
		tmp_rec.display_name = replace(tmp_rec.display_name, '_', '');
		tmp_rec.display_name = initcap(tmp_rec.display_name);
		tmp_rec.display_name = replace(tmp_rec.display_name, ' ', '');

		IF char_length(tmp_rec.display_name) > 62 THEN
			tmp_rec.display_name = substr(tmp_rec.display_name, 0, 62);
		END IF;

		return_text =  return_text || E'\n\n\t' || object_prefix || tmp_rec.display_name || E'   NOTIFICATION-TYPE
		OBJECTS			' || object_string || E'
		STATUS			current
		DESCRIPTION \t\t"'	||	tmp_rec.description || E'"
		::=  {  ' || parent_node || '  ' || tmp_rec.snmp_oid::text ||  '  }';

		group_text = group_text || E'\n\t\t\t' ||object_prefix || tmp_rec.display_name || E',';
	END LOOP;

	group_text = trim(trailing ',' from group_text);

	group_text = group_text || '}
	STATUS 	current
	DESCRIPTION
		"'|| group_description ||'"
	::= { postgresql ' || group_oid_type || '}';

	IF is_alert_found THEN
		RETURN group_text || return_text;
	ELSE
		RETURN return_text;
	END IF;
END;
$$ LANGUAGE plpgsql;

INSERT INTO pem.config (param, value) VALUES ('audit_log_retention_time', '30');

CREATE OR REPLACE FUNCTION pem.purge_data()
  RETURNS void AS
$BODY$
DECLARE
    curs_probe CURSOR FOR
	SELECT probe_internal_name, parameter_name_list,
	   parameter_value_list, lifetime
	FROM pem.probe_target_view;

    table_name varchar;
    parameter_name_list text[];
    parameter_value_list text[];
    lifetime integer;

    i integer; -- Counter
    where_clause varchar;
    subquery varchar;

BEGIN

    FOR probe IN curs_probe LOOP

	table_name := 'pemhistory.' || quote_ident(probe.probe_internal_name);
	parameter_name_list := probe.parameter_name_list;
	parameter_value_list := probe.parameter_value_list;
	lifetime := probe.lifetime;

	where_clause := 'WHERE ';

	FOR i IN array_lower(parameter_name_list, 1)..array_upper(parameter_name_list, 1)
	LOOP
	    where_clause := where_clause || parameter_name_list[i] || ' = ' || quote_literal(parameter_value_list[i]) || ' AND ';
	END LOOP;

	where_clause := where_clause || 'recorded_time < (now() - interval ''' || lifetime || ' days'' ) ';

	subquery := 'SELECT recorded_time FROM ' || table_name || ' ' || where_clause || 'ORDER BY recorded_time DESC LIMIT 1';

	where_clause := where_clause || ' AND recorded_time < (' || subquery || ')';

	EXECUTE 'DELETE FROM ' || table_name || ' ' || where_clause;

    END LOOP;

    -- Purge data from alert history table
	DELETE FROM pem.alert_history AS h
	USING pem.alert AS a
	WHERE a.id = h.alert_id
	AND (now() - h.generated) >= (a.history_retention||'days')::interval;

    -- Purge data from probe log table
	DELETE FROM pem.probe_log
	WHERE (now() - recorded_time) >= ((SELECT value FROM pem.config WHERE param = 'probe_log_retention_time')||'days')::interval;

    -- Purge data from audit log table
        DELETE FROM pemdata.audit_logs
	WHERE (now() - log_time) >= ((SELECT value FROM pem.config WHERE param = 'audit_log_retention_time')||'days')::interval;

    -- Purge old jobs, steps and schedules
	DELETE FROM pem.job
	WHERE jobnextrun IS NULL
	AND (now() - joblastrun) >= ((SELECT value FROM pem.config WHERE param = 'job_retention_time')||'days')::interval;

    -- Purge job log and job step log
	DELETE FROM pem.joblog AS jl
	WHERE (now() - jl.jlgstart) >= ((SELECT value FROM pem.config WHERE param = 'job_retention_time')||'days')::interval;

    -- Purge smtp spool table
	PERFORM pem.purge_smtp_spool();

    -- Purge snmp spool table
	PERFORM pem.purge_snmp_spool();

END;
$BODY$ LANGUAGE plpgsql;

-- Update all alert templates with SNMP OID's
UPDATE pem.alert_template SET snmp_oid = 1 WHERE display_name = 'Agents Down' AND object_type = 50;
UPDATE pem.alert_template SET snmp_oid = 2 WHERE display_name = 'Servers Down' AND object_type = 50;
-- agent level template updates
UPDATE pem.alert_template SET snmp_oid = 1 WHERE display_name = 'Load Average (1 minute)' AND object_type = 100;
UPDATE pem.alert_template SET snmp_oid = 2 WHERE display_name = 'Load Average (5 minutes)' AND object_type = 100;
UPDATE pem.alert_template SET snmp_oid = 3 WHERE display_name = 'Load Average (15 minutes)' AND object_type = 100;
UPDATE pem.alert_template SET snmp_oid = 4 WHERE display_name = 'Load Average per CPU Core (1 minutes)' AND object_type = 100;
UPDATE pem.alert_template SET snmp_oid = 5 WHERE display_name = 'Load Average per CPU Core (5 minutes)' AND object_type = 100;
UPDATE pem.alert_template SET snmp_oid = 6 WHERE display_name = 'Load Average per CPU Core (15 minutes)' AND object_type = 100;
UPDATE pem.alert_template SET snmp_oid = 7 WHERE display_name = 'CPU utilization' AND object_type = 100;
UPDATE pem.alert_template SET snmp_oid = 8 WHERE display_name = 'Number of CPUs running higher than a threshold' AND object_type = 100;
UPDATE pem.alert_template SET snmp_oid = 9 WHERE display_name = 'Free memory percentage' AND object_type = 100;
UPDATE pem.alert_template SET snmp_oid = 10 WHERE display_name = 'Memory used percentage' AND object_type = 100;
UPDATE pem.alert_template SET snmp_oid = 11 WHERE display_name = 'Swap consumption' AND object_type = 100;
UPDATE pem.alert_template SET snmp_oid = 12 WHERE display_name = 'Swap consumption percentage' AND object_type = 100;
UPDATE pem.alert_template SET snmp_oid = 13 WHERE display_name = 'Disk Consumption' AND object_type = 100;
UPDATE pem.alert_template SET snmp_oid = 14 WHERE display_name = 'Disk consumption percentage' AND object_type = 100;
UPDATE pem.alert_template SET snmp_oid = 15 WHERE display_name = 'Disk Available' AND object_type = 100;
UPDATE pem.alert_template SET snmp_oid = 16 WHERE display_name = 'Disk busy percentage' AND object_type = 100;
UPDATE pem.alert_template SET snmp_oid = 17 WHERE display_name = 'Most used disk percentage' AND object_type = 100;
UPDATE pem.alert_template SET snmp_oid = 18 WHERE display_name = 'Total table bloat on host' AND object_type = 100;
UPDATE pem.alert_template SET snmp_oid = 19 WHERE display_name = 'Highest table bloat on host' AND object_type = 100;
UPDATE pem.alert_template SET snmp_oid = 20 WHERE display_name = 'Average table bloat on host' AND object_type = 100;
UPDATE pem.alert_template SET snmp_oid = 21 WHERE display_name = 'Table size on host' AND object_type = 100;
UPDATE pem.alert_template SET snmp_oid = 22 WHERE display_name = 'Database size on host' AND object_type = 100;
-- server level template updates
UPDATE pem.alert_template SET snmp_oid = 1 WHERE display_name = 'Total table bloat in server' AND object_type = 200;
UPDATE pem.alert_template SET snmp_oid = 2 WHERE display_name = 'Largest table (by multiple of unbloated size)' AND object_type = 200;
UPDATE pem.alert_template SET snmp_oid = 3 WHERE display_name = 'Highest table bloat in server' AND object_type = 200;
UPDATE pem.alert_template SET snmp_oid = 4 WHERE display_name = 'Average table bloat in server' AND object_type = 200;
UPDATE pem.alert_template SET snmp_oid = 5 WHERE display_name = 'Table size in server' AND object_type = 200;
UPDATE pem.alert_template SET snmp_oid = 6 WHERE display_name = 'Database size in server' AND object_type = 200;
UPDATE pem.alert_template SET snmp_oid = 7 WHERE display_name = 'Number of WAL files' AND object_type = 200;
UPDATE pem.alert_template SET snmp_oid = 8 WHERE display_name = 'Number of prepared transactions' AND object_type = 200;
UPDATE pem.alert_template SET snmp_oid = 9 WHERE display_name = 'Total connections' AND object_type = 200;
UPDATE pem.alert_template SET snmp_oid = 10 WHERE display_name = 'Total connections as percentage of max_connections' AND object_type = 200;
UPDATE pem.alert_template SET snmp_oid = 11 WHERE display_name = 'Unused, non-superuser connections' AND object_type = 200;
UPDATE pem.alert_template SET snmp_oid = 12 WHERE display_name = 'Unused, non-superuser connections as percentage of max_connections' AND object_type = 200;
UPDATE pem.alert_template SET snmp_oid = 13 WHERE display_name = 'Ungranted locks' AND object_type = 200;
UPDATE pem.alert_template SET snmp_oid = 14 WHERE display_name = 'Percentage of buffers written by backends' AND object_type = 200;
UPDATE pem.alert_template SET snmp_oid = 15 WHERE display_name = 'Percentage of buffers written by checkpoint' AND object_type = 200;
UPDATE pem.alert_template SET snmp_oid = 16 WHERE display_name = 'Buffers written per second' AND object_type = 200;
UPDATE pem.alert_template SET snmp_oid = 17 WHERE display_name = 'Buffers allocated per second' AND object_type = 200;
UPDATE pem.alert_template SET snmp_oid = 18 WHERE display_name = 'Connections in idle state' AND object_type = 200;
UPDATE pem.alert_template SET snmp_oid = 19 WHERE display_name = 'Connections in idle-in-transaction state' AND object_type = 200;
UPDATE pem.alert_template SET snmp_oid = 20 WHERE display_name = 'Connections in idle-in-transaction state, as a percentage of max_connections' AND object_type = 200;
UPDATE pem.alert_template SET snmp_oid = 21 WHERE display_name = 'Long-running idle connections' AND object_type = 200;
UPDATE pem.alert_template SET snmp_oid = 22 WHERE display_name = 'Long-running idle connections and idle transactions' AND object_type = 200;
UPDATE pem.alert_template SET snmp_oid = 23 WHERE display_name = 'Long-running idle transactions' AND object_type = 200;
UPDATE pem.alert_template SET snmp_oid = 24 WHERE display_name = 'Long-running transactions' AND object_type = 200;
UPDATE pem.alert_template SET snmp_oid = 25 WHERE display_name = 'Long-running queries' AND object_type = 200;
UPDATE pem.alert_template SET snmp_oid = 26 WHERE display_name = 'Long-running vacuums' AND object_type = 200;
UPDATE pem.alert_template SET snmp_oid = 27 WHERE display_name = 'Long-running autovacuums' AND object_type = 200;
UPDATE pem.alert_template SET snmp_oid = 28 WHERE display_name = 'Committed transactions percentage' AND object_type = 200;
UPDATE pem.alert_template SET snmp_oid = 29 WHERE display_name = 'Shared buffers hit percentage' AND object_type = 200;
UPDATE pem.alert_template SET snmp_oid = 30 WHERE display_name = 'InfiniteCache buffers hit percentage' AND object_type = 200;
UPDATE pem.alert_template SET snmp_oid = 31 WHERE display_name = 'Tuples fetched' AND object_type = 200;
UPDATE pem.alert_template SET snmp_oid = 32 WHERE display_name = 'Tuples returned' AND object_type = 200;
UPDATE pem.alert_template SET snmp_oid = 33 WHERE display_name = 'Tuples inserted' AND object_type = 200;
UPDATE pem.alert_template SET snmp_oid = 34 WHERE display_name = 'Tuples updated' AND object_type = 200;
UPDATE pem.alert_template SET snmp_oid = 35 WHERE display_name = 'Tuples deleted' AND object_type = 200;
UPDATE pem.alert_template SET snmp_oid = 36 WHERE display_name = 'Tuples hot updated' AND object_type = 200;
UPDATE pem.alert_template SET snmp_oid = 37 WHERE display_name = 'Sequential Scans' AND object_type = 200;
UPDATE pem.alert_template SET snmp_oid = 38 WHERE display_name = 'Index Scans' AND object_type = 200;
UPDATE pem.alert_template SET snmp_oid = 39 WHERE display_name = 'Hot update percentage' AND object_type = 200;
UPDATE pem.alert_template SET snmp_oid = 40 WHERE display_name = 'Live Tuples' AND object_type = 200;
UPDATE pem.alert_template SET snmp_oid = 41 WHERE display_name = 'Dead Tuples' AND object_type = 200;
UPDATE pem.alert_template SET snmp_oid = 42 WHERE display_name = 'Dead tuples percentage' AND object_type = 200;
UPDATE pem.alert_template SET snmp_oid = 43 WHERE display_name = 'Last Vacuum' AND object_type = 200;
UPDATE pem.alert_template SET snmp_oid = 44 WHERE display_name = 'Last AutoVacuum' AND object_type = 200;
UPDATE pem.alert_template SET snmp_oid = 45 WHERE display_name = 'Last Analyze' AND object_type = 200;
UPDATE pem.alert_template SET snmp_oid = 46 WHERE display_name = 'Last AutoAnalyze' AND object_type = 200;
UPDATE pem.alert_template SET snmp_oid = 47 WHERE display_name = 'Percentage of buffers written by backends over last N minutes' AND object_type = 200;
UPDATE pem.alert_template SET snmp_oid = 48 WHERE display_name = 'Table Count' AND object_type = 200;
UPDATE pem.alert_template SET snmp_oid = 49 WHERE display_name = 'Function Count' AND object_type = 200;
UPDATE pem.alert_template SET snmp_oid = 50 WHERE display_name = 'Sequence Count' AND object_type = 200;
UPDATE pem.alert_template SET snmp_oid = 51 WHERE display_name = 'A user expires in N days' AND object_type = 200;
UPDATE pem.alert_template SET snmp_oid = 52 WHERE display_name = 'Index size as a percentage of table size' AND object_type = 200;
UPDATE pem.alert_template SET snmp_oid = 53 WHERE display_name = 'Largest index by table-size percentage' AND object_type = 200;
-- database level template updates
UPDATE pem.alert_template SET snmp_oid = 1 WHERE display_name = 'Total table bloat in database' AND object_type = 300;
UPDATE pem.alert_template SET snmp_oid = 2 WHERE display_name = 'Largest table (by multiple of unbloated size)' AND object_type = 300;
UPDATE pem.alert_template SET snmp_oid = 3 WHERE display_name = 'Highest table bloat in database' AND object_type = 300;
UPDATE pem.alert_template SET snmp_oid = 4 WHERE display_name = 'Average table bloat in database' AND object_type = 300;
UPDATE pem.alert_template SET snmp_oid = 5 WHERE display_name = 'Table size in database' AND object_type = 300;
UPDATE pem.alert_template SET snmp_oid = 6 WHERE display_name = 'Database size' AND object_type = 300;
UPDATE pem.alert_template SET snmp_oid = 7 WHERE display_name = 'Total connections' AND object_type = 300;
UPDATE pem.alert_template SET snmp_oid = 8 WHERE display_name = 'Total connections as percentage of max_connections' AND object_type = 300;
UPDATE pem.alert_template SET snmp_oid = 9 WHERE display_name = 'Ungranted locks' AND object_type = 300;
UPDATE pem.alert_template SET snmp_oid = 10 WHERE display_name = 'Connections in idle state' AND object_type = 300;
UPDATE pem.alert_template SET snmp_oid = 11 WHERE display_name = 'Connections in idle-in-transaction state' AND object_type = 300;
UPDATE pem.alert_template SET snmp_oid = 12 WHERE display_name = 'Connections in idle-in-transaction state, as a percentage of max_connections' AND object_type = 300;
UPDATE pem.alert_template SET snmp_oid = 13 WHERE display_name = 'Long-running idle connections' AND object_type = 300;
UPDATE pem.alert_template SET snmp_oid = 14 WHERE display_name = 'Long-running idle connections and idle transactions' AND object_type = 300;
UPDATE pem.alert_template SET snmp_oid = 15 WHERE display_name = 'Long-running idle transactions' AND object_type = 300;
UPDATE pem.alert_template SET snmp_oid = 16 WHERE display_name = 'Long-running transactions' AND object_type = 300;
UPDATE pem.alert_template SET snmp_oid = 17 WHERE display_name = 'Long-running queries' AND object_type = 300;
UPDATE pem.alert_template SET snmp_oid = 18 WHERE display_name = 'Long-running vacuums' AND object_type = 300;
UPDATE pem.alert_template SET snmp_oid = 19 WHERE display_name = 'Long-running autovacuums' AND object_type = 300;
UPDATE pem.alert_template SET snmp_oid = 20 WHERE display_name = 'Committed transactions percentage' AND object_type = 300;
UPDATE pem.alert_template SET snmp_oid = 21 WHERE display_name = 'Shared buffers hit percentage' AND object_type = 300;
UPDATE pem.alert_template SET snmp_oid = 22 WHERE display_name = 'InfiniteCache buffers hit percentage' AND object_type = 300;
UPDATE pem.alert_template SET snmp_oid = 23 WHERE display_name = 'Tuples fetched' AND object_type = 300;
UPDATE pem.alert_template SET snmp_oid = 24 WHERE display_name = 'Tuples returned' AND object_type = 300;
UPDATE pem.alert_template SET snmp_oid = 25 WHERE display_name = 'Tuples inserted' AND object_type = 300;
UPDATE pem.alert_template SET snmp_oid = 26 WHERE display_name = 'Tuples updated' AND object_type = 300;
UPDATE pem.alert_template SET snmp_oid = 27 WHERE display_name = 'Tuples deleted' AND object_type = 300;
UPDATE pem.alert_template SET snmp_oid = 28 WHERE display_name = 'Tuples hot updated' AND object_type = 300;
UPDATE pem.alert_template SET snmp_oid = 29 WHERE display_name = 'Sequential Scans' AND object_type = 300;
UPDATE pem.alert_template SET snmp_oid = 30 WHERE display_name = 'Index Scans' AND object_type = 300;
UPDATE pem.alert_template SET snmp_oid = 31 WHERE display_name = 'Hot update percentage' AND object_type = 300;
UPDATE pem.alert_template SET snmp_oid = 32 WHERE display_name = 'Live Tuples' AND object_type = 300;
UPDATE pem.alert_template SET snmp_oid = 33 WHERE display_name = 'Dead Tuples' AND object_type = 300;
UPDATE pem.alert_template SET snmp_oid = 34 WHERE display_name = 'Dead tuples percentage' AND object_type = 300;
UPDATE pem.alert_template SET snmp_oid = 35 WHERE display_name = 'Last Vacuum' AND object_type = 300;
UPDATE pem.alert_template SET snmp_oid = 36 WHERE display_name = 'Last AutoVacuum' AND object_type = 300;
UPDATE pem.alert_template SET snmp_oid = 37 WHERE display_name = 'Last Analyze' AND object_type = 300;
UPDATE pem.alert_template SET snmp_oid = 38 WHERE display_name = 'Last AutoAnalyze' AND object_type = 300;
UPDATE pem.alert_template SET snmp_oid = 39 WHERE display_name = 'Table Count' AND object_type = 300;
UPDATE pem.alert_template SET snmp_oid = 40 WHERE display_name = 'Function Count' AND object_type = 300;
UPDATE pem.alert_template SET snmp_oid = 41 WHERE display_name = 'Sequence Count' AND object_type = 300;
UPDATE pem.alert_template SET snmp_oid = 42 WHERE display_name = 'Index size as a percentage of table size' AND object_type = 300;
UPDATE pem.alert_template SET snmp_oid = 43 WHERE display_name = 'Largest index by table-size percentage' AND object_type = 300;
-- schema level template updates
UPDATE pem.alert_template SET snmp_oid = 1 WHERE display_name = 'Total table bloat in schema' AND object_type = 400;
UPDATE pem.alert_template SET snmp_oid = 2 WHERE display_name = 'Largest table (by multiple of unbloated size)' AND object_type = 400;
UPDATE pem.alert_template SET snmp_oid = 3 WHERE display_name = 'Highest table bloat in schema' AND object_type = 400;
UPDATE pem.alert_template SET snmp_oid = 4 WHERE display_name = 'Average table bloat in schema' AND object_type = 400;
UPDATE pem.alert_template SET snmp_oid = 5 WHERE display_name = 'Table size in schema' AND object_type = 400;
UPDATE pem.alert_template SET snmp_oid = 6 WHERE display_name = 'Tuples inserted' AND object_type = 400;
UPDATE pem.alert_template SET snmp_oid = 7 WHERE display_name = 'Tuples updated' AND object_type = 400;
UPDATE pem.alert_template SET snmp_oid = 8 WHERE display_name = 'Tuples deleted' AND object_type = 400;
UPDATE pem.alert_template SET snmp_oid = 9 WHERE display_name = 'Tuples hot updated' AND object_type = 400;
UPDATE pem.alert_template SET snmp_oid = 10 WHERE display_name = 'Sequential Scans' AND object_type = 400;
UPDATE pem.alert_template SET snmp_oid = 11 WHERE display_name = 'Index Scans' AND object_type = 400;
UPDATE pem.alert_template SET snmp_oid = 12 WHERE display_name = 'Hot update percentage' AND object_type = 400;
UPDATE pem.alert_template SET snmp_oid = 13 WHERE display_name = 'Live Tuples' AND object_type = 400;
UPDATE pem.alert_template SET snmp_oid = 14 WHERE display_name = 'Dead Tuples' AND object_type = 400;
UPDATE pem.alert_template SET snmp_oid = 15 WHERE display_name = 'Dead tuples percentage' AND object_type = 400;
UPDATE pem.alert_template SET snmp_oid = 16 WHERE display_name = 'Last Vacuum' AND object_type = 400;
UPDATE pem.alert_template SET snmp_oid = 17 WHERE display_name = 'Last AutoVacuum' AND object_type = 400;
UPDATE pem.alert_template SET snmp_oid = 18 WHERE display_name = 'Last Analyze' AND object_type = 400;
UPDATE pem.alert_template SET snmp_oid = 19 WHERE display_name = 'Last AutoAnalyze' AND object_type = 400;
UPDATE pem.alert_template SET snmp_oid = 20 WHERE display_name = 'Table Count' AND object_type = 400;
UPDATE pem.alert_template SET snmp_oid = 21 WHERE display_name = 'Function Count' AND object_type = 400;
UPDATE pem.alert_template SET snmp_oid = 22 WHERE display_name = 'Sequence Count' AND object_type = 400;
UPDATE pem.alert_template SET snmp_oid = 23 WHERE display_name = 'Index size as a percentage of table size' AND object_type = 400;
UPDATE pem.alert_template SET snmp_oid = 24 WHERE display_name = 'Largest index by table-size percentage' AND object_type = 400;
-- Object(table, index, function, sequence) level template updates
UPDATE pem.alert_template SET snmp_oid = 1 WHERE display_name = 'Table bloat' AND object_type = 500;
UPDATE pem.alert_template SET snmp_oid = 2 WHERE display_name = 'Table size as a multiple of ubloated size' AND object_type = 500;
UPDATE pem.alert_template SET snmp_oid = 3 WHERE display_name = 'Table size' AND object_type = 500;
UPDATE pem.alert_template SET snmp_oid = 4 WHERE display_name = 'Tuples inserted' AND object_type = 500;
UPDATE pem.alert_template SET snmp_oid = 5 WHERE display_name = 'Tuples updated' AND object_type = 500;
UPDATE pem.alert_template SET snmp_oid = 6 WHERE display_name = 'Tuples deleted' AND object_type = 500;
UPDATE pem.alert_template SET snmp_oid = 7 WHERE display_name = 'Tuples hot updated' AND object_type = 500;
UPDATE pem.alert_template SET snmp_oid = 8 WHERE display_name = 'Sequential Scans' AND object_type = 500;
UPDATE pem.alert_template SET snmp_oid = 9 WHERE display_name = 'Index Scans' AND object_type = 500;
UPDATE pem.alert_template SET snmp_oid = 10 WHERE display_name = 'Hot update percentage' AND object_type = 500;
UPDATE pem.alert_template SET snmp_oid = 11 WHERE display_name = 'Live Tuples' AND object_type = 500;
UPDATE pem.alert_template SET snmp_oid = 12 WHERE display_name = 'Dead Tuples' AND object_type = 500;
UPDATE pem.alert_template SET snmp_oid = 13 WHERE display_name = 'Dead tuples percentage' AND object_type = 500;
UPDATE pem.alert_template SET snmp_oid = 14 WHERE display_name = 'Last Vacuum' AND object_type = 500;
UPDATE pem.alert_template SET snmp_oid = 15 WHERE display_name = 'Last AutoVacuum' AND object_type = 500;
UPDATE pem.alert_template SET snmp_oid = 16 WHERE display_name = 'Last Analyze' AND object_type = 500;
UPDATE pem.alert_template SET snmp_oid = 17 WHERE display_name = 'Last AutoAnalyze' AND object_type = 500;
UPDATE pem.alert_template SET snmp_oid = 18 WHERE display_name = 'Row Count' AND object_type = 500;
UPDATE pem.alert_template SET snmp_oid = 19 WHERE display_name = 'Index size' AND object_type = 600;
UPDATE pem.alert_template SET snmp_oid = 20 WHERE display_name = 'Index size as a percentage of table size' AND object_type = 600;
UPDATE pem.alert_template SET snmp_oid = 21 WHERE display_name = 'Index size as a percentage of table size' AND object_type = 500;



REVOKE EXECUTE ON FUNCTION pem.send_snmptrap(trap_oid text, enterprise_oid text, trap_version integer, varbinding_oid text, varbinding_value text) FROM pem_user;
REVOKE EXECUTE ON FUNCTION pem.purge_snmp_spool() FROM pem_user;
REVOKE EXECUTE ON FUNCTION pem.send_snmptrap(trap_oid text, enterprise_oid text, trap_version integer, varbinding_oid text, varbinding_value text) FROM pem_admin;
REVOKE EXECUTE ON FUNCTION pem.purge_snmp_spool() FROM pem_admin;
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE pem.snmp_spool TO pem_agent;
GRANT EXECUTE ON FUNCTION pem.send_snmptrap(trap_oid text, enterprise_oid text, trap_version integer, varbinding_oid text, varbinding_value text) TO pem_agent;
GRANT EXECUTE ON FUNCTION pem.purge_snmp_spool() TO pem_agent;
REVOKE EXECUTE ON FUNCTION pem.send_snmptrap(trap_oid text, enterprise_oid text, trap_version integer, varbinding_oid text, varbinding_value text) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION pem.purge_snmp_spool() FROM PUBLIC;

-- Add a flag to the server table to specify if it will allow takeovers.
ALTER TABLE pem.agent_server_binding ADD COLUMN allow_takeover boolean NOT NULL DEFAULT false;
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE pem.agent_server_binding TO pem_agent;

-- a modified constraint alert_name_object_type_uniq is added to make sure that
-- NULL values in few columns are taken care of when inserting duplicate rows
-- in pem.alert table. Simple unique constraint does not honour NULL values.
ALTER TABLE pem.alert DROP CONSTRAINT alert_name_object_type_uniq;

CREATE UNIQUE INDEX alert_name_object_type_uniq ON pem.alert(coalesce(name,'dummy_name'), agent_id,
															coalesce(server_id, 0), coalesce(database_name,'dummy_database_name'),
															coalesce(schema_name,'dummy_schema_name'), coalesce(package_name,'dummy_package_name'),
															coalesce(object_name,'dummy_object_name'));
-- Fix Fogbugz 20330
UPDATE pem.alert SET agent_id = -1 WHERE name = 'Agents Down';
UPDATE pem.alert SET agent_id = -1 WHERE name = 'Servers Down';
UPDATE pem.alert SET agent_id = -1 WHERE name = 'Alert Errors';

-- Update the server_info probe to add server_start_time details
UPDATE pem.probe SET probe_code = 'SELECT pg_catalog.version() AS version_string, ((select setting from pg_settings where name = ''block_size'')::decimal * (select setting from pg_settings where name = ''shared_buffers'')::decimal / (1024 * 1024))::decimal(10,4) AS shared_buffers_mb, ((select setting from pg_settings where name = ''block_size'')::decimal * (select setting from pg_settings where name = ''temp_buffers'')::decimal / (1024 * 1024))::decimal(10,4) AS temp_buffers_mb, ((select setting from pg_settings where name = ''block_size'')::decimal * (select setting from pg_settings where name = ''effective_cache_size'')::decimal / (1024 * 1024))::decimal(10,4) AS effective_cache_size_mb, ((select setting from pg_settings where name = ''block_size'')::decimal * (select setting from pg_settings where name = ''segment_size'')::decimal / (1024 * 1024))::decimal(10,4) AS segment_size_mb, ((select setting from pg_settings where name = ''block_size'')::decimal * (select setting from pg_settings where name = ''wal_segment_size'')::decimal / (1024 * 1024))::decimal(10,4) AS wal_segment_size_mb, ((select setting from pg_settings where name = ''block_size'')::decimal * (select setting from pg_settings where name = ''wal_buffers'')::decimal / (1024 * 1024))::decimal(10,4) AS wal_buffers_mb, (SELECT pg_postmaster_start_time())::timestamptz AS server_start_time' WHERE internal_name = 'server_info';

-- Insert server_start_time column in pemdata.server_info
ALTER TABLE pemdata.server_info ADD COLUMN server_start_time timestamptz;
ALTER TABLE pemhistory.server_info ADD COLUMN server_start_time timestamptz;
INSERT INTO pem.probe_column(probe_id, internal_name, display_name, display_position, classification, sql_data_type, unit_of_value, calculate_pit, discard_history, pit_by_default, is_graphable) SELECT id, 'server_start_time', 'Server Start Time', 8, 'm', 'timestamp with time zone', '', false, false, false, false FROM pem.probe WHERE internal_name='server_info';

-- Update the trigger functions related to pemdata.server_info probe
CREATE OR REPLACE FUNCTION pemdata.copy_server_info_to_history() RETURNS TRIGGER AS $$
BEGIN
	IF (TG_OP = 'INSERT' OR TG_OP = 'UPDATE') THEN
		INSERT INTO pemhistory.server_info (recorded_time, server_id, version_string, shared_buffers_mb, temp_buffers_mb, effective_cache_size_mb, segment_size_mb, wal_segment_size_mb, wal_buffers_mb, server_start_time) VALUES (NEW.recorded_time, NEW.server_id, NEW.version_string, NEW.shared_buffers_mb, NEW.temp_buffers_mb, NEW.effective_cache_size_mb, NEW.segment_size_mb, NEW.wal_segment_size_mb, NEW.wal_buffers_mb, NEW.server_start_time);
	ELSIF EXISTS(SELECT 1 FROM pem.server WHERE id = OLD.server_id) THEN
		INSERT INTO pemhistory.server_info (server_id) VALUES (OLD.server_id);
	END IF;
	RETURN NEW;
END;
$$ LANGUAGE plpgsql;

--
-- Probe: os_info
--
INSERT INTO pem.probe
	(display_name, internal_name, collection_method, target_type_id,
	 agent_capability, enabled_by_default, force_enabled,
     default_execution_frequency, default_lifetime, any_server_version, probe_code)
VALUES
	('OS Information', 'os_info', 'i', 100, 'os_info', true, false, 1800,
	  180, true, 'os_info');

INSERT INTO pem.probe_column
	(probe_id, internal_name, display_name, display_position, classification,
	sql_data_type, unit_of_value, calculate_pit, discard_history, pit_by_default, is_graphable)
SELECT
	(SELECT max(id) FROM pem.probe),
	v.internal_name, v.display_name, v.display_position, v.classification,
	v.sql_data_type, v.unit_of_value, v.calculate_pit, v.discard_history, v.pit_by_default, v.is_graphable
FROM
	(VALUES
		('os_details',     'OS Details',     1, 'm', 'text'                    , '', false,  false, false, false),
		('os_start_time',  'OS Start Time',  2, 'm', 'timestamp with time zone', '', false,  false, false, false)
	) v(internal_name, display_name, display_position, classification,
		sql_data_type, unit_of_value, calculate_pit, discard_history, pit_by_default, is_graphable);

--
-- Probe: database_frozenxid
--
INSERT INTO pem.probe
	(display_name, internal_name, collection_method, target_type_id,
	 agent_capability, enabled_by_default, force_enabled,
     default_execution_frequency, default_lifetime, any_server_version, probe_code)
VALUES
	('Database Frozen XID', 'database_frozenxid', 's',
     200, NULL, true, false, 43200, 180, true,
	'SELECT datname AS database_name, age(datfrozenxid) AS frozenxid FROM pg_database');

INSERT INTO pem.probe_column
	(probe_id, internal_name, display_name, display_position, classification,
	sql_data_type, unit_of_value, calculate_pit, discard_history, pit_by_default, is_graphable)
SELECT
	(SELECT max(id) FROM pem.probe),
	v.internal_name, v.display_name, v.display_position, v.classification,
	v.sql_data_type, v.unit_of_value, v.calculate_pit, v.discard_history, v.pit_by_default, v.is_graphable
FROM
	(VALUES
		('database_name', 'Database Name', 1, 'k', 'text', '', false, false, false, false),
		('frozenxid', 'Database Frozen XID', 2, 'm', 'bigint', 'MB', false, false, true, true)
	) v(internal_name, display_name, display_position, classification,
		sql_data_type, unit_of_value, calculate_pit, discard_history, pit_by_default, is_graphable);

--
-- Probe: table_frozenxid
--
INSERT INTO pem.probe
	(display_name, internal_name, collection_method, target_type_id,
	 agent_capability, enabled_by_default, force_enabled,
     default_execution_frequency, default_lifetime, any_server_version, probe_code)
VALUES
	('Table Frozen XID', 'table_frozenxid', 's',
     300, NULL, true, false, 43200, 180, true,
	'SELECT n.nspname AS schema_name, c.relname AS table_name, age(c.relfrozenxid) AS frozenxid FROM pg_class c, pg_namespace n WHERE c.relnamespace = n.oid AND c.relkind = ''r''');

INSERT INTO pem.probe_column
	(probe_id, internal_name, display_name, display_position, classification,
	sql_data_type, unit_of_value, calculate_pit, discard_history, pit_by_default, is_graphable)
SELECT
	(SELECT max(id) FROM pem.probe),
	v.internal_name, v.display_name, v.display_position, v.classification,
	v.sql_data_type, v.unit_of_value, v.calculate_pit, v.discard_history, v.pit_by_default, v.is_graphable
FROM
	(VALUES
		('schema_name', 'Schema Name', 1, 'k', 'text', '', false, false, false, false),
		('table_name', 'Table Name', 2, 'k', 'text', '', false, false, false, false),
		('frozenxid', 'Table Frozen XID', 3, 'm', 'bigint', 'MB', false, false, true, true)
	) v(internal_name, display_name, display_position, classification,
		sql_data_type, unit_of_value, calculate_pit, discard_history, pit_by_default, is_graphable);

SELECT pem.create_data_and_history_tables();

SELECT pem.create_alert_template(
	'Table Frozen XID',
	'The age (in transactions before the current transaction) of the table''s frozen transaction ID',
	$sql$
SELECT frozenxid
FROM pemdata.table_frozenxid
WHERE	server_id = ${server_id}
AND		database_name = '${database_name}'
AND		schema_name = '${schema_name}'
AND		table_name = '${object_name}'$sql$,
	500, NULL, NULL, NULL, NULL,'{table_frozenxid}', 22);

SELECT pem.create_alert_template(
	'Database Frozen XID',
	'The age (in transactions before the current transaction) of the database''s frozen transaction ID',
	$sql$
SELECT frozenxid
FROM pemdata.database_frozenxid
WHERE	server_id = ${server_id}
AND		database_name = '${database_name}'$sql$,
	300, NULL, NULL, NULL, NULL,'{database_frozenxid}', 44);

-- Audit Manager Related Updates.
SELECT pem.create_alert_template(
       'Audit config mismatch',
       'Check for audit config parameter mismatch',
       $sql$
SELECT CASE WHEN(p.edb_audit = pd.edb_audit
AND p.edb_audit_directory = pd.edb_audit_directory
AND p.edb_audit_filename = pd.edb_audit_filename
AND p.edb_audit_rotation_day = pd.edb_audit_rotation_day
AND p.edb_audit_rotation_sec = pd.edb_audit_rotation_sec
AND p.edb_audit_rotation_size = pd.edb_audit_rotation_size
AND p.edb_audit_connect = pd.edb_audit_connect
AND p.edb_audit_disconnect = pd.edb_audit_disconnect
AND p.edb_audit_statements = pd.edb_audit_statements) OR (p.server_id IS NULL)
THEN -1
ELSE 1
END
FROM
pem.audit_configuration p RIGHT JOIN
pemdata.audit_configuration pd ON (p.server_id = pd.server_id)
WHERE p.server_id = ${server_id}$sql$,
       200, NULL, NULL, NULL, NULL,'{audit_configuration}', 54, 'ADVANCED_SERVER');

CREATE TABLE pem.audit_configuration (
       server_id                       integer NOT NULL, -- Server ID
       edb_audit                       text NOT NULL DEFAULT 'none'::text, -- Auditing State
       edb_audit_directory             text NOT NULL DEFAULT 'edb_audit'::text, -- Audit Log Directory
        edb_audit_filename             text NOT NULL DEFAULT 'audit-%Y-%m-%d_%H%M%S'::text, -- Audit Log Filename
       edb_audit_rotation_day          text NOT NULL DEFAULT 'every'::text, -- Audit Rotation (On day basis)
       edb_audit_rotation_size         integer NOT NULL DEFAULT 0, -- Audit Rotation (On size basis)
       edb_audit_rotation_sec          integer NOT NULL DEFAULT 0, -- Audit Rotation (On time basis)
       edb_audit_connect               text NOT NULL DEFAULT 'failed'::text, -- Audit Connection attempts
       edb_audit_disconnect            text NOT NULL DEFAULT 'none'::text, -- Audit Disconnection attempts
       edb_audit_statements            text NOT NULL DEFAULT 'ddl, error'::text, -- Audit Statements
       last_read_filename              text, -- Last Read Audit Log
       file_offset                     bigint, -- Last File Offset read
       log_collection                  boolean NOT NULL DEFAULT false,
       log_collection_frequency        text NOT NULL DEFAULT '1 Hour'::text,
        CONSTRAINT audit_configuration_pkey PRIMARY KEY (server_id),
       CONSTRAINT audit_configuration_server_id_fkey FOREIGN KEY (server_id)
                REFERENCES pem.server (id) MATCH SIMPLE
                ON UPDATE CASCADE ON DELETE CASCADE INITIALLY DEFERRED,
       CHECK (edb_audit IN ('none', 'xml', 'csv')),
       CHECK (edb_audit_rotation_day IN ('none', 'every', 'mon', 'tue', 'wed', 'thu', 'fri', 'sat', 'sun')),
       CHECK (edb_audit_connect IN ('none', 'failed', 'all')),
       CHECK (edb_audit_disconnect IN ('none', 'all'))
);

COMMENT ON TABLE pem.audit_configuration IS 'Global audit configuration data';
COMMENT ON COLUMN pem.audit_configuration.server_id IS 'Server id for which audit configuration is stored';
COMMENT ON COLUMN pem.audit_configuration.edb_audit IS 'Audit log state and file format';
COMMENT ON COLUMN pem.audit_configuration.edb_audit_directory IS 'Audit log directory';
COMMENT ON COLUMN pem.audit_configuration.edb_audit_filename IS 'Audit log filename';
COMMENT ON COLUMN pem.audit_configuration.edb_audit_rotation_day IS 'Audit log rotation based on days';
COMMENT ON COLUMN pem.audit_configuration.edb_audit_rotation_size IS 'Audit log rotation based on size';
COMMENT ON COLUMN pem.audit_configuration.edb_audit_rotation_sec IS 'Audit log rotation based on time';
COMMENT ON COLUMN pem.audit_configuration.edb_audit_connect IS 'Log connection attempts';
COMMENT ON COLUMN pem.audit_configuration.edb_audit_disconnect IS 'Log disconnection attempts';
COMMENT ON COLUMN pem.audit_configuration.edb_audit_statements IS 'Log DML, DDL, error statements';
COMMENT ON COLUMN pem.audit_configuration.last_read_filename IS 'Last read audit log';
COMMENT ON COLUMN pem.audit_configuration.file_offset IS 'File offset for the last read filename';
COMMENT ON COLUMN pem.audit_configuration.log_collection IS 'Enable/Disable audit log data collection';
COMMENT ON COLUMN pem.audit_configuration.log_collection_frequency IS 'Audit log data collection frequency';

CREATE TABLE pemdata.audit_logs (
        id                              bigserial NOT NULL,
        server_id                       integer NOT NULL,
        log_time timestamp              with time zone,
        user_name                       text,
        database_name                   text,
        process_id                      integer,
        connection_from                 text,
        session_id                      text,
        session_line_num                bigint,
        command_tag                     text,
        session_start_time              timestamp with time zone,
        virtual_transaction_id          text,
        transaction_id                  bigint,
        error_severity                  text,
        sql_state_code                  text,
        message                         text,
        detail                          text,
        hint                            text,
        internal_query                  text,
        internal_query_pos              integer,
        context                         text,
        query                           text,
        query_pos                       integer,
        location                        text,
        application_name                text,
        CONSTRAINT audit_logs_pkey PRIMARY KEY (id)
);

COMMENT ON TABLE pemdata.audit_logs IS 'Global audit log data';
COMMENT ON COLUMN pemdata.audit_logs.id IS 'Id for each record';
COMMENT ON COLUMN pemdata.audit_logs.server_id IS 'Server id for which audit log data is collected';
COMMENT ON COLUMN pemdata.audit_logs.log_time IS 'Time at which the statement got logged';
COMMENT ON COLUMN pemdata.audit_logs.user_name IS 'User name which issued the statement';
COMMENT ON COLUMN pemdata.audit_logs.database_name IS 'Database name on which the statement is executed';
COMMENT ON COLUMN pemdata.audit_logs.process_id IS 'Process ID of the client';
COMMENT ON COLUMN pemdata.audit_logs.connection_from IS 'Clients address and port';
COMMENT ON COLUMN pemdata.audit_logs.session_id IS 'Session ID which contains the statement';
COMMENT ON COLUMN pemdata.audit_logs.session_line_num IS '';
COMMENT ON COLUMN pemdata.audit_logs.command_tag IS 'Type of statement';
COMMENT ON COLUMN pemdata.audit_logs.session_start_time IS 'Time at which the session containing the statment started';
COMMENT ON COLUMN pemdata.audit_logs.virtual_transaction_id IS 'Virtual transaction ID of the statement';
COMMENT ON COLUMN pemdata.audit_logs.transaction_id IS 'Transaction ID of the statement';
COMMENT ON COLUMN pemdata.audit_logs.error_severity IS 'Severity of the error (if any)';
COMMENT ON COLUMN pemdata.audit_logs.sql_state_code IS 'SQL state code returned by the server';
COMMENT ON COLUMN pemdata.audit_logs.message IS 'Message returned by the server for the statement';
COMMENT ON COLUMN pemdata.audit_logs.detail IS '';
COMMENT ON COLUMN pemdata.audit_logs.hint IS 'Any hint associated with the statement';
COMMENT ON COLUMN pemdata.audit_logs.internal_query IS '';
COMMENT ON COLUMN pemdata.audit_logs.internal_query_pos IS '';
COMMENT ON COLUMN pemdata.audit_logs.context IS '';
COMMENT ON COLUMN pemdata.audit_logs.query IS 'The query in the statement';
COMMENT ON COLUMN pemdata.audit_logs.query_pos IS '';
COMMENT ON COLUMN pemdata.audit_logs.location IS '';
COMMENT ON COLUMN pemdata.audit_logs.application_name IS 'Application name which fires the statement';

--
-- Probe: audit_configuration
--
INSERT INTO pem.probe
        (display_name, internal_name, collection_method, target_type_id,
         agent_capability, enabled_by_default, force_enabled,
     default_execution_frequency, default_lifetime, any_server_version, probe_code)
VALUES
        ('EDB Audit Configuration', 'audit_configuration', 'i', 200, NULL, true, false, 1800,
          180, false, 'audit_configuration');

INSERT INTO pem.probe_server_version
    (probe_id, server_version_id, probe_code)
SELECT
       (SELECT max(id) FROM pem.probe), v.version, NULL
FROM
       (VALUES (20803), (20804), (20900))
               v(version);

INSERT INTO pem.probe_column
        (probe_id, internal_name, display_name, display_position, classification,
        sql_data_type, unit_of_value, calculate_pit, discard_history, pit_by_default, is_graphable)
SELECT
        (SELECT max(id) FROM pem.probe),
        v.internal_name, v.display_name, v.display_position, v.classification,
        v.sql_data_type, v.unit_of_value, v.calculate_pit, v.discard_history, v.pit_by_default, v.is_graphable
FROM
        (VALUES
                ('edb_audit',  'Audit State',  1, 'm', 'text', '', false, false, false, false),
                ('edb_audit_directory', 'Audit Directory', 2, 'm', 'text', '', false, false, false, false),
                ('edb_audit_filename', 'Audit Filename', 3, 'm', 'text', '', false, false, false, false),
                ('edb_audit_rotation_day', 'Audit Rotation Days', 4, 'm', 'text', '', false, false, false, false),
                ('edb_audit_rotation_size', 'Audit Rotation Size', 5, 'm', 'integer', '', false, false, false, false),
                ('edb_audit_rotation_sec', 'Audit Rotation Seconds', 6, 'm', 'integer', '', false, false, false, false),
                ('edb_audit_connect', 'Audit Connect', 7, 'm', 'text', '', false, false, false, false),
                ('edb_audit_disconnect', 'Audit Disconnect', 8, 'm', 'text', '', false, false, false, false),
                ('edb_audit_statements', 'Audit Statement', 9, 'm', 'text', '', false, false, false, false)
        ) v(internal_name, display_name, display_position, classification,
                sql_data_type, unit_of_value, calculate_pit, discard_history, pit_by_default, is_graphable);

GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE pem.audit_configuration TO pem_agent;
GRANT ALL ON ALL SEQUENCES IN SCHEMA pemdata TO pem_agent;

SELECT pem.create_data_and_history_tables();

-- Need to drop previous data_reconstruction and data_roll up function
-- otherwise create or replace with additional parameter creates a new function
-- instead of replacing the previous one.
DROP FUNCTION pem.data_reconstruction(probe_table text,
		    probe_data_column text, start_time timestamp with time zone,
		    end_time timestamp with time zone, time_interval interval,
		    probe_target_key_list varchar[], probe_target_value_list varchar[],
		    agentid integer, is_capacity_manager boolean);

CREATE OR REPLACE FUNCTION pem.data_reconstruction(probe_table text,
	probe_data_column text, start_time timestamp with time zone,
	end_time timestamp with time zone, time_interval interval,
	probe_target_key_list varchar[], probe_target_value_list varchar[],
	agentid integer, is_capacity_manager boolean, restricted_dbs varchar[] DEFAULT NULL)
RETURNS TABLE (metric_time timestamp with time zone, recorded_value numeric)
AS $$
DECLARE
    yardstick timestamp with time zone;
	probe_interval interval;
	min_multiple integer := 0;
	max_multiple integer := 1;
	new_multiple integer;
	adjustment interval := 0;
    conditional_clause text;
    tmp_end_time timestamp with time zone := NULL;
    heartbeat_freq interval := 0;
    last_heartbeat timestamp with time zone := NULL;
    probe_start_time timestamp with time zone := NULL;
BEGIN
	-- Sanity checks.
    IF (time_interval <= '0'::interval) THEN
        RAISE EXCEPTION 'time_interval must be greater than zero';
    END IF;
    IF (start_time >= end_time) THEN
        RAISE EXCEPTION 'start_time must be greater than end_time';
    END IF;

	EXECUTE 'SELECT (SELECT heartbeat_interval FROM pem.agent where id = ' || quote_literal(agentid)
	|| ') * ''1 second''::interval' INTO heartbeat_freq;

	EXECUTE 'SELECT last_heartbeat FROM pem.agent_heartbeat WHERE agent_id = ' || quote_literal(agentid) INTO last_heartbeat;
	IF last_heartbeat IS NULL THEN
		tmp_end_time = end_time;
	ELSE
		EXECUTE 'SELECT (CASE WHEN last_heartbeat + ' || quote_literal(heartbeat_freq) || ' < ' || quote_literal(end_time)
		|| 'THEN last_heartbeat ELSE  ' || quote_literal(end_time) || 'END) FROM pem.agent_heartbeat WHERE agent_id = '
		|| quote_literal(agentid) INTO tmp_end_time;
	END IF;

	-- Get probe_interval for this probe
	SELECT default_execution_frequency/60 FROM pem.probe WHERE internal_name = probe_table INTO probe_interval;

	-- Work out conditional_clause based on probe target.
	SELECT string_agg(quote_ident(probe_target_key_list[i]) || ' = ' ||
		quote_literal(probe_target_value_list[i]), ' AND ')
		FROM generate_series(array_lower(probe_target_key_list,1),
		array_upper(probe_target_key_list,1)) i INTO conditional_clause;

	-- Add restricted database clause
	IF count(restricted_dbs) > 0 THEN
		conditional_clause = conditional_clause || ' AND ' || probe_table || '.database_name = ANY( ''' || restricted_dbs::text || ''')';
	END IF;

	-- Get the time when probe started collecting the data
	EXECUTE 'SELECT COALESCE(recorded_time, now()) FROM pemhistory.'
		|| quote_ident(probe_table)
		|| ' WHERE '
		|| COALESCE(conditional_clause)
		|| ' ORDER BY recorded_time ASC LIMIT 1'
	INTO probe_start_time;

    -- We don't know exactly when during the interval the data was gathered,
	-- and it might bounce around a little bit, but it should be *roughly*
	-- the same time during each interval.  Try to align the times we look
	-- for the data with the times it was actually gathered, with a little
	-- slop.
    EXECUTE 'SELECT recorded_time FROM pemhistory.'
		|| quote_ident(probe_table)
		|| ' WHERE recorded_time < ' || quote_literal(start_time)
		|| COALESCE(' AND ' || conditional_clause, '')
		|| ' ORDER BY recorded_time DESC LIMIT 1'
    INTO yardstick;
	IF yardstick IS NOT NULL THEN
		WHILE yardstick + (max_multiple * time_interval) < start_time LOOP
			min_multiple := max_multiple;
			max_multiple := max_multiple * 2;
		END LOOP;
		WHILE min_multiple < max_multiple LOOP
			new_multiple := (min_multiple + max_multiple) / 2;
			IF yardstick + (new_multiple * time_interval) < start_time THEN
				min_multiple := new_multiple + 1;
			ELSE
				max_multiple := new_multiple;
			END IF;
		END LOOP;
		adjustment := yardstick + (min_multiple * time_interval) - start_time
			+ (probe_interval / 10);
		IF adjustment > probe_interval THEN
			adjustment := adjustment - probe_interval;
		END IF;
	END IF;

	-- Fetch the data.
	IF is_capacity_manager OR tmp_end_time >= end_time THEN
		RETURN QUERY EXECUTE 'SELECT ts, COALESCE((SELECT '
			|| quote_ident(probe_data_column) || ' FROM pemhistory.'
			|| quote_ident(probe_table)
			|| ' WHERE recorded_time <= ts + '
			|| quote_literal(adjustment) || '::interval'
			|| COALESCE(' AND ' || conditional_clause, '')
			|| ' ORDER BY recorded_time DESC LIMIT 1)::numeric, CASE WHEN ts>' || quote_literal(COALESCE(probe_start_time,now())) || 'THEN 0 END) probe_data_value'
			|| ' FROM generate_series('
			|| quote_literal(start_time) || '::timestamptz, '
			|| quote_literal(tmp_end_time) || '::timestamptz, '
			|| quote_literal(time_interval) || '::interval) ts';
	ELSE
		RETURN QUERY EXECUTE  'SELECT ts, COALESCE((SELECT '
			|| quote_ident(probe_data_column) || ' FROM pemhistory.'
			|| quote_ident(probe_table)
			|| ' WHERE recorded_time <= ts + '
			|| quote_literal(adjustment) || '::interval'
			|| COALESCE(' AND ' || conditional_clause, '')
			|| ' ORDER BY recorded_time DESC LIMIT 1)::numeric, CASE WHEN ts>' || quote_literal(COALESCE(probe_start_time,now())) || 'THEN 0 END)  probe_data_value'
			|| ' FROM generate_series('
			|| quote_literal(start_time) || '::timestamptz, '
			|| quote_literal(tmp_end_time) || '::timestamptz, '
			|| quote_literal(time_interval) || '::interval) ts UNION ALL SELECT ts, 0::numeric FROM generate_series('
			|| quote_literal(tmp_end_time) || '::timestamptz, '
			|| quote_literal(end_time) || '::timestamptz, '
			|| quote_literal(time_interval) || '::interval) ts';
	END IF;
END;
$$ LANGUAGE plpgsql;

DROP FUNCTION pem.data_rollup(probe_table text,
                                       aggregate_function text,
                                       probe_data_column text,
                                       start_time timestamp with time zone,
                                       end_time timestamp with time zone,
                                       time_interval interval,
				       				   required_points int,
				       				   probe_target_key_list varchar[],
				       				   probe_target_value_list varchar[],
				       				   agentid integer,
				       				   is_capacity_manager boolean);

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
				       				   is_capacity_manager boolean,
									   restricted_dbs varchar[] DEFAULT NULL)
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
	IF count(restricted_dbs) > 0 THEN
		OPEN curs FOR EXECUTE  'SELECT metric_time, recorded_value::numeric
								FROM pem.data_reconstruction(' || quote_literal(probe_table) || ','
   											|| quote_literal(probe_data_column) || ','
											|| quote_literal(start_time) || ','
											|| quote_literal(end_time) || ','
											|| quote_literal(time_interval) || ','
											|| quote_literal(probe_target_key_list) || ','
											|| quote_literal(probe_target_value_list)  || ','
                                	      	|| quote_literal(agentid)  || ','
                                    	   	|| quote_literal(is_capacity_manager)  || ','
                                       		|| quote_literal(restricted_dbs)
											|| ')';
	ELSE
		OPEN curs FOR EXECUTE  'SELECT metric_time, recorded_value::numeric
								FROM pem.data_reconstruction(' || quote_literal(probe_table) || ','
   											|| quote_literal(probe_data_column) || ','
											|| quote_literal(start_time) || ','
											|| quote_literal(end_time) || ','
											|| quote_literal(time_interval) || ','
											|| quote_literal(probe_target_key_list) || ','
											|| quote_literal(probe_target_value_list)  || ','
                                	      	|| quote_literal(agentid)  || ','
                                    	   	|| quote_literal(is_capacity_manager)
											|| ')';
	END IF;
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

COMMIT TRANSACTION;
