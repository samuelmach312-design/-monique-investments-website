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

-- Upgrade script for v2.0.0rc1 to v2.0.0 GA

BEGIN TRANSACTION;

-- Upgrade the schema version
CREATE OR REPLACE FUNCTION pem.schema_version()
  RETURNS integer AS
'SELECT 201108051::integer;'
  LANGUAGE 'sql' IMMUTABLE;

-- Update the database_size probe to add tablespace_name details
UPDATE pem.probe SET probe_code = 'SELECT datname AS database_name, spcname AS tablespace_name, pg_database_size(a.oid) / 1048576 AS database_size_mb FROM pg_catalog.pg_database a, pg_catalog.pg_tablespace b WHERE a.dattablespace = b.oid' WHERE internal_name = 'database_size';

-- Insert tablespace_name column in pemdata.database_size
ALTER TABLE pemdata.database_size ADD COLUMN tablespace_name text;
ALTER TABLE pemhistory.database_size ADD COLUMN tablespace_name text;
INSERT INTO pem.probe_column(probe_id, internal_name, display_name, display_position, classification, sql_data_type, unit_of_value, calculate_pit, discard_history, pit_by_default) SELECT id, 'tablespace_name', 'Tablespace Name', 3, 'm', 'text', '', false, false, false FROM pem.probe WHERE internal_name='database_size';

-- Update the trigger functions related to pemdata.database_size probe
CREATE OR REPLACE FUNCTION pemdata.copy_database_size_to_history() RETURNS TRIGGER AS $$
BEGIN
	IF (TG_OP = 'INSERT' OR TG_OP = 'UPDATE') THEN
		INSERT INTO pemhistory.database_size (recorded_time, server_id, database_name, database_size_mb, tablespace_name) VALUES (NEW.recorded_time, NEW.server_id, NEW.database_name, NEW.database_size_mb, NEW.tablespace_name);
	ELSIF EXISTS(SELECT 1 FROM pem.server WHERE id = OLD.server_id) THEN
	    INSERT INTO pemhistory.database_size (server_id, database_name) VALUES (OLD.server_id, OLD.database_name);
	END IF;
	RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Update session_waits probe
UPDATE pem.probe SET probe_code = 'SELECT sw.backend_id, psa.datname AS dbname, psa.usename, sw.wait_name, sw.wait_count, avg_wait_time, max_wait_time, total_wait_time FROM session_waits sw, pg_stat_activity psa WHERE sw.backend_id = psa.procpid' WHERE internal_name = 'session_waits';
ALTER TABLE pemdata.session_waits DROP CONSTRAINT session_waits_pkey RESTRICT;
ALTER TABLE pemdata.session_waits ADD PRIMARY KEY (server_id, backend_id, wait_name);
ALTER TABLE pemhistory.session_waits ALTER COLUMN backend_id SET NOT NULL, ALTER COLUMN wait_name SET NOT NULL;
DROP INDEX pemhistory.session_waits_keyidx;
CREATE INDEX session_waits_keyidx ON pemhistory.session_waits (server_id, backend_id, wait_name);

-- Probe is available for ppas83 as well
INSERT INTO pem.probe_server_version
	(probe_id, server_version_id, probe_code)
SELECT
	(SELECT id FROM pem.probe WHERE internal_name = 'session_waits'), v.version, NULL
FROM
	(VALUES (20803))
		v(version);
ALTER TABLE pemdata.session_waits DROP COLUMN edb_id;
ALTER TABLE pemhistory.session_waits DROP COLUMN edb_id;
UPDATE pem.probe_column SET display_position=1, classification='k' WHERE probe_id=(SELECT id FROM pem.probe WHERE internal_name='session_waits') AND internal_name='backend_id';
UPDATE pem.probe_column SET display_position=2 WHERE probe_id=(SELECT id FROM pem.probe WHERE internal_name='session_waits') AND internal_name='dbname';
UPDATE pem.probe_column SET display_position=3 WHERE probe_id=(SELECT id FROM pem.probe WHERE internal_name='session_waits') AND internal_name='usename';
UPDATE pem.probe_column SET display_position=4, classification='k' WHERE probe_id=(SELECT id FROM pem.probe WHERE internal_name='session_waits') AND internal_name='wait_name';
UPDATE pem.probe_column SET display_position=5, unit_of_value='#', pit_by_default=true WHERE probe_id=(SELECT id FROM pem.probe WHERE internal_name='session_waits') AND internal_name='wait_count';
UPDATE pem.probe_column SET display_position=6, unit_of_value='msec', pit_by_default=true WHERE probe_id=(SELECT id FROM pem.probe WHERE internal_name='session_waits') AND internal_name='avg_wait_time';
UPDATE pem.probe_column SET display_position=7, unit_of_value='msec', pit_by_default=true WHERE probe_id=(SELECT id FROM pem.probe WHERE internal_name='session_waits') AND internal_name='max_wait_time';
UPDATE pem.probe_column SET display_position=8, unit_of_value='msec', pit_by_default=true WHERE probe_id=(SELECT id FROM pem.probe WHERE internal_name='session_waits') AND internal_name='total_wait_time';
DELETE FROM pem.probe_column WHERE probe_id=(SELECT id FROM pem.probe WHERE internal_name='session_waits') AND internal_name='edb_id';

