SELECT
    pg_has_role(r.rolname, 'pem_admin', 'member') AS is_admin,
    r.rolsuper AS is_super_admin, current_user
FROM pg_catalog.pg_roles r
WHERE r.rolname = current_user