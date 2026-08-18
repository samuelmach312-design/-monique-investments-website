{# Get pem.alert table column type information #}
SELECT att.attname as name, format_type(ty.oid,NULL) AS datatype
FROM pg_attribute att
    JOIN pg_type ty ON ty.oid=atttypid
WHERE
    att.attrelid = (SELECT 'pem.alert'::regclass::oid)
    AND att.attisdropped IS FALSE
ORDER BY att.attnum
