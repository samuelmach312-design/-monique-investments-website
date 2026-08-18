/***************************************************************************
 *
 * Postgres Enterprise Manager
 *
 * Copyright (C) 2010 - 2025, EnterpriseDB Corporation. All rights reserved.
 *
 ***************************************************************************/

-- NOTE: This sql file is responsible for PEM 8.4.0 schema upgrade.

BEGIN TRANSACTION;

CREATE OR REPLACE FUNCTION pem.schema_version() RETURNS integer AS
'SELECT 202112021::integer;'
LANGUAGE 'sql' IMMUTABLE;
COMMENT ON FUNCTION pem.schema_version()
	IS 'Returns the version number of the PEM schema';

UPDATE pem.chart_func SET func = '
SELECT
    file_system AS "File System",
    ROUND((size_mb::float/1024)::numeric,2) AS "Size (GB)",
    ROUND((space_used_mb::float/1024)::numeric,2) AS "Used (GB)",
    ROUND((space_available_mb::float/1024)::numeric,2) AS "Available (GB)",
    CASE WHEN size_mb = 0
    THEN 0
    ELSE ROUND((space_used_mb::float * 100/(size_mb - COALESCE(space_reserved_mb, 0)))::numeric,2)
    END
    AS "%Used",
    CASE WHEN (device_id is NOT NULL and device_id != '''') THEN mount_point || '' ('' || device_id || '')'' ELSE mount_point END AS "Mounted On"
FROM pemdata.disk_space
WHERE agent_id = $1::int4
ORDER BY 3::int DESC' WHERE id = 44;

UPDATE pem.chart_func SET func = '
SELECT
    file_system AS "File System",
    ROUND((size_mb::float/1024)::numeric,2) AS "Size (GB)",
    ROUND((space_used_mb::float/1024)::numeric,2) AS "Used (GB)",
    ROUND((space_available_mb::float/1024)::numeric,2) AS "Available (GB)",
    CASE WHEN size_mb = 0
    THEN 0
    ELSE ROUND((space_used_mb::float * 100/(size_mb - COALESCE(space_reserved_mb, 0)))::numeric,2)
    END
    AS "%Used",
    CASE WHEN (device_id is NOT NULL and device_id != '''') THEN mount_point || '' ('' || device_id || '')'' ELSE mount_point END AS "Mounted On"
FROM pemdata.disk_space
WHERE agent_id = $1::int4
ORDER BY 3::int DESC' WHERE id = 73;

-- PEM-2493
-- We have updated the Server Down alert template and removed the dependency checking of agent's last heartbeat
-- which was causing server down alert to send alert cleared notification
UPDATE pem.alert_template SET sql = $SQL$
SELECT
    count(ps.id),
    CASE WHEN count(pa.id) = 0 THEN 'UP' ELSE 'DOWN' END display_value
FROM
    pem.server ps LEFT OUTER JOIN pem.server_heartbeat psh ON (ps.id = psh.server_id),
    pem.agent pa LEFT OUTER JOIN pem.agent_heartbeat pah ON (pa.id = pah.agent_id),
    pem.agent_server_binding pasb
WHERE
    ps.id = ${server_id} AND
    pa.id = pasb.agent_id AND
    ps.id = pasb.server_id AND
    pa.active = TRUE AND
    ps.active = TRUE AND
    NOT ps.alert_blackout AND
    CASE WHEN psh.agent_id IS NULL THEN FALSE ELSE psh.agent_id = pa.id END AND
    CASE WHEN psh.server_id IS NULL THEN FALSE ELSE psh.last_heartbeat < now() - (pa.heartbeat_interval)*2*'1 second'::interval END
$SQL$,
info_sql = $SQL$
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
       CASE WHEN psh.server_id IS NULL THEN FALSE ELSE psh.last_heartbeat < now() - (pa.heartbeat_interval)*2*'1 second'::interval END;
$SQL$
WHERE display_name = 'Server Down';

UPDATE pem.alert_template SET sql = $SQL$
SELECT
    count(ps.id)
FROM
    pem.server ps LEFT OUTER JOIN pem.server_heartbeat psh ON (ps.id = psh.server_id),
    pem.agent pa LEFT OUTER JOIN pem.agent_heartbeat pah ON (pa.id = pah.agent_id),
    pem.agent_server_binding pasb
WHERE
    pa.id = pasb.agent_id AND
    ps.id = pasb.server_id AND
    pa.active = TRUE AND
    ps.active = TRUE AND
	NOT ps.alert_blackout AND
    CASE WHEN psh.agent_id IS NULL THEN FALSE ELSE psh.agent_id = pa.id END AND
	CASE WHEN psh.server_id IS NULL THEN FALSE ELSE psh.last_heartbeat < now() - (pa.heartbeat_interval)*2*'1 second'::interval END
$SQL$
WHERE display_name = 'Servers Down';

-- PEM-1832
-- We will allow user to choose the SMTP message linebreak so that it won't break on MS Exchange like email servers
DO $DO$
BEGIN
    IF NOT EXISTS (SELECT value FROM pem.config WHERE param = 'smtp_message_linebreak') THEN
        INSERT INTO pem.config (param, value, unit, datatype, options) VALUES ('smtp_message_linebreak', '1', '', 'enum', '[{"label": "LF", "value": "1"}, {"label": "CR", "value": "2"}, { "label": "CR+LF", "value": "3"}, {"label": "LF+CR", "value": "4"}]'); -- This Line break character will be used in SMTP message body
    END IF;
END;
$DO$ LANGUAGE 'plpgsql';

CREATE OR REPLACE FUNCTION pem.send_email(mail_group_id integer[], subject text, message text)
RETURNS boolean AS $$
DECLARE
	mail_to text[] := '{}';
	mail_cc text[] := '{}';
	mail_bcc text[] := '{}';
	mail_reply_to text[] := '{}';
	mail_to_str text := '';
	mail_cc_str text := '';
	mail_bcc_str text := '';
	mail_reply_to_str text := '';
	mail_from_str text := '';
	mail_subject_prefix text := '';
	is_smtp_enabled boolean:= false;
	smtp_message_linebreak text;
	i integer;
	is_notify boolean:= false;
	tmp_row RECORD;
	now_time numeric;
BEGIN
	-- Check if smtp_enabled == true, if not return.
	SELECT value INTO is_smtp_enabled FROM pem.config WHERE param = 'smtp_enabled';

    -- Check the linebreak for message body
    SELECT res_option ->> 'label' AS label INTO smtp_message_linebreak
        FROM   pem.config pc, json_array_elements(pc.options) res_option
    WHERE  param = 'smtp_message_linebreak' AND res_option->>'value' = pc.value;

    IF smtp_message_linebreak = 'LF' THEN
        smtp_message_linebreak := '\n';
    ELSIF (smtp_message_linebreak = 'CR') THEN
        smtp_message_linebreak := '\r';
    ELSIF (smtp_message_linebreak = 'CR+LF') THEN
        smtp_message_linebreak := '\r\n';
    ELSIF (smtp_message_linebreak = 'LF+CR') THEN
        smtp_message_linebreak := '\n\r';
    END IF;

    -- If user has specified any other linebreak value then replace it against default `\n`.
    IF smtp_message_linebreak IS NOT NULL AND LENGTH(TRIM(smtp_message_linebreak)) > 0 AND TRIM(smtp_message_linebreak) != '\n' THEN
        message := REPLACE(message, '\n', smtp_message_linebreak);
    END IF;

	SELECT (EXTRACT(EPOCH FROM now()::timetz) + EXTRACT(TIMEZONE FROM now()::timetz)) INTO now_time;

	IF is_smtp_enabled THEN
		-- iterate through all the group id's and insert into the spool table
		FOR i in 1..COALESCE(array_upper(mail_group_id, 1), 0) LOOP
			-- Get email details
			-- iterate through all time intervals for a particular group and
			-- check time against server's current time and send mail to only
			-- those addresses for which current time lies within their interval
			FOR tmp_row IN SELECT grp_to, grp_cc, grp_bcc, grp_from, grp_reply_to, grp_subject_prefix, (EXTRACT(EPOCH FROM time_from) + EXTRACT(TIMEZONE FROM time_from)) as time_from, (EXTRACT(EPOCH FROM time_to) + EXTRACT(TIMEZONE FROM time_to)) as time_to FROM pem.email_group_option WHERE gid = mail_group_id[i]
			LOOP
				IF tmp_row.time_from < tmp_row.time_to THEN
					IF tmp_row.time_from <= now_time AND now_time <= tmp_row.time_to THEN
						mail_to := array_append(mail_to, tmp_row.grp_to);
						mail_cc := array_append(mail_cc, tmp_row.grp_cc);
						mail_bcc := array_append(mail_bcc, tmp_row.grp_bcc);
						mail_reply_to := array_append(mail_reply_to, tmp_row.grp_reply_to);
						mail_from_str := tmp_row.grp_from;
						mail_subject_prefix := COALESCE(tmp_row.grp_subject_prefix, '')::text;
					END IF;
				ELSIF tmp_row.time_from > tmp_row.time_to THEN
					IF (tmp_row.time_from <= now_time AND now_time <= (EXTRACT(EPOCH FROM '23:59:59'::timetz) + EXTRACT(TIMEZONE FROM '23:59:59'::timetz))) OR
						((EXTRACT(EPOCH FROM '00:00:00'::timetz) + EXTRACT(TIMEZONE FROM '00:00:00'::timetz)) <= now_time AND now_time <=tmp_row.time_to) THEN
						mail_to := array_append(mail_to, tmp_row.grp_to);
						mail_cc := array_append(mail_cc, tmp_row.grp_cc);
						mail_bcc := array_append(mail_bcc, tmp_row.grp_bcc);
						mail_reply_to := array_append(mail_reply_to, tmp_row.grp_reply_to);
						mail_from_str := tmp_row.grp_from;
						mail_subject_prefix := COALESCE(tmp_row.grp_subject_prefix, '')::text;
					END IF;
				END IF;
			END LOOP;

			mail_to_str := array_to_string(mail_to, ',');
			mail_cc_str := array_to_string(mail_cc, ',');
			mail_bcc_str := array_to_string(mail_bcc, ',');
			mail_reply_to_str := array_to_string(mail_reply_to, ',');
			IF (mail_from_str <> '') THEN
                                IF (mail_subject_prefix <> '') THEN
                                    subject := mail_subject_prefix || ': ' || subject;
                                END IF;
				-- Insert the spool record
				INSERT INTO pem.smtp_spool(mail_to, mail_cc, mail_bcc, mail_reply_to, mail_from, subject, message, sent_status) VALUES(mail_to_str, mail_cc_str, mail_bcc_str, mail_reply_to_str, mail_from_str, subject, message, 'u');
				is_notify = true;
			END IF;

			-- Clear the email address array
			mail_to := '{}';
			mail_cc := '{}';
			mail_bcc := '{}';
			mail_reply_to := '{}';

		END LOOP;

		IF is_notify THEN
			-- Notify listeners that a message is ready for delivery
			NOTIFY SMTP_SPOOL;
			RETURN true;
		END IF;
	END IF;

	RETURN false;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- PEM-3990
CREATE OR REPLACE FUNCTION pem.create_data_and_history_tables()
  RETURNS void AS $BODY$
DECLARE
    curs_table CURSOR FOR
        SELECT id, internal_name, target_type_id, discard_history FROM pem.probe as pr
            WHERE NOT EXISTS
            (SELECT 1 FROM pg_class, pg_namespace WHERE pg_namespace.oid =
             pg_class.relnamespace AND pg_namespace.nspname = 'pemdata' AND
                 pg_class.relname = pr.internal_name);
    r RECORD;
    quoted_table_name varchar;
    trigger_function_command varchar;
    trigger_command varchar;
BEGIN
    -- Loop through tables that are not present in pemdata schema, but defined
    -- in pem.probe table.
    FOR probe_table_name IN curs_table LOOP
        quoted_table_name := quote_ident(probe_table_name.internal_name);

        SELECT INTO r
            -- PIT value trigger definition
            string_agg(
                CASE WHEN calculate_pit THEN
                    '        NEW.' || quoted_name || E'_pit := 0;\n        IF NEW.' || quoted_name || ' - OLD.' || quoted_name || E' >= 0 THEN\n'
                    || '            NEW.' || quoted_name || '_pit :=  NEW.' || quoted_name || ' - OLD.' || quoted_name || E';\n        END IF;'
                END, E'\n')
                AS data_trigger_clause,
            -- Data table create definition
            string_agg(
                CASE WHEN NOT calculate_pit THEN
                    quoted_name || ' ' || column_definition
                ELSE
                    quoted_name || ' ' || column_definition || ', ' || quoted_name || '_pit ' || column_definition
                END, ', ')
                AS create_table_clause,
            -- History table create definition
            string_agg(
                CASE WHEN NOT discard_history THEN
                    CASE WHEN NOT calculate_pit THEN
                        quoted_name || ' ' || column_definition
                    ELSE
                        quoted_name || ' ' || column_definition || ', ' || quoted_name || '_pit ' || column_definition
                    END
                ELSE
                    CASE WHEN calculate_pit THEN
                        quoted_name || '_pit ' || column_definition
                    END
                END, ', ')
                AS create_history_table_clause,
            -- Insert/Update history table definition
            string_agg(
                    CASE WHEN NOT discard_history THEN
                    CASE WHEN NOT calculate_pit THEN
                        quoted_name
                    ELSE
                        quoted_name || ', ' || quoted_name || '_pit'
                    END
                ELSE
                    CASE WHEN calculate_pit THEN
                        quoted_name || '_pit'
                    END
                END, ', ')
                AS column_string,
            -- Insert/Update history table definition
            string_agg(
                CASE WHEN NOT discard_history THEN
                    CASE WHEN NOT calculate_pit THEN
                        'NEW.' || quoted_name
                    ELSE
                        'NEW.' || quoted_name || ', NEW.' || quoted_name || '_pit'
                    END
                ELSE
                    CASE WHEN calculate_pit THEN
                        'NEW.' || quoted_name || '_pit'
                    END
                END, ', ')
                AS new_column_string,
            string_agg(CASE WHEN classification = 'k' THEN quoted_name END,
                ', ') AS key_string,
            string_agg(CASE WHEN classification = 'k' THEN 'OLD.'
                || quoted_name END, ', ') AS old_key_string
            FROM
                (SELECT * FROM pem.probe_column_definition
                    ORDER BY display_position) x
            WHERE
                probe_id = probe_table_name.id;

        IF COALESCE(r.create_table_clause, '') = ''
            OR COALESCE(r.key_string, '') = '' THEN
            RAISE EXCEPTION 'data table has no defined columns: %',
                probe_table_name.id;
        END IF;

        IF COALESCE(r.create_history_table_clause, '') = ''
            OR COALESCE(r.key_string, '') = '' THEN
            RAISE EXCEPTION 'history table has no defined columns: %',
                probe_table_name.id;
        END IF;

        EXECUTE 'CREATE TABLE pemdata.' || quoted_table_name || ' ('
            || r.create_table_clause || ', PRIMARY KEY ('
            || r.key_string || '))';

                -- Give permission to pem_user, pem_agent and pem_admin
        EXECUTE 'GRANT SELECT ON TABLE pemdata.' || quoted_table_name || ' TO pem_user;';
        EXECUTE 'GRANT ALL ON TABLE pemdata.' || quoted_table_name || ' TO pem_admin;';
        EXECUTE 'GRANT SELECT, UPDATE, INSERT, DELETE ON TABLE pemdata.' || quoted_table_name || ' TO pem_agent;';

        IF NOT probe_table_name.discard_history THEN
            EXECUTE 'CREATE TABLE pemhistory.' || quoted_table_name || ' ('
                || r.create_history_table_clause || ', PRIMARY KEY ('
                || r.key_string || ', recorded_time))';

                    -- Give permission to pem_user, pem_agent and pem_admin
            EXECUTE 'GRANT SELECT ON TABLE pemhistory.' || quoted_table_name || ' TO pem_user;';
            EXECUTE 'GRANT ALL ON TABLE pemhistory.' || quoted_table_name || ' TO pem_admin;';
            EXECUTE 'GRANT SELECT, UPDATE, INSERT, DELETE ON TABLE pemhistory.' || quoted_table_name || ' TO pem_agent;';

            EXECUTE 'CREATE INDEX '
                || quote_ident(probe_table_name.internal_name || '_timeidx')
                || ' ON ' || 'pemhistory.' || quoted_table_name
                || ' (recorded_time)';

            -- Trigger Function Command String
            trigger_function_command := 'CREATE OR REPLACE FUNCTION pemdata.' ||  quote_ident('copy_' || probe_table_name.internal_name || '_to_history') || '() RETURNS TRIGGER AS $$
            BEGIN
                IF (TG_OP = ''INSERT'' OR TG_OP = ''UPDATE'') THEN
                    INSERT INTO pemhistory.' || quoted_table_name || ' (' || r.column_string || ') VALUES (' || r.new_column_string || ');
                    ELSIF EXISTS(SELECT 1 FROM ' || CASE WHEN probe_table_name.target_type_id = 100 THEN 'pem.agent WHERE id = OLD.agent_id' WHEN probe_table_name.target_type_id = 150 THEN 'pem.tool WHERE id = OLD.tool_id' ELSE 'pem.server WHERE id = OLD.server_id' END || ') THEN
                    INSERT INTO pemhistory.' || quoted_table_name || ' (' || r.key_string || ') VALUES (' || r.old_key_string || ');
                END IF;
                RETURN NEW;
            END;
            $$ LANGUAGE plpgsql;';

            -- Trigger Command String
            trigger_command := 'CREATE TRIGGER ' || quote_ident('copy_' || probe_table_name.internal_name || '_to_history') || ' AFTER INSERT OR UPDATE OR DELETE ON pemdata.' || quoted_table_name || ' FOR EACH ROW EXECUTE PROCEDURE pemdata.' || quote_ident('copy_' || probe_table_name.internal_name || '_to_history') || '()' ;

            -- Execute the commands.
            EXECUTE trigger_function_command;
            EXECUTE trigger_command;
        END IF;

        -- Trigger Function for calculating PIT values definition
        IF COALESCE(r.data_trigger_clause, '') != ''
        THEN
        -- Trigger Function Command String
        trigger_function_command := 'CREATE OR REPLACE FUNCTION pemdata.' ||  quote_ident('calculate_' || probe_table_name.internal_name || '_pit_value') || E'() RETURNS TRIGGER AS $$
BEGIN
    IF (TG_OP = ''UPDATE'') THEN \n'
     ||  r.data_trigger_clause ||
    E'\n    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;';

        -- Trigger Command String
        trigger_command := 'CREATE TRIGGER ' || quote_ident('calculate_' || probe_table_name.internal_name || '_pit_value') || ' BEFORE UPDATE ON pemdata.' || quoted_table_name || ' FOR EACH ROW EXECUTE PROCEDURE pemdata.' || quote_ident('calculate_' || probe_table_name.internal_name || '_pit_value') || '()' ;

        -- Execute the commands.
        EXECUTE trigger_function_command;
            EXECUTE trigger_command;
        END IF;

    END LOOP;
END;
$BODY$ LANGUAGE plpgsql;

DO $DO$
BEGIN
    IF NOT EXISTS (SELECT id FROM pem.probe where internal_name = 'txid_exhaustion_wraparound') THEN
        --
        -- Transaction ID Exhaustion (Wraparound) Probe
        --
        INSERT INTO pem.probe
            (display_name, internal_name, collection_method, target_type_id,
             agent_capability, enabled_by_default, force_enabled,
             default_execution_frequency, default_lifetime, any_server_version, probe_code)
        VALUES
            ('Transaction ID Exhaustion (Wraparound)', 'txid_exhaustion_wraparound', 's',
             200, NULL, true, false, 300, 180, true,
            $sql$
        WITH max_age AS ( SELECT 2000000000 as max_old_xid, setting AS autovacuum_freeze_max_age FROM pg_catalog.pg_settings WHERE name = 'autovacuum_freeze_max_age' ),
        per_database_stats AS ( SELECT datname, m.max_old_xid::int, m.autovacuum_freeze_max_age::int, age(d.datfrozenxid) AS oldest_current_xid FROM pg_catalog.pg_database d JOIN max_age m ON (true) WHERE d.datallowconn )
        SELECT  datname,
                oldest_current_xid AS oldest_current_xid,
                ROUND(100*(oldest_current_xid/max_old_xid::float)) AS percent_towards_wraparound,
                ROUND(100*(oldest_current_xid/autovacuum_freeze_max_age::float)) AS percent_towards_emergency_autovac
        FROM per_database_stats
            $sql$
        );

        INSERT INTO pem.probe_column
            (probe_id, internal_name, display_name, display_position, classification,
            sql_data_type, unit_of_value, calculate_pit, discard_history, pit_by_default, is_graphable)
        SELECT
            (SELECT max(id) FROM pem.probe),
            v.internal_name, v.display_name, v.display_position, v.classification,
            v.sql_data_type, v.unit_of_value, v.calculate_pit, v.discard_history, v.pit_by_default, v.is_graphable
        FROM
            (VALUES
                ('datname', 'Database name', 1, 'k', 'text', '', false, false, false, false),
                ('oldest_current_xid', 'Oldest current XID', 2, 'm', 'bigint', '', false, false, false, false),
                ('percent_towards_wraparound', 'Percent towards wraparound', 3, 'm', 'integer', '', false, false, false, false),
                ('percent_towards_emergency_autovac', 'Percent towards autovacuum', 4, 'm', 'integer', '', false, false, false, false)
            ) v(internal_name, display_name, display_position, classification,
                sql_data_type, unit_of_value, calculate_pit, discard_history, pit_by_default, is_graphable);
    END IF;

    -- Create tables required by probe
    PERFORM pem.create_data_and_history_tables();

	IF NOT EXISTS (SELECT id FROM pem.alert_template where display_name = 'Transaction ID Exhaustion (Wraparound)') THEN
        -- Create new alert template.
        PERFORM pem.create_alert_template(
            'Transaction ID Exhaustion (Wraparound)',
            'Percentage towards transaction ID Exhaustion (Wraparound)',
            $sql$
        SELECT  max(percent_towards_wraparound) AS percent_towards_wraparound
        FROM pemdata.txid_exhaustion_wraparound AS txew
        WHERE txew.server_id = ${server_id}
        $sql$,
            200, NULL, NULL, NULL, '%','{txid_exhaustion_wraparound}', (SELECT CASE WHEN MAX(snmp_oid) > 0 THEN MAX(snmp_oid) + 1 ELSE 1 END FROM pem.alert_template WHERE object_type = 200),
            'ALL', 1, 30, true,
            $SQL$
        SELECT  MAX(datname) AS "Database name",
                MAX(oldest_current_xid) AS "Oldest current XID",
                MAX(percent_towards_wraparound) AS "Percent towards wraparound",
                MAX(percent_towards_emergency_autovac) AS "Percent towards emergency autovacuum"
        FROM pemdata.txid_exhaustion_wraparound AS txew
        WHERE txew.server_id = ${server_id}
            $SQL$, true, '>', '{75, 85, 95}');
	END IF;
END;
$DO$ LANGUAGE 'plpgsql';

-- Function to fetch timezone of PEM database server
CREATE OR REPLACE FUNCTION pem.get_timezone() RETURNS text
LANGUAGE SQL AS
$$ SELECT current_setting('TIMEZONE')::text; $$;

-- PEM-4172
DO $DO$
BEGIN
    IF NOT EXISTS (SELECT value FROM pem.config WHERE param = 'timezone_for_system_jobs') THEN
        -- System jobs will use job's timezone using this setting
        INSERT INTO pem.config (param, value, unit, datatype) VALUES (
            'timezone_for_system_jobs', (SELECT pem.get_timezone()), '', 'string'
        );
    END IF;
END;
$DO$ LANGUAGE 'plpgsql';

-- Create new column and update it with default value
DO $$
DECLARE
    pem_db_timezone text;
BEGIN
	IF NOT EXISTS(
		SELECT * FROM pg_catalog.pg_attribute
		LEFT JOIN pg_catalog.pg_class c ON attrelid = c.oid
		LEFT JOIN pg_catalog.pg_namespace n ON c.relnamespace = n.oid
		WHERE attname = 'jsctimezone' AND relname = 'schedule' AND
			n.nspname = 'pem'
	) THEN
		RAISE INFO '--- Adding new column jsctimezone in pem.schedule table';
		ALTER TABLE pem.schedule ADD COLUMN jsctimezone text DEFAULT pem.get_timezone();
		EXECUTE 'SELECT pem.get_timezone()' INTO pem_db_timezone;

		RAISE INFO '--- Updating the jsctimezone of the existing jobs';
		UPDATE pem.schedule
		SET jsctimezone = pem_db_timezone;

		ALTER TABLE pem.schedule ALTER COLUMN jsctimezone SET NOT NULL;
	END IF;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION pem.job_trigger()
  RETURNS "trigger" AS
$$
DECLARE
    db_timezone text := NULL;
    server_config_timezone text := NULL;
    job_timezone text := NULL;
    job_tz text := NULL;
BEGIN
    IF NEW.jobenabled THEN
        IF NEW.jobnextrun IS NULL THEN
            -- Fetch required timezone values for the job
            SELECT jsctimezone INTO job_timezone
                FROM pem.schedule ps
                WHERE jscenabled AND jscjobid=OLD.jobid;

            -- If job is pem system/in-built job
            IF OLD.issystemjob THEN
                SELECT pem.get_timezone() INTO db_timezone;
                SELECT TRIM(value) INTO server_config_timezone
                    FROM pem.config WHERE param = 'timezone_for_system_jobs';

                job_tz := db_timezone;
                -- We will override the db_time if user has set the different value in System config dialog
                IF db_timezone != server_config_timezone THEN
                    job_tz := server_config_timezone;
                END IF;
            ELSE
                job_tz := job_timezone;
            END IF;

            -- Set the appropriate timezone for current transaction, it won't affect database server timezone
            IF job_tz IS NOT NULL AND job_tz != '' THEN
                EXECUTE 'SET LOCAL TIME ZONE ''' || job_tz || ''';' ;
            END IF;

            SELECT INTO NEW.jobnextrun
                MIN(pem.next_schedule(jscid, jscstart, jscend, jscminutes, jschours, jscweekdays, jscmonthdays, jscmonths))
            FROM pem.schedule
            WHERE jscenabled AND jscjobid=OLD.jobid;
        END IF;
    ELSE
        NEW.jobnextrun := NULL;
    END IF;
    RETURN NEW;
END;
$$
  LANGUAGE 'plpgsql' VOLATILE;
COMMENT ON FUNCTION pem.job_trigger() IS 'Update the job''s next run time.';

-- PEM-4391
-- Add support for extension version based probe execution
DO $DO$
BEGIN
    IF NOT EXISTS (SELECT display_name FROM pem.probe_target_type WHERE id = 1000) THEN
        RAISE INFO '--- Adding new target type for extension level';
        INSERT INTO pem.probe_target_type VALUES (1000, 'Extension');
    END IF;
END;
$DO$ LANGUAGE 'plpgsql';

-- Add a column to identify if probe needs to check extension version
DO $$
BEGIN
	IF NOT EXISTS(
		SELECT * FROM pg_catalog.pg_attribute
		LEFT JOIN pg_catalog.pg_class c ON attrelid = c.oid
		LEFT JOIN pg_catalog.pg_namespace n ON c.relnamespace = n.oid
		WHERE attname = 'any_extension_version' AND relname = 'probe' AND
			n.nspname = 'pem'
	) THEN
		RAISE INFO '--- Adding new column any_extension_version in pem.probe table';
        ALTER TABLE pem.probe
            ADD COLUMN any_extension_version boolean NOT NULL DEFAULT true;
	END IF;
END;
$$ LANGUAGE plpgsql;

-- Add a column to store check extension name
DO $$
BEGIN
	IF NOT EXISTS(
		SELECT * FROM pg_catalog.pg_attribute
		LEFT JOIN pg_catalog.pg_class c ON attrelid = c.oid
		LEFT JOIN pg_catalog.pg_namespace n ON c.relnamespace = n.oid
		WHERE attname = 'extension_name' AND relname = 'probe' AND
			n.nspname = 'pem'
	) THEN
		RAISE INFO '--- Adding new column extension_name in pem.probe table';
        ALTER TABLE pem.probe
            ADD COLUMN extension_name text;
	END IF;
END;
$$ LANGUAGE plpgsql;


-- Add new table to store extension version specific probe details
DO $$
BEGIN
	IF NOT EXISTS(
        SELECT * FROM information_schema.tables
        WHERE  table_schema = 'pem'
        AND    table_name   = 'probe_extension_version'
	) THEN
		RAISE INFO '--- Adding new new table pem.probe_extension_version';
        CREATE TABLE pem.probe_extension_version (
            id					serial NOT NULL,
            probe_id			integer NOT NULL
                REFERENCES pem.probe (id) ON UPDATE RESTRICT ON DELETE CASCADE,
            server_version_id	integer
                REFERENCES pem.server_version (id)
                ON UPDATE RESTRICT ON DELETE CASCADE,
            extension_version	text NOT NULL,
            probe_code			text,
            CONSTRAINT probe_extension_version_pkey PRIMARY KEY (id),
            CONSTRAINT probe_extension_version_unique UNIQUE (probe_id, server_version_id, extension_version)
        );
	END IF;
END;
$$ LANGUAGE plpgsql;


-- Add new table to store extension version specific probe details
DO $$
BEGIN
	IF NOT EXISTS(
        SELECT * FROM information_schema.tables
        WHERE  table_schema = 'pem'
        AND    table_name   = 'probe_config_extension'
	) THEN
		RAISE INFO '--- Adding new new table pem.probe_config_extension';
        CREATE TABLE pem.probe_config_extension (
            probe_id			integer NOT NULL
                REFERENCES pem.probe (id) ON UPDATE RESTRICT ON DELETE CASCADE,
            server_id			integer NOT NULL
                REFERENCES pem.server (id) ON UPDATE RESTRICT ON DELETE CASCADE,
            database_name		varchar NOT NULL,
            extension_name		varchar NOT NULL,
            enabled				boolean,
            execution_frequency	integer,
            lifetime		integer,
            CONSTRAINT probe_config_extension_pkey
                PRIMARY KEY (probe_id, server_id, database_name, extension_name)
        );
	END IF;
END;
$$ LANGUAGE plpgsql;

-- Updating existing BDR probes target type to 300
DO $$
BEGIN
	IF EXISTS(
        SELECT * FROM pem.probe
        WHERE internal_name like 'bdr_%' AND target_type_id = 200 AND is_system_probe
	) THEN
		RAISE INFO '--- Updating existing BDR probes target type';
		UPDATE pem.probe
		    SET target_type_id = 1000, applies_to_id = 1000, extension_name = 'bdr'
		WHERE internal_name like 'bdr_%' AND target_type_id = 200 AND is_system_probe;

	END IF;
END;
$$ LANGUAGE plpgsql;

-- There were some changes in BDR v4 which breaks below four PEM probes
-- DB version support metrics - https://www.enterprisedb.com/docs/bdr/latest/#supported-postgresql-database-servers
DO $$
BEGIN
	IF EXISTS(
        SELECT * FROM pem.probe
        WHERE internal_name IN ('bdr_node_summary', 'bdr_group_versions_details', 'bdr_worker_errors', 'bdr_group_camo_details') AND any_extension_version
	) THEN
		RAISE INFO '--- Updating pem.probe table column any_extension_version to false for BDR v4 compatibility';
		UPDATE pem.probe
		    SET any_extension_version = false
		WHERE internal_name IN ('bdr_node_summary', 'bdr_group_versions_details', 'bdr_worker_errors', 'bdr_group_camo_details') AND any_extension_version;
	END IF;
END;
$$ LANGUAGE plpgsql;

-- Make BDR v4 probe code to default
UPDATE pem.probe
    SET probe_code = $sql$
SELECT node_name, node_group_name, peer_state_name, peer_target_state_name, NULL AS sub_repsets FROM bdr.node_summary;
$sql$ WHERE internal_name = 'bdr_node_summary';

UPDATE pem.probe
    SET probe_code = $sql$
SELECT node_name, postgres_version, 'N/A' AS pglogical_version, bdr_version, bdr_edition FROM bdr.group_versions_details;
$sql$ WHERE internal_name = 'bdr_group_versions_details';

UPDATE pem.probe
    SET probe_code = $sql$
select worker_pid, node_group_name, origin_name, source_name, target_name, sub_name, worker_role, worker_role_name, error_time,
        error_age, error_message, error_context_message, remoterelid, 'N/A' AS subwriter_id, 'N/A' AS subwriter_name from bdr.worker_errors;
$sql$ WHERE internal_name = 'bdr_worker_errors';

UPDATE pem.probe
    SET probe_code = $sql$
SELECT node_name, camo_partner AS camo_partner_of, 'N/A' AS camo_origin_for, is_camo_partner_connected, is_camo_partner_ready,
		camo_transactions_resolved, apply_lsn, receive_lsn, apply_queue_size from bdr.group_camo_details;
$sql$ WHERE internal_name = 'bdr_group_camo_details';

/*
-- There were some changes in BDR v4 catalogs which breaks some of PEM probes
-- DB version support metrics - https://www.enterprisedb.com/docs/bdr/latest/#supported-postgresql-database-servers
-- BDR v4 catalog - https://documentation.enterprisedb.com/bdr4/release/4.0.0-1/catalogs/#bdrworker_errors
*/
-- BDR Node Summary
DO $$
BEGIN
	IF NOT EXISTS(
        SELECT * FROM pem.probe_extension_version
        WHERE probe_id = (SELECT id FROM pem.probe WHERE internal_name = 'bdr_node_summary')
        AND extension_version = '3.7.15'
	) THEN
        INSERT INTO pem.probe_extension_version
            (probe_id, server_version_id, extension_version, probe_code)
        SELECT
            (
            SELECT id FROM pem.probe WHERE internal_name = 'bdr_node_summary'),
            v.version,
            '3.7.15',
            'SELECT node_name, node_group_name, peer_state_name, peer_target_state_name, sub_repsets FROM bdr.node_summary;'
        FROM (
            VALUES (11100), (11200), (11300), (21100), (21200), (21300)
        ) v(version);
	END IF;
END;
$$ LANGUAGE plpgsql;

-- BDR Group Versions Details
DO $$
BEGIN
	IF NOT EXISTS(
        SELECT * FROM pem.probe_extension_version
        WHERE probe_id = (SELECT id FROM pem.probe WHERE internal_name = 'bdr_group_versions_details')
        AND extension_version = '3.7.15'
	) THEN
        INSERT INTO pem.probe_extension_version
            (probe_id, server_version_id, extension_version, probe_code)
        SELECT
            (
            SELECT id FROM pem.probe WHERE internal_name = 'bdr_group_versions_details'),
            v.version,
            '3.7.15',
            'SELECT node_name, postgres_version, pglogical_version, bdr_version, bdr_edition FROM bdr.group_versions_details;'
        FROM (
            VALUES (11100), (11200), (11300), (21100), (21200), (21300)
        ) v(version);
	END IF;
END;
$$ LANGUAGE plpgsql;

-- BDR Worker Errors
DO $$
BEGIN
	IF NOT EXISTS(
        SELECT * FROM pem.probe_extension_version
        WHERE probe_id = (SELECT id FROM pem.probe WHERE internal_name = 'bdr_worker_errors')
        AND extension_version = '3.7.15'
	) THEN
        INSERT INTO pem.probe_extension_version
            (probe_id, server_version_id, extension_version, probe_code)
        SELECT
            (
            SELECT id FROM pem.probe WHERE internal_name = 'bdr_worker_errors'),
            v.version,
            '3.7.15',
            'select worker_pid, node_group_name, origin_name, source_name, target_name, sub_name, worker_role, worker_role_name, error_time, error_age, error_message, error_context_message, remoterelid, subwriter_id, subwriter_name from bdr.worker_errors;'
        FROM (
            VALUES (11100), (11200), (11300), (21100), (21200), (21300)
        ) v(version);
	END IF;
END;
$$ LANGUAGE plpgsql;

-- BDR Group Camo Details
DO $$
BEGIN
	IF NOT EXISTS(
        SELECT * FROM pem.probe_extension_version
        WHERE probe_id = (SELECT id FROM pem.probe WHERE internal_name = 'bdr_group_camo_details')
        AND extension_version = '3.7.15'
	) THEN
        INSERT INTO pem.probe_extension_version
            (probe_id, server_version_id, extension_version, probe_code)
        SELECT
            (
            SELECT id FROM pem.probe WHERE internal_name = 'bdr_group_camo_details'),
            v.version,
            '3.7.15',
            'SELECT node_name, camo_partner_of, camo_origin_for, is_camo_partner_connected, is_camo_partner_ready, camo_transactions_resolved, apply_lsn, receive_lsn, apply_queue_size from bdr.group_camo_details;'
        FROM (
            VALUES (11100), (11200), (11300), (21100), (21200), (21300)
        ) v(version);
	END IF;
END;
$$ LANGUAGE plpgsql;

END TRANSACTION;


BEGIN TRANSACTION;

-- Add database_name column in the existing BDR probe tables
ALTER TABLE pemdata.bdr_stat_relation ADD COLUMN IF NOT EXISTS database_name text;
ALTER TABLE pemhistory.bdr_stat_relation ADD COLUMN IF NOT EXISTS database_name text;

ALTER TABLE pemdata.bdr_stat_subscription ADD COLUMN IF NOT EXISTS database_name text;
ALTER TABLE pemhistory.bdr_stat_subscription ADD COLUMN IF NOT EXISTS database_name text;

ALTER TABLE pemdata.bdr_group_replslots_details ADD COLUMN IF NOT EXISTS database_name text;
ALTER TABLE pemhistory.bdr_group_replslots_details ADD COLUMN IF NOT EXISTS database_name text;

ALTER TABLE pemdata.bdr_node_summary ADD COLUMN IF NOT EXISTS database_name text;
ALTER TABLE pemhistory.bdr_node_summary ADD COLUMN IF NOT EXISTS database_name text;

ALTER TABLE pemdata.bdr_node_replication_rates ADD COLUMN IF NOT EXISTS database_name text;
ALTER TABLE pemhistory.bdr_node_replication_rates ADD COLUMN IF NOT EXISTS database_name text;

ALTER TABLE pemdata.bdr_node_slots ADD COLUMN IF NOT EXISTS database_name text;
ALTER TABLE pemhistory.bdr_node_slots ADD COLUMN IF NOT EXISTS database_name text;

ALTER TABLE pemdata.bdr_group_subscription_summary ADD COLUMN IF NOT EXISTS database_name text;
ALTER TABLE pemhistory.bdr_group_subscription_summary ADD COLUMN IF NOT EXISTS database_name text;

ALTER TABLE pemdata.bdr_group_versions_details ADD COLUMN IF NOT EXISTS database_name text;
ALTER TABLE pemhistory.bdr_group_versions_details ADD COLUMN IF NOT EXISTS database_name text;

ALTER TABLE pemdata.bdr_monitor_group_versions ADD COLUMN IF NOT EXISTS database_name text;
ALTER TABLE pemhistory.bdr_monitor_group_versions ADD COLUMN IF NOT EXISTS database_name text;

ALTER TABLE pemdata.bdr_group_raft_details ADD COLUMN IF NOT EXISTS database_name text;
ALTER TABLE pemhistory.bdr_group_raft_details ADD COLUMN IF NOT EXISTS database_name text;

ALTER TABLE pemdata.bdr_monitor_group_raft ADD COLUMN IF NOT EXISTS database_name text;
ALTER TABLE pemhistory.bdr_monitor_group_raft ADD COLUMN IF NOT EXISTS database_name text;

ALTER TABLE pemdata.bdr_workers ADD COLUMN IF NOT EXISTS database_name text;
ALTER TABLE pemhistory.bdr_workers ADD COLUMN IF NOT EXISTS database_name text;

ALTER TABLE pemdata.bdr_worker_errors ADD COLUMN IF NOT EXISTS database_name text;
ALTER TABLE pemhistory.bdr_worker_errors ADD COLUMN IF NOT EXISTS database_name text;

ALTER TABLE pemdata.bdr_global_locks ADD COLUMN IF NOT EXISTS database_name text;
ALTER TABLE pemhistory.bdr_global_locks ADD COLUMN IF NOT EXISTS database_name text;

ALTER TABLE pemdata.bdr_conflict_history_summary ADD COLUMN IF NOT EXISTS database_name text;

ALTER TABLE pemdata.bdr_group_camo_details ADD COLUMN IF NOT EXISTS database_name text;
ALTER TABLE pemhistory.bdr_group_camo_details ADD COLUMN IF NOT EXISTS database_name text;

END TRANSACTION;

BEGIN TRANSACTION;
-- Create/Update trigger function to copy database_name to bdr history
CREATE OR REPLACE FUNCTION pemdata.copy_bdr_global_locks_to_history()
    RETURNS trigger
    LANGUAGE 'plpgsql'
    COST 100
    VOLATILE NOT LEAKPROOF
AS $BODY$
    BEGIN
        IF (TG_OP = 'INSERT' OR TG_OP = 'UPDATE') THEN
            INSERT INTO pemhistory.bdr_global_locks (recorded_time, server_id, database_name, origin_node_name, pid, origin_node_id, lock_type, relation, acquire_stage, waiters, global_lock_request_time, local_lock_request_time, last_state_change_time) VALUES (NEW.recorded_time, NEW.server_id, NEW.database_name, NEW.origin_node_name, NEW.pid, NEW.origin_node_id, NEW.lock_type, NEW.relation, NEW.acquire_stage, NEW.waiters, NEW.global_lock_request_time, NEW.local_lock_request_time, NEW.last_state_change_time);
            ELSIF EXISTS(SELECT 1 FROM pem.server WHERE id = OLD.server_id) THEN
            INSERT INTO pemhistory.bdr_global_locks (server_id, database_name, origin_node_name, pid) VALUES (OLD.server_id, OLD.database_name, OLD.origin_node_name, OLD.pid);
        END IF;
        RETURN NEW;
    END;
$BODY$;

CREATE OR REPLACE FUNCTION pemdata.copy_bdr_group_camo_details_to_history()
    RETURNS trigger
    LANGUAGE 'plpgsql'
    COST 100
    VOLATILE NOT LEAKPROOF
AS $BODY$
    BEGIN
        IF (TG_OP = 'INSERT' OR TG_OP = 'UPDATE') THEN
            INSERT INTO pemhistory.bdr_group_camo_details (recorded_time, server_id, database_name, node_name, camo_partner_of, camo_origin_for, is_camo_partner_connected, is_camo_partner_ready, camo_transactions_resolved, apply_lsn, receive_lsn, apply_queue_size) VALUES (NEW.recorded_time, NEW.server_id, NEW.database_name, NEW.node_name, NEW.camo_partner_of, NEW.camo_origin_for, NEW.is_camo_partner_connected, NEW.is_camo_partner_ready, NEW.camo_transactions_resolved, NEW.apply_lsn, NEW.receive_lsn, NEW.apply_queue_size);
            ELSIF EXISTS(SELECT 1 FROM pem.server WHERE id = OLD.server_id) THEN
            INSERT INTO pemhistory.bdr_group_camo_details (server_id, database_name, node_name, camo_partner_of) VALUES (OLD.server_id, OLD.database_name, OLD.node_name, OLD.camo_partner_of);
        END IF;
        RETURN NEW;
    END;
$BODY$;

CREATE OR REPLACE FUNCTION pemdata.copy_bdr_group_raft_details_to_history()
    RETURNS trigger
    LANGUAGE 'plpgsql'
    COST 100
    VOLATILE NOT LEAKPROOF
AS $BODY$
    BEGIN
        IF (TG_OP = 'INSERT' OR TG_OP = 'UPDATE') THEN
            INSERT INTO pemhistory.bdr_group_raft_details (recorded_time, server_id, database_name, node_name, state, leader_id, current_term, commit_index) VALUES (NEW.recorded_time, NEW.server_id, NEW.database_name, NEW.node_name, NEW.state, NEW.leader_id, NEW.current_term, NEW.commit_index);
            ELSIF EXISTS(SELECT 1 FROM pem.server WHERE id = OLD.server_id) THEN
            INSERT INTO pemhistory.bdr_group_raft_details (server_id, database_name, node_name) VALUES (OLD.server_id, OLD.database_name, OLD.node_name);
        END IF;
        RETURN NEW;
    END;
$BODY$;

CREATE OR REPLACE FUNCTION pemdata.copy_bdr_group_replslots_details_to_history()
    RETURNS trigger
    LANGUAGE 'plpgsql'
    COST 100
    VOLATILE NOT LEAKPROOF
AS $BODY$
    BEGIN
        IF (TG_OP = 'INSERT' OR TG_OP = 'UPDATE') THEN
            INSERT INTO pemhistory.bdr_group_replslots_details (recorded_time, server_id, database_name, node_group_name, origin_name, target_name, slot_name, active, state, write_lag, flush_lag, replay_lag, sent_lag_bytes, write_lag_bytes, flush_lag_bytes, replay_lag_bytes) VALUES (NEW.recorded_time, NEW.server_id, NEW.database_name, NEW.node_group_name, NEW.origin_name, NEW.target_name, NEW.slot_name, NEW.active, NEW.state, NEW.write_lag, NEW.flush_lag, NEW.replay_lag, NEW.sent_lag_bytes, NEW.write_lag_bytes, NEW.flush_lag_bytes, NEW.replay_lag_bytes);
            ELSIF EXISTS(SELECT 1 FROM pem.server WHERE id = OLD.server_id) THEN
            INSERT INTO pemhistory.bdr_group_replslots_details (server_id, database_name, origin_name, slot_name) VALUES (OLD.server_id, OLD.database_name, OLD.origin_name, OLD.slot_name);
        END IF;
        RETURN NEW;
    END;
$BODY$;

CREATE OR REPLACE FUNCTION pemdata.copy_bdr_group_subscription_summary_to_history()
    RETURNS trigger
    LANGUAGE 'plpgsql'
    COST 100
    VOLATILE NOT LEAKPROOF
AS $BODY$
    BEGIN
        IF (TG_OP = 'INSERT' OR TG_OP = 'UPDATE') THEN
            INSERT INTO pemhistory.bdr_group_subscription_summary (recorded_time, server_id, database_name, origin_node_name, target_node_name, last_xact_replay_timestamp, sub_lag_seconds) VALUES (NEW.recorded_time, NEW.server_id, NEW.database_name, NEW.origin_node_name, NEW.target_node_name, NEW.last_xact_replay_timestamp, NEW.sub_lag_seconds);
            ELSIF EXISTS(SELECT 1 FROM pem.server WHERE id = OLD.server_id) THEN
            INSERT INTO pemhistory.bdr_group_subscription_summary (server_id, database_name, origin_node_name, target_node_name) VALUES (OLD.server_id, OLD.database_name, OLD.origin_node_name, OLD.target_node_name);
        END IF;
        RETURN NEW;
    END;
$BODY$;

CREATE OR REPLACE FUNCTION pemdata.copy_bdr_group_versions_details_to_history()
    RETURNS trigger
    LANGUAGE 'plpgsql'
    COST 100
    VOLATILE NOT LEAKPROOF
AS $BODY$
    BEGIN
        IF (TG_OP = 'INSERT' OR TG_OP = 'UPDATE') THEN
            INSERT INTO pemhistory.bdr_group_versions_details (recorded_time, server_id, database_name, node_name, postgres_version, pglogical_version, bdr_version, bdr_edition) VALUES (NEW.recorded_time, NEW.server_id, NEW.database_name, NEW.node_name, NEW.postgres_version, NEW.pglogical_version, NEW.bdr_version, NEW.bdr_edition);
            ELSIF EXISTS(SELECT 1 FROM pem.server WHERE id = OLD.server_id) THEN
            INSERT INTO pemhistory.bdr_group_versions_details (server_id, database_name, node_name) VALUES (OLD.server_id, OLD.database_name, OLD.node_name);
        END IF;
        RETURN NEW;
    END;
$BODY$;

CREATE OR REPLACE FUNCTION pemdata.copy_bdr_monitor_group_raft_to_history()
    RETURNS trigger
    LANGUAGE 'plpgsql'
    COST 100
    VOLATILE NOT LEAKPROOF
AS $BODY$
    BEGIN
        IF (TG_OP = 'INSERT' OR TG_OP = 'UPDATE') THEN
            INSERT INTO pemhistory.bdr_monitor_group_raft (recorded_time, server_id, database_name, status, message) VALUES (NEW.recorded_time, NEW.server_id, NEW.database_name, NEW.status, NEW.message);
            ELSIF EXISTS(SELECT 1 FROM pem.server WHERE id = OLD.server_id) THEN
            INSERT INTO pemhistory.bdr_monitor_group_raft (server_id, database_name) VALUES (OLD.server_id, OLD.database_name);
        END IF;
        RETURN NEW;
    END;
$BODY$;

CREATE OR REPLACE FUNCTION pemdata.copy_bdr_monitor_group_versions_to_history()
    RETURNS trigger
    LANGUAGE 'plpgsql'
    COST 100
    VOLATILE NOT LEAKPROOF
AS $BODY$
    BEGIN
        IF (TG_OP = 'INSERT' OR TG_OP = 'UPDATE') THEN
            INSERT INTO pemhistory.bdr_monitor_group_versions (recorded_time, server_id, database_name, status, message) VALUES (NEW.recorded_time, NEW.server_id, NEW.database_name, NEW.status, NEW.message);
            ELSIF EXISTS(SELECT 1 FROM pem.server WHERE id = OLD.server_id) THEN
            INSERT INTO pemhistory.bdr_monitor_group_versions (server_id, database_name) VALUES (OLD.server_id, OLD.database_name);
        END IF;
        RETURN NEW;
    END;
$BODY$;

CREATE OR REPLACE FUNCTION pemdata.copy_bdr_node_replication_rates_to_history()
    RETURNS trigger
    LANGUAGE 'plpgsql'
    COST 100
    VOLATILE NOT LEAKPROOF
AS $BODY$
    BEGIN
        IF (TG_OP = 'INSERT' OR TG_OP = 'UPDATE') THEN
            INSERT INTO pemhistory.bdr_node_replication_rates (recorded_time, server_id, database_name, target_name, sent_lsn, replay_lsn, replay_lag, replay_lag_bytes, replay_lag_size, apply_rate, catchup_interval) VALUES (NEW.recorded_time, NEW.server_id, NEW.database_name, NEW.target_name, NEW.sent_lsn, NEW.replay_lsn, NEW.replay_lag, NEW.replay_lag_bytes, NEW.replay_lag_size, NEW.apply_rate, NEW.catchup_interval);
            ELSIF EXISTS(SELECT 1 FROM pem.server WHERE id = OLD.server_id) THEN
            INSERT INTO pemhistory.bdr_node_replication_rates (server_id, database_name, target_name) VALUES (OLD.server_id, OLD.database_name, OLD.target_name);
        END IF;
        RETURN NEW;
    END;
$BODY$;

CREATE OR REPLACE FUNCTION pemdata.copy_bdr_node_slots_to_history()
    RETURNS trigger
    LANGUAGE 'plpgsql'
    COST 100
    VOLATILE NOT LEAKPROOF
AS $BODY$
    BEGIN
        IF (TG_OP = 'INSERT' OR TG_OP = 'UPDATE') THEN
            INSERT INTO pemhistory.bdr_node_slots (recorded_time, server_id, database_name, slot_name, target_name, node_group_name, target_dbname, active_pid, catalog_xmin, client_addr, sent_lsn, replay_lsn, replay_lag, replay_lag_bytes, replay_lag_size) VALUES (NEW.recorded_time, NEW.server_id, NEW.database_name, NEW.slot_name, NEW.target_name, NEW.node_group_name, NEW.target_dbname, NEW.active_pid, NEW.catalog_xmin, NEW.client_addr, NEW.sent_lsn, NEW.replay_lsn, NEW.replay_lag, NEW.replay_lag_bytes, NEW.replay_lag_size);
            ELSIF EXISTS(SELECT 1 FROM pem.server WHERE id = OLD.server_id) THEN
            INSERT INTO pemhistory.bdr_node_slots (server_id, database_name, slot_name) VALUES (OLD.server_id, OLD.database_name, OLD.slot_name);
        END IF;
        RETURN NEW;
    END;
$BODY$;

CREATE OR REPLACE FUNCTION pemdata.copy_bdr_node_summary_to_history()
    RETURNS trigger
    LANGUAGE 'plpgsql'
    COST 100
    VOLATILE NOT LEAKPROOF
AS $BODY$
    BEGIN
        IF (TG_OP = 'INSERT' OR TG_OP = 'UPDATE') THEN
            INSERT INTO pemhistory.bdr_node_summary (recorded_time, server_id, database_name, node_name, node_group_name, peer_state_name, peer_target_state_name, sub_repsets) VALUES (NEW.recorded_time, NEW.server_id, NEW.database_name, NEW.node_name, NEW.node_group_name, NEW.peer_state_name, NEW.peer_target_state_name, NEW.sub_repsets);
            ELSIF EXISTS(SELECT 1 FROM pem.server WHERE id = OLD.server_id) THEN
            INSERT INTO pemhistory.bdr_node_summary (server_id, database_name, node_name) VALUES (OLD.server_id, OLD.database_name, OLD.node_name);
        END IF;
        RETURN NEW;
    END;
$BODY$;

CREATE OR REPLACE FUNCTION pemdata.copy_bdr_stat_relation_to_history()
    RETURNS trigger
    LANGUAGE 'plpgsql'
    COST 100
    VOLATILE NOT LEAKPROOF
AS $BODY$
    BEGIN
        IF (TG_OP = 'INSERT' OR TG_OP = 'UPDATE') THEN
            INSERT INTO pemhistory.bdr_stat_relation (recorded_time, server_id, database_name, nspname, relname, relid, total_time, ninsert, nupdate, ndelete, ntruncate, shared_blks_hit, shared_blks_read, shared_blks_dirtied, shared_blks_written, blk_read_time, blk_write_time, lock_acquire_time) VALUES (NEW.recorded_time, NEW.server_id, NEW.database_name, NEW.nspname, NEW.relname, NEW.relid, NEW.total_time, NEW.ninsert, NEW.nupdate, NEW.ndelete, NEW.ntruncate, NEW.shared_blks_hit, NEW.shared_blks_read, NEW.shared_blks_dirtied, NEW.shared_blks_written, NEW.blk_read_time, NEW.blk_write_time, NEW.lock_acquire_time);
            ELSIF EXISTS(SELECT 1 FROM pem.server WHERE id = OLD.server_id) THEN
            INSERT INTO pemhistory.bdr_stat_relation (server_id, database_name, relname, relid) VALUES (OLD.server_id, OLD.database_name, OLD.relname, OLD.relid);
        END IF;
        RETURN NEW;
    END;
$BODY$;

CREATE OR REPLACE FUNCTION pemdata.copy_bdr_stat_subscription_to_history()
    RETURNS trigger
    LANGUAGE 'plpgsql'
    COST 100
    VOLATILE NOT LEAKPROOF
AS $BODY$
    BEGIN
        IF (TG_OP = 'INSERT' OR TG_OP = 'UPDATE') THEN
            INSERT INTO pemhistory.bdr_stat_subscription (recorded_time, server_id, database_name, sub_name, subid, nconnect, ncommit, nabort, nerror, nskippedtx, ninsert, nupdate, ndelete, ntruncate, nddl, ndeadlocks, nretries, shared_blks_hit, shared_blks_read, shared_blks_dirtied, shared_blks_written, blk_read_time, blk_write_time, connect_time, last_disconnect_time, start_lsn, retries_at_same_lsn, curr_ncommit) VALUES (NEW.recorded_time, NEW.server_id, NEW.database_name, NEW.sub_name, NEW.subid, NEW.nconnect, NEW.ncommit, NEW.nabort, NEW.nerror, NEW.nskippedtx, NEW.ninsert, NEW.nupdate, NEW.ndelete, NEW.ntruncate, NEW.nddl, NEW.ndeadlocks, NEW.nretries, NEW.shared_blks_hit, NEW.shared_blks_read, NEW.shared_blks_dirtied, NEW.shared_blks_written, NEW.blk_read_time, NEW.blk_write_time, NEW.connect_time, NEW.last_disconnect_time, NEW.start_lsn, NEW.retries_at_same_lsn, NEW.curr_ncommit);
            ELSIF EXISTS(SELECT 1 FROM pem.server WHERE id = OLD.server_id) THEN
            INSERT INTO pemhistory.bdr_stat_subscription (server_id, database_name, sub_name, subid) VALUES (OLD.server_id, OLD.database_name, OLD.sub_name, OLD.subid);
        END IF;
        RETURN NEW;
    END;
$BODY$;

CREATE OR REPLACE FUNCTION pemdata.copy_bdr_worker_errors_to_history()
    RETURNS trigger
    LANGUAGE 'plpgsql'
    COST 100
    VOLATILE NOT LEAKPROOF
AS $BODY$
    BEGIN
        IF (TG_OP = 'INSERT' OR TG_OP = 'UPDATE') THEN
            INSERT INTO pemhistory.bdr_worker_errors (recorded_time, server_id, database_name, worker_pid, node_group_name, origin_name, source_name, target_name, sub_name, worker_role, worker_role_name, error_time, error_age, error_message, error_context_message, remoterelid, subwriter_id, subwriter_name) VALUES (NEW.recorded_time, NEW.server_id, NEW.database_name, NEW.worker_pid, NEW.node_group_name, NEW.origin_name, NEW.source_name, NEW.target_name, NEW.sub_name, NEW.worker_role, NEW.worker_role_name, NEW.error_time, NEW.error_age, NEW.error_message, NEW.error_context_message, NEW.remoterelid, NEW.subwriter_id, NEW.subwriter_name);
            ELSIF EXISTS(SELECT 1 FROM pem.server WHERE id = OLD.server_id) THEN
            INSERT INTO pemhistory.bdr_worker_errors (server_id, database_name, worker_pid) VALUES (OLD.server_id, OLD.database_name, OLD.worker_pid);
        END IF;
        RETURN NEW;
    END;
$BODY$;

CREATE OR REPLACE FUNCTION pemdata.copy_bdr_workers_to_history()
    RETURNS trigger
    LANGUAGE 'plpgsql'
    COST 100
    VOLATILE NOT LEAKPROOF
AS $BODY$
    BEGIN
        IF (TG_OP = 'INSERT' OR TG_OP = 'UPDATE') THEN
            INSERT INTO pemhistory.bdr_workers (recorded_time, server_id, database_name, worker_pid, query_start, state_change, wait_event_type, wait_event, state, worker_role_name, worker_commit_timestamp, worker_local_timestamp, origin_name, receive_lsn, receive_commit_lsn, last_xact_replay_lsn, last_xact_flush_lsn, last_xact_replay_timestamp, query) VALUES (NEW.recorded_time, NEW.server_id, NEW.database_name, NEW.worker_pid, NEW.query_start, NEW.state_change, NEW.wait_event_type, NEW.wait_event, NEW.state, NEW.worker_role_name, NEW.worker_commit_timestamp, NEW.worker_local_timestamp, NEW.origin_name, NEW.receive_lsn, NEW.receive_commit_lsn, NEW.last_xact_replay_lsn, NEW.last_xact_flush_lsn, NEW.last_xact_replay_timestamp, NEW.query);
            ELSIF EXISTS(SELECT 1 FROM pem.server WHERE id = OLD.server_id) THEN
            INSERT INTO pemhistory.bdr_workers (server_id, database_name, worker_pid) VALUES (OLD.server_id, OLD.database_name, OLD.worker_pid);
        END IF;
        RETURN NEW;
    END;
$BODY$;

END TRANSACTION;

BEGIN TRANSACTION;

-- Drop primary key for each probe table
ALTER TABLE pemdata.bdr_stat_relation DROP CONSTRAINT IF EXISTS bdr_stat_relation_pkey;
ALTER TABLE pemhistory.bdr_stat_relation DROP CONSTRAINT IF EXISTS bdr_stat_relation_pkey;

ALTER TABLE pemdata.bdr_stat_subscription DROP CONSTRAINT IF EXISTS bdr_stat_subscription_pkey;
ALTER TABLE pemhistory.bdr_stat_subscription DROP CONSTRAINT IF EXISTS bdr_stat_subscription_pkey;

ALTER TABLE pemdata.bdr_group_replslots_details DROP CONSTRAINT IF EXISTS bdr_group_replslots_details_pkey;
ALTER TABLE pemhistory.bdr_group_replslots_details DROP CONSTRAINT IF EXISTS bdr_group_replslots_details_pkey;

ALTER TABLE pemdata.bdr_node_summary DROP CONSTRAINT IF EXISTS bdr_node_summary_pkey;
ALTER TABLE pemhistory.bdr_node_summary DROP CONSTRAINT IF EXISTS bdr_node_summary_pkey;

ALTER TABLE pemdata.bdr_node_replication_rates DROP CONSTRAINT IF EXISTS bdr_node_replication_rates_pkey;
ALTER TABLE pemhistory.bdr_node_replication_rates DROP CONSTRAINT IF EXISTS bdr_node_replication_rates_pkey;

ALTER TABLE pemdata.bdr_node_slots DROP CONSTRAINT IF EXISTS bdr_node_slots_pkey;
ALTER TABLE pemhistory.bdr_node_slots DROP CONSTRAINT IF EXISTS bdr_node_slots_pkey;

ALTER TABLE pemdata.bdr_group_subscription_summary DROP CONSTRAINT IF EXISTS bdr_group_subscription_summary_pkey;
ALTER TABLE pemhistory.bdr_group_subscription_summary DROP CONSTRAINT IF EXISTS bdr_group_subscription_summary_pkey;

ALTER TABLE pemdata.bdr_group_versions_details DROP CONSTRAINT IF EXISTS bdr_group_versions_details_pkey;
ALTER TABLE pemhistory.bdr_group_versions_details DROP CONSTRAINT IF EXISTS bdr_group_versions_details_pkey;

ALTER TABLE pemdata.bdr_monitor_group_versions DROP CONSTRAINT IF EXISTS bdr_monitor_group_versions_pkey;
ALTER TABLE pemhistory.bdr_monitor_group_versions DROP CONSTRAINT IF EXISTS bdr_monitor_group_versions_pkey;

ALTER TABLE pemdata.bdr_group_raft_details DROP CONSTRAINT IF EXISTS bdr_group_raft_details_pkey;
ALTER TABLE pemhistory.bdr_group_raft_details DROP CONSTRAINT IF EXISTS bdr_group_raft_details_pkey;

ALTER TABLE pemdata.bdr_monitor_group_raft DROP CONSTRAINT IF EXISTS bdr_monitor_group_raft_pkey;
ALTER TABLE pemhistory.bdr_monitor_group_raft DROP CONSTRAINT IF EXISTS bdr_monitor_group_raft_pkey;

ALTER TABLE pemdata.bdr_workers DROP CONSTRAINT IF EXISTS bdr_workers_pkey;
ALTER TABLE pemhistory.bdr_workers DROP CONSTRAINT IF EXISTS bdr_workers_pkey;

ALTER TABLE pemdata.bdr_worker_errors DROP CONSTRAINT IF EXISTS bdr_worker_errors_pkey;
ALTER TABLE pemhistory.bdr_worker_errors DROP CONSTRAINT IF EXISTS bdr_worker_errors_pkey;

ALTER TABLE pemdata.bdr_global_locks DROP CONSTRAINT IF EXISTS bdr_global_locks_pkey;
ALTER TABLE pemhistory.bdr_global_locks DROP CONSTRAINT IF EXISTS bdr_global_locks_pkey;

ALTER TABLE pemdata.bdr_conflict_history_summary DROP CONSTRAINT IF EXISTS bdr_conflict_history_summary_pkey;

ALTER TABLE pemdata.bdr_group_camo_details DROP CONSTRAINT IF EXISTS bdr_group_camo_details_pkey;
ALTER TABLE pemhistory.bdr_group_camo_details DROP CONSTRAINT IF EXISTS bdr_group_camo_details_pkey;

-- Add maintenance database for the respective server
ALTER TABLE pemdata.bdr_stat_relation DISABLE TRIGGER USER;
UPDATE pemdata.bdr_stat_relation bdrt SET database_name = ( SELECT COALESCE(asb.database, s.database) FROM pem.server s LEFT JOIN pem.agent_server_binding asb ON asb.server_id = s.id WHERE s.id = bdrt.server_id ) WHERE database_name IS NULL;
UPDATE pemhistory.bdr_stat_relation bdrt SET database_name = ( SELECT COALESCE(asb.database, s.database) FROM pem.server s LEFT JOIN pem.agent_server_binding asb ON asb.server_id = s.id WHERE s.id = bdrt.server_id ) WHERE database_name IS NULL;
ALTER TABLE pemdata.bdr_stat_relation ENABLE TRIGGER USER;

ALTER TABLE pemdata.bdr_stat_subscription DISABLE TRIGGER USER;
UPDATE pemdata.bdr_stat_subscription bdrt SET database_name = ( SELECT COALESCE(asb.database, s.database) FROM pem.server s LEFT JOIN pem.agent_server_binding asb ON asb.server_id = s.id WHERE s.id = bdrt.server_id ) WHERE database_name IS NULL;
UPDATE pemhistory.bdr_stat_subscription bdrt SET database_name = ( SELECT COALESCE(asb.database, s.database) FROM pem.server s LEFT JOIN pem.agent_server_binding asb ON asb.server_id = s.id WHERE s.id = bdrt.server_id ) WHERE database_name IS NULL;
ALTER TABLE pemdata.bdr_stat_subscription ENABLE TRIGGER USER;

ALTER TABLE pemdata.bdr_group_replslots_details DISABLE TRIGGER USER;
UPDATE pemdata.bdr_group_replslots_details bdrt SET database_name = ( SELECT COALESCE(asb.database, s.database) FROM pem.server s LEFT JOIN pem.agent_server_binding asb ON asb.server_id = s.id WHERE s.id = bdrt.server_id ) WHERE database_name IS NULL;
UPDATE pemhistory.bdr_group_replslots_details bdrt SET database_name = ( SELECT COALESCE(asb.database, s.database) FROM pem.server s LEFT JOIN pem.agent_server_binding asb ON asb.server_id = s.id WHERE s.id = bdrt.server_id ) WHERE database_name IS NULL;
ALTER TABLE pemdata.bdr_group_replslots_details ENABLE TRIGGER USER;

ALTER TABLE pemdata.bdr_node_summary DISABLE TRIGGER USER;
UPDATE pemdata.bdr_node_summary bdrt SET database_name = ( SELECT COALESCE(asb.database, s.database) FROM pem.server s LEFT JOIN pem.agent_server_binding asb ON asb.server_id = s.id WHERE s.id = bdrt.server_id ) WHERE database_name IS NULL;
UPDATE pemhistory.bdr_node_summary bdrt SET database_name = ( SELECT COALESCE(asb.database, s.database) FROM pem.server s LEFT JOIN pem.agent_server_binding asb ON asb.server_id = s.id WHERE s.id = bdrt.server_id ) WHERE database_name IS NULL;
ALTER TABLE pemdata.bdr_node_summary ENABLE TRIGGER USER;

ALTER TABLE pemdata.bdr_node_replication_rates DISABLE TRIGGER USER;
UPDATE pemdata.bdr_node_replication_rates bdrt SET database_name = ( SELECT COALESCE(asb.database, s.database) FROM pem.server s LEFT JOIN pem.agent_server_binding asb ON asb.server_id = s.id WHERE s.id = bdrt.server_id ) WHERE database_name IS NULL;
UPDATE pemhistory.bdr_node_replication_rates bdrt SET database_name = ( SELECT COALESCE(asb.database, s.database) FROM pem.server s LEFT JOIN pem.agent_server_binding asb ON asb.server_id = s.id WHERE s.id = bdrt.server_id ) WHERE database_name IS NULL;
ALTER TABLE pemdata.bdr_node_replication_rates ENABLE TRIGGER USER;

ALTER TABLE pemdata.bdr_node_slots DISABLE TRIGGER USER;
UPDATE pemdata.bdr_node_slots bdrt SET database_name = ( SELECT COALESCE(asb.database, s.database) FROM pem.server s LEFT JOIN pem.agent_server_binding asb ON asb.server_id = s.id WHERE s.id = bdrt.server_id ) WHERE database_name IS NULL;
UPDATE pemhistory.bdr_node_slots bdrt SET database_name = ( SELECT COALESCE(asb.database, s.database) FROM pem.server s LEFT JOIN pem.agent_server_binding asb ON asb.server_id = s.id WHERE s.id = bdrt.server_id ) WHERE database_name IS NULL;
ALTER TABLE pemdata.bdr_node_slots ENABLE TRIGGER USER;

ALTER TABLE pemdata.bdr_group_subscription_summary DISABLE TRIGGER USER;
UPDATE pemdata.bdr_group_subscription_summary bdrt SET database_name = ( SELECT COALESCE(asb.database, s.database) FROM pem.server s LEFT JOIN pem.agent_server_binding asb ON asb.server_id = s.id WHERE s.id = bdrt.server_id ) WHERE database_name IS NULL;
UPDATE pemhistory.bdr_group_subscription_summary bdrt SET database_name = ( SELECT COALESCE(asb.database, s.database) FROM pem.server s LEFT JOIN pem.agent_server_binding asb ON asb.server_id = s.id WHERE s.id = bdrt.server_id ) WHERE database_name IS NULL;
ALTER TABLE pemdata.bdr_group_subscription_summary ENABLE TRIGGER USER;

ALTER TABLE pemdata.bdr_group_versions_details DISABLE TRIGGER USER;
UPDATE pemdata.bdr_group_versions_details bdrt SET database_name = ( SELECT COALESCE(asb.database, s.database) FROM pem.server s LEFT JOIN pem.agent_server_binding asb ON asb.server_id = s.id WHERE s.id = bdrt.server_id ) WHERE database_name IS NULL;
UPDATE pemhistory.bdr_group_versions_details bdrt SET database_name = ( SELECT COALESCE(asb.database, s.database) FROM pem.server s LEFT JOIN pem.agent_server_binding asb ON asb.server_id = s.id WHERE s.id = bdrt.server_id ) WHERE database_name IS NULL;
ALTER TABLE pemdata.bdr_group_versions_details ENABLE TRIGGER USER;

ALTER TABLE pemdata.bdr_monitor_group_versions DISABLE TRIGGER USER;
UPDATE pemdata.bdr_monitor_group_versions bdrt SET database_name = ( SELECT COALESCE(asb.database, s.database) FROM pem.server s LEFT JOIN pem.agent_server_binding asb ON asb.server_id = s.id WHERE s.id = bdrt.server_id ) WHERE database_name IS NULL;
UPDATE pemhistory.bdr_monitor_group_versions bdrt SET database_name = ( SELECT COALESCE(asb.database, s.database) FROM pem.server s LEFT JOIN pem.agent_server_binding asb ON asb.server_id = s.id WHERE s.id = bdrt.server_id ) WHERE database_name IS NULL;
ALTER TABLE pemdata.bdr_monitor_group_versions ENABLE TRIGGER USER;

ALTER TABLE pemdata.bdr_group_raft_details DISABLE TRIGGER USER;
UPDATE pemdata.bdr_group_raft_details bdrt SET database_name = ( SELECT COALESCE(asb.database, s.database) FROM pem.server s LEFT JOIN pem.agent_server_binding asb ON asb.server_id = s.id WHERE s.id = bdrt.server_id ) WHERE database_name IS NULL;
UPDATE pemhistory.bdr_group_raft_details bdrt SET database_name = ( SELECT COALESCE(asb.database, s.database) FROM pem.server s LEFT JOIN pem.agent_server_binding asb ON asb.server_id = s.id WHERE s.id = bdrt.server_id ) WHERE database_name IS NULL;
ALTER TABLE pemdata.bdr_group_raft_details ENABLE TRIGGER USER;

ALTER TABLE pemdata.bdr_monitor_group_raft DISABLE TRIGGER USER;
UPDATE pemdata.bdr_monitor_group_raft bdrt SET database_name = ( SELECT COALESCE(asb.database, s.database) FROM pem.server s LEFT JOIN pem.agent_server_binding asb ON asb.server_id = s.id WHERE s.id = bdrt.server_id ) WHERE database_name IS NULL;
UPDATE pemhistory.bdr_monitor_group_raft bdrt SET database_name = ( SELECT COALESCE(asb.database, s.database) FROM pem.server s LEFT JOIN pem.agent_server_binding asb ON asb.server_id = s.id WHERE s.id = bdrt.server_id ) WHERE database_name IS NULL;
ALTER TABLE pemdata.bdr_monitor_group_raft ENABLE TRIGGER USER;

ALTER TABLE pemdata.bdr_workers DISABLE TRIGGER USER;
UPDATE pemdata.bdr_workers bdrt SET database_name = ( SELECT COALESCE(asb.database, s.database) FROM pem.server s LEFT JOIN pem.agent_server_binding asb ON asb.server_id = s.id WHERE s.id = bdrt.server_id ) WHERE database_name IS NULL;
UPDATE pemhistory.bdr_workers bdrt SET database_name = ( SELECT COALESCE(asb.database, s.database) FROM pem.server s LEFT JOIN pem.agent_server_binding asb ON asb.server_id = s.id WHERE s.id = bdrt.server_id ) WHERE database_name IS NULL;
ALTER TABLE pemdata.bdr_workers ENABLE TRIGGER USER;

ALTER TABLE pemdata.bdr_worker_errors DISABLE TRIGGER USER;
UPDATE pemdata.bdr_worker_errors bdrt SET database_name = ( SELECT COALESCE(asb.database, s.database) FROM pem.server s LEFT JOIN pem.agent_server_binding asb ON asb.server_id = s.id WHERE s.id = bdrt.server_id ) WHERE database_name IS NULL;
UPDATE pemhistory.bdr_worker_errors bdrt SET database_name = ( SELECT COALESCE(asb.database, s.database) FROM pem.server s LEFT JOIN pem.agent_server_binding asb ON asb.server_id = s.id WHERE s.id = bdrt.server_id ) WHERE database_name IS NULL;
ALTER TABLE pemdata.bdr_worker_errors ENABLE TRIGGER USER;

ALTER TABLE pemdata.bdr_global_locks DISABLE TRIGGER USER;
UPDATE pemdata.bdr_global_locks bdrt SET database_name = ( SELECT COALESCE(asb.database, s.database) FROM pem.server s LEFT JOIN pem.agent_server_binding asb ON asb.server_id = s.id WHERE s.id = bdrt.server_id ) WHERE database_name IS NULL;
UPDATE pemhistory.bdr_global_locks bdrt SET database_name = ( SELECT COALESCE(asb.database, s.database) FROM pem.server s LEFT JOIN pem.agent_server_binding asb ON asb.server_id = s.id WHERE s.id = bdrt.server_id ) WHERE database_name IS NULL;
ALTER TABLE pemdata.bdr_global_locks ENABLE TRIGGER USER;

UPDATE pemdata.bdr_conflict_history_summary bdrt SET database_name = ( SELECT COALESCE(asb.database, s.database) FROM pem.server s LEFT JOIN pem.agent_server_binding asb ON asb.server_id = s.id WHERE s.id = bdrt.server_id ) WHERE database_name IS NULL;

ALTER TABLE pemdata.bdr_group_camo_details DISABLE TRIGGER USER;
UPDATE pemdata.bdr_group_camo_details bdrt SET database_name = ( SELECT COALESCE(asb.database, s.database) FROM pem.server s LEFT JOIN pem.agent_server_binding asb ON asb.server_id = s.id WHERE s.id = bdrt.server_id ) WHERE database_name IS NULL;
UPDATE pemhistory.bdr_group_camo_details bdrt SET database_name = ( SELECT COALESCE(asb.database, s.database) FROM pem.server s LEFT JOIN pem.agent_server_binding asb ON asb.server_id = s.id WHERE s.id = bdrt.server_id ) WHERE database_name IS NULL;
ALTER TABLE pemdata.bdr_group_camo_details ENABLE TRIGGER USER;

-- Now set not null constraint
ALTER TABLE pemdata.bdr_stat_relation ALTER COLUMN database_name SET NOT NULL;
ALTER TABLE pemhistory.bdr_stat_relation ALTER COLUMN database_name SET NOT NULL;

ALTER TABLE pemdata.bdr_stat_subscription ALTER COLUMN database_name SET NOT NULL;
ALTER TABLE pemhistory.bdr_stat_subscription ALTER COLUMN database_name SET NOT NULL;

ALTER TABLE pemdata.bdr_group_replslots_details ALTER COLUMN database_name SET NOT NULL;
ALTER TABLE pemhistory.bdr_group_replslots_details ALTER COLUMN database_name SET NOT NULL;

ALTER TABLE pemdata.bdr_node_summary ALTER COLUMN database_name SET NOT NULL;
ALTER TABLE pemhistory.bdr_node_summary ALTER COLUMN database_name SET NOT NULL;

ALTER TABLE pemdata.bdr_node_replication_rates ALTER COLUMN database_name SET NOT NULL;
ALTER TABLE pemhistory.bdr_node_replication_rates ALTER COLUMN database_name SET NOT NULL;

ALTER TABLE pemdata.bdr_node_slots ALTER COLUMN database_name SET NOT NULL;
ALTER TABLE pemhistory.bdr_node_slots ALTER COLUMN database_name SET NOT NULL;

ALTER TABLE pemdata.bdr_group_subscription_summary ALTER COLUMN database_name SET NOT NULL;
ALTER TABLE pemhistory.bdr_group_subscription_summary ALTER COLUMN database_name SET NOT NULL;

ALTER TABLE pemdata.bdr_group_versions_details ALTER COLUMN database_name SET NOT NULL;
ALTER TABLE pemhistory.bdr_group_versions_details ALTER COLUMN database_name SET NOT NULL;

ALTER TABLE pemdata.bdr_monitor_group_versions ALTER COLUMN database_name SET NOT NULL;
ALTER TABLE pemhistory.bdr_monitor_group_versions ALTER COLUMN database_name SET NOT NULL;

ALTER TABLE pemdata.bdr_group_raft_details ALTER COLUMN database_name SET NOT NULL;
ALTER TABLE pemhistory.bdr_group_raft_details ALTER COLUMN database_name SET NOT NULL;

ALTER TABLE pemdata.bdr_monitor_group_raft ALTER COLUMN database_name SET NOT NULL;
ALTER TABLE pemhistory.bdr_monitor_group_raft ALTER COLUMN database_name SET NOT NULL;

ALTER TABLE pemdata.bdr_workers ALTER COLUMN database_name SET NOT NULL;
ALTER TABLE pemhistory.bdr_workers ALTER COLUMN database_name SET NOT NULL;

ALTER TABLE pemdata.bdr_worker_errors ALTER COLUMN database_name SET NOT NULL;
ALTER TABLE pemhistory.bdr_worker_errors ALTER COLUMN database_name SET NOT NULL;

ALTER TABLE pemdata.bdr_global_locks ALTER COLUMN database_name SET NOT NULL;
ALTER TABLE pemhistory.bdr_global_locks ALTER COLUMN database_name SET NOT NULL;

ALTER TABLE pemdata.bdr_conflict_history_summary ALTER COLUMN database_name SET NOT NULL;

ALTER TABLE pemdata.bdr_group_camo_details ALTER COLUMN database_name SET NOT NULL;
ALTER TABLE pemhistory.bdr_group_camo_details ALTER COLUMN database_name SET NOT NULL;

END TRANSACTION;

BEGIN TRANSACTION;
-- Add database in Primary key for all the tables
-- Schema - pemdata
ALTER TABLE pemdata.bdr_conflict_history_summary
    ADD CONSTRAINT bdr_conflict_history_summary_pkey PRIMARY KEY (server_id, database_name, conflict_recorded, conflict_type);

ALTER TABLE pemdata.bdr_global_locks
    ADD CONSTRAINT bdr_global_locks_pkey PRIMARY KEY (server_id, database_name, origin_node_name, pid);

ALTER TABLE pemdata.bdr_group_camo_details
    ADD CONSTRAINT bdr_group_camo_details_pkey PRIMARY KEY (server_id, database_name, node_name, camo_partner_of);

ALTER TABLE pemdata.bdr_group_raft_details
    ADD CONSTRAINT bdr_group_raft_details_pkey PRIMARY KEY (server_id, database_name, node_name);

ALTER TABLE pemdata.bdr_group_replslots_details
    ADD CONSTRAINT bdr_group_replslots_details_pkey PRIMARY KEY (server_id, database_name, origin_name, slot_name);

ALTER TABLE pemdata.bdr_group_subscription_summary
    ADD CONSTRAINT bdr_group_subscription_summary_pkey PRIMARY KEY (server_id, database_name, origin_node_name, target_node_name);

ALTER TABLE pemdata.bdr_group_versions_details
    ADD CONSTRAINT bdr_group_versions_details_pkey PRIMARY KEY (server_id, database_name, node_name);

ALTER TABLE pemdata.bdr_monitor_group_raft
    ADD CONSTRAINT bdr_monitor_group_raft_pkey PRIMARY KEY (server_id, database_name);

ALTER TABLE pemdata.bdr_monitor_group_versions
    ADD CONSTRAINT bdr_monitor_group_versions_pkey PRIMARY KEY (server_id, database_name);

ALTER TABLE pemdata.bdr_node_replication_rates
    ADD CONSTRAINT bdr_node_replication_rates_pkey PRIMARY KEY (server_id, database_name, target_name);

ALTER TABLE pemdata.bdr_node_slots
    ADD CONSTRAINT bdr_node_slots_pkey PRIMARY KEY (server_id, database_name, slot_name);

ALTER TABLE pemdata.bdr_node_summary
    ADD CONSTRAINT bdr_node_summary_pkey PRIMARY KEY (server_id, database_name, node_name);

ALTER TABLE pemdata.bdr_stat_relation
    ADD CONSTRAINT bdr_stat_relation_pkey PRIMARY KEY (server_id, database_name, relname, relid);

ALTER TABLE pemdata.bdr_stat_subscription
    ADD CONSTRAINT bdr_stat_subscription_pkey PRIMARY KEY (server_id, database_name, sub_name, subid);

ALTER TABLE pemdata.bdr_worker_errors
    ADD CONSTRAINT bdr_worker_errors_pkey PRIMARY KEY (server_id, database_name, worker_pid);

ALTER TABLE pemdata.bdr_workers
    ADD CONSTRAINT bdr_workers_pkey PRIMARY KEY (server_id, database_name, worker_pid);

-- Schema - pemhistory
ALTER TABLE pemhistory.bdr_global_locks
    ADD CONSTRAINT bdr_global_locks_pkey PRIMARY KEY (server_id, database_name, origin_node_name, pid, recorded_time);

ALTER TABLE pemhistory.bdr_group_camo_details
    ADD CONSTRAINT bdr_group_camo_details_pkey PRIMARY KEY (server_id, database_name, node_name, camo_partner_of, recorded_time);

ALTER TABLE pemhistory.bdr_group_raft_details
    ADD CONSTRAINT bdr_group_raft_details_pkey PRIMARY KEY (server_id, database_name, node_name, recorded_time);

ALTER TABLE pemhistory.bdr_group_replslots_details
    ADD CONSTRAINT bdr_group_replslots_details_pkey PRIMARY KEY (server_id, database_name, origin_name, slot_name, recorded_time);

ALTER TABLE pemhistory.bdr_group_subscription_summary
    ADD CONSTRAINT bdr_group_subscription_summary_pkey PRIMARY KEY (server_id, database_name, origin_node_name, target_node_name, recorded_time);

ALTER TABLE pemhistory.bdr_group_versions_details
    ADD CONSTRAINT bdr_group_versions_details_pkey PRIMARY KEY (server_id, database_name, node_name, recorded_time);

ALTER TABLE pemhistory.bdr_monitor_group_raft
    ADD CONSTRAINT bdr_monitor_group_raft_pkey PRIMARY KEY (server_id, database_name, recorded_time);

ALTER TABLE pemhistory.bdr_monitor_group_versions
    ADD CONSTRAINT bdr_monitor_group_versions_pkey PRIMARY KEY (server_id, database_name, recorded_time);

ALTER TABLE pemhistory.bdr_node_replication_rates
    ADD CONSTRAINT bdr_node_replication_rates_pkey PRIMARY KEY (server_id, database_name, target_name, recorded_time);

ALTER TABLE pemhistory.bdr_node_slots
    ADD CONSTRAINT bdr_node_slots_pkey PRIMARY KEY (server_id, database_name, slot_name, recorded_time);

ALTER TABLE pemhistory.bdr_node_summary
    ADD CONSTRAINT bdr_node_summary_pkey PRIMARY KEY (server_id, database_name, node_name, recorded_time);

ALTER TABLE pemhistory.bdr_stat_relation
    ADD CONSTRAINT bdr_stat_relation_pkey PRIMARY KEY (server_id, database_name, relname, relid, recorded_time);

ALTER TABLE pemhistory.bdr_stat_subscription
    ADD CONSTRAINT bdr_stat_subscription_pkey PRIMARY KEY (server_id, database_name, sub_name, subid, recorded_time);

ALTER TABLE pemhistory.bdr_worker_errors
    ADD CONSTRAINT bdr_worker_errors_pkey PRIMARY KEY (server_id, database_name, worker_pid, recorded_time);

ALTER TABLE pemhistory.bdr_workers
    ADD CONSTRAINT bdr_workers_pkey PRIMARY KEY (server_id, database_name, worker_pid, recorded_time);

END TRANSACTION;

BEGIN TRANSACTION;

-- View to fetch extension level probes with respect to their version if specified
-- View to fetch extension level probes with respect to their version if specified
CREATE OR REPLACE VIEW pem.probe_target_extension_view AS
SELECT
	p.id AS probe_id, p.display_name AS probe_display_name,
	p.internal_name AS probe_internal_name, p.probe_key_list,
	p.applies_to_id,
	a.id AS agent_id, b.server_id, b.database AS database_name,
	ARRAY['server_id', 'database_name']::text[] AS parameter_name_list,
	ARRAY[b.server_id::text, ocd.database_name]::text[] AS parameter_value_list,
	p.collection_method,
	p.probe_code AS probe_code,
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
	INNER JOIN pem.server s ON b.server_id = s.id
	INNER JOIN pemdata.oc_database ocd
		ON b.server_id = ocd.server_id
	LEFT JOIN pemdata.server_info sd ON b.server_id = sd.server_id
    LEFT JOIN pemdata.oc_extension oce ON b.server_id = oce.server_id
        AND oce.database_name = ocd.database_name
        AND p.extension_name = oce.extension_name
	LEFT JOIN pem.probe_config_extension c
		ON p.id = c.probe_id AND b.server_id = c.server_id AND c.database_name = oce.database_name
WHERE
	p.target_type_id = 1000
	AND NOT p.deleted
	AND (p.agent_capability IS NULL
		OR p.agent_capability = ANY(a.agent_capability_list))
	-- Any extension version
    AND p.any_extension_version
	AND p.internal_name NOT IN( SELECT UNNEST(CASE WHEN s.is_remote_monitoring THEN ARRAY['pg_hba_conf', 'data_log_file_analysis', 'wal_archive_status', 'log_configuration', 'efm_cluster_node_status', 'efm_cluster_info'] ELSE ARRAY[''] END))
	AND p.internal_name NOT IN( SELECT UNNEST(CASE WHEN a.agent_capability_list @> ARRAY['windows'] THEN ARRAY['efm_cluster_node_status', 'efm_cluster_info'] ELSE ARRAY[''] END))
	AND (p.collection_method != 'b' OR
		(p.collection_method ='b' AND (a.agent_capability_list @> ARRAY['allow_batch_probes'])
			AND ((strpos(a.platform, p.platform) != 0) OR (a.platform !~ 'windows' AND p.platform = 'unix'))))
	AND b.database NOT IN (SELECT UNNEST(b.exclude_databases))
UNION ALL
SELECT
	p.id AS probe_id, p.display_name AS probe_display_name,
	p.internal_name AS probe_internal_name, p.probe_key_list,
	p.applies_to_id,
	a.id AS agent_id, b.server_id, b.database AS database_name,
	ARRAY['server_id', 'database_name']::text[] AS parameter_name_list,
	ARRAY[b.server_id::text, ocd.database_name]::text[] AS parameter_value_list,
	p.collection_method,
	COALESCE(NULLIF(TRIM(pev.probe_code), ''), p.probe_code) AS probe_code,
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
	INNER JOIN pem.server s ON b.server_id = s.id
	INNER JOIN pemdata.oc_database ocd
		ON b.server_id = ocd.server_id
	LEFT JOIN pemdata.server_info sd ON b.server_id = sd.server_id
    LEFT JOIN pemdata.oc_extension oce ON b.server_id = oce.server_id
        AND oce.database_name = ocd.database_name
        AND p.extension_name = oce.extension_name
    LEFT JOIN pem.probe_extension_version pev
        ON p.id = pev.probe_id
        AND sd.server_version_id = pev.server_version_id
        AND oce.extension_version = pev.extension_version
	LEFT JOIN pem.probe_config_extension c
		ON p.id = c.probe_id AND b.server_id = c.server_id AND c.database_name = oce.database_name
WHERE
	p.target_type_id = 1000
	AND NOT p.deleted
	AND (p.agent_capability IS NULL
		OR p.agent_capability = ANY(a.agent_capability_list))
	-- Specific extension version
    AND NOT p.any_extension_version
	AND p.internal_name NOT IN( SELECT UNNEST(CASE WHEN s.is_remote_monitoring THEN ARRAY['pg_hba_conf', 'data_log_file_analysis', 'wal_archive_status', 'log_configuration', 'efm_cluster_node_status', 'efm_cluster_info'] ELSE ARRAY[''] END))
	AND p.internal_name NOT IN( SELECT UNNEST(CASE WHEN a.agent_capability_list @> ARRAY['windows'] THEN ARRAY['efm_cluster_node_status', 'efm_cluster_info'] ELSE ARRAY[''] END))
	AND (p.collection_method != 'b' OR
		(p.collection_method ='b' AND (a.agent_capability_list @> ARRAY['allow_batch_probes'])
			AND ((strpos(a.platform, p.platform) != 0) OR (a.platform !~ 'windows' AND p.platform = 'unix'))))
	AND b.database NOT IN (SELECT UNNEST(b.exclude_databases));

CREATE OR REPLACE FUNCTION pem.generate_metric_chart_data (
	p_cid integer, p_did integer, p_aid integer, p_sid integer, p_db text, p_schema text, p_tbl text,
	p_level integer, p_sysobjs boolean, p_stime timestamptz DEFAULT NULL,
	p_etime timestamptz DEFAULT NULL)
RETURNS TABLE(o_idx int2, o_label text, o_aggtime timestamptz, o_aggval numeric)
AS $$
DECLARE
	v_chart_exists boolean := false;
	v_oid          integer;
	v_s_time       timestamptz := NULL;
	v_e_time       timestamptz := now();
	v_c_time       timestamptz := now();
	v_e_span       interval := NULL;
	v_e_id         integer := NULL;
	v_e_op         text;
	v_e_val        numeric;
	v_maxpoints    bigint;
	v_mcurs        refcursor;
	v_gcurs        refcursor;
	v_metric       pem.chart_metric%ROWTYPE;
	v_chart        pem.chart%ROWTYPE;
	v_pname        text;
	v_pid          int4;
	v_target       integer;
	v_applies      integer;
	v_deleted      boolean;
	v_disc_history boolean;
	v_keys         text[];
	v_key_vals     text[];
	v_m_rest_dbs   text[];
	v_rest_dbs     text[];
	v_rest_schemas text[];
	v_pos          int2 := 0;
	v_qry          text;
	v_aggqry       text[];
	v_t_str        text;
	v__params      text[];
	v__vals        text[];
	v_params       text[];
	v_vals         text[];
	v_mlbl         text := NULL;
	v_percent_unit boolean := false;
	v_ptype        text := NULL;
	v_span         interval := NULL;
	v_r_monitored  boolean := false;
	v_m_ops        text[][] = array[]::text[][];
	v_t_op         text[] := NULL;
	v_freq         interval;
	v_minfreq      interval := NULL;
	v_aggspan      interval;
	v_obj_active   boolean;
	v_obj          text;
	v_groupon      text;
	v_where        text;
	v_t_time       timestamptz := now();

	v_m_e_time     timestamptz := NULL;
	v_m_s_time     timestamptz := NULL;

	v_slope        numeric;
	v_intercept    numeric;
	v_corr         numeric;
	v_cnt          numeric;
	v_value        numeric;
	v_tmpval       numeric;

BEGIN
	-- Check if the data for the chart exists in the pem.metrices_chart
	EXECUTE 'SELECT CASE WHEN count(charts.*) > 0 THEN true ELSE false END FROM ((SELECT cid FROM pem.metrices_chart WHERE cid = $1::int4) UNION ALL (SELECT cid FROM pem.capacity_report_chart WHERE cid = $1::int4)) AS charts'
	INTO v_chart_exists USING p_cid;

	IF NOT v_chart_exists OR v_chart_exists IS NULL THEN

		o_idx := -1;
		o_label := '101';
		o_aggval := NULL;
		o_aggtime := NULL;
		RETURN NEXT;

		RETURN;
	END IF;

	IF p_sid IS NULL THEN
		v_oid = p_aid;
	ELSE
		v_oid = p_sid;
	END IF;

	EXECUTE E'
WITH chart_cfg AS (
	SELECT
		c.id AS cid,
		/*
		 * Some system level charts has configuration for the historical span,
		 * no of rows, and timeout saved in the pem.config table
		 *
		 * We will calculate the span in hours only
		 * Hence, EPOCH (i.e. seconds) / 3600.
		 */
		CASE
			WHEN c.type = ''L'' THEN
				COALESCE((SELECT (cfg.value || cfg.unit)::interval FROM pem.config cfg
					WHERE cfg.param = c.rwlimit_span_param), mc.time_span)::interval
			WHEN c.type IN (''CL'', ''CT'') AND cr.type = ''E'' THEN
				((cr.historical * 24) || '' hours'')::interval
			ELSE NULL
		END AS span,
		CASE
			WHEN c.type = ''L'' AND
				(mc.ext_id IS NULL AND mc.ext_span > ''0 hours''::interval) THEN
				mc.ext_span::interval
			WHEN c.type IN (''CL'', ''CT'') AND
				cr.type != ''E'' AND cr.extrapolated IS NOT NULL THEN
				((cr.extrapolated * 24) || '' hours'')::interval
			ELSE NULL
		END AS espan,
		/*
		 * maximum no of points are for line (normal/capacity report) charts
		 * and no of rows for tables
		 */
		CASE
			WHEN c.type = ''L'' THEN
				mc.max_points::bigint
			WHEN c.type IN (''CL'', ''CT'') THEN
				(SELECT value FROM pem.config WHERE param = ''cm_data_points_per_report'')::bigint
			ELSE NULL
		END AS points,
		CASE
			WHEN c.type IN (''CL'', ''CT'') THEN
				cr.midx
			ELSE mc.ext_id
		END AS ext_id,
		CASE
			WHEN c.type IN (''CL'', ''CT'') THEN
				cr.toperator::character varying
			ELSE mc.ext_op::character varying
		END AS ext_op,
		CASE
			WHEN c.type IN (''CL'', ''CT'') THEN
				cr.tval
			ELSE mc.ext_val
		END AS ext_val
	FROM
		pem.chart c
		LEFT JOIN (SELECT * FROM pem.metrices_chart WHERE cid = $1::integer) mc
			ON (mc.cid = c.id)
		LEFT JOIN (SELECT * FROM pem.data_chart WHERE cid = $1::integer) dc
			ON (dc.cid = c.id)
		LEFT JOIN (SELECT * FROM pem.capacity_report_chart WHERE cid = $1::integer) cr
			ON (cr.cid = c.id)
	WHERE c.id = $1::integer
),
user_cfg AS (
SELECT * FROM (
    SELECT
        cfg.cid,
        cfg.level,
        cfg.did,
		CASE
		WHEN cfg.did = -1 THEN
			CASE
			WHEN cfg.objid IS NULL THEN 1::integer
			WHEN $3::integer IS NOT NULL AND cfg.objid = $3::integer AND
				cfg.database IS NULL
				THEN 2::integer
			WHEN $3::integer IS NOT NULL AND cfg.objid = $3::integer AND
				$4::text IS NOT NULL AND cfg.database = $4::text AND
				cfg.schema IS NULL
				THEN 3::integer
			WHEN $3::integer IS NOT NULL AND cfg.objid = $3::integer AND
				$4::text IS NOT NULL AND cfg.database = $4::text AND
				$5::text IS NOT NULL AND cfg.schema = $5::text AND
				cfg.tbl IS NULL
				THEN 4::integer
			WHEN $3::integer IS NOT NULL AND cfg.objid = $3::integer AND
				$4::text IS NOT NULL AND cfg.database = $4::text AND
				$5::text IS NOT NULL AND cfg.schema = $5::text AND
				$6::text IS NOT NULL AND cfg.tbl = $6::text
				THEN 5::integer
			END
		ELSE
			CASE
			WHEN cfg.objid IS NULL THEN 6::integer
			WHEN $3::integer IS NOT NULL AND cfg.objid = $3::integer AND
				cfg.database IS NULL
				THEN 7::integer
			WHEN $3::integer IS NOT NULL AND cfg.objid = $3::integer AND
				$4::text IS NOT NULL AND cfg.database = $4::text AND
				cfg.schema IS NULL
				THEN 8::integer
			WHEN $3::integer IS NOT NULL AND cfg.objid = $3::integer AND
				$4::text IS NOT NULL AND cfg.database = $4::text AND
				$5::text IS NOT NULL AND cfg.schema = $5::text AND
				cfg.tbl IS NULL
				THEN 9::integer
			WHEN $3::integer IS NOT NULL AND cfg.objid = $3::integer AND
				$4::text IS NOT NULL AND cfg.database = $4::text AND
				$5::text IS NOT NULL AND cfg.schema = $5::text AND
				$6::text IS NOT NULL AND cfg.tbl = $6::text
				THEN 10::integer
			END
		END AS lvl,
		CASE WHEN cfg.span IS NOT NULL THEN (cfg.span || '' hours'')::interval ELSE NULL END AS span,
		CASE WHEN cfg.espan IS NOT NULL THEN (cfg.espan || '' hours'')::interval ELSE NULL END AS espan,
		cfg.points::bigint
FROM
    pem.chart_config cfg
WHERE
    /*
     * Find the chart configuration for the specified in pem.chart_config:
     * 1. Matches for the same combination on the same did
     * 2. On any dashboard (for same configuration)
     */
    cfg.cid = $1::integer AND
    ((cfg.did = -1 AND cfg.level <= $8::integer) OR (cfg.did = $2::integer AND
    $2::integer IS NOT NULL)) AND
    cfg.uid = (
        SELECT u.usesysid FROM pg_catalog.pg_user u
            WHERE u.usename = current_user
    )
) a
WHERE lvl IS NOT NULL
/*
 * we only need the highest level possible chart configuration saved by the
 * user
 */
ORDER BY did DESC, lvl DESC, level DESC
LIMIT 1
)
/*
 * Give priority to the user configuration over default configuration
 */
SELECT
	$7::timestamptz - COALESCE(x.span, c.span, ''7 days''::interval) AS stime,
	$7::timestamptz AS etime,
	COALESCE(x.span, c.span, ''7 days''::interval) AS span,
	COALESCE(x.espan, c.espan) AS espan,
	COALESCE(x.points, c.points) AS points,
	ext_id,
	ext_op,
	ext_val
FROM
	chart_cfg c LEFT OUTER JOIN user_cfg x ON (c.cid = x.cid)'
		INTO v_s_time, v_e_time, v_span, v_e_span, v_maxpoints, v_e_id, v_e_op, v_e_val
		USING p_cid, p_did, v_oid, p_db, p_schema, p_tbl, v_c_time, p_level;

	-- Couldn't fetch the time_span/max_points from the pem.metrices_chart table
	IF v_s_time IS NULL THEN
		o_idx := -1;
		o_label := '102';
		o_aggval := NULL;
		o_aggtime := NULL;
		RETURN NEXT;

		RETURN;
	END IF;

	IF p_stime IS NOT NULL AND p_etime IS NOT NULL THEN
		IF p_stime > p_etime THEN
			v_s_time := p_etime;
			v_e_time := p_stime;
		ELSE
			v_s_time := p_stime;
			v_e_time := p_etime;
		END IF;
	ELSE
		p_stime := NULL;
		p_etime := NULL;
	END IF;

	CASE
	WHEN p_level = 100 THEN
		-- On agent level dash, agent-id must exists
		IF p_aid IS NULL OR p_aid <= 0 THEN
			o_idx := -1;
			o_label := '103';
			o_aggval := NULL;
			o_aggtime := NULL;
			RETURN NEXT;

			RETURN;
		END IF;

	WHEN p_level >= 200 THEN
		-- On server level dash, server-id must exists
		IF p_sid IS NULL OR p_sid <= 0 THEN
			o_idx := -1;
			o_label := '104';
			o_aggval := NULL;
			o_aggtime := NULL;
			RETURN NEXT;

			RETURN;
		END IF;

		-- Fetch agent-id, if not provided
		IF p_aid IS NULL OR p_aid <= 0 THEN
			p_aid := NULL;

			EXECUTE 'SELECT agent_id FROM pem.agent_server_binding WHERE server_id = $1::int4' INTO p_aid USING p_sid;

			IF p_aid IS NULL THEN
				o_idx := -1;
				o_label := '105';
				o_aggval := NULL;
				o_aggtime := NULL;
				RETURN NEXT;

				RETURN;
			END IF;
		END IF;

		-- Fetch remote monitoring status of the server.
		EXECUTE 'SELECT is_remote_monitoring FROM pem.server WHERE id = $1::int4' INTO v_r_monitored USING p_sid;

		-- Fetch the restricted databases information (only for server level charts)
		IF p_level = 200 THEN
			EXECUTE '
SELECT
	pem.db_escaped_string_to_array(COALESCE(o.database_restriction, oa.database_restriction))
FROM
	pem.server s
	LEFT OUTER JOIN pg_catalog.pg_roles owner ON (owner.oid = s.owner)
	LEFT OUTER JOIN pem.server_options o ON (s.id = o.server_id AND o.pem_user = current_user)
	LEFT OUTER JOIN pem.server_options oa
		ON (o.server_id IS NULL AND s.id = oa.server_id AND
			(owner.rolname = oa.pem_user OR (owner.rolname IS NULL AND oa.pem_user IS NULL)))
WHERE
	s.id = $1::int4' INTO v_rest_dbs USING p_sid;
		END IF;

		IF p_level >= 300 THEN
			-- database_name is required for any charts lower than server
			-- level
			IF p_db IS NULL OR trim(p_db) = '' THEN
				o_idx := -1;
				o_label := '106';
				o_aggval := NULL;
				o_aggtime := NULL;
				RETURN NEXT;

				RETURN;
			END IF;

			-- Fetch the restricted schema information (for database level chats)
			IF p_level = 300 THEN
				EXECUTE '
SELECT
	pem.db_escaped_string_to_array(COALESCE(o.schema_restriction, oa.schema_restriction))
FROM
	pem.server s
	LEFT OUTER JOIN pg_catalog.pg_roles owner ON (owner.oid = s.owner)
	LEFT OUTER JOIN pem.database_option o ON (s.id = o.server_id AND o.pem_user = current_user AND o.database = $2::text)
	LEFT OUTER JOIN pem.database_option oa
		ON (o.server_id IS NULL AND s.id = oa.server_id AND oa.database = $2::text AND
			(owner.rolname = oa.pem_user OR (owner.rolname IS NULL AND oa.pem_user IS NULL)))
WHERE
	s.id = $1::int4' INTO v_rest_schemas USING p_sid, p_db;
			END IF;
		END IF;
	ELSE -- DO NOTHING
	END CASE;

	EXECUTE 'SELECT * FROM pem.chart WHERE id = $1::int4' USING p_cid INTO v_chart;

	-- Fetch all the metrices for this chart
	OPEN v_mcurs FOR EXECUTE 'SELECT * FROM pem.chart_metric WHERE cid = $1::int4' USING p_cid;
	LOOP
		FETCH v_mcurs INTO v_metric;
		EXIT WHEN NOT FOUND;

		v_pname := NULL;
		v_pid := NULL;
		v_target := NULL;
		v_applies := NULL;
		v_keys := NULL;
		v_deleted := false;
		v_disc_history := true;

		-- FETCH target_type, probe_applies_to, PRIMARY KEYS FOR THE INVOLVED
		-- PROBE-TABLE
		EXECUTE
		'SELECT p.display_name, p.id, p.target_type_id, p.applies_to_id, ARRAY(SELECT pc.internal_name FROM pem.probe_column pc WHERE pc.probe_id = p.id AND (($2::int4 = 300 AND pc.internal_name <> ''database_name'') OR ($2::int4 = 400 AND pc.internal_name NOT IN (''database_name'', ''schema_name'')) OR true) AND pc.classification = ''k'' ORDER BY pc.id) AS keys, p.deleted, p.discard_history FROM pem.probe p WHERE p.internal_name = $1::text'
		INTO v_pname, v_pid, v_target, v_applies, v_keys, v_deleted, v_disc_history USING v_metric.tbl, p_level;

		-- WE COULDN'T FIND 'probe_target_id', IT MEANS THE PROBE WITH
		-- THAT NAME DOES NOT EXISTS
		IF v_target IS NULL THEN
			IF v_e_id IS NOT NULL AND v_e_id = v_metric.mid THEN
				o_idx := -1;
				o_label := '107|' || v_metric.tbl;
				o_aggval := NULL;
				o_aggtime := NULL;
				RETURN NEXT;

				RETURN;
			END IF;

			o_idx := -1;
			o_label := '108|' || v_metric.tbl;
			o_aggval := NULL;
			o_aggtime := NULL;
			RETURN NEXT;

			CONTINUE;
		END IF;

		IF v_deleted THEN

			-- The probe has been marked for deletion
			IF v_e_id IS NOT NULL AND v_e_id = v_metric.mid THEN
				o_idx := -1;
				o_label := '107|' || COALESCE(v_pname, v_metric.tbl);
				o_aggval := NULL;
				o_aggtime := NULL;
				RETURN NEXT;

				RETURN;
			END IF;

			o_idx := -1;
			o_label := '108|' || COALESCE(v_pname, v_metric.tbl);
			o_aggval := NULL;
			o_aggtime := NULL;
			RETURN NEXT;

			CONTINUE;
		ELSIF v_disc_history THEN
			o_idx := -1;
			o_label := '109|' || COALESCE(v_pname, v_metric.tbl);
			o_aggval := NULL;
			o_aggtime := NULL;
			RETURN NEXT;

			CONTINUE;
		END IF;

		IF v_metric.params IS NOT NULL OR array_length(v_metric.params::pem.chart_metric_param[], 1) <> 0 THEN
			SELECT string_agg('pc.' || pg_catalog.quote_ident((param).name) || ' = ' || pg_catalog.quote_literal((param).value), ' AND ') FROM (SELECT unnest(v_metric.params::pem.chart_metric_param[]) AS param) p WHERE (param).name IN ('agent_id','server_id', 'database_name') INTO v_t_str;

			CASE
			WHEN ((v_metric.params::pem.chart_metric_param[])[1]).name = 'agent_id' THEN
				EXECUTE 'SELECT description, active FROM pem.agent WHERE id = $1::int4'
					USING ((v_metric.params::pem.chart_metric_param[])[1]).value
					INTO v_obj, v_obj_active;
			WHEN ((v_metric.params::pem.chart_metric_param[])[1]).name = 'server_id' THEN
				EXECUTE 'SELECT description, active FROM pem.server WHERE id = $1::int4'
					USING ((v_metric.params::pem.chart_metric_param[])[1]).value
					INTO v_obj, v_obj_active;
			ELSE
			END CASE;
			IF v_obj_active IS NULL OR v_obj_active = false THEN
				o_idx := -1;
				o_aggval := NULL;
				o_aggtime := NULL;

				-- The probe has been marked for deletion
				IF v_e_id IS NOT NULL AND v_e_id = v_metric.mid THEN
					IF ((v_metric.params::pem.chart_metric_param[])[1]).name = 'agent_id' THEN
						o_label := '112|'::text || COALESCE(v_obj, ((v_metric.params::pem.chart_metric_param[])[1]).value);
					ELSE
						o_label := '113|'::text || COALESCE(v_obj, ((v_metric.params::pem.chart_metric_param[])[1]).value);
					END IF;
					RETURN NEXT;
					RETURN;
				END IF;

				IF ((v_metric.params::pem.chart_metric_param[])[1]).name = 'agent_id' THEN
					o_label :=  '110|'::text || COALESCE(v_obj, ((v_metric.params::pem.chart_metric_param[])[1]).value);
				ELSE
					o_label :=  '111|'::text || COALESCE(v_obj, ((v_metric.params::pem.chart_metric_param[])[1]).value);
				END IF;
				RETURN NEXT;
				CONTINUE;
			END IF;

			CASE v_target
			WHEN 100 THEN
				IF array_length(v_metric.params::pem.chart_metric_param[], 1) >= 1 AND ((v_metric.params::pem.chart_metric_param[])[1]).name = 'agent_id' AND ((v_metric.params::pem.chart_metric_param[])[1]).value IS NOT NULL THEN
					EXECUTE 'SELECT COALESCE(c.execution_frequency, p.default_execution_frequency) AS freq FROM pem.probe p LEFT JOIN pem.probe_config_agent c ON (p.id = c.probe_id AND c.agent_id = $2::integer) WHERE p.id = $1::integer' USING v_pid, (((v_metric.params::pem.chart_metric_param[])[1]).value)::integer INTO v_freq;
				ELSE
					EXECUTE 'SELECT p.default_execution_frequency AS freq FROM pem.probe p WHERE p.id = $1::integer' USING v_pid INTO v_freq;
				END IF;
			WHEN 200 THEN
				IF array_length(v_metric.params::pem.chart_metric_param[], 1) >= 1 AND ((v_metric.params::pem.chart_metric_param[])[1]).name = 'server_id' AND ((v_metric.params::pem.chart_metric_param[])[1]).value IS NOT NULL THEN
					EXECUTE 'SELECT COALESCE(c.execution_frequency, p.default_execution_frequency) AS freq FROM pem.probe p LEFT JOIN pem.probe_config_server c ON (p.id = c.probe_id AND c.server_id = $2::integer) WHERE p.id = $1::integer' USING v_pid, (((v_metric.params::pem.chart_metric_param[])[1]).value)::integer INTO v_freq;
				ELSE
					EXECUTE 'SELECT p.default_execution_frequency AS freq FROM pem.probe p WHERE p.id = $1::integer' USING v_pid INTO v_freq;
				END IF;
			WHEN 300 THEN
				IF array_length(v_metric.params::pem.chart_metric_param[], 1) >= 2 AND ((v_metric.params::pem.chart_metric_param[])[1]).name = 'server_id' AND ((v_metric.params::pem.chart_metric_param[])[1]).value IS NOT NULL AND
					((v_metric.params::pem.chart_metric_param[])[2]).name = 'database_name' AND ((v_metric.params::pem.chart_metric_param[])[2]).value IS NOT NULL THEN
					EXECUTE 'SELECT COALESCE(c.execution_frequency, p.default_execution_frequency) AS freq FROM pem.probe p LEFT JOIN pem.probe_config_database c ON (p.id = c.probe_id AND c.server_id = $2::integer AND c.database_name = $3::text) WHERE p.id = $1::integer' USING v_pid, (((v_metric.params::pem.chart_metric_param[])[1]).value)::integer, (((v_metric.params::pem.chart_metric_param[])[2]).value)::text INTO v_freq;
				ELSE
					EXECUTE 'SELECT p.default_execution_frequency AS freq FROM pem.probe p WHERE p.id = $1::integer' USING v_pid INTO v_freq;
				END IF;
			WHEN 400 THEN
				IF array_length(v_metric.params::pem.chart_metric_param[], 1) >= 3 AND ((v_metric.params::pem.chart_metric_param[])[1]).name = 'server_id' AND ((v_metric.params::pem.chart_metric_param[])[1]).value IS NOT NULL AND
					((v_metric.params::pem.chart_metric_param[])[2]).name = 'database_name' AND ((v_metric.params::pem.chart_metric_param[])[2]).value IS NOT NULL AND
					((v_metric.params::pem.chart_metric_param[])[3]).name = 'schema_name' AND ((v_metric.params::pem.chart_metric_param[])[3]).value IS NOT NULL THEN
					EXECUTE 'SELECT COALESCE(c.execution_frequency, p.default_execution_frequency) AS freq FROM pem.probe p LEFT JOIN pem.probe_config_schema c ON (p.id = c.probe_id AND c.server_id = $2::integer AND c.database_name = $3::text AND c.schema_name = $4::text) WHERE p.id = $1::integer' USING v_pid, (((v_metric.params::pem.chart_metric_param[])[1]).value)::integer, (((v_metric.params::pem.chart_metric_param[])[2]).value)::text, (((v_metric.params::pem.chart_metric_param[])[3]).value)::text INTO v_freq;
				ELSE
					EXECUTE 'SELECT p.default_execution_frequency AS freq FROM pem.probe p WHERE p.id = $1::integer' USING v_pid INTO v_freq;
				END IF;
			WHEN 500 THEN
				IF array_length(v_metric.params::pem.chart_metric_param[], 1) >= 4 AND ((v_metric.params::pem.chart_metric_param[])[1]).name = 'server_id' AND ((v_metric.params::pem.chart_metric_param[])[1]).value IS NOT NULL AND
					((v_metric.params::pem.chart_metric_param[])[2]).name = 'database_name' AND ((v_metric.params::pem.chart_metric_param[])[2]).value IS NOT NULL AND
					((v_metric.params::pem.chart_metric_param[])[3]).name = 'schema_name' AND ((v_metric.params::pem.chart_metric_param[])[3]).value IS NOT NULL AND
					((v_metric.params::pem.chart_metric_param[])[4]).name = 'table_name' AND ((v_metric.params::pem.chart_metric_param[])[4]).value IS NOT NULL THEN
					EXECUTE 'SELECT COALESCE(c.execution_frequency, p.default_execution_frequency) AS freq FROM pem.probe p LEFT JOIN pem.probe_config_table c ON (p.id = c.probe_id AND c.server_id = $2::integer AND c.database_name = $3::text AND c.schema_name = $4::text AND c.table_name = $5::text) WHERE p.id = $1::integer' USING v_pid, (((v_metric.params::pem.chart_metric_param[])[1]).value)::integer, (((v_metric.params::pem.chart_metric_param[])[2]).value)::text, (((v_metric.params::pem.chart_metric_param[])[3]).value)::text, (((v_metric.params::pem.chart_metric_param[])[4]).value)::text INTO v_freq;
				ELSE
					EXECUTE 'SELECT p.default_execution_frequency AS freq FROM pem.probe p WHERE p.id = $1::integer' USING v_pid INTO v_freq;
				END IF;
			WHEN 600 THEN
				IF array_length(v_metric.params::pem.chart_metric_param[], 1) >= 4 AND ((v_metric.params::pem.chart_metric_param[])[1]).name = 'server_id' AND ((v_metric.params::pem.chart_metric_param[])[1]).value IS NOT NULL AND
					((v_metric.params::pem.chart_metric_param[])[2]).name = 'database_name' AND ((v_metric.params::pem.chart_metric_param[])[2]).value IS NOT NULL AND
					((v_metric.params::pem.chart_metric_param[])[3]).name = 'schema_name' AND ((v_metric.params::pem.chart_metric_param[])[3]).value IS NOT NULL AND
					((v_metric.params::pem.chart_metric_param[])[4]).name = 'index_name' AND ((v_metric.params::pem.chart_metric_param[])[4]).value IS NOT NULL THEN
					EXECUTE 'SELECT COALESCE(c.execution_frequency, p.default_execution_frequency) AS freq FROM pem.probe p LEFT JOIN pem.probe_config_table c ON (p.id = c.probe_id AND c.server_id = $2::integer AND c.database_name = $3::text AND c.schema_name = $4::text AND c.index_name = $5::text) WHERE p.id = $1::integer' USING v_pid, (((v_metric.params::pem.chart_metric_param[])[1]).value)::integer, (((v_metric.params::pem.chart_metric_param[])[2]).value)::text, (((v_metric.params::pem.chart_metric_param[])[3]).value)::text, (((v_metric.params::pem.chart_metric_param[])[4]).value)::text INTO v_freq;
				ELSE
					EXECUTE 'SELECT p.default_execution_frequency AS freq FROM pem.probe p WHERE p.id = $1::integer' USING v_pid INTO v_freq;
				END IF;
			WHEN 700 THEN
				IF array_length(v_metric.params::pem.chart_metric_param[], 1) >= 4 AND ((v_metric.params::pem.chart_metric_param[])[1]).name = 'server_id' AND ((v_metric.params::pem.chart_metric_param[])[1]).value IS NOT NULL AND
					((v_metric.params::pem.chart_metric_param[])[2]).name = 'database_name' AND ((v_metric.params::pem.chart_metric_param[])[2]).value IS NOT NULL AND
					((v_metric.params::pem.chart_metric_param[])[3]).name = 'schema_name' AND ((v_metric.params::pem.chart_metric_param[])[3]).value IS NOT NULL AND
					((v_metric.params::pem.chart_metric_param[])[4]).name = 'sequence_name' AND ((v_metric.params::pem.chart_metric_param[])[4]).value IS NOT NULL THEN
					EXECUTE 'SELECT COALESCE(c.execution_frequency, p.default_execution_frequency) AS freq FROM pem.probe p LEFT JOIN pem.probe_config_table c ON (p.id = c.probe_id AND c.server_id = $2::integer AND c.database_name = $3::text AND c.schema_name = $4::text AND c.sequence_name = $5::text) WHERE p.id = $1::integer' USING v_pid, (((v_metric.params::pem.chart_metric_param[])[1]).value)::integer, (((v_metric.params::pem.chart_metric_param[])[2]).value)::text, (((v_metric.params::pem.chart_metric_param[])[3]).value)::text, (((v_metric.params::pem.chart_metric_param[])[4]).value)::text INTO v_freq;
				ELSE
					EXECUTE 'SELECT p.default_execution_frequency AS freq FROM pem.probe p WHERE p.id = $1::integer' USING v_pid INTO v_freq;
				END IF;
			WHEN 800 THEN
				IF array_length(v_metric.params::pem.chart_metric_param[], 1) >= 4 AND ((v_metric.params::pem.chart_metric_param[])[1]).name = 'server_id' AND ((v_metric.params::pem.chart_metric_param[])[1]).value IS NOT NULL AND
					((v_metric.params::pem.chart_metric_param[])[2]).name = 'database_name' AND ((v_metric.params::pem.chart_metric_param[])[2]).value IS NOT NULL AND
					((v_metric.params::pem.chart_metric_param[])[3]).name = 'schema_name' AND ((v_metric.params::pem.chart_metric_param[])[3]).value IS NOT NULL AND
					((v_metric.params::pem.chart_metric_param[])[4]).name = 'function_name' AND ((v_metric.params::pem.chart_metric_param[])[4]).value IS NOT NULL THEN
					EXECUTE 'SELECT COALESCE(c.execution_frequency, p.default_execution_frequency) AS freq FROM pem.probe p LEFT JOIN pem.probe_config_table c ON (p.id = c.probe_id AND c.server_id = $2::integer AND c.database_name = $3::text AND c.schema_name = $4::text AND c.function_name = $5::text) WHERE p.id = $1::integer' USING v_pid, (((v_metric.params::pem.chart_metric_param[])[1]).value)::integer, (((v_metric.params::pem.chart_metric_param[])[2]).value)::text, (((v_metric.params::pem.chart_metric_param[])[3]).value)::text, (((v_metric.params::pem.chart_metric_param[])[4]).value)::text INTO v_freq;
				ELSE
					EXECUTE 'SELECT p.default_execution_frequency AS freq FROM pem.probe p WHERE p.id = $1::integer' USING v_pid INTO v_freq;
				END IF;
			WHEN 900 THEN
				IF array_length(v_metric.params::pem.chart_metric_param[], 1) >= 4 AND ((v_metric.params::pem.chart_metric_param[])[1]).name = 'server_id' AND ((v_metric.params::pem.chart_metric_param[])[1]).value IS NOT NULL AND
					((v_metric.params::pem.chart_metric_param[])[2]).name = 'database_name' AND ((v_metric.params::pem.chart_metric_param[])[2]).value IS NOT NULL AND
					((v_metric.params::pem.chart_metric_param[])[3]).name = 'schema_name' AND ((v_metric.params::pem.chart_metric_param[])[3]).value IS NOT NULL AND
					((v_metric.params::pem.chart_metric_param[])[4]).name = 'view_name' AND ((v_metric.params::pem.chart_metric_param[])[4]).value IS NOT NULL THEN
					EXECUTE 'SELECT COALESCE(c.execution_frequency, p.default_execution_frequency) AS freq FROM pem.probe p LEFT JOIN pem.probe_config_table c ON (p.id = c.probe_id AND c.server_id = $2::integer AND c.database_name = $3::text AND c.schema_name = $4::text AND c.view_name = $5::text) WHERE p.id = $1::integer' USING v_pid, (((v_metric.params::pem.chart_metric_param[])[1]).value)::integer, (((v_metric.params::pem.chart_metric_param[])[2]).value)::text, (((v_metric.params::pem.chart_metric_param[])[3]).value)::text, (((v_metric.params::pem.chart_metric_param[])[4]).value)::text INTO v_freq;
				ELSE
					EXECUTE 'SELECT p.default_execution_frequency AS freq FROM pem.probe p WHERE p.id = $1::integer' USING v_pid INTO v_freq;
				END IF;
			WHEN 1000 THEN
				IF array_length(v_metric.params::pem.chart_metric_param[], 1) >= 2 AND ((v_metric.params::pem.chart_metric_param[])[1]).name = 'server_id' AND ((v_metric.params::pem.chart_metric_param[])[1]).value IS NOT NULL AND
					((v_metric.params::pem.chart_metric_param[])[2]).name = 'database_name' AND ((v_metric.params::pem.chart_metric_param[])[2]).value IS NOT NULL THEN
					EXECUTE 'SELECT COALESCE(c.execution_frequency, p.default_execution_frequency) AS freq FROM pem.probe p LEFT JOIN pem.probe_config_extension c ON (p.id = c.probe_id AND c.server_id = $2::integer AND c.database_name = $3::text) WHERE p.id = $1::integer' USING v_pid, (((v_metric.params::pem.chart_metric_param[])[1]).value)::integer, (((v_metric.params::pem.chart_metric_param[])[2]).value)::text INTO v_freq;
				ELSE
					EXECUTE 'SELECT p.default_execution_frequency AS freq FROM pem.probe p WHERE p.id = $1::integer' USING v_pid INTO v_freq;
				END IF;
			ELSE
				EXECUTE 'SELECT p.default_execution_frequency AS freq FROM pem.probe p WHERE p.id = $1::integer' USING v_pid INTO v_freq;
			END CASE;
			IF v_minfreq IS NULL THEN
				v_minfreq := v_freq;
			ELSIF v_minfreq > v_freq THEN
				v_minfreq := v_freq;
			END IF;
			v_pos := v_pos + 1;

			SELECT string_agg(CASE WHEN (param).name = 'agent_id' THEN (SELECT description FROM pem.agent WHERE id = (param).value::int4) WHEN (param).name = 'server_id' THEN (SELECT description FROM pem.server WHERE id = (param).value::int4) ELSE (param).value END, '/'), string_agg(pg_catalog.quote_ident((param).name) || ' = ' || pg_catalog.quote_literal((param).value), ' AND '), string_agg(pg_catalog.quote_ident((param).name), ', ') FROM (SELECT unnest(v_metric.params::pem.chart_metric_param[]) AS param) p INTO v_t_str, v_where, v_groupon;

			EXECUTE E'
SELECT
	(CASE WHEN NOT pit_by_default THEN display_name || ''+'' ELSE display_name END), unit_of_value = ''%''::text
FROM pem.probe_column
WHERE probe_id = $1::int4 AND internal_name = $2::text AND is_graphable
UNION ALL
SELECT
	display_name, unit_of_value = ''%''::text
FROM pem.probe_column
WHERE probe_id = $1::int4 AND (internal_name || ''_pit'') = $2::text AND is_graphable AND NOT pit_by_default AND calculate_pit'
				USING v_pid, v_metric.metrices[1] INTO v_mlbl, v_percent_unit;
			v_mlbl := v_mlbl || ' [' || v_t_str || ']';

			EXECUTE 'SELECT min(t) FROM ((SELECT min(recorded_time) t FROM pemhistory.' || pg_catalog.quote_ident(v_metric.tbl) || ' WHERE ' || v_where || ' AND recorded_time >= $1::timestamptz) UNION ALL (SELECT max(recorded_time) t FROM pemhistory.' || pg_catalog.quote_ident(v_metric.tbl) || ' WHERE ' || v_where || ' AND recorded_time <= $1::timestamptz)) a' USING v_s_time INTO v_m_s_time;
			IF v_m_s_time < v_t_time THEN
				v_t_time := v_m_s_time;
			END IF;

			-- pos, label, probe_tbl, probe_col, agg, condition, groupon, percentage_unit, freq, min_time
			IF v_e_id IS NOT NULL AND v_e_id = v_metric.mid THEN
				v_t_op := ARRAY[v_pos::text, v_mlbl, v_metric.tbl, v_metric.metrices[1]::text, v_metric.agg_func[1]::text, v_where, v_groupon, v_percent_unit::text, v_freq::text, v_m_s_time::text];
			ELSE
				v_m_ops := v_m_ops || ARRAY[ARRAY[v_pos::text, v_mlbl, v_metric.tbl, v_metric.metrices[1]::text, v_metric.agg_func[1]::text, v_where, v_groupon, v_percent_unit::text, v_freq::text, v_m_s_time::text]];
			END IF;
		ELSE

			-- If server is remotely monitored then we will not render agent level metrics
			IF v_r_monitored AND v_target = 100 THEN
				o_idx := -1;
				o_aggval := NULL;
				o_aggtime := NULL;
				o_label :=  '114'::text;
				RETURN NEXT;

				CONTINUE;
			END IF;

			-- We need to find out, if this metric actually generates multiple
			-- sub-metrices (because they may have other primary keys too)
			IF p_level > 0 AND v_keys IS NOT NULL AND array_length(v_keys, 1) <> 0 THEN

				v_qry := 'SELECT ARRAY[';

				SELECT string_agg('tbl.' || pg_catalog.quote_ident(v_keys[a]), '::text, ')
					FROM generate_series(array_lower(v_keys,1), array_upper(v_keys,1)) a INTO v_t_str;
				v_qry := v_qry || v_t_str || '::text]::text[] FROM pemdata.' || pg_catalog.quote_ident(v_metric.tbl) || ' tbl';

				v_m_rest_dbs = NULL;
				CASE WHEN v_applies = 100 THEN
						v_qry := v_qry || ' WHERE tbl.agent_id = ' || p_aid::text || '::integer';
						v__params := ARRAY['agent_id'];
						v__vals := ARRAY[p_aid::text];

					WHEN v_target = 200 THEN
						v_qry := v_qry || ' WHERE tbl.server_id = ' || p_sid::text || '::integer';
						v__params := ARRAY['server_id'];
						v__vals := ARRAY[p_sid::text]::text[];
						IF v_applies >= 300 AND p_level >= 300 AND v_applies != 1000 AND p_level != 1000 THEN
							-- Restricted DBs are availabe that doesn't mean - they're applicable
							-- for this metric
							--
							-- Thye're applicable only if probe can applies to database level and
							-- current dashboard is for server-level
							IF array_length(v_rest_dbs, 1) <> 0 THEN
								v_m_rest_dbs = v_rest_dbs;
							ELSE
								v_m_rest_dbs := NULL;
							END IF;

							v_qry := v_qry || ' AND tbl.database_name = ' || pg_catalog.quote_literal(p_db::text) || '::text';
							v__params := ARRAY['server_id', 'database_name'];
							v__vals := ARRAY[p_sid::text, p_db];
						END IF;
						IF v_applies >= 400 AND p_level = 400 AND v_applies != 1000 AND p_level != 1000 THEN
							v__params := ARRAY['server_id', 'database_name', 'schema_name'];
							v__vals := ARRAY[p_sid::text, p_db, p_schema];
							v_qry := v_qry || ' AND tbl.schema_name = ' || pg_catalog.quote_literal(p_schema::text) || '::text';
						END IF;
						IF NOT p_sysobjs THEN
							IF v_applies = 300 THEN
								v_qry := v_qry || ' AND CASE WHEN database_name != '''' THEN database_name != ''template0'' AND database_name != ''template1'' ELSE TRUE END';
							ELSIF v_applies > 300 THEN
								v_qry := v_qry || E' AND CASE WHEN database_name != '''' THEN database_name != ''template0'' AND database_name != ''template1'' AND schema_name NOT IN (''pg_catalog'', ''sys'', ''information_schema'') AND schema_name NOT LIKE ''pg_toast%'' AND schema_name NOT LIKE ''pg_temp%'' ELSE TRUE END';

								v_qry := v_qry || ' AND CASE WHEN database_name != '''' THEN database_name != ''template0'' AND database_name != ''template1'' ELSE TRUE END';
							END IF;
						END IF;
						IF v_applies = 300 THEN
							IF v_rest_dbs IS NOT NULL AND array_length(v_rest_dbs, 1) > 0 THEN
								v_qry := v_qry || ' AND database_name = ANY(' || pg_catalog.quote_literal(v_rest_dbs::text) || ')';
							END IF;
						ELSIF v_applies > 300 THEN
							IF v_rest_dbs IS NOT NULL AND array_length(v_rest_dbs, 1) > 0 THEN
								v_qry := v_qry || ' AND database_name = ANY(' || pg_catalog.quote_literal(v_rest_dbs::text) || ') AND schema_name = ANY(
	SELECT
		COALESCE(o.schema_restriction, oa.schema_restriction)
	FROM
		pem.server s
		LEFT OUTER JOIN pg_catalog.pg_roles owner ON (owner.oid = s.owner)
		LEFT OUTER JOIN pem.database_option o ON (s.id = o.server_id AND o.pem_user = current_user AND o.database = tbl.database_name)
		LEFT OUTER JOIN pem.database_option oa
			ON (o.id IS NULL AND s.id = oa.server_id AND oa.database = tbl.database_name AND
				(owner.rolname = oa.pem_user OR (owner.rolname IS NULL AND oa.pem_user IS NULL)))
	WHERE
		s.id = tbl.server_id)';
							END IF;
							IF p_level = 400 THEN
								v_qry := v_qry || ' AND schema_name = ' || pg_catalog.quote_literal(p_schema::text) || '::text';
							END IF;
						END IF;
					WHEN v_target = 300 THEN
						v_qry := v_qry || ' WHERE tbl.server_id = ' || p_sid::text || '::integer AND tbl.database_name = ' || pg_catalog.quote_literal(p_db::text) || '::text';
						v__params := ARRAY['server_id', 'database_name'];
						v__vals := ARRAY[p_sid::text, p_db]::text[];

						IF array_length(v_rest_dbs, 1) <> 0 THEN
							v_m_rest_dbs = v_rest_dbs;
						ELSE
							v_m_rest_dbs := NULL;
						END IF;
						IF v_applies > 300  THEN
							IF p_level > 300 THEN
								v__params := ARRAY['server_id', 'database_name', 'schema_name'];
								v__vals := ARRAY[p_sid::text, p_db, p_schema];
							END IF;
							IF NOT p_sysobjs THEN
								v_qry := v_qry || E' AND (schema_name NOT IN (''pg_catalog'', ''sys'', ''information_schema'') AND schema_name NOT LIKE ''pg_toast%'' AND schema_name NOT LIKE ''pg_temp%'')';
							END IF;
							IF v_rest_schemas IS NOT NULL AND array_length(v_rest_schemas, 1) > 0 THEN
								v_qry := v_qry || ' AND schema_name = ANY(' || pg_catalog.quote_literal(v_rest_schemas::text) || ')';
							END IF;
						END IF;
					WHEN v_target = 400 THEN
						v__params := ARRAY['server_id', 'database_name', 'schema_name'];
						v__vals := ARRAY[p_sid::text, p_db, p_schema];
						v_qry := v_qry || ' WHERE tbl.server_id = ' || p_sid::text || '::integer AND tbl.database_name = ' || pg_catalog.quote_literal(p_db::text) || '::text AND tbl.schema_name = ' || pg_catalog.quote_literal(schema::text) || '::text';
					WHEN v_target = 1000 THEN
						v_qry := v_qry || ' WHERE tbl.server_id = ' || p_sid::text || '::integer';
						v__params := ARRAY['server_id'];
						v__vals := ARRAY[p_sid::text]::text[];
					ELSE
						v_qry := v_qry;
				END CASE;

				IF v_metric.gorderby IS NOT NULL AND array_length(v_metric.gorderby, 1) >0 THEN
					SELECT string_agg('tbl.' || pg_catalog.quote_ident(v_metric.gorderby[i]) || CASE WHEN v_metric.gorderdir IS NOT NULL AND array_length(v_metric.gorderdir, 1) >= i AND v_metric.gorderdir[i] = 'D' THEN ' DESC' ELSE ' ASC' END, ', ')
						FROM generate_series(array_lower(v_metric.gorderby,1), array_upper(v_metric.gorderby,1)) i INTO v_t_str;
					v_qry := v_qry || ' ORDER BY ' || v_t_str;
				END IF;
				IF (v_metric.glimit IS NOT NULL AND v_metric.glimit > 0) THEN
					v_qry := v_qry || ' LIMIT ' || v_metric.glimit::text;
				ELSE
					v_qry := v_qry || ' LIMIT 32';
				END IF;

				IF v_metric.glimit IS NULL OR v_metric.glimit <> 0 THEN
					OPEN v_gcurs FOR EXECUTE v_qry;
					LOOP
						FETCH v_gcurs INTO v_key_vals;
						EXIT WHEN NOT FOUND;
						v_params := v__params;
						v_vals := v__vals;

						FOR a IN array_lower(v_key_vals, 1) .. array_upper(v_key_vals, 1)
						LOOP
							v_params := v_params || v_keys[a]::text;
							v_vals := v_vals || v_key_vals[a]::text;
						END LOOP;

						v_freq := NULL;
						CASE v_target
						WHEN 100 THEN
							IF array_length(v_params, 1) >= 1 AND v_params[1] = 'agent_id' AND v_vals[1] IS NOT NULL THEN
								EXECUTE 'SELECT COALESCE(c.execution_frequency, p.default_execution_frequency) AS freq FROM pem.probe p LEFT JOIN pem.probe_config_agent c ON (p.id = c.probe_id AND c.agent_id = $2::integer) WHERE p.id = $1::integer' USING v_pid, (v_vals[1])::integer INTO v_freq;
							END IF;
						WHEN 200 THEN
						    IF v_applies = 1000  THEN
                                IF array_length(v_params, 1) >= 1 AND v_params[1] = 'server_id' AND v_vals[1] IS NOT NULL THEN
                                    EXECUTE 'SELECT COALESCE(c.execution_frequency, p.default_execution_frequency) AS freq FROM pem.probe p LEFT JOIN pem.probe_config_server c ON (p.id = c.probe_id AND c.server_id = $2::integer) WHERE p.id = $1::integer' USING v_pid, (v_vals[1])::integer INTO v_freq;
                                END IF;
						    ELSE
                                IF array_length(v_params, 1) >= 1 AND v_params[1] = 'server_id' AND v_vals[1] IS NOT NULL THEN
                                    EXECUTE 'SELECT COALESCE(c.execution_frequency, p.default_execution_frequency) AS freq FROM pem.probe p LEFT JOIN pem.probe_config_server c ON (p.id = c.probe_id AND c.server_id = $2::integer) WHERE p.id = $1::integer' USING v_pid, (v_vals[1])::integer INTO v_freq;
                                END IF;
                            END IF;
						WHEN 300 THEN
							IF array_length(v_params, 1) >= 2 AND v_params[1] = 'server_id' AND v_vals[1] IS NOT NULL AND
								((v_params)[2]).name = 'database_name' AND v_vals[2] IS NOT NULL THEN
								EXECUTE 'SELECT COALESCE(c.execution_frequency, p.default_execution_frequency) AS freq FROM pem.probe p LEFT JOIN pem.probe_config_database c ON (p.id = c.probe_id AND c.server_id = $2::integer AND c.database_name = $3::text) WHERE p.id = $1::integer' USING v_pid, (v_vals[1])::integer, (v_vals[2])::text INTO v_freq;
							END IF;
						WHEN 400 THEN
							IF array_length(v_params, 1) >= 3 AND v_params[1] = 'server_id' AND v_vals[1] IS NOT NULL AND
								((v_params)[2]).name = 'database_name' AND v_vals[2] IS NOT NULL AND
								((v_params)[3]).name = 'schema_name' AND v_vals[3] IS NOT NULL THEN
								EXECUTE 'SELECT COALESCE(c.execution_frequency, p.default_execution_frequency) AS freq FROM pem.probe p LEFT JOIN pem.probe_config_schema c ON (p.id = c.probe_id AND c.server_id = $2::integer AND c.database_name = $3::text AND c.schema_name = $4::text) WHERE p.id = $1::integer' USING v_pid, (v_vals[1])::integer, (v_vals[2])::text, (v_vals[3])::text INTO v_freq;
							END IF;
						WHEN 500 THEN
							IF array_length(v_params, 1) >= 4 AND v_params[1] = 'server_id' AND v_vals[1] IS NOT NULL AND
								((v_params)[2]).name = 'database_name' AND v_vals[2] IS NOT NULL AND
								((v_params)[3]).name = 'schema_name' AND v_vals[3] IS NOT NULL AND
								((v_params)[4]).name = 'table_name' AND v_vals[4] IS NOT NULL THEN
								EXECUTE 'SELECT COALESCE(c.execution_frequency, p.default_execution_frequency) AS freq FROM pem.probe p LEFT JOIN pem.probe_config_table c ON (p.id = c.probe_id AND c.server_id = $2::integer AND c.database_name = $3::text AND c.schema_name = $4::text AND c.table_name = $5::text) WHERE p.id = $1::integer' USING v_pid, (v_vals[1])::integer, (v_vals[2])::text, (v_vals[3])::text, (v_vals[4])::text INTO v_freq;
							END IF;
						WHEN 600 THEN
							IF array_length(v_params, 1) >= 4 AND v_params[1] = 'server_id' AND v_vals[1] IS NOT NULL AND
								((v_params)[2]).name = 'database_name' AND v_vals[2] IS NOT NULL AND
								((v_params)[3]).name = 'schema_name' AND v_vals[3] IS NOT NULL AND
								((v_params)[4]).name = 'index_name' AND v_vals[4] IS NOT NULL THEN
								EXECUTE 'SELECT COALESCE(c.execution_frequency, p.default_execution_frequency) AS freq FROM pem.probe p LEFT JOIN pem.probe_config_index c ON (p.id = c.probe_id AND c.server_id = $2::integer AND c.database_name = $3::text AND c.schema_name = $4::text AND c.index_name = $5::text) WHERE p.id = $1::integer' USING v_pid, (v_vals[1])::integer, (v_vals[2])::text, (v_vals[3])::text, (v_vals[4])::text INTO v_freq;
							END IF;
						WHEN 700 THEN
							IF array_length(v_params, 1) >= 4 AND v_params[1] = 'server_id' AND v_vals[1] IS NOT NULL AND
								((v_params)[2]).name = 'database_name' AND v_vals[2] IS NOT NULL AND
								((v_params)[3]).name = 'schema_name' AND v_vals[3] IS NOT NULL AND
								((v_params)[4]).name = 'sequence_name' AND v_vals[4] IS NOT NULL THEN
								EXECUTE 'SELECT COALESCE(c.execution_frequency, p.default_execution_frequency) AS freq FROM pem.probe p LEFT JOIN pem.probe_config_sequence  c ON (p.id = c.probe_id AND c.server_id = $2::integer AND c.database_name = $3::text AND c.schema_name = $4::text AND c.sequence_name = $5::text) WHERE p.id = $1::integer' USING v_pid, (v_vals[1])::integer, (v_vals[2])::text, (v_vals[3])::text, (v_vals[4])::text INTO v_freq;
							END IF;
						WHEN 800 THEN
							IF array_length(v_params, 1) >= 4 AND v_params[1] = 'server_id' AND v_vals[1] IS NOT NULL AND
								((v_params)[2]).name = 'database_name' AND v_vals[2] IS NOT NULL AND
								((v_params)[3]).name = 'schema_name' AND v_vals[3] IS NOT NULL AND
								((v_params)[4]).name = 'function_name' AND v_vals[4] IS NOT NULL THEN
								EXECUTE 'SELECT COALESCE(c.execution_frequency, p.default_execution_frequency) AS freq FROM pem.probe p LEFT JOIN pem.probe_config_function c ON (p.id = c.probe_id AND c.server_id = $2::integer AND c.database_name = $3::text AND c.schema_name = $4::text AND c.function_name = $5::text) WHERE p.id = $1::integer' USING v_pid, (v_vals[1])::integer, (v_vals[2])::text, (v_vals[3])::text, (v_vals[4])::text INTO v_freq;
							END IF;
						WHEN 900 THEN
							IF array_length(v_params, 1) >= 4 AND v_params[1] = 'server_id' AND v_vals[1] IS NOT NULL AND
								((v_params)[2]).name = 'database_name' AND v_vals[2] IS NOT NULL AND
								((v_params)[3]).name = 'schema_name' AND v_vals[3] IS NOT NULL AND
								((v_params)[4]).name = 'view_name' AND v_vals[4] IS NOT NULL THEN
								EXECUTE 'SELECT COALESCE(c.execution_frequency, p.default_execution_frequency) AS freq FROM pem.probe p LEFT JOIN pem.probe_config_view c ON (p.id = c.probe_id AND c.server_id = $2::integer AND c.database_name = $3::text AND c.schema_name = $4::text AND c.view_name = $5::text) WHERE p.id = $1::integer' USING v_pid, (v_vals[1])::integer, (v_vals[2])::text, (v_vals[3])::text, (v_vals[4])::text INTO v_freq;
							END IF;
						WHEN 1000 THEN
							IF array_length(v_params, 1) >= 1 AND v_params[1] = 'server_id' AND v_vals[1] IS NOT NULL THEN
								EXECUTE 'SELECT COALESCE(c.execution_frequency, p.default_execution_frequency) AS freq FROM pem.probe p LEFT JOIN pem.probe_config_server c ON (p.id = c.probe_id AND c.server_id = $2::integer) WHERE p.id = $1::integer' USING v_pid, (v_vals[1])::integer INTO v_freq;
							END IF;
						END CASE;
						IF v_freq IS NULL THEN
							EXECUTE 'SELECT p.default_execution_frequency AS freq FROM pem.probe p WHERE p.id = $1::integer' USING v_pid INTO v_freq;
						END IF;
						IF v_minfreq IS NULL THEN
							v_minfreq := v_freq;
						ELSIF v_minfreq > v_freq THEN
							v_minfreq := v_freq;
						END IF;

						FOR m_idx IN array_lower(v_metric.metrices, 1) .. array_upper(v_metric.metrices, 1)
							LOOP
								v_pos := v_pos + 1;
								SELECT string_agg(v_key_vals[b], ', ')
								FROM generate_series(array_lower(v_key_vals,1), array_upper(v_key_vals,1)) b INTO o_label;
								EXECUTE E'
		SELECT
			(CASE WHEN NOT pit_by_default THEN display_name || ''+'' ELSE display_name END), sql_data_type, unit_of_value = ''%''::text
		FROM pem.probe_column
		WHERE probe_id = $1::int4 AND internal_name = $2::text AND is_graphable
		UNION ALL
		SELECT
			display_name, sql_data_type, unit_of_value = ''%''::text
		FROM pem.probe_column
		WHERE probe_id = $1::int4 AND (internal_name || ''_pit'') = $2::text AND is_graphable AND NOT pit_by_default AND calculate_pit'
							USING v_pid, v_metric.metrices[m_idx] INTO v_mlbl, v_ptype, v_percent_unit;

							IF v_chart.labels IS NOT NULL AND array_length(v_chart.labels, 1) >= v_pos AND v_chart.labels[v_pos] IS NOT NULL THEN
								o_label := v_chart.labels[v_pos] || ' - ' || o_label;
							ELSE
								IF v_mlbl IS NOT NULL THEN
									o_label := v_mlbl || ' - ' || o_label;
								END IF;
							END IF;
							IF v_metric.agg_func IS NOT NULL AND array_length(v_metric.agg_func, 1) >= m_idx AND v_metric.agg_func[m_idx] IS NOT NULL THEN
								v_t_str := v_metric.agg_func[m_idx];
							END IF;

							SELECT string_agg(pg_catalog.quote_ident(v_params[idx]) || ' = ' || pg_catalog.quote_literal(v_vals[idx]), ' AND '), string_agg(pg_catalog.quote_ident(v_params[idx]), ', ') FROM generate_series(array_lower(v_params,1), array_upper(v_params,1)) idx INTO v_where, v_groupon;
							EXECUTE 'SELECT min(t) FROM ((SELECT min(recorded_time) t FROM pemhistory.' || pg_catalog.quote_ident(v_metric.tbl) || ' WHERE ' || v_where || ' AND recorded_time >= $1::timestamptz) UNION ALL (SELECT max(recorded_time) t FROM pemhistory.' || pg_catalog.quote_ident(v_metric.tbl) || ' WHERE ' || v_where || ' AND recorded_time <= $1::timestamptz)) a' USING v_s_time INTO v_m_s_time;
							IF v_m_s_time < v_t_time THEN
								v_t_time := v_m_s_time;
							END IF;

							-- pos, label, probe_tbl, probe_col, agg, condition, groupon, percentage_unit, freq, min_time
							IF v_e_id IS NOT NULL AND v_e_id = v_metric.mid THEN
								v_t_op := ARRAY[v_pos::text, o_label, v_metric.tbl, v_metric.metrices[m_idx]::text, v_t_str, v_where, v_groupon, v_percent_unit::text, v_freq::text, v_m_s_time::text];
							ELSE
								v_m_ops := v_m_ops || ARRAY[ARRAY[v_pos::text, o_label, v_metric.tbl, v_metric.metrices[m_idx]::text, v_t_str, v_where, v_groupon, v_percent_unit::text, v_freq::text, v_m_s_time::text]];
							END IF;
						END LOOP;
					END LOOP;
					CLOSE v_gcurs;
				ELSE
					FOR m_idx IN array_lower(v_metric.metrices, 1) .. array_upper(v_metric.metrices, 1)
					LOOP
						v_pos := v_pos + 1;
						EXECUTE E'
	SELECT
		(CASE WHEN NOT pit_by_default THEN display_name || ''+'' ELSE display_name END), unit_of_value = ''%''::text
	FROM pem.probe_column
	WHERE probe_id = $1::int4 AND internal_name = $2::text AND is_graphable
	UNION ALL
	SELECT
		display_name, unit_of_value = ''%''::text
	FROM pem.probe_column
	WHERE probe_id = $1::int4 AND (internal_name || ''_pit'') = $2::text AND is_graphable AND NOT pit_by_default AND calculate_pit'
	USING v_pid, v_metric.metrices[m_idx] INTO v_mlbl, v_percent_unit;

						IF v_chart.labels IS NOT NULL AND array_length(v_chart.labels, 1) >= v_pos AND v_chart.labels[v_pos] IS NOT NULL THEN
							o_label := v_chart.labels[v_pos];
						ELSE
							IF v_mlbl IS NOT NULL THEN
								o_label := v_mlbl;
							END IF;
						END IF;

						IF v_metric.agg_func IS NOT NULL AND array_length(v_metric.agg_func, 1) >= m_idx AND v_metric.agg_func[m_idx] IS NOT NULL THEN
							v_t_str := v_metric.agg_func[m_idx];
						END IF;

						v_freq := NULL;
						CASE v_target
						WHEN 100 THEN
							IF array_length(v__params, 1) >= 1 AND v__params[1] = 'agent_id' AND v__vals[1] IS NOT NULL THEN
								EXECUTE 'SELECT COALESCE(c.execution_frequency, p.default_execution_frequency) AS freq FROM pem.probe p LEFT JOIN pem.probe_config_agent c ON (p.id = c.probe_id AND c.agent_id = $2::integer) WHERE p.id = $1::integer' USING v_pid, (v__vals[1])::integer INTO v_freq;
							END IF;
						WHEN 200 THEN
						    IF v_applies = 1000  THEN
                                IF array_length(v__params, 1) >= 2 AND v__params[1] = 'server_id' AND v__vals[1] IS NOT NULL AND
                                    ((v__params)[2]).name = 'database_name' AND v__vals[2] IS NOT NULL THEN
                                    EXECUTE 'SELECT COALESCE(c.execution_frequency, p.default_execution_frequency) AS freq FROM pem.probe p LEFT JOIN pem.probe_config_extension c ON (p.id = c.probe_id AND c.server_id = $2::integer AND c.database_name = $3::text) WHERE p.id = $1::integer' USING v_pid, (v__vals[1])::integer, (v__vals[2])::text INTO v_freq;
                                END IF;
                            ELSE
                                IF array_length(v__params, 1) >= 1 AND v__params[1] = 'server_id' AND v__vals[1] IS NOT NULL THEN
                                    EXECUTE 'SELECT COALESCE(c.execution_frequency, p.default_execution_frequency) AS freq FROM pem.probe p LEFT JOIN pem.probe_config_server c ON (p.id = c.probe_id AND c.server_id = $2::integer) WHERE p.id = $1::integer' USING v_pid, (v__vals[1])::integer INTO v_freq;
                                END IF;
                            END IF;
						WHEN 300 THEN
							IF array_length(v__params, 1) >= 2 AND v__params[1] = 'server_id' AND v__vals[1] IS NOT NULL AND
								((v__params)[2]).name = 'database_name' AND v__vals[2] IS NOT NULL THEN
								EXECUTE 'SELECT COALESCE(c.execution_frequency, p.default_execution_frequency) AS freq FROM pem.probe p LEFT JOIN pem.probe_config_database c ON (p.id = c.probe_id AND c.server_id = $2::integer AND c.database_name = $3::text) WHERE p.id = $1::integer' USING v_pid, (v__vals[1])::integer, (v__vals[2])::text INTO v_freq;
							END IF;
						WHEN 400 THEN
							IF array_length(v__params, 1) >= 3 AND v__params[1] = 'server_id' AND v__vals[1] IS NOT NULL AND
								((v__params)[2]).name = 'database_name' AND v__vals[2] IS NOT NULL AND
								((v__params)[3]).name = 'schema_name' AND v__vals[3] IS NOT NULL THEN
								EXECUTE 'SELECT COALESCE(c.execution_frequency, p.default_execution_frequency) AS freq FROM pem.probe p LEFT JOIN pem.probe_config_schema c ON (p.id = c.probe_id AND c.server_id = $2::integer AND c.database_name = $3::text AND c.schema_name = $4::text) WHERE p.id = $1::integer' USING v_pid, (v__vals[1])::integer, (v__vals[2])::text, (v__vals[3])::text INTO v_freq;
							END IF;
						WHEN 500 THEN
							IF array_length(v__params, 1) >= 4 AND v__params[1] = 'server_id' AND v__vals[1] IS NOT NULL AND
								((v__params)[2]).name = 'database_name' AND v__vals[2] IS NOT NULL AND
								((v__params)[3]).name = 'schema_name' AND v__vals[3] IS NOT NULL AND
								((v__params)[4]).name = 'table_name' AND v__vals[4] IS NOT NULL THEN
								EXECUTE 'SELECT COALESCE(c.execution_frequency, p.default_execution_frequency) AS freq FROM pem.probe p LEFT JOIN pem.probe_config_table c ON (p.id = c.probe_id AND c.server_id = $2::integer AND c.database_name = $3::text AND c.schema_name = $4::text AND c.table_name = $5::text) WHERE p.id = $1::integer' USING v_pid, (v__vals[1])::integer, (v__vals[2])::text, (v__vals[3])::text, (v__vals[4])::text INTO v_freq;
							END IF;
						WHEN 600 THEN
							IF array_length(v__params, 1) >= 4 AND v__params[1] = 'server_id' AND v__vals[1] IS NOT NULL AND
								((v__params)[2]).name = 'database_name' AND v__vals[2] IS NOT NULL AND
								((v__params)[3]).name = 'schema_name' AND v__vals[3] IS NOT NULL AND
								((v__params)[4]).name = 'index_name' AND v__vals[4] IS NOT NULL THEN
								EXECUTE 'SELECT COALESCE(c.execution_frequency, p.default_execution_frequency) AS freq FROM pem.probe p LEFT JOIN pem.probe_config_index c ON (p.id = c.probe_id AND c.server_id = $2::integer AND c.database_name = $3::text AND c.schema_name = $4::text AND c.index_name = $5::text) WHERE p.id = $1::integer' USING v_pid, (v__vals[1])::integer, (v__vals[2])::text, (v__vals[3])::text, (v__vals[4])::text INTO v_freq;
							END IF;
						WHEN 700 THEN
							IF array_length(v__params, 1) >= 4 AND v__params[1] = 'server_id' AND v__vals[1] IS NOT NULL AND
								((v__params)[2]).name = 'database_name' AND v__vals[2] IS NOT NULL AND
								((v__params)[3]).name = 'schema_name' AND v__vals[3] IS NOT NULL AND
								((v__params)[4]).name = 'sequence_name' AND v__vals[4] IS NOT NULL THEN
								EXECUTE 'SELECT COALESCE(c.execution_frequency, p.default_execution_frequency) AS freq FROM pem.probe p LEFT JOIN pem.probe_config_sequence  c ON (p.id = c.probe_id AND c.server_id = $2::integer AND c.database_name = $3::text AND c.schema_name = $4::text AND c.sequence_name = $5::text) WHERE p.id = $1::integer' USING v_pid, (v__vals[1])::integer, (v__vals[2])::text, (v__vals[3])::text, (v__vals[4])::text INTO v_freq;
							END IF;
						WHEN 800 THEN
							IF array_length(v__params, 1) >= 4 AND v__params[1] = 'server_id' AND v__vals[1] IS NOT NULL AND
								((v__params)[2]).name = 'database_name' AND v__vals[2] IS NOT NULL AND
								((v__params)[3]).name = 'schema_name' AND v__vals[3] IS NOT NULL AND
								((v__params)[4]).name = 'function_name' AND v__vals[4] IS NOT NULL THEN
								EXECUTE 'SELECT COALESCE(c.execution_frequency, p.default_execution_frequency) AS freq FROM pem.probe p LEFT JOIN pem.probe_config_function c ON (p.id = c.probe_id AND c.server_id = $2::integer AND c.database_name = $3::text AND c.schema_name = $4::text AND c.function_name = $5::text) WHERE p.id = $1::integer' USING v_pid, (v__vals[1])::integer, (v__vals[2])::text, (v__vals[3])::text, (v__vals[4])::text INTO v_freq;
							END IF;
						WHEN 900 THEN
							IF array_length(v__params, 1) >= 4 AND v__params[1] = 'server_id' AND v__vals[1] IS NOT NULL AND
								((v__params)[2]).name = 'database_name' AND v__vals[2] IS NOT NULL AND
								((v__params)[3]).name = 'schema_name' AND v__vals[3] IS NOT NULL AND
								((v__params)[4]).name = 'view_name' AND v__vals[4] IS NOT NULL THEN
								EXECUTE 'SELECT COALESCE(c.execution_frequency, p.default_execution_frequency) AS freq FROM pem.probe p LEFT JOIN pem.probe_config_view c ON (p.id = c.probe_id AND c.server_id = $2::integer AND c.database_name = $3::text AND c.schema_name = $4::text AND c.view_name = $5::text) WHERE p.id = $1::integer' USING v_pid, (v__vals[1])::integer, (v__vals[2])::text, (v__vals[3])::text, (v__vals[4])::text INTO v_freq;
							END IF;
						WHEN 1000 THEN
							IF array_length(v__params, 1) >= 2 AND v__params[1] = 'server_id' AND v__vals[1] IS NOT NULL AND
								((v__params)[2]).name = 'database_name' AND v__vals[2] IS NOT NULL THEN
								EXECUTE 'SELECT COALESCE(c.execution_frequency, p.default_execution_frequency) AS freq FROM pem.probe p LEFT JOIN pem.probe_config_extension c ON (p.id = c.probe_id AND c.server_id = $2::integer AND c.database_name = $3::text) WHERE p.id = $1::integer' USING v_pid, (v__vals[1])::integer, (v__vals[2])::text INTO v_freq;
							END IF;
						END CASE;
						IF v_freq IS NULL THEN
							EXECUTE 'SELECT p.default_execution_frequency AS freq FROM pem.probe p WHERE p.id = $1::integer' USING v_pid INTO v_freq;
						END IF;
						IF v_minfreq IS NULL THEN
							v_minfreq := v_freq;
						ELSIF v_minfreq > v_freq THEN
							v_minfreq := v_freq;
						END IF;

						SELECT string_agg(pg_catalog.quote_ident(v__params[idx]) || ' = ' || pg_catalog.quote_literal(v__vals[idx]), ' AND '), string_agg(pg_catalog.quote_ident(v__params[idx]), ', ') FROM generate_series(array_lower(v__params,1), array_upper(v__params,1)) idx INTO v_where, v_groupon;
						EXECUTE 'SELECT min(t) FROM ((SELECT min(recorded_time) t FROM pemhistory.' || pg_catalog.quote_ident(v_metric.tbl) || ' WHERE ' || v_where || ' AND recorded_time >= $1::timestamptz) UNION ALL (SELECT max(recorded_time) t FROM pemhistory.' || pg_catalog.quote_ident(v_metric.tbl) || ' WHERE ' || v_where || ' AND recorded_time <= $1::timestamptz)) a' USING v_s_time INTO v_m_s_time;
						IF v_m_s_time < v_t_time THEN
							v_t_time := v_m_s_time;
						END IF;

						-- pos, label, probe_tbl, probe_col, agg, condition, groupon, percentage_unit, freq, min_time
						IF v_e_id IS NOT NULL AND v_e_id = v_metric.mid THEN
							v_t_op := ARRAY[v_pos::text, o_label, v_metric.tbl, v_metric.metrices[m_idx]::text, v_t_str, v_where, v_groupon, v_percent_unit::text, v_freq::text, v_m_s_time::text];
						ELSE
							v_m_ops := v_m_ops || ARRAY[ARRAY[v_pos::text, o_label, v_metric.tbl, v_metric.metrices[m_idx]::text, v_t_str, v_where, v_groupon, v_percent_unit::text, v_freq::text, v_m_s_time::text]];
						END IF;
					END LOOP;
				END IF;
			ELSE
				v_params := ARRAY[]::text[];
				v_vals := ARRAY[]::text[];
				v_m_rest_dbs := NULL;

				CASE WHEN v_applies = 100 THEN
						v_params := ARRAY['agent_id'];
						v_vals := ARRAY[p_aid::text];
					WHEN v_target = 200 THEN
						v_params := ARRAY['server_id'];
						v_vals := ARRAY[p_sid::text]::text[];

						IF v_applies >= 300 AND p_level >= 300 AND v_applies != 1000 THEN
							-- Restricted DBs are availabe that doesn't mean - they're applicable
							-- for this metric
							--
							-- Thye're applicable only if probe can applies to database level and
							-- current dashboard is for server-level
							IF array_length(v_rest_dbs, 1) <> 0 THEN
								v_m_rest_dbs = v_rest_dbs;
							ELSE
								v_m_rest_dbs := NULL;
							END IF;
						END IF;

						IF v_applies >= 400 AND p_level = 400 AND v_applies != 1000 AND p_level != 1000 THEN
							v_params := ARRAY['server_id', 'database_name', 'schema_name'];
							v_vals := ARRAY[p_sid::text, p_db, p_schema];
						ELSIF v_applies >= 300 AND p_level >= 300 THEN
							v_params := ARRAY['server_id', 'database_name'];
							v_vals := ARRAY[p_sid::text, p_db];
						END IF;
					WHEN v_target = 300 THEN
						v_params := ARRAY['server_id', 'database_name'];
						v_vals := ARRAY[p_sid::text, p_db]::text[];
						IF array_length(v_rest_dbs, 1) <> 0 THEN
							v_m_rest_dbs = v_rest_dbs;
						ELSE
							v_m_rest_dbs := NULL;
						END IF;
						IF v_applies > 300 AND v_applies != 1000  THEN
							IF p_level > 300 THEN
								v_params := ARRAY['server_id', 'database_name', 'schema_name'];
								v_vals := ARRAY[p_sid::text, p_db, p_schema];
							END IF;
						END IF;
					WHEN v_target = 400 THEN
						v_params := ARRAY['server_id', 'database_name', 'schema_name'];
						v_vals := ARRAY[p_sid::text, p_db, p_schema];
						-- TODO:: table level chart changes
					WHEN v_target = 1000 THEN
						v_params := ARRAY['server_id'];
						v_vals := ARRAY[p_sid::text]::text[];
				ELSE -- Do nothing
				END CASE;
				CASE WHEN v_metric.params IS NOT NULL THEN
					FOR i IN array_lower(v_metric.params, 1) .. array_upper(v_metric.params, 1)
					LOOP
						IF v_metric.params[i].name IS NOT NULL AND v_metric.params[i].name != '' THEN
							IF p_sid IS NOT NULL AND v_metric.params[i].name = 'server_id' THEN
								v_params := v_params || v_metric.params[i].name;
								v_vals := v_vals || p_sid::text;
							ELSIF p_aid IS NOT NULL AND v_metric.params[i].name = 'agent_id' THEN
								v_params := v_params || v_metric.params[i].name;
								v_vals := v_vals || p_aid::text;
							ELSIF p_db IS NOT NULL AND p_db <> '' AND v_metric.params[i].name = 'database_name' THEN
								v_params := v_params || v_metric.params[i].name;
								v_vals := v_vals || p_db::text;
							ELSIF p_schema IS NOT NULL AND p_schema <> '' AND v_metric.params[i].name = 'schema_name' THEN
								v_params := v_params || v_metric.params[i].name;
								v_vals := v_vals || p_schema::text;
							ELSE
								v_params := v_params || v_metric.params[i].name;
								v_vals := v_vals || v_metric.params[i].value;
							END IF;
						END IF;
					END LOOP;
				ELSE -- Do nothing
				END CASE;

				v_t_str := 'A';
				FOR m_idx IN array_lower(v_metric.metrices, 1) .. array_upper(v_metric.metrices, 1)
				LOOP
					v_pos := v_pos + 1;
					o_label := '';

					EXECUTE E'
	SELECT
		(CASE WHEN NOT pit_by_default THEN display_name || ''+'' ELSE display_name END), sql_data_type, unit_of_value = ''%''::text
	FROM pem.probe_column
	WHERE probe_id = $1::int4 AND internal_name = $2::text AND is_graphable
	UNION ALL
	SELECT
		display_name, sql_data_type, unit_of_value = ''%''::text
	FROM pem.probe_column
	WHERE probe_id = $1::int4 AND (internal_name || ''_pit'') = $2::text AND is_graphable AND NOT pit_by_default AND calculate_pit'
	USING v_pid, v_metric.metrices[m_idx] INTO v_mlbl, v_ptype, v_percent_unit;

					IF v_chart.labels IS NOT NULL AND array_length(v_chart.labels, 1) >= v_pos THEN
						o_label := v_chart.labels[v_pos];
					ELSE
						IF v_mlbl IS NOT NULL THEN
							o_label := v_mlbl;
						END IF;
					END IF;

					IF v_metric.agg_func IS NOT NULL AND array_length(v_metric.agg_func, 1) >= m_idx THEN
						v_t_str := v_metric.agg_func[m_idx];
					END IF;

					SELECT string_agg(pg_catalog.quote_ident(v_params[idx]) || ' = ' || pg_catalog.quote_literal(v_vals[idx]), ' AND '), string_agg(pg_catalog.quote_ident(v_params[idx]), ', ') FROM generate_series(array_lower(v_params,1), array_upper(v_params,1)) idx INTO v_where, v_groupon;
					EXECUTE 'SELECT min(t) FROM ((SELECT min(recorded_time) t FROM pemhistory.' || pg_catalog.quote_ident(v_metric.tbl) || ' WHERE ' || v_where || ' AND recorded_time >= $1::timestamptz) UNION ALL (SELECT max(recorded_time) t FROM pemhistory.' || pg_catalog.quote_ident(v_metric.tbl) || ' WHERE ' || v_where || ' AND recorded_time <= $1::timestamptz)) a' USING v_s_time INTO v_m_s_time;
					IF v_m_s_time < v_t_time THEN
						v_t_time := v_m_s_time;
					END IF;

					-- pos, label, probe_tbl, probe_col, agg, condition, groupon, percentage_unit, freq, min_time
					IF v_e_id IS NOT NULL AND v_e_id = v_metric.mid THEN
						v_t_op := ARRAY[v_pos::text, o_label, v_metric.tbl, v_metric.metrices[m_idx]::text, v_t_str, v_where, v_groupon, v_percent_unit::text, '10 seconds', v_m_s_time::text];
					ELSE
						v_m_ops := v_m_ops || ARRAY[ARRAY[v_pos::text, o_label, v_metric.tbl, v_metric.metrices[m_idx]::text, v_t_str, v_where, v_groupon, v_percent_unit::text, '10 seconds', v_m_s_time::text]];
					END IF;
				END LOOP;
			END IF;
		END IF;
	END LOOP;
	CLOSE v_mcurs;

	v_aggqry := ARRAY[
'WITH dtbl AS (
	SELECT
		floor(EXTRACT(EPOCH FROM (ph.recorded_time - $2::timestamptz)) / EXTRACT(EPOCH FROM $1::interval)) dn,
		row_number() OVER (ORDER BY ph.recorded_time) rn,
		ph.recorded_time rt, COALESCE(ph.@@COLUMN@@, 0) val
	FROM
		pemhistory.@@TABLE@@ ph
	WHERE @@CONDITION@@
		AND ph.recorded_time >= $3::timestamptz
		AND ph.recorded_time <= $4::timestamptz
)
SELECT
	$5::int2 o_idx, $6::text o_label,
	to_timestamp((dn * EXTRACT(EPOCH FROM $1::interval)) + EXTRACT(EPOCH FROM $2::timestamptz)) o_aggtime,
	val::numeric o_aggval
