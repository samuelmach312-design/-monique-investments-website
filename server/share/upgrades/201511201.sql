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
'SELECT 201511201::integer;'
  LANGUAGE 'sql' IMMUTABLE;
COMMENT ON FUNCTION pem.schema_version() IS 'Returns the version number of the PEM schema';

CREATE OR REPLACE FUNCTION pem.loganalysis_tagsstats(sdate TIMESTAMP WITHOUT TIME ZONE, edate TIMESTAMP WITHOUT TIME ZONE, span INTERVAL, aggr TEXT, server_id INTEGER, targetname TEXT ,tags TEXT[], exactmatch BOOLEAN DEFAULT FALSE)
RETURNS refcursor AS
$BODY$
DECLARE

loganalysis_tagsstatsref REFCURSOR:= 'loganalysis_tagsstats';
query TEXT:='';

BEGIN
	IF (server_id IS NULL OR server_id < 0) THEN
		RAISE EXCEPTION 'LOGANALYSIS_TAGSSTATS: Invalid server.';
	END IF;

	IF (aggr IS NULL OR (trim(both ' ' FROM aggr) = '') OR (aggr !~ '^SUM$|^AVG$|^MAX$|^MIN$')) THEN
		RAISE EXCEPTION 'LOGANALYSIS_TAGSSTATS: Invalid aggregate.';
	END IF;

	IF (targetname IS NULL OR (trim(both ' ' FROM targetname)) = '') THEN
	       RAISE EXCEPTION 'LOGANALYSIS_TAGSSTATS: Invalid targetname.';
	END IF;

	IF (array_upper(tags, 1) IS NULL) THEN
		RAISE EXCEPTION 'LOGANALYSIS_TAGSSTATS: Invalid tags.';
	END IF;

	IF ((sdate IS NULL OR edate IS NULL) OR (sdate > edate)) THEN
		RAISE EXCEPTION 'LOGANALYSIS_TAGSSTATS: Invalid time.';
	ELSE
		IF (span IS NULL OR (span::interval <= '00:00:00'::interval)) THEN
			RAISE EXCEPTION 'LOGANALYSIS_TAGSSTATS: Invalid span.';
		END IF;
	END IF;
	/*
	--
	-- We may get the command_tags from the server_logs like "CREATE FUNCTION", "CREATE VIEW", ..
	-- No need to group the result based these individual tags, where as the grouping on a single "CREATE" is enough to get the "CREATE" stats.
	--
	*/
			IF exactmatch IS false THEN
				targetname := 'split_part('||targetname||', '' '', 1)';
			END IF;

	/*
	-- Implementation details
	--
	-- 1. Generate the time series between the start and end time, with 1 Minute interval
	-- 2. Join the server_log data, with the given tags, when the log_time is equal to above generated value.
	-- 3. Get the tagname, start_time, and count of the tag occurrences when the above condition satisfies.
	-- 4. For handling the missing timeseries data, add dummy "0" and do UNION ALL.
	-- 5. By mixing the actual, dummy data, we will get the complete timeseries values as combination of Actual values + 0 value (if data not found).
	-- 6. Generate the time series between start and end time, with the actual given interval.
	-- 7. Join the 1 minute interval data with this actual interval range, and then calculate required aggregate.
	-- 8. Get tag name, and an array [ epoch, aggregate data ]
	--
	*/
			query :=
			$$
			SELECT
			a.targetname AS metric,
			ARRAY[((a.actual_time * EXTRACT(EPOCH FROM $3::INTERVAL)) + EXTRACT(EPOCH FROM $1::timestamp))::double precision,
				COALESCE(d.metric_value::double precision, 0::double precision)
			] AS data_series
		FROM
			(SELECT * FROM
				(SELECT
					unnest($6::text[]) AS targetname
				) t1,
				(SELECT
					generate_series(0, (EXTRACT(EPOCH FROM $2::TIMESTAMP - $1::TIMESTAMP)/EXTRACT(EPOCH FROM $3::INTERVAL))::int - 1, 1) as actual_time
				) t2
			) a
			LEFT JOIN
			(SELECT
				targetname,
				actual_time,
				CASE
				WHEN $4::TEXT = 'MIN' THEN
					COALESCE((SELECT * FROM UNNEST(array_agg(metric_value)) WHERE unnest!=0 ORDER BY unnest ASC LIMIT 1), 0)
				WHEN $4::TEXT = 'MAX' THEN
					MAX(metric_value)
				ELSE SUM(metric_value)
				END AS metric_value
			FROM
				(SELECT
					(EXTRACT(EPOCH FROM (log_time - $1::TIMESTAMP)) / EXTRACT(EPOCH FROM $3::interval))::int as actual_time,$$||
					targetname||$$ AS targetname,
					COUNT(command_tag) AS metric_value
				FROM
					pemdata.server_logs
				WHERE	server_id = $5::integer AND error_severity = 'LOG' AND
					log_time >= $1::TIMESTAMP AND log_time <= $2::TIMESTAMP
				GROUP BY
					actual_time,$$||
					targetname||$$
				HAVING $$||
					targetname||$$ IN ( SELECT unnest($6::text[]) )
				) b
			GROUP BY actual_time, targetname
			) d ON (a.actual_time = d.actual_time AND a.targetname = d.targetname)
		ORDER BY a.targetname,a.actual_time
			$$;
	OPEN loganalysis_tagsstatsref FOR EXECUTE query USING sdate, edate, span, aggr, server_id, tags;
	RETURN loganalysis_tagsstatsref;
