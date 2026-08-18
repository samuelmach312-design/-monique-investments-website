{% if check_by_id %}
SELECT count(id) FROM pem.webhook_endpoints
WHERE id = %(webhook_id)s::integer
{% else %}
SELECT count(name) FROM pem.webhook_endpoints
WHERE name = %(name)s::text
{% endif %}
