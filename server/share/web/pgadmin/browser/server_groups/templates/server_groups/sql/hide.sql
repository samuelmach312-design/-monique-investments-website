{% if hide %}
SELECT pem.hide_server_group({{ gid|qtLiteral }}::integer, pem.current_user_id()::integer);
{% else %}
UPDATE pem.user_server_group SET hidden=false
WHERE uid = pem.current_user_id() AND id = {{ gid|qtLiteral }}::integer;
{% endif %}
