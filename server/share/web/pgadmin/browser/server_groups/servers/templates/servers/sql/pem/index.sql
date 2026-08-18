SELECT  recorded_time,
        server_id,
        database_name,
        schema_name,
        index_name,
        table_name, ind_keys
FROM pemdata.oc_index
WHERE
  server_id=(%(server_id)s)::int4 AND
  database_name=(%(db_name)s)::text AND
  schema_name=(%(schema_name)s)::text
{% if params.index_name %}
  AND index_name = (%(index_name)s)::text
{% endif %};
