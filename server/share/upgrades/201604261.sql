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
'SELECT 201604261::integer;'
  LANGUAGE 'sql' IMMUTABLE;
COMMENT ON FUNCTION pem.schema_version() IS 'Returns the version number of the PEM schema';

-- Table: pem.server
ALTER TABLE pem.server
  ADD COLUMN comment text;

-- Table: pem.server_group
CREATE TABLE pem.server_group
(
  id serial NOT NULL,
  name text NOT NULL,
  pem_user text,
  CONSTRAINT "Primary_key" PRIMARY KEY (id),
  CONSTRAINT uniqueconstraint UNIQUE (id, name)
)
WITH (
  OIDS=FALSE
);

GRANT ALL ON TABLE pem.server_group TO pem_user;
GRANT ALL ON TABLE pem.server_group TO pem_admin;

ALTER TABLE pem.server_option
  ADD COLUMN server_group_id integer;
ALTER TABLE pem.server_option
  ADD CONSTRAINT server_group_id_fkey FOREIGN KEY (server_group_id) REFERENCES pem.server_group (id) ON UPDATE NO ACTION ON DELETE NO ACTION;

WITH default_group AS (
    INSERT INTO pem.server_group(name) VALUES ('PEM Server Directory') RETURNING id, name
)
UPDATE pem.server_option SET server_group_id = default_group.id
FROM default_group WHERE pem.server_option.server_group = default_group.name;

WITH s_groups AS(
    INSERT INTO pem.server_group(name, pem_user)
        SELECT
            (server_group), pem_user
        FROM pem.server_option
        WHERE server_group != 'PEM Server Directory'
        RETURNING id, name
    )
UPDATE pem.server_option SET server_group_id = s_groups.id
FROM s_groups WHERE pem.server_option.server_group = s_groups.name;

ALTER TABLE pem.server_option DROP COLUMN server_group;

COMMIT TRANSACTION;
