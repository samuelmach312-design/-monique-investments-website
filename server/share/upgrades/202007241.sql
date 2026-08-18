/***************************************************************************
 *
 * Postgres Enterprise Manager
 *
 * Copyright (C) 2010 - 2025, EnterpriseDB Corporation. All rights reserved.
 *
 ***************************************************************************/

-- NOTE: This sql file is responsible for PEM 7.16 schema upgrade.

BEGIN TRANSACTION;

CREATE OR REPLACE FUNCTION pem.schema_version() RETURNS integer AS
'SELECT 202007241::integer;'
LANGUAGE 'sql' IMMUTABLE;
COMMENT ON FUNCTION pem.schema_version()
	IS 'Returns the version number of the PEM schema';

-- Function unit_converter(text, text) which convert value
-- of one type to another. It is used on Alert details and Alert status
-- dashboard to display units with alert values.
CREATE OR REPLACE FUNCTION pem.unit_converter(val numeric, unit text)
RETURNS text AS $$
DECLARE
	temp_unit text:= '';
	temp_val text;
BEGIN

	IF unit IS NULL OR unit = '#' THEN
		RETURN TRIM(trailing '0' FROM ROUND(val::decimal, 2)::text)::numeric;
	END IF;

	unit := TRIM(unit);
	IF unit = 'STATE' THEN
		RETURN CASE val WHEN 1 THEN 'UP' WHEN 0 THEN 'DOWN' ELSE 'UNKNOWN ' || val::text END;
	END IF;

	IF unit = '%' THEN
		val = ROUND(val::decimal, 2);
		RETURN TRIM(trailing '0' FROM val::text)::numeric || unit;
	END IF;

	temp_val = val::decimal(30, 2);
	IF UPPER(unit) = 'KB' THEN
		-- Convert value to MB OR GB
		IF (val::decimal / 1024::decimal) >= 1.00 THEN
			val = val::decimal / 1024::decimal;
			IF (val::decimal / 1024::decimal) >= 1.00 THEN
				temp_unit = ' GB';
				temp_val = ROUND(val::decimal / 1024::decimal, 3)::text;
			ELSE
				temp_unit = ' MB';
				temp_val = ROUND(val::decimal, 3)::text;
			END IF;

		ELSE
			temp_unit = ' KB';
			temp_val = ROUND(val::decimal, 3)::text;
		END IF;
	END IF;

	IF UPPER(unit) = 'MB' THEN
		-- Convert value to GB
		IF (val::decimal / 1024::decimal) >= 1.00 THEN
			temp_unit = ' GB';
			temp_val = ROUND(val::decimal / 1024::decimal, 3)::text;
		ELSE
			temp_unit = ' MB';
			temp_val = ROUND(val::decimal, 3)::text;
		END IF;
	END IF;

	IF UPPER(unit) = 'GB' THEN
		temp_unit = ' GB';
		temp_val = ROUND(val::decimal, 3)::text;
	END IF;

	IF UPPER(unit) = 'HOURS' THEN
		temp_unit = ' hrs';
		temp_val = ROUND(val::decimal, 3)::text;
	END IF;


	IF UPPER(unit) = 'MINUTES' THEN
		temp_unit = ' mins';
		temp_val = ROUND(val::decimal, 3)::text;
	END IF;

	IF UPPER(unit) = 'DAYS' THEN
		temp_unit = ' days';
		temp_val = ROUND(val::decimal, 3)::text;
	END IF;

	RETURN TRIM(trailing '0' FROM temp_val)::numeric || temp_unit;
END
$$ LANGUAGE plpgsql;

/*
-- This method returns the up and down time of specified agent with in
-- given time interval (Start and End time)
--
-- RETURNS table
--
-- Parameters:
--
-- p_agent_id		      : Agent ID.
-- p_start_datetime	      : Start time.
-- p_end_datetime	      : End time.
*/

CREATE OR REPLACE FUNCTION pem.agent_down_status(p_agent_id int, p_start_datetime timestamptz, p_end_datetime timestamptz)
RETURNS TABLE(o_down_datetime timestamptz, o_up_datetime timestamptz)
AS $$
DECLARE
	v_alert_id  integer;
	v_curr_rec  record;
	v_prev_state pem.alert_state := NULL;
BEGIN
	SELECT id INTO v_alert_id FROM pem.alert WHERE agent_id = p_agent_id and template_id = (SELECT id FROM pem.alert_template WHERE display_name = 'Agent Down' AND is_system_template);
	o_down_datetime := NULL;
	o_up_datetime := NULL;

	FOR v_curr_rec IN EXECUTE '
SELECT
	state, generated as recorded_time
FROM
	pem.alert_history
WHERE
	alert_id = $1::integer AND generated >= $2::timestamptz AND
	generated <= $3::timestamptz
ORDER BY generated;' USING v_alert_id, p_start_datetime, p_end_datetime
	LOOP
		IF v_curr_rec.state IS NOT NULL THEN
			IF v_prev_state IS NULL THEN
				o_down_datetime := v_curr_rec.recorded_time;
			END IF;
		ELSE
			IF v_prev_state IS NOT NULL THEN
				o_up_datetime := v_curr_rec.recorded_time;
			ELSE
				o_down_datetime := p_start_datetime;
				o_up_datetime := v_curr_rec.recorded_time;
			END IF;
			RETURN NEXT;
			o_down_datetime := NULL;
			o_up_datetime := NULL;
		END IF;
		v_prev_state := v_curr_rec.state;
	END LOOP;

	IF o_down_datetime IS NOT NULL THEN
		o_up_datetime := p_end_datetime;
		RETURN NEXT;
	END IF;
END
$$ LANGUAGE 'plpgsql';

/*
-- This method returns the up and down time of specified server with in
-- given time interval (Start and End time)
--
-- RETURNS table
--
-- Parameters:
--
-- p_server_id		      : Server ID.
-- p_start_datetime	      : Start time.
-- p_end_datetime	      : End time.
*/

CREATE OR REPLACE FUNCTION pem.server_down_status(p_server_id int, p_start_datetime timestamptz, p_end_datetime timestamptz)
RETURNS TABLE(o_down_datetime timestamptz, o_up_datetime timestamptz)
AS $$
DECLARE
	v_alert_id  integer;
	v_curr_rec  record;
	v_prev_state pem.alert_state := NULL;
BEGIN
	SELECT id INTO v_alert_id FROM pem.alert
	WHERE server_id = p_server_id and template_id = (
		SELECT id FROM pem.alert_template
		WHERE display_name = 'Server Down' AND is_system_template
	);
	o_down_datetime := NULL;
	o_up_datetime := NULL;

	FOR v_curr_rec IN EXECUTE '
SELECT
	state, generated as recorded_time
FROM
	pem.alert_history
WHERE
	alert_id = $1::integer AND generated >= $2::timestamptz AND
	generated <= $3::timestamptz
ORDER BY generated;' USING v_alert_id, p_start_datetime, p_end_datetime
	LOOP
		IF v_curr_rec.state IS NOT NULL THEN
			IF v_prev_state IS NULL THEN
				o_down_datetime := v_curr_rec.recorded_time;
			END IF;
		ELSE
			IF v_prev_state IS NOT NULL THEN
				o_up_datetime := v_curr_rec.recorded_time;
			ELSE
				o_down_datetime := p_start_datetime;
				o_up_datetime := v_curr_rec.recorded_time;
			END IF;
			RETURN NEXT;
			o_down_datetime := NULL;
			o_up_datetime := NULL;
		END IF;
		v_prev_state := v_curr_rec.state;
	END LOOP;

	IF o_down_datetime IS NOT NULL THEN
		o_up_datetime := p_end_datetime;
		RETURN NEXT;
	END IF;
END
$$ LANGUAGE 'plpgsql';

UPDATE pem.alert_template
SET threshold_unit = 'STATE', sql = $SQL$
SELECT
	count(pa.id) AS current_value,
	CASE WHEN count(pa.id) = 0 THEN 'UP' ELSE 'DOWN' END display_value
FROM
	pem.agent pa LEFT OUTER JOIN pem.agent_heartbeat pah ON (pa.id = pah.agent_id)
WHERE
	pa.id = ${agent_id} AND
	pa.active = TRUE AND
	NOT pa.alert_blackout AND
	CASE WHEN pah.agent_id IS NULL THEN FALSE
	ELSE pah.last_heartbeat < (
		now() - (pa.heartbeat_interval) * 2 * '1 second'::interval
	)
	END$SQL$
WHERE display_name = 'Agent Down' AND is_system_template;

