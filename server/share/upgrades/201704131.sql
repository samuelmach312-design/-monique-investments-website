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
  'SELECT 201704131::integer;'
    LANGUAGE 'sql' IMMUTABLE;
    COMMENT ON FUNCTION pem.schema_version() IS 'Returns the version number of the PEM schema';

-- To make analyzer name same as chart header name in Postgres Log Analysis Expert reports
UPDATE pem.logexp_charts SET
    analyzer_name = 'COMMIT/ROLLBACK Statistics',
    chart_headers = 'COMMIT/ROLLBACK Statistics Timeline'
WHERE id = 5;

UPDATE pem.logexp_charts SET
    analyzer_name = 'CHECKPOINT Statistics'
WHERE id = 6;

UPDATE pem.logexp_charts SET
    chart_headers = 'Log Event Statistics'
WHERE id = 7;

UPDATE pem.logexp_charts SET
    chart_headers = 'Log Statistics'
WHERE id = 8;

UPDATE pem.logexp_charts SET
    analyzer_name = 'Temporary Query Statistics',
    chart_headers = 'Temporary Query Statistics'
WHERE id = 9;

UPDATE pem.logexp_charts SET
    analyzer_name = 'Temporary File Statistics',
    chart_headers = 'Temporary File Statistics Timeline'
WHERE id = 10;

UPDATE pem.logexp_charts SET
    analyzer_name = 'Waiting Statistics'
WHERE id = 12;

UPDATE pem.logexp_charts SET
    chart_headers = 'Autovacuum Statistics'
WHERE id = 14;

UPDATE pem.logexp_charts SET
    chart_headers = 'Autoanalyze Statistics'
WHERE id = 15;

UPDATE pem.logexp_charts SET
    chart_headers = 'Slow Running Query Statistics'
WHERE id = 16;

UPDATE pem.logexp_charts SET
    chart_headers = 'Most Time Consumed Query Statistics'
WHERE id = 18;

UPDATE pem.alert_template SET description='Number of CPUs running at greater than K% utilization specified in "Parameter Options" section.' WHERE display_name = 'Number of CPUs running higher than a threshold';

UPDATE pem.alert_template SET description='Disk space consumed (in megabytes) specified by mount point in "Parameter Options" section.' WHERE display_name = 'Disk Consumption';

UPDATE pem.alert_template SET description='Percentage of disk consumed specified by mount point in "Parameter Options" section.' WHERE display_name = 'Disk consumption percentage';

UPDATE pem.alert_template SET description='Disk space available (in megabytes) specified by mount point in "Parameter Options" section.' WHERE display_name = 'Disk Available';

UPDATE pem.alert_template SET description='Percentage of disk busy specified by mount point in "Parameter Options" section.' WHERE display_name = 'Disk busy percentage';

UPDATE pem.alert_template SET description='Largest table in schema, calculated as a multiple of its own estimated unbloated size; exclude tables smaller than N MB specified in "Parameter Options" section.' WHERE display_name = 'Largest table (by multiple of unbloated size)' AND object_type = 400;

UPDATE pem.alert_template SET description='Largest table in database, calculated as a multiple of its own estimated unbloated size; exclude tables smaller than N MB specified in "Parameter Options" section.' WHERE display_name = 'Largest table (by multiple of unbloated size)' AND object_type = 300;

UPDATE pem.alert_template SET description='Largest table in server, calculated as a multiple of its own estimated unbloated size; exclude tables smaller than N MB specified in "Parameter Options" section.' WHERE display_name = 'Largest table (by multiple of unbloated size)' AND object_type = 200;

UPDATE pem.alert_template SET description='Number of connections in the database that have been idle for more than N seconds specified in "Parameter Options" section.' WHERE display_name = 'Long-running idle connections' AND object_type = 300;

UPDATE pem.alert_template SET description='Number of connections in the server that have been idle for more than N seconds specified in "Parameter Options" section.' WHERE display_name = 'Long-running idle connections' AND object_type = 200;

UPDATE pem.alert_template SET description='Number of connections in the database that have been idle or idle-in-transaction for more than N seconds specified in "Parameter Options" section.' WHERE display_name = 'Long-running idle connections and idle transactions' AND object_type = 300;

