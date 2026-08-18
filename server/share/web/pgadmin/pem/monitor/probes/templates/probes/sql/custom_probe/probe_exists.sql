SELECT count(id) FROM pem.probe
{% if internal_name is defined and internal_name %}
WHERE internal_name = {{ display_name|qtLiteral(conn, true) }}
{% else %}
WHERE display_name = {{ display_name|qtLiteral(conn, true) }}
{% endif %}
{% if deleted is defined and deleted %}
    AND deleted IN (true, false) {# We need to fetch both deleted and not deleted #}
{% else %}
    AND NOT deleted
{% endif %}
{% if id is defined %}
    AND id != {{ id }}::bigint
{% endif %};
