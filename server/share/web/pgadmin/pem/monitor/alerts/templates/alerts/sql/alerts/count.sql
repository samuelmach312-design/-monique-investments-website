select at.object_type AS target_type_id, count(*) AS alert_count
FROM pem.alert a
LEFT OUTER JOIN pem.alert_template at ON a.template_id = at.id
GROUP BY target_type_id
ORDER BY target_type_id;