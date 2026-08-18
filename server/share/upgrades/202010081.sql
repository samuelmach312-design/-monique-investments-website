/***************************************************************************
 *
 * Postgres Enterprise Manager
 *
 * Copyright (C) 2010 - 2025, EnterpriseDB Corporation. All rights reserved.
 *
 ***************************************************************************/

-- NOTE: This sql file is responsible for PEM 8 schema upgrade.

BEGIN TRANSACTION;

CREATE OR REPLACE FUNCTION pem.schema_version() RETURNS integer AS
'SELECT 202010081::integer;'
LANGUAGE 'sql' IMMUTABLE;
COMMENT ON FUNCTION pem.schema_version()
	IS 'Returns the version number of the PEM schema';


DO $DO$
BEGIN
    -- Earlier version has below two function definitions, so we might have any of below based on current PEM version
    DROP FUNCTION IF EXISTS pem.job_is_complete(integer, character);
    DROP FUNCTION IF EXISTS pem.job_is_complete(integer[], char);

	-- Create new function
	CREATE OR REPLACE FUNCTION pem.job_is_complete(dependent_on_job_ids integer[], execute_on_dep_job_status char, jobid integer default null) RETURNS BOOL AS $$
	DECLARE
		res boolean := false;
		max_jlgid integer := null;
	BEGIN
		-- Get the latest job log id for a job, which is about get execute
		-- Compare max_jlgid with dependent job jlgid, so that we don't execute job before dependent job is executed
		SELECT MAX(jlgid) into max_jlgid FROM pem.joblog WHERE jlgjobid = jobid;
		FOR i in 1..COALESCE(array_upper(dependent_on_job_ids, 1), 0) LOOP
			SELECT CASE WHEN (execute_on_dep_job_status = 'i' AND a.jlgstatus != 'r') OR execute_on_dep_job_status = a.jlgstatus THEN true ELSE false END INTO res
			FROM
			(
				SELECT l.jlgstatus jlgstatus
				FROM pem.job j
				LEFT JOIN pem.joblog l ON j.jobid = l.jlgjobid
				WHERE j.jobid = dependent_on_job_ids[i] and (l.jlgid > max_jlgid or max_jlgid is null)
				ORDER BY l.jlgstart DESC LIMIT 1
			) a;

			IF res = false or res is null THEN
				RETURN false;
			END IF;
		END LOOP;
		RETURN true;
	END;
	$$ LANGUAGE plpgsql;
END;

$DO$ LANGUAGE 'plpgsql';

-- PEM-3612: Adding support for more placeholders
DROP FUNCTION IF EXISTS pem.create_script_job;
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
                        alert_info_names[ifn], ': ',  COALESCE(alert_info_values[idx][ifn], '')::text, E'\n'
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
			INSERT INTO pem.jobstep(jstjobid, jstname, jstdesc, jstkind, jstcode, server_id, jstonerror, jstsetenvironment) VALUES (job_id, job_name,'This job step executes the given script when alert raises', 'b', _script_code, alert_server_id, 'f', 't');
		ELSE
			INSERT INTO pem.jobstep(jstjobid, jstname, jstdesc, jstkind, jstcode, jstonerror, jstsetenvironment) VALUES (job_id, job_name,'This job step executes the given script when alert raises', 'b', _script_code, 'f', 'f');
		END IF;
	END IF;
END
$$ LANGUAGE plpgsql;

-- PEM-3786 - Added support for --checksum-algorithm and --disable-checksum parameters introduced in BART 2.6.0.
DO $DO$
BEGIN
    IF NOT EXISTS (SELECT 1
                   FROM pg_attribute
                   WHERE attrelid = (SELECT oid FROM pg_class WHERE relname = 'bart_backup_config' and relnamespace = (SELECT oid FROM pg_namespace WHERE nspname = 'pem'))
                   AND attname = 'checksum_algorithm') THEN
                   ALTER TABLE pem.bart_backup_config ADD COLUMN checksum_algorithm text DEFAULT 'NONE';
    END IF;

    IF NOT EXISTS (SELECT 1
                   FROM pg_attribute
                   WHERE attrelid = (SELECT oid FROM pg_class WHERE relname = 'bart_restore_config' and relnamespace = (SELECT oid FROM pg_namespace WHERE nspname = 'pem'))
                   AND attname = 'verify_checksum') THEN
                   ALTER TABLE pem.bart_restore_config ADD COLUMN verify_checksum boolean DEFAULT true;
    END IF;

    IF NOT EXISTS(SELECT 1 FROM pem.bart_version WHERE id = 2006000) THEN
        INSERT INTO pem.bart_version VALUES (2006000, 'BART (EnterpriseDB) 2.6');
    END IF;

	IF NOT EXISTS (SELECT version FROM pem.bart_default_config WHERE version = 2006000) THEN
        INSERT INTO pem.bart_default_config VALUES (45, 2006000, 'bart_user', NULL, true);
        INSERT INTO pem.bart_default_config VALUES (46, 2006000, 'bart_host', NULL, true);
        INSERT INTO pem.bart_default_config VALUES (47, 2006000, 'backup_path', NULL, true);
        INSERT INTO pem.bart_default_config VALUES (48, 2006000, 'pg_basebackup_path', NULL, true);
        INSERT INTO pem.bart_default_config VALUES (49, 2006000, 'xlog_method', 'fetch');
        INSERT INTO pem.bart_default_config VALUES (50, 2006000, 'retention_policy');
        INSERT INTO pem.bart_default_config VALUES (51, 2006000, 'logfile');
        INSERT INTO pem.bart_default_config VALUES (52, 2006000, 'scanner_logfile');
        INSERT INTO pem.bart_default_config VALUES (53, 2006000, 'wal_compression', 'disabled');
        INSERT INTO pem.bart_default_config VALUES (54, 2006000, 'copy_wals_during_restore', 'disabled');
        INSERT INTO pem.bart_default_config VALUES (55, 2006000, 'thread_count', '1');
        INSERT INTO pem.bart_default_config VALUES (56, 2006000, 'batch_size', '49142');
        INSERT INTO pem.bart_default_config VALUES (57, 2006000, 'scan_interval', '1');
        INSERT INTO pem.bart_default_config VALUES (58, 2006000, 'mbm_scan_timeout', '20');
        INSERT INTO pem.bart_default_config VALUES (59, 2006000, 'workers', '1');
        INSERT INTO pem.bart_default_config VALUES (60, 2006000, 'bart_socket_directory', '/tmp');
		INSERT INTO pem.bart_default_config VALUES (61, 2006000, 'bart_socket_name');
    END IF;

    IF NOT EXISTS (SELECT version FROM pem.bart_server_default_config WHERE version = 2006000) THEN
        INSERT INTO pem.bart_server_default_config VALUES (57, 2006000, 'backup_name');
        INSERT INTO pem.bart_server_default_config VALUES (58, 2006000, 'host', NULL, true);
        INSERT INTO pem.bart_server_default_config VALUES (59, 2006000, 'user', NULL, true);
        INSERT INTO pem.bart_server_default_config VALUES (60, 2006000, 'port', '5444');
        INSERT INTO pem.bart_server_default_config VALUES (61, 2006000, 'archive_command');
        INSERT INTO pem.bart_server_default_config VALUES (62, 2006000, 'cluster_owner', NULL, true);
        INSERT INTO pem.bart_server_default_config VALUES (63, 2006000, 'remote_host');
        INSERT INTO pem.bart_server_default_config VALUES (64, 2006000, 'tablespace_path');
        INSERT INTO pem.bart_server_default_config VALUES (65, 2006000, 'xlog_method', 'fetch');
        INSERT INTO pem.bart_server_default_config VALUES (66, 2006000, 'retention_policy');
        INSERT INTO pem.bart_server_default_config VALUES (67, 2006000, 'wal_compression', 'disabled');
        INSERT INTO pem.bart_server_default_config VALUES (68, 2006000, 'copy_wals_during_restore', 'disabled');
        INSERT INTO pem.bart_server_default_config VALUES (69, 2006000, 'allow_incremental_backups', 'disabled');
        INSERT INTO pem.bart_server_default_config VALUES (70, 2006000, 'thread_count', '1');
        INSERT INTO pem.bart_server_default_config VALUES (71, 2006000, 'description');
        INSERT INTO pem.bart_server_default_config VALUES (72, 2006000, 'batch_size', '49142');
        INSERT INTO pem.bart_server_default_config VALUES (73, 2006000, 'scan_interval', '1');
        INSERT INTO pem.bart_server_default_config VALUES (74, 2006000, 'mbm_scan_timeout', '20');
        INSERT INTO pem.bart_server_default_config VALUES (75, 2006000, 'workers', '1');
        INSERT INTO pem.bart_server_default_config VALUES (76, 2006000, 'archive_path');
    END IF;

