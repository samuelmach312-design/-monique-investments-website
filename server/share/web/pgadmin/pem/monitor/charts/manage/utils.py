##########################################################################
#
# Postgres Enterprise Manager
#
# Copyright (C) 2016 - 2025, EnterpriseDB Corporation. All rights reserved.
#
##########################################################################
import copy
import json
from math import floor
from flask import render_template
from flask_babel import gettext
from pgadmin.pem.utils import csv_split
from pgadmin.pem.monitor.utils import DashboardLevel
from pgadmin.pem.monitor.probes.utils import generate_export_probe_data
from pgadmin.pem.monitor.probes.utils import insert_imported_probes
from pgadmin.pem.utils.role import PEMRole

ERROR_MSG_FOR_REQUIRED_PARAMS = \
    "Could not find the required parameter chart metrics."
GET_CHART_CATEGORY_SQL = 'manage/sql/get_chart_category.sql'


manageChartRole = PEMRole(
    'pem_manage_chart', gettext('Chart management'),
    gettext('Chart management'), gettext(
        'Privilege to manage the user defined charts, including configuring.'
    )
)


def validate_charts_data(chart):
    """
    :param chart: Chart data
    """
    valid_chart_level = [DashboardLevel.DB_GLOBAL,
                         DashboardLevel.DB_AGENT,
                         DashboardLevel.DB_SERVER,
                         DashboardLevel.DB_DATABASE]

    errmsg = None

    required_params = ['chart_title', 'chart_category', 'chart_type',
                       'chart_refresh', 'chart_level']

    # Validate required parameters
    for req in required_params:
        if req not in chart or chart[req] is None or chart[req] == "":
            errmsg = gettext(
                "Could not find the required parameter (%s)." % req
            )
        if req == 'chart_refresh':
            chart_refresh = chart['chart_refresh']
            if isinstance(chart['chart_refresh'], list) and \
                    len(chart['chart_refresh']) == 0:
                errmsg = gettext(
                    "Could not find the required parameter (%s)." % req
                )
            else:
                if isinstance(chart['chart_refresh'], list):
                    chart_refresh = int(float(chart['chart_refresh'][0]))
                else:
                    chart_refresh = int(float(chart['chart_refresh']))
                if chart_refresh < 1 or chart_refresh > 120:
                    errmsg = gettext(
                        "Please specify the refresh time between 1 and"
                        " 120 minutes."
                    )

    if 'is_capacity_chart' in chart and chart['is_capacity_chart']:
        chart['chart_level'] = [DashboardLevel.DB_GLOBAL]
    else:
        # Validate chart level
        if int(chart['chart_level']) not in valid_chart_level:
            errmsg = gettext(
                "Could not find the required parameter level."
            )
        # In Import/Export, we do not have is_capacity_chart parameter so
        # we will set the value for the same to avoid any error
        if 'is_capacity_chart' not in chart:
            chart['is_capacity_chart'] = False

    # Validate: Line Chart
    if chart['chart_type'] == 'L' and not chart['is_capacity_chart']:
        if 'sel_metrics_L' not in chart or \
                chart['sel_metrics_L'] is None or \
                not isinstance(chart['sel_metrics_L'], list) or \
                len(chart['sel_metrics_L']) == 0:
            errmsg = gettext(
                ERROR_MSG_FOR_REQUIRED_PARAMS
            )

        if 'chart_line_points' not in chart or \
                chart['chart_line_points'] is None:
            errmsg = gettext(
                "Please specify the number of points between 20 and 300."
            )
        else:
            if isinstance(chart['chart_line_points'], list):
                chart['chart_line_points'] = chart['chart_line_points'][0]
            else:
                chart['chart_line_points'] = int(chart['chart_line_points'])

            if chart['chart_line_points'] < 20 or \
                    chart['chart_line_points'] > 300:
                errmsg = gettext(
                    "Please specify the number of points between 20 and "
                    "300."
                )

        if ('chart_line_span' not in chart or
            chart['chart_line_span'] is None or
            chart['chart_line_span'] == "" or
            len(chart['chart_line_span']) != 2 or
            int(chart['chart_line_span'][0]) < 0 or
            int(chart['chart_line_span'][0]) > 90 or
            int(chart['chart_line_span'][1]) < 0 or
            int(chart['chart_line_span'][1]) > 23 or
            (int(chart['chart_line_span'][0]) == 0 and
             int(chart['chart_line_span'][
                1]) < 1)):
            errmsg = gettext(
                "Please specify the time span between 1 hour up to 90 days."
            )

        valid_params = ['mid', 'pid', 'pit']
        for m in chart['sel_metrics_L']:
            for v in valid_params:
                if v not in m or m[v] == '' or m[v] is None:
                    errmsg = gettext(
                        "Could not find the required parameter (%s) for "
                        "line chart metrics." % v
                    )

    # Validate Table Chart metrics
    if chart['chart_type'] == 'TB' and not chart['is_capacity_chart']:
        if 'sel_metrics_T' not in chart or \
                chart['sel_metrics_T'] is None or \
                not isinstance(chart['sel_metrics_T'], list) or \
                len(chart['sel_metrics_T']) == 0:
            errmsg = gettext(
                ERROR_MSG_FOR_REQUIRED_PARAMS
            )

        valid_params = ['pid', 'pit']
        for m in chart['sel_metrics_T']:
            for v in valid_params:
                if v not in m or m[v] == '' or m[v] is None:
                    errmsg = gettext(
                        "Could not find the required parameter (%s) for"
                        " table metrics." % v
                    )

    # Validate Capacity Chart metrics
    if (chart['chart_type'] == 'L' or chart['chart_type'] == 'TB' or
            chart['chart_type'] == 'CM') and chart['is_capacity_chart']:
        if 'sel_metrics_C' not in chart or \
                chart['sel_metrics_C'] is None or \
                not isinstance(chart['sel_metrics_C'], list) or \
                len(chart['sel_metrics_C']) == 0:
            errmsg = gettext(
                ERROR_MSG_FOR_REQUIRED_PARAMS
            )

        valid_params = ['params', 'vals', 'mid', 'probe', 'metric', 'agg']
        for m in chart['sel_metrics_C']:
            for v in valid_params:
                if v not in m or m[v] == '' or m[v] is None:
                    errmsg = gettext(
                        "Could not find the required parameter (%s) for"
                        " capacity chart metrics." % v
                    )
                if (v == 'params' or v == 'vals') and len(m[v]) == 0:
                    errmsg = gettext(
                        "Could not find the required parameter (%s) for"
                        " capacity chart metrics." % v
                    )

    if errmsg:
        return False, errmsg

    chart['chart_description'] = chart['chart_description'] \
        if 'chart_description' in chart else ""

    chart['teams'] = []
    if 'shared' in chart and chart['shared'] is not None \
            and chart['shared'] != "" and (
            'shared_all' not in chart or
            chart['shared_all'] is False):
        teams = chart['shared'] if isinstance(chart['shared'], list) else \
            json.loads(chart['shared'])
        chart['teams'] = teams

    chart['reload'] = chart_refresh * 60000

    return True, chart


