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
'SELECT 201404152::integer;'
  LANGUAGE 'sql' IMMUTABLE;

ALTER TABLE pem.probe
	ADD COLUMN is_system_probe boolean NOT NULL DEFAULT true,
	ADD COLUMN deleted boolean NOT NULL DEFAULT false,
	ADD COLUMN deleted_time timestamptz DEFAULT NULL,
	ADD COLUMN platform text;

CREATE OR REPLACE FUNCTION pem.custom_probe_deleted() RETURNS TRIGGER AS $$
BEGIN
	IF OLD.is_system_probe THEN
		RAISE EXCEPTION 'Can not delete a pre-defined probe (%) in Postgres Enterprise Manager', OLD.id;
	END IF;
	IF NEW.deleted = true THEN
		IF OLD.deleted_time IS NOT NULL THEN
			NEW.deleted_time := OLD.deleted_time;
		ELSE
			NEW.deleted_time := now();
		END IF;
	ELSE
		NEW.deleted_time := NULL;
	END IF;

	RETURN NEW;
END
$$ LANGUAGE plpgsql;

CREATE TRIGGER pem_custom_probe_deleted BEFORE UPDATE OF deleted ON pem.probe FOR EACH ROW EXECUTE PROCEDURE pem.custom_probe_deleted();

INSERT INTO pem.config (param, value, unit, datatype) VALUES ('deleted_probes_retention_time', '7', 'days', 'integer');

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
	AND p.internal_name NOT IN( SELECT UNNEST(CASE WHEN s.is_remote_monitoring THEN ARRAY['pg_hba_conf', 'data_log_file_analysis'] ELSE ARRAY[''] END))
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


CREATE OR REPLACE FUNCTION pem.purge_deleted_probes()
RETURNS void AS $BODY$
DECLARE
	curs_del_probes CURSOR FOR
		SELECT pr.id, pr.internal_name, pr.discard_history,
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
		END IF;
	END LOOP;

	DELETE FROM pem.probe WHERE deleted AND NOT is_system_probe;
END;
$BODY$ LANGUAGE plpgsql SECURITY DEFINER;


-- This function will be called by server installer at the time of installation. This function add the PEM Server to the directory,
-- bind it to the default agent, and create the job for data purging.
--
-- NOTE: Even though - we do have new startup function to save the agen-server binding password.
--       We will have to keep this function to support the pemagent-2.0.0.

CREATE OR REPLACE FUNCTION pem.startup(server_desc text, server_name text, server_host text, server_port int, server_database text, server_ssl int,
					user_name text, ser_group text, agentid int, agent_database text)
  RETURNS void AS
$BODY$
DECLARE
	job_id integer;
	serverid integer;
	active_state boolean;
	name text;
