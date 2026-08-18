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
'SELECT 201601075::integer;'
  LANGUAGE 'sql' IMMUTABLE;

UPDATE pem.alert_template SET sql = $sql$SELECT
        ((space_used_mb::float * 100)
        / CASE size_mb WHEN 0 THEN 1 ELSE (size_mb - COALESCE(space_reserved_mb, 0)) END)
        FROM pemdata.disk_space
        WHERE agent_id = ${agent_id}
        AND mount_point = '${param_1}';$sql$
WHERE display_name = 'Disk consumption percentage';

-- Found 'Update the probe-object comination' job not exists on a customer side.
-- Creating the job (if not exists)
DO
$$
DECLARE
	pem_agent  integer;
	pem_server integer;
	job_id     integer;
	jobstep_id integer;
	pem_db     text;
BEGIN
	SELECT j.jobid, jst.server_id, jst.database_name
	INTO pem_agent, pem_server, pem_db
	FROM pem.job j LEFT JOIN pem.jobstep jst ON j.jobid = jst.jstjobid
	WHERE j.issystemjob AND j.jobname = 'Database cleanup'
	ORDER BY 1 LIMIT 1;

	IF (NOT FOUND) THEN
		RETURN;
	END IF;

	-- check if the job already exists.
	SELECT jobid INTO job_id FROM pem.job WHERE jobname = 'Update the probe-objects combination' AND agent_id = pem_agent;

	IF (NOT FOUND) THEN
		RAISE INFO E'Creating the probe-objects combination job!';
		--
		-- Generate the update probe-objects combination job
		-- it will run 10 minutes after installation.
		--
		-- Let agent fetch the information about the server, and host-machine
		-- to  determine the actual probes to run, which generates actual
		-- combination.
		INSERT INTO pem.job(
			jobname, jobdesc, agent_id, issystemjob, jobnextrun
			) VALUES (
			'Update the probe-objects combination',
			'This job updates/inserts the record of the probe, parameter_value_list in the ''pem.probe_objects_combo'' table.',
			pem_agent, true, now() + interval '10 minutes'
		) RETURNING jobid INTO job_id;
	ELSE
	END IF;

	-- Check if the job step already exists.
	SELECT jstid INTO jobstep_id FROM pem.jobstep WHERE jstname = 'Update the probe-objects combination' AND jstjobid = job_id;

	IF (NOT FOUND) THEN
		INSERT INTO pem.jobstep(
			jstjobid, jstname, jstdesc, jstkind, jstcode,
			server_id, database_name
			) VALUES (
			job_id, 'Database cleanup',
			'This job step updates the purge-job tasks on demand.',
			's', 'SELECT pem.create_update_purge_jobs()',
			pem_server, pem_db
		);
	ELSE
		UPDATE pem.jobstep SET jstenabled = TRUE
		WHERE jstid = jobstep_id AND jstjobid = job_id;
	END IF;
END;
$$ LANGUAGE 'plpgsql';

CREATE OR REPLACE VIEW pem.probe_target_without_discard_history AS
SELECT
	p.id AS probe_id, p.internal_name AS probe_internal_name,
	p.target_type_id, ARRAY[a.id::text]::text[] AS parameter_value_list,
	COALESCE(c.lifetime, p.default_lifetime) AS lifetime
FROM
	(
		SELECT * FROM pem.probe
		WHERE  target_type_id = 100 AND NOT deleted AND NOT discard_history
	) AS p
	CROSS JOIN pem.agent a
	LEFT JOIN pem.probe_config_agent c
		ON p.id = c.probe_id AND a.id = c.agent_id
WHERE
	(
		p.agent_capability IS NULL OR
		p.agent_capability = ANY(a.agent_capability_list)
	) AND (
		CASE p.collection_method
		WHEN 'b' THEN a.agent_capability_list @> ARRAY['allow_batch_probes']
		WHEN 'w' THEN strpos(a.platform, 'windows') != 0
		ELSE TRUE
		END
	)
