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
'SELECT 201907151::integer;'
  LANGUAGE 'sql' IMMUTABLE;
COMMENT ON FUNCTION pem.schema_version() IS
 'Returns the version number of the PEM schema';

CREATE OR REPLACE FUNCTION pem.default_email_group() RETURNS integer AS
$$
DECLARE
	   email_group_id integer;
BEGIN
	SELECT min(id) INTO email_group_id FROM pem.email_group;
	IF email_group_id IS NULL THEN
		INSERT INTO pem.email_group(name) VALUES ('<Default>')
			RETURNING id INTO email_group_id;
	END IF;
	RETURN email_group_id;
END;
$$ LANGUAGE 'plpgsql';

ALTER TABLE pem.agent
	ADD COLUMN job_notification_override_default boolean NOT NULL
	DEFAULT FALSE;
ALTER TABLE pem.agent
	ADD COLUMN job_failure_notification boolean NOT NULL DEFAULT FALSE;
ALTER TABLE pem.agent
	ADD COLUMN job_status_change_notification boolean NOT NULL DEFAULT FALSE;
ALTER TABLE pem.agent
	ADD COLUMN job_notification_email_group_id integer NOT NULL
	DEFAULT pem.default_email_group();

COMMENT ON COLUMN pem.agent.job_notification_override_default IS
	'Suggests whether to override the default job notification settings';
COMMENT ON COLUMN pem.agent.job_status_change_notification IS
	'Determines whether to send the notification on scheduled job '
	'successful completion';
COMMENT ON COLUMN pem.agent.job_failure_notification IS
	'Determines whether to send the notification on scheduled job '
	'failed to complete';
COMMENT ON COLUMN pem.agent.job_notification_email_group_id IS
	'Send the notification of the scheduled task to which email group';

CREATE TYPE pem.notify_job_status AS ENUM (
       'DEFAULT',
       'NEVER',
       'ALWAYS',
       'ON_FAILURE'
);

COMMENT ON TYPE pem.notify_job_status IS 'Defines when to send an email';

ALTER TABLE pem.job
	ADD COLUMN notify pem.notify_job_status NOT NULL DEFAULT 'DEFAULT';
ALTER TABLE pem.job
	ADD COLUMN email_group_id integer;

COMMENT ON COLUMN pem.job.notify IS 'Notify on job status change';
COMMENT ON COLUMN pem.job.email_group_id IS
	'ID of the email_group to whom SMTP email to be send';

ALTER TABLE pem.job ADD CONSTRAINT
	job_email_group_id_fkey FOREIGN KEY (email_group_id)
	REFERENCES pem.email_group(id) ON UPDATE CASCADE ON DELETE SET DEFAULT;

ALTER TABLE pem.joblog
	ADD COLUMN jlgemailsent boolean;

INSERT INTO pem.config (param, value, unit, datatype) VALUES (
	'job_failure_notification', 'f', 't/f', 'bool'
);
INSERT INTO pem.config (param, value, unit, datatype) VALUES (
	'job_status_change_notification', 'f', 't/f', 'bool'
);
INSERT INTO pem.config (param, value, unit, datatype) VALUES (
	'job_notification_email_group', 'default', '', 'string'
);

CREATE OR REPLACE FUNCTION pem.joblog_status_update() RETURNS TRIGGER AS
$BODY$
DECLARE
	group_id integer;
	job RECORD;
	agent RECORD;
	status_info RECORD;
	jobsteps_cur REFCURSOR;
	jobstep RECORD;
	job_failure_notification boolean;
	job_status_change_notification boolean;
	current_datestyle text;
	email_template_name text;
	email_template_subject text;
	email_template_message text;
	email_template_message_server text;
	steps text[];
	subject text;
	message text;
