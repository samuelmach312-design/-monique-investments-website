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
'SELECT 201404156::integer;'
  LANGUAGE 'sql' IMMUTABLE;

-- Disable global alerts
UPDATE pem.alert SET enabled = false WHERE template_id = (SELECT id FROM pem.alert_template WHERE display_name = 'Agents Down');
UPDATE pem.alert SET enabled = false WHERE template_id = (SELECT id FROM pem.alert_template WHERE display_name = 'Servers Down');

SELECT pem.create_alert_template(
	'Agent Down',
	'Specified agent is currently down',
	$sql$
SELECT
    count(pa.id)
FROM
    pem.agent pa LEFT OUTER JOIN pem.agent_heartbeat pah ON (pa.id = pah.agent_id)
WHERE
    pa.id = ${agent_id} AND
    pa.active = TRUE AND
    NOT pa.alert_blackout AND
    CASE WHEN pah.agent_id IS NULL THEN FALSE ELSE pah.last_heartbeat < now() - (pa.heartbeat_interval)*2*'1 second'::interval END$sql$,
    100, NULL, NULL, NULL, NULL, '{}', 31);

SELECT pem.create_alert_template(
	'Server Down',
	'Specified server is currently inaccessible.',
	$sql$
SELECT
    count(ps.id)
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
    CASE WHEN pah.agent_id is NULL THEN FALSE ELSE pah.last_heartbeat > now() - (pa.heartbeat_interval)*2*'1 second'::interval END AND
    CASE WHEN psh.server_id IS NULL THEN FALSE ELSE psh.last_heartbeat < now() - (pa.heartbeat_interval)*2*'1 second'::interval END$sql$,
    200, NULL, NULL, NULL, NULL, '{}', 74);

CREATE OR REPLACE FUNCTION pem.create_default_agent_alerts(agent_id integer)
RETURNS VOID AS $$
BEGIN
	IF NOT pem.check_alert_exist('Swap consumption percentage', $1, NULL, NULL, NULL, NULL, NULL, 100) THEN
		PERFORM pem.create_alert('Swap consumption percentage',
		(SELECT id FROM pem.alert_template WHERE display_name = 'Swap consumption percentage' AND object_type = 100 LIMIT 1),
		$1, NULL, NULL, NULL, NULL, NULL, '{}', '>', '{25, 50, 75}', 1, 30, true);
	END IF;

	IF NOT pem.check_alert_exist('Memory used percentage', $1, NULL, NULL, NULL, NULL, NULL, 100) THEN
		PERFORM pem.create_alert('Memory used percentage',
		(SELECT id FROM pem.alert_template WHERE display_name = 'Memory used percentage' AND object_type = 100 LIMIT 1),
		$1, NULL, NULL, NULL, NULL, NULL, '{}', '>', '{80, 90, 95}', 1, 30, true);
	END IF;

	IF NOT pem.check_alert_exist('Most used disk percentage', $1, NULL, NULL, NULL, NULL, NULL, 100) THEN
		PERFORM pem.create_alert('Most used disk percentage',
		(SELECT id FROM pem.alert_template WHERE display_name = 'Most used disk percentage' AND object_type = 100 LIMIT 1),
		$1, NULL, NULL, NULL, NULL, NULL, '{}', '>', '{75, 85, 95}', 1, 30, true);
	END IF;

	IF NOT pem.check_alert_exist('Load Average per CPU Core (5 minutes)', $1, NULL, NULL, NULL, NULL, NULL, 100) THEN
		PERFORM pem.create_alert('Load Average per CPU Core (5 minutes)',
		(SELECT id FROM pem.alert_template WHERE display_name = 'Load Average per CPU Core (5 minutes)' AND object_type = 100 LIMIT 1),
		$1, NULL, NULL, NULL, NULL, NULL, '{}', '>', '{0.7, 2.0, 5.0}', 1, 30, true);
	END IF;

	IF NOT pem.check_alert_exist('Package version mismatch', $1, NULL, NULL, NULL, NULL, NULL, 100) THEN
		PERFORM pem.create_alert('Package version mismatch',
		(SELECT id FROM pem.alert_template WHERE display_name = 'Package version mismatch' AND object_type = 100 LIMIT 1),
		$1, NULL, NULL, NULL, NULL, NULL, '{}', '>', '{0.1, 0.2, 0.3}', 1440, 30, true);
	END IF;
	IF NOT pem.check_alert_exist('Agent Down', $1, NULL, NULL, NULL, NULL, NULL, 100) THEN
		PERFORM pem.create_alert('Agent Down',
		(SELECT id FROM pem.alert_template WHERE display_name = 'Agent Down' AND object_type = 100 LIMIT 1),
		$1, NULL, NULL, NULL, NULL, NULL, '{}', '>', '{0.1, 0.2, 0.3}', 1, 30, true);
	END IF;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION pem.auto_create_server_alerts()