def get_and_save_chart_category(pem_conn, chart_data, with_transaction=True):
    """
    Fetch & Save the Chart category

    :param pem_conn: PEM Connection
    :param chart_data: Chart data
    :param with_transaction: With Transaction flag
    """
    # Start Transaction
    if with_transaction:
        pem_conn.execute_void('BEGIN;')

    sql = render_template(GET_CHART_CATEGORY_SQL,
                          check_cat_id=True)

    status, cat_id = pem_conn.execute_scalar(
        sql, [chart_data['chart_category']])
    if not status:
        if with_transaction:
            pem_conn.execute_void('ROLLBACK;')
        return False, cat_id

    if cat_id is None or cat_id == '':
        sql = render_template("manage/sql/save_chart_category.sql")
        status, cat_id = pem_conn.execute_scalar(
            sql, [chart_data['chart_category'], '']
        )
        if not status:
            if with_transaction:
                pem_conn.execute_void('ROLLBACK;')
            return False, cat_id

    if with_transaction:
        pem_conn.execute_void('COMMIT;')

    chart_data['cat_id'] = cat_id

    return True, chart_data


def save_chart(
    pem_conn, chart_data, with_transaction=True, chart_imported=False
):
    """
    Save the Chart metrics

    :param pem_conn: PEM Connection
    :param chart_data: Chart data
    :param with_transaction: With Transaction flag
    :param chart_imported: if chart is imported flag
    """
    # START Transaction
    if with_transaction:
        pem_conn.execute_void('BEGIN;')

    tmp_var = [DashboardLevel.DB_GLOBAL] if chart_data['is_capacity_chart']\
        else [chart_data['chart_level']]

    sql = render_template(
        "manage/sql/create_chart.sql", chart_imported=chart_imported
    )

    cparams = [chart_data['cat_id'],
               ('CT' if chart_data['chart_type'] == 'TB' else 'CL') if
               chart_data['is_capacity_chart'] else
               chart_data['chart_type'],
               tmp_var, chart_data['chart_title'],
               chart_data['chart_description'],
               chart_data['teams'],
               chart_data['reload']
               ]
    if chart_imported:
        cparams.append(chart_data['reference_id'])
    status, chart_id = pem_conn.execute_scalar(sql, cparams)
    if not status:
        if with_transaction:
            pem_conn.execute_void('ROLLBACK;')
        return False, chart_id

    chart_data['chart_id'] = chart_id

    # END Transaction
    if with_transaction:
        pem_conn.execute_void('COMMIT;')

    return True, chart_data


