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
'SELECT 201905061::integer;'
  LANGUAGE 'sql' IMMUTABLE;
COMMENT ON FUNCTION pem.schema_version() IS
 'Returns the version number of the PEM schema';

-- Add support for Ark 3.2 and 3.3 from PEM 7.8 onwards.
INSERT INTO pem.ark_api_version(api_version, display_name) VALUES ('v3.2', 'Ark 3.2');
INSERT INTO pem.ark_api_version(api_version, display_name) VALUES ('v3.3', 'Ark 3.3');

END TRANSACTION;
