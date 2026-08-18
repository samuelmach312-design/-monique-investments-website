SELECT
        d.id, d.title, d.is_ops_dashboard, d.level
    FROM
        pem.dashboard d
    LEFT JOIN
        pg_catalog.pg_roles r
    ON (d.owner = r.oid)
    WHERE d.owner IS NOT NULL
    AND (r.rolname = current_user OR pem.can_access(d.shared) 
        OR (array_length(d.shared, 1) IS NULL
        OR array_length(d.shared, 1) = 0))
    ORDER BY level