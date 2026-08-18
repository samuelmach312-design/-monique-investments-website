{# Delete alert from the list #}
DELETE FROM pem.alert WHERE id = ANY(%(alert_ids)s::int[])
