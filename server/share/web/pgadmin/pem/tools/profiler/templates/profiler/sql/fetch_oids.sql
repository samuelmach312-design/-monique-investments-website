{% if databases %}
SELECT oid FROM pg_database WHERE NOT datistemplate
{% else %}
SELECT oid FROM pg_roles WHERE rolcanlogin
{% endif %}
