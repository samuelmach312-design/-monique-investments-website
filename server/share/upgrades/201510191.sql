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
'SELECT 201510191::integer;'
  LANGUAGE 'sql' IMMUTABLE;
COMMENT ON FUNCTION pem.schema_version() IS 'Returns the version number of the PEM schema';

ALTER TABLE pem.audit_configuration
	ADD COLUMN edb_audit_tag text DEFAULT ''::text;
COMMENT ON COLUMN pem.audit_configuration.edb_audit_tag IS 'Audit log session tracking tag';

ALTER TABLE pemdata.audit_logs
   ADD COLUMN audit_tag text DEFAULT ''::text;
COMMENT ON COLUMN pemdata.audit_logs.audit_tag IS 'Audit log session tracking tag';

ALTER TABLE pemdata.audit_configuration
   ADD COLUMN edb_audit_tag text DEFAULT ''::text;
COMMENT ON COLUMN pemdata.audit_configuration.edb_audit_tag IS 'Audit log session tracking tag';

ALTER TABLE pemhistory.audit_configuration
	ADD COLUMN edb_audit_tag text DEFAULT ''::text;
COMMENT ON COLUMN pem.audit_configuration.edb_audit_tag IS 'Audit log session tracking tag';

INSERT INTO pem.probe_column
        (probe_id, internal_name, display_name, display_position, classification,
        sql_data_type, unit_of_value, calculate_pit, discard_history, pit_by_default, is_graphable)
SELECT
        (SELECT max(id) FROM pem.probe where internal_name = 'audit_configuration'),
        v.internal_name, v.display_name, v.display_position, v.classification,
        v.sql_data_type, v.unit_of_value, v.calculate_pit, v.discard_history, v.pit_by_default, v.is_graphable
FROM
        (VALUES
                ('edb_audit_tag', 'Audit Tag', 10, 'm', 'text', '', false, false, false, false)
        ) v(internal_name, display_name, display_position, classification,
                sql_data_type, unit_of_value, calculate_pit, discard_history, pit_by_default, is_graphable);

UPDATE pem.alert_template set sql = 'SELECT
  CASE
    WHEN COUNT(r.result) <> 0 THEN MAX(r.result)
    ELSE -1
  END
FROM
  (SELECT
     CASE
       WHEN(p.edb_audit = pd.edb_audit
         AND p.edb_audit_directory = pd.edb_audit_directory
         AND p.edb_audit_filename = pd.edb_audit_filename
         AND p.edb_audit_rotation_day = pd.edb_audit_rotation_day
         AND p.edb_audit_rotation_sec = pd.edb_audit_rotation_sec
         AND p.edb_audit_rotation_size = pd.edb_audit_rotation_size
         AND p.edb_audit_connect = pd.edb_audit_connect
         AND p.edb_audit_disconnect = pd.edb_audit_disconnect
         AND p.edb_audit_statements = pd.edb_audit_statements
         AND p.edb_audit_tag = pd.edb_audit_tag) OR (p.server_id IS NULL)
         THEN -1
       ELSE 1
     END AS result
   FROM
	pem.audit_configuration p RIGHT JOIN
	pemdata.audit_configuration pd ON (p.server_id = pd.server_id)
   WHERE p.server_id = ${server_id}) AS r'
WHERE display_name = 'Audit config mismatch' AND
	is_system_template = TRUE;

COMMIT TRANSACTION;
