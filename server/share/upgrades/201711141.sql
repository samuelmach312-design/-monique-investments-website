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
'SELECT 201711141::integer;'
  LANGUAGE 'sql' IMMUTABLE;
COMMENT ON FUNCTION pem.schema_version() IS 'Returns the version number of the PEM schema';

--
-- Fixes #PEM-280
-- Added SSL support for server module.
--

-- Add new column to store password file for server in server_option table in pem
ALTER TABLE pem.server_option ADD COLUMN passfile text DEFAULT NULL;

-- Add new column to store SSL compression flag for server in server_option table in pem
ALTER TABLE pem.server_option ADD COLUMN sslcompression boolean NOT NULL DEFAULT false;

COMMIT TRANSACTION;
