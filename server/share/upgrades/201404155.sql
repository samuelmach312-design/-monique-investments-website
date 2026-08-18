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

-- Update the schema version
CREATE OR REPLACE FUNCTION pem.schema_version()
  RETURNS integer AS
'SELECT 201404155::integer;'
  LANGUAGE 'sql' IMMUTABLE;
COMMENT ON FUNCTION pem.schema_version() IS 'Returns the version number of the PEM schema';

--
-- Probe: auto_discover_servers
--
INSERT INTO pem.probe
	(display_name, internal_name, collection_method, target_type_id,
	 agent_capability, enabled_by_default, force_enabled,
     default_execution_frequency, default_lifetime, any_server_version, probe_code, discard_history)
VALUES
	('Server Auto Discovery', 'auto_discover_servers', 'i', 100, 'auto_discover_servers', true, false, 86400,
	  180, true, 'auto_discover_servers', true);

INSERT INTO pem.probe_column
	(probe_id, internal_name, display_name, display_position, classification,
	sql_data_type, unit_of_value, calculate_pit, discard_history, pit_by_default, is_graphable)
SELECT
	(SELECT max(id) FROM pem.probe),
	v.internal_name, v.display_name, v.display_position, v.classification,
	v.sql_data_type, v.unit_of_value, v.calculate_pit, v.discard_history, v.pit_by_default, v.is_graphable
FROM
	(VALUES
		('port', 'Server Port', 1, 'k', 'integer', '', false, false, false, false),
		('description', 'Server Description', 2, 'm', 'text', '', false, false, false, false),
		('serviceid', 'Server Serviceid', 3, 'm', 'text', '', false, false, false, false),
		('superuser', 'Super User', 4, 'm', 'text', '', false, false, false, false),
		('version', 'Server Version', 5, 'm', 'text', '', false, false, false, false)
	) v(internal_name, display_name, display_position, classification,
		sql_data_type, unit_of_value, calculate_pit, discard_history, pit_by_default, is_graphable);

SELECT pem.create_data_and_history_tables();

-- Done!
COMMIT TRANSACTION;

