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
'SELECT 201509251::integer;'
  LANGUAGE 'sql' IMMUTABLE;
COMMENT ON FUNCTION pem.schema_version() IS 'Returns the version number of the PEM schema';

CREATE TABLE pem.sr_existing_replication (
	id serial NOT NULL PRIMARY KEY,
	repjobid int4 NOT NULL
		REFERENCES pem.job (jobid) ON DELETE CASCADE ON UPDATE RESTRICT,
	agent_id integer NOT NULL,
	client_addr text,
	application_name text,
	state text,
	sync_priority integer,
	sync_state text
);

GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE pem.sr_existing_replication TO pem_agent;
GRANT ALL ON pem.sr_existing_replication_id_seq TO pem_agent;

-- RM 35989
CREATE OR REPLACE FUNCTION pem.alert_template_postupdate() RETURNS trigger AS $$
BEGIN
	UPDATE pem.alert SET error_message = '' WHERE template_id = NEW.id;
	RETURN NULL;
END
$$ LANGUAGE plpgsql;

CREATE TRIGGER custom_alert_template_postupdate
	AFTER UPDATE ON pem.alert_template
	FOR EACH ROW EXECUTE PROCEDURE pem.alert_template_postupdate();

COMMIT TRANSACTION;
