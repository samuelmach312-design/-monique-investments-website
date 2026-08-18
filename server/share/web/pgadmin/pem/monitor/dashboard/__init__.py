##########################################################################
#
# Postgres Enterprise Manager
#
# Copyright (C) 2016 - 2025, EnterpriseDB Corporation. All rights reserved.
#
##########################################################################

"""Implements Global Dashboard"""

from flask import render_template, current_app
from flask_babel import gettext
from pgadmin.utils import PgAdminModule
from pgadmin.utils.csrf import pgCSRFProtect
from pgadmin.utils.menu import Panel
from flask import Response, url_for
from flask_security import login_required
import json
from .helpers.chart import enable_chart_dep_probes
from .helpers.settings import dashboard_set_settings

# Load logs
from .utils.homepage_headers import dashboard_info
from .utils.tablecharts import table_audit_logs, \
    table_server_logs, table_probe_logs
import config
from pgadmin.pem.utils import pem_connection, is_edb_server, \
    is_remotely_monitored_server, get_server_agent, is_db_excluded
from pgadmin.utils.ajax import internal_server_error, \
    bad_request, make_json_response
from .utils.html import PEMDashboards
from .utils import cancel_dashboard
from pgadmin.pem.monitor.utils import DashboardLevel, getTableInfo
from pgadmin.pem.monitor.utils.charts import ChartType, \
    SYSTEM_CHART_DESCRIPTIONS
from .helpers.group_chart import get_chart_metadata, group_chart_data
from pgadmin.pem.monitor.dashboard.utils.menu import get_breadcrumb_data, \
    convert_menu_namedtuple_as_dict
from pgadmin.pem.monitor.dashboard.utils.html import PEMPredefinedDashboards

MODULE_NAME = 'pem_dashboard'

# Set Header
PEM_HEADER_TYPE = "application/xhtml+xml; charset=utf-8"

# Set Response Type
config.PEM_SCRIPT_TYPE = "html"

DASH_LEVELS = {
    '50': 'system',
    '100': 'agent',
    '200': 'server',
    '300': 'database'
}


class PEMDashboardModule(PgAdminModule):
    """
    class PEMDashboardModule(Object):

        It is a wizard which inherits PgAdminModule
        class and define methods to load its own
        javascript file.
    """

    LABEL = gettext('Global Dashboard')

    def __init__(self, *args, **kwargs):
        super(PEMDashboardModule, self).__init__(*args, **kwargs)

    def get_own_stylesheets(self):
        """
        Returns:
            list: the stylesheets used by this module.
        """
        stylesheets = [
            url_for('pem_dashboard.index') + 'dashboard.css'
        ]
        return stylesheets

    def get_panels(self):
        return [
            Panel(
                name='pnl_dashboard',
                priority=1,
                title=gettext('Monitoring'),
                content='',
                is_closeable=False,
                is_private=True,
                is_iframe=True
            ).__dict__
        ]

    def get_exposed_url_endpoints(self):
        """
        Returns:
            list: a list of url endpoints exposed to the client.
        """
        return [
            'pem_dashboard.index',
            'pem_dashboard.list',
            'pem_dashboard.system_level_dashboard',
            'pem_dashboard.agent_level_dashboard',
            'pem_dashboard.server_level_dashboard',
            'pem_dashboard.database_level_dashboard',
            'pem_dashboard.custom',
            'pem_dashboard.close',
            'pem_dashboard.system_info',
            'pem_dashboard.agent_info',
            'pem_dashboard.server_info',
            'pem_dashboard.database_info',
            'pem_dashboard.server_logs_for_system',
            'pem_dashboard.server_logs_for_agent',
            'pem_dashboard.server_logs_for_server',
            'pem_dashboard.probe_logs_for_agent',
            'pem_dashboard.audit_logs_for_system',
            'pem_dashboard.audit_logs_for_agent',
            'pem_dashboard.audit_logs_for_server',
            'pem_dashboard.set_dashboard_settings',
            'pem_dashboard.bdr_worker_details',
            'pem_dashboard.bdr_worker_error_details'
        ]


# Create blueprint for Dashboard Module
blueprint = PEMDashboardModule(
    MODULE_NAME, __name__, static_url_path='',
    url_prefix='/monitoring/dashboard'
)


