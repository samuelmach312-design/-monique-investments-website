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
'SELECT 201801121::integer;'
  LANGUAGE 'sql' IMMUTABLE;
COMMENT ON FUNCTION pem.schema_version() IS 'Returns the version number of the PEM schema';

-- Reference - https://wiki.postgresql.org/wiki/Unnest_multidimensional_array
CREATE OR REPLACE FUNCTION pem.reduce_dim(anyarray)
RETURNS SETOF anyarray AS
$function$
DECLARE
    s $1%TYPE;
BEGIN
    FOREACH s SLICE 1  IN ARRAY $1 LOOP
        RETURN NEXT s;
    END LOOP;
    RETURN;
END;
$function$
LANGUAGE plpgsql IMMUTABLE;

ALTER TABLE pem.alert_template ADD COLUMN is_auto_create	boolean NOT NULL DEFAULT false;
COMMENT ON COLUMN pem.alert_template.is_auto_create IS
        'Defines whether using given template alerts will be created automatically';
ALTER TABLE pem.alert_template ADD COLUMN info_sql text DEFAULT NULL;
COMMENT ON COLUMN pem.alert_template.info_sql IS
        'SQL query, will be used to get the detailed information about the alert.';

ALTER TABLE pem.alert_status ADD COLUMN info text DEFAULT NULL;
ALTER TABLE pem.alert_status ADD COLUMN info_cols text[] DEFAULT NULL;
ALTER TABLE pem.alert_status ADD COLUMN info_vals text[] DEFAULT NULL;

COMMENT ON COLUMN pem.alert_status.info IS
        'Formatted string of detail information about the alert.';
COMMENT ON COLUMN pem.alert_status.info_cols IS
        'Column information of detail alert SQL.';
COMMENT ON COLUMN pem.alert_status.info_vals IS
        'Store alert detail information query result.';

ALTER TABLE pem.alert_template ADD COLUMN operator "char" NOT NULL DEFAULT '>'
		CONSTRAINT valid_operators CHECK(operator in ('<' ,'>'));
ALTER TABLE pem.alert_template ADD COLUMN thresholds numeric[]
		CONSTRAINT validate_thresholds_ordering
				CHECK(
				CASE WHEN is_auto_create THEN
				  array_upper(thresholds, 1) = 3
					AND thresholds[1] IS NOT NULL
					AND thresholds[2] IS NOT NULL
					AND thresholds[3] IS NOT NULL
					AND CASE
					WHEN operator = '<' THEN
						thresholds[1] > thresholds [2]
						AND thresholds[2] > thresholds[3]
					WHEN operator = '>' THEN
						thresholds[1] < thresholds [2]
						AND thresholds[2] < thresholds[3]
					ELSE false
					END
				ELSE thresholds IS NULL END);

DROP FUNCTION pem.create_alert_template(text, text, text, integer, text[], pem.alert_param_type[], text[], text, text[], integer, pem.server_type, integer, integer, boolean);
CREATE OR REPLACE FUNCTION pem.create_alert_template(
									name				text,
									description			text,
									sql				text,
									object_type			integer,
									param_names			text[],
									param_types			pem.alert_param_type[],
									param_units			text[],
									threshold_unit			text,
									probe_dependency_list		text[] DEFAULT '{}',
									snmp_oid			integer DEFAULT 0,
									applicable_on_server            pem.server_type DEFAULT 'ALL',
									default_check_frequency		integer DEFAULT 1,
									default_history_retention	integer DEFAULT 30,
									is_system_template  boolean	DEFAULT true,
									info_sql  text DEFAULT NULL,
									is_auto_create  boolean DEFAULT false,
									operator  text DEFAULT '>',
									thresholds  numeric[] DEFAULT NULL
									)
RETURNS VOID AS $$
	/*
	 * If we ever change to pl/pgsql, we might want to validate input and RAISE
	 * exceptions here.
	 *
	 * If this INSERT fails the user will see the ERROR with this function's
	 * name in context, hence it doesn't seem any worse than validating params
	 * and RAISE'ing errors, except that by using RAISE we can provide friendly
	 * hints.
	 */
	INSERT INTO pem.alert_template (display_name, description, sql, object_type,
									param_names, param_types, param_units,
									threshold_unit, probe_dependency_list, snmp_oid, applicable_on_server,
									default_check_frequency, default_history_retention, is_system_template,
									info_sql, is_auto_create, operator, thresholds)
	VALUES($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, $14, $15, $16, $17, $18);
$$ LANGUAGE SQL;


ALTER TABLE pem.alert ADD COLUMN auto_created	boolean NOT NULL DEFAULT false;
DROP FUNCTION pem.create_alert(text, integer, integer, integer, text, text, text, text, text[], text, numeric[], integer, integer, boolean, integer, boolean, boolean, timestamp with time zone, boolean, integer, boolean, integer, boolean, integer, boolean, integer, boolean, boolean, boolean, text, boolean);
CREATE OR REPLACE FUNCTION pem.create_alert(name				text,
											alert_template_id	integer,
											agent_id		integer,
											server_id		integer,
											database_name		text,
											schema_name		text,
											package_name		text,
											object_name		text,
											params			text[],
											operator		text,
											thresholds		numeric[],
											check_frequency		integer DEFAULT 1,
											history_retention	integer DEFAULT 30,
											enabled			bool DEFAULT true,
											auto_created		bool DEFAULT false,
											email_group_id		integer DEFAULT NULL,
											send_email		bool DEFAULT false,
											flapping_detected	bool DEFAULT FALSE,
											last_flapping_detection_processed timestamptz DEFAULT current_timestamp,
											send_trap		bool DEFAULT false,
											snmp_trap_version	integer DEFAULT 2,
											low_send_trap		bool DEFAULT false,
											low_email_group_id	integer DEFAULT NULL,
											med_send_trap		bool DEFAULT false,
											med_email_group_id	integer DEFAULT NULL,
											high_send_trap		bool DEFAULT false,
											high_email_group_id	integer DEFAULT NULL,
											execute_script	bool DEFAULT false,
											execute_script_on_clear	bool DEFAULT false,
											execute_script_on_pem_server	bool DEFAULT false,
											script_code	text DEFAULT NULL,
											submit_to_nagios boolean DEFAULT false)
RETURNS VOID AS $$
	/*
	 * TODO: Should we check if an object by the name object_name of type
	 * alert_template[template_id].object_type exists in the history logs? Or
	 * for that matter, verify all the Agent, Database, Server, etc.
	 *
	 * Probably not, because most of the time the user would be using the GUI to
	 * create alerts and the GUI would help the user pick up appropriate object
	 * based on object_type. And even if the object does not exist, all that
	 * would happen is the sql query of the alert would return zero rows.
	 */

	INSERT INTO pem.alert(name, enabled, template_id, agent_id, server_id,
							database_name, schema_name, package_name,
							object_name, params, operator, thresholds,
							check_frequency, history_retention, auto_created, email_group_id, send_email,
							flapping_detected, last_flapping_detection_processed,
							send_trap, snmp_trap_version, low_send_trap, low_email_group_id, med_send_trap,
							med_email_group_id, high_send_trap, high_email_group_id, execute_script, execute_script_on_clear,
							execute_script_on_pem_server, script_code, submit_to_nagios)
	VALUES($1, $14, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, $15, $16, $17, $18, $19, $20,
			$21, $22, $23, $24, $25, $26, $27, $28, $29, $30, $31, $32);
$$ LANGUAGE sql;

-- Update statements for auto alerts and detailed information of agent level alerts
UPDATE pem.alert_template SET is_auto_create = true, thresholds = '{70, 80, 85}'
WHERE display_name = 'CPU utilization' AND object_type = 100;

UPDATE pem.alert_template SET info_sql = $sql$
  SELECT a.description AS "Agent name", c.core_id AS "CPU core", c.load_percentage AS "CPU load (%)"
  FROM
      pemdata.cpu_usage AS c
  JOIN pem.agent AS a
        ON c.agent_id = a.id
  WHERE
      c.agent_id = '${agent_id}'::integer
      AND c.load_percentage ${comparison_operator} '${threshold_value}'::numeric ORDER BY c.load_percentage DESC;$sql$
WHERE display_name = 'Number of CPUs running higher than a threshold' AND object_type = 100;

UPDATE pem.alert_template SET is_auto_create = true, thresholds = '{80, 85, 90}'
  WHERE display_name = 'Memory used percentage' AND object_type = 100;

UPDATE pem.alert_template SET is_auto_create = true, thresholds = '{25, 50, 75}'
  WHERE display_name = 'Swap consumption percentage' AND object_type = 100;

UPDATE pem.alert_template SET is_auto_create = true, thresholds = '{80, 85, 90}',
  info_sql = $sql$SELECT a.description AS "Agent name", d.mount_point AS "Mount point",
        d.file_system AS "File system", d.size_mb AS "Total size (MB)", d.space_used_mb AS "Space used (MB)",
        d.space_available_mb AS "Space available (MB)", d.space_reserved_mb AS "Space reserved (MB)"
    FROM
        pemdata.disk_space AS d
    JOIN pem.agent AS a
        ON d.agent_id = a.id
    WHERE
        d.size_mb > 0 AND
        d.agent_id = '${agent_id}'::integer AND
        (d.space_used_mb::float * 100 / (d.size_mb - COALESCE(d.space_reserved_mb, 0))) ${comparison_operator} '${threshold_value}'::numeric ORDER BY (d.space_used_mb::float * 100 / (d.size_mb - COALESCE(d.space_reserved_mb, 0))) DESC;$sql$
WHERE display_name = 'Most used disk percentage' AND object_type = 100;

UPDATE pem.alert_template SET is_auto_create = true, thresholds = '{0.1, 0.2, 0.3}',
  info_sql = $sql$SELECT
       ip.name AS "Package name", ip.version AS "Installed version", pc.version AS "Catalog version"
   FROM
       pemdata.package_catalog pc LEFT JOIN pemdata.installed_packages ip
         ON (pc.pkg_id = ip.pkg_id) AND (pc.platform = ip.platform)
       JOIN pem.agent AS a
         ON ip.agent_id = a.id
   WHERE
       ip.agent_id = '${agent_id}'::integer AND
       pc.pkg_id = ip.pkg_id AND
       pc.platform = ip.platform AND
       pc.version != ip.version AND
       pc.manifesturl IS NOT NULL ORDER BY ip.name;$sql$
WHERE display_name = 'Package version mismatch' AND object_type = 100;

UPDATE pem.alert_template SET is_auto_create = true, thresholds = '{0.1, 0.2, 0.3}'
  WHERE display_name = 'Agent Down' AND object_type = 100;
UPDATE pem.alert_template SET is_auto_create = true, thresholds = '{15, 20, 25}'
  WHERE display_name = 'Load Average per CPU Core (5 minutes)' AND object_type = 100;

-- Update statements for auto alerts and detailed information of server level alerts
UPDATE pem.alert_template SET is_auto_create = true, thresholds = '{0.1, 0.2, 0.3}'
  WHERE display_name = 'Server Down' AND object_type = 200;
UPDATE pem.alert_template SET is_auto_create = true, thresholds = '{70, 85, 95}'
  WHERE display_name = 'Total table bloat in server' AND object_type = 200;

UPDATE pem.alert_template SET is_auto_create = true, thresholds = '{70, 85, 95}',
  info_sql = $sql$SELECT srv.description AS "Server name", b.database_name AS "Database name", b.schema_name AS "Schema name",
       b.table_name AS "Table name", b.estimated_pages AS "Estimated pages",
       b.estimated_bloat_multiple AS "Estimated bloat multiple", b.estimated_pages_wasted AS "Estimated pages wasted",
       b.estimated_bytes_per_tuple AS "Estimated bytes per tuple"
FROM pemdata.table_bloat AS b
     JOIN pemdata.settings AS s
     ON	b.server_id = s.server_id
     JOIN pem.server AS srv
     ON b.server_id = srv.id
     AND s.name = 'block_size'
WHERE
     b.server_id = '${server_id}'::integer
     AND ((b.estimated_pages_wasted*s.setting::integer)/1048576) ${comparison_operator} '${threshold_value}'::numeric
     AND (b.database_name != '' AND b.database_name != 'template0' AND b.database_name != 'template1')
     AND
         (b.schema_name != '' AND
                    b.schema_name NOT IN (
                        'pg_catalog', 'sys', 'information_schema'
                    ) AND
                    b.schema_name NOT LIKE 'pg_toast%%' AND
                    b.schema_name NOT LIKE 'pg_temp%%') ORDER BY ((b.estimated_pages_wasted*s.setting::integer)/1048576) DESC;$sql$
WHERE display_name = 'Highest table bloat in server' AND object_type = 200;

UPDATE pem.alert_template SET is_auto_create = true, thresholds = '{70, 85, 95}'
  WHERE display_name = 'Average table bloat in server' AND object_type = 200;
UPDATE pem.alert_template SET is_auto_create = true, thresholds = '{70, 85, 95}',
  info_sql = $sql$SELECT table_name AS "Table name", total_table_size_mb AS "Total table size(MB)"
FROM pemdata.table_size
WHERE	server_id = ${server_id}
AND total_table_size_mb ${comparison_operator} '${threshold_value}'::numeric ORDER BY total_table_size_mb DESC;$sql$
  WHERE display_name = 'Table size in server' AND object_type = 200;
