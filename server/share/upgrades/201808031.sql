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
'SELECT 201808031::integer;'
  LANGUAGE 'sql' IMMUTABLE;
COMMENT ON FUNCTION pem.schema_version() IS 'Returns the version number of the PEM schema';

-- Rename column name from "lag_MB" to "lag_mb" for streaming replication probe.
UPDATE pem.probe_column SET internal_name = 'lag_mb' WHERE internal_name = 'lag_MB' AND probe_id = (SELECT id FROM pem.probe WHERE internal_name = 'streaming_replication');

-- Rename column name only if exists.
DO
$$
BEGIN
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
AND server_version_id IN (11000, 21000);

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

COMMIT TRANSACTION;
