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

BEGIN TRANSACTION;

CREATE OR REPLACE FUNCTION pem.schema_version()
  RETURNS integer AS
'SELECT 201601073::integer;'
  LANGUAGE 'sql' IMMUTABLE;
COMMENT ON FUNCTION pem.schema_version() IS 'Returns the version number of the PEM schema';

ALTER TABLE pemdata.disk_space ADD COLUMN space_reserved_mb bigint DEFAULT NULL;
ALTER TABLE pemhistory.disk_space ADD COLUMN space_reserved_mb bigint DEFAULT NULL;

UPDATE pem.alert_template SET sql = 'SELECT
	((space_used_mb::float * 100)
        / CASE size_mb WHEN 0 THEN 1 ELSE (size_mb - COALESCE(space_reserved_mb, 0)) END
	FROM pemdata.disk_space
	WHERE agent_id = ${agent_id}
	AND mount_point = ${param_1};'
WHERE display_name = 'Disk consumption percentage';

UPDATE pem.alert_template SET sql = 'SELECT
	MAX(space_used_mb::float * 100 / (CASE size_mb WHEN 0 THEN 1 ELSE (size_mb - COALESCE(space_reserved_mb, 0)) END))
	FROM pemdata.disk_space
	WHERE size_mb > 0
	AND agent_id = ${agent_id}'
WHERE display_name = 'Most used disk percentage';

UPDATE pem.chart_func SET func = '
SELECT
	file_system AS "File System",
	(size_mb::float/1024)::numeric(30,2) AS "Size (GB)",
	(space_used_mb::float/1024)::numeric(30,2) AS "Used (GB)",
	(space_available_mb::float/1024)::numeric(30,2) AS "Available (GB)",
	CASE WHEN size_mb = 0
	THEN 0
	ELSE space_used_mb::float * 100/(size_mb - COALESCE(space_reserved_mb, 0))
	END
	AS "%Used",
	mount_point AS "Mounted On"
FROM pemdata.disk_space
WHERE agent_id = $1::int4
ORDER BY 3::int DESC' WHERE id = 44;

UPDATE pem.chart_func SET func = 'SELECT
        $$Total Database Size: $$ ||
        (SELECT
		pem.pretty_size(database_size_mb)
	FROM  pemdata.database_size
	WHERE database_size.server_id = $1::int4 AND database_size.database_name = $2::text) || $$&#183;$$
	||$$ Total Tables: $$ || (SELECT
					count(table_name)
					FROM pemdata.table_size
					WHERE server_id = $1::int4 AND database_name = $2::text ) || $$&#183;$$
	|| $$ Total Indexes: $$ || (SELECT
					count(index_name) FROM pemdata.index_size
			                WHERE server_id = $1::int4 AND database_name = $2::text AND
			                ($3::boolean OR (schema_name NOT IN(
									   $$pg_catalog$$,
									   $$pg_toast$$,
									   $$information_schema$$,
									   $$sys$$))))',
        r_sys_obj = TRUE
WHERE id = 9 AND type = 'Q';
UPDATE pem.chart SET params = '{server_id, database_name, show_sys_objects}'::text[] WHERE fid = 9;

-- Function to create unique service name for nagios
CREATE OR REPLACE FUNCTION pem.create_nagios_service_name(
    alert_name text,
    server_name text DEFAULT NULL::text,
    database_name text DEFAULT NULL::text,
    schema_name text DEFAULT NULL::text,
    package_name text DEFAULT NULL::text,
    object_name text DEFAULT NULL::text)
  RETURNS text AS
$BODY$
DECLARE
    service_name_text    text := '';
    new_alert_name       text := '';
BEGIN

        new_alert_name = regexp_replace(regexp_replace(alert_name, E'[`~$%^&*|''"<>?,(=]','-'), E'[)]', '-');
        service_name_text = E'' || new_alert_name || CASE WHEN server_name IS NOT NULL THEN ' - svr: ' || server_name ELSE '' END || CASE WHEN database_name IS NOT NULL THEN ' - db: ' || database_name ELSE '' END || CASE WHEN schema_name IS NOT NULL THEN ' - schema: ' || schema_name ELSE '' END || CASE WHEN package_name IS NOT NULL THEN ' - pkg: ' || package_name ELSE '' END || CASE WHEN object_name IS NOT NULL THEN ' - obj: ' || object_name ELSE '' END || E'';

RETURN service_name_text;

END
$BODY$
  LANGUAGE plpgsql;

-- Function to create host name for nagios
CREATE OR REPLACE FUNCTION pem.create_nagios_host_name(
    ag_id int,
    srv_id int)
  RETURNS text AS
$BODY$
DECLARE
    host_name    text := '';
BEGIN

	-- ag_id > 0 - Alert is configured as agent level
        -- ag_id = 0 - Alert is configured other then global and agent level
        -- ag_id = -1 - Alert is configured as global level
	IF ag_id > 0 THEN
            SELECT description INTO host_name FROM pem.agent where id = ag_id;
        ELSIF ag_id = 0 THEN
            SELECT description INTO host_name FROM pem.agent where id = (SELECT agent_id FROM pem.agent_server_binding where server_id = srv_id);
        ELSE
            SELECT description INTO host_name FROM pem.agent where id = 1;
        END IF;

RETURN host_name;

END
$BODY$
  LANGUAGE plpgsql;

-- Drop existing function because of change in function arguments. Fix RM#35773.
-- Added - is_max_check_attemp_require arguments to check, user need 'max_check_attempt' parameter in hosts.conf file or not
-- For older nagios version(<= 3) - 'max_check_attempt' parameter is required in hosts.conf,
-- if we do not provide then verification of hosts file will be fail but for newer version( >= 4) it not required
-- so making this parameter as configurable for users.
DROP FUNCTION IF EXISTS pem.create_nagios_host_config(text, text, text, text);

-- Function to create nagios hosts.cfg file
CREATE OR REPLACE FUNCTION pem.create_nagios_host_config(
    template_name text DEFAULT NULL::text,
    is_max_check_attemp_require boolean DEFAULT FALSE::boolean,
    icon_image text DEFAULT NULL::text,
    icon_image_alt text DEFAULT NULL::text,
    statusmap_image text DEFAULT NULL::text)
  RETURNS text AS
$BODY$

DECLARE
    host_config_text    text := '';
    row                 RECORD;
BEGIN
    FOR row IN SELECT DISTINCT ON (pa.description) pa.description, ps.server FROM pem.agent pa LEFT JOIN pem.agent_server_binding pasb ON (pa.id = pasb.agent_id) LEFT JOIN pem.server ps ON (ps.id = pasb.server_id)  WHERE pa.active = true AND ps.active = true
    LOOP
        host_config_text = host_config_text || E'define host {
        host_name                ' || row.description || E'
        address                  ' || row.server || E'
        active_checks_enabled    0
        passive_checks_enabled	 1';

        IF is_max_check_attemp_require THEN
            host_config_text = host_config_text || E'\n        max_check_attempts       10';
        END IF;

        IF icon_image IS NOT NULL THEN
            host_config_text = host_config_text || E'\n        icon_image               ' || icon_image;
        END IF;

        IF icon_image_alt IS NOT NULL THEN
            host_config_text = host_config_text || E'\n        icon_image_alt           ' || icon_image_alt;
        ELSE
            host_config_text = host_config_text || E'\n        icon_image_alt           ' || row.description;
        END IF;

        IF statusmap_image IS NOT NULL THEN
            host_config_text = host_config_text || E'\n        statusmap_image          ' || statusmap_image;
        END IF;

        IF template_name IS NOT NULL THEN
            host_config_text = host_config_text || E'\n        use                      ' || template_name;
        END IF;
        host_config_text = host_config_text ||    E'\n}\n\n';
    END LOOP;

RETURN host_config_text;

END

$BODY$
  LANGUAGE plpgsql;

-- Function to create nagios services.cfg file
CREATE OR REPLACE FUNCTION pem.create_nagios_service_config(template_name text)
  RETURNS text AS
$BODY$

DECLARE
    service_config_text    text := '';
    row                 RECORD;
    service_desc        text;
    host_agent_name        text;
    agent_description        text := '';
    service_name        text := '';

BEGIN
    -- List all the services except agent and global level
    FOR row IN SELECT a.server_id, a.agent_id, s.description, s.server, a.name, a.database_name, a.schema_name, a.package_name, a.object_name FROM pem.server s, pem.alert a WHERE a.server_id = s.id AND s.active = true AND a.enabled = true AND a.submit_to_nagios = true ORDER BY s.description, a.name
    LOOP
	-- Function to create the nagios host name from agent and server id
	SELECT pem.create_nagios_host_name(row.agent_id , row.server_id) INTO agent_description;
	-- Function to create the nagios service/alert name
	SELECT pem.create_nagios_service_name(row.name, row.description, row.database_name, row.schema_name, row.package_name, row.object_name) INTO service_name;

        service_config_text = service_config_text || E'define service {
        host_name                ' || agent_description || E'
        service_description      ' || service_name || E'
        use                      ' || template_name  || E'
        check_command            check_ping!3000.0,80%!5000.0,100%
        check_freshness          0
        active_checks_enabled    0
        passive_checks_enabled   1\n}\n\n';
    END LOOP;

    -- List only agent and global services
    FOR row IN SELECT a.server_id, a.agent_id, ag.description, a.name FROM pem.agent ag, pem.alert a WHERE (a.agent_id = ag.id) AND ag.active = true AND a.enabled = true AND a.submit_to_nagios = true ORDER BY ag.description, a.name
    LOOP
        -- Function to create the nagios service/alert name
	SELECT pem.create_nagios_service_name(row.name) INTO service_name;

        service_config_text = service_config_text || E'define service {
        host_name                ' || row.description || E'
        service_description      ' || service_name || E'
        use                      ' || template_name  || E'
        check_command            check_ping!3000.0,80%!5000.0,100%
        check_freshness          0
        active_checks_enabled    0
        passive_checks_enabled   1\n}\n\n';
    END LOOP;

