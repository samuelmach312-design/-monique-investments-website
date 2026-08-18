##########################################################################
#
# Postgres Enterprise Manager
#
# Copyright (C) 2016 - 2025, EnterpriseDB Corporation. All rights reserved.
#
##########################################################################

"""Probe Utilities"""
import json
import re
from functools import reduce

from flask import render_template, current_app
from flask_babel import gettext
from pgadmin.pem.monitor.utils import DashboardLevel
from pgadmin.pem.utils import is_agent_exists, is_object_exists, \
    is_server_group_exists, get_sql_placeholders
from pgadmin.pem.utils.role import PEMRole

valid_target_type = [100, 200, 300, 400, 500, 600, 700, 800, 900, 1000]
PROBE_LIST_SQL = 'probes/sql/custom_probe/probe_list.sql'

configProbeRole = PEMRole(
    'pem_config_probe', gettext('Probe configuration'),
    gettext('Probe configuration'),
    gettext(
        'Privilege to modify the probe configuration (i.e. execution '
        'frequency, enable/disable a probe, data history retention period) '
        ' for the monitored objects.'
    )
)

manageProbeRole = PEMRole(
    'pem_manage_probe', gettext('Probe management'),
    gettext('Probe management'),
    gettext(
        'Privilege to configure a probe same as pem_config_probe, and '
        'create/remove/modify a custom probe.'
    )
)


def get_extensions(pem_conn):
    sql = """SELECT DISTINCT extension_name
    FROM pemdata.oc_extension ORDER BY 1"""
    status, res = pem_conn.execute_dict(sql)
    if not status:
        return False, []

    data = []
    for row in res['rows']:
        data.append(row['extension_name'])
    return True, data


def check_config_parameters(data):
    """
    This function will check the parameter is correct and
    it's value is valid.

    :param data: Data to be validate
    :return:
    """

    if 'interval_min' in data:
        if data['interval_min'] is None \
                or not isinstance(data['interval_min'], int):
            return gettext("Provide valid value of Interval in minute.")
        try:
            minute = int(data['interval_min'])
        except ValueError:
            return gettext("Interval in minute must be integer.")

        if minute < 0 or minute > 2880:
            return gettext("Valid range for interval in minute is 0-2880.")

    if 'interval_sec' in data:
        if data['interval_sec'] is None \
                or not isinstance(data['interval_sec'], int):
            return gettext("Provide valid value of Interval in seconds.")
        try:
            seconds = int(data['interval_sec'])
        except ValueError:
            return gettext("Interval in seconds must be integer.")

        if seconds < 0 or seconds > 59:
            return gettext("Valid range for interval in seconds is 0-59.")

    if 'lifetime' in data:
        if data['lifetime'] is None or not (
            isinstance(data['lifetime'], int) or
            (isinstance(data['lifetime'], str) and data['lifetime'].isdigit())
        ):
            return gettext("Provide valid value of lifetime.")
        try:
            lifetime = int(data['lifetime'])
        except ValueError:
            return gettext("lifetime must be integer.")

        if lifetime <= 0 or lifetime > 365:
            return gettext("Valid range for lifetime is 1-365.")

    if 'enabled' in data:
        if data['enabled'] is None or not isinstance(data['enabled'], bool):
            return gettext("Provide valid value of probe enabled.")

    return None


def get_probes(
    target_type_id, object_id=None, database_name=None, schema_name=None,
    object_name=None, pem_conn=None, probe_id=None
):
    """
    This function will return the list of probes.

    :param target_type_id: target type id.
    :param object_id: Agent/Server id.
    :param database_name: database name.
    :param schema_name: schema name.
    :param object_name: Table/Index/Function/View/Procedure name.
    :param pem_conn: PEM Connection object
    :param probe_id: Probe ID
    """

    params = {
        'target_id': target_type_id
    }
    parameters = ''
    extension_name = None

    # Create the IN clause for the sql query to fetch the probe list
    if target_type_id == DashboardLevel.DB_AGENT:  # Agent
        params['agent_params'] = [str(object_id)]
        parameters = '%(agent_params)s'
    elif target_type_id == DashboardLevel.DB_SERVER:  # Server
        params['server_params'] = [str(object_id)]
        parameters = '%(server_params)s'
    elif target_type_id == DashboardLevel.DB_DATABASE:  # Database
        params['server_params'] = [str(object_id)]
        params['database_params'] = [
            str(object_id), str(database_name)
        ]
        parameters = '%(server_params)s, %(database_params)s'
    elif target_type_id == DashboardLevel.DB_EXTENSION:  # Extension
        params['server_params'] = [str(object_id)]
        params['database_params'] = [
            str(object_id), str(database_name)
        ]
        extension_name = str(schema_name)
        parameters = '%(server_params)s, %(database_params)s'
    elif target_type_id == DashboardLevel.DB_SCHEMA:  # Schema
        params['server_params'] = [str(object_id)]
        params['database_params'] = [
            str(object_id), str(database_name)
        ]
        params['schema_params'] = [
            str(object_id), str(database_name),
            str(schema_name)
        ]
        parameters = \
            '%(server_params)s, %(database_params)s, %(schema_params)s'
    # Table Index Sequence Function View
    elif target_type_id == DashboardLevel.DB_TABLE \
        or target_type_id == DashboardLevel.DB_INDEX \
        or target_type_id == DashboardLevel.DB_SEQUENCE \
        or target_type_id == DashboardLevel.DB_FUNCTION \
            or target_type_id == DashboardLevel.DB_VIEW:
        params['server_params'] = [str(object_id)]
        params['database_params'] = [
            str(object_id), str(database_name)
        ]
        params['schema_params'] = [
            str(object_id), str(database_name),
            str(schema_name)
        ]
        params['object_params'] = [
            str(object_id), str(database_name),
            str(schema_name), str(object_name)
        ]
        parameters = '%(server_params)s, %(database_params)s, ' \
                     '%(schema_params)s, %(object_params)s'

    if probe_id is not None:
        params['probe_id'] = probe_id

        sql = render_template('probes/sql/probes/list.sql',
                              parameters=parameters, probe_id=probe_id,
                              extension_name=extension_name, conn=pem_conn)
    else:
        sql = render_template('probes/sql/probes/list.sql',
                              parameters=parameters,
                              extension_name=extension_name, conn=pem_conn)

    # Execute the query.
    status, probes = pem_conn.execute_dict(sql, params)

    return status, probes


