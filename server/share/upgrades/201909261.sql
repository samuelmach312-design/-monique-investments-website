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
'SELECT 201909261::integer;'
  LANGUAGE 'sql' IMMUTABLE;
COMMENT ON FUNCTION pem.schema_version() IS 'Returns the version number of the PEM schema';

CREATE OR REPLACE FUNCTION pem.substitute_jobstep_info(
	input_str TEXT, info json
)
RETURNS TEXT AS
$$
DECLARE
	result TEXT;
BEGIN
    WITH newlines AS (
        SELECT lines[rn] AS line, rn
        FROM (
            SELECT lines, generate_subscripts(lines, 1) AS rn
            FROM (
                SELECT
                regexp_split_to_array(input_str, E'\n') AS lines
            ) regexp_tbl
        ) each_line
    ),
    keys AS (
        SELECT rn, line, regexp_matches(
            line, '(?:(.*?)(%[a-zA-Z_]+%)(.*)){1}', 'g'
        ) AS tokens
        FROM newlines
    ), rest AS (
        SELECT rn, line, replace(line, pattern_line, '') AS rest
        FROM (
            SELECT
                rn, line,
                array_to_string(array_agg(tokens), '', '') AS pattern_line
            FROM (
                SELECT rn, line, array_to_string(tokens, '', '') AS tokens
                FROM keys
            ) a GROUP BY rn, line
        ) rest_lines
    )
    SELECT array_to_string(array_agg(res.line ORDER BY res.rn), E'\n', '')
    INTO result
    FROM (
        SELECT k.rn, k.line || COALESCE(r.rest, '') AS line
        FROM (
            SELECT
                k.rn, array_to_string(array_agg(k.res ORDER BY k.rn), '', '') AS line
            FROM (
                SELECT
                    rn,
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
                        CASE
                        WHEN (info->>'jstenabled')::boolean IS TRUE THEN 'Yes'
                        ELSE 'False'
                        END
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
                            info->>'server_hostaddr' != ''
                            THEN info->>'server_hostaddr'
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
                    END || COALESCE(tokens[3], '') AS res
                FROM keys
            ) AS k
            GROUP BY k.rn
        ) k
        LEFT JOIN rest r ON (k.rn = r.rn)
    ) res;

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
    WITH newlines AS (
        SELECT lines[rn] AS line, rn
        FROM (
            SELECT lines, generate_subscripts(lines, 1) AS rn
            FROM (
                SELECT
                regexp_split_to_array(input_str, E'\n') AS lines
            ) regexp_tbl
        ) each_line
    ),
    keys AS (
        SELECT rn, line, regexp_matches(
            line, '(?:(.*?)(%[a-zA-Z_]+%)(.*)){1}', 'g'
        ) AS tokens
        FROM newlines
    ), rest AS (
        SELECT rn, line, replace(line, pattern_line, '') AS rest
        FROM (
            SELECT
                rn, line,
                array_to_string(array_agg(tokens), '', '') AS pattern_line
            FROM (
                SELECT rn, line, array_to_string(tokens, '', '') AS tokens
                FROM keys
            ) a GROUP BY rn, line
        ) rest_lines
    )
    SELECT array_to_string(array_agg(res.line ORDER BY res.rn), E'\n', '')
    INTO result
    FROM (
        SELECT k.rn, k.line || COALESCE(r.rest, '') AS line
        FROM (
            SELECT
                k.rn, array_to_string(array_agg(k.res ORDER BY k.rn), '', '') AS line
            FROM (
                SELECT
                    rn,
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
                    END || COALESCE(tokens[3], '') AS res
                FROM keys
            ) AS k
            GROUP BY k.rn
        ) k
        LEFT JOIN rest r ON (k.rn = r.rn)
    ) res;

	RETURN result;
END;
$$ LANGUAGE 'plpgsql';

-- Changes for JIRA: PEM-2711
ALTER TABLE pem.bart_server_binding
    DROP COLUMN IF EXISTS jobs_id;

ALTER TABLE pem.bart_server_binding
    ADD COLUMN job_id integer
    REFERENCES pem.job (jobid) ON DELETE SET NULL;

COMMENT ON COLUMN pem.bart_server_binding.job_id IS 'BART managed database server job id';

DROP FUNCTION pem.generate_bart_server_config(bart_server_id  integer, bart_version int8, all_params boolean);

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
          bart_server_config_text = bart_server_config_text || E'\n' || server_row.name || ' = ' || COALESCE(TRIM(server_row.value), '');
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

GRANT EXECUTE ON FUNCTION pem.generate_bart_server_config(bart_server_id  integer, bart_version int8, all_params boolean, tbl_server_id  integer, tablespace_str text) TO pem_admin;

GRANT EXECUTE ON FUNCTION pem.generate_bart_server_config(bart_server_id  integer, bart_version int8, all_params boolean, tbl_server_id  integer, tablespace_str text) TO pem_agent;

END TRANSACTION;
