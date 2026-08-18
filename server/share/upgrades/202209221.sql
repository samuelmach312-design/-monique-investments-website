/***************************************************************************
 *
 * Postgres Enterprise Manager
 *
 * Copyright (C) 2010 - 2025, EnterpriseDB Corporation. All rights reserved.
 *
 ***************************************************************************/

-- NOTE: This sql file is responsible for PEM 8.6.0 schema upgrade.

BEGIN TRANSACTION;
	CREATE OR REPLACE FUNCTION pem.schema_version() RETURNS integer AS
		'SELECT 202209221::integer;'
	LANGUAGE 'sql' IMMUTABLE;

	-- PEM-4544 Added support for monitoring of PG/AS 15
	DO $DO$
	BEGIN
			-- Check if the server version already exist for PG 15
			IF NOT EXISTS (SELECT id FROM pem.server_version WHERE id = 11500) THEN
					INSERT INTO pem.server_version VALUES (11500, 'PostgreSQL 15');
			END IF;

			-- Check if the server version already exist for EPAS 15
			IF NOT EXISTS (SELECT id FROM pem.server_version WHERE id = 21500) THEN
					INSERT INTO pem.server_version VALUES (21500, 'Advanced Server 15');
			END IF;

			-- Check if the probe server version already exist for PG 15
			IF NOT EXISTS (SELECT server_version_id FROM pem.probe_server_version WHERE server_version_id = 11500) THEN
					INSERT INTO pem.probe_server_version
							(probe_id, server_version_id, probe_code)
							SELECT psv.probe_id, 11500 AS server_version_id, psv.probe_code FROM (
											SELECT probe_id, probe_code FROM pem.probe_server_version
											WHERE server_version_id = 11400
							) AS psv
							JOIN pem.probe p ON (psv.probe_id = p.id) AND p.internal_name = ANY(
									ARRAY[
									'oc_table', 'oc_schema', 'oc_function', 'oc_extension', 'oc_views',
									'database_statistics', 'table_statistics', 'table_frozenxid',
									'table_size', 'function_statistics', 'mview_bloat',
									'mview_frozenxid', 'mview_size', 'blocked_session_info',
									'background_writer_statistics', 'session_info', 'lock_info',
									'number_of_wal_files', 'wal_archive_status',
									'streaming_replication', 'streaming_replication_db_conflicts',
									'streaming_replication_lag_time', 'xdb_smr_mmr_replication',
									'efm_cluster_node_status', 'efm_cluster_info'
									]::text[]
			);
			END IF;

			-- Check if the probe server version already exist for EPAS 15
			IF NOT EXISTS (SELECT server_version_id FROM pem.probe_server_version WHERE server_version_id = 21500) THEN
					INSERT INTO pem.probe_server_version
							(probe_id, server_version_id, probe_code)
							SELECT psv.probe_id, 21500 AS server_version_id, psv.probe_code FROM (
											SELECT probe_id, probe_code FROM pem.probe_server_version
											WHERE server_version_id = 21400
							) AS psv
							JOIN pem.probe p ON (psv.probe_id = p.id) AND p.internal_name = ANY(
											ARRAY[
											'oc_table', 'oc_schema','oc_function', 'oc_extension', 'database_statistics',
											'table_statistics', 'table_frozenxid', 'function_statistics', 'table_size',
											'background_writer_statistics', 'number_of_wal_files', 'session_info',
											'system_waits', 'session_waits', 'lock_info', 'audit_configuration',
											'streaming_replication', 'streaming_replication_db_conflicts',
											'xdb_smr_mmr_replication', 'oc_views', 'mview_bloat', 'mview_frozenxid',
											'mview_size', 'streaming_replication_lag_time', 'wal_archive_status',
											'efm_cluster_node_status', 'efm_cluster_info', 'blocked_session_info'
											]::text[]
			);
			END IF;

			IF NOT EXISTS (
				SELECT server_version_id FROM pem.probe_server_version
				WHERE server_version_id = 21400 AND probe_id = (
					SELECT id FROM pem.probe WHERE internal_name = 'oc_database'
				))
			THEN
				-- For Postgresql15 the datlastsysoid column is removed so we have used its hardcoded oid 16383
				INSERT INTO pem.probe_server_version
						(probe_id, server_version_id, probe_code)
				SELECT
					(SELECT id FROM pem.probe WHERE internal_name = 'oc_database'), v.version,
					'SELECT datname AS database_name, datallowconn AS connections_allowed, pg_encoding_to_char(encoding) AS encoding, CASE WHEN oid > datlastsysoid THEN false ELSE true END AS system_database FROM pg_catalog.pg_database WHERE NOT datistemplate AND datallowconn'
				FROM (
					VALUES (10901), (10902), (10903), (10904), (10905), (10906),
					(11000), (11100), (11200), (11300), (11400),
					(20901), (20902), (20903), (20904), (20905), (20906),
					(21000), (21100), (21200), (21300), (21400)
				) v(version);

				INSERT INTO pem.probe_server_version
					(probe_id, server_version_id, probe_code)
				SELECT
					(SELECT id FROM pem.probe WHERE internal_name = 'oc_database'), v.version,
					'SELECT datname AS database_name, datallowconn AS connections_allowed, pg_encoding_to_char(encoding) AS encoding, CASE WHEN oid > 16383 THEN false ELSE true END AS system_database FROM pg_catalog.pg_database WHERE NOT datistemplate AND datallowconn'
				FROM (
						VALUES (11500), (21500)
				) v(version);

				UPDATE pem.probe
						SET any_server_version = false
						WHERE id = (
							SELECT id FROM pem.probe WHERE internal_name = 'oc_database'
						);
			END IF;
	END;
	$DO$ LANGUAGE 'plpgsql';

	-- PEM-4532	Updating display name from BDR to PGD
	DO $$
	BEGIN

		-- Check if probe table contains display_name containing BDR
		IF EXISTS(
				SELECT * FROM pem.probe
				WHERE display_name like 'BDR%' AND is_system_probe
		) THEN
			RAISE INFO '--- Updating display_name from BDR to PGD in probe table';
			UPDATE pem.probe
				SET display_name = REPLACE(display_name,'BDR','PGD')
				WHERE display_name like 'BDR%' AND is_system_probe;
		END IF;
	END;
	$$ LANGUAGE plpgsql;

	DO $$
	BEGIN
		-- Check if alert_template table contains display_name containing BDR
		IF EXISTS(
					SELECT * FROM pem.alert_template
					WHERE display_name like 'BDR%'
		) THEN
			RAISE INFO '--- Updating column display_name,reference_id and description from BDR to PGD in alert_template';
			UPDATE pem.alert_template SET
				display_name = REPLACE(display_name, 'BDR', 'PGD'),
				reference_id = REPLACE(reference_id, 'BDR', 'PGD'),
				description=REPLACE(description, 'BDR', 'PGD')
				WHERE display_name like 'BDR%' AND is_system_template;
		END IF;
	END;
	$$ LANGUAGE plpgsql;

	DO $$
	BEGIN
		-- Check if chart_category table contains name column containing BDR
		IF EXISTS(
			SELECT * FROM pem.chart_category
			WHERE name like 'BDR%'
		) THEN
			RAISE INFO '--- Updating column name and descp from BDR to PGD in chart_category';
			UPDATE pem.chart_category SET
				name = REPLACE(name, 'BDR', 'PGD'),
				descp = REPLACE(descp, 'BDR', 'PGD')
				WHERE name like 'BDR%' AND id = ANY(ARRAY[16, 17, 18]);
		END IF;
	END;
	$$ LANGUAGE plpgsql;

	DO $$
	BEGIN
		-- Check if chart table contains name column containing BDR
		IF EXISTS(
			SELECT * FROM pem.chart
			WHERE name like 'BDR%' AND owner = 0
		) THEN
			RAISE INFO '--- Updating column name and reference_id from BDR to PGD in chart table';
			UPDATE pem.chart SET
					name = REPLACE(name, 'BDR', 'PGD'),
					reference_id = REPLACE(reference_id, 'BDR', 'PGD')
			WHERE name like 'BDR%' AND owner = 0;
		END IF;
	END;
	$$ LANGUAGE plpgsql;

	DO $$
	BEGIN
			--check if chart table contains labels withs values 'BDR Version and BDR Edition '
		IF EXISTS(
			SELECT * FROM pem.chart
			WHERE 'BDR Version' = ANY(labels) AND 'BDR Edition' = ANY(labels) AND owner = 0
		) THEN
			RAISE INFO '--- Updating VERSION name in column labels from BDR to PGD in chart table';
			UPDATE pem.chart
				SET labels = ARRAY['Node Name', 'Postgres Version', 'pglogical Version', 'PGD Version', 'PGD Edition']
			WHERE 'BDR Version' = ANY(labels) AND 'BDR Edition' = ANY(labels) AND owner = 0;
		END IF;
	END;
	$$ LANGUAGE plpgsql;

	DO $$
	BEGIN
		-- Check if probe_column table contains display_name containing BDR
		IF EXISTS(
					SELECT * FROM pem.probe p LEFT OUTER JOIN pem.probe_column pc ON (p.id = pc.probe_id)
					WHERE pc.display_name like 'BDR%' AND p.is_system_probe
		) THEN
			RAISE INFO '--- Updating display_name from BDR to PGD in probe_column';
			UPDATE pem.probe_column pc
				SET display_name = REPLACE(pc.display_name, 'BDR', 'PGD')
				FROM pem.probe p
				WHERE pc.display_name like 'BDR%' AND p.id = pc.probe_id;
		END IF;
	END;
	$$ LANGUAGE plpgsql;

	-- PEM-2843: Allow to hide the servers, agents, and tools
	ALTER TABLE pem.config ADD COLUMN IF NOT EXISTS role text DEFAULT NULL;
	COMMENT ON COLUMN pem.config.options IS 'Possible values for an enum type (selection/combo box)';
	COMMENT ON COLUMN pem.config.role IS 'Can only be modifitied by this role';

	-- RLS (Row Level Security) for the pem.config table
	DO $DO$
		DECLARE
			rls_supported boolean;
		BEGIN
			SELECT (count(*) = 1) INTO rls_supported FROM pg_catalog.pg_class WHERE relname = 'pg_policy' AND relnamespace = (SELECT oid FROM pg_catalog.pg_namespace WHERE nspname = 'pg_catalog');

			IF rls_supported THEN
				RAISE INFO 'RLS policies for pem.config...';
				EXECUTE $SQL$ ALTER TABLE pem.config ENABLE ROW LEVEL SECURITY $SQL$;

				DROP POLICY IF EXISTS pem_config_role_select ON pem.config;
				EXECUTE $SQL$
					CREATE POLICY pem_config_role_select
					ON pem.config
					FOR SELECT
					USING (true)
				$SQL$;

				DROP POLICY IF EXISTS pem_config_role_insert ON pem.config;
				EXECUTE $SQL$
					CREATE POLICY pem_config_role_insert
					ON pem.config
					FOR INSERT
						WITH CHECK (true)
				$SQL$;

				DROP POLICY IF EXISTS pem_config_role_update ON pem.config;
				EXECUTE $SQL$
						CREATE POLICY pem_config_role_update
						ON pem.config
						FOR UPDATE
						USING (
							role is NULL or pg_catalog.pg_has_role(role, 'member'::text)
						)
						WITH CHECK (true)
				$SQL$;

				DROP POLICY IF EXISTS pem_config_role_delete ON pem.config;
				EXECUTE $SQL$
					CREATE POLICY pem_config_role_delete
					ON pem.config
					FOR DELETE
						USING (role is NULL or pg_catalog.pg_has_role(role, 'member'::text))
				$SQL$;
			END IF;
		END
	$DO$ language 'plpgsql';

	INSERT INTO pem.config (param, value, unit, datatype, role) VALUES (
		'show_objects_with_no_team', 't', 't/f', 'bool', 'pem_admin'
	)
	ON CONFLICT ON CONSTRAINT config_pkey
	DO NOTHING;

	CREATE OR REPLACE FUNCTION pem.can_access_team(_owner OID, _team text)
	RETURNS boolean AS
	$BODY$
		SELECT
			-- team is not defined
			(
				SELECT (value = 't') AS value FROM pem.config WHERE param = 'show_objects_with_no_team' AND
				(_team IS NULL OR _team = '')
			) OR
			-- current user is the owner
			_owner = current_user::regrole::oid OR
			-- current user is pem_super_admin
			pg_catalog.pg_has_role('pem_super_admin', 'member') OR
			-- current user is a member of the team (or team does not exist)
			CASE WHEN EXISTS (
				SELECT 1 FROM pg_catalog.pg_roles AS t WHERE t.rolname = _team
			) THEN pg_catalog.pg_has_role(_team, 'member')
			ELSE false END;
	$BODY$ LANGUAGE 'sql';

	-- Only these server(s) are available, which meets following conditions:
	-- 1.  Active
	-- 2. team is accessible (Refer: pem.can_access_team)
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
			s.is_remote_monitoring AS is_remote_monitoring,
			s.efm_cluster_name AS efm_cluster_name,
			s.efm_service_name AS efm_service_name,
			s.efm_installation_path AS efm_installation_path,
			COALESCE(so.server_group_id, s.group_id, 1) AS group_id
		FROM (
			SELECT s.*, r.rolsuper AS rolsuper FROM pem.server s, pg_catalog.pg_roles r WHERE r.rolname = current_user
		) AS s
			LEFT OUTER JOIN pg_catalog.pg_roles o ON (o.oid = s.owner)
			LEFT OUTER JOIN pg_catalog.pg_roles t ON (t.rolname = s.team)
			LEFT JOIN pem.server_options so ON (s.id = so.server_id AND pem_user = current_user)
		WHERE
			-- Only active servers
			s.active AND pem.can_access_team(s.owner, s.team);

	-- Only these agent(s) are available, which meets following conditions:
	-- 1. Active
	-- AND (
	-- 2a. team is accessible (Refer: pem.can_access_team)
	-- OR
	-- 2b. One of the server bound with the agent is accessible.
	-- )
	CREATE OR REPLACE VIEW pem.avail_agents AS
		SELECT
			a.id AS id,
			a.agent_capability_list AS agent_capability_list,
			COALESCE(ao.description, a.description) AS description,
			a.active AS active,
			a.heartbeat_interval AS heartbeat_interval,
			a.alert_blackout AS alert_blackout,
			a.version AS version,
			a.platform AS platform,
			a.owner AS owner,
			a.team AS team,
			o.rolname AS agent_owner,
			COALESCE(ao.group_id, a.group_id, 0) AS group_id
		FROM (SELECT a.*, r.rolsuper AS rolsuper FROM pem.agent a, pg_catalog.pg_roles r WHERE r.rolname = current_user) AS a
			LEFT JOIN pem.agent_options ao ON (a.id = ao.agent_id AND pem_user = current_user)
			LEFT OUTER JOIN pg_catalog.pg_roles o ON (o.oid = a.owner)
			LEFT OUTER JOIN pg_catalog.pg_roles t ON (t.rolname = a.team)
		WHERE
			-- Only active agents
			a.active AND (
					pem.can_access_team(a.owner, a.team) OR
					-- Current user is having rights to view the server(s) bound with the agent
					EXISTS(
							SELECT 1 FROM pem.agent_server_binding asb
							JOIN pem.avail_servers asr ON (
									asr.id = asb.server_id AND asb.agent_id = a.id
							)
					)
			);

	-- Only these tool(s) are available, which meets following conditions:
	-- 1.  Active
	-- 2. team is accessible (Refer: pem.can_access_team)
	CREATE OR REPLACE VIEW pem.avail_tools AS
		SELECT
			a.id AS id,
			a.name,
			COALESCE(tos.description, a.description) AS description,
			a.options,
			a.active AS active,
			a.owner AS owner,
			a.team AS team,
			o.rolname AS tool_owner,
			a.gid
			--COALESCE(tos.group_id, a.group_id, 0) AS group_id
		FROM (SELECT a.*, r.rolsuper AS rolsuper FROM pem.tool a, pg_catalog.pg_roles r WHERE r.rolname = current_user) AS a
			LEFT JOIN pem.tool_options tos ON (a.id = tos.tool_id AND pem_user = current_user)
			LEFT OUTER JOIN pg_catalog.pg_roles o ON (o.oid = a.owner)
			LEFT OUTER JOIN pg_catalog.pg_roles t ON (t.rolname = a.team)
		WHERE
			-- Only active tools
			a.active AND pem.can_access_team(a.owner, a.team);

