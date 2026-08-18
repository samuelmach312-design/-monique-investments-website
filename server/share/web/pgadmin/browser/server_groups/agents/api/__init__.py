##########################################################################
#
# Postgres Enterprise Manager
#
# Copyright (C) 2015 - 2025, EnterpriseDB Corporation. All rights reserved.
#
##########################################################################
"""Register Api for Agent"""

from pgadmin.browser.server_groups.agents.api.api import \
    AgentApiV1View, AgentApiV2View, AgentApiV3View, AgentStatusApiView
from pgadmin.pem.api.utils import create_api_view

# Register V1 API View
create_api_view(AgentApiV1View)

# Register V2 API View
create_api_view(AgentApiV2View)

# Register V3 API View
create_api_view(AgentApiV3View)

# Register Agent status (v4+ API View)
create_api_view(AgentStatusApiView)
