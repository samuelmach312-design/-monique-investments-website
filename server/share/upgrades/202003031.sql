/***************************************************************************
 *
 * Postgres Enterprise Manager
 *
 * Copyright (C) 2010 - 2025, EnterpriseDB Corporation. All rights reserved.
 *
 ***************************************************************************/

-- NOTE: This sql file is responsible for PEM 7.14 schema upgrade.

BEGIN TRANSACTION;

CREATE OR REPLACE FUNCTION pem.schema_version()
  RETURNS integer AS
'SELECT 202003031::integer;'
  LANGUAGE 'sql' IMMUTABLE;
COMMENT ON FUNCTION pem.schema_version() IS 'Returns the version number of the PEM schema';

CREATE OR REPLACE FUNCTION pem.next_schedule(
    int4, timestamptz, timestamptz, _bool, _bool, _bool, _bool, _bool
) RETURNS timestamptz AS
$FUNC$
DECLARE
    jscid           ALIAS FOR $1;
    jscstart        ALIAS FOR $2;
    jscend          ALIAS FOR $3;
    jscminutes      ALIAS FOR $4;
    jschours        ALIAS FOR $5;
    jscweekdays     ALIAS FOR $6;
    jscmonthdays    ALIAS FOR $7;
    jscmonths       ALIAS FOR $8;

    nextrun         timestamptz := '1970-01-01 00:00:00-00';
    runafter        timestamp := '1970-01-01 00:00:00-00';

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
    IF date_trunc('MINUTE', jscstart) > date_trunc('MINUTE', (now() + '1 Minute'::interval)) THEN
        runafter := date_trunc('MINUTE', jscstart);
    ELSE
        runafter := date_trunc('MINUTE', (now() + '1 Minute'::interval));
    END IF;

    --
    -- Enter a loop, generating next run timestamps until we find one
    -- that falls on the required weekday, and is not matched by an exception
    --
    WHILE bingo = FALSE LOOP

        --
        -- Get the next run year
        --
        nextyear := date_part('YEAR', runafter);

        --
        -- Get the next run month
        --
        nextmonth := date_part('MONTH', runafter);
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
        IF (nextyear > date_part('YEAR', runafter) OR nextmonth > date_part('MONTH', runafter)) THEN
            nextday := 1;
            FOR i IN 1 .. 32 LOOP
                IF jscmonthdays[i] = TRUE THEN
                    nextday := i;
                    foundval := TRUE;
                    EXIT;
                END IF;
            END LOOP;
        ELSE
            nextday := date_part('DAY', runafter);
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
        IF (nextyear > date_part('YEAR', runafter) OR nextmonth > date_part('MONTH', runafter) OR nextday > date_part('DAY', runafter) OR daytweak = TRUE) THEN
            nexthour := 0;
            FOR i IN 1 .. 24 LOOP
                IF jschours[i] = TRUE THEN
                    nexthour := i - 1;
                    foundval := TRUE;
                    EXIT;
                END IF;
            END LOOP;
        ELSE
            nexthour := date_part('HOUR', runafter);
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
        IF (nextyear > date_part('YEAR', runafter) OR nextmonth > date_part('MONTH', runafter) OR nextday > date_part('DAY', runafter) OR nexthour > date_part('HOUR', runafter) OR daytweak = TRUE) THEN
            nextminute := 0;
            IF minutetweak = TRUE THEN
        d := 1;
            ELSE
        d := date_part('YEAR', runafter)::int2;
            END IF;
            FOR i IN d .. 60 LOOP
                IF jscminutes[i] = TRUE THEN
                    nextminute := i - 1;
                    foundval := TRUE;
                    EXIT;
                END IF;
            END LOOP;
        ELSE
            nextminute := date_part('MINUTE', runafter);
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

        nextrun := (nextyear::varchar || '-'::varchar || nextmonth::varchar || '-' || nextday::varchar || ' ' || nexthour::varchar || ':' || nextminute::varchar)::timestamptz;

        IF nextrun = runafter AND foundval = FALSE THEN
                nextrun := nextrun + INTERVAL '1 Minute';
        END IF;

        -- If the result is past the end date, exit.
        IF nextrun > jscend THEN
            RETURN NULL;
        END IF;

        -- Check to ensure that the nextrun time is actually still valid. Its
        -- possible that wrapped values may have carried the nextrun onto an
        -- invalid time or date.
        IF ((jscminutes = '{f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f}' OR jscminutes[date_part('MINUTE', nextrun) + 1] = TRUE) AND
            (jschours = '{f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f}' OR jschours[date_part('HOUR', nextrun) + 1] = TRUE) AND
            (jscmonthdays = '{f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f}' OR jscmonthdays[date_part('DAY', nextrun)] = TRUE OR
            (jscmonthdays = '{f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,t}' AND
             ((date_part('MONTH', nextrun) IN (1,3,5,7,8,10,12) AND date_part('DAY', nextrun) = 31) OR
              (date_part('MONTH', nextrun) IN (4,6,9,11) AND date_part('DAY', nextrun) = 30) OR
              (date_part('MONTH', nextrun) = 2 AND ((pem.is_leap_year(date_part('YEAR', nextrun)::int2) AND date_part('DAY', nextrun) = 29) OR date_part('DAY', nextrun) = 28))))) AND
            (jscmonths = '{f,f,f,f,f,f,f,f,f,f,f,f}' OR jscmonths[date_part('MONTH', nextrun)] = TRUE)) THEN

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
            IF (jscweekdays[date_part('DOW', nextrun) + 1] = TRUE OR gotit = FALSE) THEN

                -- Check for exceptions
                SELECT INTO d jexid FROM pem.exception WHERE jexscid = jscid AND ((jexdate = nextrun::date AND jextime = nextrun::time) OR (jexdate = nextrun::date AND jextime IS NULL) OR (jexdate IS NULL AND jextime = nextrun::time));
                IF FOUND THEN
                    -- Nuts - found an exception. Increment the time and try again
                    runafter := nextrun + INTERVAL '1 Minute';
                    bingo := FALSE;
                    minutetweak := TRUE;
            daytweak := FALSE;
                ELSE
                    bingo := TRUE;
                END IF;
            ELSE
                -- We're on the wrong week day - increment a day and try again.
                runafter := nextrun + INTERVAL '1 Day';
                bingo := FALSE;
                minutetweak := FALSE;
                daytweak := TRUE;
            END IF;

        ELSE
            runafter := nextrun + INTERVAL '1 Minute';
            bingo := FALSE;
            minutetweak := TRUE;
        daytweak := FALSE;
        END IF;

    END LOOP;

    RETURN nextrun;
