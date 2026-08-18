SELECT
    pc.internal_name AS metric, pc.display_name AS name,
    pc.id AS metric_id, pc.unit_of_value AS unit,
    pc.calculate_pit AS pit, pc.discard_history AS discard,
    pc.pit_by_default AS pit_def,
    (
        SELECT count(internal_name)::int FROM pem.probe_column
        WHERE classification = 'k' AND NOT internal_name IN
            ('agent_id', 'server_id', 'database_name', 'schema_name',
            'table_name', 'index_name', 'view_name', 'sequence_name',
            'function_name', 'package_name', 'function_type',
            'arg_types', 'cluster_name', 'username', 'client_addr',
            'client_port')
            AND probe_id = ptv.probe_id
    ) AS sub_count
FROM
    pem.probe_target_view ptv, pem.probe_column pc
WHERE
    ptv.probe_id = pc.probe_id
    AND ptv.agent_id = (%s)::int
    AND ptv.applies_to_id = (%s)::int4 {{ data.cond }}
    AND ptv.parameter_value_list IN ({{ data.in_string }})
    AND ptv.discard_history != 't'
    AND pc.classification != 'k'
    AND is_graphable = true
ORDER BY pc.display_name;