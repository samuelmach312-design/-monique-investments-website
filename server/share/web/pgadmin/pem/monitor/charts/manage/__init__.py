##########################################################################
#
# Postgres Enterprise Manager
#
# Copyright (C) 2016 - 2025, EnterpriseDB Corporation. All rights reserved.
#
##########################################################################

"""Implements Manage Charts"""

import copy
import json

from flask import render_template, request, Response, url_for
from flask_babel import gettext
from flask_security import login_required

import pgadmin.browser.server_groups as sg
from pgadmin.pem.monitor.utils import DashboardLevel
from pgadmin.pem.utils import pem_connection, csv_split
from pgadmin.utils import PgAdminModule
from pgadmin.utils.ajax import internal_server_error, bad_request, \
    gone, make_response as ajax_response, make_json_response
from pgadmin.pem.monitor.utils.import_export import CURRENT_EXPORT_VERSION, \
    get_pem_installation_id, is_export_version_supported, \
    get_import_schema_version
from . import utils, api

MODULE_NAME = 'manage_charts'
GET_CHART_CATEGORY_SQL = 'manage/sql/get_chart_category.sql'
ERROR_MSG_FOR_REQUIRED_PARAMS = \
    "Could not find the required parameter chart metrics."


class ManageChartsModule(PgAdminModule):
    """
    class ManageChartModule(Object):

        Inherits PgAdminModule class and define
        methods to load its own javascript/css files.
    """

    LABEL = gettext('Manage Charts')

    def get_own_stylesheets(self):
        """
        Returns:
            list: the stylesheets used by this module.
        """
        stylesheets = [
            url_for('manage_charts.static', filename='css/manage_charts.css'),
            url_for('manage_charts.index') + 'manage_charts.css'
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
            'manage_charts.import_cm_report_as_chart', 'manage_charts.create',
            'manage_charts.update', 'manage_charts.capacity_templates',
            'manage_charts.category_list', 'manage_charts.metrics_list',
            'manage_charts.role_list', 'manage_charts.properties',
            'manage_charts.chart_list', 'manage_charts.delete',
            'manage_charts.custom_export', 'manage_charts.custom_import'
        ]


# Create blueprint for Manage Chart class
blueprint = ManageChartsModule(
    MODULE_NAME, __name__, url_prefix='/pem/manage_charts')


@blueprint.route("/")
@login_required
def index():
    return bad_request(errormsg=gettext(
        "This URL cannot be called directly!")
    )


@blueprint.route("/create_charts.js")
@login_required
def create_chart_script():
    """Render own javascript"""
    return Response(
        response=render_template(
            "manage/js/create_charts.js",
            DashboardLevel=DashboardLevel
        ),
        status=200,
        mimetype="application/javascript"
    )


@blueprint.route("/manage_charts.css")
@login_required
def manage_charts_css():
    """Render css template"""
    return Response(
        render_template('manage/css/manage_charts.css'),
        200, {'Content-Type': 'text/css'}
    )


@blueprint.route("/delete", methods=['POST'], endpoint='delete')
@login_required
@pem_connection
@utils.manageChartRole.check_role(
    gettext("Logged-in user do not have permission to delete the chart.")
)
def delete(pem_conn=None):
    """Delete a chart"""
    if request.data:
        data = json.loads(request.data.decode())
    else:
        data = request.args or request.form

    if 'charts' not in data or not isinstance(data['charts'], list):
        return internal_server_error(
            errormsg=gettext("Invalid request parameters")
        )

    chart_ids = []
    for row in data['charts']:
        chart_ids.append(row['id'])

    if len(chart_ids) == 0:
        return internal_server_error(
            errormsg=gettext("Please provide correct chart to delete")
        )
    placeholders = ', '.join(['%s'] * len(chart_ids))
    sql = f"UPDATE pem.chart SET deleted = true WHERE id IN ({placeholders})"
    status, msg = pem_conn.execute_void(sql, chart_ids)
    if not status:
        return internal_server_error(
            errormsg=gettext("Error: {}".format(msg))
        )

    return make_json_response(
        success=1,
        info=gettext("Chart(s) deleted successfully.")
    )


