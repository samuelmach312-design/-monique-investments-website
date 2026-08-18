SELECT
    c.type AS type, c.name AS name, c.level AS levels,
    c.summary AS summary, c.fid AS fid, c.deleted AS deleted,
    cf.type AS func_type, cf.func AS func,
    lc.colors AS colors,
    lc.xaxis::text AS xaxis,
    lc.yaxis::text AS yaxis,
    lc.yaxis2::text AS yaxis2,
    cf.r_sys_obj AS require_show_system_objects,
    c.labels AS labels,
    lc.type AS ttype,
    c.params AS required_parameters,
    cf.dep_probes
FROM
    pem.chart c
    LEFT OUTER JOIN pem.chart_func cf ON (c.fid = cf.id)
    LEFT OUTER JOIN pem.line_chart lc ON (c.id = lc.cid)
WHERE c.id = {{ cid|qtLiteral(conn) }}
