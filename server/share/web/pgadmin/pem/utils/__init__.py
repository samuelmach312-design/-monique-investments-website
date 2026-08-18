##########################################################################
#
# Postgres Enterprise Manager
#
# Copyright (C) 2016 - 2025, EnterpriseDB Corporation. All rights reserved.
#
##########################################################################
"""PEM Utility functions"""

import os
from flask_babel import gettext
from flask import current_app
from collections import OrderedDict as __OD
from pgadmin.pem._pem import pem_connection, \
    encrypt as pem_encrypt, release_token, ALL_API_MODULES, PEMMailUtil
from pgadmin.utils.driver import get_driver
from psycopg import adapters
from psycopg.adapt import Dumper


class ChartMetricParam:
    def __init__(self, name, value):
        self.name = name
        self.val = value


class ChartMetricParamDumper(Dumper):
    def dump(self, obj):
        escaped_name = obj.name
        escaped_value = obj.val
        return f'("{escaped_name}",{escaped_value})'.encode('utf-8')


adapters.register_dumper(ChartMetricParam, ChartMetricParamDumper)

# TODO:: We need replacement to these
pem_dedicated_connection = \
    pem_cancel_current_transaction = None


def pem_token_required(func):
    """
    This function will behave as a decorator which will checks
    PEM server connection before running view, it will also return the
    pem connection object
    """
    from functools import wraps

    @wraps(func)
    def wrap(*args, **kwargs):
        from flask_login import current_user
        from pgadmin.pem import _pem

        if not current_user.has_token:
            raise _pem.TokenNotFound()

        return func(*args, **kwargs)
    return wrap


class LimitedSizeDict(__OD):
    def __init__(self, *a, **kw):
        if len(a) == 1 and isinstance(a[0], __OD):
            self._limit = a[0]._limit
        else:
            self._limit = kw.pop("limit", None)
        super(LimitedSizeDict, self).__init__(*a, **kw)
        self._check_size()

    def __setitem__(self, k, v):
        res = super(LimitedSizeDict, self).__setitem__(k, v)
        self._check_size()
        return res

    def _check_size(self):
        if self._limit is not None:
            while len(self) > self._limit:
                self.popitem(last=False)

    def update(self, *a, **kw):
        res = __OD.update(self, *a, **kw)
        self._check_size()
        return res


def show_system_objects():
    """
    This function will return if decides weather to display/show
    system objects or not based on user's preference
    """
    from pgadmin.utils.preferences import Preferences
    show_system_pref = Preferences.module('browser').preference(
        'show_system_objects'
    )
    return show_system_pref.get()


def table_sys_clause(table, has_schema=False):
    """
    This function generates sys_objects clause for database_name column to be
    checked in $table and $show_system_objects setting.

    Args:
        table: table name
        has_schema: bool
            If True, forms a query to fetch data for non-sys schema,
            otherwise fetch for 'sys' schema too.
    """
    if show_system_objects():
        # Exclude only objects from 'template0' and 'template1', when showing
        # the system objects
        res = " AND {0}.database_name not in (" \
            "'template0', 'template1')".format(table)
        if has_schema:
            res += " AND {0}.schema_name not in (" \
                "'pg_catalog', 'sys', 'information_schema')" \
                " AND {0}.schema_name !~~ 'pg_%%'".format(table)
        return res
    else:
        return ''


def get_restricted_objects_clause(
    pem_conn, param_num, table_column, object_type, id='', database=''
):
    """
    This function generates restricted_objects clause for database_name if
    object_type is 0 (server) or clause for schema_name if object_type is 1
    (database) database_name and schema_name are checked in $table.

    :param pem_conn:
    :param param_num:
    :param table_column:
    :param object_type:
    :param id:
    :param database:
    """
    result = ""
    param = ""

    if param_num == '' or table_column == '' or id == '' or pem_conn is None \
            or not pem_conn.connected():
        return False

    if object_type == 0:
        # Check for the database-restriction.
        db_rstr_sql = """
        SELECT
            pem.db_escaped_string_to_array(COALESCE(o.database_restriction,
            oa.database_restriction))
        FROM
            pem.server s
            LEFT OUTER JOIN pg_catalog.pg_roles owner ON (owner.oid = s.owner)
            LEFT OUTER JOIN pem.server_options o ON (s.id = o.server_id AND
            o.pem_user = current_user)
            LEFT OUTER JOIN pem.server_options oa
                ON (o.server_id IS NULL AND s.id = oa.server_id AND
                    (owner.rolname = oa.pem_user OR (owner.rolname IS NULL AND
                    oa.pem_user IS NULL)))
        WHERE
            s.id = (%s)::int4
        """

        status, db_rstr = pem_conn.execute_scalar(db_rstr_sql, [id])
        if db_rstr is not None:
            result = "%s = ANY(%s)" % (table_column, param_num)
            param = db_rstr

            return True, result, param
    elif object_type == 1:
        if database == '':
            return False, result, param

        # Check for the schema-restriction.
        schema_rstr_sql = """
        SELECT
            pem.db_escaped_string_to_array(COALESCE(o.schema_restriction,
            oa.schema_restriction))
        FROM
            pem.server s
            LEFT OUTER JOIN pg_catalog.pg_roles owner ON (owner.oid = s.owner)
            LEFT OUTER JOIN pem.database_option o ON (s.id = o.server_id AND
            o.pem_user = current_user AND o.database = (%s)::text)
            LEFT OUTER JOIN pem.database_option oa
                ON (o.server_id IS NULL AND s.id = oa.server_id AND
                oa.database = (%s)::text AND
                    (owner.rolname = oa.pem_user OR (owner.rolname IS NULL
                    AND oa.pem_user IS NULL)))
        WHERE
            s.id = (%s)::int4;
        """
        status, schema_rstr = pem_conn.execute_scalar(schema_rstr_sql,
                                                      [database, database, id])
        if schema_rstr is not None:
            result = "%s = ANY(%s)" % (table_column, param_num)
            param = schema_rstr

            return True, result, param
    return False, result, param


