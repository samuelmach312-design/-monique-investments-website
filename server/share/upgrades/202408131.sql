/***************************************************************************
 *
 * Postgres Enterprise Manager
 *
 * Copyright (C) 2010 - 2025, EnterpriseDB Corporation. All rights reserved.
 *
 ***************************************************************************/

-- NOTE: This sql file is responsible for PEM 9.7.0 schema upgrade.

BEGIN TRANSACTION;

    CREATE OR REPLACE FUNCTION pem.schema_version() RETURNS integer AS
        'SELECT 202408131::integer;'
    LANGUAGE 'sql' IMMUTABLE;
    COMMENT ON FUNCTION pem.schema_version() IS
        'Returns the version number of the PEM schema';

    -- Add new column "rerun_on_restart" to pem.probe
    ALTER TABLE pem.probe ADD COLUMN IF NOT EXISTS rerun_on_restart boolean NOT NULL DEFAULT false;
    UPDATE pem.probe
    SET rerun_on_restart = true
    WHERE internal_name IN ('server_info', 'pg_hba_conf', 'settings', 'audit_configuration', 'log_configuration', 'os_info');

    -- Remove the entry of the probe for the specific monitoring target(s) to force rerun a probe
    -- They will be picked up in next run automatically (if the probe is not disabled).
    CREATE OR REPLACE FUNCTION pem.rerun_probes_on_agent_restart(agent_id integer)
    RETURNS VOID AS $$
    BEGIN
        DELETE FROM pem.probe_schedule
            WHERE probe_id IN(SELECT id FROM pem.probe WHERE rerun_on_restart = 't' and target_type_id = 100)
                AND $1::text=ANY(parameter_value_list);
    END;
    $$ LANGUAGE plpgsql;

    CREATE OR REPLACE FUNCTION pem.rerun_probes_on_server_restart(server_id integer)
    RETURNS VOID AS $$
    BEGIN
        DELETE FROM pem.probe_schedule
            WHERE probe_id IN(SELECT id FROM pem.probe WHERE rerun_on_restart = 't' and target_type_id = 200)
                AND $1::text=ANY(parameter_value_list);
    END;
    $$ LANGUAGE plpgsql;

    -- trggered when an agent is restarted
    CREATE OR REPLACE FUNCTION pem.agent_restarted(agent_id integer)
    RETURNS text AS $$
    BEGIN
        RETURN (SELECT pem.rerun_probes_on_agent_restart($1::integer));
    END;
    $$ LANGUAGE plpgsql;

    -- trggered when an monitored is restarted
    CREATE OR REPLACE FUNCTION pem.server_restarted(server_id integer)
    RETURNS text AS $$
    BEGIN
        RETURN (SELECT pem.rerun_probes_on_server_restart($1::integer));
    END;
    $$ LANGUAGE plpgsql;

    -- PEM-5221: fix possible trademark infringements
    COMMENT ON SCHEMA pem IS 'Postgres Enterprise Manager Internal Tables';
    COMMENT ON SCHEMA pemdata IS 'Postgres Enterprise Manager Monitoring Data';
    COMMENT ON SCHEMA pemhistory IS 'Postgres Enterprise Manager Historical Data';

    -- PEM-5272: setting current pid to null if agent_id is null in probe_schedule table
    CREATE OR REPLACE FUNCTION pem.clear_probe_zombies(agent_id integer = NULL)
    RETURNS void AS $FUNC$
    BEGIN
        -- New agents will clear from its own zombie probes
        IF agent_id IS NOT NULL THEN
            UPDATE pem.probe_schedule s
            SET current_backend_pid = NULL, agent_id = NULL WHERE s.agent_id = $1;
            -- Clear all probes with no agent attached.
            UPDATE pem.probe_schedule s
            SET current_backend_pid = NULL
            WHERE current_backend_pid is not NULL AND s.agent_id IS NULL;
        ELSE
            WITH pids (pid) AS (
                SELECT ps.current_backend_pid FROM pem.probe_schedule AS ps
                WHERE NOT EXISTS (
                    SELECT 1 FROM pg_catalog.pg_stat_activity AS a
                    WHERE a.pid = ps.current_backend_pid
                )
                ORDER BY ps.current_backend_pid
                FOR UPDATE SKIP LOCKED
            )
            UPDATE pem.probe_schedule AS ps SET current_backend_pid = NULL, agent_id = NULL
            WHERE ps.current_backend_pid IN (SELECT pid FROM pids);
        END IF;
    END;
    $FUNC$ LANGUAGE 'plpgsql';

    -- PEM-5170: `reminder_notification_interval` to support values < 1 hour
    UPDATE pem.config
    SET value = value::numeric * 60, unit = 'minutes'
    WHERE param = 'reminder_notification_interval' AND unit != 'minutes';

    -- PEM-5291: Edited the logic to send the Servers/Agents Down alerts to send the down object list as a part of detail info sql
    UPDATE pem.email_template SET mail_message=E'Alert Details\n------------------------\nAlert Name: %AlertName%\nServer/Agent: %ObjectName%\nCurrent Value: %CurrentValue%\nThreshold Value: %ThresholdValue%\nAlert Detected: %AlertDetected%\nDetail Information: \n%DetailInfo%' WHERE display_name='Alert Detected';
    UPDATE pem.email_template SET mail_message=E'Alert Details\n------------------------\nAlert Name: %AlertName%\nServer/Agent: %ObjectName%\nCurrent Value: %CurrentValue%\nThreshold Value: %ThresholdValue%\nCurrent State: %CurrentState%\nOld State: %OldState%\nState Changed: %StateChanged%\nDetail Information: \n%DetailInfo%' WHERE display_name='Alert Level Increased';
    UPDATE pem.email_template SET mail_message=E'Alert Details\n------------------------\nAlert Name: %AlertName%\nServer/Agent: %ObjectName%\nCurrent Value: %CurrentValue%\nThreshold Value: %ThresholdValue%\nCurrent State: %CurrentState%\nOld State: %OldState%\nState Changed: %StateChanged%\nDetail Information: \n%DetailInfo%' WHERE display_name='Alert Level Decreased';
    UPDATE pem.email_template SET mail_message=E'Alert Details\n------------------------\nAlert Name: %AlertName%\nCurrent Value: %CurrentValue%\nThreshold Value: %ThresholdValue%\nCurrent State: %CurrentState%\nAlerting Since: %AlertingSince%\nDetail Information: \n%DetailInfo%' WHERE display_name='Alert Reminder';

    CREATE OR REPLACE FUNCTION pem.process_one_alert() RETURNS BOOL AS $$
        DECLARE
           err          text;
           sql          text;
           state        pem.alert_state;
           sql_ret          numeric;
           alert_rec     record;
           locked_alert      bool;
           probe_disabled_err text;
           zero_rows_err     text;
           probe_enabled     bool;
           all_probes_enabled bool;
           alert_state_since  timestamp with time zone;
           reminder_interval  integer;
           subject          text;
           message          text;
           send_mail_val     bool;
           min_probe_interval integer;
           probe_interval    integer;
           default_flapping_detection_state_change integer;
           down_objects_list text;
           template_name text;
           mail_group_id integer[];
           alert_info    text;
           sql_curs         REFCURSOR;
           sql_rec       RECORD;
           hs_row        RECORD;
           first_time    boolean := FALSE;
           sql_ret_display text := '';

        BEGIN
           probe_disabled_err := 'Required probe(s) ';
           zero_rows_err := 'Zero rows returned';

           locked_alert := false;

           FOR alert_rec in   SELECT al.*, ast.current_state AS state, at.sql, at.display_name AS template_name,
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
              IF (pg_catalog.pg_try_advisory_lock(0, alert_rec.id) = true) THEN
                 locked_alert := true;
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

           sql := alert_rec.sql;

           /* Replace any reference to hierarchy-related alert parameters */
           sql := regexp_replace(sql, E'\\${agent_id}',      COALESCE(alert_rec.agent_id::text, '')::text, 'g');
           sql := regexp_replace(sql, E'\\${server_id}',  COALESCE(alert_rec.server_id::text,    '')::text, 'g');
           sql := regexp_replace(sql, E'\\${database_name}',COALESCE(alert_rec.database_name, '')::text, 'g');
           sql := regexp_replace(sql, E'\\${schema_name}',    COALESCE(alert_rec.schema_name,       '')::text, 'g');
           sql := regexp_replace(sql, E'\\${package_name}',   COALESCE(alert_rec.package_name,   '')::text, 'g');
           sql := regexp_replace(sql, E'\\${object_name}',    COALESCE(alert_rec.object_name,       '')::text, 'g');

           /* Replace ${param_n} with corresponding alert parameters */
           FOR i IN 1..COALESCE(array_upper(alert_rec.params, 1), 0) LOOP
              sql := regexp_replace(sql, E'\\${param_' || i || '}', alert_rec.params[i]::text, 'g');
           END LOOP;

           err := '';

           /* Check any required probe is disabled from the probe dependency list */
           all_probes_enabled := true;
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
                 probe_disabled_err := probe_disabled_err || alert_rec.probe_dependency_list[i] || ',';
                 all_probes_enabled := false;
              END IF;

              -- Get minimum probe interval from all dependent probes
              SELECT default_execution_frequency INTO probe_interval FROM pem.probe WHERE internal_name = alert_rec.probe_dependency_list[i];
              IF (probe_interval <  min_probe_interval) OR (i = 1) THEN
                 min_probe_interval := probe_interval;
              END IF;
           END LOOP;

           probe_disabled_err := trim(trailing ',' from probe_disabled_err);
           probe_disabled_err := probe_disabled_err || ' are disabled.';

           IF NOT all_probes_enabled THEN
              err := probe_disabled_err;
           ELSE
              RAISE DEBUG 'Alert query being executed: %', sql;

              BEGIN
                 OPEN sql_curs FOR EXECUTE sql;
                 LOOP
                    FETCH NEXT FROM sql_curs INTO sql_rec;
                    EXIT WHEN NOT FOUND;
                    -- Loop through the output of the query using hstore.
                    FOR hs_row IN SELECT kv."key", kv."value" FROM public.each(public.hstore(sql_rec)) kv
                    LOOP
                       -- First column is our curernt value and second column is the display
                       -- value if provided in the SQL query.
                       IF first_time IS FALSE THEN
                          sql_ret := COALESCE(hs_row."value", NULL);
                          first_time := TRUE;
                       ELSE
                          sql_ret_display := COALESCE(hs_row."value", '');
                       END IF;
                    END LOOP;
                 END LOOP;
                 CLOSE sql_curs;
              EXCEPTION
                 WHEN no_data_found THEN
                   IF all_probes_enabled THEN
                     err := '';
                   END IF;

                 WHEN OTHERS THEN
                    err := SQLERRM;
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
                 state := 'HIGH';
              ELSIF (sql_ret < alert_rec.thresholds[2]) THEN
                 state := 'MEDIUM';
              ELSIF (sql_ret < alert_rec.thresholds[1]) THEN
                 state := 'LOW';
              ELSE
                 state := NULL;
              END IF;
           ELSIF (alert_rec.operator = '>') THEN
              IF (sql_ret > alert_rec.thresholds[3]) THEN
                 state := 'HIGH';
              ELSIF (sql_ret > alert_rec.thresholds[2]) THEN
                 state := 'MEDIUM';
              ELSIF (sql_ret > alert_rec.thresholds[1]) THEN
                 state := 'LOW';
              ELSE
                 state := NULL;
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
            *        set acked := false
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
                    send_mail_val := pem.send_email(mail_group_id, subject, message);
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
              display_value = sql_ret_display,
              current_state = state, -- may be NULL
              current_state_since =  CASE
                                WHEN state IS DISTINCT FROM alert_rec.state
                                THEN now()
                                ELSE current_state_since
                                END
           WHERE alert_id = alert_rec.id;

           -- If there wasn't any status row for this alert already, then populate one.
           IF (NOT FOUND) THEN
              INSERT INTO pem.alert_status("alert_id", "current_value", "current_state",
                  "current_state_since", "last_processed", "display_value")
              VALUES (alert_rec.id, sql_ret, state,
                    CASE
                    WHEN state IS NOT NULL
                    THEN now()
                    ELSE NULL
                    END,
                    now(), sql_ret_display);
           END IF;

           -- Check for reminder notification
           SELECT value INTO reminder_interval FROM pem.config WHERE param = 'reminder_notification_interval';
           SELECT current_state_since INTO alert_state_since FROM pem.alert_status WHERE alert_id = alert_rec.id;
           IF alert_rec.send_email AND (NOT alert_rec.acknowledged) AND (alert_state_since IS NOT NULL) AND (state IS NOT NULL) AND (NOT alert_rec.flapping_detected)
           AND ((now() - alert_state_since) >= (reminder_interval||'minutes')::interval)
           AND ((now() - alert_rec.last_mail_send) >= (reminder_interval||'minutes')::interval) THEN

              -- Create subject and message
              SELECT subject_mail, message_mail INTO subject, message FROM pem.create_email(alert_rec.id, 'Alert Reminder');
              SELECT info INTO alert_info FROM pem.alert_status WHERE alert_id = alert_rec.id;
              message := regexp_replace(message, '%CurrentState%', state::text, 'g');
              message := regexp_replace(message, '%AlertingSince%', alert_state_since::text, 'g');
              CASE WHEN sql_ret_display IS NOT NULL AND sql_ret_display != '' THEN
                 message := regexp_replace(message, '%CurrentValue%', COALESCE(sql_ret_display, 0::text), 'g');
              ELSE
                 message := regexp_replace(message, '%CurrentValue%', COALESCE(sql_ret, 0)::text, 'g');
              END CASE;

              message := regexp_replace(message, '%DetailInfo%', COALESCE(alert_info, 'None')::text, 'g');

              send_mail_val := pem.send_email(mail_group_id, subject, message);
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

    UPDATE pem.alert_template
    SET info_sql = E'SELECT id as "Server ID", description || '' ('' || server || '':'' || port || '')'' AS "Description" FROM pem.get_servers_with_status(''DOWN'') AS rec(id integer, description text, server text, port integer);'
    WHERE display_name = E'Servers Down';

    UPDATE pem.alert_template
    SET info_sql = E'SELECT id as "Agent ID", description AS "Description" FROM pem.get_agents_with_status(''DOWN'') AS rec(id integer, description text);'
    WHERE display_name = E'Agents Down';

    -- PEM-5307: Fixed the user_info probe to get the exact password expiry
    UPDATE pem.probe_server_version SET probe_code = 'SELECT usename, usesuper, valuntil, useconfig, now() as capture_time, pg_catalog.edb_get_password_expiry_date(usesysid) as usepasswordexpire FROM pg_catalog.pg_user'
    WHERE probe_id = (SELECT id from pem.probe WHERE internal_name = 'user_info')
    AND server_version_id IN (21100, 21200, 21300, 21400, 21500, 21600);

END TRANSACTION;

