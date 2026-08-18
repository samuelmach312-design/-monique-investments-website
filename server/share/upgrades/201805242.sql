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
'SELECT 201805242::integer;'
  LANGUAGE 'sql' IMMUTABLE;

-- DROP and create a new constraint with new type 'GL' - Group line chart
ALTER TABLE pem.chart DROP CONSTRAINT pem_chart_type_constraint;
ALTER TABLE pem.chart ADD CONSTRAINT  pem_chart_type_constraint CHECK (type IN ('TE', 'TB', 'B', 'P', 'L', 'CL', 'CT', 'GL'));

-- Add column(max_group_charts_per_chart) to limit maximum number of group chart metric to display per graph, default is 16
INSERT INTO pem.config (param, value, unit, datatype) VALUES ('max_metrics_per_group_chart', '16', '', 'integer');

-- Add new VIP and VIP Status fields to EFM cluster dashboards.
UPDATE pem.chart_func
SET func = E'SELECT
            xmlelement(name table,
                xmlattributes(''pem-chart-table pem-element pem-chart-txt'' AS class, ''width:auto;'' AS style),
                xmlelement(name thead,
                    xmlelement(name tr,
                        xmlelement(name th,
                            xmlattributes(''pem-chart-th pem-element pem-table-th'' AS class),
                            ''Properties''),
                        xmlelement(name th,
                            xmlattributes(''pem-chart-th pem-element'' AS class),
                            ''Values''))),
                xmlelement(name tbody,
                    xmlelement(name tr,
                        xmlelement(name td,
                            xmlattributes(''pem-chart-td'' AS class),
                            ''Cluster Name''),
                        xmlelement(name td,
                            xmlattributes(''pem-chart-td'' AS class),
                            ps.efm_cluster_name)),
                    xmlelement(name tr,
                        xmlelement(name td,
                            xmlattributes(''pem-chart-td'' AS class),
                            ''Failover Manager Agent Running Status''),
                        xmlelement(name td,
                            xmlattributes(''pem-chart-td'' AS class),
                            CASE WHEN pe.efm_running = true THEN ''UP'' ELSE ''DOWN'' END)),
                    xmlelement(name tr,
                        xmlelement(name td,
                            xmlattributes(''pem-chart-td'' AS class),
                            ''Allowed Node List''),
                     xmlelement(name td,
                         xmlattributes(''pem-chart-td'' AS class),
                         array_to_string(pe.efm_allowed_node_list, '', ''))),
                    xmlelement(name tr,
                        xmlelement(name td,
                            xmlattributes(''pem-chart-td'' AS class),
                            ''Standby Priority List''),
                        xmlelement(name td,
                            xmlattributes(''pem-chart-td'' AS class),
                            array_to_string(pe.efm_standby_priority_list, '', ''))),
                    xmlelement(name tr,
                            xmlelement(name td,
                                xmlattributes(''pem-chart-td'' AS class),
                                ''Cluster Status Message''),
                            xmlelement(name td,
                                xmlattributes(''pem-chart-td'' AS class),
                                pe.efm_messages)),
                    xmlelement(name tr,
                        xmlelement(name td,
                            xmlattributes(''pem-chart-td'' AS class),
                            ''VIP''),
                        xmlelement(name td,
                            xmlattributes(''pem-chart-td'' AS class),
                            ps.efm_vip)),
                    xmlelement(name tr,
                        xmlelement(name td,
                            xmlattributes(''pem-chart-td'' AS class),
                            ''VIP Status''),
                        xmlelement(name td,
                            xmlattributes(''pem-chart-td'' AS class),
                            ps.efm_vip_status))))
FROM
    pemdata.efm_cluster_info pe
    LEFT JOIN pem.server ps ON (ps.id = pe.server_id)
WHERE pe.server_id = $1::int;'
WHERE id = 89;

-- Add default agent group options.
INSERT INTO pem.server_group(id, name) VALUES(0, 'PEM Agents');

-- Added new table to save per user agent grouping information.
CREATE TABLE pem.agent_options (
    agent_id            integer NOT NULL, -- Agent identifier
    pem_user            text NOT NULL DEFAULT CURRENT_USER, -- ID of PEM user
    group_id            integer,
    description         text,
    CONSTRAINT agent_option_pkey PRIMARY KEY (agent_id, pem_user),
    CONSTRAINT agent_option_agent_id_fkey FOREIGN KEY (agent_id)
        REFERENCES pem.agent (id) MATCH SIMPLE
        ON UPDATE CASCADE ON DELETE CASCADE INITIALLY DEFERRED,
    CONSTRAINT agent_option_pem_user_key UNIQUE (pem_user, agent_id),
    CONSTRAINT group_id_fkey FOREIGN KEY (group_id)
        REFERENCES pem.server_group (id) ON UPDATE NO ACTION
        ON DELETE NO ACTION
);

ALTER TABLE pem.agent ADD COLUMN group_id integer DEFAULT 0;
ALTER TABLE pem.agent ADD CONSTRAINT agent_group_id_fkey FOREIGN KEY (group_id)
        REFERENCES pem.server_group (id) ON UPDATE NO ACTION
        ON DELETE NO ACTION;

ALTER TABLE pem.server ADD COLUMN group_id integer DEFAULT 1;
ALTER TABLE pem.server ADD CONSTRAINT server_groups_id_fkey FOREIGN KEY (group_id)
        REFERENCES pem.server_group (id) ON UPDATE NO ACTION
        ON DELETE NO ACTION;

-- Added group id column to fetch available agent details.
CREATE OR REPLACE VIEW pem.avail_agents AS
    SELECT
        a.id AS id,
        a.agent_capability_list AS agent_capability_list,
        COALESCE(ao.description, a.description) AS description,
        a.active AS active,
        a.heartbeat_interval AS heartbeat_interval,
        a.alert_blackout AS alert_blackout,
        a.version AS version,
        a.platform AS platform,
        a.owner AS owner,
        a.team AS team,
        o.rolname AS agent_owner,
        COALESCE(ao.group_id, a.group_id, 0)::text AS group_id
    FROM (SELECT a.*, r.rolsuper AS rolsuper FROM pem.agent a, pg_catalog.pg_roles r WHERE r.rolname = current_user) AS a
        LEFT JOIN pem.agent_options ao ON (a.id = ao.agent_id AND pem_user = current_user)
        LEFT OUTER JOIN pg_catalog.pg_roles o ON (o.oid = a.owner)
        LEFT OUTER JOIN pg_catalog.pg_roles t ON (t.rolname = a.team)
WHERE
        -- Only active agents
        a.active AND
        -- Is a superuser
        (a.rolsuper OR
            -- No team provided
            a.team IS NULL OR a.team = '' OR
            -- Owner of the agent
            o.rolname = current_user OR
            -- Valid team provided and current_user is member of the it
            (t.oid IS NOT NULL AND pg_catalog.pg_has_role(a.team, 'member'))) OR
        -- Current user is having rights to view the server.
        EXISTS(SELECT 1 FROM pem.agent_server_binding asb JOIN pem.avail_servers asr ON (asr.id = asb.server_id) AND asb.agent_id = a.id);

COMMIT TRANSACTION;
