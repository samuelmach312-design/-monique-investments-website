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
'SELECT 201809041::integer;'
  LANGUAGE 'sql' IMMUTABLE;
COMMENT ON FUNCTION pem.schema_version() IS 'Returns the version number of the PEM schema';

INSERT INTO pem.server_version VALUES (11100, 'PostgreSQL 11');
INSERT INTO pem.server_version VALUES (21100, 'Advanced Server 11');

INSERT INTO pem.probe_server_version
    (probe_id, server_version_id, probe_code)
SELECT psv.probe_id, 11100 AS server_version_id, psv.probe_code FROM (
    SELECT probe_id, probe_code FROM pem.probe_server_version
    WHERE server_version_id = 11000
) AS psv
JOIN pem.probe p ON (psv.probe_id = p.id) AND p.internal_name = ANY(
    ARRAY[
    'oc_schema', 'oc_function', 'oc_extension', 'oc_views',
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

INSERT INTO pem.probe_server_version
    (probe_id, server_version_id, probe_code)
SELECT psv.probe_id, 21100 AS server_version_id, psv.probe_code FROM (
    SELECT probe_id, probe_code FROM pem.probe_server_version
    WHERE server_version_id = 21000
) AS psv
JOIN pem.probe p ON (psv.probe_id = p.id) AND p.internal_name = ANY(
    ARRAY[
    'oc_schema', 'oc_function', 'oc_extension', 'table_statistics',
    'table_frozenxid', 'function_statistics', 'table_size',
    'background_writer_statistics', 'number_of_wal_files', 'session_info',
    'system_waits', 'session_waits', 'lock_info', 'audit_configuration',
    'streaming_replication', 'streaming_replication_db_conflicts',
    'xdb_smr_mmr_replication', 'oc_views', 'mview_bloat', 'mview_frozenxid',
    'mview_size', 'streaming_replication_lag_time', 'wal_archive_status',
    'efm_cluster_node_status', 'efm_cluster_info', 'blocked_session_info'
    ]::text[]
);

INSERT INTO pem.probe_server_version
    (probe_id, server_version_id, probe_code)
SELECT
    (SELECT id FROM pem.probe WHERE internal_name = 'database_statistics'),
    v.version,
     'SELECT d1.datname AS database_name, d1.numbackends,
            (SELECT COALESCE(count(query)::bigint, 0::bigint) FROM pg_catalog.pg_stat_activity WHERE datname = d1.datname AND state = ''idle'') AS idle_backends,
        d1.xact_commit, d1.xact_rollback, d1.blks_hit, NULL::bigint AS blks_icache_hit, d1.blks_read,
            d1.tup_returned, d1.tup_fetched, d1.tup_inserted, d1.tup_updated, d1.tup_deleted
      FROM pg_catalog.pg_stat_database d1'
FROM
    (VALUES (21100)) v(version);

INSERT INTO pem.probe_server_version
    (probe_id, server_version_id, probe_code)
SELECT
    (SELECT id FROM pem.probe WHERE internal_name = 'oc_table'),
    v.version,
    E'SELECT c.relname AS table_name, array_length(array(SELECT indexrelid FROM pg_catalog.pg_index WHERE indexrelid = c.oid AND indisprimary), 1) > 0 AS has_primary_key FROM pg_catalog.pg_class c, pg_catalog.pg_namespace n WHERE c.relkind IN (''r'', ''p'') AND c.relnamespace = n.oid AND n.nspname = %{schema_name}'
FROM
    (VALUES (11100), (21100)) v(version);

END TRANSACTION;
