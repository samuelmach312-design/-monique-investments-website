SELECT
    server_id,
    edb_audit,
    edb_audit as log_format,
    edb_audit_directory,
    edb_audit_filename,
    edb_audit_rotation_day,
    edb_audit_rotation_size,
    edb_audit_rotation_sec,
    edb_audit_connect,
    edb_audit_disconnect,
    edb_audit_statements,
    log_collection,
    log_collection_frequency,
    edb_audit_tag,
    edb_audit_destination
FROM pem.audit_configuration
WHERE server_id IN (
{% for _ in server_id %}
  {% if loop.index > 1 %},
  {% endif %}
  (%s)::int4
{% endfor %}
)