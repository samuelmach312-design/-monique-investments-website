SELECT row_to_json(d.*) as dashboard
FROM (
    SELECT d.*, a.sections
    FROM
    (
        SELECT s.did, array_agg(row_to_json(s)) sections
        FROM (
            SELECT s.*, c.charts
            FROM (
                SELECT sid, array_to_json(array_agg(row_to_json(a))) AS charts
                FROM (
                    SELECT
                        dc.sid, c.id, dc.index, dc.size as width, dc.align,
                        trim(c.type) as type,
                        dc.show_chart_title, dc.legend_type, c.level,
                        c.name as label, COALESCE(c.deleted, TRUE) AS deleted
                    FROM pem.dashboard_chart dc
                    LEFT JOIN pem.chart c ON (dc.cid = c.id)
                    WHERE did = {{ did|qtLiteral(conn) }}
                    ORDER BY dc.index
                ) a
                GROUP BY sid
            ) c
            LEFT JOIN pem.dashboard_section s ON (c.sid = s.id)
            WHERE did = {{ did|qtLiteral(conn) }}
        ) s
        GROUP BY s.did
    ) a
    LEFT JOIN pem.pem.dashboard d ON a.did = d.id
) d;
