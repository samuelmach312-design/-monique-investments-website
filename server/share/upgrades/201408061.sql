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
'SELECT 201408061::integer;'
  LANGUAGE 'sql' IMMUTABLE;

-- Fixed RM #33512
UPDATE pem.probe SET target_type_id = 300, applies_to_id = 300 WHERE internal_name = 'sql_protect';
DELETE FROM pem.probe_schedule WHERE probe_id = (SELECT id from pem.probe WHERE internal_name = 'sql_protect');
ALTER TABLE pemdata.sql_protect ADD COLUMN database_name text;
ALTER TABLE pemhistory.sql_protect ADD COLUMN database_name text;
UPDATE pemdata.sql_protect sp SET database_name = (SELECT database FROM pem.server WHERE id = sp.server_id);
UPDATE pemhistory.sql_protect sp SET database_name = (SELECT database FROM pem.server WHERE id = sp.server_id);
ALTER TABLE pemdata.sql_protect DROP CONSTRAINT sql_protect_pkey, ADD PRIMARY KEY(server_id, username, database_name);

CREATE OR REPLACE FUNCTION pemdata.copy_sql_protect_to_history()
RETURNS trigger AS
$$
BEGIN
	IF (TG_OP = 'INSERT' OR TG_OP = 'UPDATE') THEN
		INSERT INTO pemhistory.sql_protect (recorded_time, server_id, username, database_name, superusers, relations, commands, tautology, dml) VALUES (NEW.recorded_time, NEW.server_id, NEW.username, NEW.database_name, NEW.superusers, NEW.relations, NEW.commands, NEW.tautology, NEW.dml);
		ELSIF EXISTS(SELECT 1 FROM pem.server WHERE id = OLD.server_id) THEN
		INSERT INTO pemhistory.sql_protect (server_id, username, database_name) VALUES (OLD.server_id, OLD.username, OLD.database_name);
	END IF;
	RETURN NEW;
END;
$$
LANGUAGE plpgsql;

SELECT pem.create_alert_template(
        'Number of attacks detected in the last N minutes',
        'The number of SQL injection attacks occured in the last N minutes',
        $sql$
SELECT * FROM pem.sqlinjection_attacks_detected_on_database(${param_1},${server_id},'${database_name}')$sql$,
        300, '{Attacks Alert for last N minutes}', '{INTEGER}', '{Minutes}', NULL,'{sql_protect}', 62);

SELECT pem.create_alert_template(
        'Number of attacks detected in the last N minutes by username',
        'The number of SQL injection attacks occured in the last N minutes by username',
        $sql$
SELECT * FROM pem.sqlinjection_attacks_detected_by_username_on_database(${param_1},'${param_2}',${server_id},'${database_name}')$sql$,
        300, '{Attacks Alert for last N minutes, Username}', '{INTEGER,STRING}', '{Minutes}', NULL,'{sql_protect}', 63);

-- First argument takes last number of minutes user wants to get the data
-- Second argument takes the server id as integer
-- Third argument takes the database name

CREATE OR REPLACE FUNCTION pem.sqlinjection_attacks_detected_on_database(integer,integer,TEXT)
RETURNS integer AS $$

DECLARE
    total_count integer;
    user_requested_count integer;
    total_attacks_detected integer;
    tmp_count integer;
    tmp_days integer;
    attack_count_per_user integer;
    tmp_loop_count integer;
    total_users RECORD;
    last_row_fetched RECORD;
    first_row_fetched RECORD;
    tmp_flag boolean;

