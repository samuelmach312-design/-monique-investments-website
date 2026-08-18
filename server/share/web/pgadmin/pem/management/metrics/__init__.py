##########################################################################
#
# Postgres Enterprise Manager
#
# Copyright (C) 2016 - 2025, EnterpriseDB Corporation. All rights reserved.
#
##########################################################################

import uuid
from collections import OrderedDict

from functools import wraps, partial

from config import PG_DEFAULT_DRIVER
from pgadmin.utils.driver import get_driver

"""Implements charts metrics"""

from flask import render_template, request
from flask_babel import gettext
from pgadmin.utils.ajax import internal_server_error, bad_request, \
    make_json_response
from pgadmin.utils import PgAdminModule
from flask import url_for
from flask_security import login_required
from pgadmin.pem.utils import pem_connection, get_restricted_objects_clause

import json
from urllib.request import unquote

MODULE_NAME = 'metrics'
driver = partial(get_driver, PG_DEFAULT_DRIVER)


class MetricsModule(PgAdminModule):
    """
    class MetricsModule(Object):

        It is a wizard which inherits PgAdminModule
        class and define methods to load its own
        javascript file.
    """

    LABEL = gettext('Metrics')

    def get_own_stylesheets(self):
        stylesheets = [
            url_for('metrics.static',
                    filename='css/metrics.css')
        ]
        return stylesheets

    def get_exposed_url_endpoints(self):
        """
        Returns:
            list: a list of url endpoints exposed to the client.
        """
        return [
            'metrics.list_templates', 'metrics.no_node',
            'metrics.node_list', 'metrics.agent_node_list',
            'metrics.server_node_list', 'metrics.db_node_list',
            'metrics.schema_node_list', 'metrics.pkg_node_list',
            'metrics.metric_list', 'metrics.agent_metric_list',
            'metrics.server_metric_list', 'metrics.db_metric_list',
            'metrics.schema_metric_list', 'metrics.pkg_metric_list',
            'metrics.pkg_func_metric_list', 'metrics.submetric_list',
            'metrics.submetric_list_attr', 'metrics.submetric_list_db_attr',
            'metrics.update_templates', 'metrics.get_template',
            'metrics.add_template'
        ]


# Create blueprint for Manage Probes class
blueprint = MetricsModule(
    MODULE_NAME, __name__, static_url_path='', url_prefix="/pem/metrics")


def request_validator(f):
    """
    This function will validates requests and it's parameters if necessary
    """
    @wraps(f)
    def wrapped(*args, **kwargs):
        valid_request_parameters = True
        msg = ''
        # Check if we have valid target_type_id
        if 'query_type' in kwargs:
            if not kwargs['query_type'] <= 15:
                valid_request_parameters = False
                msg = "Invalid query type id provided"

        if 'tid' in kwargs:
            if not kwargs['tid'] > 0:
                valid_request_parameters = False
                msg = "Invalid template id provided"

        # If validation fails return from here
        if not valid_request_parameters:
            return bad_request(gettext(msg))

        return f(*args, **kwargs)
    return wrapped


@blueprint.route("/")
@login_required
def index():
    return bad_request(errormsg=gettext(
        "This URL cannot be called directly!")
    )


@blueprint.route(
    '/submetric_list/<int:query_type>/<int:val>/'
    '<path:metric_name>/<metric>/<int:mid>/<int:sub_count>',
    methods=["GET"], endpoint='submetric_list')
@blueprint.route(
    '/submetric_list/<int:query_type>/<int:val>/'
    '<path:metric_name>/<metric>/<int:mid>/<int:sub_count>/<int:only_attr>',
    methods=["GET"], endpoint='submetric_list_attr')
@blueprint.route(
    '/submetric_list/<int:query_type>/<int:val>/<db_name>/'
    '<path:metric_name>/<metric>/<int:mid>/<int:sub_count>/<int:only_attr>',
    methods=["GET"], endpoint='submetric_list_db_attr')
