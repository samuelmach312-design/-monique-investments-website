SELECT
    asb.server_id,
    asb.database,
    s.description AS name,
    asb.exclude_databases
FROM pem.agent_server_binding asb
INNER JOIN pem.avail_servers s ON (asb.server_id = s.id)
WHERE asb.server_id = {{ server_id|qtLiteral(conn) }}::int4
