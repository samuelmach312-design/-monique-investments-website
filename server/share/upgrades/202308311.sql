/***************************************************************************
 *
 * Postgres Enterprise Manager
 *
 * Copyright (C) 2010 - 2025, EnterpriseDB Corporation. All rights reserved.
 *
 ***************************************************************************/

-- NOTE: This sql file is responsible for PEM 9.3.0 schema upgrade.

BEGIN TRANSACTION;

    CREATE OR REPLACE FUNCTION pem.schema_version() RETURNS integer AS
        'SELECT 202308311::integer;'
    LANGUAGE 'sql' IMMUTABLE;
    COMMENT ON FUNCTION pem.schema_version() IS
        'Returns the version number of the PEM schema';

    -- PEM-4595 Added support for monotoring PG/EPAS 16
    DO $DO$
	BEGIN
			-- Check if the server version already exist for PG 16
			IF NOT EXISTS (SELECT id FROM pem.server_version WHERE id = 11600) THEN
					INSERT INTO pem.server_version VALUES (11600, 'PostgreSQL 16');
			END IF;

			-- Check if the server version already exist for EPAS 16
			IF NOT EXISTS (SELECT id FROM pem.server_version WHERE id = 21600) THEN
					INSERT INTO pem.server_version VALUES (21600, 'Advanced Server 16');
			END IF;

			-- Check if the probe server version already exist for PG 16
			IF NOT EXISTS (SELECT server_version_id FROM pem.probe_server_version WHERE server_version_id = 11600) THEN
					INSERT INTO pem.probe_server_version
							(probe_id, server_version_id, probe_code)
							SELECT psv.probe_id, 11600 AS server_version_id, psv.probe_code FROM (
											SELECT probe_id, probe_code FROM pem.probe_server_version
											WHERE server_version_id = 11400
							) AS psv
							JOIN pem.probe p ON (psv.probe_id = p.id) AND p.internal_name = ANY(
									ARRAY[
									'oc_table', 'oc_schema', 'oc_function', 'oc_extension', 'oc_views',
									'database_statistics', 'table_statistics', 'table_frozenxid',
									'table_size', 'function_statistics', 'mview_bloat',
									'mview_frozenxid', 'mview_size', 'blocked_session_info',
									'background_writer_statistics', 'session_info', 'lock_info',
									'number_of_wal_files', 'wal_archive_status',
									'streaming_replication', 'streaming_replication_db_conflicts',
									'streaming_replication_lag_time', 'xdb_smr_mmr_replication',
									'efm_cluster_node_status', 'efm_cluster_info'
									]::text[]
			);
			END IF;

			-- Check if the probe server version already exist for EPAS 16
			IF NOT EXISTS (SELECT server_version_id FROM pem.probe_server_version WHERE server_version_id = 21600) THEN
					INSERT INTO pem.probe_server_version
							(probe_id, server_version_id, probe_code)
							SELECT psv.probe_id, 21600 AS server_version_id, psv.probe_code FROM (
											SELECT probe_id, probe_code FROM pem.probe_server_version
											WHERE server_version_id = 21400
							) AS psv
							JOIN pem.probe p ON (psv.probe_id = p.id) AND p.internal_name = ANY(
											ARRAY[
											'oc_table', 'oc_schema','oc_function', 'oc_extension', 'database_statistics',
											'table_statistics', 'table_frozenxid', 'function_statistics', 'table_size',
											'background_writer_statistics', 'number_of_wal_files', 'session_info',
											'system_waits', 'session_waits', 'lock_info', 'audit_configuration',
											'streaming_replication', 'streaming_replication_db_conflicts',
											'xdb_smr_mmr_replication', 'oc_views', 'mview_bloat', 'mview_frozenxid',
											'mview_size', 'streaming_replication_lag_time', 'wal_archive_status',
											'efm_cluster_node_status', 'efm_cluster_info', 'blocked_session_info'
											]::text[]
			);
			END IF;
    END;
    $DO$ LANGUAGE 'plpgsql';

	-- Add new table to store custom email template
	DO $$
	BEGIN
		IF NOT EXISTS(
			SELECT * FROM information_schema.tables
			WHERE  table_schema = 'pem'
			AND    table_name   = 'custom_email_template'
		) THEN
			RAISE INFO '--- Adding new new table pem.custom_email_template';
			CREATE TABLE pem.custom_email_template(
				display_name text NOT NULL,
				mail_subject text,
				mail_message text,
				pem_user text NOT NULL DEFAULT CURRENT_USER,
				CONSTRAINT custom_email_template_pkey PRIMARY KEY (display_name),
				CONSTRAINT custom_email_template_fkey FOREIGN KEY (display_name)
					REFERENCES pem.email_template(display_name) MATCH SIMPLE
					ON UPDATE CASCADE ON DELETE CASCADE INITIALLY DEFERRED
			);
			COMMENT ON COLUMN pem.custom_email_template.display_name IS
				'The name of the email template type.';
			COMMENT ON COLUMN pem.custom_email_template.mail_subject IS
				'The value of the email subject.';
			COMMENT ON COLUMN pem.custom_email_template.mail_message IS
				'The value of the email body.';
			COMMENT ON COLUMN pem.custom_email_template.pem_user IS
				'The name of the current user.';
		END IF;
	END;
	$$ LANGUAGE plpgsql;

	CREATE OR REPLACE FUNCTION pem.get_email_template (template text)
		RETURNS TABLE (
			mail_subject text,
			mail_message text
	)
	AS $$
	BEGIN
		RETURN QUERY SELECT
			COALESCE(cet.mail_subject, et.mail_subject) AS mail_subject,
			COALESCE(cet.mail_message, et.mail_message) AS mail_message
		FROM pem.email_template AS et
				LEFT JOIN pem.custom_email_template AS cet
						ON (et.display_name = cet.display_name)
		WHERE et.display_name = template;
	END; $$
	LANGUAGE 'plpgsql';

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

		SELECT
			mail_subject, mail_message
			INTO subject_mail, message_mail
		FROM pem.get_email_template(template);

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

	CREATE OR REPLACE FUNCTION pem.joblog_status_update() RETURNS TRIGGER AS
	$BODY$
	DECLARE
		group_id integer;
		job RECORD;
		agent RECORD;
		status_info RECORD;
		jobsteps_cur REFCURSOR;
		jobstep RECORD;
		job_failure_notification boolean;
		job_status_change_notification boolean;
		current_datestyle text;
		email_template_name text;
		email_template_subject text;
		email_template_message text;
		email_template_message_server text;
		steps text[];
		subject text;
		message text;
	BEGIN
		-- We won't update when it's still running
		IF NEW.jlgstatus = 'r' or NEW.jlgstatus IS NULL THEN
			RETURN NEW;
		END IF;
		NEW.jlgemailsent := FALSE;

		-- Notify only when status has been updated
		IF NEW.jlgstatus != OLD.jlgstatus THEN
			SELECT * INTO job FROM pem.job j WHERE j.jobid = NEW.jlgjobid;

			IF job.notify = 'NEVER' OR (
				job.notify = 'ON_FAILURE' AND NEW.jlgstatus NOT IN ('f', 'd')
			) THEN
				RETURN NEW;
			END IF;

			-- Agent Info
			SELECT * INTO agent FROM pem.agent WHERE id = job.agent_id;

			IF job.notify != 'DEFAULT' THEN
				group_id := job.email_group_id;
			ELSE
				IF agent.job_notification_override_default IS TRUE THEN
					IF (
						agent.job_status_change_notification IS NOT TRUE AND
						agent.job_failure_notification IS TRUE AND
						NEW.jlgstatus NOT IN  ('f', 'd')
					) THEN
						RETURN NEW;
					END IF;
					group_id := agent.job_notification_email_group_id;
				ELSE
					SELECT (
						SELECT value FROM pem.config
						WHERE param = 'job_failure_notification'
					), (
						SELECT value FROM pem.config
						WHERE param = 'job_status_change_notification'
					) INTO job_failure_notification,
						job_status_change_notification;

					IF job_status_change_notification IS NOT TRUE AND (
							job_failure_notification IS TRUE AND
							-- Failed, or Cancelled/Interrupted
							NEW.jlgstatus not in ('f', 'd')
					) THEN
						RETURN NEW;
					END IF;

					SELECT id INTO group_id FROM pem.email_group
					WHERE name = (
						SELECT value FROM pem.config
						WHERE param = 'job_notification_email_group'
						LIMIT 1
					);
				END IF;
			END IF;

			IF group_id is NULL THEN
				RETURN NEW;
			END IF;

			SELECT (
				SELECT mail_message
				FROM pem.get_email_template('Job Step')
			), (
				SELECT mail_message
				FROM pem.get_email_template('Job Step (Database Server)')
			) INTO email_template_message, email_template_message_server;

			OPEN jobsteps_cur FOR EXECUTE 'SELECT
					jst.*, jstlog.*,
					s.description AS server_desc, s.server AS server_host,
						s.port AS server_port, s.active AS server_active,
						s.hostaddr AS server_hostaddr
					FROM
					pem.jobstep jst
						LEFT JOIN pem.jobsteplog jstlog ON (
						jst.jstid = jstlog.jsljstid
					)
					LEFT JOIN pem.server s ON (jst.server_id = s.id)
					WHERE jst.jstjobid = $1::integer AND (
						jstlog.jsljlgid = $2::integer OR jstlog.jsljlgid IS NULL
					)
				ORDER BY jstlog.jslstart;' USING NEW.jlgjobid, NEW.jlgid;
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

			email_template_name := CASE NEW.jlgstatus
				WHEN 'd' THEN 'Job Cancellation'
				WHEN 'f' THEN 'Job Failure'
				ELSE 'Job Success'
			END;

			SELECT
				mail_subject, mail_message
				INTO email_template_subject, email_template_message
			FROM pem.get_email_template(email_template_name);

			SELECT tbl.* INTO status_info FROM (
				SELECT
					NEW.jlgstatus AS status,
					NEW.jlgstart AS start_time,
					NEW.jlgduration AS duration,
					array_length(steps, 1) AS no_steps,
					array_to_string(steps, E'\n', '') AS steps
					) AS tbl;

			SELECT pem.substitute_job_info(
				email_template_subject, row_to_json(job), row_to_json(agent),
				row_to_json(status_info)
				), pem.substitute_job_info(
				email_template_message, row_to_json(job), row_to_json(agent),
				row_to_json(status_info)
				) INTO subject, message;

			NEW.jlgemailsent := pem.send_email(ARRAY[group_id], subject, message);

		END IF;

		RETURN NEW;
	END;
	$BODY$ LANGUAGE 'plpgsql' VOLATILE;

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

		SELECT mail_subject INTO status_text
		FROM pem.get_email_template(template);

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
	END $BODY$ LANGUAGE plpgsql;

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

END TRANSACTION;