@login_required
@request_validator
@pem_connection
def submetric_list(query_type=-1, val=0, db_name=None,
                   metric_name=None, metric=None, mid=0,
                   sub_count=None, only_attr=0, pem_conn=None):
    """
    Return the child node items of metrics nodes in the available metrics tree
    control in capacity manager.

    Parameters:
        query_type  - (must) Type of query (agent level, server level, etc.) to
                            get metric item
        val      - (must) The values needed to define a given database object
        metric_name - (must) The name of metric to display as label
        metric      - (must) metric name for which the sub-metric node
                            information is required
        mid         - (must) Identifier of the given metric
    """
    sub_metrics_nodes = []

    sql = """SELECT probe_id FROM pem.probe_column
        WHERE internal_name = (%s)::text AND id = (%s)::int"""

    metric_name = unquote(metric_name)
    metric = unquote(metric)
    params = [metric, mid]
    status, pid = pem_conn.execute_scalar(sql, params)

    if not status or pid == '' or pid is None or pid == 'NULL':
        return internal_server_error(errormsg=gettext(
            "Error: unable to get id of the given probe."))

    sql = render_template('metrics/sql/get_probe_by_id.sql')
    params = [pid]
    status, probe_name = pem_conn.execute_scalar(sql, params)

    if not status or probe_name == '' or \
            probe_name is None or probe_name == 'NULL':
        return internal_server_error(errormsg=gettext(
            "Error: unable to get name of the given probe"))

    sql = render_template('metrics/sql/get_probe_columns.sql')
    status, col_name = pem_conn.execute_scalar(sql, params)

    if not status or col_name == '' or col_name is None or col_name == 'NULL':
        return internal_server_error(errormsg=gettext(
            "Error: unable to get primary column names of the given probe"))

    chart_params = ""
    sql = "SELECT "

    for i in range(0, len(col_name)):
        if (i == 0):
            sql += col_name[i]
        else:
            sql += "," + col_name[i]

    sql += " FROM pemdata." + probe_name + " WHERE "

    sub_metric_dict = {
        -1: {"sql": sql, "chart_params": chart_params},
        1: {
            "sql": sql + "agent_id = (%s)::int",
            "chart_params": chart_params + '{"(agent_id,%d)",'
        },
        2: {
            "sql": sql + "server_id = (%s)::int",
            "chart_params": chart_params + '{"(server_id,%d)",'
        },
        3: {
            "sql": sql + "server_id = (%s)::int AND database_name = "
                         "(%s)::text",
            "chart_params": chart_params +
            '{"(server_id,%d)","(database_name,%s)",'
        },
        4: {
            "sql": sql + """server_id = (%s)::int AND
             database_name = (%s)::text AND schema_name = (%s)::text""",
            "chart_params": chart_params +
            '{"(server_id,%d)","(database_name,%s)","(schema_name,%s)",'
        },
        5: {
            "sql": sql + """server_id = (%s)::int AND
            database_name = (%s)::text AND schema_name = (%s)::text AND
            table_name = (%s)::text""",
            "chart_params": chart_params
        },
        6: {
            "sql": sql + """server_id = (%s)::int AND
            database_name = (%s)::text AND schema_name = (%s)::text AND
            function_name = (%s)::text
                AND function_type = (%s)::char AND arg_types = (%s)::text"""
            if len(params) == 6
            else sql + """server_id = (%s)::int AND database_name = (%s)::text
                AND schema_name = (%s)::text AND package_name = (%s):: text
                AND function_name = (%s)::text AND function_type = (%s)::char
                AND arg_types = (%s)::text""",
            "chart_params": chart_params +
            '{"(server_id,%d)","(database_name,%s)","(schema_name,%s),'
            '"(function_name,%s)",'
        },
        7: {
            "sql": sql + """server_id = (%s)::int AND
            database_name = (%s)::text
                AND schema_name = (%s)::text AND index_name = (%s)::text""",
            "chart_params": chart_params +
            '{"(server_id,%d)","(database_name,%s)","(schema_name,%s),'
            '"(index_name,%s)",'
        },
        8: {
            "sql": sql + """server_id = (%s)::int AND
            database_name = (%s)::text
                AND schema_name = (%s)::text AND sequence_name = (%s)::text""",
            "chart_params": chart_params +
            '{"(server_id,%d)","(database_name,%s)","(schema_name,%s),'
            '"(sequence_name,%s)",'
        },
        9: {
            "sql": sql + """server_id = (%s)::int AND database_name =
            (%s)::text
                AND schema_name = (%s)::text AND function_name = (%s)::text
                AND function_type = (%s)::char AND arg_types = (%s)::text"""
            if len(params) == 6
            else sql + """server_id = (%s)::int AND database_name = (%s)::text
                AND schema_name = (%s)::text AND package_name = (%s)::text
                AND function_name = (%s)::text AND function_type = (%s)::char
                AND arg_types = (%s)::text""",
            "chart_params": chart_params +
            '{"(server_id,%d)","(database_name,%s)","(schema_name,%s),'
            '"(package_name,%s)",'
        },
        10: {
            "sql": sql + """server_id = (%s)::int AND database_name =
            (%s)::text
                AND schema_name = (%s)::text AND function_name = (%s)::text
                AND function_type = (%s)::char AND arg_types = (%s)::text"""
            if len(params) == 6
            else sql + """server_id = (%s)::int AND database_name = (%s)::text
                AND schema_name = (%s)::text AND package_name = (%s):: text
                AND function_name = (%s)::text AND function_type = (%s)::char
                AND arg_types = (%s)::text""",
            "chart_params": chart_params +
            '{"(server_id,%d)","(database_name,%s)", "(schema_name,%s),'
            '"(function_name,%s)",'
        },
        12: {
            "sql": sql + """server_id = (%s)::int AND database_name =
            (%s)::text
                AND schema_name = (%s)::text AND view_name = (%s)::text""",
            "chart_params": chart_params +
            '{"(server_id,%d)","(database_name,%s)","(schema_name,%s),'
            '"(view_name,%s)",'
        },
        14: {
            "sql": sql + """server_id = (%s)::int AND database_name =
            (%s)::text
                AND schema_name = (%s)::text AND view_name = (%s)::text""",
            "chart_params": chart_params +
            '{"(server_id,%d)","(database_name,%s)","(schema_name,%s),'
            '"(view_name,%s)",'
        },
    }
    sql = sub_metric_dict.get(query_type)["sql"]
    chart_params = sub_metric_dict.get(query_type)["chart_params"]

    sql += " ORDER BY "

    for i in range(0, len(col_name)):
        if (i == 0):
            sql += str(i + 1)
        else:
            sql += ", " + (str(i + 1))

    params = [val]
    if db_name:
        params.append(db_name)

    status, res = pem_conn.execute_dict(sql, params)
    if not status:
        return internal_server_error(errormsg=res)

    server_data = []
    for server in res['rows']:
        chart_params_server = chart_params

        # Use qtIdent function if metrics value contain comma (,)
        value_list = list(server.values())
        lastname = ''
        for m_val in value_list:
            lastname += driver().qtIdent(pem_conn, m_val) \
                if ',' in m_val else m_val
            if m_val.strip() != '':
                lastname += ','
        lastname = lastname[:-1]

        new_server_data = list(server_data)
        node_label = "{0}".format(lastname) if only_attr == 1 else (
            "{0} [{1}] + ".format(metric_name, lastname) if sub_count else
            "{0} [{1}]".format(metric_name, lastname)
        )

        for k, v in list(server.items()):
            chart_params_server += \
                '"(' + k + ',' \
                + (v.replace(',', '\\\\,') if v and ',' in v else v)\
                + ')",'

        chart_params_server = chart_params_server[0:len(chart_params_server
                                                        ) - 1] + "}"
        k = {
            'server_data': new_server_data,
            'label': node_label,
            'inode': False,
            'icon': "icon-metric",
            'checked': False,
            'node_data': server if server else "",
            'is_coll': False,
            'node_type': 'metrics',
            'type': 'metrics',
            'pdata': dict(),
            'query_type': query_type,
            'params': chart_params_server % val,
            '_id': str(uuid.uuid4())[1:6]
        }
        sub_metrics_nodes.append(k)

    return make_json_response(
        data=sub_metrics_nodes
    )


@blueprint.route('/metric_list', methods=["GET"])
@blueprint.route(
    '/metric_list/<int:query_type>/<int:agent_id>',
    methods=["GET"], endpoint='agent_metric_list')
@blueprint.route(
    '/metric_list/<int:query_type>/<int:agent_id>/<int:sid>',
    methods=["GET"], endpoint='server_metric_list')
@blueprint.route(
    '/metric_list/<int:query_type>/<int:agent_id>/<int:sid>/<path:dbname>',
    methods=["GET"], endpoint='db_metric_list')
@blueprint.route(
    '/metric_list/<int:query_type>/<int:agent_id>/<int:sid>/<path:dbname>/'
    '<path:schema>',
    methods=["GET"], endpoint='schema_metric_list')
@blueprint.route(
    '/metric_list/<int:query_type>/<int:agent_id>/<int:sid>/<path:dbname>/'
    '<path:schema>/<path:pkg_name>',
    methods=["GET"], endpoint='pkg_metric_list')
@blueprint.route(
    '/metric_list/<int:query_type>/<int:agent_id>/<int:sid>/<path:dbname>/'
    '<path:schema>/<path:pkg_name>/<path:pkg_function>',
    methods=["GET"], endpoint='pkg_func_metric_list')