UPDATE pem.alert_template
SET threshold_unit = 'STATE', sql = $SQL$
SELECT
	count(ps.id),
	CASE WHEN count(pa.id) = 0 THEN 'UP' ELSE 'DOWN' END display_value
FROM
	pem.server ps LEFT OUTER JOIN pem.server_heartbeat psh ON (ps.id = psh.server_id),
	pem.agent pa LEFT OUTER JOIN pem.agent_heartbeat pah ON (pa.id = pah.agent_id),
	pem.agent_server_binding pasb
WHERE
	ps.id = ${server_id} AND
	pa.id = pasb.agent_id AND
	ps.id = pasb.server_id AND
	pa.active = TRUE AND
	ps.active = TRUE AND
	NOT ps.alert_blackout AND
	CASE WHEN psh.agent_id IS NULL THEN FALSE ELSE psh.agent_id = pa.id END AND
	CASE WHEN pah.agent_id is NULL THEN FALSE
	ELSE pah.last_heartbeat > (
		now() - (pa.heartbeat_interval) * 2 * '1 second'::interval
	) END AND
	CASE WHEN psh.server_id IS NULL THEN FALSE
	ELSE psh.last_heartbeat < (
		now() - (pa.heartbeat_interval) * 2 * '1 second'::interval
	) END$SQL$
WHERE display_name = 'Server Down' AND is_system_template;

DO $$
BEGIN
	IF NOT EXISTS(
		SELECT * FROM pg_catalog.pg_attribute
		LEFT JOIN pg_catalog.pg_class c ON attrelid = c.oid
		LEFT JOIN pg_catalog.pg_namespace n ON c.relnamespace = n.oid
		WHERE attname = 'display_value' AND relname = 'alert_history' AND
			n.nspname = 'pem'
	) THEN
		ALTER TABLE pem.alert_history ADD COLUMN display_value text;
	END IF;
END
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION pem.log_alert_history() RETURNS TRIGGER AS $$
BEGIN
	/*
	 * We log history only when the state really changes; and avoid history for
	 * last_processed updates.
	 */
	IF (TG_OP = 'INSERT' AND NEW.current_state IS NOT NULL)
		OR (TG_OP = 'UPDATE'
			AND NEW.current_state IS DISTINCT FROM OLD.current_state)
	THEN
		INSERT INTO pem.alert_history(alert_id, value, state, display_value)
		VALUES(
			NEW.alert_id, NEW.current_value, NEW.current_state, NEW.display_value
		);
	END IF;

	RETURN new;
END;
$$ LANGUAGE plpgsql;

DO $$
BEGIN
	IF NOT EXISTS(
		SELECT * FROM pg_catalog.pg_attribute
		LEFT JOIN pg_catalog.pg_class c ON attrelid = c.oid
		LEFT JOIN pg_catalog.pg_namespace n ON c.relnamespace = n.oid
		WHERE attname = 'reference_id' AND relname = 'probe' AND
			n.nspname = 'pem'
	) THEN
		RAISE INFO '--- Adding new column reference_id in pem.probe table';
		ALTER TABLE pem.probe ADD COLUMN reference_id text;

		RAISE INFO '--- Updating the reference_id of the existing probes';
		UPDATE pem.probe
		SET reference_id = CASE
			WHEN is_system_probe THEN internal_name
			ELSE md5(
				internal_name || random()::text || clock_timestamp()::text
			)::uuid::text
			END;

		ALTER TABLE pem.probe ALTER COLUMN reference_id SET NOT NULL;
	END IF;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION pem.probe_preupdate() RETURNS trigger AS $$
BEGIN
	NEW.applies_to_id := pem.probe_applies_to(
		NEW.target_type_id,	NEW.probe_key_list
	);
	-- Override the reference_name.
	-- It will same as internal_name for system proebs, but - user defined probes
	-- will use a UUID generated based on creation time.
	--
	-- It can be used to refer the importing & exporting probes.
	IF TG_OP = 'INSERT' THEN
		IF NEW.is_system_probe THEN
			NEW.reference_id := NEW.internal_name;
		ELSE
			NEW.reference_id := md5(
				NEW.internal_name || random()::text || clock_timestamp()::text
			)::uuid::text;
		END IF;
	END IF;
	RETURN NEW;
END
$$ LANGUAGE plpgsql;

DO $$
BEGIN
	IF NOT EXISTS(
		SELECT * FROM pg_catalog.pg_attribute
		LEFT JOIN pg_catalog.pg_class c ON attrelid = c.oid
		LEFT JOIN pg_catalog.pg_namespace n ON c.relnamespace = n.oid
		WHERE attname = 'reference_id' AND relname = 'alert_template' AND
			n.nspname = 'pem'
	) THEN
		RAISE INFO
			'--- Adding new column reference_id in pem.alert_template table';
		ALTER TABLE pem.alert_template ADD COLUMN reference_id text;

		RAISE INFO '--- Updating the reference_id of the existing alert templates';
		UPDATE pem.alert_template
		SET reference_id = CASE
			WHEN is_system_template THEN object_type || '|' || display_name
			ELSE md5(
				id || random()::text || clock_timestamp()::text
			)::uuid::text
			END;

		ALTER TABLE pem.alert_template ALTER COLUMN reference_id SET NOT NULL;
	END IF;
END;
$$ LANGUAGE plpgsql;

-- Function to create new the reference-id
CREATE OR REPLACE FUNCTION pem.update_alert_template_reference_id()
RETURNS trigger AS $$
BEGIN
	IF NEW.is_system_template THEN
		NEW.reference_id := NEW.object_type || '|' || NEW.display_name;
	ELSE
		NEW.reference_id := md5(
			NEW.id || random()::text || clock_timestamp()::text
		)::uuid::text;
	END IF;
	RETURN NEW;
END
$$ LANGUAGE plpgsql;

DO $DO$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_trigger
                   WHERE  NOT tgisinternal
                   AND tgname = 'alert_template_reference_id'
                   AND tgrelid = 'pem.alert_template'::regclass) THEN
        CREATE TRIGGER alert_template_reference_id
                BEFORE INSERT ON pem.alert_template
                FOR EACH ROW
                EXECUTE PROCEDURE pem.update_alert_template_reference_id();
    END IF;
END;
$DO$ LANGUAGE 'plpgsql';

-- JIRA PEM-3402 added support of audit and log manager for PG/AS 13
-- Adding new column to store backend_type parameter in server_logs
-- Adding new columns to store backend_type, type parameters in audit_logs

DO $DO$
BEGIN
    IF NOT EXISTS (SELECT 1
                   FROM pg_attribute
                   WHERE attrelid = (SELECT oid FROM pg_class WHERE relname = 'server_logs' and relnamespace = (SELECT oid FROM pg_namespace WHERE nspname = 'pemdata'))
                   AND attname = 'backend_type') THEN
                   ALTER TABLE pemdata.server_logs ADD COLUMN backend_type text DEFAULT '';
    END IF;

	IF NOT EXISTS (SELECT 1
                   FROM pg_attribute
                   WHERE attrelid = (SELECT oid FROM pg_class WHERE relname = 'audit_logs' and relnamespace = (SELECT oid FROM pg_namespace WHERE nspname = 'pemdata'))
                   AND attname = 'backend_type') THEN
                   ALTER TABLE pemdata.audit_logs ADD COLUMN backend_type text DEFAULT '';
    END IF;

	IF NOT EXISTS (SELECT 1
                   FROM pg_attribute
                   WHERE attrelid = (SELECT oid FROM pg_class WHERE relname = 'audit_logs' and relnamespace = (SELECT oid FROM pg_namespace WHERE nspname = 'pemdata'))
                   AND attname = 'type') THEN
                   ALTER TABLE pemdata.audit_logs ADD COLUMN type text DEFAULT '';
    END IF;
END;
$DO$ LANGUAGE 'plpgsql';

-- PEM-3054 Adding is_scanner_running flag to manage bart-scanner from PEM UI

DO $DO$
BEGIN
    IF NOT EXISTS (SELECT 1
                   FROM pg_attribute
                   WHERE attrelid = (SELECT oid FROM pg_class WHERE relname = 'bart' and relnamespace = (SELECT oid FROM pg_namespace WHERE nspname = 'pem'))
                   AND attname = 'is_scanner_running') THEN
                   ALTER TABLE pem.bart ADD COLUMN is_scanner_running boolean DEFAULT true;
    END IF;
END;

