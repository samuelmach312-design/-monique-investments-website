##########################################################################
#
# Postgres Enterprise Manager
#
# Copyright (C) 2016 - 2025, EnterpriseDB Corporation. All rights reserved.
#
##########################################################################
"""Implements Cluster Module"""

import json
from functools import wraps
from flask import request, render_template, jsonify, current_app
from flask_security import login_required, current_user
from flask_babel import gettext
from pgadmin.utils.ajax import make_json_response, internal_server_error, \
    make_response as ajax_response, precondition_required, gone, bad_request
from pgadmin.browser.utils import NodeView
from pgadmin.pem.utils import pem_connection
from pgadmin.browser import server_groups as sg
from pgadmin.browser.collection import CollectionNodeModule


class ClusterModule(CollectionNodeModule):
    """
    This class represents The Cluster Module.

    Methods:
    -------
    * __init__(*args, **kwargs)
      - Initialize the Cluster Module.

    * get_nodes(gid, sid, did, scid)
      - Generate the Cluster collection node.

    """
    _NODE_TYPE = 'cluster'
    _COLLECTION_LABEL = gettext("Clusters")
    LABEL = gettext("Cluster")
    CLUSTER_NODE_TYPES = ['server']

    def __init__(self, *args, **kwargs):
        super().__init__(*args, **kwargs)
        self.template_path = 'clusters/sql'

    @property
    def node_type(self):
        return self._NODE_TYPE

    @property
    def node_inode(self):
        """
        Returns node as non-leaf node.
        """
        return True

    @property
    def script_load(self):
        """
        Load the module script for server, when any of the server-group node is
        initialized.
        """
        return sg.ServerGroupModule.node_type

    @login_required
    @pem_connection
    def get_nodes(self, gid, pem_conn=None):
        """
        Generate the Cluster collection node
        """
        if self.show_node:
            # Get Pem Server connection to fetch the server list
            sql = render_template(
                "/".join([blueprint.template_path, 'node.sql']),
                parent_id=gid
            )
            status, res = pem_conn.execute_dict(sql)
            if not status:
                current_app.logger.error(res)
                yield internal_server_error(errormsg=res)

            for cl in res['rows']:
                yield self.generate_browser_node(
                    cl['id'],
                    gid,
                    cl['name'],
                )

    def register(self, app, options):
        """
        Override the default register function to automagically register
        sub-modules at once.
        """

        from ..servers import blueprint as module
        self.submodules.append(module)

        from ..agents import blueprint as module
        self.submodules.append(module)

        super().register(app, options)


blueprint = ClusterModule(__name__)


