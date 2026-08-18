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
  'SELECT 201706271::integer;'
    LANGUAGE 'sql' IMMUTABLE;
    COMMENT ON FUNCTION pem.schema_version() IS 'Returns the version number of the PEM schema';

-- Fixes #41450
CREATE OR REPLACE FUNCTION pem.backend_minimum(majorversion integer, minorversion integer DEFAULT NULL)
  RETURNS boolean AS
$$
DECLARE
    version varchar;
    version_arr varchar[3];
    major integer;
    minor integer;
BEGIN
    SELECT version() INTO version;
    version_arr := regexp_matches(version, '[PostgreSQL|EnterpriseDB] ([0-9]+)[.]{0,1}([0-9]+)*');
    major := version_arr[1]::integer;
    minor := version_arr[2]::integer;

    IF (major > majorversion OR (major = majorversion AND minor >= minorversion)) THEN
      return true;
    ELSIF (major = majorversion AND minorversion IS NULL) THEN
      return true;
    ELSE
      return false;
    END IF;
END;
$$
 LANGUAGE plpgsql VOLATILE;

-- Added support for PG/EPAS 10
INSERT INTO pem.server_version VALUES (11000, 'PostgreSQL 10');
INSERT INTO pem.server_version VALUES (21000, 'Advanced Server 10');

-- oc_schmea support
INSERT INTO pem.probe_server_version(probe_id,server_version_id,probe_code)
       VALUES((SELECT id FROM pem.probe WHERE internal_name='oc_schema'), 11000, NULL);

INSERT INTO pem.probe_server_version(probe_id,server_version_id,probe_code)
       VALUES((SELECT id FROM pem.probe WHERE internal_name='oc_schema'), 21000,
       E'SELECT nspname AS schema_name FROM pg_catalog.pg_namespace WHERE (nspname = ''pg_catalog'' OR nspname NOT LIKE E''pg\\\\_%'') AND nspparent = 0');

