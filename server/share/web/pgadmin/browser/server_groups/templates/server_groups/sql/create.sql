INSERT INTO
    pem.server_group (name, pem_user)
VALUES
    ({{name|qtLiteral}}, current_user)
RETURNING id;
