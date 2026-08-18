/***************************************************************************
 *
 * Postgres Enterprise Manager
 *
 * Copyright (C) 2010 - 2025, EnterpriseDB Corporation. All rights reserved.
 *
 ***************************************************************************/

-- NOTE: This sql file is responsible for PEM 8.1.0 schema upgrade.

BEGIN TRANSACTION;

CREATE OR REPLACE FUNCTION pem.schema_version() RETURNS integer AS
'SELECT 202104021::integer;'
LANGUAGE 'sql' IMMUTABLE;
COMMENT ON FUNCTION pem.schema_version()
	IS 'Returns the version number of the PEM schema';

-- JIRA: PEM-3966 - Do not process the state count, if flapping is detected
-- for that specific alert
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
				varbinding_oid = varbinding_oid || '|' || enterprise_oid || '.7.15';
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
		ELSIF (NEW.current_state IS NULL) AND (OLD.current_state IS NOT NULL) AND is_send_trap THEN
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
				varbinding_oid = varbinding_oid || '|' || enterprise_oid || '.7.15';
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

-- JIRA: PEM-3810
-- It will only fetch the rows for the database which has been deleted
-- by the user making the data in pemhistory schema obsolete.
CREATE OR REPLACE VIEW pem.probe_obsolete_target_view AS
-- We need invert rows of pemdata.oc_database from pemhistory.oc_database
-- because we already have job step to purge those data
WITH oc_database AS (
        SELECT database_name, server_id, connections_allowed
        FROM pemhistory.oc_database phocd
        WHERE database_name NOT IN (
            SELECT database_name
            FROM pemdata.oc_database
            WHERE server_id = phocd.server_id
        )
		AND connections_allowed
)
SELECT
	p.id AS probe_id, p.display_name AS probe_display_name,
	p.internal_name AS probe_internal_name, p.probe_key_list,
	p.applies_to_id,
	a.id AS agent_id, b.server_id, ocd.database_name AS database_name,
	ARRAY['server_id', 'database_name']::text[] AS parameter_name_list,
	ARRAY[b.server_id::text, ocd.database_name]::text[] AS parameter_value_list,
	p.collection_method,
	COALESCE(NULLIF(TRIM(psv.probe_code), ''), p.probe_code) AS probe_code,
	p.enabled_by_default, p.default_execution_frequency,
	p.default_lifetime,
	COALESCE(c.enabled, p.enabled_by_default) AS enabled,
	COALESCE(c.execution_frequency, p.default_execution_frequency)
		AS execution_frequency,
	COALESCE(c.lifetime, p.default_lifetime) AS lifetime,
	a.active AS agent_active,
	p.discard_history,
	p.is_system_probe
FROM
	pem.probe p
	CROSS JOIN pem.agent_server_binding b
	INNER JOIN pem.agent a ON b.agent_id = a.id
	LEFT JOIN pemdata.server_info sd ON b.server_id = sd.server_id
	LEFT JOIN pem.probe_server_version psv
		ON p.id = psv.probe_id
		AND sd.server_version_id = psv.server_version_id
	INNER JOIN oc_database ocd
		ON b.server_id = ocd.server_id
	LEFT JOIN pem.probe_config_database c
		ON p.id = c.probe_id AND b.server_id = c.server_id
		AND ocd.database_name = c.database_name
WHERE
	p.target_type_id = 300
	AND NOT p.deleted
	AND ocd.connections_allowed
	AND (p.agent_capability IS NULL
		OR p.agent_capability = ANY(a.agent_capability_list))
	AND (p.any_server_version OR psv.probe_id IS NOT NULL)
	AND (p.collection_method != 'b' OR
		(p.collection_method ='b' AND (a.agent_capability_list @> ARRAY['allow_batch_probes'])
			AND ((strpos(a.platform, p.platform) != 0) OR (a.platform !~ 'windows' AND p.platform = 'unix'))))
UNION ALL
SELECT
	p.id AS probe_id, p.display_name AS probe_display_name,
	p.internal_name AS probe_internal_name, p.probe_key_list,
	p.applies_to_id,
	a.id AS agent_id, b.server_id, oc.database_name AS database_name,
	ARRAY['server_id', 'database_name', 'schema_name']::text[]
		AS parameter_name_list,
	ARRAY[b.server_id::text, oc.database_name, oc.schema_name]::text[]
		AS parameter_value_list,
	p.collection_method,
	COALESCE(NULLIF(TRIM(psv.probe_code), ''), p.probe_code) AS probe_code,
	p.enabled_by_default, p.default_execution_frequency,
	p.default_lifetime,
	COALESCE(c.enabled, p.enabled_by_default) AS enabled,
	COALESCE(c.execution_frequency, p.default_execution_frequency)
		AS execution_frequency,
	COALESCE(c.lifetime, p.default_lifetime) AS lifetime,
	a.active AS agent_active,
	p.discard_history,
	p.is_system_probe
FROM
	pem.probe p
	CROSS JOIN pem.agent_server_binding b
	INNER JOIN pem.agent a ON b.agent_id = a.id
	LEFT JOIN pemdata.server_info sd ON b.server_id = sd.server_id
	LEFT JOIN pem.probe_server_version psv
		ON p.id = psv.probe_id
		AND sd.server_version_id = psv.server_version_id
	INNER JOIN oc_database ocd
		ON b.server_id = ocd.server_id
	INNER JOIN pemdata.oc_schema oc
		ON ocd.server_id = oc.server_id
		AND ocd.database_name = oc.database_name
	LEFT JOIN pem.probe_config_schema c
		ON p.id = c.probe_id AND b.server_id = c.server_id
		AND oc.database_name = c.database_name
		AND oc.schema_name = c.schema_name
WHERE
	p.target_type_id = 400
	AND NOT p.deleted
	AND ocd.connections_allowed
	AND (p.agent_capability IS NULL
		OR p.agent_capability = ANY(a.agent_capability_list))
	AND (p.any_server_version OR psv.probe_id IS NOT NULL)
	AND (p.collection_method != 'b' OR
		(p.collection_method ='b' AND (a.agent_capability_list @> ARRAY['allow_batch_probes'])
			AND ((strpos(a.platform, p.platform) != 0) OR (a.platform !~ 'windows' AND p.platform = 'unix'))))
UNION ALL
SELECT
	p.id AS probe_id, p.display_name AS probe_display_name,
	p.internal_name AS probe_internal_name, p.probe_key_list,
	p.applies_to_id,
	a.id AS agent_id, b.server_id, oc.database_name AS database_name,
	ARRAY['server_id', 'database_name', 'schema_name', 'table_name']::text[]
		AS parameter_name_list,
	ARRAY[b.server_id::text, oc.database_name, oc.schema_name,
		oc.table_name]::text[] AS parameter_value_list,
	p.collection_method,
	COALESCE(NULLIF(TRIM(psv.probe_code), ''), p.probe_code) AS probe_code,
	p.enabled_by_default, p.default_execution_frequency,
	p.default_lifetime,
	COALESCE(c.enabled, p.enabled_by_default) AS enabled,
	COALESCE(c.execution_frequency, p.default_execution_frequency)
		AS execution_frequency,
	COALESCE(c.lifetime, p.default_lifetime) AS lifetime,
	a.active AS agent_active,
	p.discard_history,
	p.is_system_probe
FROM
	pem.probe p
	CROSS JOIN pem.agent_server_binding b
	INNER JOIN pem.agent a ON b.agent_id = a.id
	LEFT JOIN pemdata.server_info sd ON b.server_id = sd.server_id
	LEFT JOIN pem.probe_server_version psv
		ON p.id = psv.probe_id
		AND sd.server_version_id = psv.server_version_id
	INNER JOIN oc_database ocd
		ON b.server_id = ocd.server_id
	INNER JOIN pemdata.oc_table oc
		ON ocd.server_id = oc.server_id
		AND ocd.database_name = oc.database_name
	LEFT JOIN pem.probe_config_table c
		ON p.id = c.probe_id AND b.server_id = c.server_id
		AND oc.database_name = c.database_name
		AND oc.schema_name = c.schema_name
		AND oc.table_name = c.table_name
WHERE
	p.target_type_id = 500
	AND NOT p.deleted
	AND ocd.connections_allowed
	AND (p.agent_capability IS NULL
		OR p.agent_capability = ANY(a.agent_capability_list))
	AND (p.any_server_version OR psv.probe_id IS NOT NULL)
	AND (p.collection_method != 'b' OR
		(p.collection_method ='b' AND (a.agent_capability_list @> ARRAY['allow_batch_probes'])
			AND ((strpos(a.platform, p.platform) != 0) OR (a.platform !~ 'windows' AND p.platform = 'unix'))))
UNION ALL
SELECT
	p.id AS probe_id, p.display_name AS probe_display_name,
	p.internal_name AS probe_internal_name, p.probe_key_list,
	p.applies_to_id,
	a.id AS agent_id, b.server_id, oc.database_name AS database_name,
	ARRAY['server_id', 'database_name', 'schema_name', 'index_name']::text[]
		AS parameter_name_list,
	ARRAY[b.server_id::text, oc.database_name, oc.schema_name,
		oc.index_name]::text[] AS parameter_value_list,
	p.collection_method,
	COALESCE(NULLIF(TRIM(psv.probe_code), ''), p.probe_code) AS probe_code,
	p.enabled_by_default, p.default_execution_frequency,
	p.default_lifetime,
	COALESCE(c.enabled, p.enabled_by_default) AS enabled,
	COALESCE(c.execution_frequency, p.default_execution_frequency)
		AS execution_frequency,
	COALESCE(c.lifetime, p.default_lifetime) AS lifetime,
	a.active AS agent_active,
	p.discard_history,
	p.is_system_probe
FROM
	pem.probe p
	CROSS JOIN pem.agent_server_binding b
	INNER JOIN pem.agent a ON b.agent_id = a.id
	LEFT JOIN pemdata.server_info sd ON b.server_id = sd.server_id
	LEFT JOIN pem.probe_server_version psv
		ON p.id = psv.probe_id
		AND sd.server_version_id = psv.server_version_id
	INNER JOIN oc_database ocd
		ON b.server_id = ocd.server_id
	INNER JOIN pemdata.oc_index oc
		ON ocd.server_id = oc.server_id
		AND ocd.database_name = oc.database_name
	LEFT JOIN pem.probe_config_index c
		ON p.id = c.probe_id AND b.server_id = c.server_id
		AND oc.database_name = c.database_name
		AND oc.schema_name = c.schema_name
		AND oc.index_name = c.index_name
WHERE
	p.target_type_id = 600
	AND NOT p.deleted
	AND ocd.connections_allowed
	AND (p.agent_capability IS NULL
		OR p.agent_capability = ANY(a.agent_capability_list))
	AND (p.any_server_version OR psv.probe_id IS NOT NULL)
	AND (p.collection_method != 'b' OR
		(p.collection_method ='b' AND (a.agent_capability_list @> ARRAY['allow_batch_probes'])
			AND ((strpos(a.platform, p.platform) != 0) OR (a.platform !~ 'windows' AND p.platform = 'unix'))))
UNION ALL
SELECT
	p.id AS probe_id, p.display_name AS probe_display_name,
	p.internal_name AS probe_internal_name, p.probe_key_list,
	p.applies_to_id,
	a.id AS agent_id, b.server_id, oc.database_name AS database_name,
	ARRAY['server_id', 'database_name', 'schema_name', 'sequence_name']::text[]
		AS parameter_name_list,
	ARRAY[b.server_id::text, oc.database_name, oc.schema_name,
		oc.sequence_name]::text[] AS parameter_value_list,
	p.collection_method,
	COALESCE(NULLIF(TRIM(psv.probe_code), ''), p.probe_code) AS probe_code,
	p.enabled_by_default, p.default_execution_frequency,
	p.default_lifetime,
	COALESCE(c.enabled, p.enabled_by_default) AS enabled,
	COALESCE(c.execution_frequency, p.default_execution_frequency)
		AS execution_frequency,
	COALESCE(c.lifetime, p.default_lifetime) AS lifetime,
	a.active AS agent_active,
	p.discard_history,
	p.is_system_probe
FROM
	pem.probe p
	CROSS JOIN pem.agent_server_binding b
	INNER JOIN pem.agent a ON b.agent_id = a.id
	LEFT JOIN pemdata.server_info sd ON b.server_id = sd.server_id
	LEFT JOIN pem.probe_server_version psv
		ON p.id = psv.probe_id
		AND sd.server_version_id = psv.server_version_id
	INNER JOIN oc_database ocd
		ON b.server_id = ocd.server_id
	INNER JOIN pemdata.oc_sequence oc
		ON ocd.server_id = oc.server_id
		AND ocd.database_name = oc.database_name
	LEFT JOIN pem.probe_config_sequence c
		ON p.id = c.probe_id AND b.server_id = c.server_id
		AND oc.database_name = c.database_name
		AND oc.schema_name = c.schema_name
		AND oc.sequence_name = c.sequence_name
