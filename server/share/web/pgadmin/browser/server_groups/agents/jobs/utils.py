##########################################################################
#
# Postgres Enterprise Manager
#
# Copyright (C) 2016 - 2025, EnterpriseDB Corporation. All rights reserved.
#
##########################################################################

"""Implements the pemAgent Jobs utility to create jobs"""
from flask import current_app, render_template
from flask_security import current_user
from .schedules.utils import format_schedule_data
from pgadmin.utils.ajax import make_json_response
import pytz


def create_job(pem_conn, agid, data, scheduled_time=None):
    # Setting default values
    if "jobenabled" not in data:
        data["jobenabled"] = True
    if "jobdesc" not in data:
        data["jobdesc"] = ""
    if "jsteps" not in data:
        data["jsteps"] = []
    if "jschedules" not in data:
        data["jschedules"] = []
    if "notify" not in data:
        data["notify"] = "DEFAULT"

    status, res = pem_conn.execute_void('BEGIN')

    if not status:
        return None, res

    if 'jschedules' in data and len(data['jschedules']) > 0:
        format_schedule_data(data['jschedules'])

    status, res = pem_conn.execute_scalar(
        render_template(
            'pem_jobs/sql/create.sql',
            data=data, conn=pem_conn, fetch_id=True, aid=agid,
            schema_version=current_user.schema_version
        )
    )

    if not status:
        pem_conn.execute_void('END')
        return None, res

    # We need properties of newly created job
    status, res = pem_conn.execute_dict(
        render_template(
            'pem_jobs/sql/nodes.sql',
            jid=res, conn=pem_conn, aid=agid
        )
    )

    if not status:
        pem_conn.execute_void('END')
        return None, res

    job = res['rows'][0]

    if scheduled_time is not None:
        status, res = pem_conn.execute_void(
            render_template(
                'pem_jobs/sql/run_at_time.sql',
                jid=job['jobid'],
                conn=pem_conn, aid=agid,
                scheduled_time=scheduled_time
            )
        )

        if not status:
            pem_conn.execute_void('END')
            return None, res

    pem_conn.execute_void('END')

    return job, None


def create_purge_job(pem_conn, sid=None, agid=None, toolid=None):

    if sid is None and agid is None and toolid is None:
        return None

    data = {
        "jobname": "purge_deleted_object",
        "jobdesc": "Deletes all the pemhistory/pemdata"
                   " probes data for the object.",
    }
    # fetching the retention value
    sql = """SELECT now() + (COALESCE((
    SELECT value FROM pem.config WHERE param=
    'deleted_objects_data_retention_time'), '3') || ' days')::interval;"""
    status, jobschedule_time = pem_conn.execute_scalar(sql,)

    if status is not True:
        current_app.logger.warning(
            'Failed to decide the next schedule for the purge \
                job due to the following error:\n' + jobschedule_time
        )
        return None

    purge_obj_params = ""

    if sid is not None:
        data["jobname"] = data["jobname"] + f"_server_{sid}"
        purge_obj_params = purge_obj_params + f"serverid := {sid}"

    if agid is not None:
        data["jobname"] = data["jobname"] + f"_agent_{agid}"
        purge_obj_params = \
            (purge_obj_params + ", "
             if len(purge_obj_params) > 0
             else purge_obj_params) + f"agentid := {agid}"

    if toolid is not None:
        data["jobname"] = data["jobname"] + f"_tool_{toolid}"
        purge_obj_params = \
            (purge_obj_params + ", "
             if len(purge_obj_params) > 0
             else purge_obj_params) + f"toolid := {toolid}"

    # Assumptions: 'id' for both pemAgent & pemServer is 1.
    data["jsteps"] = [{
        "jstname": "purge_probes_data",
        "jstdesc": "",
        "jstenabled": True,
        "jstkind": True,
        "jstcode":
            f"SELECT pem.purge_deleted_objects_data({purge_obj_params});",
        "server_id": 1,
        "database_name": "pem",
        "jstonerror": "f"
    }]

    row, err = create_job(pem_conn, 1, data, jobschedule_time)

    if err is not None:
        current_app.logger.warning(
            "Error creating purge job with error: " + err
        )

    return row


def jschedule_format(self, jschedules):
    for data in jschedules:
        if 'jscweekdays' in data:
            weekdays = ['Sunday', 'Monday', 'Tuesday', 'Wednesday',
                        'Thursday', 'Friday', 'Saturday']
            data['jscweekdays'] = [day in data['jscweekdays']
                                   for day in weekdays]

        if 'jscmonths' in data:
            months = ['January', 'February', 'March', 'April',
                      'May', 'June', 'July', 'August', 'September',
                      'October', 'November', 'December']
            data['jscmonths'] = [day in data['jscmonths']
                                 for day in months]

        if 'jscmonthdays' in data:
            monthdays = list(range(1, 33))  # List of all month days
            data['jscmonthdays'] = [day in data['jscmonthdays']
                                    for day in monthdays]

        if 'jschours' in data:
            hour_range = list(range(24))  # List of all hours in a day
            data['jschours'] = [hour in data['jschours']
                                for hour in hour_range]

        if 'jscminutes' in data:
            # List of all minutes in an hour
            minute_range = list(range(60))
            data['jscminutes'] = [minute in data['jscminutes']
                                  for minute in minute_range]

        if "jsctimezone" in data:
            is_valid, response = validate_timezone(self,
                                                   data['jsctimezone'])
            if not is_valid:
                return False, make_json_response(response)

    return True, jschedules


def validate_timezone(self, timezone):
    try:
        pytz.timezone(timezone)
        return True, None
    except pytz.exceptions.UnknownTimeZoneError:
        return False, "Invalid time zone"