-- View to fetch extension level probes with respect to their version if specified
CREATE OR REPLACE VIEW pem.probe_target_extension_view AS
SELECT
	p.id AS probe_id, p.display_name AS probe_display_name,
	p.internal_name AS probe_internal_name, p.probe_key_list,
	p.applies_to_id,
	a.id AS agent_id, b.server_id, ocd.database_name AS database_name,
	ARRAY['server_id', 'database_name']::text[] AS parameter_name_list,
	ARRAY[b.server_id::text, ocd.database_name]::text[] AS parameter_value_list,
	p.collection_method,
	CASE
	WHEN pev.probe_code IS NOT NULL THEN TRIM(pev.probe_code)
	ELSE p.probe_code
	END AS probe_code,
	p.enabled_by_default, p.default_execution_frequency,
	p.default_lifetime,
	COALESCE(c.enabled, p.enabled_by_default) AS enabled,
	COALESCE(c.execution_frequency, p.default_execution_frequency)
		AS execution_frequency,
	COALESCE(c.lifetime, p.default_lifetime) AS lifetime,
	a.active AS agent_active,
	p.discard_history,
	p.is_system_probe
FROM
	pem.probe p
	CROSS JOIN pem.agent_server_binding b
	INNER JOIN pem.agent a ON b.agent_id = a.id
	INNER JOIN pem.server s ON b.server_id = s.id
	INNER JOIN pemdata.oc_extension oce ON b.server_id = oce.server_id
		AND p.extension_name = oce.extension_name
	INNER JOIN pemdata.oc_database ocd
		ON b.server_id = ocd.server_id
		AND oce.database_name = ocd.database_name
	LEFT JOIN pemdata.server_info sd ON b.server_id = sd.server_id
	LEFT OUTER JOIN pem.probe_extension_version pev
		ON p.id = pev.probe_id
		AND sd.server_version_id = pev.server_version_id
		AND oce.extension_version = pev.extension_version
	LEFT JOIN pem.probe_config_extension c
		ON p.id = c.probe_id AND b.server_id = c.server_id AND c.database_name = oce.database_name