BEGIN
    -- Default serverid
    serverid := 1;

    -- Check the server entry is already exist.
    SELECT active INTO active_state FROM pem.server WHERE id = serverid;

    -- if entry not found or server with id serverid is already exist and server is active then add new server.
    IF (NOT FOUND) OR (active_state = 't') THEN
        -- Create entry of PEM server in pem.server table.
        INSERT INTO pem.server (description, server, port, database, ssl) VALUES (server_desc, server_name, server_port, server_database, server_ssl) RETURNING id INTO serverid;

        -- Set the options of the PEM server
        INSERT INTO pem.server_option (server_id, pem_user, username, server_group) VALUES (serverid, user_name, user_name, ser_group);
    ELSE
        UPDATE pem.server SET description = server_desc, server = server_name, port = server_port, database = server_database, ssl = server_ssl, active = 't' WHERE id = serverid;

        UPDATE pem.server_option SET pem_user = user_name, username = user_name, server_group = ser_group WHERE server_id = serverid;
    END IF;

    -- Create Agent Server Binding
    INSERT INTO pem.agent_server_binding (agent_id, server_id, server, port, username, database) VALUES (agentid, serverid, server_host, server_port, user_name, agent_database);


    -- Check if the job already exists.
    SELECT jobid INTO job_id FROM pem.job WHERE jobname = 'Database cleanup' AND agent_id = agentid;

    IF (NOT FOUND) THEN
        -- Create data purging job.
        INSERT INTO pem.job(jobname, jobdesc, agent_id) VALUES('Database cleanup', 'This job runs periodically to purge old data from the database.', agentid) RETURNING jobid INTO job_id;
    END IF;

    -- Check if the job step already exists.
    SELECT jstname INTO name FROM pem.jobstep WHERE jstname = 'Database cleanup' AND jstjobid = job_id;

    IF (NOT FOUND) THEN
        -- Create data purging step.
        INSERT INTO pem.jobstep(jstjobid, jstname, jstdesc, jstkind, jstcode, server_id, database_name) VALUES (job_id, 'Database cleanup','This job step runs periodically to purge old data from the database.', 's',
        'SELECT pem.purge_data()', serverid, 'pem');
    END IF;

    -- Check if the job schedule already exists.
    SELECT jscname INTO name FROM pem.schedule WHERE jscname = 'Database cleanup' AND jscjobid = job_id;

    IF (NOT FOUND) THEN
        -- Create data purging schedule.
        INSERT INTO pem.schedule(jscjobid, jscname, jscdesc, jscminutes, jschours, jscweekdays, jscmonthdays, jscmonths) VALUES(job_id, 'Database cleanup', 'This job schedule runs periodically to purge old data from the database.', '{t,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f}', '{f,f,f,t,f,f,f,t,f,f,f,f,f,f,f,f,f,f,f,t,f,f,f,t}','{t,t,t,t,t,t,t}', '{t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t}', '{t,t,t,t,t,t,t,t,t,t,t,t}');
    END IF;

    -- Check if the job already exists.
    SELECT jobid INTO job_id FROM pem.job WHERE jobname = 'Audit log table cleanup' AND agent_id = agentid;

    IF (NOT FOUND) THEN
        -- Create data purging job.
	INSERT INTO pem.job(jobname, jobdesc, agent_id) VALUES('Audit log table cleanup', 'This job runs periodically to purge old data from the audit log table.', agentid) RETURNING jobid INTO job_id;
    END IF;

    -- Check if the job step already exists.
    SELECT jstname INTO name FROM pem.jobstep WHERE jstname = 'Audit log table cleanup' AND jstjobid = job_id;

    IF (NOT FOUND) THEN
        -- Create data purging step.
	INSERT INTO pem.jobstep(jstjobid, jstname, jstdesc, jstkind, jstcode, server_id, database_name) VALUES (job_id, 'Audit log table cleanup','This job step runs periodically to purge old data from the audit log table.', 's',
        'SELECT pem.purge_audit_log()', serverid, 'pem');
    END IF;

    -- Check if the job schedule already exists.
    SELECT jscname INTO name FROM pem.schedule WHERE jscname = 'Audit log table cleanup' AND jscjobid = job_id;

    IF (NOT FOUND) THEN
        -- Create data purging schedule.
        INSERT INTO pem.schedule(jscjobid, jscname, jscdesc, jscminutes, jschours, jscweekdays, jscmonthdays, jscmonths) VALUES(job_id, 'Audit log table cleanup', 'This job schedule runs periodically to purge old data from the audit log table.', '{t,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f}', '{t,f,f,f,f,f,f,f,f,f,f,f,t,f,f,f,f,f,f,f,f,f,f,f}','{t,t,t,t,t,t,t}', '{t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t}', '{t,t,t,t,t,t,t,t,t,t,t,t}');
    END IF;

    -- Check if the job already exists.
    SELECT jobid INTO job_id FROM pem.job WHERE jobname = 'Server log table cleanup' AND agent_id = agentid;

    IF (NOT FOUND) THEN
        -- Create data purging job.
        INSERT INTO pem.job(jobname, jobdesc, agent_id) VALUES('Server log table cleanup', 'This job runs periodically to purge old data from the server log table.', agentid) RETURNING jobid INTO job_id;
    END IF;

    -- Check if the job step already exists.
    SELECT jstname INTO name FROM pem.jobstep WHERE jstname = 'Server log table cleanup' AND jstjobid = job_id;

    IF (NOT FOUND) THEN
        -- Create data purging step.
        INSERT INTO pem.jobstep(jstjobid, jstname, jstdesc, jstkind, jstcode, server_id, database_name) VALUES (job_id, 'Server log table cleanup','This job step runs periodically to purge old data from the server log table.', 's',
        'SELECT pem.purge_server_log()', serverid, 'pem');
    END IF;

    -- Check if the job schedule already exists.
    SELECT jscname INTO name FROM pem.schedule WHERE jscname = 'Server log table cleanup' AND jscjobid = job_id;

    IF (NOT FOUND) THEN
        -- Create data purging schedule.
        INSERT INTO pem.schedule(jscjobid, jscname, jscdesc, jscminutes, jschours, jscweekdays, jscmonthdays, jscmonths) VALUES(job_id, 'Server log table cleanup', 'This job schedule runs periodically to purge old data from the server log table.', '{t,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f}', '{f,t,f,f,f,f,f,f,f,f,f,f,f,t,f,f,f,f,f,f,f,f,f,f}','{t,t,t,t,t,t,t}', '{t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t}', '{t,t,t,t,t,t,t,t,t,t,t,t}');
    END IF;

    -- Check if the job already exists.
    SELECT jobid INTO job_id FROM pem.job WHERE jobname = 'Probe log table cleanup' AND agent_id = agentid;

    IF (NOT FOUND) THEN
        -- Create data purging job.
        INSERT INTO pem.job(jobname, jobdesc, agent_id) VALUES('Probe log table cleanup', 'This job runs periodically to purge old data from the probe log table.', agentid) RETURNING jobid INTO job_id;
    END IF;

    -- Check if the job step already exists.
    SELECT jstname INTO name FROM pem.jobstep WHERE jstname = 'Probe log table cleanup' AND jstjobid = job_id;

    IF (NOT FOUND) THEN
        -- Create data purging step.
        INSERT INTO pem.jobstep(jstjobid, jstname, jstdesc, jstkind, jstcode, server_id, database_name) VALUES (job_id, 'Probe log table cleanup','This job step runs periodically to purge old data from the probe log table.', 's',
        'SELECT pem.purge_probe_log()', serverid, 'pem');
    END IF;

    -- Check if the job schedule already exists.
    SELECT jscname INTO name FROM pem.schedule WHERE jscname = 'Probe log table cleanup' AND jscjobid = job_id;

    IF (NOT FOUND) THEN
        -- Create data purging schedule.
        INSERT INTO pem.schedule(jscjobid, jscname, jscdesc, jscminutes, jschours, jscweekdays, jscmonthdays, jscmonths) VALUES(job_id, 'Probe log table cleanup', 'This job schedule runs periodically to purge old data from the probe log table.', '{t,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f}', '{f,f,t,f,f,f,f,f,f,f,f,f,f,f,t,f,f,f,f,f,f,f,f,f}','{t,t,t,t,t,t,t}', '{t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t}', '{t,t,t,t,t,t,t,t,t,t,t,t}');
    END IF;

    -- Check if the job already exists.
    SELECT jobid INTO job_id FROM pem.job WHERE jobname = 'SMTP spool table cleanup' AND agent_id = agentid;

    IF (NOT FOUND) THEN
        -- Create data purging job.
        INSERT INTO pem.job(jobname, jobdesc, agent_id) VALUES('SMTP spool table cleanup', 'This job runs periodically to purge old data from the smtp spool table.', agentid) RETURNING jobid INTO job_id;
    END IF;

    -- Check if the job step already exists.
    SELECT jstname INTO name FROM pem.jobstep WHERE jstname = 'SMTP spool table cleanup' AND jstjobid = job_id;

    IF (NOT FOUND) THEN
        -- Create data purging step.
        INSERT INTO pem.jobstep(jstjobid, jstname, jstdesc, jstkind, jstcode, server_id, database_name) VALUES (job_id, 'SMTP spool table cleanup','This job step runs periodically to purge old data from the smtp spool table.', 's',
        'SELECT pem.purge_smtp_spool()', serverid, 'pem');
    END IF;

    -- Check if the job schedule already exists.
    SELECT jscname INTO name FROM pem.schedule WHERE jscname = 'SMTP spool table cleanup' AND jscjobid = job_id;

    IF (NOT FOUND) THEN
        -- Create data purging schedule.
        INSERT INTO pem.schedule(jscjobid, jscname, jscdesc, jscminutes, jschours, jscweekdays, jscmonthdays, jscmonths) VALUES(job_id, 'SMTP spool table cleanup', 'This job schedule runs periodically to purge old data from the smtp spool table.', '{t,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f}', '{f,f,f,t,f,f,f,f,f,f,f,f,f,f,f,t,f,f,f,f,f,f,f,f}','{t,t,t,t,t,t,t}', '{t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t}', '{t,t,t,t,t,t,t,t,t,t,t,t}');
    END IF;

    -- Check if the job already exists.
    SELECT jobid INTO job_id FROM pem.job WHERE jobname = 'SNMP spool table cleanup' AND agent_id = agentid;

    IF (NOT FOUND) THEN
        -- Create data purging job.
        INSERT INTO pem.job(jobname, jobdesc, agent_id) VALUES('SNMP spool table cleanup', 'This job runs periodically to purge old data from the snmp spool table.', agentid) RETURNING jobid INTO job_id;
    END IF;

    -- Check if the job step already exists.
    SELECT jstname INTO name FROM pem.jobstep WHERE jstname = 'SNMP spool table cleanup' AND jstjobid = job_id;

    IF (NOT FOUND) THEN
        -- Create data purging step.
        INSERT INTO pem.jobstep(jstjobid, jstname, jstdesc, jstkind, jstcode, server_id, database_name) VALUES (job_id, 'SNMP spool table cleanup','This job step runs periodically to purge old data from the snmp spool table.', 's',
        'SELECT pem.purge_snmp_spool()', serverid, 'pem');
    END IF;

    -- Check if the job schedule already exists.
    SELECT jscname INTO name FROM pem.schedule WHERE jscname = 'SNMP spool table cleanup' AND jscjobid = job_id;

    IF (NOT FOUND) THEN
        -- Create data purging schedule.
        INSERT INTO pem.schedule(jscjobid, jscname, jscdesc, jscminutes, jschours, jscweekdays, jscmonthdays, jscmonths) VALUES(job_id, 'SNMP spool table cleanup', 'This job schedule runs periodically to purge old data from the snmp spool table.', '{t,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f}', '{f,f,f,f,t,f,f,f,f,f,f,f,f,f,f,f,t,f,f,f,f,f,f,f}','{t,t,t,t,t,t,t}', '{t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t}', '{t,t,t,t,t,t,t,t,t,t,t,t}');
    END IF;

    -- Check if the job already exists.
    SELECT jobid INTO job_id FROM pem.job WHERE jobname = 'Alert history table cleanup' AND agent_id = agentid;

    IF (NOT FOUND) THEN
        -- Create data purging job.
        INSERT INTO pem.job(jobname, jobdesc, agent_id) VALUES('Alert history table cleanup', 'This job runs periodically to purge old data from the alert history table.', agentid) RETURNING jobid INTO job_id;
    END IF;

    -- Check if the job step already exists.
    SELECT jstname INTO name FROM pem.jobstep WHERE jstname = 'Alert history table cleanup' AND jstjobid = job_id;

    IF (NOT FOUND) THEN
        -- Create data purging step.
        INSERT INTO pem.jobstep(jstjobid, jstname, jstdesc, jstkind, jstcode, server_id, database_name) VALUES (job_id, 'Alert history table cleanup','This job step runs periodically to purge old data from the alert history table.', 's',
        'SELECT pem.purge_alert_history()', serverid, 'pem');
    END IF;

    -- Check if the job schedule already exists.
    SELECT jscname INTO name FROM pem.schedule WHERE jscname = 'Alert history table cleanup' AND jscjobid = job_id;

    IF (NOT FOUND) THEN
        -- Create data purging schedule.
        INSERT INTO pem.schedule(jscjobid, jscname, jscdesc, jscminutes, jschours, jscweekdays, jscmonthdays, jscmonths) VALUES(job_id, 'Alert history table cleanup', 'This job schedule runs periodically to purge old data from the alert history table.', '{t,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f}', '{f,f,f,f,f,t,f,f,f,f,f,f,f,f,f,f,f,t,f,f,f,f,f,f}','{t,t,t,t,t,t,t}', '{t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t}', '{t,t,t,t,t,t,t,t,t,t,t,t}');
    END IF;

    -- Check if the job already exists.
    SELECT jobid INTO job_id FROM pem.job WHERE jobname = 'Job log table cleanup' AND agent_id = agentid;

    IF (NOT FOUND) THEN
        -- Create data purging job.
        INSERT INTO pem.job(jobname, jobdesc, agent_id) VALUES('Job log table cleanup', 'This job runs periodically to purge old data from the job log table.', agentid) RETURNING jobid INTO job_id;
    END IF;

    -- Check if the job step already exists.
    SELECT jstname INTO name FROM pem.jobstep WHERE jstname = 'Job log table cleanup' AND jstjobid = job_id;

    IF (NOT FOUND) THEN
        -- Create data purging step.
        INSERT INTO pem.jobstep(jstjobid, jstname, jstdesc, jstkind, jstcode, server_id, database_name) VALUES (job_id, 'Job log table cleanup','This job step runs periodically to purge old data from the job log table.', 's',
        'SELECT pem.purge_job_log()', serverid, 'pem');
    END IF;

    -- Check if the job schedule already exists.
    SELECT jscname INTO name FROM pem.schedule WHERE jscname = 'Job log table cleanup' AND jscjobid = job_id;

    IF (NOT FOUND) THEN
        -- Create data purging schedule.
        INSERT INTO pem.schedule(jscjobid, jscname, jscdesc, jscminutes, jschours, jscweekdays, jscmonthdays, jscmonths) VALUES(job_id, 'Job log table cleanup', 'This job schedule runs periodically to purge old data from the job log table.', '{t,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f}', '{f,f,f,f,f,f,t,f,f,f,f,f,f,f,f,f,f,f,t,f,f,f,f,f}','{t,t,t,t,t,t,t}', '{t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t}', '{t,t,t,t,t,t,t,t,t,t,t,t}');
    END IF;

    -- Check if the job already exists (for purging deleted charts)
    SELECT jobid INTO job_id FROM pem.job WHERE jobname = 'Job purge the deleted charts' AND agent_id = agentid;

    IF (NOT FOUND) THEN
        -- Create data purging job.
        INSERT INTO pem.job(jobname, jobdesc, agent_id) VALUES('Job purge the deleted charts', 'This job runs periodically to purge the deleted charts.', agentid) RETURNING jobid INTO job_id;
    END IF;

    -- Check if the job step already exists.
    SELECT jstname INTO name FROM pem.jobstep WHERE jstname = 'Job purge the deleted charts' AND jstjobid = job_id;

    IF (NOT FOUND) THEN
        -- Create data purging step.
        INSERT INTO pem.jobstep(jstjobid, jstname, jstdesc, jstkind, jstcode, server_id, database_name) VALUES (job_id, 'Job purge the deleted charts','This job step runs periodically to purge the deleted charts (we do not clean them up immediately).', 's',
        'SELECT pem.purge_deleted_charts()', serverid, 'pem');
    END IF;

    -- Check if the job schedule already exists.
    SELECT jscname INTO name FROM pem.schedule WHERE jscname = 'Job purge the deleted charts' AND jscjobid = job_id;

    IF (NOT FOUND) THEN
        -- Create data purging schedule.
        INSERT INTO pem.schedule(jscjobid, jscname, jscdesc, jscminutes, jschours, jscweekdays, jscmonthdays, jscmonths) VALUES(job_id, 'Job purge the deleted charts', 'This job schedule runs periodically to purge the deletecd charts.', '{t,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f}', '{f,f,t,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f}','{t,t,t,t,t,t,t}', '{t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t}', '{t,t,t,t,t,t,t,t,t,t,t,t}');
    END IF;

    -- Check if the job already exists.
    SELECT jobid INTO job_id FROM pem.job WHERE jobname = 'Purge deleted custom probes' AND agent_id = agentid;

    IF (NOT FOUND) THEN
        -- Create data purging job.
        INSERT INTO pem.job(jobname, jobdesc, agent_id) VALUES('Purge deleted custom probes', 'This job runs periodically to purge deleted custom probes and its data.', agentid) RETURNING jobid INTO job_id;
    END IF;

    -- Check if the job step already exists.
    SELECT jstname INTO name FROM pem.jobstep WHERE jstname = 'Purge deleted custom probes' AND jstjobid = job_id;

    IF (NOT FOUND) THEN
        -- Create data purging step.
        INSERT INTO pem.jobstep(jstjobid, jstname, jstdesc, jstkind, jstcode, server_id, database_name) VALUES (job_id, 'Purge deleted custom probes','This job runs periodically to purge deleted custom probes and its data.', 's',
        'SELECT pem.purge_deleted_probes()', serverid, 'pem');
    END IF;

    -- Check if the job schedule already exists.
    SELECT jscname INTO name FROM pem.schedule WHERE jscname = 'Purge deleted custom probes' AND jscjobid = job_id;

    IF (NOT FOUND) THEN
    -- Create data purging schedule.
    INSERT INTO pem.schedule(jscjobid, jscname, jscdesc, jscminutes, jschours, jscweekdays, jscmonthdays, jscmonths) VALUES(job_id, 'Purge deleted custom probes', 'This job runs periodically to purge deleted custom probes and its data.', '{t,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f}', '{f,t,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f}','{t,t,t,t,t,t,t}', '{t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t}', '{t,t,t,t,t,t,t,t,t,t,t,t}');
    END IF;
