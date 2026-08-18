SELECT
    jscid, jscjobid, jscname, jscenabled
FROM
    pem.schedule
WHERE
{% if jscid %}
    jscid = {{ jscid|qtLiteral(conn) }}::integer
{% else %}
    jscjobid = {{ jid|qtLiteral(conn) }}::integer
{% endif %}
ORDER BY jscname;
