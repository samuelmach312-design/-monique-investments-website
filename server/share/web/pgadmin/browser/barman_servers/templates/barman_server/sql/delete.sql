UPDATE
    pem.tool
SET
    active = FALSE
WHERE id = {{ bsid|qtLiteral(conn) }};