BEGIN
	-- We won't update when it's still running
    IF NEW.jlgstatus = 'r' or NEW.jlgstatus IS NULL THEN
        RETURN NEW;
    END IF;
	NEW.jlgemailsent := FALSE;

	-- Notify only when status has been updated
    IF NEW.jlgstatus != OLD.jlgstatus THEN
		SELECT * INTO job FROM pem.job j WHERE j.jobid = NEW.jlgjobid;

        IF job.notify = 'NEVER' OR (
			job.notify = 'ON_FAILURE' AND NEW.jlgstatus NOT IN ('f', 'd')
		) THEN
            RETURN NEW;
        END IF;

		-- Agent Info
		SELECT * INTO agent FROM pem.agent WHERE id = job.agent_id;

		IF job.notify != 'DEFAULT' THEN
			group_id := job.email_group_id;
		ELSE
			IF agent.job_notification_override_default IS TRUE THEN
				IF (
					agent.job_status_change_notification IS NOT TRUE AND
					agent.job_failure_notification IS TRUE AND
					NEW.jlgstatus NOT IN  ('f', 'd')
				) THEN
					RETURN NEW;
				END IF;
				group_id := agent.job_notification_email_group_id;
			ELSE
				SELECT (
					SELECT value FROM pem.config
					WHERE param = 'job_failure_notification'
				), (
					SELECT value FROM pem.config
					WHERE param = 'job_status_change_notification'
				) INTO job_failure_notification,
					job_status_change_notification;

				IF job_status_change_notification IS NOT TRUE AND (
						job_failure_notification IS TRUE AND
						-- Failed, or Cancelled/Interrupted
						NEW.jlgstatus not in ('f', 'd')
				) THEN
					RETURN NEW;
				END IF;

				SELECT id INTO group_id FROM pem.email_group
				WHERE name = (
					SELECT value FROM pem.config
					WHERE param = 'job_notification_email_group'
					LIMIT 1
				);
			END IF;
		END IF;

		IF group_id is NULL THEN
			RETURN NEW;
		END IF;

		SELECT (
			SELECT mail_message FROM pem.email_template
			WHERE display_name = 'Job Step'
		), (
			SELECT mail_message FROM pem.email_template
			WHERE display_name = 'Job Step (Database Server)'
		) INTO email_template_message, email_template_message_server;

		OPEN jobsteps_cur FOR EXECUTE 'SELECT
				jst.*, jstlog.*,
				s.description AS server_desc, s.server AS server_host,
					s.port AS server_port, s.active AS server_active,
					s.hostaddr AS server_hostaddr
				FROM
				pem.jobstep jst
					LEFT JOIN pem.jobsteplog jstlog ON (
					jst.jstid = jstlog.jsljstid
				)
				LEFT JOIN pem.server s ON (jst.server_id = s.id)
				WHERE jst.jstjobid = $1::integer AND (
					jstlog.jsljlgid = $2::integer OR jstlog.jsljlgid IS NULL
				)
			ORDER BY jstlog.jslstart;' USING NEW.jlgjobid, NEW.jlgid;
		LOOP
			FETCH NEXT FROM jobsteps_cur INTO jobstep;
			EXIT WHEN NOT FOUND;

			IF jobstep.server_id IS NULL THEN
				steps := steps || pem.substitute_jobstep_info(
					email_template_message, row_to_json(jobstep)
				);
			ELSE
				steps := steps || pem.substitute_jobstep_info(
					email_template_message_server, row_to_json(jobstep)
				);
			END IF;
		END LOOP;
		CLOSE jobsteps_cur;

		email_template_name := CASE NEW.jlgstatus
			WHEN 'd' THEN 'Job Cancellation'
			WHEN 'f' THEN 'Job Failure'
			ELSE 'Job Success'
		END;

		SELECT mail_subject, mail_message
			INTO email_template_subject, email_template_message
		FROM pem.email_template	WHERE display_name = email_template_name;

		SELECT tbl.* INTO status_info FROM (
			SELECT
				NEW.jlgstatus AS status,
				NEW.jlgstart AS start_time,
				NEW.jlgduration AS duration,
				array_length(steps, 1) AS no_steps,
				array_to_string(steps, E'\n', '') AS steps
				) AS tbl;

		SELECT pem.substitute_job_info(
			email_template_subject, row_to_json(job), row_to_json(agent),
            row_to_json(status_info)
			), pem.substitute_job_info(
			email_template_message, row_to_json(job), row_to_json(agent),
            row_to_json(status_info)
			) INTO subject, message;

		NEW.jlgemailsent := pem.send_email(ARRAY[group_id], subject, message);

    END IF;

	RETURN NEW;
END;
$BODY$ LANGUAGE 'plpgsql' VOLATILE;

CREATE OR REPLACE FUNCTION pem.substitute_jobstep_info(
	input_str TEXT, info json
)
RETURNS TEXT AS
$$
DECLARE
	result TEXT;