def save_chart_metrics(pem_conn, chart_data, with_transaction=True):
    """
    Save the Chart metrics

    :param pem_conn: PEM Connection
    :param chart_data: Chart data
    :param with_transaction: With Transaction flag
    """
    # Start Transaction
    if with_transaction:
        pem_conn.execute_void('BEGIN;')

    if not isinstance(chart_data, dict):
        return False, "Invalid chart metrics data"

    if 'is_capacity_chart' not in chart_data:
        chart_data['is_capacity_chart'] = False

    if not chart_data['is_capacity_chart']:
        # Line chart
        if chart_data['chart_type'] == 'L':
            status, msg = pem_conn.execute_void(
                "DELETE FROM pem.line_chart WHERE cid = (%s)::int4",
                [chart_data['chart_id']])
            if not status:
                if with_transaction:
                    pem_conn.execute_void('ROLLBACK;')
                return False, msg

            status, msg = pem_conn.execute_void(
                "DELETE FROM pem.chart_metric WHERE cid = (%s)::int4",
                [chart_data['chart_id']])
            if not status:
                if with_transaction:
                    pem_conn.execute_void('ROLLBACK;')
                return False, msg

            status, msg = pem_conn.execute_void(
                "DELETE FROM pem.metrices_chart WHERE cid = (%s)::int4",
                [chart_data['chart_id']])
            if not status:
                if with_transaction:
                    pem_conn.execute_void('ROLLBACK;')
                return False, msg

            y1unit = ''
            y2unit = ''
            prev_metric = ''
            midx = 0

            for i in range(0, len(chart_data['sel_metrics_L'])):
                midx += 1
                if prev_metric != chart_data['sel_metrics_L'][i]['pid']:
                    prev_metric = chart_data['sel_metrics_L'][i]['pid']
                    status, pname = pem_conn.execute_scalar(
                        """SELECT internal_name FROM pem.probe
                         WHERE id = (%s)::int4""",
                        [prev_metric])
                    if not status:
                        if with_transaction:
                            pem_conn.execute_void('ROLLBACK;')
                        return False, pname

                mordr = None
                chart_data['sel_metrics_L'][i]['g'] = None if \
                    isinstance(chart_data['sel_metrics_L'][i]['g'], list) and\
                    chart_data['sel_metrics_L'][i]['g'][0] is None else \
                    chart_data['sel_metrics_L'][i]['g']
                if 'g' in chart_data['sel_metrics_L'][i] != ''\
                        and chart_data['sel_metrics_L'][i]['g'] is not None:
                    order_by = csv_split(
                        chart_data['sel_metrics_L'][i]['g'],
                        delimiter=',', quotechar='"'
                    )[0]
                    status, met_ordr = pem_conn.execute_scalar(
                        """SELECT internal_name FROM pem.probe_column
                         WHERE id = (%s)::int4""",
                        [order_by[0]]
                    )

                    if not status:
                        if with_transaction:
                            pem_conn.execute_void('ROLLBACK;')
                        return False, met_ordr
                    if order_by[1] == 't':
                        met_ordr += '_pit'
                    mordr = met_ordr

                mordrdir = [chart_data['sel_metrics_L'][i]['gd']] if\
                    'gd' in chart_data['sel_metrics_L'][i] != '' and \
                    chart_data['sel_metrics_L'][i]['gd'] is not None else None

                mid = chart_data['sel_metrics_L'][i]['mid']
                status, mname = pem_conn.execute_scalar(
                    """SELECT internal_name FROM pem.probe_column
                     WHERE id = (%s)::int4""",
                    [mid]
                )
                if not status:
                    if with_transaction:
                        pem_conn.execute_void('ROLLBACK;')
                    return False, mname

                status, munit = pem_conn.execute_scalar(
                    """SELECT unit_of_value FROM pem.probe_column
                     WHERE id = (%s)::int4""",
                    [mid]
                )

                if not status:
                    if with_transaction:
                        pem_conn.execute_void('ROLLBACK;')
                    return False, munit

                if chart_data['sel_metrics_L'][i]['pit'] is True or\
                        chart_data['sel_metrics_L'][i]['pit'] == 'true':
                    mname += '_pit'

                maggr = 'A'

                if munit != '':
                    if y1unit == '':
                        y1unit = munit
                    elif y2unit == '':
                        y2unit = munit

                mordr = [mordr] if mordr is not None else None

                sql = """
                INSERT INTO
                    pem.chart_metric (
                        cid, mid, tbl, metrices, agg_func,
                        glimit, gorderby, gorderdir, params
                    )
                    VALUES (
                        (%s)::int4, (%s)::int4, (%s)::text, (%s)::text[],
                        (%s)::text[], (%s)::int4, (%s)::text[],
                        (%s)::character(1)[], (%s)::pem.chart_metric_param[]
                )"""

                params = [
                    chart_data['chart_id'], midx, pname, [mname], [maggr],
                    (chart_data['sel_metrics_L'][i]['l']
                     if 'l' in chart_data['sel_metrics_L'][i] else 1),
                    mordr, mordrdir, None
                ]

                status, msg = pem_conn.execute_void(sql, params)

                if not status:
                    if with_transaction:
                        pem_conn.execute_void('ROLLBACK;')
                    return False, msg

                if 'c' in chart_data['sel_metrics_L'][i] and\
                        len(chart_data['sel_metrics_L'][i]['c']) > 0:
                    comp_objs = chart_data['sel_metrics_L'][i]['c']
                    len1 = len(comp_objs)

                    for j in range(0, len1):
                        midx += 1
                        params[1] = midx
                        params[5] = 1
                        params[6] = None
                        params[7] = None
                        params[8] = \
                            chart_data['sel_metrics_L'][i]['c'][j]['params']

                        status, msg = pem_conn.execute_void(sql, params)
                        if not status:
                            if with_transaction:
                                pem_conn.execute_void('ROLLBACK;')
                            return False, msg

            if y2unit == '':
                y2unit = None

            status, msg = pem_conn.execute_void(
                """INSERT INTO pem.line_chart (cid, type, yaxis, yaxis2) VALUES
                 ((%s)::int4, (%s)::text, (%s)::text, (%s)::text)""",
                [chart_data['chart_id'], 'M', y1unit, y2unit])
            if not status:
                if with_transaction:
                    pem_conn.execute_void('ROLLBACK;')
                return False, msg

            chart_data['chart_line_span'] = (int(
                chart_data['chart_line_span'][0]) * 24 * 60) + (
                int(chart_data['chart_line_span'][1]) * 60)

            params = [chart_data['chart_id'],
                      str(chart_data['chart_line_span']) + ' minutes',
                      chart_data['chart_line_points']]
            if 'chart_line_extrapolated_type' in chart_data:
                if chart_data['chart_line_extrapolated_type'] == 'SE':
                    chart_data['chart_line_ext'] = str(
                        (int(chart_data['chart_line_ext'][0]) * 24) + int(
                            chart_data['chart_line_ext'][1])) + ' hours'

                    params.append(chart_data['chart_line_ext'])
                    params.append(None)
                    params.append(None)
                    params.append(None)
                else:
                    params.append('0 hours')
                    params.append(None)
                    params.append(None)
                    params.append(None)
            else:
                params.append('0 hours')
                params.append(None)
                params.append(None)
                params.append(None)

            status, msg = pem_conn.execute_void(
                """
                INSERT INTO pem.metrices_chart (cid, time_span, max_points,
                ext_span, ext_id, ext_op, ext_val) VALUES ((%s)::int4,
                (%s)::interval, (%s)::int4, (%s)::interval, (%s)::integer,
                (%s)::character varying, (%s)::numeric)""",
                params)

            if not status:
                if with_transaction:
                    pem_conn.execute_void('ROLLBACK;')
                return False, msg

        elif chart_data['chart_type'] == 'TB':  # table chart
            status, msg = pem_conn.execute_void(
                "DELETE FROM pem.tbl_chart WHERE cid = (%s)::int4",
                [chart_data['chart_id']]
            )
            if not status:
                if with_transaction:
                    pem_conn.execute_void('ROLLBACK;')
                return False, msg
            status, msg = pem_conn.execute_void(
                "DELETE FROM pem.data_chart WHERE cid = (%s)::int4",
                [chart_data['chart_id']])
            if not status:
                if with_transaction:
                    pem_conn.execute_void('ROLLBACK;')
                return False, msg
            status, msg = pem_conn.execute_void(
                """INSERT INTO pem.tbl_chart (cid, type)
                 VALUES ((%s)::int4, 'D')""", [chart_data['chart_id']])
            if not status:
                if with_transaction:
                    pem_conn.execute_void('ROLLBACK;')
                return False, msg

            met_ordr = None
            met_ordrdir = None

            chart_data['sel_metrics_T'] = chart_data['sel_metrics_T'][0]
            if chart_data['sel_metrics_T']['g'] is None:
                chart_data['sel_metrics_T']['gd'] = None
                chart_data['sel_metrics_T']['order_by_pit'] = False
            else:
                if len(chart_data['sel_metrics_T']['g'].split(',')) != 2:
                    if with_transaction:
                        pem_conn.execute_void('ROLLBACK;')
                    return False, gettext(
                        "Could not find the required"
                        " parameter order by."
                    )

                chart_data['sel_metrics_T']['g'], \
                    chart_data['sel_metrics_T']['g_pit'] = \
                    chart_data['sel_metrics_T']['g'].split(',')
                if chart_data['sel_metrics_T']['g_pit'] == 't':
                    chart_data['sel_metrics_T']['order_by_pit'] = True
                else:
                    chart_data['sel_metrics_T']['order_by_pit'] = False

            if chart_data['sel_metrics_T']['g'] is not None:
                status, met_ordr = pem_conn.execute_scalar(
                    """SELECT internal_name FROM pem.probe_column
                     WHERE id = (%s)::int4""",
                    [chart_data['sel_metrics_T']['g']])
                if chart_data['sel_metrics_T']['pit'] is True:
                    met_ordr += '_pit'
                met_ordr = [met_ordr]

                if chart_data['sel_metrics_T']['gd'] is not None:
                    met_ordrdir = [chart_data['sel_metrics_T']['gd']]

            tbl_metrics = []
            for i in range(0, len(chart_data['sel_metrics_T']['metrics'])):
                mid = chart_data['sel_metrics_T']['metrics'][i]['mid']
                status, mname = pem_conn.execute_scalar(
                    """SELECT internal_name FROM pem.probe_column
                     WHERE id = (%s)::int4""", [mid])
                if not status:
                    if with_transaction:
                        pem_conn.execute_void('ROLLBACK;')
                    return False, mname
                if mname == "" or mname is None:
                    if with_transaction:
                        pem_conn.execute_void('ROLLBACK;')
                    return False, gettext("Incorrect parameter mid.")

                if chart_data['sel_metrics_T']['metrics'][i]['pit'] is True:
                    mname += '_pit'
                tbl_metrics.append(mname)

            chart_data['sel_metrics_T']['l'] =  \
                chart_data['sel_metrics_T']['l'] \
                if 'l' in chart_data['sel_metrics_T'] else None
            sql = """
                INSERT INTO pem.data_chart (cid, tbl, metrices, orderby,
                orderdir, glimit, r_sys_obj) VALUES ((%s)::int4,
                (SELECT internal_name FROM pem.probe
                WHERE id = (%s)::int4)::text, (%s)::text[], (%s)::text[],
                (%s)::character(1)[], (%s)::int4,
                (SELECT applies_to_id >= 200 FROM pem.probe WHERE
                id = (%s)::int4)::boolean)
            """
            params = [
                chart_data['chart_id'], chart_data['sel_metrics_T']['pid'],
                tbl_metrics, met_ordr, met_ordrdir,
                chart_data['sel_metrics_T']['l'],
                chart_data['sel_metrics_T']['pid']
            ]
            status, msg = pem_conn.execute_void(sql, params)
            if not status:
                if with_transaction:
                    pem_conn.execute_void('ROLLBACK;')
                return False, msg
    else:
        historical_days = chart_data['historical_days'][0] if\
            isinstance(chart_data['historical_days'], list) else\
            chart_data['historical_days']
        extrapolated_days = chart_data['extrapolated_days'][0] if\
            isinstance(chart_data['extrapolated_days'], list) else\
            chart_data['extrapolated_days']
        ch_cm_th_metric = chart_data['ch_cm_th_metric'] if\
            'ch_cm_th_metric' in chart_data else None
        ch_cm_th_val = chart_data['ch_cm_th_val'] if\
            'ch_cm_th_val' in chart_data else None
        ch_cm_th_opt = chart_data['ch_cm_th_opt'] if\
            'ch_cm_th_opt' in chart_data else None

        status, msg = pem_conn.execute_void(
            "DELETE FROM pem.capacity_report_chart WHERE cid = (%s)::int4",
            [chart_data['chart_id']])
        if not status:
            if with_transaction:
                pem_conn.execute_void('ROLLBACK;')
            return False, msg

        status, msg = pem_conn.execute_void(
            "DELETE FROM pem.chart_metric WHERE cid = (%s)::int4",
            [chart_data['chart_id']])
        if not status:
            if with_transaction:
                pem_conn.execute_void('ROLLBACK;')
            return False, msg

        sql = """
            INSERT INTO pem.capacity_report_chart(cid, type, historical,
            extrapolated, midx, tval, toperator) VALUES ((%s)::int4,
            (%s)::text, (%s)::int4, (%s)::int4, (%s)::int4, (%s)::numeric,
            (%s)::pem.cm_threshold_operator);"""

        params = [
            chart_data['chart_id'], chart_data['cm_type'],
            historical_days, extrapolated_days,
            ch_cm_th_metric, ch_cm_th_val, ch_cm_th_opt
        ]
        status, msg = pem_conn.execute_void(sql, params)
        if not status:
            if with_transaction:
                pem_conn.execute_void('ROLLBACK;')
            return False, msg

        len1 = len(chart_data['sel_metrics_C'])

        sql = """
            INSERT INTO pem.chart_metric (cid, mid, tbl, metrices, agg_func,
            glimit, params) VALUES ((%s)::int4, (%s)::int4, (%s)::text,
            (%s)::text[], (%s)::text[], (%s)::int4,
            (%s)::pem.chart_metric_param[])
        """
        for i in range(0, len1):
            paramsCnt = len(chart_data['sel_metrics_C'][i]['params'])
            valsCnt = len(chart_data['sel_metrics_C'][i]['vals'])
            params = []

            if paramsCnt != valsCnt:
                if with_transaction:
                    pem_conn.execute_void('ROLLBACK')
                return False, gettext(
                    "Parameters and Values count does not match for "
                    "the metric - {}".format(
                        chart_data['sel_metrics_C'][i]['display']
                    ))

            for j in range(0, paramsCnt):
                v = chart_data['sel_metrics_C'][i]['vals'][j]
                if v is None:
                    v = ''
                elif '"' in v:
                    v = '"' + v.replace('"', '""') + '"'
                elif ',' in v:
                    v = '"' + v + '"'
                chart_metric_param = str(
                    chart_data['sel_metrics_C'][i]['params'][j])

                # todo: temporary fix for the issue where we were
                # using psycopg2 escape identifier
                # Check for spaces or semicolons
                if " " in chart_metric_param or ";" in chart_metric_param:
                    raise ValueError(
                        f"Invalid parameter: {chart_metric_param}. "
                        "Spaces and semicolons are not allowed."
                    )

                params.insert(j, '(' + chart_metric_param +
                              ',' + v + ')')

            status, msg = pem_conn.execute_void(
                sql, [
                    chart_data['chart_id'],
                    chart_data['sel_metrics_C'][i]['mid'],
                    chart_data['sel_metrics_C'][i]['probe'],
                    [chart_data['sel_metrics_C'][i]['metric']],
                    [chart_data['sel_metrics_C'][i]['agg']],
                    1, params
                ])
            if not status:
                if with_transaction:
                    pem_conn.execute_void('ROLLBACK;')
                return False, msg

    # END Transaction
    if with_transaction:
        pem_conn.execute_void('COMMIT;')

    return True, None


