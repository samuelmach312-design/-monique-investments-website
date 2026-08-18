{% if check_cat_id %}
SELECT
    id
FROM
    pem.chart_category
WHERE name = (%s)::text
{% else %}
SELECT
    name as label, name as value
FROM
    pem.chart_category
ORDER BY name;
{% endif %}
