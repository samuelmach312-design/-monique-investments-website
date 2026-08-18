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
'SELECT 201502271::integer;'
  LANGUAGE 'sql' IMMUTABLE;

-- Add new column "efm_cluster_name" to pem.server
ALTER TABLE pem.server ADD COLUMN efm_cluster_name text DEFAULT NULL;
COMMENT ON COLUMN pem.server.efm_cluster_name IS 'Cluster name of EFM';
-- Add new column "efm_service_name" to pem.server
ALTER TABLE pem.server ADD COLUMN efm_service_name text DEFAULT NULL;
COMMENT ON COLUMN pem.server.efm_service_name IS 'Service name of EFM';
-- Add new column "efm_installation_path" to pem.server
ALTER TABLE pem.server ADD COLUMN efm_installation_path text DEFAULT NULL;
COMMENT ON COLUMN pem.server.efm_installation_path IS 'Installation Path of EFM';

-- Add new column "is_chartable" to pem.probe
ALTER TABLE pem.probe ADD COLUMN is_chartable boolean NOT NULL DEFAULT true;
UPDATE pem.probe SET is_chartable = false WHERE internal_name IN ('package_catalog', 'auto_discover_servers', 'installed_packages', 'data_log_file_analysis', 'audit_configuration', 'log_configuration');

GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE pem.probe_config_server TO pem_agent;

CREATE OR REPLACE FUNCTION pem.server_efm_probe_update() RETURNS trigger AS $$
DECLARE
	efm_cluster_probe_id integer;
	efm_node_probe_id integer;
	is_windows_server boolean;
BEGIN
	SELECT agent_capability_list @> ARRAY['windows'] INTO is_windows_server FROM pem.agent WHERE id = (SELECT agent_id FROM pem.agent_server_binding WHERE server_id = NEW.id);
	SELECT id INTO efm_node_probe_id FROM pem.probe WHERE internal_name = 'efm_cluster_node_status';
	SELECT id INTO efm_cluster_probe_id FROM pem.probe WHERE internal_name = 'efm_cluster_info';
	-- If cluster name is not null then either we need to insert or update
	-- the pem.probe_config_server table and if the value is NULL then we
	-- need to delete the entry fron the table.
	IF (NEW.efm_cluster_name IS NOT NULL AND NEW.efm_cluster_name != '' AND NOT NEW.is_remote_monitoring AND NOT is_windows_server)THEN
		INSERT INTO pem.probe_config_server(probe_id, server_id, enabled) SELECT efm_cluster_probe_id, NEW.id, true
		WHERE NOT EXISTS (SELECT 1 FROM pem.probe_config_server WHERE probe_id = efm_cluster_probe_id AND server_id = NEW.id);
		INSERT INTO pem.probe_config_server(probe_id, server_id, enabled) SELECT efm_node_probe_id, NEW.id, true
		WHERE NOT EXISTS (SELECT 1 FROM pem.probe_config_server WHERE probe_id = efm_node_probe_id AND server_id = NEW.id);
	ELSE
		DELETE FROM pem.probe_config_server WHERE probe_id = efm_cluster_probe_id AND server_id = NEW.id;
		DELETE FROM pem.probe_config_server WHERE probe_id = efm_node_probe_id AND server_id = NEW.id;
	END IF;
	RETURN NULL;
END
$$ LANGUAGE plpgsql;

CREATE TRIGGER server_efm_cluster_name
	AFTER INSERT OR UPDATE ON pem.server
	FOR EACH ROW EXECUTE PROCEDURE pem.server_efm_probe_update();

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
		s.efm_installation_path AS efm_installation_path
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

--
-- Probe: Failover Manager Node Status
--
INSERT INTO pem.probe
        (display_name, internal_name, collection_method, target_type_id,
         agent_capability, enabled_by_default, force_enabled,
     default_execution_frequency, default_lifetime, any_server_version, probe_code)
VALUES
        ('Failover Manager Node Status', 'efm_cluster_node_status', 'i', 200, NULL, false, false, 300,
          7, false, 'efm_cluster_node_status');

