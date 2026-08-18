INSERT INTO pem.agent_tool_binding
    (agent_id, tool_id, options)
VALUES (
    {{ agent_id}}::int4,
    {{ tool_id|qtLiteral(conn) }}::int4,
    {{ options|tojson|qtLiteral(conn, True) }}::jsonb
)
ON CONFLICT ON CONSTRAINT agent_tool_binding_pkey
DO
    UPDATE SET agent_id = {{ agent_id}}::int4,
        options = {{ options|tojson|qtLiteral(conn, True) }}::jsonb
    WHERE pem.agent_tool_binding.tool_id = {{ tool_id|qtLiteral(conn) }}::int4;
