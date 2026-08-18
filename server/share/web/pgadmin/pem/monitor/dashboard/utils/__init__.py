##########################################################################
#
# Postgres Enterprise Manager
#
# Copyright (C) 2016 - 2025, EnterpriseDB Corporation. All rights reserved.
#
##########################################################################
import os
import codecs
from flask import url_for
from pgadmin.pem.utils import pem_cancel_current_transaction


def current_datetime(fmt='%Y-%m-%d %H:%M:%S'):
    """
    Returns current datetime
    """
    from flask import session
    import datetime
    import pytz

    try:
        return datetime.datetime.now(pytz.timezone('UTC')).astimezone(
            pytz.timezone(session['timezoneid'])).strftime(fmt)
    except Exception:
        try:
            return datetime.datetime.utcnow().replace(
                tzinfo=pytz.timezone('utc')
            ).astimezone(
                pytz.FixedOffset(int(float(session['timezoneid']) * 60))
            ).strftime(fmt)
        except Exception:
            return datetime.datetime.now().strftime(fmt)


def create_dashboard_transaction_id(ret_id=False):
    # Create a unique id for the transaction
    import random
    from flask import g
    trans_id = str(random.randint(1, 9999999))
    if not ret_id:
        setattr(g, 'dashboard_trans_id', trans_id)
    else:
        return trans_id


class DashboardTransaction:

    def __init__(self, _trans_id, _conn_id, _did, _cid):
        self.trans_id = _trans_id
        self.conn_id = _conn_id
        self.did = _did
        self.cid = _cid

    def __enter__(self):
        from flask import session

        # Store pem_conn
        monitoring_data = getattr(session, 'monitoring_data', {})

        if self.trans_id not in monitoring_data:
            monitoring_data[self.trans_id] = {}

        if self.did not in monitoring_data[self.trans_id]:
            monitoring_data[self.trans_id][self.did] = {}

        if self.cid == 0:  # If only dashboard id given
            monitoring_data[self.trans_id][self.did]['conn_id'] = self.conn_id
        else:  # chart connection id
            monitoring_data[self.trans_id][self.did][self.cid] = self.conn_id

        setattr(session, 'monitoring_data', monitoring_data)

        return self

    def __exit__(self, *arg, **kwargs):
        from flask import session
        monitoring_data = getattr(session, 'monitoring_data', {})

        cid = int(self.cid) if isinstance(self.cid, str) else self.cid
        if cid > 0 and self.trans_id in monitoring_data and \
                self.did in monitoring_data[self.trans_id] and \
                cid in monitoring_data[self.trans_id][self.did]:
            del monitoring_data[self.trans_id][self.did][cid]
        elif self.trans_id in monitoring_data and \
                self.did in monitoring_data[self.trans_id]:
            del monitoring_data[self.trans_id][self.did]
            if len(monitoring_data[self.trans_id]) == 0:
                del monitoring_data[self.trans_id]

        setattr(session, 'monitoring_data', monitoring_data)


def save_dashboard_transaction_id(trans_id, conn_id, did, cid=0):
    """
    This function will store the transaction id and the related
    pem_connection id of the requested dashboard.
    """
    from flask import session

    # Store pem_conn
    monitoring_data = getattr(session, 'monitoring_data', {})

    if trans_id not in monitoring_data:
        monitoring_data[trans_id] = {}

    if did not in monitoring_data[trans_id]:
        monitoring_data[trans_id][did] = {}

    if cid == 0:  # If only dashboard id given
        monitoring_data[trans_id][did]['conn_id'] = conn_id
    else:  # chart connection id
        monitoring_data[trans_id][did][cid] = conn_id

    setattr(session, 'monitoring_data', monitoring_data)


