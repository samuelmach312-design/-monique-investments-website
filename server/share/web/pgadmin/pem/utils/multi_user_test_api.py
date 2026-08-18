##########################################################################
#
# Postgres Enterprise Manager
#
# Copyright (C) 2016 - 2025, EnterpriseDB Corporation. All rights reserved.
#
##########################################################################


from functools import wraps
from regression.pem.multi_user_test_utils import grant_role, \
    revoke_role
from regression.pem import get_test_user


def multi_user_test_api(test_roles=[]):
    """
    This function is used as wrapper to runTest functions of test cases
    to run the function multiple times with different user role
    :param : test_roles
    :type : list
    :return: multi user wrapper function
    """
    def multi_user_decorator(func):
        @wraps(func)
        def wrapper(self, *args, **kwargs):

            roles_granted = []
            self.main_tester = self.tester
            self.main_pem_conn = self.pem_conn
            test_user = None

            try:
                # skipping the multiuser test cases due to the csrf issue
                self.skipTest(
                    "skipping the multiuser test case due to the csrf "
                    "issue for scenario {0}".format(self.scenario_name))
                # Login with pem_admin
                test_admin = get_test_user(
                    self, 0, is_admin=True, is_gui=False)
                self.setTestClient(test_admin['tester'])
                self.setPemConnection(test_admin['conn'])

                # Run as 'pem_admin' user
                func(self, *args, **kwargs)

                # Connect to pem_user
                test_user = get_test_user(
                    self, 0, is_admin=False, is_gui=False)
                self.setTestClient(test_user['tester'])
                self.setPemConnection(test_user['conn'])

                # Run for roles
                for role in test_roles:
                    if role not in ('pem_admin', 'pem_user'):
                        if grant_role(test_user['username'], role) is True:
                            roles_granted.append(role)

                    print(
                        "\nGranting the role {0} to the pem_user"
                        " '{1}'".format(role, test_user['username']), end=''
                    )

                    func(self, *args, **kwargs)

            finally:
                for role in roles_granted:
                    try:
                        revoke_role(test_user['username'], role)
                    except Exception:
                        pass

                # Restore the original user and driver
                self.tester = self.main_tester
                self.setPemConnection(self.main_pem_conn)

        return wrapper

    return multi_user_decorator
