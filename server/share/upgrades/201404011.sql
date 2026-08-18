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

-- Upgrade script for v4.0.1 GA to v4.0.2 GA

BEGIN TRANSACTION;

-- Update the schema version
CREATE OR REPLACE FUNCTION pem.schema_version()
  RETURNS integer AS
'SELECT 201404011::integer;'
  LANGUAGE 'sql' IMMUTABLE;
COMMENT ON FUNCTION pem.schema_version() IS 'Returns the version number of the PEM schema';

UPDATE pem.chart SET name = 'Top 5 Scanned Tables' WHERE id = 24;
UPDATE pem.chart SET name = 'Top 5 Scanned Indexes' WHERE id = 25;

COMMIT TRANSACTION;
