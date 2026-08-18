##########################################################################
#
# Postgres Enterprise Manager
#
# Copyright (C) 2016 - 2025, EnterpriseDB Corporation. All rights reserved.
#
##########################################################################

import sys


"""
Define the schema of any data, and validate them using the utility function.

Schema is dictionary object of column definition:
schema={
    /* Identified of the column */
    'col1': {
        # Define whether the data will present in data.
        'required': True/False

        # Define the datatype of the data
        'type': int/str/dict/list/bool

        # A list can define the type of the object within it
        # Similary - an entity can also represents value from a ENUM.
        # Both of above can be by defineing the 'typeof' property.
        'typeof': 'enum'/dict/int/str/dict/list/bool,

        # Defines the ENUM values
        'values': [...],

        # User specified validator (a callable), which takes asserter, and the
        # current value for this column.
        # It takes priority over currently defined validators
        'validator': None,

        # Defines the schema of the object represented by the dict/object
        # within the list
        schema: {
           ...
        }
    },
    ...
}
"""


def dict_validator(_asserter, _name, _info, _resp):
    schema_validator(_asserter, _name, _info['schema'], _resp)


def type_input_validator(_asserter, _name, _info, _resp):
    type_validator(
        _asserter, '_', {
            'type': _info['typeof'], 'required': True,
        }, {'_': _resp}
    )


def enum_validator(_asserter, _name, _info, _resp):
    _asserter.assertTrue(
        _resp in _info['values'],
        "'{0}' is not a valid ENUM for the column({1}). Possible Values "
        "are: '{2}'".format(
            _resp, _name, _info['values']
        )
    )


def range_validator(_asserter, _name, _column, _resp):
    if 'max' in _column[_name] and _column[_name]['max'] is not None:
        _asserter.assertTrue(
            _resp <= _column[_name]['max'],
            "'{0}' is greater than {1}. (value: {2})".format(
                _name, _column[_name]['max'], _resp
            )
        )
    if 'min' in _column[_name] and _column[_name]['min'] is not None:
        _asserter.assertTrue(
            _resp >= _column[_name]['min'],
            "'{0}' is less than {1}. (value: {2})".format(
                _name, _column[_name]['min'], _resp
            )
        )


def type_validator(_asserter, _name, _column, _resp):
    if _column['required'] or _name in _resp:
        _asserter.assertTrue(
            (
                isinstance(_resp[_name], _column['type'])
            ),
            'Expcted datatype for "{0}" was of type "{2}", but - it is of '
            'type "{1}" in {3}.'.format(
                _name, type(_resp[_name]), _column['type'], _resp
            )
        )
        if _name in _resp and _resp[_name] is not None:
            if _column['type'] == list:
                typeof = _column['typeof']
                if 'validator' in _column and callable(_column['validator']):
                    validator = _column['validator']
                elif typeof == dict:
                    validator = dict_validator
                elif typeof == 'enum':
                    validator = enum_validator
                elif typeof == 'range':
                    validator = range_validator
                else:
                    validator = type_input_validator

                for obj in _resp[_name]:
                    validator(_asserter, _name, _column, obj)
            else:
                validator = None
                if 'validator' in _column and callable(_column['validator']):
                    validator = _column['validator']
                elif _column['type'] == dict:
                    validator = dict_validator
                elif 'typeof' in _column:
                    typeof = _column['typeof']
                    if typeof == 'enum':
                        validator = enum_validator
                    elif typeof == 'range':
                        validator = range_validator

                if validator is not None:
                    validator(_asserter, _name, _column, _resp[_name])


def schema_validator(_asserter, _name, _schema, _response):
    for name in _schema:
        column = _schema[name]
        if column['required']:
            _asserter.assertTrue(
                name in _response,
                '{0} not found in resp: {1}'.format(
                    name, _response
                )
            )
            type_validator(_asserter, name, column, _response)
        elif name in _response:
            type_validator(_asserter, _name, column, _response)
    return True
