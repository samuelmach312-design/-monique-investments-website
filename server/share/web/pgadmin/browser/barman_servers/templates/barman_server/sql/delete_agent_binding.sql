DELETE FROM pem.agent_tool_binding WHERE tool_id = {{ tool_id|qtLiteral(conn) }}::int;