@blueprint.route("/dashboards.js")
@pgCSRFProtect.exempt
def dashboards_js():
    # Prepare a dict containing dashboards by levels
    # such as System, Agent, Server, Database etc.
    # It is used to create menu items.
    dash_list = custom_dash_by_levels()
    import copy
    dashboards = copy.deepcopy(PEMDashboards.sys_dashboards)
    new_dashboards = dict()
    for level in dashboards:
        level_label = DASH_LEVELS[str(level)]
        temp = dict()
        temp[level_label] = dict()
        for pre_dash in dashboards[level]:
            dash_obj = PEMDashboards.dashboards[pre_dash]
            temp[level_label][pre_dash] = dash_obj
        new_dashboards[level_label] = temp[level_label]
        z = new_dashboards[level_label].copy()
        z.update(dash_list[str(level)])
        new_dashboards[level_label] = z

    return Response(
        response="""
define('pem.monitor.dashboard.list', [], function() {{ return {0}; }});
        """.format(json.dumps(new_dashboards)),
        mimetype="application/javascript",
    )


@blueprint.route("/list", endpoint='list')
@pgCSRFProtect.exempt
@login_required
@pem_connection
def dashboard_list(pem_conn=None):
    """List the dashboards"""

    # Prepare a dict containing dashboards by levels
    # such as System, Agent, Server, Database etc.
    # It is used to create menu items.
    dash_list = custom_dash_by_levels()
    import copy
    dashboards = copy.deepcopy(PEMDashboards.sys_dashboards)
    # Add Global Dashobard with id 1 in system menus
    dashboards[50].add(1)
    new_dashboards = dict()
    for level in dashboards:
        level_label = DASH_LEVELS[str(level)]
        temp = dict()
        temp[level_label] = dict()
        for pre_dash in dashboards[level]:
            dash_obj = PEMDashboards.dashboards[pre_dash]
            if level == 50 and pre_dash == 1:
                dash_obj['title'] = gettext("Global Overview")
            temp[level_label][pre_dash] = dash_obj
        new_dashboards[level_label] = temp[level_label]
        z = new_dashboards[level_label].copy()
        z.update(dash_list[str(level)])
        new_dashboards[level_label] = z

    return make_json_response(
        data=new_dashboards
    )


@blueprint.route("/levels.js", endpoint='levels')
@pgCSRFProtect.exempt
def levels_js():
    return Response(
        response="""
define('pem.monitor.dashboard.levels', [], function() {{ return {0}; }});
        """.format(json.dumps({
            k: getattr(DashboardLevel, k, 0) for k in DashboardLevel.levels
        })),
        mimetype="application/javascript",
    )


@blueprint.route("/dashboard.css")
@pgCSRFProtect.exempt
@login_required
def dashboard_css():
    """Render css template"""
    return Response(
        render_template('dashboard/css/dashboard.css'),
        200, {'Content-Type': 'text/css'}
    )


@blueprint.route("/", methods=['get'], endpoint='index')
@login_required
def index():
    return bad_request(
        errormsg=gettext('This URL cannot be requested directly.')
    )


def render_dashboard(content, menu_content, context, info):
    return render_template(
        '/dashboard/html/dashboard.html',
        content=content,
        menu_content=convert_menu_namedtuple_as_dict(menu_content),
        context=context,
        info=info,
        dashboard_title=content['title']
    )


@blueprint.route(
    "/<int:did>", methods=['get'], endpoint="system_level_dashboard"
)
@blueprint.route(
    "/<int:did>/<int:trans_id>", methods=['get'],
    endpoint="system_level_dashboard_with_trans_id"
)
@pgCSRFProtect.exempt
@pem_connection
def system_level_dashboard(did, trans_id=0, pem_conn=None):
    """
    This function fetches and return system level dashboard
    :param did: database id
    :type did: int
    :param trans_id: transaction id
    :type trans_id: int
    :param pem_conn: pem database connection
    :type pem_conn: database connection object
    :return: dashboard info and content
    :rtype: html template
    """
    info = dashboard_info(pem_conn, did)
    content = get_dashboard_content(DashboardLevel.DB_GLOBAL, did, pem_conn)

    if info is None:
        return bad_request(
            errormsg=gettext('Dashboard info not found')
        )

    if content is None:
        return bad_request(
            errormsg=gettext('Dashboard not found')
        )

    menu_content = get_breadcrumb_data(DashboardLevel.DB_GLOBAL)

    if trans_id == 0:
        trans_id = info['generated']

    info["context"] = dict({
        'level': DashboardLevel.DB_GLOBAL,
        'did': did,
        'trans_id': trans_id
    })
    return make_json_response(
        data={
            'dashboard_content': content,
            'info': info,
            'menu_content': menu_content,
        }
    )


