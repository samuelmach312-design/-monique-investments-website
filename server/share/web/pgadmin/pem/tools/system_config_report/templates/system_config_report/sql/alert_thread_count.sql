SELECT
sum(value::int) as alert_threads_count
FROM pem.agent_config ac JOIN pem.agent a ON (ac.agent_id = a.id)
WHERE a.active
AND ac.param='alert_threads'