FROM (
	SELECT
		dn, val, row_number() OVER (PARTITION BY dn ORDER BY rt) pidx
	FROM (
		SELECT
			t1.val val,
			unnest(CASE WHEN ((t1.dn = t2.dn) OR (t1.dn < 0 AND t2.dn <= 0)) THEN ARRAY[t2.dn::bigint]
			WHEN t2.dn IS NULL AND t1.dn < 0 THEN ARRAY(SELECT g::bigint FROM generate_series(0, $7::bigint, 1) g)
			WHEN t2.dn IS NULL AND t1.dn <= $7::bigint THEN ARRAY(SELECT g FROM generate_series(t1.dn::bigint, $7::bigint, 1) g)
			WHEN t1.dn < 0 AND t2.dn > 0 THEN ARRAY(SELECT g FROM generate_series(0, (t2.dn - 1)::bigint, 1) g)
			ELSE ARRAY(SELECT g FROM generate_series(t1.dn::bigint, (t2.dn - 1)::bigint, 1) g)
			END) dn,
			t1.rt rt
		FROM
			dtbl t1
			LEFT JOIN dtbl t2 ON (t1.rn = t2.rn - 1)) t
		WHERE dn >= 0) tbl
WHERE pidx = 1 AND to_timestamp((dn * EXTRACT(EPOCH FROM $1::interval)) + EXTRACT(EPOCH FROM $2::timestamptz)) < ($4::timestamptz + ($1::interval / 5))
ORDER BY dn',
'WITH dtbl AS (
	SELECT
		floor(EXTRACT(EPOCH FROM (ph.recorded_time - $2::timestamptz)) / EXTRACT(EPOCH FROM $1::interval)) dn,
		row_number() OVER (ORDER BY ph.recorded_time) rn,
		COALESCE(ph.@@COLUMN@@, 0) val
	FROM
		pemhistory.@@TABLE@@ ph
	WHERE @@CONDITION@@
		AND ph.recorded_time >= $3::timestamptz
		AND ph.recorded_time <= $4::timestamptz
)
SELECT
	$5::int2 o_idx, $6::text o_label,
	to_timestamp((dn * EXTRACT(EPOCH FROM $1::interval)) + EXTRACT(EPOCH FROM $2::timestamptz)) o_aggtime,
	max(val)::numeric o_aggval
