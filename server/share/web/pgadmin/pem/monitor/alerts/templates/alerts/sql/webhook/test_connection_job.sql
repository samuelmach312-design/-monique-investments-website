{% if create_test_endpoint %}
INSERT INTO
    pem.webhook_endpoints (name, url, enabled, method, payload_template, active)
SELECT
    {{ name|qtLiteral(conn, true) }}::text,
    {{ url|qtLiteral(conn, true) }}::text,
    false,
    {{ method|qtLiteral(conn, true) }}::text,
    {{ payload|qtLiteral(conn, true) }}::text,
    false
 RETURNING id;
{% endif %}
{% if create_job %}
INSERT INTO
    pem.job (jobname, jobdesc, agent_id, jobnextrun)
SELECT
    'Test webhook connection',
    'This job tests the connection for provided webhook parameters',
    {{ 1 }},
    now()
 RETURNING jobid;
{% endif %}

{% if create_job_step %}
INSERT INTO
    pem.jobstep (jstjobid, jstname, jstdesc, jstenabled, jstkind,
    jstonerror, jstcode, server_id, database_name)
SELECT {{ job_id|qtLiteral(conn, true) }}, 'Test webhook connection',
    'This job step tests the connection for provided webhook parameters',
    true, 'i', 'f',
    'test_webhook_connection {{ endpoint_id }} ' || {{ name|qtLiteral(conn, true) }}::text,
    null, null
{% endif %}