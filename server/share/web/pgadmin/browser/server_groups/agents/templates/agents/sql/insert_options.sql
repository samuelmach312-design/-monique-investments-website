INSERT INTO pem.agent_options (
    group_id,
    agent_id,
    pem_user{% if data.name is defined %},
    description{% endif %}
) VALUES (
    {% if data.gid is defined %}{{ data.gid|qtLiteral(conn) }}{% else %}0{% endif %}::int4,
    {{ agid|qtLiteral(conn) }}::int4,
    current_user{% if data.name is defined %},
    {{ data.name|qtLiteral(conn, True) }}::text{% endif %}
);