UPDATE pem.alert_template SET is_auto_create = true, thresholds = '{70, 85, 95}',
  info_sql = $sql$
SELECT database_name AS "Database name", database_size_mb AS "Database size(MB)"
FROM pemdata.database_size
WHERE	server_id = ${server_id}
AND database_size_mb ${comparison_operator} '${threshold_value}'::numeric ORDER BY database_size_mb DESC;$sql$
  WHERE display_name = 'Database size in server' AND object_type = 200;
UPDATE pem.alert_template SET is_auto_create = true, thresholds = '{400, 500, 600}'
  WHERE display_name = 'Number of WAL files' AND object_type = 200;
UPDATE pem.alert_template SET is_auto_create = true, thresholds = '{10, 20, 30}'
  WHERE display_name = 'Number of prepared transactions' AND object_type = 200;

UPDATE pem.alert_template SET is_auto_create = true, thresholds = '{75, 85, 95}',
  info_sql = $sql$SELECT s.description AS "Server name", si.database_name AS "Database name", si.procpid AS "Process ID", si.usename AS "Username",
        si.backend_start AS "Process start time", si.xact_start AS "Transaction start time", si.query_start AS "Query start time",
        si.is_waiting AS "Is Waiting?", si.is_idle AS "Is Idle?", si.is_idle_in_transaction AS "Is idle in transaction?",
        si.is_vacuum AS "Is vacuum?", si.is_autovacuum AS "Is autovacuum?", si.wait_event_type AS "Wait event type", si.wait_event AS "Wait event"
    FROM
        pemdata.session_info AS si
        JOIN pem.server AS s
        ON si.server_id = s.id
    WHERE
        si.server_id = '${server_id}'::integer ORDER BY s.description;$sql$
WHERE display_name = 'Total connections' AND object_type = 200;

UPDATE pem.alert_template SET is_auto_create = true, thresholds = '{80, 85, 90}'
  WHERE display_name = 'Total connections as percentage of max_connections' AND object_type = 200;

UPDATE pem.alert_template SET is_auto_create = true, thresholds = '{5, 10, 15}',
  info_sql = $sql$SELECT s.description AS "Server name", si.database_name AS "Database name", si.procpid AS "Process ID", si.usename AS "Username",
        si.backend_start AS "Process start time", si.xact_start AS "Transaction start time", si.query_start AS "Query start time",
        si.is_waiting AS "Is Waiting?", si.is_idle AS "Is Idle?", si.is_idle_in_transaction AS "Is idle in transaction?",
        si.is_vacuum AS "Is vacuum?", si.is_autovacuum AS "Is autovacuum?", si.wait_event_type AS "Wait event type", si.wait_event AS "Wait event"
    FROM
        pemdata.session_info AS si
        JOIN pem.server AS s
        ON si.server_id = s.id
    WHERE
        si.is_idle IS TRUE
        AND si.server_id = '${server_id}'::integer ORDER BY s.description;$sql$
WHERE display_name = 'Connections in idle state' AND object_type = 200;

UPDATE pem.alert_template SET is_auto_create = true, thresholds = '{5, 10, 15}',
  info_sql = $sql$SELECT s.description AS "Server name", si.database_name AS "Database name", si.procpid AS "Process ID", si.usename AS "Username",
        si.backend_start AS "Process start time", si.xact_start AS "Transaction start time", si.query_start AS "Query start time",
        si.is_waiting AS "Is Waiting?", si.is_idle AS "Is Idle?", si.is_idle_in_transaction AS "Is idle in transaction?",
        si.is_vacuum AS "Is vacuum?", si.is_autovacuum AS "Is autovacuum?", si.wait_event_type AS "Wait event type", si.wait_event AS "Wait event"
    FROM
        pemdata.session_info AS si
        JOIN pem.server AS s
        ON si.server_id = s.id
    WHERE
        si.is_idle_in_transaction IS TRUE
        AND si.server_id = '${server_id}'::integer ORDER BY s.description;$sql$
WHERE display_name = 'Connections in idle-in-transaction state' AND object_type = 200;

UPDATE pem.alert_template SET is_auto_create = true, thresholds = '{10, 20, 30}'
  WHERE display_name = 'Connections in idle-in-transaction state, as a percentage of max_connections'
  AND object_type = 200;

UPDATE pem.alert_template SET is_auto_create = true, thresholds = '{1, 4, 12}'
  WHERE display_name = 'Last Vacuum' AND object_type = 200;

UPDATE pem.alert_template SET is_auto_create = true, thresholds = '{1, 4, 12}'
  WHERE display_name = 'Last AutoVacuum' AND object_type = 200;

UPDATE pem.alert_template SET is_auto_create = true, thresholds = '{70, 85, 95}'
  WHERE display_name = 'Largest index by table-size percentage' AND object_type = 200;

UPDATE pem.alert_template SET is_auto_create = true, thresholds = '{0.1, 0.2, 0.3}',
  info_sql = $sql$SELECT a[1] as "Parameter", a[2] AS "User specified value", a[3] as "Current value"
FROM (
  SELECT pem.reduce_dim(
      ARRAY[
       CASE
         WHEN(p.edb_audit != pd.edb_audit) THEN ARRAY['Audit parameter'::text, p.edb_audit::text, pd.edb_audit::text]::text[]
	     ELSE ARRAY[null, null, null]::text[]
       END,
       CASE
         WHEN(p.edb_audit_directory != pd.edb_audit_directory) THEN ARRAY['Audit Directory'::text, p.edb_audit_directory::text, pd.edb_audit_directory::text]::text[]
	     ELSE ARRAY[null, null, null]::text[]
       END,
       CASE
         WHEN(p.edb_audit_filename != pd.edb_audit_filename) THEN ARRAY['Audit filename'::text, p.edb_audit_filename::text, pd.edb_audit_filename::text]::text[]
	     ELSE ARRAY[null, null, null]::text[]
       END,
       CASE
         WHEN(p.edb_audit_rotation_day != pd.edb_audit_rotation_day) THEN ARRAY['Audit rotation day'::text, p.edb_audit_rotation_day::text, pd.edb_audit_rotation_day::text]::text[]
	     ELSE ARRAY[null, null, null]::text[]
       END,
       CASE
         WHEN(p.edb_audit_rotation_sec != pd.edb_audit_rotation_sec) THEN ARRAY['Audit rotation sec'::text, p.edb_audit_rotation_sec::text, pd.edb_audit_rotation_sec::text]::text[]
	     ELSE ARRAY[null, null, null]::text[]
       END,
       CASE
         WHEN(p.edb_audit_rotation_size != pd.edb_audit_rotation_size) THEN ARRAY['Audit rotation size'::text, p.edb_audit_rotation_size::text, pd.edb_audit_rotation_size::text]::text[]
	     ELSE ARRAY[null, null, null]::text[]
       END,
       CASE
         WHEN(p.edb_audit_connect != pd.edb_audit_connect) THEN ARRAY['Audit connect'::text, p.edb_audit_connect::text, pd.edb_audit_connect::text]::text[]
	     ELSE ARRAY[null, null, null]::text[]
       END,
       CASE
         WHEN(p.edb_audit_disconnect != pd.edb_audit_disconnect) THEN ARRAY['Audit disconnect'::text, p.edb_audit_disconnect::text, pd.edb_audit_disconnect::text]::text[]
	     ELSE ARRAY[null, null, null]::text[]
       END,
       CASE
         WHEN(p.edb_audit_statements != pd.edb_audit_statements) THEN ARRAY['Audit statements'::text, p.edb_audit_statements::text, pd.edb_audit_statements::text]::text[]
	     ELSE ARRAY[null, null, null]::text[]
       END,
       CASE
         WHEN(p.edb_audit_tag != pd.edb_audit_tag) THEN ARRAY['Audit tag'::text, p.edb_audit_tag::text, pd.edb_audit_tag::text]::text[]
	     ELSE ARRAY[null, null, null]::text[]
       END,
       CASE
         WHEN(p.edb_audit_destination != pd.edb_audit_destination) THEN ARRAY['Audit destination'::text, p.edb_audit_destination::text, pd.edb_audit_destination::text]::text[]
	     ELSE ARRAY[null, null, null]::text[]
       END ]::text[]) as a
   FROM
     pem.audit_configuration p RIGHT JOIN
     pemdata.audit_configuration pd ON (p.server_id = pd.server_id)
   WHERE p.server_id = '${server_id}'::integer) t
WHERE t.a[1] is not NULL ORDER BY t.a[1];$sql$
  WHERE display_name = 'Audit config mismatch' AND object_type = 200;

UPDATE pem.alert_template SET is_auto_create = true, thresholds = '{0.1, 0.2, 0.3}',
  info_sql =  $sql$SELECT a[1] as "Parameter", a[2] AS "User specified value", a[3] as "Current value"
FROM (
  SELECT pem.reduce_dim(
      ARRAY[
       CASE
         WHEN(p.log_destination != pd.log_destination) THEN ARRAY['Log destination'::text, p.log_destination::text, pd.log_destination::text]::text[]
	     ELSE ARRAY[null, null, null]::text[]
       END,
       CASE
         WHEN(p.log_collector != pd.log_collector) THEN ARRAY['Log collector'::text, p.log_collector::text, pd.log_collector::text]::text[]
	     ELSE ARRAY[null, null, null]::text[]
       END,
       CASE
         WHEN(p.log_silent_mode != pd.log_silent_mode) THEN ARRAY['Log silent mode'::text, p.log_silent_mode::text, pd.log_silent_mode::text]::text[]
	     ELSE ARRAY[null, null, null]::text[]
       END,
       CASE
         WHEN(p.log_directory != pd.log_directory) THEN ARRAY['Log directory'::text, p.log_directory::text, pd.log_directory::text]::text[]
	     ELSE ARRAY[null, null, null]::text[]
       END,
       CASE
         WHEN(p.log_filename != pd.log_filename) THEN ARRAY['Log filename'::text, p.log_filename::text, pd.log_filename::text]::text[]
	     ELSE ARRAY[null, null, null]::text[]
       END,
       CASE
         WHEN(p.log_syslog_facility != pd.log_syslog_facility) THEN ARRAY['Log syslog facility'::text, p.log_syslog_facility::text, pd.log_syslog_facility::text]::text[]
	     ELSE ARRAY[null, null, null]::text[]
       END,
       CASE
         WHEN(p.log_syslog_ident != pd.log_syslog_ident) THEN ARRAY['Log syslog ident'::text, p.log_syslog_ident::text, pd.log_syslog_ident::text]::text[]
	     ELSE ARRAY[null, null, null]::text[]
       END,
       CASE
         WHEN(p.log_rotation_size != pd.log_rotation_size) THEN ARRAY['Log rotation size'::text, p.log_rotation_size::text, pd.log_rotation_size::text]::text[]
	     ELSE ARRAY[null, null, null]::text[]
       END,
       CASE
         WHEN(p.log_rotation_time != pd.log_rotation_time) THEN ARRAY['Log rotation time'::text, p.log_rotation_time::text, pd.log_rotation_time::text]::text[]
	     ELSE ARRAY[null, null, null]::text[]
       END,
       CASE
         WHEN(p.log_rotation_truncate != pd.log_rotation_truncate) THEN ARRAY['Log rotation truncate'::text, p.log_rotation_truncate::text, pd.log_rotation_truncate::text]::text[]
	     ELSE ARRAY[null, null, null]::text[]
       END,
       CASE
         WHEN(p.log_client_min_messages != pd.log_client_min_messages) THEN ARRAY['Log client min messages'::text, p.log_client_min_messages::text, pd.log_client_min_messages::text]::text[]
	     ELSE ARRAY[null, null, null]::text[]
       END,
       CASE
         WHEN(p.log_min_messages != pd.log_min_messages) THEN ARRAY['Log min messages'::text, p.log_min_messages::text, pd.log_min_messages::text]::text[]
	     ELSE ARRAY[null, null, null]::text[]
       END,
       CASE
         WHEN(p.log_min_error_statement != pd.log_min_error_statement) THEN ARRAY['Log min error statement'::text, p.log_min_error_statement::text, pd.log_min_error_statement::text]::text[]
	     ELSE ARRAY[null, null, null]::text[]
       END,
       CASE
         WHEN(p.log_min_duration_statement != pd.log_min_duration_statement) THEN ARRAY['Log min duration statement'::text, p.log_min_duration_statement::text, pd.log_min_duration_statement::text]::text[]
	     ELSE ARRAY[null, null, null]::text[]
       END,
       CASE
         WHEN(p.log_parse_tree != pd.log_parse_tree) THEN ARRAY['Log parse tree'::text, p.log_parse_tree::text, pd.log_parse_tree::text]::text[]
	     ELSE ARRAY[null, null, null]::text[]
       END,
       CASE
         WHEN(p.log_rewriter_output != pd.log_rewriter_output) THEN ARRAY['Log rewrite output'::text, p.log_rewriter_output::text, pd.log_rewriter_output::text]::text[]
	     ELSE ARRAY[null, null, null]::text[]
       END,
       CASE
         WHEN(p.log_exec_plan != pd.log_exec_plan) THEN ARRAY['Log execution plan'::text, p.log_exec_plan::text, pd.log_exec_plan::text]::text[]
	     ELSE ARRAY[null, null, null]::text[]
       END,
       CASE
         WHEN(p.log_indent_debug_output != pd.log_indent_debug_output) THEN ARRAY['Log indent debug output'::text, p.log_indent_debug_output::text, pd.log_indent_debug_output::text]::text[]
	     ELSE ARRAY[null, null, null]::text[]
       END,
       CASE
         WHEN(p.log_checkpoints != pd.log_checkpoints) THEN ARRAY['Log checkpoints'::text, p.log_checkpoints::text, pd.log_checkpoints::text]::text[]
	     ELSE ARRAY[null, null, null]::text[]
       END,
       CASE
         WHEN(p.log_connections != pd.log_connections) THEN ARRAY['Log connections'::text, p.log_connections::text, pd.log_connections::text]::text[]
	     ELSE ARRAY[null, null, null]::text[]
       END,
       CASE
         WHEN(p.log_disconnections != pd.log_disconnections) THEN ARRAY['Log disconnections'::text, p.log_disconnections::text, pd.log_disconnections::text]::text[]
	     ELSE ARRAY[null, null, null]::text[]
       END,
       CASE
         WHEN(p.log_duration != pd.log_duration) THEN ARRAY['Log duration'::text, p.log_duration::text, pd.log_duration::text]::text[]
	     ELSE ARRAY[null, null, null]::text[]
       END,
       CASE
         WHEN(p.log_hostname != pd.log_hostname) THEN ARRAY['Log host name'::text, p.log_hostname::text, pd.log_hostname::text]::text[]
	     ELSE ARRAY[null, null, null]::text[]
       END,
       CASE
         WHEN(p.log_lock_waits != pd.log_lock_waits) THEN ARRAY['Log lock waits'::text, p.log_lock_waits::text, pd.log_lock_waits::text]::text[]
	     ELSE ARRAY[null, null, null]::text[]
       END,
       CASE
         WHEN(p.log_error_verbosity != pd.log_error_verbosity) THEN ARRAY['Log error verbosity'::text, p.log_error_verbosity::text, pd.log_error_verbosity::text]::text[]
	     ELSE ARRAY[null, null, null]::text[]
       END,
CASE
         WHEN(p.log_prefix_string != pd.log_prefix_string) THEN ARRAY['Log prefix string'::text, p.log_prefix_string::text, pd.log_prefix_string::text]::text[]
	     ELSE ARRAY[null, null, null]::text[]
       END,
CASE
         WHEN(p.log_statements != pd.log_statements) THEN ARRAY['Log statements'::text, p.log_statements::text, pd.log_statements::text]::text[]
	     ELSE ARRAY[null, null, null]::text[]
       END,
CASE
         WHEN(p.log_autovacuum_min_duration != pd.log_autovacuum_min_duration) THEN ARRAY['Log autovacuum min duration'::text, p.log_autovacuum_min_duration::text, pd.log_autovacuum_min_duration::text]::text[]
	     ELSE ARRAY[null, null, null]::text[]
       END,
CASE
         WHEN(p.log_temp_files != pd.log_temp_files) THEN ARRAY['Log temp files'::text, p.log_temp_files::text, pd.log_temp_files::text]::text[]
	     ELSE ARRAY[null, null, null]::text[]
       END
       ]::text[]) as a
   FROM
     pem.log_configuration p RIGHT JOIN
     pemdata.log_configuration pd ON (p.server_id = pd.server_id)
   WHERE p.server_id = '${server_id}'::integer) t
