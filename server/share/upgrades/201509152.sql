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
'SELECT 201509152::integer;'
  LANGUAGE 'sql' IMMUTABLE;
COMMENT ON FUNCTION pem.schema_version() IS 'Returns the version number of the PEM schema';


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
		orig_value := pem.server_tuning_original_value(tune_server_id, 'max_wal_size');
		converted_value := round((orig_value)::decimal * (16)::decimal);
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
		orig_value := pem.server_tuning_original_value(tune_server_id, 'min_wal_size');
		converted_value := round((orig_value)::decimal * (16)::decimal);
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
		orig_value := pem.server_tuning_original_value(tune_server_id, 'max_wal_size');
		converted_value := round((orig_value)::decimal * (16)::decimal);
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
		orig_value := pem.server_tuning_original_value(tune_server_id, 'min_wal_size');
		converted_value := round((orig_value)::decimal * (16)::decimal);
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
		orig_value := pem.server_tuning_original_value(tune_server_id, 'max_wal_size');
		converted_value := round((orig_value)::decimal * (16)::decimal);
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
		orig_value := pem.server_tuning_original_value(tune_server_id, 'min_wal_size');
		converted_value := round((orig_value)::decimal * (16)::decimal);
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
COMMIT TRANSACTION;
