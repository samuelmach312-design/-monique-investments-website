SELECT id, description,
    '('||server::text||':'||port::text||')'::text as host_details
FROM pem.server WHERE id IN %s;