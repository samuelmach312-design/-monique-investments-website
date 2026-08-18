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
'SELECT 201804021::integer;'
  LANGUAGE 'sql' IMMUTABLE;
COMMENT ON FUNCTION pem.schema_version() IS 'Returns the version number of the PEM schema';

ALTER TABLE pem.job
ADD COLUMN userid oid DEFAULT pem.current_user_id();

DO $$
DECLARE
  rls_supported boolean;
BEGIN
    SELECT (count(*) = 1) INTO rls_supported FROM pg_catalog.pg_class WHERE relname = 'pg_policy' AND relnamespace = (SELECT oid FROM pg_catalog.pg_namespace WHERE nspname = 'pg_catalog');

    IF rls_supported THEN

	RAISE INFO 'MODIFYING RLS policy for pem.job...';
        EXECUTE 'DROP POLICY IF EXISTS pem_job_select ON pem.job';
        EXECUTE 'DROP POLICY IF EXISTS pem_job_update ON pem.job';
        EXECUTE 'DROP POLICY IF EXISTS pem_job_insert ON pem.job';
        EXECUTE 'DROP POLICY IF EXISTS pem_job_delete ON pem.job';

	RAISE INFO 'RLS policy enable on pem.job...';
	EXECUTE $SQL$
        ALTER TABLE pem.job ENABLE ROW LEVEL SECURITY
        $SQL$;

	RAISE INFO 'SELECT RLS policy for pem.job...';
	EXECUTE $SQL$
	CREATE POLICY pem_job_select
	ON pem.job
	FOR SELECT
	USING (
	  pg_catalog.pg_has_role('pem_agent','member'::text)
	  OR (
	    pg_catalog.pg_has_role('pem_admin','member'::text)
	    AND agent_id IN (SELECT id FROM pem.avail_agents)
	  )
	  OR userid = pem.current_user_id()
	)
	$SQL$;

	RAISE INFO 'UPDATE RLS policy for pem.job...';
	EXECUTE $SQL$
	CREATE POLICY pem_job_update
	ON pem.job
	FOR UPDATE
	USING (
	  pg_catalog.pg_has_role('pem_agent','member'::text)
	  OR (
	    pg_catalog.pg_has_role('pem_admin','member'::text)
	    AND agent_id IN (SELECT id FROM pem.avail_agents)
	  )
	  OR userid = pem.current_user_id()
	)
	WITH CHECK (
	  pg_catalog.pg_has_role('pem_agent','member'::text)
	  OR (
	    pg_catalog.pg_has_role('pem_admin','member'::text)
	    AND agent_id IN (SELECT id FROM pem.avail_agents)
	  )
	  OR userid = pem.current_user_id()
	)
	$SQL$;

	RAISE INFO 'INSERT RLS policy for pem.job...';
	EXECUTE $SQL$
	CREATE POLICY pem_job_insert
	ON pem.job
	FOR INSERT
	WITH CHECK (
	  pg_catalog.pg_has_role('pem_manage_schedule_task', 'member'::text)
	)
	$SQL$;

	RAISE INFO 'DELETE RLS policy for pem.job...';
	EXECUTE $SQL$
	CREATE POLICY pem_job_delete
	ON pem.job
	FOR DELETE
	USING (
	  pg_catalog.pg_has_role('pem_agent','member'::text)
	  OR (
	    pg_catalog.pg_has_role('pem_admin','member'::text)
	    AND agent_id IN (SELECT id FROM pem.avail_agents)
	  )
	  OR userid = pem.current_user_id()
	)
	$SQL$;

	RAISE INFO 'MODIFYING RLS policy for pem.jobstep...';
        EXECUTE 'DROP POLICY IF EXISTS pem_jobstep_select ON pem.jobstep';
        EXECUTE 'DROP POLICY IF EXISTS pem_jobstep_update ON pem.jobstep';
        EXECUTE 'DROP POLICY IF EXISTS pem_jobstep_insert ON pem.jobstep';
        EXECUTE 'DROP POLICY IF EXISTS pem_jobstep_delete ON pem.jobstep';

	RAISE INFO 'RLS policy enable on pem.jobstep...';
	EXECUTE $SQL$
        ALTER TABLE pem.jobstep ENABLE ROW LEVEL SECURITY
        $SQL$;

	RAISE INFO 'SELECT RLS policy for pem.jobstep...';
	EXECUTE $SQL$
	CREATE POLICY pem_jobstep_select
	ON pem.jobstep
	FOR SELECT
	USING (
	  jstjobid in (SELECT jobid FROM pem.job)
	)
	$SQL$;

	RAISE INFO 'UPDATE RLS policy for pem.jobstep...';
	EXECUTE $SQL$
	CREATE POLICY pem_jobstep_update
	ON pem.jobstep
	FOR UPDATE
	USING (
	  jstjobid in (SELECT jobid FROM pem.job)
	)
	WITH CHECK (
	  jstjobid in (SELECT jobid FROM pem.job)
	)
	$SQL$;

	RAISE INFO 'INSERT RLS policy for pem.jobstep...';
	EXECUTE $SQL$
	CREATE POLICY pem_jobstep_insert
	ON pem.jobstep
	FOR INSERT
	WITH CHECK (
	  jstjobid in (SELECT jobid FROM pem.job)
	)
	$SQL$;

	RAISE INFO 'DELETE RLS policy for pem.jobstep...';
	EXECUTE $SQL$
	CREATE POLICY pem_jobstep_delete
	ON pem.jobstep
	FOR DELETE
	USING (
	  jstjobid in (SELECT jobid FROM pem.job)
	)
	$SQL$;

	RAISE INFO 'MODIFYING RLS policy for pem.schedule...';
        EXECUTE 'DROP POLICY IF EXISTS pem_schedule_select ON pem.schedule';
        EXECUTE 'DROP POLICY IF EXISTS pem_schedule_update ON pem.schedule';
        EXECUTE 'DROP POLICY IF EXISTS pem_schedule_insert ON pem.schedule';
        EXECUTE 'DROP POLICY IF EXISTS pem_schedule_delete ON pem.schedule';

	RAISE INFO 'RLS policy enable on pem.job...';
	EXECUTE $SQL$
        ALTER TABLE pem.schedule ENABLE ROW LEVEL SECURITY
        $SQL$;

	RAISE INFO 'SELECT RLS policy for pem.schedule...';
	EXECUTE $SQL$
	CREATE POLICY pem_schedule_select
	ON pem.schedule
	FOR SELECT
	USING (
	  jscjobid in (SELECT jobid FROM pem.job)
	)
	$SQL$;

	RAISE INFO 'UPDATE RLS policy for pem.schedule...';
	EXECUTE $SQL$
	CREATE POLICY pem_schedule_update
	ON pem.schedule
	FOR UPDATE
	USING (
	  jscjobid in (SELECT jobid FROM pem.job)
	)
	WITH CHECK (
	  jscjobid in (SELECT jobid FROM pem.job)
	)
	$SQL$;

	RAISE INFO 'INSERT RLS policy for pem.schedule...';
	EXECUTE $SQL$
	CREATE POLICY pem_schedule_insert
	ON pem.schedule
	FOR INSERT
	WITH CHECK (
	  jscjobid in (SELECT jobid FROM pem.job)
	)
	$SQL$;

	RAISE INFO 'DELETE RLS policy for pem.schedule...';
	EXECUTE $SQL$
	CREATE POLICY pem_schedule_delete
	ON pem.schedule
	FOR DELETE
	USING (
	  jscjobid in (SELECT jobid FROM pem.job)
	)
	$SQL$;

	RAISE INFO 'MODIFYING RLS policy for pem.jobsteplog...';
        EXECUTE 'DROP POLICY IF EXISTS pem_jobsteplog_select ON pem.jobsteplog';
        EXECUTE 'DROP POLICY IF EXISTS pem_jobsteplog_update ON pem.jobsteplog';
        EXECUTE 'DROP POLICY IF EXISTS pem_jobsteplog_insert ON pem.jobsteplog';
        EXECUTE 'DROP POLICY IF EXISTS pem_jobsteplog_delete ON pem.jobsteplog';

	RAISE INFO 'RLS policy enable on pem.jobsteplog...';
	EXECUTE $SQL$
        ALTER TABLE pem.jobsteplog ENABLE ROW LEVEL SECURITY
        $SQL$;

	RAISE INFO 'SELECT RLS policy for pem.jobsteplog...';
	EXECUTE $SQL$
	CREATE POLICY pem_jobsteplog_select
	ON pem.jobsteplog
	FOR SELECT
	USING (
	  jsljstid IN (SELECT jstid FROM pem.jobstep)
	)
	$SQL$;

	RAISE INFO 'UPDATE RLS policy for pem.jobsteplog...';
	EXECUTE $SQL$
	CREATE POLICY pem_jobsteplog_update
	ON pem.jobsteplog
	FOR UPDATE
	USING (
	  jsljstid IN (SELECT jstid FROM pem.jobstep)
	)
	WITH CHECK (
	  jsljstid IN (SELECT jstid FROM pem.jobstep)
	)
	$SQL$;

	RAISE INFO 'INSERT RLS policy for pem.jobsteplog...';
	EXECUTE $SQL$
	CREATE POLICY pem_jobsteplog_insert
	ON pem.jobsteplog
	FOR INSERT
	WITH CHECK (
	  jsljstid IN (SELECT jstid FROM pem.jobstep)
	)
	$SQL$;

	RAISE INFO 'DELETE RLS policy for pem.jobsteplog...';
	EXECUTE $SQL$
	CREATE POLICY pem_jobsteplog_delete
	ON pem.jobsteplog
	FOR DELETE
	USING (
	  jsljstid IN (SELECT jstid FROM pem.jobstep)
	)
	$SQL$;

	RAISE INFO 'MODIFYING RLS policy for pem.joblog...';
        EXECUTE 'DROP POLICY IF EXISTS pem_joblog_select ON pem.joblog';
        EXECUTE 'DROP POLICY IF EXISTS pem_joblog_update ON pem.joblog';
        EXECUTE 'DROP POLICY IF EXISTS pem_joblog_insert ON pem.joblog';
        EXECUTE 'DROP POLICY IF EXISTS pem_joblog_delete ON pem.joblog';

	RAISE INFO 'RLS policy enable on pem.joblog...';
	EXECUTE $SQL$
        ALTER TABLE pem.joblog ENABLE ROW LEVEL SECURITY
        $SQL$;

	RAISE INFO 'SELECT RLS policy for pem.joblog...';
	EXECUTE $SQL$
	CREATE POLICY pem_joblog_select
	ON pem.joblog
	FOR SELECT
	USING (
	  jlgjobid in (SELECT jobid FROM pem.job)
	)
	$SQL$;

	RAISE INFO 'UPDATE RLS policy for pem.joblog...';
	EXECUTE $SQL$
	CREATE POLICY pem_joblog_update
	ON pem.joblog
	FOR UPDATE
	USING (
	  jlgjobid in (SELECT jobid FROM pem.job)
	)
	WITH CHECK (
	  jlgjobid in (SELECT jobid FROM pem.job)
	)
	$SQL$;

	RAISE INFO 'INSERT RLS policy for pem.joblog...';
	EXECUTE $SQL$
	CREATE POLICY pem_joblog_insert
	ON pem.joblog
	FOR INSERT
	WITH CHECK (
	  jlgjobid in (SELECT jobid FROM pem.job)
	)
	$SQL$;

	RAISE INFO 'DELETE RLS policy for pem.joblog...';
	EXECUTE $SQL$
	CREATE POLICY pem_joblog_delete
	ON pem.joblog
	FOR DELETE
	USING (
	  jlgjobid in (SELECT jobid FROM pem.job)
	)
	$SQL$;
    END IF;
