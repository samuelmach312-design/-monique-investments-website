##########################################################################
#
# Postgres Enterprise Manager
#
# Copyright (C) 2016 - 2022, EnterpriseDB Corporation. All rights reserved.
#
##########################################################################

import json
from werkzeug.exceptions import HTTPException


class APIJSONException(HTTPException):

    def __init__(self, message, status_code=417):
        HTTPException.__init__(self)
        self.msg = message
        self.code = status_code

    def get_body(self, environ=None, scope=None):
        return json.dumps({
            'errormsg': self.msg,
            'success': 0,
            'status_code': self.code
        })

    def get_headers(self, environ=None, scope=None):
        return [('Content-Type', 'application/json; charset=utf-8')]
