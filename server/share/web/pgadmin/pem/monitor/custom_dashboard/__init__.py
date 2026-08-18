##########################################################################
#
# Postgres Enterprise Manager
#
# Copyright (C) 2016 - 2025, EnterpriseDB Corporation. All rights reserved.
#
##########################################################################

"""Implements Manage Dashboard"""

import json
from flask import render_template, request
from flask_babel import gettext
from pgadmin.utils.ajax import internal_server_error, bad_request, \
    make_response as ajax_response, make_json_response, gone
from pgadmin.utils import PgAdminModule
from flask import Response, url_for
from flask_security import login_required
from pgadmin.pem.utils import pem_connection
from pgadmin.pem.monitor.utils import DashboardLevel
import pgadmin.browser.server_groups as sg
from pgadmin.pem.monitor.utils.charts import SYSTEM_CHART_DESCRIPTIONS
from pgadmin.pem.monitor.utils.import_export import CURRENT_EXPORT_VERSION, \
    get_pem_installation_id, is_export_version_supported, \
    get_import_schema_version
from . import utils, api

MODULE_NAME = 'manage_dashboards'


class ManageDashboardModule(PgAdminModule):
    """
    class ManageDashboardModule(Object):

        Inherits PgAdminModule class and define
        methods to load its own javascript/css files.
    """

    LABEL = gettext('Manage Dashboards')

    def get_own_stylesheets(self):
        """
        Returns:
            list: the stylesheets used by this module.
        """
        stylesheets = [
            url_for('manage_dashboards.static',
                    filename='css/manage_dashboards.css')
        ]
        return stylesheets

    @property
    def script_load(self):
        """
        Load the module script, when any of the server-group node is
        initialized.
        """
        return sg.ServerGroupModule.NODE_TYPE

    def get_exposed_url_endpoints(self):
        """
        Returns:
            list: a list of url endpoints exposed to the client.
        """
        return [
            'manage_dashboards.chart_list', 'manage_dashboards.role_list',
            'manage_dashboards.properties', 'manage_dashboards.create',
            'manage_dashboards.delete', 'manage_dashboards.update',
            'manage_dashboards.dashboard_list',
            'manage_dashboards.custom_export',
            'manage_dashboards.custom_import',
            'manage_dashboards.set_share_permissions',
            'manage_dashboards.get_share_permissions',

        ]


# Create blueprint for Manage Dashboard class
blueprint = ManageDashboardModule(
    MODULE_NAME, __name__, url_prefix='/pem/manage_dashboards')


@blueprint.route("/")
@login_required
def index():
    return bad_request(errormsg=gettext(
        "This URL cannot be called directly!")
    )


@blueprint.route("/create_dashboards.js")
@login_required
def create_dashboard_script():
    """Render own javascript"""
    return Response(
        response=render_template(
            "custom_dashboard/js/create_dashboards.js",
            DashboardLevel=DashboardLevel
        ),
        status=200,
        mimetype="application/javascript"
    )


@blueprint.route("/share_permissions/<dashboard_id>",
                 methods=['PUT'], endpoint='set_share_permissions')
@login_required
@pem_connection
@utils.manageDashboardRole.check_role(
    gettext("Logged-in user do not have permission to share permissions for"
            " the dashboard.")
)
def set_share_permissions(dashboard_id, pem_conn=None):
    """Updates a dashboard information
        Parameters:
            id    - (must) Dashboard id
            shared - (must) Teams/roles to share the dashboard with."""

    data = json.loads(request.data.decode())

    data['teams'] = []
    if 'shared' in data and data['shared'] is not None \
            and data['shared'] != "" and \
            ('shared_all' not in data or data['shared_all'] is False):
        teams = data['shared'] if isinstance(
            data['shared'], list) else \
            json.loads(data['shared'])
        data['teams'] = teams

    params = dict()
    params['id'] = dashboard_id
    params['shared'] = data['teams']

    pem_conn.execute_void("BEGIN;")

    sql = render_template("custom_dashboard/sql/set_share_permissions.sql")
    status, msg = pem_conn.execute_dict(sql, params)

    if not status:
        pem_conn.execute_void('ROLLBACK;')
        return internal_server_error(errormsg=msg)

    status, msg = pem_conn.execute_void("COMMIT;")

    if not status:
        pem_conn.execute_void('ROLLBACK;')
        return internal_server_error(errormsg=msg)

    return make_json_response(
        data={'id': dashboard_id},
        status=200
    )


