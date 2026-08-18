{# Check whether the server is remotely monitered or not #}
{% if sid %}
SELECT
    is_remote_monitoring
FROM
    pem.server
WHERE
    id = {{sid}}
{% endif %}