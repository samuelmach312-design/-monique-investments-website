SELECT
    agent_id
FROM pem.bart
WHERE id = {{ bart_id|qtLiteral }};