UNION ALL
SELECT
	p.id AS probe_id, p.internal_name AS probe_internal_name,
	p.target_type_id, ARRAY[s.id::text]::text[] AS parameter_value_list,
	COALESCE(c.lifetime, p.default_lifetime) AS lifetime
FROM
	(
		SELECT * FROM pem.probe
		WHERE  target_type_id = 200 AND NOT deleted AND NOT discard_history
	) AS p
	CROSS JOIN pem.server s
	LEFT JOIN pem.agent_server_binding b ON b.server_id = s.id
	LEFT JOIN pem.agent a ON b.agent_id = a.id
	LEFT JOIN pemdata.server_info sd ON s.id = sd.server_id
	LEFT JOIN pem.probe_server_version psv
		ON p.id = psv.probe_id AND sd.server_version_id = psv.server_version_id
	LEFT JOIN pem.probe_config_server c
		ON p.id = c.probe_id AND s.id = c.server_id
WHERE
	(
		p.agent_capability IS NULL OR a.agent_capability_list IS NULL OR
		p.agent_capability = ANY(a.agent_capability_list)
	) AND (
		p.any_server_version OR psv.probe_id IS NOT NULL
	) AND p.internal_name NOT IN(
		SELECT UNNEST(
			CASE
			WHEN s.is_remote_monitoring THEN
				ARRAY['pg_hba_conf', 'data_log_file_analysis', 'wal_archive_status', 'log_configuration', 'efm_cluster_node_status', 'efm_cluster_info']
			ELSE
				ARRAY['']
			END
		)
	) AND p.internal_name NOT IN(
		SELECT UNNEST(
			CASE
			WHEN a.agent_capability_list @> ARRAY['windows']
				THEN ARRAY['efm_cluster_node_status', 'efm_cluster_info']
			ELSE ARRAY[''] END
		)
	) AND (
		CASE p.collection_method
		WHEN 'b' THEN (
			a.agent_capability_list @> ARRAY['allow_batch_probes'] AND (
				strpos(a.platform, p.platform) != 0 OR (
					a.platform !~ 'windows' AND p.platform = 'unix'
				)
			)
		)
		ELSE TRUE
		END
	)
UNION ALL
SELECT
	p.id AS probe_id, p.internal_name AS probe_internal_name,
	p.target_type_id, ARRAY[s.id::text, ocd.database_name]::text[] AS parameter_value_list,
	COALESCE(c.lifetime, p.default_lifetime) AS lifetime
FROM
	(
		SELECT * FROM pem.probe
		WHERE  target_type_id = 300 AND NOT deleted AND NOT discard_history
	) AS p
	CROSS JOIN pem.server s
	LEFT JOIN pem.agent_server_binding b ON b.server_id = s.id
	LEFT JOIN pem.agent a ON b.agent_id = a.id
	LEFT JOIN pemdata.server_info sd ON s.id = sd.server_id
	LEFT JOIN pem.probe_server_version psv
		ON p.id = psv.probe_id AND sd.server_version_id = psv.server_version_id
	INNER JOIN (SELECT * FROM pemdata.oc_database WHERE connections_allowed) ocd
		ON s.id = ocd.server_id
	LEFT JOIN pem.probe_config_database c
		ON p.id = c.probe_id AND s.id = c.server_id AND
		ocd.database_name = c.database_name
WHERE
	(
		p.agent_capability IS NULL OR a.agent_capability_list IS NULL OR
		p.agent_capability = ANY(a.agent_capability_list)
	) AND (p.any_server_version OR psv.probe_id IS NOT NULL) AND (
		CASE p.collection_method
		WHEN 'b' THEN (
			a.agent_capability_list @> ARRAY['allow_batch_probes'] AND (
				strpos(a.platform, p.platform) != 0 OR (
					a.platform !~ 'windows' AND p.platform = 'unix'
				)
			)
		)
		ELSE TRUE
		END
	)
