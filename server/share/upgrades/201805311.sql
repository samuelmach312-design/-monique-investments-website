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
'SELECT 201805311::integer;'
  LANGUAGE 'sql' IMMUTABLE;
COMMENT ON FUNCTION pem.schema_version() IS 'Returns the version number of the PEM schema';

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
					(COALESCE(SUM(SUBSTRING(substring(message  FROM  '^duration:\s+[0-9\.]+\s+ms\s*') FROM '[0-9\.]+')::REAL/1000))::text||' Seconds')::interval)::TEXT,
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
								'session time:', 2)::INTERVAL))*1000
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
			RAISE EXCEPTION 'Invalid span. Can not generate aggregate data for range %-%',adjs_sdate, adjs_edate ;
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

UPDATE pem.chart_func
SET func = E'SELECT
            xmlelement(name table,
                xmlattributes(''pem-chart-table pem-element pem-chart-txt'' AS class, ''width:auto;'' AS style),
                xmlelement(name thead,
                    xmlelement(name tr,
                        xmlelement(name th,
                            xmlattributes(''pem-chart-th pem-element pem-table-th'' AS class),
                            ''Properties''),
                        xmlelement(name th,
                            xmlattributes(''pem-chart-th pem-element'' AS class),
                            ''Values''))),
                xmlelement(name tbody,
                    xmlelement(name tr,
                        xmlelement(name td,
                            xmlattributes(''pem-chart-td'' AS class),
                            ''Cluster Name''),
                        xmlelement(name td,
                            xmlattributes(''pem-chart-td'' AS class),
                            ps.efm_cluster_name)),
                    xmlelement(name tr,
                        xmlelement(name td,
                            xmlattributes(''pem-chart-td'' AS class),
                            ''Failover Manager Agent Running Status''),
                        xmlelement(name td,
                            xmlattributes(''pem-chart-td'' AS class),
                            CASE WHEN pe.efm_running = true THEN ''UP'' ELSE ''DOWN'' END)),
                    xmlelement(name tr,
                        xmlelement(name td,
                            xmlattributes(''pem-chart-td'' AS class),
                            ''Allowed Node List''),
                     xmlelement(name td,
                         xmlattributes(''pem-chart-td'' AS class),
                         array_to_string(pe.efm_allowed_node_list, '', ''))),
                    xmlelement(name tr,
                        xmlelement(name td,
                            xmlattributes(''pem-chart-td'' AS class),
                            ''Standby Priority List''),
                        xmlelement(name td,
                           xmlattributes(''pem-chart-td'' AS class),
                            array_to_string(pe.efm_standby_priority_list, '', ''))),
                    xmlelement(name tr,
                            xmlelement(name td,
                                xmlattributes(''pem-chart-td'' AS class),
                                ''Cluster Status Message''),
                            xmlelement(name td,
                                xmlattributes(''pem-chart-td'' AS class),
                                pe.efm_messages))))
FROM
    pemdata.efm_cluster_info pe
    LEFT JOIN pem.server ps ON (ps.id = pe.server_id)
WHERE pe.server_id = $1::int;'
WHERE id = 89;

-- Update column displayed in EFM Cluster Node Status graph.
UPDATE pem.chart
    SET labels = '{"Agent Type","Address","Agent","DB","XLog Location","Status Information","XLog Information", "VIP", "VIP Status"}'
WHERE
    id = 88;


-- Added group id column to fetch available agent details.
-- Issue: Removed unwanted type casting to text from group_id column
DROP VIEW IF EXISTS pem.avail_agents CASCADE;

CREATE OR REPLACE VIEW pem.avail_agents AS
    SELECT
        a.id AS id,
        a.agent_capability_list AS agent_capability_list,
        COALESCE(ao.description, a.description) AS description,
        a.active AS active,
        a.heartbeat_interval AS heartbeat_interval,
        a.alert_blackout AS alert_blackout,
        a.version AS version,
        a.platform AS platform,
        a.owner AS owner,
        a.team AS team,
        o.rolname AS agent_owner,
        COALESCE(ao.group_id, a.group_id, 0) AS group_id
    FROM (SELECT a.*, r.rolsuper AS rolsuper FROM pem.agent a, pg_catalog.pg_roles r WHERE r.rolname = current_user) AS a
        LEFT JOIN pem.agent_options ao ON (a.id = ao.agent_id AND pem_user = current_user)
        LEFT OUTER JOIN pg_catalog.pg_roles o ON (o.oid = a.owner)
        LEFT OUTER JOIN pg_catalog.pg_roles t ON (t.rolname = a.team)
WHERE
        -- Only active agents
        a.active AND
        -- Is a superuser
        (a.rolsuper OR
            -- No team provided
            a.team IS NULL OR a.team = '' OR
            -- Owner of the agent
            o.rolname = current_user OR
            -- Valid team provided and current_user is member of the it
            (t.oid IS NOT NULL AND pg_catalog.pg_has_role(a.team, 'member'))) OR
        -- Current user is having rights to view the server.
        EXISTS(SELECT 1 FROM pem.agent_server_binding asb JOIN pem.avail_servers asr ON (asr.id = asb.server_id) AND asb.agent_id = a.id);

COMMIT TRANSACTION;
