SELECT agent_id,
       agent_name,
       server_group_name,
       array_agg(server_name) as servers
FROM (
    SELECT
        pa.id AS agent_id, pa.description AS agent_name,
        ps.id AS server_id, ps.description AS server_name,
        COALESCE(usg.name, sg.name) AS server_group_name
    FROM
        pem.avail_agents pa
        LEFT OUTER JOIN pem.agent_server_binding pasb ON (
            pa.id = pasb.agent_id
        )
        LEFT OUTER JOIN pem.avail_servers ps ON (
            pasb.server_id = ps.id
        )
        LEFT OUTER JOIN pem.server_group sg
            ON (sg.id::text = pa.group_id::text)
        LEFT OUTER JOIN pem.user_server_group usg
        ON (
            usg.id::text = pa.group_id::text
            AND usg.uid = pem.current_user_id()
        )
) AS temp
GROUP BY agent_id, agent_name, server_group_name