FROM (
	SELECT
		t1.val val,
		unnest(CASE WHEN ((t1.dn = t2.dn) OR (t1.dn < 0 AND t2.dn <= 0)) THEN ARRAY[t2.dn::bigint]
		WHEN t2.dn IS NULL AND t1.dn < 0 THEN ARRAY(SELECT g::bigint FROM generate_series(0, $7::bigint, 1) g)
		WHEN t2.dn IS NULL AND t1.dn <= $7::bigint THEN ARRAY(SELECT g FROM generate_series(t1.dn::bigint, $7::bigint, 1) g)
		WHEN t1.dn < 0 AND t2.dn > 0 THEN ARRAY(SELECT g FROM generate_series(0, (t2.dn - 1)::bigint, 1) g)
		ELSE ARRAY(SELECT g FROM generate_series(t1.dn::bigint, (t2.dn - 1)::bigint, 1) g)
		END) dn
	FROM
		dtbl t1
		LEFT JOIN dtbl t2 ON (t1.rn = t2.rn - 1)) t
WHERE dn >= 0 AND to_timestamp((dn * EXTRACT(EPOCH FROM $1::interval)) + EXTRACT(EPOCH FROM $2::timestamptz)) < ($4::timestamptz + ($1::interval / 5))
GROUP BY dn
ORDER BY dn',
'WITH dtbl AS (
	SELECT
		floor(EXTRACT(EPOCH FROM (ph.recorded_time - $2::timestamptz)) / EXTRACT(EPOCH FROM $1::interval)) dn,
		row_number() OVER (ORDER BY ph.recorded_time) rn,
		COALESCE(ph.@@COLUMN@@, 0) val
	FROM
		pemhistory.@@TABLE@@ ph
	WHERE @@CONDITION@@
		AND ph.recorded_time >= $3::timestamptz
		AND ph.recorded_time <= $4::timestamptz
)
SELECT
	$5::int2 o_idx, $6::text o_label,
	to_timestamp((dn * EXTRACT(EPOCH FROM $1::interval)) + EXTRACT(EPOCH FROM $2::timestamptz)) o_aggtime,
	min(val)::numeric o_aggval
