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
'SELECT 201404172::integer;'
  LANGUAGE 'sql' IMMUTABLE;

UPDATE pem.probe_column SET pit_by_default = true, is_graphable = true WHERE internal_name = 'lag_num_events' AND probe_id = (SELECT id FROM pem.probe WHERE internal_name = 'slony_replication');
UPDATE pem.probe_column SET pit_by_default = true, is_graphable = true, unit_of_value = 'minutes' WHERE internal_name = 'lag_time' AND probe_id = (SELECT id FROM pem.probe WHERE internal_name = 'slony_replication');

UPDATE pem.probe
SET probe_code = 'SELECT client_addr, client_port, sent_location, write_location, flush_location, replay_location, xlog_lag_in_segments,
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

		FROM pg_stat_replication)
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
WHERE internal_name = 'streaming_replication';

INSERT INTO pem.probe_column
	(probe_id, internal_name, display_name, display_position, classification,
	sql_data_type, unit_of_value, calculate_pit, discard_history, pit_by_default, is_graphable)
SELECT
	(SELECT id FROM pem.probe WHERE internal_name = 'streaming_replication'),
	v.internal_name, v.display_name, v.display_position, v.classification,
	v.sql_data_type, v.unit_of_value, v.calculate_pit, v.discard_history, v.pit_by_default, v.is_graphable
FROM
	(VALUES
                ('xlog_lag_in_segments', '# Xlog lag in segments', 7, 'm', 'bigint',  '#', false, false, true,  true),
                ('xlog_lag_in_pages',    '# Xlog lag in pages',    8, 'm', 'bigint',  '#', false, false, true,  true)
	) v(internal_name, display_name, display_position, classification,
		sql_data_type, unit_of_value, calculate_pit, discard_history, pit_by_default, is_graphable);

-- Add columns to data table
ALTER TABLE pemdata.streaming_replication ADD COLUMN xlog_lag_in_segments bigint;
ALTER TABLE pemdata.streaming_replication ADD COLUMN xlog_lag_in_pages bigint;

-- Add columns to history table
ALTER TABLE pemhistory.streaming_replication ADD COLUMN xlog_lag_in_segments bigint;
ALTER TABLE pemhistory.streaming_replication ADD COLUMN xlog_lag_in_pages bigint;

CREATE OR REPLACE FUNCTION pemdata.copy_streaming_replication_to_history()
RETURNS trigger AS
$$
BEGIN
	IF (TG_OP = 'INSERT' OR TG_OP = 'UPDATE') THEN
		INSERT INTO pemhistory.streaming_replication (recorded_time, server_id, client_addr, client_port, sent_location, write_location, flush_location, replay_location, xlog_lag_in_segments, xlog_lag_in_pages) VALUES (NEW.recorded_time, NEW.server_id, NEW.client_addr, NEW.client_port, NEW.sent_location, NEW.write_location, NEW.flush_location, NEW.replay_location, NEW.xlog_lag_in_segments, NEW.xlog_lag_in_pages);
	ELSIF EXISTS(SELECT 1 FROM pem.server WHERE id = OLD.server_id) THEN
		INSERT INTO pemhistory.streaming_replication (server_id, client_addr, client_port) VALUES (OLD.server_id, OLD.client_addr, OLD.client_port);
	END IF;
	RETURN NEW;
END;
$$
LANGUAGE plpgsql;

--
-- Probe: Streaming Replication Lag Time
--
INSERT INTO pem.probe
        (display_name, internal_name, collection_method, target_type_id,
         enabled_by_default, force_enabled, default_execution_frequency,
         default_lifetime, any_server_version, probe_code)
VALUES
        ('Streaming Replication Lag Time', 'streaming_replication_lag_time', 's', 200, false, false, 300, 180, false,
        'SELECT (CASE WHEN pg_last_xlog_receive_location() = pg_last_xlog_replay_location() THEN 0
		ELSE COALESCE(EXTRACT (EPOCH FROM now() - pg_last_xact_replay_timestamp())/60, 0) END)::bigint AS lag_time,
		pg_is_xlog_replay_paused() AS replication_paused WHERE true = pg_is_in_recovery()');

INSERT INTO pem.probe_column
        (probe_id, internal_name, display_name, display_position, classification,
        sql_data_type, unit_of_value, calculate_pit, discard_history, pit_by_default, is_graphable)
SELECT
        (SELECT max(id) FROM pem.probe),
        v.internal_name, v.display_name, v.display_position, v.classification,
        v.sql_data_type, v.unit_of_value, v.calculate_pit, v.discard_history, v.pit_by_default, v.is_graphable
FROM
        (VALUES
                ('lag_time',           'Lag time (minutes)', 1, 'm', 'bigint',  'minutes', false, false, true,  true),
                ('replication_paused', 'Replication paused', 2, 'm', 'boolean', ''       , false, false, false, false)
        ) v(internal_name, display_name, display_position, classification,
                sql_data_type, unit_of_value, calculate_pit, discard_history, pit_by_default, is_graphable);

INSERT INTO pem.probe_server_version
    (probe_id, server_version_id, probe_code)
SELECT
        (SELECT max(id) FROM pem.probe), v.version, NULL
FROM
        (VALUES (10901), (10902), (10903), (20901), (20902), (20903))
                v(version);

--
-- Probe: WAL Archive Status
--
INSERT INTO pem.probe
        (display_name, internal_name, collection_method, target_type_id,
         agent_capability, enabled_by_default, force_enabled,
     default_execution_frequency, default_lifetime, any_server_version, probe_code)
VALUES
        ('WAL Archive Status', 'wal_archive_status', 'i', 200, NULL, false, false, 1800,
          180, false, 'wal_archive_status');

INSERT INTO pem.probe_column
        (probe_id, internal_name, display_name, display_position, classification,
        sql_data_type, unit_of_value, calculate_pit, discard_history, pit_by_default, is_graphable)
SELECT
        (SELECT max(id) FROM pem.probe),
        v.internal_name, v.display_name, v.display_position, v.classification,
        v.sql_data_type, v.unit_of_value, v.calculate_pit, v.discard_history, v.pit_by_default, v.is_graphable
FROM
        (VALUES
                ('archive_done',       '# Archive Done',     1, 'm', 'bigint', '#', false, false, true, true),
                ('archive_pending',    '# Archive Pending',  2, 'm', 'bigint', '#', false, false, true, true),
                ('archive_failed',     '# Archive Failed',   3, 'm', 'bigint', '#', false, false, true, true),
                ('last_archived_time', 'Last Archived Time', 4, 'm', 'timestamp with time zone', '', false, false, false, false),
                ('last_failed_time',   'Last Failed Time',   5, 'm', 'timestamp with time zone', '', false, false, false, false)
        ) v(internal_name, display_name, display_position, classification,
                sql_data_type, unit_of_value, calculate_pit, discard_history, pit_by_default, is_graphable);

INSERT INTO pem.probe_server_version
    (probe_id, server_version_id, probe_code)
SELECT
        (SELECT max(id) FROM pem.probe), v.version, NULL
FROM
        (VALUES (10901), (10902), (10903), (20901), (20902), (20903))
                v(version);

-- This view shows every possible combination of (1) a probe, and (2) a known
-- monitoring target to which that probe could be applied.
CREATE OR REPLACE VIEW pem.probe_target_view AS
SELECT
	p.id AS probe_id, p.display_name AS probe_display_name,
	p.internal_name AS probe_internal_name, p.probe_key_list,
	p.applies_to_id,
	a.id AS agent_id, NULL::integer AS server_id, NULL::text AS database_name,
	ARRAY['agent_id']::text[] AS parameter_name_list,
	ARRAY[a.id::text]::text[] AS parameter_value_list,
	p.collection_method, p.probe_code, p.enabled_by_default,
	p.default_execution_frequency,
	p.default_lifetime,
	COALESCE(c.enabled, p.enabled_by_default) AS enabled,
	COALESCE(c.execution_frequency, p.default_execution_frequency)
		AS execution_frequency,
	COALESCE(c.lifetime, p.default_lifetime) AS lifetime,
	a.active AS agent_active,
	p.discard_history
FROM
	pem.probe p
	CROSS JOIN pem.agent a
	LEFT JOIN pem.probe_config_agent c
		ON p.id = c.probe_id AND a.id = c.agent_id
WHERE
	p.target_type_id = 100
	AND NOT p.deleted
	AND (p.agent_capability IS NULL
		OR p.agent_capability = ANY(a.agent_capability_list))
	AND ((p.collection_method NOT IN ('b', 'w')) OR
		(p.collection_method ='b' AND (a.agent_capability_list @> ARRAY['allow_batch_probes'])
			AND ((strpos(a.platform, p.platform) != 0) OR (a.platform !~ 'windows' AND p.platform = 'unix'))) OR
		(p.collection_method = 'w' AND strpos(a.platform, 'windows') != 0))
UNION ALL
SELECT
	p.id AS probe_id, p.display_name AS probe_display_name,
	p.internal_name AS probe_internal_name, p.probe_key_list,
	p.applies_to_id,
	a.id AS agent_id, b.server_id, b.database AS database_name,
	ARRAY['server_id']::text[] AS parameter_name_list,
	ARRAY[b.server_id::text]::text[] AS parameter_value_list,
	p.collection_method,
	COALESCE(psv.probe_code, p.probe_code) AS probe_code,
	p.enabled_by_default, p.default_execution_frequency,
	p.default_lifetime,
	COALESCE(c.enabled, p.enabled_by_default) AS enabled,
	COALESCE(c.execution_frequency, p.default_execution_frequency)
		AS execution_frequency,
	COALESCE(c.lifetime, p.default_lifetime) AS lifetime,
	a.active AS agent_active,
	p.discard_history
