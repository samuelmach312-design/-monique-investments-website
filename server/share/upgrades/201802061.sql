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
'SELECT 201802061::integer;'
  LANGUAGE 'sql' IMMUTABLE;
COMMENT ON FUNCTION pem.schema_version() IS 'Returns the version number of the PEM schema';

-- Fixed PEM-482
UPDATE pem.alert_template SET info_sql = $sql$SELECT table_name AS "Table name", database_name AS "Database name",
schema_name AS "Schema name", total_table_size_mb AS "Total table size(MB)"
FROM pemdata.table_size
WHERE	server_id = ${server_id}
AND		database_name = '${database_name}'
AND total_table_size_mb ${comparison_operator} '${threshold_value}'::numeric ORDER BY total_table_size_mb DESC;$sql$
  WHERE display_name = 'Table size in database' AND object_type = 300;

UPDATE pem.alert_template SET info_sql = $sql$SELECT table_name AS "Table name", database_name AS "Database name",
schema_name AS "Schema name", total_table_size_mb AS "Total table size(MB)"
FROM pemdata.table_size
WHERE	server_id = ${server_id}
AND total_table_size_mb ${comparison_operator} '${threshold_value}'::numeric ORDER BY total_table_size_mb DESC;$sql$
  WHERE display_name = 'Table size in server' AND object_type = 200;

UPDATE pem.alert_template SET info_sql = $sql$SELECT si.procpid AS "Process ID", si.usename AS "Username",
        si.backend_start AS "Process start time", si.xact_start AS "Transaction start time", si.query_start AS "Query start time",
        si.is_waiting AS "Is Waiting?", si.is_idle AS "Is Idle?", si.is_idle_in_transaction AS "Is idle in transaction?",
        si.is_vacuum AS "Is vacuum?", si.is_autovacuum AS "Is autovacuum?", si.wait_event_type AS "Wait event type", si.wait_event AS "Wait event",
        (SELECT count(*) AS "Number of idle sessions" FROM pemdata.session_info WHERE server_id = '${server_id}'::integer
          AND database_name = '${database_name}'::text AND is_idle = true),
        (SELECT count(*) AS "Number of waiting sessions" FROM pemdata.session_info WHERE server_id = '${server_id}'::integer
          AND database_name = '${database_name}'::text AND is_waiting = true),
        (SELECT setting AS "Max connection" FROM pemdata.settings WHERE server_id = '${server_id}'::integer AND name = 'max_connections'),
        (SELECT setting AS "Superuser reserved connections" FROM pemdata.settings WHERE server_id = '${server_id}'::integer AND name = 'superuser_reserved_connections')
       FROM
           pemdata.session_info AS si
           JOIN pem.server AS s
           ON si.server_id = s.id
       WHERE
           si.server_id = '${server_id}'::integer
           AND  si.database_name = '${database_name}'::text ORDER BY s.description;$sql$
WHERE display_name = 'Total connections' AND object_type = 300;

UPDATE pem.alert_template SET info_sql = $sql$SELECT si.database_name AS "Database name", si.procpid AS "Process ID", si.usename AS "Username",
        si.backend_start AS "Process start time", si.xact_start AS "Transaction start time", si.query_start AS "Query start time",
        si.is_waiting AS "Is Waiting?", si.is_idle AS "Is Idle?", si.is_idle_in_transaction AS "Is idle in transaction?",
        si.is_vacuum AS "Is vacuum?", si.is_autovacuum AS "Is autovacuum?", si.wait_event_type AS "Wait event type", si.wait_event AS "Wait event",
        (SELECT count(*) AS "Number of idle sessions" FROM pemdata.session_info WHERE server_id = '${server_id}'::integer AND is_idle = true),
        (SELECT count(*) AS "Number of waiting sessions" FROM pemdata.session_info WHERE server_id = '${server_id}'::integer AND is_waiting = true),
        (SELECT setting AS "Max connection" FROM pemdata.settings WHERE server_id = '${server_id}'::integer AND name = 'max_connections'),
        (SELECT setting AS "Superuser reserved connections" FROM pemdata.settings WHERE server_id = '${server_id}'::integer AND name = 'superuser_reserved_connections')
    FROM
        pemdata.session_info AS si
        JOIN pem.server AS s
        ON si.server_id = s.id
    WHERE
        si.server_id = '${server_id}'::integer ORDER BY s.description;$sql$
