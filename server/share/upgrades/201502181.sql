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
'SELECT 201502181::integer;'
  LANGUAGE 'sql' IMMUTABLE;

ALTER TABLE pem.alert
	ADD COLUMN submit_to_nagios boolean NOT NULL DEFAULT false;

CREATE OR REPLACE FUNCTION pem.create_nagios_host_config(
	template_name	text,
	icon_image	text DEFAULT NULL::text,
	icon_image_alt	text DEFAULT NULL::text,
	statusmap_image text DEFAULT NULL::text)
RETURNS text AS $$
DECLARE
	host_config_text	text := '';
	row 			RECORD;
BEGIN
	FOR row IN SELECT description, server FROM pem.server WHERE active = true
	LOOP
		host_config_text = host_config_text || E'\ndefine host {\n
		host_name		' || row.description || E'\n
		address			' || row.server || E'\n
		use			' || template_name || E'\n
		active_checks_enabled	0\n
		passive_checks_enabled	1\n
		flap_detection_enabled	0\n
		max_check_attempts	10\n';

		IF icon_image IS NOT NULL THEN
			host_config_text = host_config_text || E'\n		icon_image		' || icon_image || E'\n';
		END IF;

		IF icon_image_alt IS NOT NULL THEN
			host_config_text = host_config_text || E'\n		icon_image_alt		' || icon_image_alt || E'\n';
		END IF;

		IF statusmap_image IS NOT NULL THEN
			host_config_text = host_config_text || E'\n		statusmap_image		' || statusmap_image || E'\n';
		END IF;

		host_config_text = host_config_text ||	E'}\n';
	END LOOP;

	For row IN SELECT DISTINCT ON (pa.description) pa.description, ps.server FROM pem.agent pa LEFT JOIN pem.agent_server_binding pasb ON (pa.id = pasb.agent_id) LEFT JOIN pem.server ps ON (ps.id = pasb.server_id)  WHERE pa.active = true AND ps.active = true AND NOT ps.is_remote_monitoring
	LOOP
		host_config_text = host_config_text || E'\ndefine host {\n
		host_name		' || row.description || E'\n
		address			' || row.server || E'\n
		use			' || template_name || E'\n
		active_checks_enabled	0\n
		passive_checks_enabled	1\n
		flap_detection_enabled	0\n';

		IF icon_image IS NOT NULL THEN
			host_config_text = host_config_text || E'\n		icon_image		' || icon_image || E'\n';
		END IF;

		IF icon_image_alt IS NOT NULL THEN
			host_config_text = host_config_text || E'\n		icon_image_alt		' || icon_image_alt || E'\n';
		END IF;

		IF statusmap_image IS NOT NULL THEN
			host_config_text = host_config_text || E'\n		statusmap_image		' || statusmap_image || E'\n';
		END IF;

		host_config_text = host_config_text ||	E'}\n';
	END LOOP;

RETURN host_config_text;

END $$  LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION pem.create_nagios_service_config(template_name text)
  RETURNS text AS $$
DECLARE
	service_config_text	text := '';
	row 				RECORD;
	service_desc		text;
	host_agent_name		text;
BEGIN

	FOR row IN select s.description, s.server, a.name from pem.server s, pem.alert a where a.server_id = s.id AND s.active = true
	LOOP
		service_desc = regexp_replace(regexp_replace(row.name, E'[`~$%^&*|''"<>?,(=]','-'), E'[)]', '-');

		service_config_text = service_config_text || E'\ndefine service {\n
		host_name		' || row.description || E'\n
		service_description	' || service_desc || E'\n
		use			' || template_name || E'\n
		check_command		check_ping!3000.0,80%!5000.0,100%\n
		check_freshness		0\n
		contact_groups		admins\n
		active_checks_enabled	0\n
		passive_checks_enabled	1\n
		flap_detection_enabled	0\n
		}\n';
	END LOOP;

	select description INTO host_agent_name from pem.agent where id = 1;

	FOR row IN SELECT al.name, ag.description FROM pem.alert al LEFT JOIN pem.agent ag ON (al.agent_id = ag.id) WHERE ag.id IN ( SELECT asb.agent_id FROM pem.agent_server_binding asb
LEFT JOIN pem.server s ON (s.id = asb.server_id) WHERE s.active = true AND NOT s.is_remote_monitoring) OR al.agent_id = -1

	LOOP
		service_desc = regexp_replace(regexp_replace(row.name, E'[`~$%^&*|''"<>?,=(]','-'), E'[)]', '-');
		service_config_text = service_config_text || E'\ndefine service {\n';

		IF row.description IS NULL THEN
			service_config_text = service_config_text || E'		host_name		' || host_agent_name || E'\n';
		ELSE
			service_config_text = service_config_text || E'		host_name		' || row.description || E'\n';
		END IF;

		service_config_text = service_config_text || E'		service_description	' || service_desc || E'\n
		use			' || template_name || E'\n
		check_command		check_ping!3000.0,80%!5000.0,100%\n
		check_freshness		0\n
		contact_groups		admins\n
		active_checks_enabled	0\n
		passive_checks_enabled	1\n
		flap_detection_enabled	0\n
		}\n';
	END LOOP;

