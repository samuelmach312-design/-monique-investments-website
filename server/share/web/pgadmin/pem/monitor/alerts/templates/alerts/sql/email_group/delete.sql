{# Delete email group #}
{%if delete_email_group %}
DELETE FROM
    pem.email_group
WHERE id in ({{placeholders}})
{% else %}
{%if delete_from_email_group %}
DELETE FROM
    pem.email_group
WHERE (id != 1) AND (id NOT IN (SELECT DISTINCT(gid) FROM pem.email_group_option))
{% else %}
DELETE FROM
    pem.email_group_option
WHERE id = ANY(%(email_group_ids)s::int[])
{% endif %}
{% endif %}