def save_probes(change_probe_data, pem_conn):
    """
    This function will save the changed probe configuration.

    :param change_probe_data: Changed Probe Data.
    :param pem_conn: PEM Connection object
    :return:
    """

    node_info = change_probe_data[0]
    probe_info = change_probe_data[1]
    changed_column = change_probe_data[2]

    target_type = node_info['target_type']
    target_type_id = int(node_info['target_type_id'])
    probe_id = int(probe_info['probe_id'])

    params = {
        'probe_id': probe_id
    }
    server_id = ''
    database_name = ''
    schema_name = ''
    extension_name = ''
    object_name = ''
    where_clause = ''
    insert_column_list = '('
    insert_value_list = '('

    error_message = check_config_parameters(changed_column)
    if error_message:
        return False, error_message

    # Create the IN clause for the sql query to fetch the probe list
    if target_type_id == DashboardLevel.DB_AGENT:  # Agent
        agent_id = int(node_info['agent_id'])
        where_clause = 'agent_id = %(agent_id)s::int4'
        insert_column_list += 'agent_id'
        insert_value_list += '%(agent_id)s::int4'
        params['agent_id'] = agent_id
    elif target_type_id == DashboardLevel.DB_SERVER:  # Server
        server_id = int(node_info['server_id'])
    elif target_type_id == DashboardLevel.DB_DATABASE:  # Database
        server_id = int(node_info['server_id'])
        database_name = node_info['database_name']
    elif target_type_id == DashboardLevel.DB_EXTENSION:  # Extension
        server_id = int(node_info['server_id'])
        database_name = node_info['database_name']
        extension_name = node_info['extension_name']
    elif target_type_id == DashboardLevel.DB_SCHEMA:  # Schema
        server_id = int(node_info['server_id'])
        database_name = node_info['database_name']
        schema_name = node_info['schema_name']
    # Table Index Sequence Function View
    elif target_type_id == DashboardLevel.DB_TABLE \
        or target_type_id == DashboardLevel.DB_INDEX \
        or target_type_id == DashboardLevel.DB_SEQUENCE \
        or target_type_id == DashboardLevel.DB_FUNCTION \
            or target_type_id == DashboardLevel.DB_VIEW:
        server_id = int(node_info['server_id'])
        database_name = node_info['database_name']
        schema_name = node_info['schema_name']
        object_name = node_info['object_name']

    if server_id != '':
        where_clause = 'server_id = %(server_id)s::int4'
        insert_column_list += 'server_id'
        insert_value_list += '%(server_id)s::int4'
        params['server_id'] = server_id
    if database_name != '':
        where_clause += ' AND database_name = %(database_name)s::text'
        insert_column_list += ', database_name'
        insert_value_list += ', %(database_name)s::text'
        params['database_name'] = database_name
    if extension_name != '':
        where_clause += ' AND extension_name = %(extension_name)s::text'
        insert_column_list += ', extension_name'
        insert_value_list += ', %(extension_name)s::text'
        params['extension_name'] = extension_name
    if schema_name != '':
        where_clause += ' AND schema_name = %(schema_name)s::text'
        insert_column_list += ', schema_name'
        insert_value_list += ', %(schema_name)s::text'
        params['schema_name'] = schema_name
    if object_name != '':
        where_clause += ' AND ' + target_type + '_name = %(target_type)s::text'
        insert_column_list += ', ' + target_type + '_name'
        insert_value_list += ', %(target_type)s::text'
        params['target_type'] = object_name

    where_clause += ' AND probe_id = %(probe_id)s::int4'

    # If there is no change while comparing with default value
    # then we may need to delete entry from the respective table.
    if (
        int(probe_info['default_interval_min']) ==
        int(probe_info['interval_min']) and
        int(probe_info['default_interval_sec']) ==
        int(probe_info['interval_sec']) and
        probe_info['default_enabled'] == probe_info['enabled'] and
        int(probe_info['default_lifetime']) == int(probe_info['lifetime'])
    ):
        delete_sql = render_template(
            'probes/sql/probes/save.sql',
            delete_probe=True, target_type=target_type,
            where_clause=where_clause
        )

        status, result = pem_conn.execute_void(delete_sql, params)
        if not status:
            return status, result
    else:
        # If we comes here then it is an INSERT or UPDATE query.
        update_clause = ' SET '

        # If change in the interval then convert it into interval
        if 'interval_min' in changed_column or \
                'interval_sec' in changed_column:
            interval = \
                int(probe_info['interval_min']) * \
                60 + int(probe_info['interval_sec'])
            insert_column_list += ', probe_id, execution_frequency)'
            insert_value_list += \
                ', %(probe_id)s::int4, %(execution_frequency)s::int4)'
            update_clause += \
                ' execution_frequency = %(execution_frequency)s::int4'
            params['execution_frequency'] = interval
        elif 'enabled' in changed_column:
            insert_column_list += ', probe_id, enabled)'
            insert_value_list += ', %(probe_id)s::int4, %(enabled)s::boolean)'
            update_clause += ' enabled = %(enabled)s::boolean'
            params['enabled'] = probe_info['enabled']
        elif 'lifetime' in changed_column:
            insert_column_list += ', probe_id, lifetime)'
            insert_value_list += ', %(probe_id)s::int4, %(lifetime)s::int4)'
            update_clause += ' lifetime = %(lifetime)s::int4'
            params['lifetime'] = int(probe_info['lifetime'])
        else:
            return True, ''

        # Check whether entry is already exist in table or not
        sql = render_template('probes/sql/probes/save.sql',
                              check_probe=True, target_type=target_type,
                              where_clause=where_clause)
        status, result = pem_conn.execute_scalar(sql, params)
        if not status:
            return status, result

        if result is None:
            sql = render_template('probes/sql/probes/save.sql',
                                  insert_probe=True, target_type=target_type,
                                  insert_column_list=insert_column_list,
                                  insert_value_list=insert_value_list)
        else:
            sql = render_template('probes/sql/probes/save.sql',
                                  update_probe=True, target_type=target_type,
                                  update_clause=update_clause,
                                  where_clause=where_clause)

        status, result = pem_conn.execute_void(sql, params)
        if not status:
            return status, result

    return status, result


def check_copy_parameters(source, targets, pem_conn):
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
            and source['type'] != 'database' and source['type'] != 'schema':
        return gettext("Source type not supported.")

    for target in targets:
        if 'type' not in target:
            return gettext("Target type for copy not provided.")
        elif target['type'] != 'agent' and target['type'] != 'server-group'\
            and target['type'] != 'server' and \
            target['type'] != 'database' and \
                target['type'] != 'schema':
            return gettext("Target type not supported.")

        if source['type'] == 'agent' and target['type'] == 'server-group':
            if 'agent_id' not in source:
                return gettext("Source agent id is not provided.")
            elif 'group_id' not in target:
                return gettext("Target group id is not provided.")

            # Check target group exists or not.
            group_exist = is_server_group_exists(pem_conn,
                                                 target['group_id'])
            if not group_exist:
                return gettext("The specified target group not found!")

        elif source['type'] == 'agent' and target['type'] == 'agent':
            if 'agent_id' not in source:
                return gettext("Source agent id is not provided.")
            elif 'agent_id' not in target:
                return gettext("Target agent id is not provided.")

            # Check target agent is exist or not.
            agent_exist = is_agent_exists(pem_conn, target['agent_id'])
            if not agent_exist:
                return gettext("The specified target agent not found!")

            if source['agent_id'] == target["agent_id"]:
                return gettext("Specified source and target is same.")

        elif source['type'] == 'server' and target['type'] == 'server-group':
            if 'server_id' not in source:
                return gettext("Source server id is not provided.")
            elif 'group_id' not in target:
                return gettext("Target group id is not provided.")

            # Check target agent is exist or not.
            group_exist = is_server_group_exists(pem_conn, target['group_id'])
            if not group_exist:
                return gettext("The specified target group not found!")

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
                return gettext("Target group id is not provided.")

            # Check target agent is exist or not.
            group_exist = is_server_group_exists(pem_conn, target['group_id'])
            if not group_exist:
                return gettext("The specified target group not found!")

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
                    "The specified target server or database not found!"
                )

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
                return gettext("Target group id is not provided.")

            # Check target agent is exist or not.
            group_exist = is_server_group_exists(pem_conn, target['group_id'])
            if not group_exist:
                return gettext("The specified target group not found!")

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
                    "The specified target server or database not found!"
                )

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

        else:
            return gettext("Please verify source type and target type for "
                           "copy probe configuration.")
    return None


