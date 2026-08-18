/***************************************************************************
 *
 * Postgres Enterprise Manager
 *
 * Copyright (C) 2010 - 2025, EnterpriseDB Corporation. All rights reserved.
 *
 ***************************************************************************/

-- NOTE: This sql file is responsible for PEM 9.0.0 schema upgrade.

BEGIN TRANSACTION;
	CREATE OR REPLACE FUNCTION pem.schema_version() RETURNS integer AS
		'SELECT 202212091::integer;'
	LANGUAGE 'sql' IMMUTABLE;

-- Show only two decimal point for the 'CPU utilization' alert template. (PEM-3854)
UPDATE pem.alert_template SET info_sql = $SQL$
	SELECT a.description AS "Agent name",u.core_id AS "Core ID", ROUND(u.load_percentage::decimal, 2)::text AS "Load percentage",u.recorded_time AS "Recorded time"
	FROM pemdata.cpu_usage AS u JOIN pem.agent a ON u.agent_id = a.id
	WHERE u.agent_id = '${agent_id}'
	ORDER BY u.load_percentage DESC; $SQL$
WHERE is_system_template AND display_name = 'CPU utilization';

UPDATE pem.chart
SET labels = ARRAY[
	'', 'Blackout', 'Name', 'Status', 'Alerts', 'Version', 'Processes',
	'Threads', 'CPU Utilization (%)', 'Memory Utilization (%)',
	'Swap Utilization (%)', 'Disk Utilization'
]
WHERE id = 2;

-- Function to give lag bytes if any of the replica lag behind the primary in streaming replication
-- parameter 1 - User given bytes in MB to generate alert
-- parameter 2 - server id
-- parameter 3 - 1- write location, 2- flush location, 3 - replay location
CREATE OR REPLACE FUNCTION pem.number_replication_lag_bytes(integer, integer, integer)
RETURNS bigint AS '
	SELECT
		count(*) as cnt
	FROM
		pemdata.streaming_replication
	WHERE
		server_id = $2 AND
		CASE $3
		WHEN 1 THEN floor(sent_location - write_location)/(1024*1024) > CAST($1 As BIGINT)
		WHEN 2 THEN floor(sent_location - flush_location)/(1024*1024) > CAST($1 As BIGINT)
		WHEN 3 THEN floor(sent_location - replay_location)/(1024*1024) > CAST($1 As BIGINT)
		ELSE false
		END
' LANGUAGE 'sql';

CREATE OR REPLACE FUNCTION pem.streaming_replication_lag_info(integer, integer)
RETURNS text AS
$SQL$
	SELECT array_to_string(array_agg(sr.host_info || ', ' || sr.lag_info), '\n') FROM (
		SELECT
			(ROW_NUMBER() OVER (ORDER BY client_addr, client_port)::text || 'Host: ' || client_addr || ':' || client_port::text) AS host_info,
			CASE $2
			WHEN 1 THEN 'Write Lag (MB): ' || ROUND((sent_location - write_location)/(1024*1024), 2)::text
			WHEN 2 THEN 'Flush Lag (MB): ' || ROUND((sent_location - flush_location)/(1024*1024), 2)::text
			WHEN 3 THEN 'Flush Lag (MB): ' || ROUND((sent_location - replay_location)/(1024*1024), 2)::text
			ELSE '??'
			END AS lag_info
		FROM pemdata.streaming_replication WHERE server_id = $1
	) sr;
$SQL$ LANGUAGE 'sql';

UPDATE pem.alert_template
SET info_sql = $sql$SELECT pem.streaming_replication_lag_info(${server_id}, 1);$sql$
WHERE display_name = 'Number of replica servers lag behind the primary by write location' AND is_system_template;

UPDATE pem.alert_template
SET info_sql = $sql$SELECT pem.streaming_replication_lag_info(${server_id}, 2);$sql$
WHERE display_name = 'Number of replica servers lag behind the primary by flush location' AND is_system_template;

UPDATE pem.alert_template
SET info_sql = $sql$SELECT pem.streaming_replication_lag_info(${server_id}, 3);$sql$
WHERE display_name = 'Number of replica servers lag behind the primary by replay location' AND is_system_template;

DROP FUNCTION IF EXISTS pem.email_write_lag_streaming_replication();
DROP FUNCTION IF EXISTS pem.email_replay_lag_streaming_replication();
DROP FUNCTION IF EXISTS pem.email_flush_lag_streaming_replication();

CREATE OR REPLACE FUNCTION pem.can_access_team(_owner OID, _team text)
RETURNS boolean AS
$$
    SELECT
        (
            -- team is not defined
            (SELECT (value = 't') AS value FROM pem.config WHERE param = 'show_objects_with_no_team') AND
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
        ELSE false
        END;
$$ LANGUAGE 'sql';

-- Only these server(s) are available, which meets following conditions:
-- 1.  Active
-- 2.  current user is member of the 'team'
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
		s.owner::regrole::name AS server_owner,
		s.is_remote_monitoring AS is_remote_monitoring,
		s.efm_cluster_name AS efm_cluster_name,
		s.efm_service_name AS efm_service_name,
		s.efm_installation_path AS efm_installation_path,
		COALESCE(so.server_group_id, s.group_id, 1) AS group_id
	FROM pem.server s
		LEFT JOIN pem.server_options so ON (s.id = so.server_id AND pem_user = current_user)
	WHERE
		-- Only active servers
		s.active AND
		pem.can_access_team(s.owner, s.team);

-- Only these agent(s) are available, which meets following conditions:
-- 1. Active
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
		a.owner::regrole::name AS agent_owner,
		COALESCE(ao.group_id, a.group_id, 0) AS group_id
	FROM pem.agent a
		LEFT JOIN pem.agent_options ao ON (a.id = ao.agent_id AND pem_user = current_user)
	WHERE
		-- Only active agents
		a.active AND (
			pem.can_access_team(a.owner, a.team) OR
			pg_catalog.pg_has_role('pem_agent', 'member'::text) OR
			id in (
				SELECT DISTINCT(agent_id)
				FROM pem.agent_server_binding
				WHERE server_id in (SELECT id FROM pem.server)
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
		a.owner::regrole::name AS tool_owner,
		a.gid
		--COALESCE(tos.group_id, a.group_id, 0) AS group_id
	FROM pem.tool a
		LEFT JOIN pem.tool_options tos ON (a.id = tos.tool_id AND pem_user = current_user)
	WHERE
		-- Only active tools
		a.active AND pem.can_access_team(a.owner, a.team);

END TRANSACTION;
