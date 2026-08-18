UPDATE pem.server_group
SET id = id
{% if data.name is defined %}
,name = {{data.name|qtLiteral(conn, True)}}::text
{% endif %}
{% if data.parent_id is defined %}
,parent_id = {{data.parent_id|qtLiteral(conn)}}::int4
{% endif %}
WHERE id = {{id|qtLiteral(conn)}}::int4
RETURNING *;
