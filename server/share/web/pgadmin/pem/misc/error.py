##########################################################################
#
# Postgres Enterprise Manager
#
# Copyright (C) 2016 - 2025, EnterpriseDB Corporation. All rights reserved.
#
##########################################################################

"""Handle Errors for the application."""

import re
from xml.etree.ElementTree import Element, SubElement

import json
from flask import request
from flask_babel import gettext
from werkzeug.exceptions import HTTPException
from pgadmin.pem.utils import prettify


def pgarray_to_pythonarray(param1, param2):
    # unimplemented
    pass


ERROR_TYPE_DICT = {
    '1': "Insufficient information is available between the start "
         "date/time and the end date/time or threshold to generate "
         "the report.",
    '2': "The specified date range or threshold is invalid.",
    '201': "Couldn't find the chart in the Postgres Enterprise "
           "Manager Server.",
    '203': "Server(s) and/or Agent(s) do not exist any more.",
    '204': "One or more probes required to render this chart no longer exist.",
    '101': "Couldn't find this chart in the Postgres Enterprise Manager "
           "Server.\nIt has been removed by the author.",
    '102': "This chart cannot be find in the Postgres Enterprise Manager"
           "Server.",
    '103': "Agent information cannot be determined to generate the data for "
           "this chart.",
    '104': "Server information cannot be determined to generate the data "
           "for this chart.",
    '105': "Agent information cannot be determined to generate the data "
           "for this chart.\n\nIs this server bound to any agent?",
    '106': "Database information is available to generate the data for "
           "this chart.",
    '108': "One or more probes required to render this chart no longer exist."
}


class PEMChartStatus:
    SUCCESS = 1
    DETAILS = 3
    NOT_ENOUGH_DATA = 4
    INFO = 5
    WARNING = 7
    ERROR = 32


class PEMErrorType:
    NORMAL = 1
    PLAINSTRING = 2
    STRING = 3
    XML = 4
    JSON = 5
    CHART_METRIC = 6
    CM_REPORT = 7


#########
##
# PEM Specific Exceptions
##
#########
class PEMHTTPException(HTTPException):

    def __init__(self, message, status_code=500):
        HTTPException.__init__(self)
        self.msg = message
        self.code = status_code

    def get_body(self, environ=None, scope=None):
        return self.msg

    def get_headers(self, environ=None, scope=None):
        return [('Content-Type', 'text/plain; charset=utf-8')]


class PEMHTMLException(HTTPException):

    def __init__(self, message, status_code=500):
        HTTPException.__init__(self)
        self.msg = message
        self.code = status_code

    def get_body(self, environ=None, scope=None):
        body = ""
        # TODO:: Append Logo
        root = Element("html")
        # html_append_logo(root, 'error.png')
        div = SubElement(root, 'div', id='ReportHeader')
        error = SubElement(div, 'h1')
        error.text = "Postgres Enterprise Manager&#8482 - Error"
        div1 = SubElement(root, 'div', id='ReportDetails')
        pre = SubElement(
            div1,
            'pre',
            style='padding-top: 50px padding-bottom: 50px white-space: '
                  'pre-wrap white-space: -moz-pre-wrap white-space: '
                  '-pre-wrap white-space: -o-pre-wrap word-wrap: break-word'
        )
        pre.text = self.msg
        body = prettify(root)

        return body

    def get_headers(self, environ=None, scope=None):
        return [('Content-Type', 'text/html; charset=utf-8')]


class PEMJSONException(HTTPException):

    def __init__(self, message, status_code=500, probe_error=False):
        HTTPException.__init__(self)
        self.msg = message
        self.code = status_code
        self.probe_error = probe_error

    def get_body(self, environ=None, scope=None):
        return json.dumps({
            'error': self.msg,
            'success': PEMChartStatus.ERROR,
            'status_code': self.code,
            'probe_error': self.probe_error,
        })

    def get_headers(self, environ=None, scope=None):
        return [('Content-Type', 'application/json; charset=utf-8')]


class PEMXMLException(HTTPException):

    def __init__(self, message, status_code=500):
        HTTPException.__init__(self)
        self.msg = message
        self.code = status_code

    def get_body(self, environ=None, scope=None):
        root = Element('resultset')
        error = SubElement(root, 'error')
        error.text = self.msg
        return prettify(root)

    def get_headers(self, environ=None, scope=None):
        return [('Content-Type', ' text/xml; charset=utf-8')]


