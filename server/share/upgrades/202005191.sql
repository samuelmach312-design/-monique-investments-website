/***************************************************************************
 *
 * Postgres Enterprise Manager
 *
 * Copyright (C) 2010 - 2025, EnterpriseDB Corporation. All rights reserved.
 *
 ***************************************************************************/

-- NOTE: This sql file is responsible for PEM 7.15 schema upgrade.

BEGIN TRANSACTION;

CREATE OR REPLACE FUNCTION pem.schema_version()
  RETURNS integer AS
'SELECT 202005191::integer;'
  LANGUAGE 'sql' IMMUTABLE;
COMMENT ON FUNCTION pem.schema_version() IS 'Returns the version number of the PEM schema';

-- JIRA: PEM-3169
-- We have fixed an issue when constructing conditional clause (line: 73) where when the value comes as null
-- then the  string formed is wrong causing syntax error
CREATE OR REPLACE FUNCTION pem.data_reconstruction(probe_table text,
	probe_data_column text, start_time timestamp with time zone,
	end_time timestamp with time zone, time_interval interval,
	probe_target_key_list varchar[], probe_target_value_list varchar[],
	agentid integer, is_capacity_manager boolean, restricted_dbs varchar[] DEFAULT NULL,
	OUT metric_time timestamp with time zone, OUT recorded_value numeric)
RETURNS SETOF RECORD
AS $$
DECLARE
	conditional_clause text := NULL;
	groupby_clause text;

	raw_query text;
	new_query text;

	heartbeat_freq interval := 0;
	last_heartbeat timestamp with time zone := NULL;
	tmp_end_time timestamp with time zone := NULL;
	adjusted_start_time timestamp with time zone := NULL;

	raw_data REFCURSOR;

	current_record record;
	next_record record;
	new_record record;
BEGIN
	-- Sanity checks.
	IF (time_interval <= '0'::interval) THEN
		RAISE EXCEPTION 'time_interval must be greater than zero';
	END IF;
	IF (start_time >= end_time) THEN
		RAISE EXCEPTION 'End time must be greater than start time';
	END IF;

	EXECUTE 'SELECT heartbeat_interval * ''1 second''::interval FROM pem.agent where id = $1::int4'
	INTO heartbeat_freq USING agentid;

	EXECUTE 'SELECT last_heartbeat FROM pem.agent_heartbeat WHERE agent_id = $1::int4'
	INTO last_heartbeat USING agentid;

	IF last_heartbeat IS NULL THEN
		tmp_end_time = end_time;
	ELSE
		EXECUTE '
SELECT
	CASE WHEN last_heartbeat + $1::interval < $2::timestamptz THEN last_heartbeat
	ELSE $2::timestamptz END
