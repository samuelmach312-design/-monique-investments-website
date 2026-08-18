SELECT
    t.id, t.metric_id, t.metric_calculate_pit, t.metric_query_type,
    t.metric_object, t.metric, t.agg, t.metric_target_attributes,
    t.metric_target_values, t.metric_display_name, t.probe,
    t.probe_display, t.probe_id,
    CASE WHEN t.metric_query_type = 1 THEN a.description
        ELSE s.description END AS obj,
    CASE WHEN t.metric_query_type = 1 THEN a.active
        ELSE s.active END AS active,
    t.deleted
FROM
    (SELECT
        ((row_number() OVER
        (PARTITION BY a.template_id ORDER BY a.id)) - 1)
             AS id,
        a.metric_id, a.metric_calculate_pit, a.metric_query_type,
        a.metric_object,
        CASE WHEN a.metric_aggregation = 'AVERAGE' THEN 'A'
             WHEN a.metric_aggregation = 'MAXIMUM' THEN 'M'
             WHEN a.metric_aggregation = 'MINIMUM' THEN 'm'
             WHEN a.metric_aggregation = 'FIRST' THEN 'F'
        ELSE 'A' END AS agg,
        a.metric_target_attributes, a.metric_target_values,
        CASE
        WHEN a.metric_calculate_pit = 'x' OR a.metric_calculate_pit = 'f'
            THEN pc.internal_name ELSE pc.internal_name || '_pit'
            END AS metric,
        CASE WHEN a.metric_calculate_pit = 'x' OR
            a.metric_calculate_pit = 'f' THEN pc.display_name
            ELSE pc.display_name || '+' END AS metric_display_name,
        p.internal_name AS probe, p.display_name AS probe_display,
        p.deleted AS deleted,
        pc.probe_id AS probe_id,
        (string_to_array(a.metric_target_values, ','))[1] AS object
    FROM pem.cm_template_metrics a
    LEFT JOIN pem.probe_column pc ON (a.metric_id = pc.id)
    LEFT JOIN pem.probe p ON (pc.probe_id = p.id)
    WHERE a.template_id = (%s)::int4) t
LEFT JOIN pem.server s ON (t.object = s.id::text)
LEFT JOIN pem.agent a ON (t.object = a.id::text)
ORDER BY id;
