DELETE FROM pem.job WHERE jobid = {{ jid|qtLiteral(conn) }}::integer AND agent_id = {{ aid|qtLiteral(conn) }}::integer;
