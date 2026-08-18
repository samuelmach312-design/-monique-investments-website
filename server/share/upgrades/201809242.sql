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
'SELECT 201809242::integer;'
  LANGUAGE 'sql' IMMUTABLE;
COMMENT ON FUNCTION pem.schema_version() IS 'Returns the version number of the PEM schema';

GRANT INSERT, UPDATE, DELETE ON TABLE pem.server_auth TO pem_user;
DO $$
DECLARE
  rls_supported boolean;
BEGIN
    SELECT (count(*) = 1) INTO rls_supported FROM pg_catalog.pg_class WHERE relname = 'pg_policy' AND relnamespace = (SELECT oid FROM pg_catalog.pg_namespace WHERE nspname = 'pg_catalog');

    IF rls_supported THEN
        RAISE INFO 'RLS policies for pem_server_auth...';

        EXECUTE $SQL$ ALTER TABLE pem.server_auth ENABLE ROW LEVEL SECURITY $SQL$;
        EXECUTE $SQL$
            CREATE POLICY pem_server_auth_select
                ON pem.server_auth
                FOR SELECT
                USING (
                    pem_user = current_user OR
                    pg_has_role('pem_admin', 'member'::text)
                )
        $SQL$;
        EXECUTE $SQL$
            CREATE POLICY pem_server_auth_update
                ON pem.server_auth
                FOR UPDATE
                USING (
                    pem_user = current_user OR
                    pg_has_role('pem_admin', 'member'::text)
                )
                WITH CHECK (
                    pg_has_role('pem_user', 'member'::text)
                )
        $SQL$;
        -- DELETE operation on pem.server_auth
        EXECUTE $SQL$
            CREATE POLICY pem_server_auth_delete
                ON pem.server_auth
                FOR DELETE
                USING (
                    pem_user = current_user OR
                    pg_has_role('pem_admin', 'member'::text)
                )
        $SQL$;
        -- INSERT operation on pem.server_auth
        EXECUTE $SQL$
            CREATE POLICY pem_server_auth_insert
                ON pem.server_auth
                FOR INSERT
                WITH CHECK (
                    pg_has_role('pem_user', 'member'::text)
                )
        $SQL$;
    END IF;
END
$$ language 'plpgsql';

END TRANSACTION;