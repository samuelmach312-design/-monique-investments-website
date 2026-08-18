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
'SELECT 201406091::integer;'
  LANGUAGE 'sql' IMMUTABLE;

UPDATE pem.probe_column SET is_graphable = true WHERE internal_name IN ('memory_usage_mb', 'swap_usage_mb', 'cpu_usage', 'io_read_bytes', 'io_write_bytes')
AND probe_id = (SELECT id FROM pem.probe WHERE internal_name = 'session_info');

UPDATE pem.probe_column SET unit_of_value = '#' WHERE internal_name IN ('io_read_bytes', 'io_write_bytes')
AND probe_id = (SELECT id FROM pem.probe WHERE internal_name = 'session_info');

COMMIT TRANSACTION;