def boolean_to_on_off(param):
    if not param or param == 0 or param == '0' or param == '':
        param = 'off'
    else:
        param = 'on'
    return param


def bool_to_numeric(param):
    if param:
        return 1
    else:
        return 0


def current_datetime(fmt='%Y-%m-%d %H:%M:%S'):
    import datetime
    from flask import session
    import pytz
    try:
        return datetime.datetime.utcnow().replace(
            tzinfo=pytz.timezone('utc')
        ).astimezone(
            pytz.timezone(session['timezoneid'])
        ).strftime(fmt)
    except Exception:
        try:
            return datetime.datetime.utcnow().replace(
                tzinfo=pytz.timezone('utc')
            ).astimezone(
                pytz.FixedOffset(int(float(session['timezoneid']) * 60))
            ).strftime(fmt)
        except Exception:
            return datetime.datetime.now().strftime(fmt)


def csv_split(val, delimiter=',', quotechar='"'):
    import csv
    import sys
    from io import StringIO

    reader = csv.reader(
        StringIO(val),
        delimiter=delimiter,
        quotechar=quotechar
    )
    return [row for row in reader]


def is_remotely_monitored_server(pem_conn, server_id):
    """
    This function checks whether the server with server_id is remotely
    monitored. It returns boolean value

    Args:
        pem_conn: the connection object
        server_id: the server id.
    """
    # Server Object
    if server_id == '':
        server_id = None
    params = [server_id]
    status, remote_monitoring = pem_conn.execute_scalar(
        "SELECT ps.is_remote_monitoring FROM pem.avail_servers AS ps "
        "LEFT OUTER JOIN pem.agent_server_binding pasb ON ("
        "ps.id = pasb.server_id) WHERE ps.id =(%s)::int4", params
    )

    return remote_monitoring


def is_edb_server(pem_conn, server_id):
    """
    This function fetch and sets the sever info in the session
    based on the server id passed and returns a boolean value.

    Args:
        pem_conn: the connection object
        server_id: the server id
    """
    from flask import session
    server_info = 'server_info#{0}'.format(server_id)

    if server_info not in session:
        status, res = pem_conn.execute_dict(
            "SELECT version_string as version, ("
            "pem.parse_version_string(version_string) > 20802) as is_edb "
            " FROM pemdata.server_info WHERE server_id=(%s)::int4",
            [server_id]
        )

        if len(res['rows']) == 1:
            res = session[server_info] = (res['rows'][0]).copy()
            return res['is_edb']
        elif len(res['rows']) == 0:
            # If there is no data in the PEMDATA, then we will fallback to
            # default logic of checking the server type same as pgAdmin4
            from config import PG_DEFAULT_DRIVER
            if server_id == 0:
                return pem_conn.manager.server_type == 'ppas'
            driver = get_driver(PG_DEFAULT_DRIVER)
            manager = driver.connection_manager(server_id)
            conn = manager.connection()
            if conn.connected() and manager.server_type == 'ppas':
                return True

        return False
    return session[server_info]['is_edb']


def get_server_agent(pem_conn, server_id):
    status, aid = pem_conn.execute_scalar("""
    SELECT
        asb.agent_id
    FROM
        pem.server s
        LEFT JOIN pem.agent_server_binding asb ON (asb.server_id = s.id)
    WHERE s.id = (%s)::int4""", [server_id])

    return aid


