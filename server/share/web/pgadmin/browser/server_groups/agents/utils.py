##########################################################################
#
# Postgres Enterprise Manager
#
# Copyright (C) 2016 - 2025, EnterpriseDB Corporation. All rights reserved.
#
##########################################################################
from flask import render_template, current_app
from flask_babel import gettext
from pgadmin.utils.ajax import bad_request

from flask_security import current_user
from pgadmin.browser.server_groups.servers.pem.utils import update_tags


def get_agent_properties(pem_conn, agid):
    return pem_conn.execute_dict(render_template(
        '/agents/sql/properties.sql',
        agent_id=agid, schema_version=current_user.schema_version
    ))


def update_agent(pem_conn, agid, data):
    status, res = get_agent_properties(pem_conn, agid)
    if not status:
        return False, res

    if len(res['rows']) == 0:
        return True, None
    else:
        agent = res['rows'][0]

        # Handle heartbeat_tol_min and heartbeat_tol_sec separately
        # to adjust the total heartbeat_tolerance
        if 'heartbeat_tol_min' in data or 'heartbeat_tol_sec' in data:
            try:
                current_heartbeat_tolerance = agent.get(
                    'heartbeat_tolerance', 0
                )
                current_minutes = current_heartbeat_tolerance // 60
                current_seconds = current_heartbeat_tolerance % 60
                minutes = current_minutes
                seconds = current_seconds

                if 'heartbeat_tol_min' in data and data['heartbeat_tol_min']:
                    minutes = int(data['heartbeat_tol_min'])
                if 'heartbeat_tol_sec' in data and data['heartbeat_tol_sec']:
                    seconds = int(data['heartbeat_tol_sec'])

                new_heartbeat_tolerance = (minutes * 60) + seconds
                data['heartbeat_tolerance'] = new_heartbeat_tolerance

            except Exception as e:
                current_app.logger.exception(
                    "Invalid value for heartbeat_tolerance: {0}".format(str(e))
                )
                return bad_request(
                    errormsg=gettext("Invalid value for heartbeat_tolerance")
                )

        # Prepare the properties to update
        properties = {
            key: data[key] for key in data if key in (
                'team', 'alert_blackout', 'heartbeat_tolerance',
                'job_notification_override_default',
                'job_failure_notification',
                'job_status_change_notification',
                'job_notification_email_group_id', 'ignore_mnt_points', 'tags',
                'profile_id'
            )
        }

    if len(properties) > 0:
        status, res = update_admin_properties(
            pem_conn, agid, properties, agent)

        if not status:
            return status, res

    properties = {key: data[key] for key in data if key in ('gid', 'name')}

    if len(properties) > 0:
        status, res = update_user_properties(pem_conn, agid, properties)

        if not status:
            return status, res

    return get_agent_properties(pem_conn, agid)


def update_admin_properties(pem_conn, agid, data, agent):
    from pgadmin.pem.utils.role import adminRole

    if adminRole.has_role() is True:
        if 'job_status_change_notification' in data and \
                data['job_status_change_notification'] is True:
            data['job_failure_notification'] = True
        update_tags(data, agent)
        return pem_conn.execute_dict(
            render_template(
                "/agents/sql/update.sql",
                agent_id=agid, data=data,
                schema_version=current_user.schema_version
            )
        )

    return gettext(
        "User does not have enough permission to update these properties."
    ), None


def update_user_properties(pem_conn, agid, data):
    status, res = pem_conn.execute_scalar(
        render_template(
            "/agents/sql/get_agent_options.sql",
            agid=agid
        )
    )
    if not status:
        return False, res

    # Update if row is present
    if res:
        return pem_conn.execute_void(
            render_template(
                "/agents/sql/update_options.sql",
                agid=agid,
                data=data
            )
        )
    else:
        return pem_conn.execute_void(
            render_template(
                "/agents/sql/insert_options.sql",
                agid=agid,
                data=data
            )
        )
