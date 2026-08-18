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
'SELECT 201406301::integer;'
  LANGUAGE 'sql' IMMUTABLE;

CREATE OR REPLACE FUNCTION pem.on_probe_config_database_insert_or_update() RETURNS TRIGGER AS
$$
BEGIN
	IF NEW.probe_id = (SELECT id FROM pem.probe WHERE internal_name = 'xdb_smr_mmr_replication') AND NEW.enabled IS TRUE THEN
		IF EXISTS (
			SELECT 1
			FROM pemdata.oc_schema
			WHERE database_name = NEW.database_name
			AND server_id = NEW.server_id
			AND schema_name = '_edb_replicator_pub') THEN

				RETURN NEW;
		ELSE
				RAISE EXCEPTION E'\nXDB publication''s catalog is not found.\nXDB probe should be configured on publication side.';
				RETURN NULL;
		END IF;
	ELSE
		RETURN NEW;
	END IF;
END;
$$
LANGUAGE PLPGSQL;

COMMIT TRANSACTION;
