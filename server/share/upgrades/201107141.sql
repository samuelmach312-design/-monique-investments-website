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

-- Upgrade script for v1.0.0b2 to v1.0.0b3

BEGIN TRANSACTION;

-- TODO: Update the schema version as per the Beta3 release date
CREATE OR REPLACE FUNCTION pem.schema_version()
  RETURNS integer AS
'SELECT 201107141::integer;'
  LANGUAGE 'sql' IMMUTABLE;

-- change made in pemserver.sql as per commit id 0660efbb6d4c9bbdce4831d4b1c017399ed45dd8
UPDATE pem.probe_column SET pit_by_default=true WHERE probe_id=(SELECT id FROM pem.probe WHERE internal_name='network_statistics') AND internal_name='link_speed_mbps';

-- change made in pemserver.sql as per commit id 825a0d2a766093fb262adcd8ea39f0983f48ea9e
SELECT pem.create_alert_template(
       'Disk Consumption',
       'Disk space consumed (in megabytes).

Probe dependency list: disk_space',
       $sql$
SELECT space_used_mb
FROM pemdata.disk_space
WHERE agent_id = ${agent_id}
AND mount_point = '${param_1}';$sql$,
       100, '{mount point}', '{STRING}', NULL, NULL);

SELECT pem.create_alert_template(
       'Disk consumption percentage',
       'Percentage of disk consumed.

Probe dependency list: disk_space',
       $sql$
SELECT (space_used_mb::float * 100)
	/ CASE size_mb WHEN 0 THEN 1 ELSE size_mb END
FROM pemdata.disk_space
WHERE agent_id = ${agent_id}
AND mount_point = '${param_1}';$sql$,
       100, '{mount point}', '{STRING}', NULL, NULL);

SELECT pem.create_alert_template(
       'Disk Available',
       'Disk space available (in megabytes).

Probe dependency list: disk_space',
       $sql$
SELECT space_available_mb
FROM pemdata.disk_space
WHERE agent_id = ${agent_id}
AND mount_point = '${param_1}';$sql$,
       100, '{mount point}', '{STRING}', NULL, NULL);

SELECT pem.create_alert_template(
       'Disk busy percentage',
       'Percentage of disk busy.

Probe dependency list: disk_busy_info',
       $sql$
SELECT disk_busy
FROM pemdata.disk_busy_info
WHERE agent_id = ${agent_id}
AND mount_point = '${param_1}';$sql$,
       100, '{mount point}', '{STRING}', NULL, NULL);

-- change made in pemserver.sql as per commit id f78464f7b685cc5d8fad96360772791d1eeb5ed9
-- In session_info probe's SQL, replace the first occurrence of 'datname' with 'datname AS database_name'
UPDATE  pem.probe
SET             probe_code = regexp_replace( probe_code, 'datname', 'datname AS database_name')
WHERE   internal_name = 'session_info';

UPDATE  pem.probe_server_version
SET             probe_code = regexp_replace( probe_code, 'datname', 'datname AS database_name')
WHERE   probe_id = (SELECT id FROM pem.probe WHERE internal_name = 'session_info')
AND             probe_code IS NOT NULL;

-- Update probe_column table to rename session_info's 'datname' column to 'database_name'
UPDATE  pem.probe_column
SET             internal_name = 'database_name'
WHERE   probe_id = (SELECT id FROM pem.probe WHERE internal_name = 'session_info')
AND             internal_name = 'datname';

-- Update the column name in session_info table in pemdata and pemhistory schema
ALTER TABLE pemdata.session_info RENAME COLUMN datname TO database_name;
ALTER TABLE pemhistory.session_info RENAME COLUMN datname TO database_name;

-- Update the trigger functions related to session_info probe
CREATE OR REPLACE FUNCTION pemdata.copy_session_info_to_history() RETURNS TRIGGER AS $$
BEGIN
        IF (TG_OP = 'INSERT' OR TG_OP = 'UPDATE') THEN
                INSERT INTO pemhistory.session_info (recorded_time, server_id, database_name, procpid, usename, backend_start, xact_start, query_start, is_waiting, is_idle, is_idle_in_transaction, is_vacuum, is_autovacuum, capture_time) VALUES (NEW.recorded_time, NEW.server_id, NEW.database_name, NEW.procpid, NEW.usename, NEW.backend_start, NEW.xact_start, NEW.query_start, NEW.is_waiting, NEW.is_idle, NEW.is_idle_in_transaction, NEW.is_vacuum, NEW.is_autovacuum, NEW.capture_time);
        ELSIF EXISTS(SELECT 1 FROM pem.server WHERE id = OLD.server_id) THEN
                INSERT INTO pemhistory.session_info (server_id, procpid) VALUES (OLD.server_id, OLD.procpid);
        END IF;
        RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- change made in pemserver.sql as per commit id 74d64542b750f4cb28debca6bace511426bc7c63
UPDATE pem.probe_column SET sql_data_type = 'numeric' WHERE internal_name = 'disk_busy' AND probe_id = (SELECT id FROM pem.probe WHERE internal_name = 'disk_busy_info');

