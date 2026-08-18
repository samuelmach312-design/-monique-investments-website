##########################################################################
#
# Postgres Enterprise Manager
#
# Copyright (C) 2016 - 2025, EnterpriseDB Corporation. All rights reserved.
#
##########################################################################

"""Probe Copy API"""

from flask import request
from flask_babel import gettext

from pgadmin.pem.api.utils import ApiView
from pgadmin.pem.monitor.probes import utils
from pgadmin.pem.utils import is_agent_exists, is_object_exists
from pgadmin.utils.ajax import make_json_response, success_return


NO_TARGET_SUPPLIED_MSG = "No target supplied to copy probe configuration."
COPY_PROBE_CONFIGURE_SUCCESS_MSG = "Copy probe configuration successfully."


class AgentCopyApiView(ApiView):
    """
    API to expose the copy of the probes at agent level.
    """

    endpoint = 'agent_copy_probe'
    url = '/probe/copy/agent/<int:agent_id>'
    methods = ['POST']
    pk = None

    def post(self, agent_id, pem_conn=None):
        """
        This function is used to copy probe configuration for
        the specified agent to the specified targets.

        :param agent_id: Agent Id for which probe configuration will be copied
        :param pem_conn: PEM Connection Object
        :return: JSON response
        """
        targets = request.get_json()

        # If targets is not supplied then return 404.
        if targets is None or len(targets) <= 0:
            return make_json_response(
                status=404, success=0,
                errormsg=gettext(NO_TARGET_SUPPLIED_MSG)
            )

        # Check agent is exist or not.
        agent_exist = is_agent_exists(pem_conn, agent_id)
        if not agent_exist:
            return make_json_response(
                status=404, success=0,
                errormsg=gettext("The specified source agent not found!")
            )

        source = {
            "type": 'agent',
            "agent_id": agent_id
        }

        status, result = utils.copy_probes(source, targets, True, pem_conn)
        if not status:
            return make_json_response(
                status=404, success=0,
                errormsg=result
            )

        return success_return(
            gettext(COPY_PROBE_CONFIGURE_SUCCESS_MSG)
        )


class ServerCopyApiView(ApiView):
    """
    API to expose the copy of the probes at server level.
    """
    endpoint = 'server_copy_probe'
    url = '/probe/copy/server/<int:server_id>'
    methods = ['POST']
    pk = None

    def post(self, server_id, pem_conn=None):
        """
        This function is used to copy probe configuration for
        the specified server to the specified targets.

        :param server_id: Server Id for which probe configuration
        will be copied
        :param pem_conn: PEM Connection Object
        :return: JSON response
        """
        targets = request.get_json()

        # If targets is not supplied then return 404.
        if targets is None or len(targets) <= 0:
            return make_json_response(
                status=404, success=0,
                errormsg=gettext(NO_TARGET_SUPPLIED_MSG)
            )

        # Check the given object is exist or not.
        object_exist, msg = is_object_exists(pem_conn, 'server', server_id)
        if not object_exist:
            return make_json_response(
                status=404, success=0,
                errormsg=gettext("The specified source server not found!")
            )

        source = {
            "type": 'server',
            "server_id": server_id
        }

        status, result = utils.copy_probes(source, targets, True, pem_conn)
        if not status:
            return make_json_response(
                status=404, success=0,
                errormsg=result
            )

        return success_return(
            gettext(COPY_PROBE_CONFIGURE_SUCCESS_MSG)
        )


class DatabaseCopyApiView(ApiView):
    """
    API to expose the copy of the probes at database level.
    """

    endpoint = 'database_copy_probe'
    url = '/probe/copy/server/<int:server_id>/database/' \
          '<string:database_name>'
    methods = ['POST']
    pk = None

    def post(self, server_id, database_name, pem_conn=None):
        """
        This function is used to copy probe configuration for
        the specified database to the specified targets.

        :param server_id: Server Id
        :param database_name: Database Name for which probe configuration
                will be copied.
        :param pem_conn: PEM Connection Object
        :return: JSON response
        """
        targets = request.get_json()

        # If targets is not supplied then return 404.
        if targets is None or len(targets) <= 0:
            return make_json_response(
                status=404, success=0,
                errormsg=gettext(
                    NO_TARGET_SUPPLIED_MSG
                )
            )

        # Check the given object is exist or not.
        object_exist, msg = is_object_exists(
            pem_conn, 'database', server_id, database_name
        )
        if not object_exist:
            return make_json_response(
                status=404, success=0,
                errormsg=gettext(
                    "The specified source server or database not found!"
                )
            )

        source = {
            "type": 'database',
            "server_id": server_id,
            "database_name": database_name
        }

        status, result = utils.copy_probes(source, targets, True, pem_conn)
        if not status:
            return make_json_response(
                status=404, success=0,
                errormsg=result
            )

        return success_return(
            gettext(COPY_PROBE_CONFIGURE_SUCCESS_MSG)
        )


class SchemaCopyApiView(ApiView):
    """
    API to expose the copy of the probes at schema level.
    """

    endpoint = 'schema_copy_probe'
    url = '/probe/copy/server/<int:server_id>/database/' \
          '<string:database_name>/schema/<string:schema_name>'
    methods = ['POST']
    pk = None

    def post(self, server_id, database_name, schema_name, pem_conn=None):
        """
        This function is used to copy probe configuration for
        the specified schema to the specified targets.

        :param server_id: Server Id
        :param database_name: Database Name
        :param schema_name: Schema Name for which probe configuration
                will be copied.
        :param pem_conn: PEM Connection Object
        :return: JSON response
        """
        targets = request.get_json()

        # If targets is not supplied then return 404.
        if targets is None or len(targets) <= 0:
            return make_json_response(
                status=404, success=0,
                errormsg=gettext(NO_TARGET_SUPPLIED_MSG)
            )

        # Check the given object is exist or not.
        object_exist, msg = is_object_exists(pem_conn, 'schema', server_id,
                                             database_name, schema_name)
        if not object_exist:
            return make_json_response(
                status=404, success=0,
                errormsg=gettext(
                    "The specified source server or database or schema "
                    "not found!"
                )
            )

        source = {
            "type": 'schema',
            "server_id": server_id,
            "database_name": database_name,
            "schema_name": schema_name
        }

        status, result = utils.copy_probes(source, targets, True, pem_conn)
        if not status:
            return make_json_response(
                status=404, success=0,
                errormsg=result
            )

        return success_return(gettext(
            COPY_PROBE_CONFIGURE_SUCCESS_MSG
        ))
