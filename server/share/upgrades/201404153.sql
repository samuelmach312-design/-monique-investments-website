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
'SELECT 201404153::integer;'
  LANGUAGE 'sql' IMMUTABLE;

UPDATE pem.probe SET collection_method = 'i' WHERE internal_name = 'session_info';

INSERT INTO pem.probe_column
	(probe_id, internal_name, display_name, display_position, classification,
	sql_data_type, unit_of_value, calculate_pit, discard_history, pit_by_default, is_graphable)
SELECT
	(SELECT id FROM pem.probe WHERE internal_name = 'session_info'),
	v.internal_name, v.display_name, v.display_position, v.classification,
	v.sql_data_type, v.unit_of_value, v.calculate_pit, v.discard_history, v.pit_by_default, v.is_graphable
FROM
	(VALUES
		('memory_usage_mb', 'Memory Usage (MB)', 15, 'm', 'numeric', 'MB', false, false, false, false),
		('swap_usage_mb', 'Swap Memory Usage (MB)', 16, 'm', 'numeric', 'MB', false, false, false, false),
		('cpu_usage', 'CPU Usage', 17, 'm', 'numeric', '%', false, false, false, false),
		('io_read_bytes', 'IO Read Bytes', 18, 'm', 'bigint', '', false, false, false, false),
		('io_write_bytes', 'IO Write Bytes', 19, 'm', 'bigint', '', false, false, false, false)
	) v(internal_name, display_name, display_position, classification,
		sql_data_type, unit_of_value, calculate_pit, discard_history, pit_by_default, is_graphable);

-- Add columns to data table
ALTER TABLE pemdata.session_info ADD COLUMN memory_usage_mb numeric NOT NULL DEFAULT 0;
ALTER TABLE pemdata.session_info ADD COLUMN swap_usage_mb numeric NOT NULL DEFAULT 0;
ALTER TABLE pemdata.session_info ADD COLUMN cpu_usage numeric NOT NULL DEFAULT 0;
ALTER TABLE pemdata.session_info ADD COLUMN io_read_bytes bigint NOT NULL DEFAULT 0;
ALTER TABLE pemdata.session_info ADD COLUMN io_write_bytes bigint NOT NULL DEFAULT 0;

-- Add columns to history table
ALTER TABLE pemhistory.session_info ADD COLUMN memory_usage_mb numeric NOT NULL DEFAULT 0;
ALTER TABLE pemhistory.session_info ADD COLUMN swap_usage_mb numeric NOT NULL DEFAULT 0;
ALTER TABLE pemhistory.session_info ADD COLUMN cpu_usage numeric NOT NULL DEFAULT 0;
ALTER TABLE pemhistory.session_info ADD COLUMN io_read_bytes bigint NOT NULL DEFAULT 0;
ALTER TABLE pemhistory.session_info ADD COLUMN io_write_bytes bigint NOT NULL DEFAULT 0;

CREATE OR REPLACE FUNCTION pemdata.copy_session_info_to_history()
RETURNS trigger AS
$$
BEGIN
	IF (TG_OP = 'INSERT' OR TG_OP = 'UPDATE') THEN
		INSERT INTO pemhistory.session_info (recorded_time, server_id, database_name, procpid, usename, backend_start, xact_start, query_start,
			is_waiting, is_idle, is_idle_in_transaction, is_vacuum, is_autovacuum, capture_time, client_addr, client_port, memory_usage_mb, swap_usage_mb,
			cpu_usage, io_read_bytes, io_write_bytes) VALUES (NEW.recorded_time, NEW.server_id, NEW.database_name, NEW.procpid, NEW.usename,
			NEW.backend_start, NEW.xact_start, NEW.query_start, NEW.is_waiting, NEW.is_idle, NEW.is_idle_in_transaction, NEW.is_vacuum,
			NEW.is_autovacuum, NEW.capture_time, NEW.client_addr, NEW.client_port, NEW.memory_usage_mb, NEW.swap_usage_mb,
			NEW.cpu_usage, NEW.io_read_bytes, NEW.io_write_bytes);
		ELSIF EXISTS(SELECT 1 FROM pem.server WHERE id = OLD.server_id) THEN
		INSERT INTO pemhistory.session_info (server_id, procpid) VALUES (OLD.server_id, OLD.procpid);
	END IF;
	RETURN NEW;
END;
$$
LANGUAGE plpgsql;

COMMIT TRANSACTION;
