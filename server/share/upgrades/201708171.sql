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
'SELECT 201708171::integer;'
  LANGUAGE 'sql' IMMUTABLE;

-- Add new column to store password for server in server_option table in pem
ALTER TABLE pem.server_option ADD COLUMN password text DEFAULT NULL;


-- Fixes RM 42331

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
	server_version int := 0;
	converted_value int := 0;
	shared_mem numeric(1000,0) := shared_memory;
	work_mem_factor decimal := 0.008;
	maint_work_mem_factor decimal := 0.08;
	server_chkpnt_cmpl_trgt decimal := 0.5;
	work_mem bigint := 0;
	maint_work_mem bigint := 0;
	shared_buffers bigint := 0;
	wal_buffers bigint := 0;
	eff_cache_size bigint := 0;
	is_checkpoint_segment_allowed boolean := TRUE;
	units int := 0;
BEGIN
	SELECT setting FROM pemdata.settings WHERE server_id = tune_server_id AND name='max_connections' INTO server_max_conn;
	SELECT setting FROM pemdata.settings WHERE server_id = tune_server_id AND name='max_locks_per_transaction' INTO server_max_locks_per_xact;
	SELECT setting FROM pemdata.settings WHERE server_id = tune_server_id AND name='max_prepared_transactions' INTO server_max_prepared_xacts;
	SELECT setting FROM pemdata.settings WHERE server_id = tune_server_id AND name='checkpoint_completion_target' INTO server_chkpnt_cmpl_trgt;
	SELECT server_version_id FROM pemdata.server_info WHERE server_id = tune_server_id INTO server_version;

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
		tuned_value := '2';
	ELSIF utilisation = 'UTILISATION_MIXED' THEN
		tuned_value := '2.5';
	ELSE
		tuned_value := '3';
	END IF;
	orig_value := pem.server_tuning_original_value(tune_server_id, 'random_page_cost');
	RETURN NEXT;

	-- check if checkpoint_segement is allowed or not depending upon the server version
	IF server_version >= 20905 THEN
		is_checkpoint_segment_allowed = false;
	ELSIF server_version >=10905 and server_version < 20000 THEN
		is_checkpoint_segment_allowed = false;
	ELSE
		is_checkpoint_segment_allowed = true;
	END IF;

	-- calculate checkpoint_segments for server_version < 9.5 and max_wal_size for server_version >= 9.5
	IF utilisation = 'UTILISATION_DEDICATED' THEN
		tuned_value := '32';
	ELSIF utilisation = 'UTILISATION_MIXED' THEN
		tuned_value := '16';
	ELSE
		tuned_value := '6';
	END IF;

	IF is_checkpoint_segment_allowed = TRUE THEN
		tuned_parameter := 'checkpoint_segments';
		orig_value := pem.server_tuning_original_value(tune_server_id, 'checkpoint_segments');
	ELSE
		tuned_parameter := 'max_wal_size';
		-- Reference: http://www.postgresql.org/message-id/E1YPwGB-0006vL-8V@gemulon.postgresql.org
		-- max_wal_size has been calculated using below formula:
		-- max_wal_size = ((2 + checkpoint_completion_target) * checkpoint_segments + 1)*wal_size
		-- where checkpoint_completion_target = Specifies the target of checkpoint completion, as a fraction of total time between checkpoints
		-- default value is 0.5
		-- checkpoint_segments = no of checkpoint decided depending upon utilization. default value is 6
		-- wal_size = size of wal file = 16 MB
		tuned_value = ((((server_chkpnt_cmpl_trgt)::decimal + (2)::decimal) * (tuned_value)::decimal) + (1)::integer) * (16)::integer;
		IF ((tuned_value)::decimal / (1024)::decimal) >= 1.00 THEN
			tuned_value := round((tuned_value)::decimal / (1024)::decimal) || 'GB';
		ELSE
			tuned_value := round((tuned_value)::decimal) || 'MB';
		END IF;
		SELECT COALESCE(SUBSTRING(setting from '[0-9]+'), '1')::decimal, COALESCE(SUBSTRING(unit from '[0-9]+'), '1')::decimal FROM pemdata.settings WHERE server_id = tune_server_id AND name = 'max_wal_size' INTO orig_value, units;
		converted_value := round((orig_value)::decimal * (units)::decimal);
	        IF (converted_value / (1024)::decimal) >= 1.00 THEN
			orig_value := round((converted_value)::decimal / (1024)::decimal) || 'GB';
		ELSE
			orig_value := round((converted_value)::decimal) || 'MB';
		END IF;
	END IF;
	RETURN NEXT;

	-- add min_wal_size for server_version < 9.5 and max_wal_size for server_version >= 9.5
	-- min_wal_size has the fixed size of 80 MB
	IF is_checkpoint_segment_allowed = FALSE THEN
		tuned_parameter := 'min_wal_size';
		tuned_value = '80MB';
		SELECT COALESCE(SUBSTRING(setting from '[0-9]+'), '1')::decimal, COALESCE(SUBSTRING(unit from '[0-9]+'), '1')::decimal FROM pemdata.settings WHERE server_id = tune_server_id AND name = 'min_wal_size' INTO orig_value, units;
		converted_value := round((orig_value)::decimal * (units)::decimal);
		IF (converted_value / (1024)::decimal) >= 1.00 THEN
			orig_value := round((converted_value)::decimal / (1024)::decimal) || 'GB';
		ELSE
			orig_value := round((converted_value)::decimal) || 'MB';
		END IF;
		RETURN NEXT;
	END IF;
	RETURN;