@blueprint.route(
    "/os/agent/<int:aid>/<int:trans_id>", methods=['get']
)
@pgCSRFProtect.exempt
def operating_system_dashboard(aid, trans_id):
    from flask import redirect, url_for
    return redirect(
        url_for(
            'pem_dashboard.agent_level_dashboard_with_transid',
            aid=aid, trans_id=trans_id, did=PEMPredefinedDashboards.OS
        )
    )


@blueprint.route(
    "/<int:did>/agent/<int:aid>", methods=['get'],
    endpoint="agent_level_dashboard"
)
@blueprint.route(
    "/<int:did>/<int:trans_id>/agent/<int:aid>", methods=['get'],
    endpoint="agent_level_dashboard_with_transid"
)
@pgCSRFProtect.exempt
@pem_connection
def agent_level_dashboard(did, aid=None, trans_id=0, pem_conn=None):
    info = dashboard_info(pem_conn, did, agent_id=aid)
    content = get_dashboard_content(DashboardLevel.DB_AGENT, did, pem_conn)

    if content is None:
        return bad_request(
            errormsg=gettext('Dashboard not found')
        )
    menu_content = get_breadcrumb_data(DashboardLevel.DB_AGENT, aid=aid)

    if trans_id == 0:
        trans_id = info['generated']

    info["context"] = dict({
        'level': DashboardLevel.DB_AGENT,
        'did': did,
        'trans_id': trans_id,
        'aid': aid,
    })
    return make_json_response(
        data={
            'dashboard_content': content,
            'info': info,
            'menu_content': menu_content,
        }
    )


@blueprint.route(
    "/server/server/<int:sid>/<int:trans_id>", methods=['get']
)
@pgCSRFProtect.exempt
def server_dashboard(sid, trans_id):
    from flask import redirect, url_for
    return redirect(
        url_for(
            'pem_dashboard.server_level_dashboard_with_transid',
            sid=sid, trans_id=trans_id, did=PEMPredefinedDashboards.SERVER
        )
    )


@blueprint.route(
    "/<int:did>/server/<int:sid>", methods=['get'],
    endpoint="server_level_dashboard"
)
@blueprint.route(
    "/<int:did>/<int:trans_id>/server/<int:sid>", methods=['get'],
    endpoint="server_level_dashboard_with_transid"
)
@pgCSRFProtect.exempt
@pem_connection
def server_level_dashboard(did, sid=None, trans_id=0, pem_conn=None):
    info = dashboard_info(pem_conn, did, server_id=sid)
    content = get_dashboard_content(DashboardLevel.DB_SERVER, did, pem_conn)

    if content is None:
        return bad_request(
            errormsg=gettext('Dashboard not found')
        )

    aid = get_server_agent(pem_conn, sid)
    is_edb = is_edb_server(pem_conn, sid)
    is_remotely_monitored = is_remotely_monitored_server(pem_conn, sid)

    menu_content = get_breadcrumb_data(
        DashboardLevel.DB_SERVER, aid=aid, sid=sid, is_edb=is_edb,
        is_remotely_monitored=is_remotely_monitored
    )

    if trans_id == 0:
        trans_id = info['generated']

    info["context"] = dict({
        'level': DashboardLevel.DB_SERVER,
        'did': did,
        'trans_id': trans_id,
        'aid': aid,
        'sid': sid,
        'is_edb': is_edb,
        'is_remotely_monitored': is_remotely_monitored
    })
    return make_json_response(
        data={
            'dashboard_content': content,
            'info': info,
            'menu_content': menu_content,
        }
    )