WHERE t.a[1] is not NULL ORDER BY t.a[1];$sql$
  WHERE display_name = 'Log config mismatch' AND object_type = 200;

UPDATE pem.alert_template SET is_auto_create = true, thresholds = '{200, 300, 500}'
  WHERE display_name = 'Number of WAL archives pending' AND object_type = 200;

UPDATE pem.alert_template SET info_sql = $sql$SELECT s.description AS "Server name", si.database_name AS "Database name", si.procpid AS "Process ID", si.usename AS "Username",
        si.backend_start AS "Process start time", si.xact_start AS "Transaction start time", si.query_start AS "Query start time",
        si.is_waiting AS "Is Waiting?", si.is_idle AS "Is Idle?", si.is_idle_in_transaction AS "Is idle in transaction?",
        si.is_vacuum AS "Is vacuum?", si.is_autovacuum AS "Is autovacuum?", si.wait_event_type AS "Wait event type", si.wait_event AS "Wait event"
    FROM
        pemdata.session_info AS si
        JOIN pem.server AS s
        ON si.server_id = s.id
    WHERE
        si.server_id = '${server_id}'::integer
        AND si.is_idle IS TRUE
        AND (si.capture_time - COALESCE(si.query_start, si.xact_start, si.backend_start))::interval > '${param_1} seconds'::interval ORDER BY s.description;$sql$
WHERE display_name = 'Long-running idle connections' AND object_type = 200;

UPDATE pem.alert_template SET info_sql = $sql$SELECT s.description AS "Server name", si.database_name AS "Database name", si.procpid AS "Process ID", si.usename AS "Username",
        si.backend_start AS "Process start time", si.xact_start AS "Transaction start time", si.query_start AS "Query start time",
        si.is_waiting AS "Is Waiting?", si.is_idle AS "Is Idle?", si.is_idle_in_transaction AS "Is idle in transaction?",
        si.is_vacuum AS "Is vacuum?", si.is_autovacuum AS "Is autovacuum?", si.wait_event_type AS "Wait event type", si.wait_event AS "Wait event"
    FROM
        pemdata.session_info AS si
        JOIN pem.server AS s
        ON si.server_id = s.id
    WHERE
        si.server_id = '${server_id}'::integer
        AND (si.is_idle IS TRUE OR si.is_idle_in_transaction IS TRUE)
        AND (si.capture_time - COALESCE(si.query_start, si.xact_start, si.backend_start))::interval > '${param_1} seconds'::interval ORDER BY s.description;$sql$
WHERE display_name = 'Long-running idle connections and idle transactions' AND object_type = 200;

UPDATE pem.alert_template SET info_sql = $sql$SELECT s.description AS "Server name", si.database_name AS "Database name", si.procpid AS "Process ID", si.usename AS "Username",
        si.backend_start AS "Process start time", si.xact_start AS "Transaction start time", si.query_start AS "Query start time",
        si.is_waiting AS "Is Waiting?", si.is_idle AS "Is Idle?", si.is_idle_in_transaction AS "Is idle in transaction?",
        si.is_vacuum AS "Is vacuum?", si.is_autovacuum AS "Is autovacuum?", si.wait_event_type AS "Wait event type", si.wait_event AS "Wait event"
    FROM
        pemdata.session_info AS si
        JOIN pem.server AS s
        ON si.server_id = s.id
    WHERE
        si.server_id = '${server_id}'::integer
        AND si.is_idle_in_transaction IS TRUE
        AND (si.capture_time - COALESCE(si.query_start, si.xact_start, si.backend_start))::interval > '${param_1} seconds'::interval ORDER BY s.description;$sql$
WHERE display_name = 'Long-running idle transactions' AND object_type = 200;

UPDATE pem.alert_template SET info_sql = $sql$SELECT s.description AS "Server name", si.database_name AS "Database name", si.procpid AS "Process ID", si.usename AS "Username",
        si.backend_start AS "Process start time", si.xact_start AS "Transaction start time", si.query_start AS "Query start time",
        si.is_waiting AS "Is Waiting?", si.is_idle AS "Is Idle?", si.is_idle_in_transaction AS "Is idle in transaction?",
        si.is_vacuum AS "Is vacuum?", si.is_autovacuum AS "Is autovacuum?", si.wait_event_type AS "Wait event type", si.wait_event AS "Wait event"
    FROM
        pemdata.session_info AS si
        JOIN pem.server AS s
        ON si.server_id = s.id
    WHERE
        si.server_id = '${server_id}'::integer
        AND si.xact_start IS NOT NULL
        AND (si.capture_time - si.xact_start) > '${param_1} seconds'::interval ORDER BY s.description;$sql$
WHERE display_name = 'Long-running transactions' AND object_type = 200;

UPDATE pem.alert_template SET info_sql = $sql$SELECT s.description AS "Server name", si.database_name AS "Database name", si.procpid AS "Process ID", si.usename AS "Username",
        si.backend_start AS "Process start time", si.xact_start AS "Transaction start time", si.query_start AS "Query start time",
        si.is_waiting AS "Is Waiting?", si.is_idle AS "Is Idle?", si.is_idle_in_transaction AS "Is idle in transaction?",
        si.is_vacuum AS "Is vacuum?", si.is_autovacuum AS "Is autovacuum?", si.wait_event_type AS "Wait event type", si.wait_event AS "Wait event"
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

UPDATE pem.alert_template SET info_sql = $sql$SELECT s.description AS "Server name", si.database_name AS "Database name",
        si.procpid AS "Process ID", si.usename AS "Username", si.backend_start AS "Process start time", si.xact_start AS "Transaction start time",
        si.query_start AS "Query start time", si.is_waiting AS "Is Waiting?", si.is_idle AS "Is Idle?",
        si.is_idle_in_transaction AS "Is idle in transaction?", si.is_vacuum AS "Is vacuum?", si.is_autovacuum AS "Is autovacuum?",
        si.wait_event_type AS "Wait event type", si.wait_event AS "Wait event"
    FROM
        pemdata.session_info AS si
        JOIN pem.server AS s
        ON si.server_id = s.id
    WHERE
        si.server_id = '${server_id}'::integer
        AND si.is_vacuum = true
        AND (si.capture_time - si.query_start) > '${param_1} seconds'::interval ORDER BY s.description;$sql$
WHERE display_name = 'Long-running vacuums' AND object_type = 200;

UPDATE pem.alert_template SET info_sql = $sql$SELECT s.description AS "Server name", si.database_name AS "Database name",
        si.procpid AS "Process ID", si.usename AS "Username",
        si.backend_start AS "Process start time", si.xact_start AS "Transaction start time", si.query_start AS "Query start time",
        si.is_waiting AS "Is Waiting?", si.is_idle AS "Is Idle?", si.is_idle_in_transaction AS "Is idle in transaction?",
        si.is_vacuum AS "Is vacuum?", si.is_autovacuum AS "Is autovacuum?", si.wait_event_type AS "Wait event type", si.wait_event AS "Wait event"
    FROM
        pemdata.session_info AS si
        JOIN pem.server AS s
        ON si.server_id = s.id
    WHERE
        si.server_id = '${server_id}'::integer
        AND si.is_autovacuum = true
        AND (si.capture_time - si.query_start) > '${param_1} seconds'::interval ORDER BY s.description;$sql$
WHERE display_name = 'Long-running autovacuums' AND object_type = 200;

UPDATE pem.alert_template SET info_sql = $sql$SELECT pem.email_write_lag_streaming_replication();$sql$
WHERE display_name = 'Number of standby servers lag behind the master by write location' AND object_type = 200;
UPDATE pem.alert_template SET info_sql = $sql$SELECT pem.email_flush_lag_streaming_replication();$sql$
WHERE display_name = 'Number of standby servers lag behind the master by flush location' AND object_type = 200;
UPDATE pem.alert_template SET info_sql = $sql$SELECT pem.email_replay_lag_streaming_replication();$sql$
WHERE display_name = 'Number of standby servers lag behind the master by replay location' AND object_type = 200;

-- Update statements for detailed information of database level alerts
UPDATE pem.alert_template SET info_sql = $sql$SELECT srv.description AS "Server name", b.database_name AS "Database name",
       b.schema_name AS "Schema name", b.table_name AS "Table name", b.estimated_pages AS "Estimated pages",
       b.estimated_bloat_multiple AS "Estimated bloat multiple", b.estimated_pages_wasted AS "Estimated pages wasted",
       b.estimated_bytes_per_tuple AS "Estimated bytes per tuple"
FROM pemdata.table_bloat AS b
JOIN pemdata.settings AS s
ON b.server_id = s.server_id
JOIN pem.server AS srv
ON b.server_id = srv.id
AND s.name = 'block_size'
WHERE b.server_id = '${server_id}'::integer
AND   b.database_name = '${database_name}'::text
AND ((b.estimated_pages_wasted*s.setting::integer)/1048576) ${comparison_operator} '${threshold_value}'::numeric
AND
    (b.schema_name != '' AND
                    b.schema_name NOT IN (
                        'pg_catalog', 'sys', 'information_schema'
                    ) AND
                    b.schema_name NOT LIKE 'pg_toast%%' AND
                    b.schema_name NOT LIKE 'pg_temp%%') ORDER BY ((b.estimated_pages_wasted*s.setting::integer)/1048576) DESC;$sql$
WHERE display_name = 'Highest table bloat in database' AND object_type = 300;

UPDATE pem.alert_template SET info_sql = $sql$SELECT table_name AS "Table name", database_name AS "Database name",
total_table_size_mb AS "Total table size(MB)"
FROM pemdata.table_size
WHERE	server_id = ${server_id}
AND		database_name = '${database_name}'
AND total_table_size_mb ${comparison_operator} '${threshold_value}'::numeric ORDER BY total_table_size_mb DESC;$sql$
  WHERE display_name = 'Table size in database' AND object_type = 300;

