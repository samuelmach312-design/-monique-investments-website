##########################################################################
#
# Postgres Enterprise Manager
#
# Copyright (C) 2016 - 2025, EnterpriseDB Corporation. All rights reserved.
#
##########################################################################

import json
from flask import request
from flask_babel import gettext
from pgadmin.utils.ajax import internal_server_error, \
    make_json_response, make_response
from pgadmin.utils import PgAdminModule
from flask_security import login_required
from pgadmin.pem.utils import pem_connection
from pgadmin.pem.utils.role import PEMRole
from . import utils

MODULE_NAME = 'manage_profile'

manageProfileRole = PEMRole(
    'pem_manage_profile', gettext('Manage Profile'),
    gettext('Manage Profile Role'),
    gettext('Priviledge to manage profiles')
)


class ManageProfileModule(PgAdminModule):
    LABEL = gettext('Manage Profiles')

    def get_exposed_url_endpoints(self):
        return [
            'manage_profile.list',
            'manage_profile.list_server_profiles',
            'manage_profile.list_agent_profiles',
            'manage_profile.save',
            'manage_profile.publish_draft',
            'manage_profile.rollback_draft',
            'manage_profile.get_profile_for_agent',
            'manage_profile.get_profile_for_server'
        ]


blueprint = ManageProfileModule(
    MODULE_NAME, __name__,
    url_prefix='/pem/manage_profile'
)


@blueprint.route('/list', methods=['GET'], endpoint='list')
@login_required
@pem_connection
@manageProfileRole.check_role(
    gettext("Logged-in user do not have permission to access profiles.")
)
def list_profiles(pem_conn=None):
    """Lists all profiles."""
    status, res = utils.get_profiles(pem_conn)
    return make_json_response(
        data=res) if status else internal_server_error(errormsg=res)


@blueprint.route(
    '/list_server_profiles',
    methods=['GET'],
    endpoint='list_server_profiles'
)
@login_required
@pem_connection
@manageProfileRole.check_role(
    gettext("Logged-in user do not have permission to access profiles.")
)
def list_server_profiles(pem_conn=None):
    """Lists all PUBLISHED profiles by servers."""
    status, res = utils.get_profiles(pem_conn, target_kind='s')
    return make_json_response(
        data=res) if status else internal_server_error(errormsg=res)


@blueprint.route(
    '/list_agent_profiles',
    methods=['GET'],
    endpoint='list_agent_profiles'
)
@login_required
@pem_connection
@manageProfileRole.check_role(
    gettext("Logged-in user do not have permission to access profiles.")
)
def list_agent_profiles(pem_conn=None):
    """Lists all PUBLISHED profiles for agents."""
    status, res = utils.get_profiles(pem_conn, target_kind='a')
    return make_json_response(
        data=res) if status else internal_server_error(errormsg=res)


@blueprint.route('/save', methods=["PUT", "POST"], endpoint='save')
@login_required
@manageProfileRole.check_role(
    gettext("Logged-in user do not have permission to update profiles.")
)
@pem_connection
def save_profiles(pem_conn=None):
    """
    This function is used to store the profile configuration
    depending on target type.

    :param pem_conn: PEM Connection Object.
    """

    if request.data:
        change_profile_data = json.loads(request.data.decode())
    else:
        change_profile_data = request.args or request.form

    status, result = utils.save_profiles(change_profile_data, pem_conn)
    if not status:
        return internal_server_error(errormsg=result)

    return make_json_response(
        data=result
    )


@blueprint.route(
    '/draft/<int:draft_id>/publish',
    methods=['POST'],
    endpoint='publish_draft'
)
@login_required
@pem_connection
@manageProfileRole.check_role(
    gettext("Logged-in user do not have permission to manage profiles.")
)
def publish_draft(draft_id, pem_conn=None):
    """Publishes the given DRAFT profile ID."""
    status, res = utils.publish_draft(pem_conn, draft_id)
    return make_json_response(
        data=res) if status else internal_server_error(errormsg=res)


@blueprint.route(
    '/draft/<int:draft_id>/rollback',
    methods=['POST'],
    endpoint='rollback_draft'
)
@login_required
@pem_connection
@manageProfileRole.check_role(
    gettext("Logged-in user do not have permission to manage profiles.")
)
def rollback_draft(draft_id, pem_conn=None):
    """Rollbacks the given DRAFT profile ID."""
    status, res = utils.delete_draft(pem_conn, draft_id)

    return make_json_response(
        data=res) if status else internal_server_error(errormsg=res)


@blueprint.route(
    '/get_profile/<int:server_id>/server',
    methods=['GET'],
    endpoint='get_profile_for_server'
)
@login_required
@pem_connection
@manageProfileRole.check_role(
    gettext("Logged-in user do not have permission to access profiles.")
)
def get_profile_for_server(server_id, pem_conn=None):
    """Rollbacks the given DRAFT profile ID."""
    status, res = utils.get_profile_for_server(pem_conn, server_id)

    return make_json_response(
        data=res) if status else internal_server_error(errormsg=res)


@blueprint.route(
    '/get_profile/<int:agent_id>/agent',
    methods=['GET'],
    endpoint='get_profile_for_agent'
)
@login_required
@pem_connection
@manageProfileRole.check_role(
    gettext("Logged-in user do not have permission to access profiles.")
)
def get_profile_for_agent(agent_id, pem_conn=None):
    """Rollbacks the given DRAFT profile ID."""
    status, res = utils.get_profile_for_agent(pem_conn, agent_id)

    return make_json_response(
        data=res) if status else internal_server_error(errormsg=res)
