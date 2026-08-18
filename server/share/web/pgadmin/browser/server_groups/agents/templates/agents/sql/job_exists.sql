{% if job_id is defined %}
SELECT COUNT(*) AS job_count
FROM pem.job a
WHERE a.jobid = %(job_id)s::integer
{% if agent_id is defined %} AND agent_id = {{ agent_id }} {% endif %}
{% endif %}