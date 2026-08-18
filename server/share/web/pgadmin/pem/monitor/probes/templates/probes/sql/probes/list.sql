{# Get all the probes for the given target type and parameters #}
SELECT p.target_type_id AS target_type_id_returned,
    ptv.probe_id AS probe_id,
    ptv.probe_display_name AS probe_name,
    ptv.enabled_by_default AS default_enabled,
    ptv.default_lifetime AS default_lifetime,
    ptv.default_execution_frequency AS default_interval,
    (ptv.default_execution_frequency/60)::int4 AS default_interval_min,
    (ptv.default_execution_frequency%%60) AS default_interval_sec,
    ptv.enabled AS enabled,
    ptv.execution_frequency AS interval,
    FLOOR(ptv.execution_frequency/60) AS interval_min,
    (ptv.execution_frequency%%60) AS interval_sec,
    ptv.lifetime AS lifetime,
    p.force_enabled As force_enabled
FROM
    pem.probe_target_view ptv, pem.probe p
WHERE
    ptv.probe_id = p.id AND
    (p.target_type_id = %(target_id)s::int4 OR p.applies_to_id = %(target_id)s::int4) AND
{% if probe_id is defined %}
    ptv.probe_id = %(probe_id)s::int4 AND
{% endif %}
{% if extension_name is not none %}
    p.extension_name = {{extension_name|qtLiteral(conn, True)}}::text AND
{% endif %}
    ptv.parameter_value_list IN ({{ parameters }})
ORDER BY ptv.probe_display_name
