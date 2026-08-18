SELECT
o_idx, o_label,
'Date(' || (
    EXTRACT(
        EPOCH FROM o_aggtime
    ) * 1000
)::numeric(40, 0)::text || ')' o_aggtime,
o_aggval
FROM
pem.generate_metric_chart_data(
    (%s), (%s), (%s), (%s), (%s), (%s), (%s), (%s),
    (%s), (%s)::timestamptz, (%s)::timestamptz
)
ORDER BY o_idx, o_aggtime