FROM
	pem.probe p
	CROSS JOIN pem.agent_server_binding b
	INNER JOIN pem.agent a ON b.agent_id = a.id
	INNER JOIN pem.server s ON b.server_id = s.id
	LEFT JOIN pemdata.server_info sd ON b.server_id = sd.server_id
	LEFT JOIN pem.probe_server_version psv
		ON p.id = psv.probe_id
		AND sd.server_version_id = psv.server_version_id
	LEFT JOIN pem.probe_config_server c
		ON p.id = c.probe_id AND b.server_id = c.server_id
WHERE
	p.target_type_id = 200
	AND NOT p.deleted
	AND (p.agent_capability IS NULL
		OR p.agent_capability = ANY(a.agent_capability_list))
	AND (p.any_server_version OR psv.probe_id IS NOT NULL)
	AND p.internal_name NOT IN( SELECT UNNEST(CASE WHEN s.is_remote_monitoring THEN ARRAY['pg_hba_conf', 'data_log_file_analysis', 'wal_archive_status'] ELSE ARRAY[''] END))
	AND (p.collection_method != 'b' OR
		(p.collection_method ='b' AND (a.agent_capability_list @> ARRAY['allow_batch_probes'])
			AND ((strpos(a.platform, p.platform) != 0) OR (a.platform !~ 'windows' AND p.platform = 'unix'))))
UNION ALL
SELECT
	p.id AS probe_id, p.display_name AS probe_display_name,
	p.internal_name AS probe_internal_name, p.probe_key_list,
	p.applies_to_id,
	a.id AS agent_id, b.server_id, ocd.database_name AS database_name,
	ARRAY['server_id', 'database_name']::text[] AS parameter_name_list,
	ARRAY[b.server_id::text, ocd.database_name]::text[] AS parameter_value_list,
	p.collection_method,
	COALESCE(psv.probe_code, p.probe_code) AS probe_code,
	p.enabled_by_default, p.default_execution_frequency,
	p.default_lifetime,
	COALESCE(c.enabled, p.enabled_by_default) AS enabled,
	COALESCE(c.execution_frequency, p.default_execution_frequency)
		AS execution_frequency,
	COALESCE(c.lifetime, p.default_lifetime) AS lifetime,
	a.active AS agent_active,
	p.discard_history
FROM
	pem.probe p
	CROSS JOIN pem.agent_server_binding b
	INNER JOIN pem.agent a ON b.agent_id = a.id
	LEFT JOIN pemdata.server_info sd ON b.server_id = sd.server_id
	LEFT JOIN pem.probe_server_version psv
		ON p.id = psv.probe_id
		AND sd.server_version_id = psv.server_version_id
	INNER JOIN pemdata.oc_database ocd
		ON b.server_id = ocd.server_id
	LEFT JOIN pem.probe_config_database c
		ON p.id = c.probe_id AND b.server_id = c.server_id
		AND ocd.database_name = c.database_name
WHERE
	p.target_type_id = 300
	AND NOT p.deleted
	AND ocd.connections_allowed
	AND (p.agent_capability IS NULL
		OR p.agent_capability = ANY(a.agent_capability_list))
	AND (p.any_server_version OR psv.probe_id IS NOT NULL)
	AND (p.collection_method != 'b' OR
		(p.collection_method ='b' AND (a.agent_capability_list @> ARRAY['allow_batch_probes'])
			AND ((strpos(a.platform, p.platform) != 0) OR (a.platform !~ 'windows' AND p.platform = 'unix'))))
UNION ALL
SELECT
	p.id AS probe_id, p.display_name AS probe_display_name,
	p.internal_name AS probe_internal_name, p.probe_key_list,
	p.applies_to_id,
	a.id AS agent_id, b.server_id, oc.database_name AS database_name,
	ARRAY['server_id', 'database_name', 'schema_name']::text[]
		AS parameter_name_list,
	ARRAY[b.server_id::text, oc.database_name, oc.schema_name]::text[]
		AS parameter_value_list,
	p.collection_method,
	COALESCE(psv.probe_code, p.probe_code) AS probe_code,
	p.enabled_by_default, p.default_execution_frequency,
	p.default_lifetime,
	COALESCE(c.enabled, p.enabled_by_default) AS enabled,
	COALESCE(c.execution_frequency, p.default_execution_frequency)
		AS execution_frequency,
	COALESCE(c.lifetime, p.default_lifetime) AS lifetime,
	a.active AS agent_active,
	p.discard_history
FROM
	pem.probe p
	CROSS JOIN pem.agent_server_binding b
	INNER JOIN pem.agent a ON b.agent_id = a.id
	LEFT JOIN pemdata.server_info sd ON b.server_id = sd.server_id
	LEFT JOIN pem.probe_server_version psv
		ON p.id = psv.probe_id
		AND sd.server_version_id = psv.server_version_id
	INNER JOIN pemdata.oc_database ocd
		ON b.server_id = ocd.server_id
	INNER JOIN pemdata.oc_schema oc
		ON ocd.server_id = oc.server_id
		AND ocd.database_name = oc.database_name
	LEFT JOIN pem.probe_config_schema c
		ON p.id = c.probe_id AND b.server_id = c.server_id
		AND oc.database_name = c.database_name
		AND oc.schema_name = c.schema_name
WHERE
	p.target_type_id = 400
	AND NOT p.deleted
	AND ocd.connections_allowed
	AND (p.agent_capability IS NULL
		OR p.agent_capability = ANY(a.agent_capability_list))
	AND (p.any_server_version OR psv.probe_id IS NOT NULL)
	AND (p.collection_method != 'b' OR
		(p.collection_method ='b' AND (a.agent_capability_list @> ARRAY['allow_batch_probes'])
			AND ((strpos(a.platform, p.platform) != 0) OR (a.platform !~ 'windows' AND p.platform = 'unix'))))
UNION ALL
SELECT
	p.id AS probe_id, p.display_name AS probe_display_name,
	p.internal_name AS probe_internal_name, p.probe_key_list,
	p.applies_to_id,
	a.id AS agent_id, b.server_id, oc.database_name AS database_name,
	ARRAY['server_id', 'database_name', 'schema_name', 'table_name']::text[]
		AS parameter_name_list,
	ARRAY[b.server_id::text, oc.database_name, oc.schema_name,
		oc.table_name]::text[] AS parameter_value_list,
	p.collection_method,
	COALESCE(psv.probe_code, p.probe_code) AS probe_code,
	p.enabled_by_default, p.default_execution_frequency,
	p.default_lifetime,
	COALESCE(c.enabled, p.enabled_by_default) AS enabled,
	COALESCE(c.execution_frequency, p.default_execution_frequency)
		AS execution_frequency,
	COALESCE(c.lifetime, p.default_lifetime) AS lifetime,
	a.active AS agent_active,
	p.discard_history
FROM
	pem.probe p
	CROSS JOIN pem.agent_server_binding b
	INNER JOIN pem.agent a ON b.agent_id = a.id
	LEFT JOIN pemdata.server_info sd ON b.server_id = sd.server_id
	LEFT JOIN pem.probe_server_version psv
		ON p.id = psv.probe_id
		AND sd.server_version_id = psv.server_version_id
	INNER JOIN pemdata.oc_database ocd
		ON b.server_id = ocd.server_id
	INNER JOIN pemdata.oc_table oc
		ON ocd.server_id = oc.server_id
		AND ocd.database_name = oc.database_name
	LEFT JOIN pem.probe_config_table c
		ON p.id = c.probe_id AND b.server_id = c.server_id
		AND oc.database_name = c.database_name
		AND oc.schema_name = c.schema_name
		AND oc.table_name = c.table_name
WHERE
	p.target_type_id = 500
	AND NOT p.deleted
	AND ocd.connections_allowed
	AND (p.agent_capability IS NULL
		OR p.agent_capability = ANY(a.agent_capability_list))
	AND (p.any_server_version OR psv.probe_id IS NOT NULL)
	AND (p.collection_method != 'b' OR
		(p.collection_method ='b' AND (a.agent_capability_list @> ARRAY['allow_batch_probes'])
			AND ((strpos(a.platform, p.platform) != 0) OR (a.platform !~ 'windows' AND p.platform = 'unix'))))
UNION ALL
SELECT
	p.id AS probe_id, p.display_name AS probe_display_name,
	p.internal_name AS probe_internal_name, p.probe_key_list,
	p.applies_to_id,
	a.id AS agent_id, b.server_id, oc.database_name AS database_name,
	ARRAY['server_id', 'database_name', 'schema_name', 'index_name']::text[]
		AS parameter_name_list,
	ARRAY[b.server_id::text, oc.database_name, oc.schema_name,
		oc.index_name]::text[] AS parameter_value_list,
	p.collection_method,
	COALESCE(psv.probe_code, p.probe_code) AS probe_code,
	p.enabled_by_default, p.default_execution_frequency,
	p.default_lifetime,
	COALESCE(c.enabled, p.enabled_by_default) AS enabled,
	COALESCE(c.execution_frequency, p.default_execution_frequency)
		AS execution_frequency,
	COALESCE(c.lifetime, p.default_lifetime) AS lifetime,
	a.active AS agent_active,
	p.discard_history
FROM
	pem.probe p
	CROSS JOIN pem.agent_server_binding b
	INNER JOIN pem.agent a ON b.agent_id = a.id
	LEFT JOIN pemdata.server_info sd ON b.server_id = sd.server_id
	LEFT JOIN pem.probe_server_version psv
		ON p.id = psv.probe_id
		AND sd.server_version_id = psv.server_version_id
	INNER JOIN pemdata.oc_database ocd
		ON b.server_id = ocd.server_id
	INNER JOIN pemdata.oc_index oc
		ON ocd.server_id = oc.server_id
		AND ocd.database_name = oc.database_name
	LEFT JOIN pem.probe_config_index c
		ON p.id = c.probe_id AND b.server_id = c.server_id
		AND oc.database_name = c.database_name
		AND oc.schema_name = c.schema_name
		AND oc.index_name = c.index_name
