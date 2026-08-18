##########################################################################
#
# Postgres Enterprise Manager
#
# Copyright (C) 2016 - 2025, EnterpriseDB Corporation. All rights reserved.
#
##########################################################################

"""Probe Config API"""

from pgadmin.pem.api.utils import ApiView
from pgadmin.utils.ajax import make_response, make_json_response, \
    internal_server_error, success_return
from pgadmin.pem.monitor.probes import utils
from flask_babel import gettext
from pgadmin.pem.utils import is_agent_exists, is_object_exists
from pgadmin.pem.monitor.utils import DashboardLevel
from flask import request
import re

EMPTY_DATA_MSG = "No data supplied for given probe."
PROBE_CONFIGURE_SUCCESS_MSG = "Configure probe successfully."


def probes_get_response(probe_id, node, res):
    """
    Responsible for probe response

    :param probe_id: Probe ID
    :param node: Node
    :param res: Result
    :return: JSON response
    """
    if not res[0]:
        return internal_server_error(errormsg=res[1])

    data = res[1]['rows']
    if probe_id is not None:
        if len(data) == 0:
            return make_json_response(
                status=404, success=0,
                errormsg=gettext(
                    "The specified probe id is not applicable for the "
                    "specified {0}"
                ).format(node)
            )
        return make_response(data[0])
    return make_response(data)


class AgentConfigApiView(ApiView):
    """
    API to expose the configuration of the probes at agent level.
    """

    endpoint = 'agent_probe_config'
    url = '/probe/config/agent/<int:agent_id>/'
    pk = 'probe_id'
    methods = ['GET', 'PUT']

    def get(self, agent_id, probe_id=None, pem_conn=None):
        """
        This function will return the list of probes for specified
        agent id.

        :param agent_id: Agent Id for which probes will be fetched.
        :param pem_conn: PEM Connection Object
        :param probe_id: Probe Id for which information will be fetched.
        :return: JSON response
        """

        # Check agent is exist or not.
        agent_exist = is_agent_exists(pem_conn, agent_id)
        if not agent_exist:
            return make_json_response(
                status=404, success=0,
                errormsg=gettext("The specified agent not found!")
            )

        return probes_get_response(
            probe_id, 'agent', utils.get_probes(
                DashboardLevel.DB_AGENT, agent_id, pem_conn=pem_conn,
                probe_id=probe_id
            )
        )

    def put(self, agent_id, probe_id, pem_conn=None):
        """
        This function is used to save the probe configuration for
        the specified probe id and target type.

        :param agent_id: Agent Id for which probes data will be configured.
        :param pem_conn: PEM Connection Object
        :param probe_id: Probe Id for which data will be configured.
        :return: JSON response
        """
        data = request.get_json()

        # If data is not supplied then return 404.
        if data is None or len(data) <= 0:
            return make_json_response(
                status=404, success=0,
                errormsg=gettext(EMPTY_DATA_MSG)
            )

        # Check agent is exist or not.
        agent_exist = is_agent_exists(pem_conn, agent_id)
        if not agent_exist:
            return make_json_response(
                status=404, success=0,
                errormsg=gettext("The specified agent not found!")
            )

        # Get the data for the given object or probe id
        status, probes = utils.get_probes(
            DashboardLevel.DB_AGENT, agent_id, pem_conn=pem_conn,
            probe_id=probe_id
        )
        if not status:
            return internal_server_error(errormsg=probes)

        if probe_id is not None and len(probes['rows']) == 0:
            return make_json_response(
                status=404, success=0,
                errormsg=gettext(
                    "The specified probe id is not applicable for "
                    "the specified agent"
                )
            )

        for key, value in list(data.items()):
            saved_data = list()
            saved_data.append(
                {'agent_id': agent_id,
                 'target_type': 'agent',
                 'target_type_id': DashboardLevel.DB_AGENT
                 }
            )

            # Update changed value in probe info dictionary
            probe_info = probes['rows'][0]
            probe_info[key] = value
            saved_data.append(probe_info)

            # Add changed column
            changed_column = dict()
            changed_column[key] = value

            error_msg = utils.check_config_parameters(changed_column)
            if error_msg is not None:
                return make_json_response(
                    status=404, success=0,
                    errormsg=error_msg
                )
            saved_data.append(changed_column)

            status, result = utils.save_probes(saved_data, pem_conn)
            if not status:
                return internal_server_error(errormsg=result)

        return success_return(gettext(PROBE_CONFIGURE_SUCCESS_MSG))


