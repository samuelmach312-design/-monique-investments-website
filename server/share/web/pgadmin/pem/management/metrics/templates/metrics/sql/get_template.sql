
SELECT
    m.*,
    CASE
    WHEN a.id IS NOT NULL THEN ARRAY[1, a.id]::text[]
    WHEN s.id IS NOT NULL THEN
        CASE
        WHEN s.is_remote_monitoring THEN ARRAY[13, s.id]::text[]
        ELSE ARRAY[1, asb.agent_id, 2, s.id]::text[]
        END ||
        CASE
        WHEN metric_query_type = 2 THEN ARRAY[]::text[]
        WHEN metric_query_type = 3 THEN ARRAY[3, targets[2]]::text[]
        WHEN metric_query_type = 4 THEN ARRAY[3, targets[2], 4, targets[3]]::text[]
        WHEN metric_query_type = 5 THEN ARRAY[3, targets[2], 4, targets[3], 5, targets[4]]::text[]
        WHEN metric_query_type = 7 THEN ARRAY[3, targets[2], 4, targets[3], 7, targets[4]]::text[]
        WHEN metric_query_type = 8 THEN ARRAY[3, targets[2], 4, targets[3], 8, targets[4]]::text[]
        WHEN metric_query_type = 9 THEN
          CASE paths[4]
          WHEN 'package_name'
            THEN ARRAY[3, targets[2], 4, targets[3], 11, targets[4], 9, targets[5] || '(' || targets[7] || ')']::text[]
          ELSE
            ARRAY[3, targets[2], 4, targets[3], 9, targets[4] || '(' || targets[6] || ')']::text[]
          END
        WHEN metric_query_type = 12 THEN ARRAY[3, targets[2], 4, targets[3], 12, targets[12]]::text[]
        WHEN metric_query_type = 14 THEN ARRAY[3, targets[2], 4, targets[3], 14, targets[12]]::text[]
        ELSE
          CASE WHEN metric_query_type = 1 THEN ARRAY[]::text[]
          ELSE
            CASE paths[4]
            WHEN 'package_name'
              THEN ARRAY[3, targets[2], 4, targets[3], 11, targets[4], metric_query_type, targets[5] || '(' || targets[7] || ')']::text[]
            ELSE
              ARRAY[3, targets[2], 4, targets[3], metric_query_type, targets[4] || '(' || targets[6] || ')']::text[]
            END
          END
        END
    END object_path,
    CASE paths[1]
    WHEN 'agent_id' THEN a.id IS NOT NULL
    WHEN 'server_id' THEN s.id IS NOT NULL AND
        CASE WHEN paths[2] = 'database_name' THEN EXISTS(SELECT ocd.database_name FROM pemdata.oc_database ocd WHERE ocd.database_name = targets[2] AND ocd.server_id::text = targets[1]) AND
            CASE
            WHEN paths[3] = 'schema_name' THEN EXISTS(SELECT ocs.schema_name FROM pemdata.oc_schema ocs WHERE ocs.server_id::text = targets[1] AND ocs.database_name = targets[2] AND ocs.schema_name::text = targets[3]) AND
                CASE paths[4]
                WHEN 'table_name' THEN EXISTS(SELECT oct.table_name FROM pemdata.oc_table oct WHERE oct.server_id::text = targets[1] AND oct.database_name = targets[2] AND oct.schema_name::text = targets[3] AND oct.table_name = targets[4])
                WHEN 'index_name' THEN EXISTS(SELECT oct.index_name FROM pemdata.oc_index oct WHERE oct.server_id::text = targets[1] AND oct.database_name = targets[2] AND oct.schema_name::text = targets[3] AND oct.index_name = targets[4])
                WHEN 'view_name' THEN EXISTS(SELECT oct.view_name FROM pemdata.oc_views oct WHERE oct.server_id::text = targets[1] AND oct.database_name = targets[2] AND oct.schema_name::text = targets[3] AND oct.view_name = targets[4])
                WHEN 'sequence_name' THEN EXISTS(SELECT oct.sequence_name FROM pemdata.oc_sequence oct WHERE oct.server_id::text = targets[1] AND oct.database_name = targets[2] AND oct.schema_name::text = targets[3] AND oct.sequence_name = targets[4])
                WHEN 'function_name' THEN EXISTS(SELECT oct.function_name FROM pemdata.oc_function oct WHERE oct.server_id::text = targets[1] AND oct.database_name = targets[2] AND oct.schema_name::text = targets[3] AND oct.function_name = targets[4])
                ELSE TRUE
                END
            ELSE TRUE
            END
        ELSE TRUE
        END
    ELSE FALSE
    END object_exists
FROM (
    SELECT
        t.start_date AS start_time, t.end_date AS end_time,
        t.output_value as destination_file, t.historical_days,
        t.extrapolated_days, t.threshold_index, t.threshold_opr,
        t.threshold_value,
        CASE WHEN t.individual_report = 'false' THEN 0 ELSE 1 END AS chart_style,
        CASE WHEN t.time_period = 'START_DATE_TO_END_DATE' THEN 0 WHEN t.time_period = 'START_DATE_TO_THREHOLD' THEN 1 WHEN t.time_period = 'HISTORIC_DATE_TO_EXTRAPOLATED_DATE' THEN 2 ELSE 3 END AS time_period,
        CASE WHEN t.report_type = 'GRAPH' THEN 0 WHEN t.report_type = 'TABLE' THEN 1 ELSE 2 END AS chart_type,
        CASE WHEN t.output_loc = 'NEW_TAB' THEN 0 WHEN t.output_loc = 'PREV_TAB' THEN 0 ELSE 1 END AS download_file,
        tm.metric_id, tm.metric_name as metric, tm.metric_disp_name as met_label, tm.metric_agent_id, tm.metric_target_attributes as met_keys, tm.metric_target_values as met_values, tm.metric_calculate_pit as metric_pit,
        CASE WHEN tm.metric_aggregation = 'AVERAGE' THEN 'AVG' WHEN tm.metric_aggregation = 'MINIMUM' THEN 'MIN' WHEN tm.metric_aggregation = 'MAXIMUM' THEN 'MAX' ELSE 'FIRST' END AS aggregation,
        string_to_array(tm.metric_target_attributes, ',') AS met_targets, tm.metric_unit, tm.metric_server_type, tm.metric_query_type, tm.metric_object,
        string_to_array(tm.metric_target_attributes, ',') AS paths,
        pem.db_escaped_string_to_array(tm.metric_target_values, '"') AS targets
    FROM pem.cm_template t, pem.cm_template_metrics tm
    WHERE t.id=tm.template_id and t.id=(%s)::int4
    ) m
    LEFT JOIN pem.avail_agents a ON (
        m.paths[1]::text = 'agent_id' AND a.id::text = m.targets[1]
    )
    LEFT JOIN pem.avail_servers s ON (
        m.paths[1]::text = 'server_id' AND s.id::text = m.targets[1]
    )
    LEFT JOIN pem.agent_server_binding asb ON (s.id IS NOT NULL AND asb.server_id = s.id)