WHERE
	p.target_type_id = 1000
	AND NOT p.deleted
	AND (p.agent_capability IS NULL
		OR p.agent_capability = ANY(a.agent_capability_list))
	AND p.internal_name NOT IN( SELECT UNNEST(CASE WHEN s.is_remote_monitoring THEN ARRAY['pg_hba_conf', 'data_log_file_analysis', 'wal_archive_status', 'log_configuration', 'efm_cluster_node_status', 'efm_cluster_info'] ELSE ARRAY[''] END))
	AND p.internal_name NOT IN( SELECT UNNEST(CASE WHEN a.agent_capability_list @> ARRAY['windows'] THEN ARRAY['efm_cluster_node_status', 'efm_cluster_info'] ELSE ARRAY[''] END))
	AND (p.collection_method != 'b' OR
		(p.collection_method ='b' AND (a.agent_capability_list @> ARRAY['allow_batch_probes'])
			AND ((strpos(a.platform, p.platform) != 0) OR (a.platform !~ 'windows' AND p.platform = 'unix'))))
	AND b.database NOT IN (SELECT UNNEST(b.exclude_databases))
	AND (p.any_extension_version OR pev.probe_code IS NOT NULL);

CREATE OR REPLACE FUNCTION pem.purge_probe_history(_pid integer)
  RETURNS void AS
