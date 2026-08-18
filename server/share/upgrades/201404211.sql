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
'SELECT 201404211::integer;'
  LANGUAGE 'sql' IMMUTABLE;

/*
-- Table: pem.logexp_tagbasecharts
--
-- This table stroes the tag based table information.
-- tag based table generates the aggregate values based on command_tag of server_logs table.
--
--
*/

CREATE TABLE pem.logexp_tagbasecharts
		(
			id SERIAL PRIMARY KEY,
			exact_match BOOLEAN,
			tags TEXT[],
			target_name	TEXT
		);

COMMENT ON COLUMN pem.logexp_tagbasecharts.id IS 'Tag based chart id';
COMMENT ON COLUMN pem.logexp_tagbasecharts.exact_match IS 'Is it a partial match or an exact match';
COMMENT ON COLUMN pem.logexp_tagbasecharts.tags IS 'tags to generate the metrices. Ex:- SELECT, UPDATE, DELETE';
COMMENT ON COLUMN pem.logexp_tagbasecharts.target_name IS 'Filed name to look for the above given tags';

INSERT INTO pem.logexp_tagbasecharts VALUES
			--ID		EXACT_MATCH	TAGS
		(
			1,		TRUE,		ARRAY['SELECT', 'FETCH', 'COPY', 'INSERT', 'UPDATE', 'DELETE'], 'command_tag'
		),
		(
			2,		FALSE,		ARRAY['CREATE', 'ALTER', 'DROP', 'TRUNCATE'], 'command_tag'
		),
		(
			3,		TRUE,		ARRAY['COMMIT','ROLLBACK','SAVEPOINT'], 'command_tag'
		),
		(
			4,		TRUE,		ARRAY['SELECT waiting', 'INSERT waiting', 'UPDATE waiting', 'DELETE waiting'], 'command_tag'
		),
		(
			5,		TRUE,		ARRAY['IDLE', 'IDLE in transaction', 'IDLE in transaction (aborted)'], 'command_tag'
		);

CREATE TABLE pem.logexp_charts
		(
			id SERIAL PRIMARY KEY,
			assoc_chart_id INT,
			analyzer_name TEXT,
			chart_headers TEXT,
			method TEXT,
			TYPE INT,
			tag_chart_id INT,
			lables TEXT[] DEFAULT NULL,
			is_pie	BOOLEAN	DEFAULT FALSE,
			CONSTRAINT pem_logexp_chart_fk_assoc_chart FOREIGN KEY (assoc_chart_id) REFERENCES pem.logexp_charts(id)
			MATCH SIMPLE ON UPDATE CASCADE ON DELETE CASCADE INITIALLY DEFERRED,
			CONSTRAINT pem_logexp_chart_type_check CHECK (TYPE IN (0, 1)),
			CONSTRAINT pem_logexp_chart_fk_tag_chart_id FOREIGN KEY(tag_chart_id) REFERENCES pem.logexp_tagbasecharts(id)
		);

COMMENT ON COLUMN pem.logexp_charts.id IS 'ID of log analysis experts chart';
COMMENT ON COLUMN pem.logexp_charts.analyzer_name IS 'Display name for the log expert wizard';
COMMENT ON COLUMN pem.logexp_charts.chart_headers IS 'Chart headers while rendering in the expert report';
COMMENT ON COLUMN pem.logexp_charts.method IS 'Associated PL/PGSQL method to work on the server_logs';
COMMENT ON COLUMN pem.logexp_charts.type IS 'Chart category type. L-Line, T-Table';
COMMENT ON COLUMN pem.logexp_charts.tag_chart_id IS 'Tag Chart ID for';
COMMENT ON COLUMN pem.logexp_charts.lables IS 'Table chart headers';
COMMENT ON COLUMN pem.logexp_charts.is_pie IS 'Do we need to show the line chart metrics as pie also.';

INSERT INTO pem.logexp_charts VALUES
	--ID	ASSOC_CHART_ID	ANALYZER_NAME				CHART_HEADERS				ASSOC_METHOD					TYPE 	TAG_CHART_ID	LABLES				IS_PIE
(
	1,	NULL,		'Summary Statistics',				'Summary Statistics',		'pem.loganalysis_overallstats',		0,	NULL, ARRAY['Statistics', 'Values'], false
),
(
	2,	NULL,		'Hourly DML Statistics',				'Hourly DML Statistics',		'pem.loganalysis_hourlydmlstats',	0,	NULL,  ARRAY['Time', 'Database', 'Command Type', 'Total Count', 'Min Duration (ms)', 'Max Duration (ms)', 'Avg Duration (ms)'], false
),
(
	3,	NULL,		'DML Statistics',			'DML Statistics Timeline',		'pem.loganalysis_tagsstats',		1,	1,  NULL, true
),
(
	4,	NULL,		'DDL Statistics',			'DDL Statistics Timeline',		'pem.loganalysis_tagsstats',		1,	2,  NULL, true
),
(
	5,	NULL,		'Commit/Rollback Statistics',	'COMMIT And ROLLBACK Statistics Timeline',	'pem.loganalysis_tagsstats', 		1, 	3, NULL, true
),
(
	6,	NULL,		'Checkpoint Statistics',		'CHECKPOINT Statistics Timeline',		'pem.loganalysis_checkpointstats', 	1,	NULL, NULL, true
),
(
	7,	NULL,		'Log Event Statistics',		'LOG Event Statistics',			'pem.loganalysis_logeventstats',	0,	NULL,	ARRAY['Error Severity', 'Message', 'Total Count'], false
),
(
	8,	NULL,		'Log Statistics',		'LOG Statistics',			'pem.loganalysis_logstats',	0,	NULL,  ARRAY['Error Severity', 'Total Count'], false
),
(
	9,	NULL,		'Temp Queries Statistics',				'Temp Generated Queries',	'pem.loganalysis_tempusedqueries',	0,	NULL, ARRAY['Log Time', 'TempFile Size(Bytes)', 'Query'], false
),
(
	10,	9,			'Temporary Files Statistics',	'Temp File Statistics Timeline',		'pem.loganalysis_tempfilestats',	1,	NULL, NULL, false
),
(
	11,	NULL,		'Lock Statistics',		'Lock Statistics Timeline',		'pem.loganalysis_locksstats',		1,	NULL, NULL, true
),
(
	12, NULL,		'Waitings Statistics',		'Waiting Statistics Timeline',	'pem.loganalysis_tagsstats',		1, 	4, NULL, true
),
(
	13,	NULL,		'Idle Statistics',		'Idle Statistics Timeline',		'pem.loganalysis_tagsstats',		1,	5,	NULL, true
),
(
	14,	NULL,		'Autovacuum Statistics',	'AUTOVACUUM Statistics',	'pem.loganalysis_autovacuumstats',	0,	NULL, ARRAY['Log Time', 'Relation', 'Index Details', 'Page Details', 'Tuple Details', 'Buffer Details', 'Read Rate', 'System Usage'], false
),
(
	15, NULL,		'Autoanalyze Statistics', 	'AUTOANALYZE Statistics', 'pem.loganalysis_autoanalyzestats', 0, NULL, ARRAY['Log Time', 'Relation', 'System Usage'], false
),
(
	16,	NULL,		'Slow Running Query Statistics',	'Slow Query Statistics',	'pem.loganalysis_slowqueries',		0,	NULL, ARRAY['Log Time', 'Tag', 'Query', 'Parameters', 'Duration (ms)', 'Host', 'Database'], false
),
(
	17,	NULL,		'Frequently Executed Query Statistics',	'Frequently Executed Query Statistics',	'pem.loganalysis_freqexe_queries',	0,	NULL, ARRAY['Query', 'Parameters', 'No.Of Times Executed', 'Total Duration (ms)'], false
),
(
	18,	NULL,		'Most Time Consumed Query Statistics',			'Most Time Executed Query Statistics',	'pem.loganalysis_mosttime_exec_queries',	0,	NULL, ARRAY['Query', 'Parameters', 'No.Of Times Executed', 'Total Duration (ms)'], false
),
(
	19,	NULL,		'Connections Overview',		'Connections Overview Timeline',	'pem.loganalysis_session_connection_stats',	1,	NULL, NULL, true
);

