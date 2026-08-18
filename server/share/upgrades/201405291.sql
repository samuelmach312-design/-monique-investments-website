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
'SELECT 201405291::integer;'
  LANGUAGE 'sql' IMMUTABLE;

INSERT INTO pem.server_version VALUES (10904, 'PostgreSQL 9.4');
INSERT INTO pem.server_version VALUES (20904, 'Advanced Server 9.4');

-- oc_schmea support
INSERT INTO pem.probe_server_version(probe_id,server_version_id,probe_code)
	VALUES((SELECT id FROM pem.probe WHERE internal_name='oc_schema'), 10904, NULL);

INSERT INTO pem.probe_server_version(probe_id,server_version_id,probe_code)
	VALUES((SELECT id FROM pem.probe WHERE internal_name='oc_schema'), 20904,
	E'SELECT nspname AS schema_name FROM pg_catalog.pg_namespace WHERE (nspname = ''pg_catalog'' OR nspname NOT LIKE E''pg\\\\_%'') AND nspparent = 0');

-- oc_function support
INSERT INTO pem.probe_server_version(probe_id,server_version_id,probe_code)
	VALUES((SELECT id FROM pem.probe WHERE internal_name='oc_function'), 10904, NULL);

INSERT INTO pem.probe_server_version(probe_id,server_version_id,probe_code)
	VALUES((SELECT id FROM pem.probe WHERE internal_name='oc_function'), 20904,
	$sql$
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

-- database_statistics support
INSERT INTO pem.probe_server_version(probe_id,server_version_id,probe_code)
	VALUES((SELECT id FROM pem.probe WHERE internal_name='database_statistics'), 10904,
	'SELECT d1.datname AS database_name, d1.numbackends,
            (SELECT COALESCE(count(query)::bigint, 0::bigint) FROM pg_catalog.pg_stat_activity WHERE datname = d1.datname AND state = ''idle'') AS idle_backends,
	    d1.xact_commit, d1.xact_rollback, d1.blks_hit, NULL::bigint AS blks_icache_hit, d1.blks_read,
            d1.tup_returned, d1.tup_fetched, d1.tup_inserted, d1.tup_updated, d1.tup_deleted
      FROM pg_catalog.pg_stat_database d1');

INSERT INTO pem.probe_server_version(probe_id,server_version_id,probe_code)
	VALUES((SELECT id FROM pem.probe WHERE internal_name='database_statistics'), 20904,
	'SELECT d1.datname AS database_name, d1.numbackends,
            (SELECT COALESCE(count(query)::bigint, 0::bigint) FROM pg_catalog.pg_stat_activity WHERE datname = d1.datname AND state = ''idle'') AS idle_backends,
            d1.xact_commit, d1.xact_rollback, d1.blks_hit, d1.blks_icache_hit, d1.blks_read, d1.tup_returned,
            d1.tup_fetched, d1.tup_inserted, d1.tup_updated, d1.tup_deleted
     FROM pg_catalog.pg_stat_database d1');

-- table_statistics support
INSERT INTO pem.probe_server_version(probe_id,server_version_id,probe_code)
	VALUES((SELECT id FROM pem.probe WHERE internal_name='table_statistics'), 10904, NULL);

INSERT INTO pem.probe_server_version(probe_id,server_version_id,probe_code)
	VALUES((SELECT id FROM pem.probe WHERE internal_name='table_statistics'), 20904, NULL);

-- function_statistics support
INSERT INTO pem.probe_server_version(probe_id,server_version_id,probe_code)
	VALUES((SELECT id FROM pem.probe WHERE internal_name='function_statistics'), 10904, NULL);

INSERT INTO pem.probe_server_version(probe_id,server_version_id,probe_code)
	VALUES((SELECT id FROM pem.probe WHERE internal_name='function_statistics'), 20904,
	$sql$
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

-- table_size support
INSERT INTO pem.probe_server_version(probe_id,server_version_id,probe_code)
	VALUES((SELECT id FROM pem.probe WHERE internal_name='table_size'), 10904,
	'SELECT n.nspname AS schema_name, c.relname AS table_name, pg_relation_size(c.oid) / 1048576 AS table_size_mb, pg_indexes_size(c.oid) / 1048576 AS size_of_indexes_mb, pg_total_relation_size(c.oid) / 1048576 AS total_table_size_mb FROM pg_class c, pg_namespace n WHERE c.relnamespace = n.oid AND c.relkind = ''r''');

INSERT INTO pem.probe_server_version(probe_id,server_version_id,probe_code)
	VALUES((SELECT id FROM pem.probe WHERE internal_name='table_size'), 20904,
	'SELECT n.nspname AS schema_name, c.relname AS table_name, pg_relation_size(c.oid) / 1048576 AS table_size_mb, pg_indexes_size(c.oid) / 1048576 AS size_of_indexes_mb, pg_total_relation_size(c.oid) / 1048576 AS total_table_size_mb FROM pg_class c, pg_namespace n WHERE c.relnamespace = n.oid AND c.relkind = ''r''');

-- background_writer_statistics support
INSERT INTO pem.probe_server_version(probe_id,server_version_id,probe_code)
	VALUES((SELECT id FROM pem.probe WHERE internal_name='background_writer_statistics'), 10904, NULL);

INSERT INTO pem.probe_server_version(probe_id,server_version_id,probe_code)
	VALUES((SELECT id FROM pem.probe WHERE internal_name='background_writer_statistics'), 20904, NULL);

-- session_info support
INSERT INTO pem.probe_server_version(probe_id,server_version_id,probe_code)
	VALUES((SELECT id FROM pem.probe WHERE internal_name='session_info'), 10904,
	'SELECT datname AS database_name, pid AS procpid, usename, client_addr, client_port, backend_start, xact_start, query_start,'
                ' waiting AS is_waiting, query = $$<IDLE>$$ AS is_idle,'
                ' query = $$<IDLE> in transaction$$ AS is_idle_in_transaction,'
                ' query ilike $$VACUUM%$$ as is_vacuum,'
                ' client_port IS NULL AND (query like $$autovacuum:%$$ OR query like $$VACUUM%$$) as is_autovacuum,'
                ' now() AS capture_time'
        ' FROM pg_catalog.pg_stat_activity');

INSERT INTO pem.probe_server_version(probe_id,server_version_id,probe_code)
	VALUES((SELECT id FROM pem.probe WHERE internal_name='session_info'), 20904,
	'SELECT datname AS database_name, pid AS procpid, usename, client_addr, client_port, backend_start, xact_start, query_start,'
                ' waiting AS is_waiting, query = $$<IDLE>$$ AS is_idle,'
                ' query = $$<IDLE> in transaction$$ AS is_idle_in_transaction,'
                ' query ilike $$VACUUM%$$ as is_vacuum,'
                ' client_port IS NULL AND (query like $$autovacuum:%$$ OR query like $$VACUUM%$$) as is_autovacuum,'
                ' now() AS capture_time'
        ' FROM pg_catalog.pg_stat_activity');

-- lock_info support
INSERT INTO pem.probe_server_version(probe_id,server_version_id,probe_code)
	VALUES((SELECT id FROM pem.probe WHERE internal_name='lock_info'), 10904,
	$sql$
SELECT	COALESCE(d.datname, '')			AS database_name,
		COALESCE(l.pid::bigint, -1)		AS procpid,
		l.relation::text::numeric		AS objid,		-- relation/XID/VXID/classid
		COALESCE(l.page::bigint, -1)	AS objsubid,	-- page/objid
		COALESCE(l.tuple::bigint, -1)	AS objsubsubid,	-- tuple/objsubid
		l.locktype, l.mode AS lockmode, l.granted AS lockgranted
FROM	pg_catalog.pg_locks AS l
LEFT JOIN	pg_catalog.pg_stat_activity AS sa
ON		l.pid = sa.pid
JOIN	pg_catalog.pg_database AS d
ON		sa.datid = d.oid
WHERE	l.locktype IN ('relation', 'extend', 'page', 'tuple')
UNION ALL
SELECT	COALESCE(d.datname, '')		AS database_name,
		COALESCE(l.pid::bigint, -1)	AS procpid,
		transactionid::text::numeric	AS objid,	-- relation/XID/VXID/classid
		-1							AS objsubid,	-- page/objid
		-1							AS objsubsubid,	-- tuple/objsubid
		l.locktype, l.mode AS lockmode, l.granted AS lockgranted
FROM	pg_catalog.pg_locks AS l
LEFT JOIN	pg_catalog.pg_stat_activity AS sa
ON		l.pid = sa.pid
JOIN	pg_catalog.pg_database AS d
ON		sa.datid = d.oid
WHERE	l.locktype = 'transactionid'
UNION ALL
SELECT	COALESCE(d.datname, '')				AS database_name,
		COALESCE(l.pid::bigint, -1)			AS procpid,
		regexp_replace(l.virtualxid, '/', '.')::numeric AS objid,-- relation/XID/VXID/classid
		-1									AS objsubid,	-- page/objid
		-1									AS objsubsubid,	-- tuple/objsubid
		l.locktype, l.mode AS lockmode, l.granted AS lockgranted
FROM	pg_catalog.pg_locks AS l
LEFT JOIN	pg_catalog.pg_stat_activity AS sa
ON		l.pid = sa.pid
JOIN	pg_catalog.pg_database AS d
ON		sa.datid = d.oid
WHERE	l.locktype = 'virtualxid'
UNION ALL
SELECT	COALESCE(d.datname, '')			AS database_name,
		COALESCE(l.pid::bigint, -1)		AS procpid,
		classid::text::numeric			AS objid,-- relation/XID/VXID/classid
		COALESCE(l.objid::bigint, -1)	AS objsubid,	-- page/objid
		COALESCE(l.objsubid::bigint, -1)AS objsubsubid,	-- tuple/objsubid
		l.locktype, l.mode AS lockmode, l.granted AS lockgranted
FROM	pg_catalog.pg_locks AS l
LEFT JOIN	pg_catalog.pg_stat_activity AS sa
ON		l.pid = sa.pid
JOIN	pg_catalog.pg_database AS d
ON		sa.datid = d.oid
WHERE	l.locktype IN ('object', 'advisory')$sql$);

INSERT INTO pem.probe_server_version(probe_id,server_version_id,probe_code)
	VALUES((SELECT id FROM pem.probe WHERE internal_name='lock_info'), 20904,
	$sql$
SELECT	COALESCE(d.datname, '')			AS database_name,
		COALESCE(l.pid::bigint, -1)		AS procpid,
		l.relation::text::numeric		AS objid,		-- relation/XID/VXID/classid
		COALESCE(l.page::bigint, -1)	AS objsubid,	-- page/objid
		COALESCE(l.tuple::bigint, -1)	AS objsubsubid,	-- tuple/objsubid
		l.locktype, l.mode AS lockmode, l.granted AS lockgranted
FROM	pg_catalog.pg_locks AS l
LEFT JOIN	pg_catalog.pg_stat_activity AS sa
ON		l.pid = sa.pid
JOIN	pg_catalog.pg_database AS d
ON		sa.datid = d.oid
WHERE	l.locktype IN ('relation', 'extend', 'page', 'tuple')
UNION ALL
SELECT	COALESCE(d.datname, '')		AS database_name,
		COALESCE(l.pid::bigint, -1)	AS procpid,
		transactionid::text::numeric	AS objid,	-- relation/XID/VXID/classid
		-1							AS objsubid,	-- page/objid
		-1							AS objsubsubid,	-- tuple/objsubid
		l.locktype, l.mode AS lockmode, l.granted AS lockgranted
FROM	pg_catalog.pg_locks AS l
LEFT JOIN	pg_catalog.pg_stat_activity AS sa
ON		l.pid = sa.pid
JOIN	pg_catalog.pg_database AS d
ON		sa.datid = d.oid
WHERE	l.locktype = 'transactionid'
UNION ALL
SELECT	COALESCE(d.datname, '')				AS database_name,
		COALESCE(l.pid::bigint, -1)			AS procpid,
		regexp_replace(l.virtualxid, '/', '.')::numeric AS objid,-- relation/XID/VXID/classid
		-1									AS objsubid,	-- page/objid
		-1									AS objsubsubid,	-- tuple/objsubid
		l.locktype, l.mode AS lockmode, l.granted AS lockgranted
FROM	pg_catalog.pg_locks AS l
LEFT JOIN	pg_catalog.pg_stat_activity AS sa
ON		l.pid = sa.pid
JOIN	pg_catalog.pg_database AS d
ON		sa.datid = d.oid
WHERE	l.locktype = 'virtualxid'
UNION ALL
SELECT	COALESCE(d.datname, '')			AS database_name,
		COALESCE(l.pid::bigint, -1)		AS procpid,
		classid::text::numeric			AS objid,-- relation/XID/VXID/classid
		COALESCE(l.objid::bigint, -1)	AS objsubid,	-- page/objid
		COALESCE(l.objsubid::bigint, -1)AS objsubsubid,	-- tuple/objsubid
		l.locktype, l.mode AS lockmode, l.granted AS lockgranted
FROM	pg_catalog.pg_locks AS l
LEFT JOIN	pg_catalog.pg_stat_activity AS sa
ON		l.pid = sa.pid
JOIN	pg_catalog.pg_database AS d
ON		sa.datid = d.oid
WHERE	l.locktype IN ('object', 'advisory')$sql$);

-- streaming_replication support
INSERT INTO pem.probe_server_version(probe_id,server_version_id,probe_code)
	VALUES((SELECT id FROM pem.probe WHERE internal_name='streaming_replication'), 10904, NULL);

INSERT INTO pem.probe_server_version(probe_id,server_version_id,probe_code)
	VALUES((SELECT id FROM pem.probe WHERE internal_name='streaming_replication'), 20904, NULL);

-- streaming_replication_db_conflicts support
INSERT INTO pem.probe_server_version(probe_id,server_version_id,probe_code)
	VALUES((SELECT id FROM pem.probe WHERE internal_name='streaming_replication_db_conflicts'), 10904, NULL);

INSERT INTO pem.probe_server_version(probe_id,server_version_id,probe_code)
	VALUES((SELECT id FROM pem.probe WHERE internal_name='streaming_replication_db_conflicts'), 20904, NULL);

-- xdb_smr_mmr_replication support
INSERT INTO pem.probe_server_version(probe_id,server_version_id,probe_code)
	VALUES((SELECT id FROM pem.probe WHERE internal_name='xdb_smr_mmr_replication'), 10904, NULL);

INSERT INTO pem.probe_server_version(probe_id,server_version_id,probe_code)
	VALUES((SELECT id FROM pem.probe WHERE internal_name='xdb_smr_mmr_replication'), 20904, NULL);

-- oc_views support
INSERT INTO pem.probe_server_version(probe_id,server_version_id,probe_code)
	VALUES((SELECT id FROM pem.probe WHERE internal_name='oc_views'), 10904, NULL);

INSERT INTO pem.probe_server_version(probe_id,server_version_id,probe_code)
	VALUES((SELECT id FROM pem.probe WHERE internal_name='oc_views'), 20904, NULL);

-- mview_bloat support
INSERT INTO pem.probe_server_version(probe_id,server_version_id,probe_code)
	VALUES((SELECT id FROM pem.probe WHERE internal_name='mview_bloat'), 10904, NULL);

INSERT INTO pem.probe_server_version(probe_id,server_version_id,probe_code)
	VALUES((SELECT id FROM pem.probe WHERE internal_name='mview_bloat'), 20904, NULL);

-- mview_frozenxid support
INSERT INTO pem.probe_server_version(probe_id,server_version_id,probe_code)
	VALUES((SELECT id FROM pem.probe WHERE internal_name='mview_frozenxid'), 10904, NULL);

INSERT INTO pem.probe_server_version(probe_id,server_version_id,probe_code)
	VALUES((SELECT id FROM pem.probe WHERE internal_name='mview_frozenxid'), 20904, NULL);

-- mview_size support
INSERT INTO pem.probe_server_version(probe_id,server_version_id,probe_code)
	VALUES((SELECT id FROM pem.probe WHERE internal_name='mview_size'), 10904, NULL);

INSERT INTO pem.probe_server_version(probe_id,server_version_id,probe_code)
	VALUES((SELECT id FROM pem.probe WHERE internal_name='mview_size'), 20904, NULL);

-- streaming_replication_lag_time support
INSERT INTO pem.probe_server_version(probe_id,server_version_id,probe_code)
	VALUES((SELECT id FROM pem.probe WHERE internal_name='streaming_replication_lag_time'), 10904, NULL);

INSERT INTO pem.probe_server_version(probe_id,server_version_id,probe_code)
	VALUES((SELECT id FROM pem.probe WHERE internal_name='streaming_replication_lag_time'), 20904, NULL);

-- wal_archive_status support
INSERT INTO pem.probe_server_version(probe_id,server_version_id,probe_code)
	VALUES((SELECT id FROM pem.probe WHERE internal_name='wal_archive_status'), 10904,
	'SELECT archived_count, last_archived_time, failed_count, last_failed_time FROM pg_catalog.pg_stat_archiver');

INSERT INTO pem.probe_server_version(probe_id,server_version_id,probe_code)
	VALUES((SELECT id FROM pem.probe WHERE internal_name='wal_archive_status'), 20904,
	'SELECT archived_count, last_archived_time, failed_count, last_failed_time FROM pg_catalog.pg_stat_archiver');

-- system_waits support
INSERT INTO pem.probe_server_version(probe_id,server_version_id,probe_code)
	VALUES((SELECT id FROM pem.probe WHERE internal_name='system_waits'), 20904, NULL);

-- session_waits support
INSERT INTO pem.probe_server_version(probe_id,server_version_id,probe_code)
	VALUES((SELECT id FROM pem.probe WHERE internal_name='session_waits'), 20904,
	'SELECT sw.backend_id, psa.datname AS dbname, psa.usename, sw.wait_name, sw.wait_count, avg_wait_time, max_wait_time, total_wait_time FROM session_waits sw, pg_stat_activity psa WHERE sw.backend_id = psa.pid');

-- audit_configuration support
INSERT INTO pem.probe_server_version(probe_id,server_version_id,probe_code)
	VALUES((SELECT id FROM pem.probe WHERE internal_name='audit_configuration'), 20904, NULL);

UPDATE pem.alert_template SET sql = $sql$
SELECT xlog_lag_in_segments FROM pemdata.streaming_replication WHERE server_id = ${server_id} AND client_addr = '${param_1}'$sql$,
param_names = '{Standby hostname}', param_types = '{STRING}'
WHERE display_name = 'Standby server lag behind the master by WAL segments';

UPDATE pem.alert_template SET sql = $sql$
SELECT xlog_lag_in_pages FROM pemdata.streaming_replication WHERE server_id = ${server_id} AND client_addr = '${param_1}'$sql$,
param_names = '{Standby hostname}', param_types = '{STRING}'
WHERE display_name = 'Standby server lag behind the master by WAL pages';

CREATE OR REPLACE FUNCTION pem.purge_deleted_probes()
RETURNS void AS $BODY$
DECLARE
	curs_del_probes CURSOR FOR
		SELECT pr.id, pr.internal_name, pr.discard_history, pr.deleted_time,
			(CASE  WHEN (SELECT 1 FROM pem.probe_column AS pc WHERE pc.probe_id = pr.id AND pc.calculate_pit = true) = 1 THEN true ELSE false END) AS has_pit
		FROM pem.probe AS pr WHERE pr.deleted AND NOT pr.is_system_probe;
	quoted_table_name varchar;
	retention_time interval;
	deleted_time interval;
BEGIN
	SELECT (value ||'days')::interval FROM pem.config WHERE param = 'deleted_probes_retention_time' into retention_time;
	FOR deleted_probes IN curs_del_probes LOOP
		deleted_time = now() - deleted_probes.deleted_time;
		IF deleted_time >= retention_time THEN
			quoted_table_name := quote_ident(deleted_probes.internal_name);

			IF deleted_probes.has_pit = true THEN
				EXECUTE 'DROP TRIGGER ' || quote_ident('calculate_' || deleted_probes.internal_name || '_pit_value') || ' ON pemdata.' || quoted_table_name;
				EXECUTE 'DROP FUNCTION pemdata.' ||  quote_ident('calculate_' || deleted_probes.internal_name || '_pit_value') || E'()';
			END IF;

			IF NOT deleted_probes.discard_history THEN
				EXECUTE 'DROP TRIGGER ' || quote_ident('copy_' || deleted_probes.internal_name || '_to_history') || ' ON pemdata.' || quoted_table_name;
				EXECUTE 'DROP FUNCTION pemdata.' ||  quote_ident('copy_' || deleted_probes.internal_name || '_to_history') || E'()';
				EXECUTE 'DROP TABLE pemhistory.' || quoted_table_name || ' CASCADE';
			END IF;

			EXECUTE 'DROP TABLE pemdata.' || quoted_table_name || ' CASCADE';
			EXECUTE 'DELETE FROM pem.probe WHERE internal_name = ''' || deleted_probes.internal_name || ''' AND deleted AND NOT is_system_probe';
		END IF;
	END LOOP;
END;
$BODY$ LANGUAGE plpgsql SECURITY DEFINER;

COMMIT TRANSACTION;
