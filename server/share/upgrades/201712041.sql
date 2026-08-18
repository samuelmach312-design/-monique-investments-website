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
'SELECT 201712041::integer;'
  LANGUAGE 'sql' IMMUTABLE;

REVOKE ALL ON TABLE pem.agent FROM pem_agent;
GRANT SELECT ON TABLE pem.agent TO pem_agent;
GRANT UPDATE(agent_capability_list, active, version, platform) ON TABLE pem.agent TO pem_agent;

CREATE OR REPLACE FUNCTION pem.is_server_owner(_user text, _server_id int)
RETURNS boolean AS
$$
SELECT CASE WHEN
_user = COALESCE((
        SELECT usename FROM pg_catalog.pg_user u
        WHERE u.usesysid = (
            SELECT s.owner FROM pem.server s WHERE s.id = _server_id
        )
    ), current_user
) THEN TRUE ELSE FALSE END;
$$ language 'sql';

CREATE OR REPLACE FUNCTION pem.can_access_server(_server_id int)
RETURNS boolean AS
$$
SELECT count(*) >= 1 FROM pem.server WHERE id = _server_id;
$$ language 'sql';

DO $$
DECLARE
  rls_supported boolean;
BEGIN
    SELECT (count(*) = 1) INTO rls_supported FROM pg_catalog.pg_class WHERE relname = 'pg_policy' AND relnamespace = (SELECT oid FROM pg_catalog.pg_namespace WHERE nspname = 'pg_catalog');

    IF rls_supported THEN
        RAISE INFO 'Enabling RLS on pem.server...';
        EXECUTE 'ALTER TABLE pem.server ENABLE ROW LEVEL SECURITY';

        RAISE INFO 'SELECT RLS policy on pem.server...';
        -- SELECT operation on pem.server
        EXECUTE $SQL$
            CREATE POLICY pem_server_team_support_select
                ON pem.server
                FOR SELECT
                USING (
                    owner = current_user::regrole::oid OR
                    pg_catalog.pg_has_role('pem_agent', 'member'::text) OR
                    team is NULL OR team = '' OR
                    ((
                        SELECT count(*) >= 1
                        FROM pg_catalog.pg_user WHERE usename = team
                    ) AND pg_catalog.pg_has_role(
                        CASE WHEN (
                            SELECT count(*) >= 1 FROM pg_user
                            WHERE usename = team::name
                        ) THEN team::name ELSE current_user::name END,
                        'member'::text
                    ))
                )
        $SQL$;

        RAISE INFO 'UPDATE RLS policy on pem.server...';
        -- UPDATE operation on pem.server
        EXECUTE $SQL$
            CREATE POLICY pem_server_team_support_update
                ON pem.server
                FOR UPDATE
                USING (owner = current_user::regrole::oid)
                WITH CHECK (
                    pg_catalog.pg_has_role(owner::oid, 'pem_admin'::name, 'member'::text)
                )
        $SQL$;

        RAISE INFO 'DELETE RLS policy on pem.server...';
        -- DELETE operation on pem.server
        EXECUTE $SQL$
            CREATE POLICY pem_server_team_support_delete
                ON pem.server
                FOR DELETE
                USING (owner = current_user::regrole::oid)
        $SQL$;

        RAISE INFO 'INSERT RLS policy on pem.server...';
        -- INSERT operation on pem.server
        EXECUTE $SQL$
            CREATE POLICY pem_server_team_support_insert
                ON pem.server
                FOR INSERT
                WITH CHECK (
                    pg_catalog.pg_has_role(owner::oid, 'pem_admin'::name, 'member'::text)
                )
        $SQL$;


        RAISE INFO 'Enabling RLS on pem.server_option...';
        EXECUTE 'ALTER TABLE pem.server_option ENABLE ROW LEVEL SECURITY';

        RAISE INFO 'SELECT RLS policy on pem.server_option...';
        -- SELECT operation on pem.server
        EXECUTE $SQL$
            CREATE POLICY pem_server_option_select
            ON pem.server_option
            FOR SELECT
                USING (
                    pem_user = current_user OR pem.is_server_owner(pem_user, server_id)
                );
        $SQL$;

        RAISE INFO 'UPDATE RLS policy on pem.server_option...';
        -- UPDATE operation on pem.server
        EXECUTE $SQL$
            CREATE POLICY pem_server_option_update
                ON pem.server_option
                FOR UPDATE
                USING (pem_user = current_user)
                WITH CHECK (pem_user = current_user)
        $SQL$;

        RAISE INFO 'DELETE RLS policy on pem.server_option...';
        -- DELETE operation on pem.server
        EXECUTE $SQL$
            CREATE POLICY pem_server_option_delete
                ON pem.server_option
                FOR DELETE
                USING (pem.is_server_owner(current_user, server_id))
        $SQL$;

        RAISE INFO 'INSERT RLS policy on pem.server_option...';
        -- INSERT operation on pem.server
        EXECUTE $SQL$
            CREATE POLICY pem_server_option_insert
                ON pem.server_option
                FOR INSERT
                WITH CHECK (
                    pem.can_access_server(server_id) AND pem_user = current_user
                )
        $SQL$;

        RAISE INFO 'Enabling RLS on pem.agent...';
        EXECUTE 'ALTER TABLE pem.agent ENABLE ROW LEVEL SECURITY';

        RAISE INFO 'SELECT RLS policy on pem.agent...';
        EXECUTE $SQL$
            CREATE POLICY pem_agent_team_support_select
                ON pem.agent
                FOR SELECT
                USING (
                    owner = current_user::regrole::oid OR
                    pg_catalog.pg_has_role('pem_agent', 'member'::text) OR
                    pg_catalog.pg_has_role('pem_admin', 'member'::text) OR
                    team is NULL OR team = '' OR
                    id in (
                        SELECT DISTINCT (agent_id)
                        FROM pem.agent_server_binding
                        WHERE server_id in (SELECT id FROM pem.server)
                    ) OR
                    ((
                        SELECT count(*) >= 1
                        FROM pg_catalog.pg_user WHERE usename = team
                    ) AND pg_catalog.pg_has_role(
                        CASE WHEN (
                            SELECT count(*) >= 1 FROM pg_user
                            WHERE usename = team::name
                        ) THEN team::name ELSE current_user::name END,
                        'member'::text
                    ))
                )
        $SQL$;

        RAISE INFO 'INSERT RLS policy on pem.agent...';
        EXECUTE $SQL$
            CREATE POLICY pem_agent_team_support_insert
                ON pem.agent
                FOR INSERT
                WITH CHECK (pg_catalog.pg_has_role('pem_admin', 'member'::text))
        $SQL$;

        RAISE INFO 'UPDATE RLS policy on pem.agent...';
        EXECUTE $SQL$
            CREATE POLICY pem_agent_team_support_update
                ON pem.agent
                FOR UPDATE
                USING (
                    pg_catalog.pg_has_role('pem_admin', 'member'::text) OR
                    pg_catalog.pg_has_role('pem_agent', 'member'::text)
                )
                WITH CHECK (
                    pg_catalog.pg_has_role('pem_admin', 'member'::text) OR
                    pg_catalog.pg_has_role('pem_agent', 'member'::text)
                )
        $SQL$;

        RAISE INFO 'DELETE RLS policy on pem.agent...';
        EXECUTE $SQL$
            CREATE POLICY pem_agent_team_support_delete
                ON pem.agent
                FOR DELETE
                USING (
                    pg_catalog.pg_has_role('pem_admin', 'member'::text)
                )
        $SQL$;
    END IF;