class ServerConfigApiView(ApiView):
    """
    API to expose the configuration of the probes at server level.
    """

    endpoint = 'server_probe_config'
    url = '/probe/config/server/<int:server_id>/'
    pk = 'probe_id'
    methods = ['GET', 'PUT']

    def get(self, server_id, probe_id=None, pem_conn=None):
        """
        This function will return the list of probes for
        specified server .

        :param server_id: Server Id for which probes will be fetched.
        :param probe_id: Probe Id for which information will be fetched.
        :param pem_conn: PEM Connection Object
        :return: JSON response
        """

        # Check the given object is exist or not.
        object_exist, msg = is_object_exists(pem_conn, 'server', server_id)
        if not object_exist:
            return make_json_response(
                status=404, success=0, errormsg=msg
            )

        return probes_get_response(
            probe_id, 'server', utils.get_probes(
                DashboardLevel.DB_SERVER, server_id, pem_conn=pem_conn,
                probe_id=probe_id
            )
        )

    def put(self, server_id, probe_id, pem_conn=None):
        """
        This function is used to save the probe configuration for
        the specified probe id and target type.

        :param server_id: Server Id for which probes data will be configured.
        :param pem_conn: PEM Connection Object
        :param probe_id: Probe Id for which data will be configured.
        :return: JSON response
        """
        data = request.get_json()

        # If data is not supplied then return 404.
        if data is None or len(data) <= 0:
            return make_json_response(
                status=404, success=0,
                errormsg=gettext(EMPTY_DATA_MSG)
            )

        # Check the given object is exist or not.
        object_exist, msg = is_object_exists(pem_conn, 'server', server_id)
        if not object_exist:
            return make_json_response(
                status=404, success=0, errormsg=msg
            )

        # Get the data for the given object or probe id
        status, probes = utils.get_probes(
            DashboardLevel.DB_SERVER, server_id, pem_conn=pem_conn,
            probe_id=probe_id
        )
        if not status:
            return internal_server_error(errormsg=probes)

        if probe_id is not None and len(probes['rows']) == 0:
            return make_json_response(
                status=404, success=0,
                errormsg=gettext(
                    "The specified probe id is not applicable for "
                    "the specified server"
                )
            )

        for key, value in list(data.items()):
            saved_data = list()
            saved_data.append(
                {'server_id': server_id,
                 'target_type': 'server',
                 'target_type_id': DashboardLevel.DB_SERVER
                 }
            )

            # Update changed value in probe info dictionary
            probe_info = probes['rows'][0]
            probe_info[key] = value
            saved_data.append(probe_info)

            # Add changed column
            changed_column = dict()
            changed_column[key] = value

            error_msg = utils.check_config_parameters(changed_column)
            if error_msg is not None:
                return make_json_response(
                    status=404, success=0,
                    errormsg=error_msg
                )
            saved_data.append(changed_column)

            status, result = utils.save_probes(saved_data, pem_conn)
            if not status:
                return internal_server_error(errormsg=result)

        return success_return(gettext(PROBE_CONFIGURE_SUCCESS_MSG))