UPDATE pem.alert_template SET description='Number of connections in the server that have been idle or idle-in-transaction for more than N seconds specified in "Parameter Options" section.' WHERE display_name = 'Long-running idle connections and idle transactions' AND object_type = 200;

UPDATE pem.alert_template SET description='Number of connections in the database that have been idle in transaction for more than N seconds specified in "Parameter Options" section.' WHERE display_name = 'Long-running idle transactions' AND object_type = 300;

UPDATE pem.alert_template SET description='Number of connections in the server that have been idle in transaction for more than N seconds specified in "Parameter Options" section.' WHERE display_name = 'Long-running idle transactions' AND object_type = 200;

UPDATE pem.alert_template SET description='Number of transactions in database that have been running for more than N seconds specified in "Parameter Options" section.' WHERE display_name = 'Long-running transactions' AND object_type = 300;

UPDATE pem.alert_template SET description='Number of transactions in server that have been running for more than N seconds specified in "Parameter Options" section.' WHERE display_name = 'Long-running transactions' AND object_type = 200;

UPDATE pem.alert_template SET description='Number of queries in database that have been running for more than N seconds specified in "Parameter Options" section.' WHERE display_name = 'Long-running queries' AND object_type = 300;

UPDATE pem.alert_template SET description='Number of queries in server that have been running for more than N seconds specified in "Parameter Options" section.' WHERE display_name = 'Long-running queries' AND object_type = 200;

UPDATE pem.alert_template SET description='Number of vacuum operations in database that have been running for more than N seconds specified in "Parameter Options" section.' WHERE display_name = 'Long-running vacuums' AND object_type = 300;

UPDATE pem.alert_template SET description='Number of vacuum operations in server that have been running for more than N seconds specified in "Parameter Options" section.' WHERE display_name = 'Long-running vacuums' AND object_type = 200;

UPDATE pem.alert_template SET description='Number of autovacuum operations in database that have been running for more than N seconds specified in "Parameter Options" section.' WHERE display_name = 'Long-running autovacuums' AND object_type = 300;

UPDATE pem.alert_template SET description='Number of autovacuum operations in server that have been running for more than N seconds specified in "Parameter Options" section.' WHERE display_name = 'Long-running autovacuums' AND object_type = 200;

UPDATE pem.alert_template SET description='Percentage of transactions in the database that committed vs. that rolled-back over last N minutes specified in "Parameter Options" section.' WHERE display_name = 'Committed transactions percentage' AND object_type = 300;

UPDATE pem.alert_template SET description='Percentage of transactions in the server that committed vs. that rolled-back over last N minutes specified in "Parameter Options" section.' WHERE display_name = 'Committed transactions percentage' AND object_type = 200;

UPDATE pem.alert_template SET description='Percentage of block read requests in the database that were satisfied by shared buffers, over last N minutes specified in "Parameter Options" section.' WHERE display_name = 'Shared buffers hit percentage' AND object_type = 300;

UPDATE pem.alert_template SET description='Percentage of block read requests in the server that were satisfied by shared buffers, over last N minutes specified in "Parameter Options" section.' WHERE display_name = 'Shared buffers hit percentage' AND object_type = 200;

UPDATE pem.alert_template SET description='Percentage of block read requests in the database that were satisfied by InfiniteCache, over last N minutes specified in "Parameter Options" section.' WHERE display_name = 'InfiniteCache buffers hit percentage' AND object_type = 300;

UPDATE pem.alert_template SET description='Percentage of block read requests in the server that were satisfied by InfiniteCache, over last N minutes specified in "Parameter Options" section.' WHERE display_name = 'InfiniteCache buffers hit percentage' AND object_type = 200;

UPDATE pem.alert_template SET description='Tuples fetched from database over last N minutes specified in "Parameter Options" section.' WHERE display_name = 'Tuples fetched' AND object_type = 300;

UPDATE pem.alert_template SET description='Tuples fetched from server over last N minutes specified in "Parameter Options" section.' WHERE display_name = 'Tuples fetched' AND object_type = 200;

