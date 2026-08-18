/***************************************************************************
 *
 * Postgres Enterprise Manager
 *
 * Copyright (C) 2010 - 2025, EnterpriseDB Corporation. All rights reserved.
 *
 ***************************************************************************/

-- NOTE: This sql file is responsible for PEM 9.1.0 schema upgrade.

BEGIN TRANSACTION;

CREATE OR REPLACE FUNCTION pem.schema_version()
  RETURNS integer AS
'SELECT 202301011::integer;'
  LANGUAGE 'sql' IMMUTABLE;
COMMENT ON FUNCTION pem.schema_version() IS 'Returns the version number of the PEM schema';

CREATE OR REPLACE FUNCTION pem.purge_webhook_spool()
RETURNS void AS $$
DECLARE
   cutoff_ts timestamp with time zone;
BEGIN
    cutoff_ts := (SELECT now() - CAST(value || ' ' || unit AS interval)
        FROM pem.config WHERE param = 'webhook_spool_retention_time');

    DELETE FROM pem.webhook_spool AS s
        WHERE s.recorded_time < cutoff_ts;

    -- Clean up the notifications for which webhook endpoint is no longer
    -- in the system.
    DELETE FROM pem.webhook_spool
    WHERE webhook_id not in (SELECT id FROM pem.webhook_endpoints);
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
	low_trap boolean:= false;
	med_trap boolean:= false;
	high_trap boolean:= false;
	is_send_webhook boolean:= false;
	webhook_ids integer[];
	low_webhook_ids integer[];
	med_webhook_ids integer[];
	high_webhook_ids integer[];
	cleared_webhook_ids integer[];
	payload text;
	send_webhook_val boolean:= false;
	is_execute_script boolean:= false;
	is_execute_on_clear boolean:= false;
	is_execute_on_pem_server boolean:= false;
	code text;
	is_submit_to_nagios boolean:= false;
	passive_check_result_text text;
	submit_to_nagios_val boolean:= false;
	alert_curr_value text;
	-- PEM-3612: Adding support for more placeholders
	alert_name text;
	alert_server_id int;
	alert_object_name text;
	alert_thresholdvalue text;
	server_name text;
	server_ip text;
	server_port integer;
	agent_name text;
	job_id integer;
	job_name text;
	alert_database_name text;
	alert_schema_name text;
	alert_package_name text;
	alert_db_object_name text;
	alert_object_type text;
	alert_params_details text;
	alert_parameters_names text[];
	alert_parameters_values text[];
	alert_info_details text;
	alert_info_names text[];
	alert_info_values text[];
	alert_param_units text[];

