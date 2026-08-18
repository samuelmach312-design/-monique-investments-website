##########################################################################
#
# Postgres Enterprise Manager
#
# Copyright (C) 2016 - 2025, EnterpriseDB Corporation. All rights reserved.
#
##########################################################################

"""Implements Probes Data API"""

from abc import abstractmethod, abstractproperty
import six
import re

from flask_babel import gettext
from flask import render_template

from pgadmin.pem.api.utils import ApiView
from pgadmin.pem.monitor.utils import DashboardLevel
from pgadmin.pem.utils import is_agent_exists, is_object_exists
from pgadmin.utils.ajax import make_response, bad_request, not_found, \
    internal_server_error


iso8601_format = re.compile(
    r'^\d{4}-\d{1,2}-\d{1,2}'
    r'[ T]\d{1,2}:\d{1,2}:\d{1,2}(\.\d{0,6}){0,1}'
    r'([+-]\d{1,2}:\d{1,2}){0,1}[Z]{0,1}$'
)

URL_SUFFIX = \
    'from/<string:from_datetime>/to/<string:to_datetime>/<int:probe_id>'


class ProbeDataAPIView(ApiView):
    """
    Abstract class for API routes for the probe data
    """
    pk = None
    data_table = 'pemdata'
    methods = ['GET']

    @abstractproperty
    def level(self):
        """
        Abstract property
        :return: None
        """
        pass

    @abstractmethod
    def validate(self, conn, **kwargs):
        """
        Abstract method
        :return: None
        """
        pass

    def get(self, **kwargs):
        """
        Responsible for listing probes

        Args:
            kwargs: Key/Value arguments

        Returns:
            JSON response
        """
        global iso8601_format

        # We do not need to pass the pem_conn to the wrapped functions
        conn = kwargs.pop('pem_conn')
        if not conn.connected():
            conn.connect()

        # If DB not connected then return error to browser
        if not conn.connected():
            return internal_server_error(
                gettext("Connection to the PEM server has been lost.")
            )

        # Set the template path for sql scripts
        res = self.validate(conn, **kwargs)

        if res is not None:
            return res

        if 'from_datetime' in kwargs and kwargs['from_datetime'] is not None\
                and iso8601_format.match(kwargs['from_datetime']) is None:
            return bad_request(
                gettext(
                    "Invalid date format.Date, format should "
                    "be %Y-%m-%dT%H:%M:%S%z"
                )
            )

        if 'to_datetime' in kwargs and kwargs['to_datetime'] is not None\
                and iso8601_format.match(kwargs['to_datetime']) is None:
            return bad_request(
                gettext(
                    "Invalid date format.Date, format should "
                    "be %Y-%m-%dT%H:%M:%S%z"
                )
            )

        status, res = conn.execute_dict(
            render_template(
                "/".join(['probes/sql/info.sql']),
                probe_id=kwargs['probe_id']
            )
        )

        if not status:
            return internal_server_error(res)

        if len(res['rows']) == 0:
            return not_found(gettext('Specified probe not found.'))

        if res['rows'][0]['deleted']:
            return not_found(
                gettext('Specified probe is no longer available.')
            )

        if (res['rows'][0]['applies_to_id'] < self.level) or (
            self.level == 100 and res['rows'][0]['applies_to_id'] >= 200
        ):
            return bad_request(
                gettext("Probe is not applicable to the specified resource.")
            )

        kwargs['conn'] = conn
        kwargs['level'] = self.level
        kwargs['pem_schema'] = self.data_table
        kwargs['probe_table'] = res['rows'][0]['internal_name']
        if 'arguments' in kwargs:
            kwargs['arguments'] = f'{{{kwargs["arguments"]}}}'

        status, res = conn.execute_dict(
            render_template('probes/sql/data.sql', **kwargs)
        )

        if not status:
            return internal_server_error(res)

        return make_response(res['rows'])


class AgentProbeDataView(ProbeDataAPIView):
    """
    API routes for accessing the probe data for agent.
    """
    endpoint = 'agent_probes_data'
    url = '/probe/data/agent/<int:agent_id>/<int:probe_id>'

    @property
    def level(self):
        """
        Agent property
        :return: Dashboard Level
        """
        return DashboardLevel.DB_AGENT

    def validate(self, conn, **kwargs):
        """
        Validates the request

        Args:
            conn: PEM connection object
            kwargs: Key/Value arguments

        Returns:
            None (on success)
            Response object (if any error)
        """
        status = is_agent_exists(conn, kwargs['agent_id'])
        if not status:
            return not_found(gettext("Specified agent not found"))

        return None


class AgentProbeHistoryView(AgentProbeDataView):
    """
    API routes for accessing the probe data for agent.
    """
    endpoint = 'agent_probes_history'
    url = '/probe/history/agent/<int:agent_id>/from/<string:from_datetime>/' \
          'to/<string:to_datetime>/<int:probe_id>'


class MetaClass(type):
    """Meta class implementation for probes"""
    @property
    def url(self):
        """Class property"""
        return '/probe/{0}/{1}/{2}'.format(
            self.api_type, '/'.join([
                '{0}/<{1}:{2}>'.format(tup[0], tup[1], tup[2])
                for tup in self.object_params
            ]), self.url_suffix
        )

    @property
    def endpoint(self):
        """Class property"""
        return '{0}_probe_{1}'.format(self.object_level, self.api_type)


