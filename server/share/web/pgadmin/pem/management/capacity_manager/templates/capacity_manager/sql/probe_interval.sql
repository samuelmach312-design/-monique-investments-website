SELECT
    p.execution_frequency
FROM
    pem.probe_target_view p, pem.probe_column c
WHERE
    p.probe_id = c.probe_id AND
    c.internal_name = %(internal_name)s::text AND
    c.id = %(cid)s::int