@blueprint.route("/list", methods=['get', 'post'], endpoint='chart_list')
@login_required
@pem_connection
@utils.manageChartRole.check_role(
    gettext("Logged-in user do not have permission to fetch the charts.")
)
def chart_list(pem_conn=None):
    """Listing charts."""

    SQL = render_template("manage/sql/chart_list.sql")
    status, charts = pem_conn.execute_dict(SQL)

    if not status:
        return internal_server_error(errormsg=charts)

    return ajax_response(
        response={
            'custom_charts': charts['rows']
        }, status=200
    )


@blueprint.route("/properties/<cid>", methods=['GET'], endpoint='properties')
@login_required
@pem_connection
@utils.manageChartRole.check_role(
    gettext("Logged-in user do not have permission to fetch the chart.")
)
def properties(cid, pem_conn=None):
    """Returns a chart properties."""
    status, details = utils.get_chart(pem_conn, cid)
    if not status:
        return internal_server_error(errormsg=details)
    return ajax_response(response=details, status=200)


def validate_request(f):
    from functools import wraps

    @wraps(f)
    def wrap(*args, **kwargs):
        if request.data:
            request.data = json.loads(request.data.decode())
        else:
            request.data = request.args or request.form

        status, res = utils.validate_charts_data(request.data)
        if not status:
            return make_json_response(
                status=410,
                success=0,
                errormsg=res
            )
        return f(*args, **kwargs)

    return wrap


@blueprint.route("/update", methods=['put'], endpoint='update')
@login_required
@pem_connection
@validate_request
@utils.manageChartRole.check_role(
    gettext("Logged-in user do not have permission to update the chart.")
)
def update(pem_conn=None):
    """Update a chart"""

    status, chart_data = utils.get_and_save_chart_category(
        pem_conn, request.data)

    # Update a chart
    sql = render_template("manage/sql/update_chart.sql")

    cparams = [chart_data['cat_id'],
               chart_data['chart_title'],
               chart_data['chart_description'],
               chart_data['teams'],
               chart_data['reload'],
               chart_data['id']
               ]

    status, msg = pem_conn.execute_void(sql, cparams)
    chart_data['chart_id'] = chart_data['id']

    if not status:
        pem_conn.execute_void('ROLLBACK;')
        return internal_server_error(errormsg=msg)

    status, res = utils.save_chart_metrics(pem_conn, chart_data)
    if not status:
        return internal_server_error(errormsg=res)
    return make_json_response(
        data={'id': chart_data['chart_id']},
        status=200
    )


@blueprint.route("/create", methods=['post'], endpoint='create')
@login_required
@pem_connection
@validate_request
@utils.manageChartRole.check_role(
    gettext("Logged-in user do not have permission to create the chart.")
)
def create(pem_conn=None):
    """Add a chart"""

    status, chart_data = utils.get_and_save_chart_category(
        pem_conn, request.data)
    if not status:
        return internal_server_error(errormsg=chart_data)

    status, chart_data = utils.save_chart(pem_conn, chart_data)
    if not status:
        return internal_server_error(errormsg=chart_data)

    status, res = utils.save_chart_metrics(pem_conn, chart_data)
    if not status:
        return internal_server_error(errormsg=res)
    return make_json_response(
        data={'id': chart_data['chart_id']},
        status=200
    )


@blueprint.route("/category_list", endpoint='category_list')
@login_required
@pem_connection
@utils.manageChartRole.check_role(
    gettext("Logged-in user do not have permission to fetch the category.")
)
def category_list(pem_conn=None):
    """Returns a metric category list"""

    sql = render_template(GET_CHART_CATEGORY_SQL)
    status, servers = pem_conn.execute_dict(sql)

    if not status:
        return internal_server_error(errormsg=servers)

    return make_json_response(
        data=servers['rows'],
        status=200
    )


@blueprint.route("/role_list", endpoint='role_list')
@login_required
@pem_connection
@utils.manageChartRole.check_role(
    gettext("Logged-in user do not have permission to fetch the roles.")
)
def role_list(pem_conn=None):
    """Returns role list"""

    sql = render_template("manage/sql/get_roles.sql")
    status, servers = pem_conn.execute_dict(sql)

    if not status:
        return internal_server_error(errormsg=servers)

    return make_json_response(
        data=servers['rows'],
        status=200
    )


