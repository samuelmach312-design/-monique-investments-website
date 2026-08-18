/***************************************************************************
 *
 * Postgres Enterprise Manager
 *
 * Copyright (C) 2010 - 2025, EnterpriseDB Corporation. All rights reserved.
 *
 ***************************************************************************/

-- NOTE: This sql file is responsible for PEM 10.1.1 schema upgrade.

BEGIN TRANSACTION;
    CREATE
    OR REPLACE FUNCTION pem.schema_version()
    RETURNS integer AS 'SELECT 202507071::integer;' LANGUAGE 'sql' IMMUTABLE;
    COMMENT ON FUNCTION pem.schema_version()
    IS 'Returns the version number of the PEM schema';

-- PEM-5602: Updating the server connection params to the default values
DO $$
BEGIN
    IF EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_schema = 'pem'
          AND table_name = 'server_options'
          AND column_name = 'connect_timeout'
    ) AND EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_schema = 'pem'
          AND table_name = 'server'
          AND column_name = 'ssl'
          ) THEN
        -- Do the full update including connect_timeout
        UPDATE pem.server_options so
        SET connection_params = jsonb_build_object(
            'sslmode',
            COALESCE(
                CASE s.ssl
                    WHEN 1 THEN 'allow'
                    WHEN 2 THEN 'prefer'
                    WHEN 3 THEN 'require'
                    WHEN 4 THEN 'disable'
                    WHEN 5 THEN 'verify-ca'
                    WHEN 6 THEN 'verify-full'
                END,
                'prefer'
            ),
            'connect_timeout', COALESCE(connect_timeout, 10)
        )
        FROM pem.server s
        WHERE so.server_id = s.id
          AND (
              so.connection_params IS NULL
              OR so.connection_params = '{}'::jsonb
          );
    END IF;
END$$;

CREATE OR REPLACE FUNCTION pem.startup(server_desc text, server_name text, server_host text, server_port int, server_database text,
					user_name text, passwd text, ser_group text, agentid int, agent_database text)
	RETURNS void AS
$BODY$
DECLARE
	sg_id     integer;
	serverid  integer := 1;
	is_active boolean;
	name      text;
	probe_curs CURSOR FOR SELECT id, display_name FROM pem.probe
		WHERE NOT discard_history AND jstid IS NULL;
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
			description, server, port, database
		) VALUES (
			server_desc, server_name, server_port, server_database
		) RETURNING id INTO serverid;

		-- Set the options of the PEM server
		INSERT INTO pem.server_options (
			server_id, pem_user, server_group_id, username, connection_params
		) VALUES (
			serverid, user_name, sg_id, user_name,
			jsonb_build_object(
		        'sslmode', 'prefer',
		        'connect_timeout', 10
	        )
		);

		-- Set the options of the PEM server auth table
		INSERT INTO pem.server_auth (server_id, pem_user) VALUES (serverid, user_name);

	ELSE
		UPDATE pem.server SET
			description = server_desc,
			server = server_name,
			port = server_port,
			database = server_database,
			active = 't'
		WHERE id = serverid;

		UPDATE pem.server_options SET
			pem_user = user_name,
			server_group_id = sg_id,
			username = user_name,
			connection_params = jsonb_build_object(
		        'sslmode', 'prefer',
		        'connect_timeout', 10
			)
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

DROP VIEW IF EXISTS pem.avail_servers;
CREATE OR REPLACE VIEW pem.avail_servers AS
	SELECT
		s.id AS id,
		s.description AS description,
		s.server AS server,
		s.port AS port,
		s.database AS database,
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

ALTER TABLE pem.server
DROP COLUMN IF EXISTS ssl;

ALTER TABLE pem.server_options
DROP COLUMN IF EXISTS connect_timeout;

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

	-- There are not email groups for the email to send.
	IF COALESCE(array_length(mail_group_id, 1), 0) = 0 THEN
		RETURN false;
	END IF;

	IF is_smtp_enabled THEN
		-- iterate through all the group id's and insert into the spool table
		FOR i in 1..COALESCE(array_upper(mail_group_id, 1), 0) LOOP

			-- Clear the email address array before any operations.
			mail_to := '{}';
			mail_cc := '{}';
			mail_bcc := '{}';
			mail_reply_to := '{}';

			-- Get email details
			-- iterate through all time intervals for a particular group and
			-- check time against server's current time and send mail to only
			-- those addresses for which current time lies within their interval
			FOR tmp_row IN SELECT grp_to, grp_cc, grp_bcc, grp_from, grp_reply_to, grp_subject_prefix, (EXTRACT(EPOCH FROM time_from) + EXTRACT(TIMEZONE FROM time_from)) as time_from, (EXTRACT(EPOCH FROM time_to) + EXTRACT(TIMEZONE FROM time_to)) as time_to FROM pem.email_group_option WHERE gid = mail_group_id[i]
			LOOP

				-- If 'FROM' is not available, we won't be to send the email.
				CONTINUE WHEN tmp_row.grp_from = '';

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

			mail_to_str := array_to_string(array_remove(array_remove(mail_to, ''), NULL), ',');
			mail_cc_str := array_to_string(array_remove(array_remove(mail_cc, ''), NULL), ',');
			mail_bcc_str := array_to_string(array_remove(array_remove(mail_bcc, ''), NULL), ',');
			mail_reply_to_str := array_to_string(array_remove(array_remove(mail_reply_to, ''), NULL), ',');

			-- We won't be able to send an email if all TO, CC and BCC are not available.
			CONTINUE WHEN mail_to_str = '' AND mail_cc_str = '' AND mail_bcc_str = '';

			IF COALESCE(mail_subject_prefix, '') <> '' THEN
				subject := mail_subject_prefix || ': ' || subject;
			END IF;

			-- Insert the spool record
			INSERT INTO pem.smtp_spool(
				mail_to, mail_cc, mail_bcc, mail_reply_to, mail_from,
				subject, message, sent_status
			) VALUES(
				mail_to_str, mail_cc_str, mail_bcc_str, mail_reply_to_str, mail_from_str,
				subject, message, 'u'
			);

			is_notify = true;

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

-- ==================================
-- Probe: Patroni Node Status
-- ==================================
DO $DO$
BEGIN
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

END TRANSACTION;