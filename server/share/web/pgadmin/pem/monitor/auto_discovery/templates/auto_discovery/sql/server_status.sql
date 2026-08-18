SELECT
    s.id
FROM
    pem.server s
WHERE
    port = {{port}}::int
    AND server = {{server|qtLiteral(conn, True)}}::text
    AND active = true
    AND s.id NOT IN (SELECT server_id FROM pem.agent_server_binding);
