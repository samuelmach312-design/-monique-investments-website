SELECT
    id as value, description AS label
FROM pem.avail_agents
WHERE 'barman' = ANY(agent_capability_list)
ORDER BY label;