BEGIN
    total_count := 0;
    user_requested_count := 0;
    total_attacks_detected := 0;
    tmp_count := 0;
    tmp_days := 1;
    tmp_loop_count := 1;

    FOR total_users IN SELECT DISTINCT username FROM pemhistory.sql_protect WHERE server_id = $2 AND database_name = $3 LOOP

        -- Find the total number of rows for specific user in the table
        SELECT count(*) INTO total_count FROM pemhistory.sql_protect WHERE server_id = $2 AND database_name = $3 AND username = total_users.username;
        -- Find the rows for specific user for user requested last N minutes in the table
        SELECT count(*) INTO user_requested_count FROM pemhistory.sql_protect WHERE server_id = $2 AND database_name = $3 AND username = total_users.username AND recorded_time > now() - ($1)*'1 minutes'::interval;

        attack_count_per_user := 0;
        tmp_flag := false;

        -- If the difference is 1 then there are total two entry in the table and for first row we have directly get the value and count the number of attacks
       IF (total_count - user_requested_count) = 1 THEN

                -- Select the last value from the below query and search for previous until we get the difference
                SELECT superusers, relations, commands, tautology, dml INTO last_row_fetched FROM pemhistory.sql_protect WHERE server_id = $2 AND database_name = $3 AND username = total_users.username AND recorded_time > now() - ($1)*'1 minutes'::interval ORDER BY recorded_time DESC LIMIT 1;


                SELECT superusers, relations, commands, tautology, dml INTO first_row_fetched FROM pemhistory.sql_protect WHERE server_id = $2 AND database_name = $3 AND username = total_users.username ORDER BY recorded_time ASC LIMIT 1;

                attack_count_per_user := (last_row_fetched.superusers - first_row_fetched.superusers) + (last_row_fetched.relations - first_row_fetched.relations) + (last_row_fetched.commands - first_row_fetched.commands) + (last_row_fetched.tautology - first_row_fetched.tautology) + (last_row_fetched.dml - first_row_fetched.dml);

                tmp_flag := true;
	END IF;

	-- If total user count and user requested count for specific time is zero that means all the entry contains in the user requested time slot and no entry in the time slot before that so we have to take the decision based on the user requested count is one then dirctly add the attacks and for more then one take the difference between the rows.
	IF (total_count - user_requested_count) = 0 THEN
		IF user_requested_count = 1 THEN
			SELECT SUM(superusers + relations + commands + tautology + dml) INTO attack_count_per_user FROM pemhistory.sql_protect WHERE server_id = $2 AND database_name = $3 AND pemhistory.sql_protect.username = total_users.username AND recorded_time > now() - ($1)*'1 minutes'::interval;
			tmp_flag := true;

		ELSE
			WHILE (tmp_loop_count < user_requested_count) LOOP

				SELECT superusers, relations, commands, tautology, dml INTO last_row_fetched FROM pemhistory.sql_protect WHERE server_id = $2 AND database_name = $3 AND pemhistory.sql_protect.username = total_users.username AND recorded_time > now() - ($1)*'1 minutes'::interval ORDER BY recorded_time DESC LIMIT 1 OFFSET (tmp_loop_count - 1);

				tmp_loop_count := tmp_loop_count + 1;

				SELECT superusers, relations, commands, tautology, dml INTO first_row_fetched FROM pemhistory.sql_protect WHERE server_id = $2 AND database_name = $3 AND pemhistory.sql_protect.username = total_users.username AND recorded_time > now() - ($1)*'1 minutes'::interval ORDER BY recorded_time DESC LIMIT 1 OFFSET (tmp_loop_count - 1);

				attack_count_per_user := attack_count_per_user + (last_row_fetched.superusers - first_row_fetched.superusers) + (last_row_fetched.relations - first_row_fetched.relations) + (last_row_fetched.commands - first_row_fetched.commands) + (last_row_fetched.tautology - first_row_fetched.tautology) + (last_row_fetched.dml - first_row_fetched.dml);

			END LOOP;

			attack_count_per_user := attack_count_per_user + first_row_fetched.superusers + first_row_fetched.relations + first_row_fetched.commands + first_row_fetched.tautology + first_row_fetched.dml;

			tmp_flag := true;

		END IF;
	END IF;

	-- There are no entry in the table for that user so don't do anything
	IF (total_count - user_requested_count) = total_count THEN
		NULL;

        ELSE
                IF tmp_flag = false THEN

                -- Select the last row value from the below query
                SELECT superusers, relations, commands, tautology, dml INTO last_row_fetched FROM pemhistory.sql_protect WHERE server_id = $2 AND database_name = $3 AND pemhistory.sql_protect.username = total_users.username AND recorded_time > now() - ($1)*'1 minutes'::interval ORDER BY recorded_time DESC LIMIT 1;

                -- Loop until we get the previous entry for specific user to take the difference to calculate the number of SQL injection attacks
                LOOP
                    tmp_days := tmp_days + 1;
                    SELECT count(*) INTO tmp_count FROM pemhistory.sql_protect WHERE server_id = $2 AND database_name = $3 AND pemhistory.sql_protect.username = total_users.username AND recorded_time > now() - (tmp_days)*'1 days'::interval;

                    IF tmp_count > user_requested_count THEN
                        SELECT superusers, relations, commands, tautology, dml INTO first_row_fetched FROM pemhistory.sql_protect WHERE server_id = $2 AND database_name = $3 AND pemhistory.sql_protect.username = total_users.username AND recorded_time > now() - (tmp_days)*'1 days'::interval ORDER BY recorded_time DESC LIMIT 1 OFFSET user_requested_count;
                        EXIT;
                   ELSE
                        tmp_days := tmp_days + 1;
                    END IF;

                END LOOP;

                attack_count_per_user := (last_row_fetched.superusers - first_row_fetched.superusers) + (last_row_fetched.relations - first_row_fetched.relations) + (last_row_fetched.commands - first_row_fetched.commands) + (last_row_fetched.tautology - first_row_fetched.tautology) + (last_row_fetched.dml - first_row_fetched.dml);

                END IF;

        END IF;

        -- Calculate the total number of SQL injection attacks for each user
        total_attacks_detected := total_attacks_detected + attack_count_per_user;

    END LOOP;

    RETURN total_attacks_detected;

