INSERT INTO
    pem.chart_category (name, descp, owner)
VALUES (
        (%s)::text, (%s)::text,
        (SELECT oid FROM pg_roles WHERE rolname = current_user)::oid
       )
RETURNING id;
