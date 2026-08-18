##########################################################################
#
# Postgres Enterprise Manager
#
# Copyright (C) 2016 - 2025, EnterpriseDB Corporation. All rights reserved.
#
##########################################################################

"""Implements the pemAgent Jobs Node"""
from functools import wraps
import json

from flask import render_template, request, jsonify
from flask_babel import gettext as _
from flask_security import current_user

from pgadmin.browser.collection import CollectionNodeModule
from pgadmin.browser.utils import NodeView
from pgadmin.pem.utils import pem_connection
from pgadmin.utils.ajax import make_json_response, internal_server_error, \
    make_response as ajax_response, gone, success_return, forbidden, created
from pgadmin.utils.preferences import Preferences
from pgadmin.pem.utils.role import scheduleTaskRole

from .schedules.utils import format_schedule_data
from .utils import create_job
from . import api


class JobModule(CollectionNodeModule):
    _NODE_TYPE = 'pem_job'
    _COLLECTION_LABEL = _("Jobs")

    @pem_connection
    def get_nodes(self, gid, agid, pem_conn=None):
        """
        Generate the collection node
        """
        if self.show_node:
            if scheduleTaskRole.has_role() is True:
                yield self.generate_browser_collection_node(agid)

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
        return 'icon-pga_job'

    @property
    def collection_icon(self):
        return 'icon-coll-pga_job'

    def register(self, app, options):
        """
        Override the default register function to automagically register
        sub-modules at once.
        """
        from .steps import blueprint as steps
        self.submodules.append(steps)

        from .schedules import blueprint as schedules
        self.submodules.append(schedules)
        super().register(app, options)


blueprint = JobModule(__name__)


