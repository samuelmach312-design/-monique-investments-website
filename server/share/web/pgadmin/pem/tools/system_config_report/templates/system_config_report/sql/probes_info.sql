SELECT ROUND(SUM(3600.0 / execution_frequency)) AS probes_per_hour
FROM pem.probe_target_view
WHERE enabled;