class ClusterView(NodeView):
    """
    class ClusterView(NodeView):

    This class inherits NodeView to get the different routes for
    the module.

    The class is responsible to Read, Update and Delete operations for
    the Cluster View.

    Methods:
    -------

    * check_precondition(f):
      - Works as a decorator.
      -  Checks database connection status.
      -  Attach connection object and template path.

    * list():
      - List the Clusters.

    * nodes():
      - Returns all the Clusters to generate Nodes in the browser.

    * properties(clid):
      - Returns the Cluster properties.

    * update(clid):
      - Updates the Cluster object.

    * delete(clid):
      - Drops the Cluster object.

    """
    node_type = blueprint.node_type
    # template_path = blueprint.template_path
    parent_ids = [{'type': 'int', 'id': 'gid'}]
    ids = [{'type': 'int', 'id': 'clid'}]
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

    NOT_FOUND_MSG = gettext('The specified cluster could not be found.')

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
            self.template_path = 'clusters/sql'

            return f(self, *args, **kwargs)
        return wrap

    @check_precondition
    def list(self, gid):
        """
        List the Clusters.
        """
        # Fetch List of Clusters
        sql = render_template(
            "/".join([self.template_path, 'node.sql']),
            parent_id=gid
        )
        status, clusters = self.conn.execute_dict(sql)

        if not status:
            return internal_server_error(errormsg=clusters)

        return ajax_response(response=clusters, status=200)

    def node(self, gid, clid):
        return self.nodes(gid, clid)

    @check_precondition
    def nodes(self, gid, clid=None):
        """
        Returns all the Clusters.
        """
        nodes = []

        SQL = render_template(
            "/".join([self.template_path, 'node.sql']),
            parent_id=gid,
            id=clid
        )
        status, rset = self.conn.execute_dict(SQL)

        if not status:
            return internal_server_error(errormsg=rset)

        if clid is not None:
            if len(rset['rows']) == 0:
                return gone(errormsg=self.NOT_FOUND_MSG)

            row = rset['rows'][0]
            return make_json_response(
                data=self.blueprint.generate_browser_node(
                    row['id'],
                    gid,
                    row['name'],
                )
            )

        for row in rset['rows']:
            nodes.append(
                self.blueprint.generate_browser_node(
                    row['id'],
                    gid,
                    row['name'],
                )
            )

        return make_json_response(
            data=nodes,
            status=200
        )

    @check_precondition
    def delete(self, gid, clid=None):
        """
        Delete a PEM Cluster
        """
        if clid is None or clid < 1:
            return gone(errormsg=self.NOT_FOUND_MSG)

        sql = render_template(
            "/".join([self.template_path, 'delete.sql']), id=clid
        )
        status, res = self.conn.execute_void(sql)
        if not status:
            return internal_server_error(res)

        return make_json_response(success=1)

    @check_precondition
    def update(self, gid, clid=None):
        """
        Update the Cluster properties
        """

        if clid is None or clid < 1:
            return gone(errormsg=self.NOT_FOUND_MSG)

        data = request.form if request.form else\
            json.loads(request.data.decode())

        sql = render_template(
            "/".join([self.template_path, 'update.sql']), data=data, id=clid
        )
        status, res = self.conn.execute_void(sql)

        if not status:
            return internal_server_error(res)

        sql = render_template(
            "/".join([self.template_path, 'node.sql']),
            id=clid
        )
        status, res = self.conn.execute_dict(sql)

        if not status:
            return internal_server_error(errormsg=res)

        cluster = res['rows'][0]

        return jsonify(
            node=self.blueprint.generate_browser_node(
                clid,
                cluster['parent_id'],
                cluster['name'],
            )
        )

    @check_precondition
    def properties(self, gid, clid=None):
        """
        Get the Cluster properties
        """
        if clid is None or clid < 1:
            return gone(errormsg=self.NOT_FOUND_MSG)

        sql = render_template(
            "/".join([self.template_path, 'node.sql']),
            parent_id=gid,
            id=clid
        )
        status, clusters = self.conn.execute_dict(sql)

        if not status:
            return internal_server_error(errormsg=clusters)

        cluster = clusters['rows'][0]

        return ajax_response(response=cluster, status=200)

    @check_precondition
    def create(self, gid):
        data = request.form if request.form else json.loads(
            request.data
        )
        if 'name' in data and data['name']:
            sql = render_template(
                "/".join([self.template_path, 'create.sql']),
                data=data
            )
            status, clid = self.conn.execute_scalar(sql)

            if not status:
                return internal_server_error(errormsg=clid)

            if clid > 0:
                return jsonify(
                    node=self.blueprint.generate_browser_node(
                        clid,
                        data['parent_id'],
                        data['name'],
                    )
                )
            else:
                return bad_request(self.get_error_msg(
                    "Cluster id can not be less than 1"))
        else:
            return make_json_response(
                status=400,
                success=0,
                errormsg=gettext('No cluster name was specified')
            )

    def sql(self, gid, clid=None):
        return make_json_response(status=422)

    def modified_sql(self, gid, clid=None):
        return make_json_response(status=422)

    def statistics(self, gid, clid=None):
        return make_json_response(status=422)

    def dependencies(self, gid, clid=None):
        return make_json_response(status=422)

    def dependents(self, gid, clid=None):
        return make_json_response(status=422)


ClusterView.register_node_view(blueprint)
