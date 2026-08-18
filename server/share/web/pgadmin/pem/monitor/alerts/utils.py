##########################################################################
#
# Postgres Enterprise Manager
#
# Copyright (C) 2016 - 2025, EnterpriseDB Corporation. All rights reserved.
#
##########################################################################

"""Alerts Utilities"""
import datetime

from flask import render_template, current_app
from flask_babel import gettext

from pgadmin.pem.monitor.probes.utils import generate_export_probe_data
from pgadmin.pem.monitor.utils import DashboardLevel
from pgadmin.pem.utils import is_agent_exists_and_active, is_object_exists, \
    is_server_group_exists, get_sql_placeholders
from pgadmin.pem.utils.role import PEMRole
from pgadmin.pem.utils.role import configManageRole as configRole
from pgadmin.utils.pem.server import Server

configAlertRole = PEMRole(
    'pem_config_alert', gettext('Alert configuration'),
    gettext('Alert configuration'),
    gettext('Privilege to configure the alerts for the monitored objects.')
)

manageAlertRole = PEMRole(
    'pem_manage_alert', gettext('Alerts management'),
    gettext('Alerts management'), gettext(
        'Privilege to manage the alert templates, including configuring '
        'alerts on the monitored objects.'
    )
)


def get_alerts(
        target_type_id, object_id=None, database_name=None, schema_name=None,
        object_name=None, pem_conn=None, alert_id=None
):
    """
    This function will return the list of alerts.

    :param target_type_id: target type id.
    :param object_id: Agent/Server id.
    :param database_name: database name.
    :param schema_name: schema name.
    :param object_name: Table/Index/Function/View/Procedure name.
    :param pem_conn: PEM Connection object
    :param alert_id: Alert ID
    """

    params = {
        'target_id': target_type_id
    }

    comparision_condition = ''

    if target_type_id == DashboardLevel.DB_GLOBAL:
        comparision_condition = "(at.object_type = %(target_id)s::int)"
    elif target_type_id == DashboardLevel.DB_AGENT:
        if object_id:
            params['agent_id'] = int(object_id)
            comparision_condition = """
                (at.object_type = %(target_id)s::int) AND
                (a.agent_id = %(agent_id)s::int4)
                """
        else:
            comparision_condition = """
                (at.object_type = %(target_id)s::int)
                """
    elif target_type_id == DashboardLevel.DB_SERVER:
        if object_id:
            params['server_id'] = int(object_id)
            comparision_condition = """
                (at.object_type = %(target_id)s::int) AND
                (a.server_id = %(server_id)s::int4)
                """
        else:
            comparision_condition = """
                (at.object_type = %(target_id)s::int)
                """
    elif target_type_id == DashboardLevel.DB_DATABASE:
        params['server_id'] = int(object_id)
        params['database_name'] = str(database_name)
        comparision_condition = """
            (at.object_type = %(target_id)s::int)
            AND (a.server_id = %(server_id)s::int4)
            AND (a.database_name = %(database_name)s::text)
            """
    elif target_type_id == DashboardLevel.DB_SCHEMA:
        params['server_id'] = int(object_id)
        params['database_name'] = str(database_name)
        params['schema_name'] = str(schema_name)
        comparision_condition = """
            (at.object_type = %(target_id)s::int)
            AND (a.server_id = %(server_id)s::int)
            AND (a.database_name = %(database_name)s::text)
            AND (a.schema_name = %(schema_name)s::text)
            """
    # Table/Index/Sequence/Function
    elif (target_type_id == DashboardLevel.DB_TABLE or
            target_type_id == DashboardLevel.DB_INDEX or
            target_type_id == DashboardLevel.DB_SEQUENCE or
            target_type_id == DashboardLevel.DB_FUNCTION):
        params['server_id'] = int(object_id)
        params['database_name'] = str(database_name)
        params['schema_name'] = str(schema_name)
        params['object_name'] = str(object_name)
        comparision_condition = """
            (at.object_type = %(target_id)s::int)
            AND (a.server_id = %(server_id)s::int)
            AND (a.database_name = %(database_name)s::text)
            AND (a.schema_name = %(schema_name)s::text)
            AND (a.object_name = %(object_name)s::text)
            """

    if alert_id is not None:
        params['alert_id'] = alert_id

        sql = render_template(
            'alerts/sql/alerts/list.sql',
            comparision_condition=comparision_condition,
            alert_id=alert_id
        )
    else:
        sql = render_template(
            'alerts/sql/alerts/list.sql',
            comparision_condition=comparision_condition
        )

    # Get the alert list based on target type id
    status, alerts = pem_conn.execute_dict(sql, params)

    return status, alerts


def validate_insert_params(target_type_id, data, is_edb=0, pem_conn=None):
    """
    This function will check whether input parameter to
    create the new alert is valid or not.

    :param target_type_id: target type id.
    :param data: Alert data to be inserted in table.
    :param is_edb: Check server is PG or PPAS.
    :param pem_conn: PEM Connection object
    """

    # Alert name is required parameter and it should not be empty.
    if 'alert_name' in data:
        if data['alert_name'] is None or not data['alert_name']:
            return False, gettext("Provide valid alert name.")
    else:
        return False, gettext("Provide valid alert name.")

    # Alert template is required parameter and it should not be empty.
    if 'alert_template' in data:
        if data['alert_template'] is None or not data['alert_template']:
            return False, gettext("Provide valid alert template.")
        try:
            float(data['alert_template'])
        except ValueError:
            return False, gettext("Alert template value should be numeric.")
    else:
        return False, gettext("Provide valid alert template.")

    # Check if it is valid template id then is it applicable to
    # same target type id and check the alert template parameters
    # exists or not.
    alert_template_id = int(data['alert_template'])
    params = {
        'alert_template_id': alert_template_id
    }

    sql = render_template(
        'alerts/sql/alerts/template_params_exists.sql',
        alert_template_id=alert_template_id
    )

    status, template_params = pem_conn.execute_dict(sql, params)

    if not status:
        return False, gettext("Error while getting alert template "
                              "parameter options.")

    param_count = template_params['rows'][0]['param_count']
    if param_count != 0:
        if 'params' not in data:
            data_len = 0
        else:
            data_len = len(data['params'])
        # Check parameters are provided or not.
        if param_count != data_len:
            return False, gettext("Parameter options are not provided "
                                  "required by alert template.")
    params = {
        'target_id': target_type_id
    }

    if target_type_id != DashboardLevel.DB_AGENT and is_edb == 0:
        comparision_condition = """
            (at.object_type = %(target_id)s::int)
            AND at.applicable_on_server IN ('ALL' , 'POSTGRES_SERVER')
            """
    elif target_type_id != DashboardLevel.DB_AGENT and is_edb == 1:
        comparision_condition = """
            (at.object_type = %(target_id)s::int)
            AND at.applicable_on_server IN ('ALL' , 'ADVANCED_SERVER')
            """
    else:
        comparision_condition = "(at.object_type = %(target_id)s::int)"

    sql = render_template(
        'alerts/sql/alerts/template_list.sql',
        comparision_condition=comparision_condition,
        alert_template_id=alert_template_id
    )

    # Get alert template list
    status, alerts = pem_conn.execute_dict(sql, params)

    if not status:
        return False, gettext("Error while getting alert template list.")

    if len(alerts['rows']) == 0:
        return False, gettext("Alert template and object type mismatch. "
                              "Alert template should be of same object type.")

    # Alert status is required parameter and it should not be empty.
    if 'enabled' in data:
        if data['enabled'] is None or not isinstance(data['enabled'], bool):
            return False, gettext(
                "Provide valid value of alert enable status.")
    else:
        return False, gettext("Provide valid value of alert enable status.")

    # Check frequency is required parameter and it should not be empty.
    if 'frequency_min' in data:
        try:
            if data['frequency_min'] is None:
                return False, gettext("Frequency value cannot be empty.")
            float(data['frequency_min'])
        except ValueError:
            return False, gettext("Frequency value should be numeric.")

        if int(data['frequency_min']) <= 0 or \
                int(data['frequency_min']) > 65534:
            return False, gettext("Valid range for frequency is 1-65534.")
    else:
        return False, gettext("Provide valid frequency value.")

    # History retention is required parameter and it
    # should not be empty.
    if 'history_retention' in data:
        try:
            if data['history_retention'] is None:
                return False, gettext(
                    "History retention value cannot be empty.")
            float(data['history_retention'])
        except ValueError:
            return False, gettext("History retention value should be numeric.")

        if int(data['history_retention']) <= 0 or \
                int(data['history_retention']) > 99999:
            return False, gettext("History retention value should be "
                                  "between 1-99999.")
    else:
        return False, gettext("Provide valid history retention value.")

    # Operator is required parameter and it should not be empty.
    if 'operator' in data:
        if data['operator'] is None or \
                not data['operator'] or \
                (data['operator'] != ">" and data['operator'] != "<"):
            return False, gettext("Provide valid operator for threshold value")
    else:
        return False, gettext("Provide operator for threshold value.")

    # low threshold value is required parameter and it
    # should not be empty.
    i_low = 0
    if 'low_threshold_value' in data:
        try:
            if data['low_threshold_value'] is None:
                return False, gettext("Low threshold value cannot be empty.")
            i_low = float(data['low_threshold_value'])
        except ValueError:
            return False, gettext("Low threshold value should be numeric.")
    else:
        return False, gettext("Provide valid low threshold value.")

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
            return False, gettext("Medium threshold value should be numeric.")
    else:
        return False, gettext("Provide valid medium threshold value.")

    # high threshold value is required parameter and it
    # should not be empty.
    i_high = 0
    if 'high_threshold_value' in data:
        try:
            if data['high_threshold_value'] is None:
                return False, gettext("High threshold value cannot be empty.")
            i_high = float(data['high_threshold_value'])
        except ValueError:
            return False, gettext("High threshold value should be numeric.")
    else:
        return False, gettext("Provide valid high threshold value.")

    # If operator provided is '>' then threshold values should be in
    # ascending order. if operator is '<' then threshold values
    # should be in descending order.
    if data['operator'] == ">":
        if not (i_low < i_med < i_high):
            return False, gettext(
                "Threshold values should be in ascending order.")
    else:
        if not (i_low > i_med > i_high):
            return False, gettext(
                "Threshold values should be in descending order.")

    if 'send_trap' in data and data['send_trap'] is True and \
        "snmp_trap_version" in data and \
            int(data['snmp_trap_version']) not in [1, 2, 3]:
        return False, gettext("Invalid SNMP trap version.")

    return True, gettext('')