CREATE OR REPLACE FUNCTION pemdata.copy_session_waits_to_history() RETURNS TRIGGER AS $$
BEGIN
	IF (TG_OP = 'INSERT' OR TG_OP = 'UPDATE') THEN
		INSERT INTO pemhistory.session_waits (recorded_time, server_id, backend_id, dbname, usename, wait_name, wait_count, avg_wait_time, max_wait_time, total_wait_time) VALUES (NEW.recorded_time, NEW.server_id, NEW.backend_id, NEW.dbname, NEW.usename, NEW.wait_name, NEW.wait_count, NEW.avg_wait_time, NEW.max_wait_time, NEW.total_wait_time);
	ELSIF EXISTS(SELECT 1 FROM pem.server WHERE id = OLD.server_id) THEN
		INSERT INTO pemhistory.session_waits (server_id, backend_id, wait_name) VALUES (OLD.server_id, OLD.backend_id, OLD.wait_name);
	END IF;
	RETURN NEW;
END;
$$ LANGUAGE plpgsql;
UPDATE pem.probe SET probe_key_list = '{backend_id, wait_name}' WHERE internal_name = 'session_waits';

-- Update system_waits probe
UPDATE pem.probe SET probe_code = 'SELECT wait_name, wait_count, avg_wait, max_wait, total_wait FROM system_waits' WHERE internal_name = 'system_waits';
ALTER TABLE pemdata.system_waits DROP CONSTRAINT system_waits_pkey RESTRICT;
ALTER TABLE pemdata.system_waits ADD PRIMARY KEY (server_id, wait_name);
ALTER TABLE pemhistory.system_waits ALTER COLUMN wait_name SET NOT NULL;
DROP INDEX pemhistory.system_waits_keyidx;
CREATE INDEX system_waits_keyidx ON pemhistory.system_waits (server_id, wait_name);

-- Probe is available for ppas83 as well
INSERT INTO pem.probe_server_version
	(probe_id, server_version_id, probe_code)
SELECT
	(SELECT id FROM pem.probe WHERE internal_name = 'system_waits'), v.version, NULL
FROM
	(VALUES (20803))
		v(version);
ALTER TABLE pemdata.system_waits DROP COLUMN edb_id;
ALTER TABLE pemhistory.system_waits DROP COLUMN edb_id;
ALTER TABLE pemdata.system_waits DROP COLUMN dbname;
ALTER TABLE pemhistory.system_waits DROP COLUMN dbname;
UPDATE pem.probe_column SET display_position=1, classification='k' WHERE probe_id=(SELECT id FROM pem.probe WHERE internal_name='system_waits') AND internal_name='wait_name';
UPDATE pem.probe_column SET display_position=2, unit_of_value='#', pit_by_default=true WHERE probe_id=(SELECT id FROM pem.probe WHERE internal_name='system_waits') AND internal_name='wait_count';
UPDATE pem.probe_column SET display_position=3, unit_of_value='msec', pit_by_default=true WHERE probe_id=(SELECT id FROM pem.probe WHERE internal_name='system_waits') AND internal_name='avg_wait';
UPDATE pem.probe_column SET display_position=4, unit_of_value='msec', pit_by_default=true WHERE probe_id=(SELECT id FROM pem.probe WHERE internal_name='system_waits') AND internal_name='max_wait';
UPDATE pem.probe_column SET display_position=5, unit_of_value='msec', pit_by_default=true WHERE probe_id=(SELECT id FROM pem.probe WHERE internal_name='system_waits') AND internal_name='total_wait';
DELETE FROM pem.probe_column WHERE probe_id=(SELECT id FROM pem.probe WHERE internal_name='system_waits') AND internal_name='edb_id';
DELETE FROM pem.probe_column WHERE probe_id=(SELECT id FROM pem.probe WHERE internal_name='system_waits') AND internal_name='dbname';

