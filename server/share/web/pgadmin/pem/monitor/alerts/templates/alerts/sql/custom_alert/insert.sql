{# Add new custom alert template #}
SELECT pem.create_alert_template(
    {{ name|qtLiteral(conn, True) }}::text,
    {{ description|qtLiteral(conn, True) }}::text,
    {{ sql|qtLiteral(conn, True) }}::text,
    {{ object_type }}::int,
    {% if param_names %} ARRAY{{ param_names|qtLiteral(conn) }}::text[] {% else %} NULL::text[] {% endif %},
    {% if param_types %} ARRAY{{ param_types|qtLiteral(conn) }}::pem.alert_param_type[] {% else %} NULL::pem.alert_param_type[] {% endif %},
    {% if param_units %} ARRAY{{ param_units|qtLiteral(conn) }}::text[] {% else %} NULL::text[] {% endif %},
    {{ threshold_unit|qtLiteral(conn, True) }}::text,
    {% if probe_dependency_list %} ARRAY{{ probe_dependency_list|qtLiteral(conn) }}::text[] {% else %} ARRAY[]::text[] {% endif %},
    {{ snmp_oid }}::int,
    {{ applicable_on_server|qtLiteral(conn, True) }}::pem.server_type,
    {{ default_check_frequency }}::int,
    {{ default_history_retention }}::int,
    FALSE::boolean,
    {{ info_sql|qtLiteral(conn, True) }}::text,
    {{ is_auto_create|qtLiteral(conn) }}::boolean
    {% if is_auto_create == true %}
      , {{ operator|qtLiteral(conn, True) }}::text,
      ARRAY{{ thresholds|qtLiteral(conn) }}::numeric[]
    {% endif %}
    {% if reference_id %}
      ,reference_id := {{ reference_id|qtLiteral(conn, True) }}::text
    {% endif %}
    )
