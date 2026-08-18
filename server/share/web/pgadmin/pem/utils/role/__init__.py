############################################################################
#
# Postgres Enterprise Manager
#
# Copyright (C) 2016 - 2025, EnterpriseDB Corporation. All rights reserved.
#
############################################################################

"""A Module container for defining the base component role."""

from flask_babel import gettext

from .role import PEMRole
from .exception import RoleRequired
from .utils import has_pem_role


# Super Administrator
superAdminRole = PEMRole(
    'pem_super_admin', gettext('Super administrator'), None,
    gettext(
        'An administrator privilege to access, manage, configure everything on'
        ' Postgres Enterprise Manager.'
    )
)

# Admin
adminRole = PEMRole(
    'pem_admin', gettext('Administrator'), None,
    gettext(
        'An administrator privilege to manage, to configure, and to admin the '
        'shared/registered monitored server, and/or agent.'
    )
)

compRole = PEMRole(
    'pem_component', gettext('Components'), None,
    gettext(
        'A privilege to run any component defiend by the system (i.e. '
        'Log manager, Audit log manager, Auto discovery of the database '
        'servers, Log analysis expert, Postgres expert, Tuning wizard, '
        'etc.)'
    )
)

scheduleTaskRole = PEMRole(
    'pem_manage_schedule_task', gettext('Scheduled tasks'),
    gettext('Scheduled Tasks'), gettext(
        'Priviledge to manage the scheduled tasks on Postgres Enterprise '
        ' Manager.'
    )
)

configManageRole = PEMRole(
    'pem_config', gettext('Configuration management'), None,
    gettext(
        'A privilege with whole system configuration privileges (i.e. probe'
        'configuration, alert configuration, etc.)'
    )
)


__all__ = [
    'PEMRole', 'RoleRequired', 'scheduleTaskRole', 'compRole', 'adminRole',
    'has_pem_role', 'configManageRole'
]
