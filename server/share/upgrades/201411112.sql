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
'SELECT 201411112::integer;'
  LANGUAGE 'sql' IMMUTABLE;

DROP INDEX pemdata.server_logs_messages;

UPDATE pem.probe SET probe_code = E'
SELECT client_addr, client_port, sent_location, write_location, flush_location, replay_location, xlog_lag_in_segments,
	(((sent_location -replay_location)>>10) / (SUBSTRING(unit FROM ''[0-9]+''))::INT) AS xlog_lag_in_pages
FROM (

		WITH pg_stat_replication_log_bytes AS (
		SELECT
			host(client_addr) AS client_addr, client_port,

			pg_catalog.split_part(sent_location, ''/'', 1) AS s1,
			pg_catalog.split_part(sent_location, ''/'', 2) AS s2,

			pg_catalog.split_part(write_location, ''/'', 1) AS w1,
			pg_catalog.split_part(write_location, ''/'', 2) AS w2,

			pg_catalog.split_part(flush_location, ''/'', 1) AS f1,
			pg_catalog.split_part(flush_location, ''/'', 2) AS f2,

			pg_catalog.split_part(replay_location, ''/'', 1) AS r1,
			pg_catalog.split_part(replay_location, ''/'', 2) AS r2,

			((''x''||SUBSTRING((pg_xlogfile_name_offset(sent_location)).file_name FROM 9))::BIT(64)::BIGINT -
				(''x''||SUBSTRING((pg_xlogfile_name_offset(replay_location)).file_name FROM 9))::BIT(64)::BIGINT) AS xlog_lag_in_segments

		FROM pg_stat_replication WHERE client_addr IS NOT NULL)
	SELECT
		client_addr, client_port,
		CASE WHEN s1 IS NULL AND s2 IS NULL THEN 0::bigint
			WHEN s1 IS NULL THEN (''x'' || repeat(''0'', 16 - length(s2)) || s2)::bit(64)::bigint
			WHEN s2 IS NULL THEN 4278190080 * (''x'' || repeat(''0'', 16 - length(s1)) || s1)::bit(64)::bigint
			ELSE 4278190080 * (''x'' || repeat(''0'', 16 - length(s1)) || s1)::bit(64)::bigint + (''x'' || repeat(''0'', 16 - length(s2)) || s2)::bit(64)::bigint
		END AS sent_location,
		CASE WHEN w1 IS NULL AND w2 IS NULL THEN 0::bigint
			WHEN w1 IS NULL THEN (''x'' || repeat(''0'', 16 - length(w2)) || w2)::bit(64)::bigint
			WHEN w2 IS NULL THEN 4278190080 * (''x'' || repeat(''0'', 16 - length(w1)) || w1)::bit(64)::bigint
			ELSE 4278190080 * (''x'' || repeat(''0'', 16 - length(w1)) || w1)::bit(64)::bigint + (''x'' || repeat(''0'', 16 - length(w2)) || w2)::bit(64)::bigint
		END AS write_location,
		CASE WHEN f1 IS NULL AND f2 IS NULL THEN 0::bigint
			WHEN f1 IS NULL THEN (''x'' || repeat(''0'', 16 - length(f2)) || f2)::bit(64)::bigint
			WHEN f2 IS NULL THEN 4278190080 * (''x'' || repeat(''0'', 16 - length(f1)) || f1)::bit(64)::bigint
			ELSE 4278190080 * (''x'' || repeat(''0'', 16 - length(f1)) || f1)::bit(64)::bigint + (''x'' || repeat(''0'', 16 - length(f2)) || f2)::bit(64)::bigint
		END AS flush_location,
		CASE WHEN r1 IS NULL AND r2 IS NULL THEN 0::bigint
			WHEN r1 IS NULL THEN (''x'' || repeat(''0'', 16 - length(r2)) || r2)::bit(64)::bigint
			WHEN r2 IS NULL THEN 4278190080 * (''x'' || repeat(''0'', 16 - length(r1)) || r1)::bit(64)::bigint
			ELSE 4278190080 * (''x'' || repeat(''0'', 16 - length(r1)) || r1)::bit(64)::bigint + (''x'' || repeat(''0'', 16 - length(r2)) || r2)::bit(64)::bigint
		END AS replay_location,
		xlog_lag_in_segments
	FROM pg_stat_replication_log_bytes
) AS pg_stat_replication_dtls, pg_catalog.pg_settings
WHERE name ~ ''wal_segment_size'''
WHERE internal_name='streaming_replication';

UPDATE pem.probe_server_version SET probe_code=E'
    SELECT client_addr, client_port, sent_location, write_location, flush_location, replay_location, xlog_lag_in_segments,
		(((sent_location -replay_location)>>10) / (SUBSTRING(unit FROM ''[0-9]+''))::INT) AS xlog_lag_in_pages
		FROM (
		WITH pg_stat_replication_log_bytes AS (
		SELECT
			host(client_addr) AS client_addr, client_port,

			pg_catalog.split_part(sent_location::text, ''/'', 1) AS s1,
			pg_catalog.split_part(sent_location::text, ''/'', 2) AS s2,

			pg_catalog.split_part(write_location::text, ''/'', 1) AS w1,
			pg_catalog.split_part(write_location::text, ''/'', 2) AS w2,

			pg_catalog.split_part(flush_location::text, ''/'', 1) AS f1,
			pg_catalog.split_part(flush_location::text, ''/'', 2) AS f2,

			pg_catalog.split_part(replay_location::text, ''/'', 1) AS r1,
			pg_catalog.split_part(replay_location::text, ''/'', 2) AS r2,

			((''x''||SUBSTRING((pg_xlogfile_name_offset(sent_location)).file_name FROM 9))::BIT(64)::BIGINT -
				(''x''||SUBSTRING((pg_xlogfile_name_offset(replay_location)).file_name FROM 9))::BIT(64)::BIGINT) AS xlog_lag_in_segments

		FROM pg_stat_replication WHERE client_addr IS NOT NULL)
	SELECT
		client_addr, client_port,
		CASE WHEN s1 IS NULL AND s2 IS NULL THEN 0::bigint
			WHEN s1 IS NULL THEN (''x'' || repeat(''0'', 16 - length(s2)) || s2)::bit(64)::bigint
			WHEN s2 IS NULL THEN 4278190080 * (''x'' || repeat(''0'', 16 - length(s1)) || s1)::bit(64)::bigint
			ELSE 4278190080 * (''x'' || repeat(''0'', 16 - length(s1)) || s1)::bit(64)::bigint + (''x'' || repeat(''0'', 16 - length(s2)) || s2)::bit(64)::bigint
		END AS sent_location,
		CASE WHEN w1 IS NULL AND w2 IS NULL THEN 0::bigint
			WHEN w1 IS NULL THEN (''x'' || repeat(''0'', 16 - length(w2)) || w2)::bit(64)::bigint
			WHEN w2 IS NULL THEN 4278190080 * (''x'' || repeat(''0'', 16 - length(w1)) || w1)::bit(64)::bigint
			ELSE 4278190080 * (''x'' || repeat(''0'', 16 - length(w1)) || w1)::bit(64)::bigint + (''x'' || repeat(''0'', 16 - length(w2)) || w2)::bit(64)::bigint
		END AS write_location,
		CASE WHEN f1 IS NULL AND f2 IS NULL THEN 0::bigint
			WHEN f1 IS NULL THEN (''x'' || repeat(''0'', 16 - length(f2)) || f2)::bit(64)::bigint
			WHEN f2 IS NULL THEN 4278190080 * (''x'' || repeat(''0'', 16 - length(f1)) || f1)::bit(64)::bigint
			ELSE 4278190080 * (''x'' || repeat(''0'', 16 - length(f1)) || f1)::bit(64)::bigint + (''x'' || repeat(''0'', 16 - length(f2)) || f2)::bit(64)::bigint
		END AS flush_location,
		CASE WHEN r1 IS NULL AND r2 IS NULL THEN 0::bigint
			WHEN r1 IS NULL THEN (''x'' || repeat(''0'', 16 - length(r2)) || r2)::bit(64)::bigint
			WHEN r2 IS NULL THEN 4278190080 * (''x'' || repeat(''0'', 16 - length(r1)) || r1)::bit(64)::bigint
			ELSE 4278190080 * (''x'' || repeat(''0'', 16 - length(r1)) || r1)::bit(64)::bigint + (''x'' || repeat(''0'', 16 - length(r2)) || r2)::bit(64)::bigint
		END AS replay_location,
		xlog_lag_in_segments
	FROM pg_stat_replication_log_bytes
) AS pg_stat_replication_dtls, pg_catalog.pg_settings
WHERE name ~ ''wal_segment_size'''
WHERE probe_id = (SELECT id FROM pem.probe WHERE internal_name = 'streaming_replication') AND server_version_id in (10904, 20904);

COMMIT TRANSACTION;