END;
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
	server_version int := 0;
	converted_value int := 0;
	shared_mem numeric(1000,0) := shared_memory;
	work_mem_factor decimal := 0.012;
	maint_work_mem_factor decimal := 0.1;
	server_chkpnt_cmpl_trgt decimal := 0.5;
	work_mem bigint := 0;
	maint_work_mem bigint := 0;
	shared_buffers bigint := 0;
	wal_buffers bigint := 0;
	eff_cache_size bigint := 0;
	is_checkpoint_segment_allowed boolean := TRUE;
	units int := 0;
BEGIN
	SELECT setting FROM pemdata.settings WHERE server_id = tune_server_id AND name='max_connections' INTO server_max_conn;
	SELECT setting FROM pemdata.settings WHERE server_id = tune_server_id AND name='max_locks_per_transaction' INTO server_max_locks_per_xact;
	SELECT setting FROM pemdata.settings WHERE server_id = tune_server_id AND name='max_prepared_transactions' INTO server_max_prepared_xacts;
	SELECT setting FROM pemdata.settings WHERE server_id = tune_server_id AND name='checkpoint_completion_target' INTO server_chkpnt_cmpl_trgt;
	SELECT server_version_id FROM pemdata.server_info WHERE server_id = tune_server_id INTO server_version;

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
		tuned_value := '2';
	ELSIF utilisation = 'UTILISATION_MIXED' THEN
		tuned_value := '2.5';
	ELSE
		tuned_value := '3';
	END IF;
	orig_value := pem.server_tuning_original_value(tune_server_id, 'random_page_cost');
	RETURN NEXT;

		-- check if checkpoint_segement is allowed or not depending upon the server version
	IF server_version >= 20905 THEN
		is_checkpoint_segment_allowed = false;
	ELSIF server_version >=10905 and server_version < 20000 THEN
		is_checkpoint_segment_allowed = false;
	ELSE
		is_checkpoint_segment_allowed = true;
	END IF;

	-- calculate checkpoint_segments for server_version < 9.5 and max_wal_size for server_version >= 9.5
	IF utilisation = 'UTILISATION_DEDICATED' THEN
		tuned_value := '48';
	ELSIF utilisation = 'UTILISATION_MIXED' THEN
		tuned_value := '24';
	ELSE
		tuned_value := '6';
	END IF;

	IF is_checkpoint_segment_allowed = TRUE THEN
		tuned_parameter := 'checkpoint_segments';
		orig_value := pem.server_tuning_original_value(tune_server_id, 'checkpoint_segments');
	ELSE
		tuned_parameter := 'max_wal_size';
		-- Reference: http://www.postgresql.org/message-id/E1YPwGB-0006vL-8V@gemulon.postgresql.org
		-- max_wal_size has been calculated using below formula:
		-- max_wal_size = ((2 + checkpoint_completion_target) * checkpoint_segments + 1)*wal_size
		-- where checkpoint_completion_target = Specifies the target of checkpoint completion, as a fraction of total time between checkpoints
		-- default value is 0.5
		-- checkpoint_segments = no of checkpoint decided depending upon utilization. default value is 6
		-- wal_size = size of wal file = 16 MB
		tuned_value = ((((server_chkpnt_cmpl_trgt)::decimal + (2)::decimal) * (tuned_value)::decimal) + (1)::integer) * (16)::integer;
		IF ((tuned_value)::decimal / (1024)::decimal) >= 1.00 THEN
			tuned_value := round((tuned_value)::decimal / (1024)::decimal) || 'GB';
		ELSE
			tuned_value := round((tuned_value)::decimal) || 'MB';
		END IF;
		SELECT COALESCE(SUBSTRING(setting from '[0-9]+'), '1')::decimal, COALESCE(SUBSTRING(unit from '[0-9]+'), '1')::decimal FROM pemdata.settings WHERE server_id = tune_server_id AND name = 'max_wal_size' INTO orig_value, units;
		converted_value := round((orig_value)::decimal * (units)::decimal);
		IF (converted_value / (1024)::decimal) >= 1.00 THEN
			orig_value := round((converted_value)::decimal / (1024)::decimal) || 'GB';
		ELSE
			orig_value := round((converted_value)::decimal) || 'MB';
		END IF;
	END IF;
	RETURN NEXT;

	-- add min_wal_size for server_version < 9.5 and max_wal_size for server_version >= 9.5
	-- min_wal_size has the fixed size of 80 MB
	IF is_checkpoint_segment_allowed = FALSE THEN
		tuned_parameter := 'min_wal_size';
		tuned_value = '80MB';
		SELECT COALESCE(SUBSTRING(setting from '[0-9]+'), '1')::decimal, COALESCE(SUBSTRING(unit from '[0-9]+'), '1')::decimal FROM pemdata.settings WHERE server_id = tune_server_id AND name = 'min_wal_size' INTO orig_value, units;
		converted_value := round((orig_value)::decimal * (units)::decimal);
		IF (converted_value / (1024)::decimal) >= 1.00 THEN
			orig_value := round((converted_value)::decimal / (1024)::decimal) || 'GB';
		ELSE
			orig_value := round((converted_value)::decimal) || 'MB';
		END IF;
		RETURN NEXT;
	END IF;
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
	server_version int := 0;
	converted_value int := 0;
	shared_mem numeric(1000,0) := shared_memory;
	work_mem_factor decimal := 0.020;
	maint_work_mem_factor decimal := 0.2;
	server_chkpnt_cmpl_trgt decimal := 0.5;
	work_mem bigint := 0;
	maint_work_mem bigint := 0;
	shared_buffers bigint := 0;
	wal_buffers bigint := 0;
	eff_cache_size bigint := 0;
	is_checkpoint_segment_allowed boolean := TRUE;
	units int := 0;
