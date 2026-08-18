BEGIN;
DO
$$
DECLARE
    min_sample_time timestamptz;
    start_time      timestamptz;
    rows_inserted   integer;
    exit_loop       bool := FALSE;
BEGIN
    DROP TABLE IF EXISTS "_pem_wait_event_query_time_tmp_{session_id}";
    CREATE TEMPORARY TABLE "_pem_wait_event_query_time_tmp_{session_id}" (
        sample_time double precision,
        wait_event_types text,
        wait_events text
    ) ON COMMIT DROP;
    min_sample_time := to_timestamp({sample_start_time}::float - 1);

    WHILE exit_loop = FALSE LOOP
        EXECUTE $SQL$
            INSERT INTO "_pem_wait_event_query_time_tmp_{session_id}"
            SELECT
                EXTRACT(EPOCH FROM sample_time) * 1000 AS sample_time,
                COALESCE(wait_event_type::text, 'CPU'::text)
                    AS wait_event_types,
                COALESCE(wait_event::text, 'CPU'::text) AS wait_events
            FROM edb_wait_states_samples(
                $1,
                $1 + interval '15 minutes'
            )
            WHERE query_id = {query_id}::int8 AND
                session_id = {session_id}::int4 AND
                query_start_time = '{query_start_time}'::timestamptz
        $SQL$ USING min_sample_time;

        GET DIAGNOSTICS rows_inserted = ROW_COUNT;

        IF rows_inserted = 0 THEN
            exit_loop := TRUE;
        ELSE
            min_sample_time := min_sample_time + INTERVAL '15 minutes';
        END IF;
    END LOOP;
END;
$$ LANGUAGE plpgsql;

SELECT
    sample_time, wait_event_types, wait_events
FROM "_pem_wait_event_query_time_tmp_{session_id}"
ORDER BY 1, 2, 3
