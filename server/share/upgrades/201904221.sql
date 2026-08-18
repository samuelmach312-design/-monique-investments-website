/***************************************************************************
 *
 * Postgres Enterprise Manager
 *
 * Copyright (C) 2010 - 2025, EnterpriseDB Corporation. All rights reserved.
 *
 ***************************************************************************/

/*
-- To fix the issue where user is not able to save the password for PEM Server,
-- the default server which we add after installation
--
-- JIRA: PEM-2031
*/

BEGIN TRANSACTION;

    CREATE OR REPLACE FUNCTION pem.schema_version()
      RETURNS integer AS
    'SELECT 201904221::integer;'
      LANGUAGE 'sql' IMMUTABLE;
    COMMENT ON FUNCTION pem.schema_version() IS
     'Returns the version number of the PEM schema';

    -- In 201809241.sql upgrade script file we added this column which is
    -- not present in pemserver.sql create table pem.server_auth defination
    -- and also not used, so removing it.
    ALTER TABLE pem.server_auth
    DROP COLUMN IF EXISTS username;

    -- Copy the user data from server_options into server_auth, so that user
    -- can have entry in server_auth for thier respective server
    INSERT INTO pem.server_auth (
        server_id,
        pem_user
    )
    SELECT
        server_id,
        pem_user
    FROM pem.server_options
    ON CONFLICT ON CONSTRAINT server_auth_pem_user_key DO NOTHING;

END TRANSACTION;