def clear_dashboard_transaction_id(trans_id, did, cid=0):
    """
    This function clears the dashboard transaction details from the session
    """
    from flask import session
    monitoring_data = getattr(session, 'monitoring_data', {})

    cid = int(cid) if isinstance(cid, str) else cid
    if cid > 0 and trans_id in monitoring_data and\
            did in monitoring_data[trans_id] and\
            cid in monitoring_data[trans_id][did]:
        del monitoring_data[trans_id][did][cid]
    elif trans_id in monitoring_data and did in monitoring_data[trans_id]:
        del monitoring_data[trans_id][did]
        if len(monitoring_data[trans_id]) == 0:
            del monitoring_data[trans_id]

    setattr(session, 'monitoring_data', monitoring_data)


def cancel_dashboard(trans_id):
    """
    This function cancels the long running query when the dashboard is
    closed before fully loaded.
    """

    from flask import session
    from pgadmin.utils.ajax import success_return

    # Get dashboard monitoring data
    monitoring_data = getattr(session, 'monitoring_data', {})
    if trans_id in monitoring_data:
        import copy
        conn_list = copy.deepcopy(monitoring_data[trans_id])

        for did in conn_list:
            for conn in conn_list[did]:
                conn_id = conn_list[did][conn]
                # Cancel the long running query
                status = pem_cancel_current_transaction(conn_id, trans_id)
                # Try one more time if it fails to cancel
                if not status:
                    status = pem_cancel_current_transaction(conn_id, trans_id)

                # Clear the stored connection id from session
                clear_dashboard_transaction_id(trans_id, did, conn)

            # Clear the stored connection id from session
            clear_dashboard_transaction_id(trans_id, did)

    return success_return()


def include_javascript(js_file, embed=False, relative=False):
    """
    Create a link for JS files or if embedded file is required then read it
    and provide it in script tag
    js_file: File
    embed: True if embedded else False
    relative: True if embedded else False
    """

    if relative:
        path = os.path.dirname(os.path.realpath(__file__))
        js_file_name = path + "/../static/js/" + js_file
    else:
        js_file_name = js_file

    jsfile = ''
    if embed and embed is True:
        if js_file != '' and os.path.isfile(js_file_name):
            try:
                handle = codecs.open(js_file_name, "r", "utf-8")
                contents = handle.read()
                handle.close()

                jsfile = '<script type="text/javascript">' \
                         '//<![CDATA[' \
                         '\n{0}\n' \
                         '//]]>' \
                         '</script>'.format(contents)
            except IOError:
                jsfile = ''
    else:
        script_tag = '<script type="text/javascript" src="{0}"></script>'
        if relative:
            src_file = url_for(
                'static', filename='js/{0}'.format(js_file))
        else:
            src_file = js_file

        jsfile = script_tag.format(src_file)

    return jsfile


def include_css_file(
        css_file, embed=False, relative=False, attribute_list=None):
    """
    # Includes a css file in the given HTML document
    xml        - document object
    css_file   - javascript file to be included
    embed      - check if you want to embed or include
    attributes - any other attributes to be added to link/style tag.
    """

    ret = ''
    if relative:
        path = os.path.dirname(os.path.realpath(__file__))
        css_file_name = path + "/../static/css/" + css_file
    else:
        css_file_name = css_file

    css_attr = '"type"="text/css"'
    for attr in attribute_list:
        css_attr += ' "{0}"="{1}"'.format(attr, attribute_list[attr])

    # To Do if (css_file and os.path.isfile(os.path.join(path, css_file))):
    if embed and embed is True:
        if css_file != '' and os.path.isfile(css_file_name):
            try:
                handle = open(css_file_name, "r")
                contents = handle.read()
                handle.close()
                ret = '<style {0}>' \
                      '\n{1}\n' \
                      '</style>'.format(css_attr, contents)
            except IOError:
                ret = ''
    else:
        if relative:
            href = url_for('static', filename='css/{0}'.format(css_file))
        else:
            href = css_file
        ret = '<link {0} rel="stylesheet" href="{1}">'.format(css_attr, href)

    return ret
