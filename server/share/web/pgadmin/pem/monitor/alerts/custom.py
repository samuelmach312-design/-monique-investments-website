##########################################################################
#
# Postgres Enterprise Manager
#
# Copyright (C) 2016 - 2025, EnterpriseDB Corporation. All rights reserved.
#
##########################################################################

"""Implements Custom Alerts"""

import json
from flask import render_template, request, Response
from pgadmin.utils.ajax import internal_server_error, \
    make_json_response, make_response, bad_request
from flask_security import login_required
from pgadmin.pem.utils import pem_connection
from flask_babel import gettext
from functools import wraps
from pgadmin.pem.monitor.utils import DashboardLevel
from pgadmin.pem.utils import get_sql_placeholders
from . import utils
from pgadmin.pem.monitor.utils.import_export import CURRENT_EXPORT_VERSION, \
    get_pem_installation_id, is_export_version_supported, \
    get_import_schema_version
from pgadmin.pem.monitor.probes.utils import insert_imported_probes


def request_validator(f):
    """
    This function will validates requests and it's parameters if necessary
    """

    @wraps(f)
    def wrapped(*args, **kwargs):
        valid_request_parameters = True
        msg = ''
        # Check if we have valid show_alert_level
        if 'show_alert_level' in kwargs:
            if not kwargs['show_alert_level'] >= 0:
                valid_request_parameters = False
                msg = "Invalid show alert level provided"

        # If validation fails return from here
        if not valid_request_parameters:
            return bad_request(gettext(msg))

        return f(*args, **kwargs)

    return wrapped


@login_required
@utils.manageAlertRole.check_role(
    gettext(
        "Logged-in user do not have permission to access custom alert "
        "template.")
)
@request_validator
@pem_connection
def alerts(show_alert_level=0, pem_conn=None):
    """
    This function will return the list of all the alerts
    including system and custom.

    :param show_alert_level: Type of level for custom alert to be displayed
    :param pem_conn: PEM Connection object.
    """
    sql = render_template('alerts/sql/custom_alert/list.sql',
                          show_alert_level=show_alert_level,
                          show_all_templates=False)

    # Get custom alert list
    status, custom_alerts = pem_conn.execute_dict(sql)

    if not status:
        return internal_server_error(errormsg=custom_alerts)

    # Format parameter option values
    for row in custom_alerts['rows']:
        param_options = []
        if row['param_names'] is not None and len(row['param_names']) > 0:
            if row['param_units'] is not None and len(row['param_units']) > 0:
                for param in zip(row['param_names'], row['param_types'],
                                 row['param_units']):
                    param_options.append({
                        "param_names": param[0], "param_types": param[1],
                        "param_units": param[2]
                    })
            else:
                for param in zip(row['param_names'], row['param_types']):
                    param_options.append({
                        "param_names": param[0], "param_types": param[1],
                        "param_units": ''
                    })
        row['params'] = param_options

    # Format probe dependency list
    for row in custom_alerts['rows']:
        param_options = []
        if row['probe_dependency_list'] is not None:
            sql = render_template('alerts/sql/custom_alert/probe_list.sql')
            # Get probe dependency list for custom alerts
            status, deps_list = pem_conn.execute_dict(sql)
            name_mapping = dict()
            for dep in deps_list['rows']:
                name_mapping[dep['internal_name']] = dep['display_name']
            for index in range(len(row['probe_dependency_list'])):
                l_internal_name = row['probe_dependency_list'][index]
                param_options.append({
                    "display_name": name_mapping.get(l_internal_name),
                    "internal_name": l_internal_name})
        row['probe_dependency_list'] = param_options

    return make_response(response={'custom_alerts': custom_alerts['rows']},
                         status=200)


@login_required
@utils.configAlertRole.check_role(
    gettext(
        "Logged-in user do not have permission to access custom alert "
        "template.")
)
@request_validator
@pem_connection
def all_alerts(pem_conn=None):
    """
    This function returns a list of all alerts, both system and custom.

    :param show_alert_level: Type of level for custom alert to be displayed
    :param pem_conn: PEM Connection object.
    """
    # Fetch custom alert list
    sql = render_template('alerts/sql/custom_alert/list.sql',
                          show_alert_level=0,
                          show_all_templates=True)
    status, custom_alerts = pem_conn.execute_dict(sql)

    if not status:
        return internal_server_error(errormsg=custom_alerts)

    # Fetch probe dependency names once
    sql = render_template('alerts/sql/custom_alert/probe_list.sql')
    status, deps_list = pem_conn.execute_dict(sql)
    if not status:
        return internal_server_error(errormsg=deps_list)

    # Map internal names to display names for probe dependencies
    name_mapping = {dep['internal_name']: dep['display_name']
                    for dep in deps_list['rows']}

    # Process each row for parameters and probe dependencies
    for row in custom_alerts['rows']:
        # Format param options
        param_names = row.get('param_names')
        param_types = row.get('param_types')
        param_units = row.get('param_units') or [''] * len(param_names or [])

        row['params'] = [
            {"param_names": name, "param_types": p_type, "param_units": unit}
            for name, p_type, unit in
            zip(param_names or [], param_types or [], param_units)
        ]

        # Format probe dependency list
        probe_dependency_list = row.get('probe_dependency_list', [])
        row['probe_dependency_list'] = [
            {
                "display_name": name_mapping.get(internal_name, "Unknown"),
                "internal_name": internal_name
            }
            for internal_name in probe_dependency_list
        ]

    return make_response(response={'custom_alerts': custom_alerts['rows']},
                         status=200)


