SELECT
    rolname as label, oid as value
FROM
    pg_roles
WHERE
    rolcanlogin IS false;