def get_dashboard_content(level, did, pem_conn):
    dashboard = PEMDashboards.getSystemDashboard(level, did)

    if dashboard is None:
        sql = render_template(
            '/dashboard/sql/content.sql',
            did=did
        )
        status, res = pem_conn.execute_dict(sql)

        if not status:
            current_app.logger.error(res)
            return None

        if len(res['rows']) == 0:
            return None

        for row in res['rows']:
            dashboard = json.loads(row['dashboard'])
            sections = dashboard.pop('sections', [])
            content = dashboard['content'] = []
            for section in sections:
                section['type'] = 'section'
                section['label'] = section.pop('title', '')
                charts = section.pop('charts', [])
                section['charts'] = []
                for chart in charts:
                    if chart.pop('deleted', False) is not True:
                        if level in chart['level']:
                            chart['level'] = level
                        else:
                            chart['level'] = max(chart['level'])
                        section['charts'].append(chart)
                content.append(section)

    if dashboard is not None:
        for content in dashboard["content"]:
            if "charts" in content:
                for chart in content["charts"]:
                    if chart["id"] in SYSTEM_CHART_DESCRIPTIONS:
                        chart["description"] = \
                            SYSTEM_CHART_DESCRIPTIONS[chart["id"]]
                    if chart["type"] in {
                        ChartType.TABLE,
                        ChartType.ALERT_DETAILS,
                        ChartType.ALERT_STATUS,
                        ChartType.PGD_WORKERS,
                        ChartType.AGENT_STATUS,
                        ChartType.SERVER_STATUS,
                        ChartType.ALERT_ERRORS,
                    }:
                        info = getTableInfo(chart["id"])

                        if info is not None:
                            chart["columns"] = info["columns"]
                            chart["label"] = info["label"]

        return dashboard

    return None


@blueprint.route(
    '/info/<int:did>', methods=['get'], endpoint="system_info"
)
@blueprint.route(
    '/info/<int:did>/agent/<int:aid>', methods=['get'], endpoint="agent_info"
)
@blueprint.route(
    '/info/<int:did>/server/<int:sid>', methods=['get'], endpoint="server_info"
)
@blueprint.route(
    '/info/<int:did>/server/<int:sid>/database/<database>', methods=['get'],
    endpoint="database_info"
)
@pem_connection
def fetch_system_info(
    did=None, aid=None, sid=None, database=None, pem_conn=None
):
    info = dashboard_info(
        pem_conn, did, agent_id=aid, server_id=sid, database=database
    )

    if info is None:
        return bad_request(gettext(
            "Failed to fetch the current system information."
        ))

    return make_json_response(
        status=200,
        success=1,
        data=info
    )


@blueprint.route(
    "/<int:did>/server/<int:sid>/database/<database>", methods=['get'],
    endpoint="database_level_dashboard"
)
@blueprint.route(
    "/<int:did>/<int:trans_id>/server/<int:sid>/database/<database>",
    methods=['get'],
    endpoint="database_level_dashboard_with_transid"
)
@pgCSRFProtect.exempt
@pem_connection
def database_level_dashboard(
    did, sid=None, database=None, trans_id=0, pem_conn=None
):
    info = dashboard_info(pem_conn, did, server_id=sid, database=database)
    content = get_dashboard_content(DashboardLevel.DB_DATABASE, did, pem_conn)

    if content is None:
        return bad_request(
            errormsg=gettext('Dashboard not found')
        )

    aid = get_server_agent(pem_conn, sid)
    is_edb = is_edb_server(pem_conn, sid)
    is_remotely_monitored = is_remotely_monitored_server(pem_conn, sid)

    menu_content = get_breadcrumb_data(
        DashboardLevel.DB_DATABASE, aid=aid, sid=sid, database=database,
        is_edb=is_edb, is_remotely_monitored=is_remotely_monitored
    )

    if trans_id == 0:
        trans_id = info['generated']

    info["context"] = dict({
        'level': DashboardLevel.DB_DATABASE,
        'did': did,
        'trans_id': trans_id,
        'aid': get_server_agent(pem_conn, sid),
        'sid': sid,
        'database': database,
        'is_edb': is_edb_server(pem_conn, sid),
        'is_db_excluded': is_db_excluded(pem_conn, sid, database),
        'is_remotely_monitored':
            is_remotely_monitored_server(pem_conn, sid)
    })
    return make_json_response(
        data={
            'dashboard_content': content,
            'info': info,
            'menu_content': menu_content,
        }
    )


