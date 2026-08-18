UPDATE
    pem.chart
SET cid=(%s)::int4,
    name=(%s)::text, descp=(%s)::text,
    shared=(%s)::oid[], reload=(%s)::int4
WHERE id=(%s)::int4;