/*
--
-- Tuning Section
--
-- 1. A wrapper function to create function based index.
-- 2. Index on function based index.
-- 3. Index on error_severity.
-- 4. Index on command_tag.
-- 5. Index on message.
--
*/

CREATE OR REPLACE FUNCTION pem.date_trunc_minutes(s timestamp with time zone)
RETURNS timestamp with time zone
LANGUAGE sql
IMMUTABLE
AS $body$
    SELECT date_trunc('MINUTES', $1);
$body$
;
CREATE INDEX server_logs_logtime_by_minutes_idx ON pemdata.server_logs(pem.date_trunc_minutes(log_time));

CREATE INDEX server_logs_error_severity_idx ON pemdata.server_logs(error_severity);

CREATE INDEX server_logs_command_tag_idx ON pemdata.server_logs(command_tag);

CREATE INDEX server_logs_messages ON pemdata.server_logs USING btree (message  text_pattern_ops);

/*
-- This method gets the start, end datetime intervals,
-- And it adjusts the time intervals as offsets.
--
-- Returns OUT parameters as current date, start date offset, end date offset.
--
-- Parameters:
-- sdate	: Start date time for the report.
-- edate	: End date time for the report.
-- sid		: ServerID
--
*/

CREATE OR REPLACE FUNCTION pem.validate_intervals(sdate TIMESTAMP, edate TIMESTAMP, sid INT, span INTERVAL, sdate_offset_timestamp OUT TIMESTAMP, edate_offset_timestamp OUT TIMESTAMP) RETURNS SETOF RECORD
AS
$BODY$
DECLARE
adjs_sdate TIMESTAMP;
adjs_edate TIMESTAMP;
present_date TIMESTAMP;
sdate_offset INTERVAL;
edate_offset INTERVAL;

BEGIN
	-- Get the offset for the start date and time.
	--
	SELECT DATE_TRUNC('MINUTES', now()) INTO present_date;
	SELECT present_date - date_trunc('MINUTES', sdate) INTO sdate_offset;
	SELECT present_date - date_trunc('MINUTES', edate) INTO edate_offset;

	IF (sdate_offset > edate_offset AND EXISTS(
				SELECT true FROM pemdata.server_logs s
				WHERE  s.server_id = sid AND s.log_time BETWEEN date_trunc('MINUTES', sdate) AND date_trunc('MINUTES', edate))) THEN
		-- Yes, Data exists in the intervals.
		-- Adjust the intervals as per the data availability.
		--
		SELECT
			min(s.log_time), max(s.log_time) INTO adjs_sdate, adjs_edate
		FROM
			pemdata.server_logs s
		WHERE
			s.server_id = sid AND s.log_time BETWEEN date_trunc('MINUTES', sdate) AND date_trunc('MINUTES', edate);

		IF ( sdate <= adjs_sdate ) THEN
			sdate := adjs_sdate;
		END IF;
		IF ( edate >= adjs_edate ) THEN
			edate := adjs_edate;
		END IF;

		-- Now, findout the sdate_offset, edate_offset as per the client, server timezones.
		--
		adjs_sdate := date_trunc('Minutes', present_date-(present_date-sdate)::INTERVAL)::TIMESTAMP;
		adjs_edate := date_trunc('Minutes', present_date-(present_date-edate)::INTERVAL)::TIMESTAMP;

		-- There might be chances that the adjusted time's difference might be < span.
		-- In that case, through an error.
		--

		IF (adjs_edate - adjs_sdate < span) THEN
			RAISE EXCEPTION 'Invalid span. Data found in the range %-%',adjs_sdate, adjs_edate ;
		END IF;

		SELECT adjs_sdate, adjs_edate INTO sdate_offset_timestamp,edate_offset_timestamp;

	ELSIF (sdate > edate) THEN
			RAISE EXCEPTION 'Invalid time interval';
	ELSE
		RAISE EXCEPTION 'Data not found for the given intervals';
	END IF;
	RETURN NEXT;
END;
$BODY$
LANGUAGE PLPGSQL;

/*
-- This method collects the aggregated values of DML, DDL opertaions
-- from the pemdata.server_logs table.
--
--
-- Retruns the REF CURSOR to the calling portion
--
-- Parameters:
--
-- startDate	: Aggregated values starts time
-- endDate		: Aggregated values end time
-- span			: Interval time for the aggregate values
-- serverID		: What server logs you want to collect data
-- aggr			: What aggregate operation you want to imply
-- targetname	: What is the target or column name
-- tags			: What command metrices you want. Ex:- SELECT, CREATE, ALTER, DELETE ..
-- exactmatch	: Do you want an exact match or partial match from beginning.
--
-- Usage:
--
-- DML Stats
--
-- > SELECT pem.loganalysis_tagsstats(
			'06/03/2014 02:00:00'::TIMESTAMP, '06/03/2014 03:00:00'::TIMESTAMP, '2 Minutes'::INTERVAL, 'MAX'::TEXT, 3::INT, 'command_tag'::TEXT,
			ARRAY['SELECT', 'FETCH', 'UPDATE', 'DELETE', 'INSERT'], true);
--
-- DDL Stats
--
-- > SELECT pem.loganalysis_tagsstats(
			'06/03/2014 02:00:00'::TIMESTAMP, '06/03/2014 03:00:00'::TIMESTAMP, '2 Minutes'::INTERVAL, 'SUM'::TEXT,3::INT, 'command_tag'::TEXT,
			ARRAY['CREATE', 'ALTER', 'DROP', 'TRUNCATE'], false);
--

*/


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
					targetname AS metric,
					ARRAY[EXTRACT(EPOCH FROM actual_time),(CASE
									WHEN $4::TEXT ~ '^SUM$|^MAX$|^MIN$' THEN
									metric_value
									WHEN $4::TEXT = 'AVG' AND (EXTRACT(EPOCH FROM $3::interval)/60)::INT != 0 THEN
									(metric_value/(EXTRACT(EPOCH FROM $3::interval)/60))::INT
									END)
					]
					AS data_series
				FROM
				(
					WITH timerage_with_actual_interval AS
					(
						SELECT
							generate_series($1::TIMESTAMP, $2::TIMESTAMP, $3::INTERVAL) AS actual_time
					)
					SELECT
						targetname,
						actual_time,
						CASE
							WHEN $4::TEXT = 'MIN' THEN
							COALESCE((SELECT * FROM UNNEST(array_agg(metric_value)) WHERE unnest!=0 ORDER BY unnest ASC LIMIT 1), 0)
							WHEN $4::TEXT = 'MAX' THEN
							MAX(metric_value)
							ELSE
							SUM(metric_value)
						END AS metric_value
					FROM
						(
							WITH timerange_with_1min_interval AS
							(
							SELECT
								generate_series($1::timestamp, $2::timestamp, '1 Minute'::interval) AS start_time
							)
							SELECT
								targetname,
								start_time,
								SUM(metrices_values) AS metric_value
							FROM
							(
								SELECT
									start_time,$$||
									targetname||$$ AS targetname,
									COUNT(command_tag) AS metrices_values
								FROM
									pemdata.server_logs
								JOIN
									timerange_with_1min_interval
								ON 	pem.date_trunc_minutes(log_time) = start_time
								WHERE	server_id = $5::integer AND error_severity = 'LOG'
								GROUP BY
									start_time,$$||
									targetname||$$
								HAVING $$||
									targetname||$$ IN ( SELECT unnest($6::text[]) )

								UNION ALL

								SELECT
									start_time,
									targetname,
								0 AS metrices_values
								FROM
									timerange_with_1min_interval,
								(
								SELECT
									unnest($6::text[]) targetname
								) AS commands
							) AS tag_summary_per_1min
							GROUP BY targetname, start_time
							ORDER BY targetname, start_time
					) AS tag_info_1min
				JOIN
					timerage_with_actual_interval ON start_time >= actual_time AND
					(CASE WHEN
						(actual_time+$3::INTERVAL) < $2::TIMESTAMP THEN
							start_time < (actual_time+$3::INTERVAL)
						ELSE
							start_time < ((actual_time+$3::INTERVAL)-((actual_time+$3::INTERVAL)-$2::TIMESTAMP))
					END)
					GROUP BY targetname, actual_time
					ORDER BY targetname, actual_time
				) AS tag_info_with_actual_span
			$$;
	OPEN loganalysis_tagsstatsref FOR EXECUTE query USING sdate, edate, span, aggr, server_id, tags;
	RETURN loganalysis_tagsstatsref;
