INSERT INTO
    pem.job (jobname, jobdesc, agent_id, jobnextrun)
VALUES
    ((%s)::text, (%s)::text, (%s)::int, (%s)::timestamptz)
RETURNING jobid