BEGIN
	SELECT setting FROM pemdata.settings WHERE server_id = tune_server_id AND name='max_connections' INTO server_max_conn;
	SELECT setting FROM pemdata.settings WHERE server_id = tune_server_id AND name='max_locks_per_transaction' INTO server_max_locks_per_xact;
	SELECT setting FROM pemdata.settings WHERE server_id = tune_server_id AND name='max_prepared_transactions' INTO server_max_prepared_xacts;
	SELECT setting FROM pemdata.settings WHERE server_id = tune_server_id AND name='checkpoint_completion_target' INTO server_chkpnt_cmpl_trgt;
	SELECT server_version_id FROM pemdata.server_info WHERE server_id = tune_server_id INTO server_version;

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
		tuned_value := '2';
	ELSIF utilisation = 'UTILISATION_MIXED' THEN
		tuned_value := '2.5';
	ELSE
		tuned_value := '3';
	END IF;
	orig_value := pem.server_tuning_original_value(tune_server_id, 'random_page_cost');
	RETURN NEXT;

		-- check if checkpoint_segement is allowed or not depending upon the server version
	IF server_version >= 20905 THEN
		is_checkpoint_segment_allowed = false;
	ELSIF server_version >=10905 and server_version < 20000 THEN
		is_checkpoint_segment_allowed = false;
	ELSE
		is_checkpoint_segment_allowed = true;
	END IF;

	-- calculate checkpoint_segments for server_version < 9.5 and max_wal_size for server_version >= 9.5
	IF utilisation = 'UTILISATION_DEDICATED' THEN
		tuned_value := '64';
	ELSIF utilisation = 'UTILISATION_MIXED' THEN
		tuned_value := '32';
	ELSE
		tuned_value := '6';
	END IF;

	IF is_checkpoint_segment_allowed = TRUE THEN
		tuned_parameter := 'checkpoint_segments';
		orig_value := pem.server_tuning_original_value(tune_server_id, 'checkpoint_segments');
	ELSE
		tuned_parameter := 'max_wal_size';
		-- Reference: http://www.postgresql.org/message-id/E1YPwGB-0006vL-8V@gemulon.postgresql.org
		-- max_wal_size has been calculated using below formula:
		-- max_wal_size = ((2 + checkpoint_completion_target) * checkpoint_segments + 1)*wal_size
		-- where checkpoint_completion_target = Specifies the target of checkpoint completion, as a fraction of total time between checkpoints
		-- default value is 0.5
		-- checkpoint_segments = no of checkpoint decided depending upon utilization. default value is 6
		-- wal_size = size of wal file = 16 MB
		tuned_value = ((((server_chkpnt_cmpl_trgt)::decimal + (2)::decimal) * (tuned_value)::decimal) + (1)::integer) * (16)::integer;
		IF ((tuned_value)::decimal / (1024)::decimal) >= 1.00 THEN
			tuned_value := round((tuned_value)::decimal / (1024)::decimal) || 'GB';
		ELSE
			tuned_value := round((tuned_value)::decimal) || 'MB';
		END IF;
		SELECT COALESCE(SUBSTRING(setting from '[0-9]+'), '1')::decimal, COALESCE(SUBSTRING(unit from '[0-9]+'), '1')::decimal FROM pemdata.settings WHERE server_id = tune_server_id AND name = 'max_wal_size' INTO orig_value, units;
		converted_value := round((orig_value)::decimal * (units)::decimal);
		IF (converted_value / (1024)::decimal) >= 1.00 THEN
			orig_value := round((converted_value)::decimal / (1024)::decimal) || 'GB';
		ELSE
			orig_value := round((converted_value)::decimal) || 'MB';
		END IF;
	END IF;
	RETURN NEXT;

	-- add min_wal_size for server_version < 9.5 and max_wal_size for server_version >= 9.5
	-- min_wal_size has the fixed size of 80 MB
	IF is_checkpoint_segment_allowed = FALSE THEN
		tuned_parameter := 'min_wal_size';
		tuned_value = '80MB';
		SELECT COALESCE(SUBSTRING(setting from '[0-9]+'), '1')::decimal, COALESCE(SUBSTRING(unit from '[0-9]+'), '1')::decimal FROM pemdata.settings WHERE server_id = tune_server_id AND name = 'min_wal_size' INTO orig_value, units;
		converted_value := round((orig_value)::decimal * (units)::decimal);
		IF (converted_value / (1024)::decimal) >= 1.00 THEN
			orig_value := round((converted_value)::decimal / (1024)::decimal) || 'GB';
		ELSE
			orig_value := round((converted_value)::decimal) || 'MB';
		END IF;
		RETURN NEXT;
	END IF;
	RETURN;
