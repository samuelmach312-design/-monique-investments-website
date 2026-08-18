##########################################################################
#
# Postgres Enterprise Manager
#
# Copyright (C) 2016 - 2024, EnterpriseDB Corporation. All rights reserved.
#
##########################################################################

from collections import namedtuple
from flask import current_app
from flask_babel import gettext
from flask import url_for
from pgadmin.pem.monitor.utils import DashboardLevel
from pgadmin.pem.utils import pem_connection
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

DASHBOARDS = gettext("DASHBOARDS")
CUSTOM_DASHBOARDS = gettext("CUSTOM DASHBOARDS")
OPS_DASHBOARDS = gettext("OPS DASHBOARDS")


def get_categories(level):
    global_categories = {
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
        DashboardLevel.DB_GLOBAL: global_categories,
        DashboardLevel.DB_AGENT: agent_categories,
        DashboardLevel.DB_SERVER: server_categories,
        DashboardLevel.DB_DATABASE: database_categories,
    }

    return category_map.get(level, {})


@pem_connection
def get_dashboard_menus(
    dashboard_level, aid=None, sid=None,
    is_edb=None, database=None, pem_conn=None
):
    showStreamingDb = False

    menu_cat = get_categories(dashboard_level)

    status, res = dashboard_breadcrumb_data(
        menu_cat, showStreamingDb, is_edb=is_edb,
        aid=aid, sid=sid, database=database, pem_conn=pem_conn,
        dashboard_level=dashboard_level
    )

    if not status:
        return {}

    return menu_cat


def get_param_value(dashboard_level, aid, sid, database):
    return {
        50: None,
        100: aid,
        200: sid,
        300: database
    }.get(dashboard_level, None)


def dashboard_breadcrumb_data(
        menu_cat, showStreamingDb, is_edb=None,
        aid=None, sid=None, database=None, pem_conn=None,
        dashboard_level=None):

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

    dashboards_by_lvl[dashboard_level] = PEMDashboards_obj.getSysDashboards(
        dashboard_level, is_edb, sid, pem_conn)

    for dashboard_level, dashboards in list(dashboards_by_lvl.items()):
        for d in dashboards:
            if not (showStreamingDb is False and dashboards[d]['id'] ==
                    PEMPredefinedDashboards.STREAMING_REPLICATION):
                menu_cat[DASHBOARDS].menus.append(MenuItem(
                    dashboards[d]['title'],
                    '{0}{1}{2}'.format(
                        BASE_URL, dashboards[d]['url'],
                        urlParams[dashboard_level]
                    ),
                    None,
                    dashboards[d]['id'],
                    'dashboard',
                    dashboard_level,
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
        {'levels': [dashboard_level]}
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

                menu_cat[OPS_DASHBOARDS].menus.append(MenuItem(
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

                menu_cat[CUSTOM_DASHBOARDS].menus.append(MenuItem(
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