FROM pem.agent_heartbeat WHERE agent_id = $3::int4'
			INTO tmp_end_time USING heartbeat_freq, end_time, agentid;
	END IF;

	-- Work out conditional_clause based on probe target.
	SELECT string_agg(pg_catalog.quote_ident(probe_target_key_list[i]) || '::text ' ||
	-- Here quote_literal() ignores null value and does not return it as NULL string
	-- causing syntax error, we will handle NULL value sepratly using IS NULL syntax
	CASE
		WHEN probe_target_value_list[i] IS NULL THEN
			'IS NULL'
		ELSE
			'= ' || pg_catalog.quote_literal(probe_target_value_list[i]::text)
	END, ' AND ')
    FROM generate_series(array_lower(probe_target_key_list,1),
    array_upper(probe_target_key_list,1)) i INTO conditional_clause;

	-- Work out comma separated probe_target_key_list to create group by
	-- clause.
	SELECT string_agg(pg_catalog.quote_ident(probe_target_key_list[i]), ', ')
		FROM generate_series(array_lower(probe_target_key_list,1),
		array_upper(probe_target_key_list,1)) i INTO groupby_clause;

	-- Add restricted database clause
	IF count(restricted_dbs) > 0 THEN
		IF conditional_clause IS NOT NULL AND conditional_clause <> '' THEN
			conditional_clause := conditional_clause || ' AND ';
		ELSE
			conditional_clause := '';
		END IF;
		conditional_clause := conditional_clause || pg_catalog.quote_ident(probe_table) || '.database_name = ANY( ' || pg_catalog.quote_literal(restricted_dbs::text) || ')';
	END IF;

	-- Get the time when probe started collecting the data
	raw_query := 'SELECT COALESCE(MAX(recorded_time), NULL::timestamptz) AS recorded_time FROM pemhistory.'
		|| pg_catalog.quote_ident(probe_table)
		|| ' WHERE recorded_time <= $1::timestamptz';
	IF conditional_clause IS NOT NULL AND conditional_clause <> '' THEN
		raw_query := raw_query || ' AND ' || conditional_clause;
	END IF;
	EXECUTE raw_query INTO adjusted_start_time USING start_time;

	-- Fetch the data.
	raw_query := '';
	IF is_capacity_manager THEN
		raw_query = 'SELECT recorded_time, ';
		IF adjusted_start_time IS NULL THEN
			raw_query := raw_query || 'COALESCE( '
				|| pg_catalog.quote_ident(probe_data_column)
				|| '::numeric, 0::numeric) AS metric_value FROM pemhistory.'
				|| pg_catalog.quote_ident(probe_table)
				|| ' WHERE recorded_time >= '
				|| pg_catalog.quote_literal(start_time::text)
				|| '::timestamptz';
		ELSE
			raw_query := raw_query || pg_catalog.quote_ident(probe_data_column)
				|| '::numeric AS metric_value FROM pemhistory.'
				|| pg_catalog.quote_ident(probe_table)
				|| ' WHERE recorded_time >= '
				|| pg_catalog.quote_literal(adjusted_start_time::text)
				|| '::timestamptz';
		END IF;
		raw_query := raw_query || ' AND recorded_time <= '
			|| pg_catalog.quote_literal(tmp_end_time::text) || '::timestamptz';
		IF conditional_clause IS NOT NULL AND trim(conditional_clause) <> '' THEN
			raw_query := raw_query || ' AND ' || conditional_clause;
		END IF;
		raw_query := raw_query
			|| ' ORDER BY recorded_time';
	ELSE -- Queries for landing pages
		-- SUM(probe_data_column) has been used to aggregate the values. For
		-- example on server page if nummbackends are to be
		-- found then SUM() will be taken after applying group by on
		-- server_id for all databases.
		-- truncate has been used in group by clause because
		-- sometimes data collection has time difference in miliseconds
		raw_query := 'SELECT MAX(recorded_time) AS recorded_time, SUM(';
		IF adjusted_start_time IS NULL THEN
			raw_query := raw_query || 'COALESCE( '
				|| pg_catalog.quote_ident(probe_data_column)
				|| '::numeric, 0::numeric)) AS metric_value FROM pemhistory.'
				|| pg_catalog.quote_ident(probe_table)
				|| ' WHERE recorded_time >= '
				|| pg_catalog.quote_literal(start_time::text) || '::timestamptz';
		ELSE
			raw_query := raw_query || pg_catalog.quote_ident(probe_data_column)
				|| ')::numeric AS metric_value FROM pemhistory.'
				|| pg_catalog.quote_ident(probe_table)
				|| ' WHERE recorded_time >= '
				|| pg_catalog.quote_literal(adjusted_start_time::text) || '::timestamptz';
		END IF;

		raw_query := raw_query || ' AND recorded_time <= ' || pg_catalog.quote_literal(tmp_end_time::text) || '::timestamptz';
		IF conditional_clause IS NOT NULL AND trim(conditional_clause) <> '' THEN
			raw_query := raw_query || ' AND ' || conditional_clause;
		END IF;
		IF groupby_clause IS NOT NULL AND trim(groupby_clause) <> '' THEN
			raw_query := raw_query || ' GROUP BY date_trunc(''second'', recorded_time), ' || groupby_clause || ' ORDER BY recorded_time';
		END IF;
	END IF;

	OPEN raw_data FOR EXECUTE raw_query;

	FETCH raw_data INTO current_record;
	IF NOT FOUND THEN
		RETURN;
	END IF;
	FETCH raw_data INTO next_record;

	new_query
		= 'SELECT ts AS recorded_time FROM generate_series($1::timestamptz, $2::timestamptz, $3::interval) ts';

	FOR new_record IN EXECUTE new_query USING start_time, tmp_end_time, time_interval
	LOOP
		IF (current_record.recorded_time IS NOT NULL
			AND current_record.recorded_time <= new_record.recorded_time) THEN
			IF (next_record IS NULL OR
				new_record.recorded_time < next_record.recorded_time) THEN
				recorded_value := current_record.metric_value;
			ELSE
				-- Find the next value for the time, which is closest to the
				-- next expected time
				WHILE next_record IS NOT NULL AND
					new_record.recorded_time > next_record.recorded_time
				LOOP
					current_record := next_record;
					FETCH raw_data INTO next_record;
				END LOOP;
			END IF;
		END IF;
		IF current_record.recorded_time <= new_record.recorded_time THEN
			metric_time := new_record.recorded_time;
			recorded_value := current_record.metric_value;

			RETURN NEXT;
		END IF;
	END LOOP;

	CLOSE raw_data;

	-- If agent is down (we assumes that the current data hasn't been modified
	-- yet during this period
	IF tmp_end_time < end_time THEN
		new_query
			= 'SELECT ts AS recorded_time FROM generate_series($1::timestamptz, $2::timestamptz, $3::interval) ts';

		--OPEN new_data FOR new_query;
		WHILE tmp_end_time + time_interval <= end_time
		LOOP
			tmp_end_time := tmp_end_time + time_interval;
			metric_time = tmp_end_time;

			RETURN NEXT;
		END LOOP;
	END IF;
END;
$$ LANGUAGE plpgsql;

---
--- Changes suggested by Vik to improve the performance of the purging data.
--- Customer Bug Story # 982331
---
DO $DO$
BEGIN
	-- For purging pem.probe_log table
	IF NOT EXISTS(
		SELECT 1 FROM pg_catalog.pg_index
		WHERE indrelid = 'pem.probe_log'::regclass AND
			indexrelid::regclass::text = 'pem.probe_log_recorded_time_idx'
		) THEN
		EXECUTE $SQL$
		CREATE INDEX probe_log_recorded_time_idx
			ON pem.probe_log (recorded_time)
		$SQL$;
	END IF;

	-- For purging pem.joblog table
	IF NOT EXISTS(
		SELECT 1 FROM pg_catalog.pg_index
		WHERE indrelid = 'pem.job'::regclass AND
			indexrelid::regclass::text = 'pem.job_joblastrun_idx'
		) THEN
		EXECUTE $SQL$
		CREATE INDEX job_joblastrun_idx ON pem.job (joblastrun)
		$SQL$;
	END IF;

	-- For purging pem.joblog table
	IF NOT EXISTS(
		SELECT 1 FROM pg_catalog.pg_index
		WHERE indrelid = 'pem.joblog'::regclass AND
			indexrelid::regclass::text = 'pem.joblog_jlgstart_idx'
		) THEN
		EXECUTE $SQL$
		CREATE INDEX joblog_jlgstart_idx ON pem.joblog (jlgstart)
		$SQL$;
	END IF;

	-- For purging pem.snmp_spool table
	IF NOT EXISTS(
		SELECT 1 FROM pg_catalog.pg_index
		WHERE indrelid = 'pem.snmp_spool'::regclass AND
			indexrelid::regclass::text = 'pem.snmp_spool_recorded_time_idx'
		) THEN
		EXECUTE $SQL$
		CREATE INDEX snmp_spool_recorded_time_idx
			ON pem.snmp_spool (recorded_time)
		$SQL$;
	END IF;

	-- For purging pem.nagios_spool table
	IF NOT EXISTS(
		SELECT 1 FROM pg_catalog.pg_index
		WHERE indrelid = 'pem.nagios_spool'::regclass AND
			indexrelid::regclass::text = 'pem.nagios_spool_recorded_time_idx'
		) THEN
		EXECUTE $SQL$
		CREATE INDEX nagios_spool_recorded_time_idx
			ON pem.nagios_spool (recorded_time)
		$SQL$;
	END IF;

	-- For purging pem.chart table (for deleted charts)
	IF NOT EXISTS(
		SELECT 1 FROM pg_catalog.pg_index
		WHERE indrelid = 'pem.chart'::regclass AND
			indexrelid::regclass::text = 'pem.chart_deleted_time_idx'
		) THEN
		EXECUTE $SQL$
		CREATE INDEX chart_deleted_time_idx ON pem.chart (deleted_time);
		$SQL$;
	END IF;
END;
$DO$ LANGUAGE 'plpgsql';

CREATE OR REPLACE FUNCTION pem.purge_smtp_spool()
RETURNS void AS $$
DECLARE
	cutoff_ts timestamp with time zone;
BEGIN
	cutoff_ts := (SELECT now() - CAST(value || ' ' || unit AS interval)
		FROM pem.config WHERE param = 'smtp_spool_retention_time');

	DELETE FROM pem.smtp_spool AS s
	WHERE s.sent_status = 's' AND s.recorded_time < cutoff_ts;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE OR REPLACE FUNCTION pem.purge_snmp_spool()
RETURNS void AS $$
DECLARE
	cutoff_ts timestamp with time zone;
BEGIN
	cutoff_ts := (SELECT now() - CAST(value || ' ' || unit AS interval)
		FROM pem.config WHERE param = 'smnp_spool_retention_time');

	DELETE FROM pem.snmp_spool AS s
	WHERE s.sent_status = 's' AND s.recorded_time < cutoff_ts;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE OR REPLACE FUNCTION pem.purge_audit_log()
RETURNS void AS $$
DECLARE
	cutoff_ts timestamp with time zone;
BEGIN
	cutoff_ts := (SELECT now() - CAST(value || ' ' || unit AS interval)
		FROM pem.config WHERE param = 'audit_log_retention_time');

	-- Purge data from audit log table
	DELETE FROM pemdata.audit_logs AS al
	WHERE al.log_time < cutoff_ts;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE OR REPLACE FUNCTION pem.purge_server_log()
RETURNS void AS $$
DECLARE
	cutoff_ts timestamp with time zone;
BEGIN
	cutoff_ts := (SELECT now() - CAST(value || ' ' || unit AS interval)
		FROM pem.config WHERE param = 'server_log_retention_time');

	-- Purge data from server log table
	DELETE FROM pemdata.server_logs AS sl
	WHERE sl.log_time < cutoff_ts;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE OR REPLACE FUNCTION pem.purge_probe_log()
RETURNS void AS $$
DECLARE
	cutoff_ts timestamp with time zone;
BEGIN
	cutoff_ts := (SELECT now() - CAST(value || ' ' || unit AS interval)
		FROM pem.config WHERE param = 'probe_log_retention_time');

	-- Purge data from probe log table
	DELETE FROM pem.probe_log AS pl
	WHERE pl.recorded_time < cutoff_ts;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE OR REPLACE FUNCTION pem.purge_alert_history()
RETURNS void AS $$
	-- Purge data from alert history table
	DELETE FROM pem.alert_history AS h
	USING pem.alert AS a
	WHERE a.id = h.alert_id AND
		h.generated < now() - a.history_retention * interval '1 day';
$$ LANGUAGE sql SECURITY DEFINER;

CREATE OR REPLACE FUNCTION pem.purge_job_log()
RETURNS void AS $$
DECLARE
	cutoff_ts timestamp with time zone;
BEGIN
	cutoff_ts := (SELECT now() - CAST(value || ' ' || unit AS interval)
		FROM pem.config WHERE param = 'job_retention_time');

	-- Purge old jobs, steps and schedules
	DELETE FROM pem.job AS j
	WHERE j.jobnextrun IS NULL AND j.joblastrun < cutoff_ts;

	-- Purge job log and job step log
	DELETE FROM pem.joblog AS jl
	WHERE jl.jlgstart < cutoff_ts;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE OR REPLACE FUNCTION pem.purge_nagios_spool()
RETURNS void AS $$
DECLARE
	cutoff_ts timestamp with time zone;
BEGIN
	cutoff_ts := (SELECT now() - CAST(value || ' ' || unit AS interval)
		FROM pem.config WHERE param = 'nagios_spool_retention_time');

	DELETE FROM pem.nagios_spool AS s
	WHERE sent_status = 's' AND s.recorded_time < cutoff_ts;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE OR REPLACE FUNCTION pem.purge_deleted_charts()
RETURNS void AS $$
DECLARE
	cutoff_ts timestamp with time zone;
BEGIN
	cutoff_ts := (SELECT now() - CAST(value || ' ' || unit AS interval)
		FROM pem.config WHERE param = 'deleted_charts_retention_time');

	-- Purge data from the pem.chart table
	DELETE FROM pem.chart AS c
	WHERE c.deleted AND c.ref_cnt = 0;

	DELETE FROM pem.chart AS c
	WHERE c.deleted AND c.deleted_time < cutoff_ts;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

DO $DO$
BEGIN
	IF pem.backend_minimum(9,5) THEN
		EXECUTE $SQL$
CREATE OR REPLACE FUNCTION pem.clear_probe_zombies(agent_id integer = NULL)
RETURNS void AS $FUNC$
BEGIN
	-- New agents will clear from its own zombie probes
	IF agent_id IS NOT NULL THEN
		UPDATE pem.probe_schedule s
		SET current_backend_pid = NULL, agent_id = NULL WHERE s.agent_id = $1;
	ELSE
		WITH pids (pid) AS (
			SELECT ps.current_backend_pid FROM pem.probe_schedule AS ps
			WHERE NOT EXISTS (
				SELECT 1 FROM pg_catalog.pg_stat_activity AS a
				WHERE a.pid = ps.current_backend_pid
			)
			ORDER BY ps.current_backend_pid
			FOR UPDATE SKIP LOCKED
		)
		UPDATE pem.probe_schedule AS ps SET current_backend_pid = NULL
		WHERE ps.current_backend_pid IN (SELECT pid FROM pids);
	END IF;
END;
$FUNC$ LANGUAGE 'plpgsql'$SQL$;
		EXECUTE $SQL$
CREATE OR REPLACE FUNCTION pem.clear_job_zombies(integer) RETURNS void AS $FUNC$
DECLARE
	agent_runtime_id integer := NULL;
BEGIN
	SELECT runtime_id INTO agent_runtime_id FROM pem.agent_runtime ar
	WHERE ar.agent_id = $1;

	WITH running_agent_job AS (
		SELECT j.jobid, j.agent_id
		FROM pem.job j LEFT JOIN pem.joblog jl ON (j.jobid = jl.jlgjobid)
		WHERE jl.jlgstatus = 'r' AND agent_id = $1 AND j.jobarid != agent_runtime_id
		ORDER BY j.jobid, jl.jlgjobid
		FOR UPDATE SKIP LOCKED
	), joblog_status_update AS (
		UPDATE pem.joblog jl SET jlgstatus='d'
		FROM running_agent_job r
		WHERE r.jobid = jl.jlgjobid AND jl.jlgstatus='r'
		RETURNING r.agent_id, jl.jlgjobid, jl.jlgid
	), jobsteplog_status_update AS (
		UPDATE pem.jobsteplog js SET jslstatus='d'
		FROM joblog_status_update jl
		WHERE js.jsljlgid = jl.jlgid AND js.jslstatus='r'
		RETURNING jl.agent_id, jl.jlgjobid AS job_id
	)
	UPDATE pem.job j SET jobprocessid=NULL, jobnextrun=NULL, jobarid=NULL
	FROM (SELECT DISTINCT agent_id, job_id FROM jobsteplog_status_update) js
	WHERE js.job_id = j.jobid;
END;
$FUNC$ LANGUAGE plpgsql$SQL$;
	ELSE
		EXECUTE $SQL$
CREATE OR REPLACE FUNCTION pem.clear_probe_zombies(agent_id integer = NULL)
RETURNS void AS $FUNC$
BEGIN
	-- New agents will clear from its own zombie probes
	IF agent_id IS NOT NULL THEN
		UPDATE pem.probe_schedule s
		SET current_backend_pid = NULL, agent_id = NULL WHERE s.agent_id = $1;
	ELSE
		WITH pids (pid) AS (
			SELECT ps.current_backend_pid FROM pem.probe_schedule AS ps
			WHERE NOT EXISTS (
				SELECT 1 FROM pg_catalog.pg_stat_activity AS a
				WHERE a.pid = ps.current_backend_pid
			)
			ORDER BY ps.current_backend_pid
			FOR UPDATE
		)
		UPDATE pem.probe_schedule AS ps SET current_backend_pid = NULL
		WHERE ps.current_backend_pid IN (SELECT pid FROM pids);
	END IF;
END;
$FUNC$ LANGUAGE 'plpgsql'$SQL$;
	END IF;
END
$DO$ LANGUAGE 'plpgsql';

CREATE OR REPLACE FUNCTION pem.check_alert_params_array_size(
	template_id pem.alert_template.id%type,
	params text[]
) RETURNS bool AS $FUNC$
DECLARE
	res bool := TRUE;
BEGIN
	/*
	 * During restoring the pem database, it does not maintain the order while
	 * inserting data in the table, and uses the sort table based on the
	 * names.
	 *
	 * Hence - we need to check the foreign key constraint is present before
	 * validating these values.
	 *
	 */
	IF EXISTS(
		SELECT 1 FROM information_schema.table_constraints
		WHERE constraint_name='alert_template_id_fkey' AND
			table_name='alert' AND table_schema='pem'
	) THEN
		/*
		 * Need to use the IS TRUE construct outside the main query, because
		 * otherwise if there's no template by that ID then the query would return
		 * 0 rows and the result of the function would be undefined and CHECK
		 * constraint would succeed.
		 *
		 * Probably this is being over-cautious, because pem.alert.template_id
		 * references pem.alert_template.id. But the SQL standard (probably) does
		 * not define the order in which the CHECK or the FOREIGN KEY constraints
		 * should be validated; in case CHECK is validated first, we want it to
		 * fail.
		 */
		EXECUTE $SQL$
		SELECT (
			SELECT pem.check_array_size_equal(t.param_names, $2)
			FROM pem.alert_template AS t
			WHERE id = $1
		) IS TRUE
		$SQL$ INTO res USING template_id, params;
	END IF;
	RETURN res;
END
$FUNC$ LANGUAGE 'plpgsql';

-- As type casting timestamp with date type will not give date output in EPAS due to redwood mode but it gives date output in postgres.
-- Extract the date while comparing with pem.exception date type so it will work on both EPAS and postgsre.
CREATE OR REPLACE FUNCTION pem.next_schedule(int4, timestamptz, timestamptz, _bool, _bool, _bool, _bool, _bool) RETURNS timestamptz AS '
DECLARE
    jscid           ALIAS FOR $1;
    jscstart        ALIAS FOR $2;
    jscend          ALIAS FOR $3;
    jscminutes      ALIAS FOR $4;
    jschours        ALIAS FOR $5;
    jscweekdays     ALIAS FOR $6;
    jscmonthdays    ALIAS FOR $7;
    jscmonths       ALIAS FOR $8;

    nextrun         timestamptz := ''1970-01-01 00:00:00-00'';
    runafter        timestamp := ''1970-01-01 00:00:00-00'';

    bingo            bool := FALSE;
    gotit            bool := FALSE;
    foundval        bool := FALSE;
    daytweak        bool := FALSE;
    minutetweak        bool := FALSE;

    i                int2 := 0;
    d                int2 := 0;

    nextminute        int2 := 0;
    nexthour        int2 := 0;
    nextday            int2 := 0;
    nextmonth       int2 := 0;
    nextyear        int2 := 0;

BEGIN
    -- No valid start date has been specified
    IF jscstart IS NULL THEN RETURN NULL; END IF;

    -- The schedule is past its end date
    IF jscend IS NOT NULL AND jscend < now() THEN RETURN NULL; END IF;

    -- Get the time to find the next run after. It will just be the later of
    -- now() + 1m and the start date for the time being, however, we might want to
    -- do more complex things using this value in the future.
    IF date_trunc(''MINUTE'', jscstart) > date_trunc(''MINUTE'', (now() + ''1 Minute''::interval)) THEN
        runafter := date_trunc(''MINUTE'', jscstart);
    ELSE
        runafter := date_trunc(''MINUTE'', (now() + ''1 Minute''::interval));
    END IF;

    --
    -- Enter a loop, generating next run timestamps until we find one
    -- that falls on the required weekday, and is not matched by an exception
    --
    WHILE bingo = FALSE LOOP

        --
        -- Get the next run year
        --
        nextyear := date_part(''YEAR'', runafter);

        --
        -- Get the next run month
        --
        nextmonth := date_part(''MONTH'', runafter);
        gotit := FALSE;
        FOR i IN (nextmonth) .. 12 LOOP
            IF jscmonths[i] = TRUE THEN
                nextmonth := i;
                gotit := TRUE;
                foundval := TRUE;
                EXIT;
            END IF;
        END LOOP;
        IF gotit = FALSE THEN
            FOR i IN 1 .. (nextmonth - 1) LOOP
                IF jscmonths[i] = TRUE THEN
                    nextmonth := i;

                    -- Wrap into next year
                    nextyear := nextyear + 1;
                    gotit := TRUE;
                    foundval := TRUE;
                    EXIT;
                END IF;
           END LOOP;
        END IF;

        --
        -- Get the next run day
        --
        -- If the year, or month have incremented, get the lowest day,
        -- otherwise look for the next day matching or after today.
        IF (nextyear > date_part(''YEAR'', runafter) OR nextmonth > date_part(''MONTH'', runafter)) THEN
            nextday := 1;
            FOR i IN 1 .. 32 LOOP
                IF jscmonthdays[i] = TRUE THEN
                    nextday := i;
                    foundval := TRUE;
                    EXIT;
                END IF;
            END LOOP;
        ELSE
            nextday := date_part(''DAY'', runafter);
            gotit := FALSE;
            FOR i IN nextday .. 32 LOOP
                IF jscmonthdays[i] = TRUE THEN
                    nextday := i;
                    gotit := TRUE;
                    foundval := TRUE;
                    EXIT;
                END IF;
            END LOOP;
            IF gotit = FALSE THEN
                FOR i IN 1 .. (nextday - 1) LOOP
                    IF jscmonthdays[i] = TRUE THEN
                        nextday := i;

                        -- Wrap into next month
                        IF nextmonth = 12 THEN
                            nextyear := nextyear + 1;
                            nextmonth := 1;
                        ELSE
                            nextmonth := nextmonth + 1;
                        END IF;
                        gotit := TRUE;
                        foundval := TRUE;
                        EXIT;
                    END IF;
                END LOOP;
            END IF;
        END IF;

        -- Was the last day flag selected?
        IF nextday = 32 THEN
            IF nextmonth = 1 THEN
                nextday := 31;
            ELSIF nextmonth = 2 THEN
                IF pem.is_leap_year(nextyear) = TRUE THEN
                    nextday := 29;
                ELSE
                    nextday := 28;
                END IF;
            ELSIF nextmonth = 3 THEN
                nextday := 31;
            ELSIF nextmonth = 4 THEN
                nextday := 30;
            ELSIF nextmonth = 5 THEN
                nextday := 31;
            ELSIF nextmonth = 6 THEN
                nextday := 30;
            ELSIF nextmonth = 7 THEN
                nextday := 31;
            ELSIF nextmonth = 8 THEN
                nextday := 31;
            ELSIF nextmonth = 9 THEN
                nextday := 30;
            ELSIF nextmonth = 10 THEN
                nextday := 31;
            ELSIF nextmonth = 11 THEN
                nextday := 30;
            ELSIF nextmonth = 12 THEN
                nextday := 31;
            END IF;
        END IF;

        --
        -- Get the next run hour
        --
        -- If the year, month or day have incremented, get the lowest hour,
        -- otherwise look for the next hour matching or after the current one.
        IF (nextyear > date_part(''YEAR'', runafter) OR nextmonth > date_part(''MONTH'', runafter) OR nextday > date_part(''DAY'', runafter) OR daytweak = TRUE) THEN
            nexthour := 0;
            FOR i IN 1 .. 24 LOOP
                IF jschours[i] = TRUE THEN
                    nexthour := i - 1;
                    foundval := TRUE;
                    EXIT;
                END IF;
            END LOOP;
        ELSE
            nexthour := date_part(''HOUR'', runafter);
            gotit := FALSE;
            FOR i IN (nexthour + 1) .. 24 LOOP
                IF jschours[i] = TRUE THEN
                    nexthour := i - 1;
                    gotit := TRUE;
                    foundval := TRUE;
                    EXIT;
                END IF;
            END LOOP;
            IF gotit = FALSE THEN
                FOR i IN 1 .. nexthour LOOP
                    IF jschours[i] = TRUE THEN
                        nexthour := i - 1;

                        -- Wrap into next month
                        IF (nextmonth = 1 OR nextmonth = 3 OR nextmonth = 5 OR nextmonth = 7 OR nextmonth = 8 OR nextmonth = 10 OR nextmonth = 12) THEN
                            d = 31;
                        ELSIF (nextmonth = 4 OR nextmonth = 6 OR nextmonth = 9 OR nextmonth = 11) THEN
                            d = 30;
                        ELSE
                            IF pem.is_leap_year(nextyear) = TRUE THEN
                                d := 29;
                            ELSE
                                d := 28;
                            END IF;
                        END IF;

                        IF nextday = d THEN
                            nextday := 1;
                            IF nextmonth = 12 THEN
                                nextyear := nextyear + 1;
                                nextmonth := 1;
                            ELSE
                                nextmonth := nextmonth + 1;
                            END IF;
                        ELSE
                            nextday := nextday + 1;
                        END IF;

                        gotit := TRUE;
                        foundval := TRUE;
                        EXIT;
                    END IF;
                END LOOP;
            END IF;
        END IF;

        --
        -- Get the next run minute
        --
        -- If the year, month day or hour have incremented, get the lowest minute,
        -- otherwise look for the next minute matching or after the current one.
        IF (nextyear > date_part(''YEAR'', runafter) OR nextmonth > date_part(''MONTH'', runafter) OR nextday > date_part(''DAY'', runafter) OR nexthour > date_part(''HOUR'', runafter) OR daytweak = TRUE) THEN
            nextminute := 0;
            IF minutetweak = TRUE THEN
        d := 1;
            ELSE
        d := date_part(''MINUTE'', runafter)::int2;
            END IF;
            FOR i IN d .. 60 LOOP
                IF jscminutes[i] = TRUE THEN
                    nextminute := i - 1;
                    foundval := TRUE;
                    EXIT;
                END IF;
            END LOOP;
        ELSE
            nextminute := date_part(''MINUTE'', runafter);
            gotit := FALSE;
            FOR i IN (nextminute + 1) .. 60 LOOP
                IF jscminutes[i] = TRUE THEN
                    nextminute := i - 1;
                    gotit := TRUE;
                    foundval := TRUE;
                    EXIT;
                END IF;
            END LOOP;
            IF gotit = FALSE THEN
                FOR i IN 1 .. nextminute LOOP
                    IF jscminutes[i] = TRUE THEN
                        nextminute := i - 1;

                        -- Wrap into next hour
                        IF (nextmonth = 1 OR nextmonth = 3 OR nextmonth = 5 OR nextmonth = 7 OR nextmonth = 8 OR nextmonth = 10 OR nextmonth = 12) THEN
                            d = 31;
                        ELSIF (nextmonth = 4 OR nextmonth = 6 OR nextmonth = 9 OR nextmonth = 11) THEN
                            d = 30;
                        ELSE
                            IF pem.is_leap_year(nextyear) = TRUE THEN
                                d := 29;
                            ELSE
                                d := 28;
                            END IF;
                        END IF;

                        IF nexthour = 23 THEN
                            nexthour = 0;
                            IF nextday = d THEN
                                nextday := 1;
                                IF nextmonth = 12 THEN
                                    nextyear := nextyear + 1;
                                    nextmonth := 1;
                                ELSE
                                    nextmonth := nextmonth + 1;
                                END IF;
                            ELSE
                                nextday := nextday + 1;
                            END IF;
                        ELSE
                            nexthour := nexthour + 1;
                        END IF;

                        gotit := TRUE;
                        foundval := TRUE;
                        EXIT;
                    END IF;
                END LOOP;
            END IF;
        END IF;

        -- Build the result, and check it is not the same as runafter - this may
        -- happen if all array entries are set to false. In this case, add a minute.

        nextrun := (nextyear::varchar || ''-''::varchar || nextmonth::varchar || ''-'' || nextday::varchar || '' '' || nexthour::varchar || '':'' || nextminute::varchar)::timestamptz;

        IF nextrun = runafter AND foundval = FALSE THEN
                nextrun := nextrun + INTERVAL ''1 Minute'';
        END IF;

        -- If the result is past the end date, exit.
        IF nextrun > jscend THEN
            RETURN NULL;
        END IF;

        -- Check to ensure that the nextrun time is actually still valid. Its
        -- possible that wrapped values may have carried the nextrun onto an
        -- invalid time or date.
        IF ((jscminutes = ''{f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f}'' OR jscminutes[date_part(''MINUTE'', nextrun) + 1] = TRUE) AND
            (jschours = ''{f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f}'' OR jschours[date_part(''HOUR'', nextrun) + 1] = TRUE) AND
            (jscmonthdays = ''{f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f}'' OR jscmonthdays[date_part(''DAY'', nextrun)] = TRUE OR
            (jscmonthdays = ''{f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,t}'' AND
             ((date_part(''MONTH'', nextrun) IN (1,3,5,7,8,10,12) AND date_part(''DAY'', nextrun) = 31) OR
              (date_part(''MONTH'', nextrun) IN (4,6,9,11) AND date_part(''DAY'', nextrun) = 30) OR
              (date_part(''MONTH'', nextrun) = 2 AND ((pem.is_leap_year(date_part(''YEAR'', nextrun)::int2) AND date_part(''DAY'', nextrun) = 29) OR date_part(''DAY'', nextrun) = 28))))) AND
            (jscmonths = ''{f,f,f,f,f,f,f,f,f,f,f,f}'' OR jscmonths[date_part(''MONTH'', nextrun)] = TRUE)) THEN

            -- Now, check to see if the nextrun time found is a) on an acceptable
            -- weekday, and b) not matched by an exception. If not, set
            -- runafter = nextrun and try again.

            -- Check for a wildcard weekday
            gotit := FALSE;
            FOR i IN 1 .. 7 LOOP
                IF jscweekdays[i] = TRUE THEN
                    gotit := TRUE;
                    EXIT;
                END IF;
            END LOOP;

            -- OK, is the correct weekday selected, or a wildcard?
            IF (jscweekdays[date_part(''DOW'', nextrun) + 1] = TRUE OR gotit = FALSE) THEN

                -- Check for exceptions
                SELECT INTO d jexid FROM pem.exception WHERE jexscid = jscid AND ((jexdate = pg_catalog.date(nextrun) AND jextime = nextrun::time) OR (jexdate = pg_catalog.date(nextrun) AND jextime IS NULL) OR (jexdate IS NULL AND jextime = nextrun::time));
                IF FOUND THEN
                    -- Nuts - found an exception. Increment the time and try again
                    runafter := nextrun + INTERVAL ''1 Minute'';
                    bingo := FALSE;
                    minutetweak := TRUE;
            daytweak := FALSE;
                ELSE
                    bingo := TRUE;
                END IF;
            ELSE
                -- We''re on the wrong week day - increment a day and try again.
                runafter := nextrun + INTERVAL ''1 Day'';
                bingo := FALSE;
                minutetweak := FALSE;
                daytweak := TRUE;
            END IF;

        ELSE
            runafter := nextrun + INTERVAL ''1 Minute'';
            bingo := FALSE;
            minutetweak := TRUE;
        daytweak := FALSE;
        END IF;

    END LOOP;

    RETURN nextrun;
