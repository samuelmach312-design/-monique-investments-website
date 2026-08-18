/***************************************************************************
 *
 * Postgres Enterprise Manager
 *
 * Copyright (C) 2010 - 2025, EnterpriseDB Corporation. All rights reserved.
 *
 ***************************************************************************/

-- NOTE: This sql file is responsible for PEM 8.3.0 schema upgrade.

BEGIN TRANSACTION;

CREATE OR REPLACE FUNCTION pem.schema_version() RETURNS integer AS
'SELECT 202109211::integer;'
LANGUAGE 'sql' IMMUTABLE;
COMMENT ON FUNCTION pem.schema_version()
	IS 'Returns the version number of the PEM schema';

DO $DO$
DECLARE
    temp text;
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pem.roles WHERE component = 'manage_chart' ) THEN
        -- Create a role for manage chart module
        SELECT pem.create_role_for(
            'manage_chart',
            'Role for create, update, delete the custom charts.',
            ARRAY['pem_admin'],
            -- INSERT
            '{}'::text[],
            -- UPDATE
            '{}'::text[],
            -- DELETE
            '{}'::text[],
            -- ALL
            ARRAY[
                ARRAY['pem', 'chart'],
                ARRAY['pem', 'chart_metric'],
                ARRAY['pem', 'metrices_chart'],
                ARRAY['pem', 'capacity_report_chart']
            ]
        ) into temp;
    END IF;
END;
$DO$ LANGUAGE 'plpgsql';

DO $DO$
DECLARE
    temp text;
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pem.roles WHERE component = 'manage_dashboard') THEN
        -- Create a role for manage dashboard module
        SELECT pem.create_role_for(
            'manage_dashboard',
            'Role for create, update, delete the custom dashboard.',
            ARRAY['pem_admin', 'pem_manage_chart'],
            -- INSERT
            '{}'::text[],
            -- UPDATE
            '{}'::text[],
            -- DELETE
            '{}'::text[],
            -- ALL
            ARRAY[
                ARRAY['pem', 'dashboard'],
                ARRAY['pem', 'dashboard_chart'],
                ARRAY['pem', 'dashboard_section']
            ]
        ) into temp;
    END IF;
END;
$DO$ LANGUAGE 'plpgsql';

