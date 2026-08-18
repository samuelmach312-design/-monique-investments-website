UPDATE
    pem.jobstep
SET
    jstname=(%s)::text, jstdesc=(%s)::text, jstenabled=true, jstkind=(%s)::text,
    jstonerror='f', jstcode=(%s)::text, server_id=(%s)::int4
WHERE
    jstjobid=(%s)::int