UPDATE pem.alert_template SET info_sql = $sql$SELECT s.description AS "Server name",
        si.database_name AS "Database name", si.procpid AS "Process ID", si.usename AS "Username",
        si.backend_start AS "Process start time", si.xact_start AS "Transaction start time", si.query_start AS "Query start time",
        si.is_waiting AS "Is Waiting?", si.is_idle AS "Is Idle?", si.is_idle_in_transaction AS "Is idle in transaction?",
        si.is_vacuum AS "Is vacuum?", si.is_autovacuum AS "Is autovacuum?", si.wait_event_type AS "Wait event type", si.wait_event AS "Wait event"
       FROM
           pemdata.session_info AS si
           JOIN pem.server AS s
           ON si.server_id = s.id
       WHERE
           si.server_id = '${server_id}'::integer
           AND  si.database_name = '${database_name}'::text ORDER BY s.description;$sql$
WHERE display_name = 'Total connections' AND object_type = 300;

UPDATE pem.alert_template SET info_sql = $sql$SELECT s.description AS "Server name",
        si.database_name AS "Database name", si.procpid AS "Process ID", si.usename AS "Username",
        si.backend_start AS "Process start time", si.xact_start AS "Transaction start time", si.query_start AS "Query start time",
        si.is_waiting AS "Is Waiting?", si.is_idle AS "Is Idle?", si.is_idle_in_transaction AS "Is idle in transaction?",
        si.is_vacuum AS "Is vacuum?", si.is_autovacuum AS "Is autovacuum?", si.wait_event_type AS "Wait event type", si.wait_event AS "Wait event"
    FROM
        pemdata.session_info AS si
        JOIN pem.server AS s
        ON si.server_id = s.id
    WHERE
        si.is_idle IS TRUE
        AND si.server_id = '${server_id}'::integer
        AND si.database_name = '${database_name}'::text ORDER BY s.description;$sql$
WHERE display_name = 'Connections in idle state' AND object_type = 300;

UPDATE pem.alert_template SET info_sql = $sql$SELECT s.description AS "Server name",
        si.database_name AS "Database name", si.procpid AS "Process ID", si.usename AS "Username",
        si.backend_start AS "Process start time", si.xact_start AS "Transaction start time", si.query_start AS "Query start time",
        si.is_waiting AS "Is Waiting?", si.is_idle AS "Is Idle?", si.is_idle_in_transaction AS "Is idle in transaction?",
        si.is_vacuum AS "Is vacuum?", si.is_autovacuum AS "Is autovacuum?", si.wait_event_type AS "Wait event type", si.wait_event AS "Wait event"
    FROM
        pemdata.session_info AS si
        JOIN pem.server AS s
        ON si.server_id = s.id
    WHERE
        si.is_idle_in_transaction IS TRUE
        AND si.server_id = '${server_id}'::integer
        AND si.database_name = '${database_name}'::text ORDER BY s.description;$sql$
WHERE display_name = 'Connections in idle-in-transaction state' AND object_type = 300;

UPDATE pem.alert_template SET info_sql = $sql$SELECT s.description AS "Server name", sr.database_name AS "Database name",
        sr.cluster_name AS "Cluster name", sr.lag_num_events AS "Number of lag events", sr.lag_time AS "Lag time"
    FROM
        pemdata.slony_replication AS sr
        JOIN pem.server AS s
        ON sr.server_id = s.id
    WHERE
        sr.server_id = '${server_id}'::integer
        AND sr.database_name = '${database_name}'::text ORDER BY sr.lag_time DESC;$sql$
WHERE display_name = 'Total events lagging in all slony clusters' AND object_type = 300;

UPDATE pem.alert_template SET info_sql = $sql$SELECT s.description AS "Server name", x.database_name AS "Database name",
        x.xdb_smr_lag_rows AS "SMR lag rows", x.xdb_mmr_lag_rows AS "MMR lag rows"
    FROM
        pemdata.xdb_smr_mmr_replication AS x
        JOIN pem.server AS s
        ON x.server_id = s.id
    WHERE
        x.server_id = '${server_id}'::integer
        AND x.database_name = '${database_name}'::text ORDER BY x.xdb_smr_lag_rows DESC;$sql$
WHERE display_name = 'Total rows lagging in xdb single master replication' AND object_type = 300;

UPDATE pem.alert_template SET info_sql = $sql$SELECT s.description AS "Server name",
        x.database_name AS "Database name", x.xdb_smr_lag_rows AS "SMR lag rows", x.xdb_mmr_lag_rows AS "MMR lag rows"
    FROM
        pemdata.xdb_smr_mmr_replication AS x
        JOIN pem.server AS s
        ON x.server_id = s.id
    WHERE
        x.server_id = '${server_id}'::integer
        AND x.database_name = '${database_name}'::text ORDER BY x.xdb_mmr_lag_rows DESC;$sql$
WHERE display_name = 'Total rows lagging in xdb multi master replication' AND object_type = 300;

UPDATE pem.alert_template SET info_sql = $sql$SELECT s.description AS "Server name",
        si.database_name AS "Database name", si.procpid AS "Process ID", si.usename AS "Username",
        si.backend_start AS "Process start time", si.xact_start AS "Transaction start time", si.query_start AS "Query start time",
        si.is_waiting AS "Is Waiting?", si.is_idle AS "Is Idle?", si.is_idle_in_transaction AS "Is idle in transaction?",
        si.is_vacuum AS "Is vacuum?", si.is_autovacuum AS "Is autovacuum?", si.wait_event_type AS "Wait event type", si.wait_event AS "Wait event"
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

UPDATE pem.alert_template SET info_sql = $sql$SELECT s.description AS "Server name",
        si.database_name AS "Database name", si.procpid AS "Process ID", si.usename AS "Username",
        si.backend_start AS "Process start time", si.xact_start AS "Transaction start time", si.query_start AS "Query start time",
        si.is_waiting AS "Is Waiting?", si.is_idle AS "Is Idle?", si.is_idle_in_transaction AS "Is idle in transaction?",
        si.is_vacuum AS "Is vacuum?", si.is_autovacuum AS "Is autovacuum?", si.wait_event_type AS "Wait event type", si.wait_event AS "Wait event"
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

UPDATE pem.alert_template SET info_sql = $sql$SELECT s.description AS "Server name",
        si.database_name AS "Database name", si.procpid AS "Process ID", si.usename AS "Username",
        si.backend_start AS "Process start time", si.xact_start AS "Transaction start time", si.query_start AS "Query start time",
        si.is_waiting AS "Is Waiting?", si.is_idle AS "Is Idle?", si.is_idle_in_transaction AS "Is idle in transaction?",
        si.is_vacuum AS "Is vacuum?", si.is_autovacuum AS "Is autovacuum?", si.wait_event_type AS "Wait event type", si.wait_event AS "Wait event"
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

UPDATE pem.alert_template SET info_sql = $sql$SELECT s.description AS "Server name",
        si.database_name AS "Database name", si.procpid AS "Process ID", si.usename AS "Username",
        si.backend_start AS "Process start time", si.xact_start AS "Transaction start time", si.query_start AS "Query start time",
        si.is_waiting AS "Is Waiting?", si.is_idle AS "Is Idle?", si.is_idle_in_transaction AS "Is idle in transaction?",
        si.is_vacuum AS "Is vacuum?", si.is_autovacuum AS "Is autovacuum?", si.wait_event_type AS "Wait event type", si.wait_event AS "Wait event"
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

UPDATE pem.alert_template SET info_sql = $sql$SELECT s.description AS "Server name",
        si.database_name AS "Database name", si.procpid AS "Process ID", si.usename AS "Username",
        si.backend_start AS "Process start time", si.xact_start AS "Transaction start time", si.query_start AS "Query start time",
        si.is_waiting AS "Is Waiting?", si.is_idle AS "Is Idle?", si.is_idle_in_transaction AS "Is idle in transaction?",
        si.is_vacuum AS "Is vacuum?", si.is_autovacuum AS "Is autovacuum?", si.wait_event_type AS "Wait event type", si.wait_event AS "Wait event"
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

UPDATE pem.alert_template SET info_sql = $sql$SELECT s.description AS "Server name",
        si.database_name AS "Database name", si.procpid AS "Process ID", si.usename AS "Username",
        si.backend_start AS "Process start time", si.xact_start AS "Transaction start time", si.query_start AS "Query start time",
        si.is_waiting AS "Is Waiting?", si.is_idle AS "Is Idle?", si.is_idle_in_transaction AS "Is idle in transaction?",
        si.is_vacuum AS "Is vacuum?", si.is_autovacuum AS "Is autovacuum?", si.wait_event_type AS "Wait event type", si.wait_event AS "Wait event"
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

UPDATE pem.alert_template SET info_sql = $sql$SELECT s.description AS "Server name",
        si.database_name AS "Database name", si.procpid AS "Process ID", si.usename AS "Username",
        si.backend_start AS "Process start time", si.xact_start AS "Transaction start time", si.query_start AS "Query start time",
        si.is_waiting AS "Is Waiting?", si.is_idle AS "Is Idle?", si.is_idle_in_transaction AS "Is idle in transaction?",
        si.is_vacuum AS "Is vacuum?", si.is_autovacuum AS "Is autovacuum?", si.wait_event_type AS "Wait event type", si.wait_event AS "Wait event"
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

-- Update statements for detailed information of schema level alerts
UPDATE pem.alert_template SET info_sql = $sql$SELECT srv.description AS "Server name",
       b.database_name AS "Database name", b.schema_name AS "Schema name",
       b.table_name AS "Table name", b.estimated_pages AS "Estimated pages",
       b.estimated_bloat_multiple AS "Estimated bloat multiple", b.estimated_pages_wasted AS "Estimated pages wasted",
       b.estimated_bytes_per_tuple AS "Estimated bytes per tuple"
FROM pemdata.table_bloat AS b
JOIN pemdata.settings AS s
ON		b.server_id = s.server_id
JOIN pem.server AS srv
ON b.server_id = srv.id
AND		s.name = 'block_size'
WHERE b.server_id = '${server_id}'::integer
AND   b.database_name = '${database_name}'::text
AND   b.schema_name = '${schema_name}'::text
AND ((b.estimated_pages_wasted*s.setting::integer)/1048576) ${comparison_operator} '${threshold_value}'::numeric ORDER BY ((b.estimated_pages_wasted*s.setting::integer)/1048576) DESC;$sql$
WHERE display_name = 'Highest table bloat in schema' AND object_type = 400;

UPDATE pem.alert_template SET info_sql = $sql$SELECT table_name AS "Table name", database_name AS "Database name",
schema_name AS "Schema name", total_table_size_mb AS "Total table size(MB)"
FROM pemdata.table_size
WHERE	server_id = ${server_id}
AND		database_name = '${database_name}'
AND		schema_name = '${schema_name}'
AND total_table_size_mb ${comparison_operator} '${threshold_value}'::numeric ORDER BY total_table_size_mb DESC;$sql$
  WHERE display_name = 'Table size in schema' AND object_type = 400;

CREATE OR REPLACE FUNCTION pem.create_default_agent_alerts(agent_id integer)
RETURNS VOID AS $$
DECLARE
	temp_rec record;
BEGIN

	FOR temp_rec IN EXECUTE 'SELECT id, display_name, default_check_frequency, default_history_retention, operator, thresholds FROM pem.alert_template WHERE object_type = 100 and is_auto_create ORDER BY id'
	LOOP
		IF NOT pem.check_alert_exist(temp_rec.display_name, $1, NULL, NULL, NULL, NULL, NULL, 100) THEN
			PERFORM pem.create_alert(temp_rec.display_name, temp_rec.id,
			$1, NULL, NULL, NULL, NULL, NULL, '{}', temp_rec.operator, temp_rec.thresholds,
			temp_rec.default_check_frequency, temp_rec.default_history_retention, true, true);
		END IF;
	END LOOP;

END;
$$ LANGUAGE plpgsql;

DROP FUNCTION pem.create_default_server_alerts(integer);
CREATE OR REPLACE FUNCTION pem.create_default_server_alerts(server_id integer, server_version_id integer DEFAULT 0)
RETURNS VOID AS $$
DECLARE
	temp_rec record;
	sql text;
BEGIN

	IF server_version_id = 0 THEN
		sql = 'SELECT id, display_name, default_check_frequency, default_history_retention, operator, thresholds FROM pem.alert_template WHERE object_type = 200 and is_auto_create and applicable_on_server = ''ALL'' ORDER BY id';
	ELSIF (server_version_id > 10900 AND server_version_id < 20000) THEN
		sql = 'SELECT id, display_name, default_check_frequency, default_history_retention, operator, thresholds FROM pem.alert_template WHERE object_type = 200 and is_auto_create and applicable_on_server IN (''ALL'', ''POSTGRES_SERVER'') ORDER BY id';
	ELSIF (server_version_id > 20000) THEN
		sql = 'SELECT id, display_name, default_check_frequency, default_history_retention, operator, thresholds FROM pem.alert_template WHERE object_type = 200 and is_auto_create and applicable_on_server IN (''ALL'', ''ADVANCED_SERVER'') ORDER BY id';
	END IF;

	FOR temp_rec IN EXECUTE sql
	LOOP
		IF NOT pem.check_alert_exist(temp_rec.display_name, 0, $1, NULL, NULL, NULL, NULL, 200) THEN
			PERFORM pem.create_alert(temp_rec.display_name, temp_rec.id,
			0, $1, NULL, NULL, NULL, NULL, '{}', temp_rec.operator, temp_rec.thresholds,
			temp_rec.default_check_frequency, temp_rec.default_history_retention, true, true);
		END IF;
	END LOOP;

