###############################################################################
#
# Postgres Enterprise Manager
# Copyright (C) 2011 - 2025, EnterpriseDB Corporation. All rights reserved.
#
# File:       cm_linecharts.py
# Purpose:    Renders the line charts for the CM dashboards in PEM
#
###############################################################################
"""
Renders the linechart/table for Capacity Manager for each metric
"""

import random
import re

import json
from flask import render_template
from flask_babel import gettext
from math import ceil

from pgadmin.pem.misc.import_helper import quote
from pgadmin.pem.monitor.dashboard.utils import DashboardTransaction
from pgadmin.pem.utils import datetimeFromPGISOString, \
    datetimeToPGISOString
from pgadmin.pem.utils import pem_connection, \
    get_params, execute_iterator

# List of aggregation values supported
AGGREGATIONS = ['AVG', 'MIN', 'MAX', 'FIRST']


def get_color(color_name):
    # Default colors
    globals()['COLOR_0'] = '#FF0000'
    globals()['COLOR_1'] = '#FFDD33'
    globals()['COLOR_2'] = '#1545ED'
    globals()['COLOR_3'] = '#3CB371'
    globals()['COLOR_4'] = '#EE82EE'
    globals()['COLOR_5'] = '#FFA500'
    globals()['COLOR_6'] = '#8B3A62'
    globals()['COLOR_7'] = '#FF6EC4'
    globals()['COLOR_8'] = '#777777'
    globals()['COLOR_9'] = '#00008B'
    globals()['COLOR_10'] = '#9400D3'
    globals()['COLOR_11'] = '#BDB76D'
    globals()['COLOR_12'] = '#AAAAAA'
    globals()['COLOR_13'] = '#32CD32'
    globals()['COLOR_14'] = '#CD5C5C'
    globals()['COLOR_15'] = '#CDAA7D'
    globals()['COLOR_16'] = '#409EA0'
    globals()['COLOR_17'] = '#E0EE20'
    globals()['COLOR_18'] = '#76EEC6'
    globals()['COLOR_19'] = '#DDDDDD'
    globals()['COLOR_20'] = '#6495ED'
    globals()['COLOR_21'] = '#8A2BE2'
    globals()['COLOR_22'] = '#8B7355'
    globals()['COLOR_23'] = '#53868B'
    globals()['COLOR_24'] = '#FF7256'
    globals()['COLOR_25'] = '#E0D0C0'
    globals()['COLOR_26'] = '#00CDCD'
    globals()['COLOR_27'] = '#EEAD0E'
    globals()['COLOR_28'] = '#FF1493'
    globals()['COLOR_29'] = '#CD6090'
    globals()['COLOR_30'] = '#E0EEB0'
    globals()['COLOR_31'] = '#8B864E'
    globals()['COLOR_32'] = '#7CFC00'

    return globals()[color_name]


def formatted_error_message(error_string):
    """
    This function returns the error message based on error code.

    :param error_string: return by the server.
    :return: parsed error message based on error code.
    """
    if 'CONTEXT' in error_string:
        error_string = error_string.split('CONTEXT')[0].strip()
    if error_string == '1':
        return gettext("Insufficient information is available between the "
                       "start date/time and the end date/time or threshold "
                       "to generate the report.")
    elif error_string == '2':
        return gettext("The specified date range or threshold is invalid.")

    error_code = re.findall(r"ERROR:\s+(\d{1,})", error_string)
    if len(error_code) > 0:
        if error_code[0] == '1':
            return gettext("Insufficient information is available between "
                           "the start date/time and the end date/time or "
                           "threshold to generate the report.")
        elif error_code[0] == '2':
            return gettext("The specified date range or threshold is invalid.")
        else:
            return error_code
    else:
        return error_string


