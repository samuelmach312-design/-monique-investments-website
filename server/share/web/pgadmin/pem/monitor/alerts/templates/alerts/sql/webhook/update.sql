{# Update existing webhook data #}
{% if update_webhook %}
UPDATE pem.webhook_endpoints SET
{% for col in data %}
{% if not loop.first %}, {% endif %}{{ conn|qtIdent(col) }} = 
{% if col == 'payload_template' %}
    '{{ data[col].replace("'", "''") }}'::text
{% else %}
    {{ data[col]|qtLiteral(conn, True) }}
{% endif %}
{% endfor %}
WHERE id = {{ id }}::integer;
{% else %}
UPDATE pem.webhook_http_headers SET
{% for col in data %}
{% if not loop.first %}, {% endif %}{{ conn|qtIdent(col) }} = {{ data[col]|qtLiteral(conn, True) }} 
{% endfor %}
WHERE id = {{ http_header_id }}::integer;
{% endif %}