@blueprint.route('/settings/<int:did>', methods=['POST'],
                 endpoint="set_dashboard_settings")
@login_required
def set_dashboard_settings(did):
    """Set the dashBoard settings."""
    return dashboard_set_settings(did)


@blueprint.route('/custom', methods=['get'])
@login_required
@pem_connection
def custom(pem_conn=None):
    """Return list of dashboards for:
        System,
        Agent,
        Server and
        Database levels
    """
    return make_json_response(
        status=200,
        success=1,
        data=custom_dash_by_levels()
    )


@login_required
@pem_connection
def custom_dash_by_levels(pem_conn=None):
    # Fetch list of custom and ops dashboards
    sql = render_template('dashboard/sql/custom_dashboards.sql')
    status, res = pem_conn.execute_dict(sql)
    if not status:
        return internal_server_error(errormsg=res)

    dash_list = dict()
    for dash_level in list(DASH_LEVELS.keys()):
        dash_list[dash_level] = {'custom': {},
                                 'ops': {}
                                 }

    for row in res['rows']:
        dash = dash_list[str(row['level'])]
        temp_dash = {
            "id": row['id'],
            "title": row["title"],
            "level": row['level']
        }
        if row['is_ops_dashboard']:
            dash['ops'][str(row['id'])] = temp_dash
        else:
            dash['custom'][str(row['id'])] = temp_dash

    return dash_list


@blueprint.route('/streaming_replication_data/<int:sid>', methods=['get'])
@login_required
@pem_connection
def streaming_replication_data(sid, pem_conn=None):
    """
    This function checks if data is available in any of the streaming
    replication table.
    Args:
        pem_conn: PEM connection object

    Returns: Returns the count if data is available in any of
        the streaming replication table.

    """
    sql = render_template('dashboard/sql/fetch_sr_data.sql')
    status, res = pem_conn.execute_scalar(sql, {'sid': sid})
    if not status:
        return internal_server_error(errormsg=res)

    return make_json_response(
        status=200,
        success=1,
        data=res
    )


@blueprint.route('/system_wait_dashboard/<int:sid>', methods=['GET'])
@blueprint.route('/session_wait_dashboard/<int:sid>', methods=['GET'])
@login_required
@pem_connection
def dashboard_availablity(sid, pem_conn=None):
    """
    Check if the EPAS server version for the given server ID is below 18.

    Args:
        sid (int): Server ID
        pem_conn: PEM connection object

    Returns: Returns True if server version is below 18, else False.
    """
    server_version = None
    if sid is not None:
        params = [sid]
        status, server_version = pem_conn.execute_scalar(
            """
            SELECT server_version_id
            FROM pemdata.server_info
            WHERE server_id = (%s)::int4
            """,
            params,
        )
        if not status:
            return internal_server_error(
                errormsg=gettext(
                    "Error executing query: {0}".format(server_version)
                )
            )

        return make_json_response(
            status=200,
            success=1,
            data=20803 <= server_version < 21800,
        )

    return make_json_response(status=200, success=1, data=False)


@blueprint.route(
    '/close/<int:trans_id>',
    methods=['get'],
    endpoint='close'
)
@login_required
def dashboard_cancel(trans_id):
    """Cancel the dashboard transactions if running."""
    if trans_id == 0 or trans_id is None:
        return bad_request(
            errormsg=gettext(
                'Could not close the dashboard.'
            )
        )
    return cancel_dashboard(trans_id)


@blueprint.route(
    '/charts/enable_probes/agent/<int:cid>/<int:aid>',
    methods=['get']
)
@blueprint.route(
    '/charts/enable_probes/server/<int:cid>/<int:sid>',
    methods=['get']
)
@blueprint.route(
    '/charts/enable_probes/database/<int:cid>/<int:sid>/<string:database>',
    methods=['get']
)
@login_required
def enable_chart_probes(cid, aid=0, sid=0, database=""):
    """
    :param chart_id: chart id
    :param aid: agent id
    :param sid: server id
    :param database: database name
    """
    return enable_chart_dep_probes(cid, aid, sid, database)


