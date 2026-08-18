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
'SELECT 201407101::integer;'
  LANGUAGE 'sql' IMMUTABLE;

DELETE FROM pem.logexp_charts WHERE analyzer_name = 'Idle Statistics';
DELETE FROM pem.logexp_tagbasecharts WHERE tags = '{IDLE,"IDLE in transaction","IDLE in transaction (aborted)"}';

COMMIT TRANSACTION;
