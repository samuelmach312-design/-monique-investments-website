##########################################################################
#
# Postgres Enterprise Manager
#
# Copyright (C) 2016 - 2025, EnterpriseDB Corporation. All rights reserved.
#
##########################################################################

"""Exposes utiltiy for the api v2."""

from functools import partial

from pgadmin.pem.api.v2 import MODULE_NAME
from pgadmin.pem.api.utils import create_api_route

# Utility function to register route under v2_api blueprint.
create_v2_api_route = partial(create_api_route, MODULE_NAME)