$function$
DECLARE
	probe_curs     REFCURSOR;
	probe          RECORD;
	table_name     varchar := NULL;
	subquery       varchar;
	where_clause   varchar;
	combo_cnt      integer;
	parameter_list text[];
BEGIN

	SELECT count(*) INTO combo_cnt
	FROM pem.probe_objects_combo o WHERE o.pid = _pid;

	-- Let's not rush to things, do the purging in small chunks.
	combo_cnt := (ceil(combo_cnt::float / 5))::integer;
	-- We will run the purging exercise only for 1000 maximum combination
	-- ordered by purge time.
	IF combo_cnt > 1000 THEN
		combo_cnt := 1000;
	ELSE
		IF combo_cnt < 20 THEN
			combo_cnt := 20;
		END IF;
	END IF;

	SELECT
		'pemhistory.' || quote_ident(p.internal_name),
		CASE p.target_type_id
		WHEN 100 THEN ARRAY['agent_id']::text[]
		WHEN 150 THEN ARRAY['tool_id']::text[]
		WHEN 200 THEN ARRAY['server_id']::text[]
		WHEN 300 THEN ARRAY['server_id', 'database_name']::text[]
		WHEN 1000 THEN ARRAY['server_id', 'database_name']::text[]
		WHEN 400 THEN ARRAY['server_id', 'database_name', 'schema_name']::text[]
		END
		INTO table_name, parameter_list
	FROM pem.probe p
	WHERE p.id = _pid AND EXISTS (
		SELECT 1 FROM pg_class, pg_namespace
		WHERE pg_namespace.oid = pg_class.relnamespace AND
			pg_namespace.nspname = 'pemhistory' AND pg_class.relname = p.internal_name
	);

	IF table_name IS NULL THEN
		RETURN;
	END IF;

	OPEN probe_curs FOR EXECUTE '
		SELECT objects, lifetime
		FROM pem.probe_objects_combo
		WHERE pid = $1::integer
		ORDER BY purged_on NULLS FIRST LIMIT ' || combo_cnt
		USING _pid;

	LOOP
		FETCH NEXT FROM probe_curs INTO probe;
		EXIT WHEN probe IS NULL;

		where_clause := ' WHERE ';

		IF parameter_list IS NOT NULL THEN
			FOR i IN array_lower(parameter_list, 1)..array_upper(parameter_list, 1)
			LOOP
        IF probe.objects[i] is NULL THEN
            RAISE WARNING 'No object found for parameter_list[%] for probe (%) with (params: %, values: %)', i, _pid, array_to_string(parameter_list, ', ', '<NULL>'), array_to_string(probe.objects, ', ', '<NULL>');
        END IF;
				where_clause := where_clause || parameter_list[i] || ' = ' || pg_catalog.quote_literal(COALESCE(probe.objects[i]::text, '<NULL>')) || ' AND ';
			END LOOP;
		ELSE
				RAISE WARNING 'No parmaters are found for probe# %', p.id;
		END IF;

		subquery := 'SELECT recorded_time FROM ' || table_name || where_clause || 'recorded_time <= (now() - interval ''' || COALESCE(probe.lifetime, 7) || ' days'') ORDER BY recorded_time DESC LIMIT 1';
		where_clause := where_clause || ' recorded_time < (' || subquery || ')';

		EXECUTE 'DELETE FROM ' || table_name || where_clause;
		UPDATE pem.probe_objects_combo SET purged_on = now() WHERE pid = _pid AND objects = probe.objects;
	END LOOP;
	CLOSE probe_curs;
