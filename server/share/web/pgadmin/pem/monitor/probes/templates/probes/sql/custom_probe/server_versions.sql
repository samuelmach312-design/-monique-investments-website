{% if to_array %}
SELECT ARRAY(
{% endif %}
SELECT {% if to_array %}
        id
       {% else %}
       id,
       display_name,
       (CASE WHEN (id > 10901 AND id < 20000) OR (id > 20901 AND id < 30000) THEN TRUE
       ELSE FALSE END) as allowed_to_add
       {% endif %} FROM pem.server_version
{% if to_array %}
WHERE (id > 10901 AND id < 20000) OR
    (id > 20901 AND id < 30000)
{% endif %}
ORDER BY id ASC
{% if to_array %}
)
{% endif%}
