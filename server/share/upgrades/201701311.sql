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
'SELECT 201701311::integer;'
  LANGUAGE 'sql' IMMUTABLE;
COMMENT ON FUNCTION pem.schema_version() IS 'Returns the version number of the PEM schema';

CREATE OR REPLACE FUNCTION pem.current_user_id()
  RETURNS oid AS $$
SELECT oid FROM pg_catalog.pg_roles WHERE rolname=current_user$$ LANGUAGE SQL;

-- Table: pem.user_server_group
CREATE TABLE pem.user_server_group
(
  id     int  NOT NULL,
  uid    oid  NOT NULL DEFAULT pem.current_user_id(),
  name   text NOT NULL,
  hidden boolean NOT NULL DEFAULT false,
  CONSTRAINT user_server_group_pk PRIMARY KEY (id, uid),
  CONSTRAINT user_server_group_id_fk FOREIGN KEY (id) REFERENCES pem.server_group(id)
    MATCH SIMPLE ON UPDATE CASCADE ON DELETE CASCADE INITIALLY DEFERRED
);

GRANT ALL ON TABLE pem.user_server_group TO pem_user;
GRANT ALL ON TABLE pem.user_server_group TO pem_admin;

-- UPDATE the duplicate server_group in one
WITH s_groups AS (
    SELECT
        ids[1] min_id,
        CASE
        WHEN array_upper(ids, 1) > 1 THEN ids[2:array_upper(ids, 1)]
        ELSE '{}'::int[]
        END AS rest
    FROM (
        SELECT array_agg(id) ids
        FROM (
            SELECT id, name FROM pem.server_group ORDER BY id
        ) sg GROUP BY name
    ) a
)
UPDATE pem.server_option SET server_group_id = s_groups.min_id
FROM s_groups WHERE pem.server_option.server_group_id = ANY(s_groups.rest);

-- DELETE duplicate server_groups
WITH s_groups AS (
    SELECT unnest(rest) AS id
    FROM (
        SELECT
            CASE
            WHEN array_upper(ids, 1) > 1 THEN ids[2:array_upper(ids, 1)]
            ELSE '{}'::int[]
            END AS rest
        FROM (
            SELECT array_agg(id) ids
            FROM (
                SELECT id, name FROM pem.server_group ORDER BY id
            ) sg GROUP BY name
        ) a
    ) b
)
DELETE FROM pem.server_group WHERE id IN (SELECT id FROM s_groups);

CREATE OR REPLACE FUNCTION pem.create_server_group(_name text)
RETURNS integer AS
$$
DECLARE
    gid integer;
    hidden bool;
BEGIN
    SELECT s.id, s.hidden INTO gid, hidden FROM pem.user_server_group s WHERE s.name = _name;

    IF gid IS NOT NULL THEN
        IF hidden THEN
            UPDATE pem.user_server_group SET hidden = FALSE WHERE id = gid;
        END IF;
        RETURN gid;
    ELSE
        SELECT s.id INTO gid FROM pem.server_group s WHERE s.name = _name;

        IF gid IS NULL THEN
            INSERT INTO pem.server_group(name) VALUES (_name) RETURNING id INTO gid;
        END IF;
        RETURN gid;
    END IF;
END$$ LANGUAGE 'plpgsql';

CREATE OR REPLACE FUNCTION pem.rename_server_group(_id integer, _name text)
RETURNS integer AS
$$
DECLARE
    v_gid integer;
    v_hidden bool;
    v_uid oid := current_user::regrole::oid;
BEGIN
    -- Server group name already exists for the user!
    SELECT s.id INTO v_gid FROM pem.user_server_group s
    WHERE s.name = _name AND s.uid = v_uid;

    IF FOUND THEN
        RETURN -2;
    END IF;

    SELECT s.id INTO v_gid FROM pem.server_group s WHERE s.name = _name AND
    NOT EXISTS(
        SELECT g.id FROM pem.user_server_group g
        WHERE g.id = s.id AND g.uid = v_uid
    );

    -- Already present!
    IF FOUND THEN
        RETURN -3;
    END IF;

    SELECT s.hidden INTO v_hidden FROM pem.user_server_group s
    WHERE s.id = _id AND s.uid = v_uid;

    IF FOUND THEN
        IF v_hidden THEN
            -- Can't change deleted!
            RETURN -1;
        END IF;
        SELECT id INTO v_gid FROM pem.server_group
        WHERE id = _id AND name = _name;

        IF FOUND THEN
            DELETE FROM pem.user_server_group WHERE id = _id AND uid = v_uid;
        ELSE
            UPDATE pem.user_server_group SET name = _name WHERE id = _id;
        END IF;
        RETURN 0;
    END IF;

    INSERT INTO pem.user_server_group (id, name) VALUES (_id, _name);
    RETURN 0;

END$$ LANGUAGE 'plpgsql';

CREATE OR REPLACE FUNCTION pem.delete_server_group(_id integer)
RETURNS integer AS
$$
DECLARE
    v_name text;
    v_hidden bool;
    v_cnt integer;
    v_uid oid := pem.current_user_id();
BEGIN
    SELECT hidden INTO v_hidden FROM pem.user_server_group WHERE id = _id AND uid = v_uid;

    IF FOUND THEN
        IF v_hidden THEN
            RETURN -1;
        END IF;

        SELECT count(*) INTO v_cnt FROM pem.server_option
        WHERE server_group_id = _id;

        IF v_cnt > 0 THEN
            UPDATE pem.user_server_group SET hidden = TRUE
            WHERE id = _id AND uid = v_uid;
        ELSE
            UPDATE pem.user_server_group SET hidden = TRUE
            WHERE id = _id AND uid = v_uid;
        END IF;
    END IF;

    INSERT INTO pem.user_server_group(id, name, hidden)
    SELECT s.id, s.name, TRUE FROM pem.server_group s WHERE s.id = _id;
    RETURN 0;
END$$ LANGUAGE 'plpgsql';

-- We don't need this column in server_group.
-- It has been moved to the pem.user_server_group table.
ALTER TABLE pem.server_group DROP COLUMN pem_user;

-- Modified package_download_chunk_size from 1KB to 1MB
UPDATE pem.config SET value = 1048576 WHERE param = 'package_download_chunk_size';


-- This function will be called by server installer at the time of installation. This function add the PEM Server to the directory,
-- bind it to the default agent, and create the job for data purging.
--
-- NOTE: Even though - we do have new startup function to save the agen-server binding password.
--       We will have to keep this function to support the pemagent-2.0.0.


CREATE OR REPLACE FUNCTION pem.startup(server_desc text, server_name text, server_host text, server_port int, server_database text, server_ssl int,
					user_name text, ser_group text, agentid int, agent_database text)
  RETURNS void AS
