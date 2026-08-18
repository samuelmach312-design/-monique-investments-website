{# Check whether the rule is applicable for remotely monitered server or not #}
SELECT
    id,
    run_on_remote_server
FROM
    pem.pe_rules
WHERE
    id IN %s