END;
' LANGUAGE 'plpgsql' VOLATILE;

-- PEM-3360
-- EDBR Network details schema
DO $FUNC$
BEGIN
    IF NOT EXISTS(
        SELECT 1 FROM pg_class c JOIN pg_catalog.pg_namespace n ON n.oid = c.relnamespace
           WHERE c.relkind = 'r' AND n.nspname = 'pem' AND c.relname = 'edbr_network'
    ) THEN
        CREATE TABLE pem.edbr_network (
                edbr_network_id                 SERIAL NOT NULL,
                name                            text NOT NULL,
                protocol                        text NOT NULL,
                host                            text NOT NULL,
                port                            integer NOT NULL,
                api_version                     text NOT NULL,
                team                            text,
                CONSTRAINT edbr_network_pkey PRIMARY KEY (edbr_network_id)
        );

        COMMENT ON TABLE pem.edbr_network IS 'Used to store EDBR network details';
        COMMENT ON COLUMN pem.edbr_network.edbr_network_id IS 'Used to store EDBR network id';
        COMMENT ON COLUMN pem.edbr_network.name IS 'Used to store EDBR network name';
        COMMENT ON COLUMN pem.edbr_network.protocol IS 'Used to store EDBR network protocol';
        COMMENT ON COLUMN pem.edbr_network.host IS 'Used to store EDBR network host';
        COMMENT ON COLUMN pem.edbr_network.port IS 'Used to store EDBR network port';
        COMMENT ON COLUMN pem.edbr_network.api_version IS 'Used to store EDBR network api version';
        COMMENT ON COLUMN pem.edbr_network.team IS 'Used to store EDBR network team';

        GRANT SELECT, INSERT, UPDATE ON TABLE pem.edbr_network TO pem_user;
        GRANT ALL ON TABLE pem.edbr_network TO pem_admin;

    END IF;
    IF NOT EXISTS(
        SELECT 1 FROM pg_class c JOIN pg_catalog.pg_namespace n ON n.oid = c.relnamespace
           WHERE c.relkind = 'r' AND n.nspname = 'pem' AND c.relname = 'edbr_network_option'
    ) THEN
        CREATE TABLE pem.edbr_network_option(
                id serial not null,
                edbr_network_id integer not null,
                pem_user text not null,
                username text not null,
                password text,
                CONSTRAINT edbr_network_option_pkey PRIMARY KEY (id),
                CONSTRAINT edbr_network_option_network_id_fkey FOREIGN KEY (edbr_network_id)
                REFERENCES pem.edbr_network (edbr_network_id) ON DELETE CASCADE ON UPDATE RESTRICT
        );
        COMMENT ON TABLE pem.edbr_network_option IS 'Used to store EDBR network options';
        COMMENT ON COLUMN pem.edbr_network_option.edbr_network_id IS 'Used to store EDBR network id';
        COMMENT ON COLUMN pem.edbr_network_option.pem_user IS 'Used to store pem user who has registered edbr network';
        COMMENT ON COLUMN pem.edbr_network_option.username IS 'Used to store EDBR network username';
        COMMENT ON COLUMN pem.edbr_network_option.password IS 'Used to store EDBR network password';

        GRANT SELECT, INSERT, UPDATE ON TABLE pem.edbr_network_option TO pem_user;
        GRANT ALL ON TABLE pem.edbr_network_option TO pem_admin;

    END IF;
