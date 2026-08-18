##########################################################################
#
# Postgres Enterprise Manager
#
# Copyright (C) 2016 - 2025, EnterpriseDB Corporation. All rights reserved.
#
##########################################################################

# Role of this file to fetch the server groups
# In pgAdmin4 we use sqlite3 to store data it but in PEM we use database tables

from flask import render_template, current_app
from flask_babel import gettext
from pgadmin.pem.utils import pem_connection
from collections import namedtuple
from flask_security import current_user


@pem_connection
def fetch_data(sgid=None, pem_conn=None):
    """

    :param sgid: Server group ID
    :param pem_conn: PEM connection

    :return: Object based array
    """
    result = []
    sql = render_template(
        'servers/sql/properties.sql',
        sgid=sgid, schema_version=current_user.schema_version
    )
    status, res = pem_conn.execute_dict(sql)
    if not status:
        current_app.logger.exception(
            gettext(
                'Failed to fetch server groups.\n'
                'Details: {0}'.format(res)
            )
        )
        return result

    # Convert dict to object base structure of ServerGroup Model
    for server_group in res['rows']:
        result.append(
            namedtuple(
                'ServerGroup',
                ['id', 'user_id', 'name'])
            (server_group['gid'], None,
             server_group['server_group_name']))

    # Return the server group specific data not an array
    if sgid and len(result) == 1:
        return result[0]

    return result


class ServerGroup(object):
    """
    A class to fetch the PEM server groups which will mimic as ServerGroup
    Model
    """
    @staticmethod
    def all():
        """
        Wrapper to return all the server groups
        :return:
        """
        return fetch_data()

    @staticmethod
    def get(sid=None):
        """
        Wrapper to return single server group
        :param sid:
        :return:
        """
        return fetch_data(sgid)
