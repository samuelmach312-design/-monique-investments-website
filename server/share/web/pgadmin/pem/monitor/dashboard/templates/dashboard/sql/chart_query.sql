{% if cid %}
WITH data_chart AS
(
    SELECT
        cid, tbl AS table_name, metrices
    FROM
        pem.data_chart
    WHERE
        cid = {{ cid }}
),
probe_columns AS
(
    SELECT
        internal_name AS internal_name, display_name AS display_name
    FROM
        pem.probe_column
    WHERE probe_id = (SELECT id FROM pem.probe, data_chart
          WHERE internal_name = table_name
                AND NOT is_graphable)
    UNION ALL
    SELECT
          internal_name AS internal_name, display_name AS display_name
    FROM pem.probe_column
    WHERE probe_id = (SELECT id FROM pem.probe, data_chart
          WHERE internal_name = table_name
                AND is_graphable AND pit_by_default AND NOT calculate_pit)
    UNION ALL
    SELECT
          internal_name AS internal_name, display_name||'+' AS display_name
    FROM pem.probe_column
    WHERE probe_id = (SELECT id FROM pem.probe, data_chart
          WHERE internal_name = table_name
                AND is_graphable AND NOT pit_by_default AND calculate_pit)
    UNION ALL
    SELECT
          internal_name||'_pit' AS internal_name, display_name AS display_name
    FROM pem.probe_column
    WHERE probe_id = (SELECT id FROM pem.probe, data_chart
          WHERE internal_name = table_name
                AND is_graphable AND NOT pit_by_default AND calculate_pit)
)
SELECT
    c.type AS type, c.name AS name, c.descp AS description,
    pg_catalog.array_to_string(c.level, ',') AS levels,
    c.summary AS summary, c.deleted AS deleted,
    COALESCE(cfg.value::bigint * 1000, c.reload) AS reload,
    COALESCE(r.rolname, '0') AS owner,
    COALESCE(lc.xaxis, '') AS xaxis, COALESCE(bc.yaxis, lc.yaxis, '') AS yaxis,
    COALESCE(lc.yaxis2, '') AS yaxis2, c.labels AS static_labels, (
    SELECT array_agg(display_name)
    FROM
        (SELECT generate_series(array_lower(metrices, 1), array_upper(metrices, 1)) as idx FROM data_chart) AS FOO,
        data_chart, probe_columns
    WHERE metrices[idx] = internal_name) AS display_labels
FROM
    pem.chart c
    LEFT OUTER JOIN pem.chart_func cf ON (c.fid = cf.id)
    LEFT OUTER JOIN pem.bar_chart  bc ON (c.id = bc.cid)
    LEFT OUTER JOIN pem.pie_chart  pc ON (c.id = pc.cid)
    LEFT OUTER JOIN pem.line_chart lc ON (c.id = lc.cid)
    LEFT OUTER JOIN pem.tbl_chart  tc ON (c.id = tc.cid)
    LEFT OUTER JOIN pg_catalog.pg_roles r ON (c.owner = r.oid)
    LEFT OUTER JOIN pem.config cfg ON (c.ref_timeout_param = cfg.param)
WHERE c.id = {{cid }}
{% endif %}
