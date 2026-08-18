##########################################################################
#
# Postgres Enterprise Manager
#
# Copyright (C) 2016 - 2025, EnterpriseDB Corporation. All rights reserved.
#
##########################################################################

"""Implements email for alert blackout"""

from __future__ import absolute_import
import json
from flask import render_template, request, current_app as app

from pgadmin.utils.ajax import internal_server_error, \
    make_json_response, precondition_required
from flask_security import login_required
from pgadmin.pem.utils import pem_connection
from flask_babel import gettext
from . import utils


@login_required
@utils.configRole.check_role(
    gettext("Logged-in user do not have permission to fetch servers.")
)
@pem_connection
def servers(pem_conn=None):
    """
    This function will return the list of servers for the specified
    server id.
    """
    res = utils.fetch_servers()
    return make_json_response(data=res)


@login_required
@utils.configRole.check_role(
    gettext("Logged-in user do not have permission to fetch servers.")
)
@pem_connection
def agents(pem_conn=None):
    res = utils.fetch_agents(pem_conn)
    return make_json_response(data=res)


@login_required
@utils.configRole.check_role(
    gettext("Logged-in user do not have permission to save alert blackouts.")
)
def save_blackouts():
    """Allow us to save the blackout jobs"""
    data = request.form if request.form else json.loads(
        request.data.decode('utf-8')
    )
    # Call delete_blackouts for the data with the 'deleted' key
    if ('deleted' in data.get('agents', {}) or
            'deleted' in data.get('servers',{})):
        status, res = delete_blackouts(data)
        if not status:
            return res
    if ('added' in data.get('agents', {}) or
            'added' in data.get('servers', {})):
        status, res = save_data(data)
        if not status:
            return res
    return make_json_response(data={'status': True})


@login_required
@utils.configRole.check_role(
    gettext("Logged-in user do not have permission to fetch alert blackouts.")
)
def get_blackouts():
    """Allow us to fetch the blackout jobs"""
    result = get_existing_blackouts()
    return make_json_response(
        data={
            'status': True,
            'result': result
        }
    )


@login_required
@utils.configRole.check_role(
    gettext("Logged-in user do not have permission to delete alert blackouts.")
)
@pem_connection
def delete_blackouts(data, pem_conn=None):
    """Allow us to delete the blackout jobs"""
    # Combine all deleted blackout jobs from agents and servers
    delete_data = (
        data.get('agents', {}).get('deleted', []) +
        data.get('servers', {}).get('deleted', []))

    # Extract the IDs from the delete_data
    ids = [item["id"] for item in delete_data if "id" in item]

    # Call delete_blackout_jobs with the extracted IDs
    status, res = delete_blackout_jobs({'ids': ids})
    if not status:
        return status, res

    return True, None


###########################################################################
# Utility functions starts from here we can use them in RestAPI in future #
###########################################################################
def verify_save_data(_agents, _servers):
    """verify the save request data"""
    if not isinstance(_agents, list) or not isinstance(_servers, list):
        return precondition_required(gettext(
            "Please provide the data in correct format"
        ))

    if len(_agents) == 0 and len(_servers) == 0:
        return precondition_required(gettext(
            "Please select at least one agent or server for the blackout"
        ))


@pem_connection
def save_data(data, pem_conn=None):
    """This is generic method to save the Blackout data"""
    selected_agents = data.get('agents', {}).get('added', [])
    selected_servers = data.get('servers', {}).get('added', [])
    verify_save_data(selected_agents, selected_servers)

    status, res = pem_conn.execute_void('BEGIN;')
    if not status:
        msg = gettext("Failed to start a transaction for alert blackout") + \
            "\n" + str(res)
        app.logger.error(msg)
        return False, internal_server_error(errormsg=msg)

    try:
        # Agents
        for agent in selected_agents:
            create_job(pem_conn, agent, is_agent=True)
        # Servers
        for server in selected_servers:
            create_job(pem_conn, server, is_agent=False)
    except RuntimeError as e:
        pem_conn.execute_void('ROLLBACK;')
        app.logger.error(e)
        return False, internal_server_error(errormsg=str(e))

    status, res = pem_conn.execute_void('COMMIT;')
    if not status:
        msg = gettext("Failed to commit a transaction for alert blackout") + \
            "\n" + str(res)
        app.logger.error(msg)
        return False, internal_server_error(errormsg=msg)
    return True, None


