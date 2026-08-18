{# Insert new webhook #}
{% if insert_webhook %}
INSERT INTO pem.webhook_endpoints(
    name, url, enabled, method, payload_type, payload_template,
    low_alert, med_alert, high_alert, cleared_alert
)
VALUES(
    %(name)s::text,
    %(url)s::text, %(enabled)s::boolean,
    %(method)s::text, %(payload_type)s::text,
    %(payload_template)s::text,
    %(low_alert)s::boolean, %(med_alert)s::boolean,
    %(high_alert)s::boolean, %(cleared_alert)s::boolean) RETURNING id;
{% else %}
{# Insert new http header key value #}
INSERT INTO pem.webhook_http_headers
    (webhook_id, http_header_key, http_header_value)
VALUES (
    %(webhook_id)s::int4, %(http_header_key)s::text, %(http_header_value)s::text)
{% endif %}
