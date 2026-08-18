
# -*- coding: utf-8 -*-
import os
import sys
import mimetypes
mimetypes.add_type('text/javascript', '.js')


sys.path.insert(0, "C:\\edb\\languagepack\\v3\\Python-3.10\\Lib\\") 
sys.path.insert(0, "C:\\edb\\languagepack\\v3\\Python-3.10\\Lib\\site-packages")
sys.path.insert(0, "C:\\Users\\user\\OneDrive\\Documents\\sams-project-website\\server\\share\\web")
sys.path.insert(0, "C:\\Users\\user\\OneDrive\\Documents\\sams-project-website\\server\\share\\web\\venv\\Lib\\site-packages")


# Languages we support in the UI
LANGUAGES = {'en': 'English'}
DATA_DIR = os.path.realpath(os.path.expanduser('C:/Users/user/OneDrive/DOCUME~1/SAMS-P~1/server/share/storage'))

# Debug mode?
DEBUG = False

LOG_FILE = os.path.join(DATA_DIR, 'pem.log')
DEFAULT_SERVER = '0.0.0.0'
DEFAULT_SERVER_PORT = 5050

MINIFY_PAGE = False

SQLITE_PATH = os.path.join(DATA_DIR, 'pem.db')
SESSION_DB_PATH = os.path.join(DATA_DIR, 'sessions')
STORAGE_DIR = os.path.join(DATA_DIR, 'storage')

SESSION_COOKIE_NAME = 'pem28fa7b9d3c68'
UPGRADE_CHECK_ENABLED = False

DEFAULT_BINARY_PATHS = {'pg': '',  'ppas': ''}

##########################################################################
# PEM Backend database server settings
##########################################################################
PEM_DB_HOST = '127.0.0.1'
PEM_DB_NAME = 'pem'
PEM_DB_PORT = '5432'
