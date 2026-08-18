##########################################################################
#
# Postgres Enterprise Manager
#
# Copyright (C) 2016 - 2025, EnterpriseDB Corporation. All rights reserved.
#
##########################################################################

"""Implements Alerts"""

import json
from flask import render_template, request
from flask_babel import gettext
from pgadmin.utils.ajax import (
    internal_server_error,
    bad_request,
    make_json_response,
    make_response,
)
from pgadmin.utils import PgAdminModule
from flask import url_for
from flask_security import login_required
from pgadmin.pem.utils import pem_connection, is_edb_server
from .copy import register_copy_routes
from .email import register_email_routes
from .email_template import register_email_template_routes
from .custom import register_custom_routes
from .blackout import register_blackout_routes
from .webhook import register_webhook_routes
from functools import wraps
from pgadmin.pem.monitor.utils import DashboardLevel
from . import utils, api
from pgadmin.pem.monitor.alerts.webhook import insert_webhook_alert_config
from pgadmin.pem.monitor.alerts.webhook import validate_update_webhook_params
from pgadmin.pem.monitor.alerts.webhook import update_webhook_alert_config

MODULE_NAME = "alerts"


class AlertsModule(PgAdminModule):
    """
    class AlertsModule(Object):

        It is a AlertModule inherits PgAdminModule
        class and define methods to load its own
        javascript file.
    """

    LABEL = gettext("Alerts")

    def get_own_stylesheets(self):
        """
        Returns:
            list: the stylesheets used by this module.
        """
        stylesheets = [url_for("alerts.static", filename="css/alerts.css")]
        return stylesheets

    def get_exposed_url_endpoints(self):
        """
        Returns:
            list: a list of url endpoints exposed to the client.
        """
        return [
            "alerts.get_alert_template",
            "alerts.template_list",
            "alerts.get_all_custom_alerts_templates",
            "alerts.object_template_list",
            "alerts.detail",
            "alerts.count",
            "alerts.info",
            "alerts.email_group_list",
            "alerts.list",
            "alerts.save",
            "alerts.object_alert_list",
            "alerts.db_alert_list",
            "alerts.schema_alert_list",
            "alerts.schema_object_alert_list",
            "alerts.copy_nodes",
            "alerts.coll_copy_nodes",
            "alerts.server_group_nodes",
            "alerts.agent_copy_nodes",
            "alerts.server_copy_nodes",
            "alerts.db_copy_nodes",
            "alerts.schema_copy_nodes",
            "alerts.table_copy_nodes",
            "alerts.copy_config",
            "alerts.custom_list_by_level",
            "alerts.alert_probe_dep_list",
            "alerts.custom_save",
            "alerts.email_list",
            "alerts.email_config",
            "alerts.save_blackouts",
            "alerts.get_blackouts",
            "alerts.delete_blackouts",
            "alerts.servers",
            "alerts.agents",
            "alerts.webhook_list",
            "alerts.webhook_config",
            "alerts.webhook_test_connection",
            "alerts.webhook_testjob_status_poll",
            "alerts.custom_export",
            "alerts.custom_import",
            "alerts.email_template_list",
            "alerts.email_template_save",
            "alerts.all_auto_created_alerts"
        ]


# Create blueprint for Manage Alerts class
blueprint = AlertsModule(
    MODULE_NAME, __name__, static_url_path="", url_prefix="/pem/alerts"
)

register_copy_routes(blueprint)
register_email_routes(blueprint)
register_email_template_routes(blueprint)
register_custom_routes(blueprint)
register_blackout_routes(blueprint)
register_webhook_routes(blueprint)


# We need list to check the valid target type when request comes
VALID_TARGET_TYPE_ID = [
    DashboardLevel.DB_GLOBAL,
    DashboardLevel.DB_AGENT,
    DashboardLevel.DB_SERVER,
    DashboardLevel.DB_DATABASE,
    DashboardLevel.DB_SCHEMA,
    DashboardLevel.DB_TABLE,
    DashboardLevel.DB_INDEX,
    DashboardLevel.DB_SEQUENCE,
    DashboardLevel.DB_FUNCTION,
]


