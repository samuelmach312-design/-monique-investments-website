##########################################################################
#
# Postgres Enterprise Manager
#
# Copyright (C) 2016 - 2025, EnterpriseDB Corporation. All rights reserved.
#
##########################################################################

"""Implements pemAgent Job Step Node"""

import json
from functools import wraps

from flask import render_template, request, jsonify
from flask_babel import gettext
from pgadmin.browser.collection import CollectionNodeModule
from pgadmin.browser.utils import PGChildNodeView
from pgadmin.pem.utils import pem_connection
from pgadmin.pem.utils.role import scheduleTaskRole
from pgadmin.utils.ajax import make_json_response, gone, \
    make_response as ajax_response, internal_server_error
from pgadmin.utils.preferences import Preferences


class JobStepModule(CollectionNodeModule):
    """
    class JobStepModule(CollectionNodeModule)

        A module class for JobStep node derived from CollectionNodeModule.

    Methods:
    -------
    * get_nodes(gid, agid, jid)
      - Method is used to generate the browser collection node.

    * node_inode()
      - Method is overridden from its base class to make the node as leaf node.
    """

    _NODE_TYPE = 'pem_jobstep'
    _COLLECTION_LABEL = gettext("Steps")

    @pem_connection
    def get_nodes(self, gid, agid, jid, pem_conn=None):
        """
        Method is used to generate the browser collection node

        Args:
            gid: Server Group ID
            agid: Agent ID
            jid: Job Id
        """
        if self.show_node:
            if scheduleTaskRole.has_role() is True:
                yield self.generate_browser_collection_node(jid)

    @property
    def node_inode(self):
        """
        Override this property to make the node a leaf node.

        Returns: False as this is the leaf node
        """
        return False

    @property
    def script_load(self):
        """
        Load the module script for language, when any of the job nodes
        are initialized.

        Returns: node type of the server module.
        """
        return 'pem_job'

    @property
    def csssnippets(self):
        """
        Returns a snippet of css to include in the page
        """
        return []

    @property
    def module_use_template_javascript(self):
        """
        Returns whether Jinja2 template is used for generating the javascript
        module.
        """
        return False

    @property
    def node_icon(self):
        return 'icon-pga_jobstep'

    @property
    def collection_icon(self):
        return 'icon-coll-pga_jobstep'


blueprint = JobStepModule(__name__)


