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
'SELECT 201810081::integer;'
  LANGUAGE 'sql' IMMUTABLE;
COMMENT ON FUNCTION pem.schema_version() IS
	'Returns the version number of the PEM schema';

-- Rename the pem.jobagent table as pem.agent_runtime
ALTER TABLE pem.jobagent RENAME TO agent_runtime;

CREATE SEQUENCE pem.agent_runtime_seq MINVALUE 0 MAXVALUE 999999999 CYCLE;
GRANT ALL ON SEQUENCE pem.agent_runtime_seq TO pem_agent;

-- Add a reference column as runtime_id to identify the ID shared with the
-- agent, while (re)starting it.
ALTER TABLE pem.agent_runtime ADD COLUMN runtime_id bigint NOT NULL
	DEFAULT nextval('pem.agent_runtime_seq');
ALTER TABLE pem.agent_runtime ADD COLUMN supported_schema int NOT NULL
	DEFAULT 0;

-- Remove the foreign key for the process-id (pem.jobagent -> jagpid)
ALTER TABLE pem.job DROP CONSTRAINT job_jobprocessid_fkey;

ALTER TABLE pem.agent_runtime RENAME COLUMN jagpid TO process_id;
ALTER TABLE pem.agent_runtime RENAME COLUMN jaglogintime TO login_time;

-- DELETE ALL the records except the latest for all the agents
-- Support ticket #829037 (PEM-1743)
DELETE FROM pem.agent_runtime o
	WHERE login_time != (
		SELECT max(login_time) FROM pem.agent_runtime ar
		WHERE ar.agent_id = o.agent_id
	);

-- 'jgapid' can not be the unique, while connection pooler is used between
-- agent, and the PEM backend databse server. Instead make agent_id the primary
-- key
ALTER TABLE pem.agent_runtime DROP CONSTRAINT jobagent_pkey;
ALTER TABLE pem.agent_runtime
	ADD CONSTRAINT jobagent_pkey PRIMARY KEY (agent_id);

-- Create the pem.jobagent view to make it work with the older version of
-- agents (i.e. < 201810021) for the backword compability
CREATE VIEW pem.jobagent AS
	SELECT
		ar.process_id AS jagpid, ar.login_time AS jaglogintime,
		ar.agent_id
	FROM pem.agent_runtime ar
	WHERE ar.supported_schema < 201810021;

CREATE RULE jobagent_insert AS ON INSERT TO pem.jobagent DO INSTEAD (
	INSERT INTO pem.agent_runtime (process_id, login_time, agent_id) VALUES (
		CASE WHEN NEW.jagpid IS NULL THEN pg_catalog.pg_backend_pid()
		ELSE NEW.jagpid END,
		CASE WHEN NEW.jaglogintime IS NULL THEN now() ELSE NEW.jaglogintime END,
		NEW.agent_id
	)
);

CREATE RULE jobagent_delete AS ON DELETE TO pem.jobagent DO INSTEAD (
	DELETE FROM pem.agent_runtime ar WHERE OLD.jagpid = ar.process_id AND OLD.agent_id = ar.agent_id;
);

GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE pem.jobagent TO pem_agent;

ALTER TABLE pem.probe_schedule ADD COLUMN agent_id integer;
ALTER TABLE pem.job ADD COLUMN jobarid integer;

CREATE OR REPLACE FUNCTION pem.lock_agent_probe_schedule_table(
	_agent_id integer, _probe_id integer, _parameter_value_list text[]
) RETURNS boolean AS $BODY$
DECLARE
    _current_agent_id integer;
BEGIN
    -- Find out if this record already exists
    SELECT agent_id INTO _current_agent_id FROM pem.probe_schedule WHERE probe_id=$2 AND parameter_value_list = $3;

    -- If not exists insert it
    IF NOT FOUND THEN
        INSERT INTO pem.probe_schedule(probe_id, parameter_value_list, agent_id) VALUES ($2, $3, _agent_id);
    ELSE
        IF _current_agent_id IS NULL THEN
            -- Update the probe_schedule table and lock by the current process
            UPDATE pem.probe_schedule SET current_backend_pid=NULL, agent_id=_agent_id WHERE probe_id=$2 AND parameter_value_list=$3;
        ELSE
            -- We can not lock a probe for which current_backend_pid is not NULL (It means - it is already been locked.)
            RETURN false;
        END IF;
    END IF;
    RETURN true;
END
$BODY$ LANGUAGE plpgsql;

DROP FUNCTION pem.clear_probe_zombies();

CREATE OR REPLACE FUNCTION pem.clear_probe_zombies(agent_id integer = NULL) RETURNS void AS $$
BEGIN
    -- New agents will clear from its own zombie probes
    IF agent_id IS NOT NULL THEN
        UPDATE pem.probe_schedule s SET current_backend_pid = NULL, agent_id = NULL WHERE s.agent_id = $1;
    ELSEIF pem.backend_minimum(9,2) THEN
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

CREATE FUNCTION pem.clear_job_zombies(integer) RETURNS void AS $$
DECLARE
	agent_runtime_id integer := NULL;
BEGIN
	SELECT runtime_id INTO agent_runtime_id FROM pem.agent_runtime ar WHERE ar.agent_id = $1;

	WITH running_agent_job AS (
		SELECT j.jobid, j.agent_id
		FROM pem.job j LEFT JOIN pem.joblog jl ON (j.jobid = jl.jlgjobid)
		WHERE jl.jlgstatus = 'r' AND agent_id = $1 AND j.jobarid != agent_runtime_id
	), joblog_status_update AS (
		UPDATE pem.joblog jl SET jlgstatus='d'
		FROM running_agent_job r
		WHERE r.jobid = jl.jlgjobid AND jl.jlgstatus='r' RETURNING r.agent_id, jl.jlgjobid, jl.jlgid
	), jobsteplog_status_update AS (
		UPDATE pem.jobsteplog js SET jslstatus='d'
		FROM joblog_status_update jl
		WHERE js.jsljlgid = jl.jlgid AND js.jslstatus='r' RETURNING jl.agent_id, jl.jlgjobid AS job_id
	)
	UPDATE pem.job j SET jobprocessid=NULL, jobnextrun=NULL, jobarid=NULL
	FROM  (SELECT DISTINCT agent_id, job_id FROM jobsteplog_status_update) js
	WHERE js.job_id = j.jobid;
END;
$$ LANGUAGE plpgsql;

COMMIT TRANSACTION;
