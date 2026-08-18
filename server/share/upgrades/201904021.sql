/***************************************************************************
 *
 * Postgres Enterprise Manager
 *
 * Copyright (C) 2010 - 2025, EnterpriseDB Corporation. All rights reserved.
 *
 ***************************************************************************/

/*
-- To fix the issue where edb redwood mode returns (null || str) -> (str)
-- instead of null, hence the justify_interval() was throwing syntax error
--
-- JIRA: PEM-2007
*/

BEGIN TRANSACTION;

    CREATE OR REPLACE FUNCTION pem.schema_version()
      RETURNS integer AS
    'SELECT 201904021::integer;'
      LANGUAGE 'sql' IMMUTABLE;
    COMMENT ON FUNCTION pem.schema_version() IS
     'Returns the version number of the PEM schema';


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
                        -- edb redwood mode returns (null || str) -> (str) instead of null, so to prevent such cases we will be explicit
                        CASE WHEN SUM(SUBSTRING(SUBSTRING(message FROM '^duration:\s+[0-9\.]\s+ms\s*') FROM '[0-9\.]')::REAL/1000) IS NULL
                        THEN
                            NULL
                        ELSE
                            (COALESCE(SUM(SUBSTRING(SUBSTRING(message FROM '^duration:\s+[0-9\.]\s+ms\s*') FROM '[0-9\.]')::REAL/1000))::text||' Seconds')::interval
                        END
                    )::TEXT,
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

END TRANSACTION;
