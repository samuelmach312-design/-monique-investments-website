##########################################################################
#
# Postgres Enterprise Manager
#
# Copyright (C) 2016 - 2025, EnterpriseDB Corporation. All rights reserved.
#
##########################################################################


from pgadmin.pem.utils import pem_connection
from pgadmin.pem.misc.error import error_return, PEMErrorType, PEMChartStatus
from ..utils.chart_constant import PEMChartDataGeneratorType
from flask import current_app, url_for, render_template
from pgadmin.utils.ajax import success_return
from flask_babel import gettext


@pem_connection
def statusColor(status, status_type, pem_conn=None):

    sql = render_template(
        'charts/sql/bar/get_settings.sql'
    )

    params = {
        "cid": 1, "did": 1,
        "objid": None, "database": None,
        "schema": None, "tbl": None,
        "level": 50
    }

    stat, dbRes = pem_conn.execute_2darray(sql, params)

    if not stat or dbRes is None or len(dbRes) == 0:
        error_return(
            gettext(
                "Couldn't find the chart settings for this chart!"
            ), PEMErrorType.JSON, status_code=503
        )

    res = {}
    idx = 0
    for row in dbRes['rows']:
        if idx == 0:
            # Fetch all the labels and store them in result.
            res['labels'] = {}
            if row['labels']:
                for index, label in enumerate(row['labels']):
                    res['labels'][index] = row['labels'][index]

            # Check default colors returned by the query and also check
            # number of labels and number of default colors must be same
            res['colors'] = {}
            if row['default_colors'] and row['labels'] and (
                len(row['labels']) == len(row['default_colors'])
            ):
                for index, label in enumerate(row['labels']):
                    res['colors'][row['labels'][index]] = \
                        row['default_colors'][index]

            # Check if color is changed by the user if it is then
            # update the color with the changed value.
            if row['clname']:
                res['colors'][row['clname']] = row['clval']
            idx += 1
        else:
            if row['clname']:
                res['colors'][row['clname']] = row['clval']

    colors = res['colors']
    status_type = status_type.capitalize()

    if status == 'UP':
        return colors[status_type + ' Up']
    elif status == 'DOWN':
        return colors[status_type + ' Down']
    elif status == 'UNKNOWN':
        return colors[status_type + ' Unknown']
    else:
        return colors['Unmanaged ' + status_type]


def alertColor(status):
    if status == 'HIGH':
        return '#EA5E51'
    elif status == 'MEDIUM':
        return '#EACE46'
    elif status == 'LOW':
        return '#9D9EA0'
    else:
        return '#646464'


_knownEventTypes = [
    'Activity', 'IO', 'LWLock', 'Lock', 'BufferPin', 'CPU', 'Extension',
    'IPC', 'Timeout', 'Client', 'ALL_WAIT_EVENT_TYPE',
]


def whichColor(id, label, colors=None, settings=None):
    # Default colors
    DEFAULT_COLORS = {
        '0': '#ED3624',
        '1': '#23D347',
        '2': '#4242E2',
        '3': '#EDBC21',
        '4': '#8E00CC',
        '5': '#C31980',
        '6': '#3FCCC0',
        '7': '#333333',
        '8': '#108C33',
        '9': '#837171',
        '10': '#84D6FF',
        '11': '#4C95E8',
        '12': '#646464',
        '13': '#D3CD28',
        '14': '#226A72',
        '15': '#827717',
        '16': '#744CBF',
        '17': '#FF7043',
        '18': '#6574A6',
        '19': '#FFA6B0',
        '20': '#B0BEC5',
        '21': '#BE8BDD',
        '22': '#F79838',
        '23': '#FC79F8',
        '24': '#653313',
        '25': '#9E9E9E',
        '26': '#D8AE97',
        '27': '#EE569E',
        '28': '#8FB6A3',
        '29': '#7F87FF',
        '30': '#CCC5A8',
        '31': '#A54029',
    }

    if (settings is not None and 'colors' in settings and settings['colors']
            is not None and label in settings['colors']):
        return settings['colors'][label]

    # Is this id available in the set of colors provided?
    if (colors is not None and id < len(colors) and colors[id]):
        return colors[id]

    # Is this id present in the list of default colors?
    if str(id) in DEFAULT_COLORS:
        return DEFAULT_COLORS[str(id)]

    import random
    # Generate random color
    return "{:06X}".format(random.randint(0, 0xFFFFFF))


