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
'SELECT 201607281::integer;'
  LANGUAGE 'sql' IMMUTABLE;
COMMENT ON FUNCTION pem.schema_version() IS 'Returns the version number of the PEM schema';

CREATE OR REPLACE FUNCTION pem.pe_engine(
    rule_id_array integer[],
    server_database_pair_array text[])
  RETURNS SETOF record AS
$BODY$
DECLARE
	temp_server int;
	prev_server int:= 0;
	database text;
	evaluator_function text;
	function_query text;
	is_server_only boolean:= false;
	is_run_on_remote_server boolean:= true;
	remote_monitoring boolean:= false;
	execute_rule boolean:= true;
	rule_name text; server_host text; expert_name text; database_name text; rule_description text; rule_trigger text; rule_recommended_value text; server_description text;
	server_port int:= 0;
	rule_id int := 0;
	expert_id int:= 0;
	row  RECORD;

BEGIN
	CREATE TEMPORARY TABLE temp_expert_records(server_id int, rule_id int, rule_name text, server_host text, server_description text, server_port int, expert_name text, database_name text, description text, trigger text, recommended_value text, data_name text[], data_value text[], severity int);
	-- Loop through the rule ids
	FOR k IN array_lower(rule_id_array,1) .. array_upper(rule_id_array,1)
	LOOP
		-- Get rule name, description, trigger, recommended value
		SELECT name, description, trigger, recommended_value INTO rule_name,rule_description,rule_trigger,rule_recommended_value FROM pem.pe_rules_text pe_text WHERE pe_text.rule_id = rule_id_array[k];

		-- Get the evaluator function and value of "run_on_server_only" and "run_on_remote_server" for rule id
		SELECT expert, evaluator, run_on_server_only, run_on_remote_server INTO expert_id, evaluator_function, is_server_only, is_run_on_remote_server FROM pem.pe_rules where id = rule_id_array[k];

		-- Get expert name
		SELECT name INTO expert_name FROM pem.pe_experts WHERE id = expert_id;

		-- Reset value of prev server for next rule
		prev_server = 0;

		-- Loop through the no of servers
		FOR i in array_lower(server_database_pair_array,1) .. array_upper(server_database_pair_array,1)
		LOOP

			-- Assumptions: We will always have two dimentions:
			--    First represents server
			--    Second represents database

			temp_server := server_database_pair_array[i][1];
			database := server_database_pair_array[i][2];

			-- Get server name
			SELECT server, is_remote_monitoring INTO server_host, remote_monitoring FROM pem.server WHERE id = temp_server;
			-- Get description and port for server
			SELECT description, port INTO server_description, server_port FROM pem.server WHERE id = temp_server;

			-- In case of remotely monitored server, we will check the value of "run_on_remote_server"
			-- if it is true then only we execute the rule else skip it.
			execute_rule = true;
			IF (remote_monitoring) THEN
				IF (is_run_on_remote_server) THEN
					execute_rule = true;
				ELSE
					execute_rule = false;
				END IF;
			END IF;

			IF  (execute_rule) THEN
				-- if value of is_server_only is true then we have to run this rule on server only
				IF (is_server_only) THEN
					IF (prev_server != temp_server) THEN
						function_query = E'SELECT ' || evaluator_function || '(' || temp_server ||',''' || rule_name ||''');';
						database_name = '-';

						INSERT INTO temp_expert_records(server_id, rule_id, rule_name, server_host, server_description, server_port, expert_name, database_name, description, trigger, recommended_value, data_name, data_value, severity) VALUES (temp_server, rule_id_array[k], rule_name, server_host, server_description, server_port, expert_name, database_name, rule_description, rule_trigger, rule_recommended_value, '{}', '{}', 0);

						EXECUTE function_query;
						prev_server = temp_server;
					END IF;
				ELSE
					-- run on databases;
					function_query = E'SELECT ' || evaluator_function || '(' || temp_server ||',''' || rule_name ||''',''' || database || ''');';
					database_name = database;

					INSERT INTO temp_expert_records(server_id, rule_id, rule_name, server_host, server_description, server_port, expert_name, database_name, description, trigger, recommended_value, data_name, data_value, severity) VALUES (temp_server, rule_id_array[k], rule_name, server_host, server_description, server_port, expert_name, database_name, rule_description, rule_trigger, rule_recommended_value, '{}', '{}', 0);

					EXECUTE function_query;
				END IF;
			END IF;
		END LOOP;
	END LOOP;

	FOR row IN SELECT * FROM temp_expert_records ORDER BY server_id, expert_name, rule_name LOOP
		RETURN NEXT row;
	END LOOP;

	DROP TABLE temp_expert_records;

	RETURN;
END
$BODY$
LANGUAGE plpgsql VOLATILE;

COMMIT TRANSACTION;

