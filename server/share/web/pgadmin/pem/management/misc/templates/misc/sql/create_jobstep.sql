INSERT INTO
    pem.jobstep (jstjobid, jstname, jstdesc, jstenabled, jstkind, jstonerror, jstcode, server_id)
VALUES
    ((%s)::int, (%s)::text, (%s)::text, true, 'i', 'f', (%s)::text, (%s)::int4);