RETURNS trigger AS $$
DECLARE
	is_auto_create boolean:= false;
BEGIN
	-- select value of auto_create_server_alerts
	SELECT value INTO is_auto_create FROM pem.config WHERE param = 'auto_create_server_alerts';

	IF is_auto_create THEN
		PERFORM pem.create_default_server_alerts(NEW.server_id);
	END IF;
	RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION pem.create_default_server_alerts(server_id integer)
RETURNS VOID AS $$
BEGIN
	IF NOT pem.check_alert_exist('Total connections as percentage of max_connections', 0, $1, NULL, NULL, NULL, NULL, 200) THEN
		PERFORM pem.create_alert('Total connections as percentage of max_connections',
		(SELECT id FROM pem.alert_template WHERE display_name = 'Total connections as percentage of max_connections' AND object_type = 200 LIMIT 1),
		0, $1, NULL, NULL, NULL, NULL, '{}', '>', '{75, 85, 95}', 1, 30, true);
	END IF;

	IF NOT pem.check_alert_exist('Connections in idle-in-transaction state, as a percentage of max_connections', 0, $1, NULL, NULL, NULL, NULL, 200) THEN
		PERFORM pem.create_alert('Connections in idle-in-transaction state, as a percentage of max_connections',
		(SELECT id FROM pem.alert_template WHERE display_name = 'Connections in idle-in-transaction state, as a percentage of max_connections' AND object_type = 200 LIMIT 1),
		0, $1, NULL, NULL, NULL, NULL, '{}', '>', '{3, 5, 10}', 1, 30, true);
	END IF;

	IF NOT pem.check_alert_exist('Last AutoVacuum', 0, $1, NULL, NULL, NULL, NULL, 200) THEN
		PERFORM pem.create_alert('Last AutoVacuum',
		(SELECT id FROM pem.alert_template WHERE display_name = 'Last AutoVacuum' AND object_type = 200 LIMIT 1),
		0, $1, NULL, NULL, NULL, NULL, '{}', '>', '{1, 4, 12}', 1, 30, true);
	END IF;

	IF NOT pem.check_alert_exist('A user expires in N days', 0, $1, NULL, NULL, NULL, NULL, 200) THEN
		PERFORM pem.create_alert('A user expires in N days',
		(SELECT id FROM pem.alert_template WHERE display_name = 'A user expires in N days' AND object_type = 200 LIMIT 1),
		0, $1, NULL, NULL, NULL, NULL, '{}', '<', '{10, 5, 1}', 1, 30, true);
	END IF;

	IF NOT pem.check_alert_exist('Server Down', 0, $1, NULL, NULL, NULL, NULL, 200) THEN
		PERFORM pem.create_alert('Server Down',
		(SELECT id FROM pem.alert_template WHERE display_name = 'Server Down' AND object_type = 200 LIMIT 1),
		0, $1, NULL, NULL, NULL, NULL, '{}', '>', '{0.1, 0.2, 0.3}', 1, 30, true);
	END IF;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION pem.auto_create_alerts_on_exisiting_servers()
RETURNS VOID AS $$
DECLARE
	rec record;
BEGIN
	FOR rec in (SELECT id FROM pem.server)
	LOOP
		PERFORM pem.create_default_server_alerts(rec.id);
	END LOOP;
END;
$$ LANGUAGE plpgsql;

-- Create auto alerts for the existing servers
SELECT pem.auto_create_alerts_on_exisiting_servers();

-- Create auto alerts for the existing agent
SELECT pem.auto_create_alerts_on_exisiting_agents();

COMMIT TRANSACTION;
