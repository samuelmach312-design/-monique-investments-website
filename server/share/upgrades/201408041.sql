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
'SELECT 201408041::integer;'
  LANGUAGE 'sql' IMMUTABLE;

DROP FUNCTION pem.server_tuning_oltp(integer,pem.tuning_server_util,numeric,numeric,boolean);
DROP FUNCTION pem.server_tuning_mixed(integer,pem.tuning_server_util,numeric,numeric,boolean);
DROP FUNCTION pem.server_tuning_dw(integer,pem.tuning_server_util,numeric,numeric,boolean);
DROP FUNCTION pem.server_tuning(integer, pem.tuning_server_util, pem.tuning_workload_profile);


UPDATE pem.chart_func SET func = E'SELECT o_idx, o_label, ''Date('' || (EXTRACT(EPOCH FROM o_aggtime) * 1000)::numeric(40, 0)::text || '')'', o_aggval FROM pem.generate_conn_overview_chart_data(55, $1::int4, NULL::text, $2::timestamptz, $3::timestamptz) ORDER BY o_idx, o_aggtime' WHERE id = 55;

CREATE OR REPLACE FUNCTION pem.server_tuning_original_value(tuned_server_id int, param_name text)
RETURNS TEXT
AS $$
DECLARE
	param_value text := '';
	orig_val int := 0;
	param_unit int := 1;
	unit_val text := '';
BEGIN
	SELECT setting::int, unit, COALESCE(SUBSTRING(unit from '[0-9]+'), '1')::int FROM pemdata.settings WHERE server_id = tuned_server_id AND name = param_name INTO orig_val, unit_val, param_unit;

	IF (unit_val IS NOT NULL) AND (unit_val != '') THEN
		orig_val = orig_val * param_unit;
		IF orig_val < 1024 THEN
			param_value = orig_val::text || 'kB';
		ELSE
			param_value = round(orig_val/1024)::text || 'MB';
		END IF;
	ELSE
		param_value = orig_val::text;
	END IF;

	RETURN param_value;
END
$$ LANGUAGE plpgsql;

-- This function executes the calculates the appropriate value for the parameters to
-- be tuned for servers with workload profile of type OLTP
-- Parameters:
--    tune_server_id - server id of the server to tune
--    utilisation - utilisation enum to specify of server
--    total_ram - total ram on the machine
--    shared_memory - shared memory on the machine
--    is_windows - if machine is windows or not
CREATE OR REPLACE FUNCTION pem.server_tuning_oltp (tune_server_id int, utilisation pem.tuning_server_util, total_ram numeric, shared_memory numeric, is_windows boolean)
RETURNS TABLE (tuned_parameter text, tuned_value text, orig_value text)
AS $$
DECLARE
	server_max_conn int := 0;
	server_max_locks_per_xact int := 0;
	server_max_prepared_xacts int := 0;
	shared_mem numeric(1000,0) := shared_memory;
	work_mem_factor decimal := 0.008;
	maint_work_mem_factor decimal := 0.08;
	work_mem bigint := 0;
	maint_work_mem bigint := 0;
	shared_buffers bigint := 0;
	wal_buffers bigint := 0;
	eff_cache_size bigint := 0;