BEGIN
	-- Get alert details
	SELECT
		a.agent_id, a.template_id, a.send_email, a.acknowledged, a.flapping_detected, a.send_trap, a.snmp_trap_version, a.low_send_trap, a.med_send_trap,
		a.high_send_trap, wa._send_notification, wa._low_webhook_ids, wa._med_webhook_ids, wa._high_webhook_ids, wa._cleared_webhook_ids,
		a.execute_script, a.execute_script_on_clear, a.execute_script_on_pem_server, a.script_code, a.submit_to_nagios,
		-- Get additional alert, agent, server details
		a.name, a.server_id, a.thresholds, a.database_name, a.schema_name, a.package_name, a.object_name,
		a.params, s.description, s.server, s.port, ag.description, at.param_names, at.param_units, ptt.display_name,
        pas.info_cols, pas.info_vals
		INTO
		agentid, templateid, is_send_email, is_acknowledged, is_flapping_detected, is_send_trap, trap_version, low_trap, med_trap,
		high_trap, is_send_webhook, low_webhook_ids, med_webhook_ids, high_webhook_ids, cleared_webhook_ids,
		is_execute_script, is_execute_on_clear, is_execute_on_pem_server, code, is_submit_to_nagios,
		alert_name, alert_server_id, alert_thresholdvalue, alert_database_name, alert_schema_name, alert_package_name, alert_db_object_name,
		alert_parameters_values, server_name, server_ip, server_port, agent_name, alert_parameters_names, alert_param_units, alert_object_type,
		alert_info_names, alert_info_values
	FROM
		pem.alert a
		LEFT JOIN pem.get_webhook_endpoints(NEW.alert_id) wa ON a.id = wa._alertid
		LEFT JOIN pem.server s ON a.server_id = s.id
        LEFT JOIN pem.agent ag ON a.agent_id = ag.id
		LEFT JOIN pem.alert_template at ON a.template_id = at.id
		LEFT JOIN pem.alert_status pas ON (a.id = pas.alert_id)
		LEFT OUTER JOIN pem.probe_target_type ptt ON at.object_type = ptt.id
	WHERE
		a.id = NEW.alert_id;

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

    alert_params_details = '';

    IF alert_parameters_names IS NOT NULL THEN
        FOR idx IN 1 .. array_length(alert_parameters_names, 1)
        LOOP
        BEGIN
         alert_params_details = concat(
             alert_params_details,
             alert_parameters_names[idx], ': ', alert_parameters_values[idx], E'\n'
         );
        EXCEPTION WHEN OTHERS THEN
            -- Do nothing just keep looping
        END;
        END LOOP;
    END IF;

    alert_info_details = '';
    IF alert_info_values IS NOT NULL THEN
        FOR idx in 1 .. array_length(alert_info_values, 1)
        LOOP
            FOR ifn in 1 .. array_length(alert_info_names, 1)
            LOOP
                BEGIN
                    alert_info_details = concat(
                        alert_info_details,
                        alert_info_names[ifn], ': ',  COALESCE(alert_info_values[idx][ifn], '')::text, E'\n'
                    );
                EXCEPTION WHEN OTHERS THEN
                   -- Do nothing just keep looping
                END;
            END LOOP;
        END LOOP;
    END IF;

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

	IF ((TG_OP = 'INSERT') AND (NEW.current_state IS NOT NULL) AND (NOT is_flapping_detected)) THEN
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

        -- Get webhook_ids according to alert level low, med, high and cleared.
        IF (NEW.current_state IS NOT NULL) AND (NEW.current_state::text = 'LOW') AND COALESCE(array_length(low_webhook_ids, 1), 0) > 0 THEN
                webhook_ids = low_webhook_ids;
        ELSIF (NEW.current_state IS NOT NULL) AND (NEW.current_state::text = 'MEDIUM') AND COALESCE(array_length(med_webhook_ids, 1), 0) > 0 THEN
                webhook_ids = med_webhook_ids;
        ELSIF (NEW.current_state IS NOT NULL) AND (NEW.current_state::text = 'HIGH') AND COALESCE(array_length(high_webhook_ids, 1), 0) > 0 THEN
                webhook_ids = high_webhook_ids;
        END IF;

		-- SMTP Notifications
		IF is_send_email AND (NOT is_acknowledged) AND (NOT is_flapping_detected) THEN
			-- Create subject and message
			SELECT subject_mail, message_mail INTO subject, message FROM pem.create_email(NEW.alert_id, 'Alert Detected');
			subject = pem.replace_text_params(subject, '%AlertType%', NEW.current_state::text, 'g');
			message = pem.replace_text_params(message, '%CurrentValue%', alert_curr_value, 'g');
			message = pem.replace_text_params(message, '%AlertDetected%', now()::text, 'g');
			message = pem.replace_text_params(message, '%DownObjects%', down_objects_list::text, 'g');
			message = pem.replace_text_params(message, '%DetailInfo%', COALESCE(NEW.info, 'None')::text, 'g');

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
				varbinding_oid = varbinding_oid || '|' || enterprise_oid || '.10.15';
				varbinding_value = varbinding_value || '|' || down_objects_list::text;
			END IF;

			-- Send SNMP traps
			send_trap_val = pem.send_snmptrap(trap_oid, enterprise_oid, trap_version, varbinding_oid, varbinding_value);
		END IF;

        -- Webhook Notifications
		IF is_send_webhook AND (NOT is_acknowledged) AND (NOT is_flapping_detected) THEN
            -- Loop through all the webhook ids
            IF webhook_ids IS NOT NULL THEN
                FOR idx in 1 .. array_length(webhook_ids,1)
                LOOP
                    BEGIN
                        SELECT payload_template INTO payload FROM pem.webhook_endpoints where id = webhook_ids[idx];
                        -- Create Payload
                        payload = pem.replace_json_params(payload, '%AlertID%', NEW.alert_id::text, 'g');
                        payload = pem.replace_json_params(payload, '%ObjectType%', alert_object_type, 'g');
                        payload = pem.replace_json_params(payload, '%ThresholdValue%', alert_thresholdvalue::text, 'g');
                        payload = pem.replace_json_params(payload, '%CurrentValue%', alert_curr_value, 'g');
                        payload = pem.replace_json_params(payload, '%CurrentState%', NEW.current_state::text, 'g');
                        payload = pem.replace_json_params(payload, '%OldState%', '', 'g');
                        payload = pem.replace_json_params(payload, '%AlertRaisedTime%', now()::text, 'g');
                        payload = pem.replace_json_params(payload, '%ObjectName%', alert_object_name, 'g');
                        payload = pem.replace_json_params(payload, '%AlertName%', alert_name, 'g');
                        payload = pem.replace_json_params(payload, '%AlertDetected%', now()::text, 'g');

                        -- Additional support for more placeholders
                        IF agentid >= 1 THEN
                             payload = pem.replace_json_params(payload, '%AgentID%', agentid::text, 'g');
                             payload = pem.replace_json_params(payload, '%AgentName%', agent_name, 'g');
                         ELSE
                             payload = pem.replace_json_params(payload, '%AgentID%', '', 'g');
                             payload = pem.replace_json_params(payload, '%AgentName%', '', 'g');
                        END IF;

                        IF alert_server_id >= 1 THEN
                            payload = pem.replace_json_params(payload, '%ServerID%', alert_server_id::text, 'g');
                            server_name = replace(server_name, E'\\', E'\\\\');
                            payload = pem.replace_json_params(payload, '%ServerName%', server_name, 'g');
                            payload = pem.replace_json_params(payload, '%ServerIP%', server_ip, 'g');
                            payload = pem.replace_json_params(payload, '%ServerPort%', server_port::text, 'g');
                        ELSE
                            payload = pem.replace_json_params(payload, '%ServerID%', '', 'g');
                            payload = pem.replace_json_params(payload, '%ServerName%', '', 'g');
                            payload = pem.replace_json_params(payload, '%ServerIP%', '', 'g');
                            payload = pem.replace_json_params(payload, '%ServerPort%', '', 'g');
                        END IF;

                        IF alert_database_name IS NOT NULL AND alert_database_name <> '' THEN
                            alert_database_name = replace(alert_database_name, E'\\', E'\\\\');
                        END IF;
                        payload = pem.replace_json_params(payload, '%DatabaseName%', alert_database_name, 'g');

                        IF alert_schema_name IS NOT NULL AND alert_schema_name <> '' THEN
                            alert_schema_name = replace(alert_schema_name, E'\\', E'\\\\');
                        END IF;
                        payload = pem.replace_json_params(payload, '%SchemaName%', alert_schema_name, 'g');

                        IF alert_package_name IS NOT NULL AND alert_package_name <> '' THEN
                            alert_package_name = replace(alert_package_name, E'\\', E'\\\\');
                        END IF;
                        payload = pem.replace_json_params(payload, '%PackageName%', alert_package_name, 'g');

                        IF alert_db_object_name IS NOT NULL AND alert_db_object_name <> '' THEN
                            alert_db_object_name = replace(alert_db_object_name, E'\\', E'\\\\');
                        END IF;
                        payload = pem.replace_json_params(payload, '%DatabaseObjectName%', alert_db_object_name, 'g');

                        payload = pem.replace_json_params(payload, '%Parameters%', alert_params_details, 'g');
                        payload = pem.replace_json_params(payload, '%AlertInfo%', alert_info_details, 'g');

                        -- send webhook requests
                        send_webhook_val = pem.send_webhook(webhook_ids[idx], NEW.alert_id, agentid, payload);
                    EXCEPTION WHEN OTHERS THEN
                    -- Do nothing just keep looping
                    END;
                END LOOP;
            END IF;
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

	IF ((TG_OP = 'UPDATE') AND (NEW.current_state IS DISTINCT FROM OLD.current_state) AND (NOT is_flapping_detected)) THEN
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
		ELSIF (NEW.current_state IS NULL) AND (OLD.current_state::text = 'LOW') AND low_trap THEN
			is_send_trap = true;
		ELSIF (NEW.current_state IS NULL) AND (OLD.current_state::text = 'MEDIUM') AND med_trap THEN
			is_send_trap = true;
		ELSIF (NEW.current_state IS NULL) AND (OLD.current_state::text = 'HIGH') AND high_trap THEN
			is_send_trap = true;
		ELSE
			is_send_trap = false;
		END IF;

        -- Get webhook_ids according to alert level low, med, high and cleared.
        IF (NEW.current_state IS NOT NULL) AND (NEW.current_state::text = 'LOW') AND COALESCE(array_length(low_webhook_ids, 1), 0) > 0 THEN
                webhook_ids = low_webhook_ids;
        ELSIF (NEW.current_state IS NOT NULL) AND (NEW.current_state::text = 'MEDIUM') AND COALESCE(array_length(med_webhook_ids, 1), 0) > 0 THEN
                webhook_ids = med_webhook_ids;
        ELSIF (NEW.current_state IS NOT NULL) AND (NEW.current_state::text = 'HIGH') AND COALESCE(array_length(high_webhook_ids, 1), 0) > 0 THEN
                webhook_ids = high_webhook_ids;
        ELSIF (NEW.current_state IS NULL) AND (OLD.current_state IS NOT NULL) AND COALESCE(array_length(cleared_webhook_ids, 1), 0) > 0 THEN
                webhook_ids = cleared_webhook_ids;
        END IF;

		-- SMTP Notifications
		IF is_send_email AND (NOT is_acknowledged) AND (NOT is_flapping_detected) THEN
			-- If current state is NULL means alert is cleared.
			IF (NEW.current_state IS NOT NULL) THEN
				-- if OLD current_state is not null means alert level changed.
				IF (OLD.current_state IS NOT NULL AND (OLD.current_state > NEW.current_state)) THEN
					-- Create subject and message
					SELECT subject_mail, message_mail INTO subject, message FROM pem.create_email(NEW.alert_id, 'Alert Level Decreased');
					message = pem.replace_text_params(message, '%CurrentState%', NEW.current_state::text, 'g');
					message = pem.replace_text_params(message, '%OldState%', OLD.current_state::text, 'g');
					message = pem.replace_text_params(message, '%StateChanged%', now()::text, 'g');
				ELSIF (OLD.current_state IS NOT NULL AND (OLD.current_state < NEW.current_state)) THEN
					-- Create subject and message
					SELECT subject_mail, message_mail INTO subject, message FROM pem.create_email(NEW.alert_id, 'Alert Level Increased');
					message = pem.replace_text_params(message, '%CurrentState%', NEW.current_state::text, 'g');
					message = pem.replace_text_params(message, '%OldState%', OLD.current_state::text, 'g');
					message = pem.replace_text_params(message, '%StateChanged%', now()::text, 'g');
				ELSE
					-- Create subject and message
					SELECT subject_mail, message_mail INTO subject, message FROM pem.create_email(NEW.alert_id, 'Alert Detected');
					subject = pem.replace_text_params(subject, '%AlertType%', NEW.current_state::text, 'g');
					message = pem.replace_text_params(message, '%AlertDetected%', now()::text, 'g');
				END IF;
			ELSE
				-- Create subject and message
				SELECT subject_mail, message_mail INTO subject, message FROM pem.create_email(NEW.alert_id, 'Alert Cleared');
				message = pem.replace_text_params(message, '%AlertCleared%', now()::text, 'g');
			END IF;

			message = pem.replace_text_params(message, '%CurrentValue%', alert_curr_value, 'g');
			message = pem.replace_text_params(message, '%DownObjects%', down_objects_list::text, 'g');
			message = pem.replace_text_params(message, '%DetailInfo%', COALESCE(NEW.info, 'None')::text, 'g');

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
				varbinding_oid = varbinding_oid || '|' || enterprise_oid || '.10.15';
				varbinding_value = varbinding_value || '|' || down_objects_list::text;
			END IF;

			-- Send SNMP traps
			send_trap_val = pem.send_snmptrap(trap_oid, enterprise_oid, trap_version, varbinding_oid, varbinding_value);
		END IF;

        -- Webhook Notifications
		IF is_send_webhook AND (NOT is_acknowledged) AND (NOT is_flapping_detected) THEN
            -- Loop through all the webhook ids
            IF COALESCE(array_length(webhook_ids, 1), 0) > 0 THEN
                FOR idx in 1 .. array_length(webhook_ids,1)
                LOOP
                    BEGIN
                        SELECT payload_template INTO payload FROM pem.webhook_endpoints where id = webhook_ids[idx];
                        -- Create Payload
                        payload = pem.replace_json_params(payload, '%AlertID%', NEW.alert_id::text, 'g');
                        payload = pem.replace_json_params(payload, '%ObjectType%', alert_object_type, 'g');
                        payload = pem.replace_json_params(payload, '%ThresholdValue%', alert_thresholdvalue::text, 'g');
                        payload = pem.replace_json_params(payload, '%CurrentValue%', alert_curr_value, 'g');

                        IF (NEW.current_state IS NULL) THEN
                            payload = pem.replace_json_params(payload, '%CurrentState%', 'CLEARED', 'g');
                        ELSE
                            payload = pem.replace_json_params(payload, '%CurrentState%', NEW.current_state::text, 'g');
                        END IF;
                        payload = pem.replace_json_params(payload, '%OldState%', OLD.current_state::text, 'g');
                        payload = pem.replace_json_params(payload, '%AlertRaisedTime%', now()::text, 'g');
                        payload = pem.replace_json_params(payload, '%ObjectName%', alert_object_name, 'g');
                        payload = pem.replace_json_params(payload, '%AlertName%', alert_name, 'g');
                        payload = pem.replace_json_params(payload, '%AlertDetected%', now()::text, 'g');
                        -- Additional support for more placeholders
                        IF agentid >= 1 THEN
                             payload = pem.replace_json_params(payload, '%AgentID%', agentid::text, 'g');
                             payload = pem.replace_json_params(payload, '%AgentName%', agent_name, 'g');
                         ELSE
                             payload = pem.replace_json_params(payload, '%AgentID%', '', 'g');
                             payload = pem.replace_json_params(payload, '%AgentName%', '', 'g');
                        END IF;

                        IF alert_server_id >= 1 THEN
                            payload = pem.replace_json_params(payload, '%ServerID%', alert_server_id::text, 'g');
                            server_name = replace(server_name, E'\\', E'\\\\');
                            payload = pem.replace_json_params(payload, '%ServerName%', server_name, 'g');
                            payload = pem.replace_json_params(payload, '%ServerIP%', server_ip, 'g');
                            payload = pem.replace_json_params(payload, '%ServerPort%', server_port::text, 'g');
                        ELSE
                            payload = pem.replace_json_params(payload, '%ServerID%', '', 'g');
                            payload = pem.replace_json_params(payload, '%ServerName%', '', 'g');
                            payload = pem.replace_json_params(payload, '%ServerIP%', '', 'g');
                            payload = pem.replace_json_params(payload, '%ServerPort%', '', 'g');
                        END IF;

                        IF alert_database_name IS NOT NULL AND alert_database_name <> '' THEN
                            alert_database_name = replace(alert_database_name, E'\\', E'\\\\');
                        END IF;
                        payload = pem.replace_json_params(payload, '%DatabaseName%', alert_database_name, 'g');

                        IF alert_schema_name IS NOT NULL AND alert_schema_name <> '' THEN
                            alert_schema_name = replace(alert_schema_name, E'\\', E'\\\\');
                        END IF;
                        payload = pem.replace_json_params(payload, '%SchemaName%', alert_schema_name, 'g');

                        IF alert_package_name IS NOT NULL AND alert_package_name <> '' THEN
                            alert_package_name = replace(alert_package_name, E'\\', E'\\\\');
                        END IF;
                        payload = pem.replace_json_params(payload, '%PackageName%', alert_package_name, 'g');

                        IF alert_db_object_name IS NOT NULL AND alert_db_object_name <> '' THEN
                            alert_db_object_name = replace(alert_db_object_name, E'\\', E'\\\\');
                        END IF;
                        payload = pem.replace_json_params(payload, '%DatabaseObjectName%', alert_db_object_name, 'g');

                        payload = pem.replace_json_params(payload, '%Parameters%', alert_params_details, 'g');
                        payload = pem.replace_json_params(payload, '%AlertInfo%', alert_info_details, 'g');

                        -- send webhook requests
                        send_webhook_val = pem.send_webhook(webhook_ids[idx], NEW.alert_id, agentid, payload);
                    EXCEPTION WHEN OTHERS THEN
                    -- Do nothing just keep looping
                    END;
                END LOOP;
            END IF;
		END IF;

		-- Script Execution
		IF is_execute_script AND (NOT is_acknowledged) AND (NOT is_flapping_detected) THEN
			-- If current state is NULL means alert is cleared then need to check the value of is_execute_on_clear flag.
			IF (NEW.current_state IS NULL) THEN
				IF is_execute_on_clear THEN
					PERFORM pem.create_script_job(NEW.alert_id, alert_curr_value, 'CLEAR'::text, OLD.current_state::text, is_execute_on_pem_server, code);
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