class DatabaseConfigApiView(ApiView):
    """
    API to expose the configuration of the probes at database level.
    """

    endpoint = 'database_probe_config'
    url = '/probe/config/server/<int:server_id>/database/' \
          '<string:database_name>/'
    pk = 'probe_id'
    methods = ['GET', 'PUT']

    def get(self, server_id, database_name,
            probe_id=None, pem_conn=None):
        """
        This function will return the list of probes for
        specified server .

        :param server_id: Server Id
        :param database_name: Database Name for which probes will be fetched.
        :param probe_id: Probe Id for which information will be fetched.
        :param pem_conn: PEM Connection Object
        :return: JSON response
        """

        # Check the given object is exist or not.
        object_exist, msg = is_object_exists(pem_conn, 'database', server_id,
                                             database_name)
        if not object_exist:
            return make_json_response(
                status=404, success=0, errormsg=msg
            )

        return probes_get_response(
            probe_id, 'database', utils.get_probes(
                DashboardLevel.DB_DATABASE, server_id, database_name,
                pem_conn=pem_conn,
                probe_id=probe_id
            )
        )

    def put(self, server_id, database_name,
            probe_id, pem_conn=None):
        """
        This function is used to save the probe configuration for
        the specified probe id and target type.

        :param server_id: Server Id
        :param database_name: Database Name for which data will be configured.
        :param probe_id: Probe Id for which data will be configured.
        :param pem_conn: PEM Connection Object
        :return: JSON response
        """
        data = request.get_json()

        # If data is not supplied then return 404.
        if data is None or len(data) <= 0:
            return make_json_response(
                status=404, success=0,
                errormsg=gettext(EMPTY_DATA_MSG)
            )

        # Check the given object is exist or not.
        object_exist, msg = is_object_exists(pem_conn, 'database', server_id,
                                             database_name)
        if not object_exist:
            return make_json_response(
                status=404, success=0, errormsg=msg
            )

        # Get the data for the given object or probe id
        status, probes = utils.get_probes(
            DashboardLevel.DB_DATABASE, server_id, database_name,
            pem_conn=pem_conn, probe_id=probe_id
        )
        if not status:
            return internal_server_error(errormsg=probes)

        if probe_id is not None and len(probes['rows']) == 0:
            return make_json_response(
                status=404, success=0,
                errormsg=gettext(
                    "The specified probe id is not applicable for "
                    "the specified database"
                )
            )

        if probes['rows'][0]['target_type_id_returned'] != \
                DashboardLevel.DB_DATABASE:
            return make_json_response(
                status=404, success=0,
                errormsg=gettext(
                    "Probe configuration can't be change at database "
                    "level for the specified probe.")
            )

        for key, value in list(data.items()):
            saved_data = list()
            saved_data.append(
                {'server_id': server_id,
                 'database_name': database_name,
                 'target_type': 'database',
                 'target_type_id': DashboardLevel.DB_DATABASE
                 }
            )

            # Update changed value in probe info dictionary
            probe_info = probes['rows'][0]
            probe_info[key] = value
            saved_data.append(probe_info)

            # Add changed column
            changed_column = dict()
            changed_column[key] = value

            error_msg = utils.check_config_parameters(changed_column)
            if error_msg is not None:
                return make_json_response(
                    status=404, success=0,
                    errormsg=error_msg
                )
            saved_data.append(changed_column)

            status, result = utils.save_probes(saved_data, pem_conn)
            if not status:
                return internal_server_error(errormsg=result)

        return success_return(gettext(PROBE_CONFIGURE_SUCCESS_MSG))


