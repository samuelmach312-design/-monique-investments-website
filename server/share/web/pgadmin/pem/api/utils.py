##########################################################################
#
# Postgres Enterprise Manager
#
# Copyright (C) 2016 - 2025, EnterpriseDB Corporation. All rights reserved.
#
##########################################################################

"""Utilities functions for supporting the token based REST API routes."""

from functools import wraps
from flask_babel import gettext
import json

from pgadmin.utils import PgAdminModule
from pgadmin.pem.utils import ALL_API_MODULES
from .registry import ApiRegistry
from .view import ApiView, api_method_not_allowed
from flask import url_for


def get_base_url():
    from flask import request
    _INDEX_PATH = 'browser.index'
    wsgi_root_path = None
    if url_for(_INDEX_PATH) != '/browser/':
        wsgi_root_path = url_for(_INDEX_PATH).replace(
            '/browser/', ''
        )
    if wsgi_root_path is None:
        base_url = request.host_url.rstrip('/')
    else:
        base_url = '{0}{1}'.format(request.host_url,
                                   wsgi_root_path.lstrip('/'))
    return base_url


def _token_auth_route_wrapper(func, endpoint, rule):

    @wraps(func)
    def wrapper(*args, **kwargs):
        from flask import request, current_app
        from flask_login import current_user

        import config
        from pgadmin.utils.ajax import forbidden, unauthorized
        from pgadmin.pem import _pem

        if current_user and current_user.is_authenticated:
            return forbidden(gettext(
                'A logged in user can not access this route.'
            ))

        return func(*args, **kwargs)

    return wrapper


class ApiModule(PgAdminModule):
    """
    Base class for all api (token) modules.

    Only modules which are inherited from this class will support token based
    authentication and token based rest api.
    """

    def token_route(self, rule, **options):
        """Like :meth:`Flask.token_route` but for a blueprint.
        The endpoint for the
        :func:`url_for` function is prefixed with the name of the blueprint.
        """
        def decorator(f):
            """Wrapper function"""
            endpoint = options.pop("endpoint", f.__name__)
            self.add_url_rule(
                rule, endpoint, f, **options
            )
            return f
        return decorator

    def token_auth_route(self, rule, **options):
        """Like :meth:`Flask.token_route` but for a blueprint.
        The endpoint for the
        :func:`url_for` function is prefixed with the name of the blueprint.
        """
        def decorator(f):
            """Wrapper function"""
            endpoint = options.pop("endpoint", f.__name__)
            self.add_url_rule(
                rule, endpoint, _token_auth_route_wrapper(f, endpoint, rule),
                **options
            )
            return f
        return decorator

    def register(self, app, options):
        """
        Override the default register function to automatically register
        sub-modules at once.
        """
        self.submodules = list(app.find_submodules(self.import_name))

        super(PgAdminModule, self).register(app, options)

        for module in self.submodules:
            module.parentmodules.append(self)
            # Don't register the API Version bluetprint just yet, we'll call
            # it separately after registering all the related routes.
            if module.name not in app.blueprints.keys() and \
                    not isinstance(module, ApiVersionModule):
                app.register_blueprint(module)
                app.register_logout_hook(module)


class ApiVersionModule(ApiModule):

    api_versions = dict()

    def __new__(cls, name, import_name, **kwargs):
        url_prefix = kwargs.get('url_prefix')

        if url_prefix is None:
            raise TypeError('url_prefix must be specified.')

        if name in ApiVersionModule.api_versions:
            raise ValueError(
                'ApiVersionModule with name "{}" already exists'.format(
                    name)
            )

        for api_module_name, url_pref in list(
                ApiVersionModule.api_versions.items()
        ):
            if url_prefix == url_pref:
                raise ValueError(
                    'url_prefix "{}" of api module "{}" is conflicting with '
                    'url_prefix "{}" of api module "{}"'.format(
                        url_prefix, name, url_pref, api_module_name)
                )

        ApiVersionModule.api_versions[name] = url_prefix

        return super(ApiVersionModule, cls).__new__(cls)


