
from pgadmin.pem.api.utils import create_api_view
from pgadmin.browser.server_groups.agents.jobs.api.api import *

# Register Agent Job View
create_api_view(AgentJobApiView)