def insert_alert(alert_data, node_info, pem_conn=None):
    """

    :param alert_data: New alert data for insert
    :param node_info: Browser node information
    :param pem_conn: pem connection object
    """
    data = dict()
    status = False
    result = None

    if 'target_type_id' in node_info and \
            node_info['target_type_id'] == DashboardLevel.DB_GLOBAL:
        data['server_id'] = 0
        data['agent_id'] = -1

    if 'server_id' in node_info:
        if node_info['server_id'] != 0:
            data['server_id'] = node_info['server_id']
            data['agent_id'] = 0
        else:
            data['server_id'] = 0
            data['agent_id'] = -1

    if 'agent_id' in node_info:
        data['server_id'] = 0
        data['agent_id'] = node_info['agent_id']

    if 'database_name' in node_info:
        data['database_name'] = node_info['database_name']
    else:
        data['database_name'] = ''

    if 'schema_name' in node_info:
        data['schema_name'] = node_info['schema_name']
    else:
        data['schema_name'] = ''

    if 'package_name' in node_info:
        data['package_name'] = node_info['package_name']
    else:
        data['package_name'] = ''

    if 'object_name' in node_info:
        data['object_name'] = node_info['object_name']
    else:
        data['object_name'] = ''

    # Assign default parameters value
    data['send_email'] = False
    data['flapping_detected'] = False
    data['last_flapping_detection_processed'] = datetime.datetime.now()

    # Update 'send_email' parameter if one of the all,low,med or high
    # alert is enabled
    if (
        alert_data.get('all_alert_enable', False) is True or
        alert_data.get('low_alert_enable', False) is True or
        alert_data.get('med_alert_enable', False) is True or
        alert_data.get('high_alert_enable', False) is True
    ):
        data['send_email'] = True

    # Add alert parameters
    if 'alert_name' in alert_data:
        data['name'] = alert_data['alert_name']

    if 'alert_template' in alert_data:
        data['template_id'] = int(alert_data['alert_template'])

    if 'frequency_min' in alert_data:
        data['check_frequency'] = alert_data['frequency_min']

    if 'enabled' in alert_data:
        data['enabled'] = alert_data['enabled']

    if 'history_retention' in alert_data:
        data['history_retention'] = alert_data['history_retention']

    if 'operator' in alert_data:
        data['operator'] = alert_data['operator']

    # Format threshold values
    if 'low_threshold_value' in alert_data \
            and 'medium_threshold_value' in alert_data \
            and 'high_threshold_value' in alert_data:

        data['thresholds'] = [alert_data['low_threshold_value'],
                              alert_data['medium_threshold_value'],
                              alert_data['high_threshold_value']]

    param_arr = []
    # Format parameter options and values
    if 'params' in alert_data:
        template_id = int(alert_data['alert_template'])
        data_column_type_sql = \
            'SELECT param_types FROM pem.alert_template ' \
            'WHERE id={0}'.format(template_id)
        status, data_column_type = \
            pem_conn.execute_scalar(data_column_type_sql)
        supported_param_names = ['agent', 'server', 'database_name',
                                 'schema_name', 'object_name', 'package_name']
        extra_params = [params['paramname'] for params in alert_data['params']
                        if params['paramname'] not in supported_param_names]
        param_length = len(alert_data['params'])
        if param_length > 0:
            i_count = 0
            while i_count < param_length:
                param_name = alert_data['params'][i_count]['paramname']
                if param_name not in supported_param_names:
                    value = alert_data['params'][i_count]['paramvalue']
                    expected_data_type_for_param = \
                        data_column_type.split(',')[extra_params.index(
                            param_name)].strip('{}')
                    status, res = \
                        validate_param_value(
                            value, expected_data_type_for_param)
                    if status:
                        if expected_data_type_for_param == 'BOOL':
                            value = value.title()
                        param_arr.append(value)
                    else:
                        return False, \
                            f"Enter the valid value for the " \
                            f"parameter - '{param_name}' it should " \
                            f"be '{expected_data_type_for_param}"
                i_count += 1
            data['params'] = param_arr
        else:
            data['params'] = param_arr
    else:
        data['params'] = param_arr

    if 'all_alert_enable' in alert_data and 'email_group_id' in alert_data \
            and alert_data['all_alert_enable'] is True:
        data['email_group_id'] = alert_data['email_group_id']
    else:
        data['email_group_id'] = None

    if 'low_alert_enable' in alert_data and 'low_email_group_id' \
            in alert_data and alert_data['low_alert_enable'] is True:
        data['low_email_group_id'] = alert_data['low_email_group_id']
    else:
        data['low_email_group_id'] = None

    if 'med_alert_enable' in alert_data and 'med_email_group_id' \
            in alert_data and alert_data['med_alert_enable'] is True:
        data['med_email_group_id'] = alert_data['med_email_group_id']
    else:
        data['med_email_group_id'] = None

    if 'high_alert_enable' in alert_data and 'high_email_group_id' \
            in alert_data and alert_data['high_alert_enable'] is True:
        data['high_email_group_id'] = alert_data['high_email_group_id']
    else:
        data['high_email_group_id'] = 'NULL'

    if 'cleared_alert_enable' in alert_data:
        data['cleared_alert_enable'] = alert_data['cleared_alert_enable']
    else:
        data['cleared_alert_enable'] = True

    if 'send_trap' in alert_data:
        data['send_trap'] = alert_data['send_trap']
    else:
        data['send_trap'] = False

    if 'snmp_trap_version' in alert_data:
        data['snmp_trap_version'] = int(alert_data['snmp_trap_version'])
    else:
        # SNMP version v2
        data['snmp_trap_version'] = 2

    if 'low_send_trap' in alert_data:
        data['low_send_trap'] = alert_data['low_send_trap']
    else:
        data['low_send_trap'] = False

    if 'med_send_trap' in alert_data:
        data['med_send_trap'] = alert_data['med_send_trap']
    else:
        data['med_send_trap'] = False

    if 'high_send_trap' in alert_data:
        data['high_send_trap'] = alert_data['high_send_trap']
    else:
        data['high_send_trap'] = False

    if 'submit_to_nagios' in alert_data:
        data['submit_to_nagios'] = alert_data['submit_to_nagios']
    else:
        data['submit_to_nagios'] = False

    if 'execute_script' in alert_data:
        data['execute_script'] = alert_data['execute_script']
    else:
        data['execute_script'] = False

    if 'execute_script_on_clear' in alert_data:
        data['execute_script_on_clear'] = alert_data['execute_script_on_clear']
    else:
        data['execute_script_on_clear'] = False

    if 'execute_script_on_pem_server' in alert_data:
        data['execute_script_on_pem_server'] = \
            alert_data['execute_script_on_pem_server']
    else:
        data['execute_script_on_pem_server'] = False

    if 'script_code' in alert_data:
        data['script_code'] = alert_data['script_code']
    else:
        data['script_code'] = ''

    if 'auto_created' in alert_data:
        data['auto_created'] = alert_data['auto_created']
    else:
        data['auto_created'] = False

    if 'enabled' in alert_data:
        data['enabled'] = alert_data['enabled']
    else:
        data['enabled'] = True

    # TODO:: Do something about the paramnames, paramvalues, paramtypes later.

    # Insert new data to pem.alert table
    if len(alert_data) > 0:
        sql = render_template('alerts/sql/alerts/insert.sql', data=data)

        status, result = pem_conn.execute_scalar(sql)

    return status, result


def validate_update_params(alert_id, target_type_id, data, is_edb=0,
                           pem_conn=None):
    """
    This function will check whether input parameter to
    update the alert is valid or not.

    :param alert_id: alert id.
    :param target_type_id: target type id.
    :param data: Alert data to be updated in table.
    :param is_edb: Check server is PG or PPAS.
    :param pem_conn: PEM Connection object
    """
    org_alert_data = dict()

    # First get existing alert parameters from database.
    if alert_id and alert_id > 0:
        params = [alert_id]
        sql = render_template('alerts/sql/alerts/alert_details.sql')

        # Execute the query.
        status, result = pem_conn.execute_dict(sql, params)
        if not status:
            return False, gettext("Error while getting alert details.")

        # Get all the alert parameters from alert id
        org_alert_data = result['rows'][0]

    # If alert name is provided then it should not be empty.
    if 'alert_name' in data:
        if data['alert_name'] is None or not data['alert_name'] or \
                org_alert_data['alert_name'] == data['alert_name']:
            return False, gettext("Provide valid alert name.")

    # If alert template is provided then it should not be empty.
    if 'alert_template' in data:
        if data['alert_template'] is None or not data['alert_template']:
            return False, gettext("Provide valid alert template id.")
        try:
            float(data['alert_template'])
        except ValueError:
            return False, gettext("Alert template value should be numeric.")

        # Check if it is valid template id then is it applicable to
        # same target type id and check the alert template parameters
        # exists or not.
        alert_template_id = int(data['alert_template'])
        params = {
            'alert_template_id': alert_template_id
        }

        sql = render_template(
            'alerts/sql/alerts/template_params_exists.sql',
            alert_template_id=alert_template_id
        )
        status, template_params = pem_conn.execute_dict(sql, params)

        if not status:
            return False, gettext("Error while getting alert template "
                                  "parameter options.")

        param_count = template_params['rows'][0]['param_count']
        if param_count != 0:
            if 'params' not in data:
                data_len = 0
            else:
                data_len = len(data['params'])
            # Check parameters are provided or not.
            if param_count != data_len:
                return False, gettext("Parameter options are not "
                                      "provided which are required by "
                                      "alert template.")

        params = {
            'target_id': target_type_id
        }

        if target_type_id != DashboardLevel.DB_AGENT and is_edb == 0:
            comparision_condition = """
                (at.object_type = %(target_id)s::int)
                AND at.applicable_on_server IN ('ALL' , 'POSTGRES_SERVER')
                """
        elif target_type_id != DashboardLevel.DB_AGENT and is_edb == 1:
            comparision_condition = """
                (at.object_type = %(target_id)s::int)
                AND at.applicable_on_server IN ('ALL' , 'ADVANCED_SERVER')
                """
        else:
            comparision_condition = "(at.object_type = %(target_id)s::int)"

        sql = render_template(
            'alerts/sql/alerts/template_list.sql',
            comparision_condition=comparision_condition,
            alert_template_id=alert_template_id
        )

        # Get alert template list
        status, alerts = pem_conn.execute_dict(sql, params)

        if not status:
            return False, gettext("Error while getting alert template list.")

        if len(alerts['rows']) == 0:
            return False, gettext(
                "Alert template and object type mismatch."
                "Alert template should be of same object type."
            )

    # Alert status is required parameter and it should not be empty.
    if 'enabled' in data:
        if data['enabled'] is None or not isinstance(data['enabled'], bool):
            return False, gettext(
                "Provide valid value of alert enable status.")

    # Check frequency is required parameter and it should not be empty.
    if 'frequency_min' in data:
        try:
            if data['frequency_min'] is None:
                return False, gettext("Frequency value cannot be empty.")
            float(data['frequency_min'])
        except ValueError:
            return False, gettext("Frequency value should be numeric.")

        if int(data['frequency_min']) <= 0 or \
                int(data['frequency_min']) > 65534:
            return False, gettext("Valid range for frequency is 1-65534.")

    # History retention is required parameter and it
    # should not be empty.
    if 'history_retention' in data:
        try:
            if data['history_retention'] is None:
                return False, gettext(
                    "History retention value cannot be empty.")
            float(data['history_retention'])
        except ValueError:
            return False, gettext(
                "History retention value should be numeric.s")

        if int(data['history_retention']) <= 0 or \
                int(data['history_retention']) > 99999:
            return False, gettext("History retention value should be "
                                  "between 1-99999.")

    # Operator is required parameter and it should not be empty.
    if 'operator' in data:
        if data['operator'] is None or \
                not data['operator'] or \
                (data['operator'] != ">" and data['operator'] != "<"):
            return False, gettext("Provide valid operator for threshold value")
        else:
            op = data['operator']
    else:
        op = org_alert_data['operator']

    # low threshold value is required parameter and it
    # should not be empty.
    i_low = 0
    if 'low_threshold_value' in data:
        try:
            if data['low_threshold_value'] is None:
                return False, gettext("Low threshold value cannot be empty.")
            i_low = float(data['low_threshold_value'])
        except ValueError:
            return False, gettext("Low threshold value should be numeric.")
        if isinstance(data['low_threshold_value'], int):
            i_low = int(data['low_threshold_value'])
        if isinstance(data['low_threshold_value'], str):
            if '.' not in data['low_threshold_value']:
                i_low = int(data['low_threshold_value'])
    else:
        if isinstance(org_alert_data['low_threshold_value'], int):
            i_low = int(org_alert_data['low_threshold_value'])
        if isinstance(org_alert_data['low_threshold_value'], str):
            if '.' in org_alert_data['low_threshold_value']:
                i_low = float(org_alert_data['low_threshold_value'])
            else:
                i_low = int(org_alert_data['low_threshold_value'])

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
            return False, gettext("Medium threshold value should be numeric.")
        if isinstance(data['medium_threshold_value'], int):
            i_med = int(data['medium_threshold_value'])
        if isinstance(data['medium_threshold_value'], str):
            if '.' not in data['medium_threshold_value']:
                i_med = int(data['medium_threshold_value'])
    else:
        if isinstance(org_alert_data['medium_threshold_value'], int):
            i_med = int(org_alert_data['medium_threshold_value'])
        if isinstance(org_alert_data['medium_threshold_value'], str):
            if '.' in org_alert_data['medium_threshold_value']:
                i_med = float(org_alert_data['medium_threshold_value'])
            else:
                i_med = int(org_alert_data['medium_threshold_value'])

    # high threshold value is required parameter and it
    # should not be empty.
    i_high = 0
    if 'high_threshold_value' in data:
        try:
            if data['high_threshold_value'] is None:
                return False, gettext("High threshold value cannot be empty.")
            i_high = float(data['high_threshold_value'])
        except ValueError:
            return False, gettext("High threshold value should be numeric.")
        if isinstance(data['high_threshold_value'], int):
            i_high = int(data['high_threshold_value'])
        if isinstance(data['high_threshold_value'], str):
            if '.' not in data['high_threshold_value']:
                i_high = int(data['high_threshold_value'])
    else:
        if isinstance(org_alert_data['high_threshold_value'], int):
            i_high = int(org_alert_data['high_threshold_value'])
        if isinstance(org_alert_data['high_threshold_value'], str):
            if '.' in org_alert_data['high_threshold_value']:
                i_high = float(org_alert_data['high_threshold_value'])
            else:
                i_high = int(org_alert_data['high_threshold_value'])

    # If operator provided is '>' then threshold values should be in
    # ascending order. if operator is '<' then threshold values
    # should be in descending order.
    if 'operator' in data or 'low_threshold_value' in data or \
            'medium_threshold_value' in data or \
            'high_threshold_value' in data:
        if op == ">":
            if not (i_low < i_med < i_high):
                return False, gettext("Threshold values should be in "
                                      "ascending order.")
            else:
                if 'operator' not in data:
                    data['operator'] = op
                if 'low_threshold_value' not in data:
                    data['low_threshold_value'] = i_low
                if 'medium_threshold_value' not in data:
                    data['medium_threshold_value'] = i_med
                if 'high_threshold_value' not in data:
                    data['high_threshold_value'] = i_high
        else:
            if not (i_low > i_med > i_high):
                return False, gettext("Threshold values should be in "
                                      "descending order.")
            else:
                if 'operator' not in data:
                    data['operator'] = op
                if 'low_threshold_value' not in data:
                    data['low_threshold_value'] = i_low
                if 'medium_threshold_value' not in data:
                    data['medium_threshold_value'] = i_med
                if 'high_threshold_value' not in data:
                    data['high_threshold_value'] = i_high

    # Alert level validation for email group
    alert_lvl_email_group_mapping = {
        'all': ['all_alert_enable', 'email_group_id'],
        'low': ['low_alert_enable', 'low_email_group_id'],
        'mid': ['med_alert_enable', 'med_email_group_id'],
        'high': ['high_alert_enable', 'high_email_group_id']
    }
    for obj in list(alert_lvl_email_group_mapping.values()):
        alert_lvl = obj[0]
        alert_email_grp = obj[1]
        if alert_lvl in data and data[alert_lvl] is not None and \
                alert_email_grp not in data:
            return False, gettext(
                "Please provide email group using {0} along with "
                "{1}.".format(alert_email_grp, alert_lvl)
            )

    return True, gettext('')