FROM (
	SELECT
		t1.val val,
		unnest(CASE WHEN ((t1.dn = t2.dn) OR (t1.dn < 0 AND t2.dn <= 0)) THEN ARRAY[t2.dn::bigint]
		WHEN t2.dn IS NULL AND t1.dn < 0 THEN ARRAY(SELECT g::bigint FROM generate_series(0, $7::bigint, 1) g)
		WHEN t2.dn IS NULL AND t1.dn <= $7::bigint THEN ARRAY(SELECT g FROM generate_series(t1.dn::bigint, $7::bigint, 1) g)
		WHEN t1.dn < 0 AND t2.dn > 0 THEN ARRAY(SELECT g FROM generate_series(0, (t2.dn - 1)::bigint, 1) g)
		ELSE ARRAY(SELECT g FROM generate_series(t1.dn::bigint, (t2.dn - 1)::bigint, 1) g)
		END) dn
	FROM
		dtbl t1
		LEFT JOIN dtbl t2 ON (t1.rn = t2.rn - 1)) t
WHERE dn >= 0 AND to_timestamp((dn * EXTRACT(EPOCH FROM $1::interval)) + EXTRACT(EPOCH FROM $2::timestamptz)) < ($4::timestamptz + ($1::interval / 5))
GROUP BY dn
ORDER BY dn',
'WITH dtbl AS (
	SELECT
		floor(EXTRACT(EPOCH FROM (ph.recorded_time - $2::timestamptz)) / EXTRACT(EPOCH FROM $1::interval)) dn,
		(((floor(EXTRACT(EPOCH FROM (ph.recorded_time - $2::timestamptz)) / (EXTRACT(EPOCH FROM $1::interval))) + 1) * EXTRACT(EPOCH FROM $1::interval) / EXTRACT(EPOCH FROM $8::interval)) - floor(EXTRACT(EPOCH FROM (ph.recorded_time - $2::timestamptz)) / (EXTRACT(EPOCH FROM $8::interval)))) cnt,
		row_number() OVER (ORDER BY ph.recorded_time) rn,
		ph.recorded_time rt, COALESCE(ph.@@COLUMN@@, 0) val
	FROM
		pemhistory.@@TABLE@@ ph
	WHERE @@CONDITION@@
		AND ph.recorded_time >= $3::timestamptz
		AND ph.recorded_time <= $4::timestamptz
)
SELECT
	$5::int2 o_idx, $6::text o_label,
	to_timestamp((dn * EXTRACT(EPOCH FROM $1::interval)) + EXTRACT(EPOCH FROM $2::timestamptz)) o_aggtime,
	(sum(val::numeric * cnt) / sum(cnt))::numeric o_aggval
