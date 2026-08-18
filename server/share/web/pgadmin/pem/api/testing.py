################################################################
#
# Postgres Enterprise Manager
#  - PostgreSQL monitoring, configuration, administrator Tools
#
# Copyright (C) 2013 - 2025, EnterpriseDB Corporation
# This software is released under the PostgreSQL Licence
#
#################################################################


import json
import six
import sys
import traceback
import unittest

from abc import ABCMeta
from importlib import import_module
from werkzeug.utils import find_modules
from collections import OrderedDict

import config
from .utils import ApiVersionModule
from pgadmin.pem.utils.validator import schema_validator

if sys.version_info < (3, 3):
    from mock import patch
else:
    from unittest.mock import patch

API_VERSIONS = ApiVersionModule.api_versions


class APITestsGenerator(ABCMeta):
    """
    class APITestsGenerator(object)
        Every module will be registered automatically by its module name.

    Class-level Methods:
    ----------- -------
    * __init__(...)
      - This is used to register test modules. You don't need to
      call this function explicitly. This will be automatically executed,
      whenever we create a class and inherit from BaseAPITestCase -
      it will register it as an available module in APITestsGenerator
      By setting the __metaclass__ for BaseAPITestCase to APITestsGenerator
      it will create new instance of this APITestsGenerator per class.

    * load_generators():
      - This function will load all the modules from __init__()
      present in registry.
    """

    registry = dict()

    def __init__(self, name, bases, d):
        """This is used to register test modules"""
        # Register this type of module, based on the module name
        # Avoid registering the BaseDriver itself
        if name != 'BaseAPITestCase':
            if d['__module__'] in APITestsGenerator.registry:
                APITestsGenerator.registry[d['__module__']].append(self)
            else:
                APITestsGenerator.registry[d['__module__']] = [self]

        ABCMeta.__init__(self, name, bases, d)

    @classmethod
    def load_generators(cls, pkg_root, exclude_pkgs):
        """This function will load all the modules"""
        cls.registry = dict()

        all_modules = []

        all_modules += find_modules(pkg_root, False, True)
        skip_modules = ['test_servers_groups_childrens', 'test_shared_server',
                        'test_preferences_get', 'test_preferences_update']

        for module_name in all_modules:
            try:
                if ("tests." in str(module_name) and
                    not any(
                        str(module_name).startswith(
                            'pgadmin.' + str(exclude_pkg)
                        ) for exclude_pkg in exclude_pkgs) and
                        not module_name.startswith('pgadmin.feature_tests') and
                        module_name.split('.')[-1] not in skip_modules):
                    import_module(module_name)
            except ImportError:
                traceback.print_exc(file=sys.stderr)