ALTER TABLE pemdata.disk_busy_info ALTER COLUMN disk_busy TYPE numeric;
ALTER TABLE pemhistory.disk_busy_info ALTER COLUMN disk_busy TYPE numeric;

-- change made in pemserver.sql as per commit id 073e042c9c8a571f524a8fae7da3ed818992655b
UPDATE pem.probe_column SET display_name='System Wait Count' WHERE probe_id=(SELECT id FROM pem.probe WHERE internal_name='system_waits') AND internal_name='wait_count';
UPDATE pem.probe_column SET display_name='System Average Wait Time' WHERE probe_id=(SELECT id FROM pem.probe WHERE internal_name='system_waits') AND internal_name='avg_wait';
UPDATE pem.probe_column SET display_name='System Max Wait Time' WHERE probe_id=(SELECT id FROM pem.probe WHERE internal_name='system_waits') AND internal_name='max_wait';
UPDATE pem.probe_column SET display_name='System Total Wait Time' WHERE probe_id=(SELECT id FROM pem.probe WHERE internal_name='system_waits') AND internal_name='total_wait';
UPDATE pem.probe_column SET display_name='System Wait Name' WHERE probe_id=(SELECT id FROM pem.probe WHERE internal_name='system_waits') AND internal_name='wait_name';

-- change made in pemserver.sql as per commit id bac2f6745bb32530208ae4ab2418d228032229b2
DELETE FROM pem.probe_server_version WHERE probe_id=24 AND server_version_id=20803;
DELETE FROM pem.probe_server_version WHERE probe_id=25 AND server_version_id=20803;

UPDATE pem.probe_column SET display_name='Session Wait Count' WHERE probe_id=(SELECT id FROM pem.probe WHERE internal_name='session_waits') AND internal_name='wait_count';
UPDATE pem.probe_column SET display_name='Session Average Wait Time' WHERE probe_id=(SELECT id FROM pem.probe WHERE internal_name='session_waits') AND internal_name='avg_wait_time';
UPDATE pem.probe_column SET display_name='Session Max Wait Time' WHERE probe_id=(SELECT id FROM pem.probe WHERE internal_name='session_waits') AND internal_name='max_wait_time';
UPDATE pem.probe_column SET display_name='Session Total Wait Time' WHERE probe_id=(SELECT id FROM pem.probe WHERE internal_name='session_waits') AND internal_name='total_wait_time';
UPDATE pem.probe_column SET display_name='Session Wait Name' WHERE probe_id=(SELECT id FROM pem.probe WHERE internal_name='session_waits') AND internal_name='wait_name';

-- change made in pemserver.sql as per commit id 3bc766d28dd729c20dfc91af01233c7f2c380c7d(Auto Configure Alerts)

SELECT pem.create_alert_template(
	'Load Average per CPU Core (1 minutes)',
	'1-minute system load average per CPU core.

Probe dependency list: load_average',
	$sql$
SELECT la.loadavg1 / CASE count(cu.core_id) WHEN 0 THEN 1 ELSE count(cu.core_id) END
FROM pemdata.load_average AS la
JOIN pemdata.cpu_usage AS cu
ON la.agent_id = cu.agent_id
WHERE la.agent_id = ${agent_id}
GROUP BY la.loadavg1$sql$,
	100, NULL, NULL, NULL, NULL);

SELECT pem.create_alert_template(
	'Load Average per CPU Core (5 minutes)',
	'5-minute system load average per CPU core.

Probe dependency list: load_average',
	$sql$
SELECT la.loadavg5 / CASE count(cu.core_id) WHEN 0 THEN 1 ELSE count(cu.core_id) END
FROM pemdata.load_average AS la
JOIN pemdata.cpu_usage AS cu
ON la.agent_id = cu.agent_id
WHERE la.agent_id = ${agent_id}
GROUP BY la.loadavg5$sql$,
	100, NULL, NULL, NULL, NULL);

SELECT pem.create_alert_template(
	'Load Average per CPU Core (15 minutes)',
	'15-minute system load average per CPU core.

Probe dependency list: load_average',
	$sql$
SELECT la.loadavg15 / CASE count(cu.core_id) WHEN 0 THEN 1 ELSE count(cu.core_id) END
FROM pemdata.load_average AS la
JOIN pemdata.cpu_usage AS cu
ON la.agent_id = cu.agent_id
WHERE la.agent_id = ${agent_id}
GROUP BY la.loadavg15$sql$,
	100, NULL, NULL, NULL, NULL);

SELECT pem.create_alert_template(
	'Memory used percentage',
	'Percentage of memory used.

Probe dependency list: memory_usage',
	$sql$
SELECT (total_ram_memory_mb - free_ram_memory_mb)::float * 100
	/ CASE total_ram_memory_mb WHEN 0 THEN 1 ELSE total_ram_memory_mb END
FROM pemdata.memory_usage
WHERE agent_id = ${agent_id}$sql$,
	100, NULL, NULL, NULL, NULL);

