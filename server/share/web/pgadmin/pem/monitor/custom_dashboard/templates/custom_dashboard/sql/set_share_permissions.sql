UPDATE pem.dashboard SET
    shared = (%(shared)s)::oid[]
WHERE id = (%(id)s)::int4;