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
'SELECT 201802051::integer;'
  LANGUAGE 'sql' IMMUTABLE;
COMMENT ON FUNCTION pem.schema_version() IS 'Returns the version number of the PEM schema';

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

            OPEN info_sql_curs FOR EXECUTE info_sql;

            LOOP
                FETCH NEXT FROM info_sql_curs INTO info_sql_rec;
                EXIT WHEN NOT FOUND;

                column_value := ARRAY[]::text[];

                FOR hs_row IN SELECT kv."key", kv."value" FROM each(hstore(info_sql_rec)) kv
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

CREATE OR REPLACE FUNCTION pem.get_ssl_ca_file()
RETURNS TEXT AS $$
    SELECT setting FROM pg_catalog.pg_settings WHERE name = 'ssl_ca_file';
$$ LANGUAGE sql SECURITY DEFINER;

CREATE OR REPLACE FUNCTION pem.get_ssl_crt_file()
RETURNS TEXT AS $$
    SELECT setting FROM pg_catalog.pg_settings WHERE name = 'ssl_cert_file';
$$ LANGUAGE sql SECURITY DEFINER;

CREATE OR REPLACE FUNCTION pem.get_ssl_key_file()
RETURNS TEXT AS $$
    SELECT setting FROM pg_catalog.pg_settings WHERE name = 'ssl_key_file';
$$ LANGUAGE sql SECURITY DEFINER;

CREATE OR REPLACE FUNCTION pem.get_ssl_crl_file()
RETURNS TEXT AS $$
    SELECT setting FROM pg_catalog.pg_settings WHERE name = 'ssl_crl_file';
$$ LANGUAGE sql SECURITY DEFINER;


GRANT EXECUTE ON FUNCTION pem.get_ssl_ca_file() TO pem_admin;
GRANT EXECUTE ON FUNCTION pem.get_ssl_crt_file() TO pem_admin;
GRANT EXECUTE ON FUNCTION pem.get_ssl_key_file() TO pem_admin;
GRANT EXECUTE ON FUNCTION pem.get_ssl_crl_file() TO pem_admin;

GRANT EXECUTE ON FUNCTION pem.get_data_directory() TO pem_agent;
GRANT EXECUTE ON FUNCTION pem.get_ssl_ca_file() TO pem_agent;
GRANT EXECUTE ON FUNCTION pem.get_ssl_crt_file() TO pem_agent;
GRANT EXECUTE ON FUNCTION pem.get_ssl_key_file() TO pem_agent;
GRANT EXECUTE ON FUNCTION pem.get_ssl_crl_file() TO pem_agent;

-- Function to create 'Check CA certificate expiry' job.
DO $$DECLARE
    job_id  integer;
	name    text;
BEGIN
	-- Check if the job already exists.
    SELECT jobid INTO job_id FROM pem.job WHERE jobname = 'Check CA certificate expiry' AND agent_id = 1;

    IF (NOT FOUND) THEN
        -- Create CA certificate expiry job.
        INSERT INTO pem.job(jobname, jobdesc, agent_id, issystemjob, jobnextrun) VALUES('Check CA certificate expiry', 'This job check the expiry of CA certificate.', 1, true, now()) RETURNING jobid INTO job_id;
    END IF;

    -- Check if the job step already exists.
    SELECT jstname INTO name FROM pem.jobstep WHERE jstname = 'Check CA certificate expiry' AND jstjobid = job_id;

    IF (NOT FOUND) THEN
        -- Create data purging step.
        INSERT INTO pem.jobstep(jstjobid, jstname, jstdesc, jstkind, jstcode) VALUES (job_id, 'Check CA certificate expiry','This job step runs to check the expiry of CA certificate.', 'i', 'check_server_certificate_expiry');
    END IF;
END$$;

-- Create a roles table which stores the rolid and the component to
-- which it has access.
CREATE TABLE pem.roles
(
    rolid OID,
    component text,
    description text,
    PRIMARY KEY(rolid)
);

-- This function will create roles based on component given and
-- allow to set permissions(select, update, delete, all etc.)
-- on associated tables.
-- and set parent roles for created role.
CREATE OR REPLACE FUNCTION pem.create_role_for(
    component_name text,
    description text,
    parent_roles text[] DEFAULT '{}'::text[],
    priv_insert_on_tables text[] DEFAULT '{}'::text[],
    priv_update_on_tables text[] DEFAULT '{}'::text[],
    priv_delete_on_tables text[] DEFAULT '{}'::text[],
    priv_all_on_tables text[] DEFAULT '{}'::text[]
)
RETURNS VOID AS
$$
DECLARE
    role_name text;
    temp_val text;
    tbl text[];
    parent_role text;
    role_oid oid := NULL;
