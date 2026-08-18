SELECT
    a.id,
    a.version,
    a.description AS name,
    ag.tags as tags,
    ag.profile_id as profile_id,
    p.name as profile_name
FROM pem.avail_agents a
LEFT JOIN pem.agent ag ON (a.id = ag.id)
LEFT JOIN pem.profile p ON (ag.profile_id = p.id)
WHERE a.group_id = {{ gid|qtLiteral(conn) }}::int4
{% if agid %}
 AND a.id = {{ agid|qtLiteral(conn) }}::int4

{% endif %}
ORDER BY name;