END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION pem.auto_create_alerts_on_exisiting_servers()
RETURNS VOID AS $$
DECLARE
	rec record;
	server_version integer;
BEGIN
	FOR rec in (SELECT id FROM pem.server WHERE active = true)
	LOOP
		SELECT server_version_id INTO server_version FROM pemdata.server_info WHERE server_id = rec.id;
		IF NOT FOUND THEN
		  PERFORM pem.create_default_server_alerts(rec.id, 0);
		ELSE
		  PERFORM pem.create_default_server_alerts(rec.id, server_version);
		END IF;
	END LOOP;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION pem.auto_create_alerts_on_exisiting_agents()
RETURNS VOID AS $$
DECLARE
	rec record;
BEGIN
	FOR rec in (SELECT id FROM pem.agent WHERE active = true)
	LOOP
		PERFORM pem.create_default_agent_alerts(rec.id);
	END LOOP;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION pem.alert_template_postupdate() RETURNS trigger AS $$
BEGIN
	UPDATE pem.alert SET error_message = '' WHERE template_id = NEW.id;
	IF NEW.is_auto_create AND OLD.is_auto_create <> NEW.is_auto_create THEN
	    IF NEW.object_type = 100 THEN
		    PERFORM pem.auto_create_alerts_on_exisiting_agents();
	    ELSIF NEW.object_type = 200 THEN
		    PERFORM pem.auto_create_alerts_on_exisiting_servers();
	    END IF;
	END IF;
	RETURN NULL;
END
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION pem.alert_template_postinsert() RETURNS trigger AS $$
BEGIN
	IF NEW.is_auto_create THEN
	    IF NEW.object_type = 100 THEN
		    PERFORM pem.auto_create_alerts_on_exisiting_agents();
	    ELSIF NEW.object_type = 200 THEN
		    PERFORM pem.auto_create_alerts_on_exisiting_servers();
	    END IF;
	END IF;
	RETURN NULL;
END
$$ LANGUAGE plpgsql;

CREATE TRIGGER custom_alert_template_postinsert
	AFTER INSERT ON pem.alert_template
	FOR EACH ROW EXECUTE PROCEDURE pem.alert_template_postinsert();

CREATE OR REPLACE FUNCTION pem.agent_postupdate() RETURNS trigger AS $$
BEGIN
	IF (OLD.active AND NOT NEW.active) THEN
		DELETE FROM pem.agent_server_binding WHERE agent_id = NEW.id;
		DELETE FROM pem.alert WHERE agent_id = NEW.id;
	END IF;
	RETURN NULL;
END
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION pem.server_postupdate() RETURNS trigger AS $$
BEGIN
	IF (OLD.active AND NOT NEW.active) THEN
		DELETE FROM pem.agent_server_binding WHERE server_id = NEW.id;
		DELETE FROM pem.alert WHERE server_id = NEW.id;
		DELETE FROM pem.job WHERE jobid IN (SELECT j.jobid FROM pem.job j INNER JOIN pem.jobstep js ON j.jobid = js.jstjobid WHERE js.server_id = NEW.id AND j.issystemjob != TRUE);
	END IF;
	RETURN NULL;
END
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION pem.agent_postdelete() RETURNS trigger AS $$
BEGIN
	DELETE FROM pem.alert WHERE agent_id = OLD.id;
	RETURN NULL;
END
$$ LANGUAGE plpgsql;

CREATE TRIGGER agent_postdelete
	AFTER DELETE ON pem.agent
	FOR EACH ROW EXECUTE PROCEDURE pem.agent_postdelete();

CREATE OR REPLACE FUNCTION pem.server_postdelete() RETURNS trigger AS $$
BEGIN
	DELETE FROM pem.alert WHERE server_id = OLD.id;
	RETURN NULL;
END
$$ LANGUAGE plpgsql;

CREATE TRIGGER server_postdelete
	AFTER DELETE ON pem.server
	FOR EACH ROW EXECUTE PROCEDURE pem.server_postdelete();

-- Create hstore extension to extract key and value pair from tables rows.
CREATE EXTENSION hstore;

-- Function to execute detail alert info SQL and insert formatted string in pem.alert_status table.
CREATE OR REPLACE FUNCTION pem.get_detail_alert_info() RETURNS TRIGGER AS $$
DECLARE
	info_sql    text := '';
	a_agent_id  integer;
	a_server_id integer;
	a_database_name text:= '';
	a_schema_name text:= '';
	a_package_name text:= '';
	a_object_name text:= '';
	alert_info_str text:= '';
	comp_operator  text:= '';
	low_threshold_val text:= '';
	alert_params text[];
	info_sql_curs     REFCURSOR;
	info_sql_rec      RECORD;
	hs_row            RECORD;
	first_time    boolean := FALSE;
	arr_col_names text[];
	arr_col_values text[];
	arr_col_final text[][];
	column_name text := '';
	column_value text := '';
BEGIN
        IF (NEW.alert_id IS NOT NULL)
        THEN
                -- Fetch additional sql to execute from the alert template table.
                EXECUTE 'SELECT info_sql FROM pem.alert_template WHERE id = (SELECT template_id FROM pem.alert WHERE id = ' || NEW.alert_id || ')' INTO info_sql;

                EXECUTE 'SELECT operator::text FROM pem.alert WHERE id = ' || NEW.alert_id INTO comp_operator;

                EXECUTE 'SELECT thresholds[1]::text FROM pem.alert WHERE id = ' || NEW.alert_id INTO low_threshold_val;

                EXECUTE 'SELECT params::text[] FROM pem.alert WHERE id = ' || NEW.alert_id INTO alert_params;

                -- If additional information sql is null or empty then no need to get extra information.
                IF (info_sql IS NOT NULL AND info_sql != '' AND comp_operator IS NOT NULL AND comp_operator != '' AND
                    low_threshold_val IS NOT NULL AND low_threshold_val != '') THEN
                    -- Fist find the all the objects of this alert.
                    EXECUTE 'SELECT agent_id FROM pem.alert WHERE id = ' || NEW.alert_id INTO a_agent_id;
                    EXECUTE 'SELECT server_id FROM pem.alert WHERE id = ' || NEW.alert_id INTO a_server_id;
                    EXECUTE 'SELECT database_name FROM pem.alert WHERE id = ' || NEW.alert_id INTO a_database_name;
                    EXECUTE 'SELECT schema_name FROM pem.alert WHERE id = ' || NEW.alert_id INTO a_schema_name;
                    EXECUTE 'SELECT package_name FROM pem.alert WHERE id = ' || NEW.alert_id INTO a_package_name;
                    EXECUTE 'SELECT object_name FROM pem.alert WHERE id = ' || NEW.alert_id INTO a_object_name;

                    -- Replace any reference to hierarchy-related alert parameters.
                    info_sql = regexp_replace(info_sql, E'\\${agent_id}', COALESCE(a_agent_id::text, '')::text, 'g');
                    info_sql = regexp_replace(info_sql, E'\\${server_id}', COALESCE(a_server_id::text, '')::text, 'g');
                    info_sql = regexp_replace(info_sql, E'\\${database_name}', COALESCE(a_database_name, '')::text, 'g');
                    info_sql = regexp_replace(info_sql, E'\\${schema_name}', COALESCE(a_schema_name, '')::text, 'g');
                    info_sql = regexp_replace(info_sql, E'\\${package_name}', COALESCE(a_package_name, '')::text, 'g');
                    info_sql = regexp_replace(info_sql, E'\\${object_name}', COALESCE(a_object_name, '')::text, 'g');
                    info_sql = regexp_replace(info_sql, E'\\${comparison_operator}', COALESCE(comp_operator::text, '')::text, 'g');
                    info_sql = regexp_replace(info_sql, E'\\${threshold_value}', COALESCE(low_threshold_val::text, '')::text, 'g');

                    /* Replace ${param_n} with corresponding alert parameters */
                    FOR i IN 1..COALESCE(array_upper(alert_params, 1), 0) LOOP
                        info_sql = regexp_replace(info_sql, E'\\${param_' || i || '}', alert_params[i]::text, 'g');
                    END LOOP;

		    arr_col_final := '{}';
                    OPEN info_sql_curs FOR EXECUTE info_sql;

                    LOOP
                        FETCH NEXT FROM info_sql_curs INTO info_sql_rec;
                        EXIT WHEN NOT FOUND;

			column_value := '';

                        FOR hs_row IN SELECT kv."key", kv."value" FROM each(hstore(info_sql_rec)) kv
                        LOOP
                            alert_info_str := alert_info_str || COALESCE(hs_row."key", '') || ' = ' || COALESCE(hs_row."value", '') || E'\n';

			    IF first_time IS FALSE THEN
				column_name := column_name || COALESCE(hs_row."key", '') || ',';
			    END IF;

			    column_value := column_value || COALESCE(hs_row."value", '') || ',';

                        END LOOP;

			first_time := TRUE;

			column_value = regexp_replace(column_value, ',$', '');
			SELECT string_to_array(column_value, ',') INTO arr_col_values;
			arr_col_final := arr_col_final || ARRAY[arr_col_values]::text[][];

                        alert_info_str := alert_info_str || E'\n\n';

                    END LOOP;
                    CLOSE info_sql_curs;

		    IF first_time IS FALSE THEN
			NEW.info_cols = NULL;
			NEW.info_vals = NULL;
			NEW.info = NULL;
		    ELSE
		        column_name = regexp_replace(column_name, ',$', '');

		        SELECT string_to_array(column_name, ',') INTO arr_col_names;
		        NEW.info_cols = arr_col_names;
		        NEW.info_vals = arr_col_final;

			IF (alert_info_str IS NOT NULL AND alert_info_str != '') THEN
			    NEW.info = alert_info_str;
			END IF;
		    END IF;
                END IF;
        END IF;

        RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION pem.process_one_alert() RETURNS BOOL AS $$
DECLARE
	err			text;
	sql			text;
	state			pem.alert_state;
	sql_ret			numeric;
	alert_rec		record;
	locked_alert		bool;
	probe_disabled_err	text;
	zero_rows_err		text;
	probe_enabled		bool;
	all_probes_enabled	bool;
	alert_state_since	timestamp with time zone;
	reminder_interval	integer;
	subject			text;
	message			text;
	send_mail_val		bool;
	min_probe_interval	integer;
	probe_interval		integer;
	default_flapping_detection_state_change integer;
	down_objects_list text;
	template_name text;
	mail_group_id integer[];
	alert_info    text;
