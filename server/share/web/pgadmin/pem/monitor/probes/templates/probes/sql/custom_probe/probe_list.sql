{# Get all the custom probes for the given target type and parameters #}
SELECT
{% if export_probes is not defined %}               {# We do not need id when exporting #}
    p.id AS probe_id,
{% endif %}
    p.display_name AS probe_name,
    p.internal_name AS internal_name,
{% if export_probes is not defined %}               {# We do not need when exporting #}
    p.is_system_probe,
{% endif %}
    p.collection_method,
    p.applies_to_id::text AS target_type,
{% if share_level is defined and share_level is true %}
    p.target_type_id::text AS target_level,
{% endif %}
    p.extension_name,
    p.enabled_by_default AS enabled,
    p.default_execution_frequency AS interval,
    p.default_lifetime AS lifetime,
    CASE WHEN NOT p.collection_method = 'i' THEN p.probe_code ELSE '[internal code]' END AS probe_code,
    p.force_enabled AS force_enabled,
    p.any_server_version,
    p.any_extension_version,
    p.discard_history,
    CASE WHEN p.platform = 'windows' then 'windows' ELSE '*nix' END AS platform,
    (SELECT json_agg(probe_column ORDER BY pc_id) FROM (
        SELECT pc.id AS pc_id, json_build_object(
        {% if export_probes is not defined %}       {# We do not need id when exporting #}
            'pc_id', pc.id,
        {% endif %}
            'pc_name', pc.display_name,
            'pc_internal_name', pc.internal_name,
            'pc_position', pc.display_position,
            'pc_col_type', pc.classification,
            'pc_data_type', pc.sql_data_type,
            'pc_unit', pc.unit_of_value,
            'pc_graphable', pc.is_graphable ,
            'pc_pit_default', pc.pit_by_default,
            'pc_calc_pit', pc.calculate_pit
            ) AS probe_column
        FROM pem.probe_column pc
        WHERE pc.probe_id = p.id
    ) probe_cols) AS probe_columns,
    (SELECT json_agg(sv.probe_code ORDER BY sv.server_version_id DESC) FROM (
        SELECT server_version_id, json_build_object(
            'server_version_id', psv.server_version_id::text,
            'extension_version', NULL,
            'server_probe_code', psv.probe_code
        ) AS probe_code
        FROM pem.probe_server_version psv
        WHERE psv.probe_id = p.id AND (
            (psv.server_version_id BETWEEN 10000 AND 19999 AND psv.server_version_id > 11000)
            OR
            (psv.server_version_id BETWEEN 20000 AND 29999 AND psv.server_version_id > 21000)
        )
        UNION ALL
        SELECT server_version_id, json_build_object(
            'server_version_id',  pev.server_version_id::text,
            'extension_version', pev.extension_version,
            'server_probe_code', pev.probe_code
        ) AS probe_code
        FROM pem.probe_extension_version pev
        WHERE pev.probe_id = p.id AND (
            (pev.server_version_id BETWEEN 10000 AND 19999 AND pev.server_version_id > 11100)
            OR
            (pev.server_version_id BETWEEN 20000 AND 29999 AND pev.server_version_id > 21000)
        )
    ) sv) AS alternate_code
FROM
    pem.probe p
WHERE
{% if deleted is defined and deleted %}
    p.deleted
{% else %}
    NOT p.deleted
{% endif %}
{% if probe_id is defined %}
    AND p.id = %(probe_id)s::int4
{% endif %}
{% if export_probes is defined %}
    {% if not show_system %}
    AND NOT p.is_system_probe
    {% endif %}
    {% if using_ids %}                  {# When we need to fetch using list of probe ids #}
    AND p.id IN ({{ placeholders }})
    {% else %}                          {# When we need to fetch using list of probe internal name #}
    AND p.internal_name IN ({{ placeholders }})
    {% endif %}
{% endif %}
{% if show_system_probe is defined and show_system_probe == 0 %}
    AND p.is_system_probe IS {{ 'true' if show_system_probe else 'false' }}
{% endif %}
ORDER BY p.id