def request_validator(f):
    """
    This function will validates requests and it's parameters if necessary
    """

    @wraps(f)
    def wrapped(*args, **kwargs):
        valid_request_parameters = True
        msg = ""
        # Check if we have valid target_type_id
        if "target_type_id" in kwargs:
            if kwargs["target_type_id"] not in VALID_TARGET_TYPE_ID:
                valid_request_parameters = False
                msg = "Invalid target type id provided"

        # Check if we have valid object_id
        if valid_request_parameters and "object_id" in kwargs:
            if not kwargs["object_id"] > 0:
                valid_request_parameters = False
                msg = "Invalid object id provided"

        # Check if we have valid alert_id
        if valid_request_parameters and "alert_id" in kwargs:
            if not kwargs["alert_id"] > 0:
                valid_request_parameters = False
                msg = "Invalid alert id provided"

        # Check if we have valid alert_template_id
        if valid_request_parameters and "alert_template_id" in kwargs:
            if not kwargs["alert_template_id"] > 0:
                valid_request_parameters = False
                msg = "Invalid alert template id provided"

        # If validation fails return from here
        if not valid_request_parameters:
            return bad_request(gettext(msg))

        return f(*args, **kwargs)

    return wrapped


@blueprint.route("/")
@login_required
def index():
    return bad_request(errormsg=gettext("This URL cannot be called directly!"))


@blueprint.route("/count", methods=["GET"], endpoint="count")
@pem_connection
@login_required
@utils.configAlertRole.check_role(
    gettext("Logged-in user do not have permission to access alert count.")
)
def alert_count(pem_conn=None):
    """
    This function returns the alert count corresponding to target type.

    Args:
        pem_conn: pem connection object
    """

    sql = render_template("alerts/sql/alerts/count.sql")

    # Get the alert count.
    status, alerts = pem_conn.execute_dict(sql)

    if not status:
        return internal_server_error(errormsg=alerts)

    return make_json_response(
        data={"status": status, "alerts": alerts["rows"]})


@blueprint.route("/list/<int:target_type_id>/",
                 methods=["GET"], endpoint="list")
