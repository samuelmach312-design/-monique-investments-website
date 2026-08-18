"""API for Agent Jobs"""

import json
from functools import wraps
from flask_babel import gettext as _
from flask import render_template, request
from flask_security import current_user
from pgadmin.utils.ajax import make_response, precondition_required, \
    make_json_response, internal_server_error
from pgadmin.pem.api.utils import ApiView
from pgadmin.pem.utils import is_agent_exists
from pgadmin.browser.server_groups.agents.jobs.utils import jschedule_format
from pgadmin.pem.utils.data_type import validate_empty_string, \
    validate_integer


def check_precondition(f):
    """
    This function will behave as a decorator that checks
    the database connection before running the view. It also attaches
    manager, conn, and template_path properties to self.
    """
    @wraps(f)
    def wrap(obj, *args, **kwargs):
        """
        Responsible for creating the PEM connection object and template path.
        """

        obj.conn = kwargs['pem_conn']

        if not obj.conn.connected():
            obj.conn.connect()

        # If the database is not connected, return an error to the browser
        if not obj.conn.connected():
            return precondition_required(
                _("Connection to the PEM server has been lost!")
            )

        # We do not need to pass pem_conn to the wrapped functions
        del kwargs['pem_conn']

        # Set the template path for SQL scripts
        obj.template_path = 'agents/sql'

        return f(obj, *args, **kwargs)
    return wrap


class AgentJobApiView(ApiView):
    """
    API to schedule PEM Jobs.
    """

    endpoint = 'agent_job'
    url = '/agent/job/<int:agent_id>/'
    pk = 'job_id'
    conn = None
    template_path = None
    is_edb = 0

    # Api version from v10 till latest
    # ['v10_api']
    api_versions = list(ApiView.api_versions)[9:]
    properties = dict({
        "name": validate_empty_string(_("Name cannot be empty"))
    })

    def __init__(self, *args, **kwargs):
        super(ApiView, self).__init__(*args, **kwargs)
        self.params = self.properties

    def get(self, agent_id, job_id=None, pem_conn=None):
        """
        This function will return the list of jobs for the specified
        agent id.

        :param agent_id: Agent Id for which jobs will be fetched.
        :param job_id: Job Id for which information will be fetched.
        :param pem_conn: PEM connection object.

        Input Data:
        Valid agent id for which information to be fetched.
        """
        from pgadmin.browser.server_groups.agents.jobs import JobView

        agent_exist = is_agent_exists(pem_conn, agent_id)
        if not agent_exist:
            return make_json_response(
                status=404, success=0,
                errormsg=_("The specified agent was not found!")
            )

        gid = None
        if job_id is not None:
            response = JobView.properties(self, gid, agent_id,
                                          jid=job_id, rest_api=True)
            return response
        else:
            response = JobView.nodes(self, gid, agent_id, rest_api=True)

        return make_response(response)

    @check_precondition
    def delete(self, agent_id, job_id=None):
        """
        This function will delete the job for the specified agent id.

        :param job_id: Job Id for which information will be deleted.
        :param agent_id: Agent Id for which job will be deleted.

        Input Data:
        Valid Job id to delete the job.
        """
        from pgadmin.browser.server_groups.agents.jobs import JobView

        # First check if alert id exists or not.
        if job_id is None:
            return make_json_response(
                status=404, success=0,
                errormsg=_("Please specify the job id you wish to delete")
            )

        if agent_id is None or agent_id == 0:
            return make_json_response(
                status=404, success=0,
                errormsg=_("Please specify a valid agent id.")
            )

        # Check if the job id exists
        status, response = self.check_job_exists(job_id, agent_id)

        if not status:
            return response

        gid = None
        response = JobView.delete(self, gid, agent_id,
                                  jid=job_id, rest_api=True)
        return response

    @check_precondition
    def put(self, agent_id, job_id):
        """
        This function will update the job for the specified agent id.

        :param agent_id: Agent Id for which job will be fetched.
        :param job_id: Job Id for which information will be updated.
        """
        from pgadmin.browser.server_groups.agents.jobs import JobView

        data = request.get_json()
        if data is None:
            return make_json_response(
                status=404, success=0,
                errormsg=_(
                    "Please specify input data for which you "
                    "wish to update the job parameters."
                )
            )

        # First check if agent/job id exists or not.
        if job_id is None or agent_id is None:
            return make_json_response(
                status=404, success=0,
                errormsg=_(
                    "Please specify agent/job id for which you wish "
                    "to update the job parameters."
                )
            )
        status, response = self.check_job_exists(job_id, agent_id)
        if not status:
            return response

        gid = None
        # Format the input data
        if "jschedules" in data:
            if "added" in data["jschedules"]:
                status, response = \
                    jschedule_format(self, data['jschedules']["added"])
                if not status:
                    return response

            if "changed" in data["jschedules"]:
                status, response = \
                    jschedule_format(self, data['jschedules']["changed"])
                if not status:
                    return response

            response = JobView.update(self, gid, agent_id, job_id,
                                      jschedules=data["jschedules"],
                                      rest_api=True)
        else:
            response = JobView.update(self, gid, agent_id, job_id,
                                      rest_api=True)

        return response

    @check_precondition
    def post(self, agent_id):
        """
        This function will create a new job for the specified agent id.

        :param agent_id: Agent Id for which job will be created.
        """
        from pgadmin.browser.server_groups.agents.jobs import JobView

        data = request.get_json()
        if data is None:
            return make_json_response(
                status=404, success=0,
                errormsg=_(
                    "Please specify input data for which you wish "
                    "to create the job."
                )
            )

        # Check if the agent exists or not.
        agent_exist = is_agent_exists(self.conn, agent_id)
        if not agent_exist:
            return make_json_response(
                status=404, success=0,
                errormsg=_("The specified agent was not found!")
            )
        gid = None
        # Format the input data
        if "jschedules" in data:
            status, response = jschedule_format(self,
                                                data['jschedules'])
            if not status:
                return response
            else:
                data['jschedules'] = response

        response = JobView.create(
            self, gid, agent_id, jobdata=data, rest_api=True)
        return response

    def check_job_exists(self, job_id, agent_id):

        """Check if the job exists for the given job ID and agent ID"""

        params = {
            'job_id': job_id,
            'agent_id': agent_id
        }

        sql = render_template(
            "/".join([self.template_path, 'job_exists.sql']),
            job_id=job_id, agent_id=agent_id
        )

        try:
            # Check if the job exists or not.
            status, response = self.conn.execute_dict(sql, params)

            if not status:
                return status, internal_server_error(response)

            if int(response['rows'][0]['job_count']) == 0:
                return False, make_json_response(
                    status=404, success=0,
                    errormsg=_("The specified agent/job id does not exist.")
                )
        except Exception as e:
            return status, internal_server_error(e)
        # Return True if the job exists, False otherwise
        return status, response
