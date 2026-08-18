SELECT jobid FROM pem.job WHERE jobname = (%s)::text AND agent_id = (%s)::int;
