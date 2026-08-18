{% if delete_probe %}
DELETE FROM
    pem.probe_schedule
WHERE probe_id = (
        SELECT
            id
        FROM
            pem.probe
        WHERE internal_name = 'auto_discover_servers'
    )
AND parameter_value_list[1] = {{agent_id|qtLiteral(conn)}}::text;
{% else %}
SELECT
    probe_id
FROM
    pem.probe_schedule
WHERE probe_id = (
        SELECT id FROM pem.probe WHERE internal_name = 'auto_discover_servers'
        )
AND parameter_value_list[1] = {{agent_id|qtLiteral(conn)}}::text AND current_backend_pid IS NULL;
{% endif %}
