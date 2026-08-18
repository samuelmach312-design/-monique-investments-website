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
'SELECT 201811211::integer;'
  LANGUAGE 'sql' IMMUTABLE;
COMMENT ON FUNCTION pem.schema_version() IS 'Returns the version number of the PEM schema';

DROP RULE jobagent_insert ON pem.jobagent;
CREATE RULE jobagent_insert AS ON INSERT TO pem.jobagent DO INSTEAD (
	INSERT INTO pem.agent_runtime (process_id, login_time, agent_id) VALUES (
		CASE WHEN NEW.jagpid IS NULL THEN pg_catalog.pg_backend_pid()
		ELSE NEW.jagpid END,
		CASE WHEN NEW.jaglogintime IS NULL THEN now() ELSE NEW.jaglogintime END,
		NEW.agent_id
	) RETURNING process_id AS jagpid, login_time AS jaglogintime, agent_id
);

END TRANSACTION;
