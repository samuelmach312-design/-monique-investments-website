/***************************************************************************
 *
 * Postgres Enterprise Manager
 *
 * Copyright (C) 2010 - 2025, EnterpriseDB Corporation. All rights reserved.
 *
 ***************************************************************************/

-- NOTE: This sql file is responsible for PEM 9.8.0 schema upgrade.

BEGIN TRANSACTION;

    CREATE OR REPLACE FUNCTION pem.schema_version() RETURNS integer AS
        'SELECT 202411191::integer;'
    LANGUAGE 'sql' IMMUTABLE;
    COMMENT ON FUNCTION pem.schema_version() IS
        'Returns the version number of the PEM schema';

    -- PEM-5320 Added support for monotoring PG/EPAS 17
    UPDATE pem.probe_server_version SET probe_code = 'SELECT checkpoints_timed, checkpoints_req, buffers_clean, buffers_checkpoint, maxwritten_clean, buffers_backend, buffers_alloc FROM pg_catalog.pg_stat_bgwriter'
    WHERE probe_id = (SELECT id from pem.probe WHERE internal_name = 'background_writer_statistics')
    AND server_version_id IN (10803, 10804, 10900, 10901, 10902, 10903, 10904, 10905, 10906, 11000, 11100, 11200, 11300, 11400, 11500, 11600,
        20804, 20900, 20901, 20902, 20903, 20904, 20905, 20906, 21000, 21100, 21200, 21300, 21400, 21500, 21600);

    DO $DO$
        BEGIN
            -- Check if the server version already exist for PG 17
            IF NOT EXISTS (SELECT id FROM pem.server_version WHERE id = 11700) THEN
                INSERT INTO pem.server_version VALUES (11700, 'PostgreSQL 17');
            END IF;

            -- Check if the server version already exist for EPAS 17
            IF NOT EXISTS (SELECT id FROM pem.server_version WHERE id = 21700) THEN
                INSERT INTO pem.server_version VALUES (21700, 'Advanced Server 17');
            END IF;

            -- Check if the probe server version already exist for PG 17
            IF NOT EXISTS (SELECT server_version_id FROM pem.probe_server_version WHERE server_version_id = 11700) THEN
                INSERT INTO pem.probe_server_version
                    (probe_id, server_version_id, probe_code)
                    SELECT psv.probe_id, 11700 AS server_version_id, psv.probe_code FROM (
                        SELECT probe_id, probe_code FROM pem.probe_server_version
                        WHERE server_version_id = 11600
                    ) AS psv
                    JOIN pem.probe p ON (psv.probe_id = p.id) AND p.internal_name = ANY(
                        ARRAY[
                            'oc_database', 'oc_table', 'oc_schema', 'oc_function', 'oc_extension', 'oc_views',
                            'database_statistics', 'table_statistics', 'table_frozenxid',
                            'table_size', 'function_statistics', 'mview_bloat',
                            'mview_frozenxid', 'mview_size', 'blocked_session_info',
                            'session_info', 'user_info', 'lock_info',
                            'number_of_wal_files', 'wal_archive_status',
                            'streaming_replication', 'streaming_replication_db_conflicts',
                            'streaming_replication_lag_time', 'xdb_smr_mmr_replication',
                            'efm_cluster_node_status', 'efm_cluster_info', 'replication_slots'
                            ]::text[]
                    );
            END IF;

            -- Check if the probe server version already exist for EPAS 17
            IF NOT EXISTS (SELECT server_version_id FROM pem.probe_server_version WHERE server_version_id = 21700) THEN
                INSERT INTO pem.probe_server_version
                    (probe_id, server_version_id, probe_code)
                    SELECT psv.probe_id, 21700 AS server_version_id, psv.probe_code FROM (
                        SELECT probe_id, probe_code FROM pem.probe_server_version
                        WHERE server_version_id = 21600
                    ) AS psv
                    JOIN pem.probe p ON (psv.probe_id = p.id) AND p.internal_name = ANY(
                        ARRAY[
                            'oc_database', 'oc_table', 'oc_schema','oc_function', 'oc_extension', 'database_statistics',
                            'table_statistics', 'table_frozenxid', 'function_statistics', 'table_size',
                            'number_of_wal_files', 'session_info',
                            'system_waits', 'session_waits', 'user_info', 'lock_info', 'audit_configuration',
                            'streaming_replication', 'streaming_replication_db_conflicts',
                            'xdb_smr_mmr_replication', 'oc_views', 'mview_bloat', 'mview_frozenxid',
                            'mview_size', 'streaming_replication_lag_time', 'wal_archive_status',
                            'efm_cluster_node_status', 'efm_cluster_info', 'blocked_session_info', 'replication_slots'
                            ]::text[]
                    );

                INSERT INTO pem.probe_server_version
                    (probe_id, server_version_id, probe_code)
                    SELECT
	                (SELECT id FROM pem.probe WHERE internal_name = 'background_writer_statistics'), v.version,
	                $SQL$SELECT c.num_timed AS checkpoints_timed, c.num_requested AS checkpoints_req, b.buffers_clean, c.buffers_written AS buffers_checkpoint,
			    b.maxwritten_clean, w.writes AS buffers_backend, b.buffers_alloc
		        FROM pg_catalog.pg_stat_bgwriter b CROSS JOIN pg_catalog.pg_stat_checkpointer c
		        CROSS JOIN (SELECT writes FROM pg_catalog.pg_stat_io WHERE backend_type='background writer' LIMIT 1) w$SQL$
                    FROM (
                        VALUES (11700), (21700)
                    ) v(version);
            END IF;
    END;
    $DO$ LANGUAGE 'plpgsql';

    -- PEM-5351 Reinstiating the "Update the probe-objects combination" job if missing to resolve the purgung job issue
    CREATE OR REPLACE FUNCTION pem.purge_job_log()
    RETURNS void AS $$
    DECLARE
	    cutoff_ts timestamp with time zone;
    BEGIN
        cutoff_ts := (SELECT now() - CAST(value || ' ' || unit AS interval)
            FROM pem.config WHERE param = 'job_retention_time');

        -- Purge old jobs, steps and schedules
        DELETE FROM pem.job AS j
        WHERE j.jobnextrun IS NULL AND j.joblastrun < cutoff_ts AND j.issystemjob = false;

        -- Purge job log and job step log
        DELETE FROM pem.joblog AS jl
        WHERE jl.jlgstart < cutoff_ts;
    END;
    $$ LANGUAGE plpgsql SECURITY DEFINER;

    DO $$
    DECLARE
        job_id INT;
        agentId INT;
        serverId INT;
        databaseName TEXT;
        tmpid INT;
    BEGIN
        -- Check if the job already exists.
        SELECT jobid INTO job_id
        FROM pem.job
        WHERE jobname = 'Update the probe-objects combination';

        IF NOT FOUND THEN
            -- Get the agent ID for a specific job if needed.
            SELECT agent_id INTO agentId
            FROM pem.job
            WHERE jobid = 1;  -- You may need to adjust this condition as necessary.

            -- Get the server ID and database name from job step.
            SELECT server_id, database_name INTO serverId, databaseName
            FROM pem.jobstep
            WHERE jstjobid = 1;  -- Adjust this condition as needed.

            -- Insert a new job to update the probe-objects combination, scheduled to run 10 minutes after creation.
            INSERT INTO pem.job (
                jobname, jobdesc, agent_id, issystemjob, jobnextrun
            ) VALUES (
                'Update the probe-objects combination',
                'This job updates/inserts the record of the probe, parameter_value_list in the ''pem.probe_objects_combo'' table.',
                agentId, true, now() + interval '10 minutes'
            ) RETURNING jobid INTO job_id;
        END IF;

        -- Check if the job step already exists.
        SELECT jstid INTO tmpid
        FROM pem.jobstep
        WHERE jstname = 'Update the probe-objects combination' AND jstjobid = job_id;

        IF NOT FOUND THEN
            -- Insert a new job step if it does not already exist.
            INSERT INTO pem.jobstep (
                jstjobid, jstname, jstdesc, jstkind, jstcode,
                server_id, database_name
            ) VALUES (
                job_id, 'Database cleanup',
                'This job step updates the purge-job tasks on demand.',
                's', 'SELECT pem.create_update_probe_objects_combo()',
                serverId, databaseName
            );
        ELSE
            -- Update the existing job step to enable it.
            UPDATE pem.jobstep
            SET jstenabled = TRUE
            WHERE jstid = tmpid AND jstjobid = job_id;
        END IF;
    END $$;

END TRANSACTION;
