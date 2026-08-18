SELECT
    eg.id AS id,
    ego.id AS oid,
    ego.gid AS gid,
    eg.name AS name,
    ego.grp_to AS to_addr,
    ego.grp_cc AS cc_addr,
    ego.grp_bcc AS bcc_addr,
    ego.grp_from AS from_addr,
    ego.grp_reply_to AS reply_to_addr,
    ego.grp_subject_prefix AS subject_prefix,
    to_char(to_timestamp(EXTRACT(EPOCH FROM current_date) + EXTRACT(EPOCH FROM ego.time_from)), 'HH24:MI:SS') AS from_time,
    to_char(to_timestamp(EXTRACT(EPOCH FROM current_date) + EXTRACT(EPOCH FROM ego.time_to)), 'HH24:MI:SS') AS to_time
FROM
    pem.email_group AS eg
LEFT JOIN pem.email_group_option AS ego ON (ego.gid = eg.id)
{% if email_group_id is defined and email_group_id is not none %} WHERE ego.gid = {{ email_group_id }} {% endif %}
ORDER BY ego.gid;