##########################################################################
#
# Postgres Enterprise Manager
#
# Copyright (C) 2016 - 2025, EnterpriseDB Corporation. All rights reserved.
#
##########################################################################

"""Implements email for alerts"""


import json
import copy
import re
from flask import render_template, request
from flask_babel import gettext
from flask_security import login_required

from pgadmin.pem.utils import pem_connection, get_sql_placeholders
from pgadmin.utils.ajax import internal_server_error, \
    make_json_response, make_response

from . import utils


@login_required
@utils.configRole.check_role(
    gettext("Logged-in user do not have permission to access email list.")
)
@pem_connection
def email_list(pem_conn=None):
    """
    This function will return the list of email groups and options.

    :param pem_conn: PEM Connection object.
    """
    sql = render_template("alerts/sql/email_group/list.sql")

    # Execute the query.
    status, email_group = pem_conn.execute_dict(sql)

    if not status:
        return internal_server_error(errormsg=email_group)

    new_val_list = []
    email_group_multiple_options = list()
    for row in email_group["rows"]:
        new_val = dict()
        email_options = []
        if row["oid"] is not None:
            if row["from_addr"] is not None and row["to_addr"] is not None:
                if (email_group["rows"].index(row)) + 1 \
                        != len(email_group["rows"]):
                    if (row["gid"] ==
                        email_group["rows"][email_group["rows"].index(row) + 1]
                            ["gid"]):
                        email_group_multiple_options.append(
                            {
                                "oid": row["oid"],
                                "gid": row["gid"],
                                "from_addr": row["from_addr"],
                                "to_addr": row["to_addr"],
                                "cc_addr": row["cc_addr"],
                                "bcc_addr": row["bcc_addr"],
                                "reply_to_addr": row["reply_to_addr"],
                                "subject_prefix": row["subject_prefix"],
                                "from_time": row["from_time"],
                                "to_time": row["to_time"],
                            }
                        )
                        continue
                    else:
                        email_options.append(
                            {
                                "oid": row["oid"],
                                "gid": row["gid"],
                                "from_addr": row["from_addr"],
                                "to_addr": row["to_addr"],
                                "cc_addr": row["cc_addr"],
                                "bcc_addr": row["bcc_addr"],
                                "reply_to_addr": row["reply_to_addr"],
                                "subject_prefix": row["subject_prefix"],
                                "from_time": row["from_time"],
                                "to_time": row["to_time"],
                            }
                        )
                        email_group_multiple_options.append(
                            {
                                "oid": row["oid"],
                                "gid": row["gid"],
                                "from_addr": row["from_addr"],
                                "to_addr": row["to_addr"],
                                "cc_addr": row["cc_addr"],
                                "bcc_addr": row["bcc_addr"],
                                "reply_to_addr": row["reply_to_addr"],
                                "subject_prefix": row["subject_prefix"],
                                "from_time": row["from_time"],
                                "to_time": row["to_time"],
                            }
                        )
                    if len(email_group_multiple_options) > 0:
                        p_copy_list = \
                            copy.deepcopy(email_group_multiple_options)
                        new_val["options"] = p_copy_list
                        del email_group_multiple_options[:]
                    if row["id"] is not None and row["name"] is not None:
                        new_val["id"] = row["id"]
                        new_val["name"] = row["name"]
                    new_val_list.append(new_val)
                else:
                    # check if <Default> email group is present with single
                    # or multiple options
                    if len(email_group_multiple_options) != 0:
                        email_group_multiple_options.append(
                            {
                                "oid": row["oid"],
                                "gid": row["gid"],
                                "from_addr": row["from_addr"],
                                "to_addr": row["to_addr"],
                                "cc_addr": row["cc_addr"],
                                "bcc_addr": row["bcc_addr"],
                                "reply_to_addr": row["reply_to_addr"],
                                "subject_prefix": row["subject_prefix"],
                                "from_time": row["from_time"],
                                "to_time": row["to_time"],
                            }
                        )
                        p_copy_list = \
                            copy.deepcopy(email_group_multiple_options)
                        new_val["options"] = p_copy_list
                        del email_group_multiple_options[:]
                    else:
                        email_options.append(
                            {
                                "oid": row["oid"],
                                "gid": row["gid"],
                                "from_addr": row["from_addr"],
                                "to_addr": row["to_addr"],
                                "cc_addr": row["cc_addr"],
                                "bcc_addr": row["bcc_addr"],
                                "reply_to_addr": row["reply_to_addr"],
                                "subject_prefix": row["subject_prefix"],
                                "from_time": row["from_time"],
                                "to_time": row["to_time"],
                            }
                        )
                        new_val["options"] = email_options
                    if row["id"] is not None and row["name"] is not None:
                        new_val["id"] = row["id"]
                        new_val["name"] = row["name"]
                    new_val_list.append(new_val)
        else:
            # <Default> email group with no option associated with it
            if row["name"] == gettext("<Default>"):
                new_val["options"] = []
                new_val["id"] = row["id"]
                new_val["name"] = row["name"]
                new_val_list.append(new_val)
    return make_response(response={"email_alerts": new_val_list}, status=200)