def show_streaming_dashboard(pem_conn, server_id):
    status, showStreamingDb = pem_conn.execute_scalar("""
        WITH server_replication AS (
            SELECT replication_solution
            FROM pem.server
            WHERE id = (%(sid)s)::int4
        )
        SELECT
            CASE
                WHEN COALESCE(
                        NULLIF(sr.replication_solution, ''),
                        NULL
                    ) IS NULL THEN
                    (
                        (SELECT count(*)
                         FROM pemdata.wal_archive_status
                         WHERE server_id = (%(sid)s)::int4) > 0
                        OR
                        (SELECT count(*)
                         FROM pemdata.streaming_replication
                         WHERE server_id = (%(sid)s)::int4) > 0
                        OR
                        (SELECT count(*)
                         FROM pemdata.streaming_replication_lag_time
                         WHERE server_id = (%(sid)s)::int4) > 0
                    )

                WHEN sr.replication_solution = 'efm' THEN
                    (
                        (SELECT count(*)
                         FROM pemdata.wal_archive_status
                         WHERE server_id = (%(sid)s)::int4) > 0
                        OR
                        (SELECT count(*)
                         FROM pemdata.streaming_replication
                         WHERE server_id = (%(sid)s)::int4) > 0
                        OR
                        (SELECT count(*)
                         FROM pemdata.streaming_replication_lag_time
                         WHERE server_id = (%(sid)s)::int4) > 0
                        OR
                        (SELECT count(*)
                         FROM pemdata.efm_cluster_node_status
                         WHERE server_id = (%(sid)s)::int4) > 0
                        OR
                        (SELECT count(*)
                         FROM pemdata.efm_cluster_info
                         WHERE server_id = (%(sid)s)::int4) > 0
                    )

                WHEN sr.replication_solution = 'patroni' THEN
                    (
                        (SELECT count(*)
                         FROM pemdata.wal_archive_status
                         WHERE server_id = (%(sid)s)::int4) > 0
                        OR
                        (SELECT count(*)
                         FROM pemdata.streaming_replication
                         WHERE server_id = (%(sid)s)::int4) > 0
                        OR
                        (SELECT count(*)
                         FROM pemdata.streaming_replication_lag_time
                         WHERE server_id = (%(sid)s)::int4) > 0
                        OR
                        (SELECT count(*)
                         FROM pemdata.patroni_cluster_status
                         WHERE server_id = (%(sid)s)::int4) > 0
                        OR
                        (SELECT count(*)
                         FROM pemdata.patroni_node_status
                         WHERE server_id = (%(sid)s)::int4) > 0
                    )

                ELSE false
            END
        FROM server_replication sr;
    """, {'sid': server_id})
    return showStreamingDb


def nl2br(parent, raw):
    from xml.etree.ElementTree import fromstring
    from html import escape

    if not raw:
        return

    data = escape(raw)
    data = data.replace("\n", '<br/>')
    el = fromstring('<span>{0}</span>'.format(data))
    parent.append(el)


# Render a re-loadable table
def graph_render_reloadable_table(
    itr, tbl, sortable=True, height=0, includeLoadingDiv=False
):
    from xml.etree.ElementTree import Element, SubElement

    # Create the document
    # Put the table in a scrollable area
    div = Element('div')
    rowid = 0  # define row id to 0

    if height != 0:
        div.attrib['style'] = 'height: ' + str(height) + 'px; overflow:auto;'
        div.attrib['onscroll'] = 'OnScrollDiv(this)'
        div.attrib['class'] = 'pem-chart-content pem-chart-tbl'
    else:
        div.attrib['style'] = 'overflow:auto;'

    table = SubElement(div, 'table', attrib={
        'id': tbl
    })

    cols = len(itr.cols)
    idx = -1
    if len(itr) == 0:
        tr = SubElement(table, 'tr')
        td = SubElement(
            tr, 'td', attrib={
                'colspan': str(cols), 'align': 'center',
                'style': 'border: 0;'
            }
        )
        SubElement(td, 'i').text = gettext('No data found for this object.')
    else:
        table.attrib['width'] = '100%'
        table.attrib['class'] = 'pem-chart-table pem-element ' \
                                'pem-chart-table-striped'

        # Add the header section, describing the columns
        thead = SubElement(table, 'thead')
        tr = SubElement(thead, 'tr')

        idx = -1
        on_sort = "javascript:$('#" + tbl + "').sortTable({" \
                  "'onTable': '" + tbl + "', 'onCol': COLUMN, " \
                                         "'keepRelationships': true"

        for col in itr.cols:
            idx += 1
            th = SubElement(
                tr, 'th', attrib={
                    'class': 'pem-chart-sortable-th'
                }
            )

            if (sortable):
                a = SubElement(th, 'a')
                # Specify numeric sorting if required
                col_attr = on_sort.replace('COLUMN', str(idx + 1))
                a.attrib['href'] = col_attr + ", 'sortType': 'numeric'})" if \
                    itr.is_col_num(idx) else col_attr + '})'
                a.attrib['style'] = 'text-decoration: none;'
                nl2br(a, col['name'])

                # End a
            else:
                nl2br(th, col['name'])
            # End th
        # End tr, thead

        # Loop through the rows, outputing each value in a list.
        tbody = SubElement(table, 'tbody')

        idx = -1
        for row in itr():
            idx += 1
            tr = SubElement(tbody, 'tr')
            # Use the appropriate style for the row
            tr.attrib['class'] = 'pem-chart-tr-even' if idx % 2 == 0 \
                else 'pem-chart-tr-odd'

            for row_idx in range(0, len(row)):
                td = SubElement(tr, 'td')
                td.attrib['class'] = 'pem-chart-td'

                val = row[row_idx]
                if val is None:
                    val = ""

                if row_idx == 0:  # ID
                    rowid = val

                td.text = str(val)
            # End tr

    # End tbody, table

    if includeLoadingDiv:
        div1 = SubElement(
            div, 'div', attrib={
                'id': 'LoadingRowsDiv', 'align': 'center',
                'style': 'float:center; display:none;'
            }
        )
        SubElement(
            div1, 'img', attrib={
                'src': '/pem/static/img/loading.gif',
                'alt': gettext('Loading'),
            }
        )
        # End img, div1

    div2 = SubElement(
        div, 'div', attrib={
            'id': 'HiddenDiv', 'align': 'center',
            'style': 'float:center; display:none;'
        }
    )

    SubElement(
        div2, 'label', attrib={'id': 'LastRowId', 'size': '20'}
    ).text = gettext(str(rowid))
    # End </label>, </div>
    # End div

    return div


