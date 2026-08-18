SELECT
    p.id, p.display_name AS label,
    p.internal_name AS probe_internal_name, p.target_type_id AS probe_target_type, p.applies_to_id AS applies_to_id,
    p.probe_key_list AS probe_key_list, p.discard_history AS probe_discard_history,
    ARRAY[
    -- Agent
    CASE WHEN p.target_type_id = 100 THEN COALESCE(array_length(p.probe_key_list, 1) > 0, false) ELSE false END,
    -- Server
    CASE
    WHEN p.target_type_id = 200 OR p.target_type_id = 100 THEN COALESCE(array_length(p.probe_key_list, 1) > 0, false)
    ELSE false
    END,
    -- Database
    CASE
    WHEN p.probe_key_list IS NULL OR array_length(p.probe_key_list, 1) = 0 THEN false
    WHEN p.target_type_id = 300 THEN
        CASE
        WHEN p.applies_to_id <= 300 THEN array_length(p.probe_key_list, 1) > 0
        WHEN p.applies_to_id > 300 THEN COALESCE(array_length((SELECT ARRAY(SELECT p.probe_key_list[i] FROM generate_series(array_lower(p.probe_key_list, 1), array_upper(p.probe_key_list, 1)) i WHERE p.probe_key_list[i] != 'database_name')), 1) > 0, false)
        END
    WHEN p.target_type_id = 200 THEN
        CASE
        WHEN p.applies_to_id = 300 THEN COALESCE(array_length((SELECT ARRAY(SELECT p.probe_key_list[i] FROM generate_series(array_lower(p.probe_key_list, 1), array_upper(p.probe_key_list, 1)) i WHERE p.probe_key_list[i] != 'database_name')), 1) > 0, false)
        ELSE array_length(p.probe_key_list, 1) > 0
        END
    WHEN p.target_type_id < 200 THEN array_length(p.probe_key_list, 1) > 0
    ELSE false
    END,
    -- Schema
    CASE
    WHEN p.probe_key_list IS NULL OR array_length(p.probe_key_list, 1) = 0 THEN false
    WHEN p.target_type_id = 400 THEN
        CASE
        WHEN p.applies_to_id = 400 THEN array_length(p.probe_key_list, 1) > 0
        WHEN p.applies_to_id > 400 THEN COALESCE(array_length((SELECT ARRAY(SELECT p.probe_key_list[i] FROM generate_series(array_lower(p.probe_key_list, 1), array_upper(p.probe_key_list, 1)) i WHERE p.probe_key_list[i] != 'schema_name')), 1) > 0, false)
        ELSE false
        END
    WHEN p.target_type_id = 300 THEN
        CASE
        WHEN p.applies_to_id = 300 THEN COALESCE(array_length((SELECT ARRAY(SELECT p.probe_key_list[i] FROM generate_series(array_lower(p.probe_key_list, 1), array_upper(p.probe_key_list, 1)) i WHERE p.probe_key_list[i] != 'database_name')), 1) > 0, false)
        WHEN p.applies_to_id > 300 THEN COALESCE(array_length((SELECT ARRAY(SELECT p.probe_key_list[i] FROM generate_series(array_lower(p.probe_key_list, 1), array_upper(p.probe_key_list, 1)) i WHERE p.probe_key_list[i] != 'schema_name')), 1) > 0, false)
        ELSE false
        END
    WHEN p.target_type_id = 200 THEN
        CASE
        WHEN p.applies_to_id = 300 THEN COALESCE(array_length((SELECT ARRAY(SELECT p.probe_key_list[i] FROM generate_series(array_lower(p.probe_key_list, 1), array_upper(p.probe_key_list, 1)) i WHERE p.probe_key_list[i] != 'database_name')), 1) > 0, false)
        ELSE array_length(p.probe_key_list, 1) > 0
        END
    WHEN p.target_type_id < 200 THEN array_length(p.probe_key_list, 1) > 0
    ELSE false
    END] AS grouped, pc.id AS metric_id, pc.internal_name AS metric_internal_name,
    pc.display_name AS metric_display_name, pc.calculate_pit AS calculate_pit,
    pc.discard_history AS discard_history, pc.pit_by_default AS pit_by_default, pc.is_graphable AS is_graphable
FROM
    pem.probe p
    LEFT JOIN pem.probe_column pc ON (pc.probe_id = p.id)
WHERE
    p.is_chartable AND NOT p.deleted
    {% if level == '300' %}
        AND (p.target_type_id <= {{level}} OR p.target_type_id = 1000)
    {% else %}
        AND p.target_type_id <= {{level}}
    {% endif %}
    {% if chart_type == 'L' %}
        AND p.discard_history = false
    {% endif %}
ORDER BY probe_target_type, label, pc.is_graphable ASC, metric_display_name;
