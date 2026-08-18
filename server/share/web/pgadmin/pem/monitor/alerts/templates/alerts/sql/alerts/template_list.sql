{# Get all the alert templates for the given target type #}
    SELECT
        at.id AS id,
        at.display_name AS display_name,
        at.param_names AS param_names,
        at.param_types AS param_types,
        replace(at.param_units::text, 'NULL', '') AS param_units,
        at.threshold_unit AS threshold_unit,
        at.default_check_frequency AS default_check_frequency,
        at.default_history_retention AS default_history_retention,
        (at.description || E'\n\nRequired probe(s): ' ||
            array_to_string(at.probe_dependency_list,','))  AS description
    FROM
        pem.alert_template at
    WHERE {{ comparision_condition }} {%if alert_template_id %} AND at.id={{ alert_template_id }} {% endif %}
    ORDER BY
        at.display_name