# Render a table of data. Yeah, I know it's not a graph.
def graph_render_table(
    itr, tableName='', sortable=True
):
    from xml.etree.ElementTree import Element, SubElement
    # Create the document
    div = Element('div', attrib={'style': 'overflow:auto;'})

    # Put the table in a scrollable area
    table = SubElement(div, 'table',
                       attrib={'id': tableName, 'class': 'TableLayout'})

    # Add the header section, describing the columns
    thead = SubElement(table, 'thead')

    tr = SubElement(thead, 'tr')

    idx = -1
    for col in list(itr.cols.items()):
        idx += 1
        th = SubElement(tr, 'th')
        if sortable:
            th.attrib['class'] = 'ReportTableHeaderCell ' \
                                 'pem-chart-sortable-th'
            th.attrib['col-id'] = str(idx + 1)
            th.attrib['onclick'] = 'javascript: sortTableCol($(this));'
            th.attrib['sort-func'] = 'pemUnknownSort'
            h4 = SubElement(th, 'h4', attrib={'class': 'pem-not-sorted'})

            nl2br(h4, col['id'])
        else:
            th.atrrib['class'] = 'ReportTableHeaderCell ' \
                                 'pem-chart-sortable-th'

            nl2br(th, col['id'])
    # End tr, thead

    # Loop through the rows, outputing each value in a list.
    tbody = SubElement(table, 'tbody')

    rowidx = 0
    for row in itr():
        tr = SubElement(tbody, 'tr')
        # Use the appropriate style for the row
        tr.attrib['class'] = 'ReportDetailsOddDataRow' if rowidx % 2 else \
            'ReportDetailsEvenDataRow'

        idx = 0
        for col in row:
            td = SubElement(tr, 'td', attrib={'class': 'ReportTableValueCell'})
            td.attrib['style'] = "text-align: {0};".format(
                'right' if itr.is_col_num(idx) else 'left'
            )
            nl2br(td, col[1])
            idx += 1
        rowidx += 1
        # End td
        # End tr

    if rowidx == 0:
        tr = SubElement(tbody, 'tr')
        td = SubElement(
            tr, 'td', attrib={
                'colspan': str(idx), 'align': 'center',
                'style': 'border: 0;'
            }
        )
        SubElement(td, 'i').text = gettext('No data found for this object.')
    # End tbody, table, div

    return div


def prettify(elem, method='xml', escapeNewLine=True, addDocType=False):
    """Return a pretty-printed XML string for the Element."""
    if elem is not None and elem != '':
        import xml.etree.ElementTree as et
        import re

        rough_string = et.tostring(
            elem,
            encoding='utf-8',
            method=method
        )
        rough_string = rough_string.decode('utf-8')
        if escapeNewLine:
            rough_string = re.sub(r"@@PEMEDBBR@@", r"<br/>", rough_string)
            rough_string = re.sub(
                r"@@PEMEDBATBR@@",
                r"&lt;br/&gt;",
                rough_string
            )
        if addDocType:
            rough_string = str(
                '<!DOCTYPE html PUBLIC "-//W3C//DTD XHTML 1.0 '
                'Transitional//EN" '
                '"http://www.w3.org/TR/xhtml1/DTD/xhtml1-transitional.dtd">'
            ) + rough_string

        return rough_string
    else:
        return elem