BEGIN
	SELECT setting FROM pemdata.settings WHERE server_id = tune_server_id AND name='max_connections' INTO server_max_conn;
	SELECT setting FROM pemdata.settings WHERE server_id = tune_server_id AND name='max_locks_per_transaction' INTO server_max_locks_per_xact;
	SELECT setting FROM pemdata.settings WHERE server_id = tune_server_id AND name='max_prepared_transactions' INTO server_max_prepared_xacts;

	-- calculate amount of memory utilized for max_connections and subtract it from shared memory
	-- to calculate work_mem and maintainance_work_mem
	shared_mem := shared_mem - (server_max_conn * 620 * server_max_locks_per_xact);
	shared_mem := shared_mem - (server_max_prepared_xacts * 820 * server_max_locks_per_xact);

	-- calculate work_mem
	work_mem := round(shared_mem * work_mem_factor);
	work_mem := round(work_mem / (1024)::decimal);

	-- work_mem needs to be at least 1MB
	IF work_mem < 1024 THEN
		work_mem := 1024;
	END IF;

	work_mem := round(work_mem / (1024)::decimal);

	tuned_parameter := 'work_mem';
	tuned_value := work_mem || 'MB';
	orig_value := pem.server_tuning_original_value(tune_server_id, 'work_mem');
	RETURN NEXT;

	shared_mem := shared_mem - (work_mem * 1024 *1024);

	-- calculate maintainence_work_mem
	maint_work_mem := round(shared_mem * maint_work_mem_factor);
	maint_work_mem := round(maint_work_mem / (1024 * 1024)::decimal);

	-- maintainence_work_mem needs to be at max 256MB
	IF maint_work_mem > 256 THEN
		maint_work_mem := 256;
	END IF;

	-- maintainence_work_mem needs to be at least 16MB
	IF maint_work_mem < 16 THEN
		maint_work_mem := 16;
	END IF;

	tuned_parameter := 'maintenance_work_mem';
	tuned_value := maint_work_mem || 'MB';
	orig_value := pem.server_tuning_original_value(tune_server_id, 'maintenance_work_mem');
	RETURN NEXT;

	-- calculate shared_buffers
	IF utilisation = 'UTILISATION_DEVELOPER' THEN
		-- set it default to 32MB
		shared_buffers := 32 * 1024 * 1024;
	ELSIF utilisation = 'UTILISATION_MIXED' THEN
		IF is_windows THEN
			-- set it default to 128MB
			shared_buffers := 128 * 1024 * 1024;
		ELSE
			-- set 25% of total RAM
			shared_buffers := round(total_ram * (0.25)::decimal);
		END IF;
	ELSE
		IF is_windows THEN
			-- set it default to 256MB
			shared_buffers := 256 * 1024 * 1024;
		ELSE
			-- set 40% of total RAM
			shared_buffers := round(total_ram * (0.40)::decimal);
		END IF;
	END IF;

	shared_buffers := round(shared_buffers / (1024*1024)::decimal);

	-- shared_buffers needs to be at max 8GB
	IF shared_buffers > 8192 THEN
		shared_buffers := 8192;
	END IF;

	-- shared_buffers needs to be at least 2MB
	IF shared_buffers < 2 THEN
		shared_buffers := 2;
	END IF;

	tuned_parameter := 'shared_buffers';
	tuned_value := shared_buffers || 'MB';
	orig_value := pem.server_tuning_original_value(tune_server_id, 'shared_buffers');
	RETURN NEXT;

	-- calculate wal_buffers
	shared_buffers := shared_buffers * 1024 * 1024;
	wal_buffers := round(shared_buffers / (8)::decimal);

	-- wal_buffers needs to be at max 16MB
	IF wal_buffers > 16777216 THEN
		wal_buffers := 16777216;
	END IF;

	-- wal_buffers needs to be at least 64KB
	IF wal_buffers < 65536 THEN
		wal_buffers := 65536;
	END IF;

	tuned_parameter := 'wal_buffers';
	IF (wal_buffers / (1048576)::decimal) > 1.00 THEN
		wal_buffers := round(wal_buffers / (1048576)::decimal);
		tuned_value := wal_buffers || 'MB';
	ELSE
		wal_buffers := round(wal_buffers / (1024)::decimal);
		tuned_value := wal_buffers || 'kB';
	END IF;
	orig_value := pem.server_tuning_original_value(tune_server_id, 'wal_buffers');
	RETURN NEXT;

	-- calculate effective_cache_size
	IF utilisation = 'UTILISATION_DEDICATED' THEN
		eff_cache_size := round(total_ram * (0.75)::decimal);
	ELSIF utilisation = 'UTILISATION_MIXED' THEN
		eff_cache_size := round(total_ram * (0.5)::decimal);
	ELSE
		eff_cache_size := round(total_ram * (0.25)::decimal);
	END IF;

	eff_cache_size := round(eff_cache_size / (1048576)::decimal);

	tuned_parameter := 'effective_cache_size';
	tuned_value := eff_cache_size || 'MB';
	orig_value := pem.server_tuning_original_value(tune_server_id, 'effective_cache_size');
	RETURN NEXT;

	-- calculate random_page_cost
	tuned_parameter := 'random_page_cost';
	IF utilisation = 'UTILISATION_DEDICATED' THEN
		tuned_value := '2.0';
	ELSIF utilisation = 'UTILISATION_MIXED' THEN
		tuned_value := '2.5';
	ELSE
		tuned_value := '3.0';
	END IF;
	orig_value := pem.server_tuning_original_value(tune_server_id, 'random_page_cost');
	RETURN NEXT;

	-- calculate checkpoint_segments
	tuned_parameter := 'checkpoint_segments';
	IF utilisation = 'UTILISATION_DEDICATED' THEN
		tuned_value := '32';
	ELSIF utilisation = 'UTILISATION_MIXED' THEN
		tuned_value := '16';
	ELSE
		tuned_value := '6';
	END IF;
	orig_value := pem.server_tuning_original_value(tune_server_id, 'checkpoint_segments');
	RETURN NEXT;

	RETURN;
