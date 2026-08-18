##########################################################################
#
# Postgres Enterprise Manager
#
# Copyright (C) 2016 - 2025, EnterpriseDB Corporation. All rights reserved.
#
##########################################################################
"""Implements Agent Module"""

import json
import math
from functools import wraps
from flask import request, render_template, jsonify, current_app
from flask_security import login_required, current_user
from flask_babel import gettext
from pgadmin.utils.ajax import make_json_response, internal_server_error, \
    make_response as ajax_response, precondition_required, gone, bad_request
from pgadmin.browser.utils import NodeView
from pgadmin.pem.utils import pem_connection
from pgadmin.browser.server_groups.agents.jobs import JobView
from pgadmin.browser.server_groups.agents.utils import update_agent
from pgadmin.browser.server_groups.servers.pem.utils import \
    fetch_message_from_exception
from pgadmin.browser import server_groups as sg
from . import api


class AgentModule(sg.ServerGroupPluginModule):
    """
    class AgentModule(CollectionNodeModule):

        This class represents The Agent Module.

    Methods:
    -------
    * __init__(*args, **kwargs)
      - Initialize the Agent Module.

    * node_inode(gid, sid, did, scid)
      - Returns Agent node as leaf node.

    * script_load()
      - Returns None

    * get_nodes(gid, sid, did, scid)
      - Generate the Agent collection node.

    """
    _NODE_TYPE = 'agent'
    _COLLECTION_LABEL = gettext("PEM Agents")
    LABEL = gettext("Servers")

    def __init__(self, *args, **kwargs):
        self.min_ver = None
        self.max_ver = None

        super(AgentModule, self).__init__(*args, **kwargs)

    @property
    def node_type(self):
        return self._NODE_TYPE

    @property
    def node_inode(self):
        """
        Returns Agnet node as non-leaf node.
        """
        return True

    @property
    def script_load(self):
        return sg.ServerGroupModule.node_type

    @login_required
    @pem_connection
    def get_nodes(self, gid, pem_conn=None, clid=None):
        """
        Generate the Agent collection node
        """
        if self.show_node:
            # Get Pem Server connection to fetch the server list
            sql = render_template(
                "/".join(['agents/sql', 'node.sql']),
                gid=clid if clid is not None else gid,
                schema_version=current_user.schema_version
            )
            status, res = pem_conn.execute_dict(sql)
            if not status:
                current_app.logger.error(res)
                yield internal_server_error(errormsg=res)

            for agent in res['rows']:
                yield self.generate_browser_node(
                    "%d" % (agent['id']),
                    clid if clid is not None else gid,
                    agent['name'],
                    "icon-%s" % self.node_type,
                    # Set inode to True
                    True,
                    # Module to load
                    self.node_type,
                    tags=json.loads(agent['tags']),
                    profile_id=agent['profile_id'],
                    profile_name=agent['profile_name']
                )

    @property
    def jssnippets(self):
        return []

    @property
    def csssnippets(self):
        snippets = [
            render_template("agents/css/agents.css")
        ]

        return snippets

    def get_own_javascripts(self):
        return []

    # We do not have any preferences for agent node.
    def register_preferences(self):
        pass

    def register(self, app, options):
        """
        Override the default register function to automagically register
        sub-modules at once.
        """
        from .jobs import blueprint as jobs
        self.submodules.append(jobs)
        super().register(app, options)


blueprint = AgentModule(__name__)