@login_required
@utils.configAlertRole.check_role(
    gettext(
        "Logged-in user do not have permission to access alert "
        "template.")
)
@request_validator
@pem_connection
def all_auto_created_alerts(pem_conn=None):
    """
    This function returns a list of all auto created alerts.

    """
    # Fetch custom alert list
    sql = render_template('alerts/sql/alerts/auto_created_alerts.sql')
    status, custom_alerts = pem_conn.execute_dict(sql)

    if not status:
        return internal_server_error(errormsg=custom_alerts)

    # Fetch probe dependency names once
    sql = render_template('alerts/sql/custom_alert/probe_list.sql')
    status, deps_list = pem_conn.execute_dict(sql)
    if not status:
        return internal_server_error(errormsg=deps_list)

    # Map internal names to display names for probe dependencies
    name_mapping = {dep['internal_name']: dep['display_name']
                    for dep in deps_list['rows']}

    # Process each row for parameters and probe dependencies
    for row in custom_alerts['rows']:
        # Format param options
        param_names = row.get('param_names')
        param_types = row.get('param_types')
        param_units = row.get('param_units') or [''] * len(param_names or [])

        row['params'] = [
            {"param_names": name, "param_types": p_type, "param_units": unit}
            for name, p_type, unit in
            zip(param_names or [], param_types or [], param_units)
        ]

        # Format probe dependency list
        probe_dependency_list = row.get('probe_dependency_list', [])
        row['probe_dependency_list'] = [
            {
                "display_name": name_mapping.get(internal_name, "Unknown"),
                "internal_name": internal_name
            }
            for internal_name in probe_dependency_list
        ]

    return make_response(response={'custom_alerts': custom_alerts['rows']},
                         status=200)


@login_required
@utils.manageAlertRole.check_role(
    gettext(
        "Logged-in user do not have permission to access probe dependency "
        "list.")
)
@pem_connection
def probe_dep_list(pem_conn=None):
    """
    This function will return probe dependency list.

    :param pem_conn: PEM Connection object.
    """
    sql = render_template('alerts/sql/custom_alert/probe_list.sql')

    # Get probe dependency list for custom alerts
    status, alert_probe_dep_list = pem_conn.execute_dict(sql)

    if not status:
        return internal_server_error(errormsg=alert_probe_dep_list)

    res = []
    for row in alert_probe_dep_list['rows']:
        res.append(
            {'label': row['display_name'],
             'value': row['display_name'],
             'display_name': row['display_name'],
             'internal_name': row['internal_name']
             }
        )

    return make_json_response(data={'status': status, 'probe_list': res})


@login_required
@utils.manageAlertRole.check_role(
    gettext(
        "Logged-in user do not have permission to save custom alert template.")
)
@pem_connection
def save(pem_conn=None):
    """
    This function is used to store the custom alerts configuration
    and newly created custom alerts.

    :param pem_conn: PEM Connection object.
    """
    if request.data:
        data = json.loads(request.data.decode())
    else:
        data = request.args or request.form
    custom_alert_data = data[0]
    original_alert_data = data[1]['custom_alerts']

    status = True
    result = None
    pem_conn.execute_void('BEGIN')

    # Update existing alert template
    if 'changed' in custom_alert_data:
        for row in custom_alert_data['changed']:
            validation_status, msg = validate_update_template_params(
                row, pem_conn)
            if not validation_status:
                return internal_server_error(errormsg=msg)
            status, result = update_custom_alert(row, original_alert_data)
            if not status:
                pem_conn.execute_void('ROLLBACK')
                return internal_server_error(errormsg=result)

    # Add new alert template
    if 'added' in custom_alert_data:
        for row in custom_alert_data['added']:
            # Insert into pem.alert_template table
            status, result = insert_custom_alert(row)
            if not status:
                pem_conn.execute_void('ROLLBACK')
                return internal_server_error(errormsg=result)

    # Delete alert template
    if 'deleted' in custom_alert_data:
        alert_ids = []
        for row in custom_alert_data['deleted']:
            alert_ids.append(row['id'])

        sql = render_template(
            'alerts/sql/custom_alert/delete.sql',
            placeholders=get_sql_placeholders(alert_ids))

        status, result = pem_conn.execute_void(sql, alert_ids)
        if not status:
            pem_conn.execute_void('ROLLBACK')
            return internal_server_error(errormsg=result)

    pem_conn.execute_void('COMMIT')

    return make_json_response(data={'status': status, 'result': result})