class JobStepView(PGChildNodeView):
    """
    class JobStepView(PGChildNodeView)

        A view class for JobStep node derived from PGChildNodeView.
        This class is responsible for all the stuff related to view like
        updating job step node, showing properties, showing sql in sql pane.

    Methods:
    -------
    * __init__(**kwargs)
      - Method is used to initialize the JobStepView and it's base view.

    * check_precondition()
      - This function will behave as a decorator which will checks
        database connection before running view, it will also attaches
        manager,conn & template_path properties to self

    * list()
      - This function is used to list all the job step nodes within that
      collection.

    * nodes()
      - This function will used to create all the child node within that
      collection.
        Here it will create all the job step node.

    * properties(gid, agid, jid, jstid)
      - This function will show the properties of the selected job step node

    * update(gid, agid, jid, jstid)
      - This function will update the data for the selected job step node

    * msql(gid, agid, jid, jstid)
      - This function is used to return modified SQL for the selected
      job step node

    * sql(gid, agid, jid, jscid)
      - Dummy response for sql panel

    * delete(gid, agid, jid, jscid)
      - Drops job step
    """

    node_type = blueprint.node_type

    parent_ids = [
        {'type': 'int', 'id': 'gid'},
        {'type': 'int', 'id': 'agid'},
        {'type': 'int', 'id': 'jid'}
    ]
    ids = [
        {'type': 'int', 'id': 'jstid'}
    ]

    operations = dict({
        'obj': [
            {'get': 'properties', 'put': 'update', 'delete': 'delete'},
            {'get': 'list', 'post': 'create', 'delete': 'delete'}
        ],
        'nodes': [{'get': 'nodes'}, {'get': 'nodes'}],
        'msql': [{'get': 'msql'}, {'get': 'msql'}],
        'sql': [{'get': 'sql'}],
        'stats': [{'get': 'statistics'}]
    })

    def _init_(self, **kwargs):
        """
        Method is used to initialize the JobStepView and its base view.
        Initialize all the variables create/used dynamically like conn,
        template_path.

        Args:
            **kwargs:
        """
        self.conn = None
        self.template_path = None

        super(JobStepView, self).__init__(**kwargs)

    def check_precondition(f):
        """
        This function will behave as a decorator which will check the
        database connection before running the view. It also attaches
        manager, conn & template_path properties to self
        """

        @wraps(f)
        @pem_connection
        def wrap(self, *args, **kwargs):
            # Here args[0] will hold self & kwargs will hold gid,agid,jid
            self.conn = kwargs.pop('pem_conn')
            self.template_path = 'pem_jobsteps/sql'

            return f(self, *args, **kwargs)

        return wrap

    @check_precondition
    def list(self, gid, agid, jid):
        """
        This function is used to list all the job step nodes within
        that collection.

        Args:
            gid: Server Group ID
            agid: Agent ID
            jid: Job ID
        """
        sql = render_template(
            "/".join([self.template_path, 'properties.sql']), jid=jid
        )
        status, res = self.conn.execute_dict(sql)

        if not status:
            return internal_server_error(errormsg=res)

        return ajax_response(
            response=res['rows'],
            status=200
        )

    @check_precondition
    def nodes(self, gid, agid, jid, jstid=None):
        """
        This function is used to create all the child nodes
        within the collection.
        Here it will create all the job step nodes.

        Args:
            gid: Server Group ID
            agid: Agent ID
            jid: Job ID
        """
        res = []
        sql = render_template(
            "/".join([self.template_path, 'nodes.sql']),
            jstid=jstid,
            jid=jid
        )

        status, result = self.conn.execute_2darray(sql)

        if not status:
            return internal_server_error(errormsg=result)

        if jstid is not None:
            if len(result['rows']) == 0:
                return gone(errormsg="Could not find the specified job step.")

            row = result['rows'][0]
            return make_json_response(
                data=self.blueprint.generate_browser_node(
                    row['jstid'],
                    row['jstjobid'],
                    row['jstname'],
                    icon="icon-pga_jobstep",
                    enabled=row['jstenabled'],
                    kind=row['jstkind']
                )
            )

        for row in result['rows']:
            res.append(
                self.blueprint.generate_browser_node(
                    row['jstid'],
                    row['jstjobid'],
                    row['jstname'],
                    icon="icon-pga_jobstep",
                    enabled=row['jstenabled'],
                    kind=row['jstkind']
                )
            )

        return make_json_response(
            data=res,
            status=200
        )

    @check_precondition
    def properties(self, gid, agid, jid, jstid):
        """
        This function will show the properties of the selected job step node.

        Args:
            gid: Server Group ID
            agid: Agent ID
            jid: Job ID
            jstid: JobStep ID
        """
        sql = render_template(
            "/".join([self.template_path, 'properties.sql']),
            jstid=jstid, jid=jid,
        )
        status, res = self.conn.execute_dict(sql)

        if not status:
            return internal_server_error(errormsg=res)

        if len(res['rows']) == 0:
            return gone(errormsg="Could not find the specified job step.")

        return ajax_response(
            response=res['rows'][0],
            status=200
        )

    @check_precondition
    def create(self, gid, agid, jid):
        """
        This function will update the data for the selected job step node.

        Args:
            gid: Server Group ID
            agid: Agent ID
            jid: Job ID
        """
        data = {}
        if request.args:
            for k, v in request.args.items():
                try:
                    data[k] = json.loads(
                        v.decode('utf-8') if hasattr(v, 'decode') else v
                    )
                except ValueError:
                    data[k] = v
        else:
            data = json.loads(request.data.decode())

        sql = render_template(
            "/".join([self.template_path, 'create.sql']), jid=jid, data=data,
        )

        status, res = self.conn.execute_scalar(sql)

        if not status:
            return internal_server_error(errormsg=res)

        sql = render_template(
            "/".join([self.template_path, 'nodes.sql']),
            jstid=res,
            jid=jid
        )
        status, res = self.conn.execute_2darray(sql)

        if not status:
            return internal_server_error(errormsg=res)

        if len(res['rows']) == 0:
            return gone(
                errormsg=gettext(
                    "Job step creation failed."
                )
            )
        row = res['rows'][0]
        return jsonify(
            node=self.blueprint.generate_browser_node(
                row['jstid'],
                row['jstjobid'],
                row['jstname'],
                icon="icon-pga_jobstep"
            )
        )

    @check_precondition
    def update(self, gid, agid, jid, jstid):
        """
        This function will update the data for the selected job step node.

        Args:
            gid: Server Group ID
            agid: Agent ID
            jid: Job ID
            jstid: JobStep ID
        """
        data = request.form if request.form else json.loads(
            request.data.decode('utf-8')
        )

        sql = render_template(
            "/".join([self.template_path, 'update.sql']),
            jid=jid, jstid=jstid, data=data,
        )

        status, res = self.conn.execute_void(sql)

        if not status:
            return internal_server_error(errormsg=res)

        sql = render_template(
            "/".join([self.template_path, 'nodes.sql']),
            jstid=jstid,
            jid=jid
        )
        status, res = self.conn.execute_2darray(sql)

        if not status:
            return internal_server_error(errormsg=res)

        if len(res['rows']) == 0:
            return gone(
                errormsg=gettext(
                    "Job step update failed."
                )
            )
        row = res['rows'][0]
        return jsonify(
            node=self.blueprint.generate_browser_node(
                jstid,
                jid,
                row['jstname'],
                icon="icon-pga_jobstep"
            )
        )

    @check_precondition
    def delete(self, gid, agid, jid, jstid=None):
        """Delete the Job step."""

        if jstid is None:
            data = request.form if request.form else json.loads(request.data)
        else:
            data = {'ids': [jstid]}

        for jstid in data['ids']:
            status, res = self.conn.execute_void(
                render_template(
                    "/".join([self.template_path, 'delete.sql']),
                    jid=jid, jstid=jstid, conn=self.conn
                )
            )
            if not status:
                return internal_server_error(errormsg=res)

        return make_json_response(success=1)

    @check_precondition
    def msql(self, gid, agid, jid, jstid=None):
        """
        This function is used to return modified SQL for the selected
        job step node.

        Args:
            gid: Server Group ID
            agid: Agent ID
            jid: Job ID
            jstid: Job Step ID
        """
        data = {}
        sql = ''
        for k, v in request.args.items():
            try:
                data[k] = json.loads(
                    v.decode('utf-8') if hasattr(v, 'decode') else v
                )
            except ValueError:
                data[k] = v

        if jstid is None:
            sql = render_template(
                "/".join([self.template_path, 'create.sql']),
                jid=jid,
                data=data,
            )
        else:
            sql = render_template(
                "/".join([self.template_path, 'update.sql']),
                jid=jid, jstid=jstid, data=data
            )

        return make_json_response(
            data=sql,
            status=200
        )

    @check_precondition
    def statistics(self, gid, agid, jid, jstid):
        """
        statistics
        Returns the statistics for a particular database if jid is specified,
        otherwise it will return statistics for all the databases in that
        server.
        """
        pref = Preferences.module('browser')
        rows_threshold = pref.preference(
            'pgagent_row_threshold'
        )

        status, res = self.conn.execute_dict(
            render_template(
                "/".join([self.template_path, 'stats.sql']),
                jid=jid, jstid=jstid, conn=self.conn,
                rows_threshold=rows_threshold.get()
            )
        )

        if not status:
            return internal_server_error(errormsg=res)

        return make_json_response(
            data=res,
            status=200
        )

    @check_precondition
    def sql(self, gid, agid, jid, jstid):
        """
        Dummy response for sql route.
        As we need to have msql tab for create and edit mode we can not
        disable it setting hasSQL=false because we have a single 'hasSQL'
        flag in JS to display both sql & msql tab
        """
        return ajax_response(
            response=gettext(
                "-- No SQL could be generated for the selected object."
            ),
            status=200
        )


JobStepView.register_node_view(blueprint)