END;
$BODY$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION pem.startup(server_desc text, server_name text, server_host text, server_port int, server_database text, server_ssl int,
					user_name text, passwd text, ser_group text, agentid int, agent_database text)
  RETURNS void AS
$BODY$
DECLARE
	job_id integer;
	serverid integer;
	active_state boolean;
	name text;
BEGIN
    -- Default serverid
    serverid := 1;

    -- Check the server entry is already exist.
    SELECT active INTO active_state FROM pem.server WHERE id = serverid;

    -- if entry not found or server with id serverid is already exist and server is active then add new server.
    IF (NOT FOUND) OR (active_state = 't') THEN
        -- Create entry of PEM server in pem.server table.
        INSERT INTO pem.server (description, server, port, database, ssl) VALUES (server_desc, server_name, server_port, server_database, server_ssl) RETURNING id INTO serverid;

        -- Set the options of the PEM server
        INSERT INTO pem.server_option (server_id, pem_user, username, server_group) VALUES (serverid, user_name, user_name, ser_group);
    ELSE
        UPDATE pem.server SET description = server_desc, server = server_name, port = server_port, database = server_database, ssl = server_ssl, active = 't' WHERE id = serverid;

        UPDATE pem.server_option SET pem_user = user_name, username = user_name, server_group = ser_group WHERE server_id = serverid;
    END IF;

    -- Create Agent Server Binding
    INSERT INTO pem.agent_server_binding (agent_id, server_id, server, port, username, database, password) VALUES (agentid, serverid, server_host, server_port, user_name, agent_database, passwd);


    -- Check if the job already exists.
    SELECT jobid INTO job_id FROM pem.job WHERE jobname = 'Database cleanup' AND agent_id = agentid;

    IF (NOT FOUND) THEN
        -- Create data purging job.
        INSERT INTO pem.job(jobname, jobdesc, agent_id) VALUES('Database cleanup', 'This job runs periodically to purge old data from the database.', agentid) RETURNING jobid INTO job_id;
    END IF;

    -- Check if the job step already exists.
    SELECT jstname INTO name FROM pem.jobstep WHERE jstname = 'Database cleanup' AND jstjobid = job_id;

    IF (NOT FOUND) THEN
        -- Create data purging step.
        INSERT INTO pem.jobstep(jstjobid, jstname, jstdesc, jstkind, jstcode, server_id, database_name) VALUES (job_id, 'Database cleanup','This job step runs periodically to purge old data from the database.', 's',
        'SELECT pem.purge_data()', serverid, 'pem');
    END IF;

    -- Check if the job schedule already exists.
    SELECT jscname INTO name FROM pem.schedule WHERE jscname = 'Database cleanup' AND jscjobid = job_id;

    IF (NOT FOUND) THEN
        -- Create data purging schedule.
        INSERT INTO pem.schedule(jscjobid, jscname, jscdesc, jscminutes, jschours, jscweekdays, jscmonthdays, jscmonths) VALUES(job_id, 'Database cleanup', 'This job schedule runs periodically to purge old data from the database.', '{t,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f}', '{f,f,f,t,f,f,f,t,f,f,f,f,f,f,f,f,f,f,f,t,f,f,f,t}','{t,t,t,t,t,t,t}', '{t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t}', '{t,t,t,t,t,t,t,t,t,t,t,t}');
    END IF;

    -- Check if the job already exists.
    SELECT jobid INTO job_id FROM pem.job WHERE jobname = 'Audit log table cleanup' AND agent_id = agentid;

    IF (NOT FOUND) THEN
        -- Create data purging job.
	INSERT INTO pem.job(jobname, jobdesc, agent_id) VALUES('Audit log table cleanup', 'This job runs periodically to purge old data from the audit log table.', agentid) RETURNING jobid INTO job_id;
    END IF;

    -- Check if the job step already exists.
    SELECT jstname INTO name FROM pem.jobstep WHERE jstname = 'Audit log table cleanup' AND jstjobid = job_id;

    IF (NOT FOUND) THEN
        -- Create data purging step.
	INSERT INTO pem.jobstep(jstjobid, jstname, jstdesc, jstkind, jstcode, server_id, database_name) VALUES (job_id, 'Audit log table cleanup','This job step runs periodically to purge old data from the audit log table.', 's',
        'SELECT pem.purge_audit_log()', serverid, 'pem');
    END IF;

    -- Check if the job schedule already exists.
    SELECT jscname INTO name FROM pem.schedule WHERE jscname = 'Audit log table cleanup' AND jscjobid = job_id;

    IF (NOT FOUND) THEN
        -- Create data purging schedule.
        INSERT INTO pem.schedule(jscjobid, jscname, jscdesc, jscminutes, jschours, jscweekdays, jscmonthdays, jscmonths) VALUES(job_id, 'Audit log table cleanup', 'This job schedule runs periodically to purge old data from the audit log table.', '{t,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f}', '{t,f,f,f,f,f,f,f,f,f,f,f,t,f,f,f,f,f,f,f,f,f,f,f}','{t,t,t,t,t,t,t}', '{t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t}', '{t,t,t,t,t,t,t,t,t,t,t,t}');
    END IF;

    -- Check if the job already exists.
    SELECT jobid INTO job_id FROM pem.job WHERE jobname = 'Server log table cleanup' AND agent_id = agentid;

    IF (NOT FOUND) THEN
        -- Create data purging job.
        INSERT INTO pem.job(jobname, jobdesc, agent_id) VALUES('Server log table cleanup', 'This job runs periodically to purge old data from the server log table.', agentid) RETURNING jobid INTO job_id;
    END IF;

    -- Check if the job step already exists.
    SELECT jstname INTO name FROM pem.jobstep WHERE jstname = 'Server log table cleanup' AND jstjobid = job_id;

    IF (NOT FOUND) THEN
        -- Create data purging step.
        INSERT INTO pem.jobstep(jstjobid, jstname, jstdesc, jstkind, jstcode, server_id, database_name) VALUES (job_id, 'Server log table cleanup','This job step runs periodically to purge old data from the server log table.', 's',
        'SELECT pem.purge_server_log()', serverid, 'pem');
    END IF;

    -- Check if the job schedule already exists.
    SELECT jscname INTO name FROM pem.schedule WHERE jscname = 'Server log table cleanup' AND jscjobid = job_id;

    IF (NOT FOUND) THEN
        -- Create data purging schedule.
        INSERT INTO pem.schedule(jscjobid, jscname, jscdesc, jscminutes, jschours, jscweekdays, jscmonthdays, jscmonths) VALUES(job_id, 'Server log table cleanup', 'This job schedule runs periodically to purge old data from the server log table.', '{t,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f}', '{f,t,f,f,f,f,f,f,f,f,f,f,f,t,f,f,f,f,f,f,f,f,f,f}','{t,t,t,t,t,t,t}', '{t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t}', '{t,t,t,t,t,t,t,t,t,t,t,t}');
    END IF;

    -- Check if the job already exists.
    SELECT jobid INTO job_id FROM pem.job WHERE jobname = 'Probe log table cleanup' AND agent_id = agentid;

    IF (NOT FOUND) THEN
        -- Create data purging job.
        INSERT INTO pem.job(jobname, jobdesc, agent_id) VALUES('Probe log table cleanup', 'This job runs periodically to purge old data from the probe log table.', agentid) RETURNING jobid INTO job_id;
    END IF;

    -- Check the job step already exist.
    SELECT jstname INTO name FROM pem.jobstep WHERE jstname = 'Probe log table cleanup' AND jstjobid = job_id;

    IF (NOT FOUND) THEN
        -- Create data purging step.
        INSERT INTO pem.jobstep(jstjobid, jstname, jstdesc, jstkind, jstcode, server_id, database_name) VALUES (job_id, 'Probe log table cleanup','This job step runs periodically to purge old data from the probe log table.', 's',
        'SELECT pem.purge_probe_log()', serverid, 'pem');
    END IF;

    -- Check if the job schedule already exists.
    SELECT jscname INTO name FROM pem.schedule WHERE jscname = 'Probe log table cleanup' AND jscjobid = job_id;

    IF (NOT FOUND) THEN
        -- Create data purging schedule.
        INSERT INTO pem.schedule(jscjobid, jscname, jscdesc, jscminutes, jschours, jscweekdays, jscmonthdays, jscmonths) VALUES(job_id, 'Probe log table cleanup', 'This job schedule runs periodically to purge old data from the probe log table.', '{t,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f}', '{f,f,t,f,f,f,f,f,f,f,f,f,f,f,t,f,f,f,f,f,f,f,f,f}','{t,t,t,t,t,t,t}', '{t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t}', '{t,t,t,t,t,t,t,t,t,t,t,t}');
    END IF;

    -- Check if the job already exists.
    SELECT jobid INTO job_id FROM pem.job WHERE jobname = 'SMTP spool table cleanup' AND agent_id = agentid;

    IF (NOT FOUND) THEN
        -- Create data purging job.
        INSERT INTO pem.job(jobname, jobdesc, agent_id) VALUES('SMTP spool table cleanup', 'This job runs periodically to purge old data from the smtp spool table.', agentid) RETURNING jobid INTO job_id;
    END IF;

    -- Check if the job step already exists.
    SELECT jstname INTO name FROM pem.jobstep WHERE jstname = 'SMTP spool table cleanup' AND jstjobid = job_id;

    IF (NOT FOUND) THEN
        -- Create data purging step.
        INSERT INTO pem.jobstep(jstjobid, jstname, jstdesc, jstkind, jstcode, server_id, database_name) VALUES (job_id, 'SMTP spool table cleanup','This job step runs periodically to purge old data from the smtp spool table.', 's',
        'SELECT pem.purge_smtp_spool()', serverid, 'pem');
    END IF;

    -- Check if the job schedule already exists.
    SELECT jscname INTO name FROM pem.schedule WHERE jscname = 'SMTP spool table cleanup' AND jscjobid = job_id;

    IF (NOT FOUND) THEN
        -- Create data purging schedule.
        INSERT INTO pem.schedule(jscjobid, jscname, jscdesc, jscminutes, jschours, jscweekdays, jscmonthdays, jscmonths) VALUES(job_id, 'SMTP spool table cleanup', 'This job schedule runs periodically to purge old data from the smtp spool table.', '{t,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f}', '{f,f,f,t,f,f,f,f,f,f,f,f,f,f,f,t,f,f,f,f,f,f,f,f}','{t,t,t,t,t,t,t}', '{t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t}', '{t,t,t,t,t,t,t,t,t,t,t,t}');
    END IF;

    -- Check if the job already exists.
    SELECT jobid INTO job_id FROM pem.job WHERE jobname = 'SNMP spool table cleanup' AND agent_id = agentid;

    IF (NOT FOUND) THEN
        -- Create data purging job.
        INSERT INTO pem.job(jobname, jobdesc, agent_id) VALUES('SNMP spool table cleanup', 'This job runs periodically to purge old data from the snmp spool table.', agentid) RETURNING jobid INTO job_id;
    END IF;

    -- Check if the job step already exists.
    SELECT jstname INTO name FROM pem.jobstep WHERE jstname = 'SNMP spool table cleanup' AND jstjobid = job_id;

    IF (NOT FOUND) THEN
        -- Create data purging step.
        INSERT INTO pem.jobstep(jstjobid, jstname, jstdesc, jstkind, jstcode, server_id, database_name) VALUES (job_id, 'SNMP spool table cleanup','This job step runs periodically to purge old data from the snmp spool table.', 's',
        'SELECT pem.purge_snmp_spool()', serverid, 'pem');
    END IF;

    -- Check if the job schedule already exists.
    SELECT jscname INTO name FROM pem.schedule WHERE jscname = 'SNMP spool table cleanup' AND jscjobid = job_id;

    IF (NOT FOUND) THEN
        -- Create data purging schedule.
        INSERT INTO pem.schedule(jscjobid, jscname, jscdesc, jscminutes, jschours, jscweekdays, jscmonthdays, jscmonths) VALUES(job_id, 'SNMP spool table cleanup', 'This job schedule runs periodically to purge old data from the snmp spool table.', '{t,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f}', '{f,f,f,f,t,f,f,f,f,f,f,f,f,f,f,f,t,f,f,f,f,f,f,f}','{t,t,t,t,t,t,t}', '{t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t}', '{t,t,t,t,t,t,t,t,t,t,t,t}');
    END IF;

    -- Check if the job already exists.
    SELECT jobid INTO job_id FROM pem.job WHERE jobname = 'Alert history table cleanup' AND agent_id = agentid;

    IF (NOT FOUND) THEN
        -- Create data purging job.
        INSERT INTO pem.job(jobname, jobdesc, agent_id) VALUES('Alert history table cleanup', 'This job runs periodically to purge old data from the alert history table.', agentid) RETURNING jobid INTO job_id;
    END IF;

    -- Check if the job step already exists.
    SELECT jstname INTO name FROM pem.jobstep WHERE jstname = 'Alert history table cleanup' AND jstjobid = job_id;

    IF (NOT FOUND) THEN
        -- Create data purging step.
        INSERT INTO pem.jobstep(jstjobid, jstname, jstdesc, jstkind, jstcode, server_id, database_name) VALUES (job_id, 'Alert history table cleanup','This job step runs periodically to purge old data from the alert history table.', 's',
        'SELECT pem.purge_alert_history()', serverid, 'pem');
    END IF;

    -- Check if the job schedule already exists.
    SELECT jscname INTO name FROM pem.schedule WHERE jscname = 'Alert history table cleanup' AND jscjobid = job_id;

    IF (NOT FOUND) THEN
        -- Create data purging schedule.
        INSERT INTO pem.schedule(jscjobid, jscname, jscdesc, jscminutes, jschours, jscweekdays, jscmonthdays, jscmonths) VALUES(job_id, 'Alert history table cleanup', 'This job schedule runs periodically to purge old data from the alert history table.', '{t,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f}', '{f,f,f,f,f,t,f,f,f,f,f,f,f,f,f,f,f,t,f,f,f,f,f,f}','{t,t,t,t,t,t,t}', '{t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t}', '{t,t,t,t,t,t,t,t,t,t,t,t}');
    END IF;

    -- Check if the job already exists.
    SELECT jobid INTO job_id FROM pem.job WHERE jobname = 'Job log table cleanup' AND agent_id = agentid;

    IF (NOT FOUND) THEN
        -- Create data purging job.
        INSERT INTO pem.job(jobname, jobdesc, agent_id) VALUES('Job log table cleanup', 'This job runs periodically to purge old data from the job log table.', agentid) RETURNING jobid INTO job_id;
    END IF;

    -- Check if the job step already exists.
    SELECT jstname INTO name FROM pem.jobstep WHERE jstname = 'Job log table cleanup' AND jstjobid = job_id;

    IF (NOT FOUND) THEN
        -- Create data purging step.
        INSERT INTO pem.jobstep(jstjobid, jstname, jstdesc, jstkind, jstcode, server_id, database_name) VALUES (job_id, 'Job log table cleanup','This job step runs periodically to purge old data from the job log table.', 's',
        'SELECT pem.purge_job_log()', serverid, 'pem');
    END IF;

    -- Check if the job schedule already exists.
    SELECT jscname INTO name FROM pem.schedule WHERE jscname = 'Job log table cleanup' AND jscjobid = job_id;

    IF (NOT FOUND) THEN
        -- Create data purging schedule.
        INSERT INTO pem.schedule(jscjobid, jscname, jscdesc, jscminutes, jschours, jscweekdays, jscmonthdays, jscmonths) VALUES(job_id, 'Job log table cleanup', 'This job schedule runs periodically to purge old data from the job log table.', '{t,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f}', '{f,f,f,f,f,f,t,f,f,f,f,f,f,f,f,f,f,f,t,f,f,f,f,f}','{t,t,t,t,t,t,t}', '{t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t}', '{t,t,t,t,t,t,t,t,t,t,t,t}');
    END IF;

    -- Check if the job already exists (for purging deleted charts)
    SELECT jobid INTO job_id FROM pem.job WHERE jobname = 'Job purge the deleted charts' AND agent_id = agentid;

    IF (NOT FOUND) THEN
        -- Create data purging job.
        INSERT INTO pem.job(jobname, jobdesc, agent_id) VALUES('Job purge the deleted charts', 'This job runs periodically to purge the deleted charts.', agentid) RETURNING jobid INTO job_id;
    END IF;

    -- Check if the job step already exists.
    SELECT jstname INTO name FROM pem.jobstep WHERE jstname = 'Job purge the deleted charts' AND jstjobid = job_id;

    IF (NOT FOUND) THEN
        -- Create data purging step.
        INSERT INTO pem.jobstep(jstjobid, jstname, jstdesc, jstkind, jstcode, server_id, database_name) VALUES (job_id, 'Job purge the deleted charts','This job step runs periodically to purge the deleted charts (we do not clean them up immediately).', 's',
        'SELECT pem.purge_deleted_charts()', serverid, 'pem');
    END IF;

    -- Check if the job schedule already exists.
    SELECT jscname INTO name FROM pem.schedule WHERE jscname = 'Job purge the deleted charts' AND jscjobid = job_id;

    IF (NOT FOUND) THEN
        -- Create data purging schedule.
        INSERT INTO pem.schedule(jscjobid, jscname, jscdesc, jscminutes, jschours, jscweekdays, jscmonthdays, jscmonths) VALUES(job_id, 'Job purge the deleted charts', 'This job schedule runs periodically to purge the deletecd charts.', '{t,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f}', '{f,f,t,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f}','{t,t,t,t,t,t,t}', '{t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t}', '{t,t,t,t,t,t,t,t,t,t,t,t}');
    END IF;

    -- Check if the job already exists.
    SELECT jobid INTO job_id FROM pem.job WHERE jobname = 'Purge deleted custom probes' AND agent_id = agentid;

    IF (NOT FOUND) THEN
        -- Create data purging job.
        INSERT INTO pem.job(jobname, jobdesc, agent_id) VALUES('Purge deleted custom probes', 'This job runs periodically to purge deleted custom probes and its data.', agentid) RETURNING jobid INTO job_id;
    END IF;

    -- Check if the job step already exists.
    SELECT jstname INTO name FROM pem.jobstep WHERE jstname = 'Purge deleted custom probes' AND jstjobid = job_id;

    IF (NOT FOUND) THEN
        -- Create data purging step.
        INSERT INTO pem.jobstep(jstjobid, jstname, jstdesc, jstkind, jstcode, server_id, database_name) VALUES (job_id, 'Purge deleted custom probes','This job runs periodically to purge deleted custom probes and its data.', 's',
        'SELECT pem.purge_deleted_probes()', serverid, 'pem');
    END IF;

    -- Check if the job schedule already exists.
    SELECT jscname INTO name FROM pem.schedule WHERE jscname = 'Purge deleted custom probes' AND jscjobid = job_id;

    IF (NOT FOUND) THEN
    -- Create data purging schedule.
    INSERT INTO pem.schedule(jscjobid, jscname, jscdesc, jscminutes, jschours, jscweekdays, jscmonthdays, jscmonths) VALUES(job_id, 'Purge deleted custom probes', 'This job runs periodically to purge deleted custom probes and its data.', '{t,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f}', '{f,t,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f}','{t,t,t,t,t,t,t}', '{t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t}', '{t,t,t,t,t,t,t,t,t,t,t,t}');
    END IF;
