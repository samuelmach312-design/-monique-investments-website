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

-- Upgrade script for 2.1.1 GA to 3.0.0b1

BEGIN TRANSACTION;

CREATE OR REPLACE FUNCTION pem.schema_version()
  RETURNS integer AS
'SELECT 201208201::integer;'
  LANGUAGE 'sql' IMMUTABLE;

UPDATE pem.email_template SET mail_message = E'Alert Details\n------------------------\nAlert Name: %AlertName%\nServer/Agent: %ObjectName%\nCurrent Value: %CurrentValue%\nThreshold Value: %ThresholdValue%\nAlert Detected: %AlertDetected%\n%DownObjects%'
WHERE display_name = 'Alert Detected' AND mail_message = E'Alert Details\n------------------------\nAlert Name: %AlertName%\nServer/Agent: %ObjectName%\nCurrent Value: %CurrentValue%\nThreshold Value: %ThresholdValue%\nAlert Detected: %AlertDetected%';

UPDATE pem.email_template SET mail_message = E'Alert Details\n------------------------\nAlert Name: %AlertName%\nServer/Agent: %ObjectName%\nCurrent Value: %CurrentValue%\nThreshold Value: %ThresholdValue%\nCurrent State: %CurrentState%\nOld State: %OldState%\nState Changed: %StateChanged%\n%DownObjects%'
WHERE display_name = 'Alert Level Increased' AND mail_message = E'Alert Details\n------------------------\nAlert Name: %AlertName%\nServer/Agent: %ObjectName%\nCurrent Value: %CurrentValue%\nThreshold Value: %ThresholdValue%\nCurrent State: %CurrentState%\nOld State: %OldState%\nState Changed: %StateChanged%';

UPDATE pem.email_template SET mail_message = E'Alert Details\n------------------------\nAlert Name: %AlertName%\nServer/Agent: %ObjectName%\nCurrent Value: %CurrentValue%\nThreshold Value: %ThresholdValue%\nCurrent State: %CurrentState%\nOld State: %OldState%\nState Changed: %StateChanged%\n%DownObjects%'
WHERE display_name = 'Alert Level Decreased' AND mail_message = E'Alert Details\n------------------------\nAlert Name: %AlertName%\nServer/Agent: %ObjectName%\nCurrent Value: %CurrentValue%\nThreshold Value: %ThresholdValue%\nCurrent State: %CurrentState%\nOld State: %OldState%\nState Changed: %StateChanged%';

UPDATE pem.email_template SET mail_message = E'Alert Details\n------------------------\nAlert Name: %AlertName%\nCurrent Value: %CurrentValue%\nThreshold Value: %ThresholdValue%\nCurrent State: %CurrentState%\nAlerting Since: %AlertingSince%\n%DownObjects%'
WHERE display_name = 'Alert Reminder' AND mail_message = E'Alert Details\n------------------------\nAlert Name: %AlertName%\nCurrent Value: %CurrentValue%\nThreshold Value: %ThresholdValue%\nCurrent State: %CurrentState%\nAlerting Since: %AlertingSince%';

CREATE OR REPLACE FUNCTION pem.send_notifications() RETURNS trigger AS $$
DECLARE
	subject text;
	message text;
	mail_group_id integer;
	is_send_email boolean:= false;
	is_acknowledged boolean:= false;
	send_mail_val boolean:= false;
	is_flapping_detected boolean:= false;
	is_send_trap boolean:= false;
	trap_oid text;
	enterprise_oid text;
	trap_version integer:= 2;
	varbinding_oid text;
	varbinding_value text;
	send_trap_val boolean:= false;
	alert_name text;
	rec record;
	down_agents_list text:= E'Agents Down:\n';
	down_servers_list text:= E'Servers Down:\n';
	index integer:= 1;
BEGIN
	-- Get alert details
	SELECT
		name, email_group_id, send_email, acknowledged, flapping_detected, send_trap, snmp_trap_version
	INTO
		alert_name, mail_group_id, is_send_email, is_acknowledged, is_flapping_detected, is_send_trap, trap_version
	FROM
		pem.alert
	WHERE
		id = NEW.alert_id;

	-- Get the list of down agents
	IF (alert_name = 'Agents Down') THEN
		FOR rec in (SELECT id, description FROM pem.get_agents_with_status('DOWN') AS (id integer, description text))
		LOOP
			down_agents_list = down_agents_list || index || ') ' || rec.description || E'\n';
			index = index + 1;
		END LOOP;
	END IF;

	-- Get the list of down servers
	IF (alert_name = 'Servers Down') THEN
		index = 1;
		FOR rec in (SELECT id, description, server , port FROM pem.get_servers_with_status('DOWN') AS
					(id integer, description text, server text, port integer))
		LOOP
			down_servers_list = down_servers_list || index || ') ' || rec.description || ' (' || rec.server ||
							':' || rec.port || E')\n';
			index = index + 1;
		END LOOP;
	END IF;

	IF ((TG_OP = 'INSERT') AND (NEW.current_state IS NOT NULL)) THEN
		-- Update state change count
		UPDATE pem.alert_status SET state_change_count = state_change_count + 1 WHERE alert_id = NEW.alert_id;

		-- SMTP Notifications
		IF is_send_email AND (NOT is_acknowledged) AND (NOT is_flapping_detected) THEN
			-- Create subject and message
			SELECT subject_mail, message_mail INTO subject, message FROM pem.create_email(NEW.alert_id, 'Alert Detected');
			subject = regexp_replace(subject, '%AlertType%', NEW.current_state::text);
			message = regexp_replace(message, '%CurrentValue%', COALESCE(NEW.current_value, 0)::text);
			message = regexp_replace(message, '%AlertDetected%', now()::text);

			-- Special handling for "Agents Down" and "Servers Down" alert
			IF (alert_name = 'Agents Down') THEN
				message = regexp_replace(message, '%DownObjects%', down_agents_list::text);
			ELSIF (alert_name = 'Servers Down') THEN
				message = regexp_replace(message, '%DownObjects%', down_servers_list::text);
			ELSE
				message = regexp_replace(message, '%DownObjects%', '');
			END IF;

			-- send emails.
			send_mail_val = pem.send_email(mail_group_id, subject, message);
			IF send_mail_val THEN
				-- update the time of mail send.
				UPDATE pem.alert SET last_mail_send = now() WHERE id = NEW.alert_id;
			END IF;
		END IF;

		-- SNMP Notifications
		IF is_send_trap AND (NOT is_acknowledged) AND (NOT is_flapping_detected) THEN
			-- Create SNMP trap objects
			SELECT
				snmp_trap_oid, snmp_enterprise_oid, snmp_varbinding_oid, snmp_varbinding_value
			INTO
				trap_oid, enterprise_oid, varbinding_oid, varbinding_value
			FROM
				pem.create_trap(NEW.alert_id);

			-- Append varbinding values
			varbinding_value = varbinding_value || '|NULL|' || COALESCE(NEW.current_value, 0)::text || '|NULL|';
			IF NEW.current_state IS NULL THEN
				varbinding_value = varbinding_value || '|CLEAR';
			ELSE
				varbinding_value = varbinding_value || NEW.current_state;
			END IF;
			-- Append current timestamp
			varbinding_value = varbinding_value || '|' || now()::text;

			-- Special handling for "Agents Down" and "Servers Down" alert
			IF (alert_name = 'Agents Down') THEN
				varbinding_value = varbinding_value || '|' || down_agents_list::text;
			ELSIF (alert_name = 'Servers Down') THEN
				varbinding_value = varbinding_value || '|' || down_servers_list::text;
			ELSIF (alert_name = 'Alert Errors') THEN
				varbinding_value = varbinding_value || '| ';
			END IF;

			-- Send SNMP traps
			send_trap_val = pem.send_snmptrap(trap_oid, enterprise_oid, trap_version, varbinding_oid, varbinding_value);
		END IF;
	END IF;

	IF ((TG_OP = 'UPDATE') AND (NEW.current_state IS DISTINCT FROM OLD.current_state)) THEN
		-- Update state change count
		UPDATE pem.alert_status SET state_change_count = state_change_count + 1 WHERE alert_id = NEW.alert_id;

		-- SMTP Notifications
		IF is_send_email AND (NOT is_acknowledged) AND (NOT is_flapping_detected) THEN
			-- If current state is NULL means alert is cleared.
			IF (NEW.current_state IS NOT NULL) THEN
				-- if OLD current_state is not null means alert level changed.
				IF (OLD.current_state IS NOT NULL AND (OLD.current_state > NEW.current_state)) THEN
					-- Create subject and message
					SELECT subject_mail, message_mail INTO subject, message FROM pem.create_email(NEW.alert_id, 'Alert Level Decreased');
					message = regexp_replace(message, '%CurrentState%', NEW.current_state::text);
					message = regexp_replace(message, '%OldState%', OLD.current_state::text);
					message = regexp_replace(message, '%StateChanged%', now()::text);
				ELSIF (OLD.current_state IS NOT NULL AND (OLD.current_state < NEW.current_state)) THEN
					-- Create subject and message
					SELECT subject_mail, message_mail INTO subject, message FROM pem.create_email(NEW.alert_id, 'Alert Level Increased');
					message = regexp_replace(message, '%CurrentState%', NEW.current_state::text);
					message = regexp_replace(message, '%OldState%', OLD.current_state::text);
					message = regexp_replace(message, '%StateChanged%', now()::text);
				ELSE
					-- Create subject and message
					SELECT subject_mail, message_mail INTO subject, message FROM pem.create_email(NEW.alert_id, 'Alert Detected');
					subject = regexp_replace(subject, '%AlertType%', NEW.current_state::text);
					message = regexp_replace(message, '%AlertDetected%', now()::text);
				END IF;
			ELSE
				-- Create subject and message
				SELECT subject_mail, message_mail INTO subject, message FROM pem.create_email(NEW.alert_id, 'Alert Cleared');
				message = regexp_replace(message, '%AlertCleared%', now()::text);
			END IF;

			message = regexp_replace(message, '%CurrentValue%', COALESCE(NEW.current_value, 0)::text);

			-- Special handling for "Agents Down" and "Servers Down" alert
			IF (alert_name = 'Agents Down') THEN
				message = regexp_replace(message, '%DownObjects%', down_agents_list::text);
			ELSIF (alert_name = 'Servers Down') THEN
				message = regexp_replace(message, '%DownObjects%', down_servers_list::text);
			ELSE
				message = regexp_replace(message, '%DownObjects%', '');
			END IF;

			-- send emails.
			send_mail_val = pem.send_email(mail_group_id, subject, message);
			IF send_mail_val THEN
				-- update the time of mail send.
				UPDATE pem.alert SET last_mail_send = now() WHERE id = NEW.alert_id;
			END IF;
		END IF;

		-- SNMP Notifications
		IF is_send_trap AND (NOT is_acknowledged) AND (NOT is_flapping_detected) THEN
			-- Create SNMP trap objects
			SELECT
				snmp_trap_oid, snmp_enterprise_oid, snmp_varbinding_oid, snmp_varbinding_value
			INTO
				trap_oid, enterprise_oid, varbinding_oid, varbinding_value
			FROM
				pem.create_trap(NEW.alert_id);

			-- Append varbinding values
			varbinding_value = varbinding_value || '|' || COALESCE(OLD.current_value, 0)::text || '|' || COALESCE(NEW.current_value, 0)::text;

			IF OLD.current_state IS NULL THEN
				varbinding_value = varbinding_value || '|CLEAR';
			ELSE
				varbinding_value = varbinding_value || '|' || OLD.current_state;
			END IF;

			IF NEW.current_state IS NULL THEN
				varbinding_value = varbinding_value || '|CLEAR';
			ELSE
				varbinding_value = varbinding_value || '|' || NEW.current_state;
			END IF;
			-- Append current timestamp
			varbinding_value = varbinding_value || '|' || now()::text;

			-- Special handling for "Agents Down" and "Servers Down" alert
			IF (alert_name = 'Agents Down') THEN
				varbinding_value = varbinding_value || '|' || down_agents_list::text;
			ELSIF (alert_name = 'Servers Down') THEN
				varbinding_value = varbinding_value || '|' || down_servers_list::text;
			ELSIF (alert_name = 'Alert Errors') THEN
				varbinding_value = varbinding_value || '| ';
			END IF;

			-- Send SNMP traps
			send_trap_val = pem.send_snmptrap(trap_oid, enterprise_oid, trap_version, varbinding_oid, varbinding_value);
		END IF;
	END IF;

	RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION pem.create_trap(alert_id integer, OUT snmp_trap_oid text, OUT snmp_enterprise_oid text, OUT snmp_varbinding_oid text, OUT snmp_varbinding_value text) AS $$
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
	alert_template_id integer;
	alert_object_type integer;
	alert_snmp_oid integer;
