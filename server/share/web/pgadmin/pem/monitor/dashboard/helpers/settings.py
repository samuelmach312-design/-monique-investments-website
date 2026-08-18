##########################################################################
#
# Postgres Enterprise Manager
#
# Copyright (C) 2016 - 2025, EnterpriseDB Corporation. All rights reserved.
#
##########################################################################
"""Implementation for the chart settings"""

from flask import request, session, current_app
from flask_babel import gettext
import json
from pgadmin.pem.utils import pem_connection
from pgadmin.utils.ajax import make_json_response, \
    internal_server_error


@pem_connection
def dashboard_set_settings(did, pem_conn=None):
    pdata = None

    if request.data:
        pdata = json.loads(request.data.decode())

    link_charts = pdata.get('linked')
    linked_span = pdata.get('linked_span')
    remember_option = pdata.get('remember')

    update_sql = """
    UPDATE pem.dashboard_settings
        SET charts_linked = %s::boolean, linked_span = %s::integer
    WHERE uid = pem.current_user_id()
        AND did=%s::integer
    RETURNING *"""

    insert_sql = """
    INSERT INTO pem.dashboard_settings (charts_linked, linked_span, did)
    values (%s::boolean, %s::integer, %s::integer)
    """

    delete_sql = """
    DELETE from pem.dashboard_settings
    WHERE uid = pem.current_user_id()
        AND did=%s::integer
    """

    params = [link_charts, int(linked_span)]
    # If remember option is checked then we have to save against dashboard id
    if remember_option:
        params.append(did)
    else:
        params.append(-1)

    # Update existing row
    status, res = pem_conn.execute_dict(update_sql, params)
    if not status:
        return internal_server_error(errormsg=res)
    # if row not found then insert new row
    if len(res['rows']) == 0:
        status, res = pem_conn.execute_void(insert_sql, params)
        if not status:
            return internal_server_error(errormsg=res)

    # Remove entry for current dashboard from database
    if not remember_option:
        status, res = pem_conn.execute_void(delete_sql, [did])
        if not status:
            return internal_server_error(errormsg=res)
        if 'pem_dashboard' in session and did in session['pem_dashboard']:
            session['pem_dashboard'].pop(did)

    if 'pem_session' not in session:
        session['pem_dashboard'] = {}

    session['pem_dashboard'][did if remember_option else -1] = {
        'linked': link_charts,
        'linked_span': linked_span
    }

    return make_json_response(
        info=gettext('Settings saved successfully.'),
        data={
            'linked': link_charts,
            'linked_span': linked_span,
            'remember': remember_option,
            'did': did if remember_option else -1
        }
    )


def dashboard_get_settings(pem_conn, did):
    result = {
        'linked': False, 'remember': False, 'linked_span': 24
    }

    sql = """
    SELECT *  FROM pem.dashboard_settings
    WHERE uid = pem.current_user_id() AND (did = %s::integer OR did = -1)
    ORDER BY did DESC LIMIT 1
    """
    status, res = pem_conn.execute_dict(sql, [did])
    if not status:
        current_app.logger.warning(
            gettext('Error fetching dashboard settings: {0}').format(res)
        )
        # Sending default hard coded values
        return result

    # We did not get any data from database
    if len(res['rows']) == 0:
        # Using default values for the first time.
        return result

    row = res['rows'][0]
    result['remember'] = (row['did'] == int(did))

    if 'pem_dashboard' not in session:
        session['pem_dashboard'] = dict()
    elif did in session['pem_dashboard']:
        data = session['pem_dashboard'][did]
        if did != row['did'] or data['linked'] != row['charts_linked'] or \
                data['linked_span'] != row['linked_span']:
            if did != row['did']:
                session['pem_dashboard'].pop(did, None)
            result['inform_user'] = gettext(
                'The dashboard configurations has been updated from some '
                'session.'
            )
    elif did != row['did'] and row['did'] in session['pem_dashboard']:
        data = session['pem_dashboard'][row['did']]
        if data['linked'] != row['charts_linked'] or \
                data['linked_span'] != row['linked_span']:
            result['inform_user'] = gettext(
                'The dashboard configurations has been updated from some '
                'session.'
            )

    result['linked_span'] = int(row['linked_span'])
    result['linked'] = row['charts_linked']

    # Update the session
    session['pem_dashboard'][row['did']] = dict({
        'linked_span': int(row['linked_span']),
        'linked': row['charts_linked']
    })

    return result
