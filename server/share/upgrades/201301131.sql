/*
// Postgres Enterprise Manager
//
// Copyright (C) 2010 - 2025, EnterpriseDB Corporation. All rights reserved.
//
// Portions of Postgres Enteprise Manager are derived from pgAgent, which is
// released under the PostgreSQL License.
// Copyright (C) 2002 - 2010 The pgAdmin Development Team
//
*/

-- Upgrade script for v3.0.0 GA to v4.0.0a1

BEGIN TRANSACTION;

-- Update the schema version
CREATE OR REPLACE FUNCTION pem.schema_version()
  RETURNS integer AS
'SELECT 201301131::integer;'
  LANGUAGE 'sql' IMMUTABLE;
COMMENT ON FUNCTION pem.schema_version() IS 'Returns the version number of the PEM schema';

-- Add the agent version to pem.agent, and add some missing comments.
ALTER TABLE pem.agent ADD COLUMN version text NOT NULL DEFAULT 'Unknown';
-- Add the agent OS platform to pem.agent.
ALTER TABLE pem.agent ADD COLUMN platform text NOT NULL DEFAULT 'Unknown';
COMMENT ON TABLE pem.agent IS 'Agent registrations';
COMMENT ON COLUMN pem.agent.id IS 'Agent unique identifier';
COMMENT ON COLUMN pem.agent.agent_capability_list IS 'Array of capabilities the agent has';
COMMENT ON COLUMN pem.agent.description IS 'Description of the agent';
COMMENT ON COLUMN pem.agent.active IS 'Is the agent active (or deleted)?';
COMMENT ON COLUMN pem.agent.heartbeat_interval IS 'The interval between heartbeats, in seconds';
COMMENT ON COLUMN pem.agent.version IS 'Agent version number';
COMMENT ON COLUMN pem.agent.platform IS 'Operating system on which agent is running';

/******************
 * Update Monitor *
 ******************/
ALTER TABLE pem.probe ADD COLUMN discard_history boolean NOT NULL DEFAULT false;

CREATE TYPE pem.pkg_installed_state AS ENUM(
	'MARKED_FOR_INSTALLATION',
	'INSTALLATION_STARTED',
	'INSTALLATION_FAILED',
	'INSTALLED'
);

CREATE TABLE pem.package_installation (
	agent_id 			integer NOT NULL REFERENCES pem.agent(id)
						ON UPDATE RESTRICT ON DELETE CASCADE,
	pkg_id 				text NOT NULL,
	pkg_version			text NOT NULL,
	installation_state  pem.pkg_installed_state NOT NULL DEFAULT 'MARKED_FOR_INSTALLATION',
	optionfilecommand	text,
	unattendedcommand	text,
	database_server		text,
	server_version		text,

	CONSTRAINT package_installation_pkey PRIMARY KEY (agent_id, pkg_id, pkg_version)
);

GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE pem.package_installation TO pem_agent;

CREATE TABLE pem.package_options (
	agent_id 			integer NOT NULL REFERENCES pem.agent(id)
						ON UPDATE RESTRICT ON DELETE CASCADE,
	pkg_id 				text NOT NULL,
	pkg_version			text NOT NULL,
	option_name			text NOT NULL,
	option_value		text,
	option_type			text,
	option_separator	text,
	option_status 		char NOT NULL,
	is_encrypted		boolean,

	CONSTRAINT package_options_pkey PRIMARY KEY (agent_id, pkg_id, pkg_version, option_name),
	CONSTRAINT package_options_option_status CHECK (option_status IN ('O', 'R', 'F')),
	CONSTRAINT package_options_fkey_comb FOREIGN KEY (agent_id, pkg_id, pkg_version) REFERENCES pem.package_installation (agent_id, pkg_id, pkg_version) MATCH SIMPLE ON UPDATE RESTRICT ON DELETE CASCADE
);

CREATE TYPE pem.pkg_download_state AS ENUM(
	'COMPLETE',
	'MARKED_FOR_DOWNLOAD'
);

--
-- Probe: package_catalog
--

INSERT INTO pem.probe
	(display_name, internal_name, collection_method, target_type_id,
	 agent_capability, enabled_by_default, force_enabled,
     default_execution_frequency, default_lifetime, any_server_version, probe_code, discard_history)
VALUES
	('Package Catalog', 'package_catalog', 'i', 100, 'package_catalog', true, false, 86400,
	  180, true, 'package_catalog', true);

INSERT INTO pem.probe_column
	(probe_id, internal_name, display_name, display_position, classification,
	sql_data_type, unit_of_value, calculate_pit, discard_history, pit_by_default, is_graphable)
SELECT
	(SELECT max(id) FROM pem.probe),
	v.internal_name, v.display_name, v.display_position, v.classification,
	v.sql_data_type, v.unit_of_value, v.calculate_pit, v.discard_history, v.pit_by_default, v.is_graphable
FROM
	(VALUES
		('pkg_id', 'Package ID', 1, 'k', 'text', '', false, false, false, false),
		('name', 'Package Name', 2, 'm', 'text', '', false, false, false, false),
		('platform', 'Platform', 3, 'k', 'text', '', false, false, false, false),
		('secondary_platform', 'Secondary Platform', 4, 'm', 'text', '', false, false, false, false),
		('version', 'Package Version', 5, 'k', 'text', '', false, false, false, false),
		('versionkey', 'Package Version Key', 6, 'm', 'text', '', false, false, false, false),
		('installoptions', 'Install Options', 7, 'm', 'text', '', false, false, false, false),
		('upgradeoptions', 'Upgrade Options', 8, 'm', 'text', '', false, false, false, false),
		('checksum', 'CheckSum', 9, 'm', 'text', '', false, false, false, false),
		('mirror_path', 'Mirror Path', 10, 'm', 'text', '', false, false, false, false),
		('alturl', 'Package URL', 11, 'm', 'text', '', false, false, false, false),
		('edbversion', 'EDB Version', 12, 'm', 'text', '', false, false, false, false),
		('pgversion', 'PG Version', 13, 'm', 'text', '', false, false, false, false),
		('category', 'PG Version', 14, 'm', 'text', '', false, false, false, false),
		('description', 'Package Description', 15, 'm', 'text', '', false, false, false, false),
		('format', 'Package Format', 16, 'm', 'text', '', false, false, false, false),
		('dependency', 'Package Dependency', 17, 'm', 'text', '', false, false, false, false),
		('manifesturl', 'Package Manifest File', 18, 'm', 'text', '', false, false, false, false),
		('package_download_state', 'Package Download State', 19, 'm', 'pem.pkg_download_state', '', false, false, false, false),
		('package_installer', 'Package Installer', 20, 'm', 'bytea', '', false, false, false, false)
	) v(internal_name, display_name, display_position, classification,
		sql_data_type, unit_of_value, calculate_pit, discard_history, pit_by_default, is_graphable);

--
-- Probe: installed_packages
--

INSERT INTO pem.probe
	(display_name, internal_name, collection_method, target_type_id,
	 agent_capability, enabled_by_default, force_enabled,
     default_execution_frequency, default_lifetime, any_server_version, probe_code, discard_history)
VALUES
	('Installed Packages', 'installed_packages', 'i', 100, 'installed_packages', true, false, 86400,
	  180, true, 'installed_packages', true);

INSERT INTO pem.probe_column
	(probe_id, internal_name, display_name, display_position, classification,
	sql_data_type, unit_of_value, calculate_pit, discard_history, pit_by_default, is_graphable)
SELECT
	(SELECT max(id) FROM pem.probe),
	v.internal_name, v.display_name, v.display_position, v.classification,
	v.sql_data_type, v.unit_of_value, v.calculate_pit, v.discard_history, v.pit_by_default, v.is_graphable
FROM
	(VALUES
		('pkg_id', 'Package ID', 1, 'k', 'text', '', false, false, false, false),
		('name', 'Package Name', 2, 'm', 'text', '', false, false, false, false),
		('platform', 'Platform', 3, 'k', 'text', '', false, false, false, false),
		('version', 'Package Version', 4, 'k', 'text', '', false, false, false, false)
	) v(internal_name, display_name, display_position, classification,
		sql_data_type, unit_of_value, calculate_pit, discard_history, pit_by_default, is_graphable);

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
    FOR table_name IN curs_table LOOP
	    quoted_table_name := quote_ident(table_name.internal_name);

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
				probe_id = table_name.id;

		IF COALESCE(r.create_table_clause, '') = ''
			OR COALESCE(r.key_string, '') = '' THEN
			RAISE EXCEPTION 'data table has no defined columns: %',
				table_name.id;
		END IF;

		IF COALESCE(r.create_history_table_clause, '') = ''
			OR COALESCE(r.key_string, '') = '' THEN
			RAISE EXCEPTION 'history table has no defined columns: %',
				table_name.id;
		END IF;

		EXECUTE 'CREATE TABLE pemdata.' || quoted_table_name || ' ('
			|| r.create_table_clause || ', PRIMARY KEY ('
			|| r.key_string || '))';

		IF NOT table_name.discard_history THEN
			EXECUTE 'CREATE TABLE pemhistory.' || quoted_table_name || ' ('
				|| r.create_history_table_clause || ')';

			EXECUTE 'CREATE INDEX '
				|| quote_ident(table_name.internal_name || '_keyidx')
				|| ' ON ' || 'pemhistory.' || quoted_table_name
				|| ' (' || r.key_string || ')';

			EXECUTE 'CREATE INDEX '
				|| quote_ident(table_name.internal_name || '_timeidx')
				|| ' ON ' || 'pemhistory.' || quoted_table_name
				|| ' (recorded_time)';

			-- Trigger Function Command String
			trigger_function_command := 'CREATE OR REPLACE FUNCTION pemdata.' ||  quote_ident('copy_' || table_name.internal_name || '_to_history') || '() RETURNS TRIGGER AS $$
			BEGIN
				IF (TG_OP = ''INSERT'' OR TG_OP = ''UPDATE'') THEN
					INSERT INTO pemhistory.' || quoted_table_name || ' (' || r.column_string || ') VALUES (' || r.new_column_string || ');
					ELSIF EXISTS(SELECT 1 FROM ' || CASE WHEN table_name.target_type_id = 100 THEN 'pem.agent WHERE id = OLD.agent_id' ELSE 'pem.server WHERE id = OLD.server_id' END || ') THEN
					INSERT INTO pemhistory.' || quoted_table_name || ' (' || r.key_string || ') VALUES (' || r.old_key_string || ');
				END IF;
				RETURN NEW;
			END;
			$$ LANGUAGE plpgsql;';

			-- Trigger Command String
			trigger_command := 'CREATE TRIGGER ' || quote_ident('copy_' || table_name.internal_name || '_to_history') || ' AFTER INSERT OR UPDATE OR DELETE ON pemdata.' || quoted_table_name || ' FOR EACH ROW EXECUTE PROCEDURE pemdata.' || quote_ident('copy_' || table_name.internal_name || '_to_history') || '()' ;

			-- Execute the commands.
			EXECUTE trigger_function_command;
			EXECUTE trigger_command;
		END IF;

	    -- Trigger Function for calculating PIT values definition
	    IF COALESCE(r.data_trigger_clause, '') != ''
	    THEN
		-- Trigger Function Command String
		trigger_function_command := 'CREATE OR REPLACE FUNCTION pemdata.' ||  quote_ident('calculate_' || table_name.internal_name || '_pit_value') || E'() RETURNS TRIGGER AS $$
BEGIN
    IF (TG_OP = ''UPDATE'') THEN \n'
	 ||  r.data_trigger_clause ||
    E'\n    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;';

		-- Trigger Command String
		trigger_command := 'CREATE TRIGGER ' || quote_ident('calculate_' || table_name.internal_name || '_pit_value') || ' BEFORE UPDATE ON pemdata.' || quoted_table_name || ' FOR EACH ROW EXECUTE PROCEDURE pemdata.' || quote_ident('calculate_' || table_name.internal_name || '_pit_value') || '()' ;

		-- Execute the commands.
		EXECUTE trigger_function_command;
	        EXECUTE trigger_command;
	    END IF;

    END LOOP;
END;
$BODY$ LANGUAGE plpgsql;

SELECT pem.create_data_and_history_tables();

INSERT INTO pem.config (param, value, unit, datatype) VALUES ('package_catalog_xml', 'http://sbp.enterprisedb.com/applications.xml', '', 'string'); -- Package Catalog XML

-- Update Monitor Templates
SELECT pem.create_alert_template(
	'Package version mismatch',
	'Check for package version mismatch as per catalog',
	$sql$
SELECT
    COUNT(ip.pkg_id)
FROM
    pemdata.package_catalog pc LEFT JOIN pemdata.installed_packages ip
    ON (pc.pkg_id = ip.pkg_id) AND (pc.platform = ip.platform)
WHERE
   ip.agent_id = ${agent_id} AND
   pc.pkg_id = ip.pkg_id AND
   pc.platform = ip.platform AND
   pc.version != ip.version$sql$,
	100, NULL, NULL, NULL, NULL,'{package_catalog, installed_packages}', 23, 'ALL', 1440);

-- Added object info in reminder email
UPDATE pem.email_template SET mail_subject = '[Alert Reminder] for "%AlertName%" on %ObjectName%', mail_message = E'Alert Details\n------------------------\nAlert Name: %AlertName%\nServer/Agent: %ObjectName%\nCurrent Value: %CurrentValue%\nThreshold Value: %ThresholdValue%\nCurrent State: %CurrentState%\nAlerting Since: %AlertingSince%\n%DownObjects%' WHERE display_name = 'Alert Reminder';

-- Fixed FB 22898
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
	write_message_streaming_repl text;
	flush_message_streaming_repl text;
	replay_message_streaming_repl text;
	upgrade_pkg_list  text;
	new_pkg_list      text;
	obsolete_pkg_list text;
BEGIN
	probe_disabled_err = 'Required probe(s) ';
	zero_rows_err = 'Zero rows returned';

	locked_alert = false;

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
			locked_alert = true;
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

	sql = alert_rec.sql;

	/* Replace any reference to hierarchy-related alert parameters */
	sql = regexp_replace(sql, E'\\${agent_id}',		COALESCE(alert_rec.agent_id::text,	'')::text, 'g');
	sql = regexp_replace(sql, E'\\${server_id}',	COALESCE(alert_rec.server_id::text,	'')::text, 'g');
	sql = regexp_replace(sql, E'\\${database_name}',COALESCE(alert_rec.database_name,	'')::text, 'g');
	sql = regexp_replace(sql, E'\\${schema_name}',	COALESCE(alert_rec.schema_name,		'')::text, 'g');
	sql = regexp_replace(sql, E'\\${package_name}',	COALESCE(alert_rec.package_name,	'')::text, 'g');
	sql = regexp_replace(sql, E'\\${object_name}',	COALESCE(alert_rec.object_name,		'')::text, 'g');

	/* Replace ${param_n} with corresponding alert parameters */
	FOR i IN 1..COALESCE(array_upper(alert_rec.params, 1), 0) LOOP
		sql = regexp_replace(sql, E'\\${param_' || i || '}', alert_rec.params[i]::text, 'g');
	END LOOP;

	err = '';

	/* Check any required probe is disabled from the probe dependency list */
	all_probes_enabled = true;
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
			probe_disabled_err = probe_disabled_err || alert_rec.probe_dependency_list[i] || ',';
			all_probes_enabled = false;
		END IF;

		-- Get minimum probe interval from all dependent probes
		SELECT default_execution_frequency INTO probe_interval FROM pem.probe WHERE internal_name = alert_rec.probe_dependency_list[i];
		IF (probe_interval <  min_probe_interval) OR (i = 1) THEN
			min_probe_interval = probe_interval;
		END IF;
	END LOOP;

	probe_disabled_err = trim(trailing ',' from probe_disabled_err);
	probe_disabled_err = probe_disabled_err || ' are disabled.';

	IF NOT all_probes_enabled THEN
		err = probe_disabled_err;
	ELSE
		RAISE DEBUG 'Alert query being executed: %', sql;

		BEGIN
			EXECUTE sql INTO STRICT sql_ret;
		EXCEPTION
			WHEN no_data_found THEN
				IF all_probes_enabled THEN
					err = zero_rows_err;
				END IF;

			WHEN OTHERS THEN
				err = SQLERRM;
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
			state = 'HIGH';
		ELSIF (sql_ret < alert_rec.thresholds[2]) THEN
			state = 'MEDIUM';
		ELSIF (sql_ret < alert_rec.thresholds[1]) THEN
			state = 'LOW';
		ELSE
			state = NULL;
		END IF;
	ELSIF (alert_rec.operator = '>') THEN
		IF (sql_ret > alert_rec.thresholds[3]) THEN
			state = 'HIGH';
		ELSIF (sql_ret > alert_rec.thresholds[2]) THEN
			state = 'MEDIUM';
		ELSIF (sql_ret > alert_rec.thresholds[1]) THEN
			state = 'LOW';
		ELSE
			state = NULL;
		END IF;
	END IF;

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
	 *        set acked = false
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
				send_mail_val = pem.send_email(alert_rec.email_group_id, subject, message);
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
		current_state = state, -- may be NULL
		current_state_since =	CASE
								WHEN state IS DISTINCT FROM alert_rec.state
								THEN now()
								ELSE current_state_since
								END
	WHERE alert_id = alert_rec.id;

	-- If there wasn't any status row for this alert already, then populate one.
	IF (NOT FOUND) THEN
		INSERT INTO pem.alert_status
		VALUES (alert_rec.id, sql_ret, state,
				CASE
				WHEN state IS NOT NULL
				THEN now()
				ELSE NULL
				END,
				now());
	END IF;

	-- Check for reminder notification
	SELECT value INTO reminder_interval FROM pem.config WHERE param = 'reminder_notification_interval';
	SELECT current_state_since INTO alert_state_since FROM pem.alert_status WHERE alert_id = alert_rec.id;
	IF alert_rec.send_email AND (NOT alert_rec.acknowledged) AND (alert_state_since IS NOT NULL) AND (state IS NOT NULL) AND (NOT alert_rec.flapping_detected)
	AND ((now() - alert_state_since) >= (reminder_interval||'hours')::interval)
	AND ((now() - alert_rec.last_mail_send) >= (reminder_interval||'hours')::interval) THEN

		-- Create subject and message
		SELECT subject_mail, message_mail INTO subject, message FROM pem.create_email(alert_rec.id, 'Alert Reminder');
		message = regexp_replace(message, '%CurrentValue%', COALESCE(sql_ret, 0)::text);
		message = regexp_replace(message, '%CurrentState%', state::text);
		message = regexp_replace(message, '%AlertingSince%', alert_state_since::text);

		-- Get the list of down objetcs
		down_objects_list = pem.get_down_objects_list(alert_rec.template_name);
		message = regexp_replace(message, '%DownObjects%', down_objects_list::text);

		-- Special handling for 'Write lag Alert' alert
		IF (alert_rec.template_name = 'Number of standby servers lag behind the master by write location') THEN
			SELECT pem.email_write_lag_streaming_replication() INTO write_message_streaming_repl;
			message = message || COALESCE(write_message_streaming_repl, '')::text;
		END IF;

		IF (alert_rec.template_name = 'Number of standby servers lag behind the master by flush location') THEN
			SELECT pem.email_flush_lag_streaming_replication() INTO flush_message_streaming_repl;
			message = message || COALESCE(flush_message_streaming_repl, '')::text;
		END IF;

		IF (alert_rec.template_name = 'Number of standby servers lag behind the master by replay location') THEN
			SELECT pem.email_replay_lag_streaming_replication() INTO replay_message_streaming_repl;
			message = message || COALESCE(replay_message_streaming_repl, '')::text;
		END IF;

		-- Get the list of obsolete packages and packages for which updates are avalibale
		IF (alert_rec.template_name = 'Package version mismatch') THEN
			SELECT upgrade_packages_list, new_packages_list, obsolete_packages_list INTO upgrade_pkg_list,
			new_pkg_list, obsolete_pkg_list FROM pem.get_mismatch_packages_list(alert_rec.agent_id);

			message = message || E'\n' || COALESCE(upgrade_pkg_list, '')::text || E'\n' || COALESCE(obsolete_pkg_list, '')::text;
		END IF;

		send_mail_val = pem.send_email(alert_rec.email_group_id, subject, message);
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

CREATE OR REPLACE FUNCTION pem.auto_create_agent_alerts()
RETURNS trigger AS $$
DECLARE
	is_auto_create boolean:= false;
BEGIN
	-- select value of auto_create_agent_alerts
	SELECT value INTO is_auto_create FROM pem.config WHERE param = 'auto_create_agent_alerts';

	IF is_auto_create THEN
		PERFORM pem.create_default_agent_alerts(NEW.id);
	END IF;
	RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION pem.create_default_agent_alerts(agent_id integer)
RETURNS VOID AS $$
BEGIN
	IF NOT pem.check_alert_exist('Swap consumption percentage', $1, NULL, NULL, NULL, NULL, NULL, 100) THEN
		PERFORM pem.create_alert('Swap consumption percentage',
		(SELECT id FROM pem.alert_template WHERE display_name = 'Swap consumption percentage' AND object_type = 100 LIMIT 1),
		$1, NULL, NULL, NULL, NULL, NULL, '{}', '>', '{25, 50, 75}', 1, 30, true);
	END IF;

	IF NOT pem.check_alert_exist('Memory used percentage', $1, NULL, NULL, NULL, NULL, NULL, 100) THEN
		PERFORM pem.create_alert('Memory used percentage',
		(SELECT id FROM pem.alert_template WHERE display_name = 'Memory used percentage' AND object_type = 100 LIMIT 1),
		$1, NULL, NULL, NULL, NULL, NULL, '{}', '>', '{80, 90, 95}', 1, 30, true);
	END IF;

	IF NOT pem.check_alert_exist('Most used disk percentage', $1, NULL, NULL, NULL, NULL, NULL, 100) THEN
		PERFORM pem.create_alert('Most used disk percentage',
		(SELECT id FROM pem.alert_template WHERE display_name = 'Most used disk percentage' AND object_type = 100 LIMIT 1),
		$1, NULL, NULL, NULL, NULL, NULL, '{}', '>', '{75, 85, 95}', 1, 30, true);
	END IF;

	IF NOT pem.check_alert_exist('Load Average per CPU Core (5 minutes)', $1, NULL, NULL, NULL, NULL, NULL, 100) THEN
		PERFORM pem.create_alert('Load Average per CPU Core (5 minutes)',
		(SELECT id FROM pem.alert_template WHERE display_name = 'Load Average per CPU Core (5 minutes)' AND object_type = 100 LIMIT 1),
		$1, NULL, NULL, NULL, NULL, NULL, '{}', '>', '{0.7, 2.0, 5.0}', 1, 30, true);
	END IF;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION pem.auto_create_alerts_on_exisiting_agents()
RETURNS VOID AS $$
DECLARE
       rec record;
BEGIN
       FOR rec in (SELECT id FROM pem.agent)
       LOOP
               PERFORM pem.create_default_agent_alerts(rec.id);
       END LOOP;
END;
$$ LANGUAGE plpgsql;

-- Create auto alerts for the existing agents
SELECT pem.auto_create_alerts_on_exisiting_agents();

CREATE OR REPLACE FUNCTION pem.send_notifications() RETURNS trigger AS $$
DECLARE
	subject text;
	message text;
	mail_group_id integer;
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
	write_message_streaming_repl text;
	flush_message_streaming_repl text;
	replay_message_streaming_repl text;
	upgrade_pkg_list text;
	new_pkg_list text;
	obsolete_pkg_list text;
BEGIN
	-- Get alert details
	SELECT
		agent_id, template_id, email_group_id, send_email, acknowledged, flapping_detected, send_trap, snmp_trap_version
	INTO
		agentid, templateid, mail_group_id, is_send_email, is_acknowledged, is_flapping_detected, is_send_trap, trap_version
	FROM
		pem.alert
	WHERE
		id = NEW.alert_id;

	-- Get the template name
	SELECT display_name INTO template_name FROM pem.alert_template WHERE id = templateid;

	-- Get the list of Agents/Servers Down
	down_objects_list = pem.get_down_objects_list(template_name);

	-- Get the list of slave that lag behind by write location
	IF (template_name = 'Number of standby servers lag behind the master by write location') THEN
		SELECT pem.email_write_lag_streaming_replication() INTO write_message_streaming_repl;
	END IF;

	-- Get the list of slave that lag behind by flush location
	IF (template_name = 'Number of standby servers lag behind the master by flush location') THEN
		SELECT pem.email_flush_lag_streaming_replication() INTO flush_message_streaming_repl;
	END IF;

	-- Get the list of slave that lag behind by replay location
	IF (template_name = 'Number of standby servers lag behind the master by replay location') THEN
		SELECT pem.email_replay_lag_streaming_replication() INTO replay_message_streaming_repl;
	END IF;

	-- Get the list of obsolete packages and packages for which updates are avalibale
	IF (template_name = 'Package version mismatch') THEN
		SELECT upgrade_packages_list, new_packages_list, obsolete_packages_list INTO upgrade_pkg_list,
		new_pkg_list, obsolete_pkg_list FROM pem.get_mismatch_packages_list(agentid);
	END IF;

	IF ((TG_OP = 'INSERT') AND (NEW.current_state IS NOT NULL)) THEN
		-- Update state change count
		UPDATE pem.alert_status SET state_change_count = state_change_count + 1 WHERE alert_id = NEW.alert_id;

		-- SMTP Notifications
		IF is_send_email AND (NOT is_acknowledged) AND (NOT is_flapping_detected) THEN
			-- Create subject and message
			SELECT subject_mail, message_mail INTO subject, message FROM pem.create_email(NEW.alert_id, 'Alert Detected');
			subject = regexp_replace(subject, '%AlertType%', NEW.current_state::text);
			message = regexp_replace(message, '%CurrentValue%', COALESCE(NEW.current_value, 0)::text);
			message = regexp_replace(message, '%AlertDetected%', now()::text);
			message = regexp_replace(message, '%DownObjects%', down_objects_list::text);

			-- Special handling for 'Write lag Alert' alert
			IF (template_name = 'Number of standby servers lag behind the master by write location') THEN
				message = message || COALESCE(write_message_streaming_repl, '')::text;
			END IF;

			-- Special handling for 'Flush lag Alert' alert
			IF (template_name = 'Number of standby servers lag behind the master by flush location') THEN
				message = message || COALESCE(flush_message_streaming_repl, '')::text;
			END IF;

			-- Special handling for 'Replay lag Alert' alert
			IF (template_name = 'Number of standby servers lag behind the master by replay location') THEN
				message = message || COALESCE(replay_message_streaming_repl, '')::text;
			END IF;

			-- Special handling for 'Package version mismatch' alert
			IF (template_name = 'Package version mismatch') THEN
				message = message || E'\n' || COALESCE(upgrade_pkg_list, '')::text || E'\n' || COALESCE(obsolete_pkg_list, '')::text;
			END IF;

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
			varbinding_value = varbinding_value || '|NULL|' || COALESCE(NEW.current_value, 0)::text || '|NULL|';
			IF NEW.current_state IS NULL THEN
				varbinding_value = varbinding_value || '|CLEAR';
			ELSE
				varbinding_value = varbinding_value || NEW.current_state::text;
			END IF;
			-- Append current timestamp
			varbinding_value = varbinding_value || '|' || now()::text;

			-- Special handling for "Agents Down" and "Servers Down" alert
			IF (template_name = 'Agents Down') OR  (template_name = 'Servers Down') OR (template_name = 'Alert Errors') THEN
				varbinding_value = varbinding_value || '|' || down_objects_list::text;
			END IF;

			-- Special handling for 'Write lag Alert' alert
			IF (template_name = 'Number of standby servers lag behind the master by write location') THEN
				varbinding_value = varbinding_value || '|' || COALESCE(write_message_streaming_repl, '')::text;
			END IF;

			IF (template_name = 'Number of standby servers lag behind the master by flush location') THEN
				varbinding_value = varbinding_value || '|' || COALESCE(flush_message_streaming_repl, '')::text;
			END IF;

			IF (template_name = 'Number of standby servers lag behind the master by replay location') THEN
				varbinding_value = varbinding_value || '|' || COALESCE(replay_message_streaming_repl, '')::text;
			END IF;

			-- Special handling for "Package version mismatch" alert
			IF (template_name = 'Package version mismatch') THEN
				varbinding_value = varbinding_value || '|' || upgrade_pkg_list::text || ' ' || obsolete_pkg_list::text;
			END IF;

			-- Send SNMP traps
			send_trap_val = pem.send_snmptrap(trap_oid, enterprise_oid, trap_version, varbinding_oid, varbinding_value);
		END IF;
	END IF;

	IF ((TG_OP = 'UPDATE') AND (NEW.current_state IS DISTINCT FROM OLD.current_state)) THEN
		-- Update state change count
		UPDATE pem.alert_status SET state_change_count = state_change_count + 1 WHERE alert_id = NEW.alert_id;

		-- SMTP Notifications
		IF is_send_email AND (NOT is_acknowledged) AND (NOT is_flapping_detected) THEN
			-- If current state is NULL means alert is cleared.
			IF (NEW.current_state IS NOT NULL) THEN
				-- if OLD current_state is not null means alert level changed.
				IF (OLD.current_state IS NOT NULL AND (OLD.current_state > NEW.current_state)) THEN
					-- Create subject and message
					SELECT subject_mail, message_mail INTO subject, message FROM pem.create_email(NEW.alert_id, 'Alert Level Decreased');
					message = regexp_replace(message, '%CurrentState%', NEW.current_state::text);
					message = regexp_replace(message, '%OldState%', OLD.current_state::text);
					message = regexp_replace(message, '%StateChanged%', now()::text);
				ELSIF (OLD.current_state IS NOT NULL AND (OLD.current_state < NEW.current_state)) THEN
					-- Create subject and message
					SELECT subject_mail, message_mail INTO subject, message FROM pem.create_email(NEW.alert_id, 'Alert Level Increased');
					message = regexp_replace(message, '%CurrentState%', NEW.current_state::text);
					message = regexp_replace(message, '%OldState%', OLD.current_state::text);
					message = regexp_replace(message, '%StateChanged%', now()::text);
				ELSE
					-- Create subject and message
					SELECT subject_mail, message_mail INTO subject, message FROM pem.create_email(NEW.alert_id, 'Alert Detected');
					subject = regexp_replace(subject, '%AlertType%', NEW.current_state::text);
					message = regexp_replace(message, '%AlertDetected%', now()::text);
				END IF;
			ELSE
				-- Create subject and message
				SELECT subject_mail, message_mail INTO subject, message FROM pem.create_email(NEW.alert_id, 'Alert Cleared');
				message = regexp_replace(message, '%AlertCleared%', now()::text);
			END IF;

			message = regexp_replace(message, '%CurrentValue%', COALESCE(NEW.current_value, 0)::text);
			message = regexp_replace(message, '%DownObjects%', down_objects_list::text);

			-- Special handling for 'Write lag Alert' alert
			IF (template_name = 'Number of standby servers lag behind the master by write location') THEN
				message = message || COALESCE(write_message_streaming_repl, '')::text;
			END IF;

			IF (template_name = 'Number of standby servers lag behind the master by flush location') THEN
				message = message || COALESCE(flush_message_streaming_repl, '')::text;
			END IF;

			IF (template_name = 'Number of standby servers lag behind the master by replay location') THEN
				message = message || COALESCE(replay_message_streaming_repl, '')::text;
			END IF;

			-- Special handling for 'Package version mismatch' alert
			IF (template_name = 'Package version mismatch') THEN
				message = message || E'\n' || COALESCE(upgrade_pkg_list, '')::text || E'\n' || COALESCE(obsolete_pkg_list, '')::text;
			END IF;

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
			varbinding_value = varbinding_value || '|' || COALESCE(OLD.current_value, 0)::text || '|' || COALESCE(NEW.current_value, 0)::text;

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
			IF (template_name = 'Agents Down') OR  (template_name = 'Servers Down') OR (template_name = 'Alert Errors') THEN
				varbinding_value = varbinding_value || '|' || down_objects_list::text;
			END IF;

			-- Special handling for 'Write lag Alert' alert
			IF (template_name = 'Number of standby servers lag behind the master by write location') THEN
				varbinding_value = varbinding_value || '|' || COALESCE(write_message_streaming_repl, '')::text;
			END IF;

			IF (template_name = 'Number of standby servers lag behind the master by flush location') THEN
				varbinding_value = varbinding_value || '|' || COALESCE(flush_message_streaming_repl, '')::text;
			END IF;

			IF (template_name = 'Number of standby servers lag behind the master by replay location') THEN
				varbinding_value = varbinding_value || '|' || COALESCE(replay_message_streaming_repl, '')::text;
			END IF;

			-- Special handling for "Package version mismatch" alert
			IF (template_name = 'Package version mismatch') THEN
				varbinding_value = varbinding_value || '|' || upgrade_pkg_list::text || ' ' || obsolete_pkg_list::text;
			END IF;

			-- Send SNMP traps
			send_trap_val = pem.send_snmptrap(trap_oid, enterprise_oid, trap_version, varbinding_oid, varbinding_value);
		END IF;
	END IF;

	RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION pem.get_down_objects_list(template_name text) RETURNS text AS $$
