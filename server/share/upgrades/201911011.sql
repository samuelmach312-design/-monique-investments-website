/***************************************************************************
 *
 * Postgres Enterprise Manager
 *
 * Copyright (C) 2010 - 2025, EnterpriseDB Corporation. All rights reserved.
 *
 ***************************************************************************/

-- NOTE: THIS SQL SCRIPT WILL BE RESPONSIBLE FOR 7.12 RELEASE PEM SCHEMA UPGRADE

BEGIN TRANSACTION;

CREATE OR REPLACE FUNCTION pem.schema_version()
  RETURNS integer AS
'SELECT 201911011::integer;'
  LANGUAGE 'sql' IMMUTABLE;
COMMENT ON FUNCTION pem.schema_version() IS 'Returns the version number of the PEM schema';

-- Allow pem_comp_bart users to RLS policies for scheduling task
GRANT pem_manage_schedule_task TO pem_comp_bart;
GRANT ALL ON TABLE pem.bart_backup_config TO pem_comp_bart;
GRANT ALL ON TABLE pem.bart_restore_config TO pem_comp_bart;

-- PEM-2859 store passwordless ssh value
DO
$$
BEGIN
IF NOT EXISTS (SELECT column_name
               FROM information_schema.columns
               WHERE table_schema='pem' and table_name='bart_server_binding' and column_name='passwordless_ssh') THEN
    ALTER TABLE pem.bart_server_binding
    ADD COLUMN passwordless_ssh boolean DEFAULT FALSE;
ELSE
    RAISE NOTICE 'column "passwordless_ssh" of relation "bart_server_binding" already exists';
END IF;
END
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION pem.schedule_bart_ssh_jobs(
    server_id integer,
    agent_id integer,
    agent_binding_id integer,
    restore_config_id integer DEFAULT 0,
    OUT client_job_id integer,
    OUT client_validate_job_id integer,
    OUT server_job_id integer,
    OUT server_validate_job_id integer)
AS
$$
DECLARE
        client_ssh_job_id   integer;
        client_auth_job_id  integer;
        server_ssh_job_id   integer;
        server_auth_job_id  integer;

        jstcode_host_server varchar;
        jstcode_server_host varchar;
        jobname_host_server varchar;
        jobname_server_host varchar;
        remote_host varchar;
