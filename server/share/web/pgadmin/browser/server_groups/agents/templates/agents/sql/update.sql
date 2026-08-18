{% if data %}
{% set configs = [] %}{% if data.name is defined %}{%
    set tmp = configs.append(
        'description = ' + data.name|qtLiteral(conn, True) + '::text'
    )
%}{% endif %}{% if data.team is defined %}{%
    set tmp = configs.append(
        'team = ' + data.team|qtLiteral(conn, True) + '::text'
    )
%}{% endif %}{% if data.alert_blackout is defined %}{%
    set tmp = configs.append(
        'alert_blackout = ' + data.alert_blackout|string|qtLiteral(conn) + '::boolean'
    )
%}{% endif %}{% if data.heartbeat_tolerance is defined %}{%
    set tmp =  configs.append(
        'heartbeat_tolerance = ' + data.heartbeat_tolerance|qtLiteral(conn, True) + '::int4'
    )
%}{% endif %}{% if data.gid is defined %}{%
    set tmp =  configs.append(
        'group_id = ' + data.gid|qtLiteral(conn) + '::int4'
    )
%}{% endif%}{% if schema_version >= 201907151 %}{% if data.job_notification_override_default is defined %}{%
    set tmp = configs.append(
        'job_notification_override_default = ' +
        data.job_notification_override_default|qtLiteral(conn, True) + '::boolean'
    )
%}{% endif%}{% if data.job_failure_notification is defined %}{%
    set tmp = configs.append(
        'job_failure_notification = ' + data.job_failure_notification|qtLiteral(conn, True) + '::boolean'
    )
%}{% endif%}{% if data.job_status_change_notification is defined %}{%
    set tmp = configs.append(
        'job_status_change_notification = ' +
        data.job_status_change_notification|qtLiteral(conn, True) + '::boolean'
    )
%}{% endif%}{% if data.job_notification_email_group_id is defined %}{%
    set tmp = configs.append(
        'job_notification_email_group_id = ' +
        data.job_notification_email_group_id|qtLiteral(conn, True) + '::int4'
    )
%}{% endif%}{% if data.ignore_mnt_points is defined %}{%
    set tmp = configs.append(
        "ignore_mnt_points = ARRAY['" + data.ignore_mnt_points | join("', '") + "']::text[]"
    )
%}{% endif%}{% if data.tags is defined %}{%
    set tmp = configs.append(
        "tags = " + data.tags | tojson | qtLiteral(conn, True)
    )
%}{% endif%}{% if data.profile_id is defined %}{%
    set tmp = configs.append(
        "profile_id = " + (data.profile_id | qtLiteral(conn, True) + "::int4" if data.profile_id is not none else "NULL")
    )
%}{% endif%}{% endif%}
{% if configs|length > 0 %}
UPDATE pem.agent SET {{ configs|join(', ') }}
 WHERE id = {{agent_id|qtLiteral(conn)}}::int4 RETURNING id, description;
{% endif %}
{% endif %}