RETURN service_config_text;

END
$BODY$
  LANGUAGE plpgsql;

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

    SELECT mail_subject INTO status_text FROM pem.email_template WHERE display_name = template;

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

    status_text = regexp_replace(status_text, '%AlertName%', alert_name);
    status_text = regexp_replace(status_text, '%ObjectName%', msg_object_name);
    IF current_state IS NOT NULL THEN
        status_text = regexp_replace(status_text, '%AlertType%', current_state);
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
END $BODY$
  LANGUAGE plpgsql;

-- This is an additional SQL function that will send the current state of all the alerts to Nagios. This enables the user to "prime" Nagios,
-- otherwise alerts will stay in an "Unknown" state until PEM sends a state change (which of course, ideally will never happen).
-- NOTE: This should only be executable by Admins.
CREATE OR REPLACE FUNCTION pem.prime_nagios_passive_alerts(
	)
    RETURNS SETOF boolean
    LANGUAGE 'sql'
    COST 100.0

AS $function$

SELECT
    pem.submit_to_nagios(
        pem.create_passive_service_check_result(
            alert_id::integer,
            template::text,
            current_value::text,
            current_state::text
        )
    )
FROM
(
    SELECT
        a.name,
        a.agent_id,
        a.server_id,
        alert_id,
        CASE WHEN current_state IS NULL THEN
                'Alert Cleared'
        ELSE
                'Alert Detected'
        END AS template,
        current_value,
        current_state
    FROM
        pem.alert a,
        pem.alert_status s
    WHERE
        submit_to_nagios = true AND
        enabled = true AND
        a.id = s.alert_id AND
        CASE WHEN agent_id IS NOT NULL THEN
            (agent_id IN (SELECT id FROM pem.agent WHERE active) = true OR agent_id = 0)
        ELSE
            true
        END AND
        CASE WHEN server_id IS NOT NULL THEN
             (server_id IN (SELECT id FROM pem.server WHERE active) = true)
        ELSE
            true
        END
) AS alerts

$function$;

-- Fix RM#38684 - Custom Probe permissions issue
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
				|| r.create_history_table_clause || ')';

	                -- Give permission to pem_user, pem_agent and pem_admin
			EXECUTE 'GRANT SELECT ON TABLE pemhistory.' || quoted_table_name || ' TO pem_user;';
			EXECUTE 'GRANT ALL ON TABLE pemhistory.' || quoted_table_name || ' TO pem_admin;';
			EXECUTE 'GRANT SELECT, UPDATE, INSERT, DELETE ON TABLE pemhistory.' || quoted_table_name || ' TO pem_agent;';

			EXECUTE 'CREATE INDEX '
				|| quote_ident(probe_table_name.internal_name || '_keyidx')
				|| ' ON ' || 'pemhistory.' || quoted_table_name
				|| ' (' || r.key_string || ')';

			EXECUTE 'CREATE INDEX '
				|| quote_ident(probe_table_name.internal_name || '_timeidx')
				|| ' ON ' || 'pemhistory.' || quoted_table_name
				|| ' (recorded_time)';

			-- Trigger Function Command String
			trigger_function_command := 'CREATE OR REPLACE FUNCTION pemdata.' ||  quote_ident('copy_' || probe_table_name.internal_name || '_to_history') || '() RETURNS TRIGGER AS $$
			BEGIN
				IF (TG_OP = ''INSERT'' OR TG_OP = ''UPDATE'') THEN
					INSERT INTO pemhistory.' || quoted_table_name || ' (' || r.column_string || ') VALUES (' || r.new_column_string || ');
					ELSIF EXISTS(SELECT 1 FROM ' || CASE WHEN probe_table_name.target_type_id = 100 THEN 'pem.agent WHERE id = OLD.agent_id' ELSE 'pem.server WHERE id = OLD.server_id' END || ') THEN
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

-- Fix RM#38488 - Number of CPU is appears higher than of actual server CPU count while preparing CPU usage graph
UPDATE pem.probe_column SET is_graphable = false
	WHERE probe_id = (SELECT id FROM pem.probe WHERE internal_name = 'session_info')
	AND internal_name IN ('cpu_usage', 'memory_usage_mb', 'swap_usage_mb', 'io_read_bytes', 'io_write_bytes');

-- Fix RM#38639 - Typo in mail template subject line. Correct mail subject typo for display_name = Alert Cleared.
UPDATE pem.email_template SET mail_subject='Alert "%AlertName%" cleared on %ObjectName%' WHERE id = 4;

-- Fix RM#38194 Support for AS / PG 9.6
INSERT INTO pem.server_version VALUES (10906, 'PostgreSQL 9.6');
INSERT INTO pem.server_version VALUES (20906, 'Advanced Server 9.6');

-- oc_schmea support
INSERT INTO pem.probe_server_version(probe_id,server_version_id,probe_code)
       VALUES((SELECT id FROM pem.probe WHERE internal_name='oc_schema'), 10906, NULL);

INSERT INTO pem.probe_server_version(probe_id,server_version_id,probe_code)
       VALUES((SELECT id FROM pem.probe WHERE internal_name='oc_schema'), 20906,
       E'SELECT nspname AS schema_name FROM pg_catalog.pg_namespace WHERE (nspname = ''pg_catalog'' OR nspname NOT LIKE E''pg\\\\_%'') AND nspparent = 0');

-- oc_function support
INSERT INTO pem.probe_server_version(probe_id,server_version_id,probe_code)
       VALUES((SELECT id FROM pem.probe WHERE internal_name='oc_function'), 10906,
	   $sql$
	SELECT
	'' AS package_name, f.proname AS function_name, '0'::"char" AS function_type,
	f.prorettype::regtype AS return_type, f.proargtypes::regtype[] AS arg_types,
	f.probin AS function_binary, e.extname::text AS extension_name
FROM
	pg_catalog.pg_namespace AS s
	JOIN	pg_catalog.pg_proc AS f
		ON f.pronamespace = s.oid
	LEFT JOIN pg_catalog.pg_depend AS d
		ON (f.oid = d.objid AND d.classid = 'pg_proc'::regclass AND d.refclassid = 'pg_extension'::regclass)
	LEFT JOIN pg_catalog.pg_extension AS e
		ON (d.refobjid = e.oid)
WHERE
	s.nspname = %{schema_name}$sql$);

INSERT INTO pem.probe_server_version(probe_id,server_version_id,probe_code)
       VALUES((SELECT id FROM pem.probe WHERE internal_name='oc_function'), 20906,
       $sql$
	SELECT	'' AS package_name, f.proname AS function_name, f.protype AS function_type,
			f.prorettype::regtype AS return_type, f.proargtypes::regtype[] AS arg_types,
			f.probin AS function_binary, e.extname::text AS extension_name
	FROM	pg_catalog.pg_namespace AS s	-- schema
	JOIN	pg_catalog.pg_proc AS f			-- function
	ON		f.pronamespace = s.oid
	LEFT JOIN pg_catalog.pg_depend AS d
		ON (f.oid = d.objid AND d.classid = 'pg_proc'::regclass AND d.refclassid = 'pg_extension'::regclass)
	LEFT JOIN pg_catalog.pg_extension AS e
		ON (d.refobjid = e.oid)
	WHERE	s.nspparent = 0 -- select schema that is not a child of some other schema
	AND		s.nspname = %{schema_name}
	UNION ALL
	SELECT	p.nspname AS package_name, f.proname AS function_name, f.protype AS function_type,
			f.prorettype::regtype AS return_type, f.proargtypes::regtype[] AS arg_types,
			f.probin AS function_binary, e.extname::text AS extension_name
	FROM	pg_catalog.pg_namespace AS s	-- schema
	JOIN	pg_catalog.pg_namespace AS p	-- package
	ON		p.nspparent = s.oid
	JOIN	pg_catalog.pg_proc AS f			-- function
	ON		f.pronamespace = p.oid
	LEFT JOIN pg_catalog.pg_depend AS d
		ON (f.oid = d.objid AND d.classid = 'pg_proc'::regclass AND d.refclassid = 'pg_extension'::regclass)
	LEFT JOIN pg_catalog.pg_extension AS e
		ON (d.refobjid = e.oid)
	WHERE	p.nspparent <> 0 -- select schema that _is_ a child of some other schema
	AND		s.nspname = %{schema_name}$sql$);

