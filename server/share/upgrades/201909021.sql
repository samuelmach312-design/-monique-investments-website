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
'SELECT 201909021::integer;'
  LANGUAGE 'sql' IMMUTABLE;
COMMENT ON FUNCTION pem.schema_version() IS 'Returns the version number of the PEM schema';

INSERT INTO pem.server_version VALUES (11200, 'PostgreSQL 12');
INSERT INTO pem.server_version VALUES (21200, 'Advanced Server 12');

INSERT INTO pem.probe_server_version
    (probe_id, server_version_id, probe_code)
SELECT psv.probe_id, 11200 AS server_version_id, psv.probe_code FROM (
    SELECT probe_id, probe_code FROM pem.probe_server_version
    WHERE server_version_id = 11100
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
    'efm_cluster_node_status', 'efm_cluster_info',
    'oc_table'
    ]::text[]
);

INSERT INTO pem.probe_server_version
    (probe_id, server_version_id, probe_code)
SELECT psv.probe_id, 21200 AS server_version_id, psv.probe_code FROM (
    SELECT probe_id, probe_code FROM pem.probe_server_version
    WHERE server_version_id = 21100
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
    'efm_cluster_node_status', 'efm_cluster_info', 'blocked_session_info',
    'database_statistics', 'oc_table'
    ]::text[]
);

-- PG/Advanced Server 12+ will return a row with database_name as 'null' for
-- the shared objects, showing database-wide statistics.
UPDATE pem.probe_server_version
SET probe_code = $SQL$
SELECT COALESCE(d1.datname, '') AS database_name, d1.numbackends, (
        SELECT COALESCE(count(query)::bigint, 0::bigint)
        FROM pg_catalog.pg_stat_activity
        WHERE datname = d1.datname AND state = 'idle'
    ) AS idle_backends,
    d1.xact_commit, d1.xact_rollback, d1.blks_hit,
    NULL::bigint AS blks_icache_hit, d1.blks_read,
    d1.tup_returned, d1.tup_fetched, d1.tup_inserted,
    d1.tup_updated, d1.tup_deleted
FROM pg_catalog.pg_stat_database d1$SQL$
WHERE probe_id = (
        SELECT p.id FROM pem.probe p WHERE p.internal_name = 'database_statistics'
    ) AND server_version_id IN (11200, 21200);

UPDATE pem.probe_server_version
SET probe_code = $SQL$
SELECT c.relname AS table_name, array_length(array_agg(i.indexrelid), 1) > 0 AS has_primary_key                                                                                                                    FROM
    (SELECT oid AS coid, * FROM pg_catalog.pg_class c WHERE relkind IN ('r', 'p')) c
    JOIN pg_catalog.pg_namespace n ON (c.relnamespace = n.oid AND n.nspname = %{schema_name})
    LEFT JOIN pg_catalog.pg_index i ON (i.indexrelid = c.coid AND i.indisprimary)
GROUP BY c.relname$SQL$
WHERE probe_id = (
        SELECT p.id FROM pem.probe p WHERE p.internal_name = 'oc_table'
    ) AND server_version_id IN (11100, 11200, 21100, 21200);

END TRANSACTION;
