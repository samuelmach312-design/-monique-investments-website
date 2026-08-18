/***************************************************************************
 *
 * Postgres Enterprise Manager
 *
 * Copyright (C) 2010 - 2025, EnterpriseDB Corporation. All rights reserved.
 *
 ***************************************************************************/

-- NOTE: This sql file is responsible for PEM 10.2.0 schema upgrade.

BEGIN TRANSACTION;
    CREATE
    OR REPLACE FUNCTION pem.schema_version()
    RETURNS integer AS 'SELECT 202508141::integer;' LANGUAGE 'sql' IMMUTABLE;
    COMMENT ON FUNCTION pem.schema_version()
    IS 'Returns the version number of the PEM schema';

    --PEM-4916: Rename 'heartbeat interval' to 'heartbeat tolerance'
    DO
    $$
    BEGIN
        IF EXISTS (
            SELECT 1
            FROM
                information_schema.columns
            WHERE
                table_schema = 'pem' AND
                table_name   = 'agent' AND
                column_name = 'heartbeat_interval'
        ) THEN
            ALTER TABLE pem.agent RENAME COLUMN heartbeat_interval TO heartbeat_tolerance;
            COMMENT ON COLUMN pem.agent.heartbeat_tolerance IS 'The interval before heartbeat is considered missed, in seconds';
            ALTER TABLE pem.agent ALTER COLUMN heartbeat_tolerance SET DEFAULT 15;
            UPDATE pem.agent SET heartbeat_tolerance = (heartbeat_tolerance * 2) - 15;
        END IF;
    END;
    $$ LANGUAGE 'plpgsql';

    DO
    $$
    BEGIN
        IF EXISTS (
            SELECT 1
            FROM
                information_schema.columns
            WHERE
                table_schema = 'pem' AND
                table_name   = 'avail_agents' AND
                column_name = 'heartbeat_interval'
        ) THEN
            ALTER TABLE pem.avail_agents RENAME COLUMN heartbeat_interval TO heartbeat_tolerance;
        END IF;
    END;
    $$ LANGUAGE 'plpgsql';

    UPDATE pem.alert_template
    SET
    sql=$sql$
        SELECT
            count(pa.id)
        FROM
            pem.agent pa LEFT OUTER JOIN pem.agent_heartbeat pah ON (pa.id = pah.agent_id)
        WHERE
            pa.active = TRUE AND
            NOT pa.alert_blackout AND
            CASE WHEN pah.agent_id IS NULL THEN FALSE ELSE pah.last_heartbeat < now() - (pa.heartbeat_tolerance+15)*'1 second'::interval END$sql$
    WHERE display_name = 'Agents Down';

    UPDATE pem.alert_template
    SET
    sql=$sql$
        SELECT
            count(ps.id)
        FROM
            pem.server ps LEFT OUTER JOIN pem.server_heartbeat psh ON (ps.id = psh.server_id),
            pem.agent pa LEFT OUTER JOIN pem.agent_heartbeat pah ON (pa.id = pah.agent_id),
            pem.agent_server_binding pasb
        WHERE
            pa.id = pasb.agent_id AND
            ps.id = pasb.server_id AND
            pa.active = TRUE AND
            ps.active = TRUE AND
            NOT ps.alert_blackout AND
            CASE WHEN psh.agent_id IS NULL THEN FALSE ELSE psh.agent_id = pa.id END AND
                CASE WHEN psh.server_id IS NULL THEN FALSE ELSE psh.last_heartbeat < now() - (pa.heartbeat_tolerance+15)*'1 second'::interval END$sql$
    WHERE display_name = 'Servers Down';

    UPDATE pem.alert_template
    SET
    sql=$sql$
        SELECT
            count(pa.id) AS current_value,
            CASE WHEN count(pa.id) = 0 THEN 'UP' ELSE 'DOWN' END display_value
        FROM
            pem.agent pa LEFT OUTER JOIN pem.agent_heartbeat pah ON (pa.id = pah.agent_id)
        WHERE
            pa.id = ${agent_id} AND
            pa.active = TRUE AND
            NOT pa.alert_blackout AND
            CASE WHEN pah.agent_id IS NULL THEN FALSE ELSE pah.last_heartbeat < now() - (pa.heartbeat_tolerance+15)*'1 second'::interval END$sql$,
    info_sql=$SQL$
        SELECT pa.description AS "Agent description",pa.platform AS "Agent platform", pah.last_heartbeat AS "Down since", pa.heartbeat_tolerance AS "Hearbeat tolerance"
        FROM
            pem.agent pa LEFT OUTER JOIN pem.agent_heartbeat pah ON (pa.id = pah.agent_id)
        WHERE
            pa.id = '${agent_id}' AND
            pa.active = TRUE AND
            NOT pa.alert_blackout AND
            CASE WHEN pah.agent_id IS NULL THEN FALSE ELSE pah.last_heartbeat < now() - (pa.heartbeat_tolerance+15)*'1 second'::interval END;$SQL$
    WHERE display_name = 'Agent Down';

    UPDATE pem.alert_template
    SET
    sql=$sql$
        SELECT
            count(ps.id),
            CASE WHEN count(pa.id) = 0 THEN 'UP' ELSE 'DOWN' END display_value
        FROM
            pem.server ps LEFT OUTER JOIN pem.server_heartbeat psh ON (ps.id = psh.server_id),
            pem.agent pa LEFT OUTER JOIN pem.agent_heartbeat pah ON (pa.id = pah.agent_id),
            pem.agent_server_binding pasb
        WHERE
            ps.id = ${server_id} AND
            pa.id = pasb.agent_id AND
            ps.id = pasb.server_id AND
            pa.active = TRUE AND
            ps.active = TRUE AND
            NOT ps.alert_blackout AND
            CASE WHEN psh.agent_id IS NULL THEN FALSE ELSE psh.agent_id = pa.id END AND
            CASE WHEN psh.server_id IS NULL THEN FALSE ELSE psh.last_heartbeat < now() - (pa.heartbeat_tolerance+15)*'1 second'::interval END$sql$,
    info_sql=$SQL$
        SELECT ps.description AS "Server description", ps.server AS "IP address", ps.port AS "Server port", ps.serviceid AS "Service ID",
           psh.last_heartbeat AS "Down since", CASE WHEN ps.is_remote_monitoring = false THEN 'False' ELSE 'True' END AS "Remote monitoring?"
        FROM
           pem.server ps LEFT OUTER JOIN pem.server_heartbeat psh ON (ps.id = psh.server_id),
           pem.agent pa LEFT OUTER JOIN pem.agent_heartbeat pah ON (pa.id = pah.agent_id),
           pem.agent_server_binding pasb
        WHERE
           ps.id = '${server_id}' AND
           pa.id = pasb.agent_id AND
           ps.id = pasb.server_id AND
           pa.active = TRUE AND
           ps.active = TRUE AND
           NOT ps.alert_blackout AND
           CASE WHEN psh.agent_id IS NULL THEN FALSE ELSE psh.agent_id = pa.id END AND
           CASE WHEN psh.server_id IS NULL THEN FALSE ELSE psh.last_heartbeat < now() - (pa.heartbeat_tolerance+15)*'1 second'::interval END;$SQL$
    WHERE display_name = 'Server Down';

    CREATE OR REPLACE FUNCTION pem.get_servers_with_status(server_state pem.server_agent_state) RETURNS SETOF RECORD
    AS $$
    DECLARE
        row  RECORD;
        sql  text;
    BEGIN

        IF (server_state = 'UP') THEN
            sql =  'SELECT ps.id, ps.description, ps.server, ps.port
                    FROM
                        pem.avail_servers ps LEFT OUTER JOIN pem.server_heartbeat psh ON (ps.id = psh.server_id),
                        pem.agent pa,
                        pem.agent_server_binding pasb
                    WHERE
                        pa.id = pasb.agent_id AND
                        ps.id = pasb.server_id AND
                        NOT ps.alert_blackout AND
                        CASE WHEN psh.agent_id IS NULL THEN FALSE ELSE psh.agent_id = pa.id END AND
                        CASE WHEN psh.server_id IS NULL THEN FALSE ELSE psh.last_heartbeat < now() AND psh.last_heartbeat > now() - (pa.heartbeat_tolerance+15)*''1 second''::interval END';
        ELSIF (server_state = 'DOWN') THEN
            sql =  'SELECT ps.id, ps.description, ps.server, ps.port
                    FROM
                        pem.avail_servers ps LEFT OUTER JOIN pem.server_heartbeat psh ON (ps.id = psh.server_id),
                        pem.agent pa LEFT OUTER JOIN pem.agent_heartbeat pah ON (pa.id = pah.agent_id),
                        pem.agent_server_binding pasb
                    WHERE
                        pa.id = pasb.agent_id AND
                        ps.id = pasb.server_id AND
                        pa.active = TRUE AND
                        NOT ps.alert_blackout AND
                        CASE WHEN psh.agent_id IS NULL THEN FALSE ELSE psh.agent_id = pa.id END AND
                        CASE WHEN pah.agent_id is NULL THEN FALSE ELSE pah.last_heartbeat < now() AND pah.last_heartbeat > now() - (pa.heartbeat_tolerance+15)*''1 second''::interval END AND
                        CASE WHEN psh.server_id IS NULL THEN FALSE ELSE psh.last_heartbeat < now() - (pa.heartbeat_tolerance+15)*''1 second''::interval END';
        ELSIF (server_state = 'UNKNOWN') THEN
            sql =  'SELECT ps.id, ps.description, ps.server, ps.port
                    FROM
                        pem.avail_servers ps LEFT OUTER JOIN pem.server_heartbeat psh ON (ps.id = psh.server_id),
                        pem.agent pa LEFT OUTER JOIN pem.agent_heartbeat pah ON (pa.id = pah.agent_id),
                        pem.agent_server_binding pasb
                    WHERE
                        pa.id = pasb.agent_id AND
                        ps.id = pasb.server_id AND
                        pa.active = TRUE AND
                        NOT ps.alert_blackout AND
                        ((pah.agent_id IS NULL) OR
                        (pah.last_heartbeat < now() - (pa.heartbeat_tolerance+15)*''1 second''::interval) OR
                        (psh.server_id IS NULL))';
        ELSIF (server_state = 'BLACKEDOUT') THEN
            sql =  'SELECT ps.id, ps.description, ps.server, ps.port
                    FROM
                        pem.avail_servers ps LEFT OUTER JOIN pem.server_heartbeat psh ON (ps.id = psh.server_id),
                        pem.agent pa,
                        pem.agent_server_binding pasb
                    WHERE
                        pa.id = pasb.agent_id AND
                        ps.id = pasb.server_id AND
                        ps.alert_blackout AND
                        CASE WHEN psh.agent_id IS NULL THEN FALSE ELSE psh.agent_id = pa.id END AND
                        CASE WHEN psh.server_id IS NULL THEN FALSE ELSE psh.last_heartbeat < now() AND psh.last_heartbeat > now() - (pa.heartbeat_tolerance+15)*''1 second''::interval END';
        END IF;

        FOR row IN EXECUTE sql
        LOOP
            RETURN NEXT row;
        END LOOP;

        RETURN;
    END;
    $$ LANGUAGE plpgsql;

    CREATE OR REPLACE FUNCTION pem.get_agents_with_status(agent_state pem.server_agent_state) RETURNS SETOF RECORD
    AS $$
    DECLARE
        row  RECORD;
        sql  text;
    BEGIN

        IF (agent_state = 'UP') THEN
            sql =  'SELECT pa.id, pa.description
                    FROM
                        pem.agent pa LEFT OUTER JOIN pem.agent_heartbeat pah ON (pa.id = pah.agent_id)
                    WHERE
                        pa.active = TRUE AND
                        NOT pa.alert_blackout AND
                        CASE WHEN pah.agent_id IS NULL THEN FALSE ELSE pah.last_heartbeat < now() AND pah.last_heartbeat > now() - (pa.heartbeat_tolerance+15)*''1 second''::interval END';
        ELSIF (agent_state = 'DOWN') THEN
            sql =  'SELECT pa.id, pa.description
                    FROM
                        pem.agent pa LEFT OUTER JOIN pem.agent_heartbeat pah ON (pa.id = pah.agent_id)
                    WHERE
                        pa.active = TRUE AND
                        NOT pa.alert_blackout AND
                        CASE WHEN pah.agent_id IS NULL THEN FALSE ELSE pah.last_heartbeat < now() - (pa.heartbeat_tolerance+15)*''1 second''::interval END';
        ELSIF (agent_state = 'UNKNOWN') THEN
            sql =  'SELECT pa.id, pa.description
                    FROM
                        pem.agent pa LEFT OUTER JOIN pem.agent_heartbeat pah ON (pa.id = pah.agent_id)
                    WHERE
                        pa.active = TRUE AND
                        NOT pa.alert_blackout AND
                        pah.agent_id IS NULL';
        ELSIF (agent_state = 'BLACKEDOUT') THEN
            sql =  'SELECT pa.id, pa.description
                    FROM
                        pem.agent pa LEFT OUTER JOIN pem.agent_heartbeat pah ON (pa.id = pah.agent_id)
                    WHERE
                        pa.active = TRUE AND
                        pa.alert_blackout AND
                        CASE WHEN pah.agent_id IS NULL THEN FALSE ELSE pah.last_heartbeat < now() AND pah.last_heartbeat > now() - (pa.heartbeat_tolerance+15)*''1 second''::interval END';
        END IF;

        FOR row IN EXECUTE sql
        LOOP
            RETURN NEXT row;
        END LOOP;

        RETURN;
    END;
    $$ LANGUAGE plpgsql;

    UPDATE pem.chart_func SET func = $QUERY$
      SELECT
        $$Replication Status: $$ ||
          COALESCE((
            SELECT
              CASE
              WHEN psh.last_heartbeat IS NULL OR pa.heartbeat_tolerance IS NULL THEN $$Unknown$$
              WHEN psh.last_heartbeat < (now() - ((pa.heartbeat_tolerance + 15) * '1 second'::interval)) THEN $$Stopped$$
              WHEN pstrl.replication_paused THEN $$Paused$$ ELSE $$Running$$
              END
            FROM pemdata.streaming_replication_lag_time pstrl
              LEFT OUTER JOIN pem.server_heartbeat psh ON (pstrl.server_id=psh.server_id)
              LEFT OUTER JOIN pem.agent_server_binding pasb ON (pstrl.server_id = pasb.server_id)
              LEFT OUTER JOIN pem.avail_agents pa ON (pasb.agent_id = pa.id AND psh.agent_id = pa.id)
              LEFT OUTER JOIN pem.agent_heartbeat pah ON (pah.agent_id = pasb.agent_id)
              WHERE pstrl.server_id = %(server_id)s::int4
          ), $$Unknown$$)
    $QUERY$ WHERE id = 83;

    UPDATE pem.chart_func SET func = $QUERY$
    WITH agent_list AS (
        SELECT
            pa.id AS id, pa.active AS active, pah.agent_id, pah.last_heartbeat, pa.heartbeat_tolerance
        FROM
            pem.avail_agents pa
            LEFT OUTER JOIN pem.agent_heartbeat pah ON (pa.id = pah.agent_id)
    ),
    server_list AS (
        SELECT
            ps.id AS server_id, psh.last_heartbeat AS server_last_heartbeat,
            pa.active AS agent_active, pah.last_heartbeat AS agent_last_heartbeat,
            pa.heartbeat_tolerance AS heartbeat_tolerance
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
                last_heartbeat > (now() - ((heartbeat_tolerance + 15) * '1 second'::interval))
            UNION
            SELECT
                2::int AS id, 'Agents Down'::text AS label, true::bool AS required, count(id)::int8 AS count
            FROM
                agent_list
            WHERE
                active = TRUE AND
                agent_id IS NOT NULL AND
                last_heartbeat < (now() - ((heartbeat_tolerance + 15) * '1 second'::interval))
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
                server_last_heartbeat > (now() - ((heartbeat_tolerance + 15) * '1 second'::interval))
            UNION
            SELECT
                5::int AS id, 'Servers Down'::text AS label, true::bool AS required, count(server_id)::int8 AS count
            FROM
                server_list
            WHERE
                agent_active IS NOT NULL AND agent_active AND
                agent_last_heartbeat IS NOT NULL AND
                agent_last_heartbeat < now() AND
                agent_last_heartbeat > (now() - ((heartbeat_tolerance + 15) * '1 second'::interval)) AND
                server_last_heartbeat IS NOT NULL AND
                server_last_heartbeat < (now() - ((heartbeat_tolerance + 15) * '1 second'::interval))
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
                        agent_last_heartbeat < (now() - ((heartbeat_tolerance + 15) * '1 second'::interval))))
            UNION
            SELECT id, label, required, count
            FROM (
                SELECT
                    7::int AS id, 'Unmanaged Servers'::text AS label, false::bool AS required,
                    COUNT(server_id)::int8 AS count
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

        EXECUTE 'SELECT heartbeat_tolerance * ''1 second''::interval FROM pem.agent where id = $1::int4'
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

    -- PEM-5602: Updating the server connection params to the default values
    DO $$
    BEGIN
        IF EXISTS (
            SELECT 1 FROM information_schema.columns
            WHERE table_schema = 'pem'
              AND table_name = 'server_options'
              AND column_name = 'connect_timeout'
        ) AND EXISTS (
            SELECT 1 FROM information_schema.columns
            WHERE table_schema = 'pem'
              AND table_name = 'server'
              AND column_name = 'ssl'
        ) THEN
            -- Do the full update including connect_timeout
            UPDATE pem.server_options so
            SET connection_params = jsonb_build_object(
                'sslmode',
                COALESCE(
                    CASE s.ssl
                        WHEN 1 THEN 'allow'
                        WHEN 2 THEN 'prefer'
                        WHEN 3 THEN 'require'
                        WHEN 4 THEN 'disable'
                        WHEN 5 THEN 'verify-ca'
                        WHEN 6 THEN 'verify-full'
                    END,
                    'prefer'
                ),
                'connect_timeout', COALESCE(connect_timeout, 10)
            )
            FROM pem.server s
            WHERE so.server_id = s.id
              AND (
                  so.connection_params IS NULL
                  OR so.connection_params = '{}'::jsonb
              );
        END IF;
    END$$;

    CREATE OR REPLACE FUNCTION pem.startup(server_desc text, server_name text, server_host text, server_port int, server_database text,
              user_name text, passwd text, ser_group text, agentid int, agent_database text)
      RETURNS void AS
    $BODY$
    DECLARE
      sg_id     integer;
      serverid  integer := 1;
      is_active boolean;
      name      text;
      probe_curs CURSOR FOR SELECT id, display_name FROM pem.probe
        WHERE NOT discard_history AND jstid IS NULL;
    BEGIN

      -- Check if the server group already exists.
      SELECT id INTO sg_id FROM pem.server_group sg WHERE sg.name = ser_group;

      IF (NOT FOUND) THEN
        -- Create new server group
        INSERT INTO pem.server_group(name) VALUES(ser_group) RETURNING id INTO sg_id;
      END IF;

      -- Check the server entry is already exist.
      SELECT active INTO is_active FROM pem.server WHERE id = serverid;

      -- if entry not found or server with id serverid is already exist and server is active then add new server.
      IF (NOT FOUND) OR is_active THEN
        -- Create entry of PEM server in pem.server table.
        INSERT INTO pem.server (
          description, server, port, database
        ) VALUES (
          server_desc, server_name, server_port, server_database
        ) RETURNING id INTO serverid;

        -- Set the options of the PEM server
        INSERT INTO pem.server_options (
          server_id, pem_user, server_group_id, username, connection_params
        ) VALUES (
          serverid, user_name, sg_id, user_name,
          jsonb_build_object(
                'sslmode', 'prefer',
                'connect_timeout', 10
              )
        );

        -- Set the options of the PEM server auth table
        INSERT INTO pem.server_auth (server_id, pem_user) VALUES (serverid, user_name);

      ELSE
        UPDATE pem.server SET
          description = server_desc,
          server = server_name,
          port = server_port,
          database = server_database,
          active = 't'
        WHERE id = serverid;

        UPDATE pem.server_options SET
          pem_user = user_name,
          server_group_id = sg_id,
          username = user_name,
          connection_params = jsonb_build_object(
                'sslmode', 'prefer',
                'connect_timeout', 10
      )
        WHERE server_id = serverid;

        UPDATE pem.server_auth SET pem_user = user_name WHERE server_id = serverid;

      END IF;

      -- Create Agent Server Binding
      INSERT INTO pem.agent_server_binding (
        agent_id, server_id, server, port, username, database, password
      ) VALUES (
        agentid, serverid, server_host, server_port, user_name, agent_database, passwd
      );

      PERFORM pem.register_pem_server(serverid);

    END;
    $BODY$ LANGUAGE plpgsql;

    DROP VIEW IF EXISTS pem.avail_servers;
    CREATE OR REPLACE VIEW pem.avail_servers AS
      SELECT
        s.id AS id,
        s.description AS description,
        s.server AS server,
        s.port AS port,
        s.database AS database,
        s.serviceid AS serviceid,
        s.active AS active,
        s.hostaddr AS hostaddr,
        s.service AS service,
        s.alert_blackout AS alert_blackout,
        s.owner AS owner,
        s.team AS team,
        s.owner::regrole::name AS server_owner,
        s.is_remote_monitoring AS is_remote_monitoring,
        s.replication_solution AS replication_solution,
        s.efm_cluster_name AS efm_cluster_name,
        s.efm_service_name AS efm_service_name,
        s.efm_installation_path AS efm_installation_path,
        s.patroni_installation_path AS patroni_installation_path,
        s.patroni_cluster_name AS patroni_cluster_name,
        s.patroni_config_path AS patroni_config_path,
        COALESCE(so.server_group_id, s.group_id, 1) AS group_id
      FROM pem.server s
        LEFT JOIN pem.server_options so ON (s.id = so.server_id AND pem_user = current_user)
      WHERE
        -- Only active servers
        s.active AND
        pem.can_access_team(s.owner, s.team);

    ALTER TABLE pem.server
    DROP COLUMN IF EXISTS ssl;

    ALTER TABLE pem.server_options
    DROP COLUMN IF EXISTS connect_timeout;

    DO $$
    BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM information_schema.columns
        WHERE table_schema = 'pem'
        AND table_name = 'alert_status'
        AND column_name = 'last_execution_duration'
    ) THEN
        ALTER TABLE pem.alert_status
        ADD COLUMN last_execution_duration interval;
    END IF;
    END $$;


    -- PEM-4443 This creates triggers and functions to log Patroni and EFM switchover events
    CREATE OR REPLACE FUNCTION pem.log_patroni_switchover()
    RETURNS TRIGGER AS $$
    DECLARE
        detail_text TEXT;
    BEGIN
        detail_text := format(
            '{"ClusterType":"patroni","ServerId":%s,"ClusterName":"%s","NodeIp":"%s","NodeName":"%s","NewRole":"%s","OldRole":"%s","Timestamp":"%s"}',
            NEW.server_id,
            COALESCE(NEW.cluster_name, 'null'),
            COALESCE(NEW.host, 'null'),
            NEW.member_name,
            NEW.role,
            OLD.role,
            to_char(OLD.recorded_time, 'YYYY-MM-DD HH24:MI:SS')
        );

        -- Ensure it fits within 255 chars
        IF length(detail_text) > 255 THEN
            detail_text := left(detail_text, 255);
        END IF;

        INSERT INTO pem.event_history (
            recorded_time, user_name, component, operation, message, details
        ) VALUES (
            now(),
            current_user,
            'HA Monitoring',
            'Switchover',
            format('Patroni leader changed for server %s', NEW.server_id),
            detail_text
        );
        RETURN NULL;
    END;
    $$ LANGUAGE plpgsql
    security definer;

    DROP TRIGGER IF EXISTS trg_patroni_switchover ON pemdata.patroni_node_status;

    CREATE TRIGGER trg_patroni_switchover
    AFTER UPDATE ON pemdata.patroni_node_status
    FOR EACH ROW
    WHEN (
        OLD.role IS DISTINCT FROM NEW.role
    )
    EXECUTE FUNCTION pem.log_patroni_switchover();

    CREATE OR REPLACE FUNCTION pem.patroni_failover_info(
        p_server_id INT,
        p_interval_minutes INT
    )
    RETURNS TABLE (
        "Failover time" timestamptz,
        "Cluster type" TEXT,
        "Cluster name" TEXT,
        "Previous leader ip" TEXT,
        "Previous primary node" TEXT,
        "New leader ip" TEXT,
        "New primary node" TEXT
    ) AS $$
    DECLARE
        r_demotion RECORD;
        r_promotion RECORD;
    BEGIN
        -- Demotion: Leader → non-Leader
        SELECT
            recorded_time,
            (details::json->>'ClusterType') AS cluster_type,
            (details::json->>'ClusterName') AS cluster_name,
            (details::json->>'NodeIp')      AS old_ip,
            (details::json->>'NodeName')    AS old_node
        INTO r_demotion
        FROM pem.event_history
        WHERE component = 'HA Monitoring'
          AND operation = 'Switchover'
          AND (details::json->>'ClusterType') = 'patroni'
          AND (details::json->>'OldRole') = 'Leader'
          AND (details::json->>'NewRole') IS DISTINCT FROM 'Leader'
          AND (details::json->>'ServerId')::int = p_server_id
          AND recorded_time >= now() - (p_interval_minutes || ' minutes')::interval
        ORDER BY recorded_time DESC
        LIMIT 1;

        IF r_demotion.recorded_time IS NULL THEN
            RETURN;
        END IF;

        -- Promotion: non-Leader → Leader
        SELECT
            recorded_time,
            (details::json->>'NodeIp')   AS new_ip,
            (details::json->>'NodeName') AS new_node
        INTO r_promotion
        FROM pem.event_history
        WHERE component = 'HA Monitoring'
          AND operation = 'Switchover'
          AND (details::json->>'ClusterType') = 'patroni'
          AND (details::json->>'NewRole') = 'Leader'
          AND (details::json->>'OldRole') IS DISTINCT FROM 'Leader'
          AND (details::json->>'ServerId')::int = p_server_id
          AND recorded_time >= r_demotion.recorded_time
          AND recorded_time <= now()
        ORDER BY recorded_time
        LIMIT 1;

        IF r_promotion.new_ip IS NOT NULL THEN
            "Failover time"   := r_demotion.recorded_time;
            "Cluster type"    := r_demotion.cluster_type;
            "Cluster name"    := r_demotion.cluster_name;
            "Previous leader ip"          := r_demotion.old_ip;
            "Previous primary node"   := r_demotion.old_node;
            "New leader ip"          := r_promotion.new_ip;
            "New primary node"   := r_promotion.new_node;
            RETURN NEXT;
        END IF;
    END;
    $$ LANGUAGE plpgsql STABLE;

    CREATE OR REPLACE FUNCTION pem.log_efm_switchover()
    RETURNS TRIGGER AS $$
    DECLARE
        cluster_name TEXT;
        detail_text TEXT;
    BEGIN
        -- Get the EFM cluster name
        SELECT efm_cluster_name INTO cluster_name
        FROM pem.server
        WHERE id = NEW.server_id;

        -- Build the JSON detail text
        detail_text := format(
            '{"ClusterType":"efm","ServerId":%s,"ClusterName":"%s","NodeIp":"%s","NewAgentType":"%s","OldAgentType":"%s","Timestamp":"%s"}',
            NEW.server_id,
            COALESCE(cluster_name, 'null'),
            COALESCE(NEW.efm_ip_address, 'null'),
            COALESCE(NEW.efm_agent_type, 'null'),
            COALESCE(OLD.efm_agent_type, 'null'),
            to_char(NEW.recorded_time, 'YYYY-MM-DD HH24:MI:SS')
        );

        -- Truncate if too long
        IF length(detail_text) > 255 THEN
            detail_text := left(detail_text, 255);
        END IF;

        -- Insert the log entry
        INSERT INTO pem.event_history (
            recorded_time,
            user_name,
            component,
            operation,
            message,
            details
        ) VALUES (
            now(),
            current_user,
            'HA Monitoring',
            'Switchover',
            format('EFM primary changed for server %s', NEW.server_id),
            detail_text
        );

        RETURN NULL;
    END;
    $$ LANGUAGE plpgsql SECURITY DEFINER;

    DROP TRIGGER IF EXISTS trg_efm_switchover ON pemdata.efm_cluster_node_status;

    CREATE TRIGGER trg_efm_switchover
    AFTER UPDATE ON pemdata.efm_cluster_node_status
    FOR EACH ROW
    WHEN (
        OLD.efm_agent_type IS DISTINCT FROM NEW.efm_agent_type
    )
    EXECUTE FUNCTION pem.log_efm_switchover();

    -- Function to log last failover information for a efm server in the last X minutes
    -- p_server_id: ID of the server to check
    -- p_interval_minutes: Interval in minutes to check for failover in last X minutes
    CREATE OR REPLACE FUNCTION pem.efm_failover_info(
        p_server_id INT,
        p_interval_minutes INT
    )
    RETURNS TABLE (
        "Failover time" timestamptz,
        "Cluster type" TEXT,
        "Cluster name" TEXT,
        "Previous primary ip" TEXT,
        "New primary ip" TEXT
    ) AS $$
    DECLARE
        r_demotion RECORD;
        r_promotion RECORD;
    BEGIN
        -- Latest demotion: Primary → not Primary
        SELECT
            recorded_time,
            (details::json->>'ClusterType') AS cluster_type,
            (details::json->>'ClusterName') AS cluster_name,
            (details::json->>'NodeIp')      AS old_ip
        INTO r_demotion
        FROM pem.event_history
        WHERE component = 'HA Monitoring'
          AND operation = 'Switchover'
          AND (details::json->>'OldAgentType') = 'Primary'
          AND (details::json->>'NewAgentType') IS DISTINCT FROM 'Primary'
          AND (details::json->>'ServerId')::int = p_server_id
          AND recorded_time >= now() - (p_interval_minutes || ' minutes')::interval
        ORDER BY recorded_time DESC
        LIMIT 1;

        IF r_demotion.recorded_time IS NULL THEN
            RETURN;
        END IF;

        -- Next promotion: Standby → Primary
        SELECT
            recorded_time,
            (details::json->>'NodeIp') AS new_ip
        INTO r_promotion
        FROM pem.event_history
        WHERE component = 'HA Monitoring'
          AND operation = 'Switchover'
          AND (details::json->>'NewAgentType') = 'Primary'
          AND (details::json->>'OldAgentType') IS DISTINCT FROM 'Primary'
          AND (details::json->>'ServerId')::int = p_server_id
          AND recorded_time >= r_demotion.recorded_time
          AND recorded_time <= now()
        ORDER BY recorded_time
        LIMIT 1;

        IF r_promotion.new_ip IS NOT NULL THEN
            "Failover time" := r_demotion.recorded_time;
            "Cluster type"  := r_demotion.cluster_type;
            "Cluster name"  := r_demotion.cluster_name;
            "Previous primary ip"        := r_demotion.old_ip;
            "New primary ip"        := r_promotion.new_ip;
            RETURN NEXT;
        END IF;
    END;
    $$ LANGUAGE plpgsql STABLE;


    -- PEM-4443 This creates an alert template for failovers recorded in the last N minutes
    DO $$
    BEGIN
      IF NOT EXISTS (SELECT 1 FROM pem.alert_template WHERE display_name = 'Patroni cluster failover detected' AND is_system_template) THEN
        PERFORM pem.create_alert_template(
          'Patroni cluster failover detected',
          'Failover triggered when a failover event is recorded for a Patroni cluster within the specified time',
          $sql$
            SELECT count(*) FROM pem.patroni_failover_info(${server_id}, ${param_1})
          $sql$,
          200,  -- object_type: server
          '{Interval}',
          '{INTEGER}',
          '{Minutes}',
          '#',
          '{patroni_node_status}',
          (SELECT COALESCE(MAX(snmp_oid), 0) + 1 FROM pem.alert_template WHERE object_type = 200),
          'ALL',
          1,  -- alert level
          30, -- frequency
          true,
          $sql$
            SELECT * FROM pem.patroni_failover_info(${server_id}, ${param_1});
          $sql$
        );
      END IF;
    END;
    $$ LANGUAGE 'plpgsql';

    DO $$
    BEGIN
      IF NOT EXISTS (SELECT 1 FROM pem.alert_template WHERE display_name = 'EFM cluster failover detected' AND is_system_template) THEN
        PERFORM pem.create_alert_template(
          'EFM cluster failover detected',
          'Failover triggered when a failover event is recorded for an EFM cluster within the specified time',
          $sql$
            SELECT count(*) FROM pem.efm_failover_info(${server_id}, ${param_1})
          $sql$,
          200,  -- object_type: server
          '{Interval}',
          '{INTEGER}',
          '{Minutes}',
          '#',
          '{efm_cluster_node_status}',
          (SELECT COALESCE(MAX(snmp_oid), 0) + 1 FROM pem.alert_template WHERE object_type = 200),
          'ALL',
          1,  -- alert level
          30, -- frequency
          true,
          $sql$
            SELECT * FROM pem.efm_failover_info(${server_id}, ${param_1});
          $sql$
        );
      END IF;
    END;
    $$ LANGUAGE 'plpgsql';

    -- PEM-5650: Updating the probe bdr_node_summary to display node_uuid also
    UPDATE pem.probe
    SET probe_code = $sql$
    SELECT node_name, node_group_name, peer_state_name, peer_target_state_name, NULL AS sub_repsets, '' AS node_uuid FROM bdr.node_summary;
    $sql$
    WHERE internal_name = 'bdr_node_summary';
    
    CREATE OR REPLACE FUNCTION pem.send_email(mail_group_id integer[], subject text, message text)
    RETURNS boolean AS $$
    DECLARE
        mail_to text[] := '{}';
        mail_cc text[] := '{}';
        mail_bcc text[] := '{}';
        mail_reply_to text[] := '{}';
        mail_to_str text := '';
        mail_cc_str text := '';
        mail_bcc_str text := '';
        mail_reply_to_str text := '';
        mail_from_str text := '';
        mail_subject_prefix text := '';
        is_smtp_enabled boolean:= false;
        smtp_message_linebreak text;
        i integer;
        is_notify boolean:= false;
        tmp_row RECORD;
        now_time numeric;
    BEGIN
        -- Check if smtp_enabled == true, if not return.
        SELECT value INTO is_smtp_enabled FROM pem.config WHERE param = 'smtp_enabled';

        -- Check the linebreak for message body
        SELECT res_option ->> 'label' AS label INTO smtp_message_linebreak
            FROM   pem.config pc, json_array_elements(pc.options) res_option
        WHERE  param = 'smtp_message_linebreak' AND res_option->>'value' = pc.value;

        IF smtp_message_linebreak = 'LF' THEN
            smtp_message_linebreak := '\n';
        ELSIF (smtp_message_linebreak = 'CR') THEN
            smtp_message_linebreak := '\r';
        ELSIF (smtp_message_linebreak = 'CR+LF') THEN
            smtp_message_linebreak := '\r\n';
        ELSIF (smtp_message_linebreak = 'LF+CR') THEN
            smtp_message_linebreak := '\n\r';
        END IF;

        -- If user has specified any other linebreak value then replace it against default `\n`.
        IF smtp_message_linebreak IS NOT NULL AND LENGTH(TRIM(smtp_message_linebreak)) > 0 AND TRIM(smtp_message_linebreak) != '\n' THEN
            message := REPLACE(message, '\n', smtp_message_linebreak);
        END IF;

        SELECT (EXTRACT(EPOCH FROM now()::timetz) + EXTRACT(TIMEZONE FROM now()::timetz)) INTO now_time;

        -- There are not email groups for the email to send.
        IF COALESCE(array_length(mail_group_id, 1), 0) = 0 THEN
            RETURN false;
        END IF;

        IF is_smtp_enabled THEN
            -- iterate through all the group id's and insert into the spool table
            FOR i in 1..COALESCE(array_upper(mail_group_id, 1), 0) LOOP

                -- Clear the email address array before any operations.
                mail_to := '{}';
                mail_cc := '{}';
                mail_bcc := '{}';
                mail_reply_to := '{}';

                -- Get email details
                -- iterate through all time intervals for a particular group and
                -- check time against server's current time and send mail to only
                -- those addresses for which current time lies within their interval
                FOR tmp_row IN SELECT grp_to, grp_cc, grp_bcc, grp_from, grp_reply_to, grp_subject_prefix, (EXTRACT(EPOCH FROM time_from) + EXTRACT(TIMEZONE FROM time_from)) as time_from, (EXTRACT(EPOCH FROM time_to) + EXTRACT(TIMEZONE FROM time_to)) as time_to FROM pem.email_group_option WHERE gid = mail_group_id[i]
                LOOP

                    -- If 'FROM' is not available, we won't be to send the email.
                    CONTINUE WHEN tmp_row.grp_from = '';

                    IF tmp_row.time_from < tmp_row.time_to THEN
                        IF tmp_row.time_from <= now_time AND now_time <= tmp_row.time_to THEN
                            mail_to := array_append(mail_to, tmp_row.grp_to);
                            mail_cc := array_append(mail_cc, tmp_row.grp_cc);
                            mail_bcc := array_append(mail_bcc, tmp_row.grp_bcc);
                            mail_reply_to := array_append(mail_reply_to, tmp_row.grp_reply_to);
                            mail_from_str := tmp_row.grp_from;
                            mail_subject_prefix := COALESCE(tmp_row.grp_subject_prefix, '')::text;
                        END IF;
                    ELSIF tmp_row.time_from > tmp_row.time_to THEN
                        IF (tmp_row.time_from <= now_time AND now_time <= (EXTRACT(EPOCH FROM '23:59:59'::timetz) + EXTRACT(TIMEZONE FROM '23:59:59'::timetz))) OR
                            ((EXTRACT(EPOCH FROM '00:00:00'::timetz) + EXTRACT(TIMEZONE FROM '00:00:00'::timetz)) <= now_time AND now_time <=tmp_row.time_to) THEN
                            mail_to := array_append(mail_to, tmp_row.grp_to);
                            mail_cc := array_append(mail_cc, tmp_row.grp_cc);
                            mail_bcc := array_append(mail_bcc, tmp_row.grp_bcc);
                            mail_reply_to := array_append(mail_reply_to, tmp_row.grp_reply_to);
                            mail_from_str := tmp_row.grp_from;
                            mail_subject_prefix := COALESCE(tmp_row.grp_subject_prefix, '')::text;
                        END IF;
                    END IF;
                END LOOP;

                mail_to_str := array_to_string(array_remove(array_remove(mail_to, ''), NULL), ',');
                mail_cc_str := array_to_string(array_remove(array_remove(mail_cc, ''), NULL), ',');
                mail_bcc_str := array_to_string(array_remove(array_remove(mail_bcc, ''), NULL), ',');
                mail_reply_to_str := array_to_string(array_remove(array_remove(mail_reply_to, ''), NULL), ',');

                -- We won't be able to send an email if all TO, CC and BCC are not available.
                CONTINUE WHEN mail_to_str = '' AND mail_cc_str = '' AND mail_bcc_str = '';

                IF COALESCE(mail_subject_prefix, '') <> '' THEN
                    subject := mail_subject_prefix || ': ' || subject;
                END IF;

                -- Insert the spool record
                INSERT INTO pem.smtp_spool(
                    mail_to, mail_cc, mail_bcc, mail_reply_to, mail_from,
                    subject, message, sent_status
                ) VALUES(
                    mail_to_str, mail_cc_str, mail_bcc_str, mail_reply_to_str, mail_from_str,
                    subject, message, 'u'
                );

                is_notify = true;

            END LOOP;

            IF is_notify THEN
                -- Notify listeners that a message is ready for delivery
                NOTIFY SMTP_SPOOL;
                RETURN true;
            END IF;
        END IF;

        RETURN false;
    END;
    $$ LANGUAGE plpgsql SECURITY DEFINER;

    -- ==================================
    -- Probe: Patroni Node Status
    -- ==================================
    DO $DO$
    BEGIN
        IF NOT EXISTS (SELECT id FROM pem.probe where internal_name = 'patroni_node_status') THEN

            INSERT INTO pem.probe
                    (display_name, internal_name, collection_method, target_type_id,
                    agent_capability, enabled_by_default, force_enabled,
                    default_execution_frequency, default_lifetime, any_server_version, probe_code)
            VALUES
                ('Patroni Node Status', 'patroni_node_status', 'i', 200, NULL, false, false, 300,
                    7, false, 'patroni_node_status');

            INSERT INTO pem.probe_column
                    (probe_id, internal_name, display_name, display_position, classification,
                    sql_data_type, unit_of_value, calculate_pit, discard_history, pit_by_default, is_graphable)
            SELECT
                    (SELECT id FROM pem.probe WHERE probe_code = 'patroni_node_status'),
                    v.internal_name, v.display_name, v.display_position, v.classification,
                    v.sql_data_type, v.unit_of_value, v.calculate_pit, v.discard_history, v.pit_by_default, v.is_graphable
            FROM
                    (VALUES
                    ('cluster_name',       'Cluster Name',        1, 'm', 'text',    '', false, false, false, false),
                    ('member_name',        'Member Name',         2, 'm', 'text',    '', false, false, false, false),
                    ('host',               'Host',                3, 'k', 'text',    '', false, false, false, false),
                    ('role',               'Role',                4, 'm', 'text',    '', false, false, false, false),
                    ('state',              'State',               5, 'm', 'text',    '', false, false, false, false),
                    ('timeline',           'Timeline',            6, 'm', 'text',    '', false, false, false, false),
                    ('replication_lag_mb', 'Replication Lag (MB)',7, 'm', 'text',    '', false, false, false, false)
                    ) v(internal_name, display_name, display_position, classification,
                            sql_data_type, unit_of_value, calculate_pit, discard_history, pit_by_default, is_graphable);

            INSERT INTO pem.probe_server_version
                (probe_id, server_version_id, probe_code)
            SELECT
                    (SELECT id FROM pem.probe WHERE probe_code = 'patroni_node_status'), v.version, NULL
            FROM (
                VALUES (10902), (10903), (10904), (10905), (10906), (11000), (11100),
                    (11200), (11300), (11400), (11500), (11600), (11700),
                    (20902), (20903), (20904), (20905), (20906), (21000), (21100),
                    (21200), (21300), (21400), (21500), (21600), (21700)
            ) v(version);
        END IF;

        PERFORM pem.create_data_and_history_tables();
    END;
    $DO$ LANGUAGE 'plpgsql';

    -- PEM-5650: Updating the probe bdr_node_summary to display node_uuid also
    UPDATE pem.probe
    SET probe_code = $sql$
    SELECT node_name, node_group_name, peer_state_name, peer_target_state_name, NULL AS sub_repsets, '' AS node_uuid FROM bdr.node_summary;
    $sql$
    WHERE internal_name = 'bdr_node_summary';

    DO $$
    BEGIN
        IF NOT EXISTS (
            SELECT 1
            FROM pem.probe_extension_version
            WHERE probe_id = (SELECT id FROM pem.probe WHERE internal_name = 'bdr_node_summary')
            AND extension_version IN ('6.0.1', '6.0.2')
        ) THEN
            INSERT INTO pem.probe_extension_version (
                probe_id, server_version_id, extension_version, probe_code
            )
            SELECT
                (SELECT id FROM pem.probe WHERE internal_name = 'bdr_node_summary'),
                v.version,
                e.version,
                'SELECT node_name, node_group_name, peer_state_name, peer_target_state_name, node_uuid FROM bdr.node_summary;'
            FROM (
                VALUES (11100), (11200), (11300), (11400), (11500), (11600), (11700),
                       (21100), (21200), (21300), (21400), (21500), (21600), (21700)
            ) v(version)
            CROSS JOIN (
                VALUES ('6.0.1'), ('6.0.2')
            ) e(version);
        END IF;
    END;
    $$ LANGUAGE plpgsql;

    DO $$
    BEGIN
        IF NOT EXISTS (
            SELECT 1
            FROM pem.probe_column
            WHERE probe_id = (SELECT id FROM pem.probe WHERE internal_name = 'bdr_node_summary')
            AND internal_name = 'node_uuid'
        ) THEN
            INSERT INTO pem.probe_column (
                probe_id, internal_name, display_name, display_position, classification,
                sql_data_type, unit_of_value, calculate_pit, discard_history,
                pit_by_default, is_graphable
            )
            SELECT
                (SELECT id FROM pem.probe WHERE internal_name = 'bdr_node_summary'),
                v.internal_name, v.display_name, v.display_position, v.classification,
                v.sql_data_type, v.unit_of_value, v.calculate_pit, v.discard_history, v.pit_by_default, v.is_graphable
            FROM (
                VALUES
                    ('node_uuid', 'Node UUID', 6, 'm', 'text', '', false, false, false, false)
            ) v(internal_name, display_name, display_position, classification,
                sql_data_type, unit_of_value, calculate_pit, discard_history, pit_by_default, is_graphable);

            ALTER TABLE pemdata.bdr_node_summary
            ADD COLUMN IF NOT EXISTS node_uuid TEXT DEFAULT '';

            ALTER TABLE pemhistory.bdr_node_summary
            ADD COLUMN IF NOT EXISTS node_uuid TEXT DEFAULT '';
        END IF;
    END;
    $$ LANGUAGE plpgsql;


    -- Adding new probes for fetching the analytical replication slot and information about group configuration options
    DO $DO$
    BEGIN
        IF NOT EXISTS (SELECT id FROM pem.probe where internal_name = 'bdr_analytic_slot_name') THEN
            INSERT INTO pem.probe
            (display_name, internal_name, collection_method, target_type_id,
             enabled_by_default, force_enabled, default_execution_frequency,
             default_lifetime, any_server_version, probe_code, extension_name, any_extension_version)
            VALUES
            ('PGD Analytic Slot Name', 'bdr_analytic_slot_name', 's', 1000, false, false, 60, 30, true,
            'SELECT NULL AS slot_name WHERE false', 'bdr', true);

            INSERT INTO pem.probe_column
                    (probe_id, internal_name, display_name, display_position, classification,
                    sql_data_type, unit_of_value, calculate_pit, discard_history, pit_by_default, is_graphable)
            SELECT
                    (SELECT id FROM pem.probe WHERE internal_name = 'bdr_analytic_slot_name'),
                    v.internal_name, v.display_name, v.display_position, v.classification,
                    v.sql_data_type, v.unit_of_value, v.calculate_pit, v.discard_history, v.pit_by_default, v.is_graphable
            FROM
                    (VALUES
                        ('slot_name', 'Slot Name', 1, 'm', 'text', '', false, false, false, false)
                    ) v(internal_name, display_name, display_position, classification,
                            sql_data_type, unit_of_value, calculate_pit, discard_history, pit_by_default, is_graphable);

            INSERT INTO pem.probe_extension_version
                (probe_id, server_version_id, extension_version, probe_code)
            SELECT
                (
                SELECT id FROM pem.probe WHERE internal_name = 'bdr_analytic_slot_name'),
                v.version,
                e.version,
                'SELECT bdr.local_analytics_slot_name() AS slot_name;'
            FROM (
                VALUES (11100), (11200), (11300), (11400), (11500), (11600), (11700), (21100), (21200), (21300), (21400), (21500), (21600), (21700)
            ) v(version) CROSS JOIN (
        VALUES ('6.0.1'), ('6.0.2')) e(version);
        END IF;

        IF NOT EXISTS (SELECT id FROM pem.probe where internal_name = 'bdr_node_group_config_summary') THEN
            INSERT INTO pem.probe
            (display_name, internal_name, collection_method, target_type_id,
             enabled_by_default, force_enabled, default_execution_frequency,
             default_lifetime, any_server_version, probe_code, extension_name, any_extension_version)
            VALUES
            ('PGD Node Group Config Summary', 'bdr_node_group_config_summary', 's', 1000, false, false, 60, 30, true,
            'SELECT NULL::bigint AS node_group_id, NULL::text AS node_group_name, NULL::text AS option_name, NULL::text AS current_value, NULL::text AS current_value_source WHERE false', 'bdr', true);

            INSERT INTO pem.probe_column
                    (probe_id, internal_name, display_name, display_position, classification,
                    sql_data_type, unit_of_value, calculate_pit, discard_history, pit_by_default, is_graphable)
            SELECT
                    (SELECT id FROM pem.probe WHERE internal_name = 'bdr_node_group_config_summary'),
                    v.internal_name, v.display_name, v.display_position, v.classification,
                    v.sql_data_type, v.unit_of_value, v.calculate_pit, v.discard_history, v.pit_by_default, v.is_graphable
            FROM
                    (VALUES
                        ('node_group_id',       'Node Group ID',        1, 'k', 'bigint',    '', false, false, false, false),
                        ('node_group_name',       'Node Group Name',        2, 'm', 'text',    '', false, false, false, false),
                        ('option_name',       'Option Name',        3, 'k', 'text',    '', false, false, false, false),
                        ('current_value',       'Current Value',        4, 'm', 'text',    '', false, false, false, false),
                        ('current_value_source',       'Current Value Source',        5, 'm', 'text',    '', false, false, false, false)
                    ) v(internal_name, display_name, display_position, classification,
                            sql_data_type, unit_of_value, calculate_pit, discard_history, pit_by_default, is_graphable);

            INSERT INTO pem.probe_extension_version
                (probe_id, server_version_id, extension_version, probe_code)
            SELECT
                (
                SELECT id FROM pem.probe WHERE internal_name = 'bdr_node_group_config_summary'),
                v.version,
                e.version,
                'SELECT node_group_id, node_group_name, option_name, current_value, current_value_source FROM bdr.node_group_config_summary;'
            FROM (
                VALUES (11100), (11200), (11300), (11400), (11500), (11600), (11700), (21100), (21200), (21300), (21400), (21500), (21600), (21700)
            ) v(version) CROSS JOIN (
        VALUES ('6.0.1'), ('6.0.2')) e(version);
        END IF;

        PERFORM pem.create_data_and_history_tables();
    END;
    $DO$ LANGUAGE 'plpgsql';

    -- PEM-5669: Disable the Last Vacuum and Last AutoVacuum alerts on the replica node.

    CREATE OR REPLACE FUNCTION pem.handle_replica_node_alerts()
    RETURNS TRIGGER AS $$
    BEGIN
      IF NEW.node_type = 'replica' THEN
        -- Disable alerts when node becomes a replica
        UPDATE pem.alert
        SET enabled = false
        WHERE server_id = NEW.server_id
          AND name IN ('Last Vacuum', 'Last AutoVacuum');

      ELSIF OLD.node_type = 'replica' AND NEW.node_type IS DISTINCT FROM 'replica' THEN
        -- Enable alerts when node is changed from replica to something else
        UPDATE pem.alert
        SET enabled = true
        WHERE server_id = NEW.server_id
          AND name IN ('Last Vacuum', 'Last AutoVacuum');
      END IF;

      RETURN NEW;
    END;
    $$ LANGUAGE plpgsql;

    -- Drop existing trigger as we do not have create/replace trigger.
    DROP TRIGGER IF EXISTS trg_handle_replica_alerts on pemdata.server_info;

    CREATE TRIGGER trg_handle_replica_alerts
    AFTER INSERT OR UPDATE OF node_type ON pemdata.server_info
    FOR EACH ROW
    EXECUTE FUNCTION pem.handle_replica_node_alerts();

    -- Executing the below block to handle the trigger functionality for the upgrade scenario
    DO $$
    DECLARE
        rec RECORD;
    BEGIN
      FOR rec IN
        SELECT server_id, node_type
        FROM pemdata.server_info
      LOOP
        IF rec.node_type = 'replica' THEN
          -- Disable alerts
          UPDATE pem.alert
          SET enabled = false
          WHERE server_id = rec.server_id
            AND name IN ('Last Vacuum', 'Last AutoVacuum');

        ELSE
          -- Enable alerts
          UPDATE pem.alert
          SET enabled = true
          WHERE server_id = rec.server_id
            AND name IN ('Last Vacuum', 'Last AutoVacuum');
        END IF;
      END LOOP;
    END $$;