BEGIN
    role_name := quote_ident('pem_'|| component_name);

    -- Fetch oid of newly created role.
    SELECT oid INTO role_oid FROM pg_roles WHERE quote_ident(rolname) = role_name;
    IF role_oid IS NULL THEN
        EXECUTE 'CREATE ROLE ' || quote_ident(role_name);
        SELECT oid INTO role_oid FROM pg_roles WHERE quote_ident(rolname) = role_name;
    END IF;

    -- Add new role entry into pem.roles table.
    INSERT INTO pem.roles VALUES (role_oid, component_name, description);

    IF array_length(priv_insert_on_tables, 1) <> 0  THEN
        FOREACH tbl SLICE 1 IN ARRAY priv_insert_on_tables LOOP
            IF array_length(tbl, 1) < 2 THEN
                RAISE INFO 'Granting INSERT permission to table: pem.%', tbl[1];
                EXECUTE 'GRANT INSERT ON TABLE ' ||
                    'pem.' || quote_ident(tbl[1]) || ' TO ' || role_name;
            ELSE
                RAISE INFO 'Granting INSERT permission to table: %.%',
                    tbl[1], tbl[2];

                EXECUTE 'GRANT INSERT ON TABLE ' ||
                    quote_ident(tbl[1]) || '.' || quote_ident(tbl[2]) || ' TO ' ||
                    role_name;
            END IF;
        END LOOP;
    END IF;

    -- Grant "UPDATE" permission to the given role
    IF array_length(priv_update_on_tables, 1) <> 0  THEN
        FOREACH tbl SLICE 1 IN ARRAY priv_update_on_tables LOOP
            IF array_length(tbl, 1) < 2 THEN
                RAISE INFO 'Granting UPDATE permission to table: pem.%', tbl[1];
                EXECUTE 'GRANT UPDATE ON TABLE ' ||
                    'pem.' || quote_ident(tbl[1]) || ' TO ' || role_name;
            ELSE
                RAISE INFO 'Granting UPDATE permission to table: %.%',
                    tbl[1], tbl[2];

                EXECUTE 'GRANT UPDATE ON TABLE ' ||
                    quote_ident(tbl[1]) || '.' || quote_ident(tbl[2]) || ' TO ' ||
                    role_name;
            END IF;
        END LOOP;
    END IF;

    -- Grant "DELETE" permission to the given role
    IF array_length(priv_delete_on_tables, 1) <> 0  THEN
        FOREACH tbl SLICE 1 IN ARRAY priv_delete_on_tables LOOP
            IF array_length(tbl, 1) < 2 THEN
                RAISE INFO 'Granting DELETE permission to table: pem.%', tbl[1];
                EXECUTE 'GRANT DELETE ON TABLE ' ||
                    'pem.' || quote_ident(tbl[1]) || ' TO ' || role_name;
            ELSE
                RAISE INFO 'Granting DELETE permission to table: %.%',
                    tbl[1], tbl[2];

                EXECUTE 'GRANT DELETE ON TABLE ' ||
                    quote_ident(tbl[1]) || '.' || quote_ident(tbl[2]) || ' TO ' ||
                    role_name;
            END IF;
        END LOOP;
    END IF;

    -- Grant "ALL" permission to the given role
    IF array_length(priv_all_on_tables, 1) <> 0  THEN
        FOREACH tbl SLICE 1 IN ARRAY priv_all_on_tables LOOP
            IF array_length(tbl, 1) < 2 THEN
                RAISE INFO 'Granting ALL permission to table: pem.%', tbl[1];
                EXECUTE 'GRANT ALL ON TABLE ' ||
                    'pem.' || quote_ident(tbl[1]) || ' TO ' || role_name;
            ELSE
                RAISE INFO 'Granting ALL permission to table: %.%',
                    tbl[1], tbl[2];

                EXECUTE 'GRANT ALL ON TABLE ' ||
                    quote_ident(tbl[1]) || '.' || quote_ident(tbl[2]) || ' TO ' ||
                    role_name;
            END IF;
        END LOOP;
    END IF;

    -- Iterate over parent roles and Grant them role_name
    FOREACH parent_role IN ARRAY parent_roles LOOP
      EXECUTE 'GRANT ' || role_name || ' TO ' || quote_ident(parent_role);
    END LOOP;
END
$$ LANGUAGE 'plpgsql';

-- Create new roles for various components
SELECT pem.create_role_for(
    'super_admin',
    'Role to manage/configure everything on Postgres Enteprise Manager'
);