def get_chart(pem_conn, cid=None, fetch_probe=False):
    """
    :param pem_conn: pem connection object
    :param cid: chart id
    :param fetch_probe: Flag to fetch probes
    """
    tbl = []

    sql = render_template(
        "manage/sql/get_chart_details.sql",
        fetch_probe=fetch_probe
    )

    # Getting chart basic details
    status, chart_details = pem_conn.execute_dict(sql, {'cid': cid})
    if not status:
        return False, chart_details

    if len(chart_details['rows']) == 0:
        return False, gettext(
            f"Couldn't find information about the chart id - {cid}")
    else:
        chart_details = chart_details['rows'][0]

    if chart_details.get('chart_refresh'):
        chart_details['chart_refresh'] = \
            int(float(chart_details['chart_refresh']))

    if chart_details['chart_type'] == 'CL' or\
            chart_details['chart_type'] == 'CT':
        chart_details['chart_level'] = 'Capacity Report Chart'
    elif isinstance(chart_details['chart_level'], list) and\
            len(chart_details['chart_level']) > 0:
        chart_details['chart_level'] = chart_details['chart_level'][0]

    # Without extrapolation
    chart_details['chart_line_extrapolated_type'] = 'NE'
    if chart_details['line_span'] is not None \
            and chart_details['line_span'] > 0:
        line_span = chart_details['line_span']
        chart_details['chart_line_span'] = [floor(line_span / 1440),
                                            floor((line_span % 1440) / 60)]
    # Span based extrapolation
    if chart_details['espan'] is not None and chart_details['espan'] > 0:
        espan = chart_details['espan']
        chart_details['chart_line_ext'] = [floor(espan / 24),
                                           floor(espan % 24)]
        chart_details['chart_line_extrapolated_type'] = 'SE'

    # Threshold based extrapolation
    if chart_details['chart_line_ext_opt'] is not None\
            and chart_details['chart_line_ext_val'] is not None:
        chart_details['chart_line_extrapolated_type'] = 'TE'

    chart_details['chart_type'] = chart_details['chart_type'].strip(' ')
    chart_details['chart_line_ext_metric_options'] = []

    sql = render_template("manage/sql/get_chart_metrics.sql")

    # Chart Metric Details
    status, chart_data = pem_conn.execute_dict(sql, {'cid': cid})
    if not status:
        return False, chart_data

    chart_data = chart_data['rows']

    rows = len(chart_data)
    if rows == 0:
        return False, gettext(
            f"Couldn't find metrics information about the chart id - {cid}")

    for num in range(0, rows):
        if chart_data[num]['tbl'] is not None:
            tbl.append(chart_data[num]['tbl'])

    sql = render_template("manage/sql/get_chart_probes.sql")

    # Chart probe details
    params = {'iname': [tbl]}
    status, metrics = pem_conn.execute_dict(sql, params)

    if not status:
        return False, gettext(
            f"Couldn't find information about the probe for chart id - {cid}")

    metrics = metrics['rows']
    probe_data = {}

    res = []
    prev_tbl = None
    prev_prob = None
    prev_metrices = None

    # Map metric with Probe and related details like display name etc.
    for m in metrics:
        is_custom_probe = False
        if m['is_system_probe'] is False and fetch_probe:
            status, probe = generate_export_probe_data(
                pem_conn, [m['probe_id']], using_ids=True,
                show_system=False, deleted=False
            )
            if not status:
                return False, probe

            if len(probe) == 0:
                return False, gettext(
                    "The dependant probe '{}' has been "
                    "deleted or not found for the chart id - '{}'"
                    "".format(m['probe_name'], cid)
                )
            is_custom_probe = True

        if m['probe_name'] != prev_prob:
            prev_prob = None
            tmp = {
                'pid': m['probe_id'],
                'metrics': {},
                'orderby': [],
                'pit': False,
                'pit_tbl': {}
            }
            # Add only when exporting
            if fetch_probe:
                tmp['is_system_probe'] = True

            # ******* IMPORTANT *********
            # Add flag so that we can create new custom Probe when importing
            # we need to update probe id & probe column id before importing
            if is_custom_probe:
                tmp['is_system_probe'] = False
                tmp['c_probe'] = probe

            probe_data.update({m['probe_name']: tmp})

        if m['probe_name'] == prev_prob or prev_prob is None:
            if m['probe_col_pit'] is True:
                tmp['pit'] = True
            tmp['orderby'].append({
                'label': m['probe_col_display'],
                'value': str(m['probe_col_id']) + ',' + m['probe_col_pit']
            })
            tmp['metrics'].update({
                m['probe_col_name']: {
                    'mid': m['probe_col_id'],
                    'name': m['probe_col_display'] +
                    " [ " + m['probe_display'] + " ]",
                    'probe_col_display': m['probe_col_display'],
                    'probe_display': m['probe_display'],
                    'probe': m['probe_name']
                }})
            tmp['applies_to_id'] = m['applies_to_id']
            tmp['probe_key_list'] = m['probe_key_list']
            tmp['probe_target_type'] = m['probe_target_type']
            tmp['probe_key_display_name'] = m['probe_col_name']
            tmp['pit_tbl'].update({m['probe_col_name']: tmp['pit']})

        prev_prob = m['probe_name']

    # Prepare chart property array
    for c in chart_data:
        c['orderby'] = c['orderby'][0] if c['orderby'] and len(
            c['orderby']) > 0 else None
        if prev_tbl != c['tbl'] or c['metrices'] != prev_metrices:
            pdata = probe_data.get(c['tbl'])
            c['orderby'] = pdata['metrics'][
                c['orderby']
            ]['probe_col_display'] if c['orderby'] else None
            g_options = copy.deepcopy(pdata['orderby'])
            for m in g_options:
                if c['orderby'] and (m['label'] == c['orderby']):
                    m['selected'] = 'selected'
                    c['orderby'] = m['value']
                elif 'selected' in m:
                    del m['selected']

            # Line Chart
            if chart_details['chart_type'] == 'L':
                probe_key_display_name = []
                internal_name = []
                for k in pdata['probe_key_list']:
                    if k in pdata['metrics']:
                        probe_key_display_name.append(
                            pdata['metrics'][k]['probe_col_display'])
                for i in c['metrices']:
                    if i.find('_pit') != -1:
                        internal_name.append(i[0:i.find('_pit')])
                    else:
                        internal_name.append(i)

                tmp = {
                    'pid': pdata['pid'],
                    'mid': pdata['metrics'].get(c['metrices'][0])['mid'],
                    'metric_id': c['mid'],
                    'g_options': g_options,
                    'g': c['orderby'],
                    'gd': c['orderdir'][0] if isinstance(c['orderdir'], list)
                    else c['orderdir'],
                    'compare': [],
                    'chart_line_ext_metric_options': [],
                    'line_ext_metric': False,
                    'c': [],
                    'pit': pdata['pit'],
                    'l': c['glimit'],
                    'mt': ", ".join(c['metrices']) if len(c['metrices']) > 1
                    else c['metrices'][0],
                    'label': pdata['metrics'].get(c['metrices'][0])[
                        'probe_col_display'
                    ],
                    'internal_name': ", ".join(internal_name)
                    if len(internal_name) > 1 else internal_name[0],
                    'm': pdata['metrics'].get(c['metrices'][0])['name'],
                    'probe_target_type': pdata['probe_target_type'],
                    'applies_to_id': pdata['applies_to_id'],
                    'probe_key_list': pdata['probe_key_list'],
                    'probe_key_display_name': probe_key_display_name,
                    'probe':
                    pdata['metrics'].get(c['metrices'][0])['probe_display']
                }
                if (tmp['g'] is None or tmp['g'][0] is None)\
                        and tmp['gd'] is None:
                    tmp['g_options'] = None
                    metric_opt = {
                        'label': tmp['m'],
                        'value': (
                            str(tmp['pid']) + ',' + str(tmp['mid']) + ',' +
                            str(tmp['pit'])
                        )
                    }

                    if tmp['metric_id'] == \
                            chart_details['chart_line_ext_metric']:
                        metric_opt['selected'] = 'selected'

                    tmp['line_ext_metric'] = True

            # Table Chart
            elif chart_details['chart_type'] == 'TB':
                tmp = {
                    'pid': pdata['pid'],
                    'g_options': g_options,
                    'g': c['orderby'],
                    'gd': c['orderdir'][0] if isinstance(c['orderdir'], list)
                    else c['orderdir'],
                    'metrics': [],
                    'pit': pdata['pit'],
                    'l': c['glimit'],
                    'm': ", ".join(c['metrices']) if len(c['metrices']) > 1
                    else c['metrices'][0]
                }
                if (tmp['g'] is None or tmp['g'][0] is None)\
                        and tmp['gd'] is None:
                    tmp['g_options'] = None

                for m in c['metrices']:
                    tbl_metrices = pdata['metrics'].get(m)
                    tbl_metrices['pit'] = pdata['pit_tbl'].get(m)
                    tmp['metrics'].append(tbl_metrices)
                    tmp['m'] = tbl_metrices['probe_display']

            # Capacity Chart
            elif chart_details['chart_type'] == 'CL' or\
                    chart_details['chart_type'] == 'CT':
                tmp = {
                    'probe_id': pdata['pid'],
                    'metric_id': pdata['metrics'].get(c['metrices'][0])['mid'],
                    'mid': c['mid'],
                    'pit': pdata['pit'],
                    'agg': c['agg_funcs'],
                    'metric_display_name': pdata['metrics'].get(
                        c['metrices'][0])['probe_col_display'],
                    'probe_display': pdata['metrics'].get(
                        c['metrices'][0])['probe_display'],
                    'params': c['param_names'],
                    'vals': c['param_vals'],
                    'metric': c['metrices'][0],
                    'probe': pdata['metrics'].get(c['metrices'][0])['probe'],
                    'obj': c['object_description']
                }
            # append our custom probe for export
            if fetch_probe:
                tmp['is_system_probe'] = pdata['is_system_probe']
                if is_custom_probe:
                    tmp['c_probe'] = pdata['c_probe']
            res.append(tmp)
        # Line Chart Comparison
        elif chart_details['chart_type'] == 'L' and c['params']:
            c['param_vals'] = ['' if v is None else
                               v.replace(',', '\\\\,') if (v and ',' in v)
                               else v for v in c['param_vals']]
            comp_params = '{'
            for i in range(0, len(c['param_names'])):
                comp_params += '"(' + c['param_names'][i] + \
                    ',' + c['param_vals'][i] + ')",'
            comp_params = comp_params[0:len(comp_params) - 1] + "}"
            tmp['compare'].append(comp_params)
            tmp['chart_line_ext_metric_options'].append({
                'label': tmp['m'] + "[" + c['object_description'] + "/" +
                '/'.join(c['param_vals'][1:len(c['param_vals'])]) +
                "]",
                'value': (str(tmp['pid']) + ',' + str(tmp['mid']) + ',' +
                          str(tmp['pit']) + ',' +
                          c['param_vals'][len(c['param_vals']) - 1]),
                'metric_id': c['mid']
            })

        elif chart_details['chart_type'] == 'TB':
            tmp['metrices'].append({'mid': pdata['metrics'].get(
                c['metrices'][0]), 'pit': pdata['pit']})

        prev_tbl = c['tbl']
        prev_metrices = c['metrices']

    if chart_details['chart_type'] == 'L':
        chart_details['sel_metrics_L'] = res
    elif chart_details['chart_type'] == 'TB':
        chart_details['sel_metrics_T'] = res
    elif chart_details['chart_type'] == 'CL' or\
            chart_details['chart_type'] == 'CT':
        chart_details['sel_metrics_C'] = res
        chart_details['is_capacity_chart'] = True
        chart_details['chart_type'] = 'L' if\
            chart_details['chart_type'] == 'CL' else 'TB'
        chart_details['historical_days'] = chart_data[0]['historical_days']
        chart_details['extrapolated_days'] = chart_data[0]['extrapolated_days']
        chart_details['ch_cm_th_metric'] = chart_data[0]['midx']
        chart_details['ch_cm_th_val'] = chart_data[0]['tval']
        chart_details['ch_cm_th_opt'] = chart_data[0]['toperator']
        chart_details['cm_type'] = chart_data[0]['cm_type']

    return True, chart_details