UNION ALL
SELECT
	p.id AS probe_id, p.internal_name AS probe_internal_name,
	p.target_type_id, ARRAY[
		s.id::text, oc.database_name, oc.schema_name
	]::text[] AS parameter_value_list,
	COALESCE(c.lifetime, p.default_lifetime) AS lifetime
FROM
	(
		SELECT * FROM pem.probe
		WHERE  target_type_id = 400 AND NOT deleted AND NOT discard_history
	) AS p
	CROSS JOIN pem.server s
	LEFT JOIN pem.agent_server_binding b ON b.server_id = s.id
	LEFT JOIN pem.agent a ON b.agent_id = a.id
	LEFT JOIN pemdata.server_info sd ON s.id = sd.server_id
	LEFT JOIN pem.probe_server_version psv
		ON p.id = psv.probe_id AND sd.server_version_id = psv.server_version_id
	INNER JOIN (SELECT * FROM pemdata.oc_database WHERE connections_allowed) ocd
		ON s.id = ocd.server_id
	INNER JOIN pemdata.oc_schema oc ON ocd.server_id = oc.server_id AND
		ocd.database_name = oc.database_name
	LEFT JOIN pem.probe_config_schema c ON p.id = c.probe_id AND
		s.id = c.server_id AND oc.database_name = c.database_name AND
		oc.schema_name = c.schema_name
WHERE
	(
		p.agent_capability IS NULL OR a.agent_capability_list IS NULL OR
		p.agent_capability = ANY(a.agent_capability_list)
	) AND (p.any_server_version OR psv.probe_id IS NOT NULL) AND (
		CASE p.collection_method
		WHEN 'b' THEN (
			a.agent_capability_list @> ARRAY['allow_batch_probes'] AND (
				strpos(a.platform, p.platform) != 0 OR (
					a.platform !~ 'windows' AND p.platform = 'unix'
				)
			)
		)
		ELSE TRUE
		END
	)
UNION ALL
SELECT
	p.id AS probe_id, p.internal_name AS probe_internal_name,
	p.target_type_id, ARRAY[
		s.id::text, oc.database_name, oc.schema_name, oc.table_name
	]::text[] AS parameter_value_list,
	COALESCE(c.lifetime, p.default_lifetime) AS lifetime
FROM
	(
		SELECT * FROM pem.probe
		WHERE  target_type_id = 500 AND NOT deleted AND NOT discard_history
	) AS p
	CROSS JOIN pem.server s
	LEFT JOIN pem.agent_server_binding b ON b.server_id = s.id
	LEFT JOIN pem.agent a ON b.agent_id = a.id
	LEFT JOIN pemdata.server_info sd ON s.id = sd.server_id
	LEFT JOIN pem.probe_server_version psv
		ON p.id = psv.probe_id AND sd.server_version_id = psv.server_version_id
	INNER JOIN (SELECT * FROM pemdata.oc_database WHERE connections_allowed) ocd
		ON s.id = ocd.server_id
	INNER JOIN pemdata.oc_table oc ON ocd.server_id = oc.server_id AND
		ocd.database_name = oc.database_name
	LEFT JOIN pem.probe_config_table c ON p.id = c.probe_id AND
		s.id = c.server_id AND oc.database_name = c.database_name AND
		oc.schema_name = c.schema_name AND oc.table_name = c.table_name
WHERE
	(
		p.agent_capability IS NULL OR a.agent_capability_list IS NULL OR
		p.agent_capability = ANY(a.agent_capability_list)
	) AND (p.any_server_version OR psv.probe_id IS NOT NULL) AND (
		CASE p.collection_method
		WHEN 'b' THEN (
			a.agent_capability_list @> ARRAY['allow_batch_probes'] AND (
				strpos(a.platform, p.platform) != 0 OR (
					a.platform !~ 'windows' AND p.platform = 'unix'
				)
			)
		)
		ELSE TRUE
		END
	)