END
$$ language 'plpgsql';

-- Remove PEM webclient product key entry from the pem.config table.
DELETE FROM pem.config WHERE param = 'web_client_product_key';

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
			downObjects,
			streamingReplicationLagBytes,
			packageUpdates,
			standbyServerDetails}
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
		SYNTAX			INTEGER  { low ( 0 ) , medium ( 1 ), high ( 2 ) }
		MAX-ACCESS		read-only
		STATUS			current
		DESCRIPTION		"This parameter gives the previous status of the alert"
		::=  {  bindingVariables  12  }

	status	OBJECT-TYPE
		SYNTAX			INTEGER  { low ( 0 ) , medium ( 1 ), high ( 2 ) }
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

	packageUpdates		OBJECT-TYPE
		SYNTAX			DisplayString
		MAX-ACCESS		read-only
		STATUS			current
		DESCRIPTION		"This parameter list the packages which needs to upgrade and also list the obsolete"
		::=  {  bindingVariables  16  }

	streamingReplicationLagBytes    OBJECT-TYPE
                SYNTAX                  DisplayString
                MAX-ACCESS              read-only
                STATUS                  current
                DESCRIPTION             "This parameter list the slaves which lags behind the master by write/flush/replay location in streaming replication"
                ::=  {  bindingVariables  17  }

	standbyServerDetails    OBJECT-TYPE
                SYNTAX                  DisplayString
                MAX-ACCESS              read-only
                STATUS                  current
                DESCRIPTION             "This parameter displays the Standby server for which there is WAL segment/page lag in streaming replication"
                ::=  {  bindingVariables  18  }';

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
		object_string = '{ alertName, thresholdValue, previousValue, value, previousStatus, status, recordedTime, downObjects }';
		object_prefix = 'gl';
		group_text = E'\n\n\tpemGlobalNotificationGroup  NOTIFICATION-GROUP
	\tNOTIFICATIONS {';
		group_description = 'This group contains the global notification types';
	WHEN object_type = 100 THEN
		where_clause = 'WHERE object_type = 100 AND snmp_oid > 0';
		parent_node = 'agentAlerts';
		object_string = '{ alertName, agentID , agentName, thresholdValue, previousValue, value, previousStatus, status, recordedTime, packageUpdates }';
		object_prefix = 'ag';
		group_text = E'\n\n\tpemAgentNotificationGroup  NOTIFICATION-GROUP
	\tNOTIFICATIONS {';
		group_description = 'This group contains the agent level notification types';
	WHEN object_type = 200 THEN
		where_clause = 'WHERE object_type = 200 AND snmp_oid > 0';
		parent_node = 'serverAlerts';
		object_string = '{ alertName, serverID , serverName, thresholdValue, previousValue, value, previousStatus, status, recordedTime, streamingReplicationLagBytes,  standbyServerDetails}';
		object_prefix = 'sr';
		group_text = E'\n\n\tpemServerNotificationGroup  NOTIFICATION-GROUP
	\tNOTIFICATIONS {';
		group_description = 'This group contains the server level notification types';
	WHEN object_type = 300 THEN
		where_clause = 'WHERE object_type = 300 AND snmp_oid > 0';
		parent_node = 'databaseAlerts';
		object_string = '{ alertName, serverID , serverName, databaseName, thresholdValue, previousValue, value, previousStatus, status, recordedTime }';
		object_prefix = 'db';
		group_text = E'\n\n\tpemDatabaseNotificationGroup  NOTIFICATION-GROUP
	\tNOTIFICATIONS {';
		group_description = 'This group contains the database level notification types';
	WHEN object_type = 400 THEN
		where_clause = 'WHERE object_type = 400 AND snmp_oid > 0';
		parent_node = 'schemaAlerts';
		object_string = '{ alertName, serverID , serverName, databaseName, schemaName, thresholdValue, previousValue, value, previousStatus, status, recordedTime }';
		object_prefix = 'sc';
		group_text = E'\n\n\tpemSchemaNotificationGroup  NOTIFICATION-GROUP
	\tNOTIFICATIONS {';
		group_description = 'This group contains the schema level notification types';
	WHEN object_type = 500 THEN
		where_clause = 'WHERE object_type = 500 AND snmp_oid > 0';
		parent_node = 'objectAlerts';
		object_string = '{ alertName, serverID , serverName, databaseName, schemaName, objectName, thresholdValue, previousValue, value, previousStatus, status, recordedTime }';
		object_prefix = 'tb';
		group_text = E'\n\n\tpemTableNotificationGroup  NOTIFICATION-GROUP
	\tNOTIFICATIONS {';
		group_description = 'This group contains the table level notification types';
	WHEN object_type = 600 THEN
		where_clause = 'WHERE object_type = 600 AND snmp_oid > 0';
		parent_node = 'objectAlerts';
		object_string = '{ alertName, serverID , serverName, databaseName, schemaName, objectName, thresholdValue, previousValue, value, previousStatus, status, recordedTime }';
		object_prefix = 'in';
		group_text = E'\n\n\tpemIndexNotificationGroup  NOTIFICATION-GROUP
	\tNOTIFICATIONS {';
		group_description = 'This group contains the index level notification types';
	WHEN object_type = 700 THEN
		where_clause = 'WHERE object_type = 700 AND snmp_oid > 0';
		parent_node = 'objectAlerts';
		object_string = '{ alertName, serverID , serverName, databaseName, schemaName, objectName, thresholdValue, previousValue, value, previousStatus, status, recordedTime }';
		object_prefix = 'se';
		group_text = E'\n\n\tpemSequenceNotificationGroup  NOTIFICATION-GROUP
	\tNOTIFICATIONS {';
		group_description = 'This group contains the sequence level notification types';
	WHEN object_type = 800 THEN
		where_clause = 'WHERE object_type = 800 AND snmp_oid > 0';
		parent_node = 'objectAlerts';
		object_string = '{ alertName, serverID , serverName, databaseName, schemaName, objectName, thresholdValue, previousValue, value, previousStatus, status, recordedTime }';
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

END TRANSACTION;
