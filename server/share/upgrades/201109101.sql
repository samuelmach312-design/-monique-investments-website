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

-- Upgrade script for v2.0.0 GA to v2.0.1 GA

BEGIN TRANSACTION;

CREATE OR REPLACE FUNCTION pem.schema_version()
  RETURNS integer AS
'SELECT 201109101::integer;'
  LANGUAGE 'sql' IMMUTABLE;

UPDATE pem.alert_template SET sql =
	$sql$
SELECT
    count(ps.id)
FROM
    pem.server ps LEFT OUTER JOIN pem.server_heartbeat psh ON (ps.id = psh.server_id),
    pem.agent pa LEFT OUTER JOIN pem.agent_heartbeat pah ON (pa.id = pah.agent_id),
    pem.agent_server_binding pasb
WHERE
    pa.id = pasb.agent_id AND
    ps.id = pasb.server_id AND
    pa.active = TRUE AND
    ps.active = TRUE AND
    CASE WHEN psh.agent_id IS NULL THEN FALSE ELSE psh.agent_id = pa.id END AND
    CASE WHEN pah.agent_id is NULL THEN FALSE ELSE pah.last_heartbeat > now() - (pa.heartbeat_interval)*2*'1 second'::interval END AND
    CASE WHEN psh.server_id IS NULL THEN FALSE ELSE psh.last_heartbeat < now() - (pa.heartbeat_interval)*2*'1 second'::interval END$sql$
WHERE display_name = 'Servers Down' AND object_type = 50;

UPDATE pem.alert_template SET sql =
	$sql$
SELECT
    count(pa.id)
FROM
    pem.agent pa LEFT OUTER JOIN pem.agent_heartbeat pah ON (pa.id = pah.agent_id)
WHERE
    pa.active = TRUE AND
    CASE WHEN pah.agent_id IS NULL THEN FALSE ELSE pah.last_heartbeat < now() - (pa.heartbeat_interval)*2*'1 second'::interval END$sql$
WHERE display_name = 'Agents Down' AND object_type = 50;

UPDATE pem.probe_column SET pit_by_default = true WHERE internal_name = 'numbackends' AND probe_id = (SELECT id FROM pem.probe WHERE internal_name = 'database_statistics');
UPDATE pem.probe_column SET pit_by_default = true WHERE internal_name = 'idle_backends' AND probe_id = (SELECT id FROM pem.probe WHERE internal_name = 'database_statistics');

CREATE OR REPLACE FUNCTION pem.pretty_size(size bigint)
  RETURNS text AS $$
DECLARE
  pretty_size text;
BEGIN
  RETURN CASE
			WHEN size >= 1024*1024 THEN
				 (size::float/(1024*1024))::numeric(30,2) || 'TB '
			WHEN size >= 1024 THEN
				 (size::float/1024)::numeric(30,2) || 'GB '
			ELSE
				size || 'MB '
		  END;
END;
$$ LANGUAGE plpgsql;

ALTER TABLE pem.agent_server_binding ADD COLUMN password text;
ALTER TABLE pem.agent_server_binding DROP CONSTRAINT agent_server_binding_sslmode_check;
ALTER TABLE pem.agent_server_binding ADD CONSTRAINT agent_server_binding_sslmode_check CHECK (sslmode IN ('', 'require', 'prefer', 'allow', 'disable', 'verify-ca', 'verify-full'));

