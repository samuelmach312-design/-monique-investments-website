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
from pgadmin.pem.monitor.utils import DashboardLevel
from pgadmin.pem.monitor.utils.charts import SYSTEM_CHART_DESCRIPTIONS
from pgadmin.pem.monitor.charts.manage.utils import \
    generate_export_chart_data, insert_imported_charts
from pgadmin.pem.utils.role import PEMRole


manageDashboardRole = PEMRole(
    'pem_manage_dashboard', gettext('Dashboard management'),
    gettext('Dashboard management'), gettext(
        'Privilege to manage the user defined dashboard, '
        'including configuring.'
    )
)


def validate_dashboard_request_data(data):
    """
    :param data: Dashboard request data
    :return:
    """
    errmsg = None
    valid_dashboards = [
        DashboardLevel.DB_GLOBAL, DashboardLevel.DB_AGENT,
        DashboardLevel.DB_SERVER, DashboardLevel.DB_DATABASE
    ]

    # Validate Dashboard name
    if 'name' not in data or data['name'] is None or data['name'] == '':
        errmsg = gettext(
            "Could not find the required parameter name."
        )

    # Validate Dashboard level
    if 'level' not in data or data['level'] is None or \
            data['level'] == '' or int(data['level']) not in valid_dashboards:
        errmsg = gettext(
            "Could not find the required parameter level."
        )

    data['show_title'] = True \
        if 'show_title' not in data else data['show_title']

    data['descp'] = None if 'descp' not in data else \
        data['descp']

    data['is_ops'] = False if 'is_ops' not in data else \
        data['is_ops']

    data['font'] = None if 'font' not in data else (
        data['font'] if data['is_ops'] else None)

    data['font_size'] = data.get('font_size', None) \
        if data.get('is_ops', False) is True else None

    data['teams'] = []
    if 'shared' in data and data['shared'] is not None \
            and data['shared'] != "" and \
            ('shared_all' not in data or data['shared_all'] is False):
        teams = data['shared'] if isinstance(
            data['shared'], list) else \
            json.loads(data['shared'])
        data['teams'] = teams

    if errmsg:
        return False, errmsg

    return True, data


def get_dashboard(pem_conn, dashboard_id, is_export=False):
    """

    :param pem_conn: PEM Connection
    :param dashboard_id: Dashboard ID
    :param is_export: Export flag
    :return:
    """
    sql = render_template(
        "custom_dashboard/sql/properties.sql", is_export=is_export
    )
    status, dashboards = pem_conn.execute_dict(sql, [dashboard_id])
    if not status:
        return False, dashboards

    if len(dashboards['rows']) == 0:
        return False, gettext('No dashboard found.')

    sql = render_template("custom_dashboard/sql/section_list.sql")
    status, sections = pem_conn.execute_dict(sql, [dashboard_id])

    if not status:
        return False, sections

    dashboards = dashboards['rows'][0]
    dashboards['design_layout'] = []
    if is_export:
        dashboards['c_charts'] = []

    if 'rows' in sections:
        old_sec_id = ''
        is_chart_process = []
        for db in sections['rows']:
            if old_sec_id != db['sec_id']:
                charts = []
                dashboards['design_layout'].append({
                    'sec_id': db['sec_id'],
                    'sec_title': db['sec_title'],
                    'charts': charts})
            if (db['chart_descp'] is None or db['chart_descp'] == '') and \
                    (db['chart_id'] in SYSTEM_CHART_DESCRIPTIONS):
                db['chart_descp'] = SYSTEM_CHART_DESCRIPTIONS[db['chart_id']]

            if is_export and db['chart_id'] not in is_chart_process and \
                    db["is_custom_chart"]:
                is_chart_process.append(db['chart_id'])
                status, c_res = generate_export_chart_data(
                    pem_conn, [db['chart_id']])
                if not status:
                    return False, c_res
                # We don't need array, we will append each as object
                dashboards['c_charts'].append(c_res[0])
            charts.append(db)
            old_sec_id = db['sec_id']

    return True, dashboards


def generate_export_dashboard_data(pem_conn, dashboards):
    """
    Fetch the dashboard data
    :param pem_conn: PEM Connection
    :param dashboards: List of dashboards
    :return:
    """
    result = []
    for did in dashboards:
        status, res = get_dashboard(pem_conn, did, is_export=True)
        if not status:
            return False, res
        result.append(res)
    return True, result


def save_dashboard(pem_conn, data, with_transaction=True, is_import=False):
    """
    Saves the dashboard in the database

    :param pem_conn: PEM Connection
    :param data: Dashboard data
    :param with_transaction: Transaction flag
    :param is_import: Import flag
    :return:
    """
    if with_transaction:
        pem_conn.execute_void("BEGIN;")

    status, owner = pem_conn.execute_scalar(
        "SELECT oid FROM pg_roles WHERE rolname = current_user")

    if not status:
        if with_transaction:
            pem_conn.execute_void('ROLLBACK;')
        return False, owner

    params = [data['name'], data['level'], owner, data['descp'],
              data['teams'], data['font'], data['font_size'],
              data['is_ops'], data['show_title']]

    if is_import:
        params.append(data['reference_id'])

    sql = render_template(
        "custom_dashboard/sql/store.sql", is_import=is_import
    )

    status, did = pem_conn.execute_scalar(sql, params)
    if not status:
        if with_transaction:
            pem_conn.execute_void('ROLLBACK;')
        return False, did

    data['id'] = did

    sql = render_template("custom_dashboard/sql/delete_section.sql")
    status, msg = pem_conn.execute_void(sql, [did])

    if not status:
        if with_transaction:
            pem_conn.execute_void('ROLLBACK;')
        return False, msg

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
                    if with_transaction:
                        pem_conn.execute_void('ROLLBACK;')
                    return False, section

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
                        status, chart = pem_conn.execute_void(
                            sql, chart_params
                        )
                        if not status:
                            if with_transaction:
                                pem_conn.execute_void('ROLLBACK;')
                            return False, chart

    if with_transaction:
        status, msg = pem_conn.execute_void("COMMIT;")
        if not status:
            pem_conn.execute_void('ROLLBACK;')
            return False, msg

    return True, did


