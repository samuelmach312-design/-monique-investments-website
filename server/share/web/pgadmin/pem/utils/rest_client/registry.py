########################################################################
#
# Postgres Enterprise Manager
#
# Copyright (C) 2015 - 2025, EnterpriseDB Corporation
#
##########################################################################

from abc import ABCMeta

from flask_babel import gettext


def _decorate_cls_name(module_name):
    length = len(__package__) + 1

    if len(module_name) > length and module_name.startswith(__package__):
        return module_name[length:]

    return module_name


class ClientRegistry(ABCMeta):
    """
    class ClientRegistry(object)
        Every Restclient will be registered automatically by its module name.

        This uses factory pattern to generate Restclient object based on its
        name automatically.

    Class-level Methods:
    ----------- -------
    * __init__(...)
        - It will be used to register type of Restclients. You don't need to
        call this function explicitly. This will be automatically executed,
        whenever we create class and inherit from BaseRestClient, it will
        register it as available client in ClientRegistry. Because - the
        __metaclass__ for ClientRegistry is set it to ClientRegistry, and it
        will create new instance of this ClientRegistry per class.

    * create(type, *args, **kwargs)
        - Create type of Restclient object for this remote server, from the
        available client list (if available, or raise exception).

    * load_clients():
        - Use this function from init_app(...) to load all available
        Restclients in the registry.
    """
    registry = None
    clients = dict()

    def __init__(cls, name, bases, d):

        # Register this type of driver, based on the module name
        # Avoid registering the BaseClient itself

        if name != 'BaseRestClient':
            ClientRegistry.registry[_decorate_cls_name(d['__module__'])] = cls

        ABCMeta.__init__(cls, name, bases, d)

    @classmethod
    def create(cls, name, **kwargs):

        if name in ClientRegistry.clients:
            return ClientRegistry.clients[name]

        if name in ClientRegistry.registry:
            ClientRegistry.clients[name] = \
                (ClientRegistry.registry[name])(**kwargs)
            return ClientRegistry.clients[name]

        raise NotImplementedError(
            gettext("Rest client '{0}' has not been implemented.").format(name)
        )

    @classmethod
    def load_clients(cls):
        # Initialize the registry only if it has not yet been initialized
        if ClientRegistry.registry is not None:
            return

        ClientRegistry.registry = dict()

        from importlib import import_module
        from werkzeug.utils import find_modules

        for module_name in find_modules(__package__, True):
            import_module(module_name)