END;
$BODY$ LANGUAGE plpgsql;


DO $$
DECLARE
	job_id integer;
	serverid integer;
	agentid integer;
	name text;
BEGIN
	-- Default serverid
	serverid := 1;

	-- Default agentid
	agentid := 1;

	-- Check if the job already exists.
	SELECT jobid INTO job_id FROM pem.job WHERE jobname = 'Purge deleted custom probes' AND agent_id = agentid;

	IF (NOT FOUND) THEN
		-- Create data purging job.
		INSERT INTO pem.job(jobname, jobdesc, agent_id) VALUES('Purge deleted custom probes', 'This job runs periodically to purge deleted custom probes and its data.', agentid) RETURNING jobid INTO job_id;
	END IF;

	-- Check if the job step already exists.
	SELECT jstname INTO name FROM pem.jobstep WHERE jstname = 'Purge deleted custom probes' AND jstjobid = job_id;

	IF (NOT FOUND) THEN
		-- Create data purging step.
		INSERT INTO pem.jobstep(jstjobid, jstname, jstdesc, jstkind, jstcode, server_id, database_name) VALUES (job_id, 'Purge deleted custom probes','This job runs periodically to purge deleted custom probes and its data.', 's',
		'SELECT pem.purge_deleted_probes()', serverid, 'pem');
	END IF;

	-- Check if the job schedule already exists.
	SELECT jscname INTO name FROM pem.schedule WHERE jscname = 'Purge deleted custom probes' AND jscjobid = job_id;

	IF (NOT FOUND) THEN
		-- Create data purging schedule.
		INSERT INTO pem.schedule(jscjobid, jscname, jscdesc, jscminutes, jschours, jscweekdays, jscmonthdays, jscmonths) VALUES(job_id, 'Purge deleted custom probes', 'This job runs periodically to purge deleted custom probes and its data.', '{t,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f}', '{f,t,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f}','{t,t,t,t,t,t,t}', '{t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t}', '{t,t,t,t,t,t,t,t,t,t,t,t}');
	END IF;