@blueprint.route(
    '/<int:did>/<int:trans_id>/gchart/<int:cid>/<int:group_id>/server/'
    '<int:sid>',
    methods=['get']
)
@blueprint.route(
    '/<int:did>/<int:trans_id>/gchart/<int:cid>/<int:group_id>/server/'
    '<int:sid>/<string:start_time>/<string:end_time>',
    methods=['get']
)
@login_required
def group_charts_server_level(
    did, trans_id, cid, sid, group_id=0, start_time=None, end_time=None
):
    """This is a common function which performs two tasks:
       1) Get metadata for the charts.
       2) Get individual chart data

       If group_id is 0, the call is for fetching metadata for server,
       otherwise fetch chart data Render Server level group charts
    """
    if did == 0 or cid == 0 or sid == 0:
        return bad_request(
            errormsg=gettext(
                'Could not find required parameter did, cid or sid.'
            )
        )
    if group_id == 0:
        result = get_chart_metadata(
            did, cid, sid=sid, group_id=group_id, trans_id=trans_id
        )
    else:
        result = group_chart_data(
            did, cid, sid=sid, trans_id=trans_id, group_id=group_id,
            start_time=start_time, end_time=end_time
        )

    return result


@blueprint.route(
    '/<int:did>/<int:trans_id>/gchart/<int:cid>/<int:group_id>/agent/'
    '<int:aid>',
    methods=['get']
)
@blueprint.route(
    '/<int:did>/<int:trans_id>/gchart/<int:cid>/<int:group_id>/agent/<int:aid>'
    '/<string:start_time>/<string:end_time>',
    methods=['get']
)
@login_required
def group_charts_agent_level(
    did, trans_id, cid, aid, group_id=0, start_time=None, end_time=None
):
    """This is a common function which performs two tasks:
       1) Get metadata for the charts.
       2) Get individual chart data
       If group_id is 0, the call is for fetching metadata for agent, otherwise
       fetch chart data
    """
    if did == 0 or cid == 0 or aid == 0:
        return bad_request(
            errormsg=gettext(
                'Could not find required parameter did, cid or aid.'
            )
        )
    if group_id == 0:
        result = get_chart_metadata(
            did, cid, aid=aid, group_id=group_id, trans_id=trans_id
        )
    else:
        result = group_chart_data(
            did, cid, aid=aid, trans_id=trans_id, group_id=group_id,
            start_time=start_time, end_time=end_time
        )

    return result


@blueprint.route(
    '/logs/server/<int:trans_id>/<int:row_id>',
    endpoint='server_logs_for_system', methods=['get']
)
@blueprint.route(
    '/logs/server/<int:trans_id>/<int:row_id>/<path:search>',
    endpoint='server_logs_for_system_with_search', methods=['get']
)
@blueprint.route(
    '/logs/server/<int:trans_id>/<int:row_id>/agent/<int:aid>',
    endpoint='server_logs_for_agent', methods=['get']
)
@blueprint.route(
    '/logs/server/<int:trans_id>/<int:row_id>/agent/<int:aid>/<path:search>',
    endpoint='server_logs_for_agent_with_filter', methods=['get']
)
@blueprint.route(
    '/logs/server/<int:trans_id>/<int:row_id>/server/<int:sid>',
    endpoint='server_logs_for_server', methods=['get']
)
@blueprint.route(
    '/logs/server/<int:trans_id>/<int:row_id>/server/<int:sid>/<path:search>',
    endpoint='server_logs_for_server_with_search', methods=['get']
)
@login_required
def server_logs_data(aid=0, sid=0, row_id=0, search=None, trans_id=None):
    kwargs = dict({
        'database': None,
        'username': None,
        'commandtype': None,
        'fromdate': None,
        'todate': None,
        'trans_id': trans_id,
    })

    if search is not None:
        paths = search.split('/')
        while len(paths):
            filter_on = paths.pop(0)
            if len(paths) > 0:
                value = paths.pop(0)
            else:
                break

            if filter_on in kwargs:
                kwargs[filter_on] = value

    return table_server_logs(aid, sid, row_id, **kwargs)


