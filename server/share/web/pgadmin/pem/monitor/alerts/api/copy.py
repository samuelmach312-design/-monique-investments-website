##########################################################################
#
# Postgres Enterprise Manager
#
# Copyright (C) 2016 - 2025, EnterpriseDB Corporation. All rights reserved.
#
##########################################################################

"""Alert Copy API"""

from flask import request
from flask_babel import gettext

from pgadmin.pem.api.utils import ApiView
from pgadmin.pem.monitor.alerts import utils
from pgadmin.pem.utils import is_object_exists, is_agent_exists_and_active, \
    validate_and_fetch_existing_alert_options
from pgadmin.utils.ajax import make_json_response, success_return
import re


class AgentCopyApiView(ApiView):
    """
    API to expose the copy of the alerts at agent level.
    """

    endpoint = 'agent_copy_alert'
    url = '/alert/copy/agent/<int:agent_id>'
    methods = ['POST']
    pk = None

    def post(self, agent_id, pem_conn=None):
        """
        This function is used to copy alert configuration for
        the specified agent to the specified targets.

        :param agent_id: Agent Id for which alert configuration
                         will be copied.
        :param pem_conn: PEM Connection Object

        Input parameters should be as below. Here 'existing_alert_options'
        is required to confirm that user want to Ignore/overwrite existing
        alerts or delete existing alerts.
        Supported values are:-
        I -> Ignore Duplicates
        R -> Replace Duplicates
        D -> Delete Existing Alerts
        By default value is 'I'.

        [
          {
            "type": "agent",
            "agent_id": "3",
            "existing_alert_options": 'I'
          }
        ]

        :return:

        Below is the expected result.

        status: 200 OK
        {
          "success":1,
          "info":"Copy alert configuration successfully.",
          "result":null,
          "errormsg":"",
          "data":null
        }

        """
        targets = request.get_json()

        # If targets is not supplied then return 404.
        if targets is None or len(targets) <= 0:
            return make_json_response(
                status=404, success=0,
                errormsg=gettext(
                    "No target supplied to copy alert configuration."
                )
            )

        # Check agent is exist or not.
        agent_exist = is_agent_exists_and_active(pem_conn, agent_id)
        if not agent_exist:
            return make_json_response(
                status=404, success=0,
                errormsg=gettext(
                    "The specified source agent not found or not active!")
            )

        source = {
            "type": 'agent',
            "agent_id": agent_id
        }

        # Ignore/Replace/Delete the existing alerts
        is_option_valid, existing_alert_options = \
            validate_and_fetch_existing_alert_options(targets)
        if not is_option_valid:
            return make_json_response(
                status=404, success=0,
                errormsg=gettext(
                    "Valid values for parameter existing_alert_options "
                    "are I, R, D"
                )
            )

        status, result = utils.copy_alerts(source, targets,
                                           existing_alert_options, pem_conn)
        if not status:
            return make_json_response(
                status=404, success=0,
                errormsg=result
            )

        return success_return(gettext(
            "Copy alert configuration successfully."
        ))


