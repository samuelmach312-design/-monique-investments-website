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

-- This upgrade script will upgrade the faulty pem schema due to previous failed upgrade script.
-- Whenever user upgrade PEM from 6.0 to 7.4, there was issue while executing 201601074, 201601075 schema.
-- so pem schema change inside that files will not be reflected so this script will check if those schema exists
-- or not and if not exists then apply the change.
-- There is no change in 'pemserver.sql' as this upgrade script will update only schema if not exists.

BEGIN TRANSACTION;

CREATE OR REPLACE FUNCTION pem.schema_version()
  RETURNS integer AS
'SELECT 201809051::integer;'
  LANGUAGE 'sql' IMMUTABLE;
COMMENT ON FUNCTION pem.schema_version() IS 'Returns the version number of the PEM schema';

UPDATE pem.alert_template SET sql = $sql$SELECT
        ((space_used_mb::float * 100)
        / CASE size_mb WHEN 0 THEN 1 ELSE (size_mb - COALESCE(space_reserved_mb, 0)) END)
        FROM pemdata.disk_space
        WHERE agent_id = ${agent_id}
        AND mount_point = '${param_1}';$sql$
WHERE display_name = 'Disk consumption percentage';

-- Check if 'pem.probe_objects_combo' table and 'lag_MB' column in streaming replication exists or not.
-- If it is not exists then apply the change.
DO
$$
BEGIN

    IF NOT EXISTS (
        SELECT 1
        FROM
            information_schema.columns
        WHERE
            table_schema = 'pem' AND
            table_name   = 'probe' AND
            column_name = 'jstid'
    ) THEN
        ALTER TABLE pem.probe ADD COLUMN jstid integer DEFAULT NULL;
    END IF;

    -- Check first "pem.probe_objects_combo" table exists or not.
    IF NOT EXISTS (
        SELECT 1
        FROM
            pg_catalog.pg_class c
        JOIN
            pg_catalog.pg_namespace n ON n.oid = c.relnamespace
        WHERE
            n.nspname = 'pem' AND
            c.relname = 'probe_objects_combo' AND
            c.relkind = 'r'
        ) THEN
        --
        -- TABLE: pem.probe_objects_combo
        --
        -- Keeps track of the combination of the probe-id, parameter_value_list.
        -- It will release the
        -- parameters combination to avoid the unnecessary locks during the
        -- whole purging process to make things smoother.
        CREATE TABLE pem.probe_objects_combo (
            pid       integer NOT NULL,
            objects   text[] NOT NULL,
            lifetime  integer NOT NULL,
            purged_on timestamptz,
            delete_on date,
            PRIMARY KEY (pid, objects),
            CONSTRAINT purge_probe_tasks_pid_fkey FOREIGN KEY (pid)
                REFERENCES pem.probe(id) MATCH SIMPLE
                ON UPDATE CASCADE ON DELETE CASCADE INITIALLY DEFERRED
        );
    END IF;

    -- Check if "lag_MB" column exists or not. As we have renamed the column name from
    -- "lag_MB" to "lag_mb". Previous upgrade script have problem so need to verify latest
    -- schema to run streaming replication probe.
    -- Rename column name from "lag_MB" to "lag_mb" for streaming replication probe.
    IF EXISTS (
        SELECT 1
        FROM
            information_schema.columns
        WHERE
            table_schema = 'pemdata' AND
            table_name   = 'streaming_replication' AND
            column_name = 'lag_MB'
    ) THEN
        ALTER TABLE pemdata.streaming_replication RENAME COLUMN "lag_MB" TO lag_mb;
    END IF;

    IF EXISTS (
        SELECT 1
        FROM
            information_schema.columns
        WHERE
            table_schema = 'pemhistory' AND
            table_name   = 'streaming_replication' AND
            column_name = 'lag_MB'
    ) THEN
        ALTER TABLE pemhistory.streaming_replication RENAME COLUMN "lag_MB" TO lag_mb;
    END IF;

    UPDATE
        pem.probe_column
    SET
        internal_name = 'lag_mb'
    WHERE
        internal_name = 'lag_MB' AND
        probe_id = (SELECT id FROM pem.probe WHERE internal_name = 'streaming_replication');
END;
$$ LANGUAGE 'plpgsql';

UPDATE pem.probe SET probe_code = $sql$
SELECT client_addr, client_port, sent_location, write_location, flush_location, replay_location, xlog_lag_in_segments,
    (((sent_location -replay_location)>>10) / (SUBSTRING(unit FROM '[0-9]+'))::INT) AS xlog_lag_in_pages,
    floor(((lag_mb/1024)/1024)) AS lag_mb
FROM (

        WITH pg_stat_replication_log_bytes AS (
        SELECT
            host(client_addr) AS client_addr, client_port,

            pg_catalog.split_part(sent_location, '/', 1) AS s1,
            pg_catalog.split_part(sent_location, '/', 2) AS s2,

            pg_catalog.split_part(write_location, '/', 1) AS w1,
            pg_catalog.split_part(write_location, '/', 2) AS w2,

            pg_catalog.split_part(flush_location, '/', 1) AS f1,
            pg_catalog.split_part(flush_location, '/', 2) AS f2,

            pg_catalog.split_part(replay_location, '/', 1) AS r1,
            pg_catalog.split_part(replay_location, '/', 2) AS r2,

            (('x'||SUBSTRING((pg_xlogfile_name_offset(sent_location)).file_name FROM 9))::BIT(64)::BIGINT -
                ('x'||SUBSTRING((pg_xlogfile_name_offset(replay_location)).file_name FROM 9))::BIT(64)::BIGINT) AS xlog_lag_in_segments,

            pg_xlog_location_diff(sent_location, replay_location) AS lag_mb

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
        xlog_lag_in_segments,
        lag_mb
    FROM pg_stat_replication_log_bytes
) AS pg_stat_replication_dtls, pg_catalog.pg_settings
WHERE name ~ 'wal_segment_size'
$sql$
WHERE internal_name = 'streaming_replication';

UPDATE pem.probe_server_version SET probe_code = $sql$
SELECT client_addr, client_port, sent_location, write_location, flush_location, replay_location, xlog_lag_in_segments,
        (((sent_location -replay_location)>>10) / (SUBSTRING(unit FROM '[0-9]+'))::INT) AS xlog_lag_in_pages,
        floor(((lag_mb/1024)/1024)) AS lag_mb
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
                ('x'||SUBSTRING((pg_xlogfile_name_offset(replay_location)).file_name FROM 9))::BIT(64)::BIGINT) AS xlog_lag_in_segments,

            pg_xlog_location_diff(sent_location, replay_location) AS lag_mb

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
        xlog_lag_in_segments,
        lag_mb
    FROM pg_stat_replication_log_bytes
) AS pg_stat_replication_dtls, pg_catalog.pg_settings
WHERE name ~ 'wal_segment_size'
$sql$
WHERE probe_id = (SELECT id from pem.probe WHERE internal_name = 'streaming_replication')
AND server_version_id IN (10904, 10905, 10906, 20904, 20905, 20906);

UPDATE pem.probe_server_version SET probe_code = $sql$
SELECT client_addr, client_port, sent_location, write_location, flush_location, replay_location, xlog_lag_in_segments,
        (((sent_location -replay_location)>>10) / (SUBSTRING(unit FROM '[0-9]+'))::INT) AS xlog_lag_in_pages,
        floor(((lag_mb/1024)/1024)) AS lag_mb
