{% if insert_alert %}
INSERT INTO pem.probe_config_{{ target_type }} {{ insert_column_list }}
VALUES {{ insert_value_list }}
{% endif %}
{% if update_alert %}
UPDATE pem.alert {{ update_clause }} WHERE {{ where_clause }}
{% endif %}
{% if delete_alert %}
DELETE FROM pem.alert WHERE {{ where_clause }}
{% endif %}
{% if check_alert %}
SELECT 1 FROM pem.alert WHERE {{ where_clause }}
{% endif %}