WHERE display_name = 'Total connections' AND object_type = 200;

UPDATE pem.alert_template SET info_sql =$sql$SELECT se.setting AS "Max connection", st.setting AS "Superuser reserved connections" FROM
    (SELECT setting FROM pemdata.settings WHERE server_id = '${server_id}'::integer AND name = 'max_connections') AS se,
    (SELECT setting FROM pemdata.settings WHERE server_id = '${server_id}'::integer AND name = 'superuser_reserved_connections') AS st;$sql$
WHERE display_name = 'Total connections as percentage of max_connections' AND object_type = 300;

UPDATE pem.alert_template SET info_sql =$sql$SELECT se.setting AS "Max connection", st.setting AS "Superuser reserved connections" FROM
    (SELECT setting FROM pemdata.settings WHERE server_id = '${server_id}'::integer AND name = 'max_connections') AS se,
    (SELECT setting FROM pemdata.settings WHERE server_id = '${server_id}'::integer AND name = 'superuser_reserved_connections') AS st;$sql$
WHERE display_name = 'Total connections as percentage of max_connections' AND object_type = 200;


-- Fixed PEM-483
ALTER TABLE pemdata.session_info ADD COLUMN query text DEFAULT NULL;
ALTER TABLE pemhistory.session_info ADD COLUMN query text DEFAULT NULL;
ALTER TABLE pemdata.session_info ADD COLUMN state text DEFAULT NULL;
ALTER TABLE pemhistory.session_info ADD COLUMN state text DEFAULT NULL;
ALTER TABLE pemdata.session_info ADD COLUMN state_change timestamp with time zone DEFAULT NULL;
ALTER TABLE pemhistory.session_info ADD COLUMN state_change timestamp with time zone DEFAULT NULL;

INSERT INTO pem.probe_column
	(probe_id, internal_name, display_name, display_position, classification,
	sql_data_type, unit_of_value, calculate_pit, discard_history, pit_by_default, is_graphable)
SELECT
	(SELECT id FROM pem.probe WHERE internal_name='session_info'),
	v.internal_name, v.display_name, v.display_position, v.classification,
	v.sql_data_type, v.unit_of_value, v.calculate_pit, v.discard_history, v.pit_by_default, v.is_graphable
FROM
	(VALUES
        ('query', 'Query', 22, 'm', 'text', '', false, false, false, false),
        ('state', 'State', 23, 'm', 'text', '', false, false, false, false),
        ('state_change', 'State Change', 24, 'm', 'timestamp with time zone', '', false, false, false, false)
	) v(internal_name, display_name, display_position, classification,
		sql_data_type, unit_of_value, calculate_pit, discard_history, pit_by_default, is_graphable);

UPDATE pem.probe_server_version SET probe_code = $sql$
SELECT datname AS database_name, pid AS procpid, usename, client_addr, client_port, backend_start,
		xact_start, query_start, waiting AS is_waiting, state = 'idle' AS is_idle,
		state = 'idle in transaction' AS is_idle_in_transaction, query ilike $$VACUUM%$$ as is_vacuum,
		client_port IS NULL AND (query like $$autovacuum:%$$ OR query like $$VACUUM%$$) as is_autovacuum,
		now() AS capture_time, query, state, state_change FROM pg_catalog.pg_stat_activity$sql$
WHERE probe_id = (SELECT id from pem.probe WHERE internal_name = 'session_info')
AND server_version_id IN (10902, 10903, 10904, 10905, 20902, 20903, 20904, 20905);