def raise_exception(res_str, status_code):
    """

    This function raises the JSON exception according to response string
    :param res_str: response string
    :param status_code: status code
    :raises : JSON Exception
    """
    message = ERROR_TYPE_DICT.get(res_str, None)
    raise PEMJSONException(gettext(message), status_code)


def error_metrics(e_type, orig_msg, msg, status_code):
    """
    This function returns error message
    :param e_type: error type
    :param orig_msg: original message
    :param msg: message
    :param status_code: status code
    :return: message
    """
    if e_type == PEMErrorType.CM_REPORT:
        res_str = orig_msg.strip() if orig_msg else msg[6:].strip()
        if re.search(r'^202:', res_str) is not None:
            matches = re.search(r'^202:', res_str)
            objs = []
            pgarray_to_pythonarray(matches[1], objs)
            if objs[0] is False:
                raise PEMJSONException(
                    gettext("""The server - '%s' is no longer exist, hence the
                    threshold value cannot be generated.""") % objs[1]
                )
            else:
                raise PEMJSONException(
                    gettext("""The agent - '%s' is no longer exist, hence the
                    threshold value cannot be generated.""") % objs[1]
                )
        else:
            raise_exception(res_str, status_code)

    elif e_type == PEMErrorType.CHART_METRIC:
        res_str = msg[6:].strip()

        if re.search(r'^107[|]', res_str) is not None:
            matches = re.search(r'^107[|]', res_str)
            msg = gettext(
                "The probe - '%s' couldn't find in the Postgres Enterprise "
                "Manager Server.\nIt might have been deleted." %
                matches[1])
        else:
            msg = ERROR_TYPE_DICT.get(res_str, None)

    return msg


def error_return(
    msg, e_type=PEMErrorType.NORMAL, orig_msg=None, status_code=503,
    probe_error=False
):
    # probe_error is added to help frontent differentiate between
    # dependency probe error and other errors
    """Return an error document."""
    if e_type:
        # Some older APIs is used pass boolean value for error in string
        if isinstance(e_type, bool):
            if e_type:
                e_type = PEMErrorType.STRING
            else:
                e_type = PEMErrorType.NORMAL
        elif not isinstance(e_type, int):
            e_type = PEMErrorType.STRING
        elif e_type > PEMErrorType.CM_REPORT:
            e_type = PEMErrorType.NORMAL
    else:
        e_type = PEMErrorType.STRING

    msg = error_metrics(e_type, orig_msg, msg, status_code)

    if e_type == PEMErrorType.XML:
        raise PEMXMLException(msg, status_code)

    elif e_type == PEMErrorType.PLAINSTRING:
        raise PEMHTTPException(msg, status_code)

    elif e_type == PEMErrorType.NORMAL:
        raise PEMHTMLException(msg, status_code)

    elif e_type == PEMErrorType.JSON:
        raise PEMJSONException(msg, status_code, probe_error)

    raise PEMHTTPException(msg, status_code)


# Return an empty XML document to indicate success.
def success_return():
    # Return an empty result set to indicate success.
    root = Element('resultset')
    return prettify(root)


def http_check_string(param, required=True, na_null=False,
                      na_false=False, error_type=PEMErrorType.XML):
    """Verify presence of a string parameter."""
    request.values = request.json if request.json is not None \
        else request.values
    if required and (
        param not in request.values or
        request.values.get(param) == ""
    ):
        error_return("Parameter not set: %s" % param, error_type)
    if param in request.values and request.values.get(param).strip() != "":
        return request.values.get(param)
    elif na_null:
        return None
    elif na_false:
        return False
    else:
        return ""


def http_check_numeric(param, required=True, na_null=False,
                       error_type=PEMErrorType.XML):
    """Verify presence of a numeric parameter."""
    request.values = request.json if request.json is not None else \
        request.values
    if required and (
        param not in request.values or
        request.values.get(param) == ""
    ):
        error_return("Parameter not set: %s" % param, error_type)

    if param in request.values and request.values.get(param).strip() != "":
        try:
            return int(request.values.get(param))
        except ValueError:
            return float(request.values.get(param))
    elif param in request.values and request.values.get(param) == "" and \
            na_null is False:
        return request.values.get(param)
    elif na_null:
        return None
    return 0


def is_numeric(var):
    try:
        float(var)
        return True
    except (ValueError, TypeError):
        return False


def return_int(name, value):
    root = Element('resultset')
    header = SubElement(root, 'header')
    column = SubElement(header, 'column', type='int4', size=str(4))
    column.text = str(name)

    row = SubElement(root, 'row')
    datum = SubElement(row, 'datum')
    datum.text = str(value)

    return prettify(root)