@blueprint.route("/metrics_list/<chart_type>/<level>", endpoint='metrics_list')
@login_required
@pem_connection
@utils.manageChartRole.check_role(
    gettext("Logged-in user do not have permission to fetch the metrics.")
)
def metrics_list(chart_type='L', level=100, pem_conn=None):
    """Return a list of metrics to generate a chart."""

    sql = render_template(
        "manage/sql/get_metrics_list.sql",
        chart_type=chart_type,
        level=level
    )
    status, metrics = pem_conn.execute_2darray(sql)

    if not status:
        return internal_server_error(errormsg=metrics)

    cnt = len(metrics['rows'])
    metrics = metrics['rows']
    probe_metrics_cols = [
        'metric_id', 'metric_internal_name', 'metric_display_name',
        'calculate_pit', 'discard_history', 'pit_by_default',
        'is_graphable'
    ]
    levels = [100, 200, 300, 400]

    res = []
    probe = None
    for num in range(0, cnt):
        if (not probe) or metrics[num]['id'] != probe.get('id'):
            probe = copy.deepcopy(metrics[num])
            probe['icon'] = 'icon-metrics'
            probe['inode'] = True
            probe['load'] = False
            probe['radio'] = True

            res.append(probe)
            probe['grouped'] = {
                levels[i]: v for i, v in enumerate(metrics[num]['grouped'])
            }

            # We don't want these parameters in probe itself, but only in
            # metrics list
            for p in probe_metrics_cols:
                del probe[p]

            probe['branch'] = []
            probe['order_by'] = []

        tmp = metrics[num]
        if chart_type == 'L' and tmp['is_graphable']:
            if tmp['pit_by_default']:
                probe['branch'].append(tmp)
            else:
                if tmp['calculate_pit']:
                    tmp['pit'] = True
                    probe['branch'].append(tmp)
                tmp1 = copy.deepcopy(tmp)
                tmp1['pit'] = False
                tmp1['label'] = (tmp1['label'] + '+')

                probe['branch'].append(tmp1)
        elif chart_type == 'TB':
            if not tmp['is_graphable'] or tmp['pit_by_default']:
                probe['branch'].append(tmp)
            else:
                if tmp['calculate_pit']:
                    tmp['pit'] = True
                    probe['branch'].append(tmp)
                tmp1 = copy.deepcopy(tmp)
                tmp1['pit'] = False
                tmp1['label'] = (tmp1['label'] + '+')

                probe['branch'].append(tmp1)

        probe['order_by'].append(tmp)

    final_res = res[:]
    for r in res:
        if len(r['branch']) == 0:
            final_res.remove(r)

    return make_json_response(
        data=final_res,
        status=200
    )


@blueprint.route("/capacity_templates", endpoint='capacity_templates')
@login_required
@pem_connection
@utils.manageChartRole.check_role(
    gettext("Logged-in user do not have permission to fetch the "
            "capacity manager templates.")
)
def capacity_templates(pem_conn=None):
    """Return a list of capacity manager templates."""

    sql = render_template("manage/sql/get_cm_template_list.sql")
    status, templates = pem_conn.execute_dict(sql)

    if not status:
        return internal_server_error(errormsg=templates)

    tmpls = []
    for t in templates['rows']:
        if t['template_id'] is not None:
            tmpls.append({'label': t['title'] + "." + t['template_name'],
                          'value': t['template_id']})

    return make_json_response(
        data=tmpls,
        status=200
    )


@blueprint.route("/import_cm_report_as_chart/<tid>",
                 endpoint='import_cm_report_as_chart')
