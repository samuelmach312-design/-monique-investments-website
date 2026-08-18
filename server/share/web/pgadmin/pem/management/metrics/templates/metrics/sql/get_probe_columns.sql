SELECT array_agg(pg_catalog.quote_ident(pc.internal_name))
FROM
    pem.probe_column pc
LEFT JOIN
    pem.probe p ON (p.id = pc.probe_id)
WHERE pc.classification = 'k'
    AND NOT
    CASE
        WHEN p.target_type_id = 100 THEN pc.internal_name IN ('agent_id')
        WHEN p.target_type_id = 200 AND p.applies_to_id = 200 THEN
            pc.internal_name IN ('server_id')
        WHEN p.applies_to_id = 300 THEN
            pc.internal_name IN ('database_name')
        WHEN p.applies_to_id = 400 THEN
            pc.internal_name IN ('database_name', 'schema_name')
        WHEN p.applies_to_id = 500 THEN
            pc.internal_name IN ('database_name', 'schema_name',
                'table_name')
        WHEN p.applies_to_id = 600 THEN
            pc.internal_name IN ('database_name', 'schema_name',
                'index_name')
        WHEN p.applies_to_id = 700 THEN
            pc.internal_name IN ('database_name', 'schema_name',
                'sequence_name')
        WHEN p.applies_to_id = 800 THEN
            pc.internal_name IN ('database_name', 'schema_name',
                'function_name', 'package_name', 'function_type',
                'arg_types')
        WHEN p.applies_to_id = 900 THEN
            pc.internal_name IN ('database_name', 'schema_name',
            'view_name')
        ELSE false
    END
    AND pc.probe_id = (%s)::int4;