WHERE
	p.target_type_id = 700
	AND NOT p.deleted
	AND ocd.connections_allowed
	AND (p.agent_capability IS NULL
		OR p.agent_capability = ANY(a.agent_capability_list))
	AND (p.any_server_version OR psv.probe_id IS NOT NULL)
	AND (p.collection_method != 'b' OR
		(p.collection_method ='b' AND (a.agent_capability_list @> ARRAY['allow_batch_probes'])
			AND ((strpos(a.platform, p.platform) != 0) OR (a.platform !~ 'windows' AND p.platform = 'unix'))))
UNION ALL
SELECT
	p.id AS probe_id, p.display_name AS probe_display_name,
	p.internal_name AS probe_internal_name, p.probe_key_list,
	p.applies_to_id,
	a.id AS agent_id, b.server_id, oc.database_name AS database_name,
	ARRAY['server_id', 'database_name', 'schema_name', 'function_name']::text[]
		AS parameter_name_list,
	ARRAY[b.server_id::text, oc.database_name, oc.schema_name,
		oc.function_name]::text[] AS parameter_value_list,
	p.collection_method,
	COALESCE(NULLIF(TRIM(psv.probe_code), ''), p.probe_code) AS probe_code,
	p.enabled_by_default, p.default_execution_frequency,
	p.default_lifetime,
	COALESCE(c.enabled, p.enabled_by_default) AS enabled,
	COALESCE(c.execution_frequency, p.default_execution_frequency)
		AS execution_frequency,
	COALESCE(c.lifetime, p.default_lifetime) AS lifetime,
	a.active AS agent_active,
	p.discard_history,
	p.is_system_probe
FROM
	pem.probe p
	CROSS JOIN pem.agent_server_binding b
	INNER JOIN pem.agent a ON b.agent_id = a.id
	LEFT JOIN pemdata.server_info sd ON b.server_id = sd.server_id
	LEFT JOIN pem.probe_server_version psv
		ON p.id = psv.probe_id
		AND sd.server_version_id = psv.server_version_id
	INNER JOIN oc_database ocd
		ON b.server_id = ocd.server_id
	INNER JOIN pemdata.oc_function oc
		ON ocd.server_id = oc.server_id
		AND ocd.database_name = oc.database_name
	LEFT JOIN pem.probe_config_function c
		ON p.id = c.probe_id AND b.server_id = c.server_id
		AND oc.database_name = c.database_name
		AND oc.schema_name = c.schema_name
		AND oc.function_name = c.function_name
WHERE
	p.target_type_id = 800
	AND NOT p.deleted
	AND ocd.connections_allowed
	AND (p.agent_capability IS NULL
		OR p.agent_capability = ANY(a.agent_capability_list))
	AND (p.any_server_version OR psv.probe_id IS NOT NULL)
	AND (p.collection_method != 'b' OR
		(p.collection_method ='b' AND (a.agent_capability_list @> ARRAY['allow_batch_probes'])
			AND ((strpos(a.platform, p.platform) != 0) OR (a.platform !~ 'windows' AND p.platform = 'unix'))))
UNION ALL
SELECT
	p.id AS probe_id, p.display_name AS probe_display_name,
	p.internal_name AS probe_internal_name, p.probe_key_list,
	p.applies_to_id,
	a.id AS agent_id, b.server_id, oc.database_name AS database_name,
	ARRAY['server_id', 'database_name', 'schema_name', 'view_name']::text[]
		AS parameter_name_list,
	ARRAY[b.server_id::text, oc.database_name, oc.schema_name,
		oc.view_name]::text[] AS parameter_value_list,
	p.collection_method,
	COALESCE(NULLIF(TRIM(psv.probe_code), ''), p.probe_code) AS probe_code,
	p.enabled_by_default, p.default_execution_frequency,
	p.default_lifetime,
	COALESCE(c.enabled, p.enabled_by_default) AS enabled,
	COALESCE(c.execution_frequency, p.default_execution_frequency)
		AS execution_frequency,
	COALESCE(c.lifetime, p.default_lifetime) AS lifetime,
	a.active AS agent_active,
	p.discard_history,
	p.is_system_probe
FROM
	pem.probe p
	CROSS JOIN pem.agent_server_binding b
	INNER JOIN pem.agent a ON b.agent_id = a.id
	LEFT JOIN pemdata.server_info sd ON b.server_id = sd.server_id
	LEFT JOIN pem.probe_server_version psv
		ON p.id = psv.probe_id
		AND sd.server_version_id = psv.server_version_id
	INNER JOIN oc_database ocd
		ON b.server_id = ocd.server_id
	INNER JOIN pemdata.oc_views oc
		ON ocd.server_id = oc.server_id
		AND ocd.database_name = oc.database_name
	LEFT JOIN pem.probe_config_view c
		ON p.id = c.probe_id AND b.server_id = c.server_id
		AND oc.database_name = c.database_name
		AND oc.schema_name = c.schema_name
		AND oc.view_name = c.view_name
WHERE
	p.target_type_id = 900
	AND NOT p.deleted
	AND ocd.connections_allowed
	AND (p.agent_capability IS NULL
		OR p.agent_capability = ANY(a.agent_capability_list))
	AND (p.any_server_version OR psv.probe_id IS NOT NULL)
	AND (p.collection_method != 'b' OR
		(p.collection_method ='b' AND (a.agent_capability_list @> ARRAY['allow_batch_probes'])
			AND ((strpos(a.platform, p.platform) != 0) OR (a.platform !~ 'windows' AND p.platform = 'unix'))));

-- This view will fetch the data for the deleted servers
-- using which we can purge the data of those servers
CREATE OR REPLACE VIEW pem.probe_deleted_target_view AS
WITH oc_database AS (
        SELECT database_name, server_id, connections_allowed
        FROM pemhistory.oc_database phocd
		WHERE connections_allowed
)
SELECT
	p.internal_name AS probe_internal_name,
	ARRAY['agent_id']::text[] AS parameter_name_list,
	ARRAY[a.id::text]::text[] AS parameter_value_list,
	COALESCE(c.lifetime, p.default_lifetime) AS lifetime,
	p.discard_history
FROM
	pem.probe p
	CROSS JOIN pem.agent a
	LEFT JOIN pem.probe_config_agent c
		ON p.id = c.probe_id AND a.id = c.agent_id
WHERE
	p.target_type_id = 100
	AND NOT p.deleted
	AND NOT a.active
UNION ALL
SELECT
	p.internal_name AS probe_internal_name,
	ARRAY['server_id']::text[] AS parameter_name_list,
	ARRAY[s.id::text]::text[] AS parameter_value_list,
	COALESCE(c.lifetime, p.default_lifetime) AS lifetime,
	p.discard_history
FROM
	pem.probe p
    CROSS JOIN pem.server s
	LEFT JOIN pem.probe_config_database c
		ON p.id = c.probe_id AND s.id = c.server_id
WHERE
	p.target_type_id = 200
	AND NOT s.active
	AND NOT p.deleted
UNION ALL
SELECT
	p.internal_name AS probe_internal_name,
	ARRAY['server_id', 'database_name']::text[] AS parameter_name_list,
	ARRAY[s.id::text, ocd.database_name]::text[] AS parameter_value_list,
	COALESCE(c.lifetime, p.default_lifetime) AS lifetime,
	p.discard_history
FROM
	pem.probe p
    CROSS JOIN pem.server s
	INNER JOIN oc_database ocd
		ON s.id = ocd.server_id
	LEFT JOIN pem.probe_config_database c
		ON p.id = c.probe_id AND s.id = c.server_id
		AND ocd.database_name = c.database_name
WHERE
	p.target_type_id = 300
	AND NOT s.active
	AND NOT p.deleted
	AND ocd.connections_allowed
UNION ALL
SELECT
	p.internal_name AS probe_internal_name,
	ARRAY['server_id', 'database_name', 'schema_name']::text[]
		AS parameter_name_list,
	ARRAY[s.id::text, oc.database_name, oc.schema_name]::text[]
		AS parameter_value_list,
	COALESCE(c.lifetime, p.default_lifetime) AS lifetime,
	p.discard_history
FROM
	pem.probe p
    CROSS JOIN pem.server s
	INNER JOIN oc_database ocd
		ON s.id = ocd.server_id
	INNER JOIN pemdata.oc_schema oc
		ON ocd.server_id = oc.server_id
		AND ocd.database_name = oc.database_name
	LEFT JOIN pem.probe_config_schema c
		ON p.id = c.probe_id AND s.id = c.server_id
		AND oc.database_name = c.database_name
		AND oc.schema_name = c.schema_name
WHERE
	p.target_type_id = 400
	AND NOT s.active
	AND NOT p.deleted
	AND ocd.connections_allowed
UNION ALL
SELECT
	p.internal_name AS probe_internal_name,
	ARRAY['server_id', 'database_name', 'schema_name', 'table_name']::text[]
		AS parameter_name_list,
	ARRAY[s.id::text, oc.database_name, oc.schema_name,
		oc.table_name]::text[] AS parameter_value_list,
	COALESCE(c.lifetime, p.default_lifetime) AS lifetime,
	p.discard_history
FROM
	pem.probe p
    CROSS JOIN pem.server s
	INNER JOIN oc_database ocd
		ON s.id = ocd.server_id
	INNER JOIN pemdata.oc_table oc
		ON ocd.server_id = oc.server_id
		AND ocd.database_name = oc.database_name
	LEFT JOIN pem.probe_config_table c
		ON p.id = c.probe_id AND s.id = c.server_id
		AND oc.database_name = c.database_name
		AND oc.schema_name = c.schema_name
		AND oc.table_name = c.table_name
WHERE
	p.target_type_id = 500
	AND NOT s.active
	AND NOT p.deleted
	AND ocd.connections_allowed
UNION ALL
SELECT
	p.internal_name AS probe_internal_name,
	ARRAY['server_id', 'database_name', 'schema_name', 'index_name']::text[]
		AS parameter_name_list,
	ARRAY[s.id::text, oc.database_name, oc.schema_name,
		oc.index_name]::text[] AS parameter_value_list,
	COALESCE(c.lifetime, p.default_lifetime) AS lifetime,
	p.discard_history
FROM
	pem.probe p
    CROSS JOIN pem.server s
	INNER JOIN oc_database ocd
		ON s.id = ocd.server_id
	INNER JOIN pemdata.oc_index oc
		ON ocd.server_id = oc.server_id
		AND ocd.database_name = oc.database_name
	LEFT JOIN pem.probe_config_index c
		ON p.id = c.probe_id AND s.id = c.server_id
		AND oc.database_name = c.database_name
		AND oc.schema_name = c.schema_name
		AND oc.index_name = c.index_name
WHERE
	p.target_type_id = 600
	AND NOT s.active
	AND NOT p.deleted
	AND ocd.connections_allowed
UNION ALL
SELECT
	p.internal_name AS probe_internal_name,
	ARRAY['server_id', 'database_name', 'schema_name', 'sequence_name']::text[]
		AS parameter_name_list,
	ARRAY[s.id::text, oc.database_name, oc.schema_name,
		oc.sequence_name]::text[] AS parameter_value_list,
	COALESCE(c.lifetime, p.default_lifetime) AS lifetime,
	p.discard_history
FROM
	pem.probe p
    CROSS JOIN pem.server s
	INNER JOIN oc_database ocd
		ON s.id = ocd.server_id
	INNER JOIN pemdata.oc_sequence oc
		ON ocd.server_id = oc.server_id
		AND ocd.database_name = oc.database_name
	LEFT JOIN pem.probe_config_sequence c
		ON p.id = c.probe_id AND s.id = c.server_id
		AND oc.database_name = c.database_name
		AND oc.schema_name = c.schema_name
		AND oc.sequence_name = c.sequence_name
WHERE
	p.target_type_id = 700
	AND NOT s.active
	AND NOT p.deleted
	AND ocd.connections_allowed
UNION ALL
SELECT
	p.internal_name AS probe_internal_name,
	ARRAY['server_id', 'database_name', 'schema_name', 'function_name']::text[]
		AS parameter_name_list,
	ARRAY[s.id::text, oc.database_name, oc.schema_name,
		oc.function_name]::text[] AS parameter_value_list,
	COALESCE(c.lifetime, p.default_lifetime) AS lifetime,
	p.discard_history
FROM
	pem.probe p
    CROSS JOIN pem.server s
	INNER JOIN oc_database ocd
		ON s.id = ocd.server_id
	INNER JOIN pemdata.oc_function oc
		ON ocd.server_id = oc.server_id
		AND ocd.database_name = oc.database_name
	LEFT JOIN pem.probe_config_function c
		ON p.id = c.probe_id AND s.id = c.server_id
		AND oc.database_name = c.database_name
		AND oc.schema_name = c.schema_name
		AND oc.function_name = c.function_name
