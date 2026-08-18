{% if upsert_probe_config %}
{#
  This single command will:
  1. INSERT a new probe configuration if it doesn't exist.
  2. If it DOES exist (ON CONFLICT), it will UPDATE only the fields
     that are provided, leaving the others unchanged.
#}
INSERT INTO pem.profile_probe_configs (
    profile_id,
    probe_id,
    enabled,
    enabled_by_default,
    execution_frequency,
    lifetime
) VALUES (
    %(profile_id)s,
    %(probe_id)s,
    %(enabled)s,
    %(enabled_by_default)s,
    %(execution_frequency)s,
    %(lifetime)s
)
ON CONFLICT (profile_id, probe_id)
DO UPDATE SET
    -- COALESCE chooses the first non-null value.
    -- If a new value is provided (from EXCLUDED), it's used.
    -- If the new value is NULL (not provided), it keeps the old value.
    enabled = COALESCE(EXCLUDED.enabled, profile_probe_configs.enabled),
    enabled_by_default = COALESCE(EXCLUDED.enabled_by_default, profile_probe_configs.enabled_by_default),
    execution_frequency = COALESCE(EXCLUDED.execution_frequency, profile_probe_configs.execution_frequency),
    lifetime = COALESCE(EXCLUDED.lifetime, profile_probe_configs.lifetime);
{% endif %}
