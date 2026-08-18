SELECT *
FROM pem.schedule_bart_ssh_jobs (
    {{ server_id|qtLiteral }}::integer,
    {{ agent_id }}::integer,
    {{ agent_binding_id }}::integer,
    {{ restore_config_id }}::integer
)
