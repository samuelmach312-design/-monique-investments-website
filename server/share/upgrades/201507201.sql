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
'SELECT 201507201::integer;'
  LANGUAGE 'sql' IMMUTABLE;
COMMENT ON FUNCTION pem.schema_version() IS 'Returns the version number of the PEM schema';

INSERT INTO pem.server_version VALUES (10905, 'PostgreSQL 9.5');
INSERT INTO pem.server_version VALUES (20905, 'Advanced Server 9.5');

ALTER TABLE pemdata.installed_packages ADD COLUMN running_on_port integer DEFAULT NULL;
ALTER TABLE pemdata.installed_packages ADD COLUMN serviceid text DEFAULT NULL;
ALTER TABLE pemdata.installed_packages ADD COLUMN service_account text DEFAULT NULL;
ALTER TABLE pemdata.installed_packages ADD COLUMN installation_dir text DEFAULT NULL;
ALTER TABLE pemdata.oc_function ADD COLUMN function_binary text DEFAULT NULL;
ALTER TABLE pemdata.oc_function ADD COLUMN extension_name text DEFAULT NULL;
ALTER TABLE pemhistory.oc_function ADD COLUMN function_binary text DEFAULT NULL;
ALTER TABLE pemhistory.oc_function ADD COLUMN extension_name text DEFAULT NULL;
ALTER TABLE pem.job ADD COLUMN dependent_on_job integer DEFAULT NULL;
ALTER TABLE pem.job ADD COLUMN execute_on_dep_job_status char NOT NULL CHECK (execute_on_dep_job_status IN ('s', 'f', 'i', 'd')) DEFAULT 's';
COMMENT ON COLUMN pem.job.execute_on_dep_job_status IS 'Execute the job only when status of the dependent job is one of this: s=successfully finished, f=failed, i=no steps to execute, d=aborted';

CREATE OR REPLACE FUNCTION pem.job_is_complete(job_id integer, status char) RETURNS BOOL AS $$
DECLARE
	res boolean := false;
BEGIN
	IF job_id IS NOT NULL THEN
		SELECT CASE WHEN (status = 'i' AND a.jlgstatus != 'r') OR status = a.jlgstatus THEN true ELSE false END INTO res
		FROM
		(
			SELECT l.jlgstatus jlgstatus
			FROM pem.job j
			LEFT JOIN pem.joblog l ON j.jobid = l.jlgjobid
			WHERE j.jobid = job_id
			ORDER BY l.jlgstart DESC LIMIT 1
		) a;
	END IF;

	RETURN res;
END;
$$ LANGUAGE plpgsql;

UPDATE pem.probe_server_version SET probe_code = $sql$
	SELECT
	'' AS package_name, f.proname AS function_name, '0'::"char" AS function_type,
	f.prorettype::regtype AS return_type, f.proargtypes::regtype[] AS arg_types,
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
AND server_version_id IN (10901, 10902, 10903, 10904, 10905);

UPDATE pem.probe_server_version SET probe_code = $sql$
	SELECT	'' AS package_name, f.proname AS function_name, f.protype AS function_type,
			f.prorettype::regtype AS return_type, f.proargtypes::regtype[] AS arg_types,
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
			f.prorettype::regtype AS return_type, f.proargtypes::regtype[] AS arg_types,
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
AND server_version_id IN (20901, 20902, 20903, 20904, 20905);

-- Streaming Replication tables
CREATE TABLE pem.sr_master (
	srid serial NOT NULL PRIMARY KEY,
	agent_id integer NOT NULL,
	sr_pkg_id text NOT NULL,
	sr_pkg_version text NOT NULL,
	ip_address text NOT NULL,
	replication_user_name text,
	replication_password text,
	database_user_name text,
	database_password text,
	replication_slot_name text
);
COMMENT ON TABLE pem.sr_master IS 'Streaming replication master node information';
COMMENT ON COLUMN pem.sr_master.srid IS 'Unique streaming replication ID';

CREATE TABLE pem.sr_standby (
	srid serial NOT NULL PRIMARY KEY,
	msrid int4 NOT NULL
		REFERENCES pem.sr_master (srid) ON DELETE CASCADE ON UPDATE RESTRICT,
	agent_id integer NOT NULL,
	ip_address text NOT NULL,
	hot_standby boolean DEFAULT false,
	sync_priority integer,
	backup_data_dir boolean DEFAULT false
);
COMMENT ON TABLE pem.sr_standby IS 'Streaming replication standby node information';
COMMENT ON COLUMN pem.sr_standby.srid IS 'Unique streaming replication ID for standby table';
COMMENT ON COLUMN pem.sr_standby.msrid IS 'Reference of unique streaming replication ID of sr_master table';

