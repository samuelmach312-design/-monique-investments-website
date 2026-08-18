SELECT
    p.internal_name AS probe_name, p.id AS probe_id,
    p.is_system_probe,
    p.display_name AS probe_display,
    pc.id AS probe_col_id, pc.internal_name AS probe_col_name,
    pc.display_name AS probe_col_display,
    pc.pit AS probe_col_pit, p.applies_to_id = 800 AS is_function_probe,
    p.applies_to_id AS applies_to_id, p.deleted AS deleted,
    p.target_type_id AS probe_target_type, p.probe_key_list AS probe_key_list
FROM (SELECT
            probe_id, id, internal_name,
            CASE WHEN is_graphable AND NOT pit_by_default
                 THEN display_name || '+' ELSE display_name
                END AS display_name,
            CASE WHEN NOT is_graphable THEN 'x'
                    ELSE 'f'
            END AS pit
    FROM pem.probe_column
    WHERE probe_id = ANY(SELECT id FROM pem.probe
            WHERE internal_name = ANY((%(iname)s)::text[]))
    UNION ALL
    SELECT
        probe_id, id, internal_name || '_pit' AS probe_col_name,
        display_name, 't' AS pit
    FROM pem.probe_column
    WHERE probe_id = ANY(SELECT id FROM pem.probe
            WHERE internal_name = ANY((%(iname)s)::text[]))
            AND is_graphable AND NOT pit_by_default AND calculate_pit) pc
    LEFT JOIN pem.probe p ON (p.id = pc.probe_id)
ORDER BY probe_name, probe_col_name;
