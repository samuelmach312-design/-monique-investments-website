{% if insert_server_code %}
DELETE FROM pem.probe_server_version
WHERE probe_id = %(probe_id)s::int4 AND server_version_id = %(server_version_id)s::int4;
{% endif %}
