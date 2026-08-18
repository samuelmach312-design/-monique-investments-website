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
'SELECT 201509151::integer;'
  LANGUAGE 'sql' IMMUTABLE;
COMMENT ON FUNCTION pem.schema_version() IS 'Returns the version number of the PEM schema';

CREATE OR REPLACE FUNCTION pem.loganalysis_autovacuumstats(sdate TIMESTAMP, edate TIMESTAMP, server_id INT, tlimit INT DEFAULT 20) RETURNS REFCURSOR
AS
$BODY$
DECLARE

autovacuumstats_ref REFCURSOR:='loganalysis_avacuumstats';
autovacuumstats_analyze_ref REFCURSOR:='loganalysis_aanalyzestats';
query TEXT:= '';

BEGIN

	IF ((sdate IS NULL OR edate IS NULL) OR (sdate > edate)) THEN
		RAISE EXCEPTION 'LOGANALYSIS_AUTOVACUUMSTATS: Invalid time range.';
	END IF;

	IF (server_id IS NULL OR server_id < 0) THEN
		RAISE EXCEPTION 'LOGANALYSIS_AUTOVACUUMSTATS: Invalid server id has.';
	END IF;
/*
--
--	Sample autovacuum text entries from the log file.
--
--	automatic vacuum of table "postgres.public.pgbench_tellers": index scans: 0
--	pages: 0 removed, 1 remain
--	tuples: 106 removed, 14 remain
--	buffer usage: 25 hits, 0 misses, 0 dirtied
--	avg read rate: 0.000 MiB/s, avg write rate: 0.000 MiB/s
--	system usage: CPU 0.00s/0.00u sec elapsed 0.03 sec
--
*/

	query :=
		$$
		SELECT
			extract(epoch from log_time) as log_time,
			SUBSTRING(message FROM '"(?:[^"]|(?:""))*"(?=: index scans:)') AS relation,
				-- Collecting index scans
				SUBSTRING(SUBSTRING(message FROM 'automatic vacuum of table "(?:[^"]|(?:""))*": index scans: \d+') FROM '\d+$') AS index_details,
				-- Collecting pages details
				SUBSTRING(SUBSTRING(message FROM 'pages: \d+ removed, \d+ remain') FROM '\d+ removed, \d+ remain') AS page_details,
				-- Collecting tuples details
				SUBSTRING(SUBSTRING(message FROM 'tuples: \d+ removed, \d+ remain') FROM '\d+ removed, \d+ remain') AS tuple_details,
				-- Collecting buffer usage details
				SUBSTRING(SUBSTRING(message FROM 'buffer usage: \d+ hits, \d+ misses, \d+ dirtied') FROM '\d+ hits, \d+ misses, \d+ dirtied') AS buffer_details,
				-- Collecting avg read rate details
				SUBSTRING(SUBSTRING(message FROM 'avg read rate: [0-9\.]+ MiB/s, avg write rate: [0-9\.]+ MiB/s') FROM '[0-9\.]+ MiB/s, avg write rate: [0-9\.]+ MiB/s') AS read_rate,
				-- Collecting system usage
				SUBSTRING(SUBSTRING(message from 'system usage: CPU [0-9\.]+s/[0-9\.]+u sec elapsed [0-9\.]+ sec') FROM 'CPU [0-9\.]+s/[0-9\.]+u sec elapsed [0-9\.]+ sec') AS system_usage

		FROM
			pemdata.server_logs
		WHERE
			pem.date_trunc_minutes(log_time) BETWEEN $1::TIMESTAMP AND $2::TIMESTAMP AND
			error_severity = 'LOG' AND message LIKE 'automatic vacuum %' AND
			message ~ '^automatic vacuum of table "(?:[^"]|(?:""))*": index scans: \d+' AND
			server_id = $3::INT
			LIMIT $4::INT
		$$;

		OPEN autovacuumstats_ref FOR EXECUTE query USING sdate, edate, server_id, tlimit;
		RETURN autovacuumstats_ref;

END;
$BODY$
LANGUAGE PLPGSQL;


/*

-- This method collects all the statistics regarding autoanalyze
-- among the given intervals for the given server.
--
-- RETURNS REFCURSOR to the calling portion.
--
-- Parameters:
--
-- sdate		: Checkpoint stats start time.
-- edate		: Checkpoint stats end time.
-- server_id	: Checkpoint stats for the server.
--
-- Implementation:
--
-- Since, it's a table chart, which we will show the actual values without any aggregates.
--

*/

CREATE OR REPLACE FUNCTION pem.loganalysis_autoanalyzestats(sdate TIMESTAMP, edate TIMESTAMP, server_id INT, tlimit INT DEFAULT 20) RETURNS REFCURSOR
AS
$BODY$
DECLARE

autovacuumstats_analyze_ref REFCURSOR:='loganalysis_aanalyzestats';
query TEXT:= '';

BEGIN

	IF ((sdate IS NULL OR edate IS NULL) OR (sdate > edate)) THEN
		RAISE EXCEPTION 'LOGANALYSIS_AUTOANALYZE: Invalid time range.';
	END IF;

	IF (server_id IS NULL OR server_id < 0) THEN
		RAISE EXCEPTION 'LOGANALYSIS_AUTOANALYZE: Invalid server id has.';
	END IF;

/*
--
--	Sample log entry for autovacuum analyze text
--
--	automatic analyze of table "pem.pem.probe_schedule" system usage: CPU 0.00s/0.00u sec elapsed 0.16 sec
--
*/
	query :=
		$$
		SELECT
			extract(epoch from log_time) as log_time,
			SUBSTRING(message FROM '"(?:[^"]|(?:""))*"(?= system usage:)') AS relation,
				-- Collecting system usage
				SUBSTRING(SUBSTRING(message FROM 'system usage: CPU [0-9\.]+s/[0-9\.]+u sec elapsed [0-9\.]+ sec') FROM 'CPU [0-9\.]+s/[0-9\.]+u sec elapsed [0-9\.]+ sec') AS system_usage

		FROM
			pemdata.server_logs
		WHERE
			pem.date_trunc_minutes(log_time) BETWEEN $1::TIMESTAMP AND $2::TIMESTAMP AND
			error_severity = 'LOG' AND message LIKE 'automatic analyze of table %' AND
			message ~ '^automatic analyze of table "(?:[^"]|(?:""))*" system usage: CPU [0-9\.]+s/[0-9\.]+u sec elapsed [0-9\.]+ sec' AND
			server_id = $3::INT
			LIMIT $4::INT
		$$;

		OPEN autovacuumstats_analyze_ref FOR EXECUTE QUERY USING sdate, edate, server_id, tlimit;
		RETURN autovacuumstats_analyze_ref;

END;
$BODY$
LANGUAGE PLPGSQL;

COMMIT TRANSACTION;
