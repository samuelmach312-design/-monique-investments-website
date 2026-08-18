##########################################################################
#
# Postgres Enterprise Manager
#
# Copyright (C) 2016 - 2025, EnterpriseDB Corporation. All rights reserved.
#
##########################################################################

""" Role of this file is to fetch the servers required by the Schema
diff tool and others.
In pgAdmin4 we use sqlite3 to store data but in PEM we use PEM database
tables """

from flask import render_template, current_app
from flask_babel import gettext
from pgadmin.pem.utils import pem_connection
from collections import namedtuple


@pem_connection
def fetch_data(sid=None, pem_conn=None):
    """

    :param sid: Server ID
    :param pem_conn: PEM connection

    :return: Object based array
    """
    result = []
    sql = render_template(
        'servers/sql/get_server.sql',
        sid=sid
    )
    status, res = pem_conn.execute_dict("""
        SELECT
        s.*,
        COALESCE(usg.name, sg.name) AS server_group_name
        FROM ({0}) s
        LEFT OUTER JOIN pem.server_group sg
            ON (sg.id::text = s.server_group_id::text)
        LEFT OUTER JOIN pem.user_server_group usg
        ON (
            usg.id::text = s.server_group_id::text
            AND usg.uid = pem.current_user_id()
        )
        """.format(sql)
    )
    if not status:
        current_app.logger.exception(
            gettext(
                'Failed to fetch servers.\n'
                'Details: {0}'.format(res)
            )
        )
        return result

    # Convert dict to object base structure so that we don't have to change
    # the existing logic of schema diff to access the variables
    # OR will require minimal changes if any
    for server in res['rows']:
        server['servergroup_id'] = server['server_group_id']
        server['shared'] = None
        server['cloud_status'] = None
        server['service'] = None
        result.append(namedtuple('Server', server.keys())(*server.values()))

    # Return the server specific data not an array
    if sid and len(result) == 1:
        return result[0]

    return result


class Server(object):
    """
    A class to fetch the PEM servers which will mimic as Server Model
    """
    @staticmethod
    def all():
        """
        Wrapper to return all the servers
        :return:
        """
        return fetch_data()

    @staticmethod
    def get(sid=None):
        """
        Wrapper to return single server
        :param sid:
        :return:
        """
        return fetch_data(sid)

    @staticmethod
    def colors(obj):
        """
        Return as Dict for icon fetching
        :param obj: Server object
        :return:
        """
        return {
            'bgcolor': obj.bgcolor,
            'fgcolor': obj.fgcolor
        }
