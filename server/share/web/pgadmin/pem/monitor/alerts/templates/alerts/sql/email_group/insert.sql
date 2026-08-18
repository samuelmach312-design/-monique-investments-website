{# Insert new email group #}
{% if insert_gid %}
INSERT INTO pem.email_group(name)
    VALUES((%s)::text) RETURNING id;
{% else %}
INSERT INTO pem.email_group_option
    (gid, grp_to, grp_cc, grp_bcc, grp_from, grp_reply_to, grp_subject_prefix, time_from, time_to)
VALUES (
    (%s)::integer , (%s)::text,  (%s)::text, (%s)::text,
    (%s)::text, (%s)::text, (%s)::text, (%s)::time with time zone,
    (%s)::time with time zone )
{% endif %}