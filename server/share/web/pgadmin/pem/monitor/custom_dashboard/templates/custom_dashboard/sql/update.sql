UPDATE pem.dashboard SET
    title = (%(title)s)::text,
    descp = (%(descp)s)::text,
    shared = (%(shared)s)::oid[],
    font = (%(font)s)::text,
    font_size = (%(font_size)s)::int4,
    is_ops_dashboard = (%(is_ops)s)::boolean,
    show_title = (%(show_title)s)::boolean
WHERE id = (%(id)s)::int4;