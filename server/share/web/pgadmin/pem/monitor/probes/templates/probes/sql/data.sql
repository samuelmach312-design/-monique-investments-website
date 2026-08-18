SELECT * FROM {{ pem_schema }}.{{ conn|qtIdent(probe_table) }}

{% if level == 100 %}
WHERE agent_id = {{ agent_id|qtLiteral(conn) }}
{% elif level == 200 %}
WHERE server_id = {{ server_id|qtLiteral(conn) }}
{% elif level == 300 %}
WHERE server_id = {{ server_id|qtLiteral(conn) }} AND database_name = {{ database_name|qtLiteral(conn, True) }}
{% elif level == 400 %}
WHERE server_id = {{ server_id|qtLiteral(conn) }} AND database_name = {{ database_name|qtLiteral(conn, True) }} AND schema_name = {{ schema_name|qtLiteral(conn, True) }}
{% elif level == 500 %}
WHERE server_id = {{ server_id|qtLiteral(conn) }} AND database_name = {{ database_name|qtLiteral(conn, True) }} AND schema_name = {{ schema_name|qtLiteral(conn, True) }} AND table_name = {{ table_name|qtLiteral(conn, True) }}
{% elif level == 600 %}
WHERE server_id = {{ server_id|qtLiteral(conn) }} AND database_name = {{ database_name|qtLiteral(conn, True) }} AND schema_name = {{ schema_name|qtLiteral(conn, True) }} AND index_name = {{ index_name|qtLiteral(conn, True) }}
{% elif level == 700 %}
WHERE server_id = {{ server_id|qtLiteral(conn) }} AND database_name = {{ database_name|qtLiteral(conn, True) }} AND schema_name = {{ schema_name|qtLiteral(conn, True) }} AND sequence_name  = {{ sequence_name |qtLiteral(conn, True) }}
{% elif level == 800 %}
WHERE server_id = {{ server_id|qtLiteral(conn) }} AND database_name = {{ database_name|qtLiteral(conn, True) }} AND schema_name = {{ schema_name|qtLiteral(conn, True) }} AND function_name = {{ function_name|qtLiteral(conn, True) }}
{% elif level == 900 %}
WHERE server_id = {{ server_id|qtLiteral(conn) }} AND database_name = {{ database_name|qtLiteral(conn, True) }} AND schema_name = {{ schema_name|qtLiteral(conn, True) }} AND view_name  = {{ view_name |qtLiteral(conn, True) }}
{% endif %}
{% if from_datetime is defined and from_datetime is not none %} AND
	recorded_time >= {{ from_datetime|qtLiteral(conn) }}
{% endif %}
{% if to_datetime is defined and to_datetime is not none %} AND
	recorded_time <= {{ to_datetime|qtLiteral(conn) }}
{% endif %}