-- Configuration for chart parameters. Value is in days.
INSERT INTO pem.config VALUES ('dash_server_dbsize_span', 7);
INSERT INTO pem.config VALUES ('dash_server_tabspacesize_span', 7);
INSERT INTO pem.config VALUES ('dash_server_sharedbuff_span', 7);
INSERT INTO pem.config VALUES ('dash_server_useract_span', 7);
INSERT INTO pem.config VALUES ('dash_server_global_span', 7);
INSERT INTO pem.config VALUES ('dash_server_rowact_span', 7);
INSERT INTO pem.config VALUES ('dash_server_comrol_span', 7);
INSERT INTO pem.config VALUES ('dash_memory_servmemact_span', 7);
INSERT INTO pem.config VALUES ('dash_memory_hostmemact_span', 7);
INSERT INTO pem.config VALUES ('dash_db_useract_span', 7);
INSERT INTO pem.config VALUES ('dash_db_io_span', 7);
INSERT INTO pem.config VALUES ('dash_db_rowact_span', 7);
INSERT INTO pem.config VALUES ('dash_db_comrol_span', 7);
INSERT INTO pem.config VALUES ('dash_db_hottable_rows', 25);
INSERT INTO pem.config VALUES ('dash_io_dbio_span', 7);
INSERT INTO pem.config VALUES ('dash_io_rowact_span', 7);
INSERT INTO pem.config VALUES ('dash_io_chkpt_span', 7);
INSERT INTO pem.config VALUES ('dash_io_objectio_rows', 25);
INSERT INTO pem.config VALUES ('dash_objectact_objectactivity_rows', 25);
INSERT INTO pem.config VALUES ('dash_objectact_objstorage_rows', 15);
INSERT INTO pem.config VALUES ('dash_os_cpu_span', 7);
INSERT INTO pem.config VALUES ('dash_os_memory_span', 7);
INSERT INTO pem.config VALUES ('dash_os_data_span', 7);
INSERT INTO pem.config VALUES ('dash_os_packet_span', 7);
INSERT INTO pem.config VALUES ('dash_os_traffic_span', 7);

-- Fixed Alerting FB 19710 and 19717
ALTER TABLE pem.alert_history
   ALTER COLUMN "value" DROP NOT NULL;

CREATE OR REPLACE FUNCTION pem.process_one_alert() RETURNS BOOL AS $$
DECLARE
	err					text;
	sql					text;
	acked				bool;
	state				pem.alert_state;
	sql_ret				numeric;
	alert_rec			record;
	locked_alert		bool;
	probe_disabled_err	text;
	zero_rows_err		text;
	probe_enabled		bool;
	all_probes_enabled	bool;