UPDATE pem.alert_template SET description='Tuples returned from database over last N minutes specified in "Parameter Options" section.' WHERE display_name = 'Tuples returned' AND object_type = 300;

UPDATE pem.alert_template SET description='Tuples returned from server over last N minutes specified in "Parameter Options" section.' WHERE display_name = 'Tuples returned' AND object_type = 200;

UPDATE pem.alert_template SET description='Tuples inserted in table over last N minutes specified in "Parameter Options" section.' WHERE display_name = 'Tuples inserted' AND object_type = 500;

UPDATE pem.alert_template SET description='Tuples inserted in schema over last N minutes specified in "Parameter Options" section.' WHERE display_name = 'Tuples inserted' AND object_type = 400;

UPDATE pem.alert_template SET description='Tuples inserted into database over last N minutes specified in "Parameter Options" section.' WHERE display_name = 'Tuples inserted' AND object_type = 300;

UPDATE pem.alert_template SET description='Tuples inserted into server over last N minutes specified in "Parameter Options" section.' WHERE display_name = 'Tuples inserted' AND object_type = 200;

UPDATE pem.alert_template SET description='Tuples updated in table over last N minutes specified in "Parameter Options" section.' WHERE display_name = 'Tuples updated' AND object_type = 500;

UPDATE pem.alert_template SET description='Tuples updated in schema over last N minutes specified in "Parameter Options" section.' WHERE display_name = 'Tuples updated' AND object_type = 400;

UPDATE pem.alert_template SET description='Tuples updated in database over last N minutes specified in "Parameter Options" section.' WHERE display_name = 'Tuples updated' AND object_type = 300;

UPDATE pem.alert_template SET description='Tuples updated in server over last N minutes specified in "Parameter Options" section.' WHERE display_name = 'Tuples updated' AND object_type = 200;

UPDATE pem.alert_template SET description='Tuples deleted from table over last N minutes specified in "Parameter Options" section.' WHERE display_name = 'Tuples deleted' AND object_type = 500;

UPDATE pem.alert_template SET description='Tuples deleted from schema over last N minutes specified in "Parameter Options" section.' WHERE display_name = 'Tuples deleted' AND object_type = 400;

UPDATE pem.alert_template SET description='Tuples deleted from database over last N minutes specified in "Parameter Options" section.' WHERE display_name = 'Tuples deleted' AND object_type = 300;

UPDATE pem.alert_template SET description='Tuples deleted from server over last N minutes specified in "Parameter Options" section.' WHERE display_name = 'Tuples deleted' AND object_type = 200;

UPDATE pem.alert_template SET description='Tuples hot updated in table, over last N minutes specified in "Parameter Options" section.' WHERE display_name = 'Tuples hot updated' AND object_type = 500;

UPDATE pem.alert_template SET description='Tuples hot updated in schema, over last N minutes specified in "Parameter Options" section.' WHERE display_name = 'Tuples hot updated' AND object_type = 400;

UPDATE pem.alert_template SET description='Tuples hot updated in database, over last N minutes specified in "Parameter Options" section.' WHERE display_name = 'Tuples hot updated' AND object_type = 300;

UPDATE pem.alert_template SET description='Tuples hot updated in server, over last N minutes specified in "Parameter Options" section.' WHERE display_name = 'Tuples hot updated' AND object_type = 200;

UPDATE pem.alert_template SET description='Number of full table scans on table, over last N minutes specified in "Parameter Options" section.' WHERE display_name = 'Sequential Scans' AND object_type = 500;

UPDATE pem.alert_template SET description='Number of full table scans in schema, over last N minutes specified in "Parameter Options" section.' WHERE display_name = 'Sequential Scans' AND object_type = 400;

UPDATE pem.alert_template SET description='Number of full table scans in database, over last N minutes specified in "Parameter Options" section.' WHERE display_name = 'Sequential Scans' AND object_type = 300;

UPDATE pem.alert_template SET description='Number of full table scans in server, over last N minutes specified in "Parameter Options" section.' WHERE display_name = 'Sequential Scans' AND object_type = 200;

UPDATE pem.alert_template SET description='Number of index scans on table, over last N minutes specified in "Parameter Options" section.' WHERE display_name = 'Index Scans' AND object_type = 500;