BEGIN
    -- Parameter details
    -- first:- 1 host to server, 0: server to host
    -- second:- 0 no restore, 1 host to server restore, 2 server to host restore
    -- third:- restore config id

    IF restore_config_id > 0 THEN
       jstcode_host_server := '1 ' || '1 ' || restore_config_id || ' ';
       jstcode_server_host := '0 ' || '2 ' || restore_config_id || ' ';
       jobname_host_server := 'BART host to restore host';
       jobname_server_host := 'restore host to BART host';
       remote_host := 'restore host';
    ELSE
      jstcode_host_server := '1 0 0 ';
      jstcode_server_host := '0 0 0 ';
      jobname_host_server := 'BART host to database server';
      jobname_server_host := 'database server to BART host';
      remote_host := 'database server host';
    END IF;
    -- Create jobs for client to server ssh authentication
    -- Create client ssh validation job
    INSERT INTO pem.job (jobname, jobdesc, agent_id, jobnextrun)
    VALUES('Validate passwordless SSH authentication from ' || jobname_host_server,
        'This job validates passwordless SSH authentication from ' || jobname_host_server,
        agent_id,
        now()
    ) RETURNING jobid INTO client_job_id;

    INSERT INTO pem.jobstep (jstjobid, jstname, jstdesc, jstenabled, jstkind,
        jstonerror, jstcode, server_id, database_name)
    VALUES(client_job_id, 'Validate passwordless SSH authentication from ' || jobname_host_server,
        'This job step will trigger the validation of passwordless SSH authentication ' || jobname_host_server,
        true, 'i',  'f', concat('bart_validate_passwordless_ssh_authentication ', jstcode_host_server), server_id, null);

    -- Create ssh client key generation job
    INSERT INTO pem.job (jobname, jobdesc, agent_id, jobnextrun,
        dependent_on_job, execute_on_dep_job_status)
    VALUES('Generate keys on BART host for passwordless SSH authentication',
        'This job creates SSH keys on BART host for passwordless SSH authentication.',
        agent_id, now(), ARRAY[client_job_id::integer]::integer[], 'i'
    ) RETURNING jobid INTO client_ssh_job_id;

    INSERT INTO pem.jobstep (jstjobid, jstname, jstdesc, jstenabled, jstkind,
        jstonerror, jstcode, server_id, database_name)
    VALUES (client_ssh_job_id, 'Generate keys on BART host for passwordless SSH authentication',
        'This job step will trigger the creation of SSH keys on BART host for passwordless SSH authentication.',
            true, 'i', 'f', concat('bart_manage_ssh_client ', jstcode_host_server, client_job_id), server_id, null);

    -- add client ssh key to server authorized_keys file
    INSERT INTO pem.job (jobname, jobdesc, agent_id, jobnextrun, dependent_on_job, execute_on_dep_job_status)
    VALUES('Authorize BART host public key for passwordless SSH authentication',
        'This job authorizes BART host public key for passwordless SSH authentication.',
        agent_binding_id, now(),ARRAY[client_ssh_job_id::integer]::integer[],'i'
    ) RETURNING jobid INTO client_auth_job_id;

    INSERT INTO pem.jobstep (jstjobid, jstname, jstdesc, jstenabled, jstkind,
        jstonerror, jstcode, server_id, database_name)
    VALUES (client_auth_job_id, 'Authorize BART host public key for passwordless SSH authentication',
        'This job step will trigger the authorization of BART host public key for passwordless SSH authentication.',
        true, 'i', 'f', concat('bart_manage_ssh_server ', jstcode_host_server, client_job_id) , server_id, null);

    -- validate client-server ssh authentication after creation of public keys
    INSERT INTO pem.job (jobname, jobdesc, agent_id, jobnextrun, dependent_on_job,
        execute_on_dep_job_status)
    VALUES('Validate passwordless SSH authentication from ' || jobname_host_server,
        'This job validates the passwordless SSH authentication from ' || jobname_host_server, agent_id,
        now(), ARRAY[client_auth_job_id::integer]::integer[], 'i'
    ) RETURNING jobid INTO client_validate_job_id;


    INSERT INTO pem.jobstep (jstjobid, jstname, jstdesc, jstenabled, jstkind,
        jstonerror, jstcode, server_id, database_name)
    VALUES(client_validate_job_id, 'Validate passwordless SSH authentication from ' || jobname_host_server,
        'This job step will trigger the validation of passwordless SSH authentication from ' || jobname_host_server,
        true, 'i', 'f', concat('bart_validate_passwordless_ssh_authentication ', jstcode_host_server, client_job_id), server_id, null);

    -- Create jobs for server to client ssh authentication
    -- Create server ssh validation job
    INSERT INTO pem.job (jobname, jobdesc, agent_id, jobnextrun)
    VALUES('Validate passwordless SSH authentication from ' || jobname_server_host,
        'This job validates the passwordless SSH authentication from ' || jobname_server_host,
        agent_binding_id,
        now() + '1 Minute'
    ) RETURNING jobid INTO server_job_id;

    INSERT INTO pem.jobstep (jstjobid, jstname, jstdesc, jstenabled, jstkind,
        jstonerror, jstcode, server_id, database_name)
    VALUES(server_job_id, 'Validate passwordless SSH authentication from ' || jobname_server_host,
        'This job step will trigger the validation of passwordless SSH authentication from ' || jobname_server_host,
        true, 'i',  'f', concat('bart_validate_passwordless_ssh_authentication ', jstcode_server_host), server_id, null);

    -- Create server ssh key generation job
    INSERT INTO pem.job (jobname, jobdesc, agent_id, jobnextrun,
        dependent_on_job, execute_on_dep_job_status)
    VALUES('Generate keys on ' || remote_host || ' for passwordless SSH authentication',
        'This job creates SSH keys on ' || remote_host || ' passwordless SSH authentication.',
        agent_binding_id, now() + '1 Minute', ARRAY[server_job_id::integer]::integer[], 'i'
    ) RETURNING jobid INTO server_ssh_job_id;

    INSERT INTO pem.jobstep (jstjobid, jstname, jstdesc, jstenabled, jstkind,
        jstonerror, jstcode, server_id, database_name)
    VALUES (server_ssh_job_id, 'Generate keys on  ' || remote_host || ' for passwordless SSH authentication',
        'This job step will trigger the creation of SSH keys on ' || remote_host || ' for passwordless SSH authentication.',
            true, 'i', 'f', concat('bart_manage_ssh_client ', jstcode_server_host, server_job_id), server_id, null);

    -- add server key to client authorized_keys file
    INSERT INTO pem.job (jobname, jobdesc, agent_id, jobnextrun, dependent_on_job, execute_on_dep_job_status)
    VALUES('Authorize ' || remote_host || ' public key for passwordless SSH authentication',
        'This job adds ' || remote_host || ' public key for passwordless SSH authentication.',
        agent_id, now()  + '1 Minute', ARRAY[server_ssh_job_id::integer]::integer[],'i'
    ) RETURNING jobid INTO server_auth_job_id;

    INSERT INTO pem.jobstep (jstjobid, jstname, jstdesc, jstenabled, jstkind,
        jstonerror, jstcode, server_id, database_name)
    VALUES (server_auth_job_id, 'Authorize ' || remote_host || ' public key for passwordless SSH authentication',
        'This job step will trigger the authorization of ' || remote_host || ' public key for passwordless SSH authentication.',
        true, 'i', 'f', concat('bart_manage_ssh_server ', jstcode_server_host, server_job_id), server_id, null);

    -- validate server-client ssh authentication after creation of public keys
    INSERT INTO pem.job (jobname, jobdesc, agent_id, jobnextrun, dependent_on_job,
        execute_on_dep_job_status)
    VALUES('Validate passwordless SSH authentication from ' || jobname_server_host,
        'This job validates the passwordless SSH authentication from ' || jobname_server_host, agent_binding_id,
        now() + '1 Minute', ARRAY[server_auth_job_id::integer]::integer[], 'i'
    ) RETURNING jobid INTO server_validate_job_id;

    INSERT INTO pem.jobstep (jstjobid, jstname, jstdesc, jstenabled, jstkind,
        jstonerror, jstcode, server_id, database_name)
    VALUES(server_validate_job_id, 'Validate passwordless SSH authentication from ' || jobname_server_host,
        'This job step will trigger the validation of passwordless SSH authentication from ' || jobname_server_host,
        true, 'i', 'f', concat('bart_validate_passwordless_ssh_authentication ', jstcode_server_host, server_job_id), server_id, null);

