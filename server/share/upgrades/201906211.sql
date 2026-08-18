/***************************************************************************
 *
 * Postgres Enterprise Manager
 *
 * Copyright (C) 2010 - 2025, EnterpriseDB Corporation. All rights reserved.
 *
 ***************************************************************************/

BEGIN TRANSACTION;

CREATE OR REPLACE FUNCTION pem.schema_version()
  RETURNS integer AS
'SELECT 201906211::integer;'
  LANGUAGE 'sql' IMMUTABLE;
COMMENT ON FUNCTION pem.schema_version() IS
 'Returns the version number of the PEM schema';

/*
-- Role based component for Performance Diagnostics
--
-- JIRA: PEM-1646
*/

SELECT pem.create_role_for(
    'comp_performance_diagnostic',
    'Role to run the Performance Diagnostics',
    ARRAY['pem_component']
);

END TRANSACTION;