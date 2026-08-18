{% import 'macros/pem_jobstep.macros' as STEP %}
{% import 'macros/pem_jobschedule.macros' as SCHEDULE %}
{% if 'jobname' in data or 'jobdesc' in data or 'jobenabled' in data or 'notify' in data or 'email_group_id' in data %}
UPDATE pem.job
SET
{% if 'jobname' in data %}jobname={{ data.jobname|qtLiteral(conn, True) }}::text{%if 'jobdesc' in data or 'jobenabled' in data or 'notify' in data or 'email_group_id' in data %}, {% endif %}{% endif %}
{% if 'jobdesc' in data %}jobdesc={{ data.jobdesc|qtLiteral(conn, True) }}::text{%if 'jobenabled' in data or 'notify' in data or 'email_group_id' in data %}, {% endif %}{% endif %}
{% if 'jobenabled' in data %}jobenabled={% if data.jobenabled %}true{% else %}false{% endif %}{%if 'notify' in data or 'email_group_id' in data %}, {% endif %}{% endif %}
{% if 'notify' in data %}notify={{ data.notify|qtLiteral(conn, True) }}::pem.notify_job_status{%if 'email_group_id' in data %}, {% endif %}{% endif %}
{% if 'email_group_id' in data %}email_group_id={{ data.email_group_id|qtLiteral(conn) }}::integer{% endif %}

WHERE jobid = {{ jid|qtLiteral(conn) }}::integer AND agent_id = {{ aid|qtLiteral(conn) }}::integer;

{% endif %}{% if 'jsteps' in data %}

{% if 'deleted' in data.jsteps %}{% for step in data.jsteps.deleted %}{{ STEP.DELETE(jid, step.jstid) }}{% endfor %}{% endif %}
{% if 'changed' in data.jsteps %}{% for step in data.jsteps.changed %}{{ STEP.UPDATE(jid, step.jstid, step) }}{% endfor %}{% endif %}
{% if 'added' in data.jsteps %}{% for step in data.jsteps.added %}{{ STEP.INSERT(jid, step) }}{% endfor %}{% endif %}{% endif %}{% if 'jschedules' in data %}

{% if 'deleted' in data.jschedules %}{% for schedule in data.jschedules.deleted %}{{ SCHEDULE.DELETE(jid, schedule.jscid) }}{% endfor %}{% endif %}
{% if 'changed' in data.jschedules %}{% for schedule in data.jschedules.changed %}{{ SCHEDULE.UPDATE(jid, schedule.jscid, schedule) }}{% endfor %}{% endif %}
{% if 'added' in data.jschedules %}{% for schedule in data.jschedules.added %}{{ SCHEDULE.UPSERT(jid, schedule) }}{% endfor %}{% endif %}{% endif %}
