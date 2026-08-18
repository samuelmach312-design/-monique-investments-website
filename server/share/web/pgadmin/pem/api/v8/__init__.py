##########################################################################
#
# Postgres Enterprise Manager
#
# Copyright (C) 2016 - 2025, EnterpriseDB Corporation. All rights reserved.
#
##########################################################################

"""A Module to handle public api with token base authentication."""
import flask
from flask import url_for

from pgadmin.pem.api import get_base_url
from pgadmin.pem.api.utils import ApiVersionModule

from pgadmin.pem.api.utils import register_api_blueprint
from pgadmin.utils.csrf import pgCSRFProtect
import config

MODULE_NAME = 'v8_api'

# Initialise the module
blueprint = ApiVersionModule(MODULE_NAME, __name__, url_prefix='/api/v8')


@blueprint.route("/")
@pgCSRFProtect.exempt
def index():
    """Show the api documentation, when try to access the api index."""

    return flask.make_response(
        flask.render_template('pem/rest_api.html',
                              url=url_for('v8_api.rest_api_json')
                              ),
        200, {'Content-Type': 'text/html'}
    )


@blueprint.route("/REST_API_v8.json", endpoint="rest_api_json")
@pgCSRFProtect.exempt
def rest_api_json():
    """REST API document JSON"""
    return flask.make_response(
        flask.render_template(
            'pem/REST_API_v8.json',
            base_url=get_base_url(),
            company_short_name=config.SHORT_COMPANY_NAME.upper(),
            company_long_name=config.LONG_COMPANY_NAME,
            company_website=config.COMPANY_SITE,
            company_contact_email=config.COMPANY_CONTACT_EMAIL
        ),
        200, {'Content-Type': 'application/json'}
    )


# Register module (blueprint) as api module so that it will allow others to
# register flask views (methodviews) under this module.
register_api_blueprint(blueprint)
