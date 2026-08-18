INSERT INTO pem.alert_blackout_config(
	start_datetime, duration, blackout_object_ids, is_agent_object,
	enable_jobid, disable_jobid
)
VALUES (
    %(start_datetime)s::timestamp with time zone, %(duration)s::interval,
    %(blackout_object_ids)s::integer[], {% if is_agent -%} true {% else %} false {% endif %},
    {{ enable_job_id }}::integer, {{ disable_job_id }}::integer
);