def validate_insert_template_params(data, pem_conn=None):
    """
    :param data: Custom Alert data for inserting new custom alert template
    :param pem_conn: pem connection object
    """
    # If alert template name is provided then it should not be empty.
    if 'name' in data:
        if data['name'] is None or not data['name']:
            return False, gettext("Provide valid alert template name.")
    else:
        return False, gettext("Alert template name cannot be empty.")

    # If Description for alert template is provided then it should not
    # be empty.
    if 'description' in data:
        if data['description'] is None or not data['description']:
            return False, gettext(
                "Provide valid description for alert template.")
    else:
        return False, gettext(
            "Description for alert template cannot be empty.")

    # If Description for alert template is provided then it should not
    # be empty.
    if 'object_type' in data:
        try:
            obj_type = 0
            if data['object_type'] is None:
                return False, gettext("Provide valid object type for "
                                      "alert template.")
            obj_type = float(data['object_type'])
        except ValueError:
            return False, gettext("Object type value should be numeric only.")

        obj_type = int(data['object_type'])
        if obj_type not in [DashboardLevel.DB_GLOBAL,
                            DashboardLevel.DB_AGENT,
                            DashboardLevel.DB_SERVER,
                            DashboardLevel.DB_DATABASE,
                            DashboardLevel.DB_SCHEMA,
                            DashboardLevel.DB_TABLE,
                            DashboardLevel.DB_INDEX,
                            DashboardLevel.DB_SEQUENCE,
                            DashboardLevel.DB_FUNCTION]:
            return False, gettext(
                "Provide valid object type for alert template.")
    else:
        return False, gettext("Object type cannot be empty.")

    # If applicable on server for alert template is provided then it should not
    # be empty and it should be 'ALL','POSTGRES_SERVER', 'ADVANCED_SERVER'
    # as valid value.
    if 'applicable_on_server' in data:
        if data['applicable_on_server'] is None or \
            not data['applicable_on_server'] or \
            (data['applicable_on_server']
             not in ['ALL', 'POSTGRES_SERVER', 'ADVANCED_SERVER']):
            return False, gettext("Provide valid applicable server type for "
                                  "alert template.")
    else:
        return False, gettext("Applicable server cannot be empty.")

    # If check frequency for alert template is provided then it should not
    # be empty and it should be numeric value only.
    # Check frequency is required parameter and it should not be empty.
    # If history retention for alert template is provided then it should not
    # be empty and it should be numeric value only.
    if 'default_check_frequency' in data:
        try:
            if data['default_check_frequency'] is None:
                return False, gettext("Provide valid check frequency value.")
            float(data['default_check_frequency'])
        except ValueError:
            return False, gettext(
                "Check frequency value should be numeric only.")

        if int(data['default_check_frequency']) <= 0 or \
                int(data['default_check_frequency']) > 65534:
            return False, gettext(
                "Valid range for check frequency is 1-65534.")
    else:
        return False, gettext("Check frequency cannot be empty.")

    # If history retention for alert template is provided then it should not
    # be empty and it should be numeric value only.
    if 'default_history_retention' in data:
        try:
            if data['default_history_retention'] is None:
                return False, gettext("Provide valid history retention value.")
            float(data['default_history_retention'])
        except ValueError:
            return False, gettext(
                "History retention value should be numeric only.")

        if int(data['default_history_retention']) <= 0 or \
                int(data['default_history_retention']) > 999999:
            return False, gettext(
                "Valid range for history retention is 1-999999.")
    else:
        return False, gettext("History retention cannot be empty.")

    # Validate operator, low, medium, high threshold values only when its True
    if 'is_auto_create' in data and data['is_auto_create'] is True:
        # Operator is required parameter and it should not be empty.
        if 'operator' in data:
            if data['operator'] is None or not data['operator'] or \
                    (data['operator'] != ">" and data['operator'] != "<"):
                return False, gettext(
                    "Provide valid operator for threshold value")

        # low threshold value is required parameter and it
        # should not be empty.
        if 'low_threshold_value' in data:
            try:
                if data['low_threshold_value'] is None:
                    return False, gettext(
                        "Low threshold value cannot be empty.")
                i_low = float(data['low_threshold_value'])
            except ValueError:
                return False, gettext("Low threshold value should be numeric.")
        else:
            return False, gettext("Low threshold value is a required "
                                  "parameter.")

        # medium threshold value is required parameter and it
        # should not be empty.
        if 'medium_threshold_value' in data:
            try:
                if data['medium_threshold_value'] is None:
                    return False, gettext(
                        "Medium threshold value cannot be empty.")
                i_med = float(data['medium_threshold_value'])
            except ValueError:
                return False, gettext(
                    "Medium threshold value should be numeric.")
        else:
            return False, gettext("Medium threshold value is a required "
                                  "parameter.")

        # high threshold value is required parameter and it
        # should not be empty.
        if 'high_threshold_value' in data:
            try:
                if data['high_threshold_value'] is None:
                    return False, gettext(
                        "High threshold value cannot be empty.")
                i_high = float(data['high_threshold_value'])
            except ValueError:
                return False, gettext("High threshold value should be "
                                      "numeric.")
        else:
            return False, gettext("High threshold value is a required "
                                  "parameter.")

        # If operator provided is '>' then threshold values should be in
        # ascending order. if operator is '<' then threshold values
        # should be in descending order.
        if 'operator' in data:
            if data['operator'] == ">":
                if not (i_low < i_med < i_high):
                    return False, gettext(
                        "Threshold values should be in ascending order.")
            else:
                if not (i_low > i_med > i_high):
                    return False, gettext(
                        "Threshold values should be in descending order.")
    elif 'is_auto_create' in data and data['is_auto_create'] is not False:
        return False, gettext(
            "Provide valid value for auto create.")

    # Check for valid parameters value.
    if 'params' in data:
        alert_count = 0
        # Check any alert is created with this template before updating the
        # alert template. if alert exists then we should not allow to edit
        # parameters.
        if 'id' in data:
            sql = render_template('alerts/sql/custom_alert/alert_exists.sql',
                                  alert_template_id=data['id'])

            status, result = pem_conn.execute_dict(sql)
            if not status:
                return False, gettext(
                    "Error getting alert details with template "
                    "id.")

            alert_count = result['rows'][0]['alert_count']
            if alert_count > 0:
                return False, gettext(
                    "Alert exists with this alert template id "
                    "so cannot modify parameter options.")

        # Validate input parameters now
        if not data['is_auto_create']:
            if (len(data['params']) > 0):
                for param in data['params']:
                    if 'param_types' not in param or \
                            'param_names' not in param or \
                            'param_units' not in param:
                        return False, gettext("Missing parameters options in "
                                              "input list.")
                    if not param['param_types'] or not param['param_names']:
                        return False, gettext("Parameter name and type value "
                                              "cannot be empty.")

    # Check for valid probe list.
    if 'probe_dependency_list' in data:
        # Validate input probe dependency parameters now
        if data['probe_dependency_list'] and \
                len(data['probe_dependency_list']) > 0:
            for param in data['probe_dependency_list']:
                if 'display_name' not in param or \
                        'internal_name' not in param:
                    return False, gettext("Missing parameter in "
                                          "probe dependency list.")
                if not param['display_name'] or not param['internal_name']:
                    return False, gettext("Display or internal name cannot be "
                                          "empty in probe dependency list.")

    if 'sql' in data:
        if data['sql'] is None or not data['sql']:
            return False, gettext("Provide sql code for alert template.")
    else:
        return False, gettext("SQL code for alert template cannot be empty.")

    return True, gettext('')