@blueprint.route("/share_permissions/<dashboard_id>",
                 methods=['GET'], endpoint='get_share_permissions')
@login_required
@pem_connection
@utils.manageDashboardRole.check_role(
    gettext("Logged-in user do not have permission to fetch share permissions"
            " for the dashboard.")
)
def get_share_permissions(dashboard_id, pem_conn=None):
    """Gets details of sharing permissions of a dashboard
        Parameters: dashboard_id - (must) Dashboard id."""

    sql = render_template("custom_dashboard/sql/get_share_permissions.sql")
    status, res = pem_conn.execute_dict(sql, {'id': dashboard_id})
    if not status:
        return internal_server_error(errormsg=res)

    if len(res['rows']) == 0:
        return internal_server_error(errormsg='No dashboard found.')

    return ajax_response(
        response=res['rows'][0],
        status=200)


@blueprint.route("/delete/<dashboard_id>",
                 methods=['POST'], endpoint='delete')
@login_required
@pem_connection
@utils.manageDashboardRole.check_role(
    gettext("Logged-in user do not have permission to delete the dashboard.")
)
def delete(dashboard_id, pem_conn=None):
    """Delete a dashboard
        Parameters: dashboard_id - (must) Dashboard id."""

    sql = render_template("custom_dashboard/sql/delete.sql")
    status, msg = pem_conn.execute_dict(
        sql, {'id': dashboard_id}
    )
    if not status:
        return internal_server_error(
            errormsg=gettext("Error: {}".format(msg))
        )

    return make_json_response(
        success=1,
        info=gettext("Dashboard(s) deleted successfully.")
    )


@blueprint.route("/dashboard_list", endpoint='dashboard_list')
@login_required
@pem_connection
@utils.manageDashboardRole.check_role(
    gettext("Logged-in user do not have permission to fetch the dashboards.")
)
def dashboard_list(pem_conn=None):
    """Listing custom dashboards."""

    sql = render_template("custom_dashboard/sql/dashboard_list.sql")
    status, res = pem_conn.execute_dict(sql)

    if not status:
        return internal_server_error(errormsg=res)

    return ajax_response(
        response={
            'custom_dashboards': res['rows']
        }, status=200
    )


@blueprint.route("/role_list", endpoint='role_list')
@login_required
@pem_connection
@utils.manageDashboardRole.check_role(
    gettext("Logged-in user do not have permission to fetch the roles.")
)
def role_list(pem_conn=None):
    """Returns role list"""

    sql = render_template("custom_dashboard/sql/get_roles.sql")
    status, servers = pem_conn.execute_dict(sql)

    if not status:
        return internal_server_error(errormsg=servers)

    return make_json_response(
        data=servers['rows'],
        status=200
    )


@blueprint.route("/properties/<dashboard_id>", endpoint='properties')
@login_required
@pem_connection
@utils.manageDashboardRole.check_role(
    gettext("Logged-in user do not have permission to fetch the dashboard "
            "properties.")
)
def properties(dashboard_id, pem_conn=None):
    """Return a list of sections and charts for a given dashboard
        to be loaded into work area
        Parameters: dashboard_id - (must) Dashboard id."""
    status, res = utils.get_dashboard(pem_conn, dashboard_id, is_export=False)
    if not status:
        return False, res

    return ajax_response(
        response=res,
        status=200)