END;
$function$ LANGUAGE plpgsql;

-- This view creates the probe list even for the deleted agents/servers to
-- allow us to purge the history for them too.
CREATE OR REPLACE VIEW pem.probe_target_without_discard_history AS
SELECT
	p.id AS probe_id, p.internal_name AS probe_internal_name,
	p.target_type_id, ARRAY[a.id::text]::text[] AS parameter_value_list,
	COALESCE(c.lifetime, p.default_lifetime) AS lifetime
FROM
	(
		SELECT * FROM pem.probe
		WHERE  target_type_id = 100 AND NOT deleted AND NOT discard_history
	) AS p
	CROSS JOIN pem.agent a
	LEFT JOIN pem.probe_config_agent c
		ON p.id = c.probe_id AND a.id = c.agent_id
WHERE
	(
		p.agent_capability IS NULL OR
		p.agent_capability = ANY(a.agent_capability_list)
	) AND (
		CASE p.collection_method
		WHEN 'b' THEN a.agent_capability_list @> ARRAY['allow_batch_probes']
		WHEN 'w' THEN strpos(a.platform, 'windows') != 0
		ELSE TRUE
		END
	)
UNION ALL
SELECT
	p.id AS probe_id, p.internal_name AS probe_internal_name,
	p.target_type_id, ARRAY[s.id::text]::text[] AS parameter_value_list,
	COALESCE(c.lifetime, p.default_lifetime) AS lifetime
