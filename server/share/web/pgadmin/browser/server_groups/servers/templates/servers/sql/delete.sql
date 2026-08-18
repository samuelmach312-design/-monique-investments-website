UPDATE
    pem.server
SET
    active = FALSE
WHERE id = {{sid}}::int4;
