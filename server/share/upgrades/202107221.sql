/***************************************************************************
 *
 * Postgres Enterprise Manager
 *
 * Copyright (C) 2010 - 2025, EnterpriseDB Corporation. All rights reserved.
 *
 ***************************************************************************/

-- NOTE: This sql file is responsible for PEM 8.2.0 schema upgrade.

BEGIN TRANSACTION;

CREATE OR REPLACE FUNCTION pem.schema_version() RETURNS integer AS
'SELECT 202107221::integer;'
LANGUAGE 'sql' IMMUTABLE;
COMMENT ON FUNCTION pem.schema_version()
	IS 'Returns the version number of the PEM schema';


-- Create PEM unique system id for each installation
DO $$
DECLARE
	uuid text;
BEGIN
    -- If we already have unique id then skip
    IF NOT EXISTS ( SELECT * FROM pg_proc WHERE proname = 'system_uid' AND prokind = 'f' ) THEN
        RAISE NOTICE 'Generating unique PEM installation id...';
        -- Generate unique id
        SELECT REGEXP_REPLACE(
            EXTRACT(epoch FROM now())::text, '\.', ''
        )::text || floor(random()* (999999-100001 + 1) + 100001)::text AS id INTO uuid;

        -- Create a function using above id
        EXECUTE format(E'CREATE FUNCTION pem.system_uid() RETURNS text AS \'SELECT %s::text\' LANGUAGE SQL IMMUTABLE;', uuid);

        COMMENT ON FUNCTION pem.system_uid()
            IS 'Returns the unique system installation id';
    END IF;
END;
$$ LANGUAGE plpgsql;


DO $$
DECLARE
    uuid                text;
	tmp					text;
    internal_name       text;
    old_internal_name   text;
	error_msg           text;
	probe_sql           text;
	probe_sql_curs      REFCURSOR;
    rec                 RECORD;
	t_sql               text;
	t_sql_curs          REFCURSOR;
    t_rec               RECORD;
    column_string       text;
    new_column_string   text;
    key_string          text;
    old_key_string      text;
    r                   RECORD;
    quoted_table_name   varchar;
    trigger_command     varchar;
    trigger_function_command varchar;
