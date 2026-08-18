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
'SELECT 201805301::integer;'
  LANGUAGE 'sql' IMMUTABLE;

-- Added group id column to fetch available agent details.
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
        COALESCE(ao.group_id, a.group_id, 0)::text AS group_id
    FROM (SELECT a.*, r.rolsuper AS rolsuper FROM pem.agent a, pg_catalog.pg_roles r WHERE r.rolname = current_user) AS a
        LEFT JOIN pem.agent_options ao ON (a.id = ao.agent_id AND pem_user = current_user)
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

-- Fix PEM-913 - Added insert policy for "pem_agent" on pem.job table.
DO $$
DECLARE
  rls_supported boolean;
BEGIN
    SELECT (count(*) = 1) INTO rls_supported FROM pg_catalog.pg_class WHERE relname = 'pg_policy' AND relnamespace = (SELECT oid FROM pg_catalog.pg_namespace WHERE nspname = 'pg_catalog');

	IF rls_supported THEN

		EXECUTE $SQL$
			ALTER POLICY pem_job_insert ON pem.job
				WITH CHECK (
					pg_catalog.pg_has_role('pem_agent','member'::text) OR
					pg_catalog.pg_has_role('pem_manage_schedule_task', 'member'::text)
				)
		$SQL$;

	END IF;
END
$$ language 'plpgsql';

COMMIT TRANSACTION;