UPDATE pem.probe_server_version SET probe_code = $sql$
SELECT datname AS database_name, pid AS procpid, usename, client_addr, client_port, backend_start,
		xact_start, query_start, CASE WHEN wait_event IS NULL THEN false ELSE true END AS is_waiting,
		state = 'idle' AS is_idle, state = 'idle in transaction' AS is_idle_in_transaction, query ilike $$VACUUM%$$ as is_vacuum,
		client_port IS NULL AND (query like $$autovacuum:%$$ OR query like $$VACUUM%$$) as is_autovacuum,
		now() AS capture_time, wait_event, wait_event_type, query, state, state_change FROM pg_catalog.pg_stat_activity$sql$
WHERE probe_id = (SELECT id from pem.probe WHERE internal_name = 'session_info')
AND server_version_id IN (10906, 11000, 20906, 21000);

CREATE OR REPLACE FUNCTION pemdata.copy_session_info_to_history()
    RETURNS trigger
    LANGUAGE 'plpgsql'
    COST 100
    VOLATILE NOT LEAKPROOF
AS $BODY$
			BEGIN
				IF (TG_OP = 'INSERT' OR TG_OP = 'UPDATE') THEN
					INSERT INTO pemhistory.session_info (recorded_time, server_id, database_name, procpid, usename, backend_start, xact_start, query_start, is_waiting, is_idle, is_idle_in_transaction, is_vacuum, is_autovacuum, capture_time, client_addr, client_port, memory_usage_mb, swap_usage_mb, cpu_usage, io_read_bytes, io_write_bytes, wait_event_type, wait_event, query, state, state_change) VALUES (NEW.recorded_time, NEW.server_id, NEW.database_name, NEW.procpid, NEW.usename, NEW.backend_start, NEW.xact_start, NEW.query_start, NEW.is_waiting, NEW.is_idle, NEW.is_idle_in_transaction, NEW.is_vacuum, NEW.is_autovacuum, NEW.capture_time, NEW.client_addr, NEW.client_port, NEW.memory_usage_mb, NEW.swap_usage_mb, NEW.cpu_usage, NEW.io_read_bytes, NEW.io_write_bytes, NEW.wait_event_type, NEW.wait_event, NEW.query, NEW.state, NEW.state_change);
					ELSIF EXISTS(SELECT 1 FROM pem.server WHERE id = OLD.server_id) THEN
					INSERT INTO pemhistory.session_info (server_id, procpid) VALUES (OLD.server_id, OLD.procpid);
				END IF;
				RETURN NEW;
			END;
$BODY$;

UPDATE pem.alert_template SET info_sql = $sql$SELECT si.procpid AS "Process ID", si.usename AS "Username",
        si.backend_start AS "Process start time", si.xact_start AS "Transaction start time", si.query_start AS "Query start time",
        si.is_waiting AS "Is Waiting?", si.is_idle AS "Is Idle?", si.is_idle_in_transaction AS "Is idle in transaction?",
        si.is_vacuum AS "Is vacuum?", si.is_autovacuum AS "Is autovacuum?", si.wait_event_type AS "Wait event type", si.wait_event AS "Wait event",
        si.query AS "Query", si.state_change AS "State change time", (now() - si.state_change)::interval AS "State change since"
    FROM
        pemdata.session_info AS si
        JOIN pem.server AS s
        ON si.server_id = s.id
    WHERE
        si.is_idle IS TRUE
        AND si.server_id = '${server_id}'::integer
        AND si.database_name = '${database_name}'::text ORDER BY s.description;$sql$
  WHERE display_name = 'Connections in idle state' AND object_type = 300;

