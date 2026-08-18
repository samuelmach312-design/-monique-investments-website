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
'SELECT 201908061::integer;'
  LANGUAGE 'sql' IMMUTABLE;
COMMENT ON FUNCTION pem.schema_version() IS
 'Returns the version number of the PEM schema';

-- PEM-706: Customer requested to change the label from 'Blocked Users' to 'Blocked Sessions'
UPDATE pem.chart_func SET func = E'
	SELECT
		$$Total Locks: $$ || count(DISTINCT locktype) || $$ &#183; Blocked Sessions: $$ || count(DISTINCT procpid)
	FROM
		pemdata.lock_info
	WHERE server_id = $1::int4'
WHERE id = 54 AND type = 'Q';

END TRANSACTION;
