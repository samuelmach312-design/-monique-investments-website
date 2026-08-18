/***************************************************************************
 *
 * Postgres Enterprise Manager
 *
 * Copyright (C) 2010 - 2025, EnterpriseDB Corporation. All rights reserved.
 *
 ***************************************************************************/

-- NOTE: This sql file is responsible for PEM 9.2.0 schema upgrade.

BEGIN TRANSACTION;

CREATE OR REPLACE FUNCTION pem.schema_version()
  RETURNS integer AS
'SELECT 202305251::integer;'
  LANGUAGE 'sql' IMMUTABLE;
COMMENT ON FUNCTION pem.schema_version() IS 'Returns the version number of the PEM schema';

-- Update the database_size probe to add tablespace_name details

UPDATE pem.chart_func SET func = '
SELECT
$$Replication Status: $$ ||
	COALESCE((
		SELECT
			CASE
			WHEN psh.last_heartbeat IS NULL OR pa.heartbeat_interval IS NULL THEN $$Unknown$$
			WHEN psh.last_heartbeat < (now() - (pa.heartbeat_interval * 2 * ''1 second''::interval)) THEN $$Stopped$$
			WHEN pstrl.replication_paused THEN $$Paused$$ ELSE $$Running$$
			END
		FROM pemdata.streaming_replication_lag_time pstrl
		LEFT OUTER JOIN pem.server_heartbeat psh ON (pstrl.server_id=psh.server_id)
		LEFT OUTER JOIN pem.agent_server_binding pasb ON (pstrl.server_id = pasb.server_id)
        LEFT OUTER JOIN pem.avail_agents pa ON (pasb.agent_id = pa.id AND psh.agent_id = pa.id)
        LEFT OUTER JOIN pem.agent_heartbeat pah ON (pah.agent_id = pasb.agent_id)
		WHERE pstrl.server_id = $1
	), $$Unknown$$)'
WHERE id = 83;

-- PEM-3992 removed the agent status from efm_cluster_node_status
UPDATE pem.chart_func SET func=E'
        SELECT
            efm_agent_type AS "Agent Type", efm_ip_address AS "Address",
            efm_db_status AS "DB",
            efm_xlog_loc AS "XLog Loc", efm_xlog_receive AS "XLog Receive",
            efm_status_info AS "Status Info", efm_xlog_info AS "XLog Info",
            efm_vip AS "Virtual IP Address", efm_vip_status AS "VIP Status"
        FROM
            pemdata.efm_cluster_node_status
        WHERE server_id = $1::int4'
WHERE dep_probes='{efm_cluster_node_status}';

DROP FUNCTION IF EXISTS pem.create_agent (varchar, integer);

-- Create an agent
CREATE OR REPLACE FUNCTION pem.create_agent (varchar, integer, bool DEFAULT false)
RETURNS integer AS $$
DECLARE
	agent_id          integer;
	agent_name        varchar;
	sql               varchar;
	agent_description varchar;
	id_exist          boolean;
	role_exist        boolean;
	is_active         boolean := false;
BEGIN
	agent_description := $1;
	id_exist := false;
	role_exist := false;

	SELECT true, active INTO id_exist, is_active FROM pem.agent WHERE id = $2;
	SELECT id INTO agent_id FROM pem.agent ORDER BY id DESC LIMIT 1 FOR UPDATE;

	IF id_exist THEN
		IF $3 IS true AND is_active IS true THEN
			RAISE EXCEPTION
				'An active agent is already present with id (#%). Please use another id.',
				$2;
		END IF;
		UPDATE pem.agent SET (active, description) = ('t', agent_description) WHERE id = $2;
		agent_id := $2;
	ELSE
		-- Fetch the greatest id again as parallel transaction may already have inserted a new id.
		SELECT id INTO agent_id FROM pem.agent ORDER BY id DESC LIMIT 1;

		IF agent_id IS NULL THEN
			agent_id := 1;
		ELSE
			agent_id := agent_id + 1;
		END IF;

		IF $2 != -1 THEN
			INSERT INTO pem.agent(id, agent_capability_list, description) VALUES ($2, '{}', agent_description) RETURNING id INTO agent_id;
		ELSE
			INSERT INTO pem.agent(id, agent_capability_list, description) VALUES (agent_id, '{}', agent_description) RETURNING id INTO agent_id;
		END IF;

		agent_name := 'agent' || agent_id;

		SELECT true INTO role_exist FROM pg_catalog.pg_roles WHERE rolname = agent_name;
		IF role_exist THEN
			RAISE NOTICE 'ROLE % already exist', agent_name;
		ELSE
			EXECUTE 'CREATE ROLE ' || agent_name  || ' WITH LOGIN';
		END IF;

		sql := 'GRANT pem_agent TO ' || agent_name;
		EXECUTE sql;
	END IF;

	RETURN agent_id;
END;
$$ LANGUAGE plpgsql;

COMMIT TRANSACTION;
