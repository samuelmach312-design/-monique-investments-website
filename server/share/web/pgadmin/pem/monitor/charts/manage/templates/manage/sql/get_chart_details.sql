SELECT
{% if fetch_probe %}
    c.reference_id,
{% else %}
    DISTINCT(c.id) AS id,
{% endif %}
    c.name AS chart_title,
    (SELECT name FROM pem.chart_category WHERE id=c.cid) AS chart_category,
    c.descp AS chart_description,
    c.level AS chart_level,
    c.type AS chart_type,
    c.shared AS shared,
    CASE WHEN array_length(c.shared, 1) > 0 THEN false
    ELSE true END AS shared_all,
    (c.reload / 60000) AS chart_refresh,
    (EXTRACT(EPOCH from d.time_span) / 60)::int4 AS line_span,
    d.max_points AS chart_line_points,
    (EXTRACT(EPOCH from d.ext_span) / 3600)::int4 AS espan,
    ext_id AS chart_line_ext_metric,
    ext_op AS chart_line_ext_opt,
    ext_val AS chart_line_ext_val
FROM
    pg_roles o,
    pem.chart c
LEFT JOIN pem.metrices_chart d ON (c.id = d.cid AND c.type = 'L')
WHERE c.id = (%(cid)s)::int4 AND o.rolname = current_user AND
    ((c.owner != 0 AND o.rolsuper IS true) OR (c.owner = o.oid))
     AND deleted = FALSE
ORDER BY
    c.name, c.level;
