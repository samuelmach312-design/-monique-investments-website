SELECT
	al.id, al.name, al.check_frequency, al.last_mail_send, ast.current_state AS state, at.display_name AS template_name,
	ast.last_processed, now(),
	(now() - COALESCE(ast.last_processed, '1900-01-01')) - (al.check_frequency||'minutes')::interval AS delayed_by
FROM (pem.alert AS al
	JOIN pem.alert_template AS at ON al.template_id = at.id)
  LEFT JOIN pem.alert_status AS ast ON(al.id = ast.alert_id)
WHERE al.enabled = true
	AND (
		COALESCE(al.error_message, '' ) IN ('', 'Zero rows returned')
		OR al.error_message LIKE 'Required probe(s) %'
	)
	AND ast.last_processed IS NOT NULL
	AND (now() - COALESCE(ast.last_processed, '1900-01-01')) >= (al.check_frequency||'minutes')::interval
/*
 * We process only those alerts that are bound to
 * 'active' agents and servers.
 *
 * Note:alert.agent_id, agent|server.active are defined
 * NOT NULL.
 */
	AND
		CASE
		WHEN al.agent_id IN (-1 , 0) THEN TRUE
		ELSE al.agent_id IN (
			SELECT id FROM pem.agent WHERE active AND NOT alert_blackout
		)
		END
	AND
		CASE WHEN (al.server_id IS NULL) OR (al.server_id = 0) THEN TRUE
		ELSE al.server_id IN (
			SELECT id FROM pem.server WHERE active AND NOT alert_blackout
			INTERSECT
			SELECT server_id FROM pem.agent_server_binding
		)
		END
ORDER BY delayed_by DESC LIMIT 50;