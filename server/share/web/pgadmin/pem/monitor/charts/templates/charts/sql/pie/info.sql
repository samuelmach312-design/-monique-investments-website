SELECT
    c.type AS type, c.name AS name, c.level AS levels,
    c.summary AS summary, c.fid AS fid, c.deleted AS deleted,
    cf.type AS func_type, cf.func AS func,
    pc.colors AS colors,
    cf.r_sys_obj AS require_show_system_objects,
    c.labels AS labels,
    pc.is_vertical AS isvertical,
    c.params AS required_parameters,
    cf.dep_probes
FROM
    pem.chart c
    LEFT OUTER JOIN pem.chart_func cf ON (c.fid = cf.id)
    LEFT OUTER JOIN pem.pie_chart pc ON (c.id = pc.cid)
WHERE c.id = {{ cid|qtLiteral(conn) }}