BEGIN
	snmp_enterprise_oid = '.1.3.6.1.4.1.27645.5444';

	-- Get alert, agent, server details
	SELECT
		a.name, a.agent_id, a.server_id, a.database_name, a.schema_name, a.object_name, a.thresholds, a.template_id,
		s.description, s.server, s.port,
		ag.description
	INTO
		alert_name, alert_agent_id, alert_server_id, alert_database_name, alert_schema_name, alert_object_name,
		alert_thresholdvalue, alert_template_id, server_name, server_ip, server_port,
		agent_name
	FROM
		pem.alert a
		LEFT JOIN pem.server s ON a.server_id = s.id
		LEFT JOIN pem.agent ag ON a.agent_id = ag.id
	WHERE
		a.id = alert_id;

	-- We used "|" as one of the delimiter for snmp_varbinding_oid and snmp_varbinding_value, so replacing it with " " to avoid errors.
	alert_name = replace(alert_name, '|', ' ');
	agent_name = replace(agent_name, '|', ' ');
	server_name = replace(server_name, '|', ' ');
	alert_database_name = replace(alert_database_name, '|', ' ');
	alert_object_name = replace(alert_object_name, '|', ' ');
	alert_schema_name = replace(alert_schema_name, '|', ' ');

	-- Get SNMP OID
	SELECT snmp_oid, object_type INTO alert_snmp_oid, alert_object_type FROM pem.alert_template WHERE id = alert_template_id;

	CASE
	WHEN alert_object_type = 50 THEN
		snmp_trap_oid = snmp_enterprise_oid || '.6.' || alert_snmp_oid;
		snmp_varbinding_oid = snmp_enterprise_oid || '.7.1|' || snmp_enterprise_oid || '.7.9|' || snmp_enterprise_oid || '.7.10|' || snmp_enterprise_oid || '.7.11|'
							|| snmp_enterprise_oid || '.7.12|' || snmp_enterprise_oid || '.7.13|' || snmp_enterprise_oid || '.7.14|'
							|| snmp_enterprise_oid || '.7.15';
		snmp_varbinding_value = alert_name || '|' || alert_thresholdvalue;
	WHEN alert_object_type = 100 THEN
		snmp_trap_oid = snmp_enterprise_oid || '.1.' || alert_snmp_oid;
		snmp_varbinding_oid = snmp_enterprise_oid || '.7.1|' || snmp_enterprise_oid || '.7.2|' || snmp_enterprise_oid || '.7.4|' || snmp_enterprise_oid ||
							'.7.9|' || snmp_enterprise_oid || '.7.10|' || snmp_enterprise_oid || '.7.11|' || snmp_enterprise_oid ||
							'.7.12|' || snmp_enterprise_oid || '.7.13|' || snmp_enterprise_oid || '.7.14';
		snmp_varbinding_value = alert_name || '|' || alert_agent_id || '|' || agent_name || '|' || alert_thresholdvalue;
	WHEN alert_object_type = 200 THEN
		snmp_trap_oid = snmp_enterprise_oid || '.2.' || alert_snmp_oid;
		snmp_varbinding_oid = snmp_enterprise_oid || '.7.1|' || snmp_enterprise_oid || '.7.3|' || snmp_enterprise_oid || '.7.5|' || snmp_enterprise_oid ||
							'.7.9|' || snmp_enterprise_oid || '.7.10|' || snmp_enterprise_oid || '.7.11|' || snmp_enterprise_oid ||
							'.7.12|' || snmp_enterprise_oid || '.7.13|' || snmp_enterprise_oid || '.7.14';
		snmp_varbinding_value = alert_name || '|' || alert_server_id || '|' || server_name || ' ('|| server_ip ||': ' || server_port || ')|'
							|| alert_thresholdvalue;
	WHEN alert_object_type = 300 THEN
		snmp_trap_oid = snmp_enterprise_oid || '.3.' || alert_snmp_oid;
		snmp_varbinding_oid = snmp_enterprise_oid || '.7.1|' || snmp_enterprise_oid || '.7.3|' || snmp_enterprise_oid || '.7.5|' || snmp_enterprise_oid ||
							'.7.6|' || snmp_enterprise_oid || '.7.9|' || snmp_enterprise_oid || '.7.10|' || snmp_enterprise_oid ||
							'.7.11|'|| snmp_enterprise_oid || '.7.12|' || snmp_enterprise_oid || '.7.13|' || snmp_enterprise_oid || '.7.14';
		snmp_varbinding_value = alert_name || '|' || alert_server_id || '|' || server_name || ' ('|| server_ip ||': ' || server_port || ')|' ||
							alert_database_name || '|' || alert_thresholdvalue;
	WHEN alert_object_type = 400 THEN
		snmp_trap_oid = snmp_enterprise_oid || '.4.' || alert_snmp_oid;
		snmp_varbinding_oid = snmp_enterprise_oid || '.7.1|' || snmp_enterprise_oid || '.7.3|' || snmp_enterprise_oid || '.7.5|' || snmp_enterprise_oid ||
							'.7.6|' || snmp_enterprise_oid || '.7.7|' || snmp_enterprise_oid || '.7.9|' || snmp_enterprise_oid ||
							'.7.10|' || snmp_enterprise_oid || '.7.11|'|| snmp_enterprise_oid || '.7.12|' || snmp_enterprise_oid ||
							'.7.13|'  ||snmp_enterprise_oid || '.7.14';
		snmp_varbinding_value = alert_name || '|' || alert_server_id || '|' || server_name || ' ('|| server_ip ||': ' || server_port || ')|' ||
							 alert_database_name || '|' || alert_schema_name || '|' || alert_thresholdvalue;
	WHEN alert_object_type > 400 THEN
		snmp_trap_oid = snmp_enterprise_oid || '.5.' || alert_snmp_oid;
		snmp_varbinding_oid = snmp_enterprise_oid || '.7.1|' || snmp_enterprise_oid || '.7.3|' || snmp_enterprise_oid || '.7.5|' || snmp_enterprise_oid ||
							'.7.6|' || snmp_enterprise_oid || '.7.7|' || snmp_enterprise_oid || '.7.8|' || snmp_enterprise_oid ||
							'.7.9|' || snmp_enterprise_oid || '.7.10|'|| snmp_enterprise_oid || '.7.11|' || snmp_enterprise_oid ||
							'.7.12|'|| snmp_enterprise_oid || '.7.13|' || snmp_enterprise_oid || '.7.14';
		snmp_varbinding_value = alert_name || '|' || alert_server_id || '|' || server_name || ' ('|| server_ip ||': ' || server_port || ')|' ||
							 alert_database_name || '|' || alert_schema_name || '|' || alert_object_name || '|' ||
							 alert_thresholdvalue;
	END CASE;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION pem.generate_alert_mib()
RETURNS text AS $$
DECLARE
	mib_text text;
BEGIN

	mib_text = E'\n-- File Name : PEM-ALERTING-MIB\n
-- Date      : ' || now()::text || E'\n
-- Author    : EnterpriseDB \n

