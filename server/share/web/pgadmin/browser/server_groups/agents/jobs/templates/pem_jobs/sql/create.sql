{% import 'macros/pem_jobstep.macros' as STEP %}
{% import 'macros/pem_jobschedule.macros' as SCHEDULE %}
DO $$
DECLARE
    jid integer;{% if 'jschedules' in data and data.jschedules|length > 0 %}

    scid integer;{% endif %}

BEGIN
-- Creating a new job
INSERT INTO pem.job(
    agent_id, jobname, jobdesc, jobenabled{% if schema_version >= 201907151 %}, notify, email_group_id{% endif %}

) VALUES (
{{ aid|qtLiteral(conn) }}::integer, {{ data.jobname|qtLiteral(conn, True) }}::text, {{ data.jobdesc|qtLiteral(conn, True) }}::text, {% if data.jobenabled %}true{% else %}false{% endif %}{% if schema_version >= 201907151 %}, {{ data.notify|qtLiteral(conn, True) }}::pem.notify_job_status, {% if 'email_group_id' in data and data.email_group_id is not none %}{{ data.email_group_id|qtLiteral(conn) }}::integer{% else %}null{% endif %}{% endif %}

) RETURNING jobid INTO jid;{% if 'jsteps' in data and data.jsteps|length > 0 %}


-- Steps
{% for step in data.jsteps %}

{{ STEP.INSERT(None, step) }}
{% endfor %}
{% endif %}{% if 'jschedules' in data and data.jschedules|length > 0 %}


-- Schedules
{% for schedule in data.jschedules %}{{ SCHEDULE.INSERT(None, schedule) }}{% endfor %}
{% endif %}

END
$$;{% if fetch_id %}

SELECT max(jobid) FROM pem.job WHERE xmin::text = (txid_current() % (2^32)::bigint)::text;{% endif %}