END;
$BODY$
LANGUAGE PLPGSQL;

/*
-- This method collects the overall statistics about the logs,
-- among the given intervals.
--
-- RETURNS REFCURSOR to the calling portion.
--
-- Parameters:
--
-- sdate	: Report start time
-- edate	: Report end time
-- serverid	: Server we will be generating the report.
*/


CREATE OR REPLACE FUNCTION pem.loganalysis_overallstats(sdate TIMESTAMP, edate TIMESTAMP, server_id INT) RETURNS REFCURSOR  AS
$BODY$
DECLARE
loganalysis_overallstats_ref REFCURSOR:='loganalysis_overallstats';
query TEXT:='';
BEGIN

	IF ((sdate IS NULL OR edate IS NULL) OR (sdate>edate)) THEN
		RAISE EXCEPTION 'LOGANALYSIS_OVERALLSTATS: Invalid interval.';
	END IF;

	IF (server_id IS NULL OR server_id < 0) THEN
		RAISE EXCEPTION 'LOGANALYSIS_OVERALLSTATS: Invalid server id.';
	END IF;

	query :=
		$$
		WITH querypeaktime AS
		(
		SELECT
			date_trunc('seconds', log_time) peaktime, COUNT(*) peakcount
		FROM
			pemdata.server_logs
		WHERE
			command_tag IN ('SELECT', 'INSERT', 'UPDATE', 'DELETE', 'FETCH', 'COPY') AND error_severity = 'LOG' AND
			pem.date_trunc_minutes(log_time) >= $1::TIMESTAMP AND pem.date_trunc_minutes(log_time) < $2::TIMESTAMP AND
			server_id = $3::INT
		GROUP BY date_trunc('seconds', log_time)
		),
		sessiondetails AS
		(
		SELECT
			message, database_name
		FROM
			pemdata.server_logs
		WHERE
			error_severity IN ('LOG') AND (message LIKE 'disconnection:%' OR message LIKE 'connection received:%') AND message ~ '^disconnection:|^connection received:' AND
			pem.date_trunc_minutes(log_time) >= $1::TIMESTAMP AND pem.date_trunc_minutes(log_time) < $2::TIMESTAMP AND
			server_id = $3::INT
		)
		SELECT
				UNNEST(ARRAY[
				'Number of unique queries',
				'Total queries',
				'Total queries duration',
				'First query',
				'Last query',
				'Queries peak time',
				'Number of events',
				'Number of unique events',
				'Total number of sessions',
				'Total duration of sessions',
				'Average sessions duration',
				'Total number of connections',
				'Total number of databases'
				]) AS "Settings",
				UNNEST(ARRAY[
				COUNT(DISTINCT(message))::TEXT,
				COUNT(message)::TEXT,
				justify_interval(
					((SUM(SUBSTRING(substring(message  FROM  '^duration:\s+[0-9\.]+\s+ms\s*') FROM '[0-9\.]+')::REAL/1000))::text||' Seconds')::interval)::TEXT,
				min(log_time)::TEXT,
				max(log_time)::TEXT,
				(
					SELECT
						peaktime::TEXT||' queries '||peakcount::TEXT
					FROM
						querypeaktime ORDER BY peakcount DESC LIMIT 1
				),
				COUNT(error_severity)::TEXT,
				COUNT(DISTINCT(error_severity))::TEXT,
				COUNT(DISTINCT(session_id))::TEXT,
				(
					SELECT
						SUM(SPLIT_PART(SUBSTRING(message FROM '^disconnection:\s+session time:\s+[0-9:\.]+\s+(?=user=(?:[^\s]+)\s+)'),
								'session time:', 2)::INTERVAL)::TEXT
					FROM
						sessiondetails
				),
				ROUND(
				(
					SELECT
						EXTRACT(EPOCH FROM
						SUM(SPLIT_PART(SUBSTRING(message FROM '^disconnection:\s+session time:\s+[0-9:\.]+\s+(?=user=(?:[^\s]+)\s+)'),
								'session time:', 2)::INTERVAL)) * 1000
					FROM
						sessiondetails WHERE message ~ '^disconnection')/NULLIF(COUNT(DISTINCT(session_id)),0)
				)::TEXT||' (ms)'::TEXT,
				(
					SELECT
						COUNT(message)::TEXT
					FROM
						sessiondetails WHERE message ~ '^connection received:'
				),
				(
					SELECT
						-- We may get the database_name as empty string, for the "connection received" log entry.
						-- In this case, we need to skip the counting of empty string by using the following mechanism.
						--
						COUNT(DISTINCT(CASE WHEN database_name IS NULL OR TRIM(BOTH ' ' FROM database_name) = '' THEN NULL ELSE database_name END))::TEXT
					FROM
						sessiondetails
				)
				]) AS "Values"
		FROM
			pemdata.server_logs
		WHERE
			command_tag IN ('SELECT','INSERT', 'UPDATE', 'DELETE', 'COPY', 'FETCH') AND error_severity = 'LOG' AND
			pem.date_trunc_minutes(log_time) >= $1::timestamp AND pem.date_trunc_minutes(log_time) < $2::timestamp AND
			server_id = $3::int;
		$$;

		OPEN loganalysis_overallstats_ref FOR EXECUTE query USING sdate, edate, server_id;

		RETURN loganalysis_overallstats_ref;
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
			metric,
			ARRAY[extract(EPOCH FROM actual_time), (CASE
										WHEN $4::TEXT ~ '^SUM$|^MIN$|^MAX$' THEN
										metric_value
										WHEN $4::TEXT = 'AVG' AND (EXTRACT(EPOCH FROM $3::interval)/60)::INT != 0 THEN
										(metric_value/(EXTRACT(EPOCH FROM $3::interval)/60))::INT
										END)
				]
				AS data_series
		FROM
		(
			WITH timerage_with_actual_interval AS
			(
				SELECT
					generate_series($1::TIMESTAMP, $2::TIMESTAMP, $3::INTERVAL) AS actual_time
			)
			SELECT
				metric,
				actual_time,
				CASE
					WHEN $4::TEXT = 'MIN' THEN
					COALESCE((SELECT * FROM UNNEST(array_agg(metric_value)) WHERE unnest!=0 ORDER BY unnest ASC LIMIT 1), 0)
					WHEN $4::TEXT = 'MAX' THEN
					MAX(metric_value)
					ELSE
					SUM(metric_value)
				END AS metric_value
			FROM
				(
					WITH timerange_with_1min_interval AS
					(
					SELECT
						generate_series($1::TIMESTAMP, $2::TIMESTAMP, '1 Minute'::INTERVAL) AS start_time
					)
					SELECT
						start_time,
						metric,
						SUM(metric_value) AS metric_value
					FROM
					(
					SELECT
						start_time,
						UNNEST(ARRAY['BUFFER','ADDED','REMOVED','RECYCLED','WROTE','SYNC','TOTAL','SYNC_FILE']) AS metric,
						UNNEST(
							ARRAY[
						SUBSTRING(message FROM '\d+ (?=buffers)')::REAL,
						SUBSTRING(message FROM '\d+ (?=transaction log file\(s\) added)')::REAL,
						SUBSTRING(message FROM '\d+ (?=removed,)')::REAL,
						SUBSTRING(message FROM '\d+ (?=recycled;)')::REAL,
						SUBSTRING(message FROM '[0-9\.]+ (?=s, sync=)')::REAL,
						SUBSTRING(message FROM '[0-9\.]+ (?=s, total=)')::REAL,
						SUBSTRING(message FROM '[0-9\.]+ (?=s; sync files=)')::REAL,
						SUBSTRING(message FROM '[0-9]+(?=, longest=)')::REAL
						]
								) AS metric_value
						FROM
							pemdata.server_logs
						JOIN
						timerange_with_1min_interval ON pem.date_trunc_minutes(log_time) = start_time
					WHERE
						error_severity = 'LOG' AND message LIKE 'checkpoint complete:%' AND
						message ~ '^checkpoint complete: wrote \d+ buffers \([0-9\.]+%\); \d+ transaction log file\(s\) added,'
						AND server_id = $5::INT

					UNION ALL

					SELECT
						start_time,
						metric,
						0.0 AS metric_value
					FROM
						timerange_with_1min_interval,
						(
						SELECT
							UNNEST(ARRAY['BUFFER','ADDED','REMOVED','RECYCLED','WROTE','SYNC','TOTAL','SYNC_FILE']) AS metric
						) AS checkpoint_metrices
					) AS checkpoints_info
					GROUP BY start_time, metric
				) AS checkpoints_summary_info
			JOIN
				timerage_with_actual_interval ON start_time >= actual_time AND
				(CASE WHEN
						(actual_time+$3::INTERVAL) < $2::TIMESTAMP THEN
							start_time < (actual_time+$3::INTERVAL)
						ELSE
							start_time < ((actual_time+$3::INTERVAL)-((actual_time+$3::INTERVAL)-$2::TIMESTAMP))
				END)
				GROUP BY metric, actual_time
				ORDER BY metric, actual_time
		) AS checkpoints_complete_info
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
				ARRAY[extract(EPOCH FROM actual_time),(CASE
											WHEN $4::TEXT ~ '^SUM$|^MIN$|^MAX$' THEN
											metric_value
											WHEN $4::TEXT = 'AVG' AND (EXTRACT(EPOCH FROM $3::interval)/60)::INT != 0 THEN
											(metric_value/(EXTRACT(EPOCH FROM $3::interval)/60))::INT
											END)
					] AS data_series
			FROM
			(
				WITH timerage_with_actual_interval AS
				(
					SELECT
						generate_series($1::TIMESTAMP, $2::TIMESTAMP, $3::INTERVAL) AS actual_time
				)
				SELECT
					actual_time,
					CASE
						WHEN $4::TEXT = 'MIN' THEN
						COALESCE((SELECT * FROM UNNEST(array_agg(metric_value)) WHERE unnest!=0 ORDER BY unnest ASC LIMIT 1), 0)
						WHEN $4::TEXT = 'MAX' THEN
						MAX(metric_value)
						ELSE
						SUM(metric_value)
					END AS metric_value
				FROM
				(
					WITH timerange_with_1min_interval AS
					(
						SELECT
							generate_series($1::TIMESTAMP, $2::TIMESTAMP, '1 Minute'::INTERVAL) AS start_time
					)
					SELECT
						start_time,
						SUM(metric_value) metric_value
					FROM
					(
						SELECT
							start_time,
							SUBSTRING(message FROM '\d+$')::NUMERIC AS metric_value
						FROM
							pemdata.server_logs
						JOIN
							timerange_with_1min_interval ON pem.date_trunc_minutes(log_time) = start_time
						WHERE
							error_severity = 'LOG' AND message LIKE 'temporary file:%' AND
							message ~ '^temporary file: path "(?:[^"]|(?:""))*", size \d+$'
							AND server_id = $5::int
						UNION ALL
						SELECT
							start_time,
							0::NUMERIC AS metrices_values
						FROM
							timerange_with_1min_interval
					) as tempfile_summary
					GROUP BY start_time
				) as tempfile_1min_info
				JOIN
					timerage_with_actual_interval ON start_time >= actual_time AND
					(CASE WHEN
						(actual_time+$3::INTERVAL) < $2::TIMESTAMP THEN
							start_time < (actual_time+$3::INTERVAL)
						ELSE
							start_time < ((actual_time+$3::INTERVAL)-((actual_time+$3::INTERVAL)-$2::TIMESTAMP))
					END)
				GROUP BY actual_time
				ORDER BY actual_time
			) AS tempfile_info_with_actual_span
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
		metric,
		ARRAY[EXTRACT(EPOCH FROM actual_time), (CASE
										WHEN $4::TEXT ~ '^SUM$|^MIN$|^MAX$' THEN
										metric_value
										WHEN $4::TEXT = 'AVG' AND (EXTRACT(EPOCH FROM $3::interval)/60)::INT != 0 THEN
										(metric_value/(EXTRACT(EPOCH FROM $3::interval)/60))::INT
									END)
			]AS data_series
	FROM
	(
		WITH timerage_with_actual_interval AS
			(
				SELECT
					generate_series($1::TIMESTAMP, $2::TIMESTAMP, $3::INTERVAL) AS actual_time
			)
		SELECT
			metric,
			actual_time,
			CASE
				WHEN $4::TEXT = 'MIN' THEN
				COALESCE((SELECT * FROM UNNEST(array_agg(metric_value)) WHERE unnest!=0 ORDER BY unnest ASC LIMIT 1), 0)
				WHEN $4::TEXT = 'MAX' THEN
				MAX(metric_value)
				ELSE
				SUM(metric_value)
			END AS metric_value
			FROM
			(
				WITH timerange_with_1min_interval AS
				(
					SELECT generate_series($1::TIMESTAMP, $2::timestamp, '1 Minute'::INTERVAL) as start_time
				)
				SELECT
					start_time,
					metric,
					SUM(lockfound) AS metric_value
				FROM
					(
						SELECT
							UNNEST(ARRAY[
								'AccessShareLock',
								'RowShareLock',
								'RowExclusiveLock',
								'ShareUpdateExclusiveLock',
								'ShareLock',
								'ShareRowExclusiveLock',
								'ExclusiveLock',
								'AccessExclusiveLock'
								]
								)as metric,
								start_time,
								UNNEST(ARRAY[

								CASE WHEN 'AccessShareLock' ~~* SUBSTRING(message FROM '[a-zA-Z]+(?= on relation \d+ of database \d+)') THEN 1 ELSE 0 END,
								CASE WHEN 'RowShareLock' ~~* SUBSTRING(message FROM '[a-zA-Z]+(?= on relation \d+ of database \d+)') THEN 1 else 0 END,
								CASE WHEN 'RowExclusiveLock' ~~* SUBSTRING(message FROM '[a-zA-Z]+(?= on relation \d+ of database \d+)') then 1 else 0 END,
								case when 'ShareUpdateExclusiveLock' ~~* SUBSTRING(message FROM '[a-zA-Z]+(?= on relation \d+ of database \d+)') then 1 else 0 END,
								case when 'ShareLock' ~~* SUBSTRING(message FROM '[a-zA-Z]+(?= on relation \d+ of database \d+)') then 1 else 0 END,
								case when 'ShareRowExclusiveLock' ~~* SUBSTRING(message FROM '[a-zA-Z]+(?= on relation \d+ of database \d+)') then 1 else 0 END,
								case when 'ExclusiveLock' ~~* SUBSTRING(message FROM '[a-zA-Z]+(?= on relation \d+ of database \d+)') then 1 else 0 END,
								CASE WHEN 'AccessExclusiveLock' ~~* SUBSTRING(message FROM '[a-zA-Z]+(?= on relation \d+ of database \d+)') THEN 1 ELSE 0 END
								]
								) as lockfound

							FROM
								pemdata.server_logs
							JOIN
								timerange_with_1min_interval ON pem.date_trunc_minutes(log_time) = start_time
							WHERE
								error_severity = 'LOG' AND message LIKE 'process %' AND
								message ~ '^process \d+ still waiting for [a-zA-Z]+ on relation \d+ of database \d+ after [0-9\.]+ ms$' AND
								server_id = $5::INT

							UNION ALL

							SELECT
								metric,
								start_time,
								0 as lockfound
							FROM
								timerange_with_1min_interval,
							(
							SELECT
								UNNEST(ARRAY[
								'AccessShareLock',
								'RowShareLock',
								'RowExclusiveLock',
								'ShareUpdateExclusiveLock',
								'ShareLock',
								'ShareRowExclusiveLock',
								'ExclusiveLock',
								'AccessExclusiveLock'
								]
								)AS metric
							) as locks
					) AS locks_1min_summary
					GROUP BY metric, start_time
			) AS locks_info_with_actual_span
			JOIN
				timerage_with_actual_interval ON start_time >=actual_time AND
				(CASE WHEN
						(actual_time+$3::INTERVAL) < $2::TIMESTAMP THEN
							start_time < (actual_time+$3::INTERVAL)
						ELSE
							start_time < ((actual_time+$3::INTERVAL)-((actual_time+$3::INTERVAL)-$2::TIMESTAMP))
				END)
				GROUP BY metric, actual_time
				ORDER BY metric, actual_time
	) as locks_complete_info
	$$;
	OPEN loganalysis_locksref FOR EXECUTE query USING sdate, edate, span, aggr, server_id;
	RETURN loganalysis_locksref;