INSERT INTO pem.probe_column
        (probe_id, internal_name, display_name, display_position, classification,
        sql_data_type, unit_of_value, calculate_pit, discard_history, pit_by_default, is_graphable)
SELECT
        (SELECT max(id) FROM pem.probe),
        v.internal_name, v.display_name, v.display_position, v.classification,
        v.sql_data_type, v.unit_of_value, v.calculate_pit, v.discard_history, v.pit_by_default, v.is_graphable
FROM
        (VALUES
		('efm_ip_address',   'IP Address',          1, 'k', 'text', '', false, false, false, false),
		('efm_agent_type',   'Agent Type',          2, 'm', 'text', '', false, false, false, false),
		('efm_agent_status', 'Agent Staus',         3, 'm', 'text', '', false, false, false, false),
		('efm_db_status',    'DB Status',           4, 'm', 'text', '', false, false, false, false),
		('efm_status_info',  'Staus Information',   5, 'm', 'text', '', false, false, false, false),
		('efm_xlog_loc',     'XLog Location',       6, 'm', 'text', '', false, false, false, false),
		('efm_xlog_info',    'XLog Information',    7, 'm', 'text', '', false, false, false, false)
        ) v(internal_name, display_name, display_position, classification,
                sql_data_type, unit_of_value, calculate_pit, discard_history, pit_by_default, is_graphable);

INSERT INTO pem.probe_server_version
    (probe_id, server_version_id, probe_code)
SELECT
        (SELECT max(id) FROM pem.probe), v.version, NULL
FROM
        (VALUES (10902), (10903), (10904), (20902), (20903), (20904))
                v(version);

--
-- Probe: Failover Manager Cluster Info
--
INSERT INTO pem.probe
        (display_name, internal_name, collection_method, target_type_id,
         agent_capability, enabled_by_default, force_enabled,
     default_execution_frequency, default_lifetime, any_server_version, probe_code)
VALUES
        ('Failover Manager Cluster Info', 'efm_cluster_info', 'i', 200, NULL, false, false, 300,
          7, false, 'efm_cluster_info');

INSERT INTO pem.probe_column
        (probe_id, internal_name, display_name, display_position, classification,
        sql_data_type, unit_of_value, calculate_pit, discard_history, pit_by_default, is_graphable)
SELECT
        (SELECT max(id) FROM pem.probe),
        v.internal_name, v.display_name, v.display_position, v.classification,
        v.sql_data_type, v.unit_of_value, v.calculate_pit, v.discard_history, v.pit_by_default, v.is_graphable
FROM
        (VALUES
		('efm_allowed_node_list',     'Allowed Node List',     1, 'm', 'text[]', '', false, false, false, false),
		('efm_standby_priority_list', 'Standby Priority List', 2, 'm', 'text[]', '', false, false, false, false),
		('efm_running',               'EFM Running',           3, 'm', 'boolean', '', false, false, false, false),
		('efm_messages',              'Messages',              4, 'm', 'text', '', false, false, false, false)
        ) v(internal_name, display_name, display_position, classification,
                sql_data_type, unit_of_value, calculate_pit, discard_history, pit_by_default, is_graphable);

INSERT INTO pem.probe_server_version
    (probe_id, server_version_id, probe_code)
SELECT
        (SELECT max(id) FROM pem.probe), v.version, NULL
FROM
        (VALUES (10902), (10903), (10904), (20902), (20903), (20904))
                v(version);

SELECT pem.create_data_and_history_tables();