FROM (
        WITH pg_stat_replication_log_bytes AS (
        SELECT
            host(client_addr) AS client_addr, client_port,

            pg_catalog.split_part(sent_lsn::text, '/', 1) AS s1,
            pg_catalog.split_part(sent_lsn::text, '/', 2) AS s2,

            pg_catalog.split_part(write_lsn::text, '/', 1) AS w1,
            pg_catalog.split_part(write_lsn::text, '/', 2) AS w2,

            pg_catalog.split_part(flush_lsn::text, '/', 1) AS f1,
            pg_catalog.split_part(flush_lsn::text, '/', 2) AS f2,

            pg_catalog.split_part(replay_lsn::text, '/', 1) AS r1,
            pg_catalog.split_part(replay_lsn::text, '/', 2) AS r2,

            (('x'||SUBSTRING((pg_walfile_name_offset(sent_lsn)).file_name FROM 9))::BIT(64)::BIGINT -
                ('x'||SUBSTRING((pg_walfile_name_offset(replay_lsn)).file_name FROM 9))::BIT(64)::BIGINT) AS xlog_lag_in_segments,

            pg_wal_lsn_diff(sent_lsn, replay_lsn) AS lag_mb

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
        xlog_lag_in_segments,
        lag_mb
    FROM pg_stat_replication_log_bytes
) AS pg_stat_replication_dtls, pg_catalog.pg_settings
WHERE name ~ 'wal_segment_size'
$sql$
WHERE probe_id = (SELECT id from pem.probe WHERE internal_name = 'streaming_replication')
AND server_version_id IN (11000, 21000, 11100, 21100);

-- Update the alert template modified the column name from "lag_MB" to "lag_mb"
UPDATE pem.alert_template SET
    sql = $sql$
    SELECT MAX(lag_mb) FROM pemdata.streaming_replication WHERE server_id = ${server_id}$sql$,
    info_sql = $sql$SELECT srv.description || ' (' || srv.server || ')' AS "Master server",
       sr.client_addr AS "Standby server",
       sr.client_port AS "Standby server port",
       sr.xlog_lag_in_segments AS "Lag in segments", sr.xlog_lag_in_pages AS "Lag in pages",
       sr.lag_mb AS "Lag in MB"
       FROM pemdata.streaming_replication AS sr
       JOIN pem.server AS srv
       ON sr.server_id = srv.id
       WHERE sr.server_id = '${server_id}'::integer
       AND lag_mb ${comparison_operator} '${threshold_value}'::numeric;$sql$
WHERE display_name = 'Standby servers lag behind the master by size(MB)';

CREATE OR REPLACE FUNCTION pemdata.copy_streaming_replication_to_history()
    RETURNS trigger
    LANGUAGE 'plpgsql'
    COST 100
    VOLATILE NOT LEAKPROOF
AS $BODY$
    BEGIN
        IF (TG_OP = 'INSERT' OR TG_OP = 'UPDATE') THEN
            INSERT INTO pemhistory.streaming_replication (recorded_time, server_id, client_addr, client_port, sent_location, write_location, flush_location, replay_location, xlog_lag_in_segments, xlog_lag_in_pages, lag_mb) VALUES (NEW.recorded_time, NEW.server_id, NEW.client_addr, NEW.client_port, NEW.sent_location, NEW.write_location, NEW.flush_location, NEW.replay_location, NEW.xlog_lag_in_segments, NEW.xlog_lag_in_pages, NEW.lag_mb);
            ELSIF EXISTS(SELECT 1 FROM pem.server WHERE id = OLD.server_id) THEN
            INSERT INTO pemhistory.streaming_replication (server_id, client_addr, client_port) VALUES (OLD.server_id, OLD.client_addr, OLD.client_port);
        END IF;
        RETURN NEW;
    END;
$BODY$;

CREATE OR REPLACE VIEW pem.probe_target_without_discard_history AS
SELECT
    p.id AS probe_id, p.internal_name AS probe_internal_name,
    p.target_type_id, ARRAY[a.id::text]::text[] AS parameter_value_list,
    COALESCE(c.lifetime, p.default_lifetime) AS lifetime
FROM
    (
        SELECT * FROM pem.probe
        WHERE  target_type_id = 100 AND NOT deleted AND NOT discard_history
    ) AS p
    CROSS JOIN pem.agent a
    LEFT JOIN pem.probe_config_agent c
        ON p.id = c.probe_id AND a.id = c.agent_id
WHERE
    (
        p.agent_capability IS NULL OR
        p.agent_capability = ANY(a.agent_capability_list)
    ) AND (
        CASE p.collection_method
        WHEN 'b' THEN a.agent_capability_list @> ARRAY['allow_batch_probes']
        WHEN 'w' THEN strpos(a.platform, 'windows') != 0
        ELSE TRUE
        END
    )
UNION ALL
SELECT
    p.id AS probe_id, p.internal_name AS probe_internal_name,
    p.target_type_id, ARRAY[s.id::text]::text[] AS parameter_value_list,
    COALESCE(c.lifetime, p.default_lifetime) AS lifetime
FROM
    (
        SELECT * FROM pem.probe
        WHERE  target_type_id = 200 AND NOT deleted AND NOT discard_history
    ) AS p
    CROSS JOIN pem.server s
    LEFT JOIN pem.agent_server_binding b ON b.server_id = s.id
    LEFT JOIN pem.agent a ON b.agent_id = a.id
    LEFT JOIN pemdata.server_info sd ON s.id = sd.server_id
    LEFT JOIN pem.probe_server_version psv
        ON p.id = psv.probe_id AND sd.server_version_id = psv.server_version_id
    LEFT JOIN pem.probe_config_server c
        ON p.id = c.probe_id AND s.id = c.server_id
WHERE
    (
        p.agent_capability IS NULL OR a.agent_capability_list IS NULL OR
        p.agent_capability = ANY(a.agent_capability_list)
    ) AND (
        p.any_server_version OR psv.probe_id IS NOT NULL
    ) AND p.internal_name NOT IN(
        SELECT UNNEST(
            CASE
            WHEN s.is_remote_monitoring THEN
                ARRAY['pg_hba_conf', 'data_log_file_analysis', 'wal_archive_status', 'log_configuration', 'efm_cluster_node_status', 'efm_cluster_info']
            ELSE
                ARRAY['']
            END
        )
    ) AND p.internal_name NOT IN(
        SELECT UNNEST(
            CASE
            WHEN a.agent_capability_list @> ARRAY['windows']
                THEN ARRAY['efm_cluster_node_status', 'efm_cluster_info']
            ELSE ARRAY[''] END
        )
    ) AND (
        CASE p.collection_method
        WHEN 'b' THEN (
            a.agent_capability_list @> ARRAY['allow_batch_probes'] AND (
                strpos(a.platform, p.platform) != 0 OR (
                    a.platform !~ 'windows' AND p.platform = 'unix'
                )
            )
        )
        ELSE TRUE
        END
    )
UNION ALL
SELECT
    p.id AS probe_id, p.internal_name AS probe_internal_name,
    p.target_type_id, ARRAY[s.id::text, ocd.database_name]::text[] AS parameter_value_list,
    COALESCE(c.lifetime, p.default_lifetime) AS lifetime
FROM
    (
        SELECT * FROM pem.probe
        WHERE  target_type_id = 300 AND NOT deleted AND NOT discard_history
    ) AS p
    CROSS JOIN pem.server s
    LEFT JOIN pem.agent_server_binding b ON b.server_id = s.id
    LEFT JOIN pem.agent a ON b.agent_id = a.id
    LEFT JOIN pemdata.server_info sd ON s.id = sd.server_id
    LEFT JOIN pem.probe_server_version psv
        ON p.id = psv.probe_id AND sd.server_version_id = psv.server_version_id
    INNER JOIN (SELECT * FROM pemdata.oc_database WHERE connections_allowed) ocd
        ON s.id = ocd.server_id
    LEFT JOIN pem.probe_config_database c
        ON p.id = c.probe_id AND s.id = c.server_id AND
        ocd.database_name = c.database_name
WHERE
    (
        p.agent_capability IS NULL OR a.agent_capability_list IS NULL OR
        p.agent_capability = ANY(a.agent_capability_list)
    ) AND (p.any_server_version OR psv.probe_id IS NOT NULL) AND (
        CASE p.collection_method
        WHEN 'b' THEN (
            a.agent_capability_list @> ARRAY['allow_batch_probes'] AND (
                strpos(a.platform, p.platform) != 0 OR (
                    a.platform !~ 'windows' AND p.platform = 'unix'
                )
            )
        )
        ELSE TRUE
        END
    )
UNION ALL
SELECT
    p.id AS probe_id, p.internal_name AS probe_internal_name,
    p.target_type_id, ARRAY[
        s.id::text, oc.database_name, oc.schema_name
    ]::text[] AS parameter_value_list,
    COALESCE(c.lifetime, p.default_lifetime) AS lifetime
FROM
    (
        SELECT * FROM pem.probe
        WHERE  target_type_id = 400 AND NOT deleted AND NOT discard_history
    ) AS p
    CROSS JOIN pem.server s
    LEFT JOIN pem.agent_server_binding b ON b.server_id = s.id
    LEFT JOIN pem.agent a ON b.agent_id = a.id
    LEFT JOIN pemdata.server_info sd ON s.id = sd.server_id
    LEFT JOIN pem.probe_server_version psv
        ON p.id = psv.probe_id AND sd.server_version_id = psv.server_version_id
    INNER JOIN (SELECT * FROM pemdata.oc_database WHERE connections_allowed) ocd
        ON s.id = ocd.server_id
    INNER JOIN pemdata.oc_schema oc ON ocd.server_id = oc.server_id AND
        ocd.database_name = oc.database_name
    LEFT JOIN pem.probe_config_schema c ON p.id = c.probe_id AND
        s.id = c.server_id AND oc.database_name = c.database_name AND
        oc.schema_name = c.schema_name
WHERE
    (
        p.agent_capability IS NULL OR a.agent_capability_list IS NULL OR
        p.agent_capability = ANY(a.agent_capability_list)
    ) AND (p.any_server_version OR psv.probe_id IS NOT NULL) AND (
        CASE p.collection_method
        WHEN 'b' THEN (
            a.agent_capability_list @> ARRAY['allow_batch_probes'] AND (
                strpos(a.platform, p.platform) != 0 OR (
                    a.platform !~ 'windows' AND p.platform = 'unix'
                )
            )
        )
        ELSE TRUE
        END
    )
UNION ALL
SELECT
    p.id AS probe_id, p.internal_name AS probe_internal_name,
    p.target_type_id, ARRAY[
        s.id::text, oc.database_name, oc.schema_name, oc.table_name
    ]::text[] AS parameter_value_list,
    COALESCE(c.lifetime, p.default_lifetime) AS lifetime
FROM
    (
        SELECT * FROM pem.probe
        WHERE  target_type_id = 500 AND NOT deleted AND NOT discard_history
    ) AS p
    CROSS JOIN pem.server s
    LEFT JOIN pem.agent_server_binding b ON b.server_id = s.id
    LEFT JOIN pem.agent a ON b.agent_id = a.id
    LEFT JOIN pemdata.server_info sd ON s.id = sd.server_id
    LEFT JOIN pem.probe_server_version psv
        ON p.id = psv.probe_id AND sd.server_version_id = psv.server_version_id
    INNER JOIN (SELECT * FROM pemdata.oc_database WHERE connections_allowed) ocd
        ON s.id = ocd.server_id
    INNER JOIN pemdata.oc_table oc ON ocd.server_id = oc.server_id AND
        ocd.database_name = oc.database_name
    LEFT JOIN pem.probe_config_table c ON p.id = c.probe_id AND
        s.id = c.server_id AND oc.database_name = c.database_name AND
        oc.schema_name = c.schema_name AND oc.table_name = c.table_name
WHERE
    (
        p.agent_capability IS NULL OR a.agent_capability_list IS NULL OR
        p.agent_capability = ANY(a.agent_capability_list)
    ) AND (p.any_server_version OR psv.probe_id IS NOT NULL) AND (
        CASE p.collection_method
        WHEN 'b' THEN (
            a.agent_capability_list @> ARRAY['allow_batch_probes'] AND (
                strpos(a.platform, p.platform) != 0 OR (
                    a.platform !~ 'windows' AND p.platform = 'unix'
                )
            )
        )
        ELSE TRUE
        END
    )
UNION ALL
SELECT
    p.id AS probe_id, p.internal_name AS probe_internal_name,
    p.target_type_id, ARRAY[
        s.id::text, oc.database_name, oc.schema_name, oc.index_name
    ]::text[] AS parameter_value_list,
    COALESCE(c.lifetime, p.default_lifetime) AS lifetime
FROM
    (
        SELECT * FROM pem.probe
        WHERE  target_type_id = 600 AND NOT deleted AND NOT discard_history
    ) AS p
    CROSS JOIN pem.server s
    LEFT JOIN pem.agent_server_binding b ON b.server_id = s.id
    LEFT JOIN pem.agent a ON b.agent_id = a.id
    LEFT JOIN pemdata.server_info sd ON s.id = sd.server_id
    LEFT JOIN pem.probe_server_version psv
        ON p.id = psv.probe_id AND sd.server_version_id = psv.server_version_id
    INNER JOIN (SELECT * FROM pemdata.oc_database WHERE connections_allowed) ocd
        ON s.id = ocd.server_id
    INNER JOIN pemdata.oc_index oc ON ocd.server_id = oc.server_id AND
        ocd.database_name = oc.database_name
    LEFT JOIN pem.probe_config_index c ON p.id = c.probe_id AND
        s.id = c.server_id AND oc.database_name = c.database_name AND
        oc.schema_name = c.schema_name AND oc.index_name = c.index_name
WHERE
    (
        p.agent_capability IS NULL OR a.agent_capability_list IS NULL OR
        p.agent_capability = ANY(a.agent_capability_list)
    ) AND (p.any_server_version OR psv.probe_id IS NOT NULL) AND (
        CASE p.collection_method
        WHEN 'b' THEN (
            a.agent_capability_list @> ARRAY['allow_batch_probes'] AND (
                strpos(a.platform, p.platform) != 0 OR (
                    a.platform !~ 'windows' AND p.platform = 'unix'
                )
            )
        )
        ELSE TRUE
        END
    )
UNION ALL
SELECT
    p.id AS probe_id, p.internal_name AS probe_internal_name,
    p.target_type_id, ARRAY[
        s.id::text, oc.database_name, oc.schema_name, oc.sequence_name
    ]::text[] AS parameter_value_list,
    COALESCE(c.lifetime, p.default_lifetime) AS lifetime
FROM
    (
        SELECT * FROM pem.probe
        WHERE  target_type_id = 700 AND NOT deleted AND NOT discard_history
    ) AS p
    CROSS JOIN pem.server s
    LEFT JOIN pem.agent_server_binding b ON b.server_id = s.id
    LEFT JOIN pem.agent a ON b.agent_id = a.id
    LEFT JOIN pemdata.server_info sd ON s.id = sd.server_id
    LEFT JOIN pem.probe_server_version psv
        ON p.id = psv.probe_id AND sd.server_version_id = psv.server_version_id
    INNER JOIN (SELECT * FROM pemdata.oc_database WHERE connections_allowed) ocd
        ON s.id = ocd.server_id
    INNER JOIN pemdata.oc_sequence oc ON ocd.server_id = oc.server_id AND
        ocd.database_name = oc.database_name
    LEFT JOIN pem.probe_config_sequence c ON p.id = c.probe_id AND
        s.id = c.server_id AND oc.database_name = c.database_name AND
        oc.schema_name = c.schema_name AND
        oc.sequence_name = c.sequence_name
WHERE
    (
        p.agent_capability IS NULL OR a.agent_capability_list IS NULL OR
        p.agent_capability = ANY(a.agent_capability_list)
    ) AND (p.any_server_version OR psv.probe_id IS NOT NULL) AND (
        CASE p.collection_method
        WHEN 'b' THEN (
            a.agent_capability_list @> ARRAY['allow_batch_probes'] AND (
                strpos(a.platform, p.platform) != 0 OR (
                    a.platform !~ 'windows' AND p.platform = 'unix'
                )
            )
        )
        ELSE TRUE
        END
    )
UNION ALL
SELECT
    p.id AS probe_id, p.internal_name AS probe_internal_name,
    p.target_type_id, ARRAY[
        s.id::text, oc.database_name, oc.schema_name, oc.function_name
    ]::text[] AS parameter_value_list,
    COALESCE(c.lifetime, p.default_lifetime) AS lifetime
FROM
    (
        SELECT * FROM pem.probe
        WHERE  target_type_id = 800 AND NOT deleted AND NOT discard_history
    ) AS p
    CROSS JOIN pem.server s
    LEFT JOIN pem.agent_server_binding b ON b.server_id = s.id
    LEFT JOIN pem.agent a ON b.agent_id = a.id
    LEFT JOIN pemdata.server_info sd ON s.id = sd.server_id
    LEFT JOIN pem.probe_server_version psv
        ON p.id = psv.probe_id AND sd.server_version_id = psv.server_version_id
    INNER JOIN (SELECT * FROM pemdata.oc_database WHERE connections_allowed) ocd
        ON s.id = ocd.server_id
    INNER JOIN pemdata.oc_function oc ON ocd.server_id = oc.server_id AND
        ocd.database_name = oc.database_name
    LEFT JOIN pem.probe_config_function c ON p.id = c.probe_id AND
        oc.server_id = c.server_id AND oc.database_name = c.database_name AND
        oc.schema_name = c.schema_name AND oc.function_name = c.function_name
WHERE
    (
        p.agent_capability IS NULL OR a.agent_capability_list IS NULL OR
        p.agent_capability = ANY(a.agent_capability_list)
    ) AND (p.any_server_version OR psv.probe_id IS NOT NULL) AND (
        CASE p.collection_method
        WHEN 'b' THEN (
            a.agent_capability_list @> ARRAY['allow_batch_probes'] AND (
                strpos(a.platform, p.platform) != 0 OR (
                    a.platform !~ 'windows' AND p.platform = 'unix'
                )
            )
        )
        ELSE TRUE
        END
    )
UNION ALL
SELECT
    p.id AS probe_id, p.internal_name AS probe_internal_name,
    p.target_type_id, ARRAY[
        s.id::text, oc.database_name, oc.schema_name, oc.view_name
    ]::text[] AS parameter_value_list,
    COALESCE(c.lifetime, p.default_lifetime) AS lifetime
FROM
    (
        SELECT * FROM pem.probe
        WHERE  target_type_id = 900 AND NOT deleted AND NOT discard_history
    ) AS p
    CROSS JOIN pem.server s
    LEFT JOIN pem.agent_server_binding b ON b.server_id = s.id
    LEFT JOIN pem.agent a ON b.agent_id = a.id
    LEFT JOIN pemdata.server_info sd ON s.id = sd.server_id
    LEFT JOIN pem.probe_server_version psv
        ON p.id = psv.probe_id AND sd.server_version_id = psv.server_version_id
    INNER JOIN (SELECT * FROM pemdata.oc_database WHERE connections_allowed) ocd
        ON s.id = ocd.server_id
    INNER JOIN pemdata.oc_views oc ON ocd.server_id = oc.server_id AND
        ocd.database_name = oc.database_name
    LEFT JOIN pem.probe_config_view c ON p.id = c.probe_id AND
        oc.server_id = c.server_id AND oc.database_name = c.database_name AND
        oc.schema_name = c.schema_name AND oc.view_name = c.view_name
WHERE
    (
        p.agent_capability IS NULL OR a.agent_capability_list IS NULL OR
        p.agent_capability = ANY(a.agent_capability_list)
    ) AND (p.any_server_version OR psv.probe_id IS NOT NULL) AND (
        CASE p.collection_method
        WHEN 'b' THEN (
            a.agent_capability_list @> ARRAY['allow_batch_probes'] AND (
                strpos(a.platform, p.platform) != 0 OR (
                    a.platform !~ 'windows' AND p.platform = 'unix'
                )
            )
        )
        ELSE TRUE
        END
    );


CREATE OR REPLACE FUNCTION pem.purge_probe_history(_pid integer)
  RETURNS void AS
$function$
DECLARE
    probe_curs     REFCURSOR;
    probe          RECORD;
    table_name     varchar := NULL;
    subquery       varchar;
    where_clause   varchar;
    combo_cnt      integer;
    parameter_list text[];
BEGIN

    SELECT count(*) INTO combo_cnt
    FROM pem.probe_objects_combo o WHERE o.pid = _pid;

    -- Let's not rush to things, do the purging in small chunks.
    combo_cnt := (ceil(combo_cnt::float / 5))::integer;
    -- We will run the purging exercise only for 1000 maximum combination
    -- ordered by purge time.
    IF combo_cnt > 1000 THEN
        combo_cnt := 1000;
    ELSE
        IF combo_cnt < 20 THEN
            combo_cnt := 20;
        END IF;
    END IF;

    SELECT
        'pemhistory.' || quote_ident(p.internal_name),
        CASE p.target_type_id
        WHEN 100 THEN ARRAY['agent_id']::text[]
        WHEN 200 THEN ARRAY['server_id']::text[]
        WHEN 300 THEN ARRAY['server_id', 'database_name']::text[]
        WHEN 400 THEN ARRAY['server_id', 'database_name', 'schema_name']::text[]
        END
        INTO table_name, parameter_list
    FROM pem.probe p
    WHERE p.id = _pid AND EXISTS (
        SELECT 1 FROM pg_class, pg_namespace
        WHERE pg_namespace.oid = pg_class.relnamespace AND
            pg_namespace.nspname = 'pemhistory' AND pg_class.relname = p.internal_name
    );

    IF table_name IS NULL THEN
        RETURN;
    END IF;

    OPEN probe_curs FOR EXECUTE '
        SELECT objects, lifetime
        FROM pem.probe_objects_combo
        WHERE pid = $1::integer
        ORDER BY purged_on NULLS FIRST LIMIT ' || combo_cnt
        USING _pid;

    LOOP
        FETCH NEXT FROM probe_curs INTO probe;
        EXIT WHEN probe IS NULL;

        where_clause := ' WHERE ';

        FOR i IN array_lower(parameter_list, 1)..array_upper(parameter_list, 1)
        LOOP
            where_clause := where_clause || parameter_list[i] || ' = ' || pg_catalog.quote_literal(probe.objects[i]::text) || ' AND ';
        END LOOP;

        subquery := 'SELECT recorded_time FROM ' || table_name || where_clause || 'recorded_time <= (now() - interval ''' || probe.lifetime || ' days'') ORDER BY recorded_time DESC LIMIT 1';
        where_clause := where_clause || ' recorded_time < (' || subquery || ')';

        EXECUTE 'DELETE FROM ' || table_name || where_clause;
        UPDATE pem.probe_objects_combo SET purged_on = now() WHERE pid = _pid AND objects = probe.objects;
    END LOOP;
    CLOSE probe_curs;
END;
$function$ LANGUAGE plpgsql;

--
-- TRIGGER FUNCTION: pem.create_delete_probe_purge_jobstep()
--
-- This trigger function will create/remove the jobsteps for purging history
-- data for a particular probe.
CREATE OR REPLACE FUNCTION pem.create_delete_probe_purge_jobstep()
    RETURNS trigger AS
$function$
DECLARE
    purge_job_id integer;
    purge_jstid  integer;
    pem_server   integer;
    pem_database text;
BEGIN
    IF TG_OP = 'INSERT' THEN
        IF NOT NEW.discard_history THEN
            -- Fetch the server-id, database name for the PEM database server
            EXECUTE $SQL$
                SELECT server_id, database_name, jstjobid
                FROM pem.jobstep
                WHERE jstjobid = (
                    SELECT jobid FROM pem.job
                    WHERE issystemjob = true AND jobname = 'Database cleanup'
                    ORDER BY jobid LIMIT 1
                )
            $SQL$ INTO pem_server, pem_database, purge_job_id;

            INSERT INTO pem.jobstep(
                jstjobid, jstname, jstdesc, jstenabled, jstkind, jstcode, server_id,
                database_name, jstonerror, jstsetenvironment
            ) VALUES (
                purge_job_id, 'Purge data (' || NEW.display_name || ')',
                'Purging the history data for the probe (' || NEW.display_name || ')...',
                true, 's', 'SELECT pem.purge_probe_history(' || NEW.id || '::integer)',
                pem_server, pem_database, 's', false
            ) RETURNING jstid INTO purge_jstid;

            NEW.jstid := purge_jstid;
        END IF;
        RETURN NEW;
    ELSE
        IF NOT OLD.discard_history AND OLD.jstid IS NOT NULL THEN
            purge_jstid := OLD.jstid;
            OLD.jstid := NULL;
            DELETE FROM pem.jobstep WHERE jstid = purge_jstid;
        END IF;
        RETURN OLD;
    END IF;
END;
$function$ LANGUAGE 'plpgsql';

--
-- FUNCTION: pem.create_update_probe_objects_combo()
--
-- This function will helps us to maintain the purging job steps for each individual probe,
-- and parameters combination. It will update only the job steps, whose
-- lifetime has been modified. Also, creates new job steps for the object-probe
-- combination.
CREATE OR REPLACE FUNCTION pem.create_update_probe_objects_combo()
    RETURNS void AS
$function$
DECLARE
    info_curs    REFCURSOR;
    info         RECORD;
BEGIN
    -- Fetch the new/updated probe-object parameters combination.
    OPEN info_curs FOR EXECUTE $SQL$
SELECT
    p.probe_id AS probe_id, c.pid AS pid, c.delete_on,
    COALESCE(p.parameter_value_list, c.objects) AS objects,
    COALESCE(p.lifetime, c.lifetime) AS lifetime
FROM
    pem.probe_target_without_discard_history p
    FULL OUTER JOIN pem.probe_objects_combo c ON (
        p.probe_id = c.pid AND p.parameter_value_list = c.objects
    )
WHERE
    c.pid IS NULL OR p.lifetime != c.lifetime OR c.delete_on IS NOT NULL OR (
        p.probe_id IS NULL AND (
            c.delete_on IS NULL OR c.delete_on > now()::date
        )
    )
$SQL$;

    LOOP
        FETCH info_curs INTO info;
        EXIT WHEN NOT FOUND;

        IF info.probe_id IS NULL THEN
            -- The probe-object is not available
            IF info.delete_on IS NULL THEN
                -- We have noticed it for the first time.
                -- Set the date on which it should be removed from the
                -- 'pem.probe_objects_combo' table.
                EXECUTE 'UPDATE pem.probe_objects_combo SET delete_on = $3::date WHERE pid = $1::integer AND objects = $2::text[]'
                USING info.pid, info.objects, (now() + ((info.lifetime + 5) * INTERVAL '1 days'))::date;
            ELSE
                -- Remove the combination from the 'pem.probe_objects_combo'
                -- table.
                DELETE FROM pem.probe_objects_combo
                WHERE pid = info.pid AND objects = info.objects;
            END IF;
        ELSE
            IF info.pid IS NULL THEN
                -- Insert the combination from the 'pem.probe_objects_combo'
                -- table.
                INSERT INTO pem.probe_objects_combo (pid, objects, lifetime)
                VALUES (info.probe_id, info.objects, info.lifetime);
            ELSE
                -- Update the lifetime, delete_on in the
                -- 'pem.probe_objects_combo' table.
                UPDATE pem.probe_objects_combo
                SET lifetime = info.lifetime, delete_on = NULL
                WHERE pid = info.probe_id AND objects = info.objects;
            END IF;
        END IF;
    END LOOP;
    CLOSE info_curs;
END;
$function$ LANGUAGE plpgsql;

--
-- TRIGGER FUNCTION: pem.run_job_to_update_probe_objects_combo()
--
-- This trigger function will update the job to update the purge jobsteps in
-- 24 hours.
CREATE OR REPLACE FUNCTION pem.run_job_to_update_probe_objects_combo()
    RETURNS trigger AS
$function$
DECLARE
    needs_update boolean;
BEGIN
    EXECUTE $SQL$SELECT NOT jobenabled OR jobnextrun IS NULL OR jobnextrun < now() FROM pem.job WHERE jobname = 'Update the probe-objects combination' AND issystemjob$SQL$ INTO needs_update;

    IF (needs_update IS NOT NULL AND needs_update = TRUE) THEN
        -- We will not update the purge job tasks immediately, there is
        -- no requirement to do it immediately.
        EXECUTE $SQL$UPDATE pem.job SET jobenabled = TRUE, jobnextrun = now() + INTERVAL '1 hours' WHERE jobname = 'Update the probe-objects combination' AND issystemjob$SQL$;
    END IF;
    RETURN NEW;
END;
$function$ LANGUAGE 'plpgsql';


-- Check for all purge object combinations trigger exists or not.
DO
$$
DECLARE
    pem_agent  integer;
BEGIN
    --  agent
    IF NOT EXISTS(
        SELECT 1
        FROM
            pg_trigger
        WHERE NOT tgisinternal AND
            tgrelid = 'pem.agent'::regclass AND
            tgname = 'update_purge_jobs_on_insert_agent')
    THEN
        CREATE TRIGGER update_purge_jobs_on_insert_agent AFTER INSERT ON pem.agent FOR STATEMENT EXECUTE PROCEDURE pem.run_job_to_update_probe_objects_combo();
    END IF;

    --  agent_server_binding
    IF NOT EXISTS(
        SELECT 1
        FROM
            pg_trigger
        WHERE NOT tgisinternal AND
            tgrelid = 'pem.agent_server_binding'::regclass AND
            tgname = 'update_purge_jobs_on_insert_asb')
    THEN
        CREATE TRIGGER update_purge_jobs_on_insert_asb AFTER INSERT ON pem.agent_server_binding FOR STATEMENT EXECUTE PROCEDURE pem.run_job_to_update_probe_objects_combo();
    END IF;

    --  Probe table
    IF NOT EXISTS(
        SELECT 1
        FROM
            pg_trigger
        WHERE NOT tgisinternal AND
            tgrelid = 'pem.probe'::regclass AND
            tgname = 'update_purge_jobs_on_insert_probe')
    THEN
        CREATE TRIGGER update_purge_jobs_on_insert_probe AFTER INSERT ON pem.probe FOR STATEMENT EXECUTE PROCEDURE pem.run_job_to_update_probe_objects_combo();
    END IF;

    --  Probe table
    IF NOT EXISTS(
        SELECT 1
        FROM
            pg_trigger
        WHERE NOT tgisinternal AND
            tgrelid = 'pem.probe'::regclass AND
            tgname = 'update_purge_jobs_on_update_probe')
    THEN
        CREATE TRIGGER update_purge_jobs_on_update_probe AFTER UPDATE OF default_lifetime ON pem.probe FOR EACH ROW EXECUTE PROCEDURE pem.run_job_to_update_probe_objects_combo();
    END IF;

    --  probe_config_table
    IF NOT EXISTS(
        SELECT 1
        FROM
            pg_trigger
        WHERE NOT tgisinternal AND
            tgrelid = 'pem.probe_config_table'::regclass AND
            tgname = 'update_purge_jobs_on_insert_probe_config_table')
    THEN
        CREATE TRIGGER update_purge_jobs_on_insert_probe_config_table AFTER INSERT OR DELETE ON pem.probe_config_table FOR STATEMENT EXECUTE PROCEDURE pem.run_job_to_update_probe_objects_combo();
    END IF;

    --  probe_config_table
    IF NOT EXISTS(
        SELECT 1
        FROM
            pg_trigger
        WHERE NOT tgisinternal AND
            tgrelid = 'pem.probe_config_table'::regclass AND
            tgname = 'update_purge_jobs_on_update_probe_config_table')
    THEN
        CREATE TRIGGER update_purge_jobs_on_update_probe_config_table AFTER UPDATE OF lifetime ON pem.probe_config_table FOR EACH ROW EXECUTE PROCEDURE pem.run_job_to_update_probe_objects_combo();
    END IF;

    --  probe_config_schema
    IF NOT EXISTS(
        SELECT 1
        FROM
            pg_trigger
        WHERE NOT tgisinternal AND
            tgrelid = 'pem.probe_config_schema'::regclass AND
            tgname = 'update_purge_jobs_on_insert_probe_config_schema')
    THEN
        CREATE TRIGGER update_purge_jobs_on_insert_probe_config_schema AFTER INSERT OR DELETE ON pem.probe_config_schema FOR STATEMENT EXECUTE PROCEDURE pem.run_job_to_update_probe_objects_combo();
    END IF;


    --  probe_config_schema
    IF NOT EXISTS(
        SELECT 1
        FROM
            pg_trigger
        WHERE NOT tgisinternal AND
            tgrelid = 'pem.probe_config_schema'::regclass AND
            tgname = 'update_purge_jobs_on_update_probe_config_schema')
    THEN
        CREATE TRIGGER update_purge_jobs_on_update_probe_config_schema AFTER UPDATE OF lifetime ON pem.probe_config_schema FOR EACH ROW EXECUTE PROCEDURE pem.run_job_to_update_probe_objects_combo();
    END IF;

    --  probe_config_database
    IF NOT EXISTS(
        SELECT 1
        FROM
            pg_trigger
        WHERE NOT tgisinternal AND
            tgrelid = 'pem.probe_config_database'::regclass AND
            tgname = 'update_purge_jobs_on_insert_probe_config_database')
    THEN
        CREATE TRIGGER update_purge_jobs_on_insert_probe_config_database AFTER INSERT OR DELETE ON pem.probe_config_database FOR STATEMENT EXECUTE PROCEDURE pem.run_job_to_update_probe_objects_combo();
    END IF;

    --  probe_config_database
    IF NOT EXISTS(
        SELECT 1
        FROM
            pg_trigger
        WHERE NOT tgisinternal AND
            tgrelid = 'pem.probe_config_database'::regclass AND
            tgname = 'update_purge_jobs_on_update_probe_config_database')
    THEN
        CREATE TRIGGER update_purge_jobs_on_update_probe_config_database AFTER UPDATE OF lifetime ON pem.probe_config_database FOR EACH ROW EXECUTE PROCEDURE pem.run_job_to_update_probe_objects_combo();
    END IF;

    --  probe_config_server
    IF NOT EXISTS(
        SELECT 1
        FROM
            pg_trigger
        WHERE NOT tgisinternal AND
            tgrelid = 'pem.probe_config_server'::regclass AND
            tgname = 'update_purge_jobs_on_insert_probe_config_server')
    THEN
        CREATE TRIGGER update_purge_jobs_on_insert_probe_config_server AFTER INSERT OR DELETE ON pem.probe_config_server FOR STATEMENT EXECUTE PROCEDURE pem.run_job_to_update_probe_objects_combo();
    END IF;

    --  probe_config_server
    IF NOT EXISTS(
        SELECT 1
        FROM
            pg_trigger
        WHERE NOT tgisinternal AND
            tgrelid = 'pem.probe_config_server'::regclass AND
            tgname = 'update_purge_jobs_on_update_probe_config_server')
    THEN
        CREATE TRIGGER update_purge_jobs_on_update_probe_config_server AFTER UPDATE OF lifetime ON pem.probe_config_server FOR EACH ROW EXECUTE PROCEDURE pem.run_job_to_update_probe_objects_combo();
    END IF;

    --  probe_config_agent
    IF NOT EXISTS(
        SELECT 1
        FROM
            pg_trigger
        WHERE NOT tgisinternal AND
            tgrelid = 'pem.probe_config_agent'::regclass AND
            tgname = 'update_purge_jobs_on_insert_probe_config_agent')
    THEN
        CREATE TRIGGER update_purge_jobs_on_insert_probe_config_agent AFTER INSERT OR DELETE ON pem.probe_config_agent FOR STATEMENT EXECUTE PROCEDURE pem.run_job_to_update_probe_objects_combo();
    END IF;

    --  probe_config_agent
    IF NOT EXISTS(
        SELECT 1
        FROM
            pg_trigger
        WHERE NOT tgisinternal AND
            tgrelid = 'pem.probe_config_agent'::regclass AND
            tgname = 'update_purge_jobs_on_update_probe_config_agent')
    THEN
        CREATE TRIGGER update_purge_jobs_on_update_probe_config_agent AFTER UPDATE OF lifetime ON pem.probe_config_agent FOR EACH ROW EXECUTE PROCEDURE pem.run_job_to_update_probe_objects_combo();
    END IF;

    --  probe_config_sequence
    IF NOT EXISTS(
        SELECT 1
        FROM
            pg_trigger
        WHERE NOT tgisinternal AND
            tgrelid = 'pem.probe_config_sequence'::regclass AND
            tgname = 'update_purge_jobs_on_insert_probe_config_sequence')
    THEN
        CREATE TRIGGER update_purge_jobs_on_insert_probe_config_sequence AFTER INSERT OR DELETE ON pem.probe_config_sequence FOR STATEMENT EXECUTE PROCEDURE pem.run_job_to_update_probe_objects_combo();
    END IF;

    --  probe_config_sequence
    IF NOT EXISTS(
        SELECT 1
        FROM
            pg_trigger
        WHERE NOT tgisinternal AND
            tgrelid = 'pem.probe_config_sequence'::regclass AND
            tgname = 'update_purge_jobs_on_update_probe_config_sequence')
    THEN
        CREATE TRIGGER update_purge_jobs_on_update_probe_config_sequence AFTER UPDATE OF lifetime ON pem.probe_config_sequence FOR EACH ROW EXECUTE PROCEDURE pem.run_job_to_update_probe_objects_combo();
    END IF;

    --  probe_config_index
    IF NOT EXISTS(
        SELECT 1
        FROM
            pg_trigger
        WHERE NOT tgisinternal AND
            tgrelid = 'pem.probe_config_index'::regclass AND
            tgname = 'update_purge_jobs_on_insert_probe_config_index')
    THEN
        CREATE TRIGGER update_purge_jobs_on_insert_probe_config_index AFTER INSERT OR DELETE ON pem.probe_config_index FOR STATEMENT EXECUTE PROCEDURE pem.run_job_to_update_probe_objects_combo();
    END IF;

    --  probe_config_index
    IF NOT EXISTS(
        SELECT 1
        FROM
            pg_trigger
        WHERE NOT tgisinternal AND
            tgrelid = 'pem.probe_config_index'::regclass AND
            tgname = 'update_purge_jobs_on_update_probe_config_index')
    THEN
        CREATE TRIGGER update_purge_jobs_on_update_probe_config_index AFTER UPDATE OF lifetime ON pem.probe_config_index FOR EACH ROW EXECUTE PROCEDURE pem.run_job_to_update_probe_objects_combo();
    END IF;

    --  probe_config_view
    IF NOT EXISTS(
        SELECT 1
        FROM
            pg_trigger
        WHERE NOT tgisinternal AND
            tgrelid = 'pem.probe_config_view'::regclass AND
            tgname = 'update_purge_jobs_on_insert_probe_config_view')
    THEN
        CREATE TRIGGER update_purge_jobs_on_insert_probe_config_view AFTER INSERT OR DELETE ON pem.probe_config_view FOR STATEMENT EXECUTE PROCEDURE pem.run_job_to_update_probe_objects_combo();
    END IF;

    --  probe_config_view
    IF NOT EXISTS(
        SELECT 1
        FROM
            pg_trigger
        WHERE NOT tgisinternal AND
            tgrelid = 'pem.probe_config_view'::regclass AND
            tgname = 'update_purge_jobs_on_update_probe_config_view')
    THEN
        CREATE TRIGGER update_purge_jobs_on_update_probe_config_view AFTER UPDATE OF lifetime ON pem.probe_config_view FOR EACH ROW EXECUTE PROCEDURE pem.run_job_to_update_probe_objects_combo();
    END IF;

    --  probe_config_function
    IF NOT EXISTS(
        SELECT 1
        FROM
            pg_trigger
        WHERE NOT tgisinternal AND
            tgrelid = 'pem.probe_config_function'::regclass AND
            tgname = 'update_purge_jobs_on_insert_probe_config_function')
    THEN
        CREATE TRIGGER update_purge_jobs_on_insert_probe_config_function AFTER INSERT OR DELETE ON pem.probe_config_function FOR STATEMENT EXECUTE PROCEDURE pem.run_job_to_update_probe_objects_combo();
    END IF;

    --  probe_config_function
    IF NOT EXISTS(
        SELECT 1
        FROM
            pg_trigger
        WHERE NOT tgisinternal AND
            tgrelid = 'pem.probe_config_function'::regclass AND
            tgname = 'update_purge_jobs_on_update_probe_config_function')
    THEN
        CREATE TRIGGER update_purge_jobs_on_update_probe_config_function AFTER UPDATE OF lifetime ON pem.probe_config_function FOR EACH ROW EXECUTE PROCEDURE pem.run_job_to_update_probe_objects_combo();
    END IF;

    --  probe_config_function
    IF NOT EXISTS(
        SELECT 1
        FROM
            pg_trigger
        WHERE NOT tgisinternal AND
            tgrelid = 'pemdata.oc_database'::regclass AND
            tgname = 'update_purge_jobs_on_insert_database')
    THEN
        CREATE TRIGGER update_purge_jobs_on_insert_database AFTER INSERT OR DELETE ON pemdata.oc_database FOR STATEMENT EXECUTE PROCEDURE pem.run_job_to_update_probe_objects_combo();
    END IF;

    --  pem.probe
    IF NOT EXISTS(
        SELECT 1
        FROM
            pg_trigger
        WHERE NOT tgisinternal AND
            tgrelid = 'pem.probe'::regclass AND
            tgname = 'create_delete_purge_probe_jobstep_trigger')
    THEN
        CREATE TRIGGER create_delete_purge_probe_jobstep_trigger AFTER INSERT OR DELETE ON pem.probe FOR EACH ROW EXECUTE PROCEDURE pem.create_delete_probe_purge_jobstep();
    END IF;

    GRANT EXECUTE ON FUNCTION pem.run_job_to_update_probe_objects_combo() TO pem_admin;
    GRANT EXECUTE ON FUNCTION pem.create_update_probe_objects_combo() TO pem_admin;
    GRANT ALL ON TABLE pem.probe_objects_combo TO pem_admin;

END;
$$ LANGUAGE 'plpgsql';

UPDATE pem.probe_column
SET classification = 'k'
WHERE
    internal_name = 'dir_type' AND
    probe_id = (SELECT id FROM pem.probe WHERE internal_name = 'data_log_file_analysis');

ALTER TABLE pemdata.data_log_file_analysis DROP CONSTRAINT data_log_file_analysis_pkey;

ALTER TABLE pemdata.data_log_file_analysis ADD PRIMARY KEY  (server_id, name, dir_type);

CREATE OR REPLACE FUNCTION pemdata.copy_data_log_file_analysis_to_history()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
BEGIN
    IF (TG_OP = 'INSERT' OR TG_OP = 'UPDATE') THEN
        INSERT INTO pemhistory.data_log_file_analysis (recorded_time, server_id, name, path, device_id, dir_type) VALUES (NEW.recorded_time, NEW.server_id, NEW.name, NEW.path, NEW.device_id, NEW.dir_type);
    ELSIF EXISTS(SELECT 1 FROM pem.server WHERE id = OLD.server_id) THEN
        INSERT INTO pemhistory.data_log_file_analysis (server_id, name, dir_type) VALUES (OLD.server_id, OLD.name, OLD.dir_type);
    END IF;
    RETURN NEW;
END;
$function$;

DELETE FROM pemhistory.data_log_file_analysis WHERE dir_type IS NULL;
ALTER TABLE pemhistory.data_log_file_analysis ALTER COLUMN dir_type SET NOT NULL;
DROP INDEX pemhistory.data_log_file_analysis_keyidx;
CREATE INDEX data_log_file_analysis_keyidx ON pemhistory.data_log_file_analysis (server_id, name, dir_type);

DO
$function$
DECLARE
    probe_curs     CURSOR FOR SELECT id, display_name FROM pem.probe
        WHERE NOT discard_history AND jstid IS NULL;
    purge_jobid    integer;
    purge_jstid    integer;
    job_id         integer;
    pem_agent      integer;
    job_step_count integer;
    pem_server     integer;
    pem_database   varchar;
    job_name       varchar;
BEGIN
    --
    -- Fetch the server-id, database name for the PEM database server
    -- And, disable the default purge-job, which is not needed any more.
    --
    -- We will keep this information to make sure, we have pem-server, and
    -- database information available for setting up the individual purge job
    -- steps based on the probe-object combination.
    UPDATE pem.jobstep SET jstenabled = FALSE
    WHERE jstjobid = (
        SELECT j.jobid FROM pem.job j
        WHERE j.issystemjob AND j.jobname = 'Database cleanup'
        ORDER BY 1 LIMIT 1
    ) AND jstname = 'Database cleanup'
    RETURNING server_id, database_name, jstjobid, (
        SELECT agent_id FROM pem.job WHERE jobid=jstjobid
    )
    INTO pem_server, pem_database, purge_jobid, pem_agent;

    -- Let the purge job run independently.
    UPDATE pem.job SET dependent_on_job=NULL WHERE jobid=purge_jobid;

    UPDATE pem.schedule SET
        jschours = '{f,t,f,f,f,t,f,f,f,t,f,f,f,t,f,f,f,t,f,f,f,t,f,f}',
        jscmonthdays = '{t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t}'
        WHERE jscjobid = purge_jobid;

    --
    -- Generate the update probe-objects combination job
    -- It will run 10 minutes after installation.
    -- Customer site, it observed that 'Update the probe-object comination' job not exists
    -- so create the job (if not exists).

    SELECT jobid INTO job_id FROM pem.job WHERE jobname = 'Update the probe-objects combination' AND agent_id = pem_agent;

    IF (NOT FOUND) THEN
        RAISE INFO E'Creating the probe-objects combination job!';

        --
        -- Generate the update probe-objects combination job
        -- it will run 10 minutes after installation.
        --
        INSERT INTO pem.job(
            jobname, jobdesc, agent_id, issystemjob, jobnextrun
        ) VALUES (
            'Update the probe-objects combination',
            'This job updates/inserts the record of the probe, parameter_value_list in the ''pem.probe_objects_combo'' table.',
            pem_agent, TRUE, now() + INTERVAL '10 minutes'
        ) RETURNING jobid INTO job_id;

        INSERT INTO pem.jobstep(
            jstjobid, jstname, jstdesc, jstkind, jstcode, server_id, database_name
        ) VALUES (
            job_id, 'Update the probe-objects combination',
            'This job-step updates/inserts the record of the probe, parameter_value_list in the ''pem.probe_objects_combo'' table.',
            's', 'SELECT pem.create_update_probe_objects_combo()', pem_server,
            pem_database
        );

        -- Let's make sure 'Purge deleted custom probes' job does not run, when
        -- we're updating the probe-objects combination task.
        UPDATE pem.job SET
            dependent_on_job=ARRAY(
                SELECT j.jobid FROM pem.job j
                WHERE j.issystemjob AND j.jobname = 'Update the probe-objects combination'
            )::int[],
            execute_on_dep_job_status='i'
        WHERE jobname='Purge deleted custom probes' AND issystemjob;

        FOR rec IN probe_curs
        LOOP
            EXECUTE 'SELECT COUNT(*) FROM pem.jobstep WHERE jstname = ' || '''' || 'Purge data (' || rec.display_name || ')' || ''''
            INTO job_step_count;
            IF (job_step_count = 0) THEN
                INSERT INTO pem.jobstep(
                    jstjobid, jstname, jstdesc, jstenabled, jstkind, jstcode, server_id,
                    database_name, jstonerror, jstsetenvironment
                    ) VALUES (
                    purge_jobid, 'Purge data (' || rec.display_name || ')',
                    'Purging the history data for the probe (' || rec.display_name || ')...',
                    true, 's', 'SELECT pem.purge_probe_history(' || rec.id || '::integer)',
                    pem_server, pem_database, 'i', false
                ) RETURNING jstid INTO purge_jstid;
                UPDATE pem.probe SET jstid = purge_jstid WHERE id = rec.id;
            END IF;
        END LOOP;
    END IF;

    -- Create job only if 'lockrowid' column not exists in lock_info probe.
    IF NOT EXISTS (
        SELECT 1
        FROM
            information_schema.columns
        WHERE
            table_schema = 'pemdata' AND
            table_name   = 'lock_info' AND
            column_name = 'lockrowid'
    ) THEN
        INSERT INTO pem.job(jobname, agent_id, issystemjob, jobnextrun, jobdesc)
            VALUES (
                'Upgrade lock_info probe', pem_agent, TRUE, now() + INTERVAL '5 minutes',
                'This job will upgrade the lock_info, please do not enable/disble it.'
            ) RETURNING jobid INTO job_id;

        INSERT INTO pem.jobstep(
            jstjobid, jstname, jstkind, server_id, database_name, jstcode, jstdesc
          ) VALUES (
                job_id, 'Alter the schema of the lock_info probe',
                's', pem_server, pem_database,
                $QUERY$
                    ALTER TABLE pem.probe DISABLE TRIGGER USER;

                    UPDATE
                        pem.probe
                    SET
                        deleted=TRUE, enabled_by_default=FALSE, probe_code=
                        $sql$
                        /* pid could be NULL for prepared transactions, and DB oid could be 0
                         * for shared relations, hence the LEFT JOIN being used below and the
                         * convoluted way of getting database OID.
                         *
                         * The side effect of this is that the locks on shared objects will
                         * appear to be taken under some database, specifically, under the
                         * database to which the backend process is connected. And if the lock
                         * on the shared object is taken by a prepared transaction, only then
                         * would we see an empty string in database_name.
                         *
                         * Note: We do not support reporting on the 'userlock' locktype; this
                         * locktype is provided by ancient contrib/userlock module.
                         * TODO: Research and implement support for this.
                         */
                        SELECT ROW_NUMBER() OVER (PARTITION BY l.pid) AS lockrowid,
                            COALESCE(d.datname, '')            AS database_name,
                            COALESCE(l.pid::bigint, -1)        AS procpid,
                            CASE
                                WHEN l.locktype IN ('relation', 'extend', 'page', 'tuple') THEN
                                     l.relation::text::numeric
                                WHEN l.locktype = 'transactionid' THEN
                                     transactionid::text::numeric
                                WHEN l.locktype = 'virtualxid' THEN
                                     regexp_replace(l.virtualxid, '/', '.')::numeric
                                WHEN l.locktype IN ('object', 'advisory') THEN
                                     classid::text::numeric
                                ELSE
                                     COALESCE(
                                         l.relation::text::numeric, transactionid::text::numeric,
                                         regexp_replace(l.virtualxid, '/', '.')::numeric,
                                         classid::text::numeric, -1
                                     )
                            END AS objid,
                            COALESCE(l.page::bigint, l.objid::bigint, -1)  AS objsubid,
                            COALESCE(l.tuple::bigint, l.objsubid::bigint, -1) AS objsubsubid,
                                     l.locktype, l.mode AS lockmode, l.granted AS lockgranted
                        FROM pg_catalog.pg_locks AS l LEFT JOIN
                             pg_catalog.pg_stat_activity AS sa ON l.pid = sa.pid JOIN
                             pg_catalog.pg_database AS d ON sa.datid = d.oid
                        $sql$
                    WHERE internal_name = 'lock_info';

                    UPDATE
                        pem.probe_server_version
                    SET
                        probe_code=
                        $sql$
                            SELECT ROW_NUMBER() OVER (PARTITION BY l.pid) AS lockrowid,
                                COALESCE(d.datname, '')            AS database_name,
                                COALESCE(l.pid::bigint, -1)        AS procpid,
                                CASE
                                    WHEN l.locktype IN ('relation', 'extend', 'page', 'tuple') THEN
                                         l.relation::text::numeric
                                    WHEN l.locktype = 'transactionid' THEN
                                         transactionid::text::numeric
                                    WHEN l.locktype = 'virtualxid' THEN
                                         regexp_replace(l.virtualxid, '/', '.')::numeric
                                    WHEN l.locktype IN ('object', 'advisory') THEN
                                         classid::text::numeric
                                    ELSE
                                        COALESCE(
                                            l.relation::text::numeric, transactionid::text::numeric,
                                            regexp_replace(l.virtualxid, '/', '.')::numeric,
                                            classid::text::numeric, -1
                                        )
                                END AS objid,
                                COALESCE(l.page::bigint, l.objid::bigint, -1)  AS objsubid,
                                COALESCE(l.tuple::bigint, l.objsubid::bigint, -1) AS objsubsubid,
                                         l.locktype, l.mode AS lockmode, l.granted AS lockgranted
                            FROM pg_catalog.pg_locks AS l LEFT JOIN
                                 pg_catalog.pg_stat_activity AS sa ON l.pid = sa.procpid JOIN
                                 pg_catalog.pg_database AS d ON sa.datid = d.oid
                        $sql$
                    WHERE probe_id = (SELECT id FROM pem.probe WHERE internal_name='lock_info')
                        AND server_version_id IN (10900, 10901, 20900, 20901);

                    UPDATE
                        pem.probe_server_version
                    SET
                        probe_code=NULL
                    WHERE
                        probe_id = (SELECT id FROM pem.probe WHERE internal_name='lock_info')
                        AND server_version_id
                        IN (10902, 10903, 10904, 10905, 10906, 20902, 20903, 20904, 20905, 20906);

                    INSERT INTO pem.probe_column (
                        probe_id, internal_name, display_name, display_position, classification,
                        sql_data_type, unit_of_value, calculate_pit, discard_history,
                        pit_by_default, is_graphable
                    ) VALUES (
                        (SELECT id FROM pem.probe WHERE internal_name='lock_info'), 'lockrowid',
                            'Row ID', 1, 'k', 'bigint', '', false, false, false, false
                    );

                    ALTER TABLE pem.probe ENABLE TRIGGER USER;
                    ALTER TABLE pemdata.lock_info ADD COLUMN lockrowid bigint NOT NULL DEFAULT 1;
                    UPDATE
                        pemdata.lock_info y
                    SET
                        lockrowid=new_lockrowid
                    FROM (
                        SELECT
                            recorded_time, server_id, database_name, procpid, objid, objsubid,
                            objsubsubid, locktype, lockmode, lockgranted, ROW_NUMBER() OVER (
                                PARTITION BY server_id, procpid
                            ) AS new_lockrowid
                            FROM pemdata.lock_info
                    ) x
                    WHERE (
                        y.recorded_time, y.server_id, y.database_name, y.procpid, y.objid,
                        y.objsubid, y.objsubsubid, y.locktype, y.lockmode, y.lockgranted
                    ) = (
                        x.recorded_time, x.server_id, x.database_name, x.procpid, x.objid,
                        x.objsubid, x.objsubsubid, x.locktype, x.lockmode, x.lockgranted
                    );

                    ALTER TABLE pemdata.lock_info DROP CONSTRAINT lock_info_pkey;
                    ALTER TABLE pemdata.lock_info ADD CONSTRAINT lock_info_pkey PRIMARY KEY (server_id, lockrowid, procpid);

                    ALTER TABLE pemhistory.lock_info ADD COLUMN lockrowid bigint NOT NULL DEFAULT 1;

                    UPDATE pemhistory.lock_info y SET lockrowid=new_lockrowid
                    FROM
                    (
                        SELECT
                            recorded_time, server_id, database_name, procpid, objid, objsubid,
                            objsubsubid, locktype, lockmode, lockgranted, ROW_NUMBER() OVER (
                                PARTITION BY recorded_time, server_id, procpid
                            ) AS new_lockrowid
                        FROM pemhistory.lock_info
                    ) x
                    WHERE (
                        y.recorded_time, y.server_id, y.database_name, y.procpid, y.objid,
                        y.objsubid, y.objsubsubid, y.locktype, y.lockmode, y.lockgranted
                    ) = (
                        x.recorded_time, x.server_id, x.database_name, x.procpid, x.objid,
                        x.objsubid, x.objsubsubid, x.locktype, x.lockmode, x.lockgranted
                    );

                    DROP INDEX pemhistory.lock_info_keyidx;
                    CREATE INDEX lock_info_keyidx ON pemhistory.lock_info (server_id, lockrowid, procpid);

                    ALTER TABLE pem.probe DISABLE TRIGGER USER;
                    UPDATE pem.probe SET deleted=FALSE, enabled_by_default=TRUE WHERE internal_name='lock_info';
                    ALTER TABLE pem.probe ENABLE TRIGGER USER;
                $QUERY$,
                'This job will set true for the flag to enable the lock_info probe by default, also - make sure, it is not marked as deleted.');
    END IF;
END;
$function$ LANGUAGE 'plpgsql';

CREATE OR REPLACE FUNCTION pem.startup(server_desc text, server_name text, server_host text, server_port int, server_database text, server_ssl int,
                    user_name text, passwd text, ser_group text, agentid int, agent_database text)
  RETURNS void AS
$BODY$
DECLARE
    job_id    integer;
    sg_id     integer;
    serverid  integer := 1;
    is_active boolean;
    name      text;
    tmpid     integer;
    dbname    text := current_database();
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
        INSERT INTO pem.server (description, server, port, database, ssl) VALUES (server_desc, server_name, server_port, server_database, server_ssl) RETURNING id INTO serverid;

        -- Set the options of the PEM server
        INSERT INTO pem.server_option (server_id, pem_user, username, server_group_id) VALUES (serverid, user_name, user_name, sg_id);
    ELSE
        UPDATE pem.server SET description = server_desc, server = server_name, port = server_port, database = server_database, ssl = server_ssl, active = 't' WHERE id = serverid;

        UPDATE pem.server_option SET pem_user = user_name, username = user_name, server_group_id = sg_id WHERE server_id = serverid;
    END IF;

    -- Create Agent Server Binding
    INSERT INTO pem.agent_server_binding (agent_id, server_id, server, port, username, database, password) VALUES (agentid, serverid, server_host, server_port, user_name, agent_database, passwd);


    -- Check if the job already exists.
    SELECT jobid INTO job_id FROM pem.job WHERE jobname = 'Database cleanup' AND agent_id = agentid;

    IF (NOT FOUND) THEN
        -- Create data purging job.
        INSERT INTO pem.job(jobname, jobdesc, agent_id, issystemjob) VALUES('Database cleanup', 'This job runs periodically to purge old data from the database.', agentid, true) RETURNING jobid INTO job_id;
    END IF;

    -- Check if the job step already exists.
    SELECT jstid INTO tmpid FROM pem.jobstep WHERE jstname = 'Database cleanup' AND jstjobid = job_id;

    IF (NOT FOUND) THEN
        -- Create data purging step.
        INSERT INTO pem.jobstep(
            jstjobid, jstname, jstenabled, jstdesc, jstkind, jstcode,
            server_id, database_name
        ) VALUES (
            job_id, 'Database cleanup', false,
            'This job step runs periodically to purge old data from the database.',
            's', 'SELECT pem.purge_data()',
            serverid, dbname
        );
    ELSE
        UPDATE pem.jobstep SET jstenabled = False
        WHERE jstjobid = job_id AND jstid = tmpid;
    END IF;

    -- Check if the job schedule already exists.
    SELECT jscid INTO tmpid FROM pem.schedule WHERE jscname = 'Database cleanup' AND jscjobid = job_id;

    IF (NOT FOUND) THEN
        -- Create data purging schedule.
        INSERT INTO pem.schedule(
            jscjobid, jscname, jscdesc,
            jscminutes, jschours, jscmonths, jscweekdays,
            jscmonthdays
        ) VALUES(
            job_id, 'Database cleanup', 'This job schedule runs periodically to purge old data from the database.',
            '{t,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f}',
            '{f,t,f,f,f,t,f,f,f,t,f,f,f,t,f,f,f,t,f,f,f,t,f,f}',
            '{t,t,t,t,t,t,t,t,t,t,t,t}', '{t,t,t,t,t,t,t}',
            '{t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t}');
    ELSE
        UPDATE pem.schedule SET
            jschours = '{f,t,f,f,f,t,f,f,f,t,f,f,f,t,f,f,f,t,f,f,f,t,f,f}',
            jscmonthdays = '{t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t}'
        WHERE
            jscjobid = job_id AND jscid = tmpid;
    END IF;

    -- check if the job already exists.
    SELECT jobid INTO job_id FROM pem.job WHERE jobname = 'Update the probe-objects combination' AND agent_id = agentid;

    IF (NOT FOUND) THEN
        --
        -- Generate the update probe-objects combination job
        -- it will run 10 minutes after installation.
        --
        -- Let agent fetch the information about the server, and host-machine
        -- to  determine the actual probes to run, which generates actual
        -- combination.
        INSERT INTO pem.job(
            jobname, jobdesc, agent_id, issystemjob, jobnextrun
        ) VALUES (
            'Update the probe-objects combination',
            'This job updates/inserts the record of the probe, parameter_value_list in the ''pem.probe_objects_combo'' table.',
            agentid, true, now() + interval '10 minutes'
        ) RETURNING jobid INTO job_id;
    END IF;

    -- check if the job step already exists.
    SELECT jstid INTO tmpid FROM pem.jobstep WHERE jstname = 'Update the probe-objects combination' AND jstjobid = job_id;

    IF (NOT FOUND) THEN
        INSERT INTO pem.jobstep(
            jstjobid, jstname, jstdesc, jstkind, jstcode,
            server_id, database_name
        ) VALUES (
            job_id, 'Database cleanup',
            'This job step updates the purge-job tasks on demand.',
            's', 'SELECT pem.create_update_probe_objects_combo()',
            serverid, dbname
        );
    ELSE
        UPDATE pem.jobstep SET jstenabled = TRUE
        WHERE jstid = tmpid AND jstjobid = job_id;
    END IF;

    -- Check if the job already exists.
    SELECT jobid INTO job_id FROM pem.job WHERE jobname = 'Audit log table cleanup' AND agent_id = agentid;

    IF (NOT FOUND) THEN
        -- Create data purging job.
        INSERT INTO pem.job(jobname, jobdesc, agent_id, issystemjob) VALUES('Audit log table cleanup', 'This job runs periodically to purge old data from the audit log table.', agentid, true) RETURNING jobid INTO job_id;
    END IF;

    -- Check if the job step already exists.
    SELECT jstname INTO name FROM pem.jobstep WHERE jstname = 'Audit log table cleanup' AND jstjobid = job_id;

    IF (NOT FOUND) THEN
        -- Create data purging step.
        INSERT INTO pem.jobstep(jstjobid, jstname, jstdesc, jstkind, jstcode, server_id, database_name) VALUES (job_id, 'Audit log table cleanup','This job step runs periodically to purge old data from the audit log table.', 's',
            'SELECT pem.purge_audit_log()', serverid, dbname);
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
        INSERT INTO pem.job(jobname, jobdesc, agent_id, issystemjob) VALUES('Server log table cleanup', 'This job runs periodically to purge old data from the server log table.', agentid, true) RETURNING jobid INTO job_id;
    END IF;

    -- Check if the job step already exists.
    SELECT jstname INTO name FROM pem.jobstep WHERE jstname = 'Server log table cleanup' AND jstjobid = job_id;

    IF (NOT FOUND) THEN
        -- Create data purging step.
        INSERT INTO pem.jobstep(jstjobid, jstname, jstdesc, jstkind, jstcode, server_id, database_name) VALUES (job_id, 'Server log table cleanup','This job step runs periodically to purge old data from the server log table.', 's',
        'SELECT pem.purge_server_log()', serverid, dbname);
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
        INSERT INTO pem.job(jobname, jobdesc, agent_id, issystemjob) VALUES('Probe log table cleanup', 'This job runs periodically to purge old data from the probe log table.', agentid, true) RETURNING jobid INTO job_id;
    END IF;

    -- Check if the job step already exists.
    SELECT jstname INTO name FROM pem.jobstep WHERE jstname = 'Probe log table cleanup' AND jstjobid = job_id;

    IF (NOT FOUND) THEN
        -- Create data purging step.
        INSERT INTO pem.jobstep(jstjobid, jstname, jstdesc, jstkind, jstcode, server_id, database_name) VALUES (job_id, 'Probe log table cleanup','This job step runs periodically to purge old data from the probe log table.', 's',
        'SELECT pem.purge_probe_log()', serverid, dbname);
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
        INSERT INTO pem.job(jobname, jobdesc, agent_id, issystemjob) VALUES('SMTP spool table cleanup', 'This job runs periodically to purge old data from the smtp spool table.', agentid, true) RETURNING jobid INTO job_id;
    END IF;

    -- Check if the job step already exists.
    SELECT jstname INTO name FROM pem.jobstep WHERE jstname = 'SMTP spool table cleanup' AND jstjobid = job_id;

    IF (NOT FOUND) THEN
        -- Create data purging step.
        INSERT INTO pem.jobstep(jstjobid, jstname, jstdesc, jstkind, jstcode, server_id, database_name) VALUES (job_id, 'SMTP spool table cleanup','This job step runs periodically to purge old data from the smtp spool table.', 's',
        'SELECT pem.purge_smtp_spool()', serverid, dbname);
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
        INSERT INTO pem.job(jobname, jobdesc, agent_id, issystemjob) VALUES('SNMP spool table cleanup', 'This job runs periodically to purge old data from the snmp spool table.', agentid, true) RETURNING jobid INTO job_id;
    END IF;

    -- Check if the job step already exists.
    SELECT jstname INTO name FROM pem.jobstep WHERE jstname = 'SNMP spool table cleanup' AND jstjobid = job_id;

    IF (NOT FOUND) THEN
        -- Create data purging step.
        INSERT INTO pem.jobstep(jstjobid, jstname, jstdesc, jstkind, jstcode, server_id, database_name) VALUES (job_id, 'SNMP spool table cleanup','This job step runs periodically to purge old data from the snmp spool table.', 's',
        'SELECT pem.purge_snmp_spool()', serverid, dbname);
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
        INSERT INTO pem.job(jobname, jobdesc, agent_id, issystemjob) VALUES('Alert history table cleanup', 'This job runs periodically to purge old data from the alert history table.', agentid, true) RETURNING jobid INTO job_id;
    END IF;

    -- Check if the job step already exists.
    SELECT jstname INTO name FROM pem.jobstep WHERE jstname = 'Alert history table cleanup' AND jstjobid = job_id;

    IF (NOT FOUND) THEN
        -- Create data purging step.
        INSERT INTO pem.jobstep(jstjobid, jstname, jstdesc, jstkind, jstcode, server_id, database_name) VALUES (job_id, 'Alert history table cleanup','This job step runs periodically to purge old data from the alert history table.', 's',
        'SELECT pem.purge_alert_history()', serverid, dbname);
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
        INSERT INTO pem.job(jobname, jobdesc, agent_id, issystemjob) VALUES('Job log table cleanup', 'This job runs periodically to purge old data from the job log table.', agentid, true) RETURNING jobid INTO job_id;
    END IF;

    -- Check if the job step already exists.
    SELECT jstname INTO name FROM pem.jobstep WHERE jstname = 'Job log table cleanup' AND jstjobid = job_id;

    IF (NOT FOUND) THEN
        -- Create data purging step.
        INSERT INTO pem.jobstep(jstjobid, jstname, jstdesc, jstkind, jstcode, server_id, database_name) VALUES (job_id, 'Job log table cleanup','This job step runs periodically to purge old data from the job log table.', 's',
        'SELECT pem.purge_job_log()', serverid, dbname);
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
        INSERT INTO pem.job(jobname, jobdesc, agent_id, issystemjob) VALUES('Job purge the deleted charts', 'This job runs periodically to purge the deleted charts.', agentid, true) RETURNING jobid INTO job_id;
    END IF;

    -- Check if the job step already exists.
    SELECT jstname INTO name FROM pem.jobstep WHERE jstname = 'Job purge the deleted charts' AND jstjobid = job_id;

    IF (NOT FOUND) THEN
        -- Create data purging step.
        INSERT INTO pem.jobstep(jstjobid, jstname, jstdesc, jstkind, jstcode, server_id, database_name) VALUES (job_id, 'Job purge the deleted charts','This job step runs periodically to purge the deleted charts (we do not clean them up immediately).', 's',
        'SELECT pem.purge_deleted_charts()', serverid, dbname);
    END IF;

    -- Check if the job schedule already exists.
    SELECT jscname INTO name FROM pem.schedule WHERE jscname = 'Job purge the deleted charts' AND jscjobid = job_id;

    IF (NOT FOUND) THEN
        -- Create data purging schedule.
        INSERT INTO pem.schedule(jscjobid, jscname, jscdesc, jscminutes, jschours, jscweekdays, jscmonthdays, jscmonths) VALUES(job_id, 'Job purge the deleted charts', 'This job schedule runs periodically to purge the deletecd charts.', '{t,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f}', '{f,f,t,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f}','{t,t,t,t,t,t,t}', '{t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t}', '{t,t,t,t,t,t,t,t,t,t,t,t}');
    END IF;

    -- Check if the job already exists.
    SELECT jobid INTO job_id FROM pem.job WHERE jobname = 'Purge deleted custom probes' AND agent_id = agentid AND issystemjob;

    IF (NOT FOUND) THEN
        -- Create data purging job.
        INSERT INTO pem.job(
            jobname, jobdesc, agent_id, issystemjob,
            dependent_on_job, execute_on_dep_job_status
        ) VALUES(
            'Purge deleted custom probes', 'This job runs periodically to purge deleted custom probes and its data.',
            agentid, true, ARRAY(
                SELECT jobid FROM pem.job
                WHERE jobname='Update the probe-objects combination' AND issystemjob
            ), 'i'
        ) RETURNING jobid INTO job_id;
    ELSE
        -- Let's make sure 'Purge deleted custom probes' job does not run, when
        -- we're updating the probe-object combination.
        UPDATE pem.job SET dependent_on_job=ARRAY(
            SELECT jobid FROM pem.job
            WHERE jobname='Update the probe-objects combination' AND issystemjob
        ), execute_on_dep_job_status='i'
        WHERE jobid=job_id;
    END IF;

    -- Check if the job step already exists.
    SELECT jstname INTO name FROM pem.jobstep WHERE jstname = 'Purge deleted custom probes' AND jstjobid = job_id;

    IF (NOT FOUND) THEN
        -- Create data purging step.
        INSERT INTO pem.jobstep(jstjobid, jstname, jstdesc, jstkind, jstcode, server_id, database_name) VALUES (job_id, 'Purge deleted custom probes','This job runs periodically to purge deleted custom probes and its data.', 's',
        'SELECT pem.purge_deleted_probes()', serverid, dbname);
    END IF;

    -- Check if the job schedule already exists.
    SELECT jscname INTO name FROM pem.schedule WHERE jscname = 'Purge deleted custom probes' AND jscjobid = job_id;

    IF (NOT FOUND) THEN
        -- Create data purging schedule.
        INSERT INTO pem.schedule(jscjobid, jscname, jscdesc, jscminutes, jschours, jscweekdays, jscmonthdays, jscmonths) VALUES(job_id, 'Purge deleted custom probes', 'This job runs periodically to purge deleted custom probes and its data.', '{t,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f}', '{f,t,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f}','{t,t,t,t,t,t,t}', '{t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t}', '{t,t,t,t,t,t,t,t,t,t,t,t}');
    END IF;

    SELECT jobid INTO job_id FROM pem.job WHERE jobname = 'Database cleanup' AND agent_id = agentid;

    FOR rec IN probe_curs
    LOOP
        INSERT INTO pem.jobstep(
            jstjobid, jstname, jstdesc, jstenabled, jstkind, jstcode, server_id,
            database_name, jstonerror, jstsetenvironment
        ) VALUES (
            job_id, 'Purge data (' || rec.display_name || ')',
            'Purging the history data for the probe (' || rec.display_name || ')...',
            true, 's', 'SELECT pem.purge_probe_history(' || rec.id || '::integer)',
            serverid, dbname, 'i', false
        ) RETURNING jstid INTO tmpid;
        UPDATE pem.probe SET jstid = tmpid WHERE id = rec.id;
    END LOOP;

    -- Check if the job already exists.
    SELECT jobid INTO job_id FROM pem.job WHERE jobname = 'Check CA certificate expiry' AND agent_id = agentid;

    IF (NOT FOUND) THEN
        -- Create CA certificate expiry job.
        INSERT INTO pem.job(jobname, jobdesc, agent_id, issystemjob, jobnextrun) VALUES('Check CA certificate expiry', 'This job check the expiry of CA certificate.', agentid, true, now()) RETURNING jobid INTO job_id;
    END IF;

    -- Check if the job step already exists.
    SELECT jstname INTO name FROM pem.jobstep WHERE jstname = 'Check CA certificate expiry' AND jstjobid = job_id;

    IF (NOT FOUND) THEN
        -- Create data purging step.
        INSERT INTO pem.jobstep(jstjobid, jstname, jstdesc, jstkind, jstcode) VALUES (job_id, 'Check CA certificate expiry','This job step runs to check the expiry of CA certificate.', 'i', 'check_server_certificate_expiry');
    END IF;

END;
$BODY$ LANGUAGE plpgsql;

-- Update the probe-objects combination table
SELECT pem.create_update_probe_objects_combo();

-- Delete existing constraint of jobstep on probe table.
ALTER TABLE pem.probe DROP CONSTRAINT probe_purge_jobstep_id_fkey;

-- Add jobstep constraint on probe table.
ALTER TABLE pem.probe ADD CONSTRAINT
        probe_purge_jobstep_id_fkey FOREIGN KEY (jstid)
        REFERENCES pem.jobstep(jstid) ON UPDATE NO ACTION;

END TRANSACTION;
