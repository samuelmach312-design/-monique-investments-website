##########################################################################
#
# Postgres Enterprise Manager
#
# Copyright (C) 2016 - 2025, EnterpriseDB Corporation. All rights reserved.
#
##########################################################################

"""A Module container for keeping all the submodules for PEM."""

from pgadmin.utils import PgAdminModule
from pgadmin.utils.ajax import bad_request, internal_server_error, \
    success_return
from pgadmin.utils.csrf import pgCSRFProtect
from flask import request, url_for, session
from flask_babel import gettext
from flask_security import login_required

from pgadmin.pem._pem import init_app, version, clear_session
from pgadmin.pem.utils import pem_connection
from pgadmin.utils.menu import MenuItem

from .submodule import pem_modules
from pgadmin.pem._pem import encrypt as pem_encrypt


MODULE_NAME = 'pem'


class PEMModule(PgAdminModule):

    def __init__(self, name, import_name, **kwargs):
        super(PEMModule, self).__init__(name, import_name, **kwargs)
        self.submodules = pem_modules()

    def get_exposed_url_endpoints(self):
        """
        Returns:
            list: a list of url endpoints exposed to the client.
        """
        return [
            'pem.static',
            'pem.agent_alert_blackout',
            'pem.server_alert_blackout',
            'pem.alert_acknowledge',
            'pem.has_role',
        ]

    def get_own_menuitems(self):
        """
        Return a (set) of dicts of help menu items, with name, priority,
        URL, target and onclick code.
        """
        return {'help_items': [
            MenuItem(
                name='mnu_restapi',
                label=gettext('REST API Reference'),
                priority=100,
                target='pem_help',
                icon='fa fa-question',
                url=url_for('api.index')
            )
        ]}

    def on_logout(self):
        """
        Clear Session when the user logs out.
        """
        if '__pem_connection_manager' in session:
            clear_session()

    def register(self, app, options):
        """
        Override the default register function to automagically register
        sub-modules at once.
        """
        super().register(app, options)


# Initialise the module
blueprint = PEMModule(MODULE_NAME, __name__)


@blueprint.route("/")
def index():
    """Calling management index URL directly is not allowed."""
    return bad_request(gettext('This URL cannot be requested directly.'))


@blueprint.route("/info.js", endpoint="info_js")
@pgCSRFProtect.exempt
@pem_connection
def info(pem_conn=None):
    """PEM application & current user Information"""

    from flask import Response, render_template
    import config as _cfg

    return Response(
        response=render_template(
            'pem/js/info.js',
            company_short_name=_cfg.SHORT_COMPANY_NAME,
            company_long_name=_cfg.LONG_COMPANY_NAME,
            company_email=_cfg.COMPANY_CONTACT_EMAIL,
            company_website=_cfg.COMPANY_SITE,
            major_version=version.APP_MAJOR,
            minor_version=version.APP_MINOR,
            patch_version=version.APP_REVISION,
            version_number=version.APP_VERSION_INT,
            version_suffix=version.APP_SUFFIX,
        ),
        mimetype="application/javascript",
    )


@blueprint.route(
    '/alert/blackout/server/<int:sid>',
    methods=['PUT', 'DELETE'],
    endpoint="server_alert_blackout"
)
@login_required
@pem_connection
def server_alert_blackout(sid, pem_conn=None):
    """
    Update the blackout flag for the monitored database server.

    Parameters:
        sid      - server id (for which blackout flag is to be updated)
    """
    # PUT method results into error sometime (if not data read from the
    # request, hence - faking to read it.)
    params = request.data
    params = [
        False if request.method == 'DELETE' else True,
        sid
    ]

    sql = """UPDATE
                pem.server
            SET
                alert_blackout = (%s)::boolean
            WHERE
                id = (%s)::integer;"""

    status, res = pem_conn.execute_void(sql, params)
    if not status:
        return internal_server_error(errormsg=str(res))

    message = 'Disabled '
    operation = 'disable_alert_blackout'
    if params[0]:
        message = 'Enabled '
        operation = 'enable_alert_blackout'

    message += 'the alert blackout for the server'
    payload = {
        "AlertBlackoutValue": params[0],
        "IsAgent": False,
        "Ids": f'{sid}',
        "Scheduled": False,
        "JobID": None
    }
    sql = """INSERT INTO pem.event_history
                ("recorded_time", "user_name", "component",
                "operation", "message", "details")
            VALUES
                (current_timestamp, current_user, 'alert_blackout'::text,
                (%s)::text, (%s)::text, (%s)::text);"""

    status, res = pem_conn.execute_void(sql, [operation, message, payload])
    if not status:
        return internal_server_error(errormsg=str(res))

    return success_return()


@blueprint.route(
    '/alert/blackout/agent/<int:aid>',
    methods=['PUT', 'DELETE'],
    endpoint="agent_alert_blackout"
)
@login_required
@pem_connection
def agent_alert_blackout(aid, pem_conn=None):
    """
    Update the blackout flag for the monitored database agent.

    Parameters:
        aid      - agent id (for which blackout flag is to be updated)
    """
    # PUT method results into error sometime (if not data read from the
    # request, hence - faking to read it.)
    params = request.data
    params = [
        False if request.method == 'DELETE' else True,
        aid
    ]

    sql = """UPDATE
                pem.agent
            SET
                alert_blackout = (%s)::boolean
            WHERE
                id = (%s)::integer;"""

    status, res = pem_conn.execute_void(sql, params)
    if not status:
        return internal_server_error(errormsg=str(res))

    message = 'Disabled '
    operation = 'disable_alert_blackout'
    if params[0]:
        message = 'Enabled '
        operation = 'enable_alert_blackout'

    message += 'the alert blackout for the agent'

    payload = {
        "AlertBlackoutValue": params[0],
        "IsAgent": True,
        "Ids": f'{aid}',
        "Scheduled": False,
        "JobID": None
    }
    sql = """INSERT INTO pem.event_history
                ("recorded_time", "user_name", "component",
                "operation", "message", "details")
            VALUES
                (current_timestamp, current_user, 'alert_blackout'::text,
                (%s)::text, (%s)::text, (%s)::text);"""

    status, res = pem_conn.execute_void(sql, [operation, message, payload])
    if not status:
        return internal_server_error(errormsg=str(res))

    return success_return()


@blueprint.route(
    '/alert/acknowlege/<int:alert_id>',
    methods=['DELETE', 'PUT'],
    endpoint="alert_acknowledge"
)
@login_required
@pem_connection
def alert_toggle_ack(alert_id, pem_conn=None):
    """
    Update the acknowledged flag in pem.alert table.
    Parameters:
        alert_id: alert id for which acked flag is to be updated.
        acked_value: value of the acked flag.
    """
    params = request.data
    params = [
        False if request.method == 'DELETE' else True,
        alert_id
    ]

    sql = """
        UPDATE pem.alert SET acknowledged = (%s)::boolean
        WHERE id = (%s)::integer
    """

    status, res = pem_conn.execute_void(sql, params)
    if not status:
        return internal_server_error(errormsg=str(res))

    return success_return()


@blueprint.route(
    '/has_role/<string:role_name>',
    methods=['GET'],
    endpoint="has_role"
)
@login_required
def has_role(role_name):
    from pgadmin.utils.ajax import make_json_response
    from pgadmin.pem.utils.role import has_pem_role
    return make_json_response(data=has_pem_role(role_name))