END
$$ LANGUAGE plpgsql;

-- This function executes the calculates the appropriate value for the parameters to
-- be tuned for servers with workload profile of type Mixed
-- Parameters:
--    tune_server_id - server id of the server to tune
--    utilisation - utilisation enum to specify of server
--    total_ram - total ram on the machine
--    shared_memory - shared memory on the machine
--    is_windows - if machine is windows or not
CREATE OR REPLACE FUNCTION pem.server_tuning_mixed (tune_server_id int, utilisation pem.tuning_server_util, total_ram numeric, shared_memory numeric, is_windows boolean)
RETURNS TABLE (tuned_parameter text, tuned_value text, orig_value text)
AS $$
DECLARE
	server_max_conn int := 0;
	server_max_locks_per_xact int := 0;
	server_max_prepared_xacts int := 0;
	shared_mem numeric(1000,0) := shared_memory;
	work_mem_factor decimal := 0.012;
	maint_work_mem_factor decimal := 0.1;
	work_mem bigint := 0;
	maint_work_mem bigint := 0;
	shared_buffers bigint := 0;
	wal_buffers bigint := 0;
	eff_cache_size bigint := 0;
BEGIN
	SELECT setting FROM pemdata.settings WHERE server_id = tune_server_id AND name='max_connections' INTO server_max_conn;
	SELECT setting FROM pemdata.settings WHERE server_id = tune_server_id AND name='max_locks_per_transaction' INTO server_max_locks_per_xact;
	SELECT setting FROM pemdata.settings WHERE server_id = tune_server_id AND name='max_prepared_transactions' INTO server_max_prepared_xacts;

	-- calculate amount of memory utilized for max_connections and subtract it from shared memory
	-- to calculate work_mem and maintainance_work_mem
	shared_mem := shared_mem - (server_max_conn * 620 * server_max_locks_per_xact);
	shared_mem := shared_mem - (server_max_prepared_xacts * 820 * server_max_locks_per_xact);

	-- calculate work_mem
	work_mem := round(shared_mem * work_mem_factor);
	work_mem := round(work_mem / (1024)::decimal);

	-- work_mem needs to be at least 1MB
	IF work_mem < 1024 THEN
		work_mem := 1024;
	END IF;

	work_mem := round(work_mem / (1024)::decimal);

	tuned_parameter := 'work_mem';
	tuned_value := work_mem || 'MB';
	orig_value := pem.server_tuning_original_value(tune_server_id, 'work_mem');
	RETURN NEXT;

	shared_mem := shared_mem - (work_mem * 1024 *1024);

	-- calculate maintainence_work_mem
	maint_work_mem := round(shared_mem * maint_work_mem_factor);
	maint_work_mem := round(maint_work_mem / (1024 * 1024)::decimal);

	-- maintainence_work_mem needs to be at max 256MB
	IF maint_work_mem > 256 THEN
		maint_work_mem := 256;
	END IF;

	-- maintainence_work_mem needs to be at least 16MB
	IF maint_work_mem < 16 THEN
		maint_work_mem := 16;
	END IF;

	tuned_parameter := 'maintenance_work_mem';
	tuned_value := maint_work_mem || 'MB';
	orig_value := pem.server_tuning_original_value(tune_server_id, 'maintenance_work_mem');
	RETURN NEXT;

	-- calculate shared_buffers
	IF utilisation = 'UTILISATION_DEVELOPER' THEN
		-- set it default to 32MB
		shared_buffers := 32 * 1024 * 1024;
	ELSIF utilisation = 'UTILISATION_MIXED' THEN
		IF is_windows THEN
			-- set it default to 128MB
			shared_buffers := 128 * 1024 * 1024;
		ELSE
			-- set 25% of total RAM
			shared_buffers := round(total_ram * (0.25)::decimal);
		END IF;
	ELSE
		IF is_windows THEN
			-- set it default to 256MB
			shared_buffers := 256 * 1024 * 1024;
		ELSE
			-- set 40% of total RAM
			shared_buffers := round(total_ram * (0.40)::decimal);
		END IF;
	END IF;

	shared_buffers := round(shared_buffers / (1024*1024)::decimal);

	-- shared_buffers needs to be at max 8GB
	IF shared_buffers > 8192 THEN
		shared_buffers := 8192;
	END IF;

	-- shared_buffers needs to be at least 2MB
	IF shared_buffers < 2 THEN
		shared_buffers := 2;
	END IF;

	tuned_parameter := 'shared_buffers';
	tuned_value := shared_buffers || 'MB';
	orig_value := pem.server_tuning_original_value(tune_server_id, 'shared_buffers');
	RETURN NEXT;

	-- calculate wal_buffers
	shared_buffers := shared_buffers * 1024 * 1024;
	wal_buffers := round(shared_buffers / (16)::decimal);

	-- wal_buffers needs to be at max 16MB
	IF wal_buffers > 16777216 THEN
		wal_buffers := 16777216;
	END IF;

	-- wal_buffers needs to be at least 64KB
	IF wal_buffers < 65536 THEN
		wal_buffers := 65536;
	END IF;

	tuned_parameter := 'wal_buffers';
	IF (wal_buffers / (1048576)::decimal) > 1.00 THEN
		wal_buffers := round(wal_buffers / (1048576)::decimal);
		tuned_value := wal_buffers || 'MB';
	ELSE
		wal_buffers := round(wal_buffers / (1024)::decimal);
		tuned_value := wal_buffers || 'kB';
	END IF;
	orig_value := pem.server_tuning_original_value(tune_server_id, 'wal_buffers');
	RETURN NEXT;

	-- calculate effective_cache_size
	IF utilisation = 'UTILISATION_DEDICATED' THEN
		eff_cache_size := round(total_ram * (0.75)::decimal);
	ELSIF utilisation = 'UTILISATION_MIXED' THEN
		eff_cache_size := round(total_ram * (0.5)::decimal);
	ELSE
		eff_cache_size := round(total_ram * (0.25)::decimal);
	END IF;

	eff_cache_size := round(eff_cache_size / (1048576)::decimal);

	tuned_parameter := 'effective_cache_size';
	tuned_value := eff_cache_size || 'MB';
	orig_value := pem.server_tuning_original_value(tune_server_id, 'effective_cache_size');
	RETURN NEXT;

	-- calculate random_page_cost
	tuned_parameter := 'random_page_cost';
	IF utilisation = 'UTILISATION_DEDICATED' THEN
		tuned_value := '2.0';
	ELSIF utilisation = 'UTILISATION_MIXED' THEN
		tuned_value := '2.5';
	ELSE
		tuned_value := '3.0';
	END IF;
	orig_value := pem.server_tuning_original_value(tune_server_id, 'random_page_cost');
	RETURN NEXT;

	-- calculate checkpoint_segments
	tuned_parameter := 'checkpoint_segments';
	IF utilisation = 'UTILISATION_DEDICATED' THEN
		tuned_value := '48';
	ELSIF utilisation = 'UTILISATION_MIXED' THEN
		tuned_value := '24';
	ELSE
		tuned_value := '6';
	END IF;
	orig_value := pem.server_tuning_original_value(tune_server_id, 'checkpoint_segments');
	RETURN NEXT;

	RETURN;
