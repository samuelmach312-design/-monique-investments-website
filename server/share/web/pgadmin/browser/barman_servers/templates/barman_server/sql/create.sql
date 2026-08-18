INSERT INTO pem.tool (
   name,
   options,
   description,
   team
) VALUES
(
  {{ data.name|qtLiteral(conn, True) }}::text,
  {{ data.options|tojson | qtLiteral(conn, True)}}::jsonb,
  {{ data.description|qtLiteral(conn, True)}}::text,
  {{ data.team|qtLiteral(conn, True)}}::text
)
RETURNING id;
