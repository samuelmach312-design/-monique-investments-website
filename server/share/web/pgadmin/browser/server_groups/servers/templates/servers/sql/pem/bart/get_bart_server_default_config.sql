SELECT
    array_agg(name) AS config_names,
    array_agg(value) AS config_values
FROM pem.bart_server_default_config;