END;
$DO$ LANGUAGE 'plpgsql';

-- Function used to get the active webhook endpoints
CREATE or REPLACE FUNCTION pem.get_webhook_endpoints(_alert_id integer) RETURNS TABLE (
        _alertid integer,
        _send_notification bool,
        _low_webhook_ids integer[],
        _med_webhook_ids integer[],
        _high_webhook_ids integer[],
        _cleared_webhook_ids integer[]
  ) AS $$
DECLARE
        _lwids integer[];
        _mwids integer[];
        _hwids integer[];
        _cwids integer[];
BEGIN
        -- Check if user has overidden default webhook end points.
        IF EXISTS (SELECT 1 FROM pem.webhook_alert_config where alert_id = _alert_id) THEN
                RETURN QUERY SELECT alert_id, send_notification,
                                (SELECT array_agg(id) FROM pem.webhook_endpoints we JOIN
                                    unnest(low_webhook_ids) low_ids ON low_ids = we.id WHERE we.enabled = true) AS low_webhook_ids,
                                (SELECT array_agg(id) FROM pem.webhook_endpoints we JOIN
                                    unnest(med_webhook_ids) med_ids ON med_ids = we.id WHERE we.enabled = true) AS med_webhook_ids,
                                (SELECT array_agg(id) FROM pem.webhook_endpoints we JOIN
                                    unnest(high_webhook_ids) high_ids ON high_ids = we.id WHERE we.enabled = true) AS high_webhook_ids,
                                 (SELECT array_agg(id) FROM pem.webhook_endpoints we JOIN
                                    unnest(cleared_webhook_ids) clear_ids ON clear_ids = we.id WHERE we.enabled = true) AS cleared_webhook_ids
                         FROM pem.webhook_alert_config WHERE alert_id = _alert_id AND  send_notification = true LIMIT 1;
        ELSE
                -- Get default webhook end points if not overridden by user
                SELECT array_agg(id) INTO  _lwids FROM pem.webhook_endpoints WHERE enabled = true AND low_alert = true;
                SELECT array_agg(id) INTO  _mwids FROM pem.webhook_endpoints WHERE enabled = true AND med_alert = true;
                SELECT array_agg(id) INTO  _hwids FROM pem.webhook_endpoints WHERE enabled = true AND high_alert = true;
                SELECT array_agg(id) INTO  _cwids FROM pem.webhook_endpoints WHERE enabled = true AND cleared_alert = true;

        RETURN QUERY SELECT
                (SELECT CASE WHEN pa.a = 1 THEN _alert_id ELSE NULL END
                        FROM (SELECT 1 as a FROM pem.alert WHERE id = _alert_id) as pa),
                                true, _lwids, _mwids, _hwids, _cwids;
        END IF;
END;
$$ LANGUAGE plpgsql;

-- JIRA: PEM-3834: Replace json params if not applicable with null

CREATE OR REPLACE FUNCTION pem.replace_json_params(original_string text, to_replace text, replace_with text, additional_flag text)
RETURNS text AS $$
DECLARE
	result text;
BEGIN
    IF replace_with IS NULL OR replace_with = '' THEN
        SELECT concat('"',to_replace,'"') INTO to_replace;
        result = regexp_replace(original_string, to_replace, 'null'::text, additional_flag);
    ELSE
        SELECT replace(replace_with::text,'"','\"') INTO replace_with;
        result = regexp_replace(original_string, to_replace, replace_with::text, additional_flag);
    END IF;
    RETURN result;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- JIRA: PEM-3834: Replace text params if not applicable with blank text

CREATE OR REPLACE FUNCTION pem.replace_text_params(original_string text, to_replace text, replace_with text, additional_flag text)
RETURNS text AS $$
DECLARE
	result text;
BEGIN
    IF replace_with IS NULL OR replace_with = '' THEN
        result = regexp_replace(original_string, to_replace, '', additional_flag);
    ELSE
        result = regexp_replace(original_string, to_replace, replace_with::text, additional_flag);
    END IF;
    RETURN result;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- JIRA: PEM-3734: Create backend schema for webhook.
-- Updated function pem.send_notifications to send the webhooks if enabled
-- Created jobs to purge the old history of webhooks from webhook_spool table
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

DO $DO$
DECLARE
    serverid integer;
    agentid integer;
    job_id integer;

