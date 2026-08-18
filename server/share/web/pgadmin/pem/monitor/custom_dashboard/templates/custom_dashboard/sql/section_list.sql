SELECT
    ds.id AS sec_id,
    ds.title AS sec_title,
    dc.cid AS chart_id,
    dc.index AS chart_idx,
    c.name AS chart_title,
    c.descp AS chart_descp,
    c.type AS chart_type,
    dc.size AS chart_size,
    dc.align AS chart_align,
    d.is_ops_dashboard AS chart_is_ops,
    dc.legend_type AS chart_legend,
    dc.show_chart_title AS chart_show_title,
    POSITION('chart_' IN c.reference_id) > 0 AS is_custom_chart,
    c.reference_id
FROM
    pem.dashboard_section ds
    LEFT JOIN pem.dashboard_chart dc ON (ds.id = dc.sid AND ds.did = dc.did)
    LEFT JOIN pem.chart c ON (dc.cid = c.id)
    LEFT JOIN pem.dashboard d ON (ds.did = d.id)
WHERE
    ds.did=(%s)::int4
ORDER BY
    ds.id ASC, dc.index ASC;
