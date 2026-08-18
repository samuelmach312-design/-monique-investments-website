{% if data %}
{% set flag = False %}
UPDATE pem.bart_server_binding SET

{% if data.bart_server is defined and data.bart_server != old_data.bart_server %}
bart_id = {{ data.bart_server|qtLiteral }}
{% set flag = True %}
{% endif %}

{% if data.bart_server_name is defined and data.bart_server_name != old_data.bart_server_name %}
{% if flag == True %}, {% endif %}
{% set flag = True %}
name = {{ data.bart_server_name|qtLiteral }}
{% endif %}

{% if data.bart_password is defined %}
{% if flag == True %}, {% endif %}
{% set flag = True %}
password = {{ data.bart_password|qtLiteral }}
{% endif %}

{% if data.passwordless_ssh is defined %}
{% if flag == True %}, {% endif %}
passwordless_ssh = {{ data.passwordless_ssh|qtLiteral }}
{% endif %}

WHERE server_id = {{ sid|qtLiteral }};
{% endif %}
