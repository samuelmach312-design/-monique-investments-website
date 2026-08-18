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
'SELECT 201909191::integer;'
  LANGUAGE 'sql' IMMUTABLE;
COMMENT ON FUNCTION pem.schema_version() IS
 'Returns the version number of the PEM schema';

ALTER table pem.bart_backup_config
RENAME backup_id to last_backup_id;

ALTER table pem.bart_backup_config
ADD COLUMN last_backup_name text;

END TRANSACTION;
