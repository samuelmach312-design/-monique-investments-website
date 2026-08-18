{# Get pem.webhook_alert_config table column type information #}
SELECT att.attname as name, format_type(ty.oid,NULL) AS datatype
FROM pg_attribute att
 JOIN pg_type ty ON ty.oid=atttypid
WHERE
 att.attrelid = (SELECT 'pem.webhook_alert_config'::regclass::oid)
 AND att.attisdropped IS FALSE
ORDER BY att.attnum
