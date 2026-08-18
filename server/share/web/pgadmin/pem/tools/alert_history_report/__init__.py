##########################################################################
#
# Postgres Enterprise Manager
#
# Copyright (C) 2016 - 2025, EnterpriseDB Corporation. All rights reserved.
#
##########################################################################
"""Implements Alert History Report"""

import json
import random
import time
import logging
from collections import OrderedDict
from flask import Response, render_template, request, current_app, session
from flask_babel import gettext
from flask_security import login_required
from pgadmin.pem.utils import pem_connection
from pgadmin.utils import PgAdminModule
from pgadmin.utils.ajax import make_json_response, bad_request, \
    internal_server_error, make_response, precondition_required, success_return
from pgadmin.pem.monitor.alerts.utils import fetch_agents, fetch_servers
from werkzeug.exceptions import BadRequest
from pgadmin.utils.csrf import pgCSRFProtect

MODULE_NAME = 'alert_history_report'


class AlertHistoryReportModule(PgAdminModule):
    """
    class AlertHistoryReportModule(Object):

        AlertHistoryReportModule inherits PgAdminModule
        class and define methods to load its own
        javascript file.
    """
    LABEL = gettext('Alert History Report')

    def register_preferences(self):
        """
            This function will setup preference for Alert History Report

            :return None
        """
        pass

    def get_exposed_url_endpoints(self):
        """
        Returns:
            list: a list of url endpoints exposed to the client.
        """
        return [
            'alert_history_report.server_agent_list',
            'alert_history_report.generate_report',
            'alert_history_report.download',
            'alert_history_report.poll'
        ]


# Create blueprint for AlertHistoryReportModule class
blueprint = AlertHistoryReportModule(
    MODULE_NAME,
    __name__,
    static_url_path='',
    url_prefix='/pem/alert_history_report'
)


@blueprint.route("/")
@login_required
def index():
    return bad_request(errormsg=gettext(
        "This URL cannot be called directly!")
    )


@blueprint.route('/server_agent_list', methods=["GET"],
                 endpoint='server_agent_list')
@login_required
@pem_connection
def server_agent_list(pem_conn=None):
    """
    This function will return the list of servers and agents group wise"""
    res = {}
    res.update(fetch_servers())
    agents = fetch_agents(pem_conn)
    for key in agents.keys():
        if key in res:
            res[key].extend(agents[key])
        else:
            res[key] = agents[key]
    return make_json_response(data=res)


@blueprint.route('/generate_report', methods=["POST"],
                 endpoint='generate_report')
@login_required
@pem_connection
def generate_report(pem_conn=None):
    """ This Function will prepare the report for Alert History"""
    try:
        if request.data:
            params = json.loads(request.data.decode())
        else:
            params = request.args or request.form
    except BadRequest as e:
        return bad_request(e.description)

    if 'alert_history_report' not in session:
        alert_history_report = session['alert_history_report'] = dict()
    else:
        alert_history_report = session['alert_history_report']

    trans_id = str(random.randint(1, 9999999))
    alert_history_report[trans_id] = params
    return make_json_response(
        data={
            'trans_id': trans_id
        }
    )


@blueprint.route('/<int:trans_id>/download', methods=["GET"],
                 endpoint='download')
@login_required
@pgCSRFProtect.exempt
@pem_connection
def download(trans_id, pem_conn=None):
    """
        Route to download Alert History Report in JSON format
        :param pem_conn:
        :return:
        """
    report_data = OrderedDict()
    if 'alert_history_report' not in session \
            or str(trans_id) not in session['alert_history_report']:
        return make_response(
            status=404,
            response=gettext('Transaction id not found')
        )
    data = session['alert_history_report'][str(trans_id)]
    if 'final_result' not in data:
        return make_response(
            status=404,
            response=gettext('Final result not found')
        )

    # Get the start and end time details
    start_time, end_time = get_start_end_time(pem_conn, data['timeframe'])

    report_data['summary'] = {
        'total_alerts': len(data['final_result']),
        'alert_types': data['alert_types'],
        'is_overall_system_report': data['overall_report'],
        'servers': data['servers'],
        'agents': data['agents'],
        'start_time': start_time,
        'end_time': end_time
    }

    report_data['alerts'] = data['final_result']
    file_extn = 'json'
    file_name = 'Alert_History_Report_{0}.{1}'.format(
        time.strftime("%Y-%m-%d_%H-%M-%S"), file_extn
    )
    resp = Response(
        json.dumps(report_data),
        mimetype='application/json'
    )
    resp.headers['Content-Disposition'] = \
        'attachment; filename={0}'.format(file_name)
    return resp