--
-- Probe: extension object catalog
--
INSERT INTO pem.probe
	(display_name, internal_name, collection_method, target_type_id,
	 enabled_by_default, force_enabled, default_execution_frequency,
	 default_lifetime, any_server_version, probe_code)
VALUES
	('Object Catalog: Extension', 'oc_extension', 's', 300, true, true, 86400, 30, false, $sql$
	SELECT e.extname AS extension_name, e.extversion AS extension_version,
		n.nspname AS extension_namespace, e.extrelocatable AS extension_relocatable
	FROM
	pg_extension e
	LEFT JOIN pg_catalog.pg_namespace n ON (e.extnamespace = n.oid)$sql$
);

INSERT INTO pem.probe_server_version
    (probe_id, server_version_id, probe_code)
SELECT
	(SELECT max(id) FROM pem.probe), v.version, NULL
FROM
	(VALUES (10901), (10902), (10903), (10904), (10905), (20901), (20902), (20903), (20904), (20905))
		v(version);

INSERT INTO pem.probe_column
	(probe_id, internal_name, display_name, display_position, classification,
	sql_data_type, unit_of_value, calculate_pit, discard_history, pit_by_default, is_graphable)
SELECT
	(SELECT max(id) FROM pem.probe),
	v.internal_name, v.display_name, v.display_position, v.classification,
	v.sql_data_type, v.unit_of_value, v.calculate_pit, v.discard_history, v.pit_by_default, v.is_graphable
FROM
	(VALUES
		('extension_name', 'Extension Name', 1, 'k', 'text', '', false, false, false, false),
		('extension_version', 'Extension Version', 2, 'k', 'text', '', false, false, false, false),
		('extension_namespace', 'Extension Namespace', 3, 'k', 'text', '', false, false, false, false),
		('extension_relocatable', 'Return Data Type', 4, 'm', 'text', '', false, false, false, false)
	) v(internal_name, display_name, display_position, classification,
		sql_data_type, unit_of_value, calculate_pit, discard_history, pit_by_default, is_graphable);

SELECT pem.create_data_and_history_tables();

-- oc_schmea support
INSERT INTO pem.probe_server_version(probe_id,server_version_id,probe_code)
       VALUES((SELECT id FROM pem.probe WHERE internal_name='oc_schema'), 10905, NULL);

INSERT INTO pem.probe_server_version(probe_id,server_version_id,probe_code)
       VALUES((SELECT id FROM pem.probe WHERE internal_name='oc_schema'), 20905,
       E'SELECT nspname AS schema_name FROM pg_catalog.pg_namespace WHERE (nspname = ''pg_catalog'' OR nspname NOT LIKE E''pg\\\\_%'') AND nspparent = 0');

