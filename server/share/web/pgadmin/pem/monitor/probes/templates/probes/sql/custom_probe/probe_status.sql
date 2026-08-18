{# Get probe status for the given probe id #}
SELECT
    p.is_system_probe,
    p.deleted
FROM
    pem.probe p
WHERE
    p.id = {{ probe_id }}::int4;