RETURN service_config_text;

END $$  LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION pem.create_passive_service_check_result(
    IN alert_id integer,
    IN template text,
    IN current_value text,
    IN current_state text,
    OUT passive_check_result text)
  RETURNS text AS $$
DECLARE
	alert_name text;
	alert_object_name text;
	msg_object_name text;
	alert_thresholdvalue text;
	server_name text;
	server_ip text;
	server_port integer;
	agent_name text;
	status_text text;
	is_nagios_medium_alert_as_critical boolean:=false;
BEGIN

	-- Get alert, agent, server details
	SELECT
		a.name, a.thresholds,
		s.description, s.server, s.port,
		ag.description
	INTO
		alert_name, alert_thresholdvalue,
		server_name, server_ip, server_port,
		agent_name
	FROM
		pem.alert a
		LEFT JOIN pem.server s ON a.server_id = s.id
		LEFT JOIN pem.agent ag ON a.agent_id = ag.id
	WHERE
		a.id = alert_id;

	SELECT value INTO is_nagios_medium_alert_as_critical FROM pem.config WHERE param = 'nagios_medium_alert_as_critical';

	SELECT mail_subject INTO status_text FROM pem.email_template WHERE display_name = template;

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

	status_text = regexp_replace(status_text, '%AlertName%', alert_name);
	status_text = regexp_replace(status_text, '%ObjectName%', msg_object_name);
	IF current_state IS NOT NULL THEN
		status_text = regexp_replace(status_text, '%AlertType%', current_state);
	END IF;
	status_text = status_text || E'|| Threshold values: ' || alert_thresholdvalue;
	status_text = status_text || E'|| Current Value: ' || current_value;

	IF template NOT IN ('Alert Detected','Alert Cleared') THEN
		status_text = status_text || E'|| New State: %NewState% ';
		status_text = status_text || E'|| Old State: %OldState% ';
	END IF;

	passive_check_result = E'[';
	passive_check_result = passive_check_result || now() || E'] ';
	passive_check_result = passive_check_result || E'PROCESS_SERVICE_CHECK_RESULT;';

	IF server_name IS NOT NULL THEN
		passive_check_result = passive_check_result || server_name || E';';
	ELSE
		passive_check_result = passive_check_result || agent_name || E';';
	END IF;

	alert_name = regexp_replace(regexp_replace(alert_name, E'[`~$%^&*|''"<>?,(=]','-'), E'[)]', '-');
	passive_check_result = passive_check_result || alert_name || E';';
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

	passive_check_result = passive_check_result || status_text || E';';
END $$ LANGUAGE plpgsql;


CREATE OR REPLACE FUNCTION pem.submit_to_nagios(passive_check_result text)
  RETURNS boolean AS $$
DECLARE
	is_nagios_enabled 	boolean:= false;
	is_notify 			boolean:= false;

BEGIN
	SELECT value INTO is_nagios_enabled FROM pem.config WHERE param = 'nagios_enabled';

	IF is_nagios_enabled THEN
		INSERT INTO pem.nagios_spool(message,sent_status) VALUES (passive_check_result,'u');
		NOTIFY NAGIOS_SPOOL;
		return true;
	END IF;

	return false;
