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
'SELECT 201405281::integer;'
  LANGUAGE 'sql' IMMUTABLE;

ALTER TABLE pem.job
	ADD COLUMN issystemjob bool NOT NULL DEFAULT false;

UPDATE pem.job SET issystemjob = true WHERE jobname IN ('Database cleanup', 'Audit log table cleanup', 'Server log table cleanup', 'Probe log table cleanup',
'SMTP spool table cleanup', 'SNMP spool table cleanup', 'Alert history table cleanup', 'Job log table cleanup', 'Job purge the deleted charts', 'Purge deleted custom probes');

COMMIT TRANSACTION;