END
$$ language 'plpgsql';

GRANT INSERT, UPDATE, DELETE ON pem.chart_config TO pem_user;

-- As per DBaas requirement and input from supprt team, added "Blocking statement"
-- as part of detailed alert information in 'ungranted locks' alert template.
UPDATE pem.alert_template SET sql = $sql$
  SELECT COUNT(*) FROM pemdata.blocked_session_info
    WHERE   server_id = ${server_id}
    AND     database_name = '${database_name}'$sql$,
probe_dependency_list = '{blocked_session_info}',
info_sql = $sql$
SELECT
    database_name AS "Database name",
    blocked_pid AS "Blocked PID",
    locktype AS "Lock type",
    blocking_pid AS "Blocking PID",
    blocking_user AS "Blocking user",
    blocking_duration AS "Blocking duration",
    blocked_duration AS "Blocked duration",
    blocking_query_start AS "Blocking query start",
    blocked_query_start AS "Blocked query start",
    blocked_statement AS "Blocked statement",
    current_statement_in_blocking_process AS "Blocking statement",
    blocked_application AS "Blocked application",
    blocking_application AS "Blocking application"
FROM
    pemdata.blocked_session_info
WHERE
    server_id = '${server_id}'::integer
    AND database_name = '${database_name}';$sql$