UPDATE pem.alert_template SET description='Number of index scans in schema, over last N minutes specified in "Parameter Options" section.' WHERE display_name = 'Index Scans' AND object_type = 400;

UPDATE pem.alert_template SET description='Number of index scans in database, over last N minutes specified in "Parameter Options" section.' WHERE display_name = 'Index Scans' AND object_type = 300;

UPDATE pem.alert_template SET description='Number of index scans in server, over last N minutes specified in "Parameter Options" section.' WHERE display_name = 'Index Scans' AND object_type = 200;

UPDATE pem.alert_template SET description='Percentage of hot updates in the table over last N minutes specified in "Parameter Options" section.' WHERE display_name = 'Hot update percentage' AND object_type = 500;

UPDATE pem.alert_template SET description='Percentage of hot updates in the schema over last N minutes specified in "Parameter Options" section.' WHERE display_name = 'Hot update percentage' AND object_type = 400;

UPDATE pem.alert_template SET description='Percentage of hot updates in the database over last N minutes specified in "Parameter Options" section.' WHERE display_name = 'Hot update percentage' AND object_type = 300;

UPDATE pem.alert_template SET description='Percentage of hot updates in the server over last N minutes specified in "Parameter Options" section.' WHERE display_name = 'Hot update percentage' AND object_type = 200;

UPDATE pem.alert_template SET description='The percentage of buffers written by backends vs. the total buffers written over last N minutes specified in "Parameter Options" section.

Probe dependency list: background_writer_statistics' WHERE display_name = 'Percentage of buffers written by backends over last N minutes';

UPDATE pem.alert_template SET description='The number of ERRORS in the logfile on server M in last X hours specified in "Parameter Options" section.' WHERE display_name = 'Number of ERRORS in the logfile on server M in the last X hours';

UPDATE pem.alert_template SET description='The number of WARNINGS in logfile on server M in the last X hours specified in "Parameter Options" section.' WHERE display_name = 'Number of WARNINGS in the logfile on server M in the last X hours';

UPDATE pem.alert_template SET description='The number of WARNINGS or ERRORS in the logfile on server M in the last X hours specified in "Parameter Options" section.' WHERE display_name = 'Number of WARNINGS or ERRORS in the logfile on server M in the last X hours';

UPDATE pem.alert_template SET description='The number of ERRORS in the logfile on agent N in last X hours specified in "Parameter Options" section.' WHERE display_name = 'Number of ERRORS in the logfile on agent N in last X hours';

UPDATE pem.alert_template SET description='The number of WARNINGS in the logfile on agent N in last X hours specified in "Parameter Options" section.' WHERE display_name = 'Number of WARNINGS in the logfile on agent N in last X hours';

UPDATE pem.alert_template SET description='The number of WARNINGS or ERRORS in the logfile on agent N in last X hours specified in "Parameter Options" section.' WHERE display_name = 'Number of WARNINGS or ERRORS in the logfile on agent N in last X hours';

UPDATE pem.alert_template SET description='The number of ERRORS in the audit logfile on server M in last X hours specified in "Parameter Options" section.' WHERE display_name = 'Number of ERRORS in the audit logfile on server M in the last X hours';

UPDATE pem.alert_template SET description='The number of WARNINGS in audit logfile on server M in the last X hours specified in "Parameter Options" section.' WHERE display_name = 'Number of WARNINGS in the audit logfile on server M in the last X hours';

UPDATE pem.alert_template SET description='The number of WARNINGS or ERRORS in the audit logfile on server M in the last X hours specified in "Parameter Options" section.' WHERE display_name = 'Number of WARNINGS or ERRORS in the audit logfile on server M in the last X hours';

UPDATE pem.alert_template SET description='The number of ERRORS in the audit logfile on agent N in last X hours specified in "Parameter Options" section.' WHERE display_name = 'Number of ERRORS in the audit logfile on agent N in last X hours';

UPDATE pem.alert_template SET description='The number of WARNINGS in the audit logfile on agent N in last X hours specified in "Parameter Options" section.' WHERE display_name = 'Number of WARNINGS in the audit logfile on agent N in last X hours';

