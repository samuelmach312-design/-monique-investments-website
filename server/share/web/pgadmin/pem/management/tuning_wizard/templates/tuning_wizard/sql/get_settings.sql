{% if flag ==1 %}
SELECT
    setting, COALESCE(SUBSTRING(unit from '[0-9]+'), '1')::int4
FROM pemdata.settings WHERE server_id=%s::int4 AND name=%s::text;
{% else %}
SELECT setting FROM pemdata.settings WHERE server_id=%s::int4 AND name=%s::text
{% endif %}
