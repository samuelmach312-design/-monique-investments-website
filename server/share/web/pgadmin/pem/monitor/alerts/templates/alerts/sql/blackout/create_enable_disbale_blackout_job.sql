{% if is_agent %}
  {% set obj_type = 'agents' -%}
{% else %}
  {% set obj_type = 'servers' -%}
{% endif %}

{### To Create main job ###}
{% if create_enable_job %}
INSERT INTO
    pem.job (jobname, jobdesc, agent_id, jobnextrun)
VALUES (
    'Schedule enable blackout for the {{ obj_type }}',
    'Scheduled enable blackout on selected objects',
    1, -- This job will always run by PEM Server's Agent
    {{ data.start_datetime|qtLiteral(conn, True) }}::timestamp with time zone
) RETURNING jobid;
{% endif %}

{### To Create job steps ###}
{% if create_enable_job_steps %}
INSERT INTO
    pem.jobstep (jstjobid, jstname, jstdesc, jstenabled, jstkind,
    jstonerror, jstcode, server_id, database_name)
VALUES (
    (%s), 'Enable the alert blackout', 'Start the blackout for selected {{ obj_type }}', true, 's',
    'f', $sql$SELECT pem.update_alert_blackout({{is_agent|qtLiteral(conn)}}::boolean, {{true|qtLiteral(conn)}}::boolean,
    ARRAY[{{ data.blackout_object_ids|join(',') }}]::integer[])$sql$, {{ data.server_id|qtLiteral(conn) }}::integer,
    {{ data.database_name|qtLiteral(conn, True) }}::text
)

{% endif %}

{### To Create main job ###}
{% if create_disable_job %}
INSERT INTO
    pem.job (jobname, jobdesc, agent_id, jobnextrun)
VALUES (
    'Schedule disable blackout for the {{ obj_type }}',
    'Scheduled disable blackout on selected objects',
    1, -- This job will always run by PEM Server's Agent
    {{ data.start_datetime|qtLiteral(conn, True) }}::timestamp with time zone + '{{ data.duration }}'::interval
) RETURNING jobid;
{% endif %}

{% if create_disable_job_steps %}
INSERT INTO
    pem.jobstep (jstjobid, jstname, jstdesc, jstenabled, jstkind,
    jstonerror, jstcode, server_id, database_name)
VALUES (
    (%s), 'Disable the alert blackout', 'End the blackout for selected {{ obj_type }}', true, 's',
    'f', $sql$SELECT pem.update_alert_blackout({{is_agent|qtLiteral(conn)}}::boolean, {{false|qtLiteral(conn)}}::boolean,
    ARRAY[{{ data.blackout_object_ids|join(',') }}]::integer[])$sql$, {{ data.server_id|qtLiteral(conn) }}::integer,
    {{ data.database_name|qtLiteral(conn, True) }}::text
)
{% endif %}
