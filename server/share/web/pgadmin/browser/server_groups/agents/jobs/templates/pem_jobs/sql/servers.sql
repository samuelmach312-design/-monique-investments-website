SELECT
    s.id, s.description, s.port,
    CASE WHEN s.hostaddr IS NULL OR s.hostaddr = '' THEN s.server ELSE s.hostaddr END AS host,
    ARRAY(
        SELECT database_name FROM pemdata.oc_database oc
        WHERE oc.server_id = s.id
    ) AS databases
FROM
    pem.agent_server_binding ab
    LEFT JOIN pem.server s ON (ab.server_id = s.id)
WHERE ab.agent_id = {{ agent_id|qtLiteral(conn) }}::integer;
