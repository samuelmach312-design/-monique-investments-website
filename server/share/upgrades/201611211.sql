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
'SELECT 201611211::integer;'
  LANGUAGE 'sql' IMMUTABLE;
COMMENT ON FUNCTION pem.schema_version() IS 'Returns the version number of the PEM schema';

-- Fixed "Removed database name from table selection clause in query"
CREATE OR REPLACE FUNCTION pem.pe_rule_missing_primary_keys(serverID int, rulename text, databasename text) RETURNS BOOLEAN
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
	SELECT sv.id < 20000 into is_postgres FROM pem.server_version sv WHERE sv.id = (SELECT si.server_version_id FROM pemdata.server_info si WHERE si.server_id = serverID);

	SELECT count(schema_name) INTO schema_count FROM pemdata.oc_schema WHERE database_name = databasename AND server_id = serverID AND schema_name IN ('pem', 'pemdata' , 'pemhistory');

	IF (is_postgres) THEN
		IF (schema_count = 3) THEN
			query := E'SELECT schema_name, table_name FROM pemdata.oc_table WHERE database_name = ''' || databasename || ''' AND server_id = ''' || serverID || ''' AND has_primary_key = false AND schema_name not in (''pem'', ''pemdata'', ''pemhistory'', ''information_schema'', ''pg_catalog'', ''pg_log'', ''pg_temp'');';
		ELSE
			query := E'SELECT schema_name, table_name FROM pemdata.oc_table WHERE database_name = ''' || databasename || ''' AND server_id = ''' || serverID || ''' AND has_primary_key = false AND schema_name not in (''information_schema'', ''pg_catalog'', ''pg_log'', ''pg_temp'');';
		END IF;
	ELSE
		IF (schema_count = 3) THEN
			query := E'SELECT schema_name, table_name FROM pemdata.oc_table WHERE database_name = ''' || databasename || ''' AND server_id = ''' || serverID || ''' AND has_primary_key = false AND schema_name not in (''pem'', ''pemdata'', ''pemhistory'', ''information_schema'', ''pg_catalog'', ''pg_log'', ''pg_temp'', ''sys'', ''dbo'');';
		ELSE
			query := E'SELECT schema_name, table_name FROM pemdata.oc_table WHERE database_name = ''' || databasename || ''' AND server_id = ''' || serverID || ''' AND has_primary_key = false AND schema_name not in (''information_schema'', ''pg_catalog'', ''pg_log'', ''pg_temp'', ''sys'', ''dbo'');';
		END IF;
	END IF;

	FOR row IN EXECUTE query
	LOOP
		data_name_arr[index]   	:= 'table';
		data_value_arr[index]  	:= quote_literal(row.schema_name) || '.' || quote_literal(row.table_name);

		resultcount:= resultcount + 1;
		index:= index + 1;
	END LOOP;

	IF (resultcount > 0 ) THEN
		severity_val := 1;

		-- Update the values of data_name , data_value and severity
		UPDATE temp_expert_records SET data_name = data_name_arr, data_value = data_value_arr, severity = severity_val WHERE rule_name = rulename AND server_id = serverID  AND database_name = databasename;
	ELSE
		DELETE FROM temp_expert_records WHERE rule_name = rulename AND server_id = serverID  AND database_name = databasename;
	END IF;

	RETURN TRUE;
END
$$ LANGUAGE plpgsql;

-- Fixed "Removed database name from table selection clause in query"
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
	SELECT sv.id < 20000 into is_postgres FROM pem.server_version sv WHERE sv.id = (SELECT si.server_version_id FROM pemdata.server_info si WHERE si.server_id = serverID);

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
			data_name_arr[index]   	:= 'table';
			data_value_arr[index]  	:= quote_literal(row.schema_name) || '.' || quote_literal(row.table_name);
			index:= index + 1;
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

CREATE OR REPLACE FUNCTION pem.pe_rule_missing_foreign_key_indexes(serverID int, rulename text, databasename text) RETURNS BOOLEAN
AS $$
DECLARE
	is_postgres boolean;
	query text;
	subquery text;
	severity_val int:= 0;
	data_name_arr text[];
	data_value_arr text[];
	row RECORD; subquery_row RECORD;
	resultcount int:= 0;
	index int:= 0;
	is_key_indexed boolean;
	schema_count int:= 0;

BEGIN
	SELECT sv.id < 20000 into is_postgres FROM pem.server_version sv WHERE sv.id = (SELECT si.server_version_id FROM pemdata.server_info si WHERE si.server_id = serverID);

	SELECT count(schema_name) INTO schema_count FROM pemdata.oc_schema WHERE database_name = databasename AND server_id = serverID AND schema_name IN ('pem', 'pemdata' , 'pemhistory');

	IF (is_postgres) THEN
		IF (schema_count = 3) THEN
			query = E'SELECT conkey, fktab, schema_name FROM pemdata.oc_foreign_key WHERE database_name = ''' || databasename || ''' AND server_id = ''' || serverID || ''' AND schema_name not in (''pem'', ''pemdata'', ''pemhistory'', ''information_schema'', ''pg_catalog'', ''pg_log'', ''pg_temp'');';
		ELSE
			query = E'SELECT conkey, fktab, schema_name FROM pemdata.oc_foreign_key WHERE database_name = ''' || databasename || ''' AND server_id = ''' || serverID || ''' AND schema_name not in (''information_schema'', ''pg_catalog'', ''pg_log'', ''pg_temp'');';
		END IF;
	ELSE
		IF (schema_count = 3) THEN
			query = E'SELECT conkey, fktab, schema_name FROM pemdata.oc_foreign_key WHERE database_name = ''' || databasename || ''' AND server_id = ''' || serverID || ''' AND schema_name not in (''pem'', ''pemdata'', ''pemhistory'', ''information_schema'', ''pg_catalog'', ''pg_log'', ''pg_temp'', ''sys'', ''dbo'');';
		ELSE
			query = E'SELECT conkey, fktab, schema_name FROM pemdata.oc_foreign_key WHERE database_name = ''' || databasename || ''' AND server_id = ''' || serverID || ''' AND schema_name not in (''information_schema'', ''pg_catalog'', ''pg_log'', ''pg_temp'', ''sys'', ''dbo'');';
		END IF;

	END IF;

	FOR row IN EXECUTE query
	LOOP
		subquery = E'SELECT string_to_array(ind_keys::text, '' '')::smallint[] AS index_keys FROM pemdata.oc_index WHERE table_name = ' || pg_catalog.quote_literal(row.fktab) || ' AND schema_name = ' || pg_catalog.quote_literal(row.schema_name) || ';';
		is_key_indexed := false;

		FOR subquery_row IN EXECUTE subquery
		LOOP
			IF (row.conkey = subquery_row.index_keys) THEN
				is_key_indexed = true;
			END IF;
		END LOOP;

		IF (is_key_indexed != true) THEN
			data_name_arr[index]   	:= 'table';
			data_value_arr[index]  	:= quote_literal(row.schema_name) || '.' || quote_literal(row.fktab);

			severity_val := 5;
			index:= index + 1;
			resultcount:= resultcount + 1;
		END IF;

	END LOOP;

	IF (resultcount > 0 ) THEN
		-- Update the values of data_name , data_value and severity
		UPDATE temp_expert_records SET data_name = data_name_arr, data_value = data_value_arr, severity = severity_val WHERE rule_name = rulename AND server_id = serverID  AND database_name = databasename;
	ELSE
		DELETE FROM temp_expert_records WHERE rule_name = rulename AND server_id = serverID  AND database_name = databasename;
	END IF;

	RETURN TRUE;
END
$$ LANGUAGE plpgsql;

COMMIT TRANSACTION;