BEGIN
    -- Fetch PEM system id
    EXECUTE 'SELECT pem.system_uid();' INTO uuid;
    -- SQL to fetch all the custom probes
    probe_sql := E'SELECT * FROM pem.probe WHERE is_system_probe = false AND deleted = false AND internal_name LIKE \'cp_%\'';

    BEGIN
        OPEN probe_sql_curs FOR EXECUTE probe_sql;
        -- START MAIN
        LOOP
            FETCH NEXT FROM probe_sql_curs INTO rec;
            EXIT WHEN NOT FOUND;

            -- New format for custom probe will be probe_<pem_id>_<id>
            old_internal_name := rec.internal_name;
            internal_name := 'probe_' || TRIM(uuid) || '_' || rec.id::text;
			tmp := internal_name;
            RAISE NOTICE 'Renaming custom probe % -> %', old_internal_name, internal_name;

	        IF NOT EXISTS (SELECT id FROM pem.probe p where p.internal_name = tmp) THEN

				-- Update the probe table 'pem.probe'
                EXECUTE format('UPDATE pem.probe SET internal_name = %L WHERE id = %L', internal_name, rec.id);

                -- Trigger Function Command String
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
                    probe_id = rec.id;

                -- Rename probe cp_* tables & trigger function to new name

                -- There won't be any trigger function or a trigger in case discard_history flag is true for a probe.
                IF NOT rec.discard_history THEN
                    EXECUTE format('DROP TRIGGER IF EXISTS %I ON %s', 'copy_' || old_internal_name || '_to_history', 'pemdata.' || old_internal_name);
                    EXECUTE format('ALTER FUNCTION pemdata.%I RENAME TO %I', 'copy_' || old_internal_name || '_to_history', 'copy_' || internal_name || '_to_history');
                    -- Update trigger function
                    quoted_table_name := quote_ident(internal_name);
                    trigger_function_command := 'CREATE OR REPLACE FUNCTION pemdata.' ||  quote_ident('copy_' || internal_name || '_to_history') || '() RETURNS TRIGGER AS $f$
                    BEGIN
                        IF (TG_OP = ''INSERT'' OR TG_OP = ''UPDATE'') THEN
                            INSERT INTO pemhistory.' || quoted_table_name || ' (' || r.column_string || ') VALUES (' || r.new_column_string || ');
                            ELSIF EXISTS(SELECT 1 FROM ' || CASE WHEN rec.target_type_id = 100 THEN 'pem.agent WHERE id = OLD.agent_id' ELSE 'pem.server WHERE id = OLD.server_id' END || ') THEN
                            INSERT INTO pemhistory.' || quoted_table_name || ' (' || r.key_string || ') VALUES (' || r.old_key_string || ');
                        END IF;
                        RETURN NEW;
                    END;
                    $f$ LANGUAGE plpgsql;';

                    -- Trigger Command String
                    trigger_command := 'CREATE TRIGGER ' || quote_ident('copy_' || internal_name || '_to_history') || ' AFTER INSERT OR UPDATE OR DELETE ON pemdata.' || old_internal_name || ' FOR EACH ROW EXECUTE PROCEDURE pemdata.' || quote_ident('copy_' || internal_name || '_to_history') || '()' ;

                    -- Execute the commands.
                    EXECUTE trigger_function_command;
                    EXECUTE trigger_command;
                END IF;


                -- Trigger Function for calculating PIT values definition
                IF COALESCE(r.data_trigger_clause, '') != ''
                THEN
                    EXECUTE format('DROP TRIGGER IF EXISTS %I ON %s', 'calculate_' || old_internal_name || '_pit_value', 'pemdata.' || old_internal_name);
                    EXECUTE format('ALTER FUNCTION pemdata.%I RENAME TO %I', 'calculate_' || old_internal_name || '_pit_value', 'calculate_' || internal_name || '_pit_value');
                    -- Trigger Function Command String
                    trigger_function_command := 'CREATE OR REPLACE FUNCTION pemdata.' ||  quote_ident('calculate_' || internal_name || '_pit_value') || E'() RETURNS TRIGGER AS $f$
                    BEGIN
                        IF (TG_OP = ''UPDATE'') THEN \n'
                         ||  r.data_trigger_clause ||
                        E'\n    END IF;
                        RETURN NEW;
                    END;
                    $f$ LANGUAGE plpgsql;';

                    -- Trigger Command String
                    trigger_command := 'CREATE TRIGGER ' || quote_ident('calculate_' || internal_name || '_pit_value') || ' BEFORE UPDATE ON pemdata.' || old_internal_name || ' FOR EACH ROW EXECUTE PROCEDURE pemdata.' || quote_ident('calculate_' || internal_name || '_pit_value') || '()' ;

                    -- Execute the commands.
                    EXECUTE trigger_function_command;
                    EXECUTE trigger_command;
                END IF;

                EXECUTE format('ALTER TABLE IF EXISTS pemdata.%I RENAME TO %I', old_internal_name, internal_name);

                -- There won't be any history table in case discard_history flag is true for a probe.
                IF NOT rec.discard_history THEN
                    EXECUTE format('ALTER TABLE IF EXISTS pemhistory.%I RENAME TO %I', old_internal_name, internal_name);
                END IF;

                -- Update the chart_func table 'pem.chart_func'
                -- START
                OPEN t_sql_curs FOR EXECUTE format('SELECT * FROM pem.chart_func WHERE %L = ANY(dep_probes)', old_internal_name);
                LOOP
                    FETCH NEXT FROM t_sql_curs INTO t_rec;
                    EXIT WHEN NOT FOUND;
                    RAISE NOTICE '% %', 'chart_func found', t_rec.id;
                    -- Update the chart_func probe dependency with new name
                    EXECUTE format('SELECT array_replace(dep_probes, %L, %L) FROM pem.chart_func WHERE id = %L', old_internal_name, internal_name, t_rec.id);
                END LOOP;
                -- END
                CLOSE t_sql_curs;

                -- Update the chart_metric table 'pem.chart_metric'
                -- START
                OPEN t_sql_curs FOR EXECUTE format('SELECT * FROM pem.chart_metric WHERE tbl = %L', old_internal_name);
                LOOP
                    FETCH NEXT FROM t_sql_curs INTO t_rec;
                    EXIT WHEN NOT FOUND;
                    RAISE NOTICE '% %', 'chart_metric found', t_rec.cid;
                    -- Update the chart_func probe dependency with new name
                    EXECUTE format('UPDATE pem.chart_metric SET tbl = %L WHERE tbl = %L AND cid = %L', internal_name, old_internal_name, t_rec.cid);
                END LOOP;
                -- END
                CLOSE t_sql_curs;

                -- Update the data_chart table 'pem.data_chart'
                -- START
                OPEN t_sql_curs FOR EXECUTE format('SELECT * FROM pem.data_chart WHERE tbl = %L', old_internal_name);
                LOOP
                    FETCH NEXT FROM t_sql_curs INTO t_rec;
                    EXIT WHEN NOT FOUND;
                    RAISE NOTICE '% %', 'data_chart found', t_rec.cid;
                    -- Update the chart_func probe dependency with new name
                    EXECUTE format('UPDATE pem.data_chart SET tbl = %L WHERE tbl = %L AND cid = %L', internal_name, old_internal_name, t_rec.cid);
                END LOOP;
                -- END
                CLOSE t_sql_curs;

                -- Update the alert_template table 'pem.alert_template'
                -- Here we need to update dependency probe list, sql & info_sql columns
                -- START
                OPEN t_sql_curs FOR EXECUTE format('SELECT * FROM pem.alert_template WHERE %L = ANY(probe_dependency_list)', old_internal_name);
                LOOP
                    FETCH NEXT FROM t_sql_curs INTO t_rec;
                    EXIT WHEN NOT FOUND;
                    RAISE NOTICE '% %', 'alert_template found', t_rec.id;

                    -- Update the probe dependency with new name
                    EXECUTE format('SELECT array_replace(probe_dependency_list, %L, %L) FROM pem.alert_template WHERE id = %L', old_internal_name, internal_name, t_rec.id);
                    -- Update the sql & info_sql queries in they are using old probe internal name
                    EXECUTE format('UPDATE pem.alert_template SET sql = replace(sql, %L, %L) WHERE id = %L', old_internal_name, internal_name, t_rec.id);
                    EXECUTE format('UPDATE pem.alert_template SET info_sql = replace(info_sql, %L, %L) WHERE id = %L', old_internal_name, internal_name, t_rec.id);
                END LOOP;
                -- END
                CLOSE t_sql_curs;

	        END IF;

        END LOOP;
        -- END MAIN
        CLOSE probe_sql_curs;
    EXCEPTION
        WHEN OTHERS THEN
            error_msg := 'Error while updating probe internal name for import export functionality SQL: ' || SQLERRM;
            RAISE LOG '%', error_msg; -- raise the error in DB server log file
    END;
