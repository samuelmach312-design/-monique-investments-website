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

-- Upgrade script for v2.1.0rc1 to v2.1.0 GA

BEGIN TRANSACTION;

CREATE OR REPLACE FUNCTION pem.schema_version()
  RETURNS integer AS
'SELECT 201204101::integer;'
  LANGUAGE 'sql' IMMUTABLE;

-- add support for PPAS 9.1
INSERT INTO pem.server_version VALUES (20901, 'Advanced Server 9.1');

-- support for oc_schema probe for 9.1AS
INSERT INTO pem.probe_server_version
	(probe_id, server_version_id, probe_code)
VALUES
	((SELECT id FROM pem.probe WHERE internal_name = 'oc_schema'), 20901,
		E'SELECT nspname AS schema_name FROM pg_catalog.pg_namespace WHERE (nspname = ''pg_catalog'' OR nspname NOT LIKE E''pg\\\\_%'') AND nspparent = 0');

-- support for oc_function probe for 9.1AS
INSERT INTO pem.probe_server_version
	(probe_id, server_version_id, probe_code)
VALUES
	((SELECT id FROM pem.probe WHERE internal_name = 'oc_function'), 20901, $sql$
SELECT	'' AS package_name, f.proname AS function_name, f.protype AS function_type,
		f.prorettype::regtype AS return_type, f.proargtypes::regtype[] AS arg_types
FROM	pg_catalog.pg_namespace AS s	-- schema
JOIN	pg_catalog.pg_proc AS f			-- function
ON		f.pronamespace = s.oid
WHERE	s.nspparent = 0 -- select schema that is not a child of some other schema
AND		s.nspname = %{schema_name}
UNION ALL
SELECT	p.nspname AS package_name, f.proname AS function_name, f.protype AS function_type,
		f.prorettype::regtype AS return_type, f.proargtypes::regtype[] AS arg_types
FROM	pg_catalog.pg_namespace AS s	-- schema
JOIN	pg_catalog.pg_namespace AS p	-- package
ON		p.nspparent = s.oid
JOIN	pg_catalog.pg_proc AS f			-- function
ON		f.pronamespace = p.oid
WHERE	p.nspparent <> 0 -- select schema that _is_ a child of some other schema
AND		s.nspname = %{schema_name}$sql$);

-- support for database_statistics probe for 9.1AS
INSERT INTO pem.probe_server_version
	(probe_id, server_version_id, probe_code)
VALUES
	((SELECT id FROM pem.probe WHERE internal_name = 'database_statistics'),
	20901,
	'SELECT d1.datname AS database_name, d1.numbackends,
		(SELECT COALESCE(count(current_query)::bigint, 0::bigint) FROM pg_catalog.pg_stat_activity WHERE datname = d1.datname AND current_query = ''<IDLE>'') AS idle_backends,
		d1.xact_commit, d1.xact_rollback, d1.blks_hit, d1.blks_icache_hit, d1.blks_read, d1.tup_returned,
		d1.tup_fetched, d1.tup_inserted, d1.tup_updated, d1.tup_deleted
		FROM pg_catalog.pg_stat_database d1');

-- support for table_statistics probe for 9.1AS
INSERT INTO pem.probe_server_version
    (probe_id, server_version_id, probe_code)
VALUES
	((SELECT id FROM pem.probe WHERE internal_name = 'table_statistics'), 20901, NULL);

-- support for function_statistics probe for 9.1AS
INSERT INTO pem.probe_server_version
	(probe_id, server_version_id, probe_code)
VALUES
	((SELECT id FROM pem.probe WHERE internal_name = 'function_statistics'), 20901, $sql$
SELECT	s.nspname AS schema_name, '' AS package_name, f.proname AS function_name,
		f.protype AS function_type, f.prorettype::regtype AS return_type,
		f.proargtypes::regtype[] AS arg_types,
		fs.calls AS call_count, fs.total_time, fs.self_time
FROM	pg_catalog.pg_namespace AS s			-- schema
JOIN	pg_catalog.pg_proc AS f					-- function
ON		f.pronamespace = s.oid
JOIN	pg_catalog.pg_stat_user_functions AS fs	-- Func. stats
ON		fs.funcid = f.oid
WHERE	s.nspparent = 0 -- select schema that is not a child of some other schema
UNION ALL
SELECT	s.nspname AS schema_name, p.nspname AS package_name, f.proname AS function_name,
		f.protype AS function_type, f.prorettype::regtype AS return_type,
		f.proargtypes::regtype[] AS arg_types,
		fs.calls AS call_count, fs.total_time, fs.self_time
FROM	pg_catalog.pg_namespace AS s			-- schema
JOIN	pg_catalog.pg_namespace AS p			-- package
ON		p.nspparent = s.oid
JOIN	pg_catalog.pg_proc AS f					-- function
ON		f.pronamespace = p.oid
JOIN	pg_catalog.pg_stat_user_functions AS fs	-- Func. stats
ON		fs.funcid = f.oid
WHERE	p.nspparent <> 0 -- select schema that _is_ a child of some other schema
$sql$);

-- support for table_size probe for 9.1AS
INSERT INTO pem.probe_server_version
	(probe_id, server_version_id, probe_code)
VALUES
	((SELECT id FROM pem.probe WHERE internal_name = 'table_size'), 20901,
	'SELECT n.nspname AS schema_name, c.relname AS table_name, pg_relation_size(c.oid) / 1048576 AS table_size_mb, pg_indexes_size(c.oid) / 1048576 AS size_of_indexes_mb, pg_total_relation_size(c.oid) / 1048576 AS total_table_size_mb FROM pg_class c, pg_namespace n WHERE c.relnamespace = n.oid AND c.relkind = ''r''');


-- support for background_writer_statistics probe for 9.1AS
INSERT INTO pem.probe_server_version
	(probe_id, server_version_id, probe_code)
VALUES
	((SELECT id FROM pem.probe WHERE internal_name = 'background_writer_statistics'), 20901, NULL);

-- support for session_info probe for 9.1AS
INSERT INTO pem.probe_server_version
	(probe_id, server_version_id, probe_code)
VALUES
	((SELECT id FROM pem.probe WHERE internal_name = 'session_info'), 20901, NULL);

-- support for system_waits probe for 9.1AS
INSERT INTO pem.probe_server_version
	(probe_id, server_version_id, probe_code)
VALUES
	((SELECT id FROM pem.probe WHERE internal_name = 'system_waits'), 20901, NULL);

-- support for session_waits probe for 9.1AS
INSERT INTO pem.probe_server_version
	(probe_id, server_version_id, probe_code)
VALUES
	((SELECT id FROM pem.probe WHERE internal_name = 'session_waits'), 20901, NULL);

-- support for lock_info probe for 9.1AS
INSERT INTO pem.probe_server_version
	(probe_id, server_version_id, probe_code)
VALUES
	((SELECT id FROM pem.probe WHERE internal_name = 'lock_info'), 20901, NULL);

-- support for audit_configuration probe for 9.1AS
INSERT INTO pem.probe_server_version
	(probe_id, server_version_id, probe_code)
VALUES
	((SELECT id FROM pem.probe WHERE internal_name = 'audit_configuration'), 20901, NULL);


COMMIT TRANSACTION;
