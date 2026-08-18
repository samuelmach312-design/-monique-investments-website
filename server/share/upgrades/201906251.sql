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
'SELECT 201906251::integer;'
  LANGUAGE 'sql' IMMUTABLE;
COMMENT ON FUNCTION pem.schema_version() IS
 'Returns the version number of the PEM schema';

-- Add all BART related schemas
CREATE TABLE pem.bart_version (
        id                      int8 NOT NULL,
        display_name            text NOT NULL,
        CONSTRAINT bart_server_version_pkey PRIMARY KEY (id)
);

COMMENT ON TABLE pem.bart_version IS 'Store BART host version information';
COMMENT ON COLUMN pem.bart_version.id IS 'BART host version';
COMMENT ON COLUMN pem.bart_version.display_name IS 'BART host version string';

-- Version will be ((major version * 1000000) + (minor version * 1000)) and
-- display name will be same as return by "bart --version" command
INSERT INTO pem.bart_version VALUES (2003000, 'BART (EnterpriseDB) 2.3');
INSERT INTO pem.bart_version VALUES (2004000, 'BART (EnterpriseDB) 2.4');

-- This table store the BART host activity.
-- This table store the BART host activity.
CREATE TABLE pem.bart (
        id                              serial NOT NULL,
        agent_id                        integer
                REFERENCES pem.agent (id) ON DELETE SET NULL,
        job_id                          integer
                REFERENCES pem.job (jobid) ON DELETE SET NULL,
        name                            text NOT NULL,
        version_string                  text,
        version                         int8
               REFERENCES pem.bart_version (id) ON DELETE SET NULL,
        status                          text,
        message                         text,
        CONSTRAINT bart_pkey PRIMARY KEY (id)
);

COMMENT ON TABLE pem.bart IS 'Store BART host activity';
COMMENT ON COLUMN pem.bart.id IS 'BART host id';
COMMENT ON COLUMN pem.bart.agent_id IS 'pemagent id binded with BART host';
COMMENT ON COLUMN pem.bart.job_id IS 'BART host job id';
COMMENT ON COLUMN pem.bart.name IS 'BART host name';
COMMENT ON COLUMN pem.bart.version_string IS 'BART full version string';
COMMENT ON COLUMN pem.bart.version IS 'BART version';
COMMENT ON COLUMN pem.bart.status IS 'BART host status';
COMMENT ON COLUMN pem.bart.message IS 'BART host status message';

-- This table store the BART host and managed database server binding information.
CREATE TABLE pem.bart_server_binding (
        bart_id                         integer NOT NULL
                REFERENCES pem.bart (id) ON DELETE CASCADE ON UPDATE RESTRICT,
        server_id                       integer NOT NULL
                REFERENCES pem.server (id) ON DELETE CASCADE ON UPDATE RESTRICT,
        name                            text NOT NULL,
        jobs_id                         integer[],
        password                        text,
        status                          text, -- status will be "INITIATED", "IN PROGRESS", "VALIDATED", "INVALID"
        message                         text,
        CONSTRAINT bart_server_binding_pkey PRIMARY KEY (bart_id, server_id)
);

COMMENT ON TABLE pem.bart_server_binding IS 'Used to store BART host and managed database server binding information';
COMMENT ON COLUMN pem.bart_server_binding.bart_id IS 'BART host id';
COMMENT ON COLUMN pem.bart_server_binding.server_id IS 'BART managed database server id';
COMMENT ON COLUMN pem.bart_server_binding.jobs_id IS 'BART managed database server jobs id';
COMMENT ON COLUMN pem.bart_server_binding.password IS 'BART managed database server password';
COMMENT ON COLUMN pem.bart_server_binding.status IS 'BART managed database server status';
COMMENT ON COLUMN pem.bart_server_binding.message IS 'BART managed database server status message';

-- This table is used to store the backup information of the managed BART database server.
CREATE TABLE pem.bart_backups (
        server_id                       integer NOT NULL
            REFERENCES pem.server (id) ON DELETE CASCADE ON UPDATE RESTRICT,
        start_time                      timestamp with time zone DEFAULT current_timestamp,
        id                              bigint NOT NULL,
        name                            text,
        type                            text,
        parent                          text,
        status                          text,
        message                         text,
        total_duration                  interval,
        size                            text,
        wal_size                        text,
        no_of_wals                      integer,
        tablespace_oid                  integer,
        CONSTRAINT bart_backups_pkey PRIMARY KEY (id)
);