END
$$ LANGUAGE plpgsql;

-- This function executes the calculates the appropriate value for the parameters to
-- be tuned for servers with workload profile of type Datawarehouse
-- Parameters:
--    tune_server_id - server id of the server to tune
--    utilisation - utilisation enum to specify of server
--    total_ram - total ram on the machine
--    shared_memory - shared memory on the machine
--    is_windows - if machine is windows or not
CREATE OR REPLACE FUNCTION pem.server_tuning_dw (tune_server_id int, utilisation pem.tuning_server_util, total_ram numeric, shared_memory numeric, is_windows boolean)
RETURNS TABLE (tuned_parameter text, tuned_value text, orig_value text)
AS $$
DECLARE
	server_max_conn int := 0;
	server_max_locks_per_xact int := 0;
	server_max_prepared_xacts int := 0;
	shared_mem numeric(1000,0) := shared_memory;
	work_mem_factor decimal := 0.020;
	maint_work_mem_factor decimal := 0.2;
	work_mem bigint := 0;
	maint_work_mem bigint := 0;
	shared_buffers bigint := 0;
	wal_buffers bigint := 0;
	eff_cache_size bigint := 0;
BEGIN
	SELECT setting FROM pemdata.settings WHERE server_id = tune_server_id AND name='max_connections' INTO server_max_conn;
	SELECT setting FROM pemdata.settings WHERE server_id = tune_server_id AND name='max_locks_per_transaction' INTO server_max_locks_per_xact;
	SELECT setting FROM pemdata.settings WHERE server_id = tune_server_id AND name='max_prepared_transactions' INTO server_max_prepared_xacts;

	-- calculate amount of memory utilized for max_connections and subtract it from shared memory
	-- to calculate work_mem and maintainance_work_mem
	shared_mem := shared_mem - (server_max_conn * 620 * server_max_locks_per_xact);
	shared_mem := shared_mem - (server_max_prepared_xacts * 820 * server_max_locks_per_xact);

	-- calculate work_mem
	work_mem := round(shared_mem * work_mem_factor);
	work_mem := round(work_mem / (1024)::decimal);

	-- work_mem needs to be at least 1MB
	IF work_mem < 1024 THEN
		work_mem := 1024;
	END IF;

	work_mem := round(work_mem / (1024)::decimal);

	tuned_parameter := 'work_mem';
	tuned_value := work_mem || 'MB';
	orig_value := pem.server_tuning_original_value(tune_server_id, 'work_mem');
	RETURN NEXT;

	shared_mem := shared_mem - (work_mem * 1024 *1024);

	-- calculate maintainence_work_mem
	maint_work_mem := round(shared_mem * maint_work_mem_factor);
	maint_work_mem := round(maint_work_mem / (1024 * 1024)::decimal);

	-- maintainence_work_mem needs to be at max 256MB
	IF maint_work_mem > 256 THEN
		maint_work_mem := 256;
	END IF;

	-- maintainence_work_mem needs to be at least 16MB
	IF maint_work_mem < 16 THEN
		maint_work_mem := 16;
	END IF;

	tuned_parameter := 'maintenance_work_mem';
	tuned_value := maint_work_mem || 'MB';
	orig_value := pem.server_tuning_original_value(tune_server_id, 'maintenance_work_mem');
	RETURN NEXT;

	-- calculate shared_buffers
	IF utilisation = 'UTILISATION_DEVELOPER' THEN
		-- set it default to 32MB
		shared_buffers := 32 * 1024 * 1024;
	ELSIF utilisation = 'UTILISATION_MIXED' THEN
		IF is_windows THEN
			-- set it default to 128MB
			shared_buffers := 128 * 1024 * 1024;
		ELSE
			-- set 25% of total RAM
			shared_buffers := round(total_ram * (0.25)::decimal);
		END IF;
	ELSE
		IF is_windows THEN
			-- set it default to 256MB
			shared_buffers := 256 * 1024 * 1024;
		ELSE
			-- set 40% of total RAM
			shared_buffers := round(total_ram * (0.40)::decimal);
		END IF;
	END IF;

	shared_buffers := round(shared_buffers / (1024*1024)::decimal);

	-- shared_buffers needs to be at max 8GB
	IF shared_buffers > 8192 THEN
		shared_buffers := 8192;
	END IF;

	-- shared_buffers needs to be at least 2MB
	IF shared_buffers < 2 THEN
		shared_buffers := 2;
	END IF;

	tuned_parameter := 'shared_buffers';
	tuned_value := shared_buffers || 'MB';
	orig_value := pem.server_tuning_original_value(tune_server_id, 'shared_buffers');
	RETURN NEXT;

	-- calculate wal_buffers
	shared_buffers := shared_buffers * 1024 * 1024;
	wal_buffers := round(shared_buffers / (32)::decimal);

	-- wal_buffers needs to be at max 16MB
	IF wal_buffers > 16777216 THEN
		wal_buffers := 16777216;
	END IF;

	-- wal_buffers needs to be at least 64KB
	IF wal_buffers < 65536 THEN
		wal_buffers := 65536;
	END IF;

	tuned_parameter := 'wal_buffers';
	IF (wal_buffers / (1048576)::decimal) > 1.00 THEN
		wal_buffers := round(wal_buffers / (1048576)::decimal);
		tuned_value := wal_buffers || 'MB';
	ELSE
		wal_buffers := round(wal_buffers / (1024)::decimal);
		tuned_value := wal_buffers || 'kB';
	END IF;
	orig_value := pem.server_tuning_original_value(tune_server_id, 'wal_buffers');
	RETURN NEXT;

	-- calculate effective_cache_size
	IF utilisation = 'UTILISATION_DEDICATED' THEN
		eff_cache_size := round(total_ram * (0.75)::decimal);
	ELSIF utilisation = 'UTILISATION_MIXED' THEN
		eff_cache_size := round(total_ram * (0.5)::decimal);
	ELSE
		eff_cache_size := round(total_ram * (0.25)::decimal);
	END IF;

	eff_cache_size := round(eff_cache_size / (1048576)::decimal);

	tuned_parameter := 'effective_cache_size';
	tuned_value := eff_cache_size || 'MB';
	orig_value := pem.server_tuning_original_value(tune_server_id, 'effective_cache_size');
	RETURN NEXT;

	-- calculate random_page_cost
	tuned_parameter := 'random_page_cost';
	IF utilisation = 'UTILISATION_DEDICATED' THEN
		tuned_value := '2.0';
	ELSIF utilisation = 'UTILISATION_MIXED' THEN
		tuned_value := '2.5';
	ELSE
		tuned_value := '3.0';
	END IF;
	orig_value := pem.server_tuning_original_value(tune_server_id, 'random_page_cost');
	RETURN NEXT;

	-- calculate checkpoint_segments
	tuned_parameter := 'checkpoint_segments';
	IF utilisation = 'UTILISATION_DEDICATED' THEN
		tuned_value := '64';
	ELSIF utilisation = 'UTILISATION_MIXED' THEN
		tuned_value := '32';
	ELSE
		tuned_value := '6';
	END IF;
	orig_value := pem.server_tuning_original_value(tune_server_id, 'checkpoint_segments');
	RETURN NEXT;

	RETURN;
