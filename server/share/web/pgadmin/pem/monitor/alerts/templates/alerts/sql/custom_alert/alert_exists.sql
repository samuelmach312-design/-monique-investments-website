{# Get any alert exists with given alert template id #}
{% if alert_template_id %}
SELECT
    COALESCE(COUNT(*), 0)::integer AS alert_count
FROM
    pem.alert
WHERE
    template_id = {{ alert_template_id }}::integer;
{% endif %}