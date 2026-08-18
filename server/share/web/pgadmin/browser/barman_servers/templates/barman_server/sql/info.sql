SELECT
    config.key AS label, config.value
FROM pemdata.barman_info b,
  jsonb_each_text(b.info::jsonb) AS config
WHERE b.tool_id = {{ bsid|qtLiteral(conn) }};
