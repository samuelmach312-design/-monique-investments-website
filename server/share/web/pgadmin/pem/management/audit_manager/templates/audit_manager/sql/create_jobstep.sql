INSERT INTO pem.jobstep (jstjobid, jstname, jstdesc,
                         jstenabled, jstkind, jstonerror, jstcode, server_id)
VALUES ((%s)::int, (%s)::text, (%s)::text,
        true, (%s)::text, 'f', (%s)::text, (%s)::int4)