-- PEM-5625: Added last_execution_duration in alert status table
CREATE OR REPLACE FUNCTION pem.process_one_alert() RETURNS BOOL AS $$
DECLARE
	err          text;
	sql          text;
	state        pem.alert_state;
	sql_ret          numeric;
	alert_rec     record;
	locked_alert      bool;
	probe_disabled_err text;
	zero_rows_err     text;
	probe_enabled     bool;
	all_probes_enabled bool;
	alert_state_since  timestamp with time zone;
	reminder_interval  integer;
	start_time timestamp;
	end_time timestamp;
	subject          text;
	message          text;
	send_mail_val     bool;
	min_probe_interval integer;
	probe_interval    integer;
	default_flapping_detection_state_change integer;
	down_objects_list text;
	template_name text;
	mail_group_id integer[];
	alert_info    text;
	sql_curs         REFCURSOR;
	sql_rec       RECORD;
	hs_row        RECORD;
	first_time    boolean := FALSE;
	sql_ret_display text := '';

BEGIN
	probe_disabled_err := 'Required probe(s) ';
	zero_rows_err := 'Zero rows returned';

	locked_alert := false;

	-- Find all alerts eligible for processing
	FOR alert_rec in SELECT al.*, ast.current_state AS state, at.sql, at.display_name AS template_name,
						at.probe_dependency_list, ast.state_change_count
					FROM (
					pem.alert AS al
					JOIN pem.alert_template AS at
					ON al.template_id = at.id
					)
					LEFT JOIN pem.alert_status AS ast
						ON(al.id = ast.alert_id)
					WHERE al.enabled = true
					-- We do not process alerts that are known erroneous
					AND (COALESCE(al.error_message, '' ) IN ('', zero_rows_err)
						OR al.error_message LIKE probe_disabled_err || '%' )
					AND (now() - COALESCE(ast.last_processed, '1900-01-01'))
						>= (al.check_frequency||'minutes')::interval
					/*
					* We process only those alerts that are bound to
					* 'active' agents and servers.
					*
					* Note:alert.agent_id, agent|server.active are defined
					* NOT NULL.
					*/
					AND CASE WHEN al.agent_id IN (-1 , 0) THEN TRUE
						ELSE al.agent_id IN (SELECT id FROM pem.agent WHERE active AND NOT alert_blackout)
						END
					AND CASE WHEN (al.server_id IS NULL) OR (al.server_id = 0) THEN TRUE
						ELSE al.server_id IN
							(SELECT id FROM pem.server WHERE active AND NOT alert_blackout
							INTERSECT
							SELECT server_id FROM pem.agent_server_binding)
						END
					ORDER BY ast.last_processed NULLS FIRST
		-- Add an advisory lock, so that only one process is working for each alert
	LOOP
		IF (pg_catalog.pg_try_advisory_lock(0, alert_rec.id) = true) THEN
			locked_alert := true;
			EXIT; /* the loop */
		END IF;
	END LOOP;

	/* If we couldn't find or lock any candidate alert ... */
	IF (locked_alert = false) THEN
		/* tell the caller that we didn't process any alerts */
		RETURN false;
	END IF;

	start_time := clock_timestamp(); -- Capture the start time to calculate the total execution time of the alert query
	
	/*
	* We should return only 'true' from here on, since there may be more alerts
	* to process.
	*
	* Also try to capture any ERROR and mark the alert as invalid
	* instead of passing that ERROR back to the caller.
	*/

	sql := alert_rec.sql;

	/* Replace any reference to hierarchy-related alert parameters */
	sql := regexp_replace(sql, E'\\${agent_id}',      COALESCE(alert_rec.agent_id::text, '')::text, 'g');
	sql := regexp_replace(sql, E'\\${server_id}',  COALESCE(alert_rec.server_id::text,    '')::text, 'g');
	sql := regexp_replace(sql, E'\\${database_name}',COALESCE(alert_rec.database_name, '')::text, 'g');
	sql := regexp_replace(sql, E'\\${schema_name}',    COALESCE(alert_rec.schema_name,       '')::text, 'g');
	sql := regexp_replace(sql, E'\\${package_name}',   COALESCE(alert_rec.package_name,   '')::text, 'g');
	sql := regexp_replace(sql, E'\\${object_name}',    COALESCE(alert_rec.object_name,       '')::text, 'g');

	/* Replace ${param_n} with corresponding alert parameters */
	FOR i IN 1..COALESCE(array_upper(alert_rec.params, 1), 0) LOOP
		sql := regexp_replace(sql, E'\\${param_' || i || '}', alert_rec.params[i]::text, 'g');
	END LOOP;

	err := '';

	/* Check any required probe is disabled from the probe dependency list */
	all_probes_enabled := true;
	FOR i IN 1..COALESCE(array_upper(alert_rec.probe_dependency_list, 1), 0) LOOP
		SELECT v.enabled INTO probe_enabled FROM pem.probe_target_view v LEFT JOIN pem.probe p ON p.id = v.probe_id
		WHERE v.probe_internal_name = alert_rec.probe_dependency_list[i]
		AND CASE WHEN p.target_type_id = 100 THEN (v.agent_id = alert_rec.agent_id)
			WHEN p.target_type_id = 200 THEN (v.server_id = alert_rec.server_id)
			WHEN p.target_type_id = 300 THEN (v.server_id = alert_rec.server_id AND v.database_name = alert_rec.database_name)
			ELSE (v.server_id = alert_rec.server_id AND v.database_name = alert_rec.database_name
			AND v.parameter_value_list[3] = alert_rec.schema_name)
			END;
		IF NOT probe_enabled THEN
			probe_disabled_err := probe_disabled_err || alert_rec.probe_dependency_list[i] || ',';
			all_probes_enabled := false;
		END IF;

		-- Get minimum probe interval from all dependent probes
		SELECT default_execution_frequency INTO probe_interval FROM pem.probe WHERE internal_name = alert_rec.probe_dependency_list[i];
		IF (probe_interval <  min_probe_interval) OR (i = 1) THEN
			min_probe_interval := probe_interval;
		END IF;
	END LOOP;

	probe_disabled_err := trim(trailing ',' from probe_disabled_err);
	probe_disabled_err := probe_disabled_err || ' are disabled.';

	IF NOT all_probes_enabled THEN
		err := probe_disabled_err;
	ELSE
		RAISE DEBUG 'Alert query being executed: %', sql;

		BEGIN
			OPEN sql_curs FOR EXECUTE sql;
			LOOP
			FETCH NEXT FROM sql_curs INTO sql_rec;
			EXIT WHEN NOT FOUND;
			-- Loop through the output of the query using hstore.
			FOR hs_row IN SELECT kv."key", kv."value" FROM public.each(public.hstore(sql_rec)) kv
			LOOP
				-- First column is our curernt value and second column is the display
				-- value if provided in the SQL query.
				IF first_time IS FALSE THEN
					sql_ret := COALESCE(hs_row."value", NULL);
					first_time := TRUE;
				ELSE
					sql_ret_display := COALESCE(hs_row."value", '');
				END IF;
			END LOOP;
			END LOOP;
			CLOSE sql_curs;
		EXCEPTION
			WHEN no_data_found THEN
			IF all_probes_enabled THEN
				err := '';
			END IF;

			WHEN OTHERS THEN
			err := SQLERRM;
		END;
	END IF;

	end_time := clock_timestamp(); -- Capture the end time to calculate the total execution time of the alert query

	-- If there was an error while processing the alert's sql
	IF (err <> '') THEN
		-- Set that error message on the alert
		UPDATE pem.alert
		SET error_message = err
		WHERE id = alert_rec.id;

		-- ... and also set the last processed timestamp
		UPDATE pem.alert_status
		SET last_processed = now(),
			last_execution_duration = end_time - start_time
		WHERE alert_id = alert_rec.id;

		-- If there wasn't any row for this alert already, then populate one.
		IF (NOT FOUND) THEN
			INSERT INTO pem.alert_status
			VALUES (alert_rec.id, NULL, NULL, NULL, now(), end_time - start_time);
		END IF;

		-- RAISE NOTICE 'Encountered error while processing SQL: %', err;

		/*
		* XXX: There's a small window of race condition here. Another transaction
		* might pick up processing of this alert immediately after we unlock it
		* below using non-transactional advisory lock.
		*
		* Someday consider trading this for transactional advisory locks. This
		* will be possible when we mandate PG 9.1 as a minimum requirement.
		*/
		PERFORM pg_catalog.pg_advisory_unlock(0, alert_rec.id);

		RETURN true;
	ELSE
		-- Set that error message to NULL on the alert if the SQL executes successfully
		UPDATE pem.alert
		SET error_message = NULL
		WHERE id = alert_rec.id;
	END IF;

	/* Some sample alerts
		Table size:  1GB => low, 2GB => med, 5GB => high

		>5 high
		>2 med
		>1 low

		operator: > ; thresholds: {1,2,5}

		current_connections : 50 => low, 20 => med, 5 => high

		<5 high
		<20 med
		<50 low

		operator: < ; thresholds: {50,20,5}
	*/

	IF (alert_rec.operator = '<') THEN
		IF (sql_ret < alert_rec.thresholds[3]) THEN
			state := 'HIGH';
		ELSIF (sql_ret < alert_rec.thresholds[2]) THEN
			state := 'MEDIUM';
		ELSIF (sql_ret < alert_rec.thresholds[1]) THEN
			state := 'LOW';
		ELSE
			state := NULL;
		END IF;
	ELSIF (alert_rec.operator = '>') THEN
		IF (sql_ret > alert_rec.thresholds[3]) THEN
			state := 'HIGH';
		ELSIF (sql_ret > alert_rec.thresholds[2]) THEN
			state := 'MEDIUM';
		ELSIF (sql_ret > alert_rec.thresholds[1]) THEN
			state := 'LOW';
		ELSE
			state := NULL;
		END IF;
	END IF;

	-- Get group id's to send email
	SELECT ARRAY(SELECT DISTINCT UNNEST(pem.get_email_group_ids(alert_rec.id, state::text, state::text))) INTO mail_group_id;

	/*
	* For an alert that is active (state IS NOT NULL), we do not want to clear
	* its 'acknowledged' flag the first time it goes lower than LOW. So we wait
	* for another round of check, and if it still appears lower than LOW, then
	* we reset its acknowledged flag.
	*
	* The pseudo-code is:
	*
	* if (acked = true)
	*     if current severity_level is null and previous/stored severity_level is null
	*        set acked := false
	*
	*     if severity_level increases or changed from null to not-null
	*         do nothing
	*
	*     If severity_level decreases or goes from not-null to null
	*         do nothing.
	* end if
	*/
	IF (alert_rec.acknowledged) THEN
		IF (state IS NULL AND alert_rec.state IS NULL) THEN
			-- State has been lower than LOW, two times in a row.
			UPDATE pem.alert
			SET acknowledged = false
			WHERE id = alert_rec.id;

			--send alert cleared SMTP notification
			IF alert_rec.send_email THEN
			-- Create subject and message
			SELECT subject_mail, message_mail INTO subject, message FROM pem.create_email(alert_rec.id, 'Alert Cleared');
			send_mail_val := pem.send_email(mail_group_id, subject, message);
			IF send_mail_val THEN
				-- update the time of mail send.
				UPDATE pem.alert SET last_mail_send = now() WHERE id = alert_rec.id;
			END IF;
			END IF;
		END IF;
	END IF;

	UPDATE pem.alert_status
	SET last_processed = now(),
	last_execution_duration = end_time - start_time,
		current_value = sql_ret,
		display_value = sql_ret_display,
		current_state = state, -- may be NULL
		current_state_since =  CASE
						WHEN state IS DISTINCT FROM alert_rec.state
						THEN now()
						ELSE current_state_since
						END
	WHERE alert_id = alert_rec.id;

	-- If there wasn't any status row for this alert already, then populate one.
	IF (NOT FOUND) THEN
		INSERT INTO pem.alert_status("alert_id", "current_value", "current_state",
			"current_state_since", "last_processed", "display_value", "last_execution_duration")
		VALUES (alert_rec.id, sql_ret, state,
			CASE
			WHEN state IS NOT NULL
			THEN now()
			ELSE NULL
			END,
			now(),
			sql_ret_display,
			end_time - start_time
			);
	END IF;

	-- Check for reminder notification
	SELECT value INTO reminder_interval FROM pem.config WHERE param = 'reminder_notification_interval';
	SELECT current_state_since INTO alert_state_since FROM pem.alert_status WHERE alert_id = alert_rec.id;
	IF alert_rec.send_email AND (NOT alert_rec.acknowledged) AND (alert_state_since IS NOT NULL) AND (state IS NOT NULL) AND (NOT alert_rec.flapping_detected)
	AND ((now() - alert_state_since) >= (reminder_interval||'minutes')::interval)
	AND ((now() - alert_rec.last_mail_send) >= (reminder_interval||'minutes')::interval) THEN

		-- Create subject and message
		SELECT subject_mail, message_mail INTO subject, message FROM pem.create_email(alert_rec.id, 'Alert Reminder');
		SELECT info INTO alert_info FROM pem.alert_status WHERE alert_id = alert_rec.id;
		message := regexp_replace(message, '%CurrentState%', state::text, 'g');
		message := regexp_replace(message, '%AlertingSince%', alert_state_since::text, 'g');
		CASE WHEN sql_ret_display IS NOT NULL AND sql_ret_display != '' THEN
			message := regexp_replace(message, '%CurrentValue%', COALESCE(sql_ret_display, 0::text), 'g');
		ELSE
			message := regexp_replace(message, '%CurrentValue%', COALESCE(sql_ret, 0)::text, 'g');
		END CASE;

		message := regexp_replace(message, '%DetailInfo%', COALESCE(alert_info, 'None')::text, 'g');

		send_mail_val := pem.send_email(mail_group_id, subject, message);
		IF send_mail_val THEN
			-- update the time of mail send.
			UPDATE pem.alert SET last_mail_send = now() WHERE id = alert_rec.id;
		END IF;
	END IF;

	SELECT value INTO default_flapping_detection_state_change FROM pem.config WHERE param = 'flapping_detection_state_change';

	IF (NOT alert_rec.flapping_detected) THEN
		--Flapping start is true when more than N state changes have occurred over (N + 1) * (min(probe_interval) * 2) seconds
		IF ((now() - alert_rec.last_flapping_detection_processed) >=
		(((default_flapping_detection_state_change + 1) * (min_probe_interval * 2)) * '1 second'::interval)) THEN

			UPDATE pem.alert SET last_flapping_detection_processed = now() WHERE id = alert_rec.id;
			UPDATE pem.alert_status SET state_change_count = 0 WHERE alert_id = alert_rec.id;

			IF (alert_rec.state_change_count > default_flapping_detection_state_change) THEN
			UPDATE pem.alert SET flapping_detected = 't' WHERE id = alert_rec.id;
			END IF;
		END IF;
	ELSE
		-- Flapping end is true when zero state changes have occurred over 2N * min(probe_interval) seconds
		IF ((now() - alert_rec.last_flapping_detection_processed) >=
		((2* default_flapping_detection_state_change * min_probe_interval) * '1 second'::interval)) THEN
			UPDATE pem.alert SET last_flapping_detection_processed = now() WHERE id = alert_rec.id;

			IF (alert_rec.state_change_count = 0) THEN
			UPDATE pem.alert SET flapping_detected = 'f' WHERE id = alert_rec.id;
			END IF;
		END IF;
	END IF;

	PERFORM pg_catalog.pg_advisory_unlock(0, alert_rec.id);
	RETURN true;
