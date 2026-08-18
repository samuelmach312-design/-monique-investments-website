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
'SELECT 201810051::integer;'
  LANGUAGE 'sql' IMMUTABLE;
COMMENT ON FUNCTION pem.schema_version() IS 'Returns the version number of the PEM schema';

DROP RULE insert_server_option ON pem.server_option;

DROP VIEW pem.server_option;

ALTER TABLE pem.server_options
    ADD COLUMN username text NOT NULL DEFAULT '';

UPDATE pem.server_options op
SET username = op_auth.username
FROM pem.server_auth op_auth
WHERE op.server_id = op_auth.server_id AND
        op.pem_user = op_auth.pem_user;

ALTER TABLE pem.server_auth DROP COLUMN username;

CREATE OR REPLACE VIEW pem.server_option AS SELECT
	o.server_id,
	o.pem_user,
	o.server_group_id,
	o.username
	FROM pem.server_options o;

COMMENT ON VIEW pem.server_option
  IS 'This view is used to maintain backward compatibility with pem agents.
  Agent will use this view to insert data in server_option and server_auth table';

CREATE RULE insert_server_option AS ON INSERT TO pem.server_option
	DO INSTEAD (
	    INSERT INTO pem.server_options (
		    server_id, pem_user, server_group_id, username)
	    VALUES (
		    NEW.server_id, NEW.pem_user, NEW.server_group_id, NEW.username);
	);

END TRANSACTION;