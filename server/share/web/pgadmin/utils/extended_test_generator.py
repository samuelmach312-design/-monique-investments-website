##########################################################################
#
# Postgres Enterprise Manager
#
# Copyright (C) 2016 - 2025, EnterpriseDB Corporation. All rights reserved.
#
##########################################################################
""" Module to override the BaseTestGenerator class"""


def verify_keys(self, actual_data):
    self.assertIn("result", actual_data)
    self.assertIn("success", actual_data)
    self.assertIn("data", actual_data)
    self.assertIn("info", actual_data)
    self.assertIn("errormsg", actual_data)


def verify_error_response(self, actual_data):
    self.verify_keys(actual_data)
    self.assertIsNone(actual_data["result"])
    self.assertEquals(0, actual_data["success"])
    self.assertIsNone(actual_data["data"])
    self.assertEquals("", actual_data["info"])


def skipIfProdApiTest(self):
    from regression.test_setup import config_data
    if config_data['api_production']:
        self.skipTest(
            "Mocked or dummy data API test cases are not "
            "supported to run on production server.")


# Initializing app.
def setGuiServerUrl(self, gui_server_url):
    self.gui_server_url = gui_server_url


@classmethod
def setPemConnection(self, pem_conn):
    self.pem_conn = pem_conn


def override_base_test_generator():
    from ..utils.route import BaseTestGenerator

    # Monkey patching the BaseTestGenerator class
    # to extend it with the below functions
    BaseTestGenerator.skipIfProdApiTest = skipIfProdApiTest
    BaseTestGenerator.verify_error_response = verify_error_response
    BaseTestGenerator.verify_keys = verify_keys
    BaseTestGenerator.setGuiServerUrl = setGuiServerUrl
    BaseTestGenerator.setPemConnection = setPemConnection
