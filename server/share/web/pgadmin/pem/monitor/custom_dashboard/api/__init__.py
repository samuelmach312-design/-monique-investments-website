##########################################################################
#
# Postgres Enterprise Manager
#
# Copyright (C) 2016 - 2025, EnterpriseDB Corporation. All rights reserved.
#
##########################################################################
"""Register Dashboard API view with blueprint"""

from pgadmin.pem.monitor.custom_dashboard.api.dashboard_import_export import \
    DashboardExportApiView, DashboardImportApiView

from pgadmin.pem.api.utils import create_api_view

# V7 Register API view for Import/Export Charts
create_api_view(DashboardExportApiView)
create_api_view(DashboardImportApiView)