UNION ALL
SELECT
	p.id AS probe_id, p.internal_name AS probe_internal_name,
	p.target_type_id, ARRAY[
		s.id::text, oc.database_name, oc.schema_name, oc.index_name
	]::text[] AS parameter_value_list,
	COALESCE(c.lifetime, p.default_lifetime) AS lifetime
FROM
	(
		SELECT * FROM pem.probe
		WHERE  target_type_id = 600 AND NOT deleted AND NOT discard_history
	) AS p
	CROSS JOIN pem.server s
	LEFT JOIN pem.agent_server_binding b ON b.server_id = s.id
	LEFT JOIN pem.agent a ON b.agent_id = a.id
	LEFT JOIN pemdata.server_info sd ON s.id = sd.server_id
	LEFT JOIN pem.probe_server_version psv
		ON p.id = psv.probe_id AND sd.server_version_id = psv.server_version_id
	INNER JOIN (SELECT * FROM pemdata.oc_database WHERE connections_allowed) ocd
		ON s.id = ocd.server_id
	INNER JOIN pemdata.oc_index oc ON ocd.server_id = oc.server_id AND
		ocd.database_name = oc.database_name
	LEFT JOIN pem.probe_config_index c ON p.id = c.probe_id AND
		s.id = c.server_id AND oc.database_name = c.database_name AND
		oc.schema_name = c.schema_name AND oc.index_name = c.index_name
WHERE
	(
		p.agent_capability IS NULL OR a.agent_capability_list IS NULL OR
		p.agent_capability = ANY(a.agent_capability_list)
	) AND (p.any_server_version OR psv.probe_id IS NOT NULL) AND (
		CASE p.collection_method
		WHEN 'b' THEN (
			a.agent_capability_list @> ARRAY['allow_batch_probes'] AND (
				strpos(a.platform, p.platform) != 0 OR (
					a.platform !~ 'windows' AND p.platform = 'unix'
				)
			)
		)
		ELSE TRUE
		END
	)
UNION ALL
SELECT
	p.id AS probe_id, p.internal_name AS probe_internal_name,
	p.target_type_id, ARRAY[
		s.id::text, oc.database_name, oc.schema_name, oc.sequence_name
	]::text[] AS parameter_value_list,
	COALESCE(c.lifetime, p.default_lifetime) AS lifetime
FROM
	(
		SELECT * FROM pem.probe
		WHERE  target_type_id = 700 AND NOT deleted AND NOT discard_history
	) AS p
	CROSS JOIN pem.server s
	LEFT JOIN pem.agent_server_binding b ON b.server_id = s.id
	LEFT JOIN pem.agent a ON b.agent_id = a.id
	LEFT JOIN pemdata.server_info sd ON s.id = sd.server_id
	LEFT JOIN pem.probe_server_version psv
		ON p.id = psv.probe_id AND sd.server_version_id = psv.server_version_id
	INNER JOIN (SELECT * FROM pemdata.oc_database WHERE connections_allowed) ocd
		ON s.id = ocd.server_id
	INNER JOIN pemdata.oc_sequence oc ON ocd.server_id = oc.server_id AND
		ocd.database_name = oc.database_name
	LEFT JOIN pem.probe_config_sequence c ON p.id = c.probe_id AND
		s.id = c.server_id AND oc.database_name = c.database_name AND
		oc.schema_name = c.schema_name AND
		oc.sequence_name = c.sequence_name
WHERE
	(
		p.agent_capability IS NULL OR a.agent_capability_list IS NULL OR
		p.agent_capability = ANY(a.agent_capability_list)
	) AND (p.any_server_version OR psv.probe_id IS NOT NULL) AND (
		CASE p.collection_method
		WHEN 'b' THEN (
			a.agent_capability_list @> ARRAY['allow_batch_probes'] AND (
				strpos(a.platform, p.platform) != 0 OR (
					a.platform !~ 'windows' AND p.platform = 'unix'
				)
			)
		)
		ELSE TRUE
		END
	)
