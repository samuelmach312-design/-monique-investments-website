INSERT INTO pem.agent_server_binding
    (agent_id, server_id, server,
     port, username, database, sslmode, password, exclude_databases, allow_takeover)
VALUES (
    {{data.agent_id}}::int4,
    {{data.server_id}}::int4,
    {{data.asb_host|qtLiteral(conn, True)}}::text,
    {{data.asb_port}}::int4,
    {{data.asb_username|qtLiteral(conn, True)}}::text,
    {{data.asb_database|qtLiteral(conn, True)}}::text,
    {{data.asb_sslmode|qtLiteral(conn, True)}}::text,
    {{data.asb_password|qtLiteral(conn, True)}}::text,
    {% if data.asb_exclude_databases %}
        {{data.asb_exclude_databases|qtLiteral(conn, True)}}::text[]
    {% else %}
        ARRAY[]::text[]
    {% endif %},
    {{data.agent_allowtakeover}}::boolean);