WHERE display_name = 'Ungranted locks' AND object_type = 300;

UPDATE pem.alert_template SET sql = $sql$SELECT COUNT(*) FROM pemdata.blocked_session_info
    WHERE   server_id = ${server_id}$sql$,
probe_dependency_list = '{blocked_session_info}',
info_sql = $sql$
SELECT
    database_name AS "Database name",
    blocked_pid AS "Blocked PID",
    locktype AS "Lock type",
    blocking_pid AS "Blocking PID",
    blocking_user AS "Blocking user",
    blocking_duration AS "Blocking duration",
    blocked_duration AS "Blocked duration",
    blocking_query_start AS "Blocking query start",
    blocked_query_start AS "Blocked query start",
    blocked_statement AS "Blocked statement",
    current_statement_in_blocking_process AS "Blocking statement",
    blocked_application AS "Blocked application",
    blocking_application AS "Blocking application"
FROM
    pemdata.blocked_session_info
WHERE
    server_id = '${server_id}'::integer;$sql$
WHERE display_name = 'Ungranted locks' AND object_type = 200;


ALTER TABLE pemdata.efm_cluster_node_status ADD COLUMN efm_vip text DEFAULT NULL;
ALTER TABLE pemdata.efm_cluster_node_status ADD COLUMN efm_vip_status boolean DEFAULT NULL;
ALTER TABLE pemhistory.efm_cluster_node_status ADD COLUMN efm_vip text DEFAULT NULL;
ALTER TABLE pemhistory.efm_cluster_node_status ADD COLUMN efm_vip_status boolean DEFAULT NULL;

INSERT INTO pem.probe_column
        (probe_id, internal_name, display_name, display_position, classification,
        sql_data_type, unit_of_value, calculate_pit, discard_history, pit_by_default, is_graphable)
SELECT
        (SELECT id FROM pem.probe WHERE internal_name='efm_cluster_node_status'),
        v.internal_name, v.display_name, v.display_position, v.classification,
        v.sql_data_type, v.unit_of_value, v.calculate_pit, v.discard_history, v.pit_by_default, v.is_graphable
FROM
        (VALUES
        ('efm_vip', 'Virtual IP Address', 8, 'm', 'text', '', false, false, false, false),
        ('efm_vip_status', 'VIP Status',  9, 'm', 'boolean', '', false, false, false, false)
        ) v(internal_name, display_name, display_position, classification,
                sql_data_type, unit_of_value, calculate_pit, discard_history, pit_by_default, is_graphable);

COMMIT TRANSACTION;