@blueprint.route(
    "/list/<int:target_type_id>/<int:object_id>",
    methods=["GET"],
    endpoint="object_alert_list",
)
@blueprint.route(
    "/list/<int:target_type_id>/<int:object_id>/<database_name>",
    methods=["GET"],
    endpoint="db_alert_list",
)
@blueprint.route(
    "/list/<int:target_type_id>/<int:object_id>/<database_name>/<schema_name>",
    methods=["GET"],
    endpoint="schema_alert_list",
)
@blueprint.route(
    "/list/<int:target_type_id>/<int:object_id>/<database_name>/"
    "<schema_name>/<object_name>",
    methods=["GET"],
    endpoint="schema_object_alert_list",
)
@login_required
@utils.configAlertRole.check_role(
    gettext("Logged-in user do not have permission to access alert list.")
)
@request_validator
@pem_connection
def get_alert_list(
    target_type_id,
    object_id=None,
    database_name=None,
    schema_name=None,
    object_name=None,
    pem_conn=None,
):
    """
    This function will return the list of alerts.

    Args:
        target_type_id: target type id.
        object_id: Agent/Server id.
        database_name: database name.
        schema_name: schema name.
        object_name: Table/Index/Function/Sequence name.
        pem_conn: pem connection object
    """

    status, alerts = utils.get_alerts(
        target_type_id, object_id, database_name,
        schema_name, object_name, pem_conn
    )

    if not status:
        return internal_server_error(errormsg=alerts)

    # Format parameter options abd values
    for row in alerts["rows"]:
        param_options = []
        if row["agent_desc"]:
            param_options.append(
                {"paramname": "agent", "paramvalue": row["agent_desc"]}
            )
        if row["server_desc"]:
            param_options.append(
                {"paramname": "server", "paramvalue": row["server_desc"]}
            )
        if row["database_name"]:
            param_options.append(
                {"paramname": "database_name",
                 "paramvalue": row["database_name"]}
            )
        if row["schema_name"]:
            param_options.append(
                {"paramname": "schema_name", "paramvalue": row["schema_name"]}
            )
        if row["package_name"]:
            param_options.append(
                {"paramname": "package_name",
                 "paramvalue": row["package_name"]}
            )
        if row["object_name"]:
            param_options.append(
                {"paramname": "object_name", "paramvalue": row["object_name"]}
            )
        if "params" in row and row["params"] is not None and \
                len(row["params"]):
            for i in range(len(row['param_names'])):
                if row['params_units'] is not None and \
                        i < len(row['params_units']):
                    # handles empty value in unit
                    if row['params_units'][i]:
                        param_options.append(
                            {"paramname":
                                f"{row['param_names'][i]}("
                                f"{row['params_units'][i]})",
                             "paramvalue": row["params"][i]})
                    else:
                        param_options.append(
                            {"paramname": row["param_names"][i],
                             "paramvalue": row["params"][i]})
                else:
                    param_options.append(
                        {"paramname": row["param_names"][i],
                         "paramvalue": row["params"][i]})

        row["params"] = param_options

    return make_response(response={"alerts": alerts["rows"]}, status=200)


@blueprint.route("/detail/<int:alert_id>", methods=["GET"], endpoint="detail")
@login_required
@request_validator
@pem_connection
def get_alert_details(alert_id=None, pem_conn=None):
    """
    This function will return the details of alert
    based on given alert id.

    Args:
        alert_id: alert id.
        pem_conn: pem connection object
    """
    params = [alert_id]
    sql = render_template("alerts/sql/alerts/alert_details.sql")

    # Execute the query.
    status, alerts = pem_conn.execute_dict(sql, params)

    if not status:
        return internal_server_error(errormsg=alerts)

    # To display the parameters and options value - Need to format the data
    # received from database pem.alert table
    alert_details = alerts["rows"][0] if len(alerts["rows"]) > 0 else None
    if alert_details:
        if alert_details["profile_id"]:
            return internal_server_error(
                errormsg=gettext(
                    "Operation restricted - Alert managed by profile"
                )
            )
        param_options = []
        if alert_details["agent_desc"]:
            param_options.append(
                {"paramname": "agent",
                 "paramvalue": alert_details["agent_desc"]}
            )
        if alert_details["server_desc"]:
            param_options.append(
                {"paramname": "server",
                 "paramvalue": alert_details["server_desc"]}
            )
        if alert_details["database_name"]:
            param_options.append(
                {
                    "paramname": "database_name",
                    "paramvalue": alert_details["database_name"],
                }
            )
        if alert_details["schema_name"]:
            param_options.append(
                {"paramname": "schema_name",
                 "paramvalue": alert_details["schema_name"]}
            )
        if alert_details["package_name"]:
            param_options.append(
                {
                    "paramname": "package_name",
                    "paramvalue": alert_details["package_name"],
                }
            )
        if alert_details["object_name"]:
            param_options.append(
                {"paramname": "object_name",
                 "paramvalue": alert_details["object_name"]}
            )
        if (
            "params" in alert_details and alert_details["params"]
            is not None and len(alert_details["params"])
        ):
            if len(alert_details['param_names']) == len(
                    alert_details["params_units"]):
                [param_options.append(
                    {"paramname": f"{name}({unit})", "paramvalue": value})
                    for name, value, unit in
                    zip(alert_details["param_names"], alert_details["params"],
                        alert_details["params_units"])]
            else:
                [param_options.append(
                    {"paramname": name, "paramvalue": value})
                    for name, value in zip(
                    alert_details["param_names"], alert_details["params"])]
        alert_details["params"] = param_options

    return make_response(
        response=alert_details if alert_details else {}, status=200)


