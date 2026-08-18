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
'SELECT 201807061::integer;'
  LANGUAGE 'sql' IMMUTABLE;
COMMENT ON FUNCTION pem.schema_version() IS 'Returns the version number of the PEM schema';

CREATE OR REPLACE VIEW pem.avail_servers AS
    SELECT
        s.id AS id,
        s.description AS description,
        s.server AS server,
        s.port AS port,
        s.database AS database,
        s.ssl AS ssl,
        s.serviceid AS serviceid,
        s.active AS active,
        s.hostaddr AS hostaddr,
        s.service AS service,
        s.alert_blackout AS alert_blackout,
        s.owner AS owner,
        s.team AS team,
        o.rolname AS server_owner,
        s.is_remote_monitoring AS is_remote_monitoring,
        s.efm_cluster_name AS efm_cluster_name,
        s.efm_service_name AS efm_service_name,
        s.efm_installation_path AS efm_installation_path,
        COALESCE(so.server_group_id, s.group_id, 1) AS group_id
    FROM (SELECT s.*, r.rolsuper AS rolsuper FROM pem.server s, pg_catalog.pg_roles r WHERE r.rolname = current_user) AS s
        LEFT OUTER JOIN pg_catalog.pg_roles o ON (o.oid = s.owner)
        LEFT OUTER JOIN pg_catalog.pg_roles t ON (t.rolname = s.team)
        LEFT JOIN pem.server_option so ON (s.id = so.server_id AND pem_user = current_user)
    WHERE
        -- Only active servers
        s.active AND
        -- Is a superuser
        (s.rolsuper OR
            -- No team provided
            s.team IS NULL OR s.team = '' OR
            -- Owner of the server
            o.rolname = current_user OR
            -- Valid team provided and current_user is member of the it
            (t.oid IS NOT NULL AND pg_catalog.pg_has_role(s.team, 'member')));

-- As 'pem_user' can hide the group so this permission is required.
GRANT UPDATE ON TABLE pem.user_server_group TO pem_user;

COMMIT TRANSACTION;