class RowListIterator(object):
    def __init__(self, pem_conn, rs):
        self._rows = rs['rows']
        self._columns = rs['columns']
        self._col_number_type = \
            [isinstance(col['type_code'], (int)) for col in self._columns]

    @property
    def cols(self):
        return self._columns

    def __len__(self):
        return len(self._rows)

    def __call__(self, _assoc=False):
        try:
            for row in self._rows:
                if _assoc:
                    yield row
                else:
                    yield list(row.values())
        except Exception as ex:
            current_app.logger.exception(ex)
            raise ex

    def is_col_num(self, idx):
        return self._col_number_type[idx]


def datetimeFromPGISOString(date_str):
    import re

    m = re.compile(
        r'(\d{1,4}[-]\d{1,2}-\d{1,2}\s+\d{1,2}[:]\d{1,2}[:]\d{1,2}([.]\d{1,6}'
        r')?)\s*(([+-])?(\d{1,2}):(\d{1,2}))?'
    ).match(date_str)

    if m:
        g = m.groups()

        from datetime import datetime

        res = datetime.strptime(g[0], '%Y-%m-%d %H:%M:%S')
        offset = None

        if g[2]:
            sign = -1 if g[3] == '-' else 1

            offset = int(g[4]) * 60
            offset += int(g[5])

            offset *= sign

            import pytz
            res = res.replace(tzinfo=pytz.FixedOffset(offset))
        return res

    return None


def datetimeToPGISOString(d):
    import datetime

    res = d.strftime('%Y-%m-%d %H:%M:%S.%f')

    if d.tzinfo:
        tz = d.tzinfo.utcoffset(d)

        if tz and isinstance(tz, datetime.timedelta):
            seconds = tz.total_seconds()
            if seconds < 0:
                res += ' -'
                seconds *= -1
            else:
                res += ' +'
            res += '{0}:{1}'.format(
                int(seconds / 3600),
                int((seconds % 3600) / 60)
            )

    return res


@pem_connection
def get_params(name, pem_conn=None):
    from flask import g
    params = getattr(g, 'PARAM_CACHE', None)

    if params is None:
        # Get the dashboard settings from pem.config and stuff them in the
        # global array.
        status, res = pem_conn.execute_2darray(
            'SELECT param, value FROM pem.config',
        )
        params = PARAM_CACHE = {r['param']: r['value'] for r in res['rows']}

        setattr(g, 'PARAM_CACHE', PARAM_CACHE)

    if name in params:
        return params[name]
    else:
        import re
        # If this param is related to dashboard span
        if re.search('/^(dash_).+(_span)/', name) is not None:
            return 7
        # If this param is related to dashboard rows
        elif re.search('/^(dash_).+(_rows)/', name) is not None:
            return 25
        # If this param is related to chart bullets
        elif re.search('/^(chart_).+(_bullets)/', name) is not None:
            return 0
        return ""


def get_params_default(name, default):
    value = get_params(name)
    if (value == ""):
        return default
    return value


def html_append_logo(logo, embed=False):
    """
    This function will return postgres expert image content
    in case embed is True else will return image path
    """
    from flask import url_for
    import os
    import base64

    src = None
    logo_file_name = url_for(
        'pem.static',
        filename='img/report_header.png'
    )
    if embed:
        try:
            path = os.path.dirname(os.path.realpath(__file__))
            logo_file_name = path + "/../static/img/" + os.path.basename(
                os.path.realpath(logo))
            handle = open(logo_file_name, "rb")
            contents = handle.read()
            handle.close()
            imgdata = base64.b64encode(contents)
            src = 'data:image/png;base64,' + imgdata.decode('utf-8')
        except IOError:
            return src
        return src
    else:
        return logo_file_name


class Server(object):

    def __init__(self, _dict):
        assert (_dict)
        self.data = _dict.copy()

    @classmethod
    def get(cls, sid):
        from pgadmin.browser.server_groups.servers import ServerNode
        import json
        res = ServerNode(cmd='get').properties(gid=-1, sid=sid)
        props = json.loads(res.response[0])

        if props is not None:
            return Server(props)
        return None

    def __getattr__(self, k):
        if 'data' == k:
            return dict()
        if k in self.data:
            return self.data[k]
        raise AttributeError(('%s not found!' % k))


