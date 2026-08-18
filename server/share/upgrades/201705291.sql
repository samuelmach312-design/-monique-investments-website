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
  'SELECT 201705291::integer;'
    LANGUAGE 'sql' IMMUTABLE;
    COMMENT ON FUNCTION pem.schema_version() IS 'Returns the version number of the PEM schema';

-- Fixes #41391
CREATE OR REPLACE FUNCTION pem.parse_version_string(text) RETURNS integer AS $$
SELECT (
   CASE (string_to_array($1, ' '))[1]
   WHEN 'EnterpriseDB' THEN 20000
   ELSE 10000
   END
   ) +
   (major_version::integer * 100) +
   (CASE WHEN minor_version = '' THEN 0::integer ELSE minor_version::integer END)
FROM (
   SELECT
   regexp_replace((string_to_array($1, ' '))[2], '^([0-9]+).*', E'\\1','g') AS major_version,
   regexp_replace((string_to_array($1, ' '))[2], '^([0-9]+)[.]?([0-9]*).*', E'\\2','g') AS minor_version
   ) AS a;
$$ LANGUAGE sql;


COMMIT TRANSACTION;