BEGIN
	probe_disabled_err = 'Required probe(s) ';
	zero_rows_err = 'Zero rows returned';

	locked_alert = false;

	FOR alert_rec in	SELECT al.*, ast.current_state AS state, at.sql, at.display_name AS template_name,
								at.probe_dependency_list, ast.state_change_count
						FROM (pem.alert AS al
								JOIN pem.alert_template AS at
								ON al.template_id = at.id)
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
	LOOP
		IF (pg_try_advisory_lock(0, alert_rec.id) = true) THEN
			locked_alert = true;
			EXIT; /* the loop */
		END IF;
	END LOOP;

	/* If we couldn't find or lock any candidate alert ... */
	IF (locked_alert = false) THEN
		/* tell the caller that we didn't process any alerts */
		RETURN false;
	END IF;

	/*
	 * We should return only 'true' from here on, since there may be more alerts
	 * to process.
	 *
	 * Also try to capture any ERROR and mark the alert as invalid
	 * instead of passing that ERROR back to the caller.
	 */

	sql = alert_rec.sql;

	/* Replace any reference to hierarchy-related alert parameters */
	sql = regexp_replace(sql, E'\\${agent_id}',		COALESCE(alert_rec.agent_id::text,	'')::text, 'g');
	sql = regexp_replace(sql, E'\\${server_id}',	COALESCE(alert_rec.server_id::text,	'')::text, 'g');
	sql = regexp_replace(sql, E'\\${database_name}',COALESCE(alert_rec.database_name,	'')::text, 'g');
	sql = regexp_replace(sql, E'\\${schema_name}',	COALESCE(alert_rec.schema_name,		'')::text, 'g');
	sql = regexp_replace(sql, E'\\${package_name}',	COALESCE(alert_rec.package_name,	'')::text, 'g');
	sql = regexp_replace(sql, E'\\${object_name}',	COALESCE(alert_rec.object_name,		'')::text, 'g');

	/* Replace ${param_n} with corresponding alert parameters */
	FOR i IN 1..COALESCE(array_upper(alert_rec.params, 1), 0) LOOP
		sql = regexp_replace(sql, E'\\${param_' || i || '}', alert_rec.params[i]::text, 'g');
	END LOOP;

	err = '';

	/* Check any required probe is disabled from the probe dependency list */
	all_probes_enabled = true;
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
			probe_disabled_err = probe_disabled_err || alert_rec.probe_dependency_list[i] || ',';
			all_probes_enabled = false;
		END IF;

		-- Get minimum probe interval from all dependent probes
		SELECT default_execution_frequency INTO probe_interval FROM pem.probe WHERE internal_name = alert_rec.probe_dependency_list[i];
		IF (probe_interval <  min_probe_interval) OR (i = 1) THEN
			min_probe_interval = probe_interval;
		END IF;
	END LOOP;

	probe_disabled_err = trim(trailing ',' from probe_disabled_err);
	probe_disabled_err = probe_disabled_err || ' are disabled.';

	IF NOT all_probes_enabled THEN
		err = probe_disabled_err;
	ELSE
		RAISE DEBUG 'Alert query being executed: %', sql;

		BEGIN
			EXECUTE sql INTO STRICT sql_ret;
		EXCEPTION
			WHEN no_data_found THEN
				IF all_probes_enabled THEN
					err = zero_rows_err;
				END IF;

			WHEN OTHERS THEN
				err = SQLERRM;
		END;
	END IF;

	-- If there was an error while processing the alert's sql
	IF (err <> '') THEN
		-- Set that error message on the alert
		UPDATE pem.alert
		SET error_message = err
		WHERE id = alert_rec.id;

		-- ... and also set the last processed timestamp
		UPDATE pem.alert_status
		SET last_processed = now()
		WHERE alert_id = alert_rec.id;

		-- If there wasn't any row for this alert already, then populate one.
		IF (NOT FOUND) THEN
			INSERT INTO pem.alert_status
			VALUES (alert_rec.id, NULL, NULL, NULL, now());
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
			state = 'HIGH';
		ELSIF (sql_ret < alert_rec.thresholds[2]) THEN
			state = 'MEDIUM';
		ELSIF (sql_ret < alert_rec.thresholds[1]) THEN
			state = 'LOW';
		ELSE
			state = NULL;
		END IF;
	ELSIF (alert_rec.operator = '>') THEN
		IF (sql_ret > alert_rec.thresholds[3]) THEN
			state = 'HIGH';
		ELSIF (sql_ret > alert_rec.thresholds[2]) THEN
			state = 'MEDIUM';
		ELSIF (sql_ret > alert_rec.thresholds[1]) THEN
			state = 'LOW';
		ELSE
			state = NULL;
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
	 *        set acked = false
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
				send_mail_val = pem.send_email(mail_group_id, subject, message);
				IF send_mail_val THEN
					-- update the time of mail send.
					UPDATE pem.alert SET last_mail_send = now() WHERE id = alert_rec.id;
				END IF;
			END IF;
		END IF;
	END IF;

	UPDATE pem.alert_status
	SET last_processed = now(),
		current_value = sql_ret,
		current_state = state, -- may be NULL
		current_state_since =	CASE
								WHEN state IS DISTINCT FROM alert_rec.state
								THEN now()
								ELSE current_state_since
								END
	WHERE alert_id = alert_rec.id;

	-- If there wasn't any status row for this alert already, then populate one.
	IF (NOT FOUND) THEN
		INSERT INTO pem.alert_status
		VALUES (alert_rec.id, sql_ret, state,
				CASE
				WHEN state IS NOT NULL
				THEN now()
				ELSE NULL
				END,
				now());
	END IF;

	-- Check for reminder notification
	SELECT value INTO reminder_interval FROM pem.config WHERE param = 'reminder_notification_interval';
	SELECT current_state_since INTO alert_state_since FROM pem.alert_status WHERE alert_id = alert_rec.id;
	IF alert_rec.send_email AND (NOT alert_rec.acknowledged) AND (alert_state_since IS NOT NULL) AND (state IS NOT NULL) AND (NOT alert_rec.flapping_detected)
	AND ((now() - alert_state_since) >= (reminder_interval||'hours')::interval)
	AND ((now() - alert_rec.last_mail_send) >= (reminder_interval||'hours')::interval) THEN

		-- Create subject and message
		SELECT subject_mail, message_mail INTO subject, message FROM pem.create_email(alert_rec.id, 'Alert Reminder');
		SELECT info INTO alert_info FROM pem.alert_status WHERE alert_id = alert_rec.id;
		message = regexp_replace(message, '%CurrentValue%', COALESCE(sql_ret, 0)::text);
		message = regexp_replace(message, '%CurrentState%', state::text);
		message = regexp_replace(message, '%AlertingSince%', alert_state_since::text);

		-- Get the list of down objetcs
		down_objects_list = pem.get_down_objects_list(alert_rec.template_name);
		message = regexp_replace(message, '%DownObjects%', down_objects_list::text);
		message = regexp_replace(message, '%DetailInfo%', COALESCE(alert_info, 'None')::text);

		send_mail_val = pem.send_email(mail_group_id, subject, message);
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

CREATE TRIGGER detail_alert_information
        BEFORE INSERT OR UPDATE ON pem.alert_status
        FOR EACH ROW
        EXECUTE PROCEDURE pem.get_detail_alert_info();

-- Email Notification changes as below.
UPDATE pem.email_template SET mail_message = E'Alert Details\n------------------------\nAlert Name: %AlertName%\nServer/Agent: %ObjectName%\nCurrent Value: %CurrentValue%\nThreshold Value: %ThresholdValue%\nAlert Detected: %AlertDetected%\n%DownObjects%\nDetail Information: \n%DetailInfo%'
WHERE display_name = 'Alert Detected' AND mail_message = E'Alert Details\n------------------------\nAlert Name: %AlertName%\nServer/Agent: %ObjectName%\nCurrent Value: %CurrentValue%\nThreshold Value: %ThresholdValue%\nAlert Detected: %AlertDetected%\n%DownObjects%';

UPDATE pem.email_template SET mail_message = E'Alert Details\n------------------------\nAlert Name: %AlertName%\nServer/Agent: %ObjectName%\nCurrent Value: %CurrentValue%\nThreshold Value: %ThresholdValue%\nCurrent State: %CurrentState%\nOld State: %OldState%\nState Changed: %StateChanged%\n%DownObjects%\nDetail Information: \n%DetailInfo%'
WHERE display_name = 'Alert Level Increased' AND mail_message = E'Alert Details\n------------------------\nAlert Name: %AlertName%\nServer/Agent: %ObjectName%\nCurrent Value: %CurrentValue%\nThreshold Value: %ThresholdValue%\nCurrent State: %CurrentState%\nOld State: %OldState%\nState Changed: %StateChanged%\n%DownObjects%';

UPDATE pem.email_template SET mail_message = E'Alert Details\n------------------------\nAlert Name: %AlertName%\nServer/Agent: %ObjectName%\nCurrent Value: %CurrentValue%\nThreshold Value: %ThresholdValue%\nCurrent State: %CurrentState%\nOld State: %OldState%\nState Changed: %StateChanged%\n%DownObjects%\nDetail Information: \n%DetailInfo%'
WHERE display_name = 'Alert Level Decreased' AND mail_message = E'Alert Details\n------------------------\nAlert Name: %AlertName%\nServer/Agent: %ObjectName%\nCurrent Value: %CurrentValue%\nThreshold Value: %ThresholdValue%\nCurrent State: %CurrentState%\nOld State: %OldState%\nState Changed: %StateChanged%\n%DownObjects%';

UPDATE pem.email_template SET mail_message = E'Alert Details\n------------------------\nAlert Name: %AlertName%\nCurrent Value: %CurrentValue%\nThreshold Value: %ThresholdValue%\nCurrent State: %CurrentState%\nAlerting Since: %AlertingSince%\n%DownObjects%\nDetail Information: \n%DetailInfo%'
WHERE display_name = 'Alert Reminder' AND mail_message = E'Alert Details\n------------------------\nAlert Name: %AlertName%\nServer/Agent: %ObjectName%\nCurrent Value: %CurrentValue%\nThreshold Value: %ThresholdValue%\nCurrent State: %CurrentState%\nAlerting Since: %AlertingSince%\n%DownObjects%';


CREATE OR REPLACE FUNCTION pem.send_notifications() RETURNS trigger AS $$
DECLARE
	subject text;
	message text;
	mail_group_id integer[];
	is_send_email boolean:= false;
	is_acknowledged boolean:= false;
	send_mail_val boolean:= false;
	is_flapping_detected boolean:= false;
	is_send_trap boolean:= false;
	trap_oid text;
	enterprise_oid text;
	trap_version integer:= 2;
	varbinding_oid text;
	varbinding_value text;
	send_trap_val boolean:= false;
	templateid integer;
	template_name text;
	down_objects_list text;
	agentid integer;
	low_trap boolean:= false;
	med_trap boolean:= false;
	high_trap boolean:= false;
	is_execute_script boolean:= false;
	is_execute_on_clear boolean:= false;
	is_execute_on_pem_server boolean:= false;
	code text;
	is_submit_to_nagios boolean:= false;
	passive_check_result_text text;
	submit_to_nagios_val boolean:= false;
