WITH chart_cfg AS (
SELECT
    c.id AS cid,
    c.type AS ctype,
    c.name,
    /*
     * Only line charts and capacity report chart (line/table) can have
     * historical span and extrapolated span
     */
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
SELECT * FROM (
SELECT
    cfg.cid,
    cfg.level,
    cfg.did,
    CASE
    WHEN cfg.objid IS NULL THEN 50::integer
    WHEN (%(objid)s)::integer IS NOT NULL AND cfg.objid = (%(objid)s)::integer AND
        cfg.database IS NULL
        THEN 75::integer
    WHEN (%(objid)s)::integer IS NOT NULL AND cfg.objid = (%(objid)s)::integer AND
        (%(database)s)::text IS NOT NULL AND cfg.database = (%(database)s)::text AND
        cfg.schema IS NULL
        THEN 300::integer
    WHEN (%(objid)s)::integer IS NOT NULL AND cfg.objid = (%(objid)s)::integer AND
        (%(database)s)::text IS NOT NULL AND cfg.database = (%(database)s)::text AND
        (%(schema)s)::text IS NOT NULL AND cfg.schema = (%(schema)s)::text AND
        cfg.tbl IS NULL
        THEN 400::integer
    WHEN (%(objid)s)::integer IS NOT NULL AND cfg.objid = (%(objid)s)::integer AND
        (%(database)s)::text IS NOT NULL AND cfg.database = (%(database)s)::text AND
        (%(schema)s)::text IS NOT NULL AND cfg.schema = (%(schema)s)::text AND
        (%(tbl)s)::text IS NOT NULL AND cfg.tbl = (%(tbl)s)::text
        THEN 500::integer
    END AS lvl,
    cfg.reload, cfg.colors,
    CASE
        WHEN cfg.downloadformat = 2::integer THEN 2::integer
        ELSE 1::integer
    END AS downloadformat
FROM
    pem.chart_config cfg
WHERE
    /*
     * Find the chart configuration for the specified in pem.chart_config:
     * 1. Matches for the same combination on the same did
     * 2. On any dashboard (for same configuration)
     */
    cfg.cid = (%(cid)s)::integer AND
    ((cfg.did = -1 AND cfg.level <= (%(level)s)::integer) OR (cfg.did = (%(did)s)::integer AND
    (%(did)s)::integer IS NOT NULL)) AND
    cfg.uid = (
        SELECT u.usesysid FROM pg_catalog.pg_user u
            WHERE u.usename = current_user
    )
) a
WHERE lvl IS NOT NULL
/*
 * we only need the highest level possible chart configuration saved by the
 * user
 */
ORDER BY did DESC, lvl DESC, level DESC
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