END;
$$ LANGUAGE plpgsql;


CREATE OR REPLACE FUNCTION pem.sqlinjection_attacks_detected_by_username_on_database(integer,TEXT,integer,TEXT)
RETURNS integer AS $$

DECLARE
    total_count integer;
    user_requested_count integer;
    tmp_count integer;
    tmp_days integer;
    attack_count_per_user integer;
    tmp_loop_count integer;
    last_row_fetched RECORD;
    first_row_fetched RECORD;
    tmp_flag boolean;

BEGIN
    total_count := 0;
    user_requested_count := 0;
    tmp_count := 0;
    tmp_days := 1;
    tmp_loop_count := 1;

    -- Find the total number of rows for specific user in the table
    SELECT count(*) INTO total_count FROM pemhistory.sql_protect WHERE server_id = $3 AND username = $2 AND database_name = $4;
    -- Find the rows for specific user for user requested last N minutes in the table
    SELECT count(*) INTO user_requested_count FROM pemhistory.sql_protect WHERE server_id = $3 AND username = $2 AND database_name = $4 AND recorded_time > now() - ($1)*'1 minutes'::interval;

    attack_count_per_user := 0;
    tmp_flag := false;

    -- If the difference is 1 then there are total two entry in the table and for first row we have directly get the value and count the number of attacks
    IF (total_count - user_requested_count) = 1 THEN

            -- Select the last value from the below query and search for previous until we get the difference
            SELECT superusers, relations, commands, tautology, dml INTO last_row_fetched FROM pemhistory.sql_protect WHERE server_id = $3 AND username = $2 AND database_name = $4 AND recorded_time > now() - ($1)*'1 minutes'::interval ORDER BY recorded_time DESC LIMIT 1;


            SELECT superusers, relations, commands, tautology, dml INTO first_row_fetched FROM pemhistory.sql_protect WHERE server_id = $3 AND username = $2 AND database_name = $4 ORDER BY recorded_time ASC LIMIT 1;

            attack_count_per_user := (last_row_fetched.superusers - first_row_fetched.superusers) + (last_row_fetched.relations - first_row_fetched.relations) + (last_row_fetched.commands - first_row_fetched.commands) + (last_row_fetched.tautology - first_row_fetched.tautology) + (last_row_fetched.dml - first_row_fetched.dml);

            tmp_flag := true;
    END IF;

    -- If total user count and user requested count for specific time is zero that means all the entry contains in the user requested time slot and no entry in the time slot before that so we have to take the decision based on the user requested count is one then dirctly add the attacks and for more then one take the difference between the rows.
    IF (total_count - user_requested_count) = 0 THEN
	IF user_requested_count = 1 THEN
		SELECT SUM(superusers + relations + commands + tautology + dml) INTO attack_count_per_user FROM pemhistory.sql_protect WHERE server_id = $3 AND database_name = $4 AND pemhistory.sql_protect.username = $2 AND recorded_time > now() - ($1)*'1 minutes'::interval;
		tmp_flag := true;

	ELSE
		WHILE (tmp_loop_count < user_requested_count) LOOP

			SELECT superusers, relations, commands, tautology, dml INTO last_row_fetched FROM pemhistory.sql_protect WHERE server_id = $3 AND database_name = $4 AND pemhistory.sql_protect.username = $2 AND recorded_time > now() - ($1)*'1 minutes'::interval ORDER BY recorded_time DESC LIMIT 1 OFFSET (tmp_loop_count - 1);

			tmp_loop_count := tmp_loop_count + 1;

			SELECT superusers, relations, commands, tautology, dml INTO first_row_fetched FROM pemhistory.sql_protect WHERE server_id = $3 AND database_name = $4 AND pemhistory.sql_protect.username = $2 AND recorded_time > now() - ($1)*'1 minutes'::interval ORDER BY recorded_time DESC LIMIT 1 OFFSET (tmp_loop_count - 1);

			attack_count_per_user := attack_count_per_user + (last_row_fetched.superusers - first_row_fetched.superusers) + (last_row_fetched.relations - first_row_fetched.relations) + (last_row_fetched.commands - first_row_fetched.commands) + (last_row_fetched.tautology - first_row_fetched.tautology) + (last_row_fetched.dml - first_row_fetched.dml);

		END LOOP;

		attack_count_per_user := attack_count_per_user + first_row_fetched.superusers + first_row_fetched.relations + first_row_fetched.commands + first_row_fetched.tautology + first_row_fetched.dml;

		tmp_flag := true;

	END IF;
    END IF;

    -- There are no entry in the table for that user so don't do anything
    IF (total_count - user_requested_count) = total_count THEN
	NULL;

    ELSE
		IF tmp_flag = false THEN

		-- Select the last row value from the below query
		SELECT superusers, relations, commands, tautology, dml INTO last_row_fetched FROM pemhistory.sql_protect WHERE server_id = $3 AND database_name = $4 AND pemhistory.sql_protect.username = $2 AND recorded_time > now() - ($1)*'1 minutes'::interval ORDER BY recorded_time DESC LIMIT 1;

		-- Loop until we get the previous entry for specific user to take the difference to calculate the number of SQL injection attacks
		LOOP
			tmp_days := tmp_days + 1;
			SELECT count(*) INTO tmp_count FROM pemhistory.sql_protect WHERE server_id = $3 AND database_name = $4 AND pemhistory.sql_protect.username = $2 AND recorded_time > now() - (tmp_days)*'1 days'::interval;

			IF tmp_count > user_requested_count THEN
				SELECT superusers, relations, commands, tautology, dml INTO first_row_fetched FROM pemhistory.sql_protect WHERE server_id = $3 AND database_name = $4 AND pemhistory.sql_protect.username = $2 AND recorded_time > now() - (tmp_days)*'1 days'::interval ORDER BY recorded_time DESC LIMIT 1 OFFSET user_requested_count;
				EXIT;
			ELSE
				tmp_days := tmp_days + 1;
			END IF;

		END LOOP;

		attack_count_per_user := (last_row_fetched.superusers - first_row_fetched.superusers) + (last_row_fetched.relations - first_row_fetched.relations) + (last_row_fetched.commands - first_row_fetched.commands) + (last_row_fetched.tautology - first_row_fetched.tautology) + (last_row_fetched.dml - first_row_fetched.dml);

		END IF;

    END IF;

    RETURN attack_count_per_user;

END;
$$ LANGUAGE plpgsql;

-- Fixed RM #33569
CREATE OR REPLACE FUNCTION pem.server_tuning_original_value(tuned_server_id int, param_name text)
RETURNS TEXT
AS $$
DECLARE
	param_value text := '';
	orig_val decimal := 0;
	param_unit int := 1;
	unit_val text := '';
BEGIN
	SELECT setting::decimal, unit, COALESCE(SUBSTRING(unit from '[0-9]+'), '1')::int FROM pemdata.settings WHERE server_id = tuned_server_id AND name = param_name INTO orig_val, unit_val, param_unit;

	IF (unit_val IS NOT NULL) AND (unit_val != '') THEN
		orig_val = orig_val * param_unit;
		IF orig_val < 1024 THEN
			param_value = orig_val::text || 'kB';
		ELSE
			param_value = round(orig_val/1024)::text || 'MB';
		END IF;
	ELSE
		param_value = orig_val::text;
	END IF;

	RETURN param_value;
END
$$ LANGUAGE plpgsql;

COMMIT TRANSACTION;