SELECT recorded_time, server_id, database_name, schema_name, package_name,
       function_name, function_type, return_type, arg_types, function_binary,
       extension_name
FROM pemdata.oc_function
WHERE
  server_id=(%(server_id)s)::int4 AND
  database_name=(%(db_name)s)::text AND
  schema_name=(%(schema_name)s)::text
{% if params.function_name %}
  AND function_name = (%(function_name)s)::text
{% endif %};