def copy_probes(source, targets, show_sys_obj, pem_conn):
    """
    This function is used to copy the probe configuration from
    source objects to multiple target objects.

    :param source: Source object.
    :param targets: Multiple target objects.
    :param show_sys_obj: Value of Show System Objects.
    :param pem_conn: PEM Connection.
    :return:
    """

    # Check whether all the required parameter is present and valid.
    error_msg = check_copy_parameters(source, targets, pem_conn)
    if error_msg is not None:
        return False, error_msg

    status, result = pem_conn.execute_void("BEGIN;")
    if not status:
        return status, result

    for target in targets:
        sql = ''
        if source['type'] == 'agent' and target['type'] == 'server-group':
            sql = render_template('probes/sql/copy_probe/config.sql',
                                  source_type=source['type'],
                                  target_type=target['type'],
                                  source_agent_id=source['agent_id'],
                                  target_group_id=target['group_id']
                                  )
        elif source['type'] == 'agent' and target['type'] == 'agent':
            sql = render_template('probes/sql/copy_probe/config.sql',
                                  source_type=source['type'],
                                  target_type=target['type'],
                                  source_agent_id=source['agent_id'],
                                  target_agent_id=target['agent_id']
                                  )
        elif source['type'] == 'server' and target['type'] == 'server-group':
            sql = render_template('probes/sql/copy_probe/config.sql',
                                  source_type=source['type'],
                                  target_type=target['type'],
                                  target_group_id=target['group_id'],
                                  source_server_id=source['server_id']
                                  )
        elif source['type'] == 'server' and target['type'] == 'server':
            sql = render_template('probes/sql/copy_probe/config.sql',
                                  source_type=source['type'],
                                  target_type=target['type'],
                                  source_server_id=source['server_id'],
                                  target_server_id=target['server_id']
                                  )
        elif source['type'] == 'database' and target['type'] == 'server-group':
            sql = render_template('probes/sql/copy_probe/config.sql',
                                  source_type=source['type'],
                                  target_type=target['type'],
                                  target_group_id=target['group_id'],
                                  source_server_id=source['server_id'],
                                  source_database_name=source['database_name']
                                  )
        elif source['type'] == 'database' and target['type'] == 'server':
            sql = render_template('probes/sql/copy_probe/config.sql',
                                  source_type=source['type'],
                                  target_type=target['type'],
                                  source_server_id=source['server_id'],
                                  source_database_name=source['database_name'],
                                  target_server_id=target['server_id']
                                  )
        elif source['type'] == 'database' and target['type'] == 'database':
            sql = render_template('probes/sql/copy_probe/config.sql',
                                  source_type=source['type'],
                                  target_type=target['type'],
                                  source_server_id=source['server_id'],
                                  source_database_name=source['database_name'],
                                  target_server_id=target['server_id'],
                                  target_database_name=target['database_name']
                                  )
        elif source['type'] == 'schema' and target['type'] == 'server-group':
            sql = render_template('probes/sql/copy_probe/config.sql',
                                  source_type=source['type'],
                                  target_type=target['type'],
                                  target_group_id=target['group_id'],
                                  source_server_id=source['server_id'],
                                  source_database_name=source['database_name'],
                                  source_schema_name=source['schema_name'],
                                  show_system_object=show_sys_obj
                                  )
        elif source['type'] == 'schema' and target['type'] == 'server':
            sql = render_template('probes/sql/copy_probe/config.sql',
                                  source_type=source['type'],
                                  target_type=target['type'],
                                  source_server_id=source['server_id'],
                                  source_database_name=source['database_name'],
                                  source_schema_name=source['schema_name'],
                                  target_server_id=target['server_id'],
                                  show_system_object=show_sys_obj
                                  )
        elif source['type'] == 'schema' and target['type'] == 'database':
            sql = render_template('probes/sql/copy_probe/config.sql',
                                  source_type=source['type'],
                                  target_type=target['type'],
                                  source_server_id=source['server_id'],
                                  source_database_name=source['database_name'],
                                  source_schema_name=source['schema_name'],
                                  target_server_id=target['server_id'],
                                  target_database_name=target['database_name'],
                                  show_system_object=show_sys_obj
                                  )
        elif source['type'] == 'schema' and target['type'] == 'schema':
            sql = render_template('probes/sql/copy_probe/config.sql',
                                  source_type=source['type'],
                                  target_type=target['type'],
                                  source_server_id=source['server_id'],
                                  source_database_name=source['database_name'],
                                  source_schema_name=source['schema_name'],
                                  target_server_id=target['server_id'],
                                  target_database_name=target['database_name'],
                                  target_schema_name=target['schema_name']
                                  )
        status, result = pem_conn.execute_void(sql)

        if not status:
            pem_conn.execute_void("ROLLBACK;")
            return status, result

    status, result = pem_conn.execute_void("COMMIT;")

    return status, result


def get_custom_probes(
    show_system_probe, pem_conn, probe_id=None, share_level=False
):
    """
    This function will return the list of all the probes
    including system and custom.

    :param show_system_probe: True or False
    :param pem_conn: PEM Connection object.
    :param probe_id: Get probe information for this probe id.
    """

    params = {}
    if probe_id is not None:
        params['probe_id'] = probe_id
        sql = render_template(
            PROBE_LIST_SQL,
            probe_id=probe_id,
            share_level=share_level
        )
    else:
        params['show_system_probe'] = show_system_probe
        sql = render_template(
            PROBE_LIST_SQL,
            show_system_probe=show_system_probe,
            share_level=share_level
        )

    # Execute the query.
    status, probes = pem_conn.execute_dict(sql, params)
    if not status:
        return status, probes

    probes = reduce(serialize_probe_cols, probes.get('rows', []), [])

    return True, {'custom_probes': probes}


def get_internal_name(name):
    """
    This function is used to get the internal name
    for the specified given name.

    :param name: Name for which internal name is required.
    """
    int_name = name
    int_name = re.sub(r'[^\w]', ' ', int_name)
    int_name = int_name.strip()
    int_name = re.sub(r'\s+', '_', int_name)
    int_name = int_name.lower()

    return int_name