COMMENT ON TABLE pem.bart_backups IS 'Store the backup information of managed BART database server';
COMMENT ON COLUMN pem.bart_backups.server_id IS 'BART managed database server id';
COMMENT ON COLUMN pem.bart_backups.id IS 'Backup ID';
COMMENT ON COLUMN pem.bart_backups.name IS 'Backup name';
COMMENT ON COLUMN pem.bart_backups.type IS 'Backup type';
COMMENT ON COLUMN pem.bart_backups.parent IS 'Parent of backup';
COMMENT ON COLUMN pem.bart_backups.status IS 'Backup status';
COMMENT ON COLUMN pem.bart_backups.start_time IS 'Backup start time';
COMMENT ON COLUMN pem.bart_backups.total_duration IS 'Backup total duration';
COMMENT ON COLUMN pem.bart_backups.size IS 'Backup size';
COMMENT ON COLUMN pem.bart_backups.wal_size IS 'WAL size of backup';
COMMENT ON COLUMN pem.bart_backups.no_of_wals IS 'Number of WALs of backups';
COMMENT ON COLUMN pem.bart_backups.tablespace_oid IS 'Tablespace OID of the backup';

-- This table is used to store the default BART host configurations.
CREATE TABLE pem.bart_default_config (
        seq_id                          serial NOT NULL, -- Sequence id
        version                         int8 NOT NULL
             REFERENCES pem.bart_version (id) ON UPDATE RESTRICT ON DELETE CASCADE,
        name                            text NOT NULL, -- BART host configuration name
        value                           text DEFAULT NULL, -- BART host configuration value
        required_params                 boolean DEFAULT false, -- Mandatory parameter or not
        CONSTRAINT bart_default_config_pkey PRIMARY KEY (seq_id)
);

COMMENT ON TABLE pem.bart_default_config IS 'Store BART default configuration parameters';
COMMENT ON COLUMN pem.bart_default_config.seq_id IS 'Sequence ID';
COMMENT ON COLUMN pem.bart_default_config.version IS 'BART version';
COMMENT ON COLUMN pem.bart_default_config.name IS 'Configuration parameter name';
COMMENT ON COLUMN pem.bart_default_config.value IS 'Configuration parameter value';
COMMENT ON COLUMN pem.bart_default_config.required_params IS 'Mandatory parameter or not';

INSERT INTO pem.bart_default_config VALUES (1,  2003000, 'bart_user', NULL, true);
INSERT INTO pem.bart_default_config VALUES (2,  2003000, 'bart_host', NULL, true);
INSERT INTO pem.bart_default_config VALUES (3,  2003000, 'backup_path', NULL, true);
INSERT INTO pem.bart_default_config VALUES (4,  2003000, 'pg_basebackup_path', NULL, true);
INSERT INTO pem.bart_default_config VALUES (5,  2003000, 'xlog_method', 'fetch');
INSERT INTO pem.bart_default_config VALUES (6,  2003000, 'retention_policy');
INSERT INTO pem.bart_default_config VALUES (7,  2003000, 'logfile');
INSERT INTO pem.bart_default_config VALUES (8,  2003000, 'scanner_logfile');
INSERT INTO pem.bart_default_config VALUES (9,  2003000, 'wal_compression', 'disabled');
INSERT INTO pem.bart_default_config VALUES (10, 2003000, 'copy_wals_during_restore', 'disabled');
INSERT INTO pem.bart_default_config VALUES (11, 2003000, 'thread_count', '1');
INSERT INTO pem.bart_default_config VALUES (12, 2003000, 'batch_size', '49142');
INSERT INTO pem.bart_default_config VALUES (13, 2003000, 'scan_interval', '0');
INSERT INTO pem.bart_default_config VALUES (14, 2003000, 'mbm_scan_timeout', '20');

