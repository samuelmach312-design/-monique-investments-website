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

-- Upgrade script for v5.0.0 (initial script)

BEGIN TRANSACTION;

-- Update the schema version
CREATE OR REPLACE FUNCTION pem.schema_version()
  RETURNS integer AS
'SELECT 201404151::integer;'
  LANGUAGE 'sql' IMMUTABLE;
COMMENT ON FUNCTION pem.schema_version() IS 'Returns the version number of the PEM schema';

-- Add new coulmn "is_remote_monitoring" to pem.server
ALTER TABLE pem.server ADD COLUMN is_remote_monitoring boolean NOT NULL DEFAULT false;
COMMENT ON COLUMN pem.server.is_remote_monitoring IS 'Indicate whether this server is remotely monitored or not';

CREATE OR REPLACE VIEW pem.avail_servers AS
	SELECT
		s.id AS id,
		s.description AS description,
		s.server AS server,
		s.port AS port,
		s.database AS database,
		s.ssl AS ssl,
		s.serviceid AS serviceid,
		s.active AS active,
		s.hostaddr AS hostaddr,
		s.service AS service,
		s.alert_blackout AS alert_blackout,
		s.owner AS owner,
		s.team AS team,
		o.rolname AS server_owner,
		s.is_remote_monitoring AS is_remote_monitoring
	FROM (SELECT s.*, r.rolsuper AS rolsuper FROM pem.server s, pg_catalog.pg_roles r WHERE r.rolname = current_user) AS s
		LEFT OUTER JOIN pg_catalog.pg_roles o ON (o.oid = s.owner)
		LEFT OUTER JOIN pg_catalog.pg_roles t ON (t.rolname = s.team)
	WHERE
	    -- Only active servers
		s.active AND
		-- Is a superuser
		(s.rolsuper OR
			-- No team provided
			s.team IS NULL OR s.team = '' OR
			-- Owner of the server
			o.rolname = current_user OR
			-- Valid team provided and current_user is member of the it
			(t.oid IS NOT NULL AND pg_catalog.pg_has_role(s.team, 'member')));

-- Add new coulmn "run_on_remote_server" to pem.pe_rules
ALTER TABLE pem.pe_rules ADD COLUMN run_on_remote_server boolean NOT NULL DEFAULT true;
COMMENT ON COLUMN pem.pe_rules.run_on_remote_server IS 'Tells the rule will be run on remote server or not';

UPDATE pem.pe_rules SET run_on_remote_server = false WHERE evaluator IN ('pem.pe_rule_shared_buffers', 'pem.pe_rule_work_mem', 'pem.pe_rule_maintenance_work_mem',
'pem.pe_rule_wal_sync_method', 'pem.pe_rule_effective_cache_size', 'pem.pe_rule_trust_authentication_disabled', 'pem.pe_rule_password_authentication',
'pem.pe_rule_ssl_for_increased_security', 'pem.pe_rule_check_log_data_deviceid', 'pem.pe_rule_check_log_tblspc_deviceid', 'pem.pe_rule_multiple_tblspc');

CREATE OR REPLACE FUNCTION pem.pe_engine(rule_id_array int[], server_database_pair_array text[][]) RETURNS SETOF RECORD
AS $$
DECLARE
	temp_server int;
	prev_server int:= 0;
	database text;
	evaluator_function text;
	function_query text;
	is_server_only boolean:= false;
	is_run_on_remote_server boolean:= true;
	remote_monitoring boolean:= false;
	execute_rule boolean:= true;
	rule_name text; server_host text; expert_name text; database_name text; rule_description text; rule_trigger text; rule_recommended_value text; server_description text;
	server_port int:= 0;
	expert_id int:= 0;
	row  RECORD;

