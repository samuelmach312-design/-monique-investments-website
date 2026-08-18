UPDATE pem.job
SET jobnextrun={{ scheduled_time|qtLiteral(conn) }}::timestamptz
WHERE jobid={{ jid|qtLiteral(conn) }}::integer AND agent_id = {{ aid|qtLiteral(conn) }}::integer