END
$$ LANGUAGE plpgsql;

-- PEM-2477
-- This table temporary store all the encrypted public key
-- once pemagent processed, it will be deleted
CREATE TABLE pem.bart_host_public_key (
       bart_id                         integer NOT NULL -- BART Server id
           REFERENCES pem.bart (id) ON DELETE CASCADE ON UPDATE RESTRICT,
       job_id                      integer,
       key                         text
);
COMMENT ON TABLE pem.bart_host_public_key IS 'Store the status of all BART server jobs';
COMMENT ON COLUMN pem.bart_host_public_key.bart_id IS 'BART host id';
COMMENT ON COLUMN pem.bart_host_public_key.job_id IS 'job id';
COMMENT ON COLUMN pem.bart_host_public_key.key IS 'Store encrypted public key';

GRANT ALL ON TABLE pem.bart_host_public_key TO pem_agent;

-- PEM-2934
CREATE OR REPLACE FUNCTION pem.schedule_bart_init_jobs(
    serverid integer,
    agent_id integer,
    agent_binding_id integer,
    OUT init_job_id integer,
    OUT restart_reload_job_id integer)
AS
$$
DECLARE
		mode_val varchar;
        jname varchar;
        code varchar;
        description varchar;
		service_id varchar;
BEGIN
    -- Create job for BART INIT
    INSERT INTO pem.job (jobname, jobdesc, agent_id, jobnextrun)
    VALUES('Execute BART INIT subcommand',
        'This job executes BART INIT subcommand',
        agent_id,
        now()
    ) RETURNING jobid INTO init_job_id;

    INSERT INTO pem.jobstep (jstjobid, jstname, jstdesc, jstenabled, jstkind,
        jstonerror, jstcode, server_id, database_name)
    VALUES(init_job_id, 'Execute BART INIT subcommand',
        'This job step will trigger the exexution of BART INIT subcommand',
        true, 'i',  'f', 'bart_init', serverid, null);

    -- Create job for DB server restart/reload based on archive_mode value
    IF agent_binding_id > 0 THEN
        SELECT setting INTO mode_val FROM pemdata.settings WHERE name = 'archive_mode' AND server_id = serverid;
        IF mode_val IS NULL THEN
            jname := 'Server Restart';
            code := 'server_restart ';
        ELSIF mode_val = 'off' THEN
            jname := 'Server Restart';
            code := 'server_restart ';
        ELSE
            jname := 'Server Reload';
            code := 'server_reload ';
        END IF;

        SELECT serviceid INTO service_id FROM pem.server WHERE id = serverid;
        code := code || service_id;
        description := 'Server ID: ' || serverid || ', agent ID: ' || agent_binding_id;

        INSERT INTO pem.job (jobname, jobdesc, agent_id, jobnextrun,
            dependent_on_job, execute_on_dep_job_status)
        VALUES(jname, description,
            agent_binding_id, now(), ARRAY[init_job_id::integer]::integer[], 'i'
        ) RETURNING jobid INTO restart_reload_job_id;

        INSERT INTO pem.jobstep (jstjobid, jstname, jstdesc, jstenabled, jstkind,
            jstonerror, jstcode, server_id, database_name)
        VALUES (restart_reload_job_id, jname, description,
                true, 'i', 'f', code, serverid, null);
    ELSE
        restart_reload_job_id := null;
    END IF;
