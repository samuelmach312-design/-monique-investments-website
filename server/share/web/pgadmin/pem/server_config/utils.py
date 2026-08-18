##########################################################################
#
# Postgres Enterprise Manager
#
# Copyright (C) 2016 - 2025, EnterpriseDB Corporation. All rights reserved.
#
##########################################################################

"""Implements Server Configuration utilites functions"""

import json
import config as global_config
from flask import render_template
from flask_babel import gettext
from pgadmin.pem.utils import pem_connection, pem_encrypt
from pgadmin.utils.ajax import internal_server_error, \
    make_response as ajax_response, success_return


@pem_connection
def config(param=None, pem_conn=None):
    """Return a list of configuration parameters for pem server."""
    sql = render_template('server_config/sql/config_list.sql', param=param)
    status, res = pem_conn.execute_dict(sql)

    if not status:
        return internal_server_error(errormsg=res)

    data = []
    if 'rows' in res:
        for row in res['rows']:
            if row['datatype'] == 'bool' or row['datatype'] == 'boolean':
                row['value'] = (row['value'] == 'TRUE')
            elif row['datatype'] == 'integer':
                row['value'] = int(row['value']) \
                    if row['value'] else row['value']
            elif row['datatype'] == 'enum':
                row['options'] = json.loads(row['options'])
                row['value'] = int(row['value']) \
                    if row['value'] else row['value']
        data = res['rows']

    if param is not None:
        if len(data) == 0:
            return ajax_response(
                status=404,
                response=gettext(
                    "Can't find the given configuration parameter!"
                )
            )
        return ajax_response(response=data[0])

    return ajax_response(response=data)


def transform_integer(_value):
    try:
        return str(int(_value))
    except ValueError:
        return None
    except Exception:
        return None


def transform_bool(_value):
    if _value is True:
        return 't'
    return 'f'


def transform_boolean(_value):
    if _value is True:
        return 'true'
    return 'false'


def transform_password(_value):
    if _value:
        if global_config.SUPPORT_FIPS_140_3_ENCRYPTION_ONLY:
            # Uses the latest encryption
            return pem_encrypt(_value)
        else:
            # Uses the old encryption
            return pem_encrypt(_value, False, None, '20110912')
    return ''


def translators(pem_conn, _param=None):
    status, res = pem_conn.execute_dict(
        render_template('server_config/sql/types.sql', param=_param)
    )

    if not status:
        return internal_server_error(errormsg=res)

    result = dict()

    for type_combo in res['rows']:
        datatype = type_combo['datatype']
        if datatype == 'integer':
            func = transform_integer
        elif datatype == 'bool':
            func = transform_bool
        elif datatype == 'boolean':
            func = transform_boolean
        elif datatype == 'password':
            func = transform_password
        else:
            func = None
        for param in type_combo['params']:
            result[param] = func

    return result


@pem_connection
def bulk_update(_configs, pem_conn=None):

    transformers = translators(pem_conn)
    cfgs = list()

    # Loop to make the update query.
    for cfg in _configs:
        if cfg['param'] in transformers:
            func = transformers[cfg['param']]
            if func is not None:
                v = func(cfg['value'])
            else:
                v = cfg['value']
            cfgs.append(dict({'param': cfg['param'], 'value': v}))
        else:
            cfgs.append({'param': cfg['param'], 'value': cfg['value']})

    sql = render_template('server_config/sql/update.sql', configs=cfgs)
    status, res = pem_conn.execute_void(sql)
    if not status:
        return internal_server_error(errormsg=res)

    # All done. Return successfully.
    return success_return(message=gettext('Saved'))


@pem_connection
def update(_param, _value, pem_conn=None):
    transformers = translators(pem_conn, _param)

    if _param not in transformers:
        return ajax_response(
            status=404,
            response=gettext("Can't find the given configuration parameter!")
        )

    func = transformers[_param]
    if func is not None:
        _value = func(_value)

    sql = render_template(
        'server_config/sql/update.sql',
        configs=[{'param': _param, 'value': _value}]
    )

    status, res = pem_conn.execute_void(sql)
    if not status:
        return internal_server_error(errormsg=res)

    # All done. Return successfully.
    return success_return(message=gettext('Updated!'))
