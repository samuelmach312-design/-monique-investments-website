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
'SELECT 201806051::integer;'
  LANGUAGE 'sql' IMMUTABLE;
COMMENT ON FUNCTION pem.schema_version() IS 'Returns the version number of the PEM schema';

-- DROP and create a new constraint with new type 'AD' - Alert Details TABLE Chart
ALTER TABLE pem.chart DROP CONSTRAINT pem_chart_type_constraint;
ALTER TABLE pem.chart ADD CONSTRAINT  pem_chart_type_constraint CHECK (type IN ('TE', 'TB', 'B', 'P', 'L', 'CL', 'CT', 'GL', 'AD'));

-- update chart type of alert details chart to AD from TB
UPDATE pem.chart SET type='AD' WHERE id=6;

COMMIT TRANSACTION;