END;
$BODY$
LANGUAGE PLPGSQL;

/*
-- This method collects all the statistics regarding the checkpoints,
-- among the given intervals for the given server.
--
-- RETURNS a REFCURSOR to the calling portion.
--
-- Parameters:
--
-- sdate		: Checkpoint stats starting interval time.
-- edate		: Checkpoint stats end interval time.
-- span			: Interval time for the metrices.
-- aggr			: Aggrgate to apply on this.
-- server_id	: Checkpoint stats for the server.
--
-- Implementation:
--
-- Fetching the log lines from server_logs, which are like below
--
-- checkpoint complete: wrote 2 buffers (1.6%); 0 transaction log file(s) added, 0 removed, 0 recycled; write=0.190 s, sync=0.006 s, total=0.788 s; sync files=2, longest=0.004 s, average=0.002 s
--
-- and collecting the stats about buffers, transaction logs, ....
*/

CREATE OR REPLACE FUNCTION pem.loganalysis_checkpointstats(sdate TIMESTAMP, edate TIMESTAMP, span INTERVAL, aggr TEXT, server_id INT) RETURNS REFCURSOR
AS
$BODY$
DECLARE
checkpoint_statsref REFCURSOR:='loganalysis_chkpointsref';
query TEXT:='';
BEGIN
	IF ((sdate IS NULL OR edate IS NULL) OR (sdate > edate)) THEN
		RAISE EXCEPTION 'LOGANALYSIS_CHECKPOINTSTATS: Invalid time range.';
	ELSE
		IF (span IS NULL OR (span::interval <= '00:00:00'::interval)) THEN
		RAISE EXCEPTION 'LOGANALYSIS_CHECKPOINTSTATS: Invalid span.';
		END IF;
	END IF;

	IF (server_id IS NULL OR server_id < 0) THEN
		RAISE EXCEPTION 'LOGANALYSIS_CHECKPOINTSTATS: Invalid server id has been detected.';
	END IF;

	IF (aggr IS NULL OR (trim(both ' ' FROM aggr) = '') OR (aggr !~ '^SUM$|^AVG$|^MIN$|^MAX$')) THEN
		RAISE EXCEPTION 'LOGANALYSIS_CHECKPOINTSTATS: Invalid aggregate.';
	END IF;


	query :=
		$$
		SELECT
			a.metric,
			ARRAY[((a.actual_time * EXTRACT(EPOCH FROM $3::INTERVAL)) + EXTRACT(EPOCH FROM $1::timestamp))::double precision,
				COALESCE(d.metric_value::double precision, 0::double precision)
			] AS data_series
		FROM
			(SELECT * FROM
				(SELECT
					unnest(ARRAY['BUFFER','ADDED','REMOVED','RECYCLED','WROTE','SYNC','TOTAL','SYNC_FILE']) AS metric
				) t1,
				(SELECT
					generate_series(0, (EXTRACT(EPOCH FROM $2::TIMESTAMP - $1::TIMESTAMP)/EXTRACT(EPOCH FROM $3::INTERVAL))::int - 1, 1) as actual_time
				) t2
			) a
			LEFT JOIN
			(SELECT
				metric,
				actual_time,
				CASE
				WHEN $4::TEXT = 'MIN' THEN
					COALESCE((SELECT * FROM UNNEST(array_agg(metric_value)) WHERE unnest!=0 ORDER BY unnest ASC LIMIT 1), 0)
				WHEN $4::TEXT = 'MAX' THEN
					MAX(metric_value)
				ELSE SUM(metric_value)
				END AS metric_value
			FROM
				(SELECT
					(EXTRACT(EPOCH FROM (log_time - $1::TIMESTAMP)) / EXTRACT(EPOCH FROM $3::interval))::int as actual_time,
					UNNEST(ARRAY['BUFFER','ADDED','REMOVED','RECYCLED','WROTE','SYNC','TOTAL','SYNC_FILE']) AS metric,
					UNNEST(ARRAY[
						SUBSTRING(message FROM '\d+ (?=buffers)')::numeric,
						SUBSTRING(message FROM '\d+ (?=transaction log file\(s\) added)')::numeric,
						SUBSTRING(message FROM '\d+ (?=removed,)')::numeric,
						SUBSTRING(message FROM '\d+ (?=recycled;)')::numeric,
						SUBSTRING(message FROM '[0-9\.]+ (?=s, sync=)')::numeric,
						SUBSTRING(message FROM '[0-9\.]+ (?=s, total=)')::numeric,
						SUBSTRING(message FROM '[0-9\.]+ (?=s; sync files=)')::numeric,
						SUBSTRING(message FROM '[0-9]+(?=, longest=)')::numeric
					]) AS metric_value
				FROM
					pemdata.server_logs
				WHERE
					error_severity = 'LOG' AND message LIKE 'checkpoint complete:%' AND
					message ~ '^checkpoint complete: wrote \d+ buffers \([0-9\.]+%\); \d+ transaction log file\(s\) added,' AND
					server_id = $5::INT AND log_time >= $1::TIMESTAMP AND log_time <= $2::TIMESTAMP
				) b
			GROUP BY actual_time, metric
			) d ON (a.actual_time = d.actual_time AND a.metric = d.metric)
		ORDER BY a.metric,a.actual_time
		$$;
		OPEN checkpoint_statsref FOR EXECUTE query USING sdate, edate, span, aggr, server_id;
	RETURN checkpoint_statsref;
