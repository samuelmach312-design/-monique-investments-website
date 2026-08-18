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
'SELECT 201601071::integer;'
  LANGUAGE 'sql' IMMUTABLE;
COMMENT ON FUNCTION pem.schema_version() IS 'Returns the version number of the PEM schema';

CREATE OR REPLACE FUNCTION pem.create_passive_service_check_result(
    IN alert_id integer,
    IN template text,
    IN current_value text,
    IN current_state text,
    OUT passive_check_result text)
  RETURNS text AS $$
DECLARE
	alert_name							text;
	alert_object_name					text;
	msg_object_name						text;
	alert_thresholdvalue				text;
	server_name							text;
	server_ip							text;
	server_port							integer;
	agent_name							text;
	status_text							text;
	is_nagios_medium_alert_as_critical	boolean:=false;
BEGIN

	-- Get alert, agent, server details
	SELECT
		a.name, a.thresholds,
		s.description, s.server, s.port,
		ag.description
	INTO
		alert_name, alert_thresholdvalue,
		server_name, server_ip, server_port,
		agent_name
	FROM
		pem.alert a
		LEFT JOIN pem.server s ON a.server_id = s.id
		LEFT JOIN pem.agent ag ON a.agent_id = ag.id
	WHERE
		a.id = alert_id;

	SELECT value INTO is_nagios_medium_alert_as_critical FROM pem.config WHERE param = 'nagios_medium_alert_as_critical';

	SELECT mail_subject INTO status_text FROM pem.email_template WHERE display_name = template;

	CASE WHEN server_name IS NOT NULL THEN
		alert_object_name = server_name || ' ('|| server_ip ||': ' || server_port || ')';
		msg_object_name = alert_object_name;
	WHEN agent_name IS NOT NULL THEN
		alert_object_name = agent_name;
		msg_object_name = alert_object_name;
	-- in case of global alert agent name and server_name are NULL so description from main pem agent has been fetched
	ELSE
		SELECT description INTO alert_object_name FROM pem.agent where id = 1;
		msg_object_name = alert_object_name;
	END CASE;

	-- Replace single "\" with "\\" because regexp_replace escapes backslash
	alert_name = replace(alert_name, E'\\', E'\\\\');
	alert_object_name = replace(alert_object_name, E'\\', E'\\\\');

	status_text = regexp_replace(status_text, '%AlertName%', alert_name);
	status_text = regexp_replace(status_text, '%ObjectName%', msg_object_name);
	IF current_state IS NOT NULL THEN
		status_text = regexp_replace(status_text, '%AlertType%', current_state);
	END IF;
	status_text = status_text || E'|| Threshold values: ' || alert_thresholdvalue;
	status_text = status_text || E'|| Current Value: ' || current_value;

	IF template NOT IN ('Alert Detected','Alert Cleared') THEN
		status_text = status_text || E'|| New State: %NewState% ';
		status_text = status_text || E'|| Old State: %OldState% ';
	END IF;

	passive_check_result = E'[';
	passive_check_result = passive_check_result || now() || E'] ';
	passive_check_result = passive_check_result || E'PROCESS_SERVICE_CHECK_RESULT;';

	--in case of global alerts server_name and agent_name both are NULL so alert_object_name has been passed to nagios
	IF server_name IS NOT NULL THEN
		passive_check_result = passive_check_result || server_name || E';';
	ELSIF agent_name IS NOT NULL THEN
		passive_check_result = passive_check_result || agent_name || E';';
	ELSE
		passive_check_result = passive_check_result || alert_object_name || E';';
	END IF;

	alert_name = regexp_replace(regexp_replace(alert_name, E'[`~$%^&*|''"<>?,(=]','-'), E'[)]', '-');
	passive_check_result = passive_check_result || alert_name || E';';
	IF (current_state = 'HIGH') THEN
		passive_check_result = passive_check_result || E'2;';

	ELSIF (current_state = 'LOW') THEN
		passive_check_result = passive_check_result || E'1;';

	ELSIF (current_state = 'MEDIUM') THEN

		IF(is_nagios_medium_alert_as_critical) THEN
			passive_check_result = passive_check_result || E'2;';
		ELSE
			passive_check_result = passive_check_result || E'1;';
		END IF;

	ELSIF (current_state IS NULL) THEN
		passive_check_result = passive_check_result || E'0;';
	END IF;

	passive_check_result = passive_check_result || status_text || E';';
END $$ LANGUAGE plpgsql;

COMMIT TRANSACTION;
