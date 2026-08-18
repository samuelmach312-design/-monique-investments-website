SELECT
    s.description as ServerName,
    ag.description as AgentName,
    a.name as AlertName,
    COALESCE(ah.state::text, 'CLEARED') as AlertType,
    round(ah.value, 3) as Value,
    ah.generated as AlertingSince
FROM
    pem.alert_history ah
LEFT JOIN pem.alert a ON ah.alert_id = a.id
LEFT JOIN pem.alert_template atm ON a.template_id = atm.id
LEFT OUTER JOIN pem.avail_servers s ON s.id = a.server_id
LEFT OUTER JOIN pem.avail_agents ag ON ag.id = a.agent_id
WHERE
    {% if overall_report %}
        atm.object_type = 50
    {% else %}
        {% if server_ids|length > 0 and agent_ids|length > 0 %}
            (a.server_id = ANY(ARRAY{{ server_ids }}) OR a.agent_id = ANY(ARRAY{{ agent_ids }}))
        {% elif server_ids|length > 0 %}
            a.server_id = ANY(ARRAY{{ server_ids }})
        {% elif agent_ids|length > 0 %}
            a.agent_id = ANY(ARRAY{{ agent_ids }})
        {% endif %}
    {% endif %}
    {% if alert_types_len > 1 %}
        AND (ah.state IN {{ alert_types|qtLiteral(conn) }}
        {% if is_clear_included %}
            OR ah.state IS NULL
        {% endif %}
        )
    {% else %}
        {% if alert_types is string %}
            {% if alert_types == 'CLEARED' %}
                AND ah.state IS NULL
            {% else %}
                AND (ah.state = {{ alert_types|qtLiteral(conn, True) }}
                {% if is_clear_included %}
                    OR ah.state IS NULL
                {% endif %}
                )
            {% endif %}
        {% else %}
            OR ah.state = {{ alert_types|qtLiteral(conn, True) }}
        {% endif %}
    {% endif %}
    AND ah.generated BETWEEN now() - interval {{ timeframe|qtLiteral(conn, True) }} AND now()
ORDER BY ah.generated;
