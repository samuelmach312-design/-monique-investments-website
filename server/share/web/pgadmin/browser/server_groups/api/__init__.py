##########################################################################
#
# Postgres Enterprise Manager
#
# Copyright (C) 2016 - 2025, EnterpriseDB Corporation. All rights reserved.
#
##########################################################################
"""Register API with Blueprint"""
# from pgadmin.browser.server_groups.servers.api.api import *
from pgadmin.browser.server_groups.api.server_group_api import \
    ServerGroupApiView

from pgadmin.pem.api.utils import create_api_view
# Register API View

# v8 api
server_group_api_blueprint = create_api_view(ServerGroupApiView)
