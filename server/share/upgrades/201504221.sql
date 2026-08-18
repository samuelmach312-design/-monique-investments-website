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
'SELECT 201504221::integer;'
  LANGUAGE 'sql' IMMUTABLE;

  ALTER TABLE pem.chart_config
   ADD COLUMN downloadformat integer NOT NULL DEFAULT 1;

  COMMENT ON TABLE pem.chart_config  IS '* downloadformat is a format in which graph will be download as a image
  + 1 - JPEG
  + 2 - PNG';

  INSERT INTO pem.config (param, value, unit, datatype) VALUES ('download_chart_format', 'jpeg', 'jpeg/png', 'string');
COMMIT TRANSACTION;