def get_chart_probe_dependency(
        chart_id, params, dashboard_transaction, pem_conn):
    """
    Find the chart probe dependency
    :param sub_query: the conditional query
    :param params: params
    :return: status and the probe dependency warning if any
    """

    probe_warning = ""
    ret_status = PEMChartStatus.SUCCESS
    sub_query = ""
    probes = tuple()
    agent = 0
    server = 0
    database = ''
    required_probes = []

    if 'probes' in params:
        probes = params['probes']
    if 'agent' in params:
        agent = params['agent']
    if 'server' in params:
        server = params['server']
    if 'database' in params:
        database = params['database']
    # Find the target type of thr probes
    query = "SELECT target_type_id, internal_name "\
        "FROM pem.probe where internal_name = any (%s);"

    with dashboard_transaction:
        status, res = pem_conn.execute_dict(query, [list(probes)])

    if not status:
        return PEMChartStatus.ERROR, res

    if 'rows' in res and len(res['rows']) > 0:
        for r in res['rows']:
            sub_query = ""
            sub_params = []
            if r['target_type_id'] == 100:
                sub_query = "AND agent_id = (%s)::int;"
                # If dashboard level > 100 but target tye id = 100
                if agent == 0 and server > 0:
                    query = \
                        "SELECT agent_id FROM pem.agent_server_binding " \
                        "WHERE server_id = %s;"
                    with dashboard_transaction:
                        status, res = pem_conn.execute_dict(query, [server])

                    if not status:
                        return PEMChartStatus.ERROR, res

                    if 'rows' in res and len(res['rows']) > 0:
                        agent = res['rows'][0]['agent_id']

                sub_params = [r['internal_name'], agent]
            elif r['target_type_id'] == 200:
                sub_query = "AND server_id = (%s)::int;"
                sub_params = [r['internal_name'], server]
            elif r['target_type_id'] in (300, 400, 1000):
                sub_query = \
                    "AND server_id = (%s)::int AND database_name = (%s)"
                sub_params = [r['internal_name'], server, database]
                if r['target_type_id'] == 1000 and server and database:
                    sub_query += " AND parameter_value_list = (%s);"
                    sub_params.append('{{{0},{1}}}'.format(server, database))

            # Check whether the probe(s) are enabled or not
            query = "SELECT probe_display_name FROM PEM.probe_target_view" + \
                " WHERE enabled = false and probe_internal_name = (%s) " + \
                sub_query

            with dashboard_transaction:
                status, res = pem_conn.execute_dict(query, sub_params)

            if not status:
                return PEMChartStatus.ERROR, res

            if 'rows' in res and len(res['rows']) > 0 and \
                    res['rows'][0]['probe_display_name'] is not None:
                required_probes.append(res['rows'][0]['probe_display_name'])

    if len(required_probes) > 0:
        ret_status = PEMChartStatus.WARNING
        probe_warning += "You must enable the "

        if len(required_probes) == 1:
            probe_warning += ", ".join(required_probes) + " probe"
        else:
            probe_warning += ", ".join(required_probes) + " probes"

        probe_warning += " to display data on this chart."

    return ret_status, probe_warning


