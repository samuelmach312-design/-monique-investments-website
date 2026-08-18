##########################################################################
#
# Postgres Enterprise Manager
#
# Copyright (C) 2016 - 2025, EnterpriseDB Corporation. All rights reserved.
#
##########################################################################

"""Implements Copy Alerts"""

import json
from flask import render_template, request
from pgadmin.utils.ajax import internal_server_error, make_json_response, \
    bad_request
from flask_security import login_required
from pgadmin.pem.utils import pem_connection, get_restricted_objects_clause
from flask_babel import gettext
from functools import wraps
from . import utils

VALID_NODE_TYPE = ['coll-group', 'server-group', 'agent', 'server',
                   'database', 'schema', 'table']


def request_validator(f):
    """
    This function will validates requests and it's parameters if necessary
    """
    @wraps(f)
    def wrapped(*args, **kwargs):
        valid_request_parameters = True
        msg = ''

        # Check if we have valid node_type
        if 'node_type' in kwargs and kwargs['node_type'] is not None:
            if kwargs['node_type'] not in VALID_NODE_TYPE:
                valid_request_parameters = False
                msg = "Invalid node type provided"

        # Check if we have valid agent_id
        if valid_request_parameters and 'agent_id' in kwargs:
            if not kwargs['agent_id'] > 0:
                valid_request_parameters = False
                msg = "Invalid agent id provided"

        # Check if we have valid server_id
        if valid_request_parameters and 'server_id' in kwargs:
            if not kwargs['server_id'] > 0:
                valid_request_parameters = False
                msg = "Invalid server id provided"

        # If validation fails return from here
        if not valid_request_parameters:
            return bad_request(gettext(msg))

        return f(*args, **kwargs)
    return wrapped


