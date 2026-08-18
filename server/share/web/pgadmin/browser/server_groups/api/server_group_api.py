##########################################################################
#
# Postgres Enterprise Manager
#
# Copyright (C) 2016 - 2025, EnterpriseDB Corporation. All rights reserved.
#
##########################################################################


""" Api for Server Group """

from flask_babel import gettext as _
from functools import wraps
from flask import render_template, request, jsonify
from flask_security import current_user
from pgadmin.utils.ajax import forbidden, make_response, \
    precondition_required, make_json_response, \
    internal_server_error, success_return, bad_request
from pgadmin.pem.api.utils import ApiView
from pgadmin.pem.utils.data_type import validate_boolean, \
    validate_empty_string, validate_integer
from flask_babel import gettext
import json
api_versions_v8 = list(ApiView.api_versions)[7:]


SG_NOT_FOUND_ERROR = 'The specified server group could not be found.'
SAME_NAME_ERROR_MSG = gettext(
    "Cannot have two groups with same name!") + "\n" + gettext(
    "Please specify another name!")
NOT_AVL_ERROR_MSG = gettext(
    "This name is not available for a group!") + "\n" + gettext(
    "Please specify another name!")


def check_precondition(f):
    """
    This function will behave as a decorator which will checks
    database connection before running view, it will also attaches
    manager,conn & template_path properties to self
    """

    @wraps(f)
    def wrap(self, *args, **kwargs):
        self.conn = kwargs.pop('pem_conn')

        # we will set template path for sql scripts
        self.template_path = 'server_groups/sql'

        return f(self, *args, **kwargs)

    return wrap


class ServerGroupApiView(ApiView):
    """
    A server group view with CRUD operations.
    """

    endpoint = ''

    url = '/server_group/'
    parent_ids = []
    ids = [{'type': 'int', 'id': 'gid'}]
    methods = ['GET', 'PUT', 'POST', 'DELETE']

    # Api version from v8 till latest
    # ['v8_api']
    api_versions = api_versions_v8
    properties = dict({
        "name": validate_empty_string(_("Name cannot be empty")),
        "heartbeat_tolerance": validate_integer(
            _("Please provide numeric value for heartbeat_tolerance field")
        )
    })

    def __init__(self, *args, **kwargs):
        super(ApiView, self).__init__(*args, **kwargs)
        self.params = self.properties

    @check_precondition
    def get(self, id=None):
        res = []
        # Fetch List of Server Groups
        sql = render_template(
            "/".join([self.template_path, 'properties.sql']),
            is_rest_api=True
        )
        status, groups = self.conn.execute_dict(sql)

        if not status:
            return internal_server_error(errormsg=groups)

        if id is not None:
            for row in groups['rows']:
                if row['id'] == id:
                    return make_response(row)

            return make_json_response(
                status=404, success=0,
                errormsg=_(
                    "The specified server group id is "
                    "not available."
                )
            )
        res = groups['rows']

        return make_response(res)

    @check_precondition
    def post(self):
        data = request.form if request.form else json.loads(
            request.data.decode()
        )
        if 'name' in data and data['name']:
            sql = "SELECT s.id FROM pem.server_group s WHERE s.name = %s::text"
            status, res = self.conn.execute_scalar(sql, (data['name'],))
            if res is None:
                sql = 'SELECT pem.create_server_group(%s::text)'
                status, res = self.conn.execute_scalar(sql, (data['name'],))

                if not status:
                    return internal_server_error(errormsg=res)

                if res > 0:
                    return success_return(message=_('Server Group created '
                                                    'successfully.'))
                else:
                    return bad_request(self.get_error_msg(res))
            else:
                return bad_request(self.get_error_msg(-2))

        else:
            return make_json_response(
                status=400,
                success=0,
                errormsg=gettext('No group name was specified')
            )

    @check_precondition
    def put(self, id=None):
        """Update the server-group"""

        data = request.form if request.form else\
            json.loads(request.data.decode())

        if 'name' not in data:
            return precondition_required(
                gettext("Couldn't find the name in the given details!")
            )

        # There can be only one record at most
        sql = "SELECT pem.rename_server_group(%s::int, %s::text)"
        status, res = self.conn.execute_scalar(sql, (id, data['name'],))

        if not status:
            return internal_server_error(errormsg='The specified server group '
                                                  'id is not available.')

        if res == 0:
            return success_return(message=_('Server Group updated '
                                            'successfully.'))
        else:
            return bad_request(self.get_error_msg(res))

    @check_precondition
    def delete(self, id):
        """Delete a server group node in the settings database"""

        if id == 0 or id == 1:
            return forbidden(gettext("Not allow to delete this group."))

        sql = "SELECT s.id FROM pem.server_group s WHERE s.id = %s::int"
        status, res = self.conn.execute_scalar(sql, (id,))

        if res is not None:

            # There can be only one record at most
            status, res = self.conn.execute_scalar(
                "SELECT pem.delete_server_group(%s, True,"
                " pem.current_user_id()::integer)""",
                (id,)
            )

            if not status:
                return internal_server_error(errormsg=res)

            return success_return(message=_('Server Group deleted '
                                            'successfully.'))

        return make_json_response(
            status=404, success=0,
            errormsg=_(
                "The specified server group id is "
                "not available."
            )
        )

    def get_error_msg(self, res):
        """
        Get proper error message
        :param res: Query response
        :return: message
        """
        if res == -1:
            return NOT_AVL_ERROR_MSG
        elif res == -2 or res == -3:
            return SAME_NAME_ERROR_MSG
        else:
            return gettext(
                'Unknown error adding a group with return id#%!') % res