def check_probe_parameters(probe_data, pem_schema_version=None):
    """
    This function is used to verify all the parameters required
    to insert data into pem.probe table will be passed or not.

    :param probe_data: Data to be insert in pem.probe table.
    :param pem_schema_version: PEM schema version
    :return:
    """
    if 'probe_name' not in probe_data:
        return gettext("Probe name not supplied.")

    if 'collection_method' not in probe_data:
        return gettext("Collection method not supplied.")
    elif probe_data['collection_method'] != 's' \
        and probe_data['collection_method'] != 'w' \
            and probe_data['collection_method'] != 'b':
        return gettext("Collection method should be ('s', 'w' or 'b').")

    if 'target_type' not in probe_data:
        return gettext("Target type not supplied.")
    else:
        if int(probe_data['target_type']) not in valid_target_type:
            return gettext("Provide valid target type.")

    if 'enabled' not in probe_data:
        return gettext("Enabled status not supplied.")
    else:
        if probe_data['enabled'] is None \
                or not isinstance(probe_data['enabled'], bool):
            return gettext("Provide valid value of probe enabled.")

    if 'interval' not in probe_data:
        return gettext("Default execution frequency not supplied.")
    else:
        if probe_data['interval'] is None \
                or not isinstance(probe_data['interval'], int):
            return gettext("Provide valid value of interval.")
        if probe_data['interval'] < 10:
            return gettext("Interval cannot be less than 10 seconds.")
        try:
            int(probe_data['interval'])
        except ValueError:
            return gettext("interval must be integer.")

    if 'lifetime' not in probe_data:
        return gettext("Default life time not supplied.")
    else:
        if probe_data['lifetime'] is None \
                or not isinstance(probe_data['lifetime'], int):
            return gettext("Provide valid value of lifetime.")
        try:
            lifetime = int(probe_data['lifetime'])
        except ValueError:
            return gettext("lifetime must be integer.")

        if lifetime <= 0 or lifetime > 365:
            return gettext("Valid range for lifetime is 1-365.")

    if 'any_server_version' not in probe_data:
        return gettext("Value for any server version not supplied.")
    else:
        if probe_data['any_server_version'] is None \
                or not isinstance(probe_data['any_server_version'], bool):
            return gettext("Provide valid value of any server version")
        elif probe_data['any_server_version'] is False:
            if 'alternate_code' not in probe_data:
                return gettext("Alternate code not supplied")

    if int(pem_schema_version) >= 202112021:
        if 'any_extension_version' not in probe_data:
            return gettext("Value for any extension version not supplied.")
        else:
            if probe_data['any_extension_version'] is None or \
                    not isinstance(probe_data['any_extension_version'], bool):
                return gettext("Provide valid value of any extension version")
            elif probe_data['any_extension_version'] is False:
                if 'alternate_code' not in probe_data:
                    return gettext("Alternate code not supplied")
        if int(probe_data['target_type']) == int(DashboardLevel.DB_EXTENSION) \
            and ('extension_name' not in probe_data or
                 probe_data['extension_name'] is None):
            return gettext("Value for extension name not supplied.")

    if 'probe_code' not in probe_data:
        return gettext("Probe Code not supplied.")

    if 'discard_history' not in probe_data:
        return gettext("Value for discard history not supplied.")
    else:
        if probe_data['discard_history'] is None \
                or not isinstance(probe_data['discard_history'], bool):
            return gettext("Provide valid value of discard history")

    if 'platform' not in probe_data:
        return gettext("Platform not supplied.")
    else:
        # If platform is '*nix' then we will store 'unix' in database
        if probe_data['platform'] == '*nix':
            probe_data['platform'] = 'unix'

        if probe_data['platform'] != 'unix' \
                and probe_data['platform'] != 'windows':
            return gettext("Provide valid platform.")

    return None


def insert_probe(probe_data, pem_conn):
    """

    :param probe_data:
    :param pem_conn:
    """
    # Fetch PEM schema version
    status, pem_schema_version = pem_conn.execute_scalar(
        'select pem.schema_version();'
    )
    if not status:
        return status, pem_schema_version

    # Check whether all the required parameter is present and valid.
    error_msg = check_probe_parameters(probe_data, pem_schema_version)
    if error_msg is not None:
        return False, error_msg

    status = True
    probe_id = None

    # Insert into pem.probe table
    if len(probe_data) > 0:
        # Get the next serial value in pem.probe table
        sql = """SELECT nextval(pg_get_serial_sequence('pem.probe', 'id'))
            as new_probe_id; """

        status, new_probe_id = pem_conn.execute_scalar(sql)
        if not status:
            return status, new_probe_id

        # If we are importing then we already have internal_name, so use it
        if 'internal_name' in probe_data:
            probe_internal_name = probe_data['internal_name']
        else:
            # Internal name for probe
            if int(pem_schema_version) >= 202107221:
                sql = "SELECT pem.system_uid();"
                status, pem_uid = pem_conn.execute_scalar(sql)
                if not status:
                    return status, pem_uid
                probe_internal_name = 'probe_{0}_{1}'.format(
                    pem_uid, new_probe_id)
            else:
                # Fallback to old style if PEM is not upgraded
                probe_internal_name = 'cp_{0}'.format(new_probe_id)

        platform = ''
        if probe_data['collection_method'] == 'b':
            platform = probe_data['platform']
        elif probe_data['collection_method'] == 'w':
            platform = 'windows'

        if probe_data['collection_method'] != 's' \
                and int(probe_data['target_type']) != DashboardLevel.DB_AGENT:
            return False, "Target type must be agent for WMI/BATCH/SHELL."

        target_type = DashboardLevel.DB_DATABASE
        # If probe is extension level then do not set it to database level
        if int(pem_schema_version) >= 202112021 and \
                int(probe_data['target_type']) == DashboardLevel.DB_EXTENSION:
            target_type = DashboardLevel.DB_EXTENSION
            if 'extension_name' not in probe_data or 'any_extension_version' \
                    not in probe_data:
                return False, "extension_name or any_extension_version not " \
                              "supplied "
            elif 'extension_name' in probe_data:
                status, extension_res = get_extensions(pem_conn)
                if probe_data['extension_name'] not in extension_res:
                    return False, "Supply valid extension name"

        elif int(probe_data['target_type']) < target_type:
            target_type = int(probe_data['target_type'])

        # by default any_extension_version 'true' if target type is not
        # extension
        if 'any_extension_version' in probe_data and\
                int(probe_data['target_type']) != DashboardLevel.DB_EXTENSION:
            probe_data['any_extension_version'] = True
        elif probe_data['target_type'] == DashboardLevel.DB_EXTENSION:
            probe_data['any_server_version'] = True

        # Add Extension name and any extension version value are supported
        # only if new schema is present
        mapped_data = {
            'id': new_probe_id,
            'display_name': probe_data.get('probe_name'),
            'internal_name': probe_internal_name,
            'collection_method': probe_data.get('collection_method'),
            'target_type_id': target_type,
            'enabled_by_default': probe_data.get('enabled'),
            'default_execution_frequency': probe_data.get('interval'),
            'default_lifetime': probe_data.get('lifetime'),
            'any_server_version': probe_data.get('any_server_version'),
            'probe_code': probe_data.get('probe_code'),
            'discard_history': probe_data.get('discard_history'),
            'platform': probe_data.get('platform')
            # Default to empty string if platform is not provided
        }
        if int(pem_schema_version) >= 202112021:
            mapped_data['any_extension_version'] = probe_data[
                'any_extension_version']
            mapped_data['extension_name'] = probe_data[
                'extension_name']
            sql = render_template(
                'probes/sql/custom_probe/insert.sql',
                insert_probe=True)
        else:
            sql = render_template(
                'probes/sql/custom_probe/insert.sql',
                insert_probe=True)

        status, probe_id = pem_conn.execute_scalar(sql, mapped_data)

    return status, probe_id