def insert_imported_dashboards(
    pem_conn,
    dashboards,
    skip_existing=True,
    skip_existing_chart=True,
    skip_overwrite_probe=True,
    with_transaction=True
):
    """

    :param pem_conn: PEM Connection
    :param dashboards: List of dashboards
    :param skip_existing:
    :param skip_existing_chart:
    :param skip_overwrite_probe:
    :param with_transaction:
    :return:
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

    for dashboard in dashboards:
        # check using reference_id column
        if 'reference_id' not in dashboard or not dashboard['reference_id']:
            update_store(
                dashboard['name'], _FAILED,
                gettext("Please provide valid reference id for the dashboard")
            )
            continue

        # Validate request first
        status, _dashboard = validate_dashboard_request_data(dashboard)
        if not status:
            update_store(
                dashboard['name'], _FAILED,
                _dashboard
            )
            continue
        dashboard = _dashboard

        # Start Xtn for inserting chart
        if with_transaction:
            status, _ = pem_conn.execute_void('BEGIN')
            if not status:
                update_store(
                    dashboard['name'], _FAILED,
                    gettext("Failed to start the transaction")
                )
                continue

        # Check if chart already exists using reference_id column and skip
        # is true then Skip it
        status, existing_record = pem_conn.execute_dict("""
        SELECT * FROM pem.dashboard WHERE reference_id = %s
        """, [dashboard['reference_id']])
        if not status:
            update_store(
                dashboard['name'], _FAILED,
                gettext("Failed to fetch the dashboard information "
                        "due to an error - {}".format(existing_record))
            )
            if with_transaction:
                pem_conn.execute_void('ROLLBACK')
            continue

        if len(existing_record['rows']) > 0 and skip_existing:
            update_store(dashboard['name'], _SKIPPED)
            if with_transaction:
                pem_conn.execute_void('ROLLBACK')
            continue
        elif len(existing_record['rows']) > 0:
            # We need to delete the existing dashboard first
            status, res = pem_conn.execute_void("""
            DELETE FROM pem.dashboard
            WHERE reference_id = %s
            """, [dashboard['reference_id']])
            if not status:
                update_store(
                    dashboard['name'], _FAILED,
                    gettext("Unable to enable the deleted dashboard "
                            "due to an error - {}".format(res))
                )
                if with_transaction:
                    pem_conn.execute_void('ROLLBACK')
                continue

        # First create required custom chart
        # We need to update chart_id field with
        # existing OR newly created chart id
        charts_result = insert_imported_charts(
            pem_conn,
            dashboard["c_charts"],
            skip_existing_chart,
            skip_overwrite_probe,
            with_transaction=False
        )

        chart_error = None
        chart_name = None
        for _chart in charts_result:
            # If one of the chart fails then Error out & jump to next
            if _chart['status'] == 'Failed':
                chart_name = _chart['name']
                chart_error = _chart['msg']
                break

        if chart_error:
            update_store(
                dashboard['name'], _FAILED,
                gettext("It failed to create the chart '{}' "
                        "due to an error - {}".format(chart_name, chart_error))
            )
            if with_transaction:
                pem_conn.execute_void('ROLLBACK')
            continue

        # Update the new CHART ID in the design_layout dict before inserting
        for _layout in dashboard['design_layout']:
            chart_error = None
            for _chart in _layout['charts']:
                # if not custom chart then no need to update the chart id
                if _chart['is_custom_chart'] is False:
                    continue

                # Fetch the new chart id
                status, chart_id = pem_conn.execute_scalar("""
                SELECT id FROM pem.chart WHERE reference_id = %s
                """, [_chart['reference_id']])
                if not status:
                    # If there is an error then break the loop and report error
                    chart_error = chart_id
                    break

                # Update the new chart id
                _chart['chart_id'] = chart_id

            # If there's an error updating chart id then skip it
            if chart_error:
                update_store(
                    dashboard['name'], _FAILED,
                    gettext("Unable to fetch the chart id "
                            "due to an error - {}".format(chart_error))
                )
                if with_transaction:
                    pem_conn.execute_void('ROLLBACK')
                break

        # Save the Dashboard
        status, dashboard_result = save_dashboard(
            pem_conn, dashboard, with_transaction=False,
            is_import=True
        )
        if not status:
            update_store(
                dashboard['name'], _FAILED,
                gettext("Unable to create the dashboard "
                        "due to an error - {}".format(dashboard_result))
            )
            if with_transaction:
                pem_conn.execute_void('ROLLBACK')
            continue

        if with_transaction:
            status, _ = pem_conn.execute_void('COMMIT')
            if not status:
                pem_conn.execute_void('ROLLBACK')
                update_store(
                    dashboard['name'], _FAILED,
                    gettext("Failed to commit the transaction"))
                continue

        update_store(dashboard['name'], _SUCCESS, None)

    return final_result
