##########################################################################
#
# Postgres Enterprise Manager
#
# Copyright (C) 2016 - 2025, EnterpriseDB Corporation. All rights reserved.
#
##########################################################################

"""Implements Server Configuration"""

import json
from flask import request, url_for
from flask_babel import gettext

from pgadmin.utils import PgAdminModule
from pgadmin.utils.ajax import bad_request
from pgadmin.pem.utils.role import configManageRole
from flask_security import login_required
from . import utils


MODULE_NAME = 'server_config'


class ServerConfigModule(PgAdminModule):
    """
    class ServerConfigModule(Object):

        Inherits PgAdminModule
        class and define methods to load its own
        javascript file.
    """

    LABEL = gettext('Server Configuration')

    def get_own_stylesheets(self):
        return [url_for('server_config.static',
                        filename='css/server_config.css')]

    def get_exposed_url_endpoints(self):
        """
        Returns:
            list: a list of url endpoints exposed to the client.
        """
        return [
            'server_config.index', 'server_config.store'
        ]


# Create blueprint for Server Config class
blueprint = ServerConfigModule(
    MODULE_NAME, __name__, static_url_path='', url_prefix='/pem/server_config')


@blueprint.route("/", endpoint='index', methods=['GET'])
@login_required
@configManageRole.check_role(gettext(
    "Logged-in user do not have permission to access server configurations "
    "list."
))
def config_list():
    """Return a list of configuration parameters for pem server."""
    return utils.config()


@blueprint.route("/", endpoint='store', methods=['POST'])
@login_required
@configManageRole.check_role(gettext(
    "Logged-in user do not have permission to save server configurations list."
))
def store():
    """store server configurations."""
    if request.data:
        try:
            req = json.loads(request.data.decode())
        except BaseException:
            return bad_request(gettext('Invalid data input!'))
    else:
        req = request.args or request.form

    return utils.bulk_update(req)
