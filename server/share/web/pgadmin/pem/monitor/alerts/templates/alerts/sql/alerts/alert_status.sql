SELECT
    EXTRACT(EPOCH FROM pas.current_state_since) * 1000 alert_since,
    pal.id alert_id,
    (
        CASE
        WHEN pas.current_state = 'HIGH' THEN 'High'
        WHEN pas.current_state = 'MEDIUM' THEN 'Medium'
        WHEN pas.current_state = 'LOW' THEN 'Low'
        END
    ) alert_state,
    pal.name AS alert_name,
    (
        CASE
        WHEN COALESCE(pas.display_value, '')::text != '' THEN pas.display_value
        ELSE pem.unit_converter(pas.current_value, pt.threshold_unit)
        END
    ) AS value,
    (CASE WHEN pt.object_type != 50
        THEN COALESCE(ps.description, pa.description, 'N/A'::text)
    ELSE 'N/A'::text END) AS object_description,
    ps.id AS server_id,
    pa.id AS agent_id,
    pal.database_name AS database,
    pal.schema_name AS schema,
    pal.package_name AS package,
    pal.object_name AS object,
    ppt.display_name AS alert_target_level,
    EXTRACT(EPOCH FROM pas.last_processed) * 1000 AS last_processed,
    pas.info,
    pas.info_cols,
    pas.info_vals
FROM
    (
      SELECT pal.* FROM pem.alert pal {% if since is not none %}
      LEFT JOIN pem.alert_history ah ON pal.id = ah.alert_id
      WHERE ah.generated > to_timestamp(({{ since }}::decimal / 1000))
      {% endif %}
    ) pal
    LEFT JOIN pem.alert_template pt ON (pt.id = pal.template_id)
    LEFT JOIN pem.probe_target_type ppt ON (pt.object_type = ppt.id)
    LEFT JOIN pem.alert_status pas ON (pal.id = pas.alert_id)
    LEFT JOIN pem.avail_servers ps ON (pal.server_id = ps.id)
    LEFT JOIN pem.avail_agents pa ON (pal.agent_id = pa.id)
WHERE
(NOT (pa.id IS NULL AND ps.id IS NULL) AND
    pal.enabled AND NOT pal.acknowledged AND
    COALESCE(pal.error_message, '') = '' AND
    ((ps.active AND NOT ps.alert_blackout) OR
    (pa.active AND NOT pa.alert_blackout)))
OR
(
    pal.agent_id = -1 AND
    pal.enabled=true AND pal.acknowledged=false AND
    COALESCE(pal.error_message, '') = ''
  )
ORDER BY 3 NULLS LAST, 1 DESC NULLS LAST;