class ServerCopyApiView(ApiView):
    """
    API to expose the copy of the alerts at server level.
    """
    endpoint = 'server_copy_alert'
    url = '/alert/copy/server/<int:server_id>'
    methods = ['POST']
    pk = None

    def post(self, server_id, pem_conn=None):
        """
        This function is used to copy alert configuration for
        the specified server to the specified targets.

        :param server_id: Server Id for which alert
                          configuration will be copied
        :param pem_conn: PEM Connection Object

        Input parameters should be as below. Here 'existing_alert_options'
        is required to confirm that user want to Ignore/overwrite existing
        alerts or delete existing alerts.
        Supported values are:-
        I -> Ignore Duplicates
        R -> Replace Duplicates
        D -> Delete Existing Alerts
        By default value is 'I'.

        [
          {
            "type": "agent",
            "agent_id": "3",
            "existing_alert_options": 'I'
          }
        ]

        :return:

        Below is the expected result.

        status: 200 OK
        {
          "success":1,
          "info":"Copy alert configuration successfully.",
          "result":null,
          "errormsg":"",
          "data":null
        }

        """
        targets = request.get_json()

        # If targets is not supplied then return 404.
        if targets is None or len(targets) <= 0:
            return make_json_response(
                status=404, success=0,
                errormsg=gettext(
                    "No target supplied to copy alert configuration."
                )
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

        # Ignore/Replace/Delete the existing alerts
        is_option_valid, existing_alert_options = \
            validate_and_fetch_existing_alert_options(targets)
        if not is_option_valid:
            return make_json_response(
                status=404, success=0,
                errormsg=gettext(
                    "Valid values for parameter existing_alert_options "
                    "are I, R, D"
                )
            )
        status, result = utils.copy_alerts(source, targets,
                                           existing_alert_options, pem_conn)
        if not status:
            return make_json_response(
                status=404, success=0,
                errormsg=result
            )

        return success_return(
            gettext("Copy alert configuration successfully.")
        )


class DatabaseCopyApiView(ApiView):
    """
    API to expose the copy of the alerts at database level.
    """

    endpoint = 'database_copy_alert'
    url = '/alert/copy/server/<int:server_id>/database/<string:database_name>'
    methods = ['POST']
    pk = None

    def post(self, server_id, database_name, pem_conn=None):
        """
        This function is used to copy alert configuration for
        the specified database to the specified targets.

        :param server_id: Server Id
        :param database_name: Database Name for which alert configuration
                will be copied.
        :param pem_conn: PEM Connection Object

        Input parameters should be as below. Here 'existing_alert_options'
        is required to confirm that user want to Ignore/overwrite existing
        alerts or delete existing alerts.
        Supported values are:-
        I -> Ignore Duplicates
        R -> Replace Duplicates
        D -> Delete Existing Alerts
        By default value is 'I'.

        [
          {
            "type": "agent",
            "agent_id": "3",
            "existing_alert_options": 'I'
          }
        ]

        :return:

        Below is the expected result.

        status: 200 OK
        {
          "success":1,
          "info":"Copy alert configuration successfully.",
          "result":null,
          "errormsg":"",
          "data":null
        }

        """
        targets = request.get_json()

        # If targets is not supplied then return 404.
        if targets is None or len(targets) <= 0:
            return make_json_response(
                status=404, success=0,
                errormsg=gettext(
                    "No target supplied to copy alert configuration."
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

        # Ignore/Replace/Delete the existing alerts
        is_option_valid, existing_alert_options = \
            validate_and_fetch_existing_alert_options(targets)
        if not is_option_valid:
            return make_json_response(
                status=404, success=0,
                errormsg=gettext(
                    "Valid values for parameter existing_alert_options "
                    "are I, R, D"
                )
            )

        status, result = utils.copy_alerts(source, targets,
                                           existing_alert_options, pem_conn)
        if not status:
            return make_json_response(
                status=404, success=0,
                errormsg=result
            )

        return success_return(
            gettext("Copy alert configuration successfully.")
        )


class SchemaCopyApiView(ApiView):
    """
    API to expose the copy of the alerts at schema level.
    """

    endpoint = 'schema_copy_alert'
    url = '/alert/copy/server/<int:server_id>/' \
          'database/<string:database_name>/' \
          'schema/<string:schema_name>'
    methods = ['POST']
    pk = None

    def post(self, server_id, database_name, schema_name, pem_conn=None):
        """
        This function is used to copy alert configuration for
        the specified schema to the specified targets.

        :param server_id: Server Id
        :param database_name: Database Name
        :param schema_name: Schema Name for which alert configuration
                will be copied.
        :param pem_conn: PEM Connection Object

        Input parameters should be as below. Here 'existing_alert_options'
        is required to confirm that user want to overwrite existing alerts
        or not.

        [
          {
            "type": "agent",
            "agent_id": "3",
            "existing_alert_options": true
          }
        ]

        :return:

        Below is the expected result.

        status: 200 OK
        {
          "success":1,
          "info":"Copy alert configuration successfully.",
          "result":null,
          "errormsg":"",
          "data":null
        }

        """
        targets = request.get_json()

        # If targets is not supplied then return 404.
        if targets is None or len(targets) <= 0:
            return make_json_response(
                status=404, success=0,
                errormsg=gettext(
                    "No target supplied to copy alert configuration."
                )
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

        # Ignore/Replace/Delete the existing alerts
        is_option_valid, existing_alert_options = \
            validate_and_fetch_existing_alert_options(targets)
        if not is_option_valid:
            return make_json_response(
                status=404, success=0,
                errormsg=gettext(
                    "Valid values for parameter existing_alert_options "
                    "are I, R, D"
                )
            )

        status, result = utils.copy_alerts(source, targets,
                                           existing_alert_options, pem_conn)
        if not status:
            return make_json_response(
                status=404, success=0,
                errormsg=result
            )

        return success_return(
            gettext("Copy alert configuration successfully.")
        )


class TableCopyApiView(ApiView):
    """
    API to expose the copy of the alerts at table level.
    """

    endpoint = 'table_copy_alert'
    url = '/alert/copy/server/<int:server_id>/' \
          'database/<string:database_name>/' \
          'schema/<string:schema_name>/table/<string:object_name>'
    methods = ['POST']
    pk = None

    def post(self, server_id, database_name, schema_name, object_name,
             pem_conn=None):
        """
        This function is used to copy alert configuration for
        the specified table to the specified targets.

        :param server_id: Server Id
        :param database_name: Database Name
        :param schema_name: Schema Name for which alert configuration
                will be copied.
        :param object_name: table Name for which alert configuration
                will be copied.
        :param pem_conn: PEM Connection Object

        Input parameters should be as below. Here 'existing_alert_options'
        is required to confirm that user want to Ignore/overwrite existing
        alerts or delete existing alerts.
        Supported values are:-
        I -> Ignore Duplicates
        R -> Replace Duplicates
        D -> Delete Existing Alerts
        By default value is 'I'.

        [
          {
            "type": "agent",
            "agent_id": "3",
            "existing_alert_options": 'I'
          }
        ]

        :return:

        Below is the expected result.

        status: 200 OK
        {
          "success":1,
          "info":"Copy alert configuration successfully.",
          "result":null,
          "errormsg":"",
          "data":null
        }

        """
        targets = request.get_json()

        # defining object_name for target
        for target in targets:
            target['object_name'] = target['table_name']

        # If targets is not supplied then return 404.
        if targets is None or len(targets) <= 0:
            return make_json_response(
                status=404, success=0,
                errormsg=gettext(
                    "No target supplied to copy alert configuration."
                )
            )

        # Check the given object is exist or not.
        object_exist, msg = is_object_exists(pem_conn, 'table', server_id,
                                             database_name, schema_name,
                                             object_name)
        if not object_exist:
            return make_json_response(
                status=404, success=0,
                errormsg=gettext(
                    "The specified source server or database "
                    "or schema or table not found!"
                )
            )

        source = {
            "type": 'table',
            "server_id": server_id,
            "database_name": database_name,
            "schema_name": schema_name,
            "object_name": object_name
        }

        # Ignore/Replace/Delete the existing alerts
        is_option_valid, existing_alert_options = \
            validate_and_fetch_existing_alert_options(targets)
        if not is_option_valid:
            return make_json_response(
                status=404, success=0,
                errormsg=gettext(
                    "Valid values for parameter existing_alert_options "
                    "are I, R, D"
                )
            )

        status, result = utils.copy_alerts(source, targets,
                                           existing_alert_options, pem_conn)
        if not status:
            return make_json_response(
                status=404, success=0,
                errormsg=result
            )

        return success_return(
            gettext("Copy alert configuration successfully.")
        )


class IndexCopyApiView(ApiView):
    """
    API to expose the copy of the alerts at index level.
    """

    endpoint = 'index_copy_alert'
    url = '/alert/copy/server/<int:server_id>/' \
          'database/<string:database_name>/' \
          'schema/<string:schema_name>/index/<string:object_name>'
    methods = ['POST']
    pk = None

    def post(self, server_id, database_name, schema_name, object_name,
             pem_conn=None):
        """
        This function is used to copy alert configuration for
        the specified table to the specified targets.

        :param server_id: Server Id
        :param database_name: Database Name
        :param schema_name: Schema Name for which alert configuration
                will be copied.
        :param object_name: index Name for which alert configuration
                will be copied.
        :param pem_conn: PEM Connection Object

        Input parameters should be as below. Here 'existing_alert_options'
        is required to confirm that user want to Ignore/overwrite existing
        alerts or delete existing alerts.
        Supported values are:-
        I -> Ignore Duplicates
        R -> Replace Duplicates
        D -> Delete Existing Alerts
        By default value is 'I'.

        [
          {
            "type": "agent",
            "agent_id": "3",
            "existing_alert_options": 'I'
          }
        ]

        :return:

        Below is the expected result.

        status: 200 OK
        {
          "success":1,
          "info":"Copy alert configuration successfully.",
          "result":null,
          "errormsg":"",
          "data":null
        }

        """
        targets = request.get_json()

        # defining object_name for target
        for target in targets:
            target['object_name'] = target['index_name']

        # If targets is not supplied then return 404.
        if targets is None or len(targets) <= 0:
            return make_json_response(
                status=404, success=0,
                errormsg=gettext(
                    "No target supplied to copy alert configuration."
                )
            )

        # Check the given object is exist or not.
        object_exist, msg = is_object_exists(pem_conn, 'index', server_id,
                                             database_name, schema_name,
                                             object_name)
        if not object_exist:
            return make_json_response(
                status=404, success=0,
                errormsg=gettext(
                    "The specified source server or database "
                    "or schema or table not found!"
                )
            )

        source = {
            "type": 'index',
            "server_id": server_id,
            "database_name": database_name,
            "schema_name": schema_name,
            "object_name": object_name
        }

        # Ignore/Replace/Delete the existing alerts
        is_option_valid, existing_alert_options = \
            validate_and_fetch_existing_alert_options(targets)
        if not is_option_valid:
            return make_json_response(
                status=404, success=0,
                errormsg=gettext(
                    "Valid values for parameter existing_alert_options "
                    "are I, R, D"
                )
            )

        status, result = utils.copy_alerts(source, targets,
                                           existing_alert_options, pem_conn)
        if not status:
            return make_json_response(
                status=404, success=0,
                errormsg=result
            )

        return success_return(
            gettext("Copy alert configuration successfully.")
        )


class SequenceCopyApiView(ApiView):
    """
    API to expose the copy of the alerts at sequence level.
    """

    endpoint = 'sequence_copy_alert'
    url = '/alert/copy/server/<int:server_id>/' \
          'database/<string:database_name>/' \
          'schema/<string:schema_name>/sequence/<string:object_name>'
    methods = ['POST']
    pk = None

    def post(self, server_id, database_name, schema_name, object_name,
             pem_conn=None):
        """
        This function is used to copy alert configuration for
        the specified table to the specified targets.

        :param server_id: Server Id
        :param database_name: Database Name
        :param schema_name: Schema Name for which alert configuration
                will be copied.
        :param object_name: sequence Name for which alert configuration
                will be copied.
        :param pem_conn: PEM Connection Object

        Input parameters should be as below. Here 'existing_alert_options' is
        required to confirm that user want to overwrite existing
        alerts or not.

        [
          {
            "type": "agent",
            "agent_id": "3",
            "existing_alert_options": true
          }
        ]

        :return:

        Below is the expected result.

        status: 200 OK
        {
          "success":1,
          "info":"Copy alert configuration successfully.",
          "result":null,
          "errormsg":"",
          "data":null
        }

        """
        targets = request.get_json()

        # defining object_name for target
        for target in targets:
            target['object_name'] = target['sequence_name']

        # If targets is not supplied then return 404.
        if targets is None or len(targets) <= 0:
            return make_json_response(
                status=404, success=0,
                errormsg=gettext(
                    "No target supplied to copy alert configuration."
                )
            )

        # Check the given object is exist or not.
        object_exist, msg = is_object_exists(pem_conn, 'sequence', server_id,
                                             database_name, schema_name,
                                             object_name)
        if not object_exist:
            return make_json_response(
                status=404, success=0,
                errormsg=gettext(
                    "The specified source server or database "
                    "or schema or table not found!"
                )
            )

        source = {
            "type": 'sequence',
            "server_id": server_id,
            "database_name": database_name,
            "schema_name": schema_name,
            "object_name": object_name
        }

        # Ignore/Replace/Delete the existing alerts
        is_option_valid, existing_alert_options = \
            validate_and_fetch_existing_alert_options(targets)
        if not is_option_valid:
            return make_json_response(
                status=404, success=0,
                errormsg=gettext(
                    "Valid values for parameter existing_alert_options "
                    "are I, R, D"
                )
            )

        status, result = utils.copy_alerts(source, targets,
                                           existing_alert_options, pem_conn)
        if not status:
            return make_json_response(
                status=404, success=0,
                errormsg=result
            )

        return success_return(
            gettext("Copy alert configuration successfully.")
        )


class FunctionCopyApiView(ApiView):
    """
    API to expose the copy of the alerts at function level.
    """

    endpoint = 'function_copy_alert'
    url = '/alert/copy/server/<int:server_id>/' \
          'database/<string:database_name>/' \
          'schema/<string:schema_name>/function/<string:function_name>/' \
          'args/<string:function_arguments>'
    methods = ['POST']
    pk = None

    def post(self, server_id, database_name, schema_name, function_name,
             function_arguments, pem_conn=None):
        """
        This function is used to copy alert configuration for
        the specified table to the specified targets.

        :param server_id: Server Id
        :param database_name: Database Name
        :param schema_name: Schema Name for which alert configuration
                will be copied.
        :param function_name: function Name for which alert configuration
                will be copied.
        :param function_arguments: function args with commas
        :param pem_conn: PEM Connection Object

        Input parameters should be as below. Here 'existing_alert_options'
        is required to confirm that user want to Ignore/overwrite existing
        alerts or delete existing alerts.
        Supported values are:-
        I -> Ignore Duplicates
        R -> Replace Duplicates
        D -> Delete Existing Alerts
        By default value is 'I'.

        [
          {
            "type": "agent",
            "agent_id": "3",
            "existing_alert_options": 'I'
          }
        ]

        :return:

        Below is the expected result.

        status: 200 OK
        {
          "success":1,
          "info":"Copy alert configuration successfully.",
          "result":null,
          "errormsg":"",
          "data":null
        }

        """

        targets = request.get_json()
        # handling if no function arguments provided
        if function_arguments == ' ':
            function_arguments = ''

        # using re for addding space after ',' for comma separated args
        function_arguments = re.sub(r'(?<=[,])(?=[^\s])',
                                    r' ', function_arguments)

        # object_name will be used as a function name with args
        # defining object_name for target
        for target in targets:
            # using re for addding space after ',' for comma separated args
            target['function_arguments'] = \
                re.sub(r'(?<=[,])(?=[^\s])', r' ',
                       target['function_arguments'])
            target['object_name'] = "{}({})".format(
                target['function_name'],
                target['function_arguments'])

        # defining object_name for source
        object_name = "{}({})".format(function_name, function_arguments)

        # If targets is not supplied then return 404.
        if targets is None or len(targets) <= 0:
            return make_json_response(
                status=404, success=0,
                errormsg=gettext(
                    "No target supplied to copy alert configuration."
                )
            )

        # Check the given object is exist or not.
        object_exist, msg = is_object_exists(pem_conn, 'function', server_id,
                                             database_name, schema_name,
                                             object_name,
                                             arguments=function_arguments,
                                             function_name=function_name)

        if not object_exist:
            return make_json_response(
                status=404, success=0,
                errormsg=gettext(
                    "The specified source server or database or "
                    "schema or function not found!"
                )
            )

        source = {
            "type": 'function',
            "server_id": server_id,
            "database_name": database_name,
            "schema_name": schema_name,
            "function_name": function_name,
            "object_name": object_name
        }

        # Ignore/Replace/Delete the existing alerts
        is_option_valid, existing_alert_options = \
            validate_and_fetch_existing_alert_options(targets)
        if not is_option_valid:
            return make_json_response(
                status=404, success=0,
                errormsg=gettext(
                    "Valid values for parameter existing_alert_options "
                    "are I, R, D"
                )
            )

        status, result = utils.copy_alerts(source, targets,
                                           existing_alert_options, pem_conn)
        if not status:
            return make_json_response(
                status=404, success=0,
                errormsg=result
            )

        return success_return(
            gettext("Copy alert configuration successfully.")
        )
