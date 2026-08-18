##########################################################################
#
# Postgres Enterprise Manager
#
# Copyright (C) 2016 - 2025, EnterpriseDB Corporation. All rights reserved.
#
##########################################################################

"""Exposes utiltiy for the api v4."""

from functools import partial

from pgadmin.pem.api.v4 import MODULE_NAME
from pgadmin.pem.api.utils import create_api_route

# Utility function to register route under v3_api blueprint.
create_v4_api_route = partial(create_api_route, MODULE_NAME)
