##########################################################################
#
# Postgres Enterprise Manager
#
# Copyright (C) 2016 - 2025, EnterpriseDB Corporation. All rights reserved.
#
##########################################################################

"""Implements webhook for alerts"""


import json
from flask import render_template, current_app, request
from flask_security import login_required
from flask_babel import gettext

from pgadmin.pem.utils import pem_connection, get_sql_placeholders
from pgadmin.utils.ajax import internal_server_error, \
    make_json_response, make_response, not_found, bad_request
from . import utils

VALID_KEY_MSG = gettext("Provide valid http header key.")
VALID_VAL_MSG = gettext("Provide valid http header value.")
VALID_CONFIG_VAL_MSG = gettext("Provide valid value for {0}.")
DUPLICATE_HEADER_KEY_MSG = gettext("Please enter unique http headers key.")


@login_required
@utils.configAlertRole.check_role(
    gettext("Logged-in user do not have permission to access webhook list.")
)
@pem_connection
def webhook_list(webhook_id=None, pem_conn=None, webhook_type=None):
    """
    This function will return the list of webhooks.

    :param webhook_id: Webhook id
    :param pem_conn: PEM Connection object.
    """
    # is_alert = False if webhook_type == 'alert' else True
    status, result = get_webhooks(webhook_type, webhook_id, pem_conn)
    if not status:
        return result

    return make_response(response={'webhook_alerts': result}, status=200)


@login_required
@utils.configAlertRole.check_role(
    gettext("Logged-in user do not have permission to test"
            " webhook configuration.")
)
@pem_connection
def webhook_test_connection(pem_conn=None):
    """
    This function is used create job to test webhook connection.

    :param pem_conn: PEM Connection object.
    """

    if request.data:
        data = json.loads(request.data.decode())
    else:
        data = request.args or request.form

    job_id = None
    req_params = ['name', 'url', 'method', 'payload']

    for arg in req_params:
        if arg not in data:
            return not_found(
                errormsg=gettext("Webhook " + arg + " not supplied."))

    if len(data) > 0:
        pem_conn.execute_void('BEGIN')
        sql = render_template(
            '/alerts/sql/webhook/test_connection_job.sql',
            name=data['name'],
            url=data['url'],
            method=data['method'],
            payload=data['payload'],
            create_test_endpoint=True,
        )

        status, endpoint_id = pem_conn.execute_scalar(sql)
        if not status:
            pem_conn.execute_void('ROLLBACK')
            return internal_server_error(job_id)

        if 'http_headers' in data and len(data['http_headers']) > 0:
            # don't do anything if only one row having
            # marked_for_deletion as False is present in http_headers
            if len(data['http_headers']) == 1 and \
                    (len(data['http_headers'][0]) == 1 or
                     data['http_headers'][0].get('http_header_key') is None or
                     data['http_headers'][0].get('http_header_value') is None):
                pass
            else:
                status, result = insert_http_header(
                    data['http_headers'], pem_conn, endpoint_id
                )
                if not status:
                    pem_conn.execute_void('ROLLBACK')
                    return result

        sql = render_template(
            '/alerts/sql/webhook/test_connection_job.sql',
            data=data,
            create_job=True,
        )

        status, job_id = pem_conn.execute_scalar(sql)
        if not status:
            pem_conn.execute_void('ROLLBACK')
            return internal_server_error(job_id)

        sql = render_template(
            '/alerts/sql/webhook/test_connection_job.sql',
            name=data['name'],
            job_id=job_id,
            endpoint_id=endpoint_id,
            create_job_step=True,
        )
        status, msg = pem_conn.execute_void(sql)
        if not status:
            pem_conn.execute_void('ROLLBACK')
            return internal_server_error(msg)

        pem_conn.execute_void('COMMIT')

        # return success true to disaply message
        return make_json_response(
            data={
                'success': True,
                'job_id': job_id,
                'info': gettext('The job has been created successfully '
                                'to test connection')
            }
        )


