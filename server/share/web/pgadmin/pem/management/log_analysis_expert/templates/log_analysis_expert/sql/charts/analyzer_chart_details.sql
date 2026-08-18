SELECT
    lc.id,
    assoc_chart_id,
    chart_headers,
    method,
    TYPE,
    lables,
    ltbc.exact_match,
    ltbc.tags,
    ltbc.target_name,
    is_pie
FROM
        pem.logexp_charts lc
LEFT OUTER JOIN
        pem.logexp_tagbasecharts ltbc ON lc.tag_chart_id = ltbc.id
WHERE lc.id IN %s;