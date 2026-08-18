########################################################################
#
# Postgres Enterprise Manager
#
# Copyright (C) 2015 - 2025, EnterpriseDB Corporation
#
# web/pgadmin/utils/driver/pem/__init__.py - PEM (psycopg3) connection driver
#     class.
#
##########################################################################

"""
Implementation of Driver class
It is a wrapper around the actual psycopg3 driver, and connection
object.

"""
from threading import Lock

from flask import session
import datetime

from pgadmin.pem import _pem
from pgadmin.utils.driver.psycopg3 import Driver as PsycopgDriver


_pem_driver_connections_restore_lock = Lock()


class Driver(PsycopgDriver):
    """
    class Driver(PsycopgDriver):

    This driver acts as a wrapper around psycopg3 connection driver
    implementation. We will be using psycopg3 for makeing connection with
    the PostgreSQL/EDB Postgres Advanced Server (EnterpriseDB).

    Properties:
    ----------

    * Version (string):
        Version of psycopg3 driver

    Methods:
    -------
    * connection_manager(sid)
    - It returns the server connection manager for this session.
    """
    def __init__(self, **kwargs):
        super(Driver, self).__init__()

    def _restore_connections_from_session(self):
        """
        Used internally by connection_manager to restore connections
        from sessions.
        """
        session_id = str(session.sid)

        if session_id in self.managers:
            return self.managers[session_id]

        self.managers[session_id] = managers = dict()

        if '__pem_server_managers' in session:
            server_managers = \
                session['__pem_server_managers'].copy()

            for sid in server_managers:
                try:
                    server_manager = _pem.ServerManager(sid)
                    server_manager._restore(server_managers[sid])
                    server_manager.update_session()
                    managers[sid] = server_manager
                except _pem.ServerNotFound as snfex:
                    pass

            return managers

    def connection_manager(self, sid=None):
        """
        connection_manager(...)

        Returns the ServerManager object for the current session. It will
        create new ServerManager object (if necessary).

        Parameters:
            sid
            - Server ID
        """
        assert (sid is not None and isinstance(sid, int))

        manager = None
        session_id = str(session.sid)
        server_id = str(sid)

        if session_id not in self.managers:
            with _pem_driver_connections_restore_lock:
                # The wait is over but the object might have been loaded
                # by some other thread check again
                self._restore_connections_from_session()

        with _pem_driver_connections_restore_lock:
            server_managers = self.managers[session_id]
            if server_id in server_managers:
                manager = server_managers[server_id]
                server_managers['pinged'] = datetime.datetime.now()

                return manager

        if server_id in server_managers:
            return self.managers[server_id]

        with _pem_driver_connections_restore_lock:
            server_managers['pinged'] = datetime.datetime.now()
            server_managers[server_id] = _pem.ServerManager(sid)
            return server_managers[server_id]
