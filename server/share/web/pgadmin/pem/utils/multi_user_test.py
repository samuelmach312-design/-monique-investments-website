##########################################################################
#
# Postgres Enterprise Manager
#
# Copyright (C) 2016 - 2025, EnterpriseDB Corporation. All rights reserved.
#
##########################################################################


from regression.pem import grant_role, get_test_user


def multiuser_runTest(role_permission):
    def wrapper(func):
        def wrapped(self, *args, **kwargs):
            # Taking backup of postgres user credentials and chrome driver
            self.main_driver = self.page.driver
            self.main_tester = self.tester
            try:
                # Check options for pem_admin
                user = get_test_user(self, 0, True)
                self.conn = user['conn']
                self.tester = user['tester']
                self.page.driver = user['driver']
                # Wait till the pem home page is successfully loaded after
                # login
                self.page.wait_for_spinner_to_disappear()
                self.page.reset_layout()
                self.page.wait_for_spinner_to_disappear()
                self.component_accessible = True
                func(self, *args, **kwargs)

                # Check options for pem_user with no privileges
                user = get_test_user(self, 0, False)
                self.conn = user['conn']
                self.tester = user['tester']
                self.page.driver = user['driver']
                # Wait till the pem home page is successfully loaded after
                # login
                self.page.wait_for_spinner_to_disappear()
                self.page.reset_layout()
                self.page.wait_for_spinner_to_disappear()
                self.component_accessible = False
                func(self, *args, **kwargs)

                # Check options for pem_user with privilege
                user = get_test_user(self, 1, False)
                grant_role(user['username'], role_permission)
                self.conn = user['conn']
                self.tester = user['tester']
                self.page.driver = user['driver']
                # Wait till the pem home page is successfully loaded after
                # login
                self.page.wait_for_spinner_to_disappear()
                self.page.reset_layout()
                self.page.wait_for_spinner_to_disappear()
                self.component_accessible = True
                func(self, *args, **kwargs)
            finally:
                # Restore the original user and driver
                self.tester = self.main_tester
                self.page.driver = self.main_driver
        return wrapped
    return wrapper