@login_required
@request_validator
@pem_connection
def metric_list(query_type=-1, agent_id=0, sid=0, dbname=None, schema=None,
                pkg_name=None, pkg_function=None, pem_conn=None):
    """
    Return the child node items of available metrics tree control in capacity
    manager.
    Parameters:
        query_type - (must) type of query to fire to get node item.
        agent_id   - (must) The ID of the agent.
        sid        - (must) Server id.
        dbname     - (must) Name of database
        schema     - (must) Name of schema
        pkg_name   - (must) Type of db objects (table, functions, indexes etc).
    """
    metrics_nodes = []
    params = [agent_id]
    valArr = []
    if sid and query_type <= 15:
        valArr.append(sid)
    else:
        valArr.append(agent_id)
    if dbname:
        valArr.append(unquote(dbname))
    if schema:
        valArr.append(unquote(schema))
    if pkg_name:
        valArr.append(unquote(pkg_name))
    if pkg_function:
        valArr.append(unquote(pkg_function))
    in_string = ''
    cond = ''

    # Query Type mapping with Applies_to_ID and parameter 'value' length
    # Parameter value hardoded as the suppied value length and in-use length
    # is different.
    query_type_dict = {
        1: {'appl_to_id': 100, 'param_len': 1},
        2: {'appl_to_id': 200, 'param_len': 1},
        3: {'appl_to_id': 300, 'param_len': 2},
        4: {'appl_to_id': 400, 'param_len': 3},
        5: {'appl_to_id': 500, 'param_len': 4},
        6: {'appl_to_id': 800, 'param_len': 4},
        7: {'appl_to_id': 600, 'param_len': 4},
        8: {'appl_to_id': 700, 'param_len': 4},
        9: {'appl_to_id': 800, 'param_len': 4},
        10: {'appl_to_id': 800, 'param_len': 4},
        12: {'appl_to_id': 900, 'param_len': 4},
        14: {'appl_to_id': 900, 'param_len': 4}
    }

    if query_type not in query_type_dict or \
            'appl_to_id' not in query_type_dict[query_type]:
        return make_json_response(
            data=metrics_nodes
        )

    params.append(query_type_dict[query_type]['appl_to_id'])

    if len(valArr) < query_type_dict[query_type]['param_len']:
        return internal_server_error(
            errormsg=gettext("Invalid Parameter values."))

    for i in range(0, query_type_dict[query_type]['param_len']):
        j = i
        temp_arr = []
        for j in range(0, i + 1):
            temp_arr.append(valArr[j])

        params.append(temp_arr)

    # No of array to IN statement
    temp_in_string = '(%s)::text[],' * \
        int(query_type_dict[query_type]['param_len'])
    in_string = temp_in_string[0:len(temp_in_string) - 1]

    if query_type == 14:
        cond = 'AND NOT ptv.is_system_probe'

    sql = render_template('metrics/sql/list_metrics.sql',
                          data={'in_string': in_string, 'cond': cond})
    # Handling the list of mixed data types
    for i in range(2, len(params)):
        params[i] = list(map(str, params[i]))
    status, res = pem_conn.execute_dict(sql, params)
    if not status:
        return internal_server_error(errormsg=res)

    server_data = [query_type, agent_id]
    for server in res['rows']:
        new_server_data = list(server_data)
        new_server_data.append(server['name'])
        new_server_data.append(server['metric'])
        new_server_data.append(server['metric_id'])

        # Add metric node
        if server['pit_def']:
            server['pit'] = 'x'
            met_label = "{}".format(server['name']) if server else ""
            server['met_label'] = met_label
            n = {
                'server_data': new_server_data,
                'label': met_label,
                'inode': True if server['sub_count'] else False,
                'icon': "icon-metric",
                'checked': False,
                'node_data': server if server else "",
                'is_coll': True,
                'metric_info': {'met_label': met_label},
                'node_type': 'submetrics',
                'type': 'submetrics',
                'pdata': dict(),
                'query_type': query_type,
                '_id': str(uuid.uuid4())[1:6]
            }
            new_server_data.append(0)
            metrics_nodes.append(n)
        else:
            import copy
            metrics_data = list(new_server_data)
            temp_server_data = copy.deepcopy(server)
            if server['pit'] and server['discard']:
                met_label = "{}".format(server['name']) if server else ""
                server['met_label'] = met_label
                n = {
                    'server_data': new_server_data,
                    'label': met_label,
                    'inode': True if server['sub_count'] else False,
                    'icon': "icon-metric",
                    'checked': False,
                    'node_data': server if server else "",
                    'is_coll': True,
                    'metric_info': {'met_label': met_label},
                    'node_type': 'submetrics',
                    'type': 'submetrics',
                    'pdata': dict(),
                    'query_type': query_type,
                    '_id': str(uuid.uuid4())[1:6]
                }
                new_server_data.append(0)
                metrics_nodes.append(n)
            elif server['pit'] and not server['discard']:
                met_label = "{}".format(server['name']) if server else ""
                server['met_label'] = met_label
                n = {
                    'server_data': new_server_data,
                    'label': met_label,
                    'inode': True if server['sub_count'] else False,
                    'icon': "icon-metric",
                    'checked': False,
                    'node_data': server if server else "",
                    'is_coll': True,
                    'metric_info': {'met_label': met_label},
                    'node_type': 'submetrics',
                    'type': 'submetrics',
                    'pdata': dict(),
                    'query_type': query_type,
                    '_id': str(uuid.uuid4())[1:6]
                }
                new_server_data.append(0)
                metrics_nodes.append(n)

                temp_server_data['pit'] = False
                met_label = "{}+".format(server['name']) if server else ""
                temp_server_data['met_label'] = met_label
                m2 = {
                    'server_data': metrics_data,
                    'label': met_label,
                    'inode': True if server['sub_count'] else False,
                    'icon': "icon-metric",
                    'checked': False,
                    'node_data': temp_server_data if temp_server_data else "",
                    'is_coll': True,
                    'node_type': 'submetrics',
                    'type': 'submetrics',
                    'metric_info': {'met_label': met_label},
                    'pdata': dict(),
                    'query_type': query_type,
                    '_id': str(uuid.uuid4())[1:6]
                }
                metrics_data.append(server['sub_count'])
                metrics_nodes.append(m2)
            else:
                server['pit'] = False
                met_label = "{}+".format(server['name']) if server else ""
                server['met_label'] = met_label
                m3 = {
                    'server_data': metrics_data,
                    'label': met_label,
                    'inode': True if server['sub_count'] else False,
                    'icon': "icon-metric",
                    'checked': False,
                    'node_data': server if server else "",
                    'is_coll': True,
                    'node_type': 'submetrics',
                    'type': 'submetrics',
                    'metric_info': {'met_label': met_label},
                    'pdata': dict(),
                    'query_type': query_type,
                    '_id': str(uuid.uuid4())[1:6]
                }
                metrics_data.append(server['sub_count'])
                metrics_nodes.append(m3)

    return make_json_response(
        data=metrics_nodes
    )


@blueprint.route('/node_list', methods=["GET"])
@blueprint.route(
    '/node_list/<int:query_type>/<int:agent_id>',
    methods=["GET"], endpoint='agent_node_list')