SELECT pem.create_alert_template(
	'Most used disk percentage',
	'Percentage used of the most utilized disk on the system.

Probe dependency list: disk_space',
	$sql$
SELECT MAX(space_used_mb::float * 100 / size_mb)
FROM pemdata.disk_space
WHERE size_mb > 0
AND agent_id = ${agent_id}$sql$,
	100, NULL, NULL, NULL, NULL);

UPDATE pem.alert_template SET display_name = 'Swap consumption percentage' WHERE display_name = 'Swap consumption %age';
UPDATE pem.alert_template SET display_name = 'Total connections as percentage of max_connections' WHERE display_name = 'Total connections as %age of max_connections';
UPDATE pem.alert_template SET display_name = 'Unused, non-superuser connections as percentage of max_connections' WHERE display_name = 'Unused, non-superuser connections as %age of max_connections';
UPDATE pem.alert_template SET display_name = 'Connections in idle-in-transaction state, as a percentage of max_connections' WHERE display_name = 'Connections in idle-in-transaction state, as a %age of max_connections';
UPDATE pem.alert_template SET display_name = 'Index size as a percentage of table size' WHERE display_name = 'Index size as a %age of table size';
UPDATE pem.alert_template SET display_name = 'Largest index by table-size percentage' WHERE display_name = 'Largest index by table-size %age';

INSERT INTO pem.config (param, value) VALUES ('auto_create_agent_alerts', 't');
INSERT INTO pem.config (param, value) VALUES ('auto_create_server_alerts', 't');

CREATE OR REPLACE FUNCTION pem.check_alert_exist(alert_name text, alert_agent_id integer, alert_server_id integer,
					alert_database_name text, alert_schema_name text,
					alert_package_name text, alert_object_name text, alert_object_type integer)
RETURNS boolean AS $$
DECLARE
	is_already_exist boolean:= false;
BEGIN
	-- select alert already exist
	PERFORM id FROM pem.alert WHERE name = alert_name AND template_id = (SELECT id FROM pem.alert_template WHERE display_name = alert_name AND object_type = alert_object_type LIMIT 1)
	AND agent_id = alert_agent_id
	AND CASE WHEN alert_server_id IS NULL THEN server_id IS NULL ELSE server_id = alert_server_id END
	AND CASE WHEN alert_database_name IS NULL THEN database_name IS NULL ELSE database_name = alert_database_name END
	AND CASE WHEN alert_schema_name IS NULL THEN schema_name IS NULL ELSE schema_name = alert_schema_name END
	AND CASE WHEN alert_package_name IS NULL THEN package_name IS NULL ELSE package_name = alert_package_name END
	AND CASE WHEN alert_object_name IS NULL THEN object_name IS NULL ELSE object_name = alert_object_name END;

	IF FOUND THEN
		is_already_exist := true;
	END IF;

	RETURN is_already_exist;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION pem.auto_create_agent_alerts()
RETURNS trigger AS $$
DECLARE
	is_auto_create boolean:= false;