BEGIN
	CREATE TEMPORARY TABLE temp_expert_records(server_id int, rule_name text, server_host text, server_description text, server_port int, expert_name text, database_name text, description text, trigger text, recommended_value text, data_name text[], data_value text[], severity int);

	-- Loop through the rule ids
	FOR k IN array_lower(rule_id_array,1) .. array_upper(rule_id_array,1)
	LOOP

		-- Get rule name, description, trigger, recommended value
		SELECT name, description, trigger, recommended_value INTO rule_name,rule_description,rule_trigger,rule_recommended_value FROM pem.pe_rules_text WHERE rule_id = rule_id_array[k];

		-- Get the evaluator function and value of "run_on_server_only" and "run_on_remote_server" for rule id
		SELECT expert, evaluator, run_on_server_only, run_on_remote_server INTO expert_id, evaluator_function, is_server_only, is_run_on_remote_server FROM pem.pe_rules where id = rule_id_array[k];

		-- Get expert name
		SELECT name INTO expert_name FROM pem.pe_experts WHERE id = expert_id;

		-- Reset value of prev server for next rule
		prev_server = 0;

		-- Loop through the no of servers
		FOR i in array_lower(server_database_pair_array,1) .. array_upper(server_database_pair_array,1)
		LOOP

			-- Assumptions: We will always have two dimentions:
			--    First represents server
			--    Second represents database

			temp_server := server_database_pair_array[i][1];
			database := server_database_pair_array[i][2];

			-- Get server name
			SELECT server, is_remote_monitoring INTO server_host, remote_monitoring FROM pem.server WHERE id = temp_server;
			-- Get description and port for server
			SELECT description, port INTO server_description, server_port FROM pem.server WHERE id = temp_server;

			-- In case of remotely monitored server, we will check the value of "run_on_remote_server"
			-- if it is true then only we execute the rule else skip it.
			execute_rule = true;
			IF (remote_monitoring) THEN
				IF (is_run_on_remote_server) THEN
					execute_rule = true;
				ELSE
					execute_rule = false;
				END IF;
			END IF;

			IF  (execute_rule) THEN
				-- if value of is_server_only is true then we have to run this rule on server only
				IF (is_server_only) THEN
					IF (prev_server != temp_server) THEN
						function_query = E'SELECT ' || evaluator_function || '(' || temp_server ||',''' || rule_name ||''');';
						database_name = '-';

						INSERT INTO temp_expert_records(server_id, rule_name, server_host, server_description, server_port, expert_name, database_name, description, trigger, recommended_value, data_name, data_value, severity) VALUES (temp_server, rule_name, server_host, server_description, server_port, expert_name, database_name, rule_description, rule_trigger, rule_recommended_value, '{}', '{}', 0);

						EXECUTE function_query;
						prev_server = temp_server;
					END IF;
				ELSE
					-- run on databases;
					function_query = E'SELECT ' || evaluator_function || '(' || temp_server ||',''' || rule_name ||''',''' || database || ''');';
					database_name = database;

					INSERT INTO temp_expert_records(server_id, rule_name, server_host, server_description, server_port, expert_name, database_name, description, trigger, recommended_value, data_name, data_value, severity) VALUES (temp_server, rule_name, server_host, server_description, server_port, expert_name, database_name, rule_description, rule_trigger, rule_recommended_value, '{}', '{}', 0);

					EXECUTE function_query;
				END IF;
			END IF;
		END LOOP;
	END LOOP;

	FOR row IN SELECT * FROM temp_expert_records ORDER BY server_id, expert_name, rule_name LOOP
		RETURN NEXT row;
	END LOOP;

	RETURN;
END
$$ LANGUAGE plpgsql;

UPDATE pem.chart SET labels = ARRAY['', 'Blackout', 'Name', 'Status', 'Connections', 'Alerts', 'Version', 'Remotely Monitored'] WHERE name = 'Servers Status Info';

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
	AND (p.agent_capability IS NULL
		OR p.agent_capability = ANY(a.agent_capability_list))
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
	AND (p.agent_capability IS NULL
		OR p.agent_capability = ANY(a.agent_capability_list))
	AND (p.any_server_version OR psv.probe_id IS NOT NULL)
	AND p.internal_name NOT IN( SELECT UNNEST(CASE WHEN s.is_remote_monitoring THEN ARRAY['pg_hba_conf', 'data_log_file_analysis'] ELSE ARRAY[''] END))
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
	AND ocd.connections_allowed
	AND (p.agent_capability IS NULL
		OR p.agent_capability = ANY(a.agent_capability_list))
	AND (p.any_server_version OR psv.probe_id IS NOT NULL)
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
	AND ocd.connections_allowed
	AND (p.agent_capability IS NULL
		OR p.agent_capability = ANY(a.agent_capability_list))
	AND (p.any_server_version OR psv.probe_id IS NOT NULL)
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
	AND ocd.connections_allowed
	AND (p.agent_capability IS NULL
		OR p.agent_capability = ANY(a.agent_capability_list))
	AND (p.any_server_version OR psv.probe_id IS NOT NULL)
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
	AND ocd.connections_allowed
	AND (p.agent_capability IS NULL
		OR p.agent_capability = ANY(a.agent_capability_list))
	AND (p.any_server_version OR psv.probe_id IS NOT NULL)
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
	AND ocd.connections_allowed
	AND (p.agent_capability IS NULL
		OR p.agent_capability = ANY(a.agent_capability_list))
	AND (p.any_server_version OR psv.probe_id IS NOT NULL)
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
	AND ocd.connections_allowed
	AND (p.agent_capability IS NULL
		OR p.agent_capability = ANY(a.agent_capability_list))
	AND (p.any_server_version OR psv.probe_id IS NOT NULL)
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
	AND ocd.connections_allowed
	AND (p.agent_capability IS NULL
		OR p.agent_capability = ANY(a.agent_capability_list))
	AND (p.any_server_version OR psv.probe_id IS NOT NULL);

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

		-- Fetch target-type, probe-applies-to, primary keys for the involved
		-- probe-table
		EXECUTE
		'SELECT p.id, p.target_type_id, p.applies_to_id, ARRAY(SELECT pc.internal_name FROM pem.probe_column pc WHERE pc.probe_id = p.id AND (($2::int4 = 300 AND pc.internal_name <> ''database_name'') OR ($2::int4 = 400 AND pc.internal_name NOT IN (''database_name'', ''schema_name'')) OR true) AND pc.classification = ''k'' ORDER BY pc.id) AS keys FROM pem.probe p WHERE p.internal_name = $1::text'
		INTO probe_id, probe_target_type, probe_applies_to_id, probe_keys USING metric.tbl, level;

		IF probe_target_type IS NULL THEN
			-- We couldn't find the probe_target_id, it means the probe with
			-- that name does not exists
			RAISE EXCEPTION '107|%', metric.tbl;
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

-- Done!
COMMIT TRANSACTION;

