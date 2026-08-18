{# Insert webhook alert config parameters #}
INSERT INTO pem.webhook_alert_config(
    alert_id, override_default_config, low_webhook_ids, med_webhook_ids, high_webhook_ids,
    cleared_webhook_ids, send_notification
)
VALUES((%s)::integer, (%s)::boolean, (%s)::integer[], (%s)::integer[], (%s)::integer[],
    (%s)::integer[], (%s)::boolean) RETURNING id;
