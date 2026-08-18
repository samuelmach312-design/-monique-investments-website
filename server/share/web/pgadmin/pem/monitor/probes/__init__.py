##########################################################################
#
# Postgres Enterprise Manager
#
# Copyright (C) 2016 - 2025, EnterpriseDB Corporation. All rights reserved.
#
##########################################################################

"""Implements Probes"""

import json
from flask import render_template, request
from flask_babel import gettext
from pgadmin.utils.ajax import internal_server_error, bad_request, \
    make_json_response
from pgadmin.utils import PgAdminModule
from flask import url_for
from flask_security import login_required
from pgadmin.pem.utils import pem_connection
from .copy import register_copy_routes
from .custom import register_custom_routes
from . import utils

MODULE_NAME = 'probes'


class ProbesModule(PgAdminModule):
    """
    class ProbesModule(Object):

        It is a wizard which inherits PgAdminModule
        class and define methods to load its own
        javascript file.
    """

    LABEL = gettext('Probes')

    def get_own_stylesheets(self):
        """
        Returns:
            list: the stylesheets used by this module.
        """
        stylesheets = [
            url_for('probes.static', filename='css/probes.css')
        ]
        return stylesheets

    def get_exposed_url_endpoints(self):
        """
        Returns:
            list: a list of url endpoints exposed to the client.
        """
        return [
            'probes.copy_nodes', 'probes.coll_copy_nodes',
            'probes.server_group_nodes',
            'probes.agent_copy_nodes', 'probes.server_copy_nodes',
            'probes.db_copy_nodes', 'probes.schema_copy_nodes',
            'probes.copy_config', 'probes.custom_save', 'probes.custom_list',
            'probes.custom_export', 'probes.custom_import',
            'probes.save', 'probes.count', 'probes.object_probe_list',
            'probes.db_probe_list', 'probes.schema_probe_list',
            'probes.schema_object_probe_list',
            'probes.extension_probe_list',
            'probes.server_versions',
            'probes.get_extensions',
            'probes.get_extension_versions',
            'probes.set_default',
            'probes.set_default_extension_probe',
            'probes.light_list'
        ]


# Create blueprint for Manage Probes class
blueprint = ProbesModule(
    MODULE_NAME, __name__, static_url_path='', url_prefix="/pem/probes")

register_copy_routes(blueprint)
register_custom_routes(blueprint)


@blueprint.route("/")
@login_required
def index():
    return bad_request(errormsg=gettext(
        "This URL cannot be called directly!")
    )


@blueprint.route('/light_list', methods=["GET"], endpoint='light_list')
@pem_connection
@login_required
@utils.configProbeRole.check_role(gettext(
    "Logged-in user do not have permission to access probe list."
))
def probe_light_list(pem_conn=None):
    """
    This function returns the probe count corresponding to target type.
    :param pem_conn: PEM Connection object.
    """

    status, result = utils.get_light_probe_list(pem_conn=pem_conn)

    if not status:
        return internal_server_error(errormsg=result)

    return {'probes': result}


@blueprint.route('/count', methods=["GET"], endpoint='count')
@pem_connection
@login_required
@utils.configProbeRole.check_role(gettext(
    "Logged-in user do not have permission to access probe count."
))
def probe_count(pem_conn=None):
    """
    This function returns the probe count corresponding to target type.
    :param pem_conn: PEM Connection object.
    """

    sql = render_template('probes/sql/probes/count.sql')

    # Execute the query.
    status, probes = pem_conn.execute_dict(sql)

    if not status:
        return internal_server_error(errormsg=probes)

    return make_json_response(data=probes['rows'])


