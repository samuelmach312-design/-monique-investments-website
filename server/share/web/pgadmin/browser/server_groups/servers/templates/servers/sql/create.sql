{% if data %}
INSERT INTO pem.server (
    description,
    server,
    port,
    database,
    serviceid,
    hostaddr,
    service,
    team,
    comment,
    tags,
    post_connection_sql
    {% if data.replication_solution is defined %}, replication_solution{% endif %}
    {% if data.efm_cluster_name is defined %}, efm_cluster_name{% endif %}
    {% if data.efm_service_name is defined %}, efm_service_name{% endif %}
    {% if data.efm_installation_path is defined %}, efm_installation_path{% endif %}
    {% if data.patroni_cluster_name is defined %}, patroni_cluster_name{% endif %}
    {% if data.patroni_installation_path is defined %}, patroni_installation_path{% endif %}
    {% if data.patroni_config_path is defined %}, patroni_config_path{% endif %}
    {% if data.profile_id is defined %}, profile_id{% endif %}
)
VALUES (
    {{data.name|qtLiteral(conn, True)}}::text,
    {{data.host|qtLiteral(conn, True)}}::text,
    {{data.port}}::int4,
    {{data.db|qtLiteral(conn, True)}}::text,
    {{data.serviceid|qtLiteral(conn, True)}}::text,
    {{data.hostaddr|qtLiteral(conn, True)}}::text,
    NULL::text,
    {{data.team|qtLiteral(conn, True)}}::text,
    {{data.comment|qtLiteral(conn, True)}}::text,
    '{{ data.tags | tojson }}'::jsonb,
    {{data.post_connection_sql|qtLiteral(conn, True)}}::text
    {% if data.replication_solution is defined %}, {{data.replication_solution|qtLiteral(conn, True)}}::text{% endif %}
    {% if data.efm_cluster_name is defined %}, {{data.efm_cluster_name|qtLiteral(conn, True)}}::text{% endif %}
    {% if data.efm_service_name is defined %}, {{data.efm_service_name|qtLiteral(conn, True)}}::text{% endif %}
    {% if data.efm_installation_path is defined %}, {{data.efm_installation_path|qtLiteral(conn, True)}}::text{% endif %}
    {% if data.patroni_cluster_name is defined %}, {{data.patroni_cluster_name|qtLiteral(conn, True)}}::text{% endif %}
    {% if data.patroni_installation_path is defined %}, {{data.patroni_installation_path|qtLiteral(conn, True)}}::text{% endif %}
    {% if data.patroni_config_path is defined %}, {{data.patroni_config_path|qtLiteral(conn, True)}}::text{% endif %}
    {% if data.profile_id is defined %}
        {% if data.profile_id is none %}
            , NULL 
        {% else %}
            , {{data.profile_id|qtLiteral(conn, True)}}::int4
        {% endif %}
    {% endif %}
)
RETURNING id;
{% endif %}