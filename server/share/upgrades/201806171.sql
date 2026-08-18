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
'SELECT 201806171::integer;'
  LANGUAGE 'sql' IMMUTABLE;
COMMENT ON FUNCTION pem.schema_version() IS 'Returns the version number of the PEM schema';

-- Table: pem.ark_api_version
CREATE TABLE pem.ark_api_version
(
  api_version text NOT NULL,
  display_name text NOT NULL,
  CONSTRAINT ark_api_version_pkey PRIMARY KEY (api_version)
)
WITH (
  OIDS=FALSE
);
GRANT SELECT ON TABLE pem.ark_api_version TO pem_user;
GRANT ALL ON TABLE pem.ark_api_version TO pem_admin;

INSERT INTO pem.ark_api_version(api_version, display_name)
VALUES  ('v2.0', 'Ark 2.0'),
        ('v2.1', 'Ark 2.1'),
        ('v2.2', 'Ark 2.2'),
        ('v2.3', 'Ark 2.3'),
        ('v3.0', 'Ark 3.0'),
        ('v3.1', 'Ark 3.1');

-- Create table to store ark servers
CREATE TABLE pem.ark_server
(
  id serial NOT NULL,
  description text,
  cloud_provider text NOT NULL,
  protocol text NOT NULL,
  host text NOT NULL,
  port integer,
  api_version text NOT NULL,
  owner oid,
  CONSTRAINT ark_server_pkey PRIMARY KEY (id)
)
WITH (
  OIDS=FALSE
);
GRANT SELECT ON TABLE pem.ark_server TO pem_user;
GRANT ALL ON TABLE pem.ark_server TO pem_admin;
COMMENT ON TABLE pem.ark_server
  IS 'Ark server directory';

-- Function: pem.ark_server_insertion()

CREATE OR REPLACE FUNCTION pem.ark_server_insertion()
  RETURNS trigger AS
$BODY$
DECLARE
	curr_user_oid oid;
BEGIN
	IF NEW.owner IS NULL THEN
		SELECT oid INTO curr_user_oid FROM pg_catalog.pg_roles WHERE rolname = current_user;
		NEW.owner := curr_user_oid;
	END IF;
	RETURN NEW;
END

$BODY$
  LANGUAGE plpgsql VOLATILE
  COST 100;
GRANT EXECUTE ON FUNCTION pem.ark_server_insertion() TO pem_user;
GRANT EXECUTE ON FUNCTION pem.ark_server_insertion() TO pem_admin;

CREATE TRIGGER ark_server_insertion
  BEFORE INSERT
  ON pem.ark_server
  FOR EACH ROW
  EXECUTE PROCEDURE pem.ark_server_insertion();

-- Create table to store ark server user options
CREATE TABLE pem.ark_server_option
(
  id serial NOT NULL,
  ark_server_id integer NOT NULL,
  pem_user text NOT NULL,
  username text NOT NULL,
  tenant_role text,
  password text,
  CONSTRAINT ark_server_option_pkey PRIMARY KEY (id),
  CONSTRAINT ark_server_option_ark_server_id_fkey FOREIGN KEY (ark_server_id)
      REFERENCES pem.ark_server (id) MATCH SIMPLE
      ON UPDATE NO ACTION ON DELETE CASCADE
)
WITH (
  OIDS=FALSE
);
GRANT SELECT ON TABLE pem.ark_server_option TO pem_user;
GRANT ALL ON TABLE pem.ark_server_option TO pem_admin;

COMMIT TRANSACTION;