END;
$BODY$
LANGUAGE PLPGSQL;

/*
-- This method collects all the statistics regarding the temp file usage,
-- among the given intervals for the given server.
--
-- RETURNS a REFCURSOR to the calling portion.
--
-- Parameters:
--
-- sdate		: Checkpoint stats start time.
-- edate		: Checkpoint stats end time.
-- span			: Checkpoint interval time.
-- aggr			: Aggregate method to apply.
-- server_id	: Checkpoint stats for the server.
--
-- Implementation:
--
-- Fetch the log lines from server_logs, which are like below
--
-- temporary file: path "base/pgsql_tmp/pgsql_tmp2652.0", size 2187264
--
-- and calculate the aggregate values of the size.
*/
CREATE OR REPLACE FUNCTION pem.loganalysis_tempfilestats(sdate TIMESTAMP, edate TIMESTAMP, span INTERVAL, aggr TEXT,server_id INT) RETURNS REFCURSOR
AS
$BODY$
DECLARE
tempfilestats_ref REFCURSOR:='loganalysis_tempfilestats';
query TEXT:= '';

BEGIN

	IF ((sdate IS NULL OR edate IS NULL) OR (sdate > edate)) THEN
		RAISE EXCEPTION 'LOGANALYSIS_TEMPFILEUSAGE: Invalid time range.';
	ELSE
		IF (span IS NULL OR (span::interval <= '00:00:00'::interval)) THEN
		RAISE EXCEPTION 'LOGANALYSIS_TEMPFILEUSAGE: Invalid span.';
		END IF;
	END IF;

	IF (server_id IS NULL OR server_id < 0) THEN
		RAISE EXCEPTION 'LOGANALYSIS_TEMPFILEUSAGE: Invalid server id.';
	END IF;

	IF (aggr IS NULL OR (trim(both ' ' FROM aggr) = '') OR (aggr !~ '^SUM$|^AVG$|^MAX$|^MIN$')) THEN
		RAISE EXCEPTION 'LOGANALYSIS_TEMPFILEUSAGE: Invalid aggregate.';
	END IF;

	query :=
			$$
			SELECT
			    'TEMP_FILES' AS metric,
			    ARRAY[((a.actual_time * EXTRACT(EPOCH FROM $3::INTERVAL)) + EXTRACT(EPOCH FROM $1::timestamp))::double precision,
				  COALESCE(d.metric_value::double precision, 0::double precision)
			    ] AS data_series
			FROM
			    (SELECT * FROM
				(SELECT
					generate_series(0, (EXTRACT(EPOCH FROM $2::TIMESTAMP - $1::TIMESTAMP)/EXTRACT(EPOCH FROM $3::INTERVAL))::int - 1, 1) as actual_time
				) t2
			    ) a
			LEFT JOIN
			(SELECT
				actual_time,
				CASE
				WHEN $4::TEXT = 'MIN' THEN
					COALESCE((SELECT * FROM UNNEST(array_agg(metric_value)) WHERE unnest!=0 ORDER BY unnest ASC LIMIT 1), 0)
				WHEN $4::TEXT = 'MAX' THEN
					MAX(metric_value)
				ELSE SUM(metric_value)
				END AS metric_value
			FROM
				(SELECT
					(EXTRACT(EPOCH FROM (log_time - $1::TIMESTAMP)) / EXTRACT(EPOCH FROM $3::interval))::int as actual_time,
					SUBSTRING(message FROM '\d+$')::NUMERIC AS metric_value
				FROM
					pemdata.server_logs
				WHERE
					error_severity = 'LOG' AND message LIKE 'temporary file:%' AND
					message ~ '^temporary file: path "(?:[^"]|(?:""))*", size \d+$' AND
					server_id = $5::INT AND log_time >= $1::TIMESTAMP AND log_time <= $2::TIMESTAMP
				) b
			GROUP BY actual_time
			) d ON (a.actual_time = d.actual_time)
		ORDER BY a.actual_time
			$$;

			OPEN tempfilestats_ref for EXECUTE query USING sdate, edate, span, aggr, server_id;
			RETURN tempfilestats_ref;
