SELECT count(*) FROM pem.server_heartbeat 
WHERE last_heartbeat >= now() - INTERVAL '24 hour';