def create_job(pem_conn, data, is_agent=False):
    """Allow us to create the blackout jobs"""
    job_sql = 'alerts/sql/blackout/create_enable_disbale_blackout_job.sql'
    # Basic data validations
    required_fields = (
        'start_datetime', 'duration', 'blackout_object_ids'
    )
    for field in required_fields:
        if field not in data or data[field] is None:
            return precondition_required(gettext(
                "Required field '{0}' is missing".format(field) +
                "\nAffected row: {0}".format(data)
            ))
        elif data[field] is None or len(data[field]) == 0:
            return precondition_required(gettext(
                "Required field '{0}' can not empty".format(field) +
                "\nAffected row: {0}".format(data)
            ))

    #  Fetch the server-id, database name for the PEM database server
    # FIXME::
    # There are two sceanario to fix in long term
    # 1. PEM HA switch over happened after enable_blackout_job and before
    #    disable_blackout_job execution.
    # 2. There are no server with 'is_leader' flag set to true.
    sql = """
        SELECT
            server_id, database as database_name
        FROM pem.pem_host_and_server WHERE is_leader LIMIT 1
    """

    status, result = pem_conn.execute_dict(sql)

    if not status or len(result['rows']) == 0:
        raise RuntimeError(gettext(
            'Failed to fetch server-id, database name for the PEM '
            'database server') + ('\n' + str(result)) if not status else ''
        )

    data.update(result['rows'][0])
    # First create the enable job
    sql = render_template(
        job_sql,
        data=data,
        create_enable_job=True,
        is_agent=is_agent
    )
    status, enable_job_id = pem_conn.execute_scalar(sql)
    if not status:
        raise RuntimeError(gettext(
            'Failed to schedule enable blackout job'
        ) + "\n" + str(enable_job_id))
    sql = render_template(
        job_sql,
        data=data,
        create_enable_job_steps=True,
        is_agent=is_agent
    )
    params = [enable_job_id]
    status, job_step = pem_conn.execute_void(sql, params)
    if not status:
        raise RuntimeError(gettext(
            'Failed to schedule enable blackout job step'
        ) + "\n" + str(job_step))

    # Second create the disable job
    sql = render_template(
        job_sql,
        data=data,
        create_disable_job=True,
        is_agent=is_agent
    )
    status, disable_job_id = pem_conn.execute_scalar(sql)
    if not status:
        raise RuntimeError(gettext(
            'Failed to schedule disable blackout job'
        ) + "\n" + str(disable_job_id))
    sql = render_template(
        job_sql,
        data=data,
        create_disable_job_steps=True,
        is_agent=is_agent
    )
    params = [disable_job_id]
    status, job_step = pem_conn.execute_void(sql, params)
    if not status:
        raise RuntimeError(gettext(
            'Failed to schedule disable blackout job step'
        ) + "\n" + str(job_step))

    sql = render_template(
        'alerts/sql/blackout/save_blackout.sql',
        enable_job_id=enable_job_id,
        disable_job_id=disable_job_id,
        is_agent=is_agent
    )
    status, res = pem_conn.execute_void(sql, data)
    if not status:
        err = str(res)
        if "duplicate key value violates unique " \
           "constraint \"alert_blackout_config_unique\"" in err:
            err = "Duplicate alert blackout configuration"
        raise RuntimeError(gettext(
            'Failed to save the alert blackout configuration'
        ) + "\n" + err)


@pem_connection
def get_existing_blackouts(pem_conn=None):
    """"""
    result = {
        'agents': [],
        'servers': []
    }
    for obj in ('agents', 'servers'):
        sql = render_template(
            'alerts/sql/blackout/get_blackouts.sql',
            agent=True if obj == 'agents' else False,
        )
        status, res = pem_conn.execute_dict(sql)
        if not status:
            app.logger.error(res)
            return internal_server_error(errormsg=res)
        if len(res['rows']) > 0:
            result[obj] = res['rows']
    return result


@pem_connection
def delete_blackout_jobs(data, pem_conn=None):
    """Generic function to delete the blackouts"""
    if 'ids' not in data or not isinstance(data['ids'], list):
        return False, precondition_required(gettext(
            "Please provide the data in correct format"
        ))

    if len(data['ids']) == 0:
        return False, precondition_required(gettext(
            "Please provide at least one id to delete"
        ))

    pem_conn.execute_scalar("BEGIN;")
    try:
        for row_id in data['ids']:
            # Fetch the job IDs
            status, job_ids = pem_conn.execute_scalar(
                "SELECT array_agg(array[enable_jobid, disable_jobid]) "
                "FROM pem.alert_blackout_config "
                "WHERE id = (%s);", [int(row_id)]
            )
            if not status:
                raise RuntimeError(
                    gettext(
                        'Failed to fetch the '
                        'blackout jobid -') + "\n" + str(job_ids))
            # Delete the jobs
            status, res = pem_conn.execute_void(
                "DELETE FROM pem.job WHERE jobid = ANY(%s);",
                [job_ids]
            )
            if not status:
                raise RuntimeError(
                    gettext(
                        'Failed to delete the '
                        'blackout job -') + "\n" + str(job_ids))

        pem_conn.execute_scalar("COMMIT;")
        return True, {"status": "success"}

    except Exception as error:
        pem_conn.execute_scalar("ROLLBACK;")
        app.logger.error(error)
        return False, internal_server_error(errormsg=str(error))


# Add blackout URLs in the blueprint
def register_blackout_routes(blueprint):
    """
    Registers the URL with alert blueprint like
    :param blueprint:
    :return:
    """
    endpoint_url = '/blackout'
    url_list = [
        (endpoint_url, ["POST"], 'save_blackouts', save_blackouts),
        (endpoint_url, ["GET"], 'get_blackouts', get_blackouts),
        (endpoint_url, ["DELETE"], 'delete_blackouts', delete_blackouts),
        ('/servers', ["GET"], 'servers', servers),
        ('/agents', ["GET"], 'agents', agents),
    ]
    for url, method, endpoint, view in url_list:
        blueprint.add_url_rule(
            url,
            methods=method,
            endpoint=endpoint,
            view_func=view
        )