def generate_export_chart_data(pem_conn, charts):
    """
    :param pem_conn: pem connection object
    :param charts: list of chart ids
    """
    res = []
    for chart in charts:
        status, details = get_chart(pem_conn, cid=chart, fetch_probe=True)
        if not status:
            return False, details
        res.append(details)
    return True, res


def update_metric_custom_probe_columns_data(pem_conn, probe, metric):
    """
    :param pem_conn: pem connection object
    :param probe: Data of probe
    :param metric: Data of metric
    """
    status, probe_id = pem_conn.execute_scalar("""
    SELECT id FROM pem.probe WHERE internal_name = %s
    """, [probe['internal_name']])
    if not status:
        return False, probe_id

    # PID here
    metric['pid'] = int(probe_id)

    status, res = pem_conn.execute_dict("""
    SELECT * FROM pem.probe_column WHERE probe_id = %s
    """, [probe_id])
    if not status:
        return False, res

    for column in res['rows']:
        if column['internal_name'] == metric['internal_name']:
            prev_mid = metric['mid']
            metric['mid'] = int(column['id'])
            if metric['g_options'] is None:
                continue
            for g_opt in metric['g_options']:
                # Update the column id references
                if g_opt['label'] == metric['label']:
                    g_opt['value'] = g_opt['value'].replace(
                        str(prev_mid), str(column['id'])
                    )
                if 'selected' in g_opt and g_opt['selected']:
                    metric['g'] = metric['g'].replace(
                        str(prev_mid), str(column['id'])
                    )

    return True, None


