##########################################################################
#
# Postgres Enterprise Manager
#
# Copyright (C) 2016 - 2025, EnterpriseDB Corporation. All rights reserved.
#
##########################################################################

"""A Module container for keeping all the submodules for PEM Monitoring."""

from flask import url_for
from pgadmin.utils import PgAdminModule
from pgadmin.utils.ajax import bad_request
from flask_babel import gettext
from flask_security import login_required

MODULE_NAME = 'monitor'


class MonitorModule(PgAdminModule):
    LABEL = gettext('Monitor')

    def get_own_stylesheets(self):
        """
        Returns:
            list: the stylesheets used by this module.
        """
        stylesheets = [
            url_for('monitor.static', filename='css/monitor.css')
        ]
        return stylesheets


# Initialise the module
blueprint = MonitorModule(MODULE_NAME, __name__, url_prefix='/pem/monitor')


@login_required
@blueprint.route("/")
def index():
    """Calling management index URL directly is not allowed."""
    return bad_request(gettext('This URL cannot be requested directly.'))
