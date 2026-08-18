SELECT
    we.id,
    we.name,
    we.url,
    we.enabled,
    we.method,
    we.payload_template,
    we.low_alert,
    we.med_alert,
    we.high_alert,
    we.cleared_alert,
    we.payload_type,
    array_agg(whh.id) AS header_ids,
    array_agg(whh.http_header_key) AS header_keys,
    array_agg(whh.http_header_value) AS header_values
FROM
    pem.webhook_endpoints AS we
LEFT JOIN pem.webhook_http_headers AS whh ON (we.id = whh.webhook_id)
WHERE
    we.active
{% if webhook_type == 'alert' %}
    AND we.payload_type = 'ALERT'
{% endif %}
{% if webhook_id is defined and webhook_id is not none %}
    AND we.id = {{ webhook_id }}
{% endif %}
GROUP BY we.id
ORDER BY we.id;