END
$$ LANGUAGE plpgsql;

-- This function provides recommendation for tuning a given server based on the server utilization
-- and workload profile as selected by the user in the Tuning Wizard dialog. This function reads
-- system parameters like total RAM and shared memory and then suggests tuned values for some parameters
-- Parameters:
--    tune_server_id - server id of the server to tune
--    utilisation - utilisation enum to specify of server
--    profile - workload profile of the server instance
CREATE OR REPLACE FUNCTION pem.server_tuning (tune_server_id int, utilisation pem.tuning_server_util, profile pem.tuning_workload_profile)
RETURNS TABLE (tuned_server_id int, tuned_parameter text, tuned_value text, orig_value text)
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
		RETURN QUERY EXECUTE 'SELECT $1::int AS tuned_server_id, tuned_parameter, tuned_value, orig_value FROM ' ||
			'pem.server_tuning_oltp($1::int, $2::pem.tuning_server_util, $3::bigint, $4::bigint, $5::boolean)'
			USING tune_server_id, utilisation, total_ram_bytea, shared_memory_bytea, is_windows;
	ELSIF profile = 'WORKLOAD_MIXED' THEN
		RETURN QUERY EXECUTE 'SELECT $1::int AS tuned_server_id, tuned_parameter, tuned_value, orig_value FROM ' ||
			'pem.server_tuning_mixed($1::int, $2::pem.tuning_server_util, $3::bigint, $4::bigint, $5::boolean)'
			USING tune_server_id, utilisation, total_ram_bytea, shared_memory_bytea, is_windows;
	ELSE
		RETURN QUERY EXECUTE 'SELECT $1::int AS tuned_server_id, tuned_parameter, tuned_value, orig_value FROM ' ||
			'pem.server_tuning_dw($1::int, $2::pem.tuning_server_util, $3::bigint, $4::bigint, $5::boolean)'
			USING tune_server_id, utilisation, total_ram_bytea, shared_memory_bytea, is_windows;
	END IF;
END
$$ LANGUAGE plpgsql;

COMMIT TRANSACTION;