END;
$BODY$
LANGUAGE PLPGSQL;

/*
-- This method collects all the statistics regarding the locks information,
-- among the given intervals for the given server.
--
-- RETURNS a REFCURSOR to the calling portion.
--
-- Parameters:
--
-- sdate		: Checkpoint stats start time.
-- edate		: Checkpoint stats end time.
-- span			: Checkpoint interval time.
-- aggr			: Aggregate to apply.
-- server_id	: Checkpoint stats for the server.
--
-- Implementation:
--
-- Fetch the logs from the server_logs, which are like below
--
-- process 3672 still waiting for AccessShareLock on relation 845939 of database 12002 after 1014.000 ms
--
-- and collecting stats about each lock.
*/

CREATE OR REPLACE FUNCTION pem.loganalysis_locksstats(sdate TIMESTAMP, edate TIMESTAMP, span INTERVAL, aggr TEXT, server_id INT) RETURNS REFCURSOR
AS
$BODY$
DECLARE
loganalysis_locksref REFCURSOR:= 'loganalysis_locksstats';
query TEXT:='';

BEGIN

	IF ((sdate IS NULL OR edate IS NULL) OR (sdate > edate)) THEN
		RAISE EXCEPTION 'LOGANALYSIS_LOCKSSTATS: Invalid time range.';
	ELSE
		IF (span IS NULL OR (span::interval <= '00:00:00'::interval)) THEN
		RAISE EXCEPTION 'LOGANALYSIS_LOCKSSTATS: Invalid span.';
		END IF;
	END IF;

	IF (server_id IS NULL OR server_id < 0) THEN
		RAISE EXCEPTION 'LOGANALYSIS_LOCKSSTATS: Invalid server id.';
	END IF;

	IF (aggr IS NULL OR (trim(both ' ' FROM aggr) = '') OR (aggr !~ '^SUM$|^AVG$|^MIN$|^MAX$')) THEN
		RAISE EXCEPTION 'LOGANALYSIS_LOCKSSTATS: Invalid aggregate.';
	END IF;

	query := $$
		SELECT
			a.metric,
			ARRAY[((a.actual_time * EXTRACT(EPOCH FROM $3::INTERVAL)) + EXTRACT(EPOCH FROM $1::timestamp))::double precision,
				COALESCE(d.metric_value::double precision, 0::double precision)
			] AS data_series
		FROM
			(SELECT * FROM
				(SELECT
					UNNEST(ARRAY['AccessShareLock',
						     'RowShareLock',
						     'RowExclusiveLock',
						     'ShareUpdateExclusiveLock',
						     'ShareLock',
						     'ShareRowExclusiveLock',
						     'ExclusiveLock',
						     'AccessExclusiveLock'
						    ]
					       ) AS metric
				) t1,
				(SELECT
					generate_series(0, (EXTRACT(EPOCH FROM $2::TIMESTAMP - $1::TIMESTAMP)/EXTRACT(EPOCH FROM $3::INTERVAL))::int - 1, 1) as actual_time
				) t2
			) a
			LEFT JOIN
			(SELECT
				metric,
				actual_time,
				CASE
				WHEN $4::TEXT = 'MIN' THEN
					COALESCE((SELECT * FROM UNNEST(array_agg(metric_value)) WHERE unnest!=0 ORDER BY unnest ASC LIMIT 1), 0)
				WHEN $4::TEXT = 'MAX' THEN
					MAX(metric_value)
				ELSE SUM(metric_value)
				END AS metric_value
			FROM
				(SELECT
					(EXTRACT(EPOCH FROM (log_time - $1::TIMESTAMP)) / EXTRACT(EPOCH FROM $3::interval))::int as actual_time,
					UNNEST(ARRAY['AccessShareLock',
						     'RowShareLock',
						     'RowExclusiveLock',
						     'ShareUpdateExclusiveLock',
						     'ShareLock',
						     'ShareRowExclusiveLock',
						     'ExclusiveLock',
						     'AccessExclusiveLock'
						     ]
					      )as metric,
					UNNEST(ARRAY[
						     CASE WHEN 'AccessShareLock' ~~* SUBSTRING(message FROM '[a-zA-Z]+(?= on relation \d+ of database \d+)') THEN 1 ELSE 0 END,
						     CASE WHEN 'RowShareLock' ~~* SUBSTRING(message FROM '[a-zA-Z]+(?= on relation \d+ of database \d+)') THEN 1 else 0 END,
						     CASE WHEN 'RowExclusiveLock' ~~* SUBSTRING(message FROM '[a-zA-Z]+(?= on relation \d+ of database \d+)') then 1 else 0 END,
						     CASE WHEN 'ShareUpdateExclusiveLock' ~~* SUBSTRING(message FROM '[a-zA-Z]+(?= on relation \d+ of database \d+)') then 1 else 0 END,
						     CASE WHEN 'ShareLock' ~~* SUBSTRING(message FROM '[a-zA-Z]+(?= on relation \d+ of database \d+)') then 1 else 0 END,
						     CASE WHEN 'ShareRowExclusiveLock' ~~* SUBSTRING(message FROM '[a-zA-Z]+(?= on relation \d+ of database \d+)') then 1 else 0 END,
						     CASE WHEN 'ExclusiveLock' ~~* SUBSTRING(message FROM '[a-zA-Z]+(?= on relation \d+ of database \d+)') then 1 else 0 END,
						     CASE WHEN 'AccessExclusiveLock' ~~* SUBSTRING(message FROM '[a-zA-Z]+(?= on relation \d+ of database \d+)') THEN 1 ELSE 0 END
						    ]
					      ) as metric_value
				FROM
					pemdata.server_logs
				WHERE
					error_severity = 'LOG' AND message LIKE 'process %' AND
					message ~ '^process \d+ still waiting for [a-zA-Z]+ on relation \d+ of database \d+ after [0-9\.]+ ms$' AND
					server_id = $5::INT AND log_time >= $1::TIMESTAMP AND log_time <= $2::TIMESTAMP
				) b
			GROUP BY actual_time, metric
			) d ON (a.actual_time = d.actual_time AND a.metric = d.metric)
		ORDER BY a.metric,a.actual_time

	$$;
	OPEN loganalysis_locksref FOR EXECUTE query USING sdate, edate, span, aggr, server_id;
	RETURN loganalysis_locksref;