CREATE OR REPLACE FUNCTION pemdata.copy_system_waits_to_history() RETURNS TRIGGER AS $$
BEGIN
	IF (TG_OP = 'INSERT' OR TG_OP = 'UPDATE') THEN
		INSERT INTO pemhistory.system_waits (recorded_time, server_id, wait_name, wait_count, avg_wait, max_wait, total_wait) VALUES (NEW.recorded_time, NEW.server_id, NEW.wait_name, NEW.wait_count, NEW.avg_wait, NEW.max_wait, NEW.total_wait);
	ELSIF EXISTS(SELECT 1 FROM pem.server WHERE id = OLD.server_id) THEN
		INSERT INTO pemhistory.system_waits (server_id, wait_name) VALUES (OLD.server_id, OLD.wait_name);
	END IF;
	RETURN NEW;
END;
$$ LANGUAGE plpgsql;
UPDATE pem.probe SET probe_key_list = '{wait_name}' WHERE internal_name = 'system_waits';

UPDATE pem.probe
	SET probe_code = E'SELECT nspname AS schema_name FROM pg_catalog.pg_namespace WHERE nspname = ''pg_catalog'' OR nspname NOT LIKE E''pg\\\\_%''',
	any_server_version = false
WHERE
	internal_name = 'oc_schema';

INSERT INTO pem.probe_server_version
	(probe_id, server_version_id, probe_code)
SELECT
	(SELECT id FROM pem.probe WHERE internal_name = 'oc_schema'), v.version, NULL
FROM
	(VALUES (10802), (10803), (10804), (10900), (10901))
		v(version);

INSERT INTO pem.probe_server_version
	(probe_id, server_version_id, probe_code)
SELECT
	(SELECT id FROM pem.probe WHERE internal_name = 'oc_schema'), v.version,
	E'SELECT nspname AS schema_name FROM pg_catalog.pg_namespace WHERE (nspname = ''pg_catalog'' OR nspname NOT LIKE E''pg\\\\_%'') AND nspparent = 0'
FROM
	(VALUES (20803), (20804), (20900))
		v(version);


ALTER TABLE pemdata.oc_foreign_key DROP CONSTRAINT oc_foreign_key_pkey RESTRICT;
ALTER TABLE pemdata.oc_foreign_key ADD PRIMARY KEY (server_id, database_name, schema_name, conname, fknsp, fktab);
DROP INDEX pemhistory.oc_foreign_key_keyidx;
ALTER TABLE pemhistory.oc_foreign_key ALTER COLUMN conkey DROP NOT NULL;
ALTER TABLE pemhistory.oc_foreign_key ALTER COLUMN confkey DROP NOT NULL;
UPDATE pemhistory.oc_foreign_key SET fknsp = '' WHERE fknsp IS NULL;
UPDATE pemhistory.oc_foreign_key SET fktab = '' WHERE fktab IS NULL;
ALTER TABLE pemhistory.oc_foreign_key ALTER COLUMN fknsp SET NOT NULL;
ALTER TABLE pemhistory.oc_foreign_key ALTER COLUMN fktab SET NOT NULL;
CREATE INDEX oc_foreign_key_keyidx ON pemhistory.oc_foreign_key (server_id, database_name, schema_name, conname, fknsp, fktab);

CREATE OR REPLACE FUNCTION pemdata.copy_oc_foreign_key_to_history() RETURNS TRIGGER AS $$
BEGIN
	IF (TG_OP = 'INSERT' OR TG_OP = 'UPDATE') THEN
		INSERT INTO pemhistory.oc_foreign_key (recorded_time, server_id, database_name, schema_name, conname, conkey, confkey, fknsp, fktab, refnsp,reftab) VALUES (NEW.recorded_time, NEW.server_id, NEW.database_name, NEW.schema_name, NEW.conname, NEW.conkey, NEW.confkey, NEW.fknsp, NEW.fktab, NEW.refnsp, NEW.reftab);
	ELSIF EXISTS(SELECT 1 FROM pem.server WHERE id = OLD.server_id) THEN
		INSERT INTO pemhistory.oc_foreign_key (server_id, database_name, schema_name, conname, fknsp, fktab) VALUES (OLD.server_id, OLD.database_name, OLD.schema_name, OLD.conname, OLD.fknsp, OLD.fktab);
	END IF;
	RETURN NEW;
END;
$$ LANGUAGE plpgsql;


COMMIT TRANSACTION;