DECLARE
	rec record;
	down_objetcs_list text:= '';
	index integer:= 1;
BEGIN
	-- Get the list of down agents
	IF (template_name = 'Agents Down') THEN
		down_objetcs_list = E'Agents Down:\n';
		FOR rec in (SELECT id, description FROM pem.get_agents_with_status('DOWN') AS (id integer, description text))
		LOOP
			down_objetcs_list = down_objetcs_list || index || ') ' || rec.description || E'\n';
			index = index + 1;
		END LOOP;
	END IF;

	-- Get the list of down servers
	IF (template_name = 'Servers Down') THEN
		down_objetcs_list = E'Servers Down:\n';
		index = 1;
		FOR rec in (SELECT id, description, server , port FROM pem.get_servers_with_status('DOWN') AS
					(id integer, description text, server text, port integer))
		LOOP
			down_objetcs_list = down_objetcs_list || index || ') ' || rec.description || ' (' || rec.server ||
							':' || rec.port || E')\n';
			index = index + 1;
		END LOOP;
	END IF;

	RETURN down_objetcs_list;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION pem.get_mismatch_packages_list(agentid integer, OUT upgrade_packages_list text, OUT new_packages_list text, OUT obsolete_packages_list text) AS $$
DECLARE
	rec record;
	index integer:= 1;
BEGIN
	-- Get the list of packages that needs to be upgrade
	FOR rec in (SELECT pc.name AS pkg_name, pc.version AS catalog_veriosn, ip.version AS installed_version
				FROM
					pemdata.package_catalog pc LEFT JOIN pemdata.installed_packages ip
					ON (pc.pkg_id = ip.pkg_id) AND (pc.platform = ip.platform)
				WHERE
					ip.agent_id = agentid AND
					pc.pkg_id = ip.pkg_id AND
					pc.platform = ip.platform AND
					pc.version > ip.version)
	LOOP
		IF ( index = 1) THEN
			upgrade_packages_list = E'Packages for which updates are available:\n';
		END IF;
		upgrade_packages_list = upgrade_packages_list || index || ') ' || rec.pkg_name || ' (Installed Version: '
							|| rec.installed_version || ' Catalog Version: ' || rec.catalog_veriosn || E')\n';
		index = index + 1;
	END LOOP;

	index = 1;
	-- Get the list of packages which is not installed on the agent machine
	FOR rec in (SELECT distinct pc.pkg_id, pc.name AS pkg_name, pc.version AS version
				FROM
					pemdata.package_catalog pc
				WHERE NOT EXISTS(SELECT pkg_id
								FROM pemdata.installed_packages ip
								WHERE pc.pkg_id = ip.pkg_id) ORDER BY pc.pkg_id)
	LOOP
		IF ( index = 1) THEN
			new_packages_list = E'Packages which are available for installation:\n';
		END IF;
		new_packages_list = new_packages_list || index || ') ' || rec.pkg_name || ' (Version: '
							|| rec.version || E')\n';
		index = index + 1;
	END LOOP;

	index = 1;
	-- Get the list of packages which is installed but obsolete from the catalog.
	FOR rec in (SELECT ip.pkg_id, ip.name AS pkg_name, ip.version AS version
				FROM
					pemdata.installed_packages ip
				WHERE NOT EXISTS
					(SELECT pc.pkg_id FROM pemdata.package_catalog pc
					WHERE ip.pkg_id = pc.pkg_id AND ip.platform = pc.platform)
				AND ip.agent_id = agentid
				ORDER BY ip.pkg_id)
	LOOP
		IF ( index = 1) THEN
			obsolete_packages_list = E'Packages which are installed, but obsolete from the catalog:\n';
		END IF;
		obsolete_packages_list = obsolete_packages_list || index || ') ' || rec.pkg_name || ' (Version: '
							|| rec.version || E')\n';
		index = index + 1;
	END LOOP;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION pem.create_trap(alert_id integer, OUT snmp_trap_oid text, OUT snmp_enterprise_oid text, OUT snmp_varbinding_oid text, OUT snmp_varbinding_value text) AS $$
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
	alert_template_id integer;
	alert_object_type integer;
	alert_snmp_oid integer;
BEGIN
	snmp_enterprise_oid = '.1.3.6.1.4.1.27645.5444';

	-- Get alert, agent, server details
	SELECT
		a.name, a.agent_id, a.server_id, a.database_name, a.schema_name, a.object_name, a.thresholds, a.template_id,
		s.description, s.server, s.port,
		ag.description
	INTO
		alert_name, alert_agent_id, alert_server_id, alert_database_name, alert_schema_name, alert_object_name,
		alert_thresholdvalue, alert_template_id, server_name, server_ip, server_port,
		agent_name
	FROM
		pem.alert a
		LEFT JOIN pem.server s ON a.server_id = s.id
		LEFT JOIN pem.agent ag ON a.agent_id = ag.id
	WHERE
		a.id = alert_id;

	-- We used "|" as one of the delimiter for snmp_varbinding_oid and snmp_varbinding_value, so replacing it with " " to avoid errors.
	alert_name = replace(alert_name, '|', ' ');
	agent_name = replace(agent_name, '|', ' ');
	server_name = replace(server_name, '|', ' ');
	alert_database_name = replace(alert_database_name, '|', ' ');
	alert_object_name = replace(alert_object_name, '|', ' ');
	alert_schema_name = replace(alert_schema_name, '|', ' ');

	-- Get SNMP OID
	SELECT snmp_oid, object_type INTO alert_snmp_oid, alert_object_type FROM pem.alert_template WHERE id = alert_template_id;

	CASE
	WHEN alert_object_type = 50 THEN
		snmp_trap_oid = snmp_enterprise_oid || '.6.' || alert_snmp_oid;
		snmp_varbinding_oid = snmp_enterprise_oid || '.7.1|' || snmp_enterprise_oid || '.7.9|' || snmp_enterprise_oid || '.7.10|' || snmp_enterprise_oid || '.7.11|'
							|| snmp_enterprise_oid || '.7.12|' || snmp_enterprise_oid || '.7.13|' || snmp_enterprise_oid || '.7.14|'
							|| snmp_enterprise_oid || '.7.15';
		snmp_varbinding_value = alert_name || '|' || alert_thresholdvalue;
	WHEN alert_object_type = 100 THEN
		snmp_trap_oid = snmp_enterprise_oid || '.1.' || alert_snmp_oid;
		snmp_varbinding_oid = snmp_enterprise_oid || '.7.1|' || snmp_enterprise_oid || '.7.2|' || snmp_enterprise_oid || '.7.4|' || snmp_enterprise_oid ||
							'.7.9|' || snmp_enterprise_oid || '.7.10|' || snmp_enterprise_oid || '.7.11|' || snmp_enterprise_oid ||
							'.7.12|' || snmp_enterprise_oid || '.7.13|' || snmp_enterprise_oid || '.7.14|' || snmp_enterprise_oid || '.7.16';
		snmp_varbinding_value = alert_name || '|' || alert_agent_id || '|' || agent_name || '|' || alert_thresholdvalue;
	WHEN alert_object_type = 200 THEN
		snmp_trap_oid = snmp_enterprise_oid || '.2.' || alert_snmp_oid;
		snmp_varbinding_oid = snmp_enterprise_oid || '.7.1|' || snmp_enterprise_oid || '.7.3|' || snmp_enterprise_oid || '.7.5|' || snmp_enterprise_oid ||
							'.7.9|' || snmp_enterprise_oid || '.7.10|' || snmp_enterprise_oid || '.7.11|' || snmp_enterprise_oid ||
							'.7.12|' || snmp_enterprise_oid || '.7.13|' || snmp_enterprise_oid || '.7.14|' || snmp_enterprise_oid || '.7.17';
		snmp_varbinding_value = alert_name || '|' || alert_server_id || '|' || server_name || ' ('|| server_ip ||': ' || server_port || ')|'
							|| alert_thresholdvalue;
	WHEN alert_object_type = 300 THEN
		snmp_trap_oid = snmp_enterprise_oid || '.3.' || alert_snmp_oid;
		snmp_varbinding_oid = snmp_enterprise_oid || '.7.1|' || snmp_enterprise_oid || '.7.3|' || snmp_enterprise_oid || '.7.5|' || snmp_enterprise_oid ||
							'.7.6|' || snmp_enterprise_oid || '.7.9|' || snmp_enterprise_oid || '.7.10|' || snmp_enterprise_oid ||
							'.7.11|'|| snmp_enterprise_oid || '.7.12|' || snmp_enterprise_oid || '.7.13|' || snmp_enterprise_oid || '.7.14';
		snmp_varbinding_value = alert_name || '|' || alert_server_id || '|' || server_name || ' ('|| server_ip ||': ' || server_port || ')|' ||
							alert_database_name || '|' || alert_thresholdvalue;
	WHEN alert_object_type = 400 THEN
		snmp_trap_oid = snmp_enterprise_oid || '.4.' || alert_snmp_oid;
		snmp_varbinding_oid = snmp_enterprise_oid || '.7.1|' || snmp_enterprise_oid || '.7.3|' || snmp_enterprise_oid || '.7.5|' || snmp_enterprise_oid ||
							'.7.6|' || snmp_enterprise_oid || '.7.7|' || snmp_enterprise_oid || '.7.9|' || snmp_enterprise_oid ||
							'.7.10|' || snmp_enterprise_oid || '.7.11|'|| snmp_enterprise_oid || '.7.12|' || snmp_enterprise_oid ||
							'.7.13|'  ||snmp_enterprise_oid || '.7.14';
		snmp_varbinding_value = alert_name || '|' || alert_server_id || '|' || server_name || ' ('|| server_ip ||': ' || server_port || ')|' ||
							 alert_database_name || '|' || alert_schema_name || '|' || alert_thresholdvalue;
	WHEN alert_object_type > 400 THEN
		snmp_trap_oid = snmp_enterprise_oid || '.5.' || alert_snmp_oid;
		snmp_varbinding_oid = snmp_enterprise_oid || '.7.1|' || snmp_enterprise_oid || '.7.3|' || snmp_enterprise_oid || '.7.5|' || snmp_enterprise_oid ||
							'.7.6|' || snmp_enterprise_oid || '.7.7|' || snmp_enterprise_oid || '.7.8|' || snmp_enterprise_oid ||
							'.7.9|' || snmp_enterprise_oid || '.7.10|'|| snmp_enterprise_oid || '.7.11|' || snmp_enterprise_oid ||
							'.7.12|'|| snmp_enterprise_oid || '.7.13|' || snmp_enterprise_oid || '.7.14';
		snmp_varbinding_value = alert_name || '|' || alert_server_id || '|' || server_name || ' ('|| server_ip ||': ' || server_port || ')|' ||
							 alert_database_name || '|' || alert_schema_name || '|' || alert_object_name || '|' ||
							 alert_thresholdvalue;
	END CASE;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION pem.generate_alert_mib()
RETURNS text AS $$
DECLARE
	mib_text text;
BEGIN

	mib_text = E'\n-- File Name : PEM-ALERTING-MIB\n
-- Date      : ' || now()::text || E'\n
-- Author    : EnterpriseDB \n

PEM-ALERTING-MIB	DEFINITIONS ::= BEGIN

	IMPORTS
		enterprises, MODULE-IDENTITY, OBJECT-TYPE, Integer32, NOTIFICATION-TYPE
			FROM SNMPv2-SMI
		DisplayString
			FROM SNMPv2-TC
		MODULE-COMPLIANCE, OBJECT-GROUP, NOTIFICATION-GROUP
			FROM SNMPv2-CONF;


	postgresql	MODULE-IDENTITY
		LAST-UPDATED	"201109271419Z"
		ORGANIZATION	"EnterpriseDB"
		CONTACT-INFO	"http://www.enterprisedb.com"
		DESCRIPTION	"This MIB file used for alerting notifications."
		REVISION	"201109271419Z"
		DESCRIPTION	"This MIB file used for alerting notifications."
		::=  {  enterprises  27645  }

	pem	OBJECT IDENTIFIER ::=  {  postgresql  5444  }

	agentAlerts	OBJECT IDENTIFIER ::=  {  pem  1  }

	serverAlerts	OBJECT IDENTIFIER ::=  {  pem  2  }

	databaseAlerts	OBJECT IDENTIFIER ::=  {  pem  3  }

	schemaAlerts	OBJECT IDENTIFIER ::=  {  pem  4  }

	objectAlerts	OBJECT IDENTIFIER ::=  {  pem  5  }

	globalAlerts	OBJECT IDENTIFIER ::=  {  pem  6  }

	bindingVariables	OBJECT IDENTIFIER ::=  {  pem  7  }

	pemObjectGroup  OBJECT-GROUP
		OBJECTS { alertName,
			agentID,
			agentName,
			databaseName,
			objectName,
			previousStatus,
			previousValue,
			schemaName,
			serverID,
			serverName,
			status,
			thresholdValue,
			value,
			recordedTime,
			downObjects,
			streamingReplicationLagBytes,
			updatePackages}
	STATUS 	current
	DESCRIPTION
		"This group contains the notification detail objects"
	::= { postgresql 5445 }

	alertName	OBJECT-TYPE
		SYNTAX			DisplayString
		MAX-ACCESS		read-only
		STATUS			current
		DESCRIPTION		"This parameter gives the alert name"
		::=  {  bindingVariables  1  }

	agentID		OBJECT-TYPE
		SYNTAX			Integer32
		MAX-ACCESS		read-only
		STATUS			current
		DESCRIPTION		"This parameter gives the agent id for which this alert is raised"
		::=  {  bindingVariables  2  }

	serverID	OBJECT-TYPE
		SYNTAX			Integer32
		MAX-ACCESS		read-only
		STATUS			current
		DESCRIPTION		"This parameter gives the server id for which this alert is raised"
		::=  {  bindingVariables  3  }

	agentName	OBJECT-TYPE
		SYNTAX			DisplayString
		MAX-ACCESS		read-only
		STATUS			current
		DESCRIPTION		"This parameter gives the agent name for which this alert is raised"
		::=  {  bindingVariables  4  }

	serverName	OBJECT-TYPE
		SYNTAX			DisplayString
		MAX-ACCESS		read-only
		STATUS			current
		DESCRIPTION		"This parameter gives the server name for which this alert is raised"
		::=  {  bindingVariables  5  }

	databaseName	OBJECT-TYPE
		SYNTAX			DisplayString
		MAX-ACCESS		read-only
		STATUS			current
		DESCRIPTION		"This parameter gives the database name for which this alert is raised"
		::=  {  bindingVariables  6  }

	schemaName	OBJECT-TYPE
		SYNTAX			DisplayString
		MAX-ACCESS		read-only
		STATUS			current
		DESCRIPTION		"This parameter gives the schema name for which this alert is raised"
		::=  {  bindingVariables  7  }

	objectName	OBJECT-TYPE
		SYNTAX			DisplayString
		MAX-ACCESS		read-only
		STATUS			current
		DESCRIPTION		"This parameter gives the object name for which this alert is raised"
		::=  {  bindingVariables  8  }

	thresholdValue	OBJECT-TYPE
		SYNTAX			DisplayString
		MAX-ACCESS		read-only
		STATUS			current
		DESCRIPTION		"This parameter gives the threshold value of the alert"
		::=  {  bindingVariables  9  }

	previousValue	OBJECT-TYPE
		SYNTAX			DisplayString
		MAX-ACCESS		read-only
		STATUS			current
		DESCRIPTION		"This parameter gives the current value of the alert"
		::=  {  bindingVariables  10  }

	value	OBJECT-TYPE
		SYNTAX			DisplayString
		MAX-ACCESS		read-only
		STATUS			current
		DESCRIPTION		"This parameter gives the current value of the alert"
		::=  {  bindingVariables  11  }

	previousStatus	OBJECT-TYPE
		SYNTAX			INTEGER  { low ( 0 ) , medium ( 1 ), high ( 2 ) }
		MAX-ACCESS		read-only
		STATUS			current
		DESCRIPTION		"This parameter gives the current status of the alert"
		::=  {  bindingVariables  12  }

	status	OBJECT-TYPE
		SYNTAX			INTEGER  { low ( 0 ) , medium ( 1 ), high ( 2 ) }
		MAX-ACCESS		read-only
		STATUS			current
		DESCRIPTION		"This parameter gives the old status of the alert"
		::=  {  bindingVariables  13  }

	recordedTime	OBJECT-TYPE
		SYNTAX			DisplayString
		MAX-ACCESS		read-only
		STATUS			current
		DESCRIPTION		"This parameter gives the time when the event was recorded"
		::=  {  bindingVariables  14  }

	downObjects		OBJECT-TYPE
		SYNTAX			DisplayString
		MAX-ACCESS		read-only
		STATUS			current
		DESCRIPTION		"This parameter lists the servers/agents that are in a down state"
		::=  {  bindingVariables  15  }

	packageUpdates		OBJECT-TYPE
		SYNTAX			DisplayString
		MAX-ACCESS		read-only
		STATUS			current
		DESCRIPTION		"This parameter list the packages which needs to upgrade and also list the obsolete"
		::=  {  bindingVariables  16  }

	streamingReplicationLagBytes    OBJECT-TYPE
                SYNTAX                  DisplayString
                MAX-ACCESS              read-only
                STATUS                  current
                DESCRIPTION             "This parameter list the slaves which lags behind the master by write/flush/replay location in streaming replication"
                ::=  {  bindingVariables  17  }';

	/* Agent Alerts */
	mib_text = mib_text || pem.create_mib_notification_type(100, 5446);
	/* server Alerts */
	mib_text = mib_text || pem.create_mib_notification_type(200, 5447);
	/* database Alerts */
	mib_text = mib_text || pem.create_mib_notification_type(300, 5448);
	/* schema Alerts */
	mib_text = mib_text || pem.create_mib_notification_type(400, 5449);
	/* object Alerts */
	mib_text = mib_text || pem.create_mib_notification_type(500, 5450);
	mib_text = mib_text || pem.create_mib_notification_type(600, 5451);
	mib_text = mib_text || pem.create_mib_notification_type(700, 5452);
	mib_text = mib_text || pem.create_mib_notification_type(800, 5453);
	/* global Alerts */
	mib_text = mib_text || pem.create_mib_notification_type(50, 5454);

	mib_text = mib_text || E'\nEND';

	RETURN mib_text;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION pem.create_mib_notification_type(object_type integer, group_oid_type integer)
RETURNS text AS $$
DECLARE
	return_text text = '';
	tmp_rec	RECORD;
	parent_node text;
	where_clause text;
	object_prefix text;
	object_string text;
	group_text text = '';
	group_description text = '';
	is_alert_found boolean = false;
