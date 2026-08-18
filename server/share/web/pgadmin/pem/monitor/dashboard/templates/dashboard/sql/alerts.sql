SELECT SUM(total) AS total, SUM(acknowledged) AS acknowledged FROM (
    {% if ctx.server_id is none %}
    SELECT
        count(*) AS total, sum(CASE WHEN pa.acknowledged THEN 1 ELSE 0 END) AS acknowledged
    FROM
        pem.alert pa, pem.alert_status pas, pem.avail_agents pag
    WHERE
        pa.id = pas.alert_id AND pas.current_state IS NOT NULL
        AND pa.enabled=true AND pa.agent_id = pag.id AND pag.active = TRUE
        AND NOT pag.alert_blackout AND COALESCE(pa.error_message, '') = ''
        {% if ctx.agent_id is not none %}AND pa.agent_id = {{ ctx.agent_id }}{% endif %}
    {% endif %}
    {% if ctx.server_id is none and ctx.agent_id is none %}
    UNION ALL
    SELECT
        count(*) AS total, sum(CASE WHEN pa.acknowledged THEN 1 ELSE 0 END) AS acknowledged
    FROM pem.alert pa, pem.alert_status pas, pem.alert_template pt
    WHERE
        pa.id = pas.alert_id
        AND pt.id = pa.template_id
        AND pas.current_state IS NOT NULL
        AND pa.enabled=true AND pt.object_type = 50
        AND COALESCE(pa.error_message, '') = ''
    UNION ALL
    {% endif %}
    {% if ctx.agent_id is none %}
    SELECT
        count(*) AS total, sum(CASE WHEN pa.acknowledged THEN 1 ELSE 0 END) AS acknowledged
    FROM
        pem.alert pa, pem.alert_status pas, pem.avail_servers ps
    WHERE
        pa.id = pas.alert_id AND pas.current_state IS NOT NULL
        AND pa.enabled=true AND pa.server_id = ps.id
        AND NOT ps.alert_blackout AND COALESCE(pa.error_message, '') = ''
        {% if ctx.server_id is not none %}
        AND pa.server_id = {{ ctx.server_id }}
        {% if ctx.database is not none %}
        AND pa.database_name = {{ ctx.database|qtLiteral(conn) }}
        {% if ctx.schema is not none %}
        AND pa.schema_name = {{ ctx.schema|qtLiteral(conn) }}
        {% endif %}
        {% endif %}
        {% endif %}
    {% endif %}
) alerts;

