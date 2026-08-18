##########################################################################
#
# Postgres Enterprise Manager
#
# Copyright (C) 2016 - 2025, EnterpriseDB Corporation. All rights reserved.
#
##########################################################################

"""Email groups API"""

from pgadmin.pem.api.utils import ApiView
from pgadmin.utils.ajax import make_response, make_json_response, \
    internal_server_error, precondition_required, success_return, \
    bad_request
from pgadmin.pem.monitor.alerts.email import insert_email_group, \
    validate_insert_email_group, update_email_group, \
    validate_update_email_group, insert_email_group_options, \
    update_email_group_options
from pgadmin.pem.utils import get_sql_placeholders
from flask_babel import gettext
from flask import render_template, request
from functools import wraps
api_versions_v5 = list(ApiView.api_versions)[4:]


class EmailGroupsApiView(ApiView):
    """
    This class provide APIs to configure the email groups.
    """

    endpoint = 'email_group_config'
    url = '/email/groups/'
    pk = 'email_group_id'

    # Api version from v5 till latest
    # ['v5_api', 'v6_api', 'v7_api', 'v8_api']
    api_versions = api_versions_v5
    methods = ['GET', 'DELETE', 'POST', 'PUT']

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
            self.template_path = 'alerts/sql/email_group'

            return f(self, *args, **kwargs)
        return wrap

    @check_precondition
    def get(self, email_group_id=None):
        """
        This function will return the list of email groups.

        :param email_group_id: email group id for which information
        will be fetched.

        Method: GET
        URL: /api/v1/email/groups
        DESCRIPTION: All the email groups will be returned.

        Method: GET
        URL: /api/v1/email/groups/1
        DESCRIPTION: Email groups with id 1 will be returned.

        Input Data:
        Valid email group id.

        e.g.
        /api/v1/email/groups/1

        :return:
        [
          {"to_addr":"email_1@email.com", "from_time":"00:00:00", .....},
          {"to_addr":"email_2@email.com", "from_time":"00:00:00", .....},
          ...
        ]

        """
        sql = render_template(
            "/".join([self.template_path, 'list.sql']),
            email_group_id=email_group_id
        )

        try:
            status, email_group = self.conn.execute_dict(sql)

            if not status:
                return internal_server_error(errormsg=email_group)

        except Exception as e:
            return internal_server_error(str(e))

        if email_group_id is not None and len(email_group['rows']) == 0:
            return make_json_response(
                status=404, success=0,
                errormsg=gettext("The specified email id is not found.")
            )

        return make_response(email_group['rows'])

    @check_precondition
    def delete(self, email_group_id):
        """
        This function will delete the email group.

        :param email_group_id: Email group Id for which information
        will be deleted.

        Method: DELETE
        URL: /api/v1/email/groups/<email_id>

        Input Data:
        Valid email group id to delete the email group.

        e.g.
        /api/v1/email/groups/234

        :return:

        Below is the expected result.

        status: 200 OK
        {
          "success":1,
          "info":"Email group deleted successfully.",
          "result":null,
          "errormsg":"",
          "data":null
        }

        """
        # First check email id exists or not.
        sql = render_template(
            "/".join([self.template_path, 'list.sql']),
            email_group_id=email_group_id
        )

        try:
            status, email_groups = self.conn.execute_dict(sql)

            if not status:
                return internal_server_error(errormsg=email_groups)

        except Exception as e:
            return internal_server_error(str(e))

        # If email id is not specified then return error.
        if email_group_id is not None and len(email_groups['rows']) == 0:
            return make_json_response(
                status=404, success=0,
                errormsg=gettext("The specified email id not found.")
            )

        sql = render_template(
            "/".join([self.template_path, 'delete.sql']),
            placeholders=get_sql_placeholders([email_group_id]),
            delete_email_group=True
        )

        try:
            email_group_ids = []
            email_group_ids.append(email_group_id)

            status, result = \
                self.conn.execute_void(sql, email_group_ids)

            if not status:
                return internal_server_error(result)

        except Exception as e:
            return internal_server_error(str(e))

        return success_return(message=gettext(
            'Email group deleted successfully.')
        )

    @check_precondition
    def put(self, email_group_id):
        """
        This function will update email group options.

        :param email_group_id: Email Id for which alert email groups
        information will be updated.

        Method: PUT
        URL: /api/v1/email/groups/<email_group_id>

        Input Data: Below are the json input format required to update
        email groups.

        Example input data as below.
        {
          "name":"email_group_name",
          "id": "3",
          "options":
          {
            'changed': [
              {
                "to_addr": "email_1@email.com",
                "from_addr": "email_1@email.com",
                "from_time": "09:07:08",
                "to_time": "23:00:00",
                "oid": "2"
              }
            ],
            'added': [
              {
                "to_addr": "email_1@email.com",
                "from_addr": "email_1@email.com",
                "from_time": "09:07:08",
                "to_time": "23:00:00"
              }
            ],
            'deleted': [
              {
                "oid": "1"
              }
            ]
          }
        }

        :return:

        Below is the expected result.

        status: 200 OK
        {
          "success":1,
          "info":"Email group updated successfully.",
          "result":null,
          "errormsg":"",
          "data":null
        }

        """
        # First check alert template id exists or not.
        if email_group_id <= 0:
            return make_json_response(
                status=404, success=0,
                errormsg=gettext("Invalid email id.")
            )

        data = request.get_json()

        # Check for empty data(dict)
        if not bool(data):
            return make_json_response(
                status=400, success=0,
                errormsg=gettext(
                    "Please specify input data for which you wish to "
                    "update the email groups."
                )
            )

        sql = render_template(
            "/".join([self.template_path, 'list.sql']),
            email_group_id=email_group_id
        )
        self.conn.execute_void('BEGIN')

        try:
            status, email_grps = self.conn.execute_dict(sql)

            if not status:
                self.conn.execute_void('ROLLBACK')
                return internal_server_error(errormsg=email_grps)

        except Exception as e:
            self.conn.execute_void('ROLLBACK')
            return internal_server_error(str(e))

        # If alert template id is not specified then return error.
        if email_group_id is not None and len(email_grps['rows']) == 0:
            return make_json_response(
                status=404, success=0,
                errormsg=gettext(
                    "The specified email group options are "
                    "not available"
                )
            )

        # set default 'to_time' & 'from_time' if not provided
        if 'added' in data['options']:
            for option in data['options']['added']:
                if 'to_time' not in option:
                    option['to_time'] = '23:59:59'
                if 'from_time' not in option:
                    option['from_time'] = '00:00:00'

        # First validate all input parameters
        status, result = validate_update_email_group(data, pem_conn=self.conn)
        if not status:
            self.conn.execute_void('ROLLBACK')
            return bad_request(result)

        if 'name' in data:
            status, result = update_email_group(data['name'], email_group_id,
                                                pem_conn=self.conn)
            if not status:
                self.conn.execute_void('ROLLBACK')
                return internal_server_error(errormsg=result)
        if 'options' in data:
            if 'deleted' in data['options']:
                sql = render_template(
                    "/".join([self.template_path, 'delete.sql']),
                    delete_email_group=False,
                    delete_from_email_group=False
                )

                try:
                    email_group_ids = []
                    for d_rows in data['options']['deleted']:
                        email_group_ids.append(d_rows['oid'])

                    status, result = self.conn.execute_void(
                        sql, {'email_group_ids': email_group_ids})

                    if not status:
                        self.conn.execute_void('ROLLBACK')
                        return internal_server_error(result)

                except Exception as e:
                    self.conn.execute_void('ROLLBACK')
                    return internal_server_error(str(e))

            if 'changed' in data['options']:
                for row_ in data['options']['changed']:
                    status, result = update_email_group_options(
                        row_, email_group_id, pem_conn=self.conn)
                    if not status:
                        self.conn.execute_void('ROLLBACK')
                        return result

            if 'added' in data['options']:
                for row_ in data['options']['added']:
                    status, result = insert_email_group_options(
                        row_, email_group_id, pem_conn=self.conn
                    )
                    if not status:
                        self.conn.execute_void('ROLLBACK')
                        return internal_server_error(errormsg=result)

        self.conn.execute_void('COMMIT')
        return success_return(
            message=gettext('Email group updated successfully.')
        )

    @check_precondition
    def post(self):
        """
        This function will create new email group with at least
        one email group option.

        Method: POST
        URL: /api/v1/email/groups

        Input Data: Below are the json input format required to create
        email group.

        Example input data as below.
        {
          "name":"email_group_name",
          "options": [
            {
              "to_addr": "email_1@email.com",
              "from_addr": "email_1@email.com",
              "from_time": "09:07:08",
              "to_time": "23:00:00"
            }
          ]
        }

        :return:

        Below is the expected result.

        status: 200 OK
        {
          "success":1,
          "info":"Email group created successfully.",
          "result":null,
          "errormsg":"",
          "data":null
        }

        """

        data = request.get_json()

        # Check for empty data(dict)
        if not bool(data):
            return make_json_response(
                status=404, success=0,
                errormsg=gettext(
                    "Please specify input data for which you wish to "
                    "create the alert template."
                )
            )

        if 'name' not in data:
            return make_json_response(
                status=404, success=0,
                errormsg=gettext("Please specify email group name.")
            )

        # set default 'to_time' & 'from_time' if not provided
        for option in data['options']:
            if 'to_time' not in option:
                option['to_time'] = '23:59:59'
            if 'from_time' not in option:
                option['from_time'] = '00:00:00'

        self.conn.execute_void('BEGIN')
        # First validate all input parameters
        status, result = validate_insert_email_group(data, pem_conn=self.conn)
        if not status:
            self.conn.execute_void('ROLLBACK')
            return bad_request(result)

        status, result = insert_email_group(data['name'], data['options'],
                                            pem_conn=self.conn)
        if not status:
            self.conn.execute_void('ROLLBACK')
            return result

        self.conn.execute_void('COMMIT')
        return success_return(
            message=gettext('Email group created successfully.')
        )