@login_required
@utils.configAlertRole.check_role(
    gettext("Logged-in user do not have permission to save"
            " webhook configuration.")
)
@pem_connection
def webhook_config(pem_conn=None):
    """
    This function is used to save the webhook.

    :param pem_conn: PEM Connection object.
    """

    if request.data:
        data = json.loads(request.data.decode())
    else:
        data = request.args or request.form

    status = False
    result = None
    req_params = ['name', 'url', 'method', 'payload_template']

    if len(data) > 0:
        webhook_data = data[0]
        pem_conn.execute_void('BEGIN')

        if 'changed' in webhook_data:
            for row in webhook_data['changed']:
                # validate the input data
                status, result = verify_webhook_parameters(
                    row, req_params, pem_conn, 'update', row['id'])
                if not status:
                    pem_conn.execute_void('ROLLBACK')
                    return result

                if 'marked_for_deletion' not in row or \
                    'marked_for_deletion' in row and \
                        not row['marked_for_deletion']:

                    status, result = update_webhook(
                        row, row['id'], pem_conn)
                    if not status:
                        pem_conn.execute_void('ROLLBACK')
                        return result
                    if 'http_headers' in row:
                        status, result = update_http_header(
                            row['http_headers'], pem_conn, row['id'])
                        if not status:
                            pem_conn.execute_void('ROLLBACK')
                            return result

            # Check for delete webhook
            delete_webhook_ids = []
            for row in webhook_data['changed']:
                if 'marked_for_deletion' in row and row['marked_for_deletion']:
                    delete_webhook_ids.append(row['id'])

            if len(delete_webhook_ids) > 0:
                # Delete webhook id from pem.webhook_endpoints table
                sql = render_template('alerts/sql/webhook/delete.sql',
                                      delete_webhook=True,
                                      placeholders=get_sql_placeholders(
                                          delete_webhook_ids))
                status, result = pem_conn.execute_void(
                    sql, delete_webhook_ids)
                if not status:
                    pem_conn.execute_void('ROLLBACK')
                    return internal_server_error(errormsg=result)

        if 'added' in webhook_data:
            for row in webhook_data['added']:
                # Validate input data
                status, result = verify_webhook_parameters(row, req_params,
                                                           pem_conn, 'insert')
                if not status:
                    pem_conn.execute_void('ROLLBACK')
                    return result

                # Insert into pem.webhook_endpoints table
                status, webhook_id = insert_webhook(row, pem_conn)
                if not status:
                    pem_conn.execute_void('ROLLBACK')
                    return webhook_id

                # If http headers are added then call
                # insert_http_header function to save the data.
                if 'http_headers' in row and len(row['http_headers']) > 0:
                    # don't do anything if only one row having
                    # marked_for_deletion as False is present in http_headers
                    if len(row['http_headers']) == 1 and \
                            len(row['http_headers'][0]) == 1:
                        pass
                    else:
                        status, result = insert_http_header(
                            row['http_headers'], pem_conn, webhook_id
                        )
                        if not status:
                            pem_conn.execute_void('ROLLBACK')
                            return result

        pem_conn.execute_void('COMMIT')

    return make_json_response(data={'status': status, 'result': result})


def get_webhooks(webhook_type, webhook_id=None, pem_conn=None):
    """
    This function will return the list of webhooks.

    :param webhook_id: Webhook id
    :param pem_conn: PEM Connection object.
    """
    sql = render_template('alerts/sql/webhook/list.sql',
                          webhook_id=webhook_id,
                          webhook_type=webhook_type)

    # Execute the query.
    status, webhook = pem_conn.execute_dict(sql)
    if not status:
        current_app.logger.error(str(webhook))
        return False, internal_server_error(errormsg=webhook)

    if webhook_id is not None and len(webhook['rows']) == 0:
        return False, not_found(errormsg=gettext("Webhook with given id "
                                                 "doesn't exist."))
    webhook_list = []
    for row in webhook['rows']:
        http_headers = []
        # get http header key and values
        if len(row['header_ids']) > 0 and len(row['header_keys']) > 0 \
                and len(row['header_values']) > 0:
            for idx, header_id in enumerate(row['header_ids']):
                http_headers.append({
                    "http_header_id": header_id,
                    "http_header_key": row['header_keys'][idx],
                    "http_header_value": row['header_values'][idx]
                })
        all_alerts = row['low_alert'] and row['med_alert'] and row[
            'high_alert'] and row['cleared_alert']
        webhook_list.append({
            "id": row['id'],
            "name": row['name'],
            "url": row['url'],
            "enabled": row['enabled'],
            "method": row['method'],
            "payload_template": row['payload_template'],
            "all_alerts": all_alerts,
            "low_alert": row['low_alert'],
            "med_alert": row['med_alert'],
            "high_alert": row['high_alert'],
            "cleared_alert": row['cleared_alert'],
            "http_headers": http_headers,
            "payload_type": row['payload_type']
        })
    return True, webhook_list


