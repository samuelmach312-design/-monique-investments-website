##########################################################################
#
# Postgres Enterprise Manager
#
# Copyright (C) 2016 - 2025, EnterpriseDB Corporation. All rights reserved.
#
##########################################################################

"""Exposes utility for the api v15."""

from functools import partial

from pgadmin.pem.api.v15 import MODULE_NAME
from pgadmin.pem.api.utils import create_api_route

# Utility function to register route under v15_api blueprint.
create_v15_api_route = partial(create_api_route, MODULE_NAME)