END $$;

REVOKE ALL ON FUNCTION pem.purge_deleted_probes() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION pem.purge_deleted_probes() TO pem_agent;

CREATE OR REPLACE FUNCTION pem.generate_metric_chart_data(
	cid integer, aid integer, sid integer, db text, schema text,
	level integer, show_system_objects boolean, is_capacity_manager boolean=false)
RETURNS TABLE(idx int2, label text, agg_time timestamptz, agg_val numeric)
AS $$
DECLARE
	chart_exists        boolean := false;
	start_time          timestamptz := NULL;
	end_time            timestamptz := NULL;
	max_points          integer;
	curs                refcursor;
	mcurs               refcursor;
	gcurs               refcursor;
	metric              pem.chart_metric%ROWTYPE;
	chart               pem.chart%ROWTYPE;
	probe_id            int4;
	probe_target_type   integer;
	probe_applies_to_id integer;
	probe_deleted       boolean;
	probe_keys          text[];
	probe_key_vals      text[];
	metric_restrict_dbs text[];
	restricted_dbs      text[];
	restricted_schemas  text[];
	pos                 int2 := 0;
	query               text;
	tmp_str             text;
	_params             text[];
	_vals               text[];
	params              text[];
	vals                text[];
	agg_int             integer;
	metric_label        text := NULL;
	probe_type          text := NULL;
	chart_span          text := NULL;
	is_remotely_monitored boolean := false;
