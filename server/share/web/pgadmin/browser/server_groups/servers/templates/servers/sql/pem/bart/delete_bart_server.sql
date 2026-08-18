-- Remove db server jobs
SELECT pem.bart_server_postdelete({{ sid|qtLiteral }});
-- Remove the configs
DELETE FROM pem.bart_server_config
    WHERE server_id = {{ sid|qtLiteral }};
-- Remove the server entry
DELETE FROM pem.bart_server_binding
    WHERE server_id = {{ sid|qtLiteral }};
-- Remove delete obsolete backup system job
DELETE FROM pem.job WHERE jobid IN
(SELECT job.jobid FROM pem.job job
	LEFT JOIN pem.jobstep js ON job.jobid = js.jstjobid
	WHERE js.server_id = {{ sid|qtLiteral }}
	AND job.jobname = 'Delete obsolete backups'
	AND job.issystemjob = true)
