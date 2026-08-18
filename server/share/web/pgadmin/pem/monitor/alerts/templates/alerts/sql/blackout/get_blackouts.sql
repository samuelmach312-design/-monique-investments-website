SELECT id, start_datetime, EXTRACT(epoch FROM duration)/3600 || ' hour' AS duration,
    blackout_object_ids
FROM pem.alert_blackout_config
WHERE is_agent_object = {% if agent %} true {% else %} false {% endif %};