END
$$ LANGUAGE plpgsql;

-- RM #41965
ALTER TABLE pem.audit_configuration
	ADD COLUMN edb_audit_destination text DEFAULT ''::text;
COMMENT ON COLUMN pem.audit_configuration.edb_audit_destination IS 'Audit log destination';

ALTER TABLE pemdata.audit_configuration
   ADD COLUMN edb_audit_destination text DEFAULT ''::text;
COMMENT ON COLUMN pemdata.audit_configuration.edb_audit_destination IS 'Audit log destination';

ALTER TABLE pemhistory.audit_configuration
	ADD COLUMN edb_audit_destination text DEFAULT ''::text;
COMMENT ON COLUMN pemhistory.audit_configuration.edb_audit_destination IS 'Audit log destination';

INSERT INTO pem.probe_column
        (probe_id, internal_name, display_name, display_position, classification,
        sql_data_type, unit_of_value, calculate_pit, discard_history, pit_by_default, is_graphable)
SELECT
        (SELECT max(id) FROM pem.probe where internal_name = 'audit_configuration'),
        v.internal_name, v.display_name, v.display_position, v.classification,
        v.sql_data_type, v.unit_of_value, v.calculate_pit, v.discard_history, v.pit_by_default, v.is_graphable
FROM
        (VALUES
                ('edb_audit_destination', 'Audit log destination', 11, 'm', 'text', '', false, false, false, false)
        ) v(internal_name, display_name, display_position, classification,
                sql_data_type, unit_of_value, calculate_pit, discard_history, pit_by_default, is_graphable);

