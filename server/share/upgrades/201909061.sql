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
'SELECT 201909061::integer;'
  LANGUAGE 'sql' IMMUTABLE;
COMMENT ON FUNCTION pem.schema_version() IS 'Returns the version number of the PEM schema';

ALTER TABLE pem.bart_log ADD COLUMN job_log_id integer;
ALTER TABLE pem.bart_log ADD COLUMN error_message text;
ALTER TABLE pem.bart_log ADD COLUMN backup_id bigint;
ALTER TABLE pem.bart_log ADD COLUMN backup_name text;

COMMENT ON COLUMN pem.bart_log.job_log_id IS 'Job log id for BART job';
COMMENT ON COLUMN pem.bart_log.error_message IS 'Log error message for BART job failure';
COMMENT ON COLUMN pem.bart_log.backup_id IS 'BART backup id';
COMMENT ON COLUMN pem.bart_log.backup_name IS 'BART Backup name';

-- Function to create BART configuration file
CREATE OR REPLACE FUNCTION pem.generate_bart_config(
    bart_host_id  integer,
    bart_version int8 DEFAULT 2004000::int8,
    all_params boolean DEFAULT true)
  RETURNS text AS
$BODY$

DECLARE
    bart_config_text    text := '';
    query               text := '';
    bart_user_name      text := '';
    row                 RECORD;
    validate_version    bool := TRUE;
BEGIN
    -- If BART installed version is not found in pem.bart_version table, we should use the latest version used in pem.bart_default_config table.
    SELECT bart_version INTO validate_version IN (SELECT DISTINCT(version) FROM pem.bart_default_config ORDER BY 1 DESC);
    IF validate_version IS FALSE THEN
        SELECT DISTINCT(version) INTO bart_version FROM pem.bart_default_config ORDER BY 1 DESC LIMIT 1;
    END IF;

    IF all_params IS FALSE THEN
      query := 'SELECT bc.name, bc.value FROM pem.bart_config bc LEFT OUTER JOIN pem.bart_default_config bdc ON (bdc.name = bc.name ) WHERE version = ' || bart_version || ' AND required_params IS TRUE AND bc.bart_id = '|| bart_host_id ||' ORDER BY bdc.seq_id;';
    ELSE
      query := 'SELECT bc.name, bc.value FROM pem.bart_config bc LEFT OUTER JOIN pem.bart_default_config bdc ON (bdc.name = bc.name ) WHERE version = ' || bart_version || ' AND bc.bart_id = '|| bart_host_id ||' ORDER BY bdc.seq_id;';
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
        ELSIF COALESCE(TRIM(row.value), '') != '' THEN
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
    server_header       text := '';
    validate_version    bool := TRUE;
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
          bart_server_config_text = bart_server_config_text || E'\n' || server_row.name || ' = ' || COALESCE(TRIM(server_row.value), '');
        END IF;
    END LOOP;

    bart_server_config_text = bart_server_config_text || E'\n';

RETURN bart_server_config_text;

END

$BODY$
  LANGUAGE plpgsql;

END TRANSACTION;
