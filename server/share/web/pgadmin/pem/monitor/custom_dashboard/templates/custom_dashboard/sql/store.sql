INSERT INTO
    pem.dashboard(
        title, level, owner, descp, shared, font, font_size, is_ops_dashboard, show_title
        {% if is_import is defined and is_import %} ,reference_id {% endif %}
    )
VALUES
    (
        (%s)::text, (%s)::int4, (%s)::oid, (%s)::text, (%s)::oid[], (%s)::text, (%s)::int4, (%s)::boolean, (%s)::boolean
        {% if is_import is defined and is_import %} ,(%s)::text {% endif %}
    )
RETURNING id