def create_probe(pem_conn, probe, skip_overwrite_probe):
    """
    :param pem_conn: pem connection object
    :param probe: Data of probe
    :param skip_overwrite_probe: Skip existing probe
    """
    # Before inserting Chart we must insert the dependent probes
    probes_result = insert_imported_probes(
        pem_conn, [probe],
        skip_overwrite_probe, with_transaction=False
    )
    for probe in probes_result:
        # If one of the probe failed then Error out & jump to next
        if probe['status'] == 'Failed':
            return False, probe['msg']
    return True, None


def check_and_create_probe(
    pem_conn, chart, skip_overwrite_probe
):
    """
    :param pem_conn: pem connection object
    :param chart: Data of chart
    :param skip_overwrite_probe: Skip existing probe
    """
    metrics = []
    # To keep track of newly created probes
    created_probes = []
    # if not capacity chart then
    if not chart['is_capacity_chart']:
        if chart['chart_type'] == 'L':
            metrics = chart['sel_metrics_L']
        elif chart['chart_type'] == 'TB':
            metrics = chart['sel_metrics_T']
    else:
        metrics = chart['sel_metrics_C']

    for metric in metrics:
        if 'c_probe' in metric and len(metric['c_probe']) > 0 and \
                metric['is_system_probe'] is False:
            for probe in metric['c_probe']:
                probe_name = probe['internal_name']
                if probe_name not in created_probes:
                    status, res = create_probe(
                        pem_conn, probe, skip_overwrite_probe)
                    if not status:
                        return status, res
                    # Make record of newly created probes
                    created_probes.append(probe_name)

                # If Probe is created then update the Probe Column ids
                status, res = update_metric_custom_probe_columns_data(
                    pem_conn, probe, metric)
                if not status:
                    return status, res

    return True, None


