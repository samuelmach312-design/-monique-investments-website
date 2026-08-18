INSERT INTO
    pem.server_group(name, parent_id)
VALUES (
    {{data.name|qtLiteral(conn, True)}}::text, {{data.parent_id}}
)
RETURNING id;

