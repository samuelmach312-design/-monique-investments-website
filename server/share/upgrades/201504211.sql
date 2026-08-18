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
'SELECT 201504211::integer;'
  LANGUAGE 'sql' IMMUTABLE;

-- Add new coulmn "font" to pem.dashboard
ALTER TABLE pem.dashboard ADD COLUMN font text DEFAULT NULL;
-- Add new coulmn "font_size" to pem.dashboard
ALTER TABLE pem.dashboard ADD COLUMN font_size integer DEFAULT NULL;
-- Add new coulmn "is_ops_dashboard" to pem.dashboard
ALTER TABLE pem.dashboard ADD COLUMN is_ops_dashboard boolean NOT NULL DEFAULT false;
-- Add new coulmn "show_title" to pem.dashboard
ALTER TABLE pem.dashboard ADD COLUMN show_title boolean NOT NULL DEFAULT true;

-- Add new coulmn "legend_type" to pem.dashboard_chart
ALTER TABLE pem.dashboard_chart ADD COLUMN legend_type integer DEFAULT 1;  -- 1 : Pop-up, 2 : Side-by-side
-- Add new coulmn "show_chart_title" to pem.dashboard_chart
ALTER TABLE pem.dashboard_chart ADD COLUMN show_chart_title boolean NOT NULL DEFAULT true;

COMMIT TRANSACTION;