UPDATE pem.alert_template SET info_sql = $sql$SELECT si.database_name AS "Database name", si.procpid AS "Process ID", si.usename AS "Username",
        si.backend_start AS "Process start time", si.xact_start AS "Transaction start time", si.query_start AS "Query start time",
        si.is_waiting AS "Is Waiting?", si.is_idle AS "Is Idle?", si.is_idle_in_transaction AS "Is idle in transaction?",
        si.is_vacuum AS "Is vacuum?", si.is_autovacuum AS "Is autovacuum?", si.wait_event_type AS "Wait event type", si.wait_event AS "Wait event",
        si.query AS "Query", si.state_change AS "State change time", (now() - si.state_change)::interval AS "State change since"
    FROM
        pemdata.session_info AS si
        JOIN pem.server AS s
        ON si.server_id = s.id
    WHERE
        si.is_idle IS TRUE
        AND si.server_id = '${server_id}'::integer ORDER BY s.description;$sql$
  WHERE display_name = 'Connections in idle state' AND object_type = 200;

UPDATE pem.alert_template SET info_sql = $sql$SELECT si.procpid AS "Process ID", si.usename AS "Username",
        si.backend_start AS "Process start time", si.xact_start AS "Transaction start time", si.query_start AS "Query start time",
        si.is_waiting AS "Is Waiting?", si.is_idle AS "Is Idle?", si.is_idle_in_transaction AS "Is idle in transaction?",
        si.is_vacuum AS "Is vacuum?", si.is_autovacuum AS "Is autovacuum?", si.wait_event_type AS "Wait event type", si.wait_event AS "Wait event",
        si.query AS "Query", si.state_change AS "State change time", (now() - si.state_change)::interval AS "State change since"
    FROM
        pemdata.session_info AS si
        JOIN pem.server AS s
        ON si.server_id = s.id
    WHERE
        si.is_idle_in_transaction IS TRUE
        AND si.server_id = '${server_id}'::integer
        AND si.database_name = '${database_name}'::text ORDER BY s.description;$sql$
  WHERE display_name = 'Connections in idle-in-transaction state' AND object_type = 300;

UPDATE pem.alert_template SET info_sql = $sql$SELECT si.database_name AS "Database name", si.procpid AS "Process ID", si.usename AS "Username",
        si.backend_start AS "Process start time", si.xact_start AS "Transaction start time", si.query_start AS "Query start time",
        si.is_waiting AS "Is Waiting?", si.is_idle AS "Is Idle?", si.is_idle_in_transaction AS "Is idle in transaction?",
        si.is_vacuum AS "Is vacuum?", si.is_autovacuum AS "Is autovacuum?", si.wait_event_type AS "Wait event type", si.wait_event AS "Wait event",
        si.query AS "Query", si.state_change AS "State change time", (now() - si.state_change)::interval AS "State change since"
    FROM
        pemdata.session_info AS si
        JOIN pem.server AS s
        ON si.server_id = s.id
    WHERE
        si.is_idle_in_transaction IS TRUE
        AND si.server_id = '${server_id}'::integer ORDER BY s.description;$sql$
  WHERE display_name = 'Connections in idle-in-transaction state' AND object_type = 200;

UPDATE pem.alert_template SET info_sql = $sql$SELECT si.procpid AS "Process ID", si.usename AS "Username",
        si.backend_start AS "Process start time", si.xact_start AS "Transaction start time", si.query_start AS "Query start time",
        si.is_waiting AS "Is Waiting?", si.is_idle AS "Is Idle?", si.is_idle_in_transaction AS "Is idle in transaction?",
        si.is_vacuum AS "Is vacuum?", si.is_autovacuum AS "Is autovacuum?", si.wait_event_type AS "Wait event type", si.wait_event AS "Wait event",
        si.query AS "Query", si.state_change AS "State change time", (now() - si.state_change)::interval AS "State change since"
    FROM
        pemdata.session_info AS si
        JOIN pem.server AS s
        ON si.server_id = s.id
    WHERE
        si.server_id = '${server_id}'::integer
        AND si.database_name = '${database_name}'::text
        AND si.is_idle IS TRUE
        AND (si.capture_time - COALESCE(si.query_start, si.xact_start, si.backend_start))::interval > '${param_1} seconds'::interval ORDER BY s.description;$sql$
  WHERE display_name = 'Long-running idle connections' AND object_type = 300;