-- PGD Workers
UPDATE pem.probe
SET probe_code = 'SELECT pid as worker_pid, query_start, state_change, wait_event_type, wait_event, state, worker_role_name,
		NULL AS worker_commit_timestamp, NULL AS worker_local_timestamp, origin_name, receive_lsn, receive_commit_lsn, last_xact_replay_lsn,
		last_xact_flush_lsn, last_xact_replay_timestamp, query
		FROM bdr.stat_activity a, bdr.workers w, bdr.subscription_summary ss
		where a.pid = w.worker_pid and w.worker_subid = ss.sub_id
		ORDER BY a.pid;'
WHERE internal_name = 'bdr_workers';

-- PGD Node Summary
INSERT INTO pem.probe_extension_version
    (probe_id, server_version_id, extension_version, probe_code)
SELECT
    (SELECT id FROM pem.probe WHERE internal_name = 'bdr_node_summary'),
    v.version,
    e.version,
    'SELECT node_name, node_group_name, peer_state_name, peer_target_state_name, sub_repsets FROM bdr.node_summary;'
FROM (
    VALUES (11100), (11200), (11300), (11400), (11500), (21100), (21200), (21300), (21400), (21500)
) v(version) CROSS JOIN (
	VALUES ('3.7.19'), ('3.7.18'), ('3.7.17'), ('3.7.16'), ('3.7.15'), ('3.7.14'), ('3.7.13.1'), ('3.7.13'), ('3.7.12'), ('3.7.11'), ('3.7.10'), ('3.7.9'), ('3.7.8'), ('3.7.7'), ('3.7.6'), ('3.7.5'), ('3.7.4'), ('3.7.3'), ('3.7.2'), ('3.6.19'), ('3.6.18'), ('3.6.17'), ('3.6.16'), ('3.6.15'), ('3.6.14'), ('3.6.12')
) e(version)
ON CONFLICT DO NOTHING;

