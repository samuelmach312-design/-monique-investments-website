{# Manages all CRUD and workflow operations for the pem.profile table. #}

{% if get_published_list_by_target %}
-- Fetches only the published profiles for the main list view.
SELECT id, name, description, target_kind
FROM pem.profile
WHERE status = 'published' AND target_kind = %(target_kind)s
ORDER BY name;

{% elif check_profile_assignment %}
-- Checks if the profile is assigned to any server or agent.
SELECT (
    (SELECT COUNT(*) FROM pem.server WHERE profile_id = %(profile_id)s and active)
    +
    (SELECT COUNT(*) FROM pem.agent WHERE profile_id = %(profile_id)s and active)
) AS assigned_count;


{% elif get_published_if_not_draft %}
-- Fetches published profiles if no draft is available for the published profile
SELECT
    COALESCE(d.id, p.id)              AS id,
    COALESCE(d.name, p.name)          AS name,
    COALESCE(d.description, p.description) AS description,
    p.target_kind,
    COALESCE(d.status, p.status) AS status,
    -- Count of associated servers/agents
    COALESCE(
        ((SELECT COUNT(*)::int
         FROM pem.server
         WHERE profile_id = COALESCE(p.id, d.id) and active) +
        (SELECT COUNT(*)::int
         FROM pem.agent
         WHERE profile_id = COALESCE(p.id, d.id) and active)),
        0
    ) AS active_assignments,

    -- Aggregation of Probe Configurations (Original Logic)
    COALESCE(
        (
            SELECT jsonb_agg(
                jsonb_build_object(
                    'probe_id', pr.id,
                    'enabled', COALESCE(pc.enabled, pr.enabled_by_default),
                    'interval', COALESCE(pc.execution_frequency, pr.default_execution_frequency),
                    'lifetime', COALESCE(pc.lifetime, pr.default_lifetime),
                    'probe_name', pr.display_name,
                    'default_enabled', pr.enabled_by_default,
                    'default_interval', pr.default_execution_frequency,
                    'default_lifetime', pr.default_lifetime,
                    'target_type', pr.target_type_id,
                    'force_enabled', pr.force_enabled
                )
            ORDER BY pr.display_name
            )
            FROM pem.probe pr
            LEFT OUTER JOIN pem.profile_probe_configs pc ON pr.id = pc.probe_id
            WHERE pc.profile_id = COALESCE(d.id, p.id) OR pc.profile_id IS NULL
        ),
        '[]'::jsonb
    ) AS target_probe_configs,

COALESCE(
    (
        SELECT jsonb_agg(
            jsonb_build_object(
                'id', ac.id, -- Using ac.id as the unique identifier for the config row
                'alert_name', ac.name,
                'alert_template', cast(ac.template_id as text),
                'description', at.description,
                'params', ac.params,
                'param_names', at.param_names,
                'param_types', at.param_types,
                'params_units', at.param_units,
                'threshold_unit', at.threshold_unit,
                'operator', ac.operator,
                'thresholds', ac.thresholds,
                'frequency_min', ac.check_frequency,
                'history_retention', ac.history_retention,
                'enabled', ac.enabled,
                'low_threshold_value', ac.thresholds[1],
                'medium_threshold_value', ac.thresholds[2],
                'high_threshold_value', ac.thresholds[3],
                'email_group_id', cast(COALESCE(ac.email_group_id,1) as text),
                'email_group_name', CASE WHEN eg.name IS NULL THEN '<Default>' ELSE eg.name END::text,
                -- Pulling default values from pem.alert_template (at)
                'default_frequency', at.default_check_frequency,
                'default_history_retention', at.default_history_retention,
                'auto_created', at.is_auto_create,
                'email_group_id', ac.email_group_id,
                'send_email', ac.send_email,
                -- 'flapping_detected', ac.flapping_detected,
                -- 'last_flapping_detection_processed', ac.last_flapping_detection_processed,
                'send_trap', ac.send_trap,
                'frequency_default', CASE WHEN ac.check_frequency = at.default_check_frequency THEN true ELSE false END::boolean,
                'history_retention_default', CASE WHEN ac.history_retention = at.default_history_retention THEN true ELSE false END::boolean,
                'snmp_trap_version', ac.snmp_trap_version,
                'low_send_trap', ac.low_send_trap,
                'low_email_group_id', ac.low_email_group_id,
                'med_send_trap', ac.med_send_trap,
                'med_email_group_id', ac.med_email_group_id,
                'high_send_trap', ac.high_send_trap,
                'high_email_group_id', ac.high_email_group_id,
                'execute_script', ac.execute_script,
                'execute_script_on_clear', ac.execute_script_on_clear,
                'execute_script_on_pem_server', CASE WHEN ac.execute_script_on_pem_server IS TRUE THEN '1' ELSE '0' END::text,
                'script_code', ac.script_code,
                'submit_to_nagios', ac.submit_to_nagios,
                'cleared_alert_enable', ac.cleared_alert_enable,
                'all_alert_enable', CASE WHEN ac.email_group_id IS NULL THEN false ELSE true END::boolean,
                'low_alert_enable', CASE WHEN ac.low_email_group_id IS NULL THEN false ELSE true END::boolean,
                'med_alert_enable', CASE WHEN ac.med_email_group_id IS NULL THEN false ELSE true END::boolean,
                'high_alert_enable', CASE WHEN ac.high_email_group_id IS NULL THEN false ELSE true END::boolean,

                -- New webhook columns
                'send_notification', ac.send_notification,
                'override_default_config', ac.override_default_config,
                'low_webhook_ids', ac.low_webhook_ids,
                'med_webhook_ids', ac.med_webhook_ids,
                'high_webhook_ids', ac.high_webhook_ids,
                'cleared_webhook_ids', ac.cleared_webhook_ids
            )
            ORDER BY COALESCE(at.is_auto_create, FALSE) DESC, ac.name
        )
        FROM pem.profile_alert_configs ac
        -- UPDATED: Changed to LEFT JOIN to handle NULL template_id
        LEFT JOIN pem.alert_template at ON at.id = ac.template_id
        LEFT OUTER JOIN pem.email_group eg ON ac.email_group_id = eg.id
        -- The WHERE clause links the configuration to the target profile
        WHERE ac.profile_id = COALESCE(d.id, p.id)
    ),
    '[]'::jsonb
) AS target_alert_configs

FROM pem.profile p
LEFT JOIN pem.profile d
    ON d.parent_id = p.id
   AND d.status = 'draft'
WHERE p.status = 'published'
ORDER BY name;

{% elif get_profile_status %}
-- Fetches the status and parent_id for a given profile ID.
SELECT status, parent_id, description, name FROM pem.profile WHERE id = %(id)s;

{% elif get_draft %}
-- Fetches an existing draft for a given published profile.
SELECT id, name, description FROM pem.profile WHERE parent_id = %(parent_id)s AND status = 'draft';

{% elif create_profile %}
-- Inserts a new, published profile.
-- 'description' is optional; if NULL or blank omit the column so driver
-- doesn't require a bound parameter. This lets callers skip providing it.
{% if description is defined and description is not none and description|trim != '' %}
INSERT INTO pem.profile (name, description, target_kind)
VALUES (%(name)s, %(description)s, %(target_kind)s)
{% else %}
INSERT INTO pem.profile (name, target_kind)
VALUES (%(name)s, %(target_kind)s)
{% endif %}
RETURNING id;

{% elif create_draft_from_parent %}
-- CORRECTED: This now copies the name and description from the parent to the new draft.
INSERT INTO pem.profile (name, description, target_kind, status, parent_id)
SELECT name, description, target_kind, 'draft', id
FROM pem.profile
WHERE id = %(parent_id)s
RETURNING id, name, description;

{% elif copy_probe_config_to_draft %}
-- Copies all probe configurations from a parent profile to its new draft.
INSERT INTO pem.profile_probe_configs (profile_id, probe_id, enabled, execution_frequency, enabled_by_default, lifetime)
SELECT %(draft_id)s, probe_id, enabled, execution_frequency, enabled_by_default, lifetime
FROM pem.profile_probe_configs
WHERE profile_id = %(parent_id)s;

{% elif copy_alert_config_to_draft %}
-- NEW BLOCK: Copies alert configurations from parent profile to new draft.
INSERT INTO pem.profile_alert_configs (
    profile_id, template_id, name, params, operator, thresholds, check_frequency, history_retention,
    enabled, email_group_id, send_email, send_trap, snmp_trap_version, low_send_trap, low_email_group_id,
    med_send_trap, med_email_group_id, high_send_trap, high_email_group_id, execute_script,
    execute_script_on_clear, execute_script_on_pem_server, script_code, submit_to_nagios,
    cleared_alert_enable, send_notification, override_default_config, low_webhook_ids, med_webhook_ids,
    high_webhook_ids, cleared_webhook_ids
)
SELECT
    %(draft_id)s, template_id, name, params, operator, thresholds, check_frequency, history_retention,
    enabled, email_group_id, send_email, send_trap, snmp_trap_version, low_send_trap, low_email_group_id,
    med_send_trap, med_email_group_id, high_send_trap, high_email_group_id, execute_script,
    execute_script_on_clear, execute_script_on_pem_server, script_code, submit_to_nagios,
    cleared_alert_enable, send_notification, override_default_config, low_webhook_ids, med_webhook_ids,
    high_webhook_ids, cleared_webhook_ids
FROM pem.profile_alert_configs
WHERE profile_id = %(parent_id)s;

{% elif update_profile %}
-- Securely updates the metadata of a profile.
-- Conditionally update name and/or description based on provided params.
-- Only columns with bound parameters will be updated.
{% if (name is defined and name is not none) or (description is defined and description is not none) %}
UPDATE pem.profile SET
    {% if name is defined and name is not none %}name = %(name)s
    {% endif %}
    {% if name is defined and name is not none and description is defined and description is not none %}, 
    {% endif %}
    {% if description is defined and description is not none %}description = %(description)s
    {% endif %}
WHERE id = %(id)s;
{% else %}
-- No metadata changes requested; noop to keep SQL execution path consistent.
SELECT 1;
{% endif %}

-- Sequence to publish a draft profile:
-- 1. Update the parent profile's metadata from the draft.
{% elif publish_delete_old_probe_config %}
DELETE FROM pem.profile_probe_configs WHERE profile_id = %(parent_id)s;
-- 2. Delete all existing probe configurations for the parent profile.
{% elif publish_promote_probes %}
UPDATE pem.profile_probe_configs SET profile_id = %(parent_id)s WHERE profile_id = %(draft_id)s;

-- 3. Promote all probe configurations from the draft to the parent profile.
{% elif publish_update_meta %}
UPDATE pem.profile p SET name = d.name, description = d.description FROM pem.profile d WHERE p.id = %(parent_id)s AND d.id = %(draft_id)s;

-- 4. Delete all existing alert configurations for the parent profile.
{% elif publish_delete_old_alert_config %}
DELETE FROM pem.profile_alert_configs WHERE profile_id = %(parent_id)s;

-- 5. Promote all alert configurations from the draft to the parent profile.
{% elif publish_promote_alerts %}
UPDATE pem.profile_alert_configs SET profile_id = %(parent_id)s WHERE profile_id = %(draft_id)s;

-- 6. Delete the draft profile.
{% elif publish_delete_draft %}
DELETE FROM pem.profile WHERE id = %(draft_id)s;

{% elif delete_profile %}
-- Deletes multiple profiles at once.
DELETE FROM pem.profile WHERE id = ANY(%(ids)s::int[]);

{% elif delete_draft %}
-- Deletes a single draft profile.
DELETE FROM pem.profile WHERE id = %(draft_id)s AND status = 'draft';

{% elif get_profile_details_for_server %}

SELECT p.id as profile_id, p.name as profile_name
FROM pem.profile p
JOIN pem.server s ON p.id = s.profile_id
WHERE s.id = %(server_id)s;

{% elif get_profile_for_agent %}

SELECT p.id as profile_id, p.name as profile_name
FROM pem.profile p
JOIN pem.agent a ON p.id = a.profile_id
WHERE a.id = %(agent_id)s;

{% endif %}