class JobView(NodeView):
    node_type = blueprint.node_type

    parent_ids = [
        {'type': 'int', 'id': 'gid'},
        {'type': 'int', 'id': 'agid'}
    ]
    ids = [
        {'type': 'int', 'id': 'jid'}
    ]

    operations = dict({
        'obj': [
            {'get': 'properties', 'delete': 'delete', 'put': 'update'},
            {'get': 'properties', 'post': 'create', 'delete': 'delete'}
        ],
        'nodes': [{'get': 'nodes'}, {'get': 'nodes'}],
        'sql': [{'get': 'sql'}],
        'msql': [{'get': 'msql'}, {'get': 'msql'}],
        'run_now': [{'put': 'run_now'}],
        'children': [{'get': 'children'}],
        'stats': [{'get': 'statistics'}],
        'servers': [{'get': 'bound_servers'}, {'get': 'bound_servers'}],
        'timezones': [{'get': 'timezones'}, {'get': 'timezones'}]
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

            if scheduleTaskRole.has_role() is False:
                return forbidden(
                    errormsg=_(
                        "User does not have permission to manage the jobs"
                    )
                )

            # Set the template path for the sql scripts.
            self.template_path = 'pem_jobs/sql'

            return f(self, *args, **kwargs)
        return wrap

    @check_precondition
    def nodes(self, gid, agid, jid=None, rest_api=False):
        if scheduleTaskRole.has_role() is False:
            if jid is not None:
                return gone(
                    errormsg=_(
                        "Could not find the specified job for the agent."
                    )
                )
            else:
                return []

        SQL = render_template(
            "/".join([self.template_path, 'nodes.sql']),
            jid=jid, aid=agid, conn=self.conn
        )
        status, rset = self.conn.execute_dict(SQL)

        if not status:
            return internal_server_error(errormsg=rset)

        if jid is not None:
            if len(rset['rows']) != 1:
                return gone(
                    errormsg=_(
                        "Could not find the specified job for the agent."
                    )
                )
            return make_json_response(
                data=self.blueprint.generate_browser_node(
                    rset['rows'][0]['jobid'],
                    agid,
                    rset['rows'][0]['jobname'],
                    "icon-pga_job" if rset['rows'][0]['jobenabled'] else
                    "icon-pga_job-disabled"
                ),
                status=200
            )
        if rest_api is True:
            return rset['rows']

        res = []
        for row in rset['rows']:
            res.append(
                self.blueprint.generate_browser_node(
                    row['jobid'],
                    agid,
                    row['jobname'],
                    "icon-pga_job" if row['jobenabled'] else
                    "icon-pga_job-disabled"
                )
            )

        return make_json_response(
            data=res,
            status=200
        )

    @check_precondition
    def properties(self, gid, agid, jid=None, rest_api=False):
        SQL = render_template(
            "/".join([self.template_path, 'properties.sql']),
            jid=jid, aid=agid, conn=self.conn,
            schema_version=current_user.schema_version
        )
        status, rset = self.conn.execute_dict(SQL)

        if not status:
            return internal_server_error(errormsg=rset)

        if jid is not None:
            if len(rset['rows']) != 1:
                return gone(
                    errormsg=_(
                        "Could not find the specified job for the agent."
                    )
                )
            res = rset['rows'][0]
            status, rset = self.conn.execute_dict(
                render_template(
                    "/".join([self.template_path, 'steps.sql']),
                    jid=jid, conn=self.conn, aid=agid
                )
            )
            if not status:
                return internal_server_error(errormsg=rset)
            res['jsteps'] = rset['rows']
            status, rset = self.conn.execute_dict(
                render_template(
                    "/".join([self.template_path, 'schedules.sql']),
                    jid=jid, conn=self.conn, aid=agid
                )
            )
            if not status:
                return internal_server_error(errormsg=rset)
            res['jschedules'] = rset['rows']
        else:
            res = rset['rows']

        return ajax_response(
            response=res,
            status=200
        )

    @check_precondition
    def create(self, gid, agid, jobdata=None, rest_api=False):
        """Create the pgAgent job."""
        required_args = [
            u'jobname'
        ]

        data = None

        if rest_api is True:
            data = jobdata if jobdata is not None else {}
        else:
            data = request.form if request.form else json.loads(
                request.data.decode('utf-8')
            )

        for arg in required_args:
            if arg not in data:
                return make_json_response(
                    status=410,
                    success=0,
                    errormsg=_(
                        "Could not find the required parameter (%s)." % arg
                    )
                )

        row, err = create_job(self.conn, agid, data)

        if err is not None:
            return internal_server_error(errormsg=err)

        if rest_api is True:
            return created(
                data={'id': row['jobid']},
                message=_('Job created successfully')
            )

        return jsonify(
            node=self.blueprint.generate_browser_node(
                row['jobid'],
                agid,
                row['jobname'],
                icon="icon-pga_job"
            )
        )

    @check_precondition
    def update(self, gid, agid, jid, jschedules=None, rest_api=False):
        """Update the pgAgent Job."""

        data = request.form if request.form else json.loads(
            request.data.decode('utf-8')
        )

        if 'jschedules' in data:
            if rest_api is True and jschedules is not None:
                data['jschedules'] = jschedules
            schedules = data['jschedules']
            if 'added' in schedules:
                for schedule in schedules['added']:
                    format_schedule_data(schedule)
            if 'changed' in schedules:
                for schedule in schedules['changed']:
                    format_schedule_data(schedule)

        status, res = self.conn.execute_void(
            render_template(
                "/".join([self.template_path, 'update.sql']),
                data=data, conn=self.conn, jid=jid, aid=agid,
                schema_version=current_user.schema_version
            )
        )

        if not status:
            return internal_server_error(errormsg=res)

        if rest_api is True:
            return make_json_response(success=1,
                                      result="Job updated successfully")

        # We need oid of newly created database
        status, res = self.conn.execute_dict(
            render_template(
                "/".join([self.template_path, 'nodes.sql']),
                jid=jid, conn=self.conn, aid=agid
            )
        )

        if not status:
            return internal_server_error(errormsg=res)

        row = res['rows'][0]

        return jsonify(
            node=self.blueprint.generate_browser_node(
                jid,
                agid,
                row['jobname'],
                icon="icon-pga_job" if row['jobenabled']
                else "icon-pga_job-disabled"
            )
        )

    @check_precondition
    def delete(self, gid, agid, jid=None, rest_api=False):
        """Delete the pgAgent Job."""

        if jid is None:
            data = request.form if request.form else json.loads(request.data)
        else:
            data = {'ids': [jid]}

        for jid in data['ids']:
            status, res = self.conn.execute_void(
                render_template(
                    "/".join([self.template_path, 'delete.sql']),
                    jid=jid, conn=self.conn, aid=agid
                )
            )
            if not status:
                return internal_server_error(errormsg=res)

        if rest_api is True:
            return make_json_response(success=1,
                                      result="Job deleted successfully")

        return make_json_response(success=1)

    @check_precondition
    def msql(self, gid, agid, jid=None):
        """
        This function to return modified SQL.
        """
        data = {}
        for k, v in request.args.items():
            try:
                data[k] = json.loads(
                    v.decode('utf-8') if hasattr(v, 'decode') else v
                )
            except ValueError:
                data[k] = v

        if 'jschedules' in data:
            if jid is not None:
                schedules = data['jschedules']
                if 'added' in schedules:
                    for schedule in schedules['added']:
                        format_schedule_data(schedule)
                if 'changed' in schedules:
                    for schedule in schedules['changed']:
                        format_schedule_data(schedule)
            else:
                for schedule in data['jschedules']:
                    format_schedule_data(schedule)

        return make_json_response(
            data=render_template(
                "/".join([
                    self.template_path,
                    'create.sql' if jid is None else 'update.sql'
                ]),
                jid=jid, data=data, conn=self.conn, fetch_id=False, aid=agid,
                schema_version=current_user.schema_version
            ),
            status=200
        )

    @check_precondition
    def statistics(self, gid, agid, jid):
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
                jid=jid, conn=self.conn, aid=agid,
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
    def sql(self, gid, agid, jid):
        """
        This function will generate sql for sql panel
        """
        SQL = render_template(
            "/".join([self.template_path, 'properties.sql']),
            jid=jid, conn=self.conn, aid=agid,
            schema_version=current_user.schema_version
        )
        status, res = self.conn.execute_dict(SQL)
        if not status:
            return internal_server_error(errormsg=res)

        if len(res['rows']) == 0:
            return gone(
                _("Could not find the object on the server.")
            )

        row = res['rows'][0]

        status, res = self.conn.execute_dict(
            render_template(
                "/".join([self.template_path, 'steps.sql']),
                jid=jid, conn=self.conn, aid=agid,
                schema_version=current_user.schema_version
            )
        )
        if not status:
            return internal_server_error(errormsg=res)

        row['jsteps'] = res['rows']

        status, res = self.conn.execute_dict(
            render_template(
                "/".join([self.template_path, 'schedules.sql']),
                jid=jid, conn=self.conn, aid=agid,
                schema_version=current_user.schema_version
            )
        )
        if not status:
            return internal_server_error(errormsg=res)

        row['jschedules'] = res['rows']
        for schedule in row['jschedules']:
            schedule['jscexceptions'] = []
            if schedule['jexid']:
                idx = 0
                for exc in schedule['jexid']:
                    schedule['jscexceptions'].append({
                        'jexid': exc,
                        'jexdate': schedule['jexdate'][idx],
                        'jextime': schedule['jextime'][idx]
                    })
                    idx += 1
            del schedule['jexid']
            del schedule['jexdate']
            del schedule['jextime']

        return ajax_response(
            response=render_template(
                "/".join([self.template_path, 'create.sql']),
                jid=jid, data=row, conn=self.conn, fetch_id=False, aid=agid,
                schema_version=current_user.schema_version
            )
        )

    @check_precondition
    def run_now(self, gid, agid, jid):
        """
        This function will set the next run to now, to inform the pgAgent to
        run the job now.
        """
        if scheduleTaskRole.has_role() is False:
            return gone(
                errormsg=_(
                    "Could not find the specified job for the agent."
                )
            )

        status, res = self.conn.execute_void(
            render_template(
                "/".join([self.template_path, 'run_now.sql']),
                jid=jid, conn=self.conn, aid=agid
            )
        )
        if not status:
            return internal_server_error(errormsg=res)

        return success_return(
            message=_("Updated the next runtime to now.")
        )

    @check_precondition
    def bound_servers(self, gid, agid, jid=None):
        sql = render_template(
            "/".join([self.template_path, 'servers.sql']), agent_id=agid,
        )
        status, agents = self.conn.execute_dict(sql)

        if not status:
            return internal_server_error(errormsg=agents)

        return ajax_response(response=dict(data=agents['rows']), status=200)

    @check_precondition
    def timezones(self, gid, agid, jid=None):
        """
        This function to return list of available timezones on PEM server
        """
        res = []
        status, rset = self.conn.execute_dict(
            "SELECT name, abbrev FROM pg_timezone_names;"
        )

        if not status:
            return internal_server_error(errormsg=rset)

        for row in rset['rows']:
            res.append(
                {
                    'label': f"{row['name']} ({row['abbrev']})",
                    'value': row['name']
                }
            )

        return make_json_response(
            data=res,
            status=200
        )


JobView.register_node_view(blueprint)