-- PGD Node Summary
INSERT INTO pem.probe_extension_version
    (probe_id, server_version_id, extension_version, probe_code)
SELECT
    (SELECT id FROM pem.probe WHERE internal_name = 'bdr_node_summary'),
    v.version,
    e.version,
    'SELECT node_name, node_group_name, peer_state_name, peer_target_state_name, sub_repsets FROM bdr.node_summary;'
FROM (
    VALUES (11100), (11200), (11300), (11400), (11500), (21100), (21200), (21300), (21400), (21500)
) v(version) CROSS JOIN (
	VALUES ('3.7.19'), ('3.7.18'), ('3.7.17'), ('3.7.16'), ('3.7.15'), ('3.7.14'), ('3.7.13.1'), ('3.7.13'), ('3.7.12'), ('3.7.11'), ('3.7.10'), ('3.7.9'), ('3.7.8'), ('3.7.7'), ('3.7.6'), ('3.7.5'), ('3.7.4'), ('3.7.3'), ('3.7.2'), ('3.6.19'), ('3.6.18'), ('3.6.17'), ('3.6.16'), ('3.6.15'), ('3.6.14'), ('3.6.12')
) e(version)
ON CONFLICT DO NOTHING;

-- PGD Group Camo Details
INSERT INTO pem.probe_extension_version
    (probe_id, server_version_id, extension_version, probe_code)
