DELETE FROM pem.job
WHERE jobid = (%s)::int;