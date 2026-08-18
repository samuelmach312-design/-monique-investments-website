SELECT
    cd.*,
    CASE WHEN server_probe IS NULL THEN NULL ELSE cr.type END AS cm_type,
    CASE WHEN server_probe IS NULL THEN NULL ELSE cr.historical END
        AS historical_days,
    CASE WHEN server_probe IS NULL THEN NULL ELSE cr.extrapolated END
        AS extrapolated_days,
    CASE WHEN server_probe IS NULL THEN NULL ELSE cr.midx END AS midx,
    CASE WHEN server_probe IS NULL THEN NULL ELSE cr.tval END AS tval,
    CASE WHEN server_probe IS NULL THEN NULL
         ELSE cr.toperator END AS toperator,
    server_probe,
    CASE WHEN server_probe IS NULL THEN NULL WHEN server_probe THEN
        s.description ELSE ag.description END AS object_description,
    CASE WHEN server_probe IS NULL THEN NULL WHEN server_probe THEN
        s.active ELSE ag.active END AS object_active
FROM
(SELECT
    c.id AS id,
    c.type AS type,
    CASE WHEN c.type IN ('L', 'CT', 'CL') THEN cm.mid ELSE 0 END AS mid,
    CASE WHEN c.type = 'TB' AND c.fid IS NULL THEN dc.orderby
         WHEN c.type IN ('L', 'CT', 'CL') AND c.fid IS NULL THEN cm.gorderby
         ELSE NULL END AS orderby,
    CASE WHEN c.type = 'TB' AND c.fid IS NULL THEN dc.orderdir
         WHEN c.type IN ('L', 'CT', 'CL') AND c.fid IS NULL THEN cm.gorderdir
         ELSE NULL END AS orderdir,
    CASE WHEN c.type = 'TB' AND c.fid IS NULL THEN dc.glimit
         WHEN c.type IN ('L', 'CT', 'CL') AND c.fid IS NULL
         THEN cm.glimit ELSE NULL END AS glimit,
    CASE WHEN c.type IN ('L', 'CT', 'CL') AND c.fid IS NULL THEN cm.tbl
         WHEN c.type = 'TB' AND c.fid IS NULL
         THEN dc.tbl ELSE NULL END AS tbl,
    CASE WHEN c.type IN ('L', 'CT', 'CL') AND c.fid IS NULL THEN cm.metrices
         WHEN c.type = 'TB' AND c.fid IS NULL THEN dc.metrices
         ELSE NULL END AS metrices,
    CASE WHEN c.type IN ('CT', 'CL', 'L') THEN cm.params
         ELSE NULL END AS params,
    CASE WHEN c.type IN ('CT', 'CL', 'L') THEN cm.param_names
         ELSE NULL END AS param_names,
    CASE WHEN c.type IN ('CT', 'CL', 'L') THEN cm.param_vals
         ELSE NULL END param_vals,
    CASE WHEN c.type IN ('CT', 'CL', 'L') AND cm.param_vals IS NOT NULL
         THEN '{server_id}' <@ cm.param_names
         ELSE NULL END AS server_probe,
    CASE WHEN c.type IN ('CT', 'CL', 'L') AND cm.param_vals IS NOT NULL
         THEN cm.param_vals[1] ELSE NULL END AS object,
    CASE WHEN c.type IN ('L', 'CT', 'CL') THEN cm.agg_func
         ELSE NULL END AS agg_funcs
FROM pem.chart c
LEFT JOIN pem.data_chart dc ON (c.id = dc.cid)
LEFT JOIN (
    SELECT
        m.cid, m.gorderby, m.gorderdir, m.glimit, m.tbl,
        m.metrices, m.mid, m.agg_func, m.params,
        ARRAY(SELECT (cmp.a).name
            FROM (SELECT unnest(m.params)::pem.chart_metric_param a)
            AS cmp)::text[] AS param_names,
        ARRAY(SELECT (cvp.b).value FROM
        (SELECT unnest(m.params)::pem.chart_metric_param b) AS cvp)::text[]
         AS param_vals
    FROM pem.chart_metric m
    WHERE m.cid = (%(cid)s)::int4
    ) cm ON (cm.cid = c.id)
WHERE c.id = (%(cid)s)::int4) cd
LEFT JOIN pem.server s ON (cd.object = s.id::text AND cd.server_probe)
LEFT JOIN pem.agent ag ON (cd.object = ag.id::text AND NOT cd.server_probe)
LEFT JOIN pem.capacity_report_chart cr ON (cd.id = cr.cid)
ORDER BY cd.tbl, cd.mid;