SELECT
    (SELECT id FROM pem.probe WHERE internal_name = 'bdr_group_camo_details'),
    v.version,
    e.version,
    'SELECT node_name, camo_partner_of, camo_origin_for, is_camo_partner_connected, is_camo_partner_ready, camo_transactions_resolved, apply_lsn, receive_lsn, apply_queue_size from bdr.group_camo_details'
FROM (
    VALUES (11100), (11200), (11300), (11400), (11500), (21100), (21200), (21300), (21400), (21500)
) v(version) CROSS JOIN (
	VALUES ('3.7.19'), ('3.7.18'), ('3.7.17'), ('3.7.16'), ('3.7.15'), ('3.7.14'), ('3.7.13.1'), ('3.7.13'), ('3.7.12'), ('3.7.11'), ('3.7.10'), ('3.7.9'), ('3.7.8'), ('3.7.7'), ('3.7.6'), ('3.7.5'), ('3.7.4'), ('3.7.3'), ('3.7.2'), ('3.6.19'), ('3.6.18'), ('3.6.17'), ('3.6.16'), ('3.6.15'), ('3.6.14'), ('3.6.12')
) e(version)
ON CONFLICT DO NOTHING;

-- PGD Group Versions Details
UPDATE pem.probe
	SET probe_code = 'SELECT node_name, postgres_version, ''N/A'' AS pglogical_version, bdr_version, ''N/A'' AS bdr_edition FROM bdr.group_versions_details;'
	WHERE internal_name = 'bdr_group_versions_details';

