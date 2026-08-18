{# CALL pem.pe_engine() to receive the postgres expert report table #}
SELECT
    server_id,
    rule_id,
    rule_name,
    server_host,
    server_description,
    server_port,
    expert_name,
    database_name,
    description,
    trigger,
    recommended_value,
    data_name,
    data_value,
    severity
FROM
    pem.pe_engine(
    %s::int[], %s::TEXT[]
    ) AS (
    server_id int,
    rule_id int,
    rule_name text,
    server_host text,
    server_description text,
    server_port int,
    expert_name text,
    database_name text,
    description text,
    trigger text,
    recommended_value text,
    data_name text[],
    data_value text[],
    severity int
   )