@login_required
@pem_connection
@utils.manageChartRole.check_role(
    gettext("Logged-in user do not have permission to import the "
            "capacity manager template.")
)
def import_cm_report_as_chart(tid=0, pem_conn=None):
    """Returns the category chart template details."""

    tid = int(tid)
    if tid <= 0:
        return internal_server_error(
            gettext('Please provide valid template id'))

    sql = render_template("manage/sql/get_cm_template.sql")
    status, rs = pem_conn.execute_dict(sql, [tid])

    if not status:
        return internal_server_error(errormsg=gettext(rs))

    rs = rs['rows']
    if len(rs) == 0:
        return internal_server_error(
            gettext("The capacity report template is no longer exist!")
        )

    CM_RES_CATEGORYID = 'folder_id'
    # CM_RES_CATEGORY = 'chart_category'
    CM_RES_HISTORY = 'historical_days'
    CM_RES_EXTRAPOLATED = 'extrapolated_days'
    CM_RES_MID = 'metric_idx'
    CM_RES_TVAL = 'tval'
    CM_LEVEL = 'chart_level'
    SHARED = 'shared_all'

    obj = rs[0]
    obj[CM_LEVEL] = gettext('Capacity Report Chart')
    obj[SHARED] = True

    obj[CM_RES_HISTORY] = int(obj[CM_RES_HISTORY]) if\
        obj[CM_RES_HISTORY] is not None else obj[CM_RES_HISTORY]
    if (obj[CM_RES_EXTRAPOLATED] is not None):
        obj[CM_RES_EXTRAPOLATED] = int(obj[CM_RES_EXTRAPOLATED]) if\
            obj[CM_RES_EXTRAPOLATED] is not None else obj[CM_RES_EXTRAPOLATED]
    if (obj[CM_RES_MID] is not None):
        obj[CM_RES_MID] = int(obj[CM_RES_MID]) if\
            obj[CM_RES_MID] is not None else obj[CM_RES_MID]
    if (obj[CM_RES_TVAL] is not None):
        obj[CM_RES_TVAL] = float(obj[CM_RES_TVAL]) if\
            obj[CM_RES_TVAL] is not None else obj[CM_RES_TVAL]
    del (obj[CM_RES_CATEGORYID])

    sql = render_template("manage/sql/get_cm_metrics.sql")
    status, res = pem_conn.execute_dict(sql, [tid])

    if not status:
        return internal_server_error(errormsg=res)

    res = res['rows']

    for idx in range(0, len(res)):
        res[idx]['params'] = csv_split(
            res[idx]['metric_target_attributes'], delimiter=',', quotechar='"'
        )[0]
        res[idx]['vals'] = csv_split(
            res[idx]['metric_target_values'], delimiter=',', quotechar='"'
        )[0]
        res[idx]['mid'] = int(res[idx]['id'])
        res[idx]['metric_query_type'] = int(res[idx]['metric_query_type'])
        res[idx]['metric_id'] = int(res[idx]['metric_id'])
        res[idx]['deleted'] = True if res[idx]['deleted'] == 't' else False

        # If count of target_attributes do not match with count of
        # target_values then there might be some issue with the given cm
        # template and hence throw an error.
        # Note: This case will only come in case of cm templates created by
        # user on PEM v3.0.1 and prior for very special cases where
        # an object (database, schema, function, etc.) name contains
        # special characters like (, ; " ')
        if len(res[idx]['vals']) != len(res[idx]['params']):
            return internal_server_error(gettext(
                "Capacity manager template '{0}' could not be loaded as"
                " this template is not compatible with custom charts."
            ).format(obj['chart_title']))

    obj['sel_metrics_C'] = res

    return ajax_response(response=obj, status=200)


@blueprint.route("/export", methods=['post'], endpoint='custom_export')
@login_required
@pem_connection
@utils.manageChartRole.check_role(
    gettext("Logged-in user do not have permission to export the charts.")
)
def custom_export(pem_conn=None):
    """
    :param pem_conn: pem connection object
    """
    if request.data:
        data = json.loads(request.data.decode())
    else:
        data = request.args or request.form

    charts = data.get('charts', [])
    if len(charts) == 0:
        return bad_request(
            errormsg=gettext("No charts to export")
        )

    status, result = utils.generate_export_chart_data(
        pem_conn, charts)
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
            "charts": result
        }),
        mimetype='application/json'
    )

    return resp


@blueprint.route("/import", methods=['post'], endpoint='custom_import')
@login_required
@pem_connection
@utils.manageChartRole.check_role(
    gettext("Logged-in user do not have permission to import the charts.")
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
    if 'content' not in data or 'charts' not in data['content'] or \
            not isinstance(data['content']['charts'], list) or \
            len(data['content']['charts']) == 0 or \
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
    skip_overwrite_probe = data['skip_overwrite_probe']

    result = utils.insert_imported_charts(
        pem_conn, data['content']['charts'],
        skip_overwrite, skip_overwrite_probe
    )

    return make_json_response(result=result)
