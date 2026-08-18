/***************************************************************************
 *
 * Postgres Enterprise Manager
 *
 * Copyright (C) 2010 - 2025, EnterpriseDB Corporation. All rights reserved.
 *
 ***************************************************************************/

-- NOTE: This sql file is responsible for PEM 10.0.0 schema upgrade.

BEGIN TRANSACTION;
    CREATE 
    OR REPLACE FUNCTION pem.schema_version() 
    RETURNS integer AS 'SELECT 202503241::integer;' LANGUAGE 'sql' IMMUTABLE;
    COMMENT ON FUNCTION pem.schema_version() 
    IS 'Returns the version number of the PEM schema';

    -- Modifying the pem.chart_func table to support psycopg3

    -- Storage Details Query
    UPDATE pem.chart_func 
    SET func = $sql$
        SELECT 
            $$Total Database Size : $$ || (
                SELECT 
                    pem.pretty_size(database_size_mb) 
                FROM 
                    pemdata.database_size 
                WHERE 
                    database_size.server_id = %(server_id)s::int4 
                    AND database_size.database_name = %(database)s::text
            ) || $$ & #183; $$ || $$ Total Tables: $$ || (
                SELECT 
                    count(table_name) 
                FROM 
                    pemdata.table_size 
                WHERE 
                    server_id = %(server_id)s::int4 
                    AND database_name = %(database)s::text 
                    AND (
                        %(show_system_objects)s::boolean 
                        OR (
                            schema_name NOT IN (
                                $$pg_catalog$$, $$pg_toast$$, $$information_schema$$, $$sys$$
                            )
                        )
                    )
            ) || $$ & #183; $$ || $$ Total Indexes: $$ || (
                SELECT 
                    count(index_name) 
                FROM 
                    pemdata.index_size 
                WHERE 
                    server_id = %(server_id)s::int4 
                    AND database_name = %(database)s::text 
                    AND (
                        %(show_system_objects)s::boolean 
                        OR (
                            schema_name NOT IN (
                                $$pg_catalog$$, $$pg_toast$$, $$information_schema$$, $$sys$$
                            )
                        )
                    )
            ) 
    $sql$ 
    WHERE id = 9;

    -- Storage Query
    UPDATE pem.chart_func 
    SET func = $sql$ 
        WITH restricted_db_schemas AS (
            SELECT 
                s.id, 
                pem.db_escaped_string_to_array(
                    COALESCE(
                        o.schema_restriction, oa.schema_restriction
                    )
                ) AS rest_schemas 
            FROM 
                pem.server s 
                LEFT OUTER JOIN pg_catalog.pg_roles owner 
                    ON (owner.oid = s.owner) 
                LEFT OUTER JOIN pem.database_option o 
                    ON (
                        s.id = o.server_id 
                        AND o.pem_user = current_user 
                        AND o.database = %(database)s::text
                    ) 
                LEFT OUTER JOIN pem.database_option oa 
                    ON (
                        o.server_id IS NULL 
                        AND s.id = oa.server_id 
                        AND oa.database = %(database)s::text 
                        AND (
                            owner.rolname = oa.pem_user 
                            OR (
                                owner.rolname IS NULL 
                                AND oa.pem_user IS NULL
                            )
                        )
                    ) 
            WHERE 
                s.id = %(server_id)s::int4
        ) 
        SELECT 
            t.schema_name || '.' || t.table_name AS object_name, 
            t.table_size_mb AS "Object Size" 
        FROM 
            pemdata.table_size t 
            LEFT OUTER JOIN restricted_db_schemas rds 
                ON (t.server_id = rds.id) 
        WHERE 
            t.server_id = %(server_id)s::int4 
            AND t.database_name = %(database)s::text 
            AND (
                rds.rest_schemas IS NULL 
                OR t.schema_name = ANY (rds.rest_schemas)
            ) 
            AND (
                %(show_system_objects)s::boolean 
                OR (
                    t.schema_name NOT IN (
                        $$pg_catalog$$, $$pg_toast$$, $$information_schema$$, $$sys$$
                    ) 
                    AND t.schema_name !~ $$pg_temp | pg_toast$$
                )
            ) 
        UNION 
        SELECT 
            i.index_name AS object_name, 
            i.index_size_mb AS "Object Size" 
        FROM 
            pemdata.index_size i 
            LEFT OUTER JOIN restricted_db_schemas rds 
                ON (i.server_id = rds.id) 
        WHERE 
            i.server_id = %(server_id)s::int4 
            AND i.database_name = %(database)s::text 
            AND (
                rds.rest_schemas IS NULL 
                OR i.schema_name = ANY (rds.rest_schemas)
            ) 
            AND (
                %(show_system_objects)s::boolean 
                OR (
                    i.schema_name NOT IN (
                        $$pg_catalog$$, $$pg_toast$$, $$information_schema$$, $$sys$$
                    ) 
                    AND i.schema_name !~ $$pg_temp | pg_toast$$
                )
            ) 
        ORDER BY 
            "Object Size" DESC 
        LIMIT 
            5 
    $sql$ 
    WHERE id = 10;

    -- Users Activity Query
    UPDATE pem.chart_func 
    SET func = $sql$
        SELECT 
            o_idx, 
            o_label, 
            'Date(' || (EXTRACT(EPOCH FROM o_aggtime) * 1000)::numeric(40, 0)::text || ')', 
            o_aggval 
        FROM 
            pem.generate_conn_overview_chart_data(
                %(chart_id)s::int4, 
                %(dashboard_id)s::int4, 
                %(server_id)s::int4, 
                %(database)s::text, 
                %(start_time)s::timestamptz, 
                %(end_time)s::timestamptz
            ) 
        ORDER BY 
            o_idx, 
            o_aggtime 
    $sql$ 
    WHERE id = 11;

    -- Connection Details Query
    UPDATE pem.chart_func 
    SET func = $SQL$
        SELECT 
            $$Max Connections : $$ || setting 
        FROM 
            pemdata.settings 
        WHERE 
            name = 'max_connections' 
            AND server_id = %(server_id)s::int4 
    $SQL$ 
    WHERE id = 12;

    -- Connection Overview Query
    UPDATE pem.chart_func 
    SET func = $SQL$
        SELECT 
            (
                SUM(numbackends) - SUM(idle_backends)
            )::bigint AS "Active Connections", 
            SUM(idle_backends) AS "Idle Connections" 
        FROM 
            pemdata.database_statistics 
        WHERE 
            server_id = %(server_id)s::int4 
            AND database_name = %(database)s::text 
        GROUP BY 
            recorded_time 
        ORDER BY 
            recorded_time DESC 
    $SQL$ 
    WHERE id = 13;

    -- Database I/O Hit/Read Details Query
    UPDATE pem.chart_func 
    SET func = $SQL$
        SELECT 
            $$Commits : $$ || COALESCE(xact_commit::text, $$Unknown$$) || $$ & #183; $$ ||
            $$ Rollbacks : $$ || COALESCE(xact_rollback::text, $$Unknown$$) 
        FROM 
            pemdata.database_statistics 
        WHERE 
            server_id = %(server_id)s::int4 
            AND database_name = %(database)s::text 
    $SQL$ 
    WHERE id = 18;

    -- Rows Activity Details Query
    UPDATE pem.chart_func 
    SET func = $SQL$
        SELECT 
            $$Transactions running for more than $$ || (
                SELECT 
                    value 
                FROM 
                    pem.config 
                WHERE 
                    param = $$long_running_transaction_minutes$$
            ) || $$ minutes : $$ || count(*) 
        FROM 
            pemdata.session_info 
        WHERE 
            now() - query_start > (
                SELECT 
                    (value || $$ minutes$$)::interval 
                FROM 
                    pem.config 
                WHERE 
                    param = $$long_running_transaction_minutes$$
            ) 
            AND not is_idle 
            AND server_id = %(server_id)s::int4 
            AND database_name = %(database)s::text 
    $SQL$ 
    WHERE id = 21;

    -- Check-points Details Query
    UPDATE pem.chart_func 
    SET func = $SQL$
        SELECT 
            $$Buffers Written by Checkpoints : $$ || COALESCE(buffers_checkpoint::text, $$Unknown$$) 
        FROM 
            pemdata.background_writer_statistics 
        WHERE 
            server_id = %(server_id)s::int4 
    $SQL$ 
    WHERE id = 22;

    -- Top 5 Scanned Tables Query
    UPDATE pem.chart_func 
    SET func = $SQL$
        WITH restricted_db_schemas AS (
            SELECT 
                s.id, 
                pem.db_escaped_string_to_array(
                    COALESCE(
                        o.schema_restriction, oa.schema_restriction
                    )
                ) AS rest_schemas 
            FROM 
                pem.server s 
                LEFT OUTER JOIN pg_catalog.pg_roles owner 
                    ON (owner.oid = s.owner) 
                LEFT OUTER JOIN pem.database_option o 
                    ON (
                        s.id = o.server_id 
                        AND o.pem_user = current_user 
                        AND o.database = %(database)s::text
                    ) 
                LEFT OUTER JOIN pem.database_option oa 
                    ON (
                        o.server_id IS NULL 
                        AND s.id = oa.server_id 
                        AND oa.database = %(database)s::text 
                        AND (
                            owner.rolname = oa.pem_user 
                            OR (
                                owner.rolname IS NULL 
                                AND oa.pem_user IS NULL
                            )
                        )
                    ) 
            WHERE 
                s.id = %(server_id)s::int4
        ) 
        SELECT 
            t.schema_name || $$.$$ || t.table_name AS "Table Name", 
            t.seq_scan AS "Scans" 
        FROM 
            pemdata.table_statistics t 
            LEFT OUTER JOIN restricted_db_schemas rds 
                ON (t.server_id = rds.id) 
        WHERE 
            t.server_id = %(server_id)s::int4 
            AND t.database_name = %(database)s::text 
            AND (
                rds.rest_schemas IS NULL 
                OR t.schema_name = ANY (rds.rest_schemas)
            ) 
            AND (
                %(show_system_objects)s::boolean 
                OR (
                    t.schema_name NOT IN (
                        $$pg_catalog$$, $$pg_toast$$, $$information_schema$$, $$sys$$
                    ) 
                    AND t.schema_name !~ $$pg_temp | pg_toast$$
                )
            ) 
        ORDER BY 
            "Scans" DESC 
        LIMIT 
            5 
    $SQL$ 
    WHERE id = 24;

    -- Top 5 Scanned Indexes Query
    UPDATE pem.chart_func 
    SET func = $SQL$
        WITH restricted_db_schemas AS (
            SELECT 
                s.id, 
                pem.db_escaped_string_to_array(
                    COALESCE(
                        o.schema_restriction, oa.schema_restriction
                    )
                ) AS rest_schemas 
            FROM 
                pem.server s 
                LEFT OUTER JOIN pg_catalog.pg_roles owner 
                    ON (owner.oid = s.owner) 
                LEFT OUTER JOIN pem.database_option o 
                    ON (
                        s.id = o.server_id 
                        AND o.pem_user = current_user 
                        AND o.database = %(database)s::text
                    ) 
                LEFT OUTER JOIN pem.database_option oa 
                    ON (
                        o.server_id IS NULL 
                        AND s.id = oa.server_id 
                        AND oa.database = %(database)s::text 
                        AND (
                            owner.rolname = oa.pem_user 
                            OR (
                                owner.rolname IS NULL 
                                AND oa.pem_user IS NULL
                            )
                        )
                    ) 
            WHERE 
                s.id = %(server_id)s::int4
        ) 
        SELECT 
            i.index_name AS "Index Name", 
            i.idx_scan AS "Scans" 
        FROM 
            pemdata.index_statistics i 
            LEFT OUTER JOIN restricted_db_schemas rds 
                ON (i.server_id = rds.id) 
        WHERE 
            i.server_id = %(server_id)s::int4 
            AND i.database_name = %(database)s::text 
            AND (
                rds.rest_schemas IS NULL 
                OR i.schema_name = ANY (rds.rest_schemas)
            ) 
            AND (
                %(show_system_objects)s::boolean 
                OR (
                    i.schema_name NOT IN (
                        $$pg_catalog$$, $$pg_toast$$, $$information_schema$$, $$sys$$
                    ) 
                    AND i.schema_name !~ $$pg_temp | pg_toast$$
                )
            ) 
        ORDER BY 
            "Scans" DESC 
        LIMIT 
            5 
    $SQL$ 
    WHERE id = 25;

    -- Memory Activity Details Query
    UPDATE pem.chart_func 
    SET func = $SQL$
        WITH shared_buf_hit AS (
            SELECT 
                (
                    CASE WHEN SUM(blks_hit) + SUM(blks_read) = 0 
                        THEN 0 
                        ELSE SUM(blks_hit) * 100 / (SUM(blks_hit) + SUM(blks_read)) 
                    END
                )::numeric(30, 2) AS shared_hit 
            FROM 
                pemdata.database_statistics d 
            WHERE 
                server_id = %(server_id)s::int4
        ) 
        SELECT 
            $$Hit Rate : $$ || shared_hit || $$ & #183; Shared Buffer Size: $$ ||
            (setting)::bigint * (
                CASE WHEN POSITION($$kb$$ IN LOWER(unit)) = 0 
                OR SPLIT_PART(unit, $$kB$$, 1) IN (NULL, $$$$) 
                    THEN 1 
                    ELSE SPLIT_PART(unit, $$kB$$, 1)::int 
                END
            ) / 1024 
        FROM 
            pemdata.settings s, 
            shared_buf_hit 
        WHERE 
            s.server_id = %(server_id)s::int4 
            AND s.name = $$shared_buffers$$ 
    $SQL$ 
    WHERE id = 26;

    -- Memory Configuration Query
    UPDATE pem.chart_func 
    SET func = $SQL$
        SELECT 
            name, 
            (
                CAST(setting AS float) * (
                    (
                        CASE WHEN POSITION($$kb$$ IN LOWER(unit)) = 0 
                        OR SPLIT_PART(unit, $$kB$$, 1) IN (NULL, $$$$) 
                            THEN 1 
                            ELSE SPLIT_PART(unit, $$kB$$, 1)::float 
                        END
                    ) / 1024
                )
            )::numeric(12, 4) 
        FROM 
            pemdata.settings 
        WHERE 
            server_id = %(server_id)s::int4 
            AND name = $$wal_buffers$$ 
        UNION 
        SELECT 
            name, 
            (
                CAST(setting AS float) * (
                    (
                        CASE WHEN POSITION($$kb$$ IN LOWER(unit)) = 0 
                        OR SPLIT_PART(unit, $$kB$$, 1) IN (NULL, $$$$) 
                            THEN 1 
                            ELSE SPLIT_PART(unit, $$kB$$, 1)::float 
                        END
                    ) / 1024
                )
            )::numeric(12, 4) 
        FROM 
            pemdata.settings 
        WHERE 
            server_id = %(server_id)s::int4 
            AND name = $$shared_buffers$$ 
        UNION 
        SELECT 
            name, 
            (
                CAST(setting AS float) * (
                    (
                        CASE WHEN POSITION($$kb$$ IN LOWER(unit)) = 0 
                        OR SPLIT_PART(unit, $$kB$$, 1) IN (NULL, $$$$) 
                            THEN 1 
                            ELSE SPLIT_PART(unit, $$kB$$, 1)::float 
                        END
                    ) / 1024
                )
            )::numeric(12, 4) 
        FROM 
            pemdata.settings 
        WHERE 
            server_id = %(server_id)s::int4 
            AND name = $$work_mem$$ 
    $SQL$ 
    WHERE id = 28;

    -- Host Memory Information Query
    UPDATE pem.chart_func 
    SET func = $SQL$
    SELECT 
        total_ram_memory_mb - free_ram_memory_mb AS Used, 
        free_ram_memory_mb AS Free 
    FROM 
        pemdata.memory_usage 
    WHERE 
        agent_id = %(agent_id)s::int4
    $SQL$ 
    WHERE id = 30;

    -- Top 5 Largest Tables Query
    UPDATE pem.chart_func 
    SET func = $SQL$
    WITH restricted_db_schemas AS (
        SELECT 
            s.id, 
            pem.db_escaped_string_to_array(
                COALESCE(o.schema_restriction, oa.schema_restriction)
            ) AS rest_schemas 
        FROM 
            pem.server s 
        LEFT OUTER JOIN pg_catalog.pg_roles owner ON (owner.oid = s.owner) 
        LEFT OUTER JOIN pem.database_option o ON (
            s.id = o.server_id 
            AND o.pem_user = current_user 
            AND o.database = %(database)s::text
        ) 
        LEFT OUTER JOIN pem.database_option oa ON (
            o.server_id IS NULL 
            AND s.id = oa.server_id 
            AND oa.database = %(database)s::text 
            AND (
                owner.rolname = oa.pem_user 
                OR (
                    owner.rolname IS NULL 
                    AND oa.pem_user IS NULL
                )
            )
        ) 
        WHERE 
            s.id = %(server_id)s::int4
    )
    SELECT 
        t.schema_name || $$.$$ || t.table_name AS object_name, 
        t.table_size_mb AS "Object Size" 
    FROM 
        pemdata.table_size t 
    LEFT OUTER JOIN restricted_db_schemas rds ON (t.server_id = rds.id) 
    WHERE 
        t.server_id = %(server_id)s::int4 
        AND t.database_name = %(database)s::text 
        AND (
            rds.rest_schemas IS NULL 
            OR t.schema_name = ANY(rds.rest_schemas)
        ) 
        AND (
            %(show_system_objects)s::boolean 
            OR (
                t.schema_name NOT IN (
                    $$pg_catalog$$, $$pg_toast$$, $$information_schema$$, $$sys$$
                ) 
                AND t.schema_name !~ $$pg_temp | pg_toast$$
            )
        ) 
    ORDER BY 
        2 DESC 
    LIMIT 
        5
    $SQL$ 
    WHERE id = 31;

    -- Top 5 Largest Indexes Query
    UPDATE pem.chart_func 
    SET func = $SQL$
    WITH restricted_db_schemas AS (
        SELECT 
            s.id, 
            pem.db_escaped_string_to_array(
                COALESCE(o.schema_restriction, oa.schema_restriction)
            ) AS rest_schemas 
        FROM 
            pem.server s 
        LEFT OUTER JOIN pg_catalog.pg_roles owner ON (owner.oid = s.owner) 
        LEFT OUTER JOIN pem.database_option o ON (
            s.id = o.server_id 
            AND o.pem_user = current_user 
            AND o.database = %(database)s::text
        ) 
        LEFT OUTER JOIN pem.database_option oa ON (
            o.server_id IS NULL 
            AND s.id = oa.server_id 
            AND oa.database = %(database)s::text 
            AND (
                owner.rolname = oa.pem_user 
                OR (
                    owner.rolname IS NULL 
                    AND oa.pem_user IS NULL
                )
            )
        ) 
        WHERE 
            s.id = %(server_id)s::int4
    )
    SELECT 
        i.index_name AS object_name, 
        i.index_size_mb AS "Object Size" 
    FROM 
        pemdata.index_size i 
    LEFT OUTER JOIN restricted_db_schemas rds ON (i.server_id = rds.id) 
    WHERE 
        i.server_id = %(server_id)s::int4 
        AND i.database_name = %(database)s::text 
        AND (
            rds.rest_schemas IS NULL 
            OR i.schema_name = ANY(rds.rest_schemas)
        ) 
        AND (
            %(show_system_objects)s::boolean 
            OR (
                i.schema_name NOT IN (
                    $$pg_catalog$$, $$pg_toast$$, $$information_schema$$, $$sys$$
                ) 
                AND i.schema_name !~ $$pg_temp | pg_toast$$
            )
        ) 
    ORDER BY 
        2 DESC 
    LIMIT 
        5
    $SQL$ 
    WHERE id = 32;

    -- Object Storage Query
    UPDATE pem.chart_func 
    SET func = $SQL$
    WITH restricted_db_schemas AS (
        SELECT 
            s.id, 
            pem.db_escaped_string_to_array(
                COALESCE(o.schema_restriction, oa.schema_restriction)
            ) AS rest_schemas 
        FROM 
            pem.server s 
        LEFT OUTER JOIN pg_catalog.pg_roles owner ON (owner.oid = s.owner) 
        LEFT OUTER JOIN pem.database_option o ON (
            s.id = o.server_id 
            AND o.pem_user = current_user 
            AND o.database = %(database)s::text
        ) 
        LEFT OUTER JOIN pem.database_option oa ON (
            o.server_id IS NULL 
            AND s.id = oa.server_id 
            AND oa.database = %(database)s::text 
            AND (
                owner.rolname = oa.pem_user 
                OR (
                    owner.rolname IS NULL 
                    AND oa.pem_user IS NULL
                )
            )
        ) 
        WHERE 
            s.id = %(server_id)s::int4
    )
    SELECT 
        schema_name AS "Schema", 
        table_name AS "Object", 
        $$Table$$ AS "Object Type", 
        table_size_mb AS "Table Size(MB)", 
        size_of_indexes_mb AS "Index Size(MB)", 
        total_table_size_mb AS "Total(MB)" 
    FROM 
        pemdata.table_size t 
    LEFT OUTER JOIN restricted_db_schemas r ON (t.server_id = r.id) 
    WHERE 
        server_id = %(server_id)s::int4 
        AND database_name = %(database)s::text 
        AND total_table_size_mb != 0 
        AND (
            r.rest_schemas IS NULL 
            OR t.schema_name = ANY(r.rest_schemas)
        ) 
        AND (
            %(show_system_objects)s::boolean 
            OR (
                t.schema_name NOT IN (
                    $$pg_catalog$$, $$pg_toast$$, $$information_schema$$, $$sys$$
                ) 
                AND t.schema_name !~ $$pg_temp | pg_toast$$
            )
        ) 
    UNION 
    SELECT 
        schema_name AS "Schema", 
        index_name AS "Object", 
        $$Index$$ AS "Object Type", 
        NULL AS "Table Size(MB)", 
        index_size_mb AS "Index Size(MB)", 
        index_size_mb AS "Total(MB)" 
    FROM 
        pemdata.index_size i 
    LEFT OUTER JOIN restricted_db_schemas r ON (i.server_id = r.id) 
    WHERE 
        server_id = %(server_id)s::int4 
        AND database_name = %(database)s::text 
        AND index_size_mb IS NOT NULL 
        AND index_size_mb != 0 
        AND (
            r.rest_schemas IS NULL 
            OR i.schema_name = ANY(r.rest_schemas)
        ) 
        AND (
            %(show_system_objects)s::boolean 
            OR (
                i.schema_name NOT IN (
                    $$pg_catalog$$, $$pg_toast$$, $$information_schema$$, $$sys$$
                ) 
                AND i.schema_name !~ $$pg_temp | pg_toast$$
            )
        ) 
    ORDER BY 
        4 DESC 
    LIMIT 
        %(rows_limit)s::int4
    $SQL$ 
    WHERE id = 34;

    -- CPU Stats Details Query
    UPDATE pem.chart_func 
    SET func = $SQL$
    SELECT 
        $$Total Processes : $$ || total_process_count || $$ & #183; Total Threads: $$ || total_thread_count
    FROM 
        pemdata.os_statistics 
    WHERE 
        agent_id = %(agent_id)s::int4
    $SQL$ 
    WHERE id = 35;

    -- Storage Stats Query
    UPDATE pem.chart_func 
    SET func = $SQL$
    SELECT 
        SUM(space_used_mb) AS used, 
        SUM(space_available_mb) AS free 
    FROM 
        pemdata.disk_space 
    WHERE 
        agent_id = %(agent_id)s::int4
    $SQL$ 
    WHERE id = 37;

    -- Memory Stats Details Query
    UPDATE pem.chart_func 
    SET func = $SQL$
    SELECT 
        $$Total : $$ || total_ram_memory_mb || $$MB & #183; Used: $$ || 
        total_ram_memory_mb - free_ram_memory_mb || $$MB & #183; Free: $$ || 
        free_ram_memory_mb || $$MB & #183; Swap Total: $$ || total_swap_memory_mb || 
        $$MB & #183; Swap Used: $$ || total_swap_memory_mb - free_swap_memory_mb || $$MB$$
    FROM 
        pemdata.memory_usage 
    WHERE 
        agent_id = %(agent_id)s::int4
    $SQL$ 
    WHERE id = 38;

    -- Memory Stats Query
    UPDATE pem.chart_func 
    SET func = $sql$
    SELECT 
        o_idx, 
        o_label, 
        'Date(' || (EXTRACT(EPOCH FROM o_aggtime) * 1000)::numeric(40, 0)::text || ')', 
        o_aggval 
    FROM 
        pem.generate_host_memory_chart_data(
            %(chart_id)s::int4, 
            %(dashboard_id)s::int4, 
            %(agent_id)s::int4, 
            %(start_time)s::timestamptz, 
            %(end_time)s::timestamptz
        ) 
    ORDER BY 
        o_idx, 
        o_aggtime
    $sql$ 
    WHERE id = 39;

    -- Host Details Query
    UPDATE pem.chart_func 
    SET func = $SQL$
    SELECT 
        file_system AS "File System", 
        ROUND((size_mb::float / 1024)::numeric, 2) AS "Size (GB)", 
        ROUND((space_used_mb::float / 1024)::numeric, 2) AS "Used (GB)", 
        ROUND((space_available_mb::float / 1024)::numeric, 2) AS "Available (GB)", 
        ROUND((space_used_mb::float * 100 / (size_mb - COALESCE(space_reserved_mb, 0)))::numeric, 2) AS "%% Used", 
        CASE 
            WHEN (device_id IS NOT NULL AND device_id != $$$$) 
            THEN mount_point || $$ ($$ || device_id || $$) $$ 
            ELSE mount_point 
        END AS "Mounted On" 
    FROM 
        pemdata.disk_space 
    WHERE 
        agent_id = %(agent_id)s::int4 
        AND size_mb != 0 
    ORDER BY 
        3::int DESC
    $SQL$ 
    WHERE id = 44;

    -- Network Bandwidth Details Query
    UPDATE pem.chart_func 
    SET func = $SQL$
    SELECT 
        $$Bandwidth : $$ || pg_catalog.array_to_string(
            array_agg(interface_name || $$ - $$ || link_speed_mbps || $$Mb / s$$), 
            $$ & #183; $$
        ) AS network_interface_details 
    FROM 
        pemdata.network_statistics 
    WHERE 
        interface_name NOT ILIKE $$lo%%$$ 
        AND agent_id = %(agent_id)s::int4
    $SQL$ 
    WHERE id = 46;

    -- Shared Buffer Details Query
    UPDATE pem.chart_func 
    SET func = $SQL$
        WITH shared_buf_hit AS (
            SELECT 
                (
                    CASE 
                        WHEN SUM(blks_hit) + SUM(blks_read) = 0 THEN 0 
                        ELSE SUM(blks_hit) * 100 / (SUM(blks_hit) + SUM(blks_read)) 
                    END
                )::numeric(30, 2) AS shared_hit 
            FROM 
                pemdata.database_statistics d 
            WHERE 
                server_id = %(server_id)s::int4
        ) 
        SELECT 
            $$Hit Rate : $$ || shared_hit || $$ & #183; Shared Buffer Size: $$ ||
            (setting)::bigint * (
                CASE 
                    WHEN POSITION(lower($$kB$$) IN lower(unit)) = 0 THEN 1 
                    ELSE SPLIT_PART(unit, $$kB$$, 1)::int 
                END
            ) / 1024 
        FROM 
            pemdata.settings, 
            shared_buf_hit 
        WHERE 
            server_id = %(server_id)s::int4 
            AND name = $$shared_buffers$$
    $SQL$
    WHERE id = 52;

    -- User Activity Details Query
    UPDATE pem.chart_func 
    SET func = $SQL$
        SELECT 
            $$Total Locks : $$ || COUNT(DISTINCT locktype) || $$ & #183; Blocked Sessions: $$ || COUNT(DISTINCT procpid)
        FROM 
            pemdata.lock_info 
        WHERE 
            server_id = %(server_id)s::int4
    $SQL$
    WHERE id = 54;

    -- User Activity Query
    UPDATE pem.chart_func 
    SET func = $sql$
        SELECT 
            o_idx, 
            o_label, 
            'Date(' || (EXTRACT(EPOCH FROM o_aggtime) * 1000)::numeric(40, 0)::text || ')', 
            o_aggval 
        FROM 
            pem.generate_conn_overview_chart_data(
                %(chart_id)s::int4, 
                %(dashboard_id)s::int4, 
                %(server_id)s::int4, 
                NULL::text, 
                %(start_time)s::timestamptz, 
                %(end_time)s::timestamptz
            ) 
        ORDER BY 
            o_idx, 
            o_aggtime
    $sql$
    WHERE id = 55;

    -- Connection Overview Details Query
    UPDATE pem.chart_func 
    SET func = $SQL$
        SELECT 
            $$Max Connections : $$ || COALESCE(setting, $$Unknown$$) 
        FROM 
            pemdata.settings 
        WHERE 
            name = $$max_connections$$ 
            AND server_id = %(server_id)s::int4
    $SQL$
    WHERE id = 56;

    -- Connection Overview Query
    UPDATE pem.chart_func 
    SET func = $SQL$
        SELECT 
            (
                SUM(numbackends) - SUM(idle_backends)
            )::bigint AS "Active Connections", 
            SUM(idle_backends) AS "Idle Connections" 
        FROM 
            pemdata.database_statistics 
        WHERE 
            server_id = %(server_id)s::int4
    $SQL$
    WHERE id = 57;

    -- Databases Analysis Query
    UPDATE pem.chart_func 
    SET func = $SQL$
        WITH restricted_dbs AS (
            SELECT 
                s.id, 
                pem.db_escaped_string_to_array(
                    COALESCE(
                        o.database_restriction, 
                        oa.database_restriction
                    )
                ) AS dbs 
            FROM 
                pem.server s 
            LEFT OUTER JOIN 
                pg_catalog.pg_roles owner ON (owner.oid = s.owner) 
            LEFT OUTER JOIN 
                pem.server_options o ON (
                    s.id = o.server_id 
                    AND o.pem_user = current_user
                ) 
            LEFT OUTER JOIN 
                pem.server_options oa ON (
                    o.server_id IS NULL 
                    AND s.id = oa.server_id 
                    AND (
                        owner.rolname = oa.pem_user 
                        OR (
                            owner.rolname IS NULL 
                            AND oa.pem_user IS NULL
                        )
                    )
                )
        ) 
        SELECT 
            d.database_name AS "Database", 
            d.numbackends AS "Connections", 
            d.xact_commit AS "TX Committed", 
            d.xact_rollback AS "TX Rolled Back", 
            d.blks_hit AS "Blocks Hit", 
            d.blks_read AS "Blocks Read", 
            d.tup_fetched AS "Tuples Fetched", 
            d.tup_returned AS "Tuples Returned", 
            d.tup_inserted AS "Tuples Inserted", 
            d.tup_updated AS "Tuples Updated", 
            d.tup_deleted AS "Tuples Deleted" 
        FROM 
            pemdata.database_statistics d 
        JOIN 
            pemdata.oc_database o ON (
                d.server_id = o.server_id 
                AND d.database_name = o.database_name
            ) 
        LEFT JOIN 
            restricted_dbs r ON (d.server_id = r.id) 
        WHERE 
            o.connections_allowed = TRUE 
            AND d.server_id = %(server_id)s::int4 
            AND (
                %(show_system_objects)s::boolean 
                OR d.database_name NOT IN ($$template0$$, $$template1$$)
            ) 
            AND (
                r.dbs IS NULL 
                OR d.database_name = ANY(r.dbs)
            ) 
        ORDER BY 
            3
    $SQL$
    WHERE id = 61;

    -- Locks Activity Query
    UPDATE pem.chart_func 
    SET func = $SQL$
        WITH restricted_dbs AS (
            SELECT 
                s.id, 
                pem.db_escaped_string_to_array(
                    COALESCE(
                        o.database_restriction, 
                        oa.database_restriction
                    )
                ) AS dbs 
            FROM 
                pem.server s 
            LEFT OUTER JOIN 
                pg_catalog.pg_roles owner ON (owner.oid = s.owner) 
            LEFT OUTER JOIN 
                pem.server_options o ON (
                    s.id = o.server_id 
                    AND o.pem_user = current_user
                ) 
            LEFT OUTER JOIN 
                pem.server_options oa ON (
                    o.server_id IS NULL 
                    AND s.id = oa.server_id 
                    AND (
                        owner.rolname = oa.pem_user 
                        OR (
                            owner.rolname IS NULL 
                            AND oa.pem_user IS NULL
                        )
                    )
                )
        ) 
        SELECT 
            pli.procpid AS "Session Id", 
            psi.usename AS "User Name", 
            (
                psi.client_addr || $$ : $$ || psi.client_port
            ) AS "Source", 
            pli.database_name AS "Database Name", 
            CASE pli.lockgranted 
                WHEN $$f$$ THEN $$Yes$$ 
                ELSE $$No$$ 
            END AS "Blocked", 
            CASE 
                WHEN pli.lockgranted = $$f$$ THEN (
                    SELECT 
                        STRING_AGG(b.procpid::text, $$, $$) 
                    FROM 
                        pemdata.lock_info b 
                    WHERE 
                        b.objid = pli.objid 
                        AND b.objsubid IS NOT DISTINCT FROM pli.objsubid 
                        AND b.objsubsubid IS NOT DISTINCT FROM pli.objsubsubid 
                        AND b.lockgranted = $$t$$
                ) 
                ELSE NULL 
            END AS "Blocked By", 
            pli.locktype AS "Lock Type", 
            pli.objid AS "Object Id", 
            pli.lockmode AS "Mode", 
            CAST(
                DATE_TRUNC($$second$$, psi.xact_start) AS timestamp
            ) AS "Transaction Start" 
        FROM 
            pemdata.lock_info pli 
        JOIN 
            pemdata.session_info psi ON (
                pli.procpid = psi.procpid 
                AND pli.server_id = psi.server_id
            ) 
        LEFT OUTER JOIN 
            restricted_dbs r ON (pli.server_id = r.id) 
        WHERE 
            pli.server_id = %(server_id)s::int4 
            AND (
                %(show_system_objects)s::boolean 
                OR pli.database_name NOT IN ($$template0$$, $$template1$$)
            ) 
            AND (
                r.dbs IS NULL 
                OR pli.database_name = ANY(r.dbs)
            ) 
        ORDER BY 
            3
    $SQL$
    WHERE id = 63;

    -- Number of Session Waits Query
    UPDATE pem.chart_func 
    SET func = $sql$
        SELECT 
            wait_name AS "Wait Name", 
            SUM(wait_count) AS "Total Wait Counts" 
        FROM 
            pemdata.session_waits 
        WHERE 
            server_id = %(server_id)s::int4 
            AND dbname = %(database)s::text 
        GROUP BY 
            wait_name 
        ORDER BY 
            "Total Wait Counts" DESC 
        LIMIT 5
    $sql$
    WHERE id = 64;

    -- Session Wait Details Table Query
    UPDATE pem.chart_func 
    SET func = $sql$
        SELECT 
            usename AS "User", 
            wait_name AS "Wait Name", 
            wait_count AS "Wait Count", 
            (total_wait_time * 1000)::numeric(30, 2) AS "Time (ms)", 
            (
                SELECT 
                    CASE 
                        WHEN SUM(total_wait_time) = 0 THEN 0 
                        ELSE (psw.total_wait_time * 100 / SUM(total_wait_time)) 
                    END 
                FROM 
                    pemdata.session_waits 
                WHERE 
                    server_id = %(server_id)s::int4
                    AND dbname = %(database)s::text
            )::numeric(5, 2) AS "Wait Time (%%)" 
        FROM 
            pemdata.session_waits psw 
        WHERE 
            server_id = %(server_id)s::int4 
            AND dbname = %(database)s::text
    $sql$
    WHERE id = 65;

    -- Session Time Waits Query
    UPDATE pem.chart_func 
    SET func = $sql$
        SELECT 
            wait_name AS "Wait Name", 
            SUM(total_wait_time) * 1000 AS "Total Wait Time" 
        FROM 
            pemdata.session_waits 
        WHERE 
            server_id = %(server_id)s::int4 
            AND dbname = %(database)s::text 
        GROUP BY 
            wait_name 
        ORDER BY 
            "Total Wait Time" DESC 
        LIMIT 5
    $sql$
    WHERE id = 66;

    -- Databases Storage Overview Query
    UPDATE pem.chart_func 
    SET func = $sql$
        WITH restricted_dbs AS (
            SELECT 
                s.id, 
                pem.db_escaped_string_to_array(
                    COALESCE(
                        o.database_restriction, 
                        oa.database_restriction
                    )
                ) AS dbs 
            FROM 
                pem.server s 
            LEFT OUTER JOIN 
                pg_catalog.pg_roles owner ON (owner.oid = s.owner) 
            LEFT OUTER JOIN 
                pem.server_options o ON (
                    s.id = o.server_id 
                    AND o.pem_user = current_user
                ) 
            LEFT OUTER JOIN 
                pem.server_options oa ON (
                    o.server_id IS NULL 
                    AND s.id = oa.server_id 
                    AND (
                        owner.rolname = oa.pem_user 
                        OR (
                            owner.rolname IS NULL 
                            AND oa.pem_user IS NULL
                        )
                    )
                )
        ) 
        SELECT 
            database_name, 
            database_size_mb AS "Size (MB)" 
        FROM 
            pemdata.database_size d 
        LEFT OUTER JOIN 
            restricted_dbs r ON (r.id = d.server_id) 
        WHERE 
            server_id = %(server_id)s::int4 
            AND (
                %(show_system_objects)s::boolean 
                OR (
                    CASE 
                        WHEN d.database_name != '' THEN d.database_name NOT IN ('template0', 'template1') 
                        ELSE TRUE 
                    END
                )
            ) 
            AND (
                r.dbs IS NULL 
                OR (
                    d.database_name = ANY(r.dbs)
                )
            ) 
        ORDER BY 
            database_size_mb DESC 
        LIMIT 20
    $sql$
    WHERE id = 67;

    -- Tablespaces Storage Overview Query
    UPDATE pem.chart_func 
    SET func = $sql$
        SELECT 
            tablespace_name, 
            tablespace_size_mb 
        FROM 
            pemdata.tablespace_size 
        WHERE 
            server_id = %(server_id)s::int4 
        ORDER BY 
            tablespace_size_mb DESC 
        LIMIT 20
    $sql$
    WHERE id = 68;

    -- Host Storage Overview Details Query
    UPDATE pem.chart_func 
    SET func = $sql$
        SELECT 
            'Number of WAL files: ' || number_of_wal_files 
        FROM 
            pemdata.number_of_wal_files 
        WHERE 
            server_id = %(server_id)s::int4
    $sql$
    WHERE id = 69;

    -- Host Storage Overview Query
    UPDATE pem.chart_func 
    SET func = $sql$
        SELECT 
            SUM(space_used_mb) AS used, 
            SUM(space_available_mb) AS free 
        FROM 
            pemdata.disk_space 
        WHERE 
            agent_id = %(agent_id)s::int4
    $sql$
    WHERE id = 70;

    -- Databases Storage Details Query
    UPDATE pem.chart_func 
    SET func = $sql$
        WITH restricted_dbs AS (
            SELECT 
                s.id, 
                pem.db_escaped_string_to_array(
                    COALESCE(
                        o.database_restriction, 
                        oa.database_restriction
                    )
                ) AS dbs 
            FROM 
                pem.server s 
            LEFT OUTER JOIN 
                pg_catalog.pg_roles owner ON (owner.oid = s.owner) 
            LEFT OUTER JOIN 
                pem.server_options o ON (
                    s.id = o.server_id 
                    AND o.pem_user = current_user
                ) 
            LEFT OUTER JOIN 
                pem.server_options oa ON (
                    o.server_id IS NULL 
                    AND s.id = oa.server_id 
                    AND (
                        owner.rolname = oa.pem_user 
                        OR (
                            owner.rolname IS NULL 
                            AND oa.pem_user IS NULL
                        )
                    )
                )
        ) 
        SELECT 
            database_name AS "Database Name", 
            database_size_mb AS "Database Size (MB)", 
            tablespace_name AS "Tablespace Name" 
        FROM 
            pemdata.database_size d 
        LEFT OUTER JOIN 
            restricted_dbs r ON (d.server_id = r.id) 
        WHERE 
            server_id = %(server_id)s::int4 
            AND (
                %(show_system_objects)s::boolean 
                OR (
                    CASE 
                        WHEN d.database_name != '' THEN d.database_name NOT IN ('template0', 'template1') 
                        ELSE TRUE 
                    END
                )
            ) 
            AND (
                r.dbs IS NULL 
                OR (
                    d.database_name = ANY(r.dbs)
                )
            ) 
        ORDER BY 
            2
    $sql$
    WHERE id = 71;

    -- Tablespaces Storage Details Query
    UPDATE pem.chart_func 
    SET func = $sql$
        SELECT 
            tablespace_name AS "Tablespace Name", 
            tablespace_size_mb AS "Tablespace Size (MB)" 
        FROM 
            pemdata.tablespace_size 
        WHERE 
            server_id = %(server_id)s::int4 
        ORDER BY 
            2
    $sql$
    WHERE id = 72;

    -- Host Storage Details Query
    UPDATE pem.chart_func 
    SET func = $sql$
        SELECT 
            file_system AS "File System", 
            ROUND((size_mb::float / 1024)::numeric, 2) AS "Size (GB)", 
            ROUND((space_used_mb::float / 1024)::numeric, 2) AS "Used (GB)", 
            ROUND((space_available_mb::float / 1024)::numeric, 2) AS "Available (GB)", 
            ROUND(
                (space_used_mb::float * 100 / (size_mb - COALESCE(space_reserved_mb, 0)))::numeric, 
                2
            ) AS "%% Used", 
            CASE 
                WHEN (device_id IS NOT NULL AND device_id != '') THEN 
                    mount_point || ' (' || device_id || ')' 
                ELSE 
                    mount_point 
            END AS "Mounted On" 
        FROM 
            pemdata.disk_space 
        WHERE 
            agent_id = %(agent_id)s::int4 
            AND size_mb != 0 
        ORDER BY 
            3::int DESC
    $sql$
    WHERE id = 73;

    -- Number of System Waits Query
    UPDATE pem.chart_func 
    SET func = $sql$
        SELECT 
            wait_name AS "Wait Name", 
            wait_count AS "Wait Counts" 
        FROM 
            pemdata.system_waits 
        WHERE 
            server_id = %(server_id)s::int4 
        ORDER BY 
            "Wait Counts" DESC 
        LIMIT 5
    $sql$
    WHERE id = 74;

    -- Wait Time Query
    UPDATE pem.chart_func 
    SET func = $sql$
        SELECT 
            wait_name AS "Wait Name", 
            total_wait * 1000 AS "Total Wait Time (Secs)" 
        FROM 
            pemdata.system_waits 
        WHERE 
            server_id = %(server_id)s::int4 
        ORDER BY 
            "Total Wait Time (Secs)" DESC 
        LIMIT 5
    $sql$
    WHERE id = 75;

    -- Wait Details Query
    UPDATE pem.chart_func 
    SET func = $sql$
        SELECT 
            wait_name AS "Event", 
            wait_count AS "Wait Count", 
            (
                SELECT 
                    CASE 
                        WHEN SUM(wait_count) = 0 THEN 0 
                        ELSE (psw.wait_count * 100 / SUM(wait_count)) 
                    END 
                FROM 
                    pemdata.system_waits 
                WHERE 
                    server_id = %(server_id)s::int4
            )::numeric(5, 2) AS "Percentage of Total", 
            (total_wait * 1000)::numeric(30, 2) AS "Time Waited (ms)", 
            (
                SELECT 
                    CASE 
                        WHEN SUM(total_wait) = 0 THEN 0 
                        ELSE (psw.total_wait * 100 / SUM(total_wait)) 
                    END 
                FROM 
                    pemdata.system_waits 
                WHERE 
                    server_id = %(server_id)s::int4
            )::numeric(5, 2) AS "Percentage of Time Waited", 
            (avg_wait * 1000)::numeric(30, 2) AS "Average Wait Time (ms)" 
        FROM 
            pemdata.system_waits psw 
        WHERE 
            server_id = %(server_id)s::int4 
        ORDER BY 
            2::int4
    $sql$
    WHERE id = 76;

    -- Host Memory Details Query
    UPDATE pem.chart_func 
    SET func = $sql$
        SELECT 
            'Swap Total: ' || total_swap_memory_mb || 'MB · Swap Used: ' || (total_swap_memory_mb - free_swap_memory_mb) || 'MB' 
        FROM 
            pemdata.memory_usage 
        WHERE 
            agent_id = %(agent_id)s::int4
    $sql$
    WHERE id = 78;

    -- WAL Lag Segments Query
    UPDATE pem.chart_func 
    SET func = $sql$
        SELECT 
            o_idx, 
            o_label, 
            'Date(' || (EXTRACT(EPOCH FROM o_aggtime) * 1000)::numeric(40, 0)::text || ')', 
            o_aggval 
        FROM 
            pem.generate_replication_segment_lag_chart_data(
                %(chart_id)s::int4, 
                %(dashboard_id)s::int4, 
                %(server_id)s::int4, 
                %(start_time)s::timestamptz, 
                %(end_time)s::timestamptz
            ) 
        ORDER BY 
            o_idx, 
            o_aggtime
    $sql$
    WHERE id = 81;

    -- WAL Lag Pages Query
    UPDATE pem.chart_func 
    SET func = $sql$
        SELECT 
            o_idx, 
            o_label, 
            'Date(' || (EXTRACT(EPOCH FROM o_aggtime) * 1000)::numeric(40, 0)::text || ')', 
            o_aggval 
        FROM 
            pem.generate_replication_page_lag_chart_data(
                %(chart_id)s::int4, 
                %(dashboard_id)s::int4, 
                %(server_id)s::int4, 
                %(start_time)s::timestamptz, 
                %(end_time)s::timestamptz
            ) 
        ORDER BY 
            o_idx, 
            o_aggtime
    $sql$
    WHERE id = 82;

    -- Replication Status Query
    UPDATE pem.chart_func 
    SET func = $sql$
        SELECT 
            'Replication Status: ' || COALESCE(
                (
                    SELECT 
                        CASE 
                            WHEN psh.last_heartbeat IS NULL 
                            OR pa.heartbeat_interval IS NULL THEN 'Unknown' 
                            WHEN psh.last_heartbeat < (now() - (pa.heartbeat_interval * 2 * '1 second'::interval)) THEN 'Stopped' 
                            WHEN pstrl.replication_paused THEN 'Paused' 
                            ELSE 'Running' 
                        END 
                    FROM 
                        pemdata.streaming_replication_lag_time pstrl 
                    LEFT OUTER JOIN 
                        pem.server_heartbeat psh ON (pstrl.server_id = psh.server_id) 
                    LEFT OUTER JOIN 
                        pem.agent_server_binding pasb ON (pstrl.server_id = pasb.server_id) 
                    LEFT OUTER JOIN 
                        pem.avail_agents pa ON (pasb.agent_id = pa.id AND psh.agent_id = pa.id) 
                    LEFT OUTER JOIN 
                        pem.agent_heartbeat pah ON (pah.agent_id = pasb.agent_id) 
                    WHERE 
                        pstrl.server_id = %(server_id)s::int4
                ), 
                'Unknown'
            )
    $sql$
    WHERE id = 83;

    -- Number of Events Lag Query
    UPDATE pem.chart_func 
    SET func = $sql$
        SELECT 
            o_idx, 
            o_label, 
            'Date(' || (EXTRACT(EPOCH FROM o_aggtime) * 1000)::numeric(40, 0)::text || ')', 
            o_aggval 
        FROM 
            pem.generate_slony_event_lag_chart_data(
                %(chart_id)s::int4, 
                %(dashboard_id)s::int4, 
                %(server_id)s::int4, 
                %(database)s::text, 
                %(start_time)s::timestamptz, 
                %(end_time)s::timestamptz
            ) 
        ORDER BY 
            o_idx, 
            o_aggtime
    $sql$
    WHERE id = 85;

    -- Time Lag Query
    UPDATE pem.chart_func 
    SET func = $sql$
        SELECT 
            o_idx, 
            o_label, 
            'Date(' || (EXTRACT(EPOCH FROM o_aggtime) * 1000)::numeric(40, 0)::text || ')', 
            o_aggval 
        FROM 
            pem.generate_slony_time_lag_chart_data(
                %(chart_id)s::int4, 
                %(dashboard_id)s::int4, 
                %(server_id)s::int4, 
                %(database)s::text, 
                %(start_time)s::timestamptz, 
                %(end_time)s::timestamptz
            ) 
        ORDER BY 
            o_idx, 
            o_aggtime
    $sql$
    WHERE id = 86;

    -- Background Writer Statistics (#Pages Written) Query
    UPDATE pem.chart_func 
    SET func = $sql$
        SELECT 
            o_idx, 
            o_label, 
            'Date(' || (EXTRACT(EPOCH FROM o_aggtime) * 1000)::numeric(40, 0)::text || ')', 
            o_aggval 
        FROM 
            pem.generate_server_pages_written(
                %(chart_id)s::int4, 
                %(dashboard_id)s::int4, 
                %(server_id)s::int4, 
                %(start_time)s::timestamptz, 
                %(end_time)s::timestamptz
            ) 
        ORDER BY 
            o_idx, 
            o_aggtime
    $sql$
    WHERE id = 87;

    -- PGD Conflict History Summary Query
    UPDATE pem.chart_func 
    SET func = $sql$
        SELECT 
            o_idx, 
            o_label, 
            'Date(' || (o_aggtime * 1000)::text || ')', 
            o_aggval 
        FROM 
            pem.generate_bdr_conflict_history_chart_data(
                %(chart_id)s::int4, 
                %(dashboard_id)s::int4, 
                %(server_id)s::int4, 
                %(start_time)s::timestamptz, 
                %(end_time)s::timestamptz
            ) 
        ORDER BY 
            o_idx, 
            o_aggtime
    $sql$
    WHERE id = 95;

    -- PEM-5354
    -- Modifying the pem.chart table to convert the Failover Manager Cluster Info' 
    -- chart type from 'text' to 'TB'
    UPDATE pem.chart SET type ='TB' WHERE id = 89;

    -- Modifying the pem.chart_func table query for the 'Failover Manager Cluster Info' chart
    UPDATE pem.chart_func 
    SET func = $SQL$
    SELECT property AS "Property", value AS "Value"
    FROM pemdata.efm_cluster_info pe
    LEFT JOIN pem.server ps ON ps.id = pe.server_id
    CROSS JOIN LATERAL (
    VALUES
        ('Cluster Name', ps.efm_cluster_name),
        ('Failover Manager Agent Running Status', CASE WHEN pe.efm_running = true THEN 'UP' ELSE 'DOWN' END),
        ('Allowed Node List', array_to_string(pe.efm_allowed_node_list, ', ')),
        ('Replica Priority List', array_to_string(pe.efm_standby_priority_list, ', ')),
        ('Missing Nodes', array_to_string(pe.efm_missing_nodes, ', ')),
        ('Minimum Standbys', pe.efm_minimum_standbys::text),
        ('Membership Coordinator', pe.efm_membership_coordinator),
        ('Cluster Status Message', pe.efm_messages)
    ) AS info(property, value)
    WHERE pe.server_id = %(server_id)s::int4;$SQL$
    WHERE id = 89;

    -- Modifying the pem.chart_func table to support psychopg3

    -- Users Activity
    UPDATE pem.chart
    SET params = ARRAY['chart_id', 'dashboard_id', 'server_id', 'database_name', 'start_time', 'end_time']
    WHERE id = 11;

    -- Memory Stats
    UPDATE pem.chart
    SET params = ARRAY['chart_id', 'dashboard_id', 'agent_id', 'start_time', 'end_time']
    WHERE id = 39;

    -- User Activity
    UPDATE pem.chart
    SET params = ARRAY['chart_id', 'dashboard_id', 'server_id', 'start_time', 'end_time']
    WHERE id = 55;

    -- WAL Lag Segments
    UPDATE pem.chart
    SET params = ARRAY['chart_id', 'dashboard_id', 'server_id', 'start_time', 'end_time']
    WHERE id = 81;

    -- WAL Lag Pages
    UPDATE pem.chart
    SET params = ARRAY['chart_id', 'dashboard_id', 'server_id', 'start_time', 'end_time']
    WHERE id = 82;

    -- Number of Events Lag
    UPDATE pem.chart
    SET params = ARRAY['chart_id', 'dashboard_id', 'server_id', 'database_name', 'start_time', 'end_time']
    WHERE id = 85;

    -- Time Lag
    UPDATE pem.chart
    SET params = ARRAY['chart_id', 'dashboard_id', 'server_id', 'database_name', 'start_time', 'end_time']
    WHERE id = 86;

    -- Background Writer Statistics (#Pages Written)
    UPDATE pem.chart
    SET params = ARRAY['chart_id', 'dashboard_id', 'server_id', 'start_time', 'end_time']
    WHERE id = 87;

    -- PGD Conflict History Summary
    UPDATE pem.chart
    SET params = ARRAY['chart_id', 'dashboard_id', 'server_id', 'start_time', 'end_time']
    WHERE id = 95;

    -- Corrections and label changes done to queries to support Table Chart

    -- PGD Subscription Statistics Chart
    UPDATE pem.data_chart
    SET metrices = ARRAY[
        'sub_name', 'subid', 'nconnect', 'ncommit', 'nabort', 
        'nerror', 'nskippedtx', 'ninsert', 'nupdate', 'ndelete', 
        'ntruncate', 'nddl', 'ndeadlocks', 'nretries', 
        'shared_blks_hit', 'shared_blks_read', 'shared_blks_dirtied', 
        'shared_blks_written', 'blk_read_time', 'blk_write_time', 
        'connect_time', 'last_disconnect_time', 'start_lsn', 
        'retries_at_same_lsn', 'curr_ncommit'
    ]
    WHERE cid = 112;

    -- PGD Global Locks
    UPDATE pem.data_chart
    SET metrices = ARRAY[
        'origin_node_name', 'lock_type', 'relation', 'pid', 
        'acquire_stage', 'waiters', 
        'global_lock_request_time', 'local_lock_request_time', 
        'last_state_change_time'
    ]
    WHERE cid = 105;

    -- Operating System
    UPDATE pem.chart
    SET labels = ARRAY[
        'File System', 'Size (GB)', 'Used (GB)', 'Available (GB)', '% Used', 'Mounted On'
    ]
    WHERE id = 44;

    -- Host Storage Details
    UPDATE pem.chart
    SET labels = ARRAY[
        'File System', 'Size (GB)', 'Used (GB)', 'Available (GB)', '% Used', 'Mounted On'
    ]
    WHERE id = 73;


    -- Failover Manager Node Status
    UPDATE pem.chart
    SET labels = ARRAY[
        'Agent Type', 'Address', 'DB', 'XLog Location', 'XLog Receive', 
        'Status Information', 'XLog Information', 'Virtual IP Address', 'VIP Status'
    ]
    WHERE id = 88;

    -- Server Status
    UPDATE pem.chart
    SET labels = ARRAY['', 'Blackout', 'Name', 'Status', 'Connections',
        'Alerts', 'Version', 'Remotely Monitored?'
    ]
    WHERE id = 3;

    -- System Wait
    UPDATE pem.chart
    SET labels = ARRAY['Event', 'Wait Count', 'Percentage of Total',
    'Time Waited (ms)', 'Percentage of Time Waited', 'Average Wait Time (ms)'
    ]
    WHERE id = 76;

    -- Failover Manager Node Status
    UPDATE pem.chart_func 
    SET func = $sql$
        SELECT 
            efm_agent_type AS "Agent Type", 
            efm_ip_address AS "Address", 
            efm_db_status AS "DB", 
            efm_xlog_loc AS "XLog Location", 
            efm_xlog_receive AS "XLog Receive", 
            efm_status_info AS "Status Information", 
            efm_xlog_info AS "XLog Information", 
            efm_vip AS "Virtual IP Address", 
            efm_vip_status AS "VIP Status" 
        FROM 
            pemdata.efm_cluster_node_status 
        WHERE 
            server_id = %(server_id)s::int4
    $sql$
    WHERE id = 88;

    -- Altered pem.chart table to check chart type for 'Alert Status' and 'PGD Workers'
    ALTER TABLE pem.chart DROP CONSTRAINT pem_chart_type_constraint;
    ALTER TABLE pem.chart ADD CONSTRAINT  pem_chart_type_constraint 
    CHECK (type IN ('TE', 'TB', 'B', 'P', 'L', 'CL', 'CT', 'GL', 'AD', 'AS', 'PW', 'AG', 'SS', 'AE'));

    -- Agent Status chart type changed to 'AG'
    UPDATE pem.chart SET type ='AG' WHERE id = 2;

    -- Server Status chart type changed to 'SS'
    UPDATE pem.chart SET type ='SS' WHERE id = 3;
    
    -- Alert Status chart type changed to 'AS'
    UPDATE pem.chart SET type ='AS' WHERE id = 4;

    -- Alert Errors chart type changed to 'AE'
    UPDATE pem.chart SET type ='AE' WHERE id = 7;

    -- PGD Workers chart type changed to 'PW'
    UPDATE pem.chart SET type ='PW' WHERE id = 106;

    -- Fixed PEM-5393: User with pem_manage_dashboard able to create/update/delete dashboard
    CREATE OR REPLACE FUNCTION pem.dashboard_chart_insertion() RETURNS trigger AS $$
    BEGIN
            UPDATE pem.chart SET ref_cnt = ref_cnt + 1 WHERE id = NEW.cid;
            RETURN NULL;
    END
    $$ LANGUAGE plpgsql SECURITY DEFINER;

    CREATE OR REPLACE FUNCTION pem.dashboard_chart_deletion() RETURNS trigger AS $$
    BEGIN
            UPDATE pem.chart SET ref_cnt = ref_cnt - 1 WHERE id = OLD.cid;
            RETURN NULL;
    END
    $$ LANGUAGE plpgsql SECURITY DEFINER;

    -- Fixed PEM-5429: Improved the purge history function performance
    CREATE OR REPLACE FUNCTION pem.purge_probe_history(_pid integer)
    RETURNS void
    LANGUAGE plpgsql
    AS $function$
    DECLARE
        r	record;
    BEGIN
        FOR r IN

            WITH
                target_types (id, parameter_list) AS (
                    VALUES  ( 100, ARRAY['agent_id']),
                        ( 150, ARRAY['tool_id']),
                        ( 200, ARRAY['server_id']),
                        ( 300, ARRAY['server_id', 'database_name']),
                        (1000, ARRAY['server_id', 'database_name']),
                        ( 400, ARRAY['server_id', 'database_name', 'schema_name'])
                )
            SELECT
                format($sql$DELETE FROM %I.%I AS d WHERE ROW(%s) IN (%s) AND d.recorded_time <= now() - %s * interval '1d'$sql$,
                    nsp.nspname,
                    rel.relname,
                    array_to_string(tt.parameter_list, ', '),
                    string_agg(objs.objects, ', '),
                    combo.lifetime) AS sql
            FROM pem.probe AS p
                JOIN pg_class AS rel ON rel.relname = p.internal_name
                JOIN pg_namespace AS nsp ON nsp.oid = rel.relnamespace
                JOIN pem.probe_objects_combo AS combo ON combo.pid = p.id
                JOIN target_types AS tt ON tt.id = p.target_type_id
                CROSS JOIN LATERAL (
                    /* Map quote_literal over each value of the `objects` array */
                    SELECT 'ROW(' || string_agg(quote_literal(objs.obj), ', ' ORDER BY objs.ord) || ')'
                    FROM UNNEST(combo.objects) WITH ORDINALITY AS objs (obj, ord)
                ) AS objs (objects)
            WHERE p.id = _pid
              AND nsp.nspname = 'pemhistory'
            GROUP BY p.id, nsp.nspname, rel.relname, tt.parameter_list, combo.lifetime

        LOOP
            EXECUTE r.sql;
        END LOOP;

        UPDATE pem.probe_objects_combo SET purged_on = now() WHERE pid = _pid;
    END;
    $function$;

    -- PEM-5426: Added the node_type information in the server Information probe
    DO $DO$
    BEGIN
        IF NOT EXISTS (SELECT 1 FROM pg_attribute WHERE attrelid = (SELECT oid FROM pg_class WHERE relname = 'server_info' and relnamespace = (SELECT oid FROM pg_namespace WHERE nspname = 'pemdata')) AND attname = 'node_type') THEN
            INSERT INTO pem.probe_column(probe_id, internal_name, display_name, display_position, classification,
            sql_data_type, unit_of_value, calculate_pit, discard_history, pit_by_default, is_graphable)
            SELECT id, 'node_type', 'Node Type', 9, 'm', 'text', '', false, false, false, false FROM pem.probe
            WHERE internal_name='server_info';

            ALTER TABLE pemdata.server_info ADD COLUMN node_type text;
            ALTER TABLE pemhistory.server_info ADD COLUMN node_type text;

            CREATE OR REPLACE FUNCTION pemdata.copy_server_info_to_history()
            RETURNS trigger
            LANGUAGE 'plpgsql'
            COST 100
            VOLATILE NOT LEAKPROOF
            AS $BODY$
            BEGIN
                IF (TG_OP = 'INSERT' OR TG_OP = 'UPDATE') THEN
                    INSERT INTO pemhistory.server_info (recorded_time, server_id, version_string, shared_buffers_mb, temp_buffers_mb, effective_cache_size_mb, segment_size_mb, wal_segment_size_mb, wal_buffers_mb, server_start_time, node_type) VALUES (NEW.recorded_time, NEW.server_id, NEW.version_string, NEW.shared_buffers_mb, NEW.temp_buffers_mb, NEW.effective_cache_size_mb, NEW.segment_size_mb, NEW.wal_segment_size_mb, NEW.wal_buffers_mb, NEW.server_start_time, NEW.node_type);
                    ELSIF EXISTS(SELECT 1 FROM pem.server WHERE id = OLD.server_id) THEN
                    INSERT INTO pemhistory.server_info (server_id) VALUES (OLD.server_id);
                END IF;
                RETURN NEW;
            END;
            $BODY$;

            UPDATE pem.probe SET probe_code=$SQL$
                SELECT
                    pg_catalog.version() AS version_string,
                    ((SELECT setting FROM pg_settings WHERE name = 'block_size')::decimal *
                     (SELECT setting FROM pg_settings WHERE name = 'shared_buffers')::decimal / (1024 * 1024))::numeric AS shared_buffers_mb,
                    ((SELECT setting FROM pg_settings WHERE name = 'block_size')::decimal *
                     (SELECT setting FROM pg_settings WHERE name = 'temp_buffers')::decimal / (1024 * 1024))::numeric AS temp_buffers_mb,
                    ((SELECT setting FROM pg_settings WHERE name = 'block_size')::decimal *
                     (SELECT setting FROM pg_settings WHERE name = 'effective_cache_size')::decimal / (1024 * 1024))::numeric AS effective_cache_size_mb,
                    ((SELECT setting FROM pg_settings WHERE name = 'block_size')::decimal *
                     (SELECT setting FROM pg_settings WHERE name = 'segment_size')::decimal / (1024 * 1024))::numeric AS segment_size_mb,
                    ((SELECT setting FROM pg_settings WHERE name = 'block_size')::decimal *
                     (SELECT setting FROM pg_settings WHERE name = 'wal_segment_size')::decimal / (1024 * 1024))::numeric AS wal_segment_size_mb,
                    ((SELECT setting FROM pg_settings WHERE name = 'block_size')::decimal *
                     (SELECT setting FROM pg_settings WHERE name = 'wal_buffers')::decimal / (1024 * 1024))::numeric AS wal_buffers_mb,
                    (SELECT pg_postmaster_start_time())::timestamptz AS server_start_time,
                    CASE
                       WHEN pg_is_in_recovery() THEN
                            CASE
                                WHEN EXISTS (SELECT 1 FROM pg_stat_wal_receiver LIMIT 1) THEN 'replica'  -- Standby and actively receiving WAL
                                ELSE 'readonly'  -- Standby but not receiving WAL
                            END
                       WHEN EXISTS (SELECT 1 FROM pg_stat_replication LIMIT 1) THEN 'primary'  -- Primary with replicas connected
                       ELSE 'standalone'  -- Primary but no replicas connected
                    END AS node_type;
            $SQL$
            WHERE internal_name='server_info';
         END IF;

        -- force rerunning the server_info probe for upgrade scenario
        DELETE FROM pem.probe_schedule WHERE probe_id=(SELECT id FROM pem.probe WHERE internal_name = 'server_info');
    END;
    $DO$ LANGUAGE plpgsql;

    -- PEM-5052: Add column read_options, write_options for io_analysis
    DO $DO$
    BEGIN
        IF NOT EXISTS (SELECT id FROM pem.probe_column
                WHERE probe_id = (SELECT id FROM pem.probe WHERE internal_name='io_analysis')
                AND internal_name = 'read_operations') THEN

            ALTER TABLE pemdata.io_analysis ADD COLUMN IF NOT EXISTS read_operations bigint;
            ALTER TABLE pemdata.io_analysis ADD COLUMN IF NOT EXISTS read_operations_pit bigint;
            ALTER TABLE pemdata.io_analysis ADD COLUMN IF NOT EXISTS write_operations bigint;
            ALTER TABLE pemdata.io_analysis ADD COLUMN IF NOT EXISTS write_operations_pit bigint;
            ALTER TABLE pemhistory.io_analysis ADD COLUMN IF NOT EXISTS read_operations bigint;
            ALTER TABLE pemhistory.io_analysis ADD COLUMN IF NOT EXISTS read_operations_pit bigint;
            ALTER TABLE pemhistory.io_analysis ADD COLUMN IF NOT EXISTS write_operations bigint;
            ALTER TABLE pemhistory.io_analysis ADD COLUMN IF NOT EXISTS write_operations_pit bigint;

            CREATE OR REPLACE FUNCTION pemdata.copy_io_analysis_to_history()
                RETURNS trigger
            AS $function$
                BEGIN
                    IF (TG_OP = 'INSERT' OR TG_OP = 'UPDATE') THEN
                        INSERT INTO pemhistory.io_analysis (recorded_time, agent_id, disk_drive, blks_read, blks_read_pit, blks_wrtn, blks_wrtn_pit, device_id, read_operations, read_operations_pit, write_operations, write_operations_pit) VALUES (NEW.recorded_time, NEW.agent_id, NEW.disk_drive, NEW.blks_read, NEW.blks_read_pit, NEW.blks_wrtn, NEW.blks_wrtn_pit, NEW.device_id, NEW.read_operations, NEW.read_operations_pit, NEW.write_operations, NEW.write_operations_pit);
                    ELSIF EXISTS(SELECT 1 FROM pem.agent WHERE id = OLD.agent_id) THEN
                        INSERT INTO pemhistory.io_analysis (agent_id, disk_drive, device_id) VALUES (OLD.agent_id, OLD.disk_drive, OLD.device_id);
                    END IF;
                    RETURN NEW;
                END;
            $function$ LANGUAGE plpgsql SECURITY DEFINER;

            CREATE OR REPLACE FUNCTION pemdata.calculate_io_analysis_pit_value()
                RETURNS trigger
            AS $function$
                BEGIN
                    IF (TG_OP = 'UPDATE') THEN
                        NEW.blks_read_pit := 0;
                        IF NEW.blks_read - OLD.blks_read >= 0 THEN
                            NEW.blks_read_pit :=  NEW.blks_read - OLD.blks_read;
                        END IF;
                        NEW.blks_wrtn_pit := 0;
                        IF NEW.blks_wrtn - OLD.blks_wrtn >= 0 THEN
                            NEW.blks_wrtn_pit :=  NEW.blks_wrtn - OLD.blks_wrtn;
                        END IF;
                        NEW.read_operations_pit := 0;
                        IF NEW.read_operations - OLD.read_operations >= 0 THEN
                            NEW.read_operations_pit :=  NEW.read_operations - OLD.read_operations;
                        END IF;
                        NEW.write_operations_pit := 0;
                        IF NEW.write_operations - OLD.write_operations >= 0 THEN
                            NEW.write_operations_pit :=  NEW.write_operations - OLD.write_operations;
                        END IF;
                    END IF;
                    RETURN NEW;
                END;
            $function$ LANGUAGE plpgsql SECURITY DEFINER;

            INSERT INTO pem.probe_column (
                probe_id, internal_name, display_name, display_position, classification,
                sql_data_type, unit_of_value, calculate_pit, discard_history,
                pit_by_default, is_graphable)
            SELECT
                (SELECT id FROM pem.probe WHERE internal_name='io_analysis'),
                v.internal_name, v.display_name, v.display_position, v.classification,
                v.sql_data_type, v.unit_of_value, v.calculate_pit, v.discard_history, v.pit_by_default, v.is_graphable
            FROM
                (VALUES
                    ('read_operations', 'Read Operations', 5, 'm', 'bigint', '#', true, false, false, false),
                    ('write_operations', 'Write Operations', 6, 'm', 'bigint', '#', true, false, false, false)
                ) v(internal_name, display_name, display_position, classification,
                    sql_data_type, unit_of_value, calculate_pit, discard_history, pit_by_default, is_graphable);
        END IF;

    END;
    $DO$ LANGUAGE plpgsql;

    -- Added a column connection_params in the server_options table
    DO $$
    BEGIN
        IF NOT EXISTS (
            SELECT 1
            FROM information_schema.columns
            WHERE table_name = 'server_options'
            AND table_schema = 'pem'
            AND column_name = 'connection_params'
        ) THEN
            ALTER TABLE pem.server_options
            ADD COLUMN connection_params JSONB;
        END IF;
    END $$;

    -- Added a column tags in the server table
    DO $$
    BEGIN
        IF NOT EXISTS (
            SELECT 1
            FROM information_schema.columns
            WHERE table_name = 'server'
            AND table_schema = 'pem'
            AND column_name = 'tags'
        ) THEN
            ALTER TABLE pem.server
            ADD COLUMN tags JSONB DEFAULT '[]'::jsonb;
        END IF;
    END $$;

    -- Added a column tags in the agent table
    DO $$
    BEGIN
        IF NOT EXISTS (
            SELECT 1
            FROM information_schema.columns
            WHERE table_name = 'agent'
            AND table_schema = 'pem'
            AND column_name = 'tags'
        ) THEN
            ALTER TABLE pem.agent
            ADD COLUMN tags JSONB DEFAULT '[]'::jsonb;
        END IF;
    END $$;

    -- Added the trigger to update the tag to primary/replica on basis of server_info node_type
    CREATE OR REPLACE FUNCTION update_server_tags()
    RETURNS TRIGGER AS $$
    DECLARE
        primary_color text := '#008000';       -- Hex value for Green
        replica_color text := '#737373';       -- Hex value for Dark Grey
    BEGIN
        -- Ensure the tags column is never NULL when we perform operations
        IF TG_OP IN ('INSERT', 'UPDATE') THEN
            -- Update the tags column of pem.server
            IF (SELECT tags FROM pem.server WHERE id = NEW.server_id) IS NULL THEN
                -- If tags are NULL, set them to empty array
                UPDATE pem.server
                SET tags = '[]'::jsonb
                WHERE id = NEW.server_id;
            END IF;
        END IF;

        -- If it's an INSERT and node_type is 'primary', add "primary" tag with the hardcoded color
        IF TG_OP = 'INSERT' AND NEW.node_type = 'primary' THEN
            -- Add primary tag if it doesn't exist
            UPDATE pem.server
            SET tags = jsonb_insert(
                    COALESCE(tags, '[]'::jsonb),
                    '{0}',
                    jsonb_build_object('color', primary_color, 'text', 'primary'),
                    true
                )
            WHERE id = NEW.server_id
            AND NOT EXISTS (
                SELECT 1
                FROM jsonb_array_elements(tags) AS tag
                WHERE tag->>'text' = 'primary'
            );
        ELSIF TG_OP = 'UPDATE' AND NEW.node_type = 'primary' AND OLD.node_type != 'primary' THEN
            -- If node_type changed to 'primary', add "primary" tag if not already present
            UPDATE pem.server
            SET tags = jsonb_insert(
                    COALESCE(tags, '[]'::jsonb),
                    '{0}',
                    jsonb_build_object('color', primary_color, 'text', 'primary'),
                    true
                )
            WHERE id = NEW.server_id
            AND NOT EXISTS (
                SELECT 1
                FROM jsonb_array_elements(tags) AS tag
                WHERE tag->>'text' = 'primary'
            );

        -- Remove "primary" tag if node_type changes from 'primary' to something else
        ELSIF TG_OP = 'UPDATE' AND NEW.node_type != 'primary' AND OLD.node_type = 'primary' THEN
            UPDATE pem.server
            SET tags = COALESCE(
                (SELECT jsonb_agg(tag)
                 FROM jsonb_array_elements(tags) AS tag
                 WHERE tag->>'text' != 'primary'),
                '[]'::jsonb
            )
            WHERE id = NEW.server_id;
        END IF;

        -- If it's an INSERT and node_type is 'replica', add "replica" tag with the hardcoded color
        IF TG_OP = 'INSERT' AND NEW.node_type = 'replica' THEN
            -- Add replica tag if it doesn't exist
            UPDATE pem.server
            SET tags = jsonb_insert(
                    COALESCE(tags, '[]'::jsonb),
                    '{0}',
                    jsonb_build_object('color', replica_color, 'text', 'replica'),
                    true
                )
            WHERE id = NEW.server_id
            AND NOT EXISTS (
                SELECT 1
                FROM jsonb_array_elements(tags) AS tag
                WHERE tag->>'text' = 'replica'
            );
        ELSIF TG_OP = 'UPDATE' AND NEW.node_type = 'replica' AND OLD.node_type != 'replica' THEN
            -- If node_type changed to 'replica', add "replica" tag if not already present
            UPDATE pem.server
            SET tags = jsonb_insert(
                    COALESCE(tags, '[]'::jsonb),
                    '{0}',
                    jsonb_build_object('color', replica_color, 'text', 'replica'),
                    true
                )
            WHERE id = NEW.server_id
            AND NOT EXISTS (
                SELECT 1
                FROM jsonb_array_elements(tags) AS tag
                WHERE tag->>'text' = 'replica'
            );

        -- Remove "replica" tag if node_type changes from 'replica' to something else
        ELSIF TG_OP = 'UPDATE' AND NEW.node_type != 'replica' AND OLD.node_type = 'replica' THEN
            UPDATE pem.server
            SET tags = COALESCE(
                (SELECT jsonb_agg(tag)
                 FROM jsonb_array_elements(tags) AS tag
                 WHERE tag->>'text' != 'replica'),
                '[]'::jsonb
            )
            WHERE id = NEW.server_id;
        END IF;

        -- Return the new row to complete the update process
        RETURN NEW;
    END;
    $$ LANGUAGE plpgsql;

    DROP TRIGGER IF EXISTS server_tags_trigger ON pemdata.server_info;
    CREATE TRIGGER server_tags_trigger
    AFTER INSERT OR UPDATE ON pemdata.server_info
    FOR EACH ROW
    EXECUTE FUNCTION update_server_tags();

    -- PEM-5372 - cluster node
    ALTER TABLE pem.server_group ADD COLUMN IF NOT EXISTS parent_id integer;

    ALTER TABLE pem.server_group DROP CONSTRAINT IF EXISTS parent_id_fkey;

    ALTER TABLE pem.server_group ADD CONSTRAINT parent_id_fkey FOREIGN KEY (parent_id)
        REFERENCES pem.server_group (id) ON UPDATE NO ACTION
        ON DELETE NO ACTION;

    CREATE OR REPLACE FUNCTION pem.delete_cluster(_id integer)
    RETURNS boolean AS
    $$
    DECLARE
        v_parent_id integer;
    BEGIN
        SELECT parent_id INTO v_parent_id FROM pem.server_group WHERE id = _id;
        IF v_parent_id IS NULL THEN
            RAISE EXCEPTION 'Cluster not found';
        END IF;

        UPDATE pem.server SET group_id = v_parent_id WHERE group_id = _id;
        UPDATE pem.server_options SET server_group_id = v_parent_id WHERE server_group_id = _id;
        DELETE FROM pem.server_group WHERE id = _id;

        RETURN true;
    END$$ LANGUAGE 'plpgsql' SECURITY DEFINER;

    DROP FUNCTION IF EXISTS pem.create_alert_template(
        text, text, text, integer, text[], pem.alert_param_type[], text[],
        text, text[], integer, pem.server_type, integer, integer, boolean,
        text, boolean, text, numeric[], text
    );
    CREATE OR REPLACE FUNCTION pem.create_alert_template(
        name                      text,
        description               text,
        sql                       text,
        object_type               integer,
        param_names               text[],
        param_types               pem.alert_param_type[],
        param_units               text[],
        threshold_unit            text,
        probe_dependency_list     text[] DEFAULT '{}',
        snmp_oid                  integer DEFAULT 0,
        applicable_on_server      pem.server_type DEFAULT 'ALL',
        default_check_frequency   integer DEFAULT 1,
        default_history_retention integer DEFAULT 30,
        is_system_template        boolean    DEFAULT true,
        info_sql                  text DEFAULT NULL,
        is_auto_create            boolean DEFAULT false,
        operator                  text DEFAULT '>',
        thresholds                numeric[] DEFAULT NULL,
        reference_id              text DEFAULT NULL
    )
    RETURNS integer AS $$
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
                default_check_frequency, default_history_retention, is_system_template,
                info_sql, is_auto_create, operator, thresholds, reference_id)
        VALUES($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, $14, $15, $16, $17, $18, $19)
        RETURNING id;
    $$ LANGUAGE SQL;

END TRANSACTION;
