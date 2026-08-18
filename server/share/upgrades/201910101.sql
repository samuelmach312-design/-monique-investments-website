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
'SELECT 201910101::integer;'
  LANGUAGE 'sql' IMMUTABLE;
COMMENT ON FUNCTION pem.schema_version() IS 'Returns the version number of the PEM schema';

-- Only these server(s) are available, which meets following conditions:
-- 1.  Active
-- 2a. No team is specified.
-- OR
-- 2b. current_user is a superuser
-- OR
-- 2c. Current user is a member of pem_super_admin
-- OR
-- 2d. Current User is the owner
-- OR
-- 2e. Current User is the member of the specified team/role.
CREATE OR REPLACE VIEW pem.avail_servers AS
	SELECT
		s.id AS id,
		s.description AS description,
		s.server AS server,
		s.port AS port,
		s.database AS database,
		s.ssl AS ssl,
		s.serviceid AS serviceid,
		s.active AS active,
		s.hostaddr AS hostaddr,
		s.service AS service,
		s.alert_blackout AS alert_blackout,
		s.owner AS owner,
		s.team AS team,
		o.rolname AS server_owner,
		s.is_remote_monitoring AS is_remote_monitoring,
		s.efm_cluster_name AS efm_cluster_name,
		s.efm_service_name AS efm_service_name,
		s.efm_installation_path AS efm_installation_path,
		COALESCE(so.server_group_id, s.group_id, 1) AS group_id
	FROM (
		SELECT s.*, r.rolsuper AS rolsuper FROM pem.server s, pg_catalog.pg_roles r WHERE r.rolname = current_user
	) AS s
		LEFT OUTER JOIN pg_catalog.pg_roles o ON (o.oid = s.owner)
		LEFT OUTER JOIN pg_catalog.pg_roles t ON (t.rolname = s.team)
		LEFT JOIN pem.server_options so ON (s.id = so.server_id AND pem_user = current_user)
	WHERE
		-- Only active servers
		s.active AND
		(
			-- Is a superuser
			s.rolsuper OR
			-- No team provided
			s.team IS NULL OR s.team = '' OR
			-- Owner of the server
			o.rolname = current_user OR
			-- Current user is member of pem_super_admin
			pg_catalog.pg_has_role('pem_super_admin', 'member') OR
			-- Valid team provided and current_user is member of the it
			(t.oid IS NOT NULL AND pg_catalog.pg_has_role(s.team, 'member'))
		);

-- Only these agent(s) are available, which meets following conditions:
-- 1.  Active
-- 2a. current_user is a superuser
-- OR
-- 2b. Current user is a member of pem_super_admin
-- OR
-- 2c. No team is specified.
-- OR
-- 2d. Current user is the owner
-- OR
-- 2e. Current user is the member of the specified team/role.
-- OR
-- 2f. Current user is having rights to view the server.
CREATE OR REPLACE VIEW pem.avail_agents AS
	SELECT
		a.id AS id,
		a.agent_capability_list AS agent_capability_list,
		COALESCE(ao.description, a.description) AS description,
		a.active AS active,
		a.heartbeat_interval AS heartbeat_interval,
		a.alert_blackout AS alert_blackout,
		a.version AS version,
		a.platform AS platform,
		a.owner AS owner,
		a.team AS team,
		o.rolname AS agent_owner,
		COALESCE(ao.group_id, a.group_id, 0) AS group_id
	FROM (SELECT a.*, r.rolsuper AS rolsuper FROM pem.agent a, pg_catalog.pg_roles r WHERE r.rolname = current_user) AS a
		LEFT JOIN pem.agent_options ao ON (a.id = ao.agent_id AND pem_user = current_user)
		LEFT OUTER JOIN pg_catalog.pg_roles o ON (o.oid = a.owner)
		LEFT OUTER JOIN pg_catalog.pg_roles t ON (t.rolname = a.team)
WHERE
		-- Only active agents
		a.active AND
		(
			-- current user is superuser
			a.rolsuper OR
			-- No team provided
			a.team IS NULL OR a.team = '' OR
			-- Owner of the agent
			o.rolname = current_user OR
			-- Is a superuser
			pg_catalog.pg_has_role('pem_super_user', 'member') OR
			-- Valid team provided and current_user is member of the it
			(t.oid IS NOT NULL AND pg_catalog.pg_has_role(a.team, 'member'))
		) OR
			-- Current user is having rights to view the server.
			EXISTS(
				SELECT 1 FROM pem.agent_server_binding asb
				JOIN pem.avail_servers asr ON (
					asr.id = asb.server_id AND asb.agent_id = a.id
				)
			);

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
	),
	non_keys AS (
		SELECT rn, line, tokens FROM (
			SELECT rn, line, regexp_split_to_array(
				line , '(?:(.*?)(%[a-zA-Z_]+%)(.*)){1}'
			) AS tokens
			FROM newlines
		) not_matched
		WHERE array_length(tokens, 1) = 1
	),
	rest AS (
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
		UNION
		SELECT rn, line FROM non_keys
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
				SELECT regexp_split_to_array(input_str, E'\n') AS lines
			) regexp_tbl
		) each_line
	),
	keys AS (
		SELECT rn, line, regexp_matches(
			line, '(?:(.*?)(%[a-zA-Z_]+%)(.*)){1}', 'g'
		) AS tokens
		FROM newlines
	),
	non_keys AS (
		SELECT rn, line, tokens FROM (
			SELECT rn, line, regexp_split_to_array(
				line , '(?:(.*?)(%[a-zA-Z_]+%)(.*)){1}'
			) AS tokens
			FROM newlines
		) not_matched
		WHERE array_length(tokens, 1) = 1
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
		UNION
		SELECT rn, line FROM non_keys
	) res;

	RETURN result;
END;
$$ LANGUAGE 'plpgsql';

-- Fix PEM-2799
ALTER TABLE pem.bart DROP CONSTRAINT bart_version_fkey;

-- Fix PEM-2763
ALTER TABLE pem.bart_log DROP CONSTRAINT bart_log_job_log_id_fkey;

END TRANSACTION;
