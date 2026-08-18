{# servers/database selection statement #}
SELECT
    DISTINCT agent_server.server_id,
    agent_server.agent_id,
    server.serviceid AS service_id,
    server.server AS server_name,
    server.description,
    server.port,
    st.setting AS data_directory,
    si.server_version_id,
    agent.agent_capability_list,
    agent.version,
    CASE(position('Windows' in os.os_details))
    WHEN 0 THEN 'linux'
    ELSE 'windows'
    END AS agent_os
FROM pem.avail_servers server
LEFT JOIN pem.agent_server_binding agent_server
    ON (agent_server.server_id = server.id)
LEFT JOIN pemdata.oc_database oc_database
    ON (agent_server.server_id = oc_database.server_id)
        AND (oc_database.connections_allowed = true)
LEFT JOIN pemdata.server_info si
    ON (si.server_id = agent_server.server_id)
LEFT JOIN pemdata.settings st ON (st.server_id = agent_server.server_id)
LEFT JOIN pem.avail_agents agent ON (agent_server.agent_id = agent.id)
LEFT JOIN pemdata.os_info os ON (os.agent_id = agent_server.agent_id)
WHERE
    si.server_version_id > 20000
    AND st.name = 'data_directory'
    AND server.is_remote_monitoring = false