@blueprint.route(
    '/node_list/<int:query_type>/<int:agent_id>/<int:sid>',
    methods=["GET"], endpoint='server_node_list')
@blueprint.route(
    '/node_list/<int:query_type>/<int:agent_id>/<int:sid>/<path:dbname>',
    methods=["GET"], endpoint='db_node_list')
@blueprint.route(
    '/node_list/<int:query_type>/<int:agent_id>/<int:sid>/'
    '<path:dbname>/<path:schema>',
    methods=["GET"], endpoint='schema_node_list')
@blueprint.route(
    '/node_list/<int:query_type>/<int:agent_id>/<int:sid>/'
    '<path:dbname>/<path:schema>/<path:pkg_name>',
    methods=["GET"], endpoint='pkg_node_list')
@login_required
@request_validator
@pem_connection
def node_list(query_type=-1, agent_id=0, sid=0, dbname=None, schema=None,
              pkg_name=None, pem_conn=None):
    """
    Return the child node items of available metrics tree control in capacity
    manager.

    Parameters:
        query_type - (must) type of query to fire to get node item.
        agent_id   - (must) The ID of the agent.
        sid        - (must) Server id.
        dbname     - (must) Name of database
        schema     - (must) Name of schema
        pkg_name   - (must) Type of db objects (table, functions, indexes etc).
    """

    servers = []
    params = {}
    res = None
    icon = 'server'
    node_name = 'schema_nodes'

    server_data = [query_type, agent_id]

    if sid:
        server_data.append(sid)
    if dbname:
        server_data.append(unquote(dbname))
    if schema:
        server_data.append(unquote(schema))
    if pkg_name:
        server_data.append(unquote(pkg_name))

    sql = "SELECT "

    count_sql1 = """
        SELECT
            count (distinct pc.display_name) FROM pem.probe_target_view ptv,
            pem.probe_column pc
        WHERE
            ptv.probe_id = pc.probe_id AND
            ptv.agent_id = (%(agent_id)s)::int4 AND ptv.applies_to_id ="""

    count_sql2 = """
        AND pc.classification != 'k' AND sql_data_type
        LIKE ANY (ARRAY['smallint%%', 'integer%%', 'bigint%%', 'decimal%%',
        'numeric%%', 'real%%', 'double precision%%'])
        AND NOT pc.sql_data_type LIKE E'%%[]'"""

    if query_type == -1:
        d = {
            'label': 'Agents',
            'server_data': [0, 0],
            'inode': True,
            'open': False,
            'branch': [],
            'icon': 'icon-coll-agent',
            'checked': False,
            'query_type': 0,
            'node_type': 'node',
            'checkbox': False,
            'is_coll': True,
            'pdata': dict(),
            'metric_info': {}
        }
        d2 = {
            'label': 'Remote Servers',
            'server_data': [13, 0],
            'inode': True,
            'open': False,
            'branch': [],
            'icon': 'icon-server_group',
            'checked': False,
            'query_type': 13,
            'node_type': 'node',
            'checkbox': False,
            'is_coll': True,
            'pdata': dict(),
            'metric_info': {}
        }
        servers.append(d)
        servers.append(d2)

        return make_json_response(
            data=servers
        )

    elif query_type != 0 and query_type != 1 and query_type != 13 and \
            query_type != 8:
        pass

    node_type = ""
    if query_type == 0:
        node_name = 'servers'
        icon = 'agent'
        node_type = 'agent'
        sql += """id As aid, description AS name FROM pem.avail_agents WHERE
        active = true ORDER BY description;"""

    elif query_type == 1:
        node_name = 'databases'
        icon = "server"
        node_type = 'server'
        params = {"agent_id": agent_id}
        sql += """b.id AS sid, b.description AS name, d.server_version_id AS
        type, (""" + count_sql1 + """ 200 """ + count_sql2 + """) AS count
        FROM
            pem.avail_agents a, pem.avail_servers b,
            pem.agent_server_binding c,
            pemdata.server_info d
        WHERE
            a.id = c.agent_id AND b.id = c.server_id AND b.id = d.server_id AND
            a.id = (%(agent_id)s)::int4 AND b.is_remote_monitoring = false
            ORDER BY b.description;"""

    elif query_type == 2:
        node_name = 'schemas'
        icon = "database"
        node_type = "database"
        # handle arguments which contains delimeters to converted to array
        params = {"agent_id": agent_id, "server_id": sid}

        ret_val, result, rest_param = \
            get_restricted_objects_clause(
                pem_conn, '(%(db_name)s)', 'b.database_name', 0, sid)

        if ret_val:
            result = " AND " + result
            params.update({"db_name": rest_param})

        sql += " b.database_name AS name, b.database_name AS dbname, " \
               "b.system_database AS sysdb, "
        sql += "(" + count_sql1 + "300" + count_sql2 + """) AS count
            FROM
                pem.agent_server_binding a, pemdata.oc_database b
            WHERE
                a.server_id = b.server_id AND b.connections_allowed = true """
        sql += result + """
        AND a.agent_id = (%(agent_id)s)::INT4 AND
        a.server_id = (%(server_id)s)::int4
        ORDER BY b.database_name;"""

    elif query_type == 3:
        node_name = 'schema_nodes'
        icon = "schema"
        node_type = "schema"
        params = {"agent_id": agent_id, "server_id": sid,
                  "db_name": dbname}

        # Always assume information_schema is a system schema, as PEM doesn't
        # collect info about views, so we have no additional confirmation
        # method available.
        sys_schema_sql = """
                    CASE WHEN (
                    (
                        schema_name = 'pg_catalog' AND
                        EXISTS (SELECT 1 FROM pemdata.oc_table WHERE
                            table_name = 'pg_class' AND
                            server_id = (%(server_id)s)::int4 AND
                            database_name = (%(db_name)s)::text
                        )
                    ) OR
                    (
                        schema_name = 'pgagent' AND
                        EXISTS (SELECT 1 FROM pemdata.oc_table WHERE
                            table_name = 'pga_job'
                            AND server_id = (%(server_id)s)::int4 AND
                            database_name = (%(db_name)s)::text
                        )
                    ) OR
                    ( schema_name = 'information_schema' ) OR
                    (
                        schema_name LIKE '_%%' AND
                        EXISTS (SELECT 1 FROM pemdata.oc_table WHERE
                            table_name = 'slonyversion' AND
                            server_id = (%(server_id)s)::int4 AND
                            database_name = (%(db_name)s)::text
                        )
                    ) OR
                    ( schema_name = 'dbo' OR schema_name = 'sys' )) THEN true
                    ELSE false
                    END
                    """

        ret_val, result, rest_param = \
            get_restricted_objects_clause(
                pem_conn, '(%(schema_name)s)', 'b.schema_name', 1, sid, dbname)

        if ret_val:
            result = " AND " + result
            # As this scenario never checked before with any test.
            # This should be 'schema_name' and not 'db_name'
            params.update({"schema_name": rest_param})

        sql += \
            "b.schema_name AS name, b.schema_name AS nspname,  (" + \
            sys_schema_sql + ") AS sys_schema, (" + \
            count_sql1 + " 400 " + count_sql2 + """) AS count
            FROM
                pem.agent_server_binding a, pemdata.oc_schema b
            WHERE
                a.server_id = b.server_id """ + result + """ AND
                a.agent_id = (%(agent_id)s)::int4 AND
                a.server_id = (%(server_id)s)::int4 AND
                b.database_name= (%(db_name)s)::text
            ORDER BY b.schema_name;"""

    elif query_type == 4:
        pass

    elif query_type == 5:
        node_name = 'table'
        icon = "table"
        node_type = "table"
        sql += """b.table_name AS name, (
            """ + count_sql1 + """ 500 """ + count_sql2 + """) AS count
            FROM pem.agent_server_binding a, pemdata.oc_table b
        WHERE
            a.server_id = b.server_id
            AND a.agent_id = (%(agent_id)s)::int4
            AND a.server_id = (%(server_id)s)::int4
            AND b.database_name = (%(db_name)s)::text
            AND b.schema_name = (%(schema_name)s)::text
        ORDER BY b.table_name;"""

        params = {"agent_id": agent_id, "server_id": sid,
                  "db_name": dbname, "schema_name": schema}

    elif query_type == 6:
        node_name = 'function'
        icon = "function"
        node_type = "function"
        if sid and dbname and schema and pkg_name is None:
            sql += """b.function_name as name, b.arg_types as show_args,
            (""" + count_sql1 + """ 800 """ + count_sql2 + """) as count
            FROM
                pem.agent_server_binding a, pemdata.oc_function b
            WHERE
                a.server_id = b.server_id
                AND a.agent_id = (%(agent_id)s)::int4
                AND a.server_id = (%(server_id)s)::int4
                AND b.database_name = (%(db_name)s)::text
                AND b.schema_name = (%(schema_name)s)::text
                AND b.package_name = ''
                AND b.function_type = '0'
            ORDER BY b.function_name;"""

            params = {"agent_id": agent_id, "server_id": sid,
                      "db_name": dbname, "schema_name": schema}

        else:
            sql += """b.function_name as name, b.arg_types as show_args,
            (""" + count_sql1 + """ 800 """ + count_sql2 + """) as count
            FROM
                pem.agent_server_binding a, pemdata.oc_function b
            WHERE
                a.server_id = b.server_id
                AND a.agent_id = (%(agent_id)s)::int4
                AND a.server_id = (%(server_id)s)::int4
                AND b.database_name = (%(db_name)s)::text
                AND b.schema_name = (%(schema_name)s)::text
                AND b.package_name = (%(package_name)s)::text
                AND b.function_type = '0'
            ORDER BY b.function_name;"""

            params = {"agent_id": agent_id, "server_id": sid,
                      "db_name": dbname, "schema_name": schema,
                      "package_name": pkg_name}

    elif query_type == 7:
        node_name = 'index'
        icon = "index"
        node_type = "index"
        sql += """b.index_name AS name, (""" + count_sql1 + """ 600 """ \
            + count_sql2 + """) AS count
        FROM
            pem.agent_server_binding a, pemdata.oc_index b
        WHERE
            a.server_id = b.server_id
            AND a.agent_id = (%(agent_id)s)::int4
            AND a.server_id = (%(server_id)s)::int4
            AND b.database_name = (%(db_name)s)::text
            AND b.schema_name = (%(schema_name)s)::text
        ORDER BY b.index_name;"""

        params = {"agent_id": agent_id, "server_id": sid,
                  "db_name": dbname, "schema_name": schema}

    elif query_type == 8:
        node_name = 'sequence'
        icon = "sequence"
        node_type = "sequence"
        sql += """b.sequence_name AS name, (""" + count_sql1 + \
            """ 700 """ + count_sql2 + """) AS count
        FROM
            pem.agent_server_binding a, pemdata.oc_sequence b
        WHERE
            a.server_id = b.server_id
            AND a.agent_id = (%(agent_id)s)::int4
            AND a.server_id = (%(server_id)s)::int4
            AND b.database_name = (%(db_name)s)::text
            AND b.schema_name = (%(schema_name)s)::text
        ORDER BY b.sequence_name;"""

        params = {"agent_id": agent_id, "server_id": sid,
                  "db_name": dbname, "schema_name": schema}

    elif query_type == 9:
        node_name = 'procedure'
        icon = "procedure"
        node_type = "procedure"
        if sid and dbname and schema and pkg_name is None:
            sql += """
            b.function_name as name, b.arg_types as show_args,
            (""" + count_sql1 + """ 800 """ + count_sql2 + """) as count
            FROM pem.agent_server_binding a, pemdata.oc_function b
            WHERE
                a.server_id = b.server_id
                AND a.agent_id = (%(agent_id)s)::int4
                AND a.server_id = (%(server_id)s)::int4
                AND b.database_name = (%(db_name)s)::text
                AND b.schema_name = (%(schema_name)s)::text
                AND b.package_name = ''
                AND b.function_type = '1'
            ORDER BY b.function_name;"""

            params = {"agent_id": agent_id, "server_id": sid,
                      "db_name": dbname, "schema_name": schema}
        else:
            sql += """
            b.function_name as name, b.arg_types as show_args,
            (""" + count_sql1 + """ 800 """ + count_sql2 + """) as count
            FROM
                pem.agent_server_binding a, pemdata.oc_function b
            WHERE
                a.server_id = b.server_id
                AND a.agent_id = (%(agent_id)s)::int4
                AND a.server_id = (%(server_id)s)::int4
                AND b.database_name = (%(db_name)s)::text
                AND b.schema_name = (%(schema_name)s)::text
                AND b.package_name = (%(package_name)s)::text
                AND b.function_type = '1'
            ORDER BY b.function_name;"""

            params = {"agent_id": agent_id, "server_id": sid,
                      "db_name": dbname, "schema_name": schema,
                      "package_name": pkg_name}

    elif query_type == 10:
        node_name = 'trigger_function'
        icon = "trigger_function"
        node_type = "triggerfunctions"
        if sid and dbname and schema and pkg_name is None:
            sql += """
            b.function_name as name, b.arg_types as show_args,
            (""" + count_sql1 + """ 800 """ + count_sql2 + """) as count
            FROM
                pem.agent_server_binding a, pemdata.oc_function b
            WHERE
                a.server_id = b.server_id
                AND a.agent_id = (%(agent_id)s)::int4
                AND a.server_id = (%(server_id)s)::int4
                AND b.database_name = (%(db_name)s)::text
                AND b.schema_name = (%(schema_name)s)::text
                AND b.package_name = ''
                AND b.function_type = '2'
            ORDER BY b.function_name;"""
            params = {"agent_id": agent_id, "server_id": sid,
                      "db_name": dbname, "schema_name": schema}
        else:
            sql += """
            b.function_name as name, b.arg_types as show_args,
            (""" + count_sql1 + """ 800 """ + count_sql2 + """) as count
            FROM
                pem.agent_server_binding a, pemdata.oc_function b
            WHERE
                a.server_id = b.server_id
                AND a.agent_id = (%(agent_id)s)::int4
                AND a.server_id = (%(server_id)s)::int4
                AND b.database_name = (%(db_name)s)::text
                AND b.schema_name = (%(schema_name)s)::text
                AND b.package_name = (%(package_name)s)::text
                AND b.function_type = '2'
            ORDER BY b.function_name;"""

            params = {"agent_id": agent_id, "server_id": sid,
                      "db_name": dbname, "schema_name": schema,
                      "package_name": pkg_name}

    elif query_type == 11:
        node_name = 'package'
        icon = "package"
        node_type = "package"
        sql += """distinct(b.package_name) as name,
        b.package_name as package_name,
        0::integer as count
        FROM
            pem.agent_server_binding a, pemdata.oc_function b
        WHERE
            a.server_id = b.server_id
            AND a.agent_id = (%(agent_id)s)::int4
            AND a.server_id = (%(server_id)s)::int4
            AND b.database_name = (%(db_name)s)::text
            AND b.schema_name = (%(schema_name)s)::text
            AND not b.package_name = ''
        ORDER BY b.package_name;"""

        params = {"agent_id": agent_id, "server_id": sid,
                  "db_name": dbname, "schema_name": schema}

    elif query_type == 12:
        node_name = 'view'
        icon = "mview"
        node_type = "mview"
        sql += """b.view_name AS name, (""" + count_sql1 + \
            """ 900 """ + count_sql2 + """) AS count
        FROM
            pem.agent_server_binding a, pemdata.oc_views b
        WHERE
            a.server_id = b.server_id
            AND a.agent_id = (%(agent_id)s)::int4
            AND a.server_id = (%(server_id)s)::int4
            AND b.database_name = (%(db_name)s)::text
            AND b.schema_name = (%(schema_name)s)::text
            AND b.view_type = 'm'
        ORDER BY b.view_name;"""

        params = {"agent_id": agent_id, "server_id": sid,
                  "db_name": dbname, "schema_name": schema}

    elif query_type == 13:
        node_name = 'databases'
        node_type = "server"
        server_data[0] = 2
        sql += """
        b.id AS sid, b.description AS name, d.server_version_id AS type,
        c.agent_id AS agent, c.agent_id AS aid,
        (""" + count_sql1 + """ 200 """ \
            + count_sql2 + """) AS count
        FROM
            pem.avail_servers b, pem.agent_server_binding c,
            pemdata.server_info d
        WHERE
            b.id = c.server_id
            AND b.id = d.server_id
            AND b.is_remote_monitoring = true
        ORDER BY b.description;"""

        params = {"agent_id": agent_id}

    elif query_type == 14:
        node_name = 'view'
        icon = "view"
        node_type = "view"
        sql += """b.view_name AS name, (""" + count_sql1 + """ 900 """ + \
            count_sql2 + """) AS count
        FROM
            pem.agent_server_binding a, pemdata.oc_views b
        WHERE
            a.server_id = b.server_id
            AND a.agent_id = (%(agent_id)s)::int4
            AND a.server_id = (%(server_id)s)::int4
            AND b.database_name = (%(db_name)s)::text
            AND b.schema_name = (%(schema_name)s)::text
            AND b.view_type = 'v'
        ORDER BY b.view_name;"""

        params = {"agent_id": agent_id, "server_id": sid,
                  "db_name": dbname, "schema_name": schema}

    status, res = pem_conn.execute_dict(sql, params)
    if not status:
        return internal_server_error(errormsg=res)

    for server in res['rows']:
        pdata = OrderedDict()
        # Copy the orignial data to new list
        new_server_data = list(server_data)
        server['version'] = server['type'] if 'type' in server else -1
        node_icon = "icon-{0}".format(icon)
        server['type'] = icon
        server['data'] = {}
        chart_params = '{'
        if 'aid' in server:
            new_server_data[1] = server['data']['aid'] = server['aid']
            pdata['agent_id'] = [server['aid'], server['name']]
            chart_params += '"(agent_id,%d)",' % server['aid']
        if server and 'sid' in server:
            if len(server_data) == 3:
                new_server_data[2] = server['sid']
            else:
                new_server_data.append(server['sid'])
            server['data']['sid'] = server['sid']
            pdata['server_id'] = [server['sid'], server['name'],
                                  server['version']]
            chart_params += '"(server_id,%d)",' % server['sid']
        elif 'dbname' in server:
            if len(server_data) == 4:
                new_server_data[3] = server['dbname']
            else:
                new_server_data.append(server['dbname'])
            server['data']['dbname'] = server['dbname']
            pdata['database_name'] = [server['dbname'], server['dbname']]
            chart_params += '"(server_id,%d)","(database_name,%s)",' %\
                            (sid, server['dbname'])
            node_icon = 'pg-icon-database'
        elif 'nspname' in server:
            if len(server_data) == 5:
                new_server_data[4] = server['nspname']
            else:
                new_server_data.append(server['nspname'])
            server['data']['nspname'] = server['nspname']
            pdata['schema_name'] = [server['name'], server['name']]
            chart_params += '"(server_id,%d)","(database_name,%s)",' \
                            '"(schema_name,%s)",' %\
                            (sid, dbname, server['nspname'])
        elif 'package_name' in server:
            if len(server_data) == 6:
                new_server_data[5] = server['package_name']
            else:
                new_server_data.append(server['package_name'])
            server['data']['pkg_name'] = server['package_name']
            pdata['package_name'] = [server['name'], server['name']]

        # If server_data count is 5, it is schema->function, otherwise
        # it is schema->package->function, procedure or trigger function
        if len(server_data) == 5 or len(server_data) == 6 and 'name' in server:
            temp_server_name = server['name']
            temp_type = '{0}_name'.format(server['type'])
            pdata_key = temp_type
            if 'show_args' in server:
                pdata_key = 'function_name'
                # Create label for function with and without arguments
                server['name'] = '{0}({1})'.format(server['name'],
                                                   server['show_args'])
                pdata[pdata_key] = \
                    [server['name'], temp_server_name, server['show_args'],
                     server['show_args']
                     ]
            else:
                pdata[pdata_key] = [server['name'], server['name']]
            new_server_data.append(server['name'])
            server['data'][server['type']] = server['name']

            # If node is inside package, add it
            if pkg_name:
                pdata[pdata_key].append(pkg_name)

            chart_params += '"(server_id,%d)","(database_name,%s)",' \
                            '"(schema_name,%s)","(%s_name,%s)",' %\
                            (sid, dbname, schema, server["type"],
                             server["name"])

        chart_params = chart_params[0:len(chart_params) - 1] + "}"

        k = {
            'server_data': new_server_data,
            'label': "{}".format(server['name']) if server else "",
            'inode': True,
            'icon': node_icon,
            'checked': False,
            'node_type': 'node',
            'params': chart_params,
            'node_data': server if server else "",
            'is_coll': False,
            'checkbox': False,
            'node_name': node_name,
            'pdata': pdata,
            'type': node_type
        }
        servers.append(k)

    return make_json_response(
        data=servers
    )