END
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION pem.generate_bart_server_config(
    bart_server_id  integer,
    bart_version int8 DEFAULT 2004000::int8,
    all_params boolean DEFAULT true,
    tbl_server_id  integer DEFAULT 1,
    tablespace_str text DEFAULT '')
  RETURNS text AS
$BODY$

DECLARE
    bart_server_config_text    text := '';
    query               text := '';
    server_id_query     text := '';
    server_row          RECORD;
    server_header       text := '';
    validate_version    bool := TRUE;
    tblspace_added      bool := FALSE;
BEGIN
    -- If BART installed version is not found in pem.bart_version table, we should use the latest version used in bart_server_default_config table.
    SELECT bart_version INTO validate_version IN (SELECT DISTINCT(version) FROM pem.bart_server_default_config ORDER BY 1 DESC);
    IF validate_version IS FALSE THEN
        SELECT DISTINCT(version) INTO bart_version FROM pem.bart_server_default_config ORDER BY 1 DESC LIMIT 1;
    END IF;

    IF all_params IS FALSE THEN
      query := 'SELECT sbc.server_id, sbb.name AS server_name, sbc.name, sbc.value FROM pem.bart_server_config sbc LEFT OUTER JOIN pem.bart_server_default_config bdc ON (bdc.name = sbc.name ) LEFT OUTER JOIN pem.bart_server_binding sbb ON (sbb.server_id = sbc.server_id) WHERE version = ' || bart_version || ' AND sbc.server_id = ANY(SELECT server_id FROM pem.bart_server_binding WHERE bart_id = '|| bart_server_id ||' ) AND required_params IS TRUE ORDER BY sbc.server_id, bdc.seq_id;';
    ELSE
      query := 'SELECT sbc.server_id, sbb.name AS server_name, sbc.name, sbc.value FROM pem.bart_server_config sbc LEFT OUTER JOIN pem.bart_server_default_config bdc ON (bdc.name = sbc.name ) LEFT OUTER JOIN pem.bart_server_binding sbb ON (sbb.server_id = sbc.server_id) WHERE version = ' || bart_version || ' AND sbc.server_id = ANY(SELECT server_id FROM pem.bart_server_binding WHERE bart_id = '|| bart_server_id ||' ) ORDER BY sbc.server_id, bdc.seq_id;';
    END IF;

    FOR server_row IN EXECUTE query
    LOOP
        IF server_header != server_row.server_name THEN
          bart_server_config_text = bart_server_config_text || E'\n';
          bart_server_config_text = bart_server_config_text || E'\n' || E'[' || server_row.server_name || ']';
          server_header := server_row.server_name;
        END IF;

        IF COALESCE(TRIM(server_row.value), '') != '' THEN
          -- As archive_command required to be quoted in bart.cfg file otherwise BART command will fail
          IF server_row.name = 'archive_command' THEN
            bart_server_config_text = bart_server_config_text || E'\n' || server_row.name || ' = ' || pg_catalog.quote_literal(TRIM(both E'\'' FROM server_row.value));
          ELSE
            bart_server_config_text = bart_server_config_text || E'\n' || server_row.name || ' = ' || COALESCE(TRIM(server_row.value), '');
          END IF;
        END IF;

        -- As tablespace path is proivded, add to 'bart.cfg' as there is no option to override through command line during restore
        IF NOT tblspace_added AND tbl_server_id = server_row.server_id AND COALESCE(TRIM(tablespace_str), '') != '' THEN
          bart_server_config_text = bart_server_config_text || E'\n' || 'tablespace_path' || ' = ' || COALESCE(TRIM(tablespace_str), '');
          tblspace_added := TRUE;
        END IF;

    END LOOP;

    bart_server_config_text = bart_server_config_text || E'\n';

RETURN bart_server_config_text;

END

$BODY$
  LANGUAGE plpgsql;

END TRANSACTION;
