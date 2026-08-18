SELECT
    c.type AS type, c.name AS name, c.level AS levels,
    c.summary AS summary, c.fid AS fid, c.deleted AS deleted,
    cf.type AS func_type, cf.func AS func,
    lc.colors AS colors,
    cf.r_sys_obj AS require_show_system_objects,
    c.labels AS labels,
    cc.type AS ttype,
    c.params AS required_parameters,
    cf.dep_probes
FROM
    pem.chart c
    LEFT OUTER JOIN pem.chart_func cf ON (c.fid = cf.id)
    LEFT OUTER JOIN pem.line_chart lc ON (c.id = lc.cid)
    LEFT OUTER JOIN pem.capacity_report_chart cc ON (c.id = cc.cid)
WHERE c.id = {{ cid|qtLiteral(conn) }}
