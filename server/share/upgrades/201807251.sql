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
'SELECT 201807251::integer;'
  LANGUAGE 'sql' IMMUTABLE;
COMMENT ON FUNCTION pem.schema_version() IS 'Returns the version number of the PEM schema';

ALTER TABLE pem.ark_server_option ADD COLUMN domain_name text;

ALTER TABLE pem.ark_server DROP COLUMN IF EXISTS cloud_provider;

-- We won't support older version of Ark RestAPI
DELETE FROM pem.ark_api_version WHERE api_version in ('v2.0', 'v2.1', 'v2.2', 'v2.3');

COMMIT TRANSACTION;
