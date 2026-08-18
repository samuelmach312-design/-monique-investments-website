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
'SELECT 201512101::integer;'
  LANGUAGE 'sql' IMMUTABLE;

CREATE OR REPLACE FUNCTION pem.int2vector2array(int2vector) RETURNS smallint[] AS $$
BEGIN
    RETURN string_to_array($1::text, ' ')::smallint[];
END;
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
	SELECT sv.id < 20000 into is_postgres FROM pem.server_version sv WHERE sv.id = (SELECT si.server_version_id FROM pem.pemdata.server_info si WHERE si.server_id = serverID);

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
