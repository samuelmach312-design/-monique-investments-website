##########################################################################
#
# Postgres Enterprise Manager
#
# Copyright (C) 2016 - 2025, EnterpriseDB Corporation. All rights reserved.
#
##########################################################################

"""PEM Monitoring Import/Export Utility functions"""
from pgadmin.pem import version as pem_version

CURRENT_EXPORT_VERSION = 2

# Here we will list down supported export version again list of
# supported schemas versions of PEM
# For example when user will try to import the export version 1
# then will first check if PEM schema supports that version
# This will be hard coded and needs to be maintained when export/import probe
# logic in incompatible with previous versions meaning any change in
# DB schema like probe tables, functions, trigger functions.
# Schema version mapping will be like '202107221' -> PEM 8.2
VALID_EXPORT_PROBE_VERSIONS = {
    1: [202107221, 202109211],
    2: [202112021]
}


def get_import_schema_version(version):
    """
    This function will return supported schema versions list
    :param version: Export version for JSON file
    :return: List of supported schema version for the import
    """
    return VALID_EXPORT_PROBE_VERSIONS.get(int(version), [])


def is_export_version_supported(version):
    """
    This function will verify if passed exported version is valid for the
    current PEM server.
    :param version: Export version for JSON file
    :return: True/False
    """
    schemas = get_import_schema_version(version)
    if len(schemas) == 0:
        return False
    # Irrespctive of the schema version, it's the import/export version that
    # we support.
    return True


def get_pem_installation_id(pem_conn):
    """
    This function will return pem unique installation id.
    :param pem_conn: PEM Connection
    :return: pem uid
    """
    status, result = pem_conn.execute_scalar("SELECT pem.system_uid()")
    if not status:
        return None
    return result
