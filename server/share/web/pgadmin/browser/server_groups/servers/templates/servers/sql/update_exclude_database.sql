{% if remove_dbs %}
UPDATE
    pem.agent_server_binding
SET
    exclude_databases = '{}'::text[]
WHERE server_id = {{ server_id|qtLiteral(conn) }}::int4
{% endif %}

{% if update_dbs %}

UPDATE
    pem.agent_server_binding
SET
    exclude_databases = {{ data.exclude_databases|qtLiteral(conn) }}::text[]
WHERE server_id = {{ server_id|qtLiteral(conn) }}::int4

{% endif %}
