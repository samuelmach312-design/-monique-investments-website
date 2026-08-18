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
'SELECT 201901011::integer;'
  LANGUAGE 'sql' IMMUTABLE;
COMMENT ON FUNCTION pem.schema_version() IS
 'Returns the version number of the PEM schema';

/*
JIRA: PEM-1530

Issue: "Session Lock Activity" table chart was not rendering due to SQL error

Fix: There was a regression with string_agg() function in query with 201812171.sql,
Earlier single quotes were quoted because of E'SELECT 1;' escape string
constant syntax and with given $SQL$..$SQL$ syntax it is not needed
*/

UPDATE pem.chart_func
    SET func = $SQL$
WITH restricted_dbs AS (
SELECT s.id, pem.db_escaped_string_to_array(COALESCE(o.database_restriction, oa.database_restriction)) AS dbs
FROM
    pem.server s
    LEFT OUTER JOIN pg_catalog.pg_roles owner ON (owner.oid = s.owner)
    LEFT OUTER JOIN pem.server_options o ON (s.id = o.server_id AND o.pem_user = current_user)
    LEFT OUTER JOIN pem.server_options oa
            ON (o.server_id IS NULL AND s.id = oa.server_id AND
                    (owner.rolname = oa.pem_user OR (owner.rolname IS NULL AND oa.pem_user IS NULL)))
)
SELECT
   pli.procpid AS "Session Id",
   psi.usename AS "User Name",
   (psi.client_addr || $$:$$ || psi.client_port) as "Source",
   pli.database_name AS "Database Name",
   CASE pli.lockgranted WHEN $$f$$ THEN $$Yes$$ ELSE $$No$$ END AS "Blocked",
   CASE WHEN pli.lockgranted = $$f$$ THEN
	   (SELECT string_agg(b.procpid::text, ', ')
	   FROM pemdata.lock_info b
	   WHERE b.objid = pli.objid AND
			 b.objsubid IS NOT DISTINCT FROM pli.objsubid AND
			 b.objsubsubid IS NOT DISTINCT FROM pli.objsubsubid AND
			 b.lockgranted = $$t$$)
	   ELSE NULL END AS "Blocked By",
   pli.locktype AS "Lock Type",
   pli.objid AS "Object Id",
   pli.lockmode AS "Mode",
   cast(date_trunc($$second$$,psi.xact_start) AS timestamp) AS "Transaction Start"
FROM
   pemdata.lock_info pli JOIN
   pemdata.session_info psi ON ( pli.procpid = psi.procpid )
   LEFT OUTER JOIN restricted_dbs r ON ( pli.server_id = r.id )
WHERE
   pli.server_id = $1::int4 AND
   ($2::boolean OR (CASE WHEN pli.database_name != '' THEN pli.database_name NOT IN ('template0', 'template1') ELSE TRUE END)) AND
   (r.dbs IS NULL OR (pli.database_name = ANY(r.dbs)))
ORDER BY 3$SQL$

WHERE id = 63;

END TRANSACTION;
