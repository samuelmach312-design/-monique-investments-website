SELECT array_agg(jobid) FROM pem.job WHERE issystemjob = 'false' AND jobid = ANY(%(jobid)s::int[]);
