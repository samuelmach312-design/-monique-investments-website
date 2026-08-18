{# Get all the probes for the given target type and parameters #}
{% if target_type == "server" %}
DELETE FROM pem.probe_config_server where server_id = {{object_id}}
{% elif target_type == "agent" %}
DELETE FROM pem.probe_config_agent where agent_id = {{object_id}}
{% elif target_type == "database" %}
DELETE FROM pem.probe_config_database where server_id = {{object_id}} and database_name = {{database_name|qtLiteral(conn)}}::text
{% elif target_type == "schema" %}
DELETE FROM pem.probe_config_schema where server_id = {{object_id}} and database_name = {{database_name|qtLiteral(conn)}}::text and schema_name = {{schema_name|qtLiteral(conn)}}::text
{% elif target_type == "extension" %}
DELETE FROM pem.probe_config_extension where server_id = {{object_id}} and database_name = {{database_name|qtLiteral(conn)}}::text and extension_name = {{extension_name|qtLiteral(conn)}}::text
{% endif %}
