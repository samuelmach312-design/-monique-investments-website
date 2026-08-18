##########################################################################
#
# Postgres Enterprise Manager
#
# Copyright (C) 2016 - 2025, EnterpriseDB Corporation. All rights reserved.
#
##########################################################################

"""
Alerts Utility Module for Manage Profiles.

This file contains helper functions specifically related to alert
configurations within the 'Manage Profiles' feature. It is imported
by 'utils.py' to handle the alert-specific parts of saving and
managing profiles.

Key responsibilities include:
- `prepare_add_alert_data`: Validating and transforming raw alert
  configuration data (often from the UI) into a clean, database-ready
  dictionary.
- `validate_webhook_ids`: Querying the database to ensure selected
  webhook IDs are valid and exist.
- `validate_param_value`: Ensuring alert parameter values match their
  expected data types (e.g., BOOL, INTEGER).
- `assign_profile_alerts_to_agent`: Handling the business logic for
  applying an alert profile to a specific agent.
- `assign_profile_alerts_to_server`: Handling the business logic for
  applying an alert profile to a specific server.
"""


from flask import current_app
from flask_babel import gettext
import datetime


class AlertProfileError(RuntimeError):
    """Domain-specific error for alert profile assignment operations."""
    def __init__(self, message):
        super().__init__(message)


VALID_CONFIG_VAL_MSG = gettext("Provide valid value for {0}.")


def validate_webhook_ids(data, pem_conn=None):
    """
    This function will check whether webhook ids(low/medium/high/cleared)
    are valid or not.
    :param data: Alert data to be updated in table.
    """

    # Check for valid webhook ids
    sql = "SELECT UNNEST(ARRAY[{0}]::integer[]) EXCEPT SELECT DISTINCT id " \
          "FROM pem.webhook_endpoints".format(data)
    status, res = pem_conn.execute_dict(sql)
    if not status:
        current_app.logger.error(str(res))
        return False, res
    # if result is empty, all passed ids are valid
    if res and len(res['rows']) > 0:
        invalid_ids = ','.join([str(r['unnest']) for r in res['rows']])
        return False, gettext("Webhook ids {0} not valid.").format(invalid_ids)

    return True, None


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
    except (ValueError, TypeError) as e:
        current_app.logger.debug(
            "Parameter validation failed: %s", e)
        return False, "Invalid parameter value passed"
    return True, None


def prepare_add_alert_data(alert_data, pem_conn=None):

    data = dict()
    status = False

    # Assign default parameters value
    data['send_email'] = False
    data['flapping_detected'] = False
    data['last_flapping_detection_processed'] = datetime.datetime.now()

    if 'alert_id' in alert_data:
        data['id'] = alert_data['alert_id']

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

        data['thresholds'] = [str(alert_data['low_threshold_value']),
                              str(alert_data['medium_threshold_value']),
                              str(alert_data['high_threshold_value'])]

    if 'override_default_config' in alert_data:
        data['override_default_config'] = alert_data['override_default_config']
        if 'send_notification' in alert_data:
            data['send_notification'] = alert_data['send_notification']
        else:
            data['send_notification'] = True

        if 'low_webhook_ids' in alert_data:
            if not isinstance(alert_data['low_webhook_ids'], list) or \
                (any(not isinstance(x, int) for x in
                     alert_data['low_webhook_ids'])):
                return False, VALID_CONFIG_VAL_MSG.format("low_webhook_ids")
            status, res = validate_webhook_ids(alert_data['low_webhook_ids'],
                                               pem_conn)
            if not status:
                return False, res
            data['low_webhook_ids'] = alert_data['low_webhook_ids']
        else:
            data['low_webhook_ids'] = []

        if 'med_webhook_ids' in alert_data:
            if not isinstance(alert_data['med_webhook_ids'], list) or \
               (any(not isinstance(x, int) for x in
                    alert_data['med_webhook_ids'])):
                return False, VALID_CONFIG_VAL_MSG.format("med_webhook_ids")
            status, res = validate_webhook_ids(alert_data['med_webhook_ids'],
                                               pem_conn)
            if not status:
                return False, res
            data['med_webhook_ids'] = alert_data['med_webhook_ids']
        else:
            data['med_webhook_ids'] = []

        if 'high_webhook_ids' in alert_data:
            if not isinstance(alert_data['high_webhook_ids'], list) or \
               (any(not isinstance(x, int) for x in
                    alert_data['high_webhook_ids'])):
                return False, VALID_CONFIG_VAL_MSG.format("high_webhook_ids")
            status, res = validate_webhook_ids(alert_data['high_webhook_ids'],
                                               pem_conn)
            if not status:
                return False, res
            data['high_webhook_ids'] = alert_data['high_webhook_ids']
        else:
            data['high_webhook_ids'] = []

        if 'cleared_webhook_ids' in alert_data:
            if not isinstance(alert_data['cleared_webhook_ids'], list) or \
                    (any(not isinstance(x, int) for x in
                         alert_data['cleared_webhook_ids'])):
                return False, VALID_CONFIG_VAL_MSG.format(
                    "cleared_webhook_ids"
                )
            status, res = validate_webhook_ids(
                alert_data['cleared_webhook_ids'], pem_conn
            )
            if not status:
                return False, res
            data['cleared_webhook_ids'] = alert_data['cleared_webhook_ids']
        else:
            data['cleared_webhook_ids'] = []

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
        data['high_email_group_id'] = None

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

    return True, data