BEGIN
	-- select value of auto_create_agent_alerts
	SELECT value INTO is_auto_create FROM pem.config WHERE param = 'auto_create_agent_alerts';

	IF is_auto_create THEN
		IF NOT pem.check_alert_exist('Swap consumption percentage', NEW.id, NULL, NULL, NULL, NULL, NULL, 100) THEN
			PERFORM pem.create_alert('Swap consumption percentage',
			(SELECT id FROM pem.alert_template WHERE display_name = 'Swap consumption percentage' AND object_type = 100 LIMIT 1),
			NEW.id, NULL, NULL, NULL, NULL, NULL, '{}', '>', '{25, 50, 75}', 1, 30, true);
		END IF;

		IF NOT pem.check_alert_exist('Memory used percentage', NEW.id, NULL, NULL, NULL, NULL, NULL, 100) THEN
			PERFORM pem.create_alert('Memory used percentage',
			(SELECT id FROM pem.alert_template WHERE display_name = 'Memory used percentage' AND object_type = 100 LIMIT 1),
			NEW.id, NULL, NULL, NULL, NULL, NULL, '{}', '>', '{80, 90, 95}', 1, 30, true);
		END IF;

		IF NOT pem.check_alert_exist('Most used disk percentage', NEW.id, NULL, NULL, NULL, NULL, NULL, 100) THEN
			PERFORM pem.create_alert('Most used disk percentage',
			(SELECT id FROM pem.alert_template WHERE display_name = 'Most used disk percentage' AND object_type = 100 LIMIT 1),
			NEW.id, NULL, NULL, NULL, NULL, NULL, '{}', '>', '{75, 85, 95}', 1, 30, true);
		END IF;

		IF NOT pem.check_alert_exist('Load Average per CPU Core (5 minutes)', NEW.id, NULL, NULL, NULL, NULL, NULL, 100) THEN
			PERFORM pem.create_alert('Load Average per CPU Core (5 minutes)',
			(SELECT id FROM pem.alert_template WHERE display_name = 'Load Average per CPU Core (5 minutes)' AND object_type = 100 LIMIT 1),
			NEW.id, NULL, NULL, NULL, NULL, NULL, '{}', '>', '{0.7, 2.0, 5.0}', 1, 30, true);
		END IF;
	END IF;
	RETURN NEW;
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
		IF NOT pem.check_alert_exist('Total connections as percentage of max_connections', 0, NEW.server_id, NULL, NULL, NULL, NULL, 200) THEN
			PERFORM pem.create_alert('Total connections as percentage of max_connections',
			(SELECT id FROM pem.alert_template WHERE display_name = 'Total connections as percentage of max_connections' AND object_type = 200 LIMIT 1),
			0, NEW.server_id, NULL, NULL, NULL, NULL, '{}', '>', '{75, 85, 95}', 1, 30, true);
		END IF;

		IF NOT pem.check_alert_exist('Connections in idle-in-transaction state, as a percentage of max_connections', 0, NEW.server_id, NULL, NULL, NULL, NULL, 200) THEN
			PERFORM pem.create_alert('Connections in idle-in-transaction state, as a percentage of max_connections',
			(SELECT id FROM pem.alert_template WHERE display_name = 'Connections in idle-in-transaction state, as a percentage of max_connections' AND object_type = 200 LIMIT 1),
			0, NEW.server_id, NULL, NULL, NULL, NULL, '{}', '>', '{3, 5, 10}', 1, 30, true);
		END IF;

		IF NOT pem.check_alert_exist('Last AutoVacuum', 0, NEW.server_id, NULL, NULL, NULL, NULL, 200) THEN
			PERFORM pem.create_alert('Last AutoVacuum',
			(SELECT id FROM pem.alert_template WHERE display_name = 'Last AutoVacuum' AND object_type = 200 LIMIT 1),
			0, NEW.server_id, NULL, NULL, NULL, NULL, '{}', '>', '{1, 4, 12}', 1, 30, true);
		END IF;

		IF NOT pem.check_alert_exist('A user expires in N days', 0, NEW.server_id, NULL, NULL, NULL, NULL, 200) THEN
			PERFORM pem.create_alert('A user expires in N days',
			(SELECT id FROM pem.alert_template WHERE display_name = 'A user expires in N days' AND object_type = 200 LIMIT 1),
			0, NEW.server_id, NULL, NULL, NULL, NULL, '{}', '<', '{10, 5, 1}', 1, 30, true);
		END IF;
	END IF;

	RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER auto_create_agent_alerts_trigger AFTER INSERT
	ON pem.agent FOR EACH ROW
	EXECUTE PROCEDURE pem.auto_create_agent_alerts();
COMMENT ON TRIGGER auto_create_agent_alerts_trigger ON pem.agent IS 'Create some auto configured agent level alerts.';

CREATE TRIGGER auto_create_server_alerts_trigger AFTER INSERT
	ON pem.agent_server_binding FOR EACH ROW
	EXECUTE PROCEDURE pem.auto_create_server_alerts();
COMMENT ON TRIGGER auto_create_server_alerts_trigger ON pem.agent_server_binding IS 'Create some auto configured server level alerts.';

-- change made in pemserver.sql as per commit id f45326e747955b37deec0669a0db62df4e681ee2 (os_statistics probe)
INSERT INTO pem.probe
	(display_name, internal_name, collection_method, target_type_id,
	 agent_capability, enabled_by_default, force_enabled,
     default_execution_frequency, default_lifetime, any_server_version, probe_code)
VALUES
	('OS Statistics', 'os_statistics', 'i', 100, 'os_statistics', true, false, 300,
	  180, true, 'os_statistics');

INSERT INTO pem.probe_column
	(probe_id, internal_name, display_name, display_position, classification,
	sql_data_type, unit_of_value, calculate_pit, discard_history, pit_by_default)
SELECT
	(SELECT max(id) FROM pem.probe),
	v.internal_name, v.display_name, v.display_position, v.classification,
	v.sql_data_type, v.unit_of_value, v.calculate_pit, v.discard_history, v.pit_by_default
FROM
	(VALUES
		('total_process_count', 'Total Process Count', 1, 'm', 'bigint', '#', false,  false, true),
		('total_thread_count',  'Total Thread Count',  2, 'm', 'bigint', '#', false,  false, true)
	) v(internal_name, display_name, display_position, classification,
		sql_data_type, unit_of_value, calculate_pit, discard_history, pit_by_default);

SELECT pem.create_data_and_history_tables();

-- change made in linear trend functions for fix of FB CASE 19093, which requires that extrapolated values for metrics with unit '%' do not exceed 100.
-- This also contains changes for fix for FB case 19072, for which we need to send current to pl/pgsql from the pem client.

DROP FUNCTION pem.linear_trend_analysis (text, text, text, timestamp with time zone, timestamp with time zone, interval, int, varchar[], varchar[], int, int);
DROP FUNCTION pem.linear_trend_threshold (text, text, timestamp with time zone, numeric, boolean, interval, varchar[], varchar[], int, int);

