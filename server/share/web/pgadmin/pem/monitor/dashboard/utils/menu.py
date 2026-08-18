##########################################################################
#
# Postgres Enterprise Manager
#
# Copyright (C) 2016 - 2025, EnterpriseDB Corporation. All rights reserved.
#
##########################################################################

from collections import namedtuple
from flask import current_app
from flask_babel import gettext
from flask import url_for, session
from pgadmin.pem.monitor.utils import DashboardLevel
from pgadmin.pem.utils import pem_connection, show_streaming_dashboard
from pgadmin.pem.monitor.dashboard.utils.html import PEMDashboards, \
    PEMPredefinedDashboards
from urllib.parse import quote


Category = namedtuple(
    'Category',
    ['name', 'priority', 'menus', 'has_next_level', 'level']
)

MenuItem = namedtuple(
    'MenuItem',
    ['title', 'url', 'target', 'id', 'object_type', 'level', 'aid', 'sid',
     'db']
)

AGENTS = gettext("AGENTS")
REMOTE_SERVERS = gettext("REMOTE SERVERS")
SERVERS = gettext("SERVERS")
DATABASES = gettext("DATABASES")
DASHBOARDS = gettext("DASHBOARDS")
CUSTOM_DASHBOARDS = gettext("CUSTOM DASHBOARDS")
OPS_DASHBOARDS = gettext("OPS DASHBOARDS")


def get_categories(level):
    global_categories = {
        AGENTS: Category(AGENTS, 1, [], True, DashboardLevel.DB_GLOBAL),
        REMOTE_SERVERS: Category(
            REMOTE_SERVERS, 2, [], True, DashboardLevel.DB_GLOBAL
        ),
        DASHBOARDS: Category(
            DASHBOARDS, 3, [], False, DashboardLevel.DB_GLOBAL
        ),
        CUSTOM_DASHBOARDS: Category(
            CUSTOM_DASHBOARDS, 4, [], False, DashboardLevel.DB_GLOBAL
        ),
        OPS_DASHBOARDS: Category(
            OPS_DASHBOARDS, 5, [], False, DashboardLevel.DB_GLOBAL
        ),
    }

    agent_categories = {
        SERVERS: Category(SERVERS, 1, [], True, DashboardLevel.DB_AGENT),
        DASHBOARDS: Category(
            DASHBOARDS, 2, [], False, DashboardLevel.DB_AGENT
        ),
        CUSTOM_DASHBOARDS: Category(
            CUSTOM_DASHBOARDS, 3, [], False, DashboardLevel.DB_AGENT
        ),
        OPS_DASHBOARDS: Category(
            OPS_DASHBOARDS, 4, [], False, DashboardLevel.DB_AGENT
        ),
    }

    server_categories = {
        DATABASES: Category(DATABASES, 1, [], True, DashboardLevel.DB_SERVER),
        DASHBOARDS: Category(
            DASHBOARDS, 2, [], False, DashboardLevel.DB_SERVER
        ),
        CUSTOM_DASHBOARDS: Category(
            CUSTOM_DASHBOARDS, 3, [], False, DashboardLevel.DB_SERVER
        ),
        OPS_DASHBOARDS: Category(
            OPS_DASHBOARDS, 4, [], False, DashboardLevel.DB_SERVER
        ),
    }

    database_categories = {
        DASHBOARDS: Category(
            DASHBOARDS, 1, [], False, DashboardLevel.DB_DATABASE
        ),
        CUSTOM_DASHBOARDS: Category(
            CUSTOM_DASHBOARDS, 2, [], False, DashboardLevel.DB_DATABASE
        ),
        OPS_DASHBOARDS: Category(
            OPS_DASHBOARDS, 3, [], False, DashboardLevel.DB_DATABASE
        ),
    }

    category_map = {
        DashboardLevel.DB_GLOBAL: {
            DashboardLevel.DB_GLOBAL: global_categories,
        },
        DashboardLevel.DB_AGENT: {
            DashboardLevel.DB_GLOBAL: global_categories,
            DashboardLevel.DB_AGENT: agent_categories,
        },
        DashboardLevel.DB_SERVER: {
            DashboardLevel.DB_GLOBAL: global_categories,
            DashboardLevel.DB_AGENT: agent_categories,
            DashboardLevel.DB_SERVER: server_categories,
        },
        DashboardLevel.DB_DATABASE: {
            DashboardLevel.DB_GLOBAL: global_categories,
            DashboardLevel.DB_AGENT: agent_categories,
            DashboardLevel.DB_SERVER: server_categories,
            DashboardLevel.DB_DATABASE: database_categories,
        },
    }

    return category_map.get(level, {})


