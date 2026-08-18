{# Update existing alert parameters #}
UPDATE pem.alert_template SET
{% for col in data %}
    {{ col }} = {% if data[col] is not none %}
        {% if col_type[col] in ['integer', 'int4', 'int8'] %}
            {{ data[col] }}
        {% elif col_type[col].endswith('[]') %}
            ARRAY{{ data[col]|qtLiteral(conn) }}::{{ col_type[col] }}
        {% else %}
            {{ data[col]|qtLiteral(conn, True) }}::{{ col_type[col] }}
        {% endif %}
    {% else %}
        NULL
    {% endif %}{% if not loop.last %}, {% endif %}
{% endfor %}
WHERE id = {{ alert_id }}::int4;