SELECT pem.create_role_for(
    'admin',
    'Role for administration/management/configuration of all visible agents/servers, and monitored objects',
    ARRAY['pem_super_admin']
);

SELECT pem.create_role_for(
    'config',
    'Role for configuration management of Postgres Enterprise Manager',
    ARRAY['pem_admin'],
    '{}'::text[],
    '{}'::text[],
    '{}'::text[],
    ARRAY[
        ARRAY['pem', 'config'],
        ARRAY['pem', 'email_group'],
        ARRAY['pem', 'email_group_option']
    ]
);

SELECT pem.create_role_for(
    'component',
    'Role to run/execute all wizard/dialog based components',
    ARRAY['pem_admin']
);

SELECT pem.create_role_for(
    'manage_schedule_task',
    'Role to configure the schedule tasks',
    ARRAY['pem_admin'],
    -- INSERT
    '{}'::text[],
    -- UPDATE
    '{}'::text[],
    -- DELETE
    '{}'::text[],
    -- ALL
    ARRAY[
        ARRAY['pem', 'job'],
        ARRAY['pem', 'jobstep'],
        ARRAY['pem', 'schedule']
    ]
);

SELECT pem.create_role_for(
    'server_service_manager',
    'Role for allowing to restart/reload the monitored database server (if server-id provided)',
    ARRAY['pem_admin']
);
GRANT pem_manage_schedule_task TO pem_server_service_manager;

SELECT pem.create_role_for(
    'manage_alert',
    'Role for managing/configuring alerts, and its templates',
    ARRAY['pem_admin'],
    -- INSERT
    '{}'::text[],
    -- UPDATE
    '{}'::text[],
    -- DELETE
    '{}'::text[],
    -- ALL
    ARRAY[
        ARRAY['pem', 'alert_template']
    ]
);

SELECT pem.create_role_for(
    'config_alert',
    'Role for configuring the alerts on any monitored objects',
    ARRAY['pem_config', 'pem_manage_alert'],
    -- INSERT
    '{}'::text[],
    -- UPDATE
    '{}'::text[],
    -- DELETE
    '{}'::text[],
    -- ALL
    ARRAY[ARRAY['pem', 'alert']]
);

SELECT pem.create_role_for(
    'manage_probe',
    'Role to create, update, delete the custom probes, and change its configuration.',
    ARRAY['pem_admin'],
    -- INSERT
    '{}'::text[],
    -- UPDATE
    '{}'::text[],
    -- DELETE
    '{}'::text[],
    -- ALL
    ARRAY[
        ARRAY['pem', 'probe'],
        ARRAY['pem', 'probe_column'],
        ARRAY['pem', 'probe_server_version'],
        ARRAY['pem', 'jobstep']
    ]
);

-- Allow to refer the pem.server(id), pem.agent table(id)
GRANT REFERENCES (id) ON pem.server TO pem_manage_probe;
GRANT REFERENCES (id) ON pem.agent TO pem_manage_probe;

-- Allow to create probe table in pemdata, and pemhistory schema
GRANT CREATE ON SCHEMA pemdata TO pem_manage_probe;
GRANT CREATE ON SCHEMA pemhistory TO pem_manage_probe;

SELECT pem.create_role_for(
    'config_probe',
    'Role for configuration of probes (history retention, execution frequency, enable/disble the probe) on all visible monitored objects',
    ARRAY['pem_config', 'pem_manage_probe'],
    -- INSERT
    '{}'::text[],
    -- UPDATE
    '{}'::text[],
    -- DELETE
    '{}'::text[],
    -- ALL
    ARRAY[
        ARRAY['pem', 'probe_config_agent'],
        ARRAY['pem', 'probe_config_server'],
        ARRAY['pem', 'probe_config_database'],
        ARRAY['pem', 'probe_config_schema'],
        ARRAY['pem', 'probe_config_table'],
        ARRAY['pem', 'probe_config_index'],
        ARRAY['pem', 'probe_config_sequence'],
        ARRAY['pem', 'probe_config_function'],
        ARRAY['pem', 'probe_config_view'],
        ARRAY['pem', 'job']
    ]
);

SELECT pem.create_role_for(
    'database_server_registration',
    'Role to register a database server',
    ARRAY['pem_admin'],
    -- INSERT
    '{}'::text[],
    -- UPDATE
    '{}'::text[],
    -- DELETE
    '{}'::text[],
    -- ALL
    ARRAY[
        ARRAY['pem', 'server'],
        ARRAY['pem', 'server_option'],
        ARRAY['pem', 'agent_server_binding'],
        ARRAY['pem', 'probe_config_server']
    ]
);

