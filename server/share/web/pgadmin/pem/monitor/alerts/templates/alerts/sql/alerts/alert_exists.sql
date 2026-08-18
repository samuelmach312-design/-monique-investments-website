{% if alert_id is defined %}
SELECT COUNT(*) AS alert_count
FROM pem.alert a
WHERE a.id = %(alert_id)s::integer
{% if agent_id is defined %} AND agent_id = {{ agent_id }} {% endif %}
{% if server_id is defined %} AND server_id = {{ server_id }} {% endif %}
{% if database_name is defined %} AND database_name = {{ database_name|qtLiteral(conn, True) }}::text {% endif %}
{% if schema_name is defined %} AND schema_name = {{ schema_name|qtLiteral(conn, True) }}::text {% endif %}
{% if object_name is defined %} AND object_name = {{ object_name|qtLiteral(conn, True) }}::text {% endif %}
{% if package_name is defined %} AND package_name = {{ package_name|qtLiteral(conn, True) }}::text {% endif %}
{% endif %}