@pem_connection
def get_breadcrumb_data(
    dashboard_level, aid=None, sid=None,
    is_edb=None, database=None, is_remotely_monitored=False,
    pem_conn=None
):
    showStreamingDb = False

    menu_cat = get_categories(dashboard_level)

    if dashboard_level >= DashboardLevel.DB_GLOBAL:
        status, res = global_breadcrumb_data(menu_cat, pem_conn)
        if not status:
            return {}

    if dashboard_level >= DashboardLevel.DB_AGENT:

        # Fetch the server remote monitoring, and agent_id (if not available)
        if dashboard_level > DashboardLevel.DB_AGENT and not aid:
            status, aid = pem_conn.execute_scalar("""
SELECT
    asb.agent_id
FROM
    pem.server s
    LEFT JOIN pem.agent_server_binding asb ON (asb.server_id = s.id)
WHERE s.id = (%s)::int4""", [sid])

            if not status:
                current_app.logger.error(aid)
                return {}

        if dashboard_level >= DashboardLevel.DB_AGENT:
            if dashboard_level == DashboardLevel.DB_AGENT:
                sid = None
                is_edb = None
            if not is_remotely_monitored:
                status, res = agent_breadcrumb_data(menu_cat, aid, pem_conn)
                if not status:
                    return {}
            else:
                del menu_cat[100]

        if dashboard_level > DashboardLevel.DB_AGENT:

            status, res = server_breadcrumb_data(menu_cat, sid, pem_conn)
            if not status:
                return {}

            showStreamingDb = show_streaming_dashboard(pem_conn, sid)

    status, res = dashboard_breadcrumb_data(
        menu_cat, showStreamingDb, is_edb=is_edb,
        aid=aid, sid=sid, database=database, pem_conn=pem_conn
    )

    if not status:
        return {}

    return menu_cat


def global_breadcrumb_data(menu_cat, pem_conn=None):
    # This will look for all the agents
    BASE_URL = url_for('pem_dashboard.index')
    status, res = pem_conn.execute_2darray("""
    SELECT
        id, description
    FROM
        pem.avail_agents
    WHERE
        active=true
    ORDER BY description""")

    if not status:
        current_app.logger.error(res)
        return False, res

    for row in res['rows']:
        row = list(row.values())
        menu_cat[DashboardLevel.DB_GLOBAL][AGENTS].menus.append(MenuItem(
            row[1],
            '{}{}/agent/{}'.format(BASE_URL,
                                   PEMPredefinedDashboards.OS,
                                   row[0]),
            None,
            PEMPredefinedDashboards.OS,
            'agent',
            DashboardLevel.DB_GLOBAL,
            row[0],
            None,
            None)
        )

    # List all the remotely monitored servers
    status, res = pem_conn.execute_2darray("""
    SELECT
        ps.id, ps.description, pasb.agent_id
    FROM
        pem.avail_servers AS ps
        LEFT OUTER JOIN pem.agent_server_binding pasb
            ON (ps.id = pasb.server_id)
    WHERE
        ps.is_remote_monitoring = true
    ORDER BY ps.description""")

    if not status:
        current_app.logger.error(res)
        return False, res

    # Add Remote Servers menu (only if any server exists)
    if len(res['rows']) > 0:
        for row in res['rows']:
            row = list(row.values())
            menu_cat[DashboardLevel.DB_GLOBAL][
                REMOTE_SERVERS].menus.append(MenuItem(
                    row[1],
                    '{}{}/server/{}'.format(BASE_URL,
                                            PEMPredefinedDashboards.SERVER,
                                            row[0]),
                    None,
                    PEMPredefinedDashboards.SERVER,
                    'server',
                    DashboardLevel.DB_GLOBAL,
                    None,
                    row[0],
                    None)
            )

    return True, None


