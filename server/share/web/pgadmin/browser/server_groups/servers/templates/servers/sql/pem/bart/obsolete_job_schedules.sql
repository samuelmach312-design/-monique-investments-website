SELECT jobid, jobenabled, jscenabled, jscstart, jscend, jscminutes,
    jschours, jscweekdays, jscmonthdays, jscmonths
FROM pem.job job
    INNER JOIN pem.schedule schedule
        ON job.jobid = schedule.jscjobid
	LEFT JOIN pem.jobstep jstep
        ON job.jobid = jstep.jstjobid
WHERE jstep.server_id={{server_id}}::integer
AND job.jobname = 'Delete obsolete backups';

