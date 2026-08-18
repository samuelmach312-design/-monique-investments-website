/***************************************************************************
 *
 * Postgres Enterprise Manager
 *
 * Copyright (C) 2010 - 2025, EnterpriseDB Corporation. All rights reserved.
 *
 ***************************************************************************/

BEGIN TRANSACTION;

CREATE OR REPLACE FUNCTION pem.schema_version()
  RETURNS integer AS
'SELECT 201901151::integer;'
  LANGUAGE 'sql' IMMUTABLE;
COMMENT ON FUNCTION pem.schema_version() IS
 'Returns the version number of the PEM schema';

-- Drop existing trigger as we do not have create/replace trigger.
DROP TRIGGER IF EXISTS detail_alert_information on pem.alert_status;

-- Create  trigger with updated definitions.
CREATE TRIGGER detail_alert_information
        AFTER INSERT OR UPDATE ON pem.alert_status
        FOR EACH ROW
        EXECUTE PROCEDURE pem.get_detail_alert_info();


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
	mail_group_id integer[];
	alert_info    text;
	sql_curs			REFCURSOR;
	sql_rec       RECORD;
	hs_row        RECORD;
	first_time    boolean := FALSE;
	sql_ret_display text := '';

BEGIN
	probe_disabled_err := 'Required probe(s) ';
	zero_rows_err := 'Zero rows returned';

	locked_alert := false;

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
	sql := regexp_replace(sql, E'\\${agent_id}',		COALESCE(alert_rec.agent_id::text,	'')::text, 'g');
	sql := regexp_replace(sql, E'\\${server_id}',	COALESCE(alert_rec.server_id::text,	'')::text, 'g');
	sql := regexp_replace(sql, E'\\${database_name}',COALESCE(alert_rec.database_name,	'')::text, 'g');
	sql := regexp_replace(sql, E'\\${schema_name}',	COALESCE(alert_rec.schema_name,		'')::text, 'g');
	sql := regexp_replace(sql, E'\\${package_name}',	COALESCE(alert_rec.package_name,	'')::text, 'g');
	sql := regexp_replace(sql, E'\\${object_name}',	COALESCE(alert_rec.object_name,		'')::text, 'g');

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
				FOR hs_row IN SELECT kv."key", kv."value" FROM each(hstore(sql_rec)) kv
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
		current_state_since =	CASE
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
	AND ((now() - alert_state_since) >= (reminder_interval||'hours')::interval)
	AND ((now() - alert_rec.last_mail_send) >= (reminder_interval||'hours')::interval) THEN

		-- Create subject and message
		SELECT subject_mail, message_mail INTO subject, message FROM pem.create_email(alert_rec.id, 'Alert Reminder');
		SELECT info INTO alert_info FROM pem.alert_status WHERE alert_id = alert_rec.id;
		message := regexp_replace(message, '%CurrentState%', state::text);
		message := regexp_replace(message, '%AlertingSince%', alert_state_since::text);
		CASE WHEN sql_ret_display IS NOT NULL AND sql_ret_display != '' THEN
			message := regexp_replace(message, '%CurrentValue%', COALESCE(sql_ret_display, 0::text));
		ELSE
			message := regexp_replace(message, '%CurrentValue%', COALESCE(sql_ret, 0)::text);
		END CASE;

		-- Get the list of down objetcs
		down_objects_list := pem.get_down_objects_list(alert_rec.template_name);
		message := regexp_replace(message, '%DownObjects%', down_objects_list::text);
		message := regexp_replace(message, '%DetailInfo%', COALESCE(alert_info, 'None')::text);

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
	alert_error_message  text:= '';
	low_threshold_val text:= '';
	alert_params text[];
	info_sql_curs     REFCURSOR;
	info_sql_rec      RECORD;
	hs_row            RECORD;
	first_time    boolean := FALSE;
	arr_col_values text[];
	column_name text[] := ARRAY[]::text[];
	column_value text[] := ARRAY[]::text[];
BEGIN
    IF (NEW.alert_id IS NOT NULL)
    THEN

        -- There should not be any error in alert sql before processing deailed alert sql.
        EXECUTE 'SELECT error_message FROM pem.alert WHERE id = ' || NEW.alert_id INTO alert_error_message;
        IF (alert_error_message <> '') THEN
            RETURN NULL;
        END IF;

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

                    FOR hs_row IN SELECT kv."key", kv."value" FROM each(hstore(info_sql_rec)) kv
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
                    RAISE EXCEPTION 'Error while executing alert detailed information SQL: %', SQLERRM;
                    RETURN NULL;
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

END TRANSACTION;
