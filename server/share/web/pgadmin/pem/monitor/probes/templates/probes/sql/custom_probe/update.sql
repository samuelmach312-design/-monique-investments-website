{% if update_probe %}
UPDATE pem.probe SET
{% for col in data %}
    {% if not loop.first %}, {% endif %}
    {{ col }} = %({{ col }})s
{% endfor %}
WHERE id = %(probe_id)s::int4
{% endif %}
{% if update_column %}
UPDATE pem.probe_column SET
{% for col in data %}
{% if not loop.first %}, {% endif %}{{ col }} = %({{ col }})s {% endfor %}
WHERE id = %(id)s::int4 AND probe_id = %(probe_id)s::int4
{% endif %}
{% if update_server_code %}
UPDATE pem.probe_server_version SET
    probe_code = %(probe_code)s::text
WHERE probe_id = %(probe_id)s::int4 AND server_version_id = %(server_version_id)s::int4
{% if extension_version is defined %}
    AND extension_version = %(extension_version)s::text
{% endif %}
{% endif %}