END
$FUNC$ LANGUAGE 'plpgsql';

-- PEM-699
-- Updated the "Long-running queries" Alert template

-- Update for Database level alert template
UPDATE pem.alert_template SET sql =
$sql$
SELECT
    COUNT(*)
FROM
    pemdata.session_info
WHERE	server_id = ${server_id}
AND	    database_name = '${database_name}'
-- query_start is updated, and not set to null when connection goes into idle state
AND	    is_idle = false
AND		is_vacuum = false
AND		is_autovacuum = false
AND		is_idle_in_transaction = false
AND		query_start IS NOT NULL
AND		(capture_time - query_start) > '${param_1} seconds'::interval
$sql$
where display_name='Long-running queries' and object_type=300;

-- Update for Server level alert template
UPDATE pem.alert_template SET sql =
$sql$
SELECT
    COUNT(*)
FROM
    pemdata.session_info
WHERE	server_id = ${server_id}
-- query_start is updated, and not set to null when connection goes into idle state
AND	    is_idle = false
AND		is_vacuum = false
AND		is_autovacuum = false
AND		is_idle_in_transaction = false
AND		query_start IS NOT NULL
AND		(capture_time - query_start) > '${param_1} seconds'::interval
$sql$
where display_name='Long-running queries' and object_type=200;

-- PEM-1508 Set is_graphable flag as False for system shared memory as it is constant in capacity manager and used only in tuning wizard
UPDATE pem.probe_column
set is_graphable = false
where internal_name = 'sys_shared_memory_mb';


-- Create unique index and primary key constraint using index on pemhistory tables
-- Also update alert templates to fetch the correct data for the alert
CREATE OR REPLACE FUNCTION pem.re_create_index_on_history_tables()
  RETURNS void AS
$BODY$
DECLARE
	jst_id integer;
	table_stats_job_id integer;
	db_stats_job_id integer;

	table_statistics_alert_templates text;
	database_statistics_alert_templates text;

	other_constraint_job_id integer;
	other_pk_job_id integer;
	other_drop_index_job_id integer;

	serverid integer;
	agentid integer;
	rw record;

	schema_version integer;
	index_suffix text;