def update_webhook(data, webhook_id, pem_conn=None):
    """
    :param data: webhook data to update
    :param id: webhook id
    :param pem_conn: PEM Connection object
    """
    status = True
    result = None
    data_to_update = {}

    # remove http headers data from update now
    data_to_update = {k: v for (k, v) in data.items() if k != 'http_headers'}
    if len(data_to_update) > 0:
        sql = render_template('alerts/sql/webhook/update.sql',
                              update_webhook=True, data=data_to_update,
                              id=webhook_id)
        status, result = pem_conn.execute_void(sql)
        if not status:
            current_app.logger.error(str(result))
            return False, internal_server_error(errormsg=result)
    return status, result


def insert_webhook(webhook_data, pem_conn=None):
    """
    :param webhook_data:
    :param pem_conn:
    """

    status = True
    webhook_id = None

    # Insert into pem.webhook_endpoints table
    if len(webhook_data) > 0:
        sql = render_template(
            'alerts/sql/webhook/insert.sql',
            insert_webhook=True
        )
        status, webhook_id = pem_conn.execute_scalar(sql, webhook_data)
        if not status:
            current_app.logger.error(str(webhook_id))
            return False, internal_server_error(errormsg=webhook_id)

    return status, webhook_id


def update_http_header(header_data, pem_conn, webhook_id=None):
    """
    This function is used to update webhook http headers

    :param header_data: http heades data to be saved.
    :param pem_conn: PEM Connection object.
    :param webhook_id: webhook ID
    """

    status = True
    result = None

    if 'changed' in header_data:
        for row in header_data['changed']:
            if 'marked_for_deletion' in row and row['marked_for_deletion']:
                sql = render_template(
                    'alerts/sql/webhook/delete.sql',
                    delete_webhook=False,
                    header_id=row['http_header_id']
                )
                status, result = pem_conn.execute_void(sql)
                if not status:
                    current_app.logger.error(str(result))
                    return False, internal_server_error(errormsg=result)
            else:
                if 'http_header_id' not in row:
                    return False, not_found(
                        errormsg=gettext("HTTP header id not supplied."))

                # check given http_header_id is valid or not
                status, result = validate_http_header_id(
                    row['http_header_id'], pem_conn)
                if not status:
                    return False, result

                data_to_update = {k: v for (k, v) in row.items()
                                  if k != 'http_header_id'}
                if len(data_to_update) > 0:
                    sql = render_template('alerts/sql/webhook/update.sql',
                                          update_webhook=False,
                                          data=data_to_update,
                                          http_header_id=row['http_header_id'])
                    status, result = pem_conn.execute_void(sql)
                    if not status:
                        current_app.logger.error(str(result))
                        if result.find('violates unique constraint'):
                            return False, bad_request(
                                errormsg=DUPLICATE_HEADER_KEY_MSG)
                        else:
                            return False, \
                                internal_server_error(errormsg=result)

    if 'deleted' in header_data:
        for row in header_data['deleted']:
            if 'http_header_id' not in row:
                return False, not_found(
                    errormsg=gettext("HTTP header id not supplied."))

            sql = render_template('alerts/sql/webhook/delete.sql',
                                  delete_webhook=False,
                                  header_id=row['http_header_id'])

            status, result = pem_conn.execute_void(sql)
            if not status:
                current_app.logger.error(str(result))
                return False, internal_server_error(errormsg=result)

    if 'added' in header_data:
        status, result = insert_http_header(header_data['added'],
                                            pem_conn, webhook_id)
        if not status:
            current_app.logger.error(str(result))
            return status, result
    return status, result


