INSERT INTO pem.tool_options
    (tool_id, description, gid, options)
VALUES (
    {{ tool_id|qtLiteral(conn) }}::int4,
    {{ description|qtLiteral(conn, True) }}::text,
    {{ gid|qtLiteral(conn) }}::int4,
    {{ options|tojson|qtLiteral(conn) }}::jsonb
)
ON CONFLICT ON CONSTRAINT tool_option_pkey
DO
    UPDATE SET description = {{ description|qtLiteral(conn, True) }}::text,
        gid = {{ gid|qtLiteral(conn) }}::int4,
        options={{ options|tojson|qtLiteral(conn) }}::jsonb
    WHERE pem.tool_options.tool_id = {{ tool_id|qtLiteral(conn) }}::int4 AND
        pem.tool_options.pem_user = CURRENT_USER;