BEGIN
	probe_disabled_err = 'Required probe(s) ';
	zero_rows_err = 'Zero rows returned';

	locked_alert = false;

	FOR alert_rec in	SELECT al.*, ast.current_state AS state, at.sql,
								at.probe_dependency_list
						FROM (pem.alert AS al
								JOIN pem.alert_template AS at
								ON al.template_id = at.id)
						LEFT JOIN pem.alert_status AS ast
							ON(al.id = ast.alert_id)
						WHERE al.enabled = true
						-- We do not process alerts that are known erroneous
						AND (COALESCE(al.error_message, '' ) IN ('', zero_rows_err)
							OR al.error_message LIKE probe_disabled_err || '%' )
						AND (now() - COALESCE(ast.last_processed, '1900-01-01'))
							>= (al.check_frequency||'minutes')::interval
						/*
						 * We process only those alerts that are bound to
						 * 'active' agents and servers.
						 *
						 * Note:alert.agent_id, agent|server.active are defined
						 * NOT NULL.
						 */
						AND CASE WHEN al.agent_id = 0 THEN TRUE
							ELSE al.agent_id IN (SELECT id FROM pem.agent WHERE active)
							END
						AND CASE WHEN (al.server_id IS NULL) OR (al.server_id = 0) THEN TRUE
							ELSE al.server_id IN
									(SELECT id FROM pem.server WHERE active
									INTERSECT
									SELECT server_id FROM pem.agent_server_binding)
							END
						ORDER BY ast.last_processed NULLS FIRST
	LOOP
		IF (pg_try_advisory_lock(0, alert_rec.id) = true) THEN
			locked_alert = true;
			EXIT; /* the loop */
		END IF;
	END LOOP;

	/* If we couldn't find or lock any candidate alert ... */
	IF (locked_alert = false) THEN
		/* tell the caller that we didn't process any alerts */
		RETURN false;
	END IF;

	/*
	 * We should return only 'true' from here on, since there may be more alerts
	 * to process.
	 *
	 * Also try to capture any ERROR and mark the alert as invalid
	 * instead of passing that ERROR back to the caller.
	 */

	sql = alert_rec.sql;

	/* Replace any reference to hierarchy-related alert parameters */
	sql = regexp_replace(sql, E'\\${agent_id}',		COALESCE(alert_rec.agent_id::text,	'')::text, 'g');
	sql = regexp_replace(sql, E'\\${server_id}',	COALESCE(alert_rec.server_id::text,	'')::text, 'g');
	sql = regexp_replace(sql, E'\\${database_name}',COALESCE(alert_rec.database_name,	'')::text, 'g');
	sql = regexp_replace(sql, E'\\${schema_name}',	COALESCE(alert_rec.schema_name,		'')::text, 'g');
	sql = regexp_replace(sql, E'\\${package_name}',	COALESCE(alert_rec.package_name,	'')::text, 'g');
	sql = regexp_replace(sql, E'\\${object_name}',	COALESCE(alert_rec.object_name,		'')::text, 'g');

	/* Replace ${param_n} with corresponding alert parameters */
	FOR i IN 1..COALESCE(array_upper(alert_rec.params, 1), 0) LOOP
		sql = regexp_replace(sql, E'\\${param_' || i || '}', alert_rec.params[i]::text, 'g');
	END LOOP;

	err = '';

	/* Check any required probe is disabled from the probe dependency list */
	all_probes_enabled = true;
	FOR i IN 1..COALESCE(array_upper(alert_rec.probe_dependency_list, 1), 0) LOOP
		SELECT enabled INTO probe_enabled FROM pem.probe_target_view WHERE probe_internal_name = alert_rec.probe_dependency_list[i]
		AND CASE WHEN applies_to_id = 100 THEN (agent_id = alert_rec.agent_id)
			WHEN applies_to_id = 200 THEN (server_id = alert_rec.server_id)
			ELSE (server_id = alert_rec.server_id AND database_name = alert_rec.database_name)
			END;
		IF NOT probe_enabled THEN
			probe_disabled_err = probe_disabled_err || alert_rec.probe_dependency_list[i] || ',';
			all_probes_enabled = false;
		END IF;
	END LOOP;
	probe_disabled_err = trim(trailing ',' from probe_disabled_err);
	probe_disabled_err = probe_disabled_err || ' are disabled.';

	IF NOT all_probes_enabled THEN
		err = probe_disabled_err;
	ELSE
		RAISE DEBUG 'Alert query being executed: %', sql;

		BEGIN
			EXECUTE sql INTO STRICT sql_ret;
		EXCEPTION
			WHEN no_data_found THEN
				IF all_probes_enabled THEN
					err = zero_rows_err;
				END IF;

			WHEN OTHERS THEN
				err = SQLERRM;
		END;
	END IF;

	-- If there was an error while processing the alert's sql
	IF (err <> '') THEN
		-- Set that error message on the alert
		UPDATE pem.alert
		SET error_message = err
		WHERE id = alert_rec.id;

		-- ... and also set the last processed timestamp
		UPDATE pem.alert_status
		SET last_processed = now()
		WHERE alert_id = alert_rec.id;

		-- If there wasn't any row for this alert already, then populate one.
		IF (NOT FOUND) THEN
			INSERT INTO pem.alert_status
			VALUES (alert_rec.id, NULL, NULL, NULL, now());
		END IF;

		-- RAISE NOTICE 'Encountered error while processing SQL: %', err;

		/*
		 * XXX: There's a small window of race condition here. Another transaction
		 * might pick up processing of this alert immediately after we unlock it
		 * below using non-transactional advisory lock.
		 *
		 * Someday consider trading this for transactional advisory locks. This
		 * will be possible when we mandate PG 9.1 as a minimum requirement.
		 */
		PERFORM pg_advisory_unlock(0, alert_rec.id);

		RETURN true;
	ELSE
		-- Set that error message to NULL on the alert if the SQL executes successfully
		UPDATE pem.alert
		SET error_message = NULL
		WHERE id = alert_rec.id;
	END IF;

	/* Some sample alerts
		Table size:  1GB => low, 2GB => med, 5GB => high

		>5 high
		>2 med
		>1 low

		operator: > ; thresholds: {1,2,5}

		current_connections : 50 => low, 20 => med, 5 => high

		<5 high
		<20 med
		<50 low

		operator: < ; thresholds: {50,20,5}
	 */

	IF (alert_rec.operator = '<') THEN
		IF (sql_ret < alert_rec.thresholds[3]) THEN
			state = 'HIGH';
		ELSIF (sql_ret < alert_rec.thresholds[2]) THEN
			state = 'MEDIUM';
		ELSIF (sql_ret < alert_rec.thresholds[1]) THEN
			state = 'LOW';
		ELSE
			state = NULL;
		END IF;
	ELSIF (alert_rec.operator = '>') THEN
		IF (sql_ret > alert_rec.thresholds[3]) THEN
			state = 'HIGH';
		ELSIF (sql_ret > alert_rec.thresholds[2]) THEN
			state = 'MEDIUM';
		ELSIF (sql_ret > alert_rec.thresholds[1]) THEN
			state = 'LOW';
		ELSE
			state = NULL;
		END IF;
	END IF;

	/*
	 * For an alert that is active (state IS NOT NULL), we do not want to clear
	 * its 'acknowledged' flag the first time it goes lower than LOW. So we wait
	 * for another round of check, and if it still appears lower than LOW, then
	 * we reset its acknowledged flag.
	 *
	 * The pseudo-code is:
	 *
	 * if (acked = true)
	 *     if current severity_level is null and previous/stored severity_level is null
	 *        set acked = false
	 *
	 *     if severity_level increases or changed from null to not-null
	 *         set acked = false
	 *
	 *     If severity_level decreases or goes from not-null to null
	 *         do nothing.
	 * end if
	 */
	IF (alert_rec.acknowledged) THEN

		acked = true;

		IF (state IS NULL AND alert_rec.state IS NULL) THEN
			-- State has been lower than LOW, two times in a row.
			acked = false;
		END IF;

		IF ((alert_rec.state IS NULL AND state IS NOT NULL)
			OR (state > alert_rec.state))
		THEN
			-- Severity has increased
			acked = false;
		END IF;

		IF ((alert_rec.state IS NOT NULL AND state IS NULL)
			OR (state < alert_rec.state))
		THEN
			/*
			 * Severity decreased, or went to NULL for the first time so don't
			 * clear the acked flag
			 */
			NULL;
		END IF;
	ELSE
		acked = false;
	END IF;

	IF (acked <> alert_rec.acknowledged)
	THEN
		-- The state changed, or acked flag changed
		UPDATE pem.alert
		SET acknowledged = acked
		WHERE id = alert_rec.id;
	END IF;

	UPDATE pem.alert_status
	SET last_processed = now(),
		current_value = sql_ret,
		current_state = state, -- may be NULL
		current_state_since =	CASE
								WHEN state IS DISTINCT FROM alert_rec.state
								THEN now()
								ELSE current_state_since
								END
	WHERE alert_id = alert_rec.id;

	-- If there wasn't any status row for this alert already, then populate one.
	IF (NOT FOUND) THEN
		INSERT INTO pem.alert_status
		VALUES (alert_rec.id, sql_ret, state,
				CASE
				WHEN state IS NOT NULL
				THEN now()
				ELSE NULL
				END,
				now());
	END IF;

	PERFORM pg_advisory_unlock(0, alert_rec.id);
	RETURN true;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION pem.startup(server_desc text, server_name text, server_host text, server_port int, server_database text, server_ssl int,
					user_name text, passwd text, ser_group text, agentid int, agent_database text)
  RETURNS void AS