def insert_http_header(header_data, pem_conn, webhook_id=None):
    """
    This function is used to insert webhook http header.

    :param header_data: http header data to be inserted.
    :param pem_conn: PEM Connection object.
    :param webhook_id: webhook ID
    """
    status = True
    result = None

    # insert into pem.webhook_http_headers table
    for row in header_data:
        if 'http_header_key' not in row:
            return False, not_found(
                errormsg=gettext("HTTP header key not supplied."))
        else:
            if row['http_header_key'] is None or row['http_header_key'] == '':
                return False, bad_request(errormsg=VALID_KEY_MSG)

        if 'http_header_value' not in row:
            return False, not_found(
                errormsg=gettext("HTTP header value not supplied."))
        else:
            if row['http_header_key'] is None or row['http_header_key'] == '':
                return False, bad_request(errormsg=VALID_VAL_MSG)

        sql = render_template('alerts/sql/webhook/insert.sql',
                              insert_webhook=False)
        row['webhook_id'] = webhook_id
        status, result = pem_conn.execute_void(sql, row)
        if not status:
            current_app.logger.error(str(result))
            if result.find('violates unique constraint'):
                return False, bad_request(
                    errormsg=DUPLICATE_HEADER_KEY_MSG)
            else:
                return False, internal_server_error(errormsg=result)

    return status, result


def validate_http_header_id(http_header_id, pem_conn):
    """
    This function validates http header id in put request
    :param http_header_id: HTTP header id
    :param pem_conn: PEM connection object
    :return:
    """
    if http_header_id is None or http_header_id == '':
        return False, bad_request(errormsg=gettext("Please provide valid "
                                                   "HTTP header id."))
    # check id is exist or not
    sql = "SELECT COUNT(*) FROM pem.webhook_http_headers WHERE id = {0}".\
        format(http_header_id)

    status, res = pem_conn.execute_scalar(sql)
    if not status:
        return False, internal_server_error(errormsg=res)
    if int(res) == 0:
        return False, not_found(errormsg=gettext("Provided HTTP header id "
                                                 "doesn't exists."))
    return True, None


def verify_webhook_parameters(data, req_params, pem_conn,
                              ops=None, webhook_id=None):
    """
    This function is used to verify the parameters required
    to insert/update data into pem.webhook_endpoints table .

    :param data: Data to be insert/update in pem.webhook_endpoints table.
    :param req_params: required parametes to validate
    :param pem_conn: PEM Connection object.
    :param ops: opearation to perform - insert/update
    :param webhook_id: Webhook ID
    :return:
    """

    if data is None or len(data) == 0:
        return False, not_found(
            errormsg=gettext("Please specify input data for which you "
                             "wish to {0} the webhook.").format(ops)
        )

    required_args = req_params

    for arg in required_args:
        if arg in data and ops in ('insert', 'update'):
            if data[arg] is None or data[arg] == '':
                return False, bad_request(
                    errormsg=gettext("Provide valid webhook {0}.").format(arg))
        elif ops == 'insert':
            return False, not_found(
                errormsg=gettext("Webhook " + arg + " not supplied."))

    # validate other parameters
    boolean_params = ['enabled', 'low_alert', 'med_alert', 'high_alert',
                      'cleared_alert']

    for param in boolean_params:
        if param in data:
            if not isinstance(data[param], bool):
                return False, bad_request(
                    errormsg=gettext("Provide valid value for "
                                     "{0}").format(param))

    # Check if webhook with same name already exists or not.
    if 'name' in data:
        sql = render_template('alerts/sql/webhook/webhook_exists.sql',
                              check_by_id=False)

        status, result = pem_conn.execute_scalar(sql, data)
        if not status:
            current_app.logger.error(str(result))
            return False, internal_server_error(errormsg=result)
        if int(result) > 0:
            return False, internal_server_error(
                errormsg=gettext("Error: webhook with same name exists."))

    if ops == 'update':
        # check if webhook with gived id is present
        sql = render_template('alerts/sql/webhook/list.sql',
                              webhook_id=webhook_id)

        status, webhooks = pem_conn.execute_dict(sql)
        if not status:
            current_app.logger.error(str(webhooks))
            return False, internal_server_error(errormsg=webhooks)

        # If webhook is not present then return error.
        if len(webhooks['rows']) == 0:
            return False, not_found(
                errormsg=gettext("The specified webhook is not available"))

    return True, None


