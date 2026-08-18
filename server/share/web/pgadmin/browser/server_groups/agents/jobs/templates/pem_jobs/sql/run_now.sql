UPDATE pem.job
SET jobnextrun=now()::timestamptz
WHERE jobid={{ jid|qtLiteral(conn) }}::integer AND agent_id = {{ aid|qtLiteral(conn) }}::integer
