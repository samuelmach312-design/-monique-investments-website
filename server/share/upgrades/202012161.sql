/***************************************************************************
 *
 * Postgres Enterprise Manager
 *
 * Copyright (C) 2010 - 2025, EnterpriseDB Corporation. All rights reserved.
 *
 ***************************************************************************/

-- NOTE: This sql file is responsible for PEM 8.0.1 schema upgrade.

BEGIN TRANSACTION;

CREATE OR REPLACE FUNCTION pem.schema_version() RETURNS integer AS
'SELECT 202012161::integer;'
LANGUAGE 'sql' IMMUTABLE;
COMMENT ON FUNCTION pem.schema_version()
	IS 'Returns the version number of the PEM schema';

-- JIRA: PEM-1963
-- Do not display catalog tables count on the database dashboard if system schema is turned off
UPDATE pem.chart_func SET func = E'SELECT
        $$Total Database Size: $$ ||
        (SELECT
		pem.pretty_size(database_size_mb)
	FROM  pemdata.database_size
	WHERE database_size.server_id = $1::int4 AND database_size.database_name = $2::text) || $$&#183;$$
	||$$ Total Tables: $$ || (SELECT
					count(table_name)
					FROM pemdata.table_size
					WHERE server_id = $1::int4 AND database_name = $2::text AND
                    ($3::boolean OR (schema_name NOT IN(
                               $$pg_catalog$$,
                               $$pg_toast$$,
                               $$information_schema$$,
                               $$sys$$)))) || $$&#183;$$
	|| $$ Total Indexes: $$ || (SELECT
					count(index_name) FROM pemdata.index_size
                    WHERE server_id = $1::int4 AND database_name = $2::text AND
                    ($3::boolean OR (schema_name NOT IN(
                               $$pg_catalog$$,
                               $$pg_toast$$,
                               $$information_schema$$,
                               $$sys$$))))',
        r_sys_obj = TRUE
WHERE id = 9 AND type = 'Q';

END TRANSACTION;
