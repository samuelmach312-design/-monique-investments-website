SELECT 
  COUNT(*) AS enabled_alerts,
  ROUND(SUM(60.0 / check_frequency)) AS alert_evaluations_per_hour
FROM pem.alert
WHERE enabled;