CREATE OR REPLACE FUNCTION pem.linear_trend_analysis (probe_table text,
							aggregate_function text,
							probe_data_column text,
							start_time timestamp with time zone,
							end_time timestamp with time zone,
							cur_time timestamp with time zone,
							time_interval interval,
							required_points int,
							probe_target_key_list varchar[],
							probe_target_value_list varchar[],
							cutoff_count int,
							agent_id int)
RETURNS TABLE (trend_metric_time timestamp with time zone, trend_metric_value numeric)
AS $$
DECLARE
	data_timestamp timestamptz[];
	data_value numeric[];
	i int :=0;
	count int := 0;
	xa numeric := 0;
	ya numeric := 0;
	xx numeric := 0;
	xy numeric := 0;
	ma numeric := 0;
	mb numeric := 0;
	start_epoch numeric;
	end_epoch1 numeric;
	end_epoch2 numeric;
	tmpx numeric;
	tmpy numeric;
	tmpt numeric;
	tmp_val numeric;
	tmp_et1 numeric;
	tmp_row RECORD;
	tmp_time timestamp with time zone;
	percent_unit boolean;
BEGIN
	-- check if unit of metric is of type % or not. if it is then the metric bound at extrapolation should never cross 100.
	EXECUTE 'SELECT (CASE WHEN unit_of_value = ''%'' THEN true ELSE false END) FROM pem.probe_column WHERE probe_id=(SELECT id FROM pem.probe WHERE internal_name='
	|| quote_literal(probe_table) || ') AND internal_name=' || quote_literal (probe_data_column) INTO percent_unit;

	-- get current time and unix epoch for comparison sake
	SELECT EXTRACT(EPOCH FROM start_time) INTO start_epoch;
	SELECT EXTRACT(EPOCH FROM cur_time) INTO end_epoch1;
	SELECT EXTRACT(EPOCH FROM end_time) INTO end_epoch2;
	IF (end_epoch2 <= end_epoch1) THEN
		cur_time = end_time;
	END IF;

	-- get data till current time from start time from data rollup function & calculate mean of value & time interval
	-- caculating xa = sum_of(time - start_time)
	--            ya = sum_of(value)
	-- these values are returned by data_reconstruction function for given start_time to end_time
	FOR tmp_row IN SELECT metric_time, recorded_value FROM pem.data_reconstruction (probe_table, probe_data_column,
		start_time, cur_time, time_interval, probe_target_key_list, probe_target_value_list, agent_id, true)
	LOOP
		IF (NOT tmp_row.recorded_value IS NULL) THEN
			data_timestamp[count] = tmp_row.metric_time;
			data_value[count] = tmp_row.recorded_value;
			SELECT EXTRACT(EPOCH FROM tmp_row.metric_time) INTO tmpt;
			xa = xa + (tmpt - start_epoch);
			ya = ya + tmp_row.recorded_value;
			count = count + 1;
		END IF;
	END LOOP;

	-- if we have less data then generation of chart is irrelevant
	IF (count < 3) THEN
		RAISE EXCEPTION '1';
		RETURN;
	END IF;

	-- get mean
	xa = xa / count;
	ya = ya / count;

	-- compute values to get values of a & b for linear equation which is (y = a + bx)
	-- where a = intercept & b = slope
	-- b = sum_of((x(i) - xa) * (y(i) - ya)) / sum_of((x(i) - xa)^2)
	-- a = ya - (b * xa)
	-- refer http://en.wikipedia.org/wiki/Regression_analysis#Linear_regression
	-- for understanding the formula
	FOR i IN 0..(count - 1)
	LOOP
		SELECT EXTRACT(EPOCH FROM data_timestamp[i]) INTO tmpt;
		tmpx = (tmpt - start_epoch) - xa;
		IF (data_value[i] IS NULL) THEN
			tmpy = 0 - ya;
		ELSE
			tmpy = data_value[i] - ya;
		END IF;
		xx = xx + (tmpx * tmpx);
		xy = xy + (tmpx * tmpy);
	END LOOP;

	-- if slope is 0 then there is no graph may get divide by 0 error
	IF (abs(xx) = 0) THEN
		RAISE EXCEPTION '2';
		RETURN;
	END IF;

	-- get a & b value
	mb = xy / xx;
	ma = ya - (mb * xa);

	-- now apply the equation to the extrapolated data if the end time
	-- is greater than the current time, else return the currently collected
	-- data.
	IF (end_epoch2 <= end_epoch1) THEN
		IF cutoff_count != 0 THEN
			IF cutoff_count < count THEN
				count = cutoff_count;
			END IF;
		END IF;
	ELSE
		tmp_time = data_timestamp[count - 1];
		SELECT EXTRACT (EPOCH FROM tmp_time) INTO tmp_et1;
		WHILE tmp_et1 < end_epoch2
		LOOP
			tmp_time = tmp_time + time_interval;
			tmpt = (SELECT EXTRACT( EPOCH FROM tmp_time)) - start_epoch;
			tmp_val = ma + (mb * tmpt);
			IF tmp_val < 0 THEN
				data_value[count] = NULL;
			ELSE
				IF percent_unit = TRUE AND tmp_val > 100 THEN
					data_value[count] = 100;
				ELSE
					data_value[count] = tmp_val;
				END IF;
			END IF;
			data_timestamp[count] = tmp_time;
			count = count + 1;
			IF (cutoff_count != 0) THEN
				-- exit if cut off point is reached
				EXIT WHEN count >= cutoff_count;
			END IF;
			SELECT EXTRACT (EPOCH FROM tmp_time) INTO tmp_et1;
		END LOOP;
	END IF;

	RETURN QUERY EXECUTE 'SELECT agg_time AS trend_metric_time, agg_value AS trend_metric_value FROM pem.data_aggregation(' ||
			quote_literal(aggregate_function) || '::text,' || quote_literal(data_timestamp)::varchar || '::timestamptz[],' ||
			quote_literal(data_value)::varchar || '::numeric[],' || quote_literal(count) || '::int,' ||
			quote_literal(required_points) || ')';
