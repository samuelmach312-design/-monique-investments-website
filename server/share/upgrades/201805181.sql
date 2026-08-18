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
'SELECT 201805181::integer;'
  LANGUAGE 'sql' IMMUTABLE;
COMMENT ON FUNCTION pem.schema_version() IS 'Returns the version number of the PEM schema';

ALTER TABLE pem.server_option ADD COLUMN use_ssh_tunnel boolean NOT NULL DEFAULT false;
ALTER TABLE pem.server_option ADD COLUMN tunnel_host text;
ALTER TABLE pem.server_option ADD COLUMN tunnel_port integer DEFAULT 22;
ALTER TABLE pem.server_option ADD COLUMN tunnel_username text;
ALTER TABLE pem.server_option ADD COLUMN tunnel_authentication boolean DEFAULT false;
ALTER TABLE pem.server_option ADD COLUMN tunnel_identity_file	text;

COMMIT TRANSACTION;
