{# Update existing alert parameters #}
UPDATE pem.alert SET
{% for col in data %}
    {% if not loop.first %}, {% endif %}
    {{ col }} =
    {% if data[col] is not none %}
        {% if col_type[col] in ['integer', 'int4', 'int8', 'boolean'] %}
            {{ data[col] }}
        {% elif col_type[col] == 'char' %}
            '{{ data[col] }}'::char
        {% elif col_type[col].endswith('[]') %}
            -- Column type is an array
            ARRAY[
                {% if data[col] is string %}
                    -- Array data is a string
                    {{ data[col].split(', ') | map('qtLiteral', conn) | join(', ') }}
                {% else %}
                    {% if data[col] | length > 1 %}
                        -- Array data is a list with multiple items
                        {% for item in data[col] %}
                            {% if col_type[col] == 'integer' %}
                                {{ item }}::integer
                            {% elif col_type[col] == 'boolean' %}
                                {{ item | lower }}::boolean
                            {% elif col_type[col] == 'string' %}
                                '{{ item }}'::text
                            {% else %}
                                -- Item is of unknown type, escaping
                                '{{ item | qtLiteral(conn) }}'
                            {% endif %}
                            {% if not loop.last %}, {% endif %}
                        {% endfor %}
                    {% elif data[col] %}
                        -- Array data is a list with one item
                        '{{ data[col] | map('qtLiteral', conn) | join('') }}'
                    {% else %}
                        -- Array data is an empty list
                    {% endif %}
                {% endif %}
            ]::{{ col_type[col] }}
        {% else %}
            {{ data[col] | qtLiteral(conn, True) }}::{{ col_type[col] }}
        {% endif %}
    {% else %}
        NULL::{{ col_type[col] }}
    {% endif %}
{% endfor %}
WHERE id = {{ alert_id }}::int4;

UPDATE pem.alert SET send_email = (
    CASE WHEN email_group_id IS null AND low_email_group_id IS null AND
    med_email_group_id IS null AND high_email_group_id IS null THEN false
    ELSE true
    END)
WHERE id = {{ alert_id }}::int4;
