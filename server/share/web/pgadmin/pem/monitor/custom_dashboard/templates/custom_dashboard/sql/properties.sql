SELECT
{% if is_export is true %}
    d.reference_id,
{% endif %}
{% if is_export is false %}
    d.id,
{% endif %}
    d.level,
    d.title AS name,
    d.descp AS descp,
    d.shared AS shared,
    CASE WHEN array_length(d.shared, 1) > 0 THEN false
    ELSE true END AS shared_all,
    d.font AS font,
    d.font_size AS font_size,
    d.is_ops_dashboard AS is_ops,
    d.show_title AS show_title
FROM
    pem.dashboard d, pg_roles r
WHERE
     d.id = (%s)::int4 AND
     r.rolname=current_user AND (d.owner = r.oid OR (d.owner != 0 AND r.rolsuper IS true))
ORDER BY
    title ASC;