END;
$BODY$
LANGUAGE PLPGSQL;

/*

-- This method collects all the statistics regarding autovacuum
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
			log_time,
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
			log_time,
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
		log_time,
		command_tag AS tag,
		-- Dividing the log line like two parts,
		-- {duration (interval ms):} {Query}
		-- and getting the Query from above parts.
		--
		TRIM(BOTH ' ' FROM
			SPLIT_PART(message,
				SUBSTRING(message FROM '^duration:\s+[0-9\.]+\s+ms\s*(?:prepare|parse|bind|execute from fetch|execute|statement)(?:\s+<(?:[^>]|>)+>)?:'), 2)) as query,
			detail AS parameters,
			ROUND(SUBSTRING(SUBSTRING(message FROM '^duration: [0-9\.]+ ms') FROM '[0-9\.]+')::NUMERIC, 2) AS duration,
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

/*
-- This method collects the frequently executed queries, and queries those have taken most time
-- among the given intervals of the given server.
--
-- RETURNS  REFCURSOR to the calling portion.
--
-- Parameters:
--
-- sdate		: Checkpoint stats start time.
-- edate		: Checkpoint stats end time.
-- server_id	: Checkpoint stats for the server.
-- tlimit		: No.Of rows limit to the display table.
--
-- Implementation:
--
-- Fetch the log lines from the server_logs, which are like below
--
-- duration: 0.000 ms  execute <unnamed>: UPDATE pem.probe_schedule SET current_backend_pid = NULL, last_execution_time = now() WHERE probe_id = $1 AND parameter_value_list = $2 AND 	current_backend_pid = pg_backend_pid();
--
-- and sorting these queries based on the frequency and execution time.
*/

