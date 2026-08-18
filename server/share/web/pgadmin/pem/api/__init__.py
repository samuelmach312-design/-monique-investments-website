##########################################################################
#
# Postgres Enterprise Manager
#
# Copyright (C) 2016 - 2025, EnterpriseDB Corporation. All rights reserved.
#
##########################################################################

"""A Module container for keeping all the submodules for PEM api."""

import flask
from flask_babel import gettext
from flask import url_for
from pgadmin.pem.utils import pem_connection, pem_token_required, \
    release_token
from .utils import ApiModule, get_base_url
from pgadmin.pem.utils.role import PEMRole, RoleRequired
from pgadmin.utils.csrf import pgCSRFProtect
import config

MODULE_NAME = 'api'

# Initialise the module
blueprint = ApiModule(MODULE_NAME, __name__)

restAPIRole = PEMRole(
    'pem_rest_api', gettext('REST API access'), None,
    gettext(
        'A privilege to access the REST API'
    )
)


@blueprint.token_auth_route("/token/", methods=('POST',))
@pgCSRFProtect.exempt
def token():
    """
    Endpoint to authenticate token request and issue new token if
    authentication was successful.
    :return: Authentication token
    """

    from pgadmin.pem import _pem
    from flask import current_app, request, Response
    from pgadmin.utils.exception import ConnectionLost
    from pgadmin.utils.ajax import internal_server_error
    import json
    resp = None

    try:
        d = request.get_json()
        return _pem.generate_token(d['username'], d['password'])
    except _pem.LoginRequired as lr:
        return Response(
            response=json.dumps({'errormsg': lr.msg}),
            status=401,
            content_type='application/json'
        )
    except ConnectionLost:
        return ConnectionLost(
            'PEM Server',
            current_app.config.get('PEM_DB_NAME', 'pem'),
            None
        )
    except RoleRequired:
        raise RoleRequired(
            gettext(
                "User does not have permission to access the REST API. "
                "Please contact the administrator to grant the privilege "
                "role 'pem_rest_api'."
            ), restAPIRole.privilege, _name=gettext(restAPIRole.name)
        )
    except Exception as e:
        current_app.logger.error(e, exc_info=True)

        return internal_server_error(errormsg=str(e))


@blueprint.token_route("/token/", methods=('DELETE',))
@pgCSRFProtect.exempt
@pem_token_required
def delete_token():
    """
    Endpoint to invalidate given token before their expiry.

    :param pem_conn: PEM connection object
    :return: Response
    """
    return release_token()


@blueprint.route("/")
@pgCSRFProtect.exempt
def index():
    """Show the api documentation, when try to access the api index."""

    return flask.make_response(
        flask.render_template('pem/rest_api.html',
                              url=url_for('api.rest_api_index')
                              ),
        200, {'Content-Type': 'text/html'}
    )


@blueprint.route("/REST_API_INDEX.json", endpoint="rest_api_index")
@pgCSRFProtect.exempt
def rest_api_json():
    """REST API document JSON"""
    return flask.make_response(
        flask.render_template(
            'pem/REST_API_INDEX.json',
            base_url=get_base_url(),
            company_short_name=config.SHORT_COMPANY_NAME.upper(),
            company_long_name=config.LONG_COMPANY_NAME,
            company_website=config.COMPANY_SITE,
            company_contact_email=config.COMPANY_CONTACT_EMAIL,
            api_versions=[{'v1': url_for('v1_api.index'),
                           'v2': url_for('v2_api.index'),
                           'v3': url_for('v3_api.index'),
                           'v4': url_for('v4_api.index'),
                           'v5': url_for('v5_api.index'),
                           'v6': url_for('v6_api.index'),
                           'v7': url_for('v7_api.index'),
                           'v8': url_for('v8_api.index'),
                           'v9': url_for('v9_api.index'),
                           'v10': url_for('v10_api.index'),
                           'v11': url_for('v11_api.index'),
                           'v12': url_for('v12_api.index'),
                           'v13': url_for('v13_api.index'),
                           'v14': url_for('v14_api.index'),
                           'v15': url_for('v15_api.index')}]
        ),
        200, {'Content-Type': 'application/json'}
    )