UPDATE pem.alert_template SET info_sql = $sql$SELECT si.database_name AS "Database name", si.procpid AS "Process ID", si.usename AS "Username",
        si.backend_start AS "Process start time", si.xact_start AS "Transaction start time", si.query_start AS "Query start time",
        si.is_waiting AS "Is Waiting?", si.is_idle AS "Is Idle?", si.is_idle_in_transaction AS "Is idle in transaction?",
        si.is_vacuum AS "Is vacuum?", si.is_autovacuum AS "Is autovacuum?", si.wait_event_type AS "Wait event type", si.wait_event AS "Wait event",
        si.query AS "Query", si.state_change AS "State change time", (now() - si.state_change)::interval AS "State change since"
    FROM
        pemdata.session_info AS si
        JOIN pem.server AS s
        ON si.server_id = s.id
    WHERE
        si.server_id = '${server_id}'::integer
        AND si.is_idle IS TRUE
        AND (si.capture_time - COALESCE(si.query_start, si.xact_start, si.backend_start))::interval > '${param_1} seconds'::interval ORDER BY s.description;$sql$
  WHERE display_name = 'Long-running idle connections' AND object_type = 200;

UPDATE pem.alert_template SET info_sql = $sql$SELECT si.procpid AS "Process ID", si.usename AS "Username",
        si.backend_start AS "Process start time", si.xact_start AS "Transaction start time", si.query_start AS "Query start time",
        si.is_waiting AS "Is Waiting?", si.is_idle AS "Is Idle?", si.is_idle_in_transaction AS "Is idle in transaction?",
        si.is_vacuum AS "Is vacuum?", si.is_autovacuum AS "Is autovacuum?", si.wait_event_type AS "Wait event type", si.wait_event AS "Wait event",
        si.query AS "Query", si.state_change AS "State change time", (now() - si.state_change)::interval AS "State change since"
    FROM
        pemdata.session_info AS si
        JOIN pem.server AS s
        ON si.server_id = s.id
    WHERE
        si.server_id = '${server_id}'::integer
        AND si.database_name = '${database_name}'::text
        AND (si.is_idle IS TRUE OR si.is_idle_in_transaction IS TRUE)
        AND (si.capture_time - COALESCE(si.query_start, si.xact_start, si.backend_start))::interval > '${param_1} seconds'::interval ORDER BY s.description;$sql$
  WHERE display_name = 'Long-running idle connections and idle transactions' AND object_type = 300;

UPDATE pem.alert_template SET info_sql = $sql$SELECT si.database_name AS "Database name", si.procpid AS "Process ID", si.usename AS "Username",
        si.backend_start AS "Process start time", si.xact_start AS "Transaction start time", si.query_start AS "Query start time",
        si.is_waiting AS "Is Waiting?", si.is_idle AS "Is Idle?", si.is_idle_in_transaction AS "Is idle in transaction?",
        si.is_vacuum AS "Is vacuum?", si.is_autovacuum AS "Is autovacuum?", si.wait_event_type AS "Wait event type", si.wait_event AS "Wait event",
        si.query AS "Query", si.state_change AS "State change time", (now() - si.state_change)::interval AS "State change since"
    FROM
        pemdata.session_info AS si
        JOIN pem.server AS s
        ON si.server_id = s.id
    WHERE
        si.server_id = '${server_id}'::integer
        AND (si.is_idle IS TRUE OR si.is_idle_in_transaction IS TRUE)
        AND (si.capture_time - COALESCE(si.query_start, si.xact_start, si.backend_start))::interval > '${param_1} seconds'::interval ORDER BY s.description;$sql$
  WHERE display_name = 'Long-running idle connections and idle transactions' AND object_type = 200;

