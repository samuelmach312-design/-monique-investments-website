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

-- Upgrade script for 3.0.0b3 to 3.0.0rc1

BEGIN TRANSACTION;

CREATE OR REPLACE FUNCTION pem.schema_version()
  RETURNS integer AS
'SELECT 201210091::integer;'
  LANGUAGE 'sql' IMMUTABLE;

ALTER TABLE pem.log_configuration ALTER COLUMN log_syslog_facility DROP DEFAULT;
ALTER TABLE pem.log_configuration ALTER COLUMN log_syslog_ident DROP DEFAULT;
ALTER TABLE pem.log_configuration ALTER COLUMN log_syslog_facility DROP NOT NULL;
ALTER TABLE pem.log_configuration ALTER COLUMN log_syslog_ident DROP NOT NULL;

-- Fixed FB 22521
CREATE OR REPLACE FUNCTION pem.pe_engine(rule_id_array int[], server_database_pair_array text[][]) RETURNS SETOF RECORD
AS $$
DECLARE
	temp_server int;
	prev_server int:= 0;
	database text;
	evaluator_function text;
	function_query text;
	is_server_only boolean:= false;
	rule_name text; server_host text; expert_name text; database_name text; rule_description text; rule_trigger text; rule_recommended_value text; server_description text;
	server_port int:= 0;
	expert_id int:= 0;
	row  RECORD;

BEGIN
	CREATE TEMPORARY TABLE temp_expert_records(server_id int, rule_name text, server_host text, server_description text, server_port int, expert_name text, database_name text, description text, trigger text, recommended_value text, data_name text[], data_value text[], severity int);

	-- Loop through the rule ids
	FOR k IN array_lower(rule_id_array,1) .. array_upper(rule_id_array,1)
	LOOP

		-- Get rule name, description, trigger, recommended value
		SELECT name, description, trigger, recommended_value INTO rule_name,rule_description,rule_trigger,rule_recommended_value FROM pem.pe_rules_text WHERE rule_id = rule_id_array[k];

		-- Get the evaluator function and value of run_on_server_only for rule id
		SELECT expert, evaluator,run_on_server_only INTO expert_id, evaluator_function, is_server_only FROM pem.pe_rules where id = rule_id_array[k];

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
			SELECT server INTO server_host FROM pem.server WHERE id = temp_server;
			-- Get description and port for server
			SELECT description, port INTO server_description, server_port FROM pem.server WHERE id = temp_server;

			-- if value of is_server_only is true then we have to run this rule on server only
			IF (is_server_only) THEN
				IF (prev_server != temp_server) THEN
					function_query = E'SELECT ' || evaluator_function || '(' || temp_server ||',''' || rule_name ||''');';
					database_name = '-';

					INSERT INTO temp_expert_records(server_id, rule_name, server_host, server_description, server_port, expert_name, database_name, description, trigger, recommended_value, data_name, data_value, severity) VALUES (temp_server, rule_name, server_host, server_description, server_port, expert_name, database_name, rule_description, rule_trigger, rule_recommended_value, '{}', '{}', 0);

					EXECUTE function_query;
					prev_server = temp_server;
				END IF;
			ELSE
				-- run on databases;
				function_query = E'SELECT ' || evaluator_function || '(' || temp_server ||',''' || rule_name ||''',''' || database || ''');';
				database_name = database;

				INSERT INTO temp_expert_records(server_id, rule_name, server_host, server_description, server_port, expert_name, database_name, description, trigger, recommended_value, data_name, data_value, severity) VALUES (temp_server, rule_name, server_host, server_description, server_port, expert_name, database_name, rule_description, rule_trigger, rule_recommended_value, '{}', '{}', 0);

				EXECUTE function_query;
			END IF;

		END LOOP;
	END LOOP;

	FOR row IN SELECT * FROM temp_expert_records ORDER BY server_id, expert_name, rule_name LOOP
		RETURN NEXT row;
	END LOOP;

	RETURN;
END
$$ LANGUAGE plpgsql;

COMMIT TRANSACTION;
