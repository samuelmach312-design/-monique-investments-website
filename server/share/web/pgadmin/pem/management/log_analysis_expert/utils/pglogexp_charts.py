#############################################################################
#
# Postgres Enterprise Manager
#
# Copyright (C) 2015 - 2025, EnterpriseDB Corporation. All rights reserved.
#
# web/pglogexp_charts.py - PgLogExpert Chart
#
#############################################################################

from flask_babel import gettext
from pgadmin.pem.monitor.dashboard.utils.charts import PEMChartAlign, \
    PEMChartWidth
from pgadmin.pem.monitor.dashboard.helpers.chart import whichColor

TABLE_HEADER_LABEL_MAPPING = {
    'Settings': gettext('Settings'),
    'Values': gettext('Values'),
    'Time': gettext('Time'),
    'Database Name': gettext('Database name'),
    'Statement': gettext('Statement'),
    'Count': gettext('Count'),
    'Min Duration': gettext('Min duration'),
    'Max Duration': gettext('Max duration'),
    'Avg Duration': gettext('Avg duration'),
    'error_severity': gettext('Error severity'),
    'message': gettext('Message'),
    'no_of_events': gettext('No of events'),
    'no_of_logs': gettext('No of logs'),
    'log_time': gettext('Log time'),
    'tempfile_size': gettext('Tempfile size'),
    'query': gettext('Query'),
    'relation': gettext('Relation'),
    'index_details': gettext('Index details'),
    'page_details': gettext('Page details'),
    'tuple_details': gettext('Tuple details'),
    'buffer_details': gettext('Buffer details'),
    'read_rate': gettext('Read rate'),
    'system_usage': gettext('System usage'),
    'tag': gettext('Tag'),
    'parameters': gettext('Parameters'),
    'duration': gettext('Duration'),
    'host': gettext('Host'),
    'database': gettext('Database'),
    'no_of_times_executed': gettext('No of times executed'),
    'total_duration': gettext('Total duration'),
}


def fetch_chart_data(async_conn, params, chart_obj, server_id, server_data):
    chart_params = [
        server_data['start_date_time'],
        server_data['end_date_time']
    ]

    if chart_obj['type'] == 0:
        # Parameter type varies for the line/table charts.

        chart_params.append(server_id)
        query = "BEGIN WORK; SET DATESTYLE TO 'SQL, DMY';"
        async_conn.execute_void(query)
        # Don't put the number of rows limit, if it's summarized statistics
        # table.
        if chart_obj['id'] == 1:
            query = """
                SELECT
                    {0}((SELECT TIMESTAMP 'epoch' + (%s) * INTERVAL '1
                    second')::timestamp,
                    (SELECT TIMESTAMP 'epoch' + (%s) * INTERVAL '1
                    second')::timestamp,
                    (%s)::int)""".format(chart_obj['method'])
        else:
            chart_params.append(params['rows_limit'])
            query = """
                SELECT
                    {0}((SELECT TIMESTAMP 'epoch' + (%s) * INTERVAL '1
                    second')::timestamp,
                    (SELECT TIMESTAMP 'epoch' + (%s) * INTERVAL '1
                    second')::timestamp,
                    (%s)::int, (%s)::int)""".format(chart_obj['method'])

        status, refcursor = async_conn.execute_2darray(query, chart_params)

        refcursor_name = refcursor['rows'][0][0]
        fetch_query = "FETCH ALL FROM " + refcursor_name
        status, res = async_conn.execute_async(fetch_query)
        return status, res

    elif chart_obj['type'] == 1:
        query = "BEGIN WORK; SET DATESTYLE TO 'SQL, DMY';"
        async_conn.execute_void(query)

        chart_params.append(str(params['interval']))
        chart_params.append(params['aggregate_method'])
        chart_params.append(server_id)
        if chart_obj['target_name'] is not None:
            chart_params.append(chart_obj['target_name'])
            chart_params.append(chart_obj['tags'])
            chart_params.append(chart_obj['exact_match'])
            query = """
            SELECT
                {0}((SELECT TIMESTAMP 'epoch' + (%s) * INTERVAL '1
                second')::timestamp,
                (SELECT TIMESTAMP 'epoch' + (%s) * INTERVAL '1
                second')::timestamp,
                (%s)::interval, (%s)::TEXT, (%s)::INT,
                (%s)::text, (%s)::text[], (%s)::boolean)""".format(
                chart_obj['method'])
        else:
            query = """
            SELECT
                {0}((SELECT TIMESTAMP 'epoch' + (%s) * INTERVAL '1
                second')::timestamp,
                (SELECT TIMESTAMP 'epoch' + (%s) * INTERVAL '1
                second')::timestamp,
                (%s)::interval, (%s)::TEXT, (%s)::INT)""".format(
                chart_obj['method'])

        status, refcursor = async_conn.execute_2darray(query, chart_params)

        refcursor_name = refcursor['rows'][0][0]
        fetch_query = "FETCH ALL FROM " + refcursor_name

        status, res = async_conn.execute_async(fetch_query)
        return status, res