def remove_existing_chart(pem_conn, chart_data):
    """
    :param pem_conn: pem connection object
    :param chart_data: existing chart to remove
    """
    status, msg = pem_conn.execute_void(
        "DELETE FROM pem.line_chart WHERE cid = (%s)::int4",
        [chart_data['id']])
    if not status:
        return False, msg

    status, msg = pem_conn.execute_void(
        "DELETE FROM pem.chart_metric WHERE cid = (%s)::int4",
        [chart_data['id']])
    if not status:
        return False, msg

    status, msg = pem_conn.execute_void(
        "DELETE FROM pem.metrices_chart WHERE cid = (%s)::int4",
        [chart_data['id']])
    if not status:
        return False, msg

    status, msg = pem_conn.execute_void(
        "DELETE FROM pem.tbl_chart WHERE cid = (%s)::int4",
        [chart_data['id']]
    )
    if not status:
        return False, msg
    status, msg = pem_conn.execute_void(
        "DELETE FROM pem.data_chart WHERE cid = (%s)::int4",
        [chart_data['id']])
    if not status:
        return False, msg
    status, msg = pem_conn.execute_void(
        """INSERT INTO pem.tbl_chart (cid, type)
         VALUES ((%s)::int4, 'D')""", [chart_data['id']])
    if not status:
        return False, msg

    status, msg = pem_conn.execute_void(
        "DELETE FROM pem.capacity_report_chart WHERE cid = (%s)::int4",
        [chart_data['id']])
    if not status:
        return False, msg

    status, msg = pem_conn.execute_void(
        "DELETE FROM pem.chart_metric WHERE cid = (%s)::int4",
        [chart_data['id']])
    if not status:
        return False, msg

    status, msg = pem_conn.execute_void(
        "DELETE FROM pem.chart WHERE id = (%s)::int4",
        [chart_data['id']])
    if not status:
        return False, msg

    return True, None


