{% if upsert_alerts %}
-- Allow multiple alerts per template distinguished by name.
INSERT INTO pem.profile_alert_configs (
    profile_id, template_id, name, params, operator, thresholds, check_frequency, history_retention,
    enabled, email_group_id, send_email, send_trap, snmp_trap_version, low_send_trap, low_email_group_id,
    med_send_trap, med_email_group_id, high_send_trap, high_email_group_id, execute_script,
    execute_script_on_clear, execute_script_on_pem_server, script_code, submit_to_nagios,
    cleared_alert_enable, send_notification, override_default_config, low_webhook_ids, med_webhook_ids,
    high_webhook_ids, cleared_webhook_ids
) VALUES (
    %(profile_id)s, %(template_id)s, %(name)s, %(params)s, %(operator)s, %(thresholds)s, %(check_frequency)s, %(history_retention)s,
    %(enabled)s, %(email_group_id)s, %(send_email)s, %(send_trap)s, %(snmp_trap_version)s, %(low_send_trap)s, %(low_email_group_id)s,
    %(med_send_trap)s, %(med_email_group_id)s, %(high_send_trap)s, %(high_email_group_id)s, %(execute_script)s,
    %(execute_script_on_clear)s, %(execute_script_on_pem_server)s, %(script_code)s, %(submit_to_nagios)s,
    %(cleared_alert_enable)s, COALESCE(%(send_notification)s, FALSE), COALESCE(%(override_default_config)s, FALSE),
    %(low_webhook_ids)s, %(med_webhook_ids)s,
    %(high_webhook_ids)s, %(cleared_webhook_ids)s
);

{% elif update_alert_config %}
UPDATE pem.profile_alert_configs SET
    template_id = %(template_id)s,
    name = %(name)s,
    params = %(params)s,
    operator = %(operator)s,
    thresholds = %(thresholds)s,
    check_frequency = %(check_frequency)s,
    history_retention = %(history_retention)s,
    enabled = %(enabled)s,
    email_group_id = %(email_group_id)s,
    send_email = %(send_email)s,
    send_trap = %(send_trap)s,
    snmp_trap_version = %(snmp_trap_version)s,
    low_send_trap = %(low_send_trap)s,
    low_email_group_id = %(low_email_group_id)s,
    med_send_trap = %(med_send_trap)s,
    med_email_group_id = %(med_email_group_id)s,
    high_send_trap = %(high_send_trap)s,
    high_email_group_id = %(high_email_group_id)s,
    execute_script = %(execute_script)s,
    execute_script_on_clear = %(execute_script_on_clear)s,
    execute_script_on_pem_server = %(execute_script_on_pem_server)s,
    script_code = %(script_code)s,
    submit_to_nagios = %(submit_to_nagios)s,
    cleared_alert_enable = %(cleared_alert_enable)s,
    send_notification = COALESCE(%(send_notification)s, FALSE),
    override_default_config = COALESCE(%(override_default_config)s, FALSE),
    low_webhook_ids = %(low_webhook_ids)s,
    med_webhook_ids = %(med_webhook_ids)s,
    high_webhook_ids = %(high_webhook_ids)s,
    cleared_webhook_ids = %(cleared_webhook_ids)s
WHERE id = %(id)s::integer;

{% elif delete_alert_config %}
{#
  This query performs a DELETE operation. It can delete a single alert
  by 'id' or multiple alerts belonging to a 'profile_id'.
#}
DELETE FROM pem.profile_alert_configs
WHERE id = %(id)s::integer;

{% endif %}
