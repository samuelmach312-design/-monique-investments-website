{% set flag = False %}
UPDATE pem.agent_server_binding
SET
{% if data.agent_id is defined %}
    agent_id={{data.agent_id}}::int4
    {% set flag = True %}
{% endif %}
{% if data.asb_host is defined %}
    {% if flag == True %}, {% endif %}{% set flag = True %}server={{data.asb_host|qtLiteral(conn, True)}}::text
{% endif %}
{% if data.asb_port is defined %}
    {% if flag == True %}, {% endif %}{% set flag = True %}port={{data.asb_port}}::int4
{% endif %}
{% if data.asb_username is defined %}
    {% if flag == True %}, {% endif %}{% set flag = True %}username={{data.asb_username|qtLiteral(conn, True)}}::text
{% endif %}
{% if data.asb_database is defined %}
    {% if flag == True %}, {% endif %}{% set flag = True %}database={{data.asb_database|qtLiteral(conn, True)}}::text
{% endif %}
{% if data.asb_sslmode is defined %}
    {% if flag == True %}, {% endif %}{% set flag = True %}sslmode={{data.asb_sslmode|qtLiteral(conn, True)}}::text
{% endif %}
{% if data.asb_password is defined %}
    {% if flag == True %}, {% endif %}{% set flag = True %}password={{data.asb_password|qtLiteral(conn, True)}}::text
{% endif %}
{% if data.asb_exclude_databases is defined %}
    {% if flag == True %}, {% endif %}{% set flag = True %}exclude_databases='{{ "{" + data.asb_exclude_databases | join(",") + "}" }}'::text[]
{% endif %}
{% if data.agent_allowtakeover is defined %}
    {% if flag == True %}, {% endif %}{% set flag = True %}allow_takeover={{data.agent_allowtakeover}}::boolean
{% endif %}
WHERE
    server_id = {{data.server_id}}::int4;