def assign_profile_alerts_to_agent(agent_id, pem_conn=None, data=None):
    """Assigns or unassigns a profile for an agent."""

    # ID to assign, or None to unassign
    new_profile_id = data.get('profile_id')
    response_msg = ""
    status = True
    try:
        # Start transaction for link update
        pem_conn.execute_void("BEGIN")

        if new_profile_id is not None:
            # Assigning a profile
            status, apply_res = pem_conn.execute_scalar(
                (
                    "SELECT pem.apply_alert_profile_to_target("
                    "%(pid)s, 'agent', %(tid)s)"
                ),
                {'pid': new_profile_id, 'tid': agent_id}
            )
            if not status:
                raise AlertProfileError(str(apply_res))
            response_msg = gettext("Alert profile applied successfully.")
        else:
            # Unassigning a profile (link removal only)
            response_msg = gettext(
                "Profile unassigned. Existing alerts remain unchanged.")

        pem_conn.execute_void("COMMIT")
    except (AlertProfileError, RuntimeError) as e:
        pem_conn.execute_void("ROLLBACK")
        current_app.logger.error(
            "Error assigning alert profile to agent %s: %s", agent_id, e)
        status = False
        response_msg = str(e)

    return status, response_msg


def assign_profile_alerts_to_server(server_id, pem_conn=None, data=None):
    """Assigns or unassigns a profile for a server."""

    # ID to assign, or None to unassign
    new_profile_id = data.get('profile_id')
    response_msg = ""
    status = True
    try:
        # Start transaction for link update
        pem_conn.execute_void("BEGIN")

        if new_profile_id is not None:
            status, apply_res = pem_conn.execute_scalar(
                (
                    "SELECT pem.apply_alert_profile_to_target("
                    "%(pid)s, 'server', %(tid)s)"
                ),
                {'pid': new_profile_id, 'tid': server_id}
            )
            if not status:
                raise AlertProfileError(str(apply_res))
            response_msg = gettext("Alert profile applied successfully.")
        else:
            response_msg = gettext(
                "Profile unassigned. Existing alerts remain unchanged.")

        pem_conn.execute_void("COMMIT")
    except (AlertProfileError, RuntimeError) as e:
        pem_conn.execute_void("ROLLBACK")
        current_app.logger.error(
            "Error assigning alert profile to server %s: %s", server_id, e)
        status = False
        response_msg = str(e)

    return status, response_msg
