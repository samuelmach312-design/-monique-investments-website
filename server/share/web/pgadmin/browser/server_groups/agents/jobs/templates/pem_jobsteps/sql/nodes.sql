SELECT
    jstid, jstjobid, jstname, jstenabled,
    jstkind = 's'::character(1) AS jstkind
FROM
    pem.jobstep
WHERE
{% if jstid %}
    jstid = {{ jstid|qtLiteral(conn) }}::integer AND
{% endif %}
    jstjobid = {{ jid|qtLiteral(conn) }}::integer
ORDER BY jstname;
