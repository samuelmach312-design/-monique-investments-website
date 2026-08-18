##########################################################################
#
# Postgres Enterprise Manager
#
# Copyright (C) 2016 - 2025, EnterpriseDB Corporation. All rights reserved.
#
##########################################################################

"""Probe Config API"""

from flask import request, current_app
from flask_babel import gettext

from pgadmin.pem.api.utils import ApiView
from pgadmin.pem.monitor.probes import utils
from pgadmin.utils.ajax import make_response, make_json_response, \
    internal_server_error, success_return, bad_request, not_found


def transform(probe):
    """
    Transforming data as required
    :param probe: Probe data
    :return: Probe data
    """
    res = {'id': probe['probe_id'], 'name': probe['probe_name'],
           'internal_name': probe['internal_name'],
           'is_system_probe': probe['is_system_probe'],
           'level': probe['target_type'], 'enabled': probe['enabled'],
           'interval': probe['interval'], 'lifetime': probe['lifetime'],
           'collection_method': probe['collection_method'],
           'discard_history': probe['discard_history'],
           'platform': probe['platform'],
           'any_server_version': probe['any_server_version'],
           'probe_code': probe['probe_code'],
           'probe_columns': probe['probe_columns'],
           'alternate_code': probe['alternate_code']}

    return res


class ProbesApiView(ApiView):
    """
    API to expose the probes.
    """

    endpoint = 'probes'
    url = '/probe/'
    pk = 'probe_id'
    DB_EXTENSION = 1000
    conn = None

    def get(self, probe_id=None, pem_conn=None):
        """
        This function will return the list of all the probes
        and if probe id is specified then return information about
        that probe.

        :param probe_id: Probe Id for which information will be fetched.
        :param pem_conn: PEM Connection Object
        :return:
        """

        status, res = utils.get_custom_probes(True, pem_conn, probe_id, False)
        if not status:
            return not_found(errormsg=res)

        if probe_id is not None:
            if len(res['custom_probes']) != 1:
                return bad_request(errormsg=gettext(
                    "Couldn't find the probe!")
                )
            return make_response(transform(res['custom_probes'][0]))

        return make_response(
            [transform(probe) for probe in res['custom_probes']]
        )

    def post(self, pem_conn=None):
        """
        This function will create new custom probe.

        :param pem_conn: PEM Connection
        """
        data = request.get_json()

        if not isinstance(data, dict):
            return not_found(
                errormsg=gettext("Data must be in the form of dictionary.")
            )

        # If data is not supplied then return 404.
        if data is None or len(data) == 0:
            return not_found(
                errormsg=gettext("No data supplied to create custom probes.")
            )

        pem_conn.execute_void('BEGIN')
        try:
            # Insert into pem.probe table
            status, probe_id = utils.insert_probe(data, pem_conn)
            if not status:
                pem_conn.execute_void('ROLLBACK')
                return internal_server_error(errormsg=probe_id)

            # If probe columns are added then call
            # insert_probe_columns function to save the data.
            if 'probe_columns' in data:
                status, result = utils.insert_probe_columns(
                    data['probe_columns'], pem_conn, probe_id
                )
                if not status:
                    pem_conn.execute_void('ROLLBACK')
                    return internal_server_error(errormsg=result)

            # If alternate code are added then call
            # insert_alternate_code function to save the data.
            if 'alternate_code' in data:
                if data['collection_method'] == 's':
                    status, result = utils.insert_alternate_code(
                        data['alternate_code'], pem_conn, probe_id,
                        data['target_type']
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

        return make_json_response(
            data={'probe_id': probe_id},
            info=gettext("Custom probe created successfully.")
        )

    def put(self, probe_id=None, pem_conn=None):
        """
        This function will update the existing probe.

        :param probe_id: Probe Id for which information will be updated.
        :param pem_conn: PEM Connection
        """
        data = request.get_json()

        if not isinstance(data, dict):
            return not_found(
                errormsg=gettext("Data must be in the form of dictionary.")
            )

        # If data is not supplied then return 404.
        if data is None or len(data) <= 0:
            return not_found(
                errormsg=gettext("No data supplied to update probes.")
            )

        pem_conn.execute_void('BEGIN')
        try:
            # Add probe is in data.
            data['probe_id'] = probe_id
            if 'interval' not in data:
                if 'interval_min' in data and 'interval_sec' not in data:
                    data['interval'] = data['interval_min'] * 60
                elif 'interval_sec' in data and 'interval_min' not in data:
                    data['interval'] = data['interval_sec']
                elif 'interval_min' in data and 'interval_sec' in data:
                    data['interval'] = \
                        data['interval_min'] * 60 + data['interval_sec']

            # Update pem.probe table
            status, result = utils.update_probe(data, pem_conn)
            if not status:
                pem_conn.execute_void('ROLLBACK')
                return internal_server_error(errormsg=result)

            # If probe columns are changed then call
            # update_probe_columns function to save the data.
            if 'probe_columns' in data:
                status, result = utils.update_probe_columns(
                    data['probe_columns'], pem_conn, data['probe_id']
                )
                if not status:
                    pem_conn.execute_void('ROLLBACK')
                    return internal_server_error(errormsg=result)

            # If alternate code are changed then call
            # update_alternate_code function to save the data.
            if 'alternate_code' in data:
                status, result = utils.update_alternate_code(
                    data['alternate_code'], pem_conn, data['probe_id']
                )
                if not status:
                    pem_conn.execute_void('ROLLBACK')
                    return internal_server_error(errormsg=result)
        except Exception as e:
            pem_conn.execute_void('ROLLBACK')
            return internal_server_error(errormsg=str(e))

        pem_conn.execute_void('COMMIT')

        return success_return(gettext("Probe updated successfully."))

    def delete(self, probe_id=None, pem_conn=None):
        """
        This function will delete the custom probe.

        :param probe_id: Probe Id to delete.
        :param pem_conn: PEM Connection
        """

        pem_conn.execute_void('BEGIN')
        try:
            if utils.is_system_probe(probe_id, pem_conn):
                pem_conn.execute_void('ROLLBACK')
                return bad_request(gettext("System probe can't be deleted."))

            status, result = utils.delete_probe(probe_id, pem_conn)
            if not status:
                pem_conn.execute_void('ROLLBACK')
                return internal_server_error(errormsg=result)
        except Exception as e:
            pem_conn.execute_void('ROLLBACK')
            return internal_server_error(errormsg=str(e))

        pem_conn.execute_void('COMMIT')

        # Immediate refresh so deleted probe is removed from view promptly.
        try:
            status, err = pem_conn.execute_void(
                "SELECT pem.refresh_stale_probe_view();"
            )
            if not status:
                current_app.logger.warning(
                    "Immediate probe view refresh after "
                    "custom probe delete failed: %s", err
                )
        except Exception as e:
            current_app.logger.warning(
                "Exception during immediate probe view "
                "refresh after custom probe delete: %s", e
            )

        return success_return(gettext("Probe deleted successfully."))