BEGIN
    serverid := -1;
    agentid := -1;
    job_id := -1;

    -- Get agent and server with agent id = 1
    SELECT a.id as agent_id, s.id as server_id INTO agentid, serverid
    FROM pem.agent a
    JOIN pem.agent_server_binding AS asb ON a.id = asb.agent_id
    JOIN pem.server AS s ON s.id = asb.server_id
    WHERE a.id = 1 AND a.active = true AND s.active = true
    ORDER BY a.id, s.id LIMIT 1;

    -- Get agent and server with server id = 1
    IF serverid = -1 OR agentid = -1 THEN
        SELECT a.id as agent, s.id as server_id INTO agentid, serverid
        FROM pem.server s
        JOIN pem.agent_server_binding AS asb ON s.id = asb.server_id
        JOIN pem.agent AS a ON a.id = asb.agent_id
        WHERE s.id = 1 AND s.active = true AND a.active = true
        ORDER BY s.id, a.id LIMIT 1;
    END IF;

    -- If default agent_id=1 & server_id=1 is not found then
    -- get first active agent and server from agent_server binding
    IF serverid = -1 OR agentid = -1 THEN
        SELECT a.id as agent_id, s.id as server_id INTO agentid, serverid
        FROM pem.agent a
        JOIN pem.agent_server_binding AS asb ON a.id = asb.agent_id
        JOIN pem.server AS s ON s.id = asb.server_id
        WHERE a.active = true and s.active = true
        ORDER BY a.id, s.id LIMIT 1;
    END IF;

    -- Webhook spool table cleanup
    -- Check if the job already exists.
    IF NOT EXISTS (SELECT FROM pem.job WHERE jobname = 'Webhook spool table cleanup' AND agent_id = agentid) THEN
        -- Create data purging job.
        INSERT INTO pem.job(jobname, jobdesc, agent_id, issystemjob) VALUES('Webhook spool table cleanup', 'This job runs periodically to purge old data from the webhook spool table.', agentid, true);
    END IF;

    -- Get job id
    SELECT jobid INTO job_id FROM pem.job WHERE jobname = 'Webhook spool table cleanup' AND agent_id = agentid;

    -- Check if the job step already exists.
    IF NOT EXISTS (SELECT FROM pem.jobstep WHERE jstname = 'Webhook spool table cleanup' AND jstjobid = job_id) THEN
        -- Create data purging step.
        INSERT INTO pem.jobstep(jstjobid, jstname, jstdesc, jstkind, jstcode, server_id, database_name) VALUES (job_id, 'Webhook spool table cleanup','This job step runs periodically to purge old data from the webhook spool table.', 's',
        'SELECT pem.purge_webhook_spool()', serverid, 'pem');
    END IF;

    -- Webhook spool history table cleanup
    -- Check if the job already exists.
    IF NOT EXISTS (SELECT FROM pem.job WHERE jobname = 'Webhook spool history table cleanup' AND agent_id = agentid) THEN
        -- Create data purging job.
        INSERT INTO pem.job(jobname, jobdesc, agent_id, issystemjob) VALUES('Webhook spool history table cleanup', 'This job runs periodically to purge old data from the webhook spool history table.', agentid, true);
    END IF;

    -- Get job id
    SELECT jobid INTO job_id FROM pem.job WHERE jobname = 'Webhook spool history table cleanup' AND agent_id = agentid;

    -- Check if the job step already exists.
    IF NOT EXISTS (SELECT FROM pem.jobstep WHERE jstname = 'Webhook spool history table cleanup' AND jstjobid = job_id) THEN
        -- Create data purging step.
        INSERT INTO pem.jobstep(jstjobid, jstname, jstdesc, jstkind, jstcode, server_id, database_name) VALUES (job_id, 'Webhook spool history table cleanup','This job step runs periodically to purge old data from the webhook spool history table.', 's',
        'SELECT pem.purge_webhook_spool_history()', serverid, 'pem');
    END IF;

    CREATE TABLE IF NOT EXISTS pem.webhook_alert_config(
        id bigserial PRIMARY KEY,
        alert_id integer UNIQUE,
        send_notification bool NOT NULL DEFAULT TRUE,
        override_default_config bool NOT NULL DEFAULT FALSE,
        low_webhook_ids integer[],
        med_webhook_ids integer[],
        high_webhook_ids integer[],
        cleared_webhook_ids integer[],
        CONSTRAINT fk_alert_webhook_config_id
          FOREIGN KEY(alert_id)
          REFERENCES pem.alert(id) MATCH SIMPLE
                ON UPDATE NO ACTION
                ON DELETE CASCADE
    );

    COMMENT ON TABLE pem.webhook_alert_config IS 'This contains the information about webhook alert configuration';
    COMMENT ON COLUMN pem.webhook_alert_config.alert_id IS 'This column stores the reference to unique alert id';
    COMMENT ON COLUMN pem.webhook_alert_config.send_notification IS 'This column stores whether to send webhook notification or not';
    COMMENT ON COLUMN pem.webhook_alert_config.override_default_config IS 'This column stores whether default configuration is overridden';
    COMMENT ON COLUMN pem.webhook_alert_config.low_webhook_ids IS 'This column stores all the webhook ids to send low alert';
    COMMENT ON COLUMN pem.webhook_alert_config.med_webhook_ids IS 'This column stores all the webhook ids to send medium alert';
    COMMENT ON COLUMN pem.webhook_alert_config.high_webhook_ids IS 'This column stores all the webhook ids to send high alert';
    COMMENT ON COLUMN pem.webhook_alert_config.cleared_webhook_ids IS 'This column stores all the webhook ids to send cleared alert';

    /********************************
    * WEBHOOK endpoints			*
    ********************************/
    CREATE TABLE IF NOT EXISTS pem.webhook_endpoints
    (
       id           serial,
       name         text NOT NULL,
       url          text NOT NULL,
       enabled      bool,
       method       text NOT NULL,
       payload_template     text NOT NULL,
       low_alert     bool,
       med_alert     bool,
       high_alert    bool,
       cleared_alert bool,
       active        bool default true,
       owner text default current_user,
       CONSTRAINT webhook_endpoints_pk PRIMARY KEY (id),
       CONSTRAINT webhook_endpoints_method CHECK (method IN ('POST', 'PUT'))
    );

    COMMENT ON TABLE pem.webhook_endpoints IS 'This contains the information about webhook endpoints saved by user';
    COMMENT ON COLUMN pem.webhook_endpoints.url IS 'This column stores the webhook URL';
    COMMENT ON COLUMN pem.webhook_endpoints.enabled IS 'This column stores whether webhook is enabled or not';
    COMMENT ON COLUMN pem.webhook_endpoints.method IS 'This column stores the method type (POST/PUT) to be used during request';
    COMMENT ON COLUMN pem.webhook_endpoints.payload_template IS 'This column stores the payload_template for webhook';
    COMMENT ON COLUMN pem.webhook_endpoints.low_alert IS 'This column stores whether to send alert for low alert or not';
    COMMENT ON COLUMN pem.webhook_endpoints.med_alert IS 'This column stores whether to send alert for medium alert or not';
    COMMENT ON COLUMN pem.webhook_endpoints.high_alert IS 'This column stores whether to send alert for high alert or not';
    COMMENT ON COLUMN pem.webhook_endpoints.cleared_alert IS 'This column stores whether to send alert for cleared alert or not';
    COMMENT ON COLUMN pem.webhook_endpoints.owner IS 'This column stores the owner who created this particular webhook endpoint';

    CREATE TABLE IF NOT EXISTS pem.webhook_http_headers
    (
       id                serial,
       webhook_id        int NOT NULL,
       http_header_key   text NOT NULL,
       http_header_value text NOT NULL,
       CONSTRAINT webhook_http_pk PRIMARY KEY (id),
       UNIQUE(webhook_id, http_header_key),
       CONSTRAINT fk_webhook_id
          FOREIGN KEY(webhook_id)
          REFERENCES pem.webhook_endpoints(id) MATCH SIMPLE
            ON UPDATE NO ACTION
            ON DELETE CASCADE
    );

    COMMENT ON TABLE pem.webhook_http_headers IS 'This contains the information about webhook http headers for each wenhook endpoints';
    COMMENT ON COLUMN pem.webhook_http_headers.webhook_id IS 'This column stores the webhook id to which the key-value belongs';
    COMMENT ON COLUMN pem.webhook_http_headers.http_header_key IS 'This column stores webhook http header key';
    COMMENT ON COLUMN pem.webhook_http_headers.http_header_value IS 'This column stores webhook http header value';

    /********************************
    * WEBHOOK Spooler			*
    ********************************/
    INSERT INTO pem.config (param, value, unit, datatype)
    SELECT 'webhook_spool_retention_time', '7', 'days', 'integer'  -- Default values to be used by purging function.
    WHERE NOT EXISTS (
            SELECT param FROM pem.config WHERE param = 'webhook_spool_retention_time'
            );

    CREATE TABLE IF NOT EXISTS pem.webhook_spool
    (
       recorded_time  timestamp with time zone NOT NULL DEFAULT now(),
       id          bigserial,
       webhook_id  integer NOT NULL,
       alert_id    integer NOT NULL,
       agent_id    integer NOT NULL,
       payload     text NOT NULL,
       sent_status    char NOT NULL,
       error          text default '',
       CONSTRAINT webhook_spool_pk PRIMARY KEY (id),
       CONSTRAINT webhook_spool_sent_status CHECK (sent_status IN ('s', 'u', 'f'))
    );

    COMMENT ON TABLE pem.webhook_spool IS 'This contains webhook spooler information';
    COMMENT ON COLUMN pem.webhook_spool.webhook_id IS 'This column stores the webhook id to refer to other webhook endpoints details';
    COMMENT ON COLUMN pem.webhook_spool.alert_id IS 'This column stores alert id to refer to other alert details';
    COMMENT ON COLUMN pem.webhook_spool.agent_id IS 'This column stores agent id for auditing purpose';
    COMMENT ON COLUMN pem.webhook_spool.payload IS 'This column stores the actual payload to be sent';
    COMMENT ON COLUMN pem.webhook_spool.sent_status IS 'This column stores sent status of webhook';
    COMMENT ON COLUMN pem.webhook_spool.error IS 'This column stores the error message if any';

    -- Purge Webhook spool table function
    CREATE INDEX IF NOT EXISTS webhook_spool_recorded_time_idx ON pem.webhook_spool(recorded_time);
    CREATE OR REPLACE FUNCTION pem.purge_webhook_spool()
    RETURNS void AS $$
    DECLARE
       cutoff_ts timestamp with time zone;
    BEGIN
       cutoff_ts := (SELECT now() - CAST(value || ' ' || unit AS interval)
          FROM pem.config WHERE param = 'webhook_spool_retention_time');
       DELETE FROM pem.webhook_spool AS s
       WHERE sent_status = 's' AND s.recorded_time < cutoff_ts;
    END;
    $$ LANGUAGE plpgsql SECURITY DEFINER;

    -- Send Webhook function
    CREATE OR REPLACE FUNCTION pem.send_webhook(webhook_id int, alert_id int, agent_id int, payload text)
    RETURNS boolean AS $$
    BEGIN
        -- Insert the spool record
        INSERT INTO pem.webhook_spool(webhook_id, alert_id, agent_id, payload, sent_status) VALUES(webhook_id, alert_id, agent_id, payload, 'u');
        -- Notify listener
        NOTIFY WEBHOOK_SPOOL;

        RETURN true;
    END;
    $$ LANGUAGE plpgsql SECURITY DEFINER;

    -- Webhook Spool History table

    INSERT INTO pem.config (param, value, unit, datatype)
    SELECT 'webhook_spool_history_retention_time', '15', 'days', 'integer'  -- Default values to be used by purging function.
    WHERE NOT EXISTS (
            SELECT param FROM pem.config WHERE param = 'webhook_spool_history_retention_time'
            );

    CREATE TABLE IF NOT EXISTS pemhistory.webhook_spool
    (
       recorded_time  timestamp with time zone NOT NULL DEFAULT now(),
       id          bigint,
       webhook_id  integer NOT NULL,
       alert_id    integer NOT NULL,
       agent_id    integer NOT NULL,
       payload     text NOT NULL,
       sent_status    char NOT NULL,
       error          text default '',
       CONSTRAINT webhook_spool_sent_status CHECK (sent_status IN ('s', 'u', 'f'))
    );

    COMMENT ON TABLE pemhistory.webhook_spool IS 'This contains webhook spooler history information';
    COMMENT ON COLUMN pemhistory.webhook_spool.webhook_id IS 'This column stores the webhook id to refer to other webhook endpoints details';
    COMMENT ON COLUMN pemhistory.webhook_spool.alert_id IS 'This column stores alert id to refer to other alert details';
    COMMENT ON COLUMN pemhistory.webhook_spool.agent_id IS 'This column stores agent id for auditing purpose';
    COMMENT ON COLUMN pemhistory.webhook_spool.payload IS 'This column stores the actual payload to be sent';
    COMMENT ON COLUMN pemhistory.webhook_spool.sent_status IS 'This column stores sent status of webhook';
    COMMENT ON COLUMN pemhistory.webhook_spool.error IS 'This column stores the error message if any';


    -- Purge Webhook spool history table function
    CREATE INDEX IF NOT EXISTS webhook_spool_history_recorded_time_idx ON pemhistory.webhook_spool(recorded_time);
    CREATE OR REPLACE FUNCTION pem.purge_webhook_spool_history()
    RETURNS void AS $$
    DECLARE
       cutoff_ts timestamp with time zone;
    BEGIN
       cutoff_ts := (SELECT now() - CAST(value || ' ' || unit AS interval)
          FROM pem.config WHERE param = 'webhook_spool_history_retention_time');
       DELETE FROM pemhistory.webhook_spool AS s
       WHERE s.recorded_time < cutoff_ts;
    END;
    $$ LANGUAGE plpgsql SECURITY DEFINER;

    -- To update webhook_spool history table
    CREATE OR REPLACE FUNCTION pem.log_webhook_spool_history() RETURNS TRIGGER AS $$
    BEGIN
       IF (TG_OP = 'INSERT')
          OR (TG_OP = 'UPDATE')
       THEN
          INSERT INTO pemhistory.webhook_spool(id, webhook_id, alert_id, agent_id, payload, sent_status)
          VALUES(
             NEW.id, NEW.webhook_id, NEW.alert_id, NEW.agent_id, NEW.payload, NEW.sent_status
          );
       END IF;
       RETURN new;
    END;
    $$ LANGUAGE plpgsql;

    DROP TRIGGER IF EXISTS log_webhook_spool_history
    ON pem.webhook_spool;

    CREATE TRIGGER log_webhook_spool_history
       AFTER INSERT OR UPDATE ON pem.webhook_spool
       FOR EACH ROW
       EXECUTE PROCEDURE pem.log_webhook_spool_history();

    BEGIN
        IF NOT EXISTS (SELECT 1 FROM pg_catalog.pg_roles WHERE  rolname = 'pem_comp_webhooks') THEN
            PERFORM pem.create_role_for(
                'comp_webhooks',
                'Role to manage (add/delete/update) the tables related to webhooks',
                ARRAY['pem_admin', 'pem_config_alert'],
                -- INSERT
                '{}'::text[],
                -- UPDATE
                '{}'::text[],
                -- DELETE
                '{}'::text[],
                -- ALL
                ARRAY[
                    ARRAY['pem', 'config'],
                    ARRAY['pem', 'webhook_endpoints'],
                    ARRAY['pem', 'webhook_http_headers'],
                    ARRAY['pem', 'webhook_spool']
                ]
            );
        END IF;
    END;

    GRANT SELECT ON TABLE pem.webhook_endpoints TO pem_comp_webhooks;
    GRANT SELECT ON TABLE pem.webhook_http_headers TO pem_comp_webhooks;
    GRANT SELECT ON TABLE pem.webhook_spool TO pem_comp_webhooks;
    GRANT SELECT, DELETE ON TABLE pem.webhook_endpoints TO pem_agent;
    GRANT SELECT ON TABLE pem.webhook_http_headers TO pem_agent;
    GRANT SELECT, UPDATE ON TABLE pem.webhook_spool to pem_agent;
    GRANT ALL ON TABLE pemhistory.webhook_spool TO pem_agent;