INSERT INTO pem.probe_extension_version
    (probe_id, server_version_id, extension_version, probe_code)
SELECT
    (
    SELECT id FROM pem.probe WHERE internal_name = 'bdr_group_versions_details'),
    v.version,
    e.version,
    'SELECT node_name, postgres_version, pglogical_version, bdr_version, bdr_edition FROM bdr.group_versions_details;'
FROM (
    VALUES (11100), (11200), (11300), (11400), (11500), (21100), (21200), (21300), (21400), (21500)
) v(version) CROSS JOIN (
	VALUES ('3.7.19'), ('3.7.18'), ('3.7.17'), ('3.7.16'), ('3.7.15'), ('3.7.14'), ('3.7.13.1'), ('3.7.13'), ('3.7.12'), ('3.7.11'), ('3.7.10'), ('3.7.9'), ('3.7.8'), ('3.7.7'), ('3.7.6'), ('3.7.5'), ('3.7.4'), ('3.7.3'), ('3.7.2'), ('3.6.19'), ('3.6.18'), ('3.6.17'), ('3.6.16'), ('3.6.15'), ('3.6.14'), ('3.6.12')
) e(version)
ON CONFLICT DO NOTHING;

INSERT INTO pem.probe_extension_version
    (probe_id, server_version_id, extension_version, probe_code)
