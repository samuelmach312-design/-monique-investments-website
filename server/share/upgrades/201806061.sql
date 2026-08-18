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
'SELECT 201806061::integer;'
  LANGUAGE 'sql' IMMUTABLE;

DROP FUNCTION pem.create_server_group(text);

CREATE OR REPLACE FUNCTION pem.create_server_group(_name text, _uid oid DEFAULT pem.current_user_id())
RETURNS integer AS
$$
DECLARE
    gid integer;
    hidden bool;
BEGIN
    SELECT s.id, s.hidden INTO gid, hidden FROM pem.user_server_group s WHERE s.name = _name AND uid = _uid;

    IF gid IS NOT NULL THEN
        IF hidden THEN
            UPDATE pem.user_server_group SET hidden = FALSE WHERE id = gid;
        END IF;
        RETURN gid;
    ELSE
        SELECT s.id INTO gid FROM pem.server_group s WHERE s.name = _name;

        IF gid IS NULL THEN
            INSERT INTO pem.server_group(name) VALUES (_name) RETURNING id INTO gid;
        END IF;
        RETURN gid;
    END IF;
END$$ LANGUAGE 'plpgsql';

GRANT INSERT, UPDATE, DELETE ON TABLE pem.agent_options TO pem_user;
DO $$
DECLARE
  rls_supported boolean;
BEGIN
    SELECT (count(*) = 1) INTO rls_supported FROM pg_catalog.pg_class WHERE relname = 'pg_policy' AND relnamespace = (SELECT oid FROM pg_catalog.pg_namespace WHERE nspname = 'pg_catalog');

    IF rls_supported THEN
        RAISE INFO 'RLS policies for pem_agent_options...';

        EXECUTE $SQL$ ALTER TABLE pem.agent ENABLE ROW LEVEL SECURITY $SQL$;
        EXECUTE $SQL$ ALTER TABLE pem.server ENABLE ROW LEVEL SECURITY $SQL$;
        EXECUTE $SQL$ ALTER TABLE pem.agent_options ENABLE ROW LEVEL SECURITY $SQL$;
        EXECUTE $SQL$
            CREATE POLICY pem_agent_options_select
                ON pem.agent_options
                FOR SELECT
                USING (
                    pem_user = current_user OR
                    pg_has_role('pem_admin', 'member'::text)
                )
        $SQL$;
        EXECUTE $SQL$
            CREATE POLICY pem_agent_options_update
                ON pem.agent_options
                FOR UPDATE
                USING (
                    pem_user = current_user OR
                    pg_has_role('pem_admin', 'member'::text)
                )
                WITH CHECK (
                    pg_has_role('pem_user', 'member'::text)
                )
        $SQL$;
        -- DELETE operation on pem.agent_options
        EXECUTE $SQL$
            CREATE POLICY pem_agent_options_delete
                ON pem.agent_options
                FOR DELETE
                USING (
                    pem_user = current_user OR
                    pg_has_role('pem_admin', 'member'::text)
                )
        $SQL$;
        -- INSERT operation on pem.agent_options
        EXECUTE $SQL$
            CREATE POLICY pem_agent_options_insert
                ON pem.agent_options
                FOR INSERT
                WITH CHECK (
                    pg_has_role('pem_user', 'member'::text)
                )
        $SQL$;
    END IF;
END
$$ language 'plpgsql';

END TRANSACTION;
