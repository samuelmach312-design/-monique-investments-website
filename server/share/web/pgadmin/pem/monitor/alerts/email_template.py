##########################################################################
#
# Postgres Enterprise Manager
#
# Copyright (C) 2016 - 2025, EnterpriseDB Corporation. All rights reserved.
#
##########################################################################

"""Implements custom email templates for alerts"""


import json
from flask import render_template, request
from pgadmin.utils.ajax import internal_server_error, \
    make_json_response, make_response
from flask_security import login_required
from pgadmin.pem.utils import pem_connection
from flask_babel import gettext
from . import utils


@login_required
@utils.configRole.check_role(
    gettext(
        "Logged-in user do not have permission to "
        "access custom email template list."
    )
)
@pem_connection
def email_template_list(pem_conn=None):
    """
    This function will return the list of custom email templates.

    :param pem_conn: PEM Connection object.
    """
    sql = render_template("alerts/sql/email_template/list.sql")
    # Execute the query.
    status, email_templates = pem_conn.execute_dict(sql)
    if not status:
        return internal_server_error(errormsg=email_templates)
    return make_response(
        response={"email_templates": email_templates["rows"]}, status=200
    )


@login_required
@utils.configRole.check_role(
    gettext("Logged-in user do not have permission to save email templates.")
)
@pem_connection
def email_template_save(pem_conn=None):
    """
    This function is used to save the email configured for alerts.

    :param pem_conn: PEM Connection object.
    """

    if request.data:
        data = json.loads(request.data.decode())
    else:
        data = request.args or request.form

    status = True
    result = None

    if len(data) > 0:
        pem_conn.execute_void("BEGIN")
        for row in data["changed"]:
            if "marked_for_deletion" in row and row["marked_for_deletion"]:
                # this is restore request, we need to
                # delete the custom email template
                status, res = delete(row)
            else:
                # Update request, we need to insert/update the
                # custom email template
                status, res = insert(row)
            if not status:
                pem_conn.execute_void("ROLLBACK")
                return internal_server_error(errormsg=gettext(res))
        pem_conn.execute_void("COMMIT")

    return make_json_response(data={"status": status, "result": result})


def validate_template(data, op="insert"):
    """
    This function will validate input parameters for email templates.

    :param data: contains email template options
    :param pem_conn: PEM Connection object
    """
    if "template" not in data or data["template"] is None or not \
            data["template"]:
        return False, gettext("Provide valid email template name.")

    if op == "insert":
        if "mail_message" not in data and "mail_subject" not in data:
            return False, gettext("Provide valid email subject or payload.")
        elif (
            "mail_message" in data and data["mail_message"] is None and not
            data["mail_message"]
        ):
            return False, gettext("Provide valid email payload.")
        elif "mail_message" not in data:
            # in case of insert we will need  subject field
            data["mail_message"] = None
        elif "mail_subject" not in data:
            # in case of insert we will need  subject field
            data["mail_subject"] = None
    return True, None


@pem_connection
def insert(data, pem_conn=None):
    # Validate the input data
    status, res = validate_template(data)
    if not status:
        return status, res

    sql = render_template("alerts/sql/email_template/insert.sql", **data)
    # Execute the query.
    status, res = pem_conn.execute_void(sql, data)
    if not status:
        return False, res
    return True, None


@pem_connection
def delete(data, pem_conn=None):
    status, res = validate_template(data, op="delete")
    if not status:
        return status, res
    sql = render_template("alerts/sql/email_template/delete.sql")
    # Execute the query.
    status, res = pem_conn.execute_void(sql, data)
    if not status:
        return False, res
    return True, None


def register_email_template_routes(blueprint):
    blueprint.add_url_rule(
        "/email_template/list",
        "email_template_list",
        email_template_list,
        methods=["GET"],
    )

    blueprint.add_url_rule(
        "/email_template/save",
        "email_template_save",
        email_template_save,
        methods=["PUT", "POST"],
    )