BEGIN
	-- Check if the data for the chart exists in the pem.metrices_chart
	EXECUTE 'SELECT CASE WHEN count(*) > 0 THEN true ELSE false END FROM pem.metrices_chart WHERE cid = $1::int4'
	INTO chart_exists USING cid;

	IF NOT chart_exists OR chart_exists IS NULL THEN
		RAISE EXCEPTION '101';
	END IF;

	EXECUTE 'SELECT value||'' ''||unit FROM pem.config WHERE param = (SELECT rwlimit_span_param FROM pem.chart WHERE id = $1::int4)'
	INTO chart_span USING cid;

	-- Fetch the start time, end time, maximum points & aggregation intervals
	IF chart_span IS NOT NULL AND trim(chart_span) != '' THEN
	EXECUTE 'SELECT now() - '''||chart_span||'''::interval, now(), max_points, agg_int FROM pem.metrices_chart WHERE cid = $1::int4'
	INTO start_time, end_time, max_points, agg_int USING cid;
	END IF;

	IF start_time IS NULL THEN
	EXECUTE 'SELECT now() -  time_span, now(), max_points, agg_int FROM pem.metrices_chart WHERE cid = $1::int4'
	INTO start_time, end_time, max_points, agg_int USING cid;
	END IF;

	-- Couldn't fetch the time_span/max_points from the pem.metrices_chart table
	IF start_time IS NULL THEN
		RAISE EXCEPTION '102';
	END IF;

	CASE
	WHEN level = 100 THEN
		-- On agent level dash, agent-id must exists
		IF aid IS NULL OR aid <= 0 THEN
			RAISE EXCEPTION '103';
		END IF;
	WHEN level >= 200 THEN
		-- On server level dash, server-id must exists
		IF sid IS NULL OR sid <= 0 THEN
			RAISE EXCEPTION '104';
		END IF;

		-- Fetch agent-id, if not provided
		IF aid IS NULL OR aid <= 0 THEN
			aid := NULL;

			EXECUTE 'SELECT agent_id FROM pem.agent_server_binding WHERE server_id = $1::int4' INTO aid USING sid;

			IF aid IS NULL THEN
				RAISE EXCEPTION '105';
			END IF;
		END IF;

		-- Fetch remote monitoring status of the server.
		EXECUTE 'SELECT is_remote_monitoring FROM pem.server WHERE id = $1::int4' INTO is_remotely_monitored USING sid;

		-- Fetch the restricted databases information (only for server level charts)
		IF level = 200 THEN
			EXECUTE '
SELECT
    pem.db_escaped_string_to_array(COALESCE(o.database_restriction, oa.database_restriction))
FROM
    pem.server s
    LEFT OUTER JOIN pg_catalog.pg_roles owner ON (owner.oid = s.owner)
    LEFT OUTER JOIN pem.server_option o ON (s.id = o.server_id AND o.pem_user = current_user)
    LEFT OUTER JOIN pem.server_option oa
        ON (o.id IS NULL AND s.id = oa.server_id AND
            (owner.rolname = oa.pem_user OR (owner.rolname IS NULL AND oa.pem_user IS NULL)))
WHERE
    s.id = $1::int4' INTO restricted_dbs USING sid;
		END IF;

		IF level >= 300 THEN
			-- database_name is required for any charts lower than server
			-- level
			IF db IS NULL OR trim(db) = '' THEN
				RAISE EXCEPTION '106';
			END IF;

			-- Fetch the restricted schema information (for database level chats)
			IF level = 300 THEN
				EXECUTE '
SELECT
    pem.db_escaped_string_to_array(COALESCE(o.schema_restriction, oa.schema_restriction))
FROM
    pem.server s
    LEFT OUTER JOIN pg_catalog.pg_roles owner ON (owner.oid = s.owner)
    LEFT OUTER JOIN pem.database_option o ON (s.id = o.server_id AND o.pem_user = current_user AND o.database = $2::text)
    LEFT OUTER JOIN pem.database_option oa
        ON (o.id IS NULL AND s.id = oa.server_id AND oa.database = $2::text AND
            (owner.rolname = oa.pem_user OR (owner.rolname IS NULL AND oa.pem_user IS NULL)))
WHERE
    s.id = $1::int4' INTO restricted_schemas USING sid, db;
			END IF;
		END IF;
	ELSE -- DO NOTHING
	END CASE;

	EXECUTE 'SELECT * FROM pem.chart WHERE id = $1::int4' USING cid INTO chart;
	-- Fetch all the metrices for this chart
	OPEN mcurs FOR EXECUTE 'SELECT * FROM pem.chart_metric WHERE cid = $1::int4' USING cid;
	LOOP
		FETCH mcurs INTO metric;
		EXIT WHEN NOT FOUND;

		probe_id := NULL;
		probe_target_type := NULL;
		probe_applies_to_id := NULL;
		probe_keys := NULL;
		probe_deleted := false;

		-- Fetch target-type, probe-applies-to, primary keys for the involved
		-- probe-table
		EXECUTE
		'SELECT p.id, p.target_type_id, p.applies_to_id, ARRAY(SELECT pc.internal_name FROM pem.probe_column pc WHERE pc.probe_id = p.id AND (($2::int4 = 300 AND pc.internal_name <> ''database_name'') OR ($2::int4 = 400 AND pc.internal_name NOT IN (''database_name'', ''schema_name'')) OR true) AND pc.classification = ''k'' ORDER BY pc.id) AS keys, p.deleted FROM pem.probe p WHERE p.internal_name = $1::text'
		INTO probe_id, probe_target_type, probe_applies_to_id, probe_keys, probe_deleted USING metric.tbl, level;

		IF probe_target_type IS NULL THEN
			-- We couldn't find the probe_target_id, it means the probe with
			-- that name does not exists
			RAISE EXCEPTION '107|%', metric.tbl;
		END IF;

		IF probe_deleted THEN
			-- The probe has been marked for deletion
			RAISE EXCEPTION '108';
		END IF;

		-- If server is remotely monitored then we will not render agent level metrics
		IF is_remotely_monitored AND probe_target_type = 100 THEN
			CONTINUE;
		END IF;

		-- We need to find out, if this metric actually generates multiple
		-- sub-metrices (because they may have other primary keys too)
		IF level > 0 AND probe_keys IS NOT NULL AND array_length(probe_keys, 1) <> 0 THEN

			query := 'SELECT ARRAY[';

			SELECT string_agg('tbl.' || pg_catalog.quote_ident(probe_keys[a]), '::text, ')
				FROM generate_series(array_lower(probe_keys,1), array_upper(probe_keys,1)) a INTO tmp_str;
			query := query || tmp_str || '::text]::text[] FROM pemdata.' || pg_catalog.quote_ident(metric.tbl) || ' tbl';

			metric_restrict_dbs = NULL;
			CASE WHEN probe_applies_to_id = 100 THEN
					query := query || ' WHERE tbl.agent_id = ' || aid::text || '::integer';
					_params := ARRAY['agent_id'];
					_vals := ARRAY[aid::text];
				WHEN probe_target_type = 200 THEN
					query := query || ' WHERE tbl.server_id = ' || sid::text || '::integer';
					_params := ARRAY['server_id'];
					_vals := ARRAY[sid::text]::text[];
					IF probe_applies_to_id >= 300 AND level >= 300 THEN
						-- Restricted DBs are availabe that doesn't mean - they're applicable
						-- for this metric
						--
						-- Thye're applicable only if probe can applies to database level and
						-- current dashboard is for server-level
						IF array_length(restricted_dbs, 1) <> 0 THEN
							metric_restrict_dbs = restricted_dbs;
						ELSE
							metric_restrict_dbs := NULL;
						END IF;

						query := query || ' AND tbl.database_name = ' || pg_catalog.quote_literal(db::text) || '::text';
						_params := ARRAY['server_id', 'database_name'];
						_vals := ARRAY[sid::text, db];
					END IF;
					IF probe_applies_to_id >= 400 AND level = 400 THEN
						_params := ARRAY['server_id', 'database_name', 'schema_name'];
						_vals := ARRAY[sid::text, db, schema];
						query := query || ' AND tbl.schema_name = ' || pg_catalog.quote_literal(schema::text) || '::text';
					END IF;
					IF NOT show_system_objects THEN
						IF probe_applies_to_id = 300 THEN
							query := query || ' AND CASE WHEN database_name != '''' THEN database_name != ''template0'' AND database_name != ''template1'' ELSE TRUE END';
						ELSIF probe_applies_to_id > 300 THEN
							query := query || E' AND CASE WHEN database_name != '''' THEN database_name != ''template0'' AND database_name != ''template1'' AND schema_name NOT IN (''pg_catalog'', ''sys'', ''information_schema'') AND schema_name NOT LIKE ''pg_toast%'' AND schema_name NOT LIKE ''pg_temp%'' ELSE TRUE END';

							query := query || ' AND CASE WHEN database_name != '''' THEN database_name != ''template0'' AND database_name != ''template1'' ELSE TRUE END';
						END IF;
					END IF;
					IF probe_applies_to_id = 300 THEN
						IF restricted_dbs IS NOT NULL AND array_length(restricted_dbs, 1) > 0 THEN
							query := query || ' AND database_name = ANY(' || pg_catalog.quote_literal(restricted_dbs::text) || ')';
						END IF;
					ELSIF probe_applies_to_id > 300 THEN
						IF restricted_dbs IS NOT NULL AND array_length(restricted_dbs, 1) > 0 THEN
							query := query || ' AND database_name = ANY(' || pg_catalog.quote_literal(restricted_dbs::text) || ') AND schema_name = ANY(
