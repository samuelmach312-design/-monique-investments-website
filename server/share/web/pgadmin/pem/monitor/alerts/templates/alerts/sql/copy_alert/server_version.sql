SELECT
    server_version_id
FROM
    pemdata.server_info
WHERE
    server_id = (%s)::int