def get_default_stylesheets():
    """
    Returns list of default stylesheets used for report
    download/generate.
    Embed css in view as well download report
    Returns: list of stylesheets

    """
    css_files = [
        os.path.realpath('{}{}'.format(
            os.path.dirname(os.path.realpath(__file__)),
            '/../../static/js/generated/style.css')
        ),
        os.path.realpath('{}{}'.format(
            os.path.dirname(os.path.realpath(__file__)),
            '/../../static/js/generated/pgadmin.style.css')
        ),
        os.path.realpath('{}{}'.format(
            os.path.dirname(os.path.realpath(__file__)),
            '/../../static/js/generated/pgadmin.css')
        ),
    ]

    return css_files


def is_agent_exists(pem_conn, agent_id):
    """
    This function will check the given agent id is exist in
    pem.agent table.

    :param pem_conn: PEM Connection Object
    :param agent_id: Agent Id
    :return:
    """
    if agent_id == '':
        agent_id = None
    params = [agent_id]
    status, agent_exist = pem_conn.execute_scalar(
        "SELECT 1 FROM pem.agent WHERE id = (%s)::int4", params
    )

    if not status or agent_exist is None:
        return False

    return True


def is_agent_exists_and_active(pem_conn, agent_id):
    """
    This function will check the given agent id exists and active in
    pem.agent table.

    :param pem_conn: PEM Connection Object
    :param agent_id: Agent Id
    :return:
    """
    if agent_id == '':
        agent_id = None
    params = [agent_id]
    status, agent_exist = pem_conn.execute_scalar(
        "SELECT 1 FROM pem.agent WHERE id = (%s)::int4 and active = true",
        params
    )

    if not status or agent_exist is None:
        return False

    return True


def is_server_group_exists(pem_conn, server_group_id):
    """
    This function will check the given server_group id is exist in
    pem.server_group table.

    :param pem_conn: PEM Connection Object
    :param agent_id: Agent Id
    :return:
    """
    if server_group_id == '':
        server_group_id = None
    params = [server_group_id]
    status, server_group_exist = pem_conn.execute_scalar(
        "SELECT 1 FROM pem.server_group WHERE id = (%s)::int4", params
    )

    if not status or server_group_exist is None:
        return False

    return True


def is_server_exists(pem_conn, server_id):
    """
    This function will check the given server id is exist in
    pem.server table.

    :param pem_conn: PEM Connection Object
    :param server_id: Server Id
    :return:
    """
    if server_id == '':
        server_id = None
    params = [server_id]
    status, server_exist = pem_conn.execute_scalar(
        "SELECT 1 FROM pem.server WHERE id = (%s)::int4 "
        "AND active", params
    )

    if not status or server_exist is None:
        return False

    return True


def is_database_exists(pem_conn, server_id, database_name):
    """
    This function will check the given database is exist in
    pemdata.oc_database table.

    :param pem_conn: PEM Connection Object
    :param server_id: Server Id
    :param database_name: Database Name
    :return:
    """
    if server_id == '' or database_name == '':
        return False

    params = [server_id, database_name]
    status, database_exist = pem_conn.execute_scalar(
        "SELECT 1 FROM pemdata.oc_database WHERE server_id = (%s)::int4 "
        "AND database_name = (%s)::text", params
    )

    if not status or database_exist is None:
        return False

    return True


def is_schema_exists(pem_conn, server_id, database_name, schema_name):
    """
    This function will check the given database is exist in
    pemdata.oc_schema table.

    :param pem_conn: PEM Connection Object
    :param server_id: Server Id
    :param database_name: Database Name
    :param schema_name: Schema Name
    :return:
    """
    if server_id == '' or database_name == '' or schema_name == '':
        return False

    params = [server_id, database_name, schema_name]
    status, schema_exist = pem_conn.execute_scalar(
        "SELECT 1 FROM pemdata.oc_schema WHERE server_id = (%s)::int4 "
        "AND database_name = (%s)::text AND schema_name = (%s)::text", params
    )

    if not status or schema_exist is None:
        return False

    return True


