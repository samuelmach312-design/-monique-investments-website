SELECT  recorded_time,
        server_id,
        database_name,
        schema_name,
        view_name,
        view_type,
        ispopulated,
        tablespace_name,
        view_owner,
        definition
FROM pemdata.oc_views
WHERE
  server_id=(%(server_id)s)::int4 AND
  database_name=(%(db_name)s)::text AND
  schema_name=(%(schema_name)s)::text
{% if params.view_name %}
  AND view_name = (%(view_name)s)::text
{% endif %};
