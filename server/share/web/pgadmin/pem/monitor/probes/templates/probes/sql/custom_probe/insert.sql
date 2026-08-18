{% if insert_probe %}
INSERT INTO pem.probe
    (id, display_name, internal_name, collection_method, target_type_id,
    enabled_by_default, force_enabled, default_execution_frequency,
    default_lifetime, any_server_version, probe_code, discard_history,
    is_system_probe, deleted, platform
{% if any_extension_version is defined %}
    ,any_extension_version, extension_name
{% endif %}
    )
VALUES ( %(id)s::integer,
    %(display_name)s::text, %(internal_name)s::text,
    %(collection_method)s::text, %(target_type_id)s::int4,
    %(enabled_by_default)s::boolean, False, %(default_execution_frequency)s::int4,
    %(default_lifetime)s::int4, %(any_server_version)s::boolean,
    %(probe_code)s::text,
    %(discard_history)s::boolean, False, False,
     %(platform)s::text
{% if any_extension_version is defined %}
    ,%(any_extension_version)s::boolean, %(extension_name)s::text
{% endif %}
    ) RETURNING id
{% endif %}
{% if insert_column %}
INSERT INTO pem.probe_column
    (probe_id, internal_name, display_name, display_position, classification,
    sql_data_type, unit_of_value, calculate_pit, discard_history, pit_by_default, is_graphable)
VALUES (
    %(probe_id)s::int4, %(internal_name)s::text, %(display_name)s::text, %(display_position)s::int4,
    %(classification)s::text, %(sql_data_type)s::text, %(unit_of_value)s::text, %(calculate_pit)s::boolean, False,
    %(pit_by_default)s::boolean, %(is_graphable)s::boolean)
{% endif %}

{% if insert_server_code and delete_sql %}
-- DELETE existing entry in probe_server_version
DELETE FROM pem.probe_server_version
WHERE probe_id = %(probe_id)s AND server_version_id = %(server_version_id)s;
{% endif %}

-- INSERT new entry into probe_server_version
{% if insert_server_code and insert_sql %}
INSERT INTO pem.probe_server_version
    (probe_id, server_version_id, probe_code)
VALUES (
    %(probe_id)s, %(server_version_id)s, %(probe_code)s);
{% endif %}

{% if insert_extension_code and delete_sql %}
-- DELETE probe_extension_version
DELETE FROM pem.probe_extension_version
WHERE probe_id = %(probe_id)s
AND server_version_id = %(server_version_id)s
AND extension_version = %(extension_version)s;
{% endif %}

-- INSERT probe_extension_version
{% if insert_extension_code and insert_sql %}
INSERT INTO pem.probe_extension_version
    (probe_id, server_version_id, extension_version, probe_code)
VALUES (
    %(probe_id)s, %(server_version_id)s, %(extension_version)s, %(probe_code)s);
{% endif %}
