SELECT DISTINCT
    avail_servers.id AS server_id,
    description || '('||server::text||':'||port::text||')'::text as description,
	CASE WHEN COALESCE(server_logs.server_id, 0) > 0 THEN TRUE ELSE FALSE END AS has_logs,
	CASE WHEN COALESCE(log_config.server_id, 0) > 0 THEN TRUE ELSE FALSE END AS log_manager_runs
FROM
    pem.avail_servers AS avail_servers
LEFT JOIN
	(SELECT server_id from pemdata.server_logs GROUP BY server_id)
	AS server_logs ON avail_servers.id=server_logs.server_id
LEFT JOIN
	pem.log_configuration AS log_config ON avail_servers.id=log_config.server_id
WHERE avail_servers.active IS TRUE
ORDER BY description ASC;