BEGIN
    serverid := -1;
    agentid := -1;
    schema_version := pem.schema_version();
    index_suffix := '_pem_' || schema_version;

    -- Get agent and server with agent id = 1
    SELECT a.id as agent_id, s.id as server_id INTO agentid, serverid
    FROM pem.agent a
    JOIN pem.agent_server_binding AS asb ON a.id = asb.agent_id
    JOIN pem.server AS s ON s.id = asb.server_id
    WHERE a.id = 1 AND a.active = true AND s.active = true
    ORDER BY a.id, s.id LIMIT 1;

    -- Get agent and server with server id = 1
    IF serverid = -1 OR agentid = -1 THEN
        SELECT a.id as agent, s.id as server_id INTO agentid, serverid
        FROM pem.server s
        JOIN pem.agent_server_binding AS asb ON s.id = asb.server_id
        JOIN pem.agent AS a ON a.id = asb.agent_id
        WHERE s.id = 1 AND s.active = true AND a.active = true
        ORDER BY s.id, a.id LIMIT 1;
    END IF;

    -- If default agent_id=1 & server_id=1 is not found then get first
    -- active agent and server from agent_server binding and set all the
    -- jobs on that pemagent
    IF serverid = -1 OR agentid = -1 THEN
        SELECT a.id as agent_id, s.id as server_id INTO agentid, serverid
        FROM pem.agent a
        JOIN pem.agent_server_binding AS asb ON a.id = asb.agent_id
        JOIN pem.server AS s ON s.id = asb.server_id
        WHERE a.active = true and s.active = true
        ORDER BY a.id, s.id LIMIT 1;
    END IF;


    IF agentid <> -1 and serverid <> -1 THEN
        table_statistics_alert_templates := $$
                            UPDATE pem.alert_template SET sql = $sql$
                                SELECT SUM(d.seq_scan - COALESCE(h.seq_scan, 0))
                                FROM pemdata.table_statistics AS d
                                LEFT JOIN LATERAL (
                                    SELECT *
                                    FROM pemhistory.table_statistics AS h
                                    WHERE h.server_id = d.server_id
                                      AND h.database_name = d.database_name
                                      AND h.schema_name = d.schema_name
                                      AND h.table_name = d.table_name
                                      AND h.recorded_time <= d.recorded_time - ${param_1} * interval '1 minute'
                                    ORDER BY h.recorded_time DESC
                                    FETCH FIRST ROW ONLY
                                ) AS h ON TRUE
                                WHERE d.server_id = ${server_id}
                                  AND d.database_name = '${database_name}'
                                  AND d.schema_name = '${schema_name}'
                                  AND d.table_name = '${object_name}'$sql$
                            WHERE display_name = 'Sequential Scans' AND object_type = 500;

                            UPDATE pem.alert_template SET sql = $sql$
                                SELECT SUM(d.seq_scan - COALESCE(h.seq_scan, 0))
                                FROM pemdata.table_statistics AS d
                                LEFT JOIN LATERAL (
                                    SELECT *
                                    FROM pemhistory.table_statistics AS h
                                    WHERE h.server_id = d.server_id
                                      AND h.database_name = d.database_name
                                      AND h.schema_name = d.schema_name
                                      AND h.recorded_time <= d.recorded_time - ${param_1} * interval '1 minute'
                                    ORDER BY h.recorded_time DESC
                                    FETCH FIRST ROW ONLY
                                ) AS h ON TRUE
                                WHERE d.server_id = ${server_id}
                                  AND d.database_name = '${database_name}'
                                  AND d.schema_name = '${schema_name}'$sql$
                            WHERE display_name = 'Sequential Scans' AND object_type = 400;

                            UPDATE pem.alert_template SET sql = $sql$
                                SELECT SUM(d.seq_scan - COALESCE(h.seq_scan, 0))
                                FROM pemdata.table_statistics AS d
                                LEFT JOIN LATERAL (
                                    SELECT *
                                    FROM pemhistory.table_statistics AS h
                                    WHERE h.server_id = d.server_id
                                      AND h.database_name = d.database_name
                                      AND h.recorded_time <= d.recorded_time - ${param_1} * interval '1 minute'
                                    ORDER BY h.recorded_time DESC
                                    FETCH FIRST ROW ONLY
                                ) AS h ON TRUE
                                WHERE d.server_id = ${server_id}
                                  AND d.database_name = '${database_name}'$sql$
                            WHERE display_name = 'Sequential Scans' AND object_type = 300;

                            UPDATE pem.alert_template SET sql = $sql$
                                SELECT SUM(d.seq_scan - COALESCE(h.seq_scan, 0))
                                FROM pemdata.table_statistics AS d
                                LEFT JOIN LATERAL (
                                    SELECT *
                                    FROM pemhistory.table_statistics AS h
                                    WHERE h.server_id = d.server_id
                                      AND h.recorded_time <= d.recorded_time - ${param_1} * interval '1 minute'
                                    ORDER BY h.recorded_time DESC
                                    FETCH FIRST ROW ONLY
                                ) AS h ON TRUE
                                WHERE d.server_id = ${server_id}$sql$
                            WHERE display_name = 'Sequential Scans' AND object_type = 200;

                            UPDATE pem.alert_template SET sql = $sql$
                                SELECT SUM(d.idx_scan - COALESCE(h.idx_scan, 0))
                                FROM pemdata.table_statistics AS d
                                LEFT JOIN LATERAL (
                                    SELECT *
                                    FROM pemhistory.table_statistics AS h
                                    WHERE h.server_id = d.server_id
                                      AND h.database_name = d.database_name
                                      AND h.schema_name = d.schema_name
                                      AND h.table_name = d.table_name
                                      AND h.recorded_time <= d.recorded_time - ${param_1} * interval '1 minute'
                                    ORDER BY h.recorded_time DESC
                                    FETCH FIRST ROW ONLY
                                ) AS h ON TRUE
                                WHERE d.server_id = ${server_id}
                                  AND d.database_name = '${database_name}'
                                  AND d.schema_name = '${schema_name}'
                                  AND d.table_name = '${object_name}'$sql$
                            WHERE display_name = 'Index Scans' AND object_type = 500;

                            UPDATE pem.alert_template SET sql = $sql$
                                SELECT SUM(d.idx_scan - COALESCE(h.idx_scan, 0))
                                FROM pemdata.table_statistics AS d
                                LEFT JOIN LATERAL (
                                    SELECT *
                                    FROM pemhistory.table_statistics AS h
                                    WHERE h.server_id = d.server_id
                                      AND h.database_name = d.database_name
                                      AND h.schema_name = d.schema_name
                                      AND h.recorded_time <= d.recorded_time - ${param_1} * interval '1 minute'
                                    ORDER BY h.recorded_time DESC
                                    FETCH FIRST ROW ONLY
                                ) AS h ON TRUE
                                WHERE d.server_id = ${server_id}
                                  AND d.database_name = '${database_name}'
                                  AND d.schema_name = '${schema_name}'$sql$
                            WHERE display_name = 'Index Scans' AND object_type = 400;

                            UPDATE pem.alert_template SET sql = $sql$
                                SELECT SUM(d.idx_scan - COALESCE(h.idx_scan, 0))
                                FROM pemdata.table_statistics AS d
                                LEFT JOIN LATERAL (
                                    SELECT *
                                    FROM pemhistory.table_statistics AS h
                                    WHERE h.server_id = d.server_id
                                      AND h.database_name = d.database_name
                                      AND h.recorded_time <= d.recorded_time - ${param_1} * interval '1 minute'
                                    ORDER BY h.recorded_time DESC
                                    FETCH FIRST ROW ONLY
                                ) AS h ON TRUE
                                WHERE d.server_id = ${server_id}
                                  AND d.database_name = '${database_name}'$sql$
                            WHERE display_name = 'Index Scans' AND object_type = 300;

                            UPDATE pem.alert_template SET sql = $sql$
                                SELECT SUM(d.idx_scan - COALESCE(h.idx_scan, 0))
                                FROM pemdata.table_statistics AS d
                                LEFT JOIN LATERAL (
                                    SELECT *
                                    FROM pemhistory.table_statistics AS h
                                    WHERE h.server_id = d.server_id
                                      AND h.recorded_time <= d.recorded_time - ${param_1} * interval '1 minute'
                                    ORDER BY h.recorded_time DESC
                                    FETCH FIRST ROW ONLY
                                ) AS h ON TRUE
                                WHERE d.server_id = ${server_id}$sql$
                            WHERE display_name = 'Index Scans' AND object_type = 200;

                            UPDATE pem.alert_template SET sql = $sql$
                                SELECT SUM(d.n_tup_ins - COALESCE(h.n_tup_ins, 0))
                                FROM pemdata.table_statistics AS d
                                LEFT JOIN LATERAL (
                                    SELECT *
                                    FROM pemhistory.table_statistics AS h
                                    WHERE h.server_id = d.server_id
                                      AND h.database_name = d.database_name
                                      AND h.schema_name = d.schema_name
                                      AND h.table_name = d.table_name
                                      AND h.recorded_time <= d.recorded_time - ${param_1} * interval '1 minute'
                                    ORDER BY h.recorded_time DESC
                                    FETCH FIRST ROW ONLY
                                ) AS h ON TRUE
                                WHERE d.server_id = ${server_id}
                                  AND d.database_name = '${database_name}'
                                  AND d.schema_name = '${schema_name}'
                                  AND d.table_name = '${object_name}'$sql$
                            WHERE display_name = 'Tuples inserted' AND object_type = 500;

                            UPDATE pem.alert_template SET sql = $sql$
                                SELECT SUM(d.n_tup_ins - COALESCE(h.n_tup_ins, 0))
                                FROM pemdata.table_statistics AS d
                                LEFT JOIN LATERAL (
                                    SELECT *
                                    FROM pemhistory.table_statistics AS h
                                    WHERE h.server_id = d.server_id
                                      AND h.database_name = d.database_name
                                      AND h.schema_name = d.schema_name
                                      AND h.recorded_time <= d.recorded_time - ${param_1} * interval '1 minute'
                                    ORDER BY h.recorded_time DESC
                                    FETCH FIRST ROW ONLY
                                ) AS h ON TRUE
                                WHERE d.server_id = ${server_id}
                                  AND d.database_name = '${database_name}'
                                  AND d.schema_name = '${schema_name}'$sql$
                            WHERE display_name = 'Tuples inserted' AND object_type = 400;

                            UPDATE pem.alert_template SET sql = $sql$
                                SELECT SUM(d.n_tup_upd - COALESCE(h.n_tup_upd, 0))
                                FROM pemdata.table_statistics AS d
                                LEFT JOIN LATERAL (
                                    SELECT *
                                    FROM pemhistory.table_statistics AS h
                                    WHERE h.server_id = d.server_id
                                      AND h.database_name = d.database_name
                                      AND h.schema_name = d.schema_name
                                      AND h.table_name = d.table_name
                                      AND h.recorded_time <= d.recorded_time - ${param_1} * interval '1 minute'
                                    ORDER BY h.recorded_time DESC
                                    FETCH FIRST ROW ONLY
                                ) AS h ON TRUE
                                WHERE d.server_id = ${server_id}
                                  AND d.database_name = '${database_name}'
                                  AND d.schema_name = '${schema_name}'
                                  AND d.table_name = '${object_name}'$sql$
                            WHERE display_name = 'Tuples updated' AND object_type = 500;

                            UPDATE pem.alert_template SET sql = $sql$
                                SELECT SUM(d.n_tup_upd - COALESCE(h.n_tup_upd, 0))
                                FROM pemdata.table_statistics AS d
                                LEFT JOIN LATERAL (
                                    SELECT *
                                    FROM pemhistory.table_statistics AS h
                                    WHERE h.server_id = d.server_id
                                      AND h.database_name = d.database_name
                                      AND h.schema_name = d.schema_name
                                      AND h.recorded_time <= d.recorded_time - ${param_1} * interval '1 minute'
                                    ORDER BY h.recorded_time DESC
                                    FETCH FIRST ROW ONLY
                                ) AS h ON TRUE
                                WHERE d.server_id = ${server_id}
                                  AND d.database_name = '${database_name}'
                                  AND d.schema_name = '${schema_name}'$sql$
                            WHERE display_name = 'Tuples updated' AND object_type = 400;


                            UPDATE pem.alert_template SET sql = $sql$
                                SELECT SUM(d.n_tup_del - COALESCE(h.n_tup_del, 0))
                                FROM pemdata.table_statistics AS d
                                LEFT JOIN LATERAL (
                                    SELECT *
                                    FROM pemhistory.table_statistics AS h
                                    WHERE h.server_id = d.server_id
                                      AND h.database_name = d.database_name
                                      AND h.schema_name = d.schema_name
                                      AND h.table_name = d.table_name
                                      AND h.recorded_time <= d.recorded_time - ${param_1} * interval '1 minute'
                                    ORDER BY h.recorded_time DESC
                                    FETCH FIRST ROW ONLY
                                ) AS h ON TRUE
                                WHERE d.server_id = ${server_id}
                                  AND d.database_name = '${database_name}'
                                  AND d.schema_name = '${schema_name}'
                                  AND d.table_name = '${object_name}'$sql$
                            WHERE display_name = 'Tuples deleted' AND object_type = 500;

                            UPDATE pem.alert_template SET sql = $sql$
                                SELECT SUM(d.n_tup_del - COALESCE(h.n_tup_del, 0))
                                FROM pemdata.table_statistics AS d
                                LEFT JOIN LATERAL (
                                    SELECT *
                                    FROM pemhistory.table_statistics AS h
                                    WHERE h.server_id = d.server_id
                                      AND h.database_name = d.database_name
                                      AND h.schema_name = d.schema_name
                                      AND h.recorded_time <= d.recorded_time - ${param_1} * interval '1 minute'
                                    ORDER BY h.recorded_time DESC
                                    FETCH FIRST ROW ONLY
                                ) AS h ON TRUE
                                WHERE d.server_id = ${server_id}
                                  AND d.database_name = '${database_name}'
                                  AND d.schema_name = '${schema_name}'$sql$
                            WHERE display_name = 'Tuples deleted' AND object_type = 400;

                            UPDATE pem.alert_template SET sql = $sql$
                                SELECT SUM(d.n_tup_hot_upd - COALESCE(h.n_tup_hot_upd, 0))
                                FROM pemdata.table_statistics AS d
                                LEFT JOIN LATERAL (
                                    SELECT *
                                    FROM pemhistory.table_statistics AS h
                                    WHERE h.server_id = d.server_id
                                      AND h.database_name = d.database_name
                                      AND h.schema_name = d.schema_name
                                      AND h.table_name = d.table_name
                                      AND h.recorded_time <= d.recorded_time - ${param_1} * interval '1 minute'
                                    ORDER BY h.recorded_time DESC
                                    FETCH FIRST ROW ONLY
                                ) AS h ON TRUE
                                WHERE d.server_id = ${server_id}
                                  AND d.database_name = '${database_name}'
                                  AND d.schema_name = '${schema_name}'
                                  AND d.table_name = '${object_name}'$sql$
                            WHERE display_name = 'Tuples hot updated' AND object_type = 500;

                            UPDATE pem.alert_template SET sql = $sql$
                                SELECT SUM(d.n_tup_hot_upd - COALESCE(h.n_tup_hot_upd, 0))
                                FROM pemdata.table_statistics AS d
                                LEFT JOIN LATERAL (
                                    SELECT *
                                    FROM pemhistory.table_statistics AS h
                                    WHERE h.server_id = d.server_id
                                      AND h.database_name = d.database_name
                                      AND h.schema_name = d.schema_name
                                      AND h.recorded_time <= d.recorded_time - ${param_1} * interval '1 minute'
                                    ORDER BY h.recorded_time DESC
                                    FETCH FIRST ROW ONLY
                                ) AS h ON TRUE
                                WHERE d.server_id = ${server_id}
                                  AND d.database_name = '${database_name}'
                                  AND d.schema_name = '${schema_name}'$sql$
                            WHERE display_name = 'Tuples hot updated' AND object_type = 400;

                            UPDATE pem.alert_template SET sql = $sql$
                                SELECT SUM(d.n_tup_hot_upd - COALESCE(h.n_tup_hot_upd, 0))
                                FROM pemdata.table_statistics AS d
                                LEFT JOIN LATERAL (
                                    SELECT *
                                    FROM pemhistory.table_statistics AS h
                                    WHERE h.server_id = d.server_id
                                      AND h.database_name = d.database_name
                                      AND h.recorded_time <= d.recorded_time - ${param_1} * interval '1 minute'
                                    ORDER BY h.recorded_time DESC
                                    FETCH FIRST ROW ONLY
                                ) AS h ON TRUE
                                WHERE d.server_id = ${server_id}
                                  AND d.database_name = '${database_name}'$sql$
                            WHERE display_name = 'Tuples hot updated' AND object_type = 300;

                            UPDATE pem.alert_template SET sql = $sql$
                                SELECT SUM(d.n_tup_hot_upd - COALESCE(h.n_tup_hot_upd, 0))
                                FROM pemdata.table_statistics AS d
                                LEFT JOIN LATERAL (
                                    SELECT *
                                    FROM pemhistory.table_statistics AS h
                                    WHERE h.server_id = d.server_id
                                      AND h.recorded_time <= d.recorded_time - ${param_1} * interval '1 minute'
                                    ORDER BY h.recorded_time DESC
                                    FETCH FIRST ROW ONLY
                                ) AS h ON TRUE
                                WHERE d.server_id = ${server_id}$sql$
                            WHERE display_name = 'Tuples hot updated' AND object_type = 200;

                            UPDATE pem.alert_template SET sql = $sql$
                                SELECT SUM(d.n_tup_hot_upd - COALESCE(h.n_tup_hot_upd, 0))::float * 100
                                        /GREATEST(SUM((d.n_tup_upd - COALESCE(h.n_tup_upd, 0)) + COALESCE(d.n_tup_hot_upd - h.n_tup_hot_upd, 0)), 1)
                                FROM pemdata.table_statistics AS d
                                LEFT JOIN LATERAL (
                                    SELECT *
                                    FROM pemhistory.table_statistics AS h
                                    WHERE h.server_id = d.server_id
                                      AND h.database_name = d.database_name
                                      AND h.schema_name = d.schema_name
                                      AND h.table_name = d.table_name
                                      AND h.recorded_time <= d.recorded_time - ${param_1} * interval '1 minute'
                                    ORDER BY h.recorded_time DESC
                                    FETCH FIRST ROW ONLY
                                ) AS h ON TRUE
                                WHERE d.server_id = ${server_id}
                                  AND d.database_name = '${database_name}'
                                  AND d.schema_name = '${schema_name}'
                                  AND d.table_name = '${object_name}'$sql$
                            WHERE display_name = 'Hot update percentage' AND object_type = 500;

                            UPDATE pem.alert_template SET sql = $sql$
                                SELECT SUM(d.n_tup_hot_upd - COALESCE(h.n_tup_hot_upd, 0))::float * 100
                                        /GREATEST(SUM((d.n_tup_upd - COALESCE(h.n_tup_upd, 0)) + COALESCE(d.n_tup_hot_upd - h.n_tup_hot_upd, 0)), 1)
                                FROM pemdata.table_statistics AS d
                                LEFT JOIN LATERAL (
                                    SELECT *
                                    FROM pemhistory.table_statistics AS h
                                    WHERE h.server_id = d.server_id
                                      AND h.database_name = d.database_name
                                      AND h.schema_name = d.schema_name
                                      AND h.recorded_time <= d.recorded_time - ${param_1} * interval '1 minute'
                                    ORDER BY h.recorded_time DESC
                                    FETCH FIRST ROW ONLY
                                ) AS h ON TRUE
                                WHERE d.server_id = ${server_id}
                                  AND d.database_name = '${database_name}'
                                  AND d.schema_name = '${schema_name}'$sql$
                            WHERE display_name = 'Hot update percentage' AND object_type = 400;

                            UPDATE pem.alert_template SET sql = $sql$
                                SELECT SUM(d.n_tup_hot_upd - COALESCE(h.n_tup_hot_upd, 0))::float * 100
                                        /GREATEST(SUM((d.n_tup_upd - COALESCE(h.n_tup_upd, 0)) + COALESCE(d.n_tup_hot_upd - h.n_tup_hot_upd, 0)), 1)
                                FROM pemdata.table_statistics AS d
                                LEFT JOIN LATERAL (
                                    SELECT *
                                    FROM pemhistory.table_statistics AS h
                                    WHERE h.server_id = d.server_id
                                      AND h.database_name = d.database_name
                                      AND h.recorded_time <= d.recorded_time - ${param_1} * interval '1 minute'
                                    ORDER BY h.recorded_time DESC
                                    FETCH FIRST ROW ONLY
                                ) AS h ON TRUE
                                WHERE d.server_id = ${server_id}
                                  AND d.database_name = '${database_name}'$sql$
                            WHERE display_name = 'Hot update percentage' AND object_type = 300;

                            UPDATE pem.alert_template SET sql = $sql$
                                SELECT SUM(d.n_tup_hot_upd - COALESCE(h.n_tup_hot_upd, 0))::float * 100
                                        /GREATEST(SUM((d.n_tup_upd - COALESCE(h.n_tup_upd, 0)) + COALESCE(d.n_tup_hot_upd - h.n_tup_hot_upd, 0)), 1)
                                FROM pemdata.table_statistics AS d
                                LEFT JOIN LATERAL (
                                    SELECT *
                                    FROM pemhistory.table_statistics AS h
                                    WHERE h.server_id = d.server_id
                                      AND h.recorded_time <= d.recorded_time - ${param_1} * interval '1 minute'
                                    ORDER BY h.recorded_time DESC
                                    FETCH FIRST ROW ONLY
                                ) AS h ON TRUE
                                WHERE d.server_id = ${server_id}$sql$
                            WHERE display_name = 'Hot update percentage' AND object_type = 200;


        $$;

	    database_statistics_alert_templates := $$
                            UPDATE pem.alert_template SET sql = $sql$
                                SELECT SUM(d.tup_fetched - COALESCE(h.tup_fetched, 0))
                                FROM pemdata.database_statistics AS d
                                LEFT JOIN LATERAL (
                                    SELECT *
                                    FROM pemhistory.database_statistics AS h
                                    WHERE h.server_id = d.server_id
                                      AND h.database_name = d.database_name
                                      AND h.recorded_time <= d.recorded_time - ${param_1} * interval '1 minute'
                                    ORDER BY h.recorded_time DESC
                                    FETCH FIRST ROW ONLY
                                ) AS h ON TRUE
                                WHERE d.server_id = ${server_id}
                                  AND d.database_name = '${database_name}'$sql$
                            WHERE display_name = 'Tuples fetched' AND object_type = 300;

                            UPDATE pem.alert_template SET sql = $sql$
                                SELECT SUM(d.tup_fetched - COALESCE(h.tup_fetched, 0))
                                FROM pemdata.database_statistics AS d
                                LEFT JOIN LATERAL (
                                    SELECT *
                                    FROM pemhistory.database_statistics AS h
                                    WHERE h.server_id = d.server_id
                                      AND h.recorded_time <= d.recorded_time - ${param_1} * interval '1 minute'
                                    ORDER BY h.recorded_time DESC
                                    FETCH FIRST ROW ONLY
                                ) AS h ON TRUE
                                WHERE d.server_id = ${server_id}$sql$
                            WHERE display_name = 'Tuples fetched' AND object_type = 200;

                            UPDATE pem.alert_template SET sql = $sql$
                                SELECT SUM(d.tup_returned - COALESCE(h.tup_returned, 0))
                                FROM pemdata.database_statistics AS d
                                LEFT JOIN LATERAL (
                                    SELECT *
                                    FROM pemhistory.database_statistics AS h
                                    WHERE h.server_id = d.server_id
                                      AND h.database_name = d.database_name
                                      AND h.recorded_time <= d.recorded_time - ${param_1} * interval '1 minute'
                                    ORDER BY h.recorded_time DESC
                                    FETCH FIRST ROW ONLY
                                ) AS h ON TRUE
                                WHERE d.server_id = ${server_id}
                                  AND d.database_name = '${database_name}'$sql$
                            WHERE display_name = 'Tuples returned' AND object_type = 300;

                            UPDATE pem.alert_template SET sql = $sql$
                                SELECT SUM(d.tup_returned - COALESCE(h.tup_returned, 0))
                                FROM pemdata.database_statistics AS d
                                LEFT JOIN LATERAL (
                                    SELECT *
                                    FROM pemhistory.database_statistics AS h
                                    WHERE h.server_id = d.server_id
                                      AND h.recorded_time <= d.recorded_time - ${param_1} * interval '1 minute'
                                    ORDER BY h.recorded_time DESC
                                    FETCH FIRST ROW ONLY
                                ) AS h ON TRUE
                                WHERE d.server_id = ${server_id}$sql$
                            WHERE display_name = 'Tuples returned' AND object_type = 200;

                            UPDATE pem.alert_template SET sql = $sql$
                                SELECT SUM(d.tup_inserted - COALESCE(h.tup_inserted, 0))
                                FROM pemdata.database_statistics AS d
                                LEFT JOIN LATERAL (
                                    SELECT *
                                    FROM pemhistory.database_statistics AS h
                                    WHERE h.server_id = d.server_id
                                      AND h.database_name = d.database_name
                                      AND h.recorded_time <= d.recorded_time - ${param_1} * interval '1 minute'
                                    ORDER BY h.recorded_time DESC
                                    FETCH FIRST ROW ONLY
                                ) AS h ON TRUE
                                WHERE d.server_id = ${server_id}
                                  AND d.database_name = '${database_name}'$sql$
                            WHERE display_name = 'Tuples inserted' AND object_type = 300;

                            UPDATE pem.alert_template SET sql = $sql$
                                SELECT SUM(d.tup_inserted - COALESCE(h.tup_inserted, 0))
                                FROM pemdata.database_statistics AS d
                                LEFT JOIN LATERAL (
                                    SELECT *
                                    FROM pemhistory.database_statistics AS h
                                    WHERE h.server_id = d.server_id
                                      AND h.recorded_time <= d.recorded_time - ${param_1} * interval '1 minute'
                                    ORDER BY h.recorded_time DESC
                                    FETCH FIRST ROW ONLY
                                ) AS h ON TRUE
                                WHERE d.server_id = ${server_id}$sql$
                            WHERE display_name = 'Tuples inserted' AND object_type = 200;

                            UPDATE pem.alert_template SET sql = $sql$
                                SELECT SUM(d.tup_updated - COALESCE(h.tup_updated, 0))
                                FROM pemdata.database_statistics AS d
                                LEFT JOIN LATERAL (
                                    SELECT *
                                    FROM pemhistory.database_statistics AS h
                                    WHERE h.server_id = d.server_id
                                      AND h.database_name = d.database_name
                                      AND h.recorded_time <= d.recorded_time - ${param_1} * interval '1 minute'
                                    ORDER BY h.recorded_time DESC
                                    FETCH FIRST ROW ONLY
                                ) AS h ON TRUE
                                WHERE d.server_id = ${server_id}
                                  AND d.database_name = '${database_name}'$sql$
                            WHERE display_name = 'Tuples updated' AND object_type = 300;

                            UPDATE pem.alert_template SET sql = $sql$
                                SELECT SUM(d.tup_updated - COALESCE(h.tup_updated, 0))
                                FROM pemdata.database_statistics AS d
                                LEFT JOIN LATERAL (
                                    SELECT *
                                    FROM pemhistory.database_statistics AS h
                                    WHERE h.server_id = d.server_id
                                      AND h.recorded_time <= d.recorded_time - ${param_1} * interval '1 minute'
                                    ORDER BY h.recorded_time DESC
                                    FETCH FIRST ROW ONLY
                                ) AS h ON TRUE
                                WHERE d.server_id = ${server_id}$sql$
                            WHERE display_name = 'Tuples updated' AND object_type = 200;
                            UPDATE pem.alert_template SET sql = $sql$
                                SELECT SUM(d.tup_deleted - COALESCE(h.tup_deleted, 0))
                                FROM pemdata.database_statistics AS d
                                LEFT JOIN LATERAL (
                                    SELECT *
                                    FROM pemhistory.database_statistics AS h
                                    WHERE h.server_id = d.server_id
                                      AND h.database_name = d.database_name
                                      AND h.recorded_time <= d.recorded_time - ${param_1} * interval '1 minute'
                                    ORDER BY h.recorded_time DESC
                                    FETCH FIRST ROW ONLY
                                ) AS h ON TRUE
                                WHERE d.server_id = ${server_id}
                                  AND d.database_name = '${database_name}'$sql$
                            WHERE display_name = 'Tuples deleted' AND object_type = 300;

                            UPDATE pem.alert_template SET sql = $sql$
                                SELECT SUM(d.tup_deleted - COALESCE(h.tup_deleted, 0))
                                FROM pemdata.database_statistics AS d
                                LEFT JOIN LATERAL (
                                    SELECT *
                                    FROM pemhistory.database_statistics AS h
                                    WHERE h.server_id = d.server_id
                                      AND h.recorded_time <= d.recorded_time - ${param_1} * interval '1 minute'
                                    ORDER BY h.recorded_time DESC
                                    FETCH FIRST ROW ONLY
                                ) AS h ON TRUE
                                WHERE d.server_id = ${server_id}$sql$
                            WHERE display_name = 'Tuples deleted' AND object_type = 200;

                            UPDATE pem.alert_template SET sql = $sql$
                                SELECT SUM(abs(d.blks_hit - COALESCE(h.blks_hit, 0)))::float * 100
                                            / GREATEST(SUM(abs(d.blks_hit - COALESCE(h.blks_hit, 0)) + abs(d.blks_read - COALESCE(h.blks_read, 0)) + COALESCE(abs(d.blks_icache_hit-COALESCE(h.blks_icache_hit, 0)), 0)), 1)
                                FROM pemdata.database_statistics AS d
                                LEFT JOIN LATERAL (
                                    SELECT *
                                    FROM pemhistory.database_statistics AS h
                                    WHERE h.server_id = d.server_id
                                      AND h.database_name = d.database_name
                                      AND h.recorded_time <= d.recorded_time - ${param_1} * interval '1 minute'
                                    ORDER BY h.recorded_time DESC
                                    FETCH FIRST ROW ONLY
                                ) AS h ON TRUE
                                WHERE d.server_id = ${server_id}
                                  AND d.database_name = '${database_name}'$sql$
                            WHERE display_name = 'Shared buffers hit percentage' AND object_type = 300;

                            UPDATE pem.alert_template SET sql = $sql$
                                SELECT SUM(abs(d.blks_hit - COALESCE(h.blks_hit, 0)))::float * 100
                                            / GREATEST(SUM(abs(d.blks_hit - COALESCE(h.blks_hit, 0)) + abs(d.blks_read - COALESCE(h.blks_read, 0)) + COALESCE(abs(d.blks_icache_hit - COALESCE(h.blks_icache_hit, 0)), 0)), 1)
                                FROM pemdata.database_statistics AS d
                                LEFT JOIN LATERAL (
                                    SELECT *
                                    FROM pemhistory.database_statistics AS h
                                    WHERE h.server_id = d.server_id
                                      AND h.recorded_time <= d.recorded_time - ${param_1} * interval '1 minute'
                                    ORDER BY h.recorded_time DESC
                                    FETCH FIRST ROW ONLY
                                ) AS h ON TRUE
                                WHERE d.server_id = ${server_id}$sql$
                            WHERE display_name = 'Shared buffers hit percentage' AND object_type = 200;

                            UPDATE pem.alert_template SET sql = $sql$
                                SELECT SUM(d.blks_icache_hit - COALESCE(h.blks_icache_hit, 0))::float * 100
                                            / GREATEST((d.blks_hit - COALESCE(h.blks_hit, 0)) + (d.blks_read - COALESCE(h.blks_read, 0)) + COALESCE(d.blks_icache_hit - h.blks_icache_hit, 0), 1)
                                FROM pemdata.database_statistics AS d
                                LEFT JOIN LATERAL (
                                    SELECT *
                                    FROM pemhistory.database_statistics AS h
                                    WHERE h.server_id = d.server_id
                                      AND h.database_name = d.database_name
                                      AND h.recorded_time <= d.recorded_time - ${param_1} * interval '1 minute'
                                    ORDER BY h.recorded_time DESC
                                    FETCH FIRST ROW ONLY
                                ) AS h ON TRUE
                                WHERE d.server_id = ${server_id}
                                  AND d.database_name = '${database_name}'$sql$
                            WHERE display_name = 'InfiniteCache buffers hit percentage' AND object_type = 300;

                            UPDATE pem.alert_template SET sql = $sql$
                                SELECT SUM(d.blks_icache_hit - COALESCE(h.blks_icache_hit, 0))::float * 100
                                            / GREATEST((d.blks_hit - COALESCE(h.blks_hit, 0)) + (d.blks_read - COALESCE(h.blks_read, 0)) + COALESCE(d.blks_icache_hit - h.blks_icache_hit, 0), 1)
                                FROM pemdata.database_statistics AS d
                                LEFT JOIN LATERAL (
                                    SELECT *
                                    FROM pemhistory.database_statistics AS h
                                    WHERE h.server_id = d.server_id
                                      AND h.recorded_time <= d.recorded_time - ${param_1} * interval '1 minute'
                                    ORDER BY h.recorded_time DESC
                                    FETCH FIRST ROW ONLY
                                ) AS h ON TRUE
                                WHERE d.server_id = ${server_id}$sql$
                            WHERE display_name = 'InfiniteCache buffers hit percentage' AND object_type = 200;
	    $$;


        SELECT jobid INTO other_constraint_job_id FROM pem.job WHERE issystemjob = true and jobname = 'Create unique index on pem history tables except table_statistics and database_statistics tables';

        IF (NOT FOUND) THEN
            -- Create job
            INSERT INTO pem.job(jobname, jobdesc, agent_id, issystemjob, jobnextrun)
            VALUES('Create unique index on pem history tables except table_statistics and database_statistics tables',
            'This job will create unique index which will be used for creating primary keys', agentid, true, now() + (1 * interval '1 minute')) RETURNING jobid INTO other_constraint_job_id;

        END IF;

        FOR rw IN
            SELECT p.internal_name as table_name, format('CREATE UNIQUE INDEX CONCURRENTLY %I ON pemhistory.%I (%s);',
			p.internal_name || index_suffix,
			p.internal_name,
			array_to_string(array_agg(quote_ident(a.attname) ORDER BY keys.ordinality) || ARRAY['recorded_time'], ', ')) as query
            FROM pem.probe AS p
            JOIN pg_class AS c ON p.internal_name = c.relname
            JOIN pg_attribute AS a ON a.attrelid = c.oid
            JOIN pg_constraint AS con ON con.conrelid = c.oid
            JOIN LATERAL UNNEST(con.conkey) WITH ORDINALITY AS keys (key, ordinality) ON keys.key = a.attnum
            WHERE p.internal_name NOT IN ('table_statistics', 'database_statistics') AND p.discard_history = false
            AND c.relnamespace = (SELECT oid FROM pg_namespace WHERE nspname = 'pemdata') AND con.contype = 'p'
            GROUP BY p.internal_name
        LOOP

            SELECT jstid INTO jst_id FROM pem.jobstep WHERE jstname = 'Create unique index on ' || rw.table_name and jstjobid = other_pk_job_id;

            IF (NOT FOUND) THEN
                -- Create index
                INSERT INTO pem.jobstep(jstjobid, jstname, jstenabled, jstkind, jstcode, server_id, database_name)
                VALUES (
                other_constraint_job_id,
                'Create unique index on ' || rw.table_name,
                true,
                's'::character(1),
                rw.query::text,
                serverid::integer,
                'pem'::text);

            END IF;
        END LOOP;

        SELECT jobid INTO other_pk_job_id FROM pem.job WHERE issystemjob = true and jobname = 'Create primary key constraints on pem history tables except table_statistics and database_statistics tables';

        IF (NOT FOUND) THEN
            INSERT INTO pem.job(jobname, jobdesc, agent_id, issystemjob, jobnextrun, dependent_on_job)
            VALUES('Create primary key constraints on pem history tables except table_statistics and database_statistics tables',
            'This job will create primary key constraints on pem history tables except table_statistics and database_statistics tables', agentid, true, now() + (1 * interval '1 minute'), format('{%I}', other_constraint_job_id)::integer[]) RETURNING jobid INTO other_pk_job_id;
        END IF;

        FOR rw IN
            SELECT relname as table_name, format('ALTER TABLE pemhistory.%I ADD CONSTRAINT %I PRIMARY KEY USING INDEX %I;', relname, relname || '_pkey', relname || index_suffix) as query
            FROM (
            SELECT distinct(p.internal_name) as relname
            FROM pem.probe as p
            JOIN pg_class AS c ON p.internal_name = c.relname
            JOIN pg_index AS i ON i.indrelid = c.oid
            WHERE p.internal_name NOT IN ('table_statistics', 'database_statistics') AND p.discard_history = false) AS pci
        LOOP

            SELECT jstid INTO jst_id FROM pem.jobstep WHERE jstname = 'Create primary key constraints on ' || rw.table_name and jstjobid = other_pk_job_id;

            IF (NOT FOUND) THEN
                -- Create primary key
                INSERT INTO pem.jobstep(
                jstjobid, jstname, jstenabled, jstkind, jstcode, server_id, database_name)
                VALUES (
                other_pk_job_id,
                'Create primary key constraints on ' || rw.table_name,
                true,
                's'::character(1),
                rw.query::text,
                serverid::integer,
                'pem'::text);
            END IF;
        END LOOP;


        SELECT jobid INTO other_drop_index_job_id FROM pem.job WHERE issystemjob = true and jobname = 'Drop old indexes on pem history tables except table_statistics and database_statistics tables';

        IF (NOT FOUND) THEN
            INSERT INTO pem.job(jobname, jobdesc, agent_id, issystemjob, jobnextrun, dependent_on_job)
            VALUES('Drop old indexes on pem history tables except table_statistics and database_statistics tables',
            'This job will drop old indexes on pem history tables', agentid, true, now() + (1 * interval '1 minute'), format('{%I}', other_pk_job_id)::integer[]) RETURNING jobid INTO other_drop_index_job_id;
        END IF;

        FOR rw IN
            SELECT p.internal_name || '_keyidx' as index_name, format('DROP INDEX CONCURRENTLY IF EXISTS pemhistory.%I;', p.internal_name || '_keyidx') as query
            FROM pem.probe AS p
            WHERE p.internal_name NOT IN ('table_statistics', 'database_statistics') AND p.discard_history = false
            ORDER BY p.internal_name
        LOOP

            SELECT jstid INTO jst_id FROM pem.jobstep WHERE jstname = 'Drop old index ' || rw.index_name::text and jstjobid = other_drop_index_job_id;

            IF (NOT FOUND) THEN
                INSERT INTO pem.jobstep(
                jstjobid, jstname, jstenabled, jstkind, jstcode, server_id, database_name)
                VALUES (
                other_drop_index_job_id,
                'Drop old index ' || rw.index_name::text,
                true,
                's'::character(1),
                rw.query::text,
                serverid::integer,
                'pem'::text);
            END IF;

        END LOOP;

        SELECT jobid INTO table_stats_job_id FROM pem.job WHERE issystemjob = true and jobname = 'Create unique index and primary key constraint on table_statistics history tables and update alert templates';

        IF (NOT FOUND) THEN
            -- create job to re-create index for table_statistics
            INSERT INTO pem.job(jobname, jobdesc, agent_id, issystemjob, jobnextrun)
            VALUES('Create unique index and primary key constraint on table_statistics history tables and update alert templates',
            'This job will create unique index and primary key constraint on table_statistics history tables and update the alert templates', agentid, true, now() + (20 * interval '1 minute') ) RETURNING jobid INTO table_stats_job_id;

        END IF;

        SELECT jstid INTO jst_id FROM pem.jobstep WHERE jstname = 'Create unique index on table_statistics history table' and jstjobid = table_stats_job_id;

        IF (NOT FOUND) THEN
            -- Create index on table_statistics
            INSERT INTO pem.jobstep(jstjobid, jstname, jstenabled, jstkind, jstcode, server_id, database_name)
            VALUES (
            table_stats_job_id,
            'Create unique index on table_statistics history table',
            true,
            's'::character(1),
            'CREATE UNIQUE INDEX CONCURRENTLY "table_statistics' || index_suffix || '" ON pemhistory.table_statistics (server_id, database_name, schema_name, table_name, recorded_time);'::text,
            serverid::integer,
            'pem'::text);

        END IF;

        SELECT jstid INTO jst_id FROM pem.jobstep WHERE jstname = 'Create primary key constraint on table_statistics' and jstjobid = table_stats_job_id;

        IF (NOT FOUND) THEN
            -- Create primary key created index on table_statistics
            INSERT INTO pem.jobstep(jstjobid, jstname, jstenabled, jstkind, jstcode, server_id, database_name)
            VALUES (
            table_stats_job_id,
            'Create primary key constraint on table_statistics',
            true,
            's'::character(1),
            'ALTER TABLE pemhistory.table_statistics ADD CONSTRAINT table_statistics_pkey PRIMARY KEY USING INDEX "table_statistics' || index_suffix || '";'::text,
            serverid::integer,
            'pem'::text);
        END IF;


        SELECT jstid INTO jst_id FROM pem.jobstep WHERE jstname = 'Drop old index on table_statistics' and jstjobid = table_stats_job_id;

        IF (NOT FOUND) THEN
            -- Drop old index on table_statistics
            INSERT INTO pem.jobstep(jstjobid, jstname, jstenabled, jstkind, jstcode, server_id, database_name)
            VALUES (
            table_stats_job_id,
            'Drop old index on table_statistics',
            true,
            's'::character(1),
            'DROP INDEX CONCURRENTLY pemhistory.table_statistics_keyidx;'::text,
            serverid::integer,
            'pem'::text);
        END IF;


        SELECT jstid INTO jst_id FROM pem.jobstep WHERE jstname = 'Update alert templates for table_statistics' and jstjobid = table_stats_job_id;

        IF (NOT FOUND) THEN
            -- Create job step to update alert templates
            INSERT INTO pem.jobstep(jstjobid, jstname, jstenabled, jstkind, jstcode, server_id, database_name)
            VALUES (
            table_stats_job_id,
            'Update alert templates for table_statistics',
            true,
            's'::character(1),
            table_statistics_alert_templates,
            serverid::integer,
            'pem'::text);
        END IF;


        SELECT jobid INTO db_stats_job_id FROM pem.job WHERE issystemjob = true and jobname = 'Create unique index and primary key constraint on database_statistics history tables and update alert templates';

        IF (NOT FOUND) THEN
            -- create job to re-create index for database_statistics
            INSERT INTO pem.job(jobname, jobdesc, agent_id, issystemjob, jobnextrun)
            VALUES('Create unique index and primary key constraint on database_statistics history tables and update alert templates',
            'This job will create unique index and primary key constraint on database_statistics history tables and update alert templates', agentid, true, now() + (45 * interval '1 minute') ) RETURNING jobid INTO db_stats_job_id;

        END IF;

        SELECT jstid INTO jst_id FROM pem.jobstep WHERE jstname = 'Create unique index on database_statistics history table' and jstjobid = db_stats_job_id;

        IF (NOT FOUND) THEN
            -- Create index on database_statistics
            INSERT INTO pem.jobstep(jstjobid, jstname, jstenabled, jstkind, jstcode, server_id, database_name)
            VALUES (
            db_stats_job_id,
            'Create unique index on database_statistics history table',
            true,
            's'::character(1),
            'CREATE UNIQUE INDEX CONCURRENTLY "database_statistics' || index_suffix || '" ON pemhistory.database_statistics (server_id, database_name, recorded_time);'::text,
            serverid::integer,
            'pem'::text);

        END IF;

        SELECT jstid INTO jst_id FROM pem.jobstep WHERE jstname = 'Create primary key constraint on database_statistics' and jstjobid = db_stats_job_id;

        IF (NOT FOUND) THEN
            -- Create primary key constraint on database_statistics
            INSERT INTO pem.jobstep(jstjobid, jstname, jstenabled, jstkind, jstcode, server_id, database_name)
            VALUES (
            db_stats_job_id,
            'Create primary key constraint on database_statistics',
            true,
            's'::character(1),
            'ALTER TABLE pemhistory.database_statistics ADD CONSTRAINT database_statistics_pkey PRIMARY KEY USING INDEX "database_statistics' || index_suffix || '";'::text,
            serverid::integer,
            'pem'::text);
        END IF;


        SELECT jstid INTO jst_id FROM pem.jobstep WHERE jstname = 'Drop old index on database_statistics' and jstjobid = db_stats_job_id;

        IF (NOT FOUND) THEN
            -- Drop old index on database_statistics
            INSERT INTO pem.jobstep(jstjobid, jstname, jstenabled, jstkind, jstcode, server_id, database_name)
            VALUES (
            db_stats_job_id,
            'Drop old index on database_statistics',
            true,
            's'::character(1),
            'DROP INDEX CONCURRENTLY pemhistory.database_statistics_keyidx;'::text,
            serverid::integer,
            'pem'::text);
        END IF;

        SELECT jstid INTO jst_id FROM pem.jobstep WHERE jstname = 'Update alert templates for database_statistics' and jstjobid = db_stats_job_id;

        IF (NOT FOUND) THEN
            -- Create job step to update alert templates
            INSERT INTO pem.jobstep(jstjobid, jstname, jstenabled, jstkind, jstcode, server_id, database_name)
            VALUES (
            db_stats_job_id,
            'Update alert templates for database_statistics',
            true,
            's'::character(1),
            database_statistics_alert_templates::text,
            serverid::integer,
            'pem'::text);
        END IF;
	END IF;