UPDATE pem.alert_template set sql = 'SELECT
  CASE
    WHEN COUNT(r.result) <> 0 THEN MAX(r.result)
    ELSE -1
  END
FROM
  (SELECT
     CASE
       WHEN(p.edb_audit = pd.edb_audit
         AND p.edb_audit_directory = pd.edb_audit_directory
         AND p.edb_audit_filename = pd.edb_audit_filename
         AND p.edb_audit_rotation_day = pd.edb_audit_rotation_day
         AND p.edb_audit_rotation_sec = pd.edb_audit_rotation_sec
         AND p.edb_audit_rotation_size = pd.edb_audit_rotation_size
         AND p.edb_audit_connect = pd.edb_audit_connect
         AND p.edb_audit_disconnect = pd.edb_audit_disconnect
         AND p.edb_audit_statements = pd.edb_audit_statements
         AND p.edb_audit_tag = pd.edb_audit_tag
         AND p.edb_audit_destination = pd.edb_audit_destination) OR (p.server_id IS NULL)
         THEN -1
       ELSE 1
     END AS result
   FROM
	pem.audit_configuration p RIGHT JOIN
	pemdata.audit_configuration pd ON (p.server_id = pd.server_id)
   WHERE p.server_id = ${server_id}) AS r'
WHERE display_name = 'Audit config mismatch' AND
	is_system_template = TRUE;

CREATE OR REPLACE FUNCTION pemdata.copy_audit_configuration_to_history()
    RETURNS trigger
    LANGUAGE 'plpgsql'
    COST 100.0
    VOLATILE NOT LEAKPROOF
AS $BODY$

  BEGIN
    IF (TG_OP = 'INSERT' OR TG_OP = 'UPDATE') THEN
      INSERT INTO pemhistory.audit_configuration (recorded_time, server_id, edb_audit, edb_audit_directory, edb_audit_filename, edb_audit_rotation_day, edb_audit_rotation_size, edb_audit_rotation_sec, edb_audit_connect, edb_audit_disconnect, edb_audit_statements, edb_audit_tag, edb_audit_destination) VALUES (NEW.recorded_time, NEW.server_id, NEW.edb_audit, NEW.edb_audit_directory, NEW.edb_audit_filename, NEW.edb_audit_rotation_day, NEW.edb_audit_rotation_size, NEW.edb_audit_rotation_sec, NEW.edb_audit_connect, NEW.edb_audit_disconnect, NEW.edb_audit_statements, NEW.edb_audit_tag, NEW.edb_audit_destination);
      ELSIF EXISTS(SELECT 1 FROM pem.server WHERE id = OLD.server_id) THEN
      INSERT INTO pemhistory.audit_configuration (server_id) VALUES (OLD.server_id);
    END IF;
    RETURN NEW;
  END;

$BODY$;

