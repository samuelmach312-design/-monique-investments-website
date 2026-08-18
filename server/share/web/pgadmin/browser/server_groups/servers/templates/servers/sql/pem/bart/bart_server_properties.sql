SELECT
    sbb.bart_id AS bart_server,
    sbb.name AS bart_server_name,
    b.name As bart_host_name,
    sbb.job_id,
    sbb.status,
    sbb.message,
    sbb.passwordless_ssh,
    array_agg(sbc.name) AS config_names,
    array_agg(sbc.value) AS config_values
FROM pem.bart_server_binding sbb
LEFT JOIN pem.bart_server_config sbc
    ON sbb.server_id = sbc.server_id
LEFT JOIN pem.bart b
    ON sbb.bart_id = b.id
{% if sid %}
    WHERE sbb.server_id = {{sid}}
{% endif %}
GROUP BY sbb.bart_id, sbb.name, sbb.job_id, sbb.status, sbb.message, sbb.passwordless_ssh, b.name
