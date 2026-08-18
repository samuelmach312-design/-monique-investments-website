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
'SELECT 201404301::integer;'
  LANGUAGE 'sql' IMMUTABLE;

ALTER TABLE pem.agent ADD COLUMN owner oid;
ALTER TABLE pem.agent ADD COLUMN team text;
COMMENT ON COLUMN pem.agent.owner IS 'The owner of the registered agent';
COMMENT ON COLUMN pem.agent.team IS 'Defines the visibility of the agent in particular role/team';

UPDATE pem.agent SET owner = (SELECT oid FROM pg_catalog.pg_roles WHERE rolname = current_user);

CREATE OR REPLACE FUNCTION pem.agent_insertion() RETURNS trigger AS $$
DECLARE
	curr_user_oid oid;
BEGIN
	IF NEW.owner IS NULL THEN
		SELECT oid INTO curr_user_oid FROM pg_catalog.pg_roles WHERE rolname = current_user;
		NEW.owner := curr_user_oid;
	END IF;
	RETURN NEW;
END
$$ LANGUAGE 'plpgsql';

CREATE TRIGGER agent_insertion
	BEFORE INSERT ON pem.agent
	FOR EACH ROW EXECUTE PROCEDURE pem.agent_insertion();

-- Only these agent(s) are available, which meets following conditions:
-- 1.  Active
-- 2a. current_user is a superuser.
-- OR
-- 2b. No team is specified.
-- OR
-- 2c. Current user is the owner
-- OR
-- 2d. Current user is the member of the specified team/role.
-- OR
-- 2e. Current user is having rights to view the server.

CREATE OR REPLACE VIEW pem.avail_agents AS
	SELECT
		a.id AS id,
		a.agent_capability_list AS agent_capability_list,
		a.description AS description,
		a.active AS active,
		a.heartbeat_interval AS heartbeat_interval,
		a.alert_blackout AS alert_blackout,
		a.version AS version,
		a.platform AS platform,
		a.owner AS owner,
		a.team AS team,
		o.rolname AS agent_owner
	FROM (SELECT a.*, r.rolsuper AS rolsuper FROM pem.agent a, pg_catalog.pg_roles r WHERE r.rolname = current_user) AS a
		LEFT OUTER JOIN pg_catalog.pg_roles o ON (o.oid = a.owner)
		LEFT OUTER JOIN pg_catalog.pg_roles t ON (t.rolname = a.team)
	WHERE
	    -- Only active agents
		a.active AND
		-- Is a superuser
		(a.rolsuper OR
			-- No team provided
			a.team IS NULL OR a.team = '' OR
			-- Owner of the agent
			o.rolname = current_user OR
			-- Valid team provided and current_user is member of the it
			(t.oid IS NOT NULL AND pg_catalog.pg_has_role(a.team, 'member'))) OR
		-- Current user is having rights to view the server.
		EXISTS(SELECT 1 FROM pem.agent_server_binding asb JOIN pem.avail_servers asr ON (asr.id = asb.server_id) AND asb.agent_id = a.id);

UPDATE pem.chart_func SET func = E'WITH agent_list AS (
	SELECT
		pa.id AS id, pa.active AS active, pah.agent_id, pah.last_heartbeat, pa.heartbeat_interval
	FROM
		pem.avail_agents pa
		LEFT OUTER JOIN pem.agent_heartbeat pah ON (pa.id = pah.agent_id)
),
server_list AS (
	SELECT
		ps.id AS server_id, psh.last_heartbeat AS server_last_heartbeat,
		pa.active AS agent_active, pah.last_heartbeat AS agent_last_heartbeat,
		pa.heartbeat_interval AS heartbeat_interval
	FROM
		pem.avail_servers ps
		LEFT OUTER JOIN pem.server_heartbeat psh ON (ps.id = psh.server_id)
		LEFT OUTER JOIN pem.agent_server_binding pasb ON (ps.id = pasb.server_id)
		LEFT OUTER JOIN pem.avail_agents pa ON (pasb.agent_id = pa.id AND psh.agent_id = pa.id)
		LEFT OUTER JOIN pem.agent_heartbeat pah ON (pah.agent_id = pasb.agent_id)
)
SELECT
	id,
	label,
	count
FROM
	(
		SELECT
			1 AS id, ''Agents Up'' AS label, true AS required, count(id) AS count
		FROM
			agent_list
		WHERE
			active = TRUE AND
			agent_id IS NOT NULL AND
			last_heartbeat < now() AND
			last_heartbeat > (now() - (heartbeat_interval * 2 * ''1 second''::interval))
		UNION
		SELECT
			2 AS id, ''Agents Down'' AS label, true AS required, count(id) AS count
		FROM
			agent_list
		WHERE
			active = TRUE AND
			agent_id IS NOT NULL AND
			last_heartbeat < (now() - (heartbeat_interval * 2 * ''1 second''::interval))
		UNION
		SELECT
			3 AS id, ''Agents Unknown'' AS label, false AS required, count(id) AS count
		FROM
			agent_list
		WHERE
			active = TRUE AND
			agent_id IS NULL
		UNION
		SELECT
			4 AS id, ''Servers Up'' AS label, true AS required, count(server_id) AS count
		FROM
			server_list
		WHERE
			agent_active IS NOT NULL AND agent_active AND
			server_last_heartbeat IS NOT NULL AND
			server_last_heartbeat < now() AND
			server_last_heartbeat > (now() - (heartbeat_interval * 2 * ''1 second''::interval))
		UNION
		SELECT
			5 AS id, ''Servers Down'' AS label, true AS required, count(server_id) AS count
		FROM
			server_list
		WHERE
			agent_active IS NOT NULL AND agent_active AND
			agent_last_heartbeat IS NOT NULL AND
			agent_last_heartbeat < now() AND
			agent_last_heartbeat > (now() - (heartbeat_interval * 2 * ''1 second''::interval)) AND
			server_last_heartbeat IS NOT NULL AND
			server_last_heartbeat < (now() - (heartbeat_interval * 2 * ''1 second''::interval))
		UNION
		SELECT
			6 AS id, ''Servers Unknown'' AS label, false AS required, count(server_id) AS count
		FROM
			server_list
		WHERE
			-- The server is not bound with any server
			agent_active IS NULL OR
			(agent_active AND
				-- The agent is bound, but never got an heartbeat from it
				(agent_last_heartbeat IS NULL OR
					-- The agent is not properly bound with the server
					-- (Agent may not have proper authentication for connection)
					server_last_heartbeat IS NULL OR
					-- Agent is down for some reason
					agent_last_heartbeat < (now() - (heartbeat_interval * 2 * ''1 second''::interval))))
	) AS global_pem_status
WHERE required OR count > 0
ORDER BY id' WHERE id = 1;

COMMIT TRANSACTION;
