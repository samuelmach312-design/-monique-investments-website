UPDATE
    pem.schedule
SET
    (jscminutes, jschours) = ((%s)::boolean[], (%s)::boolean[])
WHERE jscjobid = (%s)::int;
