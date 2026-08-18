SELECT
    p.id AS probe_id,
    p.display_name AS probe_name,
    p.is_system_probe,
    p.collection_method,
    p.applies_to_id::text AS target_level,
    p.extension_name,
    p.target_type_id AS target_type,
    p.enabled_by_default AS default_enabled,
    p.default_lifetime AS default_lifetime,
    p.default_execution_frequency AS default_interval,
    (p.default_execution_frequency / 60)::int4 AS default_interval_min,
    (p.default_execution_frequency % 60) AS default_interval_sec,
    p.enabled_by_default AS enabled,
    p.default_execution_frequency AS interval,
    (p.default_execution_frequency / 60)::int4 AS interval_min,
    (p.default_execution_frequency % 60) AS interval_sec,
    p.default_lifetime AS lifetime,
    p.force_enabled
FROM
    pem.probe p
WHERE
    NOT p.deleted
ORDER BY
    p.display_name

