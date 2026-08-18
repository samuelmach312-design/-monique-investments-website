SELECT count(*) FROM pem.agent_heartbeat 
WHERE last_heartbeat >= now() - INTERVAL '24 hour';