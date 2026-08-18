SELECT
    t.id, t.description, t.owner, t.team, t.tool_owner, t.gid,
    t.options->>'url' AS url,
    CASE WHEN t.options->>'probe_execution_frequency' IS NULL THEN 30 ELSE (t.options->>'probe_execution_frequency')::int END AS probe_execution_frequency,
    CASE WHEN t.options->>'heartbeat_interval' IS NULL THEN 10 ELSE (t.options->>'heartbeat_interval')::int END AS heartbeat_interval,
    at.agent_id AS agent_id
FROM
    pem.avail_tools t
    LEFT JOIN pem.agent_tool_binding at ON (t.id = at.tool_id)
WHERE
    t.name = 'barman'
{% if bsid %}
AND id = {{ bsid|qtLiteral(conn) }}
{% else %}{%if gid is defined and gid >= 0 %}

AND t.gid = {{ gid|qtLiteral(conn) }}::int4
{% endif %}
{% endif %}
ORDER BY t.description