UNION ALL
SELECT
	p.id AS probe_id, p.internal_name AS probe_internal_name,
	p.target_type_id, ARRAY[
		s.id::text, oc.database_name, oc.schema_name, oc.function_name
	]::text[] AS parameter_value_list,
	COALESCE(c.lifetime, p.default_lifetime) AS lifetime
FROM
	(
		SELECT * FROM pem.probe
		WHERE  target_type_id = 800 AND NOT deleted AND NOT discard_history
	) AS p
	CROSS JOIN pem.server s
	LEFT JOIN pem.agent_server_binding b ON b.server_id = s.id
	LEFT JOIN pem.agent a ON b.agent_id = a.id
	LEFT JOIN pemdata.server_info sd ON s.id = sd.server_id
	LEFT JOIN pem.probe_server_version psv
		ON p.id = psv.probe_id AND sd.server_version_id = psv.server_version_id
	INNER JOIN (SELECT * FROM pemdata.oc_database WHERE connections_allowed) ocd
		ON s.id = ocd.server_id
	INNER JOIN pemdata.oc_function oc ON ocd.server_id = oc.server_id AND
		ocd.database_name = oc.database_name
	LEFT JOIN pem.probe_config_function c ON p.id = c.probe_id AND
		oc.server_id = c.server_id AND oc.database_name = c.database_name AND
		oc.schema_name = c.schema_name AND oc.function_name = c.function_name
WHERE
	(
		p.agent_capability IS NULL OR a.agent_capability_list IS NULL OR
		p.agent_capability = ANY(a.agent_capability_list)
	) AND (p.any_server_version OR psv.probe_id IS NOT NULL) AND (
		CASE p.collection_method
		WHEN 'b' THEN (
			a.agent_capability_list @> ARRAY['allow_batch_probes'] AND (
				strpos(a.platform, p.platform) != 0 OR (
					a.platform !~ 'windows' AND p.platform = 'unix'
				)
			)
		)
		ELSE TRUE
		END
	)
UNION ALL
SELECT
	p.id AS probe_id, p.internal_name AS probe_internal_name,
	p.target_type_id, ARRAY[
		s.id::text, oc.database_name, oc.schema_name, oc.view_name
	]::text[] AS parameter_value_list,
	COALESCE(c.lifetime, p.default_lifetime) AS lifetime
FROM
	(
		SELECT * FROM pem.probe
		WHERE  target_type_id = 900 AND NOT deleted AND NOT discard_history
	) AS p
	CROSS JOIN pem.server s
	LEFT JOIN pem.agent_server_binding b ON b.server_id = s.id
	LEFT JOIN pem.agent a ON b.agent_id = a.id
	LEFT JOIN pemdata.server_info sd ON s.id = sd.server_id
	LEFT JOIN pem.probe_server_version psv
		ON p.id = psv.probe_id AND sd.server_version_id = psv.server_version_id
	INNER JOIN (SELECT * FROM pemdata.oc_database WHERE connections_allowed) ocd
		ON s.id = ocd.server_id
	INNER JOIN pemdata.oc_views oc ON ocd.server_id = oc.server_id AND
		ocd.database_name = oc.database_name
	LEFT JOIN pem.probe_config_view c ON p.id = c.probe_id AND
		oc.server_id = c.server_id AND oc.database_name = c.database_name AND
		oc.schema_name = c.schema_name AND oc.view_name = c.view_name
