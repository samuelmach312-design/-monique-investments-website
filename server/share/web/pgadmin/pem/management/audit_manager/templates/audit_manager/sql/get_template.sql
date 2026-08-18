SELECT
    id
FROM
    pem.alert_template
WHERE
    display_name = (%s)::text AND object_type = (%s)::int4 LIMIT 1