UPDATE pem.alert_template SET info_sql = $sql$SELECT si.procpid AS "Process ID", si.usename AS "Username",
        si.backend_start AS "Process start time", si.xact_start AS "Transaction start time", si.query_start AS "Query start time",
        si.is_waiting AS "Is Waiting?", si.is_idle AS "Is Idle?", si.is_idle_in_transaction AS "Is idle in transaction?",
        si.is_vacuum AS "Is vacuum?", si.is_autovacuum AS "Is autovacuum?", si.wait_event_type AS "Wait event type", si.wait_event AS "Wait event",
        si.query AS "Query", si.state_change AS "State change time", (now() - si.state_change)::interval AS "State change since"
    FROM
        pemdata.session_info AS si
        JOIN pem.server AS s
        ON si.server_id = s.id
    WHERE
        si.server_id = '${server_id}'::integer
        AND si.database_name = '${database_name}'::text
        AND si.is_idle_in_transaction IS TRUE
        AND (si.capture_time - COALESCE(si.query_start, si.xact_start, si.backend_start))::interval > '${param_1} seconds'::interval ORDER BY s.description;$sql$
  WHERE display_name = 'Long-running idle transactions' AND object_type = 300;

UPDATE pem.alert_template SET info_sql = $sql$SELECT si.database_name AS "Database name", si.procpid AS "Process ID", si.usename AS "Username",
        si.backend_start AS "Process start time", si.xact_start AS "Transaction start time", si.query_start AS "Query start time",
        si.is_waiting AS "Is Waiting?", si.is_idle AS "Is Idle?", si.is_idle_in_transaction AS "Is idle in transaction?",
        si.is_vacuum AS "Is vacuum?", si.is_autovacuum AS "Is autovacuum?", si.wait_event_type AS "Wait event type", si.wait_event AS "Wait event",
        si.query AS "Query", si.state_change AS "State change time", (now() - si.state_change)::interval AS "State change since"
    FROM
        pemdata.session_info AS si
        JOIN pem.server AS s
        ON si.server_id = s.id
    WHERE
        si.server_id = '${server_id}'::integer
        AND si.is_idle_in_transaction IS TRUE
        AND (si.capture_time - COALESCE(si.query_start, si.xact_start, si.backend_start))::interval > '${param_1} seconds'::interval ORDER BY s.description;$sql$
  WHERE display_name = 'Long-running idle transactions' AND object_type = 200;

UPDATE pem.alert_template SET info_sql = $sql$SELECT si.procpid AS "Process ID", si.usename AS "Username",
        si.backend_start AS "Process start time", si.xact_start AS "Transaction start time", si.query_start AS "Query start time",
        si.is_waiting AS "Is Waiting?", si.is_idle AS "Is Idle?", si.is_idle_in_transaction AS "Is idle in transaction?",
        si.is_vacuum AS "Is vacuum?", si.is_autovacuum AS "Is autovacuum?", si.wait_event_type AS "Wait event type", si.wait_event AS "Wait event",
        si.query AS "Query", si.state AS "State", si.state_change AS "State change time", (now() - si.state_change)::interval AS "State change since"
    FROM
        pemdata.session_info AS si
        JOIN pem.server AS s
        ON si.server_id = s.id
    WHERE
        si.server_id = '${server_id}'::integer
        AND si.database_name = '${database_name}'::text
        AND si.xact_start IS NOT NULL
        AND (si.capture_time - si.xact_start) > '${param_1} seconds'::interval ORDER BY s.description;$sql$
  WHERE display_name = 'Long-running transactions' AND object_type = 300;