def check_probe_column_parameters(columns_data):
    """
    This function is used to verify all the parameters required
    to insert data into pem.probe_column table will be passed or not.

    :param columns_data: Data to be insert in pem.probe_column table.
    :return:
    """
    if 'pc_name' not in columns_data:
        return gettext("Probe column name not supplied.")

    if 'pc_col_type' not in columns_data:
        return gettext("Column Type not supplied.")
    elif columns_data['pc_col_type'] != 'k' \
            and columns_data['pc_col_type'] != 'm':
        return gettext("Column Type should be ('k' or 'm').")

    if 'pc_data_type' not in columns_data:
        return gettext("Column's data type not supplied.")
    else:
        valid_data_type = ['bigint', 'char', 'decimal', 'double precision',
                           'integer', 'numeric', 'real', 'text', 'text[]',
                           'timestamp', 'timestamptz']
        if columns_data['pc_data_type'] not in valid_data_type:
            return gettext("Provide valid data type.")

    if 'pc_unit' not in columns_data:
        return gettext("Column unit not supplied.")

    if 'pc_calc_pit' not in columns_data:
        return gettext("Value of Calculate PIT not supplied.")
    else:
        if columns_data['pc_calc_pit'] is None \
                or not isinstance(columns_data['pc_calc_pit'], bool):
            return gettext("Provide valid value of Calculate PIT.")

    if 'pc_graphable' not in columns_data:
        return gettext("Value of graphable not supplied.")
    else:
        if columns_data['pc_graphable'] is None \
                or not isinstance(columns_data['pc_graphable'], bool):
            return gettext("Provide valid value of graphable.")

    if 'pc_pit_default' not in columns_data:
        return gettext("Value of Is PIT not supplied.")
    else:
        if columns_data['pc_pit_default'] is None \
                or not isinstance(columns_data['pc_pit_default'], bool):
            return gettext("Provide valid value of Is PIT.")

    return None


def insert_probe_columns(columns_data, pem_conn, probe_id=None):
    """
    This function is used to update probe columns data.

    :param columns_data: Data to be saved.
    :param probe_id: Probe ID
    :param pem_conn: PEM Connection object.
    """
    status = True
    result = None

    # insert into pem.probe_column table
    column = 0
    for row in columns_data:
        column += 1

        # Check whether all the required parameter is present and valid.
        error_msg = check_probe_column_parameters(row)
        if error_msg is not None:
            return False, error_msg

        # Get the internal name for column
        column_internal_name = get_internal_name(row['pc_name'])
        mapped_data = {
            'probe_id': probe_id,
            'internal_name': column_internal_name,
            'display_name': row['pc_name'],
            'display_position': column,
            'classification': row['pc_col_type'],
            'sql_data_type': row['pc_data_type'],
            'unit_of_value': row['pc_unit'],
            'calculate_pit': row['pc_calc_pit'],
            'pit_by_default': row['pc_pit_default'],
            'is_graphable': row['pc_graphable']
            # Default to empty string if platform is not provided
        }
        sql = render_template('probes/sql/custom_probe/insert.sql',
                              insert_column=True)

        status, result = pem_conn.execute_void(sql, mapped_data)

    return status, result


def check_extension_level_probe(probe_id, pem_conn):
    """
    Check if given probe is extension level probe

    :param probe_id: Probe ID
    :param pem_conn: PEM connection
    :return:
    """
    # Check whether all the required parameter is present and valid.
    status, pem_schema_version = pem_conn.execute_scalar(
        'select pem.schema_version();'
    )
    if not status:
        return status, pem_schema_version

    if int(pem_schema_version) >= 202112021:
        status, res = pem_conn.execute_dict(f"""
        SELECT any_extension_version, target_type_id,
        extension_name FROM pem.probe WHERE id = '{probe_id}'::int4""")
        if not status:
            return status, res
        if len(res['rows']) == 1:
            target_type_id = res['rows'][0]['target_type_id']
            any_extension_version = res['rows'][0]['any_extension_version']
            extension_name = res['rows'][0]['extension_name']
            # Fetch valid versions for the extension
            status, valid_extension_versions = pem_conn.execute_scalar(
                f"""SELECT ARRAY(
                SELECT extension_version FROM pemdata.oc_extension
                WHERE extension_name = '{extension_name}' ORDER BY 1)"""
            )
            if not status:
                return status, valid_extension_versions
            return True, {
                'extension_level_probe':
                    int(target_type_id) == DashboardLevel.DB_EXTENSION,
                'change_extension_table':
                    int(target_type_id) == DashboardLevel.DB_EXTENSION,
                'extension_name': extension_name,
                'valid_extension_versions': valid_extension_versions
            }
    return False, None


def insert_alternate_code(
        alternate_data, pem_conn, probe_id=None, target_type=None):
    """
    This function is used to update probe's alternate code.

    :param alternate_data: Data to be saved.
    :param probe_id: Probe ID
    :param pem_conn: PEM Connection object.
    :param target_type
    """
    status = True
    result = None
    valid_versions = []

    # Check whether all the required parameter is present and valid.
    ext_status, ext_data = check_extension_level_probe(probe_id, pem_conn)

    if alternate_data:
        sql = render_template('probes/sql/custom_probe/server_versions.sql',
                              to_array=True)
        status, valid_versions = pem_conn.execute_scalar(sql)
        if not status:
            return False, gettext("Unable to fetch server versions.")

    # insert into pem.server_version table
    for row in alternate_data:
        if target_type is not None:
            if int(target_type) == int(DashboardLevel.DB_EXTENSION):
                if 'extension_version' not in row:
                    return False, gettext("Extension Version not supplied.")
            else:
                row['extension_version'] = None

        if 'server_version_id' not in row:
            return False, gettext("Server version not supplied.")
        else:
            if int(row['server_version_id']) not in valid_versions:
                return False, gettext("Provide valid server version.")

        if 'server_probe_code' not in row:
            return False, gettext("Server Probe Code not supplied.")

        # Check if we need to insert into pem.probe_extension_version table
        insert_extension_table = False
        if ext_status and ext_data['change_extension_table']:
            insert_extension_table = True
            if 'extension_version' not in row:
                return False, gettext("Extension version not supplied.")
            elif not row['extension_version']:
                return False, gettext("Provide valid extension version.")
        map_data = {
            'probe_id': probe_id,
            'server_version_id': row['server_version_id'],
            'probe_code': row['server_probe_code']
        }
        if insert_extension_table:
            map_data['extension_version'] = row['extension_version']
            delete_sql = render_template(
                'probes/sql/custom_probe/insert.sql',
                insert_extension_code=True, delete_sql=True)
            insert_sql = render_template(
                'probes/sql/custom_probe/insert.sql',
                insert_extension_code=True, insert_sql=True)
        else:
            delete_sql = render_template(
                'probes/sql/custom_probe/insert.sql',
                insert_server_code=True, delete_sql=True)
            insert_sql = render_template(
                'probes/sql/custom_probe/insert.sql',
                insert_server_code=True, insert_sql=True)

        status, result = pem_conn.execute_void(delete_sql, map_data)
        if not status:
            return False, gettext(result)
        status, result = pem_conn.execute_void(insert_sql, map_data)
        if not status:
            return False, gettext(result)
    return status, result


