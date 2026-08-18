##########################################################################
#
# Postgres Enterprise Manager
#
# Copyright (C) 2016 - 2025, EnterpriseDB Corporation. All rights reserved.
#
##########################################################################

"""A Module container for keeping all the submodules for PEM Charts."""

from pgadmin.utils import PgAdminModule
from pgadmin.utils.ajax import bad_request
from flask_babel import gettext
from .utils import ChartViewMeta

MODULE_NAME = 'charts'


class ChartsModule(PgAdminModule):

    LABEL = gettext('Charts')

    def __init__(self, *args, **kwargs):
        super(ChartsModule, self).__init__(*args, **kwargs)
        self._exposed_url = []

    def register_exposed_url_endpoints(self, _url):
        self._exposed_url.append(_url)

    def get_exposed_url_endpoints(self):
        """
        Returns:
            list: a list of url endpoints exposed to the client.
        """
        return ['{0}.{1}'.format('charts', url) for url in self._exposed_url]


# Initialise the module
blueprint = ChartsModule(MODULE_NAME, __name__)

# Load all chart modules first
ChartViewMeta.load_classes()

# Register ChartView classes
for name, chart_class in list(ChartViewMeta.classes().items()):
    chart_class.register_chart_view(blueprint)


@blueprint.route("/")
def index():
    """Calling management index URL directly is not allowed."""
    return bad_request(gettext('This URL cannot be requested directly.'))
