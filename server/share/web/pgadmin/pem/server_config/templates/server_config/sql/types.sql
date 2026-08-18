SELECT
    datatype, array_agg(param) AS params
FROM (
    SELECT
        CASE WHEN param like '%password%' THEN 'password'
        ELSE datatype END AS datatype, param
    FROM pem.config
    WHERE
        (role IS NULL OR pg_catalog.pg_has_role(role, 'member'::text)) {% if param %} AND param = {{ param | qtLiteral(conn) }}
        {% endif %}
) c GROUP BY datatype;