def build_chart(
        result, column_info, data, server_id, pem_conn, timezoneoffset=0):

    params = data['params']
    current_server = data['current_server']
    current_analyzer = data['current_analyzer']
    pId = params['analyzers'][current_analyzer]
    pServerID = params['servers'][current_server]
    chart_obj = data['chart_config'][str(pId)]

    if chart_obj['type'] == 0:
        type_codes = tuple({col['type_code'] for col in column_info})
        type_query = 'SELECT oid, typname  FROM  pg_catalog.pg_type ' \
                     'WHERE oid IN %s;'

        status, coldata = pem_conn.execute_dict(type_query,
                                                [type_codes])

        type_name_dict = {
            row['oid']: row['typname'] for row in coldata['rows']}

        for column in column_info:
            if column['type_code'] in type_name_dict:
                column['type'] = type_name_dict[column['type_code']]
                column['name'] = TABLE_HEADER_LABEL_MAPPING.get(
                    column['name'], column['name']
                )
            column['is_number'] = pem_conn.is_number(column['type_code'])

        chart_data = {
            "id": pId,
            "level": pServerID,
            "label": gettext(chart_obj['chart_headers']),
            "align": PEMChartAlign.CENTER,
            "width": PEMChartWidth.FULL,
            "type": chart_obj['type'],
            "chart-data": {
                'columns': column_info,
                'data': result
            },
        }
    elif chart_obj['type'] == 1:
        width = PEMChartWidth.FULL

        data_series = []
        label = None
        prev_label = None
        metric_series = []
        min = 0
        max = 0
        color_counter = 0

        metric_col_pos, data_series_col_pos = None, None
        for col in column_info:
            if col['name'] == 'metric':
                metric_col_pos = col['pos']
            if col['name'] == 'data_series':
                data_series_col_pos = col['pos']

        if result is not None:
            for row in result:
                label = row[metric_col_pos]

                if prev_label is None or prev_label == label:
                    prev_label = label
                    metric_series.append(
                        list(map(float, row[data_series_col_pos])))

                elif (prev_label != label) and len(metric_series) > 0:
                    data_series.append({'data': metric_series,
                                        'label': gettext(prev_label),
                                        'color': whichColor(color_counter, 0)})
                    if min == 0 and max == 0:
                        min = metric_series[0][0]
                        max = metric_series[len(metric_series) - 1][0]

                    metric_series = []
                    color_counter += 1
                    metric_series.append(
                        list(map(float, row[data_series_col_pos])))
                    prev_label = label

        if len(metric_series) > 0:
            data_series.append({'data': metric_series,
                                'label': gettext(label),
                                'color': whichColor(color_counter, 0)})
            if min == 0 and max == 0:
                min = metric_series[0][0]
                max = metric_series[len(metric_series) - 1][0]
            metric_series = None

        x_axis_options = []
        x_axis_options.append([min, max])
        chart_data = {'data_series': data_series}

        chart_data = {
            "id": pId,
            "level": pServerID,
            "label": gettext(chart_obj['chart_headers']),
            "width": width,
            "type": chart_obj['type'],
            "is_pie": chart_obj['is_pie'],
            "chart-data": {
                'data_series': data_series,
                'x_axis_opts': x_axis_options
            }
        }
    return chart_data
