##########################################################################
#
# pgAdmin 4 - PostgreSQL Tools
#
# Copyright (C) 2013 - 2025, The pgAdmin Development Team
# This software is released under the PostgreSQL Licence
#
##########################################################################

from flask import current_app

from .registry import DriverRegistry


def get_driver(_type, app=None):

    if app is not None:
        DriverRegistry.load_modules(app)

    return DriverRegistry.get(_type)


def init_app(app):
    drivers = dict()

    setattr(app, '_pgadmin_server_drivers', drivers)
    DriverRegistry.load_modules(app)

    return drivers


def ping():
    for type in DriverRegistry._registry:
        # Checking for existence of the driver in the registry (PEM specific)
        driver = DriverRegistry._objects.get(type, None)
        if driver is not None:
            driver.gc_timeout()
