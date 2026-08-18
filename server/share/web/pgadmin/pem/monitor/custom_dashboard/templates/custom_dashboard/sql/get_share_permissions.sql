SELECT
    d.id,
    d.shared AS shared,
    CASE WHEN array_length(d.shared, 1) > 0 THEN false
    ELSE true END AS shared_all
FROM
    pem.dashboard d
WHERE
     d.id = (%(id)s)::int4