SELECT
    internal_name, target_type_id, applies_to_id, deleted
FROM
    pem.probe
WHERE
    id = {{ probe_id }};
