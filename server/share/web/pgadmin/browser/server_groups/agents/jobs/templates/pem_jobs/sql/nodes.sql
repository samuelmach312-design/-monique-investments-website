SELECT
    jobid, jobname, jobenabled
FROM
    pem.job
    LEFT JOIN (
        SELECT
            jstjobid, count(*) AS cnta
        FROM pem.jobstep
        WHERE jstkind not in ('s', 'b')
        GROUP BY jstjobid
    ) AS internal_job_steps ON (jstjobid = jobid)
WHERE agent_id = {{ aid|qtLiteral(conn) }}::integer
{% if jid %} AND jobid = {{ jid|qtLiteral(conn) }}::integer
{% endif %} AND jstjobid IS NULL AND NOT issystemjob AND NOT is_alert_job
ORDER BY jobname;