SELECT
    COALESCE(o.schema_restriction, oa.schema_restriction)
FROM
    pem.server s
    LEFT OUTER JOIN pg_catalog.pg_roles owner ON (owner.oid = s.owner)
    LEFT OUTER JOIN pem.database_option o ON (s.id = o.server_id AND o.pem_user = current_user AND o.database = tbl.database_name)
    LEFT OUTER JOIN pem.database_option oa
        ON (o.id IS NULL AND s.id = oa.server_id AND oa.database = tbl.database_name AND
            (owner.rolname = oa.pem_user OR (owner.rolname IS NULL AND oa.pem_user IS NULL)))
WHERE
    s.id = tbl.server_id)';
						END IF;
						IF level = 400 THEN
							query := query || ' AND schema_name = ' || pg_catalog.quote_literal(schema::text) || '::text';
						END IF;
					END IF;
				WHEN probe_target_type = 300 THEN
					query := query || ' WHERE tbl.server_id = ' || sid::text || '::integer AND tbl.database_name = ' || pg_catalog.quote_literal(db::text) || '::text';
					_params := ARRAY['server_id', 'database_name'];
					_vals := ARRAY[sid::text, db]::text[];
					IF array_length(restricted_dbs, 1) <> 0 THEN
						metric_restrict_dbs = restricted_dbs;
					ELSE
						metric_restrict_dbs := NULL;
					END IF;
					IF probe_applies_to_id > 300  THEN
						IF level > 300 THEN
							_params := ARRAY['server_id', 'database_name', 'schema_name'];
							_vals := ARRAY[sid::text, db, schema];
						END IF;
						IF NOT show_system_objects THEN
							query := query || E' AND (schema_name NOT IN (''pg_catalog'', ''sys'', ''information_schema'') AND schema_name NOT LIKE ''pg_toast%'' AND schema_name NOT LIKE ''pg_temp%'')';
						END IF;
						IF restricted_schemas IS NOT NULL AND array_length(restricted_schemas, 1) > 0 THEN
							query := query || ' AND schema_name = ANY(' || pg_catalog.quote_literal(restricted_schemas::text) || ')';
						END IF;
					END IF;
				WHEN probe_target_type = 400 THEN
					_params := ARRAY['server_id', 'database_name', 'schema_name'];
					_vals := ARRAY[sid::text, db, schema];
					query := query || ' WHERE tbl.server_id = ' || sid::text || '::integer AND tbl.database_name = ' || pg_catalog.quote_literal(db::text) || '::text AND tbl.schema_name = ' || pg_catalog.quote_literal(schema::text) || '::text';
				ELSE
					query := query;
			END CASE;

			IF metric.gorderby IS NOT NULL AND array_length(metric.gorderby, 1) >0 THEN
				SELECT string_agg('tbl.' || pg_catalog.quote_ident(metric.gorderby[i]), ', ')
					FROM generate_series(array_lower(metric.gorderby,1), array_upper(metric.gorderby,1)) i INTO tmp_str;
				query := query || ' ORDER BY ' || tmp_str;
			END IF;
			IF (metric.glimit IS NOT NULL OR metric.glimit <> 0) THEN
				IF (metric.glimit < 0) THEN
					query := query || ' LIMIT ' || (metric.glimit * -1)::text || ' DESC';
				ELSE
					query := query || ' LIMIT ' || metric.glimit::text;
				END IF;
			END IF;

			IF metric.glimit IS NULL OR metric.glimit <> 0 THEN
				OPEN gcurs FOR EXECUTE query;
				LOOP
					FETCH gcurs INTO probe_key_vals;
					EXIT WHEN NOT FOUND;
					params := _params;
					vals := _vals;

					FOR a IN array_lower(probe_key_vals, 1) .. array_upper(probe_key_vals, 1)
					LOOP
						params := params || probe_keys[a]::text;
						vals := vals || probe_key_vals[a]::text;
					END LOOP;

					FOR m_idx IN array_lower(metric.metrices, 1) .. array_upper(metric.metrices, 1)
					LOOP
						pos := pos + 1;
						SELECT string_agg(probe_key_vals[b], ', ')
							FROM generate_series(array_lower(probe_key_vals,1), array_upper(probe_key_vals,1)) b INTO label;
						EXECUTE '
	SELECT
		(CASE WHEN NOT pit_by_default THEN display_name || ''+'' ELSE display_name END), sql_data_type
	FROM pem.probe_column
	WHERE probe_id = $1::int4 AND internal_name = $2::text AND is_graphable
	UNION ALL
	SELECT
		display_name, sql_data_type
	FROM pem.probe_column
	WHERE probe_id = $1::int4 AND (internal_name || ''_pit'') = $2::text AND is_graphable AND NOT pit_by_default AND calculate_pit'
	USING probe_id, metric.metrices[m_idx] INTO metric_label, probe_type;

						IF chart.labels IS NOT NULL AND array_length(chart.labels, 1) >= pos AND chart.labels[pos] IS NOT NULL THEN
							label := chart.labels[pos] || ' - ' || label;
						ELSE
							IF metric_label IS NOT NULL THEN
								label := metric_label || ' - ' || label;
							END IF;
						END IF;
						query := '
	SELECT
		$1::int2 AS idx, $2::text AS label, aggregated_time, aggregated_value
	FROM pem.data_rollup ($3::text, $4::text, $5::text, $6::timestamptz, $7::timestamptz, $8::interval, $9::integer, $10::text[], $11::text[], $12::integer, $13::boolean, $14::text[])';
						IF metric.agg_func IS NOT NULL AND array_length(metric.agg_func, 1) >= m_idx AND metric.agg_func[m_idx] IS NOT NULL THEN
							tmp_str := metric.agg_func[m_idx];
						END IF;
						CASE
							WHEN tmp_str = 'A' THEN tmp_str := 'avg';
							WHEN tmp_str = 'M' THEN tmp_str := 'max';
							WHEN tmp_str = 'm' THEN tmp_str := 'min';
							WHEN tmp_str = 'F' THEN tmp_str := 'FIRST';
							ELSE tmp_str := 'avg';
						END CASE;

						RETURN QUERY EXECUTE query USING pos, label, metric.tbl, tmp_str, metric.metrices[m_idx], start_time, end_time, agg_int * '1 minute'::interval, max_points, params, vals, aid, is_capacity_manager, metric_restrict_dbs;
					END LOOP;
				END LOOP;
				CLOSE gcurs;
			ELSE
				FOR m_idx IN array_lower(metric.metrices, 1) .. array_upper(metric.metrices, 1)
				LOOP
					pos := pos + 1;
					EXECUTE '
