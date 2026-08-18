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

-- Upgrade script for v4.0.0a1 to v4.0.0b1

BEGIN TRANSACTION;

-- Update the schema version
CREATE OR REPLACE FUNCTION pem.schema_version()
  RETURNS integer AS
'SELECT 201306041::integer;'
  LANGUAGE 'sql' IMMUTABLE;
COMMENT ON FUNCTION pem.schema_version() IS 'Returns the version number of the PEM schema';

-- Add the requiredpkglauncher to pem.package_installation.
ALTER TABLE pem.package_installation ADD COLUMN requiredpkglauncher boolean NOT NULL DEFAULT false;

-- Fixed RM 30751
UPDATE pem.alert_template SET sql = 'SELECT COUNT(ip.pkg_id)
FROM
    pemdata.package_catalog pc LEFT JOIN pemdata.installed_packages ip
    ON (pc.pkg_id = ip.pkg_id) AND (pc.platform = ip.platform)
WHERE
   ip.agent_id = ${agent_id} AND
   pc.pkg_id = ip.pkg_id AND
   pc.platform = ip.platform AND
   pc.version != ip.version AND
   pc.manifesturl IS NOT NULL'
WHERE display_name = 'Package version mismatch';

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
					pc.version != ip.version AND
					pc.manifesturl IS NOT NULL)
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
				message = message || COALESCE(write_message_streaming_repl, '')::text ;
			END IF;

			-- Special handling for 'Flush lag Alert' alert
			IF (template_name = 'Number of standby servers lag behind the master by flush location') THEN
				message = message || COALESCE(flush_message_streaming_repl, '')::text ;
			END IF;

			-- Special handling for 'Replay lag Alert' alert
			IF (template_name = 'Number of standby servers lag behind the master by replay location') THEN
				message = message || COALESCE(replay_message_streaming_repl, '')::text ;
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
				varbinding_value = varbinding_value || '|' || COALESCE(upgrade_pkg_list, '')::text || ' ' || COALESCE(obsolete_pkg_list, '')::text;
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
				message = message || COALESCE(write_message_streaming_repl, '')::text ;
			END IF;

			IF (template_name = 'Number of standby servers lag behind the master by flush location') THEN
				message = message || COALESCE(flush_message_streaming_repl, '')::text ;
			END IF;

			IF (template_name = 'Number of standby servers lag behind the master by replay location') THEN
				message = message || COALESCE(replay_message_streaming_repl, '')::text ;
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
				varbinding_value = varbinding_value || '|' || COALESCE(upgrade_pkg_list, '')::text || ' ' || COALESCE(obsolete_pkg_list, '')::text;
			END IF;

			-- Send SNMP traps
			send_trap_val = pem.send_snmptrap(trap_oid, enterprise_oid, trap_version, varbinding_oid, varbinding_value);
		END IF;
	END IF;

	RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DO $$
DECLARE
	probe_for_92_exists boolean := false;
BEGIN
	EXECUTE 'SELECT COUNT(server_version_id) = 1 FROM pem.probe_server_version WHERE probe_id = (SELECT id FROM pem.probe WHERE internal_name = ''oc_schema'') AND server_version_id = 10902' INTO probe_for_92_exists;
	IF NOT probe_for_92_exists THEN
		-- Updating oc_schema probe for PG 9.2
		INSERT INTO pem.probe_server_version (probe_id, server_version_id, probe_code)
		SELECT (SELECT id FROM pem.probe WHERE internal_name = 'oc_schema'), v.version, NULL FROM (VALUES (10902)) v(version);
	END IF;

	EXECUTE 'SELECT COUNT(server_version_id) = 1 FROM pem.probe_server_version WHERE probe_id = (SELECT id FROM pem.probe WHERE internal_name = ''oc_schema'') AND server_version_id = 20902' INTO probe_for_92_exists;
	IF NOT probe_for_92_exists THEN
		-- Updating oc_schema probe for AS 9.2
		INSERT INTO pem.probe_server_version (probe_id, server_version_id, probe_code)
		SELECT (SELECT id FROM pem.probe WHERE internal_name = 'oc_schema'), v.version,
			E'SELECT nspname AS schema_name FROM pg_catalog.pg_namespace WHERE (nspname = ''pg_catalog'' OR nspname NOT LIKE E''pg\\\\_%'') AND nspparent = 0'
		FROM (VALUES (20902)) v(version);
	END IF;

	EXECUTE 'SELECT COUNT(server_version_id) = 1 FROM pem.probe_server_version WHERE probe_id = (SELECT id FROM pem.probe WHERE internal_name = ''oc_function'') AND server_version_id = 10902' INTO probe_for_92_exists;
	IF NOT probe_for_92_exists THEN
		-- Updating oc_function probe for PG 9.2
		INSERT INTO pem.probe_server_version (probe_id, server_version_id, probe_code)
		SELECT (SELECT id FROM pem.probe WHERE internal_name = 'oc_function'), v.version, NULL
		FROM (VALUES (10902)) v(version);
	END IF;

	EXECUTE 'SELECT COUNT(server_version_id) = 1 FROM pem.probe_server_version WHERE probe_id = (SELECT id FROM pem.probe WHERE internal_name = ''oc_function'') AND server_version_id = 20902' INTO probe_for_92_exists;
	IF NOT probe_for_92_exists THEN
		-- Updating oc_function probe for AS 9.2
		INSERT INTO pem.probe_server_version (probe_id, server_version_id, probe_code)
		SELECT (SELECT id FROM pem.probe WHERE internal_name = 'oc_function'), v.version, $sql$
SELECT	'' AS package_name, f.proname AS function_name, f.protype AS function_type,
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
AND		s.nspname = %{schema_name}$sql$
		FROM (VALUES (20902)) v(version);
	END IF;

	EXECUTE 'SELECT COUNT(server_version_id) = 1 FROM pem.probe_server_version WHERE probe_id = (SELECT id FROM pem.probe WHERE internal_name = ''table_statistics'') AND server_version_id = 10902' INTO probe_for_92_exists;
	IF NOT probe_for_92_exists THEN
		-- Updating table_statistics probe for PG 9.2 and AS 9.2
		INSERT INTO pem.probe_server_version (probe_id, server_version_id, probe_code)
		SELECT (SELECT id FROM pem.probe WHERE internal_name = 'table_statistics'), v.version, NULL
		FROM (VALUES (10902), (20902)) v(version);
	END IF;

	EXECUTE 'SELECT COUNT(server_version_id) = 1 FROM pem.probe_server_version WHERE probe_id = (SELECT id FROM pem.probe WHERE internal_name = ''function_statistics'') AND server_version_id = 10902' INTO probe_for_92_exists;
	IF NOT probe_for_92_exists THEN
		-- Updating function_statistics probe for PG 9.2
		INSERT INTO pem.probe_server_version (probe_id, server_version_id, probe_code)
		SELECT (SELECT id FROM pem.probe WHERE internal_name = 'function_statistics'), v.version, NULL
		FROM (VALUES (10902)) v(version);
	END IF;

	EXECUTE 'SELECT COUNT(server_version_id) = 1 FROM pem.probe_server_version WHERE probe_id = (SELECT id FROM pem.probe WHERE internal_name = ''function_statistics'') AND server_version_id = 20902' INTO probe_for_92_exists;
	IF NOT probe_for_92_exists THEN
		-- Updating function_statistics probe for AS 9.2
		INSERT INTO pem.probe_server_version (probe_id, server_version_id, probe_code)
		SELECT (SELECT id FROM pem.probe WHERE internal_name = 'function_statistics'), v.version, $sql$
SELECT	s.nspname AS schema_name, '' AS package_name, f.proname AS function_name,
		f.protype AS function_type, f.prorettype::regtype AS return_type,
		f.proargtypes::regtype[] AS arg_types,
		fs.calls AS call_count, fs.total_time, fs.self_time
FROM	pg_catalog.pg_namespace AS s		-- schema
JOIN	pg_catalog.pg_proc AS f			-- function
ON		f.pronamespace = s.oid
JOIN	pg_catalog.pg_stat_user_functions AS fs	-- Func. stats
ON		fs.funcid = f.oid
WHERE	s.nspparent = 0 -- select schema that is not a child of some other schema
UNION ALL
SELECT	s.nspname AS schema_name, p.nspname AS package_name, f.proname AS function_name,
		f.protype AS function_type, f.prorettype::regtype AS return_type,
		f.proargtypes::regtype[] AS arg_types,
		fs.calls AS call_count, fs.total_time, fs.self_time
FROM	pg_catalog.pg_namespace AS s		-- schema
JOIN	pg_catalog.pg_namespace AS p		-- package
ON		p.nspparent = s.oid
JOIN	pg_catalog.pg_proc AS f			-- function
ON		f.pronamespace = p.oid
JOIN	pg_catalog.pg_stat_user_functions AS fs	-- Func. stats
ON		fs.funcid = f.oid
WHERE	p.nspparent <> 0 -- select schema that _is_ a child of some other schema
$sql$
		FROM (VALUES (20902)) v(version);
	END IF;

	EXECUTE 'SELECT COUNT(server_version_id) = 1 FROM pem.probe_server_version WHERE probe_id = (SELECT id FROM pem.probe WHERE internal_name = ''table_size'') AND server_version_id = 10902' INTO probe_for_92_exists;
	IF NOT probe_for_92_exists THEN
		-- Updating table_size probe for PG 9.2 and AS 9.2
		INSERT INTO pem.probe_server_version (probe_id, server_version_id, probe_code)
		SELECT (SELECT id FROM pem.probe WHERE internal_name = 'table_size'), v.version,
			'SELECT n.nspname AS schema_name, c.relname AS table_name, pg_relation_size(c.oid) / 1048576 AS table_size_mb, pg_indexes_size(c.oid) / 1048576 AS size_of_indexes_mb, pg_total_relation_size(c.oid) / 1048576 AS total_table_size_mb FROM pg_class c, pg_namespace n WHERE c.relnamespace = n.oid AND c.relkind = ''r'''
		FROM (VALUES (10902), (20902)) v(version);
	END IF;

	EXECUTE 'SELECT COUNT(server_version_id) = 1 FROM pem.probe_server_version WHERE probe_id = (SELECT id FROM pem.probe WHERE internal_name = ''background_writer_statistics'') AND server_version_id = 10902' INTO probe_for_92_exists;
	IF NOT probe_for_92_exists THEN
		-- Updating background_writer_statistics probe for PG 9.2 and AS 9.2
		INSERT INTO pem.probe_server_version (probe_id, server_version_id, probe_code)
		SELECT (SELECT id FROM pem.probe WHERE internal_name = 'background_writer_statistics'), v.version, NULL
		FROM (VALUES (10902), (20902)) v(version);
	END IF;

	EXECUTE 'SELECT COUNT(server_version_id) = 1 FROM pem.probe_server_version WHERE probe_id = (SELECT id FROM pem.probe WHERE internal_name = ''system_waits'') AND server_version_id = 20902' INTO probe_for_92_exists;
	IF NOT probe_for_92_exists THEN
		-- Updating system_waits probe for AS 9.2
		INSERT INTO pem.probe_server_version (probe_id, server_version_id, probe_code)
		SELECT (SELECT id FROM pem.probe WHERE internal_name = 'system_waits'), v.version, NULL
		FROM (VALUES (20902)) v(version);
	END IF;

	EXECUTE 'SELECT COUNT(server_version_id) = 1 FROM pem.probe_server_version WHERE probe_id = (SELECT id FROM pem.probe WHERE internal_name = ''audit_configuration'') AND server_version_id = 20902' INTO probe_for_92_exists;
	IF NOT probe_for_92_exists THEN
		-- Updating audit_configuration probe for AS 9.2
		INSERT INTO pem.probe_server_version (probe_id, server_version_id, probe_code)
		SELECT (SELECT id FROM pem.probe WHERE internal_name = 'audit_configuration'), v.version, NULL
		FROM (VALUES (20902)) v(version);
	END IF;
END;
$$;

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
	conditional_clause text := NULL;
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

	EXECUTE 'SELECT heartbeat_interval * ''1 second''::interval FROM pem.agent where id = $1::int4'
	INTO heartbeat_freq USING agentid;

	EXECUTE 'SELECT last_heartbeat FROM pem.agent_heartbeat WHERE agent_id = $1::int4'
	INTO last_heartbeat USING agentid;

	IF last_heartbeat IS NULL THEN
		tmp_end_time = end_time;
	ELSE
		EXECUTE '
SELECT
	CASE WHEN last_heartbeat + $1::interval < $2::timestamptz THEN last_heartbeat
	ELSE $2::timestamptz END
