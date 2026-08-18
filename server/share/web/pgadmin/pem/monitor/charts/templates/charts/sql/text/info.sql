SELECT
    c.type AS type, c.name AS name, c.level AS levels,
    c.summary AS summary, c.fid AS fid, c.deleted AS deleted,
    cf.type AS func_type, cf.func AS func,
    cf.r_sys_obj AS require_show_system_objects,
    c.labels AS labels,
    c.params AS required_parameters,
    cf.dep_probes
FROM
    pem.chart c
    LEFT OUTER JOIN pem.chart_func cf ON (c.fid = cf.id)
WHERE c.id = {{ cid|qtLiteral(conn) }}
