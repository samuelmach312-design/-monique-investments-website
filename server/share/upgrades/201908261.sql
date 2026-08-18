/***************************************************************************
 *
 * Postgres Enterprise Manager
 *
 * Copyright (C) 2010 - 2025, EnterpriseDB Corporation. All rights reserved.
 *
 ***************************************************************************/

BEGIN TRANSACTION;

CREATE OR REPLACE FUNCTION pem.schema_version()
  RETURNS integer AS
'SELECT 201908261::integer;'
  LANGUAGE 'sql' IMMUTABLE;
COMMENT ON FUNCTION pem.schema_version() IS
 'Returns the version number of the PEM schema';


CREATE OR REPLACE FUNCTION pem.do_heartbeat(p_agent_id integer,
                                            server_IDs integer[])
RETURNS void AS $$
DECLARE
    i integer;
BEGIN
    -- perform heartbeat only when agent is active.
    IF ((SELECT active FROM pem.agent WHERE id = p_agent_id) IS NOT TRUE) THEN
        RETURN;
    END IF;

    UPDATE pem.agent_heartbeat
    SET last_heartbeat = now()
    WHERE agent_id = p_agent_id;

    IF (NOT FOUND) THEN
        INSERT INTO pem.agent_heartbeat VALUES(p_agent_id, now() );
    END IF;

    FOR i in 1..COALESCE(array_upper(server_IDs, 1), 0) LOOP
        UPDATE pem.server_heartbeat
        SET last_heartbeat = now()
        WHERE agent_id = p_agent_id
        AND server_id = server_IDs[i];

        IF (NOT FOUND) THEN
            INSERT INTO pem.server_heartbeat
                SELECT asb.agent_id, asb.server_id, now()
                FROM pem.agent_server_binding asb
                WHERE asb.agent_id = p_agent_id
                    AND asb.server_id = server_IDs[i];
        END IF;
    END LOOP;
END;
$$ LANGUAGE plpgsql;

-- Function to create a job that will mark bart backups to obsolete
CREATE OR REPLACE FUNCTION pem.mark_bart_backups_obsolete_job(
    agentid  integer)
  RETURNS void AS
$BODY$

DECLARE
    job_id    integer;
    name      text;
BEGIN
    -- Check if the job already exists.
    SELECT jobid INTO job_id FROM pem.job WHERE jobname = 'Mark BART backups obsolete' AND agent_id = agentid;

    IF (NOT FOUND) THEN
        -- Create mark backups obsolete job.
        INSERT INTO pem.job(jobname, jobdesc, agent_id, issystemjob) VALUES('Mark BART backups obsolete', 'This job runs periodically to mark BART backups to obsolete.', agentid, true) RETURNING jobid INTO job_id;
    ELSE
        return;
    END IF;

    -- Check if the job step already exists.
    SELECT jstname INTO name FROM pem.jobstep WHERE jstname = 'Mark BART backups obsolete' AND jstjobid = job_id;

    IF (NOT FOUND) THEN
        -- Create mark backups obsolete jobstep.
        INSERT INTO pem.jobstep(jstjobid, jstname, jstdesc, jstkind, jstcode, server_id, database_name) VALUES (job_id, 'Mark BART backups obsolete','This job runs periodically to mark BART backups to obsolete.', 'i',
        'mark_bart_backups_obsolete', NULL, NULL);
    END IF;

    -- Check if the job schedule already exists.
    SELECT jscname INTO name FROM pem.schedule WHERE jscname = 'Mark BART backups obsolete' AND jscjobid = job_id;

    IF (NOT FOUND) THEN
        -- Create mark backups obsolete job schedule.
        INSERT INTO pem.schedule(jscjobid, jscname, jscdesc, jscminutes, jschours, jscweekdays, jscmonthdays, jscmonths) VALUES(job_id, 'Mark BART backups obsolete', 'This job runs periodically to mark BART backups to obsolete.', '{t,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f}', '{f,f,t,f,f,t,f,f,t,f,f,t,f,f,t,f,f,t,f,f,t,f,f,t}','{t,t,t,t,t,t,t}', '{t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t}', '{t,t,t,t,t,t,t,t,t,t,t,t}');
    END IF;
END

$BODY$
  LANGUAGE plpgsql;

-- function used to delete all bart db server configuration mapped to bart host and jobs
CREATE OR REPLACE FUNCTION pem.bart_host_postdelete(_bart_id  integer)
RETURNS void AS $$
DECLARE
    _agent_id integer;
BEGIN
    EXECUTE 'SELECT agent_id FROM pem.bart WHERE id = ' || _bart_id  INTO _agent_id;
    -- Delete all db server config
	DELETE FROM pem.bart_server_config
	    WHERE server_id IN (SELECT server_id FROM pem.bart_server_binding WHERE bart_id = _bart_id);
	-- Delete all host and db server jobs
	DELETE FROM pem.job
	    WHERE agent_id = _agent_id AND
	    jobname like '%BART%';
END
$$ LANGUAGE plpgsql;


-- function used to delete bart db server jobs
CREATE OR REPLACE FUNCTION pem.bart_server_postdelete(_server_id integer)
RETURNS void AS $$
DECLARE
    _bart_id    integer;
    _agent_id   integer;
