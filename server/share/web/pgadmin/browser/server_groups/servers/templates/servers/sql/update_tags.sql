UPDATE pem.server
SET tags = '{{ data.tags | tojson }}'::jsonb
WHERE
    id = {{server_id}}::int4
RETURNING id;
