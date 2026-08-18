{### To Create Job ###}
{% if create_job %}
INSERT INTO
    pem.job (jobname, jobdesc, agent_id, jobnextrun)
SELECT
    {{ data.name|qtLiteral(conn, True) }},
    'scheduled traces',
    a.agent_id,
    {{ data.start_time|qtLiteral(conn, True) }}::timestamp with time zone
FROM pem.agent_server_binding a
 WHERE a.server_id = {{ data.server_id|qtLiteral(conn, True) }} LIMIT 1
 RETURNING jobid;
{% endif %}

{### To Create Job step ###}
{% if create_job_step %}
INSERT INTO
    pem.jobstep (jstjobid, jstname, jstdesc, jstenabled, jstkind,
    jstonerror, jstcode, server_id, database_name)
SELECT (%s), 'trace-activation', 'Activate the schedule trace', true, 's',
'f', (%s), s.id, s.database FROM pem.server s
WHERE id = (%s)
{% endif %}

{### To Create Periodic trace job ###}
{% macro JOIN_BOOL_ARRAY(arr) %}
ARRAY[{{ arr|join(', ')}}]::boolean[]
{%- endmacro %}

{% if create_repeat_job %}
INSERT INTO pem.schedule(
    jscjobid, jscname, jscdesc,
    jscminutes, jschours, jscweekdays,
    jscmonthdays, jscmonths
) VALUES (
    {{ job_id }}::bigint,
    'Periodic job schedule for sql-profiler (Trace: {{ data.name }})',
    'This job schedule runs sql-profiler trace periodically.',
    -- Minutes
    {{ JOIN_BOOL_ARRAY(data.jscminutes) }},
    -- Hours
    {{ JOIN_BOOL_ARRAY(data.jschours) }},
    -- Week days
    {{ JOIN_BOOL_ARRAY(data.jscweekdays) }},
    -- Month days
    {{ JOIN_BOOL_ARRAY(data.jscmonthdays) }},
    -- Months
    {{ JOIN_BOOL_ARRAY(data.jscmonths) }}
)
{% endif %}