-- oc_function support
INSERT INTO pem.probe_server_version(probe_id,server_version_id,probe_code)
       VALUES((SELECT id FROM pem.probe WHERE internal_name='oc_function'), 11000,
	   $sql$
	SELECT
	'' AS package_name, f.proname AS function_name, '0'::"char" AS function_type,
	f.prorettype::regtype AS return_type, pg_get_function_identity_arguments(f.oid) AS arg_types,
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
       VALUES((SELECT id FROM pem.probe WHERE internal_name='oc_function'), 21000,
       $sql$
	SELECT	'' AS package_name, f.proname AS function_name, f.protype AS function_type,
			f.prorettype::regtype AS return_type, pg_get_function_identity_arguments(f.oid) AS arg_types,
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
			f.prorettype::regtype AS return_type, pg_get_function_identity_arguments(f.oid) AS arg_types,
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
       VALUES((SELECT id FROM pem.probe WHERE internal_name='database_statistics'), 11000,
       'SELECT d1.datname AS database_name, d1.numbackends,
            (SELECT COALESCE(count(query)::bigint, 0::bigint) FROM pg_catalog.pg_stat_activity WHERE datname = d1.datname AND state = ''idle'') AS idle_backends,
	    d1.xact_commit, d1.xact_rollback, d1.blks_hit, NULL::bigint AS blks_icache_hit, d1.blks_read,
            d1.tup_returned, d1.tup_fetched, d1.tup_inserted, d1.tup_updated, d1.tup_deleted
      FROM pg_catalog.pg_stat_database d1');

INSERT INTO pem.probe_server_version(probe_id,server_version_id,probe_code)
       VALUES((SELECT id FROM pem.probe WHERE internal_name='database_statistics'), 21000,
       'SELECT d1.datname AS database_name, d1.numbackends,
            (SELECT COALESCE(count(query)::bigint, 0::bigint) FROM pg_catalog.pg_stat_activity WHERE datname = d1.datname AND state = ''idle'') AS idle_backends,
            d1.xact_commit, d1.xact_rollback, d1.blks_hit, d1.blks_icache_hit, d1.blks_read, d1.tup_returned,
            d1.tup_fetched, d1.tup_inserted, d1.tup_updated, d1.tup_deleted
     FROM pg_catalog.pg_stat_database d1');

-- table_statistics support
INSERT INTO pem.probe_server_version(probe_id,server_version_id,probe_code)
       VALUES((SELECT id FROM pem.probe WHERE internal_name='table_statistics'), 11000, NULL);

INSERT INTO pem.probe_server_version(probe_id,server_version_id,probe_code)
       VALUES((SELECT id FROM pem.probe WHERE internal_name='table_statistics'), 21000, NULL);

-- function_statistics support
INSERT INTO pem.probe_server_version(probe_id,server_version_id,probe_code)
       VALUES((SELECT id FROM pem.probe WHERE internal_name='function_statistics'), 11000, NULL);

INSERT INTO pem.probe_server_version(probe_id,server_version_id,probe_code)
       VALUES((SELECT id FROM pem.probe WHERE internal_name='function_statistics'), 21000,
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
       VALUES((SELECT id FROM pem.probe WHERE internal_name='table_size'), 11000,
       'SELECT n.nspname AS schema_name, c.relname AS table_name, pg_relation_size(c.oid) / 1048576 AS table_size_mb, pg_indexes_size(c.oid) / 1048576 AS size_of_indexes_mb, pg_total_relation_size(c.oid) / 1048576 AS total_table_size_mb FROM pg_class c, pg_namespace n WHERE c.relnamespace = n.oid AND c.relkind IN (''r'', ''p'')');

INSERT INTO pem.probe_server_version(probe_id,server_version_id,probe_code)
       VALUES((SELECT id FROM pem.probe WHERE internal_name='table_size'), 21000,
       'SELECT n.nspname AS schema_name, c.relname AS table_name, pg_relation_size(c.oid) / 1048576 AS table_size_mb, pg_indexes_size(c.oid) / 1048576 AS size_of_indexes_mb, pg_total_relation_size(c.oid) / 1048576 AS total_table_size_mb FROM pg_class c, pg_namespace n WHERE c.relnamespace = n.oid AND c.relkind IN (''r'', ''p'')');

-- background_writer_statistics support
INSERT INTO pem.probe_server_version(probe_id,server_version_id,probe_code)
       VALUES((SELECT id FROM pem.probe WHERE internal_name='background_writer_statistics'), 11000, NULL);

INSERT INTO pem.probe_server_version(probe_id,server_version_id,probe_code)
       VALUES((SELECT id FROM pem.probe WHERE internal_name='background_writer_statistics'), 21000, NULL);

-- session_info support
INSERT INTO pem.probe_server_version(probe_id,server_version_id,probe_code)
       VALUES((SELECT id FROM pem.probe WHERE internal_name='session_info'), 11000,
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
       VALUES((SELECT id FROM pem.probe WHERE internal_name='session_info'), 21000,
       $sql$
		SELECT
			datname AS database_name, pid AS procpid, usename, client_addr, client_port, backend_start,
			xact_start, query_start, CASE WHEN wait_event IS NULL THEN false ELSE true END AS is_waiting,
			state = 'idle' AS is_idle, state = 'idle in transaction' AS is_idle_in_transaction, query ilike $$VACUUM%$$ as is_vacuum,
			client_port IS NULL AND (query like $$autovacuum:%$$ OR query like $$VACUUM%$$) as is_autovacuum,
			now() AS capture_time, wait_event, wait_event_type
		FROM pg_catalog.pg_stat_activity
	   $sql$);

-- system_waits support
INSERT INTO pem.probe_server_version(probe_id,server_version_id,probe_code)
       VALUES((SELECT id FROM pem.probe WHERE internal_name='system_waits'), 21000, NULL);

-- session_waits support
INSERT INTO pem.probe_server_version(probe_id,server_version_id,probe_code)
       VALUES((SELECT id FROM pem.probe WHERE internal_name='session_waits'), 21000,
       'SELECT sw.backend_id, psa.datname AS dbname, psa.usename, sw.wait_name, sw.wait_count, avg_wait_time, max_wait_time, total_wait_time FROM session_waits sw, pg_stat_activity psa WHERE sw.backend_id = psa.pid');

-- lock_info support
INSERT INTO pem.probe_server_version(probe_id,server_version_id,probe_code)
       VALUES((SELECT id FROM pem.probe WHERE internal_name='lock_info'), 11000,
       $sql$
SELECT ROW_NUMBER() OVER (PARTITION BY l.pid) AS lockrowid,
		COALESCE(d.datname, '')			AS database_name,
		COALESCE(l.pid::bigint, -1)		AS procpid,
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
	$sql$);

INSERT INTO pem.probe_server_version(probe_id,server_version_id,probe_code)
       VALUES((SELECT id FROM pem.probe WHERE internal_name='lock_info'), 21000,
       $sql$
SELECT ROW_NUMBER() OVER (PARTITION BY l.pid) AS lockrowid,
		COALESCE(d.datname, '')			AS database_name,
		COALESCE(l.pid::bigint, -1)		AS procpid,
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
	$sql$);

-- audit_configuration support
INSERT INTO pem.probe_server_version(probe_id,server_version_id,probe_code)
       VALUES((SELECT id FROM pem.probe WHERE internal_name='audit_configuration'), 21000, NULL);

-- streaming_replication support
INSERT INTO pem.probe_server_version(probe_id,server_version_id,probe_code)
       VALUES((SELECT id FROM pem.probe WHERE internal_name='streaming_replication'), 11000,
	   $sql$
		SELECT client_addr, client_port, sent_location, write_location, flush_location, replay_location, xlog_lag_in_segments,
		(((sent_location -replay_location)>>10) / (SUBSTRING(unit FROM '[0-9]+'))::INT) AS xlog_lag_in_pages
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
				('x'||SUBSTRING((pg_walfile_name_offset(replay_lsn)).file_name FROM 9))::BIT(64)::BIGINT) AS xlog_lag_in_segments

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
       VALUES((SELECT id FROM pem.probe WHERE internal_name='streaming_replication'), 21000,
	   $sql$
		SELECT client_addr, client_port, sent_location, write_location, flush_location, replay_location, xlog_lag_in_segments,
		(((sent_location -replay_location)>>10) / (SUBSTRING(unit FROM '[0-9]+'))::INT) AS xlog_lag_in_pages
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
				('x'||SUBSTRING((pg_walfile_name_offset(replay_lsn)).file_name FROM 9))::BIT(64)::BIGINT) AS xlog_lag_in_segments

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
       VALUES((SELECT id FROM pem.probe WHERE internal_name='streaming_replication_db_conflicts'), 11000, NULL);

INSERT INTO pem.probe_server_version(probe_id,server_version_id,probe_code)
       VALUES((SELECT id FROM pem.probe WHERE internal_name='streaming_replication_db_conflicts'), 21000, NULL);

-- xdb_smr_mmr_replication support
INSERT INTO pem.probe_server_version(probe_id,server_version_id,probe_code)
       VALUES((SELECT id FROM pem.probe WHERE internal_name='xdb_smr_mmr_replication'), 11000, NULL);

INSERT INTO pem.probe_server_version(probe_id,server_version_id,probe_code)
       VALUES((SELECT id FROM pem.probe WHERE internal_name='xdb_smr_mmr_replication'), 21000, NULL);

-- oc_views support
INSERT INTO pem.probe_server_version(probe_id,server_version_id,probe_code)
       VALUES((SELECT id FROM pem.probe WHERE internal_name='oc_views'), 11000, NULL);

INSERT INTO pem.probe_server_version(probe_id,server_version_id,probe_code)
       VALUES((SELECT id FROM pem.probe WHERE internal_name='oc_views'), 21000, NULL);

-- mview_bloat support
INSERT INTO pem.probe_server_version(probe_id,server_version_id,probe_code)
       VALUES((SELECT id FROM pem.probe WHERE internal_name='mview_bloat'), 11000, NULL);

INSERT INTO pem.probe_server_version(probe_id,server_version_id,probe_code)
       VALUES((SELECT id FROM pem.probe WHERE internal_name='mview_bloat'), 21000, NULL);

-- mview_frozenxid support
INSERT INTO pem.probe_server_version(probe_id,server_version_id,probe_code)
       VALUES((SELECT id FROM pem.probe WHERE internal_name='mview_frozenxid'), 11000, NULL);

INSERT INTO pem.probe_server_version(probe_id,server_version_id,probe_code)
       VALUES((SELECT id FROM pem.probe WHERE internal_name='mview_frozenxid'), 21000, NULL);

-- mview_size support
INSERT INTO pem.probe_server_version(probe_id,server_version_id,probe_code)
       VALUES((SELECT id FROM pem.probe WHERE internal_name='mview_size'), 11000, NULL);

INSERT INTO pem.probe_server_version(probe_id,server_version_id,probe_code)
       VALUES((SELECT id FROM pem.probe WHERE internal_name='mview_size'), 21000, NULL);

-- streaming_replication_lag_time support
INSERT INTO pem.probe_server_version(probe_id,server_version_id,probe_code)
       VALUES((SELECT id FROM pem.probe WHERE internal_name='streaming_replication_lag_time'), 11000,
	   'SELECT (CASE WHEN pg_last_wal_receive_lsn() = pg_last_wal_replay_lsn() THEN 0
		ELSE COALESCE(EXTRACT (EPOCH FROM now() - pg_last_xact_replay_timestamp())/60, 0) END)::bigint AS lag_time,
		pg_is_wal_replay_paused() AS replication_paused WHERE true = pg_is_in_recovery()');

INSERT INTO pem.probe_server_version(probe_id,server_version_id,probe_code)
       VALUES((SELECT id FROM pem.probe WHERE internal_name='streaming_replication_lag_time'), 21000,
	   'SELECT (CASE WHEN pg_last_wal_receive_lsn() = pg_last_wal_replay_lsn() THEN 0
		ELSE COALESCE(EXTRACT (EPOCH FROM now() - pg_last_xact_replay_timestamp())/60, 0) END)::bigint AS lag_time,
		pg_is_wal_replay_paused() AS replication_paused WHERE true = pg_is_in_recovery()');

-- wal_archive_status support
INSERT INTO pem.probe_server_version(probe_id,server_version_id,probe_code)
       VALUES((SELECT id FROM pem.probe WHERE internal_name='wal_archive_status'), 11000,
       'SELECT archived_count, last_archived_time, failed_count, last_failed_time FROM pg_catalog.pg_stat_archiver');

INSERT INTO pem.probe_server_version(probe_id,server_version_id,probe_code)
       VALUES((SELECT id FROM pem.probe WHERE internal_name='wal_archive_status'), 21000,
       'SELECT archived_count, last_archived_time, failed_count, last_failed_time FROM pg_catalog.pg_stat_archiver');

--efm_cluster_info support
INSERT INTO pem.probe_server_version(probe_id, server_version_id, probe_code)
VALUES ((SELECT id from pem.probe WHERE internal_name ='efm_cluster_info'), 11000, NULL);
INSERT INTO pem.probe_server_version(probe_id, server_version_id, probe_code)
VALUES ((SELECT id from pem.probe WHERE internal_name ='efm_cluster_info'), 21000, NULL);

--efm_cluster_node_status support
INSERT INTO pem.probe_server_version(probe_id, server_version_id, probe_code)
VALUES ((SELECT id from pem.probe WHERE internal_name ='efm_cluster_node_status'), 11000, NULL);
INSERT INTO pem.probe_server_version(probe_id, server_version_id, probe_code)
VALUES ((SELECT id from pem.probe WHERE internal_name ='efm_cluster_node_status'), 21000, NULL);

UPDATE pem.probe
	SET any_server_version = false
WHERE
	internal_name IN ('number_of_wal_files', 'oc_table', 'table_frozenxid');

INSERT INTO pem.probe_server_version
    (probe_id, server_version_id, probe_code)
SELECT
	(SELECT id FROM pem.probe WHERE internal_name = 'number_of_wal_files'),
	v.version, NULL
FROM
	(VALUES (10901), (10902), (10903), (10904), (10905), (10906), (20901), (20902), (20903), (20904), (20905), (20906)) v(version);

INSERT INTO pem.probe_server_version
    (probe_id, server_version_id, probe_code)
SELECT
	(SELECT id FROM pem.probe WHERE internal_name = 'number_of_wal_files'),
	v.version,
	E'SELECT COALESCE(sum(1), 0) AS number_of_wal_files FROM pg_ls_waldir() AS d (file) WHERE file ~ ''^[0-9A-F]{8}[0-9A-F]{8}[0-9A-F]{8}$'''
FROM
	(VALUES (11000), (21000)) v(version);

-- Fixes #41763
ALTER TABLE pemdata.audit_logs
   ADD COLUMN audit_command_tag text DEFAULT ''::text;
COMMENT ON COLUMN pemdata.audit_logs.audit_command_tag IS 'Audit log command type';

-- Fixes #41674
INSERT INTO pem.probe_server_version
    (probe_id, server_version_id, probe_code)
SELECT
	(SELECT id FROM pem.probe WHERE internal_name = 'oc_table'),
	v.version, NULL
FROM
	(VALUES (10901), (10902), (10903), (10904), (10905), (10906), (20901), (20902), (20903), (20904), (20905), (20906)) v(version);

INSERT INTO pem.probe_server_version
    (probe_id, server_version_id, probe_code)
SELECT
	(SELECT id FROM pem.probe WHERE internal_name = 'oc_table'),
	v.version,
	E'SELECT c.relname AS table_name, c.relhaspkey AS has_primary_key FROM pg_catalog.pg_class c, pg_catalog.pg_namespace n WHERE c.relkind IN (''r'', ''p'') AND c.relnamespace = n.oid AND n.nspname = %{schema_name}'
FROM
	(VALUES (11000), (21000)) v(version);

INSERT INTO pem.probe_server_version
    (probe_id, server_version_id, probe_code)
SELECT
	(SELECT id FROM pem.probe WHERE internal_name = 'table_frozenxid'),
	v.version, NULL
FROM
	(VALUES (10901), (10902), (10903), (10904), (10905), (10906), (20901), (20902), (20903), (20904), (20905), (20906)) v(version);

INSERT INTO pem.probe_server_version
    (probe_id, server_version_id, probe_code)
SELECT
	(SELECT id FROM pem.probe WHERE internal_name = 'table_frozenxid'),
	v.version,
	E'SELECT n.nspname AS schema_name, c.relname AS table_name, age(c.relfrozenxid) AS frozenxid FROM pg_class c, pg_namespace n WHERE c.relnamespace = n.oid AND c.relkind IN (''r'', ''p'')'
FROM
	(VALUES (11000), (21000)) v(version);


-- Fixes #41643
ALTER TABLE pemdata.oc_function ALTER COLUMN arg_types TYPE text USING array_to_string(arg_types, ',');
ALTER TABLE pemhistory.oc_function ALTER COLUMN arg_types TYPE text USING array_to_string(arg_types, ',');

UPDATE pem.probe SET probe_code = $sql$
SELECT	'' AS package_name, f.proname AS function_name, '0'::"char" AS function_type,
		f.prorettype::regtype AS return_type, pg_get_function_identity_arguments(f.oid) AS arg_types
FROM	pg_catalog.pg_namespace AS s	-- schema
JOIN	pg_catalog.pg_proc AS f			-- function
ON		f.pronamespace = s.oid
WHERE	s.nspname = %{schema_name}$sql$
WHERE internal_name = 'oc_function';

UPDATE pem.probe_server_version SET probe_code = $sql$
	SELECT
	'' AS package_name, f.proname AS function_name, '0'::"char" AS function_type,
	f.prorettype::regtype AS return_type, pg_get_function_identity_arguments(f.oid) AS arg_types,
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
	s.nspname = %{schema_name}$sql$
WHERE probe_id = (SELECT id from pem.probe WHERE internal_name = 'oc_function')
AND server_version_id IN (10901, 10902, 10903, 10904, 10905, 10906);

UPDATE pem.probe_server_version SET probe_code = $sql$
	SELECT	'' AS package_name, f.proname AS function_name, f.protype AS function_type,
			f.prorettype::regtype AS return_type, pg_get_function_identity_arguments(f.oid) AS arg_types,
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
			f.prorettype::regtype AS return_type, pg_get_function_identity_arguments(f.oid) AS arg_types,
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
	AND		s.nspname = %{schema_name}$sql$
WHERE probe_id = (SELECT id from pem.probe WHERE internal_name = 'oc_function')
AND server_version_id IN (20901, 20902, 20903, 20904, 20905, 20906);

CREATE OR REPLACE FUNCTION pem.cm_report_chart_info(id int4, OUT idx int4, OUT label text,
	OUT is_agent boolean, OUT object text, OUT is_active boolean, OUT color text)
RETURNS SETOF RECORD AS $$
DECLARE
	nrec   record;
	colors text[];
	midx   int4;
	type   char(1) := NULL;
	cnt    int2 := 0;
BEGIN
	EXECUTE 'SELECT type, colors, midx FROM pem.capacity_report_chart WHERE cid = $1::int4' INTO type, colors, midx USING id;
	IF type IS NULL THEN
		RAISE EXCEPTION '201';
	END IF;

	FOR nrec IN EXECUTE E'
SELECT
    cm.mid AS mid, cm.tbl AS tbl, cm.metrices AS metrices, cm.params AS params, p.applies_to_id AS applies_to_id,
        ARRAY(SELECT
                        pc.display_name
                FROM (SELECT unnest(cm.metrices) AS metric) m
                LEFT JOIN (
                        SELECT
                                internal_name AS internal_name, CASE WHEN NOT pit_by_default THEN display_name || ''+'' ELSE display_name END AS display_name
                        FROM pem.probe_column
                        WHERE is_graphable AND probe_id = p.id
                        UNION ALL
                        SELECT
                                internal_name || ''_pit'' AS internal_name, display_name
                        FROM pem.probe_column
                        WHERE is_graphable AND NOT pit_by_default AND probe_id = p.id) pc ON (pc.internal_name = m.metric)) AS metrices_display,
	CASE WHEN p.applies_to_id <> 100 THEN s.description ELSE a.description END AS object,
	CASE WHEN p.applies_to_id <> 100 THEN s.active ELSE a.active END AS active,
	p.deleted
FROM
        pem.chart_metric cm
        LEFT JOIN pem.probe p ON (cm.tbl = p.internal_name)
		LEFT JOIN pem.server s ON (s.id::text = (cm.params[1]).value)
		LEFT JOIN pem.agent  a ON (a.id::text = (cm.params[1]).value)
WHERE cm.cid = $1::int4' USING id
	LOOP
		idx := nrec.mid;
		is_agent := (nrec.applies_to_id = 100);
		object := nrec.object;
		is_active := nrec.active;

		IF midx IS NOT NULL AND midx = idx AND NOT is_active THEN
			RAISE EXCEPTION '202:%', array[is_agent::text, object]::text;
		END IF;

		IF nrec.deleted IS NULL OR nrec.deleted = true THEN
			RAISE EXCEPTION '204';
		END IF;

		IF array_length(colors, 1) > idx THEN
			color := colors[idx];
		ELSE
			color := NULL;
		END IF;

		IF (array_length(nrec.metrices, 1) > 0) THEN
			IF nrec.applies_to_id <> 800 THEN
				IF array_length(nrec.params, 1) > 1 THEN
					EXECUTE E'SELECT $1::text || '' ('' || $2::text || ''/'' || array_to_string(ARRAY(SELECT pg_catalog.quote_ident(($3::pem.chart_metric_param[])[s].value) FROM generate_series (2, array_upper($3::pem.chart_metric_param[], 1), 1) AS s), ''/'') || '')''' INTO label USING (nrec.metrices_display)[1], nrec.object, nrec.params;
				ELSE
					label := (nrec.metrices_display)[1] || ' (' || nrec.object || ')';
				END IF;
			ELSE
				EXECUTE E'SELECT $1::text || '' ('' || $2::text || ''/'' || array_to_string(ARRAY(SELECT pg_catalog.quote_ident(($3::pem.chart_metric_param[])[s].value) FROM generate_series (2, array_upper($3::pem.chart_metric_param[], 1) - 2, 1) AS s), ''/'') || ''('' || COALESCE(($3::pem.chart_metric_param[])[array_upper($3::pem.chart_metric_param[], 1)].value, '''') ||  ''))''' INTO label USING nrec.metrices_display[1], nrec.object, nrec.params;
			END IF;
			IF is_active THEN
				cnt := cnt + 1;
			END IF;

			RETURN NEXT;
		END IF;
	END LOOP;
	IF cnt = 0 THEN
		RAISE EXCEPTION '203';
	END IF;
END;
$$ LANGUAGE plpgsql;

ALTER TABLE pem.probe_column DISABLE TRIGGER USER;

UPDATE pem.probe_column SET
    display_position = CASE WHEN internal_name = 'lockrowid' THEN 1
                            WHEN internal_name = 'database_name' THEN 2
                            WHEN internal_name = 'procpid' THEN 3
                            WHEN internal_name = 'objid' THEN 4
                            WHEN internal_name = 'objsubid' THEN 5
                            WHEN internal_name = 'objsubsubid' THEN 6
                            WHEN internal_name = 'locktype' THEN 7
                            WHEN internal_name = 'lockmode' THEN 8
                            WHEN internal_name = 'lockgranted' THEN 9
                       END
    WHERE
          (probe_id = (SELECT id FROM pem.probe WHERE internal_name='lock_info'));

ALTER TABLE pem.probe_column ENABLE TRIGGER USER;

-- Fixes #41421
CREATE OR REPLACE FUNCTION pem.send_notifications() RETURNS trigger AS $$
DECLARE
	subject text;
	message text;
	mail_group_id integer[];
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
	message_replication_lag text := '';
	replication_alert_params text[];
	low_trap boolean:= false;
	med_trap boolean:= false;
	high_trap boolean:= false;
	is_execute_script boolean:= false;
	is_execute_on_clear boolean:= false;
	is_execute_on_pem_server boolean:= false;
	code text;
	is_submit_to_nagios boolean:= false;
	passive_check_result_text text;
	submit_to_nagios_val boolean:= false;
BEGIN
	-- Get alert details
	SELECT
		agent_id, template_id, send_email, acknowledged, flapping_detected, send_trap, snmp_trap_version, low_send_trap, med_send_trap,
		high_send_trap, execute_script, execute_script_on_clear, execute_script_on_pem_server, script_code, submit_to_nagios
	INTO
		agentid, templateid, is_send_email, is_acknowledged, is_flapping_detected, is_send_trap, trap_version, low_trap, med_trap,
		high_trap, is_execute_script, is_execute_on_clear, is_execute_on_pem_server, code, is_submit_to_nagios
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

	-- Get the standby server details for segment lag and page lag alerts
	IF (template_name = 'Standby server lag behind the master by WAL segments' OR template_name = 'Standby server lag behind the master by WAL pages') THEN
		SELECT params FROM pem.alert WHERE id = NEW.alert_id INTO replication_alert_params;
		IF array_lower(replication_alert_params, 1) IS NOT NULL THEN
			message_replication_lag := 'Standby server: ' || array_to_string(replication_alert_params, ':');
		END IF;
	END IF;

	IF ((TG_OP = 'INSERT') AND (NEW.current_state IS NOT NULL)) THEN
		-- Update state change count
		UPDATE pem.alert_status SET state_change_count = state_change_count + 1 WHERE alert_id = NEW.alert_id;

		-- Get group id's to send email
		SELECT ARRAY(SELECT DISTINCT UNNEST(pem.get_email_group_ids(NEW.alert_id, NEW.current_state::text, ''))) INTO mail_group_id;

		-- Check whether to send trap according to alert level low, med and high.
		IF (NEW.current_state IS NOT NULL) AND (NEW.current_state::text = 'LOW') AND low_trap THEN
			is_send_trap = true;
		ELSIF (NEW.current_state IS NOT NULL) AND (NEW.current_state::text = 'MEDIUM') AND med_trap THEN
			is_send_trap = true;
		ELSIF (NEW.current_state IS NOT NULL) AND (NEW.current_state::text = 'HIGH') AND high_trap THEN
			is_send_trap = true;
		ELSE
			is_send_trap = false;
		END IF;

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

			-- Special handling for segment lag/page lag alerts
			IF (template_name = 'Standby server lag behind the master by WAL segments'
				OR template_name = 'Standby server lag behind the master by WAL pages') THEN
				message = message || message_replication_lag;
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
			IF (template_name = 'Agents Down') OR  (template_name = 'Servers Down') THEN
				varbinding_oid = varbinding_oid || '|' || enterprise_oid || '.7.15';
				varbinding_value = varbinding_value || '|' || down_objects_list::text;
			END IF;

			-- Special handling for 'Write lag Alert' alert
			IF (template_name = 'Number of standby servers lag behind the master by write location') THEN
				varbinding_oid = varbinding_oid || '|' || enterprise_oid || '.7.17';
				varbinding_value = varbinding_value || '|' || COALESCE(write_message_streaming_repl, '')::text;
			END IF;

			IF (template_name = 'Number of standby servers lag behind the master by flush location') THEN
				varbinding_oid = varbinding_oid || '|' || enterprise_oid || '.7.17';
				varbinding_value = varbinding_value || '|' || COALESCE(flush_message_streaming_repl, '')::text;
			END IF;

			IF (template_name = 'Number of standby servers lag behind the master by replay location') THEN
				varbinding_oid = varbinding_oid || '|' || enterprise_oid || '.7.17';
				varbinding_value = varbinding_value || '|' || COALESCE(replay_message_streaming_repl, '')::text;
			END IF;

			-- Special handling for "Package version mismatch" alert
			IF (template_name = 'Package version mismatch') THEN
				varbinding_oid = varbinding_oid || '|' || enterprise_oid || '.7.16';
				varbinding_value = varbinding_value || '|' || COALESCE(upgrade_pkg_list, '')::text || ' ' || COALESCE(obsolete_pkg_list, '')::text;
			END IF;

			-- Special handling for segment lag/page lag alerts
			IF (template_name = 'Standby server lag behind the master by WAL segments'
				OR template_name = 'Standby server lag behind the master by WAL pages') THEN
				varbinding_oid = varbinding_oid || '|' || enterprise_oid || '.7.18';
				varbinding_value = varbinding_value || '|' || message_replication_lag;
			END IF;

			-- Send SNMP traps
			send_trap_val = pem.send_snmptrap(trap_oid, enterprise_oid, trap_version, varbinding_oid, varbinding_value);
		END IF;

		-- Script Execution
		IF is_execute_script AND (NOT is_acknowledged) AND (NOT is_flapping_detected) THEN
			PERFORM pem.create_script_job(NEW.alert_id, COALESCE(NEW.current_value, 0)::text, NEW.current_state::text, ''::text, is_execute_on_pem_server, code);
		END IF;

		-- submit to Nagios
		IF is_submit_to_nagios AND (NOT is_acknowledged) AND (NOT is_flapping_detected) THEN

			SELECT passive_check_result INTO passive_check_result_text FROM pem.create_passive_service_check_result(NEW.alert_id, 'Alert Detected',
															COALESCE(NEW.current_value, 0)::text,
															NEW.current_state::text);
			submit_to_nagios_val = pem.submit_to_nagios(passive_check_result_text);
		END IF;
	END IF;

	IF ((TG_OP = 'UPDATE') AND (NEW.current_state IS DISTINCT FROM OLD.current_state)) THEN
		-- Update state change count
		UPDATE pem.alert_status SET state_change_count = state_change_count + 1 WHERE alert_id = NEW.alert_id;

		-- Get group id's to send email
		SELECT ARRAY(SELECT DISTINCT UNNEST(pem.get_email_group_ids(NEW.alert_id, NEW.current_state::text, OLD.current_state::text))) INTO mail_group_id;

		-- Check whether to send trap according to alert level low, med and high.
		IF (NEW.current_state IS NOT NULL) AND (NEW.current_state::text = 'LOW' OR OLD.current_state::text = 'LOW') AND low_trap THEN
			is_send_trap = true;
		ELSIF (NEW.current_state IS NOT NULL) AND (NEW.current_state::text = 'MEDIUM' OR OLD.current_state::text = 'MEDIUM') AND med_trap THEN
			is_send_trap = true;
		ELSIF (NEW.current_state IS NOT NULL) AND (NEW.current_state::text = 'HIGH' OR OLD.current_state::text = 'HIGH') AND high_trap THEN
			is_send_trap = true;
		ELSIF (NEW.current_state IS NULL) AND (OLD.current_state IS NOT NULL) AND is_send_trap THEN
			is_send_trap = true;
		ELSE
			is_send_trap = false;
		END IF;

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

			-- Special handling for segment lag/page lag alerts
			IF (template_name = 'Standby server lag behind the master by WAL segments'
				OR template_name = 'Standby server lag behind the master by WAL pages') THEN
				message = message || E'\n' || message_replication_lag;
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
			IF (template_name = 'Agents Down') OR  (template_name = 'Servers Down') THEN
				varbinding_oid = varbinding_oid || '|' || enterprise_oid || '.7.15';
				varbinding_value = varbinding_value || '|' || down_objects_list::text;
			END IF;

			-- Special handling for 'Write lag Alert' alert
			IF (template_name = 'Number of standby servers lag behind the master by write location') THEN
				varbinding_oid = varbinding_oid || '|' || enterprise_oid || '.7.17';
				varbinding_value = varbinding_value || '|' || COALESCE(write_message_streaming_repl, '')::text;
			END IF;

			IF (template_name = 'Number of standby servers lag behind the master by flush location') THEN
				varbinding_oid = varbinding_oid || '|' || enterprise_oid || '.7.17';
				varbinding_value = varbinding_value || '|' || COALESCE(flush_message_streaming_repl, '')::text;
			END IF;

			IF (template_name = 'Number of standby servers lag behind the master by replay location') THEN
				varbinding_oid = varbinding_oid || '|' || enterprise_oid || '.7.17';
				varbinding_value = varbinding_value || '|' || COALESCE(replay_message_streaming_repl, '')::text;
			END IF;

			-- Special handling for "Package version mismatch" alert
			IF (template_name = 'Package version mismatch') THEN
				varbinding_oid = varbinding_oid || '|' || enterprise_oid || '.7.16';
				varbinding_value = varbinding_value || '|' || COALESCE(upgrade_pkg_list, '')::text || ' ' || COALESCE(obsolete_pkg_list, '')::text;
			END IF;

			-- Special handling for segment lag/page lag alerts
			IF (template_name = 'Standby server lag behind the master by WAL segments'
				OR template_name = 'Standby server lag behind the master by WAL pages') THEN
				varbinding_oid = varbinding_oid || '|' || enterprise_oid || '.7.18';
				varbinding_value = varbinding_value || '|' || message_replication_lag;
			END IF;

			-- Send SNMP traps
			send_trap_val = pem.send_snmptrap(trap_oid, enterprise_oid, trap_version, varbinding_oid, varbinding_value);
		END IF;

		-- Script Execution
		IF is_execute_script AND (NOT is_acknowledged) AND (NOT is_flapping_detected) THEN
			-- If current state is NULL means alert is cleared then need to check the value of is_execute_on_clear flag.
			IF (NEW.current_state IS NULL) THEN
				IF is_execute_on_clear THEN
					PERFORM pem.create_script_job(NEW.alert_id, COALESCE(NEW.current_value, 0)::text, NEW.current_state::text, 'CLEAR'::text, is_execute_on_pem_server, code);
				END IF;
			ELSE
				PERFORM pem.create_script_job(NEW.alert_id, COALESCE(NEW.current_value, 0)::text, NEW.current_state::text, OLD.current_state::text, is_execute_on_pem_server, code);
			END IF;
		END IF;

		-- submit to Nagios
		IF is_submit_to_nagios AND (NOT is_acknowledged) AND (NOT is_flapping_detected) THEN

			-- If current state is NULL means alert is cleared.
			IF (NEW.current_state IS NOT NULL) THEN
				-- if OLD current_state is not null means alert level changed.
				IF (OLD.current_state IS NOT NULL AND (OLD.current_state > NEW.current_state)) THEN
					SELECT passive_check_result INTO passive_check_result_text FROM pem.create_passive_service_check_result(NEW.alert_id,
																	'Alert Level Decreased',
																	COALESCE(NEW.current_value, 0)::text,
																	NEW.current_state::text);
					passive_check_result_text = regexp_replace(passive_check_result_text, '%OldState%', OLD.current_state::text);
					passive_check_result_text = regexp_replace(passive_check_result_text, '%NewState%', NEW.current_state::text);

				ELSIF (OLD.current_state IS NOT NULL AND (OLD.current_state < NEW.current_state)) THEN
					SELECT passive_check_result INTO passive_check_result_text FROM pem.create_passive_service_check_result(NEW.alert_id,
																	'Alert Level Increased',
																	COALESCE(NEW.current_value, 0)::text,
																	NEW.current_state::text);
					passive_check_result_text = regexp_replace(passive_check_result_text, '%OldState%', OLD.current_state::text);
					passive_check_result_text = regexp_replace(passive_check_result_text, '%NewState%', NEW.current_state::text);

				ELSE
					SELECT passive_check_result INTO passive_check_result_text FROM pem.create_passive_service_check_result(NEW.alert_id,
																	'Alert Detected',
																	COALESCE(NEW.current_value, 0)::text,
																	NEW.current_state::text);
				END IF;

			ELSE
				SELECT passive_check_result INTO passive_check_result_text FROM pem.create_passive_service_check_result(NEW.alert_id,
																'Alert Cleared',
																COALESCE(NEW.current_value, 0)::text,
																NEW.current_state::text);
			END IF;

			submit_to_nagios_val = pem.submit_to_nagios(passive_check_result_text);
		END IF;
	END IF;

	RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Fixes #41354
ALTER TABLE pemdata.disk_space ADD COLUMN device_id text DEFAULT '';
ALTER TABLE pemdata.disk_space DROP CONSTRAINT disk_space_pkey;
ALTER TABLE pemdata.disk_space ADD PRIMARY KEY(agent_id, mount_point, device_id);
ALTER TABLE pemhistory.disk_space ADD COLUMN device_id text DEFAULT '';
INSERT INTO pem.probe_column (
	probe_id, internal_name, display_name, display_position, classification,
	sql_data_type, unit_of_value, calculate_pit, discard_history,
	pit_by_default, is_graphable
) VALUES (
	(SELECT id FROM pem.probe WHERE internal_name='disk_space'), 'device_id',
	'Device ID', 7, 'k', 'text', '', false, false, false, false
);

CREATE OR REPLACE FUNCTION pemdata.copy_disk_space_to_history()
    RETURNS trigger
    LANGUAGE 'plpgsql'
    COST 100.0
    VOLATILE NOT LEAKPROOF
AS $BODY$
	BEGIN
		IF (TG_OP = 'INSERT' OR TG_OP = 'UPDATE') THEN
			INSERT INTO pemhistory.disk_space (recorded_time, agent_id, mount_point, file_system, size_mb, space_used_mb, space_available_mb, space_reserved_mb, device_id) VALUES (NEW.recorded_time, NEW.agent_id, NEW.mount_point, NEW.file_system, NEW.size_mb, NEW.space_used_mb, NEW.space_available_mb, NEW.space_reserved_mb, NEW.device_id);
			IF TG_OP = 'INSERT' AND NEW.device_id IS NOT NULL THEN
				UPDATE pemhistory.disk_space SET device_id = NEW.device_id WHERE agent_id = NEW.agent_id AND mount_point = NEW.mount_point;
			END IF;
		ELSIF EXISTS(SELECT 1 FROM pem.agent WHERE id = OLD.agent_id) THEN
			INSERT INTO pemhistory.disk_space (agent_id, mount_point) VALUES (OLD.agent_id, OLD.mount_point);
		END IF;
		RETURN NEW;
	END;
$BODY$;

ALTER TABLE pemdata.disk_busy_info ADD COLUMN device_id text DEFAULT '';
ALTER TABLE pemdata.disk_busy_info DROP CONSTRAINT disk_busy_info_pkey;
ALTER TABLE pemdata.disk_busy_info ADD PRIMARY KEY(agent_id, mount_point, device_id);
ALTER TABLE pemhistory.disk_busy_info ADD COLUMN device_id text DEFAULT '';
INSERT INTO pem.probe_column (
	probe_id, internal_name, display_name, display_position, classification,
	sql_data_type, unit_of_value, calculate_pit, discard_history,
	pit_by_default, is_graphable
) VALUES (
	(SELECT id FROM pem.probe WHERE internal_name='disk_busy_info'), 'device_id',
	'Device ID', 3, 'k', 'text', '', false, false, false, false
);

CREATE OR REPLACE FUNCTION pemdata.copy_disk_busy_info_to_history()
    RETURNS trigger
    LANGUAGE 'plpgsql'
    COST 100.0
    VOLATILE NOT LEAKPROOF
AS $BODY$
	BEGIN
		IF (TG_OP = 'INSERT' OR TG_OP = 'UPDATE') THEN
			INSERT INTO pemhistory.disk_busy_info (recorded_time, agent_id, mount_point, disk_busy, device_id) VALUES (NEW.recorded_time, NEW.agent_id, NEW.mount_point, NEW.disk_busy, NEW.device_id);
			IF TG_OP = 'INSERT' AND NEW.device_id IS NOT NULL THEN
				UPDATE pemhistory.disk_busy_info SET device_id = NEW.device_id WHERE agent_id = NEW.agent_id AND mount_point = NEW.mount_point;
			END IF;
		ELSIF EXISTS(SELECT 1 FROM pem.agent WHERE id = OLD.agent_id) THEN
			INSERT INTO pemhistory.disk_busy_info (agent_id, mount_point) VALUES (OLD.agent_id, OLD.mount_point);
		END IF;
		RETURN NEW;
	END;
$BODY$;

ALTER TABLE pemdata.io_analysis ADD COLUMN device_id text DEFAULT '';
ALTER TABLE pemdata.io_analysis DROP CONSTRAINT io_analysis_pkey;
ALTER TABLE pemdata.io_analysis ADD PRIMARY KEY(agent_id, disk_drive, device_id);
ALTER TABLE pemhistory.io_analysis ADD COLUMN device_id text DEFAULT '';
INSERT INTO pem.probe_column (
	probe_id, internal_name, display_name, display_position, classification,
	sql_data_type, unit_of_value, calculate_pit, discard_history,
	pit_by_default, is_graphable
) VALUES (
	(SELECT id FROM pem.probe WHERE internal_name='io_analysis'), 'device_id',
	'Device ID', 4, 'k', 'text', '', false, false, false, false
);

CREATE OR REPLACE FUNCTION pemdata.copy_io_analysis_to_history()
    RETURNS trigger
    LANGUAGE 'plpgsql'
    COST 100.0
    VOLATILE NOT LEAKPROOF
AS $BODY$
	BEGIN
		IF (TG_OP = 'INSERT' OR TG_OP = 'UPDATE') THEN
			INSERT INTO pemhistory.io_analysis (recorded_time, agent_id, disk_drive, blks_read, blks_read_pit, blks_wrtn, blks_wrtn_pit, device_id) VALUES (NEW.recorded_time, NEW.agent_id, NEW.disk_drive, NEW.blks_read, NEW.blks_read_pit, NEW.blks_wrtn, NEW.blks_wrtn_pit, NEW.device_id);
			IF TG_OP = 'INSERT' AND NEW.device_id IS NOT NULL THEN
				UPDATE pemhistory.io_analysis SET device_id = NEW.device_id WHERE agent_id = NEW.agent_id AND disk_drive = NEW.disk_drive;
			END IF;
		ELSIF EXISTS(SELECT 1 FROM pem.agent WHERE id = OLD.agent_id) THEN
			INSERT INTO pemhistory.io_analysis (agent_id, disk_drive) VALUES (OLD.agent_id, OLD.disk_drive);
		END IF;
		RETURN NEW;
	END;
$BODY$;

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
	CASE WHEN (device_id is NOT NULL and device_id != '''') THEN mount_point || '' ('' || device_id || '')'' ELSE mount_point END AS "Mounted On"
FROM pemdata.disk_space
WHERE agent_id = $1::int4
ORDER BY 3::int DESC' WHERE id = 44;

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
	CASE WHEN (device_id is NOT NULL and device_id != '''') THEN mount_point || '' ('' || device_id || '')'' ELSE mount_point END AS "Mounted On"
FROM pemdata.disk_space
WHERE agent_id = $1::int4
ORDER BY 3::int DESC' WHERE id = 73;

UPDATE pem.chart SET labels = ARRAY['Space Used (MB)'] WHERE name = 'Disk Space Utilization';

COMMIT TRANSACTION;