@pem_connection
def enable_chart_dep_probes(cid, aid, sid, database, pem_conn=None):
    """
    :param cid: chart id
    :param aid: agent id
    :param sid: server id
    :param database: database name
    :param pem_conn: pem connection
    """
    chart_query = """
    SELECT
        c.type AS type, c.name AS name, c.level AS levels,
        c.fid AS fid, c.deleted AS deleted,
        cf.type AS func_type, cf.func AS func,
        CASE c.type
            WHEN 'TB' THEN tc.type
            WHEN  'L' THEN lc.type
            WHEN 'CL' THEN cc.type
            WHEN 'CT' THEN cc.type
            ELSE  ''
        END AS ttype,
        cf.dep_probes
    FROM
        pem.chart c
        LEFT OUTER JOIN pem.chart_func cf ON (c.fid = cf.id)
        LEFT OUTER JOIN pem.tbl_chart  tc ON (c.id = tc.cid)
        LEFT OUTER JOIN pem.line_chart lc ON (c.id = lc.cid)
        LEFT OUTER JOIN pem.capacity_report_chart cc ON (c.id = cc.cid)
    WHERE c.id = (%s)::int4"""

    status, res = pem_conn.execute_dict(chart_query, [cid])

    if not status:
        current_app.logger.warning(
            'Failed to fetch the information about the chart (id#{0}) '
            'with error - {1}'.format(
                cid, res
            )
        )
        error_return(gettext(
            'Could not find this chart (id#{0}) in the Postgres Enterprise '
            'Manager Server database'
        ).format(cid), e_type=PEMErrorType.JSON)

    if len(res) == 0:
        current_app.logger.warning(
            "Couldn't find the information of the chart (id#{0}) in the "
            "database.".format(
                cid
            )
        )
        error_return(
            gettext(
                "Couldn't find the information of the chart in the database!\n"
                "It must have been deleted!"
            ),
            e_type=PEMErrorType.JSON
        )

    chart = res['rows'][0]

    # table-chart/line-chart type
    ctype = chart['ttype']

    # Function based chart probe dependency list
    dep_probes = tuple(chart['dep_probes']) if\
        chart['dep_probes'] is not None else None

    fid = chart['fid']

    if fid:
        query = """SELECT array_agg(p.id) AS probe_id,
        array_agg(p.target_type_id) as target_type_id
        FROM pem.probe p
        WHERE p.internal_name = any (%s)
        """
        status, res = pem_conn.execute_dict(query, [dep_probes])

        if not status:
            current_app.logger.warning(
                'Failed to fetch the probe dependency of the chart '
                '(id#{0}) with error - {1}'.format(
                    cid, res
                )
            )
            error_return(gettext(
                'Failed to fetch the probe dependency of the chart (id#{0})'
                ' in the Postgres Enterprise Manager Server database'
            ).format(cid), e_type=PEMErrorType.JSON)

        if 'rows' in res and len(res['rows']) > 0:
            dep_probes = res['rows'][0]['probe_id']
            target_type = res['rows'][0]['target_type_id']
    else:
        if ctype == PEMChartDataGeneratorType.DATAVIEW:
            query = """SELECT cid, tbl AS dep_probes, p.id AS probe_id,
            p.target_type_id
            FROM pem.data_chart c
            JOIN pem.probe p on p.internal_name = c.tbl
            WHERE
            cid = (%s)::int4 AND cid >= 257;"""

            status, res = pem_conn.execute_dict(query, [cid])
            if not status:
                current_app.logger.warning(
                    'Failed to fetch the information about the chart '
                    '(id#{0}) with error - {1}'.format(
                        cid, res
                    )
                )
                error_return(gettext(
                    'Could not find this chart (id#{0}) in the Postgres '
                    'Enterprise Manager Server database'
                ).format(cid), e_type=PEMErrorType.JSON)
            if 'rows' in res and len(res['rows']) > 0:
                dep_probes = [res['rows'][0]['probe_id']]
                target_type = [res['rows'][0]['target_type_id']]
        elif ctype == PEMChartDataGeneratorType.AGG_METRICS:
            # Fetch the information about the chart from the database
            query = """
            SELECT
                array_agg(p.id) AS probe_id,
                array_agg(p.target_type_id) as target_type_id
            FROM
                pem.chart c
                LEFT OUTER JOIN pem.chart_metric cm ON (c.id = cm.cid)
                LEFT OUTER JOIN pem.probe p on p.internal_name = cm.tbl
            WHERE c.id = (%s)::int4"""

            status, res = pem_conn.execute_dict(query, [cid])

            if not status:
                current_app.logger.warning(
                    'Failed to fetch the probe dependency of the chart '
                    '(id#{0}) with error - {1}'.format(
                        cid, res
                    )
                )
                error_return(gettext(
                    'Failed to fetch the probe dependency of the chart '
                    '(id#{0}) in the Postgres Enterprise Manager Server '
                    'database'
                ).format(cid), e_type=PEMErrorType.JSON)

            if 'rows' in res and len(res['rows']) > 0:
                dep_probes = res['rows'][0]['probe_id']
                target_type = res['rows'][0]['target_type_id']

    if dep_probes:
        # Enable dependent probes
        query = None
        dep_params = []
        cnt = 0
        for pid in dep_probes:
            if target_type[cnt] == 100:
                # If dashboard level > 100 but target tye id = 100
                if aid == 0 and sid > 0:
                    query = """
SELECT agent_id from pem.agent_server_binding where server_id = %s;"""
                    status, res = pem_conn.execute_dict(query, [sid])

                    if not status:
                        current_app.logger.warning(
                            'Failed to enable the dependent probes of the '
                            'chart (id#{0}) with error - {1}'.format(
                                cid, res
                            )
                        )
                        error_return(gettext(
                            'Failed to enable the dependent probes of the '
                            'chart (id#{0}) in the Postgres Enterprise '
                            'Manager Server database'
                        ).format(cid), e_type=PEMErrorType.JSON)

                    if 'rows' in res and len(res['rows']) > 0:
                        aid = res['rows'][0]['agent_id']

                update_query = """
UPDATE pem.probe_config_agent SET enabled = true
WHERE probe_id = (%s)::int AND agent_id = (%s)::int returning probe_id;"""

                insert_query = """
INSERT INTO pem.probe_config_agent(probe_id, agent_id, enabled)
VALUES((%s)::int, (%s)::int, true);"""
                dep_params = [pid, aid]
            elif target_type[cnt] == 200:
                update_query = """
UPDATE pem.probe_config_server SET enabled = true
WHERE probe_id = (%s)::int AND server_id = (%s)::int returning probe_id;"""

                insert_query = """
INSERT INTO pem.probe_config_server(probe_id, server_id, enabled)
VALUES((%s)::int, (%s)::int, true);"""
                dep_params = [pid, sid]
            elif target_type[cnt] == 300:
                update_query = """
UPDATE pem.probe_config_database SET enabled = true
WHERE probe_id = (%s)::int AND server_id = (%s)::int AND
database_name = (%s)::text returning probe_id;"""

                insert_query = """
INSERT INTO pem.probe_config_database(
    probe_id, server_id, database_name, enabled
) VALUES((%s)::int, (%s)::int, (%s)::text, true);"""
                dep_params = [pid, sid, database]
            elif target_type[cnt] == 1000:
                update_query = """
UPDATE pem.probe_config_extension SET enabled = true
WHERE probe_id = (%s)::int AND server_id = (%s)::int AND
database_name = (%s)::text returning probe_id;"""

                insert_query = """
INSERT INTO pem.probe_config_extension(
    probe_id, server_id, database_name, extension_name, enabled
) VALUES((%s)::int, (%s)::int, (%s)::text, '', true);"""
                dep_params = [pid, sid, database]

            if update_query:
                status, probe_id = pem_conn.execute_scalar(
                    update_query, dep_params
                )

                if not status:
                    current_app.logger.warning(
                        'Failed to enable the dependent probes of the chart '
                        '(id#{0}) with error - {1}'.format(
                            cid, probe_id
                        )
                    )
                    error_return(
                        gettext(
                            'Failed to enable the dependent probes of the '
                            'chart (id#{0}) in the Postgres Enterprise '
                            'Manager Server database'
                        ).format(cid),
                        e_type=PEMErrorType.JSON)

                if probe_id is None:
                    status, res = pem_conn.execute_void(
                        insert_query, dep_params)

                    if not status:
                        current_app.logger.warning(
                            'Failed to enable the dependent probes of the '
                            'chart (id#{0}) with error - {1}'.format(
                                cid, res
                            )
                        )
                        error_return(
                            gettext(
                                'Failed to enable the dependent probes of '
                                'the chart (id#{0}) in the Postgres '
                                'Enterprise Manager Server database'
                            ).format(cid),
                            e_type=PEMErrorType.JSON
                        )

            cnt += 1
    return success_return()
