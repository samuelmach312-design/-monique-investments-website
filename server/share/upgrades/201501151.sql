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
'SELECT 201501151::integer;'
  LANGUAGE 'sql' IMMUTABLE;

ALTER TABLE pem.alert_template
	ADD COLUMN is_system_template boolean NOT NULL DEFAULT true;

DROP FUNCTION pem.create_alert_template(text, text, text, integer, text[], pem.alert_param_type[], text[], text, text[], integer, pem.server_type, integer, integer);
CREATE OR REPLACE FUNCTION pem.create_alert_template(
									name				text,
									description			text,
									sql				text,
									object_type			integer,
									param_names			text[],
									param_types			pem.alert_param_type[],
									param_units			text[],
									threshold_unit			text,
									probe_dependency_list		text[] DEFAULT '{}',
									snmp_oid			integer DEFAULT 0,
									applicable_on_server            pem.server_type DEFAULT 'ALL',
									default_check_frequency		integer DEFAULT 1,
									default_history_retention	integer DEFAULT 30,
									is_system_template boolean	DEFAULT true
									)
RETURNS VOID AS $$
	/*
	 * If we ever change to pl/pgsql, we might want to validate input and RAISE
	 * exceptions here.
	 *
	 * If this INSERT fails the user will see the ERROR with this function's
	 * name in context, hence it doesn't seem any worse than validating params
	 * and RAISE'ing errors, except that by using RAISE we can provide friendly
	 * hints.
	 */
	INSERT INTO pem.alert_template (display_name, description, sql, object_type,
									param_names, param_types, param_units,
									threshold_unit, probe_dependency_list, snmp_oid, applicable_on_server,
									default_check_frequency, default_history_retention, is_system_template)
	VALUES($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, $14);
$$ LANGUAGE SQL;

-- Function to change snmp oid if object_type of alert template is changed
CREATE OR REPLACE FUNCTION pem.update_snmp_oid() RETURNS trigger AS $$
BEGIN
	EXECUTE 'SELECT CASE WHEN MAX(snmp_oid) > 0 THEN MAX(snmp_oid) + 1 ELSE 1 END FROM pem.alert_template WHERE object_type = $1' USING NEW.object_type INTO NEW.snmp_oid;
	RETURN NEW;
END
$$ LANGUAGE plpgsql;

-- Trigger on pem.alert_template when the object_type of alert template is changed
CREATE TRIGGER alert_template_snmp_oid
    BEFORE UPDATE ON pem.alert_template
    FOR EACH ROW
    WHEN (OLD.object_type != NEW.object_type)
    EXECUTE PROCEDURE pem.update_snmp_oid();

CREATE TABLE pem.chart_config
(
	-- chart id (reference to pem.chart)
	cid      integer NOT NULL,
	-- user
	uid      oid NOT NULL,
	-- dashboard level
	level    integer NOT NULL,
	-- dashboard id
	did      integer NOT NULL DEFAULT -1::integer,
	objid      integer,
	database text,
	schema   text,
	tbl      text,
	reload   integer,
	colors   pem.chart_metric_param[],
	span     integer,
	espan    integer,
	points   integer,
	sortseq  int[],
	CONSTRAINT pem_chart_config_fk_cid FOREIGN KEY (cid) REFERENCES pem.chart(id)
		MATCH SIMPLE ON UPDATE CASCADE ON DELETE CASCADE INITIALLY DEFERRED,
	CONSTRAINT pem_chart_config_reload_constraint CHECK (reload >= 10 AND reload <= 7200),
	CONSTRAINT pem_chart_config_points_constraint CHECK (points >= 20 AND points <= 500),
	CONSTRAINT pem_chart_config_type_constraint CHECK (
		CASE
		WHEN tbl IS NOT NULL THEN objid IS NOT NULL AND database IS NOT NULL AND schema IS NOT NULL
		WHEN schema IS NOT NULL THEN objid IS NOT NULL AND database IS NOT NULL
		WHEN database IS NOT NULL THEN objid IS NOT NULL
		ELSE true
		END
	)
);

COMMENT ON TABLE  pem.chart_config IS '
* Helps to store the chart settings per user on all/specific dashboard
* This table contains settings such as:
  - Auto-Refresh (reload - in seconds)
  - Colors (colors - for each metrics for line, bar, pie charts)
  - Span   (span - applicable to line chart)
  - Extrapolated Span (espan - applicable to line chart with extrapolated time)
  - Points (points - applicable to line chart)
  - Sorting Sequence (sortseq - applicable to table chart)
* These settings are application to the specific chart and user combination on
  specific/all dashboard(s).
* If did is equal to -1:
  + If objid is NULL, then it is applicable on all the dashboards for any server/agent.
  + If database is NULL, then it is applicable to any dashboards for the given
    server.
  + If schema is NULL, then it is applicable to any dashboards for the
    combination of the given server, and database
  + If tbl is NULL, then it is applicable to any dashboards for the
    combination of the given server, database, and tbl';

CREATE UNIQUE INDEX pem_chart_config_uid_did_idx ON pem.chart_config USING btree (cid, uid, did)
	WHERE objid IS NULL;

CREATE INDEX pem_chart_config_objid_idx ON pem.chart_config USING btree (cid, uid, did, objid)
	WHERE objid IS NOT NULL AND database IS NULL;

CREATE UNIQUE INDEX pem_chart_config_objid_db_idx ON pem.chart_config USING btree (cid, uid, did, objid, database)
	WHERE objid IS NOT NULL AND database IS NOT NULL AND schema IS NULL;

CREATE UNIQUE INDEX pem_chart_config_objid_db_schema_idx ON pem.chart_config USING btree (cid, uid, did, objid, database, schema)
	WHERE objid IS NOT NULL AND database IS NOT NULL AND schema IS NOT NULL AND tbl IS NULL;

CREATE UNIQUE INDEX pem_chart_config_objid_db_schema_tbl_idx ON pem.chart_config USING btree (cid, uid, did, objid, database, schema, tbl)
	WHERE objid IS NOT NULL AND database IS NOT NULL AND schema IS NOT NULL AND tbl IS NOT NULL;


-- Feature #31982
UPDATE pem.pe_rules_text SET trigger = 'shared_buffers < 2MB OR shared_buffers > 8GB', recommended_value = '' WHERE name = 'Check shared_buffers';
UPDATE pem.pe_rules_text SET trigger = 'work_mem < 1MB', recommended_value = '' WHERE name = 'Check work_mem';
UPDATE pem.pe_rules_text SET trigger = 'maintenance_work_mem < 16MB OR maintenance_work_mem > 256MB', recommended_value = ''  WHERE name = 'Check maintenance_work_mem';
UPDATE pem.pe_rules_text SET recommended_value = ''  WHERE name = 'Check wal_buffers';
UPDATE pem.pe_rules_text SET recommended_value = ''  WHERE name = 'Check reducing random_page_cost';
UPDATE pem.pe_rules_text SET recommended_value = ''  WHERE name = 'Check checkpoint_segments';
UPDATE pem.pe_rules_text SET description = 'When estimating the cost of a nested loop with an inner index-scan, PostgreSQL uses this parameter to estimate the chances that rows from the inner relation which are fetched multiple times will still be in cache when the second fetch occurs.  Changing this parameter does not allocate any memory, but an excessively small value may discourage the planner from using indexes which would in fact speed up the query.', trigger = 'Current value is not equal to recommended value', recommended_value = ''  WHERE name = 'Check effective_cache_size';

CREATE OR REPLACE FUNCTION pem.pe_rule_shared_buffers(serverID int, rulename text) RETURNS BOOLEAN
AS $$
DECLARE
	shared_buffer_val decimal := 0;
	system_memory_val decimal:= 0;
	agentid int:= 0;
	severity_val int:= 0;
	data_name_arr text[];
	data_value_arr text[];
	shared_buffer_text text;
	system_memory_text text;
	shared_buffer_recommanded_val text;

BEGIN
	-- Get the original value and recommanded value of shared buffer .
	SELECT tuned_value, orig_value INTO shared_buffer_recommanded_val, shared_buffer_text FROM pem.server_tuning(serverID, 'UTILISATION_DEDICATED', 'WORKLOAD_OLTP') WHERE tuned_parameter = 'shared_buffers';
	shared_buffer_val = (substring(shared_buffer_text, 1, char_length(shared_buffer_text) - 2))::decimal;

	-- Get the agent id from the pemdata.agent_server_binding table.
	SELECT agent_id INTO agentid FROM pem.agent_server_binding WHERE server_id = serverID;

	-- Get the value of system memory.
	SELECT total_ram_memory_mb INTO system_memory_val FROM pemdata.memory_usage WHERE agent_id = agentid;

	-- Condition for trigger shared_buffers < 2MB OR shared_buffers > 8GB
	IF (shared_buffer_val < 2) OR (shared_buffer_val > (8 * 1024)) THEN
		severity_val := 5;

		system_memory_text := system_memory_val::int;

		data_name_arr[0] := 'shared_buffer';
		data_name_arr[1] := 'total_ram_memory';

		data_value_arr[0] := shared_buffer_text;
		data_value_arr[1] := system_memory_text || ' MB';

		-- Update the values of data_name , data_value and severity
		UPDATE temp_expert_records SET data_name = data_name_arr, data_value = data_value_arr, severity = severity_val, recommended_value = shared_buffer_recommanded_val WHERE rule_name = rulename AND server_id = serverID ;
	ELSE
		DELETE FROM temp_expert_records WHERE rule_name = rulename AND server_id = serverID ;
	END IF;

	RETURN TRUE;
END
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION pem.pe_rule_work_mem(serverID int, rulename text) RETURNS BOOLEAN
AS $$
DECLARE
	work_mem_val decimal := 0;
	system_memory_val decimal:= 0;
	agentid int:= 0;
	severity_val int:= 0;
	data_name_arr text[];
	data_value_arr text[];
	work_mem_text text;
	system_memory_text text;
	work_mem_recommanded_val text;

BEGIN
	-- Get the original value and recommanded value of work mem.
	SELECT tuned_value, orig_value INTO work_mem_recommanded_val, work_mem_text FROM pem.server_tuning(serverID, 'UTILISATION_DEDICATED', 'WORKLOAD_OLTP') WHERE tuned_parameter = 'work_mem';
	work_mem_val = (substring(work_mem_text, 1, char_length(work_mem_text) - 2))::decimal;

	-- Get the agent id from the pemdata.agent_server_binding table.
	SELECT agent_id INTO agentid FROM pem.agent_server_binding WHERE server_id = serverID;

	-- Get the value of system memory.
	SELECT total_ram_memory_mb INTO system_memory_val FROM pemdata.memory_usage WHERE agent_id = agentid;

	-- Condition for trigger work_mem < 1MB
	IF (work_mem_val < 1) THEN
		severity_val := 5;

		system_memory_text := system_memory_val::int;

		data_name_arr[0] := 'work_mem';
		data_name_arr[1] := 'total_ram_memory';

		data_value_arr[0] := work_mem_text;
		data_value_arr[1] := system_memory_text || ' MB';

		-- Update the values of data_name , data_value and severity
		UPDATE temp_expert_records SET data_name = data_name_arr, data_value = data_value_arr, severity = severity_val, recommended_value = work_mem_recommanded_val WHERE rule_name = rulename AND server_id = serverID ;
	ELSE
		DELETE FROM temp_expert_records WHERE rule_name = rulename AND server_id = serverID ;
	END IF;

	RETURN TRUE;
END
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION pem.pe_rule_maintenance_work_mem(serverID int, rulename text) RETURNS BOOLEAN
AS $$
DECLARE
	maintenance_work_mem_val decimal := 0;
	system_memory_val decimal:= 0;
	agentid int:= 0;
	severity_val int:= 0;
	data_name_arr text[];
	data_value_arr text[];
	maintenance_work_mem_text text;
	system_memory_text text;
	main_work_mem_recommanded_val text;

BEGIN
	-- Get the original value and recommanded value of maintenance work mem.
	SELECT tuned_value, orig_value INTO main_work_mem_recommanded_val, maintenance_work_mem_text FROM pem.server_tuning(serverID, 'UTILISATION_DEDICATED', 'WORKLOAD_OLTP') WHERE tuned_parameter = 'maintenance_work_mem';
	maintenance_work_mem_val = (substring(maintenance_work_mem_text, 1, char_length(maintenance_work_mem_text) - 2))::decimal;

	-- Get the agent id from the pemdata.agent_server_binding table.
	SELECT agent_id INTO agentid FROM pem.agent_server_binding WHERE server_id = serverID;

	-- Get the value of system memory.
	SELECT total_ram_memory_mb INTO system_memory_val FROM pemdata.memory_usage WHERE agent_id = agentid;

	-- Condition for trigger maintenance_work_mem < 16MB OR maintenance_work_mem > 256MB
	IF (maintenance_work_mem_val < 16) OR (maintenance_work_mem_val > 256) THEN
		severity_val := 1;

		system_memory_text := system_memory_val::int;

		data_name_arr[0] := 'maintenance_work_mem';
		data_name_arr[1] := 'total_ram_memory';

		data_value_arr[0] := maintenance_work_mem_text;
		data_value_arr[1] := system_memory_text || ' MB';

		-- Update the values of data_name , data_value and severity
		UPDATE temp_expert_records SET data_name = data_name_arr, data_value = data_value_arr, severity = severity_val, recommended_value = main_work_mem_recommanded_val WHERE rule_name = rulename AND server_id = serverID ;
	ELSE
		DELETE FROM temp_expert_records WHERE rule_name = rulename AND server_id = serverID ;
	END IF;

	RETURN TRUE;
END
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION pem.pe_rule_wal_buffers(serverID int, rulename text) RETURNS BOOLEAN
AS $$
DECLARE
	wal_buffers_val decimal := 0;
	severity_val int:= 0;
	data_name_arr text[];
	data_value_arr text[];
	wal_buffers_text text;
	wal_buffers_recommanded_val text;

BEGIN
	-- Get the original value and recommanded value of  wal buffers.
	SELECT tuned_value, orig_value INTO wal_buffers_recommanded_val, wal_buffers_text FROM pem.server_tuning(serverID, 'UTILISATION_DEDICATED', 'WORKLOAD_OLTP') WHERE tuned_parameter = 'wal_buffers';
	wal_buffers_val = (substring(wal_buffers_text, 1, char_length(wal_buffers_text) - 2))::decimal;

	IF (wal_buffers_val < 1) OR (wal_buffers_val > 16) THEN
		severity_val := 5;

		data_name_arr[0] := 'wal_buffers';
		data_value_arr[0] := wal_buffers_text;

		-- Update the values of data_name , data_value and severity
		UPDATE temp_expert_records SET data_name = data_name_arr, data_value = data_value_arr, severity = severity_val, recommended_value = wal_buffers_recommanded_val WHERE rule_name = rulename AND server_id = serverID ;
	ELSE
		DELETE FROM temp_expert_records WHERE rule_name = rulename AND server_id = serverID ;
	END IF;

	RETURN TRUE;
END
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION pem.pe_rule_checkpoint_segments(serverID int, rulename text) RETURNS BOOLEAN
AS $$
DECLARE
	checkpoint_segments_val int:= 0;
	severity_val int:= 0;
	data_name_arr text[];
	data_value_arr text[];
	checkpoint_segment_recommanded_val text;

BEGIN
	-- Get the original value and recommanded value of checkpoint_segments.
	SELECT tuned_value, orig_value INTO checkpoint_segment_recommanded_val, checkpoint_segments_val FROM pem.server_tuning(serverID, 'UTILISATION_DEDICATED', 'WORKLOAD_OLTP') WHERE tuned_parameter = 'checkpoint_segments';

	IF (checkpoint_segments_val < 10) OR (checkpoint_segments_val > 300) THEN
		severity_val := 5;

		data_name_arr[0] := 'checkpoint_segments';
		data_value_arr[0] := checkpoint_segments_val;

		-- Update the values of data_name , data_value and severity
		UPDATE temp_expert_records SET data_name = data_name_arr, data_value = data_value_arr, severity = severity_val, recommended_value = checkpoint_segment_recommanded_val WHERE rule_name = rulename AND server_id = serverID ;
	ELSE
		DELETE FROM temp_expert_records WHERE rule_name = rulename AND server_id = serverID ;
	END IF;

	RETURN TRUE;