CREATE OR REPLACE FUNCTION pem.loganalysis_freqexe_queries(sdate TIMESTAMP, edate TIMESTAMP, server_id INT, tlimit INT DEFAULT 20) RETURNS REFCURSOR
AS
$BODY$
DECLARE
loganalysis_freqexe_queries_ref REFCURSOR:= 'loganalysis_freqexe_queries';
loganalysis_mosttimeexe_queries_ref REFCURSOR:= 'loganalysis_mosttimeexe_queries';
query text := '';

BEGIN

	IF ((sdate IS NULL OR edate IS NULL) OR (sdate > edate)) THEN
		RAISE EXCEPTION 'LOGANALYSIS_FREQEXE_QUERIES: Invalid time.';
	END IF;

	IF (server_id IS NULL OR server_id < 0) THEN
		RAISE EXCEPTION 'LOGANALYSIS_FREQEXE_QUERIES: Invalid server id.';
	END IF;

	IF (tlimit IS NULL OR tlimit<=0 ) THEN
		RAISE EXCEPTION 'LOGANALYSIS_FREQEXE_QUERIES: Invalid table limit.';
	END IF;

	-- Queries executed most frequently

	query :=
		$$
		SELECT
			query,
			parameters,
			COUNT(query) AS no_of_times_executed,
			ROUND(SUM(duration), 2) AS total_duration
		FROM
		(
		SELECT
		(SUBSTRING(SUBSTRING(message FROM '^duration: [0-9\.]+ ms') FROM '[0-9\.]+')::NUMERIC) AS duration,
			TRIM(BOTH ' ' FROM
			SPLIT_PART(message,
			SUBSTRING(message FROM '^duration:\s+[0-9\.]+\s+ms\s*(?:prepare|parse|bind|execute from fetch|execute|statement)(?:\s+<(?:[^>]|>)+>)?:'), 2)) as query,
			detail AS parameters
		FROM
			pemdata.server_logs
		WHERE
		message LIKE 'duration:%' AND message ~ '^duration:\s+[0-9\.]+\s+ms\s*(?:prepare|parse|bind|execute from fetch|execute|statement)' AND
		server_id = $3::INT AND
			error_severity = 'LOG'
			AND pem.date_trunc_minutes(log_time) BETWEEN $1::TIMESTAMP AND $2::TIMESTAMP
		) AS freq_executed_queries
		GROUP BY query, parameters
		ORDER BY 3 DESC
		LIMIT $4::INT
		$$;

	OPEN loganalysis_freqexe_queries_ref FOR EXECUTE query USING sdate, edate, server_id, tlimit;
	RETURN loganalysis_freqexe_queries_ref;

END;
$BODY$
LANGUAGE PLPGSQL;


/*
-- This method collects the most time executed queries
-- among the given intervals of the given server.
--
-- RETURNS REFCURSOR to the calling portion.
--
-- Parameters:
--
-- sdate		: Checkpoint stats start time.
-- edate		: Checkpoint stats end time.
-- server_id	: Checkpoint stats for the server.
-- tlimit		: No.Of rows limit to the display table.
--
-- Implementation:
--
-- Fetch the log lines from the server_logs, which are like below
--
-- duration: 0.000 ms  execute <unnamed>: UPDATE pem.probe_schedule SET current_backend_pid = NULL, last_execution_time = now() WHERE probe_id = $1 AND parameter_value_list = $2 AND 	current_backend_pid = pg_backend_pid();
--
-- and sorting these queries based on the frequency and execution time.
*/

CREATE OR REPLACE FUNCTION pem.loganalysis_mosttime_exec_queries(sdate TIMESTAMP, edate TIMESTAMP, server_id INT, tlimit INT DEFAULT 20) RETURNS REFCURSOR
AS
$BODY$
DECLARE
loganalysis_mosttimeexe_queries_ref REFCURSOR:= 'loganalysis_mosttimeexe_queries';
query text := '';