INSERT INTO pem.bart_default_config VALUES (15, 2004000, 'bart_user', NULL, true);
INSERT INTO pem.bart_default_config VALUES (16, 2004000, 'bart_host', NULL, true);
INSERT INTO pem.bart_default_config VALUES (17, 2004000, 'backup_path', NULL, true);
INSERT INTO pem.bart_default_config VALUES (18, 2004000, 'pg_basebackup_path', NULL, true);
INSERT INTO pem.bart_default_config VALUES (19, 2004000, 'xlog_method', 'fetch');
INSERT INTO pem.bart_default_config VALUES (20, 2004000, 'retention_policy');
INSERT INTO pem.bart_default_config VALUES (21, 2004000, 'logfile');
INSERT INTO pem.bart_default_config VALUES (22, 2004000, 'scanner_logfile');
INSERT INTO pem.bart_default_config VALUES (23, 2004000, 'wal_compression', 'disabled');
INSERT INTO pem.bart_default_config VALUES (24, 2004000, 'copy_wals_during_restore', 'disabled');
INSERT INTO pem.bart_default_config VALUES (25, 2004000, 'thread_count', '1');
INSERT INTO pem.bart_default_config VALUES (26, 2004000, 'batch_size', '49142');
INSERT INTO pem.bart_default_config VALUES (27, 2004000, 'scan_interval', '0');
INSERT INTO pem.bart_default_config VALUES (28, 2004000, 'mbm_scan_timeout', '20');

-- This table is used to store the default BART managed database server configurations.
CREATE TABLE pem.bart_server_default_config (
        seq_id                          serial NOT NULL, -- Sequence id
        version                         int8 NOT NULL
             REFERENCES pem.bart_version (id) ON UPDATE RESTRICT ON DELETE CASCADE,
        name                            text NOT NULL, -- BART configuration name
        value                           text DEFAULT NULL, -- BART configuration value
        required_params                 boolean DEFAULT false, -- Mandatory parameter or not
        CONSTRAINT bart_server_default_config_pkey PRIMARY KEY (seq_id)
);

COMMENT ON TABLE pem.bart_server_default_config IS 'Store BART managed database server default configuration parameters';
COMMENT ON COLUMN pem.bart_server_default_config.seq_id IS 'Sequence ID';
COMMENT ON COLUMN pem.bart_server_default_config.version IS 'BART version';
COMMENT ON COLUMN pem.bart_server_default_config.name IS 'Database server configuration parameter name';
COMMENT ON COLUMN pem.bart_server_default_config.value IS 'Database server configuration parameter value';
COMMENT ON COLUMN pem.bart_server_default_config.required_params IS 'Mandatory parameter or not';

INSERT INTO pem.bart_server_default_config VALUES (1,  2003000, 'backup_name');
INSERT INTO pem.bart_server_default_config VALUES (2,  2003000, 'host', NULL, true);
INSERT INTO pem.bart_server_default_config VALUES (3,  2003000, 'user', NULL, true);
INSERT INTO pem.bart_server_default_config VALUES (4,  2003000, 'port', '5444');
INSERT INTO pem.bart_server_default_config VALUES (5,  2003000, 'archive_command');
INSERT INTO pem.bart_server_default_config VALUES (6,  2003000, 'cluster_owner', NULL, true);
INSERT INTO pem.bart_server_default_config VALUES (7,  2003000, 'remote_host');
INSERT INTO pem.bart_server_default_config VALUES (8,  2003000, 'tablespace_path');
INSERT INTO pem.bart_server_default_config VALUES (9,  2003000, 'xlog_method', 'fetch');
INSERT INTO pem.bart_server_default_config VALUES (10, 2003000, 'retention_policy');
INSERT INTO pem.bart_server_default_config VALUES (11, 2003000, 'wal_compression', 'disabled');
INSERT INTO pem.bart_server_default_config VALUES (12, 2003000, 'copy_wals_during_restore', 'disabled');
INSERT INTO pem.bart_server_default_config VALUES (13, 2003000, 'allow_incremental_backups', 'disabled');
INSERT INTO pem.bart_server_default_config VALUES (14, 2003000, 'thread_count', '1');
INSERT INTO pem.bart_server_default_config VALUES (15, 2003000, 'description');
INSERT INTO pem.bart_server_default_config VALUES (16, 2003000, 'batch_size', '49142');
INSERT INTO pem.bart_server_default_config VALUES (17, 2003000, 'scan_interval', '0');
INSERT INTO pem.bart_server_default_config VALUES (18, 2003000, 'mbm_scan_timeout', '20');

