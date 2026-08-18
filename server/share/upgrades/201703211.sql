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
  'SELECT 201703211::integer;'
    LANGUAGE 'sql' IMMUTABLE;
    COMMENT ON FUNCTION pem.schema_version() IS 'Returns the version number of the PEM schema';

UPDATE
    pem.config
SET
    value='http://www.enterprisedb.com/docs/en/9.6/pg/index.html'
WHERE
    param = 'webclient_help_pg';

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
-- OR
--
-- process 3672 still waiting for ShareLock on transaction 1323 after 1000.128 ms
--
-- OR
--
-- process 94215 still waiting for AccessExclusiveLock on tuple (0,18) of relation 16384 of database 13963 after 1001.105 ms
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
						     CASE WHEN 'AccessShareLock' ~~* SUBSTRING(message FROM '[a-zA-Z]+(?= on .* after [0-9\.]+ ms$)') THEN 1 ELSE 0 END,
						     CASE WHEN 'RowShareLock' ~~* SUBSTRING(message FROM '[a-zA-Z]+(?= on .* after [0-9\.]+ ms$)') THEN 1 else 0 END,
						     CASE WHEN 'RowExclusiveLock' ~~* SUBSTRING(message FROM '[a-zA-Z]+(?= on .* after [0-9\.]+ ms$)') then 1 else 0 END,
						     CASE WHEN 'ShareUpdateExclusiveLock' ~~* SUBSTRING(message FROM '[a-zA-Z]+(?= on .* after [0-9\.]+ ms$)') then 1 else 0 END,
						     CASE WHEN 'ShareLock' ~~* SUBSTRING(message FROM '[a-zA-Z]+(?= on .* after [0-9\.]+ ms$)') then 1 else 0 END,
						     CASE WHEN 'ShareRowExclusiveLock' ~~* SUBSTRING(message FROM '[a-zA-Z]+(?= on .* after [0-9\.]+ ms$)') then 1 else 0 END,
						     CASE WHEN 'ExclusiveLock' ~~* SUBSTRING(message FROM '[a-zA-Z]+(?= on .* after [0-9\.]+ ms$)') then 1 else 0 END,
						     CASE WHEN 'AccessExclusiveLock' ~~* SUBSTRING(message FROM '[a-zA-Z]+(?= on .* after [0-9\.]+ ms$)') THEN 1 ELSE 0 END
						    ]
					      ) as metric_value
				FROM
					pemdata.server_logs
				WHERE
					error_severity = 'LOG' AND message LIKE 'process %' AND
					message ~ '^process \d+ still waiting for [a-zA-Z]+ on .* after [0-9\.]+ ms$' AND
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

UPDATE pem.config SET
	value = CASE WHEN value = 'true' THEN 't' ELSE 'f' END,
	unit = 't/f', datatype = 'bool'
WHERE param = 'show_data_tab_on_graph';

UPDATE pem.config SET datatype = 'password'
WHERE param in ('smtp_password', 'proxy_server_password');

-- Function to create unique service name for nagios
CREATE OR REPLACE FUNCTION pem.create_nagios_service_name(
    alert_name text,
    server_name text DEFAULT NULL::text,
    database_name text DEFAULT NULL::text,
    schema_name text DEFAULT NULL::text,
    package_name text DEFAULT NULL::text,
    object_name text DEFAULT NULL::text)
  RETURNS text AS
$BODY$
DECLARE
    service_name_text    text := '';
    new_alert_name       text := '';
BEGIN

        new_alert_name = regexp_replace(regexp_replace(alert_name, E'[`~$%^&*|''"<>?,(=]','-'), E'[)]', '-');
        service_name_text = E'' || new_alert_name || CASE WHEN (server_name IS NOT NULL AND server_name != '') THEN ' - svr: ' || server_name ELSE '' END || CASE WHEN (database_name IS NOT NULL AND database_name != '') THEN ' - db: ' || database_name ELSE '' END || CASE WHEN (schema_name IS NOT NULL AND schema_name != '') THEN ' - schema: ' || schema_name ELSE '' END || CASE WHEN (package_name IS NOT NULL AND package_name != '') THEN ' - pkg: ' || package_name ELSE '' END || CASE WHEN (object_name IS NOT NULL AND object_name != '') THEN ' - obj: ' || object_name ELSE '' END || E'';

RETURN service_name_text;

END
$BODY$
  LANGUAGE plpgsql;

-- Function to create nagios hosts.cfg file
CREATE OR REPLACE FUNCTION pem.create_nagios_host_config(
    template_name text DEFAULT NULL::text,
    is_max_check_attemp_require boolean DEFAULT FALSE::boolean,
    icon_image text DEFAULT NULL::text,
    icon_image_alt text DEFAULT NULL::text,
    statusmap_image text DEFAULT NULL::text)
  RETURNS text AS
$BODY$

DECLARE
    host_config_text    text := '';
    row                 RECORD;
BEGIN
    FOR row IN SELECT DISTINCT ON (pa.description) pa.description, ps.server FROM pem.agent pa LEFT JOIN pem.agent_server_binding pasb ON (pa.id = pasb.agent_id) LEFT JOIN pem.server ps ON (ps.id = pasb.server_id)  WHERE pa.active = true AND ps.active = true
    LOOP
        host_config_text = host_config_text || E'define host {
        host_name                ' || row.description || E'
        address                  ' || row.server || E'
        active_checks_enabled    1
        passive_checks_enabled   1
        check_command            check-host-alive';

        IF is_max_check_attemp_require THEN
            host_config_text = host_config_text || E'\n        max_check_attempts       10';
        END IF;

        IF icon_image IS NOT NULL THEN
            host_config_text = host_config_text || E'\n        icon_image               ' || icon_image;
        END IF;

        IF icon_image_alt IS NOT NULL THEN
            host_config_text = host_config_text || E'\n        icon_image_alt           ' || icon_image_alt;
        ELSE
            host_config_text = host_config_text || E'\n        icon_image_alt           ' || row.description;
        END IF;

        IF statusmap_image IS NOT NULL THEN
            host_config_text = host_config_text || E'\n        statusmap_image          ' || statusmap_image;
        END IF;

        IF template_name IS NOT NULL THEN
            host_config_text = host_config_text || E'\n        use                      ' || template_name;
        END IF;
        host_config_text = host_config_text ||    E'\n}\n\n';
    END LOOP;

RETURN host_config_text;

END

$BODY$
  LANGUAGE plpgsql;

COMMIT TRANSACTION;
