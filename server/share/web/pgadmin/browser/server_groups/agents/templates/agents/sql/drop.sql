UPDATE
    pem.agent
SET
    active = false
WHERE
{% if gid is defined %}
  group_id = {{ gid|qtLiteral(conn) }}::int4 AND
{% endif %}
  id = {{id|qtLiteral(conn)}}::int4;