@blueprint.route('/no_node', methods=["GET"], endpoint='no_node')
@login_required
@pem_connection
def no_node(pem_conn=None):
    return make_json_response(
        data=[]
    )


@blueprint.route("/list_templates", methods=["GET"], endpoint='list_templates')
@login_required
@pem_connection
def list_templates(pem_conn=None):
    """Return a list of capacity manager templates."""
    sql = render_template('metrics/sql/list_templates.sql')
    status, templates = pem_conn.execute_dict(sql)

    if not status:
        return internal_server_error(errormsg=templates)

    list_nodes = {}
    template_nodes = []
    parent_node = {
        'label': "Templates",
        '_label': "Templates",
        'inode': True,
        'icon': "icon-folder",
        'branch': [],
        'checkbox': False,
        'selectable': True,
        'type': 'folder',
        'open': True,
        'data': []
    }

    list_nodes[0] = parent_node
    template_nodes.append(parent_node)
    for t in templates['rows']:
        if t['parent_id'] is None:
            if t['template_name'] is not None:
                child_nodes = {
                    'label': t['template_name'],
                    '_label': t['template_name'],
                    'inode': False,
                    'icon': "icon-favourite",
                    'branch': [],
                    'checkbox': False,
                    'data': t,
                    'type': 'item',
                    'open': True
                }
                parent_node['branch'].append(child_nodes)
            else:
                parent_node['inode'] = False
        else:
            if t['id'] not in list_nodes:
                sub_child_node = {
                    'label': t['title'],
                    '_label': t['title'],
                    'inode': False,
                    'icon': "icon-folder",
                    'branch': [],
                    'checkbox': False,
                    'data': t,
                    'type': 'folder'
                }
                if t['template_id'] is not None:
                    sub_child_branch = {
                        'label': t['template_name'],
                        '_label': t['template_name'],
                        'inode': False,
                        'icon': "icon-favourite",
                        'branch': [],
                        'checkbox': False,
                        'data': t,
                        'type': 'item'
                    }

                    sub_child_node['branch'].append(sub_child_branch)
                    sub_child_node['inode'] = True
                list_nodes[t['id']] = sub_child_node
                list_nodes[t['parent_id']]['inode'] = True
                list_nodes[t['parent_id']]['branch'].append(sub_child_node)
            else:
                if t['template_id'] is not None:
                    sub_child_branch = {
                        'label': t['template_name'],
                        '_label': t['template_name'],
                        'inode': False,
                        'icon': "icon-favourite",
                        'branch': [],
                        'checkbox': False,
                        'data': t,
                        'type': 'item'
                    }
                    list_nodes[t['id']]['inode'] = True
                    list_nodes[t['id']]['branch'].append(sub_child_branch)

    return make_json_response(
        data=template_nodes,
        status=200
    )


