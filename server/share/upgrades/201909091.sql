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
'SELECT 201909091::integer;'
  LANGUAGE 'sql' IMMUTABLE;
COMMENT ON FUNCTION pem.schema_version() IS
 'Returns the version number of the PEM schema';

-- BART backup config to be used while taking backup
CREATE TABLE pem.bart_backup_config
(
    id                      serial NOT NULL,
    bart_id                 integer NOT NULL
        REFERENCES pem.bart (id) ON UPDATE RESTRICT ON DELETE CASCADE,
    server_id               integer NOT NULL
        REFERENCES pem.server (id) ON UPDATE RESTRICT ON DELETE CASCADE,
    backup_name             text,
    backup_type             text NOT NULL,
    parent_backup_id        bigint,
    custom_parent_backup    text,
    output_format           text NOT NULL,
    gzip_compression        boolean,
    compression_level       integer,
    thread_count            integer NOT NULL,
    use_pg_basebackup       boolean,
    verify_checksum         boolean,
    backup_id               bigint,
    status                  text,
    message                 text,
    job_id                  integer NOT NULL
        REFERENCES pem.job (jobid) ON UPDATE RESTRICT ON DELETE CASCADE
);

COMMENT ON TABLE pem.bart_backup_config IS 'Store BART Backup config';
COMMENT ON COLUMN pem.bart_backup_config.id IS 'Unique id';
COMMENT ON COLUMN pem.bart_backup_config.bart_id IS 'BART Id';
COMMENT ON COLUMN pem.bart_backup_config.server_id IS 'Database server Id';
COMMENT ON COLUMN pem.bart_backup_config.backup_name IS 'Backup name to be used while taking backup';
COMMENT ON COLUMN pem.bart_backup_config.backup_type IS 'Backup type (Full/Incremental)';
COMMENT ON COLUMN pem.bart_backup_config.parent_backup_id IS 'Parent backup id for incremental backup';
COMMENT ON COLUMN pem.bart_backup_config.custom_parent_backup IS 'Custom parent backups latest/latest_full';
COMMENT ON COLUMN pem.bart_backup_config.output_format IS 'Backup output format (Tar/Plain)';
COMMENT ON COLUMN pem.bart_backup_config.gzip_compression IS 'GZip compression while taking Tar backup';
COMMENT ON COLUMN pem.bart_backup_config.thread_count IS 'Thread count for parallel backups';
COMMENT ON COLUMN pem.bart_backup_config.use_pg_basebackup IS 'pg_basebackup while taking Full backup';
COMMENT ON COLUMN pem.bart_backup_config.verify_checksum IS 'Set verify_checksum to verify tar backup';
COMMENT ON COLUMN pem.bart_backup_config.backup_id IS 'Used while running verify checksum job step';
COMMENT ON COLUMN pem.bart_backup_config.status IS 'Status of backup being taken';
COMMENT ON COLUMN pem.bart_backup_config.message IS 'Store failure message';
COMMENT ON COLUMN pem.bart_backup_config.job_id IS 'Job id of bart backup job';

GRANT ALL ON TABLE pem.bart_backup_config TO pem_agent;

DROP TABLE pem.bart_log;

-- This table store all the success and fail events of BART job
-- so that it will be useful in dashboard.
CREATE TABLE pem.bart_log (
        recorded_time           timestamp with time zone NOT NULL DEFAULT now(),
        bart_id                         integer NOT NULL -- BART Server id
            REFERENCES pem.bart (id) ON DELETE CASCADE ON UPDATE RESTRICT,
        server_name                     text,
        action                          text NOT NULL,
        status                          text NOT NULL,
        backup_id                       bigint,
        backup_name                     text,
        job_log_id                      integer
                REFERENCES pem.joblog (jlgid) ON DELETE CASCADE ON UPDATE RESTRICT,
        error_message                   text
);

COMMENT ON TABLE pem.bart_log IS 'Store the status of all BART server jobs';
COMMENT ON COLUMN pem.bart_log.recorded_time IS 'Recorded timestamp';
COMMENT ON COLUMN pem.bart_log.bart_id IS 'BART host id';
COMMENT ON COLUMN pem.bart_log.server_name IS 'Database server name managed by BART host';
COMMENT ON COLUMN pem.bart_log.action IS 'BART job name';
COMMENT ON COLUMN pem.bart_log.status IS 'BART job status';
COMMENT ON COLUMN pem.bart_log.backup_id IS 'BART backup id';
COMMENT ON COLUMN pem.bart_log.backup_name IS 'BART Backup name';
COMMENT ON COLUMN pem.bart_log.job_log_id IS 'Job log id for BART job';
COMMENT ON COLUMN pem.bart_log.error_message IS 'Log error message for BART job failure';

GRANT ALL ON TABLE pem.bart_log TO pem_agent;

END TRANSACTION;
