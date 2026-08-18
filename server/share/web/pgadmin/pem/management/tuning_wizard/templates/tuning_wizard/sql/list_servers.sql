{# servers/database selection statement #}
SELECT
    DISTINCT agent_server.server_id,
    agent_server.agent_id,
    server.serviceid AS service_id,
    server.server server_name,
    server.description,
    server.port,
    st.setting AS data_directory,
    agent.agent_capability_list AS agent_capability_list,
    si.server_version_id,
    (
        CASE
        WHEN 'allow_server_restart'::text=ANY (agent.agent_capability_list)
            THEN TRUE
        ELSE FALSE
        END
    ) AS can_restart
FROM pem.avail_servers server
    LEFT JOIN pem.agent_server_binding agent_server
        ON (agent_server.server_id = server.id)
    LEFT JOIN pemdata.oc_database oc_database
        ON (agent_server.server_id = oc_database.server_id)
            AND (oc_database.connections_allowed = true)
    LEFT JOIN pemdata.server_info si
        ON (si.server_id = agent_server.server_id)
    LEFT JOIN pemdata.settings st
        ON (st.server_id = agent_server.server_id)
    LEFT JOIN pem.avail_agents agent
        ON (agent_server.agent_id = agent.id)
WHERE
    ((si.server_version_id > 10802 AND si.server_version_id < 20000)
        OR (si.server_version_id > 20803))
        AND st.name = 'data_directory'
        AND server.is_remote_monitoring = false
ORDER BY server.server
