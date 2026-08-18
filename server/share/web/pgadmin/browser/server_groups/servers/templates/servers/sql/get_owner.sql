SELECT
    count(*)
FROM
    pem.avail_servers
WHERE
    id= {{server_id}}::int4 AND
    server_owner= current_user;
