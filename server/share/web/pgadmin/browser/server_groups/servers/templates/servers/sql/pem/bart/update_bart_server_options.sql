DO $$
DECLARE
	cnt int;
BEGIN
	cnt := (SELECT COUNT(name) FROM pem.bart_server_config
            WHERE name='override_archive_command' AND server_id = {{ sid|qtLiteral }});
	IF(cnt = 0) THEN
		INSERT INTO pem.bart_server_config (
           server_id,
           name,
           value
        ) VALUES
        ( {{ sid|qtLiteral }}, 'override_archive_command', false );
	END IF;

    {% for config_name, config_value in data.items() %}
    UPDATE pem.bart_server_config
      SET value = {{ config_value|qtLiteral }}
    WHERE
      name = {{ config_name|qtLiteral }}
      AND server_id = {{ sid|qtLiteral }};
    {% endfor %}

END;
$$;
