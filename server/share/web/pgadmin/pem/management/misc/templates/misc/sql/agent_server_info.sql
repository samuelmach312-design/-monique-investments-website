SELECT
    a.id AS agent_id,
    CASE
        WHEN 'allow_server_restart' = ANY(a.agent_capability_list)
            THEN TRUE
        ELSE FALSE
    END AS can_restart_server,
    CASE
        WHEN 'windows' = ANY(a.agent_capability_list)
            THEN TRUE
        ELSE FALSE
    END AS is_windows_server,
    s.serviceid AS service_id,
    s.efm_cluster_name AS efm_cluster_name,
    s.efm_installation_path AS efm_installation_path,
    s.patroni_cluster_name,
    s.patroni_installation_path,
    s.patroni_config_path,
    s.is_remote_monitoring,

    -- Get latest leader
    (
        SELECT pns.member_name
        FROM pemdata.patroni_node_status pns
        WHERE pns.server_id = s.id AND LOWER(pns.role) = 'leader'
        ORDER BY pns.recorded_time DESC
        LIMIT 1
    ) AS leader_name,

    -- Get replica list
    (
        SELECT STRING_AGG(pns.member_name, ', ')
        FROM pemdata.patroni_node_status pns
        WHERE pns.server_id = s.id AND LOWER(pns.role) = 'replica'
    ) AS replica_names

FROM pem.avail_agents a
LEFT JOIN pem.agent_server_binding b ON a.id = b.agent_id
LEFT JOIN pem.avail_servers s ON b.server_id = s.id
WHERE a.active = true
{% if server_id != 0 %}
  AND b.server_id = {{ server_id }}::int
{% endif %}
ORDER BY a.description, s.description;