@pem_connection
def linechart_capacity_manager_metric(
    start_date, current_date, end_value, required_points, single_metric,
    trans_id=0, pem_conn=None
):
    # Always return timestamp/date/timestamptz in ISO format
    pem_conn.execute_void("SET datestyle TO iso")

    min_probe_interval = 0
    metric = single_metric['metric_info']
    aggregation = metric['aggregation'].upper()
    _label = '{0} ({1})'.format(
        single_metric['label'],
        metric['metric_object']
    )
    if aggregation not in AGGREGATIONS:
        return {
            'label': _label,
            'error': gettext("Invalid value for parameter aggregation.")
        }

    dashboard_transaction = DashboardTransaction(
        trans_id, pem_conn.conn_id, -1, random.randint(1, 9999999)
    )

    params = {'internal_name': metric['metric'], 'cid': metric['metric_id']}

    sql = render_template('capacity_manager/sql/is_probe_exist.sql')

    with dashboard_transaction:
        status, is_deleted = pem_conn.execute_scalar(sql, params)
    if not status:
        return {
            'error': is_deleted,
            'success': 0
        }

    if is_deleted is None or is_deleted == "t":
        return {
            'error': quote(
                gettext(
                    "Probe required to render this chart no longer exist."
                )),
            'success': 0
        }

    sql = render_template('capacity_manager/sql/probe_interval.sql')

    with dashboard_transaction:
        status, min_probe_interval = pem_conn.execute_scalar(sql, params)

    if not status:
        return {
            'error': min_probe_interval,
            'success': 0
        }

    now_epoch = datetimeFromPGISOString(current_date)

    start_epoch = datetimeFromPGISOString(start_date)
    if start_epoch is None:
        return {
            'label': single_metric['label'] + ' (' + metric[
                'metric_object'] + ')',
            'error': "Provided start date is not in valid format."
        }

    # get the end date
    end_date = end_value
    # get end epoch time from end time also. see if end time is less then
    # current time then use this to find time interval or else use the current
    # time.

    end_epoch = datetimeFromPGISOString(end_date)
    if end_epoch is None:
        return {
            'label': _label,
            'error': "Provided end date is not in valid format."
        }

    if end_epoch < now_epoch:
        time_interval = ceil(
            (end_epoch - start_epoch).total_seconds() / required_points
        )
    else:
        time_interval = ceil(
            (now_epoch - start_epoch).total_seconds() / required_points
        )

    if time_interval < min_probe_interval:
        time_interval = min_probe_interval

    sql = render_template('capacity_manager/sql/linear_trend_analysis.sql')

    metric_name = metric['metric']
    if metric['pit'] and metric['pit'] != 'x':
        metric_name = metric['metric'] + "_pit"

    with dashboard_transaction:
        status, int_name = pem_conn.execute_scalar(
            render_template('capacity_manager/sql/probe_internal_name.sql'), {
                'internal_name': metric['metric'], 'cid': metric['metric_id']
            })

    if not status:
        return {
            'error': int_name,
            'success': 0
        }

    params = {'probe_table': int_name,
              'aggregate_function': aggregation,
              'probe_data_column': metric_name,
              'start_time': datetimeToPGISOString(start_epoch),
              'end_time': datetimeToPGISOString(end_epoch),
              'cur_time': datetimeToPGISOString(now_epoch),
              'time_interval': str(time_interval),
              'required_points': required_points,
              'probe_target_key_list': single_metric['met_keys'],
              'probe_target_value_list': single_metric['met_values'],
              'cutoff_count': 0,
              'agent_id': 1}

    try:
        with dashboard_transaction:
            status, results = execute_iterator(pem_conn, sql, params)

        if not status:
            return {
                'label': _label,
                'error': formatted_error_message(results)
            }

        return [{
            'data': results._rows,
            'label': _label,
            'color': get_color('COLOR_0')
        }]
    except Exception as e:
        return {
            'label': _label,
            'error': str(e)
        }


