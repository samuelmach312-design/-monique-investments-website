{# Update existing alert webhook config parameters #}
UPDATE pem.webhook_alert_config SET
{% for col in data %}
{% if not loop.first %}, {% endif %}{{ conn|qtIdent(col) }} = 
{% if data[col] != 'NULL' %}
    {% if col_type[col].endswith('[]') %}
    -- Column type is an array
        ARRAY[
            {% if data[col] is string %}
                -- Array data is a string
                {{ data[col].split(', ') | map('qtLiteral', conn) | join(', ') }}
            {% else %}
                {% if data[col] | length > 1 %}
                    -- Array data is a list with multiple items
                    {% for item in data[col] %}
                        {% if col_type[col] == 'integer[]' %}
                            {{ item }}::integer
                        {% elif col_type[col] == 'boolean[]' %}
                            {{ item | lower }}::boolean
                        {% elif col_type[col] == 'string[]' %}
                            '{{ item }}'::text
                        {% else %}
                            -- Item is of unknown type, escaping
                            '{{ item | qtLiteral(conn) }}'
                        {% endif %}
                        {% if not loop.last %}, {% endif %}
                    {% endfor %}
                {% elif data[col] %}
                    -- Array data is a list with one item
                    {{ data[col][0] | qtLiteral(conn) }}
                {% else %}
                    -- Array data is an empty list
                {% endif %}
            {% endif %}
        ]::{{ col_type[col] }}
    {% else %}
        {{ data[col] | qtLiteral(conn) }}::{{ col_type[col] }}
    {% endif %}
{% else %}
    NULL
{% endif %}
{% endfor %}
WHERE alert_id = {{ alert_id }}::int4;