-- oc_function support
INSERT INTO pem.probe_server_version(probe_id,server_version_id,probe_code)
       VALUES((SELECT id FROM pem.probe WHERE internal_name='oc_function'), 10905,
	   $sql$
	SELECT
	'' AS package_name, f.proname AS function_name, '0'::"char" AS function_type,
	f.prorettype::regtype AS return_type, f.proargtypes::regtype[] AS arg_types,
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
       VALUES((SELECT id FROM pem.probe WHERE internal_name='oc_function'), 20905,
       $sql$
	SELECT	'' AS package_name, f.proname AS function_name, f.protype AS function_type,
			f.prorettype::regtype AS return_type, f.proargtypes::regtype[] AS arg_types,
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
			f.prorettype::regtype AS return_type, f.proargtypes::regtype[] AS arg_types,
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
       VALUES((SELECT id FROM pem.probe WHERE internal_name='database_statistics'), 10905,
       'SELECT d1.datname AS database_name, d1.numbackends,
            (SELECT COALESCE(count(query)::bigint, 0::bigint) FROM pg_catalog.pg_stat_activity WHERE datname = d1.datname AND state = ''idle'') AS idl
           d1.xact_commit, d1.xact_rollback, d1.blks_hit, NULL::bigint AS blks_icache_hit, d1.blks_read,
            d1.tup_returned, d1.tup_fetched, d1.tup_inserted, d1.tup_updated, d1.tup_deleted
      FROM pg_catalog.pg_stat_database d1');

INSERT INTO pem.probe_server_version(probe_id,server_version_id,probe_code)
       VALUES((SELECT id FROM pem.probe WHERE internal_name='database_statistics'), 20905,
       'SELECT d1.datname AS database_name, d1.numbackends,
            (SELECT COALESCE(count(query)::bigint, 0::bigint) FROM pg_catalog.pg_stat_activity WHERE datname = d1.datname AND state = ''idle'') AS idl
            d1.xact_commit, d1.xact_rollback, d1.blks_hit, d1.blks_icache_hit, d1.blks_read, d1.tup_returned,
            d1.tup_fetched, d1.tup_inserted, d1.tup_updated, d1.tup_deleted
     FROM pg_catalog.pg_stat_database d1');

-- table_statistics support
INSERT INTO pem.probe_server_version(probe_id,server_version_id,probe_code)
       VALUES((SELECT id FROM pem.probe WHERE internal_name='table_statistics'), 10905, NULL);

INSERT INTO pem.probe_server_version(probe_id,server_version_id,probe_code)
       VALUES((SELECT id FROM pem.probe WHERE internal_name='table_statistics'), 20905, NULL);

-- function_statistics support
INSERT INTO pem.probe_server_version(probe_id,server_version_id,probe_code)
       VALUES((SELECT id FROM pem.probe WHERE internal_name='function_statistics'), 10905, NULL);

INSERT INTO pem.probe_server_version(probe_id,server_version_id,probe_code)
       VALUES((SELECT id FROM pem.probe WHERE internal_name='function_statistics'), 20905,
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
       VALUES((SELECT id FROM pem.probe WHERE internal_name='table_size'), 10905,
       'SELECT n.nspname AS schema_name, c.relname AS table_name, pg_relation_size(c.oid) / 1048576 AS table_size_mb, pg_indexes_size(c.oid) / 1048576 AS size_of_indexes_mb, pg_total_relation_size(c.oid) / 1048576 AS total_table_size_mb FROM pg_class c, pg_namespace n WHERE c.relnamespace = n.oid AND c.relkind = ''r''');

INSERT INTO pem.probe_server_version(probe_id,server_version_id,probe_code)
       VALUES((SELECT id FROM pem.probe WHERE internal_name='table_size'), 20905,
       'SELECT n.nspname AS schema_name, c.relname AS table_name, pg_relation_size(c.oid) / 1048576 AS table_size_mb, pg_indexes_size(c.oid) / 1048576 AS size_of_indexes_mb, pg_total_relation_size(c.oid) / 1048576 AS total_table_size_mb FROM pg_class c, pg_namespace n WHERE c.relnamespace = n.oid AND c.relkind = ''r''');

-- background_writer_statistics support
INSERT INTO pem.probe_server_version(probe_id,server_version_id,probe_code)
       VALUES((SELECT id FROM pem.probe WHERE internal_name='background_writer_statistics'), 10905, NULL);

INSERT INTO pem.probe_server_version(probe_id,server_version_id,probe_code)
       VALUES((SELECT id FROM pem.probe WHERE internal_name='background_writer_statistics'), 20905, NULL);

-- session_info support
INSERT INTO pem.probe_server_version(probe_id,server_version_id,probe_code)
       VALUES((SELECT id FROM pem.probe WHERE internal_name='session_info'), 10905,
       'SELECT datname AS database_name, pid AS procpid, usename, client_addr, client_port, backend_start, xact_start, query_start,'
                ' waiting AS is_waiting, query = $$<IDLE>$$ AS is_idle,'
                ' query = $$<IDLE> in transaction$$ AS is_idle_in_transaction,'
                ' query ilike $$VACUUM%$$ as is_vacuum,'
                ' client_port IS NULL AND (query like $$autovacuum:%$$ OR query like $$VACUUM%$$) as is_autovacuum,'
                ' now() AS capture_time'
        ' FROM pg_catalog.pg_stat_activity');

INSERT INTO pem.probe_server_version(probe_id,server_version_id,probe_code)
       VALUES((SELECT id FROM pem.probe WHERE internal_name='session_info'), 20905,
       'SELECT datname AS database_name, pid AS procpid, usename, client_addr, client_port, backend_start, xact_start, query_start,'
		' waiting AS is_waiting, query = $$<IDLE>$$ AS is_idle,'
                ' query = $$<IDLE> in transaction$$ AS is_idle_in_transaction,'
                ' query ilike $$VACUUM%$$ as is_vacuum,'
                ' client_port IS NULL AND (query like $$autovacuum:%$$ OR query like $$VACUUM%$$) as is_autovacuum,'
                ' now() AS capture_time'
        ' FROM pg_catalog.pg_stat_activity');

-- lock_info support
INSERT INTO pem.probe_server_version(probe_id,server_version_id,probe_code)
       VALUES((SELECT id FROM pem.probe WHERE internal_name='lock_info'), 10905,
       $sql$
SELECT COALESCE(d.datname, '')                 AS database_name,
               COALESCE(l.pid::bigint, -1)             AS procpid,
               l.relation::text::numeric               AS objid,               -- relation/XID/VXID/classid
               COALESCE(l.page::bigint, -1)    AS objsubid,    -- page/objid
               COALESCE(l.tuple::bigint, -1)   AS objsubsubid, -- tuple/objsubid
               l.locktype, l.mode AS lockmode, l.granted AS lockgranted
FROM   pg_catalog.pg_locks AS l
LEFT JOIN      pg_catalog.pg_stat_activity AS sa
ON             l.pid = sa.pid
JOIN   pg_catalog.pg_database AS d
ON             sa.datid = d.oid
WHERE  l.locktype IN ('relation', 'extend', 'page', 'tuple')
UNION ALL
SELECT COALESCE(d.datname, '')         AS database_name,
ON             l.pid = sa.pid
JOIN   pg_catalog.pg_database AS d
ON             sa.datid = d.oid
WHERE  l.locktype IN ('relation', 'extend', 'page', 'tuple')
UNION ALL
SELECT COALESCE(d.datname, '')         AS database_name,
               COALESCE(l.pid::bigint, -1)     AS procpid,
               transactionid::text::numeric    AS objid,       -- relation/XID/VXID/classid
               -1                                                      AS objsubid,    -- page/objid
               -1                                                      AS objsubsubid, -- tuple/objsubid
               l.locktype, l.mode AS lockmode, l.granted AS lockgranted
FROM   pg_catalog.pg_locks AS l
LEFT JOIN      pg_catalog.pg_stat_activity AS sa
ON             l.pid = sa.pid
JOIN   pg_catalog.pg_database AS d
ON             sa.datid = d.oid
WHERE  l.locktype = 'transactionid'
UNION ALL
SELECT COALESCE(d.datname, '')                         AS database_name,
               COALESCE(l.pid::bigint, -1)                     AS procpid,
               regexp_replace(l.virtualxid, '/', '.')::numeric AS objid,-- relation/XID/VXID/classid
               -1                                                                      AS objsubid,    -- page/objid
               -1                                                                      AS objsubsubid, -- tuple/objsubid
               l.locktype, l.mode AS lockmode, l.granted AS lockgranted
FROM   pg_catalog.pg_locks AS l
LEFT JOIN      pg_catalog.pg_stat_activity AS sa
ON             l.pid = sa.pid
JOIN   pg_catalog.pg_database AS d
ON             sa.datid = d.oid
WHERE  l.locktype = 'virtualxid'
UNION ALL
SELECT COALESCE(d.datname, '')                 AS database_name,
               COALESCE(l.pid::bigint, -1)             AS procpid,
               classid::text::numeric                  AS objid,-- relation/XID/VXID/classid
               COALESCE(l.objid::bigint, -1)   AS objsubid,    -- page/objid
               COALESCE(l.objsubid::bigint, -1)AS objsubsubid, -- tuple/objsubid
               l.locktype, l.mode AS lockmode, l.granted AS lockgranted
FROM   pg_catalog.pg_locks AS l
LEFT JOIN      pg_catalog.pg_stat_activity AS sa
ON             l.pid = sa.pid
JOIN   pg_catalog.pg_database AS d
ON             sa.datid = d.oid
WHERE  l.locktype IN ('object', 'advisory')$sql$);

INSERT INTO pem.probe_server_version(probe_id,server_version_id,probe_code)
       VALUES((SELECT id FROM pem.probe WHERE internal_name='lock_info'), 20905,
       $sql$
SELECT COALESCE(d.datname, '')                 AS database_name,
               COALESCE(l.pid::bigint, -1)             AS procpid,
               l.relation::text::numeric               AS objid,               -- relation/XID/VXID/classid
               COALESCE(l.page::bigint, -1)    AS objsubid,    -- page/objid
               COALESCE(l.tuple::bigint, -1)   AS objsubsubid, -- tuple/objsubid
               l.locktype, l.mode AS lockmode, l.granted AS lockgranted
FROM   pg_catalog.pg_locks AS l
LEFT JOIN      pg_catalog.pg_stat_activity AS sa
ON             l.pid = sa.pid
JOIN   pg_catalog.pg_database AS d
ON             sa.datid = d.oid
WHERE  l.locktype IN ('relation', 'extend', 'page', 'tuple')
UNION ALL
SELECT COALESCE(d.datname, '')         AS database_name,
               COALESCE(l.pid::bigint, -1)     AS procpid,
               transactionid::text::numeric    AS objid,       -- relation/XID/VXID/classid
               -1                                                      AS objsubid,    -- page/objid
               -1                                                      AS objsubsubid, -- tuple/objsubid
               l.locktype, l.mode AS lockmode, l.granted AS lockgranted
FROM   pg_catalog.pg_locks AS l
LEFT JOIN      pg_catalog.pg_stat_activity AS sa
ON             l.pid = sa.pid
JOIN   pg_catalog.pg_database AS d
ON             sa.datid = d.oid
WHERE  l.locktype = 'transactionid'
UNION ALL
SELECT COALESCE(d.datname, '')                         AS database_name,
               COALESCE(l.pid::bigint, -1)                     AS procpid,
               regexp_replace(l.virtualxid, '/', '.')::numeric AS objid,-- relation/XID/VXID/classid
               -1                                                                      AS objsubid,    -- page/objid
               -1                                                                      AS objsubsubid, -- tuple/objsubid
               l.locktype, l.mode AS lockmode, l.granted AS lockgranted
FROM   pg_catalog.pg_locks AS l
LEFT JOIN      pg_catalog.pg_stat_activity AS sa
ON             l.pid = sa.pid
JOIN   pg_catalog.pg_database AS d
ON             sa.datid = d.oid
WHERE  l.locktype = 'virtualxid'
UNION ALL
SELECT COALESCE(d.datname, '')                 AS database_name,
               COALESCE(l.pid::bigint, -1)             AS procpid,
               classid::text::numeric                  AS objid,-- relation/XID/VXID/classid
               COALESCE(l.objid::bigint, -1)   AS objsubid,    -- page/objid
               COALESCE(l.objsubid::bigint, -1)AS objsubsubid, -- tuple/objsubid
               l.locktype, l.mode AS lockmode, l.granted AS lockgranted
FROM   pg_catalog.pg_locks AS l
LEFT JOIN      pg_catalog.pg_stat_activity AS sa
ON             l.pid = sa.pid
JOIN   pg_catalog.pg_database AS d
ON             sa.datid = d.oid
WHERE  l.locktype IN ('object', 'advisory')$sql$);

-- streaming_replication support
INSERT INTO pem.probe_server_version(probe_id,server_version_id,probe_code)
       VALUES((SELECT id FROM pem.probe WHERE internal_name='streaming_replication'), 10905, NULL);

INSERT INTO pem.probe_server_version(probe_id,server_version_id,probe_code)
       VALUES((SELECT id FROM pem.probe WHERE internal_name='streaming_replication'), 20905, NULL);

-- streaming_replication_db_conflicts support
INSERT INTO pem.probe_server_version(probe_id,server_version_id,probe_code)
       VALUES((SELECT id FROM pem.probe WHERE internal_name='streaming_replication_db_conflicts'), 10905, NULL);

INSERT INTO pem.probe_server_version(probe_id,server_version_id,probe_code)
       VALUES((SELECT id FROM pem.probe WHERE internal_name='streaming_replication_db_conflicts'), 20905, NULL);

-- xdb_smr_mmr_replication support
INSERT INTO pem.probe_server_version(probe_id,server_version_id,probe_code)
       VALUES((SELECT id FROM pem.probe WHERE internal_name='xdb_smr_mmr_replication'), 10905, NULL);

INSERT INTO pem.probe_server_version(probe_id,server_version_id,probe_code)
       VALUES((SELECT id FROM pem.probe WHERE internal_name='xdb_smr_mmr_replication'), 20905, NULL);

-- oc_views support
INSERT INTO pem.probe_server_version(probe_id,server_version_id,probe_code)
       VALUES((SELECT id FROM pem.probe WHERE internal_name='oc_views'), 10905, NULL);

INSERT INTO pem.probe_server_version(probe_id,server_version_id,probe_code)
       VALUES((SELECT id FROM pem.probe WHERE internal_name='oc_views'), 20905, NULL);

-- mview_bloat support
INSERT INTO pem.probe_server_version(probe_id,server_version_id,probe_code)
       VALUES((SELECT id FROM pem.probe WHERE internal_name='mview_bloat'), 10905, NULL);

INSERT INTO pem.probe_server_version(probe_id,server_version_id,probe_code)
       VALUES((SELECT id FROM pem.probe WHERE internal_name='mview_bloat'), 20905, NULL);

-- mview_frozenxid support
INSERT INTO pem.probe_server_version(probe_id,server_version_id,probe_code)
       VALUES((SELECT id FROM pem.probe WHERE internal_name='mview_frozenxid'), 10905, NULL);

INSERT INTO pem.probe_server_version(probe_id,server_version_id,probe_code)
       VALUES((SELECT id FROM pem.probe WHERE internal_name='mview_frozenxid'), 20905, NULL);

-- mview_size support
INSERT INTO pem.probe_server_version(probe_id,server_version_id,probe_code)
       VALUES((SELECT id FROM pem.probe WHERE internal_name='mview_size'), 10905, NULL);

INSERT INTO pem.probe_server_version(probe_id,server_version_id,probe_code)
       VALUES((SELECT id FROM pem.probe WHERE internal_name='mview_size'), 20905, NULL);

-- streaming_replication_lag_time support
INSERT INTO pem.probe_server_version(probe_id,server_version_id,probe_code)
       VALUES((SELECT id FROM pem.probe WHERE internal_name='streaming_replication_lag_time'), 10905, NULL);

INSERT INTO pem.probe_server_version(probe_id,server_version_id,probe_code)
       VALUES((SELECT id FROM pem.probe WHERE internal_name='streaming_replication_lag_time'), 20905, NULL);

-- wal_archive_status support
INSERT INTO pem.probe_server_version(probe_id,server_version_id,probe_code)
       VALUES((SELECT id FROM pem.probe WHERE internal_name='wal_archive_status'), 10905,
       'SELECT archived_count, last_archived_time, failed_count, last_failed_time FROM pg_catalog.pg_stat_archiver');

INSERT INTO pem.probe_server_version(probe_id,server_version_id,probe_code)
       VALUES((SELECT id FROM pem.probe WHERE internal_name='wal_archive_status'), 20905,
       'SELECT archived_count, last_archived_time, failed_count, last_failed_time FROM pg_catalog.pg_stat_archiver');

-- system_waits support
INSERT INTO pem.probe_server_version(probe_id,server_version_id,probe_code)
       VALUES((SELECT id FROM pem.probe WHERE internal_name='system_waits'), 20905, NULL);

-- session_waits support
INSERT INTO pem.probe_server_version(probe_id,server_version_id,probe_code)
       VALUES((SELECT id FROM pem.probe WHERE internal_name='session_waits'), 20905,
       'SELECT sw.backend_id, psa.datname AS dbname, psa.usename, sw.wait_name, sw.wait_count, avg_wait_time, max_wait_time, total_wait_time FROM session_waits sw, pg_stat_activity psa WHERE sw.backend_id = psa.pid');

-- audit_configuration support
INSERT INTO pem.probe_server_version(probe_id,server_version_id,probe_code)
       VALUES((SELECT id FROM pem.probe WHERE internal_name='audit_configuration'), 20905, NULL);

--efm_cluster_info support
INSERT INTO pem.probe_server_version(probe_id, server_version_id, probe_code)
VALUES ((SELECT id from pem.probe WHERE internal_name ='efm_cluster_info'), 10905, NULL);
INSERT INTO pem.probe_server_version(probe_id, server_version_id, probe_code)
VALUES ((SELECT id from pem.probe WHERE internal_name ='efm_cluster_info'), 20905, NULL);

--efm_cluster_node_status support
INSERT INTO pem.probe_server_version(probe_id, server_version_id, probe_code)
VALUES ((SELECT id from pem.probe WHERE internal_name ='efm_cluster_node_status'), 10905, NULL);
INSERT INTO pem.probe_server_version(probe_id, server_version_id, probe_code)
VALUES ((SELECT id from pem.probe WHERE internal_name ='efm_cluster_node_status'), 20905, NULL);

COMMIT TRANSACTION;
