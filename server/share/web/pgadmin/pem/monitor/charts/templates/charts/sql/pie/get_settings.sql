WITH chart_cfg AS (
SELECT
    c.id AS cid,
    c.type AS ctype,
    c.name,
    c.type AS type,
    EXTRACT (EPOCH FROM COALESCE(
        (SELECT (cfg.value || cfg.unit)::interval FROM pem.config cfg
            WHERE cfg.param = c.ref_timeout_param),
        ((c.reload / 1000) || 'seconds')::interval)
    ) AS reload,
    (SELECT b.colors FROM pem.bar_chart b WHERE b.cid = (%(cid)s)::integer) AS colors,
    c.labels AS labels,
    (select CASE WHEN lower(cfg.value) = 'png' THEN 2 ELSE 1 END FROM pem.config cfg
    WHERE cfg.param = 'download_chart_format') AS downloadformat
FROM
    pem.chart c
    LEFT JOIN (SELECT * FROM pem.metrices_chart WHERE cid = (%(cid)s)::integer) mc
        ON (mc.cid = c.id)
    LEFT JOIN (SELECT * FROM pem.data_chart WHERE cid = (%(cid)s)::integer) dc
        ON (dc.cid = c.id)
    LEFT JOIN (SELECT * FROM pem.capacity_report_chart WHERE cid = (%(cid)s)::integer) cr
        ON (cr.cid = c.id)
WHERE c.id = (%(cid)s)::integer
),
user_cfg AS (
    SELECT
        cfg.cid,
        cfg.level,
        cfg.did,
        cfg.reload,
        cfg.colors,
        CASE WHEN cfg.downloadformat = 2 THEN 2 ELSE 1 END AS downloadformat,
        100 AS lvl
    FROM
        pem.chart_config cfg
    WHERE
        cfg.cid = (%(cid)s)::integer AND
        cfg.did = -1 AND
        cfg.uid = (
            SELECT u.usesysid FROM pg_catalog.pg_user u
            WHERE u.usename = current_user
        )
    ORDER BY level DESC
    LIMIT 1
)
SELECT type, timeout,
  (unnest(colors)::pem.chart_metric_param).name AS clname,
  (unnest(colors)::pem.chart_metric_param).value as clval,
  default_colors, labels, downloadformat, name, did, lvl as level
FROM
(
    /*
    * Give priority to the user configuration over default configuration
    */
    SELECT
    c.type AS type,
    /* Default timeout is 300 seconds */
    COALESCE(x.reload, c.reload, 300) AS timeout,
    CASE
        WHEN x.colors IS NOT NULL THEN x.colors
        ELSE '{"(,)"}'::pem.chart_metric_param[]
    END AS colors,
    c.colors AS default_colors,
    CASE WHEN c.labels IS NOT NULL THEN c.labels ELSE '{}'::character varying[] END AS labels,
    COALESCE(x.downloadformat, c.downloadformat) as downloadformat,
    c.name,
    x.did, x.lvl
    FROM
    chart_cfg c LEFT OUTER JOIN user_cfg x ON (c.cid = x.cid)
) c