END
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION pem.pe_rule_effective_cache_size(serverID int, rulename text) RETURNS BOOLEAN
AS $$
DECLARE
	effective_cache_size_val decimal := 0;
	recommended_val decimal := 0;
	system_memory_val decimal:= 0;
	agentid int:= 0;
	severity_val int:= 0;
	data_name_arr text[];
	data_value_arr text[];
	effective_cache_size_text text;
	system_memory_text text;
	effective_cache_size_recommanded_val text;

BEGIN
	-- Get the original value and recommanded value of effective cache size.
	SELECT tuned_value, orig_value INTO effective_cache_size_recommanded_val, effective_cache_size_text FROM pem.server_tuning(serverID, 'UTILISATION_DEDICATED', 'WORKLOAD_OLTP') WHERE tuned_parameter = 'effective_cache_size';
	effective_cache_size_val = (substring(effective_cache_size_text, 1, char_length(effective_cache_size_text) - 2))::decimal;
	recommended_val = (substring(effective_cache_size_recommanded_val, 1, char_length(effective_cache_size_recommanded_val) - 2))::decimal;

	-- Get the agent id from the pemdata.agent_server_binding table.
	SELECT agent_id INTO agentid FROM pem.agent_server_binding WHERE server_id = serverID;

	-- Get the value of system memory.
	SELECT total_ram_memory_mb INTO system_memory_val FROM pemdata.memory_usage WHERE agent_id = agentid;

	-- Condition of trigger effective_cache_size is not equal to recommended value
	IF (effective_cache_size_val != recommended_val) THEN
		severity_val := 5;

		system_memory_text := system_memory_val::int;

		data_name_arr[0] := 'effective_cache_size';
		data_name_arr[1] := 'total_ram_memory';

		data_value_arr[0] := effective_cache_size_text;
		data_value_arr[1] := system_memory_text || ' MB';

		-- Update the values of data_name , data_value and severity
		UPDATE temp_expert_records SET data_name = data_name_arr, data_value = data_value_arr, severity = severity_val, recommended_value = effective_cache_size_recommanded_val WHERE rule_name = rulename AND server_id = serverID ;
	ELSE
		DELETE FROM temp_expert_records WHERE rule_name = rulename AND server_id = serverID ;
	END IF;

	RETURN TRUE;
END
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION pem.pe_rule_reducing_random_page_cost(serverID int, rulename text) RETURNS BOOLEAN
AS $$
DECLARE
	seq_page_cost_val decimal := 0;
	random_page_cost_val decimal := 0;
	severity_val int:= 0;
	data_name_arr text[];
	data_value_arr text[];
	random_page_cost_recommanded_val text;

BEGIN
	-- Get the original value of sequential page cost.
	SELECT setting INTO seq_page_cost_val FROM pemdata.settings WHERE server_id = serverID AND name = 'seq_page_cost';

	-- Get the original value and recommanded value of random page cost.
	SELECT tuned_value, orig_value INTO random_page_cost_recommanded_val, random_page_cost_val FROM pem.server_tuning(serverID, 'UTILISATION_DEDICATED', 'WORKLOAD_OLTP') WHERE tuned_parameter = 'random_page_cost';

	IF (random_page_cost_val > (seq_page_cost_val * 2)) THEN
		severity_val := 1;

		data_name_arr[0] := 'seq_page_cost';
		data_name_arr[1] := 'random_page_cost';

		data_value_arr[0] := seq_page_cost_val::decimal(25,3);
		data_value_arr[1] := random_page_cost_val::decimal(25,3);

		-- Update the values of data_name , data_value and severity
		UPDATE temp_expert_records SET data_name = data_name_arr, data_value = data_value_arr, severity = severity_val, recommended_value = random_page_cost_recommanded_val WHERE rule_name = rulename AND server_id = serverID ;
	ELSE
		DELETE FROM temp_expert_records WHERE rule_name = rulename AND server_id = serverID ;
	END IF;

	RETURN TRUE;
END
$$ LANGUAGE plpgsql;

DROP FUNCTION pem.generate_metric_chart_data (integer, integer, integer, text, text, integer, boolean, timestamptz, timestamptz);

-------------------------------------------------------------------------------
-- Function:                                                                  -
--    pem.generate_metric_chart_data                                          -
--                                                                            -
-- Parameters:                                                                -
--    p_cid     : chart-id                                                    -
--    p_did     : dashboard-id                                                    -
--    p_aid     : agent-id                                                    -
--    p_sid     : server-id                                                   -
--    p_db      : database-name                                               -
--    p_schema  : schema-name                                                 -
--    p_tbl     : table-name                                                 -
--    p_level   : Current dashboard level                                     -
--    p_sysobjs : Show the system objects                                     -
--    p_stime   : Start time                                                  -
--    p_etime   : End time                                                    -
--                                                                            -
-- Returns:                                                                   -
--    o_idx     : Index (position) of the generated data                      -
--    o_label   : Custom label if generated                                   -
--    o_aggtime : Aggregated time for generated data                          -
--    o_agg_val : Calculated the aggregated value at that point               -
--                                                                            -
-- Purpose:                                                                   -
--    This will generate the aggregated values for the metrices for the       -
--    line/table charts. The last three parameters are used to calculate the  -
--    points for the zoom support.                                            -
--                                                                            -
-------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION pem.generate_metric_chart_data (
	p_cid integer, p_did integer, p_aid integer, p_sid integer, p_db text, p_schema text, p_tbl text,
	p_level integer, p_sysobjs boolean, p_stime timestamptz DEFAULT NULL,
	p_etime timestamptz DEFAULT NULL)
RETURNS TABLE(o_idx int2, o_label text, o_aggtime timestamptz, o_aggval numeric)
AS $$
DECLARE
	v_chart_exists boolean := false;
	v_oid          integer;
	v_s_time       timestamptz := NULL;
	v_e_time       timestamptz := now();
	v_c_time       timestamptz := now();
	v_e_span       interval := NULL;
	v_e_id         integer := NULL;
	v_e_op         text;
	v_e_val        numeric;
	v_maxpoints    bigint;
	v_mcurs        refcursor;
	v_gcurs        refcursor;
	v_metric       pem.chart_metric%ROWTYPE;
	v_chart        pem.chart%ROWTYPE;
	v_pname        text;
	v_pid          int4;
	v_target       integer;
	v_applies      integer;
	v_deleted      boolean;
	v_disc_history boolean;
	v_keys         text[];
	v_key_vals     text[];
	v_m_rest_dbs   text[];
	v_rest_dbs     text[];
	v_rest_schemas text[];
	v_pos          int2 := 0;
	v_qry          text;
	v_aggqry       text[];
	v_t_str        text;
	v__params      text[];
	v__vals        text[];
	v_params       text[];
	v_vals         text[];
	v_mlbl         text := NULL;
	v_percent_unit boolean := false;
	v_ptype        text := NULL;
	v_span         interval := NULL;
	v_r_monitored  boolean := false;
	v_m_ops        text[][] = array[]::text[][];
	v_t_op         text[] := NULL;
	v_freq         interval;
	v_minfreq      interval := NULL;
	v_aggspan      interval;
	v_obj_active   boolean;
	v_obj          text;
	v_groupon      text;
	v_where        text;
	v_t_time       timestamptz := now();

	v_m_e_time     timestamptz := NULL;
	v_m_s_time     timestamptz := NULL;

	v_slope        numeric;
	v_intercept    numeric;
	v_corr         numeric;
	v_cnt          numeric;
	v_value        numeric;
	v_tmpval       numeric;

BEGIN
	-- Check if the data for the chart exists in the pem.metrices_chart
	EXECUTE 'SELECT CASE WHEN count(charts.*) > 0 THEN true ELSE false END FROM ((SELECT cid FROM pem.metrices_chart WHERE cid = $1::int4) UNION ALL (SELECT cid FROM pem.capacity_report_chart WHERE cid = $1::int4)) AS charts'
	INTO v_chart_exists USING p_cid;

	IF NOT v_chart_exists OR v_chart_exists IS NULL THEN

		o_idx := -1;
		o_label := '101';
		o_aggval := NULL;
		o_aggtime := NULL;
		RETURN NEXT;

		RETURN;
	END IF;

	IF p_sid IS NULL THEN
		v_oid = p_aid;
	ELSE
		v_oid = p_sid;
	END IF;

	EXECUTE E'
WITH chart_cfg AS (
    SELECT
        c.id AS cid,
        /*
         * Some system level charts has configuration for the historical span,
         * no of rows, and timeout saved in the pem.config table
         *
         * We will calculate the span in hours only
         * Hence, EPOCH (i.e. seconds) / 3600.
         */
        CASE
            WHEN c.type = ''L'' THEN
                COALESCE((SELECT (cfg.value || cfg.unit)::interval FROM pem.config cfg
                    WHERE cfg.param = c.rwlimit_span_param), mc.time_span)::interval
            WHEN c.type IN (''CL'', ''CT'') AND cr.type = ''E'' THEN
                ((cr.historical * 24) || '' hours'')::interval
            ELSE NULL
        END AS span,
        CASE
            WHEN c.type = ''L'' AND
                (mc.ext_id IS NULL AND mc.ext_span > ''0 hours''::interval) THEN
                mc.ext_span::interval
            WHEN c.type IN (''CL'', ''CT'') AND
                cr.type != ''E'' THEN
                ((cr.extrapolated * 24) || '' hours'')::interval
            ELSE NULL
        END AS espan,
        /*
         * maximum no of points are for line (normal/capacity report) charts
         * and no of rows for tables
         */
        CASE
            WHEN c.type = ''L'' THEN
                mc.max_points::bigint
            WHEN c.type IN (''CL'', ''CT'') THEN
                (SELECT value FROM pem.config WHERE param = ''cm_data_points_per_report'')::bigint
            ELSE NULL
        END AS points,
        CASE
            WHEN c.type IN (''CL'', ''CT'') THEN
                cr.midx
            ELSE mc.ext_id
        END AS ext_id,
        CASE
            WHEN c.type IN (''CL'', ''CT'') THEN
                cr.toperator::character varying
            ELSE mc.ext_op::character varying
        END AS ext_op,
        CASE
            WHEN c.type IN (''CL'', ''CT'') THEN
                cr.tval
            ELSE mc.ext_val
        END AS ext_val
    FROM
        pem.chart c
        LEFT JOIN (SELECT * FROM pem.metrices_chart WHERE cid = $1::integer) mc
            ON (mc.cid = c.id)
        LEFT JOIN (SELECT * FROM pem.data_chart WHERE cid = $1::integer) dc
            ON (dc.cid = c.id)
        LEFT JOIN (SELECT * FROM pem.capacity_report_chart WHERE cid = $1::integer) cr
            ON (cr.cid = c.id)
    WHERE c.id = $1::integer
),
user_cfg AS (
    SELECT
        cfg.cid,
        CASE
        WHEN cfg.did = -1 THEN
            CASE
            WHEN cfg.objid IS NULL THEN 1::integer
            WHEN $3::integer IS NOT NULL AND cfg.objid = $3::integer AND
                cfg.database IS NULL
                THEN 2::integer
            WHEN $3::integer IS NOT NULL AND cfg.objid = $3::integer AND
                $4::text IS NOT NULL AND cfg.database = $4::text AND
                cfg.schema IS NULL
                THEN 3::integer
            WHEN $3::integer IS NOT NULL AND cfg.objid = $3::integer AND
                $4::text IS NOT NULL AND cfg.database = $4::text AND
                $5::text IS NOT NULL AND cfg.schema = $5::text AND
                cfg.tbl IS NULL
                THEN 4::integer
            WHEN $3::integer IS NOT NULL AND cfg.objid = $3::integer AND
                $4::text IS NOT NULL AND cfg.database = $4::text AND
                $5::text IS NOT NULL AND cfg.schema = $5::text AND
                $6::text IS NOT NULL AND cfg.tbl = $6::text
                THEN 5::integer
            END
        ELSE
            CASE
            WHEN cfg.objid IS NULL THEN 6::integer
            WHEN $3::integer IS NOT NULL AND cfg.objid = $3::integer AND
                cfg.database IS NULL
                THEN 7::integer
            WHEN $3::integer IS NOT NULL AND cfg.objid = $3::integer AND
                $4::text IS NOT NULL AND cfg.database = $4::text AND
                cfg.schema IS NULL
                THEN 8::integer
            WHEN $3::integer IS NOT NULL AND cfg.objid = $3::integer AND
                $4::text IS NOT NULL AND cfg.database = $4::text AND
                $5::text IS NOT NULL AND cfg.schema = $5::text AND
                cfg.tbl IS NULL
                THEN 9::integer
            WHEN $3::integer IS NOT NULL AND cfg.objid = $3::integer AND
                $4::text IS NOT NULL AND cfg.database = $4::text AND
                $5::text IS NOT NULL AND cfg.schema = $5::text AND
                $6::text IS NOT NULL AND cfg.tbl = $6::text
                THEN 10::integer
            END
        END AS lvl,
        (cfg.span || '' hours'')::interval AS span, (cfg.espan || '' hours'')::interval AS espan, cfg.points::bigint
    FROM
        pem.chart_config cfg
    WHERE
        /*
         * Find the chart configuration for the specified in pem.chart_config:
         * 1. Matches for the same combination on the same did
         * 2. On any dashboard (for same configuration)
         */
        cfg.cid = $1::integer AND
        (cfg.did = -1 OR cfg.did = $2::integer) AND
        cfg.uid = (
            SELECT u.usesysid FROM pg_catalog.pg_user u
                WHERE u.usename = current_user
        )
    /*
     * we only need the highest level possible chart configuration saved by the
     * user
     */
    ORDER BY lvl DESC
    LIMIT 1
)
/*
 * Give priority to the user configuration over default configuration
 */
SELECT
    $7::timestamptz - COALESCE(x.span, c.span, ''7 days''::interval) AS stime,
    $7::timestamptz AS etime,
    COALESCE(x.span, c.span, ''7 days''::interval) AS span,
    COALESCE(x.espan, c.espan) AS espan,
    COALESCE(x.points, c.points) AS points,
    ext_id,
    ext_op,
    ext_val
FROM
    chart_cfg c LEFT OUTER JOIN user_cfg x ON (c.cid = x.cid)'
		INTO v_s_time, v_e_time, v_span, v_e_span, v_maxpoints, v_e_id, v_e_op, v_e_val
		USING p_cid, p_did, v_oid, p_db, p_schema, p_tbl, v_c_time;

	-- Couldn't fetch the time_span/max_points from the pem.metrices_chart table
	IF v_s_time IS NULL THEN
		o_idx := -1;
		o_label := '102';
		o_aggval := NULL;
		o_aggtime := NULL;
		RETURN NEXT;

		RETURN;
	END IF;

	IF p_stime IS NOT NULL AND p_etime IS NOT NULL THEN
		IF p_stime > p_etime THEN
			v_s_time := p_etime;
			v_e_time := p_stime;
		ELSE
			v_s_time := p_stime;
			v_e_time := p_etime;
		END IF;
	ELSE
		p_stime := NULL;
		p_etime := NULL;
	END IF;

	CASE
	WHEN p_level = 100 THEN
		-- On agent level dash, agent-id must exists
		IF p_aid IS NULL OR p_aid <= 0 THEN
			o_idx := -1;
			o_label := '103';
			o_aggval := NULL;
			o_aggtime := NULL;
			RETURN NEXT;

			RETURN;
		END IF;

	WHEN p_level >= 200 THEN
		-- On server level dash, server-id must exists
		IF p_sid IS NULL OR p_sid <= 0 THEN
			o_idx := -1;
			o_label := '104';
			o_aggval := NULL;
			o_aggtime := NULL;
			RETURN NEXT;

			RETURN;
		END IF;

		-- Fetch agent-id, if not provided
		IF p_aid IS NULL OR p_aid <= 0 THEN
			p_aid := NULL;

			EXECUTE 'SELECT agent_id FROM pem.agent_server_binding WHERE server_id = $1::int4' INTO p_aid USING p_sid;

			IF p_aid IS NULL THEN
				o_idx := -1;
				o_label := '105';
				o_aggval := NULL;
				o_aggtime := NULL;
				RETURN NEXT;

				RETURN;
			END IF;
		END IF;

		-- Fetch remote monitoring status of the server.
		EXECUTE 'SELECT is_remote_monitoring FROM pem.server WHERE id = $1::int4' INTO v_r_monitored USING p_sid;

		-- Fetch the restricted databases information (only for server level charts)
		IF p_level = 200 THEN
			EXECUTE '