@blueprint.route("/chart_list/<level>", endpoint='chart_list')
@login_required
@pem_connection
@utils.manageDashboardRole.check_role(
    gettext("Logged-in user do not have permission to fetch the dashboard "
            "charts.")
)
def chart_list(level=None, pem_conn=None):
    """Return a list of charts for the dashboard created by current_user."""

    sql = render_template("custom_dashboard/sql/chart_list.sql")
    status, charts = pem_conn.execute_dict(sql, {'level': level})

    if not status:
        return internal_server_error(errormsg=charts)

    if 'rows' in charts:
        for ch in charts['rows']:
            if (ch['description'] is None or ch['description'] == '') and \
                    (ch['cid'] in SYSTEM_CHART_DESCRIPTIONS):
                ch['description'] = SYSTEM_CHART_DESCRIPTIONS[ch['cid']]
            ch['metrices'] = '</br>'.join(ch['metrices']) if\
                ch['metrices'] is not None else ''
            ch['level'] = ", ".join(ch["level"])

    return ajax_response(
        response=charts['rows'],
        status=200)


def validate_request(f):
    from functools import wraps

    @wraps(f)
    def wrap(*args, **kwargs):
        if request.data:
            request.data = json.loads(request.data.decode())
        else:
            request.data = request.args or request.form

        status, data = utils.validate_dashboard_request_data(request.data)
        if not status:
            return make_json_response(
                status=410,
                success=0,
                errormsg=data
            )
        request.data = data
        return f(*args, **kwargs)

    return wrap


@blueprint.route("/create", methods=['post'], endpoint='create')
@login_required
@pem_connection
@validate_request
@utils.manageDashboardRole.check_role(
    gettext("Logged-in user do not have permission to create the dashboard.")
)
def create(pem_conn=None):
    """Creates a dashboard information
        Parameters:
            id    - (must) Dashboard id
            name - (must) Dashboard title
            descp - (must) Dashboard description
            level - (must) Dashboard level
            shared - (must) Teams/roles to share the dashboard with.
            font  - (must) font type
            font size - (must) font size
            is_ops - (must) dashboard type
            show_title - (must) show dashboard title
            design_layout - chart selection section wise"""

    status, did = utils.save_dashboard(pem_conn, request.data)
    if not status:
        return internal_server_error(errormsg=did)
    return make_json_response(
        data={'id': did},
        status=200
    )


@blueprint.route("/update", methods=['put'])
@login_required
@pem_connection
@validate_request
@utils.manageDashboardRole.check_role(
    gettext("Logged-in user do not have permission to update the dashboard.")
)
def update(pem_conn=None):
    """Updates a dashboard information
        Parameters:
            id    - (must) Dashboard id
            name - (must) Dashboard title
            descp - (must) Dashboard description
            level - (must) Dashboard level
            shared - (must) Teams/roles to share the dashboard with.
            font  - (must) font type
            font size - (must) font size
            is_ops - (must) dashboard type
            show_title - (must) show dashboard title
            design_layout - chart selection section wise"""

    data = request.data

    params = dict()
    params['id'] = data['id']
    params['title'] = data['name']
    params['descp'] = data['descp']
    params['shared'] = data['teams']
    params['font'] = data['font']
    params['font_size'] = data['font_size']
    params['is_ops'] = data['is_ops']
    params['show_title'] = data['show_title']

    pem_conn.execute_void("BEGIN;")

    sql = render_template("custom_dashboard/sql/update.sql")
    status, msg = pem_conn.execute_void(sql, params)

    if not status:
        pem_conn.execute_void('ROLLBACK;')
        return internal_server_error(errormsg=msg)

    did = data['id']

    sql = render_template("custom_dashboard/sql/delete_section.sql")
    status, msg = pem_conn.execute_void(sql, [did])

    if not status:
        pem_conn.execute_void('ROLLBACK;')
        return internal_server_error(errormsg=msg)

    for dl in data['design_layout']:
        can_sec_add = False
        if len(dl['charts']) > 0:
            for c in dl['charts']:
                if 'chart_id' in c and c['chart_id'] is not None \
                        and c['chart_id'] > 0:
                    can_sec_add = True
                    break

            if can_sec_add:
                sec_params = [dl['sec_id'], did, dl['sec_title']]
                sql = render_template("custom_dashboard/sql/store_section.sql")
                status, section = pem_conn.execute_void(sql, sec_params)

                if not status:
                    pem_conn.execute_void('ROLLBACK;')
                    return internal_server_error(errormsg=section)

                for c in dl['charts']:
                    if 'chart_id' in c and c['chart_id'] is not None\
                            and c['chart_id'] > 0:
                        chart_params = [did, dl['sec_id'],
                                        c['chart_id'], c['chart_idx'],
                                        c['chart_size'], c['chart_align'],
                                        c['chart_legend'],
                                        c['chart_show_title']]

                        sql = render_template(
                            "custom_dashboard/sql/store_section_chart.sql")
                        status, chart = pem_conn.execute_void(sql,
                                                              chart_params)

                        if not status:
                            pem_conn.execute_void('ROLLBACK;')
                            return internal_server_error(errormsg=chart)

    status, msg = pem_conn.execute_void("COMMIT;")

    if not status:
        pem_conn.execute_void('ROLLBACK;')
        return internal_server_error(errormsg=msg)

    return make_json_response(
        data={'id': data['id']},
        status=200
    )


