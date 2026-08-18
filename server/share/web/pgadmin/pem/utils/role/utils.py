############################################################################
#
# Postgres Enterprise Manager
#
# Copyright (C) 2016 - 2025, EnterpriseDB Corporation. All rights reserved.
#
############################################################################

from .role import PEMRole


def has_pem_role(rolename: str) -> bool:
    return PEMRole.has_pem_role(rolename)


def _role_missing_message(rolename, role):
    return f"Role '{rolename}' is missing the required '{role}' role."