@blueprint.route(
    '/list/<int:target_type_id>',
    methods=["GET"], endpoint='probe_list'
)
@blueprint.route(
    '/list/<int:target_type_id>/<int:object_id>', methods=["GET"],
    endpoint='object_probe_list'
)
@blueprint.route(
    '/list/<int:target_type_id>/<int:object_id>/<database_name>',
    methods=["GET"], endpoint='db_probe_list'
)
@blueprint.route(
    '/list/<int:target_type_id>/<int:object_id>/<database_name>/<schema_name>',
    methods=["GET"], endpoint='schema_probe_list'
)
@blueprint.route(
    '/list/<int:target_type_id>/<int:object_id>/<database_name>/'
    '<schema_name>/<object_name>', methods=["GET"],
    endpoint='schema_object_probe_list'
)
@login_required
@utils.configProbeRole.check_role(
    gettext("Logged-in user do not have permission to access probe list.")
)
@pem_connection
def get_probe_list(target_type_id, object_id=None, database_name=None,
                   schema_name=None, object_name=None, pem_conn=None):
    """
    This function will return the list of probes.

    :param target_type_id: target type id.
    :param object_id: Agent/Server id.
    :param database_name: database name.
    :param schema_name: schema name.
    :param object_name: Table/Index/Function/View/Procedure name.
    :param pem_conn: PEM Connection object
    """

    status, probes = utils.get_probes(
        target_type_id, object_id, database_name, schema_name, object_name,
        pem_conn
    )

    if not status:
        return internal_server_error(errormsg=probes)

    return make_json_response(data=probes['rows'])


@blueprint.route(
    '/list/<int:target_type_id>/<int:object_id>/<database_name>/'
    '<extension_name>',
    methods=["GET"], endpoint='extension_probe_list'
)
@login_required
@utils.configProbeRole.check_role(
    gettext("Logged-in user do not have permission to access probe list.")
)
@pem_connection
def get_extension_probe_list(target_type_id, object_id=None,
                             database_name=None,
                             extension_name=None, pem_conn=None):
    """
    This function will return the list of probes.

    :param target_type_id: target type id.
    :param object_id: Agent/Server id.
    :param database_name: database name.
    :param extension_name: extension name.
    :param pem_conn: PEM Connection object
    """
    status, probes = utils.get_probes(
        target_type_id, object_id, database_name, extension_name, None,
        pem_conn
    )

    if not status:
        return internal_server_error(errormsg=probes)

    return make_json_response(data=probes['rows'])


@blueprint.route('/save', methods=["PUT", "POST"], endpoint='save')
@login_required
@utils.configProbeRole.check_role(gettext(
    "Logged-in user do not have permission to save probe configurations."
))
@pem_connection
def save_probe_config(pem_conn=None):
    """
    This function is used to store the probe configuration
    depending on target type.

    :param pem_conn: PEM Connection Object.
    """

    if request.data:
        change_probe_data = json.loads(request.data.decode())
    else:
        change_probe_data = request.args or request.form

    status, result = utils.save_probes(change_probe_data, pem_conn)
    if not status:
        return internal_server_error(errormsg=result)

    return make_json_response(
        data=result
    )


@blueprint.route('/set_default/<int:target_type_id>/<int:object_id>/'
                 '<database_name>/<schema_name>/<object_name>',
                 methods=["POST"], endpoint='set_default')
@login_required
@utils.configProbeRole.check_role(gettext(
    "Logged-in user do not have permission to save probe configurations."
))
@pem_connection
def set_default_probe(
    target_type_id, object_id=None, database_name=None, schema_name=None,
        object_name=None, pem_conn=None):
    """
    This function is used to set the probe configuration to default
    depending on target type.

    :param target_type_id: target type id.
    :param object_id: Agent/Server id.
    :param database_name: database name.
    :param schema_name: schema name.
    :param object_name: Table/Index/Function/View/Procedure name.
    :param extension_name: extension name.
    :param pem_conn: PEM Connection object
    """

    status, response = utils.set_probes_to_default(
        target_type_id, object_id, database_name, schema_name,
        object_name, pem_conn)

    if not status:
        return internal_server_error(errormsg=response)

    return make_json_response(status=200)


@blueprint.route('/set_default/<int:target_type_id>/<int:object_id>'
                 '/<database_name>/<extension_name>',
                 methods=["POST"], endpoint='set_default_extension_probe')
@login_required
@utils.configProbeRole.check_role(gettext(
    "Logged-in user do not have permission to save probe configurations."
))
@pem_connection
def set_default_extension_probe(
    target_type_id, object_id=None, database_name=None,
        extension_name=None, pem_conn=None):
    """
    This function is used to set the probe configuration to default
    depending on target type.

    :param target_type_id: target type id.
    :param object_id: Agent/Server id.
    :param database_name: database name.
    :param extension_name: extension name.
    :param pem_conn: PEM Connection object
    """

    status, response = utils.set_extension_probes_to_default(
        target_type_id, object_id, database_name,
        extension_name, pem_conn)

    if not status:
        return internal_server_error(errormsg=response)

    return make_json_response(status=200)
