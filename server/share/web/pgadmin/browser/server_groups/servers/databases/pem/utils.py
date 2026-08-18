##########################################################################
#
# Postgres Enterprise Manager
#
# Copyright (C) 2016 - 2025, EnterpriseDB Corporation. All rights reserved.
#
##########################################################################

"""Database helper utilities for PEM """
from flask import render_template, current_app
from pgadmin.pem.utils import pem_connection
from pgadmin.utils.pem.server import Server


class SchemaRestriction(object):
    """Class to perform CRUD operation for schema restriction"""
    @staticmethod
    def get_database_name(conn, did):
        status, res = conn.execute_scalar(
            """
            SELECT db.datname as name
            FROM pg_database db
            LEFT OUTER JOIN pg_tablespace ta ON db.dattablespace = ta.oid
            WHERE db.oid = %(did)s
            """,
            {'did': did}
        )
        if not status:
            current_app.logger.error(
                "Failed to get database name for did (#{0}).\n"
                "Error: {1}".format(did, res)
            )
            return None
        return res

    @staticmethod
    @pem_connection
    def get(sid, database, pem_conn=None):
        """
        Fetch the schema restriction for the current database

        sid: Server ID
        database: Database name
        pem_conn: PEM Connection
        """
        status, res = pem_conn.execute_scalar(
            """
            SELECT schema_restriction FROM pem.database_option
            WHERE server_id = %(sid)s AND database = %(database)s
            """,
            {'sid': sid, 'database': database}
        )

        if not status:
            current_app.logger.error(
                "Failed to get schema_restriction for databse (#{0}:{1}).\n"
                "Error: {1}".format(sid, database, res)
            )
            return None
        return res.split(',') if res else []

    @staticmethod
    @pem_connection
    def update(sid, database, data, pem_conn=None):
        """
        Update the schema restriction for the current database
        if row is not exists then insert new row in database option
        table

        sid: Server ID
        database: Database name
        data: Request payload data
        pem_conn: PEM Connection
        """
        sql = None
        if 'schema_res' not in data or data['schema_res'] is None or \
                data['schema_res'] == '':
            return None

        schema_res = ','.join(data['schema_res'])

        status, res = pem_conn.execute_scalar(
            """
            SELECT count(*) FROM pem.database_option
            WHERE server_id = %(sid)s AND database = %(database)s
            AND pem_user = current_user
            """,
            {'sid': sid, 'database': database}
        )
        if not status:
            current_app.logger.error(
                "Failed to get schema_restriction for databse (#{0}:{1}).\n"
                "Error: {2}".format(sid, database, res)
            )
            return status

        if int(res) > 0:
            # Update the existing row
            sql = """
            UPDATE pem.database_option
                SET schema_restriction = %(schema_res)s
            WHERE server_id = %(sid)s
                AND database = %(database)s
                AND pem_user = current_user
            """
        else:
            sql = """
            INSERT INTO pem.database_option
                (server_id, database, schema_restriction)
            VALUES (%(sid)s, %(database)s, %(schema_res)s)
            """

        status, res = pem_conn.execute_void(
            sql, {
                'sid': sid,
                'database': database,
                'schema_res': schema_res
            }
        )
        if not status:
            current_app.logger.error(
                "Failed to apply schema_restriction for databse (#{0}:{1}).\n"
                "Error: {2}".format(sid, database, res)
            )
            return None

        return status
