WITH chart_cfg AS (
SELECT
    c.id AS cid,
    c.type AS ctype,
    c.type AS type,
    c.name,
    EXTRACT (EPOCH FROM COALESCE(
        (SELECT (cfg.value || cfg.unit)::interval FROM pem.config cfg
            WHERE cfg.param = c.ref_timeout_param),
        ((c.reload / 1000) || 'seconds')::interval)
    ) AS reload
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
    cfg.reload
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
SELECT type, timeout, did, lvl as level
FROM
(
    /*
    * Give priority to the user configuration over default configuration
    */
    SELECT
    c.type AS type,
    /* Default timeout is 300 seconds */
    COALESCE(x.reload, c.reload, 300) AS timeout,
    x.did, x.lvl
    FROM
    chart_cfg c LEFT OUTER JOIN user_cfg x ON (c.cid = x.cid)
) c