BEGIN
	CASE
	WHEN object_type = 50 THEN
		where_clause = 'WHERE object_type = 50 AND snmp_oid > 0';
		parent_node = 'globalAlerts';
		object_string = '{ alertName, thresholdValue, previousValue, value, previousStatus, status, recordedTime, downObjects }';
		object_prefix = 'gl';
		group_text = E'\n\n\tpemGlobalNotificationGroup  NOTIFICATION-GROUP
	\tNOTIFICATIONS {';
		group_description = 'This group contains the global notification types';
	WHEN object_type = 100 THEN
		where_clause = 'WHERE object_type = 100 AND snmp_oid > 0';
		parent_node = 'agentAlerts';
		object_string = '{ alertName, agentID, agentName, thresholdValue, previousValue, value, previousStatus, status, recordedTime, packageUpdates }';
		object_prefix = 'ag';
		group_text = E'\n\n\tpemAgentNotificationGroup  NOTIFICATION-GROUP
	\tNOTIFICATIONS {';
		group_description = 'This group contains the agent level notification types';
	WHEN object_type = 200 THEN
		where_clause = 'WHERE object_type = 200 AND snmp_oid > 0';
		parent_node = 'serverAlerts';
		object_string = '{ alertName, serverID, serverName, thresholdValue, previousValue, value, previousStatus, status, recordedTime, streamingReplicationLagBytes}';
		object_prefix = 'sr';
		group_text = E'\n\n\tpemServerNotificationGroup  NOTIFICATION-GROUP
	\tNOTIFICATIONS {';
		group_description = 'This group contains the server level notification types';
	WHEN object_type = 300 THEN
		where_clause = 'WHERE object_type = 300 AND snmp_oid > 0';
		parent_node = 'databaseAlerts';
		object_string = '{ alertName, serverID, serverName, databaseName, thresholdValue, previousValue, value, previousStatus, status, recordedTime }';
		object_prefix = 'db';
		group_text = E'\n\n\tpemDatabaseNotificationGroup  NOTIFICATION-GROUP
	\tNOTIFICATIONS {';
		group_description = 'This group contains the database level notification types';
	WHEN object_type = 400 THEN
		where_clause = 'WHERE object_type = 400 AND snmp_oid > 0';
		parent_node = 'schemaAlerts';
		object_string = '{ alertName, serverID , serverName, databaseName, schemaName, thresholdValue, previousValue, value, previousStatus, status, recordedTime }';
		object_prefix = 'sc';
		group_text = E'\n\n\tpemSchemaNotificationGroup  NOTIFICATION-GROUP
	\tNOTIFICATIONS {';
		group_description = 'This group contains the schema level notification types';
	WHEN object_type = 500 THEN
		where_clause = 'WHERE object_type = 500 AND snmp_oid > 0';
		parent_node = 'objectAlerts';
		object_string = '{ alertName, serverID, serverName, databaseName, schemaName, objectName, thresholdValue, previousValue, value, previousStatus, status, recordedTime }';
		object_prefix = 'tb';
		group_text = E'\n\n\tpemTableNotificationGroup  NOTIFICATION-GROUP
	\tNOTIFICATIONS {';
		group_description = 'This group contains the table level notification types';
	WHEN object_type = 600 THEN
		where_clause = 'WHERE object_type = 600 AND snmp_oid > 0';
		parent_node = 'objectAlerts';
		object_string = '{ alertName, serverID, serverName, databaseName, schemaName, objectName, thresholdValue, previousValue, value, previousStatus, status, recordedTime }';
		object_prefix = 'in';
		group_text = E'\n\n\tpemIndexNotificationGroup  NOTIFICATION-GROUP
	\tNOTIFICATIONS {';
		group_description = 'This group contains the index level notification types';
	WHEN object_type = 700 THEN
		where_clause = 'WHERE object_type = 700 AND snmp_oid > 0';
		parent_node = 'objectAlerts';
		object_string = '{ alertName, serverID, serverName, databaseName, schemaName, objectName, thresholdValue, previousValue, value, previousStatus, status, recordedTime }';
		object_prefix = 'se';
		group_text = E'\n\n\tpemSequenceNotificationGroup  NOTIFICATION-GROUP
	\tNOTIFICATIONS {';
		group_description = 'This group contains the sequence level notification types';
	WHEN object_type = 800 THEN
		where_clause = 'WHERE object_type = 800 AND snmp_oid > 0';
		parent_node = 'objectAlerts';
		object_string = '{ alertName, serverID, serverName, databaseName, schemaName, objectName, thresholdValue, previousValue, value, previousStatus, status, recordedTime }';
		object_prefix = 'fn';
		group_text = E'\n\n\tpemFunctionNotificationGroup  NOTIFICATION-GROUP
	\tNOTIFICATIONS {';
		group_description = 'This group contains the function level notification types';
	END CASE;

	FOR tmp_rec IN EXECUTE 'SELECT display_name, description , snmp_oid FROM pem.alert_template ' || where_clause || ' ORDER BY snmp_oid'
	LOOP
		is_alert_found = true;
		tmp_rec.display_name = lower(tmp_rec.display_name);
		tmp_rec.display_name = replace(tmp_rec.display_name, '(', '');
		tmp_rec.display_name = replace(tmp_rec.display_name, ')', '');
		tmp_rec.display_name = replace(tmp_rec.display_name, ',', '');
		tmp_rec.display_name = replace(tmp_rec.display_name, '-', '');
		tmp_rec.display_name = replace(tmp_rec.display_name, '_', '');
		tmp_rec.display_name = initcap(tmp_rec.display_name);
		tmp_rec.display_name = replace(tmp_rec.display_name, ' ', '');

		IF char_length(tmp_rec.display_name) > 62 THEN
			tmp_rec.display_name = substr(tmp_rec.display_name, 0, 62);
		END IF;

		return_text =  return_text || E'\n\n\t' || object_prefix || tmp_rec.display_name || E'   NOTIFICATION-TYPE
		OBJECTS			' || object_string || E'
		STATUS			current
		DESCRIPTION \t\t"'	||	tmp_rec.description || E'"
		::=  {  ' || parent_node || '  ' || tmp_rec.snmp_oid::text ||  '  }';

		group_text = group_text || E'\n\t\t\t' ||object_prefix || tmp_rec.display_name || E',';
	END LOOP;

	group_text = trim(trailing ',' from group_text);

	group_text = group_text || '}
	STATUS 	current
	DESCRIPTION
		"'|| group_description ||'"
	::= { postgresql ' || group_oid_type || '}';

	IF is_alert_found THEN
		RETURN group_text || return_text;
	ELSE
		RETURN return_text;
	END IF;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION pem.purge_data() RETURNS void AS
$BODY$
DECLARE
	curs_probe           CURSOR FOR
		SELECT probe_internal_name, parameter_name_list,
			parameter_value_list, lifetime
		FROM pem.probe_target_view;

	table_name           varchar;
	parameter_name_list  text[];
	parameter_value_list text[];
	lifetime             integer;

	i                    integer; -- Counter
	where_clause         varchar;
	subquery             varchar;

BEGIN

	FOR probe IN curs_probe LOOP

	table_name := 'pemhistory.' || pg_catalog.quote_ident(probe.probe_internal_name);
	parameter_name_list := probe.parameter_name_list;
	parameter_value_list := probe.parameter_value_list;
	lifetime := probe.lifetime;

	where_clause := 'WHERE ';

	FOR i IN array_lower(parameter_name_list, 1)..array_upper(parameter_name_list, 1)
	LOOP
		where_clause := where_clause || parameter_name_list[i] || ' = ' || pg_catalog.quote_literal(parameter_value_list[i]::text) || ' AND ';
	END LOOP;

	where_clause := where_clause || 'recorded_time < (now() - interval ''' || lifetime || ' days'' ) ';

	subquery := 'SELECT recorded_time FROM ' || table_name || ' ' || where_clause || 'ORDER BY recorded_time DESC LIMIT 1';

	where_clause := where_clause || ' AND recorded_time < (' || subquery || ')';

	EXECUTE 'DELETE FROM ' || table_name || ' ' || where_clause;

	END LOOP;

END;
$BODY$ LANGUAGE plpgsql;

DROP FUNCTION pem.data_reconstruction (text, text, timestamp with time zone, timestamp with time zone, interval, character varying[], character varying[], integer, boolean, character varying[]);
-- data_reconstruction function return values as follows:
-- From start_time to probe_start_time: NULL values
-- From generate_series(start_time, end_time): probe value if it is not NULL.
--												0 if it is NULL.
-- if end_time < agent last heart beat time, end_time is updated to last heart
-- beat time and NULL values are shown if it is capacity manager or 0 in case
-- of landing pages.
CREATE OR REPLACE FUNCTION pem.data_reconstruction(probe_table text,
	probe_data_column text, start_time timestamp with time zone,
	end_time timestamp with time zone, time_interval interval,
	probe_target_key_list varchar[], probe_target_value_list varchar[],
	agentid integer, is_capacity_manager boolean, restricted_dbs varchar[] DEFAULT NULL,
	OUT metric_time timestamp with time zone, OUT recorded_value numeric)
RETURNS SETOF RECORD
AS $$
DECLARE
	conditional_clause text;
	groupby_clause text;

	raw_query text;
	new_query text;

	heartbeat_freq interval := 0;
	last_heartbeat timestamp with time zone := NULL;
	tmp_end_time timestamp with time zone := NULL;
	adjusted_start_time timestamp with time zone := NULL;

	raw_data REFCURSOR;

	current_record record;
	next_record record;
	new_record record;

BEGIN
	-- Sanity checks.
	IF (time_interval <= '0'::interval) THEN
		RAISE EXCEPTION 'time_interval must be greater than zero';
	END IF;
	IF (start_time >= end_time) THEN
		RAISE EXCEPTION 'start_time must be greater than end_time';
	END IF;

	EXECUTE 'SELECT (SELECT heartbeat_interval FROM pem.agent where id = ' || agentid
		|| ') * ''1 second''::interval' INTO heartbeat_freq;

	EXECUTE 'SELECT last_heartbeat FROM pem.agent_heartbeat WHERE agent_id = '
		|| agentid INTO last_heartbeat;

	IF last_heartbeat IS NULL THEN
		tmp_end_time = end_time;
	ELSE
		EXECUTE 'SELECT (CASE WHEN last_heartbeat + '
			|| pg_catalog.quote_literal(heartbeat_freq::text) || ' < '
			|| pg_catalog.quote_literal(end_time::text)
			|| 'THEN last_heartbeat ELSE '
			|| pg_catalog.quote_literal(end_time::text)
			|| ' END) FROM pem.agent_heartbeat WHERE agent_id = '
			|| agentid INTO tmp_end_time;
	END IF;

	-- Work out conditional_clause based on probe target.
	SELECT string_agg(pg_catalog.quote_ident(probe_target_key_list[i]) || ' = ' ||
		pg_catalog.quote_literal(probe_target_value_list[i]::text), ' AND ')
		FROM generate_series(array_lower(probe_target_key_list,1),
		array_upper(probe_target_key_list,1)) i INTO conditional_clause;

	-- Work out comma separated probe_target_key_list to create group by
	-- clause.
	SELECT string_agg(pg_catalog.quote_ident(probe_target_key_list[i]), ', ')
		FROM generate_series(array_lower(probe_target_key_list,1),
		array_upper(probe_target_key_list,1)) i INTO groupby_clause;

	-- Add restricted database clause
	IF count(restricted_dbs) > 0 THEN
		conditional_clause = conditional_clause || ' AND ' || probe_table || '.database_name = ANY( ' || pg_catalog.quote_literal(restricted_dbs::text) || ')';
	END IF;

	-- Get the time when probe started collecting the data
	EXECUTE 'SELECT COALESCE(MAX(recorded_time), NULL::timestamptz) AS recorded_time FROM pemhistory.'
		|| pg_catalog.quote_ident(probe_table)
		|| ' WHERE recorded_time <= '
		|| pg_catalog.quote_literal(start_time::text) || '::timestamptz'
		|| COALESCE(' AND ' || conditional_clause, '')
		INTO adjusted_start_time;

	-- Fetch the data.
	IF is_capacity_manager THEN
		raw_query = 'SELECT recorded_time, ';
		IF adjusted_start_time IS NULL THEN
			raw_query = raw_query || 'COALESCE( '
				|| pg_catalog.quote_ident(probe_data_column)
				|| ', 0::numeric) AS metric_value FROM pemhistory.'
				|| pg_catalog.quote_ident(probe_table)
				|| ' WHERE recorded_time >= '
				|| pg_catalog.quote_literal(start_time::text)
				|| '::timestamptz';
		ELSE
			raw_query = raw_query || pg_catalog.quote_ident(probe_data_column)
				|| ' AS metric_value FROM pemhistory.'
				|| pg_catalog.quote_ident(probe_table)
				|| ' WHERE recorded_time >= '
				|| pg_catalog.quote_literal(adjusted_start_time::text)
				|| '::timestamptz';
		END IF;
		raw_query = raw_query || ' AND recorded_time <= '
			|| pg_catalog.quote_literal(tmp_end_time::text) || '::timestamptz'
			|| COALESCE(' AND ' || conditional_clause, '');
	ELSE -- Queries for landing pages
		-- SUM(probe_data_column) has been used to aggregate the values. For
		-- example on server page if nummbackends are to be
		-- found then SUM() will be taken after applying group by on
		-- server_id for all databases.
		-- truncate has been used in group by clause because
		-- sometimes data collection has time difference in miliseconds
		raw_query = 'SELECT MAX(recorded_time) AS recorded_time, SUM(';
		IF adjusted_start_time IS NULL THEN
			raw_query = raw_query || 'COALESCE( '
				|| pg_catalog.quote_ident(probe_data_column)
				|| ', 0::numeric)) AS metric_value FROM pemhistory.'
				|| pg_catalog.quote_ident(probe_table)
				|| ' WHERE recorded_time >= '
				|| pg_catalog.quote_literal(start_time::text) || '::timestamptz';
		ELSE
			raw_query = raw_query || pg_catalog.quote_ident(probe_data_column)
				|| ') AS metric_value FROM pemhistory.'
				|| pg_catalog.quote_ident(probe_table)
				|| ' WHERE recorded_time >= '
				|| pg_catalog.quote_literal(adjusted_start_time::text) || '::timestamptz';
		END IF;

		raw_query = raw_query
			|| ' AND recorded_time <= '
			|| pg_catalog.quote_literal(tmp_end_time::text) || '::timestamptz'
			|| COALESCE(' AND ' || conditional_clause, '')
			|| ' GROUP BY date_trunc(''second'', recorded_time), ' || groupby_clause
			|| ' ORDER BY recorded_time';

	END IF;

	OPEN raw_data FOR EXECUTE raw_query;

	FETCH raw_data INTO current_record;
	FETCH raw_data INTO next_record;

	new_query
		= 'SELECT ts AS recorded_time, NULL::numeric AS metric_value FROM generate_series('
		|| pg_catalog.quote_literal(start_time::text) || '::timestamptz, '
		|| pg_catalog.quote_literal(tmp_end_time::text) || '::timestamptz, '
		|| pg_catalog.quote_literal(time_interval::text) || '::interval) ts';


	FOR new_record IN EXECUTE new_query
	LOOP
		IF (current_record.recorded_time IS NOT NULL
			AND current_record.recorded_time <= new_record.recorded_time) THEN
			IF (next_record IS NULL OR
				new_record.recorded_time < next_record.recorded_time) THEN
				new_record.metric_value = current_record.metric_value;
			ELSE
				new_record.metric_value = next_record.metric_value;
				current_record = next_record;

				FETCH raw_data INTO next_record;
			END IF;
		END IF;
		metric_time = new_record.recorded_time;
		recorded_value = new_record.metric_value;

		RETURN NEXT;

	END LOOP;

	CLOSE raw_data;

	-- If agent is down
	IF tmp_end_time < end_time THEN
		new_query
			= 'SELECT ts AS recorded_time, 0::numeric AS metric_value FROM generate_series('
			|| pg_catalog.quote_literal(tmp_end_time::text) || '::timestamptz, '
			|| pg_catalog.quote_literal(end_time::text) || '::timestamptz, '
			|| pg_catalog.quote_literal(time_interval::text) || '::interval) ts';

		--OPEN new_data FOR new_query;
		FOR new_record IN EXECUTE new_query
		LOOP
			metric_time = new_record.recorded_time;
			recorded_value = new_record.metric_value;

			RETURN NEXT;
		END LOOP;
	END IF;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION pem.data_rollup(probe_table text,
	aggregate_function text, probe_data_column text,
	start_time timestamp with time zone, end_time timestamp with time zone,
	time_interval interval, required_points int,
	probe_target_key_list varchar[], probe_target_value_list varchar[],
	agentid integer, is_capacity_manager boolean,
	restricted_dbs varchar[] DEFAULT NULL)
RETURNS TABLE (aggregated_time timestamp with time zone, aggregated_value numeric)
AS $$
DECLARE
	y_record RECORD;
	data_timestamp timestamptz[];
	data_value numeric[];
	count int;
	curs refcursor;
BEGIN
	-- Create a cursor to store actual points
	IF count(restricted_dbs) > 0 THEN
		OPEN curs FOR EXECUTE  'SELECT metric_time, recorded_value::numeric
								FROM pem.data_reconstruction(' || pg_catalog.quote_literal(probe_table) || ','
											|| pg_catalog.quote_literal(probe_data_column) || ','
											|| pg_catalog.quote_literal(start_time::text) || ','
											|| pg_catalog.quote_literal(end_time::text) || ','
											|| pg_catalog.quote_literal(time_interval::text) || ','
											|| pg_catalog.quote_literal(probe_target_key_lis::textt) || ','
											|| pg_catalog.quote_literal(probe_target_value_list::text)  || ','
											|| pg_catalog.quote_literal(agentid::text)  || ','
											|| pg_catalog.quote_literal(is_capacity_manager::text)  || ','
											|| pg_catalog.quote_literal(restricted_dbs::text)
											|| ')';
	ELSE
		OPEN curs FOR EXECUTE  'SELECT metric_time, recorded_value::numeric
								FROM pem.data_reconstruction(' || pg_catalog.quote_literal(probe_table) || ','
											|| pg_catalog.quote_literal(probe_data_column) || ','
											|| pg_catalog.quote_literal(start_time::text) || ','
											|| pg_catalog.quote_literal(end_time::text) || ','
											|| pg_catalog.quote_literal(time_interval::text) || ','
											|| pg_catalog.quote_literal(probe_target_key_list::text) || ','
											|| pg_catalog.quote_literal(probe_target_value_list::text)  || ','
											|| pg_catalog.quote_literal(agentid::text)  || ','
											|| pg_catalog.quote_literal(is_capacity_manager::text)
											|| ')';
	END IF;
	count = 0;
	LOOP
		FETCH curs INTO y_record;
		EXIT WHEN NOT FOUND;
		IF (y_record.metric_time IS NOT NULL) THEN
			data_timestamp[count] = y_record.metric_time;
			data_value[count] = y_record.recorded_value;
			count = count + 1;
		END IF;
	END LOOP;

	RETURN QUERY EXECUTE 'SELECT agg_time AS aggregated_time, agg_value AS aggregated_value FROM pem.data_aggregation(' ||
		pg_catalog.quote_literal(aggregate_function::text) || '::text,' || pg_catalog.quote_literal(data_timestamp::text) || '::timestamptz[],' ||
		pg_catalog.quote_literal(data_value::text) || '::numeric[],' || pg_catalog.quote_literal(count::text) || '::int,' ||
		pg_catalog.quote_literal(required_points::text) || ')';
END
$$ LANGUAGE plpgsql;

-- This function executes the linear trend analysis on a given set of data to predict
-- the trend in the future between the given start time and end time or the cut-off
-- threshold values based on the linear regression model
CREATE OR REPLACE FUNCTION pem.linear_trend_analysis (probe_table text,
							aggregate_function text,
							probe_data_column text,
							start_time timestamp with time zone,
							end_time timestamp with time zone,
							cur_time timestamp with time zone,
							time_interval interval,
							required_points int,
							probe_target_key_list varchar[],
							probe_target_value_list varchar[],
							cutoff_count int,
							agent_id int)
RETURNS TABLE (trend_metric_time timestamp with time zone, trend_metric_value numeric)
AS $$
DECLARE
	data_timestamp timestamptz[];
	data_value numeric[];
	i int :=0;
	count int := 0;
	xa numeric := 0;
	ya numeric := 0;
	xx numeric := 0;
	xy numeric := 0;
	ma numeric := 0;
	mb numeric := 0;
	start_epoch numeric;
	end_epoch1 numeric;
	end_epoch2 numeric;
	tmpx numeric;
	tmpy numeric;
	tmpt numeric;
	tmp_val numeric;
	tmp_et1 numeric;
	tmp_row RECORD;
	tmp_time timestamp with time zone;
	percent_unit boolean;
BEGIN
	-- check if unit of metric is of type % or not. if it is then the metric bound at extrapolation should never cross 100.
	EXECUTE 'SELECT (CASE WHEN unit_of_value = ''%'' THEN true ELSE false END) FROM pem.probe_column WHERE probe_id=(SELECT id FROM pem.probe WHERE internal_name='
	|| pg_catalog.quote_literal(probe_table) || ') AND internal_name=' || pg_catalog.quote_literal (probe_data_column) INTO percent_unit;

	-- get current time and unix epoch for comparison sake
	SELECT EXTRACT(EPOCH FROM start_time) INTO start_epoch;
	SELECT EXTRACT(EPOCH FROM cur_time) INTO end_epoch1;
	SELECT EXTRACT(EPOCH FROM end_time) INTO end_epoch2;
	IF (end_epoch2 <= end_epoch1) THEN
		cur_time = end_time;
	END IF;

	-- get data till current time from start time from data rollup function & calculate mean of value & time interval
	-- caculating xa = sum_of(time - start_time)
	--            ya = sum_of(value)
	-- these values are returned by data_reconstruction function for given start_time to end_time
	FOR tmp_row IN SELECT metric_time, recorded_value FROM pem.data_reconstruction (probe_table, probe_data_column,
		start_time, cur_time, time_interval, probe_target_key_list, probe_target_value_list, agent_id, true)
	LOOP
		IF (NOT tmp_row.recorded_value IS NULL) THEN
			data_timestamp[count] = tmp_row.metric_time;
			data_value[count] = tmp_row.recorded_value;
			SELECT EXTRACT(EPOCH FROM tmp_row.metric_time) INTO tmpt;
			xa = xa + (tmpt - start_epoch);
			ya = ya + tmp_row.recorded_value;
			count = count + 1;
		END IF;
	END LOOP;

	-- if we have less data then generation of chart is irrelevant
	IF (count < 3) THEN
		RAISE EXCEPTION '1';
		RETURN;
	END IF;

	-- get mean
	xa = xa / count;
	ya = ya / count;

	-- compute values to get values of a & b for linear equation which is (y = a + bx)
	-- where a = intercept & b = slope
	-- b = sum_of((x(i) - xa) * (y(i) - ya)) / sum_of((x(i) - xa)^2)
	-- a = ya - (b * xa)
	-- refer http://en.wikipedia.org/wiki/Regression_analysis#Linear_regression
	-- for understanding the formula
	FOR i IN 0..(count - 1)
	LOOP
		SELECT EXTRACT(EPOCH FROM data_timestamp[i]) INTO tmpt;
		tmpx = (tmpt - start_epoch) - xa;
		IF (data_value[i] IS NULL) THEN
			tmpy = 0 - ya;
		ELSE
			tmpy = data_value[i] - ya;
		END IF;
		xx = xx + (tmpx * tmpx);
		xy = xy + (tmpx * tmpy);
	END LOOP;

	-- if slope is 0 then there is no graph may get divide by 0 error
	IF (abs(xx) = 0) THEN
		RAISE EXCEPTION '2';
		RETURN;
	END IF;

	-- get a & b value
	mb = xy / xx;
	ma = ya - (mb * xa);

	-- now apply the equation to the extrapolated data if the end time
	-- is greater than the current time, else return the currently collected
	-- data.
	IF (end_epoch2 <= end_epoch1) THEN
		IF cutoff_count != 0 THEN
			IF cutoff_count < count THEN
				count = cutoff_count;
			END IF;
		END IF;
	ELSE
		tmp_time = data_timestamp[count - 1];
		SELECT EXTRACT (EPOCH FROM tmp_time) INTO tmp_et1;
		WHILE tmp_et1 < end_epoch2
		LOOP
			tmp_time = tmp_time + time_interval;
			tmpt = (SELECT EXTRACT( EPOCH FROM tmp_time)) - start_epoch;
			tmp_val = ma + (mb * tmpt);
			IF tmp_val < 0 THEN
				data_value[count] = NULL;
			ELSE
				IF percent_unit = TRUE AND tmp_val > 100 THEN
					data_value[count] = 100;
				ELSE
					data_value[count] = tmp_val;
				END IF;
			END IF;
			data_timestamp[count] = tmp_time;
			count = count + 1;
			IF (cutoff_count != 0) THEN
				-- exit if cut off point is reached
				EXIT WHEN count >= cutoff_count;
			END IF;
			SELECT EXTRACT (EPOCH FROM tmp_time) INTO tmp_et1;
		END LOOP;
	END IF;

	RETURN QUERY EXECUTE 'SELECT agg_time AS trend_metric_time, agg_value AS trend_metric_value FROM pem.data_aggregation(' ||
			pg_catalog.quote_literal(aggregate_function) || '::text,' || pg_catalog.quote_literal(data_timestamp::text) || '::timestamptz[],' ||
			pg_catalog.quote_literal(data_value::text) || '::numeric[],' || pg_catalog.quote_literal(count::text) || '::int,' ||
			pg_catalog.quote_literal(required_points::text) || ')';
END
$$ LANGUAGE plpgsql;

-- This function returns the cut-off count for a given metric for when its value
-- will either exceed or falls below the given threhold when we apply the linear
-- regression model to it.
CREATE OR REPLACE FUNCTION pem.linear_trend_threshold (probe_table text,
							probe_data_column text,
							start_time timestamp with time zone,
							cur_time timestamp with time zone,
							threshold numeric,
							exceeds_opr boolean,
							time_interval interval,
							probe_target_key_list varchar[],
							probe_target_value_list varchar[],
							max_end_time_in_years int,
							agent_id int)
RETURNS int
AS $$
DECLARE
	data_timestamp timestamptz[];
	data_value numeric[];
	count int := 0;
	i int :=0;
	final_end_time timestamp with time zone;
	xa numeric := 0;
	ya numeric := 0;
	xx numeric := 0;
	xy numeric := 0;
	ma numeric := 0;
	mb numeric := 0;
	start_epoch numeric;
	end_epoch numeric;
	tmp_et numeric;
	tmpx numeric;
	tmpy numeric;
	tmpt numeric;
	tmp_last_time timestamp with time zone;
	tmp_row RECORD;
	percent_unit boolean;
BEGIN
	-- check if unit of metric is of type % or not. if it is then the metric bound at extrapolation should never cross 100.
	EXECUTE 'SELECT (CASE WHEN unit_of_value = ''%'' THEN true ELSE false END) FROM pem.probe_column WHERE probe_id=(SELECT id FROM pem.probe WHERE internal_name='
	|| pg_catalog.quote_literal(probe_table) || ') AND internal_name=' || pg_catalog.quote_literal (probe_data_column) INTO percent_unit;

	IF percent_unit = TRUE AND threshold > 100 THEN
		threshold = 100;
	END IF;

	-- get current time and final time is which is (x) years in future
	SELECT cur_time + (max_end_time_in_years * '1 year'::interval) INTO final_end_time;

	-- get unix epoch for comparison sake
	SELECT EXTRACT(EPOCH FROM start_time) INTO start_epoch;
	SELECT EXTRACT(EPOCH FROM final_end_time) INTO end_epoch;

	-- get data till current time from start time from data rollup function & calculate mean of value & time interval
	-- caculating xa = sum_of(time - start_time)
	--            ya = sum_of(value)
	-- these values are returned by data_rollup function for given start_time to end_time
	FOR tmp_row IN SELECT metric_time, recorded_value FROM pem.data_reconstruction (probe_table, probe_data_column,
		start_time, cur_time, time_interval, probe_target_key_list, probe_target_value_list, agent_id, true)
	LOOP
		IF (NOT tmp_row.recorded_value IS NULL) THEN
			data_timestamp[count] = tmp_row.metric_time;
			data_value[count] = tmp_row.recorded_value;
			SELECT EXTRACT(EPOCH FROM tmp_row.metric_time) INTO tmpt;
			xa = xa + (tmpt - start_epoch);
			ya = ya + tmp_row.recorded_value;
			count = count + 1;
		END IF;
	END LOOP;

	-- if we have less data then generation of chart is irrelevant
	IF (count < 3) THEN
		RAISE EXCEPTION '1';
	END IF;

	-- get mean
	xa = xa / count;
	ya = ya / count;

	-- compute values to get values of a & b for linear equation which is (y = a + bx)
	-- where a = intercept & b = slope
	-- b = sum_of((x(i) - xa) * (y(i) - ya)) / sum_of((x(i) - xa)^2)
	-- a = ya - (b * xa)
	-- refer http://en.wikipedia.org/wiki/Regression_analysis#Linear_regression
	-- for understanding the formula
	FOR i IN 0..(count - 1)
	LOOP
		SELECT EXTRACT(EPOCH FROM data_timestamp[i]) INTO tmpt;
		tmpx = (tmpt - start_epoch) - xa;
		IF (data_value[i] IS NULL) THEN
			tmpy = 0 - ya;
		ELSE
			tmpy = data_value[i] - ya;
		END IF;
		xx = xx + (tmpx * tmpx);
		xy = xy + (tmpx * tmpy);
	END LOOP;

	-- if slope is 0 then there is no graph may get divide by 0 error
	IF (abs(xx) = 0) THEN
		RAISE EXCEPTION '2';
	END IF;

	-- get a & b value
	mb = xy / xx;
	ma = ya - (mb * xa);

	-- now apply the equation to extrapolated data till you reach the
	-- given threshold or you reach the final end time.
	tmp_last_time = data_timestamp[count - 1];
	SELECT EXTRACT (EPOCH FROM tmp_last_time) INTO tmp_et;
	WHILE tmp_et < end_epoch
	LOOP
		tmp_last_time = tmp_last_time + time_interval;
		tmpt = (SELECT EXTRACT( EPOCH FROM tmp_last_time)) - start_epoch;
		tmpy = ma + (mb * tmpt);
		count = count + 1;

		IF (tmpy < 0) THEN
			RETURN count;
		END IF;

		IF (exceeds_opr = TRUE) THEN
			IF (tmpy > threshold) THEN
				RETURN count-1;
			END IF;
		ELSE
			IF (tmpy < threshold) THEN
				RETURN count-1;
			END IF;
		END IF;
		SELECT EXTRACT (EPOCH FROM tmp_last_time) INTO tmp_et;
	END LOOP;

	RETURN count-1;
END
$$ LANGUAGE plpgsql;

-- This function returns the aggregated value and time for the data points given as
-- input to this function, based on the aggregated function to use. It also takes the
-- the actual no. of points and the no. of to reduce to into consideration for applying
-- the aggregation.
CREATE OR REPLACE FUNCTION pem.data_aggregation (aggregate_function text,
							data_timestamp timestamptz[],
							data_value numeric[],
							actual_points int,
							required_points int)
RETURNS TABLE (agg_time timestamp with time zone, agg_value numeric)
AS $$
DECLARE
	start_time timestamptz := NULL;
	end_time timestamptz := NULL;
	diff_interval interval := NULL;
	count int := 0;
	i int := 0;
	data_array numeric[];
	tmp int;
BEGIN
	-- if required points are not given the return actual points
	IF (required_points = 0) THEN
		RETURN QUERY EXECUTE 'SELECT unnest(' || pg_catalog.quote_literal(data_timestamp::text) || '::timestamptz[]) AS agg_time, unnest(' ||
			pg_catalog.quote_literal(data_value::text) || '::numeric[]) AS agg_value';
	ELSE
		-- if actual points are less than required points then no need to apply aggregation
		IF (required_points >= actual_points) THEN
			RETURN QUERY EXECUTE 'SELECT unnest(' || pg_catalog.quote_literal(data_timestamp::text) || '::timestamptz[]) AS agg_time, unnest(' ||
				pg_catalog.quote_literal(data_value::text) || '::numeric[]) AS agg_value';
		ELSE
			diff_interval = (data_timestamp[actual_points - 1] - data_timestamp[0]) / required_points;
			start_time := data_timestamp[0];
			end_time := data_timestamp[0] + diff_interval;
			WHILE count < actual_points
			LOOP
				agg_time = start_time;
				-- collect the set of points and apply aggregation to it and return the resultant point
				i = 0;
				WHILE data_timestamp[count] <= end_time
				LOOP
					EXIT WHEN count = actual_points;
					data_array[i] = data_value[count];
					i = i + 1;
					count = count + 1;
				END LOOP;

				IF (aggregate_function = 'FIRST') THEN
					agg_value = data_array[0];
				ELSE
					EXECUTE 'SELECT ' || aggregate_function || '(x)
							FROM (SELECT unnest(' || pg_catalog.quote_literal(data_array::text) || '::numeric[]) AS x) AS y'
							INTO agg_value;
				END IF;
				RETURN NEXT;

				-- reset the data array
				tmp = 0;
				WHILE tmp < i
				LOOP
					data_array[tmp] = NULL;
					tmp = tmp + 1;
				END LOOP;

				-- set the time counters ahead
				start_time := end_time;
				end_time := end_time + diff_interval;
			END LOOP;
		END IF;
	END IF;
	RETURN;
END
$$ LANGUAGE plpgsql;

-- First argument takes the agent id as integer value
-- Second argument takes the last number of hours users wants to get the data
-- Third argument takes type of error severity e.g. 1 - ERROR , 2- WARNING, 3 - ERROR OR WARNING
CREATE OR REPLACE FUNCTION pem.agent_level_number_errors_warning_logfile (integer, integer, integer)
RETURNS integer AS $$

DECLARE
        total_servers RECORD;
        total_errors integer;
        error_count integer;

BEGIN
        total_errors := 0;
        error_count := 0;

        -- Find one agent is bindning to how many servers and depending on that total count will be calculated
        FOR total_servers IN SELECT DISTINCT server_id FROM pem.agent_server_binding WHERE agent_id = $1 ORDER BY server_id ASC LOOP

                error_count := 0;

                -- If user requested for ERROR count only then below condition will be executed
                IF $3 = 1 THEN
                        SELECT COUNT(log_time) INTO error_count FROM pemdata.server_logs WHERE error_severity = 'ERROR' AND server_id = total_servers.server_id  AND log_time > now() - ($2)*'1 hours'::interval;
                END IF;

                -- If user requested for WARNING count only then below condition will be executed
                IF $3 = 2 THEN
                        SELECT COUNT(log_time) INTO error_count FROM pemdata.server_logs WHERE error_severity = 'WARNING' AND server_id = total_servers.server_id  AND log_time > now() - ($2)*'1 hours'::interval;
                END IF;

                -- If user requested for WARNING OR ERROR count only then below condition will be executed
                IF $3 = 3 THEN
                        SELECT COUNT(log_time) INTO error_count FROM pemdata.server_logs WHERE (error_severity = 'ERROR' OR error_severity = 'WARNING') AND server_id = total_servers.server_id  AND log_time > now() - ($2)*'1 hours'::interval;
                END IF;

               total_errors := total_errors + error_count;
        END LOOP;

        RETURN total_errors;

END;

$$ LANGUAGE plpgsql;


SELECT pem.create_alert_template(
        'Number of ERRORS in the logfile on server M in the last X hours',
        'The number of ERRORS in the logfile on server M in last X hours',
        $sql$
SELECT COUNT(log_time)
FROM pemdata.server_logs
WHERE error_severity = 'ERROR'
AND server_id = ${server_id}
AND log_time > now() - '${param_1} hours'::interval$sql$,
        200, '{ERRORS in the logfile in last X hours}', '{INTEGER}', '{Hours}', NULL,'{}', 57);

SELECT pem.create_alert_template(
        'Number of WARNINGS in the logfile on server M in the last X hours',
        'The number of WARNINGS in logfile on server M in the last X hours',
        $sql$
SELECT COUNT(log_time)
FROM pemdata.server_logs
WHERE error_severity = 'WARNING'
AND server_id = ${server_id}
AND log_time > now() - '${param_1} hours'::interval$sql$,
        200, '{WARNINGS in the logfile in last X hours}', '{INTEGER}', '{Hours}', NULL,'{}', 58);

SELECT pem.create_alert_template(
        'Number of WARNINGS or ERRORS in the logfile on server M in the last X hours',
        'The number of WARNINGS or ERRORS in the logfile on server M in the last X hours',
        $sql$
SELECT COUNT(log_time)
FROM pemdata.server_logs
WHERE (error_severity = 'WARNING' OR error_severity = 'ERROR')
AND server_id = ${server_id}
AND log_time > now() - '${param_1} hours'::interval$sql$,
        200, '{WARNINGS or ERRORS in the logfile in last X hours}', '{INTEGER}', '{Hours}', NULL,'{}', 59);

SELECT pem.create_alert_template(
        'Number of ERRORS in the logfile on agent N in last X hours',
        'The number of ERRORS in the logfile on agent N in last X hours',
        $sql$
SELECT * FROM pem.agent_level_number_errors_warning_logfile(${agent_id},${param_1},1)$sql$,
        100, '{ERRORS in the logfile in last X hours}', '{INTEGER}', '{Hours}', NULL,'{}', 24);

SELECT pem.create_alert_template(
        'Number of WARNINGS in the logfile on agent N in last X hours',
        'The number of WARNINGS in the logfile on agent N in last X hours',
        $sql$
SELECT * FROM pem.agent_level_number_errors_warning_logfile(${agent_id},${param_1},2)$sql$,
        100, '{WARNINGS in the logfile in last X hours}', '{INTEGER}', '{Hours}', NULL,'{}', 25);

SELECT pem.create_alert_template(
        'Number of WARNINGS or ERRORS in the logfile on agent N in last X hours',
        'The number of WARNINGS or ERRORS in the logfile on agent N in last X hours',
        $sql$
SELECT * FROM pem.agent_level_number_errors_warning_logfile(${agent_id},${param_1},3)$sql$,
        100, '{WARNINGS or ERRORS in the logfile in last X hours}', '{INTEGER}', '{Hours}', NULL,'{}', 26);

-- SQL/Protect

-- First argument takes last number of minutes user wants to get the data
-- Second argument takes the server id as integer

CREATE OR REPLACE FUNCTION pem.number_sqlinjection_attacks_detected (integer,integer)
RETURNS integer AS $$

DECLARE
    total_count integer;
    user_requested_count integer;
    total_attacks_detected integer;
    tmp_count integer;
    tmp_days integer;
    attack_count_per_user integer;
    tmp_loop_count integer;
    total_users RECORD;
    last_row_fetched RECORD;
    first_row_fetched RECORD;
    tmp_flag boolean;

BEGIN
    total_count := 0;
    user_requested_count := 0;
    total_attacks_detected := 0;
    tmp_count := 0;
    tmp_days := 1;
    tmp_loop_count := 1;

    FOR total_users IN SELECT DISTINCT username FROM pemhistory.sql_protect WHERE server_id = $2 LOOP

        -- Find the total number of rows for specific user in the table
        SELECT count(*) INTO total_count FROM pemhistory.sql_protect WHERE server_id = $2 AND username = total_users.username;
        -- Find the rows for specific user for user requested last N minutes in the table
        SELECT count(*) INTO user_requested_count FROM pemhistory.sql_protect WHERE server_id = $2 AND username = total_users.username AND recorded_time > now() - ($1)*'1 minutes'::interval;

        attack_count_per_user := 0;
        tmp_flag := false;

        -- If the difference is 1 then there are total two entry in the table and for first row we have directly get the value and count the number of attacks
       IF (total_count - user_requested_count) = 1 THEN

                -- Select the last value from the below query and search for previous until we get the difference
                SELECT superusers, relations, commands, tautology, dml INTO last_row_fetched FROM pemhistory.sql_protect WHERE server_id = $2 AND username = total_users.username AND recorded_time > now() - ($1)*'1 minutes'::interval ORDER BY recorded_time DESC LIMIT 1;


                SELECT superusers, relations, commands, tautology, dml INTO first_row_fetched FROM pemhistory.sql_protect WHERE server_id = $2 AND username = total_users.username ORDER BY recorded_time ASC LIMIT 1;

                attack_count_per_user := (last_row_fetched.superusers - first_row_fetched.superusers) + (last_row_fetched.relations - first_row_fetched.relations) + (last_row_fetched.commands - first_row_fetched.commands) + (last_row_fetched.tautology - first_row_fetched.tautology) + (last_row_fetched.dml - first_row_fetched.dml);

                tmp_flag := true;
	END IF;

	-- If total user count and user requested count for specific time is zero that means all the entry contains in the user requested time slot and no entry in the time slot before that so we have to take the decision based on the user requested count, if it is one then directly add the attacks and for more then one take the difference between the rows.
	IF (total_count - user_requested_count) = 0 THEN
		IF user_requested_count = 1 THEN
			SELECT SUM(superusers + relations + commands + tautology + dml) INTO attack_count_per_user FROM pemhistory.sql_protect WHERE server_id = $2 AND pemhistory.sql_protect.username = total_users.username AND recorded_time > now() - ($1)*'1 minutes'::interval;
			tmp_flag := true;

		ELSE
			WHILE (tmp_loop_count < user_requested_count) LOOP

				SELECT superusers, relations, commands, tautology, dml INTO last_row_fetched FROM pemhistory.sql_protect WHERE server_id = $2 AND pemhistory.sql_protect.username = total_users.username AND recorded_time > now() - ($1)*'1 minutes'::interval ORDER BY recorded_time DESC LIMIT 1 OFFSET (tmp_loop_count - 1);

				tmp_loop_count := tmp_loop_count + 1;

				SELECT superusers, relations, commands, tautology, dml INTO first_row_fetched FROM pemhistory.sql_protect WHERE server_id = $2 AND pemhistory.sql_protect.username = total_users.username AND recorded_time > now() - ($1)*'1 minutes'::interval ORDER BY recorded_time DESC LIMIT 1 OFFSET (tmp_loop_count - 1);

				attack_count_per_user := attack_count_per_user + (last_row_fetched.superusers - first_row_fetched.superusers) + (last_row_fetched.relations - first_row_fetched.relations) + (last_row_fetched.commands - first_row_fetched.commands) + (last_row_fetched.tautology - first_row_fetched.tautology) + (last_row_fetched.dml - first_row_fetched.dml);

			END LOOP;

			attack_count_per_user := attack_count_per_user + first_row_fetched.superusers + first_row_fetched.relations + first_row_fetched.commands + first_row_fetched.tautology + first_row_fetched.dml;

			tmp_flag := true;

                END IF;
        END IF;

        -- There are no entry in the table for that user so don't do anything
        IF (total_count - user_requested_count) = total_count THEN
                NULL;

        ELSE
                IF tmp_flag = false THEN

                -- Select the last row value from the below query
                SELECT superusers, relations, commands, tautology, dml INTO last_row_fetched FROM pemhistory.sql_protect WHERE server_id = $2 AND pemhistory.sql_protect.username = total_users.username AND recorded_time > now() - ($1)*'1 minutes'::interval ORDER BY recorded_time DESC LIMIT 1;

                -- Loop until we get the previous entry for specific user to take the difference to calculate the number of SQL injection attacks
                LOOP
                    tmp_days := tmp_days + 1;
                    SELECT count(*) INTO tmp_count FROM pemhistory.sql_protect WHERE server_id = $2 AND pemhistory.sql_protect.username = total_users.username AND recorded_time > now() - (tmp_days)*'1 days'::interval;

                    IF tmp_count > user_requested_count THEN
                        SELECT superusers, relations, commands, tautology, dml INTO first_row_fetched FROM pemhistory.sql_protect WHERE server_id = $2 AND pemhistory.sql_protect.username = total_users.username AND recorded_time > now() - (tmp_days)*'1 days'::interval ORDER BY recorded_time DESC LIMIT 1 OFFSET user_requested_count;
                        EXIT;
                   ELSE
                        tmp_days := tmp_days + 1;
                    END IF;

                END LOOP;

                attack_count_per_user := (last_row_fetched.superusers - first_row_fetched.superusers) + (last_row_fetched.relations - first_row_fetched.relations) + (last_row_fetched.commands - first_row_fetched.commands) + (last_row_fetched.tautology - first_row_fetched.tautology) + (last_row_fetched.dml - first_row_fetched.dml);

                END IF;

        END IF;

        -- Calculate the total number of SQL injection attacks for each user
        total_attacks_detected := total_attacks_detected + attack_count_per_user;

    END LOOP;

    RETURN total_attacks_detected;

END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION pem.number_sqlinjection_attacks_detected_by_username (integer,TEXT,integer)
RETURNS integer AS $$

DECLARE
    total_count integer;
    user_requested_count integer;
    tmp_count integer;
    tmp_days integer;
    attack_count_per_user integer;
    tmp_loop_count integer;
    last_row_fetched RECORD;
    first_row_fetched RECORD;
    tmp_flag boolean;

BEGIN
    total_count := 0;
    user_requested_count := 0;
    tmp_count := 0;
    tmp_days := 1;
    tmp_loop_count := 1;

    -- Find the total number of rows for specific user in the table
    SELECT count(*) INTO total_count FROM pemhistory.sql_protect WHERE server_id = $3 AND username = $2;
    -- Find the rows for specific user for user requested last N minutes in the table
    SELECT count(*) INTO user_requested_count FROM pemhistory.sql_protect WHERE server_id = $3 AND username = $2 AND recorded_time > now() - ($1)*'1 minutes'::interval;

    attack_count_per_user := 0;
    tmp_flag := false;

    -- If the difference is 1 then there are total two entry in the table and for first row we have directly get the value and count the number of attacks
    IF (total_count - user_requested_count) = 1 THEN

            -- Select the last value from the below query and search for previous until we get the difference
            SELECT superusers, relations, commands, tautology, dml INTO last_row_fetched FROM pemhistory.sql_protect WHERE server_id = $3 AND username = $2 AND recorded_time > now() - ($1)*'1 minutes'::interval ORDER BY recorded_time DESC LIMIT 1;


            SELECT superusers, relations, commands, tautology, dml INTO first_row_fetched FROM pemhistory.sql_protect WHERE server_id = $3 AND username = $2 ORDER BY recorded_time ASC LIMIT 1;

            attack_count_per_user := (last_row_fetched.superusers - first_row_fetched.superusers) + (last_row_fetched.relations - first_row_fetched.relations) + (last_row_fetched.commands - first_row_fetched.commands) + (last_row_fetched.tautology - first_row_fetched.tautology) + (last_row_fetched.dml - first_row_fetched.dml);

            tmp_flag := true;
    END IF;

    -- If total user count and user requested count for specific time is zero that means all the entry contains in the user requested time slot and no entry in the time slot before that so we have to take the decision based on the user requested count is one then dirctly add the attacks and for more then one take the difference between the rows.
    IF (total_count - user_requested_count) = 0 THEN
	IF user_requested_count = 1 THEN
		SELECT SUM(superusers + relations + commands + tautology + dml) INTO attack_count_per_user FROM pemhistory.sql_protect WHERE server_id = $3 AND pemhistory.sql_protect.username = $2 AND recorded_time > now() - ($1)*'1 minutes'::interval;
		tmp_flag := true;

	ELSE
		WHILE (tmp_loop_count < user_requested_count) LOOP

			SELECT superusers, relations, commands, tautology, dml INTO last_row_fetched FROM pemhistory.sql_protect WHERE server_id = $3 AND pemhistory.sql_protect.username = $2 AND recorded_time > now() - ($1)*'1 minutes'::interval ORDER BY recorded_time DESC LIMIT 1 OFFSET (tmp_loop_count - 1);

			tmp_loop_count := tmp_loop_count + 1;

			SELECT superusers, relations, commands, tautology, dml INTO first_row_fetched FROM pemhistory.sql_protect WHERE server_id = $3 AND pemhistory.sql_protect.username = $2 AND recorded_time > now() - ($1)*'1 minutes'::interval ORDER BY recorded_time DESC LIMIT 1 OFFSET (tmp_loop_count - 1);

			attack_count_per_user := attack_count_per_user + (last_row_fetched.superusers - first_row_fetched.superusers) + (last_row_fetched.relations - first_row_fetched.relations) + (last_row_fetched.commands - first_row_fetched.commands) + (last_row_fetched.tautology - first_row_fetched.tautology) + (last_row_fetched.dml - first_row_fetched.dml);

		END LOOP;

		attack_count_per_user := attack_count_per_user + first_row_fetched.superusers + first_row_fetched.relations + first_row_fetched.commands + first_row_fetched.tautology + first_row_fetched.dml;

		tmp_flag := true;

	END IF;
    END IF;

    -- There are no entry in the table for that user so don't do anything
    IF (total_count - user_requested_count) = total_count THEN
	NULL;

    ELSE
		IF tmp_flag = false THEN

		-- Select the last row value from the below query
		SELECT superusers, relations, commands, tautology, dml INTO last_row_fetched FROM pemhistory.sql_protect WHERE server_id = $3 AND pemhistory.sql_protect.username = $2 AND recorded_time > now() - ($1)*'1 minutes'::interval ORDER BY recorded_time DESC LIMIT 1;

		-- Loop until we get the previous entry for specific user to take the difference to calculate the number of SQL injection attacks
		LOOP
			tmp_days := tmp_days + 1;
			SELECT count(*) INTO tmp_count FROM pemhistory.sql_protect WHERE server_id = $3 AND pemhistory.sql_protect.username = $2 AND recorded_time > now() - (tmp_days)*'1 days'::interval;

			IF tmp_count > user_requested_count THEN
				SELECT superusers, relations, commands, tautology, dml INTO first_row_fetched FROM pemhistory.sql_protect WHERE server_id = $3 AND pemhistory.sql_protect.username = $2 AND recorded_time > now() - (tmp_days)*'1 days'::interval ORDER BY recorded_time DESC LIMIT 1 OFFSET user_requested_count;
				EXIT;
			ELSE
				tmp_days := tmp_days + 1;
			END IF;

		END LOOP;

		attack_count_per_user := (last_row_fetched.superusers - first_row_fetched.superusers) + (last_row_fetched.relations - first_row_fetched.relations) + (last_row_fetched.commands - first_row_fetched.commands) + (last_row_fetched.tautology - first_row_fetched.tautology) + (last_row_fetched.dml - first_row_fetched.dml);

		END IF;

    END IF;

    RETURN attack_count_per_user;

END;
$$ LANGUAGE plpgsql;
--
-- Probe: SQL/Protect and Alert
--
INSERT INTO pem.probe
        (display_name, internal_name, collection_method, target_type_id,
         enabled_by_default, force_enabled, default_execution_frequency,
         default_lifetime, any_server_version, probe_code)
VALUES
        ('SQL/Protect', 'sql_protect', 's', 200, false, false, 300, 180, true,
         'SELECT username, superusers, relations, commands, tautology, dml FROM sqlprotect.edb_sql_protect_stats');

INSERT INTO pem.probe_column
        (probe_id, internal_name, display_name, display_position, classification,
        sql_data_type, unit_of_value, calculate_pit, discard_history, pit_by_default, is_graphable)
SELECT
        (SELECT max(id) FROM pem.probe),
        v.internal_name, v.display_name, v.display_position, v.classification,
        v.sql_data_type, v.unit_of_value, v.calculate_pit, v.discard_history, v.pit_by_default, v.is_graphable
FROM
        (VALUES
                ('username', 'Username', 1, 'k', 'text', '#', false, false, false, false),
                ('superusers', '# Superuser Attacks', 2, 'm', 'integer', '#', false, false, false, true),
                ('relations', '# Relation Attacks', 3, 'm', 'integer', '#', false, false, false, true),
                ('commands', '# Command Attacks', 4, 'm', 'integer', '#', false, false, false, true),
                ('tautology', '# Tautological Attacks', 5, 'm', 'integer', '#', false, false, false, true),
                ('dml', '# DML Attacks', 6, 'm', 'integer', '#', false, false, false, true)
        ) v(internal_name, display_name, display_position, classification,
                sql_data_type, unit_of_value, calculate_pit, discard_history, pit_by_default, is_graphable);


--
-- Streaming Replication Functions
--

-- Function to convert the hexadecimal value to decimal value
-- Parameter 1 - hexadecimal value
CREATE OR REPLACE FUNCTION pem.hex_to_bigint(TEXT) RETURNS bigint AS $$
DECLARE
        result BIGINT;
BEGIN
        result := 0;

        EXECUTE 'SELECT CAST(X'|| quote_nullable($1) ||' AS BIGINT)' INTO result;

        RETURN result;
END;

$$
LANGUAGE plpgsql;


-- Function to give lag bytes if any of the slave lag behind the master in streaming replication
-- parameter 1 - User given bytes in MB to generate alert
-- parameter 2 - server id
-- parameter 3 - 1- write location, 2- flush location, 3 - replay location
CREATE OR REPLACE FUNCTION pem.number_replication_lag_bytes(integer, integer, integer)
RETURNS bigint AS $$
DECLARE
        xlog_sent_location BIGINT;
        xlog_write_location BIGINT;
        xlog_flush_location BIGINT;
        xlog_replay_location BIGINT;
        xlog_lag_bytes BIGINT;
        user_given_bytes integer;
        total_hostname RECORD;
        num_slave_lag integer;

BEGIN
        xlog_sent_location := 0;
        xlog_write_location := 0;
        xlog_flush_location := 0;
        xlog_replay_location := 0;
        user_given_bytes := $1;
        xlog_lag_bytes := 0;
        num_slave_lag := 0;

       IF $3 = 1 THEN
                -- For loop to extract the entry for each of the server and check if one of the slave is lag behind the master then raise alert
                FOR total_hostname IN SELECT client_addr FROM pemdata.streaming_replication LOOP
                        -- fetch the sent location that is sent by the master to the stanby server
                        SELECT sent_location INTO xlog_sent_location FROM pemdata.streaming_replication WHERE client_addr = total_hostname.client_addr AND server_id = $2;
                        -- fetch xlog location for write transaction by standby server
                        SELECT write_location INTO xlog_write_location FROM pemdata.streaming_replication WHERE client_addr = total_hostname.client_addr AND server_id = $2;

                        xlog_lag_bytes := (xlog_sent_location - xlog_write_location);

                        -- convert the bytes to MB and compare it with user given bytes to generate alert
                        IF floor(((xlog_lag_bytes/1024)/1024)) > CAST(user_given_bytes As BIGINT) THEN
                                num_slave_lag := num_slave_lag + 1;
                        END IF;

                END LOOP;
        END IF;

      IF $3 = 2 THEN
                -- For loop to extract the entry for each of the server and check if one of the slave is lag behind the master then raise alert
                FOR total_hostname IN SELECT client_addr FROM pemdata.streaming_replication LOOP
                        -- fetch the sent location that is sent by the master to the stanby server
                        SELECT sent_location INTO xlog_sent_location FROM pemdata.streaming_replication WHERE client_addr = total_hostname.client_addr AND server_id = $2;
                        -- fetch xlog location for flush transaction by standby server
                        SELECT flush_location INTO xlog_flush_location FROM pemdata.streaming_replication WHERE client_addr = total_hostname.client_addr AND server_id = $2;

                        xlog_lag_bytes := (xlog_sent_location - xlog_flush_location);

                        -- convert the bytes to MB and compare it with user given bytes to generate alert
                        IF floor(((xlog_lag_bytes/1024)/1024)) > CAST(user_given_bytes As BIGINT) THEN
                                num_slave_lag := num_slave_lag + 1;
                        END IF;

                END LOOP;
        END IF;

      IF $3 = 3 THEN
                -- For loop to extract the entry for each of the server and check if one of the slave is lag behind the master then raise alert
                FOR total_hostname IN SELECT client_addr FROM pemdata.streaming_replication LOOP
                        -- fetch the sent location that is sent by the master to the stanby server
                        SELECT sent_location INTO xlog_sent_location FROM pemdata.streaming_replication WHERE client_addr = total_hostname.client_addr AND server_id = $2;
                        -- fetch xlog location for replay transaction by standby server
                        SELECT replay_location INTO xlog_replay_location FROM pemdata.streaming_replication WHERE client_addr = total_hostname.client_addr AND server_id = $2;

                        xlog_lag_bytes := (xlog_sent_location - xlog_replay_location);

                        -- convert the bytes to MB and compare it with user given bytes to generate alert
                        IF floor(((xlog_lag_bytes/1024)/1024)) > CAST(user_given_bytes As BIGINT) THEN
                                num_slave_lag := num_slave_lag + 1;
                        END IF;

                END LOOP;
        END IF;

        RETURN num_slave_lag;

END;
$$ LANGUAGE plpgsql;


-- Function to check if user given host is lag behind the master or not
-- Parameter 1 - User given bytes in MB for alert
-- Parameter 2 - hostname
-- Parameter 3 - server id
-- Parameter 4 - 1 - write_location, 2 - flush_location, 3 - replay_location
CREATE OR REPLACE FUNCTION pem.replication_lag_bytes_by_hostname(integer,TEXT,integer,integer)
RETURNS bigint AS $$
DECLARE
        xlog_sent_location BIGINT;
        xlog_write_location BIGINT;
        xlog_flush_location BIGINT;
        xlog_replay_location BIGINT;
        user_given_bytes integer;
        xlog_lag_bytes BIGINT;

BEGIN
        xlog_sent_location := 0;
        xlog_write_location := 0;
        xlog_flush_location := 0;
        xlog_replay_location := 0;
        user_given_bytes := $1;
        xlog_lag_bytes := 0;

        -- fetch the sent location that is sent by the master to the stanby server
        SELECT sent_location INTO xlog_sent_location FROM pemdata.streaming_replication WHERE client_addr = $2 AND server_id = $3;

      IF $4 = 1 THEN

                -- fetch xlog location for write transaction by standby server
                SELECT write_location INTO xlog_write_location FROM pemdata.streaming_replication WHERE client_addr = $2 AND server_id = $3;

                xlog_lag_bytes := (xlog_sent_location - xlog_write_location);

                -- convert the bytes to MB and compare it with user given bytes to generate alert
                IF floor(((xlog_lag_bytes/1024)/1024)) > CAST(user_given_bytes As BIGINT) THEN
                        RETURN floor(((xlog_lag_bytes/1024)/1024));
                ELSE
                        RETURN 0;
                END IF;

        END IF;

        IF $4 = 2 THEN

                -- fetch xlog location for flush transaction by standby server
                SELECT flush_location INTO xlog_flush_location FROM pemdata.streaming_replication WHERE client_addr = $2 AND server_id = $3;

                xlog_lag_bytes := (xlog_sent_location - xlog_flush_location);

                -- convert the bytes to MB and compare it with user given bytes to generate alert
                IF floor(((xlog_lag_bytes/1024)/1024)) > CAST(user_given_bytes As BIGINT) THEN
                        RETURN floor(((xlog_lag_bytes/1024)/1024));
                ELSE
                        RETURN 0;
                END IF;

        END IF;

       IF $4 = 3 THEN

                -- fetch xlog location for replay transaction by standby server
                SELECT replay_location INTO xlog_replay_location FROM pemdata.streaming_replication WHERE client_addr = $2 AND server_id = $3;

                xlog_lag_bytes := (xlog_sent_location - xlog_replay_location);

                -- convert the bytes to MB and compare it with user given bytes to generate alert
                IF floor(((xlog_lag_bytes/1024)/1024)) > CAST(user_given_bytes As BIGINT) THEN
                        RETURN floor(((xlog_lag_bytes/1024)/1024));
                ELSE
                        RETURN 0;
                END IF;

        END IF;

END;
$$ LANGUAGE plpgsql;


-- Function to create the message text for sending the email if write location lags
CREATE OR REPLACE FUNCTION pem.email_write_lag_streaming_replication()
    RETURNS TEXT
   AS $$
DECLARE
    total_hostname RECORD;
    host_count integer;
    message_text TEXT;
    xlog_lag_bytes BIGINT;
    xlog_sent_location BIGINT;
    xlog_write_location BIGINT;

BEGIN
	host_count := 1;
	message_text := '';

	FOR total_hostname IN SELECT client_addr FROM pemdata.streaming_replication LOOP
		-- fetch the sent location that is sent by the master to the stanby server
		SELECT sent_location INTO xlog_sent_location FROM pemdata.streaming_replication WHERE client_addr = total_hostname.client_addr;
		-- fetch xlog location for write transaction by standby server
		SELECT write_location INTO xlog_write_location FROM pemdata.streaming_replication WHERE client_addr = total_hostname.client_addr;

		xlog_lag_bytes := (xlog_sent_location - xlog_write_location);
		xlog_lag_bytes := (xlog_lag_bytes/1024)/1024;

		message_text := message_text || host_count || '.' || 'Hostname: ' || total_hostname.client_addr || ', Write Lag (MB): ' || xlog_lag_bytes || E'\n';

		host_count := host_count + 1;

	END LOOP;

	RETURN message_text;
END;

$$
LANGUAGE plpgsql;

-- Function to create the message text for sending the email if flush location lags
CREATE OR REPLACE FUNCTION pem.email_flush_lag_streaming_replication()
    RETURNS TEXT
   AS $$
DECLARE
    total_hostname RECORD;
    host_count integer;
    message_text TEXT;
    xlog_lag_bytes BIGINT;
    xlog_sent_location BIGINT;
    xlog_flush_location BIGINT;

BEGIN
        host_count := 1;
	message_text := '';

        FOR total_hostname IN SELECT client_addr FROM pemdata.streaming_replication LOOP
                -- fetch the sent location that is sent by the master to the stanby server
                SELECT sent_location INTO xlog_sent_location FROM pemdata.streaming_replication WHERE client_addr = total_hostname.client_addr;
                -- fetch xlog location for write transaction by standby server
                SELECT flush_location INTO xlog_flush_location FROM pemdata.streaming_replication WHERE client_addr = total_hostname.client_addr;

                xlog_lag_bytes := (xlog_sent_location - xlog_flush_location);
                xlog_lag_bytes := (xlog_lag_bytes/1024)/1024;

                message_text := message_text || host_count || '.' || 'Hostname: ' || total_hostname.client_addr || ', Flush Lag (MB): ' || xlog_lag_bytes || E'\n';

                host_count := host_count + 1;

        END LOOP;

        RETURN message_text;
END;

$$
LANGUAGE plpgsql;


-- Function to create the message text for sending the email if replay location lags
CREATE OR REPLACE FUNCTION pem.email_replay_lag_streaming_replication()
    RETURNS TEXT
   AS $$
DECLARE
    total_hostname RECORD;
    host_count integer;
    message_text TEXT;
    xlog_lag_bytes BIGINT;
    xlog_sent_location BIGINT;
    xlog_replay_location BIGINT;

BEGIN
        host_count := 1;
	message_text := '';

        FOR total_hostname IN SELECT client_addr FROM pemdata.streaming_replication LOOP
                -- fetch the sent location that is sent by the master to the stanby server
                SELECT sent_location INTO xlog_sent_location FROM pemdata.streaming_replication WHERE client_addr = total_hostname.client_addr;
                -- fetch xlog location for replay transaction by standby server
                SELECT replay_location INTO xlog_replay_location FROM pemdata.streaming_replication WHERE client_addr = total_hostname.client_addr;

                xlog_lag_bytes := (xlog_sent_location - xlog_replay_location);
                xlog_lag_bytes := (xlog_lag_bytes/1024)/1024;

                message_text := message_text || host_count || '.' || 'Hostname: ' || total_hostname.client_addr || ', Replay Lag (MB): ' || xlog_lag_bytes || E'\n';

                host_count := host_count + 1;

        END LOOP;

        RETURN message_text;
END;

$$
LANGUAGE plpgsql;

--
-- Adding server version for PostgreSQL/PostgresPlus Advanced Server 9.3 compatibility.
--
INSERT INTO pem.server_version VALUES (10903, 'PostgreSQL 9.3');
INSERT INTO pem.server_version VALUES (20903, 'Advanced Server 9.3');

--
-- Streaming Replication Probe
--
INSERT INTO pem.probe
        (display_name, internal_name, collection_method, target_type_id,
         enabled_by_default, force_enabled, default_execution_frequency,
         default_lifetime, any_server_version, probe_code)
VALUES
        ('Streaming Replication', 'streaming_replication', 's', 200, false, false, 300, 180, false,
        'WITH pg_stat_replication_log_bytes AS (
        SELECT
                host(client_addr) AS client_addr, client_port,

                pg_catalog.split_part(sent_location, ''/'', 1) AS s1,
                pg_catalog.split_part(sent_location, ''/'', 2) AS s2,

                pg_catalog.split_part(write_location, ''/'', 1) AS w1,
                pg_catalog.split_part(write_location, ''/'', 2) AS w2,

                pg_catalog.split_part(flush_location, ''/'', 1) AS f1,
                pg_catalog.split_part(flush_location, ''/'', 2) AS f2,

                pg_catalog.split_part(replay_location, ''/'', 1) AS r1,
                pg_catalog.split_part(replay_location, ''/'', 2) AS r2

                FROM pg_stat_replication)
SELECT
        client_addr, client_port,
        CASE WHEN s1 IS NULL AND s2 IS NULL THEN 0::bigint
             WHEN s1 IS NULL THEN (''x'' || repeat(''0'', 16 - length(s2)) || s2)::bit(64)::bigint
             WHEN s2 IS NULL THEN 4278190080 * (''x'' || repeat(''0'', 16 - length(s1)) || s1)::bit(64)::bigint
             ELSE 4278190080 * (''x'' || repeat(''0'', 16 - length(s1)) || s1)::bit(64)::bigint + (''x'' || repeat(''0'', 16 - length(s2)) || s2)::bit(64)::bigint
        END AS sent_location,
      CASE WHEN w1 IS NULL AND w2 IS NULL THEN 0::bigint
             WHEN w1 IS NULL THEN (''x'' || repeat(''0'', 16 - length(w2)) || w2)::bit(64)::bigint
             WHEN w2 IS NULL THEN 4278190080 * (''x'' || repeat(''0'', 16 - length(w1)) || w1)::bit(64)::bigint
             ELSE 4278190080 * (''x'' || repeat(''0'', 16 - length(w1)) || w1)::bit(64)::bigint + (''x'' || repeat(''0'', 16 - length(w2)) || w2)::bit(64)::bigint
        END AS write_location,
        CASE WHEN f1 IS NULL AND f2 IS NULL THEN 0::bigint
             WHEN f1 IS NULL THEN (''x'' || repeat(''0'', 16 - length(f2)) || f2)::bit(64)::bigint
            WHEN f2 IS NULL THEN 4278190080 * (''x'' || repeat(''0'', 16 - length(f1)) || f1)::bit(64)::bigint
             ELSE 4278190080 * (''x'' || repeat(''0'', 16 - length(f1)) || f1)::bit(64)::bigint + (''x'' || repeat(''0'', 16 - length(f2)) || f2)::bit(64)::bigint
        END AS flush_location,
        CASE WHEN r1 IS NULL AND r2 IS NULL THEN 0::bigint
             WHEN r1 IS NULL THEN (''x'' || repeat(''0'', 16 - length(r2)) || r2)::bit(64)::bigint
             WHEN r2 IS NULL THEN 4278190080 * (''x'' || repeat(''0'', 16 - length(r1)) || r1)::bit(64)::bigint
             ELSE 4278190080 * (''x'' || repeat(''0'', 16 - length(r1)) || r1)::bit(64)::bigint + (''x'' || repeat(''0'', 16 - length(r2)) || r2)::bit(64)::bigint
        END AS replay_location
FROM pg_stat_replication_log_bytes');

INSERT INTO pem.probe_column
        (probe_id, internal_name, display_name, display_position, classification,
        sql_data_type, unit_of_value, calculate_pit, discard_history, pit_by_default, is_graphable)
SELECT
        (SELECT max(id) FROM pem.probe),
        v.internal_name, v.display_name, v.display_position, v.classification,
        v.sql_data_type, v.unit_of_value, v.calculate_pit, v.discard_history, v.pit_by_default, v.is_graphable
FROM
        (VALUES
                ('client_addr', 'Client Address', 1, 'k', 'text', '', false, false, false, false),
                ('client_port', 'Client Port', 2, 'k', 'integer', '', false, false, false, false),
                ('sent_location', 'Sent Xlog Location (Bytes)', 3, 'm', 'bigint', '', false, false, false, true),
                ('write_location', 'Write Xlog Location (Bytes)', 4, 'm', 'bigint', '', false, false, false, true),
                ('flush_location', 'Flush Xlog Location (Bytes)', 5, 'm', 'bigint', '', false, false, false, true),
                ('replay_location', 'Replay Xlog Location (Bytes)', 6, 'm', 'bigint', '', false, false, false, true)
        ) v(internal_name, display_name, display_position, classification,
                sql_data_type, unit_of_value, calculate_pit, discard_history, pit_by_default, is_graphable);


INSERT INTO pem.probe_server_version
    (probe_id, server_version_id, probe_code)
SELECT
        (SELECT max(id) FROM pem.probe), v.version, NULL
FROM
        (VALUES (10901), (10902), (10903), (20901), (20902), (20903))
                v(version);

--
-- Probe: Streaming Replication database conflicts
--
INSERT INTO pem.probe
        (display_name, internal_name, collection_method, target_type_id,
         enabled_by_default, force_enabled, default_execution_frequency,
         default_lifetime, any_server_version, probe_code)
VALUES
        ('Streaming Replication Database Conflicts', 'streaming_replication_db_conflicts', 's', 200, false, false, 300, 180, false,
         'SELECT  datname AS database_name, confl_tablespace, confl_lock, confl_snapshot, confl_bufferpin, confl_deadlock FROM pg_catalog.pg_stat_database_conflicts');

INSERT INTO pem.probe_column
        (probe_id, internal_name, display_name, display_position, classification,
        sql_data_type, unit_of_value, calculate_pit, discard_history, pit_by_default, is_graphable)
SELECT
        (SELECT max(id) FROM pem.probe),
        v.internal_name, v.display_name, v.display_position, v.classification,
        v.sql_data_type, v.unit_of_value, v.calculate_pit, v.discard_history, v.pit_by_default, v.is_graphable
FROM
        (VALUES
			    ('database_name', 'Database Name', 1, 'k', 'text', '', false, false, false, false),
                ('confl_tablespace', '# Drop Tablespace Conflicts', 2, 'm', 'bigint', '#', false, false, false, true),
                ('confl_lock', '# Lock Timeout Conflicts', 3, 'm', 'bigint', '#', false, false, false, true),
                ('confl_snapshot', '# Old Snapshot Conflicts', 4, 'm', 'bigint', '#', false, false, false, true),
                ('confl_bufferpin', '# Pinned Buffer Conflicts', 5, 'm', 'bigint', '#', false, false, false, true),
                ('confl_deadlock', '# Deadlock Conflicts', 6, 'm', 'bigint', '#', false, false, false, true)
        ) v(internal_name, display_name, display_position, classification,
                sql_data_type, unit_of_value, calculate_pit, discard_history, pit_by_default, is_graphable);


INSERT INTO pem.probe_server_version
    (probe_id, server_version_id, probe_code)
SELECT
        (SELECT max(id) FROM pem.probe), v.version, NULL
FROM
        (VALUES (10901), (10902), (10903), (20901), (20902), (20903))
                v(version);

--
-- Probe: Slony Replication
--
INSERT INTO pem.probe
        (display_name, internal_name, collection_method, target_type_id,
         agent_capability, enabled_by_default, force_enabled,
     default_execution_frequency, default_lifetime, any_server_version, probe_code)
VALUES
        ('Slony Replication', 'slony_replication', 'i', 300, 'slony_replication', true, false, 300, 180, true, 'slony_replication');

INSERT INTO pem.probe_column
        (probe_id, internal_name, display_name, display_position, classification,
        sql_data_type, unit_of_value, calculate_pit, discard_history, pit_by_default, is_graphable)
SELECT
        (SELECT max(id) FROM pem.probe),
        v.internal_name, v.display_name, v.display_position, v.classification,
        v.sql_data_type, v.unit_of_value, v.calculate_pit, v.discard_history, v.pit_by_default, v.is_graphable
FROM
        (VALUES
                ('cluster_name', 'Cluster Name', 1, 'k', 'text', '', false, false, false, false),
                ('lag_num_events', '# Lag Events', 2, 'm', 'bigint', '#', false, false, false, true),
                ('lag_time', 'Lag Time (Minutes)', 3, 'm', 'bigint', '', false, false, false, false)
        ) v(internal_name, display_name, display_position, classification,
                sql_data_type, unit_of_value, calculate_pit, discard_history, pit_by_default, is_graphable);

--
-- Probe: xDB SMR/MMR
--
INSERT INTO pem.probe
        (display_name, internal_name, collection_method, target_type_id,
         enabled_by_default, force_enabled, default_execution_frequency,
         default_lifetime, any_server_version, probe_code)
VALUES
        ('xDB Replication', 'xdb_smr_mmr_replication', 's', 300, false, false, 300, 180, false,
         'SELECT
              (SELECT COUNT(rrep_sync_id) AS pending_rows FROM _edb_replicator_pub.rrep_txset a, _edb_replicator_pub.rrep_txset_log b WHERE a.set_id = b.tx_set_id AND status IN (''P'', ''R'')) AS xdb_smr_lag_rows,
              (SELECT COUNT(rrep_sync_id) AS pending_rows FROM _edb_replicator_pub.rrep_mmr_txset a, _edb_replicator_pub.rrep_txset_log b WHERE a.set_id = b.tx_set_id AND status IN (''P'', ''R'')) AS xdb_mmr_lag_rows');

INSERT INTO pem.probe_column
        (probe_id, internal_name, display_name, display_position, classification,
        sql_data_type, unit_of_value, calculate_pit, discard_history, pit_by_default, is_graphable)
SELECT
        (SELECT max(id) FROM pem.probe),
        v.internal_name, v.display_name, v.display_position, v.classification,
        v.sql_data_type, v.unit_of_value, v.calculate_pit, v.discard_history, v.pit_by_default, v.is_graphable
FROM
        (VALUES
                ('xdb_smr_lag_rows', '# Rows Lagging in xDB Single Master Replication', 1, 'm', 'bigint', '#', false, false, false, true),
                ('xdb_mmr_lag_rows', '# Rows Lagging in xDB Multi Master Replication', 2, 'm', 'bigint', '#', false, false, false, true)
        ) v(internal_name, display_name, display_position, classification,
                sql_data_type, unit_of_value, calculate_pit, discard_history, pit_by_default, is_graphable);


INSERT INTO pem.probe_server_version
    (probe_id, server_version_id, probe_code)
SELECT
        (SELECT max(id) FROM pem.probe), v.version, NULL
FROM
        (VALUES (10804), (10900), (10901), (10902), (10903), (20804), (20900), (20901), (20902), (20903))
                v(version);

SELECT pem.create_data_and_history_tables();

SELECT pem.create_alert_template(
        'Number of attacks detected in the last N minutes',
        'The number of SQL injection attacks occured in the last N minutes',
        $sql$
SELECT * FROM pem.number_sqlinjection_attacks_detected (${param_1},${server_id})$sql$,
        200, '{Attacks Alert for last N minutes}', '{INTEGER}', '{Minutes}', NULL,'{sql_protect}', 56);

SELECT pem.create_alert_template(
        'Number of attacks detected in the last N minutes by specific user',
        'The number of SQL injection attacks occured in the last N minutes by specific user',
        $sql$
SELECT * FROM pem.number_sqlinjection_attacks_detected_by_username(${param_1},'${param_2}',${server_id})$sql$,
        200, '{Attacks Alert for last N minutes, Username}', '{INTEGER,STRING}', '{Minutes}', NULL,'{sql_protect}', 66);
--
-- Add sys_shared_memory_mb metric to memory_info probe to collect
-- shared memory statistics
--
ALTER TABLE pemdata.memory_usage ADD COLUMN sys_shared_memory_mb bigint;
ALTER TABLE pemhistory.memory_usage ADD COLUMN sys_shared_memory_mb bigint;
INSERT INTO pem.probe_column(probe_id, internal_name, display_name, display_position, classification, sql_data_type, unit_of_value, calculate_pit, discard_history, pit_by_default, is_graphable) SELECT id, 'sys_shared_memory_mb', 'Shared System Memory (MB)', 5, 'm', 'bigint', 'MB', false, false, true, true FROM pem.probe WHERE internal_name='memory_usage';

-- Update the trigger functions related to pemdata.memory_usage probe
CREATE OR REPLACE FUNCTION pemdata.copy_memory_usage_to_history() RETURNS TRIGGER AS $$
BEGIN
	IF (TG_OP = 'INSERT' OR TG_OP = 'UPDATE') THEN
		INSERT INTO pemhistory.memory_usage (recorded_time, agent_id, total_ram_memory_mb, free_ram_memory_mb, total_swap_memory_mb, free_swap_memory_mb, sys_shared_memory_mb) VALUES (NEW.recorded_time, NEW.agent_id, NEW.total_ram_memory_mb, NEW.free_ram_memory_mb, NEW.total_swap_memory_mb, NEW.free_swap_memory_mb, NEW.sys_shared_memory_mb);
	ELSIF EXISTS(SELECT 1 FROM pem.agent WHERE id = OLD.agent_id) THEN
		INSERT INTO pemhistory.memory_usage (agent_id) VALUES (OLD.agent_id);
	END IF;
	RETURN NEW;

END;
$$ LANGUAGE plpgsql;

-- Types of utilisation defined for tuning wizard
CREATE TYPE pem.tuning_server_util AS ENUM(
	'UTILISATION_DEDICATED', -- dedicated utilisation
	'UTILISATION_MIXED',     -- mixed level utilisation
	'UTILISATION_DEVELOPER'  -- developer level utilisation
);

COMMENT ON TYPE pem.tuning_server_util IS 'Types of utilisation defined for tuning wizard';

-- Types of workload profile defined for tuning wizard
CREATE TYPE pem.tuning_workload_profile AS ENUM(
	'WORKLOAD_OLTP',  -- OLTP type workload
	'WORKLOAD_MIXED', -- mixed type workload
	'WORKLOAD_DW'     -- datawarehouse type workload
);

COMMENT ON TYPE pem.tuning_workload_profile IS 'Types of workload profile defined for tuning wizard';

-- This function executes the calculates the appropriate value for the parameters to
-- be tuned for servers with workload profile of type OLTP
-- Parameters:
--    tune_server_id - server id of the server to tune
--    utilisation - utilisation enum to specify of server
--    total_ram - total ram on the machine
--    shared_memory - shared memory on the machine
--    is_windows - if machine is windows or not
CREATE OR REPLACE FUNCTION pem.server_tuning_oltp (tune_server_id int, utilisation pem.tuning_server_util, total_ram bigint, shared_memory bigint, is_windows boolean)
RETURNS TABLE (tuned_parameter text, tuned_value text)
AS $$
DECLARE
	server_max_conn int := 0;
	server_max_locks_per_xact int := 0;
	server_max_prepared_xacts int := 0;
	shared_mem bigint := shared_memory;
	work_mem_factor decimal := 0.008;
	maint_work_mem_factor decimal := 0.08;
	work_mem bigint := 0;
	maint_work_mem bigint := 0;
	shared_buffers bigint := 0;
	wal_buffers bigint := 0;
	eff_cache_size bigint := 0;
BEGIN
	SELECT setting FROM pemdata.settings WHERE server_id = tune_server_id AND name='max_connections' INTO server_max_conn;
	SELECT setting FROM pemdata.settings WHERE server_id = tune_server_id AND name='max_locks_per_transaction' INTO server_max_locks_per_xact;
	SELECT setting FROM pemdata.settings WHERE server_id = tune_server_id AND name='max_prepared_transactions' INTO server_max_prepared_xacts;

	-- calculate amount of memory utilized for max_connections and subtract it from shared memory
	-- to calculate work_mem and maintainance_work_mem
	shared_mem := shared_mem - (server_max_conn * 620 * server_max_locks_per_xact);
	shared_mem := shared_mem - (server_max_prepared_xacts * 820 * server_max_locks_per_xact);

	-- calculate work_mem
	work_mem := round(shared_mem * work_mem_factor);
	work_mem := round(work_mem / 1024);

	-- work_mem needs to be at least 1MB
	IF work_mem < 1024 THEN
		work_mem := 1024;
	END IF;

	work_mem := round(work_mem / 1024);

	tuned_parameter := 'work_mem';
	tuned_value := work_mem || 'MB';
	RETURN NEXT;

	shared_mem := shared_mem - (work_mem * 1024 *1024);

	-- calculate maintainence_work_mem
	maint_work_mem := round(shared_mem * maint_work_mem_factor);
	maint_work_mem := round(maint_work_mem / (1024  * 1024));

	-- maintainence_work_mem needs to be at max 256MB
	IF maint_work_mem > 256 THEN
		maint_work_mem := 256;
	END IF;

	-- maintainence_work_mem needs to be at least 16MB
	IF maint_work_mem < 16 THEN
		maint_work_mem := 16;
	END IF;

	tuned_parameter := 'maintenance_work_mem';
	tuned_value := maint_work_mem || 'MB';
	RETURN NEXT;

	-- calculate shared_buffers
	IF utilisation = 'UTILISATION_DEVELOPER' THEN
		-- set it default to 32MB
		shared_buffers := 32 * 1024 * 1024;
	ELSIF utilisation = 'UTILISATION_MIXED' THEN
		IF is_windows THEN
			-- set it default to 128MB
			shared_buffers := 128 * 1024 * 1024;
		ELSE
			-- set 25% of total RAM
			shared_buffers := round(total_ram * 0.25);
		END IF;
	ELSE
		IF is_windows THEN
			-- set it default to 256MB
			shared_buffers := 256 * 1024 * 1024;
		ELSE
			-- set 40% of total RAM
			shared_buffers := round(total_ram * 0.40);
		END IF;
	END IF;

	shared_buffers := round(shared_buffers / (1024*1024));

	-- shared_buffers needs to be at max 8GB
	IF shared_buffers > 8192 THEN
		shared_buffers := 8192;
	END IF;

	-- shared_buffers needs to be at least 2MB
	IF shared_buffers < 2 THEN
		shared_buffers := 2;
	END IF;

	tuned_parameter := 'shared_buffers';
	tuned_value := shared_buffers || 'MB';
	RETURN NEXT;

	-- calculate wal_buffers
	shared_buffers := shared_buffers * 1024 * 1024;
	wal_buffers := (shared_buffers / 8);

	-- wal_buffers needs to be at max 16MB
	IF wal_buffers > 16777216 THEN
		wal_buffers := 16777216;
	END IF;

	-- wal_buffers needs to be at least 64KB
	IF wal_buffers < 65536 THEN
		wal_buffers := 65536;
	END IF;

	tuned_parameter := 'wal_buffers';
	IF (wal_buffers / 1048576) > 1.00 THEN
		wal_buffers := round(wal_buffers / 1048576);
		tuned_value := wal_buffers || 'MB';
	ELSE
		wal_buffers := round(wal_buffers / 1024);
		tuned_value := wal_buffers || 'kB';
	END IF;
	RETURN NEXT;

	-- calculate effective_cache_size
	IF utilisation = 'UTILISATION_DEDICATED' THEN
		eff_cache_size := round(total_ram * 0.75);
	ELSIF utilisation = 'UTILISATION_MIXED' THEN
		eff_cache_size := round(total_ram * 0.5);
	ELSE
		eff_cache_size := round(total_ram * 0.25);
	END IF;

	eff_cache_size := round(eff_cache_size / 1048576) + 1;

	tuned_parameter := 'effective_cache_size';
	tuned_value := eff_cache_size || 'MB';
	RETURN NEXT;

	-- calculate random_page_cost
	tuned_parameter := 'random_page_cost';
	IF utilisation = 'UTILISATION_DEDICATED' THEN
		tuned_value := '2.0';
	ELSIF utilisation = 'UTILISATION_MIXED' THEN
		tuned_value := '2.5';
	ELSE
		tuned_value := '3.0';
	END IF;
	RETURN NEXT;

	-- calculate checkpoint_segments
	tuned_parameter := 'checkpoint_segments';
	IF utilisation = 'UTILISATION_DEDICATED' THEN
		tuned_value := '32';
	ELSIF utilisation = 'UTILISATION_MIXED' THEN
		tuned_value := '16';
	ELSE
		tuned_value := '6';
	END IF;
	RETURN NEXT;

	RETURN;
END
$$ LANGUAGE plpgsql;

-- This function executes the calculates the appropriate value for the parameters to
-- be tuned for servers with workload profile of type Mixed
-- Parameters:
--    tune_server_id - server id of the server to tune
--    utilisation - utilisation enum to specify of server
--    total_ram - total ram on the machine
--    shared_memory - shared memory on the machine
--    is_windows - if machine is windows or not
CREATE OR REPLACE FUNCTION pem.server_tuning_mixed (tune_server_id int, utilisation pem.tuning_server_util, total_ram bigint, shared_memory bigint, is_windows boolean)
RETURNS TABLE (tuned_parameter text, tuned_value text)
AS $$
DECLARE
	server_max_conn int := 0;
	server_max_locks_per_xact int := 0;
	server_max_prepared_xacts int := 0;
	shared_mem bigint := shared_memory;
	work_mem_factor decimal := 0.012;
	maint_work_mem_factor decimal := 0.1;
	work_mem bigint := 0;
	maint_work_mem bigint := 0;
	shared_buffers bigint := 0;
	wal_buffers bigint := 0;
	eff_cache_size bigint := 0;
BEGIN
	SELECT setting FROM pemdata.settings WHERE server_id = tune_server_id AND name='max_connections' INTO server_max_conn;
	SELECT setting FROM pemdata.settings WHERE server_id = tune_server_id AND name='max_locks_per_transaction' INTO server_max_locks_per_xact;
	SELECT setting FROM pemdata.settings WHERE server_id = tune_server_id AND name='max_prepared_transactions' INTO server_max_prepared_xacts;

	-- calculate amount of memory utilized for max_connections and subtract it from shared memory
	-- to calculate work_mem and maintainance_work_mem
	shared_mem := shared_mem - (server_max_conn * 620 * server_max_locks_per_xact);
	shared_mem := shared_mem - (server_max_prepared_xacts * 820 * server_max_locks_per_xact);

	-- calculate work_mem
	work_mem := round(shared_mem * work_mem_factor);
	work_mem := round(work_mem / 1024);

	-- work_mem needs to be at least 1MB
	IF work_mem < 1024 THEN
		work_mem := 1024;
	END IF;

	work_mem := round(work_mem / 1024);

	tuned_parameter := 'work_mem';
	tuned_value := work_mem || 'MB';
	RETURN NEXT;

	shared_mem := shared_mem - (work_mem * 1024 *1024);

	-- calculate maintainence_work_mem
	maint_work_mem := round(shared_mem * maint_work_mem_factor);
	maint_work_mem := round(maint_work_mem / (1024  * 1024));

	-- maintainence_work_mem needs to be at max 256MB
	IF maint_work_mem > 256 THEN
		maint_work_mem := 256;
	END IF;

	-- maintainence_work_mem needs to be at least 16MB
	IF maint_work_mem < 16 THEN
		maint_work_mem := 16;
	END IF;

	tuned_parameter := 'maintenance_work_mem';
	tuned_value := maint_work_mem || 'MB';
	RETURN NEXT;

	-- calculate shared_buffers
	IF utilisation = 'UTILISATION_DEVELOPER' THEN
		-- set it default to 32MB
		shared_buffers := 32 * 1024 * 1024;
	ELSIF utilisation = 'UTILISATION_MIXED' THEN
		IF is_windows THEN
			-- set it default to 128MB
			shared_buffers := 128 * 1024 * 1024;
		ELSE
			-- set 25% of total RAM
			shared_buffers := round(total_ram * 0.25);
		END IF;
	ELSE
		IF is_windows THEN
			-- set it default to 256MB
			shared_buffers := 256 * 1024 * 1024;
		ELSE
			-- set 40% of total RAM
			shared_buffers := round(total_ram * 0.40);
		END IF;
	END IF;

	shared_buffers := round(shared_buffers / (1024*1024));

	-- shared_buffers needs to be at max 8GB
	IF shared_buffers > 8192 THEN
		shared_buffers := 8192;
	END IF;

	-- shared_buffers needs to be at least 2MB
	IF shared_buffers < 2 THEN
		shared_buffers := 2;
	END IF;

	tuned_parameter := 'shared_buffers';
	tuned_value := shared_buffers || 'MB';
	RETURN NEXT;

	-- calculate wal_buffers
	shared_buffers := shared_buffers * 1024 * 1024;
	wal_buffers := (shared_buffers / 16);

	-- wal_buffers needs to be at max 16MB
	IF wal_buffers > 16777216 THEN
		wal_buffers := 16777216;
	END IF;

	-- wal_buffers needs to be at least 64KB
	IF wal_buffers < 65536 THEN
		wal_buffers := 65536;
	END IF;

	tuned_parameter := 'wal_buffers';
	IF (wal_buffers / 1048576) > 1.00 THEN
		wal_buffers := round(wal_buffers / 1048576);
		tuned_value := wal_buffers || 'MB';
	ELSE
		wal_buffers := round(wal_buffers / 1024);
		tuned_value := wal_buffers || 'kB';
	END IF;
	RETURN NEXT;

	-- calculate effective_cache_size
	IF utilisation = 'UTILISATION_DEDICATED' THEN
		eff_cache_size := round(total_ram * 0.75);
	ELSIF utilisation = 'UTILISATION_MIXED' THEN
		eff_cache_size := round(total_ram * 0.5);
	ELSE
		eff_cache_size := round(total_ram * 0.25);
	END IF;

	eff_cache_size := round(eff_cache_size / 1048576) + 1;

	tuned_parameter := 'effective_cache_size';
	tuned_value := eff_cache_size || 'MB';
	RETURN NEXT;

	-- calculate random_page_cost
	tuned_parameter := 'random_page_cost';
	IF utilisation = 'UTILISATION_DEDICATED' THEN
		tuned_value := '2.0';
	ELSIF utilisation = 'UTILISATION_MIXED' THEN
		tuned_value := '2.5';
	ELSE
		tuned_value := '3.0';
	END IF;
	RETURN NEXT;

	-- calculate checkpoint_segments
	tuned_parameter := 'checkpoint_segments';
	IF utilisation = 'UTILISATION_DEDICATED' THEN
		tuned_value := '48';
	ELSIF utilisation = 'UTILISATION_MIXED' THEN
		tuned_value := '24';
	ELSE
		tuned_value := '6';
	END IF;
	RETURN NEXT;

	RETURN;
END
$$ LANGUAGE plpgsql;

-- This function executes the calculates the appropriate value for the parameters to
-- be tuned for servers with workload profile of type Datawarehouse
-- Parameters:
--    tune_server_id - server id of the server to tune
--    utilisation - utilisation enum to specify of server
--    total_ram - total ram on the machine
--    shared_memory - shared memory on the machine
--    is_windows - if machine is windows or not
CREATE OR REPLACE FUNCTION pem.server_tuning_dw (tune_server_id int, utilisation pem.tuning_server_util, total_ram bigint, shared_memory bigint, is_windows boolean)
RETURNS TABLE (tuned_parameter text, tuned_value text)
AS $$
DECLARE
	server_max_conn int := 0;
	server_max_locks_per_xact int := 0;
	server_max_prepared_xacts int := 0;
	shared_mem bigint := shared_memory;
	work_mem_factor decimal := 0.020;
	maint_work_mem_factor decimal := 0.2;
	work_mem bigint := 0;
	maint_work_mem bigint := 0;
	shared_buffers bigint := 0;
	wal_buffers bigint := 0;
	eff_cache_size bigint := 0;
BEGIN
	SELECT setting FROM pemdata.settings WHERE server_id = tune_server_id AND name='max_connections' INTO server_max_conn;
	SELECT setting FROM pemdata.settings WHERE server_id = tune_server_id AND name='max_locks_per_transaction' INTO server_max_locks_per_xact;
	SELECT setting FROM pemdata.settings WHERE server_id = tune_server_id AND name='max_prepared_transactions' INTO server_max_prepared_xacts;

	-- calculate amount of memory utilized for max_connections and subtract it from shared memory
	-- to calculate work_mem and maintainance_work_mem
	shared_mem := shared_mem - (server_max_conn * 620 * server_max_locks_per_xact);
	shared_mem := shared_mem - (server_max_prepared_xacts * 820 * server_max_locks_per_xact);

	-- calculate work_mem
	work_mem := round(shared_mem * work_mem_factor);
	work_mem := round(work_mem / 1024);

	-- work_mem needs to be at least 1MB
	IF work_mem < 1024 THEN
		work_mem := 1024;
	END IF;

	work_mem := round(work_mem / 1024);

	tuned_parameter := 'work_mem';
	tuned_value := work_mem || 'MB';
	RETURN NEXT;

	shared_mem := shared_mem - (work_mem * 1024 *1024);

	-- calculate maintainence_work_mem
	maint_work_mem := round(shared_mem * maint_work_mem_factor);
	maint_work_mem := round(maint_work_mem / (1024  * 1024));

	-- maintainence_work_mem needs to be at max 256MB
	IF maint_work_mem > 256 THEN
		maint_work_mem := 256;
	END IF;

	-- maintainence_work_mem needs to be at least 16MB
	IF maint_work_mem < 16 THEN
		maint_work_mem := 16;
	END IF;

	tuned_parameter := 'maintenance_work_mem';
	tuned_value := maint_work_mem || 'MB';
	RETURN NEXT;

	-- calculate shared_buffers
	IF utilisation = 'UTILISATION_DEVELOPER' THEN
		-- set it default to 32MB
		shared_buffers := 32 * 1024 * 1024;
	ELSIF utilisation = 'UTILISATION_MIXED' THEN
		IF is_windows THEN
			-- set it default to 128MB
			shared_buffers := 128 * 1024 * 1024;
		ELSE
			-- set 25% of total RAM
			shared_buffers := round(total_ram * 0.25);
		END IF;
	ELSE
		IF is_windows THEN
			-- set it default to 256MB
			shared_buffers := 256 * 1024 * 1024;
		ELSE
			-- set 40% of total RAM
			shared_buffers := round(total_ram * 0.40);
		END IF;
	END IF;

	shared_buffers := round(shared_buffers / (1024*1024));

	-- shared_buffers needs to be at max 8GB
	IF shared_buffers > 8192 THEN
		shared_buffers := 8192;
	END IF;

	-- shared_buffers needs to be at least 2MB
	IF shared_buffers < 2 THEN
		shared_buffers := 2;
	END IF;

	tuned_parameter := 'shared_buffers';
	tuned_value := shared_buffers || 'MB';
	RETURN NEXT;

	-- calculate wal_buffers
	shared_buffers := shared_buffers * 1024 * 1024;
	wal_buffers := (shared_buffers / 32);

	-- wal_buffers needs to be at max 16MB
	IF wal_buffers > 16777216 THEN
		wal_buffers := 16777216;
	END IF;

	-- wal_buffers needs to be at least 64KB
	IF wal_buffers < 65536 THEN
		wal_buffers := 65536;
	END IF;

	tuned_parameter := 'wal_buffers';
	IF (wal_buffers / 1048576) > 1.00 THEN
		wal_buffers := round(wal_buffers / 1048576);
		tuned_value := wal_buffers || 'MB';
	ELSE
		wal_buffers := round(wal_buffers / 1024);
		tuned_value := wal_buffers || 'kB';
	END IF;
	RETURN NEXT;

	-- calculate effective_cache_size
	IF utilisation = 'UTILISATION_DEDICATED' THEN
		eff_cache_size := round(total_ram * 0.75);
	ELSIF utilisation = 'UTILISATION_MIXED' THEN
		eff_cache_size := round(total_ram * 0.5);
	ELSE
		eff_cache_size := round(total_ram * 0.25);
	END IF;

	eff_cache_size := round(eff_cache_size / 1048576) + 1;

	tuned_parameter := 'effective_cache_size';
	tuned_value := eff_cache_size || 'MB';
	RETURN NEXT;

	-- calculate random_page_cost
	tuned_parameter := 'random_page_cost';
	IF utilisation = 'UTILISATION_DEDICATED' THEN
		tuned_value := '2.0';
	ELSIF utilisation = 'UTILISATION_MIXED' THEN
		tuned_value := '2.5';
	ELSE
		tuned_value := '3.0';
	END IF;
	RETURN NEXT;

	-- calculate checkpoint_segments
	tuned_parameter := 'checkpoint_segments';
	IF utilisation = 'UTILISATION_DEDICATED' THEN
		tuned_value := '64';
	ELSIF utilisation = 'UTILISATION_MIXED' THEN
		tuned_value := '32';
	ELSE
		tuned_value := '6';
	END IF;
	RETURN NEXT;

	RETURN;
END
$$ LANGUAGE plpgsql;

-- This function provides recommendation for tuning a given server based on the server utilization
-- and workload profile as selected by the user in the Tuning Wizard dialog. This function reads
-- system parameters like total RAM and shared memory and then suggests tuned values for some parameters
-- Parameters:
--    tune_server_id - server id of the server to tune
--    utilisation - utilisation enum to specify of server
--    profile - workload profile of the server instance
CREATE OR REPLACE FUNCTION pem.server_tuning (tune_server_id int, utilisation pem.tuning_server_util, profile pem.tuning_workload_profile)
RETURNS TABLE (tuned_server_id int, tuned_parameter text, tuned_value text)
AS $$
DECLARE
	bound_agent_id int := 0;
	server_count int := 0;
	total_ram_bytea bigint := 0;
	shared_memory_bytea bigint := 0;
	is_windows boolean := false;
	util_percentage int := 0;
BEGIN
	SELECT agent_id FROM pem.agent_server_binding WHERE server_id = tune_server_id INTO bound_agent_id;
	SELECT count(asb.server_id) AS scount FROM pem.agent_server_binding asb, pem.avail_servers acs WHERE asb.server_id = acs.id AND agent_id = bound_agent_id INTO server_count;
	SELECT total_ram_memory_mb, sys_shared_memory_mb FROM pemdata.memory_usage WHERE agent_id = bound_agent_id INTO total_ram_bytea, shared_memory_bytea;
	SELECT 'windows' = ANY(agent_capability_list) INTO is_windows FROM pem.agent WHERE id = bound_agent_id;

	IF utilisation = 'UTILISATION_DEDICATED' THEN
		util_percentage := 100;
	ELSIF utilisation = 'UTILISATION_DEDICATED' THEN
		util_percentage := 66;
	ELSE
		util_percentage := 33;
	END IF;

	total_ram_bytea := total_ram_bytea * 1024 * 1024;
	shared_memory_bytea := shared_memory_bytea * 1024 * 1024;

	-- divide the total ram and system shared buffer size by the no. of postgres
	-- instances installed on the same machine to avoid over allocation of memory
	-- and resources to the postgres instance being tuned currently
	IF server_count > 0 THEN
		total_ram_bytea := total_ram_bytea / server_count;
		shared_memory_bytea := shared_memory_bytea / server_count;
	END IF;

	-- If SHMMAX > physical memory, we'll use physical memory as the max of SHMMAX.
	-- We don't want to end-up over allocating memory.
	IF total_ram_bytea < shared_memory_bytea THEN
		shared_memory_bytea := total_ram_bytea;
	END IF;

	-- The maximum we'll ever use is 2/3 of system-wide shared memory.
	shared_memory_bytea := round(shared_memory_bytea * 0.66);

	-- Calculate the amount of memory we'll use based on the user's defined
	-- percentage for tuning.
	shared_memory_bytea := shared_memory_bytea * round(util_percentage * 0.01);

	IF profile = 'WORKLOAD_OLTP' THEN
		RETURN QUERY EXECUTE 'SELECT $1::int AS tuned_server_id, tuned_parameter, tuned_value FROM ' ||
			'pem.server_tuning_oltp($1::int, $2::pem.tuning_server_util, $3::bigint, $4::bigint, $5::boolean)'
			USING tune_server_id, utilisation, total_ram_bytea, shared_memory_bytea, is_windows;
	ELSIF profile = 'WORKLOAD_MIXED' THEN
		RETURN QUERY EXECUTE 'SELECT $1::int AS tuned_server_id, tuned_parameter, tuned_value FROM ' ||
			'pem.server_tuning_mixed($1::int, $2::pem.tuning_server_util, $3::bigint, $4::bigint, $5::boolean)'
			USING tune_server_id, utilisation, total_ram_bytea, shared_memory_bytea, is_windows;
	ELSE
		RETURN QUERY EXECUTE 'SELECT $1::int AS tuned_server_id, tuned_parameter, tuned_value FROM ' ||
			'pem.server_tuning_dw($1::int, $2::pem.tuning_server_util, $3::bigint, $4::bigint, $5::boolean)'
			USING tune_server_id, utilisation, total_ram_bytea, shared_memory_bytea, is_windows;
	END IF;
END
$$ LANGUAGE plpgsql;


--
-- Streaming Replication Alert
--
SELECT pem.create_alert_template(
        'Number of standby servers lag behind the master by write location',
        'In streaming replication number of standby servers lag behind the master by write location',
        $sql$
SELECT pem.number_replication_lag_bytes(${param_1},${server_id},1)$sql$,
        200, '{Lag in MB}', '{INTEGER}', NULL, NULL,'{streaming_replication}', 60);

SELECT pem.create_alert_template(
        'Number of standby servers lag behind the master by flush location',
        'In streaming replication number of standby servers lag behind the master by flush location',
        $sql$
SELECT pem.number_replication_lag_bytes(${param_1},${server_id},2)$sql$,
        200, '{Lag in MB}', '{INTEGER}', NULL, NULL,'{streaming_replication}', 61);

SELECT pem.create_alert_template(
        'Number of standby servers lag behind the master by replay location',
        'In streaming replication number of standby servers lag behind the master by replay location',
        $sql$
SELECT pem.number_replication_lag_bytes(${param_1},${server_id},3)$sql$,
        200, '{Lag in MB}', '{INTEGER}', NULL, NULL,'{streaming_replication}', 62);

SELECT pem.create_alert_template(
        'Standby server lag behind the master by write location',
        'In streaming replication standby server lag behind the master by write location in MB',
        $sql$
SELECT pem.replication_lag_bytes_by_hostname(${param_1},'${param_2}',${server_id},1)$sql$,
        200, '{Lag in MB,hostname}', '{INTEGER,STRING}', NULL, NULL,'{streaming_replication}', 63);

SELECT pem.create_alert_template(
        'Standby server lag behind the master by flush location',
        'In streaming replication standby server lag behind the master by flush location in MB',
        $sql$
SELECT pem.replication_lag_bytes_by_hostname(${param_1},'${param_2}',${server_id},2)$sql$,
        200, '{Lag in MB,hostname}', '{INTEGER,STRING}', NULL, NULL,'{streaming_replication}', 64);

SELECT pem.create_alert_template(
        'Standby server lag behind the master by replay location',
        'In streaming replication standby server lag behind the master by replay location in MB',
        $sql$
SELECT pem.replication_lag_bytes_by_hostname(${param_1},'${param_2}',${server_id},3)$sql$,
        200, '{Lag in MB,hostname}', '{INTEGER,STRING}', NULL, NULL,'{streaming_replication}', 65);


--
-- Database Conflicts Alert
--
SELECT pem.create_alert_template(
        'Queries that have been canceled due to dropped tablespaces',
        'Number of queries that have been canceled due to dropped tablespaces in streaming replication',
        $sql$
SELECT confl_tablespace
FROM pemdata.streaming_replication_db_conflicts
WHERE   server_id = ${server_id}
AND     database_name = '${database_name}'$sql$,
        300, NULL, NULL, NULL, '#','{streaming_replication_db_conflicts}', 45);

SELECT pem.create_alert_template(
        'Queries that have been canceled due to lock timeouts',
        'Number of queries that have been canceled due to lock timeouts in streaming replication',
        $sql$
SELECT confl_lock
FROM pemdata.streaming_replication_db_conflicts
WHERE   server_id = ${server_id}
AND     database_name = '${database_name}'$sql$,
        300, NULL, NULL, NULL, '#','{streaming_replication_db_conflicts}', 46);


SELECT pem.create_alert_template(
        'Queries that have been canceled due to old snapshots',
        'Number of queries that have been canceled due to old snapshots in streaming replication',
        $sql$
SELECT confl_snapshot
FROM pemdata.streaming_replication_db_conflicts
WHERE   server_id = ${server_id}
AND     database_name = '${database_name}'$sql$,
        300, NULL, NULL, NULL, '#','{streaming_replication_db_conflicts}', 47);

SELECT pem.create_alert_template(
        'Queries that have been canceled due to pinned buffers',
        'Number of queries that have been canceled due to pinned buffers in streaming replication',
        $sql$
SELECT confl_bufferpin
FROM pemdata.streaming_replication_db_conflicts
WHERE   server_id = ${server_id}
AND     database_name = '${database_name}'$sql$,
        300, NULL, NULL, NULL, '#','{streaming_replication_db_conflicts}', 48);


SELECT pem.create_alert_template(
        'Queries that have been canceled due to deadlocks',
        'Number of queries that have been canceled due to deadlocks in streaming replication',
        $sql$
SELECT confl_deadlock
FROM pemdata.streaming_replication_db_conflicts
WHERE   server_id = ${server_id}
AND     database_name = '${database_name}'$sql$,
        300, NULL, NULL, NULL, '#','{streaming_replication_db_conflicts}', 49);

--
-- Slony Replication Alert
--
SELECT pem.create_alert_template(
        'Total rows lagging in all slony clusters',
        'Total rows lagging in all slony clusters in slony replication',
        $sql$
SELECT SUM(lag_num_events) FROM pemdata.slony_replication WHERE server_id = ${server_id} AND database_name='${database_name}'$sql$,
        300, NULL, NULL, NULL, '#','{slony_replication}', 50);

SELECT pem.create_alert_template(
        'Rows lagging in one slony cluster',
        'Rows lagging in one slony cluster in slony replication',
        $sql$
SELECT lag_num_events FROM pemdata.slony_replication WHERE server_id = ${server_id} AND database_name='${database_name}' AND cluster_name='$(param_1)'$sql$,
        300, '{Slony Cluster Name: }', '{STRING}', NULL, '','{slony_replication}', 51);

SELECT pem.create_alert_template(
        'Lag time (minutes) in one slony cluster',
        'Lag time (minutes) in one slony cluster in slony replication',
        $sql$
SELECT lag_time FROM pemdata.slony_replication WHERE server_id = ${server_id} AND database_name='${database_name}' AND cluster_name='$(param_1)'$sql$,
        300, '{Slony Cluster Name: }', '{STRING}', NULL, '','{slony_replication}', 52);

--
-- xDB SMR/MMR Alert
--
SELECT pem.create_alert_template(
        'Total rows lagging in xdb single master replication',
        'xDB Replication: Total rows lagging in xdb single master replication',
        $sql$
SELECT xdb_smr_lag_rows FROM pemdata.xdb_smr_mmr_replication WHERE server_id = ${server_id} AND database_name='${database_name}'$sql$,
        300, '{Lag Rows: }', '{INTEGER}', NULL, '#','{xdb_smr_mmr_replication}', 53);

SELECT pem.create_alert_template(
        'Total rows lagging in xdb multi master replication',
        'xDB Replication: Total rows lagging in xdb multi master replication',
        $sql$
SELECT xdb_mmr_lag_rows FROM pemdata.xdb_smr_mmr_replication WHERE server_id = ${server_id} AND database_name='${database_name}'$sql$,
        300, '{Lag Rows: }', '{INTEGER}', NULL, '#','{xdb_smr_mmr_replication}', 54);

--
-- Adding os_host_name, os_domain_name, os_windows_domain metrics to os_info probe
--
ALTER TABLE pemdata.os_info ADD COLUMN os_host_name text;
ALTER TABLE pemdata.os_info ADD COLUMN os_domain_name text;
ALTER TABLE pemdata.os_info ADD COLUMN os_windows_domain text;
ALTER TABLE pemhistory.os_info ADD COLUMN os_host_name text;
ALTER TABLE pemhistory.os_info ADD COLUMN os_domain_name text;
ALTER TABLE pemhistory.os_info ADD COLUMN os_windows_domain text;

INSERT INTO pem.probe_column(probe_id, internal_name, display_name, display_position, classification, sql_data_type, unit_of_value, calculate_pit, discard_history, pit_by_default, is_graphable)
(
SELECT id, 'os_host_name', 'OS Host Name',3, 'm', 'text', '', false,  false, false, false FROM pem.probe WHERE internal_name='os_info'
UNION ALL
SELECT id, 'os_domain_name', 'OS Domain Name',4, 'm', 'text', '', false,  false, false, false FROM pem.probe WHERE internal_name='os_info'
UNION ALL
SELECT id, 'os_windows_domain', 'OS Windows Domain',5, 'm', 'text', '', false,  false, false, false FROM pem.probe WHERE internal_name='os_info'
);

CREATE OR REPLACE FUNCTION pemdata.copy_os_info_to_history()
RETURNS trigger AS
$$
BEGIN
    IF (TG_OP = 'INSERT' OR TG_OP = 'UPDATE') THEN
                INSERT INTO pemhistory.os_info (recorded_time, agent_id, os_details, os_start_time, os_host_name, os_domain_name, os_windows_domain) VALUES (NEW.recorded_time, NEW.agent_id, NEW.os_details, NEW.os_start_time, NEW.os_host_name, NEW.os_domain_name, NEW.os_windows_domain);
        ELSIF EXISTS(SELECT 1 FROM pem.agent WHERE id = OLD.agent_id) THEN
                INSERT INTO pemhistory.os_info (agent_id) VALUES (OLD.agent_id);
    END IF;
    RETURN NEW;
END;
$$
LANGUAGE plpgsql;

-- Add new column error_timestamp to pem.alert table
ALTER TABLE pem.alert ADD COLUMN error_timestamp timestamp with time zone;

-- Function to log error timestamp value to pem.alert table if error_message changed
CREATE OR REPLACE FUNCTION pem.log_alert_error_timestamp() RETURNS trigger AS $$
BEGIN
        IF (NEW.error_message IS NOT NULL) THEN
                NEW.error_timestamp = now();
                RETURN NEW;
        ELSE
                NEW.error_timestamp = NULL;
                RETURN NEW;
        END IF;
END

$$ LANGUAGE plpgsql;

-- Trigger on pem.alert when the old error message changed to new error message
CREATE TRIGGER alert_error_timestamp
    BEFORE UPDATE ON pem.alert
    FOR EACH ROW
    WHEN (OLD.error_message IS DISTINCT FROM NEW.error_message)
    EXECUTE PROCEDURE pem.log_alert_error_timestamp();

COMMENT ON TRIGGER alert_error_timestamp ON pem.alert IS 'Add the current timestamp with timezone in alert table.';

UPDATE pem.alert_template SET sql=E'SELECT sum(abs( d.blks_hit-h.blks_hit))::float * 100
                / GREATEST(sum(abs(d.blks_hit-h.blks_hit)+abs(d.blks_read-h.blks_read)+COALESCE(abs(d.blks_icache_hit-h.blks_icache_hit), 0)), 1)
FROM    pemdata.database_statistics AS d
JOIN    pemhistory.database_statistics AS h
ON              d.server_id = h.server_id
WHERE   d.server_id = ${server_id}
AND             h.recorded_time = (SELECT min(recorded_time) FROM pemhistory.database_statistics AS h2
WHERE   h2.server_id = d.server_id
AND  h2.recorded_time > d.recorded_time  - ''${param_1} minutes''::interval)' WHERE display_name='Shared buffers hit percentage' and object_type=200;

UPDATE pem.alert_template SET sql=E'SELECT abs(d.blks_hit-h.blks_hit)::float * 100
                 / GREATEST(abs(d.blks_hit-h.blks_hit)+abs(d.blks_read-h.blks_read)+COALESCE(abs(d.blks_icache_hit-h.blks_icache_hit), 0), 1)
FROM    pemdata.database_statistics AS d
JOIN    pemhistory.database_statistics AS h
ON              d.server_id = h.server_id
AND             d.database_name = h.database_name
WHERE   d.server_id = ${server_id}
AND             d.database_name = ''${database_name}''
AND             h.recorded_time = (SELECT min(recorded_time)
FROM pemhistory.database_statistics AS h2
WHERE   h2.server_id = d.server_id
AND             h2.database_name = d.database_name
AND             h2.recorded_time > d.recorded_time - ''${param_1} minutes''::interval)' WHERE display_name='Shared buffers hit percentage' and object_type=300;

-- This function will be called by server installer at the time of installation. This function add the PEM Server to the directory,
-- bind it to the default agent, and create the job for data purging.
--
-- NOTE: Even though - we do have new startup function to save the agen-server binding password.
--       We will have to keep this function to support the pemagent-2.0.0.

CREATE OR REPLACE FUNCTION pem.startup(server_desc text, server_name text, server_host text, server_port int, server_database text, server_ssl int,
					user_name text, ser_group text, agentid int, agent_database text)
  RETURNS void AS
$BODY$
DECLARE
	job_id integer;
	serverid integer;
	active_state boolean;
	name text;
BEGIN
    -- Default serverid
    serverid := 1;

    -- Check the server entry is already exist.
    SELECT active INTO active_state FROM pem.server WHERE id = serverid;

    -- if entry not found or server with id serverid is already exist and server is active then add new server.
    IF (NOT FOUND) OR (active_state = 't') THEN
        -- Create entry of PEM server in pem.server table.
        INSERT INTO pem.server (description, server, port, database, ssl) VALUES (server_desc, server_name, server_port, server_database, server_ssl) RETURNING id INTO serverid;

        -- Set the options of the PEM server
        INSERT INTO pem.server_option (server_id, pem_user, username, server_group) VALUES (serverid, user_name, user_name, ser_group);
    ELSE
        UPDATE pem.server SET description = server_desc, server = server_name, port = server_port, database = server_database, ssl = server_ssl, active = 't' WHERE id = serverid;

        UPDATE pem.server_option SET pem_user = user_name, username = user_name, server_group = ser_group WHERE server_id = serverid;
    END IF;

    -- Create Agent Server Binding
    INSERT INTO pem.agent_server_binding (agent_id, server_id, server, port, username, database) VALUES (agentid, serverid, server_host, server_port, user_name, agent_database);


    -- Check if the job already exists.
    SELECT jobid INTO job_id FROM pem.job WHERE jobname = 'Database cleanup' AND agent_id = agentid;

    IF (NOT FOUND) THEN
        -- Create data purging job.
        INSERT INTO pem.job(jobname, jobdesc, agent_id) VALUES('Database cleanup', 'This job runs periodically to purge old data from the database.', agentid) RETURNING jobid INTO job_id;
    END IF;

    -- Check if the job step already exists.
    SELECT jstname INTO name FROM pem.jobstep WHERE jstname = 'Database cleanup' AND jstjobid = job_id;

    IF (NOT FOUND) THEN
        -- Create data purging step.
        INSERT INTO pem.jobstep(jstjobid, jstname, jstdesc, jstkind, jstcode, server_id, database_name) VALUES (job_id, 'Database cleanup','This job step runs periodically to purge old data from the database.', 's',
        'SELECT pem.purge_data()', serverid, 'pem');
    END IF;

    -- Check if the job schedule already exists.
    SELECT jscname INTO name FROM pem.schedule WHERE jscname = 'Database cleanup' AND jscjobid = job_id;

    IF (NOT FOUND) THEN
        -- Create data purging schedule.
        INSERT INTO pem.schedule(jscjobid, jscname, jscdesc, jscminutes, jschours, jscweekdays, jscmonthdays, jscmonths) VALUES(job_id, 'Database cleanup', 'This job schedule runs periodically to purge old data from the database.', '{t,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f}', '{f,f,f,t,f,f,f,t,f,f,f,f,f,f,f,f,f,f,f,t,f,f,f,t}','{t,t,t,t,t,t,t}', '{t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t}', '{t,t,t,t,t,t,t,t,t,t,t,t}');
    END IF;

    -- Check if the job already exists.
    SELECT jobid INTO job_id FROM pem.job WHERE jobname = 'Audit log table cleanup' AND agent_id = agentid;

    IF (NOT FOUND) THEN
        -- Create data purging job.
	INSERT INTO pem.job(jobname, jobdesc, agent_id) VALUES('Audit log table cleanup', 'This job runs periodically to purge old data from the audit log table.', agentid) RETURNING jobid INTO job_id;
    END IF;

    -- Check if the job step already exists.
    SELECT jstname INTO name FROM pem.jobstep WHERE jstname = 'Audit log table cleanup' AND jstjobid = job_id;

    IF (NOT FOUND) THEN
        -- Create data purging step.
	INSERT INTO pem.jobstep(jstjobid, jstname, jstdesc, jstkind, jstcode, server_id, database_name) VALUES (job_id, 'Audit log table cleanup','This job step runs periodically to purge old data from the audit log table.', 's',
        'SELECT pem.purge_audit_log()', serverid, 'pem');
    END IF;

    -- Check if the job schedule already exists.
    SELECT jscname INTO name FROM pem.schedule WHERE jscname = 'Audit log table cleanup' AND jscjobid = job_id;

    IF (NOT FOUND) THEN
        -- Create data purging schedule.
        INSERT INTO pem.schedule(jscjobid, jscname, jscdesc, jscminutes, jschours, jscweekdays, jscmonthdays, jscmonths) VALUES(job_id, 'Audit log table cleanup', 'This job schedule runs periodically to purge old data from the audit log table.', '{t,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f}', '{t,f,f,f,f,f,f,f,f,f,f,f,t,f,f,f,f,f,f,f,f,f,f,f}','{t,t,t,t,t,t,t}', '{t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t}', '{t,t,t,t,t,t,t,t,t,t,t,t}');
    END IF;

    -- Check if the job already exists.
    SELECT jobid INTO job_id FROM pem.job WHERE jobname = 'Server log table cleanup' AND agent_id = agentid;

    IF (NOT FOUND) THEN
        -- Create data purging job.
        INSERT INTO pem.job(jobname, jobdesc, agent_id) VALUES('Server log table cleanup', 'This job runs periodically to purge old data from the server log table.', agentid) RETURNING jobid INTO job_id;
    END IF;

    -- Check if the job step already exists.
    SELECT jstname INTO name FROM pem.jobstep WHERE jstname = 'Server log table cleanup' AND jstjobid = job_id;

    IF (NOT FOUND) THEN
        -- Create data purging step.
        INSERT INTO pem.jobstep(jstjobid, jstname, jstdesc, jstkind, jstcode, server_id, database_name) VALUES (job_id, 'Server log table cleanup','This job step runs periodically to purge old data from the server log table.', 's',
        'SELECT pem.purge_server_log()', serverid, 'pem');
    END IF;

    -- Check if the job schedule already exists.
    SELECT jscname INTO name FROM pem.schedule WHERE jscname = 'Server log table cleanup' AND jscjobid = job_id;

    IF (NOT FOUND) THEN
        -- Create data purging schedule.
        INSERT INTO pem.schedule(jscjobid, jscname, jscdesc, jscminutes, jschours, jscweekdays, jscmonthdays, jscmonths) VALUES(job_id, 'Server log table cleanup', 'This job schedule runs periodically to purge old data from the server log table.', '{t,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f}', '{f,t,f,f,f,f,f,f,f,f,f,f,f,t,f,f,f,f,f,f,f,f,f,f}','{t,t,t,t,t,t,t}', '{t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t}', '{t,t,t,t,t,t,t,t,t,t,t,t}');
    END IF;

    -- Check if the job already exists.
    SELECT jobid INTO job_id FROM pem.job WHERE jobname = 'Probe log table cleanup' AND agent_id = agentid;

    IF (NOT FOUND) THEN
        -- Create data purging job.
        INSERT INTO pem.job(jobname, jobdesc, agent_id) VALUES('Probe log table cleanup', 'This job runs periodically to purge old data from the probe log table.', agentid) RETURNING jobid INTO job_id;
    END IF;

    -- Check if the job step already exists.
    SELECT jstname INTO name FROM pem.jobstep WHERE jstname = 'Probe log table cleanup' AND jstjobid = job_id;

    IF (NOT FOUND) THEN
        -- Create data purging step.
        INSERT INTO pem.jobstep(jstjobid, jstname, jstdesc, jstkind, jstcode, server_id, database_name) VALUES (job_id, 'Probe log table cleanup','This job step runs periodically to purge old data from the probe log table.', 's',
        'SELECT pem.purge_probe_log()', serverid, 'pem');
    END IF;

    -- Check if the job schedule already exists.
    SELECT jscname INTO name FROM pem.schedule WHERE jscname = 'Probe log table cleanup' AND jscjobid = job_id;

    IF (NOT FOUND) THEN
        -- Create data purging schedule.
        INSERT INTO pem.schedule(jscjobid, jscname, jscdesc, jscminutes, jschours, jscweekdays, jscmonthdays, jscmonths) VALUES(job_id, 'Probe log table cleanup', 'This job schedule runs periodically to purge old data from the probe log table.', '{t,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f}', '{f,f,t,f,f,f,f,f,f,f,f,f,f,f,t,f,f,f,f,f,f,f,f,f}','{t,t,t,t,t,t,t}', '{t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t}', '{t,t,t,t,t,t,t,t,t,t,t,t}');
    END IF;

    -- Check if the job already exists.
    SELECT jobid INTO job_id FROM pem.job WHERE jobname = 'SMTP spool table cleanup' AND agent_id = agentid;

    IF (NOT FOUND) THEN
        -- Create data purging job.
        INSERT INTO pem.job(jobname, jobdesc, agent_id) VALUES('SMTP spool table cleanup', 'This job runs periodically to purge old data from the smtp spool table.', agentid) RETURNING jobid INTO job_id;
    END IF;

    -- Check if the job step already exists.
    SELECT jstname INTO name FROM pem.jobstep WHERE jstname = 'SMTP spool table cleanup' AND jstjobid = job_id;

    IF (NOT FOUND) THEN
        -- Create data purging step.
        INSERT INTO pem.jobstep(jstjobid, jstname, jstdesc, jstkind, jstcode, server_id, database_name) VALUES (job_id, 'SMTP spool table cleanup','This job step runs periodically to purge old data from the smtp spool table.', 's',
        'SELECT pem.purge_smtp_spool()', serverid, 'pem');
    END IF;

    -- Check if the job schedule already exists.
    SELECT jscname INTO name FROM pem.schedule WHERE jscname = 'SMTP spool table cleanup' AND jscjobid = job_id;

    IF (NOT FOUND) THEN
        -- Create data purging schedule.
        INSERT INTO pem.schedule(jscjobid, jscname, jscdesc, jscminutes, jschours, jscweekdays, jscmonthdays, jscmonths) VALUES(job_id, 'SMTP spool table cleanup', 'This job schedule runs periodically to purge old data from the smtp spool table.', '{t,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f}', '{f,f,f,t,f,f,f,f,f,f,f,f,f,f,f,t,f,f,f,f,f,f,f,f}','{t,t,t,t,t,t,t}', '{t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t}', '{t,t,t,t,t,t,t,t,t,t,t,t}');
    END IF;

    -- Check if the job already exists.
    SELECT jobid INTO job_id FROM pem.job WHERE jobname = 'SNMP spool table cleanup' AND agent_id = agentid;

    IF (NOT FOUND) THEN
        -- Create data purging job.
        INSERT INTO pem.job(jobname, jobdesc, agent_id) VALUES('SNMP spool table cleanup', 'This job runs periodically to purge old data from the snmp spool table.', agentid) RETURNING jobid INTO job_id;
    END IF;

    -- Check if the job step already exists.
    SELECT jstname INTO name FROM pem.jobstep WHERE jstname = 'SNMP spool table cleanup' AND jstjobid = job_id;

    IF (NOT FOUND) THEN
        -- Create data purging step.
        INSERT INTO pem.jobstep(jstjobid, jstname, jstdesc, jstkind, jstcode, server_id, database_name) VALUES (job_id, 'SNMP spool table cleanup','This job step runs periodically to purge old data from the snmp spool table.', 's',
        'SELECT pem.purge_snmp_spool()', serverid, 'pem');
    END IF;

    -- Check if the job schedule already exists.
    SELECT jscname INTO name FROM pem.schedule WHERE jscname = 'SNMP spool table cleanup' AND jscjobid = job_id;

    IF (NOT FOUND) THEN
        -- Create data purging schedule.
        INSERT INTO pem.schedule(jscjobid, jscname, jscdesc, jscminutes, jschours, jscweekdays, jscmonthdays, jscmonths) VALUES(job_id, 'SNMP spool table cleanup', 'This job schedule runs periodically to purge old data from the snmp spool table.', '{t,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f}', '{f,f,f,f,t,f,f,f,f,f,f,f,f,f,f,f,t,f,f,f,f,f,f,f}','{t,t,t,t,t,t,t}', '{t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t}', '{t,t,t,t,t,t,t,t,t,t,t,t}');
    END IF;

    -- Check if the job already exists.
    SELECT jobid INTO job_id FROM pem.job WHERE jobname = 'Alert history table cleanup' AND agent_id = agentid;

    IF (NOT FOUND) THEN
        -- Create data purging job.
        INSERT INTO pem.job(jobname, jobdesc, agent_id) VALUES('Alert history table cleanup', 'This job runs periodically to purge old data from the alert history table.', agentid) RETURNING jobid INTO job_id;
    END IF;

    -- Check if the job step already exists.
    SELECT jstname INTO name FROM pem.jobstep WHERE jstname = 'Alert history table cleanup' AND jstjobid = job_id;

    IF (NOT FOUND) THEN
        -- Create data purging step.
        INSERT INTO pem.jobstep(jstjobid, jstname, jstdesc, jstkind, jstcode, server_id, database_name) VALUES (job_id, 'Alert history table cleanup','This job step runs periodically to purge old data from the alert history table.', 's',
        'SELECT pem.purge_alert_history()', serverid, 'pem');
    END IF;

    -- Check if the job schedule already exists.
    SELECT jscname INTO name FROM pem.schedule WHERE jscname = 'Alert history table cleanup' AND jscjobid = job_id;

    IF (NOT FOUND) THEN
        -- Create data purging schedule.
        INSERT INTO pem.schedule(jscjobid, jscname, jscdesc, jscminutes, jschours, jscweekdays, jscmonthdays, jscmonths) VALUES(job_id, 'Alert history table cleanup', 'This job schedule runs periodically to purge old data from the alert history table.', '{t,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f}', '{f,f,f,f,f,t,f,f,f,f,f,f,f,f,f,f,f,t,f,f,f,f,f,f}','{t,t,t,t,t,t,t}', '{t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t}', '{t,t,t,t,t,t,t,t,t,t,t,t}');
    END IF;

    -- Check if the job already exists.
    SELECT jobid INTO job_id FROM pem.job WHERE jobname = 'Job log table cleanup' AND agent_id = agentid;

    IF (NOT FOUND) THEN
        -- Create data purging job.
        INSERT INTO pem.job(jobname, jobdesc, agent_id) VALUES('Job log table cleanup', 'This job runs periodically to purge old data from the job log table.', agentid) RETURNING jobid INTO job_id;
    END IF;

    -- Check if the job step already exists.
    SELECT jstname INTO name FROM pem.jobstep WHERE jstname = 'Job log table cleanup' AND jstjobid = job_id;

    IF (NOT FOUND) THEN
        -- Create data purging step.
        INSERT INTO pem.jobstep(jstjobid, jstname, jstdesc, jstkind, jstcode, server_id, database_name) VALUES (job_id, 'Job log table cleanup','This job step runs periodically to purge old data from the job log table.', 's',
        'SELECT pem.purge_job_log()', serverid, 'pem');
    END IF;

    -- Check if the job schedule already exists.
    SELECT jscname INTO name FROM pem.schedule WHERE jscname = 'Job log table cleanup' AND jscjobid = job_id;

    IF (NOT FOUND) THEN
        -- Create data purging schedule.
        INSERT INTO pem.schedule(jscjobid, jscname, jscdesc, jscminutes, jschours, jscweekdays, jscmonthdays, jscmonths) VALUES(job_id, 'Job log table cleanup', 'This job schedule runs periodically to purge old data from the job log table.', '{t,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f}', '{f,f,f,f,f,f,t,f,f,f,f,f,f,f,f,f,f,f,t,f,f,f,f,f}','{t,t,t,t,t,t,t}', '{t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t}', '{t,t,t,t,t,t,t,t,t,t,t,t}');
    END IF;

END;
$BODY$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION pem.startup(server_desc text, server_name text, server_host text, server_port int, server_database text, server_ssl int,
					user_name text, passwd text, ser_group text, agentid int, agent_database text)
  RETURNS void AS
$BODY$
DECLARE
	job_id integer;
	serverid integer;
	active_state boolean;
	name text;
BEGIN
    -- Default serverid
    serverid := 1;

    -- Check the server entry is already exist.
    SELECT active INTO active_state FROM pem.server WHERE id = serverid;

    -- if entry not found or server with id serverid is already exist and server is active then add new server.
    IF (NOT FOUND) OR (active_state = 't') THEN
        -- Create entry of PEM server in pem.server table.
        INSERT INTO pem.server (description, server, port, database, ssl) VALUES (server_desc, server_name, server_port, server_database, server_ssl) RETURNING id INTO serverid;

        -- Set the options of the PEM server
        INSERT INTO pem.server_option (server_id, pem_user, username, server_group) VALUES (serverid, user_name, user_name, ser_group);
    ELSE
        UPDATE pem.server SET description = server_desc, server = server_name, port = server_port, database = server_database, ssl = server_ssl, active = 't' WHERE id = serverid;

        UPDATE pem.server_option SET pem_user = user_name, username = user_name, server_group = ser_group WHERE server_id = serverid;
    END IF;

    -- Create Agent Server Binding
    INSERT INTO pem.agent_server_binding (agent_id, server_id, server, port, username, database, password) VALUES (agentid, serverid, server_host, server_port, user_name, agent_database, passwd);


    -- Check if the job already exists.
    SELECT jobid INTO job_id FROM pem.job WHERE jobname = 'Database cleanup' AND agent_id = agentid;

    IF (NOT FOUND) THEN
        -- Create data purging job.
        INSERT INTO pem.job(jobname, jobdesc, agent_id) VALUES('Database cleanup', 'This job runs periodically to purge old data from the database.', agentid) RETURNING jobid INTO job_id;
    END IF;

    -- Check if the job step already exists.
    SELECT jstname INTO name FROM pem.jobstep WHERE jstname = 'Database cleanup' AND jstjobid = job_id;

    IF (NOT FOUND) THEN
        -- Create data purging step.
        INSERT INTO pem.jobstep(jstjobid, jstname, jstdesc, jstkind, jstcode, server_id, database_name) VALUES (job_id, 'Database cleanup','This job step runs periodically to purge old data from the database.', 's',
        'SELECT pem.purge_data()', serverid, 'pem');
    END IF;

    -- Check if the job schedule already exists.
    SELECT jscname INTO name FROM pem.schedule WHERE jscname = 'Database cleanup' AND jscjobid = job_id;

    IF (NOT FOUND) THEN
        -- Create data purging schedule.
        INSERT INTO pem.schedule(jscjobid, jscname, jscdesc, jscminutes, jschours, jscweekdays, jscmonthdays, jscmonths) VALUES(job_id, 'Database cleanup', 'This job schedule runs periodically to purge old data from the database.', '{t,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f}', '{f,f,f,t,f,f,f,t,f,f,f,f,f,f,f,f,f,f,f,t,f,f,f,t}','{t,t,t,t,t,t,t}', '{t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t}', '{t,t,t,t,t,t,t,t,t,t,t,t}');
    END IF;

    -- Check if the job already exists.
    SELECT jobid INTO job_id FROM pem.job WHERE jobname = 'Audit log table cleanup' AND agent_id = agentid;

    IF (NOT FOUND) THEN
        -- Create data purging job.
	INSERT INTO pem.job(jobname, jobdesc, agent_id) VALUES('Audit log table cleanup', 'This job runs periodically to purge old data from the audit log table.', agentid) RETURNING jobid INTO job_id;
    END IF;

    -- Check if the job step already exists.
    SELECT jstname INTO name FROM pem.jobstep WHERE jstname = 'Audit log table cleanup' AND jstjobid = job_id;

    IF (NOT FOUND) THEN
        -- Create data purging step.
	INSERT INTO pem.jobstep(jstjobid, jstname, jstdesc, jstkind, jstcode, server_id, database_name) VALUES (job_id, 'Audit log table cleanup','This job step runs periodically to purge old data from the audit log table.', 's',
        'SELECT pem.purge_audit_log()', serverid, 'pem');
    END IF;

    -- Check if the job schedule already exists.
    SELECT jscname INTO name FROM pem.schedule WHERE jscname = 'Audit log table cleanup' AND jscjobid = job_id;

    IF (NOT FOUND) THEN
        -- Create data purging schedule.
        INSERT INTO pem.schedule(jscjobid, jscname, jscdesc, jscminutes, jschours, jscweekdays, jscmonthdays, jscmonths) VALUES(job_id, 'Audit log table cleanup', 'This job schedule runs periodically to purge old data from the audit log table.', '{t,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f}', '{t,f,f,f,f,f,f,f,f,f,f,f,t,f,f,f,f,f,f,f,f,f,f,f}','{t,t,t,t,t,t,t}', '{t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t}', '{t,t,t,t,t,t,t,t,t,t,t,t}');
    END IF;

    -- Check if the job already exists.
    SELECT jobid INTO job_id FROM pem.job WHERE jobname = 'Server log table cleanup' AND agent_id = agentid;

    IF (NOT FOUND) THEN
        -- Create data purging job.
        INSERT INTO pem.job(jobname, jobdesc, agent_id) VALUES('Server log table cleanup', 'This job runs periodically to purge old data from the server log table.', agentid) RETURNING jobid INTO job_id;
    END IF;

    -- Check if the job step already exists.
    SELECT jstname INTO name FROM pem.jobstep WHERE jstname = 'Server log table cleanup' AND jstjobid = job_id;

    IF (NOT FOUND) THEN
        -- Create data purging step.
        INSERT INTO pem.jobstep(jstjobid, jstname, jstdesc, jstkind, jstcode, server_id, database_name) VALUES (job_id, 'Server log table cleanup','This job step runs periodically to purge old data from the server log table.', 's',
        'SELECT pem.purge_server_log()', serverid, 'pem');
    END IF;

    -- Check if the job schedule already exists.
    SELECT jscname INTO name FROM pem.schedule WHERE jscname = 'Server log table cleanup' AND jscjobid = job_id;

    IF (NOT FOUND) THEN
        -- Create data purging schedule.
        INSERT INTO pem.schedule(jscjobid, jscname, jscdesc, jscminutes, jschours, jscweekdays, jscmonthdays, jscmonths) VALUES(job_id, 'Server log table cleanup', 'This job schedule runs periodically to purge old data from the server log table.', '{t,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f}', '{f,t,f,f,f,f,f,f,f,f,f,f,f,t,f,f,f,f,f,f,f,f,f,f}','{t,t,t,t,t,t,t}', '{t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t}', '{t,t,t,t,t,t,t,t,t,t,t,t}');
    END IF;

    -- Check if the job already exists.
    SELECT jobid INTO job_id FROM pem.job WHERE jobname = 'Probe log table cleanup' AND agent_id = agentid;

    IF (NOT FOUND) THEN
        -- Create data purging job.
        INSERT INTO pem.job(jobname, jobdesc, agent_id) VALUES('Probe log table cleanup', 'This job runs periodically to purge old data from the probe log table.', agentid) RETURNING jobid INTO job_id;
    END IF;

    -- Check the job step already exist.
    SELECT jstname INTO name FROM pem.jobstep WHERE jstname = 'Probe log table cleanup' AND jstjobid = job_id;

    IF (NOT FOUND) THEN
        -- Create data purging step.
        INSERT INTO pem.jobstep(jstjobid, jstname, jstdesc, jstkind, jstcode, server_id, database_name) VALUES (job_id, 'Probe log table cleanup','This job step runs periodically to purge old data from the probe log table.', 's',
        'SELECT pem.purge_probe_log()', serverid, 'pem');
    END IF;

    -- Check if the job schedule already exists.
    SELECT jscname INTO name FROM pem.schedule WHERE jscname = 'Probe log table cleanup' AND jscjobid = job_id;

    IF (NOT FOUND) THEN
        -- Create data purging schedule.
        INSERT INTO pem.schedule(jscjobid, jscname, jscdesc, jscminutes, jschours, jscweekdays, jscmonthdays, jscmonths) VALUES(job_id, 'Probe log table cleanup', 'This job schedule runs periodically to purge old data from the probe log table.', '{t,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f}', '{f,f,t,f,f,f,f,f,f,f,f,f,f,f,t,f,f,f,f,f,f,f,f,f}','{t,t,t,t,t,t,t}', '{t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t}', '{t,t,t,t,t,t,t,t,t,t,t,t}');
    END IF;

    -- Check if the job already exists.
    SELECT jobid INTO job_id FROM pem.job WHERE jobname = 'SMTP spool table cleanup' AND agent_id = agentid;

    IF (NOT FOUND) THEN
        -- Create data purging job.
        INSERT INTO pem.job(jobname, jobdesc, agent_id) VALUES('SMTP spool table cleanup', 'This job runs periodically to purge old data from the smtp spool table.', agentid) RETURNING jobid INTO job_id;
    END IF;

    -- Check if the job step already exists.
    SELECT jstname INTO name FROM pem.jobstep WHERE jstname = 'SMTP spool table cleanup' AND jstjobid = job_id;

    IF (NOT FOUND) THEN
        -- Create data purging step.
        INSERT INTO pem.jobstep(jstjobid, jstname, jstdesc, jstkind, jstcode, server_id, database_name) VALUES (job_id, 'SMTP spool table cleanup','This job step runs periodically to purge old data from the smtp spool table.', 's',
        'SELECT pem.purge_smtp_spool()', serverid, 'pem');
    END IF;

    -- Check if the job schedule already exists.
    SELECT jscname INTO name FROM pem.schedule WHERE jscname = 'SMTP spool table cleanup' AND jscjobid = job_id;

    IF (NOT FOUND) THEN
        -- Create data purging schedule.
        INSERT INTO pem.schedule(jscjobid, jscname, jscdesc, jscminutes, jschours, jscweekdays, jscmonthdays, jscmonths) VALUES(job_id, 'SMTP spool table cleanup', 'This job schedule runs periodically to purge old data from the smtp spool table.', '{t,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f}', '{f,f,f,t,f,f,f,f,f,f,f,f,f,f,f,t,f,f,f,f,f,f,f,f}','{t,t,t,t,t,t,t}', '{t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t}', '{t,t,t,t,t,t,t,t,t,t,t,t}');
    END IF;

    -- Check if the job already exists.
    SELECT jobid INTO job_id FROM pem.job WHERE jobname = 'SNMP spool table cleanup' AND agent_id = agentid;

    IF (NOT FOUND) THEN
        -- Create data purging job.
        INSERT INTO pem.job(jobname, jobdesc, agent_id) VALUES('SNMP spool table cleanup', 'This job runs periodically to purge old data from the snmp spool table.', agentid) RETURNING jobid INTO job_id;
    END IF;

    -- Check if the job step already exists.
    SELECT jstname INTO name FROM pem.jobstep WHERE jstname = 'SNMP spool table cleanup' AND jstjobid = job_id;

    IF (NOT FOUND) THEN
        -- Create data purging step.
        INSERT INTO pem.jobstep(jstjobid, jstname, jstdesc, jstkind, jstcode, server_id, database_name) VALUES (job_id, 'SNMP spool table cleanup','This job step runs periodically to purge old data from the snmp spool table.', 's',
        'SELECT pem.purge_snmp_spool()', serverid, 'pem');
    END IF;

    -- Check if the job schedule already exists.
    SELECT jscname INTO name FROM pem.schedule WHERE jscname = 'SNMP spool table cleanup' AND jscjobid = job_id;

    IF (NOT FOUND) THEN
        -- Create data purging schedule.
        INSERT INTO pem.schedule(jscjobid, jscname, jscdesc, jscminutes, jschours, jscweekdays, jscmonthdays, jscmonths) VALUES(job_id, 'SNMP spool table cleanup', 'This job schedule runs periodically to purge old data from the snmp spool table.', '{t,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f}', '{f,f,f,f,t,f,f,f,f,f,f,f,f,f,f,f,t,f,f,f,f,f,f,f}','{t,t,t,t,t,t,t}', '{t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t}', '{t,t,t,t,t,t,t,t,t,t,t,t}');
    END IF;

    -- Check if the job already exists.
    SELECT jobid INTO job_id FROM pem.job WHERE jobname = 'Alert history table cleanup' AND agent_id = agentid;

    IF (NOT FOUND) THEN
        -- Create data purging job.
        INSERT INTO pem.job(jobname, jobdesc, agent_id) VALUES('Alert history table cleanup', 'This job runs periodically to purge old data from the alert history table.', agentid) RETURNING jobid INTO job_id;
    END IF;

    -- Check if the job step already exists.
    SELECT jstname INTO name FROM pem.jobstep WHERE jstname = 'Alert history table cleanup' AND jstjobid = job_id;

    IF (NOT FOUND) THEN
        -- Create data purging step.
        INSERT INTO pem.jobstep(jstjobid, jstname, jstdesc, jstkind, jstcode, server_id, database_name) VALUES (job_id, 'Alert history table cleanup','This job step runs periodically to purge old data from the alert history table.', 's',
        'SELECT pem.purge_alert_history()', serverid, 'pem');
    END IF;

    -- Check if the job schedule already exists.
    SELECT jscname INTO name FROM pem.schedule WHERE jscname = 'Alert history table cleanup' AND jscjobid = job_id;

    IF (NOT FOUND) THEN
        -- Create data purging schedule.
        INSERT INTO pem.schedule(jscjobid, jscname, jscdesc, jscminutes, jschours, jscweekdays, jscmonthdays, jscmonths) VALUES(job_id, 'Alert history table cleanup', 'This job schedule runs periodically to purge old data from the alert history table.', '{t,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f}', '{f,f,f,f,f,t,f,f,f,f,f,f,f,f,f,f,f,t,f,f,f,f,f,f}','{t,t,t,t,t,t,t}', '{t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t}', '{t,t,t,t,t,t,t,t,t,t,t,t}');
    END IF;

    -- Check if the job already exists.
    SELECT jobid INTO job_id FROM pem.job WHERE jobname = 'Job log table cleanup' AND agent_id = agentid;

    IF (NOT FOUND) THEN
        -- Create data purging job.
        INSERT INTO pem.job(jobname, jobdesc, agent_id) VALUES('Job log table cleanup', 'This job runs periodically to purge old data from the job log table.', agentid) RETURNING jobid INTO job_id;
    END IF;

    -- Check if the job step already exists.
    SELECT jstname INTO name FROM pem.jobstep WHERE jstname = 'Job log table cleanup' AND jstjobid = job_id;

    IF (NOT FOUND) THEN
        -- Create data purging step.
        INSERT INTO pem.jobstep(jstjobid, jstname, jstdesc, jstkind, jstcode, server_id, database_name) VALUES (job_id, 'Job log table cleanup','This job step runs periodically to purge old data from the job log table.', 's',
        'SELECT pem.purge_job_log()', serverid, 'pem');
    END IF;

    -- Check if the job schedule already exists.
    SELECT jscname INTO name FROM pem.schedule WHERE jscname = 'Job log table cleanup' AND jscjobid = job_id;

    IF (NOT FOUND) THEN
        -- Create data purging schedule.
        INSERT INTO pem.schedule(jscjobid, jscname, jscdesc, jscminutes, jschours, jscweekdays, jscmonthdays, jscmonths) VALUES(job_id, 'Job log table cleanup', 'This job schedule runs periodically to purge old data from the job log table.', '{t,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f}', '{f,f,f,f,f,f,t,f,f,f,f,f,f,f,f,f,f,f,t,f,f,f,f,f}','{t,t,t,t,t,t,t}', '{t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t}', '{t,t,t,t,t,t,t,t,t,t,t,t}');
    END IF;

END;
$BODY$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION pem.purge_smtp_spool()
RETURNS void AS $$
	DELETE FROM pem.smtp_spool WHERE sent_status = 's' AND (now() - recorded_time) >= ((SELECT value FROM pem.config WHERE param = 'smtp_spool_retention_time')||'days')::interval;
$$ LANGUAGE sql SECURITY DEFINER;

CREATE OR REPLACE FUNCTION pem.purge_snmp_spool()
RETURNS void AS $$
	DELETE FROM pem.snmp_spool WHERE sent_status = 's' AND (now() - recorded_time) >= ((SELECT value FROM pem.config WHERE param = 'snmp_spool_retention_time')||'days')::interval;
$$ LANGUAGE sql SECURITY DEFINER;

CREATE OR REPLACE FUNCTION pem.purge_audit_log()
RETURNS void AS $$
	-- Purge data from audit log table
        DELETE FROM pemdata.audit_logs
        WHERE (now() - log_time) >= ((SELECT value FROM pem.config WHERE param = 'audit_log_retention_time')||'days')::interval;
$$ LANGUAGE sql SECURITY DEFINER;

CREATE OR REPLACE FUNCTION pem.purge_server_log()
RETURNS void AS $$
	-- Purge data from server log table
	DELETE FROM pemdata.server_logs
	WHERE (now() - log_time) >= ((SELECT value FROM pem.config WHERE param = 'server_log_retention_time')||'days')::interval;
$$ LANGUAGE sql SECURITY DEFINER;

CREATE OR REPLACE FUNCTION pem.purge_probe_log()
RETURNS void AS $$
	-- Purge data from probe log table
        DELETE FROM pem.probe_log
        WHERE (now() - recorded_time) >= ((SELECT value FROM pem.config WHERE param = 'probe_log_retention_time')||'days')::interval;
$$ LANGUAGE sql SECURITY DEFINER;

CREATE OR REPLACE FUNCTION pem.purge_alert_history()
RETURNS void AS $$
	-- Purge data from alert history table
	DELETE FROM pem.alert_history AS h
	USING pem.alert AS a
	WHERE a.id = h.alert_id
	AND (now() - h.generated) >= (a.history_retention||'days')::interval;
$$ LANGUAGE sql SECURITY DEFINER;

CREATE OR REPLACE FUNCTION pem.purge_job_log()
RETURNS void AS $$

	-- Purge old jobs, steps and schedules
        DELETE FROM pem.job
        WHERE jobnextrun IS NULL
        AND (now() - joblastrun) >= ((SELECT value FROM pem.config WHERE param = 'job_retention_time')||'days')::interval;

	-- Purge job log and job step log
	DELETE FROM pem.joblog AS jl
	WHERE (now() - jl.jlgstart) >= ((SELECT value FROM pem.config WHERE param = 'job_retention_time')||'days')::interval;
$$ LANGUAGE sql SECURITY DEFINER;
--
-- Adding queries for the PostgreSQL/PostgresPlus Advanced Server 9.3 compatibility.
--

INSERT INTO pem.probe_server_version(probe_id,server_version_id,probe_code) VALUES((SELECT id FROM pem.probe WHERE internal_name='oc_schema'),10903,NULL);
INSERT INTO pem.probe_server_version(probe_id,server_version_id,probe_code) VALUES((SELECT id FROM pem.probe WHERE internal_name='oc_schema'),20903,'SELECT nspname AS schema_name FROM pg_catalog.pg_namespace WHERE (nspname = ''pg_catalog'' OR nspname NOT LIKE E''pg\\\\_%'') AND nspparent = 0');
INSERT INTO pem.probe_server_version(probe_id,server_version_id,probe_code) VALUES((SELECT id FROM pem.probe WHERE internal_name='oc_function'),10903,NULL);
INSERT INTO pem.probe_server_version(probe_id,server_version_id,probe_code) VALUES((SELECT id FROM pem.probe WHERE internal_name='oc_function'),20903,'
SELECT	'''' AS package_name, f.proname AS function_name, f.protype AS function_type,
		f.prorettype::regtype AS return_type, f.proargtypes::regtype[] AS arg_types
FROM	pg_catalog.pg_namespace AS s	-- schema
JOIN	pg_catalog.pg_proc AS f			-- function
ON		f.pronamespace = s.oid
WHERE	s.nspparent = 0 -- select schema that is not a child of some other schema
AND		s.nspname = %{schema_name}
UNION ALL
SELECT	p.nspname AS package_name, f.proname AS function_name, f.protype AS function_type,
		f.prorettype::regtype AS return_type, f.proargtypes::regtype[] AS arg_types
FROM	pg_catalog.pg_namespace AS s	-- schema
JOIN	pg_catalog.pg_namespace AS p	-- package
ON		p.nspparent = s.oid
JOIN	pg_catalog.pg_proc AS f			-- function
ON		f.pronamespace = p.oid
WHERE	p.nspparent <> 0 -- select schema that _is_ a child of some other schema
AND		s.nspname = %{schema_name}');
INSERT INTO pem.probe_server_version(probe_id,server_version_id,probe_code) VALUES((SELECT id FROM pem.probe WHERE internal_name = 'database_statistics'),10903,'
SELECT	d1.datname AS database_name, d1.numbackends,
	(SELECT COALESCE(count(query)::bigint, 0::bigint) FROM pg_catalog.pg_stat_activity WHERE datname = d1.datname AND query = ''<IDLE>'') AS idle_backends,
	d1.xact_commit, d1.xact_rollback, d1.blks_hit, NULL::bigint AS blks_icache_hit, d1.blks_read,d1.tup_returned,
	d1.tup_fetched, d1.tup_inserted, d1.tup_updated, d1.tup_deleted
FROM	pg_catalog.pg_stat_database d1');
INSERT INTO pem.probe_server_version(probe_id,server_version_id,probe_code) VALUES((SELECT id FROM pem.probe WHERE internal_name = 'database_statistics'),20903,'
SELECT	d1.datname AS database_name, d1.numbackends,
        (SELECT COALESCE(count(query)::bigint, 0::bigint) FROM pg_catalog.pg_stat_activity WHERE datname = d1.datname AND query = ''<IDLE>'') AS idle_backends,
        d1.xact_commit, d1.xact_rollback, d1.blks_hit, d1.blks_icache_hit, d1.blks_read, d1.tup_returned,
        d1.tup_fetched, d1.tup_inserted, d1.tup_updated, d1.tup_deleted
FROM	pg_catalog.pg_stat_database d1');
INSERT INTO pem.probe_server_version(probe_id,server_version_id,probe_code) VALUES((SELECT id FROM pem.probe WHERE internal_name = 'table_statistics'),10903,NULL);
INSERT INTO pem.probe_server_version(probe_id,server_version_id,probe_code) VALUES((SELECT id FROM pem.probe WHERE internal_name = 'table_statistics'),20903,NULL);
INSERT INTO pem.probe_server_version(probe_id,server_version_id,probe_code) VALUES((SELECT id FROM pem.probe WHERE internal_name = 'function_statistics'),10903,NULL);
INSERT INTO pem.probe_server_version(probe_id,server_version_id,probe_code) VALUES((SELECT id FROM pem.probe WHERE internal_name = 'function_statistics'),20903,'
SELECT	s.nspname AS schema_name, '''' AS package_name, f.proname AS function_name,
	f.protype AS function_type, f.prorettype::regtype AS return_type,
	f.proargtypes::regtype[] AS arg_types,
	fs.calls AS call_count, fs.total_time, fs.self_time
FROM	pg_catalog.pg_namespace AS s			-- schema
JOIN	pg_catalog.pg_proc AS f					-- function
ON	f.pronamespace = s.oid
JOIN	pg_catalog.pg_stat_user_functions AS fs	-- Func. stats
ON	fs.funcid = f.oid
WHERE	s.nspparent = 0 -- select schema that is not a child of some other schema
UNION ALL
SELECT	s.nspname AS schema_name, p.nspname AS package_name, f.proname AS function_name,
	f.protype AS function_type, f.prorettype::regtype AS return_type,
	f.proargtypes::regtype[] AS arg_types,
	fs.calls AS call_count, fs.total_time, fs.self_time
FROM	pg_catalog.pg_namespace AS s			-- schema
JOIN	pg_catalog.pg_namespace AS p			-- package
ON	p.nspparent = s.oid
JOIN	pg_catalog.pg_proc AS f					-- function
ON	f.pronamespace = p.oid
JOIN	pg_catalog.pg_stat_user_functions AS fs	-- Func. stats
ON	fs.funcid = f.oid
WHERE	p.nspparent <> 0 -- select schema that _is_ a child of some other schema
');
INSERT INTO pem.probe_server_version(probe_id,server_version_id,probe_code) VALUES((SELECT id FROM pem.probe WHERE internal_name = 'table_size'),10903,'SELECT n.nspname AS schema_name, c.relname AS table_name, pg_relation_size(c.oid) / 1048576 AS table_size_mb, pg_indexes_size(c.oid) / 1048576 AS size_of_indexes_mb, pg_total_relation_size(c.oid) / 1048576 AS total_table_size_mb FROM pg_class c, pg_namespace n WHERE c.relnamespace = n.oid AND c.relkind = ''r''');
INSERT INTO pem.probe_server_version(probe_id,server_version_id,probe_code) VALUES((SELECT id FROM pem.probe WHERE internal_name = 'table_size'),20903,'SELECT n.nspname AS schema_name, c.relname AS table_name, pg_relation_size(c.oid) / 1048576 AS table_size_mb, pg_indexes_size(c.oid) / 1048576 AS size_of_indexes_mb, pg_total_relation_size(c.oid) / 1048576 AS total_table_size_mb FROM pg_class c, pg_namespace n WHERE c.relnamespace = n.oid AND c.relkind = ''r''');
INSERT INTO pem.probe_server_version(probe_id,server_version_id,probe_code) VALUES((SELECT id FROM pem.probe WHERE internal_name = 'session_info'),10903,'SELECT datname AS database_name, pid AS procpid, usename, client_addr, client_port, backend_start, xact_start, query_start, waiting AS is_waiting, query = $$<IDLE>$$ AS is_idle, query = $$<IDLE> in transaction$$ AS is_idle_in_transaction, query ilike $$VACUUM%$$ as is_vacuum, client_port IS NULL AND (query like $$autovacuum:%$$ OR query like $$VACUUM%$$) as is_autovacuum, now() AS capture_time FROM pg_catalog.pg_stat_activity');
INSERT INTO pem.probe_server_version(probe_id,server_version_id,probe_code) VALUES((SELECT id FROM pem.probe WHERE internal_name = 'session_info'),20903,'SELECT datname AS database_name, pid AS procpid, usename, client_addr, client_port, backend_start, xact_start, query_start, waiting AS is_waiting, query = $$<IDLE>$$ AS is_idle, query = $$<IDLE> in transaction$$ AS is_idle_in_transaction, query ilike $$VACUUM%$$ as is_vacuum, client_port IS NULL AND (query like $$autovacuum:%$$ OR query like $$VACUUM%$$) as is_autovacuum, now() AS capture_time FROM pg_catalog.pg_stat_activity');

INSERT INTO pem.probe_server_version(probe_id,server_version_id,probe_code) VALUES((SELECT ID FROM pem.probe WHERE internal_name='session_waits'),20903,'SELECT sw.backend_id, psa.datname AS dbname, psa.usename, sw.wait_name, sw.wait_count, avg_wait_time, max_wait_time, total_wait_time FROM session_waits sw, pg_stat_activity psa WHERE sw.backend_id = psa.pid');
INSERT INTO pem.probe_server_version(probe_id,server_version_id,probe_code) VALUES((SELECT id FROM pem.probe WHERE internal_name = 'lock_info'),10903,'
SELECT		COALESCE(d.datname, '''')			AS database_name,
		COALESCE(l.pid::bigint, -1)		AS procpid,
		l.relation::text::numeric		AS objid,		-- relation/XID/VXID/classid
		COALESCE(l.page::bigint, -1)	AS objsubid,	-- page/objid
		COALESCE(l.tuple::bigint, -1)	AS objsubsubid,	-- tuple/objsubid
		l.locktype, l.mode AS lockmode, l.granted AS lockgranted
FROM		pg_catalog.pg_locks AS l
LEFT JOIN	pg_catalog.pg_stat_activity AS sa
ON		l.pid = sa.pid
JOIN		pg_catalog.pg_database AS d
ON		sa.datid = d.oid
WHERE		l.locktype IN (''relation'', ''extend'', ''page'', ''tuple'')
UNION ALL
SELECT		COALESCE(d.datname, '''')		AS database_name,
		COALESCE(l.pid::bigint, -1)	AS procpid,
		transactionid::text::numeric	AS objid,	-- relation/XID/VXID/classid
		-1							AS objsubid,	-- page/objid
		-1							AS objsubsubid,	-- tuple/objsubid
		l.locktype, l.mode AS lockmode, l.granted AS lockgranted
FROM		pg_catalog.pg_locks AS l
LEFT JOIN	pg_catalog.pg_stat_activity AS sa
ON		l.pid = sa.pid
JOIN		pg_catalog.pg_database AS d
ON		sa.datid = d.oid
WHERE		l.locktype = ''transactionid''
UNION ALL
SELECT		COALESCE(d.datname, '''')				AS database_name,
		COALESCE(l.pid::bigint, -1)			AS procpid,
		regexp_replace(l.virtualxid, ''/'', ''.'')::numeric AS objid,-- relation/XID/VXID/classid
		-1									AS objsubid,	-- page/objid
		-1									AS objsubsubid,	-- tuple/objsubid
		l.locktype, l.mode AS lockmode, l.granted AS lockgranted
FROM		pg_catalog.pg_locks AS l
LEFT JOIN	pg_catalog.pg_stat_activity AS sa
ON		l.pid = sa.pid
JOIN		pg_catalog.pg_database AS d
ON		sa.datid = d.oid
WHERE		l.locktype = ''virtualxid''
UNION ALL
SELECT		COALESCE(d.datname, '''')			AS database_name,
		COALESCE(l.pid::bigint, -1)		AS procpid,
		classid::text::numeric			AS objid,-- relation/XID/VXID/classid
		COALESCE(l.objid::bigint, -1)	AS objsubid,	-- page/objid
		COALESCE(l.objsubid::bigint, -1)AS objsubsubid,	-- tuple/objsubid
		l.locktype, l.mode AS lockmode, l.granted AS lockgranted
FROM		pg_catalog.pg_locks AS l
LEFT JOIN	pg_catalog.pg_stat_activity AS sa
ON		l.pid = sa.pid
JOIN		pg_catalog.pg_database AS d
ON		sa.datid = d.oid
WHERE		l.locktype IN (''object'', ''advisory'')');
INSERT INTO pem.probe_server_version(probe_id,server_version_id,probe_code) VALUES((SELECT id FROM pem.probe WHERE internal_name = 'lock_info'),20903,'
SELECT		COALESCE(d.datname, '''')			AS database_name,
		COALESCE(l.pid::bigint, -1)		AS procpid,
		l.relation::text::numeric		AS objid,		-- relation/XID/VXID/classid
		COALESCE(l.page::bigint, -1)	AS objsubid,	-- page/objid
		COALESCE(l.tuple::bigint, -1)	AS objsubsubid,	-- tuple/objsubid
		l.locktype, l.mode AS lockmode, l.granted AS lockgranted
FROM		pg_catalog.pg_locks AS l
LEFT JOIN	pg_catalog.pg_stat_activity AS sa
ON		l.pid = sa.pid
JOIN		pg_catalog.pg_database AS d
ON		sa.datid = d.oid
WHERE		l.locktype IN (''relation'', ''extend'', ''page'', ''tuple'')
UNION ALL
SELECT		COALESCE(d.datname, '''')		AS database_name,
		COALESCE(l.pid::bigint, -1)	AS procpid,
		transactionid::text::numeric	AS objid,	-- relation/XID/VXID/classid
		-1							AS objsubid,	-- page/objid
		-1							AS objsubsubid,	-- tuple/objsubid
		l.locktype, l.mode AS lockmode, l.granted AS lockgranted
FROM		pg_catalog.pg_locks AS l
LEFT JOIN	pg_catalog.pg_stat_activity AS sa
ON		l.pid = sa.pid
JOIN		pg_catalog.pg_database AS d
ON		sa.datid = d.oid
WHERE		l.locktype = ''transactionid''
UNION ALL
SELECT		COALESCE(d.datname, '''')				AS database_name,
		COALESCE(l.pid::bigint, -1)			AS procpid,
		regexp_replace(l.virtualxid, ''/'', ''.'')::numeric AS objid,-- relation/XID/VXID/classid
		-1									AS objsubid,	-- page/objid
		-1									AS objsubsubid,	-- tuple/objsubid
		l.locktype, l.mode AS lockmode, l.granted AS lockgranted
FROM		pg_catalog.pg_locks AS l
LEFT JOIN	pg_catalog.pg_stat_activity AS sa
ON		l.pid = sa.pid
JOIN		pg_catalog.pg_database AS d
ON		sa.datid = d.oid
WHERE		l.locktype = ''virtualxid''
UNION ALL
SELECT		COALESCE(d.datname, '''')			AS database_name,
		COALESCE(l.pid::bigint, -1)		AS procpid,
		classid::text::numeric			AS objid,-- relation/XID/VXID/classid
		COALESCE(l.objid::bigint, -1)	AS objsubid,	-- page/objid
		COALESCE(l.objsubid::bigint, -1)AS objsubsubid,	-- tuple/objsubid
		l.locktype, l.mode AS lockmode, l.granted AS lockgranted
FROM		pg_catalog.pg_locks AS l
LEFT JOIN	pg_catalog.pg_stat_activity AS sa
ON		l.pid = sa.pid
JOIN		pg_catalog.pg_database AS d
ON		sa.datid = d.oid
WHERE		l.locktype IN (''object'', ''advisory'')');
INSERT INTO pem.probe_server_version(probe_id,server_version_id,probe_code) VALUES((SELECT id FROM pem.probe WHERE internal_name = 'background_writer_statistics'),10903,NULL);
INSERT INTO pem.probe_server_version(probe_id,server_version_id,probe_code) VALUES((SELECT id FROM pem.probe WHERE internal_name = 'background_writer_statistics'),20903,NULL);
INSERT INTO pem.probe_server_version(probe_id,server_version_id,probe_code) VALUES((SELECT id FROM pem.probe WHERE internal_name = 'system_waits'),20903,NULL);
INSERT INTO pem.probe_server_version(probe_id,server_version_id,probe_code) VALUES((SELECT id FROM pem.probe WHERE internal_name = 'audit_configuration'),20903,NULL);

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

	SELECT mail_subject, mail_message INTO subject_mail, message_mail FROM pem.email_template WHERE display_name = template;

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

	subject_mail = regexp_replace(subject_mail, '%AlertName%', alert_name);
	subject_mail = regexp_replace(subject_mail, '%ObjectName%', alert_object_name);
	message_mail = regexp_replace(message_mail, '%AlertName%', alert_name);
	message_mail = regexp_replace(message_mail, '%ObjectName%', msg_object_name);
	message_mail = regexp_replace(message_mail, '%ThresholdValue%', alert_thresholdvalue::text);
END;
$$ LANGUAGE plpgsql;
-- Done!

-- Fixed RM #31675
-- Created an anonymous code block to fix RM #31675. This code block will create cleanup jobs in case of upgrade.
DO $$
DECLARE
	job_id integer;
	serverid integer;
	agentid integer;
	name text;
BEGIN
    -- Default serverid
    serverid := 1;

    -- Default agentid
    agentid := 1;

    -- Check if the job already exists.
    SELECT jobid INTO job_id FROM pem.job WHERE jobname = 'Database cleanup' AND agent_id = agentid;

    IF (NOT FOUND) THEN
        -- Create data purging job.
        INSERT INTO pem.job(jobname, jobdesc, agent_id) VALUES('Database cleanup', 'This job runs periodically to purge old data from the database.', agentid) RETURNING jobid INTO job_id;
    END IF;

    -- Check if the job step already exists.
    SELECT jstname INTO name FROM pem.jobstep WHERE jstname = 'Database cleanup' AND jstjobid = job_id;

    IF (NOT FOUND) THEN
        -- Create data purging step.
        INSERT INTO pem.jobstep(jstjobid, jstname, jstdesc, jstkind, jstcode, server_id, database_name) VALUES (job_id, 'Database cleanup','This job step runs periodically to purge old data from the database.', 's',
        'SELECT pem.purge_data()', serverid, 'pem');
    END IF;

    -- Check if the job schedule already exists.
    SELECT jscname INTO name FROM pem.schedule WHERE jscname = 'Database cleanup' AND jscjobid = job_id;

    IF (NOT FOUND) THEN
        -- Create data purging schedule.
        INSERT INTO pem.schedule(jscjobid, jscname, jscdesc, jscminutes, jschours, jscweekdays, jscmonthdays, jscmonths) VALUES(job_id, 'Database cleanup', 'This job schedule runs periodically to purge old data from the database.', '{t,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f}', '{f,f,f,t,f,f,f,t,f,f,f,f,f,f,f,f,f,f,f,t,f,f,f,t}','{t,t,t,t,t,t,t}', '{t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t}', '{t,t,t,t,t,t,t,t,t,t,t,t}');
    END IF;

    -- Check if the job already exists.
    SELECT jobid INTO job_id FROM pem.job WHERE jobname = 'Audit log table cleanup' AND agent_id = agentid;

    IF (NOT FOUND) THEN
        -- Create data purging job.
	INSERT INTO pem.job(jobname, jobdesc, agent_id) VALUES('Audit log table cleanup', 'This job runs periodically to purge old data from the audit log table.', agentid) RETURNING jobid INTO job_id;
    END IF;

    -- Check if the job step already exists.
    SELECT jstname INTO name FROM pem.jobstep WHERE jstname = 'Audit log table cleanup' AND jstjobid = job_id;

    IF (NOT FOUND) THEN
        -- Create data purging step.
	INSERT INTO pem.jobstep(jstjobid, jstname, jstdesc, jstkind, jstcode, server_id, database_name) VALUES (job_id, 'Audit log table cleanup','This job step runs periodically to purge old data from the audit log table.', 's',
        'SELECT pem.purge_audit_log()', serverid, 'pem');
    END IF;

    -- Check if the job schedule already exists.
    SELECT jscname INTO name FROM pem.schedule WHERE jscname = 'Audit log table cleanup' AND jscjobid = job_id;

    IF (NOT FOUND) THEN
        -- Create data purging schedule.
        INSERT INTO pem.schedule(jscjobid, jscname, jscdesc, jscminutes, jschours, jscweekdays, jscmonthdays, jscmonths) VALUES(job_id, 'Audit log table cleanup', 'This job schedule runs periodically to purge old data from the audit log table.', '{t,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f}', '{t,f,f,f,f,f,f,f,f,f,f,f,t,f,f,f,f,f,f,f,f,f,f,f}','{t,t,t,t,t,t,t}', '{t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t}', '{t,t,t,t,t,t,t,t,t,t,t,t}');
    END IF;

    -- Check if the job already exists.
    SELECT jobid INTO job_id FROM pem.job WHERE jobname = 'Server log table cleanup' AND agent_id = agentid;

    IF (NOT FOUND) THEN
        -- Create data purging job.
        INSERT INTO pem.job(jobname, jobdesc, agent_id) VALUES('Server log table cleanup', 'This job runs periodically to purge old data from the server log table.', agentid) RETURNING jobid INTO job_id;
    END IF;

    -- Check if the job step already exists.
    SELECT jstname INTO name FROM pem.jobstep WHERE jstname = 'Server log table cleanup' AND jstjobid = job_id;

    IF (NOT FOUND) THEN
        -- Create data purging step.
        INSERT INTO pem.jobstep(jstjobid, jstname, jstdesc, jstkind, jstcode, server_id, database_name) VALUES (job_id, 'Server log table cleanup','This job step runs periodically to purge old data from the server log table.', 's',
        'SELECT pem.purge_server_log()', serverid, 'pem');
    END IF;

    -- Check if the job schedule already exists.
    SELECT jscname INTO name FROM pem.schedule WHERE jscname = 'Server log table cleanup' AND jscjobid = job_id;

    IF (NOT FOUND) THEN
        -- Create data purging schedule.
        INSERT INTO pem.schedule(jscjobid, jscname, jscdesc, jscminutes, jschours, jscweekdays, jscmonthdays, jscmonths) VALUES(job_id, 'Server log table cleanup', 'This job schedule runs periodically to purge old data from the server log table.', '{t,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f}', '{f,t,f,f,f,f,f,f,f,f,f,f,f,t,f,f,f,f,f,f,f,f,f,f}','{t,t,t,t,t,t,t}', '{t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t}', '{t,t,t,t,t,t,t,t,t,t,t,t}');
    END IF;

    -- Check if the job already exists.
    SELECT jobid INTO job_id FROM pem.job WHERE jobname = 'Probe log table cleanup' AND agent_id = agentid;

    IF (NOT FOUND) THEN
        -- Create data purging job.
        INSERT INTO pem.job(jobname, jobdesc, agent_id) VALUES('Probe log table cleanup', 'This job runs periodically to purge old data from the probe log table.', agentid) RETURNING jobid INTO job_id;
    END IF;

    -- Check if the job step already exists.
    SELECT jstname INTO name FROM pem.jobstep WHERE jstname = 'Probe log table cleanup' AND jstjobid = job_id;

    IF (NOT FOUND) THEN
        -- Create data purging step.
        INSERT INTO pem.jobstep(jstjobid, jstname, jstdesc, jstkind, jstcode, server_id, database_name) VALUES (job_id, 'Probe log table cleanup','This job step runs periodically to purge old data from the probe log table.', 's',
        'SELECT pem.purge_probe_log()', serverid, 'pem');
    END IF;

    -- Check if the job schedule already exists.
    SELECT jscname INTO name FROM pem.schedule WHERE jscname = 'Probe log table cleanup' AND jscjobid = job_id;

    IF (NOT FOUND) THEN
        -- Create data purging schedule.
        INSERT INTO pem.schedule(jscjobid, jscname, jscdesc, jscminutes, jschours, jscweekdays, jscmonthdays, jscmonths) VALUES(job_id, 'Probe log table cleanup', 'This job schedule runs periodically to purge old data from the probe log table.', '{t,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f}', '{f,f,t,f,f,f,f,f,f,f,f,f,f,f,t,f,f,f,f,f,f,f,f,f}','{t,t,t,t,t,t,t}', '{t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t}', '{t,t,t,t,t,t,t,t,t,t,t,t}');
    END IF;

    -- Check if the job already exists.
    SELECT jobid INTO job_id FROM pem.job WHERE jobname = 'SMTP spool table cleanup' AND agent_id = agentid;

    IF (NOT FOUND) THEN
        -- Create data purging job.
        INSERT INTO pem.job(jobname, jobdesc, agent_id) VALUES('SMTP spool table cleanup', 'This job runs periodically to purge old data from the smtp spool table.', agentid) RETURNING jobid INTO job_id;
    END IF;

    -- Check if the job step already exists.
    SELECT jstname INTO name FROM pem.jobstep WHERE jstname = 'SMTP spool table cleanup' AND jstjobid = job_id;

    IF (NOT FOUND) THEN
        -- Create data purging step.
        INSERT INTO pem.jobstep(jstjobid, jstname, jstdesc, jstkind, jstcode, server_id, database_name) VALUES (job_id, 'SMTP spool table cleanup','This job step runs periodically to purge old data from the smtp spool table.', 's',
        'SELECT pem.purge_smtp_spool()', serverid, 'pem');
    END IF;

    -- Check if the job schedule already exists.
    SELECT jscname INTO name FROM pem.schedule WHERE jscname = 'SMTP spool table cleanup' AND jscjobid = job_id;

    IF (NOT FOUND) THEN
        -- Create data purging schedule.
        INSERT INTO pem.schedule(jscjobid, jscname, jscdesc, jscminutes, jschours, jscweekdays, jscmonthdays, jscmonths) VALUES(job_id, 'SMTP spool table cleanup', 'This job schedule runs periodically to purge old data from the smtp spool table.', '{t,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f}', '{f,f,f,t,f,f,f,f,f,f,f,f,f,f,f,t,f,f,f,f,f,f,f,f}','{t,t,t,t,t,t,t}', '{t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t}', '{t,t,t,t,t,t,t,t,t,t,t,t}');
    END IF;

    -- Check if the job already exists.
    SELECT jobid INTO job_id FROM pem.job WHERE jobname = 'SNMP spool table cleanup' AND agent_id = agentid;

    IF (NOT FOUND) THEN
        -- Create data purging job.
        INSERT INTO pem.job(jobname, jobdesc, agent_id) VALUES('SNMP spool table cleanup', 'This job runs periodically to purge old data from the snmp spool table.', agentid) RETURNING jobid INTO job_id;
    END IF;

    -- Check if the job step already exists.
    SELECT jstname INTO name FROM pem.jobstep WHERE jstname = 'SNMP spool table cleanup' AND jstjobid = job_id;

    IF (NOT FOUND) THEN
        -- Create data purging step.
        INSERT INTO pem.jobstep(jstjobid, jstname, jstdesc, jstkind, jstcode, server_id, database_name) VALUES (job_id, 'SNMP spool table cleanup','This job step runs periodically to purge old data from the snmp spool table.', 's',
        'SELECT pem.purge_snmp_spool()', serverid, 'pem');
    END IF;

    -- Check if the job schedule already exists.
    SELECT jscname INTO name FROM pem.schedule WHERE jscname = 'SNMP spool table cleanup' AND jscjobid = job_id;

    IF (NOT FOUND) THEN
        -- Create data purging schedule.
        INSERT INTO pem.schedule(jscjobid, jscname, jscdesc, jscminutes, jschours, jscweekdays, jscmonthdays, jscmonths) VALUES(job_id, 'SNMP spool table cleanup', 'This job schedule runs periodically to purge old data from the snmp spool table.', '{t,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f}', '{f,f,f,f,t,f,f,f,f,f,f,f,f,f,f,f,t,f,f,f,f,f,f,f}','{t,t,t,t,t,t,t}', '{t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t}', '{t,t,t,t,t,t,t,t,t,t,t,t}');
    END IF;

    -- Check if the job already exists.
    SELECT jobid INTO job_id FROM pem.job WHERE jobname = 'Alert history table cleanup' AND agent_id = agentid;

    IF (NOT FOUND) THEN
        -- Create data purging job.
        INSERT INTO pem.job(jobname, jobdesc, agent_id) VALUES('Alert history table cleanup', 'This job runs periodically to purge old data from the alert history table.', agentid) RETURNING jobid INTO job_id;
    END IF;

    -- Check if the job step already exists.
    SELECT jstname INTO name FROM pem.jobstep WHERE jstname = 'Alert history table cleanup' AND jstjobid = job_id;

    IF (NOT FOUND) THEN
        -- Create data purging step.
        INSERT INTO pem.jobstep(jstjobid, jstname, jstdesc, jstkind, jstcode, server_id, database_name) VALUES (job_id, 'Alert history table cleanup','This job step runs periodically to purge old data from the alert history table.', 's',
        'SELECT pem.purge_alert_history()', serverid, 'pem');
    END IF;

    -- Check if the job schedule already exists.
    SELECT jscname INTO name FROM pem.schedule WHERE jscname = 'Alert history table cleanup' AND jscjobid = job_id;

    IF (NOT FOUND) THEN
        -- Create data purging schedule.
        INSERT INTO pem.schedule(jscjobid, jscname, jscdesc, jscminutes, jschours, jscweekdays, jscmonthdays, jscmonths) VALUES(job_id, 'Alert history table cleanup', 'This job schedule runs periodically to purge old data from the alert history table.', '{t,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f}', '{f,f,f,f,f,t,f,f,f,f,f,f,f,f,f,f,f,t,f,f,f,f,f,f}','{t,t,t,t,t,t,t}', '{t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t}', '{t,t,t,t,t,t,t,t,t,t,t,t}');
    END IF;

    -- Check if the job already exists.
    SELECT jobid INTO job_id FROM pem.job WHERE jobname = 'Job log table cleanup' AND agent_id = agentid;

    IF (NOT FOUND) THEN
        -- Create data purging job.
        INSERT INTO pem.job(jobname, jobdesc, agent_id) VALUES('Job log table cleanup', 'This job runs periodically to purge old data from the job log table.', agentid) RETURNING jobid INTO job_id;
    END IF;

    -- Check if the job step already exists.
    SELECT jstname INTO name FROM pem.jobstep WHERE jstname = 'Job log table cleanup' AND jstjobid = job_id;

    IF (NOT FOUND) THEN
        -- Create data purging step.
        INSERT INTO pem.jobstep(jstjobid, jstname, jstdesc, jstkind, jstcode, server_id, database_name) VALUES (job_id, 'Job log table cleanup','This job step runs periodically to purge old data from the job log table.', 's',
        'SELECT pem.purge_job_log()', serverid, 'pem');
    END IF;

    -- Check if the job schedule already exists.
    SELECT jscname INTO name FROM pem.schedule WHERE jscname = 'Job log table cleanup' AND jscjobid = job_id;

    IF (NOT FOUND) THEN
        -- Create data purging schedule.
        INSERT INTO pem.schedule(jscjobid, jscname, jscdesc, jscminutes, jschours, jscweekdays, jscmonthdays, jscmonths) VALUES(job_id, 'Job log table cleanup', 'This job schedule runs periodically to purge old data from the job log table.', '{t,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f}', '{f,f,f,f,f,f,t,f,f,f,f,f,f,f,f,f,f,f,t,f,f,f,f,f}','{t,t,t,t,t,t,t}', '{t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t}', '{t,t,t,t,t,t,t,t,t,t,t,t}');
    END IF;
END $$;

COMMIT TRANSACTION;

-- Adding these statements in a separate transaction block
-- to avoid the situation where a user upgrades from PEM 3.0.1
-- to PEM 4.0.0, because in that case these inserts will already
-- be there and will cause primary key error and aborts the main
-- transaction block. If this transaction blocks fails then it's okay.
BEGIN TRANSACTION;

INSERT INTO pem.config VALUES ('dash_io_index_objectio_rows', 25, 'rows', 'integer');
INSERT INTO pem.config VALUES ('dash_io_index_objectio_timeout', 60, 'seconds', 'integer');

-- Done!
COMMIT TRANSACTION;

