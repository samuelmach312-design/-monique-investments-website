#############################################################################
#
# Postgres Enterprise Manager
#
# Copyright (C) 2015 - 2025, EnterpriseDB Corporation. All rights reserved.
#
# web/pglogexp_charts.py - PgLogExpert Chart
#
#############################################################################

"""Log analysis expert utils package"""
import os
import codecs


CSS_GENERATED_DIR_PATH = os.path.realpath('{}{}'.format(
    os.path.dirname(os.path.realpath(__file__)),
    '/../../../../static/js/generated')
)

JS_GENERATED_DIR_PATH = os.path.realpath('{}{}'.format(
    os.path.dirname(os.path.realpath(__file__)),
    '/../../../static/js/generated/reports')
)

CSS_files = [
    os.path.join(CSS_GENERATED_DIR_PATH, 'style.css'),
    os.path.join(CSS_GENERATED_DIR_PATH, 'pgadmin.css'),
    os.path.join(CSS_GENERATED_DIR_PATH, 'pem.dashboard.bundle.css'),
]

JS_files = [
    os.path.join(JS_GENERATED_DIR_PATH, 'pglog_expert.js'),
]


def read_file(file):
    content = ''
    if os.path.isfile(file):
        with codecs.open(file, "r", "utf-8") as f:
            content = f.read()
    return content


def get_bundled_css():
    """
    Returns  bundled stylesheets used for report
    """
    css_content = []
    for file in CSS_files:
        css_content.append(read_file(file))
    return "\n".join(css_content)


def get_bundled_js():
    """
    Returns bundled JS used for report
    """
    js_content = []
    for file in JS_files:
        js_content.append(read_file(file))

    return "".join(js_content)
