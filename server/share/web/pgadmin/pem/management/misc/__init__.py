##########################################################################
#
# Postgres Enterprise Manager
#
# Copyright (C) 2016 - 2025, EnterpriseDB Corporation. All rights reserved.
#
##########################################################################

"""Miscellanous utilities"""

from flask import render_template, request, session
from flask_babel import gettext
from pgadmin.utils.ajax import internal_server_error, bad_request, \
    make_json_response
from pgadmin.pem.utils import pem_connection
from pgadmin.utils import PgAdminModule
from flask import url_for
from flask_security import login_required
import json
from pgadmin.pem.utils.role import PEMRole

_ = gettext
MODULE_NAME = 'misc_utilities'

serverServiceManager = PEMRole(
    'pem_server_service_manager', gettext(
        'Database server service management'),
    None,
    gettext(
        'Priviledge to reload/restart a monitored database server using the '
        'service-id. A base role for components like Log Manager, Audit Wizard'
        ', Tuning Wizard, etc., which requires restart/reload of the monitored'
        ' database server'
    )
)

efmRole = PEMRole(
    'pem_manage_efm', gettext('Failover manager utilities'),
    gettext('EFM utilities'),
    gettext('Priviledge to run the EFM functionalities.')
)

patroniRole = PEMRole(
    'pem_manage_patroni', gettext('Failover manager utilities'),
    gettext('Patroni utilities'),
    gettext('Priviledge to run the Patroni functionalities.')
)


class MiscUtilitiesModule(PgAdminModule):
    """
    class MiscModule(Object):

        UtilitiesModule inherits PgAdminModule
        class and define methods to load its own
        javascript file.
    """
    LABEL = gettext('Misc Utilities')

    def get_own_stylesheets(self):
        """
        Returns:
            list: the stylesheets used by this module.
        """
        stylesheets = [
            url_for('misc_utilities.static', filename='css/misc.css')
        ]
        return stylesheets

    def get_exposed_url_endpoints(self):
        """
        Returns:
            list: a list of url endpoints exposed to the client.
        """
        return [
            'misc_utilities.role_info', 'misc_utilities.agent_server_info',
            'misc_utilities.server_start', 'misc_utilities.server_stop',
            'misc_utilities.replace_cluster_master',
            'misc_utilities.switchover_efm_cluster',
            'misc_utilities.switchover_patroni_cluster',
            'misc_utilities.job_status'
        ]


# Create blueprint for MiscUtilitiesModule class
blueprint = MiscUtilitiesModule(
    MODULE_NAME, __name__, static_url_path='', url_prefix='/pem/misc')


@blueprint.route("/")
@login_required
def index():
    return bad_request(errormsg=gettext(
        "This URL cannot be called directly!")
    )


@blueprint.route("/role_info", methods=['get'], endpoint='role_info')
@pem_connection
@login_required
def role_info(pem_conn=None):
    """
    This function fetches the current user role information

    Returns: Current user role info

    """
    sql = render_template('misc/sql/role_info.sql')

    status, result = pem_conn.execute_dict(sql)
    if not status:
        return internal_server_error(errormsg=result)

    return make_json_response(data=result['rows'][0], status=200)


@blueprint.route('/server/start', methods=['post'], endpoint='server_start')
@login_required
@serverServiceManager.check_role(
    gettext("Logged-in user do not have permission to start database server.")
)
def start():
    """
    This function delegates the server start request
    to server_utils function

    Returns: Success
    """
    if request.data:
        req = json.loads(request.data.decode())
    else:
        req = request.args or request.form
    return server_utils('start', req)


@blueprint.route('/server/stop', methods=['post'], endpoint='server_stop')
@login_required
@serverServiceManager.check_role(
    gettext("Logged-in user do not have permission to stop database server.")
)
def stop():
    """
    This function delegates the server stop request
    to server_utils function

    Returns: Success
    """
    if request.data:
        req = json.loads(request.data.decode())
    else:
        req = request.args or request.form
    return server_utils('stop', req)