$BODY$
DECLARE
	job_id    integer;
	sg_id     integer;
	serverid  integer := 1;
	is_active boolean;
	name      text;
	tmpid     integer;
	dbname    text := current_database();
	probe_curs CURSOR FOR SELECT id, display_name FROM pem.probe
		WHERE NOT discard_history AND jstid IS NULL;
BEGIN

    -- Check if the server group already exists.
    SELECT id INTO sg_id FROM pem.server_group sg WHERE sg.name = ser_group;

    IF (NOT FOUND) THEN
        -- Create new server group
        INSERT INTO pem.server_group(name, pem_user) VALUES(ser_group,  user_name) RETURNING id INTO sg_id;
    END IF;


    -- Check the server entry is already exist.
    SELECT active INTO is_active FROM pem.server WHERE id = serverid;

    -- if entry not found or server with id serverid is already exist and server is active then add new server.
    IF (NOT FOUND) OR is_active THEN
        -- Create entry of PEM server in pem.server table.
        INSERT INTO pem.server (description, server, port, database, ssl) VALUES (server_desc, server_name, server_port, server_database, server_ssl) RETURNING id INTO serverid;

        -- Set the options of the PEM server
        INSERT INTO pem.server_option (server_id, pem_user, username, server_group_id) VALUES (serverid, user_name, user_name, sg_id);
    ELSE
        UPDATE pem.server SET description = server_desc, server = server_name, port = server_port, database = server_database, ssl = server_ssl, active = 't' WHERE id = serverid;

        UPDATE pem.server_option SET pem_user = user_name, username = user_name, server_group_id = sg_id WHERE server_id = serverid;
    END IF;

    -- Create Agent Server Binding
    INSERT INTO pem.agent_server_binding (agent_id, server_id, server, port, username, database) VALUES (agentid, serverid, server_host, server_port, user_name, agent_database);


    -- Check if the job already exists.
    SELECT jobid INTO job_id FROM pem.job WHERE jobname = 'Database cleanup' AND agent_id = agentid;

    IF (NOT FOUND) THEN
        -- Create data purging job.
        INSERT INTO pem.job(jobname, jobdesc, agent_id, issystemjob) VALUES('Database cleanup', 'This job runs periodically to purge old data from the database.', agentid, true) RETURNING jobid INTO job_id;
    END IF;

    -- Check if the job step already exists.
    SELECT jstid INTO tmpid FROM pem.jobstep WHERE jstname = 'Database cleanup' AND jstjobid = job_id;

    IF (NOT FOUND) THEN
        -- Create data purging step.
        INSERT INTO pem.jobstep(
            jstjobid, jstname, jstenabled, jstdesc, jstkind, jstcode,
            server_id, database_name
        ) VALUES (
            job_id, 'Database cleanup', false,
            'This job step runs periodically to purge old data from the database.',
            's', 'SELECT pem.purge_data()',
            serverid, dbname
        );
    ELSE
        UPDATE pem.jobstep SET jstenabled = False
        WHERE jstjobid = job_id AND jstid = tmpid;
    END IF;

    -- Check if the job schedule already exists.
    SELECT jscid INTO tmpid FROM pem.schedule WHERE jscname = 'Database cleanup' AND jscjobid = job_id;

    IF (NOT FOUND) THEN
        -- Create data purging schedule.
        INSERT INTO pem.schedule(
            jscjobid, jscname, jscdesc,
            jscminutes, jschours, jscmonths, jscweekdays,
            jscmonthdays
        ) VALUES(
            job_id, 'Database cleanup', 'This job schedule runs periodically to purge old data from the database.',
            '{t,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f}',
            '{f,t,f,f,f,t,f,f,f,t,f,f,f,t,f,f,f,t,f,f,f,t,f,f}',
            '{t,t,t,t,t,t,t,t,t,t,t,t}', '{t,t,t,t,t,t,t}',
            '{t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t}');
    ELSE
        UPDATE pem.schedule SET
            jschours = '{f,t,f,f,f,t,f,f,f,t,f,f,f,t,f,f,f,t,f,f,f,t,f,f}',
            jscmonthdays = '{t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t}'
        WHERE
            jscjobid = job_id AND jscid = tmpid;
    END IF;

    -- check if the job already exists.
    SELECT jobid INTO job_id FROM pem.job WHERE jobname = 'Update the probe-objects combination' AND agent_id = agentid;

    IF (NOT FOUND) THEN
        --
        -- Generate the update probe-objects combination job
        -- it will run 10 minutes after installation.
        --
        -- Let agent fetch the information about the server, and host-machine
        -- to  determine the actual probes to run, which generates actual
        -- combination.
        INSERT INTO pem.job(
            jobname, jobdesc, agent_id, issystemjob, jobnextrun
        ) VALUES (
            'Update the probe-objects combination',
            'This job updates/inserts the record of the probe, parameter_value_list in the ''pem.probe_objects_combo'' table.',
            agentid, true, now() + interval '10 minutes'
        ) RETURNING jobid INTO job_id;
    END IF;

    -- check if the job step already exists.
    SELECT jstid INTO tmpid FROM pem.jobstep WHERE jstname = 'Update the probe-objects combination' AND jstjobid = job_id;

    IF (NOT FOUND) THEN
        INSERT INTO pem.jobstep(
            jstjobid, jstname, jstdesc, jstkind, jstcode,
            server_id, database_name
        ) VALUES (
            job_id, 'Database cleanup',
            'This job step updates the purge-job tasks on demand.',
            's', 'SELECT pem.create_update_probe_objects_combo()',
            serverid, dbname
        );
    ELSE
        UPDATE pem.jobstep SET jstenabled = TRUE
        WHERE jstid = tmpid AND jstjobid = job_id;
    END IF;

    -- Check if the job already exists.
    SELECT jobid INTO job_id FROM pem.job WHERE jobname = 'Audit log table cleanup' AND agent_id = agentid;

    IF (NOT FOUND) THEN
        -- Create data purging job.
        INSERT INTO pem.job(jobname, jobdesc, agent_id, issystemjob) VALUES('Audit log table cleanup', 'This job runs periodically to purge old data from the audit log table.', agentid, true) RETURNING jobid INTO job_id;
    END IF;

    -- Check if the job step already exists.
    SELECT jstname INTO name FROM pem.jobstep WHERE jstname = 'Audit log table cleanup' AND jstjobid = job_id;

    IF (NOT FOUND) THEN
        -- Create data purging step.
        INSERT INTO pem.jobstep(jstjobid, jstname, jstdesc, jstkind, jstcode, server_id, database_name) VALUES (job_id, 'Audit log table cleanup','This job step runs periodically to purge old data from the audit log table.', 's',
            'SELECT pem.purge_audit_log()', serverid, dbname);
    END IF;

    -- Check if the job schedule already exists.
    SELECT jscname INTO name FROM pem.schedule WHERE jscname = 'Audit log table cleanup' AND jscjobid = job_id;

    IF (NOT FOUND) THEN
        -- Create data purging schedule.
        INSERT INTO pem.schedule(jscjobid, jscname, jscdesc, jscminutes, jschours, jscweekdays, jscmonthdays, jscmonths) VALUES(job_id, 'Audit log table cleanup', 'This job schedule runs periodically to purge old data from the audit log table.', '{t,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f}', '{t,f,f,f,f,f,f,f,f,f,f,f,t,f,f,f,f,f,f,f,f,f,f,f}','{t,t,t,t,t,t,t}', '{t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t}', '{t,t,t,t,t,t,t,t,t,t,t,t}');
    END IF;

    -- Check if the job already exists.
    SELECT jobid INTO job_id FROM pem.job WHERE jobname = 'Server log table cleanup' AND agent_id = agentid;

    IF (NOT FOUND) THEN
        -- Create data purging job.
        INSERT INTO pem.job(jobname, jobdesc, agent_id, issystemjob) VALUES('Server log table cleanup', 'This job runs periodically to purge old data from the server log table.', agentid, true) RETURNING jobid INTO job_id;
    END IF;

    -- Check if the job step already exists.
    SELECT jstname INTO name FROM pem.jobstep WHERE jstname = 'Server log table cleanup' AND jstjobid = job_id;

    IF (NOT FOUND) THEN
        -- Create data purging step.
        INSERT INTO pem.jobstep(jstjobid, jstname, jstdesc, jstkind, jstcode, server_id, database_name) VALUES (job_id, 'Server log table cleanup','This job step runs periodically to purge old data from the server log table.', 's',
        'SELECT pem.purge_server_log()', serverid, dbname);
    END IF;

    -- Check if the job schedule already exists.
    SELECT jscname INTO name FROM pem.schedule WHERE jscname = 'Server log table cleanup' AND jscjobid = job_id;

    IF (NOT FOUND) THEN
        -- Create data purging schedule.
        INSERT INTO pem.schedule(jscjobid, jscname, jscdesc, jscminutes, jschours, jscweekdays, jscmonthdays, jscmonths) VALUES(job_id, 'Server log table cleanup', 'This job schedule runs periodically to purge old data from the server log table.', '{t,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f}', '{f,t,f,f,f,f,f,f,f,f,f,f,f,t,f,f,f,f,f,f,f,f,f,f}','{t,t,t,t,t,t,t}', '{t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t}', '{t,t,t,t,t,t,t,t,t,t,t,t}');
    END IF;

    -- Check if the job already exists.
    SELECT jobid INTO job_id FROM pem.job WHERE jobname = 'Probe log table cleanup' AND agent_id = agentid;

    IF (NOT FOUND) THEN
        -- Create data purging job.
        INSERT INTO pem.job(jobname, jobdesc, agent_id, issystemjob) VALUES('Probe log table cleanup', 'This job runs periodically to purge old data from the probe log table.', agentid, true) RETURNING jobid INTO job_id;
    END IF;

    -- Check if the job step already exists.
    SELECT jstname INTO name FROM pem.jobstep WHERE jstname = 'Probe log table cleanup' AND jstjobid = job_id;

    IF (NOT FOUND) THEN
        -- Create data purging step.
        INSERT INTO pem.jobstep(jstjobid, jstname, jstdesc, jstkind, jstcode, server_id, database_name) VALUES (job_id, 'Probe log table cleanup','This job step runs periodically to purge old data from the probe log table.', 's',
        'SELECT pem.purge_probe_log()', serverid, dbname);
    END IF;

    -- Check if the job schedule already exists.
    SELECT jscname INTO name FROM pem.schedule WHERE jscname = 'Probe log table cleanup' AND jscjobid = job_id;

    IF (NOT FOUND) THEN
        -- Create data purging schedule.
        INSERT INTO pem.schedule(jscjobid, jscname, jscdesc, jscminutes, jschours, jscweekdays, jscmonthdays, jscmonths) VALUES(job_id, 'Probe log table cleanup', 'This job schedule runs periodically to purge old data from the probe log table.', '{t,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f}', '{f,f,t,f,f,f,f,f,f,f,f,f,f,f,t,f,f,f,f,f,f,f,f,f}','{t,t,t,t,t,t,t}', '{t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t}', '{t,t,t,t,t,t,t,t,t,t,t,t}');
    END IF;

    -- Check if the job already exists.
    SELECT jobid INTO job_id FROM pem.job WHERE jobname = 'SMTP spool table cleanup' AND agent_id = agentid;

    IF (NOT FOUND) THEN
        -- Create data purging job.
        INSERT INTO pem.job(jobname, jobdesc, agent_id, issystemjob) VALUES('SMTP spool table cleanup', 'This job runs periodically to purge old data from the smtp spool table.', agentid, true) RETURNING jobid INTO job_id;
    END IF;

    -- Check if the job step already exists.
    SELECT jstname INTO name FROM pem.jobstep WHERE jstname = 'SMTP spool table cleanup' AND jstjobid = job_id;

    IF (NOT FOUND) THEN
        -- Create data purging step.
        INSERT INTO pem.jobstep(jstjobid, jstname, jstdesc, jstkind, jstcode, server_id, database_name) VALUES (job_id, 'SMTP spool table cleanup','This job step runs periodically to purge old data from the smtp spool table.', 's',
        'SELECT pem.purge_smtp_spool()', serverid, dbname);
    END IF;

    -- Check if the job schedule already exists.
    SELECT jscname INTO name FROM pem.schedule WHERE jscname = 'SMTP spool table cleanup' AND jscjobid = job_id;

    IF (NOT FOUND) THEN
        -- Create data purging schedule.
        INSERT INTO pem.schedule(jscjobid, jscname, jscdesc, jscminutes, jschours, jscweekdays, jscmonthdays, jscmonths) VALUES(job_id, 'SMTP spool table cleanup', 'This job schedule runs periodically to purge old data from the smtp spool table.', '{t,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f}', '{f,f,f,t,f,f,f,f,f,f,f,f,f,f,f,t,f,f,f,f,f,f,f,f}','{t,t,t,t,t,t,t}', '{t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t}', '{t,t,t,t,t,t,t,t,t,t,t,t}');
    END IF;

    -- Check if the job already exists.
    SELECT jobid INTO job_id FROM pem.job WHERE jobname = 'SNMP spool table cleanup' AND agent_id = agentid;

    IF (NOT FOUND) THEN
        -- Create data purging job.
        INSERT INTO pem.job(jobname, jobdesc, agent_id, issystemjob) VALUES('SNMP spool table cleanup', 'This job runs periodically to purge old data from the snmp spool table.', agentid, true) RETURNING jobid INTO job_id;
    END IF;

    -- Check if the job step already exists.
    SELECT jstname INTO name FROM pem.jobstep WHERE jstname = 'SNMP spool table cleanup' AND jstjobid = job_id;

    IF (NOT FOUND) THEN
        -- Create data purging step.
        INSERT INTO pem.jobstep(jstjobid, jstname, jstdesc, jstkind, jstcode, server_id, database_name) VALUES (job_id, 'SNMP spool table cleanup','This job step runs periodically to purge old data from the snmp spool table.', 's',
        'SELECT pem.purge_snmp_spool()', serverid, dbname);
    END IF;

    -- Check if the job schedule already exists.
    SELECT jscname INTO name FROM pem.schedule WHERE jscname = 'SNMP spool table cleanup' AND jscjobid = job_id;

    IF (NOT FOUND) THEN
        -- Create data purging schedule.
        INSERT INTO pem.schedule(jscjobid, jscname, jscdesc, jscminutes, jschours, jscweekdays, jscmonthdays, jscmonths) VALUES(job_id, 'SNMP spool table cleanup', 'This job schedule runs periodically to purge old data from the snmp spool table.', '{t,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f}', '{f,f,f,f,t,f,f,f,f,f,f,f,f,f,f,f,t,f,f,f,f,f,f,f}','{t,t,t,t,t,t,t}', '{t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t}', '{t,t,t,t,t,t,t,t,t,t,t,t}');
    END IF;

    -- Check if the job already exists.
    SELECT jobid INTO job_id FROM pem.job WHERE jobname = 'Alert history table cleanup' AND agent_id = agentid;

    IF (NOT FOUND) THEN
        -- Create data purging job.
        INSERT INTO pem.job(jobname, jobdesc, agent_id, issystemjob) VALUES('Alert history table cleanup', 'This job runs periodically to purge old data from the alert history table.', agentid, true) RETURNING jobid INTO job_id;
    END IF;

    -- Check if the job step already exists.
    SELECT jstname INTO name FROM pem.jobstep WHERE jstname = 'Alert history table cleanup' AND jstjobid = job_id;

    IF (NOT FOUND) THEN
        -- Create data purging step.
        INSERT INTO pem.jobstep(jstjobid, jstname, jstdesc, jstkind, jstcode, server_id, database_name) VALUES (job_id, 'Alert history table cleanup','This job step runs periodically to purge old data from the alert history table.', 's',
        'SELECT pem.purge_alert_history()', serverid, dbname);
    END IF;

    -- Check if the job schedule already exists.
    SELECT jscname INTO name FROM pem.schedule WHERE jscname = 'Alert history table cleanup' AND jscjobid = job_id;

    IF (NOT FOUND) THEN
        -- Create data purging schedule.
        INSERT INTO pem.schedule(jscjobid, jscname, jscdesc, jscminutes, jschours, jscweekdays, jscmonthdays, jscmonths) VALUES(job_id, 'Alert history table cleanup', 'This job schedule runs periodically to purge old data from the alert history table.', '{t,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f}', '{f,f,f,f,f,t,f,f,f,f,f,f,f,f,f,f,f,t,f,f,f,f,f,f}','{t,t,t,t,t,t,t}', '{t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t}', '{t,t,t,t,t,t,t,t,t,t,t,t}');
    END IF;

    -- Check if the job already exists.
    SELECT jobid INTO job_id FROM pem.job WHERE jobname = 'Job log table cleanup' AND agent_id = agentid;

    IF (NOT FOUND) THEN
        -- Create data purging job.
        INSERT INTO pem.job(jobname, jobdesc, agent_id, issystemjob) VALUES('Job log table cleanup', 'This job runs periodically to purge old data from the job log table.', agentid, true) RETURNING jobid INTO job_id;
    END IF;

    -- Check if the job step already exists.
    SELECT jstname INTO name FROM pem.jobstep WHERE jstname = 'Job log table cleanup' AND jstjobid = job_id;

    IF (NOT FOUND) THEN
        -- Create data purging step.
        INSERT INTO pem.jobstep(jstjobid, jstname, jstdesc, jstkind, jstcode, server_id, database_name) VALUES (job_id, 'Job log table cleanup','This job step runs periodically to purge old data from the job log table.', 's',
        'SELECT pem.purge_job_log()', serverid, dbname);
    END IF;

    -- Check if the job schedule already exists.
    SELECT jscname INTO name FROM pem.schedule WHERE jscname = 'Job log table cleanup' AND jscjobid = job_id;

    IF (NOT FOUND) THEN
        -- Create data purging schedule.
        INSERT INTO pem.schedule(jscjobid, jscname, jscdesc, jscminutes, jschours, jscweekdays, jscmonthdays, jscmonths) VALUES(job_id, 'Job log table cleanup', 'This job schedule runs periodically to purge old data from the job log table.', '{t,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f}', '{f,f,f,f,f,f,t,f,f,f,f,f,f,f,f,f,f,f,t,f,f,f,f,f}','{t,t,t,t,t,t,t}', '{t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t}', '{t,t,t,t,t,t,t,t,t,t,t,t}');
    END IF;

    -- Check if the job already exists (for purging deleted charts)
    SELECT jobid INTO job_id FROM pem.job WHERE jobname = 'Job purge the deleted charts' AND agent_id = agentid;

    IF (NOT FOUND) THEN
        -- Create data purging job.
        INSERT INTO pem.job(jobname, jobdesc, agent_id, issystemjob) VALUES('Job purge the deleted charts', 'This job runs periodically to purge the deleted charts.', agentid, true) RETURNING jobid INTO job_id;
    END IF;

    -- Check if the job step already exists.
    SELECT jstname INTO name FROM pem.jobstep WHERE jstname = 'Job purge the deleted charts' AND jstjobid = job_id;

    IF (NOT FOUND) THEN
        -- Create data purging step.
        INSERT INTO pem.jobstep(jstjobid, jstname, jstdesc, jstkind, jstcode, server_id, database_name) VALUES (job_id, 'Job purge the deleted charts','This job step runs periodically to purge the deleted charts (we do not clean them up immediately).', 's',
        'SELECT pem.purge_deleted_charts()', serverid, dbname);
    END IF;

    -- Check if the job schedule already exists.
    SELECT jscname INTO name FROM pem.schedule WHERE jscname = 'Job purge the deleted charts' AND jscjobid = job_id;

    IF (NOT FOUND) THEN
        -- Create data purging schedule.
        INSERT INTO pem.schedule(jscjobid, jscname, jscdesc, jscminutes, jschours, jscweekdays, jscmonthdays, jscmonths) VALUES(job_id, 'Job purge the deleted charts', 'This job schedule runs periodically to purge the deletecd charts.', '{t,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f}', '{f,f,t,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f}','{t,t,t,t,t,t,t}', '{t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t}', '{t,t,t,t,t,t,t,t,t,t,t,t}');
    END IF;

    -- Check if the job already exists.
    SELECT jobid INTO job_id FROM pem.job WHERE jobname = 'Purge deleted custom probes' AND agent_id = agentid AND issystemjob;

    IF (NOT FOUND) THEN
        -- Create data purging job.
        INSERT INTO pem.job(
            jobname, jobdesc, agent_id, issystemjob,
            dependent_on_job, execute_on_dep_job_status
        ) VALUES(
            'Purge deleted custom probes', 'This job runs periodically to purge deleted custom probes and its data.',
            agentid, true, ARRAY(
                SELECT jobid FROM pem.job
                WHERE jobname='Update the probe-objects combination' AND issystemjob
            ), 'i'
        ) RETURNING jobid INTO job_id;
    ELSE
        -- Let's make sure 'Purge deleted custom probes' job does not run, when
        -- we're updating the probe-object combination.
        UPDATE pem.job SET dependent_on_job=ARRAY(
            SELECT jobid FROM pem.job
            WHERE jobname='Update the probe-objects combination' AND issystemjob
        ), execute_on_dep_job_status='i'
        WHERE jobid=job_id;
    END IF;

    -- Check if the job step already exists.
    SELECT jstname INTO name FROM pem.jobstep WHERE jstname = 'Purge deleted custom probes' AND jstjobid = job_id;

    IF (NOT FOUND) THEN
        -- Create data purging step.
        INSERT INTO pem.jobstep(jstjobid, jstname, jstdesc, jstkind, jstcode, server_id, database_name) VALUES (job_id, 'Purge deleted custom probes','This job runs periodically to purge deleted custom probes and its data.', 's',
        'SELECT pem.purge_deleted_probes()', serverid, dbname);
    END IF;

    -- Check if the job schedule already exists.
    SELECT jscname INTO name FROM pem.schedule WHERE jscname = 'Purge deleted custom probes' AND jscjobid = job_id;

    IF (NOT FOUND) THEN
        -- Create data purging schedule.
        INSERT INTO pem.schedule(jscjobid, jscname, jscdesc, jscminutes, jschours, jscweekdays, jscmonthdays, jscmonths) VALUES(job_id, 'Purge deleted custom probes', 'This job runs periodically to purge deleted custom probes and its data.', '{t,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f}', '{f,t,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f}','{t,t,t,t,t,t,t}', '{t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t}', '{t,t,t,t,t,t,t,t,t,t,t,t}');
    END IF;

    SELECT jobid INTO job_id FROM pem.job WHERE jobname = 'Database cleanup' AND agent_id = agentid;

    FOR rec IN probe_curs
    LOOP
        INSERT INTO pem.jobstep(
            jstjobid, jstname, jstdesc, jstenabled, jstkind, jstcode, server_id,
            database_name, jstonerror, jstsetenvironment
        ) VALUES (
            job_id, 'Purge data (' || rec.display_name || ')',
            'Purging the history data for the probe (' || rec.display_name || ')...',
            true, 's', 'SELECT pem.purge_probe_history(' || rec.id || '::integer)',
            serverid, dbname, 'i', false
        ) RETURNING jstid INTO tmpid;
        UPDATE pem.probe SET jstid = tmpid WHERE id = rec.id;
    END LOOP;