FROM
	(
		SELECT * FROM pem.probe
		WHERE  target_type_id = 200 AND NOT deleted AND NOT discard_history
	) AS p
	CROSS JOIN pem.server s
	LEFT JOIN pem.agent_server_binding b ON b.server_id = s.id
	LEFT JOIN pem.agent a ON b.agent_id = a.id
	LEFT JOIN pemdata.server_info sd ON s.id = sd.server_id
	LEFT JOIN pem.probe_server_version psv
		ON p.id = psv.probe_id AND sd.server_version_id = psv.server_version_id
	LEFT JOIN pem.probe_config_server c
		ON p.id = c.probe_id AND s.id = c.server_id
WHERE
	(
		p.agent_capability IS NULL OR a.agent_capability_list IS NULL OR
		p.agent_capability = ANY(a.agent_capability_list)
	) AND (
		p.any_server_version OR psv.probe_id IS NOT NULL
	) AND p.internal_name NOT IN(
		SELECT UNNEST(
			CASE
			WHEN s.is_remote_monitoring THEN
				ARRAY['pg_hba_conf', 'data_log_file_analysis', 'wal_archive_status', 'log_configuration', 'efm_cluster_node_status', 'efm_cluster_info']
			ELSE
				ARRAY['']
			END
		)
	) AND p.internal_name NOT IN(
		SELECT UNNEST(
			CASE
			WHEN a.agent_capability_list @> ARRAY['windows']
				THEN ARRAY['efm_cluster_node_status', 'efm_cluster_info']
			ELSE ARRAY[''] END
		)
	) AND (
		CASE p.collection_method
		WHEN 'b' THEN (
			a.agent_capability_list @> ARRAY['allow_batch_probes'] AND (
				strpos(a.platform, p.platform) != 0 OR (
					a.platform !~ 'windows' AND p.platform = 'unix'
				)
			)
		)
		ELSE TRUE
		END
	)
UNION ALL
SELECT
	p.id AS probe_id, p.internal_name AS probe_internal_name,
	p.target_type_id, ARRAY[s.id::text, ocd.database_name]::text[] AS parameter_value_list,
	COALESCE(c.lifetime, p.default_lifetime) AS lifetime
FROM
	(
		SELECT * FROM pem.probe
		WHERE  target_type_id = 300 AND NOT deleted AND NOT discard_history
	) AS p
	CROSS JOIN pem.server s
	LEFT JOIN pem.agent_server_binding b ON b.server_id = s.id
	LEFT JOIN pem.agent a ON b.agent_id = a.id
	LEFT JOIN pemdata.server_info sd ON s.id = sd.server_id
	LEFT JOIN pem.probe_server_version psv
		ON p.id = psv.probe_id AND sd.server_version_id = psv.server_version_id
	INNER JOIN (SELECT * FROM pemdata.oc_database WHERE connections_allowed) ocd
		ON s.id = ocd.server_id
	LEFT JOIN pem.probe_config_database c
		ON p.id = c.probe_id AND s.id = c.server_id AND
		ocd.database_name = c.database_name
WHERE
	(
		p.agent_capability IS NULL OR a.agent_capability_list IS NULL OR
		p.agent_capability = ANY(a.agent_capability_list)
	) AND (p.any_server_version OR psv.probe_id IS NOT NULL) AND (
		CASE p.collection_method
		WHEN 'b' THEN (
			a.agent_capability_list @> ARRAY['allow_batch_probes'] AND (
				strpos(a.platform, p.platform) != 0 OR (
					a.platform !~ 'windows' AND p.platform = 'unix'
				)
			)
		)
		ELSE TRUE
		END
	)
UNION ALL
SELECT
	p.id AS probe_id, p.internal_name AS probe_internal_name,
	p.target_type_id, ARRAY[
		s.id::text, oc.database_name, oc.schema_name
	]::text[] AS parameter_value_list,
	COALESCE(c.lifetime, p.default_lifetime) AS lifetime
