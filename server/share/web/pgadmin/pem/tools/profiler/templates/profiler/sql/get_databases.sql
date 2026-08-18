SELECT oid, datname
    FROM pg_database
WHERE datallowconn
{% if not show_system_objects %}
    AND oid > datlastsysoid
{% endif %}
ORDER BY 1;