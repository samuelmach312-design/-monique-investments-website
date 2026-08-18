/***************************************************************************
 *
 * Postgres Enterprise Manager
 *
 * Copyright (C) 2010 - 2025, EnterpriseDB Corporation. All rights reserved.
 *
 ***************************************************************************/

-- NOTE: This sql file is responsible for PEM 10.3.0 schema upgrade.

BEGIN TRANSACTION;
    CREATE
    OR REPLACE FUNCTION pem.schema_version()
    RETURNS integer AS 'SELECT 202511251::integer;' LANGUAGE 'sql' IMMUTABLE;
    COMMENT ON FUNCTION pem.schema_version()
    IS 'Returns the version number of the PEM schema';


-- PEM-5656 Added support for monitoring PGE/PG/EPAS 18

    DO $DO$
        BEGIN
            -- Check if the server version already exist for PG 18
            IF NOT EXISTS (SELECT id FROM pem.server_version WHERE id = 11800) THEN
                INSERT INTO pem.server_version VALUES (11800, 'PostgreSQL 18');
            END IF;

            -- Check if the server version already exist for EPAS 18
            IF NOT EXISTS (SELECT id FROM pem.server_version WHERE id = 21800) THEN
                INSERT INTO pem.server_version VALUES (21800, 'Advanced Server 18');
            END IF;

            -- Check if the probe server version already exist for PG 18
            IF NOT EXISTS (SELECT server_version_id FROM pem.probe_server_version WHERE server_version_id = 11800) THEN
                INSERT INTO pem.probe_server_version
                    (probe_id, server_version_id, probe_code)
                    SELECT psv.probe_id, 11800 AS server_version_id, psv.probe_code FROM (
                        SELECT probe_id, probe_code FROM pem.probe_server_version
                        WHERE server_version_id = 11700
                    ) AS psv
                    JOIN pem.probe p ON (psv.probe_id = p.id) AND p.internal_name = ANY(
                        ARRAY[
                            'oc_database', 'oc_table', 'oc_schema', 'oc_function', 'oc_extension', 'oc_views',
                            'database_statistics', 'table_statistics', 'table_frozenxid',
                            'table_size', 'function_statistics', 'mview_bloat',
                            'mview_frozenxid', 'mview_size', 'blocked_session_info',
                            'session_info', 'user_info', 'lock_info',
                            'background_writer_statistics', 'patroni_cluster_status', 'patroni_node_status',
                            'number_of_wal_files', 'wal_archive_status',
                            'streaming_replication', 'streaming_replication_db_conflicts',
                            'streaming_replication_lag_time', 'xdb_smr_mmr_replication',
                            'efm_cluster_node_status', 'efm_cluster_info', 'replication_slots'
                            ]::text[]
                    );
            END IF;

            -- Check if the probe server version already exist for EPAS 18
            IF NOT EXISTS (SELECT server_version_id FROM pem.probe_server_version WHERE server_version_id = 21800) THEN
                INSERT INTO pem.probe_server_version
                    (probe_id, server_version_id, probe_code)
                    SELECT psv.probe_id, 21800 AS server_version_id, psv.probe_code FROM (
                        SELECT probe_id, probe_code FROM pem.probe_server_version
                        WHERE server_version_id = 21700
                    ) AS psv
                    JOIN pem.probe p ON (psv.probe_id = p.id) AND p.internal_name = ANY(
                        ARRAY[
                            'oc_database', 'oc_table', 'oc_schema','oc_function', 'oc_extension', 'database_statistics',
                            'table_statistics', 'table_frozenxid', 'function_statistics', 'table_size',
                            'number_of_wal_files', 'session_info', 
                            'background_writer_statistics', 'patroni_cluster_status', 'patroni_node_status',
                            'user_info', 'lock_info', 'audit_configuration',
                            'streaming_replication', 'streaming_replication_db_conflicts',
                            'xdb_smr_mmr_replication', 'oc_views', 'mview_bloat', 'mview_frozenxid',
                            'mview_size', 'streaming_replication_lag_time', 'wal_archive_status',
                            'efm_cluster_node_status', 'efm_cluster_info', 'blocked_session_info', 'replication_slots'
                            ]::text[]
                    );
            END IF;
    END;
    $DO$ LANGUAGE 'plpgsql';
    
    -- PEM-5656 Adding support for PGE/PG/EPAS 18
    -- Altering the log_connections column of log_configuration table to type TEXT
    ALTER TABLE pem.log_configuration 
        ALTER COLUMN log_connections TYPE TEXT;

    ALTER TABLE pemdata.log_configuration 
        ALTER COLUMN log_connections TYPE TEXT;

    ALTER TABLE pemhistory.log_configuration 
        ALTER COLUMN log_connections TYPE TEXT;

    Update pem.probe_column set sql_data_type = 'text'
    WHERE internal_name = 'log_connections';

    --PEM-5740: remove column connect_timeout while calling pem.server_options function
    CREATE OR REPLACE FUNCTION pem.change_server_group(
        _old integer, _aid integer, _sid integer, _uid integer
    ) RETURNS integer AS $$
    DECLARE
        v_cnt integer;
        v_user text;
    BEGIN

        SELECT rolname into v_user FROM pg_roles WHERE oid = _uid;

        EXECUTE $SQL$
    WITH update_agent_options AS (
        UPDATE pem.agent_options SET group_id = $2
        WHERE group_id = $1 AND pem_user = $4
        RETURNING 1
    ),
    insert_agent_options AS (
        INSERT INTO pem.agent_options(agent_id, description, group_id, pem_user)
        SELECT id, description, $2, $4 FROM pem.agent a
        WHERE a.group_id = $1 AND NOT a.id = ANY(
            SELECT ao.agent_id FROM pem.agent_options ao WHERE ao.pem_user = $4
        ) RETURNING 1
    ),
    update_server_options AS (
        UPDATE pem.server_options SET server_group_id = $3
        WHERE server_group_id = $1 AND pem_user = $4
        RETURNING 1
    ),
    insert_server_options AS (
        INSERT INTO pem.server_options(
            server_id, server_group_id, pem_user, server_colour, fgcolor,
            database_restriction, store_pwd, restore_env,
            sslcompression, username
        ) SELECT
            so.server_id, $3, $4, so.server_colour, so.fgcolor,
            so.database_restriction, false, so.restore_env,
            sslcompression, username
        FROM pem.server_options so
        LEFT JOIN pem.server s ON (so.server_id = s.id)
        LEFT JOIN pg_roles r ON (s.owner = r.oid)
        WHERE s.group_id = $1 AND r.rolname = so.pem_user AND
            NOT s.id = ANY(
                SELECT c.server_id FROM pem.server_options c
                WHERE c.pem_user = $4
            )
        RETURNING 1
    )
    SELECT sum(g.cnt) FROM (
        SELECT count(*) AS cnt FROM update_agent_options
        UNION ALL
        SELECT count(*) AS cnt FROM insert_agent_options
        UNION ALL
        SELECT count(*) AS cnt FROM update_server_options
        UNION ALL
        SELECT count(*) AS cnt FROM insert_server_options
    ) g$SQL$ USING _old, _aid, _sid, v_user INTO v_cnt;
        RETURN v_cnt;
    END;
    $$ LANGUAGE 'plpgsql';

    -- PEM-5720 Altering the columns of event_history table to type TEXT
    ALTER TABLE pem.event_history
        ALTER COLUMN user_name TYPE TEXT,
        ALTER COLUMN component TYPE TEXT,
        ALTER COLUMN operation TYPE TEXT,
        ALTER COLUMN message TYPE TEXT,
        ALTER COLUMN details TYPE TEXT;

    -- PEM-5394 No need to create agent_<id> user when registing agent with --pem-agent-user specified
    DROP FUNCTION IF EXISTS pem.create_agent (varchar, integer, bool);
    CREATE OR REPLACE FUNCTION pem.create_agent (varchar, integer, bool DEFAULT false, bool DEFAULT false)
    RETURNS integer AS $$
    DECLARE
        agent_id          integer;
        agent_name        varchar;
        sql               varchar;
        agent_description varchar;
        id_exist          boolean;
        role_exist        boolean;
        is_active         boolean := false;
        use_agent_user    boolean;
    BEGIN
        agent_description := $1;
        id_exist := false;
        role_exist := false;
        use_agent_user := $4;

        SELECT true, active INTO id_exist, is_active FROM pem.agent WHERE id = $2;
        SELECT id INTO agent_id FROM pem.agent ORDER BY id DESC LIMIT 1 FOR UPDATE;

        IF id_exist THEN
            IF $3 IS true AND is_active IS true THEN
                RAISE EXCEPTION
                    'An active agent is already present with id (#%). Please use another id.',
                    $2;
            END IF;
            UPDATE pem.agent SET (active, description) = ('t', agent_description) WHERE id = $2;
            agent_id := $2;
        ELSE
            -- Fetch the greatest id again as parallel transaction may already have inserted a new id.
            SELECT id INTO agent_id FROM pem.agent ORDER BY id DESC LIMIT 1;

            IF agent_id IS NULL THEN
                agent_id := 1;
            ELSE
                agent_id := agent_id + 1;
            END IF;

            IF $2 != -1 THEN
                INSERT INTO pem.agent(id, agent_capability_list, description) VALUES ($2, '{}', agent_description) RETURNING id INTO agent_id;
            ELSE
                INSERT INTO pem.agent(id, agent_capability_list, description) VALUES (agent_id, '{}', agent_description) RETURNING id INTO agent_id;
            END IF;

            -- If use_agent_user is true, means to use common user, we do not need to create agent_<id> user
            IF use_agent_user IS false THEN
                agent_name := 'agent' || agent_id;

                SELECT true INTO role_exist FROM pg_catalog.pg_roles WHERE rolname = agent_name;
                IF role_exist THEN
                    RAISE NOTICE 'ROLE % already exist', agent_name;
                ELSE
                    EXECUTE 'CREATE ROLE ' || agent_name  || ' WITH LOGIN';
                END IF;

                sql := 'GRANT pem_agent TO ' || agent_name;
                EXECUTE sql;
            END IF;
        END IF;

        RETURN agent_id;
    END;
    $$ LANGUAGE plpgsql;
    
    -- PEM-4676 Automatically blackout the server which are no longer contactable
    INSERT INTO pem.config (param, value, unit, datatype) VALUES (
	'server_contact_timeout', 48, 'hours', 'integer'
    ) ON CONFLICT (param) DO NOTHING;

    ALTER TABLE IF EXISTS pem.server
    ADD COLUMN IF NOT EXISTS auto_alert_blackout BOOLEAN DEFAULT FALSE;

    ALTER TABLE IF EXISTS pem.agent
    ADD COLUMN IF NOT EXISTS auto_alert_blackout BOOLEAN DEFAULT FALSE;

    -- ==========================================================
    -- Function: pem.create_pem_server_system_tasks_data_cleanup
    -- Description:
    -- Creates the system job to periodically clean up obsolete
    -- database data and probe history.
    -- ==========================================================
    CREATE OR REPLACE FUNCTION pem.create_pem_server_system_tasks_data_cleanup(
    p_agent_id integer,
    p_server_id integer,
    p_database text,
    p_is_leader boolean
)
    RETURNS void AS
    $FUNC$
    DECLARE
        job_id integer;
        probe_rec RECORD;
    BEGIN
        -- JOB: Create database clean up job
        -- STEP: Obsolete database cleanup
        -- SCHEDULE: Database cleanup (runs twice a day)
        SELECT pem.create_or_update_system_job_with_a_step_and_schedule(
            p_agent_id, p_server_id, p_database,
            -- Job name
            'Database cleanup',
            -- Job description
            'This job runs periodically to purge old data from the database.',
            -- Step name
            'Obsolete database cleanup',
            -- Step description
            'This job step runs periodically to purge obsolete data from the database.',
            's',
            'SELECT pem.purge_obsolete_data()',
            p_is_leader, TRUE,
            -- Schedule name
            'Database cleanup',
            -- Schedule description
            'This job schedule runs periodically to purge old data from the database.',
            '{t,f,f,f,f,f,f,f,f,f,f,f,f,f,f,t,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f}',
            '{f,t,f,f,f,f,f,f,f,t,f,f,f,t,f,f,f,t,f,f,f,f,f,f}'
        ) INTO job_id;

        FOR probe_rec IN
            SELECT
                format(
                    $sql$
                        SELECT pem.create_or_update_jobstep(
                            $1::integer, $2::integer, $3::text,
                            'Purge data (%s)'::text,
                            'Purging the history data for the probe (id: %s, name: %s,).'::text,
                            's'::char,
                            'SELECT pem.purge_probe_history(%s::integer)'::text,
                            true::boolean,
                            'i'::char
                        )
                    $sql$,
                    p.display_name,
                    p.id,
                    p.display_name,
                    p.id
                ) AS sql
            FROM pem.probe p WHERE NOT discard_history
        LOOP
            EXECUTE probe_rec.sql USING job_id, p_server_id, p_database;
        END LOOP;
    END
    $FUNC$ LANGUAGE 'plpgsql';

    -- ==========================================================
    -- Function: pem.create_pem_server_system_tasks_update_probes
    -- Description:
    -- Creates a job that updates the probe-object combination
    -- records in PEM.
    -- ==========================================================
    CREATE OR REPLACE FUNCTION pem.create_pem_server_system_tasks_update_probes(
        p_agent_id integer,
        p_server_id integer,
        p_database text,
        p_is_leader boolean
    )
        RETURNS void AS
    $FUNC$
    DECLARE
        job_id integer;
    BEGIN
        -- JOB: Update the probe-object combination
        SELECT pem.create_or_update_system_job_with_a_step_and_schedule(
            p_agent_id, p_server_id, p_database,
            -- Job name
            'Update the probe-objects combination',
            -- Job description
            'This job updates/inserts the record of the probe, parameter_value_list in the ''pem.probe_objects_combo'' table.',
            -- Step name
            'Update the probe-objects combination',
            -- Step description
            'This job step updates the purge-job tasks on demand.',
            's',
            'SELECT pem.create_update_probe_objects_combo()',
            p_is_leader, TRUE
        ) INTO job_id;
        --
        -- Generate the update probe-objects combination job
        -- it will run 10 minutes after installation.
        --
        -- Let agent fetch the information about the server, and host-machine
        -- to determine the actual probes to run, which generates actual
        -- combination.
        UPDATE pem.job SET jobnextrun = now() + interval '10 minutes'
        WHERE jobid = job_id;
    END
    $FUNC$ LANGUAGE 'plpgsql';

    -- ==========================================================
    -- Function: pem.create_pem_server_system_tasks_log_cleanup
    -- Description:
    -- Creates cleanup jobs for various log and spool tables.
    -- ==========================================================
    CREATE OR REPLACE FUNCTION pem.create_pem_server_system_tasks_log_cleanup(
        p_agent_id integer,
        p_server_id integer,
        p_database text,
        p_is_leader boolean
    )
        RETURNS void AS
    $FUNC$
    BEGIN
        -- JOB: Audit log table cleanup
        -- SCHEDULE: Run once a day
        PERFORM pem.create_or_update_system_job_with_a_step_and_schedule(
            p_agent_id, p_server_id, p_database,
            -- Job name
            'Audit log table cleanup',
            -- Job description
            'This job runs periodically to purge old data from the audit log table.',
            -- Step name
            'Audit log table cleanup',
            -- Step description
            'This job step runs periodically to purge old data from the audit log table.',
            's',
            'SELECT pem.purge_audit_log()',
            p_is_leader, TRUE,
            -- Schedule name
            'Audit log table cleanup',
            -- Schedule description
            'This job schedule runs periodically to purge old data from the audit log table.',
            '{t,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f}',
            '{f,t,f,f,f,f,f,f,f,f,f,f,t,f,f,f,f,f,f,f,f,f,f,f}'
        );
        -- JOB: Server log table cleanup
        -- SCHEDULE: Run once a day
        PERFORM pem.create_or_update_system_job_with_a_step_and_schedule(
            p_agent_id, p_server_id, p_database,
            -- Job name
            'Server log table cleanup',
            -- Job description
            'This job runs periodically to purge old data from the server log table.',
            -- Step name
            'Server log table cleanup',
            -- Step description
            'This job step runs periodically to purge old data from the server log table.',
            's',
            'SELECT pem.purge_server_log()',
            p_is_leader, TRUE,
            -- Schedule name
            'Server log table cleanup',
            -- Schedule description
            'This job schedule runs periodically to purge old data from the server log table.',
            '{f,f,t,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f}',
            '{f,t,f,f,f,f,f,f,f,f,f,f,f,t,f,f,f,f,f,f,f,f,f,f}'
        );
        -- JOB: Probe log table cleanup
        -- SCHEDULE: Run once a day
        PERFORM pem.create_or_update_system_job_with_a_step_and_schedule(
            p_agent_id, p_server_id, p_database,
            -- Job name
            'Probe log table cleanup',
            -- Job description
            'This job runs periodically to purge old data from the probe log table.',
            -- Step name
            'Probe log table cleanup',
            -- Step description
            'This job step runs periodically to purge old data from the probe log table.',
            's',
            'SELECT pem.purge_probe_log()',
            p_is_leader, TRUE,
            -- Schedule name
            'Probe log table cleanup',
            -- Schedule description
            'This job schedule runs periodically to purge old data from the probe log table.',
            '{t,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f}',
            '{f,f,t,f,f,f,f,f,f,f,f,f,f,f,t,f,f,f,f,f,f,f,f,f}'
        );
        -- JOB: SMTP spool table cleanup
        -- SCHEDULE: Run once a day
        PERFORM pem.create_or_update_system_job_with_a_step_and_schedule(
            p_agent_id, p_server_id, p_database,
            -- Job name
            'SMTP spool table cleanup',
            -- Job description
            'This job runs periodically to purge old data from the smtp spool table.',
            -- Step name
            'SMTP spool table cleanup',
            -- Step description
            'This job step runs periodically to purge old data from the smtp spool table.',
            's',
            'SELECT pem.purge_smtp_spool()',
            p_is_leader, TRUE,
            -- Schedule name
            'SMTP spool table cleanup',
            -- Schedule description
            'This job schedule runs periodically to purge old data from the smtp spool table.',
            '{t,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f}',
            '{f,f,f,t,f,f,f,f,f,f,f,f,f,f,f,t,f,f,f,f,f,f,f,f}'
        );
        -- JOB: SNMP spool table cleanup
        -- SCHEDULE: Run once a day
        PERFORM pem.create_or_update_system_job_with_a_step_and_schedule(
            p_agent_id, p_server_id, p_database,
            -- Job name
            'SNMP spool table cleanup',
            -- Job description
            'This job runs periodically to purge old data from the snmp spool table.',
            -- Step name
            'SNMP spool table cleanup',
            -- Step description
            'This job step runs periodically to purge old data from the snmp spool table.',
            's',
            'SELECT pem.purge_snmp_spool()',
            p_is_leader, TRUE,
            -- Schedule name
            'SNMP spool table cleanup',
            -- Schedule description
            'This job schedule runs periodically to purge old data from the snmp spool table.',
            '{t,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f}',
            '{f,f,f,t,f,f,f,f,f,f,f,f,f,f,f,t,f,f,f,f,f,f,f,f}'
        );
        -- JOB: Webhook spool table cleanup
        -- SCHEDULE: Run once a day
        PERFORM pem.create_or_update_system_job_with_a_step_and_schedule(
            p_agent_id, p_server_id, p_database,
            -- Job name
            'Webhook spool table cleanup',
            -- Job description
            'This job runs periodically to purge old data from the webhook spool table.',
            -- Step name
            'Webhook spool table cleanup',
            -- Step description
            'This job step runs periodically to purge old data from the webhook spool table.',
            's',
            'SELECT pem.purge_webhook_spool()',
            p_is_leader, TRUE,
            -- Schedule name
            'Webhook spool table cleanup',
            -- Schedule description
            'This job schedule runs periodically to purge old data from the webhook spool table.',
            '{t,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f}',
            '{f,f,f,t,f,f,f,f,f,f,f,f,f,f,f,t,f,f,f,f,f,f,f,f}'
        );
        -- JOB: Webhook spool history table cleanup
        -- SCHEDULE: Run once a day
        PERFORM pem.create_or_update_system_job_with_a_step_and_schedule(
            p_agent_id, p_server_id, p_database,
            -- Job name
            'Webhook spool history table cleanup',
            -- Job description
            'This job runs periodically to purge old data from the webhook spool history table.',
            -- Step name
            'Webhook spool history table cleanup',
            -- Step description
            'This job step runs periodically to purge old data from the webhook spool history table.',
            's',
            'SELECT pem.purge_webhook_spool_history()',
            p_is_leader, TRUE,
            -- Schedule name
            'Webhook spool history table cleanup',
            -- Schedule description
            'This job schedule runs periodically to purge old data from the webhook spool history table.',
            '{t,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f}',
            '{f,f,f,f,t,f,f,f,f,f,f,f,f,f,f,f,t,f,f,f,f,f,f,f}'
        );
        -- JOB: Alert history table cleanup
        -- SCHEDULE: Run once a day
        PERFORM pem.create_or_update_system_job_with_a_step_and_schedule(
            p_agent_id, p_server_id, p_database,
            -- Job name
            'Alert history table cleanup',
            -- Job description
            'This job runs periodically to purge old data from the alert history table.',
            -- Step name
            'Alert history table cleanup',
            -- Step description
            'This job step runs periodically to purge old data from the alert history table.',
            's',
            'SELECT pem.purge_alert_history()',
            p_is_leader, TRUE,
            -- Schedule name
            'Alert history table cleanup',
            -- Schedule description
            'This job schedule runs periodically to purge old data from the alert history table.',
            '{t,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f}',
            '{f,f,f,f,f,t,f,f,f,f,f,f,f,f,f,f,f,t,f,f,f,f,f,f}'
        );
        -- JOB: Job log table cleanup
        -- SCHEDULE: Run once a day
        PERFORM pem.create_or_update_system_job_with_a_step_and_schedule(
            p_agent_id, p_server_id, p_database,
            -- Job name
            'Job log table cleanup',
            -- Job description
            'This job runs periodically to purge old data from the job log table.',
            -- Step name
            'Job log table cleanup',
            -- Step description
            'This job step runs periodically to purge old data from the job log table.',
            's',
            'SELECT pem.purge_job_log()',
            p_is_leader, TRUE,
            -- Schedule name
            'Job log table cleanup',
            -- Schedule description
            'This job schedule runs periodically to purge old data from the job log table.',
            '{t,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f}',
            '{f,f,f,f,f,f,t,f,f,f,f,f,f,f,f,f,f,f,t,f,f,f,f,f}'
        );
    END
    $FUNC$ LANGUAGE 'plpgsql';

    -- ==========================================================
    -- Function: pem.create_pem_server_system_tasks_purge_deleted
    -- Description:
    -- Creates jobs to periodically purge deleted charts and
    -- deleted custom probes from the PEM system. Both jobs are
    -- scheduled to run once per day.
    -- ==========================================================
    CREATE OR REPLACE FUNCTION pem.create_pem_server_system_tasks_purge_deleted(
        p_agent_id integer,
        p_server_id integer,
        p_database text,
        p_is_leader boolean
    )
        RETURNS void AS
    $FUNC$
    BEGIN
        -- JOB: Job purge the deleted charts
        -- SCHEDULE: Run once a day
        PERFORM pem.create_or_update_system_job_with_a_step_and_schedule(
            p_agent_id, p_server_id, p_database,
            -- Job name
            'Job purge the deleted charts',
            -- Job description
            'This job runs periodically to purge the deleted charts.',
            -- Step name
            'Job purge the deleted charts',
            -- Step description
            'This job step runs periodically to purge the deleted charts (we do not clean them up immediately).',
            's',
            'SELECT pem.purge_deleted_charts()',
            p_is_leader, TRUE,
            -- Schedule name
            'Job purge the deleted charts',
            -- Schedule description
            'This job schedule runs periodically to purge the deleted charts.',
            '{t,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f}',
            '{f,f,t,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f}'
        );
        -- JOB: Purge deleted custom probes
        -- SCHEDULE: Run once a day
        PERFORM pem.create_or_update_system_job_with_a_step_and_schedule(
            p_agent_id, p_server_id, p_database,
            -- Job name
            'Purge deleted custom probes',
            -- Job description
            'This job runs periodically to purge the deleted probes.',
            -- Step name
            'Purge deleted custom probes',
            -- Step description
            'This job runs periodically to purge deleted custom probes and its data.',
            's',
            'SELECT pem.purge_deleted_probes()',
            p_is_leader, TRUE,
            -- Schedule name
            'Purge deleted custom probes',
            -- Schedule description
            'This job runs periodically to purge deleted custom probes and its data.',
            '{t,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f}',
            '{f,t,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f}'
        );
    END
    $FUNC$ LANGUAGE 'plpgsql';

    -- ==========================================================
    -- Function: pem.create_pem_server_system_tasks_check_ca_certificate_expiry
    -- Description:
    -- Creates a job that checks for the expiry of the CA
    -- certificate used by PEM, ensuring timely alerts before
    -- certificate expiration.
    -- ==========================================================
    CREATE OR REPLACE FUNCTION pem.create_pem_server_system_tasks_check_ca_certificate_expiry(
        p_agent_id integer,
        p_server_id integer,
        p_database text,
        p_is_leader boolean
    )
        RETURNS void AS
    $FUNC$
    BEGIN
        -- JOB: Check CA certificate expiry
        PERFORM pem.create_or_update_system_job_with_a_step_and_schedule(
            p_agent_id, p_server_id, p_database,
            -- Job name
            'Check CA certificate expiry',
            -- Job description
            'This job check the expiry of CA certificate.',
            -- Step name
            'Check CA certificate expiry',
            -- Step description
            'This job step runs to check the expiry of CA certificate.',
            'i',
            'check_server_certificate_expiry',
            p_is_leader, TRUE
        );
    END
    $FUNC$ LANGUAGE 'plpgsql';

    -- ==========================================================
    -- Function: pem.create_pem_server_system_tasks_blackout_unreachable_servers
    -- Description:
    -- Creates a job that automatically blackouts servers or agents
    -- that are no longer reachable. The job runs on an hourly
    -- schedule.
    -- ==========================================================
    CREATE OR REPLACE FUNCTION pem.create_pem_server_system_tasks_blackout_unreachable_servers(
        p_agent_id integer,
        p_server_id integer,
        p_database text,
        p_is_leader boolean
    )
        RETURNS void AS
    $FUNC$
    BEGIN
        -- JOB: Blackout unreachable servers/agents
        PERFORM pem.create_or_update_system_job_with_a_step_and_schedule(
            p_agent_id, p_server_id, p_database,
            -- Job name
            'Blackout unreachable servers/agents',
            -- Job description
            'This job will blackout the servers/agents that are no longer reachable.',
            -- Step name
            'Blackout unreachable servers/agents',
            -- Step description
            'This job step runs to blackout the server/agent if it is unreachable.',
            's',
            'select pem.auto_blackout()',
            p_is_leader, TRUE,
            -- Schedule name
            'Blackout unreachable servers/agents',
            -- Schedule description
            'This job runs periodically to blackout the unreachable servers/agents.',
            '{t,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f}',
            '{t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t}'
        );
    END
    $FUNC$ LANGUAGE 'plpgsql';

    -- ----------------
    -- FUNCTION: pem.create_pem_server_system_tasks()
    --
    -- It will create the system jobs for these agent & server combination.
    -- They will be disabled by default.
    -- When leader is found automatically as a 'standalone' or 'primary', it will
    -- enable these system jobs.
    CREATE OR REPLACE FUNCTION pem.create_pem_server_system_tasks()
    RETURNS void AS
    $FUNC$
    DECLARE
        rec RECORD;
    BEGIN
        FOR rec IN SELECT * FROM pem.pem_host_and_server
        LOOP
            -- Call all the sub-functions with explicit parameters for each record
            PERFORM pem.create_pem_server_system_tasks_data_cleanup(rec.agent_id, rec.server_id, rec.database, rec.is_leader);
            PERFORM pem.create_pem_server_system_tasks_update_probes(rec.agent_id, rec.server_id, rec.database, rec.is_leader);
            PERFORM pem.create_pem_server_system_tasks_log_cleanup(rec.agent_id, rec.server_id, rec.database, rec.is_leader);
            PERFORM pem.create_pem_server_system_tasks_purge_deleted(rec.agent_id, rec.server_id, rec.database, rec.is_leader);
            PERFORM pem.create_pem_server_system_tasks_check_ca_certificate_expiry(rec.agent_id, rec.server_id, rec.database, rec.is_leader);
            PERFORM pem.create_pem_server_system_tasks_blackout_unreachable_servers(rec.agent_id, rec.server_id, rec.database, rec.is_leader);
            PERFORM pem.create_pem_server_system_tasks_refresh_probe_view(rec.agent_id, rec.server_id, rec.database, rec.is_leader);
        END LOOP;
    END
    $FUNC$ LANGUAGE 'plpgsql';

    -- Calling the function to create a job which will blackout the unreachable server/agent
    DO $$
    DECLARE
        rec RECORD;
    BEGIN
        FOR rec IN SELECT * FROM pem.pem_host_and_server
        LOOP
            PERFORM pem.create_pem_server_system_tasks_blackout_unreachable_servers(
                rec.agent_id,
                rec.server_id,
                rec.database,
                rec.is_leader
            );
        END LOOP;
    END
    $$;

    -- Function definition for automatically disabling the alerts for unreachable servers/agents
    CREATE OR REPLACE FUNCTION pem.auto_blackout()
	RETURNS void AS
    $FUNC$
    DECLARE
        v_timeout_value   INTEGER;
    BEGIN
        --
        -- Fetch the server contact timeout value from the configuration table.
        -- The value is assumed to be in hours.
        --
        SELECT value
        INTO v_timeout_value
        FROM pem.config
        WHERE param = 'server_contact_timeout';

        --
        -- 1. Blackout servers when the last heartbeat is older than the configured timeout in hours.
        --
        UPDATE pem.server s
        SET
            alert_blackout = true,
            auto_alert_blackout = true
        FROM pem.server_heartbeat sh
        WHERE
            s.id = sh.server_id
            AND sh.last_heartbeat < NOW() - (v_timeout_value || ' hours')::interval;

        --
        -- 2. Un-blackout servers only if the blackout was system-initiated.
        --
        UPDATE pem.server s
        SET
            alert_blackout = false,
            auto_alert_blackout = false
        FROM pem.server_heartbeat sh
        WHERE
            s.id = sh.server_id
            AND sh.last_heartbeat >= NOW() - (v_timeout_value || ' hours')::interval
            AND s.auto_alert_blackout = true;

        --
        -- 3. Blackout agents when the last heartbeat is older than the configured timeout in hours.
        --
        UPDATE pem.agent a
        SET
            alert_blackout = true,
            auto_alert_blackout = true
        FROM pem.agent_heartbeat ah
        WHERE
            a.id = ah.agent_id
            AND ah.last_heartbeat < NOW() - (v_timeout_value || ' hours')::interval;

        --
        -- 4. Un-blackout agents only if the blackout was system-initiated.
        --
        UPDATE pem.agent a
        SET
            alert_blackout = false,
            auto_alert_blackout = false
        FROM pem.agent_heartbeat ah
        WHERE
            a.id = ah.agent_id
            AND ah.last_heartbeat >= NOW() - (v_timeout_value || ' hours')::interval
            AND a.auto_alert_blackout = true;
    END
    $FUNC$ LANGUAGE 'plpgsql';

    -- PEM-5717: for adding privilges to pgAdmin functionalities/Tools.
	DO $$
	    BEGIN
	        IF NOT EXISTS (SELECT 1 FROM pem.roles WHERE  component = 'query_tool') THEN 
	        PERFORM pem.create_role_for(
	            'query_tool',
	            'Role to Access Query Tool',
	            ARRAY['pem_admin']
	        );
	        END IF;
	        IF NOT EXISTS (SELECT 1 FROM pem.roles WHERE  component = 'schema_diff_tool') THEN 
	        PERFORM pem.create_role_for(
	            'schema_diff_tool',
	            'Role to Access Schema Diff Tool',
	            ARRAY['pem_admin']
	        );
	        END IF;
	        IF NOT EXISTS (SELECT 1 FROM pem.roles WHERE  component = 'debugger_tool') THEN 
	        PERFORM pem.create_role_for(
	            'debugger_tool',
	            'Role to Access Debugger Tool',
	            ARRAY['pem_admin']
	        );
	        END IF;
	        IF NOT EXISTS (SELECT 1 FROM pem.roles WHERE  component = 'erd_tool') THEN 
	        PERFORM pem.create_role_for(
	            'erd_tool',
	            'Role to Access ERD Tool',
	            ARRAY['pem_admin']
	        );
	        END IF;
	        IF NOT EXISTS (SELECT 1 FROM pem.roles WHERE  component = 'grant_wizard') THEN 
	        PERFORM pem.create_role_for(
	            'grant_wizard',
	            'Role to Access Grant Wizard',
	            ARRAY['pem_admin']
	        );
	        END IF;
	        IF NOT EXISTS (SELECT 1 FROM pem.roles WHERE  component = 'backup_tool') THEN 
	        PERFORM pem.create_role_for(
	            'backup_tool',
	            'Role to Access Backup Tool',
	            ARRAY['pem_admin']
	        );
	        END IF;
	        IF NOT EXISTS (SELECT 1 FROM pem.roles WHERE  component = 'restore_tool') THEN 
	        PERFORM pem.create_role_for(
	            'restore_tool',
	            'Role to Access Restore Tool',
	            ARRAY['pem_admin']
	        );
	        END IF;
	        IF NOT EXISTS (SELECT 1 FROM pem.roles WHERE  component = 'import_export_data_tool') THEN 
	        PERFORM pem.create_role_for(
	            'import_export_data_tool',
	            'Role to Access Import/Export Data Tool',
	            ARRAY['pem_admin']
	        );
	        END IF;
	        IF NOT EXISTS (SELECT 1 FROM pem.roles WHERE  component = 'search_objects_tool') THEN 
	        PERFORM pem.create_role_for(
	            'search_objects_tool',
	            'Role to Access Search Objects Tool',
	            ARRAY['pem_admin']
	        );
	        END IF;
	        IF NOT EXISTS (SELECT 1 FROM pem.roles WHERE  component = 'maintenance_tool') THEN 
	        PERFORM pem.create_role_for(
	            'maintenance_tool',
	            'Role to Access Maintenance Tool',
	            ARRAY['pem_admin']
	        );
	        END IF;
	    END;
    $$ LANGUAGE 'plpgsql';	

    -- PEM-5755 Create Manage Profile and Configuration Tables
    -- Main table to define the profiles
    CREATE TABLE IF NOT EXISTS pem.profile (
        id SERIAL PRIMARY KEY,
        name TEXT NOT NULL,
        description TEXT,
        target_kind CHAR(1) NOT NULL CHECK (target_kind IN ('a', 's')), -- 'a' -> Agent/Host, 's' -> Server
        status TEXT NOT NULL DEFAULT 'published' CHECK (status IN ('published', 'draft')),
        parent_id INTEGER REFERENCES pem.profile(id) ON DELETE CASCADE
    );

    -- This ensures a published profile can have at most ONE draft.
    CREATE UNIQUE INDEX IF NOT EXISTS one_draft_per_profile_idx
    ON pem.profile (parent_id)
    WHERE status = 'draft';

    -- The user-facing name should be unique for published profiles.
    CREATE UNIQUE INDEX IF NOT EXISTS unique_published_profile_name_idx
    ON pem.profile (name)
    WHERE status = 'published';

    -- Stores the specific probe configurations for each profile
    CREATE TABLE IF NOT EXISTS pem.profile_probe_configs (
        profile_id  INTEGER NOT NULL REFERENCES pem.profile(id) ON DELETE CASCADE,
        probe_id    INTEGER NOT NULL REFERENCES pem.probe(id) ON DELETE CASCADE,
        enabled     BOOLEAN,
        enabled_by_default BOOLEAN,
        execution_frequency INTEGER,
        lifetime    INTEGER,
        CONSTRAINT profile_probe_config_pkey PRIMARY KEY (profile_id, probe_id)
    );

    -- Stores the specific alert configurations for each profile
    CREATE TABLE IF NOT EXISTS pem.profile_alert_configs (
        -- Primary Key (Optional but good practice)
        id                          BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,

        -- Foreign Key to Profile
        profile_id                  INTEGER NOT NULL REFERENCES pem.profile(id) ON DELETE CASCADE,

        -- Link to the Alert Template (Crucial)
        template_id                 INTEGER NOT NULL,
        CONSTRAINT profile_alert_configs_template_id_fkey FOREIGN KEY (template_id) REFERENCES pem.alert_template(id) ON DELETE CASCADE,

        -- User-defined name for the alert instance within the profile
        name                        TEXT NOT NULL, -- Keep this as requested

        -- Configurable Alert Fields (Mirroring pem.alert, but generic)
        params                      TEXT[],
        operator                    TEXT CHECK (operator IN ('<', '>')), -- Enforce valid operators
        thresholds                  NUMERIC[] CHECK (array_upper(thresholds, 1) = 3), -- Ensure 3 thresholds
        check_frequency             INTEGER CHECK (check_frequency > 0),
        history_retention           INTEGER CHECK (history_retention > 0),
        enabled                     BOOLEAN,

        -- Email and SNMP Trap fields
        email_group_id              INTEGER, -- REFERENCES pem.email_group(id) ON DELETE SET NULL,
        send_email                  BOOLEAN,
        send_trap                   BOOLEAN,
        snmp_trap_version           INTEGER,
        low_send_trap               BOOLEAN,
        low_email_group_id          INTEGER,
        med_send_trap               BOOLEAN,
        med_email_group_id          INTEGER,
        high_send_trap              BOOLEAN,
        high_email_group_id         INTEGER,

        -- Script Execution fields
        execute_script              BOOLEAN,
        execute_script_on_clear     BOOLEAN,
        execute_script_on_pem_server BOOLEAN,
        script_code                 TEXT,

        -- External Integration fields
        submit_to_nagios            BOOLEAN,
        cleared_alert_enable        BOOLEAN,

        -- Webhook configs
        send_notification           BOOLEAN NOT NULL DEFAULT FALSE,
        override_default_config     BOOLEAN NOT NULL DEFAULT FALSE,
        low_webhook_ids             INTEGER[],
        med_webhook_ids             INTEGER[],
        high_webhook_ids            INTEGER[],
        cleared_webhook_ids         INTEGER[],

        -- Ensures a profile doesn't configure the same alert name twice
        CONSTRAINT profile_alert_configs_profile_name_uq UNIQUE (profile_id, name)
    );


    -- Add the profile link to your existing tables
    ALTER TABLE pem.server
    ADD COLUMN IF NOT EXISTS profile_id integer REFERENCES pem.profile(id) ON DELETE SET NULL;

    ALTER TABLE pem.agent
    ADD COLUMN IF NOT EXISTS profile_id integer REFERENCES pem.profile(id) ON DELETE SET NULL;

    -- Added profile_id to avail_agents view
    CREATE OR REPLACE VIEW pem.avail_agents AS
    SELECT
        a.id AS id,
        a.agent_capability_list AS agent_capability_list,
        COALESCE(ao.description, a.description) AS description,
        a.active AS active,
        a.heartbeat_tolerance AS heartbeat_tolerance,
        a.alert_blackout AS alert_blackout,
        a.version AS version,
        a.platform AS platform,
        a.owner AS owner,
        a.team AS team,
        a.owner::regrole::name AS agent_owner,
        COALESCE(ao.group_id, a.group_id, 0) AS group_id,
        a.profile_id AS profile_id
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

    -- Added profile_id to avail_servers view
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
            COALESCE(so.server_group_id, s.group_id, 1) AS group_id,
            s.profile_id as profile_id
        FROM pem.server s
            LEFT JOIN pem.server_options so ON (s.id = so.server_id AND pem_user = current_user)
        WHERE
            -- Only active servers
            s.active AND
            pem.can_access_team(s.owner, s.team);


    CREATE OR REPLACE FUNCTION pem.apply_alert_profile_to_target(
        p_profile_id INTEGER,
        p_target_type TEXT, -- 'server' or 'agent'
        p_target_id INTEGER
    )
    RETURNS VOID AS $$
    DECLARE
        v_server_id INTEGER := NULL;
        v_agent_id INTEGER := NULL;
        v_server_version_id INTEGER := 0; -- Variable to hold the server's version ID
        v_is_active BOOLEAN := FALSE; -- Variable to hold active status
    BEGIN
        -- Determine target IDs, version_id, and active status
        IF p_target_type = 'server' THEN
            v_server_id := p_target_id;
            v_agent_id := 0;

            -- Fetch server active status (from pem.server) and version (from pemdata.server_info)
            BEGIN
                SELECT
                    s.active,
                    COALESCE(si.server_version_id, 0)
                INTO
                    v_is_active,
                    v_server_version_id
                FROM pem.server s
                LEFT JOIN pemdata.server_info si ON s.id = si.server_id
                WHERE s.id = v_server_id;
            EXCEPTION
                WHEN no_data_found THEN
                    v_is_active := FALSE; -- Can't be active if not found
                    v_server_version_id := 0;
                WHEN others THEN
                    v_is_active := FALSE; -- Default to not active on error
                    v_server_version_id := 0; 
            END;

        ELSIF p_target_type = 'agent' THEN
            v_agent_id := p_target_id;
            v_server_id := 0;
            v_server_version_id := 0; -- Not a server

            -- Fetch agent active status (from pem.agent)
            BEGIN
                SELECT active
                INTO v_is_active
                FROM pem.agent
                WHERE id = v_agent_id;
            EXCEPTION
                WHEN no_data_found THEN
                    v_is_active := FALSE; -- Can't be active if not found
                WHEN others THEN
                    v_is_active := FALSE; -- Default to not active on error
            END;

        ELSE
            RAISE EXCEPTION 'Invalid target type specified: %', p_target_type;
        END IF;

        -- Exit function immediately if the target is not active
        IF NOT v_is_active THEN
            RETURN;
        END IF;

        -- Step 1: Update existing alerts (match by template_id + name to allow multiple alerts per template)
        UPDATE pem.alert a
            SET
                name = pc.name,
                params = pc.params,
                operator = pc.operator,
                thresholds = pc.thresholds,
                check_frequency = pc.check_frequency,
                history_retention = pc.history_retention,
                enabled = pc.enabled,
                email_group_id = pc.email_group_id,
                send_email = pc.send_email,
                send_trap = pc.send_trap,
                snmp_trap_version = pc.snmp_trap_version,
                low_send_trap = pc.low_send_trap,
                low_email_group_id = pc.low_email_group_id,
                med_send_trap = pc.med_send_trap,
                med_email_group_id = pc.med_email_group_id,
                high_send_trap = pc.high_send_trap,
                high_email_group_id = pc.high_email_group_id,
                execute_script = pc.execute_script,
                execute_script_on_clear = pc.execute_script_on_clear,
                execute_script_on_pem_server = pc.execute_script_on_pem_server,
                script_code = pc.script_code,
                submit_to_nagios = pc.submit_to_nagios,
                cleared_alert_enable = pc.cleared_alert_enable
            FROM pem.profile_alert_configs pc
            JOIN pem.alert_template at ON at.id = pc.template_id
            WHERE
                pc.profile_id = p_profile_id
                AND a.template_id = pc.template_id
                AND a.name = pc.name  -- ensure we only update the specific named instance
                AND COALESCE(a.server_id, 0) = COALESCE(v_server_id, 0)
                AND COALESCE(a.agent_id, 0) = COALESCE(v_agent_id, 0)
                AND COALESCE(TRIM(a.database_name), '') = ''
                AND COALESCE(TRIM(a.schema_name), '') = ''
                AND COALESCE(TRIM(a.package_name), '') = ''
                AND COALESCE(TRIM(a.object_name), '') = ''
                AND (
                    v_server_id = 0 -- Always include if it's an agent-level alert
                    OR at.applicable_on_server = 'ALL'
                    OR (at.applicable_on_server = 'POSTGRES_SERVER' AND (v_server_version_id > 10900 AND v_server_version_id < 20000))
                    OR (at.applicable_on_server = 'ADVANCED_SERVER' AND (v_server_version_id > 20000))
                );

        -- Step 2: Insert new alerts (permit multiple alerts per template distinguished by name)
        INSERT INTO pem.alert (
            template_id, agent_id, server_id, database_name, schema_name, package_name, object_name,
            name, params, operator, thresholds, check_frequency, history_retention, enabled, auto_created,
            email_group_id, send_email, flapping_detected, last_flapping_detection_processed, send_trap, snmp_trap_version,
            low_send_trap, low_email_group_id, med_send_trap, med_email_group_id, high_send_trap, high_email_group_id,
            execute_script, execute_script_on_clear, execute_script_on_pem_server, script_code, submit_to_nagios,
            cleared_alert_enable
        )
        SELECT
            pc.template_id, v_agent_id, v_server_id, NULL, NULL, NULL, NULL, -- Target IDs
            pc.name, pc.params, pc.operator, pc.thresholds, pc.check_frequency, pc.history_retention, pc.enabled, FALSE, -- Configs
            pc.email_group_id, pc.send_email, FALSE, NOW(), pc.send_trap, pc.snmp_trap_version, -- Configs + default
            pc.low_send_trap, pc.low_email_group_id, pc.med_send_trap, pc.med_email_group_id, pc.high_send_trap, pc.high_email_group_id,
            pc.execute_script, pc.execute_script_on_clear, pc.execute_script_on_pem_server, pc.script_code, pc.submit_to_nagios,
            pc.cleared_alert_enable
        FROM pem.profile_alert_configs pc
        JOIN pem.alert_template at ON at.id = pc.template_id
        WHERE pc.profile_id = p_profile_id
        AND (
            v_server_id = 0 -- Always include if it's an agent-level alert
            OR at.applicable_on_server = 'ALL'
            OR (at.applicable_on_server = 'POSTGRES_SERVER' AND (v_server_version_id > 10900 AND v_server_version_id < 20000))
            OR (at.applicable_on_server = 'ADVANCED_SERVER' AND (v_server_version_id > 20000))
        )
        AND NOT EXISTS ( -- Only insert if no alert with same template_id + name exists at root scope for target
            SELECT 1
            FROM pem.alert existing
            WHERE existing.template_id = pc.template_id
            AND existing.name = pc.name
            AND COALESCE(existing.agent_id, 0) = COALESCE(v_agent_id, 0)
            AND COALESCE(existing.server_id, 0) = COALESCE(v_server_id, 0)
            AND COALESCE(TRIM(existing.database_name), '') = ''
            AND COALESCE(TRIM(existing.schema_name), '') = ''
            AND COALESCE(TRIM(existing.package_name), '') = ''
            AND COALESCE(TRIM(existing.object_name), '') = ''
        );

        -- Step 2b: Maintain webhook configurations.
        -- Preference: when override_default_config = FALSE the entire webhook_alert_config row should be absent.
        -- Implementation:
        --   1. Delete rows for alerts whose profile sets override_default_config = FALSE.
        --   2. Upsert rows for alerts whose profile sets override_default_config = TRUE.

        -- 1. Delete rows for FALSE overrides
        DELETE FROM pem.webhook_alert_config w
        USING pem.alert a
        JOIN pem.profile_alert_configs pc
            ON pc.profile_id = p_profile_id
         AND a.template_id = pc.template_id
         AND a.name = pc.name
        WHERE w.alert_id = a.id
            AND pc.override_default_config = FALSE
            AND COALESCE(a.server_id, 0) = COALESCE(v_server_id, 0)
            AND COALESCE(a.agent_id, 0) = COALESCE(v_agent_id, 0)
            AND COALESCE(TRIM(a.database_name), '') = ''
            AND COALESCE(TRIM(a.schema_name), '') = ''
            AND COALESCE(TRIM(a.package_name), '') = ''
            AND COALESCE(TRIM(a.object_name), '') = '';

        -- 2. Upsert rows for TRUE overrides only
        INSERT INTO pem.webhook_alert_config (
                alert_id,
                send_notification,
                override_default_config,
                low_webhook_ids,
                med_webhook_ids,
                high_webhook_ids,
                cleared_webhook_ids
        )
        SELECT
                a.id,
                pc.send_notification,
                pc.override_default_config,
                pc.low_webhook_ids,
                pc.med_webhook_ids,
                pc.high_webhook_ids,
                pc.cleared_webhook_ids
        FROM pem.alert a
        JOIN pem.profile_alert_configs pc
            ON pc.profile_id = p_profile_id
         AND a.template_id = pc.template_id
         AND a.name = pc.name
        WHERE pc.override_default_config = TRUE
            AND COALESCE(a.server_id, 0) = COALESCE(v_server_id, 0)
            AND COALESCE(a.agent_id, 0) = COALESCE(v_agent_id, 0)
            AND COALESCE(TRIM(a.database_name), '') = ''
            AND COALESCE(TRIM(a.schema_name), '') = ''
            AND COALESCE(TRIM(a.package_name), '') = ''
            AND COALESCE(TRIM(a.object_name), '') = ''
        ON CONFLICT (alert_id) DO UPDATE SET
                send_notification = EXCLUDED.send_notification,
                override_default_config = EXCLUDED.override_default_config,
                low_webhook_ids = EXCLUDED.low_webhook_ids,
                med_webhook_ids = EXCLUDED.med_webhook_ids,
                high_webhook_ids = EXCLUDED.high_webhook_ids,
                cleared_webhook_ids = EXCLUDED.cleared_webhook_ids;

        -- Step 3: Delete extra alerts (delete only if (template_id, name) pair absent from profile)
        DELETE FROM pem.alert a USING pem.alert_template at
        WHERE
            at.id = a.template_id
            AND COALESCE(a.server_id, 0) = COALESCE(v_server_id, 0)
            AND COALESCE(a.agent_id, 0) = COALESCE(v_agent_id, 0)
            AND COALESCE(TRIM(a.database_name), '') = ''
            AND COALESCE(TRIM(a.schema_name), '') = ''
            AND COALESCE(TRIM(a.package_name), '') = ''
            AND COALESCE(TRIM(a.object_name), '') = ''
            AND at.is_auto_create = FALSE -- Only delete alerts whose template is not auto-create
            AND NOT EXISTS ( -- Delete if the (template_id, name) pair is NOT in the profile (for this server type)
                SELECT 1
                FROM pem.profile_alert_configs pc
                JOIN pem.alert_template at2 ON at2.id = pc.template_id
                WHERE pc.profile_id = p_profile_id
                AND pc.template_id = a.template_id
                AND pc.name = a.name
                -- The compatibility logic
                AND (
                    v_server_id = 0 -- Always include if it's an agent-level alert
                    OR at2.applicable_on_server = 'ALL'
                    OR (at2.applicable_on_server = 'POSTGRES_SERVER' AND (v_server_version_id > 10900 AND v_server_version_id < 20000))
                    OR (at2.applicable_on_server = 'ADVANCED_SERVER' AND (v_server_version_id > 20000))
                )
            );

    END;
    $$ LANGUAGE plpgsql;

    CREATE OR REPLACE FUNCTION pem.trg_apply_alert_profile_server() RETURNS trigger AS $$
    BEGIN
        IF TG_OP='INSERT' THEN
            IF NEW.profile_id IS NOT NULL THEN
                PERFORM pem.apply_alert_profile_to_target(NEW.profile_id,'server',NEW.id);
            END IF;
        ELSIF TG_OP='UPDATE' THEN
            IF NEW.profile_id IS DISTINCT FROM OLD.profile_id AND NEW.profile_id IS NOT NULL THEN
                PERFORM pem.apply_alert_profile_to_target(NEW.profile_id,'server',NEW.id);
            END IF;
        END IF;
        RETURN NEW;
    END; $$ LANGUAGE plpgsql;

    CREATE OR REPLACE FUNCTION pem.trg_apply_alert_profile_agent() RETURNS trigger AS $$
    BEGIN
        IF TG_OP='INSERT' THEN
            IF NEW.profile_id IS NOT NULL THEN
                PERFORM pem.apply_alert_profile_to_target(NEW.profile_id,'agent',NEW.id);
            END IF;
        ELSIF TG_OP='UPDATE' THEN
            IF NEW.profile_id IS DISTINCT FROM OLD.profile_id AND NEW.profile_id IS NOT NULL THEN
                PERFORM pem.apply_alert_profile_to_target(NEW.profile_id,'agent',NEW.id);
            END IF;
        END IF;
        RETURN NEW;
    END; $$ LANGUAGE plpgsql;

    DROP TRIGGER IF EXISTS server_apply_alert_profile ON pem.server;
    CREATE TRIGGER server_apply_alert_profile
    AFTER INSERT OR UPDATE OF profile_id ON pem.server
    FOR EACH ROW EXECUTE PROCEDURE pem.trg_apply_alert_profile_server();

    DROP TRIGGER IF EXISTS agent_apply_alert_profile ON pem.agent;
    CREATE TRIGGER agent_apply_alert_profile
    AFTER INSERT OR UPDATE OF profile_id ON pem.agent
    FOR EACH ROW EXECUTE PROCEDURE pem.trg_apply_alert_profile_agent();

    -- Safely drop probe_target_view regardless of whether it was created as a
    -- regular view or a materialized view in a previous version.
    DO $$
    BEGIN
        -- Check for materialized view first
        IF EXISTS (
            SELECT 1 FROM pg_catalog.pg_matviews
            WHERE schemaname = 'pem' AND matviewname = 'probe_target_view'
        ) THEN
            EXECUTE 'DROP MATERIALIZED VIEW pem.probe_target_view CASCADE';
        ELSIF EXISTS (
            SELECT 1 FROM pg_catalog.pg_views
            WHERE schemaname = 'pem' AND viewname = 'probe_target_view'
        ) THEN
            EXECUTE 'DROP VIEW pem.probe_target_view CASCADE';
        END IF;
        -- If it doesn't exist, do nothing.
    END$$;

    CREATE MATERIALIZED VIEW pem.probe_target_view AS
    -- Block 1: Agent Probes
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
        COALESCE(ppc.enabled, c.enabled, p.enabled_by_default) AS enabled,
        COALESCE(ppc.execution_frequency, c.execution_frequency, p.default_execution_frequency) AS execution_frequency,
        COALESCE(ppc.lifetime, c.lifetime, p.default_lifetime) AS lifetime,
        a.active AS agent_active,
        p.discard_history,
        p.is_system_probe
    FROM
        pem.probe p
        CROSS JOIN pem.agent a
        LEFT JOIN pem.probe_config_agent c ON p.id = c.probe_id AND a.id = c.agent_id
        LEFT JOIN pem.profile_probe_configs ppc ON a.profile_id = ppc.profile_id AND p.id = ppc.probe_id
    WHERE
        p.target_type_id = 100 AND NOT p.deleted
        AND (p.agent_capability IS NULL OR p.agent_capability = ANY(a.agent_capability_list))
        AND ((p.collection_method NOT IN ('b', 'w')) OR
            (p.collection_method ='b' AND (a.agent_capability_list @> ARRAY['allow_batch_probes'])
                AND ((strpos(a.platform, p.platform) != 0) OR (a.platform !~ 'windows' AND p.platform = 'unix'))) OR
            (p.collection_method = 'w' AND strpos(a.platform, 'windows') != 0))
    UNION ALL
    -- Block 2: Server Probes
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
        COALESCE(ppc.enabled, c.enabled, p.enabled_by_default) AS enabled,
        COALESCE(ppc.execution_frequency, c.execution_frequency, p.default_execution_frequency) AS execution_frequency,
        COALESCE(ppc.lifetime, c.lifetime, p.default_lifetime) AS lifetime,
        a.active AS agent_active,
        p.discard_history,
        p.is_system_probe
    FROM
        pem.probe p
        CROSS JOIN pem.agent_server_binding b
        INNER JOIN pem.agent a ON b.agent_id = a.id
        INNER JOIN pem.server s ON b.server_id = s.id
        LEFT JOIN pemdata.server_info sd ON b.server_id = sd.server_id
        LEFT JOIN pem.probe_server_version psv ON p.id = psv.probe_id AND sd.server_version_id = psv.server_version_id
        LEFT JOIN pem.probe_config_server c ON p.id = c.probe_id AND b.server_id = c.server_id
        LEFT JOIN pem.profile_probe_configs ppc ON s.profile_id = ppc.profile_id AND p.id = ppc.probe_id
    WHERE
        p.target_type_id = 200 AND NOT p.deleted
        AND (p.agent_capability IS NULL OR p.agent_capability = ANY(a.agent_capability_list))
        AND (p.any_server_version OR psv.probe_id IS NOT NULL)
        AND p.internal_name NOT IN( SELECT UNNEST(CASE WHEN s.is_remote_monitoring THEN ARRAY['pg_hba_conf', 'data_log_file_analysis', 'wal_archive_status', 'log_configuration', 'efm_cluster_node_status', 'efm_cluster_info'] ELSE ARRAY[''] END))
        AND p.internal_name NOT IN( SELECT UNNEST(CASE WHEN a.agent_capability_list @> ARRAY['windows'] THEN ARRAY['efm_cluster_node_status', 'efm_cluster_info'] ELSE ARRAY[''] END))
        AND (p.collection_method != 'b' OR (p.collection_method ='b' AND (a.agent_capability_list @> ARRAY['allow_batch_probes'])
                AND ((strpos(a.platform, p.platform) != 0) OR (a.platform !~ 'windows' AND p.platform = 'unix'))))
        AND b.database NOT IN (SELECT UNNEST(b.exclude_databases))
    UNION ALL
    -- Block 3: Database Probes
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
        COALESCE(ppc.enabled, c.enabled, p.enabled_by_default) AS enabled,
        COALESCE(ppc.execution_frequency, c.execution_frequency, p.default_execution_frequency) AS execution_frequency,
        COALESCE(ppc.lifetime, c.lifetime, p.default_lifetime) AS lifetime,
        a.active AS agent_active,
        p.discard_history,
        p.is_system_probe
    FROM
        pem.probe p
        CROSS JOIN pem.agent_server_binding b
        INNER JOIN pem.agent a ON b.agent_id = a.id
        INNER JOIN pem.server s ON b.server_id = s.id
        LEFT JOIN pemdata.server_info sd ON b.server_id = sd.server_id
        LEFT JOIN pem.probe_server_version psv ON p.id = psv.probe_id AND sd.server_version_id = psv.server_version_id
        INNER JOIN pemdata.oc_database ocd ON b.server_id = ocd.server_id
        LEFT JOIN pem.probe_config_database c ON p.id = c.probe_id AND b.server_id = c.server_id AND ocd.database_name = c.database_name
        LEFT JOIN pem.profile_probe_configs ppc ON s.profile_id = ppc.profile_id AND p.id = ppc.probe_id
    WHERE
        p.target_type_id = 300 AND NOT p.deleted
        AND ocd.connections_allowed
        AND (p.agent_capability IS NULL OR p.agent_capability = ANY(a.agent_capability_list))
        AND (p.any_server_version OR psv.probe_id IS NOT NULL)
        AND (p.collection_method != 'b' OR (p.collection_method ='b' AND (a.agent_capability_list @> ARRAY['allow_batch_probes'])
                AND ((strpos(a.platform, p.platform) != 0) OR (a.platform !~ 'windows' AND p.platform = 'unix'))))
        AND ocd.database_name NOT IN (SELECT UNNEST(b.exclude_databases))
    UNION ALL
    -- Block 4: Schema Probes
    SELECT
        p.id AS probe_id, p.display_name AS probe_display_name,
        p.internal_name AS probe_internal_name, p.probe_key_list,
        p.applies_to_id,
        a.id AS agent_id, b.server_id, oc.database_name AS database_name,
        ARRAY['server_id', 'database_name', 'schema_name']::text[] AS parameter_name_list,
        ARRAY[b.server_id::text, oc.database_name, oc.schema_name]::text[] AS parameter_value_list,
        p.collection_method,
        COALESCE(NULLIF(TRIM(psv.probe_code), ''), p.probe_code) AS probe_code,
        p.enabled_by_default, p.default_execution_frequency,
        p.default_lifetime,
        COALESCE(ppc.enabled, c.enabled, p.enabled_by_default) AS enabled,
        COALESCE(ppc.execution_frequency, c.execution_frequency, p.default_execution_frequency) AS execution_frequency,
        COALESCE(ppc.lifetime, c.lifetime, p.default_lifetime) AS lifetime,
        a.active AS agent_active,
        p.discard_history,
        p.is_system_probe
    FROM
        pem.probe p
        CROSS JOIN pem.agent_server_binding b
        INNER JOIN pem.agent a ON b.agent_id = a.id
        INNER JOIN pem.server s ON b.server_id = s.id
        LEFT JOIN pemdata.server_info sd ON b.server_id = sd.server_id
        LEFT JOIN pem.probe_server_version psv ON p.id = psv.probe_id AND sd.server_version_id = psv.server_version_id
        INNER JOIN pemdata.oc_database ocd ON b.server_id = ocd.server_id
        INNER JOIN pemdata.oc_schema oc ON ocd.server_id = oc.server_id AND ocd.database_name = oc.database_name
        LEFT JOIN pem.probe_config_schema c ON p.id = c.probe_id AND b.server_id = c.server_id AND oc.database_name = c.database_name AND oc.schema_name = c.schema_name
        LEFT JOIN pem.profile_probe_configs ppc ON s.profile_id = ppc.profile_id AND p.id = ppc.probe_id
    WHERE
        p.target_type_id = 400 AND NOT p.deleted
        AND ocd.connections_allowed
        AND (p.agent_capability IS NULL OR p.agent_capability = ANY(a.agent_capability_list))
        AND (p.any_server_version OR psv.probe_id IS NOT NULL)
        AND (p.collection_method != 'b' OR (p.collection_method ='b' AND (a.agent_capability_list @> ARRAY['allow_batch_probes'])
                AND ((strpos(a.platform, p.platform) != 0) OR (a.platform !~ 'windows' AND p.platform = 'unix'))))
        AND oc.database_name NOT IN (SELECT UNNEST(b.exclude_databases))
    UNION ALL
    -- Block 5: Table Probes
    SELECT
        p.id AS probe_id, p.display_name AS probe_display_name,
        p.internal_name AS probe_internal_name, p.probe_key_list,
        p.applies_to_id,
        a.id AS agent_id, b.server_id, oc.database_name AS database_name,
        ARRAY['server_id', 'database_name', 'schema_name', 'table_name']::text[] AS parameter_name_list,
        ARRAY[b.server_id::text, oc.database_name, oc.schema_name, oc.table_name]::text[] AS parameter_value_list,
        p.collection_method,
        COALESCE(NULLIF(TRIM(psv.probe_code), ''), p.probe_code) AS probe_code,
        p.enabled_by_default, p.default_execution_frequency,
        p.default_lifetime,
        COALESCE(ppc.enabled, c.enabled, p.enabled_by_default) AS enabled,
        COALESCE(ppc.execution_frequency, c.execution_frequency, p.default_execution_frequency) AS execution_frequency,
        COALESCE(ppc.lifetime, c.lifetime, p.default_lifetime) AS lifetime,
        a.active AS agent_active,
        p.discard_history,
        p.is_system_probe
    FROM
        pem.probe p
        CROSS JOIN pem.agent_server_binding b
        INNER JOIN pem.agent a ON b.agent_id = a.id
        INNER JOIN pem.server s ON b.server_id = s.id
        LEFT JOIN pemdata.server_info sd ON b.server_id = sd.server_id
        LEFT JOIN pem.probe_server_version psv ON p.id = psv.probe_id AND sd.server_version_id = psv.server_version_id
        INNER JOIN pemdata.oc_database ocd ON b.server_id = ocd.server_id
        INNER JOIN pemdata.oc_table oc ON ocd.server_id = oc.server_id AND ocd.database_name = oc.database_name
        LEFT JOIN pem.probe_config_table c ON p.id = c.probe_id AND b.server_id = c.server_id AND oc.database_name = c.database_name AND oc.schema_name = c.schema_name AND oc.table_name = c.table_name
        LEFT JOIN pem.profile_probe_configs ppc ON s.profile_id = ppc.profile_id AND p.id = ppc.probe_id
    WHERE
        p.target_type_id = 500 AND NOT p.deleted
        AND ocd.connections_allowed
        AND (p.agent_capability IS NULL OR p.agent_capability = ANY(a.agent_capability_list))
        AND (p.any_server_version OR psv.probe_id IS NOT NULL)
        AND (p.collection_method != 'b' OR (p.collection_method ='b' AND (a.agent_capability_list @> ARRAY['allow_batch_probes'])
                AND ((strpos(a.platform, p.platform) != 0) OR (a.platform !~ 'windows' AND p.platform = 'unix'))))
        AND oc.database_name NOT IN (SELECT UNNEST(b.exclude_databases))
    UNION ALL
    -- Block 6: Index Probes
    SELECT
        p.id AS probe_id, p.display_name AS probe_display_name,
        p.internal_name AS probe_internal_name, p.probe_key_list,
        p.applies_to_id,
        a.id AS agent_id, b.server_id, oc.database_name AS database_name,
        ARRAY['server_id', 'database_name', 'schema_name', 'index_name']::text[] AS parameter_name_list,
        ARRAY[b.server_id::text, oc.database_name, oc.schema_name, oc.index_name]::text[] AS parameter_value_list,
        p.collection_method,
        COALESCE(NULLIF(TRIM(psv.probe_code), ''), p.probe_code) AS probe_code,
        p.enabled_by_default, p.default_execution_frequency,
        p.default_lifetime,
        COALESCE(ppc.enabled, c.enabled, p.enabled_by_default) AS enabled,
        COALESCE(ppc.execution_frequency, c.execution_frequency, p.default_execution_frequency) AS execution_frequency,
        COALESCE(ppc.lifetime, c.lifetime, p.default_lifetime) AS lifetime,
        a.active AS agent_active,
        p.discard_history,
        p.is_system_probe
    FROM
        pem.probe p
        CROSS JOIN pem.agent_server_binding b
        INNER JOIN pem.agent a ON b.agent_id = a.id
        INNER JOIN pem.server s ON b.server_id = s.id
        LEFT JOIN pemdata.server_info sd ON b.server_id = sd.server_id
        LEFT JOIN pem.probe_server_version psv ON p.id = psv.probe_id AND sd.server_version_id = psv.server_version_id
        INNER JOIN pemdata.oc_database ocd ON b.server_id = ocd.server_id
        INNER JOIN pemdata.oc_index oc ON ocd.server_id = oc.server_id AND ocd.database_name = oc.database_name
        LEFT JOIN pem.probe_config_index c ON p.id = c.probe_id AND b.server_id = c.server_id AND oc.database_name = c.database_name AND oc.schema_name = c.schema_name AND oc.index_name = c.index_name
        LEFT JOIN pem.profile_probe_configs ppc ON s.profile_id = ppc.profile_id AND p.id = ppc.probe_id
    WHERE
        p.target_type_id = 600 AND NOT p.deleted
        AND ocd.connections_allowed
        AND (p.agent_capability IS NULL OR p.agent_capability = ANY(a.agent_capability_list))
        AND (p.any_server_version OR psv.probe_id IS NOT NULL)
        AND (p.collection_method != 'b' OR (p.collection_method ='b' AND (a.agent_capability_list @> ARRAY['allow_batch_probes'])
                AND ((strpos(a.platform, p.platform) != 0) OR (a.platform !~ 'windows' AND p.platform = 'unix'))))
        AND oc.database_name NOT IN (SELECT UNNEST(b.exclude_databases))
    UNION ALL
    -- Block 7: Sequence Probes
    SELECT
        p.id AS probe_id, p.display_name AS probe_display_name,
        p.internal_name AS probe_internal_name, p.probe_key_list,
        p.applies_to_id,
        a.id AS agent_id, b.server_id, oc.database_name AS database_name,
        ARRAY['server_id', 'database_name', 'schema_name', 'sequence_name']::text[] AS parameter_name_list,
        ARRAY[b.server_id::text, oc.database_name, oc.schema_name, oc.sequence_name]::text[] AS parameter_value_list,
        p.collection_method,
        COALESCE(NULLIF(TRIM(psv.probe_code), ''), p.probe_code) AS probe_code,
        p.enabled_by_default, p.default_execution_frequency,
        p.default_lifetime,
        COALESCE(ppc.enabled, c.enabled, p.enabled_by_default) AS enabled,
        COALESCE(ppc.execution_frequency, c.execution_frequency, p.default_execution_frequency) AS execution_frequency,
        COALESCE(ppc.lifetime, c.lifetime, p.default_lifetime) AS lifetime,
        a.active AS agent_active,
        p.discard_history,
        p.is_system_probe
    FROM
        pem.probe p
        CROSS JOIN pem.agent_server_binding b
        INNER JOIN pem.agent a ON b.agent_id = a.id
        INNER JOIN pem.server s ON b.server_id = s.id
        LEFT JOIN pemdata.server_info sd ON b.server_id = sd.server_id
        LEFT JOIN pem.probe_server_version psv ON p.id = psv.probe_id AND sd.server_version_id = psv.server_version_id
        INNER JOIN pemdata.oc_database ocd ON b.server_id = ocd.server_id
        INNER JOIN pemdata.oc_sequence oc ON ocd.server_id = oc.server_id AND ocd.database_name = oc.database_name
        LEFT JOIN pem.probe_config_sequence c ON p.id = c.probe_id AND b.server_id = c.server_id AND oc.database_name = c.database_name AND oc.schema_name = c.schema_name AND oc.sequence_name = c.sequence_name
        LEFT JOIN pem.profile_probe_configs ppc ON s.profile_id = ppc.profile_id AND p.id = ppc.probe_id
    WHERE
        p.target_type_id = 700 AND NOT p.deleted
        AND ocd.connections_allowed
        AND (p.agent_capability IS NULL OR p.agent_capability = ANY(a.agent_capability_list))
        AND (p.any_server_version OR psv.probe_id IS NOT NULL)
        AND (p.collection_method != 'b' OR (p.collection_method ='b' AND (a.agent_capability_list @> ARRAY['allow_batch_probes'])
                AND ((strpos(a.platform, p.platform) != 0) OR (a.platform !~ 'windows' AND p.platform = 'unix'))))
        AND oc.database_name NOT IN (SELECT UNNEST(b.exclude_databases))
    UNION ALL
    -- Block 8: Function Probes
    SELECT
        p.id AS probe_id, p.display_name AS probe_display_name,
        p.internal_name AS probe_internal_name, p.probe_key_list,
        p.applies_to_id,
        a.id AS agent_id, b.server_id, oc.database_name AS database_name,
        ARRAY['server_id', 'database_name', 'schema_name', 'function_name']::text[] AS parameter_name_list,
        ARRAY[b.server_id::text, oc.database_name, oc.schema_name, oc.function_name]::text[] AS parameter_value_list,
        p.collection_method,
        COALESCE(NULLIF(TRIM(psv.probe_code), ''), p.probe_code) AS probe_code,
        p.enabled_by_default, p.default_execution_frequency,
        p.default_lifetime,
        COALESCE(ppc.enabled, c.enabled, p.enabled_by_default) AS enabled,
        COALESCE(ppc.execution_frequency, c.execution_frequency, p.default_execution_frequency) AS execution_frequency,
        COALESCE(ppc.lifetime, c.lifetime, p.default_lifetime) AS lifetime,
        a.active AS agent_active,
        p.discard_history,
        p.is_system_probe
    FROM
        pem.probe p
        CROSS JOIN pem.agent_server_binding b
        INNER JOIN pem.agent a ON b.agent_id = a.id
        INNER JOIN pem.server s ON b.server_id = s.id
        LEFT JOIN pemdata.server_info sd ON b.server_id = sd.server_id
        LEFT JOIN pem.probe_server_version psv ON p.id = psv.probe_id AND sd.server_version_id = psv.server_version_id
        INNER JOIN pemdata.oc_database ocd ON b.server_id = ocd.server_id
        INNER JOIN pemdata.oc_function oc ON ocd.server_id = oc.server_id AND ocd.database_name = oc.database_name
        LEFT JOIN pem.probe_config_function c ON p.id = c.probe_id AND b.server_id = c.server_id AND oc.database_name = c.database_name AND oc.schema_name = c.schema_name AND oc.function_name = c.function_name
        LEFT JOIN pem.profile_probe_configs ppc ON s.profile_id = ppc.profile_id AND p.id = ppc.probe_id
    WHERE
        p.target_type_id = 800 AND NOT p.deleted
        AND ocd.connections_allowed
        AND (p.agent_capability IS NULL OR p.agent_capability = ANY(a.agent_capability_list))
        AND (p.any_server_version OR psv.probe_id IS NOT NULL)
        AND (p.collection_method != 'b' OR (p.collection_method ='b' AND (a.agent_capability_list @> ARRAY['allow_batch_probes'])
                AND ((strpos(a.platform, p.platform) != 0) OR (a.platform !~ 'windows' AND p.platform = 'unix'))))
        AND oc.database_name NOT IN (SELECT UNNEST(b.exclude_databases))
    UNION ALL
    -- Block 9: View Probes
    SELECT
        p.id AS probe_id, p.display_name AS probe_display_name,
        p.internal_name AS probe_internal_name, p.probe_key_list,
        p.applies_to_id,
        a.id AS agent_id, b.server_id, oc.database_name AS database_name,
        ARRAY['server_id', 'database_name', 'schema_name', 'view_name']::text[] AS parameter_name_list,
        ARRAY[b.server_id::text, oc.database_name, oc.schema_name, oc.view_name]::text[] AS parameter_value_list,
        p.collection_method,
        COALESCE(NULLIF(TRIM(psv.probe_code), ''), p.probe_code) AS probe_code,
        p.enabled_by_default, p.default_execution_frequency,
        p.default_lifetime,
        COALESCE(ppc.enabled, c.enabled, p.enabled_by_default) AS enabled,
        COALESCE(ppc.execution_frequency, c.execution_frequency, p.default_execution_frequency) AS execution_frequency,
        COALESCE(ppc.lifetime, c.lifetime, p.default_lifetime) AS lifetime,
        a.active AS agent_active,
        p.discard_history,
        p.is_system_probe
    FROM
        pem.probe p
        CROSS JOIN pem.agent_server_binding b
        INNER JOIN pem.agent a ON b.agent_id = a.id
        INNER JOIN pem.server s ON b.server_id = s.id
        LEFT JOIN pemdata.server_info sd ON b.server_id = sd.server_id
        LEFT JOIN pem.probe_server_version psv ON p.id = psv.probe_id AND sd.server_version_id = psv.server_version_id
        INNER JOIN pemdata.oc_database ocd ON b.server_id = ocd.server_id
        INNER JOIN pemdata.oc_views oc ON ocd.server_id = oc.server_id AND ocd.database_name = oc.database_name
        LEFT JOIN pem.probe_config_view c ON p.id = c.probe_id AND b.server_id = c.server_id AND oc.database_name = c.database_name AND oc.schema_name = c.schema_name AND oc.view_name = c.view_name
        LEFT JOIN pem.profile_probe_configs ppc ON s.profile_id = ppc.profile_id AND p.id = ppc.probe_id
    WHERE
        p.target_type_id = 900 AND NOT p.deleted
        AND ocd.connections_allowed
        AND (p.agent_capability IS NULL OR p.agent_capability = ANY(a.agent_capability_list))
        AND (p.any_server_version OR psv.probe_id IS NOT NULL)
        AND (p.collection_method != 'b' OR (p.collection_method ='b' AND (a.agent_capability_list @> ARRAY['allow_batch_probes'])
                AND ((strpos(a.platform, p.platform) != 0) OR (a.platform !~ 'windows' AND p.platform = 'unix'))))
        AND oc.database_name NOT IN (SELECT UNNEST(b.exclude_databases))
    UNION ALL
    -- Block 10: Extension Probes
    SELECT *
    FROM pem.probe_target_extension_view
    UNION ALL
    -- Block 11: Tool Probes
    SELECT *
    FROM pem.probe_target_tool_view;

    REFRESH MATERIALIZED VIEW pem.probe_target_view;

    -- Recreating probe_schedule_view as it gets deleted due
    -- to drop cascade on pem.probe_target_view
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


    CREATE OR REPLACE FUNCTION pem.refresh_stale_probe_view()
    RETURNS void
    LANGUAGE plpgsql
    SECURITY DEFINER
    SET search_path = pem, pg_catalog
    AS $$
    DECLARE
        v_last_refreshed timestamptz;
        v_update_required timestamptz;
    BEGIN
        -- Lock the tracking row for 'probe_target_view' to prevent
        -- concurrent refresh jobs from running.
        SELECT last_refreshed, update_required
        INTO v_last_refreshed, v_update_required
        FROM pem.refresh_materialized_view
        WHERE view_name = 'probe_target_view'
        FOR UPDATE;

        -- Refresh if EITHER a change was flagged OR it's been an hour
        IF (v_update_required > v_last_refreshed) OR 
        (now() - v_last_refreshed > interval '1 hour') 
        THEN
            
            -- The view is stale or the safety net is triggered, so refresh
            REFRESH MATERIALIZED VIEW pem.probe_target_view;
            
            -- Update the 'last_refreshed' timestamp to now.
            -- Any triggers that fire during the refresh will wait for
            -- this transaction to commit, then set the 'update_required'
            -- flag, ensuring the change is picked up on the next run.
            UPDATE pem.refresh_materialized_view
            SET last_refreshed = now()
            WHERE view_name = 'probe_target_view';
            
        END IF;

        -- The transaction commits, releasing the lock.
    END;
    $$;

    -- ==========================================================
    -- Function: pem.create_pem_server_system_tasks_refresh_probe_view
    -- Description:
    -- Creates a job that periodically refreshes the
    -- pem.probe_target_view materialized view. This job ensures
    -- that probe configurations are updated for background
    -- changes (e.g., agent-discovered databases, manual DBA
    -- changes).
    -- ==========================================================
    CREATE OR REPLACE FUNCTION pem.create_pem_server_system_tasks_refresh_probe_view(
        p_agent_id integer,
        p_server_id integer,
        p_database text,
        p_is_leader boolean
    )
        RETURNS void AS
    $FUNC$
    BEGIN
        -- JOB: Refresh Probe Target Materialized View
        PERFORM pem.create_or_update_system_job_with_a_step_and_schedule(
            p_agent_id, p_server_id, p_database,
            -- Job name
            'Refresh Stale Materialized Views',
            -- Job description
            'This job checks a flag table every minute and refreshes the pem.probe_target_view materialized view if it is stale or if it has not been refreshed in one hour.',
            -- Step name
            'Check and Refresh probe_target_view',
            -- Step description
            'This job step calls pem.refresh_stale_probe_view() to refresh the view if needed.',
            's',
            'SELECT pem.refresh_stale_probe_view();',
            p_is_leader, TRUE,
            -- Schedule name
            'Refresh Stale Views (Every Minute)',
            -- Schedule description
            'This job runs every minute to check for and refresh stale materialized views.',
            -- scminutes: Run every minute
            '{t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t}',
            -- schours: Run every hour
            '{t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t}'
        );
    END
    $FUNC$ LANGUAGE 'plpgsql';

    DO $$
    DECLARE
        rec RECORD;
    BEGIN
        FOR rec IN SELECT * FROM pem.pem_host_and_server
        LOOP
            PERFORM pem.create_pem_server_system_tasks_refresh_probe_view(
                rec.agent_id,
                rec.server_id,
                rec.database,
                rec.is_leader
            );
        END LOOP;
    END
    $$;

    -- Function to flag materialized view for refresh
    CREATE TABLE IF NOT EXISTS pem.refresh_materialized_view (
        view_name text PRIMARY KEY,
        last_refreshed timestamptz NOT NULL DEFAULT '1970-01-01 00:00:00 UTC',
        update_required timestamptz NOT NULL DEFAULT '1970-01-01 00:00:00 UTC'
    );

    -- Insert the row for our view, if it doesn't exist
    INSERT INTO pem.refresh_materialized_view (view_name)
    VALUES ('probe_target_view')
    ON CONFLICT (view_name) DO NOTHING;

    -- Function to flag materialized view for refresh
    CREATE OR REPLACE FUNCTION pem.flag_mv_refresh()
    RETURNS TRIGGER
    SECURITY DEFINER
    AS $$
    BEGIN
        -- Update the timestamp to flag that this view is now stale
        UPDATE pem.refresh_materialized_view
        SET update_required = now()
        WHERE view_name = 'probe_target_view';

        UPDATE pem.job SET jobnextrun=now() 
        where jobname='Refresh Stale Materialized Views' and issystemjob;

        RETURN NULL; -- Result is ignored since this is an AFTER trigger
    END;
    $$ LANGUAGE plpgsql;

    -- Triggers for manual config (agent, server, tool) - drop then create
    DROP TRIGGER IF EXISTS trg_agent_flag_mv ON pem.agent;
    CREATE TRIGGER trg_agent_flag_mv
        AFTER UPDATE OR INSERT OR DELETE ON pem.agent
        FOR EACH STATEMENT EXECUTE PROCEDURE pem.flag_mv_refresh();

    DROP TRIGGER IF EXISTS trg_server_flag_mv ON pem.server;
    CREATE TRIGGER trg_server_flag_mv
        AFTER UPDATE OF profile_id ON pem.server
        FOR EACH STATEMENT EXECUTE PROCEDURE pem.flag_mv_refresh();

    DROP TRIGGER IF EXISTS trg_tool_flag_mv ON pem.tool;
    CREATE TRIGGER trg_tool_flag_mv
        AFTER INSERT OR DELETE ON pem.tool
        FOR EACH STATEMENT EXECUTE PROCEDURE pem.flag_mv_refresh();

    -- Triggers for probe configuration tables - drop then create
    DROP TRIGGER IF EXISTS trg_probe_flag_mv ON pem.probe;
    CREATE TRIGGER trg_probe_flag_mv
        AFTER INSERT OR UPDATE OR DELETE ON pem.probe
        FOR EACH STATEMENT EXECUTE PROCEDURE pem.flag_mv_refresh();

    DROP TRIGGER IF EXISTS trg_profile_probe_configs_flag_mv ON pem.profile_probe_configs;
    CREATE TRIGGER trg_profile_probe_configs_flag_mv
        AFTER INSERT OR UPDATE OR DELETE ON pem.profile_probe_configs
        FOR EACH STATEMENT EXECUTE PROCEDURE pem.flag_mv_refresh();

    DROP TRIGGER IF EXISTS trg_probe_config_agent_flag_mv ON pem.probe_config_agent;
    CREATE TRIGGER trg_probe_config_agent_flag_mv
        AFTER INSERT OR UPDATE OR DELETE ON pem.probe_config_agent
        FOR EACH STATEMENT EXECUTE PROCEDURE pem.flag_mv_refresh();

    DROP TRIGGER IF EXISTS trg_probe_config_server_flag_mv ON pem.probe_config_server;
    CREATE TRIGGER trg_probe_config_server_flag_mv
        AFTER INSERT OR UPDATE OR DELETE ON pem.probe_config_server
        FOR EACH STATEMENT EXECUTE PROCEDURE pem.flag_mv_refresh();

    DROP TRIGGER IF EXISTS trg_probe_config_db_flag_mv ON pem.probe_config_database;
    CREATE TRIGGER trg_probe_config_db_flag_mv
        AFTER INSERT OR UPDATE OR DELETE ON pem.probe_config_database
        FOR EACH STATEMENT EXECUTE PROCEDURE pem.flag_mv_refresh();

    DROP TRIGGER IF EXISTS trg_probe_config_schema_flag_mv ON pem.probe_config_schema;
    CREATE TRIGGER trg_probe_config_schema_flag_mv
        AFTER INSERT OR UPDATE OR DELETE ON pem.probe_config_schema
        FOR EACH STATEMENT EXECUTE PROCEDURE pem.flag_mv_refresh();

    DROP TRIGGER IF EXISTS trg_probe_config_extension_flag_mv ON pem.probe_config_extension;
    CREATE TRIGGER trg_probe_config_extension_flag_mv
        AFTER INSERT OR UPDATE OR DELETE ON pem.probe_config_extension
        FOR EACH STATEMENT EXECUTE PROCEDURE pem.flag_mv_refresh();

    DROP TRIGGER IF EXISTS trg_agent_server_binding_flag_mv ON pem.agent_server_binding;
    CREATE TRIGGER trg_agent_server_binding_flag_mv
        AFTER INSERT OR UPDATE OR DELETE ON pem.agent_server_binding
        FOR EACH STATEMENT EXECUTE PROCEDURE pem.flag_mv_refresh();


    -- Triggers for agent-discovered data - drop then create
    DROP TRIGGER IF EXISTS trg_oc_database_flag_mv ON pemdata.oc_database;
    CREATE TRIGGER trg_oc_database_flag_mv
        AFTER INSERT OR UPDATE OR DELETE ON pemdata.oc_database
        FOR EACH STATEMENT EXECUTE PROCEDURE pem.flag_mv_refresh();

    DROP TRIGGER IF EXISTS trg_oc_schema_flag_mv ON pemdata.oc_schema;
    CREATE TRIGGER trg_oc_schema_flag_mv
        AFTER INSERT OR UPDATE OR DELETE ON pemdata.oc_schema
        FOR EACH STATEMENT EXECUTE PROCEDURE pem.flag_mv_refresh();

    DROP TRIGGER IF EXISTS trg_oc_extension_flag_mv ON pemdata.oc_extension;
    CREATE TRIGGER trg_oc_extension_flag_mv
        AFTER INSERT OR UPDATE OR DELETE ON pemdata.oc_extension
        FOR EACH STATEMENT EXECUTE PROCEDURE pem.flag_mv_refresh();

    DROP TRIGGER IF EXISTS trg_server_info_flag_mv ON pemdata.server_info;
    CREATE TRIGGER trg_server_info_flag_mv
        AFTER INSERT OR UPDATE OR DELETE ON pemdata.server_info
        FOR EACH STATEMENT EXECUTE PROCEDURE pem.flag_mv_refresh();

    -- PEM-5759 Implement Event History Tracking for Manage Profile
    CREATE OR REPLACE FUNCTION pem.log_profile_assignment_change()
    RETURNS trigger
    AS $$
    DECLARE
        v_old_profile_id integer;
        v_new_profile_id integer;
        v_operation text;
        v_changed_categories text[];
        v_target_type text;
        v_payload jsonb;
        v_user text;
    BEGIN
        -- Only act if profile_id actually changed (including NULL transitions)
        v_old_profile_id := OLD.profile_id;
        v_new_profile_id := NEW.profile_id;
        IF v_old_profile_id IS NOT DISTINCT FROM v_new_profile_id THEN
            RETURN NEW; -- No change, skip
        END IF;

        -- Determine target type based on relname
        IF TG_TABLE_NAME = 'server' THEN
            v_target_type := 'server';
        ELSIF TG_TABLE_NAME = 'agent' THEN
            v_target_type := 'agent';
        ELSE
            v_target_type := TG_TABLE_NAME; -- fallback
        END IF;

        -- Classify operation and categories
        IF v_old_profile_id IS NULL AND v_new_profile_id IS NOT NULL THEN
            v_operation := 'assign';
            v_changed_categories := ARRAY['assigned_profile'];
        ELSIF v_old_profile_id IS NOT NULL AND v_new_profile_id IS NULL THEN
            v_operation := 'unassign';
            v_changed_categories := ARRAY['unassigned_profile'];
        ELSE
            v_operation := 'reassign';
            v_changed_categories := ARRAY['reassigned_profile'];
        END IF;

        -- Capture user identification (DB session user)
        SELECT current_user INTO v_user;

        v_payload := jsonb_build_object(
            'ProfileId', v_new_profile_id,
            'PreviousProfileId', v_old_profile_id,
            'ChangedCategories', v_changed_categories,
            CASE WHEN v_target_type = 'server' THEN 'ServerId' ELSE 'AgentId' END,
            NEW.id,
            'TargetType', v_target_type
        );

        INSERT INTO pem.event_history (recorded_time, user_name, component, operation, message, details)
        VALUES (
            current_timestamp,
            v_user,
            'profile',
            v_operation,
            format('%s profile %s %s %s', initcap(v_operation), COALESCE(v_new_profile_id::text, 'NULL'), 'on', v_target_type || ' ' || NEW.id),
            v_payload::text
        );

        RETURN NEW;
    END;
    $$ LANGUAGE plpgsql;

    -- Triggers
    DROP TRIGGER IF EXISTS trg_profile_assignment_server ON pem.server;
    CREATE TRIGGER trg_profile_assignment_server
    AFTER INSERT OR UPDATE OF profile_id ON pem.server
    FOR EACH ROW EXECUTE FUNCTION pem.log_profile_assignment_change();

    DROP TRIGGER IF EXISTS trg_profile_assignment_agent ON pem.agent;
    CREATE TRIGGER trg_profile_assignment_agent
    AFTER INSERT OR UPDATE OF profile_id ON pem.agent
    FOR EACH ROW EXECUTE FUNCTION pem.log_profile_assignment_change();

    -- PEM-5128: Enable Barman probes by default
    UPDATE pem.probe
    SET enabled_by_default=true, force_enabled=true
    WHERE internal_name IN ('barman_config', 'barman_info', 'barman_server', 'barman_server_status', 'barman_server_backup', 'barman_server_wal_status');

    -- PEM-5730: Adding EFM builtin alerts
    -- Creating the EFM Agent down alert template
    DO $$
        BEGIN
          IF NOT EXISTS (SELECT 1 FROM pem.alert_template WHERE display_name = 'EFM Agent Down' AND is_system_template) THEN
            PERFORM pem.create_alert_template(
              'EFM Agent Down',
              'EFM service is down',
              $sql$
                SELECT
                    CASE WHEN efm_running IS FALSE THEN 1 ELSE 0 END AS current_value,
                    CASE WHEN efm_running IS FALSE THEN 'DOWN' ELSE 'UP' END AS display_value
                FROM
                    pemdata.efm_cluster_info
                WHERE
                    server_id = ${server_id};
              $sql$,
              200,  -- object_type: server
              NULL, NULL, NULL, 'STATE',
              '{efm_cluster_info}',
              (SELECT COALESCE(MAX(snmp_oid), 0) + 1 FROM pem.alert_template WHERE object_type = 200),
              'ALL',
              1,  -- alert level
              30, -- frequency
              true,
              $sql$
                SELECT efm_messages FROM pemdata.efm_cluster_info where server_id = ${server_id} and efm_running is false;
              $sql$
            );
          END IF;
        END;
    $$ LANGUAGE 'plpgsql';

    -- Creating the EFM Missing Primary Agent alert template
    DO $$
        BEGIN
          IF NOT EXISTS (SELECT 1 FROM pem.alert_template WHERE display_name = 'EFM Missing Primary' AND is_system_template) THEN
            PERFORM pem.create_alert_template(
              'EFM Missing Primary',
              'EFM cluster is missing the primary node',
              $sql$
                WITH missing_primary AS (
                    SELECT NOT EXISTS (
                        SELECT 1
                        FROM pemdata.efm_cluster_node_status
                        WHERE server_id = ${server_id}
                          AND efm_agent_type = 'Primary'
                    ) AS is_missing
                )
                SELECT
                    CASE
                        WHEN is_missing THEN 1
                        ELSE 0
                    END AS current_value,
                    CASE
                        WHEN is_missing THEN 'No Primary'
                        ELSE 'PRESENT'
                    END AS display_value
                FROM missing_primary;
              $sql$,
              200,  -- object_type: server
              NULL, NULL, NULL, 'STATE',
              '{efm_cluster_node_status}',
              (SELECT COALESCE(MAX(snmp_oid), 0) + 1 FROM pem.alert_template WHERE object_type = 200),
              'ALL',
              1,  -- alert level
              30, -- frequency
              true
            );
          END IF;
        END;
    $$ LANGUAGE 'plpgsql';

    -- Creating the EFM fewer than N nodes activet alert template
    DO $$
        BEGIN
          IF NOT EXISTS (SELECT 1 FROM pem.alert_template WHERE display_name = 'EFM Fewer Than N Nodes Active' AND is_system_template) THEN
            PERFORM pem.create_alert_template(
                'EFM fewer than N nodes active',
                'Triggers when the number of active EFM nodes in a cluster falls below the expected threshold.',
                $sql$
                    SELECT
                        CASE
                        WHEN total_nodes < ${param_1} THEN 1
                        ELSE 0
                        END AS current_value,
                        total_nodes::text AS display_value
                        FROM (
                            SELECT
                                COUNT(*) FILTER (
                            WHERE efm_db_status = 'UP'
                            OR efm_agent_type = 'Witness'
                        ) AS total_nodes
                    FROM pemdata.efm_cluster_node_status
                    WHERE server_id = ${server_id}
                    ) AS t;
                $sql$,
                200, '{Number of required nodes}', '{INTEGER}', '{#}', '#','{efm_cluster_node_status}',
                (SELECT CASE WHEN MAX(snmp_oid) > 0 THEN MAX(snmp_oid) + 1 ELSE 1 END FROM pem.alert_template WHERE object_type = 200), 'ALL',
                info_sql :=$SQL$
                SELECT
                    efm_ip_address AS "EFM IP Address",
                    efm_agent_type AS "EFM Agent Type",
                    efm_db_status AS "EFM DB Status",
                    efm_xlog_info AS "EFM XLOG Info"
                FROM pemdata.efm_cluster_node_status
                WHERE server_id='${server_id}'::integer
                $SQL$);
          END IF;
        END;
    $$ LANGUAGE 'plpgsql';

        -- PEM-5832 : added role to manage privileges on profiles
    DO $$
    BEGIN
        -- Safely revoke old permissions
        BEGIN
            REVOKE pem_config_probe FROM pem_config;
            REVOKE pem_config_alert FROM pem_config;
        EXCEPTION
            WHEN undefined_object THEN
                RAISE NOTICE 'One or more roles/grants did not exist, skipping revocation.';
        END;

        -- Safely create the new role
        IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'pem_manage_profile') THEN
            
            PERFORM pem.create_role_for(
                'manage_profile',
                'Role to manage the profiles',
                ARRAY['pem_config'],
                '{}'::text[], '{}'::text[], '{}'::text[],
                ARRAY[
                    ARRAY['pem', 'profile'],
                    ARRAY['pem', 'profile_alert_configs'],
                    ARRAY['pem', 'profile_probe_configs'],
                    ARRAY['pem', 'event_history'],
                    ARRAY['pem', 'webhook_alert_config']
                ]
            );
        ELSE
            RAISE NOTICE 'Role pem_manage_profile already exists, skipping creation.';
        END IF;

        -- Grant permissions to the new role
        GRANT pem_config_probe TO pem_manage_profile;
        GRANT pem_config_alert TO pem_manage_profile;
    END;
    $$ LANGUAGE 'plpgsql';


    -- PEM-5744: Updating the probe PGD Conflict History Summary, to fix the type case issue in column conflict_recorded
    UPDATE pem.probe
    SET
        probe_code=$sql$select EXTRACT(EPOCH FROM date_trunc('hour', local_time))::bigint as conflict_recorded,
        conflict_type, count(*) as conflict_count
        from bdr.conflict_history_summary
        group by date_trunc('hour', local_time), conflict_type
        order by conflict_recorded, conflict_type;
		$sql$
	WHERE
	    internal_name='bdr_conflict_history_summary';

    -- PEM-5797-- changed logic to detect on basis of cluster and provided time window 
    -- for promotion around demotion time
    CREATE OR REPLACE FUNCTION pem.patroni_failover_info(
        p_server_id INT,
        p_interval_minutes INT
    )
    RETURNS TABLE (
        "Failover time" timestamptz,
        "Cluster type" TEXT,
        "Cluster name" TEXT,
        "Previous leader ip" TEXT,
        "Previous primary node" TEXT,
        "New leader ip" TEXT,
        "New primary node" TEXT
    ) AS $$
    DECLARE
        v_cluster_name TEXT;
        r_demotion RECORD;
        r_promotion RECORD;
    BEGIN
        -- Step 1: Find the cluster name using the provided server ID
        SELECT patroni_cluster_name
        INTO v_cluster_name
        FROM pem.server
        WHERE id = p_server_id;

        -- If no cluster name is found for this server ID, exit gracefully.
        IF v_cluster_name IS NULL THEN
            RETURN;
        END IF;

        -- Step 2: Find the most recent demotion in that cluster (Leader → non-Leader)
        SELECT
            recorded_time,
            (details::json->>'ClusterType') AS cluster_type,
            (details::json->>'ClusterName') AS cluster_name,
            (details::json->>'NodeIp')      AS old_ip,
            (details::json->>'NodeName')    AS old_node
        INTO r_demotion
        FROM pem.event_history
        WHERE component = 'HA Monitoring'
        AND operation = 'Switchover'
        AND (details::json->>'ClusterType') = 'patroni'
        AND (details::json->>'ClusterName') = v_cluster_name
        AND (details::json->>'OldRole') = 'Leader'
        AND (details::json->>'NewRole') IS DISTINCT FROM 'Leader'
        AND recorded_time >= now() - (p_interval_minutes || ' minutes')::interval
        ORDER BY recorded_time DESC
        LIMIT 1;

        -- If no demotion event was found, no failover occurred.
        IF r_demotion.recorded_time IS NULL THEN
            RETURN;
        END IF;

        -- Step 3: Find the corresponding promotion after the demotion (non-Leader → Leader)
        SELECT
            recorded_time,
            (details::json->>'NodeIp')   AS new_ip,
            (details::json->>'NodeName') AS new_node
        INTO r_promotion
        FROM pem.event_history
        WHERE component = 'HA Monitoring'
        AND operation = 'Switchover'
        AND (details::json->>'ClusterType') = 'patroni'
        AND (details::json->>'ClusterName') = v_cluster_name
        AND (details::json->>'NewRole') = 'Leader'
        AND (details::json->>'OldRole') IS DISTINCT FROM 'Leader'
        AND recorded_time BETWEEN (r_demotion.recorded_time - '30 seconds'::interval)
                                AND (r_demotion.recorded_time + '30 seconds'::interval)
        ORDER BY recorded_time
        LIMIT 1;

        -- Step 4: If a matching promotion was found, return the consolidated failover info
        IF r_promotion.new_ip IS NOT NULL THEN
            "Failover time"         := r_demotion.recorded_time;
            "Cluster type"          := r_demotion.cluster_type;
            "Cluster name"          := r_demotion.cluster_name;
            "Previous leader ip"    := r_demotion.old_ip;
            "Previous primary node" := r_demotion.old_node;
            "New leader ip"         := r_promotion.new_ip;
            "New primary node"      := r_promotion.new_node;
            RETURN NEXT;
        END IF;
    END;
    $$ LANGUAGE plpgsql STABLE;

    CREATE OR REPLACE FUNCTION pem.efm_failover_info(
        p_server_id INT,
        p_interval_minutes INT
    )
    RETURNS TABLE (
        "Failover time" timestamptz,
        "Cluster type" TEXT,
        "Cluster name" TEXT,
        "Previous primary ip" TEXT,
        "New primary ip" TEXT
    ) AS $$
    DECLARE
        v_cluster_name TEXT;
        r_demotion RECORD;
        r_promotion RECORD;
    BEGIN
        -- Step 1: Find the cluster name from the server ID
        -- (This is the fix for the ServerId problem)
        SELECT efm_cluster_name
        INTO v_cluster_name
        FROM pem.server
        WHERE id = p_server_id;

        -- If no cluster name, exit
        IF v_cluster_name IS NULL THEN
            RETURN;
        END IF;

        -- Step 2: Find the latest demotion in that cluster
        SELECT
            recorded_time,
            (details::json->>'ClusterType') AS cluster_type,
            (details::json->>'ClusterName') AS cluster_name,
            (details::json->>'NodeIp')      AS old_ip
        INTO r_demotion
        FROM pem.event_history
        WHERE component = 'HA Monitoring'
        AND operation = 'Switchover'
        AND (details::json->>'ClusterName') = v_cluster_name
        AND (details::json->>'OldAgentType') = 'Primary'
        AND (details::json->>'NewAgentType') IS DISTINCT FROM 'Primary'
        AND recorded_time >= now() - (p_interval_minutes || ' minutes')::interval
        ORDER BY recorded_time DESC
        LIMIT 1;

        IF r_demotion.recorded_time IS NULL THEN
            RETURN;
        END IF;

        -- Step 3: Find the matching promotion in that cluster
        -- (This is the fix for the time logic problem)
        SELECT
            recorded_time,
            (details::json->>'NodeIp') AS new_ip
        INTO r_promotion
        FROM pem.event_history
        WHERE component = 'HA Monitoring'
        AND operation = 'Switchover'
        AND (details::json->>'ClusterName') = v_cluster_name
        AND (details::json->>'NewAgentType') = 'Primary'
        AND (details::json->>'OldAgentType') IS DISTINCT FROM 'Primary'
        AND recorded_time BETWEEN (r_demotion.recorded_time - '30 seconds'::interval)
                                AND (r_demotion.recorded_time + '30 seconds'::interval)
        ORDER BY recorded_time
        LIMIT 1;

        -- Step 4: Return the result
        IF r_promotion.new_ip IS NOT NULL THEN
            "Failover time"         := r_demotion.recorded_time;
            "Cluster type"          := r_demotion.cluster_type;
            "Cluster name"          := r_demotion.cluster_name;
            "Previous primary ip"   := r_demotion.old_ip;
            "New primary ip"        := r_promotion.new_ip;
            RETURN NEXT;
        END IF;
    END;
    $$ LANGUAGE plpgsql STABLE;

    CREATE OR REPLACE FUNCTION pem.register_pem_server(integer)
    RETURNS void AS
    $FUNC$
    DECLARE
        agent_id integer := NULL;
    BEGIN
        SELECT asb.agent_id FROM pem.agent_server_binding asb WHERE asb.server_id = $1 INTO agent_id;

        IF NOT FOUND THEN
            RAISE EXCEPTION 'Server (%) is not bound to any agent, it can not be registered as a PEM server', $1;
        END IF;

        IF EXISTS (
            SELECT 1 FROM pem.pem_host_and_server WHERE server_id = $1
        ) THEN
            RAISE INFO 'Server (%) is already registerd as a PEM backend server!', $1;
            RETURN;
        END IF;

        INSERT INTO pem.pem_host_and_server (agent_id, server_id, database)  VALUES (agent_id, $1, current_database());

        -- Flag and refresh the probe target materialized view so that any
        -- newly registered server's applicable probes can be scheduled immediately.
        -- This is safe even if discovery (oc_* tables) hasn't finished yet; a later
        -- trigger will mark it stale again when those rows arrive.
        UPDATE pem.refresh_materialized_view
        SET update_required = now()
        WHERE view_name = 'probe_target_view';
        PERFORM pem.refresh_stale_probe_view();
    END
    $FUNC$ LANGUAGE 'plpgsql';

    -- PEM-5845: Creation of auto-create alert templates should add alerts to profile managed 
    -- server/agent and should be added in profile alerts as well
    CREATE OR REPLACE FUNCTION pem.alert_template_postupdate() RETURNS trigger AS $$
    BEGIN
        UPDATE pem.alert SET error_message = '' WHERE template_id = NEW.id;
        IF NEW.is_auto_create AND OLD.is_auto_create <> NEW.is_auto_create THEN
            -- Newly marked as auto-create: ensure template is present in all published profiles
            -- (Published and draft profiles inherit auto-create templates.)
            IF NEW.object_type IN (100,200) THEN
            INSERT INTO pem.profile_alert_configs (
                profile_id, template_id, name, params, operator, thresholds, check_frequency,
                history_retention, enabled, email_group_id, send_email, send_trap, snmp_trap_version,
                low_send_trap, low_email_group_id, med_send_trap, med_email_group_id, high_send_trap,
                high_email_group_id, execute_script, execute_script_on_clear, execute_script_on_pem_server,
                script_code, submit_to_nagios, cleared_alert_enable
            )
            SELECT p.id, NEW.id, NEW.display_name, '{}'::text[], NEW.operator, NEW.thresholds,
                NEW.default_check_frequency, NEW.default_history_retention, TRUE,
                NULL, FALSE, FALSE, 1,
                FALSE, NULL, FALSE, NULL, FALSE, NULL,
                FALSE, FALSE, FALSE, NULL, FALSE, FALSE
            FROM pem.profile p
            WHERE p.status IN ('published','draft')
            AND ((NEW.object_type = 100 AND p.target_kind = 'a') OR (NEW.object_type = 200 AND p.target_kind = 's'))
            ON CONFLICT (profile_id, name) DO NOTHING;
            END IF;
            IF NEW.object_type = 100 THEN
                PERFORM pem.auto_create_alerts_on_exisiting_agents();
            ELSIF NEW.object_type = 200 THEN
                PERFORM pem.auto_create_alerts_on_exisiting_servers();
            END IF;
        END IF;
        RETURN NULL;
    END
    $$ LANGUAGE plpgsql;

    CREATE OR REPLACE FUNCTION pem.alert_template_postinsert() RETURNS trigger AS $$
    BEGIN
        IF NEW.is_auto_create THEN
            -- Insert auto-create template into all published and draft profiles at creation time.
            IF NEW.object_type IN (100,200) THEN
            INSERT INTO pem.profile_alert_configs (
                profile_id, template_id, name, params, operator, thresholds, check_frequency,
                history_retention, enabled, email_group_id, send_email, send_trap, snmp_trap_version,
                low_send_trap, low_email_group_id, med_send_trap, med_email_group_id, high_send_trap,
                high_email_group_id, execute_script, execute_script_on_clear, execute_script_on_pem_server,
                script_code, submit_to_nagios, cleared_alert_enable
            )
            SELECT p.id, NEW.id, NEW.display_name, '{}'::text[], NEW.operator, NEW.thresholds,
                NEW.default_check_frequency, NEW.default_history_retention, TRUE,
                NULL, FALSE, FALSE, 1,
                FALSE, NULL, FALSE, NULL, FALSE, NULL,
                FALSE, FALSE, FALSE, NULL, FALSE, FALSE
            FROM pem.profile p
            WHERE p.status IN ('published','draft')
            AND ((NEW.object_type = 100 AND p.target_kind = 'a') OR (NEW.object_type = 200 AND p.target_kind = 's'))
            ON CONFLICT (profile_id, name) DO NOTHING;
            END IF;
            IF NEW.object_type = 100 THEN
                PERFORM pem.auto_create_alerts_on_exisiting_agents();
            ELSIF NEW.object_type = 200 THEN
                PERFORM pem.auto_create_alerts_on_exisiting_servers();
            END IF;
        END IF;
        RETURN NULL;
    END
    $$ LANGUAGE plpgsql;

    -- PEM-5847: PEM server show exception on pem.process_one_alert after upgraded from PEM 9.5 to PEM 10.2
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
		start_time timestamp;
		end_time timestamp;

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

		start_time := clock_timestamp(); -- Capture the start time to calculate the total execution time of the alert query

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

		end_time := clock_timestamp(); -- Capture the end time to calculate the total execution time of the alert query

		-- If there was an error while processing the alert's sql
		IF (err <> '') THEN
			-- Set that error message on the alert
			UPDATE pem.alert
			SET error_message = err
			WHERE id = alert_rec.id;

			-- ... and also set the last processed timestamp
			UPDATE pem.alert_status
			SET last_processed = now(),
			last_execution_duration = end_time - start_time
			WHERE alert_id = alert_rec.id;

			-- If there wasn't any row for this alert already, then populate one.
			IF (NOT FOUND) THEN
				INSERT INTO pem.alert_status
				(alert_id, current_value, current_state, current_state_since, last_processed, last_execution_duration)
				VALUES (alert_rec.id, NULL, NULL, NULL, now(), end_time - start_time);
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
			    "current_state_since", "last_processed", "display_value",
				"last_execution_duration")
			VALUES (alert_rec.id, sql_ret, state,
					CASE
					WHEN state IS NOT NULL
					THEN now()
					ELSE NULL
					END,
					now(),
					sql_ret_display,
					end_time - start_time
					);
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

END TRANSACTION;
