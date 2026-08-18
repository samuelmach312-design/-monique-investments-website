SELECT  recorded_time,
        server_id,
        database_name,
        schema_name,
        sequence_name
FROM pemdata.oc_sequence
WHERE
  server_id=(%(server_id)s)::int4 AND
  database_name=(%(db_name)s)::text AND
  schema_name=(%(schema_name)s)::text
{% if params.sequence_name %}
  AND sequence_name = (%(sequence_name)s)::text
{% endif %};
