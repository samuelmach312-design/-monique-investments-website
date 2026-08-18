SELECT
    l.jsloutput AS job_result, j.jobnextrun AS next_run, j.joblastrun AS last_run
FROM
    pem.jobstep s
    LEFT JOIN pem.jobsteplog l ON s.jstid = l.jsljstid
    LEFT JOIN pem.job j ON j.jobid = s.jstjobid
WHERE jstjobid = {{ job_id }}::int4