##########################################################################
#
# Postgres Enterprise Manager
#
# Copyright (C) 2016 - 2025, EnterpriseDB Corporation. All rights reserved.
#
##########################################################################

"""Webhook API"""

from pgadmin.pem.api.utils import ApiView
from pgadmin.pem.utils import get_sql_placeholders
from pgadmin.utils.ajax import internal_server_error, precondition_required, \
    success_return, make_response, not_found
from pgadmin.pem.monitor.alerts.webhook import webhook_list, \
    insert_webhook, insert_http_header, update_webhook, update_http_header, \
    verify_webhook_parameters, get_webhooks
from flask_babel import gettext
from flask import render_template, request, current_app
from functools import wraps

v5_req_params = ['name', 'url', 'method', 'payload_template']
api_versions_v5 = list(ApiView.api_versions)[4:]


class WebhookApiView(ApiView):
    """
    This class provide APIs to configure the webhooks.
    """

    endpoint = 'webhook_config'
    url = '/webhook/'
    pk = 'webhook_id'

    # Api version from v5 till latest
    # ['v5_api', 'v6_api', 'v7_api', 'v8_api']
    api_versions = api_versions_v5
    methods = ['GET', 'DELETE', 'POST', 'PUT']

    def __init__(self, *args, **kwargs):
        super(ApiView, self).__init__(*args, **kwargs)
        self.req_params = v5_req_params

    def check_precondition(f):
        """
        This function will behave as a decorator which will checks
        database connection before running view, it will also attaches
        manager,conn & template_path properties to self
        """
        @wraps(f)
        def wrap(self, *args, **kwargs):
            """Makes PEM connection and sets template path"""
            self.conn = kwargs['pem_conn']

            if not self.conn.connected():
                self.conn.connect()

            # If DB not connected then return error to browser
            if not self.conn.connected():
                return precondition_required(
                    gettext("Connection to the PEM server has been lost!")
                )

            # We do not need to pass the pem_conn to the wrapped functions
            del kwargs['pem_conn']
            self.is_edb = 0

            # Set the template path for sql scripts
            self.template_path = 'alerts/sql/webhook'

            return f(self, *args, **kwargs)
        return wrap

    @check_precondition
    def get(self, webhook_type=None,webhook_id=None):
        """
        This function will return the list of webhooks.

        :param webhook_id: webhook id for which information will be fetched.

        Method: GET
        URL: /api/v5/webhook/
        DESCRIPTION: All the webhooks will be returned.

        Method: GET
        URL: /api/v5/webhook/1
        DESCRIPTION: webhook with id 1 will be returned.

        Input Data:
        Valid webhook id.

        e.g.
        /api/v5/webhook/1

        :return:
            [{
                "id": 1,
                "name": "webhook1",
                "url": "www.test.com",
                "enabled": true,
                "method": "POST",
                "payload_template": "{ "Alert Name":"%AlertName%",
                "type":"Webhook" }",
                "low_alert": false,
                "med_alert": false,
                "high_alert": true,
                "cleared_alert": false,
                "http_headers": [{
                  "http_header_id": 1,
                  "Content-Type": "application/json",
                  "Accept-Language": "en-US"
                }],
            }]

        """

        status, res = get_webhooks(
            webhook_type, webhook_id=webhook_id, pem_conn=self.conn
        )
        if not status:
            return res

        return make_response(response=res, status=200)

    @check_precondition
    def delete(self, webhook_id):
        """
        This function will delete the webhook.

        :param webhook_id: webhook id for which information will be deleted.

        Method: DELETE
        URL: /api/v5/webhook/<webhook_id>

        Input Data:
        Valid webhook id to delete the webhook.

        e.g.
        /api/v5/webhook/234

        :return:

        Below is the expected result.

        status: 200 OK
        {
          "success":1,
          "info":"webhook deleted successfully.",
          "result":null,
          "errormsg":"",
          "data":null
        }

        """

        status, res = delete_webhook([webhook_id], self.conn)
        if not status:
            return res

        return success_return(message=gettext(
            'Webhook deleted successfully.')
        )

    @check_precondition
    def put(self, webhook_id):
        """
        This function will update webhook.

        :param webhookp_id: Webhook Id for which webhook information
        will be updated.

        Method: PUT
        URL: /api/v5/webhook/<webhookp_id>

        Input Data: Below are the json input format required to update webhook

        Example input data as below.
             {

                "id":4,
                "name":"test1_updated11",
                "url": "http://www.jiraaa.com",
                "enabled": true,
                "method": "POST",
                "http_headers":{
                   "added":[
                      {
                         "http_header_key": "Accept-",
                         "http_header_value": "en-US"
                      }
                   ],
                   "changed":[
                      {
                         "http_header_id": 3,
                         "http_header_key": "Content-Type",
                         "http_header_value": "text/text"
                      }
                   ],
                   "deleted":[
                      {
                         "http_header_id": 1
                      }
                   ]
                }
             }

        :return:
        Below is the expected result.

        status: 200 OK
        {
          "success":1,
          "info":"Webhook updated successfully.",
          "result":null,
          "errormsg":"",
          "data":null
        }
        """

        data = request.get_json()
        pem_conn = self.conn

        pem_conn.execute_void('BEGIN')
        try:
            # validate update data first
            status, error_msg = verify_webhook_parameters(
                data, self.req_params, pem_conn, 'update', webhook_id)
            if not status:
                pem_conn.execute_void('ROLLBACK')
                return error_msg

            # Update pem.webhook_endpoints table
            status, result = update_webhook(data, webhook_id, pem_conn)
            if not status:
                pem_conn.execute_void('ROLLBACK')
                return result

            # If http headers are changed then call
            # update_http_header function to update the data.
            if 'http_headers' in data:
                status, result = update_http_header(
                    data['http_headers'], pem_conn, webhook_id
                )
                if not status:
                    pem_conn.execute_void('ROLLBACK')
                    return result
        except Exception as e:
            pem_conn.execute_void('ROLLBACK')
            return internal_server_error(errormsg=str(e))

        pem_conn.execute_void('COMMIT')

        return success_return(gettext("Webhook updated successfully."))

    @check_precondition
    def post(self):
        """
        This function will create new webhook

        Method: POST
        URL: /api/v5/webhook

        Input Data: Below are the json input format required to create webhook

        Example input data as below.
        {
            "name":"test1",
            "url": "www.test.com",
            "enabled": true,
            "method": "POST",
            "payload_template": { "Alert Name":"%AlertName%",
                "type":"Webhook" },
            "low_alert": true,
            "med_alert": false,
            "high_alert": true,
            "cleared_alert": false,
            "http_headers": [{
              "http_header_key": "Content-Type",
              "http_header_value": "application/json"
            }]
        }

        :return:

        Below is the expected result.

        status: 200 OK
        {
          "success":1,
          "info":"webhook created successfully.",
          "result":null,
          "errormsg":"",
          "data":null
        }
        """

        data = request.get_json()
        pem_conn = self.conn

        pem_conn.execute_void('BEGIN')
        try:
            # validate insert data first
            status, error_msg = verify_webhook_parameters(
                data, self.req_params, pem_conn, 'insert')
            if not status:
                pem_conn.execute_void('ROLLBACK')
                return error_msg

            # Insert into pem.webhook_endpoints table
            status, webhook_id = insert_webhook(data, pem_conn)
            if not status:
                pem_conn.execute_void('ROLLBACK')
                return webhook_id

            # If http headers are added then call
            # insert_http_header function to save the data.
            if 'http_headers' in data and len(data['http_headers']) > 0:
                status, result = insert_http_header(
                    data['http_headers'], pem_conn, webhook_id
                )
                if not status:
                    pem_conn.execute_void('ROLLBACK')
                    return result
        except Exception as e:
            pem_conn.execute_void('ROLLBACK')
            return internal_server_error(errormsg=str(e))

        pem_conn.execute_void('COMMIT')

        return success_return(message=gettext(
            'Webhook created successfully.')
        )