@six.add_metaclass(APITestsGenerator)
class BaseAPITestCase(unittest.TestCase):
    """Base Test Class for REST API"""
    # Defining abstract method which will override by individual testcase.

    def shortDescription(self):
        return 'API Test'

    def setApp(self, app):
        """Initializing app"""
        self.app = app

    @classmethod
    def setTestClient(cls, test_client):
        """Initializing test_client"""
        cls.tester = test_client

    @classmethod
    def setPemConnection(cls, pem_conn):
        cls.pem_conn = pem_conn

    @classmethod
    def setToken(cls, token):
        """Initializing token"""
        cls.token = token

    @property
    def headers(self):
        """Get the token request header"""
        res = dict({'Content-Type': 'application/json'})
        res[
            getattr(config, 'PEM_HEADER_TOKEN_KEY', 'X-Auth-Token')
        ] = self.token
        return res

    def __init__(self, *args, **kwargs):
        """Initializing unittest test class"""
        unittest.TestCase.__init__(self, *args, **kwargs)

    def get_url(self, id=None, api_version=None):
        """Generate URL based on object id"""
        url = self.data.get('url', self.base_url)
        url = API_VERSIONS[api_version] + url

        return '{0}{1}'.format(
            url, ((str(id)) if id is not None else '')
        )

    def post(self, data, api_version=None):
        """Prepare POST request"""
        return self.tester.post(
            self.get_url(api_version=api_version), headers=self.headers,
            data=json.dumps(data) if data is not None else None
        )

    def put(self, id, data, api_version=None):
        """Prepare PUT request"""
        return self.tester.put(
            self.get_url(id, api_version=api_version), headers=self.headers,
            data=json.dumps(data) if data is not None else None
        )

    def get(self, id=None, api_version=None):
        """Prepare GET request"""
        return self.tester.get(self.get_url(
            id, api_version=api_version), headers=self.headers)

    def delete(self, id, api_version=None):
        """Prepare DELETE request"""
        return self.tester.delete(self.get_url(
            id, api_version=api_version), headers=self.headers)

    def fetch_request_response(self, api_version, method):
        """Allow us to fetch response for the request"""
        if api_version not in API_VERSIONS:
            return unittest.skip('Invalid api version {}'.format(
                api_version)
            )
        if method == 'post':
            return self.post(self.data['data'], api_version=api_version)
        elif method == 'put':
            return self.put(self.data['id'], self.data['data'],
                            api_version=api_version)
        elif method == 'delete':
            return self.delete(self.data['id'], api_version=api_version)
        elif method == 'get':
            return self.get(self.data['id'] if 'id' in self.data else None,
                            api_version=api_version)
        else:
            self.assertFalse(True, 'Not a supported method %s!' % method)

    def verify_list_data(self, api_version, resp):
        """Allow us to verify the response data if it of type List"""
        try:
            idx = 0
            expected_content = self.expected['content']
            response = json.loads(resp.data.decode('utf-8'))
            self.assertTrue(
                isinstance(response, list),
                '{} Response content ({}) is not '
                'a list: {}'.format(
                    api_version, type(response), response
                )
            )
            self.assertTrue(
                len(response) == len(expected_content),
                '{} Different length of content '
                '({}) returned: {}'.format(
                    api_version, len(response), resp.data
                )
            )
            while idx < len(expected_content):
                skip_content_check = self.expected.get(
                    'skip_content_check', []
                )
                added, removed, modified, same = dict_compare(
                    expected_content[idx], response[idx],
                    skip_content_check
                )
                self.assertTrue(
                    (added, removed, modified) == (
                        set(), set(), {}),
                    '{} Different JSON response: {}'.format(
                        api_version, (added, removed,
                                      modified, same)
                    )
                )
                idx += 1
        except Exception:
            self.app.logger.exception(
                '{} Invalid response data: {}'.format(
                    api_version, resp.data)
            )
            self.assertTrue(False)

    def verify_dict_data(self, api_version, resp):
        """Allow us to verify the response data if it of type Dict"""
        try:
            response = json.loads(resp.data.decode('utf-8'))
            self.assertTrue(
                isinstance(response, dict),
                '{} Response content ({})'
                ' is not a dict: {}'.format(
                    api_version, type(response), response
                )
            )
            skip_content_check = self.expected.get(
                'skip_content_check', []
            )
            added, removed, modified, same = dict_compare(
                self.expected['content'], response,
                skip_content_check
            )
            self.assertTrue(
                (added, removed, modified) == (set(), set(), {}),
                '{} Different JSON response:\n {} [Added],\n'
                '{} [Removed],\n {} [Modified]'.format(
                    api_version, added, removed, modified
                )
            )
        except Exception as ex:
            print(ex)
            self.assertTrue(
                False, '{} Invalid response data: {}'.format(
                    api_version, resp.data)
            )

    def verify_response(self, resp, api_version):
        """
        This function verifies the API response
        :param resp: API response object
        :param api_version: api version
        :return: None
        """
        if 'status_code' in self.expected and resp.status_code != 404:
            self.assertEqual(
                resp.status_code, self.expected['status_code'])
        if 'content' in self.expected:
            if isinstance(self.expected['content'], list):
                self.verify_list_data(api_version, resp)
            elif isinstance(self.expected['content'], dict):
                self.verify_dict_data(api_version, resp)
            else:
                self.assertEqual(
                    str(self.expected['content']), str(resp.data)
                )

        callback = self.expected.get('callback', None)
        if callback is not None:
            self.assertTrue(callable(callback))
            self.assertTrue(callback(resp, self.expected, self,
                                     api_version=api_version))

    def runTest(self):
        """Responsible for running API test cases"""
        self.data = getattr(self, 'data', {'method': 'get'})
        self.expected = getattr(self, 'expected', {'status_code': 200})
        self.api_versions = getattr(self, 'api_version', list(API_VERSIONS))

        method = self.data.get('method', 'get')

        if hasattr(self, 'function_to_be_mocked'):
            for api_version in self.api_versions:
                with patch(self.function_to_be_mocked,
                           side_effect=eval(self.side_effect)):
                    resp = self.fetch_request_response(api_version, method)
                    self.verify_response(resp, api_version)
        else:
            for api_version in self.api_versions:
                resp = self.fetch_request_response(api_version, method)
                self.verify_response(resp, api_version)


def dict_compare(d1, d2, skip_content_check=[], api_version=None):
    """Compares two dictionaries"""
    d1_keys = set(d1.keys())
    d2_keys = set(d2.keys())

    for k in skip_content_check:
        d1_keys.discard(k)
        d2_keys.discard(k)

    intersect_keys = d1_keys.intersection(d2_keys)
    added = d1_keys - d2_keys
    removed = d2_keys - d1_keys
    modified = {o: (d1[o], d2[o]) for o in intersect_keys if d1[o] != d2[o]}
    same = set(o for o in intersect_keys if d1[o] == d2[o])

    return added, removed, modified, same


def print_test_response(resp, expected, testcase):
    """Sample callback for validation"""
    print(
        '\n=================================\n'
        'STATUS CODE #{0}\nHEADERS:\n{1}\nRESPONSE:{2}'
        '\n=================================\n'.format(
            resp.status_code, resp.headers, resp.data
        )
    )
    return True


def validate_schema_list(response, expected, testcase, api_version=None):
    """Responsible for validation of schema list"""
    try:
        resp_json = json.loads(response.data.decode('utf-8'))
        testcase.assertTrue(type(resp_json), list)

        if 'schema' in expected:
            schema = expected['schema']
            for resp in resp_json:
                schema_validator(testcase, None, schema, resp)

    except ValueError as ve:
        print('{} Exception converting response data.'.format(api_version),
              file=sys.stderr)
        raise ve
    return True


def validate_schema_object(response, expected, testcase, api_version=None):
    """Responsible for validation of schema object"""
    try:
        resp = json.loads(response.data.decode('utf-8'))
        testcase.assertTrue(type(resp), dict)
        if 'schema' in expected:
            schema = expected['schema']
            schema_validator(testcase, None, schema, resp)

    except ValueError as ve:
        print('{} Exception converting response data.'.format(api_version),
              file=sys.stderr)
        raise ve
    return True


def validate_error_message(response, expected, testcase, api_version=None):
    """
    This function verifies the error messages returned by APIs
    :param response: API response object
    :param expected: expected data
    :param testcase: testcase instance
    :param api_version: api version
    :return: boolean
    """
    try:
        resp_json = json.loads(response.data.decode('utf-8'))
        testcase.assertTrue(type(resp_json), dict)
        testcase.assertEquals(resp_json["errormsg"], expected['error_message'])
    except ValueError as ve:
        print('{} Exception converting response data : {}'.format(
            api_version, ve), file=sys.stderr)
        return False
    return True