BEGIN
	WITH keys AS (
		SELECT regexp_matches(
			input_str, '(?:(.*?)(%[a-zA-Z_]+%)(.*)){1}', 'g'
		) AS tokens
	), rest AS (
		SELECT replace(
			input_str, array_to_string(ARRAY(
				SELECT array_to_string(tokens, '',  '') FROM keys
    ), '', ''), '') AS rest
	)
	SELECT array_to_string(ARRAY(SELECT
		COALESCE(tokens[1], '') ||
		CASE tokens[2]
		WHEN '%id%' THEN info->>'jstid'::text
		WHEN E'%description%' THEN info->>'jstdesc'
		WHEN E'%name%' THEN info->>'jstname'
		WHEN E'%result%' THEN COALESCE(info->>'jslresult'::text, '')
		WHEN E'%start_time%' THEN COALESCE(
			(info->>'jslstart')::timestamptz::text, ''
		)
		WHEN E'%duration%' THEN COALESCE(
			(info->>'jslduration')::interval::text, ''
		)
		WHEN E'%enabled%' THEN
			CASE WHEN (info->>'jstenabled')::boolean IS TRUE THEN 'Yes'
			ELSE 'False' END
		WHEN E'%kind%' THEN
			CASE info->>'jstkind'
			WHEN 'b' THEN 'Batch/Shell Script'
			WHEN 's' THEN 'SQL Query'
			WHEN 'i' THEN 'Internal'
			ELSE 'Unknown'
			END
		WHEN E'%status%' THEN
			CASE info->>'jslstatus'
			WHEN 's' THEN 'SUCCESS'
			WHEN 'f' THEN 'FAILED'
			WHEN 'i' THEN 'IGNORED'
			WHEN 'd' THEN 'INTERRUPTED'
			WHEN 'r' THEN 'RUNNING'
			ELSE
				CASE (info->>'jstenabled')::boolean
				WHEN FALSE THEN 'INACTIVE'
				ELSE 'NEVER RAN'
				END
			END
		WHEN E'%server_id%' THEN COALESCE(info->>'server_id'::text, '')
		WHEN E'%database%' THEN COALESCE(info->>'database_name'::text, '')
		WHEN E'%server_desc%' THEN COALESCE(info->>'server_desc', '')
		WHEN E'%server_host%' THEN
			CASE
			WHEN (info->>'server_hostaddr')::text IS NOT NULL OR
                info->>'server_hostaddr' != '' THEN info->>'server_hostaddr'
			ELSE COALESCE((info->>'server_host')::text, '')
			END
		WHEN E'%server_port%' THEN COALESCE(info->>'server_port'::text, '')
		WHEN E'%server_active%' THEN
			CASE (info->>'server_active')::boolean
			WHEN TRUE THEN 'Active'
			WHEN FALSE THEN 'Inactive'
			ELSE ''
			END
		ELSE COALESCE(tokens[2], '')
		END || COALESCE(tokens[3], '')
		FROM keys
	), '', '') || (SELECT rest FROM rest) INTO result;

	RETURN result;
END;
$$ LANGUAGE 'plpgsql';

CREATE OR REPLACE FUNCTION pem.substitute_job_info(
	input_str text, job json, agent json, status_info json
) RETURNS TEXT AS
$$
DECLARE
	result TEXT;
BEGIN
	WITH keys AS (
		SELECT regexp_matches(
			input_str, '(?:(.*?)(%[a-zA-Z_]+%)(.*)){1}', 'g'
		) AS tokens
	), rest AS (
		SELECT replace(
			input_str, array_to_string(ARRAY(
				SELECT array_to_string(tokens, '',  '') FROM keys
    ), '', ''), '') AS rest
	)
	SELECT array_to_string(ARRAY(SELECT
		COALESCE(tokens[1], '') ||
		CASE tokens[2]
		WHEN '%id%' THEN job->>'jobid'::text
		WHEN E'%description%' THEN job->>'jobdesc'
		WHEN E'%name%' THEN job->>'jobname'
		WHEN E'%start_time%'
            THEN (status_info->>'start_time')::timestamptz::text
		WHEN E'%duration%' THEN (status_info->>'duration')::interval::text
		WHEN E'%steps_count%' THEN status_info->>'no_steps'::text
		WHEN E'%steps_info%' THEN status_info->>'steps'
		WHEN E'%status%' THEN
			CASE status_info->>'status'
			WHEN 's' THEN 'SUCCESS'
			WHEN 'f' THEN 'FAILED'
			WHEN 'i' THEN 'IGNORED'
			WHEN 'd' THEN 'INTERRUPTED'
			ELSE 'RUNNING'
			END
		WHEN E'%agent_id%' THEN agent->>'id'::text
		WHEN E'%agent_desc%' THEN agent->>'description'
		ELSE COALESCE(tokens[2], '')
		END || COALESCE(tokens[3], '')
		FROM keys
	), '', '') || (SELECT rest FROM rest) INTO result;

	RETURN result;
