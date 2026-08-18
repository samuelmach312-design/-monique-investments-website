INSERT INTO
    pem.dashboard_chart(did, sid, cid, index, size, align ,legend_type, show_chart_title)
VALUES
    ((%s)::int4, (%s)::int4, (%s)::int4, (%s)::int4, (%s)::int4, (%s)::int4, (%s)::int4, (%s)::boolean);