SELECT
    p.internal_name
FROM
    pem.probe p,
    pem.probe_column c
WHERE
    p.id = c.probe_id AND
    c.internal_name = %(internal_name)s::text AND
    c.id = %(cid)s::int