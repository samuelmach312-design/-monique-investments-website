SELECT
    s.id,
    COALESCE(so.server_group_id, s.group_id) AS group_id,
    a.agent_id AS agent_id,
    ag.description AS agent_name,
    s.description AS description,
    s.server AS host,
    s.port AS port,
    s.database AS database,
    i.version_string AS version,
    s.serviceid AS service_id,
    s.is_remote_monitoring,
    s.active,
    database_storage.db_details,
    tablespace_storage.tablespace_details,
    json_build_object(
        'database_count', COALESCE(database_counts.num_databases, 0),
        'table_count', COALESCE(table_counts.num_tables, 0),
        'view_count', COALESCE(views_counts.num_views, 0),
        'function_count', COALESCE(function_counts.num_functions, 0),
        'index_count', COALESCE(index_counts.num_indexes, 0),
        'extension_count', COALESCE(extension_counts.num_extensions, 0),
        'foreign_key_count', COALESCE(foreign_key_counts.num_foreign_keys, 0),
        'sequence_count', COALESCE(sequence_counts.num_sequences, 0),
        'tablespace_count', COALESCE(tablespace_counts.num_tablespaces, 0),
        'schema_count', COALESCE(schema_counts.num_schemas, 0)
    ) ::json AS object_count,
    db_objects.db_objects_stats
FROM
    pem.server s
    LEFT JOIN pem.agent_server_binding a ON a.server_id = s.id
    LEFT JOIN pem.server_option so ON so.server_id = s.id AND so.pem_user = (%s)::text
    LEFT JOIN pemdata.server_info i ON i.server_id = s.id
    LEFT JOIN pem.agent ag ON ag.id = a.agent_id

    LEFT JOIN (
        SELECT server_id, ARRAY_AGG(db_details)::json[] AS db_details
        FROM (
            SELECT server_id, CAST(
                '{"database_name":"' || database_name || '", "database_size_mb":"' || database_size_mb ||
                '", "tablespace_name":"' || tablespace_name ||
                '", "recorded_time":"' || recorded_time || '"}' AS JSON
            ) AS db_details
            FROM pemdata.database_size
            WHERE database_name NOT IN ('template0', 'template1')
            GROUP BY server_id, database_name
        ) AS db_storage GROUP BY server_id
    ) AS database_storage ON s.id = database_storage.server_id

    LEFT JOIN (
        SELECT server_id, ARRAY_AGG(tablespace_details)::json[] AS tablespace_details
        FROM (
            SELECT server_id, CAST(
                '{"tablespace_name":"' || tablespace_name || '", "tablespace_size_mb":"' || tablespace_size_mb ||
                '", "recorded_time":"' || recorded_time || '"}' AS JSON
            ) AS tablespace_details
            FROM pemdata.tablespace_size
            GROUP BY server_id, tablespace_name
        ) AS table_storage GROUP BY server_id
    ) AS tablespace_storage ON s.id = tablespace_storage.server_id

    LEFT JOIN (
        SELECT server_id, COUNT(*) AS num_indexes
        FROM pemdata.oc_index
        GROUP BY server_id
    ) AS index_counts ON s.id = index_counts.server_id

    LEFT JOIN (
        SELECT server_id, COUNT(*) AS num_tables
        FROM pemdata.oc_table
        GROUP BY server_id
    ) AS table_counts ON s.id = table_counts.server_id

    LEFT JOIN (
        SELECT server_id, COUNT(*) AS num_databases
        FROM pemdata.oc_database
        GROUP BY server_id
    ) AS database_counts ON s.id = database_counts.server_id

    LEFT JOIN (
        SELECT server_id, COUNT(*) AS num_extensions
        FROM pemdata.oc_extension
        GROUP BY server_id
    ) AS extension_counts ON s.id = extension_counts.server_id

    LEFT JOIN (
        SELECT server_id, COUNT(*) AS num_foreign_keys
        FROM pemdata.oc_foreign_key
        GROUP BY server_id
    ) AS foreign_key_counts ON s.id = foreign_key_counts.server_id

    LEFT JOIN (
        SELECT server_id, COUNT(*) AS num_functions
        FROM pemdata.oc_function
        GROUP BY server_id
    ) AS function_counts ON s.id = function_counts.server_id

    LEFT JOIN (
        SELECT server_id, COUNT(*) AS num_schemas
        FROM pemdata.oc_schema
        GROUP BY server_id
    ) AS schema_counts ON s.id = schema_counts.server_id

    LEFT JOIN (
        SELECT server_id, COUNT(*) AS num_sequences
        FROM pemdata.oc_sequence
        GROUP BY server_id
    ) AS sequence_counts ON s.id = sequence_counts.server_id

    LEFT JOIN (
        SELECT server_id, COUNT(*) AS num_tablespaces
        FROM pemdata.oc_tablespace
        GROUP BY server_id
    ) AS tablespace_counts ON s.id = tablespace_counts.server_id

    LEFT JOIN (
        SELECT server_id, COUNT(*) AS num_views
        FROM pemdata.oc_views
        GROUP BY server_id
    ) AS views_counts ON s.id = views_counts.server_id
    LEFT JOIN (
    SELECT
        asb.agent_id,
        ARRAY_AGG(
            json_build_object(
                'db_hash', sha256((COALESCE(combined.database_name, '') || now()::timestamp)::bytea)::text,
                'schema_hash', sha256((COALESCE(combined.schema_name, '') || now()::timestamp)::bytea)::text,
                'tables', combined.tables,
                'indexes', combined.indexes
            )
        ) AS db_objects_stats
    FROM pem.agent_server_binding asb
    JOIN (
        SELECT
            COALESCE(tb.server_id, idx.server_id) AS server_id,
            COALESCE(tb.database_name, idx.database_name) AS database_name,
            COALESCE(tb.schema_name, idx.schema_name) AS schema_name,
            tb.tables,
            idx.indexes
        FROM (
            SELECT server_id, database_name, schema_name, COUNT(*) AS tables
            FROM pemdata.oc_table
            GROUP BY server_id, database_name, schema_name
        ) tb
        FULL OUTER JOIN (
            SELECT server_id, database_name, schema_name, COUNT(*) AS indexes
            FROM pemdata.oc_index
            GROUP BY server_id, database_name, schema_name
        ) idx
        ON tb.server_id = idx.server_id
           AND tb.database_name = idx.database_name
           AND tb.schema_name = idx.schema_name
    ) combined
    ON combined.server_id = asb.server_id
    GROUP BY asb.agent_id
    ) db_objects ON db_objects.agent_id = a.agent_id

WHERE s.active = TRUE
ORDER BY s.is_remote_monitoring, s.id;