@blueprint.route("/update_templates", methods=["POST"],
                 endpoint='update_templates')
@login_required
@pem_connection
def update_templates(pem_conn=None):
    """Update Templates."""
    pem_conn.execute_void("BEGIN;")

    if request.data:
        data = json.loads(request.data.decode('utf-8'))
    else:
        data = request.args or request.form

    # Process list of folders to add
    if (len(data['add_folder_list'])):
        parent_rel = {}
        for i, item in enumerate(data['add_folder_list']):
            folder_name = item['title']
            folderinfo = int(item['id'])
            pid = int(item['pid'])
            params = []

            if (pid < 10000):
                params.append(pid)
            else:
                if len(parent_rel) > 0:
                    params.append(parent_rel[pid])
                else:
                    params.append(0)

            params.append(folder_name)

            sql = render_template('metrics/sql/add_template_path.sql')
            pem_conn.execute_void(sql, params)

            if folderinfo >= 10000:
                status, newid = pem_conn.execute_scalar(
                    "SELECT currval('pem.cm_template_path_id_seq')")
                if newid == '' or newid is None or newid == 'NULL':
                    return internal_server_error(
                        errormsg=str(
                            "Error: Unable to get the "
                            "pem.cm_template_path_id_seq current value")
                    )
                parent_rel[folderinfo] = newid

    # Process list of template folders to rename
    if (len(data['ren_folder_list'])):
        for i, item in enumerate(data['ren_folder_list']):
            sql = """UPDATE pem.cm_template_path
                SET title = (%s)::text WHERE id = (%s)::int4"""
            pem_conn.execute_void(sql, [item['title'], item['id']])

    # Process list of template folders to delete
    if (len(data['del_folder_list'])):
        params = []
        sql = "DELETE FROM pem.cm_template_path WHERE "
        for i, item in enumerate(data['del_folder_list']):
            sql += "id = (%s)::int4"
            if (i != (len(data['del_folder_list']) - 1)):
                sql += " OR "
            params.append(item['id'])
        pem_conn.execute_void(sql, params)

    # Process list of template to rename
    if (len(data['ren_template_list'])):
        for i, item in enumerate(data['ren_template_list']):
            sql = """UPDATE pem.cm_template
                SET name = (%s)::text WHERE id = (%s)::int4"""
            pem_conn.execute_void(sql, [item['title'], item['id']])

    # Process list of template to delete
    if (len(data['del_template_list'])):
        for i, item in enumerate(data['del_template_list']):
            sql = "DELETE FROM pem.cm_template WHERE id = (%s)::int4"
            pem_conn.execute_void(sql, [item['id']])

    pem_conn.execute_void("COMMIT;")

    return make_json_response(
        data={
            'msg': gettext('Template saved successfully.')
        }
    )


