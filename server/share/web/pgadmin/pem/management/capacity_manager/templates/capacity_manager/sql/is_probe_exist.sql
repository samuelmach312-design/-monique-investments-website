SELECT
    p.deleted
FROM
    pem.probe p
LEFT JOIN
    pem.probe_column c ON (p.id = c.probe_id)
WHERE
    c.internal_name = %(internal_name)s::text AND
    c.id = %(cid)s::int