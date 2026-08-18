/***************************************************************************
 *
 * Postgres Enterprise Manager
 *
 * Copyright (C) 2010 - 2025, EnterpriseDB Corporation. All rights reserved.
 *
 ***************************************************************************/

-- NOTE: This sql file is responsible for PEM 9.5.0 schema upgrade.
BEGIN TRANSACTION;
DO $DO$
	DECLARE
    enum_value_exists BOOLEAN;
	BEGIN
        -- Check if 'BOOL' already exists in the enum type
        SELECT EXISTS (SELECT 1 FROM pg_enum WHERE enumtypid = 'pem.alert_param_type'::regtype AND enumlabel = 'BOOL') INTO enum_value_exists;
        -- If 'BOOL' doesn't exist, add it and commit the transaction
        IF NOT enum_value_exists THEN
        BEGIN
            -- Add 'BOOL' to the enum type
            ALTER TYPE pem.alert_param_type ADD VALUE 'BOOL';
        EXCEPTION
            WHEN OTHERS THEN
                RAISE NOTICE 'Error adding enum value: %', SQLERRM;
        END;
    END IF;
END;
$DO$ LANGUAGE plpgsql;
END TRANSACTION;

BEGIN TRANSACTION;
    CREATE OR REPLACE FUNCTION pem.schema_version() RETURNS integer AS
        'SELECT 202402091::integer;'
    LANGUAGE 'sql' IMMUTABLE;
    COMMENT ON FUNCTION pem.schema_version() IS
        'Returns the version number of the PEM schema';

    -- PEM-5009: Granted the permission to pem_agent user
    GRANT SELECT ON TABLE pem.custom_email_template TO pem_agent;

    -- PEM-4950: Added the EmailGroup/EmailGroupId to JSON payload in Webhook notification
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
        email_group_name text;
        low_email_group_id integer;
        med_email_group_id integer;
        high_email_group_id integer;
        all_email_group_id integer;
        email_group_id integer;
        cleared_alert_enable boolean:= true;

    BEGIN
        -- Get alert details
        SELECT
            a.agent_id, a.template_id, a.send_email, a.acknowledged, a.flapping_detected, a.send_trap, a.snmp_trap_version, a.low_send_trap, a.med_send_trap,
            a.high_send_trap, wa._send_notification, wa._low_webhook_ids, wa._med_webhook_ids, wa._high_webhook_ids, wa._cleared_webhook_ids,
            a.execute_script, a.execute_script_on_clear, a.execute_script_on_pem_server, a.script_code, a.submit_to_nagios,a.cleared_alert_enable,
            -- Get additional alert, agent, server details
            a.name, a.server_id, a.thresholds, a.database_name, a.schema_name, a.package_name, a.object_name,
            -- Get email group ids
            a.email_group_id, a.low_email_group_id, a.med_email_group_id, a.high_email_group_id,
            a.params, s.description, s.server, s.port, ag.description, at.param_names, at.param_units, ptt.display_name,
            pas.info_cols, pas.info_vals
            INTO
            agentid, templateid, is_send_email, is_acknowledged, is_flapping_detected, is_send_trap, trap_version, low_trap, med_trap,
            high_trap, is_send_webhook, low_webhook_ids, med_webhook_ids, high_webhook_ids, cleared_webhook_ids,
            is_execute_script, is_execute_on_clear, is_execute_on_pem_server, code, is_submit_to_nagios,cleared_alert_enable,
            alert_name, alert_server_id, alert_thresholdvalue, alert_database_name, alert_schema_name, alert_package_name, alert_db_object_name,
            all_email_group_id, low_email_group_id, med_email_group_id, high_email_group_id,
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
            alert_info_details = concat(alert_info_details, '[');
            FOR idx in 1 .. array_length(alert_info_values, 1)
            LOOP
                alert_info_details = concat(alert_info_details, '{');

                FOR ifn in 1 .. array_length(alert_info_names, 1)
                LOOP
                    BEGIN
                        -- Fixed (PEM-4766/91551):
                        -- Don't use newline character as it will not recognise it
                        -- as JSON object.
                        alert_info_details = concat(
                            alert_info_details,
                            alert_info_names[ifn], ': ',
                            COALESCE(alert_info_values[idx][ifn], '')::text,
                            E', '
                        );
                    EXCEPTION WHEN OTHERS THEN
                    -- Do nothing just keep looping
                    END;
                END LOOP;

                alert_info_details = concat(trim(trailing ', ' from alert_info_details), '}, ');
            END LOOP;
            alert_info_details = trim(trailing ', ' from alert_info_details);
            alert_info_details = concat(alert_info_details, ']');
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

            -- Get webhook_ids and group id according to alert level low, med, high and cleared.
            IF (NEW.current_state IS NOT NULL) AND (NEW.current_state::text = 'LOW') AND COALESCE(array_length(low_webhook_ids, 1), 0) > 0 THEN
                    webhook_ids = low_webhook_ids;
                    email_group_id = low_email_group_id;
            ELSIF (NEW.current_state IS NOT NULL) AND (NEW.current_state::text = 'MEDIUM') AND COALESCE(array_length(med_webhook_ids, 1), 0) > 0 THEN
                    webhook_ids = med_webhook_ids;
                    email_group_id = med_email_group_id;
            ELSIF (NEW.current_state IS NOT NULL) AND (NEW.current_state::text = 'HIGH') AND COALESCE(array_length(high_webhook_ids, 1), 0) > 0 THEN
                    webhook_ids = high_webhook_ids;
                    email_group_id = high_email_group_id;
            END IF;

            email_group_id := COALESCE(email_group_id, all_email_group_id);
            SELECT name FROM pem.email_group WHERE id = email_group_id INTO email_group_name;

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
                            payload = pem.replace_json_params(payload, '%EmailGroupId%', email_group_id::text, 'g');
                            payload = pem.replace_json_params(payload, '%EmailGroup%', email_group_name::text, 'g');

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

            -- Get webhook_ids and group id according to alert level low, med, high and cleared.
            IF (NEW.current_state IS NOT NULL) AND (NEW.current_state::text = 'LOW') AND COALESCE(array_length(low_webhook_ids, 1), 0) > 0 THEN
                    webhook_ids = low_webhook_ids;
                    email_group_id = low_email_group_id;
            ELSIF (NEW.current_state IS NOT NULL) AND (NEW.current_state::text = 'MEDIUM') AND COALESCE(array_length(med_webhook_ids, 1), 0) > 0 THEN
                    webhook_ids = med_webhook_ids;
                    email_group_id = med_email_group_id;
            ELSIF (NEW.current_state IS NOT NULL) AND (NEW.current_state::text = 'HIGH') AND COALESCE(array_length(high_webhook_ids, 1), 0) > 0 THEN
                    webhook_ids = high_webhook_ids;
                    email_group_id = high_email_group_id;
            ELSIF (NEW.current_state IS NULL) AND (OLD.current_state IS NOT NULL) AND COALESCE(array_length(cleared_webhook_ids, 1), 0) > 0 THEN
                    webhook_ids = cleared_webhook_ids;
            END IF;

            email_group_id := COALESCE(email_group_id, all_email_group_id);
            SELECT name FROM pem.email_group WHERE id = email_group_id INTO email_group_name;

            -- SMTP Notifications
            IF is_send_email AND (NOT is_acknowledged) AND (NOT is_flapping_detected) AND ((NEW.current_state IS NOT NULL) OR cleared_alert_enable) THEN
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
                            payload = pem.replace_json_params(payload, '%EmailGroupId%', email_group_id::text, 'g');
                            payload = pem.replace_json_params(payload, '%EmailGroup%', email_group_name::text, 'g');

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


    -- PEM-4959 Fixed Deleted custom probe still visible in Probe Dependency tab of Alert Templates
    CREATE or REPLACE FUNCTION pem.alert_templates_probe_dependency_deletion() RETURNS TRIGGER AS $$
    BEGIN
	    UPDATE pem.alert_template SET probe_dependency_list = (select ARRAY_REMOVE(probe_dependency_list, OLD.internal_name));
	    RETURN NEW;
    END
    $$ LANGUAGE plpgsql;

    DROP TRIGGER IF EXISTS alert_templates_probe_dependency_deletion ON pem.probe;
    CREATE TRIGGER alert_templates_probe_dependency_deletion
        AFTER UPDATE OF deleted
        OR DELETE ON pem.probe
	    FOR EACH ROW EXECUTE PROCEDURE pem.alert_templates_probe_dependency_deletion();

    -- Implemented the same for the older records
    DO $$
        DECLARE
            pr RECORD;
            -- Declare cursor
            curs_probe_deletion CURSOR FOR
                SELECT internal_name FROM pem.probe WHERE deleted = true;
            curs_alert_template cursor for
                select id, probe_dependency_list from pem.alert_template;
            probe_name varchar;
        BEGIN
            for alert_temp in curs_alert_template loop
                foreach probe_name in array alert_temp.probe_dependency_list loop
                    IF NOT EXISTS (SELECT 1 FROM pem.probe WHERE internal_name = probe_name) THEN
                        UPDATE pem.alert_template SET probe_dependency_list = ARRAY_REMOVE(probe_dependency_list, probe_name) where id=alert_temp.id;
                    end if;
                end loop;
            end loop;
            for pr in curs_probe_deletion loop
                UPDATE pem.alert_template SET probe_dependency_list = ARRAY_REMOVE(probe_dependency_list, pr.internal_name);
            END LOOP;
    END $$;

    -- Creating event_history table to identify the user who changed the blackout componenet status and datetime
    CREATE TABLE IF NOT EXISTS pem.event_history (
    recorded_time TIMESTAMP NOT NULL,
    user_name VARCHAR(255) NOT NULL,
    component VARCHAR(255) NOT NULL,
    operation VARCHAR(255) NOT NULL,
    message VARCHAR(255) NOT NULL,
    details VARCHAR(255) NOT NULL
    );

    GRANT UPDATE ON TABLE pem.event_history TO pem_agent;

    -- fuction to update the blackout value for agent/server and maintain the history
    CREATE OR REPLACE FUNCTION pem.update_alert_blackout(
        p_agent_object boolean,
        p_blackout_flag boolean,
        p_objects_ids integer[])
    RETURNS VOID AS $$
    DECLARE
        job_id integer;
        payload text;
        operation text DEFAULT '';
        _rows_affected integer;
        _owner VARCHAR(255);
        message VARCHAR(255) DEFAULT '';
    BEGIN
        EXECUTE format(
            'UPDATE pem.%I SET alert_blackout = $1::boolean WHERE active = true AND id in (SELECT unnest(%L::integer[]))',
            CASE WHEN p_agent_object THEN 'agent' ELSE 'server' END,
            p_objects_ids
        ) USING p_blackout_flag;

        -- Check for errors by examining the number of affected rows
        GET DIAGNOSTICS _rows_affected = ROW_COUNT;

        IF _rows_affected < 0 THEN
            -- Error occurred during dynamic SQL execution
            RAISE EXCEPTION 'Error updating alert_blackout';
        ELSE
            _owner = pg_catalog.quote_ident(current_user);

            IF p_blackout_flag THEN
                SELECT enable_jobid INTO job_id from pem.alert_blackout_config b WHERE blackout_object_ids = p_objects_ids;
                operation = 'enable_alert_blackout';
                message = concat('Enabled the alert blackout for the ',CASE WHEN p_agent_object THEN 'agent' ELSE 'server' END);
            ELSE
                SELECT disable_jobid INTO job_id from pem.alert_blackout_config b WHERE blackout_object_ids = p_objects_ids;
                operation = 'disable_alert_blackout';
                message = concat('Disabled the alert blackout for the ',CASE WHEN p_agent_object THEN 'agent' ELSE 'server' END);
            END IF;

            payload = '{
            "AlertBlackoutValue": "%AlertBlackoutValue%",
            "IsAgent": "%AgentObject%",
            "Ids": "%ObjectIds%",
            "Scheduled": "%Scheduled%",
            "JobID": "%JobID%"
            }';

            --cretae payload
            payload = pem.replace_json_params(payload, '%AlertBlackoutValue%',p_blackout_flag::text, 'g');
            payload = pem.replace_json_params(payload, '%AgentObject%', p_agent_object::text, 'g');
            payload = pem.replace_json_params(payload, '%ObjectIds%', p_objects_ids::text, 'g');
            payload = pem.replace_json_params(payload, '%Scheduled%', true::text, 'g');
            payload = pem.replace_json_params(payload, '%JobID%', job_id::text, 'g');

            -- used to maintain the history for alert_blackout component
            INSERT INTO pem.event_history ("recorded_time", "user_name", "component", "operation", "message", "details")
                        VALUES (current_timestamp, _owner, 'alert_blackout'::text, operation::text, message::text, payload::text);
        END IF;
    END;
    $$ LANGUAGE plpgsql;

    -- fix PEM-5006 where dashboard shows "Dashboard info not found"
    CREATE OR REPLACE FUNCTION pem.can_access_team(_owner OID, _team text)
    RETURNS boolean AS
    $$
        SELECT
            (
                -- team is not defined
                (SELECT (value = 't') AS value FROM pem.config WHERE param = 'show_objects_with_no_team') AND
                (_team IS NULL OR _team = '')
            ) OR
            -- current user is the owner
            _owner =  pg_catalog.quote_ident(current_user)::regrole::oid OR
            -- current user is pem_super_admin
            pg_catalog.pg_has_role('pem_super_admin', 'member') OR
            -- current user is a member of the team (or team does not exist)
            CASE WHEN EXISTS (
                SELECT 1 FROM pg_catalog.pg_roles AS t WHERE t.rolname = _team
            ) THEN pg_catalog.pg_has_role(_team, 'member')
            ELSE false
            END;
    $$ LANGUAGE 'sql';

	-- PEM-3611 flag to mute the clear alert notification
    ALTER TABLE IF EXISTS pem.alert
    ADD COLUMN IF NOT EXISTS cleared_alert_enable BOOLEAN NOT NULL DEFAULT TRUE;

    -- delete older pem.create_alert function
    DROP FUNCTION IF EXISTS pem.create_alert(name text,
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
                                                    check_frequency		integer,
                                                    history_retention	integer,
                                                    enabled			bool,
                                                    auto_created		bool,
                                                    email_group_id		integer,
                                                    send_email		bool,
                                                    flapping_detected	bool,
                                                    last_flapping_detection_processed timestamptz,
                                                    send_trap		bool,
                                                    snmp_trap_version	integer,
                                                    low_send_trap		bool,
                                                    low_email_group_id	integer,
                                                    med_send_trap		bool,
                                                    med_email_group_id	integer,
                                                    high_send_trap		bool,
                                                    high_email_group_id	integer,
                                                    execute_script	bool,
                                                    execute_script_on_clear	bool,
                                                    execute_script_on_pem_server bool,
                                                    script_code	text,
                                                    submit_to_nagios boolean);

    -- Added "cleared_alert_enable" column to function
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
                                                auto_created		bool DEFAULT false,
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
                                                script_code	text DEFAULT NULL,
                                                submit_to_nagios boolean DEFAULT false,
                                                cleared_alert_enable boolean DEFAULT true)
    RETURNS integer AS $$
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
                                check_frequency, history_retention, auto_created, email_group_id, send_email,
                                flapping_detected, last_flapping_detection_processed,
                                send_trap, snmp_trap_version, low_send_trap, low_email_group_id, med_send_trap,
                                med_email_group_id, high_send_trap, high_email_group_id, execute_script, execute_script_on_clear,
                                execute_script_on_pem_server, script_code, submit_to_nagios, cleared_alert_enable)
        VALUES($1, $14, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, $15, $16, $17, $18, $19, $20,
                $21, $22, $23, $24, $25, $26, $27, $28, $29, $30, $31, $32, $33) RETURNING id;
    $$ LANGUAGE sql;

  -- PEM-4776: Introduces a new Alert template for user password expiry
	DO $DO$
	BEGIN
		IF NOT EXISTS (SELECT 1
				FROM pg_attribute
				WHERE attrelid = (SELECT oid FROM pg_class WHERE relname = 'user_info' and relnamespace = (SELECT oid FROM pg_namespace WHERE nspname = 'pemdata'))
				AND attname = 'usepasswordexpire') THEN
					ALTER TABLE pemdata.user_info ADD COLUMN usepasswordexpire timestamptz;
					ALTER TABLE pemhistory.user_info ADD COLUMN usepasswordexpire timestamptz;

		END IF;

        IF NOT EXISTS (
                    SELECT server_version_id FROM pem.probe_server_version
                    WHERE server_version_id = 21600 AND probe_id = (
                        SELECT id FROM pem.probe WHERE internal_name = 'user_info'
                    ))
        THEN
            INSERT INTO pem.probe_server_version(probe_id, server_version_id, probe_code)
            SELECT
                (SELECT id FROM pem.probe WHERE internal_name = 'user_info'), v.version,
                            'SELECT usename, usesuper, valuntil, useconfig, now() as capture_time FROM pg_catalog.pg_user'
                FROM (
                    VALUES
                    (11100), (11200), (11300), (11400), (11500), (11600)
                    ) v(version);

            INSERT INTO pem.probe_server_version(probe_id, server_version_id, probe_code)
            SELECT
                (SELECT id FROM pem.probe WHERE internal_name = 'user_info'), v.version,
                            'SELECT usename, usesuper, valuntil, useconfig, now() as capture_time, usepasswordexpire FROM pg_catalog.pg_user'
                FROM (
                    VALUES
                    (21100), (21200), (21300), (21400), (21500), (21600)
                    ) v(version);
        END IF;
        UPDATE pem.probe
                SET any_server_version = false
                WHERE id = (
                    SELECT id FROM pem.probe WHERE internal_name = 'user_info'
                );
        CREATE OR REPLACE FUNCTION pemdata.copy_user_info_to_history() RETURNS TRIGGER AS $$
        BEGIN
	        IF (TG_OP = 'INSERT' OR TG_OP = 'UPDATE') THEN
			    INSERT INTO pemhistory.user_info (recorded_time, server_id, usename, usesuper, valuntil, useconfig, capture_time, usepasswordexpire) VALUES (NEW.recorded_time, NEW.server_id, NEW.usename, NEW.usesuper, NEW.valuntil, NEW.useconfig, NEW.capture_time, NEW.usepasswordexpire);
	        ELSIF EXISTS(SELECT 1 FROM pem.server WHERE id = OLD.server_id) THEN
		        INSERT INTO pemhistory.user_info (server_id, usename) VALUES (OLD.server_id, OLD.usename);
	        END IF;
	        RETURN NEW;
        END;
        $$ LANGUAGE plpgsql;
    END;
	$DO$ LANGUAGE plpgsql;

	DO $DO$
	BEGIN
        IF NOT EXISTS(SELECT 1 FROM pem.alert_template WHERE display_name='Number of users whose password expiring in N days' AND object_type=200) THEN
            PERFORM pem.create_alert_template(
            'Number of users whose password expiring in N days',
            'Number of users whose password have expired or are expiring in N days.(Will return top 10 users only)',
            $sql$
                SELECT value AS display_value FROM (SELECT count(*)
                     AS value
                FROM
                    pemdata.user_info
                WHERE  server_id = ${server_id}
                AND    usepasswordexpire IS NOT NULL
                AND    usepasswordexpire NOT IN ('infinity','-infinity')
                AND    usepasswordexpire < now()+('${param_1}'||'days')::interval
                AND ('${param_2}' OR usepasswordexpire > NOW())) s
            $sql$,
                200, '{Number of days,Include users whose password has already expired?}', '{INTEGER,BOOL}', '{DAYS,True or False}', '#','{user_info}', (SELECT CASE WHEN MAX(snmp_oid) > 0 THEN MAX(snmp_oid) + 1 ELSE 1 END FROM pem.alert_template WHERE object_type = 200), 'ADVANCED_SERVER',
                info_sql := $SQL$
                SELECT usename AS "Username",
                    CASE
                        WHEN usepasswordexpire > now() THEN
                            CASE
                                WHEN ROUND(EXTRACT(EPOCH FROM (usepasswordexpire - capture_time)) / 86400)::integer = 1 THEN
                                '1 day'
                            ELSE
                                ROUND(EXTRACT(EPOCH FROM (usepasswordexpire - capture_time)) / 86400)::integer || ' days'
                            END
                        ELSE
                    'Expired'
                    END AS "Password expiry (in Days)",
                    CASE
                        WHEN usesuper = true THEN 'True'
                        ELSE 'False'
                    END AS "Is superuser?",
                    usepasswordexpire AS "Password expires on"
                FROM
                    pemdata.user_info
                WHERE
                    server_id = ${server_id}
                    AND usepasswordexpire IS NOT NULL
                    AND usepasswordexpire NOT IN ('infinity', '-infinity')
                    AND usepasswordexpire < now()+('${param_1}'||'days')::interval
                    AND ('${param_2}' OR usepasswordexpire > NOW())
                GROUP BY
                    usename, usesuper, usepasswordexpire, capture_time
                ORDER BY
                    2 ASC LIMIT 10;
            $SQL$
            );
        END IF;
	END;
	$DO$ LANGUAGE plpgsql;

  -- Update the alert template 'A user expires in N days'
  DO $DO$
  BEGIN
      -- Print the information about the deletion
      RAISE INFO '--- Deleting all the alerts which were created using the template ''A user expires in N days''';

      DELETE FROM pem.alert
      WHERE template_id = (
      SELECT id FROM pem.alert_template WHERE display_name='A user expires in N days' AND object_type=200 AND is_system_template);
  END;
  $DO$ LANGUAGE plpgsql;

  UPDATE pem.alert_template
  SET
      display_name = 'Number of users expiring in N days',
      reference_id = REPLACE(reference_id, 'A user expires in N days', 'Number of users expiring in N days'),
      description = 'Number of users whose accounts are expiring in N days.(Will return top 10 users only)',
      param_names = '{Number of days,Include expired users?}',
      param_types = '{INTEGER, BOOL}',
      param_units = '{Days, True or False}',
      threshold_unit = '#',
      sql=$SQL$
      SELECT value AS display_value FROM (SELECT count(*)
           AS value
          FROM
              pemdata.user_info
          WHERE  server_id = ${server_id}
          AND		valuntil IS NOT NULL
          AND		valuntil NOT IN ('infinity','-infinity')
          AND		valuntil < now()+('${param_1}'||'days')::interval
          AND ('${param_2}' OR usepasswordexpire > NOW()))s
      $SQL$,
      info_sql=$SQL$
      SELECT usename AS "Username",
      CASE
          WHEN valuntil > now() THEN
              CASE
                  WHEN ROUND(EXTRACT(EPOCH FROM (valuntil - capture_time)) / 86400)::integer = 1 THEN
                  '1 day'
              ELSE
                  ROUND(EXTRACT(EPOCH FROM (valuntil - capture_time)) / 86400)::integer || ' days'
              END
          ELSE
      'Expired'
      END AS "Account expires (in Days)",
      CASE
          WHEN usesuper = true THEN 'True'
          ELSE 'False'
      END AS "Is superuser?",
      valuntil AS "Account expires on"
      FROM
          pemdata.user_info
      WHERE  server_id = '${server_id}'
      AND    valuntil IS NOT NULL
      AND    valuntil NOT IN ('infinity','-infinity')
      AND    valuntil < now()+('${param_1}'||'days')::interval
      AND ('${param_2}' OR usepasswordexpire > NOW())
      GROUP BY usename, usesuper, valuntil, capture_time
      ORDER BY 2 ASC LIMIT 10;
      $SQL$
  WHERE display_name = 'A user expires in N days' AND object_type = 200;

  -- PEM-4843: Add a column application_name to the session_info table
  DO $DO$
  BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_attribute WHERE attrelid = (SELECT oid FROM pg_class WHERE relname = 'session_info' and relnamespace = (SELECT oid FROM pg_namespace WHERE nspname = 'pemdata')) AND attname = 'application_name') THEN
        INSERT INTO pem.probe_column(probe_id, internal_name, display_name, display_position, classification, sql_data_type, unit_of_value,
        calculate_pit, discard_history, pit_by_default) SELECT id, 'application_name', 'Application Name', 25, 'm', 'text', '', false, false,
        false FROM pem.probe WHERE internal_name='session_info';
        ALTER TABLE pemdata.session_info ADD COLUMN application_name text;
        ALTER TABLE pemhistory.session_info ADD COLUMN application_name text;

        CREATE OR REPLACE FUNCTION pemdata.copy_session_info_to_history()
        RETURNS trigger
        LANGUAGE 'plpgsql'
        COST 100
        VOLATILE NOT LEAKPROOF
        AS $BODY$
        BEGIN
            IF (TG_OP = 'INSERT' OR TG_OP = 'UPDATE') THEN
                INSERT INTO pemhistory.session_info (recorded_time, server_id, database_name, procpid, usename, backend_start, xact_start, query_start, is_waiting, is_idle, is_idle_in_transaction, is_vacuum, is_autovacuum, capture_time, client_addr, client_port, memory_usage_mb, swap_usage_mb, cpu_usage, io_read_bytes, io_write_bytes, wait_event_type, wait_event, query, state, state_change, application_name) VALUES (NEW.recorded_time, NEW.server_id, NEW.database_name, NEW.procpid, NEW.usename, NEW.backend_start, NEW.xact_start, NEW.query_start, NEW.is_waiting, NEW.is_idle, NEW.is_idle_in_transaction, NEW.is_vacuum, NEW.is_autovacuum, NEW.capture_time, NEW.client_addr, NEW.client_port, NEW.memory_usage_mb, NEW.swap_usage_mb, NEW.cpu_usage, NEW.io_read_bytes, NEW.io_write_bytes, NEW.wait_event_type, NEW.wait_event, NEW.query, NEW.state, NEW.state_change, NEW.application_name);
                ELSIF EXISTS(SELECT 1 FROM pem.server WHERE id = OLD.server_id) THEN
                INSERT INTO pemhistory.session_info (server_id, procpid) VALUES (OLD.server_id, OLD.procpid);
            END IF;
            RETURN NEW;
        END;
        $BODY$;

        -- Update the sql to return the application_name
        UPDATE pem.probe_server_version SET probe_code =
            E'SELECT datname AS database_name, pid AS procpid, usename, client_addr, client_port, backend_start,
                xact_start, query_start, waiting AS is_waiting, state = ''idle'' AS is_idle,
                state like ''%idle in transaction%'' AS is_idle_in_transaction, query ilike $$VACUUM%$$ as is_vacuum,
                client_port IS NULL AND (query like $$autovacuum:%$$ OR query like $$VACUUM%$$) as is_autovacuum,
                now() AS capture_time, query, state, state_change, application_name FROM pg_catalog.pg_stat_activity'
        WHERE probe_id = (SELECT id from pem.probe WHERE internal_name = 'session_info')
        AND server_version_id IN (10902, 10903, 10904, 10905,  20902, 20903, 20904, 20905);

        UPDATE pem.probe_server_version SET probe_code =
            E'SELECT datname AS database_name, pid AS procpid, usename, client_addr, client_port, backend_start,
               xact_start, query_start, CASE WHEN wait_event IS NULL THEN false ELSE true END AS is_waiting,
               state = ''idle'' AS is_idle, state like ''%idle in transaction%'' AS is_idle_in_transaction, query ilike $$VACUUM%$$ as is_vacuum,
               client_port IS NULL AND (query like $$autovacuum:%$$ OR query like $$VACUUM%$$) as is_autovacuum,
               now() AS capture_time, wait_event, wait_event_type, query, state, state_change, application_name FROM pg_catalog.pg_stat_activity'
        WHERE probe_id = (SELECT id from pem.probe WHERE internal_name = 'session_info')
        AND server_version_id IN (11100, 11200, 11300, 11400, 11500, 11600, 21100, 21200, 21300, 21400, 21500, 21600);

    END IF;
  END;
  $DO$ LANGUAGE plpgsql;


  UPDATE pem.alert_template
    SET
    sql=$sql$
      SELECT	isz.index_size_mb::float * 100
                / CASE tsz.table_size_mb WHEN 0 THEN 1 ELSE tsz.table_size_mb END AS tbl_percentage
      FROM	pemdata.index_size AS isz
      JOIN	pemdata.oc_index AS oci
      ON		isz.server_id = oci.server_id
      AND		isz.database_name = oci.database_name
      AND		isz.schema_name = oci.schema_name
      AND		isz.index_name = oci.index_name
      JOIN	pemdata.table_size AS tsz
      ON		tsz.server_id = oci.server_id
      AND		tsz.database_name = oci.database_name
      AND		tsz.schema_name = oci.schema_name
      AND		tsz.table_name = oci.table_name
      WHERE	oci.server_id = ${server_id}
      AND     tsz.table_size_mb != 0
      ORDER BY tbl_percentage DESC
      LIMIT 1$sql$,
    info_sql=$SQL$
      SELECT	oci.server_id as "server_id",oci.database_name as "database_name",oci.schema_name as "schema_name",oci.table_name as "table_name",tsz.table_size_mb as "table_size",oci.index_name as "index_name",isz.index_size_mb as "index_size",isz.index_size_mb::float * 100
            / CASE tsz.table_size_mb WHEN 0 THEN 1 ELSE tsz.table_size_mb END AS "tbl_percentage"
      FROM	pemdata.index_size AS isz
      JOIN	pemdata.oc_index AS oci
      ON		isz.server_id = oci.server_id
      AND		isz.database_name = oci.database_name
      AND		isz.schema_name = oci.schema_name
      AND		isz.index_name = oci.index_name
      JOIN	pemdata.table_size AS tsz
      ON		tsz.server_id = oci.server_id
      AND		tsz.database_name = oci.database_name
      AND		tsz.schema_name = oci.schema_name
      AND		tsz.table_name = oci.table_name
      WHERE	oci.server_id = ${server_id}
      AND tsz.table_size_mb != 0
      ORDER BY tbl_percentage DESC
      LIMIT 1;
    $SQL$
  WHERE display_name = 'Largest index by table-size percentage' and object_type = 200;

  UPDATE pem.alert_template
      SET
      sql=$sql$
        SELECT	isz.index_size_mb::float * 100
                / CASE tsz.table_size_mb WHEN 0 THEN 1 ELSE tsz.table_size_mb END AS tbl_percentage
        FROM	pemdata.index_size AS isz
        JOIN	pemdata.oc_index AS oci
        ON		isz.server_id = oci.server_id
        AND		isz.database_name = oci.database_name
        AND		isz.schema_name = oci.schema_name
        AND		isz.index_name = oci.index_name
        JOIN	pemdata.table_size AS tsz
        ON		tsz.server_id = oci.server_id
        AND		tsz.database_name = oci.database_name
        AND		tsz.schema_name = oci.schema_name
        AND		tsz.table_name = oci.table_name
        WHERE	oci.server_id = ${server_id}
        AND     tsz.table_size_mb != 0
        AND		oci.database_name = '${database_name}'
        ORDER BY tbl_percentage DESC
        LIMIT 1$sql$,
      info_sql=$SQL$
      SELECT	oci.server_id as "server_id",oci.database_name as "database_name",oci.schema_name as "schema_name",oci.table_name as "table_name",tsz.table_size_mb as "table_size",oci.index_name as "index_name",isz.index_size_mb as "index_size",isz.index_size_mb::float * 100
            / CASE tsz.table_size_mb WHEN 0 THEN 1 ELSE tsz.table_size_mb END AS "tbl_percentage"
      FROM	pemdata.index_size AS isz
      JOIN	pemdata.oc_index AS oci
      ON		isz.server_id = oci.server_id
      AND		isz.database_name = oci.database_name
      AND		isz.schema_name = oci.schema_name
      AND		isz.index_name = oci.index_name
      JOIN	pemdata.table_size AS tsz
      ON		tsz.server_id = oci.server_id
      AND		tsz.database_name = oci.database_name
      AND		tsz.schema_name = oci.schema_name
      AND		tsz.table_name = oci.table_name
      WHERE	oci.server_id = ${server_id}
      AND		oci.database_name = '${database_name}'
      AND tsz.table_size_mb != 0
      ORDER BY tbl_percentage DESC
      LIMIT 1;
    $SQL$
  WHERE display_name = 'Largest index by table-size percentage' and object_type = 300;

  UPDATE pem.alert_template
      SET
      sql=$sql$
        SELECT	isz.index_size_mb::float * 100
                / CASE tsz.table_size_mb WHEN 0 THEN 1 ELSE tsz.table_size_mb END AS tbl_percentage
        FROM	pemdata.index_size AS isz
        JOIN	pemdata.oc_index AS oci
        ON		isz.server_id = oci.server_id
        AND		isz.database_name = oci.database_name
        AND		isz.schema_name = oci.schema_name
        AND		isz.index_name = oci.index_name
        JOIN	pemdata.table_size AS tsz
        ON		tsz.server_id = oci.server_id
        AND		tsz.database_name = oci.database_name
        AND		tsz.schema_name = oci.schema_name
        AND		tsz.table_name = oci.table_name
        WHERE	oci.server_id = ${server_id}
        AND     tsz.table_size_mb != 0
        AND		oci.database_name = '${database_name}'
        AND		oci.schema_name = '${schema_name}'
        ORDER BY tbl_percentage DESC
        LIMIT 1$sql$,
      info_sql=$SQL$
      SELECT	oci.server_id as "server_id",oci.database_name as "database_name",oci.schema_name as "schema_name",oci.table_name as "table_name",tsz.table_size_mb as "table_size",oci.index_name as "index_name",isz.index_size_mb as "index_size",isz.index_size_mb::float * 100
            / CASE tsz.table_size_mb WHEN 0 THEN 1 ELSE tsz.table_size_mb END AS "tbl_percentage"
      FROM	pemdata.index_size AS isz
      JOIN	pemdata.oc_index AS oci
      ON		isz.server_id = oci.server_id
      AND		isz.database_name = oci.database_name
      AND		isz.schema_name = oci.schema_name
      AND		isz.index_name = oci.index_name
      JOIN	pemdata.table_size AS tsz
      ON		tsz.server_id = oci.server_id
      AND		tsz.database_name = oci.database_name
      AND		tsz.schema_name = oci.schema_name
      AND		tsz.table_name = oci.table_name
      WHERE	oci.server_id = ${server_id}
      AND		oci.database_name = '${database_name}'
      AND		oci.schema_name = '${schema_name}'
      AND tsz.table_size_mb != 0
      ORDER BY tbl_percentage DESC
      LIMIT 1;
    $SQL$
  WHERE display_name = 'Largest index by table-size percentage' and object_type = 400;

END TRANSACTION;

