{% if data %}
{% set flag = False %}
UPDATE pem.server
SET
{% if data.name is defined %}
    description = {{data.name|qtLiteral(conn, True)}}::text
{% set flag = True %}
{% endif %}
{% if data.profile_id is defined %}
    profile_id = {% if data.profile_id is not none %}{{data.profile_id|qtLiteral(conn, True)}}::int4
    {% else %}NULL {% endif %}
{% set flag = True %}
{% endif %}
{% if data.host is defined %}
    {% if flag == True %}, {% endif %}{% set flag = True %}server = {{data.host|qtLiteral(conn, True)}}::text
{% endif %}
{% if data.port is defined %}
    {% if flag == True %}, {% endif %}{% set flag = True %}port = {{data.port}}::int4
{% endif %}
{% if data.db is defined %}
    {% if flag == True %}, {% endif %}{% set flag = True %}database = {{data.db|qtLiteral(conn, True)}}::text
{% endif %}
{% if data.ssl is defined %}
    {% if flag == True %}, {% endif %}{% set flag = True %}ssl = {{data.ssl}}::int4
{% endif %}
{% if data.serviceid is defined %}
    {% if flag == True %}, {% endif %}{% set flag = True %}serviceid = {{data.serviceid|qtLiteral(conn, True)}}::text
{% endif %}
{% if data.hostaddr is defined %}
    {% if flag == True %}, {% endif %}{% set flag = True %}hostaddr = {{data.hostaddr|qtLiteral(conn, True)}}::text
{% endif %}
{% if data.team is defined and canupdate == True %}
    {% if flag == True %}, {% endif %}{% set flag = True %}team = {{data.team|qtLiteral(conn, True)}}::text
{% endif %}
{% if data.is_remote_monitoring is defined %}
    {% if flag == True %}, {% endif %}{% set flag = True %}is_remote_monitoring = {{data.is_remote_monitoring}}::boolean
{% endif %}
{% if data.alert_blackout is defined %}
    {% if flag == True %}, {% endif %}{% set flag = True %}alert_blackout = {{data.alert_blackout}}::boolean
{% endif %}
{% if data.tags is defined %}
    {% if flag == True %}, {% endif %}{% set flag = True %}tags = '{{ data.tags | tojson }}'::jsonb
{% endif %}
{% if data.efm_cluster_name is defined %}
    {% if flag == True %}, {% endif %}{% set flag = True %}efm_cluster_name = {{data.efm_cluster_name|qtLiteral(conn, True)}}::text
{% endif %}
{% if data.efm_service_name is defined %}
    {% if flag == True %}, {% endif %}{% set flag = True %}efm_service_name = {{data.efm_service_name|qtLiteral(conn, True)}}::text
{% endif %}
{% if data.efm_installation_path is defined %}
    {% if flag == True %}, {% endif %}{% set flag = True %}efm_installation_path = {{data.efm_installation_path|qtLiteral(conn, True)}}::text
{% endif %}
{% if data.replication_solution is defined %}
    {% if flag == True %}, {% endif %}{% set flag = True %}replication_solution = {{data.replication_solution|qtLiteral(conn, True)}}::text
{% endif %}
{% if data.patroni_cluster_name is defined %}
    {% if flag == True %}, {% endif %}{% set flag = True %}patroni_cluster_name = {{data.patroni_cluster_name|qtLiteral(conn, True)}}::text
{% endif %}
{% if data.patroni_installation_path is defined %}
    {% if flag == True %}, {% endif %}{% set flag = True %}patroni_installation_path = {{data.patroni_installation_path|qtLiteral(conn, True)}}::text
{% endif %}
{% if data.patroni_config_path is defined %}
    {% if flag == True %}, {% endif %}{% set flag = True %}patroni_config_path = {{data.patroni_config_path|qtLiteral(conn, True)}}::text
{% endif %}
{% if data.comment is defined %}
    {% if flag == True %}, {% endif %}{% set flag = True %}comment = {{data.comment|qtLiteral(conn, True)}}::text
{% endif %}
{% if data.post_connection_sql is defined %}
    {% if flag == True %}, {% endif %}{% set flag = True %}post_connection_sql = {{data.post_connection_sql|qtLiteral(conn, True)}}::text
{% endif %}
WHERE
    id = {{server_id}}::int4
RETURNING id;
{% endif %}
