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
'SELECT 201506301::integer;'
  LANGUAGE 'sql' IMMUTABLE;
COMMENT ON FUNCTION pem.schema_version() IS 'Returns the version number of the PEM schema';
/*
-- This method collects the queries that has taken the most of the time
-- among the given intervals of the given server.
--
-- RETURNS REFCURSOR to the calling portion.
--
-- Parameters:
--
-- sdate	: Checkpoint stats start time.
-- edate	: Checkpoint stats end time.
-- server_id	: Checkpoint stats for the server.
-- tlimit	: No.Of rows limit to the display table.
--
-- Implementation:
--
-- Fetching all the lines from server_logs, which are like below
--
-- duration: 0.000 ms  execute <unnamed>: UPDATE pem.probe_schedule SET current_backend_pid = NULL, last_execution_time = now() WHERE probe_id = $1 AND parameter_value_list = $2 AND current_backend_pid = pg_backend_pid();
--
-- and doing descending sort the queries based on the duration.
--
-- NOTE:: This only works, when we enable the log_min_duration_statement != -1.
*/


CREATE OR REPLACE FUNCTION pem.loganalysis_slowqueries(sdate TIMESTAMP, edate TIMESTAMP, server_id INT, tlimit INT DEFAULT 20) RETURNS REFCURSOR
AS
$BODY$
DECLARE
loganalysis_slowqueries_ref REFCURSOR:='loganalysis_slowqueries';
query TEXT:='';

BEGIN

	IF ((sdate IS NULL OR edate IS NULL) OR (sdate > edate)) THEN
		RAISE EXCEPTION 'LOGANALYSIS_SLOWQUERIES: Invalid time.';
	END IF;

	IF (server_id IS NULL OR server_id < 0) THEN
		RAISE EXCEPTION 'LOGANALYSIS_SLOWQUERIES: Invalid server id.';
	END IF;

	IF (tlimit IS NULL OR tlimit<=0 ) THEN
		RAISE EXCEPTION 'LOGANALYSIS_SLOWQUERIES: Invalid table limit.';
	END IF;

	/*
	--
	--	Sample log lines to match the regex
	--
	--	duration: 0.000 ms  bind <unnamed>: QUERY
	--	duration: 0.000 ms  execute S_1: BEGIN
	--	duration: 0.000 ms  statement: QUERY
	--
	*/
	query := $$

		SELECT
		EXTRACT(EPOCH FROM log_time) log_time,
		command_tag AS tag,
		-- Dividing the log line like two parts,
		-- {duration (interval ms):} {Query}
		-- and getting the Query from above parts.
		--
		TRIM(BOTH ' ' FROM
			SPLIT_PART(message,
				SUBSTRING(message FROM '^duration:\s+[0-9\.]+\s+ms\s*(?:prepare|parse|bind|execute from fetch|execute|statement)(?:\s+<(?:[^>]|>)+>)?:'), 2)) as query,
			detail AS parameters,
			SUBSTRING(SUBSTRING(message FROM '^duration: [0-9\.]+ ms') FROM '[0-9\.]+') AS duration,
			connection_from AS host,
			database_name AS database
		FROM
			pemdata.server_logs
		WHERE
			message LIKE 'duration: %' AND message ~ '^duration:\s+[0-9\.]+\s+ms\s*(?:prepare|parse|bind|execute from fetch|execute|statement)' AND
			server_id = $3::INT AND
			error_severity = 'LOG'
			AND pem.date_trunc_minutes(log_time) BETWEEN $1::TIMESTAMP AND $2::TIMESTAMP
			ORDER BY 5 DESC
			LIMIT $4::INT;
		$$;

	OPEN loganalysis_slowqueries_ref FOR EXECUTE query USING sdate, edate, server_id, tlimit;
	RETURN loganalysis_slowqueries_ref;
END;
$BODY$
LANGUAGE PLPGSQL;

END TRANSACTION;