END;
$DO$ LANGUAGE 'plpgsql';

DROP FUNCTION IF EXISTS pem.create_alert(text, integer, integer, integer, text, text, text, text, text[], text, numeric[], integer, integer, boolean, boolean, integer, boolean, boolean, timestamp with time zone, boolean, integer, boolean, integer, boolean, integer, boolean, integer, boolean, boolean, boolean, text, boolean);
CREATE OR REPLACE FUNCTION pem.create_alert(
    name				text,
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
    submit_to_nagios boolean DEFAULT false)
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
							execute_script_on_pem_server, script_code, submit_to_nagios)
	VALUES($1, $14, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, $15, $16, $17, $18, $19, $20,
			$21, $22, $23, $24, $25, $26, $27, $28, $29, $30, $31, $32) RETURNING id;
$$ LANGUAGE sql;

-- PEM-3684:- Added info_sql for alert templates

UPDATE pem.alert_template SET info_sql = ( CASE description
 WHEN 'Number of alerts in an error state.'
    THEN $SQL$
        SELECT al.name AS "Alert name", s.description AS "Server name", al.database_name AS "Database name", al.schema_name AS "Schema name",
               al.package_name AS "Package name", al.object_name AS "Object name", al.error_message AS "Error message", al.error_timestamp AS "Error timestamp"
        FROM pem.alert al join pem.server as s on al.server_id = s.id
        WHERE COALESCE(error_message, '') <> ''
        AND al.enabled=true AND CASE WHEN al.agent_id = -1 OR al.agent_id = 0 THEN TRUE
                ELSE al.agent_id IN (SELECT id FROM pem.agent WHERE active AND NOT alert_blackout)
                END
        AND     CASE WHEN al.server_id IS NULL THEN TRUE
                ELSE al.server_id IN (SELECT id FROM pem.server WHERE active AND NOT alert_blackout INTERSECT SELECT server_id FROM pem.agent_server_binding)
        END;
    $SQL$

 WHEN 'Average CPU consumption.'
    THEN $SQL$
        SELECT a.description AS "Agent name",u.core_id AS "Core ID", u.load_percentage AS "Load percentage",u.recorded_time AS "Recorded time"
        FROM pemdata.cpu_usage AS u JOIN pem.agent a ON u.agent_id = a.id
        WHERE u.agent_id = '${agent_id}'
        ORDER BY u.load_percentage DESC;
    $SQL$

 WHEN 'Number of estimated dead tuples in server.'
    THEN $SQL$
        SELECT s.description AS "Server name",ts.database_name AS "Database name",ts.schema_name AS "Schema name",
               ts.table_name AS "Table name", ts.n_dead_tup AS "Dead tuple count", ts.capture_time AS "Capture time",
               CASE WHEN ts.last_vacuum IS NULL THEN 'Never ran' ELSE (ts.last_vacuum::text) END AS "Last vacuum"
        FROM pemdata.table_statistics ts JOIN pem.server s ON ts.server_id = s.id
        WHERE ts.server_id = ${server_id}
        ORDER BY n_dead_tup DESC
        LIMIT 10;
    $SQL$

 WHEN 'Number of estimated dead tuples in database.'
    THEN $SQL$
        SELECT s.description AS "Server name",ts.database_name AS "Database name",ts.schema_name AS "Schema name",
               ts.table_name AS "Table name", ts.n_dead_tup AS "Dead tuple count", ts.capture_time AS "Capture time",
               CASE WHEN ts.last_vacuum IS NULL THEN 'Never ran' ELSE (ts.last_vacuum::text) END AS "Last vacuum"
        FROM pemdata.table_statistics ts JOIN pem.server s ON ts.server_id = s.id
        WHERE ts.server_id = '${server_id}' AND ts.database_name ='${database_name}'
        ORDER BY n_dead_tup DESC
        LIMIT 10;
    $SQL$

 WHEN 'Number of estimated dead tuples in schema.'
    THEN $SQL$
        SELECT s.description AS "Server name",ts.database_name AS "Database name",ts.schema_name AS "Schema name",
               ts.table_name AS "Table name", ts.n_dead_tup AS "Dead tuple count",ts.capture_time AS "Capture time",
               CASE WHEN ts.last_vacuum IS NULL THEN 'Never ran' ELSE (ts.last_vacuum::text) END AS "Last vacuum"
        FROM pemdata.table_statistics ts JOIN pem.server s ON ts.server_id = s.id
        WHERE ts.server_id = '${server_id}' AND ts.database_name ='${database_name}' AND ts.schema_name = '${schema_name}'
        ORDER BY n_dead_tup DESC
        LIMIT 10;
    $SQL$

 WHEN 'Number of estimated dead tuples in table.'
    THEN $SQL$
        SELECT s.description AS "Server name",ts.database_name AS "Database name",ts.schema_name AS "Schema name",
               ts.table_name AS "Table name", ts.n_dead_tup AS "Dead tuple count", ts.capture_time AS "Capture time",
               CASE WHEN ts.last_vacuum IS NULL THEN 'Never ran' ELSE (ts.last_vacuum::text) END AS "Last vacuum"
        FROM pemdata.table_statistics ts JOIN pem.server s ON ts.server_id = s.id
        WHERE ts.server_id = '${server_id}' AND ts.database_name ='${database_name}' AND ts.schema_name = '${schema_name}'AND ts.table_name = '${object_name}';
    $SQL$

 WHEN 'Number of estimated live tuples in server.'
    THEN $SQL$
        SELECT s.description AS "Server name",ts.database_name AS "Database name",ts.schema_name AS "Schema name",
               ts.table_name AS "Table name", ts.n_live_tup AS "Live tuple count", ts.capture_time AS "Capture time",
               CASE WHEN ts.last_vacuum IS NULL THEN 'Never ran' ELSE (ts.last_vacuum::text) END AS "Last vacuum"
        FROM pemdata.table_statistics ts JOIN pem.server s ON ts.server_id = s.id
        WHERE ts.server_id = '${server_id}'
        ORDER BY n_live_tup DESC
        LIMIT 10;
    $SQL$

 WHEN 'Number of estimated live tuples in database.'
    THEN $SQL$
        SELECT s.description AS "Server name",ts.database_name AS "Database name",ts.schema_name AS "Schema name",
               ts.table_name AS "Table name", ts.n_live_tup AS "Live tuple count", ts.capture_time AS "Capture time",
               CASE WHEN ts.last_vacuum IS NULL THEN 'Never ran' ELSE (ts.last_vacuum::text) END AS "Last vacuum"
        FROM pemdata.table_statistics ts JOIN pem.server s ON ts.server_id = s.id
        WHERE ts.server_id = '${server_id}' AND ts.database_name = '${database_name}'
        ORDER BY n_live_tup DESC
        LIMIT 10;
    $SQL$

 WHEN 'Number of estimated live tuples in schema.'
    THEN $SQL$
        SELECT s.description AS "Server name",ts.database_name AS "Database name",ts.schema_name AS "Schema name",
               ts.table_name AS "Table name", ts.n_live_tup AS "Live tuple count", ts.capture_time AS "Capture time",
               CASE WHEN ts.last_vacuum IS NULL THEN 'Never ran' ELSE (ts.last_vacuum::text) END AS "Last vacuum"
        FROM pemdata.table_statistics ts JOIN pem.server s ON ts.server_id = s.id
        WHERE ts.server_id = '${server_id}' AND ts.database_name = '${database_name}' AND ts.schema_name = '${schema_name}'
        ORDER BY n_live_tup DESC
        LIMIT 10;
    $SQL$

 WHEN 'Number of estimated live tuples in table.'
    THEN $SQL$
        SELECT s.description AS "Server name",ts.database_name AS "Database name",ts.schema_name AS "Schema name", ts.table_name AS "Table name", ts.n_live_tup AS "Live tuple count",
               ts.capture_time AS "Capture time",
               CASE WHEN ts.last_vacuum IS NULL THEN 'Never ran' ELSE (ts.last_vacuum::text) END AS "Last vacuum"
        FROM pemdata.table_statistics ts JOIN pem.server s ON ts.server_id = s.id
        WHERE ts.server_id = '${server_id}' AND ts.database_name = '${database_name}' AND ts.schema_name = '${schema_name}' AND ts.table_name ='${object_name}';
    $SQL$

 WHEN 'Swap space consumed (in megabytes).'
    THEN $SQL$
        SELECT ag.description AS "Agent name", mu.total_swap_memory_mb AS "Total swap memory", mu.free_swap_memory_mb AS "Free swap memory",
               mu.total_swap_memory_mb - mu.free_swap_memory_mb AS "Used swap memory", mu.recorded_time AS "Recoreded time"
        FROM pemdata.memory_usage mu JOIN pem.agent ag ON mu.agent_id = ag.id
        WHERE mu.agent_id = '${agent_id}'
        ORDER BY free_swap_memory_mb ASC
        LIMIT 10;
    $SQL$

 WHEN 'Total number of functions in server.'
    THEN $SQL$
        SELECT database_name AS "Database name", schema_name AS "Schema name", count(1) AS "Function count"
        FROM pemdata.oc_function
        WHERE server_id = '${server_id}'
        GROUP BY database_name, schema_name
        ORDER BY database_name;
    $SQL$

 WHEN 'Total number of functions in database.'
    THEN $SQL$
        SELECT database_name AS "Database name", schema_name AS "Schema name", count(1) AS "Function count"
        FROM pemdata.oc_function
        WHERE server_id = '${server_id}' AND database_name = '${database_name}'
        GROUP BY database_name, schema_name
        ORDER BY schema_name;
    $SQL$

 WHEN 'Total number of functions in schema.'
    THEN $SQL$
        SELECT database_name AS "Database name", schema_name AS "Schema name", count(1) AS "Function count"
        FROM pemdata.oc_function
        WHERE server_id = '${server_id}' AND database_name = '${database_name}' AND schema_name = '${schema_name}'
        GROUP BY database_name, schema_name;
    $SQL$

 WHEN 'The total space wasted by tables in server, in MB.'
    THEN $SQL$
        SELECT b.database_name AS "Database name",b.schema_name AS "Schema name",b.table_name AS "Table name", b.estimated_pages AS "Estimated page",
               b.target_pages AS "Target pages",b.estimated_bloat_multiple AS "Estimated bloat multiple",b.estimated_bytes_per_tuple AS "Estimated bytes per tuple",
               b.estimated_pages_wasted::numeric*s.setting::integer/1048576 AS "Table bloat in MB"
        FROM pemdata.table_bloat b JOIN pemdata.settings as s ON b.server_id = s.server_id AND s.name = 'block_size'
        WHERE b.server_id = '${server_id}'
        ORDER BY estimated_pages_wasted DESC
        LIMIT 10;
    $SQL$

 WHEN 'The total space wasted by tables in database, in MB.'
    THEN $SQL$
        SELECT b.database_name AS "Database name",b.schema_name AS "Schema name",b.table_name AS "Table name", b.estimated_pages AS "Estimated page",b.target_pages AS "Target pages",
               b.estimated_bloat_multiple AS "Estimated bloat multiple",b.estimated_bytes_per_tuple AS "Estimated bytes per tuple",
               b.estimated_pages_wasted::numeric*s.setting::integer/1048576 AS "Table bloat in MB"
        FROM pemdata.table_bloat b JOIN pemdata.settings as s ON b.server_id = s.server_id AND s.name = 'block_size'
        WHERE b.server_id = '${server_id}' AND b.database_name = '${database_name}'
        ORDER BY estimated_pages_wasted DESC
        LIMIT 10;
    $SQL$

 WHEN 'The total space wasted by tables in schema, in MB.'
    THEN $SQL$
       SELECT b.database_name AS "Database name",b.schema_name AS "Schema name",b.table_name AS "Table name", b.estimated_pages AS "Estimated page",b.target_pages AS "Target pages",
              b.estimated_bloat_multiple AS "Estimated bloat multiple",b.estimated_bytes_per_tuple AS "Estimated bytes per tuple",
              b.estimated_pages_wasted::numeric*s.setting::integer/1048576 AS "Table bloat in MB"
       FROM pemdata.table_bloat b JOIN pemdata.settings as s ON b.server_id = s.server_id AND s.name = 'block_size'
       WHERE b.server_id = '${server_id}' AND b.database_name = '${database_name}' AND b.schema_name = '${schema_name}'
       ORDER BY estimated_pages_wasted DESC
       LIMIT 10;
    $SQL$

 WHEN 'Space wasted by the table, in MB.'
    THEN $SQL$
        SELECT b.database_name AS "Database name",b.schema_name AS "Schema name",b.table_name AS "Table name", b.estimated_pages AS "Estimated page",b.target_pages AS "Target pages",
               b.estimated_bloat_multiple AS "Estimated bloat multiple",b.estimated_bytes_per_tuple AS "Estimated bytes per tuple",
               b.estimated_pages_wasted::numeric*s.setting::integer/1048576 AS "Table bloat in MB"
        FROM pemdata.table_bloat b JOIN pemdata.settings as s ON b.server_id = s.server_id AND s.name = 'block_size'
        WHERE b.server_id = '${server_id}' AND b.database_name = '${database_name}' AND b.schema_name = '${schema_name}' AND b.table_name = '${object_name}'
        ORDER BY estimated_pages_wasted DESC;
    $SQL$

 WHEN 'The total space wasted by tables on a host, in MB.'
    THEN $SQL$
       SELECT ag.description AS "Agent Name",b.database_name AS "Database name",b.schema_name AS "Schema name",b.table_name AS "Table name", b.estimated_pages AS "Estimated page",
              b.target_pages AS "Target pages",b.estimated_bloat_multiple AS "Estimated bloat multiple",b.estimated_bytes_per_tuple AS "Estimated bytes per tuple",
              b.estimated_pages_wasted::numeric*s.setting::integer/1048576 AS "Table bloat in MB"
       FROM pemdata.table_bloat b JOIN pem.agent_server_binding AS asb ON	b.server_id = asb.server_id
	   JOIN pemdata.settings as s ON b.server_id = s.server_id AND s.name = 'block_size'
	   JOIN pem.agent as ag ON ag.id = asb.agent_id
       WHERE asb.agent_id = '${agent_id}'
       ORDER BY estimated_pages_wasted DESC
       LIMIT 10;
    $SQL$

 WHEN 'Specified server is currently inaccessible.'
    THEN $SQL$
        SELECT ps.description AS "Server description", ps.server AS "IP address", ps.port AS "Server port", ps.serviceid AS "Service ID",
	           psh.last_heartbeat AS "Down since", CASE WHEN ps.is_remote_monitoring = false THEN 'False' ELSE 'True' END AS "Remote monitoring?"
	    FROM
           pem.server ps LEFT OUTER JOIN pem.server_heartbeat psh ON (ps.id = psh.server_id),
           pem.agent pa LEFT OUTER JOIN pem.agent_heartbeat pah ON (pa.id = pah.agent_id),
           pem.agent_server_binding pasb
	    WHERE
           ps.id = '${server_id}' AND
           pa.id = pasb.agent_id AND
           ps.id = pasb.server_id AND
           pa.active = TRUE AND
           ps.active = TRUE AND
           NOT ps.alert_blackout AND
           CASE WHEN psh.agent_id IS NULL THEN FALSE ELSE psh.agent_id = pa.id END AND
           CASE WHEN pah.agent_id is NULL THEN FALSE ELSE pah.last_heartbeat > now() - (pa.heartbeat_interval)*2*'1 second'::interval END AND
           CASE WHEN psh.server_id IS NULL THEN FALSE ELSE psh.last_heartbeat < now() - (pa.heartbeat_interval)*2*'1 second'::interval END;
    $SQL$

 WHEN 'Specified agent is currently down'
    THEN $SQL$
        SELECT pa.description AS "Agent description",pa.platform AS "Agent platform", pah.last_heartbeat AS "Down since", pa.heartbeat_interval AS "Hearbeat interval"
        FROM
          pem.agent pa LEFT OUTER JOIN pem.agent_heartbeat pah ON (pa.id = pah.agent_id)
        WHERE
          pa.id = '${agent_id}' AND
          pa.active = TRUE AND
        NOT pa.alert_blackout AND
        CASE WHEN pah.agent_id IS NULL THEN FALSE ELSE pah.last_heartbeat < now() - (pa.heartbeat_interval)*2*'1 second'::interval END;
    $SQL$

 WHEN 'Number of days before a user''s validity expires.'
    THEN $SQL$
        SELECT	usename AS "Username", DATE_PART('day', min(valuntil::date - capture_time::date)) AS "Days remaining for expiry",
                CASE WHEN usesuper = true THEN 'True' ELSE 'False' END AS "Is superuser?",valuntil AS "Account expires on"
		FROM
		        pemdata.user_info
		WHERE	server_id = '${server_id}'
		AND		valuntil IS NOT NULL
		AND		valuntil NOT IN ('infinity','-infinity')
		AND		valuntil > capture_time
		GROUP BY usename,usesuper,valuntil
		ORDER BY 2 ASC LIMIT 10;
    $SQL$

 WHEN 'Disk space consumed (in megabytes) specified by mount point in "Parameter Options" section.'
    THEN $SQL$
        SELECT mount_point AS "Mount point", file_system AS "File system",size_mb AS "Total Size in MB",space_used_mb AS "Disk consumed in MB",
		   space_available_mb AS "Available space in MB"
	    FROM pemdata.disk_space
	    WHERE  agent_id = '${agent_id}' AND mount_point ='${param_1}';
    $SQL$

 WHEN 'Disk space available (in megabytes) specified by mount point in "Parameter Options" section.'
    THEN $SQL$
        SELECT mount_point AS "Mount point", file_system AS "File system",size_mb AS "Total Size in MB",space_available_mb AS "Available space in MB",
			   space_used_mb AS "Disk consumed in MB"
	    FROM pemdata.disk_space
	    WHERE  agent_id = '${agent_id}' AND mount_point ='${param_1}';
    $SQL$

 WHEN 'Hours since last vacuum on the server.'
    THEN $SQL$
        SELECT s.description AS "Server name",ts.database_name AS "Database name", ts.schema_name AS "Schema name",
			ts.table_name AS "Table name",
			CASE WHEN ts.last_vacuum IS NULL THEN 'Never ran' ELSE (ts.last_vacuum::text) END AS "Last Vacuum",
			CASE WHEN ts.last_autovacuum IS NULL THEN 'Never ran' ELSE (ts.last_autovacuum::text) END AS "Last AutoVacuum"
			FROM pemdata.table_statistics ts JOIN pem.server s ON ts.server_id = s.id
		WHERE	ts.server_id = '${server_id}'
		AND ts.schema_name NOT LIKE 'pg_toast%' AND ts.table_name NOT LIKE 'pg_toast%'
		ORDER BY ts.last_vacuum DESC NULLS LAST LIMIT 1;
    $SQL$

 WHEN 'Hours since last vacuum on the database.'
    THEN $SQL$
        SELECT s.description AS "Server name",ts.database_name AS "Database name", ts.schema_name AS "Schema name",
			ts.table_name AS "Table name",
			CASE WHEN ts.last_vacuum IS NULL THEN 'Never ran' ELSE (ts.last_vacuum::text) END AS "Last Vacuum",
			CASE WHEN ts.last_autovacuum IS NULL THEN 'Never ran' ELSE (ts.last_autovacuum::text) END AS "Last AutoVacuum"
			FROM pemdata.table_statistics ts JOIN pem.server s ON ts.server_id = s.id
		WHERE	ts.server_id = '${server_id}' AND ts.database_name = '${database_name}'
		AND ts.schema_name NOT LIKE 'pg_toast%' AND ts.table_name NOT LIKE 'pg_toast%'
		ORDER BY ts.last_vacuum DESC NULLS LAST LIMIT 1;
    $SQL$

 WHEN 'Hours since last vacuum on the schema.'
    THEN $SQL$
        SELECT s.description AS "Server name",ts.database_name AS "Database name", ts.schema_name AS "Schema name",
			ts.table_name AS "Table name",
			CASE WHEN ts.last_vacuum IS NULL THEN 'Never ran' ELSE (ts.last_vacuum::text) END AS "Last Vacuum",
			CASE WHEN ts.last_autovacuum IS NULL THEN 'Never ran' ELSE (ts.last_autovacuum::text) END AS "Last AutoVacuum"
			FROM pemdata.table_statistics ts JOIN pem.server s ON ts.server_id = s.id
		WHERE	ts.server_id = '${server_id}' AND ts.database_name = '${database_name}' AND ts.schema_name = '${schema_name}'
		AND ts.schema_name NOT LIKE 'pg_toast%' AND ts.table_name NOT LIKE 'pg_toast%'
		ORDER BY ts.last_vacuum DESC NULLS LAST LIMIT 1;
    $SQL$

 WHEN 'Hours since last vacuum on the table.'
    THEN $SQL$
        SELECT s.description AS "Server name",ts.database_name AS "Database name", ts.schema_name AS "Schema name",
			ts.table_name AS "Table name",
			CASE WHEN ts.last_vacuum IS NULL THEN 'Never ran' ELSE (ts.last_vacuum::text) END AS "Last Vacuum",
			CASE WHEN ts.last_autovacuum IS NULL THEN 'Never ran' ELSE (ts.last_autovacuum::text) END AS "Last AutoVacuum"
			FROM pemdata.table_statistics ts JOIN pem.server s ON ts.server_id = s.id
		WHERE	ts.server_id = '${server_id}' AND ts.database_name = '${database_name}' AND ts.schema_name = '${schema_name}' AND ts.table_name = '${object_name}'
		AND ts.schema_name NOT LIKE 'pg_toast%' AND ts.table_name NOT LIKE 'pg_toast%'
		ORDER BY ts.last_vacuum DESC NULLS LAST LIMIT 1;
    $SQL$

 WHEN 'Hours since last autovacuum on the server.'
    THEN $SQL$
        SELECT s.description AS "Server name",ts.database_name AS "Database name", ts.schema_name AS "Schema name",
			ts.table_name AS "Table name",
			CASE WHEN ts.last_autovacuum IS NULL THEN 'Never ran' ELSE (ts.last_autovacuum::text) END AS "Last AutoVacuum",
			CASE WHEN ts.last_vacuum IS NULL THEN 'Never ran' ELSE (ts.last_vacuum::text) END AS "Last Vacuum"
			FROM pemdata.table_statistics ts JOIN pem.server s ON ts.server_id = s.id
		WHERE	ts.server_id = '${server_id}'
		AND ts.schema_name NOT LIKE 'pg_toast%' AND ts.table_name NOT LIKE 'pg_toast%'
		ORDER BY ts.last_autovacuum DESC NULLS LAST LIMIT 1;
    $SQL$

 WHEN 'Hours since last autovacuum on the database.'
    THEN $SQL$
        SELECT s.description AS "Server name",ts.database_name AS "Database name", ts.schema_name AS "Schema name",
			ts.table_name AS "Table name",
			CASE WHEN ts.last_autovacuum IS NULL THEN 'Never ran' ELSE (ts.last_autovacuum::text) END AS "Last AutoVacuum",
			CASE WHEN ts.last_vacuum IS NULL THEN 'Never ran' ELSE (ts.last_vacuum::text) END AS "Last Vacuum"
			FROM pemdata.table_statistics ts JOIN pem.server s ON ts.server_id = s.id
		WHERE	ts.server_id = '${server_id}' AND ts.database_name = '${database_name}'
		AND ts.schema_name NOT LIKE 'pg_toast%' AND ts.table_name NOT LIKE 'pg_toast%'
		ORDER BY ts.last_autovacuum DESC NULLS LAST LIMIT 1;
    $SQL$

 WHEN 'Hours since last autovacuum on the schema.'
    THEN $SQL$
        SELECT s.description AS "Server name",ts.database_name AS "Database name", ts.schema_name AS "Schema name",
			ts.table_name AS "Table name",
			CASE WHEN ts.last_autovacuum IS NULL THEN 'Never ran' ELSE (ts.last_autovacuum::text) END AS "Last AutoVacuum",
			CASE WHEN ts.last_vacuum IS NULL THEN 'Never ran' ELSE (ts.last_vacuum::text) END AS "Last Vacuum"
			FROM pemdata.table_statistics ts JOIN pem.server s ON ts.server_id = s.id
		WHERE	ts.server_id = '${server_id}' AND ts.database_name = '${database_name}' AND	ts.schema_name = '${schema_name}'
		AND ts.schema_name NOT LIKE 'pg_toast%' AND ts.table_name NOT LIKE 'pg_toast%'
		ORDER BY ts.last_autovacuum DESC NULLS LAST LIMIT 1;
    $SQL$

 WHEN 'Hours since last autovacuum on the table.'
    THEN $SQL$
        SELECT s.description AS "Server name",ts.database_name AS "Database name", ts.schema_name AS "Schema name",
			ts.table_name AS "Table name",
			CASE WHEN ts.last_autovacuum IS NULL THEN 'Never ran' ELSE (ts.last_autovacuum::text) END AS "Last AutoVacuum",
			CASE WHEN ts.last_vacuum IS NULL THEN 'Never ran' ELSE (ts.last_vacuum::text) END AS "Last Vacuum"
			FROM pemdata.table_statistics ts JOIN pem.server s ON ts.server_id = s.id
		WHERE	ts.server_id = '${server_id}' AND ts.database_name = '${database_name}' AND	ts.schema_name = '${schema_name}' AND ts.table_name = '${object_name}'
		AND ts.schema_name NOT LIKE 'pg_toast%' AND ts.table_name NOT LIKE 'pg_toast%'
		ORDER BY ts.last_autovacuum DESC NULLS LAST;
    $SQL$

 WHEN 'Hours since last analyze on the server.'
    THEN $SQL$
        SELECT s.description AS "Server name",ts.database_name AS "Database name",ts.schema_name AS "Schema name",ts.table_name AS "Table name",
		   CASE WHEN ts.last_analyze IS NULL THEN 'Never ran' ELSE (ts.last_analyze::text) END AS "Last analyze",
		   CASE WHEN ts.last_autoanalyze IS NULL THEN 'Never ran' ELSE (ts.last_autoanalyze::text) END AS "Last autoanalyze"
	    FROM pemdata.table_statistics ts JOIN pem.server s ON ts.server_id = s.id
	    WHERE	ts.server_id = '${server_id}'
	    AND ts.schema_name NOT LIKE 'pg_toast%' AND ts.table_name NOT LIKE 'pg_toast%'
	    ORDER BY ts.last_analyze DESC NULLS LAST LIMIT 1;
    $SQL$

 WHEN 'Hours since last analyze on the database.'
    THEN $SQL$
        SELECT s.description AS "Server name",ts.database_name AS "Database name",ts.schema_name AS "Schema name",ts.table_name AS "Table name",
		   CASE WHEN ts.last_analyze IS NULL THEN 'Never ran' ELSE (ts.last_analyze::text) END AS "Last analyze",
		   CASE WHEN ts.last_autoanalyze IS NULL THEN 'Never ran' ELSE (ts.last_autoanalyze::text) END AS "Last autoanalyze"
	    FROM pemdata.table_statistics ts JOIN pem.server s ON ts.server_id = s.id
	    WHERE	ts.server_id = '${server_id}' AND ts.database_name = '${database_name}'
	    AND ts.schema_name NOT LIKE 'pg_toast%' AND ts.table_name NOT LIKE 'pg_toast%'
	    ORDER BY ts.last_analyze DESC NULLS LAST LIMIT 1;
    $SQL$

 WHEN 'Hours since last analyze on the schema.'
    THEN $SQL$
        SELECT s.description AS "Server name",ts.database_name AS "Database name",ts.schema_name AS "Schema name",ts.table_name AS "Table name",
		   CASE WHEN ts.last_analyze IS NULL THEN 'Never ran' ELSE (ts.last_analyze::text) END AS "Last analyze",
		   CASE WHEN ts.last_autoanalyze IS NULL THEN 'Never ran' ELSE (ts.last_autoanalyze::text) END AS "Last autoanalyze"
	    FROM pemdata.table_statistics ts JOIN pem.server s ON ts.server_id = s.id
	    WHERE	ts.server_id = '${server_id}' AND ts.database_name = '${database_name}' AND ts.schema_name = '${schema_name}'
	    AND ts.schema_name NOT LIKE 'pg_toast%' AND ts.table_name NOT LIKE 'pg_toast%'
	    ORDER BY ts.last_analyze DESC NULLS LAST LIMIT 1;
    $SQL$

 WHEN 'Hours since last analyze on the table.'
    THEN $SQL$
        SELECT s.description AS "Server name",ts.database_name AS "Database name",ts.schema_name AS "Schema name",ts.table_name AS "Table name",
		   CASE WHEN ts.last_analyze IS NULL THEN 'Never ran' ELSE (ts.last_analyze::text) END AS "Last analyze",
		   CASE WHEN ts.last_autoanalyze IS NULL THEN 'Never ran' ELSE (ts.last_autoanalyze::text) END AS "Last autoanalyze"
	    FROM pemdata.table_statistics ts JOIN pem.server s ON ts.server_id = s.id
	    WHERE	ts.server_id = '${server_id}' AND ts.database_name = '${database_name}' AND ts.schema_name = '${schema_name}' AND ts.table_name = '${object_name}'
	    AND ts.schema_name NOT LIKE 'pg_toast%' AND ts.table_name NOT LIKE 'pg_toast%'
	    ORDER BY ts.last_analyze DESC NULLS LAST LIMIT 1;
    $SQL$

 WHEN 'Hours since last autoanalyze on the server.'
    THEN $SQL$
        SELECT s.description AS "Server name",ts.database_name AS "Database name",ts.schema_name AS "Schema name",ts.table_name AS "Table name",
		   CASE WHEN ts.last_autoanalyze IS NULL THEN 'Never ran' ELSE (ts.last_autoanalyze::text) END AS "Last autoanalyze",
		   CASE WHEN ts.last_analyze IS NULL THEN 'Never ran' ELSE (ts.last_analyze::text) END AS "Last analyze"
	    FROM pemdata.table_statistics ts JOIN pem.server s ON ts.server_id = s.id
	    WHERE	ts.server_id = '${server_id}'
	    AND ts.schema_name NOT LIKE 'pg_toast%' AND ts.table_name NOT LIKE 'pg_toast%'
	    ORDER BY ts.last_autoanalyze DESC NULLS LAST LIMIT 1;
    $SQL$

 WHEN 'Hours since last autoanalyze on the database.'
    THEN $SQL$
        SELECT s.description AS "Server name",ts.database_name AS "Database name",ts.schema_name AS "Schema name",ts.table_name AS "Table name",
		   CASE WHEN ts.last_autoanalyze IS NULL THEN 'Never ran' ELSE (ts.last_autoanalyze::text) END AS "Last autoanalyze",
		   CASE WHEN ts.last_analyze IS NULL THEN 'Never ran' ELSE (ts.last_analyze::text) END AS "Last analyze"
	    FROM pemdata.table_statistics ts JOIN pem.server s ON ts.server_id = s.id
	    WHERE	ts.server_id = '${server_id}' AND ts.database_name = '${database_name}'
	    AND ts.schema_name NOT LIKE 'pg_toast%' AND ts.table_name NOT LIKE 'pg_toast%'
	    ORDER BY ts.last_autoanalyze DESC NULLS LAST LIMIT 1;
    $SQL$

 WHEN 'Hours since last autoanalyze on the schema.'
    THEN $SQL$
        SELECT s.description AS "Server name",ts.database_name AS "Database name",ts.schema_name AS "Schema name",ts.table_name AS "Table name",
		   CASE WHEN ts.last_autoanalyze IS NULL THEN 'Never ran' ELSE (ts.last_autoanalyze::text) END AS "Last autoanalyze",
		   CASE WHEN ts.last_analyze IS NULL THEN 'Never ran' ELSE (ts.last_analyze::text) END AS "Last analyze"
	    FROM pemdata.table_statistics ts JOIN pem.server s ON ts.server_id = s.id
	    WHERE	ts.server_id = '${server_id}' AND ts.database_name = '${database_name}' AND ts.schema_name = '${schema_name}'
	    AND ts.schema_name NOT LIKE 'pg_toast%' AND ts.table_name NOT LIKE 'pg_toast%'
	    ORDER BY ts.last_autoanalyze DESC NULLS LAST LIMIT 1;
    $SQL$

 WHEN 'Hours since last autoanalyze on the table.'
    THEN $SQL$
        SELECT s.description AS "Server name",ts.database_name AS "Database name",ts.schema_name AS "Schema name",ts.table_name AS "Table name",
		   CASE WHEN ts.last_autoanalyze IS NULL THEN 'Never ran' ELSE (ts.last_autoanalyze::text) END AS "Last autoanalyze",
		   CASE WHEN ts.last_analyze IS NULL THEN 'Never ran' ELSE (ts.last_analyze::text) END AS "Last analyze"
	    FROM pemdata.table_statistics ts JOIN pem.server s ON ts.server_id = s.id
	    WHERE	ts.server_id = '${server_id}' AND ts.database_name = '${database_name}' AND ts.schema_name = '${schema_name}' AND ts.table_name = '${object_name}'
	    AND ts.schema_name NOT LIKE 'pg_toast%' AND ts.table_name NOT LIKE 'pg_toast%'
	    ORDER BY ts.last_autoanalyze DESC NULLS LAST;
    $SQL$
END
)
WHERE description IN (
'Number of alerts in an error state.',
'Average CPU consumption.',
'Number of estimated dead tuples in server.',
'Number of estimated dead tuples in database.',
'Number of estimated dead tuples in schema.',
'Number of estimated dead tuples in table.',
'Number of estimated live tuples in server.',
'Number of estimated live tuples in database.',
'Number of estimated live tuples in schema.',
'Number of estimated live tuples in table.',
'Swap space consumed (in megabytes).',
'Total number of functions in server.',
'Total number of functions in database.',
'Total number of functions in schema.',
'The total space wasted by tables in server, in MB.',
'The total space wasted by tables in database, in MB.',
'The total space wasted by tables in schema, in MB.',
'Space wasted by the table, in MB.',
'The total space wasted by tables on a host, in MB.',
'Specified server is currently inaccessible.',
'Specified agent is currently down',
'Number of days before a user''s validity expires.',
'Disk space consumed (in megabytes) specified by mount point in "Parameter Options" section.',
'Disk space available (in megabytes) specified by mount point in "Parameter Options" section.',
'Hours since last vacuum on the server.',
'Hours since last vacuum on the database.',
'Hours since last vacuum on the schema.',
'Hours since last vacuum on the table.',
'Hours since last autovacuum on the server.',
'Hours since last autovacuum on the database.',
'Hours since last autovacuum on the schema.',
'Hours since last autovacuum on the table.',
'Hours since last analyze on the server.',
'Hours since last analyze on the database.',
'Hours since last analyze on the schema.',
'Hours since last analyze on the table.',
'Hours since last autoanalyze on the server.',
'Hours since last autoanalyze on the database.',
'Hours since last autoanalyze on the schema.',
'Hours since last autoanalyze on the table.'
);

