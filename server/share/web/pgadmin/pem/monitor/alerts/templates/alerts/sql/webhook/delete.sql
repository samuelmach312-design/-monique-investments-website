{# Delete webhook #}
{%if delete_webhook %}
DELETE FROM
    pem.webhook_endpoints
WHERE id in ({{placeholders}});
{% else %}
DELETE FROM
    pem.webhook_http_headers
WHERE id = {{ header_id }};
{% endif %}
