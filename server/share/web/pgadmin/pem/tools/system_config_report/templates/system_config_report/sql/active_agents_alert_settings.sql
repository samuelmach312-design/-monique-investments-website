SELECT
ac.agent_id, ac.param, ac.value
FROM pem.agent_config ac JOIN pem.agent a ON (ac.agent_id = a.id)
WHERE a.active AND
CASE ac.param
WHEN 'alert_threads' THEN ac.value != '0'
WHEN 'enable_smpt' THEN ac.value = 'true'
WHEN 'enable_snmp' THEN ac.value = 'true'
WHEN 'enable_webhooks' THEN ac.value = 'true'
WHEN 'enable_nagios' THEN ac.value = 'true'
ELSE false
END
ORDER BY ac.value;