FROM (
	SELECT
		t1.val val,
		unnest(CASE WHEN ((t1.dn = t2.dn) OR (t1.dn < 0 AND t2.dn <= 0)) THEN ARRAY[t2.dn::bigint]
		WHEN t2.dn IS NULL AND t1.dn < 0 THEN ARRAY(SELECT g::bigint FROM generate_series(0, $7::bigint, 1) g)
		WHEN t2.dn IS NULL AND t1.dn <= $7::bigint THEN ARRAY(SELECT g FROM generate_series(t1.dn::bigint, $7::bigint, 1) g)
		WHEN t1.dn < 0 AND t2.dn > 0 THEN ARRAY(SELECT g FROM generate_series(0, (t2.dn - 1)::bigint, 1) g)
		ELSE ARRAY(SELECT g FROM generate_series(t1.dn::bigint, (t2.dn - 1)::bigint, 1) g)
		END) dn,
		unnest(CASE WHEN ((t1.dn = t2.dn) OR (t1.dn < 0 AND t2.dn <= 0)) THEN ARRAY[1::bigint]
		WHEN t2.dn IS NULL AND t1.dn < 0 THEN ARRAY(SELECT 1::bigint FROM generate_series(0, $7::bigint, 1) g)
		WHEN t2.dn IS NULL AND t1.dn <= $7::bigint THEN ARRAY(SELECT 1 FROM generate_series(t1.dn::bigint, $7::bigint, 1) g)
		WHEN t1.dn < 0 AND t2.dn > 0 THEN ARRAY(SELECT 1 FROM generate_series(0, (t2.dn - 1)::bigint, 1) g)
		ELSE ARRAY(SELECT t1.cnt FROM generate_series(t1.dn::bigint, (t2.dn - 1)::bigint, 1) g)
		END) cnt
	FROM
		dtbl t1
		LEFT JOIN dtbl t2 ON (t1.rn = t2.rn - 1)) t