END;
$BODY$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION pem.startup(server_desc text, server_name text, server_host text, server_port int, server_database text, server_ssl int,
					user_name text, passwd text, ser_group text, agentid int, agent_database text)
  RETURNS void AS
$BODY$
DECLARE
	job_id    integer;
	sg_id     integer;
	serverid  integer := 1;
	is_active boolean;
	name      text;
	tmpid     integer;
	dbname    text := current_database();
	probe_curs CURSOR FOR SELECT id, display_name FROM pem.probe
		WHERE NOT discard_history AND jstid IS NULL;
BEGIN

    -- Check if the server group already exists.
    SELECT id INTO sg_id FROM pem.server_group sg WHERE sg.name = ser_group;

    IF (NOT FOUND) THEN
        -- Create new server group
        INSERT INTO pem.server_group(name) VALUES(ser_group) RETURNING id INTO sg_id;
    END IF;

    -- Check the server entry is already exist.
    SELECT active INTO is_active FROM pem.server WHERE id = serverid;

    -- if entry not found or server with id serverid is already exist and server is active then add new server.
    IF (NOT FOUND) OR is_active THEN
        -- Create entry of PEM server in pem.server table.
        INSERT INTO pem.server (description, server, port, database, ssl) VALUES (server_desc, server_name, server_port, server_database, server_ssl) RETURNING id INTO serverid;

        -- Set the options of the PEM server
        INSERT INTO pem.server_option (server_id, pem_user, username, server_group_id) VALUES (serverid, user_name, user_name, sg_id);
    ELSE
        UPDATE pem.server SET description = server_desc, server = server_name, port = server_port, database = server_database, ssl = server_ssl, active = 't' WHERE id = serverid;

        UPDATE pem.server_option SET pem_user = user_name, username = user_name, server_group_id = sg_id WHERE server_id = serverid;
    END IF;

    -- Create Agent Server Binding
    INSERT INTO pem.agent_server_binding (agent_id, server_id, server, port, username, database, password) VALUES (agentid, serverid, server_host, server_port, user_name, agent_database, passwd);


    -- Check if the job already exists.
    SELECT jobid INTO job_id FROM pem.job WHERE jobname = 'Database cleanup' AND agent_id = agentid;

    IF (NOT FOUND) THEN
        -- Create data purging job.
        INSERT INTO pem.job(jobname, jobdesc, agent_id, issystemjob) VALUES('Database cleanup', 'This job runs periodically to purge old data from the database.', agentid, true) RETURNING jobid INTO job_id;
    END IF;

    -- Check if the job step already exists.
    SELECT jstid INTO tmpid FROM pem.jobstep WHERE jstname = 'Database cleanup' AND jstjobid = job_id;

    IF (NOT FOUND) THEN
        -- Create data purging step.
        INSERT INTO pem.jobstep(
            jstjobid, jstname, jstenabled, jstdesc, jstkind, jstcode,
            server_id, database_name
        ) VALUES (
            job_id, 'Database cleanup', false,
            'This job step runs periodically to purge old data from the database.',
            's', 'SELECT pem.purge_data()',
            serverid, dbname
        );
    ELSE
        UPDATE pem.jobstep SET jstenabled = False
        WHERE jstjobid = job_id AND jstid = tmpid;
    END IF;

    -- Check if the job schedule already exists.
    SELECT jscid INTO tmpid FROM pem.schedule WHERE jscname = 'Database cleanup' AND jscjobid = job_id;

    IF (NOT FOUND) THEN
        -- Create data purging schedule.
        INSERT INTO pem.schedule(
            jscjobid, jscname, jscdesc,
            jscminutes, jschours, jscmonths, jscweekdays,
            jscmonthdays
        ) VALUES(
            job_id, 'Database cleanup', 'This job schedule runs periodically to purge old data from the database.',
            '{t,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f}',
            '{f,t,f,f,f,t,f,f,f,t,f,f,f,t,f,f,f,t,f,f,f,t,f,f}',
            '{t,t,t,t,t,t,t,t,t,t,t,t}', '{t,t,t,t,t,t,t}',
            '{t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t}');
    ELSE
        UPDATE pem.schedule SET
            jschours = '{f,t,f,f,f,t,f,f,f,t,f,f,f,t,f,f,f,t,f,f,f,t,f,f}',
            jscmonthdays = '{t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t}'
        WHERE
            jscjobid = job_id AND jscid = tmpid;
    END IF;

    -- check if the job already exists.
    SELECT jobid INTO job_id FROM pem.job WHERE jobname = 'Update the probe-objects combination' AND agent_id = agentid;

    IF (NOT FOUND) THEN
        --
        -- Generate the update probe-objects combination job
        -- it will run 10 minutes after installation.
        --
        -- Let agent fetch the information about the server, and host-machine
        -- to  determine the actual probes to run, which generates actual
        -- combination.
        INSERT INTO pem.job(
            jobname, jobdesc, agent_id, issystemjob, jobnextrun
        ) VALUES (
            'Update the probe-objects combination',
            'This job updates/inserts the record of the probe, parameter_value_list in the ''pem.probe_objects_combo'' table.',
            agentid, true, now() + interval '10 minutes'
        ) RETURNING jobid INTO job_id;
    END IF;

    -- check if the job step already exists.
    SELECT jstid INTO tmpid FROM pem.jobstep WHERE jstname = 'Update the probe-objects combination' AND jstjobid = job_id;

    IF (NOT FOUND) THEN
        INSERT INTO pem.jobstep(
            jstjobid, jstname, jstdesc, jstkind, jstcode,
            server_id, database_name
        ) VALUES (
            job_id, 'Database cleanup',
            'This job step updates the purge-job tasks on demand.',
            's', 'SELECT pem.create_update_probe_objects_combo()',
            serverid, dbname
        );
    ELSE
        UPDATE pem.jobstep SET jstenabled = TRUE
        WHERE jstid = tmpid AND jstjobid = job_id;
    END IF;

    -- Check if the job already exists.
    SELECT jobid INTO job_id FROM pem.job WHERE jobname = 'Audit log table cleanup' AND agent_id = agentid;

    IF (NOT FOUND) THEN
        -- Create data purging job.
        INSERT INTO pem.job(jobname, jobdesc, agent_id, issystemjob) VALUES('Audit log table cleanup', 'This job runs periodically to purge old data from the audit log table.', agentid, true) RETURNING jobid INTO job_id;
    END IF;

    -- Check if the job step already exists.
    SELECT jstname INTO name FROM pem.jobstep WHERE jstname = 'Audit log table cleanup' AND jstjobid = job_id;

    IF (NOT FOUND) THEN
        -- Create data purging step.
        INSERT INTO pem.jobstep(jstjobid, jstname, jstdesc, jstkind, jstcode, server_id, database_name) VALUES (job_id, 'Audit log table cleanup','This job step runs periodically to purge old data from the audit log table.', 's',
            'SELECT pem.purge_audit_log()', serverid, dbname);
    END IF;

    -- Check if the job schedule already exists.
    SELECT jscname INTO name FROM pem.schedule WHERE jscname = 'Audit log table cleanup' AND jscjobid = job_id;

    IF (NOT FOUND) THEN
        -- Create data purging schedule.
        INSERT INTO pem.schedule(jscjobid, jscname, jscdesc, jscminutes, jschours, jscweekdays, jscmonthdays, jscmonths) VALUES(job_id, 'Audit log table cleanup', 'This job schedule runs periodically to purge old data from the audit log table.', '{t,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f}', '{t,f,f,f,f,f,f,f,f,f,f,f,t,f,f,f,f,f,f,f,f,f,f,f}','{t,t,t,t,t,t,t}', '{t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t}', '{t,t,t,t,t,t,t,t,t,t,t,t}');
    END IF;

    -- Check if the job already exists.
    SELECT jobid INTO job_id FROM pem.job WHERE jobname = 'Server log table cleanup' AND agent_id = agentid;

    IF (NOT FOUND) THEN
        -- Create data purging job.
        INSERT INTO pem.job(jobname, jobdesc, agent_id, issystemjob) VALUES('Server log table cleanup', 'This job runs periodically to purge old data from the server log table.', agentid, true) RETURNING jobid INTO job_id;
    END IF;

    -- Check if the job step already exists.
    SELECT jstname INTO name FROM pem.jobstep WHERE jstname = 'Server log table cleanup' AND jstjobid = job_id;

    IF (NOT FOUND) THEN
        -- Create data purging step.
        INSERT INTO pem.jobstep(jstjobid, jstname, jstdesc, jstkind, jstcode, server_id, database_name) VALUES (job_id, 'Server log table cleanup','This job step runs periodically to purge old data from the server log table.', 's',
        'SELECT pem.purge_server_log()', serverid, dbname);
    END IF;

    -- Check if the job schedule already exists.
    SELECT jscname INTO name FROM pem.schedule WHERE jscname = 'Server log table cleanup' AND jscjobid = job_id;

    IF (NOT FOUND) THEN
        -- Create data purging schedule.
        INSERT INTO pem.schedule(jscjobid, jscname, jscdesc, jscminutes, jschours, jscweekdays, jscmonthdays, jscmonths) VALUES(job_id, 'Server log table cleanup', 'This job schedule runs periodically to purge old data from the server log table.', '{t,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f}', '{f,t,f,f,f,f,f,f,f,f,f,f,f,t,f,f,f,f,f,f,f,f,f,f}','{t,t,t,t,t,t,t}', '{t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t}', '{t,t,t,t,t,t,t,t,t,t,t,t}');
    END IF;

    -- Check if the job already exists.
    SELECT jobid INTO job_id FROM pem.job WHERE jobname = 'Probe log table cleanup' AND agent_id = agentid;

    IF (NOT FOUND) THEN
        -- Create data purging job.
        INSERT INTO pem.job(jobname, jobdesc, agent_id, issystemjob) VALUES('Probe log table cleanup', 'This job runs periodically to purge old data from the probe log table.', agentid, true) RETURNING jobid INTO job_id;
    END IF;

    -- Check if the job step already exists.
    SELECT jstname INTO name FROM pem.jobstep WHERE jstname = 'Probe log table cleanup' AND jstjobid = job_id;

    IF (NOT FOUND) THEN
        -- Create data purging step.
        INSERT INTO pem.jobstep(jstjobid, jstname, jstdesc, jstkind, jstcode, server_id, database_name) VALUES (job_id, 'Probe log table cleanup','This job step runs periodically to purge old data from the probe log table.', 's',
        'SELECT pem.purge_probe_log()', serverid, dbname);
    END IF;

    -- Check if the job schedule already exists.
    SELECT jscname INTO name FROM pem.schedule WHERE jscname = 'Probe log table cleanup' AND jscjobid = job_id;

    IF (NOT FOUND) THEN
        -- Create data purging schedule.
        INSERT INTO pem.schedule(jscjobid, jscname, jscdesc, jscminutes, jschours, jscweekdays, jscmonthdays, jscmonths) VALUES(job_id, 'Probe log table cleanup', 'This job schedule runs periodically to purge old data from the probe log table.', '{t,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f}', '{f,f,t,f,f,f,f,f,f,f,f,f,f,f,t,f,f,f,f,f,f,f,f,f}','{t,t,t,t,t,t,t}', '{t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t}', '{t,t,t,t,t,t,t,t,t,t,t,t}');
    END IF;

    -- Check if the job already exists.
    SELECT jobid INTO job_id FROM pem.job WHERE jobname = 'SMTP spool table cleanup' AND agent_id = agentid;

    IF (NOT FOUND) THEN
        -- Create data purging job.
        INSERT INTO pem.job(jobname, jobdesc, agent_id, issystemjob) VALUES('SMTP spool table cleanup', 'This job runs periodically to purge old data from the smtp spool table.', agentid, true) RETURNING jobid INTO job_id;
    END IF;

    -- Check if the job step already exists.
    SELECT jstname INTO name FROM pem.jobstep WHERE jstname = 'SMTP spool table cleanup' AND jstjobid = job_id;

    IF (NOT FOUND) THEN
        -- Create data purging step.
        INSERT INTO pem.jobstep(jstjobid, jstname, jstdesc, jstkind, jstcode, server_id, database_name) VALUES (job_id, 'SMTP spool table cleanup','This job step runs periodically to purge old data from the smtp spool table.', 's',
        'SELECT pem.purge_smtp_spool()', serverid, dbname);
    END IF;

    -- Check if the job schedule already exists.
    SELECT jscname INTO name FROM pem.schedule WHERE jscname = 'SMTP spool table cleanup' AND jscjobid = job_id;

    IF (NOT FOUND) THEN
        -- Create data purging schedule.
        INSERT INTO pem.schedule(jscjobid, jscname, jscdesc, jscminutes, jschours, jscweekdays, jscmonthdays, jscmonths) VALUES(job_id, 'SMTP spool table cleanup', 'This job schedule runs periodically to purge old data from the smtp spool table.', '{t,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f}', '{f,f,f,t,f,f,f,f,f,f,f,f,f,f,f,t,f,f,f,f,f,f,f,f}','{t,t,t,t,t,t,t}', '{t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t}', '{t,t,t,t,t,t,t,t,t,t,t,t}');
    END IF;

    -- Check if the job already exists.
    SELECT jobid INTO job_id FROM pem.job WHERE jobname = 'SNMP spool table cleanup' AND agent_id = agentid;

    IF (NOT FOUND) THEN
        -- Create data purging job.
        INSERT INTO pem.job(jobname, jobdesc, agent_id, issystemjob) VALUES('SNMP spool table cleanup', 'This job runs periodically to purge old data from the snmp spool table.', agentid, true) RETURNING jobid INTO job_id;
    END IF;

    -- Check if the job step already exists.
    SELECT jstname INTO name FROM pem.jobstep WHERE jstname = 'SNMP spool table cleanup' AND jstjobid = job_id;

    IF (NOT FOUND) THEN
        -- Create data purging step.
        INSERT INTO pem.jobstep(jstjobid, jstname, jstdesc, jstkind, jstcode, server_id, database_name) VALUES (job_id, 'SNMP spool table cleanup','This job step runs periodically to purge old data from the snmp spool table.', 's',
        'SELECT pem.purge_snmp_spool()', serverid, dbname);
    END IF;

    -- Check if the job schedule already exists.
    SELECT jscname INTO name FROM pem.schedule WHERE jscname = 'SNMP spool table cleanup' AND jscjobid = job_id;

    IF (NOT FOUND) THEN
        -- Create data purging schedule.
        INSERT INTO pem.schedule(jscjobid, jscname, jscdesc, jscminutes, jschours, jscweekdays, jscmonthdays, jscmonths) VALUES(job_id, 'SNMP spool table cleanup', 'This job schedule runs periodically to purge old data from the snmp spool table.', '{t,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f}', '{f,f,f,f,t,f,f,f,f,f,f,f,f,f,f,f,t,f,f,f,f,f,f,f}','{t,t,t,t,t,t,t}', '{t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t}', '{t,t,t,t,t,t,t,t,t,t,t,t}');
    END IF;

    -- Check if the job already exists.
    SELECT jobid INTO job_id FROM pem.job WHERE jobname = 'Alert history table cleanup' AND agent_id = agentid;

    IF (NOT FOUND) THEN
        -- Create data purging job.
        INSERT INTO pem.job(jobname, jobdesc, agent_id, issystemjob) VALUES('Alert history table cleanup', 'This job runs periodically to purge old data from the alert history table.', agentid, true) RETURNING jobid INTO job_id;
    END IF;

    -- Check if the job step already exists.
    SELECT jstname INTO name FROM pem.jobstep WHERE jstname = 'Alert history table cleanup' AND jstjobid = job_id;

    IF (NOT FOUND) THEN
        -- Create data purging step.
        INSERT INTO pem.jobstep(jstjobid, jstname, jstdesc, jstkind, jstcode, server_id, database_name) VALUES (job_id, 'Alert history table cleanup','This job step runs periodically to purge old data from the alert history table.', 's',
        'SELECT pem.purge_alert_history()', serverid, dbname);
    END IF;

    -- Check if the job schedule already exists.
    SELECT jscname INTO name FROM pem.schedule WHERE jscname = 'Alert history table cleanup' AND jscjobid = job_id;

    IF (NOT FOUND) THEN
        -- Create data purging schedule.
        INSERT INTO pem.schedule(jscjobid, jscname, jscdesc, jscminutes, jschours, jscweekdays, jscmonthdays, jscmonths) VALUES(job_id, 'Alert history table cleanup', 'This job schedule runs periodically to purge old data from the alert history table.', '{t,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f}', '{f,f,f,f,f,t,f,f,f,f,f,f,f,f,f,f,f,t,f,f,f,f,f,f}','{t,t,t,t,t,t,t}', '{t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t}', '{t,t,t,t,t,t,t,t,t,t,t,t}');
    END IF;

    -- Check if the job already exists.
    SELECT jobid INTO job_id FROM pem.job WHERE jobname = 'Job log table cleanup' AND agent_id = agentid;

    IF (NOT FOUND) THEN
        -- Create data purging job.
        INSERT INTO pem.job(jobname, jobdesc, agent_id, issystemjob) VALUES('Job log table cleanup', 'This job runs periodically to purge old data from the job log table.', agentid, true) RETURNING jobid INTO job_id;
    END IF;

    -- Check if the job step already exists.
    SELECT jstname INTO name FROM pem.jobstep WHERE jstname = 'Job log table cleanup' AND jstjobid = job_id;

    IF (NOT FOUND) THEN
        -- Create data purging step.
        INSERT INTO pem.jobstep(jstjobid, jstname, jstdesc, jstkind, jstcode, server_id, database_name) VALUES (job_id, 'Job log table cleanup','This job step runs periodically to purge old data from the job log table.', 's',
        'SELECT pem.purge_job_log()', serverid, dbname);
    END IF;

    -- Check if the job schedule already exists.
    SELECT jscname INTO name FROM pem.schedule WHERE jscname = 'Job log table cleanup' AND jscjobid = job_id;

    IF (NOT FOUND) THEN
        -- Create data purging schedule.
        INSERT INTO pem.schedule(jscjobid, jscname, jscdesc, jscminutes, jschours, jscweekdays, jscmonthdays, jscmonths) VALUES(job_id, 'Job log table cleanup', 'This job schedule runs periodically to purge old data from the job log table.', '{t,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f}', '{f,f,f,f,f,f,t,f,f,f,f,f,f,f,f,f,f,f,t,f,f,f,f,f}','{t,t,t,t,t,t,t}', '{t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t}', '{t,t,t,t,t,t,t,t,t,t,t,t}');
    END IF;

    -- Check if the job already exists (for purging deleted charts)
    SELECT jobid INTO job_id FROM pem.job WHERE jobname = 'Job purge the deleted charts' AND agent_id = agentid;

    IF (NOT FOUND) THEN
        -- Create data purging job.
        INSERT INTO pem.job(jobname, jobdesc, agent_id, issystemjob) VALUES('Job purge the deleted charts', 'This job runs periodically to purge the deleted charts.', agentid, true) RETURNING jobid INTO job_id;
    END IF;

    -- Check if the job step already exists.
    SELECT jstname INTO name FROM pem.jobstep WHERE jstname = 'Job purge the deleted charts' AND jstjobid = job_id;

    IF (NOT FOUND) THEN
        -- Create data purging step.
        INSERT INTO pem.jobstep(jstjobid, jstname, jstdesc, jstkind, jstcode, server_id, database_name) VALUES (job_id, 'Job purge the deleted charts','This job step runs periodically to purge the deleted charts (we do not clean them up immediately).', 's',
        'SELECT pem.purge_deleted_charts()', serverid, dbname);
    END IF;

    -- Check if the job schedule already exists.
    SELECT jscname INTO name FROM pem.schedule WHERE jscname = 'Job purge the deleted charts' AND jscjobid = job_id;

    IF (NOT FOUND) THEN
        -- Create data purging schedule.
        INSERT INTO pem.schedule(jscjobid, jscname, jscdesc, jscminutes, jschours, jscweekdays, jscmonthdays, jscmonths) VALUES(job_id, 'Job purge the deleted charts', 'This job schedule runs periodically to purge the deletecd charts.', '{t,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f}', '{f,f,t,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f}','{t,t,t,t,t,t,t}', '{t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t}', '{t,t,t,t,t,t,t,t,t,t,t,t}');
    END IF;

    -- Check if the job already exists.
    SELECT jobid INTO job_id FROM pem.job WHERE jobname = 'Purge deleted custom probes' AND agent_id = agentid AND issystemjob;

    IF (NOT FOUND) THEN
        -- Create data purging job.
        INSERT INTO pem.job(
            jobname, jobdesc, agent_id, issystemjob,
            dependent_on_job, execute_on_dep_job_status
        ) VALUES(
            'Purge deleted custom probes', 'This job runs periodically to purge deleted custom probes and its data.',
            agentid, true, ARRAY(
                SELECT jobid FROM pem.job
                WHERE jobname='Update the probe-objects combination' AND issystemjob
            ), 'i'
        ) RETURNING jobid INTO job_id;
    ELSE
        -- Let's make sure 'Purge deleted custom probes' job does not run, when
        -- we're updating the probe-object combination.
        UPDATE pem.job SET dependent_on_job=ARRAY(
            SELECT jobid FROM pem.job
            WHERE jobname='Update the probe-objects combination' AND issystemjob
        ), execute_on_dep_job_status='i'
        WHERE jobid=job_id;
    END IF;

    -- Check if the job step already exists.
    SELECT jstname INTO name FROM pem.jobstep WHERE jstname = 'Purge deleted custom probes' AND jstjobid = job_id;

    IF (NOT FOUND) THEN
        -- Create data purging step.
        INSERT INTO pem.jobstep(jstjobid, jstname, jstdesc, jstkind, jstcode, server_id, database_name) VALUES (job_id, 'Purge deleted custom probes','This job runs periodically to purge deleted custom probes and its data.', 's',
        'SELECT pem.purge_deleted_probes()', serverid, dbname);
    END IF;

    -- Check if the job schedule already exists.
    SELECT jscname INTO name FROM pem.schedule WHERE jscname = 'Purge deleted custom probes' AND jscjobid = job_id;

    IF (NOT FOUND) THEN
        -- Create data purging schedule.
        INSERT INTO pem.schedule(jscjobid, jscname, jscdesc, jscminutes, jschours, jscweekdays, jscmonthdays, jscmonths) VALUES(job_id, 'Purge deleted custom probes', 'This job runs periodically to purge deleted custom probes and its data.', '{t,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f}', '{f,t,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f}','{t,t,t,t,t,t,t}', '{t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t}', '{t,t,t,t,t,t,t,t,t,t,t,t}');
    END IF;

    SELECT jobid INTO job_id FROM pem.job WHERE jobname = 'Database cleanup' AND agent_id = agentid;

    FOR rec IN probe_curs
    LOOP
        INSERT INTO pem.jobstep(
            jstjobid, jstname, jstdesc, jstenabled, jstkind, jstcode, server_id,
            database_name, jstonerror, jstsetenvironment
        ) VALUES (
            job_id, 'Purge data (' || rec.display_name || ')',
            'Purging the history data for the probe (' || rec.display_name || ')...',
            true, 's', 'SELECT pem.purge_probe_history(' || rec.id || '::integer)',
            serverid, dbname, 'i', false
        ) RETURNING jstid INTO tmpid;
        UPDATE pem.probe SET jstid = tmpid WHERE id = rec.id;
    END LOOP;
END;
$BODY$ LANGUAGE plpgsql;

COMMIT TRANSACTION;