def insert_webhook_alert_config(result, alert_data, pem_conn=None):
    """
    This function will get alert_id & store webhook config details
    provided for alert
    """
    data = dict()
    ids = []
    data['alert_id'] = result
    if 'override_default_config' in alert_data:
        data['override_default_config'] = alert_data['override_default_config']
    else:
        data['override_default_config'] = False
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
            return False, VALID_CONFIG_VAL_MSG.format("cleared_webhook_ids")
        status, res = validate_webhook_ids(alert_data['cleared_webhook_ids'],
                                           pem_conn)
        if not status:
            return False, res
        data['cleared_webhook_ids'] = alert_data['cleared_webhook_ids']
    else:
        data['cleared_webhook_ids'] = []

    params = [data['alert_id'], data['override_default_config'],
              data['low_webhook_ids'], data['med_webhook_ids'],
              data['high_webhook_ids'], data['cleared_webhook_ids'],
              data['send_notification']]
    sql = render_template(
        'alerts/sql/webhook/insert_alert_webhook_config.sql'
    )
    status, result = pem_conn.execute_scalar(sql, params)
    if not status:
        current_app.logger.error(str(result))
        return False, internal_server_error(errormsg=result)
    return status, result


def validate_update_webhook_params(data, pem_conn=None):
    """
    This function will check whether input parameter to
    update the webhook alert config is valid or not.
    :param data: Alert data to be updated in table.
    """
    if 'send_notification' in data:
        if data['send_notification'] is None or \
                not isinstance(data['send_notification'], bool):
            return False, gettext("Provide valid value "
                                  "of alert send_notification status.")
    if 'override_default_config' in data:
        if data['override_default_config'] is None or \
                not isinstance(data['override_default_config'], bool):
            return False, gettext("Provide valid value of alert "
                                  "override_default_config.")
    # Check for valid webhook ids
    ids = []
    if 'low_webhook_ids' in data:
        if data['low_webhook_ids']:
            if not isinstance(data['low_webhook_ids'], list) or \
                (any(not isinstance(x, int) for x in
                     data['low_webhook_ids'])):
                return False, VALID_CONFIG_VAL_MSG.format("low_webhook_ids")
            ids.extend(data['low_webhook_ids'])
    if 'med_webhook_ids' in data:
        if data['med_webhook_ids']:
            if not isinstance(data['med_webhook_ids'], list) or \
                (any(not isinstance(x, int) for x in
                     data['med_webhook_ids'])):
                return False, VALID_CONFIG_VAL_MSG.format("med_webhook_ids")
            ids.extend(data['med_webhook_ids'])
    if 'high_webhook_ids' in data:
        if data['high_webhook_ids']:
            if not isinstance(data['high_webhook_ids'], list) or \
                (any(not isinstance(x, int) for x in
                     data['high_webhook_ids'])):
                return False, VALID_CONFIG_VAL_MSG.format("high_webhook_ids")
            ids.extend(data['high_webhook_ids'])
    if 'cleared_webhook_ids' in data:
        if data['cleared_webhook_ids']:
            if not isinstance(data['cleared_webhook_ids'], list) or \
                    (any(not isinstance(x, int) for x in
                         data['cleared_webhook_ids'])):
                return False, VALID_CONFIG_VAL_MSG.format(
                    "cleared_webhook_ids")
            ids.extend(data['cleared_webhook_ids'])
    status, result = validate_webhook_ids(ids, pem_conn)
    if not status:
        return False, result
    return True, None


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


