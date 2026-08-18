##########################################################################
#
# Postgres Enterprise Manager
#
# Copyright (C) 2016 - 2025, EnterpriseDB Corporation. All rights reserved.
#
##########################################################################
"""Implementation for the group chart."""

import os
from flask import session
import json
from flask_babel import gettext
from flask import url_for, render_template
from pgadmin.pem.misc.import_helper import urlencode
from pgadmin.utils.ajax import make_json_response, \
    make_response as ajax_response
from pgadmin.pem.utils import pem_connection
from pgadmin.pem.misc.error import error_return, PEMErrorType

from pgadmin.pem.monitor.utils.charts import SYSTEM_CHART_DESCRIPTIONS

CURRENT_PATH = os.path.dirname(os.path.realpath(__file__))


@pem_connection
def group_chart_data(
        did, cid, aid=0, sid=0, group_id=0,
        trans_id=0, database=None, tbl=None, schema=None,
        start_time=None, end_time=None, sort_index=None,
        sort_direction=None, pem_conn=None
):
    """This function returns essential data for chart to render"""
    from random import randint
    data = {}
    group_id = str(group_id)

    if trans_id == 0:
        trans_id = str(randint(1, 9999999))

    # Now fetch chart data
    try:
        with open(CURRENT_PATH + '/test_data.json') as data_file:
            file_data = json.load(data_file)
            data = file_data['chart_data'][trans_id][group_id]
    except Exception as e:
        print(("Error while reading file: %s", str(e)))

    return make_json_response(data=data)


def chart_to_draw(total_metrics):
    # Metrics/chart limit
    limit = 6
    return int(len(total_metrics) / limit)


@pem_connection
def get_chart_information(did, id, title, showTitle=False, aid=None,
                          sid=None, database=None, schema=None,
                          tbl=None, group_id=None,
                          trans_id=None, pem_conn=None):
    did = int(did)
    id = int(id)
    showTitle = showTitle if isinstance(showTitle, bool) else (
        showTitle is True if isinstance(showTitle, str) else False)

    params = {'cid': id, 'did': did,
              'level': 'system'}
    if aid is not None and aid != 0:
        params['aid'] = aid
        params['level'] = 'agent'
    if sid is not None and sid != 0:
        params['sid'] = sid
        params['level'] = 'server'
    if database is not None:
        params['database'] = database
        params['level'] = 'database'
    if schema is not None:
        params['schema'] = urlencode(schema)
        params['level'] = 'schema'
    if tbl is not None:
        params['tbl'] = urlencode(tbl)
        params['level'] = 'table'

    base_url = url_for('pem_dashboard.index')

    sql = render_template("dashboard/sql/chart_query.sql", cid=id)
    status, res = pem_conn.execute_dict(sql)
    if not status:
        error_return(
            gettext("Error executing query: {0}".format(res)),
            e_type=PEMErrorType.JSON
        )

    if status and 'rows' in res:
        result = res['rows'][0]
        # Fetch info and set into chart properties
        if (len(result) > 0):
            type = result['type'].strip()
            # if cType is not None:
            #     type = cType
            type = 'GL'

            if (title is None):
                title = result['name']

            description = None if result['description'] is None \
                else result['description']
            levels = result['levels']
            levels = levels.split(',')
            levels = levels.sort()
            summary = None if result['summary'] is None \
                else result['summary']
            deleted = True if result['deleted'] else False
            reload = result['reload']
            owner = result['owner']
            xaxis = result['xaxis']
            yaxis = result['yaxis']
            yaxis2 = result['yaxis2']
            if (result['static_labels'] is None and
                    result['display_labels'] is None):
                labels = []
            elif result['static_labels'] is not None:
                # Static label is None, then the chart was created in
                # customizable dashboard.
                # We don't store labels for the customizable dashboard,
                # since the dashboard may have dynamic attribute/metrices
                # to be displayed. Hence, we are setting the probe column
                # display_names as
                # labels
                labels = result['static_labels']

            initialized = True

            if ('SYSTEM_CHART_DESCRIPTIONS' in globals() and
                    id in SYSTEM_CHART_DESCRIPTIONS):
                description = SYSTEM_CHART_DESCRIPTIONS[id]
            if (description is None):
                description = ''
        else:
            errorMsg = gettext(
                "Couldn't find the chart in the Postgres Enterprise \
                Manager database.")

        chart_options = {
            'HtmlText': False, 'shadowSize': 1, 'parseFloat': False,
            'ieBackgroundColor': '#FFFFFF',
            'xaxis': {
                'mode': 'time',
                'timeMode': 'local', 'minorTickFreq': 0,
                'autoscale': False, 'autoscaleMargin': 0,
                'noTicks': 8, 'title': xaxis
            },
            'yaxis': {
                'autoscale': True, 'autoscaleMargin': 0.2,
                'noTicks': 10, 'title': "MB",
            },
            'selection': {'mode': 'x'},
            'y2axisTitle': yaxis2,
            'mouse': {
                'track': True, 'trackY': True, 'relative': True,
                'sensibility': 4, 'lineColor': '#CDC9C9',
                'position': 'n'
            },
            'lines': {'show': True, 'lineWidth': 1, 'stacked': False},
            'points': {
                'show': True, 'radius': 1.35, 'lineWidth': 1,
                'hitRadius': 3
            },
            'spreadsheet': {'show': False, 'xaxisLabel': 'Aggregated time'},
            'grid': {'backgroundColor': '#FFFFFF'}
        }
        options = {
            'options': chart_options,
            'initialized': initialized,
            'type': 'GL',
            'showTitle': showTitle,
            'reload': int(reload),
            'owner': owner,
            'params': params,
            'remote_monitoring_error': False,
            'default_error_msg': ''
        }
        return options


