SELECT
    j.jobid AS jobid, j.jobname as jobname, j.jobenabled as jobenabled,
    j.jobdesc AS jobdesc, j.jobcreated AS jobcreated,
    j.jobchanged AS jobchanged,
    (CASE sub.jlgstatus
      WHEN 's' THEN
         'success'
      ELSE
         'failure'
      END) AS jlgstatus,
    j.jobnextrun AS jobnextrun, j.joblastrun AS joblastrun,
    j.is_alert_job AS is_alert_job
{% if schema_version >= 201907151 %}, j.notify, j.email_group_id::text {% endif %}

FROM
    pem.job j
    LEFT JOIN (
        SELECT
            jstjobid, count(*) AS cnta
        FROM pem.jobstep
        WHERE jstkind not in ('s', 'b')
        GROUP BY jstjobid
    ) AS internal_job_steps ON (jstjobid = jobid)
    LEFT OUTER JOIN (
        SELECT DISTINCT ON (jlgjobid) jlgstatus, jlgjobid
        FROM pem.joblog
        ORDER BY jlgjobid, jlgid DESC
    ) sub ON sub.jlgjobid = j.jobid
WHERE
    agent_id = {{ aid|qtLiteral(conn) }}::integer{% if jid %}
    AND j.jobid = {{ jid|qtLiteral(conn) }}::integer
{% endif %} AND jstjobid IS NULL AND NOT issystemjob

ORDER BY j.jobname;