@login_required
@utils.configAlertRole.check_role(
    gettext("Logged-in user do not have permission "
            "to access copy alert nodes.")
)
@request_validator
@pem_connection
def nodes(browser_node_type=None, node_type=None, agent_id=None, group_id=None,
          server_id=None, db_name=None, schema_name=None, table_name=None,
          pem_conn=None):
    """
    This function will return the list of nodes.

    :param browser_node_type: Node type selected in browser.
    :param node_type: expanded node type of Copy alert dialog.
    :param agent_id: agent id.
    :param server_id: server id.
    :param db_name: database name.
    :param schema_name: schema name.
    :param table_name: table name.
    :param pem_conn: PEM Connection object.
    """

    params = []
    tree_node_type = ''
    tree_node_icon = ''
    sql = ''

    if node_type is None:
        return make_json_response(
            data=[{
                'id': 'coll-group/1',
                'inode': True,
                'label': gettext('Groups'),
                'icon': 'icon-group',
                '_type': 'coll-group',
                'checkbox': False
            }]
        )

    if node_type == 'coll-group':
        sql = render_template('alerts/sql/copy_alert/node_list.sql',
                              node_type='coll-group',
                              browser_node_type=browser_node_type)
        tree_node_type = 'server-group'
        tree_node_icon = 'icon-server_group'

    elif node_type == 'server-group':
        sql = render_template('alerts/sql/copy_alert/node_list.sql',
                              node_type='server-group',
                              browser_node_type=browser_node_type)
        params = [group_id]
        if browser_node_type == 'agent':
            tree_node_type = 'agent'
            tree_node_icon = 'icon-agent'
        else:
            tree_node_type = 'server'
            tree_node_icon = 'icon-server'

    elif node_type == 'agent':
        sql = render_template('alerts/sql/copy_alert/node_list.sql',
                              node_type='agent')
        params = [agent_id]
        tree_node_type = 'server'
        tree_node_icon = 'icon-server'

    elif node_type == 'server':
        params = {'group_id': group_id, 'server_id': server_id}
        tree_node_type = 'database'
        tree_node_icon = 'pg-icon-database'

        ret_val, result, rest_param = get_restricted_objects_clause(
            pem_conn, '(%(database_name)s)', 'b.database_name', 0, server_id)
        if ret_val:
            result = " AND (%s)" % result
            params.update({'database_name': rest_param})

        sql = render_template('alerts/sql/copy_alert/node_list.sql',
                              node_type='server', result=result)

    elif node_type == 'database':
        params = {'group_id': group_id,
                  'server_id': server_id, 'db_name': db_name}
        tree_node_type = 'schema'
        tree_node_icon = 'icon-schema'

        ret_val, result, rest_param = get_restricted_objects_clause(
            pem_conn, '(%(schema_name)s)', 'b.schema_name', 1,
            server_id, db_name)
        if ret_val:
            result = " AND (%s)" % result
            params.update({'schema_name': rest_param})

        sql = render_template('alerts/sql/copy_alert/node_list.sql',
                              node_type='database', result=result)
    elif node_type == 'schema':
        params = {'group_id': group_id,
                  'server_id': server_id, 'db_name': db_name,
                  'schema_name': schema_name}

        if browser_node_type == 'index':
            tree_node_type = 'table'
            tree_node_icon = 'icon-' + 'table'

            ret_val, result, rest_param = get_restricted_objects_clause(
                pem_conn, '(%(schema_name)s)', 'b.schema_name', 1,
                server_id, db_name)
            if ret_val:
                result = " AND (%s)" % result
                params.update({'schema_name': rest_param})

            sql = render_template('alerts/sql/copy_alert/node_list.sql',
                                  node_type='schema',
                                  browser_node_type='table',
                                  result=result)
        else:
            tree_node_type = browser_node_type
            tree_node_icon = 'icon-' + browser_node_type

            ret_val, result, rest_param = get_restricted_objects_clause(
                pem_conn, '(%(schema_name)s)', 'b.schema_name', 1,
                server_id, db_name)
            if ret_val:
                result = " AND (%s)" % result
                params.update({'schema_name': rest_param})

            sql = render_template('alerts/sql/copy_alert/node_list.sql',
                                  node_type='schema',
                                  browser_node_type=browser_node_type,
                                  result=result)
    elif node_type == 'table':
        params = {'group_id': group_id,
                  'server_id': server_id, 'db_name': db_name,
                  'schema_name': schema_name,
                  'table_name': table_name}
        tree_node_type = browser_node_type
        tree_node_icon = 'icon-' + browser_node_type

        ret_val, result, rest_param = get_restricted_objects_clause(
            pem_conn, '(%(schema_name)s)', 'b.schema_name', 1,
            server_id, db_name)
        if ret_val:
            result = " AND (%s)" % result
            params.update({'schema_name': rest_param})

        sql = render_template('alerts/sql/copy_alert/node_list.sql',
                              node_type='schema',
                              browser_node_type=browser_node_type,
                              result=result)

    # Get node list from node type
    status, result = pem_conn.execute_dict(sql, params)
    if not status:
        return internal_server_error(errormsg=result)

    # If the node type of selected node on browser is same as the
    # node type to be render in copy alert dialog then set the
    # inode property of all such node is false as they are the
    # leaf nodes.
    inode = True
    if browser_node_type == tree_node_type:
        inode = False

    node_data = []
    for row in result['rows']:
        node_id = None
        append_node = False
        if 'id' in row:
            node_id = row['id']

        # While listing database and schema we need to check the value
        # of show system object and it should not be the system's
        # database or schema.
        if node_type == 'server':
            if row['sysdb'] is False:
                append_node = True
        elif node_type == 'database':
            if row['sys_schema'] is False:
                append_node = True
        else:
            append_node = True

        label = row['name']
        if browser_node_type == 'function' and 'args' in row:
            label = row['name'] + '(' + row['args'] + ')'
        info_msg = ''
        has_checkbox = True
        if browser_node_type in ['server', 'agent']:
            info_msg = row.get(
                'profile_id',
                False
            ) and gettext(
                "Alerts cannot be copied to a profile-managed {0}".format(
                    tree_node_type
                )
            ) or ''
            has_checkbox = not row.get('profile_id', False)
        if append_node:
            node_data.append({
                '_id': node_id,
                'inode': inode,
                'label': label,
                'icon': tree_node_icon,
                '_type': tree_node_type,
                'group_id': group_id,
                'agent_id': agent_id,
                'server_id': server_id,
                'db_name': db_name,
                'checkbox': has_checkbox,
                'is_info_msg': bool(info_msg),
                'err_msg': info_msg,
                'info_msg': info_msg,
                'schema_name': schema_name,
                'object_name': row['name'],
                'args': row['args'] if 'args' in row else ''
            })

    return make_json_response(
        data=node_data
    )