WHERE
	p.target_type_id = 600
	AND NOT p.deleted
	AND ocd.connections_allowed
	AND (p.agent_capability IS NULL
		OR p.agent_capability = ANY(a.agent_capability_list))
	AND (p.any_server_version OR psv.probe_id IS NOT NULL)
	AND (p.collection_method != 'b' OR
		(p.collection_method ='b' AND (a.agent_capability_list @> ARRAY['allow_batch_probes'])
			AND ((strpos(a.platform, p.platform) != 0) OR (a.platform !~ 'windows' AND p.platform = 'unix'))))
UNION ALL
SELECT
	p.id AS probe_id, p.display_name AS probe_display_name,
	p.internal_name AS probe_internal_name, p.probe_key_list,
	p.applies_to_id,
	a.id AS agent_id, b.server_id, oc.database_name AS database_name,
	ARRAY['server_id', 'database_name', 'schema_name', 'sequence_name']::text[]
		AS parameter_name_list,
	ARRAY[b.server_id::text, oc.database_name, oc.schema_name,
		oc.sequence_name]::text[] AS parameter_value_list,
	p.collection_method,
	COALESCE(psv.probe_code, p.probe_code) AS probe_code,
	p.enabled_by_default, p.default_execution_frequency,
	p.default_lifetime,
	COALESCE(c.enabled, p.enabled_by_default) AS enabled,
	COALESCE(c.execution_frequency, p.default_execution_frequency)
		AS execution_frequency,
	COALESCE(c.lifetime, p.default_lifetime) AS lifetime,
	a.active AS agent_active,
	p.discard_history
FROM
	pem.probe p
	CROSS JOIN pem.agent_server_binding b
	INNER JOIN pem.agent a ON b.agent_id = a.id
	LEFT JOIN pemdata.server_info sd ON b.server_id = sd.server_id
	LEFT JOIN pem.probe_server_version psv
		ON p.id = psv.probe_id
		AND sd.server_version_id = psv.server_version_id
	INNER JOIN pemdata.oc_database ocd
		ON b.server_id = ocd.server_id
	INNER JOIN pemdata.oc_sequence oc
		ON ocd.server_id = oc.server_id
		AND ocd.database_name = oc.database_name
	LEFT JOIN pem.probe_config_sequence c
		ON p.id = c.probe_id AND b.server_id = c.server_id
		AND oc.database_name = c.database_name
		AND oc.schema_name = c.schema_name
		AND oc.sequence_name = c.sequence_name
WHERE
	p.target_type_id = 700
	AND NOT p.deleted
	AND ocd.connections_allowed
	AND (p.agent_capability IS NULL
		OR p.agent_capability = ANY(a.agent_capability_list))
	AND (p.any_server_version OR psv.probe_id IS NOT NULL)
	AND (p.collection_method != 'b' OR
		(p.collection_method ='b' AND (a.agent_capability_list @> ARRAY['allow_batch_probes'])
			AND ((strpos(a.platform, p.platform) != 0) OR (a.platform !~ 'windows' AND p.platform = 'unix'))))
UNION ALL
SELECT
	p.id AS probe_id, p.display_name AS probe_display_name,
	p.internal_name AS probe_internal_name, p.probe_key_list,
	p.applies_to_id,
	a.id AS agent_id, b.server_id, oc.database_name AS database_name,
	ARRAY['server_id', 'database_name', 'schema_name', 'function_name']::text[]
		AS parameter_name_list,
	ARRAY[b.server_id::text, oc.database_name, oc.schema_name,
		oc.function_name]::text[] AS parameter_value_list,
	p.collection_method,
	COALESCE(psv.probe_code, p.probe_code) AS probe_code,
	p.enabled_by_default, p.default_execution_frequency,
	p.default_lifetime,
	COALESCE(c.enabled, p.enabled_by_default) AS enabled,
	COALESCE(c.execution_frequency, p.default_execution_frequency)
		AS execution_frequency,
	COALESCE(c.lifetime, p.default_lifetime) AS lifetime,
	a.active AS agent_active,
	p.discard_history
FROM
	pem.probe p
	CROSS JOIN pem.agent_server_binding b
	INNER JOIN pem.agent a ON b.agent_id = a.id
	LEFT JOIN pemdata.server_info sd ON b.server_id = sd.server_id
	LEFT JOIN pem.probe_server_version psv
		ON p.id = psv.probe_id
		AND sd.server_version_id = psv.server_version_id
	INNER JOIN pemdata.oc_database ocd
		ON b.server_id = ocd.server_id
	INNER JOIN pemdata.oc_function oc
		ON ocd.server_id = oc.server_id
		AND ocd.database_name = oc.database_name
	LEFT JOIN pem.probe_config_function c
		ON p.id = c.probe_id AND b.server_id = c.server_id
		AND oc.database_name = c.database_name
		AND oc.schema_name = c.schema_name
		AND oc.function_name = c.function_name
WHERE
	p.target_type_id = 800
	AND NOT p.deleted
	AND ocd.connections_allowed
	AND (p.agent_capability IS NULL
		OR p.agent_capability = ANY(a.agent_capability_list))
	AND (p.any_server_version OR psv.probe_id IS NOT NULL)
	AND (p.collection_method != 'b' OR
		(p.collection_method ='b' AND (a.agent_capability_list @> ARRAY['allow_batch_probes'])
			AND ((strpos(a.platform, p.platform) != 0) OR (a.platform !~ 'windows' AND p.platform = 'unix'))))
UNION ALL
SELECT
	p.id AS probe_id, p.display_name AS probe_display_name,
	p.internal_name AS probe_internal_name, p.probe_key_list,
	p.applies_to_id,
	a.id AS agent_id, b.server_id, oc.database_name AS database_name,
	ARRAY['server_id', 'database_name', 'schema_name', 'view_name']::text[]
		AS parameter_name_list,
	ARRAY[b.server_id::text, oc.database_name, oc.schema_name,
		oc.view_name]::text[] AS parameter_value_list,
	p.collection_method,
	COALESCE(psv.probe_code, p.probe_code) AS probe_code,
	p.enabled_by_default, p.default_execution_frequency,
	p.default_lifetime,
	COALESCE(c.enabled, p.enabled_by_default) AS enabled,
	COALESCE(c.execution_frequency, p.default_execution_frequency)
		AS execution_frequency,
	COALESCE(c.lifetime, p.default_lifetime) AS lifetime,
	a.active AS agent_active,
	p.discard_history
FROM
	pem.probe p
	CROSS JOIN pem.agent_server_binding b
	INNER JOIN pem.agent a ON b.agent_id = a.id
	LEFT JOIN pemdata.server_info sd ON b.server_id = sd.server_id
	LEFT JOIN pem.probe_server_version psv
		ON p.id = psv.probe_id
		AND sd.server_version_id = psv.server_version_id
	INNER JOIN pemdata.oc_database ocd
		ON b.server_id = ocd.server_id
	INNER JOIN pemdata.oc_views oc
		ON ocd.server_id = oc.server_id
		AND ocd.database_name = oc.database_name
	LEFT JOIN pem.probe_config_view c
		ON p.id = c.probe_id AND b.server_id = c.server_id
		AND oc.database_name = c.database_name
		AND oc.schema_name = c.schema_name
		AND oc.view_name = c.view_name
WHERE
	p.target_type_id = 900
	AND NOT p.deleted
	AND ocd.connections_allowed
	AND (p.agent_capability IS NULL
		OR p.agent_capability = ANY(a.agent_capability_list))
	AND (p.any_server_version OR psv.probe_id IS NOT NULL)
	AND (p.collection_method != 'b' OR
		(p.collection_method ='b' AND (a.agent_capability_list @> ARRAY['allow_batch_probes'])
			AND ((strpos(a.platform, p.platform) != 0) OR (a.platform !~ 'windows' AND p.platform = 'unix'))));

SELECT pem.create_data_and_history_tables();

INSERT INTO pem.config VALUES ('dash_replication_archivestat_span', 7, 'days', 'integer');
INSERT INTO pem.config VALUES ('dash_replication_archivestat_timeout', 1800, 'seconds', 'integer');
INSERT INTO pem.config VALUES ('dash_replication_segmentlag_span', 7, 'days', 'integer');
INSERT INTO pem.config VALUES ('dash_replication_segmentlag_timeout', 1800, 'seconds', 'integer');
INSERT INTO pem.config VALUES ('dash_replication_pagelag_span', 7, 'days', 'integer');
INSERT INTO pem.config VALUES ('dash_replication_pagelag_timeout', 1800, 'seconds', 'integer');
INSERT INTO pem.config VALUES ('dash_replication_timelag_span', 7, 'days', 'integer');
INSERT INTO pem.config VALUES ('dash_replication_timelag_timeout', 1800, 'seconds', 'integer');
INSERT INTO pem.config VALUES ('dash_db_eventlag_span', 7, 'days', 'integer');
INSERT INTO pem.config VALUES ('dash_db_eventlag_timeout', 1800, 'seconds', 'integer');
INSERT INTO pem.config VALUES ('dash_db_timelag_span', 7, 'days', 'integer');
INSERT INTO pem.config VALUES ('dash_db_timelag_timeout', 1800, 'seconds', 'integer');

CREATE OR REPLACE FUNCTION pem.generate_replication_segment_lag_chart_data(cidx integer, span_param text, aid integer, sid integer)
	RETURNS TABLE(idx int2, label text, agg_time timestamptz, agg_val numeric) AS
