{# Update existing email group data #}
{% if update_name %}
UPDATE pem.email_group SET name = {{ name|qtLiteral(conn, True) }}::text
    WHERE id = {{ id }}::integer;
{% else %}
{% if data|length > 0 %}
UPDATE pem.email_group_option SET
{% for col in data %}
{% if not loop.first %}, {% endif %}{{ conn|qtIdent(col) }} = {{ data[col]|qtLiteral(conn, True) }} {% endfor %}
WHERE id = {{ id }}::integer;
{% endif %}
{% endif %}
