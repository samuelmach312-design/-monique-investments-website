DELETE FROM pem.agent_server_binding
WHERE
    server_id = {{server_id}}::int4;