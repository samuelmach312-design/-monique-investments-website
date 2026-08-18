SELECT
    config.key AS label, config.value
FROM pemdata.barman_config b,
  json_each_text(b.config) AS config
WHERE b.tool_id = {{ bsid|qtLiteral(conn) }};