FROM pem.agent_heartbeat WHERE agent_id = $3::int4'
			INTO tmp_end_time USING heartbeat_freq, end_time, agentid;
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
		IF conditional_clause IS NOT NULL AND conditional_clause <> '' THEN
			conditional_clause := conditional_clause || ' AND ';
		ELSE
			conditional_clause := '';
		END IF;
		conditional_clause := conditional_clause || pg_catalog.quote_ident(probe_table) || '.database_name = ANY( ' || pg_catalog.quote_literal(restricted_dbs::text) || ')';
	END IF;

	-- Get the time when probe started collecting the data
	raw_query := 'SELECT COALESCE(MAX(recorded_time), NULL::timestamptz) AS recorded_time FROM pemhistory.'
		|| pg_catalog.quote_ident(probe_table)
		|| ' WHERE recorded_time <= $1::timestamptz';
	IF conditional_clause IS NOT NULL AND conditional_clause <> '' THEN
		raw_query := raw_query || ' AND ' || conditional_clause;
	END IF;
	EXECUTE raw_query INTO adjusted_start_time USING start_time;

	-- Fetch the data.
	raw_query := '';
	IF is_capacity_manager THEN
		raw_query = 'SELECT recorded_time, ';
		IF adjusted_start_time IS NULL THEN
			raw_query := raw_query || 'COALESCE( '
				|| pg_catalog.quote_ident(probe_data_column)
				|| '::numeric, 0::numeric) AS metric_value FROM pemhistory.'
				|| pg_catalog.quote_ident(probe_table)
				|| ' WHERE recorded_time >= '
				|| pg_catalog.quote_literal(start_time::text)
				|| '::timestamptz';
		ELSE
			raw_query := raw_query || pg_catalog.quote_ident(probe_data_column)
				|| '::numeric AS metric_value FROM pemhistory.'
				|| pg_catalog.quote_ident(probe_table)
				|| ' WHERE recorded_time >= '
				|| pg_catalog.quote_literal(adjusted_start_time::text)
				|| '::timestamptz';
		END IF;
		raw_query := raw_query || ' AND recorded_time <= '
			|| pg_catalog.quote_literal(tmp_end_time::text) || '::timestamptz';
		IF conditional_clause IS NOT NULL AND trim(conditional_clause) <> '' THEN
			raw_query := raw_query || ' AND ' || conditional_clause;
		END IF;
		raw_query := raw_query
			|| ' ORDER BY recorded_time';
	ELSE -- Queries for landing pages
		-- SUM(probe_data_column) has been used to aggregate the values. For
		-- example on server page if nummbackends are to be
		-- found then SUM() will be taken after applying group by on
		-- server_id for all databases.
		-- truncate has been used in group by clause because
		-- sometimes data collection has time difference in miliseconds
		raw_query := 'SELECT MAX(recorded_time) AS recorded_time, SUM(';
		IF adjusted_start_time IS NULL THEN
			raw_query := raw_query || 'COALESCE( '
				|| pg_catalog.quote_ident(probe_data_column)
				|| '::numeric, 0::numeric)) AS metric_value FROM pemhistory.'
				|| pg_catalog.quote_ident(probe_table)
				|| ' WHERE recorded_time >= '
				|| pg_catalog.quote_literal(start_time::text) || '::timestamptz';
		ELSE
			raw_query := raw_query || pg_catalog.quote_ident(probe_data_column)
				|| ')::numeric AS metric_value FROM pemhistory.'
				|| pg_catalog.quote_ident(probe_table)
				|| ' WHERE recorded_time >= '
				|| pg_catalog.quote_literal(adjusted_start_time::text) || '::timestamptz';
		END IF;

		raw_query := raw_query
			|| ' AND recorded_time <= '
			|| pg_catalog.quote_literal(tmp_end_time::text) || '::timestamptz';

		IF conditional_clause IS NOT NULL AND trim(conditional_clause) <> '' THEN
			raw_query := raw_query || ' AND ' || conditional_clause;
		END IF;
		IF groupby_clause IS NOT NULL AND trim(groupby_clause) <> '' THEN
			raw_query := raw_query || ' GROUP BY date_trunc(''second'', recorded_time), ' || groupby_clause || ' ORDER BY recorded_time';
		END IF;
	END IF;

	OPEN raw_data FOR EXECUTE raw_query;

	FETCH raw_data INTO current_record;
	FETCH raw_data INTO next_record;


	new_query
		= 'SELECT ts AS recorded_time, NULL::numeric AS metric_value FROM generate_series($1::timestamptz, $2::timestamptz, $3::interval) ts';

	FOR new_record IN EXECUTE new_query USING start_time, tmp_end_time, time_interval
	LOOP
		IF (current_record.recorded_time IS NOT NULL
			AND current_record.recorded_time <= new_record.recorded_time) THEN
			IF (next_record IS NULL AND
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
			= 'SELECT ts AS recorded_time, 0::numeric AS metric_value FROM generate_series($1::timestamptz, $2::timestamptz, $3::interval) ts';

		--OPEN new_data FOR new_query;
		FOR new_record IN EXECUTE new_query USING tmp_end_time, end_time, time_interval
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
	OPEN curs FOR EXECUTE  'SELECT metric_time, recorded_value::numeric FROM
		pem.data_reconstruction($1::text, $2::text, $3::timestamptz, $4::timestamptz,
		$5::interval, $6::varchar[], $7::varchar[], $8::integer, $9::boolean,
		$10::varchar[])'
	USING probe_table, probe_data_column, start_time, end_time, time_interval,
		probe_target_key_list, probe_target_value_list, agentid, is_capacity_manager,
		restricted_dbs;

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

	RETURN QUERY EXECUTE 'SELECT agg_time AS aggregated_time, agg_value AS
		aggregated_value FROM pem.data_aggregation($1::text, $2::timestamptz[],
		$3::numeric[], $4::integer, $5::integer)'
	USING aggregate_function, data_timestamp, data_value, count, required_points;
END
$$ LANGUAGE plpgsql;

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

    -- Check if the job already exists (for purging deleted charts)
    SELECT jobid INTO job_id FROM pem.job WHERE jobname = 'Job purge the deleted charts' AND agent_id = agentid;

    IF (NOT FOUND) THEN
        -- Create data purging job.
        INSERT INTO pem.job(jobname, jobdesc, agent_id) VALUES('Job purge the deleted charts', 'This job runs periodically to purge the deleted charts.', agentid) RETURNING jobid INTO job_id;
    END IF;

    -- Check if the job step already exists.
    SELECT jstname INTO name FROM pem.jobstep WHERE jstname = 'Job purge the deleted charts' AND jstjobid = job_id;

    IF (NOT FOUND) THEN
        -- Create data purging step.
        INSERT INTO pem.jobstep(jstjobid, jstname, jstdesc, jstkind, jstcode, server_id, database_name) VALUES (job_id, 'Job purge the deleted charts','This job step runs periodically to purge the deleted charts (we do not clean them up immediately).', 's',
        'SELECT pem.purge_deleted_charts()', serverid, 'pem');
    END IF;

    -- Check if the job schedule already exists.
    SELECT jscname INTO name FROM pem.schedule WHERE jscname = 'Job purge the deleted charts' AND jscjobid = job_id;

    IF (NOT FOUND) THEN
        -- Create data purging schedule.
        INSERT INTO pem.schedule(jscjobid, jscname, jscdesc, jscminutes, jschours, jscweekdays, jscmonthdays, jscmonths) VALUES(job_id, 'Job purge the deleted charts', 'This job schedule runs periodically to purge the deletecd charts.', '{t,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f}', '{f,f,t,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f}','{t,t,t,t,t,t,t}', '{t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t}', '{t,t,t,t,t,t,t,t,t,t,t,t}');
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

    -- Check if the job already exists (for purging deleted charts)
    SELECT jobid INTO job_id FROM pem.job WHERE jobname = 'Job purge the deleted charts' AND agent_id = agentid;

    IF (NOT FOUND) THEN
        -- Create data purging job.
        INSERT INTO pem.job(jobname, jobdesc, agent_id) VALUES('Job purge the deleted charts', 'This job runs periodically to purge the deleted charts.', agentid) RETURNING jobid INTO job_id;
    END IF;

    -- Check if the job step already exists.
    SELECT jstname INTO name FROM pem.jobstep WHERE jstname = 'Job purge the deleted charts' AND jstjobid = job_id;

    IF (NOT FOUND) THEN
        -- Create data purging step.
        INSERT INTO pem.jobstep(jstjobid, jstname, jstdesc, jstkind, jstcode, server_id, database_name) VALUES (job_id, 'Job purge the deleted charts','This job step runs periodically to purge the deleted charts (we do not clean them up immediately).', 's',
        'SELECT pem.purge_deleted_charts()', serverid, 'pem');
    END IF;

    -- Check if the job schedule already exists.
    SELECT jscname INTO name FROM pem.schedule WHERE jscname = 'Job purge the deleted charts' AND jscjobid = job_id;

    IF (NOT FOUND) THEN
        -- Create data purging schedule.
        INSERT INTO pem.schedule(jscjobid, jscname, jscdesc, jscminutes, jschours, jscweekdays, jscmonthdays, jscmonths) VALUES(job_id, 'Job purge the deleted charts', 'This job schedule runs periodically to purge the deletecd charts.', '{t,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f}', '{f,f,t,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f}','{t,t,t,t,t,t,t}', '{t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t}', '{t,t,t,t,t,t,t,t,t,t,t,t}');
    END IF;
END;
$BODY$ LANGUAGE plpgsql;

CREATE SEQUENCE pem.chart_catagory_id_seq START WITH 257;
CREATE TABLE pem.chart_catagory
(
	id    integer           NOT NULL DEFAULT nextval('pem.chart_catagory_id_seq'::regclass),
	name  text              NOT NULL,
	descp text              NOT NULL,
	owner oid               NOT NULL,

	CONSTRAINT pem_qry_chart_pk PRIMARY KEY (id)
);

-- Query Function / PHP Function, which generates the data for the charts
CREATE SEQUENCE pem.chart_func_id_seq START WITH 257;
CREATE TABLE pem.chart_func
(
	id        integer           NOT NULL DEFAULT nextval('pem.chart_func_id_seq'::regclass),
	type      character(1)      NOT NULL,
	func      character varying NOT NULL,
	r_sys_obj boolean           NOT NULL DEFAULT true,

	CONSTRAINT pem_chart_func_pk PRIMARY KEY (id),
	CONSTRAINT pem_chart_func_type_constraint CHECK (type IN ('Q', 'P', 'F'))
);

COMMENT ON TABLE pem.chart_func IS 'This contains the information to save a plpgsql or PHP function required generating the data for the charts';
COMMENT ON COLUMN pem.chart_func.type IS 'This defines the type of the chart function:
Q - Query
P - PHP
F - FUNCTION

Query must return particular format (depending on the chart type):
Bar-chart : expects set of data [format: pos(int), label(text), value(numeric)]
Pie-chart : expects set of data [format: label(text), value(numeric)]
table-chart/line-chart : expects to return a chart-json object
data-chart: Should return set of text[]
histroy-chart: Should return set of data [format: recorded_time(timestamptz), values(text[])]';

COMMENT ON COLUMN pem.chart_func.func IS 'This keeps the name of the plpgsql/PHP function';
COMMENT ON COLUMN pem.chart_func.r_sys_obj Is 'This let us know this chart requires show_system_object variable or not';

-- First 256 charts are reserved for the system level charts
CREATE SEQUENCE pem.chart_id_seq START WITH 257;

CREATE TABLE pem.chart
(
	-- Unique id for a chart
	id      integer          NOT NULL DEFAULT nextval('pem.chart_id_seq'::regclass),

	-- catagory
	cid     integer          NOT NULL,

	-- Type of the Chart
	-- We do support the following type of charts:
	--   TE : TEXT Chart
	--   TB : TABLE Chart
	--   B  : BAR Chart
	--   P  : PIE Chart
	--   L  : LINE Chart
	type    char(2)        NOT NULL,

	-- Some charts can have text messages along with them
	summary  integer,

	-- Level at which this chart can be applied
	---------------------------------------------
	-- 50  : Global level chart
	-- 100 : Agent / Operating system level chart
	-- 200 : Server level chart
	-- 300 : Database level chart
	-- 400 : Schema level chart
	level   integer[]          NOT NULL,

	-- Name (title - Display Name)
	name   character varying NOT NULL,

	-- Description
	descp  character varying DEFAULT NULL,

	-- Owner of the chart
	--  '0' suggest - it is a system defined chart
	--  Other suggests the owner of the chart
	owner   oid              NOT NULL,

	-- Shared with which users/roles
	-- 'NULL' suggests with All
	shared  oid[],

	-- Reference counts, on how many times it has been used on different
	-- dashboards
	ref_cnt smallint         NOT NULL,

	-- Reference to the chart_func.id (if it does not support metrices)
	fid     integer,

	-- Is this chart marked for deletion
	deleted boolean          NOT NULL DEFAULT false,

	-- At what time, it was maked for deletion
	deleted_time timestamptz DEFAULT NULL,

	-- Reload in how many seconds
	reload  integer          NOT NULL DEFAULT 30000,

	-- Metric Headers
	labels character varying[],

	-- required parameters in specific order
	params character varying[] DEFAULT NULL,

	CONSTRAINT pem_chart_pk PRIMARY KEY (id),
	CONSTRAINT pem_chart_fk_fid FOREIGN KEY (fid) REFERENCES pem.chart_func(id)
		MATCH SIMPLE ON UPDATE CASCADE ON DELETE CASCADE INITIALLY DEFERRED,
	CONSTRAINT pem_chart_fk_cid FOREIGN KEY (cid) REFERENCES pem.chart_catagory(id)
		MATCH SIMPLE ON UPDATE CASCADE ON DELETE CASCADE INITIALLY DEFERRED,
	CONSTRAINT pem_chart_fk_summary FOREIGN KEY (summary) REFERENCES pem.chart(id)
		MATCH SIMPLE ON UPDATE CASCADE ON DELETE CASCADE INITIALLY DEFERRED,
	CONSTRAINT pem_chart_type_constraint CHECK (type IN ('TE', 'TB', 'B', 'P', 'L')),
	CONSTRAINT pem_chart_level_constraint CHECK (level <@ ARRAY[50, 100, 200, 300, 400])
);

COMMENT ON TABLE  pem.chart IS '
* Helps to store the chart information found on dashboards in the pem-server database
* We do support the following type of charts:
  TE : TEXT Chart (Generally a information)
  TB : TABLE Chart
  B  : BAR Chart
  P  : PIE Chart
  L  : LINE Chart
* Each chart has one defined level
  50  - Global level chart
  100 - Agent / Operating system level chart
  200 - Srver level chart
  300 - Database level chart
  400 - Schema level chart
* A system defined chart can not be removed any day
* "owner" reveals the owner information, "0" suggests a system level chart
* Shared among different users/roles, or set shared to NULL to share it with
  everybody
* Data for the chart can be generated three ways:
  - A PHP function
  - A plpgsql function
  - Metrics
* ref_cnt keeps the count for how many times this has been drawn on different
  dash-boards
* Also defines in how much seconds we need to reload this chart
* Headers are metrices list';

CREATE TABLE pem.bar_chart
(
	cid     integer,
	colors  character varying[],
	yaxis   character varying   NOT NULL,
	type    character DEFAULT 'P',
	is_position_based boolean DEFAULT false, -- Is chart need to show the bars in a specific order like "Alerts status bar chart", which shows the bars in the order like "HIGH", "MEDIUM", "LOW", "None".

	CONSTRAINT pem_bar_chart_pk PRIMARY KEY (cid),
	CONSTRAINT pem_bar_chart_fk_cid FOREIGN KEY (cid) REFERENCES pem.chart(id)
		MATCH SIMPLE ON UPDATE CASCADE ON DELETE CASCADE INITIALLY DEFERRED,
	CONSTRAINT pem_bar_chart_type_check CHECK (type IN ('D', 'P'))
	-- P : PREDEFINED (A QUERY / PHP / SQL FUNCTOIN)
	-- D : DATA METRIC
);
COMMENT ON TABLE pem.bar_chart IS 'This contains the informations to generate the bar charts';

CREATE TABLE pem.pie_chart
(
	cid    integer,
	colors character varying[],
	type   character DEFAULT 'P',
	is_vertical boolean, -- Vertical pie charts like "System Waits By Number Of Waits" ....

	CONSTRAINT pem_pie_chart_pk PRIMARY KEY (cid),
	CONSTRAINT pem_pie_chart_fk_cid FOREIGN KEY (cid) REFERENCES pem.chart(id)
		MATCH SIMPLE ON UPDATE CASCADE ON DELETE CASCADE INITIALLY DEFERRED,
	CONSTRAINT pem_pie_chart_type_check CHECK (type IN ('D', 'P'))
	-- P : PREDEFINED (A QUERY / PHP/ SQL FUNCTOIN)
	-- D : DATA METRIC
);
COMMENT ON TABLE pem.pie_chart IS 'This contains the information to generate the pie charts';

CREATE TABLE pem.tbl_chart
(
	cid  integer,
	type char(1) NOT NULL,

	CONSTRAINT pem_tbl_chart_pk PRIMARY KEY (cid),
	CONSTRAINT pem_tbl_chart_fk_cid FOREIGN KEY (cid) REFERENCES pem.chart(id)
		MATCH SIMPLE ON UPDATE CASCADE ON DELETE CASCADE INITIALLY DEFERRED,
	CONSTRAINT pem_tbl_chart_type_constraint CHECK (type IN ('H', 'D', 'M'))
);

COMMENT ON TABLE pem.tbl_chart IS 'This contains the information to generate the metrices table from the probe data/histroy table';
COMMENT ON COLUMN pem.tbl_chart.type IS 'This defined the table chart type.
D - Table from Data
H - View over History Table
M - Data generated for metrices';

CREATE TABLE pem.data_chart
(
	cid       integer,
	tbl       character varying NOT NULL,
	metrices  character varying[] NOT NULL,

	orderby   character varying[],
	glimit    integer DEFAULT 50,

	r_sys_obj boolean NOT NULL DEFAULT false,

	CONSTRAINT pem_data_chart_pk PRIMARY KEY (cid),
	CONSTRAINT pem_data_chart_fk_cid FOREIGN KEY (cid) REFERENCES pem.chart(id)
		MATCH SIMPLE ON UPDATE CASCADE ON DELETE CASCADE INITIALLY DEFERRED
);

CREATE TABLE pem.history_chart
(
	cid        integer,
	time_span  interval NOT NULL DEFAULT '7 days'::interval,
	tbl        character varying NOT NULL,
	metrices   character varying[] NOT NULL,
	r_sys_obj  boolean NOT NULL DEFAULT false,

	gorderby   character varying[],
	glimit     int2 NOT NULL DEFAULT 0,

	CONSTRAINT pem_history_chart_pk PRIMARY KEY (cid),
	CONSTRAINT pem_history_chart_fk_cid FOREIGN KEY (cid) REFERENCES pem.chart(id)
		MATCH SIMPLE ON UPDATE CASCADE ON DELETE CASCADE INITIALLY DEFERRED
);

CREATE TABLE pem.metrices_chart
(
	cid        integer,
	time_span  interval NOT NULL DEFAULT '14 days'::interval
		CONSTRAINT metrices_chart_time_span_check CHECK (time_span >= '8 hours'::interval AND time_span <= '2 months'::interval),
	max_points integer DEFAULT 100
		CONSTRAINT metrices_chart_max_points_check CHECK (max_points >= 20 AND max_points <= 300),
	agg_int    integer NOT NULL DEFAULT 180
		CONSTRAINT metrices_chart_agg_int_check CHECK (agg_int >= 10 AND agg_int <= 480),

	CONSTRAINT pem_metrices_chart_pk PRIMARY KEY (cid),
	CONSTRAINT pem_metrices_chart_fk_cid FOREIGN KEY (cid) REFERENCES pem.chart(id)
		MATCH SIMPLE ON UPDATE CASCADE ON DELETE CASCADE INITIALLY DEFERRED
);
COMMENT ON COLUMN pem.metrices_chart.agg_int IS 'Aggregation Interval in minutes';

CREATE TYPE pem.chart_metric_param AS (name text, value text);

CREATE TABLE pem.chart_metric
(
	cid       integer,
	mid       integer,
	tbl       character varying   NOT NULL,
	metrices  character varying[] NOT NULL,
	agg_func  text[] NOT NULL,

    -- Generate multiple metrices from one metrices grouped by some other metric
	glimit    integer NOT NULL DEFAULT 8,
	gorderby  text[],

	params    pem.chart_metric_param[] DEFAULT NULL,

	CONSTRAINT pem_chart_metric_pk PRIMARY KEY (cid, mid),
	CONSTRAINT pem_chart_metric_fk_cid FOREIGN KEY (cid) REFERENCES pem.chart(id)
		MATCH SIMPLE ON UPDATE CASCADE ON DELETE CASCADE INITIALLY DEFERRED
);

COMMENT ON TABLE pem.chart_metric IS 'This contains the information to generate the metrices table from the probe histroy table';
COMMENT ON COLUMN pem.chart_metric.agg_func IS 'It defines the aggregated function to be applied over the data to generated maximum number of points.
Available aggregated functions are:
A - AVERAGE
F - FIRST
M - MAX
m - MIN';
COMMENT ON COLUMN pem.chart_metric.params IS 'It contains the specified parameters (typically a name and a value pairs) provided by the user during creation of the chart
i.e. specific server, agent, database, package, function, etc.

Mainly using the Capacity Manager Reports or templates.
Or, also during global level all charts.';

CREATE OR REPLACE FUNCTION pem.check_chart_metrices () RETURNS TRIGGER AS $$
DECLARE
    i        int4;
    metrices character varying[] := NULL;
BEGIN
    IF NEW.metrices IS NOT NULL THEN
        FOR i IN array_lower(NEW.metrices, 1) .. array_upper(NEW.metrices, 1)
        LOOP
            IF NEW.metrices[i] IS NULL OR NEW.metrices[i] = '' THEN
                RAISE EXCEPTION 'Cannot enter null or an emtpy string as an metric';
            END IF;
            -- Save distinct list of metrices
            IF (metrices @> ARRAY[NEW.metrices[i]]) THEN
            ELSE
                metrices := metrices || NEW.metrices[i];
            END IF;
        END LOOP;
        NEW.metrices = metrices;
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER check_chart_metrices
	BEFORE INSERT OR UPDATE ON pem.chart_metric
	FOR EACH ROW
	EXECUTE PROCEDURE pem.check_chart_metrices();

CREATE TABLE pem.line_chart
(
	cid    integer,
	type   char(1) NOT NULL,
	xaxis  character varying,
	yaxis  character varying NOT NULL,
	yaxis2 character varying,
	colors character varying[],

	CONSTRAINT pem_line_chart_pk PRIMARY KEY (cid),
	CONSTRAINT pem_line_chart_fk_cid FOREIGN KEY (cid) REFERENCES pem.chart(id)
		MATCH SIMPLE ON UPDATE CASCADE ON DELETE CASCADE INITIALLY DEFERRED,
	CONSTRAINT pem_line_chart_type_constraint CHECK (type IN ('M'))
);

-------------------------------------------------------------------------------
-- Function:                                                                  -
--    pem.generate_metric_chart_data                                            -
--                                                                            -
-- Parameters:                                                                -
--    cid                 : chart-id                                          -
--    aid                 : agent-id                                          -
--    sid                 : server-id                                         -
--    db                  : database-name                                     -
--    schema              : schema-name                                       -
--    level               : Current dashboard level                           -
--    show_system_objects : Show the system objects                           -
--    is_capacity_manager : Generating data for capacity manager              -
--                                                                            -
-- Returns:                                                                   -
--    idx      : Index (position) of the generated data                       -
--    label    : Custom label if generated                                    -
--    agg_time : Aggregated time for generated data                           -
--    agg_val  : Calculated the aggregated value at that point                -
--                                                                            -
-- Purpose:                                                                   -
--    This will generate the aggregated values for the metrices for the       -
--    line/table charts                                                       -
--                                                                            -
-------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION pem.generate_metric_chart_data(
	cid integer, aid integer, sid integer, db text, schema text,
	level integer, show_system_objects boolean, is_capacity_manager boolean=false)
RETURNS TABLE(idx int2, label text, agg_time timestamptz, agg_val numeric)
AS $$
DECLARE
	chart_exists        boolean := false;
	start_time          timestamptz := NULL;
	end_time            timestamptz := NULL;
	max_points          integer;
	curs                refcursor;
	mcurs               refcursor;
	gcurs               refcursor;
	metric              pem.chart_metric%ROWTYPE;
	chart               pem.chart%ROWTYPE;
	probe_target_type   integer;
	probe_applies_to_id integer;
	probe_keys          text[];
	probe_key_vals      text[];
	metric_restrict_dbs text[];
	restricted_dbs      text[];
	restricted_schemas  text[];
	pos                 integer := 0;
	query               text;
	tmp_str             text;
	params              text[];
	vals                text[];
	agg_int             integer;
	mt_idx              integer := 0;
BEGIN
	-- Check if the data for the chart exists in the pem.metrices_chart
	EXECUTE 'SELECT CASE WHEN count(*) > 0 THEN true ELSE false END FROM pem.metrices_chart WHERE cid = $1::int4'
	INTO chart_exists USING cid;

	IF NOT chart_exists OR chart_exists IS NULL THEN
		RAISE EXCEPTION '101';
	END IF;

	-- Fetch the start time, end time, maximum points & aggregation intervals
	EXECUTE 'SELECT now() -  time_span, now(), max_points, agg_int FROM pem.metrices_chart WHERE cid = $1::int4'
	INTO start_time, end_time, max_points, agg_int USING cid;

	-- Couldn't fetch the time_span/max_points from the pem.metrices_chart table
	IF start_time IS NULL THEN
		RAISE EXCEPTION '102';
	END IF;

	CASE
	WHEN level = 100 THEN
		-- On agent level dash, agent-id must exists
		IF aid IS NULL OR aid <= 0 THEN
			RAISE EXCEPTION '103';
		END IF;
	WHEN level >= 200 THEN
		-- On server level dash, server-id must exists
		IF sid IS NULL OR sid <= 0 THEN
			RAISE EXCEPTION '104';
		END IF;

		-- Fetch agent-id, if not provided
		IF aid IS NULL OR aid <= 0 THEN
			aid := NULL;

			EXECUTE 'SELECT agent_id FROM pem.agent_server_binding WHERE server_id = $1::int4' INTO aid USING sid;

			IF aid IS NULL THEN
				RAISE EXCEPTION '105';
			END IF;
		END IF;

		-- Fetch the restricted databases information (only for server level charts)
		IF level = 200 THEN
			EXECUTE '
SELECT
    pem.db_escaped_string_to_array(COALESCE(o.database_restriction, oa.database_restriction))
FROM
    pem.server s
    LEFT OUTER JOIN pg_catalog.pg_roles owner ON (owner.oid = s.owner)
    LEFT OUTER JOIN pem.server_option o ON (s.id = o.server_id AND o.pem_user = current_user)
    LEFT OUTER JOIN pem.server_option oa
        ON (o.id IS NULL AND s.id = oa.server_id AND
            (owner.rolname = oa.pem_user OR (owner.rolname IS NULL AND oa.pem_user IS NULL)))
WHERE
    s.id = $1::int4' INTO restricted_dbs USING sid;
		END IF;

		IF level >= 300 THEN
			-- database_name is required for any charts lower than server
			-- level
			IF db IS NULL OR trim(db) = '' THEN
				RAISE EXCEPTION '106';
			END IF;

			-- Fetch the restricted schema information (for database level chats)
			IF level = 300 THEN
				EXECUTE '
SELECT
    COALESCE(o.schema_restriction, oa.schema_restriction)
FROM
    pem.server s
    LEFT OUTER JOIN pg_catalog.pg_roles owner ON (owner.oid = s.owner)
    LEFT OUTER JOIN pem.database_option o ON (s.id = o.server_id AND o.pem_user = current_user AND o.database = $2::text)
    LEFT OUTER JOIN pem.database_option oa
        ON (o.id IS NULL AND s.id = oa.server_id AND oa.database = $2::text AND
            (owner.rolname = oa.pem_user OR (owner.rolname IS NULL AND oa.pem_user IS NULL)))
WHERE
    s.id = $1::int4' INTO restricted_schemas USING sid, db;
			END IF;
		END IF;
	ELSE -- DO NOTHING
	END CASE;

	EXECUTE 'SELECT * FROM pem.chart WHERE id = $1::int4' USING cid INTO chart;
	-- Fetch all the metrices for this chart
	OPEN mcurs FOR EXECUTE 'SELECT * FROM pem.chart_metric WHERE cid = $1::int4' USING cid;
	LOOP
		FETCH mcurs INTO metric;
		EXIT WHEN NOT FOUND;

		probe_target_type := NULL;
		probe_applies_to_id := NULL;
		probe_keys := NULL;

		-- Fetch target-type, probe-applies-to, primary keys for the involved
		-- probe-table
		EXECUTE
		'SELECT p.target_type_id, p.applies_to_id, ARRAY(SELECT pc.internal_name FROM pem.probe_column pc WHERE pc.probe_id = p.id AND (($2::int4 = 6 AND pc.internal_name <> ''database_name'') OR ($2::int4 = 5 AND pc.internal_name NOT IN (''database_name'', ''schema_name'')) OR true) AND pc.classification = ''k'' ORDER BY pc.id) AS keys FROM pem.probe p WHERE p.internal_name = $1::text'
		INTO probe_target_type, probe_applies_to_id, probe_keys USING metric.tbl, level;

		IF probe_target_type IS NULL THEN
			-- We couldn't find the probe_target_id, it means the probe with
			-- that name does not exists
			RAISE EXCEPTION '107|%', metric.tbl;
		END IF;

		-- Restricted DBs are availabe that doesn't mean - they're applicable
		-- for this metric
		--
		-- Thye're applicable only if probe can applies to database level and
		-- current dashboard is for server-level
		IF probe_applies_to_id = 300 AND level = 200 THEN
			metric_restrict_dbs = restricted_dbs;
		ELSE
			metric_restrict_dbs = NULL;
		END IF;

		-- We need to find out, if this metric actually generates multiple
		-- sub-metrices (because they may have other primary keys too)
		IF level > 0 AND probe_keys IS NOT NULL AND array_length(probe_keys, 1) <> 0 THEN

			query := 'SELECT ARRAY[';

			SELECT string_agg('tbl.' || pg_catalog.quote_ident(probe_keys[a]), '::text, ')
				FROM generate_series(array_lower(probe_keys,1), array_upper(probe_keys,1)) a INTO tmp_str;
			query := query || tmp_str || '::text]::text[] FROM pemdata.' || pg_catalog.quote_ident(metric.tbl) || ' tbl';

			CASE WHEN level = 100 THEN
					query := query || ' WHERE tbl.agent_id = ' || aid::text || '::integer';
				WHEN level = 200 THEN
					query := query || ' WHERE tbl.server_id = ' || sid::text || '::integer';
					IF NOT show_system_objects THEN
						IF probe_applies_to_id = 300 THEN
							query := query || ' AND CASE WHEN database_name != '''' THEN database_name != ''template0'' AND database_name != ''template1'' ELSE TRUE END';
							IF restricted_dbs IS NOT NULL AND array_length(restricted_dbs, 1) > 0 THEN
								query := query || ' AND database_name = ANY(' || pg_catalog.quote_literal(restricted_dbs::text) || ')';
							END IF;
						ELSIF probe_applies_to_id > 300 THEN
							query := query || E' AND CASE WHEN database_name != '''' THEN database_name != ''template0'' AND database_name != ''template1'' AND schema_name NOT IN (''pg_catalog'', ''sys'', ''information_schema'') AND schema_name NOT LIKE ''pg_toast%'' AND schema_name NOT LIKE ''pg_temp%'' ELSE TRUE END';

							query := query || ' AND CASE WHEN database_name != '''' THEN database_name != ''template0'' AND database_name != ''template1'' ELSE TRUE END';
							IF restricted_dbs IS NOT NULL AND array_length(restricted_dbs, 1) > 0 THEN
								query := query || ' AND database_name = ANY(' || pg_catalog.quote_literal(restricted_dbs::text) || ') AND schema_name = ANY(
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
						END IF;
					END IF;
				WHEN level = 300 THEN
					query := query || ' WHERE tbl.server_id = ' || sid::text || '::integer AND tbl.database_name = ' || pg_catalog.quote_literal(db::text) || '::text';
					IF NOT show_system_objects THEN
						IF probe_applies_to_id > 300  THEN
							query := query || E' AND (schema_name NOT IN (''pg_catalog'', ''sys'', ''information_schema'') AND schema_name NOT LIKE ''pg_toast%'' AND schema_name NOT LIKE ''pg_temp%'')';
							IF restricted_schemas IS NOT NULL AND array_length(restricted_schemas, 1) > 0 THEN
								query := query || ' AND schema_name = ANY(' || pg_catalog.quote_literal(restricted_schemas::text) || ')';
							END IF;
						END IF;
					END IF;
				WHEN level = 400 THEN
					query := query || ' WHERE tbl.server_id = ' || sid::text || '::integer AND tbl.database_name = ' || pg_catalog.quote_literal(db::text) || '::text AND tbl.schema_name = ' || pg_catalog.quote_literal(schema::text) || '::text';
				ELSE
					query := query;
			END CASE;

			IF metric.gorderby IS NOT NULL AND array_length(metric.gorderby, 1) >0 THEN
				SELECT string_agg('tbl.' || pg_catalog.quote_ident(metric.gorderby[i]), ', ')
					FROM generate_series(array_lower(metric.gorderby,1), array_upper(metric.gorderby,1)) i INTO tmp_str;
				query := query || ' ORDER BY ' || tmp_str;
			END IF;
			IF (metric.glimit IS NOT NULL) THEN
				IF (metric.glimit < 0) THEN
					query := query || ' LIMIT ' || (metric.glimit * -1)::text || ' DESC';
				ELSE
					query := query || ' LIMIT ' || metric.glimit::text;
				END IF;
			END IF;

			OPEN gcurs FOR EXECUTE query;
			LOOP
				FETCH gcurs INTO probe_key_vals;
				EXIT WHEN NOT FOUND;
				CASE
				WHEN level = 100 THEN
					params := ARRAY['agent_id'::text];
					vals := ARRAY[aid::text];
				WHEN level >= 200 THEN
					IF probe_target_type >= 200 THEN
						params := ARRAY['server_id'::text];
						vals := ARRAY[sid::text];
						IF probe_target_type >= 300 THEN
							params := params || 'database_name'::text;
							vals := vals || db::text;
							IF probe_target_type >= 400 THEN
								params := params || 'schema_name'::text;
								vals := vals || schema::text;
							END IF;
						END IF;
					END IF;
				ELSE -- Do nothing
				END CASE;

				FOR a IN array_lower(probe_key_vals, 1) .. array_upper(probe_key_vals, 1)
				LOOP
					params := params || probe_keys[a]::text;
					vals := vals || probe_key_vals[a]::text;
				END LOOP;

				query := 'SELECT $1::integer AS idx, $2::text AS label, aggregated_time, aggregated_value FROM pem.data_rollup ($3::text, $4::text, $5::text, $6::timestamptz, $7::timestamptz, $8::interval, $9::integer, $10::text[], $11::text[], $12::integer, $13::boolean, $14::text[])';
				FOR m_idx IN array_lower(metric.metrices, 1) .. array_upper(metric.metrices, 1)
				LOOP
					pos := pos + 1;
					SELECT string_agg(probe_key_vals[b], ', ')
						FROM generate_series(array_lower(probe_key_vals,1), array_upper(probe_key_vals,1)) b INTO label;
					IF chart.labels IS NOT NULL AND array_length(chart.labels, 1) >= mt_idx + m_idx AND chart.labels[mt_idx + m_idx] IS NOT NULL THEN
						label := chart.labels[mt_idx + m_idx] || ' - ' || label;
					END IF;
					IF metric.agg_func IS NOT NULL AND array_length(metric.agg_func, 1) >= m_idx AND metric.agg_func[m_idx] IS NOT NULL THEN
						tmp_str := metric.agg_func[m_idx];
					END IF;
					CASE
						WHEN tmp_str = 'A' THEN tmp_str := 'avg';
						WHEN tmp_str = 'M' THEN tmp_str := 'max';
						WHEN tmp_str = 'm' THEN tmp_str := 'min';
						WHEN tmp_str = 'F' THEN tmp_str := 'FIRST';
						ELSE tmp_str := 'avg';
					END CASE;

					OPEN curs FOR EXECUTE query USING pos, label, metric.tbl, tmp_str, metric.metrices[m_idx], start_time, end_time, agg_int * '1 minute'::interval, max_points, params, vals, aid, is_capacity_manager, metric_restrict_dbs;
					LOOP
						FETCH curs INTO idx, label, agg_time, agg_val;
						EXIT WHEN NOT FOUND;

						RETURN NEXT;
					END LOOP;
					CLOSE curs;
				END LOOP;
			END LOOP;
			CLOSE gcurs;
			mt_idx := mt_idx + array_length(metric.metrices, 1);
		ELSE
			CASE
			WHEN level = 100 THEN
				params := ARRAY['agent_id'::text];
				vals := ARRAY[aid::text];
			WHEN level >= 200 THEN
				IF probe_target_type > 200 THEN
					params := ARRAY['server_id'::text];
					vals := ARRAY[sid::text];
				END IF;
				IF probe_target_type >= 300 THEN
					params := params || 'database_name'::text;
					vals := vals || db::text;
					IF probe_target_type >= 400 THEN
						params := params || 'schema_name'::text;
						vals := vals || schema::text;
					END IF;
				END IF;
			WHEN metric.params IS NOT NULL THEN
				FOR i IN array_lower(metric.params, 1) .. array_upper(metric.params, 1)
				LOOP
					IF metric.params[i].name IS NOT NULL AND metric.params[i].name != '' THEN
						IF sid IS NOT NULL AND metric.params[i].name = 'server_id' THEN
							params := params || metric.params[i].name;
							vals := vals || sid::text;
						ELSIF aid IS NOT NULL AND metric.params[i].name = 'agent_id' THEN
							params := params || metric.params[i].name;
							vals := vals || aid::text;
						ELSIF db IS NOT NULL AND db <> '' AND metric.params[i].name = 'database_name' THEN
							params := params || metric.params[i].name;
							vals := vals || db::text;
						ELSIF schema IS NOT NULL AND schema <> '' AND metric.params[i].name = 'schema_name' THEN
							params := params || metric.params[i].name;
							vals := vals || schema::text;
						ELSE
							params := params || metric.params[i].name;
							vals := vals || metric.params[i].value;
						END IF;
					END IF;
				END LOOP;
			ELSE -- Do nothing
			END CASE;

			tmp_str := 'A';
			query := 'SELECT $1::integer AS idx, $2::text AS label, aggregated_time, aggregated_value FROM pem.data_rollup ($3::text, $4::text, $5::text, $6::timestamptz, $7::timestamptz, $8::interval, $9::integer, $10::text[], $11::text[], $12::integer, $13::boolean, $14::text[])';
			FOR m_idx IN array_lower(metric.metrices, 1) .. array_upper(metric.metrices, 1)
			LOOP
				mt_idx := mt_idx + 1;
				pos := pos + 1;
				label := '';
				IF chart.labels IS NOT NULL AND array_length(chart.labels, 1) >= mt_idx THEN
					label := chart.labels[mt_idx];
				END IF;
				IF metric.agg_func IS NOT NULL AND array_length(metric.agg_func, 1) >= m_idx THEN
					tmp_str := metric.agg_func[m_idx];
				END IF;
				CASE
					WHEN tmp_str = 'A' THEN tmp_str := 'avg';
					WHEN tmp_str = 'M' THEN tmp_str := 'max';
					WHEN tmp_str = 'm' THEN tmp_str := 'min';
					WHEN tmp_str = 'F' THEN tmp_str := 'FIRST';
					ELSE tmp_str := 'avg';
				END CASE;

				OPEN curs FOR EXECUTE query USING pos, label, metric.tbl, tmp_str, metric.metrices[m_idx], start_time, end_time, agg_int * '1 minutes'::interval, max_points, params, vals, aid, is_capacity_manager, metric_restrict_dbs;
				LOOP
					FETCH curs INTO idx, label, agg_time, agg_val;
					EXIT WHEN NOT FOUND;

					RETURN NEXT;
				END LOOP;
				CLOSE curs;
			END LOOP;
		END IF;
	END LOOP;
	CLOSE mcurs;
END
$$ LANGUAGE 'plpgsql';

--------------------------------------------------------------------------------
-- Function:                                                                   -
--   pem.db_escaped_string_to_array                                            -
--                                                                             -
-- Parameters:                                                                 -
--   src : Escapsed string                                                     -
--                                                                             -
-- Returns:                                                                    -
--   - Array object containing the elements in the escaped string              -
--                                                                             -
-- Purpose:                                                                    -
--   Convert escpared string to an array.                                      -
--                                                                             -
-- Purpose:                                                                    -
--   The restricted db(s) and schema(s) are stored as an esacped string in the -
--   database server (of course - it is a bad design, but - we'll have to      -
--   leave with it), In order to use them in query, we need to convert them    -
--   into an array. This function helps doing that.                            -
--------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION pem.db_escaped_string_to_array(src text) RETURNS text[] AS
$$
DECLARE
	res text[] = ARRAY[]::text[];
	len int4;
	inquote boolean := false;
	tmpstr text := '';
	idx int4 := 1;
	arridx int4 := 1;
	prevchar text;
	currchar text;
BEGIN
	IF src IS NULL THEN
		RETURN NULL;
	END IF;
	len := length(src);

	IF len = 0 THEN
		RETURN NULL;
	END IF;

	WHILE idx <= len
	LOOP
		currchar := substring(src from idx for 1);

		IF currchar = '''' THEN
			IF NOT inquote THEN
				IF prevchar IS NOT NULL THEN
					IF prevchar = '''' THEN
						tmpstr := tmpstr || '''';
						prevchar := NULL;
					END IF;
					inquote := true;
				ELSE
					prevchar := NULL;
					inquote := true;
				END IF;
			ELSE
				prevchar := '''';
				inquote := false;
			END IF;
		ELSIF currchar = '\\' AND idx < len AND substring(src from idx + 1 for 1) = '''' THEN
			idx := idx + 1;
			prevchar := NULL;
			tmpstr := tmpstr || '''';
		ELSIF (NOT inquote) AND currchar = 'E' AND idx < len AND substring(src from idx + 1 for 1) = '''' THEN
			-- Ignore the ESCAPE character
			idx := idx + 1;
			inquote := true;
			prevchar := NULL;
		ELSIF (NOT inquote) AND currchar = ',' THEN
			res[arridx] := tmpstr;
			arridx :=  arridx + 1;
			tmpstr := '';
			prevchar := NULL;
		ELSIF (NOT inquote) AND (currchar = ' ' OR currchar = '\n' OR currchar = '\r' OR currchar = '\t' OR currchar = '\f') THEN
			-- Ignore all white-space characters outside the quote
		ELSE
			prevchar :=  currchar;
			tmpstr := tmpstr || currchar;
		END IF;
		idx := idx + 1;
	END LOOP;
	res[arridx] :=  tmpstr;

	return res;
END
$$ LANGUAGE plpgsql;

CREATE SEQUENCE pem.dashboard_id_seq START WITH 51;
CREATE TABLE pem.dashboard
(
	-- Unique id for a custom dashboard
	id	    integer		NOT NULL DEFAULT nextval('pem.dashboard_id_seq'::regclass),

	-- Level at which this dashboard will be visible
	------------------------------------------------
	-- 50  : Global level dashboard
	-- 100 : Agent / Operating system level dashboard
	-- 200 : Server level dashboard
	-- 300 : Database level dashboard
	level	    integer		NOT NULL,

	-- Title (title - Display Name)
	title	    character varying	NOT NULL,

	-- Description
	descp	    character varying	DEFAULT NULL,

	-- Owner of the dashboard
	--  '0' suggest - it is a system defined dashboard
	--  Other suggests the owner of the dashboard
	owner	    oid			NOT NULL,

	-- Shared with which users/roles
	-- 'NULL' suggests with All
	shared  oid[],

	CONSTRAINT pem_dashboard_pk PRIMARY KEY (id),
	CONSTRAINT pem_dashboard_level_constraint CHECK (level::integer IN (50, 100, 200, 300))
);

CREATE TABLE pem.dashboard_section
(
	-- Unique id for a dashboard section
	id	    integer		NOT NULL,

	-- Id of the dashboard to which it belongs
	did	    integer		NOT NULL,

	-- Title
	title	    character varying	NOT NULL,

	CONSTRAINT pem_dashboard_section_pk PRIMARY KEY (id,did),
	CONSTRAINT pem_dashboard_section_fk_did FOREIGN KEY (did) REFERENCES pem.dashboard(id)
		MATCH SIMPLE ON UPDATE CASCADE ON DELETE CASCADE INITIALLY DEFERRED
);

CREATE TABLE pem.dashboard_chart
(
	-- Id of the dashboard
	did	    integer		NOT NULL,

	-- Id of the dashboard section to which it belongs
	sid	    integer		NOT NULL,

	-- Id of the chart to display
	cid	    integer		NOT NULL,

	-- Location inside the section
	index	    integer		NOT NULL,

	-- Size of the chart
	size        integer             NOT NULL DEFAULT 2, -- 1 : SMALLEST, 2 : MEDIUM, 3 : HIGH MEDIUM, 4: BIG, 5 : FULL

	-- Alignment
	align       integer             NOT NULL DEFAULT 1, -- 1 : LEFT, 2 : CENTER, 3 : RIGHT

	CONSTRAINT pem_dashboard_chart_fk_sid FOREIGN KEY (did,sid) REFERENCES pem.dashboard_section(did,id)
		MATCH SIMPLE ON UPDATE CASCADE ON DELETE CASCADE INITIALLY DEFERRED,
	CONSTRAINT pem_dashboard_chart_fk_cid FOREIGN KEY (cid) REFERENCES pem.chart(id)
		MATCH SIMPLE ON UPDATE CASCADE ON DELETE CASCADE INITIALLY DEFERRED
);

CREATE OR REPLACE FUNCTION pem.dashboard_chart_insertion() RETURNS trigger AS $$
BEGIN
        UPDATE pem.chart SET ref_cnt = ref_cnt + 1 WHERE id = NEW.cid;
        RETURN NULL;
END
$$ LANGUAGE plpgsql;

CREATE TRIGGER pem_dashboard_chart_insertion
	AFTER INSERT ON pem.dashboard_chart
	FOR EACH ROW EXECUTE PROCEDURE pem.dashboard_chart_insertion();

CREATE OR REPLACE FUNCTION pem.dashboard_chart_deletion() RETURNS trigger AS $$
BEGIN
        UPDATE pem.chart SET ref_cnt = ref_cnt - 1 WHERE id = OLD.cid;
        RETURN NULL;
END
$$ LANGUAGE plpgsql;

CREATE TRIGGER pem_dashboard_chart_deletion
	AFTER DELETE ON pem.dashboard_chart
	FOR EACH ROW EXECUTE PROCEDURE pem.dashboard_chart_deletion();

CREATE OR REPLACE FUNCTION pem.can_access(roles oid[]) RETURNS boolean AS $$
DECLARE
	cid oid;
	is_superuser boolean;
	is_member int4 := 0;
	length int4 := 0;
BEGIN
	IF roles IS NULL THEN
		RETURN true;
	END IF;
	SELECT usesysid, usesuper INTO cid, is_superuser FROM pg_catalog.pg_user u WHERE usename = current_user;
	IF is_superuser THEN
		RETURN true;
	END IF;
	length := array_length(roles, 1);
	IF length IS NULL OR length = 0 THEN
		return false;
	END IF;
	FOR i IN array_lower(roles, 1) .. array_upper(roles, 1)
	LOOP
		CASE WHEN cid = roles[i] THEN
			RETURN true;
		ELSE
			SELECT COUNT(*) INTO is_member FROM pg_catalog.pg_auth_members WHERE roleid = roles[i] AND member = cid;
			IF is_member = 1 THEN
				RETURN true;
			END IF;
		END CASE;
	END LOOP;
	RETURN false;
END
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION pem.purge_deleted_charts()
RETURNS void AS $$
    -- Purge data from the pem.chart table
    DELETE FROM pem.chart
        WHERE deleted AND (ref_cnt = 0 OR (now() - deleted_time) >= ((SELECT value FROM pem.config WHERE param = 'deleted_charts_retention_time')||'days')::interval);
$$ LANGUAGE sql SECURITY DEFINER;


CREATE OR REPLACE FUNCTION pem.generate_host_memory_chart_data(aid integer)
        RETURNS TABLE(idx int2, label text, agg_time timestamptz, agg_val numeric) AS
$$
DECLARE
        cur refcursor;
        ts interval;
        ai interval;
        mp int4;
        rec RECORD;
BEGIN
        SELECT time_span, agg_int * '1 minutes'::interval, max_points INTO ts, ai, mp FROM pem.metrices_chart WHERE cid = 39;

        OPEN cur FOR EXECUTE 'SELECT d1.aggregated_time AS agg_time, (d2.aggregated_value - d1.aggregated_value) AS used_mem, d1.aggregated_value AS free_mem FROM pem.data_rollup($1::text, $2::text, $3::text, $4::timestamptz, $5::timestamptz, $6::interval, $7::int4, $8::varchar[], $9::varchar[], $10::int4, $11::boolean) AS d1 LEFT JOIN pem.data_rollup($1::text, $2::text, $12::text, $4::timestamptz, $5::timestamptz, $6::interval, $7::int4, $8::varchar[], $9::varchar[], $10::int4, $11::boolean) AS d2 ON (d1.aggregated_time = d2.aggregated_time) WHERE d2.aggregated_time IS NOT NULL ORDER BY d1.aggregated_time' USING 'memory_usage'::text, 'AVG'::text, 'free_ram_memory_mb'::text, (now() - ts)::timestamptz, now()::timestamptz, ai, mp, ARRAY['agent_id']::varchar[], ARRAY[aid::varchar]::varchar[], aid, false, 'total_ram_memory_mb'::text;

        LOOP
                FETCH cur INTO rec;
                EXIT WHEN NOT FOUND;

                idx = 1;
                label = 'Used Memory';
                agg_time = rec.agg_time;
                agg_val = rec.used_mem;
                RETURN NEXT;

                idx = 2;
                label = 'Free Memory';
                agg_time = rec.agg_time;
                agg_val = rec.free_mem;
                RETURN NEXT;
        END LOOP;

        CLOSE cur;
END
$$ LANGUAGE 'plpgsql';

INSERT INTO pem.chart_catagory(id, name, descp, owner) VALUES
	(1, 'Global Overview', 'Charts render on the Global Overview dashboard', 0),
	(2, 'Alerts', 'Charts render on the Alerts dashboard', 0),
	(3, 'Audit logs', 'Charts render on the Audit logs dashboard', 0),
	(4, 'Database', 'Charts render on the Database dashboard', 0),
	(5, 'Database I/O', 'Charts render on the Database I/O dashboard', 0),
	(6, 'Database Server Memory', 'Charts, related to database server memory, render on the Memory dashboard', 0),
	(7, 'Operating System Memory', 'Charts, related to operating system memory, render on the Memory dashboard', 0),
	(8, 'Database Object Activity', 'Charts render on the Object Activity dashboard', 0),
	(9, 'Operating System Information', 'Charts render on the Operating System dashboard', 0),
	(10, 'Probe Logs', 'Charts render on the Probe Log dashboard', 0),
	(11, 'Database Server', 'Charts render on the Server Logs dashboard', 0),
	(12, 'Sessions Analysis', 'Charts render on the Session Activity/Waits dashboard', 0),
	(13, 'Storage Analysis', 'Charts render on the Storage Analysis dashboard', 0),
	(14, 'System Wait Analysis', 'Charts render on the System Wait Analysis dashboard', 0);

INSERT INTO pem.chart_func(id, type, func, r_sys_obj) VALUES
	(1, 'Q', E'
WITH agent_list AS (
	SELECT
		pa.id AS id, pa.active AS active, pah.agent_id, pah.last_heartbeat, pa.heartbeat_interval
	FROM
		pem.agent pa
		LEFT OUTER JOIN pem.agent_heartbeat pah ON (pa.id = pah.agent_id)
),
server_list AS (
	SELECT
		ps.id AS server_id, psh.last_heartbeat AS server_last_heartbeat,
		pa.active AS agent_active, pah.last_heartbeat AS agent_last_heartbeat,
		pa.heartbeat_interval AS heartbeat_interval
	FROM
		pem.avail_servers ps
		LEFT OUTER JOIN pem.server_heartbeat psh ON (ps.id = psh.server_id)
		LEFT OUTER JOIN pem.agent_server_binding pasb ON (ps.id = pasb.server_id)
		LEFT OUTER JOIN pem.agent pa ON (pasb.agent_id = pa.id AND psh.agent_id = pa.id)
		LEFT OUTER JOIN pem.agent_heartbeat pah ON (pah.agent_id = pasb.agent_id)
)
SELECT
	id,
	label,
	count
FROM
	(
		SELECT
			1 AS id, ''Agents Up'' AS label, true AS required, count(id) AS count
		FROM
			agent_list
		WHERE
			active = TRUE AND
			agent_id IS NOT NULL AND
			last_heartbeat < now() AND
			last_heartbeat > (now() - (heartbeat_interval * 2 * ''1 second''::interval))
		UNION
		SELECT
			2 AS id, ''Agents Down'' AS label, true AS required, count(id) AS count
		FROM
			agent_list
		WHERE
			active = TRUE AND
			agent_id IS NOT NULL AND
			last_heartbeat < (now() - (heartbeat_interval * 2 * ''1 second''::interval))
		UNION
		SELECT
			3 AS id, ''Agents Unknown'' AS label, false AS required, count(id) AS count
		FROM
			agent_list
		WHERE
			active = TRUE AND
			agent_id IS NULL
		UNION
		SELECT
			4 AS id, ''Servers UP'' AS label, true AS required, count(server_id) AS count
		FROM
			server_list
		WHERE
			agent_active IS NOT NULL AND agent_active AND
			server_last_heartbeat IS NOT NULL AND
			server_last_heartbeat < now() AND
			server_last_heartbeat > (now() - (heartbeat_interval * 2 * ''1 second''::interval))
		UNION
		SELECT
			5 AS id, ''Servers Down'' AS label, true AS required, count(server_id) AS count
		FROM
			server_list
		WHERE
			agent_active IS NOT NULL AND agent_active AND
			agent_last_heartbeat IS NOT NULL AND
			agent_last_heartbeat < now() AND
			agent_last_heartbeat > (now() - (heartbeat_interval * 2 * ''1 second''::interval)) AND
			server_last_heartbeat IS NOT NULL AND
			server_last_heartbeat < (now() - (heartbeat_interval * 2 * ''1 second''::interval))
		UNION
		SELECT
			6 AS id, ''Servers Unknown'' AS label, false AS required, count(server_id) AS count
		FROM
			server_list
		WHERE
			-- The server is not bound with any server
			agent_active IS NULL OR
			(agent_active AND
				-- The agent is bound, but never got an heartbeat from it
				(agent_last_heartbeat IS NULL OR
					-- The agent is not properly bound with the server
					-- (Agent may not have proper authentication for connection)
					server_last_heartbeat IS NULL OR
					-- Agent is down for some reason
					agent_last_heartbeat < (now() - (heartbeat_interval * 2 * ''1 second''::interval))))
	) AS global_pem_status
WHERE required OR count > 0
ORDER BY id', false),
	( 2, 'P', 'table_global_overview_agent_status', false),
	( 3, 'P', 'table_global_overview_server_status', false),
	( 4, 'P', 'table_global_overview_alerts_status', false),
	( 5, 'P', 'barchart_alerts_overview', true),
	( 6, 'P', 'table_alerts_details', true),
	( 7, 'P', 'table_alerts_errors', true),
	( 8, 'P', 'table_audit_logs', true),
	( 9, 'Q', E'
	SELECT
		$$Total Database Size: $$ ||
		(SELECT	pem.pretty_size(database_size_mb) FROM	pemdata.database_size WHERE database_size.server_id = $1::int4 AND database_size.database_name = $2::text) || $$&#183;$$

		||$$ Total Tables: $$ ||(SELECT count(distinct(table_name)) FROM
		pemdata.table_size
		WHERE server_id = $1::int4 AND database_name = $2::text )|| $$&#183;$$

		|| $$ Total Indexes: $$ || (SELECT count(distinct(index_name)) FROM pemdata.index_size
		WHERE server_id = $1::int4 AND database_name = $2::text)', false),
	(10, 'Q', E'
	WITH restricted_db_schemas AS (SELECT
		s.id, pem.db_escaped_string_to_array(COALESCE(o.schema_restriction, oa.schema_restriction)) as rest_schemas
	FROM
		pem.server s
		LEFT OUTER JOIN pg_catalog.pg_roles owner ON (owner.oid = s.owner)
		LEFT OUTER JOIN pem.database_option o ON (s.id = o.server_id AND o.pem_user = current_user AND o.database = $2::text)
		LEFT OUTER JOIN pem.database_option oa
			ON (o.id IS NULL AND s.id = oa.server_id AND oa.database = $2::text AND
				(owner.rolname = oa.pem_user OR (owner.rolname IS NULL AND oa.pem_user IS NULL)))
	WHERE
		s.id = $1::int4)
	SELECT
		t.table_name AS object_name,
		t.table_size_mb AS "Object Size"
	FROM
		pemdata.table_size t
		LEFT OUTER JOIN restricted_db_schemas rds ON ( t.server_id = rds.id )
	WHERE t.server_id = $1::int4 AND t.database_name = $2::text AND (rds.rest_schemas IS NULL OR t.schema_name = ANY (rds.rest_schemas)) AND
		($3::boolean OR (t.schema_name NOT IN($$pg_catalog$$, $$pg_toast$$, $$information_schema$$, $$sys$$) AND t.schema_name !~ $$pg_temp|pg_toast$$))

	UNION

	SELECT
		i.index_name AS object_name,
		i.index_size_mb as "Object Size"
	FROM
		pemdata.index_size i
		LEFT OUTER JOIN restricted_db_schemas rds ON ( i.server_id = rds.id )
	WHERE i.server_id = $1::int4 AND i.database_name = $2::text AND (rds.rest_schemas IS NULL OR i.schema_name = ANY(rds.rest_schemas)) AND
		($3::boolean OR (i.schema_name NOT IN($$pg_catalog$$, $$pg_toast$$, $$information_schema$$, $$sys$$) AND i.schema_name !~ $$pg_temp|pg_toast$$))
	ORDER BY "Object Size" DESC LIMIT 5', false),
	(12, 'Q', E'
	SELECT $$Max Connections: $$|| setting from pemdata.settings WHERE name = ''max_connections'' and server_id = $1::int4', false),
	(13, 'Q', E'
	SELECT
		SUM(numbackends) AS "Total Connections",
		SUM(idle_backends) AS "Idle Connections"
	FROM
		pemdata.database_statistics
	WHERE server_id = $1::int4 AND database_name = $2::text
	GROUP BY recorded_time
	ORDER BY recorded_time DESC', false),
	(18, 'Q', E'SELECT
		$$Commits: $$||COALESCE(xact_commit::text, $$Unknown$$) || $$&#183;$$
		|| $$ Rollbacks: $$||COALESCE(xact_rollback::text, $$Unknown$$)
	FROM
		pemdata.database_statistics
	WHERE
		server_id = $1::int4 AND database_name = $2::text', false),
	(21, 'Q', E'
	SELECT
		$$Transactions running for more than $$||(SELECT value FROM pem.config WHERE param=''long_running_transaction_minutes'') ||$$ minutes: $$||count(*)
	FROM
		pemdata.session_info
	WHERE now() - query_start > (
	SELECT
		(value||'' minutes '')::interval
	FROM
		pem.config WHERE param=''long_running_transaction_minutes'') AND not is_idle AND server_id = $1::int4 AND database_name = $2::text', false),
	(22, 'Q', E'
	SELECT
		$$Buffers Written by Checkpoints: $$||COALESCE(buffers_checkpoint::text, $$Unknown$$)
	FROM
		pemdata.background_writer_statistics
	WHERE
		server_id = $1', false),
	(24, 'Q', E'
	WITH restricted_db_schemas AS (SELECT
		s.id, pem.db_escaped_string_to_array(COALESCE(o.schema_restriction, oa.schema_restriction)) as rest_schemas
	FROM
		pem.server s
		LEFT OUTER JOIN pg_catalog.pg_roles owner ON (owner.oid = s.owner)
		LEFT OUTER JOIN pem.database_option o ON (s.id = o.server_id AND o.pem_user = current_user AND o.database = $2::text)
		LEFT OUTER JOIN pem.database_option oa
			ON (o.id IS NULL AND s.id = oa.server_id AND oa.database = $2::text AND
				(owner.rolname = oa.pem_user OR (owner.rolname IS NULL AND oa.pem_user IS NULL)))
	WHERE
		s.id = $1::int4)
	SELECT
		t.table_name AS "Table Name",
		t.seq_scan AS "Scans"
	FROM
		pemdata.table_statistics t
		LEFT OUTER JOIN restricted_db_schemas rds ON ( t.server_id = rds.id )
	WHERE
		t.server_id = $1::int4 AND t.database_name = $2::text AND (rds.rest_schemas IS NULL OR t.schema_name = ANY (rds.rest_schemas)) AND
		($3::boolean OR (t.schema_name NOT IN($$pg_catalog$$, $$pg_toast$$, $$information_schema$$, $$sys$$) AND t.schema_name !~ $$pg_temp|pg_toast$$))
	ORDER BY "Scans" DESC LIMIT 5', false),
	(25, 'Q', E'
	WITH restricted_db_schemas AS (SELECT
		s.id, pem.db_escaped_string_to_array(COALESCE(o.schema_restriction, oa.schema_restriction)) as rest_schemas
	FROM
		pem.server s
		LEFT OUTER JOIN pg_catalog.pg_roles owner ON (owner.oid = s.owner)
		LEFT OUTER JOIN pem.database_option o ON (s.id = o.server_id AND o.pem_user = current_user AND o.database = $2::text)
		LEFT OUTER JOIN pem.database_option oa
			ON (o.id IS NULL AND s.id = oa.server_id AND oa.database = $2::text AND
				(owner.rolname = oa.pem_user OR (owner.rolname IS NULL AND oa.pem_user IS NULL)))
	WHERE
		s.id = $1::int4)
	SELECT
		i.index_name AS "Index Name",
		i.idx_scan as "Scans"
	FROM
		pemdata.index_statistics i
		LEFT OUTER JOIN restricted_db_schemas rds ON ( i.server_id = rds.id )
	WHERE
		i.server_id = $1::int4 AND i.database_name = $2::text AND (rds.rest_schemas IS NULL OR i.schema_name = ANY (rds.rest_schemas)) AND
		($3::boolean OR (i.schema_name NOT IN($$pg_catalog$$, $$pg_toast$$, $$information_schema$$, $$sys$$) AND i.schema_name !~ $$pg_temp|pg_toast$$))
	ORDER BY "Scans" DESC LIMIT 5', false),
	(26, 'Q', E'
	WITH shared_buf_hit AS (
	SELECT
		(CASE WHEN SUM(blks_hit)+SUM(blks_read)= 0 THEN 0 ELSE SUM(blks_hit)*100/(SUM(blks_hit)+SUM(blks_read)) END)::numeric(30,2) shared_hit
	FROM
		pemdata.database_statistics d
	WHERE server_id = $1::int AND
	($2::boolean OR (CASE WHEN d.database_name != '''' THEN d.database_name NOT IN (''template0'', ''template1'') ELSE TRUE END))
	)
	SELECT
		$$Hit Rate: $$|| shared_hit || $$&#183; Shared Buffer Size: $$ || (setting)::bigint * (CASE WHEN POSITION($$kb$$ in LOWER(unit)) = 0 OR SPLIT_PART(unit, $$kB$$, 1) IN (NULL, $$$$) THEN 1 ELSE SPLIT_PART(unit, $$kB$$, 1)::int END) / 1024
	FROM
		pemdata.settings, shared_buf_hit
	WHERE
		server_id = $1::int AND name=$$shared_buffers$$', false),
	(28, 'Q', E'
	SELECT
		name,
		(cast(setting as float) * ((CASE WHEN POSITION($$kb$$ in LOWER(unit)) = 0 OR SPLIT_PART(unit, $$kB$$, 1) IN (NULL, $$$$) THEN 1 ELSE SPLIT_PART(unit, $$kB$$, 1)::float END)/1024) )::numeric(12,4)
	FROM
		pemdata.settings
	WHERE
		server_id = $1::int4 AND
		name = $$wal_buffers$$
	UNION
	SELECT
		name,
		(cast(setting as float) * ((CASE WHEN POSITION($$kb$$ in LOWER(unit)) = 0 OR SPLIT_PART(unit, $$kB$$, 1) IN (NULL, $$$$) THEN 1 ELSE SPLIT_PART(unit, $$kB$$, 1)::float END)/1024))::numeric(12,4)
	FROM
		pemdata.settings
	WHERE
		server_id = $1::int4 AND
		name = $$shared_buffers$$
	UNION
	SELECT
		name,
		(cast (setting as float) * ((CASE WHEN POSITION($$kb$$ in LOWER(unit)) = 0 OR SPLIT_PART(unit, $$kB$$, 1) IN (NULL, $$$$) THEN 1 ELSE SPLIT_PART(unit, $$kB$$, 1)::float END)/1024))::numeric(12,4)
	FROM
		pemdata.settings
	WHERE
		server_id = $1::int4 AND
		name = $$work_mem$$', false),
	(30, 'Q', E'
	SELECT
	total_ram_memory_mb - free_ram_memory_mb AS Used,
	free_ram_memory_mb AS Free
	FROM
		pemdata.memory_usage
	WHERE
		agent_id = $1::int4', false),
	(31, 'Q', E'
	WITH restricted_db_schemas AS (SELECT
		s.id, pem.db_escaped_string_to_array(COALESCE(o.schema_restriction, oa.schema_restriction)) as rest_schemas
	FROM
		pem.server s
		LEFT OUTER JOIN pg_catalog.pg_roles owner ON (owner.oid = s.owner)
		LEFT OUTER JOIN pem.database_option o ON (s.id = o.server_id AND o.pem_user = current_user AND o.database = $2::text)
		LEFT OUTER JOIN pem.database_option oa
			ON (o.id IS NULL AND s.id = oa.server_id AND oa.database = $2::text AND
				(owner.rolname = oa.pem_user OR (owner.rolname IS NULL AND oa.pem_user IS NULL)))
	WHERE
		s.id = $1::int4)
	SELECT
		t.table_name AS object_name,
		t.table_size_mb AS "Object Size"
	FROM
		pemdata.table_size t
		LEFT OUTER JOIN restricted_db_schemas rds ON ( t.server_id = rds.id )
	WHERE t.server_id = $1::int4 AND t.database_name = $2::text AND (rds.rest_schemas IS NULL OR t.schema_name = ANY (rds.rest_schemas)) AND
	($3::boolean OR (t.schema_name NOT IN($$pg_catalog$$, $$pg_toast$$, $$information_schema$$, $$sys$$) AND t.schema_name !~ $$pg_temp|pg_toast$$))
	ORDER BY "Object Size" DESC LIMIT 5', false),
	(32, 'Q', E'
	WITH restricted_db_schemas AS (SELECT
		s.id, pem.db_escaped_string_to_array(COALESCE(o.schema_restriction, oa.schema_restriction)) as rest_schemas
	FROM
		pem.server s
		LEFT OUTER JOIN pg_catalog.pg_roles owner ON (owner.oid = s.owner)
		LEFT OUTER JOIN pem.database_option o ON (s.id = o.server_id AND o.pem_user = current_user AND o.database = $2::text)
		LEFT OUTER JOIN pem.database_option oa
			ON (o.id IS NULL AND s.id = oa.server_id AND oa.database = $2::text AND
				(owner.rolname = oa.pem_user OR (owner.rolname IS NULL AND oa.pem_user IS NULL)))
	WHERE
		s.id = $1::int4)
	SELECT
		i.index_name AS object_name,
		i.index_size_mb as "Object Size"
	FROM
		pemdata.index_size i
		LEFT OUTER JOIN restricted_db_schemas rds ON ( i.server_id = rds.id )
	WHERE i.server_id = $1::int4 AND i.database_name = $2::text AND (rds.rest_schemas IS NULL OR i.schema_name = ANY(rds.rest_schemas)) AND
	($3::boolean OR (i.schema_name NOT IN($$pg_catalog$$, $$pg_toast$$, $$information_schema$$, $$sys$$) AND i.schema_name !~ $$pg_temp|pg_toast$$))
	ORDER BY "Object Size" DESC LIMIT 5', false),

	-- ID = 34. We can easily achive the same PL/PGSQL of earlier functionality as a query. Hence changing it's behaviour from function to sql, so that we can reduce the amount of php code for PL/PGSQL behaviour.

	(34, 'Q', E'WITH restricted_db_schemas AS (
	SELECT
		s.id, pem.db_escaped_string_to_array(COALESCE(o.schema_restriction, oa.schema_restriction)) as rest_schemas
	FROM
		pem.server s
		LEFT OUTER JOIN pg_catalog.pg_roles owner ON (owner.oid = s.owner)
		LEFT OUTER JOIN pem.database_option o ON (s.id = o.server_id AND o.pem_user = current_user AND o.database = $2::text)
		LEFT OUTER JOIN pem.database_option oa
			ON (o.id IS NULL AND s.id = oa.server_id AND
				(owner.rolname = oa.pem_user OR (owner.rolname IS NULL AND oa.pem_user IS NULL)))
	WHERE
		s.id = $1::int4 AND oa.database = $2::text)

	SELECT
		schema_name AS "Schema",
		table_name AS "Object",
		''Table'' AS "Object Type",
		table_size_mb AS "Table Size(MB)",
		size_of_indexes_mb AS "Index Size(MB)",
		total_table_size_mb AS "Total(MB)"
	FROM
		pemdata.table_size t
		LEFT OUTER JOIN restricted_db_schemas r ON ( t.server_id = r.id )
	WHERE
		server_id = $1::int4 AND
		database_name = $2::text AND
		total_table_size_mb !=0 AND
		(r.rest_schemas IS NULL OR (t.schema_name = ANY(r.rest_schemas))) AND
		($3::boolean OR (t.schema_name NOT IN(''pg_catalog'', ''pg_toast'', ''information_schema'', ''sys'') AND t.schema_name !~ ''pg_temp|pg_toast''))
	UNION
	SELECT
		schema_name AS "Schema",
		index_name AS "Object",
		''Index'' AS "Object Type",
		NULL AS "Table Size(MB)",
		index_size_mb AS "Index Size(MB)",
		index_size_mb AS "Total(MB)"
	FROM
		pemdata.index_size i
		LEFT OUTER JOIN restricted_db_schemas r ON ( i.server_id = r.id )
	WHERE	server_id = $1::int4 AND
		database_name = $2::text AND
		index_size_mb IS NOT NULL AND index_size_mb !=0 AND
		(r.rest_schemas IS NULL OR (i.schema_name = ANY(r.rest_schemas))) AND
		($3::boolean OR (i.schema_name NOT IN(''pg_catalog'', ''pg_toast'', ''information_schema'', ''sys'') AND i.schema_name !~ ''pg_temp|pg_toast''))
	ORDER BY "Table Size(MB)" DESC LIMIT $4::int4', true),
	(35, 'Q', E'SELECT $$Total Process: $$ || total_process_count || $$ &#183; Total Threads: $$ || total_thread_count FROM pemdata.os_statistics WHERE agent_id = $1::int4', false),
	(37, 'Q', E'
	SELECT
		SUM(space_used_mb) AS used,
		SUM(space_available_mb) AS free
	FROM
		pemdata.disk_space
	WHERE
		agent_id = $1::int4', false),
	(38, 'Q', E'
	SELECT
		$$Total: $$ || total_ram_memory_mb || $$MB &#183; Used: $$ || total_ram_memory_mb - free_ram_memory_mb || $$MB &#183; Free: $$ || free_ram_memory_mb || $$MB &#183; Swap Total: $$ || total_swap_memory_mb || $$MB &#183; Swap Used: $$ || total_swap_memory_mb - free_swap_memory_mb
	FROM
		pemdata.memory_usage
	WHERE agent_id = $1::int4', false),

	-- ID = 44. We can easily achive the same PL/PGSQL of earlier functionality as a query. Hence changing it's behaviour from function to sql, so that we can reduce the amount of php code for PL/PGSQL behaviour.

	(44, 'Q', E'
	SELECT
		file_system AS "File System",
		(size_mb::float/1024)::numeric(30,2) AS "Size (GB)",
		(space_used_mb::float/1024)::numeric(30,2) AS "Used (GB)",
		(space_available_mb::float/1024)::numeric(30,2) AS "Available (GB)",
		CASE WHEN size_mb = 0
		THEN 0
		ELSE (space_used_mb*100)/size_mb
		END
		AS "%Used",
		mount_point AS "Mounted On"
	FROM
		pemdata.disk_space
	WHERE
		agent_id = $1::int4
	ORDER BY 3::int DESC', false),
	(46, 'Q',E'
	SELECT
		''Bandwidth: ''|| pg_catalog.array_to_string(array_agg(interface_name || '' - '' || link_speed_mbps || ''Mb/s''),'') AS network_interface_details
	FROM
		pemdata.network_statistics
	WHERE interface_name NOT ILIKE $$lo%$$ AND agent_id = $1::int4', false),
--	(48, 'P', 'table_probe_logs', false),
--	(49, 'P', 'table_server_logs', false),
	(52, 'Q', E'
	WITH shared_buf_hit AS (
	SELECT
		(CASE WHEN SUM(blks_hit)+SUM(blks_read)= 0 THEN 0 ELSE SUM(blks_hit)*100/(SUM(blks_hit)+SUM(blks_read)) END)::numeric(30,2) shared_hit
	FROM
		pemdata.database_statistics d
	WHERE server_id = $1::int4 AND
	($2::boolean OR (CASE WHEN d.database_name != '''' THEN d.database_name NOT IN (''template0'', ''template1'') ELSE TRUE END))
	)
	SELECT
		$$Hit Rate: $$ || shared_hit || $$&#183; Shared Buffer Size: $$ || (setting)::bigint * (CASE WHEN POSITION(lower($$kB$$) in lower(unit)) = 0 THEN 1 ELSE SPLIT_PART(unit,$$kB$$,1)::int END) / 1024
	FROM
		pemdata.settings, shared_buf_hit
	WHERE
		server_id = $1::int4 AND name=$$shared_buffers$$', false),
	(54, 'Q', E'
	SELECT
		$$Total Locks: $$ || count(DISTINCT locktype) || $$ &#183; Blocked Users: $$ || count(DISTINCT procpid)
	FROM
		pemdata.lock_info
	WHERE server_id = $1::int4', false),
	(56, 'Q', E'
	SELECT $$Max Connections: $$ || COALESCE(setting, $$Unknown$$) from pemdata.settings WHERE name = $$max_connections$$ and server_id = $1::int4', false),
	(57, 'Q', E'
	SELECT
		SUM(numbackends) AS "Total Connections",
		SUM(idle_backends) AS "Idle Connections"
	FROM
		pemdata.database_statistics
	WHERE server_id = $1::int4', false),
	(61, 'Q', E'
	WITH restricted_dbs AS (
		SELECT s.id, pem.db_escaped_string_to_array(COALESCE(o.database_restriction, oa.database_restriction)) AS dbs
	FROM
        pem.server s
        LEFT OUTER JOIN pg_catalog.pg_roles owner ON (owner.oid = s.owner)
        LEFT OUTER JOIN pem.server_option o ON (s.id = o.server_id AND o.pem_user = current_user)
        LEFT OUTER JOIN pem.server_option oa
                ON (o.id IS NULL AND s.id = oa.server_id AND
                        (owner.rolname = oa.pem_user OR (owner.rolname IS NULL AND oa.pem_user IS NULL)))
	)
	SELECT
		d.database_name AS "Database",
		d.numbackends AS "Connections",
		d.xact_commit AS "TX Committed",
		d.xact_rollback AS "TX Rolled Back",
		d.blks_hit AS "Blocks Hit",
		d.blks_read AS "Blocks Read",
		d.tup_fetched AS "Tuples Fetched",
		d.tup_fetched AS "Tuples Returned",
		d.tup_inserted AS "Tuples Inserted",
		d.tup_updated AS "Tuples Updated",
		d.tup_deleted AS "Tuples Deleted"
	FROM
		pemdata.database_statistics d
		JOIN pemdata.oc_database o ON (d.server_id = o.server_id AND d.database_name = o.database_name)
		LEFT JOIN restricted_dbs r ON (d.server_id = r.id)
	WHERE
		o.connections_allowed = TRUE AND
		d.server_id = $1::int4 AND
		($2::boolean OR (CASE WHEN d.database_name != '''' THEN d.database_name NOT IN (''template0'', ''template1'') ELSE TRUE END)) AND
		(r.dbs IS NULL OR (d.database_name = ANY(r.dbs)))
		ORDER BY 3::int4', true),
	(62, 'Q', E'
	WITH restricted_dbs AS (
		SELECT s.id, pem.db_escaped_string_to_array(COALESCE(o.database_restriction, oa.database_restriction)) AS dbs
	FROM
        pem.server s
        LEFT OUTER JOIN pg_catalog.pg_roles owner ON (owner.oid = s.owner)
        LEFT OUTER JOIN pem.server_option o ON (s.id = o.server_id AND o.pem_user = current_user)
        LEFT OUTER JOIN pem.server_option oa
                ON (o.id IS NULL AND s.id = oa.server_id AND
                        (owner.rolname = oa.pem_user OR (owner.rolname IS NULL AND oa.pem_user IS NULL)))
	)
	SELECT
		procpid as "Session Id",
		usename as "User Name",
		(client_addr || '':'' || client_port) as "Source",
		database_name as "Database Name",
		CASE WHEN is_waiting = $$t$$ then $$Yes$$ ELSE $$No$$ END as "Waiting",
		backend_start AS "Backend Start",
		xact_start AS "Transaction Start",
		query_start AS "Query Start"
	FROM
		pemdata.session_info s
		LEFT OUTER JOIN restricted_dbs r ON (s.server_id = r.id)
	WHERE
		server_id = $1::int4 AND
		($2::boolean OR (CASE WHEN s.database_name != '''' THEN s.database_name NOT IN (''template0'', ''template1'') ELSE TRUE END)) AND
		(r.dbs IS NULL OR (s.database_name = ANY(r.dbs)))
		ORDER BY 3', true),

	(63, 'Q', E'
	WITH restricted_dbs AS (
	SELECT s.id, pem.db_escaped_string_to_array(COALESCE(o.database_restriction, oa.database_restriction)) AS dbs
	FROM
        pem.server s
        LEFT OUTER JOIN pg_catalog.pg_roles owner ON (owner.oid = s.owner)
        LEFT OUTER JOIN pem.server_option o ON (s.id = o.server_id AND o.pem_user = current_user)
        LEFT OUTER JOIN pem.server_option oa
                ON (o.id IS NULL AND s.id = oa.server_id AND
                        (owner.rolname = oa.pem_user OR (owner.rolname IS NULL AND oa.pem_user IS NULL)))
	)
	SELECT
	   pli.procpid AS "Session Id",
	   psi.usename AS "User Name",
	   (psi.client_addr || $$:$$ || psi.client_port) as "Source",
	   pli.database_name AS "Database Name",
	   CASE pli.lockgranted WHEN $$f$$ THEN $$Yes$$ ELSE $$No$$ END AS "Blocked",
	   CASE WHEN pli.lockgranted = $$f$$ THEN
		   (SELECT b.procpid
		   FROM pemdata.lock_info b
		   WHERE b.objid = pli.objid AND
				 b.objsubid IS NOT DISTINCT FROM pli.objsubid AND
				 b.objsubsubid IS NOT DISTINCT FROM pli.objsubsubid AND
				 b.lockgranted = $$t$$)
		   ELSE NULL END AS "Blocked By",
	   pli.locktype AS "Lock Type",
	   pli.objid AS "Object Id",
	   pli.lockmode AS "Mode",
	   cast(date_trunc($$second$$,psi.xact_start) AS timestamp) AS "Transaction Start"
	FROM
	   pemdata.lock_info pli JOIN
	   pemdata.session_info psi ON ( pli.procpid = psi.procpid )
	   LEFT OUTER JOIN restricted_dbs r ON ( pli.server_id = r.id )
	WHERE
	   pli.server_id = $1::int4 AND
	   ($2::boolean OR (CASE WHEN pli.database_name != '''' THEN pli.database_name NOT IN (''template0'', ''template1'') ELSE TRUE END)) AND
	   (r.dbs IS NULL OR (pli.database_name = ANY(r.dbs)))
	ORDER BY 3', true),
	(64, 'Q', E'
	SELECT
		wait_name AS "Wait Name",
		SUM(wait_count) AS "Total Wait Counts"
	FROM
		pemdata.session_waits
	WHERE
		server_id = $1::int4 AND
		dbname = $2::text
	GROUP BY wait_name
	ORDER BY "Total Wait Counts" DESC
	LIMIT 5', false),
	(66, 'Q', E'
	SELECT
		wait_name AS "Wait Name",
		SUM(total_wait_time)*1000 AS "Total Wait Time"
	FROM
		pemdata.session_waits
	WHERE
		server_id = $1::int4 AND
		dbname = $2::text
	GROUP BY wait_name
	ORDER BY "Total Wait Time" DESC
	LIMIT 5', false),
	(65, 'Q', E'
	SELECT
		dbname AS "Database Name",
		usename AS "User",
		wait_name AS "Wait Name",
		wait_count AS "Wait Count",
		(total_wait_time*1000)::numeric(30,2) AS "Time (ms)",
		(SELECT CASE WHEN SUM(total_wait_time) = 0 THEN 0
				ELSE (psw.total_wait_time*100/SUM(total_wait_time)) END
		 FROM pemdata.session_waits WHERE server_id = $1 AND dbname = $2)::numeric(5,2) AS "Wait Time (%)"
	FROM
		pemdata.session_waits psw
	WHERE
		server_id = $1::int4 AND
		dbname = $2::text', false),
	(67, 'Q', E'
	WITH restricted_dbs AS (
	SELECT s.id, pem.db_escaped_string_to_array(COALESCE(o.database_restriction, oa.database_restriction)) AS dbs
	FROM
        pem.server s
    LEFT OUTER JOIN pg_catalog.pg_roles owner ON (owner.oid = s.owner)
	LEFT OUTER JOIN pem.server_option o ON (s.id = o.server_id AND o.pem_user = current_user)
    LEFT OUTER JOIN pem.server_option oa
    ON (o.id IS NULL AND s.id = oa.server_id AND
    (owner.rolname = oa.pem_user OR (owner.rolname IS NULL AND oa.pem_user IS NULL)))
	)
	SELECT
		database_name,
		database_size_mb AS "Size (MB)"
	FROM
		pemdata.database_size d
	LEFT OUTER JOIN restricted_dbs r ON ( r.id = d.server_id )
	WHERE
		server_id = $1::int4 AND
		($2::boolean OR (CASE WHEN d.database_name != '''' THEN d.database_name NOT IN (''template0'', ''template1'') ELSE TRUE END)) AND
		(r.dbs IS NULL OR (d.database_name = ANY(r.dbs)))
	ORDER BY database_size_mb DESC
	LIMIT 5', true),
	(68, 'Q', E'
	SELECT
		tablespace_name,
		tablespace_size_mb
	FROM
		pemdata.tablespace_size
	WHERE
		server_id = $1::int4
	ORDER BY tablespace_size_mb DESC
	LIMIT 5
	', false),
	(69, 'Q', E'
	SELECT
		''Number of WAL files: ''||number_of_wal_files
	FROM
		pemdata.number_of_wal_files
	WHERE
		server_id = $1::int4', false),
	(70, 'Q', E'
	SELECT
		SUM(space_used_mb) AS used,
		SUM(space_available_mb) AS free
	FROM
		pemdata.disk_space
	WHERE
		agent_id = $1::int4', false),
	(71, 'Q', E'
	WITH restricted_dbs AS (
	SELECT s.id, pem.db_escaped_string_to_array(COALESCE(o.database_restriction, oa.database_restriction)) AS dbs
	FROM
        pem.server s
    LEFT OUTER JOIN pg_catalog.pg_roles owner ON (owner.oid = s.owner)
	LEFT OUTER JOIN pem.server_option o ON (s.id = o.server_id AND o.pem_user = current_user)
    LEFT OUTER JOIN pem.server_option oa
    ON (o.id IS NULL AND s.id = oa.server_id AND
    (owner.rolname = oa.pem_user OR (owner.rolname IS NULL AND oa.pem_user IS NULL)))
	)
	SELECT
		database_name AS "Database Name",
		database_size_mb AS "Database Size (MB)",
		tablespace_name AS "Tablespace Name"
	FROM
		pemdata.database_size d
		LEFT OUTER JOIN restricted_dbs r ON ( d.server_id = r.id )
	WHERE
		server_id = $1::int4 AND
		($2::boolean OR (CASE WHEN d.database_name != '''' THEN d.database_name NOT IN (''template0'', ''template1'') ELSE TRUE END)) AND
		(r.dbs IS NULL OR (d.database_name = ANY(r.dbs)))
	ORDER BY 2', true),
	(72, 'Q', E'
	SELECT
		tablespace_name AS "Tablespace Name",
		tablespace_size_mb "Tablespace Size (MB)"
	FROM
		remdata.tablespace_size
	WHERE
		server_id = $1::int4
	ORDER BY 2
	', false),
	(73, 'Q', E'
	SELECT
		file_system AS "File System",
		(size_mb::float/1024)::numeric(30,2) AS "Size (GB)",
		(space_used_mb::float/1024)::numeric(30,2) AS "Used (GB)",
		(space_available_mb::float/1024)::numeric(30,2) AS "Available (GB)",
		CASE WHEN size_mb = 0
		THEN 0
		ELSE (space_used_mb*100)/size_mb
		END
		AS "%Used",
		mount_point AS "Mounted On"
	FROM
		pemdata.disk_space
	WHERE
		agent_id = $1::int4
	ORDER BY 3::int4', false),
	(74, 'Q', E'
	SELECT
		wait_name AS "Wait Name",
		wait_count AS "Wait Counts"
		FROM
		pemdata.system_waits
	WHERE
		server_id = $1::int4
	ORDER BY "Wait Counts" DESC
	LIMIT 5
	', false),
	(75, 'Q', E'
	SELECT
		wait_name AS "Wait Name",
		total_wait*1000 AS "Total Wait Time (Secs)"
	FROM
		pemdata.system_waits
	WHERE
		server_id = $1::int4
	ORDER BY "Total Wait Time (Secs)" DESC
	LIMIT 5;
	', false),
	(76, 'Q', E'
	SELECT
		wait_name AS "Event",
		wait_count AS "Wait Count",
		(SELECT CASE WHEN SUM(wait_count) = 0 THEN 0
				ELSE (psw.wait_count*100/SUM(wait_count)) END
		 FROM pemdata.system_waits WHERE server_id = $1)::numeric(5,2) AS "Percent of Total",
		(total_wait*1000)::numeric(30,2) AS "Time Waited (ms)",
		(SELECT CASE WHEN SUM(total_wait) = 0 THEN 0
				ELSE (psw.total_wait*100/SUM(total_wait)) END
		 FROM pemdata.system_waits WHERE server_id = $1)::numeric(5,2) AS "Percent of Time Waited",
		(avg_wait*1000)::numeric(30,2) AS "Average Wait Time (ms)"
	FROM
		pemdata.system_waits psw
	WHERE
		server_id = $1::int4
	ORDER BY $2::int4', false),
	 (78, 'Q', E'
       SELECT
        $$Swap Total: $$||total_swap_memory_mb||$$MB $$||$$&#183;$$||$$ Swap Used: $$||total_swap_memory_mb-free_swap_memory_mb||$$MB$$
       FROM
        pemdata.memory_usage
       WHERE agent_id = $1::int4', false);

INSERT INTO pem.chart(id, cid, fid, type, level, name, owner, shared, ref_cnt, deleted, reload, summary, labels, params) VALUES

------------------------------------- Global Overview ------------------------------------
--  ID  CID FID TYPE  LEVEL       NAME                  OWN SHARED REF READY RELOAD SUMMARY LABELS PARAMS
	(1, 1,  1,  'B',  ARRAY[50], 'Global Status',       0, NULL,  1,  true, 50000,   NULL,
	ARRAY['Agents Up', 'Agents Down', 'Agents Unknown', 'Servers UP', 'Servers Down', 'Servers Unknown'], NULL),
	(2, 1,  2,  'TB', ARRAY[50], 'Agents Status Info',  0, NULL,  1,  true, 50000,   NULL,
	ARRAY['', 'Blackout', 'Name', 'Status', 'Alerts', 'Processed', 'Threads', 'CPU Utilisation (%)',
	'Memory Utilisation (%)', 'Swap Utilisation (%)', 'Disk Utilisation'], ARRAY['sort_index', 'sort_direction']),
	(3, 1,  3,  'TB', ARRAY[50], 'Servers Status Info', 0, NULL,  1,  true, 50000,   NULL,
	ARRAY['', 'Blackout', 'Name', 'Status', 'Connections', 'Alerts', 'Version'], ARRAY['sort_index', 'sort_direction']),
	(4, 1,  4,  'TB', ARRAY[50], 'Alerts Status Info',  0, NULL,  1,  true, 50000,   NULL,
	ARRAY['', 'Object Description', 'Alarm Type', 'Alert Name', 'Value', 'Database',
	'Schema', 'Package', 'Object', 'Additional Params', 'Additional Param Values', 'Alerting Since'], ARRAY['sort_index', 'sort_direction']);

INSERT INTO pem.bar_chart(cid, colors, yaxis, is_position_based) VALUES
	(1, ARRAY['#154FED', '#FF0000', '#FFFF00', '#154FED', '#FF0000', '#FFFF00'], '(#)', true);


INSERT INTO pem.chart(id, cid, fid, type, level, name, owner, shared, ref_cnt, deleted, reload, summary, labels, params) VALUES
--------------------------------------- Alerts Dashboard ---------------------------------------
--  ID  CID FID TYPE  LEVEL                      NAME              OWN SHARED REF DELETED RELOAD SUMMARY LABELS PARAMS
	(5, 2,  5,  'B',  ARRAY[50, 100, 200, 300, 400], 'Alerts Overview', 0,
	NULL,  1,  true, 50000,   NULL, ARRAY['High', 'Medium', 'Low', 'None'], ARRAY['agent_id', 'server_id', 'database_name', 'schema_name', 'show_sys_objects']),
	 (6, 2,  6,  'TB', ARRAY[50, 100, 200, 300, 400], 'Alerts Details',  0, NULL, 1,  true, 50000,   NULL, ARRAY['','Ack''ed','Alert Type','Name','Value','Agent ID','Agent','Server ID','Server','Database','Schema','Package','Object','Additional Params','Additional Param Values','Alerting Since','Object Type','Display Name'], ARRAY['agent_id', 'database_name', 'schema_name','show_sys_objects']),
	 (7, 2,  7,  'TB', ARRAY[50, 100, 200, 300, 400], 'Alerts Errors',   0, NULL,  1,  true, 50000,   NULL,  ARRAY['','Alert Type','Name','Value','Agent ID','Agent','Server ID','Server','Database','Schema','Package','Object','Error Message','Object Type','Display Name'], ARRAY['agent_id', 'database_name', 'schema_name','show_sys_objects']),

-- --------------------------------- Audit Logs Dashboard -----------------------------------
-- -- TODO:: Need to think about the filter and scroll to load more data
-- --  ID  CID FID TYPE  LEVEL               NAME          OWN SHARED REF DELETED RELOAD SUMMARY LABELS PARAMS
--	(8, 3, 8, 'TB', ARRAY[50, 100, 200], 'Audit Logs', 0,  NULL,  1,  true, 50000,   NULL, NULL, NULL),
--
-- ------------------------------------- Database Dashboard ------------------------------------------
-- --   ID  CID FID   TYPE  LEVEL       NAME                        OWN SHARED REF DELETED RELOAD SUMMARY LABELS
	( 9, 4,     9, 'TE', ARRAY[300], 'Storage Details',          0,  NULL,  1,  true, 50000,   NULL, NULL, ARRAY['server_id', 'database_name']),
	(10, 4,    10,  'B', ARRAY[300], 'Storage',                  0,  NULL,  1,  true, 50000,      9, ARRAY['Object #'], ARRAY['server_id', 'database_name', 'show_sys_objects']),
	(11, 4,  NULL,  'L', ARRAY[300], 'Users Activity',           0,  NULL,  1,  true, 50000,   NULL, NULL, NULL),
	(12, 4,    12, 'TE', ARRAY[200], 'Connection Details',       0,  NULL,  1,  true, 50000,   NULL, NULL, ARRAY['server_id']),
	(13, 4,    13,  'P', ARRAY[300], 'Connection Overview',      0,  NULL,  1,  true, 50000,     12, ARRAY['Total Connections', 'Idle Connections'], ARRAY['server_id', 'database_name']),
	(17, 4,  NULL, 'TB', ARRAY[300], 'HOT Tables',               0,  NULL,  1,  true, 50000,   NULL, ARRAY['Schema', 'Table Name', 'Scans', 'Rows Read', 'Index Scans', 'Index Rows Read', 'Rows Inserted', 'Rows Updated', 'Rows Deleted', 'Hot Rows Updated', 'Total Rows', 'Dead Rows'], NULL),

--
-- -------------------------------------- IO Analysis Dashboard --------------------------------------------
--  ID   CID FID   TYPE  LEVEL       NAME                      OWN SHARED REF DELETED RELOAD SUMMARY LABELS PARAMS
	(18, 5,    18, 'TE', ARRAY[300], 'Database I/O Hit/Read Details',  0,  NULL,  1,  true, 50000,   NULL, NULL, ARRAY['server_id', 'database_name']),
	(19, 5,  NULL,  'L', ARRAY[300], 'Database I/O Hit/Read Stats',    0,  NULL,  1,  true, 50000,     18, NULL, NULL),
-- --  DOUBT:
-- --  + Why do we have two different charts for same work (found in the
-- --    database dashboard)?
	(21, 11,    21, 'TE', ARRAY[300], 'Rows Activity Details',           0,  NULL,  1,  true, 50000,   NULL, NULL,ARRAY['server_id', 'database_name']),
	(22, 5,    22, 'TE', ARRAY[200], 'Check-points Details',           0,  NULL,  1,  true, 50000,   NULL, NULL, ARRAY['server_id']),
	(23, 5,  NULL,  'L', ARRAY[200], 'Check-points Activity',          0,  NULL,  1,  true, 50000,     22, NULL, NULL),
	(24, 5,    24,  'B', ARRAY[300], 'Top 5 Scaned Tables',            0,  NULL,  1,  true, 50000,   NULL, NULL, ARRAY['server_id', 'database_name', 'show_sys_objects']),
	(25, 5,    25,  'B', ARRAY[300], 'Top 5 Scaned Indexes',           0,  NULL,  1,  true, 50000,   NULL, NULL, ARRAY['server_id', 'database_name', 'show_sys_objects']),
	(79, 5, NULL, 'TB', ARRAY[300], 'Top 20 Index Activities',			0, NULL, 1, true, 50000, 	NULL, ARRAY['Schema', 'Index Name', 'Index Scans', 'Index Tuple Read', 'Index Tuple Fetch', 'Index Blocks Read', 'Index Blocks Hit'], NULL),

--
-- ----------------------------------- Server Memory Dashboard -------------------------------------
--  ID   CID FID   TYPE  LEVEL       NAME                      OWN SHARED REF DELETED RELOAD SUMMARY LABELS PARAMS
	(26, 6,   26, 'TE', ARRAY[200], 'Memory Acitivity Details', 0,  NULL,  1,  true, 50000,   NULL, NULL, ARRAY['server_id', 'show_sys_objects']),
	(27, 6, NULL,  'L', ARRAY[200], 'Memory Activity',          0,  NULL,  1,  true, 50000,     26, NULL, NULL),
	(28, 6,   28,  'P', ARRAY[200], 'Memory Configuration',     0,  NULL,  1,  true, 50000,   NULL, NULL, ARRAY['server_id']),
-- 	-- Host Memory informatoin
	(29, 7,   NULL,  'L', ARRAY[100], 'Host Memory Activity',     0,  NULL,  1,  true, 50000,   NULL, NULL, NULL),
	(78, 7,   78,  'TE', ARRAY[100], 'Host Memory Details', 0, NULL, 1, true, 50000, NULL, NULL, ARRAY['agent_id']),
	(30, 7,   30,  'P', ARRAY[100], 'Host Memory Information',  0,  NULL,  1,  true, 50000,   78, ARRAY['Used Memory', 'Free Memory'], ARRAY['agent_id']),
--
-- --------------------------------- Object Activity Dashboard ----------------------------------
--  ID   CID FID   TYPE  LEVEL       NAME                      OWN SHARED REF DELETED RELOAD SUMMARY LABELS PARAMS
	(31, 8,   31,  'B', ARRAY[300], 'Top 5 Largest Tables',  0,  NULL,  1,  true, 50000,   NULL, NULL, ARRAY['server_id', 'database_name', 'show_sys_objects']),
	(32, 8,   32,  'B', ARRAY[300], 'Top 5 Largest Indexes', 0,  NULL,  1,  true, 50000,   NULL, NULL, ARRAY['server_id', 'database_name', 'show_sys_objects']),
	(33, 8, NULL, 'TB', ARRAY[300], 'Object Activities',     0,  NULL,  1,  true, 50000,   NULL, ARRAY['Schema',
     'Object Name','Scans','Rows Read','Index Scans','Index Rows Read','Rows Inserted','Rows Updated','Rows Deleted','Hot Rows Updated','Total Rows','Dead Rows'], NULL),
	(34, 8, 34, 'TB', ARRAY[300], 'Object Storage',        0,  NULL,  1,  true, 50000,   NULL, ARRAY['Schema', 'Object', 'Object Type', 'Table Size(MB)', 'Index Size(MB)', 'Total(MB)'], ARRAY['server_id',  'database_name', 'show_sys_objects']),
--
-- ---------------------------------- Operating System Dashboard -----------------------------------
--  ID   CID FID   TYPE  LEVEL       NAME                      OWN SHARED REF DELETED RELOAD SUMMARY LABLES PARAMS
-- 	-- CPU
	(35, 9,    35, 'TE', ARRAY[100], 'CPU Stats Details',      0,  NULL,  1,  true, 50000,   NULL, NULL, ARRAY['agent_id']),
	(36, 9,  NULL,  'L', ARRAY[100], 'CPU Stats',              0,  NULL,  1,  true, 50000,     35, NULL, NULL),
-- 	-- STORAGE
	(37, 9,    37,  'P', ARRAY[100], 'Storage Stats',          0,  NULL,  1,  true, 50000,   NULL, ARRAY['Used', 'Free'], ARRAY['agent_id']),
-- 	-- MEMORY
	(38, 9,    38, 'TE', ARRAY[100], 'Memory Stats Details',   0,  NULL,  1,  true, 50000,   NULL, NULL, ARRAY['agent_id']),
	(39, 9,    39,  'L', ARRAY[100], 'Memory Stats',           0,  NULL,  1,  true, 50000,     38, ARRAY['Used Memory', 'Free Memory'], ARRAY['agent_id']),
-- 	-- PROCESSES
	(40, 9,  NULL,  'L', ARRAY[100], 'Process Stats',          0,  NULL,  1,  true, 50000,   NULL, ARRAY['Process Count'], NULL),
-- 	-- Disk Space Utilization
	(42, 9,  NULL,  'L', ARRAY[100], 'Disk Space Utilization', 0,  NULL,  1,  true, 50000,   NULL, ARRAY['Used (MB)'], NULL),
-- 	-- I/O
	(43, 9,  NULL,  'L', ARRAY[100], 'I/O Stats',              0,  NULL,  1,  true, 50000,   NULL, ARRAY['Blocks Read', 'Blocks Written'], NULL),
-- 	-- Opering System
	(44, 9,    44, 'TB', ARRAY[100], 'Host Details',           0,  NULL,  1,  true, 50000,   NULL, ARRAY['File System', 'Size (GB)', 'Used (GB)', 'Available (GB)', '%Used', 'Mounted On'], ARRAY['agent_id']),

-- 	-- Network
	(45, 9,  NULL,  'L', ARRAY[100], 'Network Packet Stats',   0,  NULL,  1,  true, 50000,   NULL, ARRAY['Packets Received','Packets Sent'], NULL),
	(46, 9,    46, 'TE', ARRAY[100], 'Network Bandwidth Details',      0,  NULL,  1,  true, 50000,   NULL, NULL, ARRAY['agent_id']),
	(47, 9,  NULL,  'L', ARRAY[100], 'Network Traffic Stats',  0,  NULL,  1,  true, 50000,   46, ARRAY['Data Received/sec','Data Sent/sec'], NULL),
--
-- ------------------------------- Probe Logs Dashboard --------------------------------
-- --  ID   CID FID   TYPE  LEVEL       NAME          OWN SHARED REF DELETED RELOAD SUMMARY LABELS
-- -- TODO:: Need to think about the scroll to load more data
-- Using the old code currently
--	(48, 10, 48, 'TB', ARRAY[100], 'Probe Logs', 0,  NULL,  1,  true, 50000,   NULL, ARRAY['Timestamp', 'Probe Name', 'Error Message'], ARRAY['agent_id', 'show_system_objects']),
--
-- ------------------------------------ Server Logs Dashboard -------------------------------------
-- --  ID   CID FID   TYPE  LEVEL                 NAME           OWN SHARED REF DELETED RELOAD SUMMARY LABELS
-- -- TODO:: Need to think about the scroll to load more data
-- Using the old code currently
--	(49, 11, 49, 'TB', ARRAY[50, 100, 200], 'Server Logs', 0,  NULL,  1,  true, 50000,   NULL, ARRAY['agent_id', 'server_id', 'database_name']),
--
-- -------------------------------------- Server Analysis Dashboard -------------------------------------
-- --  ID   CID FID   TYPE  LEVEL       NAME                           OWN SHARED REF DELETED RELOAD SUMMARY LABELS PARAMS
	(50, 11,   NULL,  'L', ARRAY[200], 'Databases Size',              0,  NULL,  1,  true, 50000, NULL, NULL, ARRAY['server_id', 'agent_id']),
	(51, 11, NULL,  'L', ARRAY[200], 'Tablespaces Size',            0,  NULL,  1,  true, 50000,   NULL, NULL, NULL),
	(52, 11,   52, 'TE', ARRAY[200], 'Shared Buffer Details',       0,  NULL,  1,  true, 50000,   NULL, NULL, ARRAY['server_id', 'show_sys_objects']),
	(53, 11, NULL,  'L', ARRAY[200], 'Shared Buffer',               0,  NULL,  1,  true, 50000,     52, ARRAY['Blocks Hit', 'Blocks Read'], NULL),
	(54, 11,   54, 'TE', ARRAY[200], 'User Activity Details',       0,  NULL,  1,  true, 50000,   NULL, NULL, ARRAY['server_id']),
	(55, 11, NULL,  'L', ARRAY[200], 'User Activity',               0,  NULL,  1,  true, 50000, 	  54, ARRAY['Total Connections', 'Idle Connections'], NULL),
	(56, 11,   56, 'TE', ARRAY[200], 'Connection Overview Details', 0,  NULL,  1,  true, 50000,   NULL, NULL, ARRAY['server_id']),
	(57, 11,   57,  'P', ARRAY[200], 'Connection Overview',         0,  NULL,  1,  true, 50000,     56, ARRAY['Total Connections', 'Idle Connections'], ARRAY['server_id']),
	(58, 11,   NULL,  'L', ARRAY[100], 'Disk Information',            0,  NULL,  1,  true, 50000,   NULL, ARRAY['Blocks Read', 'Blocks Written'], NULL),
	(59, 11,   NULL,  'L', ARRAY[200, 300], 'Rows Activity',               0,  NULL,  1,  true, 50000,   NULL, ARRAY['Rows Read', 'Rows Inserted', 'Rows Updated', 'Rows Deleted'], NULL),
	(60, 11,   NULL,  'L', ARRAY[200, 300], 'Commits/Rollbacks',           0,  NULL,  1,  true, 50000,   NULL, ARRAY['Commits', 'Rollbacks'], NULL),
	(61, 11, 	61, 'TB', ARRAY[200], 'Databases Analysis',          0,  NULL,  1,  true, 50000,   NULL, ARRAY[ 'Database', 'Connections', 'TX Committed', 'TX Rolled Back', 'Blocks Hit', 'Blocks Read', 'Tuples Fetched', 'Tuples Returned', 'Tuples Inserted', 'Tuples Updated', 'Tuples Deleted'], ARRAY['server_id', 'show_sys_objects']),
--
-- ---------------------------- Session Activity Dashboard ----------------------------
-- --  ID   CID FID   TYPE  LEVEL  NAME              OWN SHARED REF DELETED RELOAD SUMMARY LABELS PARAMS
	(62, 12, 62, 'TB', ARRAY[200], 'Work Load',      0,  NULL,  1,  true, 50000,   NULL, ARRAY['Session Id', 'User Name', 'Source', 'Database Name', 'Waiting', 'Backend Start', 'Transaction Start', 'Query Start'], ARRAY['server_id', 'show_sys_objects']),
	(63, 12, 63, 'TB', ARRAY[200], 'Locks Activity', 0,  NULL,  1,  true, 50000,   NULL, ARRAY[ 'Session Id', 'User Name', 'Source', 'Database Name', 'Blocked', 'Blocked By', 'Lock Type', 'Object Id', 'Mode', 'Transaction Start'], ARRAY['server_id', 'show_sys_objects']),
--
-- ----------------------------------- Session Wait Dashboard ------------------------------------
-- --  ID   CID FID   TYPE  LEVEL  NAME                         OWN SHARED REF DELETED RELOAD SUMMARY LABELS PARAMS
	(64, 12,   64,  'P', ARRAY[300], 'Number of session waits',   0, NULL, 1, true, 50000,   NULL, NULL, ARRAY['server_id', 'database_name']),
	(65, 12,   65, 'TB', ARRAY[300], 'Session wait Details Table', 0, NULL, 1, true, 50000,   NULL, ARRAY['Database Name', 'User', 'Wait Name', 'Wait Count', 'Time (ms)', 'Wait Time (%)'], ARRAY['server_id', 'database_name']),
	(66, 12,   66,  'P', ARRAY[300], 'Session time waits',        0, NULL, 1, true, 50000,   NULL, ARRAY['Wait Name', 'Total Wait Time'], ARRAY['server_id', 'database_name']),

-- -------------------------------------- Storage Analysis Dashboard --------------------------------------
-- --  ID   CID FID   TYPE  LEVEL  NAME                                  OWN SHARED REF DELETED RELOAD SUMMARY LABELS PARAMS
	(67, 13,   67,  'P', ARRAY[200], 'Databases Storage Overview',    0,  NULL,  1,  true, 50000,   NULL, NULL, ARRAY['server_id','show_sys_objects']),
	(68, 13,   68,  'P', ARRAY[200], 'Tablespaces Storage Overview',  0,  NULL,  1,  true, 50000,   NULL, NULL, ARRAY['server_id']),
	(69, 13,   69, 'TE', ARRAY[200], 'Host Storage Overview Details', 0,  NULL,  1,  true, 50000,   NULL, NULL, ARRAY['server_id']),
	(70, 13,   70,  'P', ARRAY[100], 'Host Storage Overview',         0,  NULL,  1,  true, 50000,     69, ARRAY['used', 'free'], ARRAY['agent_id']),
	(71, 13,   71, 'TB', ARRAY[200], 'Databases Storage Details',     0,  NULL,  1,  true, 50000,   NULL, ARRAY['Database Name', 'Database Size (MB)', 'Tablespace Name'], ARRAY['server_id', 'show_sys_objects']),
	(72, 13,   72, 'TB', ARRAY[200], 'Tablespaces Storage Details',   0,  NULL,  1,  true, 50000,   NULL, ARRAY['Tablespace Name', 'Tablespace Size (MB)'], ARRAY['server_id']),
	(73, 13,   73, 'TB', ARRAY[100], 'Host Storage Details',          0,  NULL,  1,  true, 50000,   NULL, ARRAY['File System', 'Size (GB)', 'Used (GB)', 'Available (GB)', '%Used', 'Mounted On'], ARRAY['agent_id']),

-- ------------------------------------- System Wait Dashboard -------------------------------------
-- --  ID   CID FID   TYPE  LEVEL  NAME                           OWN SHARED REF DELETED RELOAD SUMMARY LABELS PARAMS
	(74, 14,   74,  'P', ARRAY[200], 'Number of System Waits', 0,  NULL,  1,  true, 50000,   NULL, ARRAY['Wait Name', 'Wait Counts'], ARRAY['server_id']),
	(75, 14,   75,  'P', ARRAY[200], 'Wait Time',              0,  NULL,  1,  true, 50000,   NULL, ARRAY['Wait Name', 'Total Wait Time (Secs)'], ARRAY['server_id']),
	(76, 14,   76, 'TB', ARRAY[200], 'Wait Details',           0,  NULL,  1,  true, 50000,   NULL, NULL, ARRAY['server_id', 'sort_index']);


--Alerts Overview
INSERT INTO pem.bar_chart(cid, colors, yaxis, is_position_based) VALUES
	(5, ARRAY['#FF0000', '#FFFF90', '#3cb371', '#154FED'], 'Count', true);
-- ------------------------------------- Database Dashboard ------------------------------------------

INSERT INTO pem.bar_chart(cid, colors, yaxis, is_position_based) VALUES
	(10, ARRAY['#154FED', '#FF0000', '#FFFF00', '#154FED', '#FF0000', '#FFFF00'], 'Object #', false);

INSERT INTO pem.line_chart (cid, type, yaxis) VALUES (11, 'M', '(#)');
INSERT INTO pem.metrices_chart (cid, time_span) VALUES (11, '7 days'::interval);
INSERT INTO pem.chart_metric (cid, mid, tbl, metrices, glimit, agg_func) VALUES
	(11, 1, 'database_statistics', ARRAY['numbackends', 'idle_backends'], 2,
	ARRAY['A', 'A']);

INSERT INTO pem.pie_chart (cid, colors, type, is_vertical) VALUES (13, ARRAY['#23FCBA','#47ABCF'], 'P', false);

-- Hot tables
INSERT INTO pem.tbl_chart(cid, type) VALUES (17, 'D');
INSERT INTO pem.data_chart(cid, tbl, metrices, orderby, glimit, r_sys_obj) VALUES(17, 'table_statistics',
ARRAY['schema_name', 'table_name', 'seq_scan', 'seq_tup_read', 'idx_scan', 'idx_tup_fetch', 'n_tup_ins', 'n_tup_upd', 'n_tup_del', 'n_tup_hot_upd', 'n_live_tup', 'n_dead_tup'], ARRAY['seq_scan'], 25, false);


-- Database I/O Hit/Read Stats
INSERT INTO pem.line_chart (cid, type, yaxis) VALUES (19, 'M', '(#)');
INSERT INTO pem.metrices_chart (cid, time_span) VALUES (19, '7 days'::interval);
INSERT INTO pem.chart_metric (cid, mid, tbl, metrices, glimit, agg_func, params) VALUES
	(19, 1, 'database_statistics', ARRAY['blks_hit_pit', 'blks_read_pit'], 2,
	ARRAY['A', 'A'], NULL);
-- Check-points Activity
INSERT INTO pem.line_chart (cid, type, yaxis) VALUES (23, 'M', '(#)');
INSERT INTO pem.metrices_chart (cid, time_span) VALUES (23, '7 days'::interval);
INSERT INTO pem.chart_metric (cid, mid, tbl, metrices, glimit, agg_func, params) VALUES
	(23, 1, 'background_writer_statistics', ARRAY['checkpoints_timed_pit', 'checkpoints_req_pit'], 2,
	ARRAY['A', 'A'], NULL);

-- Top 5 Scaned Tables
INSERT INTO pem.bar_chart(cid, colors, yaxis, is_position_based) VALUES
(24, ARRAY['#47678E', '#CB4B4B', '#EBA525', '#F10e0e', '#9440ED'], '# Scans', false);

-- Top 5 Scaned Indexes
INSERT INTO pem.bar_chart(cid, colors, yaxis, is_position_based) VALUES
(25, ARRAY['#47678E', '#CB4B4B', '#EBA525', '#F10e0e', '#9440ED'], '# Scans', false);

-- Memory Activity
INSERT INTO pem.line_chart (cid, type, yaxis) VALUES (27, 'M', '(#)');
INSERT INTO pem.metrices_chart (cid, time_span) VALUES (27, '7 days'::interval);
INSERT INTO pem.chart_metric (cid, mid, tbl, metrices, glimit,
	agg_func, params) VALUES
	(27, 1, 'database_statistics', ARRAY['blks_hit_pit', 'blks_read_pit'], 2, ARRAY['A', 'A'], NULL);

-- Memory Configuration
INSERT INTO pem.pie_chart (cid, colors, type, is_vertical) VALUES(28, NULL, 'P', true);

-- 	-- Host Memory information
INSERT INTO pem.line_chart (cid, type, yaxis) VALUES (29, 'M', '(MB)');
INSERT INTO pem.metrices_chart (cid, time_span) VALUES (29, '7 days'::interval);
INSERT INTO pem.chart_metric (cid, mid, tbl, metrices, glimit,
	agg_func, params) VALUES
	(29, 1, 'memory_usage', ARRAY['free_ram_memory_mb', 'total_ram_memory_mb'], 2, ARRAY['A', 'A'], NULL);

-- Host Memory Information
INSERT INTO pem.pie_chart (cid, colors, type, is_vertical) VALUES(30, NULL, 'P', false);

-- --------------------------------- Object Activity Dashboard
-- Top 5 Largest Tables
 INSERT INTO pem.bar_chart(cid, colors, yaxis, is_position_based) VALUES
 (31, ARRAY['#47678E', '#CB4B4B', '#EBA525', '#F10e0e', '#9440ED'], 'Table Size (MB)', false);
-- Top 5 Largest Indexes
 INSERT INTO pem.bar_chart(cid, colors, yaxis, is_position_based) VALUES
 (32, ARRAY['#47678E', '#CB4B4B', '#EBA525', '#F10e0e', '#9440ED'], 'Index Size (MB)', false);

--Object Activities
INSERT INTO pem.tbl_chart(cid, type) VALUES (33, 'D');
INSERT INTO pem.data_chart(cid, tbl, metrices, orderby, glimit, r_sys_obj) VALUES(33, 'table_statistics', ARRAY['schema_name', 'table_name', 'seq_scan','seq_tup_read', 'idx_scan', 'idx_tup_fetch', 'n_tup_ins', 'n_tup_upd', 'n_tup_del', 'n_tup_hot_upd', 'n_live_tup', 'n_dead_tup'], ARRAY['seq_scan'], 20, false);

--Index Activities
INSERT INTO pem.tbl_chart(cid, type) VALUES(79, 'D');
INSERT INTO pem.data_chart(cid, tbl, metrices, orderby, glimit, r_sys_obj) VALUES(79, 'index_statistics', ARRAY['schema_name', 'index_name', 'idx_scan', 'idx_tup_read', 'idx_tup_fetch', 'idx_blks_read', 'idx_blks_hit'], ARRAY['idx_scan'], 20, false);

-- CPU Load Stats
INSERT INTO pem.line_chart (cid, type, yaxis) VALUES (36, 'M', '(%)');
INSERT INTO pem.metrices_chart (cid, time_span, agg_int) VALUES (36, '14 days'::interval, 60);
INSERT INTO pem.chart_metric (cid, mid, tbl, metrices, glimit,
	gorderby, agg_func) VALUES
	(36, 1, 'cpu_usage', ARRAY['load_percentage'], 64,
	ARRAY['core_id'], ARRAY['A']);

-- Storage Stats
INSERT INTO pem.pie_chart (cid, colors, type, is_vertical) VALUES(37, NULL, 'P', false);

-- Memory Stats
INSERT INTO pem.line_chart (cid, type, yaxis) VALUES (39, 'M', '(MB)');
INSERT INTO pem.metrices_chart (cid, time_span) VALUES (39, '7 days'::interval);
INSERT INTO pem.chart_func(id, type, func, r_sys_obj) VALUES
	(39, 'Q', E'SELECT idx, label, ''Date('' || (EXTRACT(EPOCH FROM agg_time) * 1000)::numeric(40, 0)::text || '')'', agg_val FROM pem.generate_host_memory_chart_data($1::int4) ORDER BY idx, agg_time', false);

-- Process Stats
INSERT INTO pem.line_chart (cid, type, yaxis) VALUES (40, 'M', '(#)');
INSERT INTO pem.metrices_chart (cid, time_span) VALUES (40, '7 days'::interval);
INSERT INTO pem.chart_metric (cid, mid, tbl, metrices, glimit,
	gorderby, agg_func) VALUES
	(40, 1, 'os_statistics', ARRAY['total_process_count'], 1,
	NULL, ARRAY['A']);

-- Disk Space Utilization
INSERT INTO pem.line_chart (cid, type, yaxis) VALUES (42, 'M', '(MB)');
INSERT INTO pem.metrices_chart (cid, time_span) VALUES (42, '7 days'::interval);
INSERT INTO pem.chart_metric (cid, mid, tbl, metrices, glimit,
	gorderby, agg_func) VALUES
	(42, 1, 'disk_space', ARRAY['space_used_mb'], 8,
	ARRAY['mount_point'], ARRAY['A']);

-- I/O Stats
INSERT INTO pem.line_chart (cid, type, yaxis) VALUES (43, 'M', '(#)');
INSERT INTO pem.metrices_chart (cid, time_span) VALUES (43, '7 days'::interval);
INSERT INTO pem.chart_metric (cid, mid, tbl, metrices, glimit,
	gorderby, agg_func) VALUES
	(43, 1, 'io_analysis', ARRAY['blks_read_pit', 'blks_wrtn_pit'], 2,
	NULL, ARRAY['A', 'A']);

-- Host Details
INSERT INTO pem.tbl_chart(cid, type) VALUES (44, 'D');

-- Network Packet Stats
INSERT INTO pem.line_chart (cid, type, yaxis) VALUES (45, 'M', '#');
INSERT INTO pem.metrices_chart (cid, time_span) VALUES (45, '7 days'::interval);
INSERT INTO pem.chart_metric (cid, mid, tbl, metrices, glimit,
	gorderby, agg_func) VALUES
	(45, 1, 'network_statistics', ARRAY['packets_received_pit', 'packets_sent_pit'], 2,
	NULL, ARRAY['A', 'A']);

-- Network Traffic Stats
INSERT INTO pem.line_chart (cid, type, yaxis) VALUES (47, 'M', '(KB)');
INSERT INTO pem.metrices_chart (cid, time_span) VALUES (47, '7 days'::interval);
INSERT INTO pem.chart_metric (cid, mid, tbl, metrices, glimit,
	gorderby, agg_func) VALUES
	(47, 1, 'network_statistics', ARRAY['receive_bytes_kb_pit', 'sent_bytes_kb_pit'], 2,
	NULL, ARRAY['A', 'A']);

-- -------------------------------------- Server Analysis Dashboard
INSERT INTO pem.line_chart (cid, type, yaxis) VALUES (50, 'M', '(MB)');
INSERT INTO pem.metrices_chart (cid, time_span) VALUES (50, '7 days'::interval);
INSERT INTO pem.chart_metric (cid, mid, tbl, metrices, glimit,
	gorderby, agg_func) VALUES
	(50, 1, 'database_size', ARRAY['database_size_mb'], 1,
	ARRAY['database_name'], ARRAY['A']);


-- Tablespaces Size
INSERT INTO pem.line_chart (cid, type, yaxis) VALUES (51, 'M', '(MB)');
INSERT INTO pem.metrices_chart (cid, time_span) VALUES (51, '7 days'::interval);
INSERT INTO pem.chart_metric (cid, mid, tbl, metrices, glimit,
	gorderby, agg_func) VALUES
	(51, 1, 'tablespace_size', ARRAY['tablespace_size_mb'], 1,
	ARRAY['tablespace_name'], ARRAY['A']);

-- Shared Buffer
INSERT INTO pem.line_chart (cid, type, yaxis) VALUES (53, 'M', '(#)');
INSERT INTO pem.metrices_chart (cid, time_span) VALUES (53, '7 days'::interval);
INSERT INTO pem.chart_metric (cid, mid, tbl, metrices, glimit,
	gorderby, agg_func) VALUES
	(53, 1, 'database_statistics', ARRAY['blks_hit_pit', 'blks_read_pit'], 2,
	NULL, ARRAY['A', 'A']);

--User Activity
INSERT INTO pem.line_chart (cid, type, yaxis) VALUES (55, 'M', '(#)');
INSERT INTO pem.metrices_chart (cid, time_span) VALUES (55, '7 days'::interval);
INSERT INTO pem.chart_metric (cid, mid, tbl, metrices, glimit,
	gorderby, agg_func) VALUES
	(55, 1, 'database_statistics', ARRAY['numbackends', 'idle_backends'], 2,
	NULL, ARRAY['A', 'A']);

-- Connection Overview
INSERT INTO pem.pie_chart (cid, colors, type, is_vertical) VALUES(57, NULL, 'P', false);

-- Disk Information
INSERT INTO pem.line_chart (cid, type, yaxis) VALUES (58, 'M', '(#)');
INSERT INTO pem.metrices_chart (cid, time_span) VALUES (58, '7 days'::interval);
INSERT INTO pem.chart_metric (cid, mid, tbl, metrices, glimit,
	gorderby, agg_func) VALUES
	(58, 1, 'io_analysis', ARRAY['blks_read', 'blks_wrtn'], 2,
	NULL, ARRAY['A', 'A']);

-- Rows Activity
INSERT INTO pem.line_chart (cid, type, yaxis) VALUES (59, 'M', 'Rows Returned/Inserted/Updated/Deleted (#)');
INSERT INTO pem.metrices_chart (cid, time_span) VALUES (59, '7 days'::interval);
INSERT INTO pem.chart_metric (cid, mid, tbl, metrices, glimit,
	gorderby, agg_func) VALUES
	(59, 1, 'database_statistics', ARRAY['tup_returned_pit', 'tup_inserted_pit', 'tup_updated_pit', 'tup_deleted_pit'], 4,
	NULL, ARRAY['A', 'A', 'A', 'A']);

-- Commits/Rollbacks
INSERT INTO pem.line_chart (cid, type, yaxis) VALUES (60, 'M', 'Commits/Rollbacks (#)');
INSERT INTO pem.metrices_chart (cid, time_span) VALUES (60, '7 days'::interval);
INSERT INTO pem.chart_metric (cid, mid, tbl, metrices, glimit,
	gorderby, agg_func) VALUES
	(60, 1, 'database_statistics', ARRAY['xact_commit_pit', 'xact_rollback_pit'], 2,
	ARRAY['database_name'], ARRAY['A', 'A']);

-- Database Analysis
INSERT INTO pem.tbl_chart (cid, type) VALUES (61, 'D');

-- ---------------------------- Session Activity Dashboard ----------------------------
INSERT INTO pem.tbl_chart (cid, type) VALUES (62, 'D');
INSERT INTO pem.tbl_chart (cid, type) VALUES (63, 'D');

-- ----------------------------------- Session Wait Dashboard ------------------------------------
INSERT INTO pem.pie_chart (cid, colors, type, is_vertical) VALUES (64, NULL, 'P', true);
INSERT INTO pem.tbl_chart (cid, type) VALUES (65, 'D');
INSERT INTO pem.pie_chart (cid, colors, type, is_vertical) VALUES (66, NULL, 'P', true);

-- -------------------------------------- Storage Analysis Dashboard -------------------------------------
INSERT INTO pem.pie_chart (cid, colors, type, is_vertical) VALUES (67, NULL, 'P', true);
INSERT INTO pem.pie_chart (cid, colors, type, is_vertical) VALUES (68, NULL, 'P', true);
INSERT INTO pem.pie_chart (cid, colors, type, is_vertical) VALUES (70, NULL, 'P', false);
INSERT INTO pem.tbl_chart (cid, type) VALUES (71, 'D');
INSERT INTO pem.tbl_chart (cid, type) VALUES (72, 'D');
INSERT INTO pem.tbl_chart (cid, type) VALUES (73, 'D');

-- ------------------------------------- System Wait Dashboard -------------------------------------
INSERT INTO pem.pie_chart (cid, colors, type, is_vertical) VALUES (74, NULL, 'P', true);
INSERT INTO pem.pie_chart (cid, colors, type, is_vertical) VALUES (75, NULL, 'P', true);
INSERT INTO pem.tbl_chart (cid, type) VALUES (76, 'D');

INSERT INTO pem.config (param, value, unit, datatype) VALUES ('deleted_charts_retention_time', '7', 'days', 'integer');

CREATE OR REPLACE FUNCTION pem.purge_deleted_charts()
RETURNS void AS $$
    -- Purge data from the pem.chart table
    DELETE FROM pem.chart
	WHERE deleted AND (ref_cnt = 0 OR (now() - deleted_time) >= ((SELECT value FROM pem.config WHERE param = 'deleted_charts_retention_time')||'days')::interval);
$$ LANGUAGE sql SECURITY DEFINER;

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

    -- Check if the job already exists (for purging deleted charts)
    SELECT jobid INTO job_id FROM pem.job WHERE jobname = 'Job purge the deleted charts' AND agent_id = agentid;

    IF (NOT FOUND) THEN
        -- Create data purging job.
        INSERT INTO pem.job(jobname, jobdesc, agent_id) VALUES('Job purge the deleted charts', 'This job runs periodically to purge the deleted charts.', agentid) RETURNING jobid INTO job_id;
    END IF;

    -- Check if the job step already exists.
    SELECT jstname INTO name FROM pem.jobstep WHERE jstname = 'Job purge the deleted charts' AND jstjobid = job_id;

    IF (NOT FOUND) THEN
        -- Create data purging step.
        INSERT INTO pem.jobstep(jstjobid, jstname, jstdesc, jstkind, jstcode, server_id, database_name) VALUES (job_id, 'Job purge the deleted charts','This job step runs periodically to purge the deleted charts (we do not clean them up immediately).', 's',
        'SELECT pem.purge_deleted_charts()', serverid, 'pem');
    END IF;

    -- Check if the job schedule already exists.
    SELECT jscname INTO name FROM pem.schedule WHERE jscname = 'Job purge the deleted charts' AND jscjobid = job_id;

    IF (NOT FOUND) THEN
        -- Create data purging schedule.
        INSERT INTO pem.schedule(jscjobid, jscname, jscdesc, jscminutes, jschours, jscweekdays, jscmonthdays, jscmonths) VALUES(job_id, 'Job purge the deleted charts', 'This job schedule runs periodically to purge the deletecd charts.', '{t,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f}', '{f,f,t,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f}','{t,t,t,t,t,t,t}', '{t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t}', '{t,t,t,t,t,t,t,t,t,t,t,t}');
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

    -- Check if the job already exists (for purging deleted charts)
    SELECT jobid INTO job_id FROM pem.job WHERE jobname = 'Job purge the deleted charts' AND agent_id = agentid;

    IF (NOT FOUND) THEN
        -- Create data purging job.
        INSERT INTO pem.job(jobname, jobdesc, agent_id) VALUES('Job purge the deleted charts', 'This job runs periodically to purge the deleted charts.', agentid) RETURNING jobid INTO job_id;
    END IF;

    -- Check if the job step already exists.
    SELECT jstname INTO name FROM pem.jobstep WHERE jstname = 'Job purge the deleted charts' AND jstjobid = job_id;

    IF (NOT FOUND) THEN
        -- Create data purging step.
        INSERT INTO pem.jobstep(jstjobid, jstname, jstdesc, jstkind, jstcode, server_id, database_name) VALUES (job_id, 'Job purge the deleted charts','This job step runs periodically to purge the deleted charts (we do not clean them up immediately).', 's',
        'SELECT pem.purge_deleted_charts()', serverid, 'pem');
    END IF;

    -- Check if the job schedule already exists.
    SELECT jscname INTO name FROM pem.schedule WHERE jscname = 'Job purge the deleted charts' AND jscjobid = job_id;

    IF (NOT FOUND) THEN
        -- Create data purging schedule.
        INSERT INTO pem.schedule(jscjobid, jscname, jscdesc, jscminutes, jschours, jscweekdays, jscmonthdays, jscmonths) VALUES(job_id, 'Job purge the deleted charts', 'This job schedule runs periodically to purge the deletecd charts.', '{t,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f}', '{f,f,t,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f}','{t,t,t,t,t,t,t}', '{t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t}', '{t,t,t,t,t,t,t,t,t,t,t,t}');
    END IF;
END;
$BODY$ LANGUAGE plpgsql;

GRANT USAGE ON pem.chart_catagory_id_seq TO pem_user;
GRANT USAGE ON pem.chart_func_id_seq TO pem_user;
GRANT USAGE ON pem.chart_id_seq TO pem_user;
GRANT USAGE ON pem.dashboard_id_seq TO pem_user;

GRANT ALL ON TABLE pem.chart_catagory TO pem_admin;
GRANT ALL ON TABLE pem.chart_func TO pem_admin;
GRANT ALL ON TABLE pem.chart TO pem_admin;
GRANT ALL ON TABLE pem.bar_chart TO pem_admin;
GRANT ALL ON TABLE pem.pie_chart TO pem_admin;
GRANT ALL ON TABLE pem.tbl_chart TO pem_admin;
GRANT ALL ON TABLE pem.line_chart TO pem_admin;
GRANT ALL ON TABLE pem.data_chart TO pem_admin;
GRANT ALL ON TABLE pem.history_chart TO pem_admin;
GRANT ALL ON TABLE pem.metrices_chart TO pem_admin;
GRANT ALL ON TABLE pem.chart_metric TO pem_admin;

GRANT ALL ON TABLE pem.dashboard TO pem_admin;
GRANT ALL ON TABLE pem.dashboard_section TO pem_admin;
GRANT ALL ON TABLE pem.dashboard_chart TO pem_admin;

GRANT SELECT ON TABLE pem.chart_catagory TO pem_user;
GRANT SELECT ON TABLE pem.chart_func TO pem_user;
GRANT SELECT ON TABLE pem.chart TO pem_user;
GRANT SELECT ON TABLE pem.bar_chart TO pem_user;
GRANT SELECT ON TABLE pem.pie_chart TO pem_user;
GRANT SELECT ON TABLE pem.tbl_chart TO pem_user;
GRANT SELECT ON TABLE pem.line_chart TO pem_user;
GRANT SELECT ON TABLE pem.data_chart TO pem_user;
GRANT SELECT ON TABLE pem.history_chart TO pem_user;
GRANT SELECT ON TABLE pem.metrices_chart TO pem_user;
GRANT SELECT ON TABLE pem.chart_metric TO pem_user;

GRANT SELECT ON TABLE pem.dashboard TO pem_user;
GRANT SELECT ON TABLE pem.dashboard_section TO pem_user;
GRANT SELECT ON TABLE pem.dashboard_chart TO pem_user;

REVOKE ALL ON FUNCTION pem.check_chart_metrices() FROM PUBLIC;
REVOKE ALL ON FUNCTION pem.generate_metric_chart_data(integer, integer, integer, text, text, integer, boolean, boolean) FROM public;
REVOKE ALL ON FUNCTION pem.db_escaped_string_to_array(text) FROM PUBLIC;
REVOKE ALL ON FUNCTION pem.dashboard_chart_insertion() FROM PUBLIC;
REVOKE ALL ON FUNCTION pem.dashboard_chart_deletion() FROM PUBLIC;
REVOKE ALL ON FUNCTION pem.can_access(oid[]) FROM PUBLIC;
REVOKE ALL ON FUNCTION pem.purge_deleted_charts() FROM PUBLIC;

GRANT EXECUTE ON FUNCTION pem.check_chart_metrices() TO pem_admin;
GRANT EXECUTE ON FUNCTION pem.dashboard_chart_insertion() TO pem_admin;
GRANT EXECUTE ON FUNCTION pem.dashboard_chart_deletion() TO pem_admin;
GRANT EXECUTE ON FUNCTION pem.generate_metric_chart_data(integer, integer, integer, text, text, integer, boolean, boolean) TO pem_admin;
GRANT EXECUTE ON FUNCTION pem.db_escaped_string_to_array(text) TO pem_admin;
GRANT EXECUTE ON FUNCTION pem.can_access(oid[]) TO pem_admin;
GRANT EXECUTE ON FUNCTION pem.generate_host_memory_chart_data(integer) TO pem_admin;

GRANT EXECUTE ON FUNCTION pem.generate_metric_chart_data(integer, integer, integer, text, text, integer, boolean, boolean) TO pem_user;
GRANT EXECUTE ON FUNCTION pem.db_escaped_string_to_array(text) TO pem_user;
GRANT EXECUTE ON FUNCTION pem.can_access(oid[]) TO pem_user;
GRANT EXECUTE ON FUNCTION pem.purge_deleted_charts() TO pem_user;
GRANT EXECUTE ON FUNCTION pem.generate_host_memory_chart_data(integer) TO pem_user;

REVOKE ALL ON FUNCTION pem.purge_audit_log() FROM PUBLIC;
REVOKE ALL ON FUNCTION pem.purge_server_log() FROM PUBLIC;
REVOKE ALL ON FUNCTION pem.purge_probe_log() FROM PUBLIC;
REVOKE ALL ON FUNCTION pem.purge_smtp_spool() FROM PUBLIC;
REVOKE ALL ON FUNCTION pem.purge_snmp_spool() FROM PUBLIC;
REVOKE ALL ON FUNCTION pem.purge_alert_history() FROM PUBLIC;
REVOKE ALL ON FUNCTION pem.purge_job_log() FROM PUBLIC;
REVOKE ALL ON FUNCTION pem.purge_deleted_charts() FROM PUBLIC;
REVOKE ALL ON FUNCTION pem.send_email(mail_group_id integer, subject text, message text) FROM PUBLIC;
REVOKE ALL ON FUNCTION pem.send_snmptrap(trap_oid text, enterprise_oid text, trap_version integer, varbinding_oid text, varbinding_value text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION pem.purge_audit_log() TO pem_agent;
GRANT EXECUTE ON FUNCTION pem.purge_server_log() TO pem_agent;
GRANT EXECUTE ON FUNCTION pem.purge_probe_log() TO pem_agent;
GRANT EXECUTE ON FUNCTION pem.purge_smtp_spool() TO pem_agent;
GRANT EXECUTE ON FUNCTION pem.purge_snmp_spool() TO pem_agent;
GRANT EXECUTE ON FUNCTION pem.purge_alert_history() TO pem_agent;
GRANT EXECUTE ON FUNCTION pem.purge_job_log() TO pem_agent;
GRANT EXECUTE ON FUNCTION pem.purge_deleted_charts() TO pem_agent;
GRANT EXECUTE ON FUNCTION pem.json_escape(text) TO PUBLIC;

-- Done!
COMMIT TRANSACTION;
