{# DATABASE SELECT statement according to SERVER ID #}
{% if sid %}
SELECT
    server.server server_name,
    oc_database.database_name,
    oc_database.system_database
FROM
    pem.agent_server_binding agent_server
LEFT JOIN pemdata.oc_database oc_database
    ON (agent_server.server_id = oc_database.server_id)
    AND (oc_database.connections_allowed = true)
JOIN
    pem.avail_servers server ON (agent_server.server_id = server.id)
WHERE
    server.id = {{ sid }}
ORDER BY
    agent_server.server_id;
{% endif %}