def is_probe_exist(probe_id, pem_conn):
    """
    This function is used to check whether probe id is valid
    and exist. It also check the given probe id is already deleted.

    :param probe_id: Probe Id.
    :param pem_conn: PEM Connection
    """

    if probe_id is None or not isinstance(probe_id, int):
        return gettext("Provide valid value of probe id")
    try:
        int(probe_id)
    except ValueError:
        return gettext("Probe id must be integer.")

    sql = render_template('probes/sql/custom_probe/probe_status.sql',
                          probe_id=probe_id)

    status, result = pem_conn.execute_dict(sql)
    if not status:
        return result

    if 'rows' in result and len(result['rows']) > 0:
        if result['rows'][0]['deleted']:
            return gettext("Specified probe already deleted.")
    else:
        return gettext("Specified probe not found.")

    return None


def is_system_probe(probe_id, pem_conn):
    """
    This function is used to check the given probe is system probe.

    :param probe_id: Probe Id.
    :param pem_conn: PEM Connection
    """

    sql = render_template('probes/sql/custom_probe/probe_status.sql',
                          probe_id=probe_id)

    status, result = pem_conn.execute_dict(sql)
    if not status:
        return True

    if 'rows' in result and len(result['rows']) > 0:
        return result['rows'][0]['is_system_probe']

    return True


def update_probe(probe_data, pem_conn=None):
    """

    :param probe_data:
    :param pem_conn:
    """
    data = dict()
    status = True
    result = None

    if 'probe_id' not in probe_data:
        return False, gettext("Probe id not supplied.")
    else:
        error_msg = is_probe_exist(probe_data['probe_id'], pem_conn)
        if error_msg is not None:
            return False, error_msg

    if 'interval' in probe_data:
        if probe_data['interval'] is None \
                or not isinstance(probe_data['interval'], int):
            return False, gettext("Provide valid value of interval.")
        try:
            int(probe_data['interval'])
        except ValueError:
            return False, gettext("interval must be integer.")
        data['default_execution_frequency'] = probe_data['interval']

    if 'enabled' in probe_data:
        if probe_data['enabled'] is None \
                or not isinstance(probe_data['enabled'], bool):
            return False, gettext("Provide valid value of probe enabled.")
        data['enabled_by_default'] = probe_data['enabled']

    if 'lifetime' in probe_data:
        if probe_data['lifetime'] is None \
                or not isinstance(probe_data['lifetime'], int):
            return False, gettext("Provide valid value of lifetime.")
        try:
            lifetime = int(probe_data['lifetime'])
        except ValueError:
            return False, gettext("lifetime must be integer.")

        if lifetime <= 0 or lifetime > 365:
            return False, gettext("Valid range for lifetime is 1-365.")
        data['default_lifetime'] = probe_data['lifetime']

    if 'probe_code' in probe_data:
        data['probe_code'] = probe_data['probe_code']

    # Update pem.probe table
    if len(data) > 0:
        sql = render_template('probes/sql/custom_probe/update.sql',
                              update_probe=True, data=data)
        data['probe_id'] = probe_data['probe_id']
        status, result = pem_conn.execute_void(sql, data)

    return status, result


def update_probe_columns(columns_data, pem_conn, probe_id=None):
    """
    This function is used to update probe columns data.

    :param columns_data: Data to be saved.
    :param probe_id: Probe ID
    :param pem_conn: PEM Connection object.
    """
    # Check whether given probe is exist and valid.
    error_msg = is_probe_exist(probe_id, pem_conn)
    if error_msg is not None:
        return False, error_msg

    # Check if the probe is system probe then return from the function
    # Without throwing an error
    if is_system_probe(probe_id, pem_conn):
        return True, None

    data = dict()
    status = True
    result = None
    if 'changed' in columns_data:
        for row in columns_data['changed']:
            if 'pc_unit' in row:
                data['unit_of_value'] = row['pc_unit']
            if 'pc_graphable' in row:
                if row['pc_graphable'] is None \
                        or not isinstance(row['pc_graphable'], bool):
                    return False, gettext("Provide valid value of graphable.")
                data['is_graphable'] = row['pc_graphable']

            if len(data) > 0:
                sql = render_template('probes/sql/custom_probe/update.sql',
                                      update_column=True, data=data)
                data['id'] = row['pc_id']
                data['probe_id'] = probe_id

                status, result = pem_conn.execute_void(sql, data)

                # Clear the data
                data.clear()

    return status, result


def update_alternate_code(alternate_data, pem_conn, probe_id=None):
    """
    This function is used to update probe's alternate code.

    :param alternate_data: Data to be saved.
    :param probe_id: Probe ID
    :param pem_conn: PEM Connection object.
    """

    # Check whether given probe is exist and valid.
    error_msg = is_probe_exist(probe_id, pem_conn)
    if error_msg is not None:
        return False, error_msg

    # Check if the probe is system probe then return from the function
    # Without throwing an error
    if is_system_probe(probe_id, pem_conn):
        return True, None

    status = True
    result = None
    valid_versions = []
    if alternate_data:
        sql = render_template('probes/sql/custom_probe/server_versions.sql',
                              to_array=True)
        status, valid_versions = pem_conn.execute_scalar(sql)
        if not status:
            return False, gettext("Unable to fetch server versions.")

    if 'changed' in alternate_data:
        # Check whether extension level probe.
        ext_status, ext_data = check_extension_level_probe(probe_id, pem_conn)

        for row in alternate_data['changed']:
            if 'marked_for_deletion' in row and row['marked_for_deletion']:
                if ext_status and ext_data['change_extension_table']:
                    if 'extension_version' not in row:
                        return False, gettext(
                            "Extension version not supplied.")
                    sql = render_template(
                        'probes/sql/custom_probe/delete.sql',
                        delete_extension_code=True,
                        server_version_id=row.get('id') or
                        row.get('server_version_id'),
                        extension_version=row.get('extension_version') or
                        row.get('extension_version'),
                        probe_id=probe_id
                    )
                else:
                    sql = render_template(
                        'probes/sql/custom_probe/delete.sql',
                        delete_server_code=True,
                        server_version_id=row.get('id') or
                        row.get('server_version_id'),
                        probe_id=probe_id
                    )
                status, result = pem_conn.execute_void(sql)
                if not status:
                    return status, result
            else:
                mapped_data = {
                    'probe_code': row['server_probe_code'],
                    'server_version_id':
                        row.get('id') or
                        row.get('server_version_id'),
                    'probe_id': probe_id
                }
                if 'server_probe_code' in row and \
                        ('server_version_id' in row or 'id' in row):
                    if int(row.get('id') or row.get('server_version_id')) \
                            not in valid_versions:
                        return False, gettext(
                            "Provide valid server version."
                        )

                    if 'server_probe_code' not in row:
                        return False, gettext(
                            "Server Probe Code not supplied."
                        )
                    if ext_status and ext_data['change_extension_table']:
                        if 'extension_version' not in row:
                            return False, gettext(
                                "Extension version not supplied.")
                        elif not row['extension_version']:
                            return False, gettext(
                                "Provide valid extension version.")
                        sql = render_template(
                            'probes/sql/custom_probe/update.sql',
                            update_server_code=True,
                            extension_version=row.get('extension_version')
                        )
                        mapped_data['extension_version'] = (
                            row.get('extension_version'))
                    else:
                        sql = render_template(
                            'probes/sql/custom_probe/update.sql',
                            update_server_code=True)

                    status, result = pem_conn.execute_void(sql, mapped_data)
                    if not status:
                        return status, result

    if 'deleted' in alternate_data:
        # Check whether extension level probe.
        ext_status, ext_data = check_extension_level_probe(probe_id, pem_conn)

        for row in alternate_data['deleted']:
            if 'server_version_id' not in row and 'id' not in row:
                return False, gettext("Server version not supplied.")
            else:
                if int(row.get('id') or
                       row.get('server_version_id')) not in valid_versions:
                    return False, gettext("Provide valid server version.")
            if ext_status and ext_data['change_extension_table']:
                if 'extension_version' not in row:
                    return False, gettext("Extension version not supplied.")

                sql = render_template(
                    'probes/sql/custom_probe/delete.sql',
                    delete_server_code=True,
                    server_version_id=row.get('id') or
                    row.get('server_version_id'),
                    extension_version=row.get('extension_version'),
                    probe_id=probe_id)
            else:
                sql = render_template(
                    'probes/sql/custom_probe/delete.sql',
                    delete_server_code=True,
                    server_version_id=row.get('id') or
                    row.get('server_version_id'),
                    probe_id=probe_id)

            status, result = pem_conn.execute_void(sql)
            if not status:
                return status, result

    if 'added' in alternate_data:
        # Check whether extension level probe.
        ext_status, ext_data = check_extension_level_probe(probe_id, pem_conn)

        # insert into pem.server_version table
        for row in alternate_data['added']:
            if 'server_version_id' not in row:
                return False, gettext("Server version not supplied.")
            else:
                if int(row['server_version_id']) not in valid_versions:
                    return False, gettext("Provide valid server version.")

            if 'server_probe_code' not in row:
                return False, gettext("Server Probe Code not supplied.")
            map_data = {
                'probe_id': probe_id,
                'server_version_id': row['server_version_id'],
                'probe_code': row['server_probe_code']
            }
            if ext_status and ext_data['change_extension_table']:
                if 'extension_version' not in row:
                    return False, gettext("Extension version not supplied.")
                elif not row['extension_version']:
                    return False, gettext("Provide valid extension version.")
                map_data['extension_version'] = row['extension_version']
                delete_sql = render_template(
                    'probes/sql/custom_probe/insert.sql',
                    insert_extension_code=True, delete_sql=True)
                insert_sql = render_template(
                    'probes/sql/custom_probe/insert.sql',
                    insert_extension_code=True, insert_sql=True)
            else:
                delete_sql = render_template(
                    'probes/sql/custom_probe/insert.sql',
                    insert_server_code=True, delete_sql=True)
                insert_sql = render_template(
                    'probes/sql/custom_probe/insert.sql',
                    insert_server_code=True, insert_sql=True)

            status, result = pem_conn.execute_void(delete_sql, map_data)
            if not status:
                return False, gettext(result)
            status, result = pem_conn.execute_void(insert_sql, map_data)
            if not status:
                return False, gettext(result)

    return status, result


