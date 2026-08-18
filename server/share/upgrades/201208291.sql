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

-- Upgrade script for 3.0.0b2 to 3.0.0b3

BEGIN TRANSACTION;

CREATE OR REPLACE FUNCTION pem.schema_version()
  RETURNS integer AS
'SELECT 201208291::integer;'
  LANGUAGE 'sql' IMMUTABLE;

ALTER TABLE pem.log_configuration DROP CONSTRAINT log_configuration_log_syslog_facility_check;
ALTER TABLE pem.log_configuration ADD CONSTRAINT log_configuration_log_syslog_facility_check CHECK (log_syslog_facility = ANY (ARRAY['none'::text, 'LOCAL0'::text, 'LOCAL1'::text, 'LOCAL2'::text, 'LOCAL3'::text, 'LOCAL4'::text, 'LOCAL5'::text, 'LOCAL6'::text, 'LOCAL7'::text]));
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE pem.log_configuration TO pem_agent;

COMMIT TRANSACTION;
