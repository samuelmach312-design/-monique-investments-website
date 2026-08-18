{# Check if alert template require any parameter options #}
{% if alert_template_id is defined %}
SELECT
    COALESCE(array_length(param_names, 1), 0) AS param_count,
    object_type
FROM
    pem.alert_template
WHERE
    id = %(alert_template_id)s::integer;
{% endif %}