@pem_connection
def get_chart_metadata(did, cid, aid=None, sid=None, database=None,
                       group_id=0, trans_id=None, pem_conn=None):
    """Generate chart metadata"""

    data = {}

    # If trans_id is None, request is first time, create a new trans_id and
    # then create each chart with unique id
    if 'group_chart' not in session or \
            trans_id not in session['group_chart']:
        objects = None
        session['group_chart'] = {}
        dash_session = session['group_chart'][trans_id] = {}

        # Now fetch chart data
        try:
            with open(CURRENT_PATH + '/test_data.json') as data_file:
                file_data = json.load(data_file)
                objects = file_data['objects']
        except Exception as e:
            print(("Error while reading file: %s", str(e)))

        # Calculate metrics/chart to draw
        metrics_per_group = chart_to_draw(objects)
        dash_session['number_of_metrics'] = len(objects)
        dash_session['metrics_per_group'] = metrics_per_group
        dash_session['chart_options'] = {}
        dash_session['groups'] = {}

        if aid:
            dash_session['chart_options'] = \
                get_chart_information(
                    did, cid, "CPU chart", True, aid=aid,
                    group_id=group_id, trans_id=trans_id
            )
        elif sid:
            dash_session['chart_options'] = \
                get_chart_information(
                    did, cid, "CPU chart", True, sid=sid,
                    group_id=group_id, trans_id=trans_id
            )

        x = 0
        for i in range(1, len(objects) + 1, metrics_per_group):
            # split objects into chunks by n
            # Generate each chart's unique id
            x = x + 1
            group_id = x

            dash_session['groups'][group_id] = \
                objects[i:i + metrics_per_group]

        data = dash_session
    else:
        # Retrieve metrics from session for chart
        # Retrieve all metrics for chart from table and compare them
        if trans_id in session['group_chart']:
            # print(session['group_chart'][trans_id])
            # print(trans_id)
            data = session['group_chart'][trans_id]

    return ajax_response(
        response=data,
        status=200
    )