END $$ LANGUAGE plpgsql;


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
	is_submit_to_nagios boolean:= false;
	passive_check_result_text text;
	submit_to_nagios_val boolean:= false;
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

		-- submit to Nagios
		IF is_submit_to_nagios AND (NOT is_acknowledged) AND (NOT is_flapping_detected) THEN

			SELECT passive_check_result INTO passive_check_result_text FROM pem.create_passive_service_check_result(NEW.alert_id, 'Alert Detected',
															COALESCE(NEW.current_value, 0)::text,
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

		-- submit to Nagios
		IF is_submit_to_nagios AND (NOT is_acknowledged) AND (NOT is_flapping_detected) THEN

			-- If current state is NULL means alert is cleared.
			IF (NEW.current_state IS NOT NULL) THEN
				-- if OLD current_state is not null means alert level changed.
				IF (OLD.current_state IS NOT NULL AND (OLD.current_state > NEW.current_state)) THEN
					SELECT passive_check_result INTO passive_check_result_text FROM pem.create_passive_service_check_result(NEW.alert_id,
																	'Alert Level Decreased',
																	COALESCE(NEW.current_value, 0)::text,
																	NEW.current_state::text);
					passive_check_result_text = regexp_replace(passive_check_result_text, '%OldState%', OLD.current_state::text);
					passive_check_result_text = regexp_replace(passive_check_result_text, '%NewState%', NEW.current_state::text);

				ELSIF (OLD.current_state IS NOT NULL AND (OLD.current_state < NEW.current_state)) THEN
					SELECT passive_check_result INTO passive_check_result_text FROM pem.create_passive_service_check_result(NEW.alert_id,
																	'Alert Level Increased',
																	COALESCE(NEW.current_value, 0)::text,
																	NEW.current_state::text);
					passive_check_result_text = regexp_replace(passive_check_result_text, '%OldState%', OLD.current_state::text);
					passive_check_result_text = regexp_replace(passive_check_result_text, '%NewState%', NEW.current_state::text);

				ELSE
					SELECT passive_check_result INTO passive_check_result_text FROM pem.create_passive_service_check_result(NEW.alert_id,
																	'Alert Detected',
																	COALESCE(NEW.current_value, 0)::text,
																	NEW.current_state::text);
				END IF;

			ELSE
				SELECT passive_check_result INTO passive_check_result_text FROM pem.create_passive_service_check_result(NEW.alert_id,
																'Alert Cleared',
																COALESCE(NEW.current_value, 0)::text,
																NEW.current_state::text);
			END IF;

			submit_to_nagios_val = pem.submit_to_nagios(passive_check_result_text);
		END IF;
	END IF;

	RETURN NEW;
END;
$$ LANGUAGE plpgsql;


DROP FUNCTION pem.create_alert(text, integer, integer, integer, text, text, text, text, text[], text, numeric[], integer, integer, boolean, integer, boolean, boolean, timestamp with time zone, boolean, integer, boolean, integer, boolean, integer, boolean, integer, boolean, boolean, boolean, text);

CREATE OR REPLACE FUNCTION pem.create_alert(
    name text,
    alert_template_id integer,
    agent_id integer,
    server_id integer,
    database_name text,
    schema_name text,
    package_name text,
    object_name text,
    params text[],
    operator text,
    thresholds numeric[],
    check_frequency integer DEFAULT 1,
    history_retention integer DEFAULT 30,
    enabled boolean DEFAULT true,
    email_group_id integer DEFAULT NULL::integer,
    send_email boolean DEFAULT false,
    flapping_detected boolean DEFAULT false,
    last_flapping_detection_processed timestamp with time zone DEFAULT now(),
    send_trap boolean DEFAULT false,
    snmp_trap_version integer DEFAULT 2,
    low_send_trap boolean DEFAULT false,
    low_email_group_id integer DEFAULT NULL::integer,
    med_send_trap boolean DEFAULT false,
    med_email_group_id integer DEFAULT NULL::integer,
    high_send_trap boolean DEFAULT false,
    high_email_group_id integer DEFAULT NULL::integer,
    execute_script boolean DEFAULT false,
    execute_script_on_clear boolean DEFAULT false,
    execute_script_on_pem_server boolean DEFAULT false,
    script_code text DEFAULT NULL::text,
    submit_to_nagios boolean DEFAULT false)
  RETURNS void AS $$
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
BEGIN
	INSERT INTO pem.alert(name, enabled, template_id, agent_id, server_id,
							database_name, schema_name, package_name,
							object_name, params, operator, thresholds,
							check_frequency, history_retention, email_group_id, send_email,
							flapping_detected, last_flapping_detection_processed,
							send_trap, snmp_trap_version, low_send_trap, low_email_group_id, med_send_trap,
							med_email_group_id, high_send_trap, high_email_group_id, execute_script, execute_script_on_clear,
							execute_script_on_pem_server, script_code, submit_to_nagios)
	VALUES($1, $14, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, $15, $16, $17, $18, $19, $20,
			$21, $22, $23, $24, $25, $26, $27, $28, $29, $30, $31);
END;
 $$ LANGUAGE plpgsql;


INSERT INTO pem.config (param, value, unit, datatype) VALUES ('nagios_enabled', 't', 't/f', 'bool'); --Enable/disable submit to nagios functionality
INSERT INTO pem.config (param, value, unit, datatype ) VALUES ('nagios_medium_alert_as_critical', 'f', 't/f', 'bool'); --consider medium pem alerts as critical
INSERT INTO pem.config (param, value, unit, datatype) VALUES ('nagios_cmd_file_name', '/usr/local/nagios/var/rw/nagios.cmd', '', 'string'); --nagios cmd file to which passive service check result are needed to be sent
INSERT INTO pem.config (param, value, unit, datatype) VALUES ('nagios_spool_retention_time', '7', 'days', 'integer');  -- Default values to be used by purging function.

CREATE SEQUENCE pem.nagios_spool_id_seq;
GRANT UPDATE, SELECT, USAGE ON SEQUENCE pem.nagios_spool_id_seq TO pem_agent;

CREATE TABLE pem.nagios_spool
(
   id 				int NOT NULL DEFAULT nextval('pem.nagios_spool_id_seq'::regclass),
   message 			text NOT NULL,
   sent_status 		char NOT NULL,
   recorded_time 	timestamp with time zone NOT NULL DEFAULT now(),

   CONSTRAINT nagios_primary_key PRIMARY KEY (id),
   CONSTRAINT nagios_spool_sent_status CHECK (sent_status IN ('s', 'u', 'i'))
);

GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE pem.nagios_spool TO pem_agent;

CREATE OR REPLACE FUNCTION pem.purge_nagios_spool()
RETURNS void AS $$
	DELETE FROM pem.nagios_spool WHERE sent_status = 's' AND (now() - recorded_time) >= ((SELECT value FROM pem.config WHERE param = 'nagios_spool_retention_time')||'days')::interval;
$$ LANGUAGE sql SECURITY DEFINER;

SELECT pem.create_alert_template(
        'Number of ERRORS in the audit logfile on server M in the last X hours',
        'The number of ERRORS in the audit logfile on server M in last X hours',
        $sql$
SELECT COUNT(log_time)
FROM pemdata.audit_logs
WHERE error_severity = 'ERROR'
AND server_id = ${server_id}
AND log_time > now() - '${param_1} hours'::interval$sql$,
        200, '{ERRORS in the audit logfile in last X hours}', '{INTEGER}', '{Hours}', NULL,'{}', (SELECT CASE WHEN MAX(snmp_oid) > 0 THEN MAX(snmp_oid) + 1 ELSE 1 END FROM pem.alert_template WHERE object_type = 200), 'ADVANCED_SERVER');

SELECT pem.create_alert_template(
        'Number of WARNINGS in the audit logfile on server M in the last X hours',
        'The number of WARNINGS in audit logfile on server M in the last X hours',
        $sql$
SELECT COUNT(log_time)
FROM pemdata.audit_logs
WHERE error_severity = 'WARNING'
AND server_id = ${server_id}
AND log_time > now() - '${param_1} hours'::interval$sql$,
        200, '{WARNINGS in the audit logfile in last X hours}', '{INTEGER}', '{Hours}', NULL,'{}', (SELECT CASE WHEN MAX(snmp_oid) > 0 THEN MAX(snmp_oid) + 1 ELSE 1 END FROM pem.alert_template WHERE object_type = 200), 'ADVANCED_SERVER');

SELECT pem.create_alert_template(
        'Number of WARNINGS or ERRORS in the audit logfile on server M in the last X hours',
        'The number of WARNINGS or ERRORS in the audit logfile on server M in the last X hours',
        $sql$
SELECT COUNT(log_time)
FROM pemdata.audit_logs
WHERE (error_severity = 'WARNING' OR error_severity = 'ERROR')
AND server_id = ${server_id}
AND log_time > now() - '${param_1} hours'::interval$sql$,
        200, '{WARNINGS or ERRORS in the audit logfile in last X hours}', '{INTEGER}', '{Hours}', NULL,'{}', (SELECT CASE WHEN MAX(snmp_oid) > 0 THEN MAX(snmp_oid) + 1 ELSE 1 END FROM pem.alert_template WHERE object_type = 200), 'ADVANCED_SERVER');

SELECT pem.create_alert_template(
        'Number of ERRORS in the audit logfile on agent N in last X hours',
        'The number of ERRORS in the audit logfile on agent N in last X hours',
        $sql$
SELECT * FROM pem.agent_level_number_errors_warning_audit_logfile(${agent_id},${param_1},1)$sql$,
        100, '{ERRORS in the audit logfile in last X hours}', '{INTEGER}', '{Hours}', NULL,'{}', (SELECT CASE WHEN MAX(snmp_oid) > 0 THEN MAX(snmp_oid) + 1 ELSE 1 END FROM pem.alert_template WHERE object_type = 100), 'ADVANCED_SERVER');

SELECT pem.create_alert_template(
        'Number of WARNINGS in the audit logfile on agent N in last X hours',
        'The number of WARNINGS in the audit logfile on agent N in last X hours',
        $sql$
SELECT * FROM pem.agent_level_number_errors_warning_audit_logfile(${agent_id},${param_1},2)$sql$,
        100, '{WARNINGS in the audit logfile in last X hours}', '{INTEGER}', '{Hours}', NULL,'{}', (SELECT CASE WHEN MAX(snmp_oid) > 0 THEN MAX(snmp_oid) + 1 ELSE 1 END FROM pem.alert_template WHERE object_type = 100), 'ADVANCED_SERVER');

SELECT pem.create_alert_template(
        'Number of WARNINGS or ERRORS in the audit logfile on agent N in last X hours',
        'The number of WARNINGS or ERRORS in the audit logfile on agent N in last X hours',
        $sql$
SELECT * FROM pem.agent_level_number_errors_warning_audit_logfile(${agent_id},${param_1},3)$sql$,
        100, '{WARNINGS or ERRORS in the audit logfile in last X hours}', '{INTEGER}', '{Hours}', NULL,'{}', (SELECT CASE WHEN MAX(snmp_oid) > 0 THEN MAX(snmp_oid) + 1 ELSE 1 END FROM pem.alert_template WHERE object_type = 100), 'ADVANCED_SERVER');


CREATE OR REPLACE FUNCTION pem.agent_level_number_errors_warning_audit_logfile(integer, integer, integer)
  RETURNS integer AS $$
DECLARE
	total_servers RECORD;
	total_errors integer;
	error_count integer;

BEGIN
	total_errors := 0;
	error_count := 0;

	-- Find one agent is bindning to how many servers and depending on that total count will be calculated
	FOR total_servers IN SELECT DISTINCT server_id FROM pem.agent_server_binding WHERE agent_id = $1 ORDER BY server_id ASC LOOP

		error_count := 0;

		-- If user requested for ERROR count only then below condition will be executed
		IF $3 = 1 THEN
			SELECT COUNT(log_time) INTO error_count FROM pemdata.audit_logs WHERE error_severity = 'ERROR' AND server_id = total_servers.server_id  AND log_time > now() - ($2)*'1 hours'::interval;
		END IF;

		-- If user requested for WARNING count only then below condition will be executed
		IF $3 = 2 THEN
			SELECT COUNT(log_time) INTO error_count FROM pemdata.audit_logs WHERE error_severity = 'WARNING' AND server_id = total_servers.server_id  AND log_time > now() - ($2)*'1 hours'::interval;
		END IF;

		-- If user requested for WARNING OR ERROR count only then below condition will be executed
		IF $3 = 3 THEN
			SELECT COUNT(log_time) INTO error_count FROM pemdata.audit_logs WHERE (error_severity = 'ERROR' OR error_severity = 'WARNING') AND server_id = total_servers.server_id  AND log_time > now() - ($2)*'1 hours'::interval;
		END IF;

		total_errors := total_errors + error_count;
	END LOOP;

	RETURN total_errors;

END;
$$  LANGUAGE plpgsql;

COMMIT TRANSACTION;