WHERE dn >= 0 AND to_timestamp((dn * EXTRACT(EPOCH FROM $1::interval)) + EXTRACT(EPOCH FROM $2::timestamptz)) < ($4::timestamptz + ($1::interval / 5))
GROUP BY dn
ORDER BY dn'];

	IF v_minfreq IS NULL OR v_minfreq < '10 seconds'::interval THEN
		v_minfreq := '10 seconds'::interval;
	END IF;

	IF v_maxpoints IS NULL OR v_maxpoints <= 1 OR v_maxpoints > 300 THEN
		v_maxpoints := 300;
	END IF;

	IF v_t_time > v_s_time THEN
		v_s_time := v_t_time;
	END IF;

	-- No data available for this range
	IF v_e_time < v_t_time THEN
		RETURN;
	END IF;

	v_aggspan := EXTRACT (EPOCH FROM (v_e_time - v_s_time)) / (v_maxpoints - 1);
	IF v_aggspan < v_minfreq THEN
		v_aggspan := v_minfreq;
		SELECT max(a) + 1 INTO v_maxpoints FROM (SELECT unnest(ARRAY[floor(EXTRACT(EPOCH FROM (v_e_time - v_s_time)) / EXTRACT(EPOCH FROM v_aggspan))::bigint, 1::bigint]) a) t;
	END IF;

	IF v_t_op IS NOT NULL THEN
		IF v_e_time > v_c_time OR p_etime IS NULL THEN

			-- Slope, intercept, corr for the threshold metric
			--
			EXECUTE 'SELECT regr_slope(' || pg_catalog.quote_ident(v_t_op[4]) || '::numeric, EXTRACT(EPOCH FROM recorded_time)), regr_intercept(' || pg_catalog.quote_ident(v_t_op[4]) || '::numeric, EXTRACT(EPOCH FROM recorded_time)), corr(' || pg_catalog.quote_ident(v_t_op[4]) || '::numeric, EXTRACT(EPOCH FROM recorded_time)), count(*), (SELECT ' || pg_catalog.quote_ident(v_t_op[4]) || '::numeric FROM pemhistory.' || pg_catalog.quote_ident(v_t_op[3]) || ' WHERE ' || v_t_op[6] ||' ORDER BY recorded_time DESC LIMIT 1) FROM pemhistory.' || pg_catalog.quote_ident(v_t_op[3]) || ' WHERE ' || v_t_op[6]
			INTO v_slope, v_intercept, v_corr, v_cnt, v_value;

			IF (v_cnt = 1 AND v_value IS NOT NULL) OR
				(v_corr IS NULL AND v_value IS NOT NULL) THEN

				IF p_etime IS NULL THEN
					v_e_time := v_c_time + '3 years'::interval;
				END IF;

				v_aggspan := ((v_e_time - v_s_time) / (v_maxpoints - 1))::interval;
				IF v_minfreq > v_aggspan THEN
					v_aggspan := v_minfreq;
					SELECT max(a) + 1 INTO v_maxpoints FROM (SELECT unnest(ARRAY[floor(EXTRACT(EPOCH FROM (v_e_time - v_s_time)) / EXTRACT(EPOCH FROM v_aggspan))::bigint, 1::bigint]) a) t;
				END IF;

				IF v_s_time < v_c_time THEN
					-- 1. pos, 2. label, 3. probe_tbl, 4. probe_col, 5. agg, 6. condition, 7. groupon, 8. percentage_unit, 9. freq, 10. min_time
					CASE v_t_op[5]
					WHEN 'F' THEN
						-- frequncy, span, st, tst, et, pos, lbl
						RETURN QUERY EXECUTE replace(replace(replace(v_aggqry[1], '@@COLUMN@@', pg_catalog.quote_ident(v_t_op[4])), '@@TABLE@@', pg_catalog.quote_ident(v_t_op[3])), '@@CONDITION@@', v_t_op[6])  USING v_aggspan, v_s_time, v_t_op[10], v_c_time, v_t_op[1], v_t_op[2], v_maxpoints;
					WHEN 'M' THEN
						RETURN QUERY EXECUTE replace(replace(replace(v_aggqry[2], '@@COLUMN@@', pg_catalog.quote_ident(v_t_op[4])), '@@TABLE@@', pg_catalog.quote_ident(v_t_op[3])), '@@CONDITION@@', v_t_op[6])  USING v_aggspan, v_s_time, v_t_op[10], v_c_time, v_t_op[1], v_t_op[2], v_maxpoints;
					WHEN 'm' THEN
						RETURN QUERY EXECUTE replace(replace(replace(v_aggqry[3], '@@COLUMN@@', pg_catalog.quote_ident(v_t_op[4])), '@@TABLE@@', pg_catalog.quote_ident(v_t_op[3])), '@@CONDITION@@', v_t_op[6])  USING v_aggspan, v_s_time, v_t_op[10], v_c_time, v_t_op[1], v_t_op[2], v_maxpoints;
					ELSE
						RETURN QUERY EXECUTE replace(replace(replace(v_aggqry[4], '@@COLUMN@@', pg_catalog.quote_ident(v_t_op[4])), '@@TABLE@@', pg_catalog.quote_ident(v_t_op[3])), '@@CONDITION@@', v_t_op[6])  USING v_aggspan, v_s_time, v_t_op[10], v_c_time, v_t_op[1], v_t_op[2], v_maxpoints, v_t_op[9];
					END CASE;
					SELECT to_timestamp(((floor(EXTRACT(EPOCH FROM v_c_time - v_s_time) / EXTRACT(EPOCH FROM v_aggspan)) + 1) * EXTRACT(EPOCH FROM v_aggspan)) + EXTRACT(EPOCH FROM v_s_time)) INTO v_m_s_time;
				ELSE
					v_m_s_time := v_s_time;
				END IF;

				SELECT floor(EXTRACT(EPOCH FROM (v_e_time - v_m_s_time))/EXTRACT(EPOCH FROM v_aggspan))::bigint + 1 INTO v_maxpoints;
				RETURN QUERY EXECUTE 'SELECT $1::int2 o_idx, $2::text o_lbl, ($4::timestamptz + (series.point * $6::interval))::timestamptz o_aggtime, $3::numeric o_aggval FROM (SELECT generate_series(0, $5::bigint, 1) AS point) AS series' USING v_t_op[1], v_t_op[2], v_value, v_m_s_time, v_maxpoints, v_aggspan;

			ELSIF (v_corr IS NOT NULL AND v_slope IS NOT NULL AND v_intercept IS NOT NULL) THEN

				-- Do we need to calculate the timeline for extrapolated data?
				IF (v_e_op = 'FALLS_BELOW' AND v_value > v_e_val) OR
					(v_e_op = 'EXCEEDS' AND v_value < v_e_val) THEN

					IF p_etime IS NULL THEN
						v_e_time := v_c_time + '3 years'::interval;
					END IF;

					-- Let's calculate the value at maximum time period
					SELECT ((v_slope * EXTRACT(EPOCH FROM v_e_time)) + v_intercept) INTO v_tmpval;

					IF (v_tmpval < 0 AND v_e_op = 'FALLS_BELOW') OR
						(v_tmpval > 0 AND ((v_e_op = 'EXCEEDS' AND v_tmpval > v_e_val) OR
							(v_e_op = 'FALLS_BELOW' AND v_tmpval < v_e_val))) THEN
						SELECT to_timestamp((v_e_val - v_intercept) / v_slope) INTO v_e_time;
					ELSIF v_tmpval < 0 AND v_e_op = 'EXCEEDS' THEN
						SELECT to_timestamp((0 - v_intercept) / v_slope) INTO v_e_time;
					END IF;

					IF p_etime IS NULL AND v_e_time < v_c_time THEN
						v_e_time := v_c_time;
					END IF;
				END IF;

				v_aggspan := ((v_e_time - v_s_time) / (v_maxpoints - 1))::interval;
				IF v_minfreq > v_aggspan THEN
					v_aggspan := v_minfreq;
					SELECT max(a) + 1 INTO v_maxpoints FROM (SELECT unnest(ARRAY[floor(EXTRACT(EPOCH FROM (v_e_time - v_s_time)) / EXTRACT(EPOCH FROM v_aggspan))::bigint, 1::bigint]) a) t;
				END IF;

				IF v_s_time < v_c_time THEN
					-- 1. pos, 2. label, 3. probe_tbl, 4. probe_col, 5. agg, 6. condition, 7. groupon, 8. percentage_unit, 9. freq, 10. min_time
					CASE v_t_op[5]
					WHEN 'F' THEN
						-- frequncy, span, st, tst, et, pos, lbl
						RETURN QUERY EXECUTE replace(replace(replace(v_aggqry[1], '@@COLUMN@@', pg_catalog.quote_ident(v_t_op[4])), '@@TABLE@@', pg_catalog.quote_ident(v_t_op[3])), '@@CONDITION@@', v_t_op[6])  USING v_aggspan, v_s_time, v_t_op[10], v_c_time, v_t_op[1], v_t_op[2], v_maxpoints;
					WHEN 'M' THEN
						RETURN QUERY EXECUTE replace(replace(replace(v_aggqry[2], '@@COLUMN@@', pg_catalog.quote_ident(v_t_op[4])), '@@TABLE@@', pg_catalog.quote_ident(v_t_op[3])), '@@CONDITION@@', v_t_op[6])  USING v_aggspan, v_s_time, v_t_op[10], v_c_time, v_t_op[1], v_t_op[2], v_maxpoints;
					WHEN 'm' THEN
						RETURN QUERY EXECUTE replace(replace(replace(v_aggqry[3], '@@COLUMN@@', pg_catalog.quote_ident(v_t_op[4])), '@@TABLE@@', pg_catalog.quote_ident(v_t_op[3])), '@@CONDITION@@', v_t_op[6])  USING v_aggspan, v_s_time, v_t_op[10], v_c_time, v_t_op[1], v_t_op[2], v_maxpoints;
					ELSE
						RETURN QUERY EXECUTE replace(replace(replace(v_aggqry[4], '@@COLUMN@@', pg_catalog.quote_ident(v_t_op[4])), '@@TABLE@@', pg_catalog.quote_ident(v_t_op[3])), '@@CONDITION@@', v_t_op[6])  USING v_aggspan, v_s_time, v_t_op[10], v_c_time, v_t_op[1], v_t_op[2], v_maxpoints, v_t_op[9];
					END CASE;
					SELECT to_timestamp(((floor(EXTRACT(EPOCH FROM v_c_time - v_s_time) / EXTRACT(EPOCH FROM v_aggspan))  + 1) * EXTRACT(EPOCH FROM v_aggspan)) + EXTRACT(EPOCH FROM v_s_time)) INTO v_m_s_time;
				ELSE
					v_m_s_time := v_s_time;
				END IF;
				IF v_e_time > v_c_time THEN
					SELECT floor(EXTRACT(EPOCH FROM (v_e_time - v_m_s_time))/EXTRACT(EPOCH FROM v_aggspan))::bigint + 1 INTO v_maxpoints;
					RETURN QUERY EXECUTE 'SELECT $1::int2 o_idx, $2::text o_lbl, ($5::timestamptz + (series.point * $7::interval))::timestamptz  o_aggtime, (($3::numeric * (EXTRACT(EPOCH FROM $5::timestamptz) + (series.point * EXTRACT(EPOCH FROM $7::interval)))) + $4::numeric)::numeric o_aggval FROM (SELECT generate_series(0, $6::bigint, 1) AS point) AS series' USING v_t_op[1], v_t_op[2], v_slope, v_intercept, v_m_s_time, v_maxpoints, v_aggspan;
				END IF;
			ELSE
				o_idx := -1;
				o_aggtime := NULL;
				o_aggval  := NULL;
				o_label :=  '116';
				RETURN NEXT;

				IF (p_etime IS NOT NULL AND p_etime > v_c_time) OR (p_etime IS NULL) THEN
					v_e_time := v_c_time;
				ELSIF p_etime IS NOT NULL THEN
					v_e_time := p_etime;
				END IF;

				IF v_s_time > v_e_time THEN
					RETURN;
				END IF;

				v_aggspan := ((v_e_time - v_s_time) / (v_maxpoints - 1))::interval;
				IF v_minfreq > v_aggspan THEN
					v_aggspan := v_minfreq;
					SELECT max(a) + 1 INTO v_maxpoints FROM (SELECT unnest(ARRAY[floor(EXTRACT(EPOCH FROM (v_e_time - v_s_time)) / EXTRACT(EPOCH FROM v_aggspan))::bigint, 1::bigint]) a) t;
				END IF;

				IF v_s_time < v_c_time THEN
					-- 1. pos, 2. label, 3. probe_tbl, 4. probe_col, 5. agg, 6. condition, 7. groupon, 8. percentage_unit, 9. freq, 10. min_time
					CASE v_t_op[5]
					WHEN 'F' THEN
						-- frequncy, span, st, tst, et, pos, lbl
						RETURN QUERY EXECUTE replace(replace(replace(v_aggqry[1], '@@COLUMN@@', pg_catalog.quote_ident(v_t_op[4])), '@@TABLE@@', pg_catalog.quote_ident(v_t_op[3])), '@@CONDITION@@', v_t_op[6])  USING v_aggspan, v_s_time, v_t_op[10], v_c_time, v_t_op[1], v_t_op[2], v_maxpoints;
					WHEN 'M' THEN
						RETURN QUERY EXECUTE replace(replace(replace(v_aggqry[2], '@@COLUMN@@', pg_catalog.quote_ident(v_t_op[4])), '@@TABLE@@', pg_catalog.quote_ident(v_t_op[3])), '@@CONDITION@@', v_t_op[6])  USING v_aggspan, v_s_time, v_t_op[10], v_c_time, v_t_op[1], v_t_op[2], v_maxpoints;
					WHEN 'm' THEN
						RETURN QUERY EXECUTE replace(replace(replace(v_aggqry[3], '@@COLUMN@@', pg_catalog.quote_ident(v_t_op[4])), '@@TABLE@@', pg_catalog.quote_ident(v_t_op[3])), '@@CONDITION@@', v_t_op[6])  USING v_aggspan, v_s_time, v_t_op[10], v_c_time, v_t_op[1], v_t_op[2], v_maxpoints;
					ELSE
						RETURN QUERY EXECUTE replace(replace(replace(v_aggqry[4], '@@COLUMN@@', pg_catalog.quote_ident(v_t_op[4])), '@@TABLE@@', pg_catalog.quote_ident(v_t_op[3])), '@@CONDITION@@', v_t_op[6])  USING v_aggspan, v_s_time, v_t_op[10], v_c_time, v_t_op[1], v_t_op[2], v_maxpoints, v_t_op[9];
					END CASE;
				END IF;
			END IF;
		ELSE
			v_aggspan := ((v_e_time - v_s_time) / (v_maxpoints - 1))::interval;
			IF v_minfreq > v_aggspan THEN
				v_aggspan := v_minfreq;
				SELECT max(a) + 1 INTO v_maxpoints FROM (SELECT unnest(ARRAY[floor(EXTRACT(EPOCH FROM (v_e_time - v_s_time)) / EXTRACT(EPOCH FROM v_aggspan))::bigint, 1::bigint]) a) t;
			END IF;

			-- 1. pos, 2. label, 3. probe_tbl, 4. probe_col, 5. agg, 6. condition, 7. groupon, 8. percentage_unit, 9. freq, 10. min_time
			CASE v_t_op[5]
			WHEN 'F' THEN
				-- frequncy, span, st, tst, et, pos, lbl
				RETURN QUERY EXECUTE replace(replace(replace(v_aggqry[1], '@@COLUMN@@', pg_catalog.quote_ident(v_t_op[4])), '@@TABLE@@', pg_catalog.quote_ident(v_t_op[3])), '@@CONDITION@@', v_t_op[6])  USING v_aggspan, v_s_time, v_t_op[10], v_e_time, v_t_op[1], v_t_op[2], v_maxpoints;
			WHEN 'M' THEN
				RETURN QUERY EXECUTE replace(replace(replace(v_aggqry[2], '@@COLUMN@@', pg_catalog.quote_ident(v_t_op[4])), '@@TABLE@@', pg_catalog.quote_ident(v_t_op[3])), '@@CONDITION@@', v_t_op[6])  USING v_aggspan, v_s_time, v_t_op[10], v_e_time, v_t_op[1], v_t_op[2], v_maxpoints;
			WHEN 'm' THEN
				RETURN QUERY EXECUTE replace(replace(replace(v_aggqry[3], '@@COLUMN@@', pg_catalog.quote_ident(v_t_op[4])), '@@TABLE@@', pg_catalog.quote_ident(v_t_op[3])), '@@CONDITION@@', v_t_op[6])  USING v_aggspan, v_s_time, v_t_op[10], v_e_time, v_t_op[1], v_t_op[2], v_maxpoints;
			ELSE
				RETURN QUERY EXECUTE replace(replace(replace(v_aggqry[4], '@@COLUMN@@', pg_catalog.quote_ident(v_t_op[4])), '@@TABLE@@', pg_catalog.quote_ident(v_t_op[3])), '@@CONDITION@@', v_t_op[6])  USING v_aggspan, v_s_time, v_t_op[10], v_e_time, v_t_op[1], v_t_op[2], v_maxpoints, v_t_op[9];
			END CASE;
		END IF;
	ELSIF p_etime IS NULL AND v_e_span IS NOT NULL AND v_e_span >= '1 seconds'::interval THEN
		v_e_time := v_c_time + v_e_span;
		v_aggspan := ((v_e_time - v_s_time) / (v_maxpoints - 1))::interval;
		IF v_minfreq > v_aggspan THEN
			v_aggspan := v_minfreq;
			SELECT max(a) + 1 INTO v_maxpoints FROM (SELECT unnest(ARRAY[floor(EXTRACT(EPOCH FROM (v_e_time - v_s_time)) / EXTRACT(EPOCH FROM v_aggspan))::bigint, 1::bigint]) a) t;
		END IF;
	END IF;

	IF v_s_time <= v_c_time AND v_e_time > v_c_time THEN
		o_idx := -1;
		o_aggtime := v_c_time;
		o_aggval  := NULL;
		o_label :=  '115';

		RETURN NEXT;
	END IF;

	IF array_length(v_m_ops, 1) IS NULL OR array_length(v_m_ops, 1) = 0 THEN
		RETURN;
	END IF;

	v_m_s_time := v_s_time;
	FOR v_pos IN array_lower(v_m_ops, 1) .. array_upper(v_m_ops, 1)
	LOOP
		v_qry := '