@pem_connection
@login_required
def server_utils(action, data, pem_conn=None):
    """
    This function controls start and stop of server
    Args:
        action: One of "start" or "stop".
        agent_id: The agent ID to execute the request
        service_id: The alpha-numeric ID of the service to stop/start
        server_id: The job to run on server
        pem_conn: pem_connection object

    Returns: Success
    """

    agent_id = data.get('agent_id', 0)
    service_id = data.get('service_id', None)
    server_id = data.get('server_id', None)

    # Get ready to rock
    pem_conn.execute_void("BEGIN;")

    # Create the activation job
    name = "Server " + action + " request"
    description = "Service ID: {0}, agent ID: {1}, user: {2}".format(
        service_id,
        agent_id,
        session['username']
    )

    time = "now()"

    params = [name, description, agent_id, time]
    sql = render_template('misc/sql/create_job.sql')
    status, jobid = pem_conn.execute_scalar(sql, params)

    if not status:
        pem_conn.execute_void('ROLLBACK')
        return internal_server_error(errormsg=str(jobid))

    code = "server_{0} {1}".format(action, service_id)

    if server_id != 0:
        params = [jobid, name, description, code, server_id]
        sql = render_template('misc/sql/create_jobstep.sql')

    status = pem_conn.execute_void(sql, params)

    if not status:
        pem_conn.execute_void('ROLLBACK')
        return internal_server_error(
            errormsg=gettext("Error while inserting into jobstep table.")
        )
    pem_conn.execute_void("COMMIT;")

    # All done. Return successfully.
    return make_json_response(data={'status': 1})


@blueprint.route('/agent_server_info/<int:sid>',
                 methods=['get'], endpoint='agent_server_info')
@pem_connection
@login_required
def agent_server_info(sid=0, pem_conn=None):
    """
    Return a result set of agents and server info (where bound)
    Args:
        sid: (optional) The ID of the server bound by the agent
        pem_conn: connection object

    Returns: Agent server data

    """

    sql = render_template('misc/sql/agent_server_info.sql', server_id=sid)

    # Execute the query.
    status, res = pem_conn.execute_dict(sql)

    if not status:
        return internal_server_error(errormsg=res)

    return make_json_response(
        data=res['rows'][0] if len(res['rows']) else []
    )


@blueprint.route('/replace_cluster_master',
                 methods=['post'], endpoint='replace_cluster_master')
@pem_connection
@login_required
@efmRole.check_role(
    gettext("Logged-in user do not have permission to replace cluster "
            "primary.")
)
def replace_cluster_master(pem_conn=None):
    """
    Schedule promote action.
    Args:
        agent_id - The agent ID to execute the request
        cluster_name - name of the cluster
        cluster_path - path of the cluster
        pem_conn: connection object

    Returns: Job ID

    """

    if request.data:
        req = json.loads(request.data.decode())
    else:
        req = request.args or request.form

    time = "now()"
    agent_id = int(req['agent_id'])
    cluster_name = req['efm_cluster_name']
    installation_path = req['efm_installation_path']

    # Begin Transaction
    pem_conn.execute_void("BEGIN;")

    # Create the activation job
    name = gettext("Replace Cluster Primary")
    description = gettext(
        "This job promotes the replica with the highest priority in EFM"
    )

    params = [name, description, agent_id, time]
    sql = render_template('misc/sql/create_job.sql')
    status, jobid = pem_conn.execute_scalar(sql, params)

    if not status:
        pem_conn.execute_void('ROLLBACK')
        return internal_server_error(errormsg=str(jobid))

    code = "replace_cluster_master " + cluster_name + " " + installation_path
    params = [jobid, name, description, code, None]
    sql = render_template('misc/sql/create_jobstep.sql')
    status = pem_conn.execute_void(sql, params)

    if not status:
        pem_conn.execute_void('ROLLBACK')
        return internal_server_error(
            errormsg=gettext("Error while inserting into jobstep table.")
        )

    # Commit Transaction
    pem_conn.execute_void("COMMIT;")

    return make_json_response(
        data={'jobid': jobid}
    )


@blueprint.route('/job_status/<int:job_id>',
                 methods=['get'], endpoint='job_status')