PEM-ALERTING-MIB	DEFINITIONS ::= BEGIN

	IMPORTS
		enterprises, MODULE-IDENTITY, OBJECT-TYPE, Integer32, NOTIFICATION-TYPE
			FROM SNMPv2-SMI
		DisplayString
			FROM SNMPv2-TC
		MODULE-COMPLIANCE, OBJECT-GROUP, NOTIFICATION-GROUP
			FROM SNMPv2-CONF;


	postgresql	MODULE-IDENTITY
		LAST-UPDATED	"201109271419Z"
		ORGANIZATION	"EnterpriseDB"
		CONTACT-INFO	"http://www.enterprisedb.com"
		DESCRIPTION	"This MIB file used for alerting notifications."
		REVISION	"201109271419Z"
		DESCRIPTION	"This MIB file used for alerting notifications."
		::=  {  enterprises  27645  }

	pem	OBJECT IDENTIFIER ::=  {  postgresql  5444  }

	agentAlerts	OBJECT IDENTIFIER ::=  {  pem  1  }

	serverAlerts	OBJECT IDENTIFIER ::=  {  pem  2  }

	databaseAlerts	OBJECT IDENTIFIER ::=  {  pem  3  }

	schemaAlerts	OBJECT IDENTIFIER ::=  {  pem  4  }

	objectAlerts	OBJECT IDENTIFIER ::=  {  pem  5  }

	globalAlerts	OBJECT IDENTIFIER ::=  {  pem  6  }

	bindingVariables	OBJECT IDENTIFIER ::=  {  pem  7  }

	pemObjectGroup  OBJECT-GROUP
		OBJECTS { alertName,
			agentID,
			agentName,
			databaseName,
			objectName,
			previousStatus,
			previousValue,
			schemaName,
			serverID,
			serverName,
			status,
			thresholdValue,
			value,
			recordedTime,
			downObjects }
	STATUS 	current
	DESCRIPTION
		"This group contains the notification detail objects"
	::= { postgresql 5445 }

	alertName	OBJECT-TYPE
		SYNTAX			DisplayString
		MAX-ACCESS		read-only
		STATUS			current
		DESCRIPTION		"This parameter gives the alert name"
		::=  {  bindingVariables  1  }

	agentID		OBJECT-TYPE
		SYNTAX			Integer32
		MAX-ACCESS		read-only
		STATUS			current
		DESCRIPTION		"This parameter gives the agent id for which this alert is raised"
		::=  {  bindingVariables  2  }

	serverID	OBJECT-TYPE
		SYNTAX			Integer32
		MAX-ACCESS		read-only
		STATUS			current
		DESCRIPTION		"This parameter gives the server id for which this alert is raised"
		::=  {  bindingVariables  3  }

	agentName	OBJECT-TYPE
		SYNTAX			DisplayString
		MAX-ACCESS		read-only
		STATUS			current
		DESCRIPTION		"This parameter gives the agent name for which this alert is raised"
		::=  {  bindingVariables  4  }

	serverName	OBJECT-TYPE
		SYNTAX			DisplayString
		MAX-ACCESS		read-only
		STATUS			current
		DESCRIPTION		"This parameter gives the server name for which this alert is raised"
		::=  {  bindingVariables  5  }

	databaseName	OBJECT-TYPE
		SYNTAX			DisplayString
		MAX-ACCESS		read-only
		STATUS			current
		DESCRIPTION		"This parameter gives the database name for which this alert is raised"
		::=  {  bindingVariables  6  }

	schemaName	OBJECT-TYPE
		SYNTAX			DisplayString
		MAX-ACCESS		read-only
		STATUS			current
		DESCRIPTION		"This parameter gives the schema name for which this alert is raised"
		::=  {  bindingVariables  7  }

	objectName	OBJECT-TYPE
		SYNTAX			DisplayString
		MAX-ACCESS		read-only
		STATUS			current
		DESCRIPTION		"This parameter gives the object name for which this alert is raised"
		::=  {  bindingVariables  8  }

	thresholdValue	OBJECT-TYPE
		SYNTAX			DisplayString
		MAX-ACCESS		read-only
		STATUS			current
		DESCRIPTION		"This parameter gives the threshold value of the alert"
		::=  {  bindingVariables  9  }

	previousValue	OBJECT-TYPE
		SYNTAX			DisplayString
		MAX-ACCESS		read-only
		STATUS			current
		DESCRIPTION		"This parameter gives the current value of the alert"
		::=  {  bindingVariables  10  }

	value	OBJECT-TYPE
		SYNTAX			DisplayString
		MAX-ACCESS		read-only
		STATUS			current
		DESCRIPTION		"This parameter gives the current value of the alert"
		::=  {  bindingVariables  11  }

	previousStatus	OBJECT-TYPE
		SYNTAX			INTEGER  { low ( 0 ) , medium ( 1 ), high ( 2 ) }
		MAX-ACCESS		read-only
		STATUS			current
		DESCRIPTION		"This parameter gives the current status of the alert"
		::=  {  bindingVariables  12  }

	status	OBJECT-TYPE
		SYNTAX			INTEGER  { low ( 0 ) , medium ( 1 ), high ( 2 ) }
		MAX-ACCESS		read-only
		STATUS			current
		DESCRIPTION		"This parameter gives the old status of the alert"
		::=  {  bindingVariables  13  }

	recordedTime	OBJECT-TYPE
		SYNTAX			DisplayString
		MAX-ACCESS		read-only
		STATUS			current
		DESCRIPTION		"This parameter gives the time when the event was recorded"
		::=  {  bindingVariables  14  }

	downObjects		OBJECT-TYPE
		SYNTAX			DisplayString
		MAX-ACCESS		read-only
		STATUS			current
		DESCRIPTION		"This parameter lists the servers/agents that are in a down state"
		::=  {  bindingVariables  15  }';

	/* Agent Alerts */
	mib_text = mib_text || pem.create_mib_notification_type(100, 5446);
	/* server Alerts */
	mib_text = mib_text || pem.create_mib_notification_type(200, 5447);
	/* database Alerts */
	mib_text = mib_text || pem.create_mib_notification_type(300, 5448);
	/* schema Alerts */
	mib_text = mib_text || pem.create_mib_notification_type(400, 5449);
	/* object Alerts */
	mib_text = mib_text || pem.create_mib_notification_type(500, 5450);
	mib_text = mib_text || pem.create_mib_notification_type(600, 5451);
	mib_text = mib_text || pem.create_mib_notification_type(700, 5452);
	mib_text = mib_text || pem.create_mib_notification_type(800, 5453);
	/* global Alerts */
	mib_text = mib_text || pem.create_mib_notification_type(50, 5454);

	mib_text = mib_text || E'\nEND';

	RETURN mib_text;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION pem.create_mib_notification_type(object_type integer, group_oid_type integer)
RETURNS text AS $$
DECLARE
	return_text text = '';
	tmp_rec	RECORD;
	parent_node text;
	where_clause text;
	object_prefix text;
	object_string text;
	group_text text = '';
	group_description text = '';
	is_alert_found boolean = false;