SELECT
    (
    SELECT id FROM pem.probe WHERE internal_name = 'bdr_group_versions_details'),
    v.version,
    e.version,
    'SELECT node_name, postgres_version, ''N/A'' AS pglogical_version, bdr_version, bdr_edition FROM bdr.group_versions_details;'
FROM (
    VALUES (11100), (11200), (11300), (11400), (11500), (21100), (21200), (21300), (21400), (21500)
) v(version) CROSS JOIN (
	VALUES ('4.2.2'),  ('4.2.1'),  ('4.2.0'),  ('4.1.1'),  ('4.1.0'),  ('4.0.2'),
        ('4.0.1'),  ('4.0.0')
) e(version);

/*
-- There were some changes in PGD v5 catalogs which breaks some of PEM probes, so we need to add version specific code
*/

--
-- PGD Workers
--
INSERT INTO pem.probe_extension_version
    (probe_id, server_version_id, extension_version, probe_code)
SELECT
    (SELECT id FROM pem.probe WHERE internal_name = 'bdr_workers'),
    v.version,
    e.version,
    'SELECT pid as worker_pid, query_start, state_change, wait_event_type, wait_event, state, worker_role_name,
		worker_commit_timestamp, worker_local_timestamp, origin_name, receive_lsn, receive_commit_lsn, last_xact_replay_lsn,
		last_xact_flush_lsn, last_xact_replay_timestamp, query
		FROM bdr.stat_activity a, bdr.workers w, bdr.subscription_summary ss
		where a.pid = w.worker_pid and w.worker_subid = ss.sub_id
		ORDER BY a.pid;'
FROM (
    VALUES (11100), (11200), (11300), (11400), (11500), (21100), (21200), (21300), (21400), (21500)
) v(version) CROSS JOIN (
    VALUES
        ('3.7.19'), ('3.7.18'), ('3.7.17'), ('3.7.16'), ('3.7.15'), ('3.7.14'),
        ('3.7.13.1'), ('3.7.13'), ('3.7.12'), ('3.7.11'), ('3.7.10'),
        ('3.7.9'), ('3.7.8'), ('3.7.7'), ('3.7.6'), ('3.7.5'), ('3.7.4'),
        ('3.7.3'), ('3.7.2'), ('3.6.19'), ('3.6.18'), ('3.6.17'), ('3.6.16'),
        ('3.6.15'), ('3.6.14'), ('3.6.12'),
        ('4.2.2'),  ('4.2.1'),  ('4.2.0'),  ('4.1.1'),  ('4.1.0'),  ('4.0.2'),
        ('4.0.1'),  ('4.0.0')
) e(version)
ON CONFLICT DO NOTHING;

-- bdr.worker_errors is like a log, and contains persistent data, and it is not a statistics really.
DELETE FROM pem.alert
	WHERE template_id = (
		SELECT id FROM pem.alert_template
		WHERE display_name = 'PGD worker error detected' AND
			is_system_template AND probe_dependency_list = '{bdr_worker_errors}'
	);
DELETE FROM pem.alert_template
	WHERE display_name = 'PGD worker error detected' AND
		is_system_template AND probe_dependency_list = '{bdr_worker_errors}';

