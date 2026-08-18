WITH alert_timings AS 
(
	SELECT
		ast.last_execution_duration
	FROM
		pem.alert AS al
		LEFT JOIN pem.alert_status AS ast ON(al.id = ast.alert_id)
	WHERE al.enabled = true
		AND (
			COALESCE(al.error_message, '' ) IN ('', 'Zero rows returned')
			OR al.error_message LIKE 'Required probe(s) %'
		)
		AND
			CASE
				WHEN al.agent_id IN (-1 , 0) THEN TRUE
				ELSE al.agent_id IN (SELECT id FROM pem.agent WHERE active AND NOT alert_blackout)
			END
		AND
			CASE
			WHEN (al.server_id IS NULL) OR (al.server_id = 0) THEN TRUE
			ELSE al.server_id IN
				(
					SELECT id FROM pem.server WHERE active AND NOT alert_blackout
					INTERSECT
					SELECT server_id FROM pem.agent_server_binding
				)
			END
			ORDER BY last_processed
)
SELECT
	max(last_execution_duration) AS max_alert_processing_time,
	min(last_execution_duration) AS min_alert_processing_time,
	avg(last_execution_duration) AS avg_alert_processing_time,
	percentile_cont(0.5) WITHIN GROUP (ORDER BY last_execution_duration) AS percentile_50_alert_processing_time,
	percentile_cont(0.9) WITHIN GROUP (ORDER BY last_execution_duration) AS percentile_90_alert_processing_time,
	percentile_cont(0.95) WITHIN GROUP (ORDER BY last_execution_duration) AS percentile_95_alert_processing_time,
	percentile_cont(0.99) WITHIN GROUP (ORDER BY last_execution_duration) AS percentile_99_alert_processing_time
FROM alert_timings
WHERE last_execution_duration IS NOT NULL;