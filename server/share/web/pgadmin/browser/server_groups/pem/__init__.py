##########################################################################
#
# Postgres Enterprise Manager
#
# Copyright (C) 2016 - 2025, EnterpriseDB Corporation. All rights reserved.
#
##########################################################################

"""Defines views for management of server groups"""

import json
from abc import ABCMeta, abstractmethod

from functools import wraps
from flask import request, jsonify, render_template
from flask_babel import gettext
from flask_security import current_user, login_required
from pgadmin.browser import BrowserPluginModule
from pgadmin.browser.utils import NodeView
from pgadmin.utils.ajax import make_json_response, gone, \
    make_response as ajax_response, \
    bad_request, internal_server_error, forbidden, \
    success_return, precondition_required
from pgadmin.utils.menu import MenuItem
from sqlalchemy import exc
from pgadmin.model import db, ServerGroup, Server
import config
from pgadmin.utils.preferences import Preferences
from pgadmin.pem import pem_connection

SAME_NAME_ERROR_MSG = gettext(
    "Cannot have two groups with same name!") + "\n" + gettext(
    "Please specify another name!")
NOT_AVL_ERROR_MSG = gettext(
    "This name is not available for a group!") + "\n" + gettext(
    "Please specify another name!")


SG_NOT_FOUND_ERROR = 'The specified server group could not be found.'


class PEMServerGroupModule(BrowserPluginModule):
    _NODE_TYPE = "server_group"
    node_icon = "icon-%s" % _NODE_TYPE

    @property
    def csssnippets(self):
        """
        Returns a snippet of css to include in the page
        """
        snippets = [render_template("css/server_group.css")]

        for submodule in self.submodules:
            snippets.extend(submodule.csssnippets)

        return snippets

    @staticmethod
    def has_shared_server(gid):
        """
        To check whether given server group contains shared server or not
        :param gid:
        :return: True if servergroup contains shared server else false
        """
        servers = Server.query.filter_by(servergroup_id=gid)
        for s in servers:
            if s.shared:
                return True
        return False

    @pem_connection
    def get_nodes(self, *arg, **kwargs):
        """Return a JSON document listing the server groups for the user"""

        pem_conn = kwargs.pop('pem_conn')
        sql = render_template(
            "/".join(['server_groups/sql', 'properties.sql']),
            hidden_groups=self.show_hidden.get()
        )
        status, res = pem_conn.execute_dict(sql)

        if not status:
            yield internal_server_error(res)
            res = dict({'rows': []})

        groups = res['rows']
        for group in groups:
            yield self.generate_browser_node(
                "%d" % (int(group['id'])), None,
                group['name'],
                self.node_icon,
                True,
                self.node_type,
                _hidden=group['hidden']
            )

    @property
    def node_type(self):
        """
        node_type
        Node type for Server Group is server-group. It is defined by _NODE_TYPE
        static attribute of the class.
        """
        return self._NODE_TYPE

    @property
    def script_load(self):
        """
        script_load
        Load the server-group javascript module on loading of browser module.
        """
        return None

    def register_preferences(self):
        """
        register_preferences
        Overrides the register_preferences PgAdminModule, because - we will not
        register any preference for server-group (specially the show_node
        preference.)
        """
        from .. import blueprint as browser
        self.show_hidden = browser.preference.register(
            'display', 'show_hidden_sgroups',
            gettext("Show hidden groups?"), 'boolean', False,
            category_label=gettext('Display')
        )

    def register(self, app, options):
        """
        Override the default register function to automagically register
        sub-modules at once.
        """
        from ..servers import blueprint as servers
        from ..agents import blueprint as agents
        from ..clusters import blueprint as clusters
        self.submodules.append(servers)
        self.submodules.append(agents)
        self.submodules.append(clusters)

        super().register(app, options)


class PEMServerGroupMenuItem(MenuItem):
    def __init__(self, **kwargs):
        kwargs.setdefault("type", PEMServerGroupModule.node_type)
        super().__init__(**kwargs)


class PEMServerGroupPluginModule(BrowserPluginModule, metaclass=ABCMeta):
    """
    Base class for server group plugins.
    """

    @abstractmethod
    def get_nodes(self, *arg, **kwargs):
        pass


def get_error_msg(res):
    """
    Get proper error message
    :param res: Query response
    :return: message
    """
    if res == -1:
        return NOT_AVL_ERROR_MSG
    elif res == -2 or res == -3:
        return SAME_NAME_ERROR_MSG
    else:
        return gettext(
            'Unknown error adding a group with return id#%!') % res


