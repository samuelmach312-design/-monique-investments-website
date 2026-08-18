##########################################################################
#
# Postgres Enterprise Manager
#
# Copyright (C) 2016 - 2025, EnterpriseDB Corporation. All rights reserved.
#
##########################################################################

"""Exposes utiltiy for the api v13."""

from functools import partial

from pgadmin.pem.api.v13 import MODULE_NAME
from pgadmin.pem.api.utils import create_api_route

# Utility function to register route under v13_api blueprint.
create_v13_api_route = partial(create_api_route, MODULE_NAME)