FROM
	(
		SELECT * FROM pem.probe
		WHERE  target_type_id = 400 AND NOT deleted AND NOT discard_history
	) AS p
	CROSS JOIN pem.server s
	LEFT JOIN pem.agent_server_binding b ON b.server_id = s.id
	LEFT JOIN pem.agent a ON b.agent_id = a.id
	LEFT JOIN pemdata.server_info sd ON s.id = sd.server_id
	LEFT JOIN pem.probe_server_version psv
		ON p.id = psv.probe_id AND sd.server_version_id = psv.server_version_id
	INNER JOIN (SELECT * FROM pemdata.oc_database WHERE connections_allowed) ocd
		ON s.id = ocd.server_id
	INNER JOIN pemdata.oc_schema oc ON ocd.server_id = oc.server_id AND
		ocd.database_name = oc.database_name
	LEFT JOIN pem.probe_config_schema c ON p.id = c.probe_id AND
		s.id = c.server_id AND oc.database_name = c.database_name AND
		oc.schema_name = c.schema_name
WHERE
	(
		p.agent_capability IS NULL OR a.agent_capability_list IS NULL OR
		p.agent_capability = ANY(a.agent_capability_list)
	) AND (p.any_server_version OR psv.probe_id IS NOT NULL) AND (
		CASE p.collection_method
		WHEN 'b' THEN (
			a.agent_capability_list @> ARRAY['allow_batch_probes'] AND (
				strpos(a.platform, p.platform) != 0 OR (
					a.platform !~ 'windows' AND p.platform = 'unix'
				)
			)
		)
		ELSE TRUE
		END
	)
UNION ALL
SELECT
	p.id AS probe_id, p.internal_name AS probe_internal_name,
	p.target_type_id, ARRAY[s.id::text, ocd.database_name]::text[] AS parameter_value_list,
	COALESCE(c.lifetime, p.default_lifetime) AS lifetime
FROM
	(
		SELECT * FROM pem.probe
		WHERE  target_type_id = 1000 AND NOT deleted AND NOT discard_history
	) AS p
	CROSS JOIN pem.server s
	LEFT OUTER JOIN pem.agent_server_binding b ON b.server_id = s.id
	LEFT OUTER JOIN pem.agent a ON b.agent_id = a.id
	LEFT JOIN pemdata.server_info sd ON s.id = sd.server_id
	LEFT JOIN pem.probe_server_version psv
		ON p.id = psv.probe_id AND sd.server_version_id = psv.server_version_id
	INNER JOIN (SELECT * FROM pemdata.oc_database WHERE connections_allowed) ocd
		ON s.id = ocd.server_id
	LEFT JOIN pemdata.oc_extension oce ON b.server_id = oce.server_id
		AND oce.database_name = ocd.database_name
		AND p.extension_name = oce.extension_name
	LEFT JOIN pem.probe_extension_version pev
        ON p.id = pev.probe_id
        AND sd.server_version_id = pev.server_version_id
        AND oce.extension_version = pev.extension_version
	LEFT JOIN pem.probe_config_extension c
		ON p.id = c.probe_id AND s.id = c.server_id AND
		ocd.database_name = c.database_name
WHERE
	(
		p.agent_capability IS NULL OR a.agent_capability_list IS NULL OR
		p.agent_capability = ANY(a.agent_capability_list)
	) AND (p.any_server_version OR psv.probe_id IS NOT NULL) AND (
		CASE p.collection_method
		WHEN 'b' THEN (
			a.agent_capability_list @> ARRAY['allow_batch_probes'] AND (
				strpos(a.platform, p.platform) != 0 OR (
					a.platform !~ 'windows' AND p.platform = 'unix'
				)
			)
		)
		ELSE TRUE
		END
	)
UNION ALL
SELECT
	p.id AS probe_id, p.internal_name AS probe_internal_name,
	p.target_type_id, ARRAY[t.id::text]::text[] AS parameter_value_list,
	COALESCE(c.lifetime, p.default_lifetime) AS lifetime
FROM
	pem.probe p
	CROSS JOIN pem.tool t
	LEFT OUTER JOIN pem.agent_tool_binding b ON b.tool_id = t.id
	LEFT OUTER JOIN pem.agent a ON b.agent_id = a.id
	LEFT JOIN pem.probe_config_tool c
		ON p.id = c.probe_id AND t.id = c.tool_id
WHERE
	p.target_type_id = 150
	AND NOT p.deleted
	AND (p.agent_capability IS NULL OR a.agent_capability_list IS NULL
		OR p.agent_capability = ANY(a.agent_capability_list));

-- Resolved column not present error in bdr version 3.7.17
UPDATE pem.probe
SET probe_code = $SQL$SELECT node_name, camo_partner AS camo_partner_of, 'N/A' AS camo_origin_for, is_camo_partner_connected, is_camo_partner_ready, camo_transactions_resolved, apply_lsn, receive_lsn, apply_queue_size from bdr.group_camo_details$SQL$, any_extension_version = true
WHERE internal_name = 'bdr_group_camo_details';

UPDATE pem.probe
	SET any_extension_version = true,
	probe_code = $SQL$SELECT node_name, postgres_version, 'N/A' AS pglogical_version, bdr_version, bdr_edition FROM bdr.group_versions_details;$SQL$
	WHERE internal_name = 'bdr_group_versions_details';