WITH dtbl AS (
	SELECT
		rt, val, floor(dt / (EXTRACT(EPOCH FROM $1::interval))) pn, floor(dt / (EXTRACT(EPOCH FROM $2::interval))) dn,
		dense_rank() OVER (PARTITION BY floor(dt / (EXTRACT(EPOCH FROM $2::interval))) ORDER BY floor(dt / (EXTRACT(EPOCH FROM $1::interval))) ASC) pidx,
		row_number() OVER (ORDER BY rt) rn
	FROM (
		SELECT
			EXTRACT(EPOCH FROM (ph.recorded_time - $3::timestamptz)) dt,
			ph.recorded_time rt, COALESCE(' || pg_catalog.quote_ident(v_m_ops[v_pos][4]) || ', 0) val
		FROM
			pemhistory.' || pg_catalog.quote_ident(v_m_ops[v_pos][3]) || ' ph
		WHERE ' || v_m_ops[v_pos][6] || ' AND ph.recorded_time >= $4::timestamptz AND ph.recorded_time <= $5::timestamptz) tbl
)
';

		IF v_e_time > v_c_time THEN
			-- Calculate slope, intercept, corr for this metric
			--
			EXECUTE 'SELECT regr_slope(' || pg_catalog.quote_ident(v_m_ops[v_pos][4]) || '::numeric, EXTRACT(EPOCH FROM recorded_time)), regr_intercept(' || pg_catalog.quote_ident(v_m_ops[v_pos][4]) || '::numeric, EXTRACT(EPOCH FROM recorded_time)), corr(' || pg_catalog.quote_ident(v_m_ops[v_pos][4]) || '::numeric, EXTRACT(EPOCH FROM recorded_time)), count(*), (SELECT ' || pg_catalog.quote_ident(v_m_ops[v_pos][4]) || '::numeric FROM pemhistory.' || pg_catalog.quote_ident(v_m_ops[v_pos][3]) || ' WHERE ' || v_m_ops[v_pos][6] ||' AND ' || pg_catalog.quote_ident(v_m_ops[v_pos][4]) || ' IS NOT NULL ORDER BY recorded_time DESC LIMIT 1) FROM pemhistory.' || pg_catalog.quote_ident(v_m_ops[v_pos][3]) || ' WHERE ' || v_m_ops[v_pos][6]
			INTO v_slope, v_intercept, v_corr, v_cnt, v_value;

			IF v_cnt = 1 OR v_corr IS NULL OR v_value IS NULL OR v_s_time > v_c_time THEN
				IF (v_cnt = 1 OR v_corr IS NULL) AND v_value IS NOT NULL THEN
					SELECT floor(EXTRACT(EPOCH FROM (v_e_time - v_s_time))/EXTRACT(EPOCH FROM v_aggspan))::bigint + 1 INTO v_maxpoints;
					RETURN QUERY EXECUTE 'SELECT $1::int2 o_idx, $2::text o_lbl, ($4::timestamptz + (series.point * $6::interval))::timestamptz o_aggtime, $3::numeric o_aggval FROM (SELECT generate_series(0, $5::bigint, 1) AS point) AS series' USING v_m_ops[v_pos][1], v_m_ops[v_pos][2], v_value, v_s_time, v_maxpoints, v_aggspan;
					CONTINUE;
				ELSIF (v_corr IS NOT NULL AND v_value IS NOT NULL AND v_slope IS NOT NULL AND v_intercept IS NOT NULL) THEN
					SELECT floor(EXTRACT(EPOCH FROM (v_e_time - v_s_time))/EXTRACT(EPOCH FROM v_aggspan))::bigint + 1 INTO v_maxpoints;
					RETURN QUERY EXECUTE 'SELECT $1::int2 o_idx, $2::text o_lbl, ($5::timestamptz + (series.point * $7::interval))::timestamptz  o_aggtime, (($3::numeric * (EXTRACT(EPOCH FROM $5::timestamptz) + (series.point * EXTRACT(EPOCH FROM $7::interval)))) + $4::numeric)::numeric o_aggval FROM (SELECT generate_series(0, $6::bigint, 1) AS point) AS series' USING v_m_ops[v_pos][1], v_m_ops[v_pos][2], v_slope, v_intercept, v_s_time, v_maxpoints, v_aggspan;
					CONTINUE;
				ELSIF (v_value IS NULL OR v_cnt = 0 OR (v_corr IS NULL AND v_slope IS NULL AND v_intercept IS NULL)) THEN
					CONTINUE;
				ELSE
					v_m_e_time := v_c_time;
				END IF;
			END IF;

			-- Let's calculate the value at maximum time period
			SELECT ((v_slope * EXTRACT(EPOCH FROM v_e_time)) + v_intercept) INTO v_tmpval;

			IF (v_tmpval < 0) THEN
				SELECT to_timestamp((0 - v_intercept) / v_slope) INTO v_m_e_time;
			ELSIF v_tmpval > 0 AND (v_m_ops[v_pos][8]::boolean = true)  THEN
				SELECT to_timestamp((100 - v_intercept) / v_slope) INTO v_m_e_time;
			ELSE
				v_m_e_time := v_e_time;
			END IF;
			IF v_m_e_time > v_e_time THEN
				v_m_e_time := v_e_time;
			END IF;

			IF v_s_time <= v_c_time THEN
				-- 1. pos, 2. label, 3. probe_tbl, 4. probe_col, 5. agg, 6. condition, 7. groupon, 8. percentage_unit, 9. freq, 10. min_time
				CASE v_m_ops[v_pos][5]
				WHEN 'F' THEN
					-- frequncy, span, st, tst, et, pos, lbl
					RETURN QUERY EXECUTE replace(replace(replace(v_aggqry[1], '@@COLUMN@@', pg_catalog.quote_ident(v_m_ops[v_pos][4])), '@@TABLE@@', pg_catalog.quote_ident(v_m_ops[v_pos][3])), '@@CONDITION@@', v_m_ops[v_pos][6])  USING v_aggspan, v_s_time, v_m_ops[v_pos][10], v_c_time, v_m_ops[v_pos][1], v_m_ops[v_pos][2], v_maxpoints;
				WHEN 'M' THEN
					RETURN QUERY EXECUTE replace(replace(replace(v_aggqry[2], '@@COLUMN@@', pg_catalog.quote_ident(v_m_ops[v_pos][4])), '@@TABLE@@', pg_catalog.quote_ident(v_m_ops[v_pos][3])), '@@CONDITION@@', v_m_ops[v_pos][6])  USING v_aggspan, v_s_time, v_m_ops[v_pos][10], v_c_time, v_m_ops[v_pos][1], v_m_ops[v_pos][2], v_maxpoints;
				WHEN 'm' THEN
					RETURN QUERY EXECUTE replace(replace(replace(v_aggqry[3], '@@COLUMN@@', pg_catalog.quote_ident(v_m_ops[v_pos][4])), '@@TABLE@@', pg_catalog.quote_ident(v_m_ops[v_pos][3])), '@@CONDITION@@', v_m_ops[v_pos][6])  USING v_aggspan, v_s_time, v_m_ops[v_pos][10], v_c_time, v_m_ops[v_pos][1], v_m_ops[v_pos][2], v_maxpoints;
				ELSE
					RETURN QUERY EXECUTE replace(replace(replace(v_aggqry[4], '@@COLUMN@@', pg_catalog.quote_ident(v_m_ops[v_pos][4])), '@@TABLE@@', pg_catalog.quote_ident(v_m_ops[v_pos][3])), '@@CONDITION@@', v_m_ops[v_pos][6])  USING v_aggspan, v_s_time, v_m_ops[v_pos][10], v_c_time, v_m_ops[v_pos][1], v_m_ops[v_pos][2], v_maxpoints, v_m_ops[v_pos][9];
				END CASE;
			END IF;

			IF v_m_e_time > v_c_time THEN
				IF v_m_s_time < v_c_time THEN
					SELECT to_timestamp(((floor(EXTRACT(EPOCH FROM v_c_time - v_s_time) / EXTRACT(EPOCH FROM v_aggspan))  + 1) * EXTRACT(EPOCH FROM v_aggspan)) + EXTRACT(EPOCH FROM v_s_time)) INTO v_m_s_time;
				END IF;
				SELECT floor(EXTRACT(EPOCH FROM (v_m_e_time - v_m_s_time))/EXTRACT(EPOCH FROM v_aggspan))::bigint + 1 INTO v_maxpoints;
				RETURN QUERY EXECUTE 'SELECT $1::int2 o_idx, $2::text o_lbl, ($5::timestamptz + (series.point * $7::interval))::timestamptz  o_aggtime, (($3::numeric * (EXTRACT(EPOCH FROM $5::timestamptz) + (series.point * EXTRACT(EPOCH FROM $7::interval)))) + $4::numeric)::numeric o_aggval FROM (SELECT generate_series(0, $6::bigint, 1) AS point) AS series' USING v_m_ops[v_pos][1], v_m_ops[v_pos][2], v_slope, v_intercept, v_m_s_time, v_maxpoints, v_aggspan;
			END IF;
		ELSE
			-- max-points, span, frequncy, probe start time, st, et, pos, lbl
			CASE v_m_ops[v_pos][5]
			WHEN 'F' THEN
				RETURN QUERY EXECUTE replace(replace(replace(v_aggqry[1], '@@COLUMN@@', pg_catalog.quote_ident(v_m_ops[v_pos][4])), '@@TABLE@@', pg_catalog.quote_ident(v_m_ops[v_pos][3])), '@@CONDITION@@', v_m_ops[v_pos][6])  USING v_aggspan, v_s_time, v_m_ops[v_pos][10], v_e_time, v_m_ops[v_pos][1], v_m_ops[v_pos][2], v_maxpoints;
			WHEN 'M' THEN
				RETURN QUERY EXECUTE replace(replace(replace(v_aggqry[2], '@@COLUMN@@', pg_catalog.quote_ident(v_m_ops[v_pos][4])), '@@TABLE@@', pg_catalog.quote_ident(v_m_ops[v_pos][3])), '@@CONDITION@@', v_m_ops[v_pos][6])  USING v_aggspan, v_s_time, v_m_ops[v_pos][10], v_e_time, v_m_ops[v_pos][1], v_m_ops[v_pos][2], v_maxpoints;
			WHEN 'm' THEN
				RETURN QUERY EXECUTE replace(replace(replace(v_aggqry[3], '@@COLUMN@@', pg_catalog.quote_ident(v_m_ops[v_pos][4])), '@@TABLE@@', pg_catalog.quote_ident(v_m_ops[v_pos][3])), '@@CONDITION@@', v_m_ops[v_pos][6])  USING v_aggspan, v_s_time, v_m_ops[v_pos][10], v_e_time, v_m_ops[v_pos][1], v_m_ops[v_pos][2], v_maxpoints;
			ELSE
				RETURN QUERY EXECUTE replace(replace(replace(v_aggqry[4], '@@COLUMN@@', pg_catalog.quote_ident(v_m_ops[v_pos][4])), '@@TABLE@@', pg_catalog.quote_ident(v_m_ops[v_pos][3])), '@@CONDITION@@', v_m_ops[v_pos][6])  USING v_aggspan, v_s_time, v_m_ops[v_pos][10], v_e_time, v_m_ops[v_pos][1], v_m_ops[v_pos][2], v_maxpoints,  v_m_ops[v_pos][9];
			END CASE;
		END IF;
	END LOOP;

END
$$ LANGUAGE 'plpgsql';

-- Move all BDR Charts from Server level to Database level
UPDATE pem.chart
SET level = '{300}'
WHERE name ilike '%bdr%' and params is NULL AND level = '{200}' AND reference_id not like 'chart_%';

UPDATE pem.chart
	SET params = '{server_id,database_name}'
WHERE  name ILIKE '%bdr%' AND level = '{300}' AND reference_id NOT LIKE 'chart_%' AND params is NULL AND type = 'L';

-- BARMAN Schema
-- Update this function for listing all the supported tools.
CREATE OR REPLACE FUNCTION pem.supported_tool(text) RETURNS boolean AS $$
    SELECT $1 IN ('barman');
$$ LANGUAGE SQL IMMUTABLE;

CREATE TABLE IF NOT EXISTS pem.tool(
    id serial NOT NULL,
    gid int NOT NULL DEFAULT 1 /* PEM Directory Server */,
    name text NOT NULL,
    active boolean NOT NULL DEFAULT true,
    options jsonb,
    description text NOT NULL,
    team text NOT NULL DEFAULT '', -- Defines the visibility of the tool in particular role/team
    owner oid, -- The owner of the registered tool
    CONSTRAINT pem_tool_pkey PRIMARY KEY (id),
    CONSTRAINT pem_tool_is_supported CHECK (pem.supported_tool(name))
);

CREATE OR REPLACE FUNCTION pem.tool_insertion() RETURNS trigger AS $$
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

DROP TRIGGER IF EXISTS tool_insertion
    ON pem.tool;

CREATE TRIGGER tool_insertion
	BEFORE INSERT ON pem.tool
	FOR EACH ROW EXECUTE PROCEDURE pem.tool_insertion();

CREATE OR REPLACE FUNCTION pem.validate_agent_tool_options(p_agent_id int, p_tool_id int, p_options jsonb)
RETURNS boolean AS
$FUNC$
DECLARE
    v_name text;
BEGIN
    SELECT name INTO v_name FROM pem.tool WHERE id = p_tool_id;
    IF v_name = 'barman' THEN
        RETURN (SELECT pem.validate_barman_agent_options(p_agent_id, p_tool_id, p_options));
    END IF;
RETURN false;
END;
$FUNC$
LANGUAGE 'plpgsql';

CREATE OR REPLACE FUNCTION pem.validate_barman_agent_options(p_agent_id int, p_tool_id int, p_options jsonb)
RETURNS boolean AS
$FUNC$
DECLARE
	url text;
	result boolean;
BEGIN
	SELECT p_options -> 'barman_url' INTO url;
	SELECT url like '"http://%' OR url like '"https://%' into result;
	IF result = 'f' THEN
		RAISE INFO 'URL must start with http:// or https://';
	END IF;
	RETURN result;
RETURN true;
END;
$FUNC$
LANGUAGE 'plpgsql';

CREATE TABLE IF NOT EXISTS pem.agent_tool_binding (
    agent_id int NOT NULL,
    tool_id int NOT NULL,
    options jsonb,
    CONSTRAINT agent_tool_binding_pkey PRIMARY KEY (tool_id),
    CONSTRAINT agent_tool_uniq UNIQUE(agent_id, tool_id),
    CONSTRAINT pem_tool_id_fkey FOREIGN KEY (tool_id)
    REFERENCES pem.tool (id) MATCH SIMPLE
        ON UPDATE CASCADE ON DELETE CASCADE INITIALLY DEFERRED,
    CONSTRAINT pem_agent_id_fkey FOREIGN KEY (agent_id)
    REFERENCES pem.agent (id) MATCH SIMPLE
        ON UPDATE CASCADE ON DELETE CASCADE INITIALLY DEFERRED,
        CONSTRAINT pem_agent_tool_options_validation CHECK (pem.validate_agent_tool_options(agent_id, tool_id, options))
);


CREATE OR REPLACE FUNCTION pem.tool_postupdate() RETURNS trigger AS $$
BEGIN
    IF (OLD.active AND NOT NEW.active) THEN
        DELETE FROM pem.agent_tool_binding WHERE tool_id = NEW.id;
    END IF;
    NEW.name := OLD.name;
    RETURN NEW;
END
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS tool_postupdate
    ON pem.tool;

CREATE TRIGGER tool_postupdate
	AFTER UPDATE ON pem.tool
	FOR EACH ROW EXECUTE PROCEDURE pem.tool_postupdate();

-- table to save per user pem tool information.
CREATE TABLE IF NOT EXISTS pem.tool_options (
    tool_id            integer NOT NULL, -- Agent identifier
    pem_user            text NOT NULL DEFAULT CURRENT_USER, -- ID of PEM user
    description         text,
    options             jsonb,
    gid                 int NOT NULL DEFAULT 1,
    CONSTRAINT tool_option_pkey PRIMARY KEY (tool_id, pem_user),
    CONSTRAINT tool_option_tool_id_fkey FOREIGN KEY (tool_id)
        REFERENCES pem.tool (id) MATCH SIMPLE
        ON UPDATE CASCADE ON DELETE CASCADE INITIALLY DEFERRED,
    CONSTRAINT tool_option_pem_user_key UNIQUE (pem_user, tool_id)
);

-- Add a column to identify if tool_options need to check tools column
DO $$
BEGIN
	IF NOT EXISTS(
		SELECT * FROM pg_catalog.pg_attribute
		LEFT JOIN pg_catalog.pg_class c ON attrelid = c.oid
		LEFT JOIN pg_catalog.pg_namespace n ON c.relnamespace = n.oid
		WHERE attname = 'options' AND relname = 'tool_options' AND
			n.nspname = 'pem'
	) THEN
		RAISE INFO '--- Adding new column options in pem.tool_options';
        ALTER TABLE pem.tool_options
            ADD COLUMN options jsonb;
	END IF;
  IF NOT EXISTS(
		SELECT * FROM pg_catalog.pg_attribute
		LEFT JOIN pg_catalog.pg_class c ON attrelid = c.oid
		LEFT JOIN pg_catalog.pg_namespace n ON c.relnamespace = n.oid
		WHERE attname = 'gid' AND relname = 'tool_options' AND
			n.nspname = 'pem'
	) THEN
		RAISE INFO '--- Adding new column gid in pem.tool_options';
        ALTER TABLE pem.tool_options
            ADD COLUMN gid int NOT NULL DEFAULT 1;
	END IF;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION pem.agent_postupdate() RETURNS trigger AS $$
BEGIN
    IF (OLD.active AND NOT NEW.active) THEN
        DELETE FROM pem.agent_server_binding WHERE agent_id = NEW.id;
        DELETE FROM pem.agent_tool_binding WHERE agent_id = NEW.id;
        DELETE FROM pem.alert WHERE agent_id = NEW.id;
    END IF;
    RETURN NULL;
END
$$ LANGUAGE plpgsql;

CREATE TABLE IF NOT EXISTS pem.tool_heartbeat(
    agent_id             integer NOT NULL,
    tool_id              integer NOT NULL,
    missing_heartbeat_at timestamptz NOT NULL,

    CONSTRAINT tool_heartbeat_uniq UNIQUE(agent_id, tool_id),
    CONSTRAINT tool_heartbeat_fkey FOREIGN KEY (tool_id)
        REFERENCES pem.agent_tool_binding ON UPDATE CASCADE ON DELETE CASCADE
);

ALTER TABLE pem.tool_heartbeat
    DROP COLUMN IF EXISTS last_heartbeat;
ALTER TABLE pem.tool_heartbeat
    ADD COLUMN IF NOT EXISTS missing_heartbeat_at timestamptz NOT NULL;

CREATE OR REPLACE FUNCTION pem.update_tool_history() RETURNS trigger AS $$
BEGIN
    IF (OLD.missing_heartbeat_at IS NOT NULL AND NEW.missing_heartbeat_at IS NULL) THEN
        INSERT INTO pemhistory.tool_heartbeat(
            agent_id, tool_id, start_time, end_time
        ) VALUES (
            OLD.agent_id, OLD.tool_id, OLD.missing_heartbeat_at, now()
        );
    END IF;
    IF TG_OP = 'UPDATE' THEN
        -- Do not allow to change the tool type
        NEW.name := OLD.name;
    END IF;
    RETURN NEW;
END
$$ LANGUAGE plpgsql;


DROP TRIGGER IF EXISTS tool_heartbeat_postupdate
    ON pem.tool_heartbeat;

DROP TRIGGER IF EXISTS tool_heartbeat_postdelete
    ON pem.tool_heartbeat;

CREATE TRIGGER tool_heartbeat_postupdate
    AFTER UPDATE ON pem.tool_heartbeat
    FOR EACH ROW EXECUTE PROCEDURE pem.update_tool_history();

CREATE TRIGGER tool_heartbeat_postdelete
    AFTER DELETE ON pem.tool_heartbeat
    FOR EACH ROW EXECUTE PROCEDURE pem.update_tool_history();

CREATE TABLE IF NOT EXISTS pemhistory.tool_heartbeat(
    agent_id   integer NOT NULL,
    tool_id       integer NOT NULL,
    start_time timestamptz NOT NULL,
    end_time   timestamptz NOT NULL
);

DROP VIEW IF EXISTS pem.avail_tools;
-- Only these tool(s) are available, which meets following conditions:
-- 1.  Active
-- 2a. current_user is a superuser
-- OR
-- 2b. Current user is a member of pem_super_admin
-- OR
-- 2c. No team is specified.
-- OR
-- 2d. Current user is the owner
-- OR
-- 2e. Current user is the member of the specified team/role.
CREATE OR REPLACE VIEW pem.avail_tools AS
	SELECT
		a.id AS id,
		a.name,
		COALESCE(tos.description, a.description) AS description,
		a.options,
		a.active AS active,
		a.owner AS owner,
		a.team AS team,
		o.rolname AS tool_owner,
		a.gid
		--COALESCE(tos.group_id, a.group_id, 0) AS group_id
	FROM (SELECT a.*, r.rolsuper AS rolsuper FROM pem.tool a, pg_catalog.pg_roles r WHERE r.rolname = current_user) AS a
		LEFT JOIN pem.tool_options tos ON (a.id = tos.tool_id AND pem_user = current_user)
		LEFT OUTER JOIN pg_catalog.pg_roles o ON (o.oid = a.owner)
		LEFT OUTER JOIN pg_catalog.pg_roles t ON (t.rolname = a.team)
WHERE
		-- Only active tools
		a.active AND
		(
			-- current user is superuser
			a.rolsuper OR
			-- No team provided
			a.team IS NULL OR a.team = '' OR
			-- Owner of the agent
			o.rolname = current_user OR
			-- Is a superuser
			pg_catalog.pg_has_role('pem_super_admin', 'member') OR
			-- Valid team provided and current_user is member of the it
			(t.oid IS NOT NULL AND pg_catalog.pg_has_role(a.team, 'member'))
		);

DO $DO$
DECLARE
    temp text;
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pem.roles WHERE component = 'comp_barman' ) THEN
        -- Create a role for BARMAN tool
        SELECT pem.create_role_for(
            'comp_barman',
            'Role to access BARMAN tool in PEM',
            ARRAY['pem_component'],
            -- INSERT
            '{}'::text[],
            -- UPDATE
            '{}'::text[],
            -- DELETE
            '{}'::text[],
            -- ALL
            ARRAY[
                ARRAY['pem', 'tool'],
                ARRAY['pem', 'agent_tool_binding'],
                ARRAY['pem', 'tool_options'],
                ARRAY['pem', 'tool_heartbeat'],
                ARRAY['pemhistory', 'tool_heartbeat']
            ]
        ) into temp;
    END IF;
END;
$DO$ LANGUAGE 'plpgsql';

GRANT pem_manage_schedule_task TO pem_comp_barman;

GRANT ALL ON TABLE pem.tool TO pem_agent;
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE pem.agent_tool_binding TO pem_agent;
GRANT ALL ON TABLE pem.tool_options TO pem_agent;
GRANT ALL ON TABLE pem.tool_heartbeat TO pem_agent;
GRANT USAGE ON SEQUENCE pem.tool_id_seq TO pem_agent;

-- Team support using Row Level Security
DO $$
DECLARE
  rls_supported boolean;
BEGIN
    SELECT (count(*) = 1) INTO rls_supported FROM pg_catalog.pg_class WHERE relname = 'pg_policy' AND relnamespace = (SELECT oid FROM pg_catalog.pg_namespace WHERE nspname = 'pg_catalog');

    IF rls_supported THEN
        RAISE INFO 'RLS policies for pem.tool...';

        EXECUTE 'DROP POLICY IF EXISTS pem_tool_team_support_select ON pem.tool';
        EXECUTE 'DROP POLICY IF EXISTS pem_tool_team_support_update ON pem.tool';
        EXECUTE 'DROP POLICY IF EXISTS pem_tool_team_support_delete ON pem.tool';
        EXECUTE 'DROP POLICY IF EXISTS pem_tool_team_support_insert ON pem.tool';

        EXECUTE $SQL$ ALTER TABLE pem.tool ENABLE ROW LEVEL SECURITY $SQL$;
        EXECUTE $SQL$
            CREATE POLICY pem_tool_team_support_select
                ON pem.tool
                FOR SELECT
                USING (
                    pem.can_access_team(owner, team) OR
                    pg_has_role('pem_comp_' || name, 'member'::text) OR
                    pg_has_role('pem_agent', 'member'::text)
                )
        $SQL$;
        EXECUTE $SQL$
            CREATE POLICY pem_tool_team_support_update
                ON pem.tool
                FOR UPDATE
                USING (
                    pem.can_access_team(owner, team) OR
                    pg_has_role('pem_comp_' || name, 'member'::text) OR
                    pg_has_role('pem_agent', 'member'::text)
                )
                WITH CHECK (
                    pem.can_access_team(owner, team) OR
                    pg_has_role('pem_comp_' || name, 'member'::text) OR
                    pg_has_role('pem_agent', 'member'::text)
                )
        $SQL$;

        -- DELETE operation on pem.tool
        EXECUTE $SQL$
            CREATE POLICY pem_tool_team_support_delete
                ON pem.tool
                FOR DELETE
                USING (
                    pem.can_access_team(owner, team) OR
                    pg_has_role('pem_comp_' || name, 'member'::text) OR
                    pg_has_role('pem_agent', 'member'::text)
                )
        $SQL$;
        -- INSERT operation on pem.tool
        EXECUTE $SQL$
            CREATE POLICY pem_tool_team_support_insert
                ON pem.tool
                FOR INSERT
                WITH CHECK (
                    pg_has_role(
                        pem.current_user_id(), ('pem_comp_' || name)::name, 'member'::text
                    ) OR
                    pg_has_role('pem_agent', 'member'::text)
                )
        $SQL$;

    END IF;
