##########################################################################
#
# Postgres Enterprise Manager
#
# Copyright (C) 2016 - 2025, EnterpriseDB Corporation. All rights reserved.
#
##########################################################################

"""Implements Custom Probes"""

import json
from flask import current_app, render_template, request, Response
from flask_babel import gettext
from pgadmin.utils.ajax import internal_server_error, make_json_response, \
    make_response, precondition_required, bad_request
from pgadmin.pem.monitor.utils.import_export import CURRENT_EXPORT_VERSION, \
    get_pem_installation_id, is_export_version_supported, \
    get_import_schema_version
from flask_security import login_required
from pgadmin.pem.utils import pem_connection
from . import utils
import config


@login_required
@utils.manageProbeRole.check_role(
    gettext("Logged-in user do not have permission to access custom probes.")
)
@pem_connection
def probes(show_system_probe=0, pem_conn=None):
    """
    This function will return the list of all the probes
    including system and custom.

    :param show_system_probe: True or False
    :param pem_conn: PEM Connection object.
    """

    status, response = utils.get_custom_probes(
        show_system_probe, pem_conn, None, True
    )
    if not status:
        return internal_server_error(errormsg=response)

    return make_response(
        response=response,
        status=200
    )


@login_required
@utils.manageProbeRole.check_role(
    gettext("Logged-in user do not have permission to save custom probes.")
)
@pem_connection
def save(pem_conn=None):
    """
    This function is used to store the custom probes configuration
    and newly created custom probes.

    :param pem_conn: PEM Connection object.
    """
    if request.data:
        custom_probe_data = json.loads(request.data.decode())
    else:
        custom_probe_data = request.args or request.form

    status = True
    result = None
    pem_conn.execute_void('BEGIN')
    try:
        if 'changed' in custom_probe_data:
            for row in custom_probe_data['changed']:

                if row.get('probe_name', False):
                    is_exists = utils.\
                        is_probe_exists(pem_conn, row['probe_name'],
                                        row['probe_id'])

                    if is_exists:
                        pem_conn.execute_void('ROLLBACK')
                        return precondition_required(
                            gettext("Probe with probe name "
                                    "{0} already "
                                    "exists".format(row['probe_name'])))

                # Update pem.probe table
                status, result = utils.update_probe(row, pem_conn)
                if not status:
                    pem_conn.execute_void('ROLLBACK')
                    return internal_server_error(errormsg=result)

                # If probe columns are changed then call
                # update_probe_columns function to save the data.
                if 'probe_columns' in row:
                    status, result = utils.update_probe_columns(
                        row['probe_columns'], pem_conn, row['probe_id']
                    )
                    if not status:
                        pem_conn.execute_void('ROLLBACK')
                        return internal_server_error(errormsg=result)

                # If alternate code are changed then call
                # update_alternate_code function to save the data.
                if 'alternate_code' in row:
                    status, result = utils.update_alternate_code(
                        row['alternate_code'], pem_conn, row['probe_id']
                    )
                    if not status:
                        pem_conn.execute_void('ROLLBACK')
                        return internal_server_error(errormsg=result)

        if 'added' in custom_probe_data:
            for row in custom_probe_data['added']:
                is_exists = utils.is_probe_exists(pem_conn, row['probe_name'])
                if is_exists:
                    pem_conn.execute_void('ROLLBACK')
                    return precondition_required(
                        gettext("Probe with probe name {0} already "
                                "exists".format(row['probe_name'])))
                # Insert into pem.probe table
                status, probe_id = utils.insert_probe(row, pem_conn)
                if not status:
                    pem_conn.execute_void('ROLLBACK')
                    return internal_server_error(errormsg=probe_id)

                # If probe columns are added then call
                # insert_probe_columns function to save the data.
                if 'probe_columns' in row:
                    status, result = utils.insert_probe_columns(
                        row['probe_columns'], pem_conn, probe_id
                    )
                    if not status:
                        pem_conn.execute_void('ROLLBACK')
                        return internal_server_error(errormsg=result)

                # If alternate code are added then call
                # insert_alternate_code function to save the data.
                if 'alternate_code' in row:
                    status, result = utils.insert_alternate_code(
                        row['alternate_code'], pem_conn, probe_id
                    )
                    if not status:
                        pem_conn.execute_void('ROLLBACK')
                        return internal_server_error(errormsg=result)

            # Create data and history table.
            status, result = pem_conn.execute_void(
                "SELECT pem.create_data_and_history_tables()"
            )
            if not status:
                pem_conn.execute_void('ROLLBACK')
                return internal_server_error(errormsg=result)

        if 'deleted' in custom_probe_data:
            probe_ids = ''
            system_probe_count = 0
            for row in custom_probe_data['deleted']:
                if not utils.is_system_probe(row['probe_id'], pem_conn):
                    probe_ids += str(row['probe_id']) + ','
                else:
                    system_probe_count += 1

            # If all the probes to be deleted are system probes then
            # rollback the transaction and return error message
            if len(custom_probe_data['deleted']) == system_probe_count:
                pem_conn.execute_void('ROLLBACK')
                return internal_server_error(
                    errormsg=gettext('System probe cannot be deleted')
                )

            # Update pem.probe table for deleted custom probes.
            probe_ids = probe_ids[:-1]

            status, result = utils.delete_probe(probe_ids, pem_conn)
            if not status:
                pem_conn.execute_void('ROLLBACK')
                return internal_server_error(errormsg=result)
    except Exception as e:
        pem_conn.execute_void('ROLLBACK')
        return internal_server_error(errormsg=str(e))

    pem_conn.execute_void('COMMIT')

    # Immediate refresh so the newly created custom probe appears
    # in pem.probe_target_view without waiting for the scheduled task.
    try:
        status, err = pem_conn.execute_void(
            "SELECT pem.refresh_stale_probe_view();"
        )
        if not status:
            current_app.logger.warning(
                "Immediate probe view refresh after "
                "custom probe create failed: %s", err
            )
    except Exception as e:
        current_app.logger.warning(
            "Exception during immediate probe view refresh "
            "after custom probe create: %s", e
        )

    return make_json_response(data=result)