END;
$BODY$
LANGUAGE PLPGSQL;

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
			'Date(' || (EXTRACT(EPOCH FROM log_time) * 1000)::numeric(40, 0)::text || ')' AS log_time,
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
			'Date(' || (EXTRACT(EPOCH FROM log_time) * 1000)::numeric(40, 0)::text || ')' AS log_time,
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
		'Date(' || (EXTRACT(EPOCH FROM log_time) * 1000)::numeric(40, 0)::text || ')' AS log_time,
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
			'Date(' || (EXTRACT(EPOCH FROM log_time) * 1000)::numeric(40, 0)::text || ')' AS log_time,
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

/*
-- This method collects the stats for sessions, connections
-- among the given intervals of the given server.
--
-- RETURNS REFCURSOR to the calling portion.
--
-- Parameters:
--
-- sdate		: Checkpoint stats start time.
-- edate		: Checkpoint stats end time.
-- span			: Interval time.
-- aggr			: Aggregate to apply on.
-- server_id	: Checkpoint stats for the server.
--
-- Note: We need log_connections = on, log_disconnections = on to be configured on the monitored server.
*/

CREATE OR REPLACE FUNCTION pem.loganalysis_session_connection_stats(sdate TIMESTAMP, edate TIMESTAMP, span INTERVAL, aggr TEXT, server_id INT) RETURNS REFCURSOR
AS
$BODY$
DECLARE
loganalysis_session_connection_stats_ref REFCURSOR:= 'loganalysis_session_connection_stats';
query TEXT := '';