BEGIN
    EXECUTE 'SELECT bart_id FROM pem.bart_server_binding WHERE server_id = ' || _server_id  INTO _bart_id;
    EXECUTE 'SELECT agent_id FROM pem.bart where id = ' || _bart_id  INTO _agent_id;

	-- Delete all db server jobs
	DELETE FROM pem.job
	    WHERE jobid IN (SELECT j.jobid FROM pem.job j INNER JOIN pem.jobstep js ON j.jobid = js.jstjobid WHERE js.server_id = _server_id AND jobname like '%BART%');

    -- Remove show backups job if no other server mapped to same bart host
    IF NOT EXISTS (SELECT 1 FROM pem.bart_server_binding WHERE bart_id = _bart_id) THEN
      DELETE FROM pem.job
        WHERE agent_id = _agent_id AND jobname like '%BART%';
    END IF;
END
$$ LANGUAGE plpgsql;

-- This table store all the success and fail events of BART job
-- so that it will be useful in dashboard.
CREATE TABLE pem.bart_log (
	recorded_time           timestamp with time zone NOT NULL DEFAULT now(),
	bart_id                         integer NOT NULL -- BART Server id
            REFERENCES pem.bart (id) ON DELETE CASCADE ON UPDATE RESTRICT,
	server_name                     text,
	action                          text NOT NULL,
	status                          text NOT NULL
);
COMMENT ON TABLE pem.bart_log IS 'Store the status of all BART server jobs';
COMMENT ON COLUMN pem.bart_log.recorded_time IS 'Recorded timestamp';
COMMENT ON COLUMN pem.bart_log.bart_id IS 'BART host id';
COMMENT ON COLUMN pem.bart_log.server_name IS 'Database server name managed by BART host';
COMMENT ON COLUMN pem.bart_log.action IS 'BART job name';
COMMENT ON COLUMN pem.bart_log.status IS 'BART server job status';

GRANT ALL ON TABLE pem.bart_log TO pem_agent;

INSERT INTO pem.config (param, value, unit, datatype) VALUES ('bart_log_retention_time', '30', 'days', 'integer');

-- Function to create purge job for bart log table, if not exists for that agent
CREATE OR REPLACE FUNCTION pem.create_bart_log_purge_job()
  RETURNS void AS
$BODY$

DECLARE
    job_id    integer;
    agentid   integer;
    name      text;
BEGIN
    -- Check agent id associated with server id = 1
    SELECT agent_id INTO agentid FROM pem.agent_server_binding WHERE server_id = 1;
    IF (NOT FOUND) THEN
        return;
    END IF;

    -- Check if the job already exists.
    SELECT jobid INTO job_id FROM pem.job WHERE jobname = 'BART log table cleanup' AND agent_id = agentid;

    IF (NOT FOUND) THEN
        -- Create bart log purging job.
        INSERT INTO pem.job(jobname, jobdesc, agent_id, issystemjob) VALUES('BART log table cleanup', 'This job runs periodically to purge old data from the bart log table.', agentid, true) RETURNING jobid INTO job_id;
    END IF;

    -- Check if the job step already exists.
    SELECT jstname INTO name FROM pem.jobstep WHERE jstname = 'BART log table cleanup' AND jstjobid = job_id;

    IF (NOT FOUND) THEN
        -- Create bart log purging job step.
        INSERT INTO pem.jobstep(jstjobid, jstname, jstdesc, jstkind, jstcode, server_id, database_name) VALUES (job_id, 'BART log table cleanup','This job step runs periodically to purge old data from the bart log table.', 's',
        'SELECT pem.purge_bart_log()', NULL, NULL);
    END IF;

    -- Check if the job schedule already exists.
    SELECT jscname INTO name FROM pem.schedule WHERE jscname = 'BART log table cleanup' AND jscjobid = job_id;

    IF (NOT FOUND) THEN
        -- Create bart log purging schedule.
        INSERT INTO pem.schedule(jscjobid, jscname, jscdesc, jscminutes, jschours, jscweekdays, jscmonthdays, jscmonths) VALUES(job_id, 'BART log table cleanup', 'This job schedule runs periodically to purge old data from the bart log table.', '{t,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f}', '{f,f,f,f,f,f,t,f,f,f,f,f,f,f,f,f,f,f,t,f,f,f,f,f}','{t,t,t,t,t,t,t}', '{t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t}', '{t,t,t,t,t,t,t,t,t,t,t,t}');
    END IF;
END

$BODY$
  LANGUAGE plpgsql;

-- Function used to purge the bart logs
CREATE OR REPLACE FUNCTION pem.purge_bart_log()
RETURNS void AS $$
        -- Purge data from pem.bart_log table
        DELETE FROM pem.bart_log
        WHERE (now() - recorded_time) >= ((SELECT value FROM pem.config WHERE param = 'bart_log_retention_time')||'days')::interval;
$$ LANGUAGE sql SECURITY DEFINER;

GRANT EXECUTE ON FUNCTION pem.create_bart_log_purge_job() TO pem_admin;
GRANT EXECUTE ON FUNCTION pem.purge_bart_log() TO pem_agent;

SELECT pem.create_bart_log_purge_job();

END TRANSACTION;