$$
DECLARE
	cur refcursor;
	sub_cur refcursor;
	params varchar[];
	labels varchar[];
	ts interval;
	ai interval;
	mp int4;
	rec RECORD;
	sub_rec RECORD;
	index int4 := 1;
BEGIN
	labels = ARRAY['server_id'];
	params = ARRAY[sid::varchar];

	SELECT COALESCE((value||' '||unit)::interval, time_span), agg_int * '1 minutes'::interval, max_points INTO ts, ai, mp
		FROM pem.metrices_chart, pem.config WHERE cid = cidx AND param = span_param;

	OPEN cur FOR EXECUTE 'SELECT client_addr, client_port FROM pemdata.streaming_replication WHERE server_id = $1::int4' USING sid;
	LOOP
		FETCH cur INTO rec;
		EXIT WHEN NOT FOUND;
		OPEN sub_cur FOR EXECUTE 'SELECT aggregated_time, aggregated_value FROM pem.data_rollup($1::text, $2::text, $3::text, $4::timestamptz, $5::timestamptz, $6::interval, $7::int4, $8::varchar[], $9::varchar[], $10::int4, $11::boolean) WHERE aggregated_time IS NOT NULL ORDER BY aggregated_time'
			USING 'streaming_replication'::text, 'AVG'::text, 'xlog_lag_in_segments'::text, (now() - ts)::timestamptz, now()::timestamptz, ai, mp, labels, params, aid, false;
		LOOP
			FETCH sub_cur INTO sub_rec;
			EXIT WHEN NOT FOUND;

			idx = index;
			label = rec.client_addr || ':' || rec.client_port;
			agg_time = sub_rec.aggregated_time;
			agg_val = sub_rec.aggregated_value;
			RETURN NEXT;
		END LOOP;
		CLOSE sub_cur;
	END LOOP;
	CLOSE cur;
END
$$ LANGUAGE 'plpgsql';

CREATE OR REPLACE FUNCTION pem.generate_replication_page_lag_chart_data(cidx integer, span_param text, aid integer, sid integer)
	RETURNS TABLE(idx int2, label text, agg_time timestamptz, agg_val numeric) AS
$$
DECLARE
	cur refcursor;
	sub_cur refcursor;
	params varchar[];
	labels varchar[];
	ts interval;
	ai interval;
	mp int4;
	rec RECORD;
	sub_rec RECORD;
	index int4 := 1;
BEGIN
	labels = ARRAY['server_id'];
	params = ARRAY[sid::varchar];

	SELECT COALESCE((value||' '||unit)::interval, time_span), agg_int * '1 minutes'::interval, max_points INTO ts, ai, mp FROM pem.metrices_chart, pem.config WHERE cid = cidx AND param = span_param;

	OPEN cur FOR EXECUTE 'SELECT client_addr, client_port FROM pemdata.streaming_replication WHERE server_id = $1::int4' USING sid;
	LOOP
		FETCH cur INTO rec;
		EXIT WHEN NOT FOUND;
		OPEN sub_cur FOR EXECUTE 'SELECT aggregated_time, aggregated_value FROM pem.data_rollup($1::text, $2::text, $3::text, $4::timestamptz, $5::timestamptz, $6::interval, $7::int4, $8::varchar[], $9::varchar[], $10::int4, $11::boolean) WHERE aggregated_time IS NOT NULL ORDER BY aggregated_time'
			USING 'streaming_replication'::text, 'AVG'::text, 'xlog_lag_in_pages'::text, (now() - ts)::timestamptz, now()::timestamptz, ai, mp, labels, params, aid, false;
		LOOP
			FETCH sub_cur INTO sub_rec;
			EXIT WHEN NOT FOUND;

			idx = index;
			label = rec.client_addr || ':' || rec.client_port;
			agg_time = sub_rec.aggregated_time;
			agg_val = sub_rec.aggregated_value;
			RETURN NEXT;
		END LOOP;
		CLOSE sub_cur;
	END LOOP;
	CLOSE cur;
END
$$ LANGUAGE 'plpgsql';

CREATE OR REPLACE FUNCTION pem.generate_slony_event_lag_chart_data(cidx integer, span_param text, aid integer, sid integer, dbname text)
	RETURNS TABLE(idx int2, label text, agg_time timestamptz, agg_val numeric) AS
$$
DECLARE
	cur refcursor;
	sub_cur refcursor;
	params varchar[];
	labels varchar[];
	ts interval;
	ai interval;
	mp int4;
	rec RECORD;
	sub_rec RECORD;
	index int4 := 1;
BEGIN
	labels = ARRAY['server_id', 'database_name'];
	params = ARRAY[sid::varchar, dbname::varchar];

	SELECT COALESCE((value||' '||unit)::interval, time_span), agg_int * '1 minutes'::interval, max_points INTO ts, ai, mp
		FROM pem.metrices_chart, pem.config WHERE cid = cidx AND param = span_param;

	OPEN cur FOR EXECUTE 'SELECT cluster_name FROM pemdata.slony_replication WHERE server_id = $1::int4 AND database_name = $2::text' USING sid, dbname;
	LOOP
		FETCH cur INTO rec;
		EXIT WHEN NOT FOUND;
		OPEN sub_cur FOR EXECUTE 'SELECT aggregated_time, aggregated_value FROM pem.data_rollup($1::text, $2::text, $3::text, $4::timestamptz, $5::timestamptz, $6::interval, $7::int4, $8::varchar[], $9::varchar[], $10::int4, $11::boolean) WHERE aggregated_time IS NOT NULL ORDER BY aggregated_time'
			USING 'slony_replication'::text, 'AVG'::text, 'lag_num_events'::text, (now() - ts)::timestamptz, now()::timestamptz, ai, mp, labels, params, aid, false;
		LOOP
			FETCH sub_cur INTO sub_rec;
			EXIT WHEN NOT FOUND;

			idx = index;
			label = rec.cluster_name;
			agg_time = sub_rec.aggregated_time;
			agg_val = sub_rec.aggregated_value;
			RETURN NEXT;
		END LOOP;
		CLOSE sub_cur;
	END LOOP;
	CLOSE cur;
END
$$ LANGUAGE 'plpgsql';

CREATE OR REPLACE FUNCTION pem.generate_slony_time_lag_chart_data(cidx integer, span_param text, aid integer, sid integer, dbname text)
	RETURNS TABLE(idx int2, label text, agg_time timestamptz, agg_val numeric) AS
$$
DECLARE
	cur refcursor;
	sub_cur refcursor;
	params varchar[];
	labels varchar[];
	ts interval;
	ai interval;
	mp int4;
	rec RECORD;
	sub_rec RECORD;
	index int4 := 1;
BEGIN
	labels = ARRAY['server_id', 'database_name'];
	params = ARRAY[sid::varchar, dbname::varchar];

	SELECT COALESCE((value||' '||unit)::interval, time_span), agg_int * '1 minutes'::interval, max_points INTO ts, ai, mp
		FROM pem.metrices_chart, pem.config WHERE cid = cidx AND param = span_param;

	OPEN cur FOR EXECUTE 'SELECT cluster_name FROM pemdata.slony_replication WHERE server_id = $1::int4 AND database_name = $2::text' USING sid, dbname;
	LOOP
		FETCH cur INTO rec;
		EXIT WHEN NOT FOUND;
		OPEN sub_cur FOR EXECUTE 'SELECT aggregated_time, aggregated_value FROM pem.data_rollup($1::text, $2::text, $3::text, $4::timestamptz, $5::timestamptz, $6::interval, $7::int4, $8::varchar[], $9::varchar[], $10::int4, $11::boolean) WHERE aggregated_time IS NOT NULL ORDER BY aggregated_time'
			USING 'slony_replication'::text, 'AVG'::text, 'lag_time'::text, (now() - ts)::timestamptz, now()::timestamptz, ai, mp, labels, params, aid, false;
		LOOP
			FETCH sub_cur INTO sub_rec;
			EXIT WHEN NOT FOUND;

			idx = index;
			label = rec.cluster_name;
			agg_time = sub_rec.aggregated_time;
			agg_val = sub_rec.aggregated_value;
			RETURN NEXT;
		END LOOP;
		CLOSE sub_cur;
	END LOOP;
	CLOSE cur;
END
$$ LANGUAGE 'plpgsql';

INSERT INTO pem.chart_catagory(id, name, descp, owner) VALUES (15, 'Streaming Replication Analysis', 'Charts render on the Streaming Replication Analysis dashboard', 0);

INSERT INTO pem.chart(id, cid, fid, type, level, name, owner, shared, ref_cnt, reload, summary, labels, params, rwlimit_span_param, ref_timeout_param) VALUES
	(80, 15, NULL,'L', ARRAY[200], 'WAL Archive Status',   0, NULL, 1, 50000, NULL, ARRAY['# WAL Files', '# Archives Done', '# Archives Pending'], NULL, 'dash_replication_archivestat_span', 'dash_replication_archivestat_timeout'),
	(81, 15, 81,  'L', ARRAY[200], 'WAL Lag Segments',     0, NULL, 1, 50000, NULL, NULL, ARRAY['agent_id', 'server_id'], 'dash_replication_segmentlag_span', 'dash_replication_segmentlag_timeout'),
	(82, 15, 82,  'L', ARRAY[200], 'WAL Lag Pages',        0, NULL, 1, 50000, NULL, NULL, ARRAY['agent_id', 'server_id'], 'dash_replication_pagelag_span', 'dash_replication_pagelag_timeout'),
	(83, 15, 83, 'TE', ARRAY[200], 'Replication Lag Time Details',   0, NULL, 1, 50000, NULL, NULL, ARRAY['server_id'], NULL, 'dash_replication_timelag_timeout'),
	(84, 15, NULL,'L', ARRAY[200], 'Replication Lag Time', 0, NULL, 1, 50000, 83,   ARRAY['Lag Time'], NULL, 'dash_replication_timelag_span', 'dash_replication_timelag_timeout'),
	(85,  4, 85,  'L', ARRAY[300], 'Number of Events Lag', 0, NULL, 1, 50000, NULL, NULL, ARRAY['agent_id', 'server_id', 'database_name'], 'dash_db_eventlag_span', 'dash_db_eventlag_timeout'),
	(86,  4, 86,  'L', ARRAY[300], 'Time Lag',             0, NULL, 1, 50000, NULL, NULL, ARRAY['agent_id', 'server_id', 'database_name'], 'dash_db_timelag_span', 'dash_db_timelag_timeout');