SELECT
	(CASE WHEN NOT pit_by_default THEN display_name || ''+'' ELSE display_name END)
FROM pem.probe_column
WHERE probe_id = $1::int4 AND internal_name = $2::text AND is_graphable
UNION ALL
SELECT
	display_name
FROM pem.probe_column
WHERE probe_id = $1::int4 AND (internal_name || ''_pit'') = $2::text AND is_graphable AND NOT pit_by_default AND calculate_pit'
USING probe_id, metric.metrices[m_idx] INTO metric_label;

					IF chart.labels IS NOT NULL AND array_length(chart.labels, 1) >= pos AND chart.labels[pos] IS NOT NULL THEN
						label := chart.labels[pos];
					ELSE
						IF metric_label IS NOT NULL THEN
							label := metric_label;
						END IF;
					END IF;
					query := '
SELECT
	$1::int2 AS idx, $2::text AS label, aggregated_time, aggregated_value::numeric
FROM pem.data_rollup ($3::text, $4::text, $5::text, $6::timestamptz, $7::timestamptz, $8::interval, $9::integer, $10::text[], $11::text[], $12::integer, $13::boolean, $14::text[])';
					IF metric.agg_func IS NOT NULL AND array_length(metric.agg_func, 1) >= m_idx AND metric.agg_func[m_idx] IS NOT NULL THEN
						tmp_str := metric.agg_func[m_idx];
					END IF;
					CASE
						WHEN tmp_str = 'A' THEN tmp_str := 'avg';
						WHEN tmp_str = 'M' THEN tmp_str := 'max';
						WHEN tmp_str = 'm' THEN tmp_str := 'min';
						WHEN tmp_str = 'F' THEN tmp_str := 'FIRST';
						ELSE tmp_str := 'avg';
					END CASE;

					RETURN QUERY EXECUTE query USING pos, label, metric.tbl, tmp_str, metric.metrices[m_idx], start_time, end_time, agg_int * '1 minute'::interval, max_points, _params, _vals, aid, is_capacity_manager, metric_restrict_dbs;
				END LOOP;
			END IF;
		ELSE
			params := ARRAY[]::text[];
			vals := ARRAY[]::text[];
			metric_restrict_dbs := NULL;

			CASE WHEN probe_applies_to_id = 100 THEN
					params := ARRAY['agent_id'];
					vals := ARRAY[aid::text];
				WHEN probe_target_type = 200 THEN
					params := ARRAY['server_id'];
					vals := ARRAY[sid::text]::text[];

					IF probe_applies_to_id >= 300 AND level >= 300 THEN
						-- Restricted DBs are availabe that doesn't mean - they're applicable
						-- for this metric
						--
						-- Thye're applicable only if probe can applies to database level and
						-- current dashboard is for server-level
						IF array_length(restricted_dbs, 1) <> 0 THEN
							metric_restrict_dbs = restricted_dbs;
						ELSE
							metric_restrict_dbs := NULL;
						END IF;
					END IF;

					IF probe_applies_to_id >= 400 AND level = 400 THEN
						params := ARRAY['server_id', 'database_name', 'schema_name'];
						vals := ARRAY[sid::text, db, schema];
					ELSIF probe_applies_to_id >= 300 AND level >= 300 THEN
						params := ARRAY['server_id', 'database_name'];
						vals := ARRAY[sid::text, db];
					END IF;
				WHEN probe_target_type = 300 THEN
					params := ARRAY['server_id', 'database_name'];
					vals := ARRAY[sid::text, db]::text[];
					IF array_length(restricted_dbs, 1) <> 0 THEN
						metric_restrict_dbs = restricted_dbs;
					ELSE
						metric_restrict_dbs := NULL;
					END IF;
					IF probe_applies_to_id > 300  THEN
						IF level > 300 THEN
							params := ARRAY['server_id', 'database_name', 'schema_name'];
							vals := ARRAY[sid::text, db, schema];
						END IF;
					END IF;
				WHEN probe_target_type = 400 THEN
					params := ARRAY['server_id', 'database_name', 'schema_name'];
					vals := ARRAY[sid::text, db, schema];
			ELSE -- Do nothing
			END CASE;
			CASE WHEN metric.params IS NOT NULL THEN
				FOR i IN array_lower(metric.params, 1) .. array_upper(metric.params, 1)
				LOOP
					IF metric.params[i].name IS NOT NULL AND metric.params[i].name != '' THEN
						IF sid IS NOT NULL AND metric.params[i].name = 'server_id' THEN
							params := params || metric.params[i].name;
							vals := vals || sid::text;
						ELSIF aid IS NOT NULL AND metric.params[i].name = 'agent_id' THEN
							params := params || metric.params[i].name;
							vals := vals || aid::text;
						ELSIF db IS NOT NULL AND db <> '' AND metric.params[i].name = 'database_name' THEN
							params := params || metric.params[i].name;
							vals := vals || db::text;
						ELSIF schema IS NOT NULL AND schema <> '' AND metric.params[i].name = 'schema_name' THEN
							params := params || metric.params[i].name;
							vals := vals || schema::text;
						ELSE
							params := params || metric.params[i].name;
							vals := vals || metric.params[i].value;
						END IF;
					END IF;
				END LOOP;
			ELSE -- Do nothing
			END CASE;

			tmp_str := 'A';
			FOR m_idx IN array_lower(metric.metrices, 1) .. array_upper(metric.metrices, 1)
			LOOP
				pos := pos + 1;
				label := '';

				EXECUTE '
SELECT
	(CASE WHEN NOT pit_by_default THEN display_name || ''+'' ELSE display_name END), sql_data_type
FROM pem.probe_column
WHERE probe_id = $1::int4 AND internal_name = $2::text AND is_graphable
UNION ALL
SELECT
	display_name, sql_data_type
FROM pem.probe_column
WHERE probe_id = $1::int4 AND (internal_name || ''_pit'') = $2::text AND is_graphable AND NOT pit_by_default AND calculate_pit'
USING probe_id, metric.metrices[m_idx] INTO metric_label, probe_type;

				IF chart.labels IS NOT NULL AND array_length(chart.labels, 1) >= pos THEN
					label := chart.labels[pos];
				ELSE
					IF metric_label IS NOT NULL THEN
						label := metric_label;
					END IF;
				END IF;
				query := 'SELECT
	$1::int2 AS idx, $2::text AS label, aggregated_time, aggregated_value
FROM pem.data_rollup ($3::text, $4::text, $5::text, $6::timestamptz, $7::timestamptz, $8::interval, $9::integer, $10::text[], $11::text[], $12::integer, $13::boolean, $14::text[])';
				IF metric.agg_func IS NOT NULL AND array_length(metric.agg_func, 1) >= m_idx THEN
					tmp_str := metric.agg_func[m_idx];
				END IF;
				CASE
					WHEN tmp_str = 'A' THEN tmp_str := 'avg';
					WHEN tmp_str = 'M' THEN tmp_str := 'max';
					WHEN tmp_str = 'm' THEN tmp_str := 'min';
					WHEN tmp_str = 'F' THEN tmp_str := 'FIRST';
					ELSE tmp_str := 'avg';
				END CASE;

				RETURN QUERY EXECUTE query USING pos, label, metric.tbl, tmp_str, metric.metrices[m_idx], start_time, end_time, agg_int * '1 minutes'::interval, max_points, params, vals, aid, is_capacity_manager, metric_restrict_dbs;
			END LOOP;
		END IF;
	END LOOP;
	CLOSE mcurs;
END
$$ LANGUAGE 'plpgsql';

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
				EXECUTE E'SELECT $1::text || '' ('' || $2::text || ''/'' || array_to_string(ARRAY(SELECT pg_catalog.quote_ident(($3::pem.chart_metric_param[])[s].value) FROM generate_series (2, array_upper($3::pem.chart_metric_param[], 1) - 2, 1) AS s), ''/'') || ''('' || COALESCE(array_to_string((($3::pem.chart_metric_param[])[array_upper($3::pem.chart_metric_param[], 1)].value)::text[], '',''), '''') ||  ''))''' INTO label USING nrec.metrices_display[1], nrec.object, nrec.params;
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

COMMIT TRANSACTION;