BEGIN
	-- Get alert details
	SELECT
		agent_id, template_id, send_email, acknowledged, flapping_detected, send_trap, snmp_trap_version, low_send_trap, med_send_trap,
		high_send_trap, execute_script, execute_script_on_clear, execute_script_on_pem_server, script_code, submit_to_nagios
	INTO
		agentid, templateid, is_send_email, is_acknowledged, is_flapping_detected, is_send_trap, trap_version, low_trap, med_trap,
		high_trap, is_execute_script, is_execute_on_clear, is_execute_on_pem_server, code, is_submit_to_nagios
	FROM
		pem.alert
	WHERE
		id = NEW.alert_id;

	-- Get the template name
	SELECT display_name INTO template_name FROM pem.alert_template WHERE id = templateid;

	-- Get the list of Agents/Servers Down
	down_objects_list = pem.get_down_objects_list(template_name);

	IF ((TG_OP = 'INSERT') AND (NEW.current_state IS NOT NULL)) THEN
		-- Update state change count
		UPDATE pem.alert_status SET state_change_count = state_change_count + 1 WHERE alert_id = NEW.alert_id;

		-- Get group id's to send email
		SELECT ARRAY(SELECT DISTINCT UNNEST(pem.get_email_group_ids(NEW.alert_id, NEW.current_state::text, ''))) INTO mail_group_id;

		-- Check whether to send trap according to alert level low, med and high.
		IF (NEW.current_state IS NOT NULL) AND (NEW.current_state::text = 'LOW') AND low_trap THEN
			is_send_trap = true;
		ELSIF (NEW.current_state IS NOT NULL) AND (NEW.current_state::text = 'MEDIUM') AND med_trap THEN
			is_send_trap = true;
		ELSIF (NEW.current_state IS NOT NULL) AND (NEW.current_state::text = 'HIGH') AND high_trap THEN
			is_send_trap = true;
		ELSE
			is_send_trap = false;
		END IF;

		-- SMTP Notifications
		IF is_send_email AND (NOT is_acknowledged) AND (NOT is_flapping_detected) THEN
			-- Create subject and message
			SELECT subject_mail, message_mail INTO subject, message FROM pem.create_email(NEW.alert_id, 'Alert Detected');
			subject = regexp_replace(subject, '%AlertType%', NEW.current_state::text);
			message = regexp_replace(message, '%CurrentValue%', COALESCE(NEW.current_value, 0)::text);
			message = regexp_replace(message, '%AlertDetected%', now()::text);
			message = regexp_replace(message, '%DownObjects%', down_objects_list::text);
			message = regexp_replace(message, '%DetailInfo%', COALESCE(NEW.info, 'None')::text);

			-- send emails.
			send_mail_val = pem.send_email(mail_group_id, subject, message);
			IF send_mail_val THEN
				-- update the time of mail send.
				UPDATE pem.alert SET last_mail_send = now() WHERE id = NEW.alert_id;
			END IF;
		END IF;

		-- SNMP Notifications
		IF is_send_trap AND (NOT is_acknowledged) AND (NOT is_flapping_detected) THEN
			-- Create SNMP trap objects
			SELECT
				snmp_trap_oid, snmp_enterprise_oid, snmp_varbinding_oid, snmp_varbinding_value
			INTO
				trap_oid, enterprise_oid, varbinding_oid, varbinding_value
			FROM
				pem.create_trap(NEW.alert_id);

			-- Append varbinding values
			varbinding_value = varbinding_value || '|NULL|' || COALESCE(NEW.current_value, 0)::text || '|NULL|';
			IF NEW.current_state IS NULL THEN
				varbinding_value = varbinding_value || '|CLEAR';
			ELSE
				varbinding_value = varbinding_value || NEW.current_state::text;
			END IF;
			-- Append current timestamp
			varbinding_value = varbinding_value || '|' || now()::text;

			-- Special handling for "Agents Down" and "Servers Down" alert
			IF (template_name = 'Agents Down') OR  (template_name = 'Servers Down') THEN
				varbinding_oid = varbinding_oid || '|' || enterprise_oid || '.7.15';
				varbinding_value = varbinding_value || '|' || down_objects_list::text;
			END IF;

			-- Check if detailed information is available then add variable binding
			IF NEW.info IS NOT NULL THEN
				varbinding_oid = varbinding_oid || '|' || enterprise_oid || '.7.16';
				varbinding_value = varbinding_value || '|' || COALESCE(NEW.info, 'None')::text;
			END IF;

			-- Send SNMP traps
			send_trap_val = pem.send_snmptrap(trap_oid, enterprise_oid, trap_version, varbinding_oid, varbinding_value);
		END IF;

		-- Script Execution
		IF is_execute_script AND (NOT is_acknowledged) AND (NOT is_flapping_detected) THEN
			PERFORM pem.create_script_job(NEW.alert_id, COALESCE(NEW.current_value, 0)::text, NEW.current_state::text, ''::text, is_execute_on_pem_server, code);
		END IF;

		-- submit to Nagios
		IF is_submit_to_nagios AND (NOT is_acknowledged) AND (NOT is_flapping_detected) THEN

			SELECT passive_check_result INTO passive_check_result_text FROM pem.create_passive_service_check_result(NEW.alert_id, 'Alert Detected',
															COALESCE(NEW.current_value, 0)::text,
															NEW.current_state::text);
			submit_to_nagios_val = pem.submit_to_nagios(passive_check_result_text);
		END IF;
	END IF;

	IF ((TG_OP = 'UPDATE') AND (NEW.current_state IS DISTINCT FROM OLD.current_state)) THEN
		-- Update state change count
		UPDATE pem.alert_status SET state_change_count = state_change_count + 1 WHERE alert_id = NEW.alert_id;

		-- Get group id's to send email
		SELECT ARRAY(SELECT DISTINCT UNNEST(pem.get_email_group_ids(NEW.alert_id, NEW.current_state::text, OLD.current_state::text))) INTO mail_group_id;

		-- Check whether to send trap according to alert level low, med and high.
		IF (NEW.current_state IS NOT NULL) AND (NEW.current_state::text = 'LOW' OR OLD.current_state::text = 'LOW') AND low_trap THEN
			is_send_trap = true;
		ELSIF (NEW.current_state IS NOT NULL) AND (NEW.current_state::text = 'MEDIUM' OR OLD.current_state::text = 'MEDIUM') AND med_trap THEN
			is_send_trap = true;
		ELSIF (NEW.current_state IS NOT NULL) AND (NEW.current_state::text = 'HIGH' OR OLD.current_state::text = 'HIGH') AND high_trap THEN
			is_send_trap = true;
		ELSIF (NEW.current_state IS NULL) AND (OLD.current_state IS NOT NULL) AND is_send_trap THEN
			is_send_trap = true;
		ELSE
			is_send_trap = false;
		END IF;

		-- SMTP Notifications
		IF is_send_email AND (NOT is_acknowledged) AND (NOT is_flapping_detected) THEN
			-- If current state is NULL means alert is cleared.
			IF (NEW.current_state IS NOT NULL) THEN
				-- if OLD current_state is not null means alert level changed.
				IF (OLD.current_state IS NOT NULL AND (OLD.current_state > NEW.current_state)) THEN
					-- Create subject and message
					SELECT subject_mail, message_mail INTO subject, message FROM pem.create_email(NEW.alert_id, 'Alert Level Decreased');
					message = regexp_replace(message, '%CurrentState%', NEW.current_state::text);
					message = regexp_replace(message, '%OldState%', OLD.current_state::text);
					message = regexp_replace(message, '%StateChanged%', now()::text);
				ELSIF (OLD.current_state IS NOT NULL AND (OLD.current_state < NEW.current_state)) THEN
					-- Create subject and message
					SELECT subject_mail, message_mail INTO subject, message FROM pem.create_email(NEW.alert_id, 'Alert Level Increased');
					message = regexp_replace(message, '%CurrentState%', NEW.current_state::text);
					message = regexp_replace(message, '%OldState%', OLD.current_state::text);
					message = regexp_replace(message, '%StateChanged%', now()::text);
				ELSE
					-- Create subject and message
					SELECT subject_mail, message_mail INTO subject, message FROM pem.create_email(NEW.alert_id, 'Alert Detected');
					subject = regexp_replace(subject, '%AlertType%', NEW.current_state::text);
					message = regexp_replace(message, '%AlertDetected%', now()::text);
				END IF;
			ELSE
				-- Create subject and message
				SELECT subject_mail, message_mail INTO subject, message FROM pem.create_email(NEW.alert_id, 'Alert Cleared');
				message = regexp_replace(message, '%AlertCleared%', now()::text);
			END IF;

			message = regexp_replace(message, '%CurrentValue%', COALESCE(NEW.current_value, 0)::text);
			message = regexp_replace(message, '%DownObjects%', down_objects_list::text);
			message = regexp_replace(message, '%DetailInfo%', COALESCE(NEW.info, 'None')::text);

			-- send emails.
			send_mail_val = pem.send_email(mail_group_id, subject, message);
			IF send_mail_val THEN
				-- update the time of mail send.
				UPDATE pem.alert SET last_mail_send = now() WHERE id = NEW.alert_id;
			END IF;
		END IF;

		-- SNMP Notifications
		IF is_send_trap AND (NOT is_acknowledged) AND (NOT is_flapping_detected) THEN
			-- Create SNMP trap objects
			SELECT
				snmp_trap_oid, snmp_enterprise_oid, snmp_varbinding_oid, snmp_varbinding_value
			INTO
				trap_oid, enterprise_oid, varbinding_oid, varbinding_value
			FROM
				pem.create_trap(NEW.alert_id);

			-- Append varbinding values
			varbinding_value = varbinding_value || '|' || COALESCE(OLD.current_value, 0)::text || '|' || COALESCE(NEW.current_value, 0)::text;

			IF OLD.current_state IS NULL THEN
				varbinding_value = varbinding_value || '|CLEAR';
			ELSE
				varbinding_value = varbinding_value || '|' || OLD.current_state::text;
			END IF;

			IF NEW.current_state IS NULL THEN
				varbinding_value = varbinding_value || '|CLEAR';
			ELSE
				varbinding_value = varbinding_value || '|' || NEW.current_state::text;
			END IF;
			-- Append current timestamp
			varbinding_value = varbinding_value || '|' || now()::text;

			-- Special handling for "Agents Down" and "Servers Down" alert
			IF (template_name = 'Agents Down') OR  (template_name = 'Servers Down') THEN
				varbinding_oid = varbinding_oid || '|' || enterprise_oid || '.7.15';
				varbinding_value = varbinding_value || '|' || down_objects_list::text;
			END IF;

			-- Check if detailed information is available then add variable binding
			IF NEW.info IS NOT NULL THEN
				varbinding_oid = varbinding_oid || '|' || enterprise_oid || '.7.16';
				varbinding_value = varbinding_value || '|' || COALESCE(NEW.info, 'None')::text;
			END IF;

			-- Send SNMP traps
			send_trap_val = pem.send_snmptrap(trap_oid, enterprise_oid, trap_version, varbinding_oid, varbinding_value);
		END IF;

		-- Script Execution
		IF is_execute_script AND (NOT is_acknowledged) AND (NOT is_flapping_detected) THEN
			-- If current state is NULL means alert is cleared then need to check the value of is_execute_on_clear flag.
			IF (NEW.current_state IS NULL) THEN
				IF is_execute_on_clear THEN
					PERFORM pem.create_script_job(NEW.alert_id, COALESCE(NEW.current_value, 0)::text, NEW.current_state::text, 'CLEAR'::text, is_execute_on_pem_server, code);
				END IF;
			ELSE
				PERFORM pem.create_script_job(NEW.alert_id, COALESCE(NEW.current_value, 0)::text, NEW.current_state::text, OLD.current_state::text, is_execute_on_pem_server, code);
			END IF;
		END IF;

		-- submit to Nagios
		IF is_submit_to_nagios AND (NOT is_acknowledged) AND (NOT is_flapping_detected) THEN

			-- If current state is NULL means alert is cleared.
			IF (NEW.current_state IS NOT NULL) THEN
				-- if OLD current_state is not null means alert level changed.
				IF (OLD.current_state IS NOT NULL AND (OLD.current_state > NEW.current_state)) THEN
					SELECT passive_check_result INTO passive_check_result_text FROM pem.create_passive_service_check_result(NEW.alert_id,
																	'Alert Level Decreased',
																	COALESCE(NEW.current_value, 0)::text,
																	NEW.current_state::text);
					passive_check_result_text = regexp_replace(passive_check_result_text, '%OldState%', OLD.current_state::text);
					passive_check_result_text = regexp_replace(passive_check_result_text, '%NewState%', NEW.current_state::text);

				ELSIF (OLD.current_state IS NOT NULL AND (OLD.current_state < NEW.current_state)) THEN
					SELECT passive_check_result INTO passive_check_result_text FROM pem.create_passive_service_check_result(NEW.alert_id,
																	'Alert Level Increased',
																	COALESCE(NEW.current_value, 0)::text,
																	NEW.current_state::text);
					passive_check_result_text = regexp_replace(passive_check_result_text, '%OldState%', OLD.current_state::text);
					passive_check_result_text = regexp_replace(passive_check_result_text, '%NewState%', NEW.current_state::text);

				ELSE
					SELECT passive_check_result INTO passive_check_result_text FROM pem.create_passive_service_check_result(NEW.alert_id,
																	'Alert Detected',
																	COALESCE(NEW.current_value, 0)::text,
																	NEW.current_state::text);
				END IF;

			ELSE
				SELECT passive_check_result INTO passive_check_result_text FROM pem.create_passive_service_check_result(NEW.alert_id,
																'Alert Cleared',
																COALESCE(NEW.current_value, 0)::text,
																NEW.current_state::text);
			END IF;

			submit_to_nagios_val = pem.submit_to_nagios(passive_check_result_text);
		END IF;
	END IF;

	RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION pem.generate_alert_mib()
RETURNS text AS $$
DECLARE
	mib_text text;
BEGIN

	mib_text = E'\n-- File Name : PEM-ALERTING-MIB\n
-- Date      : ' || now()::text || E'\n
-- Author    : EnterpriseDB \n

PEM-ALERTING-MIB	DEFINITIONS ::= BEGIN

	IMPORTS
		enterprises, MODULE-IDENTITY, OBJECT-TYPE, Integer32, NOTIFICATION-TYPE
			FROM SNMPv2-SMI
		DisplayString
			FROM SNMPv2-TC
		MODULE-COMPLIANCE, OBJECT-GROUP, NOTIFICATION-GROUP
			FROM SNMPv2-CONF;


	postgresql	MODULE-IDENTITY
		LAST-UPDATED	"201109271419Z"
		ORGANIZATION	"EnterpriseDB"
		CONTACT-INFO	"http://www.enterprisedb.com"
		DESCRIPTION	"This MIB file used for alerting notifications."
		REVISION	"201109271419Z"
		DESCRIPTION	"This MIB file used for alerting notifications."
		::=  {  enterprises  27645  }

	pem	OBJECT IDENTIFIER ::=  {  postgresql  5444  }

	agentAlerts	OBJECT IDENTIFIER ::=  {  pem  1  }

	serverAlerts	OBJECT IDENTIFIER ::=  {  pem  2  }

	databaseAlerts	OBJECT IDENTIFIER ::=  {  pem  3  }

	schemaAlerts	OBJECT IDENTIFIER ::=  {  pem  4  }

	objectAlerts	OBJECT IDENTIFIER ::=  {  pem  5  }

	globalAlerts	OBJECT IDENTIFIER ::=  {  pem  6  }

	bindingVariables	OBJECT IDENTIFIER ::=  {  pem  7  }

	pemObjectGroup  OBJECT-GROUP
		OBJECTS { alertName,
			agentID,
			agentName,
			databaseName,
			objectName,
			previousStatus,
			previousValue,
			schemaName,
			serverID,
			serverName,
			status,
			thresholdValue,
			value,
			recordedTime,
			downObjects,
			detailedInformation}
	STATUS 	current
	DESCRIPTION
		"This group contains the notification detail objects"
	::= { postgresql 5445 }

	alertName	OBJECT-TYPE
		SYNTAX			DisplayString
		MAX-ACCESS		read-only
		STATUS			current
		DESCRIPTION		"This parameter gives the alert name"
		::=  {  bindingVariables  1  }

	agentID		OBJECT-TYPE
		SYNTAX			Integer32
		MAX-ACCESS		read-only
		STATUS			current
		DESCRIPTION		"This parameter gives the agent id for which this alert is raised"
		::=  {  bindingVariables  2  }

	serverID	OBJECT-TYPE
		SYNTAX			Integer32
		MAX-ACCESS		read-only
		STATUS			current
		DESCRIPTION		"This parameter gives the server id for which this alert is raised"
		::=  {  bindingVariables  3  }

	agentName	OBJECT-TYPE
		SYNTAX			DisplayString
		MAX-ACCESS		read-only
		STATUS			current
		DESCRIPTION		"This parameter gives the agent name for which this alert is raised"
		::=  {  bindingVariables  4  }

	serverName	OBJECT-TYPE
		SYNTAX			DisplayString
		MAX-ACCESS		read-only
		STATUS			current
		DESCRIPTION		"This parameter gives the server name for which this alert is raised"
		::=  {  bindingVariables  5  }

	databaseName	OBJECT-TYPE
		SYNTAX			DisplayString
		MAX-ACCESS		read-only
		STATUS			current
		DESCRIPTION		"This parameter gives the database name for which this alert is raised"
		::=  {  bindingVariables  6  }

	schemaName	OBJECT-TYPE
		SYNTAX			DisplayString
		MAX-ACCESS		read-only
		STATUS			current
		DESCRIPTION		"This parameter gives the schema name for which this alert is raised"
		::=  {  bindingVariables  7  }

	objectName	OBJECT-TYPE
		SYNTAX			DisplayString
		MAX-ACCESS		read-only
		STATUS			current
		DESCRIPTION		"This parameter gives the object name for which this alert is raised"
		::=  {  bindingVariables  8  }

	thresholdValue	OBJECT-TYPE
		SYNTAX			DisplayString
		MAX-ACCESS		read-only
		STATUS			current
		DESCRIPTION		"This parameter gives the threshold value of the alert"
		::=  {  bindingVariables  9  }

	previousValue	OBJECT-TYPE
		SYNTAX			DisplayString
		MAX-ACCESS		read-only
		STATUS			current
		DESCRIPTION		"This parameter gives the previous value of the alert"
		::=  {  bindingVariables  10  }

	value	OBJECT-TYPE
		SYNTAX			DisplayString
		MAX-ACCESS		read-only
		STATUS			current
		DESCRIPTION		"This parameter gives the current value of the alert"
		::=  {  bindingVariables  11  }

	previousStatus	OBJECT-TYPE
		SYNTAX			INTEGER  { low ( 0 ) , medium ( 1 ), high ( 2 ) }
		MAX-ACCESS		read-only
		STATUS			current
		DESCRIPTION		"This parameter gives the previous status of the alert"
		::=  {  bindingVariables  12  }

	status	OBJECT-TYPE
		SYNTAX			INTEGER  { low ( 0 ) , medium ( 1 ), high ( 2 ) }
		MAX-ACCESS		read-only
		STATUS			current
		DESCRIPTION		"This parameter gives the current status of the alert"
		::=  {  bindingVariables  13  }

	recordedTime	OBJECT-TYPE
		SYNTAX			DisplayString
		MAX-ACCESS		read-only
		STATUS			current
		DESCRIPTION		"This parameter gives the time when the event was recorded"
		::=  {  bindingVariables  14  }

	downObjects		OBJECT-TYPE
		SYNTAX			DisplayString
		MAX-ACCESS		read-only
		STATUS			current
		DESCRIPTION		"This parameter lists the servers/agents that are in a down state"
		::=  {  bindingVariables  15  }

	detailedInformation		OBJECT-TYPE
		SYNTAX			DisplayString
		MAX-ACCESS		read-only
		STATUS			current
		DESCRIPTION		"This parameter displays the detailed information of the alert"
		::=  {  bindingVariables  16  }';

	/* Agent Alerts */
	mib_text = mib_text || pem.create_mib_notification_type(100, 5446);
	/* server Alerts */
	mib_text = mib_text || pem.create_mib_notification_type(200, 5447);
	/* database Alerts */
	mib_text = mib_text || pem.create_mib_notification_type(300, 5448);
	/* schema Alerts */
	mib_text = mib_text || pem.create_mib_notification_type(400, 5449);
	/* object Alerts */
	mib_text = mib_text || pem.create_mib_notification_type(500, 5450);
	mib_text = mib_text || pem.create_mib_notification_type(600, 5451);
	mib_text = mib_text || pem.create_mib_notification_type(700, 5452);
	mib_text = mib_text || pem.create_mib_notification_type(800, 5453);
	/* global Alerts */
	mib_text = mib_text || pem.create_mib_notification_type(50, 5454);

	mib_text = mib_text || E'\nEND';

	RETURN mib_text;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION pem.create_mib_notification_type(object_type integer, group_oid_type integer)
