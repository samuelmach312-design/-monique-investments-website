##########################################################################
#
# Postgres Enterprise Manager
#
# Copyright (C) 2016 - 2025, EnterpriseDB Corporation. All rights reserved.
#
##########################################################################
""" Implements utility module for chart functionality """

import json
from collections import OrderedDict

from flask.views import View
from flask_babel import gettext
from flask import current_app, request, render_template

from pgadmin.pem.monitor.utils import DashboardLevel
from pgadmin.utils.ajax import make_json_response, internal_server_error
from pgadmin.pem.monitor.dashboard.utils import DashboardTransaction
from pgadmin.pem.utils import ChartMetricParam, pem_connection, \
    show_system_objects, execute_iterator
from pgadmin.pem.monitor.dashboard.helpers.chart import \
    get_chart_probe_dependency
from pgadmin.pem.monitor.dashboard.utils.generate_table_chart_data \
    import generate_json_for_table_chart
from pgadmin.pem.misc.error import error_return, PEMErrorType, \
    PEMChartStatus
from pgadmin.utils.driver import get_driver
from config import PG_DEFAULT_DRIVER
from pgadmin.utils.ajax import bad_request


class ChartViewMeta(type):
    """
      This class is responsible for registering each chart type.
      Any class inherited from this class will call its __init__
      method with name and attributes of base class.
      It uses _classes private variable to hold classes which is
      used to automagically register chart/graph classes as view
      from the 'charts/__init__.py'.
    """
    _classes = dict()

    def __init__(cls, name, bases, d):
        # Register type of chart/graph, based on the chart/graph name
        # Avoid registering the ChartMetaClass itself
        if name != 'ChartView':
            ChartViewMeta._classes[name.lower()] = cls

    @classmethod
    def classes(cls):
        return cls._classes

    @classmethod
    def load_classes(cls):
        """
        Import all chart and graph modules first so that
        they are available for registering as view
        """
        from importlib import import_module
        from werkzeug.utils import find_modules

        for module_name in find_modules(__package__, True):
            import_module(module_name)