@login_required
@utils.configRole.check_role(
    gettext(
        "Logged-in user do not have permission to save email configuration.")
)
@pem_connection
def configure(pem_conn=None):
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
        email_data = data
        pem_conn.execute_void("BEGIN")

        if "changed" in email_data:
            for row in email_data["changed"]:
                # Update pem.email_group table
                if (
                    "name" not in row and "options" not in
                    row and "marked_for_deletion" not in row
                ):
                    pem_conn.execute_void("ROLLBACK")
                    return internal_server_error(
                        errormsg=gettext(
                            "Provide name or one email group option.")
                    )

                # validate the input data
                status, result = validate_update_email_group(row)
                # if data is not validated
                if not status:
                    pem_conn.execute_void("ROLLBACK")
                    return internal_server_error(errormsg=result)

                if (
                    "marked_for_deletion" not in row or
                    "marked_for_deletion" in row and not row[
                        "marked_for_deletion"]
                ):
                    if "name" in row:
                        status, result = \
                            update_email_group(row["name"], row["id"])
                        if not status:
                            pem_conn.execute_void("ROLLBACK")
                            return internal_server_error(errormsg=result)
                    if "options" in row:
                        if not ("changed" in row["options"]) and not (
                            "added" in row["options"]
                        ):
                            pem_conn.execute_void("ROLLBACK")
                            return internal_server_error(
                                gettext(
                                    "Provide valid format for email "
                                    "Options")
                            )
                        if "changed" in row["options"]:
                            for row_ in row["options"]["changed"]:
                                if (
                                    "marked_for_deletion" not in row or
                                    "marked_for_deletion" in row and not row[
                                        "marked_for_deletion"]
                                ):
                                    status, res = update_email_group_options(
                                        row_, row["id"]
                                    )
                                    if not status:
                                        pem_conn.execute_void("ROLLBACK")
                                        return res

                        if "added" in row["options"]:
                            for row_ in row["options"]["added"]:
                                status, result = insert_email_group_options(
                                    row_, row["id"]
                                )
                                if not status:
                                    pem_conn.execute_void("ROLLBACK")
                                    return internal_server_error(
                                        errormsg=result)

            # Check for delete email group and email group options
            delete_email_group_ids = []
            delete_email_group_option_ids = []
            for row in email_data["changed"]:
                # Update pem.alert_template table
                if "marked_for_deletion" in row and row["marked_for_deletion"]:
                    delete_email_group_ids.append(row["id"])
                else:
                    if "options" in row:
                        if "changed" in row["options"]:
                            for row_ in row["options"]["changed"]:
                                if (
                                    "marked_for_deletion" in row_ and row_[
                                        "marked_for_deletion"]
                                ):
                                    delete_email_group_option_ids.append(
                                        row_["oid"])

            if len(delete_email_group_option_ids) > 0:
                # Delete group email id from pem.email_group_option table
                sql = render_template(
                    "alerts/sql/email_group/delete.sql",
                    delete_email_group=False,
                    delete_from_email_group=False,
                )

                # Check is there any data of gid

                status, res = pem_conn.execute_void(
                    sql, {'email_group_ids':[delete_email_group_option_ids]}
                )
                if not status:
                    pem_conn.execute_void("ROLLBACK")
                    return internal_server_error(errormsg=result)

                # Delete id from pem.email_group table
                sql = render_template(
                    "alerts/sql/email_group/delete.sql",
                    delete_email_group=False,
                    delete_from_email_group=True,
                )

                # Check is there any data of gid
                status, result = pem_conn.execute_void(sql)
                if not status:
                    pem_conn.execute_void("ROLLBACK")
                    return internal_server_error(errormsg=result)

            if len(delete_email_group_ids) > 0:
                # Delete group email id from pem.email_group table
                sql = render_template(
                    "alerts/sql/email_group/delete.sql",
                    delete_email_group=True,
                    placeholders=get_sql_placeholders(delete_email_group_ids)
                )

                # Check is there any data of gid
                status, result = pem_conn.execute_void(
                    sql, delete_email_group_ids
                )
                if not status:
                    pem_conn.execute_void("ROLLBACK")
                    return internal_server_error(errormsg=result)

        if "added" in email_data:
            for row in email_data["added"]:
                # Validate input data
                status, result = validate_insert_email_group(row)
                # if data is not validated raise it
                if not status:
                    pem_conn.execute_void("ROLLBACK")
                    return internal_server_error(errormsg=result)
                status, result = insert_email_group(
                    row["name"], row["options"])
                if not status:
                    pem_conn.execute_void("ROLLBACK")
                    return internal_server_error(errormsg=result)

        pem_conn.execute_void("COMMIT")

    return make_json_response(data={"status": status, "result": result})