END
$$ language 'plpgsql';

--
-- Add new Tool level
--
DO $DO$
BEGIN
    IF NOT EXISTS (SELECT display_name FROM pem.probe_target_type WHERE id = 150) THEN
        RAISE INFO '--- Adding new target type for tool level';
        INSERT INTO pem.probe_target_type VALUES (150, 'Tool');
    END IF;
END;
$DO$ LANGUAGE 'plpgsql';

--
-- Probe: Barman Configuration
--
DO $DO$
BEGIN
    IF NOT EXISTS (SELECT id FROM pem.probe where internal_name = 'barman_config') THEN
        INSERT INTO pem.probe
                (display_name, internal_name, collection_method, target_type_id,
                 agent_capability, enabled_by_default, force_enabled,
             default_execution_frequency, default_lifetime, any_server_version, probe_code)
        VALUES
                ('Barman Configuration', 'barman_config', 'i', 150,
                'barman_monitoring', false, false,
                10, 7, true, 'barman_config');

        INSERT INTO pem.probe_column
                (probe_id, internal_name, display_name, display_position, classification,
                sql_data_type, unit_of_value, calculate_pit, discard_history, pit_by_default, is_graphable)
        SELECT
                (SELECT max(id) FROM pem.probe),
                v.internal_name, v.display_name, v.display_position, v.classification,
                v.sql_data_type, v.unit_of_value, v.calculate_pit, v.discard_history, v.pit_by_default, v.is_graphable
        FROM
                (VALUES
                ('config',   'Config',          1, 'm', 'json',    '', false, false, false, false)
                ) v(internal_name, display_name, display_position, classification,
                        sql_data_type, unit_of_value, calculate_pit, discard_history, pit_by_default, is_graphable);
    END IF;
END;
$DO$ LANGUAGE 'plpgsql';

--
-- Probe: Barman information
--
DO $DO$
BEGIN
    IF NOT EXISTS (SELECT id FROM pem.probe where internal_name = 'barman_info') THEN
        INSERT INTO pem.probe
                (display_name, internal_name, collection_method, target_type_id,
                 agent_capability, enabled_by_default, force_enabled,
             default_execution_frequency, default_lifetime, any_server_version, probe_code)
        VALUES
                ('Barman Information', 'barman_info', 'i', 150,
                'barman_monitoring', false, false,
                10, 7, true, 'barman_info');

        INSERT INTO pem.probe_column
                (probe_id, internal_name, display_name, display_position, classification,
                sql_data_type, unit_of_value, calculate_pit, discard_history, pit_by_default, is_graphable)
        SELECT
                (SELECT max(id) FROM pem.probe),
                v.internal_name, v.display_name, v.display_position, v.classification,
                v.sql_data_type, v.unit_of_value, v.calculate_pit, v.discard_history, v.pit_by_default, v.is_graphable
        FROM
                (VALUES
                ('version',   'Version',          1, 'm', 'text',    '', false, false, false, false),
                ('info',   'Information',         2, 'm', 'json',    '', false, false, false, false)
                ) v(internal_name, display_name, display_position, classification,
                        sql_data_type, unit_of_value, calculate_pit, discard_history, pit_by_default, is_graphable);
    END IF;
END;
$DO$ LANGUAGE 'plpgsql';

DO $DO$
DECLARE
	p_probe_id int;
BEGIN
	SELECT id INTO p_probe_id FROM pem.probe WHERE internal_name = 'barman_info';

	IF EXISTS(SELECT id FROM pem.probe_column WHERE probe_id = p_probe_id AND internal_name = 'version' AND classification = 'k') THEN
		UPDATE pem.probe_column SET classification = 'm' WHERE probe_id = p_probe_id AND internal_name = 'version';
		UPDATE pem.probe SET probe_key_list = '{}'::text[] WHERE id = p_probe_id;
		DROP TABLE IF EXISTS pemdata.barman_info;
		DROP TABLE IF EXISTS pemhistory.barman_info;
	END IF;
END;
$DO$ LANGUAGE 'plpgsql';

--
-- Probe: Barman server
--
DO $DO$
BEGIN
    IF NOT EXISTS (SELECT id FROM pem.probe where internal_name = 'barman_server') THEN
        INSERT INTO pem.probe
                (display_name, internal_name, collection_method, target_type_id,
                 agent_capability, enabled_by_default, force_enabled,
             default_execution_frequency, default_lifetime, any_server_version, probe_code)
        VALUES
                ('Barman Server', 'barman_server', 'i', 150,
                'barman_monitoring', false, false,
                10, 7, true, 'barman_server');

        INSERT INTO pem.probe_column
                (probe_id, internal_name, display_name, display_position, classification,
                sql_data_type, unit_of_value, calculate_pit, discard_history, pit_by_default, is_graphable)
        SELECT
                (SELECT max(id) FROM pem.probe),
                v.internal_name, v.display_name, v.display_position, v.classification,
                v.sql_data_type, v.unit_of_value, v.calculate_pit, v.discard_history, v.pit_by_default, v.is_graphable
        FROM
                (VALUES
                ('server',   'Server Name',         1, 'k', 'text',    '', false, false, false, false),
                ('active',   'Active',              2, 'm', 'boolean',    '', false, false, false, false),
                ('config',   'Config',              3, 'm', 'json',    '', false, false, false, false)
                ) v(internal_name, display_name, display_position, classification,
                        sql_data_type, unit_of_value, calculate_pit, discard_history, pit_by_default, is_graphable);
    END IF;
END;
$DO$ LANGUAGE 'plpgsql';

--
-- Probe: Barman server status
--
DO $DO$
BEGIN
    IF NOT EXISTS (SELECT id FROM pem.probe where internal_name = 'barman_server_status') THEN
        INSERT INTO pem.probe
                (display_name, internal_name, collection_method, target_type_id,
                 agent_capability, enabled_by_default, force_enabled,
             default_execution_frequency, default_lifetime, any_server_version, probe_code)
        VALUES
                ('Barman Server Status', 'barman_server_status', 'i', 150,
                'barman_monitoring', false, false,
                10, 7, true, 'barman_server_status');

        INSERT INTO pem.probe_column
                (probe_id, internal_name, display_name, display_position, classification,
                sql_data_type, unit_of_value, calculate_pit, discard_history, pit_by_default, is_graphable)
        SELECT
                (SELECT max(id) FROM pem.probe),
                v.internal_name, v.display_name, v.display_position, v.classification,
                v.sql_data_type, v.unit_of_value, v.calculate_pit, v.discard_history, v.pit_by_default, v.is_graphable
        FROM
                (VALUES
                ('server',          'Server Name',          1, 'k', 'text',    '', false, false, false, false),
                ('status',          'Status',               2, 'm', 'json',    '', false, false, false, false)
                ) v(internal_name, display_name, display_position, classification,
                        sql_data_type, unit_of_value, calculate_pit, discard_history, pit_by_default, is_graphable);
    END IF;
END;
$DO$ LANGUAGE 'plpgsql';

--
-- Probe: Barman server backup
--
DO $DO$
BEGIN
    IF NOT EXISTS (SELECT id FROM pem.probe where internal_name = 'barman_server_backup') THEN
        INSERT INTO pem.probe
                (display_name, internal_name, collection_method, target_type_id,
                 agent_capability, enabled_by_default, force_enabled,
             default_execution_frequency, default_lifetime, any_server_version, probe_code)
        VALUES
                ('Barman Server Backup', 'barman_server_backup', 'i', 150,
                'barman_monitoring', false, false,
                10, 7, true, 'barman_server_backup');

        INSERT INTO pem.probe_column
                (probe_id, internal_name, display_name, display_position, classification,
                sql_data_type, unit_of_value, calculate_pit, discard_history, pit_by_default, is_graphable)
        SELECT
                (SELECT max(id) FROM pem.probe),
                v.internal_name, v.display_name, v.display_position, v.classification,
                v.sql_data_type, v.unit_of_value, v.calculate_pit, v.discard_history, v.pit_by_default, v.is_graphable
        FROM
                (VALUES
                ('backup_id',     'Backup ID',              1, 'k', 'text',    '', false, false, false, false),
                ('server',        'Server Name',            2, 'k', 'text',    '', false, false, false, false),
                ('begin_time',    'Begin Time',             3, 'm', 'timestamp',    '', false, false, false, false),
                ('end_time',      'End Time',               4, 'm', 'timestamp',    '', false, false, false, false),
                ('size',          'Size',                   5, 'm', 'bigint',    '', false, false, false, false),
                ('mode',          'Mode',                   6, 'm', 'text',    '', false, false, false, false),
                ('status',        'Status',                 7, 'm', 'text',    '', false, false, false, false),
                ('error',         'Error',                  8, 'm', 'text',    '', false, false, false, false),
                ('data',          'Details',                9, 'm', 'json',    '', false, false, false, false)
                ) v(internal_name, display_name, display_position, classification,
                        sql_data_type, unit_of_value, calculate_pit, discard_history, pit_by_default, is_graphable);
    END IF;
END;
$DO$ LANGUAGE 'plpgsql';

--
-- Probe: Barman server WAL status
--
DO $DO$
BEGIN
    IF NOT EXISTS (SELECT id FROM pem.probe where internal_name = 'barman_server_wal_status') THEN
        INSERT INTO pem.probe
                (display_name, internal_name, collection_method, target_type_id,
                 agent_capability, enabled_by_default, force_enabled,
             default_execution_frequency, default_lifetime, any_server_version, probe_code)
        VALUES
                ('Barman Server WAL Status', 'barman_server_wal_status', 'i', 150,
                'barman_monitoring', false, false,
                10, 7, true, 'barman_server_wal_status');

        INSERT INTO pem.probe_column
                (probe_id, internal_name, display_name, display_position, classification,
                sql_data_type, unit_of_value, calculate_pit, discard_history, pit_by_default, is_graphable)
        SELECT
                (SELECT max(id) FROM pem.probe),
                v.internal_name, v.display_name, v.display_position, v.classification,
                v.sql_data_type, v.unit_of_value, v.calculate_pit, v.discard_history, v.pit_by_default, v.is_graphable
        FROM
                (VALUES
                ('server',                              'Server Name',             1, 'k', 'text',    '', false, false, false, false),
                ('last_archived_wal_per_timeline',      'Last Archived WAL Per Timeline',           2, 'm', 'json',    '', false, false, false, false)
                ) v(internal_name, display_name, display_position, classification,
                        sql_data_type, unit_of_value, calculate_pit, discard_history, pit_by_default, is_graphable);
    END IF;
END;
$DO$ LANGUAGE 'plpgsql';

-- Probe column definition view
CREATE OR REPLACE VIEW pem.probe_column_definition AS
SELECT
	id AS probe_id,
	'recorded_time'::text AS quoted_name,
	'timestamp with time zone not null DEFAULT now()'::text AS column_definition,
	'r'::text AS classification,
	-6::integer AS display_position,
	false::boolean AS calculate_pit,
	false::boolean AS discard_history
FROM
	pem.probe
UNION ALL
SELECT
	id AS probe_id,
	'agent_id'::text AS quoted_name,
	'integer not null REFERENCES pem.agent (id) ON UPDATE RESTRICT ON DELETE CASCADE'::text AS column_definition,
	'k'::text AS classification,
	-5::integer AS display_position,
	false::boolean AS calculate_pit,
	false::boolean AS discard_history
FROM
	pem.probe
WHERE
	target_type_id = 100
UNION ALL
SELECT
	id AS probe_id,
	'tool_id'::text AS quoted_name,
	'integer not null REFERENCES pem.tool (id) ON UPDATE RESTRICT ON DELETE CASCADE'::text AS column_definition,
	'k'::text AS classification,
	-4::integer AS display_position,
	false::boolean AS calculate_pit,
	false::boolean AS discard_history
FROM
	pem.probe
WHERE
	target_type_id = 150
UNION ALL
SELECT
	id AS probe_id,
	'server_id'::text AS quoted_name,
	'integer not null REFERENCES pem.server (id) ON UPDATE RESTRICT ON DELETE CASCADE'::text AS column_definition,
	'k'::text AS classification,
	-4::integer AS display_position,
	false::boolean AS calculate_pit,
	false::boolean AS discard_history
FROM
	pem.probe
WHERE
	target_type_id != 100 AND target_type_id != 150
UNION ALL
SELECT
	id AS probe_id,
	'database_name'::text AS quoted_name,
	'text not null'::text AS column_definition,
	'k'::text AS classification,
	-3::integer AS display_position,
	false::boolean AS calculate_pit,
	false::boolean AS discard_history
FROM
	pem.probe
WHERE
	target_type_id >= 300
UNION ALL
SELECT
	id AS probe_id,
	'schema_name'::text AS quoted_name,
	'text not null'::text AS column_definition,
	'k'::text AS classification,
	-2::integer AS display_position,
	false::boolean AS calculate_pit,
	false::boolean AS discard_history
FROM
	pem.probe
WHERE
	target_type_id >= 400 AND target_type_id != 1000
UNION ALL
SELECT
	probe.id AS probe_id,
	lower(probe_target_type.display_name) || '_name' AS quoted_name,
	'text not null'::text AS column_definition,
	'k'::text AS classification,
	-1::integer AS display_position,
	false::boolean AS calculate_pit,
	false::boolean AS discard_history
FROM
	pem.probe, pem.probe_target_type
WHERE
	probe.target_type_id = probe_target_type.id
	AND target_type_id IN (500,600,700,800,900)
UNION ALL
SELECT
	probe_id,
	quote_ident(internal_name) AS quoted_name,
	sql_data_type || CASE WHEN classification = 'k' THEN ' NOT NULL'
		ELSE '' END AS column_definition,
	classification,
	display_position,
	calculate_pit,
	discard_history
FROM
	pem.probe_column;

--
-- Add new table to store extension version specific probe details
--
DO $$
BEGIN
	IF NOT EXISTS(
        SELECT * FROM information_schema.tables
        WHERE  table_schema = 'pem'
        AND    table_name   = 'probe_config_tool'
	) THEN
		RAISE INFO '--- Adding new new table pem.probe_config_tool';
        CREATE TABLE pem.probe_config_tool (
            probe_id			integer NOT NULL
                REFERENCES pem.probe (id) ON UPDATE RESTRICT ON DELETE CASCADE,
            tool_id			integer NOT NULL
                REFERENCES pem.tool (id) ON UPDATE RESTRICT ON DELETE CASCADE,
            enabled				boolean,
            execution_frequency	integer,
            lifetime		integer,
            CONSTRAINT probe_config_tool_pkey
                PRIMARY KEY (probe_id, tool_id)
        );
	END IF;
END;
$$ LANGUAGE plpgsql;

DROP VIEW IF EXISTS pem.probe_target_tool_view CASCADE;

--
-- View to fetch tool level probes
--
CREATE OR REPLACE VIEW pem.probe_target_tool_view AS
SELECT
	p.id AS probe_id, p.display_name AS probe_display_name,
	p.internal_name AS probe_internal_name, p.probe_key_list,
	p.applies_to_id,
	a.id AS agent_id, NULL::integer AS server_id, NULL::text AS database_name,
	ARRAY['tool_id']::text[] AS parameter_name_list,
	ARRAY[b.tool_id::text]::text[] AS parameter_value_list,
	p.collection_method,
	p.probe_code AS probe_code,
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
	CROSS JOIN pem.agent_tool_binding b
	INNER JOIN pem.agent a ON b.agent_id = a.id
	INNER JOIN pem.tool t ON b.tool_id = t.id
	LEFT JOIN pem.probe_config_tool c
		ON p.id = c.probe_id AND b.tool_id = c.tool_id
WHERE
	p.target_type_id = 150
	AND NOT p.deleted
	AND (p.agent_capability IS NULL
		OR p.agent_capability = ANY(a.agent_capability_list));

--
-- Create tables required by probe
--
DO $DO$
BEGIN
    PERFORM pem.create_data_and_history_tables();
END;
$DO$ LANGUAGE 'plpgsql';

-- This view shows every possible combination of (1) a probe, and (2) a known
-- monitoring target to which that probe could be applied.
-- Here, we have appended the probes for extension target level (target_type_id = 1000) which were not present earlier
CREATE OR REPLACE VIEW pem.probe_target_view AS
SELECT
	p.id AS probe_id, p.display_name AS probe_display_name,
	p.internal_name AS probe_internal_name, p.probe_key_list,
	p.applies_to_id,
	a.id AS agent_id, NULL::integer AS server_id, NULL::text AS database_name,
	ARRAY['agent_id']::text[] AS parameter_name_list,
	ARRAY[a.id::text]::text[] AS parameter_value_list,
	p.collection_method, p.probe_code, p.enabled_by_default,
	p.default_execution_frequency,
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
	CROSS JOIN pem.agent a
	LEFT JOIN pem.probe_config_agent c
		ON p.id = c.probe_id AND a.id = c.agent_id
WHERE
	p.target_type_id = 100
	AND NOT p.deleted
	AND (p.agent_capability IS NULL
		OR p.agent_capability = ANY(a.agent_capability_list))
	AND ((p.collection_method NOT IN ('b', 'w')) OR
		(p.collection_method ='b' AND (a.agent_capability_list @> ARRAY['allow_batch_probes'])
			AND ((strpos(a.platform, p.platform) != 0) OR (a.platform !~ 'windows' AND p.platform = 'unix'))) OR
		(p.collection_method = 'w' AND strpos(a.platform, 'windows') != 0))
UNION ALL
SELECT
	p.id AS probe_id, p.display_name AS probe_display_name,
	p.internal_name AS probe_internal_name, p.probe_key_list,
	p.applies_to_id,
	a.id AS agent_id, b.server_id, b.database AS database_name,
	ARRAY['server_id']::text[] AS parameter_name_list,
	ARRAY[b.server_id::text]::text[] AS parameter_value_list,
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
	INNER JOIN pem.server s ON b.server_id = s.id
	LEFT JOIN pemdata.server_info sd ON b.server_id = sd.server_id
	LEFT JOIN pem.probe_server_version psv
		ON p.id = psv.probe_id
		AND sd.server_version_id = psv.server_version_id
	LEFT JOIN pem.probe_config_server c
		ON p.id = c.probe_id AND b.server_id = c.server_id
WHERE
	p.target_type_id = 200
	AND NOT p.deleted
	AND (p.agent_capability IS NULL
		OR p.agent_capability = ANY(a.agent_capability_list))
	AND (p.any_server_version OR psv.probe_id IS NOT NULL)
	AND p.internal_name NOT IN( SELECT UNNEST(CASE WHEN s.is_remote_monitoring THEN ARRAY['pg_hba_conf', 'data_log_file_analysis', 'wal_archive_status', 'log_configuration', 'efm_cluster_node_status', 'efm_cluster_info'] ELSE ARRAY[''] END))
	AND p.internal_name NOT IN( SELECT UNNEST(CASE WHEN a.agent_capability_list @> ARRAY['windows'] THEN ARRAY['efm_cluster_node_status', 'efm_cluster_info'] ELSE ARRAY[''] END))
	AND (p.collection_method != 'b' OR
		(p.collection_method ='b' AND (a.agent_capability_list @> ARRAY['allow_batch_probes'])
			AND ((strpos(a.platform, p.platform) != 0) OR (a.platform !~ 'windows' AND p.platform = 'unix'))))
	AND b.database NOT IN (SELECT UNNEST(b.exclude_databases))
UNION ALL
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
	INNER JOIN pemdata.oc_database ocd
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
	AND ocd.database_name NOT IN (SELECT UNNEST(b.exclude_databases))
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
	INNER JOIN pemdata.oc_database ocd
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
	AND oc.database_name NOT IN (SELECT UNNEST(b.exclude_databases))
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
	INNER JOIN pemdata.oc_database ocd
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
	AND oc.database_name NOT IN (SELECT UNNEST(b.exclude_databases))
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
	INNER JOIN pemdata.oc_database ocd
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
	AND oc.database_name NOT IN (SELECT UNNEST(b.exclude_databases))
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
	INNER JOIN pemdata.oc_database ocd
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
	AND oc.database_name NOT IN (SELECT UNNEST(b.exclude_databases))
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
	INNER JOIN pemdata.oc_database ocd
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
	AND oc.database_name NOT IN (SELECT UNNEST(b.exclude_databases))
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
	INNER JOIN pemdata.oc_database ocd
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
			AND ((strpos(a.platform, p.platform) != 0) OR (a.platform !~ 'windows' AND p.platform = 'unix'))))
	AND oc.database_name NOT IN (SELECT UNNEST(b.exclude_databases))
UNION ALL
SELECT *
FROM pem.probe_target_extension_view
UNION ALL
SELECT *
FROM pem.probe_target_tool_view;

DROP FUNCTION IF EXISTS pem.do_heartbeat(integer, integer[]);

CREATE OR REPLACE FUNCTION pem.do_heartbeat(
    p_agentId                  integer,
    p_serverIDs                integer[],
    p_missedHeartbeatsForTools integer[] = '{}'::integer[]
)
RETURNS void AS $$
DECLARE
    idx integer;
BEGIN
    -- perform heartbeat only when agent is active.
    IF ((SELECT active FROM pem.agent WHERE id = p_agentId) IS NOT TRUE) THEN
        RETURN;
    END IF;

    UPDATE pem.agent_heartbeat
        SET last_heartbeat = now()
        WHERE agent_id = p_agentId;

    IF (NOT FOUND) THEN
        INSERT INTO pem.agent_heartbeat VALUES(p_agentId, now());
    END IF;

    FOR idx in 1..COALESCE(array_upper(p_serverIDs, 1), 0) LOOP
        UPDATE pem.server_heartbeat
            SET last_heartbeat = now()
            WHERE agent_id = p_agentId AND server_id = p_serverIDs[idx];

        IF (NOT FOUND) THEN
		    -- it is possible that agent-server binding is broken by now.
		    IF EXISTS(SELECT * FROM pem.agent_server_binding WHERE agent_id = p_agentId) THEN
                INSERT INTO pem.server_heartbeat
                    SELECT asb.agent_id, asb.server_id, now()
                    FROM pem.agent_server_binding asb
                    WHERE asb.agent_id = p_agentId AND
                        asb.server_id = p_serverIDs[idx];
            END IF;
        END IF;
    END LOOP;

    FOR idx in 1..COALESCE(array_upper(p_missedHeartbeatsForTools, 1), 0) LOOP
        IF EXISTS(
            SELECT agent_id FROM pem.agent_tool_binding
            WHERE agent_id = p_agentId
                AND tool_id = p_missedHeartbeatsForTools[idx]
        ) THEN
            INSERT INTO pem.tool_heartbeat (
                agent_id, tool_id, missing_heartbeat_at
            ) VALUES (
                p_agentId, p_missedHeartbeatsForTools[idx], now()
            ) ON CONFLICT DO NOTHING;
        END IF;
    END LOOP;

    -- Mark all the tools available, for which missing-heartbeat is not
    -- reported.
    DELETE FROM pem.tool_heartbeat
    WHERE agent_id = p_agentId
        AND NOT (tool_id = ANY(p_missedHeartbeatsForTools));
END;
$$ LANGUAGE plpgsql;

-- This view shows the probes that need to run.
CREATE OR REPLACE VIEW pem.probe_schedule_view AS
SELECT
	t.probe_id, t.probe_internal_name, t.probe_key_list,
	t.agent_id, t.server_id,
	t.database_name, t.parameter_name_list, t.parameter_value_list,
	t.collection_method, t.probe_code, s.last_execution_time
FROM
	pem.probe_target_view t
	LEFT JOIN pem.probe_schedule s ON t.probe_id = s.probe_id
		AND t.parameter_value_list = s.parameter_value_list
WHERE
	t.enabled
	AND t.agent_active
	AND s.current_backend_pid IS NULL
	AND (s.last_execution_time IS NULL
		OR to_timestamp(
			((extract(epoch from s.last_execution_time)::bigint
				+ t.execution_frequency - 1) / NULLIF(t.execution_frequency, 0))
			* t.execution_frequency + (s.random_seed % NULLIF(t.execution_frequency, 0)))
				< now());

-- PEM-4356
-- 'PG extended' returns two entries for 'snapshot_timestamp_timeout' in the pg_settings view.
UPDATE pem.probe
    SET probe_code = 'SELECT DISTINCT ON (name) name, setting, unit FROM pg_catalog.pg_settings'
    WHERE internal_name = 'settings';

-- PEM-4333
UPDATE pem.probe
    SET probe_code = $sql$
SELECT
    DISTINCT ON (blocked_pid, locktype, blocking_pid)
    blocked_locks.pid AS blocked_pid,
    blocked_activity.usename AS blocked_user,
    blocked_locks.mode       AS locktype,
    blocking_locks.pid AS blocking_pid,
    blocking_activity.usename AS blocking_user,
    blocking_activity.datname AS database_name,
    now() - blocking_activity.query_start AS blocking_duration,
    now() - blocked_activity.query_start  AS blocked_duration,
    blocking_activity.query_start         AS blocking_query_start,
    blocked_activity.query_start          AS blocked_query_start,
    blocked_activity.query AS blocked_statement,
    blocking_activity.query AS current_statement_in_blocking_process,
    blocked_activity.application_name AS blocked_application,
    blocking_activity.application_name AS blocking_application
FROM pg_catalog.pg_locks blocked_locks
JOIN pg_catalog.pg_stat_activity blocked_activity ON blocked_activity.pid = blocked_locks.pid
JOIN pg_catalog.pg_locks blocking_locks ON blocking_locks.locktype = blocked_locks.locktype AND
    blocking_locks.DATABASE IS NOT DISTINCT FROM blocked_locks.DATABASE AND
    blocking_locks.relation IS NOT DISTINCT FROM blocked_locks.relation AND
    blocking_locks.page IS NOT DISTINCT FROM blocked_locks.page AND
    blocking_locks.tuple IS NOT DISTINCT FROM blocked_locks.tuple AND
    blocking_locks.virtualxid IS NOT DISTINCT FROM blocked_locks.virtualxid AND
    blocking_locks.transactionid IS NOT DISTINCT FROM blocked_locks.transactionid AND
    blocking_locks.classid IS NOT DISTINCT FROM blocked_locks.classid AND
    blocking_locks.objid IS NOT DISTINCT FROM blocked_locks.objid AND
    blocking_locks.objsubid IS NOT DISTINCT FROM blocked_locks.objsubid AND
    blocking_locks.pid != blocked_locks.pid
JOIN pg_catalog.pg_stat_activity blocking_activity ON blocking_activity.pid = blocking_locks.pid
WHERE NOT blocked_locks.GRANTED$sql$
    WHERE internal_name = 'blocked_session_info';

UPDATE pem.probe_server_version
    SET probe_code = $sql$
SELECT
	DISTINCT ON (blocked_pid, locktype, blocking_pid)
	blocked_activity.pid                     AS blocked_pid,
	blocked_activity.usename                 AS blocked_user,
	blocked.mode                             AS locktype,
	blocking_activity.pid                    AS blocking_pid,
	blocking_activity.usename                AS blocking_user,
	blocking_activity.datname                AS database_name,
	now() - blocking_activity.query_start    AS blocking_duration,
	now() - blocked_activity.query_start     AS blocked_duration,
	blocking_activity.query_start            AS blocking_query_start,
	blocked_activity.query_start             AS blocked_query_start,
	blocked_activity.query                   AS blocked_statement,
	blocking_activity.query                  AS current_statement_in_blocking_process,
	blocked_activity.application_name        AS blocked_application,
	blocking_activity.application_name       AS blocking_application
FROM pg_catalog.pg_stat_activity AS blocked_activity
JOIN pg_catalog.pg_stat_activity AS blocking_activity ON blocking_activity.pid = ANY (pg_blocking_pids(blocked_activity.pid))
JOIN pg_catalog.pg_locks AS blocked ON blocked.pid = blocked_activity.pid
WHERE NOT blocked.granted$sql$
WHERE probe_id = (SELECT id FROM pem.probe WHERE internal_name = 'blocked_session_info')
        AND probe_code IS NOT NULL;

--
-- PEM-806 - Remove filesystem mount which has '0' size from the table charts
--
-- Agent level chart: Host Details
UPDATE pem.chart_func SET func = '
SELECT
    file_system AS "File System",
    ROUND((size_mb::float/1024)::numeric,2) AS "Size (GB)",
    ROUND((space_used_mb::float/1024)::numeric,2) AS "Used (GB)",
    ROUND((space_available_mb::float/1024)::numeric,2) AS "Available (GB)",
    ROUND((space_used_mb::float * 100/(size_mb - COALESCE(space_reserved_mb, 0)))::numeric,2) AS "%Used",
    CASE WHEN (device_id is NOT NULL and device_id != '''') THEN mount_point || '' ('' || device_id || '')'' ELSE mount_point END AS "Mounted On"
FROM pemdata.disk_space
WHERE agent_id = $1::int4
AND size_mb != 0
ORDER BY 3::int DESC'
WHERE id = 44;

-- Database server > Storage level chart: Host File System Details
UPDATE pem.chart_func SET func = '
SELECT
    file_system AS "File System",
    ROUND((size_mb::float/1024)::numeric,2) AS "Size (GB)",
    ROUND((space_used_mb::float/1024)::numeric,2) AS "Used (GB)",
    ROUND((space_available_mb::float/1024)::numeric,2) AS "Available (GB)",
    ROUND((space_used_mb::float * 100/(size_mb - COALESCE(space_reserved_mb, 0)))::numeric,2) AS "%Used",
    CASE WHEN (device_id is NOT NULL and device_id != '''') THEN mount_point || '' ('' || device_id || '')'' ELSE mount_point END AS "Mounted On"
FROM pemdata.disk_space
WHERE agent_id = $1::int4
AND size_mb != 0
ORDER BY 3::int DESC'
WHERE id = 73;

-- Make tablespace_oid column to bigint[] type
ALTER TABLE pem.bart_backups
    ALTER COLUMN tablespace_oid TYPE bigint[];

ALTER TABLE pem.bart_restore_config
    ALTER COLUMN tablespace_oid TYPE bigint[];

-- Move BDR probes custom configuration form server level to extension level
DO $DO$
BEGIN
    IF NOT EXISTS (SELECT probe_id FROM pem.probe_config_extension) THEN
        INSERT INTO pem.probe_config_extension(
            probe_id, server_id, database_name, extension_name, enabled, execution_frequency, lifetime
        ) SELECT probe_id,
            server_id,
            ( SELECT COALESCE(asb.database, s.database)
                FROM pem.server s LEFT JOIN pem.agent_server_binding asb ON asb.server_id = s.id WHERE s.id = pcs.server_id
            ) AS database_name,
            'bdr' AS extension_name,
            enabled,
            execution_frequency,
            lifetime
        FROM pem.probe_config_server pcs
        WHERE probe_id IN (SELECT id FROM pem.probe WHERE internal_name LIKE 'bdr_%' AND is_system_probe);
    END IF;
END;
$DO$ LANGUAGE 'plpgsql';


END TRANSACTION;