@six.add_metaclass(MetaClass)
class DatabaseObjectView(ProbeDataAPIView):
    """
    Base class for database object API view routes
    """
    api_type = 'data'
    url_suffix = '<int:probe_id>'

    def validate(self, conn, **kwargs):
        """
        Validates the request data

        Args:
            conn: PEM connection object
            kwargs: Key/Value arguments

        Returns:
            None (on success)
            Response object (if any error)
        """
        params = {
            tup[2]: kwargs[tup[2]] for tup in self.object_params
        }

        status, res = is_object_exists(conn, self.object_level, **params)

        if not status:
            return not_found(res)

        return None


class ServerProbeDataView(DatabaseObjectView):
    """
    API routes for accessing the probe data for server.
    """
    level = DashboardLevel.DB_SERVER
    object_level = 'server'
    object_params = [
        ('server', 'int', 'server_id')
    ]


class ServerProbeHistoryView(ServerProbeDataView):
    """
    API routes for accessing the probe history data for server.
    """
    api_type = 'history'
    url_suffix = URL_SUFFIX


class DatabaseProbeDataView(DatabaseObjectView):
    """
    API routes for accessing the probe data for database.
    """
    level = DashboardLevel.DB_DATABASE
    object_level = 'database'
    object_params = [
        ('server', 'int', 'server_id'),
        ('database', 'string', 'database_name')
    ]


class DatabaseProbeHistoryView(DatabaseProbeDataView):
    """
    API routes for accessing the probe history data for database.
    """
    api_type = 'history'
    url_suffix = URL_SUFFIX


class SchemaProbeDataView(DatabaseObjectView):
    """
    API routes for accessing the probe data for schema.
    """
    level = DashboardLevel.DB_SCHEMA
    object_level = 'schema'
    object_params = [
        ('server', 'int', 'server_id'),
        ('database', 'string', 'database_name'),
        ('schema', 'string', 'schema_name')
    ]


class SchemaProbeHistoryView(SchemaProbeDataView):
    """
    API routes for accessing the probe history data for schema.
    """
    api_type = 'history'
    url_suffix = URL_SUFFIX


class TableProbeDataView(DatabaseObjectView):
    """
    API routes for accessing the probe data for table.
    """
    level = DashboardLevel.DB_TABLE
    object_level = 'table'
    object_params = [
        ('server', 'int', 'server_id'),
        ('database', 'string', 'database_name'),
        ('schema', 'string', 'schema_name'),
        ('table', 'string', 'table_name')
    ]


class TableProbeHistoryView(TableProbeDataView):
    """
    API routes for accessing the probe history data for table.
    """
    api_type = 'history'
    url_suffix = URL_SUFFIX


class IndexProbeDataView(DatabaseObjectView):
    """
    API routes for accessing the probe data for index.
    """
    level = DashboardLevel.DB_INDEX
    object_level = 'index'
    object_params = [
        ('server', 'int', 'server_id'),
        ('database', 'string', 'database_name'),
        ('schema', 'string', 'schema_name'),
        ('index', 'string', 'index_name')
    ]


class IndexProbeHistoryView(IndexProbeDataView):
    """
    API routes for accessing the probe history data for index.
    """
    api_type = 'history'
    url_suffix = URL_SUFFIX


class SequenceProbeDataView(DatabaseObjectView):
    """
    API routes for accessing the probe data for sequence.
    """
    level = DashboardLevel.DB_SEQUENCE
    object_level = 'sequence'
    object_params = [
        ('server', 'int', 'server_id'),
        ('database', 'string', 'database_name'),
        ('schema', 'string', 'schema_name'),
        ('sequence', 'string', 'sequence_name')
    ]


class SequenceProbeHistoryView(SequenceProbeDataView):
    """
    API routes for accessing the probe history data for sequence.
    """
    api_type = 'history'
    url_suffix = URL_SUFFIX


class ViewProbeDataView(DatabaseObjectView):
    """
    API routes for accessing the probe data for view.
    """
    level = DashboardLevel.DB_VIEW
    object_level = 'view'
    object_params = [
        ('server', 'int', 'server_id'),
        ('database', 'string', 'database_name'),
        ('schema', 'string', 'schema_name'),
        ('view', 'string', 'view_name')
    ]


class ViewProbeHistoryView(ViewProbeDataView):
    """
    API routes for accessing the probe history data for view.
    """
    api_type = 'history'
    url_suffix = URL_SUFFIX


class FunctionProbeDataView(DatabaseObjectView):
    """
    API routes for accessing the probe data for function.
    """
    level = DashboardLevel.DB_FUNCTION
    object_level = 'function'
    object_params = [
        ('server', 'int', 'server_id'),
        ('database', 'string', 'database_name'),
        ('schema', 'string', 'schema_name'),
        ('function', 'string', 'function_name')
    ]


class FunctionProbeHistoryView(FunctionProbeDataView):
    """
    API routes for accessing the probe history data for function.
    """
    api_type = 'history'
    url_suffix = URL_SUFFIX
