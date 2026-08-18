SELECT
    a.id,
    a.group_id::text as gid,
    a.description AS name,
    a.version AS version,
    ag.profile_id as profile_id,
    array_to_string(a.agent_capability_list, ', ') AS capability_list,
    a.active,
    a.team,
    r.rolname AS owner,
    a.heartbeat_tolerance,
    a.alert_blackout AS alert_blacked_out,
    os_host_name AS host_name,
    os_details AS operating_sys,
    os_domain_name AS domain_name,
    os_windows_domain AS window_domain,
    os_start_time AS boot_time,
    ag.tags as tags,
    (
        SELECT string_agg(description, ', ')
        FROM pem.server s, pem.agent_server_binding b
        WHERE s.id = b.server_id
        {% if agent_id is defined and agent_id %}
        AND b.agent_id =  {{agent_id}}::int4
        {% endif %}
    ) AS server_bind,
    CASE
    WHEN (
        pah.agent_id IS NOT NULL AND
        pah.last_heartbeat < now() AND
        pah.last_heartbeat > (now() - ((a.heartbeat_tolerance + 15) * '1 second'::interval))
    ) THEN 'UP'
    WHEN (
        pah.agent_id IS NOT NULL AND
        pah.last_heartbeat < (now() - ((a.heartbeat_tolerance + 15) * '1 second'::interval))
    ) THEN 'DOWN'
    ELSE 'UNKNOWN' END AS status{% if schema_version >= 201907151 %},
    oa.job_notification_override_default,
    oa.job_failure_notification,
    oa.job_status_change_notification,
    oa.job_notification_email_group_id::text AS job_notification_email_group_id,
    oa.ignore_mnt_points
{% endif %}

FROM
    pem.avail_agents a
    LEFT JOIN pg_catalog.pg_roles r
        ON (a.owner = r.oid)
    LEFT OUTER JOIN pemdata.os_info o
        ON (a.id = o.agent_id)
    LEFT OUTER JOIN pem.agent_heartbeat pah
        ON (a.id = pah.agent_id)
    LEFT OUTER JOIN pem.agent ag
        ON (a.id = ag.id)
{% if schema_version >= 201907151 %}
    LEFT OUTER JOIN pem.agent oa ON (a.id = oa.id){% endif %}

{% if gid is defined and gid or agent_id %}
WHERE
{% if gid is defined %}
  a.group_id = {{ gid|qtLiteral(conn) }}::int4
{% endif %}
{% if gid is defined and agent_id %}
  AND
{% endif %}
{% if agent_id is defined and agent_id %}
  a.id = {{ agent_id|qtLiteral(conn) }}::int4
{% endif %}
{% endif %}
  ORDER BY name
