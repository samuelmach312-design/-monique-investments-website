select
    count(*)
from
        pem.server_auth
WHERE
        server_id = {{server_id}}::int4 AND
        pem_user = current_user;