@blueprint.route(
    '/logs/audit/<int:trans_id>/<int:row_id>',
    endpoint='audit_logs_for_system', methods=['get']
)
@blueprint.route(
    '/logs/audit/<int:trans_id>/<int:row_id>/<path:search>',
    endpoint='audit_logs_for_system_with_search', methods=['get']
)
@blueprint.route(
    '/logs/audit/<int:trans_id>/<int:row_id>/agent/<int:aid>',
    endpoint='audit_logs_for_agent', methods=['get']
)
@blueprint.route(
    '/logs/audit/<int:trans_id>/<int:row_id>/agent/<int:aid>/<path:search>',
    endpoint='audit_logs_for_agent_with_filter', methods=['get']
)
@blueprint.route(
    '/logs/audit/<int:trans_id>/<int:row_id>/server/<int:sid>',
    endpoint='audit_logs_for_server', methods=['get']
)
@blueprint.route(
    '/logs/audit/<int:trans_id>/<int:row_id>/server/<int:sid>/<path:search>',
    endpoint='audit_logs_for_server_with_search', methods=['get']
)
@login_required
def audit_logs_data(aid=0, sid=0, row_id=0, search=None, trans_id=None):
    kwargs = dict({
        'database': None,
        'username': None,
        'commandtype': None,
        'fromdate': None,
        'todate': None,
        'trans_id': trans_id,
    })

    if search is not None:
        paths = search.split('/')
        while len(paths):
            filter_on = paths.pop(0)
            if len(paths) > 0:
                value = paths.pop(0)
            else:
                break

            if filter_on in kwargs:
                kwargs[filter_on] = value

    return table_audit_logs(aid, sid, row_id, **kwargs)


@blueprint.route(
    '/logs/probe/<int:trans_id>/<int:row_id>/agent/<int:aid>/<path:search>',
    endpoint='probe_logs_for_agent_with_filter', methods=['get']
)
@blueprint.route(
    '/logs/probe/<int:trans_id>/<int:row_id>/agent/<int:aid>',
    endpoint='probe_logs_for_agent', methods=['get']
)
@login_required
def probe_logs_data(aid=0, row_id=0, search=None, trans_id=None):
    kwargs = dict({
        'fromdate': None,
        'todate': None,
        'trans_id': trans_id,
    })
    if search is not None:
        paths = search.split('/')
        while len(paths):
            filter_on = paths.pop(0)
            if len(paths) > 0:
                value = paths.pop(0)
            else:
                break
            if filter_on in kwargs:
                kwargs[filter_on] = value
    return table_probe_logs(aid, row_id, **kwargs)


@blueprint.route('/bdr_worker_details/<int:server_id>/'
                 '<string:worker_pid>',
                 methods=["GET"], endpoint='bdr_worker_details')
@login_required
@pem_connection
def bdr_worker_details(server_id, worker_pid, pem_conn=None):
    """
    This function is used to fetch details of BDR workers
    """
    sql = render_template(
        '/dashboard/sql/bdr_worker_details.sql',
        server_id=server_id,
        worker_pid=worker_pid,
    )
    status, res = pem_conn.execute_dict(sql)
    if not status:
        return internal_server_error(errormsg=res)

    data = {'details': {
        'cols': [],
        'rows': []
    }}

    if res and 'rows' in res:
        rows = json.loads(res['rows'][0]['row_to_json'])
        rows = list(rows.items())

        data['details']['cols'] = ['Name', 'Value']
        data['details']['rows'] = rows

    return make_json_response(
        status=200,
        success=1,
        data=data
    )


@blueprint.route('/bdr_worker_error_details/<int:server_id>/'
                 '<string:worker_pid>',
                 methods=["GET"], endpoint='bdr_worker_error_details')
@login_required
@pem_connection
def bdr_worker_error_details(server_id, worker_pid, pem_conn=None):
    """
    This function is used to fetch details of BDR workers
    """
    sql = render_template(
        '/dashboard/sql/bdr_worker_error_details.sql',
        server_id=server_id,
        worker_pid=worker_pid,
    )
    status, res = pem_conn.execute_dict(sql)
    if not status:
        return internal_server_error(errormsg=res)

    data = {'details': {
        'cols': [],
        'rows': []
    }}

    if res and 'rows' in res:
        rows = json.loads(res['rows'][0]['row_to_json'])
        rows = list(rows.items())

        data['details']['cols'] = ['Name', 'Value']
        data['details']['rows'] = rows

    return make_json_response(
        status=200,
        success=1,
        data=data
    )
