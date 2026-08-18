INSERT INTO pem.tool_options
    (tool_id, pem_user, description, options)
VALUES (
    {{ tool_id|qtLiteral(conn) }}::int4,
    {{ current_user|qtLiteral(conn, True) }}::text,
    {{ description|qtLiteral(conn, True) }}::text,
    {{ options|tojson|qtLiteral(conn) }}::jsonb)
ON CONFLICT ON CONSTRAINT tool_option_pkey
DO
    UPDATE SET description = {{ description|qtLiteral(conn, True) }}::text
    WHERE pem.tool_options.tool_id = {{ tool_id|qtLiteral(conn) }}::int4 AND
        pem.tool_options.pem_user = {{ current_user|qtLiteral(conn, True) }}::text;
