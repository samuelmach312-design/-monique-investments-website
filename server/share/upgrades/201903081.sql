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
'SELECT 201903081::integer;'
  LANGUAGE 'sql' IMMUTABLE;
COMMENT ON FUNCTION pem.schema_version() IS
 'Returns the version number of the PEM schema';

-- Drop existing trigger as we do not have create/replace trigger.
DROP TRIGGER IF EXISTS detail_alert_information on pem.alert_status;

-- Create  trigger with updated definitions.
CREATE TRIGGER detail_alert_information
        BEFORE INSERT OR UPDATE ON pem.alert_status
        FOR EACH ROW
        EXECUTE PROCEDURE pem.get_detail_alert_info();

-- Function to execute detail alert info SQL and insert formatted string in pem.alert_status table.
CREATE OR REPLACE FUNCTION pem.get_detail_alert_info() RETURNS TRIGGER AS $$
DECLARE
    info_sql    text := '';
    a_agent_id  integer;
    a_server_id integer;
    a_database_name text:= '';
    a_schema_name text:= '';
    a_package_name text:= '';
    a_object_name text:= '';
    alert_info_str text:= '';
    comp_operator  text:= '';
    low_threshold_val text:= '';
    alert_params text[];
    info_sql_curs     REFCURSOR;
    info_sql_rec      RECORD;
    hs_row            RECORD;
    first_time    boolean := FALSE;
    arr_col_values text[];
    column_name text[] := ARRAY[]::text[];
    column_value text[] := ARRAY[]::text[];
BEGIN
    IF (NEW.alert_id IS NOT NULL)
    THEN
        -- Fetch additional sql to execute from the alert template table.
        EXECUTE 'SELECT info_sql FROM pem.alert_template WHERE id = (SELECT template_id FROM pem.alert WHERE id = ' || NEW.alert_id || ')' INTO info_sql;

        EXECUTE 'SELECT operator::text FROM pem.alert WHERE id = ' || NEW.alert_id INTO comp_operator;

        EXECUTE 'SELECT thresholds[1]::text FROM pem.alert WHERE id = ' || NEW.alert_id INTO low_threshold_val;

        EXECUTE 'SELECT params::text[] FROM pem.alert WHERE id = ' || NEW.alert_id INTO alert_params;
        -- If additional information sql is null or empty then no need to get extra information.
        IF (info_sql IS NOT NULL AND info_sql != '' AND comp_operator IS NOT NULL AND comp_operator != '' AND
            low_threshold_val IS NOT NULL AND low_threshold_val != '') THEN
            -- Fist find the all the objects of this alert.
            EXECUTE 'SELECT agent_id FROM pem.alert WHERE id = ' || NEW.alert_id INTO a_agent_id;
            EXECUTE 'SELECT server_id FROM pem.alert WHERE id = ' || NEW.alert_id INTO a_server_id;
            EXECUTE 'SELECT database_name FROM pem.alert WHERE id = ' || NEW.alert_id INTO a_database_name;
            EXECUTE 'SELECT schema_name FROM pem.alert WHERE id = ' || NEW.alert_id INTO a_schema_name;
            EXECUTE 'SELECT package_name FROM pem.alert WHERE id = ' || NEW.alert_id INTO a_package_name;
            EXECUTE 'SELECT object_name FROM pem.alert WHERE id = ' || NEW.alert_id INTO a_object_name;

            -- Replace any reference to hierarchy-related alert parameters.
            info_sql = regexp_replace(info_sql, E'\\${agent_id}', COALESCE(a_agent_id::text, '')::text, 'g');
            info_sql = regexp_replace(info_sql, E'\\${server_id}', COALESCE(a_server_id::text, '')::text, 'g');
            info_sql = regexp_replace(info_sql, E'\\${database_name}', COALESCE(a_database_name, '')::text, 'g');
            info_sql = regexp_replace(info_sql, E'\\${schema_name}', COALESCE(a_schema_name, '')::text, 'g');
            info_sql = regexp_replace(info_sql, E'\\${package_name}', COALESCE(a_package_name, '')::text, 'g');
            info_sql = regexp_replace(info_sql, E'\\${object_name}', COALESCE(a_object_name, '')::text, 'g');
            info_sql = regexp_replace(info_sql, E'\\${comparison_operator}', COALESCE(comp_operator::text, '')::text, 'g');
            info_sql = regexp_replace(info_sql, E'\\${threshold_value}', COALESCE(low_threshold_val::text, '')::text, 'g');

            /* Replace ${param_n} with corresponding alert parameters */
            FOR i IN 1..COALESCE(array_upper(alert_params, 1), 0) LOOP
                info_sql = regexp_replace(info_sql, E'\\${param_' || i || '}', alert_params[i]::text, 'g');
            END LOOP;

            BEGIN
                OPEN info_sql_curs FOR EXECUTE info_sql;

                LOOP
                    FETCH NEXT FROM info_sql_curs INTO info_sql_rec;
                    EXIT WHEN NOT FOUND;

                    column_value := ARRAY[]::text[];

                    FOR hs_row IN SELECT kv."key", kv."value" FROM each(hstore(info_sql_rec::record)) kv
                    LOOP
                        alert_info_str := alert_info_str || COALESCE(hs_row."key", '') || ' = ' || COALESCE(hs_row."value", '') || E'\n';

                        IF first_time IS FALSE THEN
                            column_name := column_name || COALESCE(hs_row."key", '');
                        END IF;

                        column_value := column_value || COALESCE(hs_row."value", '');

                    END LOOP;

                    IF first_time IS FALSE THEN
                        arr_col_values := ARRAY[column_value]::text[];
                    ELSE
                        arr_col_values := arr_col_values || column_value;
                    END IF;

                    first_time := TRUE;
                    alert_info_str := alert_info_str || E'\n\n';

                END LOOP;
                CLOSE info_sql_curs;
            EXCEPTION
                WHEN OTHERS THEN
                    RAISE EXCEPTION 'Error while executing alert detailed information SQL: %', SQLERRM;
                    RETURN NULL;
            END;

            IF first_time IS FALSE THEN
                NEW.info_cols = NULL;
                NEW.info_vals = NULL;
                NEW.info = NULL;
            ELSE
                NEW.info_cols = column_name;
                NEW.info_vals = arr_col_values;

                IF (alert_info_str IS NOT NULL AND alert_info_str != '') THEN
                    NEW.info = alert_info_str;
                END IF;
            END IF;
        END IF;
  END IF;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Set proper privileges to public schema as it is required for hstore extension used for alert detailed information.