UPDATE pem.alert_template SET info_sql = $sql$SELECT si.database_name AS "Database name", si.procpid AS "Process ID", si.usename AS "Username",
        si.backend_start AS "Process start time", si.xact_start AS "Transaction start time", si.query_start AS "Query start time",
        si.is_waiting AS "Is Waiting?", si.is_idle AS "Is Idle?", si.is_idle_in_transaction AS "Is idle in transaction?",
        si.is_vacuum AS "Is vacuum?", si.is_autovacuum AS "Is autovacuum?", si.wait_event_type AS "Wait event type", si.wait_event AS "Wait event",
        si.query AS "Query", si.state AS "State", si.state_change AS "State change time", (now() - si.state_change)::interval AS "State change since"
    FROM
        pemdata.session_info AS si
        JOIN pem.server AS s
        ON si.server_id = s.id
    WHERE
        si.server_id = '${server_id}'::integer
        AND si.xact_start IS NOT NULL
        AND (si.capture_time - si.xact_start) > '${param_1} seconds'::interval ORDER BY s.description;$sql$
  WHERE display_name = 'Long-running transactions' AND object_type = 200;

UPDATE pem.alert_template SET info_sql = $sql$SELECT si.procpid AS "Process ID", si.usename AS "Username",
        si.backend_start AS "Process start time", si.xact_start AS "Transaction start time", si.query_start AS "Query start time",
        si.is_waiting AS "Is Waiting?", si.is_idle AS "Is Idle?", si.is_idle_in_transaction AS "Is idle in transaction?",
        si.is_vacuum AS "Is vacuum?", si.is_autovacuum AS "Is autovacuum?", si.wait_event_type AS "Wait event type", si.wait_event AS "Wait event",
        si.query AS "Query", si.state AS "State", si.state_change AS "State change time", (now() - si.state_change)::interval AS "State change since"
    FROM
        pemdata.session_info AS si
        JOIN pem.server AS s
        ON si.server_id = s.id
    WHERE
        si.server_id = '${server_id}'::integer
        AND si.database_name = '${database_name}'::text
        AND si.is_idle = false
        AND si.is_idle_in_transaction = false
        AND si.query_start IS NOT NULL
        AND (si.capture_time - si.query_start) > '${param_1} seconds'::interval ORDER BY s.description;$sql$
  WHERE display_name = 'Long-running queries' AND object_type = 300;

UPDATE pem.alert_template SET info_sql = $sql$SELECT si.database_name AS "Database name", si.procpid AS "Process ID", si.usename AS "Username",
        si.backend_start AS "Process start time", si.xact_start AS "Transaction start time", si.query_start AS "Query start time",
        si.is_waiting AS "Is Waiting?", si.is_idle AS "Is Idle?", si.is_idle_in_transaction AS "Is idle in transaction?",
        si.is_vacuum AS "Is vacuum?", si.is_autovacuum AS "Is autovacuum?", si.wait_event_type AS "Wait event type", si.wait_event AS "Wait event",
        si.query AS "Query", si.state AS "State", si.state_change AS "State change time", (now() - si.state_change)::interval AS "State change since"
    FROM
        pemdata.session_info AS si
        JOIN pem.server AS s
        ON si.server_id = s.id
    WHERE
        si.server_id = '${server_id}'::integer
        AND si.is_idle = false
        AND si.is_idle_in_transaction = false
        AND si.query_start IS NOT NULL
        AND (si.capture_time - si.query_start) > '${param_1} seconds'::interval ORDER BY s.description;$sql$
  WHERE display_name = 'Long-running queries' AND object_type = 200;

UPDATE pem.alert_template SET info_sql = $sql$SELECT si.procpid AS "Process ID", si.usename AS "Username",
        si.backend_start AS "Process start time", si.xact_start AS "Transaction start time", si.query_start AS "Query start time",
        si.is_waiting AS "Is Waiting?", si.is_idle AS "Is Idle?", si.is_idle_in_transaction AS "Is idle in transaction?",
        si.is_vacuum AS "Is vacuum?", si.is_autovacuum AS "Is autovacuum?", si.wait_event_type AS "Wait event type", si.wait_event AS "Wait event",
        si.query AS "Query", si.state AS "State", si.state_change AS "State change time", (now() - si.state_change)::interval AS "State change since"
    FROM
        pemdata.session_info AS si
        JOIN pem.server AS s
        ON si.server_id = s.id
    WHERE
        si.server_id = '${server_id}'::integer
        AND si.database_name = '${database_name}'::text
        AND si.is_vacuum = true
        AND (si.capture_time - si.query_start) > '${param_1} seconds'::interval ORDER BY s.description;$sql$
  WHERE display_name = 'Long-running vacuums' AND object_type = 300;

