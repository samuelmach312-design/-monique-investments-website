{% if insert_extension_code %}
INSERT INTO pem.probe_extension_version
    (probe_id, server_version_id, extension_version, probe_code)
VALUES (
    %(probe_id)s::int4, %(server_version_id)s::int4, %(extension_version)s::text, %(probe_code)s::text);
{% endif %}
