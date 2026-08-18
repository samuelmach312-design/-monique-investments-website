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
'SELECT 201509171::integer;'
  LANGUAGE 'sql' IMMUTABLE;
COMMENT ON FUNCTION pem.schema_version() IS 'Returns the version number of the PEM schema';

CREATE OR REPLACE FUNCTION pem.loganalysis_tempusedqueries(sdate TIMESTAMP, edate TIMESTAMP, server_id INT, tlimit INT DEFAULT 20) RETURNS REFCURSOR
AS
$BODY$
DECLARE
loganalysis_tempusedqueries_ref REFCURSOR:='loganalysis_tempusedqueries';
query TEXT:='';

BEGIN

	IF ((sdate IS NULL OR edate IS NULL) OR (sdate > edate)) THEN
		RAISE EXCEPTION 'LOGANALYSIS_TEMPUSEDQUERIES: Invalid time range.';
	END IF;

	IF (server_id IS NULL OR server_id < 0) THEN
		RAISE EXCEPTION 'LOGANALYSIS_TEMPUSEDQUERIES: Invalid server id.';
	END IF;

	IF (tlimit IS NULL OR tlimit<=0 ) THEN
		RAISE EXCEPTION 'LOGANALYSIS_TEMPUSEDQUERIES: Invalid table limit.';
	END IF;

	query :=
		$$
		SELECT
			EXTRACT(EPOCH FROM log_time) log_time,
			SUBSTRING(message FROM '\d+$') AS tempfile_size,
			query
		FROM
			pemdata.server_logs
		WHERE
			error_severity = 'LOG' and
			query IS NOT NULL and
			trim(both ' ' from query) != '' AND
			message ~ '^temporary file: path "(?:[^"]|(?:""))*", size \d+$' AND
			pem.date_trunc_minutes(log_time) >= $1::TIMESTAMP AND pem.date_trunc_minutes(log_time)< $2::TIMESTAMP AND
			server_id = $3::int
			order by 2 DESC
			limit $4::INT
		$$;

	OPEN loganalysis_tempusedqueries_ref FOR EXECUTE query USING sdate, edate, server_id, tlimit;
	RETURN loganalysis_tempusedqueries_ref;
END;
$BODY$
LANGUAGE PLPGSQL;

COMMIT TRANSACTION;
