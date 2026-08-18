############################################################################
#
# Postgres Enterprise Manager
#
# Copyright (C) 2016 - 2025, EnterpriseDB Corporation. All rights reserved.
#
############################################################################

from flask_babel import gettext
from functools import wraps
from werkzeug.exceptions import HTTPException


class RoleRequired(HTTPException):
    """
    RoleRequired Exception
    """

    def __init__(self, _msg=None, _role=None, _name=None, _react_comp=False):
        super(RoleRequired, self).__init__(self)

        self.msg = _msg
        self.role = _role
        self.rolename = _name
        self.code = 401
        self.content_type = 'text/plain; charset=utf-8'

    @property
    def name(self):
        from werkzeug.http import HTTP_STATUS_CODES
        return HTTP_STATUS_CODES.get(401, 'Unauthorized')

    @property
    def _message(self) -> str:
        from .utils import _role_missing_message
        if self.msg is not None:
            return gettext(self.msg)

        return _role_missing_message(self.rolename, self.role)

    def _text_body(self):
        return self._message

    def get_body(self, environ=None, scope=None):
        return self._message

    def get_headers(self, environ=None, scope=None):
        return [
            ('Content-Type', self.content_type),
            ('PEM-Role-Name', self.rolename),
            ('PEM-Role-Required', self.role)
        ]

    def __repr__(self):
        return "Role required: {0} ({1})".format(self.role, self.rolename)

    def __str__(self):
        return self.__repr__()
