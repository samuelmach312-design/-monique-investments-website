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
'SELECT 201407281::integer;'
  LANGUAGE 'sql' IMMUTABLE;

CREATE OR REPLACE FUNCTION pem.server_tuning (tune_server_id int, utilisation pem.tuning_server_util, profile pem.tuning_workload_profile)
RETURNS TABLE (tuned_server_id int, tuned_parameter text, tuned_value text)
AS $$
DECLARE
	bound_agent_id int := 0;
	server_count int := 0;
	total_ram_bytea numeric(1000,0) := 0;
	shared_memory_bytea numeric(1000,0) := 0;
	is_windows boolean := false;
	util_percentage int := 0;
BEGIN
	SELECT agent_id FROM pem.agent_server_binding WHERE server_id = tune_server_id INTO bound_agent_id;
	SELECT count(asb.server_id) AS scount FROM pem.agent_server_binding asb, pem.avail_servers acs WHERE asb.server_id = acs.id AND agent_id = bound_agent_id AND acs.is_remote_monitoring = false INTO server_count;
	SELECT total_ram_memory_mb::numeric(1000,0), sys_shared_memory_mb::numeric(1000,0) FROM pemdata.memory_usage WHERE agent_id = bound_agent_id INTO total_ram_bytea, shared_memory_bytea;
	SELECT 'windows' = ANY(agent_capability_list) INTO is_windows FROM pem.agent WHERE id = bound_agent_id;

	IF utilisation = 'UTILISATION_DEDICATED' THEN
		util_percentage := 100;
	ELSIF utilisation = 'UTILISATION_MIXED' THEN
		util_percentage := 66;
	ELSE
		util_percentage := 33;
	END IF;

	total_ram_bytea := total_ram_bytea * 1024 * 1024;
	shared_memory_bytea := shared_memory_bytea * 1024 * 1024;

	-- divide the total ram and system shared buffer size by the no. of postgres
	-- instances installed on the same machine to avoid over allocation of memory
	-- and resources to the postgres instance being tuned currently
	IF server_count > 0 THEN
		total_ram_bytea := total_ram_bytea / server_count;
		shared_memory_bytea := shared_memory_bytea / server_count;
	END IF;

	-- If SHMMAX > physical memory, we'll use physical memory as the max of SHMMAX.
	-- We don't want to end-up over allocating memory.
	IF total_ram_bytea < shared_memory_bytea THEN
		shared_memory_bytea := total_ram_bytea;
	END IF;

	-- The maximum we'll ever use is 2/3 of system-wide shared memory.
	shared_memory_bytea := round(shared_memory_bytea * (0.66)::decimal);

	-- Calculate the amount of memory we'll use based on the user's defined
	-- percentage for tuning.
	shared_memory_bytea := round(shared_memory_bytea * (util_percentage * 0.01)::decimal);

	IF profile = 'WORKLOAD_OLTP' THEN
		RETURN QUERY EXECUTE 'SELECT $1::int AS tuned_server_id, tuned_parameter, tuned_value FROM ' ||
			'pem.server_tuning_oltp($1::int, $2::pem.tuning_server_util, $3::bigint, $4::bigint, $5::boolean)'
			USING tune_server_id, utilisation, total_ram_bytea, shared_memory_bytea, is_windows;
	ELSIF profile = 'WORKLOAD_MIXED' THEN
		RETURN QUERY EXECUTE 'SELECT $1::int AS tuned_server_id, tuned_parameter, tuned_value FROM ' ||
			'pem.server_tuning_mixed($1::int, $2::pem.tuning_server_util, $3::bigint, $4::bigint, $5::boolean)'
			USING tune_server_id, utilisation, total_ram_bytea, shared_memory_bytea, is_windows;
	ELSE
		RETURN QUERY EXECUTE 'SELECT $1::int AS tuned_server_id, tuned_parameter, tuned_value FROM ' ||
			'pem.server_tuning_dw($1::int, $2::pem.tuning_server_util, $3::bigint, $4::bigint, $5::boolean)'
			USING tune_server_id, utilisation, total_ram_bytea, shared_memory_bytea, is_windows;
	END IF;
END
$$ LANGUAGE plpgsql;

COMMIT TRANSACTION;