BEGIN
	CASE
	WHEN object_type = 50 THEN
		where_clause = 'WHERE object_type = 50 AND snmp_oid > 0';
		parent_node = 'globalAlerts';
		object_string = '{ alert_name, thresholdValue, previousValue, value , previousStatus, status, recordedTime, downObjects }';
		object_prefix = 'gl';
		group_text = E'\n\n\tpemGlobalNotificationGroup  NOTIFICATION-GROUP
	\tNOTIFICATIONS {';
		group_description = 'This group contains the global notification types';
	WHEN object_type = 100 THEN
		where_clause = 'WHERE object_type = 100 AND snmp_oid > 0';
		parent_node = 'agentAlerts';
		object_string = '{ alert_name, agentID , agentName, thresholdValue, previousValue, value , previousStatus, status, recordedTime }';
		object_prefix = 'ag';
		group_text = E'\n\n\tpemAgentNotificationGroup  NOTIFICATION-GROUP
	\tNOTIFICATIONS {';
		group_description = 'This group contains the agent level notification types';
	WHEN object_type = 200 THEN
		where_clause = 'WHERE object_type = 200 AND snmp_oid > 0';
		parent_node = 'serverAlerts';
		object_string = '{ alert_name, serverID , serverName, thresholdValue, previousValue, value , previousStatus, status, recordedTime }';
		object_prefix = 'sr';
		group_text = E'\n\n\tpemServerNotificationGroup  NOTIFICATION-GROUP
	\tNOTIFICATIONS {';
		group_description = 'This group contains the server level notification types';
	WHEN object_type = 300 THEN
		where_clause = 'WHERE object_type = 300 AND snmp_oid > 0';
		parent_node = 'databaseAlerts';
		object_string = '{ alert_name, serverID , serverName, databaseName, thresholdValue, previousValue, value , previousStatus, status, recordedTime }';
		object_prefix = 'db';
		group_text = E'\n\n\tpemDatabaseNotificationGroup  NOTIFICATION-GROUP
	\tNOTIFICATIONS {';
		group_description = 'This group contains the database level notification types';
	WHEN object_type = 400 THEN
		where_clause = 'WHERE object_type = 400 AND snmp_oid > 0';
		parent_node = 'schemaAlerts';
		object_string = '{ alert_name, serverID , serverName, databaseName, schemaName, thresholdValue, previousValue, value , previousStatus, status, recordedTime }';
		object_prefix = 'sc';
		group_text = E'\n\n\tpemSchemaNotificationGroup  NOTIFICATION-GROUP
	\tNOTIFICATIONS {';
		group_description = 'This group contains the schema level notification types';
	WHEN object_type = 500 THEN
		where_clause = 'WHERE object_type = 500 AND snmp_oid > 0';
		parent_node = 'objectAlerts';
		object_string = '{ alert_name, serverID , serverName, databaseName, schemaName, objectName, thresholdValue, previousValue, value , previousStatus, status, recordedTime }';
		object_prefix = 'tb';
		group_text = E'\n\n\tpemTableNotificationGroup  NOTIFICATION-GROUP
	\tNOTIFICATIONS {';
		group_description = 'This group contains the table level notification types';
	WHEN object_type = 600 THEN
		where_clause = 'WHERE object_type = 600 AND snmp_oid > 0';
		parent_node = 'objectAlerts';
		object_string = '{ alert_name, serverID , serverName, databaseName, schemaName, objectName, thresholdValue, previousValue, value , previousStatus, status, recordedTime }';
		object_prefix = 'in';
		group_text = E'\n\n\tpemIndexNotificationGroup  NOTIFICATION-GROUP
	\tNOTIFICATIONS {';
		group_description = 'This group contains the index level notification types';
	WHEN object_type = 700 THEN
		where_clause = 'WHERE object_type = 700 AND snmp_oid > 0';
		parent_node = 'objectAlerts';
		object_string = '{ alert_name, serverID , serverName, databaseName, schemaName, objectName, thresholdValue, previousValue, value , previousStatus, status, recordedTime }';
		object_prefix = 'se';
		group_text = E'\n\n\tpemSequenceNotificationGroup  NOTIFICATION-GROUP
	\tNOTIFICATIONS {';
		group_description = 'This group contains the sequence level notification types';
	WHEN object_type = 800 THEN
		where_clause = 'WHERE object_type = 800 AND snmp_oid > 0';
		parent_node = 'objectAlerts';
		object_string = '{ alert_name, serverID , serverName, databaseName, schemaName, objectName, thresholdValue, previousValue, value , previousStatus, status, recordedTime }';
		object_prefix = 'fn';
		group_text = E'\n\n\tpemFunctionNotificationGroup  NOTIFICATION-GROUP
	\tNOTIFICATIONS {';
		group_description = 'This group contains the function level notification types';
	END CASE;

	FOR tmp_rec IN EXECUTE 'SELECT display_name, description , snmp_oid FROM pem.alert_template ' || where_clause || ' ORDER BY snmp_oid'
	LOOP
		is_alert_found = true;
		tmp_rec.display_name = lower(tmp_rec.display_name);
		tmp_rec.display_name = replace(tmp_rec.display_name, '(', '');
		tmp_rec.display_name = replace(tmp_rec.display_name, ')', '');
		tmp_rec.display_name = replace(tmp_rec.display_name, ',', '');
		tmp_rec.display_name = replace(tmp_rec.display_name, '-', '');
		tmp_rec.display_name = replace(tmp_rec.display_name, '_', '');
		tmp_rec.display_name = initcap(tmp_rec.display_name);
		tmp_rec.display_name = replace(tmp_rec.display_name, ' ', '');

		IF char_length(tmp_rec.display_name) > 62 THEN
			tmp_rec.display_name = substr(tmp_rec.display_name, 0, 62);
		END IF;

		return_text =  return_text || E'\n\n\t' || object_prefix || tmp_rec.display_name || E'   NOTIFICATION-TYPE
		OBJECTS			' || object_string || E'
		STATUS			current
		DESCRIPTION \t\t"'	||	tmp_rec.description || E'"
		::=  {  ' || parent_node || '  ' || tmp_rec.snmp_oid::text ||  '  }';

		group_text = group_text || E'\n\t\t\t' ||object_prefix || tmp_rec.display_name || E',';
	END LOOP;

	group_text = trim(trailing ',' from group_text);

	group_text = group_text || '}
	STATUS 	current
	DESCRIPTION
		"'|| group_description ||'"
	::= { postgresql ' || group_oid_type || '}';

	IF is_alert_found THEN
		RETURN group_text || return_text;
	ELSE
		RETURN return_text;
	END IF;
END;
$$ LANGUAGE plpgsql;

CREATE TYPE pem.server_agent_state AS ENUM(
	'UP',
	'DOWN',
	'UNKNOWN',
	'BLACKEDOUT'
);

CREATE OR REPLACE FUNCTION pem.get_servers_with_status(server_state pem.server_agent_state) RETURNS SETOF RECORD
AS $$
DECLARE
	row  RECORD;
	sql  text;
BEGIN

	IF (server_state = 'UP') THEN
		sql =  'SELECT ps.id, ps.description, ps.server, ps.port
				FROM
					pem.avail_servers ps LEFT OUTER JOIN pem.server_heartbeat psh ON (ps.id = psh.server_id),
					pem.agent pa,
					pem.agent_server_binding pasb
				WHERE
					pa.id = pasb.agent_id AND
					ps.id = pasb.server_id AND
					CASE WHEN psh.agent_id IS NULL THEN FALSE ELSE psh.agent_id = pa.id END AND
					CASE WHEN psh.server_id IS NULL THEN FALSE ELSE psh.last_heartbeat < now() AND psh.last_heartbeat > now() - (pa.heartbeat_interval)*2*''1 second''::interval END';
	ELSIF (server_state = 'DOWN') THEN
		sql =  'SELECT ps.id, ps.description, ps.server, ps.port
				FROM
					pem.avail_servers ps LEFT OUTER JOIN pem.server_heartbeat psh ON (ps.id = psh.server_id),
					pem.agent pa LEFT OUTER JOIN pem.agent_heartbeat pah ON (pa.id = pah.agent_id),
					pem.agent_server_binding pasb
				WHERE
					pa.id = pasb.agent_id AND
					ps.id = pasb.server_id AND
					pa.active = TRUE AND
					CASE WHEN psh.agent_id IS NULL THEN FALSE ELSE psh.agent_id = pa.id END AND
					CASE WHEN pah.agent_id is NULL THEN FALSE ELSE pah.last_heartbeat < now() AND pah.last_heartbeat > now() - (pa.heartbeat_interval)*2*''1 second''::interval END AND
					CASE WHEN psh.server_id IS NULL THEN FALSE ELSE psh.last_heartbeat < now() - (pa.heartbeat_interval)*2*''1 second''::interval END';
	ELSIF (server_state = 'UNKNOWN') THEN
		sql =  'SELECT ps.id, ps.description, ps.server, ps.port
				FROM
					pem.avail_servers ps LEFT OUTER JOIN pem.server_heartbeat psh ON (ps.id = psh.server_id),
					pem.agent pa LEFT OUTER JOIN pem.agent_heartbeat pah ON (pa.id = pah.agent_id),
					pem.agent_server_binding pasb
				WHERE
					pa.id = pasb.agent_id AND
					ps.id = pasb.server_id AND
					pa.active = TRUE AND
					((pah.agent_id IS NULL) OR
					(pah.last_heartbeat < now() - (pa.heartbeat_interval)*2*''1 second''::interval) OR
					(psh.server_id IS NULL))';
	ELSIF (server_state = 'BLACKEDOUT') THEN
		sql =  'SELECT ps.id, ps.description, ps.server, ps.port
				FROM
					pem.avail_servers ps LEFT OUTER JOIN pem.server_heartbeat psh ON (ps.id = psh.server_id),
					pem.agent pa,
					pem.agent_server_binding pasb
				WHERE
					pa.id = pasb.agent_id AND
					ps.id = pasb.server_id AND
					ps.alert_blackout AND
					CASE WHEN psh.agent_id IS NULL THEN FALSE ELSE psh.agent_id = pa.id END AND
					CASE WHEN psh.server_id IS NULL THEN FALSE ELSE psh.last_heartbeat < now() AND psh.last_heartbeat > now() - (pa.heartbeat_interval)*2*''1 second''::interval END';
	END IF;

	FOR row IN EXECUTE sql
	LOOP
		RETURN NEXT row;
	END LOOP;

	RETURN;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION pem.get_agents_with_status(agent_state pem.server_agent_state) RETURNS SETOF RECORD
AS $$
DECLARE
	row  RECORD;
	sql  text;
BEGIN

	IF (agent_state = 'UP') THEN
		sql =  'SELECT pa.id, pa.description
				FROM
					pem.agent pa LEFT OUTER JOIN pem.agent_heartbeat pah ON (pa.id = pah.agent_id)
				WHERE
					pa.active = TRUE AND
					CASE WHEN pah.agent_id IS NULL THEN FALSE ELSE pah.last_heartbeat < now() AND pah.last_heartbeat > now() - (pa.heartbeat_interval)*2*''1 second''::interval END';
	ELSIF (agent_state = 'DOWN') THEN
		sql =  'SELECT pa.id, pa.description
				FROM
					pem.agent pa LEFT OUTER JOIN pem.agent_heartbeat pah ON (pa.id = pah.agent_id)
				WHERE
					pa.active = TRUE AND
					CASE WHEN pah.agent_id IS NULL THEN FALSE ELSE pah.last_heartbeat < now() - (pa.heartbeat_interval)*2*''1 second''::interval END';
	ELSIF (agent_state = 'UNKNOWN') THEN
		sql =  'SELECT pa.id, pa.description
				FROM
					pem.agent pa LEFT OUTER JOIN pem.agent_heartbeat pah ON (pa.id = pah.agent_id)
				WHERE
					pa.active = TRUE AND
					pah.agent_id IS NULL';
	ELSIF (agent_state = 'BLACKEDOUT') THEN
		sql =  'SELECT pa.id, pa.description
				FROM
					pem.agent pa LEFT OUTER JOIN pem.agent_heartbeat pah ON (pa.id = pah.agent_id)
				WHERE
					pa.active = TRUE AND
					pa.alert_blackout AND
					CASE WHEN pah.agent_id IS NULL THEN FALSE ELSE pah.last_heartbeat < now() AND pah.last_heartbeat > now() - (pa.heartbeat_interval)*2*''1 second''::interval END';
	END IF;

	FOR row IN EXECUTE sql
	LOOP
		RETURN NEXT row;
	END LOOP;

	RETURN;
END;
$$ LANGUAGE plpgsql;

-- Fixed FB 20890 "Confusing display of table names"
CREATE OR REPLACE FUNCTION pem.pe_rule_missing_primary_keys(serverID int, rulename text, databasename text) RETURNS BOOLEAN
AS $$
DECLARE
	is_postgres boolean;
	query text;
	severity_val int:= 0;
	data_name_arr text[];
	data_value_arr text[];
	row RECORD;
	resultcount int:= 0;
	index int:= 0;
	schema_count int:= 0;

BEGIN
	SELECT sv.id < 20000 into is_postgres FROM pem.server_version sv WHERE sv.id = (SELECT si.server_version_id FROM pem.pemdata.server_info si WHERE si.server_id = serverID);

	SELECT count(schema_name) INTO schema_count FROM pemdata.oc_schema WHERE database_name = databasename AND server_id = serverID AND schema_name IN ('pem', 'pemdata' , 'pemhistory');

	IF (is_postgres) THEN
		IF (schema_count = 3) THEN
			query := E'SELECT schema_name, table_name FROM pemdata.oc_table WHERE database_name = ''' || databasename || ''' AND server_id = ''' || serverID || ''' AND has_primary_key = false AND schema_name not in (''pem'', ''pemdata'', ''pemhistory'', ''information_schema'', ''pg_catalog'', ''pg_log'', ''pg_temp'');';
		ELSE
			query := E'SELECT schema_name, table_name FROM pemdata.oc_table WHERE database_name = ''' || databasename || ''' AND server_id = ''' || serverID || ''' AND has_primary_key = false AND schema_name not in (''information_schema'', ''pg_catalog'', ''pg_log'', ''pg_temp'');';
		END IF;
	ELSE
		IF (schema_count = 3) THEN
			query := E'SELECT schema_name, table_name FROM pemdata.oc_table WHERE database_name = ''' || databasename || ''' AND server_id = ''' || serverID || ''' AND has_primary_key = false AND schema_name not in (''pem'', ''pemdata'', ''pemhistory'', ''information_schema'', ''pg_catalog'', ''pg_log'', ''pg_temp'', ''sys'', ''dbo'');';
		ELSE
			query := E'SELECT schema_name, table_name FROM pemdata.oc_table WHERE database_name = ''' || databasename || ''' AND server_id = ''' || serverID || ''' AND has_primary_key = false AND schema_name not in (''information_schema'', ''pg_catalog'', ''pg_log'', ''pg_temp'', ''sys'', ''dbo'');';
		END IF;
	END IF;

	FOR row IN EXECUTE query
	LOOP
		data_name_arr[index]   	:= 'table';
		data_value_arr[index]  	:= quote_literal(row.schema_name) || '.' || quote_literal(row.table_name);

		resultcount:= resultcount + 1;
		index:= index + 1;
	END LOOP;

	IF (resultcount > 0 ) THEN
		severity_val := 1;

		-- Update the values of data_name , data_value and severity
		UPDATE temp_expert_records SET data_name = data_name_arr, data_value = data_value_arr, severity = severity_val WHERE rule_name = rulename AND server_id = serverID  AND database_name = databasename;
	ELSE
		DELETE FROM temp_expert_records WHERE rule_name = rulename AND server_id = serverID  AND database_name = databasename;
	END IF;

	RETURN TRUE;
END
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION pem.pe_rule_check_too_many_indexes(serverID int, rulename text, databasename text) RETURNS BOOLEAN
AS $$
DECLARE
	is_postgres boolean;
	query text;
	severity_val int:= 0;
	data_name_arr text[];
	data_value_arr text[];
	row RECORD;
	resultcount int:= 0;
	index int:= 0;
	schema_count int:= 0;

BEGIN
	SELECT sv.id < 20000 into is_postgres FROM pem.server_version sv WHERE sv.id = (SELECT si.server_version_id FROM pem.pemdata.server_info si WHERE si.server_id = serverID);

	SELECT count(schema_name) INTO schema_count FROM pemdata.oc_schema WHERE database_name = databasename AND server_id = serverID AND schema_name IN ('pem', 'pemdata' , 'pemhistory');

	IF (is_postgres) THEN
		IF (schema_count = 3) THEN
			query = E'SELECT CASE WHEN COUNT(*) >= 8 AND COUNT(*) < 10 THEN 1 WHEN COUNT(*) >= 10 AND COUNT(*) < 20 THEN 5 WHEN COUNT(*) >= 20 THEN 9 ELSE 0 END AS severity, schema_name, table_name FROM pemdata.oc_index WHERE database_name = ''' || databasename || ''' AND server_id = ''' || serverID || ''' AND schema_name not in (''pem'', ''pemdata'', ''pemhistory'', ''information_schema'', ''pg_catalog'', ''pg_log'', ''pg_temp'') GROUP BY database_name, schema_name, table_name;';
		ELSE
			query = E'SELECT CASE WHEN COUNT(*) >= 8 AND COUNT(*) < 10 THEN 1 WHEN COUNT(*) >= 10 AND COUNT(*) < 20 THEN 5 WHEN COUNT(*) >= 20 THEN 9 ELSE 0 END AS severity, schema_name, table_name FROM pemdata.oc_index WHERE database_name = ''' || databasename || ''' AND server_id = ''' || serverID || ''' AND schema_name not in (''information_schema'', ''pg_catalog'', ''pg_log'', ''pg_temp'') GROUP BY database_name, schema_name, table_name;';
		END IF;
	ELSE
		IF (schema_count = 3) THEN
			query = E'SELECT CASE WHEN COUNT(*) >= 8 AND COUNT(*) < 10 THEN 1 WHEN COUNT(*) >= 10 AND COUNT(*) < 20 THEN 5 WHEN COUNT(*) >= 20 THEN 9 ELSE 0 END AS severity, schema_name, table_name FROM pemdata.oc_index WHERE database_name = ''' || databasename || ''' AND server_id = ''' || serverID || ''' AND schema_name not in (''pem'', ''pemdata'', ''pemhistory'', ''information_schema'', ''pg_catalog'', ''pg_log'', ''pg_temp'', ''sys'', ''dbo'') GROUP BY database_name, schema_name, table_name;';
		ELSE
			query = E'SELECT CASE WHEN COUNT(*) >= 8 AND COUNT(*) < 10 THEN 1 WHEN COUNT(*) >= 10 AND COUNT(*) < 20 THEN 5 WHEN COUNT(*) >= 20 THEN 9 ELSE 0 END AS severity, schema_name, table_name FROM pemdata.oc_index WHERE database_name = ''' || databasename || ''' AND server_id = ''' || serverID || ''' AND schema_name not in (''information_schema'', ''pg_catalog'', ''pg_log'', ''pg_temp'', ''sys'', ''dbo'') GROUP BY database_name, schema_name, table_name;';
		END IF;
	END IF;

	FOR row IN EXECUTE query
	LOOP
		IF (row.severity > 0) THEN
			data_name_arr[index]   	:= 'table';
			data_value_arr[index]  	:= quote_literal(row.schema_name) || '.' || quote_literal(row.table_name);
			index:= index + 1;
		END IF;

		resultcount:= resultcount + 1;

		IF (row.severity > severity_val) THEN
			severity_val := row.severity;
		END IF;
	END LOOP;

	IF (resultcount > 0 ) AND (severity_val > 0) THEN
		-- Update the values of data_name , data_value and severity
		UPDATE temp_expert_records SET data_name = data_name_arr, data_value = data_value_arr, severity = severity_val WHERE rule_name = rulename AND server_id = serverID  AND database_name = databasename;
	ELSE
		DELETE FROM temp_expert_records WHERE rule_name = rulename AND server_id = serverID  AND database_name = databasename;
	END IF;

	RETURN TRUE;
END
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION pem.pe_rule_missing_foreign_key_indexes(serverID int, rulename text, databasename text) RETURNS BOOLEAN
AS $$
DECLARE
	is_postgres boolean;
	query text;
	subquery text;
	severity_val int:= 0;
	data_name_arr text[];
	data_value_arr text[];
	row RECORD; subquery_row RECORD;
	resultcount int:= 0;
	index int:= 0;
	is_key_indexed boolean;
	schema_count int:= 0;

BEGIN
	SELECT sv.id < 20000 into is_postgres FROM pem.server_version sv WHERE sv.id = (SELECT si.server_version_id FROM pem.pemdata.server_info si WHERE si.server_id = serverID);

	SELECT count(schema_name) INTO schema_count FROM pemdata.oc_schema WHERE database_name = databasename AND server_id = serverID AND schema_name IN ('pem', 'pemdata' , 'pemhistory');

	IF (is_postgres) THEN
		IF (schema_count = 3) THEN
			query = E'SELECT conkey, fktab, schema_name FROM pemdata.oc_foreign_key WHERE database_name = ''' || databasename || ''' AND server_id = ''' || serverID || ''' AND schema_name not in (''pem'', ''pemdata'', ''pemhistory'', ''information_schema'', ''pg_catalog'', ''pg_log'', ''pg_temp'');';
		ELSE
			query = E'SELECT conkey, fktab, schema_name FROM pemdata.oc_foreign_key WHERE database_name = ''' || databasename || ''' AND server_id = ''' || serverID || ''' AND schema_name not in (''information_schema'', ''pg_catalog'', ''pg_log'', ''pg_temp'');';
		END IF;
	ELSE
		IF (schema_count = 3) THEN
			query = E'SELECT conkey, fktab, schema_name FROM pemdata.oc_foreign_key WHERE database_name = ''' || databasename || ''' AND server_id = ''' || serverID || ''' AND schema_name not in (''pem'', ''pemdata'', ''pemhistory'', ''information_schema'', ''pg_catalog'', ''pg_log'', ''pg_temp'', ''sys'', ''dbo'');';
		ELSE
			query = E'SELECT conkey, fktab, schema_name FROM pemdata.oc_foreign_key WHERE database_name = ''' || databasename || ''' AND server_id = ''' || serverID || ''' AND schema_name not in (''information_schema'', ''pg_catalog'', ''pg_log'', ''pg_temp'', ''sys'', ''dbo'');';
		END IF;

	END IF;

	FOR row IN EXECUTE query
	LOOP
		subquery = E'SELECT pem.int2vector2array(ind_keys) AS index_keys FROM pemdata.oc_index WHERE table_name = ''' || row.fktab || ''' AND schema_name = ''' || row.schema_name ||''';';
		is_key_indexed := false;

		FOR subquery_row IN EXECUTE subquery
		LOOP
			IF (row.conkey = subquery_row.index_keys) THEN
				is_key_indexed = true;
			END IF;
		END LOOP;

		IF (is_key_indexed != true) THEN
			data_name_arr[index]   	:= 'table';
			data_value_arr[index]  	:= quote_literal(row.schema_name) || '.' || quote_literal(row.fktab);

			severity_val := 5;
			index:= index + 1;
			resultcount:= resultcount + 1;
		END IF;

	END LOOP;

	IF (resultcount > 0 ) THEN
		-- Update the values of data_name , data_value and severity
		UPDATE temp_expert_records SET data_name = data_name_arr, data_value = data_value_arr, severity = severity_val WHERE rule_name = rulename AND server_id = serverID  AND database_name = databasename;
	ELSE
		DELETE FROM temp_expert_records WHERE rule_name = rulename AND server_id = serverID  AND database_name = databasename;
	END IF;

	RETURN TRUE;
END
$$ LANGUAGE plpgsql;

-- Enhancement in server configuration dialog

ALTER TABLE pem.config ADD COLUMN unit text;
ALTER TABLE pem.config ADD COLUMN datatype text NOT NULL DEFAULT '';

UPDATE pem.config SET unit = 'days', datatype = 'integer' WHERE param IN ('probe_log_retention_time', 'audit_log_retention_time',
'job_retention_time', 'dash_server_dbsize_span', 'dash_server_tabspacesize_span', 'dash_server_sharedbuff_span', 'dash_server_useract_span',
'dash_server_global_span', 'dash_server_rowact_span', 'dash_server_comrol_span', 'dash_memory_servmemact_span', 'dash_memory_hostmemact_span',
'dash_db_useract_span', 'dash_db_io_span', 'dash_db_rowact_span', 'dash_db_comrol_span', 'dash_io_dbio_span', 'dash_io_rowact_span',
'dash_io_chkpt_span', 'dash_os_cpu_span', 'dash_os_memory_span', 'dash_os_disk_span', 'dash_os_data_span', 'dash_os_packet_span',
'dash_os_traffic_span', 'smtp_spool_retention_time', 'snmp_spool_retention_time');

UPDATE pem.config SET unit = 'years', datatype = 'integer' WHERE param = 'cm_max_end_date_in_years';
UPDATE pem.config SET unit = 'hours', datatype = 'integer' WHERE param = 'reminder_notification_interval';
UPDATE pem.config SET unit = 'minutes', datatype = 'integer' WHERE param = 'long_running_transaction_minutes';

UPDATE pem.config SET value = CASE WHEN value = '1' THEN 't' ELSE 'f' END, unit = 't/f', datatype = 'bool' WHERE param = 'chart_disable_bullets';

UPDATE pem.config SET unit = 't/f', datatype = 'bool' WHERE param IN ('auto_create_agent_alerts', 'auto_create_server_alerts', 'smtp_encryption',
'smtp_enabled', 'smtp_authentication', 'snmp_enabled');

UPDATE pem.config SET unit = '', datatype = 'string' WHERE param IN ('smtp_server', 'smtp_username', 'smtp_password', 'snmp_server', 'snmp_community');

UPDATE pem.config SET unit = '', datatype = 'integer' WHERE param IN ('cm_data_points_per_report', 'smtp_port', 'flapping_detection_state_change', 'snmp_port');

UPDATE pem.config SET unit = 'rows', datatype = 'integer' WHERE param IN ('dash_db_hottable_rows', 'dash_io_objectio_rows',
'dash_objectact_objectactivity_rows', 'dash_objectact_objstorage_rows');

UPDATE pem.config SET unit = 'seconds', datatype = 'integer' WHERE param IN ('dash_objectact_objtoptables_timeout', 'dash_objectact_objtopindexes_timeout',
'dash_objectact_objectactivity_timeout', 'dash_objectact_objstorage_timeout', 'dash_probe_log_timeout', 'dash_sess_waits_nowaits_timeout',
'dash_sess_waits_timewait_timeout', 'dash_sess_waits_waitdtl_timeout', 'dash_sys_waits_nowaits_timeout', 'dash_sys_waits_timewait_timeout',
'dash_sys_waits_waitdtl_timeout', 'dash_sessact_workload_timeout', 'dash_sessact_lockact_timeout', 'dash_storage_dbovervw_timeout',
'dash_storage_tblspcovervw_timeout', 'dash_storage_hostovervw_timeout', 'dash_storage_dbdtls_timeout', 'dash_storage_tblspcdtls_timeout',
'dash_storage_hostdtls_timeout', 'dash_memory_servmemact_timeout', 'dash_memory_servmemconf_timeout', 'dash_memory_hostmemact_timeout',
'dash_memory_hostmemconf_timeout', 'dash_io_dbio_timeout', 'dash_io_rowact_timeout', 'dash_io_chkpt_timeout', 'dash_io_hottbl_timeout',
'dash_io_hotindx_timeout', 'dash_io_objectio_timeout', 'dash_db_storage_timeout', 'dash_db_useract_timeout', 'dash_db_connovervw_timeout',
'dash_db_io_timeout', 'dash_db_rowact_timeout', 'dash_db_comrol_timeout', 'dash_db_hottable_timeout', 'dash_os_cpu_timeout', 'dash_os_storage_timeout',
'dash_os_memory_timeout', 'dash_os_util_timeout', 'dash_os_io_timeout', 'dash_os_packet_timeout', 'dash_os_traffic_timeout', 'dash_server_dbsize_timeout',
'dash_server_tabspacesize_timeout', 'dash_server_sharedbuff_timeout', 'dash_server_hostmem_timeout', 'dash_server_useract_timeout', 'dash_server_connovervw_timeout',
'dash_server_disk_timeout', 'dash_server_rowact_timeout', 'dash_server_comrol_timeout', 'dash_server_database_timeout', 'dash_global_overview_timeout',
'dash_header_timeout', 'dash_alerts_timeout');

-- Log Manager relations
CREATE TABLE pem.log_configuration (
	server_id					integer NOT NULL, -- Server ID
	log_destination				text NOT NULL DEFAULT 'stderr'::text, -- Log Destination
	log_collector				boolean NOT NULL DEFAULT true, -- Log collector status
	log_silent_mode				boolean NOT NULL DEFAULT false, -- Silent mode
	log_directory       		text NOT NULL DEFAULT 'pg_log'::text, -- Log Directory
	log_filename				text NOT NULL DEFAULT 'postgresql-%Y-%m-%d_%H%M%S.log'::text, -- Log Filename
	log_syslog_facility			text NOT NULL DEFAULT 'LOCAL0'::text, -- Syslog facility
	log_syslog_ident			text NOT NULL DEFAULT 'postgres'::text, -- Syslog ident
	log_rotation_size   		integer NOT NULL DEFAULT 10, -- Log Rotation (On size basis)
	log_rotation_time   		integer NOT NULL DEFAULT 1, -- Log Rotation (On time basis)
	log_rotation_truncate 		boolean NOT NULL DEFAULT false, -- Log truncate on rotation
	log_client_min_messages		text NOT NULL DEFAULT 'notice'::text, -- Client min messages
	log_min_messages			text NOT NULL DEFAULT 'warning'::text, -- Log min messages
	log_min_error_statement		text NOT NULL DEFAULT 'error'::text, -- min error messages
	log_min_duration_statement	integer NOT NULL DEFAULT -1, -- min duration messages
	log_parse_tree				boolean NOT NULL DEFAULT false,
	log_rewriter_output			boolean NOT NULL DEFAULT false,
	log_exec_plan				boolean NOT NULL DEFAULT false,
	log_indent_debug_output		boolean NOT NULL DEFAULT true,
	log_checkpoints				boolean NOT NULL DEFAULT false,
	log_connections				boolean NOT NULL DEFAULT false,
	log_disconnections			boolean NOT NULL DEFAULT false,
	log_duration				boolean NOT NULL DEFAULT false,
	log_hostname				boolean NOT NULL DEFAULT false,
	log_lock_waits				boolean NOT NULL DEFAULT false,
	log_error_verbosity   		text NOT NULL DEFAULT 'default'::text,
	log_prefix_string  			text,
	log_statements     			text NOT NULL DEFAULT 'none'::text,
	log_import					boolean NOT NULL DEFAULT false,
	log_import_frequency        text NOT NULL DEFAULT '1 Hour'::text,
	last_read_filename          text, -- Last Read Log File
	file_offset                 bigint, -- Last File Offset read
	CONSTRAINT log_configuration_pkey PRIMARY KEY (server_id),
	CONSTRAINT log_configuration_server_id_fkey FOREIGN KEY (server_id)
                REFERENCES pem.server (id) MATCH SIMPLE
                ON UPDATE CASCADE ON DELETE CASCADE INITIALLY DEFERRED,
	CHECK (log_syslog_facility IN ('LOCAL0', 'LOCAL1', 'LOCAL2', 'LOCAL3', 'LOCAL4', 'LOCAL5', 'LOCAL6', 'LOCAL7')),
	CHECK (log_client_min_messages IN ('debug5', 'debug4', 'debug3', 'debug2', 'debug1', 'log', 'notice', 'warning', 'error', 'fatal', 'panic')),
	CHECK (log_min_messages IN ('debug5', 'debug4', 'debug3', 'debug2', 'debug1', 'info', 'notice', 'warning', 'error', 'log', 'fatal', 'panic')),
	CHECK (log_min_error_statement IN ('debug5', 'debug4', 'debug3', 'debug2', 'debug1', 'info', 'notice', 'warning', 'error', 'log', 'fatal', 'panic')),
	CHECK (log_error_verbosity IN ('terse', 'default', 'verbose')),
	CHECK (log_statements IN ('none', 'ddl', 'mod', 'all'))
);

COMMENT ON TABLE pem.log_configuration IS 'Global log configuration data';
COMMENT ON COLUMN pem.log_configuration.server_id IS 'Server id for which log configuration is stored';
COMMENT ON COLUMN pem.log_configuration.log_destination IS 'Log destination and format';
COMMENT ON COLUMN pem.log_configuration.log_collector IS 'Enable/Disable log collector';
COMMENT ON COLUMN pem.log_configuration.log_directory IS 'Log directory';
COMMENT ON COLUMN pem.log_configuration.log_filename IS 'Log filename';
COMMENT ON COLUMN pem.log_configuration.log_syslog_facility IS 'Locale for syslog';
COMMENT ON COLUMN pem.log_configuration.log_syslog_ident IS 'Identifier to check postgres log messages in the log';
COMMENT ON COLUMN pem.log_configuration.log_rotation_size IS 'Log rotation based on size';
COMMENT ON COLUMN pem.log_configuration.log_rotation_time IS 'Log rotation based on time';
COMMENT ON COLUMN pem.log_configuration.log_rotation_truncate IS 'Truncate log on rotation';
COMMENT ON COLUMN pem.log_configuration.log_client_min_messages IS 'Which log messages to be sent to client';
COMMENT ON COLUMN pem.log_configuration.log_min_messages IS 'Which log messages are to be written to server log';
COMMENT ON COLUMN pem.log_configuration.log_min_error_statement IS 'Which SQL statements that cause an error condition are recorded';
COMMENT ON COLUMN pem.log_configuration.log_min_duration_statement IS 'Log statements which took greater than this time';
COMMENT ON COLUMN pem.log_configuration.log_parse_tree IS 'Log debug parse tree';
COMMENT ON COLUMN pem.log_configuration.log_rewriter_output IS 'Log debug rewriter output';
COMMENT ON COLUMN pem.log_configuration.log_exec_plan IS 'Log debug execution plan';
COMMENT ON COLUMN pem.log_configuration.log_indent_debug_output IS 'Indent debug outputs';
COMMENT ON COLUMN pem.log_configuration.log_checkpoints IS 'Log checkpoints';
COMMENT ON COLUMN pem.log_configuration.log_connections IS 'Log connections';
COMMENT ON COLUMN pem.log_configuration.log_disconnections IS 'Log disconnections';
COMMENT ON COLUMN pem.log_configuration.log_duration IS 'Log duration';
COMMENT ON COLUMN pem.log_configuration.log_hostname IS 'Log hostname';
COMMENT ON COLUMN pem.log_configuration.log_lock_waits IS 'Log lock waits';
COMMENT ON COLUMN pem.log_configuration.log_error_verbosity IS 'The amount of detail written in the server log';
COMMENT ON COLUMN pem.log_configuration.log_prefix_string IS 'Prefix for each line in the log';
COMMENT ON COLUMN pem.log_configuration.log_statements IS 'Which SQL statements to log';
COMMENT ON COLUMN pem.log_configuration.log_import IS 'Enable/Disable log data import to PEM server';
COMMENT ON COLUMN pem.log_configuration.log_import_frequency IS 'Log data import frequency';

CREATE TABLE pemdata.server_logs (
	id                              bigserial NOT NULL,
	server_id                       integer NOT NULL,
	log_time timestamp 		with time zone,
	user_name 			text,
	database_name 			text,
	process_id 			integer,
	connection_from 		text,
	session_id 			text,
	session_line_num 		bigint,
	command_tag 			text,
	session_start_time 		timestamp with time zone,
	virtual_transaction_id 		text,
	transaction_id 			bigint,
	error_severity 			text,
	sql_state_code 			text,
	message 			text,
	detail 				text,
	hint 				text,
	internal_query 			text,
	internal_query_pos 		integer,
	context 			text,
	query 				text,
	query_pos 			integer,
	location 			text,
	application_name 		text,
	CONSTRAINT server_logs_pkey PRIMARY KEY (id)
);

COMMENT ON TABLE pemdata.server_logs IS 'Server log data';
COMMENT ON COLUMN pemdata.server_logs.id IS 'Id for each record';
COMMENT ON COLUMN pemdata.server_logs.server_id IS 'Server id for which log data is collected';
COMMENT ON COLUMN pemdata.server_logs.log_time IS 'Time at which the statement got logged';
COMMENT ON COLUMN pemdata.server_logs.user_name IS 'User name which issued the statement';
COMMENT ON COLUMN pemdata.server_logs.database_name IS 'Database name on which the statement is executed';
COMMENT ON COLUMN pemdata.server_logs.process_id IS 'Process ID of the client';
COMMENT ON COLUMN pemdata.server_logs.connection_from IS 'Clients address and port';
COMMENT ON COLUMN pemdata.server_logs.session_id IS 'Session ID which contains the statement';
COMMENT ON COLUMN pemdata.server_logs.session_line_num IS '';
COMMENT ON COLUMN pemdata.server_logs.command_tag IS 'Type of statement';
COMMENT ON COLUMN pemdata.server_logs.session_start_time IS 'Time at which the session containing the statment started';
COMMENT ON COLUMN pemdata.server_logs.virtual_transaction_id IS 'Virtual transaction ID of the statement';
COMMENT ON COLUMN pemdata.server_logs.transaction_id IS 'Transaction ID of the statement';
COMMENT ON COLUMN pemdata.server_logs.error_severity IS 'Severity of the error (if any)';
COMMENT ON COLUMN pemdata.server_logs.sql_state_code IS 'SQL state code returned by the server';
COMMENT ON COLUMN pemdata.server_logs.message IS 'Message returned by the server for the statement';
COMMENT ON COLUMN pemdata.server_logs.detail IS '';
COMMENT ON COLUMN pemdata.server_logs.hint IS 'Any hint associated with the statement';
COMMENT ON COLUMN pemdata.server_logs.internal_query IS '';
COMMENT ON COLUMN pemdata.server_logs.internal_query_pos IS '';
COMMENT ON COLUMN pemdata.server_logs.context IS '';
COMMENT ON COLUMN pemdata.server_logs.query IS 'The query in the statement';
COMMENT ON COLUMN pemdata.server_logs.query_pos IS '';
COMMENT ON COLUMN pemdata.server_logs.location IS '';
COMMENT ON COLUMN pemdata.server_logs.application_name IS 'Application name which fires the statement';

GRANT USAGE ON SEQUENCE pemdata.server_logs_id_seq TO pem_agent;

INSERT INTO pem.server_version VALUES (10902, 'PostgreSQL 9.2');
INSERT INTO pem.server_version VALUES (20902, 'Advanced Server 9.2');

--
-- Probe: log_configuration
--
INSERT INTO pem.probe
        (display_name, internal_name, collection_method, target_type_id,
         agent_capability, enabled_by_default, force_enabled,
     default_execution_frequency, default_lifetime, any_server_version, probe_code)
VALUES
        ('Server log Configuration', 'log_configuration', 'i', 200, NULL, true, false, 1800,
          180, true, 'log_configuration');

INSERT INTO pem.probe_column
        (probe_id, internal_name, display_name, display_position, classification,
        sql_data_type, unit_of_value, calculate_pit, discard_history, pit_by_default, is_graphable)
SELECT
        (SELECT max(id) FROM pem.probe),
        v.internal_name, v.display_name, v.display_position, v.classification,
        v.sql_data_type, v.unit_of_value, v.calculate_pit, v.discard_history, v.pit_by_default, v.is_graphable
FROM
        (VALUES
                ('log_destination',  'Log Destination',  1, 'm', 'text', '', false, false, false, false),
                ('log_collector',  'Log Collector',  2, 'm', 'boolean', '', false, false, false, false),
                ('log_silent_mode',  'Log Silent Mode',  3, 'm', 'boolean', '', false, false, false, false),
                ('log_directory', 'Log Directory', 4, 'm', 'text', '', false, false, false, false),
                ('log_filename', 'Log Filename', 5, 'm', 'text', '', false, false, false, false),
                ('log_syslog_facility', 'Log syslog Facility', 6, 'm', 'text', '', false, false, false, false),
                ('log_syslog_ident', 'Log syslog Ident', 7, 'm', 'text', '', false, false, false, false),
                ('log_rotation_size', 'Log Rotation Size', 8, 'm', 'integer', '', false, false, false, false),
                ('log_rotation_time', 'Log Rotation Time', 9, 'm', 'integer', '', false, false, false, false),
                ('log_rotation_truncate', 'Log Rotation Truncate',  10, 'm', 'boolean', '', false, false, false, false),
                ('log_client_min_messages', 'Log Client Min Messages', 11, 'm', 'text', '', false, false, false, false),
                ('log_min_messages', 'Log Min Messages', 12, 'm', 'text', '', false, false, false, false),
                ('log_min_error_statement', 'Log Min Error Statement', 13, 'm', 'text', '', false, false, false, false),
                ('log_min_duration_statement', 'Log Min Duration Statement', 14, 'm', 'integer', '', false, false, false, false),
                ('log_parse_tree',  'Log Parse Tree',  15, 'm', 'boolean', '', false, false, false, false),
                ('log_rewriter_output',  'Log Rewriter Output',  16, 'm', 'boolean', '', false, false, false, false),
                ('log_exec_plan',  'Log Exec Plan',  17, 'm', 'boolean', '', false, false, false, false),
                ('log_indent_debug_output',  'Log Indent Debug Output',  18, 'm', 'boolean', '', false, false, false, false),
                ('log_checkpoints',  'Log Checkpoints',  19, 'm', 'boolean', '', false, false, false, false),
                ('log_connections',  'Log Checkpoints',  20, 'm', 'boolean', '', false, false, false, false),
                ('log_disconnections',  'Log Disconnections',  21, 'm', 'boolean', '', false, false, false, false),
                ('log_duration',  'Log Duration',  22, 'm', 'boolean', '', false, false, false, false),
                ('log_hostname',  'Log Hostname ',  23, 'm', 'boolean', '', false, false, false, false),
                ('log_lock_waits',  'Log Lock Waits',  24, 'm', 'boolean', '', false, false, false, false),
                ('log_error_verbosity', 'Log Error Verbosity', 25, 'm', 'text', '', false, false, false, false),
                ('log_prefix_string', 'Log Prefix String', 26, 'm', 'text', '', false, false, false, false),
                ('log_statements', 'Log Statements', 25, 'm', 'text', '', false, false, false, false)
        ) v(internal_name, display_name, display_position, classification,
                sql_data_type, unit_of_value, calculate_pit, discard_history, pit_by_default, is_graphable);

SELECT pem.create_data_and_history_tables();

SELECT pem.create_alert_template(
       'Log config mismatch',
       'Check for log config parameter mismatch',
       $sql$
SELECT
  CASE
    WHEN COUNT(r.result) <> 0 THEN MAX(r.result)
    ELSE -1
  END
FROM
  (SELECT
     CASE
	  WHEN(p.log_destination = pd.log_destination
		AND p.log_collector = pd.log_collector
		AND p.log_silent_mode = pd.log_silent_mode
		AND p.log_directory = pd.log_directory
		AND p.log_filename = pd.log_filename
		AND p.log_syslog_facility = pd.log_syslog_facility
		AND p.log_syslog_ident = pd.log_syslog_ident
		AND p.log_rotation_size = pd.log_rotation_size
		AND p.log_rotation_time = pd.log_rotation_time
		AND p.log_rotation_truncate = pd.log_rotation_truncate
		AND p.log_client_min_messages = pd.log_client_min_messages
		AND p.log_min_messages = pd.log_min_messages
		AND p.log_min_error_statement = pd.log_min_error_statement
		AND p.log_min_duration_statement = pd.log_min_duration_statement
		AND p.log_parse_tree = pd.log_parse_tree
		AND p.log_rewriter_output = pd.log_rewriter_output
		AND p.log_exec_plan = pd.log_exec_plan
		AND p.log_indent_debug_output = pd.log_indent_debug_output
		AND p.log_checkpoints = pd.log_checkpoints
		AND p.log_connections = pd.log_connections
		AND p.log_disconnections = pd.log_disconnections
		AND p.log_duration = pd.log_duration
		AND p.log_hostname = pd.log_hostname
		AND p.log_lock_waits = pd.log_lock_waits
		AND p.log_error_verbosity = pd.log_error_verbosity
		AND p.log_prefix_string = pd.log_prefix_string
		AND p.log_statements = pd.log_statements) OR (p.server_id IS NULL)
         THEN -1
       ELSE 1
     END AS result
   FROM
     pem.log_configuration p RIGHT JOIN
     pemdata.log_configuration pd ON (p.server_id = pd.server_id)
   WHERE p.server_id = ${server_id}) AS r $sql$,
       200, NULL, NULL, NULL, NULL,'{log_configuration}', 55, 'ALL');

INSERT INTO pem.config VALUES ('dash_os_process_span', 7, 'days', 'integer');
INSERT INTO pem.config VALUES ('dash_os_process_timeout', 1800, 'seconds', 'integer');
INSERT INTO pem.config VALUES ('dash_os_hostfs_timeout', 1800, 'seconds', 'integer');

-- Set config variables for help content
INSERT INTO pem.config (param, value, datatype) VALUES ('webclient_help_pg', 'http://www.enterprisedb.com/docs/en/9.2/pg/index.html', 'string');

CREATE OR REPLACE FUNCTION pem.json_escape(text)
  RETURNS text AS $$
SELECT replace(replace($1, E'\\', E'\\\\'), E'"', E'\\"')
$$ LANGUAGE sql IMMUTABLE;
GRANT EXECUTE ON FUNCTION pem.json_escape(text) TO public;
COMMENT ON FUNCTION pem.json_escape(text) IS 'Escapes a string for inclusion in a JSON document';

CREATE OR REPLACE FUNCTION pem.backend_minimum(majorversion integer, minorversion integer)
  RETURNS boolean AS
$$
DECLARE
    version varchar;
    version_arr varchar[3];
    major integer;
    minor integer;
BEGIN
    SELECT version() INTO version;
    version_arr := regexp_matches(version, '[PostgreSQL|EnterpriseDB] ([0-9]+).([0-9]+).*');
    major := version_arr[1]::integer;
    minor := version_arr[2]::integer;

    IF (major > majorversion OR
        (major = majorversion AND minor >= minorversion)) THEN
        return true;
    ELSE
        return false;
    END IF;
END;
$$
 LANGUAGE plpgsql VOLATILE;

CREATE OR REPLACE FUNCTION pem.clear_probe_zombies() RETURNS void AS $$
BEGIN
        IF pem.backend_minimum(9,2) THEN
            UPDATE pem.probe_schedule SET current_backend_pid = NULL
                WHERE current_backend_pid
                        NOT IN (SELECT pid FROM pg_catalog.pg_stat_activity);
        ELSE
            UPDATE pem.probe_schedule SET current_backend_pid = NULL
                WHERE current_backend_pid
                        NOT IN (SELECT procpid FROM pg_catalog.pg_stat_activity);
        END IF;
END
$$ LANGUAGE plpgsql;

INSERT INTO pem.probe_server_version
    (probe_id, server_version_id, probe_code)
SELECT
       (SELECT id FROM pem.probe WHERE internal_name = 'session_info'),
       v.version,
    'SELECT datname AS database_name, pid AS procpid, usename, client_addr, client_port, backend_start, xact_start, query_start,'
                ' waiting AS is_waiting, query = $$<IDLE>$$ AS is_idle,'
                ' query = $$<IDLE> in transaction$$ AS is_idle_in_transaction,'
                ' query like $$VACUUM%$$ as is_vacuum,'
                ' client_port IS NULL AND (query like $$autovacuum:%$$ OR query like $$VACUUM%$$) as is_autovacuum,'
                ' now() AS capture_time'
        ' FROM pg_catalog.pg_stat_activity'
FROM
       (VALUES (10902), (20902)) v(version);

INSERT INTO pem.probe_server_version
    (probe_id, server_version_id, probe_code)
SELECT
       (SELECT id FROM pem.probe WHERE internal_name = 'session_waits'),
       v.version,
        'SELECT sw.backend_id, psa.datname AS dbname, psa.usename, sw.wait_name, sw.wait_count, avg_wait_time, max_wait_time, total_wait_time '
	    'FROM session_waits sw, pg_stat_activity psa WHERE sw.backend_id = psa.pid'
FROM
       (VALUES (20902)) v(version);

INSERT INTO pem.probe_server_version
    (probe_id, server_version_id, probe_code)
SELECT
       (SELECT id FROM pem.probe WHERE internal_name = 'lock_info'),
       v.version, $sql$
SELECT COALESCE(d.datname, '')                 AS database_name,
               COALESCE(l.pid::bigint, -1)             AS procpid,
               l.relation::text::numeric               AS objid,               -- relation/XID/VXID/classid
               COALESCE(l.page::bigint, -1)    AS objsubid,    -- page/objid
               COALESCE(l.tuple::bigint, -1)   AS objsubsubid, -- tuple/objsubid
               l.locktype, l.mode AS lockmode, l.granted AS lockgranted
FROM   pg_catalog.pg_locks AS l
LEFT JOIN      pg_catalog.pg_stat_activity AS sa
ON             l.pid = sa.pid
JOIN   pg_catalog.pg_database AS d
ON             sa.datid = d.oid
WHERE  l.locktype IN ('relation', 'extend', 'page', 'tuple')
UNION ALL
SELECT COALESCE(d.datname, '')         AS database_name,
               COALESCE(l.pid::bigint, -1)     AS procpid,
               transactionid::text::numeric    AS objid,       -- relation/XID/VXID/classid
               -1                                                      AS objsubid,    -- page/objid
               -1                                                      AS objsubsubid, -- tuple/objsubid
               l.locktype, l.mode AS lockmode, l.granted AS lockgranted
FROM   pg_catalog.pg_locks AS l
LEFT JOIN      pg_catalog.pg_stat_activity AS sa
ON             l.pid = sa.pid
JOIN   pg_catalog.pg_database AS d
ON             sa.datid = d.oid
WHERE  l.locktype = 'transactionid'
UNION ALL
SELECT COALESCE(d.datname, '')                         AS database_name,
               COALESCE(l.pid::bigint, -1)                     AS procpid,
               regexp_replace(l.virtualxid, '/', '.')::numeric AS objid,-- relation/XID/VXID/classid
               -1                                                                      AS objsubid,    -- page/objid
               -1                                                                      AS objsubsubid, -- tuple/objsubid
               l.locktype, l.mode AS lockmode, l.granted AS lockgranted
FROM   pg_catalog.pg_locks AS l
LEFT JOIN      pg_catalog.pg_stat_activity AS sa
ON             l.pid = sa.pid
JOIN   pg_catalog.pg_database AS d
ON             sa.datid = d.oid
WHERE  l.locktype = 'virtualxid'
UNION ALL
SELECT COALESCE(d.datname, '')                 AS database_name,
               COALESCE(l.pid::bigint, -1)             AS procpid,
               classid::text::numeric                  AS objid,-- relation/XID/VXID/classid
               COALESCE(l.objid::bigint, -1)   AS objsubid,    -- page/objid
               COALESCE(l.objsubid::bigint, -1)AS objsubsubid, -- tuple/objsubid
               l.locktype, l.mode AS lockmode, l.granted AS lockgranted
FROM   pg_catalog.pg_locks AS l
LEFT JOIN      pg_catalog.pg_stat_activity AS sa
ON             l.pid = sa.pid
JOIN   pg_catalog.pg_database AS d
ON             sa.datid = d.oid
WHERE  l.locktype IN ('object', 'advisory')$sql$
FROM
       (VALUES (10902), (20902) ) v(version);

ALTER TABLE pem.probe_column DROP CONSTRAINT column_type_for_pit;
ALTER TABLE pem.probe_column ADD CONSTRAINT column_type_for_pit CHECK (NOT calculate_pit OR sql_data_type IN ('bigint', 'integer', 'numeric', 'decimal', 'real', 'double precision'));

UPDATE pem.probe_column SET sql_data_type = 'double precision'
    WHERE  pem.probe_column.internal_name IN ('self_time', 'total_time')
    AND pem.probe_column.probe_id = (SELECT id FROM pem.probe WHERE pem.probe.internal_name = 'function_statistics');

ALTER TABLE pemdata.function_statistics ALTER COLUMN self_time TYPE double precision;
ALTER TABLE pemdata.function_statistics ALTER COLUMN total_time TYPE double precision;
ALTER TABLE pemhistory.function_statistics ALTER COLUMN self_time TYPE double precision;
ALTER TABLE pemhistory.function_statistics ALTER COLUMN total_time TYPE double precision;

INSERT INTO pem.probe_server_version
    (probe_id, server_version_id, probe_code)
SELECT
       (SELECT id FROM pem.probe WHERE internal_name = 'database_statistics'),
       v.version,
     'SELECT d1.datname AS database_name, d1.numbackends,
            (SELECT COALESCE(count(query)::bigint, 0::bigint) FROM pg_catalog.pg_stat_activity WHERE datname = d1.datname AND query = ''<IDLE>'') AS idle_backends,
           d1.xact_commit, d1.xact_rollback, d1.blks_hit, NULL::bigint AS blks_icache_hit, d1.blks_read,
            d1.tup_returned, d1.tup_fetched, d1.tup_inserted, d1.tup_updated, d1.tup_deleted
      FROM pg_catalog.pg_stat_database d1'
FROM
       (VALUES (10902)) v(version);

INSERT INTO pem.probe_server_version
    (probe_id, server_version_id, probe_code)
SELECT
       (SELECT id FROM pem.probe WHERE internal_name = 'database_statistics'),
       v.version,
    'SELECT d1.datname AS database_name, d1.numbackends,
            (SELECT COALESCE(count(query)::bigint, 0::bigint) FROM pg_catalog.pg_stat_activity WHERE datname = d1.datname AND query = ''<IDLE>'') AS idle_backends,
            d1.xact_commit, d1.xact_rollback, d1.blks_hit, d1.blks_icache_hit, d1.blks_read, d1.tup_returned,
            d1.tup_fetched, d1.tup_inserted, d1.tup_updated, d1.tup_deleted
     FROM pg_catalog.pg_stat_database d1'
FROM
       (VALUES (20902)) v(version);

COMMIT TRANSACTION;