INSERT INTO pem.config VALUES ('dash_efm_timeout', 300, 'seconds', 'integer');
INSERT INTO pem.chart(id, cid, fid, type, level, name, owner, shared, ref_cnt, reload, summary, labels, params, rwlimit_span_param, ref_timeout_param) VALUES
(88, 15, 88, 'TB', ARRAY[200], 'Failover Manager Node Status', 0,  NULL,  1, 50000,   NULL, ARRAY['Agent Type', 'Address', 'Agent', 'DB', 'XLog Location', 'Status Information', 'XLog Information'], ARRAY['server_id'], NULL, 'dash_efm_timeout'),
(89, 15, 89, 'TE', ARRAY[200], 'Failover Manager Cluster Info', 0,  NULL,  1, 50000,   NULL, NULL, ARRAY['server_id'], NULL, 'dash_efm_timeout');
INSERT INTO pem.chart_func(id, type, func, r_sys_obj) VALUES
	(88, 'Q', E'
	SELECT
		efm_agent_type AS "Agent Type", efm_ip_address AS "Address",
		efm_agent_status AS "Agent", efm_db_status AS "DB",
		efm_xlog_loc AS "XLog Loc", efm_status_info AS "Status Info",
		efm_xlog_info AS "XLog Info"
	FROM
		pemdata.efm_cluster_node_status
	WHERE server_id = $1::int4', false),
	(89, 'Q', E'SELECT
    		xmlelement(name table,
        	xmlattributes(''pem-chart-table pem-element'' AS class, ''min-width:75%;'' AS style),
        	xmlelement(name thead,
        	    xmlelement(name tr,
        	        xmlelement(name th,
                   	 xmlattributes(''pem-chart-th pem-element'' AS class),
                   	 ''Properties''),
                	xmlelement(name th,
                    	xmlattributes(''pem-chart-th pem-element'' AS class),
                    	''Values''))),
        	xmlelement(name tbody,
            	xmlelement(name tr,
                	xmlelement(name td,
                    	xmlattributes(''pem-chart-td'' AS class),
                    	''Cluster Name''),
                xmlelement(name td,
                    xmlattributes(''pem-chart-td'' AS class),
                    ps.efm_cluster_name)),
            	xmlelement(name tr,
                xmlelement(name td,
                    xmlattributes(''pem-chart-td'' AS class),
                    ''Failover Manager Agent Running Status''),
                xmlelement(name td,
                    xmlattributes(''pem-chart-td'' AS class),
                    CASE WHEN pe.efm_running = true THEN ''UP'' ELSE ''DOWN'' END)),
            	xmlelement(name tr,
                xmlelement(name td,
                    xmlattributes(''pem-chart-td'' AS class),
                    ''Allowed Node List''),
                xmlelement(name td,
                    xmlattributes(''pem-chart-td'' AS class),
                    array_to_string(pe.efm_allowed_node_list, '', ''))),
            	xmlelement(name tr,
                xmlelement(name td,
                    xmlattributes(''pem-chart-td'' AS class),
                    ''Standby Priority List''),
                xmlelement(name td,
                    xmlattributes(''pem-chart-td'' AS class),
                    array_to_string(pe.efm_standby_priority_list, '', ''))),
            	xmlelement(name tr,
                xmlelement(name td,
                    xmlattributes(''pem-chart-td'' AS class),
                    ''Cluster Status Message''),
                xmlelement(name td,
                    xmlattributes(''pem-chart-td'' AS class),
                    pe.efm_messages))))
FROM
    pemdata.efm_cluster_info pe
    LEFT JOIN pem.server ps ON (ps.id = pe.server_id)
WHERE pe.server_id = $1::int;', false);
INSERT INTO pem.tbl_chart (cid, type) VALUES (88, 'D');

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
	p.discard_history,
	p.is_system_probe
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
	p.discard_history,
	p.is_system_probe
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
	AND p.internal_name NOT IN( SELECT UNNEST(CASE WHEN s.is_remote_monitoring THEN ARRAY['pg_hba_conf', 'data_log_file_analysis', 'wal_archive_status', 'log_configuration', 'efm_cluster_node_status', 'efm_cluster_info'] ELSE ARRAY[''] END))
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
	p.discard_history,
	p.is_system_probe
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
	p.discard_history,
	p.is_system_probe
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
	p.discard_history,
	p.is_system_probe
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
	p.discard_history,
	p.is_system_probe
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
	p.discard_history,
	p.is_system_probe
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
	p.discard_history,
	p.is_system_probe
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
	p.discard_history,
	p.is_system_probe
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

COMMIT TRANSACTION;