UPDATE pem.probe
	SET any_extension_version = true
	WHERE internal_name = 'bdr_node_summary' OR internal_name = 'bdr_worker_errors';

DELETE FROM pem.probe_extension_version
    WHERE probe_id = (SELECT id FROM pem.probe WHERE internal_name = 'bdr_group_camo_details')
	AND extension_version = '3.7.15';

INSERT INTO pem.probe_extension_version
    (probe_id, server_version_id, extension_version, probe_code)
SELECT
    (SELECT id FROM pem.probe WHERE internal_name = 'bdr_node_summary'),
    v.version,
    e.version,
    'SELECT node_name, node_group_name, peer_state_name, peer_target_state_name, sub_repsets FROM bdr.node_summary'
FROM (
    VALUES (11100), (11200), (11300), (11400), (21100), (21200), (21300), (21400)
) v(version) CROSS JOIN (
	VALUES ('3.7.17'), ('3.7.16'), ('3.7.15'), ('3.7.14'), ('3.7.13.1'), ('3.7.13'), ('3.7.12'), ('3.7.11'), ('3.7.10'), ('3.7.9'), ('3.7.8'), ('3.7.7'), ('3.7.6'), ('3.7.5'), ('3.7.4'), ('3.7.3'), ('3.7.2'), ('3.6.19'), ('3.6.18'), ('3.6.17'), ('3.6.16'), ('3.6.15'), ('3.6.14'), ('3.6.12')
) e(version)
ON CONFLICT ON CONSTRAINT probe_extension_version_unique DO UPDATE
	SET probe_code = 'SELECT node_name, node_group_name, peer_state_name, peer_target_state_name, sub_repsets FROM bdr.node_summary'
	WHERE
		pem.probe_extension_version.probe_id = (SELECT id FROM pem.probe WHERE internal_name = 'bdr_node_summary') AND
		pem.probe_extension_version.extension_version = ANY(ARRAY['3.7.17', '3.7.16', '3.7.15', '3.7.14', '3.7.13.1', '3.7.13', '3.7.12', '3.7.11', '3.7.10', '3.7.9', '3.7.8', '3.7.7', '3.7.6', '3.7.5', '3.7.4', '3.7.3', '3.7.2', '3.6.19', '3.6.18', '3.6.17', '3.6.16', '3.6.15', '3.6.14', '3.6.12']);

-- PGD Group Camo Details
INSERT INTO pem.probe_extension_version
    (probe_id, server_version_id, extension_version, probe_code)
SELECT
    (SELECT id FROM pem.probe WHERE internal_name = 'bdr_group_camo_details'),
    v.version,
    e.version,
    'SELECT node_name, camo_partner_of, camo_origin_for, is_camo_partner_connected, is_camo_partner_ready, camo_transactions_resolved, apply_lsn, receive_lsn, apply_queue_size from bdr.group_camo_details'
FROM (
    VALUES (11100), (11200), (11300), (11400), (11500), (21100), (21200), (21300), (21400), (21500)
) v(version) CROSS JOIN (
	VALUES ('3.7.17'), ('3.7.16'), ('3.7.15'), ('3.7.14'), ('3.7.13.1'), ('3.7.13'), ('3.7.12'), ('3.7.11'), ('3.7.10'), ('3.7.9'), ('3.7.8'), ('3.7.7'), ('3.7.6'), ('3.7.5'), ('3.7.4'), ('3.7.3'), ('3.7.2'), ('3.6.19'), ('3.6.18'), ('3.6.17'), ('3.6.16'), ('3.6.15'), ('3.6.14'), ('3.6.12')
) e(version)
ON CONFLICT ON CONSTRAINT probe_extension_version_unique DO UPDATE
	SET probe_code = 'SELECT node_name, camo_partner_of, camo_origin_for, is_camo_partner_connected, is_camo_partner_ready, camo_transactions_resolved, apply_lsn, receive_lsn, apply_queue_size from bdr.group_camo_details'
	WHERE
		pem.probe_extension_version.probe_id = (SELECT id FROM pem.probe WHERE internal_name = 'bdr_group_camo_details') AND
		pem.probe_extension_version.extension_version = ANY(ARRAY['3.7.17', '3.7.16', '3.7.15', '3.7.14', '3.7.13.1', '3.7.13', '3.7.12', '3.7.11', '3.7.10', '3.7.9', '3.7.8', '3.7.7', '3.7.6', '3.7.5', '3.7.4', '3.7.3', '3.7.2', '3.6.19', '3.6.18', '3.6.17', '3.6.16', '3.6.15', '3.6.14', '3.6.12']);

-- PGD Group Subscription Summary
UPDATE pem.probe
    SET probe_code = $SQL$select origin_node_name, target_node_name, last_xact_replay_timestamp, NULLIF(sub_lag_seconds,'')::text as sub_lag_seconds from bdr.group_subscription_summary;$SQL$
    WHERE internal_name = 'bdr_group_subscription_summary';

END TRANSACTION;
