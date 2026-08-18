##########################################################################
#
# pgAdmin 4 - PostgreSQL Tools
#
# Copyright (C) 2013 - 2025, The pgAdmin Development Team
# This software is released under the PostgreSQL Licence
#
##########################################################################

"""A blueprint module implementing the PEM postgres authentication."""

from flask import current_app, url_for, session, request, \
    redirect, Flask, flash
from flask_babel import gettext
from flask_security.utils import logout_user

from pgadmin.authenticate.internal import BaseAuthentication
from pgadmin.model import db, User
from pgadmin.utils import PgAdminModule, get_safe_post_login_redirect, \
    get_safe_post_logout_redirect
from pgadmin.utils.constants import PEM_INTERNAL


_PEM_AUTH_LOGOUT = 'pem_auth.logout'


class PEMAuthModule(PgAdminModule):
    def register(self, app, options):
        # Do not look for the sub_modules,
        # instead call blueprint.register(...) directly
        super().register(app, options)

    def get_exposed_url_endpoints(self):
        return [_PEM_AUTH_LOGOUT]


class PEMInternaluthentication(BaseAuthentication):
    """PEM Authentication Class using PEM backend database server"""
    DEFAULT_MSG = {
        'USER_DOES_NOT_EXIST': gettext('Incorrect username or password.'),
        'LOGIN_FAILED': gettext('Login failed'),
        'USER_NOT_PROVIDED': gettext('Username not provided'),
        'PASSWORD_NOT_PROVIDED': gettext('Password not provided'),
        'INVALID_USER': gettext('Username is not valid')
    }

    LOGOUT_VIEW = _PEM_AUTH_LOGOUT

    def get_source_name(self):
        return PEM_INTERNAL

    def get_friendly_name(self):
        return gettext("internal")

    def authenticate(self, form):
        username = form.data.get('email')
        password = form.data.get('password')

        from pgadmin.pem import _pem

        return _pem.authenticate(**form.data)

    def validate(self, form):
        username = form.data['email']
        password = form.data['password']

        if username is None or username == '':
            form.email.errors = list(form.email.errors)
            form.email.errors.append(gettext(
                self.messages('USER_NOT_PROVIDED')))
            return False, None
        if password is None or password == '':
            form.password.errors = list(form.password.errors)
            form.password.errors.append(
                self.messages('PASSWORD_NOT_PROVIDED'))
            return False, None

        return True, None

    def login(self, form):
        from pgadmin.pem import _pem

        username = form.data['email']
        user = getattr(form, 'user', None)

        if user is None:
            user = User.query.filter_by(
                username=username, auth_source=PEM_INTERNAL
            ).first()

        if user is None:
            current_app.logger.exception(
                self.messages('USER_DOES_NOT_EXIST'))
            return False, self.messages('USER_DOES_NOT_EXIST')

        # Login user through flask_security
        status = _pem.login_user(user)

        if not status:
            current_app.logger.exception(self.messages('LOGIN_FAILED'))
            return False, self.messages('LOGIN_FAILED')

        current_app.logger.info(
            "Internal user {0} logged in.".format(username)
        )

        return True, None