def update_webhook_alert_config(alert_data, pem_conn=None):
    """
    :param alert_data: Alert data for update
    :param pem_conn: pem connection object
    """
    data = dict()
    status = False
    result = None
    d_data_name = []
    d_data_type = []
    config_column_type = {}
    data_col_type = {}
    # First extract pem.webhook_alert_config table column type information.
    status, data_type = pem_conn.execute_dict(
        render_template('alerts/sql/webhook/webhook_config_column_type.sql')
    )
    if not status:
        current_app.logger.error(str(result))
        return False, data_type
    else:
        d_data_name = [d['name'] for d in data_type['rows']]
        d_data_type = [d['datatype'] for d in data_type['rows']]
    if len(d_data_name) == len(d_data_type):
        item = 0
        while item < len(d_data_name):
            column_name = d_data_name[item]
            column_type = d_data_type[item]
            config_column_type[column_name] = column_type
            item += 1
    if 'send_notification' in alert_data:
        data['send_notification'] = alert_data['send_notification']
        data_col_type['send_notification'] = \
            config_column_type['send_notification']

    if 'override_default_config' in alert_data:
        data['override_default_config'] = alert_data['override_default_config']
        data_col_type['override_default_config'] = \
            config_column_type['override_default_config']

    if 'low_webhook_ids' in alert_data:
        data['low_webhook_ids'] = alert_data['low_webhook_ids']
        data_col_type['low_webhook_ids'] = \
            config_column_type['low_webhook_ids']
    if 'med_webhook_ids' in alert_data:
        data['med_webhook_ids'] = alert_data['med_webhook_ids']
        data_col_type['med_webhook_ids'] = \
            config_column_type['med_webhook_ids']
    if 'high_webhook_ids' in alert_data:
        data['high_webhook_ids'] = alert_data['high_webhook_ids']
        data_col_type['high_webhook_ids'] = \
            config_column_type['high_webhook_ids']
    if 'cleared_webhook_ids' in alert_data:
        data['cleared_webhook_ids'] = alert_data['cleared_webhook_ids']
        data_col_type['cleared_webhook_ids'] = \
            config_column_type['cleared_webhook_ids']

    # Update pem.webhook_alert_config table
    sel_sql = 'SELECT wac.id, wac.override_default_config, \
              wac.send_notification FROM pem.webhook_alert_config as wac \
              WHERE alert_id={0}'.format(alert_data['id'])
    status, res = pem_conn.execute_dict(sel_sql)
    if len(res['rows']) > 0:
        remove_entry = False
        if 'override_default_config' in alert_data:
            if alert_data['override_default_config'] or \
                    not res['rows'][0]['send_notification']:
                remove_entry = False
            else:
                remove_entry = True

        if 'send_notification' in alert_data:
            if not alert_data['send_notification'] or \
                    res['rows'][0]['override_default_config']:
                remove_entry = False
            else:
                remove_entry = True

        if 'override_default_config' in alert_data and \
                'send_notification' in alert_data:
            if not alert_data['override_default_config'] and \
                    alert_data['send_notification']:
                remove_entry = True
            else:
                remove_entry = False

        if len(data) > 0 and not remove_entry:
            sql = render_template(
                'alerts/sql/webhook/update_alert_webhook_config.sql',
                data=data,
                col_type=data_col_type,
                alert_id=alert_data['id']
            )
            status, result = pem_conn.execute_void(sql)
            if not status:
                current_app.logger.error(str(result))
                return False, internal_server_error(errormsg=result)

        if len(data) > 0 and remove_entry:
            del_sql = "DELETE FROM pem.webhook_alert_config " \
                "WHERE alert_id={0}".format(alert_data['id'])
            status, result = pem_conn.execute_void(del_sql)
        if not status:
            current_app.logger.error(str(result))
            return False, internal_server_error(errormsg=result)
    else:
        if 'send_notification' not in alert_data:
            alert_data['send_notification'] = True

        if 'override_default_config' not in alert_data:
            alert_data['override_default_config'] = False

        if alert_data['override_default_config'] or \
                not alert_data['send_notification']:
            status, res = insert_webhook_alert_config(alert_data['id'],
                                                      alert_data, pem_conn)

        if not status:
            current_app.logger.error(str(res))
            return False, internal_server_error(errormsg=res)
    return status, result


@login_required
@utils.configAlertRole.check_role(
    gettext("Logged-in user do not have permission to test"
            " webhook configuration.")
)
@pem_connection
def webhook_testjob_status_poll(job_id, pem_conn=None):
    """
    Poll request to get the status of Job
    Args:
        jobid: JoB ID

    Returns: Success/Failure
    """
    SQL = render_template(
        'alerts/sql/webhook/job_status.sql',
        job_id=job_id
    )
    status, res = pem_conn.execute_scalar(SQL)
    if not status:
        current_app.logger.error(res)
        return internal_server_error(errormsg=res)

    return make_response(
        response=res,
        status=200
    )


def register_webhook_routes(blueprint):
    blueprint.add_url_rule('/webhook/list/<webhook_type>', 'webhook_list',
                           webhook_list,
                           methods=["GET"])
    # blueprint.add_url_rule('/webhook/list', 'webhook_list', webhook_list,
    #                        methods=["GET"])
    blueprint.add_url_rule('/webhook/configure', 'webhook_config',
                           webhook_config, methods=["PUT", "POST"])
    blueprint.add_url_rule('/webhook/test_connection',
                           'webhook_test_connection', webhook_test_connection,
                           methods=["PUT", "POST"])
    blueprint.add_url_rule('/poll/<job_id>',
                           'webhook_testjob_status_poll',
                           webhook_testjob_status_poll, methods=["get"])