$DO$ LANGUAGE 'plpgsql';
-- Fix the issues for PEM-2579
-- 1) Updated the datatype for status and previousStatus
-- 2) Fixed validation issues
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
		OBJECT-GROUP, NOTIFICATION-GROUP
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

    tableObjectAlerts   OBJECT IDENTIFIER ::=  {  pem  5  }

    indexObjectAlerts   OBJECT IDENTIFIER ::=  {  pem  6  }

    sequenceObjectAlerts    OBJECT IDENTIFIER ::=  {  pem  7  }

    functionObjectAlerts    OBJECT IDENTIFIER ::=  {  pem  8  }

	globalAlerts	OBJECT IDENTIFIER ::=  {  pem  9  }

	bindingVariables	OBJECT IDENTIFIER ::=  {  pem  10  }

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
			downObjects,
			detailedInformation}
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
		DESCRIPTION		"This parameter gives the previous value of the alert"
		::=  {  bindingVariables  10  }

	value	OBJECT-TYPE
		SYNTAX			DisplayString
		MAX-ACCESS		read-only
		STATUS			current
		DESCRIPTION		"This parameter gives the current value of the alert"
		::=  {  bindingVariables  11  }

	previousStatus	OBJECT-TYPE
		SYNTAX			DisplayString
		MAX-ACCESS		read-only
		STATUS			current
		DESCRIPTION		"This parameter gives the previous status of the alert"
		::=  {  bindingVariables  12  }

	status	OBJECT-TYPE
		SYNTAX			DisplayString
		MAX-ACCESS		read-only
		STATUS			current
		DESCRIPTION		"This parameter gives the current status of the alert"
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
		::=  {  bindingVariables  15  }

	detailedInformation		OBJECT-TYPE
		SYNTAX			DisplayString
		MAX-ACCESS		read-only
		STATUS			current
		DESCRIPTION		"This parameter displays the detailed information of the alert"
		::=  {  bindingVariables  16  }';

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
		object_string = '{ alertName, thresholdValue, previousValue, value, previousStatus, status, recordedTime, downObjects, detailedInformation }';
		object_prefix = 'gl';
		group_text = E'\n\n\tpemGlobalNotificationGroup  NOTIFICATION-GROUP
	\tNOTIFICATIONS {';
		group_description = 'This group contains the global notification types';
	WHEN object_type = 100 THEN
		where_clause = 'WHERE object_type = 100 AND snmp_oid > 0';
		parent_node = 'agentAlerts';
		object_string = '{ alertName, agentID , agentName, thresholdValue, previousValue, value, previousStatus, status, recordedTime, detailedInformation }';
		object_prefix = 'ag';
		group_text = E'\n\n\tpemAgentNotificationGroup  NOTIFICATION-GROUP
	\tNOTIFICATIONS {';
		group_description = 'This group contains the agent level notification types';
	WHEN object_type = 200 THEN
		where_clause = 'WHERE object_type = 200 AND snmp_oid > 0';
		parent_node = 'serverAlerts';
		object_string = '{ alertName, serverID , serverName, thresholdValue, previousValue, value, previousStatus, status, recordedTime, detailedInformation }';
		object_prefix = 'sr';
		group_text = E'\n\n\tpemServerNotificationGroup  NOTIFICATION-GROUP
	\tNOTIFICATIONS {';
		group_description = 'This group contains the server level notification types';
	WHEN object_type = 300 THEN
		where_clause = 'WHERE object_type = 300 AND snmp_oid > 0';
		parent_node = 'databaseAlerts';
		object_string = '{ alertName, serverID , serverName, databaseName, thresholdValue, previousValue, value, previousStatus, status, recordedTime, detailedInformation }';
		object_prefix = 'db';
		group_text = E'\n\n\tpemDatabaseNotificationGroup  NOTIFICATION-GROUP
	\tNOTIFICATIONS {';
		group_description = 'This group contains the database level notification types';
	WHEN object_type = 400 THEN
		where_clause = 'WHERE object_type = 400 AND snmp_oid > 0';
		parent_node = 'schemaAlerts';
		object_string = '{ alertName, serverID , serverName, databaseName, schemaName, thresholdValue, previousValue, value, previousStatus, status, recordedTime, detailedInformation }';
		object_prefix = 'sc';
		group_text = E'\n\n\tpemSchemaNotificationGroup  NOTIFICATION-GROUP
	\tNOTIFICATIONS {';
		group_description = 'This group contains the schema level notification types';
	WHEN object_type = 500 THEN
		where_clause = 'WHERE object_type = 500 AND snmp_oid > 0';
		parent_node = 'tableObjectAlerts';
		object_string = '{ alertName, serverID , serverName, databaseName, schemaName, objectName, thresholdValue, previousValue, value, previousStatus, status, recordedTime, detailedInformation }';
		object_prefix = 'tb';
		group_text = E'\n\n\tpemTableNotificationGroup  NOTIFICATION-GROUP
	\tNOTIFICATIONS {';
		group_description = 'This group contains the table level notification types';
	WHEN object_type = 600 THEN
		where_clause = 'WHERE object_type = 600 AND snmp_oid > 0';
		parent_node = 'indexObjectAlerts';
		object_string = '{ alertName, serverID , serverName, databaseName, schemaName, objectName, thresholdValue, previousValue, value, previousStatus, status, recordedTime, detailedInformation }';
		object_prefix = 'in';
		group_text = E'\n\n\tpemIndexNotificationGroup  NOTIFICATION-GROUP
	\tNOTIFICATIONS {';
		group_description = 'This group contains the index level notification types';
	WHEN object_type = 700 THEN
		where_clause = 'WHERE object_type = 700 AND snmp_oid > 0';
		parent_node = 'sequenceObjectAlerts';
		object_string = '{ alertName, serverID , serverName, databaseName, schemaName, objectName, thresholdValue, previousValue, value, previousStatus, status, recordedTime, detailedInformation }';
		object_prefix = 'se';
		group_text = E'\n\n\tpemSequenceNotificationGroup  NOTIFICATION-GROUP
	\tNOTIFICATIONS {';
		group_description = 'This group contains the sequence level notification types';
	WHEN object_type = 800 THEN
		where_clause = 'WHERE object_type = 800 AND snmp_oid > 0';
		parent_node = 'functionObjectAlerts';
		object_string = '{ alertName, serverID , serverName, databaseName, schemaName, objectName, thresholdValue, previousValue, value, previousStatus, status, recordedTime, detailedInformation }';
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

		tmp_rec.description = replace(tmp_rec.description, '"', '');

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
		snmp_trap_oid = snmp_enterprise_oid || '.9.' || alert_snmp_oid;
		snmp_varbinding_oid = snmp_enterprise_oid || '.10.1|' || snmp_enterprise_oid || '.10.9|' || snmp_enterprise_oid || '.10.10|' || snmp_enterprise_oid || '.10.11|'
							|| snmp_enterprise_oid || '.10.12|' || snmp_enterprise_oid || '.10.13|' || snmp_enterprise_oid || '.10.14';
		snmp_varbinding_value = alert_name || '|' || alert_thresholdvalue;
	WHEN alert_object_type = 100 THEN
		snmp_trap_oid = snmp_enterprise_oid || '.1.' || alert_snmp_oid;
		snmp_varbinding_oid = snmp_enterprise_oid || '.10.1|' || snmp_enterprise_oid || '.10.2|' || snmp_enterprise_oid || '.10.4|' || snmp_enterprise_oid ||
							'.10.9|' || snmp_enterprise_oid || '.10.10|' || snmp_enterprise_oid || '.10.11|' || snmp_enterprise_oid ||
							'.10.12|' || snmp_enterprise_oid || '.10.13|' || snmp_enterprise_oid || '.10.14';
		snmp_varbinding_value = alert_name || '|' || alert_agent_id || '|' || agent_name || '|' || alert_thresholdvalue;
	WHEN alert_object_type = 200 THEN
		snmp_trap_oid = snmp_enterprise_oid || '.2.' || alert_snmp_oid;
		snmp_varbinding_oid = snmp_enterprise_oid || '.10.1|' || snmp_enterprise_oid || '.10.3|' || snmp_enterprise_oid || '.10.5|' || snmp_enterprise_oid ||
							'.10.9|' || snmp_enterprise_oid || '.10.10|' || snmp_enterprise_oid || '.10.11|' || snmp_enterprise_oid ||
							'.10.12|' || snmp_enterprise_oid || '.10.13|' || snmp_enterprise_oid || '.10.14';
		snmp_varbinding_value = alert_name || '|' || alert_server_id || '|' || server_name || ' ('|| server_ip ||': ' || server_port || ')|'
							|| alert_thresholdvalue;
	WHEN alert_object_type = 300 THEN
		snmp_trap_oid = snmp_enterprise_oid || '.3.' || alert_snmp_oid;
		snmp_varbinding_oid = snmp_enterprise_oid || '.10.1|' || snmp_enterprise_oid || '.10.3|' || snmp_enterprise_oid || '.10.5|' || snmp_enterprise_oid ||
							'.10.6|' || snmp_enterprise_oid || '.10.9|' || snmp_enterprise_oid || '.10.10|' || snmp_enterprise_oid ||
							'.10.11|'|| snmp_enterprise_oid || '.10.12|' || snmp_enterprise_oid || '.10.13|' || snmp_enterprise_oid || '.10.14';
		snmp_varbinding_value = alert_name || '|' || alert_server_id || '|' || server_name || ' ('|| server_ip ||': ' || server_port || ')|' ||
							alert_database_name || '|' || alert_thresholdvalue;
	WHEN alert_object_type = 400 THEN
		snmp_trap_oid = snmp_enterprise_oid || '.4.' || alert_snmp_oid;
		snmp_varbinding_oid = snmp_enterprise_oid || '.10.1|' || snmp_enterprise_oid || '.10.3|' || snmp_enterprise_oid || '.10.5|' || snmp_enterprise_oid ||
							'.10.6|' || snmp_enterprise_oid || '.10.7|' || snmp_enterprise_oid || '.10.9|' || snmp_enterprise_oid ||
							'.10.10|' || snmp_enterprise_oid || '.10.11|'|| snmp_enterprise_oid || '.10.12|' || snmp_enterprise_oid ||
							'.10.13|'  ||snmp_enterprise_oid || '.10.14';
		snmp_varbinding_value = alert_name || '|' || alert_server_id || '|' || server_name || ' ('|| server_ip ||': ' || server_port || ')|' ||
							 alert_database_name || '|' || alert_schema_name || '|' || alert_thresholdvalue;
	WHEN alert_object_type = 500 THEN
		snmp_trap_oid = snmp_enterprise_oid || '.5.' || alert_snmp_oid;
		snmp_varbinding_oid = snmp_enterprise_oid || '.10.1|' || snmp_enterprise_oid || '.10.3|' || snmp_enterprise_oid || '.10.5|' || snmp_enterprise_oid ||
							'.10.6|' || snmp_enterprise_oid || '.10.7|' || snmp_enterprise_oid || '.10.8|' || snmp_enterprise_oid ||
							'.10.9|' || snmp_enterprise_oid || '.10.10|'|| snmp_enterprise_oid || '.10.11|' || snmp_enterprise_oid ||
							'.10.12|'|| snmp_enterprise_oid || '.10.13|' || snmp_enterprise_oid || '.10.14';
		snmp_varbinding_value = alert_name || '|' || alert_server_id || '|' || server_name || ' ('|| server_ip ||': ' || server_port || ')|' ||
							 alert_database_name || '|' || alert_schema_name || '|' || alert_object_name || '|' ||
							 alert_thresholdvalue;
	WHEN alert_object_type = 600 THEN
		snmp_trap_oid = snmp_enterprise_oid || '.6.' || alert_snmp_oid;
		snmp_varbinding_oid = snmp_enterprise_oid || '.10.1|' || snmp_enterprise_oid || '.10.3|' || snmp_enterprise_oid || '.10.5|' || snmp_enterprise_oid ||
							'.10.6|' || snmp_enterprise_oid || '.10.7|' || snmp_enterprise_oid || '.10.8|' || snmp_enterprise_oid ||
							'.10.9|' || snmp_enterprise_oid || '.10.10|'|| snmp_enterprise_oid || '.10.11|' || snmp_enterprise_oid ||
							'.10.12|'|| snmp_enterprise_oid || '.10.13|' || snmp_enterprise_oid || '.10.14';
		snmp_varbinding_value = alert_name || '|' || alert_server_id || '|' || server_name || ' ('|| server_ip ||': ' || server_port || ')|' ||
							 alert_database_name || '|' || alert_schema_name || '|' || alert_object_name || '|' ||
							 alert_thresholdvalue;
	WHEN alert_object_type = 700 THEN
		snmp_trap_oid = snmp_enterprise_oid || '.7.' || alert_snmp_oid;
		snmp_varbinding_oid = snmp_enterprise_oid || '.10.1|' || snmp_enterprise_oid || '.10.3|' || snmp_enterprise_oid || '.10.5|' || snmp_enterprise_oid ||
							'.10.6|' || snmp_enterprise_oid || '.10.7|' || snmp_enterprise_oid || '.10.8|' || snmp_enterprise_oid ||
							'.10.9|' || snmp_enterprise_oid || '.10.10|'|| snmp_enterprise_oid || '.10.11|' || snmp_enterprise_oid ||
							'.10.12|'|| snmp_enterprise_oid || '.10.13|' || snmp_enterprise_oid || '.10.14';
		snmp_varbinding_value = alert_name || '|' || alert_server_id || '|' || server_name || ' ('|| server_ip ||': ' || server_port || ')|' ||
							 alert_database_name || '|' || alert_schema_name || '|' || alert_object_name || '|' ||
							 alert_thresholdvalue;
	WHEN alert_object_type = 800 THEN
		snmp_trap_oid = snmp_enterprise_oid || '.8.' || alert_snmp_oid;
		snmp_varbinding_oid = snmp_enterprise_oid || '.10.1|' || snmp_enterprise_oid || '.10.3|' || snmp_enterprise_oid || '.10.5|' || snmp_enterprise_oid ||
							'.10.6|' || snmp_enterprise_oid || '.10.7|' || snmp_enterprise_oid || '.10.8|' || snmp_enterprise_oid ||
							'.10.9|' || snmp_enterprise_oid || '.10.10|'|| snmp_enterprise_oid || '.10.11|' || snmp_enterprise_oid ||
							'.10.12|'|| snmp_enterprise_oid || '.10.13|' || snmp_enterprise_oid || '.10.14';
		snmp_varbinding_value = alert_name || '|' || alert_server_id || '|' || server_name || ' ('|| server_ip ||': ' || server_port || ')|' ||
							 alert_database_name || '|' || alert_schema_name || '|' || alert_object_name || '|' ||
							 alert_thresholdvalue;
	END CASE;
END;
$$ LANGUAGE plpgsql;


-- JIRA: PEM-3542
-- As per v.12 release notes, abstime, reltime, and tinterval data types have been deprecated.
-- So we need to check and convert abstime data types to timestamptz
-- This code is useful is customer wants to migrate from older version to PG/EPAS 12.
DO
$$
DECLARE
	cnt integer;
BEGIN
    -- Check for the deprecated type in our user info probe
    SELECT count(*) INTO cnt
    FROM pem.probe_column
    WHERE sql_data_type = 'abstime'
    AND internal_name = 'valuntil'
    AND probe_id = (SELECT id from pem.probe where internal_name = 'user_info');

	IF cnt = 0 THEN
		RETURN;
	END IF;

    ALTER TABLE pemdata.user_info
        ALTER COLUMN valuntil SET DATA TYPE timestamptz;
    ALTER TABLE pemhistory.user_info
        ALTER COLUMN valuntil SET DATA TYPE timestamptz;

    -- Now update the pem.probe_column itself
    UPDATE pem.probe_column
        SET sql_data_type = 'timestamptz'
    WHERE sql_data_type = 'abstime' AND internal_name = 'valuntil';

END;
$$ LANGUAGE 'plpgsql';

-- JIRA PEM-3543
    -- Replacing terminology used as 'Master' with 'Primary'
    -- Replacing terminology used as 'Slave'/'Standby' with 'Replica'

UPDATE pem.probe_column
    SET display_name = REPLACE (display_name,'Master','Primary')
    WHERE internal_name  in ('xdb_smr_lag_rows', 'xdb_mmr_lag_rows');

UPDATE pem.alert_template
    SET display_name = REPLACE (REPLACE (REPLACE (display_name,'standby','replica'),'Standby','Replica'),'master','primary'),
        reference_id = REPLACE (REPLACE (REPLACE (reference_id,'standby','replica'),'Standby','Replica'),'master','primary'),
        description = REPLACE (REPLACE (REPLACE (description,'standby','replica'),'Standby','Replica'),'master','primary')
    WHERE display_name in (
    'Number of standby servers lag behind the master by write location',
    'Number of standby servers lag behind the master by flush location',
    'Number of standby servers lag behind the master by replay location',
    'Standby server lag behind the master by write location',
    'Standby server lag behind the master by flush location',
    'Standby server lag behind the master by replay location',
    'Total rows lagging in xdb single master replication',
    'Total rows lagging in xdb multi master replication',
    'Standby server lag behind the master by WAL segments',
    'Standby server lag behind the master by WAL pages',
    'Number of minutes lag of standby server from master server',
    'Standby servers lag behind the master by size(MB)');

UPDATE pem.alert_template
    SET param_names= '{Replica IP Address}',
        description = REPLACE (description,'Standy','Replica')
    WHERE display_name in (
    'Replica server lag behind the primary by WAL segments',
    'Replica server lag behind the primary by WAL pages')
    AND param_names = '{Standby IP Address}';

UPDATE pem.alert_template
    SET info_sql ='SELECT srv.description || '' ('' || srv.server || '')'' AS "Primary server", sr.client_addr AS "Replica server", sr.client_port AS "Replica server port", sr.xlog_lag_in_segments AS "Lag in segments", sr.xlog_lag_in_pages AS "Lag in pages", sr.lag_mb AS "Lag in MB" FROM pemdata.streaming_replication AS sr JOIN pem.server AS srv ON sr.server_id = srv.id WHERE sr.server_id = ''${server_id}''::integer AND lag_mb ${comparison_operator} ''${threshold_value}''::numeric;'
    WHERE display_name = 'Replica servers lag behind the primary by size(MB)';

UPDATE pem.alert_template
    SET description =  REPLACE (description,'standby','replica')
    WHERE display_name = 'Number of WAL archives pending';

-- Function to give lag bytes if any of the replica lag behind the primary in streaming replication
-- parameter 1 - User given bytes in MB to generate alert
-- parameter 2 - server id
-- parameter 3 - 1- write location, 2- flush location, 3 - replay location
CREATE OR REPLACE FUNCTION pem.number_replication_lag_bytes(integer, integer, integer)
RETURNS bigint AS $$
DECLARE
        xlog_sent_location BIGINT;
        xlog_write_location BIGINT;
        xlog_flush_location BIGINT;
        xlog_replay_location BIGINT;
        xlog_lag_bytes BIGINT;
        user_given_bytes integer;
        total_hostname RECORD;
        num_replica_lag integer;

BEGIN
        xlog_sent_location := 0;
        xlog_write_location := 0;
        xlog_flush_location := 0;
        xlog_replay_location := 0;
        user_given_bytes := $1;
        xlog_lag_bytes := 0;
        num_replica_lag := 0;

       IF $3 = 1 THEN
                -- For loop to extract the entry for each of the server and check if one of the replica is lag behind the primary then raise alert
                FOR total_hostname IN SELECT client_addr FROM pemdata.streaming_replication LOOP
                        -- fetch the sent location that is sent by the primary to the replica server
                        SELECT sent_location INTO xlog_sent_location FROM pemdata.streaming_replication WHERE client_addr = total_hostname.client_addr AND server_id = $2;
                        -- fetch xlog location for write transaction by replica server
                        SELECT write_location INTO xlog_write_location FROM pemdata.streaming_replication WHERE client_addr = total_hostname.client_addr AND server_id = $2;

                        xlog_lag_bytes := (xlog_sent_location - xlog_write_location);

                        -- convert the bytes to MB and compare it with user given bytes to generate alert
                        IF floor(((xlog_lag_bytes/1024)/1024)) > CAST(user_given_bytes As BIGINT) THEN
                                num_replica_lag := num_replica_lag + 1;
                        END IF;

                END LOOP;
        END IF;

      IF $3 = 2 THEN
                -- For loop to extract the entry for each of the server and check if one of the replica is lag behind the primary then raise alert
                FOR total_hostname IN SELECT client_addr FROM pemdata.streaming_replication LOOP
                        -- fetch the sent location that is sent by the primary to the replica server
                        SELECT sent_location INTO xlog_sent_location FROM pemdata.streaming_replication WHERE client_addr = total_hostname.client_addr AND server_id = $2;
                        -- fetch xlog location for flush transaction by replica server
                        SELECT flush_location INTO xlog_flush_location FROM pemdata.streaming_replication WHERE client_addr = total_hostname.client_addr AND server_id = $2;

                        xlog_lag_bytes := (xlog_sent_location - xlog_flush_location);

                        -- convert the bytes to MB and compare it with user given bytes to generate alert
                        IF floor(((xlog_lag_bytes/1024)/1024)) > CAST(user_given_bytes As BIGINT) THEN
                                num_replica_lag := num_replica_lag + 1;
                        END IF;

                END LOOP;
        END IF;

      IF $3 = 3 THEN
                -- For loop to extract the entry for each of the server and check if one of the replica is lag behind the primary then raise alert
                FOR total_hostname IN SELECT client_addr FROM pemdata.streaming_replication LOOP
                        -- fetch the sent location that is sent by the primary to the replica server
                        SELECT sent_location INTO xlog_sent_location FROM pemdata.streaming_replication WHERE client_addr = total_hostname.client_addr AND server_id = $2;
                        -- fetch xlog location for replay transaction by replica server
                        SELECT replay_location INTO xlog_replay_location FROM pemdata.streaming_replication WHERE client_addr = total_hostname.client_addr AND server_id = $2;

                        xlog_lag_bytes := (xlog_sent_location - xlog_replay_location);

                        -- convert the bytes to MB and compare it with user given bytes to generate alert
                        IF floor(((xlog_lag_bytes/1024)/1024)) > CAST(user_given_bytes As BIGINT) THEN
                                num_replica_lag := num_replica_lag + 1;
                        END IF;

                END LOOP;
        END IF;

        RETURN num_replica_lag;

END;
$$ LANGUAGE plpgsql;

-- PEM-688
-- Adding efm_missing_nodes, efm_minimum_standbys and  efm_membership_coordinator parameters from efm cluster-status-json output

DO $DO$
BEGIN
	-- Add efm_missing_nodes column to store missingnodes efm property

    IF NOT EXISTS (SELECT id FROM pem.probe_column WHERE internal_name = 'efm_missing_nodes' and probe_id=(SELECT id FROM pem.probe WHERE internal_name='efm_cluster_info')) THEN
        INSERT INTO pem.probe_column
                (probe_id, internal_name, display_name, display_position, classification,
                sql_data_type, unit_of_value, calculate_pit, discard_history, pit_by_default, is_graphable)
        SELECT
                (SELECT id FROM pem.probe WHERE internal_name='efm_cluster_info'),
                v.internal_name, v.display_name, v.display_position, v.classification,
                v.sql_data_type, v.unit_of_value, v.calculate_pit, v.discard_history, v.pit_by_default, v.is_graphable
        FROM
                (VALUES
                ('efm_missing_nodes', 'Missing Nodes', 5, 'm', 'text[]',   '{}', false, false, false, false)
                ) v(internal_name, display_name, display_position, classification,
                        sql_data_type, unit_of_value, calculate_pit, discard_history, pit_by_default, is_graphable);
    END IF;

    IF NOT EXISTS (SELECT 1
                   FROM pg_attribute
                   WHERE attrelid = (SELECT oid FROM pg_class WHERE relname = 'efm_cluster_info' and relnamespace = (SELECT oid FROM pg_namespace WHERE nspname = 'pemdata'))
                   AND attname = 'efm_missing_nodes') THEN
                   ALTER TABLE pemdata.efm_cluster_info ADD COLUMN efm_missing_nodes text[] DEFAULT '{}';
    END IF;


    IF NOT EXISTS (SELECT 1
                   FROM pg_attribute
                   WHERE attrelid = (SELECT oid FROM pg_class WHERE relname = 'efm_cluster_info' and relnamespace = (SELECT oid FROM pg_namespace WHERE nspname = 'pemhistory'))
                   AND attname = 'efm_missing_nodes') THEN
                   ALTER TABLE pemhistory.efm_cluster_info ADD COLUMN efm_missing_nodes text[] DEFAULT '{}';
    END IF;

	-- Add efm_minimum_standbys column to store minimumstandbys efm property

    IF NOT EXISTS (SELECT id FROM pem.probe_column WHERE internal_name = 'efm_minimum_standbys' and probe_id=(SELECT id FROM pem.probe WHERE internal_name='efm_cluster_info')) THEN
        INSERT INTO pem.probe_column
                (probe_id, internal_name, display_name, display_position, classification,
                sql_data_type, unit_of_value, calculate_pit, discard_history, pit_by_default, is_graphable)
        SELECT
                (SELECT id FROM pem.probe WHERE internal_name='efm_cluster_info'),
                v.internal_name, v.display_name, v.display_position, v.classification,
                v.sql_data_type, v.unit_of_value, v.calculate_pit, v.discard_history, v.pit_by_default, v.is_graphable
        FROM
                (VALUES
                ('efm_minimum_standbys', 'Minimum Standbys', 6, 'm', 'text',   '', false, false, false, false)
                ) v(internal_name, display_name, display_position, classification,
                        sql_data_type, unit_of_value, calculate_pit, discard_history, pit_by_default, is_graphable);
    END IF;

    IF NOT EXISTS (SELECT 1
                   FROM pg_attribute
                   WHERE attrelid = (SELECT oid FROM pg_class WHERE relname = 'efm_cluster_info' and relnamespace = (SELECT oid FROM pg_namespace WHERE nspname = 'pemdata'))
                   AND attname = 'efm_minimum_standbys') THEN
                   ALTER TABLE pemdata.efm_cluster_info ADD COLUMN efm_minimum_standbys text DEFAULT '';
    END IF;


    IF NOT EXISTS (SELECT 1
                   FROM pg_attribute
                   WHERE attrelid = (SELECT oid FROM pg_class WHERE relname = 'efm_cluster_info' and relnamespace = (SELECT oid FROM pg_namespace WHERE nspname = 'pemhistory'))
                   AND attname = 'efm_minimum_standbys') THEN
                   ALTER TABLE pemhistory.efm_cluster_info ADD COLUMN efm_minimum_standbys text DEFAULT '';
    END IF;

	-- Add efm_membership_coordinator column to store membershipcoordinator efm property

    IF NOT EXISTS (SELECT id FROM pem.probe_column WHERE internal_name = 'efm_membership_coordinator' and probe_id=(SELECT id FROM pem.probe WHERE internal_name='efm_cluster_info')) THEN
        INSERT INTO pem.probe_column
                (probe_id, internal_name, display_name, display_position, classification,
                sql_data_type, unit_of_value, calculate_pit, discard_history, pit_by_default, is_graphable)
        SELECT
                (SELECT id FROM pem.probe WHERE internal_name='efm_cluster_info'),
                v.internal_name, v.display_name, v.display_position, v.classification,
                v.sql_data_type, v.unit_of_value, v.calculate_pit, v.discard_history, v.pit_by_default, v.is_graphable
        FROM
                (VALUES
                ('efm_membership_coordinator', 'Membership Coordinator', 7, 'm', 'text',   '', false, false, false, false)
                ) v(internal_name, display_name, display_position, classification,
                        sql_data_type, unit_of_value, calculate_pit, discard_history, pit_by_default, is_graphable);
    END IF;

    IF NOT EXISTS (SELECT 1
                   FROM pg_attribute
                   WHERE attrelid = (SELECT oid FROM pg_class WHERE relname = 'efm_cluster_info' and relnamespace = (SELECT oid FROM pg_namespace WHERE nspname = 'pemdata'))
                   AND attname = 'efm_membership_coordinator') THEN
                   ALTER TABLE pemdata.efm_cluster_info ADD COLUMN efm_membership_coordinator text DEFAULT '';
    END IF;


    IF NOT EXISTS (SELECT 1
                   FROM pg_attribute
                   WHERE attrelid = (SELECT oid FROM pg_class WHERE relname = 'efm_cluster_info' and relnamespace = (SELECT oid FROM pg_namespace WHERE nspname = 'pemhistory'))
                   AND attname = 'efm_membership_coordinator') THEN
                   ALTER TABLE pemhistory.efm_cluster_info ADD COLUMN efm_membership_coordinator text DEFAULT '';
    END IF;

    UPDATE pem.chart_func SET func=$sql$
        		SELECT
                    xmlelement(name table,
                        xmlattributes('table table-bordered table-hover mx-auto text-left' AS class, 'width:auto;' AS style),
                        xmlelement(name thead,
                            xmlelement(name tr,
                                xmlelement(name th,
                                    xmlattributes('pem-element pem-table-th' AS class),
                                    'Properties'),
                                xmlelement(name th,
                                    xmlattributes('pem-element' AS class),
                                    'Values'))),
                        xmlelement(name tbody,
                            xmlelement(name tr,
                                xmlelement(name td,
                                    xmlattributes('pem-chart-td' AS class),
                                    'Cluster Name'),
                                xmlelement(name td,
                                    xmlattributes('pem-chart-td' AS class),
                                    ps.efm_cluster_name)),
                            xmlelement(name tr,
                                xmlelement(name td,
                                    xmlattributes('pem-chart-td' AS class),
                                    'Failover Manager Agent Running Status'),
                                xmlelement(name td,
                                    xmlattributes('pem-chart-td' AS class),
                                    CASE WHEN pe.efm_running = true THEN 'UP' ELSE 'DOWN' END)),
                            xmlelement(name tr,
                                xmlelement(name td,
                                    xmlattributes('pem-chart-td' AS class),
                                    'Allowed Node List'),
                             xmlelement(name td,
                                 xmlattributes('pem-chart-td' AS class),
                                 array_to_string(pe.efm_allowed_node_list, ', '))),
                            xmlelement(name tr,
                                xmlelement(name td,
                                    xmlattributes('pem-chart-td' AS class),
                                    'Standby Priority List'),
                                xmlelement(name td,
                                    xmlattributes('pem-chart-td' AS class),
                                    array_to_string(pe.efm_standby_priority_list, ', '))),
                            xmlelement(name tr,
                                xmlelement(name td,
                                    xmlattributes('pem-chart-td' AS class),
                                    'Missing Nodes'),
                                xmlelement(name td,
                                    xmlattributes('pem-chart-td' AS class),
                                    array_to_string(pe.efm_missing_nodes, ', '))),
                            xmlelement(name tr,
                                xmlelement(name td,
                                    xmlattributes('pem-chart-td' AS class),
                                    'Minimum Standbys'),
                                xmlelement(name td,
                                    xmlattributes('pem-chart-td' AS class),
                                    pe.efm_minimum_standbys)),
                            xmlelement(name tr,
                                xmlelement(name td,
                                    xmlattributes('pem-chart-td' AS class),
                                    'Membership Coordinator'),
                                xmlelement(name td,
                                    xmlattributes('pem-chart-td' AS class),
                                    pe.efm_membership_coordinator)),
                            xmlelement(name tr,
                                    xmlelement(name td,
                                        xmlattributes('pem-chart-td' AS class),
                                        'Cluster Status Message'),
                                    xmlelement(name td,
                                        xmlattributes('pem-chart-td' AS class),
                                        pe.efm_messages))))
					FROM
						pemdata.efm_cluster_info pe
						LEFT JOIN pem.server ps ON (ps.id = pe.server_id)
					WHERE pe.server_id = $1::int;
        $sql$
    WHERE dep_probes = '{efm_cluster_info}';
END;
$DO$ LANGUAGE 'plpgsql';

-- JIRA: PEM-322
-- Updating create_agent function to use existing agent id and configuration during force agent registration.

CREATE OR REPLACE FUNCTION pem.create_agent (varchar, integer)
RETURNS integer AS $$
DECLARE
    agent_id integer;
    agent_name varchar;
    sql varchar;
    agent_description varchar;
    id_exist boolean;
    role_exist boolean;
BEGIN
    agent_description := $1;
    id_exist := false;
    role_exist := false;

    SELECT true INTO id_exist FROM pem.agent WHERE id = $2;
    IF id_exist THEN
	UPDATE pem.agent SET (active, description) = ('t', agent_description) WHERE id = $2;
	agent_id := $2;
    ELSE
	INSERT INTO pem.agent(agent_capability_list, description) VALUES ('{}', agent_description) RETURNING id INTO agent_id;

	agent_name := 'agent' || agent_id;

	SELECT true INTO role_exist FROM pg_catalog.pg_roles WHERE rolname = agent_name;
	IF role_exist THEN
	    RAISE NOTICE 'ROLE % already exist', agent_name;
	ELSE
	    EXECUTE 'CREATE ROLE ' || agent_name  || ' WITH LOGIN';
	END IF;

	sql := 'GRANT pem_agent TO ' || agent_name;
	EXECUTE sql;
    END IF;

    RETURN agent_id;
END;
$$ LANGUAGE plpgsql;

-- PEM-3619 Add capability to pemagent to run global jobs, Also added enable, disable blackout jobs
DO $DO$
BEGIN
  -- Column is_global_job is mark job as global job if set to true
  IF NOT EXISTS (SELECT 1
                  FROM pg_attribute
                  WHERE attrelid = (SELECT oid FROM pg_class WHERE relname = 'job' and relnamespace = (SELECT oid FROM pg_namespace WHERE nspname = 'pem'))
                  AND attname = 'is_global_job') THEN
                  ALTER TABLE pem.job ADD COLUMN is_global_job boolean DEFAULT false;
  END IF;

	-- This table store global ran by which agent.
	DROP TABLE IF EXISTS pem.jobloginfo;

	CREATE TABLE pem.jobloginfo
	(
		agent_id              integer NOT NULL
		REFERENCES pem.agent (id) ON UPDATE RESTRICT ON DELETE CASCADE,
		joblogid              integer NOT NULL
		REFERENCES pem.joblog (jlgid) ON UPDATE RESTRICT ON DELETE CASCADE
	);

	COMMENT ON TABLE pem.jobloginfo IS 'Stores agent_id by whom global job got executed';
	COMMENT ON COLUMN pem.jobloginfo.agent_id IS 'Stores agent_id';
	COMMENT ON COLUMN pem.jobloginfo.joblogid IS 'Stores joblog id';
	GRANT INSERT ON TABLE pem.jobloginfo TO pem_agent;

	-- Function which is responsible for adding information about which agent has ran global job
	CREATE OR REPLACE FUNCTION insert_jobinfolog()
	RETURNS trigger AS
	$$
	DECLARE
		agentid    integer;
	BEGIN
		agentid := -1;
			SELECT agent_id FROM pem.job WHERE jobid=NEW.jlgjobid AND is_global_job=true INTO agentid;
			IF agentid <> -1 THEN
				INSERT INTO pem.jobloginfo(agent_id, joblogid) VALUES(agentid, NEW.jlgid);
      END IF;
    RETURN NEW;
  END;
  $$
	LANGUAGE 'plpgsql';

  -- Trigger for identifying global is ran by which agent
  DROP TRIGGER IF EXISTS jobloginfo_insertion ON pem.joblog;

  CREATE TRIGGER jobloginfo_insertion
  AFTER INSERT ON pem.joblog
    FOR EACH ROW
    EXECUTE PROCEDURE insert_jobinfolog();

	-- Table to store alert blackout config
  DROP TABLE IF EXISTS pem.alert_blackout_config;
  CREATE TABLE pem.alert_blackout_config(
    id serial not null,
    start_datetime timestamp with time zone,
    duration interval,
    blackout_object_ids integer[] default '{}',
    is_agent_object boolean default true,
    enable_jobid integer,
		disable_jobid integer,
    owner text default current_user,
    CONSTRAINT alert_blackout_config_pkey PRIMARY KEY (id),
    CONSTRAINT alert_blackout_config_unique UNIQUE (start_datetime, duration, blackout_object_ids, is_agent_object),
    CONSTRAINT alert_blackout_config_enable_jobid_fkey FOREIGN KEY (enable_jobid)
      REFERENCES pem.job (jobid) ON DELETE CASCADE,
    CONSTRAINT alert_blackout_config_disable_jobid_fkey FOREIGN KEY (disable_jobid)
      REFERENCES pem.job (jobid) ON DELETE CASCADE
  );

  COMMENT ON TABLE pem.alert_blackout_config IS 'Stores alert blackout config';
  COMMENT ON COLUMN pem.alert_blackout_config.id IS 'Stores id of alert blackout config';
  COMMENT ON COLUMN pem.alert_blackout_config.start_datetime IS 'Stores blackout start datetime';
  COMMENT ON COLUMN pem.alert_blackout_config.duration IS 'Stores blackout duration';
  COMMENT ON COLUMN pem.alert_blackout_config.blackout_object_ids IS 'Stores ids of agents/servers to blackout';
  COMMENT ON COLUMN pem.alert_blackout_config.is_agent_object IS 'Stores if blackout_object_ids are of agent or server';
  COMMENT ON COLUMN pem.alert_blackout_config.enable_jobid IS 'Stores jobid which is will enable blackout';
  COMMENT ON COLUMN pem.alert_blackout_config.disable_jobid IS 'Stores jobid which is will disable blackout';

  GRANT SELECT ON TABLE pem.alert_blackout_config TO pem_agent;

  -- Allow pemagent to update alert_blackout in pem.agent table.
  GRANT UPDATE(alert_blackout) ON TABLE pem.agent TO pem_agent;
END;
$DO$ LANGUAGE 'plpgsql';

CREATE OR REPLACE FUNCTION pem.send_notifications() RETURNS trigger AS $$
DECLARE
	subject text;
	message text;
	mail_group_id integer[];
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
	templateid integer;
	template_name text;
	down_objects_list text;
	agentid integer;
	low_trap boolean:= false;
	med_trap boolean:= false;
	high_trap boolean:= false;
	is_execute_script boolean:= false;
	is_execute_on_clear boolean:= false;
	is_execute_on_pem_server boolean:= false;
	code text;
	is_submit_to_nagios boolean:= false;
	passive_check_result_text text;
	submit_to_nagios_val boolean:= false;
	alert_curr_value text;
BEGIN
	-- Get alert details
	SELECT
		agent_id, template_id, send_email, acknowledged, flapping_detected, send_trap, snmp_trap_version, low_send_trap, med_send_trap,
		high_send_trap, execute_script, execute_script_on_clear, execute_script_on_pem_server, script_code, submit_to_nagios
	INTO
		agentid, templateid, is_send_email, is_acknowledged, is_flapping_detected, is_send_trap, trap_version, low_trap, med_trap,
		high_trap, is_execute_script, is_execute_on_clear, is_execute_on_pem_server, code, is_submit_to_nagios
	FROM
		pem.alert
	WHERE
		id = NEW.alert_id;

	-- Get the template name
	SELECT display_name INTO template_name FROM pem.alert_template WHERE id = templateid;

	-- Get the list of Agents/Servers Down
	down_objects_list = pem.get_down_objects_list(template_name);

	-- Get the current value of alert
	CASE WHEN COALESCE(NEW.display_value, '')::text != '' THEN
		alert_curr_value = COALESCE(NEW.display_value, '')::text;
	ELSE
		alert_curr_value = COALESCE(NEW.current_value, 0)::text;
	END CASE;

	IF ((TG_OP = 'INSERT') AND (NEW.current_state IS NOT NULL)) THEN
		-- Update state change count
		UPDATE pem.alert_status SET state_change_count = state_change_count + 1 WHERE alert_id = NEW.alert_id;

		-- Get group id's to send email
		SELECT ARRAY(SELECT DISTINCT UNNEST(pem.get_email_group_ids(NEW.alert_id, NEW.current_state::text, ''))) INTO mail_group_id;

		-- Check whether to send trap according to alert level low, med and high.
		IF (NEW.current_state IS NOT NULL) AND (NEW.current_state::text = 'LOW') AND low_trap THEN
			is_send_trap = true;
		ELSIF (NEW.current_state IS NOT NULL) AND (NEW.current_state::text = 'MEDIUM') AND med_trap THEN
			is_send_trap = true;
		ELSIF (NEW.current_state IS NOT NULL) AND (NEW.current_state::text = 'HIGH') AND high_trap THEN
			is_send_trap = true;
		ELSE
			is_send_trap = false;
		END IF;

		-- SMTP Notifications
		IF is_send_email AND (NOT is_acknowledged) AND (NOT is_flapping_detected) THEN
			-- Create subject and message
			SELECT subject_mail, message_mail INTO subject, message FROM pem.create_email(NEW.alert_id, 'Alert Detected');
			subject = regexp_replace(subject, '%AlertType%', NEW.current_state::text, 'g');
			message = regexp_replace(message, '%CurrentValue%', alert_curr_value, 'g');
			message = regexp_replace(message, '%AlertDetected%', now()::text, 'g');
			message = regexp_replace(message, '%DownObjects%', down_objects_list::text, 'g');
			message = regexp_replace(message, '%DetailInfo%', COALESCE(NEW.info, 'None')::text, 'g');

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
			varbinding_value = varbinding_value || '|NULL|' || alert_curr_value || '|NULL|';
			IF NEW.current_state IS NULL THEN
				varbinding_value = varbinding_value || '|CLEAR';
			ELSE
				varbinding_value = varbinding_value || NEW.current_state::text;
			END IF;
			-- Append current timestamp
			varbinding_value = varbinding_value || '|' || now()::text;

			-- Special handling for "Agents Down" and "Servers Down" alert
			IF (template_name = 'Agents Down') OR  (template_name = 'Servers Down') THEN
				varbinding_oid = varbinding_oid || '|' || enterprise_oid || '.7.15';
				varbinding_value = varbinding_value || '|' || down_objects_list::text;
			END IF;

			-- Check if detailed information is available then add variable binding
			IF NEW.info IS NOT NULL THEN
				varbinding_oid = varbinding_oid || '|' || enterprise_oid || '.7.16';
				varbinding_value = varbinding_value || '|' || COALESCE(NEW.info, 'None')::text;
			END IF;

			-- Send SNMP traps
			send_trap_val = pem.send_snmptrap(trap_oid, enterprise_oid, trap_version, varbinding_oid, varbinding_value);
		END IF;

		-- Script Execution
		IF is_execute_script AND (NOT is_acknowledged) AND (NOT is_flapping_detected) THEN
			PERFORM pem.create_script_job(NEW.alert_id, alert_curr_value, NEW.current_state::text, ''::text, is_execute_on_pem_server, code);
		END IF;

		-- submit to Nagios
		IF is_submit_to_nagios AND (NOT is_acknowledged) AND (NOT is_flapping_detected) THEN

			SELECT passive_check_result INTO passive_check_result_text FROM pem.create_passive_service_check_result(NEW.alert_id, 'Alert Detected',
															alert_curr_value,
															NEW.current_state::text);
			submit_to_nagios_val = pem.submit_to_nagios(passive_check_result_text);
		END IF;
	END IF;

	IF ((TG_OP = 'UPDATE') AND (NEW.current_state IS DISTINCT FROM OLD.current_state)) THEN
		-- Update state change count
		UPDATE pem.alert_status SET state_change_count = state_change_count + 1 WHERE alert_id = NEW.alert_id;

		-- Get group id's to send email
		SELECT ARRAY(SELECT DISTINCT UNNEST(pem.get_email_group_ids(NEW.alert_id, NEW.current_state::text, OLD.current_state::text))) INTO mail_group_id;

		-- Check whether to send trap according to alert level low, med and high.
		IF (NEW.current_state IS NOT NULL) AND (NEW.current_state::text = 'LOW' OR OLD.current_state::text = 'LOW') AND low_trap THEN
			is_send_trap = true;
		ELSIF (NEW.current_state IS NOT NULL) AND (NEW.current_state::text = 'MEDIUM' OR OLD.current_state::text = 'MEDIUM') AND med_trap THEN
			is_send_trap = true;
		ELSIF (NEW.current_state IS NOT NULL) AND (NEW.current_state::text = 'HIGH' OR OLD.current_state::text = 'HIGH') AND high_trap THEN
			is_send_trap = true;
		ELSIF (NEW.current_state IS NULL) AND (OLD.current_state IS NOT NULL) AND is_send_trap THEN
			is_send_trap = true;
		ELSE
			is_send_trap = false;
		END IF;

		-- SMTP Notifications
		IF is_send_email AND (NOT is_acknowledged) AND (NOT is_flapping_detected) THEN
			-- If current state is NULL means alert is cleared.
			IF (NEW.current_state IS NOT NULL) THEN
				-- if OLD current_state is not null means alert level changed.
				IF (OLD.current_state IS NOT NULL AND (OLD.current_state > NEW.current_state)) THEN
					-- Create subject and message
					SELECT subject_mail, message_mail INTO subject, message FROM pem.create_email(NEW.alert_id, 'Alert Level Decreased');
					message = regexp_replace(message, '%CurrentState%', NEW.current_state::text, 'g');
					message = regexp_replace(message, '%OldState%', OLD.current_state::text, 'g');
					message = regexp_replace(message, '%StateChanged%', now()::text, 'g');
				ELSIF (OLD.current_state IS NOT NULL AND (OLD.current_state < NEW.current_state)) THEN
					-- Create subject and message
					SELECT subject_mail, message_mail INTO subject, message FROM pem.create_email(NEW.alert_id, 'Alert Level Increased');
					message = regexp_replace(message, '%CurrentState%', NEW.current_state::text, 'g');
					message = regexp_replace(message, '%OldState%', OLD.current_state::text, 'g');
					message = regexp_replace(message, '%StateChanged%', now()::text, 'g');
				ELSE
					-- Create subject and message
					SELECT subject_mail, message_mail INTO subject, message FROM pem.create_email(NEW.alert_id, 'Alert Detected');
					subject = regexp_replace(subject, '%AlertType%', NEW.current_state::text, 'g');
					message = regexp_replace(message, '%AlertDetected%', now()::text, 'g');
				END IF;
			ELSE
				-- Create subject and message
				SELECT subject_mail, message_mail INTO subject, message FROM pem.create_email(NEW.alert_id, 'Alert Cleared');
				message = regexp_replace(message, '%AlertCleared%', now()::text, 'g');
			END IF;

			message = regexp_replace(message, '%CurrentValue%', alert_curr_value, 'g');
			message = regexp_replace(message, '%DownObjects%', down_objects_list::text, 'g');
			message = regexp_replace(message, '%DetailInfo%', COALESCE(NEW.info, 'None')::text, 'g');

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
			varbinding_value = varbinding_value || '|' || COALESCE(OLD.current_value, 0)::text || '|' || alert_curr_value;

			IF OLD.current_state IS NULL THEN
				varbinding_value = varbinding_value || '|CLEAR';
			ELSE
				varbinding_value = varbinding_value || '|' || OLD.current_state::text;
			END IF;

			IF NEW.current_state IS NULL THEN
				varbinding_value = varbinding_value || '|CLEAR';
			ELSE
				varbinding_value = varbinding_value || '|' || NEW.current_state::text;
			END IF;
			-- Append current timestamp
			varbinding_value = varbinding_value || '|' || now()::text;

			-- Special handling for "Agents Down" and "Servers Down" alert
			IF (template_name = 'Agents Down') OR  (template_name = 'Servers Down') THEN
				varbinding_oid = varbinding_oid || '|' || enterprise_oid || '.7.15';
				varbinding_value = varbinding_value || '|' || down_objects_list::text;
			END IF;

			-- Check if detailed information is available then add variable binding
			IF NEW.info IS NOT NULL THEN
				varbinding_oid = varbinding_oid || '|' || enterprise_oid || '.7.16';
				varbinding_value = varbinding_value || '|' || COALESCE(NEW.info, 'None')::text;
			END IF;

			-- Send SNMP traps
			send_trap_val = pem.send_snmptrap(trap_oid, enterprise_oid, trap_version, varbinding_oid, varbinding_value);
		END IF;

		-- Script Execution
		IF is_execute_script AND (NOT is_acknowledged) AND (NOT is_flapping_detected) THEN
			-- If current state is NULL means alert is cleared then need to check the value of is_execute_on_clear flag.
			IF (NEW.current_state IS NULL) THEN
				IF is_execute_on_clear THEN
					PERFORM pem.create_script_job(NEW.alert_id, alert_curr_value, 'CLEAR'::text, OLD.current_state::text, is_execute_on_pem_server, code);
				END IF;
			ELSE
				PERFORM pem.create_script_job(NEW.alert_id, alert_curr_value, NEW.current_state::text, OLD.current_state::text, is_execute_on_pem_server, code);
			END IF;
		END IF;

		-- submit to Nagios
		IF is_submit_to_nagios AND (NOT is_acknowledged) AND (NOT is_flapping_detected) THEN

			-- If current state is NULL means alert is cleared.
			IF (NEW.current_state IS NOT NULL) THEN
				-- if OLD current_state is not null means alert level changed.
				IF (OLD.current_state IS NOT NULL AND (OLD.current_state > NEW.current_state)) THEN
					SELECT passive_check_result INTO passive_check_result_text FROM pem.create_passive_service_check_result(NEW.alert_id,
																	'Alert Level Decreased',
																	alert_curr_value,
																	NEW.current_state::text);
					passive_check_result_text = regexp_replace(passive_check_result_text, '%OldState%', OLD.current_state::text, 'g');
					passive_check_result_text = regexp_replace(passive_check_result_text, '%NewState%', NEW.current_state::text, 'g');

				ELSIF (OLD.current_state IS NOT NULL AND (OLD.current_state < NEW.current_state)) THEN
					SELECT passive_check_result INTO passive_check_result_text FROM pem.create_passive_service_check_result(NEW.alert_id,
																	'Alert Level Increased',
																	alert_curr_value,
																	NEW.current_state::text);
					passive_check_result_text = regexp_replace(passive_check_result_text, '%OldState%', OLD.current_state::text, 'g');
					passive_check_result_text = regexp_replace(passive_check_result_text, '%NewState%', NEW.current_state::text, 'g');

				ELSE
					SELECT passive_check_result INTO passive_check_result_text FROM pem.create_passive_service_check_result(NEW.alert_id,
																	'Alert Detected',
																	alert_curr_value,
																	NEW.current_state::text);
				END IF;

			ELSE
				SELECT passive_check_result INTO passive_check_result_text FROM pem.create_passive_service_check_result(NEW.alert_id,
																'Alert Cleared',
																alert_curr_value,
																NEW.current_state::text);
			END IF;

			submit_to_nagios_val = pem.submit_to_nagios(passive_check_result_text);
		END IF;
	END IF;

	RETURN NEW;
END;
$$ LANGUAGE plpgsql;

END TRANSACTION;
