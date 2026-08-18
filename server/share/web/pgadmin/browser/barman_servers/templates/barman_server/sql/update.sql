{% set flag = False %}
UPDATE pem.tool
    SET
{% if data.description is defined %}description = {{ data.description|qtLiteral(conn, True) }}{% set flag = True %}{% endif %}
{% if data.options is defined %}{% if flag %}, {% endif %}{% set flag = True %}options = {{ data.options|tojson|qtLiteral(conn) }}::jsonb{% endif %}
{% if data.team is defined %}{% if flag %}, {% endif %}{% set flag = True %}team = {{ data.team|qtLiteral(conn, True) }}{% endif %}
{% if data.gid is defined %}{% if flag %}, {% endif %}{% set flag = True %}gid = {{ data.gid|qtLiteral(conn) }}{% endif %}

WHERE id = {{ tool_id|qtLiteral(conn) }};
