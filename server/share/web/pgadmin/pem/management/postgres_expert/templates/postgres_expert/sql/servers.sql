{# servers/database selection statement #}
SELECT
    agent_server.server_id,
    server.server server_name,
    array_agg(oc_database.database_name) database_list,
    array_agg(oc_database.system_database) is_sys_db,
    server.description || E' (' || server.server || E':' || server.port || E')' description,
    server.description as s_description,
    server.port as s_port
FROM
    pem.agent_server_binding agent_server
LEFT JOIN
    pemdata.oc_database oc_database
    ON  (agent_server.server_id = oc_database.server_id)  AND (oc_database.connections_allowed = true)
JOIN
    pem.avail_servers server
    ON (agent_server.server_id = server.id)
GROUP BY
	server.description,
	server.server,
	server.port,
	agent_server.server_id
ORDER BY
    agent_server.server_id;
