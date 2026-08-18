##########################################################################
#
# Postgres Enterprise Manager
#
# Copyright (C) 2016 - 2025, EnterpriseDB Corporation. All rights reserved.
#
##########################################################################
"""Register API with Blueprint"""
from pgadmin.browser.server_groups.servers.api.api import *

from pgadmin.pem.api.utils import create_api_view

# Register API View

# V1 api
create_api_view(ServerApiV1View)

# V2, V3 api
create_api_view(ServerApiV2View)
create_api_view(ServerApiV3View)
create_api_view(ServerApiV4View)

# V1 and V2 api
create_api_view(DatabaseApiView)
create_api_view(SchemaApiView)
create_api_view(TableApiView)
create_api_view(IndexApiView)
create_api_view(SequenceApiView)
create_api_view(ViewApiView)
create_api_view(FunctionApiView)

# V4 api
create_api_view(ServerStatusApiView)

# V6 api
create_api_view(ExcludeDatabaseApiView)