@blueprint.route(
    "/template_list/<int:target_type_id>", methods=["GET"],
    endpoint="template_list"
)
@blueprint.route(
    "/template_list/<int:target_type_id>/<int:object_id>",
    methods=["GET"],
    endpoint="object_template_list",
)
@blueprint.route(
    "/template_list/<int:target_type_id>/<int:object_id>/"
    "<int:alert_template_id>",
    methods=["GET"],
    endpoint="get_alert_template",
)
@login_required
@request_validator
@pem_connection
def get_alert_template_list(
    target_type_id, object_id=None, alert_template_id=None, pem_conn=None
):
    """
    This function will return the list of alert templates.

    Args:
        target_type_id: target type id.
        object_id: Agent/Server id.
        alert_template_id: Alert template id
        pem_conn: pem connection object
    """

    is_edb = 0

    # If target type id is Global level then object id should be zero.
    if target_type_id == DashboardLevel.DB_GLOBAL:
        object_id = 0

    if object_id is None:
        object_id = 0

    if target_type_id > DashboardLevel.DB_AGENT:
        # Check server type is ppas or not
        is_edb = int(is_edb_server(pem_conn, object_id))

    params = {"target_id": target_type_id}

    if target_type_id != DashboardLevel.DB_AGENT and \
            object_id > 0 and is_edb == 0:
        comparision_condition = """
            (at.object_type = %(target_id)s::int)
            AND at.applicable_on_server IN ('ALL' , 'POSTGRES_SERVER')
            """
    elif target_type_id != DashboardLevel.DB_AGENT and \
            object_id > 0 and is_edb == 1:
        comparision_condition = """
            (at.object_type = %(target_id)s::int)
            AND at.applicable_on_server IN ('ALL' , 'ADVANCED_SERVER')
            """
    else:
        comparision_condition = "(at.object_type = %(target_id)s::int)"

    sql = render_template(
        "alerts/sql/alerts/template_list.sql",
        comparision_condition=comparision_condition,
        alert_template_id=alert_template_id,
    )

    # Get alert template list
    status, alerts = pem_conn.execute_dict(sql, params)

    if not status:
        return internal_server_error(errormsg=alerts)

    res = []
    for row in alerts["rows"]:
        res.append({"label": row["display_name"], "value": str(row["id"])})

    return make_json_response(
        data={"status": status, "alerts": alerts["rows"], "template_list": res}
    )


@blueprint.route("/email_group_list", methods=["GET"],
                 endpoint="email_group_list")
@login_required
@pem_connection
def email_group_list(pem_conn=None):
    """
    This function will return the list of email group.

    Args:
        pem_conn: pem connection object

    """

    status, version = pem_conn.execute_scalar("SELECT pem.schema_version()")

    if not status:
        return internal_server_error(errormsg=version)

    sql = render_template(
        "alerts/sql/alerts/email_group_list.sql", version=version)

    # Get email group list for alert
    status, group_data = pem_conn.execute_dict(sql)

    if not status:
        return internal_server_error(errormsg=group_data)

    result = []
    for row in group_data["rows"]:
        result.append({"label": row["group_name"],
                       "value": str(row["group_id"])})

    return make_json_response(
        data={"status": status, "data": group_data["rows"],
              "email_list": result}
    )