SELECT
	pem.db_escaped_string_to_array(COALESCE(o.database_restriction, oa.database_restriction))
FROM
	pem.server s
	LEFT OUTER JOIN pg_catalog.pg_roles owner ON (owner.oid = s.owner)
	LEFT OUTER JOIN pem.server_option o ON (s.id = o.server_id AND o.pem_user = current_user)
	LEFT OUTER JOIN pem.server_option oa
		ON (o.id IS NULL AND s.id = oa.server_id AND
			(owner.rolname = oa.pem_user OR (owner.rolname IS NULL AND oa.pem_user IS NULL)))
WHERE
	s.id = $1::int4' INTO v_rest_dbs USING p_sid;
		END IF;

		IF p_level >= 300 THEN
			-- database_name is required for any charts lower than server
			-- level
			IF p_db IS NULL OR trim(p_db) = '' THEN
				o_idx := -1;
				o_label := '106';
				o_aggval := NULL;
				o_aggtime := NULL;
				RETURN NEXT;

				RETURN;
			END IF;

			-- Fetch the restricted schema information (for database level chats)
			IF p_level = 300 THEN
				EXECUTE '
SELECT
	pem.db_escaped_string_to_array(COALESCE(o.schema_restriction, oa.schema_restriction))
FROM
	pem.server s
	LEFT OUTER JOIN pg_catalog.pg_roles owner ON (owner.oid = s.owner)
	LEFT OUTER JOIN pem.database_option o ON (s.id = o.server_id AND o.pem_user = current_user AND o.database = $2::text)
	LEFT OUTER JOIN pem.database_option oa
		ON (o.id IS NULL AND s.id = oa.server_id AND oa.database = $2::text AND
			(owner.rolname = oa.pem_user OR (owner.rolname IS NULL AND oa.pem_user IS NULL)))
WHERE
	s.id = $1::int4' INTO v_rest_schemas USING p_sid, p_db;
			END IF;
		END IF;
	ELSE -- DO NOTHING
	END CASE;

	EXECUTE 'SELECT * FROM pem.chart WHERE id = $1::int4' USING p_cid INTO v_chart;

	-- Fetch all the metrices for this chart
	OPEN v_mcurs FOR EXECUTE 'SELECT * FROM pem.chart_metric WHERE cid = $1::int4' USING p_cid;
	LOOP
		FETCH v_mcurs INTO v_metric;
		EXIT WHEN NOT FOUND;

		v_pname := NULL;
		v_pid := NULL;
		v_target := NULL;
		v_applies := NULL;
		v_keys := NULL;
		v_deleted := false;
		v_disc_history := true;

		-- FETCH target_type, probe_applies_to, PRIMARY KEYS FOR THE INVOLVED
		-- PROBE-TABLE
		EXECUTE
		'SELECT p.display_name, p.id, p.target_type_id, p.applies_to_id, ARRAY(SELECT pc.internal_name FROM pem.probe_column pc WHERE pc.probe_id = p.id AND (($2::int4 = 300 AND pc.internal_name <> ''database_name'') OR ($2::int4 = 400 AND pc.internal_name NOT IN (''database_name'', ''schema_name'')) OR true) AND pc.classification = ''k'' ORDER BY pc.id) AS keys, p.deleted, p.discard_history FROM pem.probe p WHERE p.internal_name = $1::text'
		INTO v_pname, v_pid, v_target, v_applies, v_keys, v_deleted, v_disc_history USING v_metric.tbl, p_level;

		-- WE COULDN'T FIND 'probe_target_id', IT MEANS THE PROBE WITH
		-- THAT NAME DOES NOT EXISTS
		IF v_target IS NULL THEN
			IF v_e_id IS NOT NULL AND v_e_id = v_metric.mid THEN
				o_idx := -1;
				o_label := '107|' || v_metric.tbl;
				o_aggval := NULL;
				o_aggtime := NULL;
				RETURN NEXT;

				RETURN;
			END IF;

			o_idx := -1;
			o_label := '108|' || v_metric.tbl;
			o_aggval := NULL;
			o_aggtime := NULL;
			RETURN NEXT;

			CONTINUE;
		END IF;

		IF v_deleted THEN

			-- The probe has been marked for deletion
			IF v_e_id IS NOT NULL AND v_e_id = v_metric.mid THEN
				o_idx := -1;
				o_label := '107|' || COALESCE(v_pname, v_metric.tbl);
				o_aggval := NULL;
				o_aggtime := NULL;
				RETURN NEXT;

				RETURN;
			END IF;

			o_idx := -1;
			o_label := '108|' || COALESCE(v_pname, v_metric.tbl);
			o_aggval := NULL;
			o_aggtime := NULL;
			RETURN NEXT;

			CONTINUE;
		ELSIF v_disc_history THEN
			o_idx := -1;
			o_label := '109|' || COALESCE(v_pname, v_metric.tbl);
			o_aggval := NULL;
			o_aggtime := NULL;
			RETURN NEXT;

			CONTINUE;
		END IF;

		IF v_metric.params IS NOT NULL OR array_length(v_metric.params::pem.chart_metric_param[], 1) <> 0 THEN
			SELECT string_agg('pc.' || pg_catalog.quote_ident((param).name) || ' = ' || pg_catalog.quote_literal((param).value), ' AND ') FROM (SELECT unnest(v_metric.params::pem.chart_metric_param[]) AS param) p WHERE (param).name IN ('agent_id','server_id', 'database_name') INTO v_t_str;

			CASE
			WHEN ((v_metric.params::pem.chart_metric_param[])[1]).name = 'agent_id' THEN
				EXECUTE 'SELECT description, active FROM pem.agent WHERE id = $1::int4'
					USING ((v_metric.params::pem.chart_metric_param[])[1]).value
					INTO v_obj, v_obj_active;
			WHEN ((v_metric.params::pem.chart_metric_param[])[1]).name = 'server_id' THEN
				EXECUTE 'SELECT description, active FROM pem.server WHERE id = $1::int4'
					USING ((v_metric.params::pem.chart_metric_param[])[1]).value
					INTO v_obj, v_obj_active;
			ELSE
			END CASE;
			IF v_obj_active IS NULL OR v_obj_active = false THEN
				o_idx := -1;
				o_aggval := NULL;
				o_aggtime := NULL;

				-- The probe has been marked for deletion
				IF v_e_id IS NOT NULL AND v_e_id = v_metric.mid THEN
					IF ((v_metric.params::pem.chart_metric_param[])[1]).name = 'agent_id' THEN
						o_label := '112|'::text || COALESCE(v_obj, ((v_metric.params::pem.chart_metric_param[])[1]).value);
					ELSE
						o_label := '113|'::text || COALESCE(v_obj, ((v_metric.params::pem.chart_metric_param[])[1]).value);
					END IF;
					RETURN NEXT;
					RETURN;
				END IF;

				IF ((v_metric.params::pem.chart_metric_param[])[1]).name = 'agent_id' THEN
					o_label :=  '110|'::text || COALESCE(v_obj, ((v_metric.params::pem.chart_metric_param[])[1]).value);
				ELSE
					o_label :=  '111|'::text || COALESCE(v_obj, ((v_metric.params::pem.chart_metric_param[])[1]).value);
				END IF;
				RETURN NEXT;
				CONTINUE;
			END IF;

			CASE v_target
			WHEN 100 THEN
				IF array_length(v_metric.params::pem.chart_metric_param[], 1) >= 1 AND ((v_metric.params::pem.chart_metric_param[])[1]).name = 'agent_id' AND ((v_metric.params::pem.chart_metric_param[])[1]).value IS NOT NULL THEN
					EXECUTE 'SELECT COALESCE(c.execution_frequency, p.default_execution_frequency) AS freq FROM pem.probe p LEFT JOIN pem.probe_config_agent c ON (p.id = c.probe_id AND c.agent_id = $2::integer) WHERE p.id = $1::integer' USING v_pid, (((v_metric.params::pem.chart_metric_param[])[1]).value)::integer INTO v_freq;
				ELSE
					EXECUTE 'SELECT p.default_execution_frequency AS freq FROM pem.probe p WHERE p.id = $1::integer' USING v_pid INTO v_freq;
				END IF;
			WHEN 200 THEN
				IF array_length(v_metric.params::pem.chart_metric_param[], 1) >= 1 AND ((v_metric.params::pem.chart_metric_param[])[1]).name = 'server_id' AND ((v_metric.params::pem.chart_metric_param[])[1]).value IS NOT NULL THEN
					EXECUTE 'SELECT COALESCE(c.execution_frequency, p.default_execution_frequency) AS freq FROM pem.probe p LEFT JOIN pem.probe_config_server c ON (p.id = c.probe_id AND c.server_id = $2::integer) WHERE p.id = $1::integer' USING v_pid, (((v_metric.params::pem.chart_metric_param[])[1]).value)::integer INTO v_freq;
				ELSE
					EXECUTE 'SELECT p.default_execution_frequency AS freq FROM pem.probe p WHERE p.id = $1::integer' USING v_pid INTO v_freq;
				END IF;
			WHEN 300 THEN
				IF array_length(v_metric.params::pem.chart_metric_param[], 1) >= 2 AND ((v_metric.params::pem.chart_metric_param[])[1]).name = 'server_id' AND ((v_metric.params::pem.chart_metric_param[])[1]).value IS NOT NULL AND
					((v_metric.params::pem.chart_metric_param[])[2]).name = 'database_name' AND ((v_metric.params::pem.chart_metric_param[])[2]).value IS NOT NULL THEN
					EXECUTE 'SELECT COALESCE(c.execution_frequency, p.default_execution_frequency) AS freq FROM pem.probe p LEFT JOIN pem.probe_config_database c ON (p.id = c.probe_id AND c.server_id = $2::integer AND c.database_name = $3::text) WHERE p.id = $1::integer' USING v_pid, (((v_metric.params::pem.chart_metric_param[])[1]).value)::integer, (((v_metric.params::pem.chart_metric_param[])[2]).value)::text INTO v_freq;
				ELSE
					EXECUTE 'SELECT p.default_execution_frequency AS freq FROM pem.probe p WHERE p.id = $1::integer' USING v_pid INTO v_freq;
				END IF;
			WHEN 400 THEN
				IF array_length(v_metric.params::pem.chart_metric_param[], 1) >= 3 AND ((v_metric.params::pem.chart_metric_param[])[1]).name = 'server_id' AND ((v_metric.params::pem.chart_metric_param[])[1]).value IS NOT NULL AND
					((v_metric.params::pem.chart_metric_param[])[2]).name = 'database_name' AND ((v_metric.params::pem.chart_metric_param[])[2]).value IS NOT NULL AND
					((v_metric.params::pem.chart_metric_param[])[3]).name = 'schema_name' AND ((v_metric.params::pem.chart_metric_param[])[3]).value IS NOT NULL THEN
					EXECUTE 'SELECT COALESCE(c.execution_frequency, p.default_execution_frequency) AS freq FROM pem.probe p LEFT JOIN pem.probe_config_schema c ON (p.id = c.probe_id AND c.server_id = $2::integer AND c.database_name = $3::text AND c.schema_name = $4::text) WHERE p.id = $1::integer' USING v_pid, (((v_metric.params::pem.chart_metric_param[])[1]).value)::integer, (((v_metric.params::pem.chart_metric_param[])[2]).value)::text, (((v_metric.params::pem.chart_metric_param[])[3]).value)::text INTO v_freq;
				ELSE
					EXECUTE 'SELECT p.default_execution_frequency AS freq FROM pem.probe p WHERE p.id = $1::integer' USING v_pid INTO v_freq;
				END IF;
			WHEN 500 THEN
				IF array_length(v_metric.params::pem.chart_metric_param[], 1) >= 4 AND ((v_metric.params::pem.chart_metric_param[])[1]).name = 'server_id' AND ((v_metric.params::pem.chart_metric_param[])[1]).value IS NOT NULL AND
					((v_metric.params::pem.chart_metric_param[])[2]).name = 'database_name' AND ((v_metric.params::pem.chart_metric_param[])[2]).value IS NOT NULL AND
					((v_metric.params::pem.chart_metric_param[])[3]).name = 'schema_name' AND ((v_metric.params::pem.chart_metric_param[])[3]).value IS NOT NULL AND
					((v_metric.params::pem.chart_metric_param[])[4]).name = 'table_name' AND ((v_metric.params::pem.chart_metric_param[])[4]).value IS NOT NULL THEN
					EXECUTE 'SELECT COALESCE(c.execution_frequency, p.default_execution_frequency) AS freq FROM pem.probe p LEFT JOIN pem.probe_config_table c ON (p.id = c.probe_id AND c.server_id = $2::integer AND c.database_name = $3::text AND c.schema_name = $4::text AND c.table_name = $5::text) WHERE p.id = $1::integer' USING v_pid, (((v_metric.params::pem.chart_metric_param[])[1]).value)::integer, (((v_metric.params::pem.chart_metric_param[])[2]).value)::text, (((v_metric.params::pem.chart_metric_param[])[3]).value)::text, (((v_metric.params::pem.chart_metric_param[])[4]).value)::text INTO v_freq;
				ELSE
					EXECUTE 'SELECT p.default_execution_frequency AS freq FROM pem.probe p WHERE p.id = $1::integer' USING v_pid INTO v_freq;
				END IF;
			WHEN 600 THEN
				IF array_length(v_metric.params::pem.chart_metric_param[], 1) >= 4 AND ((v_metric.params::pem.chart_metric_param[])[1]).name = 'server_id' AND ((v_metric.params::pem.chart_metric_param[])[1]).value IS NOT NULL AND
					((v_metric.params::pem.chart_metric_param[])[2]).name = 'database_name' AND ((v_metric.params::pem.chart_metric_param[])[2]).value IS NOT NULL AND
					((v_metric.params::pem.chart_metric_param[])[3]).name = 'schema_name' AND ((v_metric.params::pem.chart_metric_param[])[3]).value IS NOT NULL AND
					((v_metric.params::pem.chart_metric_param[])[4]).name = 'index_name' AND ((v_metric.params::pem.chart_metric_param[])[4]).value IS NOT NULL THEN
					EXECUTE 'SELECT COALESCE(c.execution_frequency, p.default_execution_frequency) AS freq FROM pem.probe p LEFT JOIN pem.probe_config_table c ON (p.id = c.probe_id AND c.server_id = $2::integer AND c.database_name = $3::text AND c.schema_name = $4::text AND c.index_name = $5::text) WHERE p.id = $1::integer' USING v_pid, (((v_metric.params::pem.chart_metric_param[])[1]).value)::integer, (((v_metric.params::pem.chart_metric_param[])[2]).value)::text, (((v_metric.params::pem.chart_metric_param[])[3]).value)::text, (((v_metric.params::pem.chart_metric_param[])[4]).value)::text INTO v_freq;
				ELSE
					EXECUTE 'SELECT p.default_execution_frequency AS freq FROM pem.probe p WHERE p.id = $1::integer' USING v_pid INTO v_freq;
				END IF;
			WHEN 700 THEN
				IF array_length(v_metric.params::pem.chart_metric_param[], 1) >= 4 AND ((v_metric.params::pem.chart_metric_param[])[1]).name = 'server_id' AND ((v_metric.params::pem.chart_metric_param[])[1]).value IS NOT NULL AND
					((v_metric.params::pem.chart_metric_param[])[2]).name = 'database_name' AND ((v_metric.params::pem.chart_metric_param[])[2]).value IS NOT NULL AND
					((v_metric.params::pem.chart_metric_param[])[3]).name = 'schema_name' AND ((v_metric.params::pem.chart_metric_param[])[3]).value IS NOT NULL AND
					((v_metric.params::pem.chart_metric_param[])[4]).name = 'sequence_name' AND ((v_metric.params::pem.chart_metric_param[])[4]).value IS NOT NULL THEN
					EXECUTE 'SELECT COALESCE(c.execution_frequency, p.default_execution_frequency) AS freq FROM pem.probe p LEFT JOIN pem.probe_config_table c ON (p.id = c.probe_id AND c.server_id = $2::integer AND c.database_name = $3::text AND c.schema_name = $4::text AND c.sequence_name = $5::text) WHERE p.id = $1::integer' USING v_pid, (((v_metric.params::pem.chart_metric_param[])[1]).value)::integer, (((v_metric.params::pem.chart_metric_param[])[2]).value)::text, (((v_metric.params::pem.chart_metric_param[])[3]).value)::text, (((v_metric.params::pem.chart_metric_param[])[4]).value)::text INTO v_freq;
				ELSE
					EXECUTE 'SELECT p.default_execution_frequency AS freq FROM pem.probe p WHERE p.id = $1::integer' USING v_pid INTO v_freq;
				END IF;
			WHEN 800 THEN
				IF array_length(v_metric.params::pem.chart_metric_param[], 1) >= 4 AND ((v_metric.params::pem.chart_metric_param[])[1]).name = 'server_id' AND ((v_metric.params::pem.chart_metric_param[])[1]).value IS NOT NULL AND
					((v_metric.params::pem.chart_metric_param[])[2]).name = 'database_name' AND ((v_metric.params::pem.chart_metric_param[])[2]).value IS NOT NULL AND
					((v_metric.params::pem.chart_metric_param[])[3]).name = 'schema_name' AND ((v_metric.params::pem.chart_metric_param[])[3]).value IS NOT NULL AND
					((v_metric.params::pem.chart_metric_param[])[4]).name = 'function_name' AND ((v_metric.params::pem.chart_metric_param[])[4]).value IS NOT NULL THEN
					EXECUTE 'SELECT COALESCE(c.execution_frequency, p.default_execution_frequency) AS freq FROM pem.probe p LEFT JOIN pem.probe_config_table c ON (p.id = c.probe_id AND c.server_id = $2::integer AND c.database_name = $3::text AND c.schema_name = $4::text AND c.function_name = $5::text) WHERE p.id = $1::integer' USING v_pid, (((v_metric.params::pem.chart_metric_param[])[1]).value)::integer, (((v_metric.params::pem.chart_metric_param[])[2]).value)::text, (((v_metric.params::pem.chart_metric_param[])[3]).value)::text, (((v_metric.params::pem.chart_metric_param[])[4]).value)::text INTO v_freq;
				ELSE
					EXECUTE 'SELECT p.default_execution_frequency AS freq FROM pem.probe p WHERE p.id = $1::integer' USING v_pid INTO v_freq;
				END IF;
			WHEN 900 THEN
				IF array_length(v_metric.params::pem.chart_metric_param[], 1) >= 4 AND ((v_metric.params::pem.chart_metric_param[])[1]).name = 'server_id' AND ((v_metric.params::pem.chart_metric_param[])[1]).value IS NOT NULL AND
					((v_metric.params::pem.chart_metric_param[])[2]).name = 'database_name' AND ((v_metric.params::pem.chart_metric_param[])[2]).value IS NOT NULL AND
					((v_metric.params::pem.chart_metric_param[])[3]).name = 'schema_name' AND ((v_metric.params::pem.chart_metric_param[])[3]).value IS NOT NULL AND
					((v_metric.params::pem.chart_metric_param[])[4]).name = 'view_name' AND ((v_metric.params::pem.chart_metric_param[])[4]).value IS NOT NULL THEN
					EXECUTE 'SELECT COALESCE(c.execution_frequency, p.default_execution_frequency) AS freq FROM pem.probe p LEFT JOIN pem.probe_config_table c ON (p.id = c.probe_id AND c.server_id = $2::integer AND c.database_name = $3::text AND c.schema_name = $4::text AND c.view_name = $5::text) WHERE p.id = $1::integer' USING v_pid, (((v_metric.params::pem.chart_metric_param[])[1]).value)::integer, (((v_metric.params::pem.chart_metric_param[])[2]).value)::text, (((v_metric.params::pem.chart_metric_param[])[3]).value)::text, (((v_metric.params::pem.chart_metric_param[])[4]).value)::text INTO v_freq;
				ELSE
					EXECUTE 'SELECT p.default_execution_frequency AS freq FROM pem.probe p WHERE p.id = $1::integer' USING v_pid INTO v_freq;
				END IF;
			ELSE
				EXECUTE 'SELECT p.default_execution_frequency AS freq FROM pem.probe p WHERE p.id = $1::integer' USING v_pid INTO v_freq;
			END CASE;
			IF v_minfreq IS NULL THEN
				v_minfreq := v_freq;
			ELSIF v_minfreq > v_freq THEN
				v_minfreq := v_freq;
			END IF;
			v_pos := v_pos + 1;

			SELECT string_agg(CASE WHEN (param).name = 'agent_id' THEN (SELECT description FROM pem.agent WHERE id = (param).value::int4) WHEN (param).name = 'server_id' THEN (SELECT description FROM pem.server WHERE id = (param).value::int4) ELSE (param).value END, '/'), string_agg(pg_catalog.quote_ident((param).name) || ' = ' || pg_catalog.quote_literal((param).value), ' AND '), string_agg(pg_catalog.quote_ident((param).name), ', ') FROM (SELECT unnest(v_metric.params::pem.chart_metric_param[]) AS param) p INTO v_t_str, v_where, v_groupon;

			EXECUTE E'
