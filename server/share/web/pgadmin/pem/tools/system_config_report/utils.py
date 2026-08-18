##########################################################################
#
# Postgres Enterprise Manager
#
# Copyright (C) 2016 - 2025, EnterpriseDB Corporation. All rights reserved.
#
##########################################################################
"""Implements System Config utility functions"""

import json


def get_agent_bound_servers(agent):
    """ function used to get agent bound local/remote servers"""
    if agent['bound_local_servers'] and len(agent['bound_local_servers']):
        # We get array of string for json[] type so we need to convert it
        temp = []
        for details in agent['bound_local_servers']:
            temp.append(json.loads(details))
        agent['bound_local_servers'] = temp

    if agent['bound_remote_servers'] and len(
        agent['bound_remote_servers']
    ):
        # We get array of string for json[] type so we need to convert it
        temp = []
        for details in agent['bound_remote_servers']:
            temp.append(json.loads(details))
        agent['bound_remote_servers'] = temp


def get_core_mem_disk_details(agent):
    """ function used to get agent cpu core, memory and disk utilization"""
    if agent['cpu_core_details'] and len(agent['cpu_core_details']):
        # We get array of string for json[] type so we need to convert it
        temp = []
        for details in agent['cpu_core_details']:
            temp.append(json.loads(details))
        agent['cpu_core_details'] = temp

    if agent['mem_details'] and len(agent['mem_details']):
        agent['mem_details'] = json.loads(agent['mem_details'])

    if agent['disk_utilization_details'] and \
            len(agent['disk_utilization_details']):
        # We get array of string for json[] type so we need to convert it
        temp = []
        for details in agent['disk_utilization_details']:
            temp.append(json.loads(details))
        agent['disk_utilization_details'] = temp


def get_table_index_summary(agent):
    """ function used to get table, indexes count summary"""
    if agent['db_objects_stats'] and len(agent['db_objects_stats']):
        # We get array of string for json[] type so we need to convert it
        temp = []
        for details in agent['db_objects_stats']:
            temp.append(json.loads(details))
        agent['db_objects_stats'] = temp


def get_server_details(res, result):
    # Counters
    total_servers = 0
    total_locally_managed_server = 0
    total_remotely_managed_server = 0
    total_unmanaged_server = 0
    total_pg_servers = 0
    total_epas_servers = 0
    total_unknwon_servers = 0
    for server in res['rows']:
        total_servers += 1
        # If agent id is not present then it is not managed by any agent
        if not server['agent_id']:
            total_unmanaged_server += 1
        elif server['is_remote_monitoring']:
            total_remotely_managed_server += 1
        else:
            total_locally_managed_server += 1

        _version = server['version']
        if _version and _version.find('EnterpriseDB') != -1:
            total_epas_servers += 1
        elif _version and _version.find('PostgreSQL') != -1:
            total_pg_servers += 1
        else:
            total_unknwon_servers += 1

        server_db_tablespace_details(server)
        get_table_index_summary(server)
        # converting the object count to dictionary and
        # adding it again to server
        server['object_count'] = json.loads(
            server['object_count'])

        result[server['group_id']]['servers'].append(server)
    return total_servers, total_unmanaged_server, \
        total_remotely_managed_server, total_locally_managed_server, \
        total_epas_servers, total_pg_servers, total_unknwon_servers


def server_db_tablespace_details(server):
    if server['db_details'] and len(server['db_details']):
        # We get array of string for json[] type so we need to convert it
        temp = []
        for details in server['db_details']:
            temp.append(json.loads(details))
        server['db_details'] = temp

    if server['tablespace_details'] and len(server['tablespace_details']):
        # We get array of string for json[] type so we need to convert it
        temp = []
        for details in server['tablespace_details']:
            temp.append(json.loads(details))
        server['tablespace_details'] = temp


def server_object_count(server):
    """ This function will create a dictionary containing the
    count of all the objects in the server"""
    server['object_count'] = {
        'database_count': server['num_databases'],
        'table_count': server['num_tables'],
        'view_count': server['num_views'],
        'function_count': server['num_functions'],
        'index_count': server['num_indexes'],
        'extension_count': server['num_extensions'],
        'foreign_key_count': server['num_foreign_keys'],
        'sequence_count': server['num_sequences'],
        'tablespace_count': server['num_tablespaces'],
        'schema_count': server['num_schemas'],
    }
