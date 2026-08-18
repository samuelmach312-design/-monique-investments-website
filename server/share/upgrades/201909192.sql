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
'SELECT 201909192::integer;'
  LANGUAGE 'sql' IMMUTABLE;
COMMENT ON FUNCTION pem.schema_version() IS 'Returns the version number of the PEM schema';

-- BART Restore config to be used while restoring backup
CREATE TABLE pem.bart_restore_config
(
    id                          serial NOT NULL,
    bart_id                     integer NOT NULL
        REFERENCES pem.bart (id) ON UPDATE RESTRICT ON DELETE CASCADE,
    agent_id                integer NOT NULL
        REFERENCES pem.agent (id) ON UPDATE RESTRICT ON DELETE CASCADE,
    backup_id                   bigint NOT NULL,
    job_id                      integer
        REFERENCES pem.job (jobid) ON UPDATE RESTRICT ON DELETE CASCADE,
    remote_user                 text,
    remote_host                 text,
    ssh_port                    integer,
    restore_path                text,
    tablespace_oid              integer[],
    tablespace_path             text[],
    worker                      integer,
    copy_wals                   boolean,
    pitr                        boolean,
    timeline_id                 text,
    transaction_id              text,
    timestamp                   timestamp with time zone,
    message                     text,
    status                      text
);

COMMENT ON TABLE pem.bart_restore_config IS 'Store BART Restore config';
COMMENT ON COLUMN pem.bart_restore_config.id IS 'Unique id';
COMMENT ON COLUMN pem.bart_restore_config.bart_id IS 'BART Id';
COMMENT ON COLUMN pem.bart_restore_config.agent_id IS 'Agent Id';
COMMENT ON COLUMN pem.bart_restore_config.backup_id IS 'Backup id to restore';
COMMENT ON COLUMN pem.bart_restore_config.job_id IS 'Job id of bart restore job';
COMMENT ON COLUMN pem.bart_restore_config.remote_user IS 'Remote user of the remote host';
COMMENT ON COLUMN pem.bart_restore_config.remote_host IS 'Remote host for the restore';
COMMENT ON COLUMN pem.bart_restore_config.ssh_port IS 'Port used for SSH connection';
COMMENT ON COLUMN pem.bart_restore_config.restore_path IS 'Path where backup will restore';
COMMENT ON COLUMN pem.bart_restore_config.tablespace_oid IS 'Array of tablespace OID of the backup';
COMMENT ON COLUMN pem.bart_restore_config.tablespace_path IS 'Array of tablespace path of the backup';
COMMENT ON COLUMN pem.bart_restore_config.worker IS 'Number of workers for parallel restore';
COMMENT ON COLUMN pem.bart_restore_config.copy_wals IS 'Copy WALs to restore path flag';
COMMENT ON COLUMN pem.bart_restore_config.pitr IS 'Point in time recovery(PITR) flag';
COMMENT ON COLUMN pem.bart_restore_config.timeline_id IS 'Timeline ID for PITR restore';
COMMENT ON COLUMN pem.bart_restore_config.transaction_id IS 'Transaction(XID) for PITR restore';
COMMENT ON COLUMN pem.bart_restore_config.timestamp IS 'Timestamp for PITR restore';
COMMENT ON COLUMN pem.bart_restore_config.message IS 'Message from restore job';
COMMENT ON COLUMN pem.bart_restore_config.status IS 'Status of BART restore';

GRANT ALL ON TABLE pem.bart_restore_config TO pem_agent;

-- Add new columns required for BART restore in the pem.bart_backups
ALTER TABLE pem.bart_backups
    DROP COLUMN tablespace_oid;

ALTER TABLE pem.bart_backups
    ADD COLUMN tablespace_oid integer[];
ALTER TABLE pem.bart_backups
    ADD COLUMN tablespace_name text[];
ALTER TABLE pem.bart_backups
    ADD COLUMN tablespace_path text[];

COMMENT ON COLUMN pem.bart_backups.tablespace_oid IS 'Array of tablespace OID of the backup';
COMMENT ON COLUMN pem.bart_backups.tablespace_name IS 'Array of tablespace name of the backup';
COMMENT ON COLUMN pem.bart_backups.tablespace_path IS 'Array of tablespace path of the backup';

DROP TABLE IF EXISTS pem.server_bart_binding;
DROP TABLE IF EXISTS pem.bart_server_binding;

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

GRANT ALL ON TABLE pem.bart_server_binding TO pem_agent;

DROP TABLE IF EXISTS pem.server_bart_config;
DROP TABLE IF EXISTS pem.bart_server_config;

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

GRANT SELECT ON TABLE pem.bart_server_config TO pem_agent;

GRANT ALL ON TABLE pem.bart_server_binding TO pem_comp_bart;
GRANT ALL ON TABLE pem.bart_server_config TO pem_comp_bart;

END TRANSACTION;
