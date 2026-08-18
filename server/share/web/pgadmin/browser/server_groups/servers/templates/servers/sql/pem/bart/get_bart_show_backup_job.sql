SELECT
    COUNT(*)
FROM pem.job
WHERE
    agent_id = {{ agent_id|qtLiteral }} AND
    jobname = 'Show BART backups'