@blueprint.route('/<int:trans_id>/poll', methods=["GET"], endpoint='poll')
@login_required
@pem_connection
def poll(trans_id, pem_conn=None):
    """
        Poll callback for report generation.
        :param trans_id: transaction id where data has been stored
        :param pem_conn: pem database connection cursor
        :return: returns the flag 'busy', 'completed', 'failed' according to
        the result of the query.
        """
    try:
        if 'alert_history_report' not in session \
                or str(trans_id) not in session['alert_history_report']:
            return make_response(
                status=404,
                response=gettext('Transaction id not found')
            )

        data = session['alert_history_report'][str(trans_id)]
        data['alert_types'] = [x.upper() for x in data['alert_types']]

        # Validate the input parameters
        return_val = verify_save_data(data)
        if return_val.status_code != 200:
            return precondition_required(gettext(return_val.json['errormsg']))

        if 'query_in_progress' not in data:
            server_ids = []
            agent_ids = []

            # Condition if overall system alerts history need to be generated
            if data['overall_report']:
                status, res = pem_conn.execute_dict(
                    'SELECT id FROM pem.server where active=true')
                if not status:
                    return False, internal_server_error(
                        errormsg=gettext("Not able to fetch the Servers"))
                else:
                    server_ids += [items['id'] for items in res['rows']]

                status, res = pem_conn.execute_dict(
                    'SELECT id FROM pem.agent where active=true')
                if not status:
                    return False, internal_server_error(
                        errormsg=gettext("Not able to fetch the Agents"))
                else:
                    agent_ids += [items['id'] for items in res['rows']]
            else:
                server_ids = data['servers']
                agent_ids = data['agents']

            alert_types = data['alert_types']
            alert_types_len = len(alert_types)
            if 'CLEARED' in alert_types:
                is_clear_included = True
            else:
                is_clear_included = False
            if alert_types_len > 1:
                alert_types.remove('CLEARED') if 'CLEARED' in alert_types \
                    else None
                if len(alert_types) == 1:
                    alert_types = str(alert_types[0].upper())
                    alert_types_len = 1
                else:
                    alert_types.remove(
                        'CLEARED') if 'CLEARED' in alert_types else None
                    alert_types = tuple([item.upper() for item in alert_types])
            else:
                alert_types = str(alert_types[0].upper())

            timeframe = data['timeframe']

            data['server_names'] = get_server_names(pem_conn, server_ids)
            data['agent_names'] = get_agent_names(pem_conn, agent_ids)

            sql = render_template(
                'alert_history_report/sql/report_data.sql',
                server_ids=server_ids,
                agent_ids=agent_ids,
                alert_types_len=alert_types_len,
                is_clear_included=is_clear_included,
                alert_types=alert_types,
                timeframe=timeframe,
                overall_report=data['overall_report']
            )
            data['query_in_progress'] = True
            status, res = pem_conn.execute_dict(sql)
            data['query_in_progress'] = False
            data['final_result'] = res['rows']
            if not status:
                logging.exception(str(res), exc_info=True)
                return make_json_response(data={"status": "busy"})
            return make_json_response(data={"status": "completed"})
        elif 'query_in_progress' in data and \
                data['query_in_progress'] is False:
            return make_json_response(data={"status": "completed"})
        else:
            return make_json_response(data={"status": "busy"})
    except Exception as e:
        logging.exception(str(e), exc_info=True)
        current_app.logger.error(
            "Error Encountered in ALertHistoryReport : {}".format(str(e))
        )
        return internal_server_error("{}".format(e))


def get_server_names(pem_conn, server_ids):
    # Fetch the names of the servers based on the IDs
    server_names = []
    for server_id in server_ids:
        query = "SELECT description FROM pem.server WHERE id = %s;"
        status, result = pem_conn.execute_dict(query, (server_id,))
        if status:
            server_name = result['rows'][0]['description']
            server_names.append(server_name)
    return server_names


def get_agent_names(pem_conn, agent_ids):
    # Fetch the names of the agents based on the IDs
    agent_names = []
    for agent_id in agent_ids:
        query = "SELECT description FROM pem.agent WHERE id = %s;"
        status, result = pem_conn.execute_dict(query, (agent_id,))
        if status:
            agent_name = result['rows'][0]['description']
            agent_names.append(agent_name)
    return agent_names


def get_start_end_time(pem_conn, timeframe):
    """ This  will return the start/eend time according to the timeframe"""
    start_time = ''
    end_time = ''
    status, res = \
        pem_conn.execute_dict(
            "SELECT now() - INTERVAL '{}' AS start_time, "
            "now() AS end_time;".format(timeframe))
    if not status:
        pass
    else:
        start_time = res['rows'][0]['start_time']
        end_time = res['rows'][0]['end_time']
    return start_time, end_time


def verify_save_data(data):
    """verify the save request data"""
    if type(data['agents']) is not list or type(data['servers']) is not list:
        return precondition_required(gettext(
            "Please provide the data in correct format"
        ))
    for item in data['agents']:
        if not isinstance(item, int):
            return precondition_required(gettext(
                "Agent id's should be integer"
            ))
    for item in data['servers']:
        if not isinstance(item, int):
            return precondition_required(gettext(
                "Server id's should be integer"
            ))
    expected_alert_types = ['LOW', 'MEDIUM', 'HIGH', 'CLEARED']
    for alert in data['alert_types']:
        if alert not in expected_alert_types:
            return precondition_required(gettext(
                "Please provide the correct alert types"
            ))

    expected_timeframes = ['12h', '1d', '7d', '15d', '30d']
    if data['timeframe'] not in expected_timeframes:
        return precondition_required(gettext(
            "Please provide the correct timeframes"
        ))
    if type(data['overall_report']) is not bool:
        return precondition_required(gettext(
            "overall_report should be of boolean type"
        ))
    return success_return()