$BODY$
DECLARE
	job_id integer;
	serverid integer;
	active_state boolean;
	name text;
BEGIN
    -- Default serverid
    serverid := 1;

    -- Check the server entry is already exist.
    SELECT active INTO active_state FROM pem.server WHERE id = serverid;

    -- if entry not found or server with id serverid is already exist and server is active then add new server.
    IF (NOT FOUND) OR (active_state = 't') THEN
        -- Create entry of PEM server in pem.server table.
        INSERT INTO pem.server (description, server, port, database, ssl) VALUES (server_desc, server_name, server_port, server_database, server_ssl) RETURNING id INTO serverid;

        -- Set the options of the PEM server
        INSERT INTO pem.server_option (server_id, pem_user, username, server_group) VALUES (serverid, user_name, user_name, ser_group);
    ELSE
        UPDATE pem.server SET description = server_desc, server = server_name, port = server_port, database = server_database, ssl = server_ssl, active = 't' WHERE id = serverid;

        UPDATE pem.server_option SET pem_user = user_name, username = user_name, server_group = ser_group WHERE server_id = serverid;
    END IF;

    -- Create Agent Server Binding
    INSERT INTO pem.agent_server_binding (agent_id, server_id, server, port, username, database, password) VALUES (agentid, serverid, server_host, server_port, user_name, agent_database, passwd);


    -- Check the job is already exist.
    SELECT jobid INTO job_id FROM pem.job WHERE jobname = 'Database cleanup' AND agent_id = agentid;

    IF (NOT FOUND) THEN
        -- Create data purging job.
        INSERT INTO pem.job(jobname, jobdesc, agent_id) VALUES('Database cleanup', 'This job runs periodically to purge old data from the database.', agentid) RETURNING jobid INTO job_id;
    END IF;

    -- Check the job step is already exist.
    SELECT jstname INTO name FROM pem.jobstep WHERE jstname = 'Database cleanup' AND jstjobid = job_id;

    IF (NOT FOUND) THEN
        -- Create data purging step.
        INSERT INTO pem.jobstep(jstjobid, jstname, jstdesc, jstkind, jstcode, server_id, database_name) VALUES (job_id, 'Database cleanup','This job step runs periodically to purge old data from the database.', 's',
        'SELECT pem.purge_data()', serverid, 'pem');
    END IF;

    -- Check the job schedule is already exist.
    SELECT jscname INTO name FROM pem.schedule WHERE jscname = 'Database cleanup' AND jscjobid = job_id;

    IF (NOT FOUND) THEN
        -- Create data purging schedule.
        INSERT INTO pem.schedule(jscjobid, jscname, jscdesc, jscminutes, jschours, jscweekdays, jscmonthdays, jscmonths) VALUES(job_id, 'Database cleanup', 'This job schedule runs periodically to purge old data from the database.', 	'{t,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f}', '{t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t}','{t,t,t,t,t,t,t}',
        '{t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t}', '{t,t,t,t,t,t,t,t,t,t,t,t}');
    END IF;
