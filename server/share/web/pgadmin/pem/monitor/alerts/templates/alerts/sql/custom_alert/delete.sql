{# Delete custom alert template #}
DELETE FROM
    pem.alert_template
WHERE
    id IN ({{placeholders}}) AND is_system_template = false
