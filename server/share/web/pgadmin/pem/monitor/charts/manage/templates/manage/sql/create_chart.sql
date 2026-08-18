{% if chart_imported %}
INSERT INTO pem.chart
    (cid, type, level, name, descp, owner, shared, ref_cnt, reload, reference_id)
VALUES
    ((%s)::int4, (%s)::text, (%s)::int4[], (%s)::text, (%s)::text,
    (SELECT oid FROM pg_roles WHERE rolname = current_user)::oid,
    (%s)::oid[], 0, (%s)::int4, (%s)::text)
{% else %}
INSERT INTO pem.chart
    (cid, type, level, name, descp, owner, shared, ref_cnt, reload)
VALUES
    ((%s)::int4, (%s)::text, (%s)::int4[], (%s)::text, (%s)::text,
    (SELECT oid FROM pg_roles WHERE rolname = current_user)::oid,
    (%s)::oid[], 0, (%s)::int4)
{% endif %}
RETURNING id;
