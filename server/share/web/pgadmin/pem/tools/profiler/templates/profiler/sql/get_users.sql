SELECT oid, rolname
    FROM pg_roles
WHERE rolcanlogin
ORDER BY rolname