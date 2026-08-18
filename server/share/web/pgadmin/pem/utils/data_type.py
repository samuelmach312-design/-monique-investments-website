##########################################################################
#
# Postgres Enterprise Manager
#
# Copyright (C) 2016 - 2025, EnterpriseDB Corporation. All rights reserved.
#
##########################################################################

"""A Module container for validating the type of the data."""

from flask_babel import gettext as _


def validate_boolean(message, allow_none=True):
    def validator(value):
        if not (
            (allow_none is True and value is None) or
            isinstance(value, bool)
        ):
            raise ValueError(_(message))
        return message
    return validator


def validate_empty_string(message, no_white_space=True, allow_none=True):
    def validator(value):
        if not (
            (allow_none is True and value is None) or
            value != '' or
            (no_white_space is True and len(str(value).strip()) == 0)
        ):
            raise ValueError(_(message))
        return value
    return validator


def validate_integer(message, max_value=None, min_value=None):
    def validator(value):
        try:
            value = int(value)
        except ValueError:
            raise ValueError(_(message))

        if max_value is not None and value > max_value:
            raise ValueError(_(message))

        if min_value is not None and value < min_value:
            raise ValueError(_(message))

        return value
    return validator