def validate_param_value(param_value, expected_data_type):
    # Check if the param value matches the expected data type
    try:
        param_value_lower = param_value.lower()
        if expected_data_type == 'BOOL' and \
                param_value_lower not in ['true', 'false']:
            return False, None
        elif expected_data_type == 'INTEGER' and \
                not isinstance(int(param_value_lower), int):
            return False, None
        elif expected_data_type == 'FLOAT' and \
                not isinstance(float(param_value_lower), float):
            return False, None
        elif expected_data_type == 'STRING' and \
                not isinstance(param_value_lower, str):
            return False, None
    except Exception as e:
        current_app.logger.exception(e)
        return False, "Invalid parameter value passed"
    return True, None


def update_alert(alert_data, pem_conn=None, is_api=False):
    """
    :param alert_data: Alert data for update
    :param pem_conn: pem connection object
    """
    data = dict()
    status = False
    result = None
    send_email_check = False
    d_data_name = []
    d_data_type = []
    alert_column_type = {}
    data_col_type = {}

    # First extract pem.alert table column type information.
    status, data_type = pem_conn.execute_dict(
        render_template('alerts/sql/alerts/column_type.sql')
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

    if 'alert_name' in alert_data:
        data['name'] = alert_data['alert_name']
        data_col_type['name'] = alert_column_type['name']

    if 'alert_template' in alert_data:
        data['template_id'] = int(alert_data['alert_template'])
        data_col_type['template_id'] = alert_column_type['template_id']

    if 'frequency_min' in alert_data:
        data['check_frequency'] = alert_data['frequency_min']
        data_col_type['check_frequency'] = alert_column_type['check_frequency']

    if 'enabled' in alert_data:
        data['enabled'] = alert_data['enabled']
        data_col_type['enabled'] = alert_column_type['enabled']

    if 'history_retention' in alert_data:
        data['history_retention'] = alert_data['history_retention']
        data_col_type['history_retention'] = \
            alert_column_type['history_retention']

    if 'operator' in alert_data:
        data['operator'] = alert_data['operator']
        data_col_type['operator'] = alert_column_type['operator']

    sql = f"SELECT thresholds from pem.alert where id={alert_data['id']}"
    status, res = pem_conn.execute_dict(sql)
    if not status or len(res['rows'][0]) == 0:
        return False, res
    old_thresholds = res['rows'][0]['thresholds']

    # Format threshold values
    if 'low_threshold_value' in alert_data \
        or 'medium_threshold_value' in alert_data \
            or 'high_threshold_value' in alert_data:
        data['thresholds'] = []
        if 'low_threshold_value' in alert_data:
            data['thresholds'].append(alert_data['low_threshold_value'])
        else:
            data['thresholds'].append(old_thresholds[0])
        if 'medium_threshold_value' in alert_data:
            data['thresholds'].append(alert_data['medium_threshold_value'])
        else:
            data['thresholds'].append(old_thresholds[1])
        if 'high_threshold_value' in alert_data:
            data['thresholds'].append(alert_data['high_threshold_value'])
        else:
            data['thresholds'].append(old_thresholds[2])
        data_col_type['thresholds'] = alert_column_type['thresholds']

    # Format parameter options and values
    if 'params' in alert_data:
        if 'alert_template' in alert_data:
            template_id = alert_data['alert_template']
        else:
            get_template_id_sql = \
                'SELECT template_id from pem.alert where ' \
                'id={0}'.format(alert_data['id'])
            status, template_id = pem_conn.execute_scalar(get_template_id_sql)

        get_param_names_sql = \
            'SELECT param_names from pem.alert_template ' \
            'where id={0}'.format(template_id)
        status, param_names = pem_conn.execute_scalar(get_param_names_sql)

        get_current_param_values_sql = \
            'SELECT params from pem.alert where ' \
            'id={0}'.format(alert_data['id'])
        status, current_param_values = \
            pem_conn.execute_scalar(get_current_param_values_sql)

        param_unit_sql = \
            'SELECT param_units FROM pem.alert_template ' \
            'WHERE id={0}'.format(template_id)
        status, param_units = \
            pem_conn.execute_scalar(param_unit_sql)
        param_options = []
        if not is_api:
            if param_names:
                for i in range(len(param_names)):
                    if param_units is not None and \
                            i < len(param_units):
                        # handles empty value in unit
                        if param_units[i]:
                            param_options.append(
                                f"{param_names[i]}({param_units[i]})")
                        else:
                            param_options.append(
                                f"{param_names[i]}")
                    else:
                        param_options.append(
                            f"{param_names[i]}")
        else:
            param_options = param_names

        data_column_type_sql = \
            'SELECT param_types FROM pem.alert_template ' \
            'WHERE id={0}'.format(template_id)
        status, data_column_type = \
            pem_conn.execute_scalar(data_column_type_sql)

        if 'changed' in alert_data['params']:
            param_length = len(alert_data['params']['changed'])
            if param_length > 0:
                for change in alert_data['params'].get('changed', []):
                    name = change.get('paramname')
                    value = change.get('paramvalue')
                    if name is not None and name in param_options:
                        expected_data_type_for_param = \
                            data_column_type.split(',')[param_options.index(
                                name)].strip('{}')
                        status, res = validate_param_value(
                            value, expected_data_type_for_param)
                        if status:
                            if expected_data_type_for_param == 'BOOL':
                                value = value.title()
                            current_param_values[
                                param_options.index(name)] = value
                        else:
                            return False, \
                                f"Enter the valid value for the " \
                                f"parameter - '{name}' it should " \
                                f"be '{expected_data_type_for_param}'"
                data['params'] = current_param_values

        elif 'added' in alert_data['params']:
            params = [params['paramname'] for
                      params in alert_data['params']['added']]
            param_length = len(alert_data['params']['added'])
            param_arr = []
            if param_length > 0:
                i_count = 0
                while i_count < param_length:
                    param_name = \
                        alert_data['params']['added'][i_count]['paramname']
                    value = \
                        alert_data['params']['added'][i_count]['paramvalue']

                    expected_data_type_for_param = \
                        data_column_type.split(',')[
                            params.index(param_name)].strip('{}')
                    status, res = \
                        validate_param_value(
                            value, expected_data_type_for_param)
                    if status:
                        param_arr.append(value)
                    else:
                        return False, \
                            f"Enter the valid value for the " \
                            f"parameter - '{param_name}' it should " \
                            f"be '{expected_data_type_for_param}'"
                    i_count += 1
                data['params'] = param_arr
            else:
                data['params'] = param_arr
        elif 'deleted' in alert_data['params']:
            alert_data['params']['deleted'] = []
            data['params'] = []

        data_col_type['params'] = alert_column_type['params']

    if 'email_group_id' in alert_data:
        data['email_group_id'] = alert_data['email_group_id']
        data_col_type['email_group_id'] = \
            alert_column_type['email_group_id']

    if 'low_email_group_id' in alert_data:
        data['low_email_group_id'] = alert_data['low_email_group_id']
        data_col_type['low_email_group_id'] = \
            alert_column_type['low_email_group_id']

    if 'med_email_group_id' in alert_data:
        data['med_email_group_id'] = alert_data['med_email_group_id']
        data_col_type['med_email_group_id'] = \
            alert_column_type['med_email_group_id']

    if 'high_email_group_id' in alert_data:
        data['high_email_group_id'] = alert_data['high_email_group_id']
        data_col_type['high_email_group_id'] = \
            alert_column_type['high_email_group_id']

    if (
        'all_alert_enable' in alert_data and not alert_data['all_alert_enable']
    ):
        data['email_group_id'] = 'NULL'
        if 'email_group_id' not in data_col_type:
            data_col_type['email_group_id'] = \
                alert_column_type['email_group_id']

    if 'low_alert_enable' in alert_data and not alert_data['low_alert_enable']:
        data['low_email_group_id'] = 'NULL'
        data_col_type['low_email_group_id'] = \
            alert_column_type['low_email_group_id']

    if 'med_alert_enable' in alert_data and not alert_data['med_alert_enable']:
        data['med_email_group_id'] = 'NULL'
        if 'med_email_group_id' not in data_col_type:
            data_col_type['med_email_group_id'] = \
                alert_column_type['med_email_group_id']

    if 'high_alert_enable' in alert_data and not \
            alert_data['high_alert_enable']:
        data['high_email_group_id'] = 'NULL'
        if 'high_email_group_id' not in data_col_type:
            data_col_type['high_email_group_id'] = \
                alert_column_type['high_email_group_id']

    if 'send_trap' in alert_data:
        data['send_trap'] = alert_data['send_trap']
        data_col_type['send_trap'] = alert_column_type['send_trap']

    if 'snmp_trap_version' in alert_data:
        data['snmp_trap_version'] = int(alert_data['snmp_trap_version'])
        data_col_type['snmp_trap_version'] = \
            alert_column_type['snmp_trap_version']

    if 'low_send_trap' in alert_data:
        data['low_send_trap'] = alert_data['low_send_trap']
        data_col_type['low_send_trap'] = alert_column_type['low_send_trap']

    if 'med_send_trap' in alert_data:
        data['med_send_trap'] = alert_data['med_send_trap']
        data_col_type['med_send_trap'] = alert_column_type['med_send_trap']

    if 'high_send_trap' in alert_data:
        data['high_send_trap'] = alert_data['high_send_trap']
        data_col_type['high_send_trap'] = alert_column_type['high_send_trap']

    if 'submit_to_nagios' in alert_data:
        data['submit_to_nagios'] = alert_data['submit_to_nagios']
        data_col_type['submit_to_nagios'] = \
            alert_column_type['submit_to_nagios']

    if 'execute_script' in alert_data:
        data['execute_script'] = alert_data['execute_script']
        data_col_type['execute_script'] = alert_column_type['execute_script']

    if 'execute_script_on_clear' in alert_data:
        data['execute_script_on_clear'] = alert_data['execute_script_on_clear']
        data_col_type['execute_script_on_clear'] = \
            alert_column_type['execute_script_on_clear']

    if 'execute_script_on_pem_server' in alert_data:
        if alert_data['execute_script_on_pem_server'] == '1':
            alert_data['execute_script_on_pem_server'] = True
        elif alert_data['execute_script_on_pem_server'] == '0':
            alert_data['execute_script_on_pem_server'] = False
        data['execute_script_on_pem_server'] = \
            alert_data['execute_script_on_pem_server']
        data_col_type['execute_script_on_pem_server'] = \
            alert_column_type['execute_script_on_pem_server']

    if 'script_code' in alert_data:
        data['script_code'] = alert_data['script_code']
        data_col_type['script_code'] = alert_column_type['script_code']

    if 'cleared_alert_enable' in alert_data:
        data['cleared_alert_enable'] = alert_data['cleared_alert_enable']
        data_col_type['cleared_alert_enable'] = \
            alert_column_type['cleared_alert_enable']

    # Check if 'send_email' column need to update or not.
    if 'all_alert_enable' in alert_data:
        if alert_data['all_alert_enable'] is True:
            data['send_email'] = True
            send_email_check = True
        else:
            data['send_email'] = False
        if 'send_email' not in data_col_type:
            data_col_type['send_email'] = alert_column_type['send_email']
    if not send_email_check and 'low_alert_enable' in alert_data:
        if alert_data['low_alert_enable'] is True:
            data['send_email'] = True
            send_email_check = True
        else:
            data['send_email'] = False
        if 'send_email' not in data_col_type:
            data_col_type['send_email'] = alert_column_type['send_email']
    if not send_email_check and 'med_alert_enable' in alert_data:
        if alert_data['med_alert_enable'] is True:
            data['send_email'] = True
            send_email_check = True
        else:
            data['send_email'] = False
        if 'send_email' not in data_col_type:
            data_col_type['send_email'] = alert_column_type['send_email']
    if not send_email_check and 'high_alert_enable' in alert_data:
        if alert_data['high_alert_enable'] is True:
            data['send_email'] = True
        else:
            data['send_email'] = False
        if 'send_email' not in data_col_type:
            data_col_type['send_email'] = alert_column_type['send_email']
    alert_lvl_email_group_mapping = [
        ['all_alert_enable', 'email_group_id'],
        ['low_alert_enable', 'low_email_group_id'],
        ['med_alert_enable', 'med_email_group_id'],
        ['high_alert_enable', 'high_email_group_id']
    ]
    _, default_email_group_id = pem_conn.execute_scalar(
        'select default_email_group from pem.default_email_group()'
    )
    for alert in alert_lvl_email_group_mapping:
        if alert_data.get(alert[0]) and alert[1] not in alert_data:
            data_col_type[alert[1]] = alert_column_type[alert[1]]
            data[alert[1]] = default_email_group_id
    # Update pem.alert table
    if len(data) > 0:
        if 'thresholds' in data:
            data['thresholds'] = (
                ', '.join([f"'{item}'" for item in data['thresholds']]))
        sql = render_template(
            'alerts/sql/alerts/update.sql',
            data=data,
            col_type=data_col_type,
            alert_id=alert_data['id']
        )

        status, result = pem_conn.execute_void(sql)

    return status, result


def check_alert_copy_parameters(source, targets, pem_conn):
    """
    This function will check all the required parameters is
    present and valid for copy probe configuration.

    :param source: Source object.
    :param targets: Multiple target objects.
    :param pem_conn: PEM Connection.
    :return:
    """

    if 'type' not in source:
        return gettext("Source type for copy not provided.")
    elif source['type'] != 'agent' and source['type'] != 'server' \
            and source['type'] != 'database' and source['type'] != 'schema' \
            and source['type'] != 'table' and source['type'] != 'index' \
            and source['type'] != 'sequence' and source['type'] != 'function':
        return gettext("Source type not supported.")

    for target in targets:
        if 'type' not in target:
            return gettext("Target type for copy not provided.")
        elif target['type'] != 'agent' and target['type'] != 'server' \
                and target['type'] != 'server-group' \
                and target['type'] != 'database' \
                and target['type'] != 'schema' \
                and target['type'] != 'table' and target['type'] != 'index' \
                and target['type'] != 'sequence' \
                and target['type'] != 'function':
            return gettext("Target type not supported.")

        if source['type'] == 'agent' and target['type'] == 'server-group':
            if 'agent_id' not in source:
                return gettext("Source agent id is not provided.")
            elif 'group_id' not in target:
                return gettext("Target agent id is not provided.")

            # Check target server group is exist or not.
            group_exist = is_server_group_exists(pem_conn,
                                                 target['group_id'])
            if not group_exist:
                return gettext(
                    "The specified target server_group not found!")

        elif source['type'] == 'agent' and target['type'] == 'agent':
            if 'agent_id' not in source:
                return gettext("Source agent id is not provided.")
            elif 'agent_id' not in target:
                return gettext("Target agent id is not provided.")

            # Check target agent is exist or not.
            agent_exist = is_agent_exists_and_active(
                pem_conn, target['agent_id'])
            if not agent_exist:
                return gettext(
                    "The specified target agent not found or not active!")

            if source['agent_id'] == target["agent_id"]:
                return gettext("Specified source and target is same.")

        elif source['type'] == 'server' and target['type'] == 'server-group':
            if 'server_id' not in source:
                return gettext("Source server id is not provided.")
            elif 'group_id' not in target:
                return gettext("Target group_id is not provided.")

            # Check target server group is exist or not.
            group_exist = is_server_group_exists(pem_conn,
                                                 target['group_id'])
            if not group_exist:
                return gettext(
                    "The specified target server_group not found!")

        elif source['type'] == 'server' and target['type'] == 'server':
            if 'server_id' not in source:
                return gettext("Source server id is not provided.")
            elif 'server_id' not in target:
                return gettext("Target server id is not provided.")

            # Check the given object is exist or not.
            object_exist, msg = is_object_exists(
                pem_conn, 'server', target['server_id'])
            if not object_exist:
                return gettext("The specified target server not found!")

            if source['server_id'] == target["server_id"]:
                return gettext("Specified source and target is same.")

        elif source['type'] == 'database' and target['type'] == 'server-group':
            if 'server_id' not in source:
                return gettext("Source server id is not provided.")
            elif 'database_name' not in source:
                return gettext("Source database name is not provided.")
            elif 'group_id' not in target:
                return gettext("Target group_id is not provided.")

            # Check target server group is exist or not.
            group_exist = is_server_group_exists(pem_conn, target['group_id'])
            if not group_exist:
                return gettext("The specified target server_group not found!")

        elif source['type'] == 'database' and target['type'] == 'server-group':
            if 'server_id' not in source:
                return gettext("Source server id is not provided.")
            elif 'database_name' not in source:
                return gettext("Source database name is not provided.")
            elif 'group_id' not in target:
                return gettext("Target group_id is not provided.")

            # Check target server group is exist or not.
            group_exist = is_server_group_exists(pem_conn,
                                                 target['group_id'])
            if not group_exist:
                return gettext(
                    "The specified target server_group not found!")

        elif source['type'] == 'database' and target['type'] == 'server':
            if 'server_id' not in source:
                return gettext("Source server id is not provided.")
            elif 'database_name' not in source:
                return gettext("Source database name is not provided.")
            elif 'server_id' not in target:
                return gettext("Target server id is not provided.")

            # Check the given object is exist or not.
            object_exist, msg = is_object_exists(
                pem_conn, 'server', target['server_id'])
            if not object_exist:
                return gettext("The specified target server not found!")

        elif source['type'] == 'database' and target['type'] == 'database':
            if 'server_id' not in source:
                return gettext("Source server id is not provided.")
            elif 'database_name' not in source:
                return gettext("Source database name is not provided.")
            elif 'server_id' not in target:
                return gettext("Target server id is not provided.")
            elif 'database_name' not in target:
                return gettext("Target database name is not provided.")

            # Check the given object is exist or not.
            object_exist, msg = is_object_exists(
                pem_conn, 'database', target['server_id'],
                target['database_name'])
            if not object_exist:
                return gettext(
                    "The specified target server or database not found!")

            if source['server_id'] == target["server_id"] \
                    and source['database_name'] == target['database_name']:
                return gettext("Specified source and target is same.")

        elif source['type'] == 'schema' and target['type'] == 'server-group':
            if 'server_id' not in source:
                return gettext("Source server id is not provided.")
            elif 'database_name' not in source:
                return gettext("Source database name is not provided.")
            elif 'schema_name' not in source:
                return gettext("Source schema name is not provided.")
            elif 'group_id' not in target:
                return gettext("Target group_id is not provided.")

            # Check target server group is exist or not.
            group_exist = is_server_group_exists(pem_conn,
                                                 target['group_id'])
            if not group_exist:
                return gettext(
                    "The specified target server_group not found!")

        elif source['type'] == 'schema' and target['type'] == 'server':
            if 'server_id' not in source:
                return gettext("Source server id is not provided.")
            elif 'database_name' not in source:
                return gettext("Source database name is not provided.")
            elif 'schema_name' not in source:
                return gettext("Source schema name is not provided.")
            elif 'server_id' not in target:
                return gettext("Target server id is not provided.")

            # Check the given object is exist or not.
            object_exist, msg = is_object_exists(
                pem_conn, 'server', target['server_id'])
            if not object_exist:
                return gettext("The specified target server not found!")

        elif source['type'] == 'schema' and target['type'] == 'database':
            if 'server_id' not in source:
                return gettext("Source server id is not provided.")
            elif 'database_name' not in source:
                return gettext("Source database name is not provided.")
            elif 'schema_name' not in source:
                return gettext("Source schema name is not provided.")
            elif 'server_id' not in target:
                return gettext("Target server id is not provided.")
            elif 'database_name' not in target:
                return gettext("Target database name is not provided.")

            # Check the given object is exist or not.
            object_exist, msg = is_object_exists(
                pem_conn, 'database', target['server_id'],
                target['database_name'])
            if not object_exist:
                return gettext(
                    "The specified target server or database not found!")

        elif source['type'] == 'schema' and target['type'] == 'schema':
            if 'server_id' not in source:
                return gettext("Source server id is not provided.")
            elif 'database_name' not in source:
                return gettext("Source database name is not provided.")
            elif 'schema_name' not in source:
                return gettext("Source schema name is not provided.")
            elif 'server_id' not in target:
                return gettext("Target server id is not provided.")
            elif 'database_name' not in target:
                return gettext("Target database name is not provided.")
            elif 'schema_name' not in target:
                return gettext("Target schema name is not provided.")

            # Check the given object is exist or not.
            object_exist, msg = is_object_exists(
                pem_conn, 'schema', target['server_id'],
                target['database_name'], target['schema_name'])
            if not object_exist:
                return gettext("The specified target server or database or "
                               "schema not found!")

            if source['server_id'] == target["server_id"] \
                    and source['database_name'] == target['database_name'] \
                    and source['schema_name'] == target['schema_name']:
                return gettext("Specified source and target is same.")

        elif source['type'] == 'table' and target['type'] == 'server-group':
            if 'server_id' not in source:
                return gettext("Source server id is not provided.")
            elif 'database_name' not in source:
                return gettext("Source database name is not provided.")
            elif 'schema_name' not in source:
                return gettext("Source schema name is not provided.")
            elif 'object_name' not in source:
                return gettext("Source table name is not provided.")
            elif 'group_id' not in target:
                return gettext("Target group_id is not provided.")

            # Check target server group is exist or not.
            group_exist = is_server_group_exists(pem_conn,
                                                 target['group_id'])
            if not group_exist:
                return gettext(
                    "The specified target server_group not found!")

        elif source['type'] == 'table' and target['type'] == 'server':
            if 'server_id' not in source:
                return gettext("Source server id is not provided.")
            elif 'database_name' not in source:
                return gettext("Source database name is not provided.")
            elif 'schema_name' not in source:
                return gettext("Source schema name is not provided.")
            elif 'object_name' not in source:
                return gettext("Source object name is not provided.")
            elif 'server_id' not in target:
                return gettext("Target server id is not provided.")

            # Check the given object is exist or not.
            object_exist, msg = is_object_exists(
                pem_conn, 'server', target['server_id'])
            if not object_exist:
                return gettext("The specified target server not found!")

        elif source['type'] == 'table' and target['type'] == 'database':
            if 'server_id' not in source:
                return gettext("Source server id is not provided.")
            elif 'database_name' not in source:
                return gettext("Source database name is not provided.")
            elif 'schema_name' not in source:
                return gettext("Source schema name is not provided.")
            elif 'object_name' not in source:
                return gettext("Source object name is not provided.")
            elif 'server_id' not in target:
                return gettext("Target server id is not provided.")
            elif 'database_name' not in target:
                return gettext("Target database name is not provided.")

            # Check the given object is exist or not.
            object_exist, msg = is_object_exists(
                pem_conn, 'database', target['server_id'],
                target['database_name'])
            if not object_exist:
                return gettext(
                    "The specified target server or database not found!")

        elif source['type'] == 'table' and target['type'] == 'schema':
            if 'server_id' not in source:
                return gettext("Source server id is not provided.")
            elif 'database_name' not in source:
                return gettext("Source database name is not provided.")
            elif 'schema_name' not in source:
                return gettext("Source schema name is not provided.")
            elif 'object_name' not in source:
                return gettext("Source table name is not provided.")
            elif 'server_id' not in target:
                return gettext("Target server id is not provided.")
            elif 'database_name' not in target:
                return gettext("Target database name is not provided.")
            elif 'schema_name' not in target:
                return gettext("Target schema name is not provided.")

            # Check the given object is exist or not.
            object_exist, msg = is_object_exists(
                pem_conn, 'schema', target['server_id'],
                target['database_name'], target['schema_name'])
            if not object_exist:
                return gettext("The specified target server or database or "
                               "schema not found!")

        elif source['type'] == 'table' and target['type'] == 'table':
            if 'server_id' not in source:
                return gettext("Source server id is not provided.")
            elif 'database_name' not in source:
                return gettext("Source database name is not provided.")
            elif 'schema_name' not in source:
                return gettext("Source schema name is not provided.")
            elif 'object_name' not in source:
                return gettext("Source table name is not provided.")
            elif 'server_id' not in target:
                return gettext("Target server id is not provided.")
            elif 'database_name' not in target:
                return gettext("Target database name is not provided.")
            elif 'schema_name' not in target:
                return gettext("Target schema name is not provided.")
            elif 'object_name' not in target:
                return gettext("Target table name is not provided.")

            # Check the given object is exist or not.
            object_exist, msg = is_object_exists(
                pem_conn, 'table', target['server_id'],
                target['database_name'], target['schema_name'],
                target['object_name'])
            if not object_exist:
                return gettext("The specified target server or database or "
                               "schema or table not found!")

            if source['server_id'] == target["server_id"] \
                    and source['database_name'] == target['database_name'] \
                    and source['schema_name'] == target['schema_name'] \
                    and source['object_name'] == target['object_name']:
                return gettext("Specified source and target is same.")

        elif source['type'] == 'index' and target['type'] == 'server-group':
            if 'server_id' not in source:
                return gettext("Source server id is not provided.")
            elif 'database_name' not in source:
                return gettext("Source database name is not provided.")
            elif 'schema_name' not in source:
                return gettext("Source schema name is not provided.")
            elif 'object_name' not in source:
                return gettext("Source index name is not provided.")
            elif 'group_id' not in target:
                return gettext("Target group_id is not provided.")

            # Check target server group is exist or not.
            group_exist = is_server_group_exists(pem_conn,
                                                 target['group_id'])
            if not group_exist:
                return gettext(
                    "The specified target server_group not found!")

        elif source['type'] == 'index' and target['type'] == 'server':
            if 'server_id' not in source:
                return gettext("Source server id is not provided.")
            elif 'database_name' not in source:
                return gettext("Source database name is not provided.")
            elif 'schema_name' not in source:
                return gettext("Source schema name is not provided.")
            elif 'object_name' not in source:
                return gettext("Source index name is not provided.")
            elif 'server_id' not in target:
                return gettext("Target server id is not provided.")

            # Check the given object is exist or not.
            object_exist, msg = is_object_exists(
                pem_conn, 'server', target['server_id'])
            if not object_exist:
                return gettext("The specified target server not found!")

        elif source['type'] == 'index' and target['type'] == 'database':
            if 'server_id' not in source:
                return gettext("Source server id is not provided.")
            elif 'database_name' not in source:
                return gettext("Source database name is not provided.")
            elif 'schema_name' not in source:
                return gettext("Source schema name is not provided.")
            elif 'object_name' not in source:
                return gettext("Source index name is not provided.")
            elif 'server_id' not in target:
                return gettext("Target server id is not provided.")
            elif 'database_name' not in target:
                return gettext("Target database name is not provided.")

            # Check the given object is exist or not.
            object_exist, msg = is_object_exists(
                pem_conn, 'database', target['server_id'],
                target['database_name'])
            if not object_exist:
                return gettext(
                    "The specified target server or database not found!")

        elif source['type'] == 'index' and target['type'] == 'schema':
            if 'server_id' not in source:
                return gettext("Source server id is not provided.")
            elif 'database_name' not in source:
                return gettext("Source database name is not provided.")
            elif 'schema_name' not in source:
                return gettext("Source schema name is not provided.")
            elif 'object_name' not in source:
                return gettext("Source index name is not provided.")
            elif 'server_id' not in target:
                return gettext("Target server id is not provided.")
            elif 'database_name' not in target:
                return gettext("Target database name is not provided.")
            elif 'schema_name' not in target:
                return gettext("Target schema name is not provided.")

            # Check the given object is exist or not.
            object_exist, msg = is_object_exists(
                pem_conn, 'schema', target['server_id'],
                target['database_name'], target['schema_name'])
            if not object_exist:
                return gettext("The specified target server or database or "
                               "schema not found!")

        elif source['type'] == 'index' and target['type'] == 'table':
            if 'server_id' not in source:
                return gettext("Source server id is not provided.")
            elif 'database_name' not in source:
                return gettext("Source database name is not provided.")
            elif 'schema_name' not in source:
                return gettext("Source schema name is not provided.")
            elif 'object_name' not in source:
                return gettext("Source index name is not provided.")
            elif 'server_id' not in target:
                return gettext("Target server id is not provided.")
            elif 'database_name' not in target:
                return gettext("Target database name is not provided.")
            elif 'schema_name' not in target:
                return gettext("Target schema name is not provided.")
            elif 'object_name' not in target:
                return gettext("Target table name is not provided.")

            # Check the given object is exist or not.
            object_exist, msg = is_object_exists(
                pem_conn, 'table', target['server_id'],
                target['database_name'], target['schema_name'],
                target['object_name'])
            if not object_exist:
                return gettext("The specified target server or database or "
                               "schema or table not found!")

            if source['server_id'] == target["server_id"] \
                    and source['database_name'] == target['database_name'] \
                    and source['schema_name'] == target['schema_name'] \
                    and source['object_name'] == target['object_name']:
                return gettext("Specified source and target is same.")

        elif source['type'] == 'index' and target['type'] == 'index':
            if 'server_id' not in source:
                return gettext("Source server id is not provided.")
            elif 'database_name' not in source:
                return gettext("Source database name is not provided.")
            elif 'schema_name' not in source:
                return gettext("Source schema name is not provided.")
            elif 'object_name' not in source:
                return gettext("Source index name is not provided.")
            elif 'server_id' not in target:
                return gettext("Target server id is not provided.")
            elif 'database_name' not in target:
                return gettext("Target database name is not provided.")
            elif 'schema_name' not in target:
                return gettext("Target schema name is not provided.")
            elif 'object_name' not in target:
                return gettext("Target index name is not provided.")

            # Check the given object is exist or not.
            object_exist, msg = is_object_exists(
                pem_conn, 'index', target['server_id'],
                target['database_name'], target['schema_name'],
                target['object_name'])
            if not object_exist:
                return gettext("The specified target server or database or "
                               "schema or index not found!")

            if source['server_id'] == target["server_id"] \
                    and source['database_name'] == target['database_name'] \
                    and source['schema_name'] == target['schema_name'] \
                    and source['object_name'] == target['object_name']:
                return gettext("Specified source and target is same.")

        elif source['type'] == 'sequence' and target['type'] == 'server-group':
            if 'server_id' not in source:
                return gettext("Source server id is not provided.")
            elif 'database_name' not in source:
                return gettext("Source database name is not provided.")
            elif 'schema_name' not in source:
                return gettext("Source schema name is not provided.")
            elif 'object_name' not in source:
                return gettext("Source sequence name is not provided.")
            elif 'group_id' not in target:
                return gettext("Target group_id is not provided.")

            # Check target server group is exist or not.
            group_exist = is_server_group_exists(pem_conn,
                                                 target['group_id'])
            if not group_exist:
                return gettext(
                    "The specified target server_group not found!")

        elif source['type'] == 'sequence' and target['type'] == 'server':
            if 'server_id' not in source:
                return gettext("Source server id is not provided.")
            elif 'database_name' not in source:
                return gettext("Source database name is not provided.")
            elif 'schema_name' not in source:
                return gettext("Source schema name is not provided.")
            elif 'object_name' not in source:
                return gettext("Source sequence name is not provided.")
            elif 'server_id' not in target:
                return gettext("Target server id is not provided.")

            # Check the given object is exist or not.
            object_exist, msg = is_object_exists(
                pem_conn, 'server', target['server_id'])
            if not object_exist:
                return gettext("The specified target server not found!")

        elif source['type'] == 'sequence' and target['type'] == 'database':
            if 'server_id' not in source:
                return gettext("Source server id is not provided.")
            elif 'database_name' not in source:
                return gettext("Source database name is not provided.")
            elif 'schema_name' not in source:
                return gettext("Source schema name is not provided.")
            elif 'object_name' not in source:
                return gettext("Source sequence name is not provided.")
            elif 'server_id' not in target:
                return gettext("Target server id is not provided.")
            elif 'database_name' not in target:
                return gettext("Target database name is not provided.")

            # Check the given object is exist or not.
            object_exist, msg = is_object_exists(
                pem_conn, 'database', target['server_id'],
                target['database_name'])
            if not object_exist:
                return gettext(
                    "The specified target server or database not found!")

        elif source['type'] == 'sequence' and target['type'] == 'schema':
            if 'server_id' not in source:
                return gettext("Source server id is not provided.")
            elif 'database_name' not in source:
                return gettext("Source database name is not provided.")
            elif 'schema_name' not in source:
                return gettext("Source schema name is not provided.")
            elif 'object_name' not in source:
                return gettext("Source sequence name is not provided.")
            elif 'server_id' not in target:
                return gettext("Target server id is not provided.")
            elif 'database_name' not in target:
                return gettext("Target database name is not provided.")
            elif 'schema_name' not in target:
                return gettext("Target schema name is not provided.")

            # Check the given object is exist or not.
            object_exist, msg = is_object_exists(
                pem_conn, 'schema', target['server_id'],
                target['database_name'], target['schema_name'])
            if not object_exist:
                return gettext("The specified target server or database or "
                               "schema not found!")

        elif source['type'] == 'sequence' and target['type'] == 'sequence':
            if 'server_id' not in source:
                return gettext("Source server id is not provided.")
            elif 'database_name' not in source:
                return gettext("Source database name is not provided.")
            elif 'schema_name' not in source:
                return gettext("Source schema name is not provided.")
            elif 'object_name' not in source:
                return gettext("Source sequence name is not provided.")
            elif 'server_id' not in target:
                return gettext("Target server id is not provided.")
            elif 'database_name' not in target:
                return gettext("Target database name is not provided.")
            elif 'schema_name' not in target:
                return gettext("Target schema name is not provided.")
            elif 'object_name' not in target:
                return gettext("Target sequence name is not provided.")

            # Check the given object is exist or not.
            object_exist, msg = is_object_exists(
                pem_conn, 'sequence', target['server_id'],
                target['database_name'], target['schema_name'],
                target['object_name'])
            if not object_exist:
                return gettext("The specified target server or database or "
                               "schema or sequence not found!")

            if source['server_id'] == target["server_id"] \
                    and source['database_name'] == target['database_name'] \
                    and source['schema_name'] == target['schema_name'] \
                    and source['object_name'] == target['object_name']:
                return gettext("Specified source and target is same.")

        elif source['type'] == 'function' and target['type'] == 'server-group':
            if 'server_id' not in source:
                return gettext("Source server id is not provided.")
            elif 'database_name' not in source:
                return gettext("Source database name is not provided.")
            elif 'schema_name' not in source:
                return gettext("Source schema name is not provided.")
            elif 'object_name' not in source:
                return gettext("Source function name is not provided.")
            elif 'group_id' not in target:
                return gettext("Target group_id is not provided.")

            # Check target server group is exist or not.
            group_exist = is_server_group_exists(pem_conn,
                                                 target['group_id'])
            if not group_exist:
                return gettext(
                    "The specified target server_group not found!")

        elif source['type'] == 'function' and target['type'] == 'server':
            if 'server_id' not in source:
                return gettext("Source server id is not provided.")
            elif 'database_name' not in source:
                return gettext("Source database name is not provided.")
            elif 'schema_name' not in source:
                return gettext("Source schema name is not provided.")
            elif 'object_name' not in source:
                return gettext("Source function name is not provided.")
            elif 'server_id' not in target:
                return gettext("Target server id is not provided.")

            # Check the given object is exist or not.
            object_exist, msg = is_object_exists(
                pem_conn, 'server', target['server_id'])
            if not object_exist:
                return gettext("The specified target server not found!")

        elif source['type'] == 'function' and target['type'] == 'database':
            if 'server_id' not in source:
                return gettext("Source server id is not provided.")
            elif 'database_name' not in source:
                return gettext("Source database name is not provided.")
            elif 'schema_name' not in source:
                return gettext("Source schema name is not provided.")
            elif 'object_name' not in source:
                return gettext("Source function name is not provided.")
            elif 'server_id' not in target:
                return gettext("Target server id is not provided.")
            elif 'database_name' not in target:
                return gettext("Target database name is not provided.")

            # Check the given object is exist or not.
            object_exist, msg = is_object_exists(
                pem_conn, 'database', target['server_id'],
                target['database_name'])
            if not object_exist:
                return gettext(
                    "The specified target server or database not found!")

        elif source['type'] == 'function' and target['type'] == 'schema':
            if 'server_id' not in source:
                return gettext("Source server id is not provided.")
            elif 'database_name' not in source:
                return gettext("Source database name is not provided.")
            elif 'schema_name' not in source:
                return gettext("Source schema name is not provided.")
            elif 'object_name' not in source:
                return gettext("Source function name is not provided.")
            elif 'server_id' not in target:
                return gettext("Target server id is not provided.")
            elif 'database_name' not in target:
                return gettext("Target database name is not provided.")
            elif 'schema_name' not in target:
                return gettext("Target schema name is not provided.")

            # Check the given object is exist or not.
            object_exist, msg = is_object_exists(
                pem_conn, 'schema', target['server_id'],
                target['database_name'], target['schema_name'])
            if not object_exist:
                return gettext("The specified target server or database or "
                               "schema not found!")

        elif source['type'] == 'function' and target['type'] == 'function':
            if 'server_id' not in source:
                return gettext("Source server id is not provided.")
            elif 'database_name' not in source:
                return gettext("Source database name is not provided.")
            elif 'schema_name' not in source:
                return gettext("Source schema name is not provided.")
            elif 'object_name' not in source:
                return gettext("Source function name is not provided.")
            elif 'server_id' not in target:
                return gettext("Target server id is not provided.")
            elif 'database_name' not in target:
                return gettext("Target database name is not provided.")
            elif 'schema_name' not in target:
                return gettext("Target schema name is not provided.")
            elif 'object_name' not in target:
                return gettext("Target function name is not provided.")
            elif 'args' in target:
                target['function_arguments'] = target['args']
            elif 'function_arguments' not in target:
                target['function_arguments'] = None

            # Check the given object is exist or not.
            object_exist, msg = is_object_exists(
                pem_conn, 'function', target['server_id'],
                target['database_name'], target['schema_name'],
                target['function_name'], target['function_arguments'])
            if not object_exist:
                return gettext("The specified target server or database or "
                               "schema or function not found!")

            if source['server_id'] == target["server_id"] \
                    and source['database_name'] == target['database_name'] \
                    and source['schema_name'] == target['schema_name'] \
                    and source['object_name'] == target['object_name']:
                return gettext("Specified source and target is same.")

        else:
            return gettext("Please verify source type and target type for "
                           "copy alert configuration.")
    return None


def copy_alerts(source, targets, existing_alert_options, pem_conn):
    """
    This function is used to copy the alert configuration from
    source objects to multiple target objects.

    :param source: Source object.
    :param targets: Multiple target objects.
    :param existing_alert_options: Ignore/Replace/Delete existing alert
                                    during copy.
    :param pem_conn: PEM Connection.
    :return:
    """

    # Check whether all the required parameter is present and valid.
    error_msg = check_alert_copy_parameters(source, targets, pem_conn)
    if error_msg is not None:
        return False, error_msg

    source_server_version = 0
    target_server_version = 0

    status, result = pem_conn.execute_void("BEGIN;")
    if not status:
        return status, result

    # Get the source server version id
    if 'server_id' in source:
        server_ver_id = source['server_id']
        params = [server_ver_id]
        sql = render_template('alerts/sql/copy_alert/server_version.sql')
        status, result = pem_conn.execute_dict(sql, params)

        if not status:
            pem_conn.execute_void("ROLLBACK;")
            return status, result

        source_server_version = result['rows'][0]['server_version_id']

    for target in targets:
        sql = ''
        if source['type'] == 'agent' and target['type'] == 'server-group':
            sql = render_template(
                'alerts/sql/copy_alert/get_target_list.sql',
                source_type=source['type'],
                target_type=target['type'],
                target_group_id=target['group_id'],
                source_agent_id=source['agent_id']
            )
            status, result = pem_conn.execute_dict(sql)

            if not status:
                pem_conn.execute_void("ROLLBACK;")
                return status, result

            if len(result['rows']) == 0:
                pem_conn.execute_void("ROLLBACK;")
                return False, gettext(
                    "Unable to fetch any object information bound to the"
                    " selected target server group."
                )

            sql = render_template(
                'alerts/sql/copy_alert/config.sql',
                source_type=source['type'],
                target_type=target['type'],
                source_agent_id=source['agent_id'],
                source_server_version=source_server_version,
                existing_alert_options=existing_alert_options,
                target_data=result['rows']
            )
        elif source['type'] == 'agent' and target['type'] == 'agent':
            sql = render_template(
                'alerts/sql/copy_alert/config.sql',
                source_type=source['type'],
                target_type=target['type'],
                source_agent_id=source['agent_id'],
                target_agent_id=target['agent_id'],
                existing_alert_options=existing_alert_options
            )
        elif source['type'] == 'server' and target['type'] == 'server-group':
            sql = render_template(
                'alerts/sql/copy_alert/get_target_list.sql',
                source_type=source['type'],
                target_type=target['type'],
                target_group_id=target['group_id'],
                source_server_id=source['server_id']
            )
            status, result = pem_conn.execute_dict(sql)

            if not status:
                pem_conn.execute_void("ROLLBACK;")
                return status, result

            if len(result['rows']) == 0:
                pem_conn.execute_void("ROLLBACK;")
                return False, gettext(
                    "Unable to fetch any server information bound to the"
                    " selected target agent."
                )
            sql = render_template(
                'alerts/sql/copy_alert/config.sql',
                source_type=source['type'],
                target_type=target['type'],
                source_server_id=source['server_id'],
                source_server_version=source_server_version,
                existing_alert_options=existing_alert_options,
                target_data=result['rows']
            )
        elif source['type'] == 'server' and target['type'] == 'server':
            # Get the target server version id
            if 'server_id' in target:
                server_ver_id = target['server_id']
                params = [server_ver_id]
                sql = render_template(
                    'alerts/sql/copy_alert/server_version.sql')
                status, result = pem_conn.execute_dict(sql, params)

                if not status:
                    pem_conn.execute_void("ROLLBACK;")
                    return status, result

                target_server_version = result['rows'][0]['server_version_id']

            sql = render_template(
                'alerts/sql/copy_alert/config.sql',
                source_type=source['type'],
                target_type=target['type'],
                source_server_id=source['server_id'],
                target_server_id=target['server_id'],
                source_server_version=source_server_version,
                target_server_version=target_server_version,
                existing_alert_options=existing_alert_options
            )
        elif source['type'] == 'database' and target['type'] == 'server-group':
            # First fetch all the target node information
            sql = render_template(
                'alerts/sql/copy_alert/'
                'get_target_list.sql',
                source_type=source['type'],
                target_type=target['type'],
                target_group_id=target['group_id'],
                source_server_id=source['server_id'],
                source_database_name=source['database_name']
            )
            status, result = pem_conn.execute_dict(sql)

            if not status:
                pem_conn.execute_void("ROLLBACK;")
                return status, result

            sql = render_template(
                'alerts/sql/copy_alert/config.sql',
                source_type=source['type'],
                target_type=target['type'],
                source_server_id=source['server_id'],
                source_database_name=source['database_name'],
                source_server_version=source_server_version,
                existing_alert_options=existing_alert_options,
                target_data=result['rows']
            )
        elif source['type'] == 'database' and target['type'] == 'server':
            # First fetch all the target node information
            sql = render_template(
                'alerts/sql/copy_alert/get_target_list.sql',
                source_type=source['type'],
                target_type=target['type'],
                source_server_id=source['server_id'],
                source_database_name=source['database_name'],
                target_server_id=target['server_id']
            )
            status, result = pem_conn.execute_dict(sql)

            if not status:
                pem_conn.execute_void("ROLLBACK;")
                return status, result

            sql = render_template(
                'alerts/sql/copy_alert/config.sql',
                source_type=source['type'],
                target_type=target['type'],
                source_server_id=source['server_id'],
                source_database_name=source['database_name'],
                target_server_id=target['server_id'],
                source_server_version=source_server_version,
                existing_alert_options=existing_alert_options,
                target_data=result['rows']
            )
        elif source['type'] == 'database' and target['type'] == 'database':
            # Get the target server version id
            if 'server_id' in target:
                server_ver_id = target['server_id']
                params = [server_ver_id]
                sql = render_template(
                    'alerts/sql/copy_alert/server_version.sql')
                status, result = pem_conn.execute_dict(sql, params)

                if not status:
                    pem_conn.execute_void("ROLLBACK;")
                    return status, result

                target_server_version = result['rows'][0]['server_version_id']

            sql = render_template(
                'alerts/sql/copy_alert/config.sql',
                source_type=source['type'],
                target_type=target['type'],
                source_server_id=source['server_id'],
                source_database_name=source['database_name'],
                target_server_id=target['server_id'],
                target_database_name=target['database_name'],
                source_server_version=source_server_version,
                target_server_version=target_server_version,
                existing_alert_options=existing_alert_options
            )
        elif source['type'] == 'schema' and target['type'] == 'server-group':
            sql = render_template(
                'alerts/sql/copy_alert/get_target_list.sql',
                source_type=source['type'],
                target_type=target['type'],
                target_group_id=target['group_id'],
                source_server_id=source['server_id'],
                source_database_name=source['database_name'],
                source_schema_name=source['schema_name']
            )
            status, result = pem_conn.execute_dict(sql)

            if not status:
                pem_conn.execute_void("ROLLBACK;")
                return status, result

            sql = render_template(
                'alerts/sql/copy_alert/config.sql',
                source_type=source['type'],
                target_type=target['type'],
                source_server_id=source['server_id'],
                source_database_name=source['database_name'],
                source_schema_name=source['schema_name'],
                source_server_version=source_server_version,
                existing_alert_options=existing_alert_options,
                target_data=result['rows']
            )
        elif source['type'] == 'schema' and target['type'] == 'server':
            sql = render_template(
                'alerts/sql/copy_alert/get_target_list.sql',
                source_type=source['type'],
                target_type=target['type'],
                source_server_id=source['server_id'],
                source_database_name=source['database_name'],
                source_schema_name=source['schema_name'],
                target_server_id=target['server_id']
            )
            status, result = pem_conn.execute_dict(sql)

            if not status:
                pem_conn.execute_void("ROLLBACK;")
                return status, result

            sql = render_template(
                'alerts/sql/copy_alert/config.sql',
                source_type=source['type'],
                target_type=target['type'],
                source_server_id=source['server_id'],
                source_database_name=source['database_name'],
                source_schema_name=source['schema_name'],
                target_server_id=target['server_id'],
                source_server_version=source_server_version,
                existing_alert_options=existing_alert_options,
                target_data=result['rows']
            )
        elif source['type'] == 'schema' and target['type'] == 'database':
            sql = render_template(
                'alerts/sql/copy_alert/get_target_list.sql',
                source_type=source['type'],
                target_type=target['type'],
                source_server_id=source['server_id'],
                source_database_name=source['database_name'],
                source_schema_name=source['schema_name'],
                target_server_id=target['server_id'],
                target_database_name=target['database_name']
            )
            status, result = pem_conn.execute_dict(sql)

            if not status:
                pem_conn.execute_void("ROLLBACK;")
                return status, result

            sql = render_template(
                'alerts/sql/copy_alert/config.sql',
                source_type=source['type'],
                target_type=target['type'],
                source_server_id=source['server_id'],
                source_database_name=source['database_name'],
                source_schema_name=source['schema_name'],
                target_server_id=target['server_id'],
                target_database_name=target['database_name'],
                source_server_version=source_server_version,
                existing_alert_options=existing_alert_options,
                target_data=result['rows']
            )
        elif source['type'] == 'schema' and target['type'] == 'schema':
            # Get the target server version id
            if 'server_id' in target:
                server_ver_id = target['server_id']
                params = [server_ver_id]
                sql = render_template(
                    'alerts/sql/copy_alert/server_version.sql')
                status, result = pem_conn.execute_dict(sql, params)

                if not status:
                    pem_conn.execute_void("ROLLBACK;")
                    return status, result

                target_server_version = result['rows'][0]['server_version_id']

            sql = render_template(
                'alerts/sql/copy_alert/config.sql',
                source_type=source['type'],
                target_type=target['type'],
                source_server_id=source['server_id'],
                source_database_name=source['database_name'],
                source_schema_name=source['schema_name'],
                target_server_id=target['server_id'],
                target_database_name=target['database_name'],
                target_schema_name=target['schema_name'],
                source_server_version=source_server_version,
                target_server_version=target_server_version,
                existing_alert_options=existing_alert_options
            )
        elif source['type'] == 'table' and target['type'] == 'server-group':
            sql = render_template(
                'alerts/sql/copy_alert/get_target_list.sql',
                source_type=source['type'],
                target_type=target['type'],
                target_group_id=target['group_id'],
                source_server_id=source['server_id'],
                source_database_name=source['database_name'],
                source_schema_name=source['schema_name'],
                source_object_name=source['object_name']
            )
            status, result = pem_conn.execute_dict(sql)

            if not status:
                pem_conn.execute_void("ROLLBACK;")
                return status, result

            sql = render_template(
                'alerts/sql/copy_alert/config.sql',
                source_type=source['type'],
                target_type=target['type'],
                source_server_id=source['server_id'],
                source_database_name=source['database_name'],
                source_schema_name=source['schema_name'],
                source_object_name=source['object_name'],
                source_server_version=source_server_version,
                existing_alert_options=existing_alert_options,
                target_data=result['rows']
            )
        elif source['type'] == 'table' and target['type'] == 'server':
            sql = render_template(
                'alerts/sql/copy_alert/'
                'get_target_list.sql',
                source_type=source['type'],
                target_type=target['type'],
                source_server_id=source['server_id'],
                source_database_name=source['database_name'],
                source_schema_name=source['schema_name'],
                source_object_name=source['object_name'],
                target_server_id=target['server_id']
            )
            status, result = pem_conn.execute_dict(sql)

            if not status:
                pem_conn.execute_void("ROLLBACK;")
                return status, result

            sql = render_template(
                'alerts/sql/copy_alert/config.sql',
                source_type=source['type'],
                target_type=target['type'],
                source_server_id=source['server_id'],
                source_database_name=source['database_name'],
                source_schema_name=source['schema_name'],
                source_object_name=source['object_name'],
                target_server_id=target['server_id'],
                source_server_version=source_server_version,
                existing_alert_options=existing_alert_options,
                target_data=result['rows']
            )
        elif source['type'] == 'table' and target['type'] == 'database':
            sql = render_template(
                'alerts/sql/copy_alert/get_target_list.sql',
                source_type=source['type'],
                target_type=target['type'],
                source_server_id=source['server_id'],
                source_database_name=source['database_name'],
                source_schema_name=source['schema_name'],
                source_object_name=source['object_name'],
                target_server_id=target['server_id'],
                target_database_name=target['database_name']
            )
            status, result = pem_conn.execute_dict(sql)

            if not status:
                pem_conn.execute_void("ROLLBACK;")
                return status, result

            sql = render_template(
                'alerts/sql/copy_alert/config.sql',
                source_type=source['type'],
                target_type=target['type'],
                source_server_id=source['server_id'],
                source_database_name=source['database_name'],
                source_schema_name=source['schema_name'],
                source_object_name=source['object_name'],
                target_server_id=target['server_id'],
                target_database_name=target['database_name'],
                source_server_version=source_server_version,
                existing_alert_options=existing_alert_options,
                target_data=result['rows']
            )
        elif source['type'] == 'table' and target['type'] == 'schema':
            sql = render_template(
                'alerts/sql/copy_alert/get_target_list.sql',
                source_type=source['type'],
                target_type=target['type'],
                source_server_id=source['server_id'],
                source_database_name=source['database_name'],
                source_schema_name=source['schema_name'],
                source_object_name=source['object_name'],
                target_server_id=target['server_id'],
                target_database_name=target['database_name'],
                target_schema_name=target['schema_name']
            )
            status, result = pem_conn.execute_dict(sql)

            if not status:
                pem_conn.execute_void("ROLLBACK;")
                return status, result

            sql = render_template(
                'alerts/sql/copy_alert/config.sql',
                source_type=source['type'],
                target_type=target['type'],
                source_server_id=source['server_id'],
                source_database_name=source['database_name'],
                source_schema_name=source['schema_name'],
                source_object_name=source['object_name'],
                target_server_id=target['server_id'],
                target_database_name=target['database_name'],
                target_schema_name=target['schema_name'],
                source_server_version=source_server_version,
                existing_alert_options=existing_alert_options,
                target_data=result['rows']
            )
        elif source['type'] == 'table' and target['type'] == 'table':
            # Get the target server version id
            if 'server_id' in target:
                server_ver_id = target['server_id']
                params = [server_ver_id]
                sql = render_template(
                    'alerts/sql/copy_alert/server_version.sql')
                status, result = pem_conn.execute_dict(sql, params)

                if not status:
                    pem_conn.execute_void("ROLLBACK;")
                    return status, result

                target_server_version = result['rows'][0]['server_version_id']

            sql = render_template(
                'alerts/sql/copy_alert/config.sql',
                source_type=source['type'],
                target_type=target['type'],
                source_server_id=source['server_id'],
                source_database_name=source['database_name'],
                source_schema_name=source['schema_name'],
                source_object_name=source['object_name'],
                target_server_id=target['server_id'],
                target_database_name=target['database_name'],
                target_schema_name=target['schema_name'],
                target_object_name=target['object_name'],
                source_server_version=source_server_version,
                target_server_version=target_server_version,
                existing_alert_options=existing_alert_options
            )
        elif source['type'] == 'index' and target['type'] == 'server-group':
            sql = render_template(
                'alerts/sql/copy_alert/get_target_list.sql',
                source_type=source['type'],
                target_type=target['type'],
                target_group_id=target['group_id'],
                source_server_id=source['server_id'],
                source_database_name=source['database_name'],
                source_schema_name=source['schema_name'],
                source_object_name=source['object_name']
            )
            status, result = pem_conn.execute_dict(sql)

            if not status:
                pem_conn.execute_void("ROLLBACK;")
                return status, result

            sql = render_template(
                'alerts/sql/copy_alert/config.sql',
                source_type=source['type'],
                target_type=target['type'],
                source_server_id=source['server_id'],
                source_database_name=source['database_name'],
                source_schema_name=source['schema_name'],
                source_object_name=source['object_name'],
                source_server_version=source_server_version,
                existing_alert_options=existing_alert_options,
                target_data=result['rows']
            )
        elif source['type'] == 'index' and target['type'] == 'server':
            sql = render_template(
                'alerts/sql/copy_alert/'
                'get_target_list.sql',
                source_type=source['type'],
                target_type=target['type'],
                source_server_id=source['server_id'],
                source_database_name=source['database_name'],
                source_schema_name=source['schema_name'],
                source_object_name=source['object_name'],
                target_server_id=target['server_id']
            )
            status, result = pem_conn.execute_dict(sql)

            if not status:
                pem_conn.execute_void("ROLLBACK;")
                return status, result

            sql = render_template(
                'alerts/sql/copy_alert/config.sql',
                source_type=source['type'],
                target_type=target['type'],
                source_server_id=source['server_id'],
                source_database_name=source['database_name'],
                source_schema_name=source['schema_name'],
                source_object_name=source['object_name'],
                target_server_id=target['server_id'],
                source_server_version=source_server_version,
                existing_alert_options=existing_alert_options,
                target_data=result['rows']
            )
        elif source['type'] == 'index' and target['type'] == 'database':
            sql = render_template(
                'alerts/sql/copy_alert/get_target_list.sql',
                source_type=source['type'],
                target_type=target['type'],
                source_server_id=source['server_id'],
                source_database_name=source['database_name'],
                source_schema_name=source['schema_name'],
                source_object_name=source['object_name'],
                target_server_id=target['server_id'],
                target_database_name=target['database_name']
            )
            status, result = pem_conn.execute_dict(sql)

            if not status:
                pem_conn.execute_void("ROLLBACK;")
                return status, result

            sql = render_template(
                'alerts/sql/copy_alert/config.sql',
                source_type=source['type'],
                target_type=target['type'],
                source_server_id=source['server_id'],
                source_database_name=source['database_name'],
                source_schema_name=source['schema_name'],
                source_object_name=source['object_name'],
                target_server_id=target['server_id'],
                target_database_name=target['database_name'],
                source_server_version=source_server_version,
                existing_alert_options=existing_alert_options,
                target_data=result['rows']
            )
        elif source['type'] == 'index' and target['type'] == 'schema':
            sql = render_template(
                'alerts/sql/copy_alert/get_target_list.sql',
                source_type=source['type'],
                target_type=target['type'],
                source_server_id=source['server_id'],
                source_database_name=source['database_name'],
                source_schema_name=source['schema_name'],
                source_object_name=source['object_name'],
                target_server_id=target['server_id'],
                target_database_name=target['database_name'],
                target_schema_name=target['schema_name']
            )
            status, result = pem_conn.execute_dict(sql)

            if not status:
                pem_conn.execute_void("ROLLBACK;")
                return status, result

            sql = render_template(
                'alerts/sql/copy_alert/config.sql',
                source_type=source['type'],
                target_type=target['type'],
                source_server_id=source['server_id'],
                source_database_name=source['database_name'],
                source_schema_name=source['schema_name'],
                source_object_name=source['object_name'],
                target_server_id=target['server_id'],
                target_database_name=target['database_name'],
                target_schema_name=target['schema_name'],
                source_server_version=source_server_version,
                existing_alert_options=existing_alert_options,
                target_data=result['rows']
            )
        elif source['type'] == 'index' and target['type'] == 'table':
            sql = render_template(
                'alerts/sql/copy_alert/get_target_list.sql',
                source_type=source['type'],
                target_type=target['type'],
                source_server_id=source['server_id'],
                source_database_name=source['database_name'],
                source_schema_name=source['schema_name'],
                source_object_name=source['object_name'],
                target_server_id=target['server_id'],
                target_database_name=target['database_name'],
                target_table_name=target['object_name'],
                target_schema_name=target['schema_name']
            )
            status, result = pem_conn.execute_dict(sql)

            if not status:
                pem_conn.execute_void("ROLLBACK;")
                return status, result

            sql = render_template(
                'alerts/sql/copy_alert/config.sql',
                source_type=source['type'],
                target_type=target['type'],
                source_server_id=source['server_id'],
                source_database_name=source['database_name'],
                source_schema_name=source['schema_name'],
                source_object_name=source['object_name'],
                target_server_id=target['server_id'],
                target_database_name=target['database_name'],
                target_schema_name=target['schema_name'],
                source_server_version=source_server_version,
                existing_alert_options=existing_alert_options,
                target_data=result['rows']
            )
        elif source['type'] == 'index' and target['type'] == 'index':
            # Get the target server version id
            if 'server_id' in target:
                server_ver_id = target['server_id']
                params = [server_ver_id]
                sql = render_template(
                    'alerts/sql/copy_alert/server_version.sql')
                status, result = pem_conn.execute_dict(sql, params)

                if not status:
                    pem_conn.execute_void("ROLLBACK;")
                    return status, result

                target_server_version = result['rows'][0]['server_version_id']

            sql = render_template(
                'alerts/sql/copy_alert/config.sql',
                source_type=source['type'],
                target_type=target['type'],
                source_server_id=source['server_id'],
                source_database_name=source['database_name'],
                source_schema_name=source['schema_name'],
                source_object_name=source['object_name'],
                target_server_id=target['server_id'],
                target_database_name=target['database_name'],
                target_schema_name=target['schema_name'],
                target_object_name=target['object_name'],
                source_server_version=source_server_version,
                target_server_version=target_server_version,
                existing_alert_options=existing_alert_options
            )
        elif source['type'] == 'sequence' and target['type'] == 'server-group':
            sql = render_template(
                'alerts/sql/copy_alert/get_target_list.sql',
                source_type=source['type'],
                target_type=target['type'],
                target_group_id=target['group_id'],
                source_server_id=source['server_id'],
                source_database_name=source['database_name'],
                source_schema_name=source['schema_name'],
                source_object_name=source['object_name']
            )
            status, result = pem_conn.execute_dict(sql)

            if not status:
                pem_conn.execute_void("ROLLBACK;")
                return status, result

            sql = render_template(
                'alerts/sql/copy_alert/config.sql',
                source_type=source['type'],
                target_type=target['type'],
                source_server_id=source['server_id'],
                source_database_name=source['database_name'],
                source_schema_name=source['schema_name'],
                source_object_name=source['object_name'],
                source_server_version=source_server_version,
                existing_alert_options=existing_alert_options,
                target_data=result['rows']
            )
        elif source['type'] == 'sequence' and target['type'] == 'server':
            sql = render_template(
                'alerts/sql/copy_alert/'
                'get_target_list.sql',
                source_type=source['type'],
                target_type=target['type'],
                source_server_id=source['server_id'],
                source_database_name=source['database_name'],
                source_schema_name=source['schema_name'],
                source_object_name=source['object_name'],
                target_server_id=target['server_id']
            )

            status, result = pem_conn.execute_dict(sql)

            if not status:
                pem_conn.execute_void("ROLLBACK;")
                return status, result

            sql = render_template(
                'alerts/sql/copy_alert/config.sql',
                source_type=source['type'],
                target_type=target['type'],
                source_server_id=source['server_id'],
                source_database_name=source['database_name'],
                source_schema_name=source['schema_name'],
                source_object_name=source['object_name'],
                target_server_id=target['server_id'],
                source_server_version=source_server_version,
                existing_alert_options=existing_alert_options,
                target_data=result['rows']
            )
        elif source['type'] == 'sequence' and target['type'] == 'database':
            sql = render_template(
                'alerts/sql/copy_alert/get_target_list.sql',
                source_type=source['type'],
                target_type=target['type'],
                source_server_id=source['server_id'],
                source_database_name=source['database_name'],
                source_schema_name=source['schema_name'],
                source_object_name=source['object_name'],
                target_server_id=target['server_id'],
                target_database_name=target['database_name']
            )
            status, result = pem_conn.execute_dict(sql)

            if not status:
                pem_conn.execute_void("ROLLBACK;")
                return status, result

            sql = render_template(
                'alerts/sql/copy_alert/config.sql',
                source_type=source['type'],
                target_type=target['type'],
                source_server_id=source['server_id'],
                source_database_name=source['database_name'],
                source_schema_name=source['schema_name'],
                source_object_name=source['object_name'],
                target_server_id=target['server_id'],
                target_database_name=target['database_name'],
                source_server_version=source_server_version,
                existing_alert_options=existing_alert_options,
                target_data=result['rows']
            )
        elif source['type'] == 'sequence' and target['type'] == 'schema':
            sql = render_template(
                'alerts/sql/copy_alert/get_target_list.sql',
                source_type=source['type'],
                target_type=target['type'],
                source_server_id=source['server_id'],
                source_database_name=source['database_name'],
                source_schema_name=source['schema_name'],
                source_object_name=source['object_name'],
                target_server_id=target['server_id'],
                target_database_name=target['database_name'],
                target_schema_name=target['schema_name']
            )
            status, result = pem_conn.execute_dict(sql)

            if not status:
                pem_conn.execute_void("ROLLBACK;")
                return status, result

            sql = render_template(
                'alerts/sql/copy_alert/config.sql',
                source_type=source['type'],
                target_type=target['type'],
                source_server_id=source['server_id'],
                source_database_name=source['database_name'],
                source_schema_name=source['schema_name'],
                source_object_name=source['object_name'],
                target_server_id=target['server_id'],
                target_database_name=target['database_name'],
                target_schema_name=target['schema_name'],
                source_server_version=source_server_version,
                existing_alert_options=existing_alert_options,
                target_data=result['rows']
            )
        elif source['type'] == 'sequence' and target['type'] == 'sequence':
            # Get the target server version id
            if 'server_id' in target:
                server_ver_id = target['server_id']
                params = [server_ver_id]
                sql = render_template(
                    'alerts/sql/copy_alert/server_version.sql')
                status, result = pem_conn.execute_dict(sql, params)

                if not status:
                    pem_conn.execute_void("ROLLBACK;")
                    return status, result

                target_server_version = result['rows'][0]['server_version_id']

            sql = render_template(
                'alerts/sql/copy_alert/config.sql',
                source_type=source['type'],
                target_type=target['type'],
                source_server_id=source['server_id'],
                source_database_name=source['database_name'],
                source_schema_name=source['schema_name'],
                source_object_name=source['object_name'],
                target_server_id=target['server_id'],
                target_database_name=target['database_name'],
                target_schema_name=target['schema_name'],
                target_object_name=target['object_name'],
                source_server_version=source_server_version,
                target_server_version=target_server_version,
                existing_alert_options=existing_alert_options
            )
        elif source['type'] == 'function' and target['type'] == 'server-group':
            sql = render_template(
                'alerts/sql/copy_alert/get_target_list.sql',
                source_type=source['type'],
                target_type=target['type'],
                target_group_id=target['group_id'],
                source_server_id=source['server_id'],
                source_database_name=source['database_name'],
                source_schema_name=source['schema_name'],
                source_object_name=source['object_name'].split('(', 1)[0]
            )
            status, result = pem_conn.execute_dict(sql)

            if not status:
                pem_conn.execute_void("ROLLBACK;")
                return status, result

            sql = render_template(
                'alerts/sql/copy_alert/config.sql',
                source_type=source['type'],
                target_type=target['type'],
                source_server_id=source['server_id'],
                source_database_name=source['database_name'],
                source_schema_name=source['schema_name'],
                source_object_name=source['object_name'],
                source_server_version=source_server_version,
                existing_alert_options=existing_alert_options,
                target_data=result['rows']
            )
        elif source['type'] == 'function' and target['type'] == 'server':
            sql = render_template(
                'alerts/sql/copy_alert/'
                'get_target_list.sql',
                source_type=source['type'],
                target_type=target['type'],
                source_server_id=source['server_id'],
                source_database_name=source['database_name'],
                source_schema_name=source['schema_name'],
                source_object_name=source['object_name'].split('(', 1)[0],
                target_server_id=target['server_id']
            )
            status, result = pem_conn.execute_dict(sql)

            if not status:
                pem_conn.execute_void("ROLLBACK;")
                return status, result

            sql = render_template(
                'alerts/sql/copy_alert/config.sql',
                source_type=source['type'],
                target_type=target['type'],
                source_server_id=source['server_id'],
                source_database_name=source['database_name'],
                source_schema_name=source['schema_name'],
                source_object_name=source['object_name'],
                target_server_id=target['server_id'],
                source_server_version=source_server_version,
                existing_alert_options=existing_alert_options,
                target_data=result['rows']
            )
        elif source['type'] == 'function' and target['type'] == 'database':
            sql = render_template(
                'alerts/sql/copy_alert/get_target_list.sql',
                source_type=source['type'],
                target_type=target['type'],
                source_server_id=source['server_id'],
                source_database_name=source['database_name'],
                source_schema_name=source['schema_name'],
                source_object_name=source['object_name'].split('(', 1)[0],
                target_server_id=target['server_id'],
                target_database_name=target['database_name']
            )
            status, result = pem_conn.execute_dict(sql)

            if not status:
                pem_conn.execute_void("ROLLBACK;")
                return status, result

            sql = render_template(
                'alerts/sql/copy_alert/config.sql',
                source_type=source['type'],
                target_type=target['type'],
                source_server_id=source['server_id'],
                source_database_name=source['database_name'],
                source_schema_name=source['schema_name'],
                source_object_name=source['object_name'],
                target_server_id=target['server_id'],
                target_database_name=target['database_name'],
                source_server_version=source_server_version,
                existing_alert_options=existing_alert_options,
                target_data=result['rows']
            )
        elif source['type'] == 'function' and target['type'] == 'schema':
            sql = render_template(
                'alerts/sql/copy_alert/get_target_list.sql',
                source_type=source['type'],
                target_type=target['type'],
                source_server_id=source['server_id'],
                source_database_name=source['database_name'],
                source_schema_name=source['schema_name'],
                source_object_name=source['object_name'].split('(', 1)[0],
                target_server_id=target['server_id'],
                target_database_name=target['database_name'],
                target_schema_name=target['schema_name']
            )
            status, result = pem_conn.execute_dict(sql)

            if not status:
                pem_conn.execute_void("ROLLBACK;")
                return status, result

            sql = render_template(
                'alerts/sql/copy_alert/config.sql',
                source_type=source['type'],
                target_type=target['type'],
                source_server_id=source['server_id'],
                source_database_name=source['database_name'],
                source_schema_name=source['schema_name'],
                source_object_name=source['object_name'],
                target_server_id=target['server_id'],
                target_database_name=target['database_name'],
                target_schema_name=target['schema_name'],
                source_server_version=source_server_version,
                existing_alert_options=existing_alert_options,
                target_data=result['rows']
            )
        elif source['type'] == 'function' and target['type'] == 'function':
            # Get the target server version id
            if 'server_id' in target:
                server_ver_id = target['server_id']
                params = [server_ver_id]
                sql = render_template(
                    'alerts/sql/copy_alert/server_version.sql')
                status, result = pem_conn.execute_dict(sql, params)

                if not status:
                    pem_conn.execute_void("ROLLBACK;")
                    return status, result

                target_server_version = result['rows'][0]['server_version_id']

            sql = render_template(
                'alerts/sql/copy_alert/config.sql',
                source_type=source['type'],
                target_type=target['type'],
                source_server_id=source['server_id'],
                source_database_name=source['database_name'],
                source_schema_name=source['schema_name'],
                source_object_name=source['object_name'],
                target_server_id=target['server_id'],
                target_database_name=target['database_name'],
                target_schema_name=target['schema_name'],
                target_object_name=target['object_name'],
                source_server_version=source_server_version,
                target_server_version=target_server_version,
                existing_alert_options=existing_alert_options
            )

        status, result = pem_conn.execute_void(sql)

        if not status:
            pem_conn.execute_void("ROLLBACK;")
            return status, result

    status, result = pem_conn.execute_void("COMMIT;")

    return status, result


def generate_export_alert_data(pem_conn, alert_templates, using_ids=True):
    """
    Allow us to fetch data based on
    :param pem_conn: PEM connection
    :param alert_templates: List of alert templates
    :param using_ids: Flag to switch between id and name
    :return: Dict
    """
    sql = render_template(
        'alerts/sql/custom_alert/list.sql',
        export_alerts=True,
        using_ids=using_ids,
        placeholders=get_sql_placeholders(alert_templates)
    )
    # Execute the query.
    status, result = pem_conn.execute_dict(sql, alert_templates)
    if not status:
        return False, result

    # Format parameter option values
    for row in result['rows']:
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

        if 'low_threshold_value' in row and \
                'medium_threshold_value' in row and \
                'high_threshold_value' in row:
            row['thresholds'] = [
                row['low_threshold_value'],
                row['medium_threshold_value'],
                row['high_threshold_value']
            ]

        # Format probe dependency list
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

            row['probes'] = []
            if len(row['probe_dependency_list']) > 0:
                status, probes = generate_export_probe_data(
                    pem_conn, row['probe_dependency_list'], using_ids=False,
                    show_system=True, deleted=False
                )
                if not status:
                    return False, probes
                # If there is a mismatch in probe result then error out
                if len(probes) != len(row['probe_dependency_list']):
                    d_probes = ", ".join(
                        [name_mapping.get(p, '')
                         for p in row['probe_dependency_list']]
                    )
                    if len(probes) == 1:
                        msg = gettext(
                            "The dependant probe '{}' has been "
                            "deleted or not found for the '{}' alert "
                            "template".format(d_probes, row['name']))
                    else:
                        msg = gettext(
                            "Some of the dependant probe(s) "
                            "has been deleted or not found for the '{}' "
                            "alert template".format(row['name']))
                    return False, msg

                row['probes'] = probes
        row['probe_dependency_list'] = param_options

    return True, result['rows']


def fetch_agents(pem_conn=None):
    """ This function will return the dict of agents and groups """
    res = {}
    try:
        sql = render_template('alerts/sql/blackout/get_agents.sql')
        status, result = pem_conn.execute_dict(sql)
        # Add Servers menu (only if any agents exists)
        if len(result['rows']) > 0:
            for row in result['rows']:
                agent_info = {
                    "value": row['agent_id'],
                    "label": row['agent_name'],
                    "image": 'icon-agent',
                    "servers": row['servers'],
                    "_id": row['agent_id'],
                    "type": "agent"
                }
                group = row['server_group_name']
                if group in res:
                    res[group].append(agent_info)
                else:
                    res[group] = [agent_info]
    except Exception as e:
        current_app.logger.exception(e)
    return res


def fetch_servers():
    """ This function will return the dict of servers and server groups """
    res = {}
    try:
        """Return a JSON document listing the server groups for the user"""
        for server in Server.all():
            server_info = {
                "value": server.id,
                "label": server.name,
                "image": 'icon-server-not-connected',
                "_id": server.id,
                "type": "server"
            }

            if server.server_group_name in res:
                res[server.server_group_name].append(server_info)
            else:
                res[server.server_group_name] = [server_info]

    except Exception as e:
        current_app.logger.exception(e)
    return res