def agent_breadcrumb_data(menu_cat, aid, pem_conn=None):
    # List all the servers (locally monitored) bound to this agent
    BASE_URL = url_for('pem_dashboard.index')
    status, res = pem_conn.execute_2darray("""
        SELECT
            ps.id, ps.description
        FROM
            pem.avail_servers AS ps
            LEFT OUTER JOIN pem.agent_server_binding pasb
            ON (ps.id = pasb.server_id)
        WHERE
            pasb.agent_id = (%(aid)s)::int4 AND
            not ps.is_remote_monitoring
        ORDER BY ps.description""", {'aid': aid})

    if not status:
        current_app.logger.error(res)
        return False, res

    # Add Servers menu (only if any agents exists)
    if len(res['rows']) > 0:
        for row in res['rows']:
            row = list(row.values())
            menu_cat[DashboardLevel.DB_AGENT][
                SERVERS].menus.append(MenuItem(
                    row[1],
                    '{}{}/server/{}'.format(BASE_URL,
                                            PEMPredefinedDashboards.SERVER,
                                            row[0]),
                    None,
                    PEMPredefinedDashboards.SERVER,
                    'server',
                    DashboardLevel.DB_AGENT,
                    aid,
                    row[0],
                    None)
            )

    return True, None


def server_breadcrumb_data(menu_cat, sid, pem_conn=None):
    BASE_URL = url_for('pem_dashboard.index')
    try:
        show_system_objects = session['show_system_objects']
    except Exception:
        show_system_objects = False

    # List all the databases (only restricted if specified)
    status, res = pem_conn.execute_2darray("""
    WITH restricted_dbs AS (
        SELECT
            s.id AS sid, pem.db_escaped_string_to_array(
                COALESCE(o.database_restriction, oa.database_restriction)
            ) AS dbs
        FROM
            pem.server s
            LEFT OUTER JOIN pg_catalog.pg_roles owner ON (owner.oid = s.owner)
            LEFT OUTER JOIN pem.server_options o ON
                (s.id = o.server_id AND o.pem_user = current_user)
            LEFT OUTER JOIN pem.server_options oa
                ON (o.id IS NULL AND s.id = oa.server_id AND
                    (owner.rolname = oa.pem_user OR
                     (owner.rolname IS NULL AND oa.pem_user IS NULL)))
    )
    SELECT
        database_name
    FROM
        pemdata.oc_database d
        LEFT JOIN restricted_dbs r ON (d.server_id = r.sid)
    WHERE
        d.server_id = (%s)::int4 AND
        ((%s)::boolean OR (
         CASE WHEN d.database_name != '' THEN
            d.database_name NOT IN ('template0', 'template1')
         ELSE TRUE
         END)) AND
        (r.dbs IS NULL OR (d.database_name = ANY(r.dbs)))""", [
        sid,
        True if show_system_objects else False
    ])

    if not status:
        current_app.logger.error(res)
        return False, res

    # Add Databases menu (only if any agents exists)
    if len(res['rows']) > 0:
        for row in res['rows']:
            row = list(row.values())
            menu_cat[DashboardLevel.DB_SERVER][
                DATABASES].menus.append(MenuItem(
                    row[0],
                    '{}{}/server/{}/database/{}'.format(
                        BASE_URL,
                        PEMPredefinedDashboards.DATABASE,
                        sid,
                        quote(row[0])),
                    None,
                    PEMPredefinedDashboards.DATABASE,
                    'database',
                    DashboardLevel.DB_SERVER,
                    None,
                    sid,
                    quote(row[0]))
            )
    return True, None


def get_param_value(dash_level, aid, sid, database):
    return {
        50: None,
        100: aid,
        200: sid,
        300: database
    }.get(dash_level, None)


