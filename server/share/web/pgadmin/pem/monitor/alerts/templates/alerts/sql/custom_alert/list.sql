{# Get all the alert template for the given target type #}
{% if show_all_templates is defined %}
{% if show_all_templates %}
SELECT
    id, display_name as name, description, sql, cast(object_type as text), param_names, param_types::text[], param_units, threshold_unit,
    default_check_frequency, default_history_retention, probe_dependency_list, applicable_on_server,
    is_system_template, is_auto_create, operator, thresholds, thresholds[1] AS low_threshold_value,
    thresholds[2] AS medium_threshold_value, thresholds[3] AS high_threshold_value, info_sql
FROM
    pem.alert_template
{% if alert_template_id %}
WHERE id = {{ alert_template_id }}::integer
{% endif %}
ORDER BY
    display_name;
{% else %}
SELECT
    id, display_name as name, description, sql, cast(object_type as text), param_names, param_types::text[], param_units, threshold_unit,
    default_check_frequency, default_history_retention, probe_dependency_list, applicable_on_server,
    is_system_template, is_auto_create, operator, thresholds, thresholds[1] AS low_threshold_value,
    thresholds[2] AS medium_threshold_value, thresholds[3] AS high_threshold_value, info_sql
FROM
    pem.alert_template
WHERE
    is_system_template = False
    {%if show_alert_level > 0 %}
    OR  (object_type = {{ show_alert_level }} AND is_system_template = True)
    {% endif %}
ORDER BY
    display_name;
{% endif %}
{% endif %}
{#################################################}
{% if export_alerts is defined and export_alerts %}
SELECT
    display_name as name,
    description,
    reference_id,
    sql, info_sql,
    cast(object_type as text),
    param_names, param_types::text[], param_units,
    default_check_frequency, default_history_retention, probe_dependency_list, applicable_on_server,
    is_auto_create, operator, thresholds, thresholds[1] AS low_threshold_value,
    thresholds[2] AS medium_threshold_value, thresholds[3] AS high_threshold_value, threshold_unit
FROM
    pem.alert_template
WHERE
    is_system_template = False
{% if using_ids %}                  {# When we need to fetch using list of ids #}
    AND id IN ({{placeholders}})
{% else %}                          {# When we need to fetch using list of names #}
    AND display_name IN %s
{% endif %}
{% endif %}