WHERE
	(
		p.agent_capability IS NULL OR a.agent_capability_list IS NULL OR
		p.agent_capability = ANY(a.agent_capability_list)
	) AND (p.any_server_version OR psv.probe_id IS NOT NULL) AND (
		CASE p.collection_method
		WHEN 'b' THEN (
			a.agent_capability_list @> ARRAY['allow_batch_probes'] AND (
				strpos(a.platform, p.platform) != 0 OR (
					a.platform !~ 'windows' AND p.platform = 'unix'
				)
			)
		)
		ELSE TRUE
		END
	);

--
-- FUNCTION: pem.create_update_probe_objects_combo()
--
-- This function will helps us to maintain the purging job steps for each individual probe,
-- and parameters combination. It will update only the job steps, whose
-- lifetime has been modified. Also, creates new job steps for the object-probe
-- combination.
CREATE OR REPLACE FUNCTION pem.create_update_probe_objects_combo()
	RETURNS void AS
$function$
DECLARE
	info_curs    REFCURSOR;
	info         RECORD;
BEGIN
	-- Fetch the new/updated probe-object parameters combination.
	OPEN info_curs FOR EXECUTE $SQL$
SELECT
	p.probe_id AS probe_id, c.pid AS pid, c.delete_on,
	COALESCE(p.parameter_value_list, c.objects) AS objects,
	COALESCE(p.lifetime, c.lifetime) AS lifetime
FROM
	pem.probe_target_without_discard_history p
	FULL OUTER JOIN pem.probe_objects_combo c ON (
		p.probe_id = c.pid AND p.parameter_value_list = c.objects
	)
WHERE
	c.pid IS NULL OR p.lifetime != c.lifetime OR c.delete_on IS NOT NULL OR (
		p.probe_id IS NULL AND (
			c.delete_on IS NULL OR c.delete_on > now()::date
		)
	)
$SQL$;

	LOOP
		FETCH info_curs INTO info;
		EXIT WHEN NOT FOUND;

		IF info.probe_id IS NULL THEN
			-- The probe-object is not available
			IF info.delete_on IS NULL THEN
				-- We have noticed it for the first time.
				-- Set the date on which it should be removed from the
				-- 'pem.probe_objects_combo' table.
				EXECUTE 'UPDATE pem.probe_objects_combo SET delete_on = $3::date WHERE pid = $1::integer AND objects = $2::text[]'
				USING info.pid, info.objects, (now() + ((info.lifetime + 5) * INTERVAL '1 days'))::date;
			ELSE
				-- Remove the combination from the 'pem.probe_objects_combo'
				-- table.
				DELETE FROM pem.probe_objects_combo
				WHERE pid = info.pid AND objects = info.objects;
			END IF;
		ELSE
			IF info.pid IS NULL THEN
				-- Insert the combination from the 'pem.probe_objects_combo'
				-- table.
				INSERT INTO pem.probe_objects_combo (pid, objects, lifetime)
				VALUES (info.probe_id, info.objects, info.lifetime);
			ELSE
				-- Update the lifetime, delete_on in the
				-- 'pem.probe_objects_combo' table.
				UPDATE pem.probe_objects_combo
				SET lifetime = info.lifetime, delete_on = NULL
				WHERE pid = info.probe_id AND objects = info.objects;
			END IF;
		END IF;
	END LOOP;
	CLOSE info_curs;
END;
$function$ LANGUAGE plpgsql;

-- Update the probe-objects combination table
SELECT pem.create_update_probe_objects_combo();

-- Let's run the update probe-objects combination job immediately.
UPDATE pem.job SET jobnextrun=now() WHERE issystemjob AND jobname = 'Update the probe-objects combination';

-- Delete existing constraint of jobstep on probe table.
ALTER TABLE pem.probe DROP CONSTRAINT probe_purge_jobstep_id_fkey;

-- Add jobstep constraint on probe table.
ALTER TABLE pem.probe ADD CONSTRAINT
        probe_purge_jobstep_id_fkey FOREIGN KEY (jstid)
        REFERENCES pem.jobstep(jstid) ON UPDATE NO ACTION;

COMMIT TRANSACTION;
