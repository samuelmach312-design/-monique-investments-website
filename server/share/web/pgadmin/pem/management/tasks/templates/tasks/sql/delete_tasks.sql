DELETE FROM pem.job WHERE jobid = ANY(%(jobid)s::int[]);
