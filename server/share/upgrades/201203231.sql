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

-- Upgrade script for v2.1.0b3 to v2.1.0rc1

BEGIN TRANSACTION;

CREATE OR REPLACE FUNCTION pem.schema_version()
  RETURNS integer AS
'SELECT 201203231::integer;'
  LANGUAGE 'sql' IMMUTABLE;

GRANT USAGE ON SEQUENCE pem.probe_log_id_seq TO pem_agent;

CREATE OR REPLACE FUNCTION pem.create_email(alert_id integer, template text, OUT subject_mail text, OUT message_mail text) AS $$
DECLARE
        alert_name text;
        alert_agent_id int;
        alert_server_id int;
        alert_database_name text;
        alert_object_name text;
        alert_schema_name text;
        alert_thresholdvalue text;
        server_name text;
        server_ip text;
        server_port integer;
        agent_name text;
BEGIN
        -- Get alert, agent, server details
        SELECT
                a.name, a.agent_id, a.server_id, a.database_name, a.schema_name, a.object_name, a.thresholds,
                s.description, s.server, s.port,
                ag.description
        INTO                alert_name, alert_agent_id, alert_server_id, alert_database_name, alert_schema_name, alert_object_name,
                alert_thresholdvalue, server_name, server_ip, server_port,
                agent_name        FROM
                pem.alert a
                LEFT JOIN pem.server s ON a.server_id = s.id
                LEFT JOIN pem.agent ag ON a.agent_id = ag.id
        WHERE
                a.id = alert_id;

        SELECT mail_subject, mail_message INTO subject_mail, message_mail FROM pem.email_template WHERE display_name = template;
        subject_mail = regexp_replace(subject_mail, '%AlertName%', alert_name);
        subject_mail = regexp_replace(subject_mail, '%ObjectName%', COALESCE(COALESCE(server_name || ' ('|| server_ip ||': ' || server_port || ')', agent_name), 'Postgres Enterprise Manager Server'));
        message_mail = regexp_replace(message_mail, '%AlertName%', alert_name);
        message_mail = regexp_replace(message_mail, '%ObjectName%', COALESCE(COALESCE(server_name || ' ('|| server_ip ||': ' || server_port || ')', agent_name), 'N/A'));
        message_mail = regexp_replace(message_mail, '%ThresholdValue%', alert_thresholdvalue::text);
END;
$$ LANGUAGE plpgsql;

COMMIT TRANSACTION;