GRANT USAGE ON SCHEMA public TO pem_agent;
GRANT USAGE ON SCHEMA public TO pem_user;
GRANT CREATE on SCHEMA public TO pem_admin;

-- PEM-1855 - For large size of shared buffer and other parameters, query gives buffer overflow error so change datatype to numeric.
UPDATE pem.probe SET probe_code=E'SELECT pg_catalog.version() AS version_string, ((select setting from pg_settings where name = ''block_size'')::decimal * (select setting from pg_settings where name = ''shared_buffers'')::decimal / (1024 * 1024))::numeric AS shared_buffers_mb, ((select setting from pg_settings where name = ''block_size'')::decimal * (select setting from pg_settings where name = ''temp_buffers'')::decimal / (1024 * 1024))::numeric AS temp_buffers_mb, ((select setting from pg_settings where name = ''block_size'')::decimal * (select setting from pg_settings where name = ''effective_cache_size'')::decimal / (1024 * 1024))::numeric AS effective_cache_size_mb, ((select setting from pg_settings where name = ''block_size'')::decimal * (select setting from pg_settings where name = ''segment_size'')::decimal / (1024 * 1024))::numeric AS segment_size_mb, ((select setting from pg_settings where name = ''block_size'')::decimal * (select setting from pg_settings where name = ''wal_segment_size'')::decimal / (1024 * 1024))::numeric AS wal_segment_size_mb, ((select setting from pg_settings where name = ''block_size'')::decimal * (select setting from pg_settings where name = ''wal_buffers'')::decimal / (1024 * 1024))::numeric AS wal_buffers_mb, (SELECT pg_postmaster_start_time())::timestamptz AS server_start_time'
WHERE id = ( SELECT id FROM pem.probe WHERE internal_name = 'server_info' );

UPDATE pem.probe_column SET sql_data_type = 'numeric'
    WHERE  internal_name IN ('shared_buffers_mb', 'temp_buffers_mb', 'effective_cache_size_mb', 'segment_size_mb', 'wal_segment_size_mb', 'wal_buffers_mb') AND probe_id = (SELECT id FROM pem.probe WHERE internal_name = 'server_info');

ALTER TABLE pemdata.server_info ALTER COLUMN shared_buffers_mb TYPE numeric;
ALTER TABLE pemdata.server_info ALTER COLUMN temp_buffers_mb TYPE numeric;
ALTER TABLE pemdata.server_info ALTER COLUMN effective_cache_size_mb TYPE numeric;
ALTER TABLE pemdata.server_info ALTER COLUMN segment_size_mb TYPE numeric;
ALTER TABLE pemdata.server_info ALTER COLUMN wal_segment_size_mb TYPE numeric;
ALTER TABLE pemdata.server_info ALTER COLUMN wal_buffers_mb TYPE numeric;

ALTER TABLE pemhistory.server_info ALTER COLUMN shared_buffers_mb TYPE numeric;
ALTER TABLE pemhistory.server_info ALTER COLUMN temp_buffers_mb TYPE numeric;
ALTER TABLE pemhistory.server_info ALTER COLUMN effective_cache_size_mb TYPE numeric;
ALTER TABLE pemhistory.server_info ALTER COLUMN segment_size_mb TYPE numeric;
ALTER TABLE pemhistory.server_info ALTER COLUMN wal_segment_size_mb TYPE numeric;
ALTER TABLE pemhistory.server_info ALTER COLUMN wal_buffers_mb TYPE numeric;

END TRANSACTION;