END;
$$ LANGUAGE 'plpgsql';

CREATE TRIGGER joblog_status_update AFTER UPDATE OF jlgstatus
	ON pem.joblog FOR EACH ROW
	EXECUTE PROCEDURE pem.joblog_status_update();

COMMENT ON TRIGGER joblog_status_update ON pem.joblog IS
	'Determine whether to send on SMTP email on job completion. If yes, then '
	'draft an email and put it in the smtp pool table.';

-- Template for job success
INSERT INTO pem.email_template(display_name, mail_subject, mail_message) VALUES(
	'Job Success', '[Job Completed] %name% on Agent - ''%agent_desc%''',
	array_to_string(ARRAY[
		'Job Details',
		'-----------',
		'Name: %name%',
		'ID# %id%',
		'Status: %status%',
		'',
		'Agent: %agent_desc%',
		'Agent Id# %agent_id%',
		'',
		'Description:',
		'%description%',
		'Started at: %start_time%',
		'Duration: %duration%',
		'',
		'No of steps executed: %steps_count%',
		'',
		'Steps Details',
		'-------------',
		'%steps_info%'
		], E'\n')
);

-- Template for job failure
INSERT INTO pem.email_template(display_name, mail_subject, mail_message)
SELECT 'Job Failure',
'[Job Failed] %name% on Agent - ''%agent_desc%''',
mail_message
FROM pem.email_template WHERE display_name = 'Job Success';

-- Template for job cancellation
INSERT INTO pem.email_template(display_name, mail_subject, mail_message)
SELECT 'Job Cancellation',
'[Job Interrupted] %name% on Agent - ''%agent_desc%''',
mail_message
FROM pem.email_template WHERE display_name = 'Job Success';

INSERT INTO pem.email_template(display_name, mail_subject, mail_message)
VALUES(
	'Job Step', '', array_to_string(ARRAY[
		'=== #%id% - %name% (%status%)',
		'Step Kind: %kind%',
		'Enabled? %enabled%',
		'Description:',
		'%description%',
		'',
		'Start time: %start_time%',
		'Duration: %duration%',
		'Result: %result%'
		], E'\n')
);

INSERT INTO pem.email_template(display_name, mail_subject, mail_message)
SELECT 'Job Step (Database Server)', '', mail_message || array_to_string(ARRAY[
	'',
	'Server ID# %server_id%',
	'Server: %server_desc% (%server_host%:%server_port%)',
	'Database: %database%',
	'Server status: %server_active%'
	], E'\n') FROM pem.email_template WHERE display_name = 'Job Step';

GRANT ALL ON TABLE pem.exception TO pem_manage_schedule_task;

CREATE OR REPLACE FUNCTION pem.exception_trigger() RETURNS "trigger" AS '
DECLARE
    jid int4 := 0;
BEGIN
     IF TG_OP = ''DELETE'' THEN
        SELECT INTO jid jscjobid FROM pem.schedule WHERE jscid = OLD.jexscid;
        -- update job from remaining schedules
        -- the actual calculation of jobnextrun will be performed in the trigger
        UPDATE pem.job
           SET jobnextrun = NULL
         WHERE jobenabled AND jobid=jid;
        RETURN OLD;
    ELSE
        SELECT INTO jid jscjobid FROM pem.schedule WHERE jscid = NEW.jexscid;
        UPDATE pem.job
           SET jobnextrun = NULL
         WHERE jobenabled AND jobid=jid;
        RETURN NEW;
    END IF;
END;
' LANGUAGE 'plpgsql' VOLATILE;
COMMENT ON FUNCTION pem.exception_trigger() IS 'Update the job''s next run time whenever an exception changes';

END TRANSACTION;