BEGIN

	IF ((sdate IS NULL OR edate IS NULL) OR (sdate > edate)) THEN
		RAISE EXCEPTION 'LOGANALYSIS_MOSTTIMEEXE_QUERIES: Invalid time.';
	END IF;

	IF (server_id IS NULL OR server_id < 0) THEN
		RAISE EXCEPTION 'LOGANALYSIS_MOSTTIMEEXE_QUERIES: Invalid server id.';
	END IF;

	IF (tlimit IS NULL OR tlimit<=0 ) THEN
		RAISE EXCEPTION 'LOGANALYSIS_MOSTTIMEEXE_QUERIES: Invalid table limit.';
	END IF;


	query :=
		$$
		SELECT
			query,
			parameters,
			COUNT(query) AS no_of_times_executed,
			ROUND(SUM(duration), 2) AS total_duration
		FROM
		(
		SELECT
			(SUBSTRING(SUBSTRING(message FROM '^duration: [0-9\.]+ ms') FROM '[0-9\.]+')::NUMERIC) AS duration,
			TRIM(BOTH ' ' FROM
			SPLIT_PART(message,
			SUBSTRING(message FROM '^duration:\s+[0-9\.]+\s+ms\s*(?:prepare|parse|bind|execute from fetch|execute|statement)(?:\s+<(?:[^>]|>)+>)?:'), 2)) as query,
			detail AS parameters
		FROM
			pemdata.server_logs
		WHERE
			message LIKE 'duration:%' AND message ~ '^duration:\s+[0-9\.]+\s+ms\s*(?:prepare|parse|bind|execute from fetch|execute|statement)' AND
			server_id = $3::INT AND
			error_severity = 'LOG'
			AND pem.date_trunc_minutes(log_time) BETWEEN $1::TIMESTAMP AND $2::TIMESTAMP
		) AS freq_executed_queries
		GROUP BY query, parameters
		ORDER BY 4 DESC
		LIMIT $4::INT
		$$;
	OPEN loganalysis_mosttimeexe_queries_ref FOR EXECUTE query USING sdate, edate, server_id, tlimit;
	RETURN loganalysis_mosttimeexe_queries_ref;
END;
$BODY$
LANGUAGE PLPGSQL;

/*
-- This method collects the log event details(ERROR, FATAL, ..),
-- per an Hour.
--
-- RETURNS REFCURSOR to the calling portion.
--
-- Parameters:
--
-- sdate		: Checkpoint stats start time.
-- edate		: Checkpoint stats end time.
-- server_id	: Checkpoint stats for the server.
-- tlimit		: No.Of rows limit to the display table.
--
*/

CREATE OR REPLACE FUNCTION pem.loganalysis_logeventstats(sdate TIMESTAMP, edate TIMESTAMP, server_id INT, tlimit INT DEFAULT 20) RETURNS REFCURSOR
AS
$BODY$
DECLARE
loganalysis_logeventdetails_ref REFCURSOR:= 'loganalysis_eventsdetails';
query TEXT:='';

BEGIN

	IF ((sdate IS NULL OR edate IS NULL) OR (sdate > edate)) THEN
		RAISE EXCEPTION 'LOGANALYSIS_LOGEVENTDETAILS: Invalid time range.';
	END IF;

	IF (server_id IS NULL OR server_id < 0) THEN
		RAISE EXCEPTION 'LOGANALYSIS_LOGEVENTDETAILS: Invalid server id.';
	END IF;

	IF (tlimit IS NULL OR tlimit<=0) THEN
		RAISE EXCEPTION 'LOGANALYSIS_LOGEVENTDETAILS: Invalid table limit.';
	END IF;

	query :=
			$$
			SELECT
				error_severity,
				message,
				COUNT(message) as no_of_events
			FROM
				pemdata.server_logs
			WHERE
				error_severity in ('WARNING', 'ERROR', 'FATAL', 'PANIC', 'HINT', 'CONTEXT') AND
				server_id = $3::INT AND
				message IS NOT NULL AND TRIM(BOTH ' ' from message)!='' AND
				pem.date_trunc_minutes(log_time) BETWEEN $1::TIMESTAMP AND $2::TIMESTAMP
				GROUP BY error_severity, message
				ORDER BY 3
				LIMIT $4::INT
			$$;

	OPEN loganalysis_logeventdetails_ref FOR EXECUTE query USING sdate, edate, server_id, tlimit;
	RETURN loganalysis_logeventdetails_ref;

END;
$BODY$
LANGUAGE PLPGSQL;

/*
-- This method collects the log details(LOG, DEBUG, INFO ...)
-- per an Hour.
--
-- RETURNS REFCURSOR to the calling portion.
--
-- Parameters:
--
-- sdate		: Checkpoint stats start time.
-- edate		: Checkpoint stats end time.
-- server_id	: Checkpoint stats for the server.
-- tlimit		: No.Of rows limit to the display table.
--
*/

CREATE OR REPLACE FUNCTION pem.loganalysis_logstats(sdate TIMESTAMP, edate TIMESTAMP, server_id INT, tlimit INT DEFAULT 20) RETURNS REFCURSOR
AS
$BODY$
DECLARE
loganalysis_logs_ref REFCURSOR:='loganalysis_logs';
query TEXT:='';

BEGIN

	IF ((sdate IS NULL OR edate IS NULL) OR (sdate > edate)) THEN
		RAISE EXCEPTION 'LOGANALYSIS_LOGSTATS: Invalid time range.';
	END IF;

	IF (server_id IS NULL OR server_id < 0) THEN
		RAISE EXCEPTION 'LOGANALYSIS_LOGSTATS: Invalid server id.';
	END IF;

	IF (tlimit IS NULL OR tlimit<=0) THEN
		RAISE EXCEPTION 'LOGANALYSIS_LOGSTATS: Invalid table limit.';
	END IF;

	query :=
			$$
			SELECT
				error_severity,
				COUNT(error_severity) AS no_of_logs
			from
				pemdata.server_logs
			WHERE
				error_severity IN ('LOG', 'DETAIL', 'DEBUG', 'NOTICE', 'INFO', 'STATEMENT') AND
				server_id = $3::INT AND
				message IS NOT NULL AND TRIM(BOTH ' ' from message)!='' AND
				pem.date_trunc_minutes(log_time) BETWEEN $1::TIMESTAMP AND $2::TIMESTAMP
				GROUP BY error_severity
				ORDER BY 2
				LIMIT $4::INT
			$$;
	OPEN loganalysis_logs_ref FOR EXECUTE query USING sdate, edate, server_id, tlimit;
	RETURN loganalysis_logs_ref;

END;
$BODY$
LANGUAGE PLPGSQL;


/*
-- This method collects the queries info, those have generated temp files
-- per an Hour.
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
*/

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
			log_time,
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
-- This method collects the hourly stats of dml statements for each database.
--
-- RETURNS REFCURSOR to the calling portion.
--
-- Parameters:
--
-- sdate		: Checkpoint stats start time.
-- edate		: Checkpoint stats end time.
-- server_id	: Checkpoint stats for the server.
--
-- Note: We need to enable log_duration = on, log_statements= 'mod' or log_min_duration_statement=0 to get the precises metrices.
*/

CREATE OR REPLACE FUNCTION pem.loganalysis_hourlydmlstats(sdate TIMESTAMP, edate TIMESTAMP, server_id INT, tlimit INT DEFAULT 20) RETURNS REFCURSOR
AS
$BODY$
DECLARE
loganalysis_hourlydmlstats_ref REFCURSOR:= 'loganalysis_hourlydmlstats';
query TEXT:='';