UPDATE pem.alert_template SET description='The number of WARNINGS or ERRORS in the audit logfile on agent N in last X hours specified in "Parameter Options" section.' WHERE display_name = 'Number of WARNINGS or ERRORS in the audit logfile on agent N in last X hours';

UPDATE pem.alert_template SET description='The number of SQL injection attacks occured in the last N minutes specified in "Parameter Options" section.' WHERE display_name = 'Number of attacks detected in the last N minutes' AND object_type = 200;

UPDATE pem.alert_template SET description='The number of SQL injection attacks occured in the last N minutes specified in "Parameter Options" section.' WHERE display_name = 'Number of attacks detected in the last N minutes' AND object_type = 300;

UPDATE pem.alert_template SET description='The number of SQL injection attacks occured in the last N minutes by username specified in "Parameter Options" section.' WHERE display_name = 'Number of attacks detected in the last N minutes by username' AND object_type = 200;

UPDATE pem.alert_template SET description='The number of SQL injection attacks occured in the last N minutes by username specified in "Parameter Options" section.' WHERE display_name = 'Number of attacks detected in the last N minutes by username' AND object_type = 300;

UPDATE pem.alert_template SET description='In streaming replication number of standby servers lag behind the master by write location specified in "Parameter Options" section.' WHERE display_name = 'Number of standby servers lag behind the master by write location';

UPDATE pem.alert_template SET description='In streaming replication number of standby servers lag behind the master by flush location specified in "Parameter Options" section.' WHERE display_name = 'Number of standby servers lag behind the master by flush location';

UPDATE pem.alert_template SET description='In streaming replication number of standby servers lag behind the master by replay location specified in "Parameter Options" section.' WHERE display_name = 'Number of standby servers lag behind the master by replay location';

UPDATE pem.alert_template SET description='In streaming replication standby server lag behind the master by write location in MB specified in "Parameter Options" section.', param_names='{Host IP Address}' WHERE display_name = 'Standby server lag behind the master by write location';

UPDATE pem.alert_template SET description='In streaming replication standby server lag behind the master by flush location in MB specified in "Parameter Options" section.', param_names='{Host IP Address}' WHERE display_name = 'Standby server lag behind the master by flush location';

UPDATE pem.alert_template SET description='In streaming replication standby server lag behind the master by replay location in MB specified in "Parameter Options" section.', param_names='{Host IP Address}' WHERE display_name = 'Standby server lag behind the master by replay location';

UPDATE pem.alert_template SET description='Events lagging in one slony cluster in slony replication by slony cluster name specified in "Parameter Options" section.' WHERE display_name = 'Events lagging in one slony cluster';
UPDATE pem.alert_template SET description='Lag time (minutes) in one slony cluster in slony replication specified in "Parameter Options" section.' WHERE display_name = 'Lag time (minutes) in one slony cluster';

UPDATE pem.alert_template SET description='Space wasted by the materialized view, in MB specified in "Parameter Options" section.' WHERE display_name = 'Materialized View bloat';

UPDATE pem.alert_template SET description='Size of the materialized view as a multiple of estimated unbloated size specified in "Parameter Options" section.' WHERE display_name = 'Materialized view size as a multiple of ubloated size';

UPDATE pem.alert_template SET description='Largest materialized view in schema, calculated as a multiple of its own estimated unbloated size; exclude materialized view smaller than N MB specified in "Parameter Options" section.' WHERE display_name = 'Largest materialized view (by multiple of unbloated size)' AND object_type = 400;

UPDATE pem.alert_template SET description='Largest materialized view in database, calculated as a multiple of its own estimated unbloated size; exclude materialized views smaller than N MB specified in "Parameter Options" section.' WHERE display_name = 'Largest materialized view (by multiple of unbloated size)' AND object_type = 300;

UPDATE pem.alert_template SET description='Largest materialized view in server, calculated as a multiple of its own estimated unbloated size; exclude materialized views smaller than N MB specified in "Parameter Options" section.' WHERE display_name = 'Largest materialized view (by multiple of unbloated size)' AND object_type = 200;

