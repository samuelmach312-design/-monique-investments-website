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
'SELECT 201806151::integer;'
  LANGUAGE 'sql' IMMUTABLE;
COMMENT ON FUNCTION pem.schema_version() IS 'Returns the version number of the PEM schema';

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
		EXECUTE 'ALTER TABLE pem.job ENABLE ROW LEVEL SECURITY';

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
	)$SQL$;

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
	)$SQL$;

		RAISE INFO 'INSERT RLS policy for pem.job...';
		EXECUTE $SQL$
CREATE POLICY pem_job_insert
ON pem.job
FOR INSERT
	WITH CHECK (
		pg_catalog.pg_has_role('pem_manage_schedule_task', 'member'::text)
	)$SQL$;

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
	)$SQL$;

		RAISE INFO 'MODIFYING RLS policy for pem.jobstep...';
		EXECUTE 'DROP POLICY IF EXISTS pem_jobstep_select ON pem.jobstep';
		EXECUTE 'DROP POLICY IF EXISTS pem_jobstep_update ON pem.jobstep';
		EXECUTE 'DROP POLICY IF EXISTS pem_jobstep_insert ON pem.jobstep';
		EXECUTE 'DROP POLICY IF EXISTS pem_jobstep_delete ON pem.jobstep';

		RAISE INFO 'RLS policy enable on pem.jobstep...';
		EXECUTE 'ALTER TABLE pem.jobstep ENABLE ROW LEVEL SECURITY';

		RAISE INFO 'SELECT RLS policy for pem.jobstep...';
		EXECUTE $SQL$
CREATE POLICY pem_jobstep_select
ON pem.jobstep
FOR SELECT
	USING (
		jstjobid in (SELECT jobid FROM pem.job)
	)$SQL$;


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
	)$SQL$;

		RAISE INFO 'INSERT RLS policy for pem.jobstep...';
		EXECUTE $SQL$
CREATE POLICY pem_jobstep_insert
ON pem.jobstep
FOR INSERT
	WITH CHECK (
		jstjobid in (SELECT jobid FROM pem.job)
	)$SQL$;

		RAISE INFO 'DELETE RLS policy for pem.jobstep...';
		EXECUTE $SQL$
CREATE POLICY pem_jobstep_delete
ON pem.jobstep
FOR DELETE
	USING (
		jstjobid in (SELECT jobid FROM pem.job)
	)$SQL$;

		RAISE INFO 'MODIFYING RLS policy for pem.schedule...';
		EXECUTE 'DROP POLICY IF EXISTS pem_schedule_select ON pem.schedule';
		EXECUTE 'DROP POLICY IF EXISTS pem_schedule_update ON pem.schedule';
		EXECUTE 'DROP POLICY IF EXISTS pem_schedule_insert ON pem.schedule';
		EXECUTE 'DROP POLICY IF EXISTS pem_schedule_delete ON pem.schedule';

		RAISE INFO 'RLS policy enable on pem.job...';
		EXECUTE 'ALTER TABLE pem.schedule ENABLE ROW LEVEL SECURITY';

		RAISE INFO 'SELECT RLS policy for pem.schedule...';
		EXECUTE $SQL$
CREATE POLICY pem_schedule_select
ON pem.schedule
FOR SELECT
	USING (
		jscjobid in (SELECT jobid FROM pem.job)
	)$SQL$;

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
	)$SQL$;

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
	)$SQL$;

		RAISE INFO 'MODIFYING RLS policy for pem.jobsteplog...';
		EXECUTE 'DROP POLICY IF EXISTS pem_jobsteplog_select ON pem.jobsteplog';
		EXECUTE 'DROP POLICY IF EXISTS pem_jobsteplog_update ON pem.jobsteplog';
		EXECUTE 'DROP POLICY IF EXISTS pem_jobsteplog_insert ON pem.jobsteplog';
		EXECUTE 'DROP POLICY IF EXISTS pem_jobsteplog_delete ON pem.jobsteplog';

		RAISE INFO 'RLS policy enable on pem.jobsteplog...';
		EXECUTE 'ALTER TABLE pem.jobsteplog ENABLE ROW LEVEL SECURITY';

		RAISE INFO 'SELECT RLS policy for pem.jobsteplog...';
		EXECUTE $SQL$
CREATE POLICY pem_jobsteplog_select
ON pem.jobsteplog
FOR SELECT
	USING (
		jsljstid IN (SELECT jstid FROM pem.jobstep)
	)$SQL$;

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
	)$SQL$;

		RAISE INFO 'INSERT RLS policy for pem.jobsteplog...';
		EXECUTE $SQL$
CREATE POLICY pem_jobsteplog_insert
ON pem.jobsteplog
FOR INSERT
	WITH CHECK (
		jsljstid IN (SELECT jstid FROM pem.jobstep)
	)$SQL$;

		RAISE INFO 'DELETE RLS policy for pem.jobsteplog...';
		EXECUTE $SQL$
CREATE POLICY pem_jobsteplog_delete
ON pem.jobsteplog
FOR DELETE
	USING (
		jsljstid IN (SELECT jstid FROM pem.jobstep)
	)$SQL$;

		RAISE INFO 'MODIFYING RLS policy for pem.joblog...';
		EXECUTE 'DROP POLICY IF EXISTS pem_joblog_select ON pem.joblog';
		EXECUTE 'DROP POLICY IF EXISTS pem_joblog_update ON pem.joblog';
		EXECUTE 'DROP POLICY IF EXISTS pem_joblog_insert ON pem.joblog';
		EXECUTE 'DROP POLICY IF EXISTS pem_joblog_delete ON pem.joblog';

		RAISE INFO 'RLS policy enable on pem.joblog...';
		EXECUTE 'ALTER TABLE pem.joblog ENABLE ROW LEVEL SECURITY';

		RAISE INFO 'SELECT RLS policy for pem.joblog...';
		EXECUTE $SQL$
CREATE POLICY pem_joblog_select
ON pem.joblog
FOR SELECT
	USING (
		jlgjobid in (SELECT jobid FROM pem.job)
	)$SQL$;

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
	)$SQL$;

		RAISE INFO 'INSERT RLS policy for pem.joblog...';
		EXECUTE $SQL$
CREATE POLICY pem_joblog_insert
ON pem.joblog
FOR INSERT
	WITH CHECK (
		jlgjobid in (SELECT jobid FROM pem.job)
	)$SQL$;

		RAISE INFO 'DELETE RLS policy for pem.joblog...';
		EXECUTE $SQL$
CREATE POLICY pem_joblog_delete
ON pem.joblog
FOR DELETE
	USING (
		jlgjobid in (SELECT jobid FROM pem.job)
	)$SQL$;

    END IF;
END
$$ language 'plpgsql';

COMMIT TRANSACTION;