END;
$BODY$ LANGUAGE plpgsql;

SELECT pem.re_create_index_on_history_tables();


--JIRA PEM-3432 added support for monitoring of PG/AS 13

DO $DO$
BEGIN
        -- Check if the server version already exist for PG 13
        IF NOT EXISTS (SELECT id FROM pem.server_version WHERE id = 11300) THEN
            INSERT INTO pem.server_version VALUES (11300, 'PostgreSQL 13');
        END IF;

        -- Check if the server version already exist for EPAS 13
        IF NOT EXISTS (SELECT id FROM pem.server_version WHERE id = 21300) THEN
            INSERT INTO pem.server_version VALUES (21300, 'Advanced Server 13');
        END IF;

        -- Check if the probe server version already exist for PG 13
        IF NOT EXISTS (SELECT server_version_id FROM pem.probe_server_version WHERE server_version_id = 11300) THEN
            INSERT INTO pem.probe_server_version
				(probe_id, server_version_id, probe_code)
				SELECT psv.probe_id, 11300 AS server_version_id, psv.probe_code FROM (
						SELECT probe_id, probe_code FROM pem.probe_server_version
						WHERE server_version_id = 11200
				) AS psv
				JOIN pem.probe p ON (psv.probe_id = p.id) AND p.internal_name = ANY(
					ARRAY[
					'oc_table', 'oc_schema', 'oc_function', 'oc_extension', 'oc_views',
					'database_statistics', 'table_statistics', 'table_frozenxid',
					'table_size', 'function_statistics', 'mview_bloat',
					'mview_frozenxid', 'mview_size', 'blocked_session_info',
					'background_writer_statistics', 'session_info', 'lock_info',
					'number_of_wal_files', 'wal_archive_status',
					'streaming_replication', 'streaming_replication_db_conflicts',
					'streaming_replication_lag_time', 'xdb_smr_mmr_replication',
					'efm_cluster_node_status', 'efm_cluster_info'
					]::text[]
		);
        END IF;

        -- Check if the probe server version already exist for EPAS 13
        IF NOT EXISTS (SELECT server_version_id FROM pem.probe_server_version WHERE server_version_id = 21300) THEN
            INSERT INTO pem.probe_server_version
				(probe_id, server_version_id, probe_code)
				SELECT psv.probe_id, 21300 AS server_version_id, psv.probe_code FROM (
						SELECT probe_id, probe_code FROM pem.probe_server_version
						WHERE server_version_id = 21200
				) AS psv
				JOIN pem.probe p ON (psv.probe_id = p.id) AND p.internal_name = ANY(
						ARRAY[
						'oc_table', 'oc_schema','oc_function', 'oc_extension', 'database_statistics',
						'table_statistics', 'table_frozenxid', 'function_statistics', 'table_size',
						'background_writer_statistics', 'number_of_wal_files', 'session_info',
						'system_waits', 'session_waits', 'lock_info', 'audit_configuration',
						'streaming_replication', 'streaming_replication_db_conflicts',
						'xdb_smr_mmr_replication', 'oc_views', 'mview_bloat', 'mview_frozenxid',
						'mview_size', 'streaming_replication_lag_time', 'wal_archive_status',
						'efm_cluster_node_status', 'efm_cluster_info', 'blocked_session_info'
						]::text[]
		);
        END IF;