INSERT INTO pem.bart_server_default_config VALUES (19, 2004000, 'backup_name');
INSERT INTO pem.bart_server_default_config VALUES (20, 2004000, 'host', NULL, true);
INSERT INTO pem.bart_server_default_config VALUES (21, 2004000, 'user', NULL, true);
INSERT INTO pem.bart_server_default_config VALUES (22, 2004000, 'port', '5444');
INSERT INTO pem.bart_server_default_config VALUES (23, 2004000, 'archive_command');
INSERT INTO pem.bart_server_default_config VALUES (24, 2004000, 'cluster_owner', NULL, true);
INSERT INTO pem.bart_server_default_config VALUES (25, 2004000, 'remote_host');
INSERT INTO pem.bart_server_default_config VALUES (26, 2004000, 'tablespace_path');
INSERT INTO pem.bart_server_default_config VALUES (27, 2004000, 'xlog_method', 'fetch');
INSERT INTO pem.bart_server_default_config VALUES (28, 2004000, 'retention_policy');
INSERT INTO pem.bart_server_default_config VALUES (29, 2004000, 'wal_compression', 'disabled');
INSERT INTO pem.bart_server_default_config VALUES (30, 2004000, 'copy_wals_during_restore', 'disabled');
INSERT INTO pem.bart_server_default_config VALUES (31, 2004000, 'allow_incremental_backups', 'disabled');
INSERT INTO pem.bart_server_default_config VALUES (32, 2004000, 'thread_count', '1');
INSERT INTO pem.bart_server_default_config VALUES (33, 2004000, 'description');
INSERT INTO pem.bart_server_default_config VALUES (34, 2004000, 'batch_size', '49142');
INSERT INTO pem.bart_server_default_config VALUES (35, 2004000, 'scan_interval', '0');
INSERT INTO pem.bart_server_default_config VALUES (36, 2004000, 'mbm_scan_timeout', '20');

-- This table store the user defined BART host configurations.
CREATE TABLE pem.bart_config (
        bart_id                         integer NOT NULL -- BART Server id
            REFERENCES pem.bart (id) ON DELETE CASCADE ON UPDATE RESTRICT,
        name                            text NOT NULL, -- BART configuration name
        value                           text DEFAULT NULL, -- BART configuration value
        CONSTRAINT bart_config_pkey PRIMARY KEY (bart_id, name)
);

COMMENT ON TABLE pem.bart_config IS 'Store user defined BART host configuration parameters';
COMMENT ON COLUMN pem.bart_config.bart_id IS 'BART host id';
COMMENT ON COLUMN pem.bart_config.name IS 'BART host configuration parameter name';
COMMENT ON COLUMN pem.bart_config.value IS 'BART host configuration parameter value';

-- This table store the user defined BART managed database server configurations.
CREATE TABLE pem.bart_server_config (
        server_id                       integer NOT NULL -- BART Server id
            REFERENCES pem.server (id) ON DELETE CASCADE ON UPDATE RESTRICT,
        name                            text NOT NULL, -- BART configuration name
        value                           text DEFAULT NULL, -- BART configuration value
        CONSTRAINT bart_server_config_pkey PRIMARY KEY (server_id, name)
);

COMMENT ON TABLE pem.bart_server_config IS 'Store user defined BART managed database server configurations';
COMMENT ON COLUMN pem.bart_server_config.server_id IS 'BART managed database server id';
COMMENT ON COLUMN pem.bart_server_config.name IS 'BART managed database server configuration parameter name';
COMMENT ON COLUMN pem.bart_server_config.value IS 'BART managed database server configuration parameter value';

-- This table store the user defined BART installation paths
CREATE TABLE pem.bart_default_path (
        id                          serial NOT NULL,
        install_path                text NOT NULL,
        CONSTRAINT bart_default_path_pkey PRIMARY KEY (id, install_path)
);

COMMENT ON TABLE pem.bart_default_path IS 'Store BART Installation paths';
COMMENT ON COLUMN pem.bart_default_path.id IS 'Unique id';
COMMENT ON COLUMN pem.bart_default_path.install_path IS 'Path of BART installation directory';

INSERT INTO pem.bart_default_path VALUES(1, '/usr/edb/bart');

-- Function to create BART configuration file
CREATE OR REPLACE FUNCTION pem.generate_bart_config(
    bart_version int8 DEFAULT 2004000::int8,
    all_params boolean DEFAULT true)
  RETURNS text AS
$BODY$

DECLARE
    bart_config_text    text := '';
    query               text := '';
    bart_user_name      text := '';
    row                 RECORD;