SELECT
	(CASE WHEN NOT pit_by_default THEN display_name || ''+'' ELSE display_name END), unit_of_value = ''%''::text
FROM pem.probe_column
WHERE probe_id = $1::int4 AND internal_name = $2::text AND is_graphable
UNION ALL
SELECT
	display_name, unit_of_value = ''%''::text
FROM pem.probe_column
WHERE probe_id = $1::int4 AND (internal_name || ''_pit'') = $2::text AND is_graphable AND NOT pit_by_default AND calculate_pit'
				USING v_pid, v_metric.metrices[1] INTO v_mlbl, v_percent_unit;
			v_mlbl := v_mlbl || ' [' || v_t_str || ']';

			EXECUTE 'SELECT min(t) FROM ((SELECT min(recorded_time) t FROM pemhistory.' || pg_catalog.quote_ident(v_metric.tbl) || ' WHERE ' || v_where || ' AND recorded_time >= $1::timestamptz) UNION ALL (SELECT max(recorded_time) t FROM pemhistory.' || pg_catalog.quote_ident(v_metric.tbl) || ' WHERE ' || v_where || ' AND recorded_time <= $1::timestamptz)) a' USING v_s_time INTO v_m_s_time;
			IF v_m_s_time < v_t_time THEN
				v_t_time := v_m_s_time;
			END IF;

			-- pos, label, probe_tbl, probe_col, agg, condition, groupon, percentage_unit, freq, min_time
			IF v_e_id IS NOT NULL AND v_e_id = v_metric.mid THEN
				v_t_op := ARRAY[v_pos::text, v_mlbl, v_metric.tbl, v_metric.metrices[1]::text, v_metric.agg_func[1]::text, v_where, v_groupon, v_percent_unit::text, v_freq::text, v_m_s_time::text];
			ELSE
				v_m_ops := v_m_ops || ARRAY[ARRAY[v_pos::text, v_mlbl, v_metric.tbl, v_metric.metrices[1]::text, v_metric.agg_func[1]::text, v_where, v_groupon, v_percent_unit::text, v_freq::text, v_m_s_time::text]];
			END IF;
		ELSE

			-- If server is remotely monitored then we will not render agent level metrics
			IF v_r_monitored AND v_target = 100 THEN
				o_idx := -1;
				o_aggval := NULL;
				o_aggtime := NULL;
				o_label :=  '114'::text;
				RETURN NEXT;

				CONTINUE;
			END IF;

			-- We need to find out, if this metric actually generates multiple
			-- sub-metrices (because they may have other primary keys too)
			IF p_level > 0 AND v_keys IS NOT NULL AND array_length(v_keys, 1) <> 0 THEN

				v_qry := 'SELECT ARRAY[';

				SELECT string_agg('tbl.' || pg_catalog.quote_ident(v_keys[a]), '::text, ')
					FROM generate_series(array_lower(v_keys,1), array_upper(v_keys,1)) a INTO v_t_str;
				v_qry := v_qry || v_t_str || '::text]::text[] FROM pemdata.' || pg_catalog.quote_ident(v_metric.tbl) || ' tbl';

				v_m_rest_dbs = NULL;
				CASE WHEN v_applies = 100 THEN
						v_qry := v_qry || ' WHERE tbl.agent_id = ' || p_aid::text || '::integer';
						v__params := ARRAY['agent_id'];
						v__vals := ARRAY[p_aid::text];

					WHEN v_target = 200 THEN
						v_qry := v_qry || ' WHERE tbl.server_id = ' || p_sid::text || '::integer';
						v__params := ARRAY['server_id'];
						v__vals := ARRAY[p_sid::text]::text[];
						IF v_applies >= 300 AND p_level >= 300 THEN
							-- Restricted DBs are availabe that doesn't mean - they're applicable
							-- for this metric
							--
							-- Thye're applicable only if probe can applies to database level and
							-- current dashboard is for server-level
							IF array_length(v_rest_dbs, 1) <> 0 THEN
								v_m_rest_dbs = v_rest_dbs;
							ELSE
								v_m_rest_dbs := NULL;
							END IF;

							v_qry := v_qry || ' AND tbl.database_name = ' || pg_catalog.quote_literal(p_db::text) || '::text';
							v__params := ARRAY['server_id', 'database_name'];
							v__vals := ARRAY[p_sid::text, p_db];
						END IF;
						IF v_applies >= 400 AND p_level = 400 THEN
							v__params := ARRAY['server_id', 'database_name', 'schema_name'];
							v__vals := ARRAY[p_sid::text, p_db, p_schema];
							v_qry := v_qry || ' AND tbl.schema_name = ' || pg_catalog.quote_literal(p_schema::text) || '::text';
						END IF;
						IF NOT p_sysobjs THEN
							IF v_applies = 300 THEN
								v_qry := v_qry || ' AND CASE WHEN database_name != '''' THEN database_name != ''template0'' AND database_name != ''template1'' ELSE TRUE END';
							ELSIF v_applies > 300 THEN
								v_qry := v_qry || E' AND CASE WHEN database_name != '''' THEN database_name != ''template0'' AND database_name != ''template1'' AND schema_name NOT IN (''pg_catalog'', ''sys'', ''information_schema'') AND schema_name NOT LIKE ''pg_toast%'' AND schema_name NOT LIKE ''pg_temp%'' ELSE TRUE END';

								v_qry := v_qry || ' AND CASE WHEN database_name != '''' THEN database_name != ''template0'' AND database_name != ''template1'' ELSE TRUE END';
							END IF;
						END IF;
						IF v_applies = 300 THEN
							IF v_rest_dbs IS NOT NULL AND array_length(v_rest_dbs, 1) > 0 THEN
								v_qry := v_qry || ' AND database_name = ANY(' || pg_catalog.quote_literal(v_rest_dbs::text) || ')';
							END IF;
						ELSIF v_applies > 300 THEN
							IF v_rest_dbs IS NOT NULL AND array_length(v_rest_dbs, 1) > 0 THEN
								v_qry := v_qry || ' AND database_name = ANY(' || pg_catalog.quote_literal(v_rest_dbs::text) || ') AND schema_name = ANY(
	SELECT
		COALESCE(o.schema_restriction, oa.schema_restriction)
	FROM
		pem.server s
		LEFT OUTER JOIN pg_catalog.pg_roles owner ON (owner.oid = s.owner)
		LEFT OUTER JOIN pem.database_option o ON (s.id = o.server_id AND o.pem_user = current_user AND o.database = tbl.database_name)
		LEFT OUTER JOIN pem.database_option oa
			ON (o.id IS NULL AND s.id = oa.server_id AND oa.database = tbl.database_name AND
				(owner.rolname = oa.pem_user OR (owner.rolname IS NULL AND oa.pem_user IS NULL)))
	WHERE
		s.id = tbl.server_id)';
							END IF;
							IF p_level = 400 THEN
								v_qry := v_qry || ' AND schema_name = ' || pg_catalog.quote_literal(p_schema::text) || '::text';
							END IF;
						END IF;
					WHEN v_target = 300 THEN
						v_qry := v_qry || ' WHERE tbl.server_id = ' || p_sid::text || '::integer AND tbl.database_name = ' || pg_catalog.quote_literal(p_db::text) || '::text';
						v__params := ARRAY['server_id', 'database_name'];
						v__vals := ARRAY[p_sid::text, p_db]::text[];

						IF array_length(v_rest_dbs, 1) <> 0 THEN
							v_m_rest_dbs = v_rest_dbs;
						ELSE
							v_m_rest_dbs := NULL;
						END IF;
						IF v_applies > 300  THEN
							IF p_level > 300 THEN
								v__params := ARRAY['server_id', 'database_name', 'schema_name'];
								v__vals := ARRAY[p_sid::text, p_db, p_schema];
							END IF;
							IF NOT p_sysobjs THEN
								v_qry := v_qry || E' AND (schema_name NOT IN (''pg_catalog'', ''sys'', ''information_schema'') AND schema_name NOT LIKE ''pg_toast%'' AND schema_name NOT LIKE ''pg_temp%'')';
							END IF;
							IF v_rest_schemas IS NOT NULL AND array_length(v_rest_schemas, 1) > 0 THEN
								v_qry := v_qry || ' AND schema_name = ANY(' || pg_catalog.quote_literal(v_rest_schemas::text) || ')';
							END IF;
						END IF;
					WHEN v_target = 400 THEN
						v__params := ARRAY['server_id', 'database_name', 'schema_name'];
						v__vals := ARRAY[p_sid::text, p_db, p_schema];
						v_qry := v_qry || ' WHERE tbl.server_id = ' || p_sid::text || '::integer AND tbl.database_name = ' || pg_catalog.quote_literal(p_db::text) || '::text AND tbl.schema_name = ' || pg_catalog.quote_literal(schema::text) || '::text';
					ELSE
						v_qry := v_qry;
				END CASE;

				IF v_metric.gorderby IS NOT NULL AND array_length(v_metric.gorderby, 1) >0 THEN
					SELECT string_agg('tbl.' || pg_catalog.quote_ident(v_metric.gorderby[i]) || CASE WHEN v_metric.gorderdir IS NOT NULL AND array_length(v_metric.gorderdir, 1) >= i AND v_metric.gorderdir[i] = 'D' THEN ' DESC' ELSE ' ASC' END, ', ')
						FROM generate_series(array_lower(v_metric.gorderby,1), array_upper(v_metric.gorderby,1)) i INTO v_t_str;
					v_qry := v_qry || ' ORDER BY ' || v_t_str;
				END IF;
				IF (v_metric.glimit IS NOT NULL AND v_metric.glimit > 0) THEN
					v_qry := v_qry || ' LIMIT ' || v_metric.glimit::text;
				ELSE
					v_qry := v_qry || ' LIMIT 32';
				END IF;

				IF v_metric.glimit IS NULL OR v_metric.glimit <> 0 THEN
					OPEN v_gcurs FOR EXECUTE v_qry;
					LOOP
						FETCH v_gcurs INTO v_key_vals;
						EXIT WHEN NOT FOUND;
						v_params := v__params;
						v_vals := v__vals;

						FOR a IN array_lower(v_key_vals, 1) .. array_upper(v_key_vals, 1)
						LOOP
							v_params := v_params || v_keys[a]::text;
							v_vals := v_vals || v_key_vals[a]::text;
						END LOOP;

						v_freq := NULL;
						CASE v_target
						WHEN 100 THEN
							IF array_length(v_params, 1) >= 1 AND v_params[1] = 'agent_id' AND v_vals[1] IS NOT NULL THEN
								EXECUTE 'SELECT COALESCE(c.execution_frequency, p.default_execution_frequency) AS freq FROM pem.probe p LEFT JOIN pem.probe_config_agent c ON (p.id = c.probe_id AND c.agent_id = $2::integer) WHERE p.id = $1::integer' USING v_pid, (v_vals[1])::integer INTO v_freq;
							END IF;
						WHEN 200 THEN
							IF array_length(v_params, 1) >= 1 AND v_params[1] = 'server_id' AND v_vals[1] IS NOT NULL THEN
								EXECUTE 'SELECT COALESCE(c.execution_frequency, p.default_execution_frequency) AS freq FROM pem.probe p LEFT JOIN pem.probe_config_server c ON (p.id = c.probe_id AND c.server_id = $2::integer) WHERE p.id = $1::integer' USING v_pid, (v_vals[1])::integer INTO v_freq;
							END IF;
						WHEN 300 THEN
							IF array_length(v_params, 1) >= 2 AND v_params[1] = 'server_id' AND v_vals[1] IS NOT NULL AND
								((v_params)[2]).name = 'database_name' AND v_vals[2] IS NOT NULL THEN
								EXECUTE 'SELECT COALESCE(c.execution_frequency, p.default_execution_frequency) AS freq FROM pem.probe p LEFT JOIN pem.probe_config_database c ON (p.id = c.probe_id AND c.server_id = $2::integer AND c.database_name = $3::text) WHERE p.id = $1::integer' USING v_pid, (v_vals[1])::integer, (v_vals[2])::text INTO v_freq;
							END IF;
						WHEN 400 THEN
							IF array_length(v_params, 1) >= 3 AND v_params[1] = 'server_id' AND v_vals[1] IS NOT NULL AND
								((v_params)[2]).name = 'database_name' AND v_vals[2] IS NOT NULL AND
								((v_params)[3]).name = 'schema_name' AND v_vals[3] IS NOT NULL THEN
								EXECUTE 'SELECT COALESCE(c.execution_frequency, p.default_execution_frequency) AS freq FROM pem.probe p LEFT JOIN pem.probe_config_schema c ON (p.id = c.probe_id AND c.server_id = $2::integer AND c.database_name = $3::text AND c.schema_name = $4::text) WHERE p.id = $1::integer' USING v_pid, (v_vals[1])::integer, (v_vals[2])::text, (v_vals[3])::text INTO v_freq;
							END IF;
						WHEN 500 THEN
							IF array_length(v_params, 1) >= 4 AND v_params[1] = 'server_id' AND v_vals[1] IS NOT NULL AND
								((v_params)[2]).name = 'database_name' AND v_vals[2] IS NOT NULL AND
								((v_params)[3]).name = 'schema_name' AND v_vals[3] IS NOT NULL AND
								((v_params)[4]).name = 'table_name' AND v_vals[4] IS NOT NULL THEN
								EXECUTE 'SELECT COALESCE(c.execution_frequency, p.default_execution_frequency) AS freq FROM pem.probe p LEFT JOIN pem.probe_config_table c ON (p.id = c.probe_id AND c.server_id = $2::integer AND c.database_name = $3::text AND c.schema_name = $4::text AND c.table_name = $5::text) WHERE p.id = $1::integer' USING v_pid, (v_vals[1])::integer, (v_vals[2])::text, (v_vals[3])::text, (v_vals[4])::text INTO v_freq;
							END IF;
						WHEN 600 THEN
							IF array_length(v_params, 1) >= 4 AND v_params[1] = 'server_id' AND v_vals[1] IS NOT NULL AND
								((v_params)[2]).name = 'database_name' AND v_vals[2] IS NOT NULL AND
								((v_params)[3]).name = 'schema_name' AND v_vals[3] IS NOT NULL AND
								((v_params)[4]).name = 'index_name' AND v_vals[4] IS NOT NULL THEN
								EXECUTE 'SELECT COALESCE(c.execution_frequency, p.default_execution_frequency) AS freq FROM pem.probe p LEFT JOIN pem.probe_config_index c ON (p.id = c.probe_id AND c.server_id = $2::integer AND c.database_name = $3::text AND c.schema_name = $4::text AND c.index_name = $5::text) WHERE p.id = $1::integer' USING v_pid, (v_vals[1])::integer, (v_vals[2])::text, (v_vals[3])::text, (v_vals[4])::text INTO v_freq;
							END IF;
						WHEN 700 THEN
							IF array_length(v_params, 1) >= 4 AND v_params[1] = 'server_id' AND v_vals[1] IS NOT NULL AND
								((v_params)[2]).name = 'database_name' AND v_vals[2] IS NOT NULL AND
								((v_params)[3]).name = 'schema_name' AND v_vals[3] IS NOT NULL AND
								((v_params)[4]).name = 'sequence_name' AND v_vals[4] IS NOT NULL THEN
								EXECUTE 'SELECT COALESCE(c.execution_frequency, p.default_execution_frequency) AS freq FROM pem.probe p LEFT JOIN pem.probe_config_sequence  c ON (p.id = c.probe_id AND c.server_id = $2::integer AND c.database_name = $3::text AND c.schema_name = $4::text AND c.sequence_name = $5::text) WHERE p.id = $1::integer' USING v_pid, (v_vals[1])::integer, (v_vals[2])::text, (v_vals[3])::text, (v_vals[4])::text INTO v_freq;
							END IF;
						WHEN 800 THEN
							IF array_length(v_params, 1) >= 4 AND v_params[1] = 'server_id' AND v_vals[1] IS NOT NULL AND
								((v_params)[2]).name = 'database_name' AND v_vals[2] IS NOT NULL AND
								((v_params)[3]).name = 'schema_name' AND v_vals[3] IS NOT NULL AND
								((v_params)[4]).name = 'function_name' AND v_vals[4] IS NOT NULL THEN
								EXECUTE 'SELECT COALESCE(c.execution_frequency, p.default_execution_frequency) AS freq FROM pem.probe p LEFT JOIN pem.probe_config_function c ON (p.id = c.probe_id AND c.server_id = $2::integer AND c.database_name = $3::text AND c.schema_name = $4::text AND c.function_name = $5::text) WHERE p.id = $1::integer' USING v_pid, (v_vals[1])::integer, (v_vals[2])::text, (v_vals[3])::text, (v_vals[4])::text INTO v_freq;
							END IF;
						WHEN 900 THEN
							IF array_length(v_params, 1) >= 4 AND v_params[1] = 'server_id' AND v_vals[1] IS NOT NULL AND
								((v_params)[2]).name = 'database_name' AND v_vals[2] IS NOT NULL AND
								((v_params)[3]).name = 'schema_name' AND v_vals[3] IS NOT NULL AND
								((v_params)[4]).name = 'view_name' AND v_vals[4] IS NOT NULL THEN
								EXECUTE 'SELECT COALESCE(c.execution_frequency, p.default_execution_frequency) AS freq FROM pem.probe p LEFT JOIN pem.probe_config_view c ON (p.id = c.probe_id AND c.server_id = $2::integer AND c.database_name = $3::text AND c.schema_name = $4::text AND c.view_name = $5::text) WHERE p.id = $1::integer' USING v_pid, (v_vals[1])::integer, (v_vals[2])::text, (v_vals[3])::text, (v_vals[4])::text INTO v_freq;
							END IF;
						END CASE;
						IF v_freq IS NULL THEN
							EXECUTE 'SELECT p.default_execution_frequency AS freq FROM pem.probe p WHERE p.id = $1::integer' USING v_pid INTO v_freq;
						END IF;
						IF v_minfreq IS NULL THEN
							v_minfreq := v_freq;
						ELSIF v_minfreq > v_freq THEN
							v_minfreq := v_freq;
						END IF;

						FOR m_idx IN array_lower(v_metric.metrices, 1) .. array_upper(v_metric.metrices, 1)
							LOOP
								v_pos := v_pos + 1;
								SELECT string_agg(v_key_vals[b], ', ')
								FROM generate_series(array_lower(v_key_vals,1), array_upper(v_key_vals,1)) b INTO o_label;
								EXECUTE E'
		SELECT
			(CASE WHEN NOT pit_by_default THEN display_name || ''+'' ELSE display_name END), sql_data_type, unit_of_value = ''%''::text
		FROM pem.probe_column
		WHERE probe_id = $1::int4 AND internal_name = $2::text AND is_graphable
		UNION ALL
		SELECT
			display_name, sql_data_type, unit_of_value = ''%''::text
		FROM pem.probe_column
		WHERE probe_id = $1::int4 AND (internal_name || ''_pit'') = $2::text AND is_graphable AND NOT pit_by_default AND calculate_pit'
							USING v_pid, v_metric.metrices[m_idx] INTO v_mlbl, v_ptype, v_percent_unit;

							IF v_chart.labels IS NOT NULL AND array_length(v_chart.labels, 1) >= v_pos AND v_chart.labels[v_pos] IS NOT NULL THEN
								o_label := v_chart.labels[v_pos] || ' - ' || o_label;
							ELSE
								IF v_mlbl IS NOT NULL THEN
									o_label := v_mlbl || ' - ' || o_label;
								END IF;
							END IF;
							IF v_metric.agg_func IS NOT NULL AND array_length(v_metric.agg_func, 1) >= m_idx AND v_metric.agg_func[m_idx] IS NOT NULL THEN
								v_t_str := v_metric.agg_func[m_idx];
							END IF;

							SELECT string_agg(pg_catalog.quote_ident(v_params[idx]) || ' = ' || pg_catalog.quote_literal(v_vals[idx]), ' AND '), string_agg(pg_catalog.quote_ident(v_params[idx]), ', ') FROM generate_series(array_lower(v_params,1), array_upper(v_params,1)) idx INTO v_where, v_groupon;
							EXECUTE 'SELECT min(t) FROM ((SELECT min(recorded_time) t FROM pemhistory.' || pg_catalog.quote_ident(v_metric.tbl) || ' WHERE ' || v_where || ' AND recorded_time >= $1::timestamptz) UNION ALL (SELECT max(recorded_time) t FROM pemhistory.' || pg_catalog.quote_ident(v_metric.tbl) || ' WHERE ' || v_where || ' AND recorded_time <= $1::timestamptz)) a' USING v_s_time INTO v_m_s_time;
							IF v_m_s_time < v_t_time THEN
								v_t_time := v_m_s_time;
							END IF;

							-- pos, label, probe_tbl, probe_col, agg, condition, groupon, percentage_unit, freq, min_time
							IF v_e_id IS NOT NULL AND v_e_id = v_metric.mid THEN
								v_t_op := ARRAY[v_pos::text, o_label, v_metric.tbl, v_metric.metrices[m_idx]::text, v_t_str, v_where, v_groupon, v_percent_unit::text, v_freq::text, v_m_s_time::text];
							ELSE
								v_m_ops := v_m_ops || ARRAY[ARRAY[v_pos::text, o_label, v_metric.tbl, v_metric.metrices[m_idx]::text, v_t_str, v_where, v_groupon, v_percent_unit::text, v_freq::text, v_m_s_time::text]];
							END IF;
						END LOOP;
					END LOOP;
					CLOSE v_gcurs;
				ELSE
					FOR m_idx IN array_lower(v_metric.metrices, 1) .. array_upper(v_metric.metrices, 1)
					LOOP
						v_pos := v_pos + 1;
						EXECUTE E'
	SELECT
		(CASE WHEN NOT pit_by_default THEN display_name || ''+'' ELSE display_name END), unit_of_value = ''%''::text
	FROM pem.probe_column
	WHERE probe_id = $1::int4 AND internal_name = $2::text AND is_graphable
	UNION ALL
	SELECT
		display_name, unit_of_value = ''%''::text
	FROM pem.probe_column
	WHERE probe_id = $1::int4 AND (internal_name || ''_pit'') = $2::text AND is_graphable AND NOT pit_by_default AND calculate_pit'
	USING v_pid, v_metric.metrices[m_idx] INTO v_mlbl, v_percent_unit;

						IF v_chart.labels IS NOT NULL AND array_length(v_chart.labels, 1) >= v_pos AND v_chart.labels[v_pos] IS NOT NULL THEN
							o_label := v_chart.labels[v_pos];
						ELSE
							IF v_mlbl IS NOT NULL THEN
								o_label := v_mlbl;
							END IF;
						END IF;

						IF v_metric.agg_func IS NOT NULL AND array_length(v_metric.agg_func, 1) >= m_idx AND v_metric.agg_func[m_idx] IS NOT NULL THEN
							v_t_str := v_metric.agg_func[m_idx];
						END IF;

						v_freq := NULL;
						CASE v_target
						WHEN 100 THEN
							IF array_length(v__params, 1) >= 1 AND v__params[1] = 'agent_id' AND v__vals[1] IS NOT NULL THEN
								EXECUTE 'SELECT COALESCE(c.execution_frequency, p.default_execution_frequency) AS freq FROM pem.probe p LEFT JOIN pem.probe_config_agent c ON (p.id = c.probe_id AND c.agent_id = $2::integer) WHERE p.id = $1::integer' USING v_pid, (v__vals[1])::integer INTO v_freq;
							END IF;
						WHEN 200 THEN
							IF array_length(v__params, 1) >= 1 AND v__params[1] = 'server_id' AND v__vals[1] IS NOT NULL THEN
								EXECUTE 'SELECT COALESCE(c.execution_frequency, p.default_execution_frequency) AS freq FROM pem.probe p LEFT JOIN pem.probe_config_server c ON (p.id = c.probe_id AND c.server_id = $2::integer) WHERE p.id = $1::integer' USING v_pid, (v__vals[1])::integer INTO v_freq;
							END IF;
						WHEN 300 THEN
							IF array_length(v__params, 1) >= 2 AND v__params[1] = 'server_id' AND v__vals[1] IS NOT NULL AND
								((v__params)[2]).name = 'database_name' AND v__vals[2] IS NOT NULL THEN
								EXECUTE 'SELECT COALESCE(c.execution_frequency, p.default_execution_frequency) AS freq FROM pem.probe p LEFT JOIN pem.probe_config_database c ON (p.id = c.probe_id AND c.server_id = $2::integer AND c.database_name = $3::text) WHERE p.id = $1::integer' USING v_pid, (v__vals[1])::integer, (v__vals[2])::text INTO v_freq;
							END IF;
						WHEN 400 THEN
							IF array_length(v__params, 1) >= 3 AND v__params[1] = 'server_id' AND v__vals[1] IS NOT NULL AND
								((v__params)[2]).name = 'database_name' AND v__vals[2] IS NOT NULL AND
								((v__params)[3]).name = 'schema_name' AND v__vals[3] IS NOT NULL THEN
								EXECUTE 'SELECT COALESCE(c.execution_frequency, p.default_execution_frequency) AS freq FROM pem.probe p LEFT JOIN pem.probe_config_schema c ON (p.id = c.probe_id AND c.server_id = $2::integer AND c.database_name = $3::text AND c.schema_name = $4::text) WHERE p.id = $1::integer' USING v_pid, (v__vals[1])::integer, (v__vals[2])::text, (v__vals[3])::text INTO v_freq;
							END IF;
						WHEN 500 THEN
							IF array_length(v__params, 1) >= 4 AND v__params[1] = 'server_id' AND v__vals[1] IS NOT NULL AND
								((v__params)[2]).name = 'database_name' AND v__vals[2] IS NOT NULL AND
								((v__params)[3]).name = 'schema_name' AND v__vals[3] IS NOT NULL AND
								((v__params)[4]).name = 'table_name' AND v__vals[4] IS NOT NULL THEN
								EXECUTE 'SELECT COALESCE(c.execution_frequency, p.default_execution_frequency) AS freq FROM pem.probe p LEFT JOIN pem.probe_config_table c ON (p.id = c.probe_id AND c.server_id = $2::integer AND c.database_name = $3::text AND c.schema_name = $4::text AND c.table_name = $5::text) WHERE p.id = $1::integer' USING v_pid, (v__vals[1])::integer, (v__vals[2])::text, (v__vals[3])::text, (v__vals[4])::text INTO v_freq;
							END IF;
						WHEN 600 THEN
							IF array_length(v__params, 1) >= 4 AND v__params[1] = 'server_id' AND v__vals[1] IS NOT NULL AND
								((v__params)[2]).name = 'database_name' AND v__vals[2] IS NOT NULL AND
								((v__params)[3]).name = 'schema_name' AND v__vals[3] IS NOT NULL AND
								((v__params)[4]).name = 'index_name' AND v__vals[4] IS NOT NULL THEN
								EXECUTE 'SELECT COALESCE(c.execution_frequency, p.default_execution_frequency) AS freq FROM pem.probe p LEFT JOIN pem.probe_config_index c ON (p.id = c.probe_id AND c.server_id = $2::integer AND c.database_name = $3::text AND c.schema_name = $4::text AND c.index_name = $5::text) WHERE p.id = $1::integer' USING v_pid, (v__vals[1])::integer, (v__vals[2])::text, (v__vals[3])::text, (v__vals[4])::text INTO v_freq;
							END IF;
						WHEN 700 THEN
							IF array_length(v__params, 1) >= 4 AND v__params[1] = 'server_id' AND v__vals[1] IS NOT NULL AND
								((v__params)[2]).name = 'database_name' AND v__vals[2] IS NOT NULL AND
								((v__params)[3]).name = 'schema_name' AND v__vals[3] IS NOT NULL AND
								((v__params)[4]).name = 'sequence_name' AND v__vals[4] IS NOT NULL THEN
								EXECUTE 'SELECT COALESCE(c.execution_frequency, p.default_execution_frequency) AS freq FROM pem.probe p LEFT JOIN pem.probe_config_sequence  c ON (p.id = c.probe_id AND c.server_id = $2::integer AND c.database_name = $3::text AND c.schema_name = $4::text AND c.sequence_name = $5::text) WHERE p.id = $1::integer' USING v_pid, (v__vals[1])::integer, (v__vals[2])::text, (v__vals[3])::text, (v__vals[4])::text INTO v_freq;
							END IF;
						WHEN 800 THEN
							IF array_length(v__params, 1) >= 4 AND v__params[1] = 'server_id' AND v__vals[1] IS NOT NULL AND
								((v__params)[2]).name = 'database_name' AND v__vals[2] IS NOT NULL AND
								((v__params)[3]).name = 'schema_name' AND v__vals[3] IS NOT NULL AND
								((v__params)[4]).name = 'function_name' AND v__vals[4] IS NOT NULL THEN
								EXECUTE 'SELECT COALESCE(c.execution_frequency, p.default_execution_frequency) AS freq FROM pem.probe p LEFT JOIN pem.probe_config_function c ON (p.id = c.probe_id AND c.server_id = $2::integer AND c.database_name = $3::text AND c.schema_name = $4::text AND c.function_name = $5::text) WHERE p.id = $1::integer' USING v_pid, (v__vals[1])::integer, (v__vals[2])::text, (v__vals[3])::text, (v__vals[4])::text INTO v_freq;
							END IF;
						WHEN 900 THEN
							IF array_length(v__params, 1) >= 4 AND v__params[1] = 'server_id' AND v__vals[1] IS NOT NULL AND
								((v__params)[2]).name = 'database_name' AND v__vals[2] IS NOT NULL AND
								((v__params)[3]).name = 'schema_name' AND v__vals[3] IS NOT NULL AND
								((v__params)[4]).name = 'view_name' AND v__vals[4] IS NOT NULL THEN
								EXECUTE 'SELECT COALESCE(c.execution_frequency, p.default_execution_frequency) AS freq FROM pem.probe p LEFT JOIN pem.probe_config_view c ON (p.id = c.probe_id AND c.server_id = $2::integer AND c.database_name = $3::text AND c.schema_name = $4::text AND c.view_name = $5::text) WHERE p.id = $1::integer' USING v_pid, (v__vals[1])::integer, (v__vals[2])::text, (v__vals[3])::text, (v__vals[4])::text INTO v_freq;
							END IF;
						END CASE;
						IF v_freq IS NULL THEN
							EXECUTE 'SELECT p.default_execution_frequency AS freq FROM pem.probe p WHERE p.id = $1::integer' USING v_pid INTO v_freq;
						END IF;
						IF v_minfreq IS NULL THEN
							v_minfreq := v_freq;
						ELSIF v_minfreq > v_freq THEN
							v_minfreq := v_freq;
						END IF;

						SELECT string_agg(pg_catalog.quote_ident(v__params[idx]) || ' = ' || pg_catalog.quote_literal(v__vals[idx]), ' AND '), string_agg(pg_catalog.quote_ident(v__params[idx]), ', ') FROM generate_series(array_lower(v__params,1), array_upper(v__params,1)) idx INTO v_where, v_groupon;
						EXECUTE 'SELECT min(t) FROM ((SELECT min(recorded_time) t FROM pemhistory.' || pg_catalog.quote_ident(v_metric.tbl) || ' WHERE ' || v_where || ' AND recorded_time >= $1::timestamptz) UNION ALL (SELECT max(recorded_time) t FROM pemhistory.' || pg_catalog.quote_ident(v_metric.tbl) || ' WHERE ' || v_where || ' AND recorded_time <= $1::timestamptz)) a' USING v_s_time INTO v_m_s_time;
						IF v_m_s_time < v_t_time THEN
							v_t_time := v_m_s_time;
						END IF;

						-- pos, label, probe_tbl, probe_col, agg, condition, groupon, percentage_unit, freq, min_time
						IF v_e_id IS NOT NULL AND v_e_id = v_metric.mid THEN
							v_t_op := ARRAY[v_pos::text, o_label, v_metric.tbl, v_metric.metrices[m_idx]::text, v_t_str, v_where, v_groupon, v_percent_unit::text, v_freq::text, v_m_s_time::text];
						ELSE
							v_m_ops := v_m_ops || ARRAY[ARRAY[v_pos::text, o_label, v_metric.tbl, v_metric.metrices[m_idx]::text, v_t_str, v_where, v_groupon, v_percent_unit::text, v_freq::text, v_m_s_time::text]];
						END IF;
					END LOOP;
				END IF;
			ELSE
				v_params := ARRAY[]::text[];
				v_vals := ARRAY[]::text[];
				v_m_rest_dbs := NULL;

				CASE WHEN v_applies = 100 THEN
						v_params := ARRAY['agent_id'];
						v_vals := ARRAY[p_aid::text];
					WHEN v_target = 200 THEN
						v_params := ARRAY['server_id'];
						v_vals := ARRAY[p_sid::text]::text[];

						IF v_applies >= 300 AND p_level >= 300 THEN
							-- Restricted DBs are availabe that doesn't mean - they're applicable
							-- for this metric
							--
							-- Thye're applicable only if probe can applies to database level and
							-- current dashboard is for server-level
							IF array_length(v_rest_dbs, 1) <> 0 THEN
								v_m_rest_dbs = v_rest_dbs;
							ELSE
								v_m_rest_dbs := NULL;
							END IF;
						END IF;

						IF v_applies >= 400 AND p_level = 400 THEN
							v_params := ARRAY['server_id', 'database_name', 'schema_name'];
							v_vals := ARRAY[p_sid::text, p_db, p_schema];
						ELSIF v_applies >= 300 AND p_level >= 300 THEN
							v_params := ARRAY['server_id', 'database_name'];
							v_vals := ARRAY[p_sid::text, p_db];
						END IF;
					WHEN v_target = 300 THEN
						v_params := ARRAY['server_id', 'database_name'];
						v_vals := ARRAY[p_sid::text, p_db]::text[];
						IF array_length(v_rest_dbs, 1) <> 0 THEN
							v_m_rest_dbs = v_rest_dbs;
						ELSE
							v_m_rest_dbs := NULL;
						END IF;
						IF v_applies > 300  THEN
							IF p_level > 300 THEN
								v_params := ARRAY['server_id', 'database_name', 'schema_name'];
								v_vals := ARRAY[p_sid::text, p_db, p_schema];
							END IF;
						END IF;
					WHEN v_target = 400 THEN
						v_params := ARRAY['server_id', 'database_name', 'schema_name'];
						v_vals := ARRAY[p_sid::text, p_db, p_schema];
						-- TODO:: table level chart changes
				ELSE -- Do nothing
				END CASE;
				CASE WHEN v_metric.params IS NOT NULL THEN
					FOR i IN array_lower(v_metric.params, 1) .. array_upper(v_metric.params, 1)
					LOOP
						IF v_metric.params[i].name IS NOT NULL AND v_metric.params[i].name != '' THEN
							IF p_sid IS NOT NULL AND v_metric.params[i].name = 'server_id' THEN
								v_params := v_params || v_metric.params[i].name;
								v_vals := v_vals || p_sid::text;
							ELSIF p_aid IS NOT NULL AND v_metric.params[i].name = 'agent_id' THEN
								v_params := v_params || v_metric.params[i].name;
								v_vals := v_vals || p_aid::text;
							ELSIF p_db IS NOT NULL AND p_db <> '' AND v_metric.params[i].name = 'database_name' THEN
								v_params := v_params || v_metric.params[i].name;
								v_vals := v_vals || p_db::text;
							ELSIF p_schema IS NOT NULL AND p_schema <> '' AND v_metric.params[i].name = 'schema_name' THEN
								v_params := v_params || v_metric.params[i].name;
								v_vals := v_vals || p_schema::text;
							ELSE
								v_params := v_params || v_metric.params[i].name;
								v_vals := v_vals || v_metric.params[i].value;
							END IF;
						END IF;
					END LOOP;
				ELSE -- Do nothing
				END CASE;

				v_t_str := 'A';
				FOR m_idx IN array_lower(v_metric.metrices, 1) .. array_upper(v_metric.metrices, 1)
				LOOP
					v_pos := v_pos + 1;
					o_label := '';

					EXECUTE E'
	SELECT
		(CASE WHEN NOT pit_by_default THEN display_name || ''+'' ELSE display_name END), sql_data_type, unit_of_value = ''%''::text
	FROM pem.probe_column
	WHERE probe_id = $1::int4 AND internal_name = $2::text AND is_graphable
	UNION ALL
	SELECT
		display_name, sql_data_type, unit_of_value = ''%''::text
	FROM pem.probe_column
	WHERE probe_id = $1::int4 AND (internal_name || ''_pit'') = $2::text AND is_graphable AND NOT pit_by_default AND calculate_pit'
	USING v_pid, v_metric.metrices[m_idx] INTO v_mlbl, v_ptype, v_percent_unit;

					IF v_chart.labels IS NOT NULL AND array_length(v_chart.labels, 1) >= v_pos THEN
						o_label := v_chart.labels[v_pos];
					ELSE
						IF v_mlbl IS NOT NULL THEN
							o_label := v_mlbl;
						END IF;
					END IF;

					IF v_metric.agg_func IS NOT NULL AND array_length(v_metric.agg_func, 1) >= m_idx THEN
						v_t_str := v_metric.agg_func[m_idx];
					END IF;

					SELECT string_agg(pg_catalog.quote_ident(v_params[idx]) || ' = ' || pg_catalog.quote_literal(v_vals[idx]), ' AND '), string_agg(pg_catalog.quote_ident(v_params[idx]), ', ') FROM generate_series(array_lower(v_params,1), array_upper(v_params,1)) idx INTO v_where, v_groupon;
					EXECUTE 'SELECT min(t) FROM ((SELECT min(recorded_time) t FROM pemhistory.' || pg_catalog.quote_ident(v_metric.tbl) || ' WHERE ' || v_where || ' AND recorded_time >= $1::timestamptz) UNION ALL (SELECT max(recorded_time) t FROM pemhistory.' || pg_catalog.quote_ident(v_metric.tbl) || ' WHERE ' || v_where || ' AND recorded_time <= $1::timestamptz)) a' USING v_s_time INTO v_m_s_time;
					IF v_m_s_time < v_t_time THEN
						v_t_time := v_m_s_time;
					END IF;

					-- pos, label, probe_tbl, probe_col, agg, condition, groupon, percentage_unit, freq, min_time
					IF v_e_id IS NOT NULL AND v_e_id = v_metric.mid THEN
						v_t_op := ARRAY[v_pos::text, o_label, v_metric.tbl, v_metric.metrices[m_idx]::text, v_t_str, v_where, v_groupon, v_percent_unit::text, '10 seconds', v_m_s_time::text];
					ELSE
						v_m_ops := v_m_ops || ARRAY[ARRAY[v_pos::text, o_label, v_metric.tbl, v_metric.metrices[m_idx]::text, v_t_str, v_where, v_groupon, v_percent_unit::text, '10 seconds', v_m_s_time::text]];
					END IF;
				END LOOP;
			END IF;
		END IF;
	END LOOP;
	CLOSE v_mcurs;

	v_aggqry := ARRAY[
'WITH dtbl AS (
	SELECT
		floor(EXTRACT(EPOCH FROM (ph.recorded_time - $2::timestamptz)) / EXTRACT(EPOCH FROM $1::interval)) dn,
		row_number() OVER (ORDER BY ph.recorded_time) rn,
		ph.recorded_time rt, COALESCE(ph.@@COLUMN@@, 0) val
	FROM
		pemhistory.@@TABLE@@ ph
	WHERE @@CONDITION@@
		AND ph.recorded_time >= $3::timestamptz
		AND ph.recorded_time <= $4::timestamptz
)
SELECT
	$5::int2 o_idx, $6::text o_label,
	to_timestamp((dn * EXTRACT(EPOCH FROM $1::interval)) + EXTRACT(EPOCH FROM $2::timestamptz)) o_aggtime,
	val::numeric o_aggval
FROM (
	SELECT
		dn, val, row_number() OVER (PARTITION BY dn ORDER BY rt) pidx
	FROM (
		SELECT
			t1.val val,
			unnest(CASE WHEN ((t1.dn = t2.dn) OR (t1.dn < 0 AND t2.dn <= 0)) THEN ARRAY[t2.dn::bigint]
			WHEN t2.dn IS NULL AND t1.dn < 0 THEN ARRAY(SELECT g::bigint FROM generate_series(0, $7::bigint, 1) g)
			WHEN t2.dn IS NULL AND t1.dn <= $7::bigint THEN ARRAY(SELECT g FROM generate_series(t1.dn::bigint, $7::bigint, 1) g)
			WHEN t1.dn < 0 AND t2.dn > 0 THEN ARRAY(SELECT g FROM generate_series(0, (t2.dn - 1)::bigint, 1) g)
			ELSE ARRAY(SELECT g FROM generate_series(t1.dn::bigint, (t2.dn - 1)::bigint, 1) g)
			END) dn,
			t1.rt rt
		FROM
			dtbl t1
			LEFT JOIN dtbl t2 ON (t1.rn = t2.rn - 1)) t
		WHERE dn >= 0) tbl
WHERE pidx = 1 AND to_timestamp((dn * EXTRACT(EPOCH FROM $1::interval)) + EXTRACT(EPOCH FROM $2::timestamptz)) <= $4::timestamptz
ORDER BY dn',
'WITH dtbl AS (
	SELECT
		floor(EXTRACT(EPOCH FROM (ph.recorded_time - $2::timestamptz)) / EXTRACT(EPOCH FROM $1::interval)) dn,
		row_number() OVER (ORDER BY ph.recorded_time) rn,
		COALESCE(ph.@@COLUMN@@, 0) val
	FROM
		pemhistory.@@TABLE@@ ph
	WHERE @@CONDITION@@
		AND ph.recorded_time >= $3::timestamptz
		AND ph.recorded_time <= $4::timestamptz
)
SELECT
	$5::int2 o_idx, $6::text o_label,
	to_timestamp((dn * EXTRACT(EPOCH FROM $1::interval)) + EXTRACT(EPOCH FROM $2::timestamptz)) o_aggtime,
	max(val)::numeric o_aggval
FROM (
	SELECT
		t1.val val,
		unnest(CASE WHEN ((t1.dn = t2.dn) OR (t1.dn < 0 AND t2.dn <= 0)) THEN ARRAY[t2.dn::bigint]
		WHEN t2.dn IS NULL AND t1.dn < 0 THEN ARRAY(SELECT g::bigint FROM generate_series(0, $7::bigint, 1) g)
		WHEN t2.dn IS NULL AND t1.dn <= $7::bigint THEN ARRAY(SELECT g FROM generate_series(t1.dn::bigint, $7::bigint, 1) g)
		WHEN t1.dn < 0 AND t2.dn > 0 THEN ARRAY(SELECT g FROM generate_series(0, (t2.dn - 1)::bigint, 1) g)
		ELSE ARRAY(SELECT g FROM generate_series(t1.dn::bigint, (t2.dn - 1)::bigint, 1) g)
		END) dn
	FROM
		dtbl t1
		LEFT JOIN dtbl t2 ON (t1.rn = t2.rn - 1)) t
WHERE dn >= 0 AND to_timestamp((dn * EXTRACT(EPOCH FROM $1::interval)) + EXTRACT(EPOCH FROM $2::timestamptz)) <= $4::timestamptz
GROUP BY dn
ORDER BY dn',
'WITH dtbl AS (
	SELECT
		floor(EXTRACT(EPOCH FROM (ph.recorded_time - $2::timestamptz)) / EXTRACT(EPOCH FROM $1::interval)) dn,
		row_number() OVER (ORDER BY ph.recorded_time) rn,
		COALESCE(ph.@@COLUMN@@, 0) val
	FROM
		pemhistory.@@TABLE@@ ph
	WHERE @@CONDITION@@
		AND ph.recorded_time >= $3::timestamptz
		AND ph.recorded_time <= $4::timestamptz
)
SELECT
	$5::int2 o_idx, $6::text o_label,
	to_timestamp((dn * EXTRACT(EPOCH FROM $1::interval)) + EXTRACT(EPOCH FROM $2::timestamptz)) o_aggtime,
	min(val)::numeric o_aggval
FROM (
	SELECT
		t1.val val,
		unnest(CASE WHEN ((t1.dn = t2.dn) OR (t1.dn < 0 AND t2.dn <= 0)) THEN ARRAY[t2.dn::bigint]
		WHEN t2.dn IS NULL AND t1.dn < 0 THEN ARRAY(SELECT g::bigint FROM generate_series(0, $7::bigint, 1) g)
		WHEN t2.dn IS NULL AND t1.dn <= $7::bigint THEN ARRAY(SELECT g FROM generate_series(t1.dn::bigint, $7::bigint, 1) g)
		WHEN t1.dn < 0 AND t2.dn > 0 THEN ARRAY(SELECT g FROM generate_series(0, (t2.dn - 1)::bigint, 1) g)
		ELSE ARRAY(SELECT g FROM generate_series(t1.dn::bigint, (t2.dn - 1)::bigint, 1) g)
		END) dn
	FROM
		dtbl t1
		LEFT JOIN dtbl t2 ON (t1.rn = t2.rn - 1)) t
WHERE dn >= 0 AND to_timestamp((dn * EXTRACT(EPOCH FROM $1::interval)) + EXTRACT(EPOCH FROM $2::timestamptz)) <= $4::timestamptz
GROUP BY dn
ORDER BY dn',
'WITH dtbl AS (
	SELECT
		floor(EXTRACT(EPOCH FROM (ph.recorded_time - $2::timestamptz)) / EXTRACT(EPOCH FROM $1::interval)) dn,
		(((floor(EXTRACT(EPOCH FROM (ph.recorded_time - $2::timestamptz)) / (EXTRACT(EPOCH FROM $1::interval))) + 1) * EXTRACT(EPOCH FROM $1::interval) / EXTRACT(EPOCH FROM $8::interval)) - floor(EXTRACT(EPOCH FROM (ph.recorded_time - $2::timestamptz)) / (EXTRACT(EPOCH FROM $8::interval)))) cnt,
		row_number() OVER (ORDER BY ph.recorded_time) rn,
		ph.recorded_time rt, COALESCE(ph.@@COLUMN@@, 0) val
	FROM
		pemhistory.@@TABLE@@ ph
	WHERE @@CONDITION@@
		AND ph.recorded_time >= $3::timestamptz
		AND ph.recorded_time <= $4::timestamptz
)
SELECT
	$5::int2 o_idx, $6::text o_label,
	to_timestamp((dn * EXTRACT(EPOCH FROM $1::interval)) + EXTRACT(EPOCH FROM $2::timestamptz)) o_aggtime,
	(sum(val::numeric * cnt) / sum(cnt))::numeric o_aggval
FROM (
	SELECT
		t1.val val,
		unnest(CASE WHEN ((t1.dn = t2.dn) OR (t1.dn < 0 AND t2.dn <= 0)) THEN ARRAY[t2.dn::bigint]
		WHEN t2.dn IS NULL AND t1.dn < 0 THEN ARRAY(SELECT g::bigint FROM generate_series(0, $7::bigint, 1) g)
		WHEN t2.dn IS NULL AND t1.dn <= $7::bigint THEN ARRAY(SELECT g FROM generate_series(t1.dn::bigint, $7::bigint, 1) g)
		WHEN t1.dn < 0 AND t2.dn > 0 THEN ARRAY(SELECT g FROM generate_series(0, (t2.dn - 1)::bigint, 1) g)
		ELSE ARRAY(SELECT g FROM generate_series(t1.dn::bigint, (t2.dn - 1)::bigint, 1) g)
		END) dn,
		unnest(CASE WHEN ((t1.dn = t2.dn) OR (t1.dn < 0 AND t2.dn <= 0)) THEN ARRAY[1::bigint]
		WHEN t2.dn IS NULL AND t1.dn < 0 THEN ARRAY(SELECT 1::bigint FROM generate_series(0, $7::bigint, 1) g)
		WHEN t2.dn IS NULL AND t1.dn <= $7::bigint THEN ARRAY(SELECT 1 FROM generate_series(t1.dn::bigint, $7::bigint, 1) g)
		WHEN t1.dn < 0 AND t2.dn > 0 THEN ARRAY(SELECT 1 FROM generate_series(0, (t2.dn - 1)::bigint, 1) g)
		ELSE ARRAY(SELECT t1.cnt FROM generate_series(t1.dn::bigint, (t2.dn - 1)::bigint, 1) g)
		END) cnt
	FROM
		dtbl t1
		LEFT JOIN dtbl t2 ON (t1.rn = t2.rn - 1)) t
WHERE dn >= 0 AND to_timestamp((dn * EXTRACT(EPOCH FROM $1::interval)) + EXTRACT(EPOCH FROM $2::timestamptz)) <= $4::timestamptz
GROUP BY dn
ORDER BY dn'];

	IF v_minfreq IS NULL OR v_minfreq < '10 seconds'::interval THEN
		v_minfreq := '10 seconds'::interval;
	END IF;

	IF v_maxpoints IS NULL OR v_maxpoints <= 1 OR v_maxpoints > 300 THEN
		v_maxpoints := 300;
	END IF;

	IF v_t_time > v_s_time THEN
		v_s_time := v_t_time;
	END IF;

	-- No data available for this range
	IF v_e_time < v_t_time THEN
		RETURN;
	END IF;

	v_aggspan := EXTRACT (EPOCH FROM (v_e_time - v_s_time)) / (v_maxpoints - 1);
	IF v_aggspan < v_minfreq THEN
		v_aggspan := v_minfreq;
		SELECT max(a) + 1 INTO v_maxpoints FROM (SELECT unnest(ARRAY[floor(EXTRACT(EPOCH FROM (v_e_time - v_s_time)) / EXTRACT(EPOCH FROM v_aggspan))::bigint, 1::bigint]) a) t;
	END IF;

	IF v_t_op IS NOT NULL THEN
		IF v_e_time > v_c_time OR p_etime IS NULL THEN

			-- Slope, intercept, corr for the threshold metric
			--
			EXECUTE 'SELECT regr_slope(' || pg_catalog.quote_ident(v_t_op[4]) || '::numeric, EXTRACT(EPOCH FROM recorded_time)), regr_intercept(' || pg_catalog.quote_ident(v_t_op[4]) || '::numeric, EXTRACT(EPOCH FROM recorded_time)), corr(' || pg_catalog.quote_ident(v_t_op[4]) || '::numeric, EXTRACT(EPOCH FROM recorded_time)), count(*), (SELECT ' || pg_catalog.quote_ident(v_t_op[4]) || '::numeric FROM pemhistory.' || pg_catalog.quote_ident(v_t_op[3]) || ' WHERE ' || v_t_op[6] ||' ORDER BY recorded_time DESC LIMIT 1) FROM pemhistory.' || pg_catalog.quote_ident(v_t_op[3]) || ' WHERE ' || v_t_op[6]
			INTO v_slope, v_intercept, v_corr, v_cnt, v_value;

			IF (v_cnt = 1 AND v_value IS NOT NULL) OR
				(v_corr IS NULL AND v_value IS NOT NULL) THEN

				IF p_etime IS NULL THEN
					v_e_time := v_c_time + '3 years'::interval;
				END IF;

				v_aggspan := ((v_e_time - v_s_time) / (v_maxpoints - 1))::interval;
				IF v_minfreq > v_aggspan THEN
					v_aggspan := v_minfreq;
					SELECT max(a) + 1 INTO v_maxpoints FROM (SELECT unnest(ARRAY[floor(EXTRACT(EPOCH FROM (v_e_time - v_s_time)) / EXTRACT(EPOCH FROM v_aggspan))::bigint, 1::bigint]) a) t;
				END IF;

				IF v_s_time < v_c_time THEN
					-- 1. pos, 2. label, 3. probe_tbl, 4. probe_col, 5. agg, 6. condition, 7. groupon, 8. percentage_unit, 9. freq, 10. min_time
					CASE v_t_op[5]
					WHEN 'F' THEN
						-- frequncy, span, st, tst, et, pos, lbl
						RETURN QUERY EXECUTE replace(replace(replace(v_aggqry[1], '@@COLUMN@@', pg_catalog.quote_ident(v_t_op[4])), '@@TABLE@@', pg_catalog.quote_ident(v_t_op[3])), '@@CONDITION@@', v_t_op[6])  USING v_aggspan, v_s_time, v_t_op[10], v_c_time, v_t_op[1], v_t_op[2], v_maxpoints;
					WHEN 'M' THEN
						RETURN QUERY EXECUTE replace(replace(replace(v_aggqry[2], '@@COLUMN@@', pg_catalog.quote_ident(v_t_op[4])), '@@TABLE@@', pg_catalog.quote_ident(v_t_op[3])), '@@CONDITION@@', v_t_op[6])  USING v_aggspan, v_s_time, v_t_op[10], v_c_time, v_t_op[1], v_t_op[2], v_maxpoints;
					WHEN 'm' THEN
						RETURN QUERY EXECUTE replace(replace(replace(v_aggqry[3], '@@COLUMN@@', pg_catalog.quote_ident(v_t_op[4])), '@@TABLE@@', pg_catalog.quote_ident(v_t_op[3])), '@@CONDITION@@', v_t_op[6])  USING v_aggspan, v_s_time, v_t_op[10], v_c_time, v_t_op[1], v_t_op[2], v_maxpoints;
					ELSE
						RETURN QUERY EXECUTE replace(replace(replace(v_aggqry[4], '@@COLUMN@@', pg_catalog.quote_ident(v_t_op[4])), '@@TABLE@@', pg_catalog.quote_ident(v_t_op[3])), '@@CONDITION@@', v_t_op[6])  USING v_aggspan, v_s_time, v_t_op[10], v_c_time, v_t_op[1], v_t_op[2], v_maxpoints, v_t_op[9];
					END CASE;
					SELECT to_timestamp(((floor(EXTRACT(EPOCH FROM v_c_time - v_s_time) / EXTRACT(EPOCH FROM v_aggspan))  + 1) * EXTRACT(EPOCH FROM v_aggspan)) + EXTRACT(EPOCH FROM v_s_time)) INTO v_m_s_time;
				ELSE
					v_m_s_time := v_s_time;
				END IF;
				RETURN QUERY EXECUTE 'SELECT $1::int2 o_idx, $2::text o_lbl, g o_aggtime, $3::numeric o_aggval FROM generate_series($4::timestamptz, $5::timestamptz, $6::interval) g' USING v_t_op[1], v_t_op[2], v_value, v_m_s_time, v_e_time, v_aggspan;

			ELSIF (v_corr IS NOT NULL AND v_slope IS NOT NULL AND v_intercept IS NOT NULL) THEN

				-- Do we need to calculate the timeline for extrapolated data?
				IF (v_e_op = 'FALLS_BELOW' AND v_value > v_e_val) OR
					(v_e_op = 'EXCEEDS' AND v_value < v_e_val) THEN

					IF p_etime IS NULL THEN
						v_e_time := v_c_time + '3 years'::interval;
					END IF;

					-- Let's calculate the value at maximum time period
					SELECT ((v_slope * EXTRACT(EPOCH FROM v_e_time)) + v_intercept) INTO v_tmpval;

					IF (v_tmpval < 0 AND v_e_op = 'FALLS_BELOW') OR
						(v_tmpval > 0 AND ((v_e_op = 'EXCEEDS' AND v_tmpval > v_e_val) OR
							(v_e_op = 'FALLS_BELOW' AND v_tmpval < v_e_val))) THEN
						SELECT to_timestamp((v_e_val - v_intercept) / v_slope) INTO v_e_time;
					ELSIF v_tmpval < 0 AND v_e_op = 'EXCEEDS' THEN
						SELECT to_timestamp((0 - v_intercept) / v_slope) INTO v_e_time;
					END IF;

					IF p_etime IS NULL AND v_e_time < v_c_time THEN
						v_e_time := v_c_time;
					END IF;
				END IF;

				v_aggspan := ((v_e_time - v_s_time) / (v_maxpoints - 1))::interval;
				IF v_minfreq > v_aggspan THEN
					v_aggspan := v_minfreq;
					SELECT max(a) + 1 INTO v_maxpoints FROM (SELECT unnest(ARRAY[floor(EXTRACT(EPOCH FROM (v_e_time - v_s_time)) / EXTRACT(EPOCH FROM v_aggspan))::bigint, 1::bigint]) a) t;
				END IF;

				IF v_s_time < v_c_time THEN
					-- 1. pos, 2. label, 3. probe_tbl, 4. probe_col, 5. agg, 6. condition, 7. groupon, 8. percentage_unit, 9. freq, 10. min_time
					CASE v_t_op[5]
					WHEN 'F' THEN
						-- frequncy, span, st, tst, et, pos, lbl
						RETURN QUERY EXECUTE replace(replace(replace(v_aggqry[1], '@@COLUMN@@', pg_catalog.quote_ident(v_t_op[4])), '@@TABLE@@', pg_catalog.quote_ident(v_t_op[3])), '@@CONDITION@@', v_t_op[6])  USING v_aggspan, v_s_time, v_t_op[10], v_c_time, v_t_op[1], v_t_op[2], v_maxpoints;
					WHEN 'M' THEN
						RETURN QUERY EXECUTE replace(replace(replace(v_aggqry[2], '@@COLUMN@@', pg_catalog.quote_ident(v_t_op[4])), '@@TABLE@@', pg_catalog.quote_ident(v_t_op[3])), '@@CONDITION@@', v_t_op[6])  USING v_aggspan, v_s_time, v_t_op[10], v_c_time, v_t_op[1], v_t_op[2], v_maxpoints;
					WHEN 'm' THEN
						RETURN QUERY EXECUTE replace(replace(replace(v_aggqry[3], '@@COLUMN@@', pg_catalog.quote_ident(v_t_op[4])), '@@TABLE@@', pg_catalog.quote_ident(v_t_op[3])), '@@CONDITION@@', v_t_op[6])  USING v_aggspan, v_s_time, v_t_op[10], v_c_time, v_t_op[1], v_t_op[2], v_maxpoints;
					ELSE
						RETURN QUERY EXECUTE replace(replace(replace(v_aggqry[4], '@@COLUMN@@', pg_catalog.quote_ident(v_t_op[4])), '@@TABLE@@', pg_catalog.quote_ident(v_t_op[3])), '@@CONDITION@@', v_t_op[6])  USING v_aggspan, v_s_time, v_t_op[10], v_c_time, v_t_op[1], v_t_op[2], v_maxpoints, v_t_op[9];
					END CASE;
					SELECT to_timestamp(((floor(EXTRACT(EPOCH FROM v_c_time - v_s_time) / EXTRACT(EPOCH FROM v_aggspan))  + 1) * EXTRACT(EPOCH FROM v_aggspan)) + EXTRACT(EPOCH FROM v_s_time)) INTO v_m_s_time;
				ELSE
					v_m_s_time := v_s_time;
				END IF;
				IF v_e_time > v_c_time THEN
					RETURN QUERY EXECUTE 'SELECT $1::int2 o_idx, $2::text o_lbl, g o_aggtime, (($3::numeric * EXTRACT(EPOCH FROM g)) + $4::numeric)::numeric o_aggval FROM generate_series($5::timestamptz, $6::timestamptz, $7::interval) g' USING v_t_op[1], v_t_op[2], v_slope, v_intercept, v_m_s_time, v_e_time, v_aggspan;
				END IF;
			ELSE
				o_idx := -1;
				o_aggtime := NULL;
				o_aggval  := NULL;
				o_label :=  '116';
				RETURN NEXT;

				IF (p_etime IS NOT NULL AND p_etime > v_c_time) OR (p_etime IS NULL) THEN
					v_e_time := v_c_time;
				ELSIF p_etime IS NOT NULL THEN
					v_e_time := p_etime;
				END IF;

				IF v_s_time > v_e_time THEN
					RETURN;
				END IF;

				v_aggspan := ((v_e_time - v_s_time) / (v_maxpoints - 1))::interval;
				IF v_minfreq > v_aggspan THEN
					v_aggspan := v_minfreq;
					SELECT max(a) + 1 INTO v_maxpoints FROM (SELECT unnest(ARRAY[floor(EXTRACT(EPOCH FROM (v_e_time - v_s_time)) / EXTRACT(EPOCH FROM v_aggspan))::bigint, 1::bigint]) a) t;
				END IF;

				IF v_s_time < v_c_time THEN
					-- 1. pos, 2. label, 3. probe_tbl, 4. probe_col, 5. agg, 6. condition, 7. groupon, 8. percentage_unit, 9. freq, 10. min_time
					CASE v_t_op[5]
					WHEN 'F' THEN
						-- frequncy, span, st, tst, et, pos, lbl
						RETURN QUERY EXECUTE replace(replace(replace(v_aggqry[1], '@@COLUMN@@', pg_catalog.quote_ident(v_t_op[4])), '@@TABLE@@', pg_catalog.quote_ident(v_t_op[3])), '@@CONDITION@@', v_t_op[6])  USING v_aggspan, v_s_time, v_t_op[10], v_c_time, v_t_op[1], v_t_op[2], v_maxpoints;
					WHEN 'M' THEN
						RETURN QUERY EXECUTE replace(replace(replace(v_aggqry[2], '@@COLUMN@@', pg_catalog.quote_ident(v_t_op[4])), '@@TABLE@@', pg_catalog.quote_ident(v_t_op[3])), '@@CONDITION@@', v_t_op[6])  USING v_aggspan, v_s_time, v_t_op[10], v_c_time, v_t_op[1], v_t_op[2], v_maxpoints;
					WHEN 'm' THEN
						RETURN QUERY EXECUTE replace(replace(replace(v_aggqry[3], '@@COLUMN@@', pg_catalog.quote_ident(v_t_op[4])), '@@TABLE@@', pg_catalog.quote_ident(v_t_op[3])), '@@CONDITION@@', v_t_op[6])  USING v_aggspan, v_s_time, v_t_op[10], v_c_time, v_t_op[1], v_t_op[2], v_maxpoints;
					ELSE
						RETURN QUERY EXECUTE replace(replace(replace(v_aggqry[4], '@@COLUMN@@', pg_catalog.quote_ident(v_t_op[4])), '@@TABLE@@', pg_catalog.quote_ident(v_t_op[3])), '@@CONDITION@@', v_t_op[6])  USING v_aggspan, v_s_time, v_t_op[10], v_c_time, v_t_op[1], v_t_op[2], v_maxpoints, v_t_op[9];
					END CASE;
				END IF;
			END IF;
		ELSE
			v_aggspan := ((v_e_time - v_s_time) / (v_maxpoints - 1))::interval;
			IF v_minfreq > v_aggspan THEN
				v_aggspan := v_minfreq;
				SELECT max(a) + 1 INTO v_maxpoints FROM (SELECT unnest(ARRAY[floor(EXTRACT(EPOCH FROM (v_e_time - v_s_time)) / EXTRACT(EPOCH FROM v_aggspan))::bigint, 1::bigint]) a) t;
			END IF;

			-- 1. pos, 2. label, 3. probe_tbl, 4. probe_col, 5. agg, 6. condition, 7. groupon, 8. percentage_unit, 9. freq, 10. min_time
			CASE v_t_op[5]
			WHEN 'F' THEN
				-- frequncy, span, st, tst, et, pos, lbl
				RETURN QUERY EXECUTE replace(replace(replace(v_aggqry[1], '@@COLUMN@@', pg_catalog.quote_ident(v_t_op[4])), '@@TABLE@@', pg_catalog.quote_ident(v_t_op[3])), '@@CONDITION@@', v_t_op[6])  USING v_aggspan, v_s_time, v_t_op[10], v_e_time, v_t_op[1], v_t_op[2], v_maxpoints;
			WHEN 'M' THEN
				RETURN QUERY EXECUTE replace(replace(replace(v_aggqry[2], '@@COLUMN@@', pg_catalog.quote_ident(v_t_op[4])), '@@TABLE@@', pg_catalog.quote_ident(v_t_op[3])), '@@CONDITION@@', v_t_op[6])  USING v_aggspan, v_s_time, v_t_op[10], v_e_time, v_t_op[1], v_t_op[2], v_maxpoints;
			WHEN 'm' THEN
				RETURN QUERY EXECUTE replace(replace(replace(v_aggqry[3], '@@COLUMN@@', pg_catalog.quote_ident(v_t_op[4])), '@@TABLE@@', pg_catalog.quote_ident(v_t_op[3])), '@@CONDITION@@', v_t_op[6])  USING v_aggspan, v_s_time, v_t_op[10], v_e_time, v_t_op[1], v_t_op[2], v_maxpoints;
			ELSE
				RETURN QUERY EXECUTE replace(replace(replace(v_aggqry[4], '@@COLUMN@@', pg_catalog.quote_ident(v_t_op[4])), '@@TABLE@@', pg_catalog.quote_ident(v_t_op[3])), '@@CONDITION@@', v_t_op[6])  USING v_aggspan, v_s_time, v_t_op[10], v_e_time, v_t_op[1], v_t_op[2], v_maxpoints, v_t_op[9];
			END CASE;
		END IF;
	ELSIF p_etime IS NULL AND v_e_span IS NOT NULL AND v_e_span >= '1 seconds'::interval THEN
		v_e_time := v_c_time + v_e_span;
		v_aggspan := ((v_e_time - v_s_time) / (v_maxpoints - 1))::interval;
		IF v_minfreq > v_aggspan THEN
			v_aggspan := v_minfreq;
			SELECT max(a) + 1 INTO v_maxpoints FROM (SELECT unnest(ARRAY[floor(EXTRACT(EPOCH FROM (v_e_time - v_s_time)) / EXTRACT(EPOCH FROM v_aggspan))::bigint, 1::bigint]) a) t;
		END IF;
	END IF;

	IF v_s_time <= v_c_time AND v_e_time > v_c_time THEN
		o_idx := -1;
		o_aggtime := v_c_time;
		o_aggval  := NULL;
		o_label :=  '115';

		RETURN NEXT;
	END IF;

	IF array_length(v_m_ops, 1) IS NULL OR array_length(v_m_ops, 1) = 0 THEN
		RETURN;
	END IF;

	v_m_s_time := v_s_time;
	FOR v_pos IN array_lower(v_m_ops, 1) .. array_upper(v_m_ops, 1)
	LOOP
		v_qry := '
WITH dtbl AS (
	SELECT
		rt, val, floor(dt / (EXTRACT(EPOCH FROM $1::interval))) pn, floor(dt / (EXTRACT(EPOCH FROM $2::interval))) dn,
		dense_rank() OVER (PARTITION BY floor(dt / (EXTRACT(EPOCH FROM $2::interval))) ORDER BY floor(dt / (EXTRACT(EPOCH FROM $1::interval))) ASC) pidx,
		row_number() OVER (ORDER BY rt) rn
	FROM (
		SELECT
			EXTRACT(EPOCH FROM (ph.recorded_time - $3::timestamptz)) dt,
			ph.recorded_time rt, COALESCE(' || pg_catalog.quote_ident(v_m_ops[v_pos][4]) || ', 0) val
		FROM
			pemhistory.' || pg_catalog.quote_ident(v_m_ops[v_pos][3]) || ' ph
		WHERE ' || v_m_ops[v_pos][6] || ' AND ph.recorded_time >= $4::timestamptz AND ph.recorded_time <= $5::timestamptz) tbl
)
';

		IF v_e_time > v_c_time THEN
			-- Calculate slope, intercept, corr for this metric
			--
			EXECUTE 'SELECT regr_slope(' || pg_catalog.quote_ident(v_m_ops[v_pos][4]) || '::numeric, EXTRACT(EPOCH FROM recorded_time)), regr_intercept(' || pg_catalog.quote_ident(v_m_ops[v_pos][4]) || '::numeric, EXTRACT(EPOCH FROM recorded_time)), corr(' || pg_catalog.quote_ident(v_m_ops[v_pos][4]) || '::numeric, EXTRACT(EPOCH FROM recorded_time)), count(*), (SELECT ' || pg_catalog.quote_ident(v_m_ops[v_pos][4]) || '::numeric FROM pemhistory.' || pg_catalog.quote_ident(v_m_ops[v_pos][3]) || ' WHERE ' || v_m_ops[v_pos][6] ||' AND ' || pg_catalog.quote_ident(v_m_ops[v_pos][4]) || ' IS NOT NULL ORDER BY recorded_time DESC LIMIT 1) FROM pemhistory.' || pg_catalog.quote_ident(v_m_ops[v_pos][3]) || ' WHERE ' || v_m_ops[v_pos][6]
			INTO v_slope, v_intercept, v_corr, v_cnt, v_value;

			IF v_cnt = 1 OR v_corr IS NULL OR v_value IS NULL OR v_s_time > v_c_time THEN
				IF (v_cnt = 1 OR v_corr IS NULL) AND v_value IS NOT NULL THEN
					RETURN QUERY EXECUTE 'SELECT $1::int2 o_idx, $2::text o_lbl, g o_aggtime, $3::numeric o_aggval FROM generate_series($4::timestamptz, $5::timestamptz, $6::interval) g' USING v_m_ops[v_pos][1], v_m_ops[v_pos][2], v_value, v_s_time, v_e_time, v_aggspan;
					CONTINUE;
				ELSIF (v_corr IS NOT NULL AND v_value IS NOT NULL AND v_slope IS NOT NULL AND v_intercept IS NOT NULL) THEN
					RETURN QUERY EXECUTE 'SELECT $1::int2 o_idx, $2::text o_lbl, g o_aggtime, (($3::numeric * EXTRACT(EPOCH FROM g)) + $4::numeric)::numeric o_aggval FROM generate_series($5::timestamptz, $6::timestamptz, $7::interval) g' USING v_m_ops[v_pos][1], v_m_ops[v_pos][2], v_slope, v_intercept, v_s_time, v_e_time, v_aggspan;
					CONTINUE;
				ELSIF (v_value IS NULL OR v_cnt = 0 OR (v_corr IS NULL AND v_slope IS NULL AND v_intercept IS NULL)) THEN
					CONTINUE;
				ELSE
					v_m_e_time := v_c_time;
				END IF;
			END IF;

			-- Let's calculate the value at maximum time period
			SELECT ((v_slope * EXTRACT(EPOCH FROM v_e_time)) + v_intercept) INTO v_tmpval;

			IF (v_tmpval < 0) THEN
				SELECT to_timestamp((0 - v_intercept) / v_slope) INTO v_m_e_time;
			ELSIF v_tmpval > 0 AND (v_m_ops[v_pos][8]::boolean = true)  THEN
				SELECT to_timestamp((100 - v_intercept) / v_slope) INTO v_m_e_time;
			ELSE
				v_m_e_time := v_e_time;
			END IF;
			IF v_m_e_time > v_e_time THEN
				v_m_e_time := v_e_time;
			END IF;

			IF v_s_time <= v_c_time THEN
				-- 1. pos, 2. label, 3. probe_tbl, 4. probe_col, 5. agg, 6. condition, 7. groupon, 8. percentage_unit, 9. freq, 10. min_time
				CASE v_m_ops[v_pos][5]
				WHEN 'F' THEN
					-- frequncy, span, st, tst, et, pos, lbl
					RETURN QUERY EXECUTE replace(replace(replace(v_aggqry[1], '@@COLUMN@@', pg_catalog.quote_ident(v_m_ops[v_pos][4])), '@@TABLE@@', pg_catalog.quote_ident(v_m_ops[v_pos][3])), '@@CONDITION@@', v_m_ops[v_pos][6])  USING v_aggspan, v_s_time, v_m_ops[v_pos][10], v_c_time, v_m_ops[v_pos][1], v_m_ops[v_pos][2], v_maxpoints;
				WHEN 'M' THEN
					RETURN QUERY EXECUTE replace(replace(replace(v_aggqry[2], '@@COLUMN@@', pg_catalog.quote_ident(v_m_ops[v_pos][4])), '@@TABLE@@', pg_catalog.quote_ident(v_m_ops[v_pos][3])), '@@CONDITION@@', v_m_ops[v_pos][6])  USING v_aggspan, v_s_time, v_m_ops[v_pos][10], v_c_time, v_m_ops[v_pos][1], v_m_ops[v_pos][2], v_maxpoints;
				WHEN 'm' THEN
					RETURN QUERY EXECUTE replace(replace(replace(v_aggqry[3], '@@COLUMN@@', pg_catalog.quote_ident(v_m_ops[v_pos][4])), '@@TABLE@@', pg_catalog.quote_ident(v_m_ops[v_pos][3])), '@@CONDITION@@', v_m_ops[v_pos][6])  USING v_aggspan, v_s_time, v_m_ops[v_pos][10], v_c_time, v_m_ops[v_pos][1], v_m_ops[v_pos][2], v_maxpoints;
				ELSE
					RETURN QUERY EXECUTE replace(replace(replace(v_aggqry[4], '@@COLUMN@@', pg_catalog.quote_ident(v_m_ops[v_pos][4])), '@@TABLE@@', pg_catalog.quote_ident(v_m_ops[v_pos][3])), '@@CONDITION@@', v_m_ops[v_pos][6])  USING v_aggspan, v_s_time, v_m_ops[v_pos][10], v_c_time, v_m_ops[v_pos][1], v_m_ops[v_pos][2], v_maxpoints, v_m_ops[v_pos][9];
				END CASE;
			END IF;

			IF v_m_e_time > v_c_time THEN
				IF v_m_s_time < v_c_time THEN
					SELECT to_timestamp(((floor(EXTRACT(EPOCH FROM v_c_time - v_s_time) / EXTRACT(EPOCH FROM v_aggspan))  + 1) * EXTRACT(EPOCH FROM v_aggspan)) + EXTRACT(EPOCH FROM v_s_time)) INTO v_m_s_time;
				END IF;
				RETURN QUERY EXECUTE 'SELECT $1::int2 o_idx, $2::text o_lbl, g::timestamptz o_aggtime, (($3::numeric * EXTRACT(EPOCH FROM g)) + $4::numeric)::numeric o_aggval FROM generate_series($5::timestamptz, $6::timestamptz, $7::interval) g' USING v_m_ops[v_pos][1], v_m_ops[v_pos][2], v_slope, v_intercept, v_m_s_time, v_m_e_time, v_aggspan;
			END IF;
		ELSE
			-- max-points, span, frequncy, probe start time, st, et, pos, lbl
			CASE v_m_ops[v_pos][5]
			WHEN 'F' THEN
				RETURN QUERY EXECUTE replace(replace(replace(v_aggqry[1], '@@COLUMN@@', pg_catalog.quote_ident(v_m_ops[v_pos][4])), '@@TABLE@@', pg_catalog.quote_ident(v_m_ops[v_pos][3])), '@@CONDITION@@', v_m_ops[v_pos][6])  USING v_aggspan, v_s_time, v_m_ops[v_pos][10], v_e_time, v_m_ops[v_pos][1], v_m_ops[v_pos][2], v_maxpoints;
			WHEN 'M' THEN
				RETURN QUERY EXECUTE replace(replace(replace(v_aggqry[2], '@@COLUMN@@', pg_catalog.quote_ident(v_m_ops[v_pos][4])), '@@TABLE@@', pg_catalog.quote_ident(v_m_ops[v_pos][3])), '@@CONDITION@@', v_m_ops[v_pos][6])  USING v_aggspan, v_s_time, v_m_ops[v_pos][10], v_e_time, v_m_ops[v_pos][1], v_m_ops[v_pos][2], v_maxpoints;
			WHEN 'm' THEN
				RETURN QUERY EXECUTE replace(replace(replace(v_aggqry[3], '@@COLUMN@@', pg_catalog.quote_ident(v_m_ops[v_pos][4])), '@@TABLE@@', pg_catalog.quote_ident(v_m_ops[v_pos][3])), '@@CONDITION@@', v_m_ops[v_pos][6])  USING v_aggspan, v_s_time, v_m_ops[v_pos][10], v_e_time, v_m_ops[v_pos][1], v_m_ops[v_pos][2], v_maxpoints;
			ELSE
				RETURN QUERY EXECUTE replace(replace(replace(v_aggqry[4], '@@COLUMN@@', pg_catalog.quote_ident(v_m_ops[v_pos][4])), '@@TABLE@@', pg_catalog.quote_ident(v_m_ops[v_pos][3])), '@@CONDITION@@', v_m_ops[v_pos][6])  USING v_aggspan, v_s_time, v_m_ops[v_pos][10], v_e_time, v_m_ops[v_pos][1], v_m_ops[v_pos][2], v_maxpoints,  v_m_ops[v_pos][9];
			END CASE;
		END IF;
	END LOOP;

END
$$ LANGUAGE 'plpgsql';

COMMIT TRANSACTION;