UPDATE pem.alert_template SET info_sql = $sql$SELECT si.database_name AS "Database name",
        si.procpid AS "Process ID", si.usename AS "Username", si.backend_start AS "Process start time", si.xact_start AS "Transaction start time",
        si.query_start AS "Query start time", si.is_waiting AS "Is Waiting?", si.is_idle AS "Is Idle?",
        si.is_idle_in_transaction AS "Is idle in transaction?", si.is_vacuum AS "Is vacuum?", si.is_autovacuum AS "Is autovacuum?",
        si.wait_event_type AS "Wait event type", si.wait_event AS "Wait event",
        si.query AS "Query", si.state AS "State", si.state_change AS "State change time", (now() - si.state_change)::interval AS "State change since"
    FROM
        pemdata.session_info AS si
        JOIN pem.server AS s
        ON si.server_id = s.id
    WHERE
        si.server_id = '${server_id}'::integer
        AND si.is_vacuum = true
        AND (si.capture_time - si.query_start) > '${param_1} seconds'::interval ORDER BY s.description;$sql$
  WHERE display_name = 'Long-running vacuums' AND object_type = 200;

UPDATE pem.alert_template SET info_sql = $sql$SELECT si.procpid AS "Process ID", si.usename AS "Username",
        si.backend_start AS "Process start time", si.xact_start AS "Transaction start time", si.query_start AS "Query start time",
        si.is_waiting AS "Is Waiting?", si.is_idle AS "Is Idle?", si.is_idle_in_transaction AS "Is idle in transaction?",
        si.is_vacuum AS "Is vacuum?", si.is_autovacuum AS "Is autovacuum?", si.wait_event_type AS "Wait event type", si.wait_event AS "Wait event",
        si.query AS "Query", si.state AS "State", si.state_change AS "State change time", (now() - si.state_change)::interval AS "State change since"
    FROM
        pemdata.session_info AS si
        JOIN pem.server AS s
        ON si.server_id = s.id
    WHERE
        si.server_id = '${server_id}'::integer
        AND si.database_name = '${database_name}'::text
        AND si.is_autovacuum = true
        AND (si.capture_time - si.query_start) > '${param_1} seconds'::interval ORDER BY s.description;$sql$
  WHERE display_name = 'Long-running autovacuums' AND object_type = 300;

UPDATE pem.alert_template SET info_sql = $sql$SELECT si.database_name AS "Database name",
        si.procpid AS "Process ID", si.usename AS "Username",
        si.backend_start AS "Process start time", si.xact_start AS "Transaction start time", si.query_start AS "Query start time",
        si.is_waiting AS "Is Waiting?", si.is_idle AS "Is Idle?", si.is_idle_in_transaction AS "Is idle in transaction?",
        si.is_vacuum AS "Is vacuum?", si.is_autovacuum AS "Is autovacuum?", si.wait_event_type AS "Wait event type", si.wait_event AS "Wait event",
        si.query AS "Query", si.state AS "State", si.state_change AS "State change time", (now() - si.state_change)::interval AS "State change since"
    FROM
        pemdata.session_info AS si
        JOIN pem.server AS s
        ON si.server_id = s.id
    WHERE
        si.server_id = '${server_id}'::integer
        AND si.is_autovacuum = true
        AND (si.capture_time - si.query_start) > '${param_1} seconds'::interval ORDER BY s.description;$sql$
  WHERE display_name = 'Long-running autovacuums' AND object_type = 200;

COMMIT TRANSACTION;
