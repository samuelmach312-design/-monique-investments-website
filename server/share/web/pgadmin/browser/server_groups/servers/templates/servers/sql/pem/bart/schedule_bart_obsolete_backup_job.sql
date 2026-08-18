{% if create_job %}
INSERT INTO
    pem.job (jobname, jobdesc, agent_id, jobenabled, issystemjob)
SELECT
    'Delete obsolete backups',
    'This job runs periodically to delete the BART obsolete backups.',
    {{ agent_id|qtLiteral }},
    false,
    true
 RETURNING jobid;
{% endif %}


{% if create_job_step %}
INSERT INTO
    pem.jobstep (jstjobid, jstname, jstdesc, jstenabled, jstkind,
    jstonerror, jstcode, server_id, database_name)
SELECT {{ job_id|qtLiteral }}, 'Delete obsolete backups',
'This job step runs periodically to delete the BART obsolete backups', false, 'i',
'f', 'bart_delete_backups', {{ server_id|qtLiteral }}, null;


INSERT INTO
    pem.jobstep (jstjobid, jstname, jstdesc, jstenabled, jstkind,
    jstonerror, jstcode, server_id, database_name)
SELECT {{ job_id|qtLiteral }}, 'Mark backups to obsolete',
'This job step runs periodically to mark the BART backups to obsolete', false, 'i',
'f', 'mark_bart_backups_obsolete', null, null;

INSERT INTO
    pem.jobstep (jstjobid, jstname, jstdesc, jstenabled, jstkind,
    jstonerror, jstcode, server_id, database_name)
SELECT {{ job_id|qtLiteral }}, 'Show backups',
'This job step runs periodically to insert backups details', false, 'i',
'f', 'bart_show_backups', null, null;
{% endif %}


{% if create_repeat_job %}
INSERT INTO pem.schedule(
    jscjobid, jscname, jscdesc, jscenabled,
    jscminutes, jschours, jscmonths, jscweekdays,
    jscmonthdays)
SELECT {{ job_id|qtLiteral }}, 'Delete obsolete backups',
    'This job schedule runs periodically to delete the BART obsolete backups.',
    false,
    '{t,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f}',
    '{f,f,t,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f}',
    '{t,t,t,t,t,t,t,t,t,t,t,t}',
    '{t,t,t,t,t,t,t}',
    '{t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t}'
RETURNING jscid;
{% endif %}