class ChartView(View, metaclass=ChartViewMeta):
    """
    This class has utility functions for all charts like bar,line tablegraph
    etc..
    Some functions like initialize chart settings, get_chart_settings,
    set_settings_for_chart called from child classes of ChartView
    """
    chart_label = None
    chart_type = None
    suffix = None
    methods = None
    nodes = [
        {'name': 'system', 'url': 'system'},
        {'name': 'agent', 'url': 'agent/<int:aid>'},
        {'name': 'server', 'url': 'server/<int:sid>'},
        {'name': 'database', 'url': 'server/<int:sid>/database/<database>'}
    ]

    def __init__(self, *args, **kwargs):
        super(ChartView, self).__init__()
        self.level = None
        self.did = None
        self.cid = None
        self.aid = None
        self.sid = None
        self.database = None
        self.schema = None
        self.table = None
        self.trans_id = None
        self.operation = kwargs['operation']
        self.show_system_objects = show_system_objects()
        self.is_server_remotely_monitored = None

    def initialize(self, chart_type, pem_conn, *args, **kwargs):
        """
        This function initialize charts settings parameters like
        dep_probes_params, dep_probes_warning, name, levels etc..
        :param self: BartChart class instance
        :param chart_type: chart type
        :param pem_conn: pem database connection
        :param args: arguments
        :param kwargs: keyword arguments
        :return: None
        """
        self.dashboard_transaction = DashboardTransaction(
            self.trans_id, pem_conn.conn_id, self.did, self.cid
        )

        if chart_type != 'text':
            if self.sid is not None:
                self.is_remotely_monitored_server = \
                    self.is_remotely_monitored_server()

        # Dependent probes
        self.dep_probes_params = {}
        self.dep_probes_warning = ""
        self.ret_status = PEMChartStatus.SUCCESS

        res = ChartView.fetch_chart_info(self, pem_conn, chart_type)
        for resp in res.get('rows'):
            self.chart = resp  # We need only the first row.
            break

        self.ctype = self.chart['type']  # Type of the chart
        self.name = self.chart['name']  # Display name of the chart
        self.levels = self.chart['levels']  # Levels
        self.required_params = self.chart['required_parameters']

        labels = self.chart['labels']
        self.labels = {}
        if labels:
            self.labels = {i: labels[i] for i in range(0, len(labels))}

        # Function based chart probe dependency list
        self.dep_probes = tuple(self.chart['dep_probes']) \
            if self.chart['dep_probes'] is not None else None

        self.levels = [int(d) for d in self.levels]
        self.levels.sort(reverse=True)

        if chart_type not in ['cmline', 'cmtable']:
            self.lowest_supported_level = self.levels[-1]
            if self.level < self.lowest_supported_level:
                error_return(
                    gettext(
                        "Not enough information is available to"
                        " render this chart - {0}"
                    ).format(self.name), e_type=PEMErrorType.JSON,
                    status_code=503
                )

        self.settings = self.get_chart_settings(**kwargs)
        self.settings['timeout'] = \
            int(float(self.settings.get('timeout', 30))) * 1000

    def get_chart_settings(self, pem_conn, chart_type):
        """
        This function gets the chart settings
        :param pem_conn: pem database connection
        :param chart_type: chart type
        :return: chart settings (res)
        """
        sql = render_template(
            'charts/sql/{0}/get_settings.sql'.format(chart_type)
        )

        # Keeping did as -1 and other params like objid, database,
        # schema and table as None to remove the support of chart
        # setting per dashboard
        objid = None
        params = {
            "cid": self.cid, "did": -1,
            "objid": objid, "database": None,
            "schema": None, "tbl": None,
            "level": self.level
        }

        status, db_res = pem_conn.execute_2darray(sql, params)

        if not status or db_res is None or len(db_res) == 0:
            error_return(
                gettext(
                    "Couldn't find the chart settings for this chart."
                ), PEMErrorType.JSON, status_code=503
            )

        res = {}
        idx = 0
        for row in db_res['rows']:
            if idx == 0:
                res['type'] = row['type']
                res['timeout'] = row['timeout']
                res['did'] = row['did']
                res['level'] = row['level']

                if chart_type in ['line', 'cmline']:
                    res['span'] = row['span']
                    res['espan'] = row['espan']
                    if row['points'] is not None:
                        res['points'] = row['points']

                if row['downloadformat']:
                    res['downloadformat'] = row['downloadformat']

                # Fetch all the labels and store them in result.
                res['labels'] = {}
                if row['labels']:
                    for i in range(0, len(row['labels'])):
                        res['labels'][i] = row['labels'][i]

                # Check default colors returned by the query and also check
                # number of labels and number of default colors must be same
                res['colors'] = {}
                if row['default_colors'] and row['labels'] and \
                        len(row['labels']) == len(row['default_colors']):
                    for i in range(0, len(row['labels'])):
                        res['colors'][row['labels'][i]] = \
                            row['default_colors'][i]

                # Check if color is changed by the user if it is then
                # update the color with the changed value.
                if row['clname']:
                    res['colors'][row['clname']] = row['clval']
                    # cleaned_clname = row['clname'].strip("'")
                    # res['colors'][cleaned_clname] = row['clval']

                idx += 1
            elif chart_type in ['line', 'cmline', 'pie']:
                if res['type'] != 'TB':
                    if row['clname']:
                        res['colors'][row['clname']] = row['clval']
                        # cleaned_clname = row['clname'].strip("'")
                        # res['colors'][cleaned_clname] = row['clval']
            else:
                if row['clname']:
                    res['colors'][row['clname']] = row['clval']
                    # cleaned_clname = row['clname'].strip("'")
                    # res['colors'][cleaned_clname] = row['clval']
        return res

    def set_settings_for_chart(self, req, level, pem_conn):
        """
        This function sets the charts parameters like span, points,
        download_format etc.
        :param self: BartChart class instance
        :param pem_conn: pem database connection
        :param req: request object
        :param level: chart level
        :return: JSON response or error
        """
        timeout = None
        obj_id = self.get_obj_id()

        span = req.get('span') if 'span' in req else None
        espan = req.get('espan') if 'espan' in req else None
        points = req.get('points') if 'points' in req else None
        did = req.get('did') if 'did' in req else self.did
        download_format = req.get('downloadformat') \
            if 'downloadformat' in req else None
        colors = req.get('colors') if 'colors' in req else dict()
        delete = req.get('delete') if 'delete' in req else None
        if delete is None or delete != '1':
            if 'timeout' in req:
                timeout = req.get('timeout')
            else:
                return bad_request(
                    errormsg=gettext(
                        "Could not find the required parameter (timeout)."
                    )
                )
            if colors and isinstance(colors, str):
                try:
                    colors = json.loads(colors)
                except Exception:
                    colors = dict()
            res_colors = []
            for key, value in list(colors.items()):
                res_colors.append(ChartMetricParam(str(key), value))
            colors = res_colors

        params = {
            'cid': self.cid,
            'did': did,
            'level': level,
            'objid': None,
            'database': None,
            'schema': None,
            'tbl': None,
        }

        if level == 50:
            template = 'charts/sql/delete_config_system.sql'
        elif level == 100 or level == 200:
            params['objid'] = obj_id
            template = 'charts/sql/delete_config_object.sql'
        else:
            params['objid'] = obj_id
            params['database'] = self.database
            template = 'charts/sql/delete_config_database.sql'

        sql = render_template(template)
        status, res = pem_conn.execute_void(sql, params)
        if not status:
            return internal_server_error(errormsg=res)

        if delete is None and delete != '1':
            params.update({
                'reload': timeout, 'colors': colors, 'span': span,
                'espan': espan, 'points': points,
                'sort_seq': None,
                'download_format': download_format,
                'show_ack_alerts': None
            })

            sql = render_template(
                "charts/sql/insert_settings.sql"
            )

            status, res = pem_conn.execute_void(sql, params)
            if not status:
                return internal_server_error(errormsg=res)

        return make_json_response(
            info=gettext('Settings saved successfully.')
        )

    def fetch_chart_info(self, pem_conn, chart_type):
        """
        This function fetches the chart information from info.sql
        :param pem_conn: pem database connection
        :param chart_type: chart type
        :return: chart information
        """
        with self.dashboard_transaction:
            sql = render_template("charts/sql/{0}/info.sql".format(chart_type),
                                  cid=self.cid, conn=pem_conn)
            status, res = pem_conn.execute_dict(sql)
            if not status:
                current_app.logger.error(
                    "Error executing query: {0}".format(res)
                )
                error_return(
                    gettext("Error executing query: {0}").format(res),
                    e_type=PEMErrorType.JSON, status_code=500
                )

        if len(res) == 0:
            current_app.logger.warning(
                "Couldn't find the information of the "
                "chart (id#{0}) in the database.".format(
                    self.cid
                )
            )
            error_return(
                gettext(
                    "Couldn't find the information of the "
                    "chart in the database.\n"
                    "It must have been deleted."
                ), e_type=PEMErrorType.JSON, status_code=503
            )
        return res

    @pem_connection
    def data_view(self, pem_conn=None):
        """ Generate chart data if function type is data view """
        query = render_template(
            'charts/sql/table/data_view.sql'
        )

        with self.dashboard_transaction:
            status, res = pem_conn.execute_dict(
                query, {"chart_id": self.cid}, True
            )

        if not status:
            current_app.logger.warning(
                gettext(
                    "Couldn't find the information for this chart.\n"
                    "ERROR: {0}"
                ).format(res)
            )
            error_return(
                gettext(
                    "Couldn't find the information for this chart."
                ), e_type=PEMErrorType.JSON
            )

        if len(res['rows']) == 0:
            error_return(
                gettext(
                    "Couldn't find the information for this chart in the "
                    "PEM database."
                ), e_type=PEMErrorType.JSON
            )

        row = res['rows'][0]

        if row['deleted']:
            error_return(
                gettext(
                    "One or more probes required to render this "
                    "chart no longer exist."
                )
            )

        tbl = row['tbl']
        metrics = row['metrices']

        # We may get this display labels as null for the existing
        # dashboards.
        # In this case, use the existing chart labels.
        col_titles = (
            list(self.labels.values())
            if self.labels is not None and len(self.labels.values()) > 0
            else row['display_labels']
        )

        order_by = row['orderby']
        order_direction = row['orderdir']
        limit = row['glimit'] if self.chart_row_limit is None \
            else self.chart_row_limit
        probe_applies_to = row['applies_to_id']
        probe_target_type = row['target_type_id']
        query = 'SELECT '

        while True:
            query += (
                'tbl.' + metrics.pop(0) + ' AS "' + col_titles.pop(0) + '"')

            if len(metrics) == 0 or len(col_titles) == 0:
                query += ' FROM pemdata.' + tbl + ' tbl'
                break
            query += ', '

        params = {}
        ret_status = PEMChartStatus.SUCCESS
        if probe_applies_to == DashboardLevel.DB_AGENT or \
                probe_target_type == DashboardLevel.DB_AGENT:
            query += ' WHERE tbl.agent_id = (%(agent)s)::int4'
            params = {'agent': self.aid}
        elif probe_target_type >= DashboardLevel.DB_SERVER:
            if probe_applies_to in (
                DashboardLevel.DB_DATABASE, DashboardLevel.DB_EXTENSION
            ):
                query += """
            LEFT JOIN (
                SELECT
                    s.id AS server_id,
                    pem.db_escaped_string_to_array(COALESCE(
                        o.database_restriction, oa.database_restriction, ''
                    )) AS r_dbs
                FROM
                    pem.server s
                    LEFT OUTER JOIN pg_catalog.pg_roles owner
                        ON (owner.oid = s.owner)
                    LEFT OUTER JOIN pem.server_options o ON (
                        s.id = o.server_id AND o.pem_user = current_user
                    )
                    LEFT OUTER JOIN pem.server_options oa ON (
                        o.id IS NULL AND s.id = oa.server_id AND
                        (
                            owner.rolname = oa.pem_user OR (
                                owner.rolname IS NULL AND oa.pem_user IS NULL
                            )
                        )
                    )
                WHERE
                    s.id = (%(server_id)s)::int4
                ) sd ON (tbl.server_id = sd.server_id)"""
                params = {'server_id': self.sid}
            elif probe_applies_to > DashboardLevel.DB_DATABASE:
                if self.level >= DashboardLevel.DB_DATABASE:
                    query += """
                LEFT JOIN (
                    SELECT
                        s.id AS server_id,
                        pem.db_escaped_string_to_array(COALESCE(
                            o.database_restriction, oa.database_restriction, ''
                        )) AS r_dbs
                    FROM
                        pem.server s
                        LEFT OUTER JOIN pg_catalog.pg_roles owner
                            ON (owner.oid = s.owner)
                        LEFT OUTER JOIN pem.server_options o ON (
                            s.id = o.server_id AND o.pem_user = current_user
                        )
                        LEFT OUTER JOIN pem.server_options oa ON (
                            o.id IS NULL AND s.id = oa.server_id AND (
                                owner.rolname = oa.pem_user OR (
                                    owner.rolname IS NULL AND oa.pem_user IS
                                     NULL
                                )
                            )
                        )
                    WHERE s.id = (%(server_id)s)::int4
                ) sd ON (tbl.server_id = sd.server_id)
                LEFT JOIN (
                    SELECT
                        o.database AS database_name,
                        pem.db_escaped_string_to_array(COALESCE(
                            o.schema_restriction, oa.schema_restriction, ''
                        )) AS r_schs
                    FROM
                        pem.server s
                        LEFT OUTER JOIN pg_catalog.pg_roles owner
                            ON (owner.oid = s.owner)
                        LEFT OUTER JOIN pem.database_option o ON (
                            s.id = o.server_id AND o.pem_user = current_user
                        )
                        LEFT OUTER JOIN pem.database_option oa ON (
                            o.id IS NULL AND s.id = oa.server_id AND
                            oa.database = (%(database)s)::text AND (
                                owner.rolname = oa.pem_user OR (
                                    owner.rolname IS NULL AND oa.pem_user IS
                                     NULL
                                )
                            )
                        )
                    WHERE
                        s.id = (%(server_id)s)::int4
                ) dd ON (tbl.database_name = dd.database_name)"""
                    params = {
                        "database": self.database,
                        "server_id": self.sid
                    }
                else:
                    query += """
                LEFT JOIN (
                    SELECT
                        s.id AS server_id,
                        pem.db_escaped_string_to_array(COALESCE(
                            o.database_restriction, oa.database_restriction, ''
                        )) AS r_dbs
                    FROM
                        pem.server s
                        LEFT OUTER JOIN pg_catalog.pg_roles owner
                            ON (owner.oid = s.owner)
                        LEFT OUTER JOIN pem.server_options o ON (
                            s.id = o.server_id AND o.pem_user = current_user
                        )
                        LEFT OUTER JOIN pem.server_options oa ON (
                            o.id IS NULL AND s.id = oa.server_id AND (
                                owner.rolname = oa.pem_user OR (
                                    owner.rolname IS NULL AND oa.pem_user IS
                                     NULL
                                )
                            )
                        )
                    WHERE
                        s.id = (%(server_id)s)::int4
                ) sd ON (tbl.server_id = sd.server_id)
                LEFT JOIN (
                    SELECT
                        o.database AS database_name,
                        pem.db_escaped_string_to_array(COALESCE(
                            o.schema_restriction, oa.schema_restriction, ''
                        )) AS r_schs
                    FROM
                        pem.server s
                        LEFT OUTER JOIN pg_catalog.pg_roles owner
                            ON (owner.oid = s.owner)
                        LEFT OUTER JOIN pem.database_option o ON (
                            s.id = o.server_id AND o.pem_user = current_user
                        )
                        LEFT OUTER JOIN pem.database_option oa ON (
                            o.id IS NULL AND s.id = oa.server_id AND (
                                owner.rolname = oa.pem_user OR (
                                    owner.rolname IS NULL AND oa.pem_user IS
                                     NULL
                                )
                            )
                        )
                    WHERE
                        s.id = (%(server_id)s)::int4
                ) dd ON (tbl.database_name = dd.database_name)"""
                    params = {"server_id": self.sid}
            else:
                params = {"server_id": self.sid}

            if (probe_applies_to >= DashboardLevel.DB_DATABASE and
                    self.level >= DashboardLevel.DB_DATABASE):
                if probe_applies_to in (
                    DashboardLevel.DB_DATABASE, DashboardLevel.DB_EXTENSION
                ):
                    params.update({"database": self.database})

                if probe_applies_to >= DashboardLevel.DB_SCHEMA and \
                        self.level >= DashboardLevel.DB_SCHEMA and \
                        probe_applies_to != DashboardLevel.DB_EXTENSION:
                    query += """
            WHERE
                tbl.server_id = (%(server_id)s)::int4 AND
                tbl.database_name = (%(database)s)::text AND
                tbl.schema_name = (%(schema)s)::text AND
                CASE WHEN pg_catalog.array_length(sd.r_dbs, 1) != 0
                    THEN tbl.database_name = ANY(sd.r_dbs)
                ELSE TRUE
                END AND
                CASE WHEN pg_catalog.array_length(dd.r_schs, 1) != 0
                    THEN tbl.schema_name = ANY(dd.r_schs)
                ELSE TRUE
                END"""
                    params.update({"schema": self.schema})

                elif probe_applies_to >= DashboardLevel.DB_SCHEMA and \
                        probe_applies_to != DashboardLevel.DB_EXTENSION:
                    query += """
            WHERE
                tbl.server_id = (%(server_id)s)::int4 AND
                tbl.database_name = (%(database)s)::text AND
                CASE WHEN pg_catalog.array_length(sd.r_dbs, 1) != 0
                    THEN tbl.database_name = ANY(sd.r_dbs)
                ELSE TRUE
                END AND
                CASE WHEN pg_catalog.array_length(dd.r_schs, 1) != 0
                    THEN tbl.schema_name = ANY(dd.r_schs)
                ELSE TRUE
                END"""
                else:
                    query += """
            WHERE
                tbl.server_id = (%(server_id)s)::int4 AND
                tbl.database_name = (%(database)s)::text AND
                CASE WHEN pg_catalog.array_length(sd.r_dbs, 1) != 0
                    THEN tbl.database_name = ANY(sd.r_dbs)
                ELSE TRUE
                END"""
                if not self.show_system_objects:
                    if probe_applies_to == DashboardLevel.DB_DATABASE:
                        query += """ AND
                CASE WHEN tbl.database_name != ''
                    THEN tbl.database_name != 'template0' AND
                    tbl.database_name != 'template1'
                ELSE TRUE
                END"""
                    elif probe_applies_to >= DashboardLevel.DB_SCHEMA and \
                            probe_applies_to != DashboardLevel.DB_EXTENSION:
                        query += """ AND
                CASE WHEN tbl.database_name != ''
                    THEN tbl.database_name != 'template0' AND
                        tbl.database_name != 'template1' AND
                        tbl.schema_name NOT IN (
                            'pg_catalog', 'sys', 'information_schema'
                        ) AND
                        tbl.schema_name NOT LIKE 'pg_toast%%' AND
                        tbl.schema_name NOT LIKE 'pg_temp%%'
                ELSE TRUE
                END"""
            elif probe_applies_to >= DashboardLevel.DB_DATABASE and \
                    self.level >= DashboardLevel.DB_SERVER:
                if probe_applies_to >= DashboardLevel.DB_SCHEMA and \
                        probe_applies_to != DashboardLevel.DB_EXTENSION:
                    query += """
            WHERE
                tbl.server_id = (%(server_id)s)::int4 AND
                CASE WHEN pg_catalog.array_length(sd.r_dbs, 1) != 0
                    THEN tbl.database_name = ANY(sd.r_dbs)
                ELSE TRUE
                END AND
                CASE WHEN pg_catalog.array_length(dd.r_schs, 1) != 0
                    THEN tbl.schema_name = ANY(dd.r_schs)
                ELSE TRUE
                END"""
                else:
                    query += """
            WHERE
                tbl.server_id = (%(server_id)s)::int4 AND
                CASE WHEN pg_catalog.array_length(sd.r_dbs, 1) != 0
                    THEN tbl.database_name = ANY(sd.r_dbs)
                ELSE TRUE
                END"""
                if not self.show_system_objects:
                    if probe_applies_to in (
                        DashboardLevel.DB_DATABASE,
                        DashboardLevel.DB_EXTENSION
                    ):
                        query += """ AND
                CASE WHEN tbl.database_name != ''
                    THEN tbl.database_name != 'template0'
                        AND tbl.database_name != 'template1'
                ELSE TRUE
                END"""
                    elif probe_applies_to >= DashboardLevel.DB_SCHEMA and \
                            probe_applies_to != DashboardLevel.DB_EXTENSION:
                        query += """ AND
                CASE WHEN tbl.database_name != ''
                    THEN tbl.database_name != 'template0' AND
                        tbl.database_name != 'template1' AND
                        tbl.schema_name NOT IN (
                            'pg_catalog', 'sys', 'information_schema'
                        ) AND
                        tbl.schema_name NOT LIKE 'pg_toast%%' AND
                        tbl.schema_name NOT LIKE 'pg_temp%%'
                ELSE TRUE
                END"""

            elif probe_applies_to == DashboardLevel.DB_SERVER and \
                    self.level >= DashboardLevel.DB_SERVER:
                query += """
            WHERE
                tbl.server_id = (%(server_id)s)::int4
            """

        is_order_direction_applicable = False
        if order_by is not None and isinstance(order_by, list):
            strorder_by = ''

            driver = get_driver(PG_DEFAULT_DRIVER)
            for i in range(0, len(order_by)):
                if i != 0:
                    strorder_by += ', '
                strorder_by += str(driver.qtIdent(pem_conn, order_by[i]))

            if strorder_by != 'None' and strorder_by != '':
                query += ' ORDER BY ' + strorder_by
                is_order_direction_applicable = True

        if is_order_direction_applicable:
            if order_direction is not None and isinstance(
                order_direction, list
            ):
                order_direction_str = ''
                if len(order_direction) > 0:
                    order_direction_str = ' ASC '
                    if order_direction[0] == 'D':
                        order_direction_str = ' DESC '
                query += order_direction_str

        if limit is not None and limit > 0:
            query += ' LIMIT ' + str(limit)

        if tbl:
            # Check the probe dependency
            self.dep_probes_params['probes'] = tuple([tbl])
            ret_status, self.dep_probes_warning = get_chart_probe_dependency(
                self.cid, self.dep_probes_params,
                self.dashboard_transaction, pem_conn
            )

            if ret_status == PEMChartStatus.ERROR:
                current_app.logger.warning(
                    'Failed to fetch the probe dependency of the '
                    'chart (id#{0}) with error - {1}'.format(
                        self.cid, self.dep_probes_warning
                    )
                )
                error_return(
                    gettext(
                        'Failed to fetch the probe dependency of the '
                        'chart (id#{0}) in the'
                        ' Postgres Enterprise Manager Server '
                        'database'
                    ).format(self.cid),
                    e_type=PEMErrorType.JSON,
                    probe_error=bool(self.dep_probes_warning)
                )

        with self.dashboard_transaction:
            status, res = pem_conn.execute_dict(query, params)

        if not status:
            error_return(
                gettext("Error fetching the chart data."),
                e_type=PEMErrorType.JSON
            )
        # Generate JSON for table chart
        res = generate_json_for_table_chart(res, table_id=self.cid)

        # Create a key msg if data is missing due to some reason
        msg = None
        if (self.is_server_remotely_monitored and
            (self.level > DashboardLevel.DB_AGENT) and
            (probe_applies_to == DashboardLevel.DB_AGENT or
             probe_target_type == DashboardLevel.DB_AGENT)):
            msg = gettext(
                "Information not available, as server "
                "is remotely monitored."
            )
        if len(res['data']) == 0:
            msg = gettext(
                "Not enough data is available to generate "
                "the table. {0} "
            ).format(self.dep_probes_warning)

        response_data = {
            'is_nested': res.get('is_nested', False),
            'columns': res.get('columns', []),
            'data': res.get('data', []),
            'probe_applies_to': probe_applies_to,
            'probe_target_type': probe_target_type,
            'info_msg': msg or self.dep_probes_warning,
            'timeout': self.settings.get('timeout', 300000),
        }
        return make_json_response(data=response_data)

    @pem_connection
    def get_start_end_time(self, pem_conn=None):
        """
        This function get the start and end time for chart
        :param pem_conn: pem database connection
        :return: result set
        """
        with self.dashboard_transaction:
            sql = render_template(
                'charts/sql/line/get_start_end_time.sql'
            )
            status, results = pem_conn.execute_dict(
                sql, [int(float(self.start_time)), int(float(self.end_time))]
            )
        if not status:
            error_return(
                gettext(
                    "Error executing query: {0}"
                ).format(results), e_type=PEMErrorType.JSON
            )

        return results['rows']

    @pem_connection
    def set_chart_settings(self, pem_conn=None, *args, **kwargs):
        """"
        This function sets the settings for charts
        """
        if request.data:
            req = json.loads(request.data)
        else:
            req = request.args or request.form

        objid = self.get_obj_id()
        timeout = None
        level = req.get('level') if 'level' in req else None
        did = req.get('did') if 'did' in req else self.did
        colors = req.get('colors') if 'colors' in req else None
        download_format = req.get('downloadformat') \
            if 'downloadformat' in req else None
        show_ack_alerts = req.get(
            'showackalerts') if 'showackalerts' in req else None

        delete = req.get('delete') if 'delete' in req else None
        if delete is None or delete != '1':
            if 'timeout' in req:
                timeout = req.get('timeout')
            else:
                return bad_request(
                    errormsg=gettext(
                        "Could not find the required parameter (timeout)."
                    )
                )

        params = {
            'cid': self.cid,
            'did': did,
            'level': level,
            'objid': None,
            'database': None,
            'schema': None,
            'tbl': None,
        }

        if level == 50:
            template = 'charts/sql/delete_config_system.sql'
        elif level == 100 or level == 200:
            params['objid'] = objid
            template = 'charts/sql/delete_config_object.sql'
        else:
            params['objid'] = objid
            params['database'] = self.database
            template = 'charts/sql/delete_config_database.sql'

        sql = render_template(template)
        status, res = pem_conn.execute_void(sql, params)
        if not status:
            return internal_server_error(errormsg=res)

        if delete is None and delete != '1':
            params.update({
                'reload': timeout, 'colors': colors, 'span': None,
                'espan': None, 'points': None,
                'sort_seq': None,
                'download_format': download_format,
                'show_ack_alerts': show_ack_alerts
            })

            sql = render_template(
                "charts/sql/insert_settings.sql"
            )

            status, res = pem_conn.execute_void(sql, params)
            if not status:
                return internal_server_error(errormsg=res)

        return make_json_response(
            info=gettext('Settings saved successfully.')
        )

    @staticmethod
    def pop(o):
        if isinstance(o, OrderedDict):
            return o.popitem(False)[1]
        return o.pop(0)

    @staticmethod
    def get_chart_level(**kwargs):
        level = 50
        if 'aid' in kwargs:
            level = 100
        if 'database' in kwargs:
            level = 300
        elif 'sid' in kwargs:
            level = 200
        return level

    @pem_connection
    def get_dep_probes(self, pem_conn=None):
        # Check the probe dependency
        if self.dep_probes:
            self.dep_probes_params['probes'] = self.dep_probes
            if self.sid:
                self.dep_probes_params['server'] = self.sid
            if self.database:
                self.dep_probes_params['database'] = self.database
            ret_status, self.dep_probes_warning = get_chart_probe_dependency(
                self.cid, self.dep_probes_params,
                self.dashboard_transaction, pem_conn
            )

            if ret_status == PEMChartStatus.ERROR:
                current_app.logger.warning(
                    'Failed to fetch the probe dependency of the '
                    'chart (id#{0}) with error - {1}'.format(
                        self.cid, self.dep_probes_warning
                    )
                )
                error_return(
                    gettext(
                        'Failed to fetch the probe dependency of the '
                        'chart (id#{0}) in the Postgres Enterprise Manager '
                        'Server database'
                    ).format(self.cid), e_type=PEMErrorType.JSON,
                    status_code=503,
                    probe_error=bool(self.dep_probes_warning)
                )

    @pem_connection
    def is_remotely_monitored_server(self, pem_conn=None):
        self.is_server_remotely_monitored = False
        status = False
        # Fetch the remote monitoring status of the server
        if self.sid != 0:
            remote_query = """SELECT is_remote_monitoring FROM pem.server
            WHERE id = (%s)::int4"""

            with self.dashboard_transaction:
                status, self.is_server_remotely_monitored = \
                    pem_conn.execute_scalar(remote_query, [self.sid])

        return status, self.is_server_remotely_monitored

    @pem_connection
    def get_agent_id(self, sid, pem_conn=None):
        agent_id = None
        # Get agent id
        with self.dashboard_transaction:
            status, agent_id = pem_conn.execute_scalar(
                "select agent_id from pem.agent_server_binding "
                "where server_id = %s", [sid]
            )
        return agent_id

    def get_params(self):
        """ Generates a list of params based on the chart level """
        self.params = {}
        if self.required_params and self.required_params[0] is not None:
            for param in self.required_params:
                if param == "agent_id":
                    self.params['agent_id'] = self.aid
                elif param == "server_id":
                    self.params['server_id'] = self.sid
                elif param == "database_name":
                    self.params['database'] = self.database
                elif param == "schema_name":
                    self.params['schema_name'] = self.schema
                elif param == "show_sys_objects":
                    self.params['show_system_objects'] = (
                        self.show_system_objects
                    )
                elif param == "sort_index":
                    self.params['sort_index'] = self.sort_index
                elif param == "sort_direction":
                    self.params['sort_direction'] = self.sort_direction
                elif param == "rows_limit":
                    self.params['rows_limit'] = (
                        self.chart_row_limit
                        if self.chart_row_limit is not None
                        else 50
                    )
                elif param == "start_time":
                    self.params['start_time'] = self.stime
                elif param == "end_time":
                    self.params['end_time'] = self.etime
                elif param == "chart_id":
                    self.params['chart_id'] = self.cid
                elif param == "dashboard_id":
                    self.params['dashboard_id'] = self.did
                else:
                    self.params[param] = None

    def get_obj_id(self):
        obj_id = None
        if self.aid is not None:
            obj_id = self.aid
        if self.sid is not None:
            obj_id = self.sid
        return obj_id

    @pem_connection
    def dispatch_request(self, pem_conn=None, *args, **kwargs):

        # Set did, level, aid or sid or database
        for arg in kwargs:
            setattr(self, arg, kwargs[arg])

        self.level = self.get_chart_level(**kwargs)

        # find out method to call
        method = getattr(self, self.operation, None)

        # Check if chart(with cid) of given type exists
        sql = """
            SELECT id FROM pem.chart WHERE id = {0} AND type = '{1}'
            """.format(self.cid, self.chart_type)

        status, res = pem_conn.execute_scalar(sql)
        if not status:
            return internal_server_error(errormsg=res)

        if method is None or res is None:
            return make_json_response(
                status=406,
                success=0,
                errormsg=gettext("Method is not implemented yet")
            )

        return method(*args, **kwargs)

    @classmethod
    def register_chart_view(cls, blueprint):
        assert (cls.chart_label is not None)

        def add_url_rule(url_prefix, operation, name, url, methods):
            end_point = '{0}_{1}_{2}'.format(
                name, cls.chart_label, operation,
            )
            url = "/{0}/<int:did>/<int:trans_id>/{1}/<int:cid>/{2}".format(
                url_prefix, cls.chart_label, url
            )
            blueprint.add_url_rule(
                url,
                view_func=cls.as_view(end_point, operation=operation),
                methods=methods
            )
            blueprint.register_exposed_url_endpoints(end_point)

        def url_point(action, node):
            return '{0}_{1}_{2}'.format(
                cls.chart_label, action, node['name']
            )

        for node in cls.nodes:
            add_url_rule(
                'data', 'data', node['name'], node['url'],
                methods=('GET',)
            )

            if cls.suffix is not None:
                add_url_rule(
                    'data', 'data_with_timespan', node['name'],
                    '{0}/{1}'.format(node['url'], cls.suffix),
                    methods=('GET',)
                )

            add_url_rule(
                'settings', 'settings', node['name'], node['url'],
                methods=('GET', 'PUT',)
            )

    def settings(self, *args, **kwargs):

        if request.method == 'PUT':
            return self.set_settings(*args, **kwargs)
        elif request.method == 'GET':
            return self.get_settings(*args, **kwargs)

        return make_json_response(
            status=406,
            success=0,
            errormsg=gettext("Method is not implemented yet")
        )