def is_object_exists(pem_conn, object_type, server_id, database_name=None,
                     schema_name=None, object_name=None, arguments=None,
                     table_name=None, index_name=None, sequence_name=None,
                     view_name=None, function_name=None):
    """
    This function will check whether given object is exist
    in respective PEM table or not.

    :param pem_conn: PEM Connection Object
    :param object_type: Type of the object like (agent, server, database ..)
    :param server_id: Server ID.
    :param database_name: Database Name
    :param schema_name: Schema Name
    :param object_name: Object(Table, Index, Sequence, Function, View) Name
    :param arguments: Function argument types comma separated
    :return: True/False
    """

    if object_type == 'server':
        if not is_server_exists(pem_conn, server_id):
            return False, gettext("The specified server not found")

    elif object_type == 'database':
        if not is_server_exists(pem_conn, server_id):
            return False, gettext("The specified server not found")
        if not is_database_exists(pem_conn, server_id, database_name):
            return False, gettext("The specified database not found")

    elif object_type == 'schema':
        if not is_server_exists(pem_conn, server_id):
            return False, gettext("The specified server not found")
        if not is_database_exists(pem_conn, server_id, database_name):
            return False, gettext("The specified database not found")
        if not is_schema_exists(pem_conn, server_id, database_name,
                                schema_name):
            return False, gettext("The specified schema not found")

    elif object_type == 'table':
        if not is_server_exists(pem_conn, server_id):
            return False, gettext("The specified server not found")
        if not is_database_exists(pem_conn, server_id, database_name):
            return False, gettext("The specified database not found")
        if not is_schema_exists(pem_conn, server_id, database_name,
                                schema_name):
            return False, gettext("The specified schema not found")

        if table_name:
            object_name = table_name

        if object_name == '':
            return False, gettext("The specified table not found")

        params = [server_id, database_name, schema_name, object_name]
        status, object_exist = pem_conn.execute_scalar(
            "SELECT 1 FROM pemdata.oc_table WHERE server_id = (%s)::int4 "
            "AND database_name = (%s)::text AND schema_name = (%s)::text "
            "AND table_name = (%s)::text", params
        )

        if not status or object_exist is None:
            return False, gettext("The specified table not found")

    elif object_type == 'index':
        if not is_server_exists(pem_conn, server_id):
            return False, gettext("The specified server not found")
        if not is_database_exists(pem_conn, server_id, database_name):
            return False, gettext("The specified database not found")
        if not is_schema_exists(pem_conn, server_id, database_name,
                                schema_name):
            return False, gettext("The specified schema not found")

        if index_name:
            object_name = index_name

        if object_name == '':
            return False, gettext("The specified index not found")

        params = [server_id, database_name, schema_name, object_name]
        status, object_exist = pem_conn.execute_scalar(
            "SELECT 1 FROM pemdata.oc_index WHERE server_id = (%s)::int4 "
            "AND database_name = (%s)::text AND schema_name = (%s)::text "
            "AND index_name = (%s)::text", params
        )

        if not status or object_exist is None:
            return False, gettext("The specified index not found")

    elif object_type == 'sequence':
        if not is_server_exists(pem_conn, server_id):
            return False, gettext("The specified server not found")
        if not is_database_exists(pem_conn, server_id, database_name):
            return False, gettext("The specified database not found")
        if not is_schema_exists(pem_conn, server_id, database_name,
                                schema_name):
            return False, gettext("The specified schema not found")

        if sequence_name:
            object_name = sequence_name

        if object_name == '':
            return False, gettext("The specified sequence not found")

        params = [server_id, database_name, schema_name, object_name]
        status, object_exist = pem_conn.execute_scalar(
            "SELECT 1 FROM pemdata.oc_sequence WHERE server_id = (%s)::int4 "
            "AND database_name = (%s)::text AND schema_name = (%s)::text "
            "AND sequence_name = (%s)::text", params
        )

        if not status or object_exist is None:
            return False, gettext("The specified sequence not found")

    elif object_type == 'function':
        if not is_server_exists(pem_conn, server_id):
            return False, gettext("The specified server not found")
        if not is_database_exists(pem_conn, server_id, database_name):
            return False, gettext("The specified database not found")
        if not is_schema_exists(pem_conn, server_id, database_name,
                                schema_name):
            return False, gettext("The specified schema not found")

        if function_name:
            object_name = function_name

        if object_name == '':
            return False, gettext("The specified function not found")

        params = [server_id, database_name, schema_name, object_name,
                  arguments]

        # TODO: issue with arguments need to be fixed
        if arguments is None:
            status, object_exist = pem_conn.execute_scalar(
                "SELECT 1 FROM pemdata.oc_function WHERE "
                "server_id = (%s)::int4 "
                "AND database_name = (%s)::text AND schema_name = (%s)::text "
                "AND function_name = (%s)::text",
                params[:-1]
            )
        else:
            status, object_exist = pem_conn.execute_scalar(
                "SELECT 1 FROM pemdata.oc_function "
                "WHERE server_id = (%s)::int4 "
                "AND database_name = (%s)::text AND schema_name = (%s)::text "
                "AND function_name = (%s)::text AND arg_types = (%s)::text",
                params
            )

        if not status or object_exist is None:
            return False, gettext("The specified function not found")

    elif object_type == 'view':
        if not is_server_exists(pem_conn, server_id):
            return False, gettext("The specified server not found")
        if not is_database_exists(pem_conn, server_id, database_name):
            return False, gettext("The specified database not found")
        if not is_schema_exists(pem_conn, server_id, database_name,
                                schema_name):
            return False, gettext("The specified schema not found")

        if view_name:
            object_name = view_name

        if object_name == '':
            return False, gettext("The specified view not found")

        params = [server_id, database_name, schema_name, object_name]
        status, object_exist = pem_conn.execute_scalar(
            "SELECT 1 FROM pemdata.oc_views WHERE server_id = (%s)::int4 "
            "AND database_name = (%s)::text AND schema_name = (%s)::text "
            "AND view_name = (%s)::text", params
        )

        if not status or object_exist is None:
            return False, gettext("The specified view not found")

    return True, None


