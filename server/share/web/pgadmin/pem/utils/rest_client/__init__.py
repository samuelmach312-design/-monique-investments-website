########################################################################
#
# Postgres Enterprise Manager
#
# Copyright (C) 2015 - 2025, EnterpriseDB Corporation
#
##########################################################################


from .registry import ClientRegistry


def get_rest_client(type, app=None):
    return ClientRegistry.create(type)


def init_app(app):
    ClientRegistry.load_clients()


def ping():

    for a in ClientRegistry.clients:
        client = ClientRegistry.clients[a]
        client.refresh()