BEGIN

	IF ((sdate IS NULL OR edate IS NULL) OR (sdate > edate)) THEN
		RAISE EXCEPTION 'LOGANALYSIS_SESSION_CONNECTION_STATS: Invalid time range.';
	ELSE
		IF (span IS NULL OR (span::interval <= '00:00:00'::interval)) THEN
		RAISE EXCEPTION 'LOGANALYSIS_SESSION_CONNECTION_STATS: Invalid span.';
		END IF;
	END IF;

	IF (server_id IS NULL OR server_id < 0) THEN
		RAISE EXCEPTION 'LOGANALYSIS_SESSION_CONNECTION_STATS: Invalid server id.';
	END IF;

	IF (aggr IS NULL OR (trim(both ' ' FROM aggr) = '') OR (aggr !~ '^SUM$|^AVG$|^MIN$|^MAX$')) THEN
		RAISE EXCEPTION 'LOGANALYSIS_SESSION_CONNECTION_STATS: Invalid aggregate.';
	END IF;

	query :=
			$$
			SELECT
				a.metric,
				ARRAY[((a.actual_time * EXTRACT(EPOCH FROM $3::INTERVAL)) + EXTRACT(EPOCH FROM $1::timestamp))::double precision,
				        COALESCE(d.metric_value::double precision, 0::double precision)
				     ] AS data_series
			FROM
				(SELECT * FROM
				    (SELECT
					UNNEST(ARRAY['Connections Authenticated', 'Connection Attempts']) AS metric
				    ) t1,
				    (SELECT
					generate_series(0, (EXTRACT(EPOCH FROM $2::TIMESTAMP - $1::TIMESTAMP)/EXTRACT(EPOCH FROM $3::INTERVAL))::int - 1, 1) as actual_time
				    ) t2
			        ) a
			LEFT JOIN
			    (SELECT
				metric,
				actual_time,
				CASE
				WHEN $4::TEXT = 'MIN' THEN
					COALESCE((SELECT * FROM UNNEST(array_agg(metric_value)) WHERE unnest!=0 ORDER BY unnest ASC LIMIT 1), 0)
				WHEN $4::TEXT = 'MAX' THEN
					MAX(metric_value)
				ELSE SUM(metric_value)
				END AS metric_value
			    FROM
				(
					WITH session_conn_details AS
					(
						SELECT
							message,
							(EXTRACT(EPOCH FROM (log_time - $1::TIMESTAMP)) / EXTRACT(EPOCH FROM $3::interval))::int as actual_time
						FROM
							pemdata.server_logs
						WHERE
							message IS NOT NULL AND trim(BOTH ' ' FROM message) != '' AND
							error_severity = 'LOG' AND message ~ '^disconnection:|^connection received:'
							AND server_id = $5::INT AND log_time >= $1::TIMESTAMP AND
							log_time <= $2::TIMESTAMP
					)
					(
						SELECT
							'Connections Authenticated' as metric,
							actual_time,
							COUNT(message) AS metric_value
						FROM
							session_conn_details
						WHERE
							message ~ '^disconnection:\s+session time:\s+[0-9:\.]+\s+(?:user=(?:[^\s]+)\s+)?(?:database=(?:[^\s]+)\s+)?(?:host=(?:[^\s]+)\s+)?'
						GROUP BY actual_time

						UNION ALL

						SELECT
							'Connection Attempts' AS metric,
							actual_time,
							COUNT(message) AS metric_value
						FROM
							session_conn_details
						WHERE
							message ~ '^connection\s+received:\s+(?:host=(?:[^\s]+)\s+)?'
						GROUP BY actual_time
					)
				) b
			GROUP BY actual_time, metric
			) d ON (a.actual_time = d.actual_time AND a.metric = d.metric)
		ORDER BY a.metric,a.actual_time
			$$;
	OPEN loganalysis_session_connection_stats_ref FOR EXECUTE query USING sdate, edate, span, aggr, server_id;
	RETURN loganalysis_session_connection_stats_ref;
END;
$BODY$
LANGUAGE PLPGSQL;

COMMIT TRANSACTION;