BEGIN

	IF ((sdate IS NULL OR edate IS NULL) OR (sdate > edate)) THEN
		RAISE EXCEPTION 'LOGANALYSIS_hourlydmlstats: Invalid time range.';
	END IF;

	IF (server_id IS NULL OR server_id < 0) THEN
		RAISE EXCEPTION 'LOGANALYSIS_hourlydmlstats: Invalid server id.';
	END IF;

	query :=
			$$
			SELECT
				rtrim(rtrim(log_time::timestamp::text, '0'), ':') AS "Time",
				database_name as "Database Name",
				command_tag AS "Statement",
				COUNT(command_tag) AS "Count",
				ROUND(min(duration), 2) as "Min Duration",
				ROUND(max(duration), 2) as "Max Duration",
				ROUND(avg(duration), 2) as "Avg Duration"
			FROM
			(
				SELECT
					command_tag,
					ROUND(SUBSTRING(SUBSTRING(message FROM '^duration: [0-9\.]+ ms') FROM '[0-9\.]+')::NUMERIC/1000, 2) as duration,
					date_trunc('hour', log_time) as log_time,
					database_name
				FROM
					pemdata.server_logs
				WHERE
					error_severity = 'LOG' AND command_tag IN ('SELECT', 'INSERT', 'UPDATE', 'DELETE', 'FETCH', 'COPY') AND
					pem.date_trunc_minutes(log_time) >=$1::TIMESTAMP AND pem.date_trunc_minutes(log_time)<$2::TIMESTAMP AND
					server_id = $3::INT
			) AS dml_hourly_stats
			GROUP BY 1, command_tag, database_name
			ORDER BY 1, 2
			LIMIT $4::INT
			$$;
	OPEN loganalysis_hourlydmlstats_ref FOR EXECUTE query USING sdate, edate, server_id, tlimit;
	RETURN loganalysis_hourlydmlstats_ref;
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
				metric,
				ARRAY[EXTRACT(EPOCH FROM actual_time), (CASE
											WHEN $4::TEXT ~ '^SUM$|^MIN$|^MAX$' THEN
											metric_value
											WHEN $4::TEXT = 'AVG' AND (EXTRACT(EPOCH FROM $3::interval)/60)::INT != 0 THEN
											(metric_value/(EXTRACT(EPOCH FROM $3::interval)/60))::INT
										END)
					]AS data_series
			FROM
			(
				WITH timerage_with_actual_interval AS
				(
					SELECT
						generate_series($1::TIMESTAMP, $2::TIMESTAMP, $3::INTERVAL) AS actual_time
				)
				SELECT
					metric,
					actual_time,
					CASE
						WHEN $4::TEXT = 'MIN' THEN
						COALESCE((SELECT * FROM UNNEST(array_agg(metric_value)) WHERE unnest!=0 ORDER BY unnest ASC LIMIT 1), 0)
						WHEN $4::TEXT = 'MAX' THEN
						MAX(metric_value)
						ELSE
						SUM(metric_value)
					END AS metric_value
				FROM
				(
					WITH timerange_with_1min_interval as
					(
						SELECT
							generate_series($1::TIMESTAMP, $2::TIMESTAMP, '1 Minute'::INTERVAL) as start_time
					)
					, session_conn_details AS
					(
						SELECT
							message,
							start_time
						FROM
							pemdata.server_logs
						JOIN
							timerange_with_1min_interval ON pem.date_trunc_minutes(log_time) = start_time
						WHERE
							message IS NOT NULL AND trim(BOTH ' ' FROM message) != '' AND
							error_severity = 'LOG' AND message ~ '^disconnection:|^connection received:'
							AND
							server_id = $5::INT
					)
					(
						SELECT
							'Connections Authenticated' as metric,
							start_time,
							COUNT(message) AS metric_value
						FROM
							session_conn_details
						WHERE
							message ~ '^disconnection:\s+session time:\s+[0-9:\.]+\s+(?:user=(?:[^\s]+)\s+)?(?:database=(?:[^\s]+)\s+)?(?:host=(?:[^\s]+)\s+)?'
						GROUP BY start_time

						UNION ALL

						SELECT
							'Connection Attempts' AS metric,
							start_time,
							COUNT(message) AS metric_value
						FROM
							session_conn_details
						WHERE
							message ~ '^connection\s+received:\s+(?:host=(?:[^\s]+)\s+)?'
						GROUP BY start_time
					)

					UNION ALL

						SELECT
							metric,
							start_time,
							0 as metric_value
						FROM
							timerange_with_1min_interval,
							(
								SELECT UNNEST(ARRAY['Connections Authenticated', 'Connection Attempts']) metric
							) AS metrices
				) as session_connection_1min_details
				JOIN
					timerage_with_actual_interval ON start_time >=actual_time AND
					(CASE WHEN
						(actual_time+$3::INTERVAL) < $2::TIMESTAMP THEN
							start_time < (actual_time+$3::INTERVAL)
						ELSE
							start_time < ((actual_time+$3::INTERVAL)-((actual_time+$3::INTERVAL)-$2::TIMESTAMP))
					END)
				GROUP by metric, actual_time
				ORDER BY metric, actual_time
			) AS session_connection_details_with_actual_span
			$$;
	OPEN loganalysis_session_connection_stats_ref FOR EXECUTE query USING sdate, edate, span, aggr, server_id;
	RETURN loganalysis_session_connection_stats_ref;
END;
$BODY$
LANGUAGE PLPGSQL;

-- Fixing the number of wal files probe sql query

UPDATE pem.probe set probe_code = 'SELECT COALESCE(sum(1), 0) AS number_of_wal_files FROM pg_ls_dir(''pg_xlog'') AS d (file) WHERE file ~ ''^[0-9A-F]{8}[0-9A-F]{8}[0-9A-F]{8}$''' WHERE internal_name = 'number_of_wal_files';

-- Fixing #32703

ALTER TABLE pem.log_configuration ADD COLUMN log_temp_files BIGINT NOT NULL DEFAULT -1;
ALTER TABLE pem.log_configuration ADD COLUMN log_autovacuum_min_duration BIGINT NOT NULL DEFAULT -1;

COMMENT ON COLUMN pem.log_configuration.log_autovacuum_min_duration IS 'Log autovacuum details which took greater than this time';
COMMENT ON COLUMN pem.log_configuration.log_temp_files IS 'Log temp file details which size was greater than this';


ALTER TABLE pemdata.log_configuration ADD COLUMN log_temp_files BIGINT NOT NULL DEFAULT -1;
ALTER TABLE pemdata.log_configuration ADD COLUMN log_autovacuum_min_duration BIGINT NOT NULL DEFAULT -1;

ALTER TABLE pemhistory.log_configuration ADD COLUMN log_temp_files BIGINT NOT NULL DEFAULT -1;
ALTER TABLE pemhistory.log_configuration ADD COLUMN log_autovacuum_min_duration BIGINT NOT NULL DEFAULT -1;

INSERT INTO pem.probe_column
        (probe_id, internal_name, display_name, display_position, classification,
        sql_data_type, unit_of_value, calculate_pit, discard_history, pit_by_default, is_graphable)
(
	SELECT id, 'log_autovacuum_min_duration', 'Log Autovacuum Min Duration', 27, 'm', 'bigint', '', false, false, false, false
		FROM pem.probe WHERE internal_name='log_configuration'
	UNION ALL
	SELECT id, 'log_temp_files', 'Log Temp Files', 28, 'm', 'bigint', '', false, false, false, false
		FROM pem.probe WHERE internal_name='log_configuration'
);

CREATE OR REPLACE FUNCTION pemdata.copy_log_configuration_to_history()
  RETURNS trigger AS
$BODY$
			BEGIN
				IF (TG_OP = 'INSERT' OR TG_OP = 'UPDATE') THEN
					INSERT INTO pemhistory.log_configuration (recorded_time, server_id, log_destination, log_collector, log_silent_mode, log_directory, log_filename, log_syslog_facility, log_syslog_ident, log_rotation_size, log_rotation_time, log_rotation_truncate, log_client_min_messages, log_min_messages, log_min_error_statement, log_min_duration_statement, log_parse_tree, log_rewriter_output, log_exec_plan, log_indent_debug_output, log_checkpoints, log_connections, log_disconnections, log_duration, log_hostname, log_lock_waits, log_error_verbosity, log_statements, log_temp_files, log_autovacuum_min_duration, log_prefix_string) VALUES (NEW.recorded_time, NEW.server_id, NEW.log_destination, NEW.log_collector, NEW.log_silent_mode, NEW.log_directory, NEW.log_filename, NEW.log_syslog_facility, NEW.log_syslog_ident, NEW.log_rotation_size, NEW.log_rotation_time, NEW.log_rotation_truncate, NEW.log_client_min_messages, NEW.log_min_messages, NEW.log_min_error_statement, NEW.log_min_duration_statement, NEW.log_parse_tree, NEW.log_rewriter_output, NEW.log_exec_plan, NEW.log_indent_debug_output, NEW.log_checkpoints, NEW.log_connections, NEW.log_disconnections, NEW.log_duration, NEW.log_hostname, NEW.log_lock_waits, NEW.log_error_verbosity, NEW.log_statements, NEW.log_temp_files, NEW.log_autovacuum_min_duration, NEW.log_prefix_string);
					ELSIF EXISTS(SELECT 1 FROM pem.server WHERE id = OLD.server_id) THEN
					INSERT INTO pemhistory.log_configuration (server_id) VALUES (OLD.server_id);
				END IF;
				RETURN NEW;
			END;
			$BODY$
  LANGUAGE plpgsql VOLATILE
  COST 100;

