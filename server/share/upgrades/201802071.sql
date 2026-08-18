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
'SELECT 201802071::integer;'
  LANGUAGE 'sql' IMMUTABLE;
COMMENT ON FUNCTION pem.schema_version() IS 'Returns the version number of the PEM schema';

CREATE OR REPLACE FUNCTION pem.can_access_team(_owner OID, _team text)
RETURNS boolean AS
$$
    SELECT
        u.usesysid = _owner OR
        pg_has_role('pem_super_admin', 'member'::text) OR
        _team is NULL OR _team = '' OR ((
            SELECT count(*) >= 1 FROM pg_catalog.pg_user t WHERE t.usename = _team
        ) AND pg_catalog.pg_has_role(
            CASE WHEN (
                SELECT count(*) >= 1 FROM pg_user t WHERE t.usename = _team::name
            ) THEN _team::name ELSE u.usename END,
            'member'::text
        ))
    FROM pg_user u WHERE usename = current_user;
$$ LANGUAGE 'sql';

CREATE OR REPLACE FUNCTION pem.object_owner(_owner OID)
RETURNS boolean AS
$$
    SELECT
        u.usesysid = _owner OR
        pg_has_role('pem_admin', 'member'::text)
    FROM pg_user u WHERE usename = current_user;
$$ LANGUAGE 'sql';

-- Do not allow to change team other than owner/pem_super_admin
CREATE OR REPLACE FUNCTION pem.on_team_onwer_update()
RETURNS trigger AS
$$
DECLARE
    is_owner boolean := false;
BEGIN
    SELECT
        (usesysid = OLD.owner OR
        pg_has_role('pem_super_admin', 'member'::text)) INTO is_owner
    FROM pg_user u WHERE u.usename = current_user;

    IF NOT is_owner THEN
        RAISE EXCEPTION
            '% does not have permission to change the team/owner.',
            current_user;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE 'plpgsql';

DROP TRIGGER IF EXISTS pem_team_update ON pem.server;
CREATE TRIGGER pem_team_update BEFORE UPDATE OF team, owner
    ON pem.server
    FOR EACH ROW
    EXECUTE PROCEDURE pem.on_team_onwer_update();

DROP TRIGGER IF EXISTS pem_team_update ON pem.agent;
CREATE TRIGGER pem_team_update BEFORE UPDATE OF team, owner
    ON pem.agent
    FOR EACH ROW
    EXECUTE PROCEDURE pem.on_team_onwer_update();

DO $$
DECLARE
  rls_supported boolean;