def dashboard_breadcrumb_data(
        menu_cat, showStreamingDb, is_edb=None,
        aid=None, sid=None, database=None, pem_conn=None):

    PEMDashboards_obj = PEMDashboards()
    BASE_URL = url_for('pem_dashboard.index')
    urlParams = {
        DashboardLevel.DB_GLOBAL: '',
        DashboardLevel.DB_AGENT: '/agent/{0}'.format(aid),
        DashboardLevel.DB_SERVER: '/server/{0}'.format(sid),
        DashboardLevel.DB_DATABASE: '/server/{0}/database/{1}'.format(
            sid, quote(database) if database else None)
    }

    dashboards_by_lvl = dict()
    required_dashboards_levels = list(menu_cat.keys())

    for dash_level in required_dashboards_levels:
        dashboards_by_lvl[dash_level] = PEMDashboards_obj.getSysDashboards(
            dash_level, is_edb, sid, pem_conn)

    for dash_level, dashboards in list(dashboards_by_lvl.items()):
        for d in dashboards:
            if not (showStreamingDb is False and dashboards[d]['id'] ==
                    PEMPredefinedDashboards.STREAMING_REPLICATION):
                menu_cat[dash_level][DASHBOARDS].menus.append(MenuItem(
                    dashboards[d]['title'],
                    '{0}{1}{2}'.format(
                        BASE_URL, dashboards[d]['url'], urlParams[dash_level]
                    ),
                    None,
                    dashboards[d]['id'],
                    'dashboard',
                    dash_level,
                    aid,
                    sid,
                    database)
                )

    # Custom dashboard menus
    sql = """
    SELECT
        d.id, d.title,
        d.title || '(#' || d.id || ')' AS title_sep,
        d.descp, d.owner, d.is_ops_dashboard,
        d.level
    FROM
        pem.dashboard d
        LEFT JOIN pg_catalog.pg_roles r ON (d.owner = r.oid)
    WHERE
        d.owner IS NOT NULL AND
        (r.rolname = current_user
        OR pem.can_access(d.shared)
        OR (array_length(d.shared, 1) IS NULL
        OR array_length(d.shared, 1) = 0)) AND
        d.level = ANY(%(levels)s::int[])
    ORDER BY d.owner, title_sep"""

    status, res = pem_conn.execute_2darray(
        sql,
        {'levels': required_dashboards_levels}
    )

    if not status:
        current_app.logger.error(res)
        return False, res

    if len(res['rows']) > 0:
        for row in res['rows']:
            row = list(row.values())
            if row[5] is True:
                urlParams_str = "{0}{1}{2}".format(
                    BASE_URL, row[0], urlParams[row[6]]
                )

                menu_cat[row[6]][OPS_DASHBOARDS].menus.append(MenuItem(
                    row[1],
                    urlParams_str,
                    '_blank',
                    row[0],
                    'dashboard',
                    row[6],
                    aid,
                    sid,
                    database)
                )

            else:
                urlParams_str = "{0}{1}{2}".format(
                    BASE_URL, row[0], urlParams[row[6]]
                )

                menu_cat[row[6]][CUSTOM_DASHBOARDS].menus.append(MenuItem(
                    row[1],
                    urlParams_str,
                    None,
                    row[0],
                    'dashboard',
                    row[6],
                    aid,
                    sid,
                    database)
                )
    return True, None


def convert_menu_namedtuple_as_dict(obj):
    """
    Convert Menu dict with nested namedtuple items to Dict, so that
    they can be converted to JSON properly by newer version of Jinja template

    :param obj: Menu dict with nested namedtuple
    :return: Menu dict with nested namedtuple converted to normal dict
    """
    menu_dict = {}
    for menu, contents in obj.items():
        menu_dict[menu] = contents
        for key, content in contents.items():
            # convert Category (namedtuple type) to Dict
            menu_content = content
            if hasattr(content, '_asdict'):
                menu_content = dict(content._asdict())
            if 'menus' in menu_content:
                # convert all MenuItem (namedtuple type) to Dict and lastly
                # convert Map object with correct data to List
                menu_content['menus'] = list(
                    map(
                        lambda sub_menu: dict(
                            sub_menu._asdict() if hasattr(sub_menu, '_asdict')
                            else sub_menu
                        ), menu_content['menus']
                    )
                )
            menu_dict[menu][key] = menu_content
    return menu_dict