RETURNS text AS $$
DECLARE
	return_text text = '';
	tmp_rec	RECORD;
	parent_node text;
	where_clause text;
	object_prefix text;
	object_string text;
	group_text text = '';
	group_description text = '';
	is_alert_found boolean = false;
BEGIN
	CASE
	WHEN object_type = 50 THEN
		where_clause = 'WHERE object_type = 50 AND snmp_oid > 0';
		parent_node = 'globalAlerts';
		object_string = '{ alertName, thresholdValue, previousValue, value, previousStatus, status, recordedTime, downObjects, detailedInformation }';
		object_prefix = 'gl';
		group_text = E'\n\n\tpemGlobalNotificationGroup  NOTIFICATION-GROUP
	\tNOTIFICATIONS {';
		group_description = 'This group contains the global notification types';
	WHEN object_type = 100 THEN
		where_clause = 'WHERE object_type = 100 AND snmp_oid > 0';
		parent_node = 'agentAlerts';
		object_string = '{ alertName, agentID , agentName, thresholdValue, previousValue, value, previousStatus, status, recordedTime, detailedInformation }';
		object_prefix = 'ag';
		group_text = E'\n\n\tpemAgentNotificationGroup  NOTIFICATION-GROUP
	\tNOTIFICATIONS {';
		group_description = 'This group contains the agent level notification types';
	WHEN object_type = 200 THEN
		where_clause = 'WHERE object_type = 200 AND snmp_oid > 0';
		parent_node = 'serverAlerts';
		object_string = '{ alertName, serverID , serverName, thresholdValue, previousValue, value, previousStatus, status, recordedTime, detailedInformation }';
		object_prefix = 'sr';
		group_text = E'\n\n\tpemServerNotificationGroup  NOTIFICATION-GROUP
	\tNOTIFICATIONS {';
		group_description = 'This group contains the server level notification types';
	WHEN object_type = 300 THEN
		where_clause = 'WHERE object_type = 300 AND snmp_oid > 0';
		parent_node = 'databaseAlerts';
		object_string = '{ alertName, serverID , serverName, databaseName, thresholdValue, previousValue, value, previousStatus, status, recordedTime, detailedInformation }';
		object_prefix = 'db';
		group_text = E'\n\n\tpemDatabaseNotificationGroup  NOTIFICATION-GROUP
	\tNOTIFICATIONS {';
		group_description = 'This group contains the database level notification types';
	WHEN object_type = 400 THEN
		where_clause = 'WHERE object_type = 400 AND snmp_oid > 0';
		parent_node = 'schemaAlerts';
		object_string = '{ alertName, serverID , serverName, databaseName, schemaName, thresholdValue, previousValue, value, previousStatus, status, recordedTime, detailedInformation }';
		object_prefix = 'sc';
		group_text = E'\n\n\tpemSchemaNotificationGroup  NOTIFICATION-GROUP
	\tNOTIFICATIONS {';
		group_description = 'This group contains the schema level notification types';
	WHEN object_type = 500 THEN
		where_clause = 'WHERE object_type = 500 AND snmp_oid > 0';
		parent_node = 'objectAlerts';
		object_string = '{ alertName, serverID , serverName, databaseName, schemaName, objectName, thresholdValue, previousValue, value, previousStatus, status, recordedTime, detailedInformation }';
		object_prefix = 'tb';
		group_text = E'\n\n\tpemTableNotificationGroup  NOTIFICATION-GROUP
	\tNOTIFICATIONS {';
		group_description = 'This group contains the table level notification types';
	WHEN object_type = 600 THEN
		where_clause = 'WHERE object_type = 600 AND snmp_oid > 0';
		parent_node = 'objectAlerts';
		object_string = '{ alertName, serverID , serverName, databaseName, schemaName, objectName, thresholdValue, previousValue, value, previousStatus, status, recordedTime, detailedInformation }';
		object_prefix = 'in';
		group_text = E'\n\n\tpemIndexNotificationGroup  NOTIFICATION-GROUP
	\tNOTIFICATIONS {';
		group_description = 'This group contains the index level notification types';
	WHEN object_type = 700 THEN
		where_clause = 'WHERE object_type = 700 AND snmp_oid > 0';
		parent_node = 'objectAlerts';
		object_string = '{ alertName, serverID , serverName, databaseName, schemaName, objectName, thresholdValue, previousValue, value, previousStatus, status, recordedTime, detailedInformation }';
		object_prefix = 'se';
		group_text = E'\n\n\tpemSequenceNotificationGroup  NOTIFICATION-GROUP
	\tNOTIFICATIONS {';
		group_description = 'This group contains the sequence level notification types';
	WHEN object_type = 800 THEN
		where_clause = 'WHERE object_type = 800 AND snmp_oid > 0';
		parent_node = 'objectAlerts';
		object_string = '{ alertName, serverID , serverName, databaseName, schemaName, objectName, thresholdValue, previousValue, value, previousStatus, status, recordedTime, detailedInformation }';
		object_prefix = 'fn';
		group_text = E'\n\n\tpemFunctionNotificationGroup  NOTIFICATION-GROUP
	\tNOTIFICATIONS {';
		group_description = 'This group contains the function level notification types';
	END CASE;

	FOR tmp_rec IN EXECUTE 'SELECT display_name, description , snmp_oid FROM pem.alert_template ' || where_clause || ' ORDER BY snmp_oid'
	LOOP
		is_alert_found = true;
		tmp_rec.display_name = lower(tmp_rec.display_name);
		tmp_rec.display_name = replace(tmp_rec.display_name, '(', '');
		tmp_rec.display_name = replace(tmp_rec.display_name, ')', '');
		tmp_rec.display_name = replace(tmp_rec.display_name, ',', '');
		tmp_rec.display_name = replace(tmp_rec.display_name, '-', '');
		tmp_rec.display_name = replace(tmp_rec.display_name, '_', '');
		tmp_rec.display_name = initcap(tmp_rec.display_name);
		tmp_rec.display_name = replace(tmp_rec.display_name, ' ', '');

		tmp_rec.description = replace(tmp_rec.description, '"', '');

		IF char_length(tmp_rec.display_name) > 62 THEN
			tmp_rec.display_name = substr(tmp_rec.display_name, 0, 62);
		END IF;

		return_text =  return_text || E'\n\n\t' || object_prefix || tmp_rec.display_name || E'   NOTIFICATION-TYPE
		OBJECTS			' || object_string || E'
		STATUS			current
		DESCRIPTION \t\t"'	||	tmp_rec.description || E'"
		::=  {  ' || parent_node || '  ' || tmp_rec.snmp_oid::text ||  '  }';

		group_text = group_text || E'\n\t\t\t' ||object_prefix || tmp_rec.display_name || E',';
	END LOOP;

	group_text = trim(trailing ',' from group_text);

	group_text = group_text || '}
	STATUS 	current
	DESCRIPTION
		"'|| group_description ||'"
	::= { postgresql ' || group_oid_type || '}';

	IF is_alert_found THEN
		RETURN group_text || return_text;
	ELSE
		RETURN return_text;
	END IF;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION pem.get_mismatch_packages_list(agentid integer, OUT upgrade_packages_list text, OUT new_packages_list text, OUT obsolete_packages_list text) AS $$
DECLARE
	rec record;
	index integer:= 1;
BEGIN
	-- Get the list of packages that needs to be upgrade
	upgrade_packages_list = E'';
	FOR rec in (SELECT pc.name AS pkg_name, pc.version AS catalog_veriosn, ip.version AS installed_version
				FROM
					pemdata.package_catalog pc LEFT JOIN pemdata.installed_packages ip
					ON (pc.pkg_id = ip.pkg_id) AND (pc.platform = ip.platform)
				WHERE
					ip.agent_id = agentid AND
					pc.pkg_id = ip.pkg_id AND
					pc.platform = ip.platform AND
					pc.version != ip.version AND
					pc.manifesturl IS NOT NULL)
	LOOP
		upgrade_packages_list = upgrade_packages_list || index || ') ' || rec.pkg_name || ' (Installed Version: '
							|| rec.installed_version || ' Catalog Version: ' || rec.catalog_veriosn || E')\n';
		index = index + 1;
	END LOOP;

	index = 1;
	new_packages_list = E'';
	-- Get the list of packages which is not installed on the agent machine
	FOR rec in (SELECT distinct pc.pkg_id, pc.name AS pkg_name, pc.version AS version
				FROM
					pemdata.package_catalog pc
				WHERE NOT EXISTS(SELECT pkg_id
								FROM pemdata.installed_packages ip
								WHERE pc.pkg_id = ip.pkg_id) ORDER BY pc.pkg_id)
	LOOP
		new_packages_list = new_packages_list || index || ') ' || rec.pkg_name || ' (Version: '
							|| rec.version || E')\n';
		index = index + 1;
	END LOOP;

	index = 1;
	obsolete_packages_list = E'';
	-- Get the list of packages which is installed but obsolete from the catalog.
	FOR rec in (SELECT ip.pkg_id, ip.name AS pkg_name, ip.version AS version
				FROM
					pemdata.installed_packages ip
				WHERE NOT EXISTS
					(SELECT pc.pkg_id FROM pemdata.package_catalog pc
					WHERE ip.pkg_id = pc.pkg_id AND ip.platform = pc.platform)
				AND ip.agent_id = agentid
				ORDER BY ip.pkg_id)
	LOOP
		obsolete_packages_list = obsolete_packages_list || index || ') ' || rec.pkg_name || ' (Version: '
							|| rec.version || E')\n';
		index = index + 1;
	END LOOP;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION pemdata.server_info_postupdate() RETURNS trigger AS $$
BEGIN
	PERFORM pem.create_default_server_alerts(NEW.server_id, NEW.server_version_id);
	RETURN NULL;
END
$$ LANGUAGE plpgsql;

CREATE TRIGGER server_info_postupdate
	AFTER INSERT ON pemdata.server_info
	FOR EACH ROW EXECUTE PROCEDURE pemdata.server_info_postupdate();

GRANT USAGE ON SEQUENCE pem.alert_id_seq TO pem_agent;

COMMIT TRANSACTION;