def create_api_view(api_view):
    """
    Utility function to register view under given module.

    :param module: api module (blueprint) name (e.g v1, v2 etc)
    :param api_view: view to be registered under given module.
    :return:
    """

    for api_version in api_view.api_versions:
        if api_version not in ALL_API_MODULES:
            raise ValueError('Unknown api version module "{}"'.format(
                api_version)
            )

        ApiRegistry.create_view(api_version, api_view)


def create_api_route(module, callback, route, *args, **kwargs):
    """
    Utility function to register route under given module.

    :param module: api module (blueprint) name (e.g v1, v2 etc)
    :param callback: callback function to register.
    :param route: route for callback.
    :param args:
    :param kwargs:
    :return:
    """

    if module not in ALL_API_MODULES:
        raise ValueError('Unknown api module "{}"'.format(module))

    ApiRegistry.create_route(module, callback, route, *args, **kwargs)


def register_api_blueprint(api_blueprint):
    """
    This will add api modules (blueprints) in blacklisted module list and keep
    the track of such modules. As don't want them to register now. We'll be
    registering these blueprint after all respective token api view/s and token
    route/s are added to such blueprints.

    Use this function when you want to register any modules as ApiModules which
    has support api views and api routes.

    :param api_blueprint:
    :return:
    """
    import config

    ApiRegistry.blueprints.append(api_blueprint.import_name)
    module_blacklist = getattr(config, 'MODULE_BLACKLIST', [])
    module_blacklist.append(api_blueprint.__module__)

    getattr(config, 'MODULE_BLACKLIST', module_blacklist)


def register_api_views(api_blueprint):
    """
    This will look up for any token api view/s in ApiRegistry for given api
    module (blueprint) and register same to given module.

    :param api_blueprint:
    :return:
    """

    try:
        apiviews = ApiRegistry.views[api_blueprint.name]
    except KeyError:
        return

    for apiview in apiviews:

        view_func = apiview.as_view(apiview.endpoint)
        methods = getattr(apiview, 'methods', ['GET', 'PUT', 'POST', 'DELETE'])

        if 'GET' in methods:
            api_blueprint.add_url_rule(
                apiview.url, defaults={apiview.pk: None} if apiview.pk else {},
                view_func=view_func, methods=['GET', ]
            )

        if 'POST' in methods:
            api_blueprint.add_url_rule(
                apiview.url, view_func=view_func, methods=['POST', ]
            )

        # Allowed methods with id-attribute are: GET, PUT, and 'DELETE'
        methods = [
            method for method in methods if method in ['GET', 'PUT', 'DELETE']
        ]

        if apiview.pk is not None and len(methods) > 0:
            api_blueprint.add_url_rule(
                '%s<%s:%s>' % (apiview.url, apiview.pk_type, apiview.pk),
                view_func=view_func, methods=methods
            )


def register_api_routes(api_blueprint):
    """
    This will look up for any route/s in ApiRegistry for given api module
    (blueprint) and register same to given module.

    :param api_blueprint:
    :return:
    """
    try:
        apiroutes = ApiRegistry.routes[api_blueprint.name]
    except KeyError:
        return

    for apiroute in apiroutes:
        api_blueprint.add_url_rule(
            apiroute['route'],
            view_func=apiroute['callback'],
            *apiroute['args'],
            **apiroute['kwargs']
        )


def init_api(app):

    from importlib import import_module
    from pgadmin.utils.csrf import pgCSRFProtect

    for api_module in ApiRegistry.blueprints:
        app.logger.info('Examining potential api module: %s' % api_module)
        module = import_module(api_module)

        for key in list(module.__dict__.keys()):
            if isinstance(module.__dict__[key], PgAdminModule):

                api_blueprint = module.__dict__[key]

                # Register all the views & routes with API Bluerprints
                register_api_views(api_blueprint)
                register_api_routes(api_blueprint)

                app.logger.info('Registering blueprint module: %s' % module)
                if api_blueprint.name not in app.blueprints.keys():
                    # We've not registered the blueprint yet. Let's register
                    # it here.
                    app.register_blueprint(api_blueprint)
                    pgCSRFProtect.exempt(api_blueprint)
