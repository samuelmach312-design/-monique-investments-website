INSERT INTO pem.bart_server_binding (
   bart_id,
   server_id,
   name,
   password,
   status,
   passwordless_ssh
) VALUES
(%s::integer, %s::integer, %s::text, %s::text, %s::text, %s)
