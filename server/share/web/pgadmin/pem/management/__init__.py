##########################################################################
#
# Postgres Enterprise Manager
#
# Copyright (C) 2016 - 2025, EnterpriseDB Corporation. All rights reserved.
#
##########################################################################

"""A Module container for keeping all the submodules for PEM Management."""

from pgadmin.utils import PgAdminModule
from pgadmin.utils.ajax import bad_request
from flask_babel import gettext

MODULE_NAME = 'management'

# Initialise the module
blueprint = PgAdminModule(MODULE_NAME, __name__)


@blueprint.route("/")
def index():
    """Calling management index URL directly is not allowed."""
    return bad_request(gettext('This URL cannot be requested directly.'))