def delete_probe(probe_ids, pem_conn):
    """
    This function is used to delete specified custom probes.

    :param probe_ids: List of custom probes to be deleted.
    :param pem_conn: PEM Connection
    """

    sql = render_template('probes/sql/custom_probe/delete.sql',
                          delete_probe=True,
                          probe_ids=probe_ids)

    status, result = pem_conn.execute_void(sql)

    return status, result


def is_probe_exists(
    pem_conn, display_name, probe_id=None,
    deleted=False, internal_name=False
):
    """
    Check if probe name being added/updated already exists
    :param pem_conn: PEM connection
    :param display_name: probe name
    :param probe_id: probe Id
    :param deleted: If we need to include deleted probes
    :param internal_name: To look via internal name or display name
    :return: True/False
    """
    params = {
        'display_name': display_name,
        'deleted': deleted,
        'internal_name': internal_name
    }
    if probe_id:
        params['id'] = probe_id

    sql = render_template('probes/sql/custom_probe/probe_exists.sql', **params)

    status, result = pem_conn.execute_scalar(sql)

    if status and int(result) > 0:
        return True
    return False


def serialize_probe_cols(intermediate_rows, row):
    """
    Allow us to decouple the columns data and alternate code data
    :param intermediate_rows:
    :param row: Result row
    :return: serialize data for json response
    """
    probe_columns = json.loads(row.get('probe_columns', '[]'))
    row['probe_columns'] = probe_columns
    row['alternate_code'] = [] if row.get('alternate_code') is None \
        else json.loads(row['alternate_code'])
    intermediate_rows.append(row)
    return intermediate_rows


def generate_export_probe_data(
    pem_conn, probes, using_ids=True, show_system=False, deleted=False
):
    """
    Check if probe name being added/updated already exists
    :param pem_conn: PEM connection
    :param probes: List of selected probes by user
    :param using_ids: Flag to switch between id and internal name
    :param show_system: Also look into system probes
    :param deleted: Export deleted probes
    :return: Dict
    """

    sql = render_template(
        PROBE_LIST_SQL,
        export_probes=True,
        using_ids=using_ids,
        show_system=show_system,
        deleted=deleted,
        placeholders=get_sql_placeholders(probes)
    )
    # Execute the query.
    status, result = pem_conn.execute_dict(sql, probes)
    if not status:
        return status, result

    result = reduce(serialize_probe_cols, result.get('rows', []), [])

    return True, result


def insert_imported_probes(
    pem_conn, probes, skip_existing=True, with_transaction=True
):
    """
    :param pem_conn: PEM connection
    :param probes: Probes to insert
    :param skip_existing: Skip if probe already present
    :param with_transaction: Set transaction for each row if set to True
    :return: List of status
    """
    _FAILED = "Failed"
    _SUCCESS = "Success"
    _SKIPPED = "Skipped"
    success = 0
    final_result = []

    def update_store(_name, _status=_SUCCESS, _msg=None):
        """Avoid duplication of code using this inner function"""
        final_result.append({
            'name': _name,
            'status': _status,
            'msg': _msg
        })

    for probe in probes:
        # Per probe transaction starts
        inner_count = 3
        is_probe_insert = True
        msg = None

        is_exists = is_probe_exists(
            pem_conn, probe['internal_name'], probe_id=None,
            deleted=True, internal_name=True
        )
        if is_exists:
            if skip_existing:
                # Update as Skipped and go to next probe
                update_store(probe['probe_name'], _SKIPPED)
            else:
                # If the probe is deleted then make it enable again and
                # set the status to success

                status, is_deleted = pem_conn.execute_scalar("""
                SELECT count(1) FROM pem.probe WHERE internal_name = %s
                AND deleted""", [probe['internal_name']])
                if not status:
                    update_store(probe['probe_name'], _FAILED, is_deleted)
                if is_deleted and int(is_deleted) == 1:
                    status, msg = pem_conn.execute_void("""
                    UPDATE pem.probe SET deleted = false WHERE
                    internal_name = %s
                    """, [probe['internal_name']])
                    if not status:
                        update_store(probe['probe_name'], _FAILED, msg)
                    update_store(probe['probe_name'], _SUCCESS)
                    continue
                # ERROR OUT in main result and go to next probe
                update_store(
                    probe['probe_name'], _FAILED, "The probe already exist")
            continue  # Do not want to ahead let go to next probe now

        if with_transaction:
            status, _ = pem_conn.execute_void("BEGIN")
            if not status:
                update_store(
                    probe['probe_name'], _FAILED,
                    gettext("Failed to start the transaction")
                )
                continue

        # Insert into pem.probe table
        status, probe_id = insert_probe(probe, pem_conn)
        if not status:
            inner_count -= 1
            is_probe_insert = False  # Flag to insert columns and code
            msg = probe_id
            if with_transaction:
                pem_conn.execute_void('ROLLBACK')

        # If probe columns are added then call
        # insert_probe_columns function to save the data.
        if is_probe_insert and 'probe_columns' in probe:
            status, result = insert_probe_columns(
                probe['probe_columns'], pem_conn, probe_id
            )
            if not status:
                inner_count -= 1
                msg = result
                if with_transaction:
                    pem_conn.execute_void('ROLLBACK')

        # If alternate code are added then call
        # insert_alternate_code function to save the data.
        if is_probe_insert and 'alternate_code' in probe and \
                len(probe['alternate_code']) > 0:
            status, result = insert_alternate_code(
                probe['alternate_code'], pem_conn, probe_id
            )
            if not status:
                inner_count -= 1
                msg = result
                if with_transaction:
                    pem_conn.execute_void('ROLLBACK')

        if inner_count == 3:
            # Per probe transaction ends
            if with_transaction:
                status, _ = pem_conn.execute_void("COMMIT")
                if status:
                    success += 1
                    update_store(probe['probe_name'], _SUCCESS)
                else:
                    update_store(
                        probe['probe_name'], _FAILED,
                        gettext("The probe failed to commit")
                    )
            else:
                success += 1
                update_store(probe['probe_name'], _SUCCESS)
        else:
            update_store(
                probe['probe_name'], _FAILED, msg
            )

    if success > 0:
        # Finally Create data and history table.
        status, result = pem_conn.execute_void(
            "SELECT pem.create_data_and_history_tables()"
        )
        if not status:
            pem_conn.execute_void('ROLLBACK')
            update_store(
                "", _FAILED,
                gettext("Failed to create pemdata & history objects for"
                        "the inserted probes due to an error - "
                        "{}".format(result))
            )

    return final_result