END;
$$ LANGUAGE plpgsql;


-- Update existing alert template table reference id column so that we can identify unique rows while exporting/importing
DO $$
DECLARE
    uuid                text;
    internal_name       text;
    old_internal_name   text;
	error_msg           text;
	alert_sql           text;
	sql_curs            REFCURSOR;
    rec                 RECORD;
BEGIN
    -- Fetch PEM system id
    EXECUTE 'SELECT pem.system_uid();' INTO uuid;
    -- SQL to fetch all the custom probes
    alert_sql := E'SELECT * FROM pem.alert_template WHERE is_system_template = false';
    BEGIN
        OPEN sql_curs FOR EXECUTE alert_sql;
        -- START MAIN
        LOOP
            FETCH NEXT FROM sql_curs INTO rec;
            EXIT WHEN NOT FOUND;
            -- New format for custom alert's reference_id will be template_<pem_id>_<id>
            old_internal_name := rec.reference_id;
            internal_name := 'template_' || TRIM(uuid) || '_' || rec.id::text;
            RAISE NOTICE 'Renaming reference_id % -> %', old_internal_name, internal_name;
            -- Update the probe table 'pem.probe'
            EXECUTE format('UPDATE pem.alert_template SET reference_id = %L WHERE id = %L', internal_name, rec.id);
        END LOOP;
        -- END MAIN
        CLOSE sql_curs;
    EXCEPTION
        WHEN OTHERS THEN
            error_msg := 'Error while updating alert template reference_id for import export functionality SQL: ' || SQLERRM;
            RAISE LOG '%', error_msg; -- raise the error in DB server log file
    END;
END;
$$ LANGUAGE plpgsql;

-- Also allow us to insert reference id while creating the alert when importing
DROP FUNCTION IF EXISTS pem.create_alert_template(
    text, text, text, integer, text[], pem.alert_param_type[], text[], text, text[], integer, pem.server_type, integer, integer, boolean, text, boolean, text, numeric[]);