@login_required
@pem_connection
def insert_custom_alert(alert_data, pem_conn=None, return_data=False):
    """

    :param alert_data: alert data for new custom alert
    :param pem_conn: pem connection object
    """
    # Valide the input data for recommended values

    status, msg = validate_insert_template_params(alert_data)
    if not status:
        return status, gettext(msg)

    data = dict()
    status = False
    result = None

    if 'name' in alert_data:
        data['name'] = alert_data['name']
    if 'description' in alert_data:
        data['description'] = alert_data['description']
    if 'object_type' in alert_data:
        data['object_type'] = int(alert_data['object_type'])
    if 'applicable_on_server' in alert_data:
        data['applicable_on_server'] = alert_data['applicable_on_server']
    if 'default_check_frequency' in alert_data:
        data['default_check_frequency'] = \
            int(alert_data['default_check_frequency'])
    if 'default_history_retention' in alert_data:
        data['default_history_retention'] = \
            int(alert_data['default_history_retention'])
    if 'threshold_unit' in alert_data:
        data['threshold_unit'] = alert_data['threshold_unit']
    else:
        data['threshold_unit'] = ''

    if 'info_sql' in alert_data:
        data['info_sql'] = alert_data['info_sql']
    else:
        data['info_sql'] = ''

    if 'is_auto_create' in alert_data:
        data['is_auto_create'] = alert_data['is_auto_create']

    if 'reference_id' in alert_data:
        data['reference_id'] = alert_data['reference_id']

    if 'operator' in alert_data:
        data['operator'] = alert_data['operator']
    else:
        data['operator'] = '>'

    # Format threshold values

    if 'low_threshold_value' in alert_data \
        and 'medium_threshold_value' \
            in alert_data and 'high_threshold_value' in alert_data:

        data['thresholds'] = [alert_data['low_threshold_value'],
                              alert_data['medium_threshold_value'],
                              alert_data['high_threshold_value']]
    else:
        data['thresholds'] = None

    # Format parameter option values
    param_name_arr = []
    param_type_arr = []
    param_unit_arr = []
    if 'params' in alert_data:
        for index in range(len(alert_data['params'])):
            param_name_arr.append(alert_data['params'][index]['param_names'])
            param_type_arr.append(alert_data['params'][index]['param_types'])
            if 'param_units' in alert_data['params'][index]:
                if not alert_data['params'][index]['param_units']:
                    param_unit_arr.append(None)
                else:
                    param_unit_arr.append(
                        alert_data['params'][index]['param_units'])
            else:
                param_unit_arr.append(None)

        data['param_names'] = param_name_arr
        data['param_types'] = param_type_arr
        data['param_units'] = param_unit_arr
    else:
        data['param_names'] = param_name_arr
        data['param_types'] = param_type_arr
        data['param_units'] = param_unit_arr

    # Format probe dependency list
    probe_dep_arr = []
    if 'probe_dependency_list' in alert_data:
        if len(alert_data['probe_dependency_list']) == 0:
            data['probe_dependency_list'] = {}
        else:
            for index in range(len(alert_data['probe_dependency_list'])):
                probe_dep_arr.append(
                    alert_data['probe_dependency_list'][index][
                        'internal_name'])
            data['probe_dependency_list'] = probe_dep_arr
    else:
        data['probe_dependency_list'] = {}

    if 'sql' in alert_data:
        data['sql'] = alert_data['sql']

    if len(data) > 0:
        # Get the snmp oid
        status, snmp_oid_res = pem_conn.execute_dict(
            "SELECT MAX(snmp_oid) FROM pem.alert_template "
            "WHERE object_type = %(object_type)s",
            {'object_type': data['object_type']}
        )

        if not status:
            return False, internal_server_error(errormsg=snmp_oid_res)

        # if there are no SNMP entries in the table then it will return NONE -
        # so this has to be taken care by 1 or else just increment id by 1
        if snmp_oid_res['rows'][0]['max'] is None:
            snmp_oid = 1
            data['snmp_oid'] = snmp_oid
        else:
            snmp_oid = snmp_oid_res['rows'][0]['max'] + 1
            data['snmp_oid'] = snmp_oid

        if return_data:
            return True, data

        sql = render_template('alerts/sql/custom_alert/insert.sql',
                              name=data['name'],
                              description=data['description'],
                              sql=data['sql'],
                              object_type=data['object_type'],
                              param_names=data['param_names'],
                              param_types=data['param_types'],
                              param_units=data['param_units'],
                              threshold_unit=data['threshold_unit'],
                              probe_dependency_list=data
                              ['probe_dependency_list'],
                              snmp_oid=snmp_oid,
                              applicable_on_server=data
                              ['applicable_on_server'],
                              default_check_frequency=data
                              ['default_check_frequency'],
                              default_history_retention=data
                              ['default_history_retention'],
                              info_sql=data[
                                  'info_sql'] if 'info_sql' in data else '',
                              is_auto_create=data[
                                  'is_auto_create'] if 'is_auto_create'
                                                       in data else False,
                              operator=data[
                                  'operator'] if 'operator' in data else '>',
                              thresholds=data[
                                  'thresholds'] if 'thresholds'
                                                   in data else [],
                              reference_id=data['reference_id'] if
                              'reference_id' in data else None
                              )

        # Insert new custom alert template into pem.alert_template table
        status, result = pem_conn.execute_scalar(sql)

    return status, result


