SELECT
    a.id AS agent_id,
    a.description AS name,
    a.agent_capability_list AS agent_capability_list,
    a.description AS agent_description,
    a.version AS agent_version,
    b.server_id AS server_id,
    b.server AS asb_host,
    b.port AS asb_port,
    b.username AS asb_username,
    b.database AS asb_database,
    b.sslmode AS asb_sslmode,
    b.password AS asb_password,
    s.description AS server_description,
    s.efm_service_name AS server_efm_service,
    s.efm_cluster_name AS server_efm_cluster,
    s.efm_installation_path AS server_efm_path,
    o.os_host_name AS host_name,
    o.os_domain_name AS domain_name,
    o.os_windows_domain AS windows_domain
FROM
    pem.avail_agents a
    LEFT OUTER JOIN pem.agent_server_binding b ON a.id = b.agent_id
    LEFT OUTER JOIN pem.avail_servers s ON b.server_id = s.id
    LEFT OUTER JOIN pemdata.os_info o ON a.id=o.agent_id
WHERE
    a.active = true
{% if agent_id AND server_id %}
    AND a.id = {{agent_id}}::int4 AND server_id = {{server_id}}::int4
{% elif agent_id %}
    AND a.id = {{agent_id}}::int4
{% elif server_id %}
    AND server_id = {{server_id}}::int4
{% endif %}
ORDER BY a.description, s.description;
