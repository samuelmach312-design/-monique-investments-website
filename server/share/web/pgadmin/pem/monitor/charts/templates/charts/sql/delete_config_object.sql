DELETE FROM
    pem.chart_config
WHERE
    cid = %(cid)s::int AND did = %(did)s::int AND
    uid = (SELECT usesysid FROM pg_catalog.pg_user WHERE
    usename = current_user) AND level = %(level)s::integer AND
    objid = %(objid)s::integer AND
    database IS NULL AND schema IS NULL AND tbl IS NULL
