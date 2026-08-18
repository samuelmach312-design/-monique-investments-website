{% if create_job %}
INSERT INTO
    pem.job (jobname, jobdesc, agent_id, jobnextrun, dependent_on_job, execute_on_dep_job_status)
SELECT
    'Validate BART database server configuration',
    'This job validates the BART database server configurations.',
    {{ data.agent_id|qtLiteral }},
    now(),
    {% if data.passwordless_ssh or data.archive_command and data.archive_command|length > 0 or data.archive_path and data.archive_path|length > 0 %}
        ARRAY[{{ ssh_res|join(', ') }}]::integer[]{% else %}null{% endif %},
    {% if data.passwordless_ssh or data.archive_command and data.archive_command|length > 0 or data.archive_path and data.archive_path|length > 0 %}
        'i'{% else %}'s'{% endif %}
 RETURNING jobid;
{% endif %}


{% if create_job_step %}
INSERT INTO
    pem.jobstep (jstjobid, jstname, jstdesc, jstenabled, jstkind,
    jstonerror, jstcode, server_id, database_name)
SELECT {{ job_id|qtLiteral }}, 'Verify BART database server configuration',
'This job step will trigger the validation of the BART database server configuration', true, 'i',
'f', 'bart_server_config_validate {{ server_id|qtLiteral }}', {{ server_id|qtLiteral }}, null
{% endif %}
