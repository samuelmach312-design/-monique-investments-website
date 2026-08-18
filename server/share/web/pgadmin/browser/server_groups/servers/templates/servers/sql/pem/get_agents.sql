SELECT
    id as value,
    COALESCE(ao.description, a.description) AS label
FROM pem.avail_agents a
    LEFT JOIN pem.agent_options ao
    ON (a.id = ao.agent_id AND pem_user = current_user)
ORDER BY label;