@login_required
@pem_connection
def server_versions(pem_conn):
    sql = render_template('probes/sql/custom_probe/server_versions.sql')

    status, svr_ver = pem_conn.execute_dict(sql)

    if not status:
        return internal_server_error(errormsg=svr_ver)

    res = []

    for row in svr_ver['rows']:
        if row['id'] >= 20000:
            display_name = '{} {}'.format(config.SHORT_COMPANY_NAME.upper(),
                                          row['display_name'])
        else:
            display_name = row['display_name']

        res.append(
            {'label': display_name,
             'value': str(row['id']),
             'allowed_to_add': row['allowed_to_add']
             }
        )

    return make_json_response(data=res)


@login_required
@pem_connection
def get_extensions(pem_conn):
    sql = """SELECT DISTINCT extension_name
    FROM pemdata.oc_extension ORDER BY 1"""
    status, res = pem_conn.execute_dict(sql)
    if not status:
        return internal_server_error(errormsg=res)

    data = []
    for row in res['rows']:
        data.append({
            'label': row['extension_name'], 'value': row['extension_name']
        })
    return make_json_response(data=data)


@login_required
@pem_connection
def get_extension_versions(name, pem_conn=None):
    sql = f"""SELECT extension_version FROM pemdata.oc_extension
    WHERE extension_name = '{name}' ORDER BY 1"""
    status, res = pem_conn.execute_dict(sql)
    if not status:
        return internal_server_error(errormsg=res)
    data = []
    for row in res['rows']:
        data.append({
            'label': row['extension_version'],
            'value': row['extension_version']
        })
    return make_json_response(data=data)


@login_required
@utils.manageProbeRole.check_role(
    gettext("Logged-in user do not have permission to export custom probes.")
)
@pem_connection
def probe_export(pem_conn=None):
    if request.data:
        data = json.loads(request.data.decode())
    else:
        data = request.args or request.form

    probe_list = data.get('probes', [])
    if len(probe_list) == 0:
        return bad_request(
            errormsg=gettext("No probes to export")
        )
    status, result = utils.generate_export_probe_data(pem_conn, probe_list)
    if not status:
        return internal_server_error(errormsg=result)

    # ========================= IMPORTANT NOTE =========================
    # Here we will add Export "version" key for compatibility check
    # we need to update the "VALID_EXPORT_PROBE_VERSIONS" variables
    # in the utils.py when there is a change in probe schema which can
    # break the import/export logic, we will check this version while
    # importing the probes from json file
    # ==================================================================
    resp = Response(
        json.dumps({
            "version": CURRENT_EXPORT_VERSION,
            "probes": result
        }),
        mimetype='application/json'
    )

    return resp


@login_required
@utils.manageProbeRole.check_role(
    gettext("Logged-in user do not have permission to import custom probes.")
)
@pem_connection
def probe_import(pem_conn=None):
    # Set transaction for each probe insert
    # Check if probe already exits with the same internal name - Skip it
    # Try to insert the probe add a flg for success or error we need to add
    # colors for each line in the status message
    # { name: internal_name, msg: msg (success/skip/error),
    # is_error: true/false }
    # finally pem.create_data_and_history_tables() to create required objects
    if request.data:
        data = json.loads(request.data.decode())
    else:
        data = request.args or request.form

    # Verify the request
    if 'content' not in data or 'probes' not in data['content'] or \
            type(data['content']['probes']) is not list or \
            len(data['content']['probes']) == 0 or \
            'skip_overwrite' not in data:
        return bad_request(
            errormsg=gettext("Please provide valid JSON file")
        )

    # Check if export version is supported
    if 'version' not in data['content'] or not data['content']['version']:
        return bad_request(
            errormsg=gettext("Unable to verify the export version")
        )

    if not is_export_version_supported(data['content']['version']):
        return bad_request(
            errormsg=gettext(
                "The JSON file is incompatible with current version of PEM,"
                " the import is supported from following"
                " schema version(s) - {}".format(", ".join(
                    str(sv) for sv in
                    get_import_schema_version(CURRENT_EXPORT_VERSION)
                ))
            )
        )
    skip_overwrite = data['skip_overwrite']

    # Verify the inputs first
    status, msg = utils.validate_imported_probes_fields(
        pem_conn, data['content']['probes'])
    if not status:
        return bad_request(errormsg=msg)

    result = utils.insert_imported_probes(
        pem_conn, data['content']['probes'], skip_overwrite
    )
    return make_json_response(result=result)


def register_custom_routes(blueprint):
    blueprint.add_url_rule('/custom/probes/<int:show_system_probe>',
                           'custom_list', probes, methods=["GET"])
    blueprint.add_url_rule('/custom/save', 'custom_save',
                           save, methods=["PUT", "POST"])
    blueprint.add_url_rule('/server_versions', 'server_versions',
                           server_versions, methods=["GET"])
    blueprint.add_url_rule('/get_extensions', 'get_extensions',
                           get_extensions, methods=["GET"])
    blueprint.add_url_rule('/get_extension_versions/<string:name>',
                           'get_extension_versions',
                           get_extension_versions, methods=["GET"])
    blueprint.add_url_rule('/custom/export', 'custom_export',
                           probe_export, methods=["POST"])
    blueprint.add_url_rule('/custom/import', 'custom_import',
                           probe_import, methods=["POST"])