class PEMServerGroupView(NodeView):
    node_type = PEMServerGroupModule._NODE_TYPE
    node_icon = PEMServerGroupModule.node_icon
    node_label = "Server Group"
    parent_ids = []
    ids = [{'type': 'int', 'id': 'gid'}]

    operations = dict({
        **NodeView.operations,
        'list_with_clusters': [
            {},
            {'get': 'list_with_clusters'}
        ],
    })

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

            # we will set template path for sql scripts
            self.template_path = 'server_groups/sql'

            return f(self, *args, **kwargs)
        return wrap

    @login_required
    @check_precondition
    def list(self, filter_cluster=True):
        res = []
        # Fetch List of Server Groups
        sql = render_template(
            "/".join([self.template_path, 'properties.sql']),
            hidden_groups=self.blueprint.show_hidden.get(),
            filter_cluster=filter_cluster
        )
        status, groups = self.conn.execute_dict(sql)

        if not status:
            return internal_server_error(errormsg=groups)

        res = groups['rows']

        return ajax_response(response=res, status=200)

    @login_required
    @check_precondition
    def list_with_clusters(self):
        return self.list(False)

    @login_required
    @check_precondition
    def delete(self, gid):
        """Delete a server group node in the settings database"""
        if gid == 0 or gid == 1:
            return forbidden(gettext("Not allow to delete this group."))
            # There can be only one record at most
        status, res = self.conn.execute_scalar(
            "SELECT pem.delete_server_group(%s, True,"
            " pem.current_user_id()::integer)""",
            (gid,)
        )

        if not status:
            return internal_server_error(errormsg=res)

        return success_return()

    @login_required
    @check_precondition
    def update(self, gid):
        """Update the server-group properties"""
        data = request.form if request.form else \
            json.loads(request.data.decode())

        if 'name' not in data:
            return precondition_required(
                gettext("Couldn't find the name in the given details!")
            )
        # There can be only one record at most
        sql = "SELECT pem.rename_server_group(%s::int, %s::text)"
        status, res = self.conn.execute_scalar(sql, (gid, data['name'],))

        if not status:
            return internal_server_error(errormsg=res)

        if res == 0:
            return jsonify(
                node=self.blueprint.generate_browser_node(
                    "%d" % (gid), None,
                    data['name'],
                    self.node_icon,
                    True,
                    self.node_type,
                    _hidden=False
                )
            )
        else:
            return bad_request(get_error_msg(res))

    @login_required
    @check_precondition
    def properties(self, gid):
        """Update the server-group properties"""

        sql = render_template(
            "/".join([self.template_path, 'properties.sql']),
            id=gid, hidden_groups=self.blueprint.show_hidden.get()
        )
        status, groups = self.conn.execute_dict(sql)

        if not status:
            return internal_server_error(errormsg=groups)

        if len(groups['rows']) == 0:
            return gone(gettext(SG_NOT_FOUND_ERROR))

        sg = groups['rows'][0]

        if sg is None:
            return make_json_response(
                status=410,
                success=0,
                errormsg=gettext(SG_NOT_FOUND_ERROR)
            )
        else:
            return ajax_response(
                response={'id': sg['id'], 'name': sg['name']},
                status=200
            )

    @login_required
    @check_precondition
    def create(self):
        """Creates new server-group """
        data = request.form if request.form else json.loads(
            request.data
        )
        if 'name' in data and data['name']:
            sql = 'SELECT pem.create_server_group(%s::text)'
            status, res = self.conn.execute_scalar(sql, (data['name'],))

            if not status:
                return internal_server_error(errormsg=res)

            if res > 0:
                return jsonify(
                    node=self.blueprint.generate_browser_node(
                        "%d" % (res),
                        None,
                        data['name'],
                        self.node_icon,
                        True,
                        self.node_type,
                        _hidden=False,
                        # This is user created hence can deleted
                        can_delete=True
                    )
                )
            else:
                return bad_request(self.get_error_msg(res))
        else:
            return make_json_response(
                status=400,
                success=0,
                errormsg=gettext('No group name was specified')
            )

    @login_required
    def sql(self, gid):
        return make_json_response(status=422)

    @login_required
    def modified_sql(self, gid):
        return make_json_response(status=422)

    @login_required
    def statistics(self, gid):
        return make_json_response(status=422)

    @login_required
    def dependencies(self, gid):
        return make_json_response(status=422)

    @login_required
    def dependents(self, gid):
        return make_json_response(status=422)

    @login_required
    @check_precondition
    def nodes(self, gid=None):
        """Return a JSON document listing the server groups for the user"""
        res = []
        sql = render_template(
            "/".join([self.template_path, 'properties.sql']),
            id=gid, hidden_groups=self.blueprint.show_hidden.get()
        )
        status, groups = self.conn.execute_dict(sql)

        if not status:
            return internal_server_error(errormsg=groups)

        groups = groups['rows']

        if gid is not None:
            if len(groups) == 0:
                return gone(gettext(SG_NOT_FOUND_ERROR))
            group = groups[0]
            res = self.blueprint.generate_browser_node(
                "%d" % (group['id']), None,
                group['name'],
                self.node_icon,
                True,
                self.node_type,
                _hidden=group['hidden']
            )
        else:
            for group in groups:
                res.append(
                    self.blueprint.generate_browser_node(
                        "%d" % (group['id']),
                        None,
                        group['name'],
                        self.node_icon,
                        True,
                        self.node_type,
                        _hidden=group['hidden']
                    )
                )

        return make_json_response(data=res)

    def node(self, gid):
        return self.nodes(gid)
