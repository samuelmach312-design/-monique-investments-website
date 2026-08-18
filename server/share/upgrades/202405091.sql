/***************************************************************************
 *
 * Postgres Enterprise Manager
 *
 * Copyright (C) 2010 - 2025, EnterpriseDB Corporation. All rights reserved.
 *
 ***************************************************************************/

-- NOTE: This sql file is responsible for PEM 9.6.0 schema upgrade.

BEGIN TRANSACTION;

    CREATE OR REPLACE FUNCTION pem.schema_version() RETURNS integer AS
        'SELECT 202405091::integer;'
    LANGUAGE 'sql' IMMUTABLE;
    COMMENT ON FUNCTION pem.schema_version() IS
        'Returns the version number of the PEM schema';


    -- Default character limit for job error notification
    INSERT INTO pem.config (param, value, unit, datatype)
    VALUES ('job_notification_error_limit', '1000', 'characters', 'integer')
    ON CONFLICT (param) DO NOTHING;

    -- updating the job step email template to accomodate error message
    UPDATE pem.email_template
    SET mail_message = array_to_string(ARRAY[
            '=== #%id% - %name% (%status%)',
            'Step Kind: %kind%',
            'Enabled? %enabled%',
            'Error:',
            '%error%'
            '',
            'Description:',
            '%description%',
            '',
            'Start time: %start_time%',
            'Duration: %duration%',
            'Result: %result%'
        ], E'\n')
    WHERE display_name = 'Job Step';

    UPDATE pem.email_template
    SET mail_message = (SELECT mail_message || array_to_string(ARRAY[
        '',
        'Server ID# %server_id%',
        'Server: %server_desc% (%server_host%:%server_port%)',
        'Database: %database%',
        'Server status: %server_active%'
    ], E'\n') FROM pem.email_template WHERE display_name = 'Job Step') 
    WHERE display_name = 'Job Step (Database Server)';

    -- Adding error message in job email template
    CREATE OR REPLACE FUNCTION pem.substitute_jobstep_info(
        input_str TEXT, info json
    )
    RETURNS TEXT AS
    $$
    DECLARE
        result TEXT;
        char_limit INTEGER := 1000;
    BEGIN
        -- default char limit
        SELECT conf.value INTO char_limit FROM pem.config conf WHERE param = 'job_notification_error_limit';
        WITH newlines AS (
            SELECT lines[rn] AS line, rn
            FROM (
                SELECT lines, generate_subscripts(lines, 1) AS rn
                FROM (
                    SELECT
                    regexp_split_to_array(input_str, E'\n') AS lines
                ) regexp_tbl
            ) each_line
        ),
        keys AS (
            SELECT rn, line, regexp_matches(
                line, '(?:(.*?)(%[a-zA-Z_]+%)(.*)){1}', 'g'
            ) AS tokens
            FROM newlines
        ),
        non_keys AS (
            SELECT rn, line, tokens FROM (
                SELECT rn, line, regexp_split_to_array(
                    line , '(?:(.*?)(%[a-zA-Z_]+%)(.*)){1}'
                ) AS tokens
                FROM newlines
            ) not_matched
            WHERE array_length(tokens, 1) = 1
        ),
        rest AS (
            SELECT rn, line, replace(line, pattern_line, '') AS rest
            FROM (
                SELECT
                    rn, line,
                    array_to_string(array_agg(tokens), '', '') AS pattern_line
                FROM (
                    SELECT rn, line, array_to_string(tokens, '', '') AS tokens
                    FROM keys
                ) a GROUP BY rn, line
            ) rest_lines
        )
        SELECT array_to_string(array_agg(res.line ORDER BY res.rn), E'\n', '')
        INTO result
        FROM (
            SELECT k.rn, k.line || COALESCE(r.rest, '') AS line
            FROM (
                SELECT
                    k.rn, array_to_string(array_agg(k.res ORDER BY k.rn), '', '') AS line
                FROM (
                    SELECT
                        rn,
                        COALESCE(tokens[1], '') ||
                        CASE tokens[2]
                        WHEN '%id%' THEN info->>'jstid'::text
                        WHEN E'%error%' THEN 
                            CASE info->>'jslstatus'
                            WHEN 'f' THEN LEFT(COALESCE(info ->> 'jsloutput', ''), char_limit)
                            END
                        WHEN E'%description%' THEN info->>'jstdesc'
                        WHEN E'%name%' THEN info->>'jstname'
                        WHEN E'%result%' THEN COALESCE(info->>'jslresult'::text, '')
                        WHEN E'%start_time%' THEN COALESCE(
                            (info->>'jslstart')::timestamptz::text, ''
                        )
                        WHEN E'%duration%' THEN COALESCE(
                            (info->>'jslduration')::interval::text, ''
                        )
                        WHEN E'%enabled%' THEN
                            CASE
                            WHEN (info->>'jstenabled')::boolean IS TRUE THEN 'Yes'
                            ELSE 'False'
                            END
                        WHEN E'%kind%' THEN
                            CASE info->>'jstkind'
                            WHEN 'b' THEN 'Batch/Shell Script'
                            WHEN 's' THEN 'SQL Query'
                            WHEN 'i' THEN 'Internal'
                            ELSE 'Unknown'
                            END
                        WHEN E'%status%' THEN
                            CASE info->>'jslstatus'
                            WHEN 's' THEN 'SUCCESS'
                            WHEN 'f' THEN 'FAILED'
                            WHEN 'i' THEN 'IGNORED'
                            WHEN 'd' THEN 'INTERRUPTED'
                            WHEN 'r' THEN 'RUNNING'
                            ELSE
                                CASE (info->>'jstenabled')::boolean
                                WHEN FALSE THEN 'INACTIVE'
                                ELSE 'NEVER RAN'
                                END
                            END
                        WHEN E'%server_id%' THEN COALESCE(info->>'server_id'::text, '')
                        WHEN E'%database%' THEN COALESCE(info->>'database_name'::text, '')
                        WHEN E'%server_desc%' THEN COALESCE(info->>'server_desc', '')
                        WHEN E'%server_host%' THEN
                            CASE
                            WHEN (info->>'server_hostaddr')::text IS NOT NULL OR
                                info->>'server_hostaddr' != ''
                                THEN info->>'server_hostaddr'
                            ELSE COALESCE((info->>'server_host')::text, '')
                            END
                        WHEN E'%server_port%' THEN COALESCE(info->>'server_port'::text, '')
                        WHEN E'%server_active%' THEN
                            CASE (info->>'server_active')::boolean
                            WHEN TRUE THEN 'Active'
                            WHEN FALSE THEN 'Inactive'
                            ELSE ''
                            END
                        ELSE COALESCE(tokens[2], '')
                        END || COALESCE(tokens[3], '') AS res
                    FROM keys
                ) AS k
                GROUP BY k.rn
            ) k
            LEFT JOIN rest r ON (k.rn = r.rn)
            UNION
            SELECT rn, line FROM non_keys
        ) res;

        RETURN result;
    END;
    $$ LANGUAGE 'plpgsql';

    -- PEM-5077: Added detailed information for alert "Table size in server"
    UPDATE pem.alert_template SET display_name = 'Total table size in server', description = 'The total size of tables in server, in MB.',
    info_sql = $sql$SELECT table_name AS "Table name", database_name AS "Database name",
    schema_name AS "Schema name", total_table_size_mb AS "Total table size(MB)"
    FROM pemdata.table_size
    WHERE	server_id = ${server_id} ORDER BY total_table_size_mb DESC limit 10;$sql$
    WHERE is_system_template AND display_name = 'Table size in server' AND object_type = 200;

    -- Added detailed information for alert "Table size in database"
    UPDATE pem.alert_template SET display_name = 'Total table size in database', description = 'The total size of tables in database, in MB.',
    info_sql = $sql$SELECT table_name AS "Table name", database_name AS "Database name",
    schema_name AS "Schema name", total_table_size_mb AS "Total table size(MB)"
    FROM pemdata.table_size
    WHERE	server_id = ${server_id}
    AND		database_name = '${database_name}'
    ORDER BY total_table_size_mb DESC limit 10;$sql$
    WHERE is_system_template AND display_name = 'Table size in database' AND object_type = 300;

    -- Added detailed information for alert "Table size in schema"
    UPDATE pem.alert_template SET display_name = 'Total table size in schema', description = 'The total size of tables in schema, in MB.',
    info_sql = $sql$SELECT table_name AS "Table name", database_name AS "Database name",
    schema_name AS "Schema name", total_table_size_mb AS "Total table size(MB)"
    FROM pemdata.table_size
    WHERE	server_id = ${server_id}
    AND		database_name = '${database_name}'
    AND		schema_name = '${schema_name}'
    ORDER BY total_table_size_mb DESC limit 10;$sql$
    WHERE is_system_template AND display_name = 'Table size in schema' AND object_type = 400;

    CREATE OR REPLACE FUNCTION pem.create_default_server_alerts(server_id integer, server_version_id integer DEFAULT 0)
    RETURNS VOID AS $$
    DECLARE
        temp_rec record;
        sql text;
        enabled boolean;
    BEGIN
        IF server_version_id = 0 THEN
            sql = 'SELECT id, display_name, default_check_frequency, default_history_retention, operator, thresholds FROM pem.alert_template WHERE object_type = 200 and is_auto_create and applicable_on_server = ''ALL'' ORDER BY id';
        ELSIF (server_version_id > 10900 AND server_version_id < 20000) THEN
            sql = 'SELECT id, display_name, default_check_frequency, default_history_retention, operator, thresholds FROM pem.alert_template WHERE object_type = 200 and is_auto_create and applicable_on_server IN (''ALL'', ''POSTGRES_SERVER'') ORDER BY id';
        ELSIF (server_version_id > 20000) THEN
            sql = 'SELECT id, display_name, default_check_frequency, default_history_retention, operator, thresholds FROM pem.alert_template WHERE object_type = 200 and is_auto_create and applicable_on_server IN (''ALL'', ''ADVANCED_SERVER'') ORDER BY id';
        END IF;
        FOR temp_rec IN EXECUTE sql
        LOOP

            IF temp_rec.display_name in ('Database size in server','Total table size in server','Number of WAL archives pending') THEN
                enabled = false;
              else
                enabled = true;
            END IF;

            IF NOT pem.check_alert_exist(temp_rec.display_name, 0, $1, NULL, NULL, NULL, NULL, 200) THEN
                PERFORM pem.create_alert(temp_rec.display_name, temp_rec.id,
                0, $1, NULL, NULL, NULL, NULL, '{}', temp_rec.operator, temp_rec.thresholds,temp_rec.default_check_frequency, temp_rec.default_history_retention, enabled, true);
            END IF;
        END LOOP;
    END;
    $$ LANGUAGE plpgsql;

    -- PEM-5109-- fixed team role feature for agents
    CREATE OR REPLACE VIEW pem.avail_agents AS
        SELECT
            a.id AS id,
            a.agent_capability_list AS agent_capability_list,
            COALESCE(ao.description, a.description) AS description,
            a.active AS active,
            a.heartbeat_interval AS heartbeat_interval,
            a.alert_blackout AS alert_blackout,
            a.version AS version,
            a.platform AS platform,
            a.owner AS owner,
            a.team AS team,
            a.owner::regrole::name AS agent_owner,
            COALESCE(ao.group_id, a.group_id, 0) AS group_id
        FROM pem.agent a
            LEFT JOIN pem.agent_options ao ON (a.id = ao.agent_id AND pem_user = current_user)
        WHERE
            -- Only active agents
            a.active AND (
                pem.can_access_team(a.owner, a.team) OR
                pg_catalog.pg_has_role('pem_agent', 'member'::text) OR
                id in (
                    SELECT DISTINCT(agent_id)
                    FROM pem.agent_server_binding
                    WHERE server_id in (SELECT s.id FROM pem.server s WHERE pem.can_access_team(s.owner, s.team))
                )
            );
            
    -- PEM-5113
    -- Transaction ID Exhaustion (Wraparound) update the probe_code
    UPDATE pem.probe
        SET probe_code =
        $sql$
        SELECT datname, 
            age(datfrozenxid) AS oldest_current_xid, 
            ROUND((age(datfrozenxid)::int / 2147483648::float) * 100) AS percent_towards_wraparound, 
            ROUND((age(datfrozenxid) / (SELECT setting::int FROM pg_catalog.pg_settings WHERE name = 'autovacuum_freeze_max_age')) * 100) AS percent_towards_emergency_autovac 
        FROM pg_catalog.pg_database;
        $sql$
    WHERE internal_name ='txid_exhaustion_wraparound';

    DO $DO$
    BEGIN
        IF NOT EXISTS (SELECT id FROM pem.probe where internal_name = 'mxid_exhaustion_wraparound') THEN
            --
            -- New probe Multixact ID Exhaustion (Wraparound)
            --
            INSERT INTO pem.probe
                (display_name, internal_name, collection_method, target_type_id,
                agent_capability, enabled_by_default, force_enabled,
                default_execution_frequency, default_lifetime, any_server_version, probe_code)
            VALUES
                ('Multixact ID Exhaustion (Wraparound)', 'mxid_exhaustion_wraparound', 's',
                200, NULL, true, false, 300, 180, true,
                $sql$
                SELECT datname, 
                    mxid_age(datminmxid) AS oldest_current_mxid, 
                    round((mxid_age(datminmxid)::int/2147483648)*100) AS percent_towards_wraparound, 
                    round((mxid_age(datminmxid)/(SELECT setting::int FROM pg_catalog.pg_settings WHERE name = 'autovacuum_multixact_freeze_max_age'))*100) AS percent_towards_emergency_autovac 
                FROM pg_catalog.pg_database;
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
                    ('oldest_current_mxid', 'Oldest current MXID', 2, 'm', 'bigint', '', false, false, false, false),
                    ('percent_towards_wraparound', 'Percent towards wraparound', 3, 'm', 'integer', '', false, false, false, false),
                    ('percent_towards_emergency_autovac', 'Percent towards autovacuum', 4, 'm', 'integer', '', false, false, false, false)
                ) v(internal_name, display_name, display_position, classification,
                    sql_data_type, unit_of_value, calculate_pit, discard_history, pit_by_default, is_graphable);
        END IF;

        -- Create tables required by probe
        PERFORM pem.create_data_and_history_tables();

        IF NOT EXISTS (SELECT id FROM pem.alert_template where display_name = 'Multixact ID Exhaustion (Wraparound)') THEN
            -- Create new alert template.
            PERFORM pem.create_alert_template(
                'Multixact ID Exhaustion (Wraparound)',
                'Percentage towards Multixact ID Exhaustion (Wraparound)',
                $sql$
            SELECT  max(percent_towards_wraparound) AS percent_towards_wraparound
            FROM pemdata.mxid_exhaustion_wraparound AS mxew
            WHERE mxew.server_id = ${server_id}
            $sql$,
                200, NULL, NULL, NULL, '%','{mxid_exhaustion_wraparound}', (SELECT CASE WHEN MAX(snmp_oid) > 0 THEN MAX(snmp_oid) + 1 ELSE 1 END FROM pem.alert_template WHERE object_type = 200),
                'ALL', 1, 30, true,
                $SQL$
            SELECT  MAX(datname) AS "Database name",
                    MAX(oldest_current_mxid) AS "Oldest current MXID",
                    MAX(percent_towards_wraparound) AS "Percent towards wraparound",
                    MAX(percent_towards_emergency_autovac) AS "Percent towards emergency autovacuum"
            FROM pemdata.mxid_exhaustion_wraparound AS mxew
            WHERE mxew.server_id = ${server_id}
                $SQL$, true, '>', '{75, 85, 95}');
        END IF;
    END;
    $DO$ LANGUAGE 'plpgsql';

    -- Added a probe for collecting the pg_replication_slots
    DO $DO$
    BEGIN
        IF NOT EXISTS (SELECT id FROM pem.probe where internal_name = 'replication_slots') THEN
            INSERT INTO pem.probe
            (display_name, internal_name, collection_method, target_type_id,
             agent_capability, enabled_by_default, force_enabled,
             default_execution_frequency, default_lifetime, any_server_version, probe_code)
            VALUES
                ('Replication Slots', 'replication_slots', 's',
                 200, NULL, true, false, 300, 180, false,
                'SELECT slot_name, plugin, slot_type, datoid, database, temporary,
                active, active_pid, xmin as xmin_id, catalog_xmin, restart_lsn,
                confirmed_flush_lsn, NULL::text as wal_status,
                NULL::bigint as safe_wal_size, NULL::boolean as two_phase,
                NULL::boolean as conflicting
                FROM pg_catalog.pg_replication_slots');

            INSERT INTO pem.probe_server_version
                (probe_id, server_version_id, probe_code)
            SELECT
                (SELECT max(id) FROM pem.probe), v.version, NULL
                FROM (
                VALUES
                (11100), (11200), (21100), (21200)
            ) v(version);

            INSERT INTO pem.probe_server_version
                (probe_id, server_version_id, probe_code)
            SELECT
                (SELECT max(id) FROM pem.probe), v.version,
                'SELECT slot_name, plugin, slot_type, datoid, database, temporary,
                active, active_pid, xmin as xmin_id, catalog_xmin, restart_lsn,
                confirmed_flush_lsn, wal_status, safe_wal_size,
                NULL::boolean as two_phase, NULL::boolean as conflicting
                FROM pg_catalog.pg_replication_slots'
                FROM (
                VALUES
                (11300), (21300)
            ) v(version);

            INSERT INTO pem.probe_server_version
                (probe_id, server_version_id, probe_code)
            SELECT
                (SELECT max(id) FROM pem.probe), v.version,
                'SELECT slot_name, plugin, slot_type, datoid, database, temporary,
                active, active_pid, xmin as xmin_id, catalog_xmin, restart_lsn,
                confirmed_flush_lsn, wal_status, safe_wal_size, two_phase,
                NULL::boolean as conflicting
                FROM pg_catalog.pg_replication_slots'
                FROM (
                VALUES
                (11400), (11500), (21400), (21500)
            ) v(version);

            INSERT INTO pem.probe_server_version
                (probe_id, server_version_id, probe_code)
            SELECT
                (SELECT max(id) FROM pem.probe), v.version,
                'SELECT slot_name, plugin, slot_type, datoid, database, temporary,
                active, active_pid, xmin as xmin_id, catalog_xmin, restart_lsn,
                confirmed_flush_lsn, wal_status, safe_wal_size, two_phase,
                conflicting FROM pg_catalog.pg_replication_slots'
                FROM (
                VALUES
                (11600), (21600)
            ) v(version);
            
            INSERT INTO pem.probe_column
                (probe_id, internal_name, display_name, display_position, classification,
                sql_data_type, unit_of_value, calculate_pit, discard_history, pit_by_default, is_graphable)
            SELECT
                (SELECT max(id) FROM pem.probe),
                v.internal_name, v.display_name, v.display_position, v.classification,
                v.sql_data_type, v.unit_of_value, v.calculate_pit, v.discard_history, v.pit_by_default, v.is_graphable
            FROM
                (VALUES
                    ('slot_name', 'Slot Name', 1, 'k', 'text', '', false, false, false, false),
                    ('plugin', 'Plugin', 2, 'm', 'text', '', false, false, false, false),
                    ('slot_type', 'Slot Type', 3, 'm', 'text', '', false, false, false, false),
                    ('datoid', 'Database OID', 4, 'm', 'bigint', '', false, false, false, false),
                    ('database', 'Database Name', 5, 'm', 'text', '', false, false, false, false),
                    ('temporary', 'Temporary?', 6, 'm', 'boolean', '', false, false, false, false),
                    ('active', 'Active?', 7, 'm', 'boolean', '', false, false, false, false),
                    ('active_pid', 'Active PID', 8, 'm', 'bigint', '', false, false, false, false),
                    ('xmin_id', 'Oldest Transaction ID', 9, 'm', 'bigint', '', false, false, false, false),
                    ('catalog_xmin', 'Oldest Catalog Transaction', 10, 'm', 'bigint', '', false, false, false, false),
                    ('restart_lsn', 'Oldest WAL LSN', 11, 'm', 'text', '', false, false, false, false),
                    ('confirmed_flush_lsn', 'Confirmed LSN', 12, 'm', 'text', '', false, false, false, false),
                    ('wal_status', 'WAL Status', 13, 'm', 'text', '', false, false, false, false),
                    ('safe_wal_size', 'Safe WAL Size', 14, 'm', 'bigint', '', false, false, false, false),
                    ('two_phase', 'Two Phase?', 15, 'm', 'boolean', '', false, false, false, false),
                    ('conflicting', 'Conflicting?', 16, 'm', 'boolean', '', false, false, false, false)
                ) v(internal_name, display_name, display_position, classification,
                    sql_data_type, unit_of_value, calculate_pit, discard_history, pit_by_default, is_graphable);

            PERFORM pem.create_data_and_history_tables();
        END IF;
    END;
    $DO$ LANGUAGE 'plpgsql';

    -- Added an alert for inactive replication slot
    DO $DO$
    BEGIN
        IF NOT EXISTS (SELECT id FROM pem.alert_template where display_name = 'Inactive replication slots' AND is_system_template) THEN
            PERFORM pem.create_alert_template(
            'Inactive replication slots',
            'Slots which are inactive for a particular server.',
            $sql$
            SELECT
                count(*),
                CASE WHEN count(*) = 0 THEN 'Active' ELSE 'Inactive' END display_value
            FROM
                pemdata.replication_slots
            WHERE
                server_id = ${server_id} AND
                active = false AND
                temporary = false
            $sql$,
            200, NULL, NULL, NULL, 'STATE', '{replication_slots}', (SELECT CASE WHEN MAX(snmp_oid) > 0 THEN MAX(snmp_oid) + 1 ELSE 1 END FROM pem.alert_template WHERE object_type = 200),
            'ALL', 1, 30, true, $SQL$
            SELECT
                ps.description AS "Server description",rs.server_id AS "Server ID",
                rs.slot_name as "Slot Name", rs.slot_type as "Slot Type",
                rs.active as "Is Active?", rs.temporary as "Is Temporary?"
            FROM
                pem.server ps LEFT OUTER JOIN pemdata.replication_slots rs ON (ps.id = rs.server_id)
            WHERE
                rs.server_id = ${server_id} AND
                rs.active = false AND
                rs.temporary = false$SQL$,true, '>', '{0.1, 0.2, 0.3}');
        END IF;
    END;
    $DO$ LANGUAGE 'plpgsql';

    DO $DO$
    BEGIN
        IF NOT EXISTS (SELECT id FROM pem.alert_template where display_name = 'Conflicting replication slots' AND is_system_template) THEN
            PERFORM pem.create_alert_template(
            'Conflicting replication slots',
            'Slots which are conflicting for a particular server.',
            $sql$
            SELECT
                count(*),
                CASE WHEN count(*) = 0 THEN 'Not Conflicting' ELSE 'Conflicting' END display_value
            FROM
                pemdata.replication_slots
            WHERE
                server_id = ${server_id} AND
                conflicting = true
            $sql$,
            200, NULL, NULL, NULL, 'STATE', '{replication_slots}', (SELECT CASE WHEN MAX(snmp_oid) > 0 THEN MAX(snmp_oid) + 1 ELSE 1 END FROM pem.alert_template WHERE object_type = 200),
            'ALL', 1, 30, true, $SQL$
            SELECT
                ps.description AS "Server description",rs.server_id AS "Server ID",
                rs.slot_name as "Slot Name", rs.slot_type as "Slot Type",
                rs.active as "Is Active?", rs.conflicting as "Is Conflicting?"
            FROM
                pem.server ps LEFT OUTER JOIN pemdata.replication_slots rs ON (ps.id = rs.server_id)
            WHERE
                rs.server_id = ${server_id} AND
                conflicting = true$SQL$,true, '>', '{0.1, 0.2, 0.3}');
        END IF;
    END;
    $DO$ LANGUAGE 'plpgsql';

END TRANSACTION;

