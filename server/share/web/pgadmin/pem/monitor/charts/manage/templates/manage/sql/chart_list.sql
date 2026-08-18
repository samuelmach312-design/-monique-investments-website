SELECT
    DISTINCT(c.id) AS id,
    c.name AS name,
    (SELECT name FROM pem.chart_category WHERE id=c.cid) AS category,
    CASE WHEN c.level = ARRAY[50] THEN 'Global'
        WHEN c.level @> ARRAY[100] THEN 'Agent'
        WHEN c.level @> ARRAY[200] THEN 'Server'
        ELSE 'Database' END AS level,
    CASE WHEN c.type = 'L' THEN '<i class="fa fa-chart-line"></i>  Line Chart'
         WHEN c.type = 'TB' THEN '<i class="fa fa-table"></i>  Table'
         WHEN c.type = 'CL' THEN '<i class="fa fa-chart-line"></i>  Capacity Chart'
         WHEN c.type = 'CT' THEN '<i class="fa fa-table"></i>  Capacity Chart'
         ELSE '<i class="fa fa-chart-line"></i>  Line Chart' END AS type,
    c.shared AS shared
FROM
    pg_roles o,
    pem.chart c
WHERE o.rolname = current_user AND
    ((c.owner != 0 AND o.rolsuper IS true) OR (c.owner = o.oid)) AND deleted = FALSE
ORDER BY
    c.name, level;
