{# Get the number of probes for each target type #}
SELECT
    target_type_id,
    count(*) AS probe_count
FROM
    pem.probe
GROUP BY target_type_id
ORDER BY target_type_id;