@blueprint.route("/add_template", methods=["POST"], endpoint='add_template')
@login_required
@pem_connection
def add_template(pem_conn=None):
    pem_conn.execute_void("BEGIN;")
    params = []

    try:
        if request.data:
            req_data = json.loads(request.data.decode('utf-8'))
        else:
            req_data = request.args or request.form
    except Exception as e:
        return internal_server_error(errormsg=str(e))

    # folder id
    folder_id = req_data.get('tid')
    params.append(folder_id)

    # name
    name = req_data.get('template_name')
    params.append(name)

    # metrices
    metrices = json.loads(req_data.get('metrices'))
    metric_count = len(metrices)

    # aggregation
    aggregation = req_data.get('aggregation', 'FIRST')

    # check if the template already exists; if so delete and then we can
    # add a new one; this updates the existing template
    status, exists_template = \
        pem_conn.execute_scalar(
            """SELECT EXISTS (
                SELECT 1 FROM pem.cm_template
                WHERE name=(%s)::text AND folder_id=(%s)::int4)""",
            [name, folder_id])
    if exists_template:
        pem_conn.execute_void(
            """DELETE FROM pem.cm_template
                WHERE name=(%s)::text AND folder_id=(%s)::int4""",
            [name, folder_id])

    sql_start = """INSERT INTO pem.cm_template
        (folder_id, name, individual_report, time_period, """
    sql_values = """VALUES
        ((%s)::int4, (%s)::text, (%s)::boolean, (%s)::pem.cm_time_period,
        """

    # individual report
    chart_style = req_data.get('chart_style')
    individual_report = "false"
    if chart_style == 1:
        individual_report = "true"
    params.append(individual_report)

    # time period and its values
    tp = int(req_data.get('time_period'))
    thres_idx = req_data.get('threshold_index')
    thres_opr = req_data.get('threshold_opr')
    thres_val = int(req_data.get('threshold_value')) if \
        req_data.get('threshold_value') else None
    # historical days and extrapolated days
    historical = req_data.get('historical_days')
    extrapolated = req_data.get('extrapolated_days')
    # start date and end date
    st_date = req_data.get('start_time')
    ed_date = req_data.get('end_time')
    if tp == 0:
        time_period = "START_DATE_TO_END_DATE"
        params.append(time_period)

        sql_start += "start_date, end_date, "
        sql_values += "(%s)::timestamptz, (%s)::timestamptz, "

        params.append(st_date)
        params.append(ed_date)
    elif tp == 1:
        time_period = "START_DATE_TO_THREHOLD"
        params.append(time_period)

        sql_start += """
            start_date, threshold_index, threshold_opr, threshold_value,
            """
        sql_values += """
            (%s)::timestamptz, (%s)::int4, (%s)::pem.cm_threshold_operator,
            (%s)::numeric,"""

        params.append(st_date)
        params.append(thres_idx)
        params.append(thres_opr)
        params.append(thres_val)
    elif tp == 2:
        time_period = "HISTORIC_DATE_TO_EXTRAPOLATED_DATE"
        params.append(time_period)

        sql_start += "historical_days, extrapolated_days, "
        sql_values += "(%s)::int4, (%s)::int4, "

        params.append(historical)
        params.append(extrapolated)
    else:
        time_period = "HISTORIC_DATE_TO_THRESHOLD"
        params.append(time_period)

        sql_start += """
            historical_days, threshold_index, threshold_opr,
            threshold_value, """
        sql_values += """
            (%s)::int4, (%s)::int4, (%s)::pem.cm_threshold_operator,
            (%s)::numeric, """

        params.append(historical)
        params.append(thres_idx)
        params.append(thres_opr)
        params.append(thres_val)

    # report types, report location and report values
    sql_start += "report_type, output_loc"
    sql_values += "(%s)::pem.cm_report_type, (%s)::pem.cm_output_loc"

    r_type = req_data.get('chart_type')
    r_loc = req_data.get('download_file')

    report_type = "GRAPH"
    if r_type == 1:
        report_type = "TABLE"
    elif r_type == 2:
        report_type = "GRAPH_AND_TABLE"

    params.append(report_type)

    report_loc = "NEW_TAB"
    if r_loc == 1:
        report_loc = "PREV_TAB"
    elif r_loc == 2:
        report_loc = "FILE"
    params.append(report_loc)

    if r_loc == 2:
        sql_start += ", output_value"
        sql_values += ", (%s)::text"

        report_val = req_data.get('destination_file')
        params.append(report_val)

    sql_start += ")"
    sql_values += ")"

    sql = sql_start + sql_values

    pem_conn.execute_void(sql, params)

    if metric_count != 0:
        status, newid = pem_conn.execute_scalar(
            "SELECT currval('pem.cm_template_id_seq')")
        if newid == '' or newid is None or newid == 'NULL':
            return internal_server_error(
                errormsg=str(gettext(
                    "Error: Unable to get the "
                    "pem.cm_template_id_seq \n current value"))
            )

        sql = """INSERT INTO pem.cm_template_metrics (
            template_id, metric_id, metric_name, metric_disp_name,
            metric_agent_id, metric_target_attributes,
            metric_target_values, metric_calculate_pit,
            metric_unit, metric_server_type, metric_query_type,
            metric_object, metric_aggregation) VALUES """

        params = []

        for key, row in enumerate(metrices):
            metric_data = row['metric_info']

            sql += """
                ((%s)::int4 , (%s)::int4, (%s)::text, (%s)::text,
                (%s)::int4, (%s)::text, (%s)::text, (%s)::text,
                (%s)::text, (%s)::text, (%s)::int4, (%s)::text,
                (%s)::pem.cm_metric_aggregation)"""

            if key != (metric_count - 1):
                sql += ", "

            params.append(newid)
            params.append(metric_data['metric_id'])
            params.append(metric_data['metric'])
            params.append(metric_data['met_label'])
            # params.append(row['pdata']['agent_id'][0]) #TODO
            params.append(1)
            params.append(','.join(row['met_keys']))

            # Use qtIdent function if metrics value contain comma (,)
            met_values = ''
            for m_val in row['met_values']:
                met_values += \
                    driver().qtIdent(pem_conn, m_val) if (
                        ',' in m_val) else m_val
                met_values += ','
            met_values = met_values[:-1]
            params.append(met_values)

            params.append(metric_data['pit'])
            params.append(metric_data['unit'])
            params.append(metric_data['version'] if 'version' in metric_data
                          else -1)
            params.append(row['query_type'])
            params.append(metric_data['metric_object'])

            if aggregation.upper() == "AVG":
                params.append("AVERAGE")
            elif aggregation.upper() == "MAX":
                params.append("MAXIMUM")
            elif aggregation.upper() == "MIN":
                params.append("MINIMUM")
            else:
                params.append("FIRST")

        pem_conn.execute_void(sql, params)

    pem_conn.execute_void("COMMIT;")

    status, curr_id = pem_conn.execute_scalar(
        "SELECT currval('pem.cm_template_id_seq') AS curr_id")

    if not status:
        return internal_server_error(errormsg=str(curr_id))

    return make_json_response(
        data={
            'curr_id': curr_id,
            'msg': gettext('Template saved successfully.')
        }
    )


@blueprint.route("/get_template/<int:tid>", methods=["GET"],
                 endpoint='get_template')
@login_required
@request_validator
@pem_connection
def get_template(tid, pem_conn=None):
    """ Return template details based on given id """
    sql = render_template('metrics/sql/get_template.sql')
    status, res = pem_conn.execute_dict(sql, [tid])
    if not status:
        return internal_server_error(errormsg=res)

    return make_json_response(
        data=res['rows']
    )