# Renders the linechart/table for Capacity Manager comparing multiple metrics
@pem_connection
def linechart_capacity_manager_report(
    start_date, current_date, end_value, required_points,
    metrics, threshold=None, trans_id=0, pem_conn=None
):
    dashboard_transaction = DashboardTransaction(
        trans_id, pem_conn.conn_id, -1, random.randint(1, 9999999)
    )

    with dashboard_transaction:
        # Always return timestamp/date/timestamptz in ISO format
        pem_conn.execute_void("SET datestyle TO iso")

    cutoff_count = 0
    min_probe_interval = 0
    res = list()
    # Loop through the no of metrics
    for x, row in enumerate(metrics):
        # get the minimum probe execution interval value
        metric = row
        minfo = metric['metric_info']

        sql = render_template('capacity_manager/sql/is_probe_exist.sql')

        with dashboard_transaction:
            status, is_deleted = pem_conn.execute_scalar(
                sql, {
                    'internal_name': minfo['metric'],
                    'cid': minfo['metric_id']
                })

        if not status:
            return {
                'error': is_deleted,
                'success': 0
            }

        if is_deleted is None or is_deleted == "t" or is_deleted is True:
            return json.dumps({
                'error': quote(
                    "One or more probes required to render this chart no "
                    "longer exist."),
                'success': 0
            })

        sql = render_template('capacity_manager/sql/probe_interval.sql')

        with dashboard_transaction:
            status, tmp_time_interval = pem_conn.execute_scalar(
                sql, {
                    'internal_name': minfo['metric'],
                    'cid': minfo['metric_id']
                })

        if not status:
            return {
                'error': tmp_time_interval,
                'success': 0
            }

        if x == 0:
            # Set min_probe_interval to the frequency of the probe related to
            # first metric
            min_probe_interval = tmp_time_interval
        else:
            # Check for frequency of probes related to other metrics and change
            # if frequency is less than the current min_probe_interval
            if tmp_time_interval < min_probe_interval:
                min_probe_interval = tmp_time_interval

    now_epoch = datetimeFromPGISOString(current_date)
    start_epoch = datetimeFromPGISOString(start_date)

    _label = metric['label'] + ' (' + minfo[
        'metric_object'] + ')'

    if start_epoch is None:
        res.append({
            'label': _label,
            'error': formatted_error_message(
                "Provided start date is not in valid format.")
        })
        return res

    # get the end date
    if threshold is None:
        # get the end date
        end_date = end_value

        # Get end epoch time from end time also. see if end time is less then
        # current time then use this to find time interval or else use the
        # current time.
        end_epoch = datetimeFromPGISOString(end_date)
        if end_epoch is None:
            res.append({
                'label': _label,
                'error': formatted_error_message(
                    "Provided end date is not in valid format.")
            })
            return res

        if end_epoch < now_epoch:
            time_interval = ceil(
                (end_epoch - start_epoch).total_seconds() / required_points
            )
        else:
            time_interval = ceil(
                (now_epoch - start_epoch).total_seconds() / required_points
            )

        if time_interval < min_probe_interval:
            time_interval = min_probe_interval
    else:
        # Get the cut-off count based on the threshold value after which we
        # need to stop generation of the chart
        time_interval = ceil(
            (now_epoch - start_epoch).total_seconds() / required_points
        )
        if time_interval < min_probe_interval:
            time_interval = min_probe_interval

        time_interval *= 2
        # Doubling the time interval as fudge-factor in case the threshold
        # extrapolates to more than twice the data points got from history

        sql = render_template(
            'capacity_manager/sql/probe_internal_name.sql'
        )

        with dashboard_transaction:
            status, thres_probe = pem_conn.execute_scalar(
                sql, {
                    'internal_name': minfo['metric'],
                    'cid': minfo['metric_id']
                })

        if not status:
            return {
                'error': thres_probe,
                'success': 0
            }

        thres_metric = minfo['metric']
        if minfo['pit'] == "t" or minfo['pit'] is True:
            thres_metric = minfo['metric'] + "_pit"

        max_years = get_params('cm_max_end_date_in_years')

        if not isinstance(max_years, int):
            max_years = 5

        import datetime

        end_epoch = now_epoch + datetime.timedelta(days=(max_years * 365))

        sql = render_template(
            'capacity_manager/sql/linear_trend_threshold.sql'
        )

        thres_opr = 'false' if threshold[2] == 'FALLS_BELOW' \
            else 'true'

        thres_params = {
            'probe_table': thres_probe,
            'probe_data_column': thres_metric,
            'start_time': datetimeToPGISOString(start_epoch),
            'cur_time': datetimeToPGISOString(now_epoch),
            'threshold': threshold[1],
            'exceeds_opr': thres_opr,
            'time_interval': str(time_interval),
            'probe_target_key_list': metric['met_keys'],
            'probe_target_value_list': metric['met_values'],
            'max_end_time_in_years': max_years,
            'agent_id': int(metric['met_values'][0])
        }

        with dashboard_transaction:
            status, cutoff_count = pem_conn.execute_scalar(sql, thres_params)

        if not status:
            res.append({
                'label': _label,
                'error': formatted_error_message(cutoff_count)
            })

    # generate the body of the sql query
    for x, row in enumerate(metrics):
        sql = render_template(
            'capacity_manager/sql/linear_trend_analysis.sql'
        )

        # generate the params list
        metric = row
        minfo = metric['metric_info']
        metric_name = minfo['metric']

        aggregation = minfo['aggregation'].upper()

        _label = metric['label'] + ' (' + minfo['metric_object'] + ')'

        if aggregation not in AGGREGATIONS:
            res.append({
                'label': _label,
                'error': gettext("Invalid value for parameter aggregation.")
            })

        if minfo['pit'] == "t" or minfo['pit'] is True:
            metric_name = metric_name + "_pit"

        with dashboard_transaction:
            status, probe_int_name = pem_conn.execute_scalar(
                render_template(
                    'capacity_manager/sql/probe_internal_name.sql'
                ), {
                    'internal_name': minfo['metric'],
                    'cid': minfo['metric_id']
                }
            )
        params = {'probe_table': probe_int_name,
                  'aggregate_function': aggregation,
                  'probe_data_column': metric_name,
                  'start_time': datetimeToPGISOString(start_epoch),
                  'end_time': datetimeToPGISOString(end_epoch),
                  'cur_time': datetimeToPGISOString(now_epoch),
                  'time_interval': str(time_interval),
                  'required_points': required_points,
                  'probe_target_key_list': metric['met_keys'],
                  'probe_target_value_list': metric['met_values'],
                  'cutoff_count': cutoff_count,
                  'agent_id': 1}

        try:
            with dashboard_transaction:
                status, results = execute_iterator(pem_conn, sql, params)
            if not status:
                res.append({
                    'label': _label,
                    'error': formatted_error_message(results)
                })
            else:
                if results._rows:
                    res.append({
                        'data': results._rows,
                        'label': _label,
                        'color': get_color('COLOR_' + str(x))
                    })
        except Exception as e:
            print(e)
            res.append({
                'label': _label,
                'error': str(e)
            })
    return res
