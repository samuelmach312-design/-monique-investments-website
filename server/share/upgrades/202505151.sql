/***************************************************************************
 *
 * Postgres Enterprise Manager
 *
 * Copyright (C) 2010 - 2025, EnterpriseDB Corporation. All rights reserved.
 *
 ***************************************************************************/

-- NOTE: This sql file is responsible for PEM 10.1.0 schema upgrade.

BEGIN TRANSACTION;
    CREATE
    OR REPLACE FUNCTION pem.schema_version()
    RETURNS integer AS 'SELECT 202505151::integer;' LANGUAGE 'sql' IMMUTABLE;
    COMMENT ON FUNCTION pem.schema_version()
    IS 'Returns the version number of the PEM schema';

    --PEM-5151: Make the jobs created by alert un-editable
    ALTER TABLE IF EXISTS pem.job
    ADD COLUMN IF NOT EXISTS is_alert_job BOOLEAN DEFAULT FALSE;

    --PEM-5541: Adding support for sending the webhook notification on job failure
    INSERT INTO pem.config (param, value, unit, datatype)
    SELECT 'job_notification_webhook_endpoint', '', '', 'string'
    WHERE NOT EXISTS (
        SELECT 1 FROM pem.config WHERE param = 'job_notification_webhook_endpoint'
    );

	ALTER TABLE pem.webhook_endpoints
    ADD COLUMN IF NOT EXISTS payload_type TEXT NOT NULL DEFAULT 'ALERT';

    ALTER TABLE pem.joblog
    ADD COLUMN IF NOT EXISTS jlgwebhookid INTEGER[];

    CREATE OR REPLACE FUNCTION pem.get_job_notification_settings(job_id integer, jlgstatus char)
	RETURNS TABLE (group_id INTEGER, webhook_ids INTEGER[]) AS
	$BODY$
	DECLARE
	    job RECORD;
	    agent RECORD;
	    job_failure_notification BOOLEAN;
	    job_status_change_notification BOOLEAN;
	    webhook_names TEXT;
	BEGIN
	    SELECT * INTO job FROM pem.job WHERE jobid = job_id;

	    IF job.notify = 'NEVER' OR (
	        job.notify = 'ON_FAILURE' AND jlgstatus NOT IN ('f', 'd')
	    ) THEN
	        RETURN;  -- No notification needed
	    END IF;

	    SELECT * INTO agent FROM pem.agent WHERE id = job.agent_id;

	    IF job.notify != 'DEFAULT' THEN
	        group_id := job.email_group_id;
	    ELSE
	        IF agent.job_notification_override_default IS TRUE THEN
	            IF agent.job_status_change_notification IS NOT TRUE AND
	               agent.job_failure_notification IS TRUE AND
	               jlgstatus NOT IN  ('f', 'd') THEN
	                RETURN;  -- No notification needed
	            END IF;
	            group_id := agent.job_notification_email_group_id;
	        ELSE
	            SELECT value::BOOLEAN INTO job_failure_notification
	            FROM pem.config WHERE param = 'job_failure_notification';

	            SELECT value::BOOLEAN INTO job_status_change_notification
	            FROM pem.config WHERE param = 'job_status_change_notification';

	            IF job_status_change_notification IS NOT TRUE AND
	               job_failure_notification IS TRUE AND
	               jlgstatus NOT IN ('f', 'd') THEN
	                RETURN;  -- No notification needed
	            END IF;

	            SELECT id INTO group_id
	            FROM pem.email_group
	            WHERE name = (
	                SELECT value FROM pem.config
	                WHERE param = 'job_notification_email_group'
	                LIMIT 1
	            );
	        END IF;
	    END IF;

	    -- Fetch webhook names from config
	    SELECT value INTO webhook_names
	    FROM pem.config
	    WHERE param = 'job_notification_webhook_endpoint'
	    LIMIT 1;

	    -- Fetch webhook IDs based on the webhook names (converted to an array)
	    SELECT ARRAY(
            SELECT id
            FROM pem.webhook_endpoints
            WHERE TRIM(name) = ANY(
                SELECT TRIM(value)
                FROM unnest(string_to_array(webhook_names, ',')) AS value
            )
            AND payload_type = 'JOB'
        ) INTO webhook_ids;

	    -- Return both group_id and webhook_ids array
	    RETURN NEXT;
	END;
	$BODY$
	LANGUAGE plpgsql;

    CREATE OR REPLACE FUNCTION pem.construct_webhook_payload(
    job_id integer,
    agent_id integer,
    status char,
    steps text[],
    jobname text,
    jobdesc text,
    start_time timestamp with time zone,
    duration interval,
    webhook_id integer  -- Added webhook_id as parameter
    ) RETURNS TEXT AS
    $BODY$
    DECLARE
        payload TEXT;
		steps_json TEXT;
    BEGIN
        -- Fetch the payload template using the provided webhook_id
        SELECT payload_template INTO payload
        FROM pem.webhook_endpoints
        WHERE id = webhook_id;

        -- Replace placeholders with actual values in the payload
        payload := pem.replace_json_params(payload, '%id%', job_id::text, 'g');
        payload := pem.replace_json_params(payload, '%name%', jobname, 'g');
        payload := pem.replace_json_params(payload, '%status%', status, 'g');
        payload := pem.replace_json_params(payload, '%agent_desc%', (SELECT description FROM pem.agent WHERE id = agent_id), 'g');
        payload := pem.replace_json_params(payload, '%agent_id%', agent_id::text, 'g');
        payload := pem.replace_json_params(payload, '%steps_info%', jsonb_pretty(to_jsonb(steps)), 'g');
        RETURN payload;
    END;
    $BODY$
    LANGUAGE plpgsql;

    CREATE OR REPLACE FUNCTION pem.get_job_steps(job_id integer, log_id integer) RETURNS TEXT[] AS
    $BODY$
    DECLARE
        jobsteps_cur REFCURSOR;
        jobstep RECORD;
        steps TEXT[] := '{}';
        email_template_message TEXT;
        email_template_message_server TEXT;
    BEGIN
        SELECT
            mail_message
        INTO email_template_message
        FROM pem.get_email_template('Job Step');

        SELECT
            mail_message
        INTO email_template_message_server
        FROM pem.get_email_template('Job Step (Database Server)');

        OPEN jobsteps_cur FOR EXECUTE '
            SELECT
                jst.*, jstlog.*,
                s.description AS server_desc,
                s.server AS server_host,
                s.port AS server_port,
                s.active AS server_active,
                s.hostaddr AS server_hostaddr
            FROM
                pem.jobstep jst
            LEFT JOIN
                pem.jobsteplog jstlog ON (jst.jstid = jstlog.jsljstid)
            LEFT JOIN
                pem.server s ON (jst.server_id = s.id)
            WHERE
                jst.jstjobid = $1::integer
                AND (jstlog.jsljlgid = $2::integer OR jstlog.jsljlgid IS NULL)
            ORDER BY
                jstlog.jslstart;' USING job_id, log_id;

        LOOP
            FETCH NEXT FROM jobsteps_cur INTO jobstep;
            EXIT WHEN NOT FOUND;

            IF jobstep.server_id IS NULL THEN
                steps := steps || pem.substitute_jobstep_info(
                    email_template_message, row_to_json(jobstep)
                );
            ELSE
                steps := steps || pem.substitute_jobstep_info(
                    email_template_message_server, row_to_json(jobstep)
                );
            END IF;
        END LOOP;
        CLOSE jobsteps_cur;
        RETURN steps;
    END;
    $BODY$
    LANGUAGE plpgsql;

    CREATE OR REPLACE FUNCTION pem.joblog_status_update()
	RETURNS TRIGGER AS
	$BODY$
	DECLARE
	    group_id INTEGER;
	    webhook_ids INTEGER[];
	    job RECORD;
	    agent RECORD;
	    status_info RECORD;
	    steps TEXT[];
	    subject TEXT;
	    message TEXT;
	    payload TEXT;
	    success_status BOOLEAN;
		webhook_inserted_id INTEGER;
	    inserted_id INTEGER;
	    webhook_results INTEGER[] := '{}';  -- Store successful webhook IDs
	BEGIN
	    -- Skip update if the job is still running
	    IF NEW.jlgstatus = 'r' OR NEW.jlgstatus IS NULL THEN
	        RETURN NEW;
	    END IF;

	    NEW.jlgemailsent := FALSE;
	    NEW.jlgwebhookid := NULL;  -- Clear previous webhook ID(s)

	    -- Notify only if the status has changed
	    IF NEW.jlgstatus != OLD.jlgstatus THEN
	        -- Get job details
	        SELECT * INTO job FROM pem.job WHERE jobid = NEW.jlgjobid;

	        -- Get notification settings (email group and webhook IDs)
	        SELECT ns.group_id, ns.webhook_ids
	        INTO group_id, webhook_ids
	        FROM pem.get_job_notification_settings(NEW.jlgjobid, NEW.jlgstatus) AS ns;

	        -- If no email or webhook notification is needed, exit
	        IF group_id IS NULL AND webhook_ids IS NULL THEN
	            RETURN NEW;
	        END IF;

	        -- Get agent details
	        SELECT * INTO agent FROM pem.agent WHERE id = job.agent_id;

	        -- Get job steps
	        steps := pem.get_job_steps(NEW.jlgjobid, NEW.jlgid);

	        -- Fetch email templates
	        SELECT mail_subject, mail_message
	        INTO subject, message
	        FROM pem.get_email_template(CASE NEW.jlgstatus
	            WHEN 'd' THEN 'Job Cancellation'
	            WHEN 'f' THEN 'Job Failure'
	            ELSE 'Job Success'
	        END);

	        -- Loop over webhook IDs and send webhooks
	        IF webhook_ids IS NOT NULL AND array_length(webhook_ids, 1) IS NOT NULL THEN
			    FOR i IN 1..array_length(webhook_ids, 1) LOOP
			        -- Construct webhook payload
			        payload := pem.construct_webhook_payload(
			            NEW.jlgjobid, agent.id, NEW.jlgstatus, steps,
			            job.jobname, job.jobdesc, NEW.jlgstart, NEW.jlgduration, webhook_ids[i]
			        );

			        -- Send webhook and capture result
			        -- setting the alert_id as -1 since this is for job and not for alert.
					SELECT * INTO success_status, webhook_inserted_id
           	 		FROM pem.send_webhook(webhook_ids[i], -1, agent.id, payload);

			        -- Only store successful webhook IDs
			        IF success_status THEN
			            webhook_results := array_append(webhook_results, webhook_inserted_id);
			        END IF;
			    END LOOP;


	            -- ✅ Update joblog with all successfully inserted webhook IDs
	            UPDATE pem.joblog
	            SET jlgwebhookid =
	                CASE
	                    WHEN webhook_results IS NULL OR array_length(webhook_results, 1) IS NULL THEN NULL
	                    ELSE webhook_results
	                END
	            WHERE jlgid = NEW.jlgid;

	            -- ✅ Store webhook IDs in NEW for return
	            NEW.jlgwebhookid := webhook_results;
	        END IF;

	        -- Prepare email status info
	        SELECT
	            NEW.jlgstatus AS status,
	            NEW.jlgstart AS start_time,
	            NEW.jlgduration AS duration,
	            array_length(steps, 1) AS no_steps,
	            array_to_string(steps, E'\n', '') AS steps
	        INTO status_info;

	        -- Substitute job info into email templates
	        subject := pem.substitute_job_info(subject, row_to_json(job), row_to_json(agent), row_to_json(status_info));
	        message := pem.substitute_job_info(message, row_to_json(job), row_to_json(agent), row_to_json(status_info));

	        -- Send email notification
	        NEW.jlgemailsent := pem.send_email(ARRAY[group_id], subject, message);
	        IF NEW.jlgemailsent THEN
                -- update the jlgemailsent column in pem.joblog tabel.
                UPDATE pem.joblog SET jlgemailsent = NEW.jlgemailsent WHERE jlgid = NEW.jlgid;
			END IF;
	    END IF;

	    RETURN NEW;
	END;
	$BODY$
	LANGUAGE plpgsql VOLATILE;

    COMMENT ON TRIGGER joblog_status_update ON pem.joblog IS
	'Determine whether to send a SMTP email or Webhook notification on job completion. If yes, then '
	'draft an email or webhook payload and put it in the smtp_spool/webhook_spool table.';

    DROP FUNCTION pem.send_webhook(integer,integer,integer,text);

	CREATE OR REPLACE FUNCTION pem.send_webhook(webhook_id int, alert_id int, agent_id int, payload text)
    RETURNS TABLE(success boolean, inserted_id int) AS $$
    DECLARE
        new_id int;
    BEGIN
        -- Insert the spool record and get the new ID
        INSERT INTO pem.webhook_spool(webhook_id, alert_id, agent_id, payload, sent_status)
        VALUES (webhook_id, alert_id, agent_id, payload, 'u')
        RETURNING id INTO new_id;

        -- Notify listener
        NOTIFY WEBHOOK_SPOOL;

        -- Correctly return values
        RETURN QUERY SELECT TRUE, new_id;
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
                            PERFORM pem.send_webhook(webhook_ids[idx], NEW.alert_id, agentid, payload);
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
                            PERFORM pem.send_webhook(webhook_ids[idx], NEW.alert_id, agentid, payload);
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

    -- Creating a trigger function to clear the webhook ids if the payload type is changed to JOB
    CREATE OR REPLACE FUNCTION pem.cleanup_webhook_ids()
    RETURNS TRIGGER AS $$
    BEGIN
        -- Check if payload_type is being updated from 'ALERT' to 'JOB'
        IF OLD.payload_type = 'ALERT' AND NEW.payload_type = 'JOB' THEN
            -- Remove webhook id from all webhook_id columns in the relevant table
            UPDATE pem.webhook_alert_config
            SET
                low_webhook_ids = array_remove(low_webhook_ids, OLD.id),
                med_webhook_ids = array_remove(med_webhook_ids, OLD.id),
                high_webhook_ids = array_remove(high_webhook_ids, OLD.id),
                cleared_webhook_ids = array_remove(cleared_webhook_ids, OLD.id)
            WHERE OLD.id = ANY(low_webhook_ids)
               OR OLD.id = ANY(med_webhook_ids)
               OR OLD.id = ANY(high_webhook_ids)
               OR OLD.id = ANY(cleared_webhook_ids);
        END IF;
        RETURN NEW;
    END;
    $$ LANGUAGE plpgsql;

     -- Added a column post_connection_sql in the server table
    DO $$
    BEGIN
        IF NOT EXISTS (
            SELECT 1
            FROM information_schema.columns
            WHERE table_name = 'server'
            AND table_schema = 'pem'
            AND column_name = 'post_connection_sql'
        ) THEN
            ALTER TABLE pem.server
            ADD COLUMN post_connection_sql text DEFAULT ''::text;
        END IF;
    END $$;

    -- Drop existing trigger as we do not have create/replace trigger.
    DROP TRIGGER IF EXISTS webhook_cleanup_trigger on pem.webhook_endpoints;

    -- Trigger to identify which webhook_id's payload_type is updated
    CREATE TRIGGER webhook_cleanup_trigger
    AFTER UPDATE OF payload_type ON pem.webhook_endpoints
    FOR EACH ROW
    EXECUTE FUNCTION pem.cleanup_webhook_ids();

    -- PEM-5542: Modifying the pem.chart_func table query for the 'Failover Manager Cluster Info' chart
    UPDATE pem.chart_func
    SET func = $SQL$
    SELECT property AS "Property", value AS "Value"
    FROM pemdata.efm_cluster_info pe
    LEFT JOIN pem.server ps ON ps.id = pe.server_id
    CROSS JOIN LATERAL (
    VALUES
        ('Cluster Name', ps.efm_cluster_name),
        ('Failover Manager Agent Running Status', CASE WHEN pe.efm_running = true THEN 'UP' ELSE 'DOWN' END),
        ('Allowed Node List', array_to_string(pe.efm_allowed_node_list, ', ')),
        ('Replica Priority List', array_to_string(pe.efm_standby_priority_list, ', ')),
        ('Missing Nodes', array_to_string(pe.efm_missing_nodes, ', ')),
        ('Minimum Standbys', pe.efm_minimum_standbys::text),
        ('Membership Coordinator', pe.efm_membership_coordinator),
        ('Cluster Status Message', pe.efm_messages)
    ) AS info(property, value)
    WHERE pe.server_id = %(server_id)s::int4;$SQL$
    WHERE id = 89;

    -- PEM-5560 Patroni Cluster and Node Status Probes
    -- =================================================
    -- Add new columns to the server table for Patroni
    -- =================================================
    ALTER TABLE pem.server
    ADD COLUMN IF NOT EXISTS replication_solution text DEFAULT ''::text,
    ADD COLUMN IF NOT EXISTS patroni_installation_path text NULL,
    ADD COLUMN IF NOT EXISTS patroni_cluster_name text NULL,
    ADD COLUMN IF NOT EXISTS patroni_config_path text NULL;

    COMMENT ON COLUMN pem.server.replication_solution IS 'Replication solution used by the server.';
    COMMENT ON COLUMN pem.server.patroni_installation_path IS 'Optional path to the patronictl executable if not in standard PATH.';
    COMMENT ON COLUMN pem.server.patroni_cluster_name IS 'The name of the Patroni cluster to monitor (used by patronictl).';
    COMMENT ON COLUMN pem.server.patroni_config_path IS 'Optional path to the patroni.yml configuration file used by the patronictl command run by the agent.';

    DROP VIEW IF EXISTS pem.avail_servers;

    CREATE VIEW pem.avail_servers AS
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
            s.owner::regrole::name AS server_owner,
            s.is_remote_monitoring AS is_remote_monitoring,
            s.replication_solution AS replication_solution,
            s.efm_cluster_name AS efm_cluster_name,
            s.efm_service_name AS efm_service_name,
            s.efm_installation_path AS efm_installation_path,
            s.patroni_installation_path AS patroni_installation_path,
            s.patroni_cluster_name AS patroni_cluster_name,
            s.patroni_config_path AS patroni_config_path,
            COALESCE(so.server_group_id, s.group_id, 1) AS group_id
        FROM pem.server s
            LEFT JOIN pem.server_options so ON (s.id = so.server_id AND pem_user = current_user)
        WHERE
            -- Only active servers
            s.active AND
            pem.can_access_team(s.owner, s.team);

    -- ==================================
    -- Probe: Patroni Cluster Status
    -- ==================================
    DO $DO$
	BEGIN
	    IF NOT EXISTS (SELECT id FROM pem.probe where internal_name = 'patroni_cluster_status') THEN
	
	        INSERT INTO pem.probe
	                (display_name, internal_name, collection_method, target_type_id,
	                agent_capability, enabled_by_default, force_enabled,
	                default_execution_frequency, default_lifetime, any_server_version, probe_code)
	        VALUES	
	            ('Patroni Cluster Status', 'patroni_cluster_status', 'i', 200, NULL, false, false, 300,
	                7, false, 'patroni_cluster_status');
	
	        INSERT INTO pem.probe_column
	                (probe_id, internal_name, display_name, display_position, classification,
	                sql_data_type, unit_of_value, calculate_pit, discard_history, pit_by_default, is_graphable)
	        SELECT
	                (SELECT id FROM pem.probe WHERE probe_code = 'patroni_cluster_status'),
	                v.internal_name, v.display_name, v.display_position, v.classification,
	                v.sql_data_type, v.unit_of_value, v.calculate_pit, v.discard_history, v.pit_by_default, v.is_graphable
	        FROM
	                (VALUES
	                ('cluster_name',         'Cluster Name',          1, 'm', 'text',    '', false, false, false, false),
	                ('timeline',             'Timeline',              2, 'm', 'text',    '', false, false, false, false),
	                ('leader_member_name',   'Leader Member Name',    3, 'm', 'text',    '', false, false, false, false),
	                ('leader_host',          'Leader Host',           4, 'm', 'text',    '', false, false, false, false),
	                ('dcs_healthy',          'DCS Healthy',           5, 'm', 'boolean', '', false, false, false, false),
	                ('patroni_down',         'Patroni Down',          6, 'm', 'boolean', '', false, false, false, false),
	                ('cluster_paused',       'Cluster Paused',        7, 'm', 'boolean', '', false, false, false, false)
	                ) v(internal_name, display_name, display_position, classification,
	                        sql_data_type, unit_of_value, calculate_pit, discard_history, pit_by_default, is_graphable);
	
	        INSERT INTO pem.probe_server_version
	            (probe_id, server_version_id, probe_code)
	        SELECT
	                (SELECT id FROM pem.probe WHERE probe_code = 'patroni_cluster_status'), v.version, NULL
	        FROM (
	            VALUES (10902), (10903), (10904), (10905), (10906), (11000), (11100),
	                (11200), (11300), (11400), (11500), (11600), (11700),
	                (20902), (20903), (20904), (20905), (20906), (21000), (21100),
	                (21200), (21300), (21400), (21500), (21600), (21700)
	        ) v(version);
	    END IF;
	
	    -- ==================================
	    -- Probe: Patroni Node Status
	    -- ==================================
	
	    IF NOT EXISTS (SELECT id FROM pem.probe where internal_name = 'patroni_node_status') THEN
	
	        INSERT INTO pem.probe
	                (display_name, internal_name, collection_method, target_type_id,
	                agent_capability, enabled_by_default, force_enabled,
	                default_execution_frequency, default_lifetime, any_server_version, probe_code)
	        VALUES	
	            ('Patroni Node Status', 'patroni_node_status', 'i', 200, NULL, false, false, 300,
	                7, false, 'patroni_node_status');
	
	        INSERT INTO pem.probe_column
	                (probe_id, internal_name, display_name, display_position, classification,
	                sql_data_type, unit_of_value, calculate_pit, discard_history, pit_by_default, is_graphable)
	        SELECT
	                (SELECT id FROM pem.probe WHERE probe_code = 'patroni_node_status'),
	                v.internal_name, v.display_name, v.display_position, v.classification,
	                v.sql_data_type, v.unit_of_value, v.calculate_pit, v.discard_history, v.pit_by_default, v.is_graphable
	        FROM
	                (VALUES
	                ('cluster_name',       'Cluster Name',        1, 'm', 'text',    '', false, false, false, false),
	                ('member_name',        'Member Name',         2, 'm', 'text',    '', false, false, false, false),
	                ('host',               'Host',                3, 'k', 'text',    '', false, false, false, false),
	                ('role',               'Role',                4, 'm', 'text',    '', false, false, false, false),
	                ('state',              'State',               5, 'm', 'text',    '', false, false, false, false),
	                ('timeline',           'Timeline',            6, 'm', 'text',    '', false, false, false, false),
	                ('replication_lag_mb', 'Replication Lag (MB)',7, 'm', 'text',    '', false, false, false, false)
	                ) v(internal_name, display_name, display_position, classification,
	                        sql_data_type, unit_of_value, calculate_pit, discard_history, pit_by_default, is_graphable);
	
	        INSERT INTO pem.probe_server_version
	            (probe_id, server_version_id, probe_code)
	        SELECT
	                (SELECT id FROM pem.probe WHERE probe_code = 'patroni_node_status'), v.version, NULL
	        FROM (
	            VALUES (10902), (10903), (10904), (10905), (10906), (11000), (11100),
	                (11200), (11300), (11400), (11500), (11600), (11700),
	                (20902), (20903), (20904), (20905), (20906), (21000), (21100),
	                (21200), (21300), (21400), (21500), (21600), (21700)
	        ) v(version);
	    END IF;
	
	    PERFORM pem.create_data_and_history_tables();
	END;
    $DO$ LANGUAGE 'plpgsql';

    -- Set the replication solution to 'efm' for servers with EFM cluster name and installation path
    UPDATE pem.server
    SET replication_solution = 'efm'
    WHERE
    COALESCE(NULLIF(TRIM(efm_cluster_name), ''), '') <> ''
    AND COALESCE(NULLIF(TRIM(efm_installation_path), ''), '') <> '';

    DO $$
    BEGIN
        -- ================================================
        -- Alert Templates for Patroni Monitoring in PEM
        -- ================================================
        -- PEM-5572: Create alert templates and charts for patroni
        -- 1. Timeline Mismatch
        IF NOT EXISTS (SELECT 1 FROM pem.alert_template WHERE display_name = 'Patroni timeline mismatch' AND is_system_template) THEN
            PERFORM pem.create_alert_template(
                'Patroni timeline mismatch',
                'Detects if node timeline does not match cluster timeline',
                $sql$
                SELECT
                    CASE WHEN COUNT(*) > 0 THEN 1 ELSE 0 END AS current_value,
                    CASE WHEN COUNT(*) > 0 THEN 'Timeline Mismatch' ELSE 'No Mismatch' END AS display_value
                FROM
                    pemdata.patroni_node_status pns
                JOIN
                    pemdata.patroni_cluster_status pcs ON pns.cluster_name = pcs.cluster_name
                WHERE
                    pns.timeline::int <> pcs.timeline::int
                    AND pns.server_id = ${server_id};
                $sql$,
                200, NULL, NULL, NULL, 'STATE',
                '{patroni_node_status, patroni_cluster_status}', 
                (SELECT COALESCE(MAX(snmp_oid), 0) + 1 FROM pem.alert_template WHERE object_type = 200),
                'ALL', 1, 30, true,
                $SQL$
                SELECT pns.member_name AS "Node", pns.timeline AS "Node TL", pcs.timeline AS "Cluster TL"
                FROM pemdata.patroni_node_status pns
                JOIN pemdata.patroni_cluster_status pcs ON pns.cluster_name = pcs.cluster_name
                WHERE pns.timeline::int <> pcs.timeline::int AND pns.server_id = ${server_id};
                $SQL$
            );
        END IF;

        -- 2. DCS Not Healthy
        IF NOT EXISTS (SELECT 1 FROM pem.alert_template WHERE display_name = 'Patroni DCS not healthy' AND is_system_template) THEN
            PERFORM pem.create_alert_template(
                'Patroni DCS not healthy',
                'Detects if the distributed configuration store (etcd) is not healthy',
                $sql$
                SELECT
                    CASE WHEN dcs_healthy IS FALSE THEN 1 ELSE 0 END AS current_value,
                    CASE WHEN dcs_healthy IS FALSE THEN 'DOWN' ELSE 'UP' END AS display_value
                FROM
                    pemdata.patroni_cluster_status
                WHERE
                    server_id = ${server_id};
                $sql$,
                200, NULL, NULL, NULL, 'STATE',
                '{patroni_cluster_status}', 
                (SELECT COALESCE(MAX(snmp_oid), 0) + 1 FROM pem.alert_template WHERE object_type = 200),
                'ALL', 1, 30, true
            );
        END IF;

        -- 3. Patroni Down or Out of Contact
        IF NOT EXISTS (SELECT 1 FROM pem.alert_template WHERE display_name = 'Patroni down or out of contact' AND is_system_template) THEN
            PERFORM pem.create_alert_template(
                'Patroni down or out of contact',
                'Detects if the Patroni process is not reachable or has failed on a monitored node',
                $sql$
                SELECT
                    CASE WHEN patroni_down IS TRUE THEN 1 ELSE 0 END AS current_value,
                    CASE WHEN patroni_down IS TRUE THEN 'DOWN' ELSE 'UP' END AS display_value
                FROM
                    pemdata.patroni_cluster_status
                WHERE
                    server_id = ${server_id};
                $sql$,
                200, NULL, NULL, NULL, 'STATE',
                '{patroni_cluster_status}', 
                (SELECT COALESCE(MAX(snmp_oid), 0) + 1 FROM pem.alert_template WHERE object_type = 200),
                'ALL', 1, 30, true,
                $SQL$
                SELECT cluster_name AS "Cluster", patroni_down AS "Patroni Down"
                FROM pemdata.patroni_cluster_status
                WHERE server_id = ${server_id};
                $SQL$
            );
        END IF;

        -- 4. No Master Detected
        IF NOT EXISTS (SELECT 1 FROM pem.alert_template WHERE display_name = 'Patroni no leader detected' AND is_system_template) THEN
            PERFORM pem.create_alert_template(
                'Patroni no leader detected',
                'Detects when Patroni cluster has no leader/master node',
                $sql$
                SELECT
                    CASE WHEN leader_member_name IS NULL OR leader_member_name = '' THEN 1 ELSE 0 END AS current_value,
                    CASE
                        WHEN leader_member_name IS NULL OR leader_member_name = '' THEN 'No Leader'
                        ELSE 'Leader Present'
                    END AS display_value
                FROM
                    pemdata.patroni_cluster_status
                WHERE
                    server_id = ${server_id}
                    AND dcs_healthy IS TRUE
                    AND patroni_down IS FALSE;
                $sql$,
                200, NULL, NULL, NULL, 'STATE',
                '{patroni_cluster_status}', 
                (SELECT COALESCE(MAX(snmp_oid), 0) + 1 FROM pem.alert_template WHERE object_type = 200),
                'ALL', 1, 30, true
            );
        END IF;

        -- 5. Cluster is Paused
        IF NOT EXISTS (SELECT 1 FROM pem.alert_template WHERE display_name = 'Patroni cluster paused' AND is_system_template) THEN
            PERFORM pem.create_alert_template(
                'Patroni cluster paused',
                'Detects if the Patroni cluster is paused and unavailable for failover',
                $sql$
                SELECT
                    CASE WHEN cluster_paused IS TRUE THEN 1 ELSE 0 END AS current_value,
                    CASE
                        WHEN cluster_paused IS TRUE THEN 'PAUSED'
                        ELSE 'ACTIVE'
                    END AS display_value
                FROM
                    pemdata.patroni_cluster_status
                WHERE
                    server_id = ${server_id};
                $sql$,
                200, NULL, NULL, NULL, 'STATE',
                '{patroni_cluster_status}', 
                (SELECT COALESCE(MAX(snmp_oid), 0) + 1 FROM pem.alert_template WHERE object_type = 200),
                'ALL', 1, 30, true,
                $SQL$
                SELECT cluster_name AS "Cluster", cluster_paused AS "Cluster Paused"
                FROM pemdata.patroni_cluster_status
                WHERE server_id = ${server_id};
                $SQL$
            );
        END IF;
    END;
    $$ LANGUAGE 'plpgsql';
    --
    -- Patroni Node Status
    -- This chart is used to show the Patroni Node Status

  	INSERT INTO pem.config (param, value, unit, datatype)
    	SELECT 'dash_patroni_timeout', 300, 'seconds', 'integer'
    	WHERE NOT EXISTS (
        	SELECT 1 FROM pem.config WHERE param = 'dash_patroni_timeout'
    	);

    INSERT INTO pem.chart_func(id, type, func, r_sys_obj, dep_probes) VALUES
    (113, 'Q', E'
    SELECT
        cluster_name AS "Cluster Name",
        member_name AS "Member Name",
        host AS "Host",
        role AS "Role",
        state AS "State",
        timeline AS "Timeline",
        replication_lag_mb AS "Replication Lag (MB)"
    FROM
        pemdata.patroni_node_status
    WHERE server_id = %(server_id)s::int4;', false, '{patroni_node_status}')
	ON CONFLICT DO NOTHING;

    INSERT INTO pem.chart(id, cid, fid, type, level, name, owner, shared, ref_cnt, reload, summary, labels, params, rwlimit_span_param, ref_timeout_param) VALUES
        (113, 15, 113, 'TB', ARRAY[200], 'Patroni Node Status', 0, NULL, 1, 50000, NULL, NULL, ARRAY['server_id'], NULL, 'dash_patroni_timeout')
		ON CONFLICT DO NOTHING;

    -- Patroni Cluster Status
    -- This chart is used to show the Patroni Cluster Status
    INSERT INTO pem.chart_func(id, type, func, r_sys_obj, dep_probes) VALUES
    (114, 'Q', E'
    SELECT property AS "Property", value AS "Value"
        FROM pemdata.patroni_cluster_status pcs
        LEFT JOIN pem.server ps ON ps.id = pcs.server_id
        CROSS JOIN LATERAL (
        VALUES
        (''Cluster name'', pcs.cluster_name),
        (''Timeline'', pcs.timeline::text),
        (''Leader member name'', pcs.leader_member_name),
        (''Leader host'', pcs.leader_host),
        (''DCS healthy?'', CASE WHEN pcs.dcs_healthy THEN ''Yes'' ELSE ''No'' END),
        (''Patroni down?'', CASE WHEN pcs.patroni_down THEN ''Yes'' ELSE ''No'' END),
        (''Cluster paused?'', CASE WHEN pcs.cluster_paused THEN ''Yes'' ELSE ''No'' END)
        ) AS info(property, value)
        WHERE pcs.server_id = %(server_id)s::int4;', false, '{patroni_cluster_status}')
		ON CONFLICT DO NOTHING;

    INSERT INTO pem.chart(id, cid, fid, type, level, name, owner, shared, ref_cnt, reload, summary, labels, params, rwlimit_span_param, ref_timeout_param) VALUES
        (114, 15, 114, 'TB', ARRAY[200], 'Patroni Cluster Info', 0,  NULL,  1, 50000,   NULL, NULL, ARRAY['server_id'], NULL, 'dash_patroni_timeout')
		ON CONFLICT DO NOTHING;

	DO $DO$
	DECLARE
	    temp text;
	BEGIN
	    IF NOT EXISTS (SELECT 1 FROM pem.roles WHERE component = 'manage_patroni' ) THEN
	    -- Create a role for managing the Patroni functionalities
	    SELECT pem.create_role_for(
	        'manage_patroni',
	        'Role to manage the patroni functionalities',
	        ARRAY['pem_admin']
	        ) into temp;
	    END IF;
	END;
	$DO$ LANGUAGE 'plpgsql';

    GRANT pem_manage_schedule_task TO pem_manage_patroni;

    -- PEM-5577: Allow users to include agents in clusters from UI
	CREATE OR REPLACE FUNCTION pem.delete_cluster(_id integer)
	RETURNS boolean AS
	$$
	DECLARE
		v_parent_id integer;
	BEGIN
        SELECT parent_id INTO v_parent_id FROM pem.server_group WHERE id = _id;
        IF v_parent_id IS NULL THEN
            RAISE EXCEPTION 'Cluster not found';
        END IF;

        UPDATE pem.server SET group_id = v_parent_id WHERE group_id = _id;
        UPDATE pem.server_options SET server_group_id = v_parent_id WHERE server_group_id = _id;

        UPDATE pem.agent SET group_id = v_parent_id WHERE group_id = _id;
        UPDATE pem.agent_options SET group_id = v_parent_id WHERE group_id = _id;
        DELETE FROM pem.server_group WHERE id = _id;

        RETURN true;
    END$$ LANGUAGE 'plpgsql' SECURITY DEFINER;

    -- PEM-5559: Added a Probe to fetch the PGD Roles
    DO $DO$
    BEGIN
        IF NOT EXISTS (SELECT id FROM pem.probe where internal_name = 'bdr_node_roles') THEN
            INSERT INTO pem.probe
            (display_name, internal_name, collection_method, target_type_id,
             enabled_by_default, force_enabled, default_execution_frequency,
             default_lifetime, any_server_version, probe_code, extension_name)
            VALUES
                ('PGD Node Roles', 'bdr_node_roles', 's', 1000, false, false, 60, 30, true,
                $sql$
                WITH roles AS (
                SELECT
                    ln.node_name, NULL AS group_name, ln.node_kind_name AS role_in_group
                FROM bdr.local_node_summary ln
                UNION
                SELECT
                    ln.node_name, r.node_group_name AS group_name, 'write leader' AS role_in_group
                FROM bdr.local_node_summary ln
                JOIN bdr.node_group_routing_summary r
                    ON ln.node_name = r.write_lead
                UNION
                SELECT
                    ln.node_name, raft.node_group_name AS group_name, raft.state AS role_in_group
                FROM bdr.local_node_summary ln
                JOIN bdr.group_raft_details raft
                    ON ln.node_name = raft.node_name
            ),
            grouped_roles AS (
                SELECT
                    node_name, group_name, array_agg(role_in_group) AS roles
                FROM roles
                GROUP BY node_name, group_name
            ),
            json_agg_roles AS (
                SELECT node_name, jsonb_object_agg(COALESCE(group_name, 'nogroup'), roles) AS roles_by_group
                FROM grouped_roles
                GROUP BY node_name
            )
            SELECT * FROM json_agg_roles;$sql$, 'bdr');

            INSERT INTO pem.probe_column
                    (probe_id, internal_name, display_name, display_position, classification,
                    sql_data_type, unit_of_value, calculate_pit, discard_history, pit_by_default, is_graphable)
            SELECT
                    (SELECT max(id) FROM pem.probe),
                    v.internal_name, v.display_name, v.display_position, v.classification,
                    v.sql_data_type, v.unit_of_value, v.calculate_pit, v.discard_history, v.pit_by_default, v.is_graphable
            FROM
                    (VALUES
                    ('node_name',  'Node name',  1, 'k', 'text',    '',   false, false, false, false),
                    ('roles_by_group', 'Roles by group', 2, 'm', 'jsonb',    '',   false, false, false, false)
                    ) v(internal_name, display_name, display_position, classification,
                            sql_data_type, unit_of_value, calculate_pit, discard_history, pit_by_default, is_graphable);

            PERFORM pem.create_data_and_history_tables();
        END IF;
    END;
    $DO$ LANGUAGE 'plpgsql';

    CREATE OR REPLACE FUNCTION pem.update_tags_from_bdr_roles()
    RETURNS TRIGGER AS $$
    DECLARE
        k text;
        v text;
        tag_color text;
    BEGIN
        -- Step 1: Remove old tags on DELETE or UPDATE
        IF TG_OP IN ('DELETE', 'UPDATE') AND OLD.roles_by_group IS NOT NULL THEN
            UPDATE pem.server
            SET tags = COALESCE((
                SELECT jsonb_agg(tag_elem)
                FROM jsonb_array_elements(COALESCE(tags, '[]'::jsonb)) AS tag_elem
                WHERE NOT EXISTS (
                    SELECT 1
                    FROM jsonb_each(OLD.roles_by_group) AS e(old_k, old_v)
                    CROSS JOIN jsonb_array_elements_text(old_v) AS val
                    WHERE old_k != 'nogroup'
                    AND LOWER(val) NOT IN ('raft_follower', 'data', 'shadow')
                    AND tag_elem->>'text' = old_k || ': ' || initcap(val)
                )
            ), '[]'::jsonb)
            WHERE id = OLD.server_id;
        END IF;

        -- Step 2: Add new tags on INSERT or UPDATE
        IF TG_OP IN ('INSERT', 'UPDATE') AND NEW.roles_by_group IS NOT NULL THEN
            FOR k, v IN
                SELECT new_k, val
                FROM jsonb_each(NEW.roles_by_group) AS e(new_k, new_v)
                CROSS JOIN jsonb_array_elements_text(new_v) AS val
                WHERE new_k != 'nogroup'
                AND LOWER(val) NOT IN ('raft_follower', 'data', 'shadow')
            LOOP
                -- Determine tag color
                IF LOWER(v) = 'write leader' THEN
                    tag_color := '#008000';  -- green
                ELSE
                    tag_color := '#737373';  -- grey
                END IF;
                UPDATE pem.server
                SET tags = COALESCE(tags, '[]'::jsonb) || jsonb_build_array(
                    jsonb_build_object(
                        'text', k || ': ' || initcap(v),
                        'color', tag_color
                    )
                )
                WHERE id = NEW.server_id
                AND NOT EXISTS (
                    SELECT 1
                    FROM jsonb_array_elements(COALESCE(tags, '[]'::jsonb)) AS tag_check
                    WHERE tag_check->>'text' = k || ': ' || initcap(v)
                );
            END LOOP;
        END IF;

        RETURN COALESCE(NEW, OLD);
    END;
    $$ LANGUAGE plpgsql;

    DROP TRIGGER IF EXISTS bdr_roles_tags_update_trigger ON pemdata.bdr_node_roles;

    CREATE TRIGGER bdr_roles_tags_update_trigger
    AFTER INSERT OR UPDATE OR DELETE ON pemdata.bdr_node_roles
    FOR EACH ROW
    EXECUTE FUNCTION pem.update_tags_from_bdr_roles();

    -- Removing the tags with name primary if the servers has bdr extension installed
    UPDATE pem.server s
    SET tags = COALESCE((
        SELECT jsonb_agg(tag_elem)
        FROM jsonb_array_elements(s.tags) AS tag_elem
        WHERE tag_elem->>'text' IS DISTINCT FROM 'primary'
    ), '[]'::jsonb)
    WHERE EXISTS (
        SELECT 1
        FROM pemdata.oc_extension e
        WHERE e.server_id = s.id
          AND e.extension_name = 'bdr'
    );

	-- ==========================================================
	-- Table: pem.pem_host_and_server
	-- Description: Maps PEM agents to backend database servers.
	-- ==========================================================
	CREATE TABLE IF NOT EXISTS pem.pem_host_and_server (
		agent_id  INTEGER NOT NULL,	-- Represents the host (PEM agent)
		server_id INTEGER NOT NULL,	-- Represents the backend server
		database  TEXT NOT NULL,		 -- Name of the database on the server
		is_leader BOOLEAN DEFAULT FALSE, -- Leader flag for job execution

		FOREIGN KEY (agent_id, server_id)
			REFERENCES pem.agent_server_binding(agent_id, server_id)
			ON DELETE CASCADE ON UPDATE CASCADE
	);

	-- ==========================================================
	-- Function: pem.create_or_update_job
	-- Description: Creates or updates a job in the pem.job table.
	-- ==========================================================
	CREATE OR REPLACE FUNCTION pem.create_or_update_job(
		job_name TEXT, job_desc TEXT, agentid INTEGER, is_systemjob BOOLEAN DEFAULT FALSE,
		enabled BOOLEAN DEFAULT TRUE
	) RETURNS INTEGER AS
	$FUNC$
	DECLARE
		job_id INTEGER;
	BEGIN
		-- Try to find an existing job with the same name, agent, and system flag
		SELECT j.jobid INTO job_id FROM pem.job j
		WHERE j.jobname = job_name AND j.agent_id = agentid AND j.issystemjob = is_systemjob;

		IF NOT FOUND THEN
			-- Create a new job
			INSERT INTO pem.job(jobname, jobdesc, agent_id, issystemjob, jobenabled)
			VALUES (job_name, job_desc, agentid, is_systemjob, enabled)
			RETURNING jobid INTO job_id;
		ELSE
			-- Update the existing job
			UPDATE pem.job
			SET
				jobenabled = enabled,
				jobdesc = job_desc
			WHERE jobid = job_id;
		END IF;

		RETURN job_id;
	END
	$FUNC$ LANGUAGE 'plpgsql';

	-- ==========================================================
	-- Function: pem.create_or_update_jobstep
	-- Description: Creates or updates a job step for the given job.
	-- ==========================================================
	CREATE OR REPLACE FUNCTION pem.create_or_update_jobstep(
		job_id INTEGER, serverid INTEGER, database TEXT,
		name TEXT, jst_desc TEXT, kind CHAR, code TEXT, enabled BOOLEAN,
		onerror char = 'f'
	) RETURNS VOID AS
	$FUNC$
	DECLARE
		jobstepid INTEGER;
	BEGIN
		-- Try to find an existing jobstep with the same name and job_id
		SELECT jstid INTO jobstepid FROM pem.jobstep
		WHERE jstname = name AND jstjobid = job_id;

		IF NOT FOUND THEN
			-- Insert new jobstep
			INSERT INTO pem.jobstep(
				jstjobid, jstname, jstenabled, jstdesc, jstkind, jstcode, server_id,
				database_name, jstonerror
			) VALUES (
				job_id, name, enabled, jst_desc, kind, code, serverid, database, onerror
			);
		ELSE
			-- Update existing jobstep
			UPDATE pem.jobstep
			SET
				jstenabled = enabled,
				jstkind = kind,
				jstcode = code,
				server_id = serverid,
				database_name = database,
				jstdesc = jst_desc
			WHERE jstjobid = job_id AND jstid = jobstepid;
		END IF;
	END
	$FUNC$ LANGUAGE plpgsql;


	-- ==========================================================
	-- Function: pem.create_or_update_jobschedule
	-- Description: Creates or updates a schedule for a job.
	-- ==========================================================
	CREATE OR REPLACE FUNCTION pem.create_or_update_jobschedule(
		job_id INTEGER, name TEXT, jscdesc TEXT,
		minutes BOOL[60],
		hours BOOL[24],
		weekdays BOOL[7] DEFAULT '{t,t,t,t,t,t,t}',
		months BOOL[12] DEFAULT '{t,t,t,t,t,t,t,t,t,t,t,t}',
		monthdays BOOL[32] DEFAULT '{t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t}'
	) RETURNS VOID AS
	$FUNC$
	DECLARE
		scid INTEGER;
	BEGIN
		-- Try to find existing schedule for the job
		SELECT jscid INTO scid FROM pem.schedule
		WHERE jscname = name AND jscjobid = job_id;

		IF NOT FOUND THEN
			-- Create new schedule
			INSERT INTO pem.schedule(
				jscjobid, jscname, jscdesc,
				jscminutes, jschours, jscmonths, jscweekdays, jscmonthdays
			) VALUES(
				job_id, name, jscdesc,
				minutes, hours, months, weekdays, monthdays
			);
		ELSE
			-- Update existing schedule
			UPDATE pem.schedule
			SET
				jscminutes = minutes,
				jschours = hours,
				jscmonths = months,
				jscweekdays = weekdays,
				jscmonthdays = monthdays
			WHERE jscjobid = job_id AND jscid = scid;
		END IF;
	END
	$FUNC$ LANGUAGE plpgsql;


	-- ==========================================================
	-- Function: pem.create_or_update_system_job_with_a_step_and_schedule
	-- Description:
	-- Creates or updates a system job, its jobstep, and optionally its schedule.
	-- ==========================================================
	CREATE OR REPLACE FUNCTION
		pem.create_or_update_system_job_with_a_step_and_schedule (
			agent_id integer, server_id integer, database text,
			jobname text, jobdesc text,
			jstname text, jstdesc text, jstkind char, jstcode text,
			jobenabled boolean = TRUE, jstenabled boolean = TRUE,
			jscname text = NULL, jscdesc text = NULL,
			jscminutes bool[60] = NULL, jschours bool[24] = NULL
		) RETURNS INTEGER AS
	$FUNC$
	DECLARE
		job_id INTEGER;
	BEGIN
		-- Create or update job
		SELECT pem.create_or_update_job(
			jobname, jobdesc, agent_id, TRUE, jobenabled
		) INTO job_id;

		-- Create or update job step
		PERFORM pem.create_or_update_jobstep(
			job_id, server_id, database,
			jstname, jstdesc, jstkind, jstcode, jstenabled
		);

		-- If schedule info is provided, create or update the schedule
		IF
			jscname IS NOT NULL AND
			jscdesc IS NOT NULL AND
			jscminutes IS NOT NULL AND
			jschours IS NOT NULL
		THEN
			PERFORM pem.create_or_update_jobschedule(
				job_id, jscname, jscdesc, jscminutes, jschours
			);
		END IF;

		RETURN job_id;
	END
	$FUNC$ LANGUAGE plpgsql;


	-- ----------------
	-- FUNCTION: pem.create_pem_server_system_tasks()
	--
	-- It will create the system jobs for these agent & server combination.
	-- They will be disabled by default.
	-- When leader is found automatically as a 'standalone' or 'primary', it will
	-- enable these system jobs.
	--
	CREATE OR REPLACE FUNCTION pem.create_pem_server_system_tasks()
		RETURNS void AS
	$FUNC$
	DECLARE
		job_id    integer;
		agent_id  integer;
		server_id integer;
		database  text;
		rec       RECORD;
		probe_rec RECORD;
	BEGIN

		FOR rec IN SELECT * FROM pem.pem_host_and_server
		LOOP
			-- JOB: Create database clean up job
			-- STEP: Obsolete database cleanup
			-- SCHEDULE: Database cleanup (runs twice a day)
			SELECT pem.create_or_update_system_job_with_a_step_and_schedule(
				rec.agent_id, rec.server_id, rec.database,
				-- Job name
				'Database cleanup',
				-- Job description
				'This job runs periodically to purge old data from the database.',
				-- Step name
				'Obsolete database cleanup',
				-- Step description
				'This job step runs periodically to purge obsolete data from the database.',
				's',
				'SELECT pem.purge_obsolete_data()',
				rec.is_leader, TRUE,
				-- Schedule name
				'Database cleanup',
				-- Schedule description
				'This job schedule runs periodically to purge old data from the database.',
				'{t,f,f,f,f,f,f,f,f,f,f,f,f,f,f,t,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f}',
				'{f,t,f,f,f,f,f,f,f,t,f,f,f,t,f,f,f,t,f,f,f,f,f,f}'
			) INTO job_id;

			FOR probe_rec IN
				SELECT
					format(
						$sql$
							SELECT pem.create_or_update_jobstep(
								$1::integer, $2::integer, $3::text,
								'Purge data (%s)'::text,
								'Purging the history data for the probe (id: %s, name: %s,).'::text,
								's'::char,
								'SELECT pem.purge_probe_history(%s::integer)'::text,
								true::boolean,
								'i'::char
							)
						$sql$,
						p.display_name,
						p.id,
						p.display_name,
						p.id
					) AS sql
				FROM pem.probe p WHERE NOT discard_history
			LOOP
				EXECUTE probe_rec.sql USING job_id, rec.server_id, rec.database;
			END LOOP;

			-- JOB: Update the probe-object combination
			SELECT pem.create_or_update_system_job_with_a_step_and_schedule(
				rec.agent_id, rec.server_id, rec.database,
				-- Job name
				'Update the probe-objects combination',
				-- Job description
				'This job updates/inserts the record of the probe, parameter_value_list in the ''pem.probe_objects_combo'' table.',
				-- Step name
				'Update the probe-objects combination',
				-- Step description
				'This job step updates the purge-job tasks on demand.',
				's',
				'SELECT pem.create_update_probe_objects_combo()',
				rec.is_leader, TRUE
			) INTO job_id;

			--
			-- Generate the update probe-objects combination job
			-- it will run 10 minutes after installation.
			--
			-- Let agent fetch the information about the server, and host-machine
			-- to determine the actual probes to run, which generates actual
			-- combination.
			UPDATE pem.job SET jobnextrun = now() + interval '10 minutes'
			WHERE jobid = job_id;


			-- JOB: Audit log table cleanup
			-- SCHEDULE: Run once a day
			PERFORM pem.create_or_update_system_job_with_a_step_and_schedule(
				rec.agent_id, rec.server_id, rec.database,
				-- Job name
				'Audit log table cleanup',
				-- Job description
				'This job runs periodically to purge old data from the audit log table.',
				-- Step name
				'Audit log table cleanup',
				-- Step description
				'This job step runs periodically to purge old data from the audit log table.',
				's',
				'SELECT pem.purge_audit_log()',
				rec.is_leader, TRUE,
				-- Schedule name
				'Audit log table cleanup',
				-- Schedule description
				'This job schedule runs periodically to purge old data from the audit log table.',
				'{t,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f}',
				'{f,t,f,f,f,f,f,f,f,f,f,f,t,f,f,f,f,f,f,f,f,f,f,f}'
			);


			-- JOB: Server log table cleanup
			-- SCHEDULE: Run once a day
			PERFORM pem.create_or_update_system_job_with_a_step_and_schedule(
				rec.agent_id, rec.server_id, rec.database,
				-- Job name
				'Server log table cleanup',
				-- Job description
				'This job runs periodically to purge old data from the server log table.',
				-- Step name
				'Server log table cleanup',
				-- Step description
				'This job step runs periodically to purge old data from the server log table.',
				's',
				'SELECT pem.purge_server_log()',
				rec.is_leader, TRUE,
				-- Schedule name
				'Server log table cleanup',
				-- Schedule description
				'This job schedule runs periodically to purge old data from the server log table.',
				'{f,f,t,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f}',
				'{f,t,f,f,f,f,f,f,f,f,f,f,f,t,f,f,f,f,f,f,f,f,f,f}'
			);

			-- JOB: Probe log table cleanup
			-- SCHEDULE: Run once a day
			PERFORM pem.create_or_update_system_job_with_a_step_and_schedule(
				rec.agent_id, rec.server_id, rec.database,
				-- Job name
				'Probe log table cleanup',
				-- Job description
				'This job runs periodically to purge old data from the probe log table.',
				-- Step name
				'Probe log table cleanup',
				-- Step description
				'This job step runs periodically to purge old data from the probe log table.',
				's',
				'SELECT pem.purge_probe_log()',
				rec.is_leader, TRUE,
				-- Schedule name
				'Probe log table cleanup',
				-- Schedule description
				'This job schedule runs periodically to purge old data from the probe log table.',
				'{t,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f}',
				'{f,f,t,f,f,f,f,f,f,f,f,f,f,f,t,f,f,f,f,f,f,f,f,f}'
			);


			-- JOB: SMTP spool table cleanup
			-- SCHEDULE: Run once a day
			PERFORM pem.create_or_update_system_job_with_a_step_and_schedule(
				rec.agent_id, rec.server_id, rec.database,
				-- Job name
				'SMTP spool table cleanup',
				-- Job description
				'This job runs periodically to purge old data from the smtp spool table.',
				-- Step name
				'SMTP spool table cleanup',
				-- Step description
				'This job step runs periodically to purge old data from the smtp spool table.',
				's',
				'SELECT pem.purge_smtp_spool()',
				rec.is_leader, TRUE,
				-- Schedule name
				'SMTP spool table cleanup',
				-- Schedule description
				'This job schedule runs periodically to purge old data from the smtp spool table.',
				'{t,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f}',
				'{f,f,f,t,f,f,f,f,f,f,f,f,f,f,f,t,f,f,f,f,f,f,f,f}'
			);


			-- JOB: SMTP spool table cleanup
			-- SCHEDULE: Run once a day
			PERFORM pem.create_or_update_system_job_with_a_step_and_schedule(
				rec.agent_id, rec.server_id, rec.database,
				-- Job name
				'SNMP spool table cleanup',
				-- Job description
				'This job runs periodically to purge old data from the snmp spool table.',
				-- Step name
				'SNMP spool table cleanup',
				-- Step description
				'This job step runs periodically to purge old data from the snmp spool table.',
				's',
				'SELECT pem.purge_snmp_spool()',
				rec.is_leader, TRUE,
				-- Schedule name
				'SNMP spool table cleanup',
				-- Schedule description
				'This job schedule runs periodically to purge old data from the snmp spool table.',
				'{t,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f}',
				'{f,f,f,t,f,f,f,f,f,f,f,f,f,f,f,t,f,f,f,f,f,f,f,f}'
			);

			-- JOB: Webhook spool table cleanup
			-- SCHEDULE: Run once a day
			PERFORM pem.create_or_update_system_job_with_a_step_and_schedule(
				rec.agent_id, rec.server_id, rec.database,
				-- Job name
				'Webhook spool table cleanup',
				-- Job description
				'This job runs periodically to purge old data from the webhook spool table.',
				-- Step name
				'Webhook spool table cleanup',
				-- Step description
				'This job step runs periodically to purge old data from the webhook spool table.',
				's',
				'SELECT pem.purge_webhook_spool()',
				rec.is_leader, TRUE,
				-- Schedule name
				'Webhook spool table cleanup',
				-- Schedule description
				'This job schedule runs periodically to purge old data from the webhook spool table.',
				'{t,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f}',
				'{f,f,f,t,f,f,f,f,f,f,f,f,f,f,f,t,f,f,f,f,f,f,f,f}'
			);


			-- JOB: Webhook spool history table cleanup
			-- SCHEDULE: Run once a day
			PERFORM pem.create_or_update_system_job_with_a_step_and_schedule(
				rec.agent_id, rec.server_id, rec.database,
				-- Job name
				'Webhook spool history table cleanup',
				-- Job description
				'This job runs periodically to purge old data from the webhook spool history table.',
				-- Step name
				'Webhook spool history table cleanup',
				-- Step description
				'This job step runs periodically to purge old data from the webhook spool history table.',
				's',
				'SELECT pem.purge_webhook_spool_history()',
				rec.is_leader, TRUE,
				-- Schedule name
				'Webhook spool history table cleanup',
				-- Schedule description
				'This job schedule runs periodically to purge old data from the webhook spool history table.',
				'{t,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f}',
				'{f,f,f,f,t,f,f,f,f,f,f,f,f,f,f,f,t,f,f,f,f,f,f,f}'
			);

			-- JOB: Alert history table cleanup
			-- SCHEDULE: Run once a day
			PERFORM pem.create_or_update_system_job_with_a_step_and_schedule(
				rec.agent_id, rec.server_id, rec.database,
				-- Job name
				'Alert history table cleanup',
				-- Job description
				'This job runs periodically to purge old data from the alert history table.',
				-- Step name
				'Alert history table cleanup',
				-- Step description
				'This job step runs periodically to purge old data from the alert history table.',
				's',
				'SELECT pem.purge_alert_history()',
				rec.is_leader, TRUE,
				-- Schedule name
				'Alert history table cleanup',
				-- Schedule description
				'This job schedule runs periodically to purge old data from the alert history table.',
				'{t,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f}',
				'{f,f,f,f,f,t,f,f,f,f,f,f,f,f,f,f,f,t,f,f,f,f,f,f}'
			);

			-- JOB: Job log table cleanup
			-- SCHEDULE: Run once a day
			PERFORM pem.create_or_update_system_job_with_a_step_and_schedule(
				rec.agent_id, rec.server_id, rec.database,
				-- Job name
				'Job log table cleanup',
				-- Job description
				'This job runs periodically to purge old data from the job log table.',
				-- Step name
				'Job log table cleanup',
				-- Step description
				'This job step runs periodically to purge old data from the job log table.',
				's',
				'SELECT pem.purge_job_log()',
				rec.is_leader, TRUE,
				-- Schedule name
				'Job log table cleanup',
				-- Schedule description
				'This job schedule runs periodically to purge old data from the job log table.',
				'{t,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f}',
				'{f,f,f,f,f,f,t,f,f,f,f,f,f,f,f,f,f,f,t,f,f,f,f,f}'
			);

			-- JOB: Job purge the deleted charts
			-- SCHEDULE: Run once a day
			PERFORM pem.create_or_update_system_job_with_a_step_and_schedule(
				rec.agent_id, rec.server_id, rec.database,
				-- Job name
				'Job purge the deleted charts',
				-- Job description
				'This job runs periodically to purge the deleted charts.',
				-- Step name
				'Job purge the deleted charts',
				-- Step description
				'This job step runs periodically to purge the deleted charts (we do not clean them up immediately).',
				's',
				'SELECT pem.purge_deleted_charts()',
				rec.is_leader, TRUE,
				-- Schedule name
				'Job purge the deleted charts',
				-- Schedule description
				'This job schedule runs periodically to purge the deleted charts.',
				'{t,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f}',
				'{f,f,t,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f}'
			);


			-- JOB: Purge deleted custom probes
			-- SCHEDULE: Run once a day
			PERFORM pem.create_or_update_system_job_with_a_step_and_schedule(
				rec.agent_id, rec.server_id, rec.database,
				-- Job name
				'Purge deleted custom probes',
				-- Job description
				'This job runs periodically to purge the deleted probes.',
				-- Step name
				'Purge deleted custom probes',
				-- Step description
				'This job runs periodically to purge deleted custom probes and its data.',
				's',
				'SELECT pem.purge_deleted_probes()',
				rec.is_leader, TRUE,
				-- Schedule name
				'Purge deleted custom probes',
				-- Schedule description
				'This job runs periodically to purge deleted custom probes and its data.',
				'{t,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f}',
				'{f,t,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f}'
			);


			-- JOB: Check CA certificate expiry
			PERFORM pem.create_or_update_system_job_with_a_step_and_schedule(
				rec.agent_id, rec.server_id, rec.database,
				-- Job name
				'Check CA certificate expiry',
				-- Job description
				'This job check the expiry of CA certificate.',
				-- Step name
				'Check CA certificate expiry',
				-- Step description
				'This job step runs to check the expiry of CA certificate.',
				'i',
				'check_server_certificate_expiry',
				rec.is_leader, TRUE
			);

		END LOOP;
	END
	$FUNC$ LANGUAGE 'plpgsql';

	-- ----------------
	-- TRIGGER FUNCTION: pem.pem_host_and_server_updated()
	--
	--   It calls the 'pem.create_pem_server_system_tasks()' function.
	--
	CREATE OR REPLACE FUNCTION pem.pem_host_and_server_updated()
		RETURNS TRIGGER AS
	$FUNC$
	BEGIN
		PERFORM pem.create_pem_server_system_tasks();
		RETURN NULL;
	END
	$FUNC$ LANGUAGE 'plpgsql';

	---------
	-- Trigger: pem_host_and_server_change
	-- Table: pem.pem_host_and_server
	-- Event: insert or update or delete (statement level)
	--
	--   Execute 'pem.pem_host_and_server_updated(...)' trigger function to
	--   create the system jobs for this server and agent.
	--
	DO $$
	BEGIN
		IF NOT EXISTS (
			SELECT 1 FROM pg_catalog.pg_trigger
			WHERE tgrelid = 'pem.pem_host_and_server'::regclass::oid AND tgname = 'pem_host_and_server_change'
		) THEN
			EXECUTE $trig$
				CREATE TRIGGER pem_host_and_server_change
					AFTER INSERT OR UPDATE OR DELETE ON pem.pem_host_and_server
					FOR EACH STATEMENT
					EXECUTE FUNCTION pem.pem_host_and_server_updated()
			$trig$;
		END IF;
	END
	$$ LANGUAGE plpgsql;

	DROP TRIGGER IF EXISTS server_tags_trigger ON pemdata.server_info;
	DROP FUNCTION IF EXISTS update_server_tags();

	CREATE OR REPLACE FUNCTION pem.add_server_tag(p_server_id INTEGER, p_tag TEXT, p_color TEXT)
	RETURNS VOID AS $$
	BEGIN
		-- Initialize tags if NULL
		UPDATE pem.server
		SET tags = '[]'::jsonb
		WHERE id = p_server_id AND tags IS NULL;

		-- Add tag if not already present
		UPDATE pem.server
		SET tags = jsonb_insert(
				COALESCE(tags, '[]'::jsonb),
				'{0}',
				jsonb_build_object('color', p_color, 'text', p_tag),
				true
			)
		WHERE id = p_server_id
		AND NOT EXISTS (
			SELECT 1
			FROM jsonb_array_elements(tags) AS tag
			WHERE tag->>'text' = p_tag
		);
	END;
	$$ LANGUAGE plpgsql;

	CREATE OR REPLACE FUNCTION pem.remove_server_tag(p_server_id INTEGER, p_tag TEXT)
	RETURNS VOID AS $$
	BEGIN
		UPDATE pem.server
		SET tags = COALESCE(
			(SELECT jsonb_agg(tag)
			 FROM jsonb_array_elements(tags) AS tag
			 WHERE tag->>'text' != p_tag),
			'[]'::jsonb
		)
		WHERE id = p_server_id;
	END;
	$$ LANGUAGE plpgsql;

	-- Trigger to add the tags primary/replica based on the node_type in server_info
	CREATE OR REPLACE FUNCTION pem.update_server_node_type_info()
	RETURNS TRIGGER AS $$
	DECLARE
		primary_color text := '#008000';   -- Green
		replica_color text := '#737373';   -- Dark Grey
	BEGIN

		-- Update is_leader field for non-replica nodes
		IF (
				TG_OP = 'INSERT' OR (TG_OP = 'UPDATE' AND NEW.node_type <> OLD.node_type)
			)
			AND NEW.node_type = ANY('{standalone, primary}'::text[])
			AND EXISTS (
				SELECT 1 FROM pem.pem_host_and_server WHERE server_id = NEW.server_id
			)
		THEN
			UPDATE pem.pem_host_and_server
				SET is_leader = (server_id = NEW.server_id)::boolean;
		END IF;

		-- Add or remove tags based on node_type changes
		IF TG_OP = 'INSERT' OR TG_OP = 'UPDATE' THEN
			-- Skip processing if server has 'bdr' extension
			IF EXISTS (
				SELECT 1
					FROM pemdata.oc_extension
					WHERE server_id = NEW.server_id AND extension_name = 'bdr'
				) THEN
				RETURN NEW;
			END IF;

			-- PRIMARY tag handling
			IF NEW.node_type = 'primary' AND (TG_OP = 'INSERT' OR OLD.node_type != 'primary') THEN
				PERFORM pem.add_server_tag(NEW.server_id, 'primary', primary_color);
			ELSIF TG_OP = 'UPDATE' AND OLD.node_type = 'primary' AND NEW.node_type != 'primary' THEN
				PERFORM pem.remove_server_tag(NEW.server_id, 'primary');
			END IF;

			-- REPLICA tag handling
			IF NEW.node_type = 'replica' AND (TG_OP = 'INSERT' OR OLD.node_type != 'replica') THEN
				PERFORM pem.add_server_tag(NEW.server_id, 'replica', replica_color);
			ELSIF TG_OP = 'UPDATE' AND OLD.node_type = 'replica' AND NEW.node_type != 'replica' THEN
				PERFORM pem.remove_server_tag(NEW.server_id, 'replica');
			END IF;
		END IF;

		RETURN NEW;
	END;
	$$ LANGUAGE plpgsql SECURITY DEFINER;

	DO $$
	BEGIN
		IF NOT EXISTS (
			SELECT 1 FROM pg_catalog.pg_trigger
			WHERE tgrelid = 'pemdata.server_info'::regclass::oid AND tgname = 'server_node_type_info_trigger'
		) THEN
			EXECUTE $trig$
				CREATE TRIGGER server_node_type_info_trigger
					AFTER INSERT OR UPDATE ON pemdata.server_info
					FOR EACH ROW
					EXECUTE FUNCTION pem.update_server_node_type_info();
			$trig$;
		END IF;
	END
	$$ LANGUAGE plpgsql;

	CREATE OR REPLACE FUNCTION pem.server_postupdate() RETURNS trigger AS $$
	BEGIN
		IF (OLD.active AND NOT NEW.active) THEN
			DELETE FROM pem.agent_server_binding WHERE server_id = NEW.id;
			DELETE FROM pem.alert WHERE server_id = NEW.id;
			DELETE FROM pem.job WHERE jobid IN (SELECT j.jobid FROM pem.job j INNER JOIN pem.jobstep js ON j.jobid = js.jstjobid WHERE js.server_id = NEW.id);
		END IF;
		RETURN NULL;
	END
	$$ LANGUAGE plpgsql;

	--
	-- TRIGGER FUNCTION: pem.create_delete_probe_purge_jobstep()
	--
	-- This trigger function will create/remove the jobsteps for purging history
	-- data for a particular probe.
	CREATE OR REPLACE FUNCTION pem.create_delete_probe_purge_jobstep()
		RETURNS trigger AS
	$function$
	DECLARE
		purge_job_id integer;
		purge_jstid  integer;
		pem_server   integer;
		pem_database text;
		phs RECORD;
	BEGIN
		IF TG_OP = 'INSERT' THEN
			IF NOT NEW.discard_history THEN
				FOR phs IN
					SELECT * FROM pem.pem_host_and_server
					LOOP
						PERFORM pem.create_or_update_system_job_with_a_step_and_schedule(
							phs.agent_id, phs.server_id, phs.database,
							-- Job name
							'Database cleanup',
							-- Job description
							'This job runs periodically to purge old data from the database.',
							-- Step name
							'Purge data (' || NEW.display_name || ')',
							-- Step description
							'Purging the history data for the probe (' || NEW.display_name || ')...',
							's',
							'SELECT pem.purge_probe_history(' || NEW.id || '::integer)',
							phs.is_leader, TRUE,
							-- Schedule name
							'Database cleanup',
							-- Schedule description
							'This job schedule runs periodically to purge old data from the database.',
							'{t,f,f,f,f,f,f,f,f,f,f,f,f,f,f,t,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f}',
							'{f,t,f,f,f,f,f,f,f,t,f,f,f,t,f,f,f,t,f,f,f,f,f,f}'
						);
					END LOOP;
			END IF;
			RETURN NEW;
		ELSE
			IF NOT OLD.discard_history THEN
				DELETE FROM pem.jobstep
				WHERE jstjobid = ANY (
					SELECT jobid FROM pem.job
					WHERE jobdesc = 'Database cleanup' AND issystemjob
				)
				AND jstdesc = 'Purge data (' || OLD.display_name || ')';
			END IF;
			RETURN OLD;
		END IF;
	END;
	$function$ LANGUAGE plpgsql SECURITY DEFINER;

	--
	-- TRIGGER FUNCTION: pem.run_job_to_update_probe_objects_combo()
	--
	-- This trigger function will update the job to update the purge jobsteps in
	-- 24 hours.
	CREATE OR REPLACE FUNCTION pem.run_job_to_update_probe_objects_combo()
		RETURNS trigger AS
	$function$
	DECLARE
		needs_update boolean;
	BEGIN
		-- We will not update the purge job tasks immediately, there is
		-- no requirement to do it immediately.
		EXECUTE $SQL$
		  UPDATE pem.job
			  SET jobnextrun = now() + INTERVAL '10 minutes'
			  WHERE jobname = 'Update the probe-objects combination' AND issystemjob AND (
				  jobnextrun IS NULL OR jobnextrun < now()
			  )
		  $SQL$;
		RETURN NEW;
	END;
	$function$ LANGUAGE 'plpgsql' SECURITY DEFINER;

	CREATE OR REPLACE FUNCTION pem.startup(
		server_desc text, server_name text, server_host text,
		server_port int, server_database text, server_ssl int,
		user_name text, passwd text, ser_group text,
		agentid int, agent_database text
	)
		RETURNS void AS
	$BODY$
	DECLARE
		sg_id     integer;
		serverid  integer := 1;
		is_active boolean;
		name      text;
	BEGIN

		-- Check if the server group already exists.
		SELECT id INTO sg_id FROM pem.server_group sg WHERE sg.name = ser_group;

		IF (NOT FOUND) THEN
			-- Create new server group
			INSERT INTO pem.server_group(name) VALUES(ser_group) RETURNING id INTO sg_id;
		END IF;

		-- Check the server entry is already exist.
		SELECT active INTO is_active FROM pem.server WHERE id = serverid;

		-- if entry not found or server with id serverid is already exist and server is active then add new server.
		IF (NOT FOUND) OR is_active THEN
			-- Create entry of PEM server in pem.server table.
			INSERT INTO pem.server (
				description, server, port, database, ssl
			) VALUES (
				server_desc, server_name, server_port, server_database, server_ssl
			) RETURNING id INTO serverid;

			-- Set the options of the PEM server
			INSERT INTO pem.server_options (
				server_id, pem_user, server_group_id, username
			) VALUES (
				serverid, user_name, sg_id, user_name
			);

			-- Set the options of the PEM server auth table
			INSERT INTO pem.server_auth (server_id, pem_user) VALUES (serverid, user_name);

		ELSE
			UPDATE pem.server SET
				description = server_desc,
				server = server_name,
				port = server_port,
				database = server_database,
				ssl = server_ssl,
				active = 't'
			WHERE id = serverid;

			UPDATE pem.server_options SET
				pem_user = user_name,
				server_group_id = sg_id,
				username = user_name
			WHERE server_id = serverid;

			UPDATE pem.server_auth SET pem_user = user_name WHERE server_id = serverid;

		END IF;

		-- Create Agent Server Binding
		INSERT INTO pem.agent_server_binding (
			agent_id, server_id, server, port, username, database, password
		) VALUES (
			agentid, serverid, server_host, server_port, user_name, agent_database, passwd
		);

		PERFORM pem.register_pem_server(serverid);

	END;
	$BODY$ LANGUAGE plpgsql;

	CREATE OR REPLACE FUNCTION pem.create_script_job(_alert_id integer, _current_value text, _current_state text, _previous_state text, _run_on_pem_server boolean, _script_code text) RETURNS VOID AS $$
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
		-- Get alert, agent, server details
		SELECT
			a.name, a.agent_id, a.server_id, a.thresholds, s.description, s.server, s.port,
			ag.description, a.database_name, a.schema_name, a.package_name, a.object_name,
			a.params, at.param_names, at.param_units, ptt.display_name,
			pas.info_cols, pas.info_vals
		INTO
			alert_name, alert_agent_id, alert_server_id, alert_thresholdvalue, server_name, server_ip, server_port,
			agent_name, alert_database_name, alert_schema_name, alert_package_name, alert_db_object_name,
			alert_parameters_values, alert_parameters_names, alert_param_units, alert_object_type,
			alert_info_names, alert_info_values
		FROM
			pem.alert a
			LEFT JOIN pem.server s ON a.server_id = s.id
			LEFT JOIN pem.agent ag ON a.agent_id = ag.id
			LEFT JOIN pem.alert_template at ON a.template_id = at.id
			LEFT JOIN pem.alert_status pas ON (a.id = pas.alert_id)
			LEFT OUTER JOIN pem.probe_target_type ptt ON at.object_type = ptt.id
		WHERE
			a.id = _alert_id;

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

		_script_code = pem.replace_text_params(_script_code, '%ThresholdValue%', alert_thresholdvalue::text, 'g');
		_script_code = pem.replace_text_params(_script_code, '%CurrentValue%', _current_value, 'g');
		_script_code = pem.replace_text_params(_script_code, '%CurrentState%', COALESCE(_current_state, '')::text, 'g');
		_script_code = pem.replace_text_params(_script_code, '%OldState%', COALESCE(_previous_state, '')::text, 'g');
		_script_code = pem.replace_text_params(_script_code, '%AlertRaisedTime%', now()::text, 'g');
		_script_code = pem.replace_text_params(_script_code, '%ObjectName%', alert_object_name, 'g');
		_script_code = pem.replace_text_params(_script_code, '%AlertName%', alert_name, 'g');

			-- PEM-3612: Adding support for more placeholders
			-- We will form a alert params details string from arrays
			_script_code = pem.replace_text_params(_script_code, '%AlertID%', _alert_id::text, 'g');
			_script_code = pem.replace_text_params(_script_code, '%ObjectType%', alert_object_type, 'g');

			alert_params_details = '';
			IF alert_parameters_names IS NOT NULL THEN
					FOR idx in 1 .. array_length(alert_parameters_names, 1)
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
													alert_info_names[ifn], ': ',	COALESCE(alert_info_values[idx][ifn], '')::text, E'\n'
											);
									EXCEPTION WHEN OTHERS THEN
										 -- Do nothing just keep looping
									END;
							END LOOP;
					END LOOP;
			END IF;

			IF alert_agent_id >= 1 THEN
					_script_code = pem.replace_text_params(_script_code, '%AgentID%', alert_agent_id::text, 'g');
					_script_code = pem.replace_text_params(_script_code, '%AgentName%', agent_name, 'g');
			ELSE
					_script_code = pem.replace_text_params(_script_code, '%AgentID%', '', 'g');
					_script_code = pem.replace_text_params(_script_code, '%AgentName%', '', 'g');
			END IF;

		IF alert_server_id >= 1 THEN
				_script_code = pem.replace_text_params(_script_code, '%ServerID%', alert_server_id::text, 'g');
					server_name = replace(server_name, E'\\', E'\\\\');
				_script_code = pem.replace_text_params(_script_code, '%ServerName%', server_name, 'g');
				_script_code = pem.replace_text_params(_script_code, '%ServerIP%', server_ip, 'g');
				_script_code = pem.replace_text_params(_script_code, '%ServerPort%', server_port::text, 'g');
		ELSE
				_script_code = pem.replace_text_params(_script_code, '%ServerID%', '', 'g');
				_script_code = pem.replace_text_params(_script_code, '%ServerName%', '', 'g');
				_script_code = pem.replace_text_params(_script_code, '%ServerIP%', '', 'g');
				_script_code = pem.replace_text_params(_script_code, '%ServerPort%', '', 'g');
		END IF;

			IF alert_database_name IS NOT NULL AND alert_database_name <> '' THEN
					alert_database_name = replace(alert_database_name, E'\\', E'\\\\');
			END IF;
			_script_code = pem.replace_text_params(_script_code, '%DatabaseName%', alert_database_name, 'g');

			IF alert_schema_name IS NOT NULL AND alert_schema_name <> '' THEN
					alert_schema_name = replace(alert_schema_name, E'\\', E'\\\\');
			END IF;
			_script_code = pem.replace_text_params(_script_code, '%SchemaName%', alert_schema_name, 'g');

			IF alert_package_name IS NOT NULL AND alert_package_name <> '' THEN
					alert_package_name = replace(alert_package_name, E'\\', E'\\\\');
			END IF;
			_script_code = pem.replace_text_params(_script_code, '%PackageName%', alert_package_name, 'g');

			IF alert_db_object_name IS NOT NULL AND alert_db_object_name <> '' THEN
					alert_db_object_name = replace(alert_db_object_name, E'\\', E'\\\\');
			END IF;
			_script_code = pem.replace_text_params(_script_code, '%DatabaseObjectName%', alert_db_object_name, 'g');

			_script_code = pem.replace_text_params(_script_code, '%Parameters%', alert_params_details, 'g');
			_script_code = pem.replace_text_params(_script_code, '%AlertInfo%', alert_info_details, 'g');

		IF _run_on_pem_server THEN
			SELECT agent_id FROM pem.pem_host_and_server WHERE is_leader LIMIT 1 INTO alert_agent_id;
		ELSE
			IF alert_agent_id < 1 THEN
				SELECT agent_id FROM pem.agent_server_binding WHERE server_id = alert_server_id INTO alert_agent_id;
			END IF;
		END IF;

		-- Create jobs only when agent_id is correct
		IF alert_agent_id >= 1 THEN
			job_name = 'Execute script for alert "' || alert_name || '"';
			-- Create script execution job.
			INSERT INTO pem.job(jobname, jobdesc, agent_id, jobnextrun, is_alert_job) VALUES(job_name, 'This job executes the given script when alert raises', alert_agent_id, now(), true) RETURNING jobid INTO job_id;
			-- Create script execution step.
			IF alert_server_id >= 1 THEN
				INSERT INTO pem.jobstep(jstjobid, jstname, jstdesc, jstkind, jstcode, server_id, jstonerror, jstsetenvironment) VALUES (job_id, job_name,'This job step executes the given script when alert raises', 'b', _script_code, alert_server_id, 'f', 't');
			ELSE
				INSERT INTO pem.jobstep(jstjobid, jstname, jstdesc, jstkind, jstcode, jstonerror, jstsetenvironment) VALUES (job_id, job_name,'This job step executes the given script when alert raises', 'b', _script_code, 'f', 'f');
			END IF;
		END IF;
	END
	$$ LANGUAGE plpgsql;

	CREATE OR REPLACE FUNCTION pem.register_pem_server(integer)
	RETURNS void AS
	$FUNC$
	DECLARE
		agent_id integer := NULL;
	BEGIN
		SELECT asb.agent_id FROM pem.agent_server_binding asb WHERE asb.server_id = $1 INTO agent_id;

		IF NOT FOUND THEN
			RAISE EXCEPTION 'Server (%) is not bound to any agent, it can not be registered as a PEM server', $1;
		END IF;

		IF EXISTS (
			SELECT 1 FROM pem.pem_host_and_server WHERE server_id = $1
		) THEN
			RAISE INFO 'Server (%) is already registerd as a PEM backend server!', $1;
			RETURN;
		END IF;

		INSERT INTO pem.pem_host_and_server (agent_id, server_id, database)  VALUES (agent_id, $1, current_database());
	END
	$FUNC$ LANGUAGE 'plpgsql';

	DO $$
	DECLARE
		sid integer := NULL;
	BEGIN
		IF (
			SELECT count(*) <> 0 FROM pem.pem_host_and_server
		) THEN
		-- Do nothing
			RETURN;
		END IF;

		SELECT jst.server_id FROM pem.jobstep jst
		WHERE jst.jstname = 'Database cleanup' AND jst.jstjobid = (
			SELECT j.jobid FROM pem.job j WHERE j.jobname = 'Database cleanup' AND j.issystemjob
		) INTO sid;

		IF sid IS NOT NULL THEN
			PERFORM pem.register_pem_server(sid);
		END IF;

		UPDATE pem.pem_host_and_server SET is_leader = true WHERE server_id = sid;

	END;
	$$ LANGUAGE plpgsql;
END TRANSACTION;