def validate_update_email_group(data, pem_conn=None):
    """
    This function will validate input parameters for email groups.

    :param data: contains email group options
    :param pem_conn: PEM Connection object
    """
    # If email group name is provided then it should not be empty.
    if "name" in data:
        if data["name"] is None or not data["name"]:
            return False, gettext("Provide valid email group name.")

    # At least one email group option should be present.
    if "options" in data:
        if "added" in data["options"]:
            for option in data["options"]["added"]:
                status, result = validate_email_group_options(option)
                if not status:
                    return status, result
        if "changed" in data["options"]:
            if len(data["options"]["changed"]) <= 0:
                return False, gettext(
                    "Provide valid data for email group " "options.")
            for option in data["options"]["changed"]:
                if not option.get('marked_for_deletion'):
                    status, result = validate_email_group_options(option)
                    if not status:
                        return status, result

        if "deleted" in data["options"]:
            for option in data["options"]["deleted"]:
                if "oid" not in option:
                    return False, gettext(
                        "Provide valid email group " "option id.")

    return True, gettext("")


def validate_email_group_options(option):
    """
    This function will validate parameters for email group options.
    :param option: contains email group options
    """

    regex = (
        "^[a-zA-Z0-9_+&*-]+(?:\\.[a-zA-Z0-9_+&*-]+)*@"
        "(?:[a-zA-Z0-9-]+\\.)+[a-zA-Z]{2,7}$"
    )
    to_addr_regex = (
        r"^([a-zA-Z0-9_+&*-]+(?:\.[a-zA-Z0-9_+&*-]+)*@"
        r"(?:[a-zA-Z0-9-]+\.)+[a-zA-Z]{2,7}"
        r")(,\s*([a-zA-Z0-9_+&*-]+(?:\.[a-zA-Z0-9_+&*-]+)*@"
        r"(?:[a-zA-Z0-9-]+\.)+[a-zA-Z]{2,7}))*$"
    )

    if (
        "from_addr" not in option or "from_addr" in option and not re.search(
            regex, option["from_addr"])
    ):
        return False, gettext("Provide valid email " "sender address.")
    if (
        "to_addr" not in option or "to_addr" in option and not re.search(
            to_addr_regex, option["to_addr"])
    ):
        return False, gettext("Provide valid email " "receiver address.")
    if "to_time" not in option:
        return False, gettext("Provide valid to-from time.")
    if "from_time" not in option:
        return False, gettext("Provide valid to-from time.")

    return True, None


