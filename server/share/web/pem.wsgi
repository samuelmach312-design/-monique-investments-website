#!/usr/bin/env python
##########################################################################
#
# Postgres Enterprise Manager
#
# Copyright (C) 2015 - 2025, EnterpriseDB Corporation. All rights reserved.
#
# pem.wsgi - Main application entry point for WSGI (used by mod_wsgi)
#
##########################################################################

"""This is the application entry point for Postgres Enterprise Manager."""

import sys
import os

root = os.path.dirname(os.path.realpath(__file__))
if sys.path[0] != root:
    sys.path.insert(0, root)

try:
    import config_distro
except Exception as e:
    print(e)
    pass

import config

##########################################################################
# Support reverse proxying
##########################################################################
class ReverseProxied():
    def __init__(self, app):
        self.app = app
        # https://werkzeug.palletsprojects.com/en/0.15.x/middleware/proxy_fix
        try:
            from werkzeug.middleware.proxy_fix import ProxyFix
            self.app = ProxyFix(app,
                                x_for=config.PROXY_X_FOR_COUNT,
                                x_proto=config.PROXY_X_PROTO_COUNT,
                                x_host=config.PROXY_X_HOST_COUNT,
                                x_port=config.PROXY_X_PORT_COUNT,
                                x_prefix=config.PROXY_X_PREFIX_COUNT
                                )
        except ImportError:
            pass

    def __call__(self, environ, start_response):
        script_name = environ.get("HTTP_X_SCRIPT_NAME", "")
        if script_name:
            environ["SCRIPT_NAME"] = script_name
            path_info = environ["PATH_INFO"]
            if path_info.startswith(script_name):
                environ["PATH_INFO"] = path_info[len(script_name):]
        scheme = environ.get("HTTP_X_SCHEME", "")
        if scheme:
            environ["wsgi.url_scheme"] = scheme
        return self.app(environ, start_response)

#########################################################################
# Sanity Checks
#########################################################################

# Check if the database exists. If it does not, create it.
if not os.path.isfile(config.SQLITE_PATH):
    def which(program, paths):
        def is_exe(fpath):
            return os.path.exists(fpath) and os.access(fpath, os.X_OK)

        for path in paths:
            if not os.path.isdir(path):
                continue
            exe_file = os.path.join(path, program)
            if is_exe(exe_file):
                return exe_file
        return None

    setup = os.path.join(
        os.path.dirname(os.path.realpath(__file__)), 'setup.py'
    )
    paths = sys.path[:]
    interpreter = None

    if os.name == 'nt':
        paths.insert(0, os.path.join(sys.prefix, 'Scripts'))
        paths.insert(0, os.path.join(sys.prefix))

        interpreter = which('pythonw.exe', paths)
        if interpreter is None:
            interpreter = which('python.exe', paths)
    else:
        paths.insert(0, os.path.join(sys.prefix, 'bin'))
        python_binary_name = 'python{0}'.format(sys.version_info[0]) \
            if sys.version_info[0] >= 3 else 'python'
        interpreter = which(python_binary_name, paths)
    setattr(config, 'PYTHON_INTERPRETER', interpreter)

    import subprocess

    p = subprocess.Popen(
        [interpreter, setup, 'setup-db'], stdout=subprocess.PIPE, stderr=subprocess.PIPE
    )
    p.wait()

    out = ''
    for o in p.stdout:
        out += o.decode('utf-8')
    print('Stdout (setup):\n{0}'.format(out))
    out = ''
    for o in p.stderr:
        out += o.decode('utf-8')
    print('Stderr (setup):\n{0}'.format(out))
    print('setup completed with the exit-code: {0}'.format(p.returncode))
    print('Continue with the execution of the WSGI Application...')


##########################################################################
# Server starup
##########################################################################

# Create the app!
from pgadmin import create_app
from pgadmin.model import SCHEMA_VERSION

config.SETTINGS_SCHEMA_VERSION = SCHEMA_VERSION

application = create_app()

application.PGADMIN_RUNTIME = False
application.PGADMIN_INT_KEY = ''

if not application.PGADMIN_RUNTIME:
    application.wsgi_app = ReverseProxied(application.wsgi_app)

application.run_before_app_start()