def delete_webhook(delete_webhook_ids, pem_conn=None):
    """
    :param delete_webhook_ids: list of webhook ids to be deleted
    :param pem_conn: PEM Connection object
    """
    status = False
    result = None

    # First check webhook id exists or not.
    if len(delete_webhook_ids) == 0:
        return False, not_found(
            errormsg=gettext("Please specify webhook id you wish to delete.")
        )

    for webhook_id in delete_webhook_ids:
        sql = render_template('alerts/sql/webhook/list.sql',
                              webhook_id=webhook_id)

        try:
            status, webhooks = pem_conn.execute_dict(sql)
            if not status:
                current_app.logger.error(str(webhooks))
                return False, internal_server_error(errormsg=webhooks)

        except Exception as e:
            current_app.logger.error(str(e))
            return False, internal_server_error(errormsg=e)

        # If webhook id is not specified then return error.
        if webhook_id is not None and len(webhooks['rows']) == 0:
            return False, not_found(
                errormsg=gettext("The specified webhook id not found."))

    # Delete webhook id from pem.webhook_endpoints table
    sql = render_template('alerts/sql/webhook/delete.sql',
                          delete_webhook=True,
                          placeholders=get_sql_placeholders(
                              delete_webhook_ids))

    status, result = pem_conn.execute_void(
        sql, delete_webhook_ids)
    if not status:
        current_app.logger.error(str(result))
        return status, internal_server_error(errormsg=result)
    return status, result