END;
$FUNC$
LANGUAGE 'plpgsql' VOLATILE;

-- PEM-3192 - Update pem.bart_backups table with primary key as server id and backup id ( Case #972254 )
DO $FUNC$
DECLARE
  primary_key_name text;
BEGIN
    -- First find the name of the primary key and drop that constraint and recreate it.
    SELECT constraint_name INTO primary_key_name FROM information_schema.table_constraints WHERE constraint_type = 'PRIMARY KEY' AND table_schema = 'pem' AND table_name = 'bart_backups';

    IF primary_key_name IS NOT NULL AND primary_key_name != '' THEN
        EXECUTE 'ALTER TABLE pem.bart_backups DROP CONSTRAINT IF EXISTS ' || primary_key_name;
        EXECUTE 'ALTER TABLE pem.bart_backups ADD CONSTRAINT bart_backups_pkey PRIMARY KEY (id, server_id)';
    END IF;

END;
$FUNC$ LANGUAGE 'plpgsql';

-- PEM-3176
-- Remove PEM schema for Package Deployment and Streaming Replication module

DO $FUNC$
BEGIN
    IF EXISTS (
        SELECT 1 FROM pg_catalog.pg_roles AS t
        WHERE t.rolname = 'pem_comp_package_deployment'
    ) THEN
        RAISE INFO 'Revoke permissions from objects for pem_comp_package_deployment role';
        REVOKE ALL ON TABLE pem.schedule FROM pem_comp_package_deployment;
        REVOKE ALL ON TABLE pem.job FROM pem_comp_package_deployment;
        REVOKE ALL ON TABLE pem.jobstep FROM pem_comp_package_deployment;
        REVOKE DELETE ON TABLE pem.probe_schedule FROM pem_comp_package_deployment;
        REVOKE INSERT, DELETE ON TABLE pem.package_options FROM pem_comp_package_deployment;
        REVOKE UPDATE, INSERT ON TABLE pem.package_installation FROM pem_comp_package_deployment;
        REVOKE UPDATE ON TABLE pemdata.package_catalog FROM pem_comp_package_deployment;
    END IF;

    IF EXISTS (
        SELECT 1 FROM pg_catalog.pg_roles AS t
        WHERE t.rolname = 'pem_comp_streaming_replication'
    ) THEN
        RAISE INFO 'Revoke permissions from objects for pem_comp_streaming_replication role';
        REVOKE ALL ON TABLE pem.schedule FROM pem_comp_streaming_replication;
        REVOKE ALL ON TABLE pem.job FROM pem_comp_streaming_replication;
        REVOKE ALL ON TABLE pem.jobstep FROM pem_comp_streaming_replication;
        REVOKE DELETE ON TABLE pem.probe_schedule FROM pem_comp_streaming_replication;
        REVOKE INSERT, DELETE ON TABLE pem.sr_standby FROM pem_comp_streaming_replication;
        REVOKE UPDATE, INSERT ON TABLE pem.sr_master FROM pem_comp_streaming_replication;
        REVOKE UPDATE ON TABLE pemdata.package_catalog FROM pem_comp_streaming_replication;
        REVOKE UPDATE ON TABLE pem.package_options FROM pem_comp_streaming_replication;
        REVOKE UPDATE ON TABLE pem.package_installation FROM pem_comp_streaming_replication;

        REVOKE SELECT, INSERT, UPDATE, DELETE ON TABLE pem.sr_existing_replication FROM pem_agent;
        REVOKE ALL ON pem.sr_existing_replication_id_seq FROM pem_agent;
    END IF;
END;
$FUNC$ LANGUAGE 'plpgsql';

-- Config options
DELETE FROM pem.config
WHERE param IN (
    'package_catalog_xml', 'package_download_chunk_size',
    'proxy_server_enabled', 'proxy_server', 'proxy_server_port', 'proxy_server_authentication',
    'proxy_server_username', 'proxy_server_password'
);

-- Remove type
DROP TYPE IF EXISTS pem.pkg_download_state CASCADE;
DROP TYPE IF EXISTS pem.pkg_installed_state CASCADE;

-- Remove table
DROP TABLE IF EXISTS pem.package_installation CASCADE;
DROP TABLE IF EXISTS pem.package_options CASCADE;
DROP TABLE IF EXISTS pemdata.installed_packages CASCADE;
DROP TABLE IF EXISTS pemdata.package_catalog CASCADE;

DROP TABLE IF EXISTS  pem.sr_existing_replication CASCADE;
DROP TABLE IF EXISTS  pem.sr_master CASCADE;
DROP TABLE IF EXISTS pem.sr_standby CASCADE;

-- Remove roles
DROP ROLE IF EXISTS pem_comp_streaming_replication;
DROP ROLE IF EXISTS pem_comp_package_deployment;

DROP FUNCTION IF EXISTS pem.get_mismatch_packages_list(agentid integer);
DROP FUNCTION IF EXISTS pem.reschedule_installed_package_probe();

-- Remove alert and alert template for package deployment
DELETE FROM pem.alert WHERE name = 'Package version mismatch';
DELETE FROM pem.alert_template WHERE display_name = 'Package version mismatch';

-- Remove package catalog and installed packages probe
DELETE FROM pem.probe WHERE internal_name = 'package_catalog';
DELETE FROM pem.probe WHERE internal_name = 'installed_packages';

DELETE FROM pem.probe_column WHERE internal_name = 'package_catalog';
DELETE FROM pem.probe_column WHERE internal_name = 'installed_packages';

-- JIRA: PEM-3122

-- Remove default constraint for background color and set the server color to null
-- so that it works in both dark & light themes
ALTER TABLE pem.server_options
    ALTER COLUMN server_colour
    DROP NOT NULL;

ALTER TABLE pem.server_options
    ALTER COLUMN server_colour
    DROP DEFAULT;

-- Here we are assuming that if background color is default then
-- user had not changed it, we will set it to null for all existing servers
UPDATE pem.server_options
    SET server_colour = NULL
WHERE server_colour = '#FFFFFF';

-- Jira: PEM-3117
-- Change the default color for Agent/server status
-- Jira: PEM-1593
-- Introduced color for Agents Unmanaged

UPDATE pem.bar_chart SET colors = ARRAY[
    '#23D347', '#ED3624', '#646464', '#23D347', '#ED3624', '#646464', '#DDDDDD'
    ]
WHERE cid = 1;

-- Jira: PEM-1593
-- Introducing a config option to decide - show/hide the unmanaged servers
-- (Default: true)
DO $FUNC$
DECLARE
    config_present bool;
BEGIN
    config_present := EXISTS(
        SELECT 1 FROM pem.config WHERE param = 'show_unmanaged_servers'
    );
    IF NOT config_present THEN
        INSERT INTO pem.config (param, value, unit, datatype) VALUES (
            'show_unmanaged_servers', 't', 't/f', 'bool'
        );
    END IF;
END;
$FUNC$
LANGUAGE 'plpgsql';

-- Update the barchart code of global overview to show the unmanaged servers
-- separately from 'Unknown' servers.
UPDATE pem.chart_func SET func = $QUERY$
WITH agent_list AS (
	SELECT
		pa.id AS id, pa.active AS active, pah.agent_id, pah.last_heartbeat, pa.heartbeat_interval
	FROM
		pem.avail_agents pa
		LEFT OUTER JOIN pem.agent_heartbeat pah ON (pa.id = pah.agent_id)
),
server_list AS (
	SELECT
		ps.id AS server_id, psh.last_heartbeat AS server_last_heartbeat,
		pa.active AS agent_active, pah.last_heartbeat AS agent_last_heartbeat,
		pa.heartbeat_interval AS heartbeat_interval
	FROM
		pem.avail_servers ps
		LEFT OUTER JOIN pem.server_heartbeat psh ON (ps.id = psh.server_id)
		LEFT OUTER JOIN pem.agent_server_binding pasb ON (ps.id = pasb.server_id)
		LEFT OUTER JOIN pem.avail_agents pa ON (pasb.agent_id = pa.id AND psh.agent_id = pa.id)
		LEFT OUTER JOIN pem.agent_heartbeat pah ON (pah.agent_id = pasb.agent_id)
)
SELECT
	id,
	label,
	count
FROM
	(
		SELECT
			1::int AS id, 'Agents Up'::text AS label, true::bool AS required, count(id)::int8 AS count
		FROM
			agent_list
		WHERE
			active = TRUE AND
			agent_id IS NOT NULL AND
			last_heartbeat < now() AND
			last_heartbeat > (now() - (heartbeat_interval * 2 * '1 second'::interval))
		UNION
		SELECT
			2::int AS id, 'Agents Down'::text AS label, true::bool AS required, count(id)::int8 AS count
		FROM
			agent_list
		WHERE
			active = TRUE AND
			agent_id IS NOT NULL AND
			last_heartbeat < (now() - (heartbeat_interval * 2 * '1 second'::interval))
		UNION
		SELECT
			3::int AS id, 'Agents Unknown'::text AS label, false::bool AS required, count(id)::int8 AS count
		FROM
			agent_list
		WHERE
			active = TRUE AND
			agent_id IS NULL
		UNION
		SELECT
			4::int AS id, 'Servers Up'::text AS label, true::bool AS required, count(server_id)::int8 AS count
		FROM
			server_list
		WHERE
			agent_active IS NOT NULL AND agent_active AND
			server_last_heartbeat IS NOT NULL AND
			server_last_heartbeat < now() AND
			server_last_heartbeat > (now() - (heartbeat_interval * 2 * '1 second'::interval))
		UNION
		SELECT
			5::int AS id, 'Servers Down'::text AS label, true::bool AS required, count(server_id)::int8 AS count
		FROM
			server_list
		WHERE
			agent_active IS NOT NULL AND agent_active AND
			agent_last_heartbeat IS NOT NULL AND
			agent_last_heartbeat < now() AND
			agent_last_heartbeat > (now() - (heartbeat_interval * 2 * '1 second'::interval)) AND
			server_last_heartbeat IS NOT NULL AND
			server_last_heartbeat < (now() - (heartbeat_interval * 2 * '1 second'::interval))
		UNION
		SELECT
			6::int AS id, 'Servers Unknown'::text AS label, false::bool AS required, count(server_id)::int8 AS count
		FROM
			server_list
		WHERE
			(agent_active AND
				-- The agent is bound, but never got an heartbeat from it
				(agent_last_heartbeat IS NULL OR
					-- The agent is not properly bound with the server
					-- (Agent may not have proper authentication for connection)
					server_last_heartbeat IS NULL OR
					-- Agent is down for some reason
					agent_last_heartbeat < (now() - (heartbeat_interval * 2 * '1 second'::interval))))
		UNION
		SELECT id, label, required, count
		FROM (
			SELECT
				7::int AS id, 'Unmanaged Servers'::text AS label, false::bool AS required, count(server_id)::int8 AS count
			FROM server_list
			WHERE agent_active is NULL
		) d
		LEFT JOIN (
			SELECT value FROM pem.config WHERE param = 'show_unmanaged_servers'
		) c ON c.value = 'f'
		WHERE c.value IS NULL
	) AS global_pem_status
WHERE required OR count > 0
ORDER BY id
$QUERY$ WHERE id = 1;

-- Update in the lables of the global overview (bar chart)
UPDATE pem.chart SET labels = ARRAY[
    'Agents Up', 'Agents Down', 'Agents Unknown', 'Servers Up', 'Servers Down',
    'Servers Unknown', 'Unmanaged Servers'
    ]
WHERE id = 1;

-- JIRA: PEM-3174
-- agent_config to store Agent configuration.
DO $FUNC$
BEGIN
    IF NOT EXISTS(
        SELECT 1 FROM pg_class c JOIN pg_catalog.pg_namespace n ON n.oid = c.relnamespace
           WHERE c.relkind = 'r' AND n.nspname = 'pem' AND c.relname = 'agent_config'
    ) THEN
        CREATE TABLE pem.agent_config (
            id                              SERIAL NOT NULL,
            agent_id                        integer NOT NULL,
            param                           text NOT NULL,
            value                           text,
            label                           text NOT NULL,
            category                        text NOT NULL,
            CONSTRAINT agent_config_pkey PRIMARY KEY (id),
            CONSTRAINT agent_config_agent_id_fkey FOREIGN KEY (agent_id)
            REFERENCES pem.agent (id) ON DELETE CASCADE ON UPDATE RESTRICT
        );

        COMMENT ON TABLE pem.agent_config IS
            'Used to store configuration of pemagent';
        COMMENT ON COLUMN pem.agent_config.id IS 'Used to store id';
        COMMENT ON COLUMN pem.agent_config.agent_id IS
            'Used to store agent id of pemagent';
        COMMENT ON COLUMN pem.agent_config.label IS
            'Used to store readable label for parameter from agent.cfg';
        COMMENT ON COLUMN pem.agent_config.param IS
            'Used to store parameter name from agent.cfg';
        COMMENT ON COLUMN pem.agent_config.category IS
            'Used to store parameter category';
        COMMENT ON COLUMN pem.agent_config.value IS
            'Used to store parameter value from agent.cfg';

        GRANT INSERT, UPDATE, DELETE ON TABLE pem.agent_config TO pem_agent;
        GRANT USAGE ON SEQUENCE pem.agent_config_id_seq TO pem_agent;
    END IF;
END
$FUNC$ LANGUAGE 'plpgsql';

DO $FUNC$
DECLARE
    ver int := pem.parse_version_string(version());
    pem_access_function text;
BEGIN
    IF ver <= 10904 OR (ver > 20000 AND ver <= 20904) THEN
        RAISE INFO 'pem.can_access_team() function#1 for %', ver;
        pem_access_function := $SQL$
CREATE OR REPLACE FUNCTION pem.can_access_team(_owner OID, _team text)
RETURNS boolean AS
$$
     SELECT
         -- team is not defined
         _team IS NULL OR _team = '' OR
         -- current user is the owner
         _owner = (SELECT o.usesysid FROM pg_catalog.pg_user AS o WHERE o.usename = current_user) OR
         -- current user is pem_super_admin
         pg_catalog.pg_has_role('pem_super_admin', 'member') OR
         -- team role exists and current user is a member of the team
         CASE WHEN EXISTS (
             SELECT 1 FROM pg_catalog.pg_roles AS t WHERE t.rolname = _team
         ) THEN pg_catalog.pg_has_role(_team, 'member')
         ELSE false
         END;
$$ LANGUAGE 'sql';$SQL$;
    ELSE
        RAISE INFO 'pem.can_access_team() function#2 for %', ver;
        pem_access_function := $SQL$
CREATE OR REPLACE FUNCTION pem.can_access_team(_owner OID, _team text)
RETURNS boolean AS
$$
     SELECT
         -- team is not defined
         _team IS NULL OR _team = '' OR
         -- current user is the owner
         _owner = current_user::regrole::oid OR
         -- current user is pem_super_admin
         pg_catalog.pg_has_role('pem_super_admin', 'member') OR
         -- team role exists and current user is a member of the team
         CASE WHEN EXISTS (
             SELECT 1 FROM pg_catalog.pg_roles AS t WHERE t.rolname = _team
         ) THEN pg_catalog.pg_has_role(_team, 'member')
         ELSE false
         END;
$$ LANGUAGE 'sql';$SQL$;
    END IF;
    EXECUTE pem_access_function;
END;
$FUNC$ LANGUAGE 'plpgsql';

CREATE OR REPLACE FUNCTION pem.can_access_server(_server_id int)
 RETURNS boolean AS
 $$
    SELECT EXISTS (SELECT 1 FROM pem.server WHERE id = _server_id);
$$ language 'sql';

DO $FUNC$
BEGIN
    IF NOT EXISTS(
        SELECT 1
        FROM pg_class t,
             pg_class i,
             pg_index ix,
             pg_attribute a
        WHERE t.oid = ix.indrelid
            AND t.relkind = 'r'
            AND t.relname LIKE 'probe_schedule'
            AND t.relnamespace = (
                SELECT oid FROM pg_namespace WHERE nspname = 'pem'
            )
            AND i.oid = ix.indexrelid
            AND a.attname = 'agent_id'
            AND a.attrelid = t.oid
            AND a.attnum::text = ix.indkey::text
    ) THEN
        CREATE INDEX probe_schedule_agent_id_idx
            ON pem.probe_schedule (agent_id);
    END IF;
END;
$FUNC$ LANGUAGE 'plpgsql';

GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE pem.jobagent TO pem_agent;

-- Below changes are required for RM#2813 where we are allowing user to save
-- blank password
DO $FUNC$
BEGIN
    IF NOT EXISTS(
        SELECT 1 FROM information_schema.columns
            WHERE table_name='server_auth' AND column_name = 'save_password'
            AND table_schema = 'pem' AND table_catalog = 'pem'
    ) THEN
        ALTER TABLE pem.server_auth
            ADD COLUMN save_password boolean NOT NULL DEFAULT false;

        -- Update the flag as per current password status
        UPDATE pem.server_auth SET save_password = (
            CASE WHEN password IS NOT NULL AND password != '' THEN
                True
            ELSE
                False
            END
        );

        COMMENT ON COLUMN pem.server_auth.save_password IS 'The Server password saved flag';
    END IF;

END
$FUNC$ LANGUAGE 'plpgsql';

CREATE OR REPLACE FUNCTION pem.purge_server_log()
RETURNS void AS $$
	-- Purge data from server log table
    DELETE FROM pemdata.server_logs
    WHERE log_time <= now() - (SELECT (value || ' ' || unit)::interval FROM pem.config WHERE param = 'server_log_retention_time');
$$ LANGUAGE sql SECURITY DEFINER;

REVOKE ALL ON FUNCTION pem.purge_server_log() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION pem.purge_server_log() TO pem_agent;

-- Update the blocked_session_info probe code for PG 9.6 onwards
UPDATE pem.probe_server_version
SET probe_code = $SQL$
	SELECT blocked_activity.pid                     AS blocked_pid,
                blocked_activity.usename                 AS blocked_user,
                blocked.mode                             AS locktype,
                blocking_activity.pid                    AS blocking_pid,
                blocking_activity.usename                AS blocking_user,
                blocking_activity.datname                AS database_name,
                now() - blocking_activity.query_start    AS blocking_duration,
                now() - blocked_activity.query_start     AS blocked_duration,
                blocking_activity.query_start            AS blocking_query_start,
                blocked_activity.query_start             AS blocked_query_start,
                blocked_activity.query                   AS blocked_statement,
                blocking_activity.query                  AS current_statement_in_blocking_process,
                blocked_activity.application_name        AS blocked_application,
                blocking_activity.application_name       AS blocking_application
        FROM pg_catalog.pg_stat_activity AS blocked_activity
        JOIN pg_catalog.pg_stat_activity AS blocking_activity ON blocking_activity.pid = ANY (pg_blocking_pids(blocked_activity.pid))
        JOIN pg_catalog.pg_locks AS blocked ON blocked.pid = blocked_activity.pid
        WHERE NOT blocked.granted$SQL$
WHERE probe_id = (
        SELECT p.id FROM pem.probe p WHERE p.internal_name = 'blocked_session_info'
    ) AND server_version_id IN (10906, 20906, 11000, 11100, 11200, 21000, 21100, 21200);


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
                SELECT INTO d jexid FROM pem.exception WHERE jexscid = jscid AND ((jexdate = nextrun::date AND jextime = nextrun::time) OR (jexdate = nextrun::date AND jextime IS NULL) OR (jexdate IS NULL AND jextime = nextrun::time));
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
COMMENT ON FUNCTION pem.next_schedule(int4, timestamptz, timestamptz, _bool, _bool, _bool, _bool, _bool) IS 'Calculates the next runtime for a given schedule';

END TRANSACTION;
