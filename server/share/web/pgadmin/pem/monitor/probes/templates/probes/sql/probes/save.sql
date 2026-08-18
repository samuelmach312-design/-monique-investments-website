{% if insert_probe %}
INSERT INTO pem.probe_config_{{ target_type }} {{ insert_column_list }}
VALUES {{ insert_value_list }}
{% endif %}
{% if update_probe %}
UPDATE pem.probe_config_{{ target_type }} {{ update_clause }} WHERE {{ where_clause }}
{% endif %}
{% if delete_probe %}
DELETE FROM pem.probe_config_{{ target_type }} WHERE {{ where_clause }}
{% endif %}
{% if check_probe %}
SELECT 1 FROM pem.probe_config_{{ target_type }} WHERE {{ where_clause }}
{% endif %}