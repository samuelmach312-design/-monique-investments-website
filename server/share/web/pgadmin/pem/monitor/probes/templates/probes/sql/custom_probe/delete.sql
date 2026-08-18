{% if delete_probe %}
UPDATE pem.probe SET
    deleted = true, enabled_by_default = false
WHERE id IN ({{ probe_ids }})
{% endif %}

{% if delete_server_code %}
DELETE FROM pem.probe_server_version
WHERE probe_id = {{ probe_id }}::int4 AND server_version_id = {{ server_version_id }}::int4
{% endif %}

{% if delete_extension_code %}
DELETE FROM pem.probe_extension_version
WHERE probe_id = {{ probe_id }}::int4
AND server_version_id = {{ server_version_id }}::int4
AND extension_version = {{ extension_version|qtLiteral(conn, true) }}::text;
{% endif %}