def validate_update_template_params(data, pem_conn=None):
    """
    :param data: Custom Alert data for updating existing custom alert template
    :param pem_conn: pem connection object
    """
    # If alert template name is provided then it should not be empty.
    if 'name' in data:
        if data['name'] is None or not data['name']:
            return False, gettext("Provide valid alert template name.")

    # If Description for alert template is provided then it should not
    # be empty.
    if 'description' in data:
        if data['description'] is None or not data['description']:
            return False, gettext(
                "Provide valid description for alert template.")

    # If Description for alert template is provided then it should not
    # be empty.
    if 'object_type' in data:
        try:
            obj_type = 0
            if data['object_type'] is None:
                return False, gettext("Provide valid object type for "
                                      "alert template.")
            obj_type = float(data['object_type'])
        except ValueError:
            return False, gettext("Object type value should be numeric only.")

        obj_type = int(data['object_type'])
        if obj_type not in [DashboardLevel.DB_GLOBAL,
                            DashboardLevel.DB_AGENT,
                            DashboardLevel.DB_SERVER,
                            DashboardLevel.DB_DATABASE,
                            DashboardLevel.DB_SCHEMA,
                            DashboardLevel.DB_TABLE,
                            DashboardLevel.DB_INDEX,
                            DashboardLevel.DB_SEQUENCE,
                            DashboardLevel.DB_FUNCTION]:
            return False, gettext(
                "Provide valid object type for alert template.")

    # If applicable on server for alert template is provided then it should not
    # be empty and it should be 'ALL','POSTGRES_SERVER', 'ADVANCED_SERVER'
    # as valid value.
    if 'applicable_on_server' in data:
        if data['applicable_on_server'] is None or \
            not data['applicable_on_server'] or \
            (data['applicable_on_server']
             not in ['ALL', 'POSTGRES_SERVER', 'ADVANCED_SERVER']):
            return False, gettext("Provide valid applicable server type for "
                                  "alert template.")

    # If check frequency for alert template is provided then it should not
    # be empty and it should be numeric value only.
    # Check frequency is required parameter and it should not be empty.
    # If history retention for alert template is provided then it should not
    # be empty and it should be numeric value only.
    if 'default_check_frequency' in data:
        try:
            if data['default_check_frequency'] is None:
                return False, gettext("Provide valid check frequency value.")
            float(data['default_check_frequency'])
        except ValueError:
            return False, gettext(
                "Check frequency value should be numeric only.")

        if int(data['default_check_frequency']) <= 0 or \
                int(data['default_check_frequency']) > 65534:
            return False, gettext(
                "Valid range for check frequency is 1-65534.")

    # If history retention for alert template is provided then it should not
    # be empty and it should be numeric value only.
    if 'default_history_retention' in data:
        try:
            if data['default_history_retention'] is None:
                return False, gettext("Provide valid history retention value.")
            float(data['default_history_retention'])
        except ValueError:
            return False, gettext(
                "History retention value should be numeric only.")

        if int(data['default_history_retention']) <= 0 or \
                int(data['default_history_retention']) > 999999:
            return False, gettext(
                "Valid range for history retention is 1-999999.")

    # If threshold unit for alert template is provided then it should not
    # be empty.
    if 'threshold_unit' in data:
        if data['threshold_unit'] is None or not data['threshold_unit']:
            return False, gettext(
                "Provide valid threshold unit for alert template.")

    # check parameters only when is_auto_create is true
    if "is_auto_create" in data and data['is_auto_create'] is True:
        # Operator is required parameter and it should not be empty.
        if 'operator' in data:
            if data['operator'] is None or not data['operator'] or \
                    (data['operator'] != ">" and data['operator'] != "<"):
                return False, gettext(
                    "Provide valid operator for threshold value")

        # low threshold value is required parameter and it
        # should not be empty.
        i_low = 0
        if 'low_threshold_value' in data:
            try:
                if data['low_threshold_value'] is None:
                    return False, gettext(
                        "Low threshold value cannot be empty.")
                i_low = float(data['low_threshold_value'])
            except ValueError:
                return False, gettext("Low threshold value should be numeric.")
        else:
            return False, gettext("Low threshold value is a required "
                                  "parameter.")

        # medium threshold value is required parameter and it
        # should not be empty.
        i_med = 0
        if 'medium_threshold_value' in data:
            try:
                if data['medium_threshold_value'] is None:
                    return False, gettext(
                        "Medium threshold value cannot be empty.")
                i_med = float(data['medium_threshold_value'])
            except ValueError:
                return False, gettext(
                    "Medium threshold value should be numeric.")
        else:
            return False, gettext("Medium threshold value is a required "
                                  "parameter.")

        # high threshold value is required parameter and it
        # should not be empty.
        i_high = 0
        if 'high_threshold_value' in data:
            try:
                if data['high_threshold_value'] is None:
                    return False, gettext(
                        "High threshold value cannot be empty.")
                i_high = float(data['high_threshold_value'])
            except ValueError:
                return False, gettext(
                    "High threshold value should be numeric.")
        else:
            return False, gettext("High threshold value is a required "
                                  "parameter.")

        # If operator provided is '>' then threshold values should be in
        # ascending order. if operator is '<' then threshold values
        # should be in descending order.
        if 'operator' in data:
            if data['operator'] == ">":
                if not (i_low < i_med < i_high):
                    return False, gettext(
                        "Threshold values should be in ascending order.")
            else:
                if not (i_low > i_med > i_high):
                    return False, gettext(
                        "Threshold values should be in descending order.")
    elif 'is_auto_create' in data and data['is_auto_create'] is not False:
        return False, gettext(
            "Provide valid value for Is Auto Create.")

    if 'params' in data:
        return False, gettext("Cannot modify parameters option")

    # Validate input probe dependency parameters now
    if 'probe_dependency_list' in data:
        if 'added' in data['probe_dependency_list'] and \
                len(data['probe_dependency_list']['added']) > 0:
            for param in data['probe_dependency_list']['added']:
                if 'display_name' not in param or \
                        'internal_name' not in param:
                    return False, gettext("Missing parameter in "
                                          "probe dependency list.")
                if not param['display_name'] or not param['internal_name']:
                    return False, gettext("Display or internal name cannot be "
                                          "empty in probe dependency list.")

        if 'deleted' in data['probe_dependency_list'] and \
                len(data['probe_dependency_list']['deleted']) > 0:
            for param in data['probe_dependency_list']['deleted']:
                if 'display_name' not in param or \
                        'internal_name' not in param:
                    return False, gettext("Missing parameter in "
                                          "probe dependency list.")
                if not param['display_name'] or not param['internal_name']:
                    return False, gettext("Display or internal name cannot be "
                                          "empty in probe dependency list.")

    if 'sql' in data:
        if data['sql'] is None or not data['sql']:
            return False, gettext("Provide sql code for alert template.")

    return True, gettext('')