BEGIN
    SELECT (count(*) = 1) INTO rls_supported FROM pg_catalog.pg_class WHERE relname = 'pg_policy' AND relnamespace = (SELECT oid FROM pg_catalog.pg_namespace WHERE nspname = 'pg_catalog');

    IF rls_supported THEN
        RAISE INFO 'Modifying RLS policies for pem.server...';
        -- SELECT operation on pem.server
        EXECUTE 'DROP POLICY IF EXISTS pem_server_team_support_select ON pem.server';
        EXECUTE 'DROP POLICY IF EXISTS pem_server_team_support_update ON pem.server';
        EXECUTE 'DROP POLICY IF EXISTS pem_server_team_support_delete ON pem.server';
        EXECUTE 'DROP POLICY IF EXISTS pem_server_team_support_insert ON pem.server';

        RAISE INFO 'RLS policy for select, update, delete on pem.server...';
        EXECUTE $SQL$
            CREATE POLICY pem_server_team_support_select
                ON pem.server
                FOR SELECT
                USING (
                    pem.can_access_team(owner, team) OR
                    pg_has_role('pem_agent', 'member'::text)
                )
        $SQL$;
        EXECUTE $SQL$
            CREATE POLICY pem_server_team_support_update
                ON pem.server
                FOR UPDATE
                USING (
                    pem.can_access_team(owner, team) OR
                    pg_has_role('pem_agent', 'member'::text)
                )
                WITH CHECK (
                    pem.can_access_team(owner, team) OR
                    pg_has_role('pem_agent', 'member'::text)
                )
        $SQL$;
        -- DELETE operation on pem.server
        EXECUTE $SQL$
            CREATE POLICY pem_server_team_support_delete
                ON pem.server
                FOR DELETE
                USING (pem.object_owner(owner))
        $SQL$;
        RAISE INFO 'INSERT RLS policy on pem.server...';
        -- INSERT operation on pem.server
        EXECUTE $SQL$
            CREATE POLICY pem_server_team_support_insert
                ON pem.server
                FOR INSERT
                WITH CHECK (
                    pg_has_role(
                        owner, 'pem_database_server_registration'::name, 'member'::text
                    )
                )
        $SQL$;

        RAISE INFO 'Modifying RLS policies for pem.agent...';
        EXECUTE 'DROP POLICY IF EXISTS pem_agent_team_support_select ON pem.agent';
        EXECUTE 'DROP POLICY IF EXISTS pem_agent_team_support_update ON pem.agent';
        EXECUTE 'DROP POLICY IF EXISTS pem_agent_team_support_delete ON pem.agent';
        EXECUTE 'DROP POLICY IF EXISTS pem_agent_team_support_insert ON pem.agent';

        RAISE INFO 'RLS policy for select, update, delete on pem.agent...';
        EXECUTE $SQL$
            CREATE POLICY pem_agent_team_support_select
                ON pem.agent
                FOR SELECT
                USING (
                    pem.can_access_team(owner, team) OR
                    pg_catalog.pg_has_role('pem_agent', 'member'::text) OR
                    id in (
                        SELECT DISTINCT(agent_id)
                        FROM pem.agent_server_binding
                        WHERE server_id in (SELECT id FROM pem.server)
                    )
                )
        $SQL$;

        RAISE INFO 'INSERT RLS policy on pem.agent...';
        EXECUTE $SQL$
            CREATE POLICY pem_agent_team_support_insert
                ON pem.agent
                FOR INSERT
                WITH CHECK (
                    pg_catalog.pg_has_role('pem_admin', 'member'::text)
                )
        $SQL$;

        RAISE INFO 'UPDATE RLS policy on pem.agent...';
        EXECUTE $SQL$
            CREATE POLICY pem_agent_team_support_update
                ON pem.agent
                FOR UPDATE
                USING (
                    pg_catalog.pg_has_role('pem_admin', 'member'::text) OR
                    pg_catalog.pg_has_role('pem_agent', 'member'::text)
                )
                WITH CHECK (
                    pg_catalog.pg_has_role('pem_admin', 'member'::text) OR
                    pg_catalog.pg_has_role('pem_agent', 'member'::text)
                )
        $SQL$;

        RAISE INFO 'DELETE RLS policy on pem.agent...';
        EXECUTE $SQL$
            CREATE POLICY pem_agent_team_support_delete
                ON pem.agent
                FOR DELETE
                USING (
                    pg_catalog.pg_has_role('pem_admin', 'member'::text)
                )
        $SQL$;
    END IF;
END
$$ language 'plpgsql';

CREATE OR REPLACE FUNCTION pem.parse_version_string(text) RETURNS integer AS $$
SELECT
    CASE
    WHEN (b.version > 11000 AND b.version < 20000) OR (b.version > 21000 AND b.version < 30000) THEN ((b.version / 100)::int * 100)
    ELSE b.version
    END AS version
FROM (
SELECT ((
   CASE (string_to_array($1, ' '))[1]
   WHEN 'EnterpriseDB' THEN 20000
   ELSE 10000
   END
   ) +
   (major_version::integer * 100) +
   (CASE WHEN minor_version = '' THEN 0::integer ELSE minor_version::integer END)) AS version
FROM (
   SELECT
   regexp_replace((string_to_array($1, ' '))[2], '^([0-9]+).*', E'\\1','g') AS major_version,
   regexp_replace((string_to_array($1, ' '))[2], '^([0-9]+)[.]?([0-9]*).*', E'\\2','g') AS minor_version
   ) AS a
) b;
$$ LANGUAGE sql;

UPDATE pem.alert_template SET sql = $sql$
SELECT
	count(*)
FROM
	pem.alert al
WHERE 	COALESCE(error_message, '') <> ''
AND 	CASE WHEN al.agent_id = -1 OR al.agent_id = 0 THEN TRUE
	ELSE al.agent_id IN (SELECT id FROM pem.agent WHERE active AND NOT alert_blackout)
	END
AND 	CASE WHEN al.server_id IS NULL THEN TRUE
	ELSE al.server_id IN
		(SELECT id FROM pem.server WHERE active AND NOT alert_blackout
		INTERSECT
		SELECT server_id FROM pem.agent_server_binding)
        END$sql$
WHERE display_name = 'Alert Errors';


UPDATE pem.config
	SET value = 'https://www.enterprisedb.com/docs/en/10/pg/index.html'
	WHERE param = 'webclient_help_pg';

END TRANSACTION;
