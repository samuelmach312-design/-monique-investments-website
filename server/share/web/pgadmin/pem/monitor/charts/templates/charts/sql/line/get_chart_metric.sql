SELECT
    array_agg(cm.tbl) as dep_probes
FROM
    pem.chart c
    LEFT OUTER JOIN pem.chart_metric cm ON (c.id = cm.cid)
WHERE c.id = (%s)::int4