/*
-- This method returns the up and down time of specified agent with in
-- given time interval (Start and End time)
--
-- RETURNS table
--
-- Parameters:
--
-- p_agent_id		      : Agent ID.
-- p_start_datetime	      : Start time.
-- p_end_datetime	      : End time.
*/

CREATE OR REPLACE FUNCTION pem.agent_down_status(p_agent_id int, p_start_datetime timestamptz, p_end_datetime timestamptz)
RETURNS TABLE(o_down_datetime timestamptz, o_up_datetime timestamptz)
AS $$
DECLARE
	v_alert_id  integer;
	v_curr_rec  record;
	v_prev_state pem.alert_state := NULL;
BEGIN
	SELECT id INTO v_alert_id FROM pem.alert WHERE agent_id = p_agent_id and template_id = (SELECT id FROM pem.alert_template WHERE display_name = 'Agent Down');
	o_down_datetime := NULL;
	o_up_datetime := NULL;

	FOR v_curr_rec IN EXECUTE '
SELECT
    state, generated as recorded_time
FROM
    pem.alert_history
WHERE
    alert_id = $1::integer AND generated >= $2::timestamptz AND generated <= $3::timestamptz
ORDER BY generated;' USING v_alert_id, p_start_datetime, p_end_datetime
        LOOP
		IF v_curr_rec.state IS NOT NULL THEN
			IF v_prev_state IS NULL THEN
				o_down_datetime := v_curr_rec.recorded_time;
			END IF;
		ELSE
			IF v_prev_state IS NOT NULL THEN
				o_up_datetime := v_curr_rec.recorded_time;
			ELSE
				o_down_datetime := p_start_datetime;
				o_up_datetime := v_curr_rec.recorded_time;
			END IF;
			RETURN NEXT;
			o_down_datetime := NULL;
			o_up_datetime := NULL;
		END IF;
		v_prev_state := v_curr_rec.state;
	END LOOP;

	IF o_down_datetime IS NOT NULL THEN
		o_up_datetime := p_end_datetime;
		RETURN NEXT;
	END IF;
END
$$ LANGUAGE 'plpgsql';

/*
-- This method returns the up and down time of specified server with in
-- given time interval (Start and End time)
--
-- RETURNS table
--
-- Parameters:
--
-- p_server_id		      : Server ID.
-- p_start_datetime	      : Start time.
-- p_end_datetime	      : End time.
*/

CREATE OR REPLACE FUNCTION pem.server_down_status(p_server_id int, p_start_datetime timestamptz, p_end_datetime timestamptz)
RETURNS TABLE(o_down_datetime timestamptz, o_up_datetime timestamptz)
AS $$
DECLARE
	v_alert_id  integer;
	v_curr_rec  record;
	v_prev_state pem.alert_state := NULL;
BEGIN
	SELECT id INTO v_alert_id FROM pem.alert WHERE server_id = p_server_id and template_id = (SELECT id FROM pem.alert_template WHERE display_name = 'Server Down');
	o_down_datetime := NULL;
	o_up_datetime := NULL;

	FOR v_curr_rec IN EXECUTE '
SELECT
    state, generated as recorded_time
FROM
    pem.alert_history
WHERE
    alert_id = $1::integer AND generated >= $2::timestamptz AND generated <= $3::timestamptz
ORDER BY generated;' USING v_alert_id, p_start_datetime, p_end_datetime
        LOOP
		IF v_curr_rec.state IS NOT NULL THEN
			IF v_prev_state IS NULL THEN
				o_down_datetime := v_curr_rec.recorded_time;
			END IF;
		ELSE
			IF v_prev_state IS NOT NULL THEN
				o_up_datetime := v_curr_rec.recorded_time;
			ELSE
				o_down_datetime := p_start_datetime;
				o_up_datetime := v_curr_rec.recorded_time;
			END IF;
			RETURN NEXT;
			o_down_datetime := NULL;
			o_up_datetime := NULL;
		END IF;
		v_prev_state := v_curr_rec.state;
	END LOOP;

	IF o_down_datetime IS NOT NULL THEN
		o_up_datetime := p_end_datetime;
		RETURN NEXT;
	END IF;
END
$$ LANGUAGE 'plpgsql';

COMMIT TRANSACTION;
