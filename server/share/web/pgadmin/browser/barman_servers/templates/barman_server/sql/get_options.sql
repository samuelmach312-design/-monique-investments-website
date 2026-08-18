SELECT
    count(*)
FROM
    pem.tool_options
WHERE
    tool_id = {{bsid}}::int4 AND
    pem_user = current_user;