@pem_connection
@login_required
@efmRole.check_role(
    gettext(
        "Logged-in user do not have permission to schedule replace cluster "
        "primary."
    )
)
def job_result(job_id, pem_conn=None):
    """
    Return output of job-step for the given job.
    Args:
        job_id: Job ID
        pem_conn:

    Returns: Job result

    """
    sql = render_template('misc/sql/job_status.sql', job_id=job_id)

    # Execute the query.
    status, res = pem_conn.execute_dict(sql)

    if not status:
        return internal_server_error(errormsg=res)

    data = res['rows'][0]
    return make_json_response(
        data=data
    )


@blueprint.route('/switchover_efm_cluster',
                 methods=['post'], endpoint='switchover_efm_cluster')
@pem_connection
@login_required
@efmRole.check_role(
    gettext("Logged-in user do not have permission to switchover efm cluster.")
)
def switchover_efm_cluster(pem_conn=None):
    """
    Schedule switchover action.
    Args:
        agent_id - The agent ID to execute the request
        cluster_name - name of the cluster
        cluster_path - path of the cluster
        pem_conn: connection object

    Returns: Job ID

    """

    if request.data:
        req = json.loads(request.data.decode())
    else:
        req = request.args or request.form

    time = "now()"
    agent_id = int(req['agent_id'])
    cluster_name = req['efm_cluster_name']
    installation_path = req['efm_installation_path']

    # Begin Transaction
    pem_conn.execute_void("BEGIN;")

    # Create the activation job
    name = gettext("Switchover EFM Cluster")
    description = gettext(
        "This job performs switchover of EFM cluster"
    )

    params = [name, description, agent_id, time]
    sql = render_template('misc/sql/create_job.sql')
    status, jobid = pem_conn.execute_scalar(sql, params)

    if not status:
        pem_conn.execute_void('ROLLBACK')
        return internal_server_error(errormsg=str(jobid))

    code = "switchover_efm_cluster " + cluster_name + " " + installation_path
    params = [jobid, name, description, code, None]
    sql = render_template('misc/sql/create_jobstep.sql')
    status = pem_conn.execute_void(sql, params)

    if not status:
        pem_conn.execute_void('ROLLBACK')
        return internal_server_error(
            errormsg=gettext("Error while inserting into jobstep table.")
        )

    # Commit Transaction
    pem_conn.execute_void("COMMIT;")

    return make_json_response(
        data={'jobid': jobid}
    )


@blueprint.route('/switchover_patroni_cluster',
                 methods=['post'], endpoint='switchover_patroni_cluster')
@pem_connection
@login_required
@patroniRole.check_role(
    gettext(
        "Logged-in user do not have permission to switchover patroni cluster."
    )
)
def switchover_patroni_cluster(pem_conn=None):
    """
    Schedule switchover action.
    Args:
        agent_id - The agent ID to execute the request
        patroni_config_path - path of the patroni config file
        patroni_cluster_leader - name of the current leader
        patroni_cluster_candidate - name of the candidate
        pem_conn: connection object

    Returns: Job ID

    """

    if request.data:
        req = json.loads(request.data.decode())
    else:
        req = request.args or request.form

    time = "now()"
    agent_id = int(req['agent_id'])
    config_path = req['patroni_config_path']
    leader = req['patroni_cluster_leader']
    candidate = req['patroni_cluster_candidate']

    # Begin Transaction
    pem_conn.execute_void("BEGIN;")

    # Create the activation job
    name = gettext("Switchover Patroni Cluster")
    description = gettext(
        "This job performs switchover of patroni cluster"
    )

    params = [name, description, agent_id, time]
    sql = render_template('misc/sql/create_job.sql')
    status, jobid = pem_conn.execute_scalar(sql, params)

    if not status:
        pem_conn.execute_void('ROLLBACK')
        return internal_server_error(errormsg=str(jobid))

    code = "switchover_patroni_cluster " + \
        config_path + " " + leader + " " + candidate
    params = [jobid, name, description, code, None]
    sql = render_template('misc/sql/create_jobstep.sql')
    status = pem_conn.execute_void(sql, params)

    if not status:
        pem_conn.execute_void('ROLLBACK')
        return internal_server_error(
            errormsg=gettext("Error while inserting into jobstep table.")
        )

    # Commit Transaction
    pem_conn.execute_void("COMMIT;")

    return make_json_response(
        data={'jobid': jobid}
    )