class SchemaConfigApiView(ApiView):
    """
    API to expose the configuration of the probes at schema level.
    """

    endpoint = 'schema_probe_config'
    url = '/probe/config/server/<int:server_id>/database/' \
          '<string:database_name>/schema/<string:schema_name>/'
    pk = 'probe_id'
    methods = ['GET', 'PUT']

    def get(self, server_id, database_name,
            schema_name, probe_id=None, pem_conn=None):
        """
        This function will return the list of probes for
        specified server .

        :param server_id: Server Id
        :param database_name: Database Name
        :param schema_name: Schema Name for which probes will be fetched.
        :param probe_id: Probe Id for which information will be fetched.
        :param pem_conn: PEM Connection Object
        :return: JSON response
        """

        # Check the given object is exist or not.
        object_exist, msg = is_object_exists(pem_conn, 'schema', server_id,
                                             database_name, schema_name)
        if not object_exist:
            return make_json_response(
                status=404, success=0, errormsg=msg
            )

        return probes_get_response(
            probe_id, 'schema', utils.get_probes(
                400, server_id, database_name, schema_name,
                pem_conn=pem_conn,
                probe_id=probe_id
            )
        )

    def put(self, server_id, database_name,
            schema_name, probe_id, pem_conn=None):
        """
        This function is used to save the probe configuration for
        the specified probe id and target type.

        :param server_id: Server Id
        :param database_name: Database Name
        :param schema_name: Schema Name for which data will be configured.
        :param probe_id: Probe Id for which data will be configured.
        :param pem_conn: PEM Connection Object
        :return: JSON response
        """
        data = request.get_json()

        # If data is not supplied then return 404.
        if data is None or len(data) <= 0:
            return make_json_response(
                status=404, success=0,
                errormsg=gettext(EMPTY_DATA_MSG)
            )

        # Check the given object is exist or not.
        object_exist, msg = is_object_exists(pem_conn, 'schema', server_id,
                                             database_name, schema_name)
        if not object_exist:
            return make_json_response(
                status=404, success=0, errormsg=msg
            )

        # Get the data for the given object or probe id
        status, probes = utils.get_probes(
            DashboardLevel.DB_SCHEMA, server_id, database_name, schema_name,
            pem_conn=pem_conn,
            probe_id=probe_id
        )
        if not status:
            return internal_server_error(errormsg=probes)

        if probe_id is not None and len(probes['rows']) == 0:
            return make_json_response(
                status=404, success=0,
                errormsg=gettext(
                    "The specified probe id is not applicable for "
                    "the specified schema")
            )

        if probes['rows'][0]['target_type_id_returned'] != \
                DashboardLevel.DB_SCHEMA:
            return make_json_response(
                status=404, success=0,
                errormsg=gettext(
                    "Probe configuration can't be change at schema "
                    "level for the specified probe."
                )
            )

        for key, value in list(data.items()):
            saved_data = list()
            saved_data.append(
                {'server_id': server_id,
                 'database_name': database_name,
                 'schema_name': schema_name,
                 'target_type': 'schema',
                 'target_type_id': DashboardLevel.DB_SCHEMA
                 }
            )

            # Update changed value in probe info dictionary
            probe_info = probes['rows'][0]
            probe_info[key] = value
            saved_data.append(probe_info)

            # Add changed column
            changed_column = dict()
            changed_column[key] = value

            error_msg = utils.check_config_parameters(changed_column)
            if error_msg is not None:
                return make_json_response(
                    status=404, success=0,
                    errormsg=error_msg
                )
            saved_data.append(changed_column)

            status, result = utils.save_probes(saved_data, pem_conn)
            if not status:
                return internal_server_error(errormsg=result)

        return success_return(gettext(PROBE_CONFIGURE_SUCCESS_MSG))


class TableConfigApiView(ApiView):
    """
    API to expose the configuration of the probes at table level.
    """

    endpoint = 'table_probe_config'
    url = '/probe/config/server/<int:server_id>/database/' \
          '<string:database_name>/schema/<string:schema_name>/table/' \
          '<string:table_name>/'
    pk = 'probe_id'
    methods = ['GET']

    def get(
        self, server_id, database_name, schema_name, table_name,
            probe_id=None, pem_conn=None
    ):
        """
        This function will return the list of probes for
        specified server .

        :param server_id: Server Id
        :param database_name: Database Name
        :param schema_name: Schema Name
        :param table_name: Table Name for which probes will be fetched.
        :param probe_id: Probe Id for which information will be fetched.
        :param pem_conn: PEM Connection Object
        :return: JSON response
        """

        # Check the given object is exist or not.
        object_exist, msg = is_object_exists(pem_conn, 'table', server_id,
                                             database_name, schema_name,
                                             table_name)
        if not object_exist:
            return make_json_response(
                status=404, success=0, errormsg=msg
            )

        return probes_get_response(
            probe_id, 'table', utils.get_probes(
                DashboardLevel.DB_TABLE, server_id,
                database_name, schema_name, table_name,
                pem_conn=pem_conn, probe_id=probe_id
            )
        )


class IndexConfigApiView(ApiView):
    """
    API to expose the configuration of the probes at index level.
    """

    endpoint = 'index_probe_config'
    url = '/probe/config/server/<int:server_id>/database/' \
          '<string:database_name>/schema/<string:schema_name>/index/' \
          '<string:index_name>/'
    pk = 'probe_id'
    methods = ['GET']

    def get(self, server_id, database_name, schema_name,
            index_name, probe_id=None, pem_conn=None):
        """
        This function will return the list of probes for
        specified server .

        :param server_id: Server Id
        :param database_name: Database Name
        :param schema_name: Schema Name
        :param index_name: Index Name for which probes will be fetched.
        :param probe_id: Probe Id for which information will be fetched.
        :param pem_conn: PEM Connection Object
        :return: JSON response
        """

        # Check the given object is exist or not.
        object_exist, msg = is_object_exists(pem_conn, 'index', server_id,
                                             database_name, schema_name,
                                             index_name)
        if not object_exist:
            return make_json_response(
                status=404, success=0, errormsg=msg
            )

        return probes_get_response(
            probe_id, 'index', utils.get_probes(
                DashboardLevel.DB_INDEX, server_id, database_name,
                schema_name, index_name, pem_conn=pem_conn, probe_id=probe_id
            )
        )


