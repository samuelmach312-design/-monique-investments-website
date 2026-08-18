##########################################################################
#
# Postgres Enterprise Manager
#
# Copyright (C) 2016 - 2025, EnterpriseDB Corporation. All rights reserved.
#
##########################################################################

"""Helper function to format the schedule values"""
import json


def _format_list_data(value):
    """
    Converts to proper array data for sql
    Args:
        value: data to be converted

    Returns:
        Converted data
    """
    if not isinstance(value, list):
        return json.loads(value)
    return value


def format_schedule_data(data):
    def format_list(data, name):
        if name in data and data[name] is not None:
            data[name] = _format_list_data(
                data[name]
            )

    # Convert python list literal to postgres array literal.
    format_list(data, 'jscminutes')
    format_list(data, 'jschours')
    format_list(data, 'jscweekdays')
    format_list(data, 'jscmonthdays')
    format_list(data, 'jscmonths')
