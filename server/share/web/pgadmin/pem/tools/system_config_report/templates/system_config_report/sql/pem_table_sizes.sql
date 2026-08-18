SELECT
  table_schema AS "Schema Name",
  table_name AS "Table Name",
  pg_size_pretty(pg_total_relation_size(quote_ident(table_schema) || '.' || quote_ident(table_name))) AS "Total Table Size",
  pg_size_pretty(pg_relation_size(quote_ident(table_schema) || '.' || quote_ident(table_name))) AS "Table Size",
  pg_size_pretty(pg_indexes_size(quote_ident(table_schema) || '.' || quote_ident(table_name))) AS "Index Size"
FROM information_schema.tables
WHERE table_schema IN ('pemdata', 'pemhistory', 'pem') AND table_type != 'VIEW'
ORDER BY pg_total_relation_size(quote_ident(table_schema) || '.' || quote_ident(table_name)) DESC;
