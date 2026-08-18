UPDATE pem.agent_options
SET
{% if data.gid is defined %}
    group_id = {{ data.gid|qtLiteral(conn) }}::int4
{% endif%}
{% if data.name is defined %}
    {% if data.gid is defined %},{% endif %} description = {{ data.name|qtLiteral(conn, True) }}::text
{% endif%}
WHERE pem_user = current_user AND agent_id = {{ agid|qtLiteral(conn) }}::int4;
