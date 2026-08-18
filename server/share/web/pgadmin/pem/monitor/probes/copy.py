##########################################################################
#
# Postgres Enterprise Manager
#
# Copyright (C) 2016 - 2025, EnterpriseDB Corporation. All rights reserved.
#
##########################################################################

"""Implements Copy Probes"""

import json
from flask import current_app, render_template, request
from pgadmin.utils.ajax import internal_server_error, make_json_response
from flask_security import login_required
from pgadmin.pem.utils import pem_connection, get_restricted_objects_clause
from pgadmin.utils.preferences import Preferences
from . import utils
from flask_babel import gettext


class CopyModule:
    show_system_pref = None

    @staticmethod
    def show_system_objects():
        if CopyModule.show_system_pref is None:
            CopyModule.show_system_pref = Preferences.module(
                'browser'
            ).preference(
                'show_system_objects'
            )
        return CopyModule.show_system_pref.get()


@login_required
@utils.configProbeRole.check_role(gettext(
    "Logged-in user do not have permission to access copy probe nodes."
))
@pem_connection
def nodes(
    browser_node_type=None, node_type=None, agent_id=None, group_id=None,
    server_id=None, db_name=None, schema_name=None, pem_conn=None
):
    """
    This function will return the list of nodes.

    :param browser_node_type: Node type selected in browser.
    :param node_type: expanded node type of Copy probe dialog.
    :param agent_id: agent id.
    :param server_id: server id.
    :param db_name: database name.
    :param schema_name: schema name.
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
        sql = render_template('probes/sql/copy_probe/node_list.sql',
                              node_type='coll-group',
                              browser_node_type=browser_node_type)
        tree_node_type = 'server-group'
        tree_node_icon = 'icon-server_group'

    elif node_type == 'server-group':
        sql = render_template('probes/sql/copy_probe/node_list.sql',
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
        sql = render_template(
            'probes/sql/copy_probe/node_list.sql', node_type='agent'
        )
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

        sql = render_template('probes/sql/copy_probe/node_list.sql',
                              node_type='server', result=result)

    elif node_type == 'database':
        params = {'group_id': group_id,
                  'server_id': server_id, 'db_name': db_name}
        tree_node_type = 'schema'
        tree_node_icon = 'icon-schema'

        ret_val, result, rest_param = get_restricted_objects_clause(
            pem_conn, '(%(schema_name)s)', 'b.schema_name', 1, server_id,
            db_name
        )
        if ret_val:
            result = " AND (%s)" % result
            params.update({'schema_name': rest_param})

        sql = render_template('probes/sql/copy_probe/node_list.sql',
                              node_type='database', result=result)

    # Execute the query.
    status, result = pem_conn.execute_dict(sql, params)

    if not status:
        return internal_server_error(errormsg=result)

    # If the node type of selected node on browser is same as the
    # node type to be render in copy probe dialog then set the
    # inode property of all such node is false as they are the
    # leaf nodes.
    inode = True
    if browser_node_type == tree_node_type:
        inode = False

    show_sysobj = CopyModule.show_system_objects()

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
            if show_sysobj is True or row['sysdb'] is False:
                append_node = True
        elif node_type == 'database':
            if show_sysobj is True or row['sys_schema'] is False:
                append_node = True
        else:
            append_node = True
        info_msg = ''
        has_checkbox = True
        allowed_browser_nodes = [
            'server', 'agent', 'database', 'schema', 'extension'
        ]
        if browser_node_type in allowed_browser_nodes:
            info_msg = row.get(
                'profile_id',
                False
            ) and gettext(
                'Probes cannot be copied to a profile-managed {0}'.format(
                    tree_node_type
                )
            ) or ''
            has_checkbox = not row.get('profile_id', False)
        if append_node:
            node_data.append({
                '_id': node_id,
                'inode': inode,
                'label': row['name'],
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
            })

    return make_json_response(
        data=node_data
    )


@login_required
@utils.configProbeRole.check_role(
    gettext("Logged-in user do not have permission to configure copy probes.")
)
@pem_connection
def configure(pem_conn=None):
    """
    This function is used to copy the probe configuration
    from source to specified target types.

    :param pem_conn: PEM Connection object.
    """

    if request.data:
        copy_data = json.loads(request.data.decode())
    else:
        copy_data = request.args or request.form

    if len(copy_data) > 1:

        show_sys_obj = CopyModule.show_system_objects()

        # First element of the copy_target array is source object
        source = copy_data[0]

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

        # Iterate all the targets create new data structure with proper name
        copy_targets = list()
        for data in copy_data[1:]:
            target = dict()

            if data['type'] == 'agent':
                target['agent_id'] = data['id']
                target['type'] = data['type']
            elif data['type'] == 'server':
                target['server_id'] = data['id']
                target['type'] = data['type']
            elif data['type'] == 'server-group':
                target['group_id'] = data['id']
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

            copy_targets.append(target)

        status, result = utils.copy_probes(
            copy_source, copy_targets, show_sys_obj, pem_conn
        )

        if not status:
            return internal_server_error(errormsg=result)

        # Optionally force an immediate refresh of the probe target MV so
        # that newly copied probe configurations are visible to the UI right
        # away. Normally the AFTER triggers on the probe config tables flag
        # staleness and the system job refreshes within the next minute.
        # If the UX requires synchronous visibility, keep this call.
        # (Low overhead if the view is already fresh because the function
        # short-circuits when no refresh is needed.)
        status, err = pem_conn.execute_void(
            "SELECT pem.refresh_stale_probe_view();")
        if not status:
            current_app.logger.warning(
                "Refresh of probe_target_view skipped "
                "after copy: %s", err
            )

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
         '<int:server_id>/<db_name>/<schema_name>', 'schema_copy_nodes']
    ]:
        blueprint.add_url_rule(
            '/copy' + rule[0], methods=["GET"], endpoint=rule[1],
            view_func=nodes
        )

    blueprint.add_url_rule(
        '/copy/configure', methods=["PUT", "POST"],
        endpoint='copy_config', view_func=configure
    )