END;
$$ LANGUAGE plpgsql;

    -- PEM-5595: Creating a trigger to remove the primary tag from the server if the server has pgd extension
    UPDATE pem.probe SET rerun_on_restart='true' WHERE internal_name='oc_extension';
    CREATE OR REPLACE FUNCTION pem.remove_primary_tag_on_bdr()
    RETURNS TRIGGER AS $$
    BEGIN
        -- Only proceed if extension_name contains 'bdr'
        IF NEW.extension_name ILIKE '%bdr%' THEN
            UPDATE pem.server s
            SET tags = COALESCE((
                SELECT jsonb_agg(tag_elem)
                FROM jsonb_array_elements(s.tags) AS tag_elem
                WHERE tag_elem->>'text' IS DISTINCT FROM 'primary'
            ), '[]'::jsonb)
            WHERE s.id = NEW.server_id;
        END IF;

        RETURN NEW;
    END;
    $$ LANGUAGE plpgsql SECURITY DEFINER;

    DROP TRIGGER IF EXISTS trg_remove_primary_tag_on_bdr ON pemdata.oc_extension;
    CREATE TRIGGER trg_remove_primary_tag_on_bdr
    AFTER INSERT OR UPDATE ON pemdata.oc_extension
    FOR EACH ROW
    EXECUTE FUNCTION pem.remove_primary_tag_on_bdr();

    -- PEM-5578: Updating the probe oc_table to display parent_table_name column also
    DO $$
    BEGIN
        -- Step 1: Update the probe code
        UPDATE pem.probe
        SET probe_code = $sql$
            SELECT
                c.relname AS table_name,
                CASE
            WHEN parent.oid IS NOT NULL THEN pg_catalog.quote_ident(pn.nspname) || '.' || pg_catalog.quote_ident(parent.relname)
            ELSE NULL
            END AS parent_table_name,
                (COUNT(i.indexrelid)) > 0 AS has_primary_key
            FROM
                (SELECT oid AS coid, * FROM pg_catalog.pg_class WHERE relkind IN ('r', 'p')) c
            JOIN
                pg_catalog.pg_namespace n ON c.relnamespace = n.oid AND n.nspname = %{schema_name}
            LEFT JOIN
                pg_catalog.pg_index i ON i.indrelid = c.coid AND i.indisprimary
            LEFT JOIN
                pg_inherits inh ON inh.inhrelid = c.coid
            LEFT JOIN
                pg_class parent ON parent.oid = inh.inhparent
            LEFT JOIN
                pg_namespace pn ON parent.relnamespace = pn.oid
            GROUP BY
                c.relname, parent.relname, pn.nspname, n.nspname, parent.oid
        $sql$,
        any_server_version = true
        WHERE internal_name = 'oc_table';

        -- Step 2: Insert column if it doesn't exist
        IF NOT EXISTS (
            SELECT 1
            FROM pem.probe_column
            WHERE probe_id = (SELECT id FROM pem.probe WHERE internal_name = 'oc_table')
              AND internal_name = 'parent_table_name'
        ) THEN
            INSERT INTO pem.probe_column (
                probe_id, internal_name, display_name, display_position, classification,
                sql_data_type, unit_of_value, calculate_pit, discard_history,
                pit_by_default, is_graphable
            )
            SELECT
                (SELECT id FROM pem.probe WHERE internal_name = 'oc_table'),
                v.internal_name, v.display_name, v.display_position, v.classification,
                v.sql_data_type, v.unit_of_value, v.calculate_pit, v.discard_history,
                v.pit_by_default, v.is_graphable
            FROM (
                VALUES
                    ('parent_table_name', 'Parent Table Name', 3, 'm', 'text', '', false, false, false, false)
            ) AS v(internal_name, display_name, display_position, classification,
                  sql_data_type, unit_of_value, calculate_pit, discard_history,
                  pit_by_default, is_graphable);
        END IF;

        -- Step 3: Clean up version mapping and add new column in data/history tables
        DELETE FROM pem.probe_server_version
        WHERE probe_id = (SELECT id FROM pem.probe WHERE internal_name = 'oc_table');

        ALTER TABLE pemdata.oc_table
        ADD COLUMN IF NOT EXISTS parent_table_name TEXT;

        ALTER TABLE pemhistory.oc_table
        ADD COLUMN IF NOT EXISTS parent_table_name TEXT;
    END;
    $$ LANGUAGE plpgsql;

    -- PEM-5682: Updating the Patroni timeline mismatch alert template
    DO $$
    BEGIN
        -- Update the alert template for Patroni timeline mismatch
        UPDATE pem.alert_template set info_sql =$sql$
            SELECT pns.member_name AS "Node", pns.timeline AS "Node TL", pcs.timeline AS "Cluster TL"
            FROM pemdata.patroni_node_status pns
            JOIN pemdata.patroni_cluster_status pcs ON pns.cluster_name = pcs.cluster_name
            WHERE 
            CAST(NULLIF(pns.timeline, '') AS INT) IS NOT NULL AND
            CAST(NULLIF(pcs.timeline, '') AS INT) IS NOT NULL AND
            CAST(pns.timeline AS INT) <> CAST(pcs.timeline AS INT)
            AND pns.server_id = ${server_id};
            $sql$
            WHERE display_name = 'Patroni timeline mismatch'
            AND is_system_template = true;

        UPDATE pem.alert_template set sql =$sql$
            SELECT
                CASE WHEN COUNT(*) > 0 THEN 1 ELSE 0 END AS current_value,
                CASE WHEN COUNT(*) > 0 THEN 'Timeline Mismatch' ELSE 'No Mismatch' END AS display_value
            FROM
                pemdata.patroni_node_status pns
            JOIN
                pemdata.patroni_cluster_status pcs ON pns.cluster_name = pcs.cluster_name
            WHERE 
            CAST(NULLIF(pns.timeline, '') AS INT) IS NOT NULL AND
            CAST(NULLIF(pcs.timeline, '') AS INT) IS NOT NULL AND
            CAST(pns.timeline AS INT) <> CAST(pcs.timeline AS INT)
            AND pns.server_id = ${server_id};
            $sql$
            WHERE display_name = 'Patroni timeline mismatch'
            AND is_system_template = true;
    END $$ LANGUAGE plpgsql;

    -- Added exception handling for no data exception.
	CREATE OR REPLACE FUNCTION pem.generate_cm_chart_data(id int4, OUT idx int4, OUT rtime timestamptz, OUT value numeric)
	RETURNS SETOF RECORD AS $$
	DECLARE
		type         char(1);
		historical   int4;
		extrapolated int4;
		midx         int4;
		topt         text;
		tval         numeric;
		rec          record;
		curs         refcursor;
		points       int4;
		frequency    interval := NULL;
		intv         interval := NULL;
		max_cm_span  int4;
		cutoff_cnt   int4 := 0;
		back         int4 := -1;
		start_time   timestamptz;
		end_time     timestamptz;
		curr_time    timestamptz := now();
		min_recorded_time timestamptz;
		history_sql  text := '';
		prev_tbl     text := '';
	BEGIN
		EXECUTE 'SELECT
		type, historical, extrapolated, midx, tval, toperator,
		COALESCE((SELECT value::int4 FROM pem.config WHERE param like ''cm_data_points_per_report''), 100),
		COALESCE((SELECT value::int4 FROM pem.config WHERE param like ''cm_max_end_date_in_years''), 5)
	FROM pem.capacity_report_chart
	WHERE cid = $1::int4'
			INTO type, historical, extrapolated, midx, tval, topt, points, max_cm_span USING id;

		IF type IS NULL THEN
			-- Couldn't find the chart in capacity_report_chart table
			RAISE EXCEPTION '201';
		END IF;

		OPEN curs SCROLL FOR EXECUTE 'SELECT
		cm.mid AS mid, cm.tbl AS tbl, p.applies_to_id AS applies_to_id,
		cm.metrices[1] AS metric, cm.agg_func[1] AS agg,
		CASE WHEN p.applies_to_id <> 100 THEN (SELECT agent_id FROM pem.agent_server_binding WHERE server_id = s.id) ELSE a.id END agent,
		COALESCE(CASE WHEN p.applies_to_id <> 100 THEN s.id ELSE a.id END, 0) AS object,
		COALESCE(CASE WHEN p.applies_to_id <> 100 THEN s.active ELSE a.active END, false) AS is_active,
		(pv.execution_frequency * ''1 sec''::interval) AS execution_frequency,
		array(SELECT (param).name FROM (SELECT unnest(cm.params) AS param) p) AS names,
		array(SELECT (param).value FROM (SELECT unnest(cm.params) AS param) p) AS vals
	FROM
		pem.chart_metric cm
		LEFT JOIN pem.server s ON (s.id::text = (cm.params[1]).value)
		LEFT JOIN pem.agent  a ON (a.id::text = (cm.params[1]).value)
		LEFT JOIN pem.probe p ON (p.internal_name = cm.tbl)
		LEFT JOIN pem.probe_target_view pv ON (p.id = pv.probe_id AND
			CASE
			WHEN p.target_type_id = 100 THEN pv.agent_id = a.id
			WHEN p.target_type_id = 200 THEN pv.server_id = s.id
			ELSE pv.server_id = s.id AND pv.database_name = (cm.params[2]).value
			END)
	WHERE cm.cid = $1::int4 AND CASE WHEN p.applies_to_id <> 100 THEN s.active ELSE a.active END ORDER BY p.internal_name' USING id;

		-- Find the minimum frequency of the probes
		LOOP
			FETCH curs INTO rec;
			EXIT WHEN NOT FOUND;
			-- Create query to find the least time from when the metrics are available
			IF prev_tbl <> rec.tbl THEN
				IF history_sql <> '' THEN
					history_sql := history_sql || ' UNION ALL ';
				END IF;
				history_sql := history_sql || 'SELECT min(recorded_time) AS r FROM pemhistory.' || pg_catalog.quote_ident(rec.tbl);
				prev_tbl := rec.tbl;
			END IF;

			IF rec.execution_frequency IS NOT NULL THEN
				IF frequency IS NULL THEN
					frequency := rec.execution_frequency;
				ELSEIF frequency > rec.execution_frequency THEN
					frequency := rec.execution_frequency;
				END IF;
				IF type = 'T' THEN
					IF back <> -1 THEN
						back := back + 1;
					ELSEIF rec.mid = midx THEN
						back := 1;
					END IF;
				END IF;
			END IF;
		END LOOP;

		IF frequency IS NULL THEN
			-- No matrices are for the active server or agent
			RAISE EXCEPTION '203';
		END IF;

		history_sql := 'SELECT min(s.r) FROM (' || history_sql || ') s';
		-- Find the least time from when the metrics are available
		EXECUTE history_sql INTO min_recorded_time;

		intv := (historical * '1 day'::interval) / points;
		start_time := curr_time - (historical * '1 day'::interval);
		-- If minimum recorded time for data is greater than start_time it means that data
		-- is available from the recorded time not from the start time.
		IF min_recorded_time > start_time THEN
			start_time := min_recorded_time;
			intv := (curr_time - min_recorded_time) / points;
		END IF;

		IF intv < frequency THEN
			intv := frequency;
		END IF;

		IF type = 'T' THEN
			intv := intv * 2;

			WHILE back >= 0
			LOOP
				MOVE PRIOR IN curs;
				back := back - 1;
			END LOOP;
			FETCH curs INTO rec;
			end_time := curr_time + (max_cm_span * '1 year'::interval);
			-- Start of the new BEGIN block for exception handling
			BEGIN
				EXECUTE 'SELECT pem.linear_trend_threshold($1::text, $2::text, $3::timestamptz, $4::timestamptz,
					$5::numeric, $6::boolean, $7::interval, $8::varchar[], $9::varchar[], 10::int4, $11::int4)'
				INTO cutoff_cnt USING rec.tbl, rec.metric, start_time, curr_time, tval,
					CASE WHEN topt = 'EXCEEDS' THEN true ELSE false END, intv, rec.names,
					rec.vals, max_cm_span, rec.agent;
			EXCEPTION
					WHEN raise_exception THEN
						back := 1;
			END; -- End of the BEGIN block for exception handling
		ELSE
			end_time := curr_time + (extrapolated * '1 day'::interval);
		END IF;

		-- Moving the cursor to the first record now
		MOVE BACKWARD ALL FROM curs;

		LOOP
			FETCH curs INTO rec;
			EXIT WHEN NOT FOUND;

			BEGIN
				RETURN QUERY EXECUTE '
	SELECT
		$1::int4 AS idx, trend_metric_time AS rtime, trend_metric_value::numeric(25, 4) AS value
	FROM pem.linear_trend_analysis($2::text, $3::text, $4::text, $5::timestamptz, $6::timestamptz,
		$7::timestamptz, $8::interval, $9::int4, $10::varchar[], $11::varchar[], $12::int4, $13::int4) WHERE trend_metric_value IS NOT NULL'
				USING rec.mid, rec.tbl, CASE WHEN rec.agg = 'A' THEN 'avg'
					WHEN rec.agg = 'M' THEN 'max' WHEN rec.agg = 'm' THEN 'min'
					WHEN rec.agg = 'F' THEN 'FIRST' ELSE 'avg' END, rec.metric, start_time,
					end_time, curr_time, intv, points, rec.names, rec.vals, cutoff_cnt,
					rec.agent;
				EXCEPTION
					WHEN raise_exception THEN
						back := 1;
			END;
		END LOOP;
	END;
	$$ LANGUAGE plpgsql;

END TRANSACTION;