@pem_connection
def get_config_by_name(name=None, pem_conn=None):
    """
    This function will retrieve the configuration
    settings by given name from pem.config table
    Args:
        name: Name of configuration setting
        pem_conn: PEM Database connection object

    Returns: Boolean value

    """
    status, res = pem_conn.execute_scalar("""
SELECT
    COALESCE(value::boolean, false)
FROM
    pem.config WHERE param = '{0}'""".format(name))

    return res


@pem_connection
def validate_server_for_wizard_tree_control(server, pem_conn=None):
    """
    Using this function we can validate the server for following wizard tree
    control
    1) Audit manager
    2) Log manager
    3) Tuning Wizard

    :param server: Server details in dict
    :param pem_conn: PEM Connection object
    :return: checkbox <Boolean>, is_info_msg <Boolean>, err_msg <String>
    """

    # Default values
    checkbox = True
    is_info_msg = False
    err_msg = None

    service_id = server.get('service_id', None)
    agent_capability_list = server.get('agent_capability_list', None)
    version = server.get('version', None)

    if not service_id or service_id == '':
        checkbox = False
        is_info_msg = True
        err_msg = gettext(
            "Specify the name of the service in the Service ID field "
            "on the Server Properties dialog."
        )

    elif agent_capability_list and \
            'allow_server_restart' not in agent_capability_list:
        checkbox = False
        is_info_msg = True
        err_msg = gettext(
            "The agent bound to this server does not have the "
            "required permissions to restart the server."
        )
    elif version and version != '' and int(version.split('.')[0]) < 5:
        checkbox = False
        is_info_msg = True
        err_msg = gettext(
            "The agent bound to this server is older than the PEM "
            "server version."
        )
    else:
        # Also make sure 'settings' probe should be enable to change
        # the postgresql.conf
        status, enable_probe = pem_conn.execute_dict(
            "SELECT enabled FROM pem.probe_config_server "
            "WHERE server_id = %(server_id)s AND probe_id = "
            "( SELECT id FROM pem.probe "
            "WHERE internal_name = 'settings')",
            {'server_id': server['server_id']}
        )
        if not status:
            checkbox = False
            is_info_msg = False
            err_msg = enable_probe
        else:
            if len(enable_probe['rows']) > 0:
                if enable_probe['rows'][0]['enabled'] is False:
                    checkbox = False
                    is_info_msg = True
                    err_msg = gettext(
                        "'Settings' probe for this server is disabled. Please "
                        "enable it from 'Manage Probe' configuration."
                    )

    return checkbox, is_info_msg, err_msg


def is_db_excluded(pem_conn, sid, db_name):

    """
    This function will return True if database is excluded from agent
    monitoring
    :param pem_conn: PEM connection
    :param sid: server id
    :param db_name: Database name
    :return: Boolean
    """
    sql = f"""
    SELECT
        asb.exclude_databases
    FROM pem.agent_server_binding asb
    INNER JOIN pem.avail_servers s ON (asb.server_id = s.id)
    WHERE asb.server_id = '{sid}'::int4
    """
    status, res = pem_conn.execute_dict(sql)
    if not status:
        return False, res

    exclude_databases = []
    if len(res['rows']) > 0 and len(res['rows'][0]['exclude_databases']) > 0:
        exclude_databases = res['rows'][0]['exclude_databases']

    return db_name in exclude_databases


def validate_and_fetch_existing_alert_options(targets):
    """This function will validate the existing_alert_options param and also
    set its value according to v9 and previous api versions"""

    existing_alert_options = 'I'
    is_option_valid = True
    for target in targets:
        if 'existing_alert_options' in target:
            if target['existing_alert_options'] not in ['I', 'R', 'D']:
                is_option_valid = False
            existing_alert_options = target['existing_alert_options']
            break
        elif 'ignore_duplicate_alerts' in target:
            existing_alert_options = 'I' if target[
                'ignore_duplicate_alerts'] else 'R'
            break
        else:
            is_option_valid = False
    return is_option_valid, existing_alert_options


def execute_iterator(
    pem_conn, query, params=None, formatted_exception_msg=False
):
    status, res = pem_conn.execute_2darray(
        query, params, formatted_exception_msg
    )

    if status:
        return True, RowListIterator(pem_conn, res)

    return status, res


def get_sql_placeholders(param):
    """ This function will return the required format for
    sql array formatting"""
    return ', '.join(
        ['%s'] * len(param))
