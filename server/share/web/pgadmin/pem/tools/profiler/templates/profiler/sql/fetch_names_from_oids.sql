{##### Databses #####}
{% if databases %}
SELECT array_to_string(ARRAY(
    SELECT datname
        FROM pg_database
    WHERE oid = ANY(%s)
), ', ') AS dbs
{% else %}
{##### Users #####}
SELECT array_to_string(ARRAY(
    SELECT rolname
        FROM pg_roles
    WHERE oid = ANY(%s)
), ', ') AS users
{% endif %}
