SELECT
    count(pa.id)
FROM
    pem.agent pa LEFT OUTER JOIN pem.agent_heartbeat pah ON (pa.id = pah.agent_id)
WHERE
    pa.id = {{agent_id}}::int4 AND
    pa.active = TRUE AND
    NOT pa.alert_blackout AND
    CASE WHEN pah.agent_id IS NULL THEN FALSE ELSE
    pah.last_heartbeat < now() - (pa.heartbeat_tolerance+15)*'1 second'::interval
    END
