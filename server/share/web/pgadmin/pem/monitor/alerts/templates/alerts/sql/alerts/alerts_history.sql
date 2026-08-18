SELECT
	ah.alert_id, ah.generated,
	CASE
	WHEN ah.state = 'HIGH' THEN 'High'
	WHEN ah.state = 'MEDIUM' THEN 'Medium'
	WHEN ah.state = 'LOW' THEN 'Low'
	END as state,
	CASE
	WHEN COALESCE(ah.display_value, '')::text != '' THEN ah.display_value
	ELSE pem.unit_converter(ah.value, at.threshold_unit)
	END AS value, ah.value AS actual_value
FROM pem.alert_history ah
LEFT JOIN pem.alert a ON (ah.alert_id = a.id)
LEFT JOIN pem.alert_template at ON (a.template_id = at.id) {% if alert_id is not none %}
WHERE ah.alert_id = {{ alert_id }}::integer
{% endif %} {% if server_id is not none %}
WHERE a.server_id = {{ server_id }}::integer {% if database_name is not none %} AND
a.database_name = {{ database_name|qtLiteral(conn, True) }}{% endif %}{% endif %} {% if agent_id is not none %}
WHERE a.agent_id = {{ agent_id }}::integer {% endif %}
ORDER BY 1, 3 DESC
