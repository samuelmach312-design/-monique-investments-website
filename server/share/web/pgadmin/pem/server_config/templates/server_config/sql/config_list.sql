SELECT
    param,
    CASE WHEN (datatype = 'bool' or datatype = 'boolean') AND (value = 't' or value = 'true') THEN 'TRUE'
    WHEN (datatype = 'bool' or datatype = 'boolean') AND (value = 'f' or value = 'false') THEN 'FALSE'
    ELSE value
    END AS value,
    unit, datatype, options
FROM
    pem.config
WHERE
    (role IS NULL OR pg_catalog.pg_has_role(role, 'member'::text)) {% if param %} AND param = {{ param|qtLiteral(conn) }}
{% endif %}

ORDER BY param;
