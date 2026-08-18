SELECT count(*) > 0 AS is_row_present
    FROM pem.agent_options
WHERE
    pem_user = current_user
    AND agent_id = {{ agid|qtLiteral(conn) }}::int4;
