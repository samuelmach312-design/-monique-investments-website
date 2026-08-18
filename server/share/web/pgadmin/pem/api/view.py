##########################################################################
#
# Postgres Enterprise Manager
#
# Copyright (C) 2016 - 2022, EnterpriseDB Corporation. All rights reserved.
#
##########################################################################

from flask import Response
from flask.views import MethodView
from flask_babel import gettext
import json

from pgadmin.pem.utils import pem_connection, pem_token_required, \
    ALL_API_MODULES
from .exception import APIJSONException


def api_method_not_allowed(*args, **kwargs):
    """Responsible for returning 405 response for invalid methods"""
    return Response(
        response=json.dumps(dict({'error': ("Method not allowed!")})),
        mimetype="application/json",
        status=405
    )


class ApiView(MethodView):
    """
    Base class to create views (flask methodviews) with some required
    defaults.
    """
    decorators = (pem_connection, pem_token_required)
    url = None
    pk = 'id'
    pk_type = 'int'
    get = post = delete = put = api_method_not_allowed
    api_versions = ALL_API_MODULES

    def discard_unwanted_params(self, data, params=None):
        if params is None:
            params = self.params
        for param in list(data):
            if param not in params:
                del data[param]
        return data

    def check_for_invalid_param(self, data):
        for key in list(data):
            if key not in self.params:
                raise APIJSONException(
                    gettext('%s is not an valid input data!') % key
                )
