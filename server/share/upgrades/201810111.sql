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
  RETURNS integer AS 'SELECT 201810111::integer;'
  LANGUAGE 'sql' IMMUTABLE;
COMMENT ON FUNCTION pem.schema_version() IS 'Returns the version number of the PEM schema';

DROP FUNCTION pem.create_generic_role(varchar);
CREATE OR REPLACE FUNCTION pem.create_generic_role(varchar)
RETURNS BOOL AS $$
DECLARE
    role_exist boolean;
    role_name text;
BEGIN
    role_exist := false;
    role_name  := quote_ident($1);

    SELECT true INTO role_exist FROM pg_catalog.pg_roles WHERE rolname = role_name;
    IF role_exist THEN
        RAISE NOTICE 'ROLE % already exist', role_name;
    ELSE
        EXECUTE 'CREATE ROLE ' || role_name  || ' WITH NOLOGIN';
    END IF;
    RETURN role_exist;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION pem.create_proxy_agent_user(varchar, varchar DEFAULT NULL)
RETURNS VOID AS $$
DECLARE
    username text;
    passwd text;
    user_exists boolean;
BEGIN
    user_exists := pem.create_generic_role($1);
    username := pg_catalog.quote_ident($1);

    IF user_exists THEN
        RAISE NOTICE 'ROLE/USER % EXIST.', $1;
    ELSE
        passwd := pg_catalog.quote_literal(COALESCE($2, md5(random()::text)));
        EXECUTE $SQL$ALTER USER $SQL$ || username || $SQL$ LOGIN PASSWORD $SQL$ || passwd;
    END IF;
    EXECUTE $SQL$GRANT pem_agent_pool, pem_agent TO $SQL$ || username;
END;
$$ LANGUAGE plpgsql;

-- Create a generic user pem_agent.
SELECT pem.create_generic_role('pem_agent_pool');

CREATE OR REPLACE FUNCTION pem.get_agent_pool_auth(p_usename TEXT)
RETURNS TABLE(username TEXT, password TEXT) AS
$$
BEGIN
    RETURN QUERY
    SELECT u.rolname::TEXT, u.rolpassword::TEXT
    FROM pg_authid g
    JOIN pg_auth_members m ON (m.roleid = g.oid)
    JOIN pg_authid u ON (u.oid = m.member)
    WHERE NOT u.rolsuper
        AND g.rolname = 'pem_agent_pool'
        AND u.rolname = p_usename;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

REVOKE ALL ON FUNCTION pem.get_agent_pool_auth(p_usename TEXT) FROM PUBLIC, pem_admin;

GRANT SELECT, INSERT, DELETE ON TABLE pem.agent_runtime TO pem_agent;

COMMIT TRANSACTION;
