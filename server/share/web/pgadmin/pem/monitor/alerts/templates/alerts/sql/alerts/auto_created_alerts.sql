{# Get all the alerts that are auto_creted for server and agents #}

SELECT
    id as template_id, display_name as name, description, sql, cast(object_type as text), 
    param_names, param_types::text[], param_units, threshold_unit,
    default_check_frequency, default_history_retention, probe_dependency_list, applicable_on_server,
    is_system_template, is_auto_create, operator, thresholds, thresholds[1] AS low_threshold_value,
    thresholds[2] AS medium_threshold_value, thresholds[3] AS high_threshold_value, info_sql
FROM
    pem.alert_template
WHERE object_type in (200,100) and is_auto_create=true
ORDER BY display_name;