SELECT pem.create_role_for(
    'manage_efm',
    'Role to manage the EFM functionalities',
    ARRAY['pem_admin']
);
GRANT pem_manage_schedule_task TO pem_manage_efm;

SELECT pem.create_role_for(
    'rest_api',
    'Role to access the REST API',
    ARRAY['pem_admin']
);

SELECT pem.create_role_for(
    'comp_postgres_expert',
    'Role for running the Postgres expert',
    ARRAY['pem_component']
);

SELECT pem.create_role_for(
    'comp_auto_discovery',
    'Role to run the Auto discovery of a database server dialog',
    ARRAY['pem_component'],
    -- INSERT
    '{}'::text[],
    -- UPDATE
    '{}'::text[],
    -- DELETE
    ARRAY[ARRAY['pem', 'probe_schedule']]
);
GRANT pem_database_server_registration TO pem_comp_auto_discovery;

SELECT pem.create_role_for(
    'comp_log_analysis_expert',
    'Role to run the Log analysis expert',
    ARRAY['pem_component']
);

SELECT pem.create_role_for(
    'comp_capacity_manager',
    'Role to run the Capacity manager',
    ARRAY['pem_component'],
    '{}'::text[],
    '{}'::text[],
    '{}'::text[],
    ARRAY[
        ARRAY['pem', 'cm_template'],
        ARRAY['pem', 'cm_template_metrics'],
        ARRAY['pem', 'cm_template_path']
    ]
);

SELECT pem.create_role_for(
    'comp_log_manager',
    'Role to run the log manager',
    ARRAY['pem_component'],
    -- INSERT
    ARRAY[
        ARRAY['pem', 'alert'],
        ARRAY['pem', 'log_configuration']
    ],
    -- UPDATE
    ARRAY[ARRAY['pem', 'log_configuration']]
);
GRANT pem_server_service_manager TO pem_comp_log_manager;

SELECT pem.create_role_for(
    'comp_audit_manager',
    'Role to run the audit manager',
    ARRAY['pem_component'],
    -- INSERT
    ARRAY[
        ARRAY['pem', 'alert'],
        ARRAY['pem', 'audit_configuration']
    ],
    -- UPDATE
    ARRAY[ARRAY['pem', 'audit_configuration']]
);
GRANT pem_server_service_manager TO pem_comp_audit_manager;

SELECT pem.create_role_for(
    'comp_package_deployment',
    'Role to run the Package deployment',
    ARRAY['pem_component'],
    -- INSERT
    ARRAY[
        ARRAY['pem', 'package_installation'],
        ARRAY['pem', 'package_options']
    ],
    -- UPDATE
    ARRAY[
        ARRAY['pem', 'package_installation'],
        ARRAY['pemdata', 'package_catalog']
    ],
    -- DELETE
    ARRAY[
        ARRAY['pem', 'package_options'],
        ARRAY['pem', 'probe_schedule']
    ],
    -- ALL
    ARRAY[
        ARRAY['pem', 'job'],
        ARRAY['pem', 'jobstep'],
        ARRAY['pem', 'schedule']
    ]
);

SELECT pem.create_role_for(
    'comp_streaming_replication',
    'Role to run the Streaming replication',
    ARRAY['pem_component'],
    -- INSERT
    ARRAY[
        ARRAY['pem', 'package_installation'],
        ARRAY['pem', 'package_options']
    ],
    -- UPDATE
    ARRAY[
        ARRAY['pem', 'package_installation'],
        ARRAY['pemdata', 'package_catalog']
    ],
    -- DELETE
    ARRAY[
        ARRAY['pem', 'probe_schedule'],
        ARRAY['pem', 'package_options']
    ],
    -- ALL
    ARRAY[
        ARRAY['pem', 'sr_master'],
        ARRAY['pem', 'sr_standby'],
        ARRAY['pem', 'job'],
        ARRAY['pem', 'jobstep'],
        ARRAY['pem', 'schedule']
    ]
);
GRANT pem_server_service_manager TO pem_comp_streaming_replication;

SELECT pem.create_role_for(
    'comp_tuning_wizard',
    'Role to run the Tuning wizard',
    ARRAY['pem_component']
);
GRANT pem_server_service_manager TO pem_comp_tuning_wizard;

SELECT pem.create_role_for(
    'comp_sqlprofiler',
    'Role to run the SQL profiler',
    ARRAY['pem_component']
);
GRANT pem_manage_schedule_task TO pem_comp_sqlprofiler;

COMMIT TRANSACTION;
