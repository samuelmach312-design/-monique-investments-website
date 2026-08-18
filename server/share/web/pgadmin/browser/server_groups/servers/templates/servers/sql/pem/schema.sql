SELECT  recorded_time,
        server_id,
        database_name,
        schema_name
FROM pemdata.oc_schema
WHERE
  server_id=(%(server_id)s)::int4 AND
  database_name=(%(db_name)s)::text
{% if params.schema_name %}
  AND schema_name = (%(schema_name)s)::text
{% endif %};
