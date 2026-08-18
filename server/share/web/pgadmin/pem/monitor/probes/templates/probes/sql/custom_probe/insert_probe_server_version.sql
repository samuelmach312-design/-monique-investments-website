{% if insert_server_code %}
INSERT INTO pem.probe_server_version
    (probe_id, server_version_id, probe_code)
VALUES (
    %(probe_id)s::int4, %(server_version_id)s::int4, %(probe_code)s::text)
{% endif %}
