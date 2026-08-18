SELECT *
FROM pem.schedule_bart_init_jobs (
    {{ server_id|qtLiteral }}::integer,
    {{ agent_id }}::integer,
    {{ agent_binding_id }}::integer
)
