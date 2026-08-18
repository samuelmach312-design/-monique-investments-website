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
'SELECT 201905081::integer;'
  LANGUAGE 'sql' IMMUTABLE;
COMMENT ON FUNCTION pem.schema_version() IS
 'Returns the version number of the PEM schema';

/*
-- Allow non-pem admin users to select, insert and update ark server credentials
--
-- JIRA: PEM-1360
*/

GRANT SELECT, INSERT, UPDATE ON TABLE pem.ark_server TO pem_user;
GRANT SELECT, INSERT, UPDATE ON TABLE pem.ark_server_option TO pem_user;

END TRANSACTION;