END
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION pem.linear_trend_threshold (probe_table text,
							probe_data_column text,
							start_time timestamp with time zone,
							cur_time timestamp with time zone,
							threshold numeric,
							exceeds_opr boolean,
							time_interval interval,
							probe_target_key_list varchar[],
							probe_target_value_list varchar[],
							max_end_time_in_years int,
							agent_id int)
RETURNS int
AS $$
DECLARE
	data_timestamp timestamptz[];
	data_value numeric[];
	count int := 0;
	i int :=0;
	final_end_time timestamp with time zone;
	xa numeric := 0;
	ya numeric := 0;
	xx numeric := 0;
	xy numeric := 0;
	ma numeric := 0;
	mb numeric := 0;
	start_epoch numeric;
	end_epoch numeric;
	tmp_et numeric;
	tmpx numeric;
	tmpy numeric;
	tmpt numeric;
	tmp_last_time timestamp with time zone;
	tmp_row RECORD;
	percent_unit boolean;
BEGIN
	-- check if unit of metric is of type % or not. if it is then the metric bound at extrapolation should never cross 100.
	EXECUTE 'SELECT (CASE WHEN unit_of_value = ''%'' THEN true ELSE false END) FROM pem.probe_column WHERE probe_id=(SELECT id FROM pem.probe WHERE internal_name='
	|| quote_literal(probe_table) || ') AND internal_name=' || quote_literal (probe_data_column) INTO percent_unit;

	IF percent_unit = TRUE AND threshold > 100 THEN
		threshold = 100;
	END IF;

	-- get current time and final time is which is (x) years in future
	SELECT cur_time + (max_end_time_in_years * '1 year'::interval) INTO final_end_time;

	-- get unix epoch for comparison sake
	SELECT EXTRACT(EPOCH FROM start_time) INTO start_epoch;
	SELECT EXTRACT(EPOCH FROM final_end_time) INTO end_epoch;

	-- get data till current time from start time from data rollup function & calculate mean of value & time interval
	-- caculating xa = sum_of(time - start_time)
	--            ya = sum_of(value)
	-- these values are returned by data_rollup function for given start_time to end_time
	FOR tmp_row IN SELECT metric_time, recorded_value FROM pem.data_reconstruction (probe_table, probe_data_column,
		start_time, cur_time, time_interval, probe_target_key_list, probe_target_value_list, agent_id, true)
	LOOP
		IF (NOT tmp_row.recorded_value IS NULL) THEN
			data_timestamp[count] = tmp_row.metric_time;
			data_value[count] = tmp_row.recorded_value;
			SELECT EXTRACT(EPOCH FROM tmp_row.metric_time) INTO tmpt;
			xa = xa + (tmpt - start_epoch);
			ya = ya + tmp_row.recorded_value;
			count = count + 1;
		END IF;
	END LOOP;

	-- if we have less data then generation of chart is irrelevant
	IF (count < 3) THEN
		RAISE EXCEPTION '1';
	END IF;

	-- get mean
	xa = xa / count;
	ya = ya / count;

	-- compute values to get values of a & b for linear equation which is (y = a + bx)
	-- where a = intercept & b = slope
	-- b = sum_of((x(i) - xa) * (y(i) - ya)) / sum_of((x(i) - xa)^2)
	-- a = ya - (b * xa)
	-- refer http://en.wikipedia.org/wiki/Regression_analysis#Linear_regression
	-- for understanding the formula
	FOR i IN 0..(count - 1)
	LOOP
		SELECT EXTRACT(EPOCH FROM data_timestamp[i]) INTO tmpt;
		tmpx = (tmpt - start_epoch) - xa;
		IF (data_value[i] IS NULL) THEN
			tmpy = 0 - ya;
		ELSE
			tmpy = data_value[i] - ya;
		END IF;
		xx = xx + (tmpx * tmpx);
		xy = xy + (tmpx * tmpy);
	END LOOP;

	-- if slope is 0 then there is no graph may get divide by 0 error
	IF (abs(xx) = 0) THEN
		RAISE EXCEPTION '2';
	END IF;

	-- get a & b value
	mb = xy / xx;
	ma = ya - (mb * xa);

	-- now apply the equation to extrapolated data till you reach the
	-- given threshold or you reach the final end time.
	tmp_last_time = data_timestamp[count - 1];
	SELECT EXTRACT (EPOCH FROM tmp_last_time) INTO tmp_et;
	WHILE tmp_et < end_epoch
	LOOP
		tmp_last_time = tmp_last_time + time_interval;
		tmpt = (SELECT EXTRACT( EPOCH FROM tmp_last_time)) - start_epoch;
		tmpy = ma + (mb * tmpt);
		count = count + 1;

		IF (tmpy < 0) THEN
			RETURN count;
		END IF;

		IF (exceeds_opr = TRUE) THEN
			IF (tmpy > threshold) THEN
				RETURN count-1;
			END IF;
		ELSE
			IF (tmpy < threshold) THEN
				RETURN count-1;
			END IF;
		END IF;
		SELECT EXTRACT (EPOCH FROM tmp_last_time) INTO tmp_et;
	END LOOP;

	RETURN count-1;