-- Fixed typo in display name for two alerts

UPDATE pem.alert_template SET display_name = (
	CASE description
		WHEN 'Size of the table as a multiple of estimated unbloated size.'
			THEN 'Table size as a multiple of unbloated size'

		WHEN 'Size of the materialized view as a multiple of estimated unbloated size specified in "Parameter Options" section.'
			THEN 'Materialized view size as a multiple of unbloated size'
	END
)
WHERE description IN ('Size of the table as a multiple of estimated unbloated size.',
'Size of the materialized view as a multiple of estimated unbloated size specified in "Parameter Options" section.'
);

-- Fixed sql for alert template 'A user expires in N days' as it was failing to invalid input syntax for type numeric:

UPDATE pem.alert_template SET sql = $sql$
	SELECT	DATE_PART('day', min(valuntil::date - capture_time::date))
	FROM pemdata.user_info
	WHERE server_id = ${server_id}
	AND	valuntil IS NOT NULL
	AND	valuntil NOT IN ('infinity','-infinity')
	AND	valuntil > capture_time;$sql$
where description = 'Number of days before a user''s validity expires.';

-- JIRA: PEM-3833, Update all the servers which were added by auto discovery
-- which does not have valid SSL column value in the backend, we will set it
-- to 'prefer' mode
UPDATE pem.server SET ssl = 2
WHERE ssl = 0;

END TRANSACTION;