-- database_statistics support
INSERT INTO pem.probe_server_version(probe_id,server_version_id,probe_code)
       VALUES((SELECT id FROM pem.probe WHERE internal_name='database_statistics'), 10906,
       'SELECT d1.datname AS database_name, d1.numbackends,
            (SELECT COALESCE(count(query)::bigint, 0::bigint) FROM pg_catalog.pg_stat_activity WHERE datname = d1.datname AND state = ''idle'') AS idle_backends,
	    d1.xact_commit, d1.xact_rollback, d1.blks_hit, NULL::bigint AS blks_icache_hit, d1.blks_read,
            d1.tup_returned, d1.tup_fetched, d1.tup_inserted, d1.tup_updated, d1.tup_deleted
      FROM pg_catalog.pg_stat_database d1');

INSERT INTO pem.probe_server_version(probe_id,server_version_id,probe_code)
       VALUES((SELECT id FROM pem.probe WHERE internal_name='database_statistics'), 20906,
       'SELECT d1.datname AS database_name, d1.numbackends,
            (SELECT COALESCE(count(query)::bigint, 0::bigint) FROM pg_catalog.pg_stat_activity WHERE datname = d1.datname AND state = ''idle'') AS idle_backends,
            d1.xact_commit, d1.xact_rollback, d1.blks_hit, d1.blks_icache_hit, d1.blks_read, d1.tup_returned,
            d1.tup_fetched, d1.tup_inserted, d1.tup_updated, d1.tup_deleted
     FROM pg_catalog.pg_stat_database d1');

-- table_statistics support
INSERT INTO pem.probe_server_version(probe_id,server_version_id,probe_code)
       VALUES((SELECT id FROM pem.probe WHERE internal_name='table_statistics'), 10906, NULL);

INSERT INTO pem.probe_server_version(probe_id,server_version_id,probe_code)
       VALUES((SELECT id FROM pem.probe WHERE internal_name='table_statistics'), 20906, NULL);

-- function_statistics support
INSERT INTO pem.probe_server_version(probe_id,server_version_id,probe_code)
       VALUES((SELECT id FROM pem.probe WHERE internal_name='function_statistics'), 10906, NULL);

INSERT INTO pem.probe_server_version(probe_id,server_version_id,probe_code)
       VALUES((SELECT id FROM pem.probe WHERE internal_name='function_statistics'), 20906,
       $sql$
SELECT s.nspname AS schema_name, '' AS package_name, f.proname AS function_name,
               f.protype AS function_type, f.prorettype::regtype AS return_type,
               f.proargtypes::regtype[] AS arg_types,
               fs.calls AS call_count, fs.total_time, fs.self_time
FROM   pg_catalog.pg_namespace AS s                    -- schema
JOIN   pg_catalog.pg_proc AS f                                 -- function
ON             f.pronamespace = s.oid
JOIN   pg_catalog.pg_stat_user_functions AS fs -- Func. stats
ON             fs.funcid = f.oid
WHERE  s.nspparent = 0 -- select schema that is not a child of some other schema
UNION ALL
SELECT s.nspname AS schema_name, p.nspname AS package_name, f.proname AS function_name,
               f.protype AS function_type, f.prorettype::regtype AS return_type,
               f.proargtypes::regtype[] AS arg_types,
               fs.calls AS call_count, fs.total_time, fs.self_time
FROM   pg_catalog.pg_namespace AS s                    -- schema
JOIN   pg_catalog.pg_namespace AS p                    -- package
ON             p.nspparent = s.oid
JOIN   pg_catalog.pg_proc AS f                                 -- function
ON             f.pronamespace = p.oid
JOIN   pg_catalog.pg_stat_user_functions AS fs -- Func. stats
ON             fs.funcid = f.oid
WHERE  p.nspparent <> 0 -- select schema that _is_ a child of some other schema
$sql$);

-- table_size support
INSERT INTO pem.probe_server_version(probe_id,server_version_id,probe_code)
       VALUES((SELECT id FROM pem.probe WHERE internal_name='table_size'), 10906,
       'SELECT n.nspname AS schema_name, c.relname AS table_name, pg_relation_size(c.oid) / 1048576 AS table_size_mb, pg_indexes_size(c.oid) / 1048576 AS size_of_indexes_mb, pg_total_relation_size(c.oid) / 1048576 AS total_table_size_mb FROM pg_class c, pg_namespace n WHERE c.relnamespace = n.oid AND c.relkind = ''r''');

INSERT INTO pem.probe_server_version(probe_id,server_version_id,probe_code)
       VALUES((SELECT id FROM pem.probe WHERE internal_name='table_size'), 20906,
       'SELECT n.nspname AS schema_name, c.relname AS table_name, pg_relation_size(c.oid) / 1048576 AS table_size_mb, pg_indexes_size(c.oid) / 1048576 AS size_of_indexes_mb, pg_total_relation_size(c.oid) / 1048576 AS total_table_size_mb FROM pg_class c, pg_namespace n WHERE c.relnamespace = n.oid AND c.relkind = ''r''');

-- background_writer_statistics support
INSERT INTO pem.probe_server_version(probe_id,server_version_id,probe_code)
       VALUES((SELECT id FROM pem.probe WHERE internal_name='background_writer_statistics'), 10906, NULL);

INSERT INTO pem.probe_server_version(probe_id,server_version_id,probe_code)
       VALUES((SELECT id FROM pem.probe WHERE internal_name='background_writer_statistics'), 20906, NULL);

-- session_info support
ALTER TABLE pemdata.session_info ADD COLUMN wait_event_type text DEFAULT NULL;
ALTER TABLE pemhistory.session_info ADD COLUMN wait_event_type text DEFAULT NULL;
ALTER TABLE pemdata.session_info ADD COLUMN wait_event text DEFAULT NULL;
ALTER TABLE pemhistory.session_info ADD COLUMN wait_event text DEFAULT NULL;

INSERT INTO pem.probe_server_version(probe_id,server_version_id,probe_code)
       VALUES((SELECT id FROM pem.probe WHERE internal_name='session_info'), 10906,
       $sql$
		SELECT
			datname AS database_name, pid AS procpid, usename, client_addr, client_port, backend_start,
			xact_start, query_start, CASE WHEN wait_event IS NULL THEN false ELSE true END AS is_waiting,
			state = 'idle' AS is_idle, state = 'idle in transaction' AS is_idle_in_transaction, query ilike $$VACUUM%$$ as is_vacuum,
			client_port IS NULL AND (query like $$autovacuum:%$$ OR query like $$VACUUM%$$) as is_autovacuum,
			now() AS capture_time, wait_event, wait_event_type
		FROM pg_catalog.pg_stat_activity
	   $sql$);

INSERT INTO pem.probe_server_version(probe_id,server_version_id,probe_code)
       VALUES((SELECT id FROM pem.probe WHERE internal_name='session_info'), 20906,
       $sql$
		SELECT
			datname AS database_name, pid AS procpid, usename, client_addr, client_port, backend_start,
			xact_start, query_start, CASE WHEN wait_event IS NULL THEN false ELSE true END AS is_waiting,
			state = 'idle' AS is_idle, state = 'idle in transaction' AS is_idle_in_transaction, query ilike $$VACUUM%$$ as is_vacuum,
			client_port IS NULL AND (query like $$autovacuum:%$$ OR query like $$VACUUM%$$) as is_autovacuum,
			now() AS capture_time, wait_event, wait_event_type
		FROM pg_catalog.pg_stat_activity
	   $sql$);

-- lock_info support
INSERT INTO pem.probe_server_version(probe_id,server_version_id,probe_code)
       VALUES((SELECT id FROM pem.probe WHERE internal_name='lock_info'), 10906,
       $sql$
SELECT	COALESCE(d.datname, '')			AS database_name,
		COALESCE(l.pid::bigint, -1)		AS procpid,
		l.relation::text::numeric		AS objid,		-- relation/XID/VXID/classid
		COALESCE(l.page::bigint, -1)	AS objsubid,	-- page/objid
		COALESCE(l.tuple::bigint, -1)	AS objsubsubid,	-- tuple/objsubid
		l.locktype, l.mode AS lockmode, l.granted AS lockgranted
FROM	pg_catalog.pg_locks AS l
LEFT JOIN	pg_catalog.pg_stat_activity AS sa
ON		l.pid = sa.pid
JOIN	pg_catalog.pg_database AS d
ON		sa.datid = d.oid
WHERE	l.locktype IN ('relation', 'extend', 'page', 'tuple')
UNION ALL
SELECT	COALESCE(d.datname, '')		AS database_name,
		COALESCE(l.pid::bigint, -1)	AS procpid,
		transactionid::text::numeric	AS objid,	-- relation/XID/VXID/classid
		-1							AS objsubid,	-- page/objid
		-1							AS objsubsubid,	-- tuple/objsubid
		l.locktype, l.mode AS lockmode, l.granted AS lockgranted
FROM	pg_catalog.pg_locks AS l
LEFT JOIN	pg_catalog.pg_stat_activity AS sa
ON		l.pid = sa.pid
JOIN	pg_catalog.pg_database AS d
ON		sa.datid = d.oid
WHERE	l.locktype = 'transactionid'
UNION ALL
SELECT	COALESCE(d.datname, '')				AS database_name,
		COALESCE(l.pid::bigint, -1)			AS procpid,
		regexp_replace(l.virtualxid, '/', '.')::numeric AS objid,-- relation/XID/VXID/classid
		-1									AS objsubid,	-- page/objid
		-1									AS objsubsubid,	-- tuple/objsubid
		l.locktype, l.mode AS lockmode, l.granted AS lockgranted
FROM	pg_catalog.pg_locks AS l
LEFT JOIN	pg_catalog.pg_stat_activity AS sa
ON		l.pid = sa.pid
JOIN	pg_catalog.pg_database AS d
ON		sa.datid = d.oid
WHERE	l.locktype = 'virtualxid'
UNION ALL
SELECT	COALESCE(d.datname, '')			AS database_name,
		COALESCE(l.pid::bigint, -1)		AS procpid,
		classid::text::numeric			AS objid,-- relation/XID/VXID/classid
		COALESCE(l.objid::bigint, -1)	AS objsubid,	-- page/objid
		COALESCE(l.objsubid::bigint, -1)AS objsubsubid,	-- tuple/objsubid
		l.locktype, l.mode AS lockmode, l.granted AS lockgranted
FROM	pg_catalog.pg_locks AS l
LEFT JOIN	pg_catalog.pg_stat_activity AS sa
ON		l.pid = sa.pid
JOIN	pg_catalog.pg_database AS d
ON		sa.datid = d.oid
WHERE	l.locktype IN ('object', 'advisory')$sql$);

INSERT INTO pem.probe_server_version(probe_id,server_version_id,probe_code)
       VALUES((SELECT id FROM pem.probe WHERE internal_name='lock_info'), 20906,
       $sql$
SELECT	COALESCE(d.datname, '')			AS database_name,
		COALESCE(l.pid::bigint, -1)		AS procpid,
		l.relation::text::numeric		AS objid,		-- relation/XID/VXID/classid
		COALESCE(l.page::bigint, -1)	AS objsubid,	-- page/objid
		COALESCE(l.tuple::bigint, -1)	AS objsubsubid,	-- tuple/objsubid
		l.locktype, l.mode AS lockmode, l.granted AS lockgranted
FROM	pg_catalog.pg_locks AS l
LEFT JOIN	pg_catalog.pg_stat_activity AS sa
ON		l.pid = sa.pid
JOIN	pg_catalog.pg_database AS d
ON		sa.datid = d.oid
WHERE	l.locktype IN ('relation', 'extend', 'page', 'tuple')
UNION ALL
SELECT	COALESCE(d.datname, '')		AS database_name,
		COALESCE(l.pid::bigint, -1)	AS procpid,
		transactionid::text::numeric	AS objid,	-- relation/XID/VXID/classid
		-1							AS objsubid,	-- page/objid
		-1							AS objsubsubid,	-- tuple/objsubid
		l.locktype, l.mode AS lockmode, l.granted AS lockgranted
FROM	pg_catalog.pg_locks AS l
LEFT JOIN	pg_catalog.pg_stat_activity AS sa
ON		l.pid = sa.pid
JOIN	pg_catalog.pg_database AS d
ON		sa.datid = d.oid
WHERE	l.locktype = 'transactionid'
UNION ALL
SELECT	COALESCE(d.datname, '')				AS database_name,
		COALESCE(l.pid::bigint, -1)			AS procpid,
		regexp_replace(l.virtualxid, '/', '.')::numeric AS objid,-- relation/XID/VXID/classid
		-1									AS objsubid,	-- page/objid
		-1									AS objsubsubid,	-- tuple/objsubid
		l.locktype, l.mode AS lockmode, l.granted AS lockgranted
FROM	pg_catalog.pg_locks AS l
LEFT JOIN	pg_catalog.pg_stat_activity AS sa
ON		l.pid = sa.pid
JOIN	pg_catalog.pg_database AS d
ON		sa.datid = d.oid
WHERE	l.locktype = 'virtualxid'
UNION ALL
SELECT	COALESCE(d.datname, '')			AS database_name,
		COALESCE(l.pid::bigint, -1)		AS procpid,
		classid::text::numeric			AS objid,-- relation/XID/VXID/classid
		COALESCE(l.objid::bigint, -1)	AS objsubid,	-- page/objid
		COALESCE(l.objsubid::bigint, -1)AS objsubsubid,	-- tuple/objsubid
		l.locktype, l.mode AS lockmode, l.granted AS lockgranted
FROM	pg_catalog.pg_locks AS l
LEFT JOIN	pg_catalog.pg_stat_activity AS sa
ON		l.pid = sa.pid
JOIN	pg_catalog.pg_database AS d
ON		sa.datid = d.oid
WHERE	l.locktype IN ('object', 'advisory')$sql$);

-- streaming_replication support
INSERT INTO pem.probe_server_version(probe_id,server_version_id,probe_code)
       VALUES((SELECT id FROM pem.probe WHERE internal_name='streaming_replication'), 10906,
	   $sql$
		SELECT client_addr, client_port, sent_location, write_location, flush_location, replay_location, xlog_lag_in_segments,
		(((sent_location -replay_location)>>10) / (SUBSTRING(unit FROM '[0-9]+'))::INT) AS xlog_lag_in_pages
		FROM (
		WITH pg_stat_replication_log_bytes AS (
		SELECT
			host(client_addr) AS client_addr, client_port,

			pg_catalog.split_part(sent_location::text, '/', 1) AS s1,
			pg_catalog.split_part(sent_location::text, '/', 2) AS s2,

			pg_catalog.split_part(write_location::text, '/', 1) AS w1,
			pg_catalog.split_part(write_location::text, '/', 2) AS w2,

			pg_catalog.split_part(flush_location::text, '/', 1) AS f1,
			pg_catalog.split_part(flush_location::text, '/', 2) AS f2,

			pg_catalog.split_part(replay_location::text, '/', 1) AS r1,
			pg_catalog.split_part(replay_location::text, '/', 2) AS r2,

			(('x'||SUBSTRING((pg_xlogfile_name_offset(sent_location)).file_name FROM 9))::BIT(64)::BIGINT -
				('x'||SUBSTRING((pg_xlogfile_name_offset(replay_location)).file_name FROM 9))::BIT(64)::BIGINT) AS xlog_lag_in_segments

		FROM pg_stat_replication WHERE client_addr IS NOT NULL)
		SELECT
			client_addr, client_port,
			CASE WHEN s1 IS NULL AND s2 IS NULL THEN 0::bigint
				WHEN s1 IS NULL THEN ('x' || repeat('0', 16 - length(s2)) || s2)::bit(64)::bigint
				WHEN s2 IS NULL THEN 4278190080 * ('x' || repeat('0', 16 - length(s1)) || s1)::bit(64)::bigint
				ELSE 4278190080 * ('x' || repeat('0', 16 - length(s1)) || s1)::bit(64)::bigint + ('x' || repeat('0', 16 - length(s2)) || s2)::bit(64)::bigint
			END AS sent_location,
			CASE WHEN w1 IS NULL AND w2 IS NULL THEN 0::bigint
				WHEN w1 IS NULL THEN ('x' || repeat('0', 16 - length(w2)) || w2)::bit(64)::bigint
				WHEN w2 IS NULL THEN 4278190080 * ('x' || repeat('0', 16 - length(w1)) || w1)::bit(64)::bigint
				ELSE 4278190080 * ('x' || repeat('0', 16 - length(w1)) || w1)::bit(64)::bigint + ('x' || repeat('0', 16 - length(w2)) || w2)::bit(64)::bigint
			END AS write_location,
			CASE WHEN f1 IS NULL AND f2 IS NULL THEN 0::bigint
				WHEN f1 IS NULL THEN ('x' || repeat('0', 16 - length(f2)) || f2)::bit(64)::bigint
				WHEN f2 IS NULL THEN 4278190080 * ('x' || repeat('0', 16 - length(f1)) || f1)::bit(64)::bigint
				ELSE 4278190080 * ('x' || repeat('0', 16 - length(f1)) || f1)::bit(64)::bigint + ('x' || repeat('0', 16 - length(f2)) || f2)::bit(64)::bigint
			END AS flush_location,
			CASE WHEN r1 IS NULL AND r2 IS NULL THEN 0::bigint
				WHEN r1 IS NULL THEN ('x' || repeat('0', 16 - length(r2)) || r2)::bit(64)::bigint
				WHEN r2 IS NULL THEN 4278190080 * ('x' || repeat('0', 16 - length(r1)) || r1)::bit(64)::bigint
				ELSE 4278190080 * ('x' || repeat('0', 16 - length(r1)) || r1)::bit(64)::bigint + ('x' || repeat('0', 16 - length(r2)) || r2)::bit(64)::bigint
			END AS replay_location,
			xlog_lag_in_segments
		FROM pg_stat_replication_log_bytes
		) AS pg_stat_replication_dtls, pg_catalog.pg_settings
		WHERE name ~ 'wal_segment_size'$sql$);

INSERT INTO pem.probe_server_version(probe_id,server_version_id,probe_code)
       VALUES((SELECT id FROM pem.probe WHERE internal_name='streaming_replication'), 20906,
	   $sql$
		SELECT client_addr, client_port, sent_location, write_location, flush_location, replay_location, xlog_lag_in_segments,
		(((sent_location -replay_location)>>10) / (SUBSTRING(unit FROM '[0-9]+'))::INT) AS xlog_lag_in_pages
		FROM (
		WITH pg_stat_replication_log_bytes AS (
		SELECT
			host(client_addr) AS client_addr, client_port,

			pg_catalog.split_part(sent_location::text, '/', 1) AS s1,
			pg_catalog.split_part(sent_location::text, '/', 2) AS s2,

			pg_catalog.split_part(write_location::text, '/', 1) AS w1,
			pg_catalog.split_part(write_location::text, '/', 2) AS w2,

			pg_catalog.split_part(flush_location::text, '/', 1) AS f1,
			pg_catalog.split_part(flush_location::text, '/', 2) AS f2,

			pg_catalog.split_part(replay_location::text, '/', 1) AS r1,
			pg_catalog.split_part(replay_location::text, '/', 2) AS r2,

			(('x'||SUBSTRING((pg_xlogfile_name_offset(sent_location)).file_name FROM 9))::BIT(64)::BIGINT -
				('x'||SUBSTRING((pg_xlogfile_name_offset(replay_location)).file_name FROM 9))::BIT(64)::BIGINT) AS xlog_lag_in_segments

		FROM pg_stat_replication WHERE client_addr IS NOT NULL)
		SELECT
			client_addr, client_port,
			CASE WHEN s1 IS NULL AND s2 IS NULL THEN 0::bigint
				WHEN s1 IS NULL THEN ('x' || repeat('0', 16 - length(s2)) || s2)::bit(64)::bigint
				WHEN s2 IS NULL THEN 4278190080 * ('x' || repeat('0', 16 - length(s1)) || s1)::bit(64)::bigint
				ELSE 4278190080 * ('x' || repeat('0', 16 - length(s1)) || s1)::bit(64)::bigint + ('x' || repeat('0', 16 - length(s2)) || s2)::bit(64)::bigint
			END AS sent_location,
			CASE WHEN w1 IS NULL AND w2 IS NULL THEN 0::bigint
				WHEN w1 IS NULL THEN ('x' || repeat('0', 16 - length(w2)) || w2)::bit(64)::bigint
				WHEN w2 IS NULL THEN 4278190080 * ('x' || repeat('0', 16 - length(w1)) || w1)::bit(64)::bigint
				ELSE 4278190080 * ('x' || repeat('0', 16 - length(w1)) || w1)::bit(64)::bigint + ('x' || repeat('0', 16 - length(w2)) || w2)::bit(64)::bigint
			END AS write_location,
			CASE WHEN f1 IS NULL AND f2 IS NULL THEN 0::bigint
				WHEN f1 IS NULL THEN ('x' || repeat('0', 16 - length(f2)) || f2)::bit(64)::bigint
				WHEN f2 IS NULL THEN 4278190080 * ('x' || repeat('0', 16 - length(f1)) || f1)::bit(64)::bigint
				ELSE 4278190080 * ('x' || repeat('0', 16 - length(f1)) || f1)::bit(64)::bigint + ('x' || repeat('0', 16 - length(f2)) || f2)::bit(64)::bigint
			END AS flush_location,
			CASE WHEN r1 IS NULL AND r2 IS NULL THEN 0::bigint
				WHEN r1 IS NULL THEN ('x' || repeat('0', 16 - length(r2)) || r2)::bit(64)::bigint
				WHEN r2 IS NULL THEN 4278190080 * ('x' || repeat('0', 16 - length(r1)) || r1)::bit(64)::bigint
				ELSE 4278190080 * ('x' || repeat('0', 16 - length(r1)) || r1)::bit(64)::bigint + ('x' || repeat('0', 16 - length(r2)) || r2)::bit(64)::bigint
			END AS replay_location,
			xlog_lag_in_segments
		FROM pg_stat_replication_log_bytes
		) AS pg_stat_replication_dtls, pg_catalog.pg_settings
		WHERE name ~ 'wal_segment_size'$sql$);

-- streaming_replication_db_conflicts support
INSERT INTO pem.probe_server_version(probe_id,server_version_id,probe_code)
       VALUES((SELECT id FROM pem.probe WHERE internal_name='streaming_replication_db_conflicts'), 10906, NULL);

INSERT INTO pem.probe_server_version(probe_id,server_version_id,probe_code)
       VALUES((SELECT id FROM pem.probe WHERE internal_name='streaming_replication_db_conflicts'), 20906, NULL);

-- xdb_smr_mmr_replication support
INSERT INTO pem.probe_server_version(probe_id,server_version_id,probe_code)
       VALUES((SELECT id FROM pem.probe WHERE internal_name='xdb_smr_mmr_replication'), 10906, NULL);

INSERT INTO pem.probe_server_version(probe_id,server_version_id,probe_code)
       VALUES((SELECT id FROM pem.probe WHERE internal_name='xdb_smr_mmr_replication'), 20906, NULL);

-- oc_views support
INSERT INTO pem.probe_server_version(probe_id,server_version_id,probe_code)
       VALUES((SELECT id FROM pem.probe WHERE internal_name='oc_views'), 10906, NULL);

INSERT INTO pem.probe_server_version(probe_id,server_version_id,probe_code)
       VALUES((SELECT id FROM pem.probe WHERE internal_name='oc_views'), 20906, NULL);

-- mview_bloat support
INSERT INTO pem.probe_server_version(probe_id,server_version_id,probe_code)
       VALUES((SELECT id FROM pem.probe WHERE internal_name='mview_bloat'), 10906, NULL);

INSERT INTO pem.probe_server_version(probe_id,server_version_id,probe_code)
       VALUES((SELECT id FROM pem.probe WHERE internal_name='mview_bloat'), 20906, NULL);

-- mview_frozenxid support
INSERT INTO pem.probe_server_version(probe_id,server_version_id,probe_code)
       VALUES((SELECT id FROM pem.probe WHERE internal_name='mview_frozenxid'), 10906, NULL);

INSERT INTO pem.probe_server_version(probe_id,server_version_id,probe_code)
       VALUES((SELECT id FROM pem.probe WHERE internal_name='mview_frozenxid'), 20906, NULL);

-- mview_size support
INSERT INTO pem.probe_server_version(probe_id,server_version_id,probe_code)
       VALUES((SELECT id FROM pem.probe WHERE internal_name='mview_size'), 10906, NULL);

INSERT INTO pem.probe_server_version(probe_id,server_version_id,probe_code)
       VALUES((SELECT id FROM pem.probe WHERE internal_name='mview_size'), 20906, NULL);

-- streaming_replication_lag_time support
INSERT INTO pem.probe_server_version(probe_id,server_version_id,probe_code)
       VALUES((SELECT id FROM pem.probe WHERE internal_name='streaming_replication_lag_time'), 10906, NULL);

INSERT INTO pem.probe_server_version(probe_id,server_version_id,probe_code)
       VALUES((SELECT id FROM pem.probe WHERE internal_name='streaming_replication_lag_time'), 20906, NULL);

-- wal_archive_status support
INSERT INTO pem.probe_server_version(probe_id,server_version_id,probe_code)
       VALUES((SELECT id FROM pem.probe WHERE internal_name='wal_archive_status'), 10906,
       'SELECT archived_count, last_archived_time, failed_count, last_failed_time FROM pg_catalog.pg_stat_archiver');

INSERT INTO pem.probe_server_version(probe_id,server_version_id,probe_code)
       VALUES((SELECT id FROM pem.probe WHERE internal_name='wal_archive_status'), 20906,
       'SELECT archived_count, last_archived_time, failed_count, last_failed_time FROM pg_catalog.pg_stat_archiver');

-- system_waits support
INSERT INTO pem.probe_server_version(probe_id,server_version_id,probe_code)
       VALUES((SELECT id FROM pem.probe WHERE internal_name='system_waits'), 20906, NULL);

-- session_waits support
INSERT INTO pem.probe_server_version(probe_id,server_version_id,probe_code)
       VALUES((SELECT id FROM pem.probe WHERE internal_name='session_waits'), 20906,
       'SELECT sw.backend_id, psa.datname AS dbname, psa.usename, sw.wait_name, sw.wait_count, avg_wait_time, max_wait_time, total_wait_time FROM session_waits sw, pg_stat_activity psa WHERE sw.backend_id = psa.pid');

-- audit_configuration support
INSERT INTO pem.probe_server_version(probe_id,server_version_id,probe_code)
       VALUES((SELECT id FROM pem.probe WHERE internal_name='audit_configuration'), 20906, NULL);

--oc_extension support
INSERT INTO pem.probe_server_version(probe_id, server_version_id, probe_code)
VALUES ((SELECT id from pem.probe WHERE internal_name ='oc_extension'), 10906, NULL);
INSERT INTO pem.probe_server_version(probe_id, server_version_id, probe_code)
VALUES ((SELECT id from pem.probe WHERE internal_name ='oc_extension'), 20906, NULL);

--efm_cluster_info support
INSERT INTO pem.probe_server_version(probe_id, server_version_id, probe_code)
VALUES ((SELECT id from pem.probe WHERE internal_name ='efm_cluster_info'), 10906, NULL);
INSERT INTO pem.probe_server_version(probe_id, server_version_id, probe_code)
VALUES ((SELECT id from pem.probe WHERE internal_name ='efm_cluster_info'), 20906, NULL);

--efm_cluster_node_status support
INSERT INTO pem.probe_server_version(probe_id, server_version_id, probe_code)
VALUES ((SELECT id from pem.probe WHERE internal_name ='efm_cluster_node_status'), 10906, NULL);
INSERT INTO pem.probe_server_version(probe_id, server_version_id, probe_code)
VALUES ((SELECT id from pem.probe WHERE internal_name ='efm_cluster_node_status'), 20906, NULL);

-- Fixes RM #39253 #39255
CREATE OR REPLACE FUNCTION pem.server_tuning_oltp (tune_server_id int, utilisation pem.tuning_server_util, total_ram numeric, shared_memory numeric, is_windows boolean)
RETURNS TABLE (tuned_parameter text, tuned_value text, orig_value text)
AS $$
DECLARE
	server_max_conn int := 0;
	server_max_locks_per_xact int := 0;
	server_max_prepared_xacts int := 0;
	server_version int := 0;
	converted_value int := 0;
	shared_mem numeric(1000,0) := shared_memory;
	work_mem_factor decimal := 0.008;
	maint_work_mem_factor decimal := 0.08;
	server_chkpnt_cmpl_trgt decimal := 0.5;
	work_mem bigint := 0;
	maint_work_mem bigint := 0;
	shared_buffers bigint := 0;
	wal_buffers bigint := 0;
	eff_cache_size bigint := 0;
	is_checkpoint_segment_allowed boolean := TRUE;
BEGIN
	SELECT setting FROM pemdata.settings WHERE server_id = tune_server_id AND name='max_connections' INTO server_max_conn;
	SELECT setting FROM pemdata.settings WHERE server_id = tune_server_id AND name='max_locks_per_transaction' INTO server_max_locks_per_xact;
	SELECT setting FROM pemdata.settings WHERE server_id = tune_server_id AND name='max_prepared_transactions' INTO server_max_prepared_xacts;
	SELECT setting FROM pemdata.settings WHERE server_id = tune_server_id AND name='checkpoint_completion_target' INTO server_chkpnt_cmpl_trgt;
	SELECT server_version_id FROM pemdata.server_info WHERE server_id = tune_server_id INTO server_version;

	-- calculate amount of memory utilized for max_connections and subtract it from shared memory
	-- to calculate work_mem and maintainance_work_mem
	shared_mem := shared_mem - (server_max_conn * 620 * server_max_locks_per_xact);
	shared_mem := shared_mem - (server_max_prepared_xacts * 820 * server_max_locks_per_xact);

	-- calculate work_mem
	work_mem := round(shared_mem * work_mem_factor);
	work_mem := round(work_mem / (1024)::decimal);

	-- work_mem needs to be at least 1MB
	IF work_mem < 1024 THEN
		work_mem := 1024;
	END IF;

	work_mem := round(work_mem / (1024)::decimal);

	tuned_parameter := 'work_mem';
	tuned_value := work_mem || 'MB';
	orig_value := pem.server_tuning_original_value(tune_server_id, 'work_mem');
	RETURN NEXT;

	shared_mem := shared_mem - (work_mem * 1024 *1024);

	-- calculate maintainence_work_mem
	maint_work_mem := round(shared_mem * maint_work_mem_factor);
	maint_work_mem := round(maint_work_mem / (1024 * 1024)::decimal);

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
	orig_value := pem.server_tuning_original_value(tune_server_id, 'maintenance_work_mem');
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
			shared_buffers := round(total_ram * (0.25)::decimal);
		END IF;
	ELSE
		IF is_windows THEN
			-- set it default to 256MB
			shared_buffers := 256 * 1024 * 1024;
		ELSE
			-- set 40% of total RAM
			shared_buffers := round(total_ram * (0.40)::decimal);
		END IF;
	END IF;

	shared_buffers := round(shared_buffers / (1024*1024)::decimal);

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
	orig_value := pem.server_tuning_original_value(tune_server_id, 'shared_buffers');
	RETURN NEXT;

	-- calculate wal_buffers
	shared_buffers := shared_buffers * 1024 * 1024;
	wal_buffers := round(shared_buffers / (8)::decimal);

	-- wal_buffers needs to be at max 16MB
	IF wal_buffers > 16777216 THEN
		wal_buffers := 16777216;
	END IF;

	-- wal_buffers needs to be at least 64KB
	IF wal_buffers < 65536 THEN
		wal_buffers := 65536;
	END IF;

	tuned_parameter := 'wal_buffers';
	IF (wal_buffers / (1048576)::decimal) > 1.00 THEN
		wal_buffers := round(wal_buffers / (1048576)::decimal);
		tuned_value := wal_buffers || 'MB';
	ELSE
		wal_buffers := round(wal_buffers / (1024)::decimal);
		tuned_value := wal_buffers || 'kB';
	END IF;
	orig_value := pem.server_tuning_original_value(tune_server_id, 'wal_buffers');
	RETURN NEXT;

	-- calculate effective_cache_size
	IF utilisation = 'UTILISATION_DEDICATED' THEN
		eff_cache_size := round(total_ram * (0.75)::decimal);
	ELSIF utilisation = 'UTILISATION_MIXED' THEN
		eff_cache_size := round(total_ram * (0.5)::decimal);
	ELSE
		eff_cache_size := round(total_ram * (0.25)::decimal);
	END IF;

	eff_cache_size := round(eff_cache_size / (1048576)::decimal);

	tuned_parameter := 'effective_cache_size';
	tuned_value := eff_cache_size || 'MB';
	orig_value := pem.server_tuning_original_value(tune_server_id, 'effective_cache_size');
	RETURN NEXT;

	-- calculate random_page_cost
	tuned_parameter := 'random_page_cost';
	IF utilisation = 'UTILISATION_DEDICATED' THEN
		tuned_value := '2';
	ELSIF utilisation = 'UTILISATION_MIXED' THEN
		tuned_value := '2.5';
	ELSE
		tuned_value := '3';
	END IF;
	orig_value := pem.server_tuning_original_value(tune_server_id, 'random_page_cost');
	RETURN NEXT;

	-- check if checkpoint_segement is allowed or not depending upon the server version
	IF server_version >= 20905 THEN
		is_checkpoint_segment_allowed = false;
	ELSIF server_version >=10905 and server_version < 20000 THEN
		is_checkpoint_segment_allowed = false;
	ELSE
		is_checkpoint_segment_allowed = true;
	END IF;

	-- calculate checkpoint_segments for server_version < 9.5 and max_wal_size for server_version >= 9.5
	IF utilisation = 'UTILISATION_DEDICATED' THEN
		tuned_value := '32';
	ELSIF utilisation = 'UTILISATION_MIXED' THEN
		tuned_value := '16';
	ELSE
		tuned_value := '6';
	END IF;

	IF is_checkpoint_segment_allowed = TRUE THEN
		tuned_parameter := 'checkpoint_segments';
		orig_value := pem.server_tuning_original_value(tune_server_id, 'checkpoint_segments');
	ELSE
		tuned_parameter := 'max_wal_size';
		-- Reference: http://www.postgresql.org/message-id/E1YPwGB-0006vL-8V@gemulon.postgresql.org
		-- max_wal_size has been calculated using below formula:
		-- max_wal_size = ((2 + checkpoint_completion_target) * checkpoint_segments + 1)*wal_size
		-- where checkpoint_completion_target = Specifies the target of checkpoint completion, as a fraction of total time between checkpoints
		-- default value is 0.5
		-- checkpoint_segments = no of checkpoint decided depending upon utilization. default value is 6
		-- wal_size = size of wal file = 16 MB
		tuned_value = ((((server_chkpnt_cmpl_trgt)::decimal + (2)::decimal) * (tuned_value)::decimal) + (1)::integer) * (16)::integer;
		IF ((tuned_value)::decimal / (1024)::decimal) >= 1.00 THEN
			tuned_value := round((tuned_value)::decimal / (1024)::decimal) || 'GB';
		ELSE
			tuned_value := round((tuned_value)::decimal) || 'MB';
		END IF;
		SELECT COALESCE(SUBSTRING(setting from '[0-9]+'), '1')::decimal FROM pemdata.settings WHERE server_id = tune_server_id AND name = 'max_wal_size' INTO orig_value;
		converted_value := round((orig_value)::decimal * (16)::decimal);
	        IF (converted_value / (1024)::decimal) >= 1.00 THEN
			orig_value := round((converted_value)::decimal / (1024)::decimal) || 'GB';
		ELSE
			orig_value := round((converted_value)::decimal) || 'MB';
		END IF;
	END IF;
	RETURN NEXT;

	-- add min_wal_size for server_version < 9.5 and max_wal_size for server_version >= 9.5
	-- min_wal_size has the fixed size of 80 MB
	IF is_checkpoint_segment_allowed = FALSE THEN
		tuned_parameter := 'min_wal_size';
		tuned_value = '80MB';
		SELECT COALESCE(SUBSTRING(setting from '[0-9]+'), '1')::decimal FROM pemdata.settings WHERE server_id = tune_server_id AND name = 'min_wal_size' INTO orig_value;
		converted_value := round((orig_value)::decimal * (16)::decimal);
		IF (converted_value / (1024)::decimal) >= 1.00 THEN
			orig_value := round((converted_value)::decimal / (1024)::decimal) || 'GB';
		ELSE
			orig_value := round((converted_value)::decimal) || 'MB';
		END IF;
		RETURN NEXT;
	END IF;
	RETURN;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION pem.server_tuning_mixed (tune_server_id int, utilisation pem.tuning_server_util, total_ram numeric, shared_memory numeric, is_windows boolean)
RETURNS TABLE (tuned_parameter text, tuned_value text, orig_value text)
AS $$
DECLARE
	server_max_conn int := 0;
	server_max_locks_per_xact int := 0;
	server_max_prepared_xacts int := 0;
	server_version int := 0;
	converted_value int := 0;
	shared_mem numeric(1000,0) := shared_memory;
	work_mem_factor decimal := 0.012;
	maint_work_mem_factor decimal := 0.1;
	server_chkpnt_cmpl_trgt decimal := 0.5;
	work_mem bigint := 0;
	maint_work_mem bigint := 0;
	shared_buffers bigint := 0;
	wal_buffers bigint := 0;
	eff_cache_size bigint := 0;
	is_checkpoint_segment_allowed boolean := TRUE;
BEGIN
	SELECT setting FROM pemdata.settings WHERE server_id = tune_server_id AND name='max_connections' INTO server_max_conn;
	SELECT setting FROM pemdata.settings WHERE server_id = tune_server_id AND name='max_locks_per_transaction' INTO server_max_locks_per_xact;
	SELECT setting FROM pemdata.settings WHERE server_id = tune_server_id AND name='max_prepared_transactions' INTO server_max_prepared_xacts;
	SELECT setting FROM pemdata.settings WHERE server_id = tune_server_id AND name='checkpoint_completion_target' INTO server_chkpnt_cmpl_trgt;
	SELECT server_version_id FROM pemdata.server_info WHERE server_id = tune_server_id INTO server_version;

	-- calculate amount of memory utilized for max_connections and subtract it from shared memory
	-- to calculate work_mem and maintainance_work_mem
	shared_mem := shared_mem - (server_max_conn * 620 * server_max_locks_per_xact);
	shared_mem := shared_mem - (server_max_prepared_xacts * 820 * server_max_locks_per_xact);

	-- calculate work_mem
	work_mem := round(shared_mem * work_mem_factor);
	work_mem := round(work_mem / (1024)::decimal);

	-- work_mem needs to be at least 1MB
	IF work_mem < 1024 THEN
		work_mem := 1024;
	END IF;

	work_mem := round(work_mem / (1024)::decimal);

	tuned_parameter := 'work_mem';
	tuned_value := work_mem || 'MB';
	orig_value := pem.server_tuning_original_value(tune_server_id, 'work_mem');
	RETURN NEXT;

	shared_mem := shared_mem - (work_mem * 1024 *1024);

	-- calculate maintainence_work_mem
	maint_work_mem := round(shared_mem * maint_work_mem_factor);
	maint_work_mem := round(maint_work_mem / (1024 * 1024)::decimal);

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
	orig_value := pem.server_tuning_original_value(tune_server_id, 'maintenance_work_mem');
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
			shared_buffers := round(total_ram * (0.25)::decimal);
		END IF;
	ELSE
		IF is_windows THEN
			-- set it default to 256MB
			shared_buffers := 256 * 1024 * 1024;
		ELSE
			-- set 40% of total RAM
			shared_buffers := round(total_ram * (0.40)::decimal);
		END IF;
	END IF;

	shared_buffers := round(shared_buffers / (1024*1024)::decimal);

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
	orig_value := pem.server_tuning_original_value(tune_server_id, 'shared_buffers');
	RETURN NEXT;

	-- calculate wal_buffers
	shared_buffers := shared_buffers * 1024 * 1024;
	wal_buffers := round(shared_buffers / (16)::decimal);

	-- wal_buffers needs to be at max 16MB
	IF wal_buffers > 16777216 THEN
		wal_buffers := 16777216;
	END IF;

	-- wal_buffers needs to be at least 64KB
	IF wal_buffers < 65536 THEN
		wal_buffers := 65536;
	END IF;

	tuned_parameter := 'wal_buffers';
	IF (wal_buffers / (1048576)::decimal) > 1.00 THEN
		wal_buffers := round(wal_buffers / (1048576)::decimal);
		tuned_value := wal_buffers || 'MB';
	ELSE
		wal_buffers := round(wal_buffers / (1024)::decimal);
		tuned_value := wal_buffers || 'kB';
	END IF;
	orig_value := pem.server_tuning_original_value(tune_server_id, 'wal_buffers');
	RETURN NEXT;

	-- calculate effective_cache_size
	IF utilisation = 'UTILISATION_DEDICATED' THEN
		eff_cache_size := round(total_ram * (0.75)::decimal);
	ELSIF utilisation = 'UTILISATION_MIXED' THEN
		eff_cache_size := round(total_ram * (0.5)::decimal);
	ELSE
		eff_cache_size := round(total_ram * (0.25)::decimal);
	END IF;

	eff_cache_size := round(eff_cache_size / (1048576)::decimal);

	tuned_parameter := 'effective_cache_size';
	tuned_value := eff_cache_size || 'MB';
	orig_value := pem.server_tuning_original_value(tune_server_id, 'effective_cache_size');
	RETURN NEXT;

	-- calculate random_page_cost
	tuned_parameter := 'random_page_cost';
	IF utilisation = 'UTILISATION_DEDICATED' THEN
		tuned_value := '2';
	ELSIF utilisation = 'UTILISATION_MIXED' THEN
		tuned_value := '2.5';
	ELSE
		tuned_value := '3';
	END IF;
	orig_value := pem.server_tuning_original_value(tune_server_id, 'random_page_cost');
	RETURN NEXT;

		-- check if checkpoint_segement is allowed or not depending upon the server version
	IF server_version >= 20905 THEN
		is_checkpoint_segment_allowed = false;
	ELSIF server_version >=10905 and server_version < 20000 THEN
		is_checkpoint_segment_allowed = false;
	ELSE
		is_checkpoint_segment_allowed = true;
	END IF;

	-- calculate checkpoint_segments for server_version < 9.5 and max_wal_size for server_version >= 9.5
	IF utilisation = 'UTILISATION_DEDICATED' THEN
		tuned_value := '48';
	ELSIF utilisation = 'UTILISATION_MIXED' THEN
		tuned_value := '24';
	ELSE
		tuned_value := '6';
	END IF;

	IF is_checkpoint_segment_allowed = TRUE THEN
		tuned_parameter := 'checkpoint_segments';
		orig_value := pem.server_tuning_original_value(tune_server_id, 'checkpoint_segments');
	ELSE
		tuned_parameter := 'max_wal_size';
		-- Reference: http://www.postgresql.org/message-id/E1YPwGB-0006vL-8V@gemulon.postgresql.org
		-- max_wal_size has been calculated using below formula:
		-- max_wal_size = ((2 + checkpoint_completion_target) * checkpoint_segments + 1)*wal_size
		-- where checkpoint_completion_target = Specifies the target of checkpoint completion, as a fraction of total time between checkpoints
		-- default value is 0.5
		-- checkpoint_segments = no of checkpoint decided depending upon utilization. default value is 6
		-- wal_size = size of wal file = 16 MB
		tuned_value = ((((server_chkpnt_cmpl_trgt)::decimal + (2)::decimal) * (tuned_value)::decimal) + (1)::integer) * (16)::integer;
		IF ((tuned_value)::decimal / (1024)::decimal) >= 1.00 THEN
			tuned_value := round((tuned_value)::decimal / (1024)::decimal) || 'GB';
		ELSE
			tuned_value := round((tuned_value)::decimal) || 'MB';
		END IF;
		SELECT COALESCE(SUBSTRING(setting from '[0-9]+'), '1')::decimal FROM pemdata.settings WHERE server_id = tune_server_id AND name = 'max_wal_size' INTO orig_value;
		converted_value := round((orig_value)::decimal * (16)::decimal);
		IF (converted_value / (1024)::decimal) >= 1.00 THEN
			orig_value := round((converted_value)::decimal / (1024)::decimal) || 'GB';
		ELSE
			orig_value := round((converted_value)::decimal) || 'MB';
		END IF;
	END IF;
	RETURN NEXT;

	-- add min_wal_size for server_version < 9.5 and max_wal_size for server_version >= 9.5
	-- min_wal_size has the fixed size of 80 MB
	IF is_checkpoint_segment_allowed = FALSE THEN
		tuned_parameter := 'min_wal_size';
		tuned_value = '80MB';
		SELECT COALESCE(SUBSTRING(setting from '[0-9]+'), '1')::decimal FROM pemdata.settings WHERE server_id = tune_server_id AND name = 'min_wal_size' INTO orig_value;
		converted_value := round((orig_value)::decimal * (16)::decimal);
		IF (converted_value / (1024)::decimal) >= 1.00 THEN
			orig_value := round((converted_value)::decimal / (1024)::decimal) || 'GB';
		ELSE
			orig_value := round((converted_value)::decimal) || 'MB';
		END IF;
		RETURN NEXT;
	END IF;
	RETURN;
END
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION pem.server_tuning_dw (tune_server_id int, utilisation pem.tuning_server_util, total_ram numeric, shared_memory numeric, is_windows boolean)
RETURNS TABLE (tuned_parameter text, tuned_value text, orig_value text)
AS $$
DECLARE
	server_max_conn int := 0;
	server_max_locks_per_xact int := 0;
	server_max_prepared_xacts int := 0;
	server_version int := 0;
	converted_value int := 0;
	shared_mem numeric(1000,0) := shared_memory;
	work_mem_factor decimal := 0.020;
	maint_work_mem_factor decimal := 0.2;
	server_chkpnt_cmpl_trgt decimal := 0.5;
	work_mem bigint := 0;
	maint_work_mem bigint := 0;
	shared_buffers bigint := 0;
	wal_buffers bigint := 0;
	eff_cache_size bigint := 0;
	is_checkpoint_segment_allowed boolean := TRUE;
BEGIN
	SELECT setting FROM pemdata.settings WHERE server_id = tune_server_id AND name='max_connections' INTO server_max_conn;
	SELECT setting FROM pemdata.settings WHERE server_id = tune_server_id AND name='max_locks_per_transaction' INTO server_max_locks_per_xact;
	SELECT setting FROM pemdata.settings WHERE server_id = tune_server_id AND name='max_prepared_transactions' INTO server_max_prepared_xacts;
	SELECT setting FROM pemdata.settings WHERE server_id = tune_server_id AND name='checkpoint_completion_target' INTO server_chkpnt_cmpl_trgt;
	SELECT server_version_id FROM pemdata.server_info WHERE server_id = tune_server_id INTO server_version;

	-- calculate amount of memory utilized for max_connections and subtract it from shared memory
	-- to calculate work_mem and maintainance_work_mem
	shared_mem := shared_mem - (server_max_conn * 620 * server_max_locks_per_xact);
	shared_mem := shared_mem - (server_max_prepared_xacts * 820 * server_max_locks_per_xact);

	-- calculate work_mem
	work_mem := round(shared_mem * work_mem_factor);
	work_mem := round(work_mem / (1024)::decimal);

	-- work_mem needs to be at least 1MB
	IF work_mem < 1024 THEN
		work_mem := 1024;
	END IF;

	work_mem := round(work_mem / (1024)::decimal);

	tuned_parameter := 'work_mem';
	tuned_value := work_mem || 'MB';
	orig_value := pem.server_tuning_original_value(tune_server_id, 'work_mem');
	RETURN NEXT;

	shared_mem := shared_mem - (work_mem * 1024 *1024);

	-- calculate maintainence_work_mem
	maint_work_mem := round(shared_mem * maint_work_mem_factor);
	maint_work_mem := round(maint_work_mem / (1024 * 1024)::decimal);

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
	orig_value := pem.server_tuning_original_value(tune_server_id, 'maintenance_work_mem');
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
			shared_buffers := round(total_ram * (0.25)::decimal);
		END IF;
	ELSE
		IF is_windows THEN
			-- set it default to 256MB
			shared_buffers := 256 * 1024 * 1024;
		ELSE
			-- set 40% of total RAM
			shared_buffers := round(total_ram * (0.40)::decimal);
		END IF;
	END IF;

	shared_buffers := round(shared_buffers / (1024*1024)::decimal);

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
	orig_value := pem.server_tuning_original_value(tune_server_id, 'shared_buffers');
	RETURN NEXT;

	-- calculate wal_buffers
	shared_buffers := shared_buffers * 1024 * 1024;
	wal_buffers := round(shared_buffers / (32)::decimal);

	-- wal_buffers needs to be at max 16MB
	IF wal_buffers > 16777216 THEN
		wal_buffers := 16777216;
	END IF;

	-- wal_buffers needs to be at least 64KB
	IF wal_buffers < 65536 THEN
		wal_buffers := 65536;
	END IF;

	tuned_parameter := 'wal_buffers';
	IF (wal_buffers / (1048576)::decimal) > 1.00 THEN
		wal_buffers := round(wal_buffers / (1048576)::decimal);
		tuned_value := wal_buffers || 'MB';
	ELSE
		wal_buffers := round(wal_buffers / (1024)::decimal);
		tuned_value := wal_buffers || 'kB';
	END IF;
	orig_value := pem.server_tuning_original_value(tune_server_id, 'wal_buffers');
	RETURN NEXT;

	-- calculate effective_cache_size
	IF utilisation = 'UTILISATION_DEDICATED' THEN
		eff_cache_size := round(total_ram * (0.75)::decimal);
	ELSIF utilisation = 'UTILISATION_MIXED' THEN
		eff_cache_size := round(total_ram * (0.5)::decimal);
	ELSE
		eff_cache_size := round(total_ram * (0.25)::decimal);
	END IF;

	eff_cache_size := round(eff_cache_size / (1048576)::decimal);

	tuned_parameter := 'effective_cache_size';
	tuned_value := eff_cache_size || 'MB';
	orig_value := pem.server_tuning_original_value(tune_server_id, 'effective_cache_size');
	RETURN NEXT;

	-- calculate random_page_cost
	tuned_parameter := 'random_page_cost';
	IF utilisation = 'UTILISATION_DEDICATED' THEN
		tuned_value := '2';
	ELSIF utilisation = 'UTILISATION_MIXED' THEN
		tuned_value := '2.5';
	ELSE
		tuned_value := '3';
	END IF;
	orig_value := pem.server_tuning_original_value(tune_server_id, 'random_page_cost');
	RETURN NEXT;

		-- check if checkpoint_segement is allowed or not depending upon the server version
	IF server_version >= 20905 THEN
		is_checkpoint_segment_allowed = false;
	ELSIF server_version >=10905 and server_version < 20000 THEN
		is_checkpoint_segment_allowed = false;
	ELSE
		is_checkpoint_segment_allowed = true;
	END IF;

	-- calculate checkpoint_segments for server_version < 9.5 and max_wal_size for server_version >= 9.5
	IF utilisation = 'UTILISATION_DEDICATED' THEN
		tuned_value := '64';
	ELSIF utilisation = 'UTILISATION_MIXED' THEN
		tuned_value := '32';
	ELSE
		tuned_value := '6';
	END IF;

	IF is_checkpoint_segment_allowed = TRUE THEN
		tuned_parameter := 'checkpoint_segments';
		orig_value := pem.server_tuning_original_value(tune_server_id, 'checkpoint_segments');
	ELSE
		tuned_parameter := 'max_wal_size';
		-- Reference: http://www.postgresql.org/message-id/E1YPwGB-0006vL-8V@gemulon.postgresql.org
		-- max_wal_size has been calculated using below formula:
		-- max_wal_size = ((2 + checkpoint_completion_target) * checkpoint_segments + 1)*wal_size
		-- where checkpoint_completion_target = Specifies the target of checkpoint completion, as a fraction of total time between checkpoints
		-- default value is 0.5
		-- checkpoint_segments = no of checkpoint decided depending upon utilization. default value is 6
		-- wal_size = size of wal file = 16 MB
		tuned_value = ((((server_chkpnt_cmpl_trgt)::decimal + (2)::decimal) * (tuned_value)::decimal) + (1)::integer) * (16)::integer;
		IF ((tuned_value)::decimal / (1024)::decimal) >= 1.00 THEN
			tuned_value := round((tuned_value)::decimal / (1024)::decimal) || 'GB';
		ELSE
			tuned_value := round((tuned_value)::decimal) || 'MB';
		END IF;
		SELECT COALESCE(SUBSTRING(setting from '[0-9]+'), '1')::decimal FROM pemdata.settings WHERE server_id = tune_server_id AND name = 'max_wal_size' INTO orig_value;
		converted_value := round((orig_value)::decimal * (16)::decimal);
		IF (converted_value / (1024)::decimal) >= 1.00 THEN
			orig_value := round((converted_value)::decimal / (1024)::decimal) || 'GB';
		ELSE
			orig_value := round((converted_value)::decimal) || 'MB';
		END IF;
	END IF;
	RETURN NEXT;

	-- add min_wal_size for server_version < 9.5 and max_wal_size for server_version >= 9.5
	-- min_wal_size has the fixed size of 80 MB
	IF is_checkpoint_segment_allowed = FALSE THEN
		tuned_parameter := 'min_wal_size';
		tuned_value = '80MB';
		SELECT COALESCE(SUBSTRING(setting from '[0-9]+'), '1')::decimal FROM pemdata.settings WHERE server_id = tune_server_id AND name = 'min_wal_size' INTO orig_value;
		converted_value := round((orig_value)::decimal * (16)::decimal);
		IF (converted_value / (1024)::decimal) >= 1.00 THEN
			orig_value := round((converted_value)::decimal / (1024)::decimal) || 'GB';
		ELSE
			orig_value := round((converted_value)::decimal) || 'MB';
		END IF;
		RETURN NEXT;
	END IF;
	RETURN;
END
$$ LANGUAGE plpgsql;

-- Fixes RM #38891
/*************************
* Proxy Server settings  *
**************************/
INSERT INTO pem.config (param, value, unit, datatype) VALUES ('proxy_server_enabled', 'f', 't/f', 'bool'); -- Should proxy server be used (t/f)?
INSERT INTO pem.config (param, value, unit, datatype) VALUES ('proxy_server', '127.0.0.1', '', 'string'); -- Proxy server/smarthost to use
INSERT INTO pem.config (param, value, unit, datatype) VALUES ('proxy_server_port', '80', '', 'integer'); -- Proxy server port
INSERT INTO pem.config (param, value, unit, datatype) VALUES ('proxy_server_authentication', 'f', 't/f', 'bool'); -- Required authentication (t/f)
INSERT INTO pem.config (param, value, unit, datatype) VALUES ('proxy_server_username', NULL, '', 'string'); -- The username for the Proxy server
INSERT INTO pem.config (param, value, unit, datatype) VALUES ('proxy_server_password', NULL, '', 'string'); -- The password for the Proxy server

COMMIT TRANSACTION;