END
$$ LANGUAGE plpgsql;

-- changes made to fix FB # 19047
REVOKE ALL ON DATABASE pem FROM PUBLIC;

-- changes made to fix FB #19102
UPDATE pem.alert_template SET sql = E'SELECT min(valuntil::date - capture_time::date)
				FROM pemdata.user_info
				WHERE server_id = ${server_id}
				AND valuntil IS NOT NULL
				AND valuntil NOT IN (''infinity'', ''-infinity'')
				AND valuntil > capture_time'
WHERE display_name = 'A user expires in N days';

UPDATE pem.alert_template SET sql = E'SELECT COALESCE((SELECT COUNT(*)::float * 100 / mc.setting::integer
				FROM pemdata.session_info AS si
				JOIN pemdata.settings AS mc
				ON si.server_id = mc.server_id
				AND mc.name = ''max_connections''
				WHERE si.is_idle_in_transaction IS TRUE
				AND si.server_id = ${server_id}
				AND si.database_name = ''${database_name}''
				GROUP BY mc.setting), 0)'
WHERE display_name = 'Connections in idle-in-transaction state, as a percentage of max_connections' AND object_type = 300;

UPDATE pem.alert_template SET sql = E'SELECT COALESCE((SELECT COUNT(*)::float * 100 / mc.setting::integer
				FROM pemdata.session_info AS si
				JOIN pemdata.settings AS mc
				ON si.server_id = mc.server_id
				AND mc.name = ''max_connections''
				WHERE si.is_idle_in_transaction IS TRUE
				AND si.server_id = ${server_id}
				GROUP BY mc.setting), 0)'
WHERE display_name = 'Connections in idle-in-transaction state, as a percentage of max_connections' AND object_type = 200;

CREATE OR REPLACE FUNCTION pem.get_data_directory()
RETURNS TEXT AS $$
    SELECT setting FROM pg_catalog.pg_settings WHERE name = 'data_directory';
$$ LANGUAGE sql SECURITY DEFINER;

-- Create a generic user pem_agent.
SELECT pem.create_generic_role('pem_user');

GRANT CONNECT ON DATABASE pem TO pem_user;
GRANT TEMP ON DATABASE pem TO pem_user;
GRANT USAGE on SCHEMA pem TO pem_user;
GRANT USAGE on SCHEMA pemdata TO pem_user;
GRANT USAGE on SCHEMA pemhistory TO pem_user;

GRANT SELECT ON ALL TABLES IN SCHEMA pem TO pem_user;
GRANT USAGE ON ALL SEQUENCES IN SCHEMA pem TO pem_user;
GRANT SELECT ON ALL TABLES IN SCHEMA pemdata TO pem_user;
GRANT SELECT ON ALL TABLES IN SCHEMA pemhistory TO pem_user;
GRANT INSERT, UPDATE, DELETE ON TABLE pem.server_option TO pem_user;
GRANT INSERT, UPDATE, DELETE ON TABLE pem.database_option TO pem_user;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA pem TO pem_user;
REVOKE EXECUTE ON FUNCTION pem.get_data_directory() FROM pem_user;
ALTER DEFAULT PRIVILEGES IN SCHEMA pem GRANT SELECT ON TABLES TO pem_user;
ALTER DEFAULT PRIVILEGES IN SCHEMA pem GRANT USAGE ON SEQUENCES TO pem_user;
ALTER DEFAULT PRIVILEGES IN SCHEMA pemdata GRANT SELECT ON TABLES TO pem_user;
ALTER DEFAULT PRIVILEGES IN SCHEMA pemhistory GRANT SELECT ON TABLES TO pem_user;
ALTER DEFAULT PRIVILEGES IN SCHEMA pem GRANT EXECUTE ON  FUNCTIONS TO pem_user;

