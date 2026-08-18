SELECT  recorded_time,
        server_id,
        database_name,
        schema_name,
        table_name,
        has_primary_key
FROM pemdata.oc_table
WHERE
  server_id=(%(server_id)s)::int4 AND
  database_name=(%(db_name)s)::text AND
  schema_name=(%(schema_name)s)::text
{% if params.table_name %}
  AND table_name = (%(table_name)s)::text
{% endif %};
