##########################################################################
#
# Postgres Enterprise Manager
#
# Copyright (C) 2016 - 2025, EnterpriseDB Corporation. All rights reserved.
#
##########################################################################


""" Api for servers """

from flask import request
from flask_babel import gettext
import json

from pgadmin.pem.api.utils import ApiView
from pgadmin.pem.api.utils import create_api_view
from pgadmin.pem.utils import pem_token_required
from pgadmin.utils.ajax import bad_request
from . import utils


class ServerConfigView(ApiView):
    """
    API routes for accessing the PEM configuration.
    """
    decorators = (pem_token_required,)
    endpoint = 'server_config'
    url = '/config/'
    pk = 'param'
    pk_type = 'string'
    methods = ['GET', 'PUT']

    def get(self, param=None):
        """

        :param param:
        :return:
        """
        return utils.config(param)

    def put(self, param):
        """

        :param param:
        :return:
        """
        try:
            data = json.loads(request.data)
        except BaseException:
            return bad_request(errormsg=gettext("Invalid data!"))

        if 'value' not in data:
            return bad_request(errormsg=gettext("Invalid data!"))

        return utils.update(param, data['value'])


create_api_view(ServerConfigView)