GRANT pem_user TO pem_admin;
ALTER ROLE pem_admin CREATEROLE;
GRANT ALL ON SCHEMA pem TO pem_admin;
GRANT ALL ON ALL TABLES IN SCHEMA pem TO pem_admin;
GRANT ALL ON ALL FUNCTIONS IN SCHEMA pem TO pem_admin;
GRANT ALL ON ALL SEQUENCES IN SCHEMA pem TO pem_admin;
GRANT EXECUTE ON FUNCTION pem.get_data_directory() TO pem_admin;
ALTER DEFAULT PRIVILEGES IN SCHEMA pem GRANT ALL ON TABLES TO pem_admin;
ALTER DEFAULT PRIVILEGES IN SCHEMA pem GRANT ALL ON FUNCTIONS TO pem_admin;
ALTER DEFAULT PRIVILEGES IN SCHEMA pem GRANT ALL ON SEQUENCES TO pem_admin;

GRANT ALL ON SCHEMA pemdata TO pem_admin;
GRANT ALL ON ALL TABLES IN SCHEMA pemdata TO pem_admin;
GRANT ALL ON ALL FUNCTIONS IN SCHEMA pemdata TO pem_admin;
GRANT ALL ON ALL SEQUENCES IN SCHEMA pemdata TO pem_admin;
ALTER DEFAULT PRIVILEGES IN SCHEMA pemdata GRANT ALL ON TABLES TO pem_admin;
ALTER DEFAULT PRIVILEGES IN SCHEMA pemdata GRANT ALL ON FUNCTIONS TO pem_admin;
ALTER DEFAULT PRIVILEGES IN SCHEMA pemdata GRANT ALL ON SEQUENCES TO pem_admin;

GRANT ALL ON SCHEMA pemhistory TO pem_admin;
GRANT ALL ON ALL TABLES IN SCHEMA pemhistory TO pem_admin;
GRANT ALL ON ALL FUNCTIONS IN SCHEMA pemhistory TO pem_admin;
GRANT ALL ON ALL SEQUENCES IN SCHEMA pemhistory TO pem_admin;
ALTER DEFAULT PRIVILEGES IN SCHEMA pemhistory GRANT ALL ON TABLES TO pem_admin;
ALTER DEFAULT PRIVILEGES IN SCHEMA pemhistory GRANT ALL ON FUNCTIONS TO pem_admin;
ALTER DEFAULT PRIVILEGES IN SCHEMA pemhistory GRANT ALL ON SEQUENCES TO pem_admin;

GRANT CONNECT ON DATABASE pem TO pem_agent;

GRANT TEMP ON DATABASE pem TO pem_agent;
GRANT USAGE ON SCHEMA pem TO pem_agent;
GRANT USAGE ON SCHEMA pemdata TO pem_agent;
GRANT USAGE ON SCHEMA pemhistory TO pem_agent;

GRANT USAGE ON SEQUENCE pem.joblog_jlgid_seq TO pem_agent;
GRANT USAGE ON SEQUENCE pem.jobsteplog_jslid_seq TO pem_agent;

GRANT SELECT ON ALL TABLES IN SCHEMA pem TO pem_agent;
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE pem.agent_heartbeat TO pem_agent;
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE pem.agent TO pem_agent;
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE pem.alert TO pem_agent;
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE pem.alert_status TO pem_agent;
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE pem.alert_history TO pem_agent;
GRANT SELECT, DELETE ON TABLE pem.agent_server_binding TO pem_agent;
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE pem.job TO pem_agent;
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE pem.jobagent TO pem_agent;
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE pem.joblog TO pem_agent;
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE pem.jobsteplog TO pem_agent;
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE pem.probe_log TO pem_agent;
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE pem.probe_schedule TO pem_agent;
GRANT SELECT, UPDATE ON TABLE pem.server TO pem_agent;
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE pem.server_heartbeat TO pem_agent;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA pem TO pem_agent;
REVOKE EXECUTE ON FUNCTION pem.get_data_directory() FROM pem_agent;
ALTER DEFAULT PRIVILEGES IN SCHEMA pem GRANT SELECT ON TABLES TO pem_agent;
ALTER DEFAULT PRIVILEGES IN SCHEMA pem GRANT EXECUTE ON  FUNCTIONS TO pem_agent;

GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA pemdata TO pem_agent;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA pemdata TO pem_agent;
ALTER DEFAULT PRIVILEGES IN SCHEMA pemdata GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO pem_agent;
ALTER DEFAULT PRIVILEGES IN SCHEMA pemdata GRANT EXECUTE ON FUNCTIONS TO pem_agent;

GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA pemhistory TO pem_agent;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA pemhistory TO pem_agent;
ALTER DEFAULT PRIVILEGES IN SCHEMA pemhistory GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO pem_agent;
ALTER DEFAULT PRIVILEGES IN SCHEMA pemhistory GRANT EXECUTE ON FUNCTIONS TO pem_agent;

REVOKE EXECUTE ON FUNCTION pem.get_data_directory() FROM PUBLIC;

COMMIT TRANSACTION;