WHERE
	p.target_type_id = 800
	AND NOT s.active
	AND NOT p.deleted
	AND ocd.connections_allowed
UNION ALL
SELECT
	p.internal_name AS probe_internal_name,
	ARRAY['server_id', 'database_name', 'schema_name', 'view_name']::text[]
		AS parameter_name_list,
	ARRAY[s.id::text, oc.database_name, oc.schema_name,
		oc.view_name]::text[] AS parameter_value_list,
	COALESCE(c.lifetime, p.default_lifetime) AS lifetime,
	p.discard_history
FROM
	pem.probe p
    CROSS JOIN pem.server s
	INNER JOIN oc_database ocd
		ON s.id = ocd.server_id
	INNER JOIN pemdata.oc_views oc
		ON ocd.server_id = oc.server_id
		AND ocd.database_name = oc.database_name
	LEFT JOIN pem.probe_config_view c
		ON p.id = c.probe_id AND s.id = c.server_id
		AND oc.database_name = c.database_name
		AND oc.schema_name = c.schema_name
		AND oc.view_name = c.view_name
WHERE
	p.target_type_id = 900
	AND NOT s.active
	AND NOT p.deleted
	AND ocd.connections_allowed;

-- Purge function to remove the data from pemhisotry for database objects
-- for which database has been deleted by user making the data in pemhistory obsolete
CREATE OR REPLACE FUNCTION pem.purge_obsolete_data()
  RETURNS void AS
$BODY$
DECLARE
    curs_probe CURSOR FOR
	SELECT probe_internal_name, parameter_name_list,
	   parameter_value_list, lifetime, discard_history
	FROM pem.probe_obsolete_target_view
	UNION ALL
	SELECT probe_internal_name, parameter_name_list,
	   parameter_value_list, lifetime, discard_history
	FROM pem.probe_deleted_target_view;

    table_name varchar;
    parameter_name_list text[];
    parameter_value_list text[];

    i integer; -- Counter
    where_clause varchar;

BEGIN

    FOR probe IN curs_probe LOOP
	IF (NOT probe.discard_history) THEN
		table_name := 'pemhistory.' || pg_catalog.quote_ident(probe.probe_internal_name);
		parameter_name_list := probe.parameter_name_list;
		parameter_value_list := probe.parameter_value_list;

		where_clause := 'WHERE ';

		FOR i IN array_lower(parameter_name_list, 1)..array_upper(parameter_name_list, 1)
		LOOP
		    IF (i != 1) THEN
		        where_clause := where_clause || ' AND ';
		    END IF;
			where_clause := where_clause || parameter_name_list[i] || ' = ' || pg_catalog.quote_literal(parameter_value_list[i]::text);
		END LOOP;

        -- Purge the data by deleting it
		EXECUTE 'DELETE FROM ' || table_name || ' ' || where_clause;
	END IF;
    END LOOP;

END;
$BODY$ LANGUAGE plpgsql;


DO
$$
DECLARE
	job_id integer;
	tmpid integer;
	serverid  integer := 1;
    dbname text:= current_database();
BEGIN
    -- Check if the job already exists.
    SELECT jobid INTO job_id FROM pem.job WHERE jobname = 'Database cleanup';
    IF FOUND THEN
        -- Check if the job step already exists.
        SELECT jstid INTO tmpid FROM pem.jobstep
            WHERE jstname = 'Obsolete database cleanup' AND jstjobid = job_id;

        IF (NOT FOUND) THEN
            -- Create obsolete data purging step.
            INSERT INTO pem.jobstep(
                jstjobid, jstname, jstenabled, jstdesc, jstkind, jstcode,
                server_id, database_name
            ) VALUES (
                job_id, 'Obsolete database cleanup', true,
                'This job step runs periodically to purge obsolete data from the database.',
                's', 'SELECT pem.purge_obsolete_data()',
                serverid, dbname
            );
        END IF;
    END IF;
END;
$$ LANGUAGE 'plpgsql';

DO $$
DECLARE
  tbl_oid OID;
BEGIN
	SELECT oid INTO tbl_oid FROM pg_catalog.pg_class
		WHERE relname = 'server_auth' AND relkind ='r' AND relnamespace::regnamespace::name = 'pem';

	IF FOUND THEN
		IF NOT EXISTS(
			SELECT attname FROM pg_catalog.pg_attribute
				WHERE attrelid = tbl_oid AND attname = 'use_gssapi'
		) THEN
			RAISE INFO 'Column (use_gssapi) not found in pem.server_auth table, adding now...';
			ALTER TABLE pem.server_auth
			ADD COLUMN use_gssapi boolean NOT NULL DEFAULT false;
                        COMMENT ON COLUMN pem.server_auth.use_gssapi IS 'Kerberos Authentication?';
		END IF;
	END IF;
END;
$$ LANGUAGE 'plpgsql';

ALTER POLICY pem_server_auth_select ON pem.server_auth
	USING (pem_user = current_user);

ALTER POLICY pem_server_auth_update ON pem.server_auth
	USING (
		pem_user = current_user OR
		pg_has_role('pem_admin', 'member'::text)
	)
	WITH CHECK (
		pem_user = current_user AND
		pg_has_role('pem_user', 'member'::text)
	);

-- JIRA: PEM-1032
--
-- Fixed the issue where pem.process_one_alert() was unable to continue if there was in any error
-- in inserting/updating alert detailed info or if any syntax error in the alert detailed info sql.
--
-- Function to execute detail alert info SQL and insert formatted string in pem.alert_status table.
CREATE OR REPLACE FUNCTION pem.get_detail_alert_info() RETURNS TRIGGER AS $$
DECLARE
	info_sql    text := '';
	a_agent_id  integer;
	a_server_id integer;
	a_database_name text:= '';
	a_schema_name text:= '';
	a_package_name text:= '';
	a_object_name text:= '';
	alert_info_str text:= '';
	comp_operator  text:= '';
	low_threshold_val text:= '';
	alert_params text[];
	info_sql_curs     REFCURSOR;
	info_sql_rec      RECORD;
	hs_row            RECORD;
	first_time    boolean := FALSE;
	arr_col_values text[];
	column_name text[] := ARRAY[]::text[];
	column_value text[] := ARRAY[]::text[];
	error_msg text:= '';
BEGIN
    IF (NEW.alert_id IS NOT NULL)
    THEN
        -- Fetch additional sql to execute from the alert template table.
        EXECUTE 'SELECT info_sql FROM pem.alert_template WHERE id = (SELECT template_id FROM pem.alert WHERE id = ' || NEW.alert_id || ')' INTO info_sql;

        EXECUTE 'SELECT operator::text FROM pem.alert WHERE id = ' || NEW.alert_id INTO comp_operator;

        EXECUTE 'SELECT thresholds[1]::text FROM pem.alert WHERE id = ' || NEW.alert_id INTO low_threshold_val;

        EXECUTE 'SELECT params::text[] FROM pem.alert WHERE id = ' || NEW.alert_id INTO alert_params;

        -- If additional information sql is null or empty then no need to get extra information.
        IF (info_sql IS NOT NULL AND info_sql != '' AND comp_operator IS NOT NULL AND comp_operator != '' AND
            low_threshold_val IS NOT NULL AND low_threshold_val != '') THEN
            -- Fist find the all the objects of this alert.
            EXECUTE 'SELECT agent_id FROM pem.alert WHERE id = ' || NEW.alert_id INTO a_agent_id;
            EXECUTE 'SELECT server_id FROM pem.alert WHERE id = ' || NEW.alert_id INTO a_server_id;
            EXECUTE 'SELECT database_name FROM pem.alert WHERE id = ' || NEW.alert_id INTO a_database_name;
            EXECUTE 'SELECT schema_name FROM pem.alert WHERE id = ' || NEW.alert_id INTO a_schema_name;
            EXECUTE 'SELECT package_name FROM pem.alert WHERE id = ' || NEW.alert_id INTO a_package_name;
            EXECUTE 'SELECT object_name FROM pem.alert WHERE id = ' || NEW.alert_id INTO a_object_name;

            -- Replace any reference to hierarchy-related alert parameters.
            info_sql = regexp_replace(info_sql, E'\\${agent_id}', COALESCE(a_agent_id::text, '')::text, 'g');
            info_sql = regexp_replace(info_sql, E'\\${server_id}', COALESCE(a_server_id::text, '')::text, 'g');
            info_sql = regexp_replace(info_sql, E'\\${database_name}', COALESCE(a_database_name, '')::text, 'g');
            info_sql = regexp_replace(info_sql, E'\\${schema_name}', COALESCE(a_schema_name, '')::text, 'g');
            info_sql = regexp_replace(info_sql, E'\\${package_name}', COALESCE(a_package_name, '')::text, 'g');
            info_sql = regexp_replace(info_sql, E'\\${object_name}', COALESCE(a_object_name, '')::text, 'g');
            info_sql = regexp_replace(info_sql, E'\\${comparison_operator}', COALESCE(comp_operator::text, '')::text, 'g');
            info_sql = regexp_replace(info_sql, E'\\${threshold_value}', COALESCE(low_threshold_val::text, '')::text, 'g');

            /* Replace ${param_n} with corresponding alert parameters */
            FOR i IN 1..COALESCE(array_upper(alert_params, 1), 0) LOOP
                info_sql = regexp_replace(info_sql, E'\\${param_' || i || '}', alert_params[i]::text, 'g');
            END LOOP;

            BEGIN
                OPEN info_sql_curs FOR EXECUTE info_sql;

                LOOP
                    FETCH NEXT FROM info_sql_curs INTO info_sql_rec;
                    EXIT WHEN NOT FOUND;

                    column_value := ARRAY[]::text[];

                    FOR hs_row IN SELECT kv."key", kv."value" FROM each(hstore(info_sql_rec::record)) kv
                    LOOP
                        alert_info_str := alert_info_str || COALESCE(hs_row."key", '') || ' = ' || COALESCE(hs_row."value", '') || E'\n';

                        IF first_time IS FALSE THEN
                            column_name := column_name || COALESCE(hs_row."key", '');
                        END IF;

                        column_value := column_value || COALESCE(hs_row."value", '');

                    END LOOP;

                    IF first_time IS FALSE THEN
                        arr_col_values := ARRAY[column_value]::text[];
                    ELSE
                        arr_col_values := arr_col_values || column_value;
                    END IF;

                    first_time := TRUE;
                    alert_info_str := alert_info_str || E'\n\n';

                END LOOP;
                CLOSE info_sql_curs;
            EXCEPTION
                WHEN OTHERS THEN
                    error_msg := 'Error while executing alert detailed information SQL: ' || SQLERRM;
                    RAISE LOG '%', error_msg; -- raise the error in DB server log file
                    -- We will also log the error in the alert status table which will make debugging issue easy
                    NEW.info_cols = ARRAY['ERROR_EXECUTING_ALERT_INFO']::text[];
                    NEW.info_vals = ARRAY[ARRAY[error_msg]::text[]]::text[];
                    NEW.info = NULL;
                    RETURN NEW;
            END;

            IF first_time IS FALSE THEN
                NEW.info_cols = NULL;
                NEW.info_vals = NULL;
                NEW.info = NULL;
            ELSE
                NEW.info_cols = column_name;
                NEW.info_vals = arr_col_values;

                IF (alert_info_str IS NOT NULL AND alert_info_str != '') THEN
                    NEW.info = alert_info_str;
                END IF;
            END IF;
        END IF;
  END IF;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Create a generic role for Kerberos/GSSAPI support
SELECT pem.create_generic_role('pem_gssapi');

-- PEM-3988
-- Fixed "A user expires in N days" alert template which is failing on postgres database
-- We need to update sql & info_sql column
UPDATE pem.alert_template
SET sql =  $SQL$
    SELECT
        ROUND(
            EXTRACT(
                EPOCH FROM (valuntil - capture_time)
            ) / 86400
        )::integer -- Diff divided by 86400 [86400: seconds in a Day]
    FROM
        pemdata.user_info
    WHERE	server_id = '${server_id}'
    AND		valuntil IS NOT NULL
    AND		valuntil NOT IN ('infinity','-infinity')
    AND		valuntil > capture_time
$SQL$,
info_sql =  $SQL$
    SELECT
        usename AS "Username",
        ROUND(
            EXTRACT(
                EPOCH FROM (valuntil - capture_time)
            ) / 86400
        )::integer AS "Days remaining for expiry", -- Diff divided by 86400 [86400: seconds in a Day]
        CASE WHEN usesuper = true THEN 'True' ELSE 'False' END AS "Is superuser?",
        valuntil AS "Account expires on"
    FROM
        pemdata.user_info
    WHERE	server_id = '${server_id}'
    AND		valuntil IS NOT NULL
    AND		valuntil NOT IN ('infinity','-infinity')
    AND		valuntil > capture_time
    GROUP BY usename, usesuper, valuntil, capture_time
    ORDER BY 2 ASC LIMIT 10;