END;
$DO$ LANGUAGE 'plpgsql';

-- PEM-3415 Add role based management for EDBR
DO $DO$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname='pem_comp_edbr') THEN
        PERFORM pem.create_role_for(
            'comp_edbr',
            'Role to access EDBR tool in PEM',
            ARRAY['pem_component'],
            -- INSERT
            '{}'::text[],
            -- UPDATE
            '{}'::text[],
            -- DELETE
            '{}'::text[],
            -- ALL
            ARRAY[
                ARRAY['pem', 'edbr_network'],
                ARRAY['pem', 'edbr_network_option']
            ]
        );
    END IF;
END;
$DO$ LANGUAGE 'plpgsql';


-- PEM-2540
-- Adding new column to store xLogReceive parameter of efm cluster-status-json output

DO $DO$
BEGIN
    IF NOT EXISTS (SELECT id FROM pem.probe_column WHERE internal_name = 'efm_xlog_receive' and probe_id=(SELECT id FROM pem.probe WHERE internal_name='efm_cluster_node_status')) THEN
        INSERT INTO pem.probe_column
                (probe_id, internal_name, display_name, display_position, classification,
                sql_data_type, unit_of_value, calculate_pit, discard_history, pit_by_default, is_graphable)
        SELECT
                (SELECT id FROM pem.probe WHERE internal_name='efm_cluster_node_status'),
                v.internal_name, v.display_name, v.display_position, v.classification,
                v.sql_data_type, v.unit_of_value, v.calculate_pit, v.discard_history, v.pit_by_default, v.is_graphable
        FROM
                (VALUES
                ('efm_xlog_receive', 'XLog Receive', 10, 'm', 'text',   '', false, false, false, false)
                ) v(internal_name, display_name, display_position, classification,
                        sql_data_type, unit_of_value, calculate_pit, discard_history, pit_by_default, is_graphable);
    END IF;

    IF NOT EXISTS (SELECT 1
                   FROM pg_attribute 
                   WHERE attrelid = (SELECT oid FROM pg_class WHERE relname = 'efm_cluster_node_status' and relnamespace = (SELECT oid FROM pg_namespace WHERE nspname = 'pemdata')) 
                   AND attname = 'efm_xlog_receive') THEN
                   ALTER TABLE pemdata.efm_cluster_node_status ADD COLUMN efm_xlog_receive text DEFAULT '';
    END IF;
	
	
    IF NOT EXISTS (SELECT 1
                   FROM pg_attribute
                   WHERE attrelid = (SELECT oid FROM pg_class WHERE relname = 'efm_cluster_node_status' and relnamespace = (SELECT oid FROM pg_namespace WHERE nspname = 'pemhistory')) 
                   AND attname = 'efm_xlog_receive') THEN
                   ALTER TABLE pemhistory.efm_cluster_node_status ADD COLUMN efm_xlog_receive text DEFAULT '';
    END IF;


    UPDATE pem.chart_func SET func=E'
        SELECT
            efm_agent_type AS "Agent Type", efm_ip_address AS "Address",
            efm_agent_status AS "Agent", efm_db_status AS "DB",
            efm_xlog_loc AS "XLog Loc", efm_xlog_receive AS "XLog Receive",
            efm_status_info AS "Status Info", efm_xlog_info AS "XLog Info",
            efm_vip AS "Virtual IP Address", efm_vip_status AS "VIP Status"
        FROM
            pemdata.efm_cluster_node_status
        WHERE server_id = $1::int4'
    WHERE dep_probes='{efm_cluster_node_status}';