@login_required
@pem_connection
def update_email_group(email_group_name, gid, pem_conn=None):
    """

    :param email_group_name: Email group name
    :param gid: Email group id
    :param pem_conn: PEM Connection object
    """
    status = True
    result = None

    # Update pem.email_group table
    if email_group_name is not None:
        sql = render_template(
            "alerts/sql/email_group/update.sql",
            update_name=True,
            name=email_group_name,
            id=gid,
        )
        status, result = pem_conn.execute_void(sql)
        if not status:
            return status, gettext(result)

    return status, result


@login_required
@pem_connection
def update_email_group_options(email_options, gid, pem_conn=None):
    """
    :param email_options: contains email options
    :param gid: email group id
    :param pem_conn: PEM Connection object
    """
    data = dict()
    status = True
    result = None

    if "to_addr" in email_options:
        data["grp_to"] = email_options["to_addr"]

    if "cc_addr" in email_options:
        data["grp_cc"] = email_options["cc_addr"]

    if "bcc_addr" in email_options:
        data["grp_bcc"] = email_options["bcc_addr"]

    if "from_addr" in email_options:
        data["grp_from"] = email_options["from_addr"]

    if "reply_to_addr" in email_options:
        data["grp_reply_to"] = email_options["reply_to_addr"]

    if "subject_prefix" in email_options:
        data["grp_subject_prefix"] = email_options["subject_prefix"]

    if "from_time" in email_options:
        data["time_from"] = email_options["from_time"]

    if "to_time" in email_options:
        data["time_to"] = email_options["to_time"]

    # Update pem.email_group_options table
    if len(data) > 0:
        sql = render_template(
            "alerts/sql/email_group/update.sql",
            update_name=False,
            id=email_options["oid"],
            data=data,
        )

        status, result = pem_conn.execute_void(sql)
        if not status:
            return False, internal_server_error(errormsg=result)

    return status, result


def validate_insert_email_group(data, pem_conn=None):
    """
    This function will validate input parameters for email groups.
    :param data: contains email group options
    :param pem_conn: PEM Connection object
    """
    # If email group name is provided then it should not be empty.
    if "name" in data:
        if data["name"] is None or not data["name"]:
            return False, gettext("Provide valid email group name.")
    else:
        return False, gettext("Email group name cannot be empty.")

    # At least one email group option should be present.
    if "options" in data:
        if len(data["options"]) == 0:
            return False, gettext("Provide at least one email group option.")
        for option in data["options"]:
            status, result = validate_email_group_options(option)
            if not status:
                return status, result
    else:
        return False, gettext("Provide at least one email group option.")

    return True, gettext("")