UPDATE pem.alert_template SET description='The size of materialized view, in MB specified by materialized view name in "Parameter Options" section.' WHERE display_name = 'Materialized view size';

UPDATE pem.alert_template SET description='The age (in transactions before the current transaction) of the materialized view frozen transaction ID specified by materialized view name in "Parameter Options" section.' WHERE display_name = 'Materialized View Frozen XID';

UPDATE pem.alert_template SET description='Standy server lag behind the master by WAL segments specified by standby ip address in "Parameter Options" section.', param_names='{"Standby IP Address"}' WHERE display_name = 'Standby server lag behind the master by WAL segments';

UPDATE pem.alert_template SET description='Standy server lag behind the master by WAL pages specified by standby ip address in "Parameter Options" section.', param_names='{"Standby IP Address"}' WHERE display_name = 'Standby server lag behind the master by WAL pages';

--------------------------------------------------------------------------------
-- Function:                                                                   -
--   pem.db_escaped_string_to_array                                            -
--                                                                             -
-- Parameters:                                                                 -
--   p_src   : Escapsed string                                                 -
--   p_quote : Quoting string (Default: ')                                     -
--                                                                             -
-- Returns:                                                                    -
--   - Array object containing the elements in the escaped string              -
--                                                                             -
-- Purpose:                                                                    -
--   Convert escpared string to an array.                                      -
--                                                                             -
-- Purpose:                                                                    -
--   The restricted db(s) and schema(s) are stored as an esacped string in the -
--   database server (of course - it is a bad design, but - we'll have to      -
--   leave with it), In order to use them in query, we need to convert them    -
--   into an array. This function helps doing that.                            -
--------------------------------------------------------------------------------
DROP FUNCTION pem.db_escaped_string_to_array(text);
CREATE OR REPLACE FUNCTION pem.db_escaped_string_to_array(p_src text, p_quote text DEFAULT '''') RETURNS text[] AS
$$
DECLARE
	res text[] = ARRAY[]::text[];
	len int4;
	inquote boolean := false;
	indquote boolean := false;
	tmpstr text := '';
	idx int4 := 1;
	arridx int4 := 1;
	prevchar text;
	currchar text;
BEGIN
	IF p_src IS NULL THEN
		RETURN NULL;
	END IF;
	len := length(p_src);

	IF len = 0 THEN
		RETURN NULL;
	END IF;

	WHILE idx <= len
	LOOP
		currchar := substring(p_src from idx for 1);

		IF currchar = p_quote THEN
			IF NOT inquote THEN
				IF prevchar IS NOT NULL THEN
					IF prevchar = p_quote THEN
						tmpstr := tmpstr || p_quote;
						prevchar := NULL;
					END IF;
					inquote := true;
				ELSE
					prevchar := NULL;
					inquote := true;
				END IF;
			ELSE
				prevchar := p_quote;
				inquote := false;
			END IF;
		ELSIF currchar = E'\\' AND idx < len AND substring(p_src from idx + 1 for 1) = p_quote THEN
			idx := idx + 1;
			prevchar := NULL;
			tmpstr := tmpstr || '''';
		ELSIF (NOT inquote) AND currchar = 'E' AND idx < len AND substring(p_src from idx + 1 for 1) = p_quote THEN
			-- Ignore the ESCAPE character
			idx := idx + 1;
			inquote := true;
			prevchar := NULL;
		ELSIF (NOT inquote) AND currchar = ',' THEN
			res[arridx] := tmpstr;
			arridx :=  arridx + 1;
			tmpstr := '';
			prevchar := NULL;
		ELSIF (NOT inquote) AND (currchar = ' ' OR currchar = E'\n' OR currchar = E'\r' OR currchar = E'\t' OR currchar = E'\f') THEN
			-- Ignore all white-space characters outside the quote
		ELSE
			prevchar :=  currchar;
			tmpstr := tmpstr || currchar;
		END IF;
		idx := idx + 1;
	END LOOP;
	res[arridx] :=  tmpstr;

	return res;
END
$$ LANGUAGE plpgsql;

INSERT INTO pem.config (param, value, unit, datatype) VALUES ('show_data_points_on_graph', 'f', 't/f', 'bool');

COMMIT TRANSACTION;
