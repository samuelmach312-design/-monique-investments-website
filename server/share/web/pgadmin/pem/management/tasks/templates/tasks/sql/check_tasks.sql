SELECT array_agg(jobid) FROM pem.job WHERE jobid = ANY(%(jobid)s::int[]);