class SequenceConfigApiView(ApiView):
    """
    API to expose the configuration of the probes at sequence level.
    """

    endpoint = 'sequence_probe_config'

    url = '/probe/config/server/<int:server_id>/database/' \
          '<string:database_name>/schema/<string:schema_name>/sequence/' \
          '<string:sequence_name>/'
    pk = 'probe_id'
    methods = ['GET']

    def get(self, server_id, database_name, schema_name,
            sequence_name, probe_id=None, pem_conn=None):
        """
        This function will return the list of probes for
        specified server .

        :param server_id: Server Id
        :param database_name: Database Name
        :param schema_name: Schema Name
        :param sequence_name: Sequence Name for which probes will be fetched.
        :param probe_id: Probe Id for which information will be fetched.
        :param pem_conn: PEM Connection Object
        :return: JSON response
        """

        # Check the given object is exist or not.
        object_exist, msg = is_object_exists(pem_conn, 'sequence', server_id,
                                             database_name, schema_name,
                                             sequence_name)
        if not object_exist:
            return make_json_response(
                status=404, success=0, errormsg=msg
            )

        return probes_get_response(
            probe_id, 'sequence', utils.get_probes(
                DashboardLevel.DB_SEQUENCE, server_id, database_name,
                schema_name, sequence_name, pem_conn=pem_conn,
                probe_id=probe_id
            )
        )


class FunctionConfigApiView(ApiView):
    """
    API to expose the configuration of the probes at function level.
    """

    endpoint = 'function_probe_config'

    url = '/probe/config/server/<int:server_id>/database/' \
          '<string:database_name>/schema/<string:schema_name>/function/' \
          '<string:function_name>/'
    pk = 'probe_id'
    methods = ['GET']

    def get(self, server_id, database_name, schema_name,
            function_name, probe_id=None, pem_conn=None):
        """
        This function will return the list of probes for
        specified server .

        :param server_id: Server Id
        :param database_name: Database Name
        :param schema_name: Schema Name
        :param function_name: Function Name for which probes will be fetched.
        :param probe_id: Probe Id for which information will be fetched.
        :param pem_conn: PEM Connection Object
        :return: JSON response
        """

        # Check the given object is exist or not.
        object_exist, msg = is_object_exists(pem_conn, 'function', server_id,
                                             database_name, schema_name,
                                             function_name)
        if not object_exist:
            return make_json_response(
                status=404, success=0, errormsg=msg
            )

        return probes_get_response(
            probe_id, 'function', utils.get_probes(
                DashboardLevel.DB_FUNCTION, server_id, database_name,
                schema_name, function_name, pem_conn=pem_conn,
                probe_id=probe_id
            )
        )


class ViewConfigApiView(ApiView):
    """
    API to expose the configuration of the probes at view level.
    """

    endpoint = 'view_probe_config'

    url = '/probe/config/server/<int:server_id>/database/' \
          '<string:database_name>/schema/<string:schema_name>/view/' \
          '<string:view_name>/'
    pk = 'probe_id'
    methods = ['GET']

    def get(self, server_id, database_name, schema_name,
            view_name, probe_id=None, pem_conn=None):
        """
        This function will return the list of probes for
        specified server .

        :param server_id: Server Id
        :param database_name: Database Name
        :param schema_name: Schema Name
        :param view_name: View Name for which probes will be fetched.
        :param probe_id: Probe Id for which information will be fetched.
        :param pem_conn: PEM Connection Object
        :return: JSON response
        """

        # Check the given object is exist or not.
        object_exist, msg = is_object_exists(pem_conn, 'view', server_id,
                                             database_name, schema_name,
                                             view_name)
        if not object_exist:
            return make_json_response(
                status=404, success=0, errormsg=msg
            )

        return probes_get_response(
            probe_id, 'view', utils.get_probes(
                DashboardLevel.DB_VIEW, server_id, database_name, schema_name,
                view_name, pem_conn=pem_conn, probe_id=probe_id
            )
        )
