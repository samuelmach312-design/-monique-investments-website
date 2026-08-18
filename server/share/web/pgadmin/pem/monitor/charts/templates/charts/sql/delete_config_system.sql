DELETE FROM
    pem.chart_config
WHERE
    cid = %(cid)s::integer AND did = %(did)s::integer AND
    uid = (SELECT usesysid FROM pg_catalog.pg_user WHERE
    usename = current_user) AND level = %(level)s::integer AND
    objid IS NULL AND database IS NULL AND schema IS NULL AND tbl IS NULL
