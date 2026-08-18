##########################################################################
#
# Postgres Enterprise Manager
#
# Copyright (C) 2016 - 2025, EnterpriseDB Corporation. All rights reserved.
#
##########################################################################

"""Implements Auto Discovery"""

import time
import json
from flask import render_template, request
from flask_babel import gettext
from flask_security import login_required
from pgadmin.utils.ajax import internal_server_error, bad_request, \
    gone, make_response as ajax_response, make_json_response
from pgadmin.utils import PgAdminModule
from pgadmin.utils.ajax import precondition_required
from pgadmin.pem.utils import pem_connection
from pgadmin.pem.utils.role import PEMRole

MODULE_NAME = 'auto_discovery'

autoDiscoveryRole = PEMRole(
    'pem_comp_auto_discovery', gettext('Server auto-discovery'),
    gettext('Auto-discovery'),
    gettext(
        'Priviledge to register the database server auto-discovered the '
        'PEMAgen.'
    )
)


class AutoDiscoveryModule(PgAdminModule):
    """
    class AutoDiscoveryModule(Object):

        It is a dialogue which inherits PgAdminModule
        class and define methods to load its own
        javascript file.
    """

    LABEL = gettext('Auto Discovery')

    def get_exposed_url_endpoints(self):
        """
        Returns:
            list: a list of url endpoints exposed to the client.
        """
        return [
            'auto_discovery.server_list', 'auto_discovery.server_details',
            'auto_discovery.server_status', 'auto_discovery.agent_status'
        ]


# Create blueprint for Auto Discovery class
blueprint = AutoDiscoveryModule(MODULE_NAME, __name__, static_url_path='',
                                url_prefix='/pem/auto_discovery')


@blueprint.route("/")
@login_required
def index():
    return bad_request(errormsg=gettext(
        "This URL cannot be called directly!")
    )


@blueprint.route('/server_list/<int:aid>',
                 methods=['GET'], endpoint='server_list')
@login_required
@autoDiscoveryRole.check_role(
    gettext("Logged-in user do not have permission to access server list.")
)
@pem_connection
def server_list(aid, pem_conn=None):
    """
    Return a list of auto discover servers.
    Args:
        aid: Agent ID
    """
    if aid is None or aid == '' or aid == 0:
        return internal_server_error(errormsg="Agent ID not found.")

    # Delete the jobs to re-run Server Auto Discovery probe.
    SQL = render_template('auto_discovery/sql/probes.sql',
                          delete_probe=True,
                          agent_id=aid)
    status, res = pem_conn.execute_void(SQL)

    if not status:
        return internal_server_error(errormsg=res)

    # Waiting for the Server Auto Discovery probe to finish. We will wait till
    # result will come or 2 min max
    start = time.time()
    elapsed = 0
    while elapsed < 120:
        # Wait before running the command once again
        time.sleep(2)
        SQL = render_template(
            'auto_discovery/sql/probes.sql',
            agent_id=aid
        )
        status, probe_id = pem_conn.execute_scalar(SQL)

        if not status:
            return internal_server_error(errormsg=probe_id)

        if probe_id == '' or probe_id is None or probe_id == 'NULL':
            end = time.time()
            elapsed = end - start
        else:
            break

    SQL = render_template('auto_discovery/sql/server_list.sql',
                          agent_id=aid)
    status, servers = pem_conn.execute_dict(SQL)

    if not status:
        return internal_server_error(errormsg=servers)

    return make_json_response(
        data=servers['rows'],
        status=200
    )


@blueprint.route('/server_details/<int:aid>', methods=['GET'],
                 endpoint='server_details')
@login_required
@autoDiscoveryRole.check_role(
    gettext("Logged-in user do not have permission to access server details.")
)
@pem_connection
def server_details(aid, pem_conn=None):
    if aid is None or aid == '' or aid == 0:
        return internal_server_error(errormsg="Agent ID not found.")

    SQL = render_template('auto_discovery/sql/server_details.sql',
                          agent_id=aid)
    status, servers = pem_conn.execute_dict(SQL)

    if not status:
        return internal_server_error(errormsg=servers)

    # Prepare host name array in select2 format.
    result = []
    if 'rows' in servers:
        result = servers['rows']

        for s in result:
            server_host = []
            for host in s['servers']:
                server_host.append({'label': host, 'value': host})

            # Add default host to the servers list
            if '127.0.0.1' not in s['servers']:
                server_host.append(
                    {'label': '127.0.0.1', 'value': '127.0.0.1'})
            s['servers'] = server_host

    return ajax_response(
        response=result,
        status=200
    )


@blueprint.route('/server_status', methods=['POST'], endpoint='server_status')
@login_required
@autoDiscoveryRole.check_role(
    gettext("Logged-in user do not have permission to access server status.")
)
@pem_connection
def server_status(pem_conn=None):
    """
    Return a list of auto discover servers.
    Args:
        server: Server Host List
        port: Server Port
    """

    if request.data:
        req = json.loads(request.data.decode())
    else:
        req = request.args or request.form

    for arg in ['host', 'port']:
        if arg not in req or req[arg] == '':
            return gone(
                errormsg=gettext(
                    "Could not find the required parameter (%s)." % arg
                )
            )

    SQL = render_template('auto_discovery/sql/server_status.sql',
                          server=req['host'],
                          port=req['port'])
    status, servers = pem_conn.execute_dict(SQL)

    if not status:
        return internal_server_error(errormsg=servers)

    if 'rows' in servers and len(servers['rows']) > 0:
        data = servers['rows'][0]
    else:
        data = None

    return make_json_response(
        data=data,
        status=200
    )


@blueprint.route('/agent_status/<int:aid>',
                 methods=['GET'], endpoint='agent_status')
@login_required
@autoDiscoveryRole.check_role(
    gettext("Logged-in user do not have permission to access server list.")
)
@pem_connection
def agent_status(aid, pem_conn=None):
    """
    Return agent status.
    Args:
        aid: Agent ID
    """
    if aid is None or aid == '' or aid == 0:
        return internal_server_error(errormsg="Agent ID not found.")

    sql = render_template(
        'auto_discovery/sql/agent_status.sql',
        agent_id=aid
    )
    status, agent_down = pem_conn.execute_scalar(sql)

    if not status:
        return internal_server_error(errormsg=agent_down)

    return make_json_response(
        status=200,
        data={'agent_status':False if int(agent_down) > 0 else True}
    )
