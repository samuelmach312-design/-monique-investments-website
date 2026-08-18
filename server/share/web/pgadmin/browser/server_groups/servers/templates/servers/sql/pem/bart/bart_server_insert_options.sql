INSERT INTO pem.bart_server_config (
   server_id,
   name,
   value
) VALUES
{% for config_name, config_value in data.items() %}
{% if loop.index != 1 %}, {% endif %}
( {{ server_id|qtLiteral }}, {{ config_name|qtLiteral }}, {{ config_value|qtLiteral }} )
{% endfor %}