DELETE FROM pem.chart WHERE id = 107 AND name = 'PGD Worker Errors';
DELETE FROM pem.chart_func WHERE id = 107 AND func = 'table_bdr_worker_errors';

DROP TABLE IF EXISTS pemdata.bdr_worker_errors;
DROP TABLE IF EXISTS pemhistory.bdr_worker_errors;

DELETE FROM pem.probe
	WHERE internal_name = 'bdr_worker_errors' AND is_system_probe;

-- Make the node_name and commit_index primary keys in the bdr_group_raft_details probe.
DO $$
DECLARE
        v_probe_id pem.probe.id%TYPE;
BEGIN
        SELECT id INTO v_probe_id FROM pem.probe WHERE internal_name = 'bdr_group_raft_details';
        IF EXISTS(
                SELECT internal_name FROM pem.probe_column
                WHERE internal_name = 'commit_index' AND display_position = 2 AND probe_id = v_probe_id
        ) THEN
                RAISE INFO $MSG$-- No changes required for 'bdr_group_raft_details' probe$MSG$;
                RETURN;
        END IF;

        LOCK TABLE pemdata.bdr_group_raft_details;
        LOCK TABLE pemhistory.bdr_group_raft_details;

        ALTER TABLE pemdata.bdr_group_raft_details RENAME TO bdr_group_raft_details_20230203;
        ALTER TABLE pemhistory.bdr_group_raft_details RENAME TO bdr_group_raft_details_20230203;
        ALTER INDEX pemhistory.bdr_group_raft_details_timeidx RENAME TO bdr_group_raft_details_timeidx_20230203;
        ALTER TABLE pemdata.bdr_group_raft_details_pkey RENAME TO bdr_group_raft_details_pkey_20230203;
        ALTER TABLE pemhistory.bdr_group_raft_details_pkey RENAME TO bdr_group_raft_details_pkey_20230203;

        UPDATE pem.probe
        SET probe_code = $SQL$SELECT distinct node_name, COALESCE(commit_index::text, 'N/A') AS commit_index, state, leader_id, current_term FROM bdr.group_raft_details;$SQL$
        WHERE id = v_probe_id;

        DELETE FROM pem.probe_column WHERE probe_id = v_probe_id;

        INSERT INTO pem.probe_column
        (probe_id, internal_name, display_name, display_position, classification,
                sql_data_type, unit_of_value, calculate_pit, discard_history, pit_by_default, is_graphable)
        SELECT
        (SELECT id FROM pem.probe WHERE internal_name = 'bdr_group_raft_details'),
        v.internal_name, v.display_name, v.display_position, v.classification,
        v.sql_data_type, v.unit_of_value, v.calculate_pit, v.discard_history, v.pit_by_default, v.is_graphable
        FROM
        (VALUES
                ('node_name',    'Node Name',    1, 'k', 'text',    '',   false, false, false, false),
                ('commit_index', 'Commit Index', 2, 'k', 'text',    '',   false, false, false, false),
                ('state',        'State',        3, 'm', 'text',    '',   false, false, false, false),
                ('leader_id',    'Leader ID',    4, 'm', 'text',    '',   false, false, false, false),
                ('current_term', 'Current Term', 5, 'm', 'text',    '',   false, false, false, false)
                ) v(internal_name, display_name, display_position, classification,
                sql_data_type, unit_of_value, calculate_pit, discard_history, pit_by_default, is_graphable);

        PERFORM pem.create_data_and_history_tables();

        ALTER TABLE pemdata.bdr_group_raft_details DISABLE TRIGGER USER;

        INSERT INTO pemhistory.bdr_group_raft_details (
                recorded_time, server_id, database_name, node_name, commit_index, state, leader_id, current_term
        )
        SELECT
        recorded_time, server_id, database_name, node_name, COALESCE(commit_index, 'N/A'), state, leader_id, current_term
        FROM pemhistory.bdr_group_raft_details_20230203;

        INSERT INTO pemdata.bdr_group_raft_details (
                recorded_time, server_id, database_name, node_name, commit_index, state, leader_id, current_term
        )
        SELECT
        recorded_time, server_id, database_name, node_name, COALESCE(commit_index, 'N/A'), state, leader_id, current_term
        FROM pemdata.bdr_group_raft_details_20230203;

        DROP TABLE pemhistory.bdr_group_raft_details_20230203;
        DROP TABLE pemdata.bdr_group_raft_details_20230203;
END$$ LANGUAGE 'plpgsql';

END TRANSACTION;
