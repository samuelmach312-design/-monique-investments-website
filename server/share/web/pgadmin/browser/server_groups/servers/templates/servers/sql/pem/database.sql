SELECT  recorded_time,
        server_id,
        database_name,
        connections_allowed,
        encoding,
        system_database
FROM pemdata.oc_database
WHERE
  server_id=(%(server_id)s)::int4
{% if params.db_name %}
  AND database_name = (%(db_name)s)::text
{% endif %};
