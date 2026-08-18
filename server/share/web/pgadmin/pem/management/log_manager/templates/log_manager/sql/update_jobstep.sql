UPDATE  pem.jobstep
SET jstname = (%s)::text,
    jstdesc = (%s)::text,
    jstenabled = true,
    jstkind = 'i',
    jstonerror = 'f',
    jstcode = (%s)::text,
    server_id = (%s)::int4
WHERE jstjobid = (%s)::int;