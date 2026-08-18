##########################################################################
#
# Postgres Enterprise Manager
#
# Copyright (C) 2016 - 2022, EnterpriseDB Corporation. All rights reserved.
#
##########################################################################

class ApiRegistry(object):
    """
    Api view registry class this will keep track of all api views with the
    """
    views = dict()
    routes = dict()
    blueprints = []

    @staticmethod
    def create_view(module, view):
        """
        Responsible for creating views

        :param module: api module (blueprint) name (e.g v1, v2, v3, v4 etc)
        :param view: view to be registered under given module.
        :return:
        """
        ApiRegistry.views.setdefault(module, []).append(view)

    @staticmethod
    def create_route(module, callback, route, *args, **kwargs):
        """
        Responsible for creating routes

        :param module: api module (blueprint) name (e.g v1, v2 etc)
        :param callback: callback function to register.
        :param route: route for callback.
        :param args:
        :param kwargs:
        :return:
        """

        ApiRegistry.routes.setdefault(module, []).append(
            {
                'callback': callback,
                'route': route,
                'args': args,
                'kwargs': kwargs
            }
        )