CREATE OR REPLACE FUNCTION pem.create_alert_template(
									name				text,
									description			text,
									sql				text,
									object_type			integer,
									param_names			text[],
									param_types			pem.alert_param_type[],
									param_units			text[],
									threshold_unit			text,
									probe_dependency_list		text[] DEFAULT '{}',
									snmp_oid			integer DEFAULT 0,
									applicable_on_server            pem.server_type DEFAULT 'ALL',
									default_check_frequency		integer DEFAULT 1,
									default_history_retention	integer DEFAULT 30,
									is_system_template  boolean	DEFAULT true,
									info_sql  text DEFAULT NULL,
									is_auto_create  boolean DEFAULT false,
									operator  text DEFAULT '>',
									thresholds  numeric[] DEFAULT NULL,
									reference_id    text DEFAULT NULL
									)
RETURNS VOID AS $$
	/*
	 * If we ever change to pl/pgsql, we might want to validate input and RAISE
	 * exceptions here.
	 *
	 * If this INSERT fails the user will see the ERROR with this function's
	 * name in context, hence it doesn't seem any worse than validating params
	 * and RAISE'ing errors, except that by using RAISE we can provide friendly
	 * hints.
	 */
	INSERT INTO pem.alert_template (display_name, description, sql, object_type,
									param_names, param_types, param_units,
									threshold_unit, probe_dependency_list, snmp_oid, applicable_on_server,
									default_check_frequency, default_history_retention, is_system_template,
									info_sql, is_auto_create, operator, thresholds, reference_id)
	VALUES($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, $14, $15, $16, $17, $18, $19);
$$ LANGUAGE SQL;



-- Updating the logic for user defined alert template's reference_id column
-- Function to create new the reference-id
CREATE OR REPLACE FUNCTION pem.update_alert_template_reference_id()
RETURNS trigger AS $$
DECLARE
    uuid text;
BEGIN
	IF NEW.is_system_template THEN
		NEW.reference_id := NEW.object_type || '|' || NEW.display_name;
	ELSE
        -- If old reference id exist then it may be a case where this template was imported
        -- so we will update it only when it's new and empty
        IF NEW.reference_id IS NULL OR TRIM(NEW.reference_id) = '' THEN
            EXECUTE 'SELECT pem.system_uid();' INTO uuid;
            NEW.reference_id := 'template_' || TRIM(uuid) || '_' || NEW.id::text;
        END IF;
	END IF;
	RETURN NEW;
END
$$ LANGUAGE plpgsql;


-- Fixes: PEM-4178
-- Issue: After re-registration the new ids were not getting updated in the pem.probe_schedule table casuing
-- issue in running probes
CREATE OR REPLACE FUNCTION pem.lock_agent_probe_schedule_table(
	_agent_id integer, _probe_id integer, _parameter_value_list text[]
) RETURNS boolean AS $BODY$
DECLARE
    _current_agent_id integer;
BEGIN
    -- Find out if this record already exists
    SELECT agent_id INTO _current_agent_id FROM pem.probe_schedule WHERE probe_id=$2 AND parameter_value_list = $3;

    -- If not exists insert it
    IF NOT FOUND THEN
        INSERT INTO pem.probe_schedule(probe_id, parameter_value_list, agent_id) VALUES ($2, $3, _agent_id);
    ELSE
        IF _current_agent_id IS NULL OR _current_agent_id != _agent_id THEN
            -- Update the probe_schedule table and lock by the current process
            UPDATE pem.probe_schedule SET current_backend_pid=NULL, agent_id=_agent_id WHERE probe_id=$2 AND parameter_value_list=$3;
        ELSE
            -- We can not lock a probe for which current_backend_pid is not NULL (It means - it is already been locked.)
            RETURN false;
        END IF;
    END IF;
    RETURN true;
END
$BODY$ LANGUAGE plpgsql;

DO $FUNC$
BEGIN
IF NOT EXISTS (SELECT 1
    FROM pg_attribute
    WHERE attrelid = (SELECT oid FROM pg_class WHERE relname = 'agent_server_binding' and relnamespace = (SELECT oid FROM pg_namespace WHERE nspname = 'pem'))
    AND attname = 'exclude_databases') THEN
    ALTER TABLE pem.agent_server_binding ADD COLUMN exclude_databases text[] DEFAULT '{}';
END IF;
END
$FUNC$ LANGUAGE 'plpgsql';

-- This view shows every possible combination of (1) a probe, and (2) a known
-- monitoring target to which that probe could be applied.
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
	AND oc.database_name NOT IN (SELECT UNNEST(b.exclude_databases));

END TRANSACTION;
