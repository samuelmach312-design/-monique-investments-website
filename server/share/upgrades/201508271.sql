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
'SELECT 201508271::integer;'
  LANGUAGE 'sql' IMMUTABLE;
COMMENT ON FUNCTION pem.schema_version() IS 'Returns the version number of the PEM schema';

ALTER TABLE pem.job DROP COLUMN IF EXISTS dependent_on_job;
ALTER TABLE pem.job ADD COLUMN dependent_on_job integer[] DEFAULT NULL;

DROP FUNCTION pem.job_is_complete(integer, character);
CREATE OR REPLACE FUNCTION pem.job_is_complete(job_id integer[], status char) RETURNS BOOL AS $$
DECLARE
	res boolean := false;
BEGIN
	FOR i in 1..COALESCE(array_upper(job_id, 1), 0) LOOP
		SELECT CASE WHEN (status = 'i' AND a.jlgstatus != 'r') OR status = a.jlgstatus THEN true ELSE false END INTO res
		FROM
		(
			SELECT l.jlgstatus jlgstatus
			FROM pem.job j
			LEFT JOIN pem.joblog l ON j.jobid = l.jlgjobid
			WHERE j.jobid = job_id[i]
			ORDER BY l.jlgstart DESC LIMIT 1
		) a;

		IF NOT res THEN
			RETURN false;
		END IF;
	END LOOP;

	RETURN true;
END;
$$ LANGUAGE plpgsql;

COMMIT TRANSACTION;
