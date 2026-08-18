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

-- Upgrade script for v2.1.0b2 to v2.1.0b3

BEGIN TRANSACTION;

CREATE OR REPLACE FUNCTION pem.schema_version()
  RETURNS integer AS
'SELECT 201203201::integer;'
  LANGUAGE 'sql' IMMUTABLE;

UPDATE pem.pe_rules_text SET trigger = 'table has more than or equal to 8 indexes' WHERE name = 'Check for too many indexes';

CREATE OR REPLACE FUNCTION pem.pe_rule_check_too_many_indexes(serverID int, rulename text, databasename text) RETURNS BOOLEAN
AS $$
DECLARE
	is_postgres boolean;
	query text;
	severity_val int:= 0;
	data_name_arr text[];
	data_value_arr text[];
	row RECORD;
	resultcount int:= 0;
	index int:= 0;
	schema_count int:= 0;

BEGIN
	SELECT sv.id < 20000 into is_postgres FROM pem.server_version sv WHERE sv.id = (SELECT si.server_version_id FROM pem.pemdata.server_info si WHERE si.server_id = serverID);

	SELECT count(schema_name) INTO schema_count FROM pemdata.oc_schema WHERE database_name = databasename AND server_id = serverID AND schema_name IN ('pem', 'pemdata' , 'pemhistory');

	IF (is_postgres) THEN
		IF (schema_count = 3) THEN
			query = E'SELECT CASE WHEN COUNT(*) >= 8 AND COUNT(*) < 10 THEN 1 WHEN COUNT(*) >= 10 AND COUNT(*) < 20 THEN 5 WHEN COUNT(*) >= 20 THEN 9 ELSE 0 END AS severity, schema_name, table_name FROM pemdata.oc_index WHERE database_name = ''' || databasename || ''' AND server_id = ''' || serverID || ''' AND schema_name not in (''pem'', ''pemdata'', ''pemhistory'', ''information_schema'', ''pg_catalog'', ''pg_log'', ''pg_temp'') GROUP BY database_name, schema_name, table_name;';
		ELSE
			query = E'SELECT CASE WHEN COUNT(*) >= 8 AND COUNT(*) < 10 THEN 1 WHEN COUNT(*) >= 10 AND COUNT(*) < 20 THEN 5 WHEN COUNT(*) >= 20 THEN 9 ELSE 0 END AS severity, schema_name, table_name FROM pemdata.oc_index WHERE database_name = ''' || databasename || ''' AND server_id = ''' || serverID || ''' AND schema_name not in (''information_schema'', ''pg_catalog'', ''pg_log'', ''pg_temp'') GROUP BY database_name, schema_name, table_name;';
		END IF;
	ELSE
		IF (schema_count = 3) THEN
			query = E'SELECT CASE WHEN COUNT(*) >= 8 AND COUNT(*) < 10 THEN 1 WHEN COUNT(*) >= 10 AND COUNT(*) < 20 THEN 5 WHEN COUNT(*) >= 20 THEN 9 ELSE 0 END AS severity, schema_name, table_name FROM pemdata.oc_index WHERE database_name = ''' || databasename || ''' AND server_id = ''' || serverID || ''' AND schema_name not in (''pem'', ''pemdata'', ''pemhistory'', ''information_schema'', ''pg_catalog'', ''pg_log'', ''pg_temp'', ''sys'', ''dbo'') GROUP BY database_name, schema_name, table_name;';
		ELSE
			query = E'SELECT CASE WHEN COUNT(*) >= 8 AND COUNT(*) < 10 THEN 1 WHEN COUNT(*) >= 10 AND COUNT(*) < 20 THEN 5 WHEN COUNT(*) >= 20 THEN 9 ELSE 0 END AS severity, schema_name, table_name FROM pemdata.oc_index WHERE database_name = ''' || databasename || ''' AND server_id = ''' || serverID || ''' AND schema_name not in (''information_schema'', ''pg_catalog'', ''pg_log'', ''pg_temp'', ''sys'', ''dbo'') GROUP BY database_name, schema_name, table_name;';
		END IF;
	END IF;

	FOR row IN EXECUTE query
	LOOP
		IF (row.severity > 0) THEN
			data_name_arr[index]   	:= 'schema_name';
			data_name_arr[index+1] 	:= 'table_name';

			data_value_arr[index]  	:=  row.schema_name;
			data_value_arr[index+1] :=  row.table_name;
			index:= index + 2;
		END IF;

		resultcount:= resultcount + 1;

		IF (row.severity > severity_val) THEN
			severity_val := row.severity;
		END IF;
	END LOOP;

	IF (resultcount > 0 ) AND (severity_val > 0) THEN
		-- Update the values of data_name , data_value and severity
		UPDATE temp_expert_records SET data_name = data_name_arr, data_value = data_value_arr, severity = severity_val WHERE rule_name = rulename AND server_id = serverID  AND database_name = databasename;
	ELSE
		DELETE FROM temp_expert_records WHERE rule_name = rulename AND server_id = serverID  AND database_name = databasename;
	END IF;

	RETURN TRUE;
END
$$ LANGUAGE plpgsql;

/* Fixed FB 20789: audit config mismatch alert */
UPDATE pem.alert_template SET sql = 'SELECT
  CASE
    WHEN COUNT(r.result) <> 0 THEN MAX(r.result)
    ELSE -1
  END
  FROM
  (SELECT
     CASE
       WHEN(p.edb_audit = pd.edb_audit
         AND p.edb_audit_directory = pd.edb_audit_directory
         AND p.edb_audit_filename = pd.edb_audit_filename
         AND p.edb_audit_rotation_day = pd.edb_audit_rotation_day
         AND p.edb_audit_rotation_sec = pd.edb_audit_rotation_sec
         AND p.edb_audit_rotation_size = pd.edb_audit_rotation_size
         AND p.edb_audit_connect = pd.edb_audit_connect
         AND p.edb_audit_disconnect = pd.edb_audit_disconnect
         AND p.edb_audit_statements = pd.edb_audit_statements) OR (p.server_id IS NULL)
         THEN -1
       ELSE 1
     END AS result
   FROM
     pem.audit_configuration p RIGHT JOIN
     pemdata.audit_configuration pd ON (p.server_id = pd.server_id)
   WHERE p.server_id = ${server_id}) AS r'
 WHERE display_name = 'Audit config mismatch';

COMMIT TRANSACTION;