DO $DO$
BEGIN
    IF NOT EXISTS (SELECT id FROM pem.probe where internal_name = 'bdr_stat_relation') THEN
        --
        -- BDR Stat Relation Probe
        --
        INSERT INTO pem.probe
                (display_name, internal_name, collection_method, target_type_id,
                 enabled_by_default, force_enabled, default_execution_frequency,
                 default_lifetime, any_server_version, probe_code)
        VALUES
                ('BDR Stat Relation', 'bdr_stat_relation', 's', 200, false, false, 60, 30, true,
                'SELECT nspname, relname, relid, total_time, ninsert, nupdate, ndelete, ntruncate, shared_blks_hit,
                shared_blks_read, shared_blks_dirtied, shared_blks_written, blk_read_time, blk_write_time,
                lock_acquire_time FROM bdr.stat_relation;');

        INSERT INTO pem.probe_column
                (probe_id, internal_name, display_name, display_position, classification,
                sql_data_type, unit_of_value, calculate_pit, discard_history, pit_by_default, is_graphable)
        SELECT
                (SELECT max(id) FROM pem.probe),
                v.internal_name, v.display_name, v.display_position, v.classification,
                v.sql_data_type, v.unit_of_value, v.calculate_pit, v.discard_history, v.pit_by_default, v.is_graphable
        FROM
                (VALUES
                        ('nspname',                 'Relation Schema Name',             1, 'm', 'name',             '',   false, false, false, false),
                        ('relname',                 'Relation Name',                    2, 'k', 'name',             '',   false, false, false, false),
                        ('relid',                   'Relation OID',                     3, 'k', 'bigint',              '',   false, false, false, false),
                        ('total_time',              'Total Time',                       4, 'm', 'double precision', '',   false, false, false, false),
                        ('ninsert',                 '# Inserts',                        5, 'm', 'bigint',           '',   false, false, false, false),
                        ('nupdate',                 '# Updates',                        6, 'm', 'bigint',           '',   false, false, false, false),
                        ('ndelete',                 '# Deletes',                        7, 'm', 'bigint',           '',   false, false, false, false),
                        ('ntruncate',               '# Truncates',                      8, 'm', 'bigint',           '',   false, false, false, false),
                        ('shared_blks_hit',         '# Shared Blocks Cache Hit',    9, 'm', 'bigint',           '',   false, false, false, false),
                        ('shared_blks_read',        '# Shared Blocks Read',         10, 'm', 'bigint',          '',   false, false, false, false),
                        ('shared_blks_dirtied',     '# Shared Blocks Dirtied',      11, 'm', 'bigint',          '',   false, false, false, false),
                        ('shared_blks_written',     '# Shared Blocks Written',      12, 'm', 'bigint',          '',   false, false, false, false),
                        ('blk_read_time',           '# Time Spent Reading Blocks',  13, 'm', 'double precision','',   false, false, false, false),
                        ('blk_write_time',          '# Time Spent Writing Blocks',  14, 'm', 'double precision','',   false, false, false, false),
                        ('lock_acquire_time',       '# Time Spent Acquiring Blocks',15, 'm', 'double precision','',   false, false, false, false)
                ) v(internal_name, display_name, display_position, classification,
                        sql_data_type, unit_of_value, calculate_pit, discard_history, pit_by_default, is_graphable);
    END IF;
    IF NOT EXISTS (SELECT id FROM pem.probe where internal_name = 'bdr_stat_subscription') THEN
        --
        -- BDR Stat Subscription Probe
        --
        INSERT INTO pem.probe
                (display_name, internal_name, collection_method, target_type_id,
                 enabled_by_default, force_enabled, default_execution_frequency,
                 default_lifetime, any_server_version, probe_code)
        VALUES
                ('BDR Stat Subscription', 'bdr_stat_subscription', 's', 200, false, false, 60, 30, true,
                'SELECT sub_name, subid, nconnect, ncommit, nabort, nerror, nskippedtx, ninsert, nupdate, ndelete,
                ntruncate, nddl, ndeadlocks, nretries, shared_blks_hit, shared_blks_read, shared_blks_dirtied,
                shared_blks_written, blk_read_time, blk_write_time FROM bdr.stat_subscription;');

        INSERT INTO pem.probe_column
                (probe_id, internal_name, display_name, display_position, classification,
                sql_data_type, unit_of_value, calculate_pit, discard_history, pit_by_default, is_graphable)
        SELECT
                (SELECT max(id) FROM pem.probe),
                v.internal_name, v.display_name, v.display_position, v.classification,
                v.sql_data_type, v.unit_of_value, v.calculate_pit, v.discard_history, v.pit_by_default, v.is_graphable
        FROM
                (VALUES
                        ('sub_name',            'Subscription Name',                        1, 'k', 'name',             '',   false, false, false, false),
                        ('subid',               'Subscription OID',                         2, 'k', 'bigint',              '',   false, false, false, false),
                        ('nconnect',            '# Subscription Connected Upstream',        3, 'm', 'bigint',           '',   false, false, false, false),
                        ('ncommit',             '# Commits',                                4, 'm', 'bigint',           '',   false, false, false, false),
                        ('nabort',              '# Aborts',                                 5, 'm', 'bigint',           '',   false, false, false, false),
                        ('nerror',              '# Errors',                                 6, 'm', 'bigint',           '',   false, false, false, false),
                        ('nskippedtx',          '# Transactions Skipped',                   7, 'm', 'bigint',           '',   false, false, false, false),
                        ('ninsert',             '# Inserts',                                8, 'm', 'bigint',           '',   false, false, false, false),
                        ('nupdate',             '# Updates',                                9, 'm', 'bigint',           '',   false, false, false, false),
                        ('ndelete',             '# Deletes',                                10, 'm', 'bigint',          '',   false, false, false, false),
                        ('ntruncate',           '# Truncates',                              11, 'm', 'bigint',          '',   false, false, false, false),
                        ('nddl',                '# DDL operations',                         12, 'm', 'bigint',          '',   false, false, false, false),
                        ('ndeadlocks',          '# Errors Caused By Deadlocks',             13, 'm', 'bigint',          '',   false, false, false, false),
                        ('nretries',            '# Retries',                                14, 'm', 'bigint',          '',   false, false, false, false),
                        ('shared_blks_hit',     '# Shared Blocks Cache Hit',            15, 'm', 'bigint',          '',   false, false, false, false),
                        ('shared_blks_read',    '# Shared Blocks Read',                 16, 'm', 'bigint',          '',   false, false, false, false),
                        ('shared_blks_dirtied', '# Shared Blocks Dirtied',              17, 'm', 'bigint',          '',   false, false, false, false),
                        ('shared_blks_written', '# Shared Blocks Written',              18, 'm', 'bigint',          '',   false, false, false, false),
                        ('blk_read_time',       '# Time Spent Reading Blocks',          19, 'm', 'double precision','',   false, false, false, false),
                        ('blk_write_time',      '# Time Spent Writing Blocks',          20, 'm', 'double precision','',   false, false, false, false),
                        ('connect_time',        'Current Upstream connection Time',         21, 'm', 'timestamp with time zone', '',   false, false, false, false),
                        ('last_disconnect_time','Last Upstream Disconnection Time',         22, 'm', 'timestamp with time zone', '',   false, false, false, false),
                        ('start_lsn',           'LSN Requested to start Upstream Replication',  23, 'm', 'pg_lsn',          '',   false, false, false, false),
                        ('retries_at_same_lsn', '# Retries At Same LSN',                          24, 'm', 'bigint',          '',   false, false, false, false),
                        ('curr_ncommit',        '# Commits After Current Connection',           25, 'm', 'bigint',          '',   false, false, false, false)
                ) v(internal_name, display_name, display_position, classification,
                        sql_data_type, unit_of_value, calculate_pit, discard_history, pit_by_default, is_graphable);
    END IF;
    PERFORM pem.create_data_and_history_tables();

    --
	-- BDR Relation Statistics Chart
	--

	INSERT INTO pem.chart(id, cid, fid, type, level, name, owner, shared, ref_cnt, reload, summary, labels, params, rwlimit_span_param, ref_timeout_param) VALUES
	(111, 16, NULL, 'TB', ARRAY[200], 'BDR Relation Statistics', 0, NULL, 1, 50000, NULL,
	ARRAY['Relation Schema Name', 'Relation Name', 'Relation OID', 'Total Time', '# Inserts', '# Updates',
	'# Deletes', '# Truncates','# Shared Blocks Cache Hit', '# Shared Blocks Read', '# Shared Blocks Dirtied',
	'# Shared Blocks Written', '# Time Spent Reading Blocks', '# Time Spent Writing Blocks',
	'# Time Spent Acquiring Blocks'], NULL, NULL, NULL) ON CONFLICT DO NOTHING;
	INSERT INTO pem.tbl_chart(cid, type) VALUES (111, 'D') ON CONFLICT DO NOTHING;
	INSERT INTO pem.data_chart(cid, tbl, metrices, orderby, glimit, r_sys_obj) VALUES(111, 'bdr_stat_relation',
	ARRAY['nspname', 'relname', 'relid', 'total_time', 'ninsert', 'nupdate', 'ndelete', 'ntruncate', 'shared_blks_hit',
	'shared_blks_read', 'shared_blks_dirtied', 'shared_blks_written', 'blk_read_time', 'blk_write_time',
	'lock_acquire_time'], ARRAY['relname', 'relid'], 32, false) ON CONFLICT DO NOTHING;

	--
	-- BDR Subscription Statistics Chart
	--

	INSERT INTO pem.chart(id, cid, fid, type, level, name, owner, shared, ref_cnt, reload, summary, labels, params, rwlimit_span_param, ref_timeout_param) VALUES
	(112, 16, NULL, 'TB', ARRAY[200], 'BDR Subscription Statistics', 0, NULL, 1, 50000, NULL,
	ARRAY['Subscription Name', 'Subscription OID', '# Subscription Connected Upstream', '# Commits',
	'# Aborts', '# Errors', '# Transaction Skipped', '# Inserts', '# Updates', '# Deletes', '# Truncates','# DDL Operations',
	'# Errors Caused By Deadlocks', '# Retries', '# Shared Blocks Cache Hit', '# Shared Blocks Read',
	'# Shared Blocks Dirtied','# Shared Blocks Written', '# Time Spent Reading Blocks',
	'# Time Spent Writing Blocks', 'Current Upstream connection Time', 'Last Upstream Disconnection Time', 'LSN Requested to start Upstream Replication',
	'# Retries At Same LSN', '# Commits After Current Connection'], NULL, NULL, NULL) ON CONFLICT DO NOTHING;
	INSERT INTO pem.tbl_chart(cid, type) VALUES (112, 'D') ON CONFLICT DO NOTHING;
	INSERT INTO pem.data_chart(cid, tbl, metrices, orderby, glimit, r_sys_obj) VALUES(112, 'bdr_stat_subscription',
	ARRAY['sub_name', 'subid', 'nconnect', 'ncommit', 'nabort', 'nerror', 'nskippedtx', 'ninsert', 'nupdate', 'ndelete',
	'ntruncate', 'nddl', 'ndeadlocks', 'nretries', 'shared_blks_hit,'
	'shared_blks_read', 'shared_blks_dirtied', 'shared_blks_written', 'blk_read_time', 'blk_write_time',
	'connect_time', 'last_disconnect_time', 'start_lsn', 'retries_at_same_lsn', 'curr_ncommit'],
	ARRAY['sub_name', 'subid'], 32, false) ON CONFLICT DO NOTHING;

END;
$DO$ LANGUAGE 'plpgsql';

END TRANSACTION;

-- We need this separate Tnx to avoid locks on chart table
BEGIN TRANSACTION;
-- PEM-4300
-- SQL schema changes for Import/Export of Custom Charts
DO $$
DECLARE
    uuid text;
BEGIN
	IF NOT EXISTS(
		SELECT * FROM pg_catalog.pg_attribute
		LEFT JOIN pg_catalog.pg_class c ON attrelid = c.oid
		LEFT JOIN pg_catalog.pg_namespace n ON c.relnamespace = n.oid
		WHERE attname = 'reference_id' AND relname = 'chart' AND
			n.nspname = 'pem'
	) THEN
		RAISE INFO
			'--- Adding new column reference_id in pem.chart table';
		ALTER TABLE pem.chart ADD COLUMN reference_id text;
		EXECUTE 'SELECT pem.system_uid();' INTO uuid;

		RAISE INFO '--- Updating the reference_id of the existing charts';
		UPDATE pem.chart
		SET reference_id = CASE
			WHEN owner = 0 THEN id::text || '|' || name
			ELSE 'chart_' || TRIM(uuid) || '_' || id::text
			END;
		ALTER TABLE pem.chart ALTER COLUMN reference_id SET NOT NULL;
	END IF;
END;
$$ LANGUAGE plpgsql;
END TRANSACTION;

BEGIN TRANSACTION;
-- Function to create new the reference-id for custom chart
CREATE OR REPLACE FUNCTION pem.update_chart_reference_id()
RETURNS trigger AS $$
DECLARE
    uuid text;
BEGIN
	IF NEW.owner = 0 THEN
		NEW.reference_id := NEW.id::text || '|' || NEW.name;
	ELSE
        -- If old reference id exist then it may be a case where this template was imported
        -- so we will update it only when it's new and empty
        IF NEW.reference_id IS NULL OR TRIM(NEW.reference_id) = '' THEN
            EXECUTE 'SELECT pem.system_uid();' INTO uuid;
            NEW.reference_id := 'chart_' || TRIM(uuid) || '_' || NEW.id::text;
        END IF;
	END IF;
	RETURN NEW;
END
$$ LANGUAGE plpgsql;

-- Create trigger if not exists on pem.chart
DO $DO$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_trigger
                   WHERE  NOT tgisinternal
                   AND tgname = 'pem_chart_reference_id'
                   AND tgrelid = 'pem.chart'::regclass)
    AND EXISTS(
		SELECT * FROM pg_catalog.pg_attribute
		LEFT JOIN pg_catalog.pg_class c ON attrelid = c.oid
		LEFT JOIN pg_catalog.pg_namespace n ON c.relnamespace = n.oid
		WHERE attname = 'reference_id' AND relname = 'chart' AND
			n.nspname = 'pem'
	) THEN
        CREATE TRIGGER pem_chart_reference_id
            BEFORE INSERT ON pem.chart
            FOR EACH ROW
            EXECUTE PROCEDURE pem.update_chart_reference_id();
    END IF;
END;
$DO$ LANGUAGE 'plpgsql';


-- PEM-4302 added support for monitoring of PG/AS 14

DO $DO$
BEGIN
    -- Check if the server version already exist for PG 14
    IF NOT EXISTS (SELECT id FROM pem.server_version WHERE id = 11400) THEN
        INSERT INTO pem.server_version VALUES (11400, 'PostgreSQL 14');
    END IF;

    -- Check if the server version already exist for EPAS 14
    IF NOT EXISTS (SELECT id FROM pem.server_version WHERE id = 21400) THEN
        INSERT INTO pem.server_version VALUES (21400, 'Advanced Server 14');
    END IF;

    -- Check if the probe server version already exist for PG 14
    IF NOT EXISTS (SELECT server_version_id FROM pem.probe_server_version WHERE server_version_id = 11400) THEN
        INSERT INTO pem.probe_server_version
            (probe_id, server_version_id, probe_code)
            SELECT psv.probe_id, 11400 AS server_version_id, psv.probe_code FROM (
                    SELECT probe_id, probe_code FROM pem.probe_server_version
                    WHERE server_version_id = 11300
            ) AS psv
            JOIN pem.probe p ON (psv.probe_id = p.id) AND p.internal_name = ANY(
                ARRAY[
                'oc_table', 'oc_schema', 'oc_function', 'oc_extension', 'oc_views',
                'database_statistics', 'table_statistics', 'table_frozenxid',
                'table_size', 'function_statistics', 'mview_bloat',
                'mview_frozenxid', 'mview_size', 'blocked_session_info',
                'background_writer_statistics', 'session_info', 'lock_info',
                'number_of_wal_files', 'wal_archive_status',
                'streaming_replication', 'streaming_replication_db_conflicts',
                'streaming_replication_lag_time', 'xdb_smr_mmr_replication',
                'efm_cluster_node_status', 'efm_cluster_info'
                ]::text[]
    );
    END IF;

    -- Check if the probe server version already exist for EPAS 14
    IF NOT EXISTS (SELECT server_version_id FROM pem.probe_server_version WHERE server_version_id = 21400) THEN
        INSERT INTO pem.probe_server_version
            (probe_id, server_version_id, probe_code)
            SELECT psv.probe_id, 21400 AS server_version_id, psv.probe_code FROM (
                    SELECT probe_id, probe_code FROM pem.probe_server_version
                    WHERE server_version_id = 21300
            ) AS psv
            JOIN pem.probe p ON (psv.probe_id = p.id) AND p.internal_name = ANY(
                    ARRAY[
                    'oc_table', 'oc_schema','oc_function', 'oc_extension', 'database_statistics',
                    'table_statistics', 'table_frozenxid', 'function_statistics', 'table_size',
                    'background_writer_statistics', 'number_of_wal_files', 'session_info',
                    'system_waits', 'session_waits', 'lock_info', 'audit_configuration',
                    'streaming_replication', 'streaming_replication_db_conflicts',
                    'xdb_smr_mmr_replication', 'oc_views', 'mview_bloat', 'mview_frozenxid',
                    'mview_size', 'streaming_replication_lag_time', 'wal_archive_status',
                    'efm_cluster_node_status', 'efm_cluster_info', 'blocked_session_info'
                    ]::text[]
    );
    END IF;
END;
$DO$ LANGUAGE 'plpgsql';

-- JIRA PEM-4302
-- leader_pid and query_id has been added to csv logs in PG/AS 14 so added support that.

DO $DO$
BEGIN
	IF NOT EXISTS (SELECT 1
			FROM pg_attribute
			WHERE attrelid = (SELECT oid FROM pg_class WHERE relname = 'server_logs' and relnamespace = (SELECT oid FROM pg_namespace WHERE nspname = 'pemdata'))
			AND attname = 'leader_pid') THEN
				ALTER TABLE pemdata.server_logs ADD COLUMN leader_pid integer;
	END IF;

	IF NOT EXISTS (SELECT 1
			FROM pg_attribute
			WHERE attrelid = (SELECT oid FROM pg_class WHERE relname = 'server_logs' and relnamespace = (SELECT oid FROM pg_namespace WHERE nspname = 'pemdata'))
			AND attname = 'query_id') THEN
				ALTER TABLE pemdata.server_logs ADD COLUMN query_id bigint;
	END IF;

	IF NOT EXISTS (SELECT 1
			FROM pg_attribute
			WHERE attrelid = (SELECT oid FROM pg_class WHERE relname = 'audit_logs' and relnamespace = (SELECT oid FROM pg_namespace WHERE nspname = 'pemdata'))
			AND attname = 'leader_pid') THEN
				ALTER TABLE pemdata.audit_logs ADD COLUMN leader_pid integer;
	END IF;

	IF NOT EXISTS (SELECT 1
			FROM pg_attribute
			WHERE attrelid = (SELECT oid FROM pg_class WHERE relname = 'audit_logs' and relnamespace = (SELECT oid FROM pg_namespace WHERE nspname = 'pemdata'))
			AND attname = 'query_id') THEN
				ALTER TABLE pemdata.audit_logs ADD COLUMN query_id bigint;
	END IF;
END;
$DO$ LANGUAGE plpgsql;

-- PEM-4325
-- SQL schema changes for Import/Export of Custom Dashboard
DO $$
DECLARE
    uuid text;
BEGIN
	IF NOT EXISTS(
		SELECT * FROM pg_catalog.pg_attribute
		LEFT JOIN pg_catalog.pg_class c ON attrelid = c.oid
		LEFT JOIN pg_catalog.pg_namespace n ON c.relnamespace = n.oid
		WHERE attname = 'reference_id' AND relname = 'dashboard' AND
			n.nspname = 'pem'
	) THEN
		RAISE INFO '--- Adding new column reference_id in pem.dashboard table';
		ALTER TABLE pem.dashboard ADD COLUMN reference_id text;
		EXECUTE 'SELECT pem.system_uid();' INTO uuid;

		RAISE INFO '--- Updating the reference_id of the existing charts';
		UPDATE pem.dashboard
		SET reference_id = 'dashboard_' || TRIM(uuid) || '_' || id::text;

		ALTER TABLE pem.dashboard ALTER COLUMN reference_id SET NOT NULL;
	END IF;
END;
$$ LANGUAGE plpgsql;

-- Function to create new the reference-id for custom dashboard
CREATE OR REPLACE FUNCTION pem.update_dashboard_reference_id()
RETURNS trigger AS $$
DECLARE
    uuid text;
BEGIN
    -- If old reference id exist then it may be a case where this dashboard was imported
    -- so we will update it only when it's new and empty
    IF NEW.reference_id IS NULL OR TRIM(NEW.reference_id) = '' THEN
        EXECUTE 'SELECT pem.system_uid();' INTO uuid;
        NEW.reference_id := 'dashboard_' || TRIM(uuid) || '_' || NEW.id::text;
    END IF;
	RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Create trigger if not exists on pem.dashboard
DO $DO$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_trigger
                   WHERE  NOT tgisinternal
                   AND tgname = 'dashboard_reference_id'
                   AND tgrelid = 'pem.dashboard'::regclass) THEN
        CREATE TRIGGER dashboard_reference_id
            BEFORE INSERT ON pem.dashboard
            FOR EACH ROW
            EXECUTE PROCEDURE pem.update_dashboard_reference_id();
    END IF;
END;
$DO$ LANGUAGE 'plpgsql';

END TRANSACTION;
