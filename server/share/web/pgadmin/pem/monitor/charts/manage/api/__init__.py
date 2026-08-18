##########################################################################
#
# Postgres Enterprise Manager
#
# Copyright (C) 2016 - 2025, EnterpriseDB Corporation. All rights reserved.
#
##########################################################################
"""Register Chart API view with blueprint"""

from pgadmin.pem.monitor.charts.manage.api.chart_import_export import \
    ChartExportApiView, ChartImportApiView

from pgadmin.pem.api.utils import create_api_view

# V7 Register API view for Import/Export Charts
create_api_view(ChartExportApiView)
create_api_view(ChartImportApiView)
