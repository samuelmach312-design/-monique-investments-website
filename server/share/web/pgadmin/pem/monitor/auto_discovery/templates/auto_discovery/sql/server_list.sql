SELECT
    ad.description as label, ad.description as value
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
