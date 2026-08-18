WITH user_overridden_server_groups AS (
    SELECT * FROM pem.user_server_group
        WHERE uid = pem.current_user_id()
),
pgd_extension_details AS (
	SELECT e.server_id, COALESCE(e.extension_name,'') AS extension_name, COALESCE(e.extension_version,'') AS extension_version
    from pemdata.oc_extension e, pem.server s
	WHERE e.server_id=s.id AND e.extension_name LIKE '%bdr%'
),
all_available_server_groups AS (
    SELECT  sg.id,
            COALESCE(usg.name, sg.name) AS name,
            COALESCE(usg.hidden, false) AS hidden
    FROM pem.server_group sg
    LEFT JOIN user_overridden_server_groups usg
        ON sg.id = usg.id
    WHERE usg.deleted IS NULL OR NOT usg.deleted
    ORDER BY NAME
),
agents AS (
   SELECT
       a.id, a.description AS agent_name, a.platform, a.group_id, a.active,
       cpu_usage.cpu_cores
   FROM pem.avail_agents a
   LEFT JOIN (
       SELECT agent_id, COUNT (core_id) AS cpu_cores FROM pemdata.cpu_usage GROUP BY agent_id
   ) AS cpu_usage ON cpu_usage.agent_id = a.id
),
server_cpu_info AS (
SELECT
    s.group_id AS gid,
    s.id AS sid,
    a.agent_id AS aid,
    agent_name,
    platform,
    CASE
    WHEN i.version_string LIKE '%2ndQPG%' THEN 'EDB Postgres Extended'
    WHEN i.version_string LIKE '%EnterpriseDB%' THEN 'EDB Postgres Advanced Server'
    WHEN i.version_string LIKE '%PostgreSQL%' THEN 'PostgreSQL'
    ELSE 'UNKNOWN'
    END AS server_type,
	CASE
    WHEN i.version_string LIKE '%2ndQPG%' THEN CONCAT('2ndQ ', sv.display_name)
    else COALESCE(sv.display_name, '') END AS display_name,
    i.server_version_id AS version,
    s.description AS description,
    s.is_remote_monitoring,
    s.server AS host,
    s.port AS port,
    cpu_cores
FROM pem.avail_servers s
	LEFT OUTER JOIN pem.agent_server_binding a ON a.server_id = s.id
    LEFT OUTER JOIN pemdata.server_info i ON i.server_id = s.id
    LEFT OUTER JOIN pem.server_version sv ON i.server_version_id = sv.id
    LEFT OUTER JOIN agents ON agents.id = a.agent_id
	ORDER BY i.server_id
),
unmanaged_servers AS (
SELECT
    s.group_id AS gid,
	count(s.group_id) total
FROM pem.avail_servers s
	LEFT OUTER JOIN pem.agent_server_binding a ON a.server_id = s.id
WHERE a.agent_id IS NULL
GROUP BY s.group_id
),
remotely_managed_servers AS (
SELECT
    s.group_id AS gid,
	count(s.group_id) total
FROM pem.avail_servers s
	LEFT OUTER JOIN pem.agent_server_binding a ON a.server_id = s.id
WHERE s.is_remote_monitoring = true
GROUP BY s.group_id
),
bart_servers AS (
    SELECT * FROM pem.bart b
    LEFT JOIN agents ON agents.id = b.agent_id
)
SELECT json_build_object('total_cpu_cores', sum(cpu_cores)) AS res FROM (
    SELECT cpu_cores FROM bart_servers
    UNION ALL
    SELECT cpu_cores FROM server_cpu_info sci
    WHERE sci.is_remote_monitoring = false AND sci.aid IS NOT NULL
) all_objects
UNION ALL
SELECT json_build_object('count_by_platform', array_agg(p.res)) AS res FROM (
	SELECT json_build_object(
	    'platform', platform,
	    'cpu_cores', sum(cpu_cores),
	    'servers', count(cpu_cores)
	    ) AS res
	FROM (
		SELECT platform, cpu_cores FROM bart_servers
		UNION ALL
		SELECT platform, cpu_cores FROM server_cpu_info sci
        WHERE sci.is_remote_monitoring = false AND sci.aid IS NOT NULL
	) bsi
	GROUP BY bsi.platform
) p
UNION ALL
SELECT json_build_object('count_by_server_type', array_agg(st.res)) AS res FROM (
    SELECT json_build_object(
        'type', server_type,
        'cpu_cores', sum(cpu_cores),
        'count', count(cpu_cores)
    ) AS res
    FROM server_cpu_info sci
    WHERE sci.is_remote_monitoring = false AND sci.aid IS NOT NULL
    GROUP BY server_type
) st
UNION ALL
SELECT json_build_object('count_by_server_version', array_agg(sv.res)) AS res FROM (
    SELECT
        json_build_object(
            'version', COALESCE(ci.display_name, ''),
            'core_count', core_count,
            'servers', server_count
        ) AS res
    FROM (
        SELECT sci.version, sci.display_name, sum(sci.cpu_cores) AS core_count, count(sci.*) AS server_count FROM server_cpu_info sci
        WHERE sci.aid IS NOT NULL AND sci.is_remote_monitoring = false
        GROUP BY version, display_name
    ) ci
    LEFT JOIN pem.server_version sv ON ci.version = sv.id
	ORDER BY ci.version
) sv
UNION ALL
SELECT json_build_object('count_by_group', array_agg(sv.res)) AS res FROM (
    SELECT json_build_object(
        'name', avs.name,
        'hidden', avs.hidden,
        'servers', server_count,
        'cpu_cores', cpu_cores
    ) AS res FROM (
        SELECT gid, count(gid) AS server_count, sum(cpu_cores) AS cpu_cores
        FROM server_cpu_info sci
        WHERE sci.is_remote_monitoring = false AND sci.aid IS NOT NULL
        GROUP BY gid
    ) cpi
    LEFT JOIN all_available_server_groups avs ON (avs.id = cpi.gid)
) sv
UNION ALL
SELECT json_build_object('count_by_bart_servers', bs.res) AS res FROM (
    SELECT  json_build_object('total', sum(cpu_cores), 'versions', array_agg(json_build_object(version, cpu_cores)), 'servers', count(cpu_cores)) AS res
    FROM (
        SELECT b.version, sum(b.cpu_cores) AS cpu_cores FROM bart_servers AS b
        WHERE version_string IS NOT NULL GROUP BY b.version
    ) cnt_bart_servers
) bs
UNION ALL
SELECT json_build_object('total_locally_managed_servers', count(sid)) AS res FROM (
    SELECT sid FROM server_cpu_info sci
    WHERE sci.is_remote_monitoring = false AND sci.aid IS NOT NULL
) total_managed
UNION ALL
SELECT json_build_object('total_unmanaged_servers', sum(total)) AS res FROM (
    SELECT total FROM unmanaged_servers
) total_unmanaged
UNION ALL
SELECT json_build_object('total_remotely_managed_servers', sum(total)) AS res FROM (
    SELECT total FROM remotely_managed_servers
) total_remotely_managed
UNION ALL
SELECT json_build_object('servers', array_agg(sv.res)) AS res FROM (
    SELECT json_build_object(
        'gid', gid,
        'group_name', avs.name,
        'aid', aid,
        'agent_name', agent_name,
        'platform', CASE WHEN is_remote_monitoring = true THEN NULL ELSE platform END,
        'sid', sid,
        'name', description,
        'display_name', display_name,
        'server_type', CASE WHEN is_remote_monitoring = true and i.version_string LIKE '%2ndQPG%' THEN 'EDB Postgres Extended'ELSE server_type END,
        'is_remote_monitoring', is_remote_monitoring,
        'host', host,
        'port', port,
		'is_pgd', CASE WHEN bed.extension_name is NULL THEN 'False' ELSE 'True' END,
		'pgd_extension_version', CASE WHEN bed.extension_name is NULL THEN 'NA' ELSE bed.extension_version END,
        -- PUT IF ELSE on REMOTE MONITORED SERVER TO DISPLAY BELOW AS NULL
        'cpu_cores', CASE WHEN is_remote_monitoring = true THEN NULL ELSE cpu_cores END,
        'total_ram_memory_mb', CASE WHEN is_remote_monitoring = true THEN NULL ELSE total_ram_memory_mb END,
        'free_ram_memory_mb', CASE WHEN is_remote_monitoring = true THEN NULL ELSE free_ram_memory_mb END,
        'mem_usage_percentage', CASE
                WHEN is_remote_monitoring = true THEN NULL
                WHEN total_ram_memory_mb = 0 OR free_ram_memory_mb = 0 THEN 0
				ELSE round((100 - (free_ram_memory_mb::numeric / total_ram_memory_mb) * 100)::numeric, 2)
			END
    ) AS res FROM (
        SELECT gid, aid, sid, agent_name, platform, description,
            display_name, server_type, is_remote_monitoring, host, port,
            cpu_cores
        FROM server_cpu_info sci
        ORDER BY display_name
    ) cpi
    LEFT JOIN all_available_server_groups avs ON (avs.id = cpi.gid)
    LEFT JOIN pemdata.memory_usage mu ON (mu.agent_id = cpi.aid)
	LEFT JOIN pemdata.server_info i ON i.server_id = cpi.sid
	LEFT JOIN pgd_extension_details bed ON bed.server_id = cpi.sid
    ORDER BY avs.id
) sv;