BEGIN
    IF all_params IS FALSE THEN
      query := 'SELECT bc.name, bc.value FROM pem.bart_config bc LEFT OUTER JOIN pem.bart_default_config bdc ON (bdc.name = bc.name ) WHERE version = ' || bart_version || ' AND required_params IS TRUE ORDER BY bdc.seq_id;';
    ELSE
      query := 'SELECT bc.name, bc.value FROM pem.bart_config bc LEFT OUTER JOIN pem.bart_default_config bdc ON (bdc.name = bc.name ) WHERE version = ' || bart_version || ' ORDER BY bdc.seq_id;';
    END IF;

    FOR row IN EXECUTE query
    LOOP
        IF COALESCE(TRIM(bart_config_text), '') = '' THEN
          bart_config_text = bart_config_text || E'[BART]';
        END IF;

        IF row.name = 'bart_user' THEN
          bart_user_name = row.value;
        ELSIF row.name = 'bart_host' THEN
          bart_config_text = bart_config_text || E'\n' || row.name || ' = ' || bart_user_name || '@' || COALESCE(TRIM(row.value), '');
        ELSE
          bart_config_text = bart_config_text || E'\n' || row.name || ' = ' || COALESCE(TRIM(row.value), '');
        END IF;

    END LOOP;

    bart_config_text = bart_config_text || E'\n';

RETURN bart_config_text;

END

$BODY$
  LANGUAGE plpgsql;

-- Function to create BART managed database server configuration file.
CREATE OR REPLACE FUNCTION pem.generate_bart_server_config(
    bart_server_id  integer,
    bart_version int8 DEFAULT 2004000::int8,
    all_params boolean DEFAULT true)
  RETURNS text AS
$BODY$

DECLARE
    bart_server_config_text    text := '';
    query               text := '';
    server_id_query     text := '';
    server_row          RECORD;
    row                 RECORD;
    add_server_header   boolean := true;

BEGIN
    server_id_query := 'SELECT server_id, name FROM pem.bart_server_binding WHERE bart_id = '|| bart_server_id ||' ORDER BY server_id;';

    IF all_params IS FALSE THEN
      query := 'SELECT name, value FROM pem.bart_server_default_config WHERE version = ' || bart_version || ' AND required_params IS TRUE ORDER BY seq_id;';
    ELSE
      query := 'SELECT name, value FROM pem.bart_server_default_config WHERE version = ' || bart_version || ' ORDER BY seq_id;';
    END IF;

    FOR server_row IN EXECUTE server_id_query
    LOOP
        add_server_header := true;
        FOR row IN EXECUTE query
        LOOP
            IF add_server_header IS TRUE THEN
              bart_server_config_text = bart_server_config_text || E'[' || server_row.name || ']';
              add_server_header := false;
            END IF;

            bart_server_config_text = bart_server_config_text || E'\n' || row.name || ' = ' || COALESCE(TRIM(row.value), '');

        END LOOP;
        bart_server_config_text = bart_server_config_text || E'\n\n';
    END LOOP;

    bart_server_config_text = bart_server_config_text || E'\n\n';

RETURN bart_server_config_text;

END

$BODY$
  LANGUAGE plpgsql;

SELECT pem.create_role_for(
    'comp_bart',
    'Role to access BART tool in PEM',
    ARRAY['pem_component'],
    -- INSERT
    '{}'::text[],
    -- UPDATE
    '{}'::text[],
    -- DELETE
    '{}'::text[],
    -- ALL
    ARRAY[
        ARRAY['pem', 'bart'],
        ARRAY['pem', 'bart_config'],
        ARRAY['pem', 'bart_server_binding'],
        ARRAY['pem', 'bart_server_config'],
        ARRAY['pem', 'bart_backups'],
        ARRAY['pem', 'job'],
        ARRAY['pem', 'jobstep'],
        ARRAY['pem', 'schedule']
    ]
);

GRANT ALL ON TABLE pem.bart TO pem_agent;
GRANT SELECT ON TABLE pem.bart_config TO pem_agent;
GRANT ALL ON TABLE pem.bart_server_binding TO pem_agent;
GRANT SELECT ON TABLE pem.bart_server_config TO pem_agent;
GRANT ALL ON TABLE pem.bart_backups TO pem_agent;

GRANT EXECUTE ON FUNCTION pem.generate_bart_config(bart_version int8, all_params boolean) TO pem_admin;
GRANT EXECUTE ON FUNCTION pem.generate_bart_config(bart_version int8, all_params boolean) TO pem_agent;
GRANT EXECUTE ON FUNCTION pem.generate_bart_server_config(bart_server_id  integer, bart_version int8, all_params boolean) TO pem_admin;
GRANT EXECUTE ON FUNCTION pem.generate_bart_server_config(bart_server_id  integer, bart_version int8, all_params boolean) TO pem_agent;

END TRANSACTION;

