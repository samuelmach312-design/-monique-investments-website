{% if insert_extension_code %}
DELETE FROM pem.probe_extension_version
WHERE probe_id = %(probe_id)s::int4
AND server_version_id = %(server_version_id)s::int4
AND extension_version = %(extension_version)s::text;
{% endif %}
