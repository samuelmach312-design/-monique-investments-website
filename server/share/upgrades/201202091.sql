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

-- Upgrade script for v2.1.0b1 to v2.1.0b2

BEGIN TRANSACTION;

CREATE OR REPLACE FUNCTION pem.schema_version()
  RETURNS integer AS
'SELECT 201202091::integer;'
  LANGUAGE 'sql' IMMUTABLE;

ALTER TABLE pem.probe_log ADD COLUMN id bigserial NOT NULL;

COMMIT TRANSACTION;