def insert_imported_charts(
    pem_conn, charts, skip_existing=True,
    skip_overwrite_probe=True, with_transaction=True
):
    """
    :param pem_conn: pem connection object
    :param charts: list of charts
    :param skip_existing: Skip existing chart
    :param skip_overwrite_probe: Skip existing probe
    :param with_transaction: With transaction flag
    """
    _FAILED = "Failed"
    _SUCCESS = "Success"
    _SKIPPED = "Skipped"
    final_result = []

    def update_store(_name, _status="Success", _msg=None):
        """Avoid duplication of code using this inner function"""
        final_result.append({
            'name': _name,
            'status': _status,
            'msg': _msg
        })

    for chart in charts:
        # check using reference_id column
        if 'reference_id' not in chart or not chart['reference_id']:
            update_store(
                chart['chart_title'], _FAILED,
                gettext("Please provide valid reference id for the chart")
            )
            continue

        # Validate request first
        status, _chart = validate_charts_data(chart)
        if not status:
            update_store(
                chart['chart_title'], _FAILED,
                _chart
            )
            continue
        chart = _chart

        # Start Xtn for inserting chart
        if with_transaction:
            status, _ = pem_conn.execute_void('BEGIN')
            if not status:
                update_store(
                    chart['chart_title'], _FAILED,
                    gettext("Failed to start the transaction")
                )
                continue

        # Check if chart already exists using reference_id column and skip
        # is true then Skip it
        status, existing_record = pem_conn.execute_dict("""
        SELECT * FROM pem.chart WHERE reference_id = %s
        """, [chart['reference_id']])
        if not status:
            update_store(
                chart['chart_title'], _FAILED,
                gettext("Failed to fetch the chart information "
                        "due to an error - {}".format(existing_record))
            )
            if with_transaction:
                pem_conn.execute_void('ROLLBACK')
            continue

        if len(existing_record['rows']) > 0 and skip_existing:
            update_store(chart['chart_title'], _SKIPPED)
            if with_transaction:
                pem_conn.execute_void('ROLLBACK')
            continue
        elif len(existing_record['rows']) > 0:
            if existing_record['rows'][0]['deleted']:
                status, res = pem_conn.execute_void("""
                UPDATE pem.chart SET deleted = 'false'::boolean
                WHERE reference_id = %s
                """, [chart['reference_id']])
                if not status:
                    update_store(
                        chart['chart_title'], _FAILED,
                        gettext("Unable to enable the deleted chart "
                                "due to an error - {}".format(res))
                    )
                    if with_transaction:
                        pem_conn.execute_void('ROLLBACK')
                    continue
                # Commit the transaction if with_transaction is True
                if with_transaction:
                    commit_status, _ = pem_conn.execute_void('COMMIT')
                    if not commit_status:
                        pem_conn.execute_void('ROLLBACK')
                        update_store(
                            chart['chart_title'], _FAILED,
                            gettext(
                                "Failed to commit the transaction after "
                                "enabling the chart")
                        )
                        continue
                # Return from here as chart is there
                update_store(chart['chart_title'], _SUCCESS, None)
                continue
            else:
                # Delete everything and create new chart
                status, res = remove_existing_chart(
                    pem_conn, existing_record['rows'][0])
                if not status:
                    update_store(
                        chart['chart_title'], _FAILED,
                        gettext("Failed to remove existing  the chart "
                                "due to an error - {}".format(res))
                    )
                    if with_transaction:
                        pem_conn.execute_void('ROLLBACK')
                    continue

        # If probe is custom then we need to create that
        # probe and use the columns data from newly created
        # probe instead of the id provided by file because
        # source and target may have different probe column ids
        status, result = check_and_create_probe(
            pem_conn, chart, skip_overwrite_probe)
        if not status:
            if with_transaction:
                pem_conn.execute_void('ROLLBACK')
            update_store(chart['chart_title'], _FAILED, result)
            continue

        status, chart_data = get_and_save_chart_category(
            pem_conn, chart)
        if not status:
            if with_transaction:
                pem_conn.execute_void('ROLLBACK')
            update_store(chart['chart_title'], _FAILED, chart_data)
            continue

        status, chart_data = save_chart(pem_conn, chart_data, True, True)
        if not status:
            if with_transaction:
                pem_conn.execute_void('ROLLBACK')
            update_store(chart['chart_title'], _FAILED, chart_data)
            continue

        status, chart_data = save_chart_metrics(pem_conn, chart_data)
        if not status:
            if with_transaction:
                pem_conn.execute_void('ROLLBACK')
            update_store(chart['chart_title'], _FAILED, chart_data)
            continue

        if with_transaction:
            status, _ = pem_conn.execute_void('COMMIT')
            if not status:
                pem_conn.execute_void('ROLLBACK')
                update_store(
                    chart['chart_title'], _FAILED,
                    gettext("Failed to commit the transaction"))
                continue

        update_store(chart['chart_title'], _SUCCESS, None)

    return final_result