@login_required
@pem_connection
def update_custom_alert(alert_data, original_alert_data, pem_conn=None):
    """

    :param alert_data: Alert data for updating existing custom alert template
    :param original_alert_data: Original custom alert model data
    :param pem_conn: pem connection object
    """
    data = dict()
    status = False
    result = None
    d_data_name = []
    d_data_type = []
    alert_column_type = {}
    data_col_type = {}

    # First extract pem.alert table column type information.
    status, data_type = pem_conn.execute_dict(
        render_template('alerts/sql/custom_alert/column_type.sql')
    )

    if not status:
        return status, data_type
    else:
        d_data_name = [d['name'] for d in data_type['rows']]
        d_data_type = [d['datatype'] for d in data_type['rows']]
        if len(d_data_name) == len(d_data_type):
            item = 0
            while item < len(d_data_name):
                column_name = d_data_name[item]
                column_type = d_data_type[item]
                alert_column_type[column_name] = column_type
                item += 1

    if 'name' in alert_data:
        data['display_name'] = alert_data['name']
        data_col_type['display_name'] = alert_column_type['display_name']
    if 'description' in alert_data:
        data['description'] = alert_data['description']
        data_col_type['description'] = alert_column_type['description']
    if 'object_type' in alert_data:
        data['object_type'] = alert_data['object_type']
        data_col_type['object_type'] = alert_column_type['object_type']
    if 'applicable_on_server' in alert_data:
        data['applicable_on_server'] = alert_data['applicable_on_server']
        data_col_type['applicable_on_server'] = alert_column_type[
            'applicable_on_server']
    if 'default_check_frequency' in alert_data:
        data['default_check_frequency'] = \
            alert_data['default_check_frequency']
        data_col_type['default_check_frequency'] = alert_column_type[
            'default_check_frequency']
    if 'default_history_retention' in alert_data:
        data['default_history_retention'] = \
            alert_data['default_history_retention']
        data_col_type['default_history_retention'] = alert_column_type[
            'default_history_retention']
    if 'threshold_unit' in alert_data:
        data['threshold_unit'] = alert_data['threshold_unit']
        data_col_type['threshold_unit'] = alert_column_type['threshold_unit']
    if 'info_sql' in alert_data:
        data['info_sql'] = alert_data['info_sql']
        data_col_type['info_sql'] = alert_column_type['info_sql']

    if 'is_auto_create' in alert_data:
        data['is_auto_create'] = alert_data['is_auto_create']
        data_col_type['is_auto_create'] = alert_column_type['is_auto_create']

        if not data['is_auto_create']:
            data['thresholds'] = None
            data_col_type['thresholds'] = alert_column_type['thresholds']

    if 'operator' in alert_data and 'is_auto_create' in alert_data:
        if data['is_auto_create']:
            data['operator'] = alert_data['operator']
            data_col_type['operator'] = alert_column_type['operator']
    elif 'operator' in alert_data:
        # We will have to iterate through original data to check the
        # value of is_auto_create flag.
        for row in original_alert_data:
            if row['id'] == alert_data['id'] and row['is_auto_create']:
                data['operator'] = alert_data['operator']
                data_col_type['operator'] = alert_column_type['operator']

    if 'low_threshold_value' in alert_data \
        and 'medium_threshold_value' in alert_data \
        and 'high_threshold_value' \
            in alert_data and 'is_auto_create' in alert_data:

        if data['is_auto_create']:
            data['thresholds'] = [alert_data['low_threshold_value'],
                                  alert_data['medium_threshold_value'],
                                  alert_data['high_threshold_value']]
        else:
            data['thresholds'] = None

        data_col_type['thresholds'] = alert_column_type['thresholds']
    elif 'low_threshold_value' in alert_data \
        and 'medium_threshold_value' \
            in alert_data and 'high_threshold_value' in alert_data:
        # We will have to iterate through original data to check the
        # value of is_auto_create flag.
        for row in original_alert_data:
            if row['id'] == alert_data['id'] and row['is_auto_create']:
                data['thresholds'] = [alert_data['low_threshold_value'],
                                      alert_data['medium_threshold_value'],
                                      alert_data['high_threshold_value']]
                data_col_type['thresholds'] = alert_column_type['thresholds']

    # Format probe dependency list
    probe_dep_arr = []
    if 'probe_dependency_list' in alert_data:
        for row in original_alert_data:
            if row['id'] == alert_data['id']:
                for index in range(len(row['probe_dependency_list'])):
                    probe_dep_arr.append(
                        row['probe_dependency_list'][index]['internal_name'])
                for probe_dep in alert_data[
                        'probe_dependency_list'].get('added',[]):
                    if probe_dep['internal_name'] not in probe_dep_arr:
                        probe_dep_arr.append(probe_dep['internal_name'])
                for probe_dep in alert_data[
                        'probe_dependency_list'].get('deleted',[]):
                    probe_dep_arr.remove(probe_dep['internal_name'])
        data['probe_dependency_list'] = probe_dep_arr
        data_col_type['probe_dependency_list'] = alert_column_type[
            'probe_dependency_list']
    if 'sql' in alert_data:
        data['sql'] = alert_data['sql']
        data_col_type['sql'] = alert_column_type['sql']

    # Update pem.alert_template table
    if len(data) > 0:
        sql = render_template('alerts/sql/custom_alert/update.sql',
                              update_alert=True, data=data,
                              col_type=data_col_type,
                              alert_id=alert_data['id'])

        status, result = pem_conn.execute_void(sql)
    else:
        # Ignore only 'id' attribute in alert_data
        if len(alert_data) == 1 and 'id' in alert_data:
            status = True

    return status, result