@login_required
@utils.configAlertRole.check_role(
    gettext("Logged-in user do not have permission to configure copy alert.")
)
@pem_connection
def configure(pem_conn=None):
    """
    This function is used to copy the alert configuration
    from source to specified target types.

    :param pem_conn: PEM Connection object.
    """

    if request.data:
        copy_data = json.loads(request.data.decode())

    if len(copy_data) > 1:

        # First element of the copy_target array is source object
        source = copy_data[0]

        # Ignore or Replace the duplicate entry of alerts
        if 'existing_alert_options' in source:
            existing_alert_options = source['existing_alert_options']
        else:
            existing_alert_options = 'I'

        # Iterate source and create new data structure with proper name
        copy_source = dict()
        if source['type'] == 'agent':
            copy_source['agent_id'] = source['id']
            copy_source['type'] = source['type']
        elif source['type'] == 'server':
            copy_source['server_id'] = source['id']
            copy_source['type'] = source['type']
        elif source['type'] == 'database':
            copy_source['database_name'] = source['label']
            copy_source['server_id'] = source['server_id']
            copy_source['type'] = source['type']
        elif source['type'] == 'schema':
            copy_source['schema_name'] = source['label']
            copy_source['database_name'] = source['database_name']
            copy_source['server_id'] = source['server_id']
            copy_source['type'] = source['type']
        elif source['type'] in ['table', 'index', 'sequence', 'function']:
            copy_source['object_name'] = source['label']
            copy_source['schema_name'] = source['schema_name']
            copy_source['database_name'] = source['database_name']
            copy_source['server_id'] = source['server_id']
            copy_source['type'] = source['type']

        # Iterate all the targets create new data structure with proper name
        copy_targets = list()
        for data in copy_data[1:]:
            target = dict()

            if data['type'] == 'agent':
                target['agent_id'] = data['id']
                target['type'] = data['type']
            elif data['type'] == 'server-group':
                target['group_id'] = data['id']
                target['type'] = data['type']
            elif data['type'] == 'server':
                target['server_id'] = data['id']
                target['type'] = data['type']
            elif data['type'] == 'database':
                target['database_name'] = data['label']
                target['server_id'] = data['server_id']
                target['type'] = data['type']
            elif data['type'] == 'schema':
                target['schema_name'] = data['label']
                target['database_name'] = data['database_name']
                target['server_id'] = data['server_id']
                target['type'] = data['type']
            elif data['type'] in ['table', 'index', 'sequence']:
                target['object_name'] = data['label']
                target['schema_name'] = data['schema_name']
                target['database_name'] = data['database_name']
                target['server_id'] = data['server_id']
                target['type'] = data['type']
            elif data['type'] == 'function':
                target['object_name'] = data['label']
                target['schema_name'] = data['schema_name']
                target['database_name'] = data['database_name']
                target['server_id'] = data['server_id']
                target['type'] = data['type']
                target['function_name'] = data['object_name']
                target['args'] = data['args']

            copy_targets.append(target)

        status, result = utils.copy_alerts(
            copy_source, copy_targets, existing_alert_options, pem_conn
        )

        if not status:
            return internal_server_error(errormsg=result)

    return make_json_response(status=200)


def register_copy_routes(blueprint):
    for rule in [
        ['/nodes/', 'copy_nodes'],
        ['/nodes/<browser_node_type>/<node_type>/', 'coll_copy_nodes'],
        ['/nodes/<browser_node_type>/<node_type>/<int:group_id>',
         'server_group_nodes'],
        ['/nodes/<browser_node_type>/<node_type>/<int:agent_id>',
         'agent_copy_nodes'],
        ['/nodes/<browser_node_type>/<node_type>/<int:group_id>/'
            '<int:server_id>', 'server_copy_nodes'],
        ['/nodes/<browser_node_type>/<node_type>/<int:group_id>/'
            '<int:server_id>/<db_name>', 'db_copy_nodes'],
        ['/nodes/<browser_node_type>/<node_type>/<int:group_id>/'
            '<int:server_id>/<db_name>/<schema_name>', 'schema_copy_nodes'],
        ['/nodes/<browser_node_type>/<node_type>/<int:group_id>/'
            '<int:server_id>/<db_name>/<schema_name>/<table_name>',
            'table_copy_nodes']
    ]:
        blueprint.add_url_rule('/copy' + rule[0],
                               methods=["GET"], endpoint=rule[1],
                               view_func=nodes)
    blueprint.add_url_rule('/copy/configure',
                           methods=["PUT", "POST"], endpoint='copy_config',
                           view_func=configure)