@login_required
@pem_connection
def insert_email_group(group_name, email_options, pem_conn=None):
    """

    :param group_name: contains name of group
    :param email_options: contains email group options
    :param pem_conn: PEM Connection object
    """
    status = True
    result = None

    # Insert group name to pem.email_group table
    if (
        group_name is not None and group_name and len(
            group_name.strip().strip("\n")) > 0
    ):
        # Before inserting new email group check if group already
        # exists or not.
        sql = """
        SELECT id FROM pem.email_group WHERE name = '{0}'::text
        """.format(
            group_name
        )

        status, result = pem_conn.execute_dict(sql)
        if not status:
            pem_conn.execute_void("ROLLBACK")
            return False, internal_server_error(errormsg=result)

        if len(result["rows"]) == 0:
            params = [group_name]
            # First get the group id from group name
            sql = render_template(
                "alerts/sql/email_group/insert.sql", insert_gid=True)

            status, result = pem_conn.execute_dict(sql, params)
            if not status:
                pem_conn.execute_void("ROLLBACK")
                return False, internal_server_error(errormsg=result)
        else:
            pem_conn.execute_void("ROLLBACK")
            return False, internal_server_error(
                gettext("Error: Email group name exists.\n")
            )

        group_id = result["rows"][0]["id"]
        # Insert email group options assosiated with email group name
        for row in email_options:
            status, result = insert_email_group_options(row, group_id)
            if not status:
                pem_conn.execute_void("ROLLBACK")
                return False, internal_server_error(errormsg=result)

    return status, result


@login_required
@pem_connection
def insert_email_group_options(email_data, gid, pem_conn=None):
    """

    :param email_data: contains email group options data
    :param gid: contains email group id
    :param pem_conn: PEM Connection object
    """
    data = dict()
    status = True
    result = None

    if (
        "to_addr" in email_data and email_data["to_addr"] and len(
            email_data["to_addr"].strip().strip("\n")) > 0
    ):
        data["grp_to"] = email_data["to_addr"]
    else:
        status = False
        result = gettext("Error: To addresses field cannot be empty.\n")
        return status, result

    if (
        "from_addr" in email_data and email_data["from_addr"] and len(
            email_data["from_addr"].strip().strip("\n")) > 0
    ):
        data["grp_from"] = email_data["from_addr"]
    else:
        status = False
        result = gettext("Error: From addresses field cannot be empty.\n")
        return status, result

    if "cc_addr" in email_data:
        data["grp_cc"] = email_data["cc_addr"]
    else:
        data["grp_cc"] = ""

    if "bcc_addr" in email_data:
        data["grp_bcc"] = email_data["bcc_addr"]
    else:
        data["grp_bcc"] = ""

    if "reply_to_addr" in email_data:
        data["grp_reply_to"] = email_data["reply_to_addr"]
    else:
        data["grp_reply_to"] = ""

    if "subject_prefix" in email_data:
        data["grp_subject_prefix"] = email_data["subject_prefix"]
    else:
        data["grp_subject_prefix"] = ""

    if (
        "from_time" in email_data and email_data["from_time"] and len(
            email_data["from_time"].strip().strip("\n")) > 0
    ):
        data["time_from"] = email_data["from_time"]
    else:
        status = False
        result = gettext("Error: From time field cannot be empty.\n")
        return status, result

    if (
        "to_time" in email_data and email_data["to_time"] and len(
            email_data["to_time"].strip().strip("\n")) > 0
    ):
        data["time_to"] = email_data["to_time"]
    else:
        status = False
        result = gettext("Error: To time field cannot be empty.\n")
        return status, result

    # Update pem.alert table
    if len(data) > 0:
        params = [
            gid,
            data["grp_to"],
            data["grp_cc"],
            data["grp_bcc"],
            data["grp_from"],
            data["grp_reply_to"],
            data["grp_subject_prefix"],
            data["time_from"],
            data["time_to"],
        ]
        sql = render_template(
            "alerts/sql/email_group/insert.sql", insert_gid=False)

        status, result = pem_conn.execute_void(sql, params)
        if not status:
            return False, result

    return status, result


def register_email_routes(blueprint):
    blueprint.add_url_rule("/email/list", "email_list",
                           email_list, methods=["GET"])
    blueprint.add_url_rule(
        "/email/configure", "email_config", configure, methods=["PUT", "POST"]
    )