END;
$DO$ LANGUAGE 'plpgsql';

-- PEM-3445 - Add support for new configurations for BART 2.5
DO $DO$
BEGIN
    IF NOT EXISTS (SELECT id FROM pem.bart_version WHERE id = 2005000) THEN
        INSERT INTO pem.bart_version VALUES (2005000, 'BART (EnterpriseDB) 2.5');
    END IF;

    IF NOT EXISTS (SELECT version FROM pem.bart_default_config WHERE version = 2005000) THEN
        INSERT INTO pem.bart_default_config VALUES (29, 2005000, 'bart_user', NULL, true);
        INSERT INTO pem.bart_default_config VALUES (30, 2005000, 'bart_host', NULL, true);
        INSERT INTO pem.bart_default_config VALUES (31, 2005000, 'backup_path', NULL, true);
        INSERT INTO pem.bart_default_config VALUES (32, 2005000, 'pg_basebackup_path', NULL, true);
        INSERT INTO pem.bart_default_config VALUES (33, 2005000, 'xlog_method', 'fetch');
        INSERT INTO pem.bart_default_config VALUES (34, 2005000, 'retention_policy');
        INSERT INTO pem.bart_default_config VALUES (35, 2005000, 'logfile');
        INSERT INTO pem.bart_default_config VALUES (36, 2005000, 'scanner_logfile');
        INSERT INTO pem.bart_default_config VALUES (37, 2005000, 'wal_compression', 'disabled');
        INSERT INTO pem.bart_default_config VALUES (38, 2005000, 'copy_wals_during_restore', 'disabled');
        INSERT INTO pem.bart_default_config VALUES (39, 2005000, 'thread_count', '1');
        INSERT INTO pem.bart_default_config VALUES (40, 2005000, 'batch_size', '49142');
        INSERT INTO pem.bart_default_config VALUES (41, 2005000, 'scan_interval', '1');
        INSERT INTO pem.bart_default_config VALUES (42, 2005000, 'mbm_scan_timeout', '20');
        INSERT INTO pem.bart_default_config VALUES (43, 2005000, 'workers', '1');
        INSERT INTO pem.bart_default_config VALUES (44, 2005000, 'bart_socket_directory', '/tmp');
    END IF;

    IF NOT EXISTS (SELECT version FROM pem.bart_server_default_config WHERE version = 2005000) THEN
        INSERT INTO pem.bart_server_default_config VALUES (37, 2005000, 'backup_name');
        INSERT INTO pem.bart_server_default_config VALUES (38, 2005000, 'host', NULL, true);
        INSERT INTO pem.bart_server_default_config VALUES (39, 2005000, 'user', NULL, true);
        INSERT INTO pem.bart_server_default_config VALUES (40, 2005000, 'port', '5444');
        INSERT INTO pem.bart_server_default_config VALUES (41, 2005000, 'archive_command');
        INSERT INTO pem.bart_server_default_config VALUES (42, 2005000, 'cluster_owner', NULL, true);
        INSERT INTO pem.bart_server_default_config VALUES (43, 2005000, 'remote_host');
        INSERT INTO pem.bart_server_default_config VALUES (44, 2005000, 'tablespace_path');
        INSERT INTO pem.bart_server_default_config VALUES (45, 2005000, 'xlog_method', 'fetch');
        INSERT INTO pem.bart_server_default_config VALUES (46, 2005000, 'retention_policy');
        INSERT INTO pem.bart_server_default_config VALUES (47, 2005000, 'wal_compression', 'disabled');
        INSERT INTO pem.bart_server_default_config VALUES (48, 2005000, 'copy_wals_during_restore', 'disabled');
        INSERT INTO pem.bart_server_default_config VALUES (49, 2005000, 'allow_incremental_backups', 'disabled');
        INSERT INTO pem.bart_server_default_config VALUES (50, 2005000, 'thread_count', '1');
        INSERT INTO pem.bart_server_default_config VALUES (51, 2005000, 'description');
        INSERT INTO pem.bart_server_default_config VALUES (52, 2005000, 'batch_size', '49142');
        INSERT INTO pem.bart_server_default_config VALUES (53, 2005000, 'scan_interval', '1');
        INSERT INTO pem.bart_server_default_config VALUES (54, 2005000, 'mbm_scan_timeout', '20');
        INSERT INTO pem.bart_server_default_config VALUES (55, 2005000, 'workers', '1');
        INSERT INTO pem.bart_server_default_config VALUES (56, 2005000, 'archive_path');
    END IF;

END;
$DO$ LANGUAGE 'plpgsql';

END TRANSACTION;