-- -------------------------------------- Replication Analysis Dashboard
INSERT INTO pem.line_chart (cid, type, yaxis) VALUES (80, 'M', '#');
INSERT INTO pem.metrices_chart (cid, time_span) VALUES (80, '7 days'::interval);
INSERT INTO pem.chart_metric (cid, mid, tbl, metrices, glimit, gorderby, agg_func) VALUES
	(80, 1, 'number_of_wal_files', ARRAY['number_of_wal_files'], 1, NULL, ARRAY['A']);
INSERT INTO pem.chart_metric (cid, mid, tbl, metrices, glimit, gorderby, agg_func) VALUES
	(80, 2, 'wal_archive_status', ARRAY['archive_done', 'archive_pending'], 1, NULL, ARRAY['A', 'A']);

INSERT INTO pem.line_chart (cid, type, yaxis) VALUES (81, 'M', '#');
INSERT INTO pem.metrices_chart (cid, time_span) VALUES (81, '7 days'::interval);
INSERT INTO pem.chart_func(id, type, func, r_sys_obj) VALUES
	(81, 'Q', E'SELECT idx, label, ''Date('' || (EXTRACT(EPOCH FROM agg_time) * 1000)::numeric(40, 0)::text || '')'', agg_val FROM pem.generate_replication_segment_lag_chart_data(81, ''dash_replication_segmentlag_span'', $1::int4, $2::int4) ORDER BY idx, agg_time', false);

INSERT INTO pem.line_chart (cid, type, yaxis) VALUES (82, 'M', '#');
INSERT INTO pem.metrices_chart (cid, time_span) VALUES (82, '7 days'::interval);
INSERT INTO pem.chart_func(id, type, func, r_sys_obj) VALUES
	(82, 'Q', E'SELECT idx, label, ''Date('' || (EXTRACT(EPOCH FROM agg_time) * 1000)::numeric(40, 0)::text || '')'', agg_val FROM pem.generate_replication_page_lag_chart_data(82, ''dash_replication_pagelag_span'', $1::int4, $2::int4) ORDER BY idx, agg_time', false);

