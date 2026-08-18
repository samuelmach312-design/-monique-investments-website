UPDATE pem.config AS c SET
    value = p.value
FROM (VALUES{% for c in configs %}

    ({{ c.param|qtLiteral(conn, True) }}, {% if c.value is none %}NULL{% else %}{{ c.value|qtLiteral(conn, True) }}{% endif %}){% if not loop.last %},{% endif %}{% endfor %}

) as p(param, value)
WHERE p.param = c.param;
