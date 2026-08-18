SELECT
    id,
    name,
    parent_id
FROM pem.server_group a
WHERE 1 = 1
{% if parent_id is defined and parent_id is not none %}
  AND a.parent_id = {{ parent_id|qtLiteral(conn) }}::int4
{% endif %}
{% if id is defined and id is not none %}
  AND a.id = {{ id|qtLiteral(conn) }}::int4
{% endif %}
ORDER BY name;
