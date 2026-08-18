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
'SELECT 201508241::integer;'
  LANGUAGE 'sql' IMMUTABLE;
COMMENT ON FUNCTION pem.schema_version() IS 'Returns the version number of the PEM schema';

UPDATE pem.chart_func SET func = E'SELECT
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
                pe.efm_messages))))
FROM
    pemdata.efm_cluster_info pe
    LEFT JOIN pem.server ps ON (ps.id = pe.server_id)
WHERE pe.server_id = $1::int;' WHERE id = 89;

COMMIT TRANSACTION;