def validate_imported_probes_fields(pem_conn, probes):
    """
    :param pem_conn: PEM connection
    :param probes: List of probes to import
    :return: boolean, error_msg
    """
    for probe in probes:
        # If name is missing then error and return from here
        if 'probe_name' not in probe or not probe['probe_name']:
            return False, gettext("Please provide valid probe name.")
        # Rest of the fields
        msg = None
        if 'internal_name' not in probe or not probe['internal_name']:
            msg = gettext("Please provide valid internal name.")
        elif 'collection_method' not in probe or \
                not probe['collection_method']:
            msg = gettext("Please provide valid collection method.")
        elif 'target_type' not in probe or not probe['target_type']:
            msg = gettext("Please provide valid probe target type.")
        elif 'enabled' not in probe or type(probe['enabled']) is not bool:
            msg = gettext("Please provide valid value for enabled.")
        elif 'interval' not in probe or type(probe['interval']) is not int:
            msg = gettext("Please provide valid interval.")
        elif 'lifetime' not in probe or type(probe['lifetime']) is not int:
            msg = gettext("Please provide valid lifetime.")
        elif 'probe_code' not in probe or not probe['probe_code']:
            msg = gettext("Please provide valid probe code.")
        elif 'any_server_version' not in probe or \
                type(probe['any_server_version']) is not bool:
            msg = gettext(
                "Please provide valid value for any server version.")
        elif 'discard_history' not in probe or \
                type(probe['discard_history']) is not bool:
            msg = gettext(
                "Please provide valid value for discard history.")
        elif 'platform' not in probe or not probe['platform']:
            msg = gettext("Please provide valid platform.")
        elif 'probe_columns' not in probe or len(probe['probe_columns']) == 0:
            msg = gettext("Please provide valid probe columns.")

        if msg:
            return False, "Probe '{}': {}".format(probe['probe_name'], msg)

        # Check probe columns array
        for column_row in probe['probe_columns']:
            msg = check_probe_column_parameters(column_row)
            if msg:
                return False, "Probe '{}': {}".format(probe['probe_name'], msg)

        # Check alternate code array
        if 'alternate_code' in probe and len(probe['alternate_code']) > 0:
            status, valid_versions = pem_conn.execute_scalar(
                render_template(
                    'probes/sql/custom_probe/server_versions.sql',
                    to_array=True
                )
            )
            if not status:
                msg = gettext("Unable to fetch server versions.")
                return False, "Probe '{}': {}".format(
                    probe['probe_name'], msg)

            for row in probe['alternate_code']:
                if 'server_version_id' not in row:
                    msg = gettext("Server version not supplied.")
                elif int(row['server_version_id']) not in valid_versions:
                    msg = gettext("Provide valid server version.")
                elif 'server_probe_code' not in row:
                    msg = gettext("Server Probe Code not supplied.")

                if msg:
                    return False, "Probe '{}': {}".format(
                        probe['probe_name'], msg)

        return True, None


def set_probes_to_default(
    target_type_id, object_id, database_name, schema_name,
        object_name, pem_conn):
    """This will set the probes to the default settings for the
    specified target type
    """
    if target_type_id == DashboardLevel.DB_AGENT:  # Agent
        sql = render_template('probes/sql/probes/set_default.sql',
                              target_type='agent',
                              object_id=object_id,
                              conn=pem_conn
                              )
    elif target_type_id == DashboardLevel.DB_SERVER:  # Server
        sql = render_template('probes/sql/probes/set_default.sql',
                              target_type='server',
                              object_id=object_id,
                              conn=pem_conn
                              )
    elif target_type_id == DashboardLevel.DB_DATABASE:  # Database
        sql = render_template('probes/sql/probes/set_default.sql',
                              target_type='database',
                              object_id=object_id,
                              database_name=database_name,
                              conn=pem_conn
                              )
    elif target_type_id == DashboardLevel.DB_SCHEMA:  # Schema
        sql = render_template('probes/sql/probes/set_default.sql',
                              target_type='schema',
                              object_id=object_id,
                              database_name=database_name,
                              schema_name=schema_name,
                              conn=pem_conn
                              )
    status, result = pem_conn.execute_void(sql)

    if not status:
        pem_conn.execute_void("ROLLBACK;")
        return status, result

    status, result = pem_conn.execute_void("COMMIT;")

    return status, result


def set_extension_probes_to_default(
        target_type_id, object_id, database_name, extension_name, pem_conn):
    """This will set the probes to the default settings for the
    specified target type
    """
    if target_type_id == DashboardLevel.DB_EXTENSION:  # Extension
        sql = render_template('probes/sql/probes/set_default.sql',
                              target_type='extension',
                              object_id=object_id,
                              database_name=database_name,
                              extension_name=extension_name,
                              conn=pem_conn
                              )
    else:
        current_app.logger.error(
            "Target type id should be 1000 but got: {0}".format(target_type_id)
        )
    status, result = pem_conn.execute_void(sql)

    if not status:
        pem_conn.execute_void("ROLLBACK;")
        return status, result

    status, result = pem_conn.execute_void("COMMIT;")

    return status, result


def get_light_probe_list(pem_conn):
    sql = render_template('probes/sql/custom_probe/probe_light_list.sql')
    status, probes = pem_conn.execute_dict(sql)
    return status, reduce(serialize_probe_cols, probes.get('rows', []), [])
