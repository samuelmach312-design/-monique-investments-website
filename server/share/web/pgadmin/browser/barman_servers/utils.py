##########################################################################
#
# Postgres Enterprise Manager
#
# Copyright (C) 2016 - 2025, EnterpriseDB Corporation. All rights reserved.
#
##########################################################################

import json
from flask import current_app, render_template
from pgadmin.utils.ajax import internal_server_error, make_json_response, \
    bad_request
from flask_babel import gettext
from pgadmin.pem.utils.role import PEMRole

BARMAN_RLS_ROLE = 'pem_comp_barman'
BARMAN_RLS_ERROR_MSG = gettext(
    "User does not have privileges to manage the Barman Server."
)
manageBarman = PEMRole(
    BARMAN_RLS_ROLE,
    gettext('Manage Barman Server'),
    gettext('Manage Barman Server'),
    gettext('Privilege to manage the Barman Server.')
)

VALID_BACKUP_STATUS = [
    'FAILED',
    'DONE',
    'STARTED',
    'SYNCING',
    'WAITING_FOR_WALS'
]


def get_all_server_details(bsid, pem_conn):
    """

    :param bsid: Barman server id
    :param pem_conn: PEM Connection
    :return: list of servers
    """
    status, servers = pem_conn.execute_dict("""
    SELECT
        pbs.server,
        pbs.active,
        pbs.active::text as status,
        json_agg(
            json_build_object('name', d.key, 'value', d.value)
        ) AS data
    FROM pemdata.barman_server pbs
        JOIN json_each_text(pbs.config) d ON true
    WHERE tool_id = %s::int
        GROUP BY pbs.server, pbs.active
        ORDER BY 1, 2;
    """, (bsid,))
    if not status:
        return False, servers

    # Json comes as string, we need to convert it to dict
    for server in servers['rows']:
        server['data'] = json.loads(server['data'])

    return True, servers['rows']


def get_all_backup_details(bsid, pem_conn):
    """

    :param bsid: Barman server id
    :param pem_conn: PEM Connection
    :return: list of backups
    """
    status, backups = pem_conn.execute_dict("""
        SELECT
            psb.backup_id,
            psb.server,
            psb.begin_time,
            psb.end_time,
            pg_size_pretty(psb.size) AS size,
            psb.mode,
            LOWER(psb.status) AS status,
            COALESCE(psb.error, '') AS errmsg,
            json_agg(
                json_build_object('name', d.key, 'value', d.value)
            ) AS data
        FROM pemdata.barman_server_backup psb
            JOIN json_each_text(psb.data) d ON true
        WHERE tool_id = %s::int
            GROUP BY psb.backup_id, psb.server,
            psb.begin_time, psb.end_time,
            psb.size, psb.mode, psb.status, psb.error
            ORDER BY 4 DESC, 2 ASC;
    """, (bsid,))
    if not status:
        return False, backups

    # Json comes as string, we need to convert it to dict
    for backup in backups['rows']:
        backup['data'] = json.loads(backup['data'])
        for obj in backup['data']:
            if obj['name'] == 'included_files':
                if obj['value'] is None:
                    obj['value'] = ""
                else:
                    obj['value'] = ", ".join(json.loads(obj['value']))
    return True, backups['rows']
