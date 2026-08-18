##########################################################################
#
# Postgres Enterprise Manager
#
# Copyright (C) 2016 - 2025, EnterpriseDB Corporation. All rights reserved.
#
##########################################################################

"""Exposes utiltiy for the api v1."""

from functools import partial

from pgadmin.pem.api.v1 import MODULE_NAME
from pgadmin.pem.api.utils import create_api_route

# Utility function to register route under v1_api blueprint.
create_v1_api_route = partial(create_api_route, MODULE_NAME)