GRANT EXECUTE ON FUNCTION pemdata.copy_log_configuration_to_history() TO public;
GRANT EXECUTE ON FUNCTION pemdata.copy_log_configuration_to_history() TO pem_admin;
GRANT EXECUTE ON FUNCTION pemdata.copy_log_configuration_to_history() TO pem_agent;

--
-- SQL/Proetect Template
--
UPDATE pem.alert_template SET sql = $sql$ SELECT
  CASE
    WHEN COUNT(r.result) <> 0 THEN MAX(r.result)
    ELSE -1
  END
FROM
  (SELECT
     CASE
	  WHEN(p.log_destination = pd.log_destination
		AND p.log_collector = pd.log_collector
		AND p.log_silent_mode = pd.log_silent_mode
		AND p.log_directory = pd.log_directory
		AND p.log_filename = pd.log_filename
		AND p.log_syslog_facility = pd.log_syslog_facility
		AND p.log_syslog_ident = pd.log_syslog_ident
		AND p.log_rotation_size = pd.log_rotation_size
		AND p.log_rotation_time = pd.log_rotation_time
		AND p.log_rotation_truncate = pd.log_rotation_truncate
		AND p.log_client_min_messages = pd.log_client_min_messages
		AND p.log_min_messages = pd.log_min_messages
		AND p.log_min_error_statement = pd.log_min_error_statement
		AND p.log_min_duration_statement = pd.log_min_duration_statement
		AND p.log_parse_tree = pd.log_parse_tree
		AND p.log_rewriter_output = pd.log_rewriter_output
		AND p.log_exec_plan = pd.log_exec_plan
		AND p.log_indent_debug_output = pd.log_indent_debug_output
		AND p.log_checkpoints = pd.log_checkpoints
		AND p.log_connections = pd.log_connections
		AND p.log_disconnections = pd.log_disconnections
		AND p.log_duration = pd.log_duration
		AND p.log_hostname = pd.log_hostname
		AND p.log_lock_waits = pd.log_lock_waits
		AND p.log_error_verbosity = pd.log_error_verbosity
		AND p.log_prefix_string = pd.log_prefix_string
		AND p.log_statements = pd.log_statements
		AND p.log_autovacuum_min_duration = pd.log_autovacuum_min_duration
		AND p.log_temp_files = pd.log_temp_files) OR (p.server_id IS NULL)
         THEN -1
       ELSE 1
     END AS result
   FROM
     pem.log_configuration p RIGHT JOIN
     pemdata.log_configuration pd ON (p.server_id = pd.server_id)
   WHERE p.server_id = ${server_id}) AS r $sql$ WHERE display_name = 'Log config mismatch';

--

-- Postgres Log Expert Grants/Revokes

REVOKE EXECUTE ON FUNCTION pem.loganalysis_tagsstats(timestamp without time zone, timestamp without time zone, interval, text, integer, text, text[], boolean) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION pem.loganalysis_overallstats(timestamp without time zone, timestamp without time zone, integer) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION pem.loganalysis_checkpointstats(timestamp without time zone, timestamp without time zone, interval, text, integer) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION pem.loganalysis_tempfilestats(timestamp without time zone, timestamp without time zone, interval, text, integer) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION pem.loganalysis_locksstats(timestamp without time zone, timestamp without time zone, interval, text, integer) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION pem.loganalysis_autovacuumstats(timestamp without time zone, timestamp without time zone, integer, tlimit integer) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION pem.loganalysis_autoanalyzestats(timestamp without time zone, timestamp without time zone, integer, tlimit integer) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION pem.loganalysis_slowqueries(timestamp without time zone, timestamp without time zone, integer, tlimit integer) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION pem.loganalysis_freqexe_queries(timestamp without time zone, timestamp without time zone, integer, tlimit integer) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION pem.loganalysis_mosttime_exec_queries(timestamp without time zone, timestamp without time zone, integer, tlimit integer) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION pem.loganalysis_logeventstats(timestamp without time zone, timestamp without time zone, integer, tlimit integer) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION pem.loganalysis_logstats(timestamp without time zone, timestamp without time zone, integer, tlimit integer) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION pem.loganalysis_tempusedqueries(timestamp without time zone, timestamp without time zone, integer, tlimit integer) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION pem.loganalysis_hourlydmlstats(timestamp without time zone, timestamp without time zone, integer, tlimit integer) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION pem.loganalysis_session_connection_stats(timestamp without time zone, timestamp without time zone, interval, text, integer) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION pem.validate_intervals(timestamp without time zone, timestamp without time zone, integer, interval, out timestamp without time zone, out timestamp without time zone) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION pem.loganalysis_tagsstats(timestamp without time zone, timestamp without time zone, interval, text, integer, text, text[], boolean) TO pem_user;
GRANT EXECUTE ON FUNCTION pem.loganalysis_overallstats(timestamp without time zone, timestamp without time zone, integer) TO pem_user;
GRANT EXECUTE ON FUNCTION pem.loganalysis_checkpointstats(timestamp without time zone, timestamp without time zone, interval, text, integer) TO pem_user;
GRANT EXECUTE ON FUNCTION pem.loganalysis_tempfilestats(timestamp without time zone, timestamp without time zone, interval, text, integer) TO pem_user;
GRANT EXECUTE ON FUNCTION pem.loganalysis_locksstats(timestamp without time zone, timestamp without time zone, interval, text, integer) TO pem_user;
GRANT EXECUTE ON FUNCTION pem.loganalysis_autovacuumstats(timestamp without time zone, timestamp without time zone, integer, tlimit integer) TO pem_user;
GRANT EXECUTE ON FUNCTION pem.loganalysis_autoanalyzestats(timestamp without time zone, timestamp without time zone, integer, tlimit integer) TO pem_user;
GRANT EXECUTE ON FUNCTION pem.loganalysis_slowqueries(timestamp without time zone, timestamp without time zone, integer, tlimit integer) TO pem_user;
GRANT EXECUTE ON FUNCTION pem.loganalysis_freqexe_queries(timestamp without time zone, timestamp without time zone, integer, tlimit integer) TO pem_user;
GRANT EXECUTE ON FUNCTION pem.loganalysis_mosttime_exec_queries(timestamp without time zone, timestamp without time zone, integer, tlimit integer) TO pem_user;
GRANT EXECUTE ON FUNCTION pem.loganalysis_logeventstats(timestamp without time zone, timestamp without time zone, integer, tlimit integer) TO pem_user;
GRANT EXECUTE ON FUNCTION pem.loganalysis_logstats(timestamp without time zone, timestamp without time zone, integer, tlimit integer) TO pem_user;
GRANT EXECUTE ON FUNCTION pem.loganalysis_tempusedqueries(timestamp without time zone, timestamp without time zone, integer, tlimit integer) TO pem_user;
GRANT EXECUTE ON FUNCTION pem.loganalysis_hourlydmlstats(timestamp without time zone, timestamp without time zone, integer, tlimit integer) TO pem_user;
GRANT EXECUTE ON FUNCTION pem.loganalysis_session_connection_stats(timestamp without time zone, timestamp without time zone, interval, text, integer) TO pem_user;
GRANT EXECUTE ON FUNCTION pem.validate_intervals(timestamp without time zone, timestamp without time zone, integer, interval, out timestamp without time zone, out timestamp without time zone) TO pem_user;

COMMIT TRANSACTION;
