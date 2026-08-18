############################################################################
#
# Postgres Enterprise Manager
#
# Copyright (C) 2016 - 2025, EnterpriseDB Corporation. All rights reserved.
#
############################################################################

from flask_babel import gettext
from functools import wraps

from pgadmin.pem import _pem


class PEMRole(object):
    """Class to define the PEM privilege role"""
    __registry = dict()

    def __init__(self, _privilege, _name, _component, _description):
        self.privilege = _privilege
        self.name = _name
        self.component = _component
        self.description = _description

        assert _privilege not in PEMRole.__registry
        PEMRole.__registry[_privilege] = self

    def has_role(self) -> bool:
        """Check the current user is member of the role, or not."""
        return _pem.has_pem_privilege(self.privilege)

    def check_role(self, msg=None):
        """
        A decorator to check the role for the current user.

        If current user does not have the role, it raises the RoleRequired
        exception.
        """
        def inner_wrapper(f):

            @wraps(f)
            def wrap(*args, **kwargs):
                conn = kwargs.get('pem_conn', None)
                if not self.has_role():
                    from pgadmin.pem.utils.role import RoleRequired
                    raise RoleRequired(
                        _msg=gettext(msg), _role=gettext(self.privilege),
                        _name=gettext(self.name)
                    )

                return f(*args, **kwargs)
            return wrap

        return inner_wrapper

    @classmethod
    def has_pem_role(cls, rolename):
        role = cls.__registry.get(rolename, None)
        return role is not None and role.has_role()
