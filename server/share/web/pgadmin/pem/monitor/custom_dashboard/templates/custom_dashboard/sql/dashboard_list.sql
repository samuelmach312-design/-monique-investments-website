SELECT
    DISTINCT(d.id) AS id,
    CASE WHEN d.level = 50 THEN 'Global'
        WHEN d.level = 100 THEN 'Agent'
        WHEN d.level = 200 THEN 'Server'
        ELSE 'Database' END AS level,
    d.title AS name,
    d.descp AS description,
    d.shared AS teams,
    d.font AS font,
    d.font_size AS font_size,
    d.is_ops_dashboard AS is_ops,
    d.show_title AS show_title
FROM
    pem.dashboard d, pg_roles r
WHERE
     r.rolname=current_user AND (d.owner = r.oid OR (d.owner != 0 AND r.rolsuper IS true))
ORDER BY
    title ASC;
