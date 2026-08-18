{% if create_job %}
INSERT INTO
    pem.job (jobname, jobdesc, agent_id, jobnextrun)
SELECT
    'Show BART backups',
    'This job runs periodically to update BART backup details',
    {{ agent_id|qtLiteral }},
    null
 RETURNING jobid;
{% endif %}


{% if create_job_step %}
INSERT INTO
    pem.jobstep (jstjobid, jstname, jstdesc, jstenabled, jstkind,
    jstonerror, jstcode, server_id, database_name)
SELECT {{ job_id|qtLiteral }}, 'BART show backups',
'This job step runs periodically to insert backups details', true, 'i',
'f', 'bart_show_backups', null, null
{% endif %}

{% if create_job_schedule %}
INSERT INTO pem.schedule(
    jscjobid, jscname, jscdesc,
    jscminutes, jschours, jscmonths, jscweekdays,
    jscmonthdays
) VALUES(
    {{ job_id|qtLiteral }}, 'BART show backups', 'This job schedule runs periodically to insert backups details.',
    '{t,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f}',
    '{t,f,f,f,f,f,f,f,f,f,f,f,t,f,f,f,f,f,f,f,f,f,f,f}',
    '{t,t,t,t,t,t,t,t,t,t,t,t}', '{t,t,t,t,t,t,t}',
    '{t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t}');
{% endif %}
