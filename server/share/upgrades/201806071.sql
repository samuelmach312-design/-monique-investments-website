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
'SELECT 201806071::integer;'
  LANGUAGE 'sql' IMMUTABLE;

CREATE OR REPLACE FUNCTION pem.check_alert_exist(alert_name text, alert_agent_id integer, alert_server_id integer,
					alert_database_name text, alert_schema_name text,
					alert_package_name text, alert_object_name text, alert_object_type integer)
RETURNS boolean AS $$
DECLARE
	is_already_exist boolean:= false;
BEGIN
	-- select alert already exist
	PERFORM id FROM pem.alert WHERE name = alert_name AND template_id = (SELECT id FROM pem.alert_template WHERE display_name = alert_name AND object_type = alert_object_type LIMIT 1)
	AND agent_id = alert_agent_id
	AND CASE WHEN alert_server_id IS NULL THEN (server_id IS NULL OR server_id = 0) ELSE server_id = alert_server_id END
	AND CASE WHEN alert_database_name IS NULL THEN (database_name IS NULL OR database_name = '') ELSE database_name = alert_database_name END
	AND CASE WHEN alert_schema_name IS NULL THEN (schema_name IS NULL OR schema_name = '') ELSE schema_name = alert_schema_name END
	AND CASE WHEN alert_package_name IS NULL THEN (package_name IS NULL OR package_name = '') ELSE package_name = alert_package_name END
	AND CASE WHEN alert_object_name IS NULL THEN (object_name IS NULL OR object_name = '') ELSE object_name = alert_object_name END;

	IF FOUND THEN
		is_already_exist := true;
	END IF;

	RETURN is_already_exist;
END;
$$ LANGUAGE plpgsql;

COMMIT TRANSACTION;