$SQL$
WHERE id = 157 AND display_name = 'A user expires in N days';

-- Adding BDR Monitoring support
DO $DO$
BEGIN
	IF NOT EXISTS (SELECT id FROM pem.probe where internal_name = 'bdr_node_summary') THEN
		--
		-- BDR Node Summary Probe
		--
		INSERT INTO pem.probe
				(display_name, internal_name, collection_method, target_type_id,
				enabled_by_default, force_enabled, default_execution_frequency,
				default_lifetime, any_server_version, probe_code)
		VALUES
				('BDR Node Summary', 'bdr_node_summary', 's', 200, false, false, 60, 30, true,
				'SELECT node_name, node_group_name, peer_state_name, peer_target_state_name, sub_repsets FROM bdr.node_summary;');

		INSERT INTO pem.probe_column
				(probe_id, internal_name, display_name, display_position, classification,
				sql_data_type, unit_of_value, calculate_pit, discard_history, pit_by_default, is_graphable)
		SELECT
				(SELECT max(id) FROM pem.probe),
				v.internal_name, v.display_name, v.display_position, v.classification,
				v.sql_data_type, v.unit_of_value, v.calculate_pit, v.discard_history, v.pit_by_default, v.is_graphable
		FROM
				(VALUES
						('node_name',               'Node Name',               1, 'k', 'text',   '',   false, false, false, false),
						('node_group_name',         'Node Group Name',         2, 'm', 'text',   '',   false, false, false, false),
						('peer_state_name',         'Peer State Name',         3, 'm', 'text',   '',   false, false, false, false),
						('peer_target_state_name',  'Peer Target State Name',  4, 'm', 'text',   '',   false, false, false, false),
						('sub_repsets',             'Sub Repsets',             5, 'm', 'text[]', '',   false, false, false, false)
				) v(internal_name, display_name, display_position, classification,
						sql_data_type, unit_of_value, calculate_pit, discard_history, pit_by_default, is_graphable);
	END IF;
	IF NOT EXISTS (SELECT id FROM pem.probe where internal_name = 'bdr_node_replication_rates') THEN
	--
	-- BDR Node Replication Rates Probe
	--

	INSERT INTO pem.probe
			(display_name, internal_name, collection_method, target_type_id,
			enabled_by_default, force_enabled, default_execution_frequency,
			default_lifetime, any_server_version, probe_code)
	VALUES
			('BDR Node Replication Rates', 'bdr_node_replication_rates', 's', 200, false, false, 10, 30, true,
			'SELECT target_name, sent_lsn, replay_lsn,  EXTRACT(EPOCH FROM  replay_lag::INTERVAL)::decimal as replay_lag, replay_lag_bytes, 
			replay_lag_size, apply_rate, EXTRACT(EPOCH FROM  catchup_interval::INTERVAL)::decimal as catchup_interval FROM bdr.node_replication_rates;');

	INSERT INTO pem.probe_column
			(probe_id, internal_name, display_name, display_position, classification,
			sql_data_type, unit_of_value, calculate_pit, discard_history, pit_by_default, is_graphable)
	SELECT
			(SELECT max(id) FROM pem.probe),
			v.internal_name, v.display_name, v.display_position, v.classification,
			v.sql_data_type, v.unit_of_value, v.calculate_pit, v.discard_history, v.pit_by_default, v.is_graphable
	FROM
			(VALUES
					('target_name',       'Target name',      1, 'k', 'text',     '',   false, false, false, false),
					('sent_lsn',          'Sent LSN',         2, 'm', 'text',     '',   false, false, false, false),
					('replay_lsn',        'Replay LSN',       3, 'm', 'text',     '',   false, false, false, false),
					('replay_lag',        'Replay lag',       4, 'm', 'decimal',  '',   false, false, false, true),
					('replay_lag_bytes',  'Replay lag bytes', 5, 'm', 'numeric',  '',   false, false, false, true),
					('replay_lag_size',   'Replay lag size',  6, 'm', 'text',     '',   false, false, false, false),
					('apply_rate',        'Apply rates',      7, 'm', 'bigint',   '',   false, false, false, true),
					('catchup_interval',  'Catchup interval', 8, 'm', 'decimal',  '',   false, false, false, true)
			) v(internal_name, display_name, display_position, classification,
					sql_data_type, unit_of_value, calculate_pit, discard_history, pit_by_default, is_graphable);
	END IF;
	IF NOT EXISTS (SELECT id FROM pem.probe where internal_name = 'bdr_node_slots') THEN
	--
	-- BDR Node Slots Probe
	--

	INSERT INTO pem.probe
			(display_name, internal_name, collection_method, target_type_id,
			enabled_by_default, force_enabled, default_execution_frequency,
			default_lifetime, any_server_version, probe_code)
	VALUES
			('BDR Node Slots', 'bdr_node_slots', 's', 200, false, false, 10, 30, true,
			'SELECT slot_name, target_name, node_group_name, target_dbname, active_pid, catalog_xmin, client_addr,
			sent_lsn, replay_lsn, (EXTRACT(EPOCH FROM replay_lag::INTERVAL))::decimal as replay_lag, replay_lag_bytes,
			replay_lag_size FROM bdr.node_slots
			where slot_name != bdr.local_group_slot_name();');

	INSERT INTO pem.probe_column
			(probe_id, internal_name, display_name, display_position, classification,
			sql_data_type, unit_of_value, calculate_pit, discard_history, pit_by_default, is_graphable)
	SELECT
			(SELECT max(id) FROM pem.probe),
			v.internal_name, v.display_name, v.display_position, v.classification,
			v.sql_data_type, v.unit_of_value, v.calculate_pit, v.discard_history, v.pit_by_default, v.is_graphable
	FROM
			(VALUES
			('slot_name',       'Slot name',         1, 'k', 'text',    '',   false, false, false, false),
			('target_name',     'Target name',       2, 'm', 'text',    '',   false, false, false, false),
			('node_group_name', 'Node group name',   3, 'm', 'text',    '',   false, false, false, false),
			('target_dbname',   'Target DB name',    4, 'm', 'text',    '',   false, false, false, false),
			('active_pid',      'active PID',        5, 'm', 'integer', '',   false, false, false, false),
			('catalog_xmin',    'Catalog xmin',      6, 'm', 'text',    '',   false, false, false, false),
			('client_addr',     'Client address',    7, 'm', 'text',    '',   false, false, false, false),
			('sent_lsn',        'Sent LSN',          8, 'm', 'text',    '',   false, false, false, false),
			('replay_lsn',      'Replay LSN',        9, 'm', 'text',    '',   false, false, false, false),
			('replay_lag',      'Replay lag',       10, 'm', 'decimal',  '',   false, false, false, true),
			('replay_lag_bytes','Replay lag bytes', 11, 'm', 'numeric', '',   false, false, false, true),
			('replay_lag_size', 'Replay lag size',  12, 'm', 'text',    '',   false, false, false, false)
			) v(internal_name, display_name, display_position, classification,
					sql_data_type, unit_of_value, calculate_pit, discard_history, pit_by_default, is_graphable);
	END IF;
	IF NOT EXISTS (SELECT id FROM pem.probe where internal_name = 'bdr_group_subscription_summary') THEN
	--
	-- BDR Group Subscription Summary
	--

	INSERT INTO pem.probe
			(display_name, internal_name, collection_method, target_type_id,
			enabled_by_default, force_enabled, default_execution_frequency,
			default_lifetime, any_server_version, probe_code)
	VALUES
			('BDR Group Subscription Summary', 'bdr_group_subscription_summary', 's', 200, false, false, 10, 30, true,
			'select origin_node_name, target_node_name, last_xact_replay_timestamp, sub_lag_seconds from bdr.group_subscription_summary;');

	INSERT INTO pem.probe_column
			(probe_id, internal_name, display_name, display_position, classification,
			sql_data_type, unit_of_value, calculate_pit, discard_history, pit_by_default, is_graphable)
	SELECT
			(SELECT max(id) FROM pem.probe),
			v.internal_name, v.display_name, v.display_position, v.classification,
			v.sql_data_type, v.unit_of_value, v.calculate_pit, v.discard_history, v.pit_by_default, v.is_graphable
	FROM
			(VALUES
			('origin_node_name',           'Origin node Name',            1, 'k', 'text',    '',   false, false, false, false),
			('target_node_name',           'Target node Name',            2, 'k', 'text',    '',   false, false, false, false),
			('last_xact_replay_timestamp', 'Last exact replay timestamp', 3, 'm', 'text',    '',   false, false, false, false),
			('sub_lag_seconds',            'Subscription lag in seconds', 4, 'm', 'decimal', '',   false, false, false, true)
			) v(internal_name, display_name, display_position, classification,
					sql_data_type, unit_of_value, calculate_pit, discard_history, pit_by_default, is_graphable);

	END IF;
	IF NOT EXISTS (SELECT id FROM pem.probe where internal_name = 'bdr_group_versions_details') THEN
	--
	-- BDR Versions Details
	--
	INSERT INTO pem.probe
			(display_name, internal_name, collection_method, target_type_id,
			enabled_by_default, force_enabled, default_execution_frequency,
			default_lifetime, any_server_version, probe_code)
	VALUES
			('BDR Group Versions Details', 'bdr_group_versions_details', 's', 200, false, false, 86400, 30, true,
			'SELECT node_name, postgres_version, pglogical_version, bdr_version, bdr_edition FROM bdr.group_versions_details;');

	INSERT INTO pem.probe_column
			(probe_id, internal_name, display_name, display_position, classification,
			sql_data_type, unit_of_value, calculate_pit, discard_history, pit_by_default, is_graphable)
	SELECT
			(SELECT max(id) FROM pem.probe),
			v.internal_name, v.display_name, v.display_position, v.classification,
			v.sql_data_type, v.unit_of_value, v.calculate_pit, v.discard_history, v.pit_by_default, v.is_graphable
	FROM
			(VALUES
			('node_name',           'Node Name',           1, 'k', 'text',    '',   false, false, false, false),
			('postgres_version',    'Postgres Name',       2, 'm', 'text',    '',   false, false, false, false),
			('pglogical_version',   'PG Logical version',  3, 'm', 'text',    '',   false, false, false, false),
			('bdr_version',         'BDR Version',         4, 'm', 'text',    '',   false, false, false, false),
			('bdr_edition',         'BDR Edition',         5, 'm', 'text',    '',   false, false, false, false)
			) v(internal_name, display_name, display_position, classification,
					sql_data_type, unit_of_value, calculate_pit, discard_history, pit_by_default, is_graphable);

	END IF;
	IF NOT EXISTS (SELECT id FROM pem.probe where internal_name = 'bdr_monitor_group_versions') THEN
	--
	-- BDR Versions Status
	--

	INSERT INTO pem.probe
			(display_name, internal_name, collection_method, target_type_id,
			enabled_by_default, force_enabled, default_execution_frequency,
			default_lifetime, any_server_version, probe_code)
	VALUES
			('BDR Monitor Group Versions', 'bdr_monitor_group_versions', 's', 200, false, false, 86400, 30, true,
			'SELECT status, message FROM bdr.monitor_group_versions();');

	INSERT INTO pem.probe_column
			(probe_id, internal_name, display_name, display_position, classification,
			sql_data_type, unit_of_value, calculate_pit, discard_history, pit_by_default, is_graphable)
	SELECT
			(SELECT max(id) FROM pem.probe),
			v.internal_name, v.display_name, v.display_position, v.classification,
			v.sql_data_type, v.unit_of_value, v.calculate_pit, v.discard_history, v.pit_by_default, v.is_graphable
	FROM
			(VALUES
			('status',  'Status',  1, 'm', 'text',    '',   false, false, false, false),
			('message', 'Message', 2, 'm', 'text',    '',   false, false, false, false)
			) v(internal_name, display_name, display_position, classification,
					sql_data_type, unit_of_value, calculate_pit, discard_history, pit_by_default, is_graphable);

	END IF;
	IF NOT EXISTS (SELECT id FROM pem.probe where internal_name = 'bdr_group_raft_details') THEN
	--
	-- BDR Group Raft Details
	--
	INSERT INTO pem.probe
			(display_name, internal_name, collection_method, target_type_id,
			enabled_by_default, force_enabled, default_execution_frequency,
			default_lifetime, any_server_version, probe_code)
	VALUES
			('BDR Group Raft Details', 'bdr_group_raft_details', 's', 200, false, false, 60, 30, true,
			'select node_name, state, leader_id, current_term, commit_index from bdr.group_raft_details;');

	INSERT INTO pem.probe_column
			(probe_id, internal_name, display_name, display_position, classification,
			sql_data_type, unit_of_value, calculate_pit, discard_history, pit_by_default, is_graphable)
	SELECT
			(SELECT max(id) FROM pem.probe),
			v.internal_name, v.display_name, v.display_position, v.classification,
			v.sql_data_type, v.unit_of_value, v.calculate_pit, v.discard_history, v.pit_by_default, v.is_graphable
	FROM
			(VALUES
			('node_name',    'Node Name',    1, 'k', 'text',    '',   false, false, false, false),
			('state',        'State',        2, 'm', 'text',    '',   false, false, false, false),
			('leader_id',    'Leader ID',    3, 'm', 'text',    '',   false, false, false, false),
			('current_term', 'Current Term', 4, 'm', 'text',    '',   false, false, false, false),
			('commit_index', 'Commit Index', 5, 'm', 'text',    '',   false, false, false, false)
			) v(internal_name, display_name, display_position, classification,
					sql_data_type, unit_of_value, calculate_pit, discard_history, pit_by_default, is_graphable);

	END IF;
	IF NOT EXISTS (SELECT id FROM pem.probe where internal_name = 'bdr_monitor_group_raft') THEN

	--
	-- BDR Group Raft Status
	--
	INSERT INTO pem.probe
			(display_name, internal_name, collection_method, target_type_id,
			enabled_by_default, force_enabled, default_execution_frequency,
			default_lifetime, any_server_version, probe_code)
	VALUES
			('BDR Monitor Group Raft Status', 'bdr_monitor_group_raft', 's', 200, false, false, 60, 30, true,
			'SELECT status, message FROM bdr.monitor_group_raft();');

	INSERT INTO pem.probe_column
			(probe_id, internal_name, display_name, display_position, classification,
			sql_data_type, unit_of_value, calculate_pit, discard_history, pit_by_default, is_graphable)
	SELECT
			(SELECT max(id) FROM pem.probe),
			v.internal_name, v.display_name, v.display_position, v.classification,
			v.sql_data_type, v.unit_of_value, v.calculate_pit, v.discard_history, v.pit_by_default, v.is_graphable
	FROM
			(VALUES
			('status',  'Status',  1, 'm', 'text',    '',   false, false, false, false),
			('message', 'Message', 2, 'm', 'text',    '',   false, false, false, false)
			) v(internal_name, display_name, display_position, classification,
					sql_data_type, unit_of_value, calculate_pit, discard_history, pit_by_default, is_graphable);

	END IF;
	IF NOT EXISTS (SELECT id FROM pem.probe where internal_name = 'bdr_group_replslots_details') THEN

	--
	-- BDR Replication Slots Details
	--
	INSERT INTO pem.probe
			(display_name, internal_name, collection_method, target_type_id,
			enabled_by_default, force_enabled, default_execution_frequency,
			default_lifetime, any_server_version, probe_code)
	VALUES
			('BDR Group Replication Slots Details', 'bdr_group_replslots_details', 's', 200, false, false, 60, 30, true,
			'select node_group_name, origin_name, target_name, slot_name, active, state, 
			(EXTRACT(EPOCH FROM write_lag::INTERVAL))::decimal as write_lag, (EXTRACT(EPOCH FROM flush_lag::INTERVAL))::decimal as flush_lag,
			(EXTRACT(EPOCH FROM replay_lag::INTERVAL))::decimal as replay_lag, 
			sent_lag_bytes::numeric, write_lag_bytes::numeric, flush_lag_bytes::numeric, replay_lag_bytes::numeric 
			from bdr.group_replslots_details;');

	INSERT INTO pem.probe_column
			(probe_id, internal_name, display_name, display_position, classification,
			sql_data_type, unit_of_value, calculate_pit, discard_history, pit_by_default, is_graphable)
	SELECT
			(SELECT max(id) FROM pem.probe),
			v.internal_name, v.display_name, v.display_position, v.classification,
			v.sql_data_type, v.unit_of_value, v.calculate_pit, v.discard_history, v.pit_by_default, v.is_graphable
	FROM
			(VALUES
				('node_group_name',   'Node group name',   1, 'm', 'text',     '',   false, false, false, false),
				('origin_name',       'Origin name',       2, 'k', 'text',     '',   false, false, false, false),
				('target_name',       'Target name',       3, 'm', 'text',     '',   false, false, false, false),
				('slot_name',         'Slot name',         4, 'k', 'text',     '',   false, false, false, false),
				('active',            'Active',            5, 'm', 'text',     '',   false, false, false, false),
				('state',             'State',             6, 'm', 'text',     '',   false, false, false, false),
				('write_lag',         'Write lag',         7, 'm', 'decimal',  '',   false, false, false, true),
				('flush_lag',         'Flush lag',         8, 'm', 'decimal',  '',   false, false, false, true),
				('replay_lag',        'Replay lag',        9, 'm', 'decimal',  '',   false, false, false, true),
				('sent_lag_bytes',    'Sent lag bytes',   10, 'm', 'numeric', '',   false, false, false, true),
				('write_lag_bytes',   'Write lag bytes',  11, 'm', 'numeric', '',   false, false, false, true),
				('flush_lag_bytes',   'Flush lag bytes',  12, 'm', 'numeric', '',   false, false, false, true),
				('replay_lag_bytes',  'Replay lag bytes', 13, 'm', 'numeric', '',   false, false, false, true)
			) v(internal_name, display_name, display_position, classification,
					sql_data_type, unit_of_value, calculate_pit, discard_history, pit_by_default, is_graphable);

	END IF;
	IF NOT EXISTS (SELECT id FROM pem.probe where internal_name = 'bdr_workers') THEN
	--
	-- BDR Workers
	--
	INSERT INTO pem.probe
			(display_name, internal_name, collection_method, target_type_id,
			enabled_by_default, force_enabled, default_execution_frequency,
			default_lifetime, any_server_version, probe_code)
	VALUES
			('BDR Workers', 'bdr_workers', 's', 200, false, false, 60, 30, true,
			'SELECT pid as worker_pid, query_start, state_change, wait_event_type, wait_event, state, worker_role_name,
			worker_commit_timestamp, worker_local_timestamp, origin_name, receive_lsn, receive_commit_lsn, last_xact_replay_lsn,
			last_xact_flush_lsn, last_xact_replay_timestamp, query
			FROM bdr.stat_activity a, bdr.workers w, bdr.subscription_summary ss
			where a.pid = w.worker_pid and w.worker_subid = ss.sub_id
			ORDER BY a.pid;');

	INSERT INTO pem.probe_column
			(probe_id, internal_name, display_name, display_position, classification,
			sql_data_type, unit_of_value, calculate_pit, discard_history, pit_by_default, is_graphable)
	SELECT
			(SELECT max(id) FROM pem.probe),
			v.internal_name, v.display_name, v.display_position, v.classification,
			v.sql_data_type, v.unit_of_value, v.calculate_pit, v.discard_history, v.pit_by_default, v.is_graphable
	FROM
			(VALUES
				('worker_pid',                    'Worker PID',                          1, 'k', 'integer',  '',   false, false, false, false),
				('query_start',                   'Query start',                         2, 'm', 'timestamp',  '',   false, false, false, false),
				('state_change',                  'State change',                        3, 'm', 'timestamp',  '',   false, false, false, false),
				('wait_event_type',               'Wait event type',                     4, 'm', 'text',  '',   false, false, false, false),
				('wait_event',                    'Wait event',                          5, 'm', 'text',  '',   false, false, false, false),
				('state',                         'State',                               6, 'm', 'text',  '',   false, false, false, false),
				('worker_role_name',              'Worker role name',                    7, 'm', 'text',  '',   false, false, false, false),
				('worker_commit_timestamp',       'Worker commit timestamp',             8, 'm', 'timestamp',  '',   false, false, false, false),
				('worker_local_timestamp',        'Worker local timestamp',              9, 'm', 'timestamp',  '',   false, false, false, false),
				('origin_name',                   'Origin name',                        10, 'm', 'text',  '',   false, false, false, false),
				('receive_lsn',                   'Receive LSN',                        11, 'm', 'text',  '',   false, false, false, false),
				('receive_commit_lsn',            'Receive commit LSN',                 12, 'm', 'text', '',   false, false, false, false),
				('last_xact_replay_lsn',          'Last xact replay LSN',               13, 'm', 'text', '',   false, false, false, false),
				('last_xact_flush_lsn',           'Last xact flush LSN',                14, 'm', 'text', '',   false, false, false, false),
				('last_xact_replay_timestamp',    'Last xact replay timestamp',         15, 'm', 'timestamp', '',   false, false, false, false),
				('query',                         'Query',                              16, 'm', 'text', '',   false, false, false, false)
			) v(internal_name, display_name, display_position, classification,
					sql_data_type, unit_of_value, calculate_pit, discard_history, pit_by_default, is_graphable);

	END IF;
	IF NOT EXISTS (SELECT id FROM pem.probe where internal_name = 'bdr_worker_errors') THEN
	--
	-- BDR Worker Errors
	--
	INSERT INTO pem.probe
			(display_name, internal_name, collection_method, target_type_id,
			enabled_by_default, force_enabled, default_execution_frequency,
			default_lifetime, any_server_version, probe_code)
	VALUES
			('BDR Worker Errors', 'bdr_worker_errors', 's', 200, false, false, 15, 30, true,
			'select worker_pid, node_group_name, origin_name, source_name, target_name, sub_name, worker_role, worker_role_name, error_time,
			error_age, error_message, error_context_message, remoterelid, subwriter_id, subwriter_name from bdr.worker_errors;');

	INSERT INTO pem.probe_column
			(probe_id, internal_name, display_name, display_position, classification,
			sql_data_type, unit_of_value, calculate_pit, discard_history, pit_by_default, is_graphable)
	SELECT
			(SELECT max(id) FROM pem.probe),
			v.internal_name, v.display_name, v.display_position, v.classification,
			v.sql_data_type, v.unit_of_value, v.calculate_pit, v.discard_history, v.pit_by_default, v.is_graphable
	FROM
			(VALUES
				('worker_pid',            'Worker PID',                1, 'k', 'integer',   '',   false, false, false, false),
				('node_group_name',       'Node group name',           2, 'm', 'text',      '',   false, false, false, false),
				('origin_name',           'Origin name',               3, 'm', 'text',      '',   false, false, false, false),
				('source_name',           'Source name',               4, 'm', 'text',      '',   false, false, false, false),
				('target_name',           'Target name',               5, 'm', 'text',      '',   false, false, false, false),
				('sub_name',              'Subscription name',         6, 'm', 'text',      '',   false, false, false, false),
				('worker_role',           'Worker role',               7, 'm', 'text',      '',   false, false, false, false),
				('worker_role_name',      'Worker role name',          8, 'm', 'text',      '',   false, false, false, false),
				('error_time',            'Error time',                9, 'm', 'timestamptz', '',   false, false, false, false),
				('error_age',             'Error age',                10, 'm', 'interval',   '', false, false, false, false),
				('error_message',         'Error message',            11, 'm', 'text',      '',   false, false, false, false),
				('error_context_message', 'Error context message',    12, 'm', 'text',      '',   false, false, false, false),
				('remoterelid',           'Remote relation ID',       13, 'm', 'text',      '',   false, false, false, false),
				('subwriter_id',          'Subscription writer ID',   14, 'm', 'text',      '',   false, false, false, false),
				('subwriter_name',        'Subscription writer name', 15, 'm', 'text',      '',   false, false, false, false)
			) v(internal_name, display_name, display_position, classification,
					sql_data_type, unit_of_value, calculate_pit, discard_history, pit_by_default, is_graphable);

	END IF;
	IF NOT EXISTS (SELECT id FROM pem.probe where internal_name = 'bdr_global_locks') THEN

	--
	-- BDR Global Locks
	--

	INSERT INTO pem.probe
			(display_name, internal_name, collection_method, target_type_id,
			enabled_by_default, force_enabled, default_execution_frequency,
			default_lifetime, any_server_version, probe_code)
	VALUES
			('BDR Global Locks', 'bdr_global_locks', 's', 200, false, false, 60, 30, true,
			'select origin_node_name, pid, origin_node_id, lock_type, relation, acquire_stage, waiters, 
			global_lock_request_time, local_lock_request_time, last_state_change_time from bdr.global_locks;');

	INSERT INTO pem.probe_column
			(probe_id, internal_name, display_name, display_position, classification,
			sql_data_type, unit_of_value, calculate_pit, discard_history, pit_by_default, is_graphable)
	SELECT
			(SELECT max(id) FROM pem.probe),
			v.internal_name, v.display_name, v.display_position, v.classification,
			v.sql_data_type, v.unit_of_value, v.calculate_pit, v.discard_history, v.pit_by_default, v.is_graphable
	FROM
			(VALUES
				('origin_node_name',        'Origin node name',         1, 'k', 'text',       '',   false, false, false, false),
				('pid',                     'PID',                      2, 'k', 'integer',    '',   false, false, false, false),
				('origin_node_id',          'Origin node ID',           3, 'm', 'text',       '',   false, false, false, false),
				('lock_type',               'Lock type',                4, 'm', 'text',       '',   false, false, false, false),
				('relation',                'Relation',                 5, 'm', 'text',       '',   false, false, false, false),
				('acquire_stage',           'Acquire stage',            6, 'm', 'text',       '',   false, false, false, false),
				('waiters',                 'Waiters',                  7, 'm', 'text',       '',   false, false, false, false),
				('global_lock_request_time','Global lock request time', 8, 'm', 'timestamp',  '',   false, false, false, false),
				('local_lock_request_time', 'Local lock request time',  9, 'm', 'timestamp',  '',   false, false, false, false),
				('last_state_change_time',  'Last state change time',  10, 'm', 'timestamp',  '',   false, false, false, false)
			) v(internal_name, display_name, display_position, classification,
					sql_data_type, unit_of_value, calculate_pit, discard_history, pit_by_default, is_graphable);


	END IF;
	IF NOT EXISTS (SELECT id FROM pem.probe where internal_name = 'bdr_conflict_history_summary') THEN

	--
	-- BDR Conflicts History Summary
	--
	INSERT INTO pem.probe
			(display_name, internal_name, collection_method, target_type_id,
			enabled_by_default, force_enabled, default_execution_frequency,
			default_lifetime, any_server_version, probe_code, discard_history)
	VALUES
			('BDR Conflict History Summary', 'bdr_conflict_history_summary', 's', 200, false, false, 60, 7, true,
			$sql$
			select EXTRACT(EPOCH FROM date_trunc('hour', local_time at time zone 'UTC')) as conflict_recorded,
			conflict_type, count(*) as conflict_count
			from bdr.conflict_history_summary
			group by date_trunc('hour', local_time at time zone 'UTC'), conflict_type
			order by conflict_recorded, conflict_type;
			$sql$, true);


	INSERT INTO pem.probe_column
			(probe_id, internal_name, display_name, display_position, classification,
			sql_data_type, unit_of_value, calculate_pit, discard_history, pit_by_default, is_graphable)
	SELECT
			(SELECT max(id) FROM pem.probe),
			v.internal_name, v.display_name, v.display_position, v.classification,
			v.sql_data_type, v.unit_of_value, v.calculate_pit, v.discard_history, v.pit_by_default, v.is_graphable
	FROM
			(VALUES
					('conflict_recorded',    'Conflict Recorded',     1, 'k', 'bigint',  '',   false, false, false, false),
					('conflict_type',        'Conflict Type',         2, 'k', 'text',  '',   false, false, false, false),
					('conflict_count',       'Conflict Count',        3, 'm', 'bigint',  '',   false, false, false, false)
			) v(internal_name, display_name, display_position, classification,
					sql_data_type, unit_of_value, calculate_pit, discard_history, pit_by_default, is_graphable);

	END IF;
	IF NOT EXISTS (SELECT id FROM pem.probe where internal_name = 'bdr_group_camo_details') THEN

	--
	-- BDR Group Camo Details
	--

	INSERT INTO pem.probe
			(display_name, internal_name, collection_method, target_type_id,
			enabled_by_default, force_enabled, default_execution_frequency,
			default_lifetime, any_server_version, probe_code)
	VALUES
			('BDR Group Camo Details', 'bdr_group_camo_details', 's', 200, false, false, 60, 30, true,
			'SELECT node_name, camo_partner_of, camo_origin_for, is_camo_partner_connected, is_camo_partner_ready,
			camo_transactions_resolved, apply_lsn, receive_lsn, apply_queue_size from bdr.group_camo_details;');

	INSERT INTO pem.probe_column
			(probe_id, internal_name, display_name, display_position, classification,
			sql_data_type, unit_of_value, calculate_pit, discard_history, pit_by_default, is_graphable)
	SELECT
			(SELECT max(id) FROM pem.probe),
			v.internal_name, v.display_name, v.display_position, v.classification,
			v.sql_data_type, v.unit_of_value, v.calculate_pit, v.discard_history, v.pit_by_default, v.is_graphable
	FROM
			(VALUES
				('node_name',                   'Node name',                  1, 'k', 'text',  '',   false, false, false, false),
				('camo_partner_of',             'Camo partner of',            2, 'k', 'text',  '',   false, false, false, false),
				('camo_origin_for',             'Camo origin for',            3, 'm', 'text',  '',   false, false, false, false),
				('is_camo_partner_connected',   'Is camo partner connected?', 4, 'm', 'text',  '',   false, false, false, false),
				('is_camo_partner_ready',       'Is camo partner ready?',     5, 'm', 'text',  '',   false, false, false, false),
				('camo_transactions_resolved',  'Camo transactions resolved', 6, 'm', 'text',  '',   false, false, false, false),
				('apply_lsn',                   'Apply LSN',                  7, 'm', 'text',  '',   false, false, false, false),
				('receive_lsn',                 'Receive LSN',                8, 'm', 'text',  '',   false, false, false, false),
				('apply_queue_size',            'Apply queue size',           9, 'm', 'text',  '',   false, false, false, false)
			) v(internal_name, display_name, display_position, classification,
					sql_data_type, unit_of_value, calculate_pit, discard_history, pit_by_default, is_graphable);

	END IF;
	PERFORM pem.create_data_and_history_tables();


	INSERT INTO pem.chart_category(id, name, descp, owner) VALUES
		(16, 'BDR Node Monitoring', 'Charts render on the BDR Node Monitoring dashboard', 0),
		(17, 'BDR Group Monitoring', 'Charts render on the BDR Group Monitoring dashboard', 0),
		(18, 'BDR Admin', 'Charts render on the BDR Admin dashboard', 0) ON CONFLICT DO NOTHING;

	--
	-- BDR Node Replication Lag (Seconds)
	--
	INSERT INTO pem.chart(id, cid, fid, type, level, name, owner, shared, ref_cnt, reload, summary, labels, params, rwlimit_span_param, ref_timeout_param) VALUES
	(90, 16,  NULL,  'L', ARRAY[200], 'BDR Node Replication Lag (Seconds)',   0, NULL, 1, 50000,   NULL, NULL, NULL, '', '')  ON CONFLICT DO NOTHING;

	INSERT INTO pem.line_chart (cid, type, yaxis) VALUES (90, 'M', 'Lag (Seconds)') ON CONFLICT DO NOTHING;
	INSERT INTO pem.metrices_chart (cid, time_span) VALUES (90, '14 days'::interval)  ON CONFLICT DO NOTHING;
	INSERT INTO pem.chart_metric (cid, mid, tbl, metrices, glimit, agg_func, params) VALUES
		(90, 1, 'bdr_node_replication_rates', ARRAY['replay_lag'], 32,
		ARRAY['M'], NULL)  ON CONFLICT DO NOTHING;

	--
	-- BDR Node Replication Lag (Bytes)
	--
	INSERT INTO pem.chart(id, cid, fid, type, level, name, owner, shared, ref_cnt, reload, summary, labels, params, rwlimit_span_param, ref_timeout_param) VALUES
	(91, 16,  NULL,  'L', ARRAY[200], 'BDR Node Replication Lag (Bytes)',   0, NULL, 1, 50000,   NULL, NULL, NULL, '', '')  ON CONFLICT DO NOTHING;

	INSERT INTO pem.line_chart (cid, type, yaxis) VALUES (91, 'M', 'Lag (Bytes)')  ON CONFLICT DO NOTHING;
	INSERT INTO pem.metrices_chart (cid, time_span) VALUES (91, '14 days'::interval)  ON CONFLICT DO NOTHING;
	INSERT INTO pem.chart_metric (cid, mid, tbl, metrices, glimit, agg_func, params) VALUES
		(91, 1, 'bdr_node_replication_rates', ARRAY['replay_lag_bytes'], 32,
		ARRAY['M'], NULL)  ON CONFLICT DO NOTHING;

	--
	-- BDR Node Replication Apply Rates
	--
	INSERT INTO pem.chart(id, cid, fid, type, level, name, owner, shared, ref_cnt, reload, summary, labels, params, rwlimit_span_param, ref_timeout_param) VALUES
	(92, 16,  NULL,  'L', ARRAY[200], 'BDR Node Replication Apply Rates',   0, NULL, 1, 50000,   NULL, NULL, NULL, '', '')  ON CONFLICT DO NOTHING;

	INSERT INTO pem.line_chart (cid, type, yaxis) VALUES (92, 'M', 'Apply Rates')  ON CONFLICT DO NOTHING;
	INSERT INTO pem.metrices_chart (cid, time_span) VALUES (92, '14 days'::interval)  ON CONFLICT DO NOTHING;
	INSERT INTO pem.chart_metric (cid, mid, tbl, metrices, glimit, agg_func, params) VALUES
		(92, 1, 'bdr_node_replication_rates', ARRAY['apply_rate'], 32,
		ARRAY['M'], NULL)  ON CONFLICT DO NOTHING;

	--
	-- BDR Node Slot Replay Lag (Seconds)
	--
	INSERT INTO pem.chart(id, cid, fid, type, level, name, owner, shared, ref_cnt, reload, summary, labels, params, rwlimit_span_param, ref_timeout_param) VALUES
	(93, 16,  NULL,  'L', ARRAY[200], 'BDR Node Slot Replay Lag (Seconds)',   0, NULL, 1, 50000,   NULL, NULL, NULL, '', '')  ON CONFLICT DO NOTHING;

	INSERT INTO pem.line_chart (cid, type, yaxis) VALUES (93, 'M', 'Lag (Seconds)')  ON CONFLICT DO NOTHING;
	INSERT INTO pem.metrices_chart (cid, time_span) VALUES (93, '14 days'::interval)  ON CONFLICT DO NOTHING;
	INSERT INTO pem.chart_metric (cid, mid, tbl, metrices, glimit, agg_func, params) VALUES
		(93, 1, 'bdr_node_slots', ARRAY['replay_lag'], 32,
		ARRAY['M'], NULL)  ON CONFLICT DO NOTHING;

	--
	-- BDR Node Slot Replay Lag (Bytes)
	--
	INSERT INTO pem.chart(id, cid, fid, type, level, name, owner, shared, ref_cnt, reload, summary, labels, params, rwlimit_span_param, ref_timeout_param) VALUES
	(94, 16,  NULL,  'L', ARRAY[200], 'BDR Node Slot Replay Lag (Bytes)',   0, NULL, 1, 50000,   NULL, NULL, NULL, '', '')  ON CONFLICT DO NOTHING;

	INSERT INTO pem.line_chart (cid, type, yaxis) VALUES (94, 'M', 'Lag (Bytes)')  ON CONFLICT DO NOTHING;
	INSERT INTO pem.metrices_chart (cid, time_span) VALUES (94, '14 days'::interval)  ON CONFLICT DO NOTHING;
	INSERT INTO pem.chart_metric (cid, mid, tbl, metrices, glimit, agg_func, params) VALUES
		(94, 1, 'bdr_node_slots', ARRAY['replay_lag_bytes'], 32,
		ARRAY['M'], NULL)  ON CONFLICT DO NOTHING;

	--
	-- BDR Conflict History Summary
	--
	CREATE OR REPLACE FUNCTION pem.generate_bdr_conflict_history_chart_data(
		p_cid integer, p_did integer, p_sid integer, p_stime timestamptz, p_etime timestamptz
	) RETURNS TABLE(
		o_idx int2, o_label text, o_aggtime bigint, o_aggval bigint
	) AS $$
	DECLARE
		v_span      interval;
		v_time      timestamptz;
		v_stime     timestamptz;
		v_etime     timestamptz;
		v_hbtime    timestamptz;
		v_tzdiff    int2;
		v_minute    int2;
	BEGIN
		v_time := now();
		SELECT max(last_heartbeat) INTO v_hbtime FROM pem.server_heartbeat WHERE server_id = p_sid;
	-- Ignoring the number of points for this chart
	EXECUTE '
	SELECT
		span
	FROM
		(SELECT
			CASE
			WHEN cfg.did = -1 THEN
				CASE
				WHEN cfg.objid IS NULL THEN 1::integer
				WHEN $3::integer IS NOT NULL AND cfg.objid = $3::integer
					THEN 2::integer
				END
			ELSE
				CASE
				WHEN cfg.objid IS NULL THEN 6::integer
				WHEN $3::integer IS NOT NULL AND cfg.objid = $3::integer
					THEN 7::integer
				END
			END AS lvl,
			(cfg.span * ''1 hours''::interval) as span
		FROM
			pem.chart_config cfg
		WHERE
			cfg.cid = $1::integer AND (
				(cfg.did = -1 AND cfg.level <= COALESCE(
						(SELECT level FROM pem.dashboard WHERE id=$2::integer),
						CASE WHEN $1::integer = 55 THEN 200 ELSE 300 END
					)) OR
				($2::integer IS NOT NULL AND cfg.did = $2::integer)
			) AND cfg.uid = (
				SELECT u.usesysid FROM pg_catalog.pg_user u
					WHERE u.usename = current_user
			)
		) config
	ORDER BY lvl DESC NULLS LAST
	LIMIT 1' USING p_cid, p_did, p_sid INTO v_span;
		IF v_span IS NULL THEN
			v_span = '7 days'::interval;
		END IF;
		IF p_stime IS NULL OR p_etime IS NULL OR p_stime >= p_etime THEN
			v_stime := v_time - v_span;
			v_etime := v_time;
			IF v_hbtime IS NOT NULL THEN
				v_etime := v_hbtime;
			END IF;
		ELSE
			v_stime := p_stime;
			v_etime := p_etime;
			IF v_stime >= v_etime THEN
				RETURN;
			END IF;
			IF v_etime > v_hbtime THEN
				v_etime := v_hbtime;
			ELSIF v_etime > v_time THEN
				v_etime := v_time;
			END IF;
		END IF;

	EXECUTE $SQL$
	SELECT min(to_timestamp(conflict_recorded)), EXTRACT('minute' FROM min(to_timestamp(conflict_recorded))) FROM pemdata.bdr_conflict_history_summary
	WHERE server_id = $1::integer
	$SQL$ INTO v_time, v_minute USING p_sid;
	IF v_time IS NULL THEN
        RETURN;
    END IF;
	EXECUTE $sql$
	SELECT date_trunc('hour', $1::timestamptz at time zone 'UTC'), date_trunc('hour', $2::timestamptz at time zone 'UTC')
	$sql$ INTO v_stime, v_etime USING v_stime, v_etime;
	
	SELECT EXTRACT('minute' FROM v_stime)::int2 INTO v_tzdiff;
	v_tzdiff := v_minute - v_tzdiff;
	v_stime := v_stime + (v_tzdiff::text || ' minutes')::interval;
	v_etime := v_etime + (v_tzdiff::text || ' minutes')::interval;
	
	RETURN QUERY EXECUTE $SQL$
	WITH D(recorded_time, label, value) AS (
	SELECT
		conflict_recorded, conflict_type, conflict_count
	FROM pemdata.bdr_conflict_history_summary
	WHERE conflict_recorded >= $2::bigint
		AND conflict_recorded <= $3::bigint AND server_id = $1::integer
	),
	L(label, id) AS (
	SELECT distinct(label), DENSE_RANK() OVER (ORDER BY label) FROM D
	),
	T(recorded_time, label, id) AS (
	SELECT S.recorded_time, L.label, L.id
	FROM (
		SELECT generate_series(
		$2::bigint, $3::bigint, 3600
		) AS recorded_time
	) S, L
	)
	-- o_idx, o_label, o_aggtime,      o_aggval
	SELECT T.id::int2, T.label, T.recorded_time, COALESCE(D.value, 0)
	FROM T
	LEFT JOIN D ON (T.label = D.label AND T.recorded_time = D.recorded_time)
	ORDER BY T.recorded_time, T.id;
	$SQL$ USING p_sid, EXTRACT(EPOCH FROM v_stime)::bigint, EXTRACT(EPOCH FROM v_etime)::bigint;
	END$$ LANGUAGE 'plpgsql';

	INSERT INTO pem.chart_func(id, type, func, r_sys_obj, dep_probes) VALUES
		(95, 'Q', 
		E'SELECT o_idx, o_label,  ''Date('' || (o_aggtime * 1000)::text || '')'', o_aggval
		FROM pem.generate_bdr_conflict_history_chart_data($1::int4, $2::int4, $3::int4, $4::timestamptz, $5::timestamptz) 
		ORDER BY o_idx, o_aggtime', false, '{bdr_conflict_history_summary}')  ON CONFLICT DO NOTHING;

	INSERT INTO pem.chart(id, cid, fid, type, level, name, owner, shared, ref_cnt, reload, summary, labels, params, rwlimit_span_param, ref_timeout_param) VALUES
	(95, 16,  95,  'L', ARRAY[200], 'BDR Conflict History Summary',   0, NULL, 1, 50000,   NULL, 
	NULL, ARRAY['cid', 'did', 'server_id', 'start_time', 'end_time'], 'dash_db_useract_span', 'dash_db_useract_timeout')  ON CONFLICT DO NOTHING;
	INSERT INTO pem.line_chart (cid, type, yaxis) VALUES (95, 'M', 'Conflicts (#)') ON CONFLICT DO NOTHING;
	INSERT INTO pem.metrices_chart (cid, time_span) VALUES (95, '7 days'::interval) ON CONFLICT DO NOTHING;

	--
	-- BDR Group Replication Slots Replay Lag (Seconds)
	--
	INSERT INTO pem.chart(id, cid, fid, type, level, name, owner, shared, ref_cnt, reload, summary, labels, params, rwlimit_span_param, ref_timeout_param) VALUES
	(96, 17,  NULL,  'L', ARRAY[200], 'BDR Group Replication Slots Replay Lag (Seconds)',   0, NULL, 1, 50000,   NULL, NULL, NULL, '', '') ON CONFLICT DO NOTHING;

	INSERT INTO pem.line_chart (cid, type, yaxis) VALUES (96, 'M', 'Lag (Seconds)') ON CONFLICT DO NOTHING;
	INSERT INTO pem.metrices_chart (cid, time_span) VALUES (96, '14 days'::interval) ON CONFLICT DO NOTHING;
	INSERT INTO pem.chart_metric (cid, mid, tbl, metrices, glimit, agg_func, params) VALUES
		(96, 1, 'bdr_group_replslots_details', ARRAY['replay_lag'], 32,
		ARRAY['M'], NULL) ON CONFLICT DO NOTHING;

	--
	-- BDR Group Replication Slots Flush Lag (Seconds)
	--
	INSERT INTO pem.chart(id, cid, fid, type, level, name, owner, shared, ref_cnt, reload, summary, labels, params, rwlimit_span_param, ref_timeout_param) VALUES
	(97, 17,  NULL,  'L', ARRAY[200], 'BDR Group Replication Slots Flush Lag (Seconds)',   0, NULL, 1, 50000,   NULL, NULL, NULL, '', '') ON CONFLICT DO NOTHING;

	INSERT INTO pem.line_chart (cid, type, yaxis) VALUES (97, 'M', 'Lag (Seconds)') ON CONFLICT DO NOTHING;
	INSERT INTO pem.metrices_chart (cid, time_span) VALUES (97, '14 days'::interval) ON CONFLICT DO NOTHING;
	INSERT INTO pem.chart_metric (cid, mid, tbl, metrices, glimit, agg_func, params) VALUES
		(97, 1, 'bdr_group_replslots_details', ARRAY['flush_lag'], 32,
		ARRAY['M'], NULL) ON CONFLICT DO NOTHING;

	--
	-- BDR Group Replication Slots Write Lag (Seconds)
	--
	INSERT INTO pem.chart(id, cid, fid, type, level, name, owner, shared, ref_cnt, reload, summary, labels, params, rwlimit_span_param, ref_timeout_param) VALUES
	(98, 17,  NULL,  'L', ARRAY[200], 'BDR Group Replication Slots Write Lag (Seconds)',   0, NULL, 1, 50000,   NULL, NULL, NULL, '', '') ON CONFLICT DO NOTHING;

	INSERT INTO pem.line_chart (cid, type, yaxis) VALUES (98, 'M', 'Lag (Seconds)') ON CONFLICT DO NOTHING;
	INSERT INTO pem.metrices_chart (cid, time_span) VALUES (98, '14 days'::interval) ON CONFLICT DO NOTHING;
	INSERT INTO pem.chart_metric (cid, mid, tbl, metrices, glimit, agg_func, params) VALUES
		(98, 1, 'bdr_group_replslots_details', ARRAY['write_lag'], 32,
		ARRAY['M'], NULL) ON CONFLICT DO NOTHING;

	--
	-- BDR Group Replication Slots Sent Lag (Bytes)
	--
	INSERT INTO pem.chart(id, cid, fid, type, level, name, owner, shared, ref_cnt, reload, summary, labels, params, rwlimit_span_param, ref_timeout_param) VALUES
	(99, 17,  NULL,  'L', ARRAY[200], 'BDR Group Replication Slots Sent Lag (Bytes)',   0, NULL, 1, 50000,   NULL, NULL, NULL, '', '') ON CONFLICT DO NOTHING;

	INSERT INTO pem.line_chart (cid, type, yaxis) VALUES (99, 'M', 'Lag (Bytes)') ON CONFLICT DO NOTHING;
	INSERT INTO pem.metrices_chart (cid, time_span) VALUES (99, '14 days'::interval) ON CONFLICT DO NOTHING;
	INSERT INTO pem.chart_metric (cid, mid, tbl, metrices, glimit, agg_func, params) VALUES
		(99, 1, 'bdr_group_replslots_details', ARRAY['sent_lag_bytes'], 32,
		ARRAY['M'], NULL) ON CONFLICT DO NOTHING;

	--
	-- BDR Group Replication Slots Replay Lag (Bytes)
	--
	INSERT INTO pem.chart(id, cid, fid, type, level, name, owner, shared, ref_cnt, reload, summary, labels, params, rwlimit_span_param, ref_timeout_param) VALUES
	(100, 17,  NULL,  'L', ARRAY[200], 'BDR Group Replication Slots Replay Lag (Bytes)',   0, NULL, 1, 50000,   NULL, NULL, NULL, '', '') ON CONFLICT DO NOTHING;

	INSERT INTO pem.line_chart (cid, type, yaxis) VALUES (100, 'M', 'Lag (Bytes)') ON CONFLICT DO NOTHING;
	INSERT INTO pem.metrices_chart (cid, time_span) VALUES (100, '14 days'::interval) ON CONFLICT DO NOTHING;
	INSERT INTO pem.chart_metric (cid, mid, tbl, metrices, glimit, agg_func, params) VALUES
		(100, 1, 'bdr_group_replslots_details', ARRAY['replay_lag_bytes'], 32,
		ARRAY['M'], NULL) ON CONFLICT DO NOTHING;

	--
	-- BDR Group Replication Slots Flush Lag (Bytes)
	--
	INSERT INTO pem.chart(id, cid, fid, type, level, name, owner, shared, ref_cnt, reload, summary, labels, params, rwlimit_span_param, ref_timeout_param) VALUES
	(101, 17,  NULL,  'L', ARRAY[200], 'BDR Group Replication Slots Flush Lag (Bytes)',   0, NULL, 1, 50000,   NULL, NULL, NULL, '', '') ON CONFLICT DO NOTHING;

	INSERT INTO pem.line_chart (cid, type, yaxis) VALUES (101, 'M', 'Lag (Bytes)') ON CONFLICT DO NOTHING;
	INSERT INTO pem.metrices_chart (cid, time_span) VALUES (101, '14 days'::interval) ON CONFLICT DO NOTHING;
	INSERT INTO pem.chart_metric (cid, mid, tbl, metrices, glimit, agg_func, params) VALUES
		(101, 1, 'bdr_group_replslots_details', ARRAY['flush_lag_bytes'], 32,
		ARRAY['M'], NULL) ON CONFLICT DO NOTHING;

	--
	-- BDR Group Replication Slots Write Lag (Bytes)
	--
	INSERT INTO pem.chart(id, cid, fid, type, level, name, owner, shared, ref_cnt, reload, summary, labels, params, rwlimit_span_param, ref_timeout_param) VALUES
	(102, 17,  NULL,  'L', ARRAY[200], 'BDR Group Replication Slots Write Lag (Bytes)',   0, NULL, 1, 50000,   NULL, NULL, NULL, '', '') ON CONFLICT DO NOTHING;

	INSERT INTO pem.line_chart (cid, type, yaxis) VALUES (102, 'M', 'Lag (Bytes)') ON CONFLICT DO NOTHING;
	INSERT INTO pem.metrices_chart (cid, time_span) VALUES (102, '14 days'::interval) ON CONFLICT DO NOTHING;
	INSERT INTO pem.chart_metric (cid, mid, tbl, metrices, glimit, agg_func, params) VALUES
		(102, 1, 'bdr_group_replslots_details', ARRAY['write_lag_bytes'], 32,
		ARRAY['M'], NULL) ON CONFLICT DO NOTHING;

	--
	-- BDR Group Subscription Lag (Seconds)
	--
	INSERT INTO pem.chart(id, cid, fid, type, level, name, owner, shared, ref_cnt, reload, summary, labels, params, rwlimit_span_param, ref_timeout_param) VALUES
	(103, 17,  NULL,  'L', ARRAY[200], 'BDR Group Subscription Lag (Seconds)',   0, NULL, 1, 50000,   NULL, NULL, NULL, '', '') ON CONFLICT DO NOTHING;

	INSERT INTO pem.line_chart (cid, type, yaxis) VALUES (103, 'M', 'Lag (Seconds)') ON CONFLICT DO NOTHING;
	INSERT INTO pem.metrices_chart (cid, time_span) VALUES (103, '14 days'::interval) ON CONFLICT DO NOTHING;
	INSERT INTO pem.chart_metric (cid, mid, tbl, metrices, glimit, agg_func, params) VALUES
		(103, 1, 'bdr_group_subscription_summary', ARRAY['sub_lag_seconds'], 32,
		ARRAY['M'], NULL) ON CONFLICT DO NOTHING;


	--
	-- BDR Node Summary
	--
	INSERT INTO pem.chart_func(id, type, func, r_sys_obj, dep_probes) VALUES
		(104, 'P', 'table_bdr_node_summary', false, '{bdr_node_summary}') ON CONFLICT DO NOTHING;
	INSERT INTO pem.chart(id, cid, fid, type, level, name, owner, shared, ref_cnt, reload, summary, labels, params, rwlimit_span_param, ref_timeout_param) VALUES
		(104, 18,  104,  'TB', ARRAY[200], 'BDR Node Summary',  0, NULL,  1,  50000,   NULL,
		ARRAY['', 'Node', 'Node Group', 'Peer State', 'Peer Target State', 'Sub Repset'], ARRAY['server_id', 'sort_index', 'sort_direction'],
		NULL, NULL) ON CONFLICT DO NOTHING;

	--
	-- BDR Global Locks
	--
	INSERT INTO pem.chart(id, cid, fid, type, level, name, owner, shared, ref_cnt, reload, summary, labels, params, rwlimit_span_param, ref_timeout_param) VALUES
	(105, 18, NULL, 'TB', ARRAY[200], 'BDR Global Locks',          0, NULL, 1, 50000, NULL,
	ARRAY['Origin Node Name', 'Lock Type', 'Relation', 'PID', 'Acquire Stage', 'Waiters', 
			'Global Lock Request Time', 'Local Lock Request Time', 'Last State Change Time'], NULL, NULL, NULL) ON CONFLICT DO NOTHING;
	INSERT INTO pem.tbl_chart(cid, type) VALUES (105, 'D') ON CONFLICT DO NOTHING;
	INSERT INTO pem.data_chart(cid, tbl, metrices, orderby, glimit, r_sys_obj) VALUES(105, 'bdr_global_locks',
	ARRAY['origin_node_name', 'lock_type', 'relation', 'pid::text', 'acquire_stage', 'waiters', 
			'global_lock_request_time', 'local_lock_request_time', 'last_state_change_time'], ARRAY['origin_node_name'], 32, false) ON CONFLICT DO NOTHING;

	--
	-- BDR Workers
	--
	INSERT INTO pem.chart_func(id, type, func, r_sys_obj, dep_probes) VALUES
		(106, 'P', 'table_bdr_workers', false, '{bdr_workers}') ON CONFLICT DO NOTHING;
	INSERT INTO pem.chart(id, cid, fid, type, level, name, owner, shared, ref_cnt, reload, summary, labels, params, rwlimit_span_param, ref_timeout_param) VALUES
		(106, 18,  106,  'TB', ARRAY[200], 'BDR Workers',  0, NULL,  1,  50000,   NULL, ARRAY[''],
		ARRAY['server_id', 'sort_index', 'sort_direction'], NULL, NULL) ON CONFLICT DO NOTHING;

	--
	-- BDR Worker Errors
	--
	INSERT INTO pem.chart_func(id, type, func, r_sys_obj, dep_probes) VALUES
		(107, 'P', 'table_bdr_worker_errors', false, '{bdr_worker_errors}') ON CONFLICT DO NOTHING;
	INSERT INTO pem.chart(id, cid, fid, type, level, name, owner, shared, ref_cnt, reload, summary, labels, params, rwlimit_span_param, ref_timeout_param) VALUES
		(107, 18,  107,  'TB', ARRAY[200], 'BDR Worker Errors',  0, NULL,  1,  50000,   NULL, ARRAY[''],
		ARRAY['server_id', 'sort_index', 'sort_direction'], NULL, NULL) ON CONFLICT DO NOTHING;

	--
	-- BDR Group Versions Details
	--
	INSERT INTO pem.chart(id, cid, fid, type, level, name, owner, shared, ref_cnt, reload, summary, labels, params, rwlimit_span_param, ref_timeout_param) VALUES
	(108, 18, NULL, 'TB', ARRAY[200], 'BDR Group Versions Details', 0, NULL, 1, 50000, NULL, 
	ARRAY['Node Name', 'Postgres Version', 'pglogical Version', 'BDR Version', 'BDR Edition'], NULL, NULL, NULL) ON CONFLICT DO NOTHING;
	INSERT INTO pem.tbl_chart(cid, type) VALUES (108, 'D') ON CONFLICT DO NOTHING;
	INSERT INTO pem.data_chart(cid, tbl, metrices, orderby, glimit, r_sys_obj) VALUES(108, 'bdr_group_versions_details',
	ARRAY['node_name', 'postgres_version', 'pglogical_version', 'bdr_version', 'bdr_edition'], ARRAY['node_name'], 32, false) ON CONFLICT DO NOTHING;

	--
	-- BDR Group Raft Details
	--
	INSERT INTO pem.chart(id, cid, fid, type, level, name, owner, shared, ref_cnt, reload, summary, labels, params, rwlimit_span_param, ref_timeout_param) VALUES
	(109, 18, NULL, 'TB', ARRAY[200], 'BDR Group Raft Details', 0, NULL, 1, 50000, NULL,
	ARRAY['Node Name', 'State', 'Leader ID', 'Current Term', 'Commit Index'], NULL, NULL, NULL) ON CONFLICT DO NOTHING;
	INSERT INTO pem.tbl_chart(cid, type) VALUES (109, 'D') ON CONFLICT DO NOTHING;
	INSERT INTO pem.data_chart(cid, tbl, metrices, orderby, glimit, r_sys_obj) VALUES(109, 'bdr_group_raft_details',
	ARRAY['node_name', 'state', 'leader_id', 'current_term', 'commit_index'], ARRAY['node_name'], 32, false) ON CONFLICT DO NOTHING;


	--
	-- BDR Group Camo Details
	--
	INSERT INTO pem.chart(id, cid, fid, type, level, name, owner, shared, ref_cnt, reload, summary, labels, params, rwlimit_span_param, ref_timeout_param) VALUES
	(110, 17, NULL, 'TB', ARRAY[200], 'BDR Group Camo Details', 0, NULL, 1, 50000, NULL,
	ARRAY['Node Name', 'Camo Partner Of', 'Camo Origin For', 'Is Camo Partner Connected?', 'Is Camo Partner Ready?',
	'Camo Transactions Resolved', 'Apply LSN', 'Receive LSN', 'Apply Queue Size'], NULL, NULL, NULL) ON CONFLICT DO NOTHING;
	INSERT INTO pem.tbl_chart(cid, type) VALUES (110, 'D') ON CONFLICT DO NOTHING;
	INSERT INTO pem.data_chart(cid, tbl, metrices, orderby, glimit, r_sys_obj) VALUES(110, 'bdr_group_camo_details',
	ARRAY['node_name', 'camo_partner_of', 'camo_origin_for', 'is_camo_partner_connected', 'is_camo_partner_ready',
			'camo_transactions_resolved', 'apply_lsn', 'receive_lsn', 'apply_queue_size'], ARRAY['node_name', 'camo_partner_of'], 32, false) ON CONFLICT DO NOTHING;

	IF NOT EXISTS (SELECT id FROM pem.alert_template where display_name = 'BDR Group Raft Consensus') THEN
	-- Create new alert template that check for BDR group raft consensus working or not
	PERFORM pem.create_alert_template(
		'BDR Group Raft Consensus',
		'BDR group raft consensus not working',
		$sql$
		SELECT CASE
				WHEN status = 'WARNING' THEN 0.3
				WHEN status = 'CRITICAL' or status = 'UNKNOWN' THEN 0.5
				ELSE 0.0
			END,
			status as display_value
		FROM pemdata.bdr_monitor_group_raft where server_id = ${server_id};
		$sql$,
		200, NULL, NULL, NULL, 'STATE', '{bdr_monitor_group_raft}', (SELECT CASE WHEN MAX(snmp_oid) > 0 THEN MAX(snmp_oid) + 1 ELSE 1 END FROM pem.alert_template WHERE object_type = 200),
		'ALL', 1, 30, true,
		$SQL$
		SELECT
		status as "Status", message as "Message"
		FROM pemdata.bdr_monitor_group_raft where server_id = ${server_id};
		$SQL$,
	true, '>', '{0.1, 0.2, 0.4}');

	END IF;
	IF NOT EXISTS (SELECT id FROM pem.alert_template where display_name = 'BDR Group Versions check') THEN

	-- Create new alert template that check for BDR version check
	PERFORM pem.create_alert_template(
		'BDR Group Versions check',
		'BDR/pglogical version mismatched in BDR group',
		$sql$
		SELECT CASE
					WHEN status = 'WARNING' THEN 0.3
					WHEN status = 'UNKNOWN' THEN 0.5
					ELSE 0.0
				END,
				status as display_value
		FROM pemdata.bdr_monitor_group_versions where server_id = ${server_id};$sql$,
		200, NULL, NULL, NULL, 'STATE', '{bdr_monitor_group_raft}', (SELECT CASE WHEN MAX(snmp_oid) > 0 THEN MAX(snmp_oid) + 1 ELSE 1 END FROM pem.alert_template WHERE object_type = 200),
		'ALL', 1, 30, true,
		$SQL$
		SELECT
		status as "Status", message as "Message"
		FROM pemdata.bdr_monitor_group_versions where server_id = ${server_id};
		$SQL$, true, '>', '{0.1, 0.2, 0.4}');
	END IF;

	IF NOT EXISTS (SELECT id FROM pem.alert_template where display_name = 'BDR Group Raft Leader ID not matching') THEN
	-- Create new alert template that check if are more than one Leader ID's in customer
	PERFORM pem.create_alert_template(
		'BDR Group Raft Leader ID not matching',
		'BDR group raft leader id not matching',
		$sql$
		SELECT
		CASE WHEN COUNT(DISTINCT leader_id) + COUNT(DISTINCT CASE WHEN leader_id is null THEN 1 END) > 1 THEN 1 ELSE 0 END,
		COUNT(DISTINCT leader_id) + COUNT(DISTINCT CASE WHEN leader_id is null THEN 1 END) AS display_value
		FROM pemdata.bdr_group_raft_details WHERE server_id = ${server_id};
		$sql$,
		200, NULL, NULL, NULL, 'No of Leader ID''s', '{bdr_group_raft_details}', (SELECT CASE WHEN MAX(snmp_oid) > 0 THEN MAX(snmp_oid) + 1 ELSE 1 END FROM pem.alert_template WHERE object_type = 200),
		'ALL', 1, 30, true,
		$SQL$
		SELECT node_name as "Node Name", leader_id as "Leader ID"
		FROM pemdata.bdr_group_raft_details where server_id = ${server_id};
		$SQL$, true, '>', '{0.1, 0.2, 0.3}');

	END IF;
	IF NOT EXISTS (SELECT id FROM pem.alert_template where display_name = 'BDR worker error detected') THEN
	-- Create new alert template that check if worker errors reported for a BDR node.
	PERFORM pem.create_alert_template(
		'BDR worker error detected',
		'BDR worker error detected reported for BDR node',
		$sql$
		SELECT
		COUNT(*)
		FROM pemdata.bdr_worker_errors WHERE server_id = ${server_id};
		$sql$,
		200, NULL, NULL, NULL, 'No of worker error''s', '{bdr_worker_errors}', (SELECT CASE WHEN MAX(snmp_oid) > 0 THEN MAX(snmp_oid) + 1 ELSE 1 END FROM pem.alert_template WHERE object_type = 200),
		'ALL', 1, 30, true, NULL, true, '>', '{0.1, 0.2, 0.3}');

	END IF;

END;
$DO$ LANGUAGE 'plpgsql';

-- PEM-4073
-- Update downObjects binding variable object oid to .10.15
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
		ELSIF (NEW.current_state IS NULL) AND (OLD.current_state IS NOT NULL) AND is_send_trap THEN
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

END TRANSACTION;
