SELECT
    a.id,
    a.description AS description,
	COALESCE(ao.group_id,a.group_id) AS group_id,
	a.platform,
    a.version,
    a.active,
	o.os_details AS os_details,
    o.os_host_name AS hostname,
    o.os_domain_name AS domainname,
    CASE WHEN o.os_details  ILIKE '%%microsoft%%'
    THEN o.os_windows_domain ELSE '' END AS windows_domain,
	local_servers.bound_local_servers,
	remote_servers.bound_remote_servers,
    cpu_usage.total_cpu_cores,
    cpu_usage.avg_cpu_utilization_percentage,
    cpu_usage.cpu_core_details,
	memory_usage.mem_details,
	disk_usage.total_disk_size_mb,
	disk_usage.total_disk_space_used_mb,
	disk_usage.total_disk_space_available_mb,
	disk_usage.disk_utilization_percentage,
	disk_usage.disk_utilization_details
FROM
    pem.agent a
    LEFT OUTER JOIN pem.agent_options ao ON ao.agent_id=a.id AND ao.pem_user = (%s)::text
    LEFT JOIN (
        SELECT
            asb_1.agent_id, count(*) AS bound_servers_count,
            SUM(
                CASE WHEN s.is_remote_monitoring THEN 1 ELSE 0 END
            ) AS bound_remote_servers_count, SUM(
                CASE WHEN s.is_remote_monitoring THEN 0 ELSE 1 END
            ) AS bound_local_servers_count
        FROM
            pem.agent_server_binding asb_1
            LEFT JOIN pem.server s ON s.id = asb_1.server_id
        GROUP BY asb_1.agent_id
    ) asb ON asb.agent_id = a.id
    LEFT JOIN pemdata.os_info o ON a.id=o.agent_id
	-- local servers
	LEFT JOIN (
        SELECT agent_id,
            ARRAY_AGG(bound_local_servers)::json[] AS bound_local_servers
        FROM (
            SELECT asb_1.agent_id,
            CAST(
                '{"server_id":"' || asb_1.server_id || '", "server_name":"' || s.description
                || '"}' AS JSON
            ) AS bound_local_servers
                FROM pem.agent_server_binding asb_1
            INNER JOIN pem.server s ON s.id = asb_1.server_id
			AND s.is_remote_monitoring = false
        ) AS local_server  GROUP BY agent_id
    ) AS local_servers ON local_servers.agent_id = a.id
	-- remote servers
	LEFT JOIN (
        SELECT agent_id,
            ARRAY_AGG(bound_remote_servers)::json[] AS bound_remote_servers
        FROM (
            SELECT asb_1.agent_id,
            CAST(
                '{"server_id":"' || asb_1.server_id || '", "server_name":"' || s.description
                || '"}' AS JSON
            ) AS bound_remote_servers
                FROM pem.agent_server_binding asb_1
            INNER JOIN pem.server s ON s.id = asb_1.server_id
			AND s.is_remote_monitoring = true
        ) AS remote_server GROUP BY agent_id
    ) AS remote_servers ON remote_servers.agent_id = a.id
    -- CPU details
    LEFT JOIN (
        SELECT agent_id,
            COUNT(cpu_core_details) AS total_cpu_cores,
            ROUND(AVG(load_percentage), 2) AS avg_cpu_utilization_percentage,
            ARRAY_AGG(cpu_core_details)::json[] AS cpu_core_details
        FROM (
            SELECT agent_id,
            load_percentage::numeric,
            CAST(
                '{"core_id":"' || core_id || '", "load_percentage":"' || load_percentage
                || '", "recorded_time":"' || recorded_time || '"}' AS JSON
            ) AS cpu_core_details
                FROM pemdata.cpu_usage
            GROUP BY agent_id, core_id
            ORDER BY core_id
        ) AS cpu GROUP BY agent_id
    ) AS cpu_usage ON cpu_usage.agent_id = a.id
    -- Memory details
	LEFT JOIN (
        SELECT agent_id, CAST (
			'{"total_ram_memory_mb":"' || total_ram_memory_mb ||
			'", "free_ram_memory_mb":"' || free_ram_memory_mb ||
			'", "mem_usage_percentage":"' ||
			CASE
				WHEN total_ram_memory_mb = 0 OR free_ram_memory_mb = 0 THEN 0
				ELSE round((100 - (free_ram_memory_mb::numeric / total_ram_memory_mb) * 100)::numeric, 2)
			END ||
			'", "total_swap_memory_mb":"' || total_swap_memory_mb ||
			'", "free_swap_memory_mb":"' || free_swap_memory_mb ||
			'", "swap_usage_percentage":"' ||
			CASE
				WHEN total_swap_memory_mb = 0 OR free_swap_memory_mb = 0 THEN 0
				ELSE round((100 - (free_swap_memory_mb::numeric / total_swap_memory_mb) * 100)::numeric, 2)
			END ||
			'", "recorded_time":"' || recorded_time || '"}' AS JSON
		) AS mem_details
		FROM pemdata.memory_usage
		GROUP BY agent_id
	) AS memory_usage ON memory_usage.agent_id = a.id
	-- Disk details
	LEFT JOIN (
        SELECT agent_id,
            SUM(size_mb) AS total_disk_size_mb,
            SUM(space_used_mb) AS total_disk_space_used_mb,
            SUM(space_available_mb) AS total_disk_space_available_mb,
            CASE
                WHEN sum(size_mb) > 0
                    THEN round((
                        sum(space_used_mb)::numeric / sum(size_mb) * 100
                    )::numeric, 2)
                ELSE 0
            END AS disk_utilization_percentage,
            ARRAY_AGG(disk_details)::json[] AS disk_utilization_details
        FROM (
            SELECT agent_id,
                size_mb,
                space_used_mb,
                space_available_mb,
                CAST(
                    '{"mount_point":"' || mount_point ||
                    '", "file_system":"' || file_system ||
                    '", "size_mb":"' || size_mb ||
                    '", "space_used_mb":"' || space_used_mb ||
                    '", "space_available_mb":"' || space_available_mb ||
                    '", "recorded_time":"' || recorded_time || '"}' AS JSON
                ) AS disk_details
            FROM pemdata.disk_space
            ORDER BY size_mb DESC
        ) AS disk GROUP BY agent_id
	) AS disk_usage ON disk_usage.agent_id = a.id
WHERE a.active = true
ORDER BY a.active, a.id;
