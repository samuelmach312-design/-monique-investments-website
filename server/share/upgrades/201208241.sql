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

-- Upgrade script for 3.0.0b1 to 3.0.0b2

BEGIN TRANSACTION;

CREATE OR REPLACE FUNCTION pem.schema_version()
  RETURNS integer AS
'SELECT 201208241::integer;'
  LANGUAGE 'sql' IMMUTABLE;

-- Set a variable for PEM Validation Key in Config table
INSERT INTO pem.config (param, datatype) VALUES ('web_client_product_key','string');
-- log_silent_mode can be NULL for >=9.2
ALTER TABLE pem.log_configuration ALTER COLUMN log_silent_mode DROP NOT NULL;
-- purge server_logs
INSERT INTO pem.config (param, value, unit, datatype) VALUES ('server_log_retention_time', '30', 'days', 'integer');

CREATE OR REPLACE FUNCTION pem.purge_data()
  RETURNS void AS
$BODY$
DECLARE
    curs_probe CURSOR FOR
	SELECT probe_internal_name, parameter_name_list,
	   parameter_value_list, lifetime
	FROM pem.probe_target_view;

    table_name varchar;
    parameter_name_list text[];
    parameter_value_list text[];
    lifetime integer;

    i integer; -- Counter
    where_clause varchar;
    subquery varchar;

BEGIN

    FOR probe IN curs_probe LOOP

	table_name := 'pemhistory.' || quote_ident(probe.probe_internal_name);
	parameter_name_list := probe.parameter_name_list;
	parameter_value_list := probe.parameter_value_list;
	lifetime := probe.lifetime;

	where_clause := 'WHERE ';

	FOR i IN array_lower(parameter_name_list, 1)..array_upper(parameter_name_list, 1)
	LOOP
	    where_clause := where_clause || parameter_name_list[i] || ' = ' || quote_literal(parameter_value_list[i]) || ' AND ';
	END LOOP;

	where_clause := where_clause || 'recorded_time < (now() - interval ''' || lifetime || ' days'' ) ';

	subquery := 'SELECT recorded_time FROM ' || table_name || ' ' || where_clause || 'ORDER BY recorded_time DESC LIMIT 1';

	where_clause := where_clause || ' AND recorded_time < (' || subquery || ')';

	EXECUTE 'DELETE FROM ' || table_name || ' ' || where_clause;

    END LOOP;

    -- Purge data from alert history table
	DELETE FROM pem.alert_history AS h
	USING pem.alert AS a
	WHERE a.id = h.alert_id
	AND (now() - h.generated) >= (a.history_retention||'days')::interval;

    -- Purge data from probe log table
	DELETE FROM pem.probe_log
	WHERE (now() - recorded_time) >= ((SELECT value FROM pem.config WHERE param = 'probe_log_retention_time')||'days')::interval;

    -- Purge data from audit log table
	DELETE FROM pemdata.audit_logs
	WHERE (now() - log_time) >= ((SELECT value FROM pem.config WHERE param = 'audit_log_retention_time')||'days')::interval;

    -- Purge data from server log table
	DELETE FROM pemdata.server_logs
	WHERE (now() - log_time) >= ((SELECT value FROM pem.config WHERE param = 'server_log_retention_time')||'days')::interval;

    -- Purge old jobs, steps and schedules
	DELETE FROM pem.job
	WHERE jobnextrun IS NULL
	AND (now() - joblastrun) >= ((SELECT value FROM pem.config WHERE param = 'job_retention_time')||'days')::interval;

    -- Purge job log and job step log
	DELETE FROM pem.joblog AS jl
	WHERE (now() - jl.jlgstart) >= ((SELECT value FROM pem.config WHERE param = 'job_retention_time')||'days')::interval;

    -- Purge smtp spool table
	PERFORM pem.purge_smtp_spool();

    -- Purge snmp spool table
	PERFORM pem.purge_snmp_spool();

END;
$BODY$ LANGUAGE plpgsql;

COMMIT TRANSACTION;