INSERT INTO pem.chart_func(id, type, func, r_sys_obj) VALUES
	(83, 'Q', E'
	SELECT
		$$Replication Status: $$|| COALESCE((SELECT (CASE WHEN replication_paused THEN $$Paused$$ ELSE $$Running$$ END)
		FROM pemdata.streaming_replication_lag_time WHERE server_id = $1), $$Unknown$$)', false);

INSERT INTO pem.line_chart (cid, type, yaxis) VALUES (84, 'M', 'minute(s)');
INSERT INTO pem.metrices_chart (cid, time_span) VALUES (84, '7 days'::interval);
INSERT INTO pem.chart_metric (cid, mid, tbl, metrices, glimit, gorderby, agg_func) VALUES
	(84, 1, 'streaming_replication_lag_time', ARRAY['lag_time'], 1, NULL, ARRAY['A']);

INSERT INTO pem.line_chart (cid, type, yaxis) VALUES (85, 'M', '#');
INSERT INTO pem.metrices_chart (cid, time_span) VALUES (85, '7 days'::interval);
INSERT INTO pem.chart_func(id, type, func, r_sys_obj) VALUES
	(85, 'Q', E'SELECT idx, label, ''Date('' || (EXTRACT(EPOCH FROM agg_time) * 1000)::numeric(40, 0)::text || '')'', agg_val FROM pem.generate_slony_event_lag_chart_data(85, ''dash_db_eventlag_span'', $1::int4, $2::int4, $3::text) ORDER BY idx, agg_time', false);

INSERT INTO pem.line_chart (cid, type, yaxis) VALUES (86, 'M', 'minute(s)');
INSERT INTO pem.metrices_chart (cid, time_span) VALUES (86, '7 days'::interval);
INSERT INTO pem.chart_func(id, type, func, r_sys_obj) VALUES
	(86, 'Q', E'SELECT idx, label, ''Date('' || (EXTRACT(EPOCH FROM agg_time) * 1000)::numeric(40, 0)::text || '')'', agg_val FROM pem.generate_slony_time_lag_chart_data(86, ''dash_db_timelag_span'', $1::int4, $2::int4, $3::text) ORDER BY idx, agg_time', false);

REVOKE EXECUTE ON FUNCTION pem.generate_replication_segment_lag_chart_data(integer, text, integer, integer) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION pem.generate_replication_page_lag_chart_data(integer, text, integer, integer) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION pem.generate_slony_event_lag_chart_data(integer, text, integer, integer, text) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION pem.generate_slony_time_lag_chart_data(integer, text, integer, integer, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION pem.generate_replication_segment_lag_chart_data(integer, text, integer, integer) TO pem_user;
GRANT EXECUTE ON FUNCTION pem.generate_replication_page_lag_chart_data(integer, text, integer, integer) TO pem_user;
GRANT EXECUTE ON FUNCTION pem.generate_slony_event_lag_chart_data(integer, text, integer, integer, text) TO pem_user;
GRANT EXECUTE ON FUNCTION pem.generate_slony_time_lag_chart_data(integer, text, integer, integer, text) TO pem_user;

--
-- Streaming Replication Alert
--
SELECT pem.create_alert_template(
        'Number of WAL archives pending',
        'In streaming replication number of WAL files pending to be replayed at standby',
        $sql$
SELECT archive_pending FROM pemdata.wal_archive_status WHERE server_id = ${server_id}$sql$,
        200, NULL, NULL, NULL, NULL,'{wal_archive_status}', 75);

SELECT pem.create_alert_template(
        'Standby server lag behind the master by WAL segments',
        'In streaming replication standy server lag behind the master by WAL segments',
        $sql$
SELECT xlog_lag_in_segments FROM pemdata.streaming_replication WHERE server_id = ${server_id} AND client_addr = '${param_1}' AND client_port = ${param_2}$sql$,
        200, '{Standby hostname, Standby port}', '{STRING,INTEGER}', NULL, NULL,'{streaming_replication}', 76);

SELECT pem.create_alert_template(
        'Standby server lag behind the master by WAL pages',
        'In streaming replication standy server lag behind the master by WAL pages',
        $sql$
SELECT xlog_lag_in_pages FROM pemdata.streaming_replication WHERE server_id = ${server_id} AND client_addr = '${param_1}' AND client_port = ${param_2}$sql$,
        200, '{Standby hostname, Standby port}', '{STRING,INTEGER}', NULL, NULL,'{streaming_replication}', 77);

SELECT pem.create_alert_template(
        'Number of minutes lag of standby server from master server',
        'In streaming replication number of minutes standby node is lagging behind the master node',
        $sql$
SELECT lag_time FROM pemdata.streaming_replication_lag_time WHERE server_id = ${server_id}$sql$,
        200, NULL, NULL, NULL, 'Minutes','{streaming_replication_lag_time}', 78);

CREATE OR REPLACE FUNCTION pem.process_one_alert() RETURNS BOOL AS $$
DECLARE
	err			text;
	sql			text;
	state			pem.alert_state;
	sql_ret			numeric;
	alert_rec		record;
	locked_alert		bool;
	probe_disabled_err	text;
	zero_rows_err		text;
	probe_enabled		bool;
	all_probes_enabled	bool;
	alert_state_since	timestamp with time zone;
	reminder_interval	integer;
	subject			text;
	message			text;
	send_mail_val		bool;
	min_probe_interval	integer;
	probe_interval		integer;
	default_flapping_detection_state_change integer;
	down_objects_list text;
	template_name text;
	write_message_streaming_repl text;
	flush_message_streaming_repl text;
	replay_message_streaming_repl text;
	upgrade_pkg_list text;
	new_pkg_list text;
	obsolete_pkg_list text;
BEGIN
	probe_disabled_err = 'Required probe(s) ';
	zero_rows_err = 'Zero rows returned';

	locked_alert = false;

	FOR alert_rec in	SELECT al.*, ast.current_state AS state, at.sql, at.display_name AS template_name,
								at.probe_dependency_list, ast.state_change_count
						FROM (pem.alert AS al
								JOIN pem.alert_template AS at
								ON al.template_id = at.id)
						LEFT JOIN pem.alert_status AS ast
							ON(al.id = ast.alert_id)
						WHERE al.enabled = true
						-- We do not process alerts that are known erroneous
						AND (COALESCE(al.error_message, '' ) IN ('', zero_rows_err)
							OR al.error_message LIKE probe_disabled_err || '%' )
						AND (now() - COALESCE(ast.last_processed, '1900-01-01'))
							>= (al.check_frequency||'minutes')::interval
						/*
						 * We process only those alerts that are bound to
						 * 'active' agents and servers.
						 *
						 * Note:alert.agent_id, agent|server.active are defined
						 * NOT NULL.
						 */
						AND CASE WHEN al.agent_id IN (-1 , 0) THEN TRUE
							ELSE al.agent_id IN (SELECT id FROM pem.agent WHERE active AND NOT alert_blackout)
							END
						AND CASE WHEN (al.server_id IS NULL) OR (al.server_id = 0) THEN TRUE
							ELSE al.server_id IN
									(SELECT id FROM pem.server WHERE active AND NOT alert_blackout
									INTERSECT
									SELECT server_id FROM pem.agent_server_binding)
							END
						ORDER BY ast.last_processed NULLS FIRST
	LOOP
		IF (pg_try_advisory_lock(0, alert_rec.id) = true) THEN
			locked_alert = true;
			EXIT; /* the loop */
		END IF;
	END LOOP;

	/* If we couldn't find or lock any candidate alert ... */
	IF (locked_alert = false) THEN
		/* tell the caller that we didn't process any alerts */
		RETURN false;
	END IF;

	/*
	 * We should return only 'true' from here on, since there may be more alerts
	 * to process.
	 *
	 * Also try to capture any ERROR and mark the alert as invalid
	 * instead of passing that ERROR back to the caller.
	 */

	sql = alert_rec.sql;

	/* Replace any reference to hierarchy-related alert parameters */
	sql = regexp_replace(sql, E'\\${agent_id}',		COALESCE(alert_rec.agent_id::text,	'')::text, 'g');
	sql = regexp_replace(sql, E'\\${server_id}',	COALESCE(alert_rec.server_id::text,	'')::text, 'g');
	sql = regexp_replace(sql, E'\\${database_name}',COALESCE(alert_rec.database_name,	'')::text, 'g');
	sql = regexp_replace(sql, E'\\${schema_name}',	COALESCE(alert_rec.schema_name,		'')::text, 'g');
	sql = regexp_replace(sql, E'\\${package_name}',	COALESCE(alert_rec.package_name,	'')::text, 'g');
	sql = regexp_replace(sql, E'\\${object_name}',	COALESCE(alert_rec.object_name,		'')::text, 'g');

	/* Replace ${param_n} with corresponding alert parameters */
	FOR i IN 1..COALESCE(array_upper(alert_rec.params, 1), 0) LOOP
		sql = regexp_replace(sql, E'\\${param_' || i || '}', alert_rec.params[i]::text, 'g');
	END LOOP;

	err = '';

	/* Check any required probe is disabled from the probe dependency list */
	all_probes_enabled = true;
	FOR i IN 1..COALESCE(array_upper(alert_rec.probe_dependency_list, 1), 0) LOOP
		SELECT v.enabled INTO probe_enabled FROM pem.probe_target_view v LEFT JOIN pem.probe p ON p.id = v.probe_id
		WHERE v.probe_internal_name = alert_rec.probe_dependency_list[i]
		AND CASE WHEN p.target_type_id = 100 THEN (v.agent_id = alert_rec.agent_id)
			WHEN p.target_type_id = 200 THEN (v.server_id = alert_rec.server_id)
			WHEN p.target_type_id = 300 THEN (v.server_id = alert_rec.server_id AND v.database_name = alert_rec.database_name)
			ELSE (v.server_id = alert_rec.server_id AND v.database_name = alert_rec.database_name
				AND v.parameter_value_list[3] = alert_rec.schema_name)
			END;
		IF NOT probe_enabled THEN
			probe_disabled_err = probe_disabled_err || alert_rec.probe_dependency_list[i] || ',';
			all_probes_enabled = false;
		END IF;

		-- Get minimum probe interval from all dependent probes
		SELECT default_execution_frequency INTO probe_interval FROM pem.probe WHERE internal_name = alert_rec.probe_dependency_list[i];
		IF (probe_interval <  min_probe_interval) OR (i = 1) THEN
			min_probe_interval = probe_interval;
		END IF;
	END LOOP;

	probe_disabled_err = trim(trailing ',' from probe_disabled_err);
	probe_disabled_err = probe_disabled_err || ' are disabled.';

	IF NOT all_probes_enabled THEN
		err = probe_disabled_err;
	ELSE
		RAISE DEBUG 'Alert query being executed: %', sql;

		BEGIN
			EXECUTE sql INTO STRICT sql_ret;
		EXCEPTION
			WHEN no_data_found THEN
				IF all_probes_enabled THEN
					err = zero_rows_err;
				END IF;

			WHEN OTHERS THEN
				err = SQLERRM;
		END;
	END IF;

	-- If there was an error while processing the alert's sql
	IF (err <> '') THEN
		-- Set that error message on the alert
		UPDATE pem.alert
		SET error_message = err
		WHERE id = alert_rec.id;

		-- ... and also set the last processed timestamp
		UPDATE pem.alert_status
		SET last_processed = now()
		WHERE alert_id = alert_rec.id;

		-- If there wasn't any row for this alert already, then populate one.
		IF (NOT FOUND) THEN
			INSERT INTO pem.alert_status
			VALUES (alert_rec.id, NULL, NULL, NULL, now());
		END IF;

		-- RAISE NOTICE 'Encountered error while processing SQL: %', err;

		/*
		 * XXX: There's a small window of race condition here. Another transaction
		 * might pick up processing of this alert immediately after we unlock it
		 * below using non-transactional advisory lock.
		 *
		 * Someday consider trading this for transactional advisory locks. This
		 * will be possible when we mandate PG 9.1 as a minimum requirement.
		 */
		PERFORM pg_catalog.pg_advisory_unlock(0, alert_rec.id);

		RETURN true;
	ELSE
		-- Set that error message to NULL on the alert if the SQL executes successfully
		UPDATE pem.alert
		SET error_message = NULL
		WHERE id = alert_rec.id;
	END IF;

	/* Some sample alerts
		Table size:  1GB => low, 2GB => med, 5GB => high

		>5 high
		>2 med
		>1 low

		operator: > ; thresholds: {1,2,5}

		current_connections : 50 => low, 20 => med, 5 => high

		<5 high
		<20 med
		<50 low

		operator: < ; thresholds: {50,20,5}
	 */

	IF (alert_rec.operator = '<') THEN
		IF (sql_ret < alert_rec.thresholds[3]) THEN
			state = 'HIGH';
		ELSIF (sql_ret < alert_rec.thresholds[2]) THEN
			state = 'MEDIUM';
		ELSIF (sql_ret < alert_rec.thresholds[1]) THEN
			state = 'LOW';
		ELSE
			state = NULL;
		END IF;
	ELSIF (alert_rec.operator = '>') THEN
		IF (sql_ret > alert_rec.thresholds[3]) THEN
			state = 'HIGH';
		ELSIF (sql_ret > alert_rec.thresholds[2]) THEN
			state = 'MEDIUM';
		ELSIF (sql_ret > alert_rec.thresholds[1]) THEN
			state = 'LOW';
		ELSE
			state = NULL;
		END IF;
	END IF;

	/*
	 * For an alert that is active (state IS NOT NULL), we do not want to clear
	 * its 'acknowledged' flag the first time it goes lower than LOW. So we wait
	 * for another round of check, and if it still appears lower than LOW, then
	 * we reset its acknowledged flag.
	 *
	 * The pseudo-code is:
	 *
	 * if (acked = true)
	 *     if current severity_level is null and previous/stored severity_level is null
	 *        set acked = false
	 *
	 *     if severity_level increases or changed from null to not-null
	 *         do nothing
	 *
	 *     If severity_level decreases or goes from not-null to null
	 *         do nothing.
	 * end if
	 */
	IF (alert_rec.acknowledged) THEN
		IF (state IS NULL AND alert_rec.state IS NULL) THEN
			-- State has been lower than LOW, two times in a row.
			UPDATE pem.alert
			SET acknowledged = false
			WHERE id = alert_rec.id;

			--send alert cleared SMTP notification
			IF alert_rec.send_email THEN
				-- Create subject and message
				SELECT subject_mail, message_mail INTO subject, message FROM pem.create_email(alert_rec.id, 'Alert Cleared');
				send_mail_val = pem.send_email(alert_rec.email_group_id, subject, message);
				IF send_mail_val THEN
					-- update the time of mail send.
					UPDATE pem.alert SET last_mail_send = now() WHERE id = alert_rec.id;
				END IF;
			END IF;
		END IF;
	END IF;

	UPDATE pem.alert_status
	SET last_processed = now(),
		current_value = sql_ret,
		current_state = state, -- may be NULL
		current_state_since =	CASE
								WHEN state IS DISTINCT FROM alert_rec.state
								THEN now()
								ELSE current_state_since
								END
	WHERE alert_id = alert_rec.id;

	-- If there wasn't any status row for this alert already, then populate one.
	IF (NOT FOUND) THEN
		INSERT INTO pem.alert_status
		VALUES (alert_rec.id, sql_ret, state,
				CASE
				WHEN state IS NOT NULL
				THEN now()
				ELSE NULL
				END,
				now());
	END IF;

	-- Check for reminder notification
	SELECT value INTO reminder_interval FROM pem.config WHERE param = 'reminder_notification_interval';
	SELECT current_state_since INTO alert_state_since FROM pem.alert_status WHERE alert_id = alert_rec.id;
	IF alert_rec.send_email AND (NOT alert_rec.acknowledged) AND (alert_state_since IS NOT NULL) AND (state IS NOT NULL) AND (NOT alert_rec.flapping_detected)
	AND ((now() - alert_state_since) >= (reminder_interval||'hours')::interval)
	AND ((now() - alert_rec.last_mail_send) >= (reminder_interval||'hours')::interval) THEN

		-- Create subject and message
		SELECT subject_mail, message_mail INTO subject, message FROM pem.create_email(alert_rec.id, 'Alert Reminder');
		message = regexp_replace(message, '%CurrentValue%', COALESCE(sql_ret, 0)::text);
		message = regexp_replace(message, '%CurrentState%', state::text);
		message = regexp_replace(message, '%AlertingSince%', alert_state_since::text);

		-- Get the list of down objetcs
		down_objects_list = pem.get_down_objects_list(alert_rec.template_name);
		message = regexp_replace(message, '%DownObjects%', down_objects_list::text);

		-- Special handling for 'Write lag Alert' alert
		IF (alert_rec.template_name = 'Number of standby servers lag behind the master by write location') THEN
			SELECT pem.email_write_lag_streaming_replication() INTO write_message_streaming_repl;
			message = message || COALESCE(write_message_streaming_repl, '')::text ;
		END IF;

		IF (alert_rec.template_name = 'Number of standby servers lag behind the master by flush location') THEN
			SELECT pem.email_flush_lag_streaming_replication() INTO flush_message_streaming_repl;
			message = message || COALESCE(flush_message_streaming_repl, '')::text ;
		END IF;

		IF (alert_rec.template_name = 'Number of standby servers lag behind the master by replay location') THEN
			SELECT pem.email_replay_lag_streaming_replication() INTO replay_message_streaming_repl;
			message = message || COALESCE(replay_message_streaming_repl, '')::text ;
		END IF;

		-- Get the list of obsolete packages and packages for which updates are avalibale
		IF (alert_rec.template_name = 'Package version mismatch') THEN
			SELECT upgrade_packages_list, new_packages_list, obsolete_packages_list INTO upgrade_pkg_list,
			new_pkg_list, obsolete_pkg_list FROM pem.get_mismatch_packages_list(alert_rec.agent_id);

			message = message || E'\n' || COALESCE(upgrade_pkg_list, '')::text || E'\n' || COALESCE(obsolete_pkg_list, '')::text;
		END IF;

		-- Special handling for segment lag/page lag alerts
		IF (alert_rec.template_name = 'Standby server lag behind the master by WAL segments'
			OR alert_rec.template_name = 'Standby server lag behind the master by WAL pages') THEN
			IF array_lower(alert_rec.params, 1) IS NOT NULL THEN
				message = message || E'Standby server: ' || array_to_string(replication_alert_params, ':');
			END IF;
		END IF;

		send_mail_val = pem.send_email(alert_rec.email_group_id, subject, message);
		IF send_mail_val THEN
			-- update the time of mail send.
			UPDATE pem.alert SET last_mail_send = now() WHERE id = alert_rec.id;
		END IF;
	END IF;

	SELECT value INTO default_flapping_detection_state_change FROM pem.config WHERE param = 'flapping_detection_state_change';

	IF (NOT alert_rec.flapping_detected) THEN
		--Flapping start is true when more than N state changes have occurred over (N + 1) * (min(probe_interval) * 2) seconds
		IF ((now() - alert_rec.last_flapping_detection_processed) >=
		(((default_flapping_detection_state_change + 1) * (min_probe_interval * 2)) * '1 second'::interval)) THEN

			UPDATE pem.alert SET last_flapping_detection_processed = now() WHERE id = alert_rec.id;
			UPDATE pem.alert_status SET state_change_count = 0 WHERE alert_id = alert_rec.id;

			IF (alert_rec.state_change_count > default_flapping_detection_state_change) THEN
				UPDATE pem.alert SET flapping_detected = 't' WHERE id = alert_rec.id;
			END IF;
		END IF;
	ELSE
		-- Flapping end is true when zero state changes have occurred over 2N * min(probe_interval) seconds
		IF ((now() - alert_rec.last_flapping_detection_processed) >=
		((2* default_flapping_detection_state_change * min_probe_interval) * '1 second'::interval)) THEN
			UPDATE pem.alert SET last_flapping_detection_processed = now() WHERE id = alert_rec.id;

			IF (alert_rec.state_change_count = 0) THEN
				UPDATE pem.alert SET flapping_detected = 'f' WHERE id = alert_rec.id;
			END IF;
		END IF;
	END IF;

	PERFORM pg_catalog.pg_advisory_unlock(0, alert_rec.id);
	RETURN true;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION pem.send_notifications() RETURNS trigger AS $$
DECLARE
	subject text;
	message text;
	mail_group_id integer;
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
BEGIN
	-- Get alert details
	SELECT
		agent_id, template_id, email_group_id, send_email, acknowledged, flapping_detected, send_trap, snmp_trap_version
	INTO
		agentid, templateid, mail_group_id, is_send_email, is_acknowledged, is_flapping_detected, is_send_trap, trap_version
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
	END IF;

	IF ((TG_OP = 'UPDATE') AND (NEW.current_state IS DISTINCT FROM OLD.current_state)) THEN
		-- Update state change count
		UPDATE pem.alert_status SET state_change_count = state_change_count + 1 WHERE alert_id = NEW.alert_id;

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
	END IF;

	RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION pem.generate_alert_mib()
RETURNS text AS $$
DECLARE
	mib_text text;
BEGIN

	mib_text = E'\n-- File Name : PEM-ALERTING-MIB\n
-- Date      : ' || now()::text || E'\n
-- Author    : EnterpriseDB \n

PEM-ALERTING-MIB	DEFINITIONS ::= BEGIN

	IMPORTS
		enterprises, MODULE-IDENTITY, OBJECT-TYPE, Integer32, NOTIFICATION-TYPE
			FROM SNMPv2-SMI
		DisplayString
			FROM SNMPv2-TC
		MODULE-COMPLIANCE, OBJECT-GROUP, NOTIFICATION-GROUP
			FROM SNMPv2-CONF;


	postgresql	MODULE-IDENTITY
		LAST-UPDATED	"201109271419Z"
		ORGANIZATION	"EnterpriseDB"
		CONTACT-INFO	"http://www.enterprisedb.com"
		DESCRIPTION	"This MIB file used for alerting notifications."
		REVISION	"201109271419Z"
		DESCRIPTION	"This MIB file used for alerting notifications."
		::=  {  enterprises  27645  }

	pem	OBJECT IDENTIFIER ::=  {  postgresql  5444  }

	agentAlerts	OBJECT IDENTIFIER ::=  {  pem  1  }

	serverAlerts	OBJECT IDENTIFIER ::=  {  pem  2  }

	databaseAlerts	OBJECT IDENTIFIER ::=  {  pem  3  }

	schemaAlerts	OBJECT IDENTIFIER ::=  {  pem  4  }

	objectAlerts	OBJECT IDENTIFIER ::=  {  pem  5  }

	globalAlerts	OBJECT IDENTIFIER ::=  {  pem  6  }

	bindingVariables	OBJECT IDENTIFIER ::=  {  pem  7  }

	pemObjectGroup  OBJECT-GROUP
		OBJECTS { alertName,
			agentID,
			agentName,
			databaseName,
			objectName,
			previousStatus,
			previousValue,
			schemaName,
			serverID,
			serverName,
			status,
			thresholdValue,
			value,
			recordedTime,
			downObjects,
			streamingReplicationLagBytes,
			updatePackages,
			standbyServerDetails}
	STATUS 	current
	DESCRIPTION
		"This group contains the notification detail objects"
	::= { postgresql 5445 }

	alertName	OBJECT-TYPE
		SYNTAX			DisplayString
		MAX-ACCESS		read-only
		STATUS			current
		DESCRIPTION		"This parameter gives the alert name"
		::=  {  bindingVariables  1  }

	agentID		OBJECT-TYPE
		SYNTAX			Integer32
		MAX-ACCESS		read-only
		STATUS			current
		DESCRIPTION		"This parameter gives the agent id for which this alert is raised"
		::=  {  bindingVariables  2  }

	serverID	OBJECT-TYPE
		SYNTAX			Integer32
		MAX-ACCESS		read-only
		STATUS			current
		DESCRIPTION		"This parameter gives the server id for which this alert is raised"
		::=  {  bindingVariables  3  }

	agentName	OBJECT-TYPE
		SYNTAX			DisplayString
		MAX-ACCESS		read-only
		STATUS			current
		DESCRIPTION		"This parameter gives the agent name for which this alert is raised"
		::=  {  bindingVariables  4  }

	serverName	OBJECT-TYPE
		SYNTAX			DisplayString
		MAX-ACCESS		read-only
		STATUS			current
		DESCRIPTION		"This parameter gives the server name for which this alert is raised"
		::=  {  bindingVariables  5  }

	databaseName	OBJECT-TYPE
		SYNTAX			DisplayString
		MAX-ACCESS		read-only
		STATUS			current
		DESCRIPTION		"This parameter gives the database name for which this alert is raised"
		::=  {  bindingVariables  6  }

	schemaName	OBJECT-TYPE
		SYNTAX			DisplayString
		MAX-ACCESS		read-only
		STATUS			current
		DESCRIPTION		"This parameter gives the schema name for which this alert is raised"
		::=  {  bindingVariables  7  }

	objectName	OBJECT-TYPE
		SYNTAX			DisplayString
		MAX-ACCESS		read-only
		STATUS			current
		DESCRIPTION		"This parameter gives the object name for which this alert is raised"
		::=  {  bindingVariables  8  }

	thresholdValue	OBJECT-TYPE
		SYNTAX			DisplayString
		MAX-ACCESS		read-only
		STATUS			current
		DESCRIPTION		"This parameter gives the threshold value of the alert"
		::=  {  bindingVariables  9  }

	previousValue	OBJECT-TYPE
		SYNTAX			DisplayString
		MAX-ACCESS		read-only
		STATUS			current
		DESCRIPTION		"This parameter gives the current value of the alert"
		::=  {  bindingVariables  10  }

	value	OBJECT-TYPE
		SYNTAX			DisplayString
		MAX-ACCESS		read-only
		STATUS			current
		DESCRIPTION		"This parameter gives the current value of the alert"
		::=  {  bindingVariables  11  }

	previousStatus	OBJECT-TYPE
		SYNTAX			INTEGER  { low ( 0 ) , medium ( 1 ), high ( 2 ) }
		MAX-ACCESS		read-only
		STATUS			current
		DESCRIPTION		"This parameter gives the current status of the alert"
		::=  {  bindingVariables  12  }

	status	OBJECT-TYPE
		SYNTAX			INTEGER  { low ( 0 ) , medium ( 1 ), high ( 2 ) }
		MAX-ACCESS		read-only
		STATUS			current
		DESCRIPTION		"This parameter gives the old status of the alert"
		::=  {  bindingVariables  13  }

	recordedTime	OBJECT-TYPE
		SYNTAX			DisplayString
		MAX-ACCESS		read-only
		STATUS			current
		DESCRIPTION		"This parameter gives the time when the event was recorded"
		::=  {  bindingVariables  14  }

	downObjects		OBJECT-TYPE
		SYNTAX			DisplayString
		MAX-ACCESS		read-only
		STATUS			current
		DESCRIPTION		"This parameter lists the servers/agents that are in a down state"
		::=  {  bindingVariables  15  }

	packageUpdates		OBJECT-TYPE
		SYNTAX			DisplayString
		MAX-ACCESS		read-only
		STATUS			current
		DESCRIPTION		"This parameter list the packages which needs to upgrade and also list the obsolete"
		::=  {  bindingVariables  16  }

	streamingReplicationLagBytes    OBJECT-TYPE
                SYNTAX                  DisplayString
                MAX-ACCESS              read-only
                STATUS                  current
                DESCRIPTION             "This parameter list the slaves which lags behind the master by write/flush/replay location in streaming replication"
                ::=  {  bindingVariables  17  }

	standbyServerDetails    OBJECT-TYPE
                SYNTAX                  DisplayString
                MAX-ACCESS              read-only
                STATUS                  current
                DESCRIPTION             "This parameter displays the Standby server for which there is WAL segment/page lag in streaming replication"
                ::=  {  bindingVariables  18  }';

	/* Agent Alerts */
	mib_text = mib_text || pem.create_mib_notification_type(100, 5446);
	/* server Alerts */
	mib_text = mib_text || pem.create_mib_notification_type(200, 5447);
	/* database Alerts */
	mib_text = mib_text || pem.create_mib_notification_type(300, 5448);
	/* schema Alerts */
	mib_text = mib_text || pem.create_mib_notification_type(400, 5449);
	/* object Alerts */
	mib_text = mib_text || pem.create_mib_notification_type(500, 5450);
	mib_text = mib_text || pem.create_mib_notification_type(600, 5451);
	mib_text = mib_text || pem.create_mib_notification_type(700, 5452);
	mib_text = mib_text || pem.create_mib_notification_type(800, 5453);
	/* global Alerts */
	mib_text = mib_text || pem.create_mib_notification_type(50, 5454);

	mib_text = mib_text || E'\nEND';

	RETURN mib_text;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION pem.create_mib_notification_type(object_type integer, group_oid_type integer)
RETURNS text AS $$
DECLARE
	return_text text = '';
	tmp_rec	RECORD;
	parent_node text;
	where_clause text;
	object_prefix text;
	object_string text;
	group_text text = '';
	group_description text = '';
	is_alert_found boolean = false;
BEGIN
	CASE
	WHEN object_type = 50 THEN
		where_clause = 'WHERE object_type = 50 AND snmp_oid > 0';
		parent_node = 'globalAlerts';
		object_string = '{ alertName, thresholdValue, previousValue, value, previousStatus, status, recordedTime, downObjects }';
		object_prefix = 'gl';
		group_text = E'\n\n\tpemGlobalNotificationGroup  NOTIFICATION-GROUP
	\tNOTIFICATIONS {';
		group_description = 'This group contains the global notification types';
	WHEN object_type = 100 THEN
		where_clause = 'WHERE object_type = 100 AND snmp_oid > 0';
		parent_node = 'agentAlerts';
		object_string = '{ alertName, agentID , agentName, thresholdValue, previousValue, value, previousStatus, status, recordedTime, packageUpdates }';
		object_prefix = 'ag';
		group_text = E'\n\n\tpemAgentNotificationGroup  NOTIFICATION-GROUP
	\tNOTIFICATIONS {';
		group_description = 'This group contains the agent level notification types';
	WHEN object_type = 200 THEN
		where_clause = 'WHERE object_type = 200 AND snmp_oid > 0';
		parent_node = 'serverAlerts';
		object_string = '{ alertName, serverID , serverName, thresholdValue, previousValue, value, previousStatus, status, recordedTime, streamingReplicationLagBytes,  standbyServerDetails}';
		object_prefix = 'sr';
		group_text = E'\n\n\tpemServerNotificationGroup  NOTIFICATION-GROUP
	\tNOTIFICATIONS {';
		group_description = 'This group contains the server level notification types';
	WHEN object_type = 300 THEN
		where_clause = 'WHERE object_type = 300 AND snmp_oid > 0';
		parent_node = 'databaseAlerts';
		object_string = '{ alertName, serverID , serverName, databaseName, thresholdValue, previousValue, value, previousStatus, status, recordedTime }';
		object_prefix = 'db';
		group_text = E'\n\n\tpemDatabaseNotificationGroup  NOTIFICATION-GROUP
	\tNOTIFICATIONS {';
		group_description = 'This group contains the database level notification types';
	WHEN object_type = 400 THEN
		where_clause = 'WHERE object_type = 400 AND snmp_oid > 0';
		parent_node = 'schemaAlerts';
		object_string = '{ alertName, serverID , serverName, databaseName, schemaName, thresholdValue, previousValue, value, previousStatus, status, recordedTime }';
		object_prefix = 'sc';
		group_text = E'\n\n\tpemSchemaNotificationGroup  NOTIFICATION-GROUP
	\tNOTIFICATIONS {';
		group_description = 'This group contains the schema level notification types';
	WHEN object_type = 500 THEN
		where_clause = 'WHERE object_type = 500 AND snmp_oid > 0';
		parent_node = 'objectAlerts';
		object_string = '{ alertName, serverID , serverName, databaseName, schemaName, objectName, thresholdValue, previousValue, value, previousStatus, status, recordedTime }';
		object_prefix = 'tb';
		group_text = E'\n\n\tpemTableNotificationGroup  NOTIFICATION-GROUP
	\tNOTIFICATIONS {';
		group_description = 'This group contains the table level notification types';
	WHEN object_type = 600 THEN
		where_clause = 'WHERE object_type = 600 AND snmp_oid > 0';
		parent_node = 'objectAlerts';
		object_string = '{ alertName, serverID , serverName, databaseName, schemaName, objectName, thresholdValue, previousValue, value, previousStatus, status, recordedTime }';
		object_prefix = 'in';
		group_text = E'\n\n\tpemIndexNotificationGroup  NOTIFICATION-GROUP
	\tNOTIFICATIONS {';
		group_description = 'This group contains the index level notification types';
	WHEN object_type = 700 THEN
		where_clause = 'WHERE object_type = 700 AND snmp_oid > 0';
		parent_node = 'objectAlerts';
		object_string = '{ alertName, serverID , serverName, databaseName, schemaName, objectName, thresholdValue, previousValue, value, previousStatus, status, recordedTime }';
		object_prefix = 'se';
		group_text = E'\n\n\tpemSequenceNotificationGroup  NOTIFICATION-GROUP
	\tNOTIFICATIONS {';
		group_description = 'This group contains the sequence level notification types';
	WHEN object_type = 800 THEN
		where_clause = 'WHERE object_type = 800 AND snmp_oid > 0';
		parent_node = 'objectAlerts';
		object_string = '{ alertName, serverID , serverName, databaseName, schemaName, objectName, thresholdValue, previousValue, value, previousStatus, status, recordedTime }';
		object_prefix = 'fn';
		group_text = E'\n\n\tpemFunctionNotificationGroup  NOTIFICATION-GROUP
	\tNOTIFICATIONS {';
		group_description = 'This group contains the function level notification types';
	END CASE;

	FOR tmp_rec IN EXECUTE 'SELECT display_name, description , snmp_oid FROM pem.alert_template ' || where_clause || ' ORDER BY snmp_oid'
	LOOP
		is_alert_found = true;
		tmp_rec.display_name = lower(tmp_rec.display_name);
		tmp_rec.display_name = replace(tmp_rec.display_name, '(', '');
		tmp_rec.display_name = replace(tmp_rec.display_name, ')', '');
		tmp_rec.display_name = replace(tmp_rec.display_name, ',', '');
		tmp_rec.display_name = replace(tmp_rec.display_name, '-', '');
		tmp_rec.display_name = replace(tmp_rec.display_name, '_', '');
		tmp_rec.display_name = initcap(tmp_rec.display_name);
		tmp_rec.display_name = replace(tmp_rec.display_name, ' ', '');

		IF char_length(tmp_rec.display_name) > 62 THEN
			tmp_rec.display_name = substr(tmp_rec.display_name, 0, 62);
		END IF;

		return_text =  return_text || E'\n\n\t' || object_prefix || tmp_rec.display_name || E'   NOTIFICATION-TYPE
		OBJECTS			' || object_string || E'
		STATUS			current
		DESCRIPTION \t\t"'	||	tmp_rec.description || E'"
		::=  {  ' || parent_node || '  ' || tmp_rec.snmp_oid::text ||  '  }';

		group_text = group_text || E'\n\t\t\t' ||object_prefix || tmp_rec.display_name || E',';
	END LOOP;

	group_text = trim(trailing ',' from group_text);

	group_text = group_text || '}
	STATUS 	current
	DESCRIPTION
		"'|| group_description ||'"
	::= { postgresql ' || group_oid_type || '}';

	IF is_alert_found THEN
		RETURN group_text || return_text;
	ELSE
		RETURN return_text;
	END IF;
END;
$$ LANGUAGE plpgsql;

COMMIT TRANSACTION;