@blueprint.route("/export", methods=['post'], endpoint='custom_export')
@login_required
@pem_connection
@utils.manageDashboardRole.check_role(
    gettext("Logged-in user do not have permission to export the dashboard.")
)
def custom_export(pem_conn=None):
    """
    :param pem_conn: pem connection object
    """
    if request.data:
        data = json.loads(request.data.decode())
    else:
        data = request.args or request.form

    dashboards = data.get('dashboards', [])
    if len(dashboards) == 0:
        return bad_request(
            errormsg=gettext("No charts to dashboards")
        )

    status, result = utils.generate_export_dashboard_data(
        pem_conn, dashboards)
    if not status:
        return internal_server_error(errormsg=result)

    # ========================= IMPORTANT NOTE =========================
    # Here we will add Export "version" key for compatibility check
    # we need to update the "VALID_EXPORT_VERSIONS" variables
    # in the utils.py when there is a change in chart, probe schema which can
    # break the import/export logic, we will check this version while
    # importing the chart, probes from json file
    # ==================================================================
    resp = Response(
        json.dumps({
            "version": CURRENT_EXPORT_VERSION,
            "dashboards": result
        }),
        mimetype='application/json'
    )

    return resp


@blueprint.route("/import", methods=['post'], endpoint='custom_import')
@login_required
@pem_connection
@utils.manageDashboardRole.check_role(
    gettext("Logged-in user do not have permission to import the dashboard.")
)
def custom_import(pem_conn=None):
    """
    :param pem_conn: pem connection object
    """
    if request.data:
        data = json.loads(request.data.decode())
    else:
        data = request.args or request.form

    # Verify the request
    if 'content' not in data or 'dashboards' not in data['content'] or \
            not isinstance(data['content']['dashboards'], list) or \
            len(data['content']['dashboards']) == 0 or \
            'skip_overwrite' not in data or \
            'skip_overwrite_probe' not in data:
        return bad_request(
            errormsg=gettext("Please provide valid JSON file")
        )

    # Check if export version is supported
    if 'version' not in data['content'] or not data['content']['version']:
        return bad_request(
            errormsg=gettext("Unable to verify the export version")
        )

    if not is_export_version_supported(data['content']['version']):
        return bad_request(
            errormsg=gettext(
                "The JSON file is incompatible with current version of PEM,"
                " the import is supported from following"
                " schema version(s) - {}".format(", ".join(
                    str(sv) for sv in
                    get_import_schema_version(CURRENT_EXPORT_VERSION)
                ))
            )
        )
    skip_overwrite = data['skip_overwrite']
    skip_overwrite_chart = data['skip_overwrite_chart']
    skip_overwrite_probe = data['skip_overwrite_probe']

    result = utils.insert_imported_dashboards(
        pem_conn,
        data['content']['dashboards'],
        skip_overwrite,
        skip_overwrite_chart,
        skip_overwrite_probe
    )

    return make_json_response(result=result)
