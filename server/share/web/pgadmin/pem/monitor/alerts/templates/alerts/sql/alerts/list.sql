{# Get all the alerts for the given target type and parameters #}
    SELECT
        a.id AS id,
        a.name AS alert_name,
        cast(a.template_id as text) AS alert_template,
        at.description AS description,
        a.enabled AS enabled,
        at.is_auto_create AS auto_created,
        at.display_name AS template_id,
        a.agent_id AS agent_id,
        a.server_id AS server_id,
        a.database_name AS database_name,
        a.schema_name AS schema_name,
        a.package_name AS package_name,
        a.object_name AS object_name,
        a.params AS params,
        at.param_names AS param_names,
        at.param_types AS param_types,
        at.param_units AS params_units,
        at.threshold_unit AS threshold_unit,
        a.operator AS operator,
        a.thresholds AS thresholds,
        a.thresholds[1] AS low_threshold_value,
        a.thresholds[2] AS medium_threshold_value,
        a.thresholds[3] AS high_threshold_value,
        a.check_frequency AS frequency_min,
        at.default_check_frequency AS default_frequency,
        at.default_history_retention::text AS default_history_retention,
        CASE WHEN a.check_frequency = at.default_check_frequency THEN true ELSE false END::boolean AS frequency_default,
        a.history_retention  AS history_retention,
        CASE WHEN a.history_retention = at.default_history_retention THEN true ELSE false END::boolean AS history_retention_default,
        cast(COALESCE(a.email_group_id,1) as text) AS email_group_id,
        a.send_email AS send_email,
        a.send_trap AS send_trap,
        a.snmp_trap_version::text AS snmp_trap_version,
        ag.description AS agent_desc,
        s.description AS server_desc,
        CASE WHEN eg.name IS NULL THEN '<Default>' ELSE eg.name END::text AS email_group_name,
        a.low_send_trap AS low_send_trap,
        a.med_send_trap AS med_send_trap,
        a.high_send_trap AS high_send_trap,
        a.cleared_alert_enable AS cleared_alert_enable,
        cast(COALESCE(a.low_email_group_id,1) as text) AS low_email_group_id,
        cast(COALESCE(a.med_email_group_id,1) as text)  AS med_email_group_id,
        cast(COALESCE(a.high_email_group_id,1) as text) AS high_email_group_id,
        a.execute_script AS execute_script,
        a.execute_script_on_clear AS execute_script_on_clear,
        CASE WHEN a.execute_script_on_pem_server IS TRUE THEN '1' ELSE '0' END::text AS execute_script_on_pem_server,
        a.script_code AS script_code,
        a.submit_to_nagios AS submit_to_nagios,
        (
            SELECT name FROM pem.email_group WHERE id = COALESCE(a.low_email_group_id,1)
        ) AS low_email_group_name,
        (
            SELECT name FROM pem.email_group WHERE id = COALESCE(a.med_email_group_id,1)
        ) AS med_email_group_name,
        (
            SELECT name FROM pem.email_group WHERE id = COALESCE(a.high_email_group_id,1)
        ) AS high_email_group_name,
        CASE WHEN a.email_group_id IS NULL THEN false ELSE true END::boolean AS all_alert_enable,
        CASE WHEN a.low_email_group_id IS NULL THEN false ELSE true END::boolean AS low_alert_enable,
        CASE WHEN a.med_email_group_id IS NULL THEN false ELSE true END::boolean AS med_alert_enable,
        CASE WHEN a.high_email_group_id IS NULL THEN false ELSE true END::boolean AS high_alert_enable,
        wac.override_default_config AS override_default_config,
        wac.send_notification AS send_notification,
        wac.low_webhook_ids AS low_webhook_ids,
        wac.med_webhook_ids AS med_webhook_ids,
        wac.high_webhook_ids AS high_webhook_ids,
        wac.cleared_webhook_ids AS cleared_webhook_ids
    FROM
        pem.alert a
        LEFT OUTER JOIN pem.avail_agents ag ON a.agent_id = ag.id
        LEFT OUTER JOIN pem.avail_servers s ON a.server_id = s.id
        LEFT OUTER JOIN pem.alert_template at ON a.template_id = at.id
        LEFT OUTER JOIN pem.email_group eg ON a.email_group_id = eg.id
        LEFT OUTER JOIN pem.webhook_alert_config wac ON a.id = wac.alert_id
    WHERE {{ comparision_condition }}
    {% if alert_id %}
      AND a.id = %(alert_id)s::int4
    {% endif %}
    ORDER BY a.name
