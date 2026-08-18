SELECT
    array_agg(ns.ip_address) AS servers,
    ad.port,
    ad.description as name,
    ad.description as id,
    ad.serviceid,
    CASE WHEN ad.superuser IS NOT NULL AND ad.superuser != '' THEN ad.superuser
         WHEN ad.serviceid ilike 'postgresql%' THEN 'postgres'
         ELSE 'enterprisedb' END AS username,
    CASE WHEN ad.superuser IS NOT NULL AND ad.superuser != '' THEN ad.superuser
         WHEN ad.serviceid ilike 'postgresql%' THEN 'postgres'
         ELSE 'enterprisedb' END AS asb_username,
    CASE WHEN ad.serviceid ilike 'postgresql%' THEN 'postgres'
         ELSE 'edb' END AS database,
    ad.version,
    '127.0.0.1' AS host,
    '127.0.0.1' AS asb_host,
    'prefer' AS asb_sslmode,
    '1' AS gid
FROM
    pemdata.auto_discover_servers ad
LEFT JOIN
    pemdata.network_statistics ns ON (ns.agent_id = ad.agent_id AND ns.interface_name NOT ilike 'lo%%')
WHERE
    ad.agent_id = {{agent_id}}::int
    AND (
        ad.port NOT IN
            (
                SELECT asb.port
                FROM pem.agent_server_binding asb
                LEFT JOIN pem.server s ON (asb.server_id = s.id)
                WHERE ad.agent_id = asb.agent_id AND NOT s.is_remote_monitoring
            )
        )
GROUP BY ad.agent_id, ad.port;