@login_required
@utils.manageAlertRole.check_role(
    gettext(
        "Logged-in user do not have permission to export alert templates.")
)
@pem_connection
def export(pem_conn=None):
    """
    :param pem_conn: pem connection object
    """
    if request.data:
        data = json.loads(request.data.decode())
    else:
        data = request.args or request.form

    alert_templates = data.get('alert_templates', [])
    if len(alert_templates) == 0:
        return bad_request(
            errormsg=gettext("No alert templates to export")
        )

    status, result = utils.generate_export_alert_data(
        pem_conn, alert_templates)
    if not status:
        return internal_server_error(errormsg=result)

    # ========================= IMPORTANT NOTE =========================
    # Here we will add Export "version" key for compatibility check
    # we need to update the "VALID_EXPORT_VERSIONS" variables
    # in the utils.py when there is a change in alert, probe schema which can
    # break the import/export logic, we will check this version while
    # importing the alert, probes from json file
    # ==================================================================
    resp = Response(
        json.dumps({
            "version": CURRENT_EXPORT_VERSION,
            "alert_templates": result
        }),
        mimetype='application/json'
    )

    return resp


def insert_imported_alerts(
    pem_conn, alert_templates, skip_existing=True,
    skip_overwrite_probe=True, with_transaction=True
):
    """
    :param pem_conn: PEM connection
    :param alert_templates: Alerts to insert
    :param skip_existing: Skip if alert already present
    :param skip_overwrite_probe: Skip if dependant probe already present
    :param with_transaction: Set transaction for each row if set to True
    :return: List of status
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

    for alert in alert_templates:
        # check using reference_id column
        if 'reference_id' not in alert or not alert['reference_id']:
            update_store(
                alert['name'], _FAILED,
                gettext("Please provide valid reference id for the alert "
                        "template")
            )
            continue
        if with_transaction:
            status, _ = pem_conn.execute_void('BEGIN')
            if not status:
                update_store(
                    alert['name'], _FAILED,
                    gettext("Failed to start the transaction")
                )
                continue

        # Check if alert already exists using reference_id column and skip
        # is true then Skip it
        status, existing_record = pem_conn.execute_dict("""
        SELECT * FROM pem.alert_template WHERE reference_id = %s
        """, [alert['reference_id']])
        if not status:
            update_store(
                alert['name'], _FAILED,
                gettext("Failed to fetch the alert template information "
                        "due to an error - {}".format(existing_record))
            )
            pem_conn.execute_void('ROLLBACK')
            continue

        if len(existing_record['rows']) > 0:
            existing_record = existing_record['rows'][0]
            # If user selected to Skip then
            if skip_existing:
                update_store(alert['name'], _SKIPPED)
                pem_conn.execute_void('ROLLBACK')
                continue

            # If alert template already exists then we will check if there are
            # any alert created using that
            sql = render_template(
                'alerts/sql/custom_alert/alert_exists.sql',
                alert_template_id=existing_record['id'])
            status, is_alert_created = pem_conn.execute_scalar(sql)
            if not status:
                update_store(
                    alert['name'], _FAILED,
                    gettext("Failed to fetch the existing alert information "
                            "due to an error - {}".format(is_alert_created))
                )
                pem_conn.execute_void('ROLLBACK')
                continue
            # If there are alerts created then it is dependency on it
            # so we will error out and skip
            if int(is_alert_created) > 0:
                update_store(
                    alert['name'], _FAILED,
                    gettext("Failed to overwrite the existing alert template "
                            "information because some alerts are dependent "
                            "on it")
                )
                pem_conn.execute_void('ROLLBACK')
                continue
            else:
                # Try to delete existing alert template before we create new
                status, res = pem_conn.execute_void("""
                DELETE FROM pem.alert_template
                WHERE reference_id = %(reference_id)s::text
                """, {'reference_id': alert['reference_id']})
                if not status:
                    update_store(
                        alert['name'], _FAILED,
                        gettext("Failed to delete the existing alert template"
                                " due to an error - {}".format(res))
                    )
                    pem_conn.execute_void('ROLLBACK')
                    continue

        # Before inserting Alert template we must insert the dependent probes
        is_probe_insert_successful = True
        probes_result = insert_imported_probes(
            pem_conn, alert['probes'],
            skip_overwrite_probe, with_transaction=False
        )
        for probe in probes_result:
            # If one of the probe failed then Error out & jump to next
            if probe['status'] == 'Failed':
                update_store(alert['name'], _FAILED, probe['msg'])
                is_probe_insert_successful = False
                if with_transaction:
                    _, _ = pem_conn.execute_void('ROLLBACK')
                continue

        # If any probe failed then skip insert of alert template
        if not is_probe_insert_successful:
            continue

        # Insert into pem.alert_template table
        status, result = insert_custom_alert(alert)
        if not status:
            if with_transaction:
                pem_conn.execute_void('ROLLBACK')
            update_store(alert['name'], _FAILED, result)

        if with_transaction:
            status, _ = pem_conn.execute_void('COMMIT')
            if not status:
                pem_conn.execute_void('ROLLBACK')
                update_store(
                    alert['name'], _FAILED,
                    gettext("Failed to commit the transaction")
                )
        update_store(alert['name'], _SUCCESS, None)

    return final_result


@login_required
@utils.manageAlertRole.check_role(
    gettext(
        "Logged-in user do not have permission to import alert templates.")
)
@pem_connection
def alert_import(pem_conn=None):
    """
    :param pem_conn: pem connection object
    """
    # Set transaction for each alert insert
    # Check if alert already exits with the same internal name - Skip it
    # Try to insert the alert add a flg for success or error we need to add
    # colors for each line in the status message
    # { name: alert_name, msg: msg (success/skip/error),
    # is_error: true/false }
    if request.data:
        data = json.loads(request.data.decode())
    else:
        data = request.args or request.form

    # Verify the request
    if 'content' not in data or 'alert_templates' not in data['content'] or \
            type(data['content']['alert_templates']) != list or \
            len(data['content']['alert_templates']) == 0 or \
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

    result = insert_imported_alerts(
        pem_conn, data['content']['alert_templates'],
        skip_overwrite, skip_overwrite_probe
    )

    return make_json_response(result=result)


def register_custom_routes(blueprint):
    blueprint.add_url_rule('/custom/alerts/probe_list', 'alert_probe_dep_list',
                           probe_dep_list, methods=["GET"])
    blueprint.add_url_rule('/custom/alerts/', 'custom_list', alerts,
                           methods=["GET"])
    blueprint.add_url_rule('/custom/all_alerts',
                           'get_all_custom_alerts_templates', all_alerts,
                           methods=["GET"])
    blueprint.add_url_rule('/custom/all_auto_created_alerts',
                           'all_auto_created_alerts', all_auto_created_alerts,
                           methods=["GET"])
    blueprint.add_url_rule('/custom/alerts/<int:show_alert_level>',
                           'custom_list_by_level', alerts, methods=["GET"])
    blueprint.add_url_rule('/custom/save', 'custom_save',
                           save, methods=["PUT", "POST"])
    blueprint.add_url_rule('/custom/export', 'custom_export',
                           export, methods=["POST"])
    blueprint.add_url_rule('/custom/import', 'custom_import',
                           alert_import, methods=["POST"])