END;
$BODY$ LANGUAGE plpgsql;

-- Fixed FB 19877 Checkpoint completion target issue.
CREATE OR REPLACE FUNCTION pem.pe_rule_checkpoint_completion_target(serverID int, rulename text) RETURNS BOOLEAN
AS $$
DECLARE
	checkpoint_completion_target_val decimal:= 0;
	severity_val int:= 0;
	data_name_arr text[];
	data_value_arr text[];

BEGIN
	-- Get the value of checkpoint_completion_target from pemdata.settings table.
	SELECT setting INTO checkpoint_completion_target_val FROM pemdata.settings WHERE name = 'checkpoint_completion_target' AND server_id = serverID;

	IF (checkpoint_completion_target_val != 0.9) THEN
		severity_val := 5;

		data_name_arr[0] := 'checkpoint_completion_target';
		data_value_arr[0] := checkpoint_completion_target_val;

		-- Update the values of data_name , data_value and severity
		UPDATE temp_expert_records SET data_name = data_name_arr, data_value = data_value_arr, severity = severity_val WHERE rule_name = rulename AND server_id = serverID ;
	ELSE
		DELETE FROM temp_expert_records WHERE rule_name = rulename AND server_id = serverID ;
	END IF;

	RETURN TRUE;
END
$$ LANGUAGE plpgsql;

COMMIT TRANSACTION;