@blueprint.route("/save", methods=["PUT", "POST"], endpoint="save")
@login_required
@utils.configAlertRole.check_role(
    gettext(
        "Logged-in user do not have permission to save alert configurations.")
)
@pem_connection
def save_alert_config(pem_conn=None):
    """
    This function is used to store the alert configuration
    depending on target type.

    Args:
        pem_conn: pem connection object
    """
    if request.data:
        change_alert_data = json.loads(request.data.decode())
    else:
        change_alert_data = request.args or request.form

    node_info = change_alert_data[0]
    alert_data = change_alert_data[1]

    status = True
    result = None
    pem_conn.execute_void("BEGIN")

    # Update alert configuration parameters
    if "changed" in alert_data:
        for row in alert_data["changed"]:
            status, result = utils.update_alert(row, pem_conn)
            if not status:
                pem_conn.execute_void("ROLLBACK")
                return internal_server_error(errormsg=result)
            wh_status, wh_result = \
                validate_update_webhook_params(row, pem_conn)
            if not wh_status:
                pem_conn.execute_void("ROLLBACK")
                return internal_server_error(errormsg=wh_result)
            wh_status, wh_result = update_webhook_alert_config(row, pem_conn)
            if not wh_status:
                pem_conn.execute_void("ROLLBACK")
                return internal_server_error(errormsg=wh_result)

    # Delete any existing alert from alert id
    if "deleted" in alert_data:
        alert_ids = []
        for row in alert_data["deleted"]:
            if "id" in row:
                alert_ids.append(row["id"])

        sql = render_template("alerts/sql/alerts/delete.sql")

        if len(alert_ids) > 0:
            status, result = (
                pem_conn.execute_void(sql, {'alert_ids': alert_ids}))
            if not status:
                pem_conn.execute_void("ROLLBACK")
                return internal_server_error(errormsg=result)

    # Add new alert to pem.alert template
    if "added" in alert_data:
        for row in alert_data["added"]:
            status, result = utils.insert_alert(row, node_info, pem_conn)
            if not status:
                pem_conn.execute_void("ROLLBACK")
                return internal_server_error(errormsg=result)

            if result and "override_default_config" in alert_data["added"][0]:
                if alert_data["added"][0]["override_default_config"]:
                    wh_status, wh_result = insert_webhook_alert_config(
                        result, row, pem_conn
                    )
                    if not wh_status:
                        pem_conn.execute_void("ROLLBACK")
                        return internal_server_error(errormsg=wh_result)
                    result = None

            if result and "send_notification" in alert_data["added"][0]:
                if not alert_data["added"][0]["send_notification"]:
                    wh_status, wh_result = insert_webhook_alert_config(
                        result, row, pem_conn
                    )
                    if not wh_status:
                        pem_conn.execute_void("ROLLBACK")
                        return internal_server_error(errormsg=wh_result)
                    result = None
    pem_conn.execute_void("COMMIT")

    return make_json_response(data={"status": status, "result": result})


@blueprint.route("/info/<int:alert_id>", methods=["GET"], endpoint="info")
@login_required
@request_validator
@pem_connection
def get_alert_info(alert_id, pem_conn=None):
    """
    This function is used to fetch details of alert
    :param alert_id: the alert of which details needs to fetch.
    :param pem_conn: Connection object
    :return: Alert details
    """
    sql = render_template("alerts/sql/alerts/alert_details_for_dashboard.sql")
    status, res = pem_conn.execute_dict(sql, {"alert_id": alert_id})
    if not status:
        return internal_server_error(errormsg=res)

    alert_data = {}
    alert_data["detail_info"] = {}
    alert_data["params"] = {}
    if res and "rows" in res:
        rows = res["rows"][0]

        # Prepare data in proper format before sending to client
        new_list = []
        for idx, val in enumerate(rows["param_values"]):
            new_list.append([rows["param_names"][idx], val])

        alert_data["detail_info"]["cols"] = rows["detail_info_cols"]
        alert_data["detail_info"]["rows"] = rows["detail_info_rows"]
        alert_data["params"]["cols"] = ["Name", "Value"]
        alert_data["params"]["rows"] = new_list

    return make_json_response(status=200, success=1, data=alert_data)
