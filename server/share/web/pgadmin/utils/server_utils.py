##########################################################################
#
# pgAdmin 4 - PostgreSQL Tools
#
# Copyright (C) 2013 - 2025, The pgAdmin Development Team
# This software is released under the PostgreSQL Licence
#
##########################################################################


import json
from regression.test_setup import config_data

SERVER_URL = '/browser/server/obj/'
SERVER_CONNECT_URL = '/browser/server/connect/'
DUMMY_SERVER_GROUP = 10000


def connect_server(self, server_id):
    """
    This function used to connect added server
    :param self: class object of server's test class
    :type self: class
    :param server_id: server id
    :type server_id: str
    """
    kwargs = {
        'data': json.dumps({"password":self.server['db_password']}),
        'follow_redirects': True
    }
    if config_data['api_production']:
        kwargs['verify'] = False
    response = self.tester.post(SERVER_CONNECT_URL + str(DUMMY_SERVER_GROUP) +
                                '/' + str(server_id),
                                **kwargs)
    assert response.status_code == 200
    response_data = json.loads(response.data.decode('utf-8'))
    return response_data