class AgentView(NodeView):
    """
    class AgentView(NodeView):

    This class inherits NodeView to get the different routes for
    the module.

    The class is responsible to Read, Update and Delete operations for
    the Agent View.

    Methods:
    -------

    * check_precondition(f):
      - Works as a decorator.
      -  Checks database connection status.
      -  Attach connection object and template path.

    * list():
      - List the Agents.

    * nodes():
      - Returns all the Agents to generate Nodes in the browser.

    * properties(agid):
      - Returns the Agent properties.

    * update(agid):
      - Updates the Agent object.

    * delete(agid):
      - Drops the Agent object.

    """
    node_type = blueprint.node_type
    parent_ids = [{'type': 'int', 'id': 'gid'}]
    ids = [{'type': 'int', 'id': 'agid'}]
    operations = dict({
        'obj': [
            {'get': 'properties', 'delete': 'delete', 'put': 'update'},
            {'get': 'list', 'post': 'create'}
        ],
        'nodes': [{'get': 'node'}, {'get': 'nodes'}],
        'sql': [{'get': 'sql'}],
        'msql': [{'get': 'modified_sql'}],
        'stats': [{'get': 'statistics'}],
        'dependency': [{'get': 'dependencies'}],
        'dependent': [{'get': 'dependents'}],
        'children': [{'get': 'children'}]
    })

    NOT_FOUND_MSG = gettext('The specified agent could not be found.')

    def check_precondition(f):
        """
        This function will behave as a decorator which will checks
        database connection before running view, it will also attaches
        manager,conn & template_path properties to self
        """
        @wraps(f)
        @pem_connection
        def wrap(self, *args, **kwargs):

            self.conn = kwargs.pop('pem_conn')

            # If DB not connected then return error to browser
            if not self.conn.connected():
                self.conn.connect()

            if not self.conn.connected():
                return precondition_required(
                    gettext(
                        "Connection to the PEM server has been lost!"
                    )
                )

            # Set the template path for sql scripts
            self.template_path = 'agents/sql'

            return f(self, *args, **kwargs)
        return wrap

    @check_precondition
    def list(self, gid):
        """
        List the Agents.
        """
        # Fetch List of Agents
        sql = render_template(
            "/".join([self.template_path, 'node.sql'])
        )
        status, agents = self.conn.execute_dict(sql)

        if not status:
            return internal_server_error(errormsg=agents)

        return ajax_response(response=agents, status=200)

    def node(self, gid, agid):
        return self.nodes(gid, agid)

    @check_precondition
    def nodes(self, gid, agid=None):
        """
        Returns all the Agents.
        """
        nodes = []

        if agid is None or agid < 1:
            return gone(errormsg=self.NOT_FOUND_MSG)

        SQL = render_template(
            "/".join([self.template_path, 'node.sql']),
            gid=gid,
            agid=agid
        )
        status, rset = self.conn.execute_dict(SQL)

        if not status:
            return internal_server_error(errormsg=rset)

        if agid is not None:
            if len(rset['rows']) == 0:
                return gone(errormsg=self.NOT_FOUND_MSG)

            row = rset['rows'][0]
            return make_json_response(
                data=self.blueprint.generate_browser_node(
                    row['id'],
                    gid,
                    row['name'],
                    "icon-%s" % self.node_type,
                    # Set inode to True
                    True,
                    # # Module to load
                    self.node_type,
                    tags=json.loads(row['tags'])
                )
            )

        for row in rset['rows']:
            nodes.append(
                self.blueprint.generate_browser_node(
                    row['id'],
                    gid,
                    row['name'],
                    "icon-%s" % self.node_type,
                    # Set inode to True
                    True,
                    # # Module to load
                    self.node_type,
                    tags=json.loads(row['tags'])
                )
            )

        return make_json_response(
            data=nodes,
            status=200
        )

    @check_precondition
    def delete(self, gid, agid=None):
        """
        Delete a PEM Agent
        """
        if agid is None or agid < 1:
            return gone(errormsg=self.NOT_FOUND_MSG)

        sql = render_template(
            "/".join([self.template_path, 'drop.sql']), id=agid
        )
        try:
            _, _ = self.conn.execute_void("BEGIN;")
            _, _ = self.conn.execute_void(sql)
            _, _ = self.conn.execute_void("COMMIT;")

            # Create a scheduled job to delete all probe data for the agent
            # try:
            #     from .jobs.utils import create_purge_job
            #     create_purge_job(self.conn, agid=agid)
            # except Exception as e:
            #     current_app.logger.exception(e)
            #     return internal_server_error(
            #         errormsg=fetch_message_from_exception(e))
        except Exception as e:
            return make_json_response(
                status=410,
                success=0,
                errormsg=str(e)
            )

        return make_json_response(success=1)

    @check_precondition
    def update(self, gid, agid=None):
        """
        Update the Agent properties
        """

        if agid is None or agid < 1:
            return gone(errormsg=self.NOT_FOUND_MSG)

        data = request.form if request.form else\
            json.loads(request.data.decode())

        if data:
            # Use the latest group as a node parent
            if 'heartbeat_tol_min' in data or 'heartbeat_tol_sec' in data:
                try:
                    # Initialize the variables for minutes and seconds
                    minutes = 0
                    seconds = 0

                    # Handle the minutes if present
                    if 'heartbeat_tol_min' in data and data[
                            'heartbeat_tol_min']:
                        # Convert minutes to seconds
                        minutes = (
                            int(data['heartbeat_tol_min']) * 60)

                    # Handle the seconds if present
                    if 'heartbeat_tol_sec' in data and data[
                            'heartbeat_tol_sec']:
                        # Use seconds as is
                        seconds = int(
                            data['heartbeat_tol_sec'])

                    # Calculate the total heartbeat tolerance in seconds
                    data['heartbeat_tolerance'] = minutes + seconds

                except Exception as e:
                    current_app.logger.exception(
                        "Invalid value for heartbeat_tolerance: {0}".format(
                            str(e))
                    )
                    return bad_request(
                        errormsg=gettext(
                            "Invalid value for heartbeat_tolerance"
                        )
                    )

            # Check if 'team' has only while-spaces
            if "team" in data and data["team"].isspace():
                data["team"] = ""

        status, res = update_agent(self.conn, agid, data)

        if status is False:
            return internal_server_error(res)

        if status is not True:
            return make_json_response(
                status=404, success=0,
                errormsg=status
            )

        if res is None or len(res['rows']) == 0:
            return gone(errormsg=self.NOT_FOUND_MSG)

        row = res['rows'][0]

        return jsonify(
            node=self.blueprint.generate_browser_node(
                "%d" % (agid),
                row['gid'],
                row['name'],
                "icon-%s" % self.node_type,
                True,
                self.node_type,
                tags=json.loads(row['tags'])
            )
        )

    @check_precondition
    def properties(self, gid, agid=None):
        """
        Get the Agent properties
        """
        if agid is None or agid < 1:
            return gone(errormsg=self.NOT_FOUND_MSG)

        sql = render_template(
            "/".join([self.template_path, 'properties.sql']),
            gid=gid,
            agent_id=agid,
            schema_version=current_user.schema_version
        )
        status, agents = self.conn.execute_dict(sql)

        if not status:
            return internal_server_error(errormsg=agents)

        sql = render_template(
            "/".join([self.template_path, 'agent_configs.sql']),
            agent_id=agid,
        )
        status, agent_configs = self.conn.execute_scalar(sql)
        if not status:
            return internal_server_error(errormsg=agents)

        agent_configs = json.loads('[]' if agent_configs is None else
                                   agent_configs)

        agent = agents['rows'][0]

        # Convert Heartbeat seconds into Minutes.
        heartbeat_tol_min = math.floor(agent['heartbeat_tolerance'] / 60)

        # Convert Heartbeat seconds into Seconds.
        heartbeat_tol_sec = agent['heartbeat_tolerance'] % 60

        agent['heartbeat_tol_min'] = heartbeat_tol_min
        agent['heartbeat_tol_sec'] = heartbeat_tol_sec

        agent['agent_configs'] = agent_configs
        if agent['tags'] is not None:
            agent['tags'] = json.loads(agent['tags'])
            agent['tags'] = [{**tag, 'old_text': tag['text']}
                             for tag in agent['tags']]

        if agent is None:
            return make_json_response(
                status=400,
                success=0,
                errormsg=self.NOT_FOUND_MSG
            )
        else:
            return ajax_response(response=agent, status=200)

    def create(self, gid):
        return make_json_response(status=422)

    def sql(self, gid, agid=None):
        return make_json_response(status=422)

    def modified_sql(self, gid, agid=None):
        return make_json_response(status=422)

    def statistics(self, gid, agid=None):
        return make_json_response(status=422)

    def dependencies(self, gid, agid=None):
        return make_json_response(status=422)

    def dependents(self, gid, agid=None):
        return make_json_response(status